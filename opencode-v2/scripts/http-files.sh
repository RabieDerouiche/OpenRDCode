#!/bin/sh
# For /outil http: the requests of the HTTP endpoints of the repository, for the HTTP client of Rider (JetBrains) and
# of Visual Studio, written from the code (api-routes.sh), in <API project folder>/http/:
#   - one <Controller>.http per controller and one <File>.http per file of minimal APIs: each request with its verb and
#     route (route parameters as {{name}}), `Authorization: Bearer {{token}}` when the endpoint needs authentication, an
#     empty JSON body to fill in when it takes one (its type in the comment above it), and a check of its success
#     status (a response handler of the JetBrains HTTP client: Rider runs it, Visual Studio leaves it);
#   - http-client.env.json: `local` (the https URL of Properties/launchSettings.json) and each environment of AGENTS.md
#     « ## Environnements » (environments.sh) but production ones, with baseUrl and a value for each route parameter;
#   - http-client.private.env.json: the token of each environment, empty, for the developer to fill in; never committed:
#     its path is added to .gitignore when git does not ignore it yet.
# A file that exists is never overwritten (its requests may have been edited): it is listed as kept.
# Usage: http-files.sh [<folder>]     the API of the repository, or of one folder of it
# Output: "HTTP: <file> (<n> requests, <b> with a body to fill in)", "KEPT: <file> (exists)", "ENVIRONMENTS: <names>",
# "IGNORED: <path added to .gitignore>", "LEFT OUT: <endpoint>: <why>"; "STOP:" when there is no endpoint.

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/http-files.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

sh "$here/api-routes.sh" ${1:+"$1"} > "$tmp/routes.md" 2>&1
# The endpoints, one per line: <group>\t<source file>\t<verb>\t<route>\t<handler>\t<authorization>\t<parameters>\t<returns>\t<summary>
awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /^### Controller / {
    group = $3; sub(/Controller$/, "", group)
    src = $0; sub(/^[^(]*\(/, "", src); sub(/:[0-9]+\).*$/, "", src); sub(/\).*$/, "", src)
    next
  }
  /^### Minimal APIs \(/ {
    src = $0; sub(/^### Minimal APIs \(/, "", src); sub(/\).*$/, "", src)
    group = src; sub(/.*\//, "", group); sub(/\.cs$/, "", group)
    next
  }
  /^### / { group = ""; next }
  group != "" && /^\| [A-Z]/ {
    n = split($0, c, "|")
    if (n < 9) next
    verb = trim(c[2]); route = trim(c[3])
    if (verb == "Verb") next
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", group, src, verb, route, trim(c[4]), trim(c[5]), trim(c[6]), trim(c[7]), trim(c[8])
  }' "$tmp/routes.md" > "$tmp/endpoints"
if [ ! -s "$tmp/endpoints" ]; then
  echo "STOP: no HTTP endpoint found in the code${1:+ of $1} (api-routes.sh): nothing written"
  exit 1
fi

# The project folder of each source file (the folder of its nearest .csproj)
project_dir() {
  d=$(dirname "$1")
  while [ "$d" != . ] && [ "$d" != / ]; do
    for c in "$d"/*.csproj; do [ -f "$c" ] && { printf '%s\n' "$d"; return 0; }; done
    d=$(dirname "$d")
  done
  printf '.\n'
}
cut -f2 "$tmp/endpoints" | sort -u | while IFS= read -r src; do printf '%s\t%s\n' "$src" "$(project_dir "$src")"; done > "$tmp/dirs"

# The environments: local from launchSettings.json, then those of AGENTS.md but production ones
sh "$here/environments.sh" | grep -v '^WARNING:' | awk -F '\t' '$5 != "yes" { print $1 "\t" $2 }' > "$tmp/envs"
sh "$here/environments.sh" | awk -F '\t' '!/^WARNING:/ && $5 == "yes" { print $1 }' > "$tmp/prod"

cut -f2 "$tmp/dirs" | sort -u | while IFS= read -r pdir; do
  out="$pdir/http"
  [ "$pdir" = . ] && out=http
  mkdir -p "$out"
  local_url=""
  if [ -f "$pdir/Properties/launchSettings.json" ]; then
    local_url=$(sed -n 's/.*"applicationUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pdir/Properties/launchSettings.json" |
      tr ';' '\n' | grep '^https://' | head -n 1)
    [ -n "$local_url" ] || local_url=$(sed -n 's/.*"applicationUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pdir/Properties/launchSettings.json" | tr ';' '\n' | head -n 1)
  fi
  # the endpoints of this project, and the parameters of their routes
  awk -F '\t' -v dirs="$tmp/dirs" -v pdir="$pdir" 'BEGIN { while ((getline l < dirs) > 0) { split(l, a, "\t"); d[a[1]] = a[2] } } d[$2] == pdir' \
    "$tmp/endpoints" > "$tmp/mine"
  params=$(cut -f4 "$tmp/mine" | grep -o '{[^}]*}' | sed 's/^{\**//; s/[:=?}].*//' | sort -u)
  # the environment files: written once, never overwritten
  if [ -f "$out/http-client.env.json" ]; then
    echo "KEPT: $out/http-client.env.json (exists)"
  else
    {
      echo "{"
      first=1
      { [ -n "$local_url" ] && printf 'local\t%s\n' "$local_url"; cat "$tmp/envs"; } | while IFS="$(printf '\t')" read -r name url; do
        [ "$first" -eq 1 ] || echo ","
        first=0
        printf '  "%s": {\n    "baseUrl": "%s"' "$name" "$url"
        printf '%s\n' "$params" | while IFS= read -r p; do [ -n "$p" ] && printf ',\n    "%s": "1"' "$p"; done
        printf '\n  }'
      done
      printf '\n}\n'
    } > "$out/http-client.env.json"
    echo "ENVIRONMENTS: $( { [ -n "$local_url" ] && echo local; cut -f1 "$tmp/envs"; } | tr '\n' ' ' | sed 's/ $//') in $out/http-client.env.json$( [ -s "$tmp/prod" ] && printf ' (production left out: %s)' "$(tr '\n' ' ' < "$tmp/prod" | sed 's/ $//')")"
  fi
  private="$out/http-client.private.env.json"
  if [ ! -f "$private" ]; then
    {
      echo "{"
      first=1
      { [ -n "$local_url" ] && echo local; cut -f1 "$tmp/envs"; } | while IFS= read -r name; do
        [ "$first" -eq 1 ] || echo ","
        first=0
        printf '  "%s": {\n    "token": ""\n  }' "$name"
      done
      printf '\n}\n'
    } > "$private"
  fi
  if ! git check-ignore -q "$private"; then
    [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ] && echo >> .gitignore
    printf '%s\n' "$private" >> .gitignore
    echo "IGNORED: $private added to .gitignore (the tokens are never committed)"
  fi
  # one file per group
  cut -f1 "$tmp/mine" | sort -u | while IFS= read -r group; do
    file="$out/$group.http"
    if [ -f "$file" ]; then
      echo "KEPT: $file (exists)"
      continue
    fi
    awk -F '\t' -v group="$group" -v file="$file" '
      function status(returns,   s, n, i, a) {
        s = returns; if (!match(s, /\([0-9, ]+\)/)) return ""
        s = substr(s, RSTART + 1, RLENGTH - 2); n = split(s, a, /, */)
        for (i = 1; i <= n; i++) if (a[i] + 0 >= 200 && a[i] + 0 < 300) return a[i]
        return ""
      }
      function needs_body(verb, params,   n, i, a, p, t) {
        if (params ~ /\[FromBody\]/) { match(params, /\[FromBody\][ \t]*[A-Za-z0-9_.<>?\[\]]+/); t = substr(params, RSTART, RLENGTH); sub(/\[FromBody\][ \t]*/, "", t); return t }
        if (verb !~ /^(POST|PUT|PATCH)$/) return ""
        n = split(params, a, /, */)
        for (i = 1; i <= n; i++) {
          p = a[i]
          if (p ~ /\[From(Route|Query|Header|Services|Form|Keyed)/ || p == "-" || p == "") continue
          t = p; sub(/[ \t]+[A-Za-z0-9_]+$/, "", t)
          if (t ~ /^(int|long|short|byte|string|bool|Guid|DateTime|DateTimeOffset|DateOnly|TimeOnly|decimal|double|float|CancellationToken|HttpContext|HttpRequest|ClaimsPrincipal|IFormFile)\??$/) continue
          if (t ~ /^[A-Z]/) return t
        }
        return ""
      }
      $1 == group {
        verb = $3; route = $4
        if (route ~ /</ || verb !~ /^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|ANY)$/) { print "LEFT OUT: " verb " " route ": " (route ~ /</ ? "a route computed in the code" : "not an HTTP request") > "/dev/stderr"; next }
        if (verb == "ANY") verb = "GET"
        path = route; gsub(/\{\**/, "{{", path); gsub(/(:[^}]*|=[^}]*|\?)\}/, "}}", path); gsub(/\}/, "}}", path); gsub(/\}\}\}\}/, "}}", path)
        title = ($9 != "-" && $9 != "") ? $9 : verb " " route
        body = needs_body(verb, $7)
        code = status($8)
        n++
        if (n == 1) {
          print "# The requests of " group ", written by the pack (http-files.sh) from the code. Fill in the bodies, the route"
          print "# values in http-client.env.json and your tokens in http-client.private.env.json (never committed)."
          print ""
        }
        print "### " title
        print "# " verb " " route " - " $5 " (" $2 ")"
        if (body != "") print "# body: " body ", to fill in"
        print verb " {{baseUrl}}" path
        print "Accept: application/json"
        if ($6 != "-" && $6 !~ /anonymous/) print "Authorization: Bearer {{token}}"
        if (body != "") { print "Content-Type: application/json"; print ""; print "{}" }
        print ""
        print "> {%"
        print "    client.test(\"" verb " " route "\", function () {"
        if (code != "") print "        client.assert(response.status === " code ", \"status \" + response.status);"
        else print "        client.assert(response.status >= 200 && response.status < 300, \"status \" + response.status);"
        print "    });"
        print "%}"
        print ""
        if (body != "") bodies++
      }
      END { print n "\t" bodies > (file ".count") }' "$tmp/mine" > "$file" 2>> "$tmp/left"
    count=$(cut -f1 "$file.count")
    b=$(cut -f2 "$file.count")
    rm -f "$file.count"
    [ "${count:-0}" -gt 0 ] || { rm -f "$file"; continue; }
    echo "HTTP: $file ($count requests${b:+, $b with a body to fill in})" | sed 's/, 0 with a body to fill in//; s/, with a body to fill in//'
  done
done
sort -u "$tmp/left" 2>/dev/null
exit 0
