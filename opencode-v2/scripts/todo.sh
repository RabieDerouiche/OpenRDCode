#!/bin/sh
# My personal todo list, kept in one Markdown file outside every repository (default ~/.config/opencode/todo.md,
# or $OPENCODE_TODO): each line "- [ ] #<id> [<YYYY-MM-DD>] <text> (ajoutée le <date>)", done lines kept 30 days.
# The file can also be edited by hand. Due dates are read from the text in French: aujourd'hui, demain,
# après-demain, lundi... dimanche (the next one), dans 3 jours, dans 2 semaines, semaine prochaine (its Monday),
# fin de semaine (Friday), fin du mois, le 24, 24/10, 24/10/2026, 24 octobre, 2026-10-24. The text is kept as typed.
# Output in French: it is shown to me as it is.
# Usage: todo.sh                          the open items, overdue first
#        todo.sh add <text>               add an item (with its due date when the text gives one)
#        todo.sh done <id>[,<id>...]      mark items as done
#        todo.sh remove <id>[,<id>...]    delete items
#        todo.sh due                      only the overdue items and those due today (reminders)
#        todo.sh count                    the number of those reminders
#        todo.sh --raw "<text>"           what I typed after /todo: "", "fait 3", "suppr 2,4", "liste", "rappels",
#                                         otherwise an item to add

LC_ALL=C
export LC_ALL

file=${OPENCODE_TODO:-$HOME/.config/opencode/todo.md}

op=$1
[ $# -gt 0 ] && shift
arg=$*
if [ "$op" = --raw ]; then
  op=raw
elif [ -z "$op" ]; then
  op=list
fi
case "$op" in
  raw | list | add | done | remove | due | count) ;;
  *) echo "Usage: todo.sh [add <texte> | done <n> | remove <n> | due | count | --raw \"<texte>\"]"; exit 0 ;;
esac

dir=$(dirname "$file")
[ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null
[ -f "$file" ] || : > "$file" 2>/dev/null
if [ ! -r "$file" ]; then
  echo "Todo : fichier illisible ($file)"
  exit 0
fi
tmp="$file.tmp.$$"
trap 'rm -f "$tmp"' EXIT

# shellcheck disable=SC1112 # a typed date may use the typographic apostrophe of macOS (aujourd’hui)
TODAY=$(date '+%Y-%m-%d') OP=$op ARG=$arg OUT=$tmp awk '
# ---------- dates: day numbers (Howard Hinnant), French names ----------
function days(y, m, d,   era, yoe, doy, doe) {
  y -= (m <= 2)
  era = int(y / 400)
  yoe = y - era * 400
  doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function iso(n,   z, era, doe, yoe, y, doy, mp, d, m) {
  z = n + 719468
  era = int(z / 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = mp < 10 ? mp + 3 : mp - 9
  y += (m <= 2)
  return sprintf("%04d-%02d-%02d", y, m, d)
}
function num(s) { return days(substr(s, 1, 4) + 0, substr(s, 6, 2) + 0, substr(s, 9, 2) + 0) }
function weekday(n) { return ((n + 3) % 7) + 1 }
function valid(y, m, d,   n) { if (m < 1 || m > 12 || d < 1 || d > 31) return 0; n = days(y, m, d); return iso(n) == sprintf("%04d-%02d-%02d", y, m, d) }
# The next date with this month and day: this year, or next year when it has passed
function next_md(m, d,   y) {
  y = substr(TODAY, 1, 4) + 0
  if (!valid(y, m, d)) return ""
  if (days(y, m, d) < TN) y++
  return valid(y, m, d) ? iso(days(y, m, d)) : ""
}
function month_of(word,   w) {
  w = word
  if (w ~ /^janv/) return 1
  if (w ~ /^f(é|e)v/) return 2
  if (w ~ /^mars/) return 3
  if (w ~ /^avr/) return 4
  if (w ~ /^mai/) return 5
  if (w ~ /^juin/) return 6
  if (w ~ /^juil/) return 7
  if (w ~ /^ao(û|u)t/) return 8
  if (w ~ /^sept/) return 9
  if (w ~ /^oct/) return 10
  if (w ~ /^nov/) return 11
  if (w ~ /^d(é|e)c/) return 12
  return 0
}
# The due date written in the text, or ""
function due_of(str,   t, s, y, m, d, n, i, k, names) {
  t = " " tolower(str) " "
  gsub(/[,.;:!?()]/, " ", t)
  if (match(t, / [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /)) {
    s = substr(t, RSTART + 1, 10)
    if (valid(substr(s, 1, 4) + 0, substr(s, 6, 2) + 0, substr(s, 9, 2) + 0)) return s
  }
  if (match(t, / [0-9][0-9]?\/[0-9][0-9]?\/[0-9][0-9]([0-9][0-9])? /)) {
    s = substr(t, RSTART + 1, RLENGTH - 2)
    split(s, k, "/")
    y = k[3] + 0
    if (y < 100) y += 2000
    if (valid(y, k[2] + 0, k[1] + 0)) return iso(days(y, k[2] + 0, k[1] + 0))
  }
  if (match(t, / [0-9][0-9]?\/[0-9][0-9]? /)) {
    s = substr(t, RSTART + 1, RLENGTH - 2)
    split(s, k, "/")
    s = next_md(k[2] + 0, k[1] + 0)
    if (s != "") return s
  }
  if (match(t, / [0-9][0-9]? (janv|f(é|e)v|mars|avr|mai|juin|juil|ao(û|u)t|sept|oct|nov|d(é|e)c)[^ ]* /)) {
    s = substr(t, RSTART + 1, RLENGTH - 2)
    split(s, k, " ")
    s = next_md(month_of(k[2]), k[1] + 0)
    if (s != "") return s
  }
  if (match(t, / le [0-9][0-9]? /)) {
    d = substr(t, RSTART + 4, RLENGTH - 5) + 0
    y = substr(TODAY, 1, 4) + 0
    m = substr(TODAY, 6, 2) + 0
    for (i = 0; i < 3; i++) {
      if (valid(y, m, d) && days(y, m, d) >= TN) return iso(days(y, m, d))
      m++
      if (m > 12) { m = 1; y++ }
    }
  }
  if (t ~ / aujourd(\047|’)?hui | ce soir | ce matin | cet apr(è|e)s-midi /) return iso(TN)
  if (t ~ / apr(è|e)s(-| )demain /) return iso(TN + 2)
  if (t ~ / demain /) return iso(TN + 1)
  if (match(t, / dans [0-9]+ jours? /)) { split(substr(t, RSTART + 1, RLENGTH - 2), k, " "); return iso(TN + k[2]) }
  if (match(t, / dans [0-9]+ semaines? /)) { split(substr(t, RSTART + 1, RLENGTH - 2), k, " "); return iso(TN + 7 * k[2]) }
  if (t ~ / dans (une|1) semaine | dans huit jours /) return iso(TN + 7)
  if (t ~ / dans quinze jours /) return iso(TN + 14)
  if (t ~ / (la )?semaine prochaine /) return iso(TN + 8 - weekday(TN))
  if (t ~ / fin de (la )?semaine /) { n = 5 - weekday(TN); if (n < 0) n += 7; return iso(TN + n) }
  if (t ~ / fin (du|de) mois /) {
    y = substr(TODAY, 1, 4) + 0
    m = substr(TODAY, 6, 2) + 0 + 1
    if (m > 12) { m = 1; y++ }
    return iso(days(y, m, 1) - 1)
  }
  split("lundi mardi mercredi jeudi vendredi samedi dimanche", names, " ")
  for (i = 1; i <= 7; i++) {
    if (index(t, " " names[i] " ")) { n = i - weekday(TN); if (n <= 0) n += 7; return iso(TN + n) }
  }
  return ""
}
# Today, tomorrow, "ven. 23/10", or "mer. 13/10/2027" in another year (French labels)
function datelabel(s,   n, wd, out) {
  n = num(s)
  split("lun. mar. mer. jeu. ven. sam. dim.", wd, " ")
  if (n == TN) return "aujourd\047hui"
  if (n == TN + 1) return "demain"
  out = wd[weekday(n)] " " substr(s, 9, 2) "/" substr(s, 6, 2)
  if (substr(s, 1, 4) != substr(TODAY, 1, 4)) out = out "/" substr(s, 1, 4)
  return out
}

# ---------- the file ----------
function parse(line,   rest, i) {
  # "- [ ] #12 2026-10-24 text (ajoutée le 2026-10-19)" -> fields of item n
  n_items++
  isdone[n_items] = (line ~ /^- \[[xX]\]/)
  rest = line
  sub(/^- \[[ xX]\][ \t]*/, "", rest)
  id[n_items] = 0
  if (match(rest, /^#[0-9]+/)) { id[n_items] = substr(rest, 2, RLENGTH - 1) + 0; rest = substr(rest, RLENGTH + 1); sub(/^[ \t]+/, "", rest) }
  due[n_items] = ""
  if (match(rest, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { due[n_items] = substr(rest, 1, 10); rest = substr(rest, 11); sub(/^[ \t]+/, "", rest) }
  meta[n_items] = ""
  if (match(rest, / \((ajoutée|faite) le [^)]*\)$/)) { meta[n_items] = substr(rest, RSTART + 1); rest = substr(rest, 1, RSTART - 1) }
  text[n_items] = rest
  if (id[n_items] > maxid) maxid = id[n_items]
}
function render(i) {
  return "- [" (isdone[i] ? "x" : " ") "] #" id[i] (due[i] != "" ? " " due[i] : "") " " text[i] (meta[i] != "" ? " " meta[i] : "")
}
# One open item under its group: its number first (for /todo fait <n>), then the text and its date
function line_of(i, with_date) {
  return "  #" id[i] "  " text[i] (with_date && due[i] != "" ? " · " datelabel(due[i]) : "")
}
function group_of(i) {
  if (due[i] == "") return "none"
  if (num(due[i]) < TN) return "late"
  if (num(due[i]) == TN) return "today"
  if (num(due[i]) <= TN + 7) return "week"
  return "later"
}
# The open items, overdue first, grouped by urgency; hint: the commands, when I typed /todo alone
function show_list(hint,   i, j, k, order, cnt, recent, g, grp) {
  cnt = 0
  for (i = 1; i <= n_items; i++) if (!isdone[i] && id[i] > 0 && text[i] != "") { cnt++; order[cnt] = i; key[i] = (due[i] != "" ? due[i] : "9999-99-99") sprintf("%08d", id[i]) }
  # insertion sort: few items
  for (j = 2; j <= cnt; j++) { k = order[j]; i = j - 1; while (i >= 1 && key[order[i]] > key[k]) { order[i + 1] = order[i]; i-- } order[i + 1] = k }
  if (cnt == 0) print "📋 Ma todo · rien à faire 🎉"
  else {
    print "📋 Ma todo · " cnt " à faire"
    g = ""
    for (j = 1; j <= cnt; j++) {
      i = order[j]
      grp = group_of(i)
      if (grp != g) {
        print ""
        if (grp == "late") print "⚠️ En retard"
        else if (grp == "today") print "🔔 Aujourd\047hui"
        else if (grp == "week") print "📅 Dans les 7 jours"
        else if (grp == "later") print "🗓️ Plus tard"
        else print "🗒️ Sans échéance"
        g = grp
      }
      print line_of(i, grp != "today")
    }
  }
  recent = 0
  for (i = 1; i <= n_items; i++) if (isdone[i] && match(meta[i], /faite le [0-9-]+/) && num(substr(meta[i], RSTART + 9, 10)) >= TN - 7) recent++
  if (recent > 0) { print ""; print "✅ " recent (recent > 1 ? " faites" : " faite") " ces 7 derniers jours" }
  if (hint) { print ""; print "✏️ /outil todo <texte> pour ajouter · ✅ /outil todo fait <n> · 🗑️ /outil todo suppr <n>" }
}
# One line: the items overdue or due today (/next, /todo rappels)
function reminders(   i, n, out) {
  n = 0; out = ""
  for (i = 1; i <= n_items; i++) if (!isdone[i] && id[i] > 0 && due[i] != "" && num(due[i]) <= TN) {
    n++
    out = out (out == "" ? "" : " ; ") "#" id[i] " " text[i] (num(due[i]) < TN ? " (en retard : " datelabel(due[i]) ")" : " (aujourd\047hui)")
  }
  reminder_count = n
  return out
}
function ids_of(s, list,   k, n, i, c) {
  gsub(/[#,;]/, " ", s)
  n = split(s, k, " ")
  c = 0
  for (i = 1; i <= n; i++) if (k[i] ~ /^[0-9]+$/) list[++c] = k[i] + 0
  return c
}
function find(want,   i) { for (i = 1; i <= n_items; i++) if (id[i] == want && id[i] > 0) return i; return 0 }

BEGIN { TODAY = ENVIRON["TODAY"]; TN = num(TODAY); op = ENVIRON["OP"]; arg = ENVIRON["ARG"]; n_items = 0; maxid = 0; header = "" }
/^- \[[ xX]\]/ { parse($0); next }
{ other[++n_other] = $0 }
END {
  sub(/^[ \t]+/, "", arg); sub(/[ \t]+$/, "", arg)
  raw = (op == "raw")
  if (op == "raw") {
    first = tolower(arg); sub(/[ \t].*$/, "", first)
    rest = arg; if (index(rest, " ")) { sub(/^[^ \t]+[ \t]+/, "", rest) } else rest = ""
    # a keyword counts only when the rest is what it expects: "/todo fait le point avec Paul" is an item to add
    numbers = (rest ~ /^[#0-9 ,;]+$/ || rest == "")
    if (arg == "" || tolower(arg) ~ /^(liste|list|voir|tout)$/) op = "list"
    else if (first ~ /^(fait|faite|faites|fini|finie|done)$/ && numbers) { op = "done"; arg = rest }
    else if (first ~ /^(suppr|supprime|supprimer|enl(è|e)ve|retire|remove|delete)$/ && numbers) { op = "remove"; arg = rest }
    else if (tolower(arg) ~ /^(rappels?|due)$/) op = "due"
    else if (first ~ /^(ajoute|ajouter|add)$/ && rest != "") { op = "add"; arg = rest }
    else op = "add"
  }
  changed = 0
  # lines written by hand without a number get one
  for (i = 1; i <= n_items; i++) if (id[i] == 0) { id[i] = ++maxid; changed = 1 }
  if (op == "add") {
    if (arg == "") { print "✏️ Rien à ajouter : /outil todo <texte>, avec une échéance si tu veux (demain, vendredi, 24/10)." ; exit }
    n_items++
    id[n_items] = ++maxid; isdone[n_items] = 0; text[n_items] = arg; due[n_items] = due_of(arg); meta[n_items] = "(ajoutée le " TODAY ")"
    print "➕ Ajoutée · #" id[n_items] " " arg (due[n_items] == "" ? " · sans échéance" : (num(due[n_items]) < TN ? " · ⚠️ " datelabel(due[n_items]) ", date passée" : " · 📅 " datelabel(due[n_items])))
    changed = 1
  } else if (op == "done" || op == "remove") {
    c = ids_of(arg, list)
    if (c == 0) { print "❓ Quel numéro ? /outil todo " (op == "done" ? "fait" : "suppr") " <n> (les numéros sont dans /outil todo)"; exit }
    for (j = 1; j <= c; j++) {
      i = find(list[j])
      if (!i) { print "❓ #" list[j] " introuvable"; continue }
      if (op == "done") {
        if (isdone[i]) { print "☑️ #" list[j] " déjà faite"; continue }
        isdone[i] = 1; meta[i] = "(faite le " TODAY ")"
        print "✅ Faite · #" id[i] " " text[i]
      } else {
        print "🗑️ Supprimée · #" id[i] " " text[i]
        id[i] = -1
      }
      changed = 1
    }
  } else if (op == "due") {
    s = reminders()
    print (reminder_count == 0 ? "🔔 Aucun rappel" : "🔔 Rappels (" reminder_count ") : " s)
    exit
  } else if (op == "count") {
    reminders()
    print reminder_count
    exit
  }
  if (op != "count" && op != "due") { if (op != "list") print ""; show_list(raw && op == "list") }
  if (changed) {
    out = ENVIRON["OUT"]
    print "# Ma todo (/outil todo dans OpenCode, modifiable à la main)" > out
    for (i = 1; i <= n_other; i++) if (other[i] !~ /^# Ma todo/ && other[i] != "") print other[i] > out
    for (i = 1; i <= n_items; i++) {
      if (id[i] < 0) continue
      # done items are kept 30 days
      if (isdone[i] && match(meta[i], /faite le [0-9-]+/) && num(substr(meta[i], RSTART + 9, 10)) < TN - 30) continue
      print render(i) > out
    }
    close(out)
  }
}
' "$file"

if [ -s "$tmp" ]; then
  mv "$tmp" "$file"
fi
exit 0
