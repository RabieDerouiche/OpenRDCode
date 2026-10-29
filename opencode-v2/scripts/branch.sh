#!/bin/sh
# For /go and /push: puts the repository on the right branch, without asking anything.
# Ticket mode (/go): branch.sh <JIRA-KEY | LOCAL> <feature|bugfix|hotfix> "<ticket summary>" [--from <branch>] [--on <branch>]
# - The current branch already contains the key, or the key is recorded for it (below): kept.
# - --on <branch> (/go … sur <branch>): the work goes on that branch, as it is named (local first, then on origin); the
#   key is recorded for it in git (branch.<name>.opencode-key), where the scripts that look for the ticket sheet of a
#   branch find it when its name does not hold it. Never develop, main, master, the base branch nor a workspace branch.
# - Otherwise a branch of the key (local first, then on origin) is checked out.
# - Otherwise a new branch <type>/<KEY>-<words of the summary> starts from the up-to-date base branch
#   (origin/develop, otherwise origin/main or origin/master), without tracking it (the first push sets the upstream).
#   With --from <branch> (/go … depuis <branch>), it starts from origin/<branch> instead, and that branch is recorded as
#   its base (base.sh): its diff, its review, the check before the push, the merges of ship.sh --base and the target of
#   its merge request. The branch must be on origin (a merge request targets a branch of origin).
# - A change without a Jira ticket: the key LOCAL becomes the next free local key, LOCAL-<n> (branches here and on
#   origin, ticket sheets, keys recorded), printed on a "KEY:" line; the key is reserved at once in the git folder that
#   the worktrees share, so that two /go of two worktrees started at the same moment never get the same key. It names the
#   ticket sheet only: a new branch is <type>/<words of the summary> (-2, -3… when taken), with the key recorded for it;
#   with --on, the branch given keeps its name (a key already recorded for it is kept: the same sheet).
# Here mode (/push and /tests, work done outside a ticket):
#   branch.sh --here <feature|bugfix|hotfix|test|docs|refactor|chore|poc|wip> "<summary>"   or   branch.sh --here --name <branch>
# - On develop, master, main, a detached HEAD (an OpenCode workspace starts detached) or an OpenCode workspace branch:
#   a new branch <type>/<words of the summary> (or the name given) at the current commit, with the uncommitted
#   changes; a name already taken gets -2, -3… (a name given and taken stops: choose another); on any other branch:
#   that branch is kept. Commits made on develop, master or main that origin does not have go to the new branch with
#   the rest, and the protected branch goes back to its copy on origin ("MOVED:"): it never keeps work of its own.
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

here=$(cd "$(dirname "$0")" && pwd)
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
  key="" type=${1:-poc} summary=$2 given=""
  if [ "$1" = --name ]; then
    given=$2 type=""
  fi
  if [ $# -ge 2 ]; then shift 2; else shift $#; fi
fi
from="" on="" localkey=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from)
      [ $# -ge 2 ] && [ -n "$2" ] || stop "--from needs the name of the branch to start from"
      from=${2#origin/}
      shift 2 ;;
    --on)
      [ $# -ge 2 ] && [ -n "$2" ] || stop "--on needs the name of the branch to work on"
      on=${2#origin/}
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
elif [ -n "$given" ] || [ "$type" = "" ]; then
  raw=${given#origin/}
  # a name typed by the developer in the question of /push: spaces become hyphens, the characters git refuses go
  given=$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]][[:space:]]*/-/g' \
    -e 's/@{//g; s/[~^:?*[]//g' -e 's#\\#/#g; s#//*#/#g; s/\.\.\.*/./g; s#^[/.-]*##; s#[/.]*$##; s/\.lock$//')
  renamed=""
  [ "$given" = "$raw" ] || renamed=$raw
  [ -n "$given" ] && git check-ref-format --branch "$given" >/dev/null 2>&1 || stop "\"$raw\" is not a branch name"
  case "$given" in
    develop|master|main|opencode/*) stop "$given is not a branch for this work: give the name of a branch of its own" ;;
  esac
else
  case "$type" in
    feature|bugfix|hotfix|test|docs|refactor|chore|poc|wip) ;;
    *) type=poc ;;
  esac
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not a git repository"
cd "$(git rev-parse --show-toplevel)" || exit 0
if [ -n "$from" ]; then
  git check-ref-format --branch "$from" >/dev/null 2>&1 || stop "\"$from\" is not a branch name"
fi
if [ -n "$on" ]; then
  git check-ref-format --branch "$on" >/dev/null 2>&1 || stop "\"$on\" is not a branch name"
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
  taken() {
    git rev-parse -q --verify "refs/heads/$1" >/dev/null || git rev-parse -q --verify "refs/remotes/origin/$1" >/dev/null
  }
  if [ -n "$given" ]; then
    name=$given
    taken "$name" && stop "the branch $name exists already (here or on origin): give another name"
  else
    words=$(slug "$summary")
    [ -n "$words" ] || words=$(date '+%Y%m%d-%H%M')
    name="$type/$words"
    n=1
    while taken "$name"; do
      n=$((n + 1))
      [ "$n" -le 9 ] || stop "the branches $type/$words to $type/$words-9 exist already: give another summary"
      name="$type/$words-$n"
    done
  fi
  # commits of develop, master or main that origin does not have: they are the work, they go with it
  own=0
  case "$current" in
    develop|master|main)
      git rev-parse -q --verify "refs/remotes/origin/$current" >/dev/null &&
        own=$(git rev-list --count "refs/remotes/origin/$current..HEAD") ;;
  esac
  # a detached HEAD that is not on the default base (a workspace started from another branch): its commits go with the
  # work, and with its merge request
  extra=0
  if [ -z "$current" ]; then
    default=$(sh "$here/base.sh" --default)
    [ -n "$default" ] && git rev-parse -q --verify "refs/remotes/origin/$default" >/dev/null &&
      extra=$(git rev-list --count "refs/remotes/origin/$default..HEAD")
  fi
  sh "$here/transient.sh" git switch -q -c "$name" >/dev/null || stop "git could not create $name"
  echo "BRANCH: $name (created from ${current:-the detached HEAD $detached}, at $(git log -1 --format='%h, %cs'))${renamed:+ (the name given, made valid: $renamed)}"
  [ -n "$dirty" ] && echo "CARRIED: the uncommitted changes came along: $dirty"
  if [ "$extra" -gt 0 ]; then
    from_branches=$(git for-each-ref --contains HEAD --format='%(refname:short)' refs/heads refs/remotes/origin | grep -vxF "$name" | grep -v '/HEAD$' | head -n 3 | tr '\n' ' ' | sed 's/ $//')
    echo "WARNING: the detached HEAD was $extra commits ahead of origin/$default${from_branches:+ (the commits of $from_branches)}: they are in $name, and in its merge request"
  fi
  if [ "$own" -gt 0 ]; then
    if git branch -q -f "$current" "refs/remotes/origin/$current" 2>/dev/null; then
      echo "MOVED: the $own commits of $current that origin/$current does not have are on $name now; $current is back at origin/$current"
    else
      echo "WARNING: the $own commits of $current that origin/$current does not have are on $name too; $current still has them (it is checked out in another worktree): reset it there"
    fi
  fi
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
# the key recorded for a branch that /go worked on under its own name (--on, or a change without a ticket)
recorded_key() { [ -n "$1" ] && git config --get "branch.$1.opencode-key" 2>/dev/null; }
record_key() {
  git config "branch.$1.opencode-key" "$2" 2>/dev/null || echo "WARNING: the key $2 could not be recorded for $1: its ticket sheet is not found from it"
}
if [ "$key" != LOCAL ] && [ -z "$on" ] && { printf '%s' "$current" | grep -qE "$regex" || [ "$(recorded_key "$current")" = "$key" ]; }; then
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

# A change without a ticket: the next free local key (branches, ticket sheets, reservations and keys recorded)
next_local_key() {
  common=$(git rev-parse --git-common-dir 2>/dev/null) && common=$(cd "$common" && pwd)
  keys="${common:-.git}/opencode-tickets/.local-keys"
  mkdir -p "$keys" 2>/dev/null
  last=$( { git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin; ls "${common:-.git}/opencode-tickets" "$keys" 2>/dev/null
    git config --get-regexp '^branch\..*\.opencode-key$' 2>/dev/null; } |
    grep -oE '(^|[^A-Za-z0-9])LOCAL-[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -n 1)
  n=$(( ${last:-0} + 1 ))
  # the reservation: mkdir succeeds for one run only (a /go of another worktree at the same moment takes the next)
  tries=0
  while ! mkdir "$keys/LOCAL-$n" 2>/dev/null; do
    n=$((n + 1))
    tries=$((tries + 1))
    [ "$tries" -lt 50 ] || stop "no free local key (LOCAL-$n reserved): check $keys"
  done
  echo "LOCAL-$n"
}

# --on <branch>: the work goes on that branch, as it is named
if [ -n "$on" ]; then
  case "$on" in
    develop|master|main|"$default"|opencode/*) stop "$on is not a branch for this work: name a branch of its own, or let /go create the branch of the ticket" ;;
  esac
  if [ "$current" = "$on" ]; then
    how="already checked out"
  elif git rev-parse -q --verify "refs/heads/$on" >/dev/null; then
    [ -z "$dirty" ] || stop "uncommitted changes on ${current:-the detached HEAD $detached} ($dirty): commit them (/push) or put them aside before switching to $on"
    elsewhere=$(git worktree list --porcelain 2>/dev/null | awk -v b="branch refs/heads/$on" '/^worktree / { w = substr($0, 10) } $0 == b { print w }' | head -n 1)
    [ -z "$elsewhere" ] || stop "the branch $on is open in another worktree ($elsewhere): continue there (one ticket per worktree)"
    sh "$here/transient.sh" git switch -q "$on" >/dev/null || stop "git could not switch to $on"
    how="switched, existing local branch"
  elif git rev-parse -q --verify "refs/remotes/origin/$on" >/dev/null; then
    [ -z "$dirty" ] || stop "uncommitted changes on ${current:-the detached HEAD $detached} ($dirty): commit them (/push) or put them aside before switching to $on"
    sh "$here/transient.sh" git switch -q -c "$on" --track "origin/$on" >/dev/null || stop "git could not create $on from origin/$on"
    how="switched, from origin/$on"
  else
    hint=$(printf '%s' "$on" | sed 's#.*/##; s#[-_.].*##')
    near=""
    [ -n "$hint" ] && near=$( { git for-each-ref --format='%(refname:short)' refs/heads; git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed 's#^origin/##'; } |
      grep -v '^HEAD$' | sort -u | grep -iF -- "$hint" | head -n 5 | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }')
    stop "no branch $on here nor on origin${near:+ (close names: $near)}: check its name, then run again"
  fi
  if [ "$key" = LOCAL ]; then
    key=$(recorded_key "$on")
    [ -n "$key" ] || key=$(next_local_key) || { echo "$key"; exit 1; }
  fi
  # the key recorded for the branch, unless its name holds it
  printf '%s' "$on" | grep -qE "(^|[^A-Za-z0-9])$key([^0-9]|$)" || record_key "$on" "$key"
  echo "BRANCH: $on ($how)"
  echo "KEY: $key"
  record_base "$on"
  cleanup_workspace_branch
  exit 0
fi

if [ "$key" = LOCAL ]; then
  key=$(next_local_key) || { echo "$key"; exit 1; }
  regex="(^|[^A-Za-z0-9])$key([^0-9]|$)"
  echo "KEY: $key"
  localkey=1
fi

local_branch=$(git for-each-ref --format='%(refname:short)' refs/heads | grep -E "$regex" | head -n 1)
# a branch named without its key that /go recorded it for (--on)
[ -n "$local_branch" ] || local_branch=$(git config --get-regexp '^branch\..*\.opencode-key$' 2>/dev/null |
  awk -v k="$key" '$2 == k { sub(/^branch\./, "", $1); sub(/\.opencode-key$/, "", $1); print $1 }' |
  while read -r b; do git rev-parse -q --verify "refs/heads/$b" >/dev/null && echo "$b"; done | head -n 1)
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
    sh "$here/transient.sh" git switch -q "$local_branch" >/dev/null || stop "git could not switch to $local_branch"
    echo "BRANCH: $local_branch (switched, existing local branch)"
    record_base "$local_branch"
  else
    name=${remote_branch#origin/}
    sh "$here/transient.sh" git switch -q -c "$name" --track "$remote_branch" >/dev/null || stop "git could not create $name from $remote_branch"
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
if [ -n "$localkey" ]; then
  # a change without a ticket: a branch named after the change, its key recorded for it (the sheet is found from it)
  [ -n "$words" ] || words=$(date '+%Y%m%d-%H%M')
  name="$type/$words"
  n=1
  while git rev-parse -q --verify "refs/heads/$name" >/dev/null || git rev-parse -q --verify "refs/remotes/origin/$name" >/dev/null; do
    n=$((n + 1))
    [ "$n" -le 9 ] || stop "the branches $type/$words to $type/$words-9 exist already: describe the change in other words"
    name="$type/$words-$n"
  done
fi

while :; do
  if sh "$here/transient.sh" git switch -q --no-track -c "$name" "origin/$start" >/dev/null; then
    echo "BRANCH: $name (created from origin/$start, $(git log -1 --format='%h, %cs' "origin/$start"))"
  elif [ -n "$dirty" ] && sh "$here/transient.sh" git switch -q -c "$name" >/dev/null; then
    # the changes touch files that origin/<start> changed since the current commit: the branch starts here, with them
    echo "BRANCH: $name (created at the current commit $(git log -1 --format='%h, %cs'), with the uncommitted changes: origin/$start changed the same files since; ship.sh --base merges it before the push)"
  elif [ -n "$localkey" ] && [ "$n" -lt 9 ] && git rev-parse -q --verify "refs/heads/$name" >/dev/null; then
    # a /go of another worktree took the same name at the same moment: the next one
    n=$((n + 1))
    name="$type/$words-$n"
    continue
  else
    stop "git could not create $name from origin/$start"
  fi
  break
done
record_base "$name"
[ -z "$localkey" ] || record_key "$name" "$key"
[ -n "$dirty" ] && echo "CARRIED: the uncommitted changes made on ${current:-the detached HEAD $detached} came along: $dirty"
cleanup_workspace_branch
exit 0
