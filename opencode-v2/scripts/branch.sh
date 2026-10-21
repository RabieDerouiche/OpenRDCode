#!/bin/sh
# For /go: puts the repository on the branch of a Jira ticket, without asking anything.
# - The current branch already contains the key: kept.
# - Otherwise a branch of the key (local first, then on origin) is checked out.
# - Otherwise a new branch <type>/<KEY>-<words of the summary> starts from the up-to-date base branch
#   (origin/develop, otherwise origin/main or origin/master), without tracking it (the first push sets the upstream).
# Uncommitted changes never travel silently: they go to a NEW branch only when they were made on the base branch
# itself (work started on develop before /go); in every other case the script stops and lists them.
# - A change without a Jira ticket: the key LOCAL becomes the next free local key, LOCAL-<n> (branches here and on
#   origin, ticket sheets), printed on a "KEY:" line.
# - In a worktree made by workspace.sh (a detached HEAD on the base), the branch is checked out or created the same way.
# - In an OpenCode workspace (a git worktree that OpenCode starts on its own branch, opencode/<name>), that branch is
#   deleted once the ticket branch is checked out, when it has no commit of its own; a ticket branch already open in
#   another worktree stops the script (one ticket per worktree).
# Output: "BRANCH: <name> (<how>)", sometimes followed by "KEY: ...", "CARRIED: ...", "CLEANED: ..." or "WARNING: ..."
# (exit 0), or one "STOP: <reason>" line (exit 1).
# Usage: branch.sh <JIRA-KEY | LOCAL> <feature|bugfix|hotfix> "<ticket summary>"

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

key=$1
type=${2:-feature}
summary=$3
here=$(dirname "$0")

if [ "$key" != LOCAL ] && ! printf '%s' "$key" | grep -qE '^[A-Z][A-Z0-9_]+-[0-9]+$'; then
  echo "STOP: \"$key\" is not a Jira key (ABC-123), nor LOCAL for a change without a ticket"
  exit 1
fi
case "$type" in
  feature|bugfix|hotfix) ;;
  *) type=feature ;;
esac
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "STOP: not a git repository"
  exit 1
fi
cd "$(git rev-parse --show-toplevel)" || exit 0

current=$(git branch --show-current)
regex="(^|[^A-Za-z0-9])$key([^0-9]|$)"
if [ "$key" != LOCAL ] && printf '%s' "$current" | grep -qE "$regex"; then
  echo "BRANCH: $current (already checked out)"
  exit 0
fi

# The branch an OpenCode workspace started on, opencode/<name>, has no use once the ticket branch is checked out:
# deleted when its last commit is also on another branch, here or on origin (nothing is lost)
cleanup_workspace_branch() {
  case "$current" in opencode/*) ;; *) return 0 ;; esac
  tip=$(git rev-parse -q --verify "refs/heads/$current") || return 0
  if git for-each-ref --contains "$tip" --format='%(refname)' refs/heads refs/remotes | grep -v "^refs/heads/$current\$" | grep -q .; then
    git branch -q -D "$current" 2>/dev/null && echo "CLEANED: the workspace branch $current (no commit of its own)"
  fi
  return 0
}

# Uncommitted changes, tracked or not (ignored files excluded)
dirty=$(git status --porcelain 2>/dev/null | head -n 20 | cut -c4- | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }')

# Every branch of origin, to find a branch of this key pushed from another computer
sh "$here/fetch.sh" -q --no-tags origin 2>/dev/null
status=$?
case "$status" in
  0) ;;
  77)
    echo "STOP: AUTH FAILED: GitLab refused the credentials of this machine, or got none (COMMANDES.md, section \"Identifiants GitLab\"); nothing was changed"
    exit 1 ;;
  *) echo "WARNING: fetch failed or timed out: branches and base as of the last fetch" ;;
esac

base=""
for candidate in develop main master; do
  if git rev-parse -q --verify "refs/remotes/origin/$candidate" >/dev/null; then
    base=$candidate
    break
  fi
done

# A change without a ticket: the next free local key
if [ "$key" = LOCAL ]; then
  common=$(git rev-parse --git-common-dir 2>/dev/null) && common=$(cd "$common" && pwd)
  last=$( { git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin; ls "${common:-.git}/opencode-tickets" 2>/dev/null; } |
    grep -oE '(^|[^A-Za-z0-9])LOCAL-[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -n 1)
  key="LOCAL-$(( ${last:-0} + 1 ))"
  regex="(^|[^A-Za-z0-9])$key([^0-9]|$)"
  echo "KEY: $key"
fi

local_branch=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -E "$regex" | head -n 1)
remote_branch=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v '/HEAD$' | grep -E "$regex" | head -n 1)

if [ -n "$local_branch" ] || [ -n "$remote_branch" ]; then
  if [ -n "$dirty" ]; then
    echo "STOP: uncommitted changes on $current ($dirty): commit them or put them aside before switching to the branch of $key"
    exit 1
  fi
  if [ -n "$local_branch" ]; then
    elsewhere=$(git worktree list --porcelain 2>/dev/null | awk -v b="branch refs/heads/$local_branch" '/^worktree / { w = substr($0, 10) } $0 == b { print w }' | head -n 1)
    if [ -n "$elsewhere" ]; then
      echo "STOP: the branch $local_branch is open in another worktree ($elsewhere): continue the ticket there (one ticket per worktree)"
      exit 1
    fi
    if git switch -q "$local_branch" 2>/dev/null; then
      echo "BRANCH: $local_branch (switched, existing local branch)"
      cleanup_workspace_branch
    else
      echo "STOP: git could not switch to $local_branch"
      exit 1
    fi
  else
    name=${remote_branch#origin/}
    if git switch -q -c "$name" --track "$remote_branch" 2>/dev/null; then
      echo "BRANCH: $name (switched, from $remote_branch pushed from another computer)"
      cleanup_workspace_branch
    else
      echo "STOP: git could not create $name from $remote_branch"
      exit 1
    fi
  fi
  exit 0
fi

if [ -z "$base" ]; then
  echo "STOP: no origin/develop, origin/main or origin/master to start the branch from"
  exit 1
fi
if [ -n "$dirty" ] && [ "$current" != "$base" ]; then
  echo "STOP: uncommitted changes on $current ($dirty): commit them or put them aside before starting $key"
  exit 1
fi

# Branch name: the key, then the first 5 meaningful words of the summary (no one-letter word, no article or
# preposition) in lower-case ASCII, joined with hyphens
# (one substitution per letter: in the C locale, a bracket expression would see the bytes of an accented letter)
slug=$(printf '%s' "$summary" | sed \
  -e 's/à/a/g; s/á/a/g; s/â/a/g; s/ä/a/g; s/ã/a/g; s/À/a/g; s/Â/a/g; s/Ä/a/g' \
  -e 's/è/e/g; s/é/e/g; s/ê/e/g; s/ë/e/g; s/È/e/g; s/É/e/g; s/Ê/e/g; s/Ë/e/g' \
  -e 's/ì/i/g; s/í/i/g; s/î/i/g; s/ï/i/g; s/Î/i/g; s/Ï/i/g' \
  -e 's/ò/o/g; s/ó/o/g; s/ô/o/g; s/ö/o/g; s/õ/o/g; s/Ô/o/g; s/Ö/o/g' \
  -e 's/ù/u/g; s/ú/u/g; s/û/u/g; s/ü/u/g; s/Ù/u/g; s/Û/u/g; s/Ü/u/g' \
  -e 's/ç/c/g; s/Ç/c/g; s/ñ/n/g; s/ÿ/y/g; s/œ/oe/g; s/Œ/oe/g; s/æ/ae/g; s/Æ/ae/g' |
  tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' ' |
  awk 'BEGIN { split("de des du la le les un une et en au aux pour par sur dans avec the of a an to for and in on with", W, " "); for (k in W) stop[W[k]] = 1 }
    { out = ""; n = 0
      for (i = 1; i <= NF && n < 5; i++) if (length($i) > 1 && !($i in stop)) { out = out (n > 0 ? "-" : "") $i; n++ }
      print substr(out, 1, 40) }' |
  sed 's/-*$//')
name="$type/$key"
[ -n "$slug" ] && name="$name-$slug"

if ! git switch -q --no-track -c "$name" "origin/$base" 2>/dev/null; then
  echo "STOP: git could not create $name from origin/$base (uncommitted changes in conflict with it?)"
  exit 1
fi
echo "BRANCH: $name (created from origin/$base, $(git log -1 --format='%h, %cs' "origin/$base"))"
[ -n "$dirty" ] && echo "CARRIED: the uncommitted changes made on $base came along: $dirty"
cleanup_workspace_branch
exit 0
