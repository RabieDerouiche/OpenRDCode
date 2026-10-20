#!/bin/sh
# Lists what changed on the production branch of one repository between two points (read-only).
# Usage: release-commits.sh <repository path> [from: commit hash or YYYY-MM-DD] [to: commit or ref, default origin/master]
#        release-commits.sh <repository path> --head   only the repository root and the production branch head (after
#                                                      a fetch): the starting point of /release-notes
# Output: repository name, resolved range, merged merge requests, commits, Jira keys, version changes.

here=$(cd "$(dirname "$0")" && pwd)
repo="$1"
from="$2"
to="$3"
# A leading ~ typed by the user arrives quoted: expand it here
# shellcheck disable=SC2088 # a literal ~/ is matched on purpose
case "$repo" in
  "~") repo=$HOME ;;
  "~/"*) repo="$HOME/${repo#"~/"}" ;;
esac

if [ -z "$repo" ] || ! cd "$repo" 2>/dev/null; then
  echo "ERROR: repository folder not found: $repo"
  exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repository: $repo"
  exit 0
fi

name=$(basename "$(git rev-parse --show-toplevel)")

# Production branch: origin/master, otherwise origin/main. The fetch never asks for credentials and gives up after
# 30 s (fetch.sh): the head is then the one of the last fetch, and the output says so.
prod="master"
if ! git rev-parse -q --verify refs/remotes/origin/master >/dev/null && git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
  prod="main"
fi
fetched="after fetch"
sh "$here/fetch.sh" -q origin "$prod" 2>/dev/null
status=$?
if [ "$status" = 124 ]; then
  fetched="as of the last fetch: GitLab did not answer within 30 s"
elif [ "$status" = 77 ]; then
  fetched="as of the last fetch: GitLab refused the credentials of the machine that hosts OpenCode, or got none"
elif [ "$status" != 0 ]; then
  if [ "$prod" = master ] && sh "$here/fetch.sh" -q origin main 2>/dev/null; then
    prod="main"
  else
    fetched="as of the last fetch: the fetch failed"
  fi
fi
[ -z "$to" ] && to="origin/$prod"

if [ "$from" = "--head" ]; then
  echo "Repository: $name"
  echo "Repository path: $(git rev-parse --show-toplevel)"
  echo "Production branch: origin/$prod"
  echo "Production head ($fetched): $(git log -1 --format='%H %cs %s' "origin/$prod" 2>/dev/null || echo 'none')"
  exit 0
fi

if ! to_hash=$(git rev-parse --verify --quiet "$to^{commit}"); then
  echo "Repository: $name"
  echo "ERROR: invalid 'to' ref: $to"
  exit 0
fi

range_args=""
range_label=""
case "$from" in
  "")
    echo "Repository: $name"
    echo "ERROR: missing 'from' (previous deployed commit or date YYYY-MM-DD)"
    exit 0
    ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    range_args="--since=$from $to_hash"
    range_label="since $from (date) -> $(git log -1 --format=%h "$to_hash") (included)"
    ;;
  *)
    if ! from_hash=$(git rev-parse --verify --quiet "$from^{commit}"); then
      echo "Repository: $name"
      echo "ERROR: invalid 'from' ref: $from"
      exit 0
    fi
    range_args="$from_hash..$to_hash"
    range_label="$(git log -1 --format=%h "$from_hash") (excluded) -> $(git log -1 --format=%h "$to_hash") (included)"
    ;;
esac

echo "Repository: $name"
echo "Production branch: origin/$prod"
echo "Range: $range_label"
echo "Deployed commit: $to_hash ($(git log -1 --format=%cs "$to_hash"))"
echo
echo "## Merged merge requests"
# shellcheck disable=SC2086
git log --first-parent --merges --format='%h%x09%cs%x09%s' $range_args
echo
echo "## Commits"
# shellcheck disable=SC2086
git log --no-merges --format='%h%x09%an%x09%s' $range_args
echo
echo "## Jira keys"
# shellcheck disable=SC2086
git log --format='%s%n%b' $range_args | grep -o -E '[A-Z][A-Z0-9_]+-[0-9]+' | sort -u | tr '\n' ' '
echo
echo
echo "## Version changes (csproj, Directory.Packages.props, package.json)"
case "$from" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    first=$(git rev-list --since="$from" --reverse "$to_hash" | head -1)
    base=$(git rev-parse --verify --quiet "$first^" 2>/dev/null)
    ;;
  *) base="$from_hash" ;;
esac
if [ -n "$base" ]; then
  git diff "$base" "$to_hash" -- '*.csproj' 'Directory.Packages.props' 'Directory.Build.props' 'package.json' '*/package.json' \
    | grep -E '^[+-][[:space:]]*(<Version>|<VersionPrefix>|<PackageVersion |<PackageReference |"version":)' \
    | grep -v -E '^(\+\+\+|---)' | head -40
fi
