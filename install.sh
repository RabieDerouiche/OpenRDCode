#!/usr/bin/env bash
# Installs the agents, commands and skills of this pack into the global OpenCode config.
# Existing files with the same name are backed up first. AGENTS.md and opencode.json are never touched.
set -euo pipefail

PACK_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
BACKUP_DIR="$TARGET_DIR/backup-$(date +%Y%m%d-%H%M%S)"
backed_up=0

backup_if_exists() {
  # $1: path relative to TARGET_DIR; $2 (optional): the new version from the pack.
  # Backs up only what would be lost: a file that differs from the new version, or a file being removed.
  local rel="$1" new="${2:-}"
  [ -e "$TARGET_DIR/$rel" ] || return 0
  if [ -n "$new" ]; then
    if [ -d "$new" ]; then
      diff -rq "$TARGET_DIR/$rel" "$new" >/dev/null 2>&1 && return 0
    else
      cmp -s "$TARGET_DIR/$rel" "$new" && return 0
    fi
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  cp -R "$TARGET_DIR/$rel" "$BACKUP_DIR/$rel"
  backed_up=1
}

mkdir -p "$TARGET_DIR/agents" "$TARGET_DIR/commands" "$TARGET_DIR/skills"

# Files from older versions of the pack, merged into the workflow commands: backed up, then removed.
OBSOLETE="agents/fortify.md
commands/review-branch.md
commands/test-for.md
commands/test-branch.md
commands/commit-msg.md
commands/mr-desc.md
commands/quality.md
commands/fortify.md
commands/start-ticket.md
commands/git-start.md
commands/git-sync.md
commands/git-ship.md
commands/explain.md
commands/debug.md
commands/plan-feature.md
commands/build-fix.md
commands/release-notes-group.md
commands/agents-from-confluence.md"
for rel in $OBSOLETE; do
  if [ -e "$TARGET_DIR/$rel" ]; then
    backup_if_exists "$rel"
    rm -f "$TARGET_DIR/$rel"
    echo "Removed (merged):  $rel"
  fi
done

for f in "$PACK_DIR"/agents/*.md; do
  name="$(basename "$f")"
  backup_if_exists "agents/$name" "$f"
  cp "$f" "$TARGET_DIR/agents/$name"
  echo "Installed agent:   ${name%.md}"
done

for f in "$PACK_DIR"/commands/*.md; do
  name="$(basename "$f")"
  backup_if_exists "commands/$name" "$f"
  cp "$f" "$TARGET_DIR/commands/$name"
  echo "Installed command: /${name%.md}"
done

for d in "$PACK_DIR"/skills/*/; do
  name="$(basename "$d")"
  backup_if_exists "skills/$name" "$d"
  rm -rf "$TARGET_DIR/skills/$name"
  cp -R "$d" "$TARGET_DIR/skills/$name"
  echo "Installed skill:   $name"
done

mkdir -p "$TARGET_DIR/scripts"
for f in "$PACK_DIR"/scripts/*.sh; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  backup_if_exists "scripts/$name" "$f"
  cp "$f" "$TARGET_DIR/scripts/$name"
  chmod +x "$TARGET_DIR/scripts/$name"
  echo "Installed script:  $name"
done

echo
if [ "$backed_up" -eq 1 ]; then
  echo "Previous versions of overwritten files were saved to: $BACKUP_DIR"
fi
# Keep only the 5 most recent backups (portable: GNU and BSD/macOS)
# shellcheck disable=SC2012 # the backup folder names are generated: backup-<date>-<time>
backups=$(ls -1d "$TARGET_DIR"/backup-* 2>/dev/null | sort || true)
count=$(printf '%s\n' "$backups" | grep -c . || true)
if [ "$count" -gt 5 ]; then
  printf '%s\n' "$backups" | head -n "$((count - 5))" | while read -r old; do rm -rf "$old"; done
fi
echo "Not modified (merge manually):"
echo "  - $TARGET_DIR/AGENTS.md      <- content of AGENTS.global.md"
echo "  - $TARGET_DIR/opencode.json  <- content of opencode.snippet.json"
echo "Restart opencode to load the changes."
