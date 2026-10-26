#!/bin/sh
# How the unit tests of a .NET repository run, for build-test.sh and test-guardian.sh: VSTest (the default runner of
# `dotnet test`) or Microsoft.Testing.Platform (MTP: MSTest.Sdk, the MSTest, NUnit or xUnit v3 runners, TUnit, or a
# global.json that opts in). On the .NET 10 SDK, `dotnet test` in its default mode refuses an MTP v2 project ("Testing
# with VSTest target is no longer supported"), and in its MTP mode it takes other options: the tests of an MTP project
# are run here as what they are, an application (`dotnet exec <its dll>`), with the options of the pack translated,
# without `dotnet run` (refused to the agents) and without changing the repository (no global.json to add).
#   scope [<solution, project or folder>]   the test projects of the target, one per line: "<vstest|mtp>\t<path>"
#   kind <project>                          "<vstest|mtp> <framework> <coverage extension|none>" (framework:
#                                           mstest, nunit, xunit2, xunit3, tunit or unknown)
#   projects                                every test project of the repository: "<kind>\t<path>" (/outil setup)
#   run <project> [<options of dotnet test>]
#                                           runs the tests of an MTP project (built already): --filter (VSTest
#                                           syntax: as is for MSTest and NUnit, translated for xUnit v3 into
#                                           --filter-method (Category=<name>: --filter-trait) and for TUnit into
#                                           --treenode-filter: the class, then the method), --collect "XPlat Code Coverage" (the coverage extension
#                                           of the project, Cobertura), --results-directory, and a time limit for
#                                           the run (5 minutes with a filter, 25 without or the time left to the
#                                           command, TEST_SUITE_LIMIT; none on a platform older than 1.5, which
#                                           lacks --timeout); the other VSTest options are dropped
#                                           (--logger, --blame…), anything else goes to the test app.
#                                           Prints the output of the test app, then one of "HANG:" (a test that
#                                           hangs), "TIMEOUT:" (a whole run longer than its time), "No test
#                                           matches", "COVERAGE: NOT MEASURED" when it applies; exit 0 when every
#                                           test passed, 1 otherwise
# Usage: test-platform.sh scope [<target>] | kind <project> | projects | run <project> [<options>]

LC_ALL=C
export LC_ALL
DOTNET_CLI_UI_LANGUAGE=en DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 TESTINGPLATFORM_NOBANNER=1
export DOTNET_CLI_UI_LANGUAGE DOTNET_NOLOGO DOTNET_CLI_TELEMETRY_OPTOUT TESTINGPLATFORM_NOBANNER
HANG=${TEST_GUARDIAN_HANG:-5m}
# the longest a whole test application may run without a filter; build-test.sh gives the time left to its command
# (the pack's plugin stops a command of its scripts after 45 minutes)
SUITE_LIMIT=${TEST_SUITE_LIMIT:-25m}

root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(pwd)

# The text that decides how a project runs its tests: the project, and the Directory.Build.props / .targets and
# Directory.Packages.props of its folders up to the repository root
evidence() {
  cat "$1" 2>/dev/null
  d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 0
  top=$(cd "$root" && pwd -P)
  while :; do
    for f in Directory.Build.props Directory.Build.targets Directory.Packages.props; do
      [ -f "$d/$f" ] && cat "$d/$f"
    done
    [ "$d" = "$top" ] || [ "$d" = / ] && break
    d=$(dirname "$d")
  done
}

# global.json of the repository opts every test project into MTP
mtp_global() {
  grep -qs '"runner"[[:space:]]*:[[:space:]]*"Microsoft.Testing.Platform"' "$root/global.json"
}

# "<vstest|mtp> <framework> <coverage>" of a project
kind() {
  text=$(evidence "$1")
  has() { printf '%s\n' "$text" | grep -qi -- "$1"; }
  sdk=$(grep -io 'Sdk="MSTest.Sdk' "$1" 2>/dev/null | head -n 1)
  framework=unknown
  if has 'Include="TUnit'; then framework=tunit
  elif has 'Include="xunit.v3'; then framework=xunit3
  elif has 'Include="YTest.MTP.XUnit2'; then framework=xunit2
  elif has 'Include="NUnit'; then framework=nunit
  elif [ -n "$sdk" ] || has 'Include="MSTest'; then framework=mstest
  elif has 'Include="xunit'; then framework=xunit2
  fi
  platform=vstest
  if mtp_global || [ "$framework" = tunit ] || [ -n "$sdk" ] ||
    has '<UseMicrosoftTestingPlatformRunner>[[:space:]]*true' || has '<EnableMSTestRunner>[[:space:]]*true' ||
    has '<EnableNUnitRunner>[[:space:]]*true' || has '<TestingPlatformDotnetTestSupport>[[:space:]]*true' ||
    has 'Include="YTest.MTP.XUnit2'; then
    platform=mtp
  fi
  has '<UseVSTest>[[:space:]]*true' && platform=vstest
  coverage=none
  if has 'Include="Microsoft.Testing.Extensions.CodeCoverage'; then coverage=codecoverage
  elif has 'Include="coverlet.MTP'; then coverage=coverlet-mtp
  elif [ -n "$sdk" ] && ! has '<TestingExtensionsProfile>[[:space:]]*None'; then coverage=codecoverage
  fi
  echo "$platform $framework $coverage"
}

# Whether a project file is a unit test project (the same rule as test-guardian.sh and fortify.sh, TUnit included)
is_test_project() {
  grep -qi 'Microsoft.NET.Test.Sdk\|MSTest.Sdk\|xunit.v3\|Include="MSTest"\|Include="TUnit\|<IsTestProject>[[:space:]]*true' "$1" 2>/dev/null ||
    printf '%s\n' "$1" | grep -qE '\.(Unit|Integration)?Tests?\.csproj$'
}

# The projects of a solution (.sln or .slnx), as paths from the current folder
solution_projects() {
  dir=$(dirname "$1")
  case "$1" in
    *.slnx) sed -n 's/.*Path="\([^"]*\.[cf]sproj\)".*/\1/p' "$1" ;;
    *) sed -n 's/^Project("[^"]*") = "[^"]*", "\([^"]*\.[cf]sproj\)".*/\1/p' "$1" ;;
  esac | tr '\\' '/' | while IFS= read -r p; do
    [ "$dir" = . ] && printf '%s\n' "$p" || printf '%s\n' "$dir/$p"
  done
}

# The test projects of a target: a project, a solution, a folder (its only solution or project, otherwise every test
# project under it), or the current folder
scope() {
  target=${1:-.}
  if [ -d "$target" ]; then
    found=$(cd "$target" && ls -1 ./*.sln ./*.slnx 2>/dev/null; true)
    projects=$(cd "$target" && ls -1 ./*.csproj 2>/dev/null; true)
    if [ "$(printf '%s\n' "$found" | grep -c .)" -eq 1 ]; then
      target="${target%/}/$(printf '%s' "$found" | sed 's#^\./##')"
    elif [ -z "$found" ] && [ "$(printf '%s\n' "$projects" | grep -c .)" -eq 1 ]; then
      target="${target%/}/$(printf '%s' "$projects" | sed 's#^\./##')"
    else
      git ls-files -- "$target" | grep -E '\.csproj$' | while IFS= read -r p; do printf './%s\n' "$p"; done
      return 0
    fi
  fi
  case "$target" in
    *.sln|*.slnx) solution_projects "$target" ;;
    *) printf '%s\n' "$target" ;;
  esac
}

# The names of a filter of the VSTest syntax, one per line: "~<name>" (FullyQualifiedName~, Name~, DisplayName~ or a bare
# name: contains), "=<name>" (FullyQualifiedName=: the full name), or UNTRANSLATED (another property, &, !, parentheses):
# the forms the pack uses, joined with |
names_of() {
  case "$1" in *'&'*|*'('*|*'!'*) echo UNTRANSLATED; return 0 ;; esac
  printf '%s\n' "$1" | tr '|' '\n' | while IFS= read -r term; do
    term=$(printf '%s' "$term" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$term" in
      "") ;;
      FullyQualifiedName~*) echo "~${term#FullyQualifiedName~}" ;;
      FullyQualifiedName=*) echo "=${term#FullyQualifiedName=}" ;;
      Name~*|DisplayName~*) echo "~${term#*~}" ;;
      *[=~]*) echo UNTRANSLATED ;;
      *) echo "~$term" ;;
    esac
  done
}

# The TUnit tree filters (/<assembly>/<namespace>/<class>/<method>) of these names, in the order they are tried: names
# without a dot as classes, then as methods; one dotted name as <class>.<method>, then as <namespace>.<class>.
# Fails for several dotted names (no single path holds them)
tunit_paths() {
  dotted=$(printf '%s\n' "$1" | grep -c '\.')
  count=$(printf '%s\n' "$1" | grep -c .)
  if [ "$dotted" -eq 0 ]; then
    alts=$(printf '%s\n' "$1" | sed -n 's/^~\(.*\)/*\1*/p; s/^=//p')
    if [ "$count" -gt 1 ]; then alts=$(printf '%s\n' "$alts" | sed 's/.*/(&)/' | paste -sd '|' -); fi
    printf '/*/*/%s/*\n/*/*/*/%s\n' "$alts" "$alts"
    return 0
  fi
  [ "$count" -eq 1 ] || return 1
  n=${1#?} how=${1%"$n"}
  left=${n%.*} last=${n##*.} cls=${left##*.}
  if [ "$how" = "=" ]; then
    ns=${left%.*}
    [ "$ns" = "$left" ] && ns='*'
    printf '/*/%s/%s/%s\n' "$ns" "$cls" "$last"
  else
    printf '/*/*/*%s/%s*\n/*/*%s/%s*/*\n' "$cls" "$last" "$left" "$last"
  fi
}

case "$1" in
  scope)
    scope "$2" | sed 's#^\./##' | while IFS= read -r p; do
      [ -f "$p" ] && is_test_project "$p" || continue
      printf '%s\t%s\n' "$(kind "$p" | cut -d' ' -f1)" "$p"
    done
    exit 0 ;;

  kind)
    [ -f "$2" ] || { echo "unknown none none"; exit 0; }
    kind "$2"
    exit 0 ;;

  projects)
    cd "$root" || exit 1
    git ls-files '*.csproj' '*.fsproj' | while IFS= read -r p; do
      is_test_project "$p" && printf '%s\t%s\n' "$(kind "$p")" "$p"
    done
    exit 0 ;;

  run)
    project=$2
    shift 2
    [ -f "$project" ] || { echo "TESTS: NOT RUN (no project $project)"; exit 1; }
    set -- "$@" ""
    info=$(kind "$project")
    framework=$(printf '%s' "$info" | cut -d' ' -f2)
    coverage=$(printf '%s' "$info" | cut -d' ' -f3)
    name=$(basename "$project")
    name=${name%.*}
    # the application of the tests: the output of the project (its first target framework when it has several)
    dll=$(dotnet msbuild "$project" -nologo -getProperty:TargetPath 2>/dev/null | tail -n 1 | tr -d '\r')
    if [ -z "$dll" ]; then
      tfm=$(dotnet msbuild "$project" -nologo -getProperty:TargetFrameworks 2>/dev/null | tail -n 1 | tr -d '\r' | cut -d';' -f1)
      [ -n "$tfm" ] && dll=$(dotnet msbuild "$project" -nologo -getProperty:TargetPath -p:TargetFramework="$tfm" 2>/dev/null | tail -n 1 | tr -d '\r')
    fi
    if [ -z "$dll" ] || [ ! -f "$dll" ]; then
      echo "TESTS: NOT RUN (the test application of $project is not built: ${dll:-its output path is unknown})"
      exit 1
    fi
    # the options of dotnet test, as the test application takes them; one argument per line
    args=$(mktemp "${TMPDIR:-/tmp}/test-platform.XXXXXX") || exit 1
    trap 'rm -f "$args"' EXIT
    filtered=0 results="" want_coverage=0 untranslated="" candidates=""
    while [ $# -gt 1 ]; do
      a=$1
      shift
      case "$a" in
        --filter)
          filter=$1
          shift
          filtered=1
          case "$framework" in
            xunit3)
              # traits (Category=Environment of env-tests.sh): --filter-trait, once per value (they are or'ed)
              if printf '%s' "$filter" | grep -q -E '^[[:space:]]*Category=[A-Za-z0-9_.-]+([[:space:]]*[|][[:space:]]*Category=[A-Za-z0-9_.-]+)*[[:space:]]*$'; then
                printf '%s\n' "$filter" | tr '|' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r term; do
                  printf '%s\n%s\n' --filter-trait "$term"
                done >> "$args"
                continue
              fi
              # traits and names together (env-tests.sh <environment> --filter <names>: "(Category=…)&(<names>)"):
              # xUnit v3 ands filters of different kinds, ors those of one kind
              cats=$(printf '%s' "$filter" | sed -n 's/^[[:space:]]*(\(Category=[A-Za-z0-9_.-]*\([[:space:]]*|[[:space:]]*Category=[A-Za-z0-9_.-]*\)*\))[[:space:]]*&[[:space:]]*(\(.*\))[[:space:]]*$/\1/p')
              rest=$(printf '%s' "$filter" | sed -n 's/^[[:space:]]*(\(Category=[A-Za-z0-9_.-]*\([[:space:]]*|[[:space:]]*Category=[A-Za-z0-9_.-]*\)*\))[[:space:]]*&[[:space:]]*(\(.*\))[[:space:]]*$/\3/p')
              if [ -n "$cats" ] && [ -n "$rest" ]; then
                names=$(names_of "$rest")
                if printf '%s\n' "$names" | grep -q '^UNTRANSLATED$'; then
                  untranslated=$filter
                else
                  printf '%s\n' "$cats" | tr '|' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | while IFS= read -r term; do
                    printf '%s\n%s\n' --filter-trait "$term"
                  done >> "$args"
                  printf '%s\n' "$names" | sed -n 's/^~\(.*\)/*\1*/p; s/^=//p' | while IFS= read -r m; do
                    printf '%s\n%s\n' --filter-method "$m"
                  done >> "$args"
                fi
                continue
              fi
              names=$(names_of "$filter")
              if printf '%s\n' "$names" | grep -q '^UNTRANSLATED$'; then
                untranslated=$filter
              else
                echo "--filter-method" >> "$args"
                printf '%s\n' "$names" | sed -n 's/^~\(.*\)/*\1*/p; s/^=//p' >> "$args"
              fi ;;
            tunit)
              names=$(names_of "$filter")
              candidates=$(tunit_paths "$names") || untranslated=$filter ;;
            *) printf '%s\n%s\n' --filter "$filter" >> "$args" ;;
          esac ;;
        --filter=*) set -- --filter "${a#--filter=}" "$@" ;;
        --collect|--collect:*|--collect=*)
          what=${a#--collect}
          what=${what#[:=]}
          if [ -z "$what" ]; then what=$1; shift; fi
          case "$what" in *[Cc]overage*) want_coverage=1 ;; esac ;;
        --results-directory) results=$1; shift ;;
        --results-directory=*) results=${a#*=} ;;
        --blame-hang-timeout|--blame-hang-dump-type|--logger|-l|--verbosity|-v|--settings|-s|--diag|-d|--framework|-f|--configuration|-c)
          shift ;;
        --blame*|--logger=*|--logger:*|--verbosity=*|-v:*|--nologo|-nologo|/nologo|--no-build|--no-restore) ;;
        --) ;;
        *) printf '%s\n' "$a" >> "$args" ;;
      esac
    done
    if [ -n "$untranslated" ]; then
      echo "TESTS: NOT RUN (the filter \"$untranslated\" cannot be given to $framework on Microsoft.Testing.Platform: use FullyQualifiedName~<name>, joined with | for several)"
      exit 1
    fi
    # a time limit for the whole run (MTP has no limit per test without its HangDump extension): the hang limit with a
    # filter (a test that hangs), the suite limit otherwise or when less time is left (a run that does not end in the
    # time of the command: TIMEOUT)
    secs() {
      v=$(printf '%s' "$1" | sed 's/min$/m/; s/sec$/s/')
      case "$v" in *h) echo $((${v%h} * 3600)) ;; *m) echo $((${v%m} * 60)) ;; *s) echo "${v%s}" ;; *) echo "$v" ;; esac
    }
    limit_kind=timeout limit=$SUITE_LIMIT
    if [ "$filtered" -eq 1 ] && [ "$(secs "$HANG")" -le "$(secs "$SUITE_LIMIT")" ]; then limit_kind=hang limit=$HANG; fi
    limit=$(printf '%s' "$limit" | sed 's/min$/m/; s/sec$/s/')
    report=""
    if [ -n "$results" ] || [ "$want_coverage" -eq 1 ]; then
      dir=${results:-$(dirname "$dll")/TestResults}
      case "$dir" in /*) ;; *) dir="$(pwd)/$dir" ;; esac
      dir="$dir/$name"
      mkdir -p "$dir"
      printf '%s\n%s\n' --results-directory "$dir" >> "$args"
      if [ "$want_coverage" -eq 1 ]; then
        case "$coverage" in
          codecoverage) printf '%s\n' --coverage --coverage-output-format cobertura --coverage-output "$dir/coverage.cobertura.xml" >> "$args" ;;
          coverlet-mtp) printf '%s\n' --coverlet --coverlet-output-format cobertura >> "$args" ;;
          *) report="COVERAGE: NOT MEASURED for $project (no coverage extension: Microsoft.Testing.Extensions.CodeCoverage or coverlet.MTP; test-guardian.sh setup adds the first one)" ;;
        esac
      fi
    fi
    out=$(mktemp "${TMPDIR:-/tmp}/test-platform-out.XXXXXX") || exit 1
    trap 'rm -f "$args" "$out"' EXIT
    # one run of the test application: the filter arguments of this attempt, then the options above, then the limit
    use_timeout=1 note=""
    exec_once() {
      while IFS= read -r a; do set -- "$@" "$a"; done < "$args"
      [ "$use_timeout" -eq 1 ] && set -- "$@" --timeout "$limit"
      (cd "$(dirname "$dll")" && dotnet exec "$dll" "$@") > "$out" 2>&1
      status=$?
    }
    launch() {
      exec_once "$@"
      # a platform older than 1.5 has no --timeout (exit 5, invalid command line): the same run without it
      if [ "$status" -eq 5 ] && [ "$use_timeout" -eq 1 ] && grep -qi 'timeout' "$out"; then
        use_timeout=0
        note="NOTE: the test platform of $project has no --timeout (Microsoft.Testing.Platform older than 1.5): no time limit of its own for this run"
        exec_once "$@"
      fi
    }
    echo "Tests of $project (Microsoft.Testing.Platform, $framework): its test application, $(basename "$dll")"
    if [ -n "$candidates" ]; then
      # TUnit: the name is a class, or a method (or a class and its method): the first path that runs tests
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        launch --treenode-filter "$c"
        [ "$status" -eq 8 ] || { echo "(TUnit tree filter: $c)"; break; }
      done <<LIST
$candidates
LIST
    else
      launch
    fi
    # no colors in the output the agents read
    esc=$(printf '\033')
    sed "s/$esc\[[0-9;]*[A-Za-z]//g" "$out"
    [ -n "$report" ] && echo "$report"
    [ -n "$note" ] && echo "$note"
    case "$status" in
      0) exit 0 ;;
      2) exit 1 ;;
      3)
        if [ "$use_timeout" -eq 1 ] && [ "$limit_kind" = hang ]; then
          echo "HANG: the tests of $project ran more than $limit and were stopped (a test waits for the network, a real clock or a lock, or loops): fix that test (or report it), never raise the limit"
        elif [ "$use_timeout" -eq 1 ]; then
          echo "TIMEOUT: the tests of $project ran more than $limit, the time left to this command, and were stopped"
        else
          echo "TESTS: the test session of $project was aborted (exit 3)"
        fi
        exit 1 ;;
      5) echo "TESTS: an option is unknown to the test application of $project (exit 5: its framework or a missing extension): $(grep -m 1 -i 'unknown option\|not recognized\|invalid' "$out")"; exit 1 ;;
      8) echo "No test matches the filter in $project (Microsoft.Testing.Platform: zero tests ran, exit 8)"; exit 0 ;;
      *) echo "TESTS: the test application of $project stopped with exit code $status"; exit 1 ;;
    esac ;;

  *)
    echo "usage: test-platform.sh scope [<target>] | kind <project> | projects | run <project> [<options>]"
    exit 1 ;;
esac
