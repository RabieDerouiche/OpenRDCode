#!/bin/sh
# For /go, /fix, /push and /sync: the only way the agents write to git. In one call:
# 1. commits everything of the working tree (git add -A) on the branch of the ticket;
# 2. integrates the commits pushed meanwhile on its remote copy (for example from Rider on another computer);
# 3. with --base, merges the new commits of the base branch (base.sh: the branch it was started from when /go recorded
#    one, otherwise origin/develop, origin/main or origin/master);
#    with --merge <branch>, merges another branch too (a hotfix, a teammate's branch), from origin when it is there;
# 4. checks the changes of the branch (diff-guard.sh: a secret, a conflict marker or a paid package stops everything),
#    then pushes, and sets the upstream on the first push.
# With --no-push: step 1 only (a local commit at the end of a plan step: the work is saved, the CI is not started).
# Always by merge, never a rebase, never a force-push, never on develop, master or main. A merge conflict is aborted
# (nothing is lost, the conflicting files are listed): the agents never pick a side. git never waits for a password:
# missing GitLab credentials end with "STOP: AUTH FAILED".
# Output: one line per stage (COMMIT, REMOTE, BASE, GUARD with its WARNING and PACKAGES lines, PUSH, MR LINK), then
# "RESULT: OK" (exit 0), or a "STOP: <reason>"
# line where the script stopped (exit 1, so that a command chained with && does not run).
# Usage: ship.sh [--base] "<commit summary>" ["<body line>"...]
#        ship.sh --no-push "<commit summary>" ["<body line>"...]
#        ship.sh --sync-only [--base] [--merge <branch>]
#                                          steps 2 and 3 only: no commit, no push, local changes left as they are;
#                                          on develop, master, main or the base branch, --sync-only alone: a
#                                          fast-forward to origin, never a merge

PUSH_TIMEOUT=${PUSH_TIMEOUT:-90}

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT
GIT_EDITOR=true
export GIT_EDITOR
if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ] && [ -z "$(git config --get core.sshCommand 2>/dev/null)" ]; then
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15"
  export GIT_SSH_COMMAND
fi

here=$(cd "$(dirname "$0")" && pwd)
with_base=0
sync_only=0
no_push=0
merge_branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) with_base=1; shift ;;
    --sync-only) sync_only=1; shift ;;
    --no-push) no_push=1; shift ;;
    --merge)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "STOP: --merge needs the name of the branch to merge"; exit 1; }
      merge_branch=${2#origin/}
      shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
summary=$1
[ $# -gt 0 ] && shift
body=""
[ $# -gt 0 ] && body=$(printf '%s\n' "$@")

stop() {
  echo "STOP: $*"
  exit 1
}
join() {
  awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }'
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not a git repository"
cd "$(git rev-parse --show-toplevel)" || exit 0
gitdir=$(git rev-parse --git-dir)
branch=$(git branch --show-current)
[ -n "$branch" ] || stop "detached HEAD (an OpenCode workspace starts so): no branch to commit on; /push creates one (branch.sh --here) before it commits"
# The base: the branch it was started from when branch.sh recorded one (/go … depuis <branch>), otherwise develop,
# main or master (base.sh)
base=$(sh "$here/base.sh" "$branch")
# develop, master, main and the base branch: never a commit, a merge or a push; only --sync-only alone, which brings
# them up to date with origin by fast-forward (/sync on develop)
protected=0
case "$branch" in
  develop|master|main) protected=1 ;;
esac
[ -n "$base" ] && [ "$branch" = "$base" ] && protected=1
if [ "$protected" -eq 1 ] && { [ "$sync_only" -eq 0 ] || [ "$with_base" -eq 1 ] || [ -n "$merge_branch" ]; }; then
  stop "$branch is a protected branch: commits, merges and pushes go on another branch (/push creates one for this work, /go one for a ticket)"
fi
[ -f "$gitdir/MERGE_HEAD" ] && stop "a merge is in progress on $branch: finish it in Rider (or git merge --abort), then run again"
if [ -n "$merge_branch" ]; then
  git check-ref-format --branch "$merge_branch" >/dev/null 2>&1 || stop "\"$merge_branch\" is not a branch name"
  [ "$merge_branch" = "$branch" ] && stop "$branch cannot be merged into itself"
fi
{ [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; } && stop "a rebase is in progress on $branch: finish or abort it first"

# 1. Commit
if [ "$sync_only" -eq 0 ]; then
  git add -A || stop "git add failed"
  if git diff --cached --quiet; then
    echo "COMMIT: nothing new to commit"
  else
    [ -n "$summary" ] || stop "commit summary missing (ship.sh \"<summary>\" [\"<body line>\"...])"
    if [ -n "$body" ]; then
      set -- -m "$summary" -m "$body"
    else
      set -- -m "$summary"
    fi
    if ! out=$(git commit -q "$@" 2>&1); then
      stop "git commit failed (a commit hook?): $(printf '%s\n' "$out" | tail -n 5 | join)"
    fi
    echo "COMMIT: $(git log -1 --format='%h %s') ($(git show --stat --format= HEAD | tail -n 1 | sed 's/^ *//'))"
  fi
fi

if [ "$no_push" -eq 1 ]; then
  echo "RESULT: OK (committed locally, nothing pushed)"
  exit 0
fi

# 2. Fetch the base branch and the remote copy of this branch (a pattern that matches nothing is not an error)
set -- "+refs/heads/$branch*:refs/remotes/origin/$branch*"
[ -n "$base" ] && set -- "+refs/heads/$base:refs/remotes/origin/$base" "$@"
[ -n "$merge_branch" ] && set -- "$@" "+refs/heads/$merge_branch*:refs/remotes/origin/$merge_branch*"
sh "$here/fetch.sh" -q --no-tags origin "$@" 2>/dev/null
status=$?
case "$status" in
  0) ;;
  77) stop "AUTH FAILED: GitLab refused the credentials of this machine, or got none (COMMANDES.md, section \"Identifiants GitLab\"); what is committed stays committed" ;;
  124) stop "GitLab did not answer within ${FETCH_TIMEOUT:-30} s (VPN or network); what is committed stays committed" ;;
  *) stop "git fetch failed (status $status); what is committed stays committed" ;;
esac

# Merges a ref, or aborts the merge and stops with the conflicting files
merge() {
  ref=$1
  label=$2
  if ! out=$(git merge --no-edit "$ref" 2>&1); then
    conflicts=$(git diff --name-only --diff-filter=U | join)
    if [ -f "$gitdir/MERGE_HEAD" ]; then
      git merge --abort >/dev/null 2>&1
      stop "CONFLICT while merging $label ($ref) in $conflicts: merge aborted, nothing is lost; resolve it in Rider (git merge $ref), then run again"
    fi
    stop "git refused to merge $label ($ref): $(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | head -n 3 | join)"
  fi
}

# 3. Remote copy of the branch: commits pushed from another computer
if git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
  counts=$(git rev-list --left-right --count "HEAD...origin/$branch")
  ahead=${counts%%[!0-9]*}
  behind=${counts##*[!0-9]}
  if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ]; then
    out=$(git merge -q --ff-only "origin/$branch" 2>&1) ||
      stop "git refused to bring the $behind commits of origin/$branch: $(printf '%s\n' "$out" | head -n 3 | join)"
    echo "REMOTE: $behind commits of origin/$branch brought in (pushed from another computer)"
  elif [ "$protected" -eq 1 ] && [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    stop "the local $branch has $ahead commits that origin/$branch does not have: nothing was merged; /push puts them on a branch of their own and brings $branch back to origin/$branch"
  elif [ "$behind" -gt 0 ]; then
    merge "origin/$branch" "the $behind commits pushed on origin/$branch from another computer"
    echo "REMOTE: the $behind commits of origin/$branch merged (pushed from another computer)"
  else
    echo "REMOTE: nothing new on origin/$branch"
  fi
else
  echo "REMOTE: origin/$branch does not exist yet (first push)"
fi

# 4. Base branch, by merge
if [ "$with_base" -eq 1 ] && [ -n "$base" ]; then
  new=$(git rev-list --count "HEAD..origin/$base")
  if [ "$new" -gt 0 ]; then
    merge "origin/$base" "the $new new commits of $base"
    echo "BASE: the $new new commits of origin/$base merged"
  else
    echo "BASE: up to date with origin/$base"
  fi
fi

# 4b. Another branch asked by the developer (a hotfix, a teammate's branch), by merge: its copy on origin, otherwise
# the local branch
if [ -n "$merge_branch" ]; then
  if git rev-parse -q --verify "refs/remotes/origin/$merge_branch" >/dev/null; then
    ref="origin/$merge_branch"
  elif git rev-parse -q --verify "refs/heads/$merge_branch" >/dev/null; then
    ref=$merge_branch
    echo "WARNING: $merge_branch is not on origin: the local branch is merged"
  else
    stop "no branch $merge_branch on origin nor here: check its name (git branch -a)"
  fi
  if git merge-base --is-ancestor "$ref" HEAD; then
    echo "MERGED: $ref is already in $branch"
  else
    new=$(git rev-list --count "HEAD..$ref")
    before=$(git rev-parse HEAD)
    merge "$ref" "the branch $merge_branch"
    echo "MERGED: the $new commits of $ref merged into $branch"
    git diff --stat "$before" HEAD | tail -n 1 | sed 's/^ */MERGED FILES: /'
  fi
fi

if [ "$sync_only" -eq 1 ]; then
  echo "RESULT: OK (synchronized, nothing committed or pushed)"
  exit 0
fi

# 5. Push, never forced
if git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null &&
  [ "$(git rev-list --count "origin/$branch..HEAD")" -eq 0 ] &&
  git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  echo "PUSH: nothing to push, origin/$branch is up to date"
  echo "RESULT: OK"
  exit 0
fi

# The last gate before GitLab, without the model: no secret, no conflict marker, no paid package (diff-guard.sh)
if [ -n "$base" ]; then
  if ! sh "$here/diff-guard.sh" "origin/$base"; then
    stop "the pre-push check refused the push (GUARD lines above): nothing was pushed, what is committed stays committed"
  fi
fi

kill_tree() {
  for child in $(pgrep -P "$1" 2>/dev/null); do
    kill_tree "$child"
  done
  kill "$1" 2>/dev/null
}
log=$(mktemp "${TMPDIR:-/tmp}/ship.XXXXXX") || stop "no temporary file"
trap 'rm -f "$log"' EXIT
git push -u origin "refs/heads/$branch:refs/heads/$branch" </dev/null >"$log" 2>&1 &
pid=$!
( sleep "$PUSH_TIMEOUT"; kill_tree "$pid" ) </dev/null >/dev/null 2>&1 &
watchdog=$!
wait "$pid" 2>/dev/null
status=$?
if kill -0 "$watchdog" 2>/dev/null; then
  kill_tree "$watchdog"
else
  status=124
fi
if [ "$status" -ne 0 ]; then
  if [ "$status" -eq 124 ]; then
    stop "the push got no answer within $PUSH_TIMEOUT s (VPN or network); what is committed stays committed"
  elif grep -qiE 'could not read (username|password)|terminal prompts disabled|authentication failed|access denied|returned error: 40[13]|permission denied \(publickey|host key verification failed' "$log"; then
    stop "AUTH FAILED: GitLab refused the credentials of this machine, or got none (COMMANDES.md, section \"Identifiants GitLab\"); what is committed stays committed"
  elif grep -qiE 'rejected|non-fast-forward|fetch first' "$log"; then
    stop "push rejected: origin/$branch changed in the meantime; run again (the new commits will be merged first)"
  fi
  stop "git push failed: $(grep -v '^remote: *$' "$log" | head -n 3 | join)"
fi
echo "PUSH: OK, origin/$branch at $(git rev-parse --short HEAD)"
link=$(grep -oE 'https?://[^ ]*merge_requests[^ ]*' "$log" | head -n 1)
[ -n "$link" ] && echo "MR LINK: $link"
echo "RESULT: OK"
exit 0
