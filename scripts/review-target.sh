#!/bin/sh
# Prepares /review, the review of a teammate's merge request, WITHOUT touching the working tree, the index or the
# current branch: fetches the merge request (GitLab ref refs/merge-requests/<iid>/head) or its source branch, then
# prints the revision to review, its commits, the Jira keys they mention and its diff against the target branch.
# Read-only, except `git fetch` (a branch goes to its usual remote-tracking ref; a merge request only to FETCH_HEAD).
# Usage: review-target.sh <!IID | IID | merge request URL | source branch> [<target branch>]
#   (default target: origin/develop, otherwise origin/main or origin/master)

MAX_DIFF_LINES=1500

# English git messages whatever the language of the machine
LC_ALL=C
export LC_ALL
# File names as they are, without octal quoting of accented letters (git 2.31 or later; older versions ignore it)
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=core.quotePath
GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

arg=$1
target=${2#origin/}
if [ -z "$arg" ]; then
  echo "No revision: give the merge request to review (/review !42, its URL, or its source branch)."
  exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "No revision: not a git repository."
  exit 0
fi

iid=""
branch=""
case "$arg" in
  *merge_requests/*) iid=$(printf '%s' "$arg" | sed -E 's#.*merge_requests/([0-9]+).*#\1#') ;;
  "!"*) iid=${arg#!} ;;
  *[!0-9]*) branch=${arg#origin/} ;;
  *) iid=$arg ;;
esac
case "$iid" in
  *[!0-9]*) echo "No revision: \"$arg\" is not a merge request number."; exit 0 ;;
esac

# Base: the target given, otherwise origin/develop, origin/main or origin/master
find_base() {
  base=""
  if [ -n "$target" ]; then
    git rev-parse -q --verify "refs/remotes/origin/$target" >/dev/null && base="origin/$target"
    return
  fi
  for candidate in develop main master; do
    if git rev-parse -q --verify "refs/remotes/origin/$candidate" >/dev/null; then
      base="origin/$candidate"
      return
    fi
  done
}

# Fetches one refspec; on failure, says why without printing the remote URL (it may hold credentials)
fetch() {
  if ! err=$(git fetch -q --no-tags origin "$1" 2>&1); then
    case "$err" in
      *"couldn't find remote ref"*|*"not our ref"*|*"no such ref"*)
        echo "No revision: $2 not found on origin (wrong number or name, or another repository)." ;;
      *)
        echo "No revision: the fetch failed (offline, or GitLab credentials to fix in the Mac Terminal)." ;;
    esac
    exit 0
  fi
}

find_base
if [ -n "$base" ]; then
  fetch "+refs/heads/${base#origin/}:refs/remotes/$base" "the target branch $base"
else
  fetch "+refs/heads/*:refs/remotes/origin/*" "the branches of origin"
  find_base
fi
if [ -z "$base" ]; then
  echo "No revision: target branch ${target:-develop, main or master} not found on origin."
  exit 0
fi

if [ -n "$iid" ]; then
  label="merge request !$iid"
  fetch "refs/merge-requests/$iid/head" "$label"
  rev=$(git rev-parse -q --verify FETCH_HEAD)
else
  label="branch $branch"
  fetch "+refs/heads/$branch:refs/remotes/origin/$branch" "$label"
  rev=$(git rev-parse -q --verify "refs/remotes/origin/$branch")
fi
short=$(git rev-parse --short "$rev")

echo "Reviewed revision: $short ($label). Read its files with: git show $short:<path>"
echo "Target branch: $base"
echo "Commits of $base not merged into it: $(git rev-list --count "$rev..$base")"
keys=$({ printf '%s\n' "$branch"; git log --no-merges --format='%s%n%b' "$base..$rev"; } | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | sort -u | tr '\n' ' ')
echo "Jira keys (branch name and commit messages): ${keys:-none}"
echo
echo "=== Commits ($(git rev-list --no-merges --count "$base..$rev"), merges of the target branch not shown)"
git log --no-merges --format='%h %an: %s' "$base..$rev"
echo
echo "=== Changed files"
git diff --stat=160 "$base...$rev"
echo
echo "=== Diff against $base"
tmp=$(mktemp "${TMPDIR:-/tmp}/review-target.XXXXXX") || exit 0
trap 'rm -f "$tmp"' EXIT
git diff "$base...$rev" > "$tmp"
lines=$(wc -l < "$tmp" | tr -d ' ')
if [ "$lines" -gt "$MAX_DIFF_LINES" ]; then
  echo "DIFF TOO LARGE ($lines lines): review it file by file with: git diff $base...$short -- <path>"
else
  cat "$tmp"
fi
