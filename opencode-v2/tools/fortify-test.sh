#!/bin/sh
# shellcheck disable=SC2034 # variables read inside the eval of truth
# The flow of /fortify and of its test-guardian, from A to Z, played at the level of the scripts that
# commands/fortify.md prescribes, with the exact command lines of its steps, in their order: the prerequisites (and the
# set-up of the unit tests), the start conditions, the batch branch and its sheet, the measure of develop, the cards,
# the proofs of a wave written in parallel (and their builds waiting on the folder lock), a red for the right reason, a
# test that passes already (the code resists), a flaky test, a test that hangs, a test file of another test-guardian
# that does not compile yet, the proofs parked, a vulnerability closed by the fix of another, the fix, a coder that
# changes the sealed tests, a lost coverage, a vulnerability that no unit test can show, a vulnerability given up and
# put aside, the resumes after an interruption (each case of step 1), the final suite with the coverage of the changes,
# the check before the push, the push; a second batch in a worktree at the same time, and the same flow on a
# Microsoft.Testing.Platform project (MSTest.Sdk). GitLab is a bare repository; the part of the model (the cards, the
# tests, the fixes) is played with fixed answers: real C# code and real tests. Each step checks what the pilot reads and
# what git holds.
#   --real   with the dotnet of this machine: real builds, real xUnit and MSTest tests, real coverage (coverlet and the
#            coverage extension of the platform), NuGet packages from the feed of this machine (about 10 minutes). Run
#            it on the machine of OpenCode. Everything happens in a temporary folder: no repository, no git or NuGet
#            setting of this machine is changed.
#   (none)   with tools/fake-dotnet.sh, for a machine without the .NET SDK: the scripts and the flow, not the compiler
#            (the test files carry, in comments, what the fake runs: the same results as their real code)
# Usage, from opencode-v2/: sh tools/fortify-test.sh [--real] [<shell>] (default sh; dash and bash).
REAL=0
[ "$1" = --real ] && { REAL=1; shift; }
SHELL_UNDER_TEST=${1:-sh}
SH=$SHELL_UNDER_TEST
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
work=$(mktemp -d "${TMPDIR:-/tmp}/fortify-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state" "$work/tmp" "$work/nodotnet"
FAKE_DOTNET_LOG="$work/dotnet.log"
if [ "$REAL" -eq 1 ]; then
  real_dotnet=$(command -v dotnet) || { echo "fortify-test --real: dotnet is not on the PATH of this machine"; exit 2; }
  # every call logged (never dotnet run), then the real one
  printf '#!/bin/sh\nprintf "dotnet %%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$FAKE_DOTNET_LOG" "$real_dotnet" > "$work/bin/dotnet"
  TFM="net$(dotnet --version | cut -d. -f1).0"
  # the NuGet settings and cache of this machine stay those of its user; the build servers do not outlive the run
  MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
  export MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO
  # a test that hangs is stopped after 30 s here (5 minutes in a real run of the pack)
  HANG_TIME=30s
  echo "fortify-test --real: $(dotnet --version) ($TFM), in $work"
else
  HOME="$work/home"
  mkdir -p "$HOME"
  export HOME
  cp "$pack/tools/fake-dotnet.sh" "$work/bin/dotnet"
  TFM=net10.0
  HANG_TIME=5m
fi
chmod +x "$work/bin/dotnet"
PATH="$work/bin:$PATH"
FAKE_DOTNET_STATE="$work/state"
FAKE_DOTNET_COVER="$work/cover.txt"
TMPDIR="$work/tmp"
export PATH FAKE_DOTNET_LOG FAKE_DOTNET_STATE FAKE_DOTNET_COVER TMPDIR
# git: a global configuration of its own (git 2.32 and later), never the one of this machine (its hooks, a signing of
# the commits), which is never written either
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
printf '[init]\n\tdefaultBranch = develop\n[advice]\n\tdetachedHead = false\n' > "$GIT_CONFIG_GLOBAL"
# a repository standing for GitLab, and its clone on develop
gitlab() {
  git init -q --bare "$1.git"
  git --git-dir="$1.git" symbolic-ref HEAD refs/heads/develop
  git clone -q "$1.git" "$1" 2>/dev/null
  git -C "$1" checkout -q -b develop 2>/dev/null
}
# the tools of this machine without dotnet, for the case where it is missing
for f in /usr/local/bin/* /usr/bin/* /bin/*; do
  n=$(basename "$f")
  [ "$n" = dotnet ] || [ -e "$work/nodotnet/$n" ] || ln -s "$f" "$work/nodotnet/$n" 2>/dev/null
done

pass=0
fail=0
scenario=""
step() {
  scenario=$1
  [ "$REAL" -eq 1 ] && echo "== $scenario"
}
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
    echo "FAIL: [$scenario] $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}
truth() {
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: [$scenario] $1 ($2)"; fi
}
# pick <with the fake> <with the real dotnet>: a figure that only the real tools decide (coverage, a version)
pick() { if [ "$REAL" -eq 1 ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
# run <script> <arguments>: a script of the pack, as the pilot or a subagent runs it
run() {
  script=$1
  shift
  out=$("$SH" "$scripts/$script" "$@" 2>&1)
  status=$?
}
# chain "<script> <args>" "<script> <args>"…: one shell call of the pilot, its commands joined by &&
chain() {
  out=$(for c in "$@"; do printf '%s\n' "$c"; done | run_chain 2>&1)
  status=$(cat "$work/chain.s")
}
run_chain() {
  st=0
  while IFS= read -r c; do
    # the command line of the pilot, its quotes as it writes them; never the rest of the chain on its input
    eval "\"\$SH\" \"\$scripts/\"$c" </dev/null || { st=1; break; }
  done
  echo "$st" > "$work/chain.s"
}
# bg <name> <commands>: a subagent working at the same time as others (its output and status kept in files)
bg() {
  n=$1
  shift
  ( "$@" > "$work/$n" 2>&1; echo $? > "$work/$n.s" ) &
}
got() { out=$(cat "$work/$1"); status=$(cat "$work/$1.s"); }
# cover "<file> <line>:<hits>…"…: with the fake, the coverage the next runs measure; the real tools measure their own
cover() { for l in "$@"; do printf '<!-- fake-cover: %s -->\n' "$l"; done > "$FAKE_DOTNET_COVER"; }
on_origin() { git --git-dir="$1" rev-parse -q --verify "refs/heads/$2" >/dev/null; }
# put <file>: a test file written at once (a build of another test-guardian never reads half of it)
put() { cat > "$1.part" && mv "$1.part" "$1"; }
clean() { [ -z "$(git status --porcelain)" ]; }
# the card of a vulnerability, as the analyst writes it (commands/fortify.md step 4)
card() {
  # card <batch folder> <V> <category> <file:line> <verdict> <context files> <tests>
  { echo "# $2 - $3"
    echo "## Faille"; echo "$3 dans $4."
    echo "## Verdict"; echo "$5"
    echo "## Correction"; echo "La plus petite correction de fortify-remediation."
    echo "## Contexte"; echo "Fichiers : $6"
    echo "## Tests"; echo "$7"
    echo "## État"; } > "$1/$2.md"
}
etat() { echo "$3" >> "$1/$2.md"; }
# a C# project (the fake reads none of it)
csproj() {
  # csproj <file> <sdk> <lines of an ItemGroup>...
  f=$1 sdk=$2
  shift 2
  mkdir -p "$(dirname "$f")"
  { echo "<Project Sdk=\"$sdk\">"
    echo "  <PropertyGroup>"
    echo "    <TargetFramework>$TFM</TargetFramework>"
    echo "    <Nullable>enable</Nullable>"
    echo "    <ImplicitUsings>enable</ImplicitUsings>"
    echo "    <IsPackable>false</IsPackable>"
    echo "  </PropertyGroup>"
    if [ $# -gt 0 ]; then
      echo "  <ItemGroup>"
      for l in "$@"; do echo "    $l"; done
      echo "  </ItemGroup>"
    fi
    echo "</Project>"; } > "$f"
}

T=tests/App.Tests/App.Tests.csproj

# ---------- GitLab and the repository "api", on develop: a production project and its unit tests ----------
gitlab "$work/api"
cd "$work/api" || exit 1
csproj src/App/App.csproj Microsoft.NET.Sdk
cat > src/App/IFileStore.cs <<'EOF'
namespace App;

public interface IFileStore
{
    string ReadAll(string path);
}
EOF
cat > src/App/FileStore.cs <<'EOF'
namespace App;

public class FileStore : IFileStore
{
    public string ReadAll(string path) => File.ReadAllText(path);
}
EOF
cat > src/App/PathService.cs <<'EOF'
namespace App;

public class PathService(IFileStore store)
{
    private readonly string root = "/data";

    public string Read(string name) => store.ReadAll(Path.Combine(root, name));

    public string Preview(string name)
    {
        var text = Read(name);
        return text.Length > 10 ? text[..10] : text;
    }
}
EOF
cat > src/App/DownloadController.cs <<'EOF'
namespace App;

public class DownloadController(PathService paths)
{
    public string Get(string name) => paths.Read(name);
}
EOF
cat > src/App/RedirectController.cs <<'EOF'
namespace App;

public class RedirectController
{
    public string Go(string url) => url;
}
EOF
cat > src/App/LogService.cs <<'EOF'
namespace App;

public class LogService
{
    public string Line(string user) => "login " + user.Replace("\n", "_").Replace("\r", "_");
}
EOF
cat > src/App/Headers.cs <<'EOF'
namespace App;

public static class Headers
{
    public static readonly Dictionary<string, string> Values = new();

    public static void Add(string name, string value) => Values[name] = value;
}
EOF
cat > src/App/Startup.cs <<'EOF'
namespace App;

public static class Startup
{
    public static void Configure() { }
}
EOF
cat > src/App/Hasher.cs <<'EOF'
namespace App;

public static class Hasher
{
    public static string Hash(string s) => "md5:" + s;
}
EOF
cat > src/App/TokenService.cs <<'EOF'
namespace App;

public static class TokenService
{
    public static string NewToken() => new Random(42).Next().ToString();
}
EOF
cat > src/App/Report.cs <<'EOF'
namespace App;

public static class Report
{
    public static string Export(string path) => path;
}
EOF
csproj "$T" Microsoft.NET.Sdk '<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '<PackageReference Include="xunit" Version="2.9.2" />' '<PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />' \
  '<PackageReference Include="coverlet.collector" Version="6.0.2" />' '<ProjectReference Include="../../src/App/App.csproj" />' \
  '<Using Include="Xunit" />'
cat > tests/App.Tests/FakeStore.cs <<'EOF'
namespace App.Tests;

public sealed class FakeStore : IFileStore
{
    public string? LastPath { get; private set; }

    public string ReadAll(string path)
    {
        LastPath = path;
        return "content of " + path;
    }
}
EOF
cat > tests/App.Tests/PathServiceTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.PathServiceTests.Read_ValidName_ReturnsContent pass -->
public class PathServiceTests
{
    [Fact]
    public void Read_ValidName_ReturnsContent() => Assert.Equal("content of /data/a.txt", new PathService(new FakeStore()).Read("a.txt"));
}
EOF
cat > tests/App.Tests/RedirectControllerTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.RedirectControllerTests.Go_LocalUrl_Kept pass -->
public class RedirectControllerTests
{
    [Fact]
    public void Go_LocalUrl_Kept() => Assert.Equal("/home", new RedirectController().Go("/home"));
}
EOF
# a test that already fails on develop: never the batch's to fix
cat > tests/App.Tests/LegacyTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.LegacyTests.Old_Rounding fail Assert.Equal() Failure: Values differ -->
public class LegacyTests
{
    [Fact]
    public void Old_Rounding() => Assert.Equal(3, (int)Math.Round(2.5));
}
EOF
cat > App.sln <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 17
VisualStudioVersion = 17.0.31903.59
MinimumVisualStudioVersion = 10.0.40219.1
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "src\App\App.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App.Tests", "tests\App.Tests\App.Tests.csproj", "{22222222-2222-2222-2222-222222222222}"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|Any CPU = Debug|Any CPU
		Release|Any CPU = Release|Any CPU
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		{11111111-1111-1111-1111-111111111111}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		{11111111-1111-1111-1111-111111111111}.Debug|Any CPU.Build.0 = Debug|Any CPU
		{11111111-1111-1111-1111-111111111111}.Release|Any CPU.ActiveCfg = Release|Any CPU
		{11111111-1111-1111-1111-111111111111}.Release|Any CPU.Build.0 = Release|Any CPU
		{22222222-2222-2222-2222-222222222222}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
		{22222222-2222-2222-2222-222222222222}.Debug|Any CPU.Build.0 = Debug|Any CPU
		{22222222-2222-2222-2222-222222222222}.Release|Any CPU.ActiveCfg = Release|Any CPU
		{22222222-2222-2222-2222-222222222222}.Release|Any CPU.Build.0 = Release|Any CPU
	EndGlobalSection
EndGlobal
EOF
# the Fortify SSC application, next to a value that must never be printed
printf 'APPSEC_PROJECT_NAME=app-api\nAPPSEC_TOKEN=s3cr3t-never-printed\n' > appsec-ci.env
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m "chore: the api" && git push -q origin develop 2>/dev/null
git branch -q -u origin/develop
cover "src/App/PathService.cs 7:1 10:0 11:0" "src/App/FileStore.cs 5:0" "src/App/DownloadController.cs 5:0" \
  "src/App/RedirectController.cs 5:1" "src/App/LogService.cs 5:0" "src/App/Startup.cs 5:0" "src/App/Hasher.cs 5:0" \
  "src/App/TokenService.cs 5:0" "src/App/Report.cs 5:0"

# ======================================================================================================================
# A. The prerequisites (fortify.sh prereq), each case of step 1
# ======================================================================================================================
step "A. prérequis"
out=$(PATH="$work/nodotnet" "$SH" "$scripts/fortify.sh" prereq 2>&1); status=$?
check "dotnet absent: STOP, an environment problem" 1 '^STOP: dotnet is not on the PATH of this machine \(ENVIRONMENT PROBLEM'
out=$(PATH="$work/nodotnet" "$SH" "$scripts/test-guardian.sh" coverage V0 "$T" src/App/PathService.cs 2>&1); status=$?
check "dotnet absent: the test-guardian stops too" 1 '^ENVIRONMENT PROBLEM: dotnet is not on the PATH'
git rm -q appsec-ci.env && git commit -q -m "tmp: no appsec"
run fortify.sh prereq
check "no SSC application line: STOP" 1 '^STOP: no APPSEC_PROJECT_NAME line in appsec-ci.env'
git reset -q --hard HEAD~1
run fortify.sh prereq
check "everything there: OK" 0 '^PREREQ: OK$'
check "the test project and its collector" 0 "^PREREQ: test project $T \(coverlet.collector\)$"
check "the SSC line found, its value never printed" 0 '^PREREQ: Fortify SSC application line found$' 's3cr3t'
run workflow-state.sh --no-fetch --appsec
check "workflow state: the SSC application only" 0 '^Fortify SSC application line \(appsec-ci.env\): APPSEC_PROJECT_NAME=app-api$' 's3cr3t'

# no coverage collector: the developer says « Oui », the set-up is the first commit of the batch (step 3.3)
git switch -q -c tmp/no-coverlet
sed -i '/coverlet.collector/d' "$T"
git add -A && git commit -q -m "tmp: no coverlet"
run fortify.sh prereq
check "no collector: COVERLET MISSING" 0 "^PREREQ: COVERLET MISSING in: $T"
check "no collector: SETUP NEEDED" 0 '^PREREQ: SETUP NEEDED$'
chain "test-guardian.sh setup xunit src/App/PathService.cs" "ship.sh --no-push 'test: add coverlet.collector to the unit test projects (SEC-1)'"
check "set-up: the collector added, built" 0 "^SETUP: coverlet.collector $(pick 6.0.4 '[0-9.]+') added to $T; build OK$"
check "set-up: committed" 0 '^COMMIT: .*test: add coverlet.collector to the unit test projects'
run fortify.sh prereq
check "after the set-up: OK" 0 '^PREREQ: OK$'
git switch -q develop

# no test project at all: SETUP NEEDED, then a new test project referenced by the solution
git switch -q -c tmp/no-tests
git rm -q -r tests && sed -i '/"App.Tests"/,/EndProject/d; /22222222-2222/d' App.sln
git add -A && git commit -q -m "tmp: no tests"
run fortify.sh prereq
check "no test project: NO TEST PROJECT" 0 '^PREREQ: NO TEST PROJECT'
check "no test project: SETUP NEEDED" 0 '^PREREQ: SETUP NEEDED$'
chain "test-guardian.sh setup xunit src/App/PathService.cs" "ship.sh --no-push 'test: add the unit test project (SEC-1)'"
check "set-up: a new test project" 0 "^SETUP: tests/App.UnitTests/App.UnitTests.csproj created \(xunit, $TFM\)"
check "set-up: in the solution" 0 'added to App.sln; build OK$'
truth "set-up: the solution lists it" 'grep -q "App.UnitTests" App.sln'
run fortify.sh prereq
check "after the set-up: OK" 0 '^PREREQ: OK$'
# a set-up that fails (the production project does not compile) undoes all it did
git switch -q -c tmp/no-tests-2 tmp/no-tests~1
git clean -q -fdX
cat > src/App/Broken.cs <<'EOF'
namespace App;

// <!-- fake-build-error -->
public class Broken
{
    public int X() => ;
}
EOF
git add -A && git commit -q -m "tmp: broken"
run test-guardian.sh setup xunit src/App/PathService.cs
check "set-up that fails: STOP" 1 '^STOP: the new test project does not build: nothing created$'
truth "set-up that fails: nothing left" 'clean && [ ! -d tests ]'
git switch -q develop
git clean -q -fdX
git branch -q -D tmp/no-coverlet tmp/no-tests tmp/no-tests-2

# ======================================================================================================================
# B. The start conditions (step 1): develop clean, uncommitted files
# ======================================================================================================================
step "B. conditions de départ"
echo "// wip" >> src/App/Report.cs
run workflow-state.sh --no-fetch --sheet
check "uncommitted file: the pilot sees it and stops" 0 'src/App/Report.cs'
git checkout -q -- src/App/Report.cs
run workflow-state.sh --no-fetch --sheet
check "develop, clean: the batch can start" 0 '^Current branch: develop$'

# ======================================================================================================================
# C. Batch 1: the branch and the sheet (step 3), the measure of develop (step 4)
# ======================================================================================================================
step "C. lot 1 : branche, fiche, mesure"
chain "branch.sh LOCAL bugfix 'Fortify Path Manipulation lot 2026-10-24'" "workflow-state.sh --no-fetch --sheet" "fortify.sh batch"
check "the batch branch, from origin/develop" 0 '^BRANCH: bugfix/LOCAL-1-fortify-path-manipulation.* \(created from origin/develop'
check "a local key" 0 '^KEY: LOCAL-1$'
check "the sheet to write" 0 '^Current ticket sheet: none for LOCAL-1 \(to be written at .*/opencode-tickets/LOCAL-1.md\)$'
check "the batch folder" 0 '^BATCH: .*/opencode-tickets/LOCAL-1.fortify$'
B1=$(printf '%s\n' "$out" | sed -n 's/^BATCH: //p')
SHEET=$(printf '%s\n' "$out" | sed -n 's/^Current ticket sheet: none for LOCAL-1 (to be written at \(.*\))$/\1/p')
cat > "$SHEET" <<'EOF'
# Lot Fortify app-api / develop
- Lot Fortify : app-api / develop - 2026-10-24

## Plan
- [ ] 1. V1 : Path Manipulation - src/App/PathService.cs:7 - Fortify 1001 - Critical
- [ ] 2. V2 : Path Manipulation - src/App/DownloadController.cs:5 - Fortify 1002 - Critical
- [ ] 3. V3 : Open Redirect - src/App/RedirectController.cs:5 - Fortify 1003 - High
- [ ] 4. V4 : Path Manipulation - src/App/PathService.cs:11 - Fortify 1004 - High
- [ ] 5. V5 : Log Forging - src/App/LogService.cs:5 - Fortify 1005 - High

## Décisions

## Suivi
EOF
run workflow-state.sh --no-fetch --sheet
check "the sheet is read back, a batch sheet" 0 '^- Lot Fortify : app-api / develop'
# the measure of develop: a test that already fails there is never the batch's
run build-test.sh App.sln
check "measure of develop: built" 1 '^BUILD: OK'
check "measure of develop: the test that already fails, named" 1 '^FAILED TESTS \(1\): App.Tests.LegacyTests.Old_Rounding$'
BASE_FAILS=$(printf '%s\n' "$out" | sed -n 's/^FAILED TESTS ([0-9]*): //p')
run ticket-sheet.sh suivi "/fortify - base develop : build ok - en échec avant le lot : $BASE_FAILS"
check "measure recorded in the sheet" 0 '^- \[ \] 1\. V1'
truth "…in its Suivi" 'grep -q "en échec avant le lot : App.Tests.LegacyTests.Old_Rounding" "$SHEET"'
# the cards of the analysts (step 4): V2's misses PathService.cs, which V1's fix will change
card "$B1" V1 "Path Manipulation" "src/App/PathService.cs:7" "vraie faille" "src/App/PathService.cs src/App/FileStore.cs src/App/IFileStore.cs" "$T ; entrée ../../etc/passwd rejetée"
card "$B1" V2 "Path Manipulation" "src/App/DownloadController.cs:5" "vraie faille" "src/App/DownloadController.cs" "$T ; entrée ../x rejetée"
card "$B1" V3 "Open Redirect" "src/App/RedirectController.cs:5" "vraie faille" "src/App/RedirectController.cs" "$T ; https://evil.example refusée"
card "$B1" V4 "Path Manipulation" "src/App/PathService.cs:11" "vraie faille" "src/App/PathService.cs" "$T ; ../x rejetée"
card "$B1" V5 "Log Forging" "src/App/LogService.cs:5" "vraie faille" "src/App/LogService.cs" "$T ; retour à la ligne neutralisé"
truth "five cards" '[ "$(ls "$B1" | wc -l | tr -d " ")" = 5 ]'

# ======================================================================================================================
# D. Wave 1 (V1, V2, V3: their cards share no file): the proofs, together (step 5.1)
# ======================================================================================================================
step "D. vague 1 : preuves en parallèle"
# the test-guardian of each vulnerability, phase « avant le correctif » (agents/test-guardian.md)
guardian_v1() {
  "$SH" "$scripts/test-guardian.sh" deps src/App/PathService.cs
  "$SH" "$scripts/test-guardian.sh" coverage V1-before "$T" src/App/PathService.cs src/App/FileStore.cs || return 1
  put tests/App.Tests/PathServiceContextTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.PathServiceContextTests.Read_Name_CombinesRoot pass -->
public class PathServiceContextTests
{
    [Fact]
    public void Read_Name_CombinesRoot()
    {
        var store = new FakeStore();
        new PathService(store).Read("a.txt");
        Assert.Equal("/data/a.txt", store.LastPath);
    }
}
EOF
  "$SH" "$scripts/test-guardian.sh" green "$T" FullyQualifiedName~PathServiceContextTests || return 1
  put tests/App.Tests/PathServiceSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.PathServiceSecurityTests.Security_PathManipulation_V1_Traversal requires src/App/PathService.cs:GetFullPath Assert.Throws() Failure: No exception was thrown -->
public class PathServiceSecurityTests
{
    [Fact]
    public void Security_PathManipulation_V1_Traversal() =>
        Assert.Throws<ArgumentException>(() => new PathService(new FakeStore()).Read("../../etc/passwd"));
}
EOF
  "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_PathManipulation_V1 || return 1
  "$SH" "$scripts/test-guardian.sh" coverage V1-tests "$T" src/App/PathService.cs src/App/FileStore.cs || return 1
  "$SH" "$scripts/test-guardian.sh" seal V1 tests/App.Tests/PathServiceContextTests.cs tests/App.Tests/PathServiceSecurityTests.cs
}
guardian_v2() {
  "$SH" "$scripts/test-guardian.sh" coverage V2-before "$T" src/App/DownloadController.cs || return 1
  put tests/App.Tests/DownloadSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.DownloadSecurityTests.Security_PathManipulation_V2_Traversal requires src/App/PathService.cs:GetFullPath Assert.Throws() Failure: No exception was thrown -->
public class DownloadSecurityTests
{
    [Fact]
    public void Security_PathManipulation_V2_Traversal() =>
        Assert.Throws<ArgumentException>(() => new DownloadController(new PathService(new FakeStore())).Get("../x"));
}
EOF
  "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_PathManipulation_V2 || return 1
  "$SH" "$scripts/test-guardian.sh" seal V2 tests/App.Tests/DownloadSecurityTests.cs
}
# V3: its first test is flaky (a file left by the run before it), then deterministic
guardian_v3() {
  "$SH" "$scripts/test-guardian.sh" coverage V3-before "$T" src/App/RedirectController.cs || return 1
  put tests/App.Tests/RedirectSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.RedirectSecurityTests.Security_OpenRedirect_V3_External flaky Expected a local url -->
public class RedirectSecurityTests
{
    [Fact]
    public void Security_OpenRedirect_V3_External()
    {
        var marker = Path.Combine(Path.GetTempPath(), "fortify-test-flaky-v3");
        if (File.Exists(marker))
        {
            File.Delete(marker);
            Assert.Fail("Expected a local url");
        }
        File.WriteAllText(marker, "");
    }
}
EOF
  "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_OpenRedirect_V3
  echo "== made deterministic"
  put tests/App.Tests/RedirectSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.RedirectSecurityTests.Security_OpenRedirect_V3_External requires src/App/RedirectController.cs:IsLocalUrl Assert.Equal() Failure: Strings differ -->
public class RedirectSecurityTests
{
    [Fact]
    public void Security_OpenRedirect_V3_External() => Assert.Equal("/", new RedirectController().Go("https://evil.example"));
}
EOF
  "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_OpenRedirect_V3 || return 1
  "$SH" "$scripts/test-guardian.sh" seal V3 tests/App.Tests/RedirectSecurityTests.cs
}
[ "$REAL" -eq 1 ] || { FAKE_DOTNET_SLOW_TEST=1; export FAKE_DOTNET_SLOW_TEST; }
bg g1 guardian_v1
bg g2 guardian_v2
bg g3 guardian_v3
wait
unset FAKE_DOTNET_SLOW_TEST
got g1
check "V1: its module and its dependency" 0 '^DEPENDS: IFileStore -> src/App/FileStore.cs$'
check "V1: coverage before" 0 "^src/App/PathService.cs lines $(pick '1/3 \(33%\) branches 0/0 uncovered 10-11$' '[0-9]+/[0-9]+ \([0-9]+%\)')"
check "V1: context tests green twice" 0 '^GREEN: 1 tests pass, twice$'
check "V1: red for the reason of the vulnerability" 0 'Security_PathManipulation_V1_Traversal: Assert.Throws\(\) Failure: No exception was thrown'
check "V1: RED twice" 0 '^RED: 1 tests fail on the current code, twice the same way, as expected$'
check "V1: sealed" 0 '^SEALED: 2 test files'
got g2
check "V2: RED" 0 '^RED: 1 tests fail on the current code'
check "V2: sealed" 0 '^SEALED: 1 test files'
got g3
check "V3: a flaky test is refused" 0 '^FLAKY: App.Tests.RedirectSecurityTests.Security_OpenRedirect_V3_External'
check "V3: then RED once deterministic" 0 '^RED: 1 tests fail on the current code'
check "V3: sealed" 0 '^SEALED: 1 test files'
out=$(cat "$work/g1" "$work/g2" "$work/g3")
status=0
check "the three guardians met on the lock of the folder, and waited" 0 '^WAIT: another build or test run of this folder is in progress'
run test-guardian.sh tests-only
check "the wave wrote in the test projects only" 0 '^TESTS-ONLY: OK$'

# a test file of another test-guardian of the wave that does not compile yet: the red of this one says so
cat >> tests/App.Tests/RedirectSecurityTests.cs <<'EOF'
// <!-- fake-build-error -->
public class RedirectWorkInProgress
{
    public int X() => ;
}
EOF
run test-guardian.sh red "$T" FullyQualifiedName~Security_PathManipulation_V2
check "a file of another guardian does not compile: STOP, named" 1 'RedirectSecurityTests.cs\([0-9]+,[0-9]+\): error CS[0-9]+'
check "…and the reason" 1 '^STOP: the tests do not build: a red test must compile against the current code'
run test-guardian.sh sealed V3
check "the seal sees the file changed" 1 '^STOP: the test files of the proof V3 changed since they were sealed: tests/App.Tests/RedirectSecurityTests.cs'
run test-guardian.sh restore V3
check "restore: back as sealed" 0 '^RESTORED: tests/App.Tests/RedirectSecurityTests.cs$'
run test-guardian.sh red "$T" FullyQualifiedName~Security_PathManipulation_V2
check "the same red once more: RED" 0 '^RED: 1 tests fail'

# ======================================================================================================================
# E. The proofs put away (step 5.2): the working tree is clean, each fix starts from its own proof only
# ======================================================================================================================
step "E. preuves rangées"
for v in V1 V2 V3; do etat "$B1" "$v" "- tests : RED - contexte ajouté - couverture avant - test-guardian ses_$v"; done
chain "test-guardian.sh park V1" "test-guardian.sh park V2" "test-guardian.sh park V3"
check "three proofs parked" 0 '^PARKED: 1 test files of the proof V3 out of the working tree'
truth "the working tree is clean" 'clean'
for v in V1 V2 V3; do etat "$B1" "$v" "- preuve rangée"; done
run test-guardian.sh park V1
check "a proof is parked once" 1 '^STOP: the proof V1 is parked already'

# ======================================================================================================================
# F. V1, in turn (step 5.4): its proof back, still red; the fix; the tests after; the commit
# ======================================================================================================================
step "F. V1 corrigée"
chain "test-guardian.sh unpark V1" "test-guardian.sh red $T FullyQualifiedName~Security_PathManipulation_V1"
check "4a: the proof back, as sealed" 0 '^UNPARKED: 2 test files of the proof V1 back, as sealed$'
check "4a: still red on the current code" 0 '^RED: 1 tests fail'
truth "4a: only V1's tests are back" '[ -f tests/App.Tests/PathServiceSecurityTests.cs ] && [ ! -f tests/App.Tests/DownloadSecurityTests.cs ] && [ ! -f tests/App.Tests/RedirectSecurityTests.cs ]'
# 4b: the coder fixes the code (the smallest change of the card), never the tests
cat > src/App/PathService.cs <<'EOF'
namespace App;

public class PathService(IFileStore store)
{
    private readonly string root = "/data";

    public string Read(string name)
    {
        var full = Path.GetFullPath(Path.Combine(root, name));
        if (!full.StartsWith(root + "/", StringComparison.Ordinal))
        {
            throw new ArgumentException("outside the data folder", nameof(name));
        }
        return store.ReadAll(full);
    }

    public string Preview(string name)
    {
        var text = Read(name);
        return text.Length > 10 ? text[..10] : text;
    }
}
EOF
run test-guardian.sh green "$T" FullyQualifiedName~Security_PathManipulation_V1
check "4b: the coder's done condition, GREEN" 0 '^GREEN: 1 tests pass, twice$'
etat "$B1" V1 "- correctif : src/App/PathService.cs - coder ses_c1"
# 4c: the same test-guardian, phase « après le correctif »
cover "src/App/PathService.cs 9:1 10:1 11:1 12:1 14:1 19:0 20:0" "src/App/FileStore.cs 5:0" "src/App/RedirectController.cs 5:1"
run test-guardian.sh sealed V1
check "4c: the tests as sealed" 0 '^SEAL: OK, 2 test files as sealed$'
run test-guardian.sh green "$T" "FullyQualifiedName~Security_PathManipulation_V1|FullyQualifiedName~PathServiceContextTests"
check "4c: the proof and the context, green twice" 0 '^GREEN: 2 tests pass, twice$'
run test-guardian.sh coverage V1-after "$T" src/App/PathService.cs src/App/FileStore.cs
check "4c: coverage after" 0 "^src/App/PathService.cs lines $(pick '5/7 \(71%\)' '[0-9]+/[0-9]+ \([0-9]+%\)')"
run test-guardian.sh compare V1-before V1-after
check "4c: no file lost coverage" 0 '^COVERAGE: no file lost coverage$'
etat "$B1" V1 "- après : GREEN deux fois - couverture après - perte aucune"
# 4d: the commit, the fix and its tests together
chain "test-guardian.sh sealed V1" "ship.sh --no-push 'fix(security): path manipulation in PathService.cs (V1, LOCAL-1)' '- Fortify 1001' '- tests: 1 context, 1 vulnerability (red before, green after, twice each)'" "ticket-sheet.sh tick 1 '/fortify V1 - corrigée - tests 1+1 - couverture sans perte'"
check "4d: committed" 0 '^COMMIT: .*fix\(security\): path manipulation in PathService.cs \(V1, LOCAL-1\)'
check "4d: ticked" 0 '^- \[x\] 1\. V1'
truth "4d: the commit holds V1's fix and tests only" '[ "$(git show --name-only --format= HEAD | sort | tr "\n" " ")" = "src/App/PathService.cs tests/App.Tests/PathServiceContextTests.cs tests/App.Tests/PathServiceSecurityTests.cs " ]'
truth "4d: nothing left" 'clean'

# ======================================================================================================================
# G. V2, in turn: V1's fix closed it too (4a « PASS on the current code »), committed as a proof
# ======================================================================================================================
step "G. V2 fermée par V1"
chain "test-guardian.sh unpark V2" "test-guardian.sh red $T FullyQualifiedName~Security_PathManipulation_V2"
check "4a: back" 1 '^UNPARKED: 1 test files of the proof V2 back'
check "4a: its test passes now: a fix before it closed it" 1 '^STOP: 1 of these tests PASS on the current code: they do not show the problem$'
run test-guardian.sh green "$T" FullyQualifiedName~Security_PathManipulation_V2
check "c: green twice" 0 '^GREEN: 1 tests pass, twice$'
chain "test-guardian.sh sealed V2" "ship.sh --no-push 'test(security): show that path manipulation in DownloadController.cs is fixed by V1 (V2, LOCAL-1)' '- Fortify 1002'" "ticket-sheet.sh tick 2 '/fortify V2 - corrigée par V1 - tests 1'"
check "committed as a proof of V1's fix" 0 '^COMMIT: .*is fixed by V1 \(V2, LOCAL-1\)'
check "ticked" 0 '^- \[x\] 2\. V2'

# ======================================================================================================================
# H. V3, in turn: a coder that changes the sealed test; the proof put back; a lost coverage; the commit
# ======================================================================================================================
step "H. V3 : test modifié, couverture perdue"
chain "test-guardian.sh unpark V3" "test-guardian.sh red $T FullyQualifiedName~Security_OpenRedirect_V3"
check "4a: red" 0 '^RED: 1 tests fail'
# the coder makes the test pass by changing it, not the code
cat > tests/App.Tests/RedirectSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.RedirectSecurityTests.Security_OpenRedirect_V3_External pass -->
public class RedirectSecurityTests
{
    [Fact]
    public void Security_OpenRedirect_V3_External() => Assert.Equal("https://evil.example", new RedirectController().Go("https://evil.example"));
}
EOF
run test-guardian.sh green "$T" FullyQualifiedName~Security_OpenRedirect_V3
check "the coder's own green passes (it changed the test)" 0 '^GREEN: 1 tests pass'
run test-guardian.sh sealed V3
check "4c: the seal catches it" 1 '^STOP: the test files of the proof V3 changed since they were sealed'
run test-guardian.sh restore V3
check "4c: the test put back as sealed" 0 '^RESTORED: tests/App.Tests/RedirectSecurityTests.cs$'
run test-guardian.sh green "$T" FullyQualifiedName~Security_OpenRedirect_V3
check "4c: on the real test, still red: ÉCHEC for the coder" 1 '^STOP: 1 of these tests FAIL, twice the same way$'
# one round of the same coder session: the real fix, with a method that no test runs
cat > src/App/RedirectController.cs <<'EOF'
namespace App;

public class RedirectController
{
    public string Go(string url) => IsLocalUrl(url) ? url : "/";

    public string GoOrFallback(string url, string fallback)
    {
        if (string.IsNullOrEmpty(fallback))
        {
            fallback = "/";
        }
        return IsLocalUrl(url) ? url : fallback;
    }

    private static bool IsLocalUrl(string url) => url.StartsWith('/') && !url.StartsWith("//", StringComparison.Ordinal);
}
EOF
run test-guardian.sh green "$T" FullyQualifiedName~Security_OpenRedirect_V3
check "after the coder's round: GREEN" 0 '^GREEN: 1 tests pass, twice$'
cover "src/App/RedirectController.cs 5:1 8:0 9:0 10:0 11:0 13:0 16:1"
run test-guardian.sh coverage V3-after "$T" src/App/RedirectController.cs
run test-guardian.sh compare V3-before V3-after
check "4c: a file lost coverage: STOP" 1 '^STOP: coverage lost after the change in src/App/RedirectController.cs$'
# the coder's next round: the method that nothing calls goes away
cat > src/App/RedirectController.cs <<'EOF'
namespace App;

public class RedirectController
{
    public string Go(string url) => IsLocalUrl(url) ? url : "/";

    private static bool IsLocalUrl(string url) => url.StartsWith('/') && !url.StartsWith("//", StringComparison.Ordinal);
}
EOF
cover "src/App/RedirectController.cs 5:1 7:1"
run test-guardian.sh coverage V3-after "$T" src/App/RedirectController.cs
run test-guardian.sh compare V3-before V3-after
check "4c: then no loss" 0 '^COVERAGE: no file lost coverage$'
chain "test-guardian.sh sealed V3" "ship.sh --no-push 'fix(security): open redirect in RedirectController.cs (V3, LOCAL-1)' '- Fortify 1003'" "ticket-sheet.sh tick 3 '/fortify V3 - corrigée - tests 0+1 - couverture sans perte'"
check "4d: committed" 0 '^COMMIT: .*open redirect in RedirectController.cs \(V3, LOCAL-1\)'
truth "4d: the sealed test, as sealed, in the commit" 'git show HEAD:tests/App.Tests/RedirectSecurityTests.cs | grep -q "Assert.Equal(\"/\""'

# ======================================================================================================================
# I. Wave 2 (V4 shares PathService.cs with V1: a wave of its own; V5): the code resists (step 5.3)
# ======================================================================================================================
step "I. vague 2 : le code résiste"
guardian_v4() {
  "$SH" "$scripts/test-guardian.sh" coverage V4-before "$T" src/App/PathService.cs || return 1
  put tests/App.Tests/PreviewSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.PreviewSecurityTests.Security_PathManipulation_V4_Traversal requires src/App/PathService.cs:GetFullPath Assert.Throws() Failure: No exception was thrown -->
public class PreviewSecurityTests
{
    [Fact]
    public void Security_PathManipulation_V4_Traversal() =>
        Assert.Throws<ArgumentException>(() => new PathService(new FakeStore()).Preview("../x"));
}
EOF
  "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_PathManipulation_V4
  echo "== the hostile input of the card once more: it passes still, the code resists"
  "$SH" "$scripts/test-guardian.sh" green "$T" FullyQualifiedName~Security_PathManipulation_V4 || return 1
  "$SH" "$scripts/test-guardian.sh" seal V4 tests/App.Tests/PreviewSecurityTests.cs
}
guardian_v5() {
  "$SH" "$scripts/test-guardian.sh" coverage V5-before "$T" src/App/LogService.cs || return 1
  # a fake token in a test fixture: a warning of the check before the push, never a stop
  put tests/App.Tests/LogSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.LogSecurityTests.Security_LogForging_V5_NewLine requires src/App/LogService.cs:Replace( Assert.DoesNotContain() Failure -->
// fixture of the log reader: glpat-AbCdEfGhIjKlMnOpQrSt
public class LogSecurityTests
{
    [Fact]
    public void Security_LogForging_V5_NewLine() => Assert.DoesNotContain("\n", new LogService().Line("bob\nadmin logged in"));
}
EOF
  "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_LogForging_V5
  "$SH" "$scripts/test-guardian.sh" green "$T" FullyQualifiedName~Security_LogForging_V5 || return 1
  "$SH" "$scripts/test-guardian.sh" seal V5 tests/App.Tests/LogSecurityTests.cs
}
bg g4 guardian_v4
bg g5 guardian_v5
wait
got g4
check "V4: its test passes on the current code (V1's fix covers Preview)" 0 'STOP: 1 of these tests PASS on the current code'
check "V4: résiste, sealed" 0 '^SEALED: 1 test files'
got g5
check "V5: résiste, sealed" 0 '^SEALED: 1 test files'
for v in V4 V5; do etat "$B1" "$v" "- tests : résiste - contexte déjà couvert - test-guardian ses_$v"; done
chain "test-guardian.sh park V4" "test-guardian.sh park V5"
check "parked" 0 '^PARKED: 1 test files of the proof V5'
truth "clean" 'clean'
chain "test-guardian.sh unpark V4" "ship.sh --no-push 'test(security): show that path manipulation in PathService.cs is not exploitable (V4, LOCAL-1)' '- Fortify 1004'" "ticket-sheet.sh tick 4 '/fortify V4 - non exploitable - tests 1 - à déclarer dans SSC par toi'"
check "5.3: V4 committed as not exploitable" 0 '^COMMIT: .*is not exploitable \(V4, LOCAL-1\)'
chain "test-guardian.sh unpark V5" "ship.sh --no-push 'test(security): show that log forging in LogService.cs is not exploitable (V5, LOCAL-1)' '- Fortify 1005'" "ticket-sheet.sh tick 5 '/fortify V5 - non exploitable - tests 1 - à déclarer dans SSC par toi'"
check "5.3: V5 committed as not exploitable" 0 '^COMMIT: .*is not exploitable \(V5, LOCAL-1\)'
truth "every vulnerability of the plan ticked" '! grep -q "^- \[ \]" "$SHEET"'

# ======================================================================================================================
# J. Verify and deliver (step 6): the full suite and the coverage of the changes, the check, the push
# ======================================================================================================================
step "J. vérification et livraison du lot 1"
cover "src/App/PathService.cs 9:1 10:1 11:1 12:1 14:1 19:1 20:1" "src/App/RedirectController.cs 5:1 7:1"
run test-guardian.sh changes origin/develop App.sln
check "the suite: the only failure is the one of develop" 1 '^FAILED TESTS \(1\): App.Tests.LegacyTests.Old_Rounding$'
check "the coverage of the changes" 1 '^COVERAGE OF THE CHANGES: [0-9]+/[0-9]+ changed lines covered'
check "the changed lines of the fixes" 1 '^CHANGED: src/App/PathService.cs '
chain "ship.sh --sync-only --base" "ship.sh --base 'fix(security): Fortify batch app-api / develop (LOCAL-1)'"
check "the check before the push: a fake token of a test fixture is a warning" 0 '^WARNING: .*tests/App.Tests/LogSecurityTests.cs'
check "pushed" 0 '^PUSH: OK, origin/bugfix/LOCAL-1-fortify-path-manipulation'
truth "the branch is on GitLab" 'on_origin "$work/api.git" "$(git branch --show-current)"'
truth "the measures and cards never committed" '! git ls-files | grep -q "opencode-tickets"'
truth "five commits, one per vulnerability" '[ "$(git rev-list --count origin/develop..HEAD)" = 5 ]'

# ======================================================================================================================
# K. Batch 2, in a worktree started detached (an OpenCode workspace), with a Jira key
# ======================================================================================================================
step "K. lot 2 : espace de travail, clé Jira"
git worktree add -q --detach "$work/wt" origin/develop 2>/dev/null
cd "$work/wt" || exit 1
run workflow-state.sh --no-fetch --sheet
check "a detached worktree: the batch can start from it" 0 '^Current branch: \(detached HEAD\)$'
chain "branch.sh SEC-7 bugfix 'Fortify Weak Cryptographic Hash lot 2026-10-24'" "workflow-state.sh --no-fetch --sheet" "fortify.sh batch"
check "the batch branch of the key, from origin/develop" 0 '^BRANCH: bugfix/SEC-7-fortify-weak-cryptographic-hash.* \(created from origin/develop'
check "its batch folder, shared with the main checkout" 0 "^BATCH: $work/api/.git/opencode-tickets/SEC-7.fortify$"
B2=$(printf '%s\n' "$out" | sed -n 's/^BATCH: //p')
SHEET2=$(printf '%s\n' "$out" | sed -n 's/^Current ticket sheet: none for SEC-7 (to be written at \(.*\))$/\1/p')
cat > "$SHEET2" <<'EOF'
# Lot Fortify app-api / develop
- Lot Fortify : app-api / develop - 2026-10-24

## Plan
- [ ] 1. V1 : Missing Security Headers - src/App/Startup.cs:5 - Fortify 2001 - High
- [ ] 2. V2 : Weak Cryptographic Hash - src/App/Hasher.cs:5 - Fortify 2002 - High
- [ ] 3. V3 : Insecure Randomness - src/App/TokenService.cs:5 - Fortify 2003 - High
- [ ] 4. V4 : Path Manipulation - src/App/Report.cs:5 - Fortify 2004 - High

## Décisions

## Suivi
EOF
run test-guardian.sh folder
check "measures of SEC-7: a folder of their own" 0 "^FOLDER: $work/api/.git/opencode-tickets/SEC-7.tests$"
cover "src/App/PathService.cs 7:1 10:0 11:0" "src/App/Startup.cs 5:0" "src/App/Hasher.cs 5:0" "src/App/TokenService.cs 5:0" "src/App/Report.cs 5:0"
card "$B2" V1 "Missing Security Headers" "src/App/Startup.cs:5" "vraie faille" "src/App/Startup.cs" "non démontrable par un test unitaire : configuration du pipeline HTTP"
card "$B2" V2 "Weak Cryptographic Hash" "src/App/Hasher.cs:5" "vraie faille" "src/App/Hasher.cs" "$T ; le hachage n'est pas MD5"
card "$B2" V3 "Insecure Randomness" "src/App/TokenService.cs:5" "vraie faille" "src/App/TokenService.cs" "$T ; deux jetons diffèrent"
card "$B2" V4 "Path Manipulation" "src/App/Report.cs:5" "vraie faille" "src/App/Report.cs" "$T ; ../x rejetée"

# the guardians of both worktrees at the same time: one lock per worktree, neither waits for the other
( cd "$work/api" && FAKE_DOTNET_SLOW_TEST=2 "$SH" "$scripts/test-guardian.sh" coverage X1 "$T" src/App/PathService.cs > "$work/w1" 2>&1; echo $? > "$work/w1.s" ) &
( cd "$work/wt" && FAKE_DOTNET_SLOW_TEST=2 "$SH" "$scripts/test-guardian.sh" coverage X2 "$T" src/App/Hasher.cs > "$work/w2" 2>&1; echo $? > "$work/w2.s" ) &
wait
got w1
check "two worktrees: the first measured without waiting" 0 '^src/App/PathService.cs lines' 'WAIT:'
got w2
check "two worktrees: the second measured without waiting" 0 '^src/App/Hasher.cs lines' 'WAIT:'

# ======================================================================================================================
# L. A vulnerability that no unit test can show (configuration): an empty proof, then the fix and its commit
# ======================================================================================================================
step "L. non démontrable"
run test-guardian.sh coverage V1-before "$T" src/App/Startup.cs
check "V1: coverage before" 0 '^src/App/Startup.cs lines 0/[0-9]+'
run test-guardian.sh seal V1
check "V1: an empty proof is sealed (nothing a unit test can show)" 0 '^SEALED: 0 test files: this proof holds no test'
etat "$B2" V1 "- tests : non démontrable - contexte déjà couvert - test-guardian ses_w1"

# ======================================================================================================================
# M. V2 (RED, but the coder never makes it green) and V3 (RED) in the same wave as V1; V2 given up and put aside
# ======================================================================================================================
step "M. abandon d'une faille"
cat > tests/App.Tests/HasherSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.HasherSecurityTests.Security_WeakCryptographicHash_V2_NotMd5 requires src/App/Hasher.cs:SHA256 Assert.StartsWith() Failure -->
public class HasherSecurityTests
{
    [Fact]
    public void Security_WeakCryptographicHash_V2_NotMd5() => Assert.StartsWith("sha256:", Hasher.Hash("secret"));
}
EOF
run test-guardian.sh red "$T" FullyQualifiedName~Security_WeakCryptographicHash_V2
check "V2: RED" 0 '^RED: 1 tests fail'
run test-guardian.sh seal V2 tests/App.Tests/HasherSecurityTests.cs
cat > tests/App.Tests/TokenSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.TokenSecurityTests.Security_InsecureRandomness_V3_Unpredictable requires src/App/TokenService.cs:RandomNumberGenerator Assert.NotEqual() Failure -->
public class TokenSecurityTests
{
    [Fact]
    public void Security_InsecureRandomness_V3_Unpredictable() => Assert.NotEqual(TokenService.NewToken(), TokenService.NewToken());
}
EOF
run test-guardian.sh red "$T" FullyQualifiedName~Security_InsecureRandomness_V3
check "V3: RED" 0 '^RED: 1 tests fail'
run test-guardian.sh seal V3 tests/App.Tests/TokenSecurityTests.cs
for v in V2 V3; do etat "$B2" "$v" "- tests : RED - contexte déjà couvert - test-guardian ses_w$v"; done
chain "test-guardian.sh park V1" "test-guardian.sh park V2" "test-guardian.sh park V3"
check "the wave parked, the empty proof included" 0 '^PARKED: 1 test files of the proof V3'
truth "clean" 'clean'
for v in V1 V2 V3; do etat "$B2" "$v" "- preuve rangée"; done
# V1: its proof back (nothing), the fix, the build and the tests of the module, the commit
run test-guardian.sh unpark V1
check "V1: the empty proof back" 0 '^UNPARKED: the proof V1 is in the working tree already, as sealed$'
cat > src/App/Startup.cs <<'EOF'
namespace App;

public static class Startup
{
    public static void Configure() => Headers.Add("X-Content-Type-Options", "nosniff");
}
EOF
run build-test.sh "$T"
check "V1: the coder's done condition, the build" 1 '^BUILD: OK'
check "V1: …and no failure but the one of develop" 1 '^FAILED TESTS \(1\): App.Tests.LegacyTests.Old_Rounding$'
run test-guardian.sh coverage V1-after "$T" src/App/Startup.cs
run test-guardian.sh compare V1-before V1-after
check "V1: no loss" 0 '^COVERAGE: no file lost coverage$'
chain "test-guardian.sh sealed V1" "ship.sh --no-push 'fix(security): missing security headers in Startup.cs (V1, SEC-7)' '- Fortify 2001' '- tests: none, no unit test can show it (configuration)'" "ticket-sheet.sh tick 1 '/fortify V1 - corrigée - non démontrable'"
check "V1: the empty seal is OK, committed" 0 '^COMMIT: .*missing security headers in Startup.cs \(V1, SEC-7\)'
check "V1: …its seal said so" 0 '^SEAL: OK, 0 test files as sealed$'
# V2: the proof back and red; the coder's fix leaves it red: given up, put aside
chain "test-guardian.sh unpark V2" "test-guardian.sh red $T FullyQualifiedName~Security_WeakCryptographicHash_V2"
check "V2: red" 0 '^RED: 1 tests fail'
cat > src/App/Hasher.cs <<'EOF'
namespace App;

public static class Hasher
{
    public static string Hash(string s) => "sha1:" + s;
}
EOF
run test-guardian.sh green "$T" FullyQualifiedName~Security_WeakCryptographicHash_V2
check "V2: the coder's fix does not make it green" 1 '^STOP: 1 of these tests FAIL'
run fortify.sh discard V2
check "V2: put aside, recoverable" 0 '^DISCARDED: 2 files put aside in git stash « fortify SEC-7 V2 \(wt\) », commit [0-9a-f]{40}'
STASH=$(printf '%s\n' "$out" | sed -n 's/.*, commit \([0-9a-f]\{40\}\)\..*/\1/p')
truth "V2: the working tree is clean" 'clean'
truth "V2: its fix is in the stash" 'git stash show -p "$STASH" | grep -q "sha1"'
run ticket-sheet.sh tick 2 "/fortify V2 - non corrigée : test toujours rouge après deux corrections - stash $STASH"
check "V2: ticked, not fixed" 0 '^- \[x\] 2\. V2'

# ======================================================================================================================
# N. V3 interrupted after its fix (a restart of OpenCode): the resume of step 1, case (3) then 4a, then case (1)
# ======================================================================================================================
step "N. reprise : correctif interrompu"
chain "test-guardian.sh unpark V3" "test-guardian.sh red $T FullyQualifiedName~Security_InsecureRandomness_V3"
check "V3: red" 0 '^RED: 1 tests fail'
fix_token() {
  cat > src/App/TokenService.cs <<'EOF'
namespace App;

public static class TokenService
{
    public static string NewToken() => Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(16));
}
EOF
}
fix_token
etat "$B2" V3 "- correctif : src/App/TokenService.cs - coder ses_c3"
# --- OpenCode restarts here; /fortify again: the sheet has « - Lot Fortify », the cards say where it stopped
run workflow-state.sh --no-fetch --sheet
check "resume: the batch sheet" 0 '^- Lot Fortify : app-api / develop'
check "resume: uncommitted files" 0 'src/App/TokenService.cs'
# V3 has « preuve rangée » and « correctif » but no « après »: case (3), what remains is put aside
run fortify.sh discard reprise
check "resume: the interrupted work put aside" 0 '^DISCARDED: 2 files put aside in git stash « fortify SEC-7 reprise \(wt\) »'
truth "resume: clean" 'clean'
# then 4a: its proof comes back from its seal, its fix is made again
chain "test-guardian.sh unpark V3" "test-guardian.sh red $T FullyQualifiedName~Security_InsecureRandomness_V3"
check "resume 4a: the proof back from its seal" 0 '^UNPARKED: 1 test files of the proof V3 back, as sealed$'
check "resume 4a: red again (the fix was put aside)" 0 '^RED: 1 tests fail'
fix_token
run test-guardian.sh green "$T" FullyQualifiedName~Security_InsecureRandomness_V3
check "resume: green" 0 '^GREEN: 1 tests pass, twice$'
etat "$B2" V3 "- après : GREEN deux fois - perte aucune"
# --- interrupted once more, after « après » and before its commit: case (1), 5.4d for it
chain "test-guardian.sh sealed V3" "ship.sh --no-push 'fix(security): insecure randomness in TokenService.cs (V3, SEC-7)' '- Fortify 2003'" "ticket-sheet.sh tick 3 '/fortify V3 - corrigée - tests 0+1'"
check "resume (1): committed" 0 '^COMMIT: .*insecure randomness in TokenService.cs \(V3, SEC-7\)'

# ======================================================================================================================
# O. V4: a test that hangs; a wave cut before its proofs were parked: the resume of step 1, case (2)
# ======================================================================================================================
step "O. test bloqué, reprise avant rangement"
cat > tests/App.Tests/ReportSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.ReportSecurityTests.Security_PathManipulation_V4_Traversal hang -->
public class ReportSecurityTests
{
    [Fact]
    public void Security_PathManipulation_V4_Traversal() => Thread.Sleep(Timeout.Infinite);
}
EOF
out=$(TEST_GUARDIAN_HANG=$HANG_TIME "$SH" "$scripts/test-guardian.sh" red "$T" FullyQualifiedName~Security_PathManipulation_V4 2>&1); status=$?
check "a test that hangs: stopped and named" 1 '^STOP: a test ran more than [0-9]+[smh] and was stopped .*App.Tests.ReportSecurityTests.Security_PathManipulation_V4_Traversal'
cat > tests/App.Tests/ReportSecurityTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.ReportSecurityTests.Security_PathManipulation_V4_Traversal requires src/App/Report.cs:GetFullPath Assert.Throws() Failure: No exception was thrown -->
public class ReportSecurityTests
{
    [Fact]
    public void Security_PathManipulation_V4_Traversal() => Assert.Throws<ArgumentException>(() => Report.Export("../x"));
}
EOF
run test-guardian.sh red "$T" FullyQualifiedName~Security_PathManipulation_V4
check "bounded: RED" 0 '^RED: 1 tests fail'
run test-guardian.sh seal V4 tests/App.Tests/ReportSecurityTests.cs
etat "$B2" V4 "- tests : RED - contexte déjà couvert - test-guardian ses_w4"
# --- OpenCode restarts: V4 has « tests : » but neither « preuve rangée » nor « correctif »: case (2), park it
run test-guardian.sh park V4
check "resume (2): parked" 0 '^PARKED: 1 test files of the proof V4'
truth "resume (2): clean" 'clean'
chain "test-guardian.sh unpark V4" "test-guardian.sh red $T FullyQualifiedName~Security_PathManipulation_V4"
check "V4: red" 0 '^RED: 1 tests fail'
cat > src/App/Report.cs <<'EOF'
namespace App;

public static class Report
{
    public static string Export(string path)
    {
        var full = Path.GetFullPath(Path.Combine("/reports", path));
        if (!full.StartsWith("/reports/", StringComparison.Ordinal))
        {
            throw new ArgumentException("outside the reports folder", nameof(path));
        }
        return full;
    }
}
EOF
chain "test-guardian.sh green $T FullyQualifiedName~Security_PathManipulation_V4" "test-guardian.sh sealed V4" "ship.sh --no-push 'fix(security): path manipulation in Report.cs (V4, SEC-7)' '- Fortify 2004'" "ticket-sheet.sh tick 4 '/fortify V4 - corrigée - tests 0+1'"
check "V4: committed" 0 '^COMMIT: .*path manipulation in Report.cs \(V4, SEC-7\)'
# an unpark refused: a commit changed a file of the proof since it was parked
cat > tests/App.Tests/ExtraTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.ExtraTests.Security_PathManipulation_V9_X pass -->
public class ExtraTests
{
    [Fact]
    public void Security_PathManipulation_V9_X() => Assert.True(true);
}
EOF
run test-guardian.sh seal V9 tests/App.Tests/ExtraTests.cs
run test-guardian.sh park V9
printf 'namespace App.Tests;\n\npublic class ExtraTests\n{\n}\n' > tests/App.Tests/ExtraTests.cs
git add -A && git commit -q -m "test: extra"
run test-guardian.sh unpark V9
check "unpark refused when a commit changed the proof" 1 '^STOP: the proof V9 cannot come back as it was made: tests/App.Tests/ExtraTests.cs \(committed meanwhile\)'
git reset -q --hard HEAD~1

# delivery of batch 2: V2 not fixed, its stash named
run test-guardian.sh changes origin/develop App.sln
check "batch 2: the suite, the failure of develop only" 1 '^FAILED TESTS \(1\): App.Tests.LegacyTests.Old_Rounding$'
chain "ship.sh --sync-only --base" "ship.sh --base 'fix(security): Fortify batch app-api / develop (SEC-7)'"
check "batch 2: pushed" 0 '^PUSH: OK, origin/bugfix/SEC-7-fortify-weak-cryptographic-hash'
truth "batch 2: the stash of V2 still recoverable" 'git stash show -p "$STASH" | grep -q "sha1"'
cd "$work/api" || exit 1
git worktree remove --force "$work/wt"

# ======================================================================================================================
# P. discard and the stashes of two worktrees: each commit names its own work
# ======================================================================================================================
step "P. mises de côté de deux espaces de travail"
git switch -q -c bugfix/SEC-8-a origin/develop
echo "// a" >> src/App/Report.cs
run fortify.sh discard F1
SA=$(printf '%s\n' "$out" | sed -n 's/.*, commit \([0-9a-f]\{40\}\)\..*/\1/p')
git worktree add -q -b bugfix/SEC-9-b "$work/wt2" origin/develop 2>/dev/null
( cd "$work/wt2" && echo "// b" >> src/App/Report.cs && "$SH" "$scripts/fortify.sh" discard F1 > "$work/d2" 2>&1; echo $? > "$work/d2.s" )
got d2
check "the second worktree's discard" 0 '^DISCARDED: 1 files put aside in git stash « fortify SEC-9 F1 \(wt2\) »'
SB=$(printf '%s\n' "$out" | sed -n 's/.*, commit \([0-9a-f]\{40\}\)\..*/\1/p')
truth "the first stash, by its commit, still holds its own work" 'git stash show -p "$SA" | grep -q "^+// a"'
truth "the second, its own" 'git stash show -p "$SB" | grep -q "^+// b"'
run fortify.sh discard F2
check "nothing to put aside" 0 '^DISCARDED: nothing to put aside$'
git switch -q --detach origin/develop
run fortify.sh discard F3
check "detached HEAD: never" 1 '^STOP: not on a branch of its own \(detached HEAD\)'
git switch -q develop
run fortify.sh discard F3
check "develop: never" 1 '^STOP: not on a branch of its own \(develop\)'
git worktree remove --force "$work/wt2"

# ======================================================================================================================
# Q. The same proof on a Microsoft.Testing.Platform project (MSTest.Sdk, its coverage extension)
# ======================================================================================================================
step "Q. Microsoft.Testing.Platform"
gitlab "$work/core"
cd "$work/core" || exit 1
csproj src/Core/Core.csproj Microsoft.NET.Sdk
cat > src/Core/UrlHelper.cs <<'EOF'
namespace Core;

public static class UrlHelper
{
    public static string Next(string url) => url;
}
EOF
MT=tests/Core.Tests/Core.Tests.csproj
csproj "$MT" MSTest.Sdk/3.8.0 '<ProjectReference Include="../../src/Core/Core.csproj" />'
cat > tests/Core.Tests/UrlHelperTests.cs <<'EOF'
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Core.Tests;

// <!-- fake-test: Core.Tests.UrlHelperTests.Next_Local_Kept pass -->
[TestClass]
public class UrlHelperTests
{
    [TestMethod]
    public void Next_Local_Kept() => Assert.AreEqual("/home", UrlHelper.Next("/home"));
}
EOF
printf 'APPSEC_PROJECT_NAME=core-api\n' > appsec-ci.env
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m "chore: core" && git push -q origin develop 2>/dev/null
cover "src/Core/UrlHelper.cs 5:1"
run fortify.sh prereq
check "MTP: its coverage extension is enough" 0 "^PREREQ: test project $MT \(Microsoft.Testing.Platform, coverage: codecoverage\)$"
check "MTP: OK" 0 '^PREREQ: OK$'
chain "branch.sh LOCAL bugfix 'Fortify Open Redirect lot 2026-10-24'" "fortify.sh batch"
check "MTP: the batch" 0 '^BATCH: .*/opencode-tickets/LOCAL-1.fortify$'
run test-guardian.sh coverage V1-before "$MT" src/Core/UrlHelper.cs
check "MTP: coverage before, through its extension" 0 "^src/Core/UrlHelper.cs lines $(pick '1/1 \(100%\)' '[0-9]+/[0-9]+')"
cat > tests/Core.Tests/UrlHelperSecurityTests.cs <<'EOF'
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Core.Tests;

// <!-- fake-test: Core.Tests.UrlHelperSecurityTests.Security_OpenRedirect_V1_External requires src/Core/UrlHelper.cs:StartsWith Assert.AreEqual failed. Expected:</>. Actual:<https://evil.example>. -->
[TestClass]
public class UrlHelperSecurityTests
{
    [TestMethod]
    public void Security_OpenRedirect_V1_External() => Assert.AreEqual("/", UrlHelper.Next("https://evil.example"));
}
EOF
run test-guardian.sh red "$MT" FullyQualifiedName~Security_OpenRedirect_V1
check "MTP: RED, run as its application" 0 '^RED: 1 tests fail on the current code'
check "MTP: the reason" 0 'Security_OpenRedirect_V1_External: Assert.AreEqual failed'
chain "test-guardian.sh seal V1 tests/Core.Tests/UrlHelperSecurityTests.cs" "test-guardian.sh park V1"
check "MTP: sealed and parked" 0 '^PARKED: 1 test files of the proof V1'
chain "test-guardian.sh unpark V1" "test-guardian.sh red $MT FullyQualifiedName~Security_OpenRedirect_V1"
check "MTP: back and red" 0 '^RED: 1 tests fail'
cat > src/Core/UrlHelper.cs <<'EOF'
namespace Core;

public static class UrlHelper
{
    public static string Next(string url) => url.StartsWith('/') && !url.StartsWith("//", StringComparison.Ordinal) ? url : "/";
}
EOF
run test-guardian.sh green "$MT" FullyQualifiedName~Security_OpenRedirect_V1
check "MTP: green twice" 0 '^GREEN: 1 tests pass, twice$'
run test-guardian.sh coverage V1-after "$MT" src/Core/UrlHelper.cs
run test-guardian.sh compare V1-before V1-after
check "MTP: no loss" 0 '^COVERAGE: no file lost coverage$'
chain "test-guardian.sh sealed V1" "ship.sh --no-push 'fix(security): open redirect in UrlHelper.cs (V1, LOCAL-1)'"
check "MTP: committed" 0 '^COMMIT: .*open redirect in UrlHelper.cs'
truth "never dotnet run" '! grep -q "^dotnet run" "$FAKE_DOTNET_LOG"'

[ "$REAL" -eq 1 ] && dotnet build-server shutdown >/dev/null 2>&1
echo "fortify-test ($([ "$REAL" -eq 1 ] && echo "real dotnet $(dotnet --version), " || echo "fake dotnet, ")$SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
