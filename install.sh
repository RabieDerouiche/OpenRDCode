#!/usr/bin/env bash
# Installs the agents, commands and skills of this pack into the global OpenCode config.
# Existing files with the same name are backed up first. AGENTS.md and opencode.json are never touched.
set -euo pipefail

PACK_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
BACKUP_DIR="$TARGET_DIR/backup-$(date +%Y%m%d-%H%M%S)"
backed_up=0

backup_if_exists() {
  # $1: path relative to TARGET_DIR
  local rel="$1"
  if [ -e "$TARGET_DIR/$rel" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -R "$TARGET_DIR/$rel" "$BACKUP_DIR/$rel"
    backed_up=1
  fi
}

mkdir -p "$TARGET_DIR/agents" "$TARGET_DIR/commands" "$TARGET_DIR/skills"

for f in "$PACK_DIR"/agents/*.md; do
  name="$(basename "$f")"
  backup_if_exists "agents/$name"
  cp "$f" "$TARGET_DIR/agents/$name"
  echo "Installed agent:   ${name%.md}"
done

for f in "$PACK_DIR"/commands/*.md; do
  name="$(basename "$f")"
  backup_if_exists "commands/$name"
  cp "$f" "$TARGET_DIR/commands/$name"
  echo "Installed command: /${name%.md}"
done

for d in "$PACK_DIR"/skills/*/; do
  name="$(basename "$d")"
  backup_if_exists "skills/$name"
  rm -rf "$TARGET_DIR/skills/$name"
  cp -R "$d" "$TARGET_DIR/skills/$name"
  echo "Installed skill:   $name"
done

echo
if [ "$backed_up" -eq 1 ]; then
  echo "Previous versions of overwritten files were saved to: $BACKUP_DIR"
fi
echo "Not modified (merge manually):"
echo "  - $TARGET_DIR/AGENTS.md      <- content of AGENTS.global.md"
echo "  - $TARGET_DIR/opencode.json  <- content of opencode.snippet.json"
echo "Restart opencode to load the changes."
