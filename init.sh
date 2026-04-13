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
mkdir -p "$RALPH_DST/skills/convert"
mkdir -p "$RALPH_DST/skills/create"
mkdir -p "$RALPH_DST/logs"
mkdir -p "$RALPH_DST/archive"

# Copy core scripts
cp "$RALPH_SRC/ralph.sh" "$RALPH_DST/ralph.sh"
cp "$RALPH_SRC/run_ralph.sh" "$RALPH_DST/run_ralph.sh"
cp "$RALPH_SRC/CLAUDE.md" "$RALPH_DST/CLAUDE.md"

# Copy config (don't overwrite existing)
if [ ! -f "$RALPH_DST/ralph.config" ]; then
  cp "$RALPH_SRC/ralph.config" "$RALPH_DST/ralph.config"
  echo "  Created ralph.config (edit to customize PRD location, stories field, etc.)"
else
  echo "  ralph.config already exists - skipping (check ralph_framework for updates)"
fi

# Copy skills
cp "$RALPH_SRC/skills/convert/SKILL.md" "$RALPH_DST/skills/convert/SKILL.md"
cp "$RALPH_SRC/skills/create/SKILL.md" "$RALPH_DST/skills/create/SKILL.md"

# Make scripts executable
chmod +x "$RALPH_DST/ralph.sh"
chmod +x "$RALPH_DST/run_ralph.sh"

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
echo "  2. Create a PRD: use the 'create' skill or write tasks/prd-feature.md manually"
echo "  3. Convert PRD to prd.json: use the 'convert' skill"
echo "  4. Run single iteration:  ./scripts/ralph/ralph.sh --tool claude"
echo "  5. Run parallel orchestrator: ./scripts/ralph/run_ralph.sh --parallel 2 --tool claude"
