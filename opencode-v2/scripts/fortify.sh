#!/bin/sh
# Measures and proofs of /fortify, so that the agents never judge them by eye. Run from the repository.
#   prereq                         dotnet, unit test projects, coverlet.collector in each of them, the Fortify SSC
#                                  application line: "PREREQ: ..." lines, or one "STOP:" line telling what to set up
#   deps <file.cs>                 the module of a vulnerability: the classes of the file, the types its constructors
#                                  receive (classic or primary constructor), and the files that implement them
#                                  (two levels): "MODULE:", "DEPENDS:", "UNRESOLVED:" lines
#   coverage <label> <test project> <file.cs>...
#                                  runs the tests of the project with coverlet and prints the line and branch coverage
#                                  of each file, with its uncovered lines; kept as <label> in the folder of the batch
#   compare <label before> <label after>
#                                  coverage after the fix, file by file: "STOP:" when a file lost coverage
#   red <test project> <filter>    the vulnerability tests must FAIL on the current code (and compile)
#   green <test project> <filter>  the same tests must PASS
#   tests-only                     the uncommitted changes touch only test projects
#   discard <label>                puts the uncommitted work aside (git stash, recoverable), on a batch branch only
# The batch folder: <git folder>/opencode-tickets/<KEY>.fortify (KEY from the branch), shared by the worktrees,
# never committed. Output lines are for the agents; exit 1 with one "STOP: <reason>" line when a check fails.
# Usage: fortify.sh prereq | deps <file> | coverage <label> <proj> <file>... | compare <a> <b> | red|green <proj> <filter> | tests-only

LC_ALL=C
export LC_ALL
DOTNET_CLI_UI_LANGUAGE=en DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_CLI_UI_LANGUAGE DOTNET_NOLOGO DOTNET_CLI_TELEMETRY_OPTOUT

stop() {
  echo "STOP: $1"
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || stop "not in a git repository"
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 1
common=$(git rev-parse --git-common-dir) && common=$(cd "$common" && pwd)
key=$(git branch --show-current 2>/dev/null | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n 1)
batch="$common/opencode-tickets/${key:-NOKEY}.fortify"

# The unit test projects: .csproj files that reference Microsoft.NET.Test.Sdk (outside bin and obj)
test_projects() {
  git ls-files '*.csproj' | while read -r p; do
    grep -qi 'Microsoft.NET.Test.Sdk\|MSTest.Sdk\|xunit.v3' "$p" 2>/dev/null && echo "$p"
  done
}

# coverlet.collector for a project: in the project, or in a Directory.Build.props / Directory.Packages.props /
# Directory.Build.targets of one of its folders
has_coverlet() {
  grep -qi 'coverlet.collector' "$1" 2>/dev/null && return 0
  dir=$(dirname "$1")
  while :; do
    for f in Directory.Build.props Directory.Build.targets; do
      grep -qi 'coverlet.collector' "$dir/$f" 2>/dev/null && return 0
    done
    [ "$dir" = "." ] || [ "$dir" = "/" ] && return 1
    dir=$(dirname "$dir")
  done
}

# "Passed: n" and "Failed: n" of a dotnet test output, summed over the test assemblies (VSTest or
# Microsoft.Testing.Platform summaries)
counts() {
  awk '/(Passed|Failed)!/ || /Total tests:/ || /^ *(Passed|Failed):/ {
         line = $0
         if (match(line, /Failed: *[0-9]+/)) { s = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); f += s }
         if (match(line, /Passed: *[0-9]+/)) { s = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); p += s }
       }
       # Microsoft.Testing.Platform summary ("Test run summary": failed: n, succeeded: n)
       /^ *succeeded: *[0-9]+/ { s = $0; gsub(/[^0-9]/, "", s); p += s }
       /^ *failed: *[0-9]+/ { s = $0; gsub(/[^0-9]/, "", s); f += s }
       END { printf "%d %d\n", p, f }' "$1"
}

run_tests() {
  # $1 project, $2 filter, $3 output file
  dotnet test "$1" --filter "$2" --nologo -v q > "$3" 2>&1
}

case "$1" in
  prereq)
    command -v dotnet >/dev/null 2>&1 || stop "dotnet is not on the PATH of this machine (ENVIRONMENT PROBLEM: COMMANDES.md, « Environnement »)"
    echo "PREREQ: dotnet $(dotnet --version 2>/dev/null | head -n 1)"
    projects=$(test_projects)
    [ -n "$projects" ] || stop "no unit test project in this repository (a .csproj that references Microsoft.NET.Test.Sdk): /fortify proves each fix with unit tests"
    missing=""
    for p in $projects; do
      if has_coverlet "$p"; then echo "PREREQ: test project $p (coverlet.collector)"; else missing="$missing $p"; fi
    done
    [ -z "$missing" ] || stop "coverlet.collector is missing in:$missing. To add by the developer, in its own merge request: dotnet add <project> package coverlet.collector (then /fortify again)"
    ssc=$(git grep -h '^APPSEC_PROJECT_NAME=' -- '*appsec-ci.env' 2>/dev/null | head -n 1)
    [ -n "$ssc" ] || stop "no APPSEC_PROJECT_NAME line in appsec-ci.env: the Fortify SSC application of this repository is unknown"
    echo "PREREQ: Fortify SSC application line found"
    echo "PREREQ: OK"
    exit 0 ;;

  deps)
    file=$2
    [ -f "$file" ] || stop "no file $file"
    # Type names given to the constructors of the classes of the file (classic and primary constructors)
    types=$(awk '
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
      }' "$file" | sort -u)
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

  deps-one)
    # first level only (used by deps for the second level)
    sh "$0" deps "$2" | grep '^DEPENDS: ' | grep -v ' (level 2)'
    exit 0 ;;

  coverage)
    [ $# -ge 4 ] || stop "usage: fortify.sh coverage <label> <test project> <file.cs>..."
    label=$2 project=$3
    shift 3
    [ -f "$project" ] || stop "no test project $project"
    printf '%s' "$label" | grep -qE '^[A-Za-z0-9._-]+$' || stop "bad label $label"
    mkdir -p "$batch" || stop "cannot create $batch"
    results="$batch/results-$label"
    rm -rf "$results"
    dotnet test "$project" --collect:"XPlat Code Coverage" --results-directory "$results" --nologo -v q > "$batch/test-$label.log" 2>&1
    report=$(find "$results" -name 'coverage.cobertura.xml' 2>/dev/null | head -n 1)
    if [ -z "$report" ]; then
      grep -m 3 'error CS\|error MSB\|NU1301' "$batch/test-$label.log"
      stop "no coverage report: the build failed or coverlet.collector is missing (fortify.sh prereq)"
    fi
    pf=$(counts "$batch/test-$label.log")
    echo "TESTS: ${pf% *} passed, ${pf#* } failed"
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
      }' | tee "$batch/coverage-$label.txt"
    exit 0 ;;

  compare)
    a="$batch/coverage-$2.txt" b="$batch/coverage-$3.txt"
    [ -f "$a" ] && [ -f "$b" ] || stop "missing coverage $2 or $3 (fortify.sh coverage first)"
    awk 'FNR == NR { before[$1] = $3; next }
         { split(before[$1], x, "/"); split($3, y, "/")
           pb = x[2] ? x[1] / x[2] : 0; pa = y[2] ? y[1] / y[2] : 0
           status = pa + 0.0001 < pb ? "LOST" : "ok"; if (status == "LOST") lost = lost " " $1
           was = (before[$1] == "") ? "new" : before[$1]; printf "%s %s -> %s %s\n", $1, was, $3, status }
         END { if (lost != "") { print "STOP: coverage lost after the fix in" lost; exit 1 } print "COVERAGE: no file lost coverage" }' "$a" "$b"
    exit $? ;;

  red|green)
    project=$2 filter=$3
    [ -f "$project" ] && [ -n "$filter" ] || stop "usage: fortify.sh $1 <test project> <filter>"
    mkdir -p "$batch"
    out="$batch/$1-$(date +%H%M%S).log"
    run_tests "$project" "$filter" "$out"
    if grep -q 'error CS\|error MSB' "$out"; then
      grep -m 3 'error CS\|error MSB' "$out"
      stop "the tests do not build: $([ "$1" = red ] && echo "a red test must compile against the current code (call what exists)" || echo "fix the build first")"
    fi
    pf=$(counts "$out")
    passed=${pf% *} failed=${pf#* }
    [ $((passed + failed)) -gt 0 ] || stop "no test matched the filter $filter"
    if [ "$1" = red ]; then
      [ "$passed" -eq 0 ] || stop "$passed of these tests PASS on the current code: they do not show the vulnerability"
      echo "RED: $failed tests fail on the current code, as expected"
      grep -m 5 -E '^ +(Failed |Assert|Expected|Error Message)' "$out" | sed 's/^ */  /'
    else
      [ "$failed" -eq 0 ] || stop "$failed of these tests still FAIL after the fix"
      echo "GREEN: $passed tests pass"
    fi
    exit 0 ;;

  tests-only)
    dirs=$(test_projects | while read -r p; do dirname "$p"; done)
    bad=$(git status --porcelain | cut -c4- | while read -r f; do
      ok=0
      for d in $dirs; do case "$f" in "$d"/*) ok=1 ;; esac; done
      [ "$ok" = 1 ] || echo "$f"
    done)
    [ -z "$bad" ] || stop "changes outside the test projects: $(printf '%s' "$bad" | tr '\n' ' ')"
    echo "TESTS-ONLY: OK"
    exit 0 ;;

  discard)
    # Puts aside the uncommitted work of one vulnerability that failed or was interrupted, recoverable (git stash),
    # never on another branch than a batch branch
    [ -n "$key" ] || stop "not on the branch of a batch (no key in the branch name): nothing put aside"
    label=${2:-work}
    printf '%s' "$label" | grep -qE '^[A-Za-z0-9._-]+$' || stop "bad label $label"
    n=$(git status --porcelain | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || { echo "DISCARDED: nothing to put aside"; exit 0; }
    git stash push -q --include-untracked -m "fortify $key $label" || stop "git could not put the changes aside"
    echo "DISCARDED: $n files put aside in git stash (\"fortify $key $label\": git stash list shows it, git stash pop brings it back)"
    exit 0 ;;

  *) stop "usage: fortify.sh prereq | deps <file> | coverage <label> <project> <file>... | compare <a> <b> | red|green <project> <filter> | tests-only" ;;
esac
