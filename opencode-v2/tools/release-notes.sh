#!/bin/sh
# The release notes of the pack (RELEASE-NOTES.md), checked by the CI:
#   check                each entry, newest first: "## YYYY-MM-DD HH:MM — <title>", then its four lines in this order,
#                        none empty: "- **Ajouté** : ", "- **Changé** : ", "- **Retiré** : ", "- **But** : "
#   commits <range>      each commit of the range (git rev-list <range>, merges left out) that changes a file of
#                        opencode-v2/ changes RELEASE-NOTES.md too: one entry per commit of the pack
# Output: "RELEASE NOTES: OK (<n> entries)" or "RELEASE NOTES: OK (<n> commits of the pack, each with its note)";
# "FAIL: " lines, then exit 1. Usage, from opencode-v2/: sh tools/release-notes.sh check | commits <range>
LC_ALL=C.UTF-8
export LC_ALL
here=$(cd "$(dirname "$0")/.." && pwd)
notes="$here/RELEASE-NOTES.md"

case "$1" in
  check)
    [ -f "$notes" ] || { echo "FAIL: no RELEASE-NOTES.md in $here"; exit 1; }
    awk '
      function fail(msg) { print "FAIL: RELEASE-NOTES.md:" NR ": " msg; bad++ }
      function close_entry() {
        if (entry != "" && want <= 4) { print "FAIL: RELEASE-NOTES.md: the entry « " entry " » lacks its line « " label[want] " »"; bad++ }
      }
      BEGIN { label[1] = "- **Ajouté** : "; label[2] = "- **Changé** : "; label[3] = "- **Retiré** : "; label[4] = "- **But** : "; want = 5 }
      /^```/ { fence = !fence; next }
      fence { next }
      /^## / {
        close_entry()
        entry = substr($0, 4); want = 1; n++
        if ($0 !~ /^## [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9] — ./) fail("the heading is not « ## AAAA-MM-JJ HH:MM — titre »: " $0)
        stamp = substr($0, 4, 16)
        if (last != "" && stamp > last) fail("« " stamp " » comes after « " last " »: the newest entry goes first")
        last = stamp
        next
      }
      entry != "" && /^- \*\*/ {
        if (want > 4) { fail("a fifth line in the entry « " entry " »"); next }
        if (index($0, label[want]) != 1) { fail("« " label[want] "» expected, found: " substr($0, 1, 40)); next }
        if (length($0) <= length(label[want])) fail("« " label[want] "» is empty")
        want++
        next
      }
      END {
        close_entry()
        if (n == 0) { print "FAIL: RELEASE-NOTES.md has no entry"; bad++ }
        if (bad) exit 1
        print "RELEASE NOTES: OK (" n " entries)"
      }' "$notes"
    exit $? ;;
  commits)
    range=$2
    [ -n "$range" ] || { echo "FAIL: usage: release-notes.sh commits <range>"; exit 1; }
    cd "$here" || exit 1
    top=$(git rev-parse --show-prefix 2>/dev/null)
    top=${top%/}
    [ -n "$top" ] || top=opencode-v2
    # the paths of the commits are those of the repository: read from its root
    cd "$(git rev-parse --show-toplevel)" || exit 1
    count=0
    fails=0
    for c in $(git rev-list --no-merges "$range" 2>/dev/null); do
      files=$(git diff-tree --no-commit-id --name-only -r "$c" -- "$top/")
      [ -n "$files" ] || continue
      count=$((count + 1))
      if ! printf '%s\n' "$files" | grep -q -x -F "$top/RELEASE-NOTES.md"; then
        echo "FAIL: commit $(git log -1 --format='%h « %s »' "$c") changes the pack without its entry in RELEASE-NOTES.md"
        fails=$((fails + 1))
      fi
    done
    [ "$fails" -eq 0 ] || exit 1
    echo "RELEASE NOTES: OK ($count commits of the pack, each with its note)" ;;
  *)
    echo "FAIL: usage: release-notes.sh check | commits <range>"
    exit 1 ;;
esac
