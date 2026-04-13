#!/bin/bash
# Ralph Loop Orchestrator - parallel task execution with git worktrees
# Usage: ./run_ralph.sh [--parallel N] [--max-iterations N] [--no-pr] [--tool claude|amp]
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config if exists (can override PRD_DIR, STORIES_FIELD, INSTALL_CMD)
CONFIG_FILE="$SCRIPT_DIR/ralph.config"
PRD_DIR="$SCRIPT_DIR"
STORIES_FIELD=""
INSTALL_CMD="npm install --ignore-scripts --no-audit --no-fund"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

PRD="$PRD_DIR/prd.json"
WORKTREE_BASE="$REPO_ROOT/.worktrees"
LOG_DIR="$SCRIPT_DIR/logs"
LOCK_DIR="$REPO_ROOT/.ralph-locks"

# Auto-detect stories field if not set in config
if [ -z "$STORIES_FIELD" ] && [ -f "$PRD" ]; then
  if jq -e '.stories' "$PRD" &>/dev/null; then
    STORIES_FIELD="stories"
  elif jq -e '.userStories' "$PRD" &>/dev/null; then
    STORIES_FIELD="userStories"
  else
    STORIES_FIELD="stories"
  fi
elif [ -z "$STORIES_FIELD" ]; then
  STORIES_FIELD="stories"
fi

# Defaults
PARALLEL=2
MAX_ITERATIONS=50
MAX_RETRIES=2
CREATE_PR=true
TOOL="claude"
MODEL="opus"  # opus | sonnet | haiku
BASE_BRANCH="main"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --parallel|-p)   PARALLEL="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    --max-retries)   MAX_RETRIES="$2"; shift 2 ;;
    --no-pr)         CREATE_PR=false; shift ;;
    --tool)          TOOL="$2"; shift 2 ;;
    --model|-m)      MODEL="$2"; shift 2 ;;
    --base)          BASE_BRANCH="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./run_ralph.sh [--parallel N] [--max-iterations N] [--max-retries N] [--no-pr] [--tool claude|amp] [--base main]"
      echo ""
      echo "  --parallel N      Run N tasks in parallel (default: 2)"
      echo "  --max-iterations  Max total iterations (default: 50)"
      echo "  --max-retries N   Max retries per failed task (default: 2)"
      echo "  --no-pr           Skip PR creation, merge directly"
      echo "  --tool            claude or amp (default: claude)"
      echo "  --model, -m       Claude model: opus, sonnet, haiku (default: opus)"
      echo "  --base            Base branch (default: main)"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

FAILED_REPORT="$LOG_DIR/failed_report.json"

mkdir -p "$LOG_DIR" "$LOCK_DIR" "$WORKTREE_BASE"

# Initialize empty report
echo '[]' > "$FAILED_REPORT"

# Retry tracking: RETRIES[task_id]=count
declare -A RETRIES

# ============================================================================
# Colors & Symbols
# ============================================================================
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BMAGENTA='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'
BG_BLUE='\033[44m'
BG_YELLOW='\033[43m'

SCRIPT_START=$(date +%s)

# Task title cache
declare -A TASK_TITLES
cache_task_titles() {
  while IFS=$'\t' read -r id title; do
    TASK_TITLES["$id"]="$title"
  done < <(jq -r ".${STORIES_FIELD}[] | [.id, .title] | @tsv" "$PRD" 2>/dev/null)
}
cache_task_titles

task_title() {
  echo "${TASK_TITLES[$1]:-$1}"
}

elapsed_since() {
  local start=$1
  local now
  now=$(date +%s)
  local diff=$(( now - start ))
  if [ $diff -ge 3600 ]; then
    printf '%dh%02dm%02ds' $(( diff / 3600 )) $(( (diff % 3600) / 60 )) $(( diff % 60 ))
  else
    printf '%dm%02ds' $(( diff / 60 )) $(( diff % 60 ))
  fi
}

progress_bar() {
  local completed=$1
  local total=$2
  local width=30
  local filled=0
  if [ "$total" -gt 0 ]; then
    filled=$(( completed * width / total ))
  fi
  local empty=$(( width - filled ))
  local pct=0
  if [ "$total" -gt 0 ]; then
    pct=$(( completed * 100 / total ))
  fi
  printf "${BGREEN}"
  for ((pb_i=0; pb_i<filled; pb_i++)); do printf '#'; done
  printf "${DIM}"
  for ((pb_i=0; pb_i<empty; pb_i++)); do printf '-'; done
  printf "${RST} ${BOLD}%3d%%${RST}" "$pct"
}

# Spinner for background waits
SPINNER_PID=""
start_spinner() {
  local msg="$1"
  (
    local frames=('|' '/' '-' '\')
    local i=0
    while true; do
      printf "\r  ${CYAN}%s${RST} %s " "${frames[$i]}" "$msg" >&2
      i=$(( (i + 1) % ${#frames[@]} ))
      sleep 0.12
    done
  ) &
  SPINNER_PID=$!
  disown "$SPINNER_PID" 2>/dev/null
}

stop_spinner() {
  if [ -n "$SPINNER_PID" ]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf "\r\033[K" >&2
  fi
}

# ============================================================================
# Logging helpers
# ============================================================================
_ts() { printf "${DIM}[%s]${RST}" "$(date '+%H:%M:%S')"; }

log()       { echo -e "$(_ts) $*"; }
log_info()  { echo -e "$(_ts) ${CYAN}*${RST}  $*"; }
log_ok()    { echo -e "$(_ts) ${BGREEN}OK${RST} $*"; }
log_warn()  { echo -e "$(_ts) ${BYELLOW}!!${RST} $*"; }
log_fail()  { echo -e "$(_ts) ${BRED}FAIL${RST} $*"; }
log_step()  { echo -e "$(_ts) ${BBLUE}->${RST} $*"; }
log_task()  {
  local tid="$1"; shift
  local ttl
  ttl=$(task_title "$tid")
  echo -e "$(_ts) ${BMAGENTA}[$tid]${RST} ${DIM}$ttl${RST}  $*"
}

# Horizontal rule
hr() {
  local char="${1:-=}"
  local color="${2:-$DIM}"
  printf "${color}"
  printf '%*s' 60 '' | tr ' ' "$char"
  printf "${RST}\n"
}

# ============================================================================
# Core helpers
# ============================================================================

report_failure() {
  local task_id="$1"
  local attempt="$2"
  local max="$3"
  local t_title
  t_title=$(jq -r ".${STORIES_FIELD}[] | select(.id == \"$task_id\") | .title" "$PRD")
  local logfile="$LOG_DIR/${task_id}.log"
  local last_lines=""
  if [ -f "$logfile" ]; then
    last_lines=$(tail -20 "$logfile" | jq -Rs .)
  else
    last_lines='""'
  fi

  local tmp="$FAILED_REPORT.tmp.$$"
  jq --arg id "$task_id" \
     --arg title "$t_title" \
     --argjson attempt "$attempt" \
     --argjson max "$max" \
     --arg time "$(date -Iseconds)" \
     --arg log "$logfile" \
     --argjson tail "$last_lines" \
     '. |= map(select(.id != $id)) + [{
       id: $id,
       title: $title,
       attempt: $attempt,
       max_retries: $max,
       gave_up: ($attempt > $max),
       timestamp: $time,
       logfile: $log,
       last_output: $tail
     }]' "$FAILED_REPORT" > "$tmp" && mv "$tmp" "$FAILED_REPORT"
}

get_pending_tasks() {
  local min_priority
  min_priority=$(jq "[.${STORIES_FIELD}[] | select(.passes == false) | .priority] | min // empty" "$PRD" 2>/dev/null)
  if [ -z "$min_priority" ]; then
    echo ""
    return
  fi
  # Return tasks, filtering out those that exhausted retries
  for tid in $(jq -r ".${STORIES_FIELD}[] | select(.passes == false and .priority == $min_priority) | .id" "$PRD"); do
    if [ "${RETRIES[$tid]:-0}" -le "$MAX_RETRIES" ]; then
      echo "$tid"
    fi
  done
}

count_pending() {
  jq "[.${STORIES_FIELD}[] | select(.passes == false)] | length" "$PRD"
}

count_total() {
  jq "[.${STORIES_FIELD}[]] | length" "$PRD"
}

mark_done() {
  local task_id="$1"
  local tmp="$PRD.tmp.$$"
  jq "(.${STORIES_FIELD}[] | select(.id == \"$task_id\") | .passes) = true" "$PRD" > "$tmp" && mv "$tmp" "$PRD"
}

branch_name() {
  echo "ralph/$(echo "$1" | tr '[:upper:]' '[:lower:]')"
}

# Simple file-based lock to serialize git setup operations
git_lock()   { while ! mkdir "$LOCK_DIR/git.lock" 2>/dev/null; do sleep 0.2; done; }
git_unlock() { rmdir "$LOCK_DIR/git.lock" 2>/dev/null || true; }

# ============================================================================
# Worker: runs one task in a worktree
# ============================================================================

run_worker() {
  local task_id="$1"
  local branch
  branch=$(branch_name "$task_id")
  local worktree_dir="$WORKTREE_BASE/$task_id"
  local logfile="$LOG_DIR/${task_id}.log"
  local worker_start
  worker_start=$(date +%s)

  log_task "$task_id" "${BBLUE}Starting${RST} -> branch: ${CYAN}$branch${RST}"

  # Serialize git setup (branch + worktree creation)
  git_lock

  cd "$REPO_ROOT"
  git branch "$branch" "$BASE_BRANCH" 2>/dev/null || true

  if [ -d "$worktree_dir" ]; then
    git worktree remove "$worktree_dir" --force 2>/dev/null || rm -rf "$worktree_dir"
  fi
  git worktree add "$worktree_dir" "$branch"

  git_unlock

  # Install dependencies in the worktree
  cd "$worktree_dir"
  log_task "$task_id" "${CYAN}Installing dependencies...${RST}"
  eval "$INSTALL_CMD" > "$logfile.npm" 2>&1 || {
    log_task "$task_id" "${BYELLOW}Dependency install failed (check $logfile.npm)${RST}"
  }

  # Run claude in worktree
  log_task "$task_id" "${BCYAN}Running $TOOL${RST} in worktree..."

  local exit_code=0
  if [[ "$TOOL" == "claude" ]]; then
    RALPH_TASK_ID="$task_id" stdbuf -oL claude \
      --model "$MODEL" \
      --dangerously-skip-permissions \
      --print \
      -p "You are Ralph, an autonomous coding agent. Read scripts/ralph/CLAUDE.md and follow ALL instructions there. Your assigned task is: $task_id. Do NOT work on any other task. The project PRD is at prd.json in the repo root. You are already on the correct branch - do NOT switch branches. After implementing, commit your changes." \
      2>&1 | tee "$logfile" || exit_code=$?
  else
    RALPH_TASK_ID="$task_id" cat "$SCRIPT_DIR/CLAUDE.md" | amp --dangerously-allow-all \
      > "$logfile" 2>&1 || exit_code=$?
  fi

  if [ $exit_code -ne 0 ]; then
    log_task "$task_id" "${BYELLOW}!!${RST} $TOOL exited with code ${BRED}$exit_code${RST} (check $logfile)"
  fi

  # Check if there are any commits on this branch beyond base
  cd "$worktree_dir"
  local commits_ahead
  commits_ahead=$(git rev-list "$BASE_BRANCH".."$branch" --count 2>/dev/null || echo "0")

  if [ "$commits_ahead" -eq 0 ]; then
    if [ -n "$(git status --porcelain)" ]; then
      git add -A
      git commit -m "feat: $task_id - automated implementation" || true
      commits_ahead=$(git rev-list "$BASE_BRANCH".."$branch" --count 2>/dev/null || echo "0")
    fi
  fi

  if [ "$commits_ahead" -eq 0 ]; then
    log_task "$task_id" "${YELLOW}No changes produced - skipping${RST}"
    git_lock
    cd "$REPO_ROOT"
    git worktree remove "$worktree_dir" --force 2>/dev/null || true
    git branch -D "$branch" 2>/dev/null || true
    git_unlock
    return 1
  fi

  # Push branch
  cd "$worktree_dir"
  git push -u origin "$branch" --force-with-lease 2>/dev/null || git push -u origin "$branch" || true
  log_task "$task_id" "${GREEN}Pushed${RST} ${BWHITE}$commits_ahead${RST} commit(s) to ${CYAN}$branch${RST}"

  # Create PR
  if [ "$CREATE_PR" = true ]; then
    local t_title
    t_title=$(jq -r ".${STORIES_FIELD}[] | select(.id == \"$task_id\") | .title" "$PRD")
    gh pr create \
      --title "feat: $task_id - $t_title" \
      --body "Automated by Ralph Loop. Task: $task_id" \
      --base "$BASE_BRANCH" \
      --head "$branch" 2>/dev/null || log_task "$task_id" "${YELLOW}PR already exists or creation failed${RST}"
  fi

  # Cleanup worktree (keep branch for merge)
  git_lock
  cd "$REPO_ROOT"
  git worktree remove "$worktree_dir" --force 2>/dev/null || true
  git_unlock

  local elapsed
  elapsed=$(elapsed_since "$worker_start")
  log_task "$task_id" "${BGREEN}Done${RST} ${DIM}($elapsed)${RST}"
  return 0
}

# ============================================================================
# Merge diff box - shows changes after each merge in a colored frame
# ============================================================================

print_merge_box() {
  local task_id="$1"
  local branch="$2"
  local merge_type="$3"  # "clean" or "conflict"

  local t_title
  t_title=$(task_title "$task_id")

  # Get commit messages from the merged branch (skip merge commit itself)
  local commit_msgs
  commit_msgs=$(git log HEAD~1..HEAD --no-merges --format='%s' 2>/dev/null || true)
  if [ -z "$commit_msgs" ]; then
    commit_msgs=$(git log HEAD^2 --not HEAD^1 --format='%s' 2>/dev/null | head -5 || true)
  fi

  # Extract ralph progress summary for this task from progress.txt
  local progress_file="$SCRIPT_DIR/progress.txt"
  local ralph_summary=""
  if [ -f "$progress_file" ]; then
    ralph_summary=$(awk -v tid="$task_id" '
      BEGIN { found=0 }
      /^## / && index($0, tid) { found=1; next }
      found && /^## / { exit }
      found && /^---/ { exit }
      found && /^- \*\*Learnings/ { exit }
      found && /^- Files changed/ { exit }
      found && /^- / { print }
    ' "$progress_file" | head -8)
  fi

  # Shortstat summary
  local shortstat
  shortstat=$(git diff --shortstat HEAD~1 HEAD -- . ':!prd.json' 2>/dev/null || true)

  # PRD task priority
  local priority
  priority=$(jq -r ".${STORIES_FIELD}[] | select(.id == \"$task_id\") | .priority" "$PRD" 2>/dev/null || echo "?")

  # Box color based on merge type
  local box_color="$GREEN"
  local status_label="${BGREEN}MERGED${RST}"
  if [ "$merge_type" = "conflict" ]; then
    box_color="$YELLOW"
    status_label="${BYELLOW}MERGED (conflicts resolved)${RST}"
  fi

  local box_w=70
  local inner_w=$(( box_w - 6 ))

  echo ""
  # Top border
  printf "    ${box_color}+"; printf '%*s' "$((box_w - 2))" '' | tr ' ' '-'; printf "+${RST}\n"

  # Status + Task ID + priority
  printf "    ${box_color}|${RST} %b  ${BMAGENTA}%s${RST}  ${DIM}(priority %s)${RST}%*s${box_color}|${RST}\n" \
    "$status_label" "$task_id" "$priority" "1" ""

  # Task title
  printf "    ${box_color}|${RST} ${BWHITE}%s${RST}%*s${box_color}|${RST}\n" \
    "$t_title" "1" ""

  # Separator
  printf "    ${box_color}|"; printf '%*s' "$((box_w - 2))" '' | tr ' ' '-'; printf "|${RST}\n"

  # Ralph progress summary
  if [ -n "$ralph_summary" ]; then
    printf "    ${box_color}|${RST} ${BOLD}What was done:${RST}%*s${box_color}|${RST}\n" "1" ""
    while IFS= read -r sline; do
      [ -z "$sline" ] && continue
      # Strip leading "- "
      sline="${sline#- }"
      if [ ${#sline} -gt $inner_w ]; then
        sline="${sline:0:$((inner_w - 3))}..."
      fi
      printf "    ${box_color}|${RST}   ${CYAN}%s${RST}%*s${box_color}|${RST}\n" "$sline" "1" ""
    done <<< "$ralph_summary"
  fi

  # Commit messages (only if different from summary / as fallback)
  if [ -n "$commit_msgs" ]; then
    printf "    ${box_color}|"; printf '%*s' "$((box_w - 2))" '' | tr ' ' '-'; printf "|${RST}\n"
    printf "    ${box_color}|${RST} ${BOLD}Commits:${RST}%*s${box_color}|${RST}\n" "1" ""
    while IFS= read -r msg; do
      [ -z "$msg" ] && continue
      if [ ${#msg} -gt $inner_w ]; then
        msg="${msg:0:$((inner_w - 3))}..."
      fi
      printf "    ${box_color}|${RST}   ${DIM}%s${RST}%*s${box_color}|${RST}\n" "$msg" "1" ""
    done <<< "$commit_msgs"
  fi

  # Shortstat line
  if [ -n "$shortstat" ]; then
    local files_n ins_n del_n
    files_n=$(echo "$shortstat" | grep -oP '\d+ file' | grep -oP '\d+' || echo "0")
    ins_n=$(echo "$shortstat" | grep -oP '\d+ insertion' | grep -oP '\d+' || echo "0")
    del_n=$(echo "$shortstat" | grep -oP '\d+ deletion' | grep -oP '\d+' || echo "0")

    printf "    ${box_color}|"; printf '%*s' "$((box_w - 2))" '' | tr ' ' '-'; printf "|${RST}\n"
    printf "    ${box_color}|${RST} ${DIM}Stats:${RST} ${BWHITE}%s${RST} file(s)  ${BGREEN}+%s${RST}  ${BRED}-%s${RST}%*s${box_color}|${RST}\n" \
      "$files_n" "$ins_n" "$del_n" "1" ""
  fi

  # Bottom border
  printf "    ${box_color}+"; printf '%*s' "$((box_w - 2))" '' | tr ' ' '-'; printf "+${RST}\n"
  echo ""
}

# ============================================================================
# Merge: merge completed branches back to base
# ============================================================================

merge_tasks() {
  local tasks=("$@")
  echo ""
  hr "-" "$BLUE"
  log_step "${BBLUE}Merging ${#tasks[@]} branch(es) -> $BASE_BRANCH${RST}"
  hr "-" "$BLUE"

  cd "$REPO_ROOT"
  git checkout "$BASE_BRANCH"
  git pull --rebase origin "$BASE_BRANCH" 2>/dev/null || true

  for task_id in "${tasks[@]}"; do
    local branch
    branch=$(branch_name "$task_id")

    if ! git rev-parse --verify "$branch" &>/dev/null; then
      log_task "$task_id" "${YELLOW}Branch $branch not found - skipping merge${RST}"
      continue
    fi

    log_task "$task_id" "${BLUE}Merging${RST} ${CYAN}$branch${RST} -> ${CYAN}$BASE_BRANCH${RST}"

    # --no-ff handles diverging branches (no fast-forward-only errors)
    if git merge --no-ff --no-edit "$branch" 2>&1; then
      log_task "$task_id" "${BGREEN}Merged cleanly${RST}"
      print_merge_box "$task_id" "$branch" "clean"
    else
      log_task "$task_id" "${BYELLOW}Conflict detected${RST} - auto-resolving..."

      # prd.json: always keep ours (base) - orchestrator manages this file
      git checkout --ours prd.json 2>/dev/null || true

      # Everything else: accept theirs (feature branch wins)
      git diff --name-only --diff-filter=U 2>/dev/null | grep -v prd.json | while read -r f; do
        git checkout --theirs "$f" 2>/dev/null || true
      done

      # package-lock.json: regenerate if conflicted (--theirs often breaks it)
      if git diff --name-only --diff-filter=U 2>/dev/null | grep -q "package-lock.json"; then
        git checkout --theirs package-lock.json 2>/dev/null || true
      fi

      git add -A
      git commit --no-edit -m "merge: $task_id with auto-resolved conflicts" || true
      log_task "$task_id" "${GREEN}Conflict resolved${RST}"
      print_merge_box "$task_id" "$branch" "conflict"
    fi

    # Mark done
    mark_done "$task_id"
    git add prd.json
    git commit -m "chore: mark $task_id done" 2>/dev/null || true

    # Close PR
    if [ "$CREATE_PR" = true ]; then
      local pr_number
      pr_number=$(gh pr list --head "$branch" --json number -q '.[0].number' 2>/dev/null || echo "")
      if [ -n "$pr_number" ]; then
        gh pr close "$pr_number" --comment "Merged by Ralph orchestrator" 2>/dev/null || true
      fi
    fi

    # Cleanup branch
    git branch -D "$branch" 2>/dev/null || true
    git push origin --delete "$branch" 2>/dev/null || true
  done

  git push origin "$BASE_BRANCH" || true
  log_ok "${GREEN}Pushed to ${CYAN}$BASE_BRANCH${RST}"
}

# ============================================================================
# Main Loop
# ============================================================================

total_tasks=$(count_total)

echo ""
echo -e "${BBLUE}  ____       _       _     ${RST}"
echo -e "${BBLUE} |  _ \\ __ _| |_ __ | |__  ${RST}"
echo -e "${BBLUE} | |_) / _\` | | '_ \\| '_ \\ ${RST}"
echo -e "${BBLUE} |  _ < (_| | | |_) | | | |${RST}"
echo -e "${BBLUE} |_| \\_\\__,_|_| .__/|_| |_|${RST}"
echo -e "${BBLUE}              |_|           ${RST}${DIM}Loop Orchestrator${RST}"
echo ""
hr "=" "$BBLUE"
echo -e "  ${BOLD}Parallel:${RST}  ${BCYAN}$PARALLEL${RST} workers"
echo -e "  ${BOLD}Tool:${RST}      ${BCYAN}$TOOL${RST} (model: ${BCYAN}$MODEL${RST})"
echo -e "  ${BOLD}PRs:${RST}       $([ "$CREATE_PR" = true ] && echo -e "${BGREEN}enabled${RST}" || echo -e "${YELLOW}disabled${RST}")"
echo -e "  ${BOLD}Base:${RST}      ${CYAN}$BASE_BRANCH${RST}"
echo -e "  ${BOLD}Tasks:${RST}     ${BWHITE}$total_tasks${RST} total in PRD"
echo -e "  ${BOLD}Max iter:${RST}  ${DIM}$MAX_ITERATIONS${RST}"
echo -e "  ${BOLD}Max retry:${RST} ${DIM}$MAX_RETRIES${RST} per task"
hr "=" "$BBLUE"
echo ""

cd "$REPO_ROOT"
git checkout "$BASE_BRANCH"
git pull --rebase origin "$BASE_BRANCH" 2>/dev/null || true

# Cleanup stale locks
rm -rf "$LOCK_DIR/git.lock" 2>/dev/null

batch_num=0
iteration=0
while [ $iteration -lt $MAX_ITERATIONS ]; do
  # Refresh title cache and counts each batch
  cache_task_titles
  pending=$(count_pending)
  completed=$(( total_tasks - pending ))

  if [ "$pending" -eq 0 ]; then
    echo ""
    hr "=" "$BGREEN"
    echo -e "  ${BGREEN}ALL TASKS DONE!${RST}  ($iteration iterations used, $(elapsed_since $SCRIPT_START) elapsed)"
    hr "=" "$BGREEN"
    echo ""
    echo -e "  $(progress_bar "$total_tasks" "$total_tasks")"
    echo ""
    gave_up_count=$(jq '[.[] | select(.gave_up == true)] | length' "$FAILED_REPORT")
    if [ "$gave_up_count" -gt 0 ]; then
      log_warn "${YELLOW}$gave_up_count task(s) had failures (later completed on retry)${RST}"
      log_info "Full failure history: ${DIM}$FAILED_REPORT${RST}"
    fi
    rm -rf "$LOCK_DIR"
    exit 0
  fi

  batch_num=$(( batch_num + 1 ))
  echo ""
  hr "-" "$MAGENTA"
  echo -e "  ${BMAGENTA}BATCH $batch_num${RST}  ${DIM}|${RST}  ${BWHITE}$pending${RST} pending  ${DIM}|${RST}  ${BWHITE}$completed${RST}/${BWHITE}$total_tasks${RST} done  ${DIM}|${RST}  elapsed: ${DIM}$(elapsed_since $SCRIPT_START)${RST}"
  echo -e "  $(progress_bar "$completed" "$total_tasks")"
  hr "-" "$MAGENTA"

  mapfile -t batch < <(get_pending_tasks)

  if [ ${#batch[@]} -eq 0 ]; then
    log_warn "No pending tasks found (all exhausted retries?)"
    exit 0
  fi

  # Cap to PARALLEL limit
  run_batch=("${batch[@]:0:$PARALLEL}")

  echo ""
  log_step "${BOLD}Launching ${BCYAN}${#run_batch[@]}${RST}${BOLD} worker(s):${RST}"
  for tid in "${run_batch[@]}"; do
    echo -e "          ${BMAGENTA}[$tid]${RST} ${DIM}$(task_title "$tid")${RST}"
  done
  echo ""

  # Launch workers
  pids=()
  local_batch_start=$(date +%s)
  for task_id in "${run_batch[@]}"; do
    run_worker "$task_id" &
    pids+=($!)
    iteration=$(( iteration + 1 ))
  done

  # Wait for all workers
  start_spinner "Waiting for ${#run_batch[@]} worker(s)..."
  failed=()
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      failed+=("${run_batch[$i]}")
    fi
  done
  stop_spinner

  echo ""
  batch_elapsed=$(elapsed_since "$local_batch_start")

  # Report results
  succeeded=$(( ${#run_batch[@]} - ${#failed[@]} ))
  if [ "$succeeded" -gt 0 ]; then
    log_ok "${BGREEN}$succeeded${RST} task(s) succeeded ${DIM}($batch_elapsed)${RST}"
  fi

  if [ ${#failed[@]} -gt 0 ]; then
    log_fail "${BRED}${#failed[@]}${RST} task(s) failed"
    for f in "${failed[@]}"; do
      RETRIES[$f]=$(( ${RETRIES[$f]:-0} + 1 ))
      report_failure "$f" "${RETRIES[$f]}" "$MAX_RETRIES"
      if [ "${RETRIES[$f]}" -le "$MAX_RETRIES" ]; then
        log_task "$f" "${YELLOW}Will retry${RST} (attempt ${BWHITE}${RETRIES[$f]}${RST}/${MAX_RETRIES})"
      else
        log_task "$f" "${BRED}GAVE UP${RST} after ${MAX_RETRIES} retries"
      fi
    done
  fi

  # Build merge list (exclude failed)
  merge_list=()
  for task_id in "${run_batch[@]}"; do
    is_failed=false
    for f in "${failed[@]}"; do
      if [ "$task_id" = "$f" ]; then is_failed=true; break; fi
    done
    if [ "$is_failed" = false ]; then
      merge_list+=("$task_id")
    fi
  done

  # Merge successful tasks
  if [ ${#merge_list[@]} -gt 0 ]; then
    merge_tasks "${merge_list[@]}"
  fi
done

echo ""
hr "=" "$BRED"
echo -e "  ${BRED}Reached max iterations ($MAX_ITERATIONS).${RST}  $(count_pending) tasks remaining."
echo -e "  Elapsed: ${DIM}$(elapsed_since $SCRIPT_START)${RST}"
hr "=" "$BRED"

# Final summary
gave_up_count=$(jq '[.[] | select(.gave_up == true)] | length' "$FAILED_REPORT")
if [ "$gave_up_count" -gt 0 ]; then
  echo ""
  echo -e "  ${BRED}FAILED TASKS: $gave_up_count task(s) gave up${RST}"
  echo -e "  ${DIM}Details: $FAILED_REPORT${RST}"
  echo ""
  jq -r '.[] | select(.gave_up == true) | .id + ": " + .title + " (after " + (.attempt|tostring) + " attempts)"' "$FAILED_REPORT" | while read -r line; do
    echo -e "    ${RED}x${RST} $line"
  done
  echo ""
fi

rm -rf "$LOCK_DIR"
exit 1
