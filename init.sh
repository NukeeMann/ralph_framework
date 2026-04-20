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
mkdir -p "$RALPH_DST/skills/karpathy-guidelines"
mkdir -p "$RALPH_DST/logs"
mkdir -p "$RALPH_DST/archive"

# Copy core scripts
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
cp "$RALPH_SRC/skills/prd_init/SKILL.md" "$RALPH_DST/skills/prd_init/SKILL.md"
cp "$RALPH_SRC/skills/prd_append/SKILL.md" "$RALPH_DST/skills/prd_append/SKILL.md"
cp "$RALPH_SRC/skills/karpathy-guidelines/SKILL.md" "$RALPH_DST/skills/karpathy-guidelines/SKILL.md"

# Make scripts executable
chmod +x "$RALPH_DST/run_ralph.sh"

# Initialize progress file if it doesn't exist
if [ ! -f "$RALPH_DST/progress.txt" ]; then
  echo "# Ralph Progress Log" > "$RALPH_DST/progress.txt"
  echo "Started: $(date)" >> "$RALPH_DST/progress.txt"
  echo "---" >> "$RALPH_DST/progress.txt"
fi

# Initialize empty failed report
echo '[]' > "$RALPH_DST/logs/failed_report.json"

# Install ralph-framework as a Claude Code plugin (user scope)
PLUGIN_CACHE="$HOME/.claude/plugins/cache/local/ralph-framework/1.0.0"
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"

if [ ! -d "$PLUGIN_CACHE" ]; then
  mkdir -p "$PLUGIN_CACHE/skills/prd_init"
  mkdir -p "$PLUGIN_CACHE/skills/prd_append"
  mkdir -p "$PLUGIN_CACHE/skills/karpathy-guidelines"
  mkdir -p "$PLUGIN_CACHE/.claude-plugin"

  cp "$RALPH_SRC/skills/prd_init/SKILL.md" "$PLUGIN_CACHE/skills/prd_init/SKILL.md"
  cp "$RALPH_SRC/skills/prd_append/SKILL.md" "$PLUGIN_CACHE/skills/prd_append/SKILL.md"
  cp "$RALPH_SRC/skills/karpathy-guidelines/SKILL.md" "$PLUGIN_CACHE/skills/karpathy-guidelines/SKILL.md"
  cat > "$PLUGIN_CACHE/.claude-plugin/plugin.json" << 'JSON'
{
  "name": "ralph-framework",
  "version": "1.0.0",
  "description": "Ralph autonomous coding agent: prd_init, prd_append, karpathy-guidelines skills."
}
JSON

  # Register plugin in installed_plugins.json
  if [ -f "$INSTALLED_PLUGINS" ]; then
    python3 - "$INSTALLED_PLUGINS" "$PLUGIN_CACHE" << 'PYEOF'
import json, sys
path, install_path = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data.setdefault("plugins", {})["ralph-framework@local"] = [{
    "scope": "user",
    "installPath": install_path,
    "version": "1.0.0",
    "installedAt": __import__('datetime').datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.000Z'),
    "lastUpdated": __import__('datetime').datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.000Z'),
    "projectPath": None
}]
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
    echo "  Installed ralph-framework plugin (restart Claude Code to activate skills)"
  else
    echo "  Warning: $INSTALLED_PLUGINS not found — install Claude Code first"
  fi
else
  # Update skill files in existing cache
  cp "$RALPH_SRC/skills/prd_init/SKILL.md" "$PLUGIN_CACHE/skills/prd_init/SKILL.md"
  cp "$RALPH_SRC/skills/prd_append/SKILL.md" "$PLUGIN_CACHE/skills/prd_append/SKILL.md"
  cp "$RALPH_SRC/skills/karpathy-guidelines/SKILL.md" "$PLUGIN_CACHE/skills/karpathy-guidelines/SKILL.md"
  echo "  Updated ralph-framework plugin skills"
fi

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
echo "  1. Restart Claude Code to activate prd_init, prd_append, karpathy-guidelines skills"
echo "  2. Edit scripts/ralph/ralph.config to configure PRD location & stories field"
echo "  3. New project: use the 'prd_init' skill in Claude Code"
echo "  4. Mid-project bugs/features: use the 'prd_append' skill in Claude Code"
echo "  5. Run orchestrator: ./scripts/ralph/run_ralph.sh --parallel 2 --tool claude"
