#!/bin/sh
# Lists what changed on the production branch of one repository between two points (read-only).
# Usage: release-commits.sh <repository path> [from: commit hash or YYYY-MM-DD] [to: commit or ref, default origin/master]
# Output: repository name, resolved range, merged merge requests, commits, Jira keys, version changes.

repo="$1"
from="$2"
to="$3"

if [ -z "$repo" ] || ! cd "$repo" 2>/dev/null; then
  echo "ERROR: repository folder not found: $repo"
  exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repository: $repo"
  exit 0
fi

name=$(basename "$(git rev-parse --show-toplevel)")

# Production branch: origin/master, otherwise origin/main
prod="master"
git fetch -q origin master >/dev/null 2>&1 || { prod="main"; git fetch -q origin main >/dev/null 2>&1; }
[ -z "$to" ] && to="origin/$prod"

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
git log --format='%s%n%b' $range_args | grep -o -E '[A-Z][A-Z0-9]+-[0-9]+' | sort -u | tr '\n' ' '
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
