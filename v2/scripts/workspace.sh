#!/bin/sh
# Several tickets of one repository at the same time, each in its own folder (a git worktree) with its own OpenCode
# sessions. OpenCode 1.19 web no longer offers to create one: the layout that had the option was retired on
# 2026-09-14, and the new layout shows its workspace selector only in development builds. Run by the developer in a
# terminal; every agent is refused this script (permission rules).
#   new <KEY | name>     creates ~/worktrees/<repository>/<KEY | name> from the up-to-date base branch (origin/develop,
#                        otherwise origin/main or origin/master), on a detached HEAD: /go <KEY> in that folder puts it
#                        on the branch of the ticket (new, or the existing one with its ticket sheet). Prints the
#                        folder and the ADDRESS that opens a new OpenCode session in it: the OpenCode address in the
#                        browser (up to the port) followed by that path.
#   list                 the worktrees of the repository: folder, branch, uncommitted files, commits not pushed, address
#   remove <KEY | name>  removes a worktree folder; refused while it holds uncommitted files, or commits that are on
#                        no branch. Its branch stays (here and on GitLab): the merge request needs it.
# Run it from the repository (its main checkout or any of its worktrees). Ticket sheets are shared by all of them.
# Output: "WORKSPACE:", "ADDRESS:", "REMOVED:", "NOTE:", "WARNING:" lines (exit 0), or one "STOP: <reason>" line (exit 1).
# Usage: workspace.sh new <KEY | name> | list | remove <KEY | name>

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

action=$1
name=$2
here=$(dirname "$0")

stop() {
  echo "STOP: $1"
  exit 1
}

case "$action" in
  new|remove)
    [ -n "$name" ] || stop "a name is needed: workspace.sh $action <KEY | name> (a Jira key such as ABC-123, or a short word)"
    printf '%s' "$name" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' ||
      stop "\"$name\" is not a valid name: letters, digits, dot, hyphen and underscore only (a Jira key such as ABC-123)" ;;
  list) ;;
  *) stop "usage: workspace.sh new <KEY | name> | list | remove <KEY | name>" ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not in a git repository: cd into the repository first"
top=$(git rev-parse --show-toplevel)
common=$(git rev-parse --git-common-dir 2>/dev/null) && common=$(cd "$common" && pwd -P)
[ "$(basename "$common")" = .git ] || stop "unusual repository layout ($common): worktrees are made from a normal clone"
main=$(dirname "$common")
repo=$(basename "$main")
folder="$HOME/worktrees/$repo"

# The path after the OpenCode address that opens a new session in a folder: /<folder in base64url>/session
address() {
  printf '/%s/session\n' "$(printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_')"
}

# One line per worktree of the repository: "<path>|<branch or empty>|<prunable or empty>", the main checkout first
worktrees() {
  git worktree list --porcelain | awk '
    /^worktree / { if (path != "") print path "|" branch "|" gone; path = substr($0, 10); branch = ""; gone = "" }
    /^branch refs\/heads\// { branch = substr($0, 19) }
    /^prunable/ { gone = "prunable" }
    END { if (path != "") print path "|" branch "|" gone }'
}

# "3 uncommitted files, 2 commits not pushed" for the worktree at $1 on branch $2 (empty: detached)
state() {
  dirty=$(git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$2" ] && git -C "$1" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
    ahead=$(git -C "$1" rev-list --count '@{u}..HEAD' 2>/dev/null)
    pushed="${ahead:-0} commits not pushed"
    [ "${ahead:-0}" -eq 0 ] && pushed="pushed"
  elif [ -n "$2" ]; then
    ahead=$(git -C "$1" rev-list --count HEAD --not --remotes 2>/dev/null)
    pushed="never pushed (${ahead:-0} commits of its own)"
  else
    ahead=$(git -C "$1" rev-list --count HEAD --not --branches --remotes 2>/dev/null)
    pushed="detached HEAD at $(git -C "$1" rev-parse --short HEAD 2>/dev/null)"
    [ "${ahead:-0}" -gt 0 ] && pushed="$pushed, $ahead commits on no branch"
  fi
  printf '%s uncommitted files, %s\n' "$dirty" "$pushed"
}

case "$action" in
  list)
    first=1
    worktrees | while IFS='|' read -r path branch gone; do
      if [ "$first" = 1 ]; then
        first=0
        echo "Main checkout: $path ($([ -n "$branch" ] && echo "branch $branch" || echo "detached HEAD"))"
        continue
      fi
      echo ""
      echo "$(basename "$path")   $path"
      if [ -n "$gone" ]; then
        echo "  folder missing: git worktree prune forgets it"
        continue
      fi
      echo "  ${branch:+branch $branch: }$(state "$path" "$branch")"
      echo "  address: $(address "$path")"
    done
    [ "$(worktrees | wc -l)" -gt 1 ] || echo "No worktree yet: workspace.sh new <KEY>"
    exit 0 ;;

  new)
    path="$folder/$name"
    [ -e "$path" ] && stop "the folder $path already exists (workspace.sh list shows the worktrees)"
    # A branch of the key already checked out in a folder: one ticket per folder, continue it there
    if printf '%s' "$name" | grep -qE '^[A-Z][A-Z0-9_]+-[0-9]+$'; then
      regex="(^|[^A-Za-z0-9])$name([^0-9]|$)"
      open=$(worktrees | awk -F'|' -v r="$regex" '$2 ~ r { print $2 " is checked out in " $1; exit }')
      [ -n "$open" ] && stop "the branch $open: continue the ticket in that folder, or switch that folder to develop first (git switch develop, with nothing uncommitted)"
    fi
    sh "$here/fetch.sh" -q --no-tags origin 2>/dev/null
    case $? in
      0) ;;
      77) stop "AUTH FAILED: GitLab refused the credentials of this machine, or got none (COMMANDES.md, section \"Identifiants GitLab\"); nothing was created" ;;
      *) echo "WARNING: fetch failed or timed out: the base branch is as of the last fetch" ;;
    esac
    base=""
    for candidate in develop main master; do
      if git rev-parse -q --verify "refs/remotes/origin/$candidate" >/dev/null; then
        base=$candidate
        break
      fi
    done
    [ -n "$base" ] || stop "no origin/develop, origin/main or origin/master to start the folder from"
    mkdir -p "$folder" || stop "cannot create $folder"
    path="$(cd "$folder" && pwd -P)/$name"
    if ! out=$(git worktree add -q --detach "$path" "origin/$base" 2>&1); then
      rmdir "$folder" 2>/dev/null
      stop "git could not create the worktree: $(printf '%s' "$out" | tail -n 1)"
    fi
    echo "WORKSPACE: $path (from origin/$base, $(git log -1 --format='%h, %cs' "origin/$base"); detached HEAD: /go $name puts it on the branch of the ticket)"
    echo "ADDRESS: $(address "$path")"
    # Files ignored by git exist only where they were made: name those of the main checkout that a build, a test or
    # a run may need (local settings), never their content
    local_files=$(git -C "$main" ls-files --others --ignored --exclude-standard --directory 2>/dev/null |
      grep -vE '(^|/)(bin|obj|\.vs|\.idea|\.vscode|node_modules|TestResults|packages|dist|out|coverage|\.angular|\.nuget)/' |
      grep -vE '(\.user|\.suo|\.log|\.DS_Store|\.swp)$' | head -n 8 | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }')
    [ -n "$local_files" ] && echo "NOTE: ignored by git, so only in the main checkout (copy what the build or the tests need): $local_files"
    echo "NEXT: open the OpenCode address in the browser (up to the port), followed by the ADDRESS path; in that new session, /go $name"
    exit 0 ;;

  remove)
    match=$(worktrees | tail -n +2 | awk -F'|' -v n="$name" '{ p = $1; sub(/.*\//, "", p) } p == n')
    [ -n "$match" ] || stop "no worktree named $name in this repository (workspace.sh list shows them)"
    [ "$(printf '%s\n' "$match" | wc -l)" -eq 1 ] || stop "several worktrees are named $name: remove the right one with git worktree remove <path>"
    path=${match%%|*}
    rest=${match#*|}
    branch=${rest%%|*}
    gone=${rest#*|}
    if [ -n "$gone" ]; then
      git worktree prune
      echo "REMOVED: $path (its folder was already gone; git forgot it)"
      exit 0
    fi
    [ "$(cd "$top" && pwd -P)" = "$(cd "$path" && pwd -P)" ] && stop "this terminal is in the folder to remove: cd $main first"
    dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$dirty" -eq 0 ] || stop "$dirty uncommitted files in $path: deliver them (/fix in a session of that folder) or discard them first; nothing was removed"
    if [ -z "$branch" ]; then
      orphans=$(git -C "$path" rev-list --count HEAD --not --branches --remotes 2>/dev/null)
      [ "${orphans:-0}" -eq 0 ] || stop "$orphans commits of $path are on no branch (detached HEAD) and would be lost: put them on a branch first; nothing was removed"
    fi
    if ! out=$(git worktree remove "$path" 2>&1); then
      stop "git could not remove the worktree: $(printf '%s' "$out" | tail -n 1)"
    fi
    rmdir "$folder" 2>/dev/null
    if [ -n "$branch" ]; then
      unpushed=$(git rev-list --count "refs/heads/$branch" --not --remotes 2>/dev/null)
      key=$(printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
      echo "REMOVED: $path (the branch $branch stays, with its ticket sheet)"
      if [ "${unpushed:-0}" -gt 0 ]; then
        echo "WARNING: $unpushed commits of $branch are not pushed yet: they are safe in the branch${key:+; /go $key in a session of the main checkout (or of a new worktree) delivers them}"
      fi
    else
      echo "REMOVED: $path"
    fi
    echo "NOTE: its OpenCode sessions stay in the list without their folder: archive them (home page of OpenCode)"
    exit 0 ;;
esac
