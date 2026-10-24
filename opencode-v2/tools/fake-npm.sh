#!/bin/sh
# A fake npm, yarn and pnpm and fake front-end tools (ng, jest, vitest, vite, karma, react-scripts), for tools/frontend-test.sh
# (never installed by the pack): enough of the installs, of `run <script>` and of the output of each test runner to test
# front-test.sh and build-test.sh without a registry. Which one it is: its name ($0); the install links the tools into
# node_modules/.bin. The scripts of package.json are run as the package managers run them (node reads package.json).
# A package declares its tests in a file next to its package.json, fake-tests, one per line:
#   pass|fail <test file> <test name>                     (a failed test says: expected 120 to be 100)
# Markers, files next to package.json:
#   fake-build-error       its build fails (a TypeScript error)
#   fake-install-401       the registry refuses the install (Artifactory, 401)
#   fake-install-crash     npm fails inside itself (Cannot read properties of null)
#   fake-install-script-error  the install script of a package fails
#   fake-lock-out-of-sync  the lockfile does not match package.json
#   fake-chrome-missing    Karma finds no Chrome
#   fake-hang              the tests never end
#   fake-node-old          the Angular CLI refuses the version of node
# FAKE_COLOR=1: the summary of Jest in colors (chalk colors it in a CI, NO_COLOR or not)
# The tools watch as the real ones do: `ng test` with Karma, `karma start`, `react-scripts test` and `jest --watch`
# never end without their single-run option (Vitest runs once without a terminal, as here).
# Every call is logged, one line, to $FAKE_NPM_LOG.
name=$(basename "$0")
[ -n "$FAKE_NPM_LOG" ] && printf '%s\n' "$name $*" >> "$FAKE_NPM_LOG"
self=$(cd "$(dirname "$0")" && pwd)/$name
pkg=$(pwd)
while [ "$pkg" != / ] && [ ! -f "$pkg/package.json" ]; do pkg=$(dirname "$pkg"); done
[ -f "$pkg/package.json" ] || pkg=$(pwd)
hang() { sleep "${FAKE_HANG_SECONDS:-30}"; exit 0; }
has() { for w in $args; do [ "$w" = "$1" ] && return 0; done; return 1; }

# ---------- the package managers ----------
install() {
  if [ -f "$pkg/fake-install-401" ]; then
    echo "npm error code E401"
    echo "npm error Unable to authenticate, need: Basic realm=\"Artifactory Realm\""
    exit 1
  fi
  if [ -f "$pkg/fake-install-crash" ]; then
    # npm 10 resolving some trees (Vitest 4): npm/cli#9787
    echo "npm error Cannot read properties of null (reading 'edgesOut')"
    echo "npm error A complete log of this run can be found in: $HOME/.npm/_logs/2026-10-24T17_14_56_042Z-debug-0.log"
    exit 1
  fi
  if [ -f "$pkg/fake-install-script-error" ]; then
    # the install script of a package fails: its lines come after npm's
    echo "npm error code 1"
    echo "npm error path $pkg/node_modules/esbuild"
    echo "npm error command failed"
    echo "npm error command sh -c node install.js"
    echo "npm error Cannot read properties of undefined (reading 'platform')"
    exit 1
  fi
  if [ -f "$pkg/fake-lock-out-of-sync" ]; then
    case "$name" in
      yarn) echo "error Your lockfile needs to be updated, but yarn was run with \`--frozen-lockfile\`." ;;
      pnpm) echo " ERR_PNPM_OUTDATED_LOCKFILE  Cannot install with \"frozen-lockfile\" because pnpm-lock.yaml is not up to date with package.json" ;;
      *) echo "npm error \`npm ci\` can only install packages when your package.json and package-lock.json or npm-shrinkwrap.json are in sync. Please update your lock file with \`npm install\` before continuing." ;;
    esac
    exit 1
  fi
  mkdir -p node_modules/.bin
  for tool in ng jest vitest vite karma react-scripts craco playwright; do ln -sf "$self" "node_modules/.bin/$tool"; done
  echo "added 812 packages in 4s"
  exit 0
}
run_script() {
  script=$1
  shift
  body=$(node -e 'const p = require(process.argv[1]); const s = (p.scripts || {})[process.argv[2]]; if (s === undefined) process.exit(3); process.stdout.write(s)' "$pkg/package.json" "$script" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "npm error Missing script: \"$script\""
    exit 1
  fi
  quoted=""
  for a in "$@"; do quoted="$quoted '$(printf '%s' "$a" | sed "s/'/'\\\\''/g")'"; done
  echo ""
  echo "> fake-package@1.0.0 $script"
  echo "> $body$quoted"
  echo ""
  cd "$pkg" || exit 1
  PATH="$pkg/node_modules/.bin:$PATH" exec sh -c "$body$quoted"
}
case "$name" in
  npm)
    case "$1" in
      ci|install|i) install ;;
      run|run-script)
        script=$2
        shift 2
        [ "$1" = -- ] && shift
        run_script "$script" "$@" ;;
      test|t|tst)
        shift
        [ "$1" = -- ] && shift
        run_script test "$@" ;;
      --version) echo "10.9.2"; exit 0 ;;
      *) echo "fake npm: $* is not simulated"; exit 2 ;;
    esac ;;
  yarn|pnpm)
    case "$1" in
      ""|install|i) install ;;
      run) script=$2; shift 2; [ "$1" = -- ] && shift; run_script "$script" "$@" ;;
      --version) echo "1.22.22"; exit 0 ;;
      *) script=$1; shift; [ "$1" = -- ] && shift; run_script "$script" "$@" ;;
    esac ;;
esac

# ---------- the tools ----------
args="$*"
# the tests of the package, with the filter of the run: a test file (--include=, a path) or a test name (-t, --filter=)
# all the tests of the package (the skipped count of a filter)
all_tests() { [ -f "$pkg/fake-tests" ] && grep -c '^[pf]' "$pkg/fake-tests" || echo 0; }
tests() {
  file="" match=""
  prev=""
  for a in "$@"; do
    case "$prev" in -t|--testNamePattern|--grep) match=$a ;; esac
    case "$a" in
      --include=*) file=${a#--include=} ;;
      --filter=*) match=${a#--filter=} ;;
      -*) ;;
      */*|*.spec.*|*.test.*) [ "$prev" = -t ] || file=$a ;;
    esac
    prev=$a
  done
  [ -f "$pkg/fake-tests" ] || return 0
  while read -r status tfile tname; do
    [ -n "$status" ] || continue
    [ -n "$file" ] && [ "$tfile" != "$file" ] && continue
    [ -n "$match" ] && ! printf '%s\n' "$tname" | grep -q -E -- "$match" && continue
    echo "$status $tfile $tname"
  done < "$pkg/fake-tests"
}
karma_report() {
  list=$(tests "$@")
  [ -f "$pkg/fake-hang" ] && hang
  if [ -f "$pkg/fake-chrome-missing" ]; then
    echo "ERROR [launcher]: No binary for ChromeHeadless browser on your platform."
    echo "  Please, set \"CHROME_BIN\" env variable."
    exit 1
  fi
  t=$(printf '%s\n' "$list" | grep -c '^[pf]')
  f=$(printf '%s\n' "$list" | grep -c '^fail ')
  printf '%s\n' "$list" | while read -r status tfile tname; do
    [ "$status" = fail ] && printf 'Chrome Headless 130.0.0.0 (Linux x86_64) %s FAILED\n\tExpected 120 to be 100.\n' "$tname"
  done
  if [ "$t" -eq 0 ]; then echo "Chrome Headless 130.0.0.0 (Linux x86_64): Executed 0 of 0 ERROR (0.004 secs / 0 secs)"; exit 1; fi
  if [ "$f" -gt 0 ]; then
    echo "Chrome Headless 130.0.0.0 (Linux x86_64): Executed $t of $t ($f FAILED) (0.21 secs / 0.18 secs)"
    exit 1
  fi
  echo "Chrome Headless 130.0.0.0 (Linux x86_64): Executed $t of $t SUCCESS (0.19 secs / 0.15 secs)"
  exit 0
}
vitest_report() {
  list=$(tests "$@")
  [ -f "$pkg/fake-hang" ] && hang
  t=$(printf '%s\n' "$list" | grep -c '^[pf]')
  f=$(printf '%s\n' "$list" | grep -c '^fail ')
  if [ "$t" -eq 0 ]; then echo "No test files found, exiting with code 1"; exit 1; fi
  printf '%s\n' "$list" | while read -r status tfile tname; do
    [ "$status" = fail ] && printf ' FAIL  %s > %s\nAssertionError: expected 120 to be 100\n' "$tfile" "$tname"
  done
  all=$(all_tests)
  skipped=""
  [ "$all" -gt "$t" ] && skipped=" | $((all - t)) skipped"
  if [ "$f" -gt 0 ]; then
    echo " Test Files  1 failed (1)"
    echo "      Tests  $f failed | $((t - f)) passed$skipped ($all)"
    exit 1
  fi
  echo " Test Files  1 passed (1)"
  echo "      Tests  $t passed$skipped ($all)"
  exit 0
}
jest_report() {
  list=$(tests "$@")
  [ -f "$pkg/fake-hang" ] && hang
  t=$(printf '%s\n' "$list" | grep -c '^[pf]')
  f=$(printf '%s\n' "$list" | grep -c '^fail ')
  if [ "$t" -eq 0 ]; then echo "No tests found, exiting with code 1"; exit 1; fi
  printf '%s\n' "$list" | while read -r status tfile tname; do
    [ "$status" = fail ] && printf '  \342\227\217 %s\n\n    expect(received).toBe(expected)\n\n    Expected: 100\n    Received: 120\n\n' "$(printf '%s' "$tname" | sed 's/ > / \342\200\272 /g')"
  done
  all=$(all_tests)
  skipped=""
  [ "$all" -gt "$t" ] && skipped="$((all - t)) skipped, "
  if [ "$f" -gt 0 ]; then
    echo "Tests:       $f failed, $skipped$((t - f)) passed, $all total"
    exit 1
  fi
  if [ -n "$FAKE_COLOR" ]; then printf '\033[1mTests:\033[22m       \033[1m\033[32m%s passed\033[39m\033[22m, %s total\n' "$t" "$all"
  else echo "Tests:       $skipped$t passed, $all total"; fi
  exit 0
}
builder() { grep -o '"builder"[[:space:]]*:[[:space:]]*"[^"]*"' "$pkg/angular.json" 2>/dev/null | grep -E 'karma|unit-test|jest' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/'; }
case "$name" in
  ng)
    case "$1" in
      build)
        if [ -f "$pkg/fake-node-old" ]; then
          echo "Node.js version v16.20.0 detected."
          echo "The Angular CLI requires a minimum Node.js version of v20.19 or v22.12."
          exit 3
        fi
        if [ -f "$pkg/fake-build-error" ]; then
          echo "✘ [ERROR] TS2304: Cannot find name 'Invoic'. [plugin angular-compiler]"
          echo ""
          echo "    src/app/invoice/invoice.component.ts:12:10:"
          exit 1
        fi
        mkdir -p "$pkg/dist/browser" && printf '<html></html>\n' > "$pkg/dist/browser/index.html"
        echo "Application bundle generation complete. [3.214 seconds]"
        exit 0 ;;
      test)
        shift
        b=$(builder)
        case "$b" in
          *unit-test*)
            if grep -q '"runner"[[:space:]]*:[[:space:]]*"karma"' "$pkg/angular.json" 2>/dev/null; then
              has --watch=false || has --no-watch || hang
              karma_report "$@"
            fi
            vitest_report "$@" ;;
          *jest*) jest_report "$@" ;;
          *)
            # Karma watches unless --watch=false
            has --watch=false || has --no-watch || hang
            karma_report "$@" ;;
        esac ;;
      serve) hang ;;
      *) echo "fake ng: $* is not simulated"; exit 2 ;;
    esac ;;
  jest)
    for w in $args; do case "$w" in --watch|--watchAll|--watch=true|--watchAll=true) hang ;; esac; done
    jest_report "$@" ;;
  vite)
    [ "$1" = build ] || hang
    mkdir -p "$pkg/dist" && printf '<html></html>\n' > "$pkg/dist/index.html"
    echo "✓ 42 modules transformed."
    echo "✓ built in 1.21s"
    exit 0 ;;
  vitest)
    case "$1" in watch|dev) hang ;; esac
    [ "$1" = run ] && shift
    vitest_report "$@" ;;
  karma)
    has --single-run || hang
    shift
    karma_report "$@" ;;
  react-scripts|craco)
    case "$1" in
      build) mkdir -p "$pkg/build" && printf '<html></html>\n' > "$pkg/build/index.html"; echo "Compiled successfully."; exit 0 ;;
      start) hang ;;
      test)
        shift
        [ -z "$CI" ] && ! has --watchAll=false && hang
        jest_report "$@" ;;
    esac ;;
  playwright)
    echo "Error: browserType.launch: Executable doesn't exist at /home/dev/.cache/ms-playwright/chromium-1140/chrome-linux/chrome"
    exit 1 ;;
esac
echo "fake front-end tool: $name $* is not simulated"
exit 2
