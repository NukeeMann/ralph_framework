# Ralph Framework

Autonomous AI coding agent loop for executing projects from PRDs (Product Requirements Documents).

Ralph reads a PRD with prioritized user stories, picks one story per iteration, implements it, runs quality checks, commits, and moves to the next. It supports parallel execution with git worktrees.

## How It Works

1. Use the `prd_init` skill in Claude Code — it asks up to 10 clarifying questions and writes `prd.json` directly
2. Ralph picks the highest-priority incomplete stories
3. Spawns parallel Claude Code agents in git worktrees to implement them
4. Agents commit changes, log progress, and exit
5. If `VALIDATE_CMD` is set, Ralph runs build/test validation before allowing merge
6. Ralph merges completed branches (rejecting real source conflicts for retry), picks next stories, and repeats
7. Mid-project: use `prd_append` to triage bugs and new features into the existing `prd.json`

## Quick Start

### Install into your project

```bash
# From the ralph_framework repo
./init.sh /path/to/your/project
```

This copies all ralph scripts and skills into `your-project/scripts/ralph/`.

### Create a PRD

Open Claude Code in your project and type:

> "Chcę zbudować aplikację X" / "I want to build X"

The `prd_init` skill will ask up to 10 clarifying questions (problem, users, stack, auth, scope, success metrics, etc.), show you the proposed stories for review, and write `prd.json` directly — no intermediate markdown file.

**`prd.json` format:**

```json
{
  "project": "MyApp",
  "branchName": "ralph/my-feature",
  "description": "Feature description",
  "stories": [
    {
      "id": "US-001",
      "title": "Add database schema",
      "description": "As a developer, I need the data model.",
      "acceptanceCriteria": ["Migration runs", "Typecheck passes"],
      "priority": 1,
      "passes": false,
      "notes": "",
      "tags": []
    }
  ]
}
```

Add `"ui"` to a story's `tags` array to enable Playwright browser testing for that task. Without the tag, browser testing is skipped and the Chromium runtime is not installed.

### Configure (optional)

Edit `scripts/ralph/ralph.config`:

```bash
# Put prd.json in repo root instead of scripts/ralph/
PRD_DIR="$REPO_ROOT"

# If your PRD uses "userStories" instead of "stories"
STORIES_FIELD="userStories"

# For non-npm projects
INSTALL_CMD="pip install -r requirements.txt"

# Validate after agent commits, before merge
VALIDATE_CMD="npm run build && npm test"
```

### Run

```bash
./scripts/ralph/ralph.sh --parallel 2 --model opus
```

### Manual skill installation (optional)

Skills live in `scripts/ralph/skills/` per project. `init.sh` does **not** install them into your user-scope Claude Code (`~/.claude/`). If you want skills like `prd_init` / `prd_append` available globally across all projects, copy them yourself:

```bash
mkdir -p ~/.claude/skills
cp -r scripts/ralph/skills/prd_init ~/.claude/skills/
cp -r scripts/ralph/skills/prd_append ~/.claude/skills/
# Restart Claude Code to pick them up.
```

The project-local copies are what Ralph's orchestrator actually invokes during agent runs, so the global copy is only for convenience when using skills interactively.

## Scripts

| Script | Purpose |
|--------|---------|
| `ralph.sh` | Parallel orchestrator with git worktrees, auto-merge, retry logic. |
| `init.sh` | Bootstraps ralph into a new project. |

Ralph merges feature branches directly into the base branch and pushes — it does not open pull requests. Code review happens on the base branch post-factum, not per task.

### Parallel execution caveat

`VALIDATE_CMD` runs **per task, in its own worktree, before merge** — not after. With `--parallel 2+`, two tasks can each pass validation in isolation and then be merged into a base branch where their combined changes break the build. Ralph will not re-run validation on the merged state.

If you run with parallelism > 1, treat your base branch's CI (or a manual `VALIDATE_CMD` after a batch) as the real integration gate. For stricter safety, run `--parallel 1` — then per-task validation is also effectively post-merge validation, since tasks merge sequentially.

## ralph.sh Options

```
--parallel N      Run N tasks in parallel (default: 2)
--max-iterations  Max total iterations (default: 50)
--max-retries N   Max retries per failed task (default: 2)
--model, -m       Claude model: opus, sonnet, haiku (default: opus)
--base            Base branch (default: current branch)
```

## Configuration (ralph.config)

| Variable | Default | Description |
|----------|---------|-------------|
| `PRD_DIR` | `$SCRIPT_DIR` | Directory containing `prd.json` |
| `STORIES_FIELD` | auto-detect | JSON field name: `stories` or `userStories` |
| `INSTALL_CMD` | `npm install ...` | Dependency install command for worktrees |
| `VALIDATE_CMD` | *(empty)* | Command to validate code before merge (e.g. `npm run build && npm test`) |
| `TASK_TIMEOUT_SEC` | `1800` | Per-task timeout in seconds. Agent is killed and the task retried if it exceeds this. |
| `PROGRESS_ROTATE_LINES` | `200` | Rotate `progress.txt` into `archive/` once it grows past this many lines. The `## Codebase Patterns` section is preserved across rotations. |

## Skills

Skills are invoked in Claude Code via slash commands or by describing what you need.

### `prd_init`
**Trigger:** "chcę zbudować", "new project", "create prd", "zaplanuj projekt"

New project from scratch. Asks up to 10 clarifying questions (problem, users, core actions, scope, stack, auth, data, integrations, success metrics, MVP vs full). Shows proposed stories for review before writing. Writes `prd.json` directly — no intermediate `.md` file. Archives previous `prd.json` if switching features.

### `prd_append`
**Trigger:** "mam bugi", "dodaj taski", "found bugs", "lista bugów", "mid-project tasks"

Mid-project triage. Reads the existing `prd.json`, takes a rough list of bugs and/or new features, classifies each item (bug / feature / enhancement), asks clarifying questions per item where needed, then appends properly formatted stories. Never modifies existing stories or completed entries.

- Bug stories automatically get the test-first criterion: *"A failing test reproducing the bug exists before the fix"*
- Priorities are assigned relative to existing stories

### `playwright-skill`
**Trigger:** "test website", "check UI", "take screenshot", "browser test"

Browser automation via Playwright. Auto-detects running dev servers, writes test scripts to `/tmp`, executes via `run.js`. Runs headless in Ralph mode (WSL2).

**Activation is tag-driven:** Ralph runs the skill only when the current task has `"tags": ["ui"]` in `prd.json`. The Chromium runtime (~300MB) is installed lazily on the first UI task, not up-front — backend-only projects never pay the cost. Files touched by a task do **not** trigger browser testing on their own; the tag is the sole switch.

## Directory Structure

```
scripts/ralph/
  ralph.sh              # Parallel orchestrator
  CLAUDE.md             # Agent instructions (read by each iteration)
  ralph.config          # Configuration overrides
  prd.json              # Your project's PRD (generated, not committed)
  progress.txt          # Cumulative progress log (generated, rotated)
  logs/                 # Per-task execution logs, failed_report.json, last_failure snapshots
  archive/              # Rotated progress.txt snapshots (Codebase Patterns preserved)
  skills/
    prd_init/           # New project: questions → prd.json
    prd_append/         # Mid-project: triage bugs/features → append to prd.json
    playwright-skill/   # Browser automation (Playwright)
```

## How Ralph Learns

Each iteration appends to `progress.txt` with:
- What was implemented
- Files changed
- Learnings for future iterations

General patterns get consolidated into a `## Codebase Patterns` section at the top of `progress.txt`, which future iterations read first. This gives Ralph a growing understanding of your codebase across iterations.

When `progress.txt` grows past `PROGRESS_ROTATE_LINES` (default 200), older entries are rotated into `archive/progress-YYYY-MM-DD-HHMM.txt`. The `## Codebase Patterns` section is preserved in the live file so that hard-won knowledge survives rotation.

Ralph also updates nearby `CLAUDE.md` files in directories it modifies, preserving module-specific knowledge for future work.

When validation fails, the last 50 lines of the validation log are saved to `logs/<task_id>.last_failure.txt` and injected into the next retry's prompt so the agent can fix the specific error instead of starting from scratch. The file is cleared after the task succeeds.

## Coding Philosophy

Every spawned agent follows the principles embedded in `CLAUDE.md`:

- **Think Before Coding** — State assumptions in the progress report; on ambiguity pick the conservative interpretation and flag it for the reviewer (agent runs non-interactively, no asking)
- **Simplicity First** — Minimum code that satisfies the story, no speculative abstractions
- **Surgical Changes** — Only modify what the story requires, match existing style
- **Goal-Driven Execution** — Test-first for bugs; put the plan in the commit message and progress report, then execute
