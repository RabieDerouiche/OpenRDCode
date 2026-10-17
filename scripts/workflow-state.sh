#!/bin/sh
# Prints, in one sequential run, the git state used by the workflow commands (/next, /dev, /test, /check, /ship, /sync,
# /ticket, /scans). OpenCode runs the shell injections of a command in parallel: running everything here, after a
# single fetch, avoids stale remote refs and git lock conflicts.
# Read-only, except `git fetch`.
# Usage: workflow-state.sh [--no-fetch] [--diff]
#   --no-fetch  do not fetch origin first
#   --diff      also print the commits and the full diffs of the branch (committed and uncommitted)

fetch=1
diff=0
for arg in "$@"; do
  case "$arg" in
    --no-fetch) fetch=0 ;;
    --diff) diff=1 ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository"
  exit 0
fi

if [ "$fetch" -eq 1 ]; then
  git fetch -q origin 2>/dev/null || echo "Fetch: FAILED (offline, or GitLab credentials to fix in the Mac Terminal)"
fi

root=$(git rev-parse --show-toplevel)
branch=$(git branch --show-current)
key=$(printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)

# Base branch: origin/develop, otherwise origin/main or origin/master
base=""
for candidate in origin/develop origin/main origin/master; do
  if git rev-parse -q --verify "$candidate" >/dev/null; then
    base=$candidate
    break
  fi
done

upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
sheets="$root/.git/opencode/tickets"

echo "Repository root: $root"
echo "Current branch: ${branch:-(detached HEAD)}"
echo "Jira key from branch: ${key:-none}"
echo "Base branch: ${base:-NONE (no origin/develop, origin/main or origin/master)}"
echo "HEAD: $(git rev-parse --short HEAD 2>/dev/null)"
echo "Branch vs its remote copy: $(git status -sb | head -1)"
if [ -n "$upstream" ]; then
  echo "Upstream: $upstream"
  echo "Pushed commit (upstream): $(git rev-parse '@{u}')"
  echo "Pushed commit date: $(git log -1 --format=%cI '@{u}')"
  echo "Local commits not pushed:"
  git log --oneline '@{u}..HEAD'
else
  echo "Upstream: none (branch never pushed)"
fi
if [ -n "$base" ]; then
  echo "Commits behind / ahead of $base: $(git rev-list --left-right --count "$base...HEAD" | tr '\t' ' ')"
fi
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo "Merge in progress: yes"
else
  echo "Merge in progress: no"
fi
echo "Uncommitted changes summary: $(git diff HEAD --shortstat)"
echo "Staged changes summary:"
git diff --staged --stat | tail -1
echo "Uncommitted files (staged and unstaged):"
git diff HEAD --name-status
echo "Untracked files:"
git ls-files --others --exclude-standard
if [ -n "$base" ]; then
  echo "Files changed on the branch (vs $base):"
  git diff --name-status "$base...HEAD"
fi
echo "Last change of AGENTS.md: $(git log -1 --format='%h %cs' -- AGENTS.md)"
echo "Ticket sheets folder: $sheets"
echo "Existing ticket sheets:"
ls "$sheets" 2>/dev/null
if [ -n "$key" ] && [ -f "$sheets/$key.md" ]; then
  echo "Current ticket sheet: $sheets/$key.md"
  echo "Ticket title line: $(head -1 "$sheets/$key.md")"
  echo "Ticket Jira line: $(grep -m1 '^- Jira' "$sheets/$key.md")"
elif [ -n "$key" ]; then
  echo "Current ticket sheet: none for $key"
fi

if [ "$diff" -eq 1 ] && [ -n "$base" ]; then
  echo
  echo "=== Commits since $base"
  git log --oneline "$base..HEAD"
  echo
  echo "=== Committed diff against $base"
  git diff "$base...HEAD"
  echo
  echo "=== Uncommitted diff (staged and unstaged)"
  git diff HEAD
fi
