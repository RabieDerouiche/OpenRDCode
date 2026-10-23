#!/bin/sh
# Prints the base branch of a branch, without "origin/": the branch it was started from when branch.sh created it from
# another branch than develop (/go … depuis <branch>), recorded in the git configuration of the repository
# (branch.<name>.opencode-base), as long as origin still has it; otherwise origin/develop, origin/main or origin/master,
# the first that exists. Prints nothing when there is none. Read-only, no fetch.
# The base is what a ticket branch is compared with (diff, review, check before the push), what ship.sh --base merges,
# and the target of its merge request.
# Usage: base.sh [--why] [--default] [<branch>]     (default: the current branch)
#   --why      a second line says where the base comes from: "recorded", "default", or "recorded <X> gone: default"
#   --default  the default base only (develop, main or master), whatever the branch recorded

why=0
default_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --why) why=1; shift ;;
    --default) default_only=1; shift ;;
    *) break ;;
  esac
done
branch=${1:-$(git branch --show-current 2>/dev/null)}

recorded=""
[ "$default_only" -eq 0 ] && [ -n "$branch" ] && recorded=$(git config --get "branch.$branch.opencode-base" 2>/dev/null)
if [ -n "$recorded" ] && git rev-parse -q --verify "refs/remotes/origin/$recorded" >/dev/null; then
  echo "$recorded"
  [ "$why" -eq 1 ] && echo "recorded"
  exit 0
fi
for candidate in develop main master; do
  if git rev-parse -q --verify "refs/remotes/origin/$candidate" >/dev/null; then
    echo "$candidate"
    if [ "$why" -eq 1 ]; then
      if [ -n "$recorded" ]; then echo "recorded $recorded gone: default"; else echo "default"; fi
    fi
    exit 0
  fi
done
exit 0
