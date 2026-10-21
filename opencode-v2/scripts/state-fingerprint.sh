#!/bin/sh
# Prints the fingerprint of the code in the working tree: the same code gives the same value, whether it is
# committed, staged or neither, and any edit changes it (counts of changed lines cannot tell an edited line, or a new
# file edited again). /check, /test, /ship and /next compare it to know whether a review or a test run is still valid.
# It hashes the list "<content id> <path>" of every file: tracked files with their current content, and untracked
# files that are not ignored (what `git add -A` would commit). Writes nothing: the index, the working tree, the
# history and the object store are not touched.
# Used by workflow-state.sh and build-test.sh. Usage: state-fingerprint.sh

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/state-fingerprint.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# Paths as they are (no octal quoting of accented names), so that they can be hashed
lsf() {
  git -c core.quotePath=false ls-files "$@"
}

# Content of the index: "<content id> <path>" (the path comes after the tab and may contain spaces)
lsf -s | awk -F '\t' '{ split($1, f, " "); print f[2] " " $2 }' > "$tmp/index"
# Working tree on top of it: deleted files, then the modified files that still exist and the untracked files,
# with the id of their current content
lsf -d > "$tmp/deleted"
lsf -m > "$tmp/modified"
lsf -o --exclude-standard > "$tmp/untracked"
# (an untracked folder ending with "/" is a nested repository: its files are not part of this one)
awk 'FILENAME == ARGV[1] { gone[$0] = 1; next } !($0 in gone) && !/\/$/ && !seen[$0]++' \
  "$tmp/deleted" "$tmp/modified" "$tmp/untracked" > "$tmp/changed"
git hash-object --stdin-paths < "$tmp/changed" > "$tmp/ids" 2>/dev/null
paste -d ' ' "$tmp/ids" "$tmp/changed" > "$tmp/current"

awk '
  FILENAME == ARGV[1] { gone[$0] = 1; next }
  FILENAME == ARGV[2] { i = index($0, " "); id[substr($0, i + 1)] = substr($0, 1, i - 1); next }
  {
    i = index($0, " "); path = substr($0, i + 1)
    if (!(path in gone) && !(path in id)) id[path] = substr($0, 1, i - 1)
  }
  END { for (path in id) print id[path] " " path }
' "$tmp/deleted" "$tmp/current" "$tmp/index" | LC_ALL=C sort | git hash-object --stdin | cut -c1-12
