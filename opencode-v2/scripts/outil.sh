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
EOF
    exit 0 ;;
esac

# todo and stats: the result is shown to me at once, above the line that the pack plugin turns into my message
if [ "$name" = todo ]; then
  sh "$here/todo.sh" --raw "$rest"
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
esac
exit 0
