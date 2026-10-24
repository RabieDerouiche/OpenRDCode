#!/bin/sh
# The environments where the API of the repository is deployed, as its AGENTS.md declares them, for env-tests.sh and
# http-files.sh. Section « ## Environnements », one line per environment:
#   - `recette` : https://api-recette.example.com (jeton : `API_TOKEN_RECETTE`, écriture permise)
#   - `prod` : https://api.example.com (production)
# its name between backquotes, its base URL, then optionally: « jeton : `<VARIABLE>` », the environment variable of this
# machine that holds its token (set outside OpenCode, in ~/.zshenv: never in AGENTS.md, never in a command);
# « écriture permise », tests that write may run there; « production ». A production environment (marked, or named
# prod, production, prd or live) is listed as such: no test of the pack ever runs there. A URL with a user or a
# password is refused: the token comes from its variable. Read-only.
# Output: one line per environment, tab-separated: <name> <url> <token variable or -> <writes: yes|no> <production: yes|no>
#         then "WARNING:" lines (a line of the section not understood, a URL with credentials)
# Usage: environments.sh [<name>]     with a name: its line only; exit 1 when it is not declared

LC_ALL=C
export LC_ALL

root=$(git rev-parse --show-toplevel 2>/dev/null) || root=.
file=$root/AGENTS.md
[ -f "$file" ] || { [ -n "$1" ] && exit 1; exit 0; }
awk -v want="$1" '
  function lower(s) { return tolower(s) }
  /^## / { insec = (lower($0) ~ /^## +(environnements|environments)[ \t]*$/); next }
  !insec || $0 !~ /^[ \t]*[-*] / { next }
  {
    line = $0
    if (!match(line, /`[^`]+`/)) { print "WARNING: not understood (no `name`): " line; next }
    name = substr(line, RSTART + 1, RLENGTH - 2)
    rest = substr(line, RSTART + RLENGTH)
    if (!match(rest, /https?:\/\/[^ \t`,;()]+/)) { print "WARNING: " name ": no http(s) URL"; next }
    url = substr(rest, RSTART, RLENGTH)
    after = substr(rest, RSTART + RLENGTH)
    sub(/\/+$/, "", url)
    host = url
    sub(/^https?:\/\//, "", host)
    sub(/\/.*/, "", host)
    if (host ~ /@/) { print "WARNING: " name ": a user or a password in its URL: never; its token comes from a variable (jeton : `VARIABLE`)"; next }
    token = "-"
    low = lower(after)
    if (match(low, /(jeton|token)[^`]*`[A-Za-z_][A-Za-z0-9_]*`/)) {
      t = substr(after, RSTART, RLENGTH)
      sub(/`$/, "", t)
      sub(/.*`/, "", t)
      token = t
    }
    writes = (low ~ /criture permise|writes allowed/) ? "yes" : "no"
    prod = (low ~ /production/ || lower(name) ~ /^(prod|production|prd|live)$/) ? "yes" : "no"
    if (prod == "yes") writes = "no"
    if (want == "" || want == name) { print name "\t" url "\t" token "\t" writes "\t" prod; found = 1 }
  }
  END { if (want != "" && !found) exit 1 }
' "$file"
