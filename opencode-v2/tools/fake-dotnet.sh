#!/bin/sh
# A fake dotnet for tools/dotnet-test.sh (never installed by the pack): enough of `dotnet build`, `dotnet msbuild -getProperty`, `dotnet test`
# (VSTest mode) and `dotnet exec <test app>` (Microsoft.Testing.Platform) to test the pack's scripts without a .NET SDK.
# The output formats are those of VSTest's console logger and of MTP's terminal reporter (microsoft/testfx,
# TerminalTestReporter: "failed <name> (12ms)", "Test run summary: Failed! - <dll> (<tfm>|<arch>)", "  total: n"…).
# A test project declares its fake tests in comments:
#   <!-- fake-test: <fully qualified name> pass|fail <message>|hang|flaky -->
#   <!-- fake-cover: <source file> <line>:<hits> ... -->   (the coverage report of a run with coverage)
#   <!-- fake-mtp-v2 -->                                   (dotnet test in VSTest mode refuses it, as the .NET 10 SDK)
#   <!-- fake-build-error -->                              (its build fails)
#   <!-- fake-mtp-old -->                                  (a platform older than 1.5: no --timeout)
#   <!-- fake-ansi -->                                     (colors in the output of the test application)
# $FAKE_DOTNET_STATE: a folder for the state of the flaky tests; FAKE_TEMPLATE=mtp: `dotnet new mstest` makes an
# MSTest.Sdk project (the template of a recent SDK)
# Every call is logged, one line, to $FAKE_DOTNET_LOG.
[ -n "$FAKE_DOTNET_LOG" ] && printf '%s\n' "dotnet $*" >> "$FAKE_DOTNET_LOG"

abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd)" "$1" ;; esac; }
name_of() { n=$(basename "$1"); printf '%s\n' "${n%.*}"; }
dll_of() { d=$(cd "$(dirname "$1")" && pwd); printf '%s/bin/Debug/net10.0/%s.dll\n' "$d" "$(name_of "$1")"; }

# the projects of a target (a project, a solution, or the solution/project of the current folder)
projects_of() {
  t=$1
  if [ -z "$t" ]; then
    t=$(ls ./*.sln ./*.slnx ./*.csproj 2>/dev/null | head -n 1)
  fi
  case "$t" in
    *.sln) d=$(dirname "$t"); sed -n 's/^Project("[^"]*") = "[^"]*", "\([^"]*\.csproj\)".*/\1/p' "$t" | tr '\\' '/' | while read -r p; do printf '%s/%s\n' "$d" "$p"; done ;;
    *.slnx) d=$(dirname "$t"); sed -n 's/.*Path="\([^"]*\.csproj\)".*/\1/p' "$t" | while read -r p; do printf '%s/%s\n' "$d" "$p"; done ;;
    *) printf '%s\n' "$t" ;;
  esac
}

# the fake tests of a project that a filter selects: "<name>|<outcome>|<message>"
selected() {
  proj=$1 mode=$2
  shift 2
  sed -n 's/.*<!-- fake-test: \([^ ]*\) \([a-z]*\) *\(.*\) -->.*/\1|\2|\3/p' "$proj" | while IFS='|' read -r n o m; do
    keep=1
    if [ "$mode" = vstest ] && [ -n "$1" ]; then
      keep=0
      for term in $(printf '%s' "$1" | tr '|' ' '); do
        v=${term#FullyQualifiedName~}
        case "$n" in *"$v"*) keep=1 ;; esac
      done
    elif [ "$mode" = method ] && [ $# -gt 0 ]; then
      keep=0
      for v in "$@"; do
        case "$v" in
          \**\*) w=${v#\*}; w=${w%\*}; case "$n" in *"$w"*) keep=1 ;; esac ;;
          *) [ "$n" = "$v" ] && keep=1 ;;
        esac
      done
    elif [ "$mode" = tree ] && [ -n "$1" ]; then
      # /<assembly>/<namespace>/<class>/<method>, alternatives (A)|(B) in a segment
      m=${n##*.} rest=${n%.*}
      c=${rest##*.} ns=${rest%.*}
      keep=0
      if segment "$ns" "$(printf '%s' "$1" | cut -d/ -f3)" && segment "$c" "$(printf '%s' "$1" | cut -d/ -f4)" &&
        segment "$m" "$(printf '%s' "$1" | cut -d/ -f5)"; then
        keep=1
      fi
    fi
    [ "$keep" -eq 1 ] && printf '%s|%s|%s\n' "$n" "$o" "$m"
  done
}

segment() {
  set -f
  for alt in $(printf '%s' "$2" | tr '|' ' '); do
    alt=${alt#(}
    alt=${alt%)}
    # shellcheck disable=SC2254 # the segment is a pattern
    case "$1" in $alt) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

outcome() {
  # flaky: pass, then fail, then pass… (a counter next to the project)
  if [ "$2" = flaky ]; then
    f="${FAKE_DOTNET_STATE:-${TMPDIR:-/tmp}}/flaky-$(name_of "$1")"
    c=$(cat "$f" 2>/dev/null || echo 0)
    echo $((c + 1)) > "$f"
    [ $((c % 2)) -eq 0 ] && echo pass || echo fail
  else
    echo "$2"
  fi
}

cobertura() {
  # cobertura <project> <file>
  mkdir -p "$(dirname "$2")"
  top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<coverage line-rate="0.5" branch-rate="0" version="1.9"><packages><package name="p"><classes>'
    sed -n 's/.*<!-- fake-cover: \(.*\) -->.*/\1/p' "$1" | while read -r file rest; do
      echo "<class name=\"C\" filename=\"$top/$file\" line-rate=\"0.5\"><lines>"
      for lh in $rest; do echo "<line number=\"${lh%%:*}\" hits=\"${lh#*:}\" branch=\"False\" />"; done
      echo "</lines></class>"
    done
    echo '</classes></package></packages></coverage>'
  } > "$2"
}

case "$1" in
  --version) echo "10.0.100"; exit 0 ;;
  build)
    shift
    t=""
    case "$1" in ""|-*) ;; *) t=$1 ;; esac
    status=0
    for p in $(projects_of "$t"); do
      if grep -q 'fake-build-error' "$p" 2>/dev/null; then
        echo "$(dirname "$p")/Broken.cs(3,5): error CS0103: The name 'x' does not exist in the current context [$(abs "$p")]"
        status=1
      else
        d=$(dll_of "$p"); mkdir -p "$(dirname "$d")"; : > "$d"
      fi
    done
    exit $status ;;
  msbuild)
    p=$2
    case " $* " in *" -getProperty:TargetPath"*) dll_of "$p" ;; *" -getProperty:TargetFrameworks"*) echo "" ;; esac
    exit 0 ;;
  test)
    shift
    t=""
    case "$1" in ""|-*) ;; *) t=$1; shift ;; esac
    filter="" logger="" results="" collect=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --filter) filter=$2; shift 2 ;;
        --logger) logger=$2; shift 2 ;;
        --results-directory) results=$2; shift 2 ;;
        --collect:*) collect=1; shift ;;
        --collect) collect=1; shift 2 ;;
        --blame-hang-timeout|--blame-hang-dump-type) shift 2 ;;
        *) shift ;;
      esac
    done
    status=0 any=0
    for p in $(projects_of "$t"); do
      grep -q 'fake-test:' "$p" 2>/dev/null || continue
      any=1
      if grep -q 'fake-mtp-v2' "$p"; then
        echo "/usr/share/dotnet/sdk/10.0.100/Microsoft.TestPlatform.targets(48,5): error : Testing with VSTest target is no longer supported by Microsoft.Testing.Platform on .NET 10 SDK and later. If you use dotnet test, you should opt-in to the new dotnet test experience. For more information, see https://aka.ms/dotnet-test-mtp-error [$(abs "$p")]"
        status=1
        continue
      fi
      list=$(selected "$p" vstest "$filter")
      if [ -z "$list" ]; then echo "No test matches the given testcase filter \`$filter\` in $(dll_of "$p")"; continue; fi
      passed=0 failed=0
      while IFS='|' read -r n o m; do
        [ -n "$n" ] || continue
        o=$(outcome "$p" "$o")
        case "$o" in
          pass) passed=$((passed + 1)); case "$logger" in *normal*) echo "  Passed $n [12 ms]" ;; esac ;;
          hang)
            echo "The active test run was aborted. Reason: Test host process crashed"
            echo "Blame: the test host was stopped after an inactivity time of 00:05:00"
            echo "The test running when the crash occurred:"
            echo "$n"
            echo ""
            echo "Test Run Aborted."
            exit 1 ;;
          *) failed=$((failed + 1)); echo "  Failed $n [15 ms]"; echo "  Error Message:"; echo "   $m"; echo "  Stack Trace:"; echo "     at $n() in /src/T.cs:line 9" ;;
        esac
      done <<EOF
$list
EOF
      [ "$failed" -gt 0 ] && { verdict=Failed; status=1; } || verdict=Passed
      echo "$verdict!  - Failed:     $failed, Passed:     $passed, Skipped:     0, Total:     $((passed + failed)), Duration: 30 ms - $(name_of "$p").dll (net10.0)"
      [ "$collect" -eq 1 ] && [ -n "$results" ] && cobertura "$p" "$results/$(name_of "$p")-guid/coverage.cobertura.xml"
    done
    [ "$any" -eq 0 ] && echo "No test source files were specified."
    exit $status ;;
  exec)
    dll=$2
    shift 2
    projdir=$(cd "$(dirname "$dll")/../../.." && pwd)
    p=$(ls "$projdir"/*.csproj | head -n 1)
    mode=all values="" results="" coverage=0 coverout="" coverlet=0 timeout=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --filter) mode=vstest; values=$2; shift 2 ;;
        --filter-method) mode=method; shift; values=""; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do values="$values $1"; shift; done ;;
        --treenode-filter) mode=tree; values=$2; shift 2 ;;
        --timeout)
          grep -q 'fake-mtp-old' "$p" && { echo "Unknown option '--timeout'"; exit 5; }
          timeout=$2; shift 2 ;;
        --results-directory) results=$2; shift 2 ;;
        --coverage) coverage=1; shift ;;
        --coverage-output-format) shift 2 ;;
        --coverage-output) coverout=$2; shift 2 ;;
        --coverlet) coverlet=1; shift ;;
        --coverlet-output-format) shift 2 ;;
        *) echo "Unknown option '$1'"; exit 5 ;;
      esac
    done
    if [ "$coverage" -eq 1 ] && ! grep -q 'Microsoft.Testing.Extensions.CodeCoverage\|Sdk="MSTest.Sdk' "$p"; then echo "Unknown option '--coverage'"; exit 5; fi
    if [ "$mode" = method ]; then
      # shellcheck disable=SC2086 # the values are words
      list=$(set -f; selected "$p" method $values)
    else
      list=$(selected "$p" "$mode" "$values")
    fi
    passed=0 failed=0
    while IFS='|' read -r n o m; do
      [ -n "$n" ] || continue
      o=$(outcome "$p" "$o")
      case "$o" in
        pass) passed=$((passed + 1)) ;;
        hang) echo "failed (cancelled) $n (${timeout:-5m})"; echo "Test run summary: Aborted! - $dll (net10.0|x64)"; exit 3 ;;
        *)
          failed=$((failed + 1))
          if grep -q 'fake-ansi' "$p"; then printf '\033[31mfailed\033[0m %s \033[90m(15ms)\033[0m\n' "$n"; else echo "failed $n (15ms)"; fi
          echo "  $m"; echo "    at $n() in /src/T.cs:line 9" ;;
      esac
    done <<EOF
$list
EOF
    total=$((passed + failed))
    if [ "$total" -eq 0 ]; then verdict="Zero tests ran"; elif [ "$failed" -gt 0 ]; then verdict="Failed!"; else verdict="Passed!"; fi
    echo ""
    echo "Test run summary: $verdict - $dll (net10.0|x64)"
    echo "  total: $total"
    echo "  failed: $failed"
    echo "  succeeded: $passed"
    echo "  skipped: 0"
    echo "  duration: 31ms"
    [ "$coverage" -eq 1 ] && cobertura "$p" "${coverout:-$results/coverage.cobertura.xml}"
    [ "$coverlet" -eq 1 ] && cobertura "$p" "$results/coverage.cobertura.xml"
    [ "$total" -eq 0 ] && exit 8
    [ "$failed" -gt 0 ] && exit 2
    exit 0 ;;
  new)
    template=$2
    shift 2
    dir="" name=""
    while [ $# -gt 0 ]; do
      case "$1" in -o) dir=$2; shift 2 ;; -n) name=$2; shift 2 ;; -f) tfm=$2; shift 2 ;; *) shift ;; esac
    done
    mkdir -p "$dir"
    if [ "$template" = mstest ] && [ "${FAKE_TEMPLATE:-}" = mtp ]; then
      printf '<Project Sdk="MSTest.Sdk/3.8.0">\n  <PropertyGroup>\n    <TargetFramework>%s</TargetFramework>\n  </PropertyGroup>\n</Project>\n' "${tfm:-net10.0}" > "$dir/$name.csproj"
    else
      case "$template" in xunit) pkg="xunit 2.9.2" runner="xunit.runner.visualstudio 2.8.2" ;; mstest) pkg="MSTest.TestFramework 3.6.4" runner="MSTest.TestAdapter 3.6.4" ;; *) pkg="NUnit 4.2.2" runner="NUnit3TestAdapter 4.6.0" ;; esac
      {
        echo '<Project Sdk="Microsoft.NET.Sdk">'
        echo '  <PropertyGroup>'
        echo "    <TargetFramework>${tfm:-net10.0}</TargetFramework>"
        echo '  </PropertyGroup>'
        echo '  <ItemGroup>'
        echo '    <PackageReference Include="coverlet.collector" Version="6.0.2" />'
        echo '    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />'
        echo "    <PackageReference Include=\"${pkg% *}\" Version=\"${pkg#* }\" />"
        echo "    <PackageReference Include=\"${runner% *}\" Version=\"${runner#* }\" />"
        echo '  </ItemGroup>'
        echo '</Project>'
      } > "$dir/$name.csproj"
    fi
    echo "namespace T; public class UnitTest1 { }" > "$dir/UnitTest1.cs"
    echo "The template was created successfully."
    exit 0 ;;
  sln|add|format|restore) exit 0 ;;
  run) echo "fake dotnet: dotnet run must never be called by the pack's scripts"; exit 99 ;;
  *) echo "fake dotnet: unknown command $1"; exit 99 ;;
esac
