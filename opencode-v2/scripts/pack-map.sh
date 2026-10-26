#!/bin/sh
# For /outil carte: the map of the flows of the pack, made from its own files as they are installed - its commands and
# their steps (the agents, the questions and the stops of each step, the scripts they run), the tools of /outil, the
# agents and what they may write, the skills, the functions of the plugin and the scripts - as one page in French, to
# open in a browser or to show to someone who never used the pack; then the same facts, for the agent that presents it.
# Nothing is read in a repository: the page says what the pack does, never what a repository holds.
#   (no argument)        the page in the configuration folder of OpenCode: <pack>/carte-des-flux.html
#   --out <file.html>    the page there instead (/outil carte <path>: a path of the repository, to push it)
#   --pack <folder>      the pack read from that folder (its commands, agents, skills, plugin and scripts: its tests)
# The pack is the one this OpenCode reads, found as its plugin finds it: OPENCODE_CONFIG_DIR (OpenCode v2 next to 1.19,
# in ~/oc2: MIGRATION.md), otherwise ${XDG_CONFIG_HOME:-~/.config}/opencode, otherwise the folder above these scripts;
# its scripts are these ones (~/.config/opencode/scripts, common to 1.19 and v2) unless that folder has its own.
# The steps of a command: its numbered sections (« ## 4. Analysis… », « ## Step 2 - Links »), its lettered sections as
# alternatives (« ## M. The menu »), otherwise its numbered list; as the command writes them for the model (English).
# The plain words (what a command or an agent is for, what a function of the plugin prevents) are written here, for
# the commands and agents of the pack; a command, an agent or a function added later shows its own description.
# Output: "CARTE: <file> (<counts>)", then "COMMANDE:", "OUTIL:", "AGENT:", "SKILL:" and "PLUGIN:" lines; "STOP:" when
# the folder is not a pack (no commands/ or agents/ in it) or the page cannot be written.
# Usage: pack-map.sh [--out <file.html>] [--pack <folder>]

LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
pack=""
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out=$2; shift 2 ;;
    --pack) pack=$2; shift 2 ;;
    *) echo "STOP: usage: pack-map.sh [--out <file.html>] [--pack <folder>]"; exit 1 ;;
  esac
done
if [ -z "$pack" ]; then
  for d in "${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}" "$(dirname "$here")"; do
    if [ -d "$d/commands" ] && [ -d "$d/agents" ]; then pack=$d; break; fi
  done
  [ -n "$pack" ] || pack=$(dirname "$here")
fi
{ [ -d "$pack/commands" ] && [ -d "$pack/agents" ]; } || { echo "STOP: $pack is not a pack of OpenCode (no commands/ or agents/ folder in it)"; exit 1; }
pack=$(cd "$pack" && pwd)
if [ -d "$pack/scripts" ]; then scripts="$pack/scripts"; else scripts=$here; fi
[ -n "$out" ] || out="$pack/carte-des-flux.html"
case "$out" in
  *.html) ;;
  *) echo "STOP: the map is an .html page: $out"; exit 1 ;;
esac
dir=$(dirname "$out")
[ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || { echo "STOP: cannot create the folder $dir"; exit 1; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pack-map.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')
# the separator of the lists read by the shell: not white space, so that an empty field stays a field
us=$(printf '\037')

# ---------- the plain words: what each command, agent, skill and function of the plugin is for ----------
# <command> <family> <its line on the map> <what it does, for someone who never used the pack>
cat > "$tmp/commands.fr" <<'EOF'
go	ticket	un ticket Jira, jusqu'à la MR en Draft	Tu donnes la clé d'un ticket Jira ; le pack va jusqu'à la merge request en Draft sans s'arrêter. L'analyste lit le ticket et écrit un plan ; chaque étape est codée avec ses tests (avant de toucher du code existant, des tests figent son comportement actuel ; un bug a d'abord son test, qui échoue) ; puis build et tests complets, relecture automatique, contrôle avant push et MR. Ses questions, s'il en a, arrivent au début, toutes en même temps. Sans ticket : /go sans ticket : ce qu'il faut faire.
fix	ticket	les retours de la CI et de la review	Après la CI ou la review : il rassemble en une fois les jobs en échec, les constats Sonar et Fortify et les commentaires de la MR, corrige ce qui est à corriger (une faille ou un bug avec la preuve qu'il est corrigé), prépare les réponses à coller dans GitLab, puis repousse. Avec ou sans ticket.
fortify	ticket	un lot de failles Fortify, chacune prouvée	Les quatre ou cinq failles Fortify les plus graves de l'application : chacune analysée, puis prouvée par un test qui échoue avant la correction et passe après ; une seule MR pour le lot.
tests	free	des tests prouvés, sans ticket, par QCM	Des tests sans ticket, guidés par des QCM : les tests unitaires d'une classe ou d'une page, les tests d'une API en mémoire scénario par scénario, ceux d'un environnement déployé (son OpenID Connect, son proxy). Chaque test est prouvé, vert deux fois de suite. Rien n'est poussé : /push ensuite.
push	free	builder, tester, pousser, avec ou sans MR	Pousse le travail du dossier : il builde et teste ce qui a changé, puis propose en une seule question la branche, le message de commit et la MR, chacun avec sa recommandation. Rien ne part sans le contrôle avant push (secrets, conflits, fichiers générés).
sync	free	récupérer ce qu'un autre poste a poussé	Met la branche à jour avec ce qui a été poussé depuis un autre poste, et avec develop si tu le demandes, sans rien commiter ni pousser. Un conflit se règle dans Rider.
daily	read	le point du matin	Le point du matin, en lecture seule : ton sprint, les reviews qui t'attendent, tes merge requests et leurs pipelines, ce qu'il faut prendre ensuite, ta todo.
review	read	relire la MR d'un collègue	Relit la merge request d'un collègue sans toucher ta branche ni tes fichiers : des commentaires prêts à coller dans GitLab, avec le fichier, la ligne et la gravité.
compare	read	pourquoi ça marche ailleurs et plus ici	Compare une fonctionnalité avec un dépôt où elle marche (du code migré, une ancienne version) : paquets, code et historique comparés par un script, puis la première différence expliquée, preuves à l'appui.
outil	tools	les autres outils, à la demande	Les autres outils du pack, chacun à la demande : documentation, audit, licences, notes de version, dépôts liés, requêtes HTTP pour Rider ou Visual Studio, planification, carte des flux. Leur liste vient du pack lui-même.
EOF
# <agent> <what it is for>
cat > "$tmp/agents.fr" <<'EOF'
pilot	Le chef d'orchestre : il mène les commandes de bout en bout, confie le travail aux autres agents, commite et pousse par les scripts du pack ; il n'écrit jamais de code.
analyst	L'analyste : il lit le ticket, ses pages Confluence et le code, puis écrit la fiche du ticket (critères d'acceptation, plan en étapes, tests attendus, décisions).
coder	Le développeur : il code une étape du plan, ou une liste de corrections, avec ses tests, puis builde et teste.
test-guardian	Le gardien des tests : il mesure, écrit et prouve les tests (filet de non-régression, preuve d'un bug ou d'une faille, couverture des changements, tests d'API) ; il n'écrit que dans les projets de tests.
checker	Le relecteur : l'auto-review d'une branche avant son push, ou la review de la MR d'un collègue ; il n'écrit rien.
debugger	L'enquêteur : la cause d'un échec qui résiste, preuves à l'appui ; il n'écrit rien.
doc-writer	Le rédacteur : la documentation du dépôt (docs/, README.md), écrite depuis le code, sans jamais lire une valeur de configuration.
EOF
# <skill> <what it knows>
cat > "$tmp/skills.fr" <<'EOF'
api-tests	Les tests d'intégration d'une API ASP.NET Core : en mémoire, et sur un environnement déployé (OpenID Connect, proxy).
automapper	AutoMapper (payant depuis la 15.0, vulnérable avant) : son remplacement par Mapperly (recommandé) ou Mapster (le plus proche), profil par profil sous des tests enregistrés sur AutoMapper (inventaire, ajout, traduction des maps et vérification par un script) ; chaque forme d'AutoMapper et son équivalent Mapperly.
best-practices	Les bonnes pratiques par type de projet : erreurs et Result, feature flags, performance, tests.
blazorise	Blazorise : son remplacement par du Razor 100 % natif, sans paquet, page par page sous un filet de tests bUnit (inventaire, composants de l'application et vérification par un script) ; tant qu'il est là, la langue de son DataGrid et l'API de sa version.
build-fix	Réparer un build cassé par le plus petit changement, quelle que soit la version de .NET.
dotnet-cqrs-conventions	Les conventions des API CQRS (commands, queries, handlers, validators).
efcore	Entity Framework Core : des requêtes qui restent rapides, des écritures et des transactions sûres, des migrations qui ne perdent aucune donnée, les tests du code qui utilise un DbContext.
explain-code	Expliquer un fichier, un endpoint ou une page de bout en bout, pour un nouvel arrivant.
fortify-remediation	Corriger une faille Fortify ou Sonar selon sa catégorie, avec sa preuve.
integrations-guardrails	Les pièges des intégrations : SharePoint, DocuSign, AWS S3, Piano Analytics.
mapster	AutoMapper remplacé par Mapster : MapsterSetup.cs et les règles d'AutoMapper, le Register de chaque profil, le test qui remplace AssertConfigurationIsValid, la bascule des appels (automapper.sh switch) ; chaque forme d'AutoMapper et son équivalent Mapster.
EOF
# <number of the function> <what the plugin does there>
cat > "$tmp/plugin.fr" <<'EOF'
1	Calcule les faits d'une commande (état git, fiche, détection du projet) avant que le modèle ne lise sa demande.
2	Donne aux commandes des agents un environnement stable, sans mot de passe ni jeton de la machine.
3	Affiche la commande et son dossier au lieu du prompt déroulé, et nomme la session.
4	Lance tout seul la commande choisie dans un QCM, dans la même session.
5	Montre l'avancement d'un run dans le titre de la session.
6	Refuse une commande qui change PATH ou DOTNET_ROOT, ou qui écrit un identifiant.
7	Garde les agents dans le dépôt : un chemin hors du dépôt est refusé.
8	Donne 20 minutes à un build ou à des tests (OpenCode coupe une commande après 2).
9	Un seul run à la fois par dossier : deux pilotes y mélangeraient leurs commits.
10	Laisse l'issue d'un run dans le titre : ✅, ⏸, ↻ ou ⛔.
11	Lance un outil appelé par son chemin complet par son nom, pour que les règles s'appliquent.
12	Ferme ce que la v2 ouvre : le code mode, la recherche web, les outils qui déplacent une session.
13	Allège les longues sessions en retirant des requêtes les sorties des anciens outils.
14	Attend les serveurs MCP encore en connexion au démarrage (Jira, GitLab).
15	Met le nom du dossier d'un espace de travail en tête de ses titres.
16	Refuse le troisième appel identique d'un outil : le modèle change d'approche.
17	Garde la procédure d'un run quand son contexte est plein et résumé.
18	Étale les nouveaux essais d'OpenCode quand le serveur du modèle redémarre.
19	Reprend tout seul un run arrêté avant sa fin, depuis sa fiche.
20	Corrige les messages que la passerelle du modèle refusait (contenu null).
21	Coupe une réponse du modèle qui se répète en boucle.
22	« continue » reprend un run arrêté avec le pilote.
23	Ne permet dotnet run qu'à un projet que le dernier commit contient : jamais un programme sonde.
24	Refuse une commande qui ne finit jamais (un serveur, un mode watch) aux agents du pack.
25	Refuse aux agents une commande qui change les dépendances du dépôt (npm install, dotnet package add).
26	Lance à leur heure les commandes de /outil planifier, seulement ce qui n'écrit rien.
27	Coupe après 5 minutes un appel à un serveur MCP qui ne répond plus (OpenCode v2 attendait jusqu'à 12 heures).
28	Envoie au modèle les réglages de chaque agent (température, effort de réflexion), que la v2 lisait sans les envoyer.
29	Chronomètre chaque run (le modèle, les sous-agents, les outils, tes réponses) pour /outil vitesse, jamais le texte des demandes.
30	Allège chaque requête des agents du pack : les règles qui ne servent qu'à la conversation ne leur partent plus.
31	Ne donne au pilote que les outils des serveurs MCP de sa commande (/go : Jira et GitLab) : des requêtes plus courtes, un choix d'outil plus sûr.
EOF

# ---------- what the files of the pack say ----------
# the value of a key of the frontmatter of a file, its quotes removed
front() {
  awk -v key="$2" 'NR == 1 && /^---[ \t\r]*$/ { fm = 1; next }
    fm && /^---[ \t\r]*$/ { exit }
    fm && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v)
      if (v ~ /^".*"$/) { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v) }
      print v; exit
    }' "$1"
}
lookup() { awk -F "$tab" -v k="$2" -v c="$3" '$1 == k { print $c; exit }' "$1"; }
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }
# the first sentence of a text (up to « . » followed by a space), 40 words at most
first_sentence() {
  printf '%s\n' "$1" | awk '{ n = split($0, w, " "); s = ""
    for (i = 1; i <= n && i <= 40; i++) { s = s (s == "" ? "" : " ") w[i]; if (w[i] ~ /[.]$/ && i > 3) break }
    if (i > 40 && n > 40) s = s " …"; print s }'
}

agent_names=$(for f in "$pack"/agents/*.md; do [ -f "$f" ] && basename "$f" .md; done | tr '\n' ' ')

# The steps of a command, fields separated by $us: "PRE <scripts run before the first turn>", then one
# "STEP <num|alt> <label> <agents> <questions> <stops> <scripts>" per step, then
# "END <the endings it names> <yes when it ends with its « Suite » question>"
cat > "$tmp/steps.awk" <<'EOF'
function add(list, item) { return index(", " list ", ", ", " item ", ") ? list : list (list == "" ? "" : ", ") item }
function label_of(t,   w, n, i, s) {
  gsub(/`/, "", t); gsub(/\*\*/, "", t)
  sub(/[ \t]*:[ \t].*$/, "", t); sub(/[ \t]*:$/, "", t); sub(/\. .*$/, "", t); sub(/[.]$/, "", t)
  n = split(t, w, " "); s = ""
  for (i = 1; i <= n && i <= 12; i++) s = s (s == "" ? "" : " ") w[i]
  if (n > 12) s = s " …"
  return s
}
function facts(line,   s, p, q, name, a, n, i, k) {
  # the agents of the pack it names, as `name`
  n = split(agents, a, " ")
  for (i = 1; i <= n; i++) if (a[i] != "" && index(line, "`" a[i] "`")) cur_agents = add(cur_agents, a[i])
  # the questions of a QCM, in the order the line asks them: header « … » or header "…"
  s = line
  while (1) {
    p = index(s, "header « "); k = index(s, "header \"")
    if (p == 0 && k == 0) break
    if (p > 0 && (k == 0 || p < k)) {
      s = substr(s, p + length("header « ")); q = index(s, " »")
      if (q == 0) break
      # « header « **/tests** — … » » is the first line of an answer, not a question
      name = substr(s, 1, q - 1); if (name != "Suite" && name !~ /^\*\*/) cur_q = add(cur_q, name)
      s = substr(s, q)
    } else {
      s = substr(s, k + length("header \"")); q = index(s, "\"")
      if (q == 0) break
      name = substr(s, 1, q - 1); if (name != "Suite") cur_q = add(cur_q, name)
      s = substr(s, q + 1)
    }
  }
  if (index(line, "« Suite »") || index(line, "header \"Suite\"")) suite = 1
  # the stops it may end with
  s = line; while ((p = index(s, "⛔")) > 0) { cur_stops++; s = substr(s, p + 3) }
  # the scripts of the pack it runs
  s = line
  while ((p = index(s, "scripts/")) > 0) {
    s = substr(s, p + 8)
    if (match(s, /^[A-Za-z0-9_.-]+\.sh/)) cur_scripts = add(cur_scripts, substr(s, 1, RLENGTH))
  }
  for (k in endings) if (index(line, k)) seen_end[k] = 1
}
function flush() {
  if (cur_label != "") {
    out = sprintf("STEP\037%s\037%s\037%s\037%s\037%d\037%s", cur_kind, cur_label, cur_agents, cur_q, cur_stops, cur_scripts)
    if (mode == "heading") hsteps[++nh] = out; else lsteps[++nl] = out
  }
  cur_label = ""; cur_agents = ""; cur_q = ""; cur_stops = 0; cur_scripts = ""
}
BEGIN {
  endings["🚀"] = 1; endings["✅"] = 1; endings["⛔"] = 1; endings["⏸"] = 1; endings["🔁"] = 1
  stage = "pre"
}
NR == 1 && /^---[ \t\r]*$/ { fm = 1; next }
fm { if ($0 ~ /^---[ \t\r]*$/) fm = 0; next }
/^```/ { fence = !fence; next }
fence { next }
{ sub(/\r$/, "") }
/^\[\[run / { s = $0; sub(/^\[\[run /, "", s); sub(/[ \]].*$/, "", s); pre = add(pre, s); next }
/^## (Answer|Output|Réponse)/ { flush(); stage = "end"; mode = ""; next }
stage == "end" { for (k in endings) if (index($0, k)) seen_end[k] = 1; if (index($0, "« Suite »")) suite = 1; next }
/^## / {
  h = substr($0, 4)
  if (h ~ /^[0-9]+\. /) { flush(); mode = "heading"; cur_kind = "num"; sub(/^[0-9]+\. /, "", h); cur_label = label_of(h); stage = "steps"; next }
  if (h ~ /^[A-Z]\. /) { flush(); mode = "heading"; cur_kind = "alt"; sub(/^[A-Z]\. /, "", h); cur_label = label_of(h); stage = "steps"; next }
  if (h ~ /^Step [0-9]+ - /) { flush(); mode = "heading"; cur_kind = "num"; sub(/^Step [0-9]+ - /, "", h); cur_label = label_of(h); stage = "steps"; next }
  # another section (« ## Unit tests », « ## Rules »): its text belongs to no step
  flush(); mode = (nh > 0 ? "heading" : ""); next
}
/^[0-9]+\. / && mode != "heading" {
  flush(); mode = "list"; cur_kind = "num"; h = $0; sub(/^[0-9]+\. /, "", h); cur_label = label_of(h); facts($0); next
}
{ if (cur_label != "") facts($0); else if (stage != "end") { for (k in endings) if (index($0, k)) seen_end[k] = 1; if (index($0, "« Suite »")) suite = 1 } }
END {
  flush()
  print "PRE\037" pre
  if (nh > 0) for (i = 1; i <= nh; i++) print hsteps[i]
  else for (i = 1; i <= nl; i++) print lsteps[i]
  n = split("🚀 🔁 ✅ ⏸ ⛔", order, " "); e = ""
  for (i = 1; i <= n; i++) if (order[i] in seen_end) e = e (e == "" ? "" : " ") order[i]
  print "END\037" e "\037" (suite ? "yes" : "no")
}
EOF

# ---------- the commands, in the order of their families ----------
: > "$tmp/cmds"
for f in "$pack"/commands/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  fam=$(lookup "$tmp/commands.fr" "$name" 2)
  # the order of the map: the families, then the order of the plain words above (/go before /fix)
  rank=$(awk -F "$tab" -v k="$name" '$1 == k { print NR; exit }' "$tmp/commands.fr")
  case "$fam" in
    ticket) o=1 ;; free) o=2 ;; read) o=3 ;; tools) o=4 ;; *) o=5; fam=other ;;
  esac
  o=$((o * 100 + ${rank:-99}))
  printf '%s%s%s%s%s\n' "$o" "$us" "$name" "$us" "$fam" >> "$tmp/cmds"
done
sort -t "$us" -k1,1n -k2,2 "$tmp/cmds" > "$tmp/cmds.sorted"
ncmd=$(grep -c . "$tmp/cmds.sorted")

# the tools of /outil, as outil.sh lists them: "<name> <arguments> <what it does>"
: > "$tmp/tools"
if [ -f "$scripts/outil.sh" ]; then
  sh "$scripts/outil.sh" 2>/dev/null | sed -n 's/^- //p' | awk '{
    # the first « : » outside the brackets of the arguments (« pattern <nom> [où : clé Jira] : capture… »)
    line = $0; depth = 0; p = 0
    for (i = 1; i < length(line) - 1; i++) {
      c = substr(line, i, 1)
      if (c == "[") depth++; else if (c == "]") depth--
      else if (depth == 0 && substr(line, i, 3) == " : ") { p = i; break }
    }
    if (p == 0) next
    head = substr(line, 1, p - 1); what = substr(line, p + 3)
    n = split(head, w, " "); name = w[1]; args = substr(head, length(name) + 2)
    printf "%s\037%s\037%s\n", name, args, what }' > "$tmp/tools"
fi
ntool=$(grep -c . "$tmp/tools")

# the agents: "<name> <mode> <steps> <what it may write>"
: > "$tmp/agents"
for f in "$pack"/agents/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f" .md)
  mode=$(front "$f" mode)
  steps=$(front "$f" steps)
  perm=$(front "$f" permission)
  edit=$(printf '%s' "$perm" | sed -n -E 's/.*edit: (deny|allow)[,} ].*/\1/p')
  [ -n "$edit" ] || edit=$(printf '%s' "$perm" | awk '{ p = index($0, "edit: {"); if (!p) exit; s = substr($0, p + 7); q = index(s, "}"); print substr(s, 1, q - 1) }')
  case "$edit" in
    deny) writes="rien (lecture seule)" ;;
    allow|"") writes="le dépôt" ;;
    *)
      if printf '%s' "$edit" | grep -q '"\*": allow'; then
        writes="le code et les tests du dépôt"
      else
        writes=$(printf '%s\n' "$edit" | tr ',' '\n' | sed -n 's/^ *"\([^"]*\)": allow.*/\1/p' | while IFS= read -r p; do
          case "$p" in
            *opencode-tickets*) echo "la fiche du ticket" ;;
            *Tests/*|*Test/*|tests/*|test/*|*/tests/*|*/test/*) echo "les projets de tests" ;;
            docs/*) echo "docs/" ;;
            *) echo "$p" ;;
          esac
        done | awk '!seen[$0]++' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
      fi ;;
  esac
  printf '%s%s%s%s%s%s%s\n' "$name" "$us" "$mode" "$us" "$steps" "$us" "$writes" >> "$tmp/agents"
done
nagent=$(grep -c . "$tmp/agents")

# the skills: "<name> <description>"
: > "$tmp/skills"
for f in "$pack"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  printf '%s%s%s\n' "$(basename "$(dirname "$f")")" "$us" "$(front "$f" description)" >> "$tmp/skills"
done
nskill=$(grep -c . "$tmp/skills")

# the functions of the plugin, numbered in its header: "<n> <its first line>"
: > "$tmp/plugin"
plugin=$(ls "$pack"/plugins/*.js 2>/dev/null | head -n 1)
if [ -n "$plugin" ]; then
  awk 'NR > 200 { exit } /^\/\/ [0-9]+\. / { s = $0; sub(/^\/\/ /, "", s); n = s; sub(/\..*$/, "", n); sub(/^[0-9]+\. /, "", s); printf "%s\037%s\n", n, s }' "$plugin" > "$tmp/plugin"
fi
nplugin=$(grep -c . "$tmp/plugin")

# the scripts: "<name> <the first line of their header>"
: > "$tmp/scripts"
for f in "$scripts"/*.sh; do
  [ -f "$f" ] || continue
  printf '%s%s%s\n' "$(basename "$f")" "$us" "$(sed -n '2s/^# *//p' "$f")" >> "$tmp/scripts"
done
nscript=$(grep -c . "$tmp/scripts")

# ---------- the page ----------
now=$(date '+%d/%m/%Y à %H:%M')
page="$tmp/page.html"
cat > "$page" <<'EOF'
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Carte des flux du pack</title>
<style>
:root { --bg: #f6f7f4; --surface: #ffffff; --ink: #1d2320; --muted: #59625d; --line: #d9ddd7; --accent: #2f6b4f;
  --accent-soft: #e3efe8; --stop: #a2342b; --warn: #9a5b12; --q: #6b4a9b; --ag: #2f5f8a; --sc: #8a6a12;
  --font: "Atkinson Hyperlegible", "Segoe UI", system-ui, sans-serif; --mono: ui-monospace, "SFMono-Regular", Menlo, monospace; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #121614; --surface: #1a1f1c; --ink: #e5ebe7; --muted: #9aa69f; --line: #2c3430; --accent: #7cc3a0;
    --accent-soft: #1f3129; --stop: #ef8a80; --warn: #e0a65a; --q: #b8a1e3; --ag: #8ab8e0; --sc: #dcbd63; color-scheme: dark; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font-family: var(--font); font-size: 16px; line-height: 1.55;
  padding: 28px max(16px, env(safe-area-inset-right)) 64px max(16px, env(safe-area-inset-left)); }
.wrap { max-width: 1180px; margin: 0 auto; display: grid; grid-template-columns: 210px minmax(0, 1fr); gap: 40px; }
nav { position: sticky; top: 16px; align-self: start; display: flex; flex-direction: column; gap: 2px; font-size: 14.5px; }
nav .label { font-size: 12px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); margin: 10px 0 4px; }
nav a { color: var(--muted); text-decoration: none; padding: 4px 10px; border-radius: 6px; }
nav a:hover, nav a:focus-visible { color: var(--ink); background: var(--accent-soft); outline: none; }
main { min-width: 0; display: flex; flex-direction: column; gap: 48px; }
h1 { font-size: clamp(28px, 4vw, 38px); line-height: 1.15; margin: 0 0 10px; }
h2 { font-size: 23px; margin: 0; display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 12px; }
h2 .who { font-size: 14.5px; font-weight: 400; color: var(--muted); }
header p, section > p { margin: 0; max-width: 74ch; }
header p { color: var(--muted); font-size: 17px; }
section { display: flex; flex-direction: column; gap: 14px; scroll-margin-top: 16px; }
code { font-family: var(--mono); font-size: .9em; background: var(--accent-soft); padding: 1px 5px; border-radius: 4px; }
.marks { display: flex; flex-wrap: wrap; gap: 6px 18px; margin-top: 14px; font-size: 14.5px; color: var(--muted); }
.plain { font-size: 17px; }
.usage { color: var(--muted); }
.mm { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }
.mm .root { grid-column: 1 / -1; background: var(--accent); color: var(--surface); border-radius: 10px; padding: 14px 18px; font-size: 20px; font-weight: 700; }
.mm .root small { display: block; font-size: 14px; font-weight: 400; }
.branch { background: var(--surface); border: 1px solid var(--line); border-top: 3px solid var(--c, var(--accent)); border-radius: 10px; padding: 12px 14px; }
.branch h3 { margin: 0 0 8px; font-size: 15px; color: var(--c, var(--accent)); }
.branch ul { margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 6px; font-size: 14.5px; line-height: 1.4; }
.diagram { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 14px; overflow-x: auto; }
.diagram pre.mermaid { margin: 0; }
pre.mermaid:not([data-processed]) { display: none; }
.diagram:has(pre.mermaid:not([data-processed])) { display: none; }
ol.steps { margin: 0; padding-left: 1.6em; display: flex; flex-direction: column; gap: 8px; }
ol.steps li.alt { list-style-type: "↳ "; }
.chip { display: inline-block; font-size: 13px; border: 1px solid var(--line); border-radius: 999px; padding: 0 8px; margin: 2px 2px 0 0; max-width: 100%; overflow-wrap: anywhere; }
.chip.ag { color: var(--ag); } .chip.q { color: var(--q); } .chip.stop { color: var(--stop); } .chip.sc { color: var(--sc); font-family: var(--mono); font-size: 12px; }
.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 10px 28px; margin: 0; padding: 0; list-style: none; }
.facts li { padding-left: 12px; border-left: 2px solid var(--line); font-size: 15px; min-width: 0; }
.facts li b { display: block; font-size: 12.5px; letter-spacing: .05em; text-transform: uppercase; color: var(--accent); }
.tablewrap { overflow-x: auto; border: 1px solid var(--line); border-radius: 10px; background: var(--surface); }
table { border-collapse: collapse; width: 100%; font-size: 15px; min-width: 560px; }
th, td { text-align: left; padding: 9px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { font-size: 12.5px; letter-spacing: .05em; text-transform: uppercase; color: var(--muted); }
tr:last-child td { border-bottom: 0; }
details summary { cursor: pointer; color: var(--accent); }
footer { color: var(--muted); font-size: 14px; border-top: 1px solid var(--line); padding-top: 14px; }
@media (max-width: 860px) {
  .wrap { grid-template-columns: minmax(0, 1fr); gap: 20px; }
  nav { position: static; flex-direction: row; flex-wrap: wrap; gap: 6px; }
  nav .label { width: 100%; margin: 4px 0 0; }
  nav a { border: 1px solid var(--line); }
}
</style>
</head>
<body>
<div class="wrap">
EOF

# the menu
{
  echo '<nav aria-label="Sections">'
  echo '<span class="label">Vue d&rsquo;ensemble</span><a href="#minute">En une minute</a><a href="#carte">Carte d&rsquo;ensemble</a>'
  echo '<span class="label">Les commandes</span>'
  while IFS="$us" read -r o name fam; do echo "<a href=\"#cmd-$name\"><code>/$name</code></a>"; done < "$tmp/cmds.sorted"
  echo '<span class="label">Le pack</span><a href="#agents">Qui fait quoi</a><a href="#skills">Ce qu&rsquo;il sait</a><a href="#plugin">Ses garde-fous</a><a href="#scripts">Ses scripts</a>'
  echo '</nav>'
  echo '<main>'
  echo '<header>'
  echo '<h1>Carte des flux du pack</h1>'
  echo "<p>Ce que fait le pack OpenCode installé, commande par commande : qui travaille, quelles questions il peut te poser, où il peut s&rsquo;arrêter. Générée depuis ses propres fichiers le $now ($ncmd commandes, $ntool outils, $nagent agents, $nskill savoirs, $nplugin fonctions du plugin, $nscript scripts).</p>"
  echo '<div class="marks" aria-label="Les issues d&rsquo;un run"><span><b>⏳</b> en cours</span><span><b>✅</b> fini</span><span><b>🚀</b> MR créée ou poussé</span><span><b>🔁</b> MR mise à jour</span><span><b>⏸</b> attend le PO</span><span><b>⛔</b> arrêté, avec la raison</span><span><b>❓</b> une question t&rsquo;attend</span></div>'
  echo '</header>'
  cat <<'EOF'
<section id="minute">
<h2>En une minute</h2>
<p><b>OpenCode</b> est un assistant de développement : on lui écrit une demande, un modèle d&rsquo;IA lit le code et agit. <b>Le pack</b> lui ajoute des <b>commandes</b> (des demandes toutes prêtes, qui commencent par une barre oblique : <code>/go</code>, <code>/tests</code>, <code>/push</code>), des <b>agents</b> (des rôles : un analyste, un développeur, un gardien des tests, un relecteur), des <b>savoirs</b> (des fiches qu&rsquo;un agent lit quand le sujet se présente) et des <b>scripts</b> qui font les gestes sensibles toujours de la même façon (commiter, pousser, mesurer la couverture).</p>
<p>Une commande déroule des <b>étapes</b>. Quand une décision t&rsquo;appartient, elle te pose un <b>QCM</b> : tu cliques une réponse, la recommandée est en premier. À la fin, un dernier QCM, « Suite », propose la commande d&rsquo;après. Des <b>garde-fous</b> empêchent ce qui ne doit jamais arriver : un secret qui part, un commit sur develop, un agent qui sort du dépôt.</p>
<p>Les schémas ci-dessous viennent des fichiers du pack : les titres des étapes sont écrits comme la commande les donne au modèle (en anglais) ; les explications en français sont celles du pack.</p>
</section>
EOF
} >> "$page"

# the map: the families of commands, the tools, the agents, the skills, the guardrails
{
  echo '<section id="carte"><h2>Carte d&rsquo;ensemble</h2><div class="mm">'
  echo "<div class=\"root\">Le pack OpenCode<small>$ncmd commandes · $nagent agents · $nskill savoirs · $nplugin garde-fous du plugin</small></div>"
  for fam in ticket free read other; do
    case "$fam" in
      ticket) title="Avec un ticket Jira"; color="#2f6b4f" ;;
      free) title="Sans ticket"; color="#6b4a9b" ;;
      read) title="Lire sans rien changer"; color="#2f5f8a" ;;
      other) title="Autres commandes"; color="#4b5661" ;;
    esac
    items=$(awk -F "$us" -v f="$fam" '$3 == f { print $2 }' "$tmp/cmds.sorted")
    [ -n "$items" ] || continue
    echo "<div class=\"branch\" style=\"--c: $color\"><h3>$title</h3><ul>"
    for name in $items; do
      line=$(lookup "$tmp/commands.fr" "$name" 3)
      [ -n "$line" ] || line=$(first_sentence "$(front "$pack/commands/$name.md" description)")
      echo "<li><code>/$name</code> $(esc "$line")</li>"
    done
    echo '</ul></div>'
  done
  if [ -s "$tmp/tools" ]; then
    echo '<div class="branch" style="--c: #8a6a12"><h3><code>/outil</code></h3><ul>'
    while IFS="$us" read -r name _ what; do
      echo "<li><code>$(esc "$name")</code> $(esc "$(first_sentence "$what" | awk '{ n = split($0, w, " "); s = ""; for (i = 1; i <= n && i <= 9; i++) s = s (s == "" ? "" : " ") w[i]; if (n > 9) s = s " …"; print s }')")</li>"
    done < "$tmp/tools"
    echo '</ul></div>'
  fi
  echo '<div class="branch" style="--c: #4b5661"><h3>Qui travaille</h3><ul>'
  while IFS="$us" read -r name mode steps writes; do
    echo "<li><code>$(esc "$name")</code> écrit : $(esc "$writes")</li>"
  done < "$tmp/agents"
  echo '<li><code>build</code> la conversation : ni commit, ni push</li></ul></div>'
  echo '<div class="branch" style="--c: #1f7470"><h3>Ce que le pack sait</h3><ul>'
  awk -F "$us" '$1 !~ /^pack-/ { print $1 }' "$tmp/skills" | while IFS= read -r name; do echo "<li><code>$(esc "$name")</code></li>"; done
  echo "<li>et $(grep -c '^pack-' "$tmp/skills") procédures d&rsquo;outils (<code>pack-…</code>)</li></ul></div>"
  echo '<div class="branch" style="--c: #a14d2a"><h3>Toujours vrai</h3><ul>'
  echo '<li>build et tests avant chaque push</li><li>un filet de tests avant de toucher du code existant</li><li>une preuve : rouge, puis vert, deux fois</li><li>aucun secret ne part, rien n&rsquo;est commité sur develop</li>'
  echo "<li>$nplugin fonctions du plugin veillent sur chaque commande</li></ul></div>"
  echo '</div></section>'
} >> "$page"

# one section per command: what it is for, how to start it, its steps as a diagram and as a list, its facts
: > "$tmp/facts"
while IFS="$us" read -r o name fam; do
  f="$pack/commands/$name.md"
  desc=$(front "$f" description)
  agent=$(front "$f" agent)
  plain=$(lookup "$tmp/commands.fr" "$name" 4)
  usage=$(printf '%s' "$desc" | sed -n 's/.*Usage *: *//p')
  awk -v agents="$agent_names" -f "$tmp/steps.awk" "$f" > "$tmp/steps-$name"
  pre=$(awk -F "$us" '$1 == "PRE" { print $2 }' "$tmp/steps-$name")
  ends=$(awk -F "$us" '$1 == "END" { print $2 }' "$tmp/steps-$name")
  suite=$(awk -F "$us" '$1 == "END" { print $3 }' "$tmp/steps-$name")
  nsteps=$(grep -c '^STEP' "$tmp/steps-$name")
  allq=$(awk -F "$us" '$1 == "STEP" && $5 != "" { print $5 }' "$tmp/steps-$name" | tr ',' '\n' | sed 's/^ *//' | awk 'NF && !seen[$0]++' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  alla=$(awk -F "$us" '$1 == "STEP" && $4 != "" { print $4 }' "$tmp/steps-$name" | tr ',' '\n' | sed 's/^ *//' | awk 'NF && !seen[$0]++' | tr '\n' ',' | sed 's/,$//; s/,/, /g')
  {
    echo "<section id=\"cmd-$name\">"
    echo "<h2><code>/$name</code> <span class=\"who\">agent ${agent:-build}${nsteps:+ · $nsteps étapes}</span></h2>"
    if [ -n "$plain" ]; then
      echo "<p class=\"plain\">$(esc "$plain")</p>"
    else
      echo "<p class=\"plain\">$(esc "$(first_sentence "$desc")")</p>"
    fi
    [ -n "$usage" ] && echo "<p class=\"usage\"><b>Comment la lancer :</b> <code>$(esc "$usage")</code></p>"
    if [ "$nsteps" -gt 0 ]; then
      # the diagram: the numbered steps one after the other, the lettered ones as alternatives of the step before them
      echo '<div class="diagram"><pre class="mermaid">'
      awk -F "$us" -v cmd="/$name" -v ends="$ends" '
        function lab(s) { gsub(/"/, "#quot;", s); gsub(/</, "#lt;", s); gsub(/>/, "#gt;", s); return s }
        BEGIN { print "flowchart TD"; print "  S([\"" lab(cmd) "\"])"; prev = "S"; from = "S"; i = 0 }
        $1 == "STEP" {
          i++; id = "N" i; extra = ""
          if ($4 != "") extra = extra (extra == "" ? "" : " · ") "🤖 " $4
          if ($5 != "") extra = extra (extra == "" ? "" : " · ") "❓ " $5
          if ($6 + 0 > 0) extra = extra (extra == "" ? "" : " · ") "⛔"
          print "  " id "[\"" lab(i ". " $3) (extra == "" ? "" : "<br/>" lab(extra)) "\"]"
          if ($2 == "alt") { print "  " from " -.-> " id }
          else { print "  " prev " --> " id; prev = id; from = id }
        }
        END { if (ends != "") { print "  E([\"" lab(ends) "\"])"; print "  " prev " --> E" } }' "$tmp/steps-$name" | sed 's/&/\&amp;/g'
      echo '</pre></div>'
      echo '<ol class="steps">'
      awk -F "$us" '$1 == "STEP" { print }' "$tmp/steps-$name" | while IFS="$us" read -r _ kind label ags qs stops scs; do
        chips=""
        [ -n "$ags" ] && chips="$chips <span class=\"chip ag\">🤖 $(esc "$ags")</span>"
        [ -n "$qs" ] && chips="$chips <span class=\"chip q\">❓ $(esc "$qs")</span>"
        [ "${stops:-0}" -gt 0 ] && chips="$chips <span class=\"chip stop\">⛔ peut s&rsquo;arrêter</span>"
        [ -n "$scs" ] && chips="$chips <span class=\"chip sc\">$(esc "$scs")</span>"
        if [ "$kind" = alt ]; then echo "<li class=\"alt\">$(esc "$label")$chips</li>"; else echo "<li>$(esc "$label")$chips</li>"; fi
      done
      echo '</ol>'
    fi
    if [ "$name" = outil ] && [ -s "$tmp/tools" ]; then
      echo '<div class="tablewrap"><table><thead><tr><th>Outil</th><th>Ce qu&rsquo;il fait</th></tr></thead><tbody>'
      while IFS="$us" read -r tname targs twhat; do
        echo "<tr><td><code>/outil $(esc "$tname")</code>${targs:+ <span class=\"usage\">$(esc "$targs")</span>}</td><td>$(esc "$twhat")</td></tr>"
      done < "$tmp/tools"
      echo '</tbody></table></div>'
    fi
    echo '<ul class="facts">'
    [ -n "$pre" ] && echo "<li><b>Calculé avant qu&rsquo;il lise ta demande</b>$(esc "$pre")</li>"
    [ -n "$alla" ] && echo "<li><b>Les agents qu&rsquo;il appelle</b>$(esc "$alla")</li>"
    [ -n "$allq" ] && echo "<li><b>Les questions qu&rsquo;il peut poser</b>$(esc "$allq")</li>"
    [ -n "$ends" ] && echo "<li><b>Comment il peut finir</b>$(esc "$ends")$([ "$suite" = yes ] && echo ', puis le QCM « Suite »')</li>"
    echo '</ul>'
    echo '</section>'
  } >> "$page"
  printf 'COMMANDE: /%s — %s — %s — %s étapes%s%s\n' "$name" "${agent:-build}" "$(first_sentence "${plain:-$desc}")" "$nsteps" "${alla:+ — agents : $alla}" "${allq:+ — questions : $allq}" >> "$tmp/facts"
done < "$tmp/cmds.sorted"

# the agents, the skills, the guardrails, the scripts
{
  echo '<section id="agents"><h2>Qui fait quoi</h2>'
  echo '<p>Le pilote orchestre ; chaque autre agent part d&rsquo;un contexte neuf, fait sa part et rend son rapport. Seuls les scripts du pack écrivent dans git.</p>'
  echo '<div class="tablewrap"><table><thead><tr><th>Agent</th><th>Son rôle</th><th>Ce qu&rsquo;il peut écrire</th></tr></thead><tbody>'
  while IFS="$us" read -r name mode steps writes; do
    role=$(lookup "$tmp/agents.fr" "$name" 2)
    [ -n "$role" ] || role=$(first_sentence "$(front "$pack/agents/$name.md" description)")
    echo "<tr><td><code>$(esc "$name")</code><br><span class=\"usage\">$([ "$mode" = subagent ] && echo 'sous-agent' || echo 'mène les commandes')${steps:+, $steps étapes au plus}</span></td><td>$(esc "$role")</td><td>$(esc "$writes")</td></tr>"
    printf 'AGENT: %s — %s — écrit : %s\n' "$name" "${mode:-?}" "$writes" >> "$tmp/facts"
  done < "$tmp/agents"
  echo '<tr><td><code>build</code><br><span class="usage">agent d&rsquo;OpenCode</span></td><td>La conversation : un essai, de la doc, un petit correctif, les outils de <code>/outil</code>.</td><td>le dépôt, jamais un commit ni un push</td></tr>'
  echo '</tbody></table></div></section>'

  echo '<section id="skills"><h2>Ce que le pack sait</h2>'
  echo '<p>Un savoir (skill) est une fiche qu&rsquo;un agent lit seulement quand le sujet se présente : il ne coûte rien le reste du temps.</p>'
  echo '<div class="tablewrap"><table><thead><tr><th>Savoir</th><th>Ce qu&rsquo;il apporte</th></tr></thead><tbody>'
  while IFS="$us" read -r name desc; do
    what=$(lookup "$tmp/skills.fr" "$name" 2)
    [ -n "$what" ] || what=$(first_sentence "$desc")
    echo "<tr><td><code>$(esc "$name")</code></td><td>$(esc "$what")</td></tr>"
    printf 'SKILL: %s — %s\n' "$name" "$what" >> "$tmp/facts"
  done < "$tmp/skills"
  echo '</tbody></table></div></section>'

  echo '<section id="plugin"><h2>Ses garde-fous</h2>'
  echo '<p>Le plugin du pack voit chaque demande, chaque commande d&rsquo;un agent et chaque requête au modèle ; ses fonctions sont numérotées dans son en-tête.</p>'
  echo '<div class="tablewrap"><table><thead><tr><th>N°</th><th>Ce qu&rsquo;il fait</th></tr></thead><tbody>'
  while IFS="$us" read -r n what; do
    fr=$(lookup "$tmp/plugin.fr" "$n" 2)
    [ -n "$fr" ] || fr=$what
    echo "<tr><td>$(esc "$n")</td><td>$(esc "$fr")</td></tr>"
    printf 'PLUGIN: %s. %s\n' "$n" "$fr" >> "$tmp/facts"
  done < "$tmp/plugin"
  echo '</tbody></table></div></section>'

  echo '<section id="scripts"><h2>Ses scripts</h2>'
  echo '<p>Les gestes qui doivent être identiques à chaque fois (commiter, pousser, mesurer, vérifier un environnement) sont des scripts : un agent les lance, il ne les refait jamais à la main.</p>'
  echo "<details><summary>Les $nscript scripts et leur rôle (en anglais, comme leur en-tête)</summary>"
  echo '<div class="tablewrap"><table><thead><tr><th>Script</th><th>Son en-tête</th></tr></thead><tbody>'
  while IFS="$us" read -r name what; do echo "<tr><td><code>$(esc "$name")</code></td><td>$(esc "$what")</td></tr>"; done < "$tmp/scripts"
  echo '</tbody></table></div></details></section>'
  echo "<footer>Générée par <code>/outil carte</code> (<code>pack-map.sh</code>) depuis <code>$(esc "$pack")</code> le $now. Après une mise à jour du pack, relance <code>/outil carte</code>.</footer>"
  echo '</main></div>'
  cat <<'EOF'
<script src="https://cdn.jsdelivr.net/npm/mermaid@11.16.1/dist/mermaid.min.js"></script>
<script>
// the diagrams, when the browser can load mermaid; otherwise each command keeps its list of steps
if (window.mermaid) {
  var dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches
  mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'neutral', flowchart: { useMaxWidth: true } })
  mermaid.run({ querySelector: 'pre.mermaid' })
}
</script>
</body>
</html>
EOF
} >> "$page"

if ! cp "$page" "$out" 2>/dev/null; then
  echo "STOP: cannot write $out"
  exit 1
fi
while IFS="$us" read -r name _ what; do printf 'OUTIL: %s — %s\n' "$name" "$(first_sentence "$what")"; done < "$tmp/tools" > "$tmp/tools.facts"
echo "CARTE: $out ($ncmd commandes, $ntool outils de /outil, $nagent agents, $nskill skills, $nplugin fonctions du plugin, $nscript scripts)"
cat "$tmp/facts" "$tmp/tools.facts"
exit 0
