# Ralph Framework

Autonomous AI coding agent loop for executing projects from PRDs (Product Requirements Documents).

Ralph reads a PRD with prioritized user stories, picks one story per iteration, implements it, runs quality checks, commits, and moves to the next. It supports both sequential and parallel execution with git worktrees.

## How It Works

1. You write a PRD describing your feature as user stories
2. Convert it to `prd.json` (Ralph's structured format)
3. Ralph picks the highest-priority incomplete story
4. Spawns a fresh AI agent (Claude Code or Amp) to implement it
5. Agent commits changes, logs progress, and exits
6. Ralph picks the next story and repeats
7. Parallel mode runs multiple stories simultaneously in git worktrees

## Quick Start

### Install into your project

```bash
# From the ralph_framework repo
./init.sh /path/to/your/project
```

This copies all ralph scripts into `your-project/scripts/ralph/`.

### Configure

Edit `scripts/ralph/ralph.config`:

```bash
# Put prd.json in repo root instead of scripts/ralph/
PRD_DIR="$REPO_ROOT"

# If your PRD uses "userStories" instead of "stories"
STORIES_FIELD="userStories"

# For non-npm projects
INSTALL_CMD="pip install -r requirements.txt"
```

### Create a PRD

Use the built-in skill or write one manually, then convert to `prd.json`:

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

### Run

```bash
# Single iteration mode (one story at a time)
./scripts/ralph/ralph.sh --tool claude 20

# Parallel orchestrator (multiple stories via git worktrees)
./scripts/ralph/run_ralph.sh --parallel 2 --tool claude --model opus
```

## Scripts

| Script | Purpose |
|--------|---------|
| `ralph.sh` | Single-iteration loop runner. Runs one story per iteration sequentially. |
| `run_ralph.sh` | Parallel orchestrator with git worktrees, auto-merge, PR creation, retry logic. |
| `init.sh` | Bootstraps ralph into a new project. |

## run_ralph.sh Options

```
--parallel N      Run N tasks in parallel (default: 2)
--max-iterations  Max total iterations (default: 50)
--max-retries N   Max retries per failed task (default: 2)
--no-pr           Skip PR creation, merge directly
--tool            claude or amp (default: claude)
--model, -m       Claude model: opus, sonnet, haiku (default: opus)
--base            Base branch (default: main)
```

## Configuration (ralph.config)

| Variable | Default | Description |
|----------|---------|-------------|
| `PRD_DIR` | `$SCRIPT_DIR` | Directory containing `prd.json` |
| `STORIES_FIELD` | auto-detect | JSON field name: `stories` or `userStories` |
| `INSTALL_CMD` | `npm install ...` | Dependency install command for worktrees |

## Skills

### PRD Create (`skills/create/SKILL.md`)
Generates a structured PRD markdown file from a feature description. Asks clarifying questions, then outputs to `tasks/prd-[feature].md`.

### PRD Convert (`skills/convert/SKILL.md`)
Converts a PRD markdown file into the `prd.json` format Ralph needs. Handles story sizing, dependency ordering, and acceptance criteria.

## Directory Structure

```
scripts/ralph/
  ralph.sh          # Single iteration runner
  run_ralph.sh      # Parallel orchestrator
  CLAUDE.md         # Agent instructions (read by each iteration)
  ralph.config      # Configuration overrides
  prd.json          # Your project's PRD (generated, not committed)
  progress.txt      # Cumulative progress log (generated)
  logs/             # Per-task execution logs
  archive/          # Archived previous runs
  skills/
    convert/SKILL.md  # PRD -> prd.json converter
    create/SKILL.md   # PRD generator
```

## How Ralph Learns

Each iteration appends to `progress.txt` with:
- What was implemented
- Files changed
- Learnings for future iterations

General patterns get consolidated into a `## Codebase Patterns` section at the top of `progress.txt`, which future iterations read first. This gives Ralph a growing understanding of your codebase across iterations.

Ralph also updates `CLAUDE.md` files in directories it modifies, preserving knowledge for future work.
