#!/bin/sh
# For /outil abandon: undoes the ticket of the current branch, started by mistake (wrong repository, wrong ticket),
# without ever losing work. It refuses a branch that holds anything of its own: a commit that its base does not have,
# or an uncommitted or untracked file. Otherwise it deletes the ticket sheet of the branch, goes back to the base (in
# the main checkout: the base branch, brought to origin by fast-forward only; in a worktree, where the base is checked
# out in the main checkout: a detached HEAD at origin/<base>), then deletes the local branch with `git branch -d`
# (never a branch with unmerged work). Nothing changes on GitLab or in Jira.
#   abandon.sh --check   says what would be deleted, changes nothing ("WOULD DELETE:" lines), or one "STOP:" line
#   abandon.sh           does it: "DELETED:", "SWITCHED:" lines, then "PUSHED:" when the branch is on origin too and
#                        "WORKTREE:" when this folder is a worktree that now holds nothing
# Exit 1 with one "STOP: <reason>" line when it refuses.
# Usage: abandon.sh [--check]

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

stop() {
  echo "STOP: $*"
  exit 1
}

check=0
[ "$1" = --check ] && check=1
here=$(cd "$(dirname "$0")" && pwd)
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not a git repository"
cd "$(git rev-parse --show-toplevel)" || exit 1

branch=$(git branch --show-current)
case "$branch" in
  "") stop "detached HEAD: there is no branch to abandon" ;;
  develop|master|main) stop "nothing to abandon on $branch" ;;
esac
git rev-parse -q --verify MERGE_HEAD >/dev/null && stop "a merge is in progress: finish it or abort it first (git merge --abort)"

# the base of the branch (recorded with /go … depuis, otherwise develop, main or master), up to date
base=$(sh "$here/base.sh" "$branch")
sh "$here/fetch.sh" -q --no-tags origin "+refs/heads/$base:refs/remotes/origin/$base" >/dev/null 2>&1
git rev-parse -q --verify "refs/remotes/origin/$base" >/dev/null || stop "no origin/$base to go back to"

# what the branch holds of its own: commits that neither its base nor its copy on origin had before it, and files
dirty=$(git status --porcelain | head -n 10 | cut -c4- | tr '\n' ' ')
[ -z "$dirty" ] || stop "uncommitted or untracked files: $dirty— commit them on a branch of their own (/push) or remove them yourself; nothing deleted"
ahead=$(git rev-list --count "refs/remotes/origin/$base..HEAD")
[ "$ahead" -eq 0 ] || stop "$branch has $ahead commits that origin/$base does not have: $(git log --oneline -3 "refs/remotes/origin/$base..HEAD" | tr '\n' ';' | sed 's/;$//')$([ "$ahead" -gt 3 ] && echo "; …") — never deleted here: push them (/push) or delete the branch yourself"

common=$(git rev-parse --git-common-dir) && common=$(cd "$common" && pwd)
gitdir=$(git rev-parse --absolute-git-dir)
key=$(printf '%s\n' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
sheet=""
[ -n "$key" ] && [ -f "$common/opencode-tickets/$key.md" ] && sheet="$common/opencode-tickets/$key.md"
worktree=no
[ "$gitdir" = "$common" ] || worktree=yes
upstream=$(git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null && echo yes)

if [ "$check" -eq 1 ]; then
  echo "WOULD DELETE: the local branch $branch (nothing of its own: 0 commits ahead of origin/$base, no uncommitted file)"
  [ -n "$sheet" ] && echo "WOULD DELETE: its ticket sheet $sheet"
  if [ "$worktree" = yes ]; then
    echo "WOULD SWITCH: this worktree to a detached HEAD at origin/$base"
  else
    echo "WOULD SWITCH: to $base, brought to origin/$base"
  fi
  [ -n "$upstream" ] && echo "PUSHED: origin/$branch exists too: it stays (delete it from the Branches page of GitLab)"
  exit 0
fi

if [ "$worktree" = yes ]; then
  sh "$here/transient.sh" git switch -q --detach "refs/remotes/origin/$base" >/dev/null || stop "git could not leave $branch: nothing deleted"
  echo "SWITCHED: this worktree to a detached HEAD at origin/$base"
else
  sh "$here/transient.sh" git switch -q "$base" >/dev/null || sh "$here/transient.sh" git switch -q -c "$base" "refs/remotes/origin/$base" >/dev/null ||
    stop "git could not switch to $base (is it checked out in another worktree?): nothing deleted"
  if sh "$here/transient.sh" git merge -q --ff-only "refs/remotes/origin/$base" >/dev/null; then
    echo "SWITCHED: to $base, at origin/$base"
  else
    echo "SWITCHED: to $base (it has commits of its own: not moved to origin/$base)"
  fi
fi
[ -n "$sheet" ] && rm -f "$sheet" && echo "DELETED: the ticket sheet $sheet"
if git branch -q -d "$branch" 2>/dev/null; then
  echo "DELETED: the local branch $branch"
else
  echo "WARNING: git kept the branch $branch (it sees work that is not merged): delete it yourself if you are sure"
fi
[ -n "$upstream" ] && echo "PUSHED: origin/$branch exists too: it stays (delete it from the Branches page of GitLab)"
[ "$worktree" = yes ] && echo "WORKTREE: $(basename "$(pwd)") holds nothing now: remove it from the main checkout (git worktree remove $(pwd))"
exit 0
