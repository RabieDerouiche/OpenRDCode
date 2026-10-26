#!/bin/sh
# Tests of the pack's .NET scripts (build-test.sh, test-platform.sh, test-guardian.sh, fortify.sh prereq,
# blazor-native.sh, automapper.sh) with a fake dotnet (tools/fake-dotnet.sh): VSTest, Microsoft.Testing.Platform (xUnit v3, MSTest.Sdk,
# TUnit), a solution that mixes them, a project that dotnet test of the .NET 10 SDK refuses, an application that leaves
# Blazorise. No .NET SDK needed; the real one is tried by the first run on a developer's machine.
# Usage, from opencode-v2/: sh tools/dotnet-test.sh [<shell>] (default sh).
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
work=$(mktemp -d "${TMPDIR:-/tmp}/dotnet-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
HOME="$work/home"
mkdir -p "$HOME" "$work/bin" "$work/state"
export HOME
cp "$pack/tools/fake-dotnet.sh" "$work/bin/dotnet"
chmod +x "$work/bin/dotnet"
PATH="$work/bin:$PATH"
FAKE_DOTNET_LOG="$work/dotnet.log"
FAKE_DOTNET_STATE="$work/state"
TMPDIR="$work/tmp"
mkdir -p "$TMPDIR"
export PATH FAKE_DOTNET_LOG FAKE_DOTNET_STATE TMPDIR
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
git config --global init.defaultBranch develop

pass=0
fail=0
check() {
  # check <name> <expected exit: 0|1|any> <grep pattern of the output> [<pattern that must not appear>]
  name=$1 want=$2 pattern=$3 absent=$4
  ok=1
  case "$want" in
    any) ;;
    *) [ "$status" -eq "$want" ] || ok=0 ;;
  esac
  printf '%s\n' "$out" | grep -qE -- "$pattern" || ok=0
  [ -n "$absent" ] && printf '%s\n' "$out" | grep -qE -- "$absent" && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}
run() {
  script=$1
  shift
  : > "$FAKE_DOTNET_LOG"
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
  calls=$(cat "$FAKE_DOTNET_LOG")
  cat "$FAKE_DOTNET_LOG" >> "$work/all-calls.log"
}
called() {
  # called <name> <grep pattern of the dotnet calls> [<pattern that must not appear>]
  if printf '%s\n' "$calls" | grep -qE -- "$2" && { [ -z "$3" ] || ! printf '%s\n' "$calls" | grep -qE -- "$3"; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 (dotnet calls)"
    printf '%s\n' "$calls" | sed 's/^/    /'
  fi
}
truth() {
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 ($2)"; fi
}
project() {
  # project <path> <sdk line> <body lines...>
  mkdir -p "$(dirname "$1")"
  f=$1 sdk=$2
  shift 2
  { echo "<Project Sdk=\"$sdk\">"
    echo "  <PropertyGroup>"
    echo "    <TargetFramework>net10.0</TargetFramework>"
    echo "  </PropertyGroup>"
    for l in "$@"; do echo "  $l"; done
    echo "</Project>"; } > "$f"
}

# ---------- a VSTest repository: App.sln, src/App, tests/App.Tests (xUnit v2, coverlet.collector) ----------
mkdir -p "$work/vs"
cd "$work/vs" || exit 1
git init -q
project src/App/App.csproj Microsoft.NET.Sdk
printf 'namespace App;\npublic class Invoice {\n  public int Total() => 1;\n}\n' > src/App/Invoice.cs
project tests/App.Tests/App.Tests.csproj Microsoft.NET.Sdk \
  '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '  <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />' \
  '  <PackageReference Include="coverlet.collector" Version="6.0.2" />' '</ItemGroup>' \
  '<!-- fake-test: App.Tests.InvoiceTests.Total pass -->' '<!-- fake-test: App.Tests.InvoiceTests.Tax pass -->' \
  '<!-- fake-test: App.Tests.OrderTests.Ship pass -->' '<!-- fake-cover: src/App/Invoice.cs 2:1 3:1 4:0 -->'
cat > App.sln <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "src\App\App.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App.Tests", "tests\App.Tests\App.Tests.csproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
EOF
echo 'APPSEC_PROJECT_NAME=app' > appsec-ci.env
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init

run test-platform.sh kind tests/App.Tests/App.Tests.csproj
check "kind: VSTest xUnit v2" 0 '^vstest xunit2 none$'
run test-platform.sh scope App.sln
check "scope: the test project of the solution only" 0 "^vstest	tests/App.Tests/App.Tests.csproj$" 'src/App'

run build-test.sh
check "VSTest: whole solution" 0 '^TESTS: OK$' 'NOTE|exec'
check "VSTest: fingerprint after the whole solution" 0 '^Code fingerprint of this run: '
called "VSTest: one dotnet test with the blame, no exec, no run" '^dotnet test --no-build -nologo --blame-hang-timeout 5m' '^dotnet (exec|run)'
truth "VSTest: one dotnet test call" '[ "$(printf "%s\n" "$calls" | grep -c "^dotnet test")" -eq 1 ]'

run build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceTests
check "VSTest: a filter" 0 '^TESTS: OK$'
called "VSTest: the filter as given" '^dotnet test tests/App.Tests/App.Tests.csproj --no-build .*--filter FullyQualifiedName~InvoiceTests'
run build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~Nothing
check "VSTest: a filter that matches nothing, said so" 0 '^TESTS: NONE RUN \(no test matches the filter\)$'
# a test project without any test yet (just set up): not « no test project »
mkdir -p tests/Empty.Tests
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <ItemGroup>\n    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />\n  </ItemGroup>\n</Project>\n' > tests/Empty.Tests/Empty.Tests.csproj
git add -A && git commit -q -m "test: an empty test project"
run build-test.sh tests/Empty.Tests/Empty.Tests.csproj
check "VSTest: a test project without tests, said so" 0 '^TESTS: NONE RUN \(1 test project\(s\) in this target, but no test ran'
# beside a test project whose tests run: they ran, whatever the empty one says (the memory of the last green run of
# the solution kept aside, for --if-changed below)
green="$(git rev-parse --absolute-git-dir)/opencode-green"
cp "$green" "$work/green.kept"
{ cat App.sln; printf 'Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Empty.Tests", "tests\\Empty.Tests\\Empty.Tests.csproj", "{33333333-3333-3333-3333-333333333333}"\nEndProject\n'; } > Both.sln
run build-test.sh Both.sln
check "VSTest: tests that ran beside a test project without tests: OK" 0 '^TESTS: OK$' 'NONE RUN'
run build-test.sh Both.sln --filter FullyQualifiedName~InvoiceTests
check "VSTest: a filter that only one test project matches: OK" 0 '^TESTS: OK$' 'NONE RUN'
# its coverage before its first test: coverlet writes its report, each line of the code at 0
sed -i 's#</Project>#  <ItemGroup><ProjectReference Include="../../src/App/App.csproj" /></ItemGroup>\n  <!-- fake-cover: src/App/Invoice.cs c=App.Invoice m=Total 3:0 -->\n</Project>#' tests/Empty.Tests/Empty.Tests.csproj
run test-guardian.sh coverage empty tests/Empty.Tests/Empty.Tests.csproj src/App/Invoice.cs
check "coverage before the first test: no test ran" 0 '^TESTS: 0 passed, 0 failed$' '^STOP'
check "…each line of the file at 0" 0 '^src/App/Invoice.cs lines 0/1 \(0%\) branches 0/0 uncovered 3$'
run test-guardian.sh net empty src/App/Invoice.cs:Total
check "…its net: THIN" 0 '^SAFETY NET: THIN \(0/1 lines of this method run by the tests, 0% < 80%\)'
# a runner that writes no report when no test runs: the same 0 %, never taken for a missing collector
sed -i 's#</Project>#  <!-- fake-no-cover-without-tests -->\n</Project>#' tests/Empty.Tests/Empty.Tests.csproj
run test-guardian.sh coverage none-yet tests/Empty.Tests/Empty.Tests.csproj src/App/Invoice.cs
check "no report and no test: said, not a STOP" 0 '^TESTS: 0 passed, 0 failed \(no test in tests/Empty.Tests/Empty.Tests.csproj yet\)$' '^STOP'
check "…each file at 0/0" 0 '^src/App/Invoice.cs lines 0/0 \(no test yet: none of its lines runs\)$'
run test-guardian.sh net none-yet src/App/Invoice.cs:Total src/App/Invoice.cs:Invoice
check "its net: THIN, every line of the methods to run" 0 '^SAFETY NET: THIN \(no test runs these 2 methods yet, 0% < 80%\): before the fix'
check "…each method named" 0 '^NET: src/App/Invoice.cs:Total no test yet: none of its lines runs$'
run test-guardian.sh net none-yet --min 0 src/App/Invoice.cs:Total
check "…a minimum of 0 %: OK" 0 '^SAFETY NET: OK \(no test runs this method yet, 0%; minimum 0%\)$'
run test-guardian.sh net none-yet src/App/Nothing.cs:Total
check "…a file that does not exist: STOP" 1 '^STOP: no file src/App/Nothing.cs in this repository$'
run test-guardian.sh compare none-yet empty
check "…compared with a later measure: nothing lost" 0 '^COVERAGE: no file lost coverage$'
rm -f Both.sln
git reset -q --hard HEAD~1
cp "$work/green.kept" "$green"

# --if-changed (/push): the code that already passed is not built and tested again
run build-test.sh --if-changed
check "if-changed: the same code is not run again" 0 '^TESTS: OK \(not run again: same code'
truth "if-changed: no dotnet call" '[ -z "$calls" ]'
printf '// changed\n' >> src/App/Invoice.cs
run build-test.sh --if-changed
check "if-changed: a change runs it" 0 '^TESTS: OK$' 'not run again'
run build-test.sh --if-changed
check "if-changed: and remembers it" 0 'not run again'
run build-test.sh --if-changed --filter FullyQualifiedName~InvoiceTests
check "if-changed: other options run" 0 '^TESTS: OK$' 'not run again'
git checkout -q -- .

sed -i 's/InvoiceTests.Tax pass/InvoiceTests.Tax fail Assert.Equal() Failure: Expected 2, Actual 3/' tests/App.Tests/App.Tests.csproj
run build-test.sh
check "VSTest: a failure is named" 1 '^FAILED TESTS \(1\): App.Tests.InvoiceTests.Tax$'
check "VSTest: TESTS: FAILED" 1 '^TESTS: FAILED \(exit 1\)$'
run build-test.sh --if-changed
check "if-changed: a red run is never remembered" 1 '^TESTS: FAILED' 'not run again'

run test-guardian.sh red tests/App.Tests/App.Tests.csproj FullyQualifiedName~InvoiceTests.Tax
check "VSTest red: the failing test, twice" 0 '^RED: 1 tests fail on the current code'
check "VSTest red: the reason" 0 'App.Tests.InvoiceTests.Tax: Assert.Equal\(\) Failure'
run test-guardian.sh green tests/App.Tests/App.Tests.csproj FullyQualifiedName~InvoiceTests.Total
check "VSTest green" 0 '^GREEN: 1 tests pass, twice$'
run test-guardian.sh green tests/App.Tests/App.Tests.csproj FullyQualifiedName~InvoiceTests.Tax
check "VSTest green on a failing test: STOP" 1 '^STOP: 1 of these tests FAIL'
sed -i 's/OrderTests.Ship pass/OrderTests.Ship flaky/' tests/App.Tests/App.Tests.csproj
run test-guardian.sh green tests/App.Tests/App.Tests.csproj FullyQualifiedName~OrderTests
check "VSTest flaky" 1 '^FLAKY: '
git checkout -q -- .

run test-guardian.sh coverage before tests/App.Tests/App.Tests.csproj src/App/Invoice.cs
check "VSTest coverage of a file" 0 '^src/App/Invoice.cs lines 2/3 \(66%\) branches 0/0 uncovered 4$'
check "VSTest coverage: the counts" 0 '^TESTS: 3 passed, 0 failed$'
called "VSTest coverage: each test named in its log" '^dotnet test tests/App.Tests/App.Tests.csproj --collect:XPlat Code Coverage .*--logger console;verbosity=normal'
sed -i 's/InvoiceTests.Tax pass/InvoiceTests.Tax fail Assert.Equal() Failure: Expected 2, Actual 3/' tests/App.Tests/App.Tests.csproj
run test-guardian.sh coverage with-failure tests/App.Tests/App.Tests.csproj src/App/Invoice.cs
check "VSTest coverage: a test that fails, named" 0 '^FAILED TESTS \(1\): App.Tests.InvoiceTests.Tax$'
git checkout -q -- .

# ---------- verify: the checks of the phase after a fix, by script, for the pilot (VERIFY: OK, or the test-guardian) ----------
FAKE_DOTNET_COVER="$work/verify-cover.txt"
export FAKE_DOTNET_COVER
vcover() { printf '<!-- fake-cover: %s -->\n' "$1" > "$FAKE_DOTNET_COVER"; }
T=tests/App.Tests/App.Tests.csproj
vcover "src/App/Invoice.cs c=App.Invoice m=Total 3:1 m=Tax 4:0"
run test-guardian.sh coverage V9-before "$T" src/App/Invoice.cs
check "verify: the measure before the fix" 0 '^src/App/Invoice.cs lines 1/2 \(50%\)'
run test-guardian.sh net V9-before src/App/Invoice.cs:Total
check "verify: the net before, OK" 0 '^SAFETY NET: OK \(1/1 lines'
run test-guardian.sh seal V9 --problem src/App/Nothing.cs:Total
check "seal --problem: a file that does not exist" 1 '^STOP: no file src/App/Nothing.cs in this repository$'
run test-guardian.sh seal V9 --problem Total
check "seal --problem: <file>:<method> only" 1 '^STOP: bad method Total: '
run test-guardian.sh seal V9 --problem src/App/Invoice.cs:Total
check "seal --problem: an empty proof with the method of its problem" 0 '^SEALED: 0 test files'
run test-guardian.sh verify V9 FullyQualifiedName~InvoiceTests.Total
check "verify: all green, OK" 0 '^VERIFY: OK \(the sealed tests as sealed, green twice, no test failing that passed before, no file lost coverage, the net at its minimum, every line of the method of the problem run\): commit it$' '^STOP:'
check "verify: …the proof green twice" 0 '^GREEN: 1 tests pass, twice$'
check "verify: …the coverage after, on the files measured before" 0 '^src/App/Invoice.cs lines 1/2 \(50%\)'
check "verify: …the net of the seal" 0 '^NET: src/App/Invoice.cs:Total lines 1/1 \(100%\)'
check "verify: …the method of the problem" 0 '^PROBLEM: src/App/Invoice.cs:Total lines 1/1 \(100%\)'
truth "verify: the coverage after is kept as V9-after (the test-guardian reads it when it takes over)" '[ -f "$(git rev-parse --git-common-dir)/opencode-tickets/NOKEY.tests/coverage-V9-after.txt" ] || ls "$(git rev-parse --git-common-dir)"/opencode-tickets/*.tests/coverage-V9-after.txt >/dev/null 2>&1'
run test-guardian.sh verify V9
check "verify without a filter (an empty proof, a net without new tests): no green, the rest" 0 '^VERIFY: OK \(the sealed tests as sealed, no test failing' '^GREEN:'
# a test that passed before fails after the fix: a regression, or a behavior changed on purpose: the test-guardian judges
sed -i 's/InvoiceTests.Tax pass/InvoiceTests.Tax fail Assert.Equal() Failure: Expected 2, Actual 3/' "$T"
run test-guardian.sh verify V9 FullyQualifiedName~InvoiceTests.Total
check "verify: a test that passed before fails: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(a test that passed before fails: a behavior the step changes on purpose \(a test to update\), or a regression\)' '^STOP:'
check "verify: …the test named" 1 '^FAILED: tests that passed before the change fail now: App.Tests.InvoiceTests.Tax$'
git checkout -q -- .
# the tests of the proof fail: the test-guardian
run test-guardian.sh verify V9 FullyQualifiedName~InvoiceTests.Nothing
check "verify: the tests of the filter do not pass: the test-guardian, no STOP" 1 '^VERIFY: TEST-GUARDIAN \(the tests of the proof or of its net do not pass, twice the same way\)' '^STOP:'
check "verify: …its failure as FAILED" 1 '^FAILED: no test matched the filter FullyQualifiedName~InvoiceTests.Nothing$'
# a file that loses coverage
vcover "src/App/Invoice.cs c=App.Invoice m=Total 3:0 m=Tax 4:0"
run test-guardian.sh verify V9
check "verify: a lost coverage: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(a file lost coverage\)'
check "verify: …the file named" 1 '^FAILED: coverage lost after the change in src/App/Invoice.cs$'
# the net falls under its minimum, the file keeping its coverage
vcover "src/App/Invoice.cs c=App.Invoice m=Total 3:0 m=Tax 4:1"
run test-guardian.sh verify V9
check "verify: the net under its minimum, OK before: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(the net fell under its minimum with the change\)'
check "verify: …its NET line" 1 '^NET: src/App/Invoice.cs:Total lines 0/1 \(0%\)'
# a net already thin before the change (INSUFFISANT): which lines are left is the test-guardian's call
vcover "src/App/Invoice.cs c=App.Invoice m=Total 3:1 m=Tax 4:0"
run test-guardian.sh coverage V8-before "$T" src/App/Invoice.cs
run test-guardian.sh net V8-before src/App/Invoice.cs:Total src/App/Invoice.cs:Tax
check "verify: a net thin before" 0 '^SAFETY NET: THIN'
run test-guardian.sh seal V8
run test-guardian.sh verify V8
check "verify: thin before and after: the test-guardian decides (INSUFFISANT)" 1 '^VERIFY: TEST-GUARDIAN \(the net is under its minimum, as it was before the change \(INSUFFISANT\)'
# the method of the problem keeps a line that no test runs
run test-guardian.sh coverage V7-before "$T" src/App/Invoice.cs
run test-guardian.sh net V7-before src/App/Invoice.cs:Total
run test-guardian.sh seal V7 --problem src/App/Invoice.cs:Tax
run test-guardian.sh verify V7
check "verify: a line of the method of the problem not run: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(lines of the method of the problem that no test runs after the fix\)'
check "verify: …its line" 1 '^PROBLEM: src/App/Invoice.cs:Tax lines 0/1 \(0%\) branches 0/0 uncovered 4$'
# a method of the net that the change removed or renamed
vcover "src/App/Invoice.cs c=App.Invoice m=Tax 4:1 m=Grand 3:1"
run test-guardian.sh verify V7
check "verify: a method of the net gone from the report: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(a method of the net is not in the coverage after the change \(renamed or removed\)\)' '^STOP:'
vcover "src/App/Invoice.cs c=App.Invoice m=Total 3:1 m=Tax 4:0"
# a seal without its measures (made by an older pack, or without coverage before), and no seal at all
run test-guardian.sh seal V6
run test-guardian.sh verify V6
check "verify: a seal without the measures before: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(the seal of V6 did not keep the measures before the change'
run test-guardian.sh verify V5
check "verify: no seal: the test-guardian" 1 '^VERIFY: TEST-GUARDIAN \(no seal V5: '
# a new measure before a change starts a new proof: the net of an earlier attempt no longer counts
run test-guardian.sh coverage V4-net "$T" src/App/Invoice.cs
run test-guardian.sh net V4-net src/App/Invoice.cs:Tax
run test-guardian.sh coverage V4-before "$T" src/App/Invoice.cs
run test-guardian.sh net V4-before src/App/Invoice.cs:Total
run test-guardian.sh seal V4
run test-guardian.sh verify V4
check "verify: the net of the seal is that of this proof (V4-before), not of an earlier attempt (V4-net)" 0 '^NET: src/App/Invoice.cs:Total ' 'Invoice.cs:Tax'
# a test run that does not end in the time of the command: final, no VERIFY line, no turn of the test-guardian
out=$(FAKE_DOTNET_SLOW_TEST=5 TEST_SUITE_LIMIT=1s "$SHELL_UNDER_TEST" "$scripts/test-guardian.sh" verify V9 FullyQualifiedName~InvoiceTests.Total 2>&1)
status=$?
check "verify: a timeout is final, never handed to the test-guardian" 1 '^TESTS: TIMEOUT' '^VERIFY:'
# the machine cannot run the tests: the ENVIRONMENT PROBLEM line, at once, and no VERIFY line
mkdir -p "$work/nodotnet"
for f in /usr/local/bin/* /usr/bin/* /bin/*; do
  n=$(basename "$f")
  [ "$n" = dotnet ] || [ -e "$work/nodotnet/$n" ] || ln -s "$f" "$work/nodotnet/$n" 2>/dev/null
done
out=$(PATH="$work/nodotnet" "$SHELL_UNDER_TEST" "$scripts/test-guardian.sh" verify V9 2>&1)
status=$?
check "verify: dotnet missing: the ENVIRONMENT PROBLEM line, nothing else to judge" 1 '^ENVIRONMENT PROBLEM: dotnet is not on the PATH' '^VERIFY:'
unset FAKE_DOTNET_COVER

run fortify.sh prereq
check "VSTest prereq" 0 '^PREREQ: OK$'
check "VSTest prereq: coverlet" 0 'tests/App.Tests/App.Tests.csproj \(coverlet.collector\)'

sed -i 's#</Project>#  <!-- fake-build-error -->\n</Project>#' src/App/App.csproj
run build-test.sh
check "VSTest: a build error stops before the tests" 1 '^BUILD: FAILED \(exit 1, 1 distinct errors\) - tests not run$'
called "VSTest: no test run after a failed build" '^dotnet build' '^dotnet test'
git checkout -q -- .

# a lock held by a live process: the wait gives up, and leaves no file behind
mkdir -p .git/opencode-dotnet.lock && echo $$ > .git/opencode-dotnet.lock/pid
# shellcheck disable=SC2034 # read by truth
before=$(ls "$TMPDIR" | wc -l)
out=$(TEST_GUARDIAN_LOCK_WAIT=2 "$SHELL_UNDER_TEST" "$scripts/build-test.sh" 2>&1)
status=$?
check "lock: the wait gives up" 1 'BUILD: NOT RUN \(another build or test run'
truth "lock: no output file left behind" '[ "$(ls "$TMPDIR" | wc -l)" -eq "$before" ]'
truth "lock: the lock of the other run is kept" '[ -d .git/opencode-dotnet.lock ]'
rm -rf .git/opencode-dotnet.lock

# a test run that does not end in the time of a command: stopped by the script itself, which says what ran and why
# (the plugin would stop the command later and lose its whole output)
out=$(FAKE_DOTNET_SLOW_TEST=5 TEST_SUITE_LIMIT=1s "$SHELL_UNDER_TEST" "$scripts/build-test.sh" 2>&1)
status=$?
check "timeout: the suite stopped by the script, said" 124 '^TESTS: TIMEOUT \(the tests ran until the time of this command ran out' '^TESTS: (OK|FAILED)'
check "timeout: …what to do, never a limit raised" 124 '^NOTE: a test run this long cannot prove a change on this machine: AGENTS.md « Build & test », « Tests locaux »'
truth "timeout: no test host left running" '! pgrep -f "fake-dotnet|dotnet test" >/dev/null 2>&1 || ! pgrep -P $$ >/dev/null 2>&1'
# the wait for the lock counts: a command that already used its time gets what is left, not a whole run
out=$(FAKE_DOTNET_SLOW_TEST=5 OPENCODE_COMMAND_START=$(($(date +%s) - 2518)) "$SHELL_UNDER_TEST" "$scripts/build-test.sh" 2>&1)
status=$?
check "timeout: the time already spent (the wait for the lock) counts" 124 '^TESTS: TIMEOUT \(the tests ran until the time of this command ran out, 42 min with the build and the wait'
out=$(FAKE_DOTNET_SLOW_TEST=5 TEST_SUITE_LIMIT=1s "$SHELL_UNDER_TEST" "$scripts/test-guardian.sh" green tests/App.Tests/App.Tests.csproj FullyQualifiedName~InvoiceTests.Total 2>&1)
status=$?
check "timeout: the test-guardian's proof, final like an environment problem, never a STOP" 124 '^TESTS: TIMEOUT \(the tests of tests/App.Tests/App.Tests.csproj ran until the time' '^STOP:'
out=$(FAKE_DOTNET_SLOW_TEST=5 TEST_SUITE_LIMIT=1s "$SHELL_UNDER_TEST" "$scripts/build-test.sh" tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceTests 2>&1)
status=$?
check "timeout: a filtered run too" 124 '^TESTS: TIMEOUT'

# ---------- a Microsoft.Testing.Platform repository (.slnx): xUnit v3, MSTest.Sdk, a VSTest one, TUnit ----------
mkdir -p "$work/mtp"
cd "$work/mtp" || exit 1
git init -q
project src/Core/Core.csproj Microsoft.NET.Sdk
printf 'namespace Core;\npublic static class Price {\n  public static int Round(int x) => x;\n}\n' > src/Core/Price.cs
project tests/Core.Tests/Core.Tests.csproj Microsoft.NET.Sdk \
  '<PropertyGroup>' '  <OutputType>Exe</OutputType>' '  <UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>' '</PropertyGroup>' \
  '<ItemGroup>' '  <PackageReference Include="xunit.v3" Version="3.1.0" />' \
  '  <PackageReference Include="Microsoft.Testing.Extensions.CodeCoverage" Version="18.6.2" />' '</ItemGroup>' \
  '<!-- fake-test: Core.Tests.PriceTests.Round pass -->' '<!-- fake-test: Core.Tests.PriceTests.Floor pass -->' \
  '<!-- fake-test: Core.Tests.CartTests.Add pass -->' '<!-- fake-cover: src/Core/Price.cs 2:1 3:0 -->'
project tests/Core.MsTests/Core.MsTests.csproj MSTest.Sdk/3.8.0 '<!-- fake-test: Core.MsTests.RuleTests.Apply pass -->'
project tests/Legacy.Tests/Legacy.Tests.csproj Microsoft.NET.Sdk \
  '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '  <PackageReference Include="coverlet.collector" Version="6.0.2" />' '</ItemGroup>' \
  '<!-- fake-test: Legacy.Tests.OldTests.Works pass -->'
cat > Mtp.slnx <<'EOF'
<Solution>
  <Project Path="src/Core/Core.csproj" />
  <Project Path="tests/Core.Tests/Core.Tests.csproj" />
  <Project Path="tests/Core.MsTests/Core.MsTests.csproj" />
  <Project Path="tests/Legacy.Tests/Legacy.Tests.csproj" />
</Solution>
EOF
project tests/Ui.Tests/Ui.Tests.csproj Microsoft.NET.Sdk \
  '<ItemGroup>' '  <PackageReference Include="TUnit" Version="0.57.24" />' '</ItemGroup>' \
  '<!-- fake-test: Ui.Tests.LoginTests.Accepts pass -->' '<!-- fake-test: Ui.Tests.LoginTests.Refuses pass -->' \
  '<!-- fake-test: Ui.Tests.CookieTests.LoginBanner pass -->'
echo 'APPSEC_PROJECT_NAME=core' > appsec-ci.env
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init

run test-platform.sh kind tests/Core.Tests/Core.Tests.csproj
check "kind: xUnit v3 on MTP, CodeCoverage" 0 '^mtp xunit3 codecoverage$'
run test-platform.sh kind tests/Core.MsTests/Core.MsTests.csproj
check "kind: MSTest.Sdk, its coverage" 0 '^mtp mstest codecoverage$'
run test-platform.sh kind tests/Ui.Tests/Ui.Tests.csproj
check "kind: TUnit" 0 '^mtp tunit none$'
run test-platform.sh kind tests/Legacy.Tests/Legacy.Tests.csproj
check "kind: VSTest next to them" 0 '^vstest xunit2 none$'
run test-platform.sh scope Mtp.slnx
check "scope: the solution, MTP and VSTest" 0 "^mtp	tests/Core.Tests/Core.Tests.csproj$" 'src/Core|Ui.Tests'
check "scope: the VSTest project" 0 "^vstest	tests/Legacy.Tests/Legacy.Tests.csproj$"

run build-test.sh Mtp.slnx
check "mixed solution: every test, summed" 0 '^TESTS: OK \(5 tests\)$'
called "mixed: the VSTest project with dotnet test" '^dotnet test tests/Legacy.Tests/Legacy.Tests.csproj --no-build'
called "mixed: xUnit v3 as its application, the suite limit: the time left to the command, 25 minutes at most" '^dotnet exec .*/Core.Tests.dll --timeout 1(4[0-9][0-9]|500)s$' '^dotnet run'
called "mixed: MSTest.Sdk as its application" '^dotnet exec .*/Core.MsTests.dll --timeout 1(4[0-9][0-9]|500)s$'
called "mixed: dotnet test never runs an MTP project" '^dotnet test' '^dotnet test [^ ]*(Core.Tests|Core.MsTests)'

run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter FullyQualifiedName~PriceTests
check "xUnit v3: a filter" 0 '^TESTS: OK \(2 tests\)$'
called "xUnit v3: --filter-method with wildcards, the hang limit" '^dotnet exec .*/Core.Tests.dll --filter-method \*PriceTests\* --timeout 5m$'
run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter "FullyQualifiedName~PriceTests.Round|FullyQualifiedName~CartTests"
check "xUnit v3: two names" 0 '^TESTS: OK \(2 tests\)$'
called "xUnit v3: one --filter-method, two values" '--filter-method \*PriceTests.Round\* \*CartTests\* --timeout'
run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter "FullyQualifiedName~PriceTests&Category=Unit"
check "xUnit v3: a filter it cannot take" 1 '^TESTS: NOT RUN \(the filter "FullyQualifiedName~PriceTests&Category=Unit" cannot be given to xunit3'
run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter FullyQualifiedName~Nothing
check "xUnit v3: no test matches" 0 '^TESTS: NONE RUN'
run build-test.sh tests/Core.MsTests/Core.MsTests.csproj --filter FullyQualifiedName~RuleTests
check "MSTest: the VSTest filter as is" 0 '^TESTS: OK \(1 test\)$'
called "MSTest: --filter" '^dotnet exec .*/Core.MsTests.dll --filter FullyQualifiedName~RuleTests --timeout 5m$'

run build-test.sh tests/Ui.Tests/Ui.Tests.csproj --filter FullyQualifiedName~LoginTests
check "TUnit: a class" 0 '^TESTS: OK \(2 tests\)$'
check "TUnit: the tree filter of a class" 0 '^\(TUnit tree filter: /\*/\*/\*LoginTests\*/\*\)$'
run build-test.sh tests/Ui.Tests/Ui.Tests.csproj --filter FullyQualifiedName~Banner
check "TUnit: a method, after the class" 0 '^TESTS: OK \(1 test\)$'
called "TUnit: the class first, then the method" '--treenode-filter /\*/\*/\*/\*Banner\*'
run build-test.sh tests/Ui.Tests/Ui.Tests.csproj --filter FullyQualifiedName~LoginTests.Refuses
check "TUnit: a class and its method" 0 '^TESTS: OK \(1 test\)$'
run build-test.sh tests/Ui.Tests/Ui.Tests.csproj --filter "FullyQualifiedName~LoginTests|FullyQualifiedName~CookieTests"
check "TUnit: two classes" 0 '^TESTS: OK \(3 tests\)$'

sed -i 's/PriceTests.Floor pass/PriceTests.Floor fail Assert.Equal() Failure: Expected 1, Actual 2/' tests/Core.Tests/Core.Tests.csproj
run build-test.sh tests/Core.Tests/Core.Tests.csproj
check "MTP: a failure is named" 1 '^FAILED TESTS \(1\): Core.Tests.PriceTests.Floor$'
check "MTP: TESTS: FAILED" 1 '^TESTS: FAILED \(exit 1\)$'
sed -i 's#</Project>#  <!-- fake-ansi -->\n</Project>#' tests/Core.Tests/Core.Tests.csproj
run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter FullyQualifiedName~PriceTests
check "MTP: colors taken out, the failure still named" 1 '^FAILED TESTS \(1\): Core.Tests.PriceTests.Floor$'
truth "MTP: no escape character in the output" '! printf "%s" "$out" | grep -q "$(printf "\033")"'
git checkout -q -- tests/Core.Tests/Core.Tests.csproj
sed -i 's/PriceTests.Floor pass/PriceTests.Floor fail Assert.Equal() Failure: Expected 1, Actual 2/' tests/Core.Tests/Core.Tests.csproj
run test-guardian.sh red tests/Core.Tests/Core.Tests.csproj FullyQualifiedName~PriceTests.Floor
check "MTP red: twice the same" 0 '^RED: 1 tests fail on the current code'
check "MTP red: the reason" 0 'Core.Tests.PriceTests.Floor: Assert.Equal\(\) Failure: Expected 1, Actual 2'
called "MTP red: the second run without a build" '^dotnet exec .*--filter-method \*PriceTests.Floor\*' '^dotnet test'
truth "MTP red: one build for two runs" '[ "$(printf "%s\n" "$calls" | grep -c "^dotnet build")" -eq 1 ]'
run test-guardian.sh red tests/Core.Tests/Core.Tests.csproj FullyQualifiedName~PriceTests.Round
check "MTP red on a passing test: STOP" 1 '^STOP: 1 of these tests PASS on the current code'
run test-guardian.sh green tests/Core.Tests/Core.Tests.csproj FullyQualifiedName~PriceTests.Round
check "MTP green" 0 '^GREEN: 1 tests pass, twice$'
run test-guardian.sh green tests/Core.Tests/Core.Tests.csproj FullyQualifiedName~Nothing
check "MTP green, no test matches: STOP" 1 '^STOP: no test matched the filter FullyQualifiedName~Nothing$'
sed -i 's/CartTests.Add pass/CartTests.Add flaky/' tests/Core.Tests/Core.Tests.csproj
run test-guardian.sh green tests/Core.Tests/Core.Tests.csproj FullyQualifiedName~CartTests
check "MTP flaky" 1 '^FLAKY: '
git checkout -q -- .
sed -i 's/CartTests.Add pass/CartTests.Add hang/' tests/Core.Tests/Core.Tests.csproj
run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter FullyQualifiedName~CartTests
check "MTP hang: named and stopped" 1 '^HANG: the tests of tests/Core.Tests/Core.Tests.csproj ran more than 5m'
run test-guardian.sh green tests/Core.Tests/Core.Tests.csproj FullyQualifiedName~CartTests
check "MTP hang: the test-guardian stops" 1 '^STOP: the tests of tests/Core.Tests/Core.Tests.csproj ran more than 5m'
# a whole run of the application longer than the time left: a TIMEOUT of the run, never a test to fix
out=$(TEST_SUITE_LIMIT=7m "$SHELL_UNDER_TEST" "$scripts/test-platform.sh" run tests/Core.Tests/Core.Tests.csproj 2>&1)
status=$?
check "MTP: a whole run past its time is a TIMEOUT, not a hanging test" 1 '^TIMEOUT: the tests of tests/Core.Tests/Core.Tests.csproj ran more than 7m, the time left to this command' '^HANG:'
run build-test.sh tests/Core.Tests/Core.Tests.csproj
check "MTP: build-test.sh says TESTS: TIMEOUT" 124 '^TESTS: TIMEOUT' '^HANG:'
out=$(TEST_SUITE_LIMIT=2m "$SHELL_UNDER_TEST" "$scripts/test-platform.sh" run tests/Core.Tests/Core.Tests.csproj --filter FullyQualifiedName~CartTests 2>&1)
status=$?
check "MTP: a filtered run with less time left than the hang limit: a TIMEOUT too" 1 '^TIMEOUT: the tests of tests/Core.Tests/Core.Tests.csproj ran more than 2m'
git checkout -q -- .

sed -i 's#</Project>#  <!-- fake-mtp-old -->\n</Project>#' tests/Core.MsTests/Core.MsTests.csproj
run build-test.sh tests/Core.MsTests/Core.MsTests.csproj
check "MTP older than 1.5: run again without --timeout" 0 '^NOTE: the test platform of tests/Core.MsTests/Core.MsTests.csproj has no --timeout'
check "MTP older than 1.5: the tests ran" 0 '^TESTS: OK \(1 test\)$'
git checkout -q -- .

run test-guardian.sh coverage before tests/Core.Tests/Core.Tests.csproj src/Core/Price.cs
check "MTP coverage of a file" 0 '^src/Core/Price.cs lines 1/2 \(50%\) branches 0/0 uncovered 3$'
check "MTP coverage: the counts" 0 '^TESTS: 3 passed, 0 failed$'
check "MTP coverage: no failed test, no line" 0 '^TESTS: 3 passed' '^FAILED TESTS'
called "MTP coverage: the CodeCoverage extension, Cobertura" '--coverage --coverage-output-format cobertura --coverage-output /.*/Core.Tests/coverage.cobertura.xml'

git switch -q -c feature/CORE-7-round
printf 'namespace Core;\npublic static class Price {\n  public static int Round(int x) => x + 0;\n  public static int Floor(int x) => x - 0;\n}\n' > src/Core/Price.cs
sed -i 's#fake-cover: src/Core/Price.cs 2:1 3:0#fake-cover: src/Core/Price.cs 2:1 3:1 4:0#' tests/Core.Tests/Core.Tests.csproj
git commit -q -am "round"
run test-guardian.sh changes develop Mtp.slnx
check "MTP changes: the suite" 0 '^TESTS: OK \(5 tests\)$'
check "MTP changes: the changed lines" 0 '^CHANGED: src/Core/Price.cs 1/2 changed lines covered; not covered: 4$'
check "MTP changes: the total" 0 '^COVERAGE OF THE CHANGES: 1/2 changed lines covered \(50%\) in 1 files; 1 not covered$'
git switch -q develop

run outil.sh setup
check "/outil setup: the runner of each test project" 0 '^  mtp xunit3 codecoverage tests/Core.Tests/Core.Tests.csproj$'
check "/outil setup: TUnit outside the solution" 0 '^  mtp tunit none tests/Ui.Tests/Ui.Tests.csproj$'
check "/outil setup: VSTest" 0 '^  vstest xunit2 none tests/Legacy.Tests/Legacy.Tests.csproj$'
check "/outil setup: no global.json opt-in" 0 "^  global.json : pas d'option Microsoft.Testing.Platform"
run fortify.sh prereq
check "MTP prereq: coverage extensions found" 0 '^PREREQ: COVERLET MISSING in: tests/Ui.Tests/Ui.Tests.csproj '
check "MTP prereq: xUnit v3" 0 'tests/Core.Tests/Core.Tests.csproj \(Microsoft.Testing.Platform, coverage: codecoverage\)'
run test-guardian.sh coverage ui tests/Ui.Tests/Ui.Tests.csproj src/Core/Price.cs
check "MTP coverage without an extension: STOP and why" 1 '^COVERAGE: NOT MEASURED for tests/Ui.Tests/Ui.Tests.csproj'
run test-guardian.sh setup xunit src/Core/Price.cs
check "MTP setup: the extension where it lacks" 0 '^SETUP: Microsoft.Testing.Extensions.CodeCoverage 18.6.2 added to tests/Ui.Tests/Ui.Tests.csproj; build OK$'
truth "MTP setup: the reference in the project" 'grep -q "<PackageReference Include=\"Microsoft.Testing.Extensions.CodeCoverage\" Version=\"18.6.2\" />" tests/Ui.Tests/Ui.Tests.csproj'
truth "MTP setup: the other projects unchanged" '[ "$(git status --porcelain | wc -l)" -eq 1 ]'
run fortify.sh prereq
check "MTP prereq after setup" 0 '^PREREQ: OK$'
git checkout -q -- .

# a branch without a Jira key (/push, /tests, /fix without a ticket): its own measures folder; its work put aside
git switch -q -c poc/essai-cache
run test-guardian.sh folder
check "no key: a measures folder of its own" 0 'FOLDER: .*/opencode-tickets/poc-essai-cache.tests$'
printf 'class Extra { }\n' > src/Core/Extra.cs
run fortify.sh discard F1
check "no key: a failed proof put aside" 0 '^DISCARDED: 1 files put aside in git stash « fortify poc/essai-cache F1'
git switch -q develop
git branch -q -D poc/essai-cache
printf 'class Extra { }\n' > src/Core/Extra.cs
run fortify.sh discard F1
check "develop: nothing put aside" 1 'STOP: not on a branch of its own \(develop\)'
rm -f src/Core/Extra.cs
git switch -q -c feature/CORE-9-x
run test-guardian.sh folder
check "a Jira key: the folder of the key" 0 'FOLDER: .*/opencode-tickets/CORE-9.tests$'
git switch -q develop
git branch -q -D feature/CORE-9-x
project tests/Ui.Specs/Ui.Specs.csproj Microsoft.NET.Sdk '<ItemGroup>' '  <PackageReference Include="TUnit" Version="0.57.24" />' '</ItemGroup>'
git add -A && git commit -q -m specs
run fortify.sh prereq --tests
check "TUnit without Tests in its name: a test project" 0 'tests/Ui.Specs/Ui.Specs.csproj'

# a project that the scripts take for VSTest, and that dotnet test of the .NET 10 SDK refuses: run as its application
project tests/Hidden.Tests/Hidden.Tests.csproj Microsoft.NET.Sdk \
  '<ItemGroup>' '  <PackageReference Include="xunit.v3.mtp-v2" Version="3.1.0" />' '</ItemGroup>' \
  '<!-- fake-mtp-v2 -->' '<!-- fake-test: Hidden.Tests.SecretTests.Kept pass -->'
git add -A && git commit -q -m hidden
run build-test.sh tests/Hidden.Tests/Hidden.Tests.csproj
check "refused by dotnet test: run as its application" 0 '^NOTE: 1 test project\(s\) on Microsoft.Testing.Platform, refused by dotnet test'
check "refused by dotnet test: the tests ran" 0 '^TESTS: OK \(1 test\)$'
sed -i 's#  <Project Path="tests/Legacy.Tests/Legacy.Tests.csproj" />#&\n  <Project Path="tests/Hidden.Tests/Hidden.Tests.csproj" />#' Mtp.slnx
run build-test.sh Mtp.slnx
check "refused inside a mixed solution: its application" 0 '^NOTE: tests/Hidden.Tests/Hidden.Tests.csproj runs on Microsoft.Testing.Platform'
check "refused inside a mixed solution: every test" 0 '^TESTS: OK \(6 tests\)$'
git checkout -q -- .

# a new test project, the template of a recent SDK being MSTest.Sdk: its coverage is the extension of the SDK
mkdir -p "$work/none"
cd "$work/none" || exit 1
git init -q
project src/Api/Api.csproj Microsoft.NET.Sdk
printf 'namespace Api;\npublic class Orders { }\n' > src/Api/Orders.cs
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
run fortify.sh prereq --tests
check "prereq for /tests: no Fortify application needed" 0 '^PREREQ: NO TEST PROJECT' 'STOP'
run fortify.sh prereq
check "prereq for /fortify: the Fortify application is needed" 1 '^STOP: no APPSEC_PROJECT_NAME line'
FAKE_TEMPLATE=mtp
export FAKE_TEMPLATE
run test-guardian.sh setup mstest src/Api/Orders.cs
check "setup on an MSTest.Sdk template" 0 '^SETUP: tests/Api.UnitTests/Api.UnitTests.csproj created \(mstest, net10.0\)'
truth "setup on an MSTest.Sdk template: no coverlet" '! grep -q coverlet tests/Api.UnitTests/Api.UnitTests.csproj'
git clean -qfdx && git checkout -q -- .
unset FAKE_TEMPLATE
run test-guardian.sh setup xunit src/Api/Orders.cs
check "setup on a VSTest template" 0 '^SETUP: tests/Api.UnitTests/Api.UnitTests.csproj created \(xunit, net10.0\)'
truth "setup on a VSTest template: coverlet" 'grep -q "coverlet.collector" tests/Api.UnitTests/Api.UnitTests.csproj'
truth "setup: the example test removed" '[ ! -f tests/Api.UnitTests/UnitTest1.cs ]'

# ---------- package-refs.sh --doc: the XML documentation of a public package (the Blazorise DataGrid case) ----------
NUGET_PACKAGES="$work/nuget"
export NUGET_PACKAGES
for v in 1.5.0 1.6.2; do
  for f in net6.0 net8.0 netstandard2.0; do
    mkdir -p "$NUGET_PACKAGES/blazorise.datagrid/$v/lib/$f"
    echo '<doc><members><member name="P:Blazorise.DataGrid.DataGrid`1.Localizers"/></members></doc>' > "$NUGET_PACKAGES/blazorise.datagrid/$v/lib/$f/Blazorise.DataGrid.xml"
  done
  : > "$NUGET_PACKAGES/blazorise.datagrid/$v/.signature.p7s"
done
mkdir -p "$NUGET_PACKAGES/blazorise/1.6.2/lib/net8.0" "$NUGET_PACKAGES/blazorise/1.7.0-preview1/lib/net8.0"
: > "$NUGET_PACKAGES/blazorise/1.6.2/lib/net8.0/Blazorise.xml"
: > "$NUGET_PACKAGES/blazorise/1.7.0-preview1/lib/net8.0/Blazorise.xml"
mkdir -p "$NUGET_PACKAGES/nodoc.lib/2.0.0/lib/net8.0"
mkdir -p "$work/web"
cd "$work/web" || exit 1
git init -q
project src/Web/Web.csproj Microsoft.NET.Sdk.Razor '<ItemGroup>' '  <PackageReference Include="Blazorise.DataGrid" Version="1.6.2" />' \
  '  <PackageReference Include="NoDoc.Lib" Version="2.0.0" />' '</ItemGroup>'
sed -i 's#net10.0#net8.0#' src/Web/Web.csproj
git add -A && git commit -q -m init
run package-refs.sh --doc Blazorise.DataGrid
check "--doc: the version and the framework of the project" 0 "^- $NUGET_PACKAGES/blazorise.datagrid/1.6.2/lib/net8.0/Blazorise.DataGrid.xml\$"
check "--doc: how it was chosen" 0 '^XML documentation of Blazorise.DataGrid 1.6.2 \(lib/net8.0; the version referenced by src/Web/Web.csproj\)'
run package-refs.sh --doc blazorise
check "--doc: a dependency, its highest stable version" 0 "^- $NUGET_PACKAGES/blazorise/1.6.2/lib/net8.0/Blazorise.xml\$"
mkdir -p "$NUGET_PACKAGES/blazorise/1.5.0/lib/net8.0" src/Web/obj
: > "$NUGET_PACKAGES/blazorise/1.5.0/lib/net8.0/Blazorise.xml"
printf '{\n  "targets": {\n    "net8.0": {\n      "Blazorise/1.5.0": {\n        "type": "package"\n      }\n    }\n  },\n  "libraries": {\n    "Blazorise/1.5.0": {\n      "sha512": "x"\n    }\n  }\n}\n' > src/Web/obj/project.assets.json
run package-refs.sh --doc Blazorise
check "--doc: a dependency, the version the restore resolved" 0 "^- $NUGET_PACKAGES/blazorise/1.5.0/lib/net8.0/Blazorise.xml\$"
rm -rf src/Web/obj
run package-refs.sh --doc NoDoc.Lib
check "--doc: a package without documentation" 0 '^XML documentation of NoDoc.Lib 2.0.0: none .*never probe the assembly'
run package-refs.sh --doc Missing.Package
check "--doc: a package never restored" 0 '^XML documentation of Missing.Package: not in the package cache'
run package-refs.sh
check "the list says how to get the documentation of a public package" 0 '^nuget.org packages \(the XML documentation of one: package-refs.sh --doc <id>\):$'
# detect-project-type.sh: the components of Blazorise, its version and its skill
mkdir -p src/Web/Pages
printf '<DataGrid TItem="Order" Data="@orders" ShowPager="true" />\n' > src/Web/Pages/Orders.razor
git add -A && git commit -q -m page
run detect-project-type.sh
check "detect: Blazorise, its version and the skill that knows it" 0 '^- Blazor components: 1 \.razor files, 0 with a \.razor\.cs code-behind; component library: Blazorise; Blazorise 1\.6\.2: the skill blazorise \(the language of the DataGrid and of its pager'
sed -i 's#Include="Blazorise.DataGrid" Version="1.6.2"#Include="Blazorise.DataGrid" Version="2.2.2"#' src/Web/Web.csproj
printf '<Project>\n  <ItemGroup>\n    <PackageVersion Include="Blazorise.Bootstrap5" Version="2.10.1" />\n  </ItemGroup>\n</Project>\n' > Directory.Packages.props
git add -A && git commit -q -m upgrade
run detect-project-type.sh
check "detect: the highest version of Blazorise, central versions included" 0 'Blazorise 2\.10\.1: the skill blazorise'
check "detect: no EF Core line without EF Core" 0 'Blazorise 2' '^- EF Core'
# Entity Framework Core: its version, its providers and the skill that knows it, central versions included
printf '<Project>\n  <ItemGroup>\n    <PackageVersion Include="Blazorise.Bootstrap5" Version="2.10.1" />\n    <PackageVersion Include="Microsoft.EntityFrameworkCore.SqlServer" Version="8.0.11" />\n    <PackageVersion Include="Microsoft.EntityFrameworkCore.Design" Version="8.0.11" />\n  </ItemGroup>\n</Project>\n' > Directory.Packages.props
sed -i 's#</Project>#  <ItemGroup>\n    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" />\n    <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="8.0.2" />\n  </ItemGroup>\n</Project>#' src/Web/Web.csproj
git add -A && git commit -q -m ef
run detect-project-type.sh
check "detect: EF Core, its highest version, its providers, the skill efcore" 0 '^- EF Core 8\.0\.11 \(SqlServer, Sqlite\): the skill efcore'
git rm -q Directory.Packages.props && git checkout -q HEAD~1 -- src/Web/Web.csproj && git commit -q -m central

# ---------- the machine, not the code (dotnet-problem.sh): .NET 8, global.json, the runtimes of the tests ----------
mkdir -p "$work/env"
cd "$work/env" || exit 1
git init -q
mkdir -p src/Api src/Contracts tests/Api.Tests
printf '<Project Sdk="Microsoft.NET.Sdk.Web">\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/Api/Api.csproj
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>netstandard2.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/Contracts/Contracts.csproj
cat > tests/Api.Tests/Api.Tests.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="8.0.11" />
  </ItemGroup>
  <!-- fake-test: Api.Tests.HealthTests.Get_ReturnsOk pass -->
</Project>
EOF
cat > Api.sln <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api", "src\Api\Api.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Contracts", "src\Contracts\Contracts.csproj", "{33333333-3333-3333-3333-333333333333}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api.Tests", "tests\Api.Tests\Api.Tests.csproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
EOF
printf '{\n  "sdk": { "version": "8.0.400" }\n}\n' > global.json
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
# only the .NET 10 SDK on this machine: global.json asks for 8.0.400 (rollForward patch by default)
run build-test.sh
check "the SDK of global.json is missing: an environment problem" any 'ENVIRONMENT PROBLEM: global.json asks for the .NET SDK 8.0.400, which is not installed on this machine \(installed: 10.0.100\)'
check "and global.json is never changed to make it build" any 'Never change global.json or its rollForward yourself'
truth "the SDK of global.json is missing: the run fails" '[ "$status" -ne 0 ]'
called "and no test runs" '^dotnet build' '^dotnet test'
run dotnet-targets.sh
check "dotnet-targets: the SDK global.json asks for, not installed" 0 '^\.NET SDK: global.json asks for 8\.0\.400 \(rollForward patch\): NOT INSTALLED on this machine \(installed: 10\.0\.100\)'
check "dotnet-targets: the target frameworks and their projects" 0 '^Target frameworks: net8\.0 \(src/Api, tests/Api\.Tests\), netstandard2\.0 \(src/Contracts\)$'
check "dotnet-targets: the C# version of each target framework" 0 '^C#: 12 for net8\.0, 7\.3 for netstandard2\.0 \(the defaults: no LangVersion\)'
check "dotnet-targets: the end of support of .NET 8" 0 '^Support: net8\.0 \((ends|ended) on 2026-11-10\)'
# the .NET 8 SDK installed, not its runtimes: the build passes, the tests cannot start
FAKE_DOTNET_SDKS="8.0.404 10.0.100"
export FAKE_DOTNET_SDKS
run build-test.sh
check "the runtime of the tests is missing: an environment problem" any 'ENVIRONMENT PROBLEM: the tests run on Microsoft\.NETCore\.App 8\.0\.0 \(a net8\.0 project\), which is not installed on this machine \(found: 10\.0\.0\)'
check "and the target framework is never changed to make them run" any 'Never change the target framework of a project, never roll it forward'
run dotnet-targets.sh
check "dotnet-targets: the SDK fits" 0 '^\.NET SDK: global.json asks for 8\.0\.400 \(rollForward patch\): 8\.0\.404 is installed'
check "dotnet-targets: the runtimes of the tests, not installed" 0 '^Test runtimes: NOT INSTALLED on this machine: Microsoft\.AspNetCore\.App 8\.0 for net8\.0, Microsoft\.NETCore\.App 8\.0 for net8\.0'
# and its runtimes
FAKE_DOTNET_RUNTIMES="Microsoft.AspNetCore.App 8.0.11
Microsoft.NETCore.App 8.0.11
Microsoft.AspNetCore.App 10.0.0
Microsoft.NETCore.App 10.0.0"
export FAKE_DOTNET_RUNTIMES
run build-test.sh
check ".NET 8 with its SDK and runtimes: build and tests" 0 '^TESTS: OK$' 'ENVIRONMENT PROBLEM'
run dotnet-targets.sh
check "dotnet-targets: the runtimes of the tests, installed" 0 '^Test runtimes: installed \(net8\.0: Microsoft\.AspNetCore\.App, Microsoft\.NETCore\.App\)'
unset FAKE_DOTNET_SDKS FAKE_DOTNET_RUNTIMES
# the other messages, read from the output of dotnet
mkdir -p "$work/logs"
printf '/src/Api/Api.csproj : error NETSDK1045: The current .NET SDK does not support targeting .NET 11.0.  Either target .NET 10.0 or lower, or use a version of the .NET SDK that supports .NET 11.0.\n' > "$work/logs/1045"
printf 'error NETSDK1147: To build this project, the following workloads must be installed: wasm-tools\n' > "$work/logs/1147"
printf '/x/src/Desktop/Desktop.csproj : error NETSDK1100: To build a project targeting Windows on this operating system, set the EnableWindowsTargeting property to true. [/x/src/Desktop/Desktop.csproj]\n' > "$work/logs/1100"
printf '  /x/src/Api/Api.csproj : error NU1301: Unable to load the service index for source https://artifactory.example.com/api/nuget/v3/nuget.\n' > "$work/logs/1301"
printf 'src/Api/Program.cs(12,5): error CS0103: The name '"'"'Foo'"'"' does not exist in the current context\n' > "$work/logs/cs"
printf '/x/src/Legacy/Legacy.csproj : error MSB3644: The reference assemblies for .NETFramework,Version=v4.8 were not found. To resolve this, install the Developer Pack.\n' > "$work/logs/3644"
printf '  Failed Api.Tests.OrderRepositoryTests.Save [1 ms]\n  Error Message:\n   DotNet.Testcontainers.Builders.DockerUnavailableException : Docker is either not running or misconfigured. Please ensure that Docker is running and that the endpoint is properly configured.\n' > "$work/logs/docker"
printf '  Error Message:\n   System.PlatformNotSupportedException : LocalDB is not supported on this platform.\n' > "$work/logs/localdb"
for c in "1045:a project targets \.NET 11\.0 newer than the \.NET SDK of this machine \(10\.0\.100\).*Never lower the target framework" \
  "1147:needs the \.NET workload wasm-tools" "1100:targets Windows .*solution filter \(\.slnf\)" \
  "1301:the package feed \(Artifactory\) refused access or cannot be reached" "3644:a \.NET Framework project \(\.NETFramework,Version=v4\.8\) needs the reference assemblies" \
  "docker:some tests need Docker \(Testcontainers\).*Never change or skip these tests" "localdb:some tests need SQL Server LocalDB"; do
  out=$(cd "$work/logs" && "$SHELL_UNDER_TEST" "$scripts/dotnet-problem.sh" "$work/logs/${c%%:*}" 2>&1)
  status=$?
  check "dotnet-problem: ${c%%:*}" 0 "ENVIRONMENT PROBLEM: .*${c#*:}"
done
out=$("$SHELL_UNDER_TEST" "$scripts/dotnet-problem.sh" "$work/logs/cs" 2>&1)
status=$?
check "dotnet-problem: a compilation error is the code, not the machine" 1 '^$'

# ---------- a library: its package, its public API, its tests ----------
mkdir -p "$work/lib"
cd "$work/lib" || exit 1
git init -q
mkdir -p src/Lib/Dtos src/Api/Controllers tests/Lib.Tests
cat > src/Lib/Lib.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net8.0</TargetFrameworks>
    <IsPackable>true</IsPackable>
    <PackageId>Company.Lib</PackageId>
    <Version>2.3.0</Version>
    <EnablePackageValidation>true</EnablePackageValidation>
    <PackageValidationBaselineVersion>2.2.0</PackageValidationBaselineVersion>
  </PropertyGroup>
</Project>
EOF
cat > src/Lib/Client.cs <<'EOF'
namespace Lib;
public class Client
{
    public Client(string host) { }
    public void Connect(string host) { }
    public void Disconnect() { }
    internal void Hidden() { }
}
EOF
cat > src/Lib/Dtos/InvoiceDto.cs <<'EOF'
namespace Lib.Dtos;
public class InvoiceDto
{
    public string Number { get; set; } = "";
    public decimal Total { get; set; }
}
EOF
cat > src/Api/Controllers/InvoicesController.cs <<'EOF'
[ApiController]
[Route("api/invoices")]
public class InvoicesController : ControllerBase
{
    [HttpGet("{id:int}")]
    public IActionResult Get(int id) => Ok();
}
EOF
project tests/Lib.Tests/Lib.Tests.csproj Microsoft.NET.Sdk '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '</ItemGroup>' '<!-- fake-test: Lib.Tests.ClientTests.Connect_Opens pass -->'
cat > tests/Lib.Tests/ClientTests.cs <<'EOF'
namespace Lib.Tests;
public class ClientTests
{
    [Fact]
    public void Connect_Opens() => Assert.True(new Client("h").IsOpen);
}
EOF
cat > Lib.sln <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Lib", "src\Lib\Lib.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Lib.Tests", "tests\Lib.Tests\Lib.Tests.csproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
EOF
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
git checkout -q -b feature/ABC-7-retry
run detect-project-type.sh
check "detect-project-type: the library, its version and its package validation" 0 '^Library: src/Lib/Lib\.csproj packable; version: 2\.3\.0 \(Version in src/Lib/Lib\.csproj\); package validation: on, against 2\.2\.0: dotnet pack fails on a breaking change \(build-test\.sh --pack\)'
check "detect-project-type: a multi-target library" 0 '^Target frameworks: netstandard2\.0 \(src/Lib\), net8\.0 \(src/Lib, tests/Lib\.Tests\)|^Target frameworks: .*netstandard2\.0 \(src/Lib\)'
run build-test.sh --pack
check "--pack: build, tests, then the package" 0 '^PACK: OK \(Lib\.1\.0\.0\.nupkg\)'
called "--pack: dotnet pack of what was built (Debug), into the git folder" "^dotnet pack --no-build -c Debug -nologo -v q -o $work/lib/.git/opencode-pack\$"
truth "--pack: nothing written in the repository" '[ -z "$(git status --porcelain)" ]'
# a breaking change that package validation finds
printf '// fake-breaking: Member '"'"'Lib.Client.Connect(string)'"'"' exists on [Baseline] lib/net8.0/Company.Lib.dll but not on lib/net8.0/Company.Lib.dll\n' >> src/Lib/Client.cs
run build-test.sh --pack
check "--pack: a breaking change of the public API is named" 1 "^BREAKING CHANGE: CP0002: Member 'Lib\.Client\.Connect\(string\)' exists on \[Baseline\]"
check "--pack: and fails, never hidden by a suppression file" 1 '^PACK: FAILED \(package validation: 1 breaking change of the public API.*never a suppression file'
git checkout -q -- src/Lib/Client.cs
# what the branch changes in the contracts (api-surface.sh): a signature, a removal, a field, a route
sed -i 's/public void Connect(string host) { }/public void Connect(string host, int port) { }/; /public void Disconnect() { }/d' src/Lib/Client.cs
sed -i 's/    public decimal Total { get; set; }/    public decimal Total { get; set; }\n    public string Currency { get; set; } = "EUR";/' src/Lib/Dtos/InvoiceDto.cs
sed -i 's/\[HttpGet("{id:int}")\]/[HttpGet("{id:guid}")]/' src/Api/Controllers/InvoicesController.cs
run api-surface.sh develop
check "api-surface: a changed signature" 0 '^API CHANGED: src/Lib/Client\.cs: public void Connect\(string host\) -> public void Connect\(string host, int port\)$'
check "api-surface: a removed member" 0 '^API REMOVED: src/Lib/Client\.cs: public void Disconnect\(\)$'
check "api-surface: a new field of a contract" 0 '^CONTRACT FIELD ADDED: src/Lib/Dtos/InvoiceDto\.cs: public string Currency \{ get; set; \} = "EUR";$'
check "api-surface: a route changed" 0 '^ROUTE REMOVED: src/Api/Controllers/InvoicesController\.cs: \[HttpGet\("\{id:int\}"\)\]$'
check "api-surface: the verdict" 0 '^SURFACE: breaking \(3 removed or changed\)'
truth "api-surface: the internal member is not the public API" '! printf "%s\n" "$out" | grep -q Hidden'
git checkout -q -- src
printf 'namespace Lib;\npublic static class ClientExtensions\n{\n    public static void Ping(this Client c) { }\n}\n' > src/Lib/ClientExtensions.cs
run api-surface.sh develop
check "api-surface: an addition only is additive" 0 '^SURFACE: additive \(2 added\): compatible'
rm src/Lib/ClientExtensions.cs
run api-surface.sh develop
check "api-surface: no production code changed" 0 '^SURFACE: unchanged \(no production C# file changed\)$'
# the quality of the tests (test-lint.sh): what the branch brings, not what was there
cat >> tests/Lib.Tests/ClientTests.cs <<'EOF'
public class RetryTests
{
    [Fact]
    public void Retry_NoAssert()
    {
        var client = new Client("h");
        client.Connect("h");
    }

    [Fact]
    public async Task Retry_Waits()
    {
        await Task.Delay(100);
        var now = DateTime.Now;
        Assert.Equal(1, Retry.Count(now));
    }

    [Fact(Skip = "flaky")]
    public void Retry_Old() { Assert.True(true); }

    [Fact]
    public void Retry_Helper()
    {
        var policy = Build();
        AssertValid(policy);
    }
}
EOF
run test-lint.sh --changed develop
check "test-lint: a test without assertion" 0 'ClientTests\.cs:[0-9]+: blocking: test without assertion'
check "test-lint: a real delay" 0 'ClientTests\.cs:[0-9]+: major: sleep or real delay'
check "test-lint: a real clock" 0 'ClientTests\.cs:[0-9]+: major: real clock'
check "test-lint: a skipped test" 0 'ClientTests\.cs:[0-9]+: major: skipped test'
check "test-lint: an assertion that cannot fail" 0 'ClientTests\.cs:[0-9]+: minor: an assertion that cannot fail'
check "test-lint: the count" 0 '^TEST LINT: 5 problems \(1 blocking, 3 major\)$'
truth "test-lint: a helper that asserts is an assertion" '! printf "%s\n" "$out" | grep -q "ClientTests.cs:3[2-9]: blocking"'
truth "test-lint: the test that was there is not read again" '! printf "%s\n" "$out" | grep -q "ClientTests.cs:5:"'
git checkout -q -- tests
# /review of a teammate's branch: its contracts and the tests it brings, read from git (review-target.sh), my working
# tree untouched
git init -q --bare "$work/lib-origin.git"
git remote add origin "$work/lib-origin.git"
git push -q origin develop 2>/dev/null
git checkout -q -b feature/ABC-8-teammate develop
sed -i '/public void Disconnect() { }/d' src/Lib/Client.cs
printf 'public class TeammateTests\n{\n    [Fact]\n    public void Connect_Twice() { var c = new Client("h"); c.Connect("h"); }\n}\n' >> tests/Lib.Tests/ClientTests.cs
git add -A && git commit -q -m "feat: a teammate change"
git push -q origin feature/ABC-8-teammate 2>/dev/null
git checkout -q feature/ABC-7-retry
git branch -q -D feature/ABC-8-teammate
printf 'local work in progress\n' > notes.txt
# shellcheck disable=SC2034 # read in the eval of truth
before=$(git status --porcelain; git rev-parse HEAD; git branch --show-current)
run review-target.sh feature/ABC-8-teammate
check "review: the contracts of the reviewed branch, from git" 0 '^API REMOVED: src/Lib/Client\.cs: public void Disconnect\(\)$'
check "review: their verdict" 0 '^SURFACE: breaking \(1 removed or changed\)'
check "review: the tests it brings, as committed" 0 '^tests/Lib\.Tests/ClientTests\.cs:[0-9]+: blocking: test without assertion'
truth "review: my working tree, my branch and my files untouched" '[ "$(git status --porcelain; git rev-parse HEAD; git branch --show-current)" = "$before" ]'
rm notes.txt

# ---------- two repositories of one application (related-repos.sh) ----------
mkdir -p "$work/apps"
for r in api-factures front-factures; do
  mkdir -p "$work/apps/$r"
  git -C "$work/apps/$r" init -q
  printf '# %s\n' "$r" > "$work/apps/$r/README.md"
done
cat > "$work/apps/front-factures/AGENTS.md" <<'EOF'
# AGENTS.md

## Dépôts liés
- `api-factures` : l'API .NET des factures (GET /api/invoices)
- `lib-commun` (`~/nowhere/lib-commun`) : la librairie NuGet interne des montants

## Build & test
- npm test
EOF
for r in api-factures front-factures; do git -C "$work/apps/$r" add -A && git -C "$work/apps/$r" commit -q -m init; done
git -C "$work/apps/api-factures" checkout -q -b feature/ABC-123-export-csv
mkdir -p "$work/apps/api-factures/.git/opencode-tickets"
cat > "$work/apps/api-factures/.git/opencode-tickets/ABC-123.md" <<'EOF'
# ABC-123 — Export CSV des factures

## Contrat
- GET /api/invoices/export?from=&to= : text/csv, colonnes Number;Date;Total
- InvoiceDto : champ Currency ajouté (string, "EUR" par défaut)

## Suivi
- 2026-10-20 10:00 — /go - étape 1 faite
- 2026-10-21 16:30 — /go - livré - MR https://gitlab.example.com/g/api/-/merge_requests/42 - build ok - tests 48/48
EOF
cd "$work/apps/front-factures" || exit 1
run related-repos.sh ABC-123
check "related-repos: the other repository, next to this one" 0 "^RELATED: api-factures — $work/apps/api-factures \(branch feature/ABC-123-export-csv; next to this repository\): l'API \.NET des factures"
check "related-repos: its branch and its delivery for the ticket" 0 '^  ABC-123 there: branch feature/ABC-123-export-csv, sheet .*ABC-123\.md; 2026-10-21 16:30 — /go - livré - MR https://gitlab\.example\.com/g/api/-/merge_requests/42'
check "related-repos: its contract" 0 '^    - GET /api/invoices/export\?from=&to= : text/csv'
check "related-repos: a repository not on this machine says how to find it" 0 "^RELATED: lib-commun — not found at $HOME/nowhere/lib-commun \(path of its line\): /outil liens finds it"
run related-repos.sh
check "related-repos: without a key, where they are" 0 '^RELATED: api-factures — ' '^  ABC-123'
cd "$work/apps/api-factures" || exit 1
run related-repos.sh ABC-123
check "related-repos: a repository without the section" 0 '^RELATED: none \(no AGENTS\.md'
run detect-project-type.sh
cd "$work/apps/front-factures" || exit 1
run detect-project-type.sh
check "detect-project-type: the related repositories" any '^Related repositories \(AGENTS\.md\): api-factures, lib-commun \(~/nowhere/lib-commun\) — sh ~/.config/opencode/scripts/related-repos\.sh <KEY>'

# ---------- /tests api: the integration test project; env-tests.sh, environments.sh, http-files.sh, schedule.sh ----------
mkdir -p "$work/apitests" "$NUGET_PACKAGES/microsoft.aspnetcore.mvc.testing/8.0.11" "$NUGET_PACKAGES/microsoft.aspnetcore.mvc.testing/10.0.0"
cd "$work/apitests" || exit 1
git init -q
project src/Api/Api.csproj Microsoft.NET.Sdk.Web
sed -i 's#net10.0#net8.0#' src/Api/Api.csproj
printf 'var builder = WebApplication.CreateBuilder(args);\nvar app = builder.Build();\napp.MapGet("/api/orders", () => Results.Ok());\napp.MapHealthChecks("/health");\napp.Run();\n' > src/Api/Program.cs
project src/Lib/Lib.csproj Microsoft.NET.Sdk
printf '<Solution>\n  <Project Path="src/Api/Api.csproj" />\n  <Project Path="src/Lib/Lib.csproj" />\n</Solution>\n' > Shop.slnx
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
run test-guardian.sh setup --integration xunit src/Lib/Lib.csproj
check "setup --integration: a project that is not an API" 1 '^STOP: src/Lib/Lib\.csproj is not an ASP\.NET Core project'
run test-guardian.sh setup --integration xunit src/Api/Program.cs
check "setup --integration: the integration test project of the API" 0 '^SETUP: tests/Shop\.IntegrationTests/Shop\.IntegrationTests\.csproj created \(xunit, net8\.0\), it references src/Api/Api\.csproj; .*Microsoft\.AspNetCore\.Mvc\.Testing 8\.0\.11 \(cache\).*added to Shop\.slnx; public partial class Program added to src/Api/Program\.cs; build OK'
truth "setup --integration: WebApplicationFactory of the major version of the target framework" 'grep -q "Microsoft.AspNetCore.Mvc.Testing\" Version=\"8.0.11\"" tests/Shop.IntegrationTests/Shop.IntegrationTests.csproj'
truth "setup --integration: Program made public before .NET 10" 'grep -q "^public partial class Program { }$" src/Api/Program.cs'
git add -A && git commit -q -m setup
run test-guardian.sh setup --integration xunit src/Api/Api.csproj
check "setup --integration: nothing when a test project has WebApplicationFactory" 0 '^SETUP: nothing to do, tests/Shop\.IntegrationTests/Shop\.IntegrationTests\.csproj has Microsoft\.AspNetCore\.Mvc\.Testing'
mkdir -p "$work/api10"
cd "$work/api10" || exit 1
git init -q
project src/Api/Api.csproj Microsoft.NET.Sdk.Web
printf 'var app = WebApplication.CreateBuilder(args).Build();\napp.Run();\n' > src/Api/Program.cs
git add -A && git commit -q -m init
run test-guardian.sh setup --integration xunit src/Api/Api.csproj
check "setup --integration: .NET 10 makes Program public itself" 0 'Microsoft\.AspNetCore\.Mvc\.Testing 10\.0\.0; build OK$' 'public partial class Program'
cd "$work/apitests" || exit 1

# the environment tests: one class with the category, in memory tests beside them
cat > tests/Shop.IntegrationTests/OrdersEnvironmentTests.cs <<'EOF'
using Xunit;
namespace Shop.IntegrationTests;
[Trait("Category", "Environment")]
public class OrdersEnvironmentTests { }
// <!-- fake-test: Shop.IntegrationTests.OrdersEnvironmentTests.Get_Orders_OnItsUrl env API_BASE_URL=https://api-recette.example.com category=Environment -->
// <!-- fake-test: Shop.IntegrationTests.OrdersEnvironmentTests.Get_Orders_WithItsToken env API_TOKEN=s3cr3t-value category=Environment -->
// <!-- fake-test: Shop.IntegrationTests.OrdersEnvironmentTests.Get_Orders_OnItsName env API_ENVIRONMENT=recette category=Environment -->
// <!-- fake-test: Shop.IntegrationTests.OrdersEnvironmentTests.Post_Orders_CreatesThenDeletes pass category=EnvironmentWrites -->
EOF
cat > tests/Shop.IntegrationTests/OrdersTests.cs <<'EOF'
namespace Shop.IntegrationTests;
public class OrdersTests { }
// <!-- fake-test: Shop.IntegrationTests.OrdersTests.Get_Orders_Returns200 pass -->
EOF
mkdir -p tests/Edge.Tests
project tests/Edge.Tests/Edge.Tests.csproj Microsoft.NET.Sdk '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' '  <PackageReference Include="xunit" Version="2.9.2" />' '</ItemGroup>'
cat > tests/Edge.Tests/EdgeTests.cs <<'EOF'
[Xunit.Trait("Category", "Environment")]
public class EdgeTests { }
// <!-- fake-test: Edge.Tests.EdgeTests.Echoes fail The API refused the header Authorization: Bearer s3cr3t-value category=Environment -->
// <!-- fake-test: Edge.Tests.EdgeTests.Unreachable fail System.Net.Http.HttpRequestException : Name or service not known (api-recette.example.com:443) category=Environment -->
EOF
git add -A && git commit -q -m tests
# (the call to the API before the build goes to the network: left out here, environments-test.sh checks it)
ENV_TESTS_PREFLIGHT=0
export ENV_TESTS_PREFLIGHT
run env-tests.sh recette
check "env-tests: no environment declared, how to declare one" 1 '^STOP: no environment declared in AGENTS\.md\. Add a section « ## Environnements »'
cat > AGENTS.md <<'EOF'
# Shop

## Environnements
- `recette` : https://api-recette.example.com/ (jeton : `API_TOKEN_RECETTE`, écriture permise)
- `preprod` : https://api-preprod.example.com (jeton : `API_TOKEN_PREPROD`)
- `prod` : https://api.example.com (production)
- `leak` : https://user:secret@api.example.com
EOF
git add -A && git commit -q -m env
run environments.sh
check "environments: each line, its token variable, writes, production, its access" 0 "^recette	https://api-recette\.example\.com	API_TOKEN_RECETTE	yes	no	token$"
check "environments: production, no writes" 0 "^prod	https://api\.example\.com	-	no	yes	none$"
check "environments: a URL with a password is refused" 0 '^WARNING: leak: a user or a password in its URL' 'secret@'
run env-tests.sh
check "env-tests: which environment" 1 '^STOP: which environment\? env-tests\.sh <environment>: recette preprod prod$'
run env-tests.sh qa
check "env-tests: an environment that is not declared" 1 '^STOP: no environment qa in AGENTS\.md \(declared: recette preprod prod\)'
run env-tests.sh prod
check "env-tests: never production" 1 '^STOP: prod is a production environment: the pack never runs tests there'
run env-tests.sh preprod --ecriture
check "env-tests: writes only where AGENTS.md allows them" 1 '^STOP: preprod does not allow writes'
run env-tests.sh recette tests/Shop.IntegrationTests/Shop.IntegrationTests.csproj
check "env-tests: its token variable not set is the machine's problem" 1 '^ENVIRONMENT PROBLEM: the variable API_TOKEN_RECETTE, which holds the token of recette, is not set in the environment of OpenCode'
API_TOKEN_RECETTE=s3cr3t-value
# a machine with the runtimes of these net8.0 tests
FAKE_DOTNET_RUNTIMES="Microsoft.AspNetCore.App 8.0.11
Microsoft.NETCore.App 8.0.11
Microsoft.AspNetCore.App 10.0.0
Microsoft.NETCore.App 10.0.0"
export API_TOKEN_RECETTE FAKE_DOTNET_RUNTIMES
run env-tests.sh recette tests/Shop.IntegrationTests/Shop.IntegrationTests.csproj
check "env-tests: the environment tests, read only, with the URL, token and name of the environment" 0 '^ENVIRONMENT: recette https://api-recette\.example\.com \(read only\)'
check "env-tests: one line per test" 0 '^  OK  Shop\.IntegrationTests\.OrdersEnvironmentTests\.Get_Orders_WithItsToken \([0-9]+\.[0-9]{2} s\)$' 'CreatesThenDeletes|OrdersTests\.Get_Orders_Returns200'
check "env-tests: the build and tests of build-test.sh" 0 '^TESTS: OK$' 'TESTS: FAILED'
called "env-tests: the filter of the category" '^dotnet test tests/Shop\.IntegrationTests/Shop\.IntegrationTests\.csproj .*--filter Category=Environment '
run env-tests.sh recette --ecriture tests/Shop.IntegrationTests/Shop.IntegrationTests.csproj
check "env-tests: --ecriture adds the tests that write, where they are allowed" 0 '^  OK  Shop\.IntegrationTests\.OrdersEnvironmentTests\.Post_Orders_CreatesThenDeletes'
check "env-tests: with writes, said" 0 '^ENVIRONMENT: recette https://api-recette\.example\.com \(writes allowed\)'
run env-tests.sh recette tests/Edge.Tests/Edge.Tests.csproj
check "env-tests: the token is never printed" 1 'Bearer \*\*\* ' 's3cr3t-value'
check "env-tests: an environment out of reach is the machine's problem" 1 '^ENVIRONMENT PROBLEM: recette \(https://api-recette\.example\.com\) cannot be reached from this machine'
run env-tests.sh recette
check "env-tests: every project with environment tests" 1 '^PROJECT: tests/Edge\.Tests/Edge\.Tests\.csproj$'
unset API_TOKEN_RECETTE FAKE_DOTNET_RUNTIMES ENV_TESTS_PREFLIGHT

# test-lint: the HTTP calls and the conditional skip of environment tests are their purpose
cat > tests/Shop.IntegrationTests/HealthEnvironmentTests.cs <<'EOF'
using Xunit;
[Trait("Category", "Environment")]
public class HealthEnvironmentTests
{
    [Fact]
    public async Task Get_Health()
    {
        using var client = new HttpClient();
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("API_BASE_URL"))) Assert.Inconclusive("no environment");
        var response = await client.GetAsync("https://api-recette.example.com/health");
        Assert.True(response.IsSuccessStatusCode);
    }
}
EOF
run test-lint.sh tests/Shop.IntegrationTests/HealthEnvironmentTests.cs
check "test-lint: an environment test calls the deployed API" 0 '^TEST LINT: OK'
sed 's/\[Trait("Category", "Environment")\]//' tests/Shop.IntegrationTests/HealthEnvironmentTests.cs > tests/Shop.IntegrationTests/HealthTests.cs
run test-lint.sh tests/Shop.IntegrationTests/HealthTests.cs
check "test-lint: the same calls in another test are findings" 0 'HealthTests\.cs:[0-9]+: major: real HTTP call'
check "test-lint: and its skip too" 0 'HealthTests\.cs:[0-9]+: major: skipped test'
rm tests/Shop.IntegrationTests/HealthEnvironmentTests.cs tests/Shop.IntegrationTests/HealthTests.cs

# http-files.sh: the requests of the API for the HTTP client of Rider
mkdir -p src/Api/Properties
printf '{ "profiles": { "https": { "applicationUrl": "https://localhost:7123;http://localhost:5123" } } }\n' > src/Api/Properties/launchSettings.json
git add -A && git commit -q -m launch
run http-files.sh
check "http-files: one file per group of endpoints" 0 '^HTTP: src/Api/http/Program\.http \(2 requests\)$'
check "http-files: the environments, never production" 0 '^ENVIRONMENTS: local recette preprod in src/Api/http/http-client\.env\.json \(production left out: prod\)$'
check "http-files: the private file of the tokens never committed" 0 '^IGNORED: src/Api/http/http-client\.private\.env\.json added to \.gitignore'
truth "http-files: git ignores the tokens" 'git check-ignore -q src/Api/http/http-client.private.env.json'
truth "http-files: each request checks its status" 'grep -q "client.assert(response.status >= 200 && response.status < 300" src/Api/http/Program.http'
truth "http-files: the base URL of each environment" 'grep -q "\"baseUrl\": \"https://api-recette.example.com\"" src/Api/http/http-client.env.json && ! grep -q "api.example.com\"" src/Api/http/http-client.env.json'
run http-files.sh
check "http-files: a file that exists is never overwritten" 0 '^KEPT: src/Api/http/Program\.http \(exists\)$' '^HTTP:'

# schedule.sh: what /outil planifier writes for the plugin
OPENCODE_SCHEDULES="$work/schedules.md"
export OPENCODE_SCHEDULES
run schedule.sh --raw "8h45 lun-ven /daily"
check "schedule: a command that writes nothing, at its time, in the main folder of the repository" 0 "^Planifiée : #1, /daily à 08:45 \(lun,mar,mer,jeu,ven\), dans $work/apitests$"
run schedule.sh --raw "22h /tests env recette"
check "schedule: the environment tests, read only" 0 '^Planifiée : #2, /tests env recette à 22:00'
run schedule.sh --raw "22h /tests env prod"
check "schedule: never on production" 1 '^Refusé : prod est la production'
run schedule.sh --raw "7h /go ABC-1"
check "schedule: never a command that writes" 1 '^Refusé : /go ABC-1 ne se planifie pas'
run schedule.sh --raw "suppr 1"
check "schedule: removed" 0 '^Retirée : #1$' '#1 08:45'
truth "schedule: the line the plugin reads" "grep -q '^- #2 22:00 lun,mar,mer,jeu,ven /tests env recette — $work/apitests (ajoutée le ' '$work/schedules.md'"
unset OPENCODE_SCHEDULES

# the category filter of xUnit v3 on Microsoft.Testing.Platform: --filter-trait
cd "$work/mtp" || exit 1
printf '// <!-- fake-test: Core.Tests.HealthEnvironmentTests.Get pass category=Environment -->\n' > tests/Core.Tests/HealthEnvironmentTests.cs
run build-test.sh tests/Core.Tests/Core.Tests.csproj --filter "Category=Environment"
check "xUnit v3: the category as a trait filter" 0 'TESTS: OK \(1 tests?\)'
called "xUnit v3: --filter-trait" '^dotnet exec .*--filter-trait Category=Environment'
rm tests/Core.Tests/HealthEnvironmentTests.cs

# ---------- Razor components: their module, their safety net, their tests with bUnit (a page that leaves Blazorise) ----------
mkdir -p "$work/blazor"
cd "$work/blazor" || exit 1
git init -q
project src/Web/Web.csproj Microsoft.NET.Sdk.Web '<ItemGroup>' '  <PackageReference Include="Blazorise.DataGrid" Version="2.2.2" />' '</ItemGroup>'
mkdir -p src/Web/Components/Pages src/Web/Orders
cat > src/Web/Components/Pages/Orders.razor <<'EOF'
@page "/commandes"
@inject IOrderSource Source
@inject ILogger<Orders> Logger

<DataGrid TItem="Order" Data="@orders" ShowPager PageSize="5">
    <DataGridColumn TItem="Order" Field="@nameof(Order.Number)" Caption="Numéro" />
</DataGrid>
<button type="button" @onclick="() => Logger.LogInformation(\"refresh\")">Actualiser</button>

@code {
    private IReadOnlyList<Order> orders = Array.Empty<Order>();

    protected override void OnInitialized() => orders = Source.All();
}
EOF
printf 'namespace Web.Orders;\npublic interface IOrderSource\n{\n    IReadOnlyList<Order> All();\n}\n' > src/Web/Orders/IOrderSource.cs
printf 'namespace Web.Orders;\npublic class OrderSource(OrdersDb db) : IOrderSource\n{\n    public IReadOnlyList<Order> All() => db.Orders;\n}\n' > src/Web/Orders/OrderSource.cs
printf 'namespace Web.Orders;\npublic class OrdersDb\n{\n    public List<Order> Orders { get; } = new();\n}\n' > src/Web/Orders/OrdersDb.cs
printf '<p>@Total</p>\n' > src/Web/Components/Pages/Invoices.razor
printf 'namespace Web.Components.Pages;\npublic partial class Invoices\n{\n    [Inject] private IOrderSource Source { get; set; } = default!;\n    private int Total => Source.All().Count;\n}\n' > src/Web/Components/Pages/Invoices.razor.cs
project src/Lib/Lib.csproj Microsoft.NET.Sdk
printf 'namespace Lib;\npublic static class Money { }\n' > src/Lib/Money.cs
# two unit test projects, and none references the web project yet
project tests/Web.Tests/Web.Tests.csproj Microsoft.NET.Sdk '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '  <PackageReference Include="coverlet.collector" Version="6.0.2" />' '</ItemGroup>' \
  '<!-- fake-test: Web.Tests.SmokeTests.Builds pass -->'
project tests/Lib.Tests/Lib.Tests.csproj Microsoft.NET.Sdk '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '  <PackageReference Include="coverlet.collector" Version="6.0.2" />' \
  '  <ProjectReference Include="../../src/Lib/Lib.csproj" />' '</ItemGroup>'
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init

run test-guardian.sh deps src/Web/Components/Pages/Orders.razor
check "deps of a Razor component: its class, named after its file" 0 '^  class Orders$'
check "deps of a Razor component: what it injects, and the class that implements it" 0 '^DEPENDS: IOrderSource -> src/Web/Orders/OrderSource\.cs$'
check "deps of a Razor component: the second level" 0 '^DEPENDS \(level 2\): OrdersDb -> src/Web/Orders/OrdersDb\.cs$'
check "deps of a Razor component: a type of the framework, without its generic argument" 0 '^UNRESOLVED: ILogger \(outside this repository'
run test-guardian.sh deps src/Web/Components/Pages/Invoices.razor
check "deps of a Razor component: the [Inject] properties of its code-behind" 0 '^DEPENDS: IOrderSource -> src/Web/Orders/OrderSource\.cs$'

run fortify.sh prereq --tests
check "prereq in a Blazor repository: no unit test project has bUnit" 0 '^PREREQ: COMPONENT TESTS: none \(no unit test project has bUnit' 'COMPONENT TESTS: bUnit'
check "prereq: the unit test projects themselves are ready" 0 '^PREREQ: OK$'
run test-guardian.sh setup --components xunit src/Web/Components/Pages/Orders.razor
check "setup --components: several unit test projects, none for these components: STOP, nothing changed" 1 '^STOP: several unit test projects, and none references src/Web/Web\.csproj'
truth "setup --components: the STOP changed nothing" '[ -z "$(git status --porcelain)" ]'
sed -i 's#</Project>#  <ItemGroup><ProjectReference Include="..\\..\\src\\Web\\Web.csproj" /></ItemGroup>\n</Project>#' tests/Web.Tests/Web.Tests.csproj
git add -A && git commit -q -m "test: reference the web project"
run test-guardian.sh setup --components xunit src/Lib/Money.cs
check "setup --components: a project without component" 1 '^STOP: src/Lib/Lib\.csproj has no Razor component'
run test-guardian.sh setup --components xunit src/Web/Components/Pages/Orders.razor
check "setup --components: bUnit in the unit test project that references the components" 0 '^SETUP: bunit 2\.11\.3 added to tests/Web\.Tests/Web\.Tests\.csproj; build OK$'
truth "setup --components: the package, next to the others" 'grep -q "<PackageReference Include=\"bunit\" Version=\"2.11.3\" />" tests/Web.Tests/Web.Tests.csproj'
truth "setup --components: only that project changed" '[ "$(git status --porcelain)" = " M tests/Web.Tests/Web.Tests.csproj" ]'
called "setup --components: built once" '^dotnet build tests/Web\.Tests/Web\.Tests\.csproj'
git add -A && git commit -q -m "test: add bUnit"
run fortify.sh prereq --tests
check "prereq: the unit test project that has bUnit" 0 '^PREREQ: COMPONENT TESTS: bUnit in tests/Web\.Tests/Web\.Tests\.csproj$'
run test-guardian.sh setup --components xunit src/Web/Components/Pages/Invoices.razor
check "setup --components: nothing to do when bUnit is there" 0 '^SETUP: nothing to do, tests/Web\.Tests/Web\.Tests\.csproj has bUnit$'

# the safety net of a page: its markup (BuildRenderTree, its event handlers included) and the methods of its @code
cat > tests/Web.Tests/OrdersPageTests.cs <<'EOF'
// <!-- fake-test: Web.Tests.OrdersPageTests.Orders_FirstPage_ShowsFiveOrders pass -->
// <!-- fake-cover: src/Web/Components/Pages/Orders.razor c=Web.Components.Pages.Orders m=BuildRenderTree 5:1 6:1 -->
// <!-- fake-cover: src/Web/Components/Pages/Orders.razor c=Web.Components.Pages.Orders/<>c__DisplayClass0_0 m=<BuildRenderTree>b__0_0 8:0 -->
// <!-- fake-cover: src/Web/Components/Pages/Orders.razor c=Web.Components.Pages.Orders m=OnInitialized 13:1 -->
EOF
run test-guardian.sh coverage P1-net tests/Web.Tests/Web.Tests.csproj src/Web/Components/Pages/Orders.razor
check "coverage of a Razor component" 0 '^src/Web/Components/Pages/Orders\.razor lines 3/4 \(75%\) branches 0/0 uncovered 8$'
run test-guardian.sh net P1-net src/Web/Components/Pages/Orders.razor:BuildRenderTree src/Web/Components/Pages/Orders.razor:OnInitialized
check "net of a Razor component: its markup, its event handler included" 0 '^NET: src/Web/Components/Pages/Orders\.razor:BuildRenderTree lines 2/3 \(66%\) branches 0/0 uncovered 8$'
check "net of a Razor component: a method of its @code" 0 '^NET: src/Web/Components/Pages/Orders\.razor:OnInitialized lines 1/1 \(100%\)'
check "net of a Razor component: THIN under the minimum" 0 '^SAFETY NET: THIN \(3/4 lines of these 2 methods run by the tests, 75% < 80%\)'
run test-guardian.sh net P1-net src/Web/Components/Pages/Orders.razor:Render
check "net of a Razor component: a wrong name, and the methods the report has" 1 '^STOP: not in the coverage report: src/Web/Components/Pages/Orders\.razor:Render \(the methods of this file in the report: BuildRenderTree, OnInitialized\)'
run test-guardian.sh net P1-net src/Web/Components/Pages/Orders.razor
check "net of a Razor component: a method is needed" 1 '^STOP: bad method src/Web/Components/Pages/Orders\.razor: '
sed -i 's#m=<BuildRenderTree>b__0_0 8:0#m=<BuildRenderTree>b__0_0 8:1#' tests/Web.Tests/OrdersPageTests.cs
run test-guardian.sh coverage P1-after tests/Web.Tests/Web.Tests.csproj src/Web/Components/Pages/Orders.razor
run test-guardian.sh net P1-after src/Web/Components/Pages/Orders.razor:BuildRenderTree src/Web/Components/Pages/Orders.razor:OnInitialized
check "net of a Razor component: OK once its event handler runs" 0 '^SAFETY NET: OK \(4/4 lines of these 2 methods run by the tests, 100%; minimum 80%\)$'
run test-guardian.sh compare P1-net P1-after
check "compare: a Razor component that gained coverage" 0 '^COVERAGE: no file lost coverage$'
# a markup without C# (tags and attributes only): coverlet reports no BuildRenderTree for it
cp tests/Web.Tests/OrdersPageTests.cs "$work/orders-tests.kept"
printf '%s\n' '// <!-- fake-test: Web.Tests.OrdersPageTests.Orders_FirstPage_ShowsFiveOrders pass -->' \
  '// <!-- fake-cover: src/Web/Components/Pages/Orders.razor c=Web.Components.Pages.Orders m=OnInitialized 13:1 -->' > tests/Web.Tests/OrdersPageTests.cs
run test-guardian.sh coverage P2 tests/Web.Tests/Web.Tests.csproj src/Web/Components/Pages/Orders.razor
run test-guardian.sh net P2 src/Web/Components/Pages/Orders.razor:OnInitialized src/Web/Components/Pages/Orders.razor:BuildRenderTree
check "net of a page whose markup coverlet does not measure: said, never a STOP" 0 '^NET: src/Web/Components/Pages/Orders\.razor:BuildRenderTree not measured: coverlet counts the C# statements of a component' '^STOP'
check "net of a page whose markup coverlet does not measure: its @code measured" 0 '^SAFETY NET: OK \(1/1 lines of these 2 methods run by the tests, 100%; minimum 80%\)$'
run test-guardian.sh net P2 src/Web/Components/Pages/Orders.razor:BuildRenderTree
check "net of a markup alone: nothing measured, its tests are its net" 0 '^SAFETY NET: OK \(no line of these methods is measured: the markup of a component is checked by the tests of what its users see'
run test-guardian.sh net P2 src/Web/Components/Pages/Invoices.razor:BuildRenderTree
check "net of a component that no test reaches: a STOP, not « not measured »" 1 '^STOP: not in the coverage report: src/Web/Components/Pages/Invoices\.razor:BuildRenderTree \(this file is not in the report'
cp "$work/orders-tests.kept" tests/Web.Tests/OrdersPageTests.cs
git add -A && git commit -q -m "test: the safety net of the orders page"
# the changed lines of a page: measured like those of a C# file
git checkout -q -b feature/natif
sed -i 's#ShowPager PageSize="5"#ShowPager PageSize="10"#' src/Web/Components/Pages/Orders.razor
git commit -q -am "feat: ten orders per page"
run test-guardian.sh changes develop tests/Web.Tests/Web.Tests.csproj
check "changes: the changed lines of a Razor component" 0 '^CHANGED: src/Web/Components/Pages/Orders\.razor 1/1 changed lines covered$'
check "changes: their coverage" 0 '^COVERAGE OF THE CHANGES: 1/1 changed lines covered \(100%\) in 1 files'
git checkout -q develop

# a Blazor repository without any test project: the unit test project created with bUnit
mkdir -p "$work/blazor-new"
cd "$work/blazor-new" || exit 1
git init -q
project src/Web/Web.csproj Microsoft.NET.Sdk.Web
mkdir -p src/Web/Components/Pages
printf '@page "/"\n<h1>Accueil</h1>\n' > src/Web/Components/Pages/Home.razor
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
run fortify.sh prereq --tests
check "prereq: no test project, in a Blazor repository" 0 '^PREREQ: COMPONENT TESTS: none'
check "prereq: no test project, the setup needed" 0 '^PREREQ: SETUP NEEDED$'
run test-guardian.sh setup --components xunit src/Web/Components/Pages/Home.razor
check "setup --components without test project: created, with bUnit" 0 '^SETUP: tests/Web\.UnitTests/Web\.UnitTests\.csproj created \(xunit, net10\.0\), it references src/Web/Web\.csproj; packages: .*bunit 2\.11\.3; build OK$'
truth "setup --components without test project: its coverage collector too" 'grep -q "coverlet.collector" tests/Web.UnitTests/Web.UnitTests.csproj'

# ---------- blazor-native.sh: the inventory of a Blazorise application, its native components, what is left ----------
mkdir -p "$work/blazorise"
cd "$work/blazorise" || exit 1
git init -q
mkdir -p src/Web/Components/Pages src/Web/Components/Layout src/Lib docs
cat > src/Web/Web.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Blazorise.Bootstrap5" Version="2.2.2" />
    <PackageReference Include="Blazorise.DataGrid" Version="2.2.2" />
  </ItemGroup>
</Project>
EOF
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/Lib/Lib.csproj
printf '@using Microsoft.AspNetCore.Components.Web\n@using Blazorise\n@using Blazorise.DataGrid\n' > src/Web/Components/_Imports.razor
printf '<link href="_content/Blazorise/blazorise.css" rel="stylesheet" />\n<Routes />\n' > src/Web/Components/App.razor
printf 'var builder = WebApplication.CreateBuilder(args);\nbuilder.Services.AddBlazorise(o => o.ProductToken = "SECRET-TOKEN-VALUE").AddBootstrap5Providers();\n' > src/Web/Program.cs
printf '{ "Blazorise": { "ProductToken": "SECRET-TOKEN-VALUE" } }\n' > src/Web/appsettings.json
printf '@inherits LayoutComponentBase\n<Bar><Icon Name="IconName.Home" /></Bar>\n@Body\n' > src/Web/Components/Layout/MainLayout.razor
cat > src/Web/Components/Pages/Orders.razor <<'EOF'
@page "/commandes"
@* <DataGrid> in a Razor comment is no tag *@
<DataGrid TItem="Order" Data="@orders" ShowPager>
    <DataGridColumn TItem="Order" Field="Number" Caption="Numéro" />
    <DataGridColumn TItem="Order" Field="Total" Caption="Total" />
</DataGrid>
<Button Clicked="Reload">Recharger</Button>
<SfGrid />
<Frobnicate />
@code {
    private List<Order> orders = new();
    private Dictionary<string, Alert> other = new();
}
EOF
cat > src/Web/Components/Pages/Edit.razor <<'EOF'
@page "/edit"
@inject IMessageService Messages
<Validations>
    <Field><FieldLabel>Nom</FieldLabel><TextInput @bind-Value="name" /></Field>
</Validations>
EOF
printf '@page "/confirm"\n<Modal @ref="modal"><ModalContent>Oui ?</ModalContent></Modal>\n' > src/Web/Components/Pages/Confirm.razor
printf '@page "/"\n<PageTitle>Accueil</PageTitle>\n<h1>Accueil</h1>\n' > src/Web/Components/Pages/Home.razor
printf '# Notes\nBlazorise leaves: DataGrid, IMessageService, ProductToken.\n' > docs/notes.md
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
# a page of the step under way, not committed yet
printf '<Badge>neuf</Badge>\n' > src/Web/Components/Pages/Draft.razor
# shellcheck disable=SC2034 # read in the eval of truth
before=$(git status --porcelain)
run blazor-native.sh inventory
check "native inventory: the files that use Blazorise, its version" 0 '^INVENTORY: 5 \.razor file\(s\) use Blazorise \(14 tags in all\), Blazorise 2\.2\.2$'
check "native inventory: the leaves first (simple, form, dialog, grid), the page not committed yet included" 0 '^PAGE: src/Web/Components/Pages/Draft\.razor — simple: Badge×1 — step 1$'
check "native inventory: the layout, a simple page" 0 '^PAGE: src/Web/Components/Layout/MainLayout\.razor — simple: Icon×1, Bar×1 — step 2$'
check "native inventory: the form" 0 '^PAGE: src/Web/Components/Pages/Edit\.razor — form: Validations×1, TextInput×1, FieldLabel×1, Field×1 — step 3$'
check "native inventory: the dialog" 0 '^PAGE: src/Web/Components/Pages/Confirm\.razor — dialog: ModalContent×1, Modal×1 — step 4$'
check "native inventory: the grid last, without the tag of its Razor comment" 0 '^PAGE: src/Web/Components/Pages/Orders\.razor — grid: DataGridColumn×2, DataGrid×1, Button×1 — step 5$'
check "native inventory: a tag of nobody named to check" 0 '^UNKNOWN TAG: <Frobnicate> in src/Web/Components/Pages/Orders\.razor:9 '
check "native inventory: never a tag of another library, of ASP.NET Core, of a C# generic, of a page without Blazorise" 0 . '<SfGrid>|<PageTitle>|<Order>|<Alert>|Home\.razor'
check "native inventory: the service, and its native one" 0 '^SERVICE: IMessageService in src/Web/Components/Pages/Edit\.razor:2 -> NativeDialogService \(ConfirmAsync; '
check "native inventory: the registration, its license value masked" 0 '^REGISTRATION: src/Web/Program\.cs:2 builder\.Services\.AddBlazorise\(o => o\.ProductToken = "…"\)'
check "native inventory: the link" 0 '^LINK: src/Web/Components/App\.razor:1 _content/Blazorise/blazorise\.css$'
check "native inventory: the packages" 0 '^PACKAGE: Blazorise\.Bootstrap5 2\.2\.2, Blazorise\.DataGrid 2\.2\.2$'
check "native inventory: the license keys, by their names" 0 '^LICENSE KEY: src/Web/appsettings\.json:1 ProductToken \(its value is never printed'
check "native inventory: the license value never printed" 0 . 'SECRET-TOKEN-VALUE'
check "native inventory: the native equivalent of each tag" 0 '^EQUIVALENT: <DataGrid> -> NativeGrid \(Items=, ShowPager'
check "native inventory: the plan, the components first" 0 '^PLAN: a first step that writes the native components \(blazor-native\.sh scaffold <the web project>\), then one page per step .*\(1 with a grid: NativeGrid\) \(1 with dialogs or messages'
truth "native inventory: reads only" '[ "$(git status --porcelain)" = "$before" ]'
run blazor-native.sh check
check "native check: what is left, exit 1" 1 '^BLAZORISE: 23 place\(s\) left$'
check "native check: the packages, the usings, the registration, the link, the service" 1 '^LEFT: project: src/Web/Web\.csproj:6:.*Blazorise\.Bootstrap5'
check "native check: the configuration and the license keys, never their values" 1 '^LEFT: configuration: src/Web/appsettings\.json:1 the section "Blazorise"$' 'SECRET-TOKEN-VALUE'
check "native check: the tags, those of a file not committed yet included" 1 '^LEFT: tag: src/Web/Components/Pages/Draft\.razor:1 <Badge>$'
check "native check: never the Markdown documentation" 1 . 'docs/notes\.md'
run blazor-native.sh frob
check "native: an unknown action" 1 '^STOP: blazor-native\.sh inventory'
run blazor-native.sh scaffold
check "native scaffold: the project is needed" 1 '^STOP: blazor-native\.sh scaffold <the folder of the web project'
run blazor-native.sh scaffold src/Lib
check "native scaffold: never in a project that is no Blazor one" 1 '^STOP: src/Lib/Lib\.csproj is not a Blazor or Razor project'
truth "native scaffold: nothing written in it" '[ ! -d src/Lib/Components ]'
run blazor-native.sh scaffold src/Web
check "native scaffold: in Components/Native, the namespace of the project" 0 '^SCAFFOLD: src/Web/Components/Native \(namespace Web\.Components\.Native, net10\.0\)$'
check "native scaffold: the grid, its columns, the dialogs, the messages, the classes of a field" 0 '^WRITTEN: src/Web/Components/Native/NativeFieldCssClassProvider\.cs$'
truth "native scaffold: 11 files written" '[ "$(printf "%s\n" "$out" | grep -c "^WRITTEN: ")" -eq 11 ]'
check "native scaffold: their @using in _Imports.razor" 0 '^IMPORTS: @using Web\.Components\.Native added to src/Web/Components/_Imports\.razor$'
check "native scaffold: what the pages need once" 0 '^NEXT: .*AddScoped<NativeDialogService>\(\); .*<NativeDialogHost /> <NativeToastHost /> in the layout'
truth "native scaffold: _Imports.razor ends with the @using" '[ "$(tail -n 1 src/Web/Components/_Imports.razor)" = "@using Web.Components.Native" ]'
truth "native scaffold: the namespace in every file, no placeholder left" '! grep -l "__NS__" src/Web/Components/Native/* && [ "$(grep -l -E "^(@namespace|namespace) Web\.Components\.Native;?$" src/Web/Components/Native/* | wc -l)" -eq 11 ]'
truth "native scaffold: never a word of Blazorise in the components (nothing left of it at the end)" '! grep -i -l -E "blazorise|IMessageService|INotificationService|IModalService|IToastService" src/Web/Components/Native/*'
truth "native scaffold: every type named Native… (none meets a name of Blazorise while both are there)" '! grep -h -o -E "^(public|internal)( sealed| abstract| static)* (class|record|enum) [A-Za-z]+" src/Web/Components/Native/*.cs | grep -v -E " Native[A-Za-z]+$" && ! ls src/Web/Components/Native | grep -v "^Native"'
printf '\n// mine\n' >> src/Web/Components/Native/NativeGrid.razor
run blazor-native.sh scaffold src/Web/Web.csproj
check "native scaffold again: every file kept" 0 '^KEPT: src/Web/Components/Native/NativeGrid\.razor \(exists: the application owns it\)$' '^WRITTEN: '
check "native scaffold again: the @using once" 0 '^IMPORTS: src/Web/Components/_Imports\.razor has @using Web\.Components\.Native already$'
truth "native scaffold again: the changes of the application kept" 'tail -n 1 src/Web/Components/Native/NativeGrid.razor | grep -q "// mine"'
truth "native scaffold again: one @using" '[ "$(grep -c "^@using Web.Components.Native$" src/Web/Components/_Imports.razor)" -eq 1 ]'
run blazor-native.sh inventory
check "native inventory after scaffold: the native components are never pages to replace" 0 '^INVENTORY: 5 \.razor file' 'Components/Native/|UNKNOWN TAG: <(TItem|Guid|NativeGrid)'
# a project with its RootNamespace and only a Shared folder; one for .NET 6
mkdir -p src/Shop/Shared src/Old
printf '<Project Sdk="Microsoft.NET.Sdk.Razor">\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n    <RootNamespace>Acme.Shop</RootNamespace>\n  </PropertyGroup>\n</Project>\n' > src/Shop/Shop.csproj
printf '@using Microsoft.AspNetCore.Components.Web\n' > src/Shop/_Imports.razor
run blazor-native.sh scaffold src/Shop
check "native scaffold: the RootNamespace, the Shared folder" 0 '^SCAFFOLD: src/Shop/Shared/Native \(namespace Acme\.Shop\.Shared\.Native, net8\.0\)$'
check "native scaffold: the @using in the _Imports.razor of the project" 0 '^IMPORTS: @using Acme\.Shop\.Shared\.Native added to src/Shop/_Imports\.razor$'
printf '<Project Sdk="Microsoft.NET.Sdk.Web">\n  <PropertyGroup>\n    <TargetFramework>net6.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/Old/Old.csproj
run blazor-native.sh scaffold src/Old
check "native scaffold: .NET 8 and later only" 1 '^STOP: the native components are written for \.NET 8 and later; src/Old/Old\.csproj targets net6\.0$'
rm -rf src/Shop src/Old
# the last step done: nothing left of Blazorise
sed -i '/Blazorise/d' src/Web/Web.csproj src/Web/Components/_Imports.razor src/Web/Components/App.razor
printf 'var builder = WebApplication.CreateBuilder(args);\n' > src/Web/Program.cs
printf '{ }\n' > src/Web/appsettings.json
printf '<NativeGrid Items="@orders"><NativeColumn Field="@(o => o.Number)" Title="Numéro" /></NativeGrid>\n@code {\n    private List<Order> orders = new();\n}\n' > src/Web/Components/Pages/Orders.razor
printf '@page "/edit"\n@inject NativeDialogService Dialogs\n<EditForm Model="this"><InputText @bind-Value="name" /></EditForm>\n' > src/Web/Components/Pages/Edit.razor
printf '<NativeModal @bind-Visible="shown"><Footer><button type="button">OK</button></Footer></NativeModal>\n' > src/Web/Components/Pages/Confirm.razor
printf '<span class="badge text-bg-primary">neuf</span>\n' > src/Web/Components/Pages/Draft.razor
printf '@inherits LayoutComponentBase\n<nav class="navbar"></nav>\n@Body\n<NativeDialogHost />\n<NativeToastHost />\n' > src/Web/Components/Layout/MainLayout.razor
run blazor-native.sh check
check "native check: nothing left, the Markdown documentation not looked at" 0 '^BLAZORISE: GONE ' '^LEFT: '
run blazor-native.sh inventory
check "native inventory: nothing left to replace" 0 '^INVENTORY: 0 \.razor file\(s\) use Blazorise \(0 tags in all\)$'
check "native inventory: no plan of pages" 0 '^PLAN: no \.razor file uses Blazorise'
cd "$work" || exit 1

# ---------- automapper.sh: the inventory of an application on AutoMapper, its mappers, its setup, what is left ----------
mkdir -p "$work/automapper"
cd "$work/automapper" || exit 1
git init -q
mkdir -p src/Shop/Mapping src/Shop/Billing src/Legacy src/Web tests/Shop.Tests/Mapping docs
cat > src/Shop/Shop.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="AutoMapper" />
  </ItemGroup>
</Project>
EOF
cat > src/Shop/Directory.Packages.props <<'EOF'
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="AutoMapper" Version="14.0.0" />
  </ItemGroup>
</Project>
EOF
cat > src/Legacy/Legacy.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="AutoMapper" Version="14.0.0" />
  </ItemGroup>
</Project>
EOF
cat > src/Shop/Mapping/OrderProfile.cs <<'EOF'
using AutoMapper;
using Shop.Domain;

namespace Shop.Mapping;

public class OrderProfile : Profile
{
    public OrderProfile()
    {
        // CreateMap<Ghost, GhostDto>() in a comment is no map
        CreateMap<Order, OrderDto>()
            .ForMember(d => d.Total, o => o.MapFrom(s => s.Lines.Sum(l => l.Amount)))
            .ForMember(d => d.Note, o => o.NullSubstitute("(aucun; vraiment)"))
            .ForMember(d => d.Discount, o => o.Condition(s => s.Paid))
            .BeforeMap((s, d) => d.Audit = "mappé")
            .AfterMap((s, d) => d.Summary = $"{d.Number}");
        CreateMap<Customer, CustomerDto>().ReverseMap();
        CreateMap(typeof(Page<>), typeof(PageDto<>));
    }
}
EOF
cat > src/Shop/Billing/InvoiceProfile.cs <<'EOF'
using AutoMapper;

namespace Billing;

public class InvoiceProfile : Profile
{
    public InvoiceProfile()
    {
        CreateMap<Money, string>().ConvertUsing<MoneyConverter>();
        CreateMap<Payment, PaymentDto>().Include<CardPayment, CardPaymentDto>();
        CreateMap<Invoice, InvoiceDto>().ForMember(d => d.Tax, o => o.MapFrom<TaxResolver>());
    }
}

public class TaxResolver(ITaxRates rates) : IValueResolver<Invoice, InvoiceDto, decimal>
{
    public decimal Resolve(Invoice s, InvoiceDto d, decimal m, ResolutionContext c) => s.Amount * rates.RateFor(s.Country);
}

public class MoneyConverter : ITypeConverter<Money, string>
{
    public string Convert(Money s, string d, ResolutionContext c) => s.ToString();
}
EOF
cat > src/Legacy/LegacyProfile.cs <<'EOF'
namespace Legacy
{
    public class LegacyProfile : AutoMapper.Profile
    {
        public LegacyProfile() { CreateMap<Row, RowDto>(); }
    }
}
EOF
cat > src/Shop/OrderService.cs <<'EOF'
using AutoMapper;
using AutoMapper.QueryableExtensions;

namespace Shop;

public class OrderService(IMapper mapper)
{
    public OrderDto Get(Order order) => mapper.Map<OrderDto>(order);
    public void Update(Order order, OrderUpdate update) => mapper.Map(update, order);
    public IQueryable<OrderDto> List(IQueryable<Order> q) => q.ProjectTo<OrderDto>(mapper.ConfigurationProvider);
}
EOF
cat > src/Shop/Startup.cs <<'EOF'
namespace Shop;

public static class Startup
{
    public static void Add(IServiceCollection services) =>
        services.AddAutoMapper(cfg => cfg.AllowNullCollections = true, typeof(Startup));
}
EOF
printf 'var app = WebApplication.Create(args);\napp.Map("/health", () => "ok");\n' > src/Web/Program.cs
cat > tests/Shop.Tests/Shop.Tests.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <RootNamespace>Acme.Shop.Tests</RootNamespace>
  </PropertyGroup>
  <!-- fake-test: Acme.Shop.Tests.Mapping.OrderMappingTests.Order_ToOrderDto env MAPPING_RECORD=1 No golden file: automapper.sh record -->
</Project>
EOF
cat > tests/Shop.Tests/OrderServiceTests.cs <<'EOF'
public class OrderServiceTests
{
    private readonly Mock<IMapper> mapper = new();
    [Fact] public void Valid() => new MapperConfiguration(c => c.AddProfile<OrderProfile>()).AssertConfigurationIsValid();
}
EOF
printf '# Notes\nAutoMapper leaves: CreateMap<Order, OrderDto>, IMapper.\n' > docs/notes.md
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
# shellcheck disable=SC2034 # read in the eval of truth
before=$(git status --porcelain)
run automapper.sh inventory
check "mapperly inventory: the files with maps, the maps, the version" 0 '^INVENTORY: 3 file\(s\) with maps, 7 map\(s\), AutoMapper 14\.0\.0$'
check "mapperly inventory: each package once, with its version" 0 '^PACKAGE: AutoMapper 14\.0\.0$'
check "mapperly inventory: the CVE of a free version" 0 '^PACKAGE: AutoMapper 14\.0\.0: a free version, with CVE-2026-32933'
check "mapperly inventory: the simplest profile first" 0 '^PROFILE: src/Legacy/LegacyProfile\.cs — LegacyProfile — 1 map\(s\) — step 1$'
check "mapperly inventory: the profile with its BeforeMap and AfterMap after it" 0 '^PROFILE: src/Shop/Mapping/OrderProfile\.cs — OrderProfile — 3 map\(s\), 3 option\(s\) beyond an attribute per member — step 2$'
check "mapperly inventory: a map, its line and its options (never a map in a comment, a ; in a string kept in it)" 0 '^MAP: src/Shop/Mapping/OrderProfile\.cs:11 Order -> OrderDto — ForMember×3, MapFrom, BeforeMap, AfterMap, Condition, NullSubstitute$' 'Ghost'
check "mapperly inventory: an open generic" 0 '^MAP: src/Shop/Mapping/OrderProfile\.cs:18 Page<> -> PageDto<>$'
check "mapperly inventory: a resolver with its options" 0 '^MAP: src/Shop/Billing/InvoiceProfile\.cs:[0-9]+ Invoice -> InvoiceDto — ForMember, MapFrom, a resolver/converter/action class$'
check "mapperly inventory: the projects where Mapperly goes" 0 '^PROJECTS: src/Legacy/Legacy\.csproj src/Shop/Shop\.csproj \(Riok\.Mapperly to add'
check "mapperly inventory: a resolver that takes a service" 0 '^CONVERTER: src/Shop/Billing/InvoiceProfile\.cs:[0-9]+ TaxResolver \(IValueResolver<Invoice, InvoiceDto, decimal>\) — takes services'
check "mapperly inventory: a converter without service" 0 '^CONVERTER: src/Shop/Billing/InvoiceProfile\.cs:[0-9]+ MoneyConverter \(ITypeConverter<Money, string>\)$'
check "mapperly inventory: a global setting" 0 '^GLOBAL: src/Shop/Startup\.cs:6 .*AllowNullCollections'
check "mapperly inventory: the calls" 0 '^CALL: src/Shop/OrderService\.cs:9 Map\(source, destination\) '
check "mapperly inventory: the projection" 0 '^CALL: src/Shop/OrderService\.cs:10 ProjectTo '
check "mapperly inventory: IMapper injected" 0 '^CALL: src/Shop/OrderService\.cs:6 IMapper injected'
check "mapperly inventory: a test double of IMapper" 0 '^CALL: tests/Shop\.Tests/OrderServiceTests\.cs:3 a test double of IMapper'
check "mapperly inventory: never the Map of a minimal API" 0 . 'src/Web/Program\.cs'
check "mapperly inventory: the registration" 0 '^REGISTRATION: src/Shop/Startup\.cs:6 services\.AddAutoMapper'
check "mapperly inventory: the tests of AutoMapper" 0 '^TEST: tests/Shop\.Tests/OrderServiceTests\.cs:4 .*AssertConfigurationIsValid'
check "mapperly inventory: what scaffold leaves by hand, for each target" 0 '^TRANSLATED: automapper\.sh scaffold translates each map, for Mapperly or for Mapster; by hand \(a TODO line\): a resolver/converter/action class, an open generic \(Mapperly\), a resolver/converter/action class \(Mapster\)$'
check "mapperly inventory: the facts of Mapperly" 0 '^TARGET: Mapperly \(recommended: .*\): 2 call\(s\) of IMapper and 1 ProjectTo rewritten into calls of the mappers, 1 constructor\(s\) without IMapper, 1 test double\(s\) of IMapper rewritten; 3 BeforeMap, AfterMap or Condition into methods written by scaffold; 1 resolver\(s\) with services into an instance mapper; 0 map\(s\) of runtime types and 0 use\(s\) of Items'
check "mapperly inventory: the facts of Mapster" 0 '^TARGET: Mapster \(the closest to AutoMapper: .*\): the 2 call\(s\), the 1 constructor\(s\) and the 1 test double\(s\) unchanged .*; 0 use\(s\) of Items or of the mapper inside a map and 1 global setting\(s\)'
check "mapperly inventory: the plan" 0 "^PLAN: the developer's answer first \\(« Cible » : Mapperly, Mapster or by hand; then automapper\\.sh setup \\[--mapster\\]"
truth "mapperly inventory: reads only" '[ "$(git status --porcelain)" = "$before" ]'
run automapper.sh inventory src/Legacy
check "mapperly inventory of a folder" 0 '^INVENTORY: 1 file\(s\) with maps, 1 map\(s\)'
run automapper.sh check
check "mapperly check: what is left, exit 1" 1 '^AUTOMAPPER: [0-9]+ place\(s\) left$'
check "mapperly check: the package, the usings, the maps, the configuration, IMapper, the resolvers" 1 '^LEFT: project: src/Legacy/Legacy\.csproj:[0-9]+:.*AutoMapper'
check "mapperly check: a resolver" 1 '^LEFT: type: src/Shop/Billing/InvoiceProfile\.cs:[0-9]+:.*IValueResolver<'
check "mapperly check: a using once" 1 '^LEFT: using: src/Shop/OrderService\.cs:2:using AutoMapper\.QueryableExtensions;$' '^LEFT: type: src/Shop/OrderService\.cs:2:'
check "mapperly check: never the Markdown documentation, never a minimal API" 1 . 'docs/notes\.md|src/Web/Program\.cs'
run automapper.sh frob
check "mapperly: an unknown action" 1 '^STOP: automapper\.sh inventory'
run automapper.sh scaffold
check "mapperly scaffold: the profile is needed" 1 '^STOP: automapper\.sh scaffold \[--mapster\] <the \.cs file of a profile>$'
run automapper.sh scaffold src/Shop/OrderService.cs
check "mapperly scaffold: a file without map" 1 '^STOP: no CreateMap in src/Shop/OrderService\.cs$'
run automapper.sh scaffold src/Shop/Mapping/OrderProfile.cs
check "mapperly scaffold: a static mapper next to the profile" 0 '^SCAFFOLD: src/Shop/Mapping/OrderMapper\.cs \(OrderMapper, namespace Shop\.Mapping\) from OrderProfile, 3 map\(s\)$'
check "mapperly scaffold: a method per map, the way back of ReverseMap" 0 '^METHOD: ToCustomer CustomerDto$'
truth "mapperly scaffold: the static partial class, BeforeMap, Condition and AfterMap around the generated method" 'grep -q "^public static partial class OrderMapper$" src/Shop/Mapping/OrderMapper.cs && grep -q "^    public static OrderDto ToOrderDto(this Order source)$" src/Shop/Mapping/OrderMapper.cs && grep -q "^        MapOrderToOrderDto(source, target);$" src/Shop/Mapping/OrderMapper.cs && grep -q "if (s.Paid) { target.Discount = source.Discount; }" src/Shop/Mapping/OrderMapper.cs && grep -q "^    private static partial void MapOrderToOrderDto(Order source, OrderDto target);$" src/Shop/Mapping/OrderMapper.cs'
truth "mapperly scaffold: a map not translated whole quoted above its code, its TODO lines" 'grep -q "^    // AutoMapper (to finish: its TODO lines):$" src/Shop/Mapping/OrderMapper.cs && grep -q "^    //   .BeforeMap((s, d) => d.Audit = \"mappé\")$" src/Shop/Mapping/OrderMapper.cs && grep -q "TODO: ProjectTo<OrderDto> of a map with code around its method" src/Shop/Mapping/OrderMapper.cs'
truth "mapperly scaffold: NullSubstitute in a helper, a ; in its string kept" 'grep -q "NoteOrDefault(object /\* TODO: its type \*/ value) => value ?? \"(aucun; vraiment)\";" src/Shop/Mapping/OrderMapper.cs'
truth "mapperly scaffold: an open generic left to write by hand" 'grep -q "TODO: an open generic" src/Shop/Mapping/OrderMapper.cs'
truth "mapperly scaffold: the usings of the profile, never AutoMapper" 'grep -q "^using Shop.Domain;$" src/Shop/Mapping/OrderMapper.cs && ! grep -q "^using AutoMapper" src/Shop/Mapping/OrderMapper.cs'
printf '// mine\n' >> src/Shop/Mapping/OrderMapper.cs
run automapper.sh scaffold src/Shop/Mapping/OrderProfile.cs
check "mapperly scaffold again: the mapper kept" 0 '^KEPT: src/Shop/Mapping/OrderMapper\.cs \(exists: the application owns it\)$'
truth "mapperly scaffold again: the changes of the application kept" 'tail -n 1 src/Shop/Mapping/OrderMapper.cs | grep -q "// mine"'
(cd src/Shop && "$SHELL_UNDER_TEST" "$scripts/automapper.sh" scaffold Billing/InvoiceProfile.cs) > "$work/scaffold.out" 2>&1
out=$(cat "$work/scaffold.out") status=0
check "mapperly scaffold from a folder of the project: an instance mapper, the service of its resolver" 0 '^SCAFFOLD: src/Shop/Billing/InvoiceMapper\.cs \(InvoiceMapper, namespace Billing\) from InvoiceProfile, 3 map\(s\); an instance mapper: its resolvers take ITaxRates rates$'
check "mapperly scaffold: a conversion of a type pair" 0 '^METHOD: MoneyToString Money$'
check "mapperly scaffold: registered in place of AddAutoMapper" 0 '^NEXT: .*the mapper registered in place of AddAutoMapper'
truth "mapperly scaffold: the instance class, its methods, the conversion left to write" 'grep -q "^public partial class InvoiceMapper(ITaxRates rates)$" src/Shop/Billing/InvoiceMapper.cs && grep -q "^    public partial InvoiceDto ToInvoiceDto(Invoice source);$" src/Shop/Billing/InvoiceMapper.cs && grep -q "TODO: ConvertUsing<MoneyConverter>: the code of its Convert in a \[UserMapping(Default = true)\] method of the mapper, Money to string" src/Shop/Billing/InvoiceMapper.cs'
run automapper.sh scaffold src/Legacy/LegacyProfile.cs
check "mapperly scaffold: a profile in a block namespace" 0 '^SCAFFOLD: src/Legacy/LegacyMapper\.cs \(LegacyMapper, namespace Legacy\) from LegacyProfile, 1 map\(s\)$'
rm -f src/Shop/Mapping/OrderMapper.cs src/Shop/Billing/InvoiceMapper.cs src/Legacy/LegacyMapper.cs
# the Registers of Mapster
run automapper.sh scaffold --mapster src/Shop/Mapping/OrderProfile.cs
check "mapster scaffold: the Register next to the profile" 0 '^SCAFFOLD: src/Shop/Mapping/OrderRegister\.cs \(OrderRegister, namespace Shop\.Mapping\) from OrderProfile, 3 map\(s\), for Mapster$'
check "mapster scaffold: what is left by hand (NullSubstitute of a member whose type is not declared)" 0 '^NEXT: 1 TODO line\(s\) to finish \(the skill mapster\)'
truth "mapster scaffold: an IRegister, Condition into IgnoreIf, BeforeMapping, AfterMapping, the open generic, the way back unflattened" 'grep -q "^public class OrderRegister : IRegister$" src/Shop/Mapping/OrderRegister.cs && grep -q "^using Mapster;$" src/Shop/Mapping/OrderRegister.cs && ! grep -q "^using AutoMapper" src/Shop/Mapping/OrderRegister.cs && grep -q "\.IgnoreIf((s, _) => !(s.Paid), d => d.Discount)$" src/Shop/Mapping/OrderRegister.cs && grep -q "\.BeforeMapping((s, d) => d.Audit = \"mappé\")$" src/Shop/Mapping/OrderRegister.cs && grep -q "\.AfterMapping((s, d) => d.Summary = \$\"{d.Number}\")$" src/Shop/Mapping/OrderRegister.cs && grep -q "config.NewConfig(typeof(Page<>), typeof(PageDto<>));" src/Shop/Mapping/OrderRegister.cs && grep -q "\.Unflattening(true)$" src/Shop/Mapping/OrderRegister.cs'
run automapper.sh scaffold --mapster src/Shop/Mapping/OrderProfile.cs
check "mapster scaffold again: the Register kept" 0 '^KEPT: src/Shop/Mapping/OrderRegister\.cs \(exists: the application owns it\)$'
run automapper.sh scaffold --mapster src/Shop/Billing/InvoiceProfile.cs
check "mapster scaffold: the converter and the resolver classes left by hand" 0 '^NEXT: 2 TODO line\(s\) to finish \(the skill mapster\)'
truth "mapster scaffold: Include" 'grep -q "\.Include<CardPayment, CardPaymentDto>()$" src/Shop/Billing/InvoiceRegister.cs'
rm -f src/Shop/Mapping/OrderRegister.cs src/Shop/Billing/InvoiceRegister.cs
# the helpers of the snapshot tests
run automapper.sh helpers
check "mapperly helpers: the test project is needed" 1 '^STOP: automapper\.sh helpers <the test project \.csproj>$'
run automapper.sh helpers tests/Shop.Tests/Shop.Tests.csproj
check "mapperly helpers: written, the namespace of the test project" 0 '^HELPERS: tests/Shop\.Tests/Mapping/MappingSnapshot\.cs, namespace Acme\.Shop\.Tests\.Mapping: '
truth "mapperly helpers: MappingSample and MappingSnapshot, no placeholder left" 'grep -q "^namespace Acme.Shop.Tests.Mapping;$" tests/Shop.Tests/Mapping/MappingSnapshot.cs && grep -q "public static class MappingSample$" tests/Shop.Tests/Mapping/MappingSnapshot.cs && grep -q "public static class MappingSnapshot$" tests/Shop.Tests/Mapping/MappingSnapshot.cs && ! grep -q "__NAMESPACE__" tests/Shop.Tests/Mapping/MappingSnapshot.cs'
run automapper.sh helpers tests/Shop.Tests/Shop.Tests.csproj
check "mapperly helpers again: kept" 0 '^KEPT: tests/Shop\.Tests/Mapping/MappingSnapshot\.cs '
# record: the snapshot tests run with MAPPING_RECORD=1 (the fake test passes only so)
run automapper.sh record tests/Shop.Tests/Shop.Tests.csproj
check "mapperly record: the tests run with MAPPING_RECORD=1" 0 '^RECORD: 0 golden file\(s\) written from AutoMapper \(FullyQualifiedName~Mapping\)'
called "mapperly record: the tests of the filter" 'dotnet test .*Shop\.Tests\.csproj.*FullyQualifiedName~Mapping'
run build-test.sh tests/Shop.Tests/Shop.Tests.csproj --filter FullyQualifiedName~Mapping
check "without MAPPING_RECORD, the same test fails" 1 'No golden file'
sed -i 's/env MAPPING_RECORD=1 No golden file/fail No golden file/' tests/Shop.Tests/Shop.Tests.csproj
run automapper.sh record tests/Shop.Tests/Shop.Tests.csproj
check "mapperly record: tests that fail, nothing recorded" 1 '^STOP: the snapshot tests do not pass on AutoMapper: nothing recorded$'
git checkout -q -- tests/Shop.Tests/Shop.Tests.csproj
mkdir -p tests/Shop.Tests/Mapping/Snapshots
printf '{\n  "$type": "OrderDto"\n}\n' > tests/Shop.Tests/Mapping/Snapshots/OrderDto.json
git add -A && git commit -q -m "test: the snapshot tests"
printf '{\n  "$type": "Other"\n}\n' > tests/Shop.Tests/Mapping/Snapshots/OrderDto.json
run automapper.sh record tests/Shop.Tests/Shop.Tests.csproj
check "mapperly record: a committed golden file edited, STOP before any run" 1 '^STOP: golden files committed and changed since \(tests/Shop\.Tests/Mapping/Snapshots/OrderDto\.json\): the contract of the maps is the committed version'
called "mapperly record: no test run then" '^$' 'dotnet test'
truth "mapperly record: the edit left to the one who made it" 'grep -q Other tests/Shop.Tests/Mapping/Snapshots/OrderDto.json'
git reset -q --hard HEAD~1
rm -rf tests/Shop.Tests/Mapping
# setup: a build that fails puts every file back; central versions; C# 9 for netstandard; once
run automapper.sh setup
check "mapperly setup: the project is needed" 1 '^STOP: automapper\.sh setup \[--mapster\] <the project of the profiles'
printf '<Project ToolsVersion="15.0">\n</Project>\n' > src/Legacy/Old.csproj
run automapper.sh setup src/Legacy/Old.csproj
check "mapperly setup: never an old-style project" 1 '^STOP: src/Legacy/Old\.csproj is not an SDK-style project'
rm -f src/Legacy/Old.csproj
printf '// <!-- fake-build-error -->\n' > src/Legacy/Broken.cs
run automapper.sh setup src/Legacy
check "mapperly setup: a build that fails" 1 '^STOP: the build of src/Legacy/Legacy\.csproj fails with Riok\.Mapperly 4\.3\.1: every file put back, nothing changed$'
rm -f src/Legacy/Broken.cs
truth "mapperly setup that fails: every file as it was" '[ "$(git status --porcelain)" = "$before" ]'
# Mapster: an older Microsoft.Extensions.DependencyInjection.Abstractions, a build that fails, central versions, once
run automapper.sh switch
check "mapster switch: setup first" 1 '^STOP: no MapsterSetup\.cs: automapper\.sh setup --mapster'
sed -i 's#<PackageReference Include="AutoMapper" Version="14.0.0" />#&\n    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="8.0.2" />#' src/Legacy/Legacy.csproj
run automapper.sh setup --mapster src/Shop
check "mapster setup: an older DependencyInjection.Abstractions referenced: STOP" 1 '^STOP: Mapster\.DependencyInjection 10\.0\.13 needs Microsoft\.Extensions\.DependencyInjection\.Abstractions 9\.0\.0 or more .*src/Legacy/Legacy\.csproj:[0-9]+'
git checkout -q -- src/Legacy/Legacy.csproj
printf '// <!-- fake-build-error -->\n' > src/Shop/Broken.cs
run automapper.sh setup --mapster src/Shop
check "mapster setup: a build that fails" 1 '^STOP: the build of src/Shop/Shop\.csproj fails with Mapster 10\.0\.13: every file put back, nothing changed$'
rm -f src/Shop/Broken.cs
truth "mapster setup that fails: every file as it was, no MapsterSetup.cs" '[ "$(git status --porcelain)" = "$before" ] && [ ! -e src/Shop/MapsterSetup.cs ]'
run automapper.sh setup --mapster src/Shop
check "mapster setup: the versions in Directory.Packages.props, MapsterSetup.cs" 0 '^SETUP: Mapster 10\.0\.13 and Mapster\.DependencyInjection 10\.0\.13 added to src/Shop/Shop\.csproj \(their version in src/Shop/Directory\.Packages\.props\); src/Shop/MapsterSetup\.cs written .*; build OK$'
truth "mapster setup: the references without version, their versions central, the rules of AutoMapper, a null list kept null (AllowNullCollections)" 'grep -q "<PackageReference Include=\"Mapster\" />" src/Shop/Shop.csproj && grep -q "<PackageReference Include=\"Mapster.DependencyInjection\" />" src/Shop/Shop.csproj && grep -q "<PackageVersion Include=\"Mapster.DependencyInjection\" Version=\"10.0.13\" />" src/Shop/Directory.Packages.props && grep -q "^namespace Shop;$" src/Shop/MapsterSetup.cs && grep -q "NameMatchingStrategy(NameMatchingStrategy.IgnoreCase)" src/Shop/MapsterSetup.cs && grep -q "EnumMappingStrategy(EnumMappingStrategy.ByName);$" src/Shop/MapsterSetup.cs && ! grep -q EmptyCollectionIfNull src/Shop/MapsterSetup.cs && grep -q "a null list left null (AllowNullCollections = true)" src/Shop/MapsterSetup.cs'
run automapper.sh setup --mapster src/Shop
check "mapster setup again: nothing added" 0 '^SETUP: Mapster already in src/Shop/Shop\.csproj; src/Shop/MapsterSetup\.cs kept; build OK$'
truth "mapster setup again: one PackageReference each" '[ "$(grep -c "Include=\"Mapster\"" src/Shop/Shop.csproj)" -eq 1 ] && [ "$(grep -c "Include=\"Mapster.DependencyInjection\"" src/Shop/Shop.csproj)" -eq 1 ]'
# switch: the code onto Mapster, the profiles and resolvers left out, the rest listed
run automapper.sh scaffold --mapster src/Shop/Mapping/OrderProfile.cs
run automapper.sh switch
check "mapster switch: the service" 0 '^SWITCHED: src/Shop/OrderService\.cs — 3 line\(s\)$'
check "mapster switch: the test of the configuration" 0 '^SWITCHED: tests/Shop\.Tests/OrderServiceTests\.cs — 2 line\(s\)$'
check "mapster switch: a registration with a setting, left by hand" 0 '^LEFT: src/Shop/Startup\.cs:6 services\.AddAutoMapper\(cfg => cfg\.AllowNullCollections = true, typeof\(Startup\)\);$'
check "mapster switch: the summary" 0 '^SWITCH: 2 file\(s\) rewritten .*, 1 line\(s\) left by hand .*, 3 profile or resolver file\(s\) left out'
truth "mapster switch: the usings, ProjectToType, the strict configuration of the test, its usings" 'grep -q "^using MapsterMapper;$" src/Shop/OrderService.cs && grep -q "^using Mapster;$" src/Shop/OrderService.cs && grep -q "q.ProjectToType<OrderDto>(mapper.Config);" src/Shop/OrderService.cs && grep -q "mapper.Map(update, order);" src/Shop/OrderService.cs && grep -q "=> MapsterSetup.Configure(new TypeAdapterConfig(), true, typeof(OrderRegister).Assembly).Compile(failFast: false);" tests/Shop.Tests/OrderServiceTests.cs && head -n 2 tests/Shop.Tests/OrderServiceTests.cs | grep -q "^using Shop;$" && grep -q "Mock<IMapper>" tests/Shop.Tests/OrderServiceTests.cs'
truth "mapster switch: the profiles as they were" 'git diff --quiet -- src/Shop/Mapping/OrderProfile.cs src/Shop/Billing/InvoiceProfile.cs src/Legacy/LegacyProfile.cs'
run automapper.sh switch
check "mapster switch again: nothing to rewrite" 0 '^SWITCH: 0 file\(s\) rewritten'
git checkout -q -- . && git clean -q -f -d src tests
truth "mapster: every file as it was before the next stories" '[ "$(git status --porcelain)" = "$before" ]'
run automapper.sh setup src/Legacy
check "mapperly setup: the version in the project, compile time only, C# 9 for netstandard2.0" 0 '^SETUP: Riok\.Mapperly 4\.3\.1 added to src/Legacy/Legacy\.csproj, compile time only \(ExcludeAssets runtime, PrivateAssets all\); LangVersion latest \(Mapperly needs C# 9, the default of netstandard2\.0 is older\); .*; build OK$'
truth "mapperly setup: the PackageReference, the LangVersion, the diagnostics, the rules" 'grep -q "<PackageReference Include=\"Riok.Mapperly\" Version=\"4.3.1\" ExcludeAssets=\"runtime\" PrivateAssets=\"all\" />" src/Legacy/Legacy.csproj && grep -q "<LangVersion>latest</LangVersion>" src/Legacy/Legacy.csproj && grep -q "<GlobalAnalyzerConfigFiles Include=\"Mapperly.globalconfig\" />" src/Legacy/Legacy.csproj && grep -q "^dotnet_diagnostic.RMG012.severity = error$" src/Legacy/Mapperly.globalconfig && grep -q "^is_global = true$" src/Legacy/Mapperly.globalconfig && grep -q "AutoUserMappings = false" src/Legacy/MapperDefaults.cs'
run automapper.sh setup src/Shop/Shop.csproj
check "mapperly setup: the version in Directory.Packages.props" 0 '^SETUP: Riok\.Mapperly 4\.3\.1 added to src/Shop/Shop\.csproj \(its version in src/Shop/Directory\.Packages\.props\), compile time only'
truth "mapperly setup: no version in the project, its PackageVersion beside the others, no LangVersion for net10.0" 'grep -q "<PackageReference Include=\"Riok.Mapperly\" ExcludeAssets=\"runtime\" PrivateAssets=\"all\" />" src/Shop/Shop.csproj && grep -q "^    <PackageVersion Include=\"Riok.Mapperly\" Version=\"4.3.1\" />$" src/Shop/Directory.Packages.props && ! grep -q LangVersion src/Shop/Shop.csproj'
run automapper.sh setup src/Shop
check "mapperly setup again: nothing added" 0 '^SETUP: Riok\.Mapperly already in src/Shop/Shop\.csproj; .*, kept as they were; build OK$'
truth "mapperly setup again: one PackageReference, one item of the diagnostics" '[ "$(grep -c Riok.Mapperly src/Shop/Shop.csproj)" -eq 1 ] && [ "$(grep -c Mapperly.globalconfig src/Shop/Shop.csproj)" -eq 1 ]'
run automapper.sh inventory
check "mapperly inventory after setup: Mapperly there" 0 '^PACKAGE: Riok\.Mapperly already in src/Legacy/Legacy\.csproj src/Shop/Shop\.csproj$'
check "mapperly inventory after setup: no project left to set up" 0 '^PROJECTS: src/Legacy/Legacy\.csproj src/Shop/Shop\.csproj \(Mapperly already set up\)$'
# the last step done: nothing left of AutoMapper
rm -f src/Shop/Mapping/OrderProfile.cs src/Shop/Billing/InvoiceProfile.cs src/Legacy/LegacyProfile.cs tests/Shop.Tests/OrderServiceTests.cs
sed -i '/Include="AutoMapper"/d' src/Shop/Shop.csproj src/Legacy/Legacy.csproj src/Shop/Directory.Packages.props
printf 'namespace Shop;\n\npublic class OrderService\n{\n    public OrderDto Get(Order order) => order.ToOrderDto();\n}\n' > src/Shop/OrderService.cs
printf 'namespace Shop;\n\npublic static class Startup\n{\n    public static void Add(IServiceCollection services) => services.AddScoped<InvoiceMapper>();\n}\n' > src/Shop/Startup.cs
run automapper.sh check
check "mapperly check: nothing left, the Markdown documentation not looked at" 0 '^AUTOMAPPER: GONE ' '^LEFT: '
run automapper.sh inventory
check "mapperly inventory: nothing left to replace" 0 '^PLAN: no map of AutoMapper'
cd "$work" || exit 1

# never dotnet run, in any of these runs
truth "never dotnet run" '! grep -q "^dotnet run" "$work/all-calls.log"'
truth "no output file left in the temporary folder" '[ -z "$(ls "$TMPDIR")" ]'

echo "dotnet-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
