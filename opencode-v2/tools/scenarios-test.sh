#!/bin/sh
# shellcheck disable=SC2034,SC2120 # variables read inside the eval of truth; sync_run takes options in other scenarios
# Scenarios of a developer's days with the pack, played at the level of its scripts: the scripts that /go, /fix,
# /push, /sync and /tests run, in the order their command files give, on several repositories (with and without unit
# tests, a build that passes or breaks, a branch up to date or behind its copy on GitLab, commits pushed from the Mac)
# and in two worktrees of one repository that work and push at the same time, each on its own branch. GitLab is a
# bare repository, the Mac a second clone; the part of the model (the code it writes, the names it chooses) is played
# here with fixed answers, real C# code and real xUnit tests. Each scenario checks what the developer sees and what
# git holds afterwards: nothing pushed when it must not be, nothing lost when it stops.
#   --real   with the dotnet of this machine (real builds and tests, NuGet packages from the feed of this machine):
#            run it on the machine of OpenCode; no repository, no git or NuGet setting of this machine is changed
#   (none)   with tools/fake-dotnet.sh, for a machine without the .NET SDK (the test files carry, in comments, what the
#            fake runs: the same results as their real code)
# Usage, from opencode-v2/: sh tools/scenarios-test.sh [--real] [<shell>] (default sh; dash and bash).
REAL=0
[ "$1" = --real ] && { REAL=1; shift; }
SHELL_UNDER_TEST=${1:-sh}
SH=$SHELL_UNDER_TEST
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
work=$(mktemp -d "${TMPDIR:-/tmp}/scenarios-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state" "$work/tmp" "$work/nodotnet"
FAKE_DOTNET_LOG="$work/dotnet.log"
if [ "$REAL" -eq 1 ]; then
  real_dotnet=$(command -v dotnet) || { echo "scenarios-test --real: dotnet is not on the PATH of this machine"; exit 2; }
  # every call logged, then the real one
  printf '#!/bin/sh\nprintf "dotnet %%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$FAKE_DOTNET_LOG" "$real_dotnet" > "$work/bin/dotnet"
  TFM="net$(dotnet --version | cut -d. -f1).0"
  MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
  export MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO
  echo "scenarios-test --real: $(dotnet --version) ($TFM), in $work"
else
  HOME="$work/home"
  mkdir -p "$HOME"
  export HOME
  cp "$pack/tools/fake-dotnet.sh" "$work/bin/dotnet"
  TFM=net10.0
fi
chmod +x "$work/bin/dotnet"
PATH="$work/bin:$PATH"
FAKE_DOTNET_STATE="$work/state"
TMPDIR="$work/tmp"
export PATH FAKE_DOTNET_LOG FAKE_DOTNET_STATE TMPDIR
# git: a global configuration of its own (git 2.32 and later), never the one of this machine, which is never written
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
printf '[init]\n\tdefaultBranch = develop\n[advice]\n\tdetachedHead = false\n[pull]\n\trebase = false\n' > "$GIT_CONFIG_GLOBAL"
# the tools of this machine without dotnet, for the case where it is missing
for f in /usr/local/bin/* /usr/bin/* /bin/*; do
  n=$(basename "$f")
  [ "$n" = dotnet ] || [ -e "$work/nodotnet/$n" ] || ln -s "$f" "$work/nodotnet/$n" 2>/dev/null
done

pass=0
fail=0
scenario=""
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
run() {
  script=$1
  shift
  : > "$FAKE_DOTNET_LOG"
  out=$("$SH" "$scripts/$script" "$@" 2>&1)
  status=$?
  calls=$(cat "$FAKE_DOTNET_LOG")
}
project() {
  mkdir -p "$(dirname "$1")"
  f=$1 sdk=$2
  shift 2
  { echo "<Project Sdk=\"$sdk\">"
    echo "  <PropertyGroup>"
    echo "    <TargetFramework>$TFM</TargetFramework>"
    echo "    <Nullable>enable</Nullable>"
    echo "    <ImplicitUsings>enable</ImplicitUsings>"
    echo "    <IsPackable>false</IsPackable>"
    echo "  </PropertyGroup>"
    for l in "$@"; do echo "  $l"; done
    echo "</Project>"; } > "$f"
}
# a solution file that MSBuild reads: sln <file> "<name> <path with backslashes> <guid>"...
sln() {
  f=$1
  shift
  specs=$(printf '%s\n' "$@")
  { echo "Microsoft Visual Studio Solution File, Format Version 12.00"
    echo "# Visual Studio Version 17"
    echo "VisualStudioVersion = 17.0.31903.59"
    echo "MinimumVisualStudioVersion = 10.0.40219.1"
    printf '%s\n' "$specs" | while read -r name path guid; do
      printf 'Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "%s", "%s", "{%s}"\nEndProject\n' "$name" "$path" "$guid"
    done
    printf 'Global\n\tGlobalSection(SolutionConfigurationPlatforms) = preSolution\n\t\tDebug|Any CPU = Debug|Any CPU\n\t\tRelease|Any CPU = Release|Any CPU\n\tEndGlobalSection\n'
    printf '\tGlobalSection(ProjectConfigurationPlatforms) = postSolution\n'
    printf '%s\n' "$specs" | while read -r name path guid; do
      for c in Debug Release; do
        printf '\t\t{%s}.%s|Any CPU.ActiveCfg = %s|Any CPU\n\t\t{%s}.%s|Any CPU.Build.0 = %s|Any CPU\n' "$guid" "$c" "$c" "$guid" "$c" "$c"
      done
    done
    printf '\tEndGlobalSection\nEndGlobal\n'; } > "$f"
}
on_origin() {
  # on_origin <repo.git> <branch>: the branch exists on "GitLab"
  git --git-dir="$1" rev-parse -q --verify "refs/heads/$2" >/dev/null
}

# ---------- the pilot's part, as the command files prescribe it ----------
# /push (commands/push.md): the state, nothing to push?, the build and tests of changed code (build-test.sh
# --if-changed), the branch when one is needed (the name the developer chose), ship.sh
push_run() {
  msg="" name="" base_flag="" tests=1 target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --msg) msg=$2; shift 2 ;;
      --name) name=$2; shift 2 ;;
      --base) base_flag=--base; shift ;;
      --no-tests) tests=0; shift ;;
      --target) target=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  : > "$FAKE_DOTNET_LOG"
  ws=$("$SH" "$scripts/workflow-state.sh" --no-fetch 2>&1)
  if printf '%s\n' "$ws" | grep -q '^Merge in progress: yes'; then out="⛔ merge in progress"; status=1; return; fi
  unc=$(printf '%s\n' "$ws" | sed -n '/^Uncommitted files/,/^Untracked files:/p' | sed '1d;$d')
  unt=$(printf '%s\n' "$ws" | sed -n '/^Untracked files:/,/^\(Files changed\|Existing ticket\)/p' | sed '1d;$d')
  if [ -z "$unc$unt" ] && printf '%s\n' "$ws" | grep -q '^Branch vs its remote copy.*: up to date'; then
    out="✅ Rien à pousser"; status=0; calls=""; return
  fi
  log=""
  # the files of the uncommitted changes and of the commits not pushed yet (since the base for a branch never pushed)
  since='@{upstream}'
  git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1 || since="origin/$("$SH" "$scripts/base.sh")"
  changed=$( { git status --porcelain | cut -c4-; git diff --name-only "$since..HEAD" 2>/dev/null; } |
    grep -vE '\.md$|^docs/|\.txt$|\.png$' )
  if [ "$tests" -eq 1 ] && [ -n "$changed" ]; then
    bt=$("$SH" "$scripts/build-test.sh" --if-changed $target 2>&1)
    log="$bt"
    if printf '%s\n' "$bt" | grep -qE '^BUILD: FAILED|^TESTS: FAILED|^ENVIRONMENT PROBLEM|^BUILD: NOT RUN'; then
      out="$log
⛔ Build ou tests en échec : rien n'est poussé"
      status=1
      calls=$(cat "$FAKE_DOTNET_LOG")
      return
    fi
  fi
  cur=$(git branch --show-current)
  case "$cur" in
    ""|develop|master|main|opencode/*)
      if ! br=$("$SH" "$scripts/branch.sh" --here --name "$name" 2>&1); then
        out="$log
$br"
        status=1
        calls=$(cat "$FAKE_DOTNET_LOG")
        return
      fi
      log="$log
$br" ;;
  esac
  sp=$("$SH" "$scripts/ship.sh" $base_flag "$msg" 2>&1)
  status=$?
  out="$log
$sp"
  calls=$(cat "$FAKE_DOTNET_LOG")
}
# /sync (commands/sync.md)
sync_run() {
  if [ -z "$(git branch --show-current)" ]; then out="⛔ HEAD détachée"; status=1; return; fi
  run ship.sh --sync-only "$@"
}
# /go (commands/go.md): the branch, the sheet the analyst writes, the measure of the base
go_start() {
  key=$1 summary=$2
  shift 2
  run branch.sh "$key" feature "$summary" "$@"
  [ "$status" -eq 0 ] || return
  started=$out
  case "$key" in LOCAL) key=$(printf '%s\n' "$out" | sed -n 's/^KEY: //p') ;; esac
  sheet=$("$SH" "$scripts/workflow-state.sh" --no-fetch --sheet 2>&1 | sed -n 's/^Current ticket sheet: none for [^ ]* (to be written at \(.*\))$/\1/p')
  if [ -n "$sheet" ]; then
    mkdir -p "$(dirname "$sheet")"
    printf '# %s - %s\n- Branche : %s\n\n## Plan\n- [ ] 1. %s\n\n## Décisions\n\n## Suivi\n' "$key" "$summary" "$(git branch --show-current)" "$summary" > "$sheet"
  fi
  run build-test.sh App.sln
  measure=$out
  out="$started
$measure"
}
# one plan step: the coder's edit, its tests, the commit and the tick
go_step() {
  msg=$1 edit=$2
  $edit
  run build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceTests
  [ "$status" -eq 0 ] || return
  run ship.sh --no-push "$msg"
  [ "$status" -eq 0 ] || return
  "$SH" "$scripts/ticket-sheet.sh" tick 1 "/go étape 1 - build ok" >/dev/null 2>&1
}
# the delivery: the whole suite with the coverage of the changes, then ship.sh --base
go_deliver() {
  msg=$1
  base=$("$SH" "$scripts/base.sh")
  run test-guardian.sh changes "origin/$base" App.sln
  delivered=$out
  run ship.sh --base "$msg"
  out="$delivered
$out"
}

# ---------- GitLab, the Mac, the machine of OpenCode: the repository "api", with its unit tests ----------
git init -q --bare "$work/api.git"
git --git-dir="$work/api.git" symbolic-ref HEAD refs/heads/develop
git clone -q "$work/api.git" "$work/seed" 2>/dev/null
cd "$work/seed" || exit 1
git checkout -q -b develop 2>/dev/null
project src/App/App.csproj Microsoft.NET.Sdk
printf 'namespace App;\npublic class Invoice\n{\n    public decimal Total(decimal amount) => amount;\n    public decimal Vat(decimal amount) => amount * 0.2m;\n}\n' > src/App/Invoice.cs
printf 'namespace App;\npublic class Order\n{\n    public int Lines => 0;\n}\n' > src/App/Order.cs
project tests/App.Tests/App.Tests.csproj Microsoft.NET.Sdk \
  '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '  <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />' \
  '  <PackageReference Include="coverlet.collector" Version="6.0.2" />' '  <ProjectReference Include="../../src/App/App.csproj" />' \
  '  <Using Include="Xunit" />' '</ItemGroup>' '<!-- fake-cover: src/App/Invoice.cs 4:1 5:1 -->'
# the tests of the team (a total stays positive whatever the business rule of the moment)
cat > tests/App.Tests/InvoiceTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.InvoiceTests.Total pass -->
// <!-- fake-test: App.Tests.InvoiceTests.Vat pass -->
public class InvoiceTests
{
    [Fact]
    public void Total() => Assert.True(new Invoice().Total(10m) > 0m);

    [Fact]
    public void Vat() => Assert.Equal(2m, new Invoice().Vat(10m));
}
EOF
cat > tests/App.Tests/OrderTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.OrderTests.Lines pass -->
public class OrderTests
{
    [Fact]
    public void Lines() => Assert.Equal(0, new Order().Lines);
}
EOF
sln App.sln 'App src\App\App.csproj 11111111-1111-1111-1111-111111111111' \
  'App.Tests tests\App.Tests\App.Tests.csproj 22222222-2222-2222-2222-222222222222'
printf '# API\n' > README.md
echo 'APPSEC_PROJECT_NAME=api' > appsec-ci.env
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init
git push -q origin develop
git push -q origin develop:master
git clone -q "$work/api.git" "$work/mac" 2>/dev/null
git clone -q "$work/api.git" "$work/api" 2>/dev/null
cd "$work/api" || exit 1

# ---------- 1. A ticket, from its branch to the push ----------
scenario="/go ABC-1"
go_start ABC-1 "Arrondi de la TVA"
check "the ticket branch from origin/develop" 0 '^BRANCH: feature/ABC-1-arrondi-tva \(created from origin/develop'
check "the measure of develop: green" 0 '^TESTS: OK$'
round_vat() { sed -i 's/amount \* 0.2m;/decimal.Round(amount * 0.2m, 2);/' src/App/Invoice.cs; }
go_step "fix(billing): round the VAT to the cent (ABC-1)" round_vat
check "the step: committed" 0 '^COMMIT: .* fix\(billing\): round the VAT to the cent \(ABC-1\)'
truth "the step: ticked in the sheet" 'grep -q "^- \[x\] 1\." .git/opencode-tickets/ABC-1.md'
go_deliver "fix(billing): round the VAT to the cent (ABC-1)"
check "delivery: the coverage of the changes" 0 '^COVERAGE OF THE CHANGES: '
check "delivery: checked, then pushed" 0 '^PUSH: OK, origin/feature/ABC-1-arrondi-tva'
check "delivery: the check before the push" 0 '^GUARD: OK'
truth "delivery: the branch is on GitLab" 'on_origin "$work/api.git" feature/ABC-1-arrondi-tva'

# ---------- 2. A ticket that starts from a teammate's branch, which moves on meanwhile ----------
scenario="/go ABC-2 depuis feature/ABC-1"
git switch -q develop
go_start ABC-2 "Remise sur la TVA arrondie" --from feature/ABC-1-arrondi-tva
check "the branch starts from the teammate's" 0 'BRANCH: feature/ABC-2-remise-tva-arrondie \(created from origin/feature/ABC-1-arrondi-tva'
check "its base is recorded" 0 '^BASE: origin/feature/ABC-1-arrondi-tva instead of origin/develop'
( cd "$work/mac" && git fetch -q && git switch -q feature/ABC-1-arrondi-tva && printf 'namespace App;\npublic static class Rates\n{\n    public const decimal Vat = 0.2m;\n}\n' > src/App/Rates.cs &&
  git add -A && git commit -q -m "feat: rates" && git push -q origin feature/ABC-1-arrondi-tva )
discount() { printf 'namespace App;\npublic class Discount\n{\n    public decimal Apply(decimal amount) => amount * 0.9m;\n}\n' > src/App/Discount.cs; }
go_step "feat(billing): apply the discount (ABC-2)" discount
go_deliver "feat(billing): apply the discount (ABC-2)"
check "delivery: the new commits of the base merged first" 0 '^BASE: the 1 new commits of origin/feature/ABC-1-arrondi-tva merged'
check "delivery: checked against the base, then pushed" 0 '^PUSH: OK, origin/feature/ABC-2-remise-tva-arrondie'
truth "the teammate's file is in the branch" '[ -f src/App/Rates.cs ]'

# ---------- 3. A POC on develop, pushed without a merge request ----------
scenario="/push d'un POC"
git switch -q develop
git merge -q --ff-only origin/develop
printf 'namespace App;\npublic class Cache\n{\n}\n' > src/App/Cache.cs
push_run --name poc/essai-cache --msg "feat(cache): try an in-memory cache"
check "built and tested before the commit" 0 '^TESTS: OK$'
check "its own branch, from develop" 0 '^BRANCH: poc/essai-cache \(created from develop'
check "pushed" 0 '^PUSH: OK, origin/poc/essai-cache'
truth "develop has nothing of it" '[ "$(git rev-parse develop)" = "$(git rev-parse origin/develop)" ]'
push_run --msg "anything"
check "nothing more to push" 0 '^✅ Rien à pousser'

# ---------- 4. Documentation only: no build ----------
scenario="/push de la doc"
git switch -q develop
printf '# API\n\nHow to run it.\n' > README.md
push_run --name docs/readme-run --msg "docs: explain how to run the API"
check "pushed" 0 '^PUSH: OK, origin/docs/readme-run'
truth "no build, no test for a documentation change" '[ -z "$calls" ]'

# ---------- 5. The build breaks, then the tests: nothing pushed, nothing lost ----------
scenario="/push qui casse"
git switch -q develop
printf 'namespace App;\n\n// <!-- fake-build-error -->\npublic class Broken\n{\n    public int X() => ;\n}\n' > src/App/Broken.cs
before=$(git rev-parse HEAD)
push_run --name feature/wip-broken --msg "feat: broken"
check "stopped by the build" 1 '^BUILD: FAILED'
truth "nothing committed" '[ "$(git rev-parse HEAD)" = "$before" ] && [ "$(git branch --show-current)" = develop ]'
truth "the change is still there" '[ -f src/App/Broken.cs ]'
truth "nothing on GitLab" '! on_origin "$work/api.git" feature/wip-broken'
push_run --name feature/wip-broken --msg "wip: broken build, to finish" --no-tests
check "« sans les tests »: pushed anyway, a work in progress" 0 '^PUSH: OK, origin/feature/wip-broken'
git switch -q develop
sed -i 's/OrderTests.Lines pass/OrderTests.Lines fail Assert.Equal() Failure: Values differ/; s/Assert.Equal(0, new Order().Lines)/Assert.Equal(1, new Order().Lines)/' tests/App.Tests/OrderTests.cs
push_run --name feature/red-test --msg "test: a red test"
check "stopped by a red test, named" 1 '^FAILED TESTS \(1\): App.Tests.OrderTests.Lines$'
truth "nothing committed, nothing on GitLab" '[ "$(git branch --show-current)" = develop ] && ! on_origin "$work/api.git" feature/red-test'
git checkout -q -- .

# ---------- 6. The code that just passed in the conversation is not built again ----------
scenario="/push après un build vert"
git switch -q develop
printf 'namespace App;\npublic class Report\n{\n}\n' > src/App/Report.cs
run build-test.sh
check "the conversation built and tested it" 0 '^TESTS: OK$'
push_run --name feature/report --msg "feat(report): add the report class"
check "not built again" 0 'not run again: this same code passed'
truth "no dotnet call at all" '[ -z "$calls" ]'
check "pushed" 0 '^PUSH: OK, origin/feature/report'

# ---------- 7. Commits pushed from the Mac, local work here ----------
scenario="Mac + /push"
git switch -q poc/essai-cache
( cd "$work/mac" && git fetch -q && git switch -q poc/essai-cache && printf 'namespace App;\npublic class CacheKey\n{\n}\n' > src/App/CacheKey.cs &&
  git add -A && git commit -q -m "feat: cache key from the Mac" && git push -q origin poc/essai-cache )
printf 'namespace App;\npublic class Cache\n{\n    public int Size => 1;\n}\n' > src/App/Cache.cs
push_run --msg "feat(cache): give the cache a size"
check "the Mac's commit merged before the push" 0 '^REMOTE: the 1 commits of origin/poc/essai-cache merged'
check "pushed" 0 '^PUSH: OK, origin/poc/essai-cache'
truth "both changes on GitLab" 'git --git-dir="$work/api.git" show poc/essai-cache:src/App/CacheKey.cs >/dev/null && git --git-dir="$work/api.git" show poc/essai-cache:src/App/Cache.cs | grep -q Size'

scenario="Mac + /push en conflit"
( cd "$work/mac" && git pull -q origin poc/essai-cache && sed -i 's/Size => 1;/Size => 2;/' src/App/Cache.cs && git commit -q -am "fix: size 2 from the Mac" && git push -q origin poc/essai-cache )
sed -i 's/Size => 1;/Size => 3;/' src/App/Cache.cs
push_run --msg "fix(cache): size 3"
check "the conflict stops the push, with its file" 1 'STOP: CONFLICT while merging .* in src/App/Cache.cs: merge aborted, nothing is lost'
truth "the local commit is kept" 'git log -1 --format=%s | grep -q "size 3"'
truth "no merge left half done" '[ ! -f .git/MERGE_HEAD ] && [ -z "$(git status --porcelain)" ]'
truth "GitLab still has the Mac's version" 'git --git-dir="$work/api.git" show poc/essai-cache:src/App/Cache.cs | grep -q "Size => 2"'
# the developer resolves it in Rider
git merge -q origin/poc/essai-cache >/dev/null 2>&1
sed -i '/^<<<<<<<\|^=======\|^>>>>>>>/d; /Size => 2;/d' src/App/Cache.cs
git add -A && git commit -q -m "Merge the Mac's size" >/dev/null
push_run --msg "anything"
check "after the resolution: pushed" 0 '^PUSH: OK, origin/poc/essai-cache'

# ---------- 8. /sync: from the Mac, with work in progress here ----------
scenario="/sync"
( cd "$work/mac" && git pull -q origin poc/essai-cache && printf 'namespace App;\npublic class CacheStats\n{\n}\n' > src/App/CacheStats.cs &&
  git add -A && git commit -q -m "feat: stats from the Mac" && git push -q origin poc/essai-cache )
printf 'namespace App;\npublic class CacheTtl\n{\n}\n' > src/App/CacheTtl.cs
sync_run
check "the Mac's commits brought in" 0 '^REMOTE: 1 commits of origin/poc/essai-cache brought in'
check "nothing committed or pushed" 0 '^RESULT: OK \(synchronized, nothing committed or pushed\)'
truth "the work in progress is still there, not committed" '[ -f src/App/CacheTtl.cs ] && git status --porcelain | grep -q CacheTtl.cs'
( cd "$work/mac" && git pull -q origin poc/essai-cache && printf 'namespace App;\npublic class CacheTtl\n{\n    public int Seconds => 60;\n}\n' > src/App/CacheTtl.cs &&
  git add -A && git commit -q -m "feat: ttl from the Mac" && git push -q origin poc/essai-cache )
sync_run
check "the same file changed here: git refuses, says why" 1 'STOP: git refused to bring the 1 commits of origin/poc/essai-cache: .*(untracked working tree files would be overwritten|would be overwritten)'
truth "the work here is untouched" 'grep -q "class CacheTtl" src/App/CacheTtl.cs && ! grep -q Seconds src/App/CacheTtl.cs'
rm -f src/App/CacheTtl.cs
sync_run
check "then it comes in" 0 '^REMOTE: 1 commits of origin/poc/essai-cache brought in'

scenario="/sync sur develop"
git switch -q develop
( cd "$work/mac" && git switch -q develop && git pull -q origin develop && printf '# API\n\nChangelog.\n' > CHANGELOG.md && git add -A &&
  git commit -q -m "docs: changelog" && git push -q origin develop )
sync_run
check "develop brought to origin by fast-forward" 0 '^REMOTE: [0-9]+ commits of origin/develop brought in'
truth "develop is origin/develop" '[ "$(git rev-parse develop)" = "$(git rev-parse origin/develop)" ]'

# ---------- 9. A commit made on develop by mistake: /push gives it a branch and frees develop ----------
scenario="commit sur develop"
printf 'namespace App;\npublic class Audit\n{\n}\n' > src/App/Audit.cs
git add -A && git commit -q -m "feat: audit, committed on develop by mistake"
( cd "$work/mac" && git pull -q origin develop && printf '# API\n\nChangelog, v2.\n' > CHANGELOG.md && git commit -q -am "docs: changelog v2" && git push -q origin develop )
sync_run
check "/sync refuses to merge into develop" 1 'STOP: the local develop has 1 commits that origin/develop does not have: nothing was merged; /push puts them on a branch'
push_run --name feature/audit --msg "feat(audit): add the audit class"
check "the commit goes to the new branch" 0 '^MOVED: the 1 commits of develop that origin/develop does not have are on feature/audit now; develop is back at origin/develop'
check "pushed" 0 '^PUSH: OK, origin/feature/audit'
truth "develop is origin/develop again" '[ "$(git rev-parse develop)" = "$(git rev-parse origin/develop)" ]'
truth "the commit is on GitLab" 'git --git-dir="$work/api.git" log --format=%s feature/audit | grep -q "audit, committed on develop"'

# ---------- 10. A secret: never pushed, even removed by a later commit ----------
scenario="un secret"
git switch -q develop
printf 'namespace App;\npublic static class Keys\n{\n    public const string Aws = "AKIAIOSFODNN7EXAMPLE";\n}\n' > src/App/Keys.cs
push_run --name feature/keys --msg "feat: keys"
check "the check before the push stops it" 1 '^GUARD: STOP'
truth "nothing on GitLab" '! on_origin "$work/api.git" feature/keys'
printf 'namespace App;\npublic static class Keys\n{\n}\n' > src/App/Keys.cs
push_run --msg "fix: remove the key"
check "removed by a later commit: still stopped (the history is pushed too)" 1 '^GUARD: STOP'
truth "still nothing on GitLab" '! on_origin "$work/api.git" feature/keys'
git switch -q develop
git branch -q -D feature/keys

# ---------- 11. No dotnet on the PATH: an environment problem, never a code problem ----------
scenario="dotnet absent"
git switch -q develop
printf 'namespace App;\npublic class Export\n{\n}\n' > src/App/Export.cs
saved=$PATH
# shellcheck disable=SC2123 # on purpose: the tools of this machine, without dotnet
PATH="$work/nodotnet"
push_run --name feature/export --msg "feat: export"
check "stopped, an environment problem" 1 '^ENVIRONMENT PROBLEM: dotnet is not in the PATH'
push_run --name feature/export --msg "feat(export): add the export class" --no-tests
check "« sans les tests »: pushed, the CI builds it" 0 '^PUSH: OK, origin/feature/export'
PATH=$saved

# ---------- 12. /fix on a branch without a ticket, after its CI ----------
scenario="/fix sans ticket"
git switch -q poc/essai-cache
( cd "$work/mac" && git switch -q develop && git pull -q origin develop && printf 'namespace App;\npublic class Health\n{\n}\n' > src/App/Health.cs &&
  git add -A && git commit -q -m "feat: health on develop" && git push -q origin develop )
run ship.sh --sync-only --base
check "the new commits of develop merged first" 0 '^BASE: the [0-9]+ new commits of origin/develop merged'
sed -i 's/Size => 3;/Size => 4;/' src/App/Cache.cs
run ship.sh --no-push "fix(cache): size 4 after the review"
check "the fix committed, without a key" 0 '^COMMIT: .* fix\(cache\): size 4 after the review'
run test-guardian.sh folder
check "its own measures folder" 0 'FOLDER: .*/opencode-tickets/poc-essai-cache.tests$'
run test-guardian.sh changes origin/develop App.sln
check "the suite and the coverage of the changes" 0 '^TESTS: OK$'
run ship.sh --base "fix(cache): address the review"
check "pushed" 0 '^PUSH: OK, origin/poc/essai-cache'

# ---------- 13. A repository without unit tests: /push builds, /tests creates them ----------
scenario="sans tests"
git init -q --bare "$work/lib.git"
git --git-dir="$work/lib.git" symbolic-ref HEAD refs/heads/develop
git clone -q "$work/lib.git" "$work/lib-seed" 2>/dev/null
cd "$work/lib-seed" || exit 1
git checkout -q -b develop 2>/dev/null
project src/Lib/Lib.csproj Microsoft.NET.Sdk
printf 'namespace Lib;\npublic static class Slug\n{\n    public static string Of(string s) => s.ToLowerInvariant();\n}\n' > src/Lib/Slug.cs
sln Lib.sln 'Lib src\Lib\Lib.csproj 33333333-3333-3333-3333-333333333333'
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init && git push -q origin develop
git clone -q "$work/lib.git" "$work/lib" 2>/dev/null
cd "$work/lib" || exit 1
printf 'namespace Lib;\npublic static class Slug\n{\n    public static string Of(string s) => s.Trim().ToLowerInvariant();\n}\n' > src/Lib/Slug.cs
push_run --name bugfix/slug-trim --msg "fix(slug): trim the text first"
check "built, no test project: said, not a failure" 0 '^TESTS: NONE RUN \(no test project for this target\)$'
check "pushed" 0 '^PUSH: OK, origin/bugfix/slug-trim'
run build-test.sh --if-changed
check "the same code without tests: not built again, and why" 0 '^TESTS: NONE RUN \(not run again: same code, same target and options; no test project for this target\)$'
truth "no dotnet call" '[ -z "$calls" ]'
# a memory written by the previous version of the pack (without the reason): the general reason
g="$(git rev-parse --absolute-git-dir)/opencode-green"
head -n 3 "$g" > "$g.old" && mv "$g.old" "$g"
run build-test.sh --if-changed
check "a memory of the previous pack: the general reason" 0 '^TESTS: NONE RUN \(not run again: same code, same target and options; no test project for this target, or no test matches the filter\)$'
git switch -q develop
printf 'namespace Lib;\npublic static class Slug\n{\n    public static string Of(string s) => s.Trim().ToLowerInvariant().Replace(" ", "-");\n}\n' > src/Lib/Slug.cs
run fortify.sh prereq --tests
check "/tests: no test project yet" 0 '^PREREQ: NO TEST PROJECT'
# the developer's work in progress first, in its own commit, on a branch named after it (tests.md, step 1 and 3)
run branch.sh --here feature "slug with hyphens"
check "/tests: the branch of the work in progress" 0 '^BRANCH: feature/slug-hyphens \(created from develop'
run ship.sh --no-push "feat(slug): join the words with hyphens"
check "/tests: the work in progress committed alone" 0 '^COMMIT: .* feat\(slug\): join the words with hyphens'
run test-guardian.sh setup xunit src/Lib/Slug.cs
check "/tests: the test project created" 0 "^SETUP: tests/Lib.UnitTests/Lib.UnitTests.csproj created \\(xunit, $TFM\\)"
run ship.sh --no-push "test: add the unit test project"
check "/tests: its own commit" 0 '^COMMIT: .* test: add the unit test project'
# the test-guardian's tests (mission « tests »), then its proof and the commit
sed -i 's#</Project>#  <!-- fake-cover: src/Lib/Slug.cs 4:1 -->\n</Project>#' tests/Lib.UnitTests/Lib.UnitTests.csproj
cat > tests/Lib.UnitTests/SlugTests.cs <<'EOF'
namespace Lib.UnitTests;

// <!-- fake-test: Lib.UnitTests.SlugTests.Of_TrimsAndJoins pass -->
public class SlugTests
{
    [Xunit.Fact]
    public void Of_TrimsAndJoins() => Xunit.Assert.Equal("a-b", Slug.Of(" A B "));
}
EOF
run test-guardian.sh green tests/Lib.UnitTests/Lib.UnitTests.csproj FullyQualifiedName~SlugTests
check "/tests: green twice" 0 '^GREEN: 1 tests pass, twice$'
run test-guardian.sh tests-only
check "/tests: only test files changed" 0 '^TESTS-ONLY: OK$'
run ship.sh --no-push "test(slug): add unit tests of the slug"
check "/tests: the tests committed" 0 '^COMMIT: .* test\(slug\): add unit tests of the slug'
truth "/tests: three commits in order, nothing pushed" '[ "$(git log --format=%s origin/develop..HEAD | tr "\n" "|")" = "test(slug): add unit tests of the slug|test: add the unit test project|feat(slug): join the words with hyphens|" ] && ! on_origin "$work/lib.git" feature/slug-hyphens'
push_run --msg "anything"
check "/push: built and tested now that tests exist" 0 '^TESTS: OK$'
check "/push: pushed" 0 '^PUSH: OK, origin/feature/slug-hyphens'

# ---------- 14. Two worktrees of one repository, at the same time, each on its own branch ----------
scenario="deux worktrees"
cd "$work/api" || exit 1
git switch -q develop && git merge -q --ff-only origin/develop 2>/dev/null
git worktree add -q --detach "$work/wt1" origin/develop
git worktree add -q --detach "$work/wt2" origin/develop
# two /go started at the same moment, one in each worktree
( cd "$work/wt1" && "$SH" "$scripts/branch.sh" ABC-10 feature "Remise client" > "$work/o1" 2>&1; echo $? > "$work/o1.s" ) &
( cd "$work/wt2" && "$SH" "$scripts/branch.sh" ABC-11 feature "Frais de port" > "$work/o2" 2>&1; echo $? > "$work/o2.s" ) &
wait
got() { out=$(cat "$work/$1"); status=$(cat "$work/$1.s"); }
got o1
check "worktree 1: its ticket branch" 0 '^BRANCH: feature/ABC-10-remise-client \(created from origin/develop'
got o2
check "worktree 2: its ticket branch" 0 '^BRANCH: feature/ABC-11-frais-port \(created from origin/develop'
# both change the same line of Invoice.cs, and each its own file
( cd "$work/wt1" && sed -i 's/=> amount;/=> amount * 0.95m;/' src/App/Invoice.cs && printf 'namespace App;\npublic class Customer\n{\n}\n' > src/App/Customer.cs )
( cd "$work/wt2" && sed -i 's/=> amount;/=> amount + 4.9m;/' src/App/Invoice.cs && printf 'namespace App;\npublic class Shipping\n{\n}\n' > src/App/Shipping.cs )
# their builds at the same time: one lock per worktree, so neither waits for the other
( cd "$work/wt1" && "$SH" "$scripts/build-test.sh" > "$work/b1" 2>&1; echo $? > "$work/b1.s" ) &
( cd "$work/wt2" && "$SH" "$scripts/build-test.sh" > "$work/b2" 2>&1; echo $? > "$work/b2.s" ) &
wait
got b1
check "worktree 1: built and tested, without waiting" 0 '^TESTS: OK$' 'WAIT:'
got b2
check "worktree 2: built and tested, without waiting" 0 '^TESTS: OK$' 'WAIT:'
# two builds in ONE worktree: the second waits for the first
( cd "$work/wt1" && FAKE_DOTNET_SLOW=1 "$SH" "$scripts/build-test.sh" > "$work/b3" 2>&1; echo $? > "$work/b3.s" ) &
sleep 1
( cd "$work/wt1" && "$SH" "$scripts/build-test.sh" > "$work/b4" 2>&1; echo $? > "$work/b4.s" ) &
wait
got b3
check "one worktree, two builds: the first runs" 0 '^TESTS: OK$'
got b4
check "one worktree, two builds: the second waits, then runs" 0 '^WAIT: another build or test run of this folder is in progress'
check "one worktree, two builds: the second passes too" 0 '^TESTS: OK$'
# their sheets and measures never meet
truth "two measures folders" '[ "$(cd "$work/wt1" && "$SH" "$scripts/test-guardian.sh" folder)" != "$(cd "$work/wt2" && "$SH" "$scripts/test-guardian.sh" folder)" ]'
printf '# ABC-11 - Frais de port\n## Plan\n- [ ] 1. x\n' > .git/opencode-tickets/ABC-11.md
out=$(cd "$work/wt2" && "$SH" "$scripts/workflow-state.sh" --no-fetch --sheet 2>&1)
check "worktree 2 sees its own sheet" 0 '^Current ticket sheet: .*/opencode-tickets/ABC-11.md$'
check "worktree 2: a worktree, folder wt2" 0 '^Worktree: yes, folder wt2'
# the same ticket in the other worktree: refused, one ticket per worktree
out=$(cd "$work/wt2" && git stash -q -u && "$SH" "$scripts/branch.sh" ABC-10 feature "Remise client" 2>&1; status=$?; git stash pop -q; exit $status)
status=$?
check "the ticket of worktree 1 refused in worktree 2" 1 'STOP: the branch feature/ABC-10-remise-client is open in another worktree'
# both commit and push at the same time, each its own branch
( cd "$work/wt1" && "$SH" "$scripts/ship.sh" --base "feat(billing): customer discount (ABC-10)" > "$work/p1" 2>&1; echo $? > "$work/p1.s" ) &
( cd "$work/wt2" && "$SH" "$scripts/ship.sh" --base "feat(billing): shipping costs (ABC-11)" > "$work/p2" 2>&1; echo $? > "$work/p2.s" ) &
wait
got p1
check "worktree 1: pushed" 0 '^PUSH: OK, origin/feature/ABC-10-remise-client'
got p2
check "worktree 2: pushed" 0 '^PUSH: OK, origin/feature/ABC-11-frais-port'
truth "both branches on GitLab" 'on_origin "$work/api.git" feature/ABC-10-remise-client && on_origin "$work/api.git" feature/ABC-11-frais-port'
# the merge request of worktree 1 is merged into develop (GitLab): worktree 2 changed the same line
( cd "$work/mac" && git switch -q develop && git pull -q origin develop && git fetch -q origin &&
  git merge -q --no-ff -m "Merge ABC-10" origin/feature/ABC-10-remise-client && git push -q origin develop )
out=$(cd "$work/wt2" && "$SH" "$scripts/ship.sh" --sync-only --base 2>&1)
status=$?
check "worktree 2: the conflict with develop, aborted, its file named" 1 'STOP: CONFLICT while merging the [0-9]+ new commits of develop .* in src/App/Invoice.cs: merge aborted, nothing is lost'
truth "worktree 2: clean, nothing lost" '(cd "$work/wt2" && [ -z "$(git status --porcelain)" ] && [ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ] && grep -q "4.9m" src/App/Invoice.cs)'
# the developer resolves it in Rider, then /push
( cd "$work/wt2" && git merge -q origin/develop >/dev/null 2>&1; sed -i '/^<<<<<<<\|^=======\|^>>>>>>>/d; /0.95m/d' src/App/Invoice.cs && git add -A && git commit -q -m "Merge develop" )
out=$(cd "$work/wt2" && "$SH" "$scripts/ship.sh" "merge develop (ABC-11)" 2>&1)
status=$?
check "worktree 2: after the resolution, pushed" 0 '^PUSH: OK, origin/feature/ABC-11-frais-port'
# two /go without a ticket started at the same moment: two different keys
( cd "$work/wt1" && git switch -q --detach origin/develop && "$SH" "$scripts/branch.sh" LOCAL feature "Essai A" > "$work/l1" 2>&1 ) &
( cd "$work/wt2" && git switch -q --detach origin/develop && "$SH" "$scripts/branch.sh" LOCAL feature "Essai B" > "$work/l2" 2>&1 ) &
wait
k1=$(sed -n 's/^KEY: //p' "$work/l1")
k2=$(sed -n 's/^KEY: //p' "$work/l2")
truth "two /go without a ticket at the same moment: two keys ($k1, $k2)" '[ -n "$k1" ] && [ -n "$k2" ] && [ "$k1" != "$k2" ]'
# two POCs pushed at the same moment from two detached worktrees
( cd "$work/wt1" && git switch -q --detach origin/develop && printf 'x\n' > poc1.txt && printf 'namespace App;\npublic class Poc1\n{\n}\n' > src/App/Poc1.cs )
( cd "$work/wt2" && git switch -q --detach origin/develop && printf 'namespace App;\npublic class Poc2\n{\n}\n' > src/App/Poc2.cs )
( cd "$work/wt1" && push_run --name poc/idee-une --msg "feat: idea one"; printf '%s\n' "$out" > "$work/q1"; echo "$status" > "$work/q1.s" ) &
( cd "$work/wt2" && push_run --name poc/idee-deux --msg "feat: idea two"; printf '%s\n' "$out" > "$work/q2"; echo "$status" > "$work/q2.s" ) &
wait
got q1
check "worktree 1: its POC pushed" 0 '^PUSH: OK, origin/poc/idee-une'
got q2
check "worktree 2: its POC pushed" 0 '^PUSH: OK, origin/poc/idee-deux'
# /sync in a worktree still detached
( cd "$work/wt1" && git switch -q --detach origin/develop )
out=$(cd "$work/wt1" && sync_run; printf '%s' "$out")
check "/sync on a detached worktree: says so" 0 'HEAD détachée'
git worktree remove --force "$work/wt1"
git worktree remove --force "$work/wt2"

# ---------- 15. A ticket started on the Mac; a workspace opened on a feature branch ----------
scenario="branche du Mac"
cd "$work/api" || exit 1
git switch -q develop
( cd "$work/mac" && git switch -q develop && git pull -q origin develop && git switch -q -c feature/ABC-20-import-mac &&
  printf 'namespace App;\npublic class Import\n{\n}\n' > src/App/Import.cs && git add -A && git commit -q -m "feat: import, started on the Mac" &&
  git push -q -u origin feature/ABC-20-import-mac )
run branch.sh ABC-20 feature "Import"
check "/go on a ticket started on the Mac: its branch from GitLab" 0 '^BRANCH: feature/ABC-20-import-mac \(switched, from origin/feature/ABC-20-import-mac pushed from another computer\)'
truth "the Mac's work is here" '[ -f src/App/Import.cs ]'
git switch -q develop
git worktree add -q --detach "$work/wt3" origin/feature/ABC-20-import-mac
out=$(cd "$work/wt3" && printf 'namespace App;\npublic class Idea\n{\n}\n' > src/App/Idea.cs && "$SH" "$scripts/branch.sh" --here --name poc/idee 2>&1)
status=$?
check "a POC in a workspace opened on a feature branch: its commits come along, said so" 0 '^WARNING: the detached HEAD was 1 commits ahead of origin/develop \(the commits of .*feature/ABC-20-import-mac.*\): they are in poc/idee, and in its merge request'
git worktree remove --force "$work/wt3"
git branch -q -D poc/idee

# ---------- 16. Four worktrees fetching at the same moment while GitLab moves: never a failed fetch ----------
scenario="fetchs simultanés"
cd "$work/api" || exit 1
for w in 1 2 3 4; do git worktree add -q --detach "$work/f$w" origin/develop; done
( cd "$work/mac" && git switch -q develop && for i in 1 2 3 4 5 6 7 8 9 10 11 12; do git push -q origin "HEAD:refs/heads/team/b$i"; done )
failed=0
for round in 1 2 3; do
  ( cd "$work/mac" && for i in 1 2 3 4 5 6 7 8 9 10 11 12; do git commit -q --allow-empty -m "move $round $i"; git push -q -f origin "HEAD:refs/heads/team/b$i"; done )
  for w in 1 2 3 4; do
    ( cd "$work/f$w" && "$SH" "$scripts/fetch.sh" -q --no-tags origin 2> "$work/fe$w"; echo $? > "$work/fe$w.s" ) &
  done
  wait
  for w in 1 2 3 4; do [ "$(cat "$work/fe$w.s")" = 0 ] || { failed=$((failed + 1)); sed 's/^/    /' "$work/fe$w"; }; done
done
truth "12 fetches of 4 worktrees at the same moment: none failed ($failed)" '[ "$failed" -eq 0 ]'
for w in 1 2 3 4; do git worktree remove --force "$work/f$w"; done

# ---------- 17. A legacy .NET Framework repository: recognized, never built here ----------
scenario="legacy"
mkdir -p "$work/legacy/src/Web" && cd "$work/legacy" && git init -q
printf '<Project ToolsVersion="15.0">\n  <PropertyGroup>\n    <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>\n  </PropertyGroup>\n</Project>\n' > src/Web/Web.csproj
printf '<%%@ Page Language="C#" %%>\n' > src/Web/Default.aspx
git add -A && git commit -q -m init
run detect-project-type.sh
check "the detection says legacy (/push does not build it)" 0 'legacy'

# ---------- 18. /go: a step « (filet d'abord) »: the safety net of a refactoring, and the regression it catches ----------
scenario="/go ABC-5 (filet d'abord)"
git init -q --bare "$work/billing.git"
git --git-dir="$work/billing.git" symbolic-ref HEAD refs/heads/develop
git clone -q "$work/billing.git" "$work/billing" 2>/dev/null
cd "$work/billing" || exit 1
git checkout -q -b develop 2>/dev/null
project src/App/App.csproj Microsoft.NET.Sdk
# a discount that no test runs yet (a teammate's code)
cat > src/App/Invoice.cs <<'EOF'
namespace App;
public class Invoice
{
    public decimal Total(decimal amount) => amount;
    public decimal Vat(decimal amount) => amount * 0.2m;
    public decimal Discount(decimal amount, int percent)
    {
        if (percent <= 0)
        {
            return amount;
        }
        return amount - amount * percent / 100m;
    }
}
EOF
# what the tests of the team run (for the fake: the lines of Discount before and after it is rewritten)
project tests/App.Tests/App.Tests.csproj Microsoft.NET.Sdk \
  '<ItemGroup>' '  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />' \
  '  <PackageReference Include="xunit" Version="2.9.2" />' '  <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />' \
  '  <PackageReference Include="coverlet.collector" Version="6.0.2" />' '  <ProjectReference Include="../../src/App/App.csproj" />' \
  '  <Using Include="Xunit" />' '</ItemGroup>' \
  '<!-- fake-cover: src/App/Invoice.cs c=App.Invoice m=Total 4:1 m=Vat 5:1 -->' \
  '<!-- fake-cover: src/App/Invoice.cs if=src/App/Invoice.cs:return c=App.Invoice m=Discount 7:0 8:0:0/2 9:0 10:0 11:0 12:0 13:0 -->' \
  '<!-- fake-cover: src/App/Invoice.cs unless=src/App/Invoice.cs:return c=App.Invoice m=Discount 6:0:0/2 -->'
cat > tests/App.Tests/InvoiceTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.InvoiceTests.Total pass -->
// <!-- fake-test: App.Tests.InvoiceTests.Vat pass -->
public class InvoiceTests
{
    [Fact]
    public void Total() => Assert.True(new Invoice().Total(10m) > 0m);

    [Fact]
    public void Vat() => Assert.Equal(2m, new Invoice().Vat(10m));
}
EOF
sln App.sln 'App src\App\App.csproj 11111111-1111-1111-1111-111111111111' \
  'App.Tests tests\App.Tests\App.Tests.csproj 22222222-2222-2222-2222-222222222222'
printf 'bin/\nobj/\n' > .gitignore
git add -A && git commit -q -m init && git push -q origin develop
git branch -q -u origin/develop
go_start ABC-5 "Remise en une expression"
check "the ticket branch" 0 '^BRANCH: feature/ABC-5-remise-expression'
# the step of the analyst ends with « (filet d'abord) »: the test-guardian, mission « filet », phase « avant la modification »
T5=tests/App.Tests/App.Tests.csproj
run test-guardian.sh coverage S1-before "$T5" src/App/Invoice.cs
run test-guardian.sh net S1-before src/App/Invoice.cs:Discount
check "the net of the method to rewrite: no test runs it" 0 '^SAFETY NET: THIN \(0/[0-9]+ lines of this method run by the tests, 0% < 80%\)'
cat > tests/App.Tests/InvoiceDiscountTests.cs <<'EOF'
namespace App.Tests;

// <!-- fake-test: App.Tests.InvoiceDiscountTests.Discount_TenPercent_TakesTenOff pass -->
// <!-- fake-test: App.Tests.InvoiceDiscountTests.Discount_ZeroPercent_Unchanged pass -->
// <!-- fake-test: App.Tests.InvoiceDiscountTests.Discount_NegativePercent_Unchanged requires src/App/Invoice.cs:<= Assert.Equal() Failure: Values differ -->
// <!-- fake-cover: src/App/Invoice.cs if=src/App/Invoice.cs:return c=App.Invoice m=Discount 7:1 8:1:2/2 9:1 10:1 11:1 12:1 13:1 -->
// <!-- fake-cover: src/App/Invoice.cs unless=src/App/Invoice.cs:return c=App.Invoice m=Discount 6:1:2/2 -->
public class InvoiceDiscountTests
{
    [Fact]
    public void Discount_TenPercent_TakesTenOff() => Assert.Equal(90m, new Invoice().Discount(100m, 10));

    [Fact]
    public void Discount_ZeroPercent_Unchanged() => Assert.Equal(100m, new Invoice().Discount(100m, 0));

    [Fact]
    public void Discount_NegativePercent_Unchanged() => Assert.Equal(100m, new Invoice().Discount(100m, -5));
}
EOF
run test-guardian.sh green "$T5" FullyQualifiedName~InvoiceDiscountTests
check "its non-regression tests: the current behavior, green twice" 0 '^GREEN: 3 tests pass, twice$'
run test-guardian.sh coverage S1-net "$T5" src/App/Invoice.cs
run test-guardian.sh net S1-net src/App/Invoice.cs:Discount
check "the net, then OK" 0 '^SAFETY NET: OK \([0-9]+/[0-9]+ lines of this method run by the tests, 100%; minimum 80%\)$'
run test-guardian.sh tests-only
run test-guardian.sh seal S1 tests/App.Tests/InvoiceDiscountTests.cs
check "the net sealed" 0 '^SEALED: 1 test files'
# the coder rewrites the method, and forgets the negative percentages: the net shows it
cat > src/App/Invoice.cs <<'EOF'
namespace App;
public class Invoice
{
    public decimal Total(decimal amount) => amount;
    public decimal Vat(decimal amount) => amount * 0.2m;
    public decimal Discount(decimal amount, int percent) => amount * (100 - percent) / 100m;
}
EOF
run test-guardian.sh green "$T5" FullyQualifiedName~InvoiceDiscountTests
check "the coder's done condition: the net catches the regression" 1 '^STOP: 1 of these tests FAIL'
check "…and names it" 1 'App.Tests.InvoiceDiscountTests.Discount_NegativePercent_Unchanged'
cat > src/App/Invoice.cs <<'EOF'
namespace App;
public class Invoice
{
    public decimal Total(decimal amount) => amount;
    public decimal Vat(decimal amount) => amount * 0.2m;
    public decimal Discount(decimal amount, int percent) => percent <= 0 ? amount : amount * (100 - percent) / 100m;
}
EOF
run test-guardian.sh green "$T5" FullyQualifiedName~InvoiceDiscountTests
check "its next round: the net green" 0 '^GREEN: 3 tests pass, twice$'
# the same test-guardian, phase « après la modification »
run test-guardian.sh sealed S1
check "after: the net as sealed" 0 '^SEAL: OK, 1 test files as sealed$'
run test-guardian.sh coverage S1-after "$T5" src/App/Invoice.cs
check "after: no test fails" 0 '^TESTS: [0-9]+ passed, 0 failed$' '^FAILED TESTS'
run test-guardian.sh compare S1-before S1-after
check "after: no file lost coverage" 0 '^COVERAGE: no file lost coverage$'
run test-guardian.sh net S1-after src/App/Invoice.cs:Discount
check "after: the net kept" 0 '^SAFETY NET: OK \([0-9]+/[0-9]+ lines of this method run by the tests, 100%; minimum 80%\)$'
# the commit of the step (go.md 5.4): its net with it
run test-guardian.sh sealed S1
run ship.sh --no-push "refactor(billing): compute the discount in one expression (ABC-5)" "- src/App: Invoice.Discount" "- safety net: 0% -> 100% of the lines of 1 methods"
check "the step committed" 0 '^COMMIT: .* refactor\(billing\): compute the discount in one expression \(ABC-5\)'
truth "the commit holds the change and its net" '[ "$(git show --name-only --format= HEAD | sort | tr "\n" " ")" = "src/App/Invoice.cs tests/App.Tests/InvoiceDiscountTests.cs " ]'
truth "the commit says the net" 'git log -1 --format=%B | grep -q "^- safety net: 0% -> 100%"'

[ "$REAL" -eq 1 ] && dotnet build-server shutdown >/dev/null 2>&1
echo "scenarios ($([ "$REAL" -eq 1 ] && echo "real dotnet $(dotnet --version), " || echo "fake dotnet, ")$SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
