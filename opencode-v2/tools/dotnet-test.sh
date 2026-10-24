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
git reset -q --hard HEAD~1

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

# never dotnet run, in any of these runs
truth "never dotnet run" '! grep -q "^dotnet run" "$work/all-calls.log"'
truth "no output file left in the temporary folder" '[ -z "$(ls "$TMPDIR")" ]'

echo "dotnet-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
