#!/bin/sh
# What /fortify needs besides the measures of the tests (test-guardian.sh). Run from the repository.
#   prereq           dotnet, the Fortify SSC application line ("STOP:" when one lacks), then the unit test projects
#                    and the coverage collector of each of them (coverlet.collector with VSTest; with
#                    Microsoft.Testing.Platform, Microsoft.Testing.Extensions.CodeCoverage or coverlet.MTP):
#                    "PREREQ: NO TEST PROJECT" or "PREREQ: COVERLET MISSING", then "PREREQ: SETUP NEEDED"
#                    (test-guardian.sh setup, once the developer agreed), or "PREREQ: OK"
#   batch            creates the folder of the batch of this branch and prints it ("BATCH: <path>")
#   discard <label>  puts the uncommitted work of a failed vulnerability aside (git stash, recoverable), on the branch
#                    of a ticket only (/fortify, and a security finding of /fix): "DISCARDED:" with the commit of the
#                    stash, which names it whatever other stashes the worktrees of the repository add after it
# The batch folder: <git folder>/opencode-tickets/<KEY>.fortify (KEY from the branch): the vulnerability cards,
# shared by the worktrees, never committed. Exit 1 with one "STOP: <reason>" line when a check fails.
# Usage: fortify.sh prereq | batch | discard <label>

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
key=$(git branch --show-current 2>/dev/null | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
batch="$common/opencode-tickets/${key:-NOKEY}.fortify"

# The unit test projects: .csproj files that reference a test SDK or the MSTest package, say they are test projects,
# or are named so
test_projects() {
  git ls-files '*.csproj' | while read -r p; do
    if grep -qi 'Microsoft.NET.Test.Sdk\|MSTest.Sdk\|xunit.v3\|Include="MSTest"\|<IsTestProject>[[:space:]]*true' "$p" 2>/dev/null ||
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

case "$1" in
  prereq)
    command -v dotnet >/dev/null 2>&1 || stop "dotnet is not on the PATH of this machine (ENVIRONMENT PROBLEM: COMMANDES.md, « Environnement »)"
    echo "PREREQ: dotnet $(dotnet --version 2>/dev/null | head -n 1)"
    ssc=$(git grep -h '^APPSEC_PROJECT_NAME=' -- '*appsec-ci.env' 2>/dev/null | head -n 1)
    [ -n "$ssc" ] || stop "no APPSEC_PROJECT_NAME line in appsec-ci.env: the Fortify SSC application of this repository is unknown"
    echo "PREREQ: Fortify SSC application line found"
    # what the proofs need and is not there: the pilot asks the developer, then test-guardian.sh setup does it
    projects=$(test_projects)
    if [ -z "$projects" ]; then
      echo "PREREQ: NO TEST PROJECT: this repository has no unit test project, and /fortify proves each fix with unit tests. With the developer's agreement, test-guardian.sh setup xunit|mstest|nunit <the files of the batch> creates it (dotnet new template, coverlet.collector, solution), as the first commit of the batch"
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
      echo "PREREQ: SETUP NEEDED"
      exit 0
    fi
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
    # never on another branch than the branch of a ticket. The stash list is shared by every worktree of the
    # repository: the message names the key, the label and the folder, and the commit of the stash names it for good.
    [ -n "$key" ] || stop "not on the branch of a ticket (no key in the branch name): nothing put aside"
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
