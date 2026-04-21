# Ralph tests

Unit tests for the helper functions in `ralph.sh` — pure functions, PRD reads,
progress rotation, and `STORIES_FIELD` validation/auto-detect. No Claude or git
operations are exercised; those are integration territory.

## Requirements

- [bats-core](https://github.com/bats-core/bats-core)
- `jq` (already required by ralph itself)

Install bats:

```bash
# Debian/Ubuntu
sudo apt install bats

# macOS
brew install bats-core

# From source
git clone https://github.com/bats-core/bats-core.git
cd bats-core && sudo ./install.sh /usr/local
```

## Running

From the repo root:

```bash
bats scripts/ralph/tests/ralph.bats
```

Or a single test:

```bash
bats scripts/ralph/tests/ralph.bats --filter "rotate_progress: preserves"
```

## How it works

`ralph.sh` checks `RALPH_TEST_MODE=1` right before its main loop and `return`s
early when set. Tests source `ralph.sh` with that flag so every helper function
is defined and callable, but no orchestration runs. Path variables
(`REPO_ROOT`, `SCRIPT_DIR`, `PRD_DIR`) are overridable via env — each test
points them at a fresh `mktemp -d` so the live `prd.json` / `progress.txt` /
`logs/` are never touched.

## Adding a test

1. If the helper depends on `prd.json`, copy one of `fixtures/prd_*.json` into
   `$SCRIPT_DIR/prd.json` at the top of your test.
2. Use `run <function> <args>`, then assert on `$status` and `$output`.
3. For tests that need a fresh environment (e.g. `STORIES_FIELD` auto-detect),
   spawn a subshell with `run bash -c '...'` rather than reusing the sourced
   state — sourcing a second time inside the same shell would skip re-running
   initialization.
