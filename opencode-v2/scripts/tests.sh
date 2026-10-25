#!/bin/sh
# For /tests: which mode the request asks, and the facts of that mode, computed by the pack's scripts before the first
# turn of the pilot (each wizard question is then built from them, without a call in between). Read-only.
#   (nothing)                 the menu: unit test candidates (production files changed lately that no test names),
#                             the API and its endpoints, the environments, the environment tests
#   env <environment> [--écriture] [--filter <filter>] | env <environment> <filter words>
#                             the environment and its settings (never a secret), its environment tests
#   env                       the launch wizard: the environments, their variables (set or not), the environment tests
#   env config [<environment>] (configurer, setup, ajouter, réglages): the configuration wizard: env-setup.sh scan
#   api [<controller, route or folder>] [<directives>]
#                             the workflow state, the endpoints (api-routes.sh), the pre-flight (api-preflight.sh), the
#                             environments
#   <classes, files, folders> the workflow state and the prerequisites of the unit tests (fortify.sh prereq --tests)
# Output: "Mode : <menu | env | env-launch | env-config | api | unit>", then the facts, each block under its title.
# Usage: tests.sh --raw "<what I typed after /tests>"

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
if [ "$1" = --raw ]; then text=$2; else text=$*; fi
text=$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
first=${text%%[[:space:]]*}
rest=${text#"$first"}
rest=$(printf '%s' "$rest" | sed 's/^[[:space:]]*//')
lower=$(printf '%s' "$first" | tr '[:upper:]' '[:lower:]')

envtests() {
  # the classes of environment tests, by their category
  n=$(git grep -l -E '(Trait|Category|TestCategory)[[:space:]]*\([[:space:]]*("Category",[[:space:]]*)?"Environment(Writes)?"' -- '*.cs' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n:-0}" -gt 0 ]; then
    echo "Tests d'environnement : $n fichier(s)"
    git grep -h -o -E 'class[[:space:]]+[A-Za-z0-9_]+EnvironmentTests' -- '*.cs' 2>/dev/null | sed 's/class[[:space:]]*/  - /' | sort -u | head -n 20
    git grep -q -E '"EnvironmentWrites"' -- '*.cs' 2>/dev/null && echo "  (des tests qui écrivent : EnvironmentWrites)"
  else
    echo "Tests d'environnement : aucun (/tests api les écrit)"
  fi
}
environments() {
  list=$(sh "$here/environments.sh")
  if [ -z "$(printf '%s\n' "$list" | grep -v '^WARNING:' | grep .)" ]; then
    echo "Environnements : aucun dans AGENTS.md"
  else
    echo "Environnements (AGENTS.md) :"
    printf '%s\n' "$list" | awk -F '\t' '
      /^WARNING:/ { print "  " $0; next }
      { printf "  - %s %s — %s%s%s\n", $1, $2, ($6 == "oidc" ? "OpenID Connect" : $6 == "token" ? "jeton fixe" : "sans jeton"), ($4 == "yes" ? ", écriture permise" : ""), ($5 == "yes" ? ", PRODUCTION (jamais testée)" : "") }'
  fi
}

case "$lower" in
  "")
    echo "Mode : menu"
    echo "Candidats aux tests unitaires (fichiers de production modifiés depuis 90 jours qu'aucun test ne nomme) :"
    git ls-files '*.cs' | grep -i -E '(^|/)[^/]*tests?[^/]*/' > "${TMPDIR:-/tmp}/tests-sh.$$" 2>/dev/null
    git log --since=90.days --name-only --pretty=format: -- '*.cs' 2>/dev/null | grep . | grep -v -i -E '(^|/)[^/]*tests?[^/]*/|(^|/)(Migrations|obj|bin)/|Program\.cs$|Startup\.cs$|\.Designer\.cs$|(Dto|Options|Settings|Request|Response|Command|Query|Controller|DbContext|Extensions|Module|Registration|Configuration|Endpoints?)\.cs$' |
      sort | uniq -c | sort -rn | while read -r count file; do
        [ -f "$file" ] || continue
        cls=$(basename "$file" .cs)
        # a test file that names the class: it has tests already
        [ -s "${TMPDIR:-/tmp}/tests-sh.$$" ] && xargs grep -l -E "(^|[^A-Za-z0-9_])$cls([^A-Za-z0-9_]|$)" < "${TMPDIR:-/tmp}/tests-sh.$$" 2>/dev/null | grep -q . && continue
        echo "  - $file ($count modification(s))"
      done | head -n 6
    rm -f "${TMPDIR:-/tmp}/tests-sh.$$"
    if git ls-files -- '*.csproj' | xargs grep -l 'Sdk="Microsoft.NET.Sdk.Web"' > /dev/null 2>&1; then
      n=$(sh "$here/api-routes.sh" 2>/dev/null | grep -c -E '^\| (GET|POST|PUT|PATCH|DELETE|ANY|HEAD|OPTIONS) ')
      echo "API ASP.NET Core : $n endpoint(s) ; projet de tests d'intégration : $(git ls-files -- '*.csproj' | xargs grep -l -i 'Microsoft.AspNetCore.Mvc.Testing' 2>/dev/null | head -n 1 | grep . || echo aucun)"
    else
      echo "API ASP.NET Core : aucune"
    fi
    environments
    envtests ;;
  env|environnement|environnements|environment)
    sub=${rest%%[[:space:]]*}
    lsub=$(printf '%s' "$sub" | tr '[:upper:]' '[:lower:]')
    case "$lsub" in
      config|configurer|configuration|setup|ajouter|réglages|reglages|regler|régler|parametrer|paramétrer|nouvel|nouveau)
        name=${rest#"$sub"}
        name=$(printf '%s' "$name" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
        echo "Mode : env-config"
        echo "Environnement visé : ${name:-un nouveau}"
        echo "Faits (env-setup.sh scan) :"
        sh "$here/env-setup.sh" scan
        # the path that tells the API is up, when the code maps one
        h=$(git grep -h -o -E 'MapHealthChecks\("[^"]+"' -- '*.cs' 2>/dev/null | head -n 1 | sed 's/.*("//; s/"$//')
        [ -n "$h" ] && echo "Santé : $h (MapHealthChecks dans le code)"
        envtests ;;
      "")
        echo "Mode : env-launch"
        environments
        echo "Variables de cette machine (présence seulement, vue au démarrage d'OpenCode : chaque commande relit ~/.zshenv, et env-tests.sh dit si l'une manque vraiment) :"
        sh "$here/env-setup.sh" scan | grep -E '^  variables: |^DECLARED: ' | sed 's/^/  /'
        envtests ;;
      *)
        echo "Mode : env"
        echo "Environnement : $sub"
        d=$(sh "$here/environments.sh" --details "$sub") || { echo "Absent d'AGENTS.md : $sub"; environments; exit 0; }
        printf '%s\n' "$d" | grep -E '^(url|auth|proxy|writes|production|invalid)=' | sed 's/^/  /'
        printf '%s\n' "$d" | grep '^WARNING:' | sed 's/^/  /'
        envtests ;;
    esac ;;
  api)
    echo "Mode : api"
    echo "État git :"
    sh "$here/workflow-state.sh" --no-fetch
    scope=${rest%%[[:space:]]*}
    [ -n "$scope" ] && [ ! -e "$scope" ] && scope=""
    echo "Pré-vol de l'API (api-preflight.sh) :"
    sh "$here/api-preflight.sh" ${scope:+"$scope"}
    echo "Endpoints (api-routes.sh${scope:+ $scope}) :"
    sh "$here/api-routes.sh" ${scope:+"$scope"}
    environments ;;
  *)
    echo "Mode : unit"
    echo "État git :"
    sh "$here/workflow-state.sh" --no-fetch
    echo "Prérequis (dotnet, projets de tests unitaires, collecteur de couverture) :"
    sh "$here/fortify.sh" prereq --tests ;;
esac
exit 0
