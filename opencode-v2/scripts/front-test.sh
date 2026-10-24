#!/bin/sh
# Builds a front-end package and runs its unit tests ONCE, never in a watch mode, in ONE call: what build-test.sh is for
# .NET, with the same lines: "BUILD:", "TESTS:", "FAILED TESTS (<n>): <names>", "ENVIRONMENT PROBLEM:" when the
# machine is the problem (node, the package registry, Chrome for Karma, npm failing inside itself), "STOP:" when the
# package cannot be run as it is. build-test.sh calls it for a front-end target: a folder with a package.json and no
# .NET project, or a repository without .NET project.
#   - the dependencies are installed when node_modules or the test runner is missing, from the lockfile only (npm ci,
#     yarn --frozen-lockfile or --immutable, pnpm --frozen-lockfile): never a package added or upgraded;
#   - the build is the "build" script of package.json (not with a filter: the tests compile what they import);
#   - the tests are the "test" script, with what makes it run once: --watch=false (Angular CLI, Karma in ChromeHeadless),
#     --watchAll=false (Create React App), --run (Vitest); a test script that watches by itself is run without its watch
#     option; end-to-end tests (Playwright, Cypress) are left to the CI; a run that does not end within 15 minutes is
#     stopped ("HANG:");
#   - focused tests (fdescribe, fit, .only) are a failure: the other tests would silently not run;
#   - --filter <test file or test name>: only those tests, in the form of the runner (--include, a path, -t);
#   - --if-changed: nothing when the same code passed this same run already (its memory is apart from .NET's).
# One build or test run at a time in a working tree, shared with build-test.sh and test-guardian.sh ("WAIT:").
# Usage: front-test.sh [--if-changed] [--build-only | --no-build] [<folder>] [--filter <file or name>] [<runner options>...]

here=$(cd "$(dirname "$0")" && pwd)
build_only=0 no_build=0 if_changed=0
while :; do
  case "$1" in
    --build-only) build_only=1; shift ;;
    --no-build) no_build=1; shift ;;
    --if-changed) if_changed=1; shift ;;
    *) break ;;
  esac
done
target=""
case "$1" in ""|-*) ;; *) target=$1; shift ;; esac
filter=""
if [ "$1" = --filter ]; then
  filter=$2
  shift 2
fi
# a command that may not end (a browser that never starts): stopped after 15 minutes, with every process it started
# (timeout of GNU coreutils, gtimeout on a Mac with Homebrew's coreutils; without either, OpenCode stops the command)
limit=${FRONT_TEST_TIMEOUT:-900}
if [ "$limit" -ge 120 ] 2>/dev/null; then limit_text="$((limit / 60)) min"; else limit_text="$limit s"; fi
if command -v timeout >/dev/null 2>&1; then bounded() { timeout -k 20 "$limit" "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then bounded() { gtimeout -k 20 "$limit" "$@"; }
else bounded() { "$@"; }; fi

# Plain output: the tools color it when they believe a CI runs them (picocolors, chalk); what is left is removed below
NO_COLOR=1
export NO_COLOR
esc=$(printf '\033')
plain() { sed "s/${esc}\[[0-9;?]*[A-Za-z]//g" "$1" > "$1.plain" && mv "$1.plain" "$1"; }

# What the package is (front-info.sh: key=value lines, read as data)
f_dir=none f_pm=npm f_lock=none f_test=none f_runner=other f_watch=0 f_build=none f_node=none f_nodewant=none
info=$(sh "$here/front-info.sh" ${target:+"$target"})
while IFS= read -r line; do
  k=${line%%=*} v=${line#*=}
  case "$k" in
    dir) f_dir=$v ;; pm) f_pm=$v ;; lock) f_lock=$v ;; test) f_test=$v ;; runner) f_runner=$v ;;
    watch) f_watch=$v ;; build) f_build=$v ;; node) f_node=$v ;; nodewant) f_nodewant=$v ;;
  esac
done <<EOF
$info
EOF
if [ "$f_dir" = none ]; then
  echo "BUILD: NOT RUN"
  echo "STOP: no package.json in ${target:-this repository}: give the folder of the front-end package (build-test.sh <folder>)"
  exit 1
fi
root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$root/$f_dir" || exit 1
# a test file given from the repository root: relative to the package, as the runners take it
[ "$f_dir" != . ] && filter=${filter#"$f_dir"/}

# node and the package manager
if [ "$f_node" = none ]; then
  echo "BUILD: NOT RUN"
  echo "ENVIRONMENT PROBLEM: node is not on the PATH of OpenCode's shell. Stop and tell the user in one line: add it to ~/.zshenv (see the README of the pack), then restart OpenCode. Do not look for node and do not change any variable."
  exit 127
fi
case "$f_pm" in yarn|yarn-berry) pmbin=yarn ;; *) pmbin=$f_pm ;; esac
if ! command -v "$pmbin" >/dev/null 2>&1; then
  echo "BUILD: NOT RUN"
  echo "ENVIRONMENT PROBLEM: this package uses $pmbin ($f_lock), which is not installed on this machine. Stop and tell the user in one line: install it outside OpenCode (corepack enable, or npm install -g $pmbin)."
  exit 127
fi
# the node version the package asks for: a warning (the Angular CLI refuses a version itself)
want=${f_nodewant%% *}
case "$want" in
  none|"") ;;
  *)
    have=${f_node#v}
    case "$want" in
      [0-9]*) [ "${want%%.*}" = "${have%%.*}" ] || echo "WARNING: node $f_node here, the package asks for $f_nodewant: a failure of the build or of the tests may come from it" ;;
    esac ;;
esac

gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null)
# --if-changed: the same code, the same package and options, green already
green=${gitdir:+$gitdir/opencode-green-front}
runkey=""
if [ -n "$gitdir" ] && [ "$build_only" -eq 0 ] && [ "$no_build" -eq 0 ]; then
  fingerprint=$(sh "$here/state-fingerprint.sh" 2>/dev/null)
  [ -n "$fingerprint" ] && runkey="$fingerprint $(printf '%s\n' "$f_dir" "$filter" "$@" | cksum | cut -d' ' -f1)"
fi
if [ "$if_changed" -eq 1 ] && [ -n "$runkey" ] && [ "$(head -n 1 "$green" 2>/dev/null)" = "$runkey" ]; then
  echo "BUILD: OK (not run again: this same code passed this build on $(sed -n 2p "$green"))"
  if [ "$(sed -n 3p "$green")" = none ]; then
    echo "TESTS: NONE RUN (not run again: same code, same package and options; $(sed -n 4p "$green"))"
  else
    echo "TESTS: OK (not run again: same code, same package and options)"
  fi
  exit 0
fi

# The lock of build-test.sh and test-guardian.sh: one build or test run at a time in this working tree
lockdir=${gitdir:+$gitdir/opencode-dotnet.lock}
out=$(mktemp "${TMPDIR:-/tmp}/front-test.XXXXXX") || exit 1
# What the run leaves in the package that git neither tracks nor ignores (dist, coverage, .angular): the next commit of
# the pack (git add -A) would hold it, so it is said at the end
untracked() { [ -n "$gitdir" ] && git ls-files --others --exclude-standard --directory -- . 2>/dev/null; }
left_before=$(untracked)
left() {
  new=$(untracked | while IFS= read -r f; do printf '%s\n' "$left_before" | grep -q -x -F -- "$f" || echo "$f"; done | head -n 5 | tr '\n' ' ')
  [ -n "$new" ] && echo "WARNING: this run left ${new% } in $f_dir, which git does not ignore: the next commit would hold it; the developer adds it to the .gitignore"
  return 0
}
own_lock=0
cleanup() { left; rm -f "$out" "$out.plain"; [ "$own_lock" -eq 1 ] && rm -rf "$lockdir"; return 0; }
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
if [ -n "$lockdir" ] && [ "${OPENCODE_DOTNET_LOCK:-}" != "$lockdir" ]; then
  waited=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    holder=$(cat "$lockdir/pid" 2>/dev/null)
    if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } || { [ -z "$holder" ] && [ "$waited" -ge 30 ]; }; then
      rm -rf "$lockdir"
      continue
    fi
    [ "$waited" -eq 0 ] && echo "WAIT: another build or test run of this folder is in progress: this one starts after it"
    if [ "$waited" -ge "${TEST_GUARDIAN_LOCK_WAIT:-900}" ]; then
      echo "BUILD: NOT RUN (another build or test run of this folder has been running for more than ${TEST_GUARDIAN_LOCK_WAIT:-900} s)"
      exit 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "$$" > "$lockdir/pid"
  own_lock=1
  OPENCODE_DOTNET_LOCK=$lockdir
  export OPENCODE_DOTNET_LOCK
fi

# The machine, not the code: the registry, the network, Chrome, the version of node
problem() {
  if grep -q -E 'E401|E403|ERR_PNPM_FETCH_40[13]|YN0041|401 Unauthorized|403 Forbidden|Unable to authenticate|code E40[13]' "$1"; then
    echo "ENVIRONMENT PROBLEM: the package registry (Artifactory) refused access (401 or 403). Stop and tell the user in one line. Never read .npmrc or environment variables, never set them in a command, and never retry with other options."
  elif grep -q -E 'ENOTFOUND|ETIMEDOUT|ECONNREFUSED|EAI_AGAIN|ECONNRESET|getaddrinfo|network request to .* failed' "$1"; then
    echo "ENVIRONMENT PROBLEM: the package registry cannot be reached from this machine (network). Stop and tell the user in one line."
  elif grep -q -E 'No binary for Chrome|CHROME_BIN|Cannot start Chrome|ChromeHeadless was not killed|Failed to launch the browser' "$1"; then
    echo "ENVIRONMENT PROBLEM: the Karma tests need Chrome or Chromium, which this machine does not start (not installed, or CHROME_BIN not set in ~/.zshenv). Stop and tell the user in one line."
  elif grep -q -E 'Node\.js version .* detected|requires a minimum Node\.js version|Unsupported engine|The engine "node" is incompatible' "$1"; then
    echo "ENVIRONMENT PROBLEM: the version of node of this machine ($f_node) does not fit this package (${f_nodewant}). Stop and tell the user in one line: install the version it asks for."
  elif grep -q -E "Executable doesn't exist at .*ms-playwright|npx playwright install" "$1"; then
    echo "ENVIRONMENT PROBLEM: the tests run in a Playwright browser that is not installed on this machine. Stop and tell the user in one line."
  elif grep -q -E '^npm (error|ERR!) (Cannot read propert(y|ies) of (null|undefined)|Exit handler never called)' "$1" &&
    ! grep -q -E '^npm (error|ERR!) command failed' "$1"; then
    # npm itself failed, not a script of a package ("command failed"): npm 10 on some trees, npm/cli#9787
    echo "ENVIRONMENT PROBLEM: npm $(npm --version 2>/dev/null) of this machine failed inside itself ($(grep -m 1 -o -E '(Cannot read propert(y|ies) of (null|undefined)[^)]*\)?|Exit handler never called)' "$1")): a bug of npm, not of the code (npm 10 fails so on some dependency trees, Vitest 4 among them). Stop and tell the user in one line: update npm on this machine, outside OpenCode (the latest version its node accepts). Never retry with --legacy-peer-deps or --force (the lockfile would no longer install the same everywhere), never delete package-lock.json or node_modules."
  else
    return 1
  fi
  return 0
}

# The binary of the test runner, to know whether the dependencies are there
case "$f_runner" in
  karma-ng|vitest-ng|jest-ng|ng) tool=ng ;;
  cra) tool=$(printf '%s' "$f_test" | grep -o -E '(react-scripts|craco|rescripts)' | head -n 1) ;;
  vitest|jest|karma|mocha) tool=$f_runner ;;
  *) tool="" ;;
esac
modules=""
[ -d node_modules ] && modules=node_modules
[ -z "$modules" ] && [ -d "$root/node_modules" ] && modules="$root/node_modules"
if [ -z "$modules" ] || { [ -n "$tool" ] && [ ! -e "$modules/.bin/$tool" ]; }; then
  # the install writes node_modules here: git must ignore it, or the next commit of the pack (git add -A) holds it
  if [ -n "$gitdir" ] && ! git check-ignore -q node_modules/.bin; then
    echo "BUILD: NOT RUN"
    echo "STOP: git does not ignore node_modules in ${f_dir} (no node_modules line in a .gitignore): an install would put thousands of files in the next commit. The developer adds node_modules/ to the .gitignore, then the run starts again."
    exit 1
  fi
  case "$f_pm" in
    pnpm) install="pnpm install --frozen-lockfile" ;;
    yarn) install="yarn install --frozen-lockfile" ;;
    yarn-berry) install="yarn install --immutable" ;;
    *) if [ "$f_lock" = none ]; then install="npm install --no-package-lock --no-save"; else install="npm ci"; fi ;;
  esac
  echo "INSTALL: $install (node_modules${tool:+ or $tool} missing)"
  # shellcheck disable=SC2086 # the words of the command
  if ! $install > "$out" 2>&1; then
    plain "$out"
    tail -n 25 "$out"
    echo "BUILD: NOT RUN (the install failed)"
    if ! problem "$out"; then
      if grep -q -E 'can only install packages when your package.json and package-lock.json|lockfile needs to be updated|ERR_PNPM_OUTDATED_LOCKFILE|YN0028|frozen-lockfile' "$out"; then
        echo "STOP: the lockfile ($f_lock) is not in sync with package.json: the change of package.json needs its lockfile updated (npm install, run by the developer: never a package added by an agent)"
      else
        echo "STOP: the install of the dependencies failed: the lines above say why"
      fi
    fi
    exit 1
  fi
  echo "INSTALL: OK"
fi

# Focused tests: the other tests of the suite would not run
specs=$(git ls-files --cached --others --exclude-standard -- '*.spec.ts' '*.spec.tsx' '*.spec.js' '*.spec.jsx' '*.test.ts' '*.test.tsx' '*.test.js' '*.test.jsx' '*.spec.mjs' '*.test.mjs' 2>/dev/null)
focused=""
if [ -n "$specs" ]; then
  focused=$(printf '%s\n' "$specs" | while IFS= read -r f; do
    [ -f "$f" ] && grep -n -E '(^|[^A-Za-z0-9_.])(fdescribe|fit)[[:space:]]*\(|(^|[^A-Za-z0-9_])(describe|it|test|context|suite)\.only[[:space:]]*\(' "$f" /dev/null | head -n 3
  done | head -n 6 | cut -d: -f1,2 | tr '\n' ' ')
fi

# The build
if [ "$no_build" -eq 1 ]; then
  echo "BUILD: NOT RUN (--no-build)"
elif [ -n "$filter" ] && [ "$build_only" -eq 0 ]; then
  echo "BUILD: NOT RUN (a filter: the tests compile what they import)"
elif [ "$f_build" = none ]; then
  echo "BUILD: NONE (no build script in package.json)"
else
  if bounded "$pmbin" run build > "$out" 2>&1; then
    plain "$out"
    tail -n 15 "$out"
    echo "BUILD: OK"
  else
    status=$?
    plain "$out"
    tail -n 60 "$out"
    errors=$(grep -c -E 'error TS[0-9]+|\[ERROR\]|ERROR in |^Error: |✘ \[ERROR\]' "$out")
    echo "BUILD: FAILED (exit $status, $errors errors) - tests not run"
    problem "$out" || :
    exit "$status"
  fi
fi
[ "$build_only" -eq 1 ] && exit 0

# The tests
none_run() {
  echo "TESTS: NONE RUN ($1)"
  why=$1
}
why=""
tests_ok=0
status=0
case "$f_runner" in
  none) none_run "no test script in package.json" ;;
  e2e) none_run "the test script runs end-to-end tests ($f_test): they need the application running, the CI runs them" ;;
esac
if [ -z "$why" ] && [ -n "$focused" ]; then
  echo "FOCUSED TESTS: $focused"
  echo "TESTS: FAILED (focused tests: fdescribe, fit or .only make the other tests of the suite silently not run; remove them)"
  exit 1
fi
if [ -z "$why" ]; then
  # what makes the runner run once, and the filter in its form
  args=""
  isfile=0
  case "$filter" in */*|*.spec.*|*.test.*) isfile=1 ;; esac
  case "$f_runner" in
    karma-ng)
      args="--watch=false --no-progress"
      case "$f_test $*" in *--browsers*) ;; *) args="$args --browsers=ChromeHeadless" ;; esac
      if [ -n "$filter" ]; then if [ "$isfile" -eq 1 ]; then args="$args --include=$filter"; else echo "NOTE: Karma takes a test file, not a test name: every test runs"; fi; fi ;;
    vitest-ng)
      # the unit-test builder (Angular 21): --include takes a test file, --filter a regular expression of test names
      args="--watch=false --no-progress"
      if [ -n "$filter" ]; then if [ "$isfile" -eq 1 ]; then args="$args --include=$filter"; else args="$args --filter=$filter"; fi; fi ;;
    jest-ng)
      # a Jest builder runs once by itself, and its options differ from one builder to another
      [ -n "$filter" ] && echo "NOTE: the Jest builder of this Angular project takes no filter the pack knows: every test runs" ;;
    ng)
      args="--watch=false"
      [ -n "$filter" ] && echo "NOTE: the test builder of this Angular project ($(printf '%s\n' "$info" | sed -n 's/^builder=//p')) takes no filter the pack knows: every test runs" ;;
    cra)
      args="--watchAll=false"
      if [ -n "$filter" ]; then if [ "$isfile" -eq 1 ]; then args="$args $filter"; else args="$args -t $filter"; fi; fi ;;
    vitest)
      case " $f_test " in *" run "*|*" --run "*) ;; *) args="--run" ;; esac
      if [ -n "$filter" ]; then if [ "$isfile" -eq 1 ]; then args="$args $filter"; else args="$args -t $filter"; fi; fi ;;
    jest)
      if [ -n "$filter" ]; then if [ "$isfile" -eq 1 ]; then args="$filter"; else args="-t $filter"; fi; fi ;;
    karma)
      args="--single-run"
      case "$f_test $*" in *--browsers*) ;; *) args="$args --browsers ChromeHeadless" ;; esac
      [ -n "$filter" ] && echo "NOTE: karma start takes no filter: every test runs" ;;
    mocha)
      if [ -n "$filter" ]; then if [ "$isfile" -eq 1 ]; then args="$filter"; else args="--grep $filter"; fi; fi ;;
    node)
      [ -n "$filter" ] && [ "$isfile" -eq 1 ] && args="$filter" ;;
    *)
      [ -n "$filter" ] && echo "NOTE: the test script ($f_test) has no filter the pack knows: every test runs" ;;
  esac
  # a test script that watches by itself: its command without its watch option, run as npm would (node_modules/.bin)
  if [ "$f_watch" = 1 ]; then
    cmd=$(printf '%s' "$f_test" | sed -E 's/[[:space:]]--watch(All)?([=:]true)?([[:space:]]|$)/\3/g; s/[[:space:]]+/ /g')
    echo "NOTE: the test script watches ($f_test): run without its watch option"
    run() { PATH="$PWD/node_modules/.bin:$root/node_modules/.bin:$PATH" bounded sh -c "$cmd $args $*"; }
  else
    # shellcheck disable=SC2086 # the options are words
    case "$f_pm" in
      npm) run() { if [ -n "$args$*" ]; then bounded npm run test -- $args "$@"; else bounded npm run test; fi; } ;;
      *) run() { bounded "$pmbin" run test $args "$@"; } ;;
    esac
  fi
  run "$@" > "$out" 2>&1
  status=$?
  plain "$out"
  total_lines=$(wc -l < "$out" | tr -d ' ')
  tail -n 80 "$out"
  [ "$total_lines" -gt 80 ] && echo "(the first $((total_lines - 80)) lines of the test output are not shown)"
  # the counts and the failed tests, in the form of each runner
  # "<failed> <ran>": the tests that ran, never those a filter or a skip left out
  counts=$(awk '
    function n(line, what) { return match(line, "[0-9]+ " what) ? substr(line, RSTART, RLENGTH) + 0 : 0 }
    /^[[:space:]]*Tests:[[:space:]]+/ { jest = n($0, "failed") " " (n($0, "failed") + n($0, "passed")) }
    /^[[:space:]]*Tests[[:space:]]+[0-9]/ { vitest = n($0, "failed") " " (n($0, "failed") + n($0, "passed")) }
    /Executed [0-9]+ of [0-9]+/ { line = $0; f = 0
      match(line, /Executed [0-9]+ of [0-9]+/); split(substr(line, RSTART, RLENGTH), a, " "); done = a[2] + 0
      if (match(line, /\([0-9]+ FAILED\)/)) f = substr(line, RSTART + 1, RLENGTH - 2) + 0
      karma = f " " done }
    /^[[:space:]]*[0-9]+ passing/ { mp = $1 + 0 } /^[[:space:]]*[0-9]+ failing/ { mf = $1 + 0 }
    /^(#|ℹ) (pass|fail) [0-9]+/ { if ($2 == "pass") np = $3 + 0; else nf = $3 + 0 }
    END {
      if (jest != "") print jest; else if (vitest != "") print vitest; else if (karma != "") print karma
      else if (mp + mf > 0) print mf " " (mp + mf); else if (np + nf > 0) print nf " " (np + nf) }' "$out" | tail -n 1)
  failed_names=$(sed -n \
    -e 's/^[[:space:]]*● \(.*[^[:space:]]\)[[:space:]]*$/\1/p' \
    -e 's/^[[:space:]]*FAIL[[:space:]][[:space:]]*\(.* > .*[^[:space:]]\)[[:space:]]*$/\1/p' \
    -e 's/^.*([^)]*) \(.*[^[:space:]]\) FAILED$/\1/p' \
    -e 's/^not ok [0-9][0-9]* - \(.*\)$/\1/p' \
    -e 's/^[[:space:]]*✖ \(.*[^[:space:]]\)[[:space:]]*([0-9.]*ms)$/\1/p' "$out" |
    grep -v -E '^(Test suite failed to run|Console|failing tests:)' | awk '!seen[$0]++' | head -n 25)
  failed=${counts%% *} total=${counts##* }
  zero=0
  grep -q -E 'No tests found, exiting with code 1|No test files found|Executed 0 of 0|^[[:space:]]*0 passing' "$out" && zero=1
  [ -n "$counts" ] && [ "${total:-0}" = 0 ] && zero=1
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    echo "HANG: the tests did not end within $limit_text and were stopped (a watch mode, or a browser that never starts): report it with the lines above; never run the test command another way"
    echo "TESTS: FAILED (stopped after $limit_text)"
    status=1
  elif [ "$zero" -eq 1 ]; then
    if [ -n "$filter" ]; then none_run "no test matches the filter"; else none_run "no test in this package yet"; fi
    status=0
  elif [ "$status" -ne 0 ]; then
    if [ -n "$failed_names" ]; then
      echo "FAILED TESTS ($(printf '%s\n' "$failed_names" | grep -c .)): $(printf '%s\n' "$failed_names" | awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { print "" }')"
    fi
    problem "$out" || :
    if [ -n "$counts" ]; then echo "TESTS: FAILED ($failed of $total failed)"; else echo "TESTS: FAILED (exit $status)"; fi
  else
    tests_ok=1
    if [ -n "$counts" ] && [ "${total:-0}" -gt 0 ] 2>/dev/null; then echo "TESTS: OK ($total test$([ "$total" -eq 1 ] || echo s))"; else echo "TESTS: OK"; fi
  fi
fi

# a green run is remembered for --if-changed
if [ -n "$runkey" ] && [ "$status" -eq 0 ]; then
  if [ "$tests_ok" -eq 1 ]; then
    printf '%s\n%s\nok\n' "$runkey" "$(date '+%Y-%m-%d %H:%M')"
  else
    printf '%s\n%s\nnone\n%s\n' "$runkey" "$(date '+%Y-%m-%d %H:%M')" "$why"
  fi > "$green" 2>/dev/null
fi
exit "$status"
