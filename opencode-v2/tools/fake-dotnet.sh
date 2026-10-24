#!/bin/sh
# A fake dotnet for tools/dotnet-test.sh (never installed by the pack): enough of `dotnet build`, `dotnet msbuild -getProperty`, `dotnet test`
# (VSTest mode) and `dotnet exec <test app>` (Microsoft.Testing.Platform) to test the pack's scripts without a .NET SDK.
# The output formats are those of VSTest's console logger and of MTP's terminal reporter (microsoft/testfx,
# TerminalTestReporter: "failed <name> (12ms)", "Test run summary: Failed! - <dll> (<tfm>|<arch>)", "  total: n"…).
# A test project declares its fake tests in comments, in its project file or in the .cs files of its folder (a test
# file declares the tests it holds: sealing, parking or deleting it changes what runs):
#   <!-- fake-test: <fully qualified name> pass|fail <message>|hang|flaky -->
#   <!-- fake-test: <fully qualified name> env <VARIABLE>=<value> <message> -->
#                                                          (passes when the variable has that value: env-tests.sh)
#   ... category=<name> in the message: its category (a filter Category=<name> or TestCategory=<name> selects it)
#   <!-- fake-test: <fully qualified name> requires <file>:<text> <message> -->
#                                                          (passes when <file> of the repository holds <text>, fails
#                                                          with <message> otherwise: a test of the production code)
#   <!-- fake-cover: <source file> [if=|unless=<file>:<text>] [c=<class>] [m=<method>] <line>:<hits>[:<cov>/<total>] ... -->
#                                                          (the coverage of a run with coverage: c= a class of the file
#                                                          as coverlet names it, m= a method as it names it; in a test
#                                                          file, what that test runs, while the code holds or lacks
#                                                          a text)
#   <!-- fake-mtp-v2 -->                                   (dotnet test in VSTest mode refuses it, as the .NET 10 SDK)
#   <!-- fake-build-error -->                              (its build fails; in a .cs file: that file does not compile)
#   <!-- fake-mtp-old -->                                  (a platform older than 1.5: no --timeout)
#   <!-- fake-ansi -->                                     (colors in the output of the test application)
#   <!-- fake-no-cover-without-tests -->                   (a test project without tests: no coverage report, where
#                                                          coverlet writes one with every line at 0)
# $FAKE_DOTNET_STATE: a folder for the state of the flaky tests; FAKE_DOTNET_SLOW: builds take 3 s; FAKE_DOTNET_SLOW_TEST=<s>:
# a test run takes <s> seconds (test-guardians of a wave that meet on the lock); FAKE_TEMPLATE=mtp: `dotnet new mstest` makes an
# MSTest.Sdk project (the template of a recent SDK); FAKE_DOTNET_COVER: a file of fake-cover lines that replaces those
# of the projects (the coverage a run measures, changed by a test without touching the repository)
# Every call is logged, one line, to $FAKE_DOTNET_LOG.
[ -n "$FAKE_DOTNET_LOG" ] && printf '%s\n' "dotnet $*" >> "$FAKE_DOTNET_LOG"

# The SDKs and runtimes of the fake machine: FAKE_DOTNET_SDKS (versions, default 10.0.100) and FAKE_DOTNET_RUNTIMES
# ("<name> <version>" per line, default the .NET 10 runtimes); their lists answer as the real host does
sdks=${FAKE_DOTNET_SDKS:-10.0.100}
runtimes=${FAKE_DOTNET_RUNTIMES:-"Microsoft.AspNetCore.App 10.0.0
Microsoft.NETCore.App 10.0.0"}
case "$1" in
  --list-sdks) for s in $sdks; do echo "$s [/usr/share/dotnet/sdk]"; done; exit 0 ;;
  --list-runtimes)
    printf '%s\n' "$runtimes" | while read -r n v; do [ -n "$n" ] && echo "$n $v [/usr/share/dotnet/shared/$n]"; done
    exit 0 ;;
esac
# global.json: the SDK it asks for (rollForward patch when it gives none), resolved by the host before any command,
# with the message of the real host when none fits
g="" d=$(pwd)
while [ "$d" != / ]; do
  [ -f "$d/global.json" ] && { g="$d/global.json"; break; }
  d=$(dirname "$d")
done
if [ -n "$g" ]; then
  want=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$g" | head -n 1)
  roll=$(sed -n 's/.*"rollForward"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$g" | head -n 1)
  if [ -n "$want" ]; then
    fit=$(for s in $sdks; do echo "$s"; done | awk -v want="$want" -v roll="${roll:-patch}" '
      function num(v, part,   a) { sub(/-.*/, "", v); split(v, a, "."); return a[part] + 0 }
      BEGIN { M = num(want, 1); m = num(want, 2); b = int(num(want, 3) / 100); p = num(want, 3) % 100; r = tolower(roll) }
      { M2 = num($1, 1); m2 = num($1, 2); b2 = int(num($1, 3) / 100); p2 = num($1, 3) % 100
        if (r == "disable") ok = ($1 == want)
        else if (r == "patch" || r == "latestpatch") ok = (M2 == M && m2 == m && b2 == b && p2 >= p)
        else if (r == "feature" || r == "latestfeature") ok = (M2 == M && m2 == m && (b2 * 100 + p2) >= (b * 100 + p))
        else if (r == "minor" || r == "latestminor") ok = (M2 == M && (m2 * 10000 + b2 * 100 + p2) >= (m * 10000 + b * 100 + p))
        else ok = (M2 * 1000000 + m2 * 10000 + b2 * 100 + p2) >= (M * 1000000 + m * 10000 + b * 100 + p)
        if (ok) print $1 }' | tail -n 1)
    if [ -z "$fit" ]; then
      echo "The command could not be loaded, possibly because:"
      echo "  * You intended to execute a .NET application:"
      echo "      The application '$1' does not exist or is not a managed .dll or .exe."
      echo "  * You intended to execute a .NET SDK command:"
      echo "      A compatible .NET SDK was not found."
      echo ""
      echo "Requested SDK version: $want"
      echo "global.json file: $g"
      echo ""
      # as the real host (10.0): the list of the SDKs on its own stream, after the message
      echo "Installed SDKs:"
      echo ""
      echo "Install the [$want] .NET SDK or update [$g] to match an installed SDK."
      echo ""
      echo "Learn about SDK resolution:"
      echo "https://aka.ms/dotnet/sdk-not-found"
      for s in $sdks; do echo "$s [/usr/share/dotnet/sdk]"; done
      exit 155
    fi
  fi
fi
# the runtime a test project needs (its target framework, ASP.NET Core too for the tests of a web project): the
# message of the real host when this machine lacks it
missing_runtime() {
  t=$(sed -n 's:.*<TargetFramework>\([^<]*\)</TargetFramework>.*:\1:p' "$1" | head -n 1)
  case "$t" in net[0-9]*.[0-9]*) ;; *) return 1 ;; esac
  v=${t#net}; v=${v%%-*}
  for need in Microsoft.NETCore.App Microsoft.AspNetCore.App; do
    [ "$need" = Microsoft.AspNetCore.App ] && ! grep -q 'Microsoft.AspNetCore.Mvc.Testing' "$1" && continue
    printf '%s\n' "$runtimes" | grep -q "^$need $v\." && continue
    echo "Testhost process for source(s) '$(dll_of "$1")' exited with error: You must install or update .NET to run this application."
    echo "App: $(dirname "$(dll_of "$1")")/testhost.dll"
    echo "Architecture: x64"
    echo "Framework: '$need', version '$v.0' (x64)"
    echo ".NET location: /usr/share/dotnet/"
    echo "The following frameworks were found:"
    printf '%s\n' "$runtimes" | awk -v n="$need" '$1 == n { print "  " $2 " at [/usr/share/dotnet/shared/" n "]" }'
    echo "Learn more about framework resolution:"
    echo "https://aka.ms/dotnet/app-launch-failed"
    echo ". Please check the diagnostic logs for more information."
    return 0
  done
  return 1
}

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

# the project file and the .cs files of its folder (bin and obj left out): where its fake tests are declared
sources_of() {
  printf '%s\n' "$1"
  find "$(dirname "$1")" -name '*.cs' -not -path '*/bin/*' -not -path '*/obj/*' 2>/dev/null | sort
}

# the first source that does not compile in a project or in the projects it references (as dotnet builds them first)
broken_of() {
  b=$(sources_of "$1" | while IFS= read -r src; do grep -l 'fake-build-error' "$src" 2>/dev/null; done | head -n 1)
  if [ -n "$b" ]; then
    [ "$b" = "$1" ] && b="$(dirname "$1")/Broken.cs"
    printf '%s\n' "$b"
    return
  fi
  [ "${2:-0}" -ge 3 ] && return
  sed -n 's/.*<ProjectReference Include="\([^"]*\)".*/\1/p' "$1" 2>/dev/null | tr '\\' '/' | while IFS= read -r r; do
    broken_of "$(dirname "$1")/$r" $((${2:-0} + 1))
  done | head -n 1
}

# the fake tests of a project that a filter selects: "<name>|<outcome>|<message>"
selected() {
  proj=$1 mode=$2
  shift 2
  sources_of "$proj" | while IFS= read -r src; do
    sed -n 's/.*<!-- fake-test: \([^ ]*\) \([a-z]*\) *\(.*\) -->.*/\1|\2|\3/p' "$src"
  done | while IFS='|' read -r n o m; do
    keep=1
    if [ "$mode" = vstest ] && [ -n "$1" ]; then
      keep=0
      for term in $(printf '%s' "$1" | tr '|' ' '); do
        case "$term" in
          # a category (xUnit trait, NUnit Category, MSTest TestCategory): "category=<name>" in the fake-test line
          Category=*|TestCategory=*) case " $m " in *" category=${term#*=} "*) keep=1 ;; esac ;;
          *) v=${term#FullyQualifiedName~}; case "$n" in *"$v"*) keep=1 ;; esac ;;
        esac
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
  # env <VARIABLE>=<value>: the test passes when the variable has that value in its environment (env-tests.sh)
  if [ "$2" = env ]; then
    spec=${3%% *} var=${3%%=*}
    [ "$(printenv "$var" 2>/dev/null)" = "${spec#*=}" ] && echo pass || echo fail
    return
  fi
  # requires <file>:<text>: the test passes when the production code holds the text
  if [ "$2" = requires ]; then
    spec=${3%% *} top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    if grep -qF -- "${spec#*:}" "$top/${spec%%:*}" 2>/dev/null; then echo pass; else echo fail; fi
    return
  fi
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
  # cobertura <project> <file>: the report of coverlet's format, one element per line, each line of the code in its
  # method and again in the lines of its class, the names of the compiler (<Read>d__2, <Preview>b__3_0) escaped. What
  # it covers: the fake-cover lines of FAKE_DOTNET_COVER (otherwise of the project file), and those of the test files
  # of the project (a test written adds what it runs); a line listed several times keeps its most hits
  mkdir -p "$(dirname "$2")"
  top=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<coverage line-rate="0.5" branch-rate="0" version="1.9" timestamp="0" lines-covered="0" lines-valid="0">'
    echo '  <sources />'
    echo '  <packages>'
    echo '    <package name="p" line-rate="0.5" branch-rate="0" complexity="1">'
    echo '      <classes>'
    { if [ -n "${FAKE_DOTNET_COVER:-}" ]; then cat "$FAKE_DOTNET_COVER" 2>/dev/null; else cat "$1"; fi
      sources_of "$1" | sed 1d | while IFS= read -r src; do cat "$src"; done
    } | sed -n 's/.*<!-- fake-cover: \(.*\) -->.*/\1/p' | while IFS= read -r l; do
      # if=<file>:<text>, unless=<file>:<text>: lines that hold only while the code holds (or lacks) a text (a test
      # file that runs other lines once a fix changed the code)
      keep=1
      set -f
      for t in $l; do
        case "$t" in
          if=*) c=${t#if=}; grep -qF -- "${c#*:}" "$top/${c%%:*}" 2>/dev/null || keep=0 ;;
          unless=*) c=${t#unless=}; grep -qF -- "${c#*:}" "$top/${c%%:*}" 2>/dev/null && keep=0 ;;
        esac
      done
      set +f
      [ "$keep" -eq 1 ] && printf '%s\n' "$l" | sed -e 's/ if=[^ ]*//g' -e 's/ unless=[^ ]*//g'
    done | awk -v top="$top" '
      function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
      function element(k, n) {
        if (btot[k] == "") return "<line number=\"" n "\" hits=\"" hits[k] "\" branch=\"False\" />"
        return "<line number=\"" n "\" hits=\"" hits[k] "\" branch=\"True\" condition-coverage=\"" int(100 * bcov[k] / btot[k]) "% (" bcov[k] "/" btot[k] ")\" />"
      }
      function sorted(list,   a, n, i, j, x, out) {
        n = split(list, a, " ")
        for (i = 2; i <= n; i++) { x = a[i] + 0; for (j = i - 1; j >= 1 && a[j] + 0 > x; j--) a[j + 1] = a[j]; a[j + 1] = x }
        out = ""; for (i = 1; i <= n; i++) out = out " " a[i]
        return out
      }
      # a line of <file> [c=<class>] [m=<method>] <line>:<hits>[:<covered>/<total>]…: c= a class of the file as coverlet
      # names it (C when none), m= one of its methods (none: lines of the class only)
      {
        file = $1; cls = "C"; meth = ""
        if (!(file in fseen)) { fseen[file] = 1; files[++nf] = file }
        for (i = 2; i <= NF; i++) {
          t = $i
          if (t ~ /^c=/) { cls = substr(t, 3); meth = ""; continue }
          if (t ~ /^m=/) { meth = substr(t, 3); continue }
          ck = file SUBSEP cls
          if (!(ck in cseen)) { cseen[ck] = 1; classes[file] = classes[file] SUBSEP cls }
          mk = ck SUBSEP meth
          if (!(mk in mseen)) { mseen[mk] = 1; methods[ck] = methods[ck] SUBSEP meth }
          split(t, a, ":")
          n = a[1] + 0
          # the line in its method, and in its class
          for (scope = 1; scope <= 2; scope++) {
            k = (scope == 1 ? mk : ck SUBSEP "\001") SUBSEP n
            if (!(k in hits)) { hits[k] = 0; if (scope == 1) mlines[mk] = mlines[mk] " " n; else clines[ck] = clines[ck] " " n }
            if (a[2] + 0 > hits[k]) hits[k] = a[2] + 0
            if (a[3] != "") { split(a[3], b, "/"); if (btot[k] == "" || b[1] + 0 > bcov[k]) { bcov[k] = b[1] + 0; btot[k] = b[2] + 0 } }
          }
        }
      }
      END {
        for (f = 1; f <= nf; f++) {
          file = files[f]
          nc = split(substr(classes[file], 2), cl, SUBSEP)
          for (c = 1; c <= nc; c++) {
            ck = file SUBSEP cl[c]
            print "        <class name=\"" esc(cl[c]) "\" filename=\"" top "/" file "\" line-rate=\"0.5\" branch-rate=\"0\" complexity=\"1\">"
            print "          <methods>"
            nmeth = split(substr(methods[ck], 2), ml, SUBSEP)
            for (m = 1; m <= nmeth; m++) {
              if (ml[m] == "") continue
              mk = ck SUBSEP ml[m]
              print "            <method name=\"" esc(ml[m]) "\" signature=\"()\" line-rate=\"0.5\" branch-rate=\"0\" complexity=\"1\">"
              print "              <lines>"
              nl = split(sorted(mlines[mk]), ln, " ")
              for (l = 1; l <= nl; l++) print "                " element(mk SUBSEP ln[l], ln[l])
              print "              </lines>"
              print "            </method>"
            }
            print "          </methods>"
            print "          <lines>"
            nl = split(sorted(clines[ck]), ln, " ")
            for (l = 1; l <= nl; l++) print "            " element(ck SUBSEP "\001" SUBSEP ln[l], ln[l])
            print "          </lines>"
            print "        </class>"
          }
        }
      }'
    echo '      </classes>'
    echo '    </package>'
    echo '  </packages>'
    echo '</coverage>'
  } > "$2"
}

case "$1" in
  --version) echo "${fit:-$(for s in $sdks; do echo "$s"; done | tail -n 1)}"; exit 0 ;;
  build)
    shift
    # FAKE_DOTNET_SLOW: a build that takes 3 s (two builds of one folder at the same time)
    [ -n "${FAKE_DOTNET_SLOW:-}" ] && sleep 3
    t=""
    case "$1" in ""|-*) ;; *) t=$1 ;; esac
    status=0
    for p in $(projects_of "$t"); do
      broken=$(broken_of "$p")
      if [ -n "$broken" ]; then
        echo "$broken(3,5): error CS0103: The name 'x' does not exist in the current context [$(abs "$p")]"
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
    [ -n "${FAKE_DOTNET_SLOW_TEST:-}" ] && sleep "$FAKE_DOTNET_SLOW_TEST"
    t=""
    case "$1" in ""|-*) ;; *) t=$1; shift ;; esac
    filter="" logger="" results="" collect=0 nobuild=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --no-build) nobuild=1; shift ;;
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
      if ! sources_of "$p" | while IFS= read -r src; do cat "$src" 2>/dev/null; done | grep -q 'fake-test:'; then
        # a test project with no test yet (just set up): VSTest finds none, and coverlet still writes its report, each
        # line of the code at 0 (fake-no-cover-without-tests: a runner that then writes none)
        grep -q 'Microsoft.NET.Test.Sdk' "$p" 2>/dev/null || continue
        any=1
        echo "No test is available in $(dll_of "$p"). Make sure that test discoverer & executors are registered and platform & framework version settings are appropriate and try again."
        [ "$collect" -eq 1 ] && [ -n "$results" ] && ! grep -q 'fake-no-cover-without-tests' "$p" &&
          cobertura "$p" "$results/$(name_of "$p")-guid/coverage.cobertura.xml"
        continue
      fi
      any=1
      # dotnet test builds first (not with --no-build): a test file that does not compile stops it
      broken=$(broken_of "$p")
      if [ "$nobuild" -eq 0 ] && [ -n "$broken" ]; then
        echo "$broken(3,5): error CS0103: The name 'x' does not exist in the current context [$(abs "$p")]"
        status=1
        continue
      fi
      if grep -q 'fake-mtp-v2' "$p"; then
        echo "/usr/share/dotnet/sdk/10.0.100/Microsoft.TestPlatform.targets(48,5): error : Testing with VSTest target is no longer supported by Microsoft.Testing.Platform on .NET 10 SDK and later. If you use dotnet test, you should opt-in to the new dotnet test experience. For more information, see https://aka.ms/dotnet-test-mtp-error [$(abs "$p")]"
        status=1
        continue
      fi
      if missing_runtime "$p"; then
        status=1
        continue
      fi
      list=$(selected "$p" vstest "$filter")
      if [ -z "$list" ]; then echo "No test matches the given testcase filter \`$filter\` in $(dll_of "$p")"; continue; fi
      passed=0 failed=0
      # a TRX report (--logger "trx;LogFileName=<name>" with --results-directory): one result per test
      trx=""
      case "$logger" in
        trx*) [ -n "$results" ] && { mkdir -p "$results"; trx=$results/$(printf '%s' "$logger" | sed -n 's/.*LogFileName=\([^;]*\).*/\1/p'); }
              [ "$trx" = "$results/" ] && trx=$results/fake.trx
              printf '<?xml version="1.0" encoding="utf-8"?>\n<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">\n  <Results>\n' > "$trx" ;;
      esac
      while IFS='|' read -r n o m; do
        [ -n "$n" ] || continue
        case "$o" in
          requires|env) r=$(outcome "$p" "$o" "$m"); m=${m#* }; o=$r ;;
        esac
        o=$(outcome "$p" "$o")
        [ -n "$trx" ] && printf '    <UnitTestResult executionId="x" testId="y" testName="%s" computerName="fake" duration="00:00:00.0%s" startTime="2026-10-24T10:00:00" endTime="2026-10-24T10:00:01" testType="z" outcome="%s" testListId="w" />\n' \
          "$n" "$( [ "$o" = pass ] && echo 120000 || echo 150000)" "$( [ "$o" = pass ] && echo Passed || echo Failed)" >> "$trx"
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
      [ -n "$trx" ] && printf '  </Results>\n</TestRun>\n' >> "$trx"
      [ "$failed" -gt 0 ] && { verdict=Failed; status=1; } || verdict=Passed
      echo "$verdict!  - Failed:     $failed, Passed:     $passed, Skipped:     0, Total:     $((passed + failed)), Duration: 30 ms - $(name_of "$p").dll (net10.0)"
      [ "$collect" -eq 1 ] && [ -n "$results" ] && cobertura "$p" "$results/$(name_of "$p")-guid/coverage.cobertura.xml"
    done
    [ "$any" -eq 0 ] && echo "No test source files were specified."
    exit $status ;;
  exec)
    [ -n "${FAKE_DOTNET_SLOW_TEST:-}" ] && sleep "$FAKE_DOTNET_SLOW_TEST"
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
        --filter-trait) mode=vstest; values="${values:+$values|}$2"; shift 2 ;;
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
      case "$o" in
        requires|env) r=$(outcome "$p" "$o" "$m"); m=${m#* }; o=$r ;;
      esac
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
  sln)
    # dotnet sln <solution> add <project>: the project goes in the solution, as the real one does
    if [ "$3" = add ] && [ -f "$2" ]; then
      case "$2" in
        *.slnx) sed -i "s#</Solution>#  <Project Path=\"$4\" />\n</Solution>#" "$2" ;;
        *) printf 'Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "%s", "%s", "{44444444-4444-4444-4444-444444444444}"\nEndProject\n' \
             "$(name_of "$4")" "$(printf '%s' "$4" | tr '/' '\\')" >> "$2" ;;
      esac
    fi
    exit 0 ;;
  add)
    # dotnet add <project> reference <project>...: the references go in the project file, as the real one writes them
    if [ "$3" = reference ]; then
      proj=$2
      shift 3
      for r in "$@"; do
        rel=$(realpath -m --relative-to="$(dirname "$proj")" "$r")
        sed -i "s#</Project>#  <ItemGroup>\n    <ProjectReference Include=\"$rel\" />\n  </ItemGroup>\n</Project>#" "$proj"
      done
    fi
    exit 0 ;;
  pack)
    # the packable projects of the target: <name>.1.0.0.nupkg in the output folder; a "fake-breaking: <message>" in the
    # project or its files is a breaking change that package validation reports (CP0002)
    shift
    t="" o=""
    case "$1" in ""|-*) ;; *) t=$1; shift ;; esac
    while [ $# -gt 0 ]; do case "$1" in -o|--output) o=$2; shift 2 ;; *) shift ;; esac; done
    status=0
    for p in $(projects_of "$t"); do
      grep -q -i '<IsPackable>true\|<PackageId>\|<GeneratePackageOnBuild>true' "$p" 2>/dev/null || continue
      breaking=$(sources_of "$p" | while IFS= read -r src; do sed -n 's/.*fake-breaking: \(.*[^ ]\) *-->.*/\1/p; s/.*fake-breaking: \([^>]*[^ ]\) *$/\1/p' "$src"; done | head -n 3)
      if [ -n "$breaking" ]; then
        printf '%s\n' "$breaking" | while IFS= read -r m; do echo "/usr/share/dotnet/sdk/10.0.100/Sdks/Microsoft.DotNet.ApiCompat.Task/build/Microsoft.DotNet.ApiCompat.ValidatePackage.targets(39,5): error CP0002: $m [$(abs "$p")]"; done
        status=1
        continue
      fi
      [ -n "$o" ] && { mkdir -p "$o"; : > "$o/$(name_of "$p").1.0.0.nupkg"; }
    done
    exit $status ;;
  format|restore) exit 0 ;;
  run) echo "fake dotnet: dotnet run must never be called by the pack's scripts"; exit 99 ;;
  *) echo "fake dotnet: unknown command $1"; exit 99 ;;
esac
