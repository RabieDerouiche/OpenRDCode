#!/bin/sh
# For /check: a snapshot of the code under review, and what changed since the last /check of the ticket.
# The snapshot is a git tree written through a temporary copy of the index: the real index, the working tree, the
# branches and the history are not touched (only objects are added to the object store, like a fetch). /check writes
# its id in the ticket sheet ("arbre <id>" at the end of its "## Suivi" line); the next /check diffs the code against
# it, so that it reviews only what changed and checks that the points it raised are fixed.
# Usage: review-delta.sh

MAX_DIFF_LINES=1500

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Review snapshot: not a git repository"
  exit 0
fi
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/review-delta.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# Snapshot: the working tree as `git add -A` would stage it (untracked files included, ignored files left out)
index=$(git rev-parse --git-path index)
[ -f "$index" ] && cp "$index" "$tmp/index"
if ! GIT_INDEX_FILE="$tmp/index" git add -A >/dev/null 2>&1 || ! tree=$(GIT_INDEX_FILE="$tmp/index" git write-tree 2>/dev/null); then
  echo "Review snapshot: unavailable (git could not read the working tree)"
  exit 0
fi
short=$(printf '%s' "$tree" | cut -c1-12)
echo "Review snapshot of this code (write it as \"arbre $short\" in the /check line of the sheet): $short"

branch=$(git symbolic-ref --short -q HEAD)
key=$(printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -1)
sheet="$root/.git/opencode-tickets/$key.md"
if [ -z "$key" ] || [ ! -f "$sheet" ]; then
  echo "Last /check of this ticket: none recorded (no ticket sheet): full review"
  exit 0
fi

# Last "/check" line of "## Suivi" that recorded a snapshot
last=$(awk '/^## / { insuivi = ($0 ~ /^## Suivi[[:space:]]*$/); next } insuivi && / \/check / && /arbre [0-9a-f]+/ { line = $0 } END { print line }' "$sheet")
if [ -z "$last" ]; then
  echo "Last /check of this ticket: none recorded with a snapshot: full review"
  exit 0
fi
old=$(printf '%s\n' "$last" | sed -n 's/.*arbre \([0-9a-f][0-9a-f]*\).*/\1/p')
echo "Last /check of this ticket: ${last#- }"

# Open points of that /check: unchecked items of the last block of "## Retours /check"
awk '
  /^## / { inret = ($0 ~ /^## Retours \/check[[:space:]]*$/); next }
  inret && /^### / { for (k in item) delete item[k]; n = 0; head = $0; next }
  inret && /^[[:space:]]*- \[ \]/ { item[++n] = $0 }
  END {
    if (head == "") { print "Open points of the last /check: none recorded"; exit }
    print "Open points of the last /check (" n ", block \"" substr(head, 5) "\"):"
    for (i = 1; i <= n; i++) print item[i]
  }' "$sheet"

if ! full=$(git rev-parse -q --verify "$old^{tree}" 2>/dev/null); then
  echo "Snapshot $old of that /check is not in this clone: full review"
  exit 0
fi
if [ "$full" = "$tree" ]; then
  echo "Changes since that /check: none (same code)"
  exit 0
fi
echo "Changes since that /check (working tree included; review these, plus the open points above):"
git diff --stat=120 "$full" "$tree"
git diff "$full" "$tree" > "$tmp/diff"
lines=$(grep -c '' "$tmp/diff")
if [ "$lines" -gt "$MAX_DIFF_LINES" ]; then
  echo "DIFF TOO LARGE ($lines lines): read each file of the list above, and \`git diff $old -- <path>\` shows its change"
else
  cat "$tmp/diff"
fi
exit 0
