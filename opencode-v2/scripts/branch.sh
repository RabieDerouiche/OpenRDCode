#!/bin/sh
# For /go and /push: puts the repository on the right branch, without asking anything.
# Ticket mode (/go): branch.sh <JIRA-KEY | LOCAL> <feature|bugfix|hotfix> "<ticket summary>" [--from <branch>]
# - The current branch already contains the key: kept.
# - Otherwise a branch of the key (local first, then on origin) is checked out.
# - Otherwise a new branch <type>/<KEY>-<words of the summary> starts from the up-to-date base branch
#   (origin/develop, otherwise origin/main or origin/master), without tracking it (the first push sets the upstream).
#   With --from <branch> (/go … depuis <branch>), it starts from origin/<branch> instead, and that branch is recorded as
#   its base (base.sh): its diff, its review, the check before the push, the merges of ship.sh --base and the target of
#   its merge request. The branch must be on origin (a merge request targets a branch of origin).
# - A change without a Jira ticket: the key LOCAL becomes the next free local key, LOCAL-<n> (branches here and on
#   origin, ticket sheets), printed on a "KEY:" line.
# Here mode (/push of work done outside a ticket): branch.sh --here <poc|feature|bugfix|hotfix|wip> "<summary>"
# - On develop, master, main, a detached HEAD (an OpenCode workspace starts detached) or an OpenCode workspace branch:
#   a new branch <type>/<words of the summary> at the current commit, with the uncommitted changes; a name already
#   taken gets -2, -3…; on any other branch: that branch is kept.
# Uncommitted changes never travel silently: they go to a NEW branch only when they were made on the base branch, on
# a detached HEAD or on a workspace branch (work started there before /go or /push); in every other case the script
# stops and lists them. A new ticket branch that cannot start from the base with them (they touch files the base
# changed since) starts at the current commit instead: ship.sh --base merges the base before anything is pushed.
# In an OpenCode workspace, a branch opencode/<name> left without a commit of its own is deleted once the work is on
# its real branch; a ticket branch already open in another worktree stops the script (one ticket per worktree).
# Output: "BRANCH: <name> (<how>)", sometimes followed by "KEY: ...", "BASE: ...", "CARRIED: ...", "CLEANED: ..." or
# "WARNING: ..." (exit 0), or one "STOP: <reason>" line (exit 1).

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

here=$(dirname "$0")
stop() {
  echo "STOP: $*"
  exit 1
}

mode=ticket
if [ "$1" = --here ]; then
  mode=here
  shift
fi
if [ "$mode" = ticket ]; then
  key=$1 type=${2:-feature} summary=$3
  if [ $# -ge 3 ]; then shift 3; else shift $#; fi
else
  key="" type=${1:-poc} summary=$2
  if [ $# -ge 2 ]; then shift 2; else shift $#; fi
fi
from=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      [ $# -ge 2 ] && [ -n "$2" ] || stop "--from needs the name of the branch to start from"
      from=${2#origin/}
      shift 2 ;;
    *) shift ;;
  esac
done

if [ "$mode" = ticket ]; then
  if [ "$key" != LOCAL ] && ! printf '%s' "$key" | grep -qE '^[A-Z][A-Z0-9_]+-[0-9]+$'; then
    stop "\"$key\" is not a Jira key (ABC-123), nor LOCAL for a change without a ticket"
  fi
  case "$type" in
    feature|bugfix|hotfix) ;;
    *) type=feature ;;
  esac
else
  case "$type" in
    poc|feature|bugfix|hotfix|wip) ;;
    *) type=poc ;;
  esac
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not a git repository"
cd "$(git rev-parse --show-toplevel)" || exit 0
if [ -n "$from" ]; then
  git check-ref-format --branch "$from" >/dev/null 2>&1 || stop "\"$from\" is not a branch name"
fi

current=$(git branch --show-current)
detached=""
[ -n "$current" ] || detached=$(git rev-parse --short HEAD 2>/dev/null)

# The branch an OpenCode workspace started on, opencode/<name>, has no use once the work is on its real branch:
# deleted when its last commit is also on another branch, here or on origin (nothing is lost)
cleanup_workspace_branch() {
  case "$current" in opencode/*) ;; *) return 0 ;; esac
  tip=$(git rev-parse -q --verify "refs/heads/$current") || return 0
  if git for-each-ref --contains "$tip" --format='%(refname)' refs/heads refs/remotes | grep -v "^refs/heads/$current\$" | grep -q .; then
    git branch -q -D "$current" 2>/dev/null && echo "CLEANED: the workspace branch $current (no commit of its own)"
  fi
  return 0
}

# Branch name words: the first 5 meaningful words of a summary (no one-letter word, no article or preposition) in
# lower-case ASCII, joined with hyphens (one substitution per letter: in the C locale, a bracket expression would see
# the bytes of an accented letter)
slug() {
  printf '%s' "$1" | sed \
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
    sed 's/-*$//'
}

# Uncommitted changes, tracked or not (ignored files excluded)
dirty=$(git status --porcelain 2>/dev/null | head -n 20 | cut -c4- | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }')

# ---------- here mode: the work goes on a branch of its own, at the current commit ----------
if [ "$mode" = here ]; then
  case "$current" in
    ""|develop|master|main|opencode/*) ;;
    *)
      echo "BRANCH: $current (kept: the work is committed on it)"
      exit 0 ;;
  esac
  words=$(slug "$summary")
  [ -n "$words" ] || words=$(date '+%Y%m%d-%H%M')
  name="$type/$words"
  n=1
  while git rev-parse -q --verify "refs/heads/$name" >/dev/null || git rev-parse -q --verify "refs/remotes/origin/$name" >/dev/null; do
    n=$((n + 1))
    [ "$n" -le 9 ] || stop "the branches $type/$words to $type/$words-9 exist already: give another summary"
    name="$type/$words-$n"
  done
  git switch -q -c "$name" 2>/dev/null || stop "git could not create $name"
  echo "BRANCH: $name (created from ${current:-the detached HEAD $detached}, at $(git log -1 --format='%h, %cs'))"
  [ -n "$dirty" ] && echo "CARRIED: the uncommitted changes came along: $dirty"
  cleanup_workspace_branch
  exit 0
fi

# ---------- ticket mode ----------
# The base of a new branch, and the record of the base when it is not the default one
default=$(sh "$here/base.sh" --default)
record_base() {
  [ -n "$from" ] || return 0
  if [ "$from" = "$default" ]; then
    git config --unset "branch.$1.opencode-base" 2>/dev/null
    return 0
  fi
  was=$(git config --get "branch.$1.opencode-base" 2>/dev/null)
  git config "branch.$1.opencode-base" "$from" || { echo "WARNING: the base $from could not be recorded for $1"; return 0; }
  if [ -n "$was" ] && [ "$was" != "$from" ]; then
    echo "BASE: origin/$from (was origin/$was): the diff, the review, the check before the push and the merge request target it"
  else
    echo "BASE: origin/$from instead of origin/${default:-develop}: the diff, the review, the check before the push and the merge request target it"
  fi
}

regex="(^|[^A-Za-z0-9])$key([^0-9]|$)"
if [ "$key" != LOCAL ] && printf '%s' "$current" | grep -qE "$regex"; then
  echo "BRANCH: $current (already checked out)"
  if [ -n "$from" ]; then
    git rev-parse -q --verify "refs/remotes/origin/$from" >/dev/null || sh "$here/fetch.sh" -q --no-tags origin "+refs/heads/$from:refs/remotes/origin/$from" 2>/dev/null
    if git rev-parse -q --verify "refs/remotes/origin/$from" >/dev/null; then
      record_base "$current"
    else
      echo "WARNING: no branch $from on origin: the base of $current stays origin/$(sh "$here/base.sh")"
    fi
  fi
  exit 0
fi

# Every branch of origin, to find a branch of this key pushed from another computer
sh "$here/fetch.sh" -q --no-tags origin 2>/dev/null
status=$?
case "$status" in
  0) ;;
  77) stop "AUTH FAILED: GitLab refused the credentials of this machine, or got none (COMMANDES.md, section \"Identifiants GitLab\"); nothing was changed" ;;
  *) echo "WARNING: fetch failed or timed out: branches and base as of the last fetch" ;;
esac
default=$(sh "$here/base.sh" --default)

# The branch to start from
start=$default
if [ -n "$from" ]; then
  if git rev-parse -q --verify "refs/remotes/origin/$from" >/dev/null; then
    start=$from
  elif git rev-parse -q --verify "refs/heads/$from" >/dev/null; then
    stop "the branch $from is not on origin (a merge request can only target a branch of origin): push it first (/push on it), then run again"
  else
    # close names: the branches of origin that share its Jira key, otherwise the first word of its last part
    hint=$(printf '%s' "$from" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
    [ -n "$hint" ] || hint=$(printf '%s' "$from" | sed 's#.*/##; s#[-_.].*##')
    near=""
    [ -n "$hint" ] && near=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed 's#^origin/##' | grep -v '^HEAD$' |
      grep -iF -- "$hint" | head -n 5 | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }')
    stop "no branch $from on origin${near:+ (close names: $near)}: check its name, then run again"
  fi
fi

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
    stop "uncommitted changes on ${current:-the detached HEAD $detached} ($dirty): commit them (/push) or put them aside before switching to the branch of $key"
  fi
  if [ -n "$local_branch" ]; then
    elsewhere=$(git worktree list --porcelain 2>/dev/null | awk -v b="branch refs/heads/$local_branch" '/^worktree / { w = substr($0, 10) } $0 == b { print w }' | head -n 1)
    if [ -n "$elsewhere" ]; then
      stop "the branch $local_branch is open in another worktree ($elsewhere): continue the ticket there (one ticket per worktree)"
    fi
    git switch -q "$local_branch" 2>/dev/null || stop "git could not switch to $local_branch"
    echo "BRANCH: $local_branch (switched, existing local branch)"
    record_base "$local_branch"
  else
    name=${remote_branch#origin/}
    git switch -q -c "$name" --track "$remote_branch" 2>/dev/null || stop "git could not create $name from $remote_branch"
    echo "BRANCH: $name (switched, from $remote_branch pushed from another computer)"
    record_base "$name"
  fi
  cleanup_workspace_branch
  exit 0
fi

[ -n "$start" ] || stop "no origin/develop, origin/main or origin/master to start the branch from"
# Uncommitted changes go along only when they were made on the branch the new one starts from, on a detached HEAD or
# on a workspace branch
carry=0
case "$current" in
  "$start"|"$default"|""|opencode/*) carry=1 ;;
esac
if [ -n "$dirty" ] && [ "$carry" -eq 0 ]; then
  stop "uncommitted changes on $current ($dirty): commit them (/push) or put them aside before starting $key"
fi

words=$(slug "$summary")
name="$type/$key"
[ -n "$words" ] && name="$name-$words"

if git switch -q --no-track -c "$name" "origin/$start" 2>/dev/null; then
  echo "BRANCH: $name (created from origin/$start, $(git log -1 --format='%h, %cs' "origin/$start"))"
elif [ -n "$dirty" ] && git switch -q -c "$name" 2>/dev/null; then
  # the changes touch files that origin/<start> changed since the current commit: the branch starts here, with them
  echo "BRANCH: $name (created at the current commit $(git log -1 --format='%h, %cs'), with the uncommitted changes: origin/$start changed the same files since; ship.sh --base merges it before the push)"
else
  stop "git could not create $name from origin/$start"
fi
record_base "$name"
[ -n "$dirty" ] && echo "CARRIED: the uncommitted changes made on ${current:-the detached HEAD $detached} came along: $dirty"
cleanup_workspace_branch
exit 0
