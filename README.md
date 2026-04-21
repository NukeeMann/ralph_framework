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
      "notes": ""
    }
  ]
}
```

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
| `ralph.sh` | Parallel orchestrator with git worktrees, auto-merge, PR creation, retry logic. |
| `init.sh` | Bootstraps ralph into a new project. |

## ralph.sh Options

```
--parallel N      Run N tasks in parallel (default: 2)
--max-iterations  Max total iterations (default: 50)
--max-retries N   Max retries per failed task (default: 2)
--no-pr           Skip PR creation, merge directly
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

### `karpathy_guidelines`
**Trigger:** "karpathy guidelines", "coding philosophy", "coding principles"

Reference for the four behavioral principles applied to every agent iteration: Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution. These are already embedded in `CLAUDE.md` — use this skill for detailed reference or discussion.

### `playwright-skill`
**Trigger:** "test website", "check UI", "take screenshot", "browser test"

Browser automation via Playwright. Auto-detects running dev servers, writes test scripts to `/tmp`, executes via `run.js`. Used automatically by Ralph agents when stories involve UI changes (detected via `ui` tag or HTML/CSS/template changes). Runs headless in Ralph mode (WSL2).

## Directory Structure

```
scripts/ralph/
  ralph.sh              # Parallel orchestrator
  CLAUDE.md             # Agent instructions (read by each iteration)
  ralph.config          # Configuration overrides
  prd.json              # Your project's PRD (generated, not committed)
  progress.txt          # Cumulative progress log (generated)
  logs/                 # Per-task execution logs
  archive/              # Archived previous runs
  skills/
    prd_init/           # New project: questions → prd.json
    prd_append/         # Mid-project: triage bugs/features → append to prd.json
    karpathy-guidelines/  # Coding philosophy reference
    playwright-skill/     # Browser automation (Playwright)
```

## How Ralph Learns

Each iteration appends to `progress.txt` with:
- What was implemented
- Files changed
- Learnings for future iterations

General patterns get consolidated into a `## Codebase Patterns` section at the top of `progress.txt`, which future iterations read first. This gives Ralph a growing understanding of your codebase across iterations.

Ralph also updates nearby `CLAUDE.md` files in directories it modifies, preserving module-specific knowledge for future work.

## Coding Philosophy

Every spawned agent follows the Karpathy guidelines embedded in `CLAUDE.md`:

- **Think Before Coding** — State assumptions, present interpretations, ask when confused
- **Simplicity First** — Minimum code that satisfies the story, no speculative abstractions
- **Surgical Changes** — Only modify what the story requires, match existing style
- **Goal-Driven Execution** — Test-first for bugs, verify each acceptance criterion before committing
