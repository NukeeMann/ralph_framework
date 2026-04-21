#!/bin/bash
# Ralph Framework - Initialize ralph in a new project
# Usage: ./init.sh [target_project_path]
#
# Copies the ralph scripts into your project's scripts/ralph/ directory.
# Run this from the ralph_framework repo, pointing at your project.

set -e

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-.}"
TARGET=$(cd "$TARGET" && pwd)

RALPH_SRC="$FRAMEWORK_DIR/scripts/ralph"
RALPH_DST="$TARGET/scripts/ralph"

if [ ! -d "$TARGET/.git" ]; then
  echo "Warning: $TARGET does not appear to be a git repository."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo "Installing Ralph Framework into: $TARGET"
echo ""

# Create directory structure
mkdir -p "$RALPH_DST/skills/prd_init"
mkdir -p "$RALPH_DST/skills/prd_append"
mkdir -p "$RALPH_DST/skills/playwright-skill"
mkdir -p "$RALPH_DST/logs"
mkdir -p "$RALPH_DST/archive"

# Copy core scripts
cp "$RALPH_SRC/ralph.sh" "$RALPH_DST/ralph.sh"
cp "$RALPH_SRC/CLAUDE.md" "$RALPH_DST/CLAUDE.md"

# Copy config (don't overwrite existing)
if [ ! -f "$RALPH_DST/ralph.config" ]; then
  cp "$RALPH_SRC/ralph.config" "$RALPH_DST/ralph.config"
  echo "  Created ralph.config (edit to customize PRD location, stories field, etc.)"
else
  echo "  ralph.config already exists - skipping (check ralph_framework for updates)"
fi

# Copy skills
cp "$RALPH_SRC/skills/prd_init/SKILL.md" "$RALPH_DST/skills/prd_init/SKILL.md"
cp "$RALPH_SRC/skills/prd_append/SKILL.md" "$RALPH_DST/skills/prd_append/SKILL.md"

# Copy playwright-skill to project (full skill from ralph repo)
PW_SRC="$RALPH_SRC/skills/playwright-skill"
PW_DST="$RALPH_DST/skills/playwright-skill"
mkdir -p "$PW_DST/lib"
cp "$PW_SRC/SKILL.md" "$PW_DST/SKILL.md"
cp "$PW_SRC/API_REFERENCE.md" "$PW_DST/API_REFERENCE.md"
cp "$PW_SRC/run.js" "$PW_DST/run.js"
cp "$PW_SRC/package.json" "$PW_DST/package.json"
cp "$PW_SRC/lib/helpers.js" "$PW_DST/lib/helpers.js"

# Install playwright runtime (npm + chromium) if not already set up
if [ ! -d "$PW_DST/node_modules" ]; then
  echo "  Installing playwright runtime (npm + chromium)..."
  (cd "$PW_DST" && npm run setup 2>&1) || {
    echo "  Warning: playwright setup failed — run manually: cd $PW_DST && npm run setup"
  }
else
  echo "  playwright-skill runtime already installed"
fi

# Make scripts executable
chmod +x "$RALPH_DST/ralph.sh"

# Initialize progress file if it doesn't exist
if [ ! -f "$RALPH_DST/progress.txt" ]; then
  echo "# Ralph Progress Log" > "$RALPH_DST/progress.txt"
  echo "Started: $(date)" >> "$RALPH_DST/progress.txt"
  echo "---" >> "$RALPH_DST/progress.txt"
fi

# Initialize empty failed report
echo '[]' > "$RALPH_DST/logs/failed_report.json"

# Add recommended .gitignore entries
GITIGNORE="$TARGET/.gitignore"
RALPH_IGNORES=(".worktrees/" ".ralph-locks/")
for pattern in "${RALPH_IGNORES[@]}"; do
  if [ -f "$GITIGNORE" ]; then
    if ! grep -qF "$pattern" "$GITIGNORE"; then
      echo "$pattern" >> "$GITIGNORE"
      echo "  Added $pattern to .gitignore"
    fi
  fi
done

# Create .claude/settings.local.json if it doesn't exist
CLAUDE_SETTINGS="$TARGET/.claude/settings.local.json"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  mkdir -p "$TARGET/.claude"
  cat > "$CLAUDE_SETTINGS" << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(bash:*)"
    ]
  }
}
SETTINGS
  echo "  Created .claude/settings.local.json with bash permissions"
fi

echo ""
echo "Ralph Framework installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Edit scripts/ralph/ralph.config to configure PRD location & stories field"
echo "  2. New project: use the 'prd_init' skill in Claude Code"
echo "  3. Mid-project bugs/features: use the 'prd_append' skill in Claude Code"
echo "  4. Run orchestrator: ./scripts/ralph/ralph.sh --parallel 2"
echo ""
echo "Skills are project-local (scripts/ralph/skills/). For global install, see README."
