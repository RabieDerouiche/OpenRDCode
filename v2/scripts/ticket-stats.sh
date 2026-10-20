#!/bin/sh
# For /outil stats: what /go and /fix did on the tickets of this repository (or of the repositories given), read from
# their ticket sheets (.git/opencode-tickets/<KEY>.md, never committed): plan steps, launches of /go, runs of /fix,
# answers given by the developer, decisions taken by the agent, stops, and the time from the analysis to the merge
# request. Read-only. The output is shown as it is to the developer (/outil stats), so it is in French.
# Usage: ticket-stats.sh [<repository path>...]      default: the current repository

LC_ALL=C
export LC_ALL

if [ $# -eq 0 ]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Statistiques des tickets : ce dossier n'est pas un dépôt git"; exit 0; }
  set -- "$root"
fi

for repo in "$@"; do
  # shellcheck disable=SC2088 # a literal ~/ is matched on purpose
  case "$repo" in
    "~") repo=$HOME ;;
    "~/"*) repo="$HOME/${repo#"~/"}" ;;
  esac
  dir=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || { echo "Statistiques des tickets : $repo n'est pas un dépôt git"; continue; }
  sheets="$dir/.git/opencode-tickets"
  set --
  for file in "$sheets"/*.md; do
    [ -f "$file" ] && set -- "$@" "$file"
  done
  if [ $# -eq 0 ]; then
    echo "Statistiques des tickets de $(basename "$dir") : aucune fiche pour l'instant (/go en crée une par ticket)"
    continue
  fi
  awk -v repo="$(basename "$dir")" '
    # minutes since 1970-01-01 of "YYYY-MM-DD HH:MM" (days from civil, valid for any Gregorian date)
    function minutes(stamp,   y, m, d, h, mi, era, yoe, doy, doe) {
      if (stamp !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]/) return -1
      y = substr(stamp, 1, 4) + 0; m = substr(stamp, 6, 2) + 0; d = substr(stamp, 9, 2) + 0
      h = substr(stamp, 12, 2) + 0; mi = substr(stamp, 15, 2) + 0
      if (m <= 2) y--
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return ((era * 146097 + doe - 719468) * 24 + h) * 60 + mi
    }
    function duration(n) {
      if (n < 0) return "-"
      if (n < 60) return n " min"
      if (n < 1440) return int(n / 60) " h " sprintf("%02d", n % 60)
      return int(n / 1440) " j " int((n % 1440) / 60) " h"
    }
    function flush(   took, state) {
      if (key == "") return
      n++
      took = (created >= 0 && delivered >= 0) ? delivered - created : -1
      if (delivered >= 0) done++
      if (took >= 0) times[++timed] = took
      if (start == "") start = "?"
      state = (delivered >= 0) ? (took >= 0 ? duration(took) : "livré") : (stops > 0 ? "arrêté" : "en cours")
      row[n] = start "|" key "|" title "|" ticked "/" (ticked + open) "|" launches "|" fixes "|" answers "|" decisions "|" stops "|" state
      tl += launches; tf += fixes; ta += answers; td += decisions; ts += stops
    }
    FNR == 1 {
      flush()
      key = FILENAME; sub(/^.*\//, "", key); sub(/\.md$/, "", key)
      title = $0; sub(/^# [^ ]* - /, "", title); sub(/^# /, "", title)
      if (length(title) > 50) title = substr(title, 1, 47) "..."
      gsub(/\|/, "/", title)
      created = -1; delivered = -1; start = ""; ticked = 0; open = 0; launches = 0; fixes = 0; answers = 0
      decisions = 0; stops = 0; section = ""
      next
    }
    /^- Cr[^ ]*e le *: / { s = $0; sub(/^- Cr[^ ]*e le *: */, "", s); created = minutes(s); start = substr(s, 1, 10); next }
    /^## / { section = $0; next }
    section ~ /^## Plan/ && /^[[:space:]]*- \[[xX]\]/ { ticked++; next }
    section ~ /^## Plan/ && /^[[:space:]]*- \[ \]/ { open++; next }
    section ~ /^## D/ && /^- / { decisions++; if ($0 ~ /\(r[^ ]*ponse du dev\)/) answers++; next }
    section ~ /^## Suivi/ && /^- [0-9][0-9][0-9][0-9]-/ {
      stamp = substr($0, 3, 16); text = substr($0, 19)
      if (text ~ /^ *\/go - fiche cr/) { launches++; if (created < 0) { created = minutes(stamp); start = substr(stamp, 1, 10) } }
      else if (text ~ /^ *\/go - reprise/) launches++
      else if (text ~ /^ *\/go - livr/) { if (delivered < 0) delivered = minutes(stamp) }
      else if (text ~ /^ *\/fix/) fixes++
      if (text ~ /bloqu/ || text ~ /en attente du PO/) stops++
      next
    }
    END {
      flush()
      print "Tickets de " repo " (" n " fiche" (n > 1 ? "s" : "") ", les plus récentes d'\''abord) :"
      print "| Créée le | Ticket | Titre | Étapes | Lancements /go | /fix | Réponses du dev | Décisions de l'\''agent | Arrêts | Analyse → MR |"
      print "|---|---|---|---|---|---|---|---|---|---|"
      # most recent first (dates sort as text)
      for (i = 1; i <= n; i++) order[i] = i
      for (i = 2; i <= n; i++) { j = i; while (j > 1 && row[order[j - 1]] < row[order[j]]) { t = order[j]; order[j] = order[j - 1]; order[j - 1] = t; j-- } }
      for (i = 1; i <= n; i++) { r = row[order[i]]; gsub(/\|/, " | ", r); print "| " r " |" }
      # median time to the merge request
      for (i = 2; i <= timed; i++) { j = i; while (j > 1 && times[j - 1] > times[j]) { t = times[j]; times[j] = times[j - 1]; times[j - 1] = t; j-- } }
      median = timed ? (timed % 2 ? times[(timed + 1) / 2] : int((times[timed / 2] + times[timed / 2 + 1]) / 2)) : -1
      printf "Total : %d ticket%s, %d livré%s en merge request", n, (n > 1 ? "s" : ""), done, (done > 1 ? "s" : "")
      if (timed) printf ", médiane de l'\''analyse à la MR : %s", duration(median)
      per = n ? sprintf("%.1f", (tl + tf + ta) / n) : "0"
      sub(/\./, ",", per)
      printf ". Interventions du développeur : %d lancement%s de /go, %d /fix, %d réponse%s aux questions (%s par ticket). Décisions prises par l'\''agent : %d, listées dans ses MR. Arrêts : %d.\n", tl, (tl > 1 ? "s" : ""), tf, ta, (ta > 1 ? "s" : ""), per, td, ts
    }
  ' "$@"
done
exit 0
