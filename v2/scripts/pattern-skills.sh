#!/bin/sh
# Lists the pattern skills (pattern-*) of this machine with their ABSOLUTE paths, read from the disk.
# OpenCode loads its skills once, when a project is first opened: a skill created or enriched by /extract-pattern is
# unknown to the skill tool (or stale) until OpenCode restarts, so /apply-pattern and /dev read the file itself. The
# file tools of OpenCode do not expand `~`: the absolute paths below are the ones to use.
# Usage: pattern-skills.sh [<pattern name>]

dir="$HOME/.config/opencode/skills"
echo "Pattern skills folder: $dir"
echo "Existing pattern skills (name | description):"
found=0
for file in "$dir"/pattern-*/SKILL.md; do
  [ -f "$file" ] || continue
  found=1
  name=$(basename "$(dirname "$file")")
  description=$(sed -n 's/^description: *//p' "$file" | head -1 | cut -c1-200)
  echo "- $name | $description"
done
[ "$found" -eq 0 ] && echo "- none"
if [ -n "$1" ]; then
  name=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  for scope in back front; do
    file="$dir/pattern-$name-$scope/SKILL.md"
    if [ -f "$file" ]; then
      echo "Skill file pattern-$name-$scope: $file (exists, $(wc -l < "$file" | tr -d ' ') lines)"
    else
      echo "Skill file pattern-$name-$scope: $file (does not exist)"
    fi
  done
fi
