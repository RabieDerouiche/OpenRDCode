#!/bin/sh
# What /fortify needs besides the measures of the tests (test-guardian.sh). Run from the repository.
#   prereq [--tests] a .NET project (a front-end repository: "STOP:"), dotnet and the SDK its global.json asks for
#                    ("ENVIRONMENT PROBLEM:"), the Fortify SSC application line ("STOP:" when one lacks; not with
#                    --tests, for /tests),
#                    then the unit test projects
#                    and the coverage collector of each of them (coverlet.collector with VSTest; with
#                    Microsoft.Testing.Platform, Microsoft.Testing.Extensions.CodeCoverage or coverlet.MTP):
#                    "PREREQ: NO TEST PROJECT" or "PREREQ: COVERLET MISSING", then "PREREQ: SETUP NEEDED"
#                    (test-guardian.sh setup, once the developer agreed), or "PREREQ: OK"; with --tests, in a Blazor
#                    repository, "PREREQ: COMPONENT TESTS:" says which unit test project has bUnit (the tests of a
#                    .razor component), or none (test-guardian.sh setup --components, once the developer agreed)
#   batch            creates the folder of the batch of this branch and prints it ("BATCH: <path>")
#   discard <label>  puts the uncommitted work of a failed vulnerability aside (git stash, recoverable), on the branch
#                    of a ticket or of a work without a ticket (/fortify, and a security finding of /fix; never on
#                    develop, master, main or a detached HEAD): "DISCARDED:" with the commit of the
#                    stash, which names it whatever other stashes the worktrees of the repository add after it
# The batch folder: <git folder>/opencode-tickets/<KEY>.fortify (KEY from the branch): the vulnerability cards,
# shared by the worktrees, never committed. Exit 1 with one "STOP: <reason>" line when a check fails.
# Usage: fortify.sh prereq [--tests] | batch | discard <label>

LC_ALL=C
export LC_ALL
DOTNET_CLI_UI_LANGUAGE=en DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_CLI_UI_LANGUAGE DOTNET_NOLOGO DOTNET_CLI_TELEMETRY_OPTOUT

stop() {
  echo "STOP: $1"
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not in a git repository"
here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 1
common=$(git rev-parse --git-common-dir) && common=$(cd "$common" && pwd)
branch=$(git branch --show-current 2>/dev/null)
key=$(printf '%s\n' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
# a branch named without its key (a change without a ticket, a branch given to /go): the key branch.sh recorded for it
[ -n "$key" ] || [ -z "$branch" ] || key=$(git config --get "branch.$branch.opencode-key" 2>/dev/null)
batch="$common/opencode-tickets/${key:-NOKEY}.fortify"

# The unit test projects: .csproj files that reference a test SDK or the MSTest package, say they are test projects,
# or are named so
test_projects() {
  git ls-files '*.csproj' | while read -r p; do
    if grep -qi 'Microsoft.NET.Test.Sdk\|MSTest.Sdk\|xunit.v3\|Include="MSTest"\|Include="TUnit\|<IsTestProject>[[:space:]]*true' "$p" 2>/dev/null ||
      printf '%s\n' "$p" | grep -qE '\.(Unit|Integration)?Tests?\.csproj$'; then
      echo "$p"
    fi
  done
}

# coverlet.collector for a project: in the project, or in a Directory.Build.props / Directory.Build.targets /
# Directory.Packages.props of one of its folders
has_coverlet() {
  grep -qi 'coverlet.collector' "$1" 2>/dev/null && return 0
  dir=$(dirname "$1")
  while :; do
    for f in Directory.Build.props Directory.Build.targets Directory.Packages.props; do
      grep -qi 'coverlet.collector' "$dir/$f" 2>/dev/null && return 0
    done
    [ "$dir" = "." ] || [ "$dir" = "/" ] && return 1
    dir=$(dirname "$dir")
  done
}

# The tests of Razor components, in a Blazor repository (for /go and /tests): the unit test projects that have bUnit,
# which renders a component in a test (the safety net of a page before it changes)
components() {
  [ "$tests" = --tests ] && [ -n "$(git ls-files '*.razor' 2>/dev/null | head -n 1)" ] || return 0
  with=$(for p in $1; do grep -qi 'Include="bunit"' "$p" 2>/dev/null && printf '%s ' "$p"; done)
  if [ -n "$with" ]; then
    echo "PREREQ: COMPONENT TESTS: bUnit in ${with% }"
  else
    echo "PREREQ: COMPONENT TESTS: none (no unit test project has bUnit, and a test of a .razor component renders it with bUnit: with the developer's agreement, test-guardian.sh setup --components adds it, as the first commit)"
  fi
}

case "$1" in
  prereq)
    # a repository without .NET project (a front-end): the proofs of /fortify and /tests are .NET unit tests
    [ -n "$(git ls-files '*.csproj' 2>/dev/null | head -n 1)" ] ||
      stop "no .NET project in this repository (front-end): /fortify and /tests write and prove .NET unit tests; a front-end fix goes through /go (its test first, with the test runner of the repository)"
    command -v dotnet >/dev/null 2>&1 || stop "dotnet is not on the PATH of this machine (ENVIRONMENT PROBLEM: COMMANDES.md, « Environnement »)"
    # the SDK of global.json missing: dotnet --version itself fails, and says why
    log=$(mktemp "${TMPDIR:-/tmp}/fortify-prereq.XXXXXX") || exit 1
    if ! dotnet --version > "$log" 2>&1; then
      sh "$here/dotnet-problem.sh" "$log" || echo "ENVIRONMENT PROBLEM: dotnet --version fails here: $(grep . "$log" | head -n 2 | tr '\n' ' ')"
      rm -f "$log"
      exit 1
    fi
    echo "PREREQ: dotnet $(head -n 1 "$log")"
    rm -f "$log"
    if [ "$2" != --tests ]; then
      ssc=$(git grep -h '^APPSEC_PROJECT_NAME=' -- '*appsec-ci.env' 2>/dev/null | head -n 1)
      [ -n "$ssc" ] || stop "no APPSEC_PROJECT_NAME line in appsec-ci.env: the Fortify SSC application of this repository is unknown"
      echo "PREREQ: Fortify SSC application line found"
    fi
    # what the proofs need and is not there: the pilot asks the developer, then test-guardian.sh setup does it
    projects=$(test_projects)
    tests=$2
    if [ -z "$projects" ]; then
      echo "PREREQ: NO TEST PROJECT: this repository has no unit test project, and /fortify and /tests prove their work with unit tests. With the developer's agreement, test-guardian.sh setup xunit|mstest|nunit <the files to test> creates it (dotnet new template, coverage collector, solution), as the first commit"
      components ""
      echo "PREREQ: SETUP NEEDED"
      exit 0
    fi
    missing=""
    for p in $projects; do
      kind=$(sh "$here/test-platform.sh" kind "$p")
      if [ "${kind%% *}" = mtp ]; then
        if [ "${kind##* }" != none ]; then echo "PREREQ: test project $p (Microsoft.Testing.Platform, coverage: ${kind##* })"; else missing="$missing $p"; fi
      elif has_coverlet "$p"; then
        echo "PREREQ: test project $p (coverlet.collector)"
      else
        missing="$missing $p"
      fi
    done
    if [ -n "$missing" ]; then
      echo "PREREQ: COVERLET MISSING in:$missing (the coverage collector: coverlet.collector, or Microsoft.Testing.Extensions.CodeCoverage for a Microsoft.Testing.Platform project). With the developer's agreement, test-guardian.sh setup adds it, as the first commit of the batch"
      components "$projects"
      echo "PREREQ: SETUP NEEDED"
      exit 0
    fi
    components "$projects"
    echo "PREREQ: OK"
    exit 0 ;;

  batch)
    # The folder of the batch of this branch, created: where the cards go
    [ -n "$key" ] || stop "not on the branch of a batch (no key in the branch name)"
    mkdir -p "$batch" || stop "cannot create $batch"
    echo "BATCH: $batch"
    exit 0 ;;

  discard)
    # Puts aside the uncommitted work of one vulnerability that failed or was interrupted, recoverable (git stash),
    # on the branch of a ticket or of a work without a ticket (/fix on a branch of /push), never on develop, master,
    # main or a detached HEAD. The stash list is shared by every worktree of the repository: the message names the
    # key (or the branch), the label and the folder, and the commit of the stash names it for good.
    case "$branch" in
      ""|develop|master|main) stop "not on a branch of its own (${branch:-detached HEAD}): nothing put aside" ;;
    esac
    [ -n "$key" ] || key=$branch
    label=${2:-work}
    printf '%s' "$label" | grep -qE '^[A-Za-z0-9._-]+$' || stop "bad label $label"
    n=$(git status --porcelain | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || { echo "DISCARDED: nothing to put aside"; exit 0; }
    git stash push -q --include-untracked -m "fortify $key $label ($(basename "$root"))" || stop "git could not put the changes aside"
    [ -z "$(git status --porcelain)" ] || stop "git put the changes aside, but files remain: $(git status --porcelain | head -n 3 | cut -c4- | tr '\n' ' ')"
    # the full commit: git stash reads a short one made of digits only as a position in the list (stash@{n})
    stash=$(git rev-parse "stash@{0}")
    echo "DISCARDED: $n files put aside in git stash « fortify $key $label ($(basename "$root")) », commit $stash. To look at them: git stash show -p $stash; to bring them back on this branch: git stash apply $stash"
    exit 0 ;;

  deps|coverage|compare|red|green|tests-only)
    stop "fortify.sh $1 is now test-guardian.sh $1 (the measures of the tests serve /go and /fix too)" ;;

  *) stop "usage: fortify.sh prereq | batch | discard <label>" ;;
esac
