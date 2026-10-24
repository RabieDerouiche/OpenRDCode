#!/bin/sh
# Builds a .NET solution or project quietly, then runs its tests only if the build passed, in ONE call. A front-end
# folder (a package.json, no .NET project), or a repository without .NET project: front-test.sh does the same for it.
# Ends with explicit "BUILD:" and "TESTS:" lines: OpenCode shows the output of a command to the model, not its exit code.
# Usage: build-test.sh [--if-changed] [--pack] [--build-only | --no-build] [<solution, project or folder>] [<dotnet test options>...]
#   build-test.sh                                         the solution or project of the current folder
#   build-test.sh src/App.sln                             a given solution (several solutions in the folder)
#   build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceServiceTests
#                                                         only some tests (the test project and what it references)
#   build-test.sh --build-only [<solution or project>]    the build only, to fix compilation errors
#   build-test.sh --no-build <project> [<options>]        the tests only, of what was just built (test-guardian.sh)
#   build-test.sh --if-changed [<target>] [<options>]     nothing when the same code passed this same run already
#                                                         (/push after the conversation built and tested)
#   build-test.sh ClientApp [--filter <spec file or name>] a front-end package: its build, then its tests once
#   build-test.sh --pack [<solution or project>]          a library: then its packages ("PACK:"), into the git folder;
#                                                         package validation, when enabled, fails on a breaking change
#                                                         of the public API ("BREAKING CHANGE:" lines)
# Output: the build errors (each once) and the build summary, then the end of the test output (failures and totals),
# preceded by the summary line of the test assemblies that scrolled out of it; after a test failure, a line
# "FAILED TESTS (<n>): <names>" with every failed test of the run. After a run of the whole solution
# (no target, or a .sln/.slnx, and no test option), a last line gives the code fingerprint that was built and tested
# (state-fingerprint.sh): /check does not run the build and tests again while the code keeps this fingerprint.
# An environment problem (dotnet missing from the PATH, the SDK of global.json or the runtime of the tests not installed,
# a workload missing, the package feed refusing access: dotnet-problem.sh) ends with an "ENVIRONMENT PROBLEM" line: the
# agent stops and tells the user instead of investigating.
# A test that runs more than 5 minutes is stopped and named ("HANG:"), with VSTest, the default runner of dotnet test;
# its run files go to the git folder, never to the repository.
# Microsoft.Testing.Platform (MSTest.Sdk, the MSTest, NUnit or xUnit v3 runners, TUnit, or global.json): on the .NET 10
# SDK, `dotnet test` refuses these projects in its default mode, and takes other options in its MTP mode. Their tests
# run as the applications they are (test-platform.sh: `dotnet exec` of the test project's output, the options of the
# pack translated: the filter, the coverage, a time limit), the other test projects with dotnet test as before; a
# project that dotnet test refuses for this reason is run that way at once. Never `dotnet run`.
# One dotnet build or test run at a time in a working tree, shared with test-guardian.sh: a run that waits says
# "WAIT:" once (the test-guardians of a wave of /fortify or /fix work in parallel).

# English output whatever the machine's language, so that the summaries below are found
DOTNET_CLI_UI_LANGUAGE=en
export DOTNET_CLI_UI_LANGUAGE
HANG=${TEST_GUARDIAN_HANG:-5m}

# The lock of test-guardian.sh (same folder, same rules); not taken again under a script that holds it
gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null)
lockdir=${gitdir:+$gitdir/opencode-dotnet.lock}
take_lock() {
  [ -n "$lockdir" ] || return 0
  [ "${OPENCODE_DOTNET_LOCK:-}" = "$lockdir" ] && return 0
  waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    holder=$(cat "$lockdir/pid" 2>/dev/null)
    if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } || { [ -z "$holder" ] && [ "$waited" -ge 30 ]; }; then
      rm -rf "$lockdir"
      continue
    fi
    [ "$waited" -eq 0 ] && echo "WAIT: another build or test run of this folder is in progress: this one starts after it"
    if [ "$waited" -ge "${TEST_GUARDIAN_LOCK_WAIT:-900}" ]; then
      echo "BUILD: NOT RUN (another build or test run of this folder has been running for more than ${TEST_GUARDIAN_LOCK_WAIT:-900} s)"
      exit 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "$$" > "$lockdir/pid"
  OPENCODE_DOTNET_LOCK=$lockdir
  export OPENCODE_DOTNET_LOCK
}

build_only=0
no_build=0
if_changed=0
pack=0
while :; do
  case "$1" in
    --pack) pack=1; shift ;;
    --build-only) build_only=1; shift ;;
    --no-build) no_build=1; shift ;;
    --if-changed) if_changed=1; shift ;;
    *) break ;;
  esac
done
target=""
case "$1" in
  ""|-*) ;;
  *) target=$1; shift ;;
esac

# A front-end target (a folder with a package.json and no solution or project file of its own), or a repository without
# .NET project: front-test.sh builds it and runs its tests once, with the same BUILD and TESTS lines
front=0
if [ -n "$target" ]; then
  t=${target%/package.json}
  [ "$t" = package.json ] && t=.
  if [ -f "$t/package.json" ] && [ -z "$(find "$t" -maxdepth 1 \( -name '*.sln' -o -name '*.slnx' -o -name '*.csproj' \) 2>/dev/null | head -n 1)" ]; then
    front=1 target=$t
  fi
elif [ -z "$(git ls-files '*.sln' '*.slnx' '*.csproj' 2>/dev/null | head -n 1)" ] &&
  [ -n "$(git ls-files 'package.json' '*/package.json' 2>/dev/null | grep -v node_modules | head -n 1)" ]; then
  front=1
fi
if [ "$front" -eq 1 ]; then
  set -- ${target:+"$target"} "$@"
  [ "$if_changed" -eq 1 ] && set -- --if-changed "$@"
  [ "$build_only" -eq 1 ] && set -- --build-only "$@"
  [ "$no_build" -eq 1 ] && set -- --no-build "$@"
  exec sh "$(dirname "$0")/front-test.sh" "$@"
fi

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
{ [ "$whole" -eq 1 ] || [ "$if_changed" -eq 1 ]; } && fingerprint=$(sh "$(dirname "$0")/state-fingerprint.sh" 2>/dev/null)
# The last run of this working tree that built and passed its tests: its code fingerprint and its target and options.
# --if-changed: the same again is not run again
green=${gitdir:+$gitdir/opencode-green}
runkey=""
if [ -n "$fingerprint" ] && [ -n "$green" ] && [ "$build_only" -eq 0 ] && [ "$no_build" -eq 0 ]; then
  runkey="$fingerprint $(printf '%s\n' "$target" "$@" "pack=$pack" | cksum | cut -d' ' -f1)"
fi
if [ "$if_changed" -eq 1 ] && [ -n "$runkey" ] && [ "$(head -n 1 "$green" 2>/dev/null)" = "$runkey" ]; then
  echo "BUILD: OK (not run again: this same code passed this build on $(sed -n 2p "$green"))"
  if [ "$(sed -n 3p "$green")" = none ]; then
    echo "TESTS: NONE RUN (not run again: same code, same target and options; $(sed -n 4p "$green" | grep . || echo "no test project for this target, or no test matches the filter"))"
  else
    echo "TESTS: OK (not run again: same code, same target and options)"
  fi
  exit 0
fi

out=$(mktemp "${TMPDIR:-/tmp}/build-test.XXXXXX") || exit 1
one="$out.one"
# the output files go even when the wait for the lock gives up; the lock is released only by the run that took it
trap 'rm -f "$out" "$one"' EXIT
trap 'exit 1' INT TERM HUP
mine=""
[ "${OPENCODE_DOTNET_LOCK:-}" = "$lockdir" ] || mine=1
take_lock
if [ -n "$mine" ] && [ -n "$lockdir" ]; then
  trap 'rm -f "$out" "$one"; rm -rf "$lockdir"' EXIT
fi

if [ "$no_build" -eq 1 ]; then
  : > "$out"
  status=0
else
  dotnet build ${target:+"$target"} -nologo -v q -clp:ErrorsOnly > "$out" 2>&1
  status=$?
fi
tail -n 60 "$out"
if [ "$status" -ne 0 ]; then
  # Distinct errors: MSBuild may print the same error once per project that builds the file
  errors=$(grep -E ': error [A-Z]+[0-9]+' "$out" | sed -E 's/ \[[^]]*\]$//' | sort -u | wc -l | tr -d ' ')
  if [ "$build_only" -eq 1 ]; then
    echo "BUILD: FAILED (exit $status, $errors distinct errors)"
  else
    echo "BUILD: FAILED (exit $status, $errors distinct errors) - tests not run"
  fi
  # the machine, not the code: an SDK, a runtime, a workload, the package feed (dotnet-problem.sh)
  if sh "$(dirname "$0")/dotnet-problem.sh" "$out"; then
    :
  elif [ "$errors" -gt 0 ]; then
    echo "NOTE: this is the complete list for the projects that were compiled. A project that references a project with errors is not compiled at all (its own errors, test projects included, appear only once these are fixed). Fix these errors, then build again: the same build without a change gives the same output."
  fi
  exit "$status"
fi
if [ "$no_build" -eq 1 ]; then echo "BUILD: NOT RUN (--no-build: the tests of the last build)"; else echo "BUILD: OK"; fi
# --pack (a library): its packages, as the CI makes them, into the git folder; package validation, when the project
# enables it, compares the public API with the baseline package and fails on a breaking change
do_pack() {
  [ -n "$gitdir" ] || { echo "PACK: NOT RUN (not in a git repository)"; return 1; }
  packs="$gitdir/opencode-pack"
  rm -rf "$packs"
  # (the status read right after the command: after an if without else, $? would be 0)
  # the configuration of the build above (dotnet pack builds Release by default since the .NET 8 SDK)
  dotnet pack ${target:+"$target"} --no-build -c Debug -nologo -v q -o "$packs" > "$out" 2>&1
  pstatus=$?
  if [ "$pstatus" -eq 0 ]; then
    made=$(find "$packs" -name '*.nupkg' ! -name '*.symbols.nupkg' 2>/dev/null | sed 's#.*/##' | sort | tr '\n' ' ' | sed 's/ $//')
    if [ -n "$made" ]; then echo "PACK: OK ($made)"; else echo "PACK: NONE (no packable project in this target)"; fi
    return 0
  fi
  grep -E ': error CP[0-9]+' "$out" | sed -E 's/ \[[^]]*\]$//; s/^.*: error (CP[0-9]+): /BREAKING CHANGE: \1: /' | sort -u | head -n 20
  breaking=$(grep -E ': error CP[0-9]+' "$out" | sed -E 's/ \[[^]]*\]$//' | sort -u | grep -c .)
  if [ "$breaking" -gt 0 ]; then
    echo "PACK: FAILED (package validation: $breaking breaking change$([ "$breaking" -eq 1 ] || echo s) of the public API against the baseline package): restore what the consumers use, or the change is a major version (the merge request says it, never a suppression file written to hide it)"
  else
    tail -n 30 "$out"
    sh "$(dirname "$0")/dotnet-problem.sh" "$out" || echo "PACK: FAILED (exit $pstatus)"
  fi
  return "$pstatus"
}
if [ "$build_only" -eq 1 ]; then
  [ "$pack" -eq 1 ] && { do_pack; exit $?; }
  exit 0
fi

# A hanging test is stopped and named (VSTest blame): unless the caller set it, or the repository runs
# Microsoft.Testing.Platform (global.json), whose options differ; the run files go to the git folder
blame=1
case " $* " in *" --blame"*) blame="" ;; esac
grep -qs '"runner"[[:space:]]*:[[:space:]]*"Microsoft.Testing.Platform"' "$(git rev-parse --show-toplevel 2>/dev/null)/global.json" && blame=""
[ -n "$gitdir" ] || blame=""
results=""
case " $* " in *" --results-directory"*) ;; *) [ -n "$blame" ] && results="$gitdir/opencode-test-results" ;; esac
[ -n "$results" ] && rm -rf "$results"
# dotnet test in its default mode (VSTest), for a target
vstest_run() {
  run_target=$1
  shift
  if [ -n "$blame" ]; then
    dotnet test ${run_target:+"$run_target"} --no-build -nologo --blame-hang-timeout "$HANG" --blame-hang-dump-type none \
      ${results:+--results-directory "$results"} "$@"
  else
    dotnet test ${run_target:+"$run_target"} --no-build -nologo "$@"
  fi
}
# The test projects of the target and how each one runs (test-platform.sh): VSTest or Microsoft.Testing.Platform
platform="$(dirname "$0")/test-platform.sh"
scope=$(sh "$platform" scope ${target:+"$target"})
mtp=$(printf '%s\n' "$scope" | awk -F '\t' '$1 == "mtp" { print $2 }')
vst=$(printf '%s\n' "$scope" | awk -F '\t' '$1 == "vstest" { print $2 }')
MTP_REFUSAL='no longer supported by M\(icrosoft\.Testing\.Platform\|TP\)\|aka\.ms/dotnet-test-mtp-error'
# Each project on its own: dotnet test for the VSTest ones (a project that it refuses for Microsoft.Testing.Platform:
# its test application), the test application for the MTP ones
per_project() {
  : > "$out"
  status=0
  if [ -n "$vst" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if vstest_run "$p" "$@" > "$one" 2>&1; then
        cat "$one" >> "$out"
      elif grep -q "$MTP_REFUSAL" "$one"; then
        echo "NOTE: $p runs on Microsoft.Testing.Platform, refused by dotnet test in its default mode on this SDK: run as its test application (test-platform.sh)" >> "$out"
        sh "$platform" run "$p" "$@" >> "$out" 2>&1 || status=1
      else
        cat "$one" >> "$out"
        status=1
      fi
    done <<LIST
$vst
LIST
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    sh "$platform" run "$p" "$@" >> "$out" 2>&1 || status=1
  done <<LIST
$mtp
LIST
}
mixed=0
tests_ok=0
why=""
# why no test ran: no test project, a filter that matches nothing, or test projects whose tests did not run (none
# written yet, or a solution that does not build them)
none_run() {
  n=$(printf '%s\n' "$scope" | grep -c .)
  case " $* " in
    *" --filter "*|*" --filter="*) why="no test matches the filter" ;;
    *) if [ "$n" -eq 0 ]; then why="no test project for this target"
       else why="$n test project(s) in this target, but no test ran: none written yet, or the build skipped them"; fi ;;
  esac
  echo "TESTS: NONE RUN ($why)"
}
if [ -z "$mtp" ]; then
  vstest_run "$target" "$@" > "$out" 2>&1
  status=$?
  # dotnet test of the .NET 10 SDK refuses a Microsoft.Testing.Platform v2 project in its default mode: those run as
  # applications, the others as before
  if grep -q "$MTP_REFUSAL" "$out"; then
    refused=$(grep "$MTP_REFUSAL" "$out" | grep -oE '[^] ["]+\.[cf]sproj' | sed 's#\\#/#g' | sort -u)
    all=$(printf '%s\n' "$scope" | cut -f2)
    [ -n "$all" ] || all=$refused
    [ -n "$refused" ] || refused=$all
    mtp="" vst=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      pattern=$(printf '%s' "${p#./}" | sed 's/[].[*^$\\]/\\&/g')
      if printf '%s\n' "$refused" | grep -qE "(^|/)$pattern\$"; then
        mtp="$mtp$p
"
      else
        vst="$vst$p
"
      fi
    done <<LIST
$all
LIST
    echo "NOTE: $(printf '%s' "$mtp" | grep -c .) test project(s) on Microsoft.Testing.Platform, refused by dotnet test in its default mode on this SDK: run as test applications (test-platform.sh)"
    mixed=1
    per_project "$@"
  fi
else
  mixed=1
  per_project "$@"
fi
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
  # The names of the failed tests, from the whole output (VSTest: "Failed <name> [12 ms]"; Microsoft.Testing.Platform:
  # "failed <name> (12ms)"): /go compares them with the tests that already failed on develop before the ticket
  failed=$(sed -n \
    -e 's/^[[:space:]]*Failed[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}\[[^]]*\][[:space:]]*$/\1/p' \
    -e 's/^[[:space:]]*failed[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}([0-9][^)]*)[[:space:]]*$/\1/p' "$out" |
    sort -u)
  if [ -n "$failed" ]; then
    count=$(printf '%s\n' "$failed" | grep -c .)
    echo "FAILED TESTS ($count): $(printf '%s\n' "$failed" | head -n 25 | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { print "" }')$([ "$count" -gt 25 ] && echo " (+$((count - 25)) more)")"
  fi
  # a test host that hung or crashed: the test that was running
  if grep -q 'test run was aborted\|Test Run Aborted' "$out"; then
    running=$(awk '/The test running when the crash occurred:/ { on = 1; next } on && NF { print; n++ } on && !NF && n { exit }' "$out" | head -n 3 | tr '\n' ' ')
    if grep -q 'inactivity time of' "$out"; then
      echo "HANG: a test ran more than $HANG and was stopped: ${running:-unknown test}. A unit test never waits for the network, a real clock or a lock: fix that test (or report it), never raise the limit"
    else
      echo "CRASH: the test host stopped (a stack overflow or an exit of the process) during: ${running:-unknown test}"
    fi
  fi
  echo "TESTS: FAILED (exit $status)"
  # a runtime the tests need and the machine lacks, DOTNET_ROOT missing (dotnet-problem.sh)
  sh "$(dirname "$0")/dotnet-problem.sh" "$out" || :
elif [ "$mixed" -eq 1 ]; then
  # several runs: the tests that ran, summed over the VSTest summaries and the Microsoft.Testing.Platform ones
  ran=$(awk '/(Passed|Failed)!/ { if (match($0, /Total: *[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); n += s } }
             /^ *total: *[0-9]+/ { s = $0; gsub(/[^0-9]/, "", s); n += s }
             END { print n + 0 }' "$out")
  if [ "$ran" -eq 0 ]; then
    none_run "$@"
  else
    echo "TESTS: OK ($ran test$([ "$ran" -eq 1 ] || echo s))"
    tests_ok=1
  fi
else
  # the tests that ran, from the summary of each test assembly: a project of the target whose tests the filter leaves
  # out, or that has no test yet, says so beside those of the others, which ran
  ran=$(awk '/(Passed|Failed)!/ { if (match($0, /Total: *[0-9]+/)) { s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); n += s } }
             END { print n + 0 }' "$out")
  if [ "$ran" -eq 0 ] && { ! grep -q '[^[:space:]]' "$out" || grep -q -E 'No test matches|No test is available|No test source files' "$out"; }; then
    none_run "$@"
  else
    echo "TESTS: OK"
    tests_ok=1
  fi
fi
if [ "$pack" -eq 1 ] && [ "$status" -eq 0 ]; then
  do_pack || status=1
fi
# a repository that also holds a front-end package (an ASP.NET Core + Angular or React application): its build and its
# tests are another run
if [ "$whole" -eq 1 ]; then
  fronts=$(git ls-files 'package.json' '*/package.json' 2>/dev/null | grep -v -E '(^|/)node_modules/' | while IFS= read -r f; do
    grep -q -E '"(@angular/core|react|vue|svelte|next|nuxt)"[[:space:]]*:' "$f" 2>/dev/null && dirname "$f"; done | head -n 3 | tr '\n' ' ')
  [ -n "$fronts" ] && echo "NOTE: this repository also holds a front-end package (${fronts% }), not built here: when the branch changes it, its build and its tests are sh ~/.config/opencode/scripts/build-test.sh <its folder>"
fi
if [ -n "$fingerprint" ] && [ "$whole" -eq 1 ]; then
  echo "Code fingerprint of this run: $fingerprint (whole solution)"
fi
# a green run is remembered for --if-changed, with what its tests said (a build without any test to run included, with
# why no test ran)
if [ -n "$runkey" ] && [ "$status" -eq 0 ]; then
  if [ "$tests_ok" -eq 1 ]; then
    printf '%s\n%s\nok\n' "$runkey" "$(date '+%Y-%m-%d %H:%M')"
  else
    printf '%s\n%s\nnone\n%s\n' "$runkey" "$(date '+%Y-%m-%d %H:%M')" "$why"
  fi > "$green" 2>/dev/null
fi
exit "$status"
