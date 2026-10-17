#!/bin/sh
# Builds a .NET solution or project quietly, then runs its tests only if the build passed, in ONE call.
# Ends with explicit "BUILD:" and "TESTS:" lines: OpenCode shows the output of a command to the model, not its exit code.
# Usage: build-test.sh [<solution, project or folder>] [<dotnet test options>...]
#   build-test.sh                                         the solution or project of the current folder
#   build-test.sh src/App.sln                             a given solution (several solutions in the folder)
#   build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceServiceTests
#                                                         only some tests (the test project and what it references)
# Output: the build errors (each once) and the build summary, then the end of the test output (failures and totals),
# preceded by the summary line of the test assemblies that scrolled out of it.

target=""
case "$1" in
  ""|-*) ;;
  *) target=$1; shift ;;
esac

out=$(mktemp "${TMPDIR:-/tmp}/build-test.XXXXXX") || exit 1
trap 'rm -f "$out"' EXIT
trap 'exit 1' INT TERM

dotnet build ${target:+"$target"} -nologo -v q -clp:ErrorsOnly > "$out" 2>&1
status=$?
tail -n 60 "$out"
if [ "$status" -ne 0 ]; then
  echo "BUILD: FAILED (exit $status) - tests not run"
  exit "$status"
fi
echo "BUILD: OK"

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
elif grep -q -E 'Passed!|Failed!|Skipped!|Test run summary|Total tests' "$out"; then
  echo "TESTS: OK"
else
  echo "TESTS: NONE RUN (no test project for this target, or no test matches the filter)"
fi
exit "$status"
