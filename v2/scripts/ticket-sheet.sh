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
#   ticket-sheet.sh fixed <N>[,<N>...] ["<suivi line>"]
#                                                check the points N of the last block of "## Retours /check" (the
#                                                points of the last /check), then append the "## Suivi" line
#   ticket-sheet.sh plan                         print the steps of "## Plan"
#   ticket-sheet.sh check                        check the structure /go relies on (sections, numbered steps with
#                                                their files and tests, each criterion covered by an expected test)
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
  awk '
    /^## / { inret = ($0 ~ /^## Retours \/check[[:space:]]*$/); next }
    inret && /^### / { for (k in item) delete item[k]; n = 0; head = $0; next }
    inret && /^[[:space:]]*- \[[ xX]\]/ { item[++n] = $0 }
    END { if (head != "") { print "Points of the last /check (" substr(head, 5) "):"; for (i = 1; i <= n; i++) print item[i] } }
  ' "$sheet"
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
  fixed)
    list=$1
    suivi=$2
    case "$list" in
      ''|*[!0-9,]*) echo "Usage: ticket-sheet.sh fixed <N>[,<N>...] [\"<suivi line>\"]"; exit 0 ;;
    esac
    STATUS="$tmp.status" LIST=$list awk '
      BEGIN { n = split(ENVIRON["LIST"], L, ","); for (i = 1; i <= n; i++) if (L[i] != "") want[L[i] + 0] = 1 }
      { text[++count] = $0 }
      END {
        inret = 0; lastblock = 0
        for (i = 1; i <= count; i++) {
          if (text[i] ~ /^## /) inret = (text[i] ~ /^## Retours \/check[[:space:]]*$/)
          else if (inret && text[i] ~ /^### /) lastblock = i
        }
        done = ""; missing = ""
        if (lastblock > 0) {
          for (i = lastblock + 1; i <= count && text[i] !~ /^##/; i++) {
            if (match(text[i], /^[[:space:]]*- \[[ xX]\] [0-9]+[.)]/)) {
              num = text[i]; sub(/^[[:space:]]*- \[[ xX]\] /, "", num); sub(/[.)].*$/, "", num); num += 0
              if (num in want) {
                if (text[i] ~ /^[[:space:]]*- \[ \]/) sub(/\[ \]/, "[x]", text[i])
                found[num] = 1
              }
            }
          }
        }
        for (k in want) if (!(k in found)) missing = missing (missing == "" ? "" : ",") k
        for (i = 1; i <= count; i++) print text[i]
        print (lastblock == 0 ? "noblock" : (missing == "" ? "ok" : "missing " missing)) > (ENVIRON["STATUS"])
      }' "$sheet" > "$tmp"
    status=$(cat "$tmp.status" 2>/dev/null)
    case "$status" in
      ok) mv "$tmp" "$sheet"; echo "Points $list of the last /check of $key: checked." ;;
      noblock) rm -f "$tmp"; echo "No \"## Retours /check\" block in the sheet of $key (nothing changed)."; print_plan; exit 0 ;;
      *) rm -f "$tmp"; echo "Points not found in the last /check block: ${status#missing } (nothing changed)."; print_plan; exit 0 ;;
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
  check)
    # The structure /go relies on, checked once the analyst has written the sheet: the sections, a plan of numbered
    # steps with their files and tests, every acceptance criterion covered by an expected test
    KEY=$key awk '
      function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
      NR == 1 { title = $0 }
      /^## / { section = trim(substr($0, 4)); seen[section] = 1; next }
      section == "Plan" && /^[[:space:]]*- \[[ xX]\] / {
        n = $0; sub(/^[[:space:]]*- \[[ xX]\] /, "", n)
        if (n !~ /^[0-9]+[.)]/) { problems[++np] = "a step of \"## Plan\" has no number: " trim($0); next }
        num = n; sub(/[.)].*$/, "", num); num += 0
        steps++
        if (num != steps) problems[++np] = "step " num " of \"## Plan\" comes where step " steps " was expected (steps are numbered 1, 2, 3...)"
        if ($0 !~ /fichiers *:/) warnings[++nw] = "step " num " names no file (— fichiers : ...)"
        if ($0 !~ /tests *:/) warnings[++nw] = "step " num " names no test (— tests : ...)"
        next
      }
      section ~ /^Crit/ {
        line = $0
        while (match(line, /C[0-9]+/)) {
          id = substr(line, RSTART, RLENGTH)
          before = (RSTART > 1) ? substr(line, RSTART - 1, 1) : " "
          if (before !~ /[A-Za-z0-9]/ && !(id in criteria)) { criteria[id] = 1; order[++nc] = id }
          line = substr(line, RSTART + RLENGTH)
        }
        next
      }
      section ~ /^Tests attendus/ && /^\|/ && $0 !~ /^\|[-: |]+\|?[[:space:]]*$/ {
        if ($0 ~ /\| *# *\|/ || tolower($0) ~ /\| *crit/) next
        rows++
        line = $0
        while (match(line, /C[0-9]+/)) { covered[substr(line, RSTART, RLENGTH)] = 1; line = substr(line, RSTART + RLENGTH) }
        next
      }
      END {
        if (title !~ ("^# " ENVIRON["KEY"] "( |$)")) problems[++np] = "the first line is not \"# " ENVIRON["KEY"] " - <summary>\""
        split("Résumé|Critères d'\''acceptation|Questions bloquantes|Zones de code concernées|Tests attendus|Plan|Décisions|Suivi", need, "|")
        for (i = 1; i <= 8; i++) if (!(need[i] in seen)) problems[++np] = "missing section: ## " need[i]
        if (steps == 0) problems[++np] = "no step in \"## Plan\" (- [ ] 1. <step> — fichiers : ... — tests : ...)"
        else if (steps > 7) warnings[++nw] = steps " steps: more than 7, each step should be bigger"
        if (nc == 0) problems[++np] = "no acceptance criterion (C1, C2...) in \"## Critères d'\''acceptation\""
        for (i = 1; i <= nc; i++) if (!(order[i] in covered)) problems[++np] = "criterion " order[i] " is covered by no row of \"## Tests attendus\""
        if (np == 0) print "Sheet check of " ENVIRON["KEY"] ": OK (" steps " steps, " nc " criteria, " rows + 0 " expected tests)"
        else {
          print "Sheet check of " ENVIRON["KEY"] ": " np " problem(s)"
          for (i = 1; i <= np; i++) print "- " problems[i]
        }
        for (i = 1; i <= nw; i++) print "- warning: " warnings[i]
      }
    ' "$sheet"
    ;;
  *)
    echo "Usage: ticket-sheet.sh tick <N> [\"<suivi line>\"] | fixed <N>[,<N>...] [\"<suivi line>\"] | decision \"<decision>\" | suivi \"<line>\" | plan | check"
    ;;
esac
exit 0
