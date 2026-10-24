#!/bin/sh
# Runs the environment tests of the repository against one of its environments (AGENTS.md « ## Environnements »,
# environments.sh): the tests marked with the category Environment (xUnit [Trait("Category", "Environment")], NUnit
# [Category("Environment")], MSTest [TestCategory("Environment")]), and those marked EnvironmentWrites with --ecriture,
# where the environment allows it. They get, for this run only: API_BASE_URL (its URL), API_TOKEN (the value of the
# variable AGENTS.md names for it, set outside OpenCode: read here, never printed, masked in the output),
# API_ENVIRONMENT (its name) and API_WRITES (0 or 1). Outside this script they are skipped: they need API_BASE_URL.
# Never a production environment. Read-only by default: the GET of the API, and what the tests themselves undo.
# Usage: env-tests.sh <environment> [--ecriture] [<test project>] [--filter <VSTest filter>]
# Output: "ENVIRONMENT: <name> <url> (read only | writes allowed)", "PROJECT: <test project>", the BUILD and TESTS lines
# of build-test.sh, then one line per test (VSTest projects: "  OK  <name> (<s> s)" or "  FAILED  <name> (<s> s)",
# the name carrying the endpoint); "ENVIRONMENT PROBLEM:" when the environment cannot be reached from this machine or
# its token variable is not set; "STOP:" otherwise. Exit 0 when every test passed.

here=$(cd "$(dirname "$0")" && pwd)
name="" project="" writes=0 extra=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ecriture|--écriture|--allow-writes) writes=1; shift ;;
    --filter) extra=$2; shift 2 ;;
    -*) echo "STOP: unknown option $1 (env-tests.sh <environment> [--ecriture] [<test project>] [--filter <filter>])"; exit 1 ;;
    *) if [ -z "$name" ]; then name=$1; else project=$1; fi; shift ;;
  esac
done
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1

all=$(sh "$here/environments.sh")
printf '%s\n' "$all" | grep '^WARNING:'
envs=$(printf '%s\n' "$all" | grep -v '^WARNING:' | grep .)
names=$(printf '%s\n' "$envs" | cut -f1 | tr '\n' ' ' | sed 's/ $//')
if [ -z "$envs" ]; then
  echo "STOP: no environment declared in AGENTS.md. Add a section « ## Environnements », one line per environment, for example: - \`recette\` : https://api-recette.example.com (jeton : \`API_TOKEN_RECETTE\`) — COMMANDES.md, « Tests sur un environnement »"
  exit 1
fi
if [ -z "$name" ]; then
  echo "STOP: which environment? env-tests.sh <environment>: $names"
  exit 1
fi
line=$(printf '%s\n' "$envs" | awk -F '\t' -v n="$name" '$1 == n' | head -n 1)
[ -n "$line" ] || { echo "STOP: no environment $name in AGENTS.md (declared: $names)"; exit 1; }
url=$(printf '%s' "$line" | cut -f2)
tokenvar=$(printf '%s' "$line" | cut -f3)
allow=$(printf '%s' "$line" | cut -f4)
prod=$(printf '%s' "$line" | cut -f5)
if [ "$prod" = yes ]; then
  echo "STOP: $name is a production environment: the pack never runs tests there (a check of production is the CI's, with its own approval)"
  exit 1
fi
if [ "$writes" -eq 1 ] && [ "$allow" != yes ]; then
  echo "STOP: $name does not allow writes (AGENTS.md: « écriture permise » on its line): its read-only tests only, without --ecriture"
  exit 1
fi
token=""
if [ "$tokenvar" != - ]; then
  case "$tokenvar" in
    *[!A-Za-z0-9_]*|[0-9]*) echo "STOP: the token variable of $name is not a variable name: $tokenvar"; exit 1 ;;
  esac
  token=$(printenv "$tokenvar" 2>/dev/null)
  if [ -z "$token" ]; then
    echo "ENVIRONMENT PROBLEM: the variable $tokenvar, which holds the token of $name, is not set in the environment of OpenCode. Stop and tell the user in one line: set it in ~/.zshenv (export $tokenvar=…), then restart OpenCode. Never set it in a command, never read ~/.zshenv."
    exit 1
  fi
fi

# The projects of the environment tests: those whose test files carry the category
if [ -z "$project" ]; then
  project=$(git grep -l -E '(Trait|Category|TestCategory)[[:space:]]*\([[:space:]]*("Category",[[:space:]]*)?"Environment(Writes)?"' -- '*.cs' 2>/dev/null |
    while IFS= read -r f; do
      d=$(dirname "$f")
      while [ "$d" != . ] && [ -z "$(ls "$d"/*.csproj 2>/dev/null)" ]; do d=$(dirname "$d"); done
      ls "$d"/*.csproj 2>/dev/null | head -n 1
    done | sed 's#^\./##' | sort -u)
fi
if [ -z "$project" ]; then
  echo "STOP: no environment test in this repository (tests marked with the category Environment): /tests api writes them"
  exit 1
fi

echo "ENVIRONMENT: $name $url ($([ "$writes" -eq 1 ] && echo "writes allowed" || echo "read only"))"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/env-tests.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM HUP
# the output with the token masked: never printed, even by a test that would print a header
mask() {
  if [ -z "$token" ]; then cat "$1"; return; fi
  ENV_TESTS_TOKEN=$token awk 'BEGIN { t = ENVIRON["ENV_TESTS_TOKEN"] } { while ((i = index($0, t)) > 0) $0 = substr($0, 1, i - 1) "***" substr($0, i + length(t)); print }' "$1"
}
final=0 i=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  i=$((i + 1))
  echo "PROJECT: $p"
  kind=$(sh "$here/test-platform.sh" kind "$p" 2>/dev/null)
  case "$kind" in *" mstest "*) prop=TestCategory ;; *) prop=Category ;; esac
  filter="$prop=Environment"
  [ "$writes" -eq 1 ] && filter="$filter|$prop=EnvironmentWrites"
  [ -n "$extra" ] && filter="($filter)&($extra)"
  res="$tmp/results-$i"
  out="$tmp/out-$i"
  # one result per test (VSTest: a TRX report; a Microsoft.Testing.Platform project gives its summary only)
  set -- --filter "$filter"
  case "$kind" in vstest*) set -- "$@" --logger "trx;LogFileName=env-tests.trx" --results-directory "$res" ;; esac
  API_BASE_URL=$url API_TOKEN=$token API_ENVIRONMENT=$name API_WRITES=$writes \
    sh "$here/build-test.sh" "$p" "$@" > "$out" 2>&1
  status=$?
  mask "$out" > "$out.masked"
  cat "$out.masked"
  if [ -f "$res/env-tests.trx" ]; then
    mask "$res/env-tests.trx" | awk '
      function attr(name,   r) { if (match($0, name "=\"[^\"]*\"")) { r = substr($0, RSTART + length(name) + 2, RLENGTH - length(name) - 3); return r } return "" }
      /<UnitTestResult / {
        n = attr("testName"); o = attr("outcome"); d = attr("duration")
        split(d, t, ":"); secs = t[1] * 3600 + t[2] * 60 + t[3]
        printf "  %s  %s (%.2f s)\n", (o == "Passed" ? "OK" : o == "NotExecuted" ? "SKIPPED" : "FAILED"), n, secs
      }'
  fi
  if grep -q -E 'HttpRequestException|SocketException' "$out.masked" &&
    grep -q -E 'No such host is known|Name or service not known|nodename nor servname|Temporary failure in name resolution|Connection refused|actively refused|No route to host|Network is unreachable|SSL connection could not be established|remote certificate is invalid' "$out.masked"; then
    echo "ENVIRONMENT PROBLEM: $name ($url) cannot be reached from this machine (name resolution, network, VPN, proxy or certificate). Stop and tell the user in one line; never retry another way."
    status=1
  elif grep -q -E 'TaskCanceledException.*(HttpClient\.Timeout|timeout)' "$out.masked"; then
    echo "ENVIRONMENT PROBLEM: $name ($url) did not answer within the timeout of the tests. Stop and tell the user in one line."
    status=1
  fi
  [ "$status" -eq 0 ] || final=1
done <<EOF
$project
EOF
exit $final
