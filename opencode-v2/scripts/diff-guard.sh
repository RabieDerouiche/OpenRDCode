#!/bin/sh
# Check of the branch before ship.sh pushes it, without the model: what nobody may push, and what the merge request must
# say. /go and /fix push without a human in between, so this check is the last gate.
# STOP (exit 1, nothing pushed): a secret in a line added by any commit about to be pushed, even one removed by a later
# commit (the history is pushed too): private key, cloud or GitLab/GitHub/Slack token, user and password in a URL, a
# password in a connection string, a secret value in a configuration file; a key or certificate file, a .env file or
# the private environment file of an HTTP client (Rider: http-client.private.env.json, Visual Studio:
# http-client.env.json.user, where /outil http keeps the secrets) added by one of these commits; a merge conflict
# marker left in the code; a package whose added version is paid or copyleft (package-licenses.sh); installed
# dependencies or build outputs (node_modules, obj, bin/Debug, TestResults) that a .gitignore misses; the value of a
# secret variable of the environment (a name with PASSWORD, PASSWD, TOKEN, SECRET, API_KEY or CREDENTIAL: the
# Artifactory password of ~/.zshenv) anywhere in an added line, test files and "gitleaks:allow" included. The value of
# a secret is never printed: only its kind and its place.
# WARNING (exit 0): the same findings in test files (fake tokens in fixtures), a binary or a file over 1 MB added, a
# dist/ or coverage/ folder added.
# PACKAGES (exit 0): every package added or changed, for the merge request.
# A false positive: the comment "gitleaks:allow" (or "pragma: allowlist secret") on that line lets it through.
# Usage: diff-guard.sh [<base ref>]     default: the base of the branch (base.sh), origin/develop when none is recorded

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

here=$(cd "$(dirname "$0")" && pwd)
base=$1
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "GUARD: not a git repository"
  exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 0
if [ -z "$base" ]; then
  # the base of the branch (base.sh: the one recorded when it started from another branch, otherwise develop, main or
  # master)
  name=$(sh "$here/base.sh")
  [ -n "$name" ] && base="origin/$name"
fi
if [ -z "$base" ] || ! git rev-parse -q --verify "$base" >/dev/null; then
  echo "GUARD: no base branch to compare with: nothing checked"
  exit 0
fi
mb=$(git merge-base HEAD "$base" 2>/dev/null)
if [ -z "$mb" ]; then
  echo "GUARD: no common commit with $base: nothing checked"
  exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/diff-guard.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# The commits about to be pushed: reachable from HEAD, on no branch of origin yet (the merges of develop bring commits
# that are already there), merge commits left out (a clean merge adds no line of its own)
git log --no-color --no-ext-diff -p -U0 --no-merges --format='commit %h' HEAD --not --remotes=origin > "$tmp/history"
git log --no-ext-diff --no-merges --diff-filter=A --name-only --format= HEAD --not --remotes=origin | sort -u | grep . > "$tmp/added-history"
commits=$(grep -c '^commit ' "$tmp/history")
# The state of the branch against its base: conflict markers left, binaries and large files, packages
git diff --no-color --no-ext-diff -U0 "$mb" HEAD > "$tmp/diff"
git diff --no-ext-diff --name-only --diff-filter=A "$mb" HEAD > "$tmp/added"
git diff --no-ext-diff --numstat "$mb" HEAD > "$tmp/numstat"
files=$(grep -c . "$tmp/numstat")

scan() {
  awk -v mode="$1" '
  # the values of the secret variables of the environment: never pushed, whatever the file, and never printed
  BEGIN {
    if (mode == "secrets") for (k in ENVIRON) {
      v = ENVIRON[k]
      if (toupper(k) ~ /PASSWORD|PASSWD|TOKEN|SECRET|API_?KEY|CREDENTIAL/ && length(v) >= 8 && v !~ /^[\/~.$]/ && v !~ /^(true|false|[0-9]+)$/) {
        secrets++
        secret_name[secrets] = k
        secret_value[secrets] = v
      }
    }
  }
  function test_file(f) {
    f = tolower(f)
    return f ~ /(^|\/)(tests?|specs?|__tests__|testdata|test-data|fixtures?|mocks?)\// || f ~ /\.(unit|integration|functional|e2e)?tests?\// || f ~ /(tests?|spec)\.(cs|ts|tsx|js|jsx)$/ || f ~ /\.(spec|test)\.(ts|tsx|js|jsx)$/
  }
  function config_file(f) {
    f = tolower(f)
    return f ~ /(^|\/)appsettings[^\/]*\.json$/ || f ~ /\.(config|yml|yaml|properties|ini|toml|env)$/ || f ~ /(^|\/)\.env(\.[^\/]*)?$/ || f ~ /(^|\/)launchsettings\.json$/ || f ~ /(^|\/)http-client[^\/]*\.json(\.user)?$/
  }
  # a value that only stands for a secret: empty, a placeholder, a variable, a reference to a secret store
  function placeholder(v,   l) {
    l = tolower(v)
    gsub(/^["'\'']+|["'\'',;]+$/, "", l)
    if (length(l) < 6) return 1
    if (l ~ /^(<.*>|\{.*\}|\$\{.*\}|\$\(.*\)|#\{.*\}#?|__.*__|%.*%|\*+|x+|\.+)$/) return 1
    # a variable of an HTTP client ({{clientSecret}}, {{$auth.token("api")}}, {{$processEnv NAME}}), cut at its first }
    if (l ~ /^(\{\{|\$\{|\$\()/) return 1
    if (l ~ /^(changeme|change_me|password|passwd|secret|token|apikey|api_key|your[-_].*|my[-_].*|example.*|dummy.*|fake.*|sample.*|test.*|todo|tbd|null|none|undefined|replace.*|placeholder.*|\[.*\])$/) return 1
    if (l ~ /^(env|vault|secret|keyvault|azurekeyvault|aws|ssm|arn):/) return 1
    return 0
  }
  function report(kind,   where) {
    where = file ":" line (commit != "" ? " (commit " commit ")" : "")
    if (index(text, "gitleaks:allow") || index(text, "pragma: allowlist secret")) return
    if (test_file(file)) print "WARNING|" kind " in a test file, " where " (fake value? check it before the review)"
    else print "STOP|" kind " in " where
  }
  /^commit / { commit = $2; file = ""; next }
  /^diff --git / { file = ""; next }
  /^\+\+\+ / { file = substr($0, 5); sub(/^b\//, "", file); if (file == "/dev/null") file = ""; next }
  /^@@ / {
    n = $0; sub(/^@@ -[0-9,]+ \+/, "", n); sub(/[ ,].*$/, "", n); line = n + 0; next
  }
  /^\+/ && file != "" && mode == "conflicts" {
    if (substr($0, 2) ~ /^(<<<<<<<|>>>>>>>)( |$)/) print "STOP|merge conflict marker in " file ":" line
    line++
    next
  }
  /^\+/ && file != "" {
    text = substr($0, 2)
    found = 0
    for (i = 1; i <= secrets; i++) if (index(text, secret_value[i])) {
      print "STOP|value of the environment variable " secret_name[i] " in " file ":" line (commit != "" ? " (commit " commit ")" : "")
      found = 1
    }
    if (found) { line++; next }
    if (text ~ /-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----/) report("private key")
    else if (text ~ /(^|[^A-Z0-9])(AKIA|ASIA)[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z]([^A-Z0-9]|$)/) report("AWS access key")
    else if (text ~ /gl(pat|dt|rt|ptt|ft|imt|oas|cbt|soat|ffct|agent)-[0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-]/) report("GitLab token")
    else if (text ~ /(gh[pousr]_[0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z][0-9A-Za-z]|github_pat_[0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_][0-9A-Za-z_])/) report("GitHub token")
    else if (text ~ /xox[baprs]-[0-9A-Za-z][0-9A-Za-z-]*-[0-9A-Za-z-][0-9A-Za-z-][0-9A-Za-z-][0-9A-Za-z-][0-9A-Za-z-][0-9A-Za-z-]/) report("Slack token")
    else if (text ~ /eyJ[0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-]*\.eyJ[0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-]*\.[0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-][0-9A-Za-z_-]/) report("JWT (signed token)")
    else {
      # user and password in a URL: scheme://user:password@host
      if (match(text, /[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/ \t:@"'\''<>{}$]+:[^\/ \t@"'\''<>{}$]+@/)) {
        cred = substr(text, RSTART, RLENGTH); sub(/^[^:]*:\/\/[^:]*:/, "", cred); sub(/@$/, "", cred)
        if (!placeholder(cred)) { report("user and password in a URL"); line++; next }
      }
      # a password in a connection string: Password=...; or Pwd=...;
      if (match(text, /(^|[;"'\'' \t])([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Ww][Dd])[ \t]*=[ \t]*[^;"'\'' \t]+/)) {
        value = substr(text, RSTART, RLENGTH); sub(/^[^=]*=[ \t]*/, "", value)
        if (!placeholder(value)) { report("password in a connection string"); line++; next }
      }
      # a secret value in a configuration file: "Password": "...", ClientSecret: ..., api_key=...
      if (config_file(file) && match(text, /["'\'']?[A-Za-z0-9_.:-]*([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Pp][Ii]_?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss]_?[Kk][Ee][Yy]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]_?[Kk][Ee][Yy]|[Tt][Oo][Kk][Ee][Nn])["'\'']?[ \t]*[:=][ \t]*["'\'']?[^"'\'' \t,}]+/)) {
        value = substr(text, RSTART, RLENGTH); sub(/^[^:=]*[:=][ \t]*/, "", value)
        if (!placeholder(value) && value !~ /^(true|false|[0-9]+)$/) { report("secret value in a configuration file"); line++; next }
      }
    }
    line++
  }
' "$2"
}
{
  scan secrets "$tmp/history"
  scan conflicts "$tmp/diff"
} > "$tmp/findings"

# Files that should never be pushed, even when a later commit deleted them: keys, certificates with their key, .env
while IFS= read -r f; do
  lower=$(printf '%s' "$f" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *.env.example|*.env.sample|*.env.template|*.env.dist) continue ;;
  esac
  kind=""
  case "$lower" in
    *.pfx|*.p12|*.key|*.jks|*.keystore|*.kdbx|*.ppk|*/id_rsa|id_rsa|*/id_ed25519|id_ed25519|*/id_ecdsa|id_ecdsa) kind="key or certificate file" ;;
    .env|*/.env|.env.*|*/.env.*) kind=".env file" ;;
    *private.env.json|*.env.json.user) kind="private environment file of an HTTP client (its secrets)" ;;
  esac
  [ -n "$kind" ] || continue
  case "/$lower" in
    */test/*|*/tests/*|*/testdata/*|*/fixtures/*|*.tests/*|*.test/*) echo "WARNING|$kind added in a test folder: $f (fake value? check it before the review)" ;;
    *) echo "STOP|$kind added: $f" ;;
  esac
done < "$tmp/added-history" >> "$tmp/findings"

# Installed dependencies and build outputs added by these commits (a folder the .gitignore misses: node_modules after an
# install, obj/ after a build): one line per folder kind, never pushed; bin/, dist/ and coverage/ may be meant (a legacy
# site with its bin/ in git): a warning
awk '{ p = "/" $0
  if (p ~ /\/node_modules\//) k = "node_modules"; else if (p ~ /\/obj\//) k = "obj"; else if (p ~ /\/\.angular\/cache\//) k = ".angular/cache"
  else if (p ~ /\/TestResults\//) k = "TestResults"; else if (p ~ /\/bin\/(Debug|Release)\//) k = "bin/Debug or bin/Release"
  else if (p ~ /\/(dist|coverage)\//) k = (p ~ /\/dist\//) ? "dist" : "coverage"; else next
  n[k]++; if (!(k in first)) first[k] = $0 }
  END { for (k in n) {
    sev = (k == "dist" || k == "coverage") ? "WARNING" : "STOP"
    print sev "|" n[k] " file(s) of " k " added (" first[k] (n[k] > 1 ? ", …" : "") "): an install or a build output that .gitignore misses; the developer adds " k "/ to .gitignore and takes them out of the commits not pushed yet" } }' "$tmp/added-history" >> "$tmp/findings"

# Binaries and large files added
while IFS= read -r f; do
  size=$(git cat-file -s "HEAD:$f" 2>/dev/null) || continue
  if grep -q "^-	-	$f\$" "$tmp/numstat"; then
    echo "WARNING|binary file added: $f ($size bytes)"
  elif [ "$size" -gt 1048576 ]; then
    echo "WARNING|large file added: $f ($size bytes)"
  fi
done < "$tmp/added" >> "$tmp/findings"

# Packages added or changed, and the paid or copyleft versions among them
sh "$here/package-licenses.sh" --diff "$base" > "$tmp/packages" 2>/dev/null
grep -E '^- [+~] .*\]: (COMMERCIAL|MAINTENANCE FEE|AGPL) ' "$tmp/packages" | sed 's/^- /STOP|paid or copyleft package: /' >> "$tmp/findings"

stops=$(grep -c '^STOP|' "$tmp/findings")
warnings=$(grep -c '^WARNING|' "$tmp/findings")
if [ "$stops" -gt 0 ]; then
  echo "GUARD: STOP, $stops problem(s) in the $commits commit(s) not pushed yet or in the changes since $base: nothing may be pushed"
  grep '^STOP|' "$tmp/findings" | sort -u | sed 's/^STOP|/- /'
  echo "A false positive: the comment gitleaks:allow on that line, then run again. A real secret: it is in a local commit only (nothing was pushed): rewrite the local commits without it (COMMANDES.md, section \"Contrôle avant push\"), and have it revoked if it is a real one."
else
  echo "GUARD: OK ($commits commit(s) to push, $files files changed since $base: no secret, no conflict marker, no paid package)"
fi
if [ "$warnings" -gt 0 ]; then
  grep '^WARNING|' "$tmp/findings" | sort -u | sed 's/^WARNING|/WARNING: /'
fi
if grep -q '^- [+~] ' "$tmp/packages"; then
  echo "PACKAGES (for the merge request):"
  grep '^- [+~] ' "$tmp/packages" | sed 's/^- /  /'
fi
[ "$stops" -gt 0 ] && exit 1
exit 0
