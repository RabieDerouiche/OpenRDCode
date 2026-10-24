#!/bin/sh
# Tests of the pack's front-end scripts (front-info.sh, front-test.sh, build-test.sh for a front-end folder,
# detect-project-type.sh, test-lint.sh) with a fake npm, yarn and pnpm and fake test runners (tools/fake-npm.sh): Angular
# with Karma (ng test watches by default), Angular 21 with Vitest, Create React App on yarn, Vitest, Jest, a test script
# that watches, end-to-end tests, the registry that refuses access, a lockfile out of sync, Chrome missing, a run that
# never ends. node is needed (front-info.sh reads package.json with it).
# --real: the same scripts on real packages installed from the npm registry (Jest, Vitest, an Angular application of
# the current Angular CLI with Vitest and one of Angular 19 with Karma in ChromeHeadless): the CI runs it, with node,
# the registry and Chrome.
# Usage, from opencode-v2/: sh tools/frontend-test.sh [--real] [<shell>] (default sh).
real=0
[ "$1" = --real ] && { real=1; shift; }
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
work=$(mktemp -d "${TMPDIR:-/tmp}/frontend-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
if [ "$real" -eq 0 ]; then
  # the fake machine: its own HOME, the fake package managers first on the PATH
  HOME="$work/home"
  mkdir -p "$HOME" "$work/bin"
  export HOME
  cp "$pack/tools/fake-npm.sh" "$work/bin/npm"
  chmod +x "$work/bin/npm"
  ln -s npm "$work/bin/yarn"
  ln -s npm "$work/bin/pnpm"
  cp "$pack/tools/fake-dotnet.sh" "$work/bin/dotnet"
  chmod +x "$work/bin/dotnet"
  PATH="$work/bin:$PATH"
  FAKE_NPM_LOG="$work/npm.log"
  FAKE_DOTNET_LOG="$work/dotnet.log"
  FAKE_DOTNET_STATE="$work/state"
  mkdir -p "$FAKE_DOTNET_STATE"
  export PATH FAKE_NPM_LOG FAKE_DOTNET_LOG FAKE_DOTNET_STATE
fi
TMPDIR="$work/tmp"
mkdir -p "$TMPDIR"
export TMPDIR
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
[ "$real" -eq 0 ] && git config --global init.defaultBranch develop

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
  [ -n "$FAKE_NPM_LOG" ] && : > "$FAKE_NPM_LOG"
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
  calls=$([ -n "$FAKE_NPM_LOG" ] && cat "$FAKE_NPM_LOG")
}
called() {
  # called <name> <grep pattern of the calls> [<pattern that must not appear>]
  if printf '%s\n' "$calls" | grep -qE -- "$2" && { [ -z "$3" ] || ! printf '%s\n' "$calls" | grep -qE -- "$3"; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 (calls)"
    printf '%s\n' "$calls" | sed 's/^/    /'
  fi
}
truth() {
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 ($2)"; fi
}
repo() {
  # repo <name>: a new repository, the current folder
  rm -rf "${work:?}/$1"
  mkdir -p "$work/$1"
  cd "$work/$1" || exit 1
  git init -q .
}
commit() { git add -A >/dev/null 2>&1; git commit -q -m x >/dev/null 2>&1; }

if [ "$real" -eq 1 ]; then
  # ---------- real packages from the npm registry ----------
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || { echo "frontend-test (real): node and npm are needed"; exit 1; }
  echo "node $(node --version), npm $(npm --version)"
  # Jest: a package of the repository root
  repo jest-app
  cat > package.json <<'EOF'
{ "name": "jest-app", "version": "1.0.0", "private": true, "scripts": { "test": "jest" } }
EOF
  cat > sum.js <<'EOF'
module.exports = (a, b) => a + b
EOF
  cat > sum.test.js <<'EOF'
const sum = require("./sum")
test("adds two numbers", () => { expect(sum(1, 2)).toBe(3) })
test("adds a negative number", () => { expect(sum(1, -2)).toBe(-1) })
EOF
  printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
  npm install --no-audit --no-fund --save-dev jest@29.7.0 > "$work/jest-install.log" 2>&1 || { tail -20 "$work/jest-install.log"; exit 1; }
  commit
  run build-test.sh
  check "real Jest: the tests of a repository without .NET run once" 0 'TESTS: OK \(2 tests\)'
  check "real Jest: no build script" 0 'BUILD: NONE \(no build script in package.json\)'
  run build-test.sh --if-changed
  check "real Jest: --if-changed does not run them again" 0 'TESTS: OK \(not run again'
  cat > sum.fail.test.js <<'EOF'
const sum = require("./sum")
test("rounds the total", () => { expect(sum(0.1, 0.2)).toBe(0.3) })
EOF
  run build-test.sh
  check "real Jest: a failed test is named" 1 'FAILED TESTS \(1\): rounds the total'
  check "real Jest: the counts of the run" 1 'TESTS: FAILED \(1 of 3 failed\)'
  rm sum.fail.test.js
  run build-test.sh . --filter sum.test.js
  check "real Jest: a test file as the filter" 0 'TESTS: OK \(2 tests\)'
  run build-test.sh . --filter "negative"
  check "real Jest: a test name as the filter" 0 'TESTS: OK \(1 tests?\)'
  sed 's/^test("adds two/test.only("adds two/' sum.test.js > sum.only.test.js
  run build-test.sh
  check "real Jest: a focused test is a failure" 1 'TESTS: FAILED \(focused tests'
  rm sum.only.test.js
  run test-lint.sh sum.test.js
  check "real Jest: test-lint reads the spec" 0 'TEST LINT: OK'

  # Vitest: the test script without run (Vitest runs once without a terminal; front-test.sh adds --run anyway)
  repo vitest-app
  mkdir -p web/src
  cat > web/package.json <<'EOF'
{ "name": "vitest-app", "version": "1.0.0", "private": true, "type": "module", "scripts": { "test": "vitest" } }
EOF
  cat > web/src/total.js <<'EOF'
export const total = (lines) => lines.reduce((sum, line) => sum + line.price * line.quantity, 0)
EOF
  cat > web/src/total.test.js <<'EOF'
import { describe, expect, it } from "vitest"
import { total } from "./total.js"
describe("total", () => {
  it("sums the lines", () => { expect(total([{ price: 2, quantity: 3 }, { price: 1, quantity: 1 }])).toBe(7) })
  it("is zero without lines", () => { expect(total([])).toBe(0) })
})
EOF
  printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
  (cd web && npm install --no-audit --no-fund --save-dev vitest@2.1.9 > "$work/vitest-install.log" 2>&1) || { tail -20 "$work/vitest-install.log"; exit 1; }
  commit
  run build-test.sh web
  check "real Vitest: the tests of a folder run once" 0 'TESTS: OK \(2 tests\)'
  run build-test.sh web --filter "sums"
  check "real Vitest: a test name as the filter" 0 'TESTS: OK \(1 tests?\)'
  sed 's/toBe(7)/toBe(8)/' web/src/total.test.js > web/src/total.bad.test.js
  run build-test.sh web
  check "real Vitest: a failed test is named" 1 'FAILED TESTS \(1\): .*sums the lines'
  rm web/src/total.bad.test.js

  # Angular of the current CLI (Vitest, Angular 21 and later), then Angular 19 (Karma in ChromeHeadless)
  for ng in 21 19; do
    repo "ng$ng"
    if ! NG_CLI_ANALYTICS=false npx --yes "@angular/cli@$ng" new shop --defaults --skip-git --ssr=false --style=css --directory ClientApp > "$work/ng$ng.log" 2>&1; then
      tail -30 "$work/ng$ng.log"
      fail=$((fail + 1))
      echo "FAIL: Angular $ng: ng new"
      continue
    fi
    printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
    commit
    sh "$scripts/front-info.sh" ClientApp > "$work/ng$ng.info"
    echo "Angular $ng: $(tr '\n' ' ' < "$work/ng$ng.info")"
    run build-test.sh ClientApp
    check "real Angular $ng: build, then the tests once" 0 'BUILD: OK.*|TESTS: OK \([0-9]+ tests\)'
    check "real Angular $ng: the tests passed" 0 'TESTS: OK \([0-9]+ tests\)'
    spec=$(cd ClientApp && git ls-files 'src/*.spec.ts' | head -n 1)
    run build-test.sh ClientApp --filter "ClientApp/$spec"
    check "real Angular $ng: a spec file as the filter" 0 'TESTS: OK \([0-9]+ tests?\)'
    sed 's/toBeTruthy()/toBeFalsy()/' "ClientApp/$spec" > "$work/spec" && cp "$work/spec" "ClientApp/$spec"
    run build-test.sh ClientApp
    check "real Angular $ng: a failed test is named" 1 'FAILED TESTS \([0-9]+\): ' 'HANG'
    git checkout -q -- ClientApp
    run detect-project-type.sh
    check "real Angular $ng: detect-project-type names the front-end" 0 "Front-end: ClientApp .*angular $ng"
  done
  echo "frontend-test (real, $SHELL_UNDER_TEST): $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
  exit
fi

# ---------- Angular with Karma (ng test watches without --watch=false) ----------
repo ng-karma
mkdir -p ClientApp/src/app/invoice
cat > ClientApp/package.json <<'EOF'
{ "name": "shop", "version": "1.0.0", "scripts": { "build": "ng build", "test": "ng test" },
  "dependencies": { "@angular/core": "^19.2.0" }, "devDependencies": { "karma": "~6.4.0" } }
EOF
cat > ClientApp/angular.json <<'EOF'
{ "projects": { "shop": { "projectType": "application", "architect": {
  "build": { "builder": "@angular-devkit/build-angular:application" },
  "test": { "builder": "@angular-devkit/build-angular:karma", "options": { "karmaConfig": "karma.conf.js" } } } } } }
EOF
printf '{ "lockfileVersion": 3 }\n' > ClientApp/package-lock.json
cat > ClientApp/fake-tests <<'EOF'
pass src/app/app.component.spec.ts AppComponent should create
pass src/app/invoice/invoice.component.spec.ts InvoiceComponent should create
pass src/app/invoice/invoice.component.spec.ts InvoiceComponent should compute the total
EOF
cat > ClientApp/src/app/invoice/invoice.component.spec.ts <<'EOF'
describe("InvoiceComponent", () => {
  it("should compute the total", () => {
    expect(total([{ price: 2, quantity: 3 }])).toBe(6)
  })
})
EOF
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
commit
run front-info.sh ClientApp
check "front-info: Angular with Karma" 0 'runner=karma-ng'
check "front-info: the framework and the package manager" 0 'framework=angular 19'
check "front-info: npm, from package-lock.json" 0 'pm=npm'
run build-test.sh ClientApp
check "Karma: the dependencies are installed from the lockfile" 0 'INSTALL: npm ci \(node_modules or ng missing\)'
check "Karma: build, then the tests once" 0 'BUILD: OK'
check "Karma: the count of the tests" 0 'TESTS: OK \(3 tests\)'
called "Karma: ng test runs once, in ChromeHeadless" 'ng test --watch=false --no-progress --browsers=ChromeHeadless'
called "Karma: the build is the build script" 'ng build'
truth "Karma: node_modules made by the install" '[ -e ClientApp/node_modules/.bin/ng ]'
run build-test.sh ClientApp
check "Karma: no install when node_modules is there" 0 'TESTS: OK \(3 tests\)' 'INSTALL:'
run build-test.sh ClientApp --filter ClientApp/src/app/invoice/invoice.component.spec.ts
check "Karma: a spec file as the filter, from the repository root" 0 'TESTS: OK \(2 tests\)'
check "Karma: no build with a filter" 0 'BUILD: NOT RUN \(a filter'
called "Karma: the filter is --include, relative to the package" 'ng test --watch=false --no-progress --browsers=ChromeHeadless --include=src/app/invoice/invoice.component.spec.ts'
run build-test.sh ClientApp --filter "should compute"
check "Karma: a test name is no filter of Karma, and it says so" 0 'NOTE: Karma takes a test file, not a test name'
run build-test.sh --build-only ClientApp
check "Karma: --build-only builds" 0 'BUILD: OK' 'TESTS:'
run build-test.sh --if-changed ClientApp
check "Karma: --if-changed runs the first time" 0 'TESTS: OK \(3 tests\)'
run build-test.sh --if-changed ClientApp
check "Karma: --if-changed does not run the same code again" 0 'TESTS: OK \(not run again'
echo "pass src/app/invoice/invoice.component.spec.ts InvoiceComponent should round" >> ClientApp/fake-tests
run build-test.sh --if-changed ClientApp
check "Karma: --if-changed runs again on a change" 0 'TESTS: OK \(4 tests\)'
# a failed test
sed 's/^pass \(src\/app\/invoice\/invoice.component.spec.ts InvoiceComponent should compute the total\)/fail \1/' ClientApp/fake-tests > "$work/t" && cp "$work/t" ClientApp/fake-tests
run build-test.sh ClientApp
check "Karma: a failed test is named" 1 'FAILED TESTS \(1\): InvoiceComponent should compute the total'
check "Karma: the counts of the run" 1 'TESTS: FAILED \(1 of 4 failed\)'
git checkout -q -- ClientApp/fake-tests
# a focused test
sed 's/  it("should compute/  fit("should compute/' ClientApp/src/app/invoice/invoice.component.spec.ts > "$work/s" && cp "$work/s" ClientApp/src/app/invoice/invoice.component.spec.ts
run build-test.sh ClientApp
check "Karma: a focused test fails the run" 1 'FOCUSED TESTS: src/app/invoice/invoice.component.spec.ts:2'
check "Karma: and says why" 1 'TESTS: FAILED \(focused tests'
git checkout -q -- ClientApp/src
# a build error
touch ClientApp/fake-build-error
run build-test.sh ClientApp
check "Karma: a build error, no tests" 1 'BUILD: FAILED \(exit 1, 1 errors\) - tests not run' 'TESTS:'
rm ClientApp/fake-build-error
# Chrome missing
touch ClientApp/fake-chrome-missing
run build-test.sh ClientApp
check "Karma: Chrome missing is an environment problem" 1 'ENVIRONMENT PROBLEM: the Karma tests need Chrome'
rm ClientApp/fake-chrome-missing
# a run that never ends
touch ClientApp/fake-hang
out=$(FRONT_TEST_TIMEOUT=2 FAKE_HANG_SECONDS=20 "$SHELL_UNDER_TEST" "$scripts/build-test.sh" ClientApp 2>&1)
status=$?
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  check "a run that never ends is stopped" 1 'HANG: the tests did not end within 2 s'
  check "and fails" 1 'TESTS: FAILED \(stopped after 2 s\)'
fi
rm ClientApp/fake-hang
# the node version of the package
printf '18\n' > ClientApp/.nvmrc
run build-test.sh ClientApp
check "a node version other than the one the package asks for is a warning" 0 "WARNING: node v[0-9.]+ here, the package asks for 18 \\(ClientApp/.nvmrc\\)"
rm ClientApp/.nvmrc
touch ClientApp/fake-node-old
run build-test.sh ClientApp
check "a node version the Angular CLI refuses is an environment problem" any 'ENVIRONMENT PROBLEM: the version of node of this machine'
rm ClientApp/fake-node-old

# ---------- the install: the registry, a lockfile out of sync ----------
rm -rf ClientApp/node_modules
touch ClientApp/fake-install-401
run build-test.sh ClientApp
check "the registry refuses the install: an environment problem" 1 'ENVIRONMENT PROBLEM: the package registry \(Artifactory\) refused access'
check "and nothing is built" 1 'BUILD: NOT RUN \(the install failed\)'
rm ClientApp/fake-install-401
touch ClientApp/fake-lock-out-of-sync
run build-test.sh ClientApp
check "a lockfile out of sync stops the run" 1 'STOP: the lockfile \(ClientApp/package-lock.json\) is not in sync with package.json'
called "and no package is added: npm ci only" '^npm ci$' 'npm install'
rm ClientApp/fake-lock-out-of-sync

# ---------- a .NET API and its Angular front-end in one repository ----------
mkdir -p src/Api
cat > src/Api/Api.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF
cat > App.sln <<'EOF'
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "Api", "src\Api\Api.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
EOF
commit
: > "$FAKE_DOTNET_LOG"
run build-test.sh
check "a mixed repository: build-test.sh builds .NET" any 'BUILD: OK'
check "and names the front-end package it does not build" any 'NOTE: this repository also holds a front-end package \(ClientApp\)'
truth "and runs no npm" '! grep -q . "$FAKE_NPM_LOG"'
run build-test.sh ClientApp
check "a mixed repository: build-test.sh <folder> runs the front-end" 0 'TESTS: OK \(3 tests\)'
run detect-project-type.sh
check "detect-project-type: the front-end line" 0 'Front-end: ClientApp — angular 19, npm, tests: '
check "detect-project-type: its build and tests through build-test.sh" 0 'build-test.sh ClientApp'

# ---------- Angular 21: the unit-test builder runs Vitest ----------
repo ng21
cat > package.json <<'EOF'
{ "name": "shop21", "version": "1.0.0", "scripts": { "build": "ng build", "test": "ng test" },
  "dependencies": { "@angular/core": "^21.0.0" }, "devDependencies": { "vitest": "^4.0.0" } }
EOF
cat > angular.json <<'EOF'
{ "projects": { "shop21": { "projectType": "application", "architect": {
  "build": { "builder": "@angular/build:application" }, "test": { "builder": "@angular/build:unit-test" } } } } }
EOF
printf '{ "lockfileVersion": 3 }\n' > package-lock.json
cat > fake-tests <<'EOF'
pass src/app/app.spec.ts App should create
pass src/app/cart/cart.spec.ts Cart should add a line
fail src/app/cart/cart.spec.ts Cart should apply the discount
EOF
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
commit
run front-info.sh
check "front-info: Angular 21 with the unit-test builder" 0 'runner=vitest-ng'
run build-test.sh
check "Angular 21: a repository without .NET goes to front-test.sh" 1 'BUILD: OK'
check "Angular 21: the Vitest output is read" 1 'FAILED TESTS \(1\): src/app/cart/cart.spec.ts > Cart should apply the discount'
check "Angular 21: the counts" 1 'TESTS: FAILED \(1 of 3 failed\)'
called "Angular 21: ng test runs once, without a browser option" 'ng test --watch=false --no-progress$' 'ChromeHeadless'
run build-test.sh . --filter "add a line"
check "Angular 21: a test name as the filter (--filter)" 0 'TESTS: OK \(1 tests?\)'
called "Angular 21: --filter= of the unit-test builder" 'ng test --watch=false --no-progress --filter=add a line'
# the unit-test builder with its Karma runner
sed 's/"builder": "@angular\/build:unit-test" }/"builder": "@angular\/build:unit-test", "options": { "runner": "karma" } }/' angular.json > "$work/a" && cp "$work/a" angular.json
run front-info.sh
check "front-info: the unit-test builder with runner karma is Karma" 0 'runner=karma-ng'
git checkout -q -- angular.json

# ---------- Create React App on yarn (it watches unless --watchAll=false) ----------
repo cra
cat > package.json <<'EOF'
{ "name": "cra", "version": "0.1.0", "private": true, "dependencies": { "react": "^18.3.1", "react-scripts": "5.0.1" },
  "scripts": { "start": "react-scripts start", "build": "react-scripts build", "test": "react-scripts test" } }
EOF
printf '# yarn lockfile v1\n' > yarn.lock
cat > fake-tests <<'EOF'
pass src/App.test.js App > renders the title
pass src/cart.test.js cart > sums the lines
EOF
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
commit
run front-info.sh
check "front-info: Create React App on yarn" 0 'runner=cra'
check "front-info: yarn, from yarn.lock" 0 'pm=yarn'
run build-test.sh
check "CRA: yarn installs from the lockfile" 0 'INSTALL: yarn install --frozen-lockfile'
check "CRA: the tests once" 0 'TESTS: OK \(2 tests\)'
called "CRA: --watchAll=false" 'yarn run test --watchAll=false'
run build-test.sh . --filter src/cart.test.js
check "CRA: a test file as the filter" 0 'TESTS: OK \(1 tests?\)'
run build-test.sh . --filter "renders"
called "CRA: a test name as the filter (-t)" 'yarn run test --watchAll=false -t renders'

# ---------- Vitest and Jest ----------
repo vite
mkdir -p web
cat > web/package.json <<'EOF'
{ "name": "web", "version": "1.0.0", "type": "module", "dependencies": { "vue": "^3.5.0" },
  "scripts": { "build": "vite build", "test": "vitest", "dev": "vite" } }
EOF
printf 'lockfileVersion: 9.0\n' > web/pnpm-lock.yaml
cat > web/fake-tests <<'EOF'
pass src/total.test.ts total > sums the lines
EOF
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
commit
run build-test.sh web
check "Vitest on pnpm: installs from the lockfile" 0 'INSTALL: pnpm install --frozen-lockfile'
check "Vitest: the tests once" 0 'TESTS: OK \(1 tests?\)'
called "Vitest: run once (--run)" 'pnpm run test --run'
rm web/fake-tests
run build-test.sh web
check "Vitest: no test yet is no failure" 0 'TESTS: NONE RUN \(no test in this package yet\)'

repo jest-watch
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
cat > package.json <<'EOF'
{ "name": "lib", "version": "1.0.0", "scripts": { "test": "jest --watch" } }
EOF
printf '{ "lockfileVersion": 3 }\n' > package-lock.json
printf 'pass src/a.test.js a > works\n' > fake-tests
commit
run build-test.sh
check "a test script that watches is run without its watch option" 0 'NOTE: the test script watches \(jest --watch\)'
check "and its tests run once" 0 'TESTS: OK \(1 tests?\)'

out=$(FAKE_COLOR=1 "$SHELL_UNDER_TEST" "$scripts/build-test.sh" 2>&1)
status=$?
check "colored output (a CI): the counts are read all the same" 0 'TESTS: OK \(1 test\)'
truth "and no escape sequence is shown" '! printf "%s\n" "$out" | grep -q "$(printf "\033")"'

# ---------- no unit tests to run ----------
repo e2e
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
cat > package.json <<'EOF'
{ "name": "site", "version": "1.0.0", "scripts": { "build": "ng build", "test": "playwright test" },
  "dependencies": { "@angular/core": "^19.2.0" } }
EOF
printf '{ "lockfileVersion": 3 }\n' > package-lock.json
commit
run build-test.sh
check "end-to-end tests are left to the CI" 0 'TESTS: NONE RUN \(the test script runs end-to-end tests'
called "and never run" 'ng build' 'playwright'
repo notest
printf 'node_modules/\ndist/\nbuild/\n' > .gitignore
cat > package.json <<'EOF'
{ "name": "tool", "version": "1.0.0", "scripts": { "build": "tsc", "test": "echo \"Error: no test specified\" && exit 1" } }
EOF
commit
run build-test.sh --no-build
check "no test script: none run" 0 'TESTS: NONE RUN \(no test script in package.json\)'
run build-test.sh some/where
check "a folder without package.json: the .NET path, which says what is missing" any 'BUILD|STOP|ENVIRONMENT'

# ---------- what git would commit: node_modules not ignored, a build output not ignored ----------
repo noignore
cat > package.json <<'EOF'
{ "name": "tool", "version": "1.0.0", "scripts": { "build": "vite build", "test": "vitest" }, "dependencies": { "vue": "^3.5.0" } }
EOF
printf '{ "lockfileVersion": 3 }\n' > package-lock.json
printf 'pass src/a.test.ts a > works\n' > fake-tests
commit
run build-test.sh
check "node_modules not ignored by git: no install" 1 'STOP: git does not ignore node_modules in \. '
truth "and npm never installs" '! printf "%s\n" "$calls" | grep -q "^npm ci"'
truth "and no node_modules was made" '[ ! -d node_modules ]'
printf 'node_modules/\n' > .gitignore
commit
run build-test.sh
check "a build output git does not ignore: a warning" 0 'WARNING: this run left dist/ in \., which git does not ignore'
check "and the run itself passes" 0 'TESTS: OK \(1 tests?\)'
printf 'node_modules/\ndist/\n' > .gitignore
commit
run build-test.sh
check "ignored outputs: no warning" 0 'TESTS: OK' 'WARNING: this run left'

# ---------- test-lint.sh on front-end specs ----------
repo lint
mkdir -p src
cat > src/cart.spec.ts <<'EOF'
describe("Cart", () => {
  fit("adds a line", () => {
    expect(cart.add(line).lines.length).toBe(1)
  })
  it("applies the discount", () => {
    cart.applyDiscount(10)
  })
  it("expires", () => {
    const now = Date.now()
    expect(true).toBe(true)
  })
  xit("rounds", () => {
    expect(round(1.005)).toBe(1.01)
  })
})
EOF
commit
run test-lint.sh src/cart.spec.ts
check "test-lint: a focused test is blocking" 0 'src/cart.spec.ts:2: blocking: focused test'
check "test-lint: a test without assertion is blocking" 0 'src/cart.spec.ts:5: blocking: test without assertion'
check "test-lint: a real clock is major" 0 'src/cart.spec.ts:9: major: real clock'
check "test-lint: an assertion that cannot fail" 0 'src/cart.spec.ts:10: minor: an assertion that cannot fail'
check "test-lint: a skipped test is major" 0 'src/cart.spec.ts:12: major: skipped test'
check "test-lint: the summary" 0 'TEST LINT: 5 problems \(2 blocking, 2 major\)'

echo "frontend-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
