#!/bin/sh
# What a branch changes in the contracts other code relies on, read from its diff against a base (no build): the public
# API of a library (public and protected types and members removed, changed or added), the HTTP routes of an API (route
# attributes and Map calls), and the fields of the types other repositories exchange with it (request, response, DTO,
# command, query, event, message, contract: in the name of the type or of its folder; their JSON names too). A
# heuristic for the review and the merge request; when a library enables package validation, `build-test.sh --pack`
# checks its binary compatibility for real.
# For the checker (« Compatibilité »), the pilot (the « ## Contrat » of the ticket sheet, the merge request) and the
# analyst of the other repository (related-repos.sh).
# Output: "API REMOVED|CHANGED|ADDED: <file>: <declaration>", "ROUTE REMOVED|ADDED: <file>: <line>",
# "CONTRACT FIELD REMOVED|CHANGED|ADDED: <file>: <line>", then one line
# "SURFACE: breaking (<n> removed or changed)" | "SURFACE: additive (<n> added)" | "SURFACE: unchanged".
# Usage: api-surface.sh <base> (the working tree against the base: what is committed on the branch and what is not)
#        api-surface.sh <base> <revision> (a committed revision against its merge base with the base, the working tree
#                                          untouched: /review)

base=$1
rev=$2
[ -n "$base" ] || { echo "STOP: usage: api-surface.sh <base> [<revision>]"; exit 1; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not in a git repository"; exit 1; }
cd "$root" || exit 1
git rev-parse --verify -q "$base" >/dev/null || { echo "STOP: no such base: $base"; exit 1; }
[ -z "$rev" ] || git rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "STOP: no such revision: $rev"; exit 1; }
production() { grep -v -i -E '(^|/)[^/]*tests?[^/]*/|(^|/)Migrations/|\.Designer\.cs$|\.g\.cs$|\.g\.i\.cs$|(^|/)(obj|bin)/'; }
# the production C# files the branch changed: never the tests, the migrations or the generated code
if [ -n "$rev" ]; then
  files=$(git diff --name-only "$base...$rev" -- '*.cs' 2>/dev/null | sort -u | production)
else
  files=$({ git diff --name-only "$base" -- '*.cs'; git ls-files --others --exclude-standard -- '*.cs'; } 2>/dev/null | sort -u | production)
fi
if [ -z "$files" ]; then
  echo "SURFACE: unchanged (no production C# file changed)"
  exit 0
fi
for f in $files; do
  if [ -n "$rev" ]; then
    git diff -U0 "$base...$rev" -- "$f" 2>/dev/null
  elif git cat-file -e "$base:$f" 2>/dev/null; then
    git diff -U0 "$base" -- "$f" 2>/dev/null
  else
    # a new file: every line is added
    printf 'diff --git a/%s b/%s\n+++ b/%s\n' "$f" "$f" "$f"
    sed 's/^/+/' "$f"
  fi
done | awk '
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); gsub(/[[:space:]]+/, " ", s); return s }
  # the declaration of a public or protected type or member, without its body: "kind name" as its key, or ""
  function key(s,   t, a) {
    t = s
    if (t !~ /^[[:space:]]*(public|protected)[[:space:]]/) return ""
    sub(/[[:space:]]*(\{|=>).*$/, "", t)
    sub(/[[:space:]]*=([^>]|$).*$/, "", t)
    if (match(t, /(class|interface|record|struct|enum|delegate)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) { split(substr(t, RSTART, RLENGTH), a, /[[:space:]]+/); return "type " a[2] }
    if (match(t, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(<[^>]*>)?[[:space:]]*\(/)) { u = substr(t, RSTART, RLENGTH); sub(/[[:space:]]*(<[^>]*>)?[[:space:]]*\($/, "", u); return "member " u }
    if (match(t, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(;|=)?[[:space:]]*$/)) { u = substr(t, RSTART, RLENGTH); sub(/[[:space:]]*(;|=)?[[:space:]]*$/, "", u); return "member " u }
    return ""
  }
  function decl(s,   t) { t = s; sub(/[[:space:]]*(\{|=>).*$/, "", t); return trim(t) }
  function contract(file, s) { return file ~ /(Dto|DTO|Request|Response|Command|Query|Contract|Event|Message|Model)s?(\/|\.cs$)/ || s ~ /(Dto|Request|Response|Command|Query|Contract|Event|Message)[[:space:]]*(\(|$|:|\{)/ }
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^(---|\+\+\+|diff |index |@@|new file|deleted file)/ { next }
  /^[-+]/ {
    sign = substr($0, 1, 1); line = substr($0, 2)
    if (line ~ /^[[:space:]]*(\/\/|\*|\/\*)/) next
    if (line ~ /\[(Http(Get|Post|Put|Delete|Patch|Head|Options)|Route)[[:space:]]*(\(|\])/ || line ~ /\.Map(Get|Post|Put|Delete|Patch|Methods|Group)[[:space:]]*\([[:space:]]*"/) {
      r = trim(line); if (sign == "-") rmr[r] = rmr[r] (rmr[r] == "" ? "" : "|") file; else adr[r] = adr[r] (adr[r] == "" ? "" : "|") file
    }
    if (line ~ /\[(JsonPropertyName|JsonProperty|DataMember)[[:space:]]*\(/ || (contract(file, line) && line ~ /^[[:space:]]*public[[:space:]]+[^(=]*[[:space:]][A-Za-z_][A-Za-z0-9_]*[[:space:]]*\{[[:space:]]*(get|init)/)) {
      c = trim(line); if (sign == "-") rmc[c] = file; else adc[c] = file
    }
    k = key(line)
    if (k != "") { d = decl(line); if (sign == "-") { rm[k] = rm[k] (rm[k] == "" ? "" : "\n") d; rmf[k] = file } else { ad[k] = ad[k] (ad[k] == "" ? "" : "\n") d; adf[k] = file } }
  }
  END {
    broken = 0; added = 0
    for (k in rm) {
      if (k in ad) { if (rm[k] != ad[k]) { n = split(rm[k], a, "\n"); m = split(ad[k], b, "\n"); printf "API CHANGED: %s: %s -> %s\n", rmf[k], a[1], b[1]; broken++ } }
      else { n = split(rm[k], a, "\n"); for (i = 1; i <= n; i++) { printf "API REMOVED: %s: %s\n", rmf[k], a[i]; broken++ } }
    }
    for (k in ad) if (!(k in rm)) { n = split(ad[k], b, "\n"); for (i = 1; i <= n; i++) { printf "API ADDED: %s: %s\n", adf[k], b[i]; added++ } }
    for (r in rmr) if (!(r in adr)) { printf "ROUTE REMOVED: %s: %s\n", rmr[r], r; broken++ }
    for (r in adr) if (!(r in rmr)) { printf "ROUTE ADDED: %s: %s\n", adr[r], r; added++ }
    for (c in rmc) if (!(c in adc)) { printf "CONTRACT FIELD REMOVED OR CHANGED: %s: %s\n", rmc[c], c; broken++ }
    for (c in adc) if (!(c in rmc)) { printf "CONTRACT FIELD ADDED: %s: %s\n", adc[c], c; added++ }
    if (broken > 0) print "SURFACE: breaking (" broken " removed or changed): the other repositories and the consumers of the package must follow; say it in the merge request"
    else if (added > 0) print "SURFACE: additive (" added " added): compatible for those who use it"
    else print "SURFACE: unchanged"
  }' | sort -t: -k1,1 -s | awk '/^SURFACE:/ { last = $0; next } { print } END { if (last != "") print last }'
exit 0
