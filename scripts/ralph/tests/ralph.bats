#!/usr/bin/env bats
# Unit tests for ralph.sh helper functions.
# Run:  bats scripts/ralph/tests/ralph.bats

RALPH_SH="$BATS_TEST_DIRNAME/../ralph.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"

setup() {
  TEST_TMP=$(mktemp -d)
  export REPO_ROOT="$TEST_TMP/repo"
  export SCRIPT_DIR="$TEST_TMP/ralph"
  export PRD_DIR="$SCRIPT_DIR"
  mkdir -p "$REPO_ROOT" "$SCRIPT_DIR/logs" "$SCRIPT_DIR/archive" \
           "$REPO_ROOT/.ralph-locks" "$REPO_ROOT/.worktrees"

  # Pre-set STORIES_FIELD so ralph.sh skips its own auto-detect during sourcing.
  # Individual tests that exercise auto-detect unset it before re-sourcing.
  export STORIES_FIELD="stories"
  export RALPH_TEST_MODE=1

  # bats passes its internal test-function name in $@; clear it so ralph.sh's
  # argument parser doesn't choke on it.
  set --
  # shellcheck disable=SC1090
  source "$RALPH_SH"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ---------- Pure functions ----------

@test "branch_name: prefixes ralph/ and lowercases the id" {
  run branch_name "US-001"
  [ "$status" -eq 0 ]
  [ "$output" = "ralph/us-001" ]
}

@test "branch_name: handles mixed case" {
  run branch_name "Fix-Login-Bug"
  [ "$status" -eq 0 ]
  [ "$output" = "ralph/fix-login-bug" ]
}

@test "elapsed_since: formats minutes and seconds under an hour" {
  local start
  start=$(( $(date +%s) - 125 ))
  run elapsed_since "$start"
  [ "$status" -eq 0 ]
  [ "$output" = "2m05s" ]
}

@test "elapsed_since: formats hours when over 3600s" {
  local start
  start=$(( $(date +%s) - 3665 ))
  run elapsed_since "$start"
  [ "$status" -eq 0 ]
  [ "$output" = "1h01m05s" ]
}

# ---------- PRD-reading helpers ----------

@test "count_total: returns full story count" {
  cp "$FIXTURES/prd_basic.json" "$SCRIPT_DIR/prd.json"
  run count_total
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "count_pending: excludes stories with passes=true" {
  cp "$FIXTURES/prd_basic.json" "$SCRIPT_DIR/prd.json"
  run count_pending
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "get_pending_tasks: returns only lowest-priority pending stories" {
  cp "$FIXTURES/prd_basic.json" "$SCRIPT_DIR/prd.json"
  # US-001 is done; US-002/US-003 share priority 2 (lowest pending); US-004 is priority 3
  declare -gA RETRIES=()
  MAX_RETRIES=2
  run get_pending_tasks
  [ "$status" -eq 0 ]
  # Lines may arrive in any order — sort before comparing
  sorted=$(echo "$output" | sort | tr '\n' ' ')
  [ "$sorted" = "US-002 US-003 " ]
}

@test "get_pending_tasks: skips tasks that exhausted their retries" {
  cp "$FIXTURES/prd_basic.json" "$SCRIPT_DIR/prd.json"
  declare -gA RETRIES=(["US-002"]=5)
  MAX_RETRIES=2
  run get_pending_tasks
  [ "$status" -eq 0 ]
  [ "$output" = "US-003" ]
}

@test "mark_done: flips passes=true for the named task" {
  cp "$FIXTURES/prd_basic.json" "$SCRIPT_DIR/prd.json"
  mark_done "US-002"
  result=$(jq -r '.stories[] | select(.id == "US-002") | .passes' "$SCRIPT_DIR/prd.json")
  [ "$result" = "true" ]
  # Other stories unchanged
  untouched=$(jq -r '.stories[] | select(.id == "US-003") | .passes' "$SCRIPT_DIR/prd.json")
  [ "$untouched" = "false" ]
}

# ---------- Progress rotation ----------

@test "rotate_progress: skips when file is under threshold" {
  export PROGRESS_ROTATE_LINES=1000
  cp "$FIXTURES/progress_with_patterns.txt" "$SCRIPT_DIR/progress.txt"
  local before_lines
  before_lines=$(wc -l < "$SCRIPT_DIR/progress.txt")
  rotate_progress
  local after_lines
  after_lines=$(wc -l < "$SCRIPT_DIR/progress.txt")
  [ "$before_lines" = "$after_lines" ]
  # archive dir stays empty
  [ -z "$(ls -A "$SCRIPT_DIR/archive")" ]
}

@test "rotate_progress: preserves Codebase Patterns section across rotation" {
  export PROGRESS_ROTATE_LINES=5
  cp "$FIXTURES/progress_with_patterns.txt" "$SCRIPT_DIR/progress.txt"
  rotate_progress
  # Live file must still contain the three pattern lines
  run grep -c '^- Use `sql<number>' "$SCRIPT_DIR/progress.txt"
  [ "$output" = "1" ]
  run grep -c '^- Always use `IF NOT EXISTS`' "$SCRIPT_DIR/progress.txt"
  [ "$output" = "1" ]
  run grep -c '^- Export types from actions.ts' "$SCRIPT_DIR/progress.txt"
  [ "$output" = "1" ]
  # Story-specific sections should be gone from the live file
  run grep -c 'US-001' "$SCRIPT_DIR/progress.txt"
  [ "$output" = "0" ]
  # Archive should have been created
  archived=$(ls "$SCRIPT_DIR/archive" | wc -l)
  [ "$archived" = "1" ]
}

# ---------- STORIES_FIELD validation & auto-detect ----------

@test "STORIES_FIELD validation: rejects values with shell metacharacters" {
  # ralph.sh sources ralph.config; a malicious value there must be rejected.
  cat > "$SCRIPT_DIR/ralph.config" <<'EOF'
STORIES_FIELD="stories; rm -rf /"
EOF
  run bash -c "
    export REPO_ROOT='$REPO_ROOT'
    export SCRIPT_DIR='$SCRIPT_DIR'
    export RALPH_TEST_MODE=1
    set --
    source '$RALPH_SH'
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid STORIES_FIELD"* ]]
}

@test "MODE validation: rejects unknown mode values" {
  run bash -c "
    export REPO_ROOT='$REPO_ROOT'
    export SCRIPT_DIR='$SCRIPT_DIR'
    set --
    bash '$RALPH_SH' --mode frobnicate
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --mode"* ]]
}

@test "STORIES_FIELD auto-detect: picks userStories when only that field exists" {
  cp "$FIXTURES/prd_user_stories.json" "$SCRIPT_DIR/prd.json"
  run bash -c "
    export REPO_ROOT='$REPO_ROOT'
    export SCRIPT_DIR='$SCRIPT_DIR'
    export PRD_DIR='$SCRIPT_DIR'
    unset STORIES_FIELD
    export RALPH_TEST_MODE=1
    source '$RALPH_SH'
    echo \"\$STORIES_FIELD\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"userStories"* ]]
}
