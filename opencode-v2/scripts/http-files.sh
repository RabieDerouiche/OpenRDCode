#!/bin/sh
# For /outil http: the requests of the HTTP endpoints of the repository, for the HTTP client of Rider (JetBrains) and
# of Visual Studio, written from the code (api-routes.sh), in <API project folder>/http/:
#   - one <Controller>.http per controller and one <File>.http per file of minimal APIs: each request with its verb and
#     route (route parameters as {{name}}), its token when the endpoint needs authentication, an empty JSON body to
#     fill in when it takes one (its type in the comment above it), and a check of its success status (a response
#     handler of the JetBrains HTTP client: Rider runs it, Visual Studio leaves it);
#   - http-client.env.json: `local` (the https URL of Properties/launchSettings.json) and each environment of AGENTS.md
#     « ## Environnements » (environments.sh) but production ones, with baseUrl and a value for each route parameter.
#     For Rider (the default), the token of each environment is Rider's own: an environment with OpenID Connect gets the
#     OAuth 2.0 client credentials of the HTTP client (its token URL, client id, scope, how the client authenticates:
#     Rider asks the token and renews it), the others a token to paste (Type Mock); every request says
#     `Authorization: Bearer {{$auth.token("api")}}`. For Visual Studio (--client vs): `Authorization: Bearer {{token}}`;
#   - http-client.private.env.json: what each environment needs and nobody commits (the client secret, a token, the
#     client id when AGENTS.md keeps it in a variable), empty, for the developer to fill in; never committed (its path is
#     added to .gitignore when git does not ignore it yet), never rewritten once it exists (the missing keys are named).
# A file that exists is kept (its requests may have been edited), unless --replace: the .http files of the groups
# chosen and http-client.env.json are written again, never the private file.
# Usage: http-files.sh [--plan] [--only <group>[,<group>...]] [--replace] [--client rider|vs] [<folder>]
#   --plan     what would be written, nothing written: "PLAN:", "GROUP:", "ENVIRONMENT:", "FILE:" lines
# Output: "HTTP: <file> (<n> requests, <b> with a body to fill in)", "KEPT: <file> (exists)", "ENVIRONMENTS: <names>",
# "IGNORED: <path added to .gitignore>", "PRIVATE: <what to fill in>", "NOTE:", "LEFT OUT: <endpoint>: <why>"; "STOP:"
# when there is no endpoint.

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
plan=0 only="" replace=0 client=rider folder=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan=1; shift ;;
    --only) only=$2; shift 2 ;;
    --replace) replace=1; shift ;;
    --client) client=$2; shift 2 ;;
    -*) echo "STOP: unknown option $1 (http-files.sh [--plan] [--only <groups>] [--replace] [--client rider|vs] [<folder>])"; exit 1 ;;
    *) folder=$1; shift ;;
  esac
done
case "$client" in rider|vs) ;; *) echo "STOP: --client rider or vs"; exit 1 ;; esac
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/http-files.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

sh "$here/api-routes.sh" ${folder:+"$folder"} > "$tmp/routes.md" 2>&1
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
  }' "$tmp/routes.md" > "$tmp/all"
if [ ! -s "$tmp/all" ]; then
  echo "STOP: no HTTP endpoint found in the code${folder:+ of $folder} (api-routes.sh): nothing written"
  exit 1
fi
# the groups chosen (--only), all by default
if [ -n "$only" ]; then
  printf '%s\n' "$only" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/Controller$//' | grep . > "$tmp/only"
  awk -F '\t' -v f="$tmp/only" 'BEGIN { while ((getline l < f) > 0) want[l] = 1 } want[$1]' "$tmp/all" > "$tmp/endpoints"
  [ -s "$tmp/endpoints" ] || { echo "STOP: no endpoint in the groups $only (the groups: $(cut -f1 "$tmp/all" | sort -u | tr '\n' ' ' | sed 's/ $//'))"; exit 1; }
else
  cp "$tmp/all" "$tmp/endpoints"
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

# The environments: those of AGENTS.md but production ones, each with its settings ("key=value" of environments.sh)
sh "$here/environments.sh" | grep -v '^WARNING:' | awk -F '\t' '$5 != "yes" { print $1 }' > "$tmp/envs"
sh "$here/environments.sh" | awk -F '\t' '!/^WARNING:/ && $5 == "yes" { print $1 }' > "$tmp/prod"
: > "$tmp/notes"
while IFS= read -r e; do
  [ -n "$e" ] || continue
  sh "$here/environments.sh" --details "$e" | grep -v '^WARNING:' > "$tmp/env.$e"
  get() { sed -n "s/^$1=//p" "$tmp/env.$e" | head -n 1; }
  if [ "$client" = rider ] && [ "$(get auth)" = oidc ] && [ -z "$(get token_url)" ]; then
    # the token URL that Rider needs: from the discovery document of the provider, when it answers from here
    ep=$(sh "$here/env-tests.sh" --discover "$e" 2>/dev/null | sed -n 's/^TOKEN ENDPOINT: //p' | head -n 1)
    if [ -n "$ep" ]; then
      printf 'token_url=%s\n' "$ep" >> "$tmp/env.$e"
    else
      echo "NOTE: $e: the token URL of its provider could not be read from here: fill « Token URL » of $e in http-client.env.json, or /tests env config $e writes it in AGENTS.md" >> "$tmp/notes"
    fi
  fi
done < "$tmp/envs"
jesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# The JSON object of one environment in http-client.env.json: baseUrl, the route values, and Rider's token
env_json() {
  name=$1 url=$2 params=$3 file=$4
  printf '  "%s": {\n    "baseUrl": "%s"' "$(jesc "$name")" "$(jesc "$url")"
  printf '%s\n' "$params" | while IFS= read -r p; do [ -n "$p" ] && printf ',\n    "%s": "1"' "$p"; done
  if [ "$client" = rider ]; then
    auth=none
    [ -n "$file" ] && auth=$(sed -n 's/^auth=//p' "$file")
    if [ "$auth" = oidc ]; then
      tu=$(sed -n 's/^token_url=//p' "$file" | head -n 1)
      [ -n "$tu" ] || tu='{{tokenUrl}}'
      cl=$(sed -n 's/^client=//p' "$file")
      [ -n "$cl" ] || cl="{{clientId}}"
      sc=$(sed -n 's/^scope=//p' "$file")
      au=$(sed -n 's/^audience=//p' "$file")
      rs=$(sed -n 's/^resource=//p' "$file")
      how=$(sed -n 's/^client_auth=//p' "$file")
      printf ',\n    "Security": {\n      "Auth": {\n        "api": {\n          "Type": "OAuth2",\n          "Grant Type": "Client Credentials",\n'
      printf '          "Token URL": "%s",\n          "Client ID": "%s",\n          "Client Secret": "{{clientSecret}}",\n' "$(jesc "$tu")" "$(jesc "$cl")"
      printf '          "Client Credentials": "%s"' "$([ "$how" = basic ] && echo basic || echo "in body")"
      [ -n "$sc" ] && printf ',\n          "Scope": "%s"' "$(jesc "$sc")"
      if [ -n "$au" ] || [ -n "$rs" ]; then
        printf ',\n          "Custom Request Parameters": {'
        sep=""
        [ -n "$au" ] && { printf '\n            "audience": { "Value": "%s", "Use": "In Token Request" }' "$(jesc "$au")"; sep=","; }
        [ -n "$rs" ] && printf '%s\n            "resource": { "Value": "%s", "Use": "In Token Request" }' "$sep" "$(jesc "$rs")"
        printf '\n          }'
      fi
      printf '\n        }\n      }\n    }'
    else
      printf ',\n    "Security": {\n      "Auth": {\n        "api": { "Type": "Mock", "Token": "{{token}}" }\n      }\n    }'
    fi
  fi
  printf '\n  }'
}
# What the private file holds for one environment: "<key>" lines
private_keys() {
  file=$1
  if [ "$client" = vs ] || [ -z "$file" ] || [ "$(sed -n 's/^auth=//p' "$file")" != oidc ]; then echo token; return 0; fi
  [ -n "$(sed -n 's/^client=//p' "$file")" ] || echo clientId
  echo clientSecret
  [ -n "$(sed -n 's/^token_url=//p' "$file" | head -n 1)" ] || echo tokenUrl
}

if [ "$plan" -eq 1 ]; then
  cut -f2 "$tmp/dirs" | sort -u | while IFS= read -r pdir; do
    out="$pdir/http"; [ "$pdir" = . ] && out=http
    echo "PLAN: $out (project $pdir)"
    awk -F '\t' -v dirs="$tmp/dirs" -v pdir="$pdir" 'BEGIN { while ((getline l < dirs) > 0) { split(l, a, "\t"); d[a[1]] = a[2] } } d[$2] == pdir' "$tmp/endpoints" |
      cut -f1,2 | sort | uniq -c | while read -r n g s; do
        printf '  GROUP: %s — %s request(s) (%s)%s\n' "$g" "$n" "$s" "$([ -f "$out/$g.http" ] && echo " — exists: $out/$g.http ($([ "$replace" -eq 1 ] && echo replaced || echo kept unless --replace))")"
      done
    lu=""
    [ -f "$pdir/Properties/launchSettings.json" ] && lu=$(sed -n 's/.*"applicationUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pdir/Properties/launchSettings.json" | tr ';' '\n' | grep '^https://' | head -n 1)
    [ -n "$lu" ] && echo "  ENVIRONMENT: local $lu — a token to paste in http-client.private.env.json"
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      u=$(sed -n 's/^url=//p' "$tmp/env.$e")
      if [ "$(sed -n 's/^auth=//p' "$tmp/env.$e")" = oidc ]; then
        tu=$(sed -n 's/^token_url=//p' "$tmp/env.$e" | head -n 1)
        echo "  ENVIRONMENT: $e $u — OpenID Connect: Rider asks the token itself (OAuth 2.0 client credentials, token URL ${tu:-to fill in}), client secret in http-client.private.env.json; Visual Studio: a token to paste"
      else
        echo "  ENVIRONMENT: $e $u — a token to paste in http-client.private.env.json"
      fi
    done < "$tmp/envs"
    [ -s "$tmp/prod" ] && echo "  LEFT OUT: $(tr '\n' ' ' < "$tmp/prod" | sed 's/ $//') (production: never in the HTTP files)"
    [ -f "$out/http-client.env.json" ] && echo "  FILE: $out/http-client.env.json exists ($([ "$replace" -eq 1 ] && echo replaced || echo kept unless --replace))"
    [ -f "$out/http-client.private.env.json" ] && echo "  FILE: $out/http-client.private.env.json exists (never rewritten: your secrets are there)"
  done
  cat "$tmp/notes"
  echo "GROUPS: $(cut -f1 "$tmp/all" | sort -u | tr '\n' ',' | sed 's/,$//')"
  exit 0
fi

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
  # the endpoints of this project (all of them for the route values), and the parameters of their routes
  awk -F '\t' -v dirs="$tmp/dirs" -v pdir="$pdir" 'BEGIN { while ((getline l < dirs) > 0) { split(l, a, "\t"); d[a[1]] = a[2] } } d[$2] == pdir' \
    "$tmp/endpoints" > "$tmp/mine"
  # (the route values of every endpoint of the project, not only of the groups chosen: http-client.env.json serves all)
  params=$(awk -F '\t' -v pdir="$pdir" -v here="$root" '{ print }' "$tmp/all" | while IFS="$(printf '\t')" read -r _ src _ route _; do
    [ "$(project_dir "$src")" = "$pdir" ] && printf '%s\n' "$route"
  done | grep -o '{[^}]*}' | sed 's/^{\**//; s/[:=?}].*//' | sort -u)
  # the environment files
  if [ -f "$out/http-client.env.json" ] && [ "$replace" -eq 0 ]; then
    echo "KEPT: $out/http-client.env.json (exists)"
  else
    {
      echo "{"
      first=1
      { [ -n "$local_url" ] && printf 'local\t%s\n' "$local_url"; while IFS= read -r e; do [ -n "$e" ] && printf '%s\t%s\n' "$e" "$(sed -n 's/^url=//p' "$tmp/env.$e")"; done < "$tmp/envs"; } |
        while IFS="$(printf '\t')" read -r name url; do
          [ "$first" -eq 1 ] || echo ","
          first=0
          f=""
          [ "$name" != local ] && [ -f "$tmp/env.$name" ] && f="$tmp/env.$name"
          env_json "$name" "$url" "$params" "$f"
        done
      printf '\n}\n'
    } > "$out/http-client.env.json"
    echo "ENVIRONMENTS: $( { [ -n "$local_url" ] && echo local; cat "$tmp/envs"; } | tr '\n' ' ' | sed 's/ $//') in $out/http-client.env.json$( [ -s "$tmp/prod" ] && printf ' (production left out: %s)' "$(tr '\n' ' ' < "$tmp/prod" | sed 's/ $//')")"
  fi
  private="$out/http-client.private.env.json"
  if [ ! -f "$private" ]; then
    {
      echo "{"
      first=1
      { [ -n "$local_url" ] && echo local; cat "$tmp/envs"; } | while IFS= read -r name; do
        [ -n "$name" ] || continue
        [ "$first" -eq 1 ] || echo ","
        first=0
        f=""
        [ "$name" != local ] && f="$tmp/env.$name"
        printf '  "%s": {' "$(jesc "$name")"
        sep=""
        for k in $(private_keys "$f"); do printf '%s\n    "%s": ""' "$sep" "$k"; sep=","; done
        printf '\n  }'
      done
      printf '\n}\n'
    } > "$private"
    echo "PRIVATE: $private written, empty: $( { [ -n "$local_url" ] && echo local; cat "$tmp/envs"; } | while IFS= read -r name; do [ -n "$name" ] || continue; f=""; [ "$name" != local ] && f="$tmp/env.$name"; printf '%s (%s) ' "$name" "$(private_keys "$f" | tr '\n' ',' | sed 's/,$//')"; done | sed 's/ $//')"
  else
    echo "PRIVATE: $private exists, never rewritten; each environment needs there: $( { [ -n "$local_url" ] && echo local; cat "$tmp/envs"; } | while IFS= read -r name; do [ -n "$name" ] || continue; f=""; [ "$name" != local ] && f="$tmp/env.$name"; printf '%s (%s) ' "$name" "$(private_keys "$f" | tr '\n' ',' | sed 's/,$//')"; done | sed 's/ $//')"
  fi
  if ! git check-ignore -q "$private"; then
    [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ] && echo >> .gitignore
    printf '%s\n' "$private" >> .gitignore
    echo "IGNORED: $private added to .gitignore (the tokens are never committed)"
  fi
  # one file per group
  cut -f1 "$tmp/mine" | sort -u | while IFS= read -r group; do
    file="$out/$group.http"
    if [ -f "$file" ] && [ "$replace" -eq 0 ]; then
      echo "KEPT: $file (exists)"
      continue
    fi
    awk -F '\t' -v group="$group" -v file="$file" -v bearer="$([ "$client" = vs ] && echo '{{token}}' || echo '{{$auth.token("api")}}')" '
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
          print "# values in http-client.env.json and what http-client.private.env.json asks (never committed)."
          print ""
        }
        print "### " title
        print "# " verb " " route " - " $5 " (" $2 ")"
        if (body != "") print "# body: " body ", to fill in"
        print verb " {{baseUrl}}" path
        print "Accept: application/json"
        if ($6 != "-" && $6 !~ /anonymous/) print "Authorization: Bearer " bearer
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
      END { print n "\t" bodies > (file ".count") }' "$tmp/mine" > "$file.new" 2>> "$tmp/left"
    count=$(cut -f1 "$file.count")
    b=$(cut -f2 "$file.count")
    rm -f "$file.count"
    if [ "${count:-0}" -gt 0 ]; then mv "$file.new" "$file"; else rm -f "$file.new"; continue; fi
    echo "HTTP: $file ($count requests${b:+, $b with a body to fill in})" | sed 's/, 0 with a body to fill in//; s/, with a body to fill in//'
  done
done
cat "$tmp/notes"
sort -u "$tmp/left" 2>/dev/null
exit 0
