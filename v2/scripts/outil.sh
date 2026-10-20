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
  *)
    [ -n "$name" ] && echo "Outil inconnu : $name"
    cat <<'EOF'
Outils disponibles (/outil <nom> [arguments]) :
- doc [architecture|api|configuration|integrations|donnees|exploitation] [confluence <ESPACE> [<page parente>]] : documentation du dépôt dans docs/, depuis le code, sans aucune valeur de configuration
- audit [domaine] : audit des bonnes pratiques du dépôt, avec preuves et la plus petite façon d'ajouter ce qui manque
- licences [branche | <package> [version]] : packages NuGet devenus payants ou copyleft, avec l'option gratuite
- release-notes [<groupe>] : note de version d'une mise en production depuis master (plusieurs dépôts avec un groupe)
- pattern extract <nom> <dépôt source> [où : clé Jira, classes] · pattern apply <nom> [back|front] [consignes] : réutiliser une bonne implémentation d'un autre dépôt
- cqrs <command|query> <Nom> <Feature> : command ou query, handler, validator et tests (projets CQRS)
- setup [page Confluence] : crée ou met à jour l'AGENTS.md du dépôt (à faire une fois par dépôt)
- abandon : annule un ticket lancé par erreur (branche et fiche supprimées, avec ta validation)
- todo [texte | fait <n> | suppr <n> | rappels] : ta todo list personnelle, hors Jira
EOF
    exit 0 ;;
esac

# todo: the list is shown to me at once, above the line that the pack plugin turns into my message
if [ "$name" = todo ]; then
  sh "$here/todo.sh" --raw "$rest"
  echo "[[visible]]"
fi
echo "Outil : $name"
echo "Skill : outil-$name"
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
    sub=$1
    case "$sub" in
      extract|extraire)
        echo "Action : extract (nom : ${2:-manquant}, dépôt source : ${3:-manquant})"
        if [ -n "${3:-}" ]; then
          where=$(printf '%s' "$rest" | awk '{ $1 = ""; $2 = ""; $3 = ""; sub(/^ +/, ""); print }')
          echo "Dépôt source (détection, racine absolue, fichiers de projet) :"
          sh "$here/detect-project-type.sh" --files "$3"
          sh "$here/pattern-source.sh" "$3" "$where"
          echo "Packages du dépôt source :"
          sh "$here/package-refs.sh" "$3"
        fi
        echo "Skills de pattern de cette machine :"
        sh "$here/pattern-skills.sh" "${2:-}" ;;
      apply|appliquer)
        echo "Action : apply (nom : ${2:-manquant})"
        echo "État git et fiche ticket :"
        sh "$here/workflow-state.sh" --no-fetch --sheet
        echo "Détection du projet :"
        sh "$here/detect-project-type.sh"
        echo "Packages de ce dépôt :"
        sh "$here/package-refs.sh"
        echo "Skills de pattern de cette machine :"
        sh "$here/pattern-skills.sh" "${2:-}" ;;
      *)
        echo "Action : manquante (pattern extract <nom> <dépôt source> [où] ou pattern apply <nom> [back|front] [consignes])" ;;
    esac ;;
  cqrs)
    echo "Détection du projet :"
    sh "$here/detect-project-type.sh" ;;
  setup)
    echo "Détection du projet et fichiers :"
    sh "$here/detect-project-type.sh" --files ;;
  abandon)
    echo "État git (une récupération, puis l'état de la branche et de sa fiche) :"
    sh "$here/workflow-state.sh" ;;
  todo)
    echo "Résultat : déjà affiché au-dessus, tel quel" ;;
esac
exit 0
