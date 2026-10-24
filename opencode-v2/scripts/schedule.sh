#!/bin/sh
# For /outil planifier: the commands the pack plugin starts by itself at a time of the day, each in a new session of
# its repository (the plugin, function 26). Kept in one Markdown file outside every repository (default
# ~/.config/opencode/schedules.md, or $OPENCODE_SCHEDULES), one line per schedule, editable by hand:
#   - #1 08:45 lun,mar,mer,jeu,ven /daily — /home/dev/repos/api (ajoutée le 2026-10-24)
# Only the commands that write nothing, in git or in Jira, run without me: /daily, /outil audit [domaine],
# /outil licences [...], /tests env <environnement> (read only: never --écriture, never production). /go, /fix,
# /push, /sync, /fortify and the others are refused: they write or push, never without me. The repository is the main
# folder of the one I am in (not a workspace folder, which may be removed).
# The time is the local time of the machine of OpenCode; the days: lun-ven (or « semaine », the default), « tous les
# jours », or names (lundi, mar, mer...). Output in French: shown to me as it is.
# Usage: schedule.sh                         the list
#        schedule.sh add <time> [<days>] </command> [<arguments>]
#        schedule.sh remove <n>[,<n>...]
#        schedule.sh --raw "<text>"         what I typed after /outil planifier: "", "liste", "suppr 2", or a schedule

file=${OPENCODE_SCHEDULES:-$HOME/.config/opencode/schedules.md}
here=$(cd "$(dirname "$0")" && pwd)

list() {
  if [ ! -s "$file" ] || ! grep -q '^- #' "$file"; then
    echo "Aucune planification. Exemple : /outil planifier 8h45 lun-ven /daily"
    return 0
  fi
  echo "Planifications (lancées par OpenCode, dans une nouvelle session, à l'heure de cette machine) :"
  grep '^- #' "$file" | sed 's/^- /  /'
  echo "(le service OpenCode doit tourner à cette heure-là ; /outil planifier suppr <n> pour en retirer une)"
}

remove() {
  ids=$(printf '%s' "$1" | tr ',' ' ')
  [ -n "$ids" ] || { echo "Lesquelles ? /outil planifier suppr <n>[,<n>]"; return 1; }
  [ -f "$file" ] || { echo "Aucune planification."; return 1; }
  for id in $ids; do
    case "$id" in *[!0-9]*) echo "Numéro invalide : $id"; return 1 ;; esac
    grep -q "^- #$id " "$file" || { echo "Pas de planification #$id."; return 1; }
  done
  for id in $ids; do
    grep -v "^- #$id " "$file" > "$file.new" && mv "$file.new" "$file"
    echo "Retirée : #$id"
  done
  list
}

add() {
  text=$*
  # the command: from the first word that starts with /
  cmd=$(printf '%s\n' "$text" | sed -n 's#^[^/]*\(/.*\)$#\1#p' | sed 's/[[:space:]]*$//')
  before=$(printf '%s\n' "$text" | sed 's#/.*$##')
  [ -n "$cmd" ] || { echo "Quelle commande ? Exemple : /outil planifier 8h45 lun-ven /daily"; return 1; }
  # the time: 8h45, 08:45, 22h
  time=$(printf '%s\n' "$before" | grep -o -E '(^|[[:space:]])([01]?[0-9]|2[0-3])([:h]([0-5][0-9])?)([[:space:]]|$)' | head -n 1 | tr -d ' \t')
  [ -n "$time" ] || { echo "À quelle heure ? Exemple : /outil planifier 8h45 lun-ven /daily"; return 1; }
  hh=$(printf '%s' "$time" | sed 's/[:h].*//')
  mm=$(printf '%s' "$time" | sed -n 's/^[0-9]*[:h]\([0-9][0-9]\)$/\1/p')
  # no leading zero for printf (08 would be read as octal)
  hh=$(printf '%s' "$hh" | sed 's/^0*\([0-9]\)/\1/')
  hh=$(printf '%02d' "$hh") mm=${mm:-00}
  days_text=$(printf '%s\n' "$before" | sed -E 's/(^|[[:space:]])([01]?[0-9]|2[0-3])([:h]([0-5][0-9])?)([[:space:]]|$)/ /' | tr '[:upper:]' '[:lower:]')
  days=$(printf '%s\n' "$days_text" | awk '
    BEGIN { split("lun mar mer jeu ven sam dim", n, " "); for (i = 1; i <= 7; i++) idx[n[i]] = i }
    function key(w) { return substr(w, 1, 3) }
    {
      t = $0
      if (t ~ /tous les jours|chaque jour|quotidien/) { for (i = 1; i <= 7; i++) on[i] = 1; found = 1 }
      if (t ~ /semaine|ouvr/) { for (i = 1; i <= 5; i++) on[i] = 1; found = 1 }
      gsub(/,/, " ", t)
      m = split(t, w, /[[:space:]]+/)
      for (j = 1; j <= m; j++) {
        if (w[j] ~ /^[a-z]+-[a-z]+$/) {
          split(w[j], r, "-"); a = idx[key(r[1])]; b = idx[key(r[2])]
          if (a && b) { for (i = a; ; i = i % 7 + 1) { on[i] = 1; if (i == b) break }; found = 1 }
        } else if (key(w[j]) in idx && w[j] !~ /^(le|les|du|au)$/) { on[idx[key(w[j])]] = 1; found = 1 }
      }
    }
    END {
      if (!found) for (i = 1; i <= 5; i++) on[i] = 1
      s = ""; for (i = 1; i <= 7; i++) if (on[i]) s = s (s == "" ? "" : ",") n[i]
      print s
    }')
  # what may run without me
  words=$(printf '%s\n' "$cmd" | tr -s ' \t' '  ')
  case "$words" in
    /daily|/daily\ *) ;;
    "/outil audit"|"/outil audit "*|"/outil licences"|"/outil licences "*) ;;
    "/tests env "*)
      case " $words " in *" --ecriture "*|*" --écriture "*|*" --allow-writes "*|*" --writes "*|*" écriture "*)
        echo "Refusé : /tests env se planifie en lecture seule, jamais avec écriture."; return 1 ;;
      esac
      env=$(printf '%s\n' "$words" | awk '{ print $3 }')
      line=$(sh "$here/environments.sh" "$env" 2>/dev/null | grep -v '^WARNING:' | head -n 1)
      [ -n "$line" ] || { echo "Refusé : aucun environnement « $env » dans l'AGENTS.md de ce dépôt (section ## Environnements)."; return 1; }
      [ "$(printf '%s' "$line" | cut -f5)" = yes ] && { echo "Refusé : $env est la production, où le pack ne lance jamais de tests."; return 1; } ;;
    *)
      echo "Refusé : $cmd ne se planifie pas. Seules les commandes qui n'écrivent ni dans git ni dans Jira partent sans toi : /daily, /outil audit, /outil licences, /tests env <environnement>."
      return 1 ;;
  esac
  # the main folder of this repository (a workspace folder may be removed)
  common=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "Lance /outil planifier depuis une session d'un dépôt git."; return 1; }
  case "$common" in /*) ;; *) common=$(cd "$common" && pwd) ;; esac
  repo=$(dirname "$common")
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || printf '# Planifications du pack OpenRDCode (/outil planifier) : le plugin lance chaque ligne à son heure, dans une nouvelle session.\n\n' > "$file"
  id=$(sed -n 's/^- #\([0-9][0-9]*\) .*/\1/p' "$file" | sort -n | tail -n 1)
  id=$(( ${id:-0} + 1 ))
  printf '%s\n' "- #$id $hh:$mm $days $cmd — $repo (ajoutée le $(date +%Y-%m-%d))" >> "$file"
  echo "Planifiée : #$id, $cmd à $hh:$mm ($days), dans $repo"
  list
}

case "$1" in
  --raw)
    t=$(printf '%s' "$2" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$t" in
      ""|liste|list) list ;;
      suppr\ *|supprime\ *|supprimer\ *|retire\ *|remove\ *) remove "$(printf '%s' "$t" | sed 's/^[^ ]* *//; s/ //g')" ;;
      *) add "$t" ;;
    esac ;;
  add) shift; add "$*" ;;
  remove) remove "$2" ;;
  ""|list) list ;;
  *) echo "Usage: schedule.sh [add <time> [<days>] </command> | remove <n> | --raw <text>]"; exit 1 ;;
esac
