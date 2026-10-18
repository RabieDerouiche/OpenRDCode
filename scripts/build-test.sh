#!/bin/sh
# Builds a .NET solution or project quietly, then runs its tests only if the build passed, in ONE call.
# Ends with explicit "BUILD:" and "TESTS:" lines: OpenCode shows the output of a command to the model, not its exit code.
# Usage: build-test.sh [--build-only] [<solution, project or folder>] [<dotnet test options>...]
#   build-test.sh                                         the solution or project of the current folder
#   build-test.sh src/App.sln                             a given solution (several solutions in the folder)
#   build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceServiceTests
#                                                         only some tests (the test project and what it references)
#   build-test.sh --build-only [<solution or project>]    the build only, to fix compilation errors
# Output: the build errors (each once) and the build summary, then the end of the test output (failures and totals),
# preceded by the summary line of the test assemblies that scrolled out of it. After a run of the whole solution
# (no target, or a .sln/.slnx, and no test option), a last line gives the code fingerprint that was built and tested
# (state-fingerprint.sh): /check does not run the build and tests again while the code keeps this fingerprint.
# An environment problem (dotnet missing from the PATH, the package feed refusing access, no .NET runtime for the
# test host) ends with an "ENVIRONMENT PROBLEM" line: the agent stops and tells the user instead of investigating.

# English output whatever the machine's language, so that the summaries below are found
DOTNET_CLI_UI_LANGUAGE=en
export DOTNET_CLI_UI_LANGUAGE

build_only=0
if [ "$1" = "--build-only" ]; then
  build_only=1
  shift
fi
target=""
case "$1" in
  ""|-*) ;;
  *) target=$1; shift ;;
esac

if ! command -v dotnet >/dev/null 2>&1; then
  echo "BUILD: NOT RUN"
  echo "ENVIRONMENT PROBLEM: dotnet is not in the PATH of OpenCode's shell. Stop and tell the user in one line: add DOTNET_ROOT and PATH to ~/.zshenv (see the README of the pack), then restart OpenCode. Do not look for dotnet and do not change any variable."
  exit 127
fi

# Whole solution: no test option, and no target or a solution file
whole=0
if [ $# -eq 0 ] && [ "$build_only" -eq 0 ]; then
  case "$target" in
    ""|*.sln|*.slnx) whole=1 ;;
  esac
fi
# Fingerprint of the code before the build: the code that is built and tested
fingerprint=""
[ "$whole" -eq 1 ] && fingerprint=$(sh "$(dirname "$0")/state-fingerprint.sh" 2>/dev/null)

out=$(mktemp "${TMPDIR:-/tmp}/build-test.XXXXXX") || exit 1
trap 'rm -f "$out"' EXIT
trap 'exit 1' INT TERM

dotnet build ${target:+"$target"} -nologo -v q -clp:ErrorsOnly > "$out" 2>&1
status=$?
tail -n 60 "$out"
if [ "$status" -ne 0 ]; then
  if [ "$build_only" -eq 1 ]; then echo "BUILD: FAILED (exit $status)"; else echo "BUILD: FAILED (exit $status) - tests not run"; fi
  if grep -q -E 'NU1301|Response status code does not indicate success: 40[13]|\((Unauthorized|Forbidden)\)' "$out"; then
    echo "ENVIRONMENT PROBLEM: the package feed (Artifactory) refused access or cannot be reached (NU1301, 401 or 403). Stop and tell the user in one line. Never read nuget.config, NuGet.Config or environment variables, and never retry with other options."
  fi
  exit "$status"
fi
echo "BUILD: OK"
[ "$build_only" -eq 1 ] && exit 0

dotnet test ${target:+"$target"} --no-build -nologo "$@" > "$out" 2>&1
status=$?
total=$(wc -l < "$out" | tr -d ' ')
if [ "$total" -gt 80 ]; then
  # Per-assembly results printed before the last 80 lines
  earlier=$(head -n "$((total - 80))" "$out" | grep -E 'Passed!|Failed!|Skipped!|Aborted|Test run summary')
  if [ -n "$earlier" ]; then
    echo "Earlier test results:"
    echo "$earlier"
    echo "..."
  fi
fi
tail -n 80 "$out"
if [ "$status" -ne 0 ]; then
  echo "TESTS: FAILED (exit $status)"
  if grep -q -E 'You must install (or update )?\.NET to run this application' "$out"; then
    echo "ENVIRONMENT PROBLEM: the test host does not find the .NET runtime (DOTNET_ROOT is missing). Stop and tell the user in one line: add DOTNET_ROOT to ~/.zshenv (see the README of the pack), then restart OpenCode."
  fi
elif ! grep -q '[^[:space:]]' "$out" || grep -q -E 'No test matches|No test is available|No test source files' "$out"; then
  echo "TESTS: NONE RUN (no test project for this target, or no test matches the filter)"
else
  echo "TESTS: OK"
fi
if [ -n "$fingerprint" ]; then
  echo "Code fingerprint of this run: $fingerprint (whole solution)"
fi
exit "$status"
