#!/bin/sh
# Updates the ticket sheet of the current branch (.git/opencode-tickets/<KEY>.md) in one call. An agent that ticks a
# step with the edit tool must rebuild the exact lines of the sheet: a line that changed in between (a subagent
# updated "Tests attendus", I edited the sheet) makes the edit fail and the step stays unchecked. The date of the
# "## Suivi" lines is added here. The texts are taken as they are (no escape is interpreted).
# Usage:
#   ticket-sheet.sh tick <N> ["<suivi line>"]   check step N of "## Plan" (`- [ ] N.` -> `- [x] N.`), then append
#                                                "- <date> <suivi line>" at the end of "## Suivi"
#   ticket-sheet.sh decision "<decision>"        append "- <decision>" to "## Décisions" (created before "## Suivi")
#   ticket-sheet.sh suivi "<line>"               append "- <date> <line>" at the end of "## Suivi"
#   ticket-sheet.sh plan                         print the steps of "## Plan"
# Every write ends by printing the steps of "## Plan", so that the agent sees what is checked.

LC_ALL=C
export LC_ALL

action=$1
[ $# -gt 0 ] && shift

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Ticket sheet: not a git repository"
  exit 0
fi
root=$(git rev-parse --show-toplevel)
branch=$(git symbolic-ref --short -q HEAD)
key=$(printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -1)
if [ -z "$key" ]; then
  echo "Ticket sheet: none (branch ${branch:-detached HEAD} has no Jira key)"
  exit 0
fi
sheet="$root/.git/opencode-tickets/$key.md"
if [ ! -f "$sheet" ]; then
  echo "Ticket sheet: none for $key ($sheet does not exist; /ticket $key creates it)"
  exit 0
fi

now=$(date '+%Y-%m-%d %H:%M')
tmp="$sheet.tmp.$$"
trap 'rm -f "$tmp" "$tmp.status"' EXIT
trap 'exit 1' INT TERM

print_plan() {
  echo "Plan of $key:"
  awk '/^## / { inplan = ($0 ~ /^## Plan[[:space:]]*$/); next } inplan && /^[[:space:]]*- \[[ xX]\]/ { print }' "$sheet"
}

# Appends a line at the end of a section (before the blank lines and the next "## " heading); a missing section is
# created before "## Suivi", or at the end of the file. The line comes from the environment (LINE): awk -v would
# interpret backslashes.
append() {
  SECTION=$1 LINE=$2 awk '
    BEGIN { section = ENVIRON["SECTION"]; line = ENVIRON["LINE"]; n = 0 }
    { text[++n] = $0 }
    END {
      start = 0
      for (i = 1; i <= n; i++) if (text[i] ~ ("^## " section "[[:space:]]*$")) { start = i; break }
      if (start == 0) {
        # missing section: before "## Suivi", otherwise at the end
        before = 0
        for (i = 1; i <= n; i++) if (text[i] ~ /^## Suivi[[:space:]]*$/) { before = i; break }
        for (i = 1; i <= n; i++) {
          if (i == before) { print "## " section; print line; print "" }
          print text[i]
        }
        if (before == 0) { if (n > 0 && text[n] != "") print ""; print "## " section; print line }
        exit
      }
      stop = n + 1
      for (i = start + 1; i <= n; i++) if (text[i] ~ /^## /) { stop = i; break }
      last = start
      for (i = start + 1; i < stop; i++) if (text[i] !~ /^[[:space:]]*$/) last = i
      for (i = 1; i <= n; i++) {
        # the placeholder line of a new sheet, "(...)", goes away with the first real line
        if (!(i > start && i <= last && text[i] ~ /^\(.*\)[[:space:]]*$/)) print text[i]
        if (i == last) print line
      }
    }' "$sheet" > "$tmp" && mv "$tmp" "$sheet"
}

case "$action" in
  tick)
    step=$1
    suivi=$2
    case "$step" in
      ''|*[!0-9]*) echo "Usage: ticket-sheet.sh tick <step number> [\"<suivi line>\"]"; exit 0 ;;
    esac
    STATUS="$tmp.status" STEP=$step awk '
      BEGIN { step = ENVIRON["STEP"]; found = "" }
      /^## / { inplan = ($0 ~ /^## Plan[[:space:]]*$/) }
      inplan && found == "" && $0 ~ ("^[[:space:]]*- \\[[ xX]\\] " step "[.)]") {
        if ($0 ~ /^[[:space:]]*- \[ \]/) { sub(/\[ \]/, "[x]"); found = "ticked" } else found = "already"
      }
      { print }
      END { print (found == "" ? "missing" : found) > (ENVIRON["STATUS"]) }
    ' "$sheet" > "$tmp"
    status=$(cat "$tmp.status" 2>/dev/null)
    case "$status" in
      ticked) mv "$tmp" "$sheet"; echo "Step $step of $key: checked." ;;
      already) rm -f "$tmp"; echo "Step $step of $key: already checked." ;;
      *) rm -f "$tmp"; echo "Step $step of $key: NOT FOUND in \"## Plan\" (nothing changed)."; print_plan; exit 0 ;;
    esac
    [ -n "$suivi" ] && append "Suivi" "- $now $suivi" && printf 'Suivi: - %s %s\n' "$now" "$suivi"
    print_plan
    ;;
  decision)
    [ -n "$1" ] || { echo "Usage: ticket-sheet.sh decision \"<topic> : <choice> (<origin>)\""; exit 0; }
    append "Décisions" "- $1" && printf 'Décision added: - %s\n' "$1"
    print_plan
    ;;
  suivi)
    [ -n "$1" ] || { echo "Usage: ticket-sheet.sh suivi \"<line>\""; exit 0; }
    append "Suivi" "- $now $1" && printf 'Suivi: - %s %s\n' "$now" "$1"
    print_plan
    ;;
  plan)
    print_plan
    ;;
  *)
    echo "Usage: ticket-sheet.sh tick <N> [\"<suivi line>\"] | decision \"<decision>\" | suivi \"<line>\" | plan"
    ;;
esac
exit 0
