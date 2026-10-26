#!/bin/sh
# For /outil http: the requests of the HTTP endpoints of the repository, for the HTTP client of Rider (JetBrains) and
# of Visual Studio, written from the code (api-routes.sh), in <API project folder>/http/:
#   - one <Controller>.http per controller and one <File>.http per file of minimal APIs: each request with its verb and
#     route (route parameters as {{name}}), its token when the endpoint needs authentication, an empty JSON body to
#     fill in when it takes one (its type in the comment above it), and for Rider a check of its success status (a
#     response handler of the JetBrains HTTP client; Visual Studio runs none, its requests have none);
#   - http-client.env.json: `local` (the https URL of Properties/launchSettings.json) and each environment of AGENTS.md
#     « ## Environnements » (environments.sh) but production ones, with baseUrl and a value for each route parameter.
#     For Rider (the default), the token of each environment is Rider's own: an environment with OpenID Connect gets the
#     OAuth 2.0 client credentials of the HTTP client (its token URL, client id, scope, how the client authenticates:
#     Rider asks the token and renews it), the others a token to paste (Type Mock); every request says
#     `Authorization: Bearer {{$auth.token("api")}}`. For Visual Studio (--client vs): `Authorization: Bearer {{token}}`;
#   - the private file of the HTTP client, what each environment needs and nobody commits (the client secret, a token,
#     the client id when AGENTS.md keeps it in a variable): http-client.private.env.json for Rider,
#     http-client.env.json.user for Visual Studio (the only file it reads for that; it runs no response handler, so its
#     requests have none); empty, for the developer to fill in; never committed (its path is added to .gitignore when
#     git does not ignore it yet), never rewritten once it exists (the missing keys are named), never read by an agent.
# A file that exists is kept (its requests may have been edited), unless --replace: the .http files of the groups
# chosen and http-client.env.json are written again, never the private file.
# --private fills the empty values of the private files that exist (Rider's and Visual Studio's) from where AGENTS.md
# says each secret is: a variable of this machine (~/.zshenv) or HashiCorp Vault (vault:<path>#<field>, read by the
# vault CLI: secrets.sh); the client id from its variable, the token URL from AGENTS.md. A value already there is never
# replaced; nothing is ever printed but the names of what was filled. The developer's choice, in the conversation.
# Usage: http-files.sh [--plan] [--only <group>[,<group>...]] [--replace] [--client rider|vs] [<folder>]
#        http-files.sh --private [<folder>]
#   --plan     what would be written, nothing written: "PLAN:", "GROUP:", "ENVIRONMENT:", "FILE:" lines
# Output: "HTTP: <file> (<n> requests, <b> with a body to fill in)", "KEPT: <file> (exists)", "ENVIRONMENTS: <names>",
# "IGNORED: <path added to .gitignore>", "PRIVATE: <what to fill in>", "NOTE:", "LEFT OUT: <endpoint>: <why>"; "STOP:"
# when there is no endpoint. --private: "FILLED: <file>: <environment> <key> (from <where>)", "EMPTY: <file>: <environment>
# <key>: <why>", "UNCHANGED: <file>" when it had nothing empty to fill.

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=secrets.sh
. "$here/secrets.sh"
plan=0 only="" replace=0 client=rider folder="" fill=0
while [ $# -gt 0 ]; do
  case "$1" in
    --plan) plan=1; shift ;;
    --private) fill=1; shift ;;
    --only) only=$2; shift 2 ;;
    --replace) replace=1; shift ;;
    --client) client=$2; shift 2 ;;
    -*) echo "STOP: unknown option $1 (http-files.sh [--plan] [--only <groups>] [--replace] [--client rider|vs] [<folder>] | --private [<folder>])"; exit 1 ;;
    *) folder=$1; shift ;;
  esac
done
case "$client" in rider|vs) ;; *) echo "STOP: --client rider or vs"; exit 1 ;; esac
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/http-files.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------- --private: the empty values of the private files, from the variables of this machine and from Vault ----------
if [ "$fill" -eq 1 ]; then
  find "${folder:-.}" \( -name node_modules -o -name bin -o -name obj -o -name .git \) -prune -o -type f \
    \( -name http-client.private.env.json -o -name http-client.env.json.user \) -print 2>/dev/null | sed 's#^\./##' | sort > "$tmp/privates"
  if [ ! -s "$tmp/privates" ]; then
    echo "STOP: no private file of an HTTP client${folder:+ in $folder} (http-client.private.env.json for Rider, http-client.env.json.user for Visual Studio): /outil http writes it first"
    exit 1
  fi
  # the values go through a file of this run only (never on a command line), escaped for JSON
  umask 077
  jval() { printf '%s' "$1" | awk 'BEGIN { RS = "\001" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, "\\r"); gsub(/\n/, "\\n"); printf "%s", $0 }'; }
  while IFS= read -r pf; do
    # the environments and the keys of the file: '  "<env>": {' then '    "<key>": "<value>"'
    awk '/^  "[^"]+": *\{/ { e = $0; sub(/^  "/, "", e); sub(/".*/, "", e); next }
         /^    "[^"]+": *""/ && e != "" { k = $0; sub(/^    "/, "", k); sub(/".*/, "", k); print e "\t" k }' "$pf" > "$tmp/empty"
    : > "$tmp/values"
    : > "$tmp/report"
    while IFS="$(printf '\t')" read -r e k; do
      [ -n "$e" ] || continue
      if [ "$e" = local ]; then
        printf 'EMPTY: %s: local %s: a token of the API on this machine, to paste (its local identity provider, or a token of a test user)\n' "$pf" "$k" >> "$tmp/report"
        continue
      fi
      sh "$here/environments.sh" --details "$e" > "$tmp/details" 2>/dev/null || { printf 'EMPTY: %s: %s %s: no environment %s in AGENTS.md\n' "$pf" "$e" "$k" "$e" >> "$tmp/report"; continue; }
      d() { sed -n "s/^$1=//p" "$tmp/details" | head -n 1; }
      ref="" what=""
      case "$k" in
        clientSecret) ref=$(d secret_var); what="its client secret" ;;
        clientId)
          cv=$(d client_var)
          if [ -n "$cv" ]; then ref=$cv; what="its client id"
          else v=$(d client); [ -n "$v" ] && { printf '%s\t%s\t%s\n' "$e" "$k" "$(jval "$v")" >> "$tmp/values"; printf 'FILLED: %s: %s clientId (from AGENTS.md)\n' "$pf" "$e" >> "$tmp/report"; }; continue
          fi ;;
        tokenUrl)
          v=$(d token_url)
          [ -n "$v" ] || v=$(sh "$here/env-tests.sh" --discover "$e" 2>/dev/null | sed -n 's/^TOKEN ENDPOINT: //p' | head -n 1)
          if [ -n "$v" ]; then
            printf '%s\t%s\t%s\n' "$e" "$k" "$(jval "$v")" >> "$tmp/values"; printf 'FILLED: %s: %s tokenUrl (from AGENTS.md and its provider)\n' "$pf" "$e" >> "$tmp/report"
          else
            printf 'EMPTY: %s: %s tokenUrl: its provider does not answer from here: /tests env config %s writes it in AGENTS.md\n' "$pf" "$e" "$e" >> "$tmp/report"
          fi
          continue ;;
        token)
          if [ "$(d auth)" = token ]; then ref=$(d token_var); what="its token"
          elif [ "$(d auth)" = oidc ]; then
            printf 'EMPTY: %s: %s token: %s asks a token to its OpenID Connect provider; Visual Studio cannot: paste a fresh one (Rider asks it itself)\n' "$pf" "$e" "$e" >> "$tmp/report"; continue
          else
            printf 'EMPTY: %s: %s token: AGENTS.md gives no token for %s (an API without one: leave it empty)\n' "$pf" "$e" "$e" >> "$tmp/report"; continue
          fi ;;
        *) printf 'EMPTY: %s: %s %s: a key of yours, left as it is\n' "$pf" "$e" "$k" >> "$tmp/report"; continue ;;
      esac
      if [ -z "$ref" ]; then
        printf 'EMPTY: %s: %s %s: AGENTS.md does not say where %s is (/tests env config %s)\n' "$pf" "$e" "$k" "$what" "$e" >> "$tmp/report"
        continue
      fi
      value=""
      if [ "$k" = clientId ]; then value=$(printenv "$ref" 2>/dev/null); [ -n "$value" ] || secret_why="the variable $ref is not set in the environment of OpenCode"
      else secret_get "$ref" value || :; fi
      if [ -n "$value" ]; then
        printf '%s\t%s\t%s\n' "$e" "$k" "$(jval "$value")" >> "$tmp/values"
        printf 'FILLED: %s: %s %s (from %s)\n' "$pf" "$e" "$k" "$(secret_where "$ref")" >> "$tmp/report"
      else
        # shellcheck disable=SC2154 # secret_why: set by secret_get (secrets.sh)
        printf 'EMPTY: %s: %s %s: %s\n' "$pf" "$e" "$k" "$secret_why" >> "$tmp/report"
      fi
      value=""
    done < "$tmp/empty"
    if [ -s "$tmp/values" ]; then
      # the empty values replaced, the rest of the file as it is (its other keys, those already filled)
      awk -v values="$tmp/values" '
        BEGIN { while ((getline l < values) > 0) { i = index(l, "\t"); e = substr(l, 1, i - 1); r = substr(l, i + 1); j = index(r, "\t"); v[e SUBSEP substr(r, 1, j - 1)] = substr(r, j + 1) } }
        /^  "[^"]+": *\{/ { env = $0; sub(/^  "/, "", env); sub(/".*/, "", env) }
        /^    "[^"]+": *""/ { k = $0; sub(/^    "/, "", k); sub(/".*/, "", k); if ((env SUBSEP k) in v) { sub(/""/, "\"" v[env SUBSEP k] "\""); } }
        { print }' "$pf" > "$tmp/filled" && cat "$tmp/filled" > "$pf"
      : > "$tmp/filled"
      : > "$tmp/values"
    fi
    if [ -s "$tmp/report" ]; then cat "$tmp/report"; else echo "UNCHANGED: $pf (nothing empty to fill)"; fi
    if ! git check-ignore -q "$pf"; then
      [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ] && echo >> .gitignore
      printf '%s\n' "$pf" >> .gitignore
      echo "IGNORED: $pf added to .gitignore (its secrets are never committed)"
    fi
  done < "$tmp/privates"
  exit 0
fi

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
    [ -n "$lu" ] && echo "  ENVIRONMENT: local $lu — a token to paste in the private file (Rider: http-client.private.env.json, Visual Studio: http-client.env.json.user)"
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      u=$(sed -n 's/^url=//p' "$tmp/env.$e")
      if [ "$(sed -n 's/^auth=//p' "$tmp/env.$e")" = oidc ]; then
        tu=$(sed -n 's/^token_url=//p' "$tmp/env.$e" | head -n 1)
        echo "  ENVIRONMENT: $e $u — OpenID Connect: Rider asks the token itself (OAuth 2.0 client credentials, token URL ${tu:-to fill in}), client secret in http-client.private.env.json ($(secret_where "$(sed -n 's/^secret_var=//p' "$tmp/env.$e")"): --private fills it); Visual Studio: a token to paste in http-client.env.json.user"
      else
        tv=$(sed -n 's/^token_var=//p' "$tmp/env.$e")
        echo "  ENVIRONMENT: $e $u — $([ -n "$tv" ] && echo "its token in the private file ($(secret_where "$tv"): --private fills it)" || echo "a token to paste in the private file")"
      fi
    done < "$tmp/envs"
    [ -s "$tmp/prod" ] && echo "  LEFT OUT: $(tr '\n' ' ' < "$tmp/prod" | sed 's/ $//') (production: never in the HTTP files)"
    [ -f "$out/http-client.env.json" ] && echo "  FILE: $out/http-client.env.json exists ($([ "$replace" -eq 1 ] && echo replaced || echo kept unless --replace))"
    [ -f "$out/http-client.private.env.json" ] && echo "  FILE: $out/http-client.private.env.json exists (never rewritten: your secrets are there)"
    [ -f "$out/http-client.env.json.user" ] && echo "  FILE: $out/http-client.env.json.user exists (never rewritten: your secrets are there)"
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
  # Rider reads its secrets in http-client.private.env.json, Visual Studio in http-client.env.json.user
  private="$out/http-client.private.env.json"
  [ "$client" = vs ] && private="$out/http-client.env.json.user"
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
    awk -F '\t' -v group="$group" -v file="$file" -v vs="$([ "$client" = vs ] && echo 1 || echo 0)" -v bearer="$([ "$client" = vs ] && echo '{{token}}' || echo '{{$auth.token("api")}}')" '
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
          print "# values in http-client.env.json and what " (vs ? "http-client.env.json.user" : "http-client.private.env.json") " asks (never committed)."
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
        # the check of its status: a response handler of the JetBrains HTTP client (Visual Studio runs none)
        if (!vs) {
          print "> {%"
          print "    client.test(\"" verb " " route "\", function () {"
          if (code != "") print "        client.assert(response.status === " code ", \"status \" + response.status);"
          else print "        client.assert(response.status >= 200 && response.status < 300, \"status \" + response.status);"
          print "    });"
          print "%}"
          print ""
        }
        if (body != "") bodies++
      }
      END { print n "\t" bodies > (file ".count") }' "$tmp/mine" > "$file.new" 2>> "$tmp/left"
    count=$(cut -f1 "$file.count")
    b=$(cut -f2 "$file.count")
    rm -f "$file.count"
    if [ "${count:-0}" -gt 0 ]; then mv "$file.new" "$file"; else rm -f "$file.new"; continue; fi
    echo "HTTP: $file ($count request$([ "$count" -gt 1 ] && echo s)${b:+, $b with a body to fill in})" | sed 's/, 0 with a body to fill in//; s/, with a body to fill in//'
  done
done
cat "$tmp/notes"
sort -u "$tmp/left" 2>/dev/null
exit 0
