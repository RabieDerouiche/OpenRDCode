#!/bin/sh
# The quality of test code, read from its files (no build, no run): what makes a test pass without proving anything,
# hide the other tests, or fail at random. For the coder and the test-guardian (their new tests), /go and /fix (the test
# files of the branch) and the checker. C# (xUnit, NUnit, MSTest, TUnit) and TypeScript / JavaScript specs (Jasmine,
# Jest, Vitest, Mocha).
#   blocking  a focused test (fdescribe, fit, .only): the other tests of the suite silently stop running;
#             a test without any assertion: it passes whatever the code does
#   major     a real clock (DateTime.Now, Date.now()), a sleep or a real delay (Thread.Sleep, Task.Delay, setTimeout),
#             a real HTTP client or call, an unseeded Random, a skipped test (Skip, [Ignore], xit, it.skip); a file of
#             environment tests (the category Environment, run by env-tests.sh) calls the deployed API and skips
#             itself without API_BASE_URL: neither is a finding there
#   minor     an assertion that cannot fail (Assert.True(true), expect(true).toBe(true))
# With --changed <base>: the test files the branch adds or changes (committed or not), and only what its lines
# brought; a focused test is reported wherever it is.
# Output: one line per finding, "<file>:<line>: <severity>: <what>", then "TEST LINT: OK" or
# "TEST LINT: <n> problems (<b> blocking, <m> major)".
# With --changed <base> <revision>: the same for a committed revision (its files as committed, the working tree
# untouched: /review).
# Usage: test-lint.sh <test file>... | test-lint.sh --changed <base> [<revision>]

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not in a git repository"; exit 1; }
cd "$root" || exit 1
rev=""
is_test_file() {
  case "$1" in
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx|*.spec.mjs|*.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.test.mjs) return 0 ;;
    *.cs) printf '%s\n' "$1" | grep -qiE '(^|/)[^/]*tests?[^/]*/' && return 0 ;;
  esac
  return 1
}

base="" files=""
if [ "$1" = --changed ]; then
  base=$2
  rev=$3
  [ -n "$base" ] || { echo "STOP: usage: test-lint.sh --changed <base> [<revision>]"; exit 1; }
  git rev-parse --verify -q "$base" >/dev/null || { echo "STOP: no such base: $base"; exit 1; }
  [ -z "$rev" ] || git rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "STOP: no such revision: $rev"; exit 1; }
  if [ -n "$rev" ]; then
    files=$(git diff --name-only --diff-filter=AM "$base...$rev" 2>/dev/null | sort -u | while IFS= read -r f; do is_test_file "$f" && echo "$f"; done)
  else
    files=$({ git diff --name-only --diff-filter=AM "$base"...HEAD; git diff --name-only --diff-filter=AM HEAD; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u |
      while IFS= read -r f; do [ -f "$f" ] && is_test_file "$f" && echo "$f"; done)
  fi
else
  files=$(for f in "$@"; do f=${f#"$root"/}; [ -f "$f" ] && echo "$f"; done)
fi
if [ -z "$files" ]; then
  echo "TEST LINT: OK (no test file to read)"
  exit 0
fi

# the lines the branch brought, per file (--changed): "<file>:<line>" from the diff since the base, and every line of
# a file the branch adds or that git does not track yet
added() {
  if [ -n "$rev" ]; then
    { git diff -U0 "$base...$rev" -- "$1"; } 2>/dev/null | awk '
      /^@@/ { s = $3; sub(/^\+/, "", s); split(s, a, ","); n = (a[2] == "") ? 1 : a[2] + 0; for (i = 0; i < n; i++) print a[1] + i }'
  elif git cat-file -e "$base:$1" 2>/dev/null; then
    { git diff -U0 "$base" -- "$1"; } 2>/dev/null | awk '
      /^@@/ { s = $3; sub(/^\+/, "", s); split(s, a, ","); n = (a[2] == "") ? 1 : a[2] + 0; for (i = 0; i < n; i++) print a[1] + i }'
  else
    awk '{ print NR }' "$1"
  fi
}

total=0 blocking=0 major=0
if [ -n "$rev" ]; then
  committed=$(mktemp "${TMPDIR:-/tmp}/test-lint.XXXXXX") || exit 1
  trap 'rm -f "$committed"' EXIT
fi
report=$(for f in $files; do
  src=$f
  if [ -n "$rev" ]; then git show "$rev:$f" > "$committed" 2>/dev/null; src=$committed; fi
  lines=""
  [ -n "$base" ] && lines=$(added "$f" | tr '\n' ' ')
  case "$f" in *.cs) lang=cs ;; *) lang=ts ;; esac
  # environment tests (env-tests.sh): their HTTP calls to the deployed API are what they test, and they are skipped
  # without API_BASE_URL
  envtests=0
  grep -q -E '(Trait|Category|TestCategory)[[:space:]]*\([[:space:]]*("Category",[[:space:]]*)?"Environment(Writes)?"' "$src" 2>/dev/null && envtests=1
  awk -v file="$f" -v lang="$lang" -v envtests="$envtests" -v lines=" $lines " -v all="$([ -z "$base" ] && echo 1 || echo 0)" '
    function brought(n) { return all == 1 || index(lines, " " n " ") > 0 }
    function say(n, sev, what) { print file ":" n ": " sev ": " what }
    function braces(s,   t, o, c) { t = s; gsub(/"([^"\\]|\\.)*"|'"'"'([^'"'"'\\]|\\.)*'"'"'|\/\/.*$/, "", t); o = gsub(/\{/, "{", t); c = gsub(/\}/, "}", t); return o - c }
    { text[NR] = $0 }
    END {
      fake = 0
      for (i = 1; i <= NR; i++) if (text[i] ~ /useFakeTimers|jasmine\.clock\(\)|fakeAsync|FakeTimeProvider|TimeProvider|ISystemClock|IClock|IDateTimeProvider/) fake = 1
      for (i = 1; i <= NR; i++) {
        l = text[i]
        if (l ~ /^[[:space:]]*(\/\/|\*|\/\*)/) continue
        if (lang == "ts") {
          if (l ~ /(^|[^A-Za-z0-9_.])(fdescribe|fit)[[:space:]]*\(/ || l ~ /(^|[^A-Za-z0-9_])(describe|it|test|context|suite)\.only[[:space:]]*\(/) say(i, "blocking", "focused test (fdescribe, fit or .only): the other tests of the suite silently stop running")
          if (!brought(i)) continue
          if (l ~ /(^|[^A-Za-z0-9_.])(xit|xdescribe|xtest)[[:space:]]*\(/ || l ~ /(^|[^A-Za-z0-9_])(describe|it|test)\.skip[[:space:]]*\(/) say(i, "major", "skipped test: it never runs; remove it or make it pass")
          if (!fake && l ~ /setTimeout[[:space:]]*\(|new Promise\([^)]*setTimeout/) say(i, "major", "real delay in a test: fake timers (fakeAsync and tick, vi.useFakeTimers, jest.useFakeTimers) instead")
          if (!fake && (l ~ /Date\.now[[:space:]]*\(\)/ || l ~ /new Date[[:space:]]*\([[:space:]]*\)/)) say(i, "major", "real clock in a test: a fixed date, or fake timers")
          if (l ~ /expect\([[:space:]]*(true|false|1)[[:space:]]*\)\.(toBe|toEqual|toBeTruthy|toBeFalsy)/) say(i, "minor", "an assertion that cannot fail")
          if (l ~ /(^|[^A-Za-z0-9_.])(it|test)[[:space:]]*\(/ && l !~ /\.(each|skip|todo)/) {
            depth = 0; ok = 0; started = 0
            for (j = i; j <= NR && j < i + 400; j++) {
              if (text[j] ~ /expect[A-Za-z]*[[:space:]]*\(|assert[A-Za-z.]*[[:space:]]*\(|\.should[^A-Za-z]|toHaveBeenCalled|toMatchSnapshot|verify[A-Za-z]*[[:space:]]*\(|(get|find|getAll|findAll)By[A-Z][A-Za-z]*[[:space:]]*\(/) ok = 1
              depth += braces(text[j]); if (index(text[j], "{")) started = 1
              if (started && depth <= 0) break
              if (!started && j > i + 2) break
            }
            if (!ok && started) say(i, "blocking", "test without assertion: it passes whatever the code does")
          }
        } else {
          if (!brought(i)) continue
          if (l ~ /Thread\.Sleep[[:space:]]*\(|Task\.Delay[[:space:]]*\(/) say(i, "major", "sleep or real delay in a test: a fake clock (FakeTimeProvider) or a synchronous seam instead")
          if (!fake && l ~ /DateTime(Offset)?\.(Now|UtcNow|Today)/) say(i, "major", "real clock in a test: a fixed date, or a FakeTimeProvider (Microsoft.Extensions.TimeProvider.Testing) when the code takes a TimeProvider")
          if (!envtests && (l ~ /new HttpClient[[:space:]]*\([[:space:]]*\)/ || l ~ /https?:\/\/[A-Za-z0-9.-]+\.(com|net|org|fr|io)/ && l ~ /GetAsync|PostAsync|SendAsync|GetStringAsync/)) say(i, "major", "real HTTP call in a unit test: a fake HttpMessageHandler, or WebApplicationFactory for the API itself")
          if (l ~ /new Random[[:space:]]*\([[:space:]]*\)/) say(i, "major", "unseeded Random: a test that changes from run to run; give it a seed, or fixed values")
          if (l ~ /\[(Fact|Theory|Test|TestMethod)[^]]*Skip[[:space:]]*=/ || l ~ /\[(Ignore|Explicit)[^]]*\]/ || !envtests && l ~ /Assert\.(Inconclusive|Ignore)\(/) say(i, "major", "skipped test: it never runs; remove it or make it pass")
          if (l ~ /Assert\.(True|IsTrue)\([[:space:]]*true[[:space:]]*\)|Assert\.(False|IsFalse)\([[:space:]]*false[[:space:]]*\)/) say(i, "minor", "an assertion that cannot fail")
          if (l ~ /\[(Fact|Theory|Test|TestCase|TestMethod|DataTestMethod)([^A-Za-z]|$)/) {
            expected = 0
            for (j = i; j <= NR && j < i + 8; j++) { if (text[j] ~ /\[ExpectedException/) expected = 1; if (text[j] ~ /(void|Task|ValueTask)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*\(/) break }
            if (j > NR || j >= i + 8) continue
            depth = 0; ok = expected; started = 0; arrow = 0
            for (k = j; k <= NR && k < j + 400; k++) {
              if (text[k] ~ /Assert[A-Za-z]*\.|\.Should[A-Za-z]*\(|Should[A-Za-z]*\.|\.Verify[A-Za-z]*\(|\.Received[A-Za-z]*\(|\.DidNotReceive[A-Za-z]*\(|Throws[A-Za-z]*[<(]|Verifier\.|Snapshot|(^|[[:space:](;=!])(Assert|Verify|Check|Ensure|Expect)[A-Za-z0-9_]*[[:space:]]*\(/) ok = 1
              if (!started && text[k] ~ /=>/ && text[k] !~ /\{/) arrow = 1
              if (arrow) { if (text[k] ~ /;[[:space:]]*$/) { started = 1; break } ; continue }
              depth += braces(text[k]); if (index(text[k], "{")) started = 1
              if (started && depth <= 0) break
            }
            if (!ok && started) say(j, "blocking", "test without assertion: it passes whatever the code does")
          }
        }
      }
    }' "$src"
done)
if [ -n "$report" ]; then
  printf '%s\n' "$report"
  total=$(printf '%s\n' "$report" | grep -c .)
  blocking=$(printf '%s\n' "$report" | grep -c ': blocking: ')
  major=$(printf '%s\n' "$report" | grep -c ': major: ')
  echo "TEST LINT: $total problems ($blocking blocking, $major major)"
else
  echo "TEST LINT: OK ($(printf '%s\n' "$files" | grep -c .) test files read)"
fi
exit 0
