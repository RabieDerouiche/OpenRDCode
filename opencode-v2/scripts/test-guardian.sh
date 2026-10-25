#!/bin/sh
# Measures and proofs of the unit tests, for the test-guardian and the coder of /fortify, /go and /fix: no agent judges
# a coverage or a test result by reading code. Run from the repository (.NET projects that build on this machine).
#   deps <file.cs or file.razor>   the module of a file: its classes, the types its constructors receive (classic or
#                                  primary constructor; a Razor component: the types it injects, @inject and [Inject],
#                                  its code-behind <file>.razor.cs included) and the files that implement them (two
#                                  levels): "MODULE:", "DEPENDS:", "UNRESOLVED:" lines
#   coverage <label> <test project> <file.cs or file.razor>...
#                                  runs the tests of the project with coverlet and prints the line and branch coverage
#                                  of each file, with its uncovered lines, and the tests that fail; kept as <label> in
#                                  the measures folder. A test project with no test yet (just set up): "no test in
#                                  <project> yet", each file at 0/0 (no line of it runs)
#   compare <label before> <label after>
#                                  coverage after a change, file by file: "STOP:" when a file lost coverage
#   net <label> [--min <percent>] <file.cs or file.razor>:<method>...
#                                  the safety net of a fix (no test run: the report of coverage <label>): the line and
#                                  branch coverage of each method the fix will change or that leads to it, its async
#                                  state machine, lambdas and local functions included, with its uncovered lines, then
#                                  "SAFETY NET: OK" or "SAFETY NET: THIN" against the minimum (80 % of their lines when
#                                  none is given): below it, the non-regression tests of the current behavior come
#                                  before the fix. <method>: its name as the code writes it, <class>.<method> when the
#                                  file has several classes; a constructor: the name of its class; a Razor component:
#                                  BuildRenderTree (its markup, the C# written in it and its event handlers) and the
#                                  methods of its @code block. Measured with no test yet: THIN, every line of these
#                                  methods to run
#   red <test project> <filter>    the new tests must FAIL on the current code (and compile), the same way twice
#   green <test project> <filter>  the same tests must PASS, twice: a test whose result changes is FLAKY
#   build <project>                builds a project (the test-guardian never runs dotnet itself): "BUILD: OK", or the
#                                  compiler errors and "BUILD: FAILED"
#   tests-only                     the uncommitted changes touch only test projects
#   seal <label> [<test file>...]  keeps a copy of the test files of a proof, before the fix: "SEALED: <n> test files";
#                                  none for a problem that no unit test can show (« non démontrable »): an empty proof
#   sealed <label>                 the sealed test files are unchanged ("SEAL: OK"), or "STOP:" with the changed ones
#   restore <label>                puts the sealed test files back as they were sealed: "RESTORED: <files>"
#   park <label>, unpark <label>   (the pilot) takes the sealed test files of a proof out of the working tree until its
#                                  turn, and brings them back as sealed: the proofs of a wave are written together,
#                                  their fixes one after the other, each commit with its own tests only
#   setup [--integration [--db sqlite] | --components] xunit|mstest|nunit <file.cs, file.razor or project>...
#                                  (the pilot, once the developer agreed) creates the unit test project of these files:
#                                  the dotnet new template of the SDK, coverlet.collector, the versions this machine's
#                                  NuGet cache already holds (otherwise the template's), the central versions when the
#                                  repository has them, the project references and the solution, then a build; or adds
#                                  the coverage collector to the test projects that lack it (coverlet.collector, or
#                                  Microsoft.Testing.Extensions.CodeCoverage for a Microsoft.Testing.Platform project). A
#                                  failure undoes everything. --integration: the integration test project of an ASP.NET
#                                  Core API (/tests api), <solution>.IntegrationTests, with Microsoft.AspNetCore.Mvc.Testing
#                                  of the major version of its target framework (WebApplicationFactory), and, before
#                                  .NET 10, `public partial class Program { }` at the end of a Program.cs of top-level
#                                  statements; nothing when a test project has Microsoft.AspNetCore.Mvc.Testing already.
#                                  --db sqlite (the developer's choice in the wizard of /tests api, for endpoints that
#                                  use a DbContext directly): Microsoft.EntityFrameworkCore.Sqlite of the EF Core version
#                                  of the API too, in the new project or in the integration test project already there.
#                                  --components (the tests of Razor components, with bUnit: the safety net of a page
#                                  before it changes, its replacement of a component library included): bUnit in the
#                                  unit test project that references the project of these components (the only unit
#                                  test project otherwise, which then references it), with its coverage collector when
#                                  it lacks; the unit test project created with bUnit when there is none
#   changes <base> [<solution, project or folder>]
#                                  the whole suite once, with coverlet (the BUILD, TESTS and FAILED TESTS lines of
#                                  build-test.sh), then the lines the branch changed since <base> that no test runs, in
#                                  its C# and Razor files: "CHANGED:" lines per source file, then one "COVERAGE OF THE
#                                  CHANGES:" line
#   folder                         creates and prints the measures folder ("FOLDER: <path>")
# The measures folder: <git folder>/opencode-tickets/<KEY>.tests (KEY from the branch; a branch without a Jira key, of
# /push, /tests or /fix without a ticket: its name, / as -; a detached HEAD: NOKEY), shared by the
# worktrees, never committed; the test runs write nothing in the repository. Output lines are for the agents: exit 1
# with one "STOP: <reason>" line when a check fails, "ENVIRONMENT PROBLEM:" when this machine cannot build or run the
# tests (the agent stops and tells the developer). A test that runs more than 5 minutes is stopped and named.
# One dotnet build or test run at a time in a working tree (a lock shared with build-test.sh): the test-guardians of
# a wave work in parallel, their builds wait for each other ("WAIT:"). VSTest (the default runner of dotnet test) and
# Microsoft.Testing.Platform (MSTest.Sdk, the MSTest, NUnit or xUnit v3 runners, TUnit, global.json): the tests of an
# MTP project run as the application they are, through build-test.sh and test-platform.sh, with the coverage of its
# extension (Microsoft.Testing.Extensions.CodeCoverage or coverlet.MTP) instead of coverlet.collector.
# A seal is the proof of the test-guardian: the coder makes the sealed tests pass as they are, and the test-guardian
# checks them before its proof after the fix. Only the test-guardian may seal or restore, only the pilot may park,
# unpark and set up (permission rules).
# Usage: test-guardian.sh deps <file> | coverage <label> <proj> <file>... | compare <a> <b>
#        | net <label> [--min <pct>] <file>:<method>... | red|green <proj> <filter>
#        | build <proj> | tests-only | seal <label> [<file>...] | sealed <label> | restore <label> | park|unpark <label>
#        | setup [--integration [--db sqlite] | --components] xunit|mstest|nunit <file>... | changes <base> [<target>]
#        | folder

LC_ALL=C
export LC_ALL
DOTNET_CLI_UI_LANGUAGE=en DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_CLI_UI_LANGUAGE DOTNET_NOLOGO DOTNET_CLI_TELEMETRY_OPTOUT
# the longest a single test may run before the test host is stopped (VSTest blame); a test of the pack never needs it
HANG=${TEST_GUARDIAN_HANG:-5m}
# bUnit for the tests of Razor components (setup --components) when the NuGet cache of this machine holds none: a
# version of the 2.x line (BunitContext, Render), for net8.0 and later
BUNIT_DEFAULT=2.11.3

stop() {
  echo "STOP: $1"
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not in a git repository"
here=$(pwd -P)
# the folder of the pack's scripts (build-test.sh, test-platform.sh), found before the cd below
scripts=$(cd "$(dirname "$0")" && pwd -P)
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 1
root=$(pwd -P)
common=$(git rev-parse --git-common-dir) && common=$(cd "$common" && pwd)
branch=$(git branch --show-current 2>/dev/null)
key=$(printf '%s\n' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
# a branch without a key has a folder of its own: the labels of two branches without a ticket (F1, T1…) never meet
[ -n "$key" ] || key=$(printf '%s' "$branch" | tr -c 'A-Za-z0-9._-' '-')
folder="$common/opencode-tickets/${key:-NOKEY}.tests"

# One dotnet build or test run at a time in this working tree: the test-guardians of a wave work in parallel, and two
# builds of the same projects break each other. The lock is a folder in the git folder of the working tree (its own
# for each worktree); a run stopped by a timeout leaves it behind, and the next run takes it over. A script called by
# the one that holds it (build-test.sh under changes or build) does not take it again.
lockdir="$(git rev-parse --absolute-git-dir)/opencode-dotnet.lock"
LOCK_WAIT=${TEST_GUARDIAN_LOCK_WAIT:-900}
take_lock() {
  [ "${OPENCODE_DOTNET_LOCK:-}" = "$lockdir" ] && return 0
  waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    holder=$(cat "$lockdir/pid" 2>/dev/null)
    if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } || { [ -z "$holder" ] && [ "$waited" -ge 30 ]; }; then
      rm -rf "$lockdir"
      continue
    fi
    [ "$waited" -eq 0 ] && echo "WAIT: another build or test run of this folder is in progress (a test-guardian working in parallel): this one starts after it"
    [ "$waited" -ge "$LOCK_WAIT" ] && stop "another build or test run of this folder has been running for more than $LOCK_WAIT s"
    sleep 2
    waited=$((waited + 2))
  done
  echo "$$" > "$lockdir/pid"
  OPENCODE_DOTNET_LOCK=$lockdir
  export OPENCODE_DOTNET_LOCK
  trap 'rm -rf "$lockdir"' EXIT
  trap 'exit 1' INT TERM HUP
}

# Microsoft.Testing.Platform takes other options and prints other results than VSTest, the default runner of dotnet
# test: an MTP test project runs through build-test.sh and test-platform.sh (its test application), a VSTest one with
# dotnet test as always
is_mtp() {
  [ "$(sh "$scripts/test-platform.sh" kind "$1" | cut -d' ' -f1)" = mtp ]
}
# the coverage of a test project: coverlet.collector (VSTest), or the coverage extension of an MTP project
has_coverage() {
  if is_mtp "$1"; then
    [ "$(sh "$scripts/test-platform.sh" kind "$1" | cut -d' ' -f3)" != none ]
  else
    has_coverlet "$1"
  fi
}

need_dotnet() {
  command -v dotnet >/dev/null 2>&1 && return 0
  echo "ENVIRONMENT PROBLEM: dotnet is not on the PATH of this machine. Stop and tell the developer in one line (COMMANDES.md, « Environnement »)."
  exit 1
}

# An output of dotnet that says the machine, not the code, is the problem (an SDK, a runtime, a workload, the package
# feed): its "ENVIRONMENT PROBLEM" line, and stop
environment() {
  sh "$scripts/dotnet-problem.sh" "$1" && exit 1
  return 0
}

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

# The nearest project file in the folder of a file or above it
project_of() {
  d=$(dirname "$1")
  while :; do
    for c in "$d"/*.csproj; do
      [ -f "$c" ] && { printf '%s\n' "${c#./}"; return 0; }
    done
    [ "$d" = . ] || [ "$d" = / ] && return 1
    d=$(dirname "$d")
  done
}

# Whether a project file references another project (a ProjectReference to its file name, / or \\ before it)
references() {
  bn=$(basename "$2" | sed 's/[].[*^$\\]/\\&/g')
  grep -qE "<ProjectReference[^>]*Include=\"([^\"]*[/\\\\])?$bn\"" "$1" 2>/dev/null
}

# The Directory.Packages.props that sets the versions of a folder, when the repository manages them centrally
central_props() {
  d=$1
  while :; do
    if [ -f "$d/Directory.Packages.props" ]; then
      if grep -qi '<ManagePackageVersionsCentrally>[[:space:]]*true' "$d/Directory.Packages.props" ||
        grep -qsi '<ManagePackageVersionsCentrally>[[:space:]]*true' "$d/Directory.Build.props"; then
        printf '%s\n' "${d#./}/Directory.Packages.props" | sed 's:^\./::'
      fi
      return 0
    fi
    [ "$d" = . ] || [ "$d" = / ] && return 0
    d=$(dirname "$d")
  done
}

# The highest stable version of a package in the NuGet cache of this machine (what the package feed already served
# here, for the other repositories), otherwise the version given
cache_version() {
  cache=${NUGET_PACKAGES:-$HOME/.nuget/packages}
  id=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  best=$(for d in "$cache/$id"/*; do [ -d "$d" ] && basename "$d"; done | grep -E '^[0-9]+(\.[0-9]+)*$' |
    awk -F. '{ printf "%09d%09d%09d%09d %s\n", $1, $2, $3, $4, $0 }' | sort | tail -n 1 | cut -d' ' -f2)
  printf '%s\n' "${best:-$2}"
}

# The highest version of a package in the NuGet cache of this machine whose major version is <major>, otherwise <default>
cache_version_major() {
  cache=${NUGET_PACKAGES:-$HOME/.nuget/packages}
  id=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  best=$(for d in "$cache/$id"/*; do [ -d "$d" ] && basename "$d"; done | grep -E "^$2\.[0-9]+\.[0-9]+\$" |
    awk -F. '{ printf "%09d%09d%09d %s\n", $1, $2, $3, $0 }' | sort | tail -n 1 | cut -d' ' -f2)
  printf '%s\n' "${best:-$3}"
}

# The version of EF Core the repository uses (its Microsoft.EntityFrameworkCore packages, versions in the projects or in
# Directory.Packages.props), so that a provider added for the tests is of the same version; otherwise, the version of
# the NuGet cache of this machine of the major version of <target framework major>, or <major>.0.0
ef_version() {
  v=$(git ls-files -- '*.csproj' 'Directory.Packages.props' 'Directory.Build.props' 2>/dev/null |
    while IFS= read -r f; do grep -h -o -E '"Microsoft\.EntityFrameworkCore(\.[A-Za-z]+)*"[[:space:]]+Version="[0-9][^"]*"' "$f" 2>/dev/null; done |
    sed 's/.*Version="\([^"]*\)".*/\1/' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' |
    awk -F. '{ printf "%09d%09d%09d %s\n", $1, $2, $3, $0 }' | sort | tail -n 1 | cut -d' ' -f2)
  if [ -n "$v" ]; then printf '%s\n' "$v"; return 0; fi
  cache_version_major Microsoft.EntityFrameworkCore.Sqlite "${1:-10}" "${1:-10}.0.0"
}

# Adds <PackageReference Include="id"[ Version="v"] /> to a project, next to its other package references
add_package_ref() {
  awk -v id="$2" -v v="$3" '
    function line() { return "    <PackageReference Include=\"" id "\"" (v == "" ? "" : " Version=\"" v "\"") " />" }
    !done && /<PackageReference / { seen = 1 }
    !done && seen && /<\/ItemGroup>/ { print line(); done = 1 }
    !done && /<\/Project>/ { print "  <ItemGroup>"; print line(); print "  </ItemGroup>"; print ""; done = 1 }
    { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}

# Declares a version in Directory.Packages.props, next to the other PackageVersion lines (nothing when it is there)
add_package_version() {
  grep -qi "<PackageVersion[^>]*Include=\"$2\"" "$1" && return 0
  awk -v id="$2" -v v="$3" '
    function line() { return "    <PackageVersion Include=\"" id "\" Version=\"" v "\" />" }
    !done && /<PackageVersion / { seen = 1 }
    !done && seen && /<\/ItemGroup>/ { print line(); done = 1 }
    !done && /<\/Project>/ { print "  <ItemGroup>"; print line(); print "  </ItemGroup>"; done = 1 }
    { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}

# The target framework a new test project takes from a production project (its own, or its Directory.Build.props):
# the first modern one (net8.0, net10.0); none (netstandard only): the SDK's default; .NET Framework only: legacy
target_of() {
  tfms=$(sed -n 's:.*<TargetFrameworks\{0,1\}>\([^<]*\)</TargetFrameworks\{0,1\}>.*:\1:p' "$1" | tr ';' '\n')
  if [ -z "$tfms" ]; then
    d=$(dirname "$1")
    while [ -z "$tfms" ]; do
      [ -f "$d/Directory.Build.props" ] &&
        tfms=$(sed -n 's:.*<TargetFrameworks\{0,1\}>\([^<]*\)</TargetFrameworks\{0,1\}>.*:\1:p' "$d/Directory.Build.props" | tr ';' '\n')
      [ "$d" = . ] || [ "$d" = / ] && break
      d=$(dirname "$d")
    done
  fi
  modern=$(printf '%s\n' "$tfms" | tr -d ' \r' | grep -E '^net[0-9]+\.[0-9]+' | head -n 1)
  if [ -n "$modern" ]; then printf '%s\n' "$modern"; return 0; fi
  printf '%s\n' "$tfms" | tr -d ' \r' | grep -qE '^net[0-9]+$' && echo legacy
  return 0
}

# The folders of the test projects, one per line ("." for a test project at the root of the repository)
test_dirs() {
  test_projects | while read -r p; do dirname "$p"; done
}

# Whether a path of the repository is in a test project
in_tests() {
  test_dirs | while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ "$d" = . ]; then echo yes; break; fi
    case "$1" in "$d"/*) echo yes; break ;; esac
  done | grep -q yes
}

# A file named by an agent (from where it ran the script, from the root of the repository, or absolute) as a path of
# the repository; nothing, and a failure, for a missing file or a file outside the repository
repo_path() {
  case "$1" in
    /*) set -- "$1" ;;
    *) if [ -f "$here/$1" ]; then set -- "$here/$1"; else set -- "$root/$1"; fi ;;
  esac
  [ -f "$1" ] || return 1
  dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  case "$dir/" in
    "$root"/*) p="${dir#"$root"}/$(basename "$1")"; printf '%s\n' "${p#/}" ;;
    *) return 1 ;;
  esac
}

# "Passed: n" and "Failed: n" of a dotnet test output, summed over the test assemblies (VSTest summaries, minimal or
# normal, or Microsoft.Testing.Platform)
counts() {
  awk '/(Passed|Failed)!/ || /Total tests:/ || /^ *(Passed|Failed):/ {
         line = $0
         if (match(line, /Failed: *[0-9]+/)) { s = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); f += s }
         if (match(line, /Passed: *[0-9]+/)) { s = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); p += s }
       }
       /^ *succeeded: *[0-9]+/ { s = $0; gsub(/[^0-9]/, "", s); p += s }
       /^ *failed: *[0-9]+/ { s = $0; gsub(/[^0-9]/, "", s); f += s }
       END { printf "%d %d\n", p, f }' "$1"
}

# "<Passed|Failed|Skipped> <test name>" per test of a run (console logger, normal verbosity); a name may hold spaces
# (the cases of a theory). Microsoft.Testing.Platform lists the failed and skipped tests only ("failed <name> (12ms)"):
# with the counts, that is enough to compare two runs of the same tests
outcomes() {
  sed -n -e 's/^failed[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}([0-9][^)]*)[[:space:]]*$/Failed \1/p' \
    -e 's/^skipped[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}([0-9][^)]*)[[:space:]]*$/Skipped \1/p' \
    -e 's/^[[:space:]]*\(Passed\)[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}\[[^]]*\][[:space:]]*$/\1 \2/p' \
    -e 's/^[[:space:]]*\(Failed\)[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}\[[^]]*\][[:space:]]*$/\1 \2/p' \
    -e 's/^[[:space:]]*\(Skipped\)[[:space:]]\{1,\}\(.*[^[:space:]]\)[[:space:]]\{1,\}\[[^]]*\][[:space:]]*$/\1 \2/p' "$1" | sort -u
}

# "  <test>: <error message>" for each failed test of a run (its first lines, joined), 8 tests at most
reasons() {
  awk 'function flush() { if (name != "" && msg != "") print "  " name ": " substr(msg, 1, 240); name = ""; msg = "" }
       /^ *(Failed|Passed|Skipped) [^:]/ { flush(); if ($1 == "Failed") { name = $0; sub(/^ *Failed +/, "", name); sub(/ +\[[^]]*\] *$/, "", name) } inmsg = 0; next }
       # Microsoft.Testing.Platform: "failed <name> (12ms)", then its message indented, then the stack frames ("at …")
       /^(failed|passed|skipped) .* \([0-9][^)]*\) *$/ { flush(); if ($1 == "failed") { name = $0; sub(/^failed +/, "", name); sub(/ +\([0-9][^)]*\) *$/, "", name); inmsg = 2 } else inmsg = 0; next }
       inmsg == 2 && /^  +at / { inmsg = 0; next }
       inmsg == 2 && /^[^ ]/ { inmsg = 0 }
       /^ *Error Message:/ { inmsg = 1; next }
       /^ *Stack Trace:/ { inmsg = 0; next }
       inmsg && NF { line = $0; sub(/^ +/, "", line); msg = (msg == "" ? line : msg " · " line); next }
       END { flush() }' "$1" | head -n 8
}

# A test host that hung or crashed: says which test ran, and stops
aborted() {
  if grep -q '^HANG: ' "$1"; then
    stop "$(sed -n 's/^HANG: //p' "$1" | head -n 1)"
  fi
  grep -q 'test run was aborted\|Test Run Aborted' "$1" || return 0
  running=$(awk '/The test running when the crash occurred:/ { on = 1; next } on && NF { print; n++ } on && !NF && n { exit }' "$1" | head -n 3 | tr '\n' ' ')
  if grep -q 'inactivity time of' "$1"; then
    stop "a test ran more than $HANG and was stopped (it hangs: an endless loop, a wait without timeout, a real network or clock): ${running:-unknown test}. A test of the pack bounds its own time and never waits for something outside."
  fi
  stop "the test host crashed (a stack overflow or an exit of the process) during: ${running:-unknown test}"
}

# One run of the tests of a filter, with the results outside the repository; $4: --no-build for a second run
run_tests() {
  if is_mtp "$1"; then
    sh "$scripts/build-test.sh" ${4:+"$4"} "$1" --filter "$2" > "$3" 2>&1
    return
  fi
  dotnet test "$1" --filter "$2" --nologo -v q --logger "console;verbosity=normal" ${4:+"$4"} \
    --results-directory "$folder/results-run" --blame-hang-timeout "$HANG" --blame-hang-dump-type none > "$3" 2>&1
}

case "$1" in
  folder)
    mkdir -p "$folder" || stop "cannot create $folder"
    echo "FOLDER: $folder"
    exit 0 ;;

  deps)
    file=$2
    [ -f "$file" ] || stop "no file $file"
    # The types a Razor component receives from the container: @inject in its markup, [Inject] properties in its @code
    # block or its code-behind (namespaces and generic arguments dropped: ILogger<Orders> is ILogger)
    inject_types() {
      sed -n -E -e 's/^[[:space:]]*@inject[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*).*/TYPE \1/p' \
        -e 's/.*\[Inject[^]]*\][[:space:]]*((public|private|protected|internal)[[:space:]]+)?(required[[:space:]]+)?([A-Za-z_][A-Za-z0-9_.]*).*/TYPE \4/p' "$1" |
        sed 's/^TYPE .*\./TYPE /'
    }
    case "$file" in
      *.razor)
        # a component: its class is named after its file; its code-behind (<file>.razor.cs) may add a constructor
        # (.NET 9 and later) or [Inject] properties
        types=$({ printf 'CLASS %s\n' "$(basename "$file" .razor)"; inject_types "$file"
          if [ -f "$file.cs" ]; then sh "$0" deps-types "$file.cs"; inject_types "$file.cs"; fi; } | sort -u) ;;
      *) types=$({ sh "$0" deps-types "$file"; inject_types "$file"; } | sort -u) ;;
    esac
    echo "MODULE: $file"
    printf '%s\n' "$types" | sed -n 's/^CLASS /  class /p'
    resolve() {
      # the files that declare the type, or a class that implements the interface (test projects excluded)
      { git grep -lE "(class|record|struct)[[:space:]]+$1([^A-Za-z0-9_]|\$)" -- '*.cs'
        git grep -lE "(class|record)[[:space:]]+[A-Za-z0-9_]+[^{;]*:[^{;]*[^A-Za-z0-9_]$1([^A-Za-z0-9_]|\$)" -- '*.cs'; } 2>/dev/null |
        grep -viE '(^|/)[^/]*tests?[^/]*/|/(bin|obj)/' | grep -vxF "$file" | sort -u
    }
    level2=""
    for t in $(printf '%s\n' "$types" | sed -n 's/^TYPE //p'); do
      found=$(resolve "$t")
      if [ -n "$found" ]; then
        for f in $found; do echo "DEPENDS: $t -> $f"; level2="$level2 $f"; done
      else
        echo "UNRESOLVED: $t (outside this repository: framework or package)"
      fi
    done
    # second level, once: what the dependencies receive
    for f in $level2; do
      sh "$0" deps-one "$f" 2>/dev/null | sed -n 's/^DEPENDS: /DEPENDS (level 2): /p'
    done | sort -u
    exit 0 ;;

  deps-types)
    # the classes of a C# file and the type names given to their constructors (classic and primary constructors):
    # "CLASS <name>" and "TYPE <name>" lines (used by deps)
    file=$2
    [ -f "$file" ] || stop "no file $file"
    awk '
      { text = text " " $0 }
      END {
        n = split(text, chunks, /class[ \t]+/)
        for (i = 2; i <= n; i++) {
          if (!match(chunks[i], /^[A-Za-z_][A-Za-z0-9_]*/)) continue
          cls = substr(chunks[i], RSTART, RLENGTH)
          print "CLASS " cls
          body = chunks[i]
          # primary constructor: class Name(params) or class Name<T>(params)
          rest = substr(body, RLENGTH + 1)
          sub(/^<[^>]*>/, "", rest)
          if (rest ~ /^[ \t]*\(/) { params = rest; sub(/^[ \t]*\(/, "", params); sub(/\).*/, "", params); emit(params) }
          # classic constructors: Name(params) {
          while (match(body, cls "[ \t]*\\([^)]*\\)[ \t]*(:[^{]*)?\\{")) {
            ctor = substr(body, RSTART, RLENGTH); body = substr(body, RSTART + RLENGTH)
            params = ctor; sub(/^[^(]*\(/, "", params); sub(/\).*/, "", params); emit(params)
          }
        }
      }
      function emit(params,   k, m, parts, t) {
        m = split(params, parts, ",")
        for (k = 1; k <= m; k++) {
          t = parts[k]; gsub(/\[[^]]*\]/, "", t); gsub(/^[ \t]+|[ \t]+$/, "", t)
          sub(/[ \t]+[A-Za-z_][A-Za-z0-9_]*([ \t]*=.*)?$/, "", t)
          sub(/<.*/, "", t); sub(/\?$/, "", t); sub(/.*\./, "", t)
          if (t ~ /^[A-Z][A-Za-z0-9_]*$/) print "TYPE " t
        }
      }' "$file"
    exit 0 ;;

  deps-one)
    # first level only (used by deps for the second level)
    sh "$0" deps "$2" | grep '^DEPENDS: ' | grep -v ' (level 2)'
    exit 0 ;;

  coverage)
    [ $# -ge 4 ] || stop "usage: test-guardian.sh coverage <label> <test project> <file.cs or file.razor>..."
    label=$2 project=$3
    shift 3
    [ -f "$project" ] || stop "no test project $project"
    printf '%s' "$label" | grep -qE '^[A-Za-z0-9._-]+$' || stop "bad label $label"
    need_dotnet
    mkdir -p "$folder" || stop "cannot create $folder"
    take_lock
    results="$folder/results-$label"
    rm -rf "$results"
    if is_mtp "$project"; then
      sh "$scripts/build-test.sh" "$project" --collect:"XPlat Code Coverage" --results-directory "$results" > "$folder/test-$label.log" 2>&1
    else
      dotnet test "$project" --collect:"XPlat Code Coverage" --results-directory "$results" --nologo -v q \
        --logger "console;verbosity=normal" --blame-hang-timeout "$HANG" --blame-hang-dump-type none > "$folder/test-$label.log" 2>&1
    fi
    environment "$folder/test-$label.log"
    aborted "$folder/test-$label.log"
    report=$(find "$results" -name '*.cobertura.xml' 2>/dev/null | head -n 1)
    # a test project with no test yet (just set up): nothing runs these files, which is their net (0 %), not a failure
    if [ -z "$report" ] && [ "$(counts "$folder/test-$label.log")" = "0 0" ] && ! grep -qE 'error (CS|MSB)|^COVERAGE: NOT MEASURED' "$folder/test-$label.log" &&
      grep -qE 'No test is available|No test source files|Zero tests ran|NONE RUN' "$folder/test-$label.log"; then
      mkdir -p "$results" && : > "$results/no-test-yet"
      echo "TESTS: 0 passed, 0 failed (no test in $project yet)"
      for f in "$@"; do echo "$f lines 0/0 (no test yet: none of its lines runs)"; done | tee "$folder/coverage-$label.txt"
      exit 0
    fi
    if [ -z "$report" ]; then
      grep -m 3 'error CS\|error MSB' "$folder/test-$label.log"
      grep -m 1 '^COVERAGE: NOT MEASURED' "$folder/test-$label.log"
      stop "no coverage report: the build failed, or the coverage collector is missing in $project (coverlet.collector, or Microsoft.Testing.Extensions.CodeCoverage for Microsoft.Testing.Platform: fortify.sh prereq)"
    fi
    pf=$(counts "$folder/test-$label.log")
    echo "TESTS: ${pf% *} passed, ${pf#* } failed"
    # the tests that fail: those that already fail on develop, or a regression (after a change)
    if [ "${pf#* }" -gt 0 ]; then
      names=$(sed -n 's/^FAILED TESTS ([0-9]*): //p' "$folder/test-$label.log" | head -n 1)
      [ -n "$names" ] || names=$(outcomes "$folder/test-$label.log" | sed -n 's/^Failed //p' | head -n 8 | tr '\n' ' ' | sed 's/ $//')
      echo "FAILED TESTS (${pf#* }): $names"
    fi
    # One line per file asked: "<file> lines <covered>/<total> (<pct>%) branches <covered>/<total> uncovered <ranges>"
    for f in "$@"; do echo "WANT $f"; done | cat - "$report" | awk '
      /^WANT / { want[++w] = substr($0, 6); next }
      /<class / {
        cur = ""
        if (match($0, /filename="[^"]*"/)) { fn = substr($0, RSTART + 10, RLENGTH - 11); gsub(/\\/, "/", fn)
          for (i = 1; i <= w; i++) if (ends(fn, want[i]) || ends(want[i], fn)) cur = want[i] }
        next
      }
      cur != "" && /<line / {
        if (!match($0, /number="[0-9]+"/)) next
        num = substr($0, RSTART + 8, RLENGTH - 9) + 0
        match($0, /hits="[0-9]+"/); hits = substr($0, RSTART + 6, RLENGTH - 7) + 0
        key = cur SUBSEP num
        # coverlet lists each line twice (in its method and in its class): counted once, branches from either
        if (!(key in seen)) { seen[key] = 1; total[cur]++; if (hits > 0) cov[cur]++; else miss[cur] = miss[cur] " " num }
        if (!(key in bseen) && match($0, /condition-coverage="[0-9]+% \([0-9]+\/[0-9]+\)"/)) {
          bseen[key] = 1
          c = substr($0, RSTART, RLENGTH); sub(/.*\(/, "", c); sub(/\).*/, "", c); split(c, bc, "/")
          bcov[cur] += bc[1]; btot[cur] += bc[2]
        }
      }
      END {
        for (i = 1; i <= w; i++) {
          f = want[i]
          if (!(f in total)) { printf "%s lines 0/0 (not in the report: no test reaches this file)\n", f; continue }
          printf "%s lines %d/%d (%d%%) branches %d/%d uncovered%s\n", f, cov[f], total[f], int(100 * cov[f] / total[f]), bcov[f], btot[f], ranges(miss[f])
        }
      }
      function ends(a, b) { return length(a) >= length(b) && substr(a, length(a) - length(b) + 1) == b && (length(a) == length(b) || substr(a, length(a) - length(b), 1) == "/") }
      function ranges(s,   a, n, i, out, start, prev) {
        n = split(s, a, " "); if (n == 0) return " none"
        out = ""; start = a[1]; prev = a[1]
        for (i = 2; i <= n + 1; i++) {
          if (i <= n && a[i] == prev + 1) { prev = a[i]; continue }
          out = out " " (start == prev ? start : start "-" prev)
          if (i <= n) { start = a[i]; prev = a[i] }
        }
        return out
      }' | tee "$folder/coverage-$label.txt"
    exit 0 ;;

  compare)
    a="$folder/coverage-$2.txt" b="$folder/coverage-$3.txt"
    [ -f "$a" ] && [ -f "$b" ] || stop "missing coverage $2 or $3 (test-guardian.sh coverage first)"
    awk 'FNR == NR { before[$1] = $3; next }
         { split(before[$1], x, "/"); split($3, y, "/")
           pb = x[2] ? x[1] / x[2] : 0; pa = y[2] ? y[1] / y[2] : 0
           status = pa + 0.0001 < pb ? "LOST" : "ok"; if (status == "LOST") lost = lost " " $1
           was = (before[$1] == "") ? "new" : before[$1]; printf "%s %s -> %s %s\n", $1, was, $3, status }
         END { if (lost != "") { print "STOP: coverage lost after the change in" lost; exit 1 } print "COVERAGE: no file lost coverage" }' "$a" "$b"
    exit $? ;;

  net)
    [ $# -ge 3 ] || stop "usage: test-guardian.sh net <label> [--min <percent>] <file.cs or file.razor>:<method>..."
    label=$2
    shift 2
    min=80
    if [ "$1" = --min ]; then
      min=${2%%%}
      shift 2
    fi
    { printf '%s' "$min" | grep -qE '^[0-9]{1,3}$' && [ "$min" -le 100 ]; } || stop "bad minimum $min: a percentage, from 0 to 100"
    [ $# -ge 1 ] || stop "usage: test-guardian.sh net <label> [--min <percent>] <file.cs or file.razor>:<method>..."
    printf '%s' "$label" | grep -qE '^[A-Za-z0-9._-]+$' || stop "bad label $label"
    # <file.cs>:<method> or <file.razor>:<method> (a Razor component: BuildRenderTree, or a method of its @code block):
    # the file in f, the method in spec
    split_method() {
      case "$1" in
        *.razor:?*) f="${1%%.razor:*}.razor" spec=${1#*.razor:} ;;
        *.cs:?*) f="${1%%.cs:*}.cs" spec=${1#*.cs:} ;;
        *) stop "bad method $1: <file.cs>:<method>, <file.cs>:<class>.<method>, or <file.razor>:<method> (BuildRenderTree, or a method of its @code block)" ;;
      esac
      f=${f#./}
      [ -f "$f" ] || [ -f "$root/$f" ] || stop "no file $f in this repository"
    }
    report=$(find "$folder/results-$label" -name '*.cobertura.xml' 2>/dev/null | head -n 1)
    if [ -z "$report" ] && [ -f "$folder/results-$label/no-test-yet" ]; then
      # measured before any test exists: every line of these methods is to run
      n=0
      for m in "$@"; do
        split_method "$m"
        n=$((n + 1))
      done
      for m in "$@"; do echo "NET: ${m#./} no test yet: none of its lines runs"; done
      if [ "$n" -eq 1 ]; then what="this method"; else what="these $n methods"; fi
      if [ "$min" -eq 0 ]; then
        echo "SAFETY NET: OK (no test runs $what yet, 0%; minimum 0%)"
      else
        echo "SAFETY NET: THIN (no test runs $what yet, 0% < $min%): before the fix, the non-regression tests of their current behavior that run all their lines (green twice), then coverage and net again"
      fi
      exit 0
    fi
    [ -n "$report" ] || stop "no coverage measured as $label: test-guardian.sh coverage $label <test project> <files> first"
    # one "WANT<tab><file><tab><class or -><tab><method><tab><as given>" line per method asked
    wants=""
    for m in "$@"; do
      split_method "$m"
      case "$spec" in
        *[!A-Za-z0-9_.]*) stop "bad method $spec in $m: the name of a method, or <class>.<method>" ;;
      esac
      case "$spec" in
        .ctor|.cctor) qual=- name=$spec ;;
        *..ctor|*..cctor) qual=${spec%..*} name=.${spec##*..} ;;
        *.*) qual=${spec%.*} name=${spec##*.} ;;
        *) qual=- name=$spec ;;
      esac
      [ -n "$qual" ] && [ -n "$name" ] || stop "bad method $spec in $m"
      wants="${wants}WANT	$f	$qual	$name	$m
"
    done
    printf '%s' "$wants" | cat - "$report" | awk -v min="$min" '
      function unesc(s) { gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s); gsub(/&apos;/, "'"'"'", s); gsub(/&amp;/, "\\&", s); return s }
      function attr(line, name) { if (!match(line, " " name "=\"[^\"]*\"")) return ""; return substr(line, RSTART + length(name) + 3, RLENGTH - length(name) - 4) }
      # the method a name made by the compiler belongs to: <Read>b__3_0 (a lambda), <Read>g__Local|3_0 (a local
      # function), <.ctor>b__0_0; never a generic method of the code (Map<T>)
      function ownerof(s,   t) { if (!match(s, /^<+\.?[A-Za-z_][A-Za-z0-9_]*>/)) return ""; t = substr(s, 1, RLENGTH - 1); sub(/^<+/, "", t); return t }
      # the same for a type made by the compiler: <ReadAsync>d__2 (async method or iterator), <>c/<<Preview>b__3_0>d__0
      # (an async lambda); <>c and <>c__DisplayClass3_0 (closures) belong to no method: their methods say it
      function genowner(s) { if (match(s, /<\.?[A-Za-z_][A-Za-z0-9_]*>/)) return substr(s, RSTART + 1, RLENGTH - 2); return "" }
      function ends(a, b) { return length(a) >= length(b) && substr(a, length(a) - length(b) + 1) == b && (length(a) == length(b) || substr(a, length(a) - length(b), 1) == "/") }
      function simple(t,   n, p) { n = split(t, p, "."); return p[n] }
      function qualifies(t, q) { return t == q || (length(t) > length(q) && substr(t, length(t) - length(q)) == "." q) }
      function sorted(s,   a, n, i, j, x, out) {
        n = split(s, a, " ")
        for (i = 2; i <= n; i++) { x = a[i] + 0; for (j = i - 1; j >= 1 && a[j] + 0 > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
        out = ""; for (i = 1; i <= n; i++) out = out " " a[i]
        return out
      }
      function ranges(s,   a, n, i, out, start, prev) {
        n = split(sorted(s), a, " "); if (n == 0) return " none"
        out = ""; start = a[1]; prev = a[1]
        for (i = 2; i <= n + 1; i++) {
          if (i <= n && a[i] == prev + 1) { prev = a[i]; continue }
          out = out " " (start == prev ? start : start "-" prev)
          if (i <= n) { start = a[i]; prev = a[i] }
        }
        return out
      }
      /^WANT\t/ { w++; split($0, f, "\t"); wfile[w] = f[2]; wqual[w] = (f[3] == "-" ? "" : f[3]); wname[w] = f[4]; wspec[w] = f[5]; next }
      /<class / {
        cur = ""; active = ""
        fn = attr($0, "filename"); gsub(/\\/, "/", fn)
        cls = unesc(attr($0, "name"))
        # the type of the code, and the method of a type the compiler made for it (coverlet nests types with /,
        # other tools with + or .)
        gen = ""; user = cls
        i = index(cls, "/<"); if (!i) i = index(cls, "+<"); if (!i) i = index(cls, ".<")
        if (i) { gen = substr(cls, i + 1); user = substr(cls, 1, i - 1) }
        gsub(/`[0-9]+/, "", user); gsub(/[\/+]/, ".", user)
        cowner = genowner(gen)
        for (k = 1; k <= w; k++) if (ends(fn, wfile[k]) || ends(wfile[k], fn)) { cur = wfile[k]; seenfile[cur] = 1; break }
        next
      }
      cur != "" && /<method / {
        active = ""
        raw = unesc(attr($0, "name"))
        o = cowner
        if (o == "") o = ownerof(raw)
        if (o == "") {
          o = raw
          sub(/<.*$/, "", o)
          if (o !~ /^\./) { n = split(o, part, "."); o = part[n] }
          if (o ~ /^(get|set|add|remove)_./) o = substr(o, index(o, "_") + 1)
        }
        if (!((cur SUBSEP o) in listed)) { listed[cur SUBSEP o] = 1; names[cur] = names[cur] (names[cur] == "" ? "" : ", ") o }
        for (k = 1; k <= w; k++) {
          if (wfile[k] != cur) continue
          if (!(o == wname[k] || raw == wname[k] || (o == ".ctor" && wname[k] == simple(user)))) continue
          if (wqual[k] != "" && !qualifies(user, wqual[k])) continue
          active = active " " k; found[k] = 1
        }
        if ($0 ~ /\/>[[:space:]]*$/) active = ""
        next
      }
      cur != "" && /<\/method>/ { active = ""; next }
      active != "" && /<line / {
        if (!match($0, /number="[0-9]+"/)) next
        num = substr($0, RSTART + 8, RLENGTH - 9) + 0
        hits = 0; if (match($0, /hits="[0-9]+"/)) hits = substr($0, RSTART + 6, RLENGTH - 7) + 0
        bc[1] = 0; bc[2] = 0
        if (match($0, /condition-coverage="[0-9.]+% \([0-9]+\/[0-9]+\)"/)) {
          c = substr($0, RSTART, RLENGTH); sub(/.*\(/, "", c); sub(/\).*/, "", c); split(c, bc, "/")
        }
        n = split(active, ks, " ")
        for (x = 1; x <= n; x++) {
          k = ks[x]
          if ((k SUBSEP num) in seen) continue
          seen[k SUBSEP num] = 1; tot[k]++
          if (hits > 0) cov[k]++; else miss[k] = miss[k] " " num
          bcov[k] += bc[1]; btot[k] += bc[2]
        }
        if (!((cur SUBSEP num) in union)) { union[cur SUBSEP num] = 1; utot++; if (hits > 0) ucov++ }
        next
      }
      END {
        bad = ""
        for (k = 1; k <= w; k++) {
          if (!found[k]) {
            # the markup of a Razor component: coverlet counts the C# statements written in it (an @if, an @foreach, an
            # event handler), never its tags and their attributes; a page made of them has no BuildRenderTree in the report
            if (wfile[k] ~ /\.razor$/ && wname[k] == "BuildRenderTree" && seenfile[wfile[k]]) {
              printf "NET: %s not measured: coverlet counts the C# statements of a component (its @code, the @if, @foreach and event handlers of its markup), never its tags and their attributes; the tests of what its users see are the net of its markup\n", wspec[k]
              continue
            }
            bad = bad "; " wspec[k] " (" (seenfile[wfile[k]] ? "the methods of this file in the report: " (names[wfile[k]] == "" ? "none" : names[wfile[k]]) : "this file is not in the report: no project the tests reference holds it") ")"
            continue
          }
          printf "NET: %s lines %d/%d (%d%%) branches %d/%d uncovered%s\n", wspec[k], cov[k], tot[k], (tot[k] ? int(100 * cov[k] / tot[k]) : 100), bcov[k], btot[k], ranges(miss[k])
        }
        if (bad != "") {
          print "STOP: not in the coverage report: " substr(bad, 3) ". Give each method by its name in the code (<class>.<method> when the file has several classes; a constructor: the name of its class)"
          exit 1
        }
        if (utot == 0) {
          print "SAFETY NET: OK (no line of these methods is measured: the markup of a component is checked by the tests of what its users see, which must exist and pass before the change)"
          exit 0
        }
        pct = int(100 * ucov / utot)
        what = (ucov + 0) "/" utot " lines of " (w == 1 ? "this method" : "these " w " methods") " run by the tests, " pct "%"
        if (ucov * 100 >= min * utot) print "SAFETY NET: OK (" what "; minimum " min "%)"
        else print "SAFETY NET: THIN (" what " < " min "%): before the fix, the non-regression tests of their current behavior that run the uncovered lines above (green twice), then coverage and net again"
      }'
    exit $? ;;

  red|green)
    project=$2 filter=$3
    [ -f "$project" ] && [ -n "$filter" ] || stop "usage: test-guardian.sh $1 <test project> <filter>"
    need_dotnet
    mkdir -p "$folder"
    take_lock
    stamp=$(date +%H%M%S)
    one="$folder/$1-$stamp-1.log" two="$folder/$1-$stamp-2.log"
    run_tests "$project" "$filter" "$one"
    environment "$one"
    if grep -q 'error CS\|error MSB' "$one"; then
      grep 'error CS\|error MSB' "$one" | sed -E 's/ \[[^]]*\]$//' | sort -u | head -n 3
      stop "the tests do not build: $([ "$1" = red ] && echo "a red test must compile against the current code (call what exists)" || echo "fix the build first")"
    fi
    aborted "$one"
    pf=$(counts "$one")
    passed=${pf% *} failed=${pf#* }
    [ $((passed + failed)) -gt 0 ] || stop "no test matched the filter $filter"
    # the same tests once more, without building: a test whose result changes is FLAKY (time, order, shared state,
    # randomness), and a flaky test is never committed
    run_tests "$project" "$filter" "$two" --no-build
    aborted "$two"
    outcomes "$one" > "$one.outcomes"
    outcomes "$two" > "$two.outcomes"
    flaky=$(awk 'FNR == NR { o = $1; sub(/^[^ ]+ /, ""); first[$0] = o; next }
                 { o = $1; sub(/^[^ ]+ /, ""); if (($0 in first) && first[$0] != o) print $0 }' "$one.outcomes" "$two.outcomes")
    pf2=$(counts "$two")
    if [ -n "$flaky" ] || [ "$pf2" != "$pf" ]; then
      echo "FLAKY: $(printf '%s\n' "$flaky" | grep . | head -n 5 | tr '\n' ' ')(first run: $passed passed, $failed failed; second run: ${pf2% *} passed, ${pf2#* } failed)"
      stop "a test changed its result between two runs of the same code: it depends on time, order, shared state or randomness. Make it deterministic before anything else."
    fi
    if [ "$1" = red ]; then
      if [ "$passed" -ne 0 ]; then
        sed -n 's/^Passed /  passes now: /p' "$one.outcomes" | head -n 5
        stop "$passed of these tests PASS on the current code: they do not show the problem"
      fi
      echo "RED: $failed tests fail on the current code, twice the same way, as expected"
      # the reason of each failure: the message of the assertion, never a build error or a missing set-up
      reasons "$one"
      if grep -q 'NullReferenceException\|Object reference not set' "$one"; then
        echo "WARNING: a test fails with a NullReferenceException: is that the problem itself, or a test that does not set up its objects? A red test fails for the reason of the problem."
      fi
    else
      if [ "$failed" -ne 0 ]; then
        reasons "$one"
        stop "$failed of these tests FAIL, twice the same way"
      fi
      echo "GREEN: $passed tests pass, twice"
    fi
    exit 0 ;;

  build)
    project=$2
    [ -n "$project" ] && [ -f "$project" ] || stop "usage: test-guardian.sh build <project or solution>"
    need_dotnet
    take_lock
    sh "$(dirname "$0")/build-test.sh" --build-only "$project"
    exit $? ;;

  tests-only)
    dirs=$(test_dirs)
    bad=$(git status --porcelain | cut -c4- | while read -r f; do
      ok=0
      for d in $dirs; do case "$f" in "$d"/*) ok=1 ;; esac; done
      [ "$ok" = 1 ] || echo "$f"
    done)
    [ -z "$bad" ] || stop "changes outside the test projects: $(printf '%s' "$bad" | tr '\n' ' ')"
    echo "TESTS-ONLY: OK"
    exit 0 ;;

  seal)
    [ $# -ge 2 ] || stop "usage: test-guardian.sh seal <label> [<test file>...]"
    label=$2
    shift 2
    printf '%s' "$label" | grep -qE '^[A-Za-z0-9._-]+$' || stop "bad label $label"
    # every file first: a seal is all the files of the proof or nothing
    list=""
    for f in "$@"; do
      p=$(repo_path "$f") || stop "no file $f in this repository"
      in_tests "$p" || stop "$p is not in a test project: only the test files of a proof are sealed"
      list="$list$p
"
    done
    seal="$folder/seal-$label"
    rm -rf "$seal"
    mkdir -p "$seal/files" || stop "cannot create $seal"
    printf '%s' "$list" | sort -u > "$seal/list"
    while IFS= read -r p; do
      { mkdir -p "$seal/files/$(dirname "$p")" && cp "$p" "$seal/files/$p"; } || stop "cannot copy $p"
    done < "$seal/list"
    if [ -s "$seal/list" ]; then
      echo "SEALED: $(wc -l < "$seal/list" | tr -d ' ') test files ($(tr '\n' ' ' < "$seal/list" | sed 's/ $//')): the fix must make them pass as they are"
    else
      # a problem that no unit test can show (configuration, a framework setting): an empty proof, so that park, unpark
      # and sealed work the same way; the fix is checked by the build, the tests of the module and the review
      echo "SEALED: 0 test files: this proof holds no test (« non démontrable »); the fix is checked by the build, the tests of the module and the review"
    fi
    exit 0 ;;

  sealed|restore)
    label=$2
    [ -n "$label" ] || stop "usage: test-guardian.sh $1 <label>"
    seal="$folder/seal-$label"
    [ -f "$seal/list" ] || stop "no seal $label (test-guardian.sh seal $label <test files> before the fix)"
    changed=""
    while IFS= read -r p; do
      if [ ! -f "$p" ]; then changed="$changed, $p (deleted)"
      elif ! cmp -s "$p" "$seal/files/$p"; then changed="$changed, $p"
      fi
    done < "$seal/list"
    changed=${changed#, }
    if [ "$1" = sealed ]; then
      [ -z "$changed" ] || stop "the test files of the proof $label changed since they were sealed: $changed. The fix must make the sealed tests pass as they are: test-guardian.sh restore $label puts them back"
      echo "SEAL: OK, $(wc -l < "$seal/list" | tr -d ' ') test files as sealed"
      exit 0
    fi
    while IFS= read -r p; do
      if [ ! -f "$p" ] || ! cmp -s "$p" "$seal/files/$p"; then
        { mkdir -p "$(dirname "$p")" && cp "$seal/files/$p" "$p"; } || stop "cannot put back $p"
      fi
    done < "$seal/list"
    echo "RESTORED: ${changed:-nothing (the test files were as sealed)}"
    exit 0 ;;

  park|unpark)
    label=$2
    [ -n "$label" ] || stop "usage: test-guardian.sh $1 <label>"
    seal="$folder/seal-$label"
    [ -f "$seal/list" ] || stop "no seal $label: only a sealed proof is parked"
    tab=$(printf '\t')
    total=$(wc -l < "$seal/list" | tr -d ' ')
    # the sealed files that are in the working tree as they were sealed
    intact=0 changed=""
    while IFS= read -r p; do
      if [ -f "$p" ] && cmp -s "$p" "$seal/files/$p"; then intact=$((intact + 1)); else changed="$changed $p"; fi
    done < "$seal/list"
    if [ "$1" = park ]; then
      # only an intact proof, and only once
      [ ! -f "$seal/parked" ] || stop "the proof $label is parked already (test-guardian.sh unpark $label brings it back)"
      [ -z "$changed" ] || stop "the tests of the proof $label are not as sealed:$changed. Nothing parked"
      # what HEAD holds for each file when it leaves: unpark refuses a file that a commit changed meanwhile
      while IFS= read -r p; do
        blob=$(git rev-parse -q --verify "HEAD:$p" 2>/dev/null) || blob=new
        printf '%s\t%s\n' "$blob" "$p"
      done < "$seal/list" > "$seal/base.new"
      while IFS="$tab" read -r blob p; do
        if [ "$blob" = new ]; then
          rm -f "$p" || stop "cannot take $p out"
        else
          git checkout -q HEAD -- "$p" || stop "cannot put $p back to its committed content"
        fi
      done < "$seal/base.new"
      mv "$seal/base.new" "$seal/base"
      : > "$seal/parked"
      echo "PARKED: $total test files of the proof $label out of the working tree until its turn (test-guardian.sh unpark $label)"
      exit 0
    fi
    # unpark: a proof out of the working tree (parked, or put aside with the work of an interrupted fix) comes back as
    # sealed, unless a commit changed one of its files since it was parked
    [ -f "$seal/base" ] || stop "the proof $label was never parked"
    if [ "$intact" -eq "$total" ]; then
      rm -f "$seal/parked"
      echo "UNPARKED: the proof $label is in the working tree already, as sealed"
      exit 0
    fi
    moved=""
    while IFS="$tab" read -r blob p; do
      [ -f "$p" ] && cmp -s "$p" "$seal/files/$p" && continue
      now=$(git rev-parse -q --verify "HEAD:$p" 2>/dev/null) || now=new
      if [ "$now" != "$blob" ]; then moved="$moved $p (committed meanwhile)"
      elif [ "$blob" = new ] && [ -e "$p" ]; then moved="$moved $p (exists)"
      elif [ "$blob" != new ] && ! git diff --quiet HEAD -- "$p"; then moved="$moved $p (changed)"
      fi
    done < "$seal/base"
    [ -z "$moved" ] || stop "the proof $label cannot come back as it was made:$moved. Its test-guardian makes it again (phase « avant le correctif »)"
    while IFS= read -r p; do
      { mkdir -p "$(dirname "$p")" && cp "$seal/files/$p" "$p"; } || stop "cannot bring back $p"
    done < "$seal/list"
    rm -f "$seal/parked"
    echo "UNPARKED: $total test files of the proof $label back, as sealed"
    exit 0 ;;

  setup)
    kind=unit db=""
    case "$2" in
      --integration) kind=integration; shift ;;
      --components) kind=components; shift ;;
    esac
    if [ "$2" = --db ]; then
      [ "$kind" = integration ] || stop "--db goes with --integration (the database of the API tests)"
      db=$3
      [ "$db" = sqlite ] || stop "--db sqlite only (an in-memory SQLite database for the DbContext of the API; Testcontainers is the developer's own setup)"
      shift 2
    fi
    framework=$2
    case "$framework" in
      xunit|mstest|nunit) ;;
      *) stop "usage: test-guardian.sh setup [--integration [--db sqlite] | --components] xunit|mstest|nunit <file.cs, file.razor or project>..." ;;
    esac
    shift 2
    [ $# -ge 1 ] || stop "usage: test-guardian.sh setup [--integration [--db sqlite] | --components] xunit|mstest|nunit <file.cs, file.razor or project>..."
    need_dotnet
    [ -z "$(git status --porcelain)" ] || stop "uncommitted changes: setup runs on a clean working tree, so that a failure undoes all it did"
    # the production projects of the files
    prods=$(for f in "$@"; do
      p=$(repo_path "$f") || { echo "MISSING $f"; continue; }
      case "$p" in
        *.csproj) printf '%s\n' "$p" ;;
        *) project_of "$p" || echo "MISSING $f" ;;
      esac
    done | sort -u)
    missing=$(printf '%s\n' "$prods" | sed -n 's/^MISSING //p' | tr '\n' ' ')
    [ -z "$missing" ] || stop "no project file for: $missing"
    prods=$(printf '%s\n' "$prods" | while IFS= read -r p; do in_tests "$p" || printf '%s\n' "$p"; done)
    [ -n "$prods" ] || stop "these files belong to test projects only"
    webs=""
    if [ "$kind" = integration ]; then
      # the API tests run an ASP.NET Core project in memory: its web projects only
      webs=$(printf '%s\n' "$prods" | while IFS= read -r p; do grep -q 'Sdk="Microsoft.NET.Sdk.Web"' "$p" 2>/dev/null && printf '%s\n' "$p"; done)
      [ -n "$webs" ] || stop "$(printf '%s\n' "$prods" | tr '\n' ' ')is not an ASP.NET Core project (Sdk=\"Microsoft.NET.Sdk.Web\"): the API tests run one"
      prods=$webs
      done_already=$(test_projects | while IFS= read -r t; do grep -qi 'Microsoft.AspNetCore.Mvc.Testing' "$t" && { printf '%s\n' "$t"; break; }; done)
      if [ -n "$done_already" ] && [ "$db" = sqlite ] && ! grep -qi 'Microsoft.EntityFrameworkCore.Sqlite' "$done_already"; then
        # the integration test project is there: SQLite added to it, of the EF Core version of the API
        major=$(target_of "$(printf '%s\n' "$webs" | head -n 1)" | sed -n 's/^net\([0-9][0-9]*\)\..*/\1/p')
        efv=$(ef_version "$major")
        mkdir -p "$folder" || stop "cannot create $folder"
        log="$folder/setup.log"
        take_lock
        props=$(central_props "$(dirname "$done_already")")
        if [ -n "$props" ]; then
          add_package_version "$props" Microsoft.EntityFrameworkCore.Sqlite "$efv"
          add_package_ref "$done_already" Microsoft.EntityFrameworkCore.Sqlite ""
        else
          add_package_ref "$done_already" Microsoft.EntityFrameworkCore.Sqlite "$efv"
        fi
        if ! dotnet build "$done_already" -nologo -v q > "$log" 2>&1; then
          git checkout -q -- . 2>/dev/null
          environment "$log"
          grep -E ': error [A-Z]+[0-9]+' "$log" | sed -E 's/ \[[^]]*\]$//' | sort -u | head -n 5
          stop "the build of $done_already fails with Microsoft.EntityFrameworkCore.Sqlite $efv: nothing changed"
        fi
        echo "SETUP: Microsoft.EntityFrameworkCore.Sqlite $efv (the EF Core version of the API) added to $done_already${props:+ (version in $props)}; build OK"
        exit 0
      fi
      [ -z "$done_already" ] || { echo "SETUP: nothing to do, $done_already has Microsoft.AspNetCore.Mvc.Testing (WebApplicationFactory)${db:+ and Microsoft.EntityFrameworkCore.Sqlite}"; exit 0; }
    fi
    if [ "$kind" = components ]; then
      # bUnit renders the components of a Blazor project: the projects of these files that hold .razor files
      blazor=$(printf '%s\n' "$prods" | while IFS= read -r p; do
        d=$(dirname "$p")
        git ls-files -- "$d" | grep -q '\.razor$' && printf '%s\n' "$p"
      done)
      [ -n "$blazor" ] || stop "$(printf '%s\n' "$prods" | tr '\n' ' ')has no Razor component (.razor file): bUnit tests the components of a Blazor project"
      prods=$blazor
      # the unit test projects (an integration test project of /tests api runs the API, not its components)
      units=$(test_projects | while IFS= read -r t; do grep -qi 'Microsoft.AspNetCore.Mvc.Testing' "$t" || printf '%s\n' "$t"; done)
      if [ -n "$units" ]; then
        # the one that references the project of these components; otherwise the only one, which will reference it
        target=$(printf '%s\n' "$units" | while IFS= read -r t; do
          printf '%s\n' "$prods" | while IFS= read -r p; do references "$t" "$p" && { printf '%s\n' "$t"; break; }; done
        done | head -n 1)
        if [ -z "$target" ]; then
          [ "$(printf '%s\n' "$units" | grep -c .)" -eq 1 ] ||
            stop "several unit test projects, and none references $(printf '%s\n' "$prods" | tr '\n' ' ')(add that reference to the one that tests these components, then run setup again): $(printf '%s\n' "$units" | tr '\n' ' ' | sed 's/ $//')"
          target=$units
        fi
        if grep -qi 'Include="bunit"' "$target"; then
          echo "SETUP: nothing to do, $target has bUnit"
          exit 0
        fi
        mkdir -p "$folder" || stop "cannot create $folder"
        log="$folder/setup.log"
        take_lock
        props=$(central_props "$(dirname "$target")")
        v=$(cache_version bunit "$BUNIT_DEFAULT")
        if [ -n "$props" ]; then
          add_package_version "$props" bunit "$v"
          add_package_ref "$target" bunit ""
        else
          add_package_ref "$target" bunit "$v"
        fi
        also=""
        if ! has_coverage "$target"; then
          if is_mtp "$target"; then
            id=Microsoft.Testing.Extensions.CodeCoverage cv=$(cache_version Microsoft.Testing.Extensions.CodeCoverage 18.6.2)
          else
            id=coverlet.collector cv=$(cache_version coverlet.collector 6.0.4)
          fi
          if [ -n "$props" ]; then
            add_package_version "$props" "$id" "$cv"
            add_package_ref "$target" "$id" ""
          else
            add_package_ref "$target" "$id" "$cv"
          fi
          also="; $id $cv too (its coverage collector)"
        fi
        refs=$(printf '%s\n' "$prods" | while IFS= read -r p; do references "$target" "$p" || printf '%s\n' "$p"; done)
        if [ -n "$refs" ] && ! printf '%s\n' "$refs" | tr '\n' '\0' | xargs -0 dotnet add "$target" reference > "$log" 2>&1; then
          git checkout -q -- . 2>/dev/null
          stop "dotnet add reference failed: $(grep -v '^[[:space:]]*$' "$log" | tail -n 2 | tr '\n' ' ')"
        fi
        if ! dotnet build "$target" -nologo -v q > "$log" 2>&1; then
          git checkout -q -- . 2>/dev/null
          environment "$log"
          grep -E ': error [A-Z]+[0-9]+' "$log" | sed -E 's/ \[[^]]*\]$//' | sort -u | head -n 5
          stop "the build of $target fails with bUnit $v: nothing changed"
        fi
        echo "SETUP: bunit $v added to $target${props:+ (version in $props)}$also${refs:+; it references $(printf '%s\n' "$refs" | tr '\n' ' ' | sed 's/ $//') now}; build OK"
        exit 0
      fi
    fi
    mkdir -p "$folder" || stop "cannot create $folder"
    log="$folder/setup.log"
    take_lock
    built=""
    undo() {
      # the folder it created, and the parent folders that hold nothing else now (tests/ of a first test project)
      [ -n "$built" ] && rm -rf "$built" && rmdir -p "$(dirname "$built")" 2>/dev/null
      git checkout -q -- . 2>/dev/null
    }
    # Test projects already there: the coverage collector where it lacks, nothing else (coverlet.collector for VSTest,
    # Microsoft.Testing.Extensions.CodeCoverage for Microsoft.Testing.Platform)
    existing=$(test_projects)
    if [ -n "$existing" ] && [ "$kind" = unit ]; then
      added="" props="" ids=""
      while IFS= read -r t; do
        has_coverage "$t" && continue
        if is_mtp "$t"; then
          id=Microsoft.Testing.Extensions.CodeCoverage v=$(cache_version Microsoft.Testing.Extensions.CodeCoverage 18.6.2)
        else
          id=coverlet.collector v=$(cache_version coverlet.collector 6.0.4)
        fi
        props=$(central_props "$(dirname "$t")")
        if [ -n "$props" ]; then
          add_package_version "$props" "$id" "$v"
          add_package_ref "$t" "$id" ""
        else
          add_package_ref "$t" "$id" "$v"
        fi
        added="$added$t
"
        case " $ids " in *" $id $v "*) ;; *) ids="$ids $id $v," ;; esac
      done <<EOF
$existing
EOF
      [ -n "$added" ] || { echo "SETUP: nothing to do, every test project has its coverage collector"; exit 0; }
      while IFS= read -r t; do
        [ -n "$t" ] || continue
        if ! dotnet build "$t" -nologo -v q > "$log" 2>&1; then
          undo
          environment "$log"
          grep -E ': error [A-Z]+[0-9]+' "$log" | sed -E 's/ \[[^]]*\]$//' | sort -u | head -n 5
          stop "the build of $t fails with its coverage collector: nothing changed"
        fi
      done <<EOF
$added
EOF
      echo "SETUP:${ids%,} added to $(printf '%s' "$added" | tr '\n' ' ' | sed 's/ $//')${props:+ (version in $props)}; build OK"
      exit 0
    fi
    # A new test project: named after the solution that builds these projects, in its tests folder
    first=$(printf '%s\n' "$prods" | head -n 1)
    # the solutions that list one of these projects ("…\Api.csproj" in a .sln, "…/Api.csproj" in a .slnx)
    slns=$(git ls-files '*.sln' '*.slnx' | while IFS= read -r s; do
      printf '%s\n' "$prods" | while IFS= read -r p; do
        bn=$(basename "$p" | sed 's/[].[*^$\\]/\\&/g')
        grep -qE "[\"/\\\\]$bn\"" "$s" 2>/dev/null && { printf '%s\n' "$s"; break; }
      done
    done | sort -u)
    sln1=$(printf '%s\n' "$slns" | head -n 1)
    if [ -n "$sln1" ]; then
      base=$(basename "$sln1"); base=${base%.*}; home=$(dirname "$sln1")
    else
      base=$(basename "$first" .csproj); home=.
    fi
    name="$base.UnitTests"
    [ "$kind" = integration ] && name="$base.IntegrationTests"
    if [ -d "$home/test" ] && [ ! -d "$home/tests" ]; then dir="$home/test/$name"
    elif [ -d "$home/tests" ] || [ -d "$home/src" ]; then dir="$home/tests/$name"
    else dir="$home/$name"; fi
    dir=${dir#./}
    [ ! -e "$dir" ] || stop "$dir exists already: nothing created"
    tfm=$(target_of "$first")
    case "$tfm" in
      legacy) stop "$first is a .NET Framework project: it does not build on this machine (Linux)" ;;
      *-windows*) stop "$first targets $tfm: a Windows project does not build on this machine" ;;
    esac
    built=$dir
    if ! dotnet new "$framework" -o "$dir" -n "$name" ${tfm:+-f "$tfm"} --no-update-check --no-restore > "$log" 2>&1; then
      rm -rf "$dir"
      dotnet new "$framework" -o "$dir" -n "$name" --no-update-check --no-restore > "$log" 2>&1 ||
        { undo; stop "dotnet new $framework failed: $(grep -v '^[[:space:]]*$' "$log" | tail -n 2 | tr '\n' ' ')"; }
      [ -n "$tfm" ] && sed "s:<TargetFramework>[^<]*</TargetFramework>:<TargetFramework>$tfm</TargetFramework>:" \
        "$dir/$name.csproj" > "$dir/$name.csproj.new" && mv "$dir/$name.csproj.new" "$dir/$name.csproj"
    fi
    csproj="$dir/$name.csproj"
    # the template of this SDK may run Microsoft.Testing.Platform: its coverage is then the CodeCoverage extension
    mtp_template=0
    is_mtp "$csproj" && mtp_template=1
    # the example test of the template is not kept: the test-guardian writes the real ones
    rm -f "$dir/UnitTest1.cs" "$dir/Test1.cs"
    if [ "$mtp_template" -eq 1 ]; then
      grep -qi 'Microsoft.Testing.Extensions.CodeCoverage\|Sdk="MSTest.Sdk' "$csproj" ||
        add_package_ref "$csproj" Microsoft.Testing.Extensions.CodeCoverage 18.6.2
    else
      grep -qi 'coverlet.collector' "$csproj" || add_package_ref "$csproj" coverlet.collector 6.0.4
    fi
    # the tests of Razor components render them with bUnit
    [ "$kind" = components ] && add_package_ref "$csproj" bunit "$BUNIT_DEFAULT"
    # WebApplicationFactory: Microsoft.AspNetCore.Mvc.Testing of the major version of the target framework (8.0.x for
    # net8.0: a later one targets a later .NET only)
    major=$(printf '%s' "$tfm" | sed -n 's/^net\([0-9][0-9]*\)\..*/\1/p')
    [ "$kind" = integration ] && add_package_ref "$csproj" Microsoft.AspNetCore.Mvc.Testing "${major:-10}.0.0"
    # the in-memory database of the DbContext of the API, of its EF Core version (a provider of another version would
    # not restore or not run beside it)
    [ "$db" = sqlite ] && add_package_ref "$csproj" Microsoft.EntityFrameworkCore.Sqlite "$(ef_version "${major:-10}")"
    # the versions this machine already uses, otherwise the template's; the central versions file when there is one
    props=$(central_props "$dir")
    versions=""
    pvs=$(sed -n 's/.*<PackageReference Include="\([^"]*\)" Version="\([^"]*\)".*/\1=\2/p' "$csproj")
    while IFS= read -r pv; do
      [ -n "$pv" ] || continue
      id=${pv%%=*} v=${pv#*=}
      case "$id" in
        Microsoft.AspNetCore.Mvc.Testing) nv=$(cache_version_major "$id" "${major:-10}" "$v") ;;
        Microsoft.EntityFrameworkCore.Sqlite) nv=$v ;;
        *) nv=$(cache_version "$id" "$v") ;;
      esac
      how=""
      [ "$nv" = "$v" ] || how=" (cache)"
      if [ -n "$props" ]; then
        if grep -qi "<PackageVersion[^>]*Include=\"$id\"" "$props"; then
          nv="" how="(central)"
        else
          add_package_version "$props" "$id" "$nv"
        fi
        awk -v id="$id" 'index($0, "Include=\"" id "\"") && /<PackageReference / { sub(/ Version="[^"]*"/, "") } { print }' \
          "$csproj" > "$csproj.new" && mv "$csproj.new" "$csproj"
      elif [ "$nv" != "$v" ]; then
        awk -v id="$id" -v nv="$nv" 'index($0, "Include=\"" id "\"") && /<PackageReference / { sub(/Version="[^"]*"/, "Version=\"" nv "\"") } { print }' \
          "$csproj" > "$csproj.new" && mv "$csproj.new" "$csproj"
      fi
      versions="$versions, $id $nv$how"
    done <<EOF
$pvs
EOF
    if ! printf '%s\n' "$prods" | tr '\n' '\0' | xargs -0 dotnet add "$csproj" reference > "$log" 2>&1; then
      undo
      stop "dotnet add reference failed: $(grep -v '^[[:space:]]*$' "$log" | tail -n 2 | tr '\n' ' ')"
    fi
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      if ! dotnet sln "$s" add "$csproj" > "$log" 2>&1; then
        undo
        stop "dotnet sln $s add failed: $(grep -v '^[[:space:]]*$' "$log" | tail -n 2 | tr '\n' ' ')"
      fi
    done <<EOF
$slns
EOF
    # before .NET 10, the Program class of top-level statements is internal: WebApplicationFactory<Program> needs it
    # public (.NET 10 makes it public itself)
    program=""
    if [ "$kind" = integration ] && [ "${major:-10}" -lt 10 ]; then
      while IFS= read -r w; do
        [ -n "$w" ] || continue
        d=$(dirname "$w")
        pf="$d/Program.cs"
        [ -f "$pf" ] || continue
        git grep -q -E 'class[[:space:]]+Program([^A-Za-z0-9_]|$)' -- "$d" 2>/dev/null && continue
        grep -q -E 'WebApplication\.Create' "$pf" || continue
        printf '\n// WebApplicationFactory<Program> of the integration tests needs a public entry point before .NET 10\npublic partial class Program { }\n' >> "$pf"
        program="$program${program:+, }$pf"
      done <<EOF
$webs
EOF
    fi
    if ! dotnet build "$csproj" -nologo -v q > "$log" 2>&1; then
      undo
      environment "$log"
      grep -E ': error [A-Z]+[0-9]+' "$log" | sed -E 's/ \[[^]]*\]$//' | sort -u | head -n 5
      stop "the new test project does not build: nothing created"
    fi
    echo "SETUP: $csproj created ($framework${tfm:+, $tfm}), it references $(printf '%s\n' "$prods" | tr '\n' ' ' | sed 's/ $//'); packages:${versions#,}${props:+; versions in $props}${slns:+; added to $(printf '%s\n' "$slns" | tr '\n' ' ' | sed 's/ $//')}${program:+; public partial class Program added to $program}; build OK"
    exit 0 ;;

  changes)
    base=$2 target=$3
    [ -n "$base" ] || stop "usage: test-guardian.sh changes <base branch> [<solution, project or folder>]"
    git rev-parse --verify -q "$base^{commit}" >/dev/null || stop "unknown base $base"
    need_dotnet
    mkdir -p "$folder" || stop "cannot create $folder"
    take_lock
    results="$folder/results-changes"
    rm -rf "$results"
    # the whole suite once, with coverlet: build-test.sh prints its usual BUILD, TESTS and FAILED TESTS lines
    sh "$(dirname "$0")/build-test.sh" ${target:+"$target"} --collect:"XPlat Code Coverage" --results-directory "$results" \
      --blame-hang-timeout "$HANG" --blame-hang-dump-type none
    status=$?
    # the source files the branch changed (committed or not), outside the test projects and the generated code
    fork=$(git merge-base "$base" HEAD) || stop "no common history with $base"
    tests=$(test_projects | while read -r p; do dirname "$p"; done)
    git diff -U0 --no-color "$fork" -- '*.cs' '*.razor' > "$folder/changes.diff" 2>/dev/null
    reports=$(find "$results" -name '*.cobertura.xml' 2>/dev/null)
    if [ -z "$reports" ]; then
      echo "COVERAGE OF THE CHANGES: not measured (no coverage report: the build failed, or the coverage collector is missing in the test projects: coverlet.collector, or Microsoft.Testing.Extensions.CodeCoverage for Microsoft.Testing.Platform)"
      exit "$status"
    fi
    # "FILE <path>" and "LINE <n>" for each changed line; then each report: "REPORT", "CLASS <file>", "HIT <n> <hits>"
    { awk '/^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); print "FILE " f; next }
           /^@@ / { if (match($0, /\+[0-9]+(,[0-9]+)?/)) { s = substr($0, RSTART + 1, RLENGTH - 1); n = split(s, p, ",");
                    start = p[1] + 0; count = (n > 1) ? p[2] + 0 : 1; for (i = 0; i < count; i++) print "LINE " start + i } }' "$folder/changes.diff"
      for r in $reports; do
        echo "REPORT"
        awk '/<class / { if (match($0, /filename="[^"]*"/)) { fn = substr($0, RSTART + 10, RLENGTH - 11); gsub(/\\/, "/", fn); print "CLASS " fn } next }
             /<line / { if (match($0, /number="[0-9]+"/)) { n = substr($0, RSTART + 8, RLENGTH - 9); match($0, /hits="[0-9]+"/); print "HIT " n " " substr($0, RSTART + 6, RLENGTH - 7) } }' "$r"
      done
      for d in $tests; do echo "TESTDIR $d"; done
    } | awk '
      $1 == "FILE" { cur = substr($0, 6); files[++nf] = cur; next }
      $1 == "LINE" { changed[cur, $2] = 1; next }
      $1 == "TESTDIR" { testdir[++nt] = substr($0, 9); next }
      $1 == "REPORT" { next }
      $1 == "CLASS" { name = substr($0, 7); cls = ""; for (i = 1; i <= nf; i++) if (ends(files[i], name) || ends(name, files[i])) cls = files[i]; next }
      $1 == "HIT" && cls != "" { coverable[cls, $2] = 1; if ($3 > 0) hit[cls, $2] = 1; next }
      END {
        for (i = 1; i <= nf; i++) {
          f = files[i]
          if (f ~ /(^|\/)(bin|obj|Migrations)\// || f ~ /\.(Designer|g|g\.i)\.cs$/ || f ~ /ModelSnapshot\.cs$/) continue
          skip = 0; for (t = 1; t <= nt; t++) if (index(f, testdir[t] "/") == 1) skip = 1
          if (skip) continue
          c = 0; n = 0; miss = ""
          for (key in changed) { split(key, k, SUBSEP); if (k[1] != f) continue
            if ((f, k[2]) in coverable) { n++; if ((f, k[2]) in hit) c++; else miss = miss " " k[2] } }
          if (n == 0) continue
          sorted = sortnum(miss)
          printf "CHANGED: %s %d/%d changed lines covered%s\n", f, c, n, (c < n ? "; not covered:" ranges(sorted) : "")
          tc += c; tn += n; files_n++
        }
        if (tn == 0) { print "COVERAGE OF THE CHANGES: no changed line that a test could run (no source change, or only declarations)"; exit }
        printf "COVERAGE OF THE CHANGES: %d/%d changed lines covered (%d%%) in %d files; %d not covered\n", tc, tn, int(100 * tc / tn), files_n, tn - tc
      }
      function ends(a, b) { return length(a) >= length(b) && substr(a, length(a) - length(b) + 1) == b && (length(a) == length(b) || substr(a, length(a) - length(b), 1) == "/") }
      function sortnum(s,   a, n, i, j, t, out) {
        n = split(s, a, " ")
        for (i = 2; i <= n; i++) { t = a[i] + 0; j = i - 1; while (j >= 1 && a[j] + 0 > t) { a[j + 1] = a[j]; j-- } a[j + 1] = t }
        out = ""; for (i = 1; i <= n; i++) out = out " " a[i]; return out
      }
      function ranges(s,   a, n, i, out, start, prev) {
        n = split(s, a, " "); if (n == 0) return ""
        out = ""; start = a[1]; prev = a[1]
        for (i = 2; i <= n + 1; i++) {
          if (i <= n && a[i] == prev + 1) { prev = a[i]; continue }
          out = out " " (start == prev ? start : start "-" prev)
          if (i <= n) { start = a[i]; prev = a[i] }
        }
        return out
      }'
    exit "$status" ;;

  *) stop "usage: test-guardian.sh deps <file> | coverage <label> <project> <file>... | compare <a> <b> | red|green <project> <filter> | build <project> | tests-only | seal <label> [<file>...] | sealed <label> | restore <label> | park|unpark <label> | setup [--integration [--db sqlite] | --components] xunit|mstest|nunit <file>... | changes <base> [<target>] | folder" ;;
esac
