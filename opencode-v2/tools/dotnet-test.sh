#!/bin/sh
# Tests of the pack's .NET scripts (build-test.sh, test-platform.sh, test-guardian.sh, fortify.sh prereq) with a fake
# dotnet (tools/fake-dotnet.sh): VSTest, Microsoft.Testing.Platform (xUnit v3, MSTest.Sdk, TUnit), a solution that mixes
# them, and a project that dotnet test of the .NET 10 SDK refuses. No .NET SDK needed; the real one is tried by the
# first run on a developer's machine. Usage, from opencode-v2/: sh tools/dotnet-test.sh [<shell>] (default sh).
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
called "mixed: xUnit v3 as its application, the suite limit" '^dotnet exec .*/Core.Tests.dll --timeout 18m$' '^dotnet run'
called "mixed: MSTest.Sdk as its application" '^dotnet exec .*/Core.MsTests.dll --timeout 18m$'
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
git rm -q Directory.Packages.props && git commit -q -m central

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
check "related-repos: the other repository, next to this one" 0 "^RELATED: api-factures — $work/apps/api-factures \(branch feature/ABC-123-export-csv\): l'API \.NET des factures"
check "related-repos: its branch and its delivery for the ticket" 0 '^  ABC-123 there: branch feature/ABC-123-export-csv, sheet .*ABC-123\.md; 2026-10-21 16:30 — /go - livré - MR https://gitlab\.example\.com/g/api/-/merge_requests/42'
check "related-repos: its contract" 0 '^    - GET /api/invoices/export\?from=&to= : text/csv'
check "related-repos: a repository not on this machine says how to give its path" 0 "^RELATED: lib-commun — not found at $HOME/nowhere/lib-commun: give its path"
run related-repos.sh
check "related-repos: without a key, where they are" 0 '^RELATED: api-factures — ' '^  ABC-123'
cd "$work/apps/api-factures" || exit 1
run related-repos.sh ABC-123
check "related-repos: a repository without the section" 0 '^RELATED: none \(no AGENTS\.md'
run detect-project-type.sh
cd "$work/apps/front-factures" || exit 1
run detect-project-type.sh
check "detect-project-type: the related repositories" any '^Related repositories \(AGENTS\.md\): api-factures, lib-commun \(~/nowhere/lib-commun\) — sh ~/.config/opencode/scripts/related-repos\.sh <KEY>'

# never dotnet run, in any of these runs
truth "never dotnet run" '! grep -q "^dotnet run" "$work/all-calls.log"'
truth "no output file left in the temporary folder" '[ -z "$(ls "$TMPDIR")" ]'

echo "dotnet-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
