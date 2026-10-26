#!/bin/sh
# For /outil: the tools of the pack outside the ticket workflow, behind one command. Prints the tool, the skill that
# holds its procedure, and the facts it needs, computed by the pack's scripts before the first turn (what each command
# of the first version injected). Without a known tool name: the list of the tools.
# Usage: outil.sh --raw "<tool> [arguments]"     what I typed after /outil, apostrophes included
#        outil.sh <tool> [arguments]

LC_ALL=C
export LC_ALL

here=$(cd "$(dirname "$0")" && pwd)
if [ "$1" = --raw ]; then
  text=$2
else
  text=$*
fi
# The first word is the tool, the rest is kept as typed
text=$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
name=${text%%[[:space:]]*}
rest=${text#"$name"}
rest=$(printf '%s' "$rest" | sed 's/^[[:space:]]*//')

case "$name" in
  doc|docs) name=doc ;;
  audit) ;;
  licences|licenses|licence|license) name=licences ;;
  release-notes|release|releasenotes|release-note) name=release-notes ;;
  pattern|patterns) name=pattern ;;
  cqrs) ;;
  setup|agents-md|agents) name=setup ;;
  abandon|abandonner) name=abandon ;;
  todo) ;;
  stats|statistiques|stat) name=stats ;;
  http|requetes|requêtes|requests) name=http ;;
  liens|lien|depots|dépôts|depots-lies|dépôts-liés|repos|related|repositories) name=liens ;;
  planifier|planification|planifie|planifications|schedule) name=planifier ;;
  carte|cartes|carte-des-flux|flux|map) name=carte ;;
  vitesse|lenteur|lenteurs|perf|performance|performances|speed|temps) name=vitesse ;;
  *)
    [ -n "$name" ] && echo "Outil inconnu : $name"
    cat <<'EOF'
Outils disponibles (/outil <nom> [arguments]) :
- doc [architecture|api|configuration|integrations|donnees|exploitation] [confluence <ESPACE> [<page parente>]] : documentation du dépôt dans docs/, depuis le code, sans aucune valeur de configuration
- audit [domaine] : audit des bonnes pratiques du dépôt, avec preuves et la plus petite façon d'ajouter ce qui manque
- licences [branche | <package> [version]] : packages NuGet devenus payants ou copyleft, avec l'option gratuite
- release-notes [<groupe>] : note de version d'une mise en production depuis master (plusieurs dépôts avec un groupe)
- pattern <nom> <dépôt source> [où : clé Jira, classes] : capture une bonne implémentation d'un autre dépôt en skill d'équipe ; ensuite /go s'en sert tout seul (ou /go <CLÉ> comme le pattern <nom>)
- cqrs <command|query> <Nom> <Feature> : command ou query, handler, validator et tests (projets CQRS)
- setup [page Confluence] : crée ou met à jour l'AGENTS.md du dépôt (à faire une fois par dépôt)
- abandon : annule un ticket lancé par erreur (branche et fiche supprimées, avec ta validation)
- todo [texte | fait <n> | suppr <n> | rappels] : ta todo list personnelle, hors Jira
- stats [<dépôt>...] : ce que /go et /fix ont fait sur tes tickets (étapes, interventions, décisions, arrêts, temps jusqu'à la MR)
- http [dossier] : les requêtes des endpoints de l'API pour le client HTTP de Rider, pas à pas (un fichier .http par contrôleur, les environnements d'AGENTS.md, le jeton OIDC demandé par Rider lui-même, tes secrets dans un fichier privé jamais commité)
- liens : les dépôts de la même application (front, API, librairies), pas à pas : leur rôle dans AGENTS.md, des deux côtés, et la lecture de leur code par les agents
- planifier [<heure> <jours> /commande | suppr <n>] : /daily, /outil audit, /outil licences ou /tests env <environnement> lancés tout seuls à heure fixe ; sans argument, pas à pas
- carte [<dossier ou page .html du dépôt>] : la carte des flux du pack, générée depuis ses propres fichiers (commandes et leurs étapes, agents, questions, outils, garde-fous), une page à ouvrir ou à présenter ; avec un chemin, écrite dans le dépôt pour la pousser
- vitesse [<nombre de runs>] [<commande>] : où passe le temps des derniers runs (modèle, sous-agents, outils, questions) et ce qui les a ralentis ou bloqués (passerelle, tampon, cache du serveur, réflexion, résumés), avec où agir
EOF
    exit 0 ;;
esac

# todo and stats: the result is shown to me at once, above the line that the pack plugin turns into my message
if [ "$name" = todo ]; then
  sh "$here/todo.sh" --raw "$rest"
  echo "[[visible]]"
fi
# planifier with a schedule or « suppr <n> »: done at once, shown to me; without argument, the wizard of its skill
if [ "$name" = planifier ] && [ -n "$rest" ]; then
  sh "$here/schedule.sh" --raw "$rest"
  echo "[[visible]]"
fi
# vitesse: the time of the last runs, measured by the pack plugin, shown at once
if [ "$name" = vitesse ]; then
  set -f
  # shellcheck disable=SC2086 # a count and a command, one per word
  sh "$here/vitesse.sh" $rest
  set +f
  echo "[[visible]]"
fi
if [ "$name" = stats ]; then
  set -f
  # shellcheck disable=SC2086 # the repositories given, one per word
  sh "$here/ticket-stats.sh" $rest
  set +f
  echo "[[visible]]"
fi
echo "Outil : $name"
echo "Skill : pack-$name"
# its file, for a skill OpenCode does not know yet (added since it started): where this OpenCode reads its skills
for f in "${OPENCODE_CONFIG_DIR:+$OPENCODE_CONFIG_DIR/skills/pack-$name/SKILL.md}" "$HOME/oc2/config/opencode/skills/pack-$name/SKILL.md" "$HOME/.config/opencode/skills/pack-$name/SKILL.md"; do
  [ -n "$f" ] && [ -f "$f" ] && { echo "Fichier du skill : $f"; break; }
done
echo "Arguments : ${rest:-aucun}"

# The words of the arguments, for the tools that take positional ones
set -f
# shellcheck disable=SC2086 # split on purpose
set -- $rest
set +f

case "$name" in
  doc)
    echo "Faits : calculés par le sous-agent doc-writer (il lance lui-même les scripts de la procédure)" ;;
  audit)
    echo "Détection du projet et fichiers :"
    sh "$here/detect-project-type.sh" --files
    echo "Packages :"
    sh "$here/package-refs.sh" ;;
  licences)
    echo "Résultat de package-licenses.sh $rest :"
    sh "$here/package-licenses.sh" "$rest" ;;
  release-notes)
    echo "Commits de master depuis la dernière mise en production de ce dépôt :"
    sh "$here/release-commits.sh" . --head ;;
  pattern)
    # "pattern <name> <source repository> [where]"; the older "pattern extract ..." still works
    case "$1" in
      extract|extraire) shift ;;
    esac
    case "$1" in
      apply|appliquer)
        echo "Action : apply n'existe plus. /go applique les patterns tout seul : /go <CLÉ> comme le pattern ${2:-<nom>}" ;;
      "")
        echo "Action : manquante (/outil pattern <nom> <dépôt source> [où : clé Jira, classes])" ;;
      *)
        echo "Action : extract (nom : $1, dépôt source : ${2:-manquant})"
        if [ -n "${2:-}" ]; then
          name_arg=$1
          source_arg=$2
          shift 2
          where="$*"
          echo "Dépôt source (détection, racine absolue, fichiers de projet) :"
          sh "$here/detect-project-type.sh" --files "$source_arg"
          sh "$here/pattern-source.sh" "$source_arg" "$where"
          echo "Packages du dépôt source :"
          sh "$here/package-refs.sh" "$source_arg"
          set -- "$name_arg"
        fi
        echo "Skills de pattern de cette machine :"
        sh "$here/pattern-skills.sh" "${1:-}" ;;
    esac ;;
  cqrs)
    echo "Détection du projet :"
    sh "$here/detect-project-type.sh" ;;
  setup)
    echo "Détection du projet et fichiers :"
    sh "$here/detect-project-type.sh" --files
    # the runner of each test project: what « Build & test » says, and why build-test.sh runs them as it does
    echo "Projets de tests (lanceur, framework, extension de couverture, projet) :"
    (
      cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0
      tests=$(sh "$here/test-platform.sh" projects)
      if [ -z "$tests" ]; then
        echo "  aucun"
        exit 0
      fi
      printf '%s\n' "$tests" | tr '\t' ' ' | sed 's/^/  /'
      if grep -qs '"runner"[[:space:]]*:[[:space:]]*"Microsoft.Testing.Platform"' global.json; then
        echo "  global.json : dotnet test en mode Microsoft.Testing.Platform"
      else
        echo "  global.json : pas d'option Microsoft.Testing.Platform pour dotnet test"
      fi
    ) ;;
  abandon)
    echo "État git (une récupération, puis l'état de la branche et de sa fiche) :"
    sh "$here/workflow-state.sh" ;;
  todo|stats)
    echo "Résultat : déjà affiché au-dessus, tel quel" ;;
  planifier)
    if [ -n "$rest" ]; then
      echo "Résultat : déjà affiché au-dessus, tel quel"
    else
      echo "Planifications actuelles (schedule.sh) :"
      sh "$here/schedule.sh"
      echo "Environnements (pour /tests env) :"
      sh "$here/environments.sh" | awk -F '\t' '/^WARNING:/ { next } { print "  - " $1 " " $2 ($5 == "yes" ? " (production : jamais planifiable)" : "") }'
      echo "Dépôt : $(cd "$(dirname "$(git rev-parse --git-common-dir 2>/dev/null || echo .)")" 2>/dev/null && pwd)"
    fi ;;
  http)
    echo "Plan des requêtes (http-files.sh --plan : rien n'est encore écrit) :"
    sh "$here/http-files.sh" --plan ${1:+"$1"} ;;
  liens)
    echo "Dépôts de cette machine et ce qui les lie (related-setup.sh scan) :"
    sh "$here/related-setup.sh" scan ;;
  carte)
    # without argument the page goes to the folder of the pack; with one, to that path of the repository (a folder:
    # carte-des-flux.html in it), to push it
    if [ -n "$1" ]; then
      case "$1" in
        /*|*..*) echo "Carte : « $1 » n'est pas un chemin du dépôt (relatif à sa racine, sans ..) : rien n'est écrit"; exit 0 ;;
        *.html) page=$1 ;;
        *) page="${1%/}/carte-des-flux.html" ;;
      esac
      echo "Carte des flux (pack-map.sh, dans le dépôt : $page) :"
      sh "$here/pack-map.sh" --out "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/$page"
    else
      echo "Carte des flux (pack-map.sh, dans le dossier du pack) :"
      sh "$here/pack-map.sh"
    fi ;;
esac
exit 0
