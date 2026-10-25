#!/bin/sh
# For /tests env config (the wizard of the environments): what the repository and this machine already say of its
# environments, then the block of one environment written in AGENTS.md « ## Environnements » (environments.sh reads it),
# never a secret: only the names of the variables of this machine that hold them, by convention from the name of the
# environment (recette: RECETTE_CLIENT_ID, RECETTE_CLIENT_SECRET, RECETTE_PROXY_CREDENTIALS, API_TOKEN_RECETTE), set by
# the developer in ~/.zshenv. The other lines of AGENTS.md, and the other environments, are kept as they are.
#   scan                 the environments declared (and whether their variables are set), the hints of the code for a new
#                        one (URLs of the deploy jobs of .gitlab-ci.yml, the authority and the audience the API checks in
#                        its appsettings files: those keys only, never another value), the proxy of this machine (its
#                        credentials masked), and the names of the variables of each environment
#   set <name> --url <url> [--oidc <authority> | --token-url <url>] [--client <id> | --client-var]
#       [--scope <scopes>] [--audience <aud>] [--resource <res>] [--auth-client post|basic] [--token-var]
#       [--proxy system|none|<url>] [--proxy-auth] [--no-proxy <hosts>] [--ca <PEM file>] [--health <path>]
#       [--writes] [--production] [--role <text>]
#                        writes (or replaces) the block of <name>: OpenID Connect by client credentials (--oidc or
#                        --token-url: its client id as a value or, --client-var, in <NAME>_CLIENT_ID; its secret always
#                        in <NAME>_CLIENT_SECRET), or a fixed token (--token-var: API_TOKEN_<NAME>), or none; the proxy
#                        (--proxy-auth: <NAME>_PROXY_CREDENTIALS holds <user>:<password>), the certificate authorities,
#                        the path that tells the API is up, writes allowed, production (never tested: its line only).
#                        With --oidc, the token endpoint of its discovery document is written too (token-url), when the
#                        provider answers from here (http-files.sh needs it for Rider)
#   remove <name>        takes the block of <name> out
# Output: "DECLARED:", "HINT …:", "PROXY OF THIS MACHINE:", "VARIABLES OF <name>:" (scan); "WRITTEN:" and the block,
# "TOKEN URL:", "VARIABLES:" and the export lines to put in ~/.zshenv, "NEXT:" (set); "REMOVED:"; "STOP:" when an
# argument is not valid (nothing is written then).
# Usage: env-setup.sh scan | set <name> --url <url> [<options>] | remove <name>

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
agents=AGENTS.md

# NAME of the variables of an environment: recette -> RECETTE, pre-prod -> PRE_PROD
prefix() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g; s/^\([0-9]\)/E\1/'; }
isset() { [ -n "$(printenv "$1" 2>/dev/null)" ] && echo set || echo "not set"; }
masked() { printf '%s' "$1" | sed -E 's#://[^/@]*@#://***@#'; }

case "$1" in
  scan)
    sh "$here/environments.sh" | while IFS= read -r l; do
      case "$l" in
        WARNING:*) printf '%s\n' "$l"; continue ;;
      esac
      n=$(printf '%s' "$l" | cut -f1)
      sh "$here/environments.sh" --details "$n" | awk -F= -v n="$n" '
        /^WARNING:/ { next }
        { k = $1; sub(/^[^=]*=/, ""); v[k] = $0 }
        END {
          s = "DECLARED: " n " " v["url"]
          if (v["production"] == "yes") { print s " — production (never tested)"; exit }
          if (v["auth"] == "oidc") s = s " — OpenID Connect (" (v["authority"] != "" ? "authority " v["authority"] : "token-url " v["token_url"]) ", client " (v["client_var"] != "" ? "`" v["client_var"] "`" : v["client"]) ", secret `" v["secret_var"] "`" (v["scope"] != "" ? ", scope " v["scope"] : "") ")"
          else if (v["auth"] == "token") s = s " — fixed token `" v["token_var"] "`"
          else s = s " — no token"
          s = s ", proxy " v["proxy"] (v["proxy_credentials_var"] != "" ? " (credentials `" v["proxy_credentials_var"] "`)" : "")
          if (v["ca"] != "") s = s ", certificate " v["ca"]
          s = s (v["writes"] == "yes" ? ", writes allowed" : ", read only")
          print s
          vars = v["client_var"] " " v["secret_var"] " " v["token_var"] " " v["proxy_credentials_var"]
          print "VARS " vars
        }' | while IFS= read -r d; do
        case "$d" in
          "VARS "*)
            out=""
            for x in ${d#VARS }; do out="$out${out:+, }$x $(isset "$x")"; done
            [ -n "$out" ] && echo "  variables: $out" ;;
          *) printf '%s\n' "$d" ;;
        esac
      done
    done
    # the URLs of the deploy jobs: environment: name: / url:
    for ci in .gitlab-ci.yml $(git ls-files '.gitlab/ci/*.yml' '.gitlab/*.yml' 'ci/*.yml' 2>/dev/null); do
      [ -f "$ci" ] || continue
      awk -v file="$ci" '
        /^[A-Za-z0-9_.-][^:]*:[ \t]*$/ { job = $0; sub(/:.*/, "", job); inenv = 0; ename = ""; next }
        /^[ \t]+environment:[ \t]*\{/ {
          line = $0; n = ""; u = ""
          if (match(line, /name:[ \t]*[^,}]+/)) { n = substr(line, RSTART + 5, RLENGTH - 5); gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", n) }
          if (match(line, /url:[ \t]*[^,}]+/)) { u = substr(line, RSTART + 4, RLENGTH - 4); gsub(/^[ \t"\047]+|[ \t"\047]+$/, "", u) }
          if (u ~ /^https?:\/\// && u !~ /\$/) print "HINT URL: " (n != "" ? n : job) " " u " (" file ", job " job ")"
          next
        }
        /^[ \t]+environment:[ \t]*$/ { inenv = 1; ename = ""; next }
        inenv && /^[ \t]+name:/ { ename = $0; sub(/^[ \t]+name:[ \t]*/, "", ename); gsub(/["\047]/, "", ename); next }
        inenv && /^[ \t]+url:/ {
          u = $0; sub(/^[ \t]+url:[ \t]*/, "", u); gsub(/["\047]/, "", u)
          if (u ~ /^https?:\/\// && u !~ /\$/) print "HINT URL: " (ename != "" ? ename : job) " " u " (" file ", job " job ")"
          next
        }
        inenv && /^[ \t]*[A-Za-z_]+:/ && !/^[ \t]+(name|url|action|deployment_tier|kubernetes|on_stop|auto_stop_in):/ { inenv = 0 }
      ' "$ci"
    done | sort -u
    # what the API checks in its tokens: these keys of its appsettings files, never another value
    # (each object and each key on its own line first: a compact file reads like a formatted one)
    split_json() {
      awk 'BEGIN { RS = "\001" }
        {
          s = $0; n = length(s); out = ""; instr = 0; arr = 0
          for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (instr) { out = out c; if (c == "\\") { out = out substr(s, i + 1, 1); i++ } else if (c == "\"") instr = 0; continue }
            if (c == "\"") { instr = 1; out = out c; continue }
            if (c == "[") arr++
            if (c == "]") arr--
            if (c == "{" && !arr) { out = out c "\n"; continue }
            if (c == "}" && !arr) { out = out "\n" c; continue }
            if (c == "," && !arr) { out = out c "\n"; continue }
            out = out c
          }
          print out
        }' "$1"
    }
    git ls-files '*appsettings*.json' 2>/dev/null | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' | while IFS= read -r f; do
      split_json "$f" | awk -v file="$f" '
        function keyof(s) { if (match(s, /"[^"]+"[ \t]*:/)) { s = substr(s, RSTART + 1, RLENGTH - 1); sub(/"[ \t]*:$/, "", s); return s } return "" }
        {
          line = $0
          k = keyof(line)
          # an object opens: its name is the section of the keys inside it
          if (k != "" && line ~ /:[ \t]*\{[ \t]*$/) { depth++; sect[depth] = k; next }
          if (line ~ /^[ \t]*\}/) { if (depth > 0) depth--; next }
          if (k == "") next
          if (k !~ /^(Authority|Issuer|ValidIssuer|MetadataAddress|Audience|ValidAudience|ValidAudiences|Instance|TenantId|ClientId)$/) next
          # ClientId: only the identity of the API itself (AzureAd / EntraId / Bearer sections)
          path = ""; for (i = 1; i <= depth; i++) path = path (path == "" ? "" : ":") sect[i]
          if (k == "ClientId" && path !~ /(AzureAd|AzureAD|EntraId|EntraID|Bearer|JwtBearer)/) next
          v = line; sub(/^[^:]*:[ \t]*/, "", v); sub(/,[ \t]*$/, "", v)
          gsub(/[]["]/, "", v); gsub(/[ \t]+/, "", v)
          if (v == "" || v ~ /\$|\{/) next
          if (v !~ /^(https?:\/\/[^ ]+|api:\/\/[^ ]+|[0-9a-fA-F-]{36}|[A-Za-z0-9._,:\/-]+)$/) next
          print "HINT OIDC: " k " " v " (" file (path != "" ? ": " path : "") ")"
        }'
    done
    # Microsoft.Identity.Web: Instance + TenantId give the authority, the audience or the client id the scope
    for f in $(git ls-files '*appsettings*.json' 2>/dev/null | grep -v -i -E '(^|/)[^/]*tests?[^/]*/'); do
      inst=$(sed -n 's/.*"Instance"[[:space:]]*:[[:space:]]*"\(https:[^"]*\)".*/\1/p' "$f" | head -n 1)
      tenant=$(sed -n 's/.*"TenantId"[[:space:]]*:[[:space:]]*"\([0-9A-Za-z.-]*\)".*/\1/p' "$f" | head -n 1)
      [ -n "$inst" ] && [ -n "$tenant" ] && echo "HINT AUTHORITY: ${inst%/}/$tenant/v2.0 (Entra ID, $f)"
    done | sort -u
    git ls-files '*appsettings*.json' 2>/dev/null | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' | while IFS= read -r f; do
      sed -n -E 's/.*"(Audience|ValidAudience)"[[:space:]]*:[[:space:]]*"(api:\/\/[^"]*)".*/\2/p' "$f"
    done | sort -u | sed 's#/*$##; s#$#/.default#; s#^#HINT SCOPE: #; s#$# (Entra ID: the audience of the API followed by /.default)#'
    # the local address of the API (launchSettings.json)
    git ls-files '*launchSettings.json' 2>/dev/null | while IFS= read -r f; do
      u=$(sed -n 's/.*"applicationUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" | tr ';' '\n' | grep '^https://' | head -n 1)
      [ -n "$u" ] && echo "HINT LOCAL: $u ($f: the API on this machine; never an environment)"
    done
    sys=${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-$http_proxy}}}
    if [ -n "$sys" ]; then
      case "$sys" in *://*@*) cred=yes ;; *) cred=no ;; esac
      np=${NO_PROXY:-$no_proxy}
      [ "${#np}" -gt 160 ] && np="$(printf '%s' "$np" | cut -c1-160)…"
      echo "PROXY OF THIS MACHINE: $(masked "$sys") (HTTPS_PROXY; credentials in its URL: $cred)${np:+; NO_PROXY: $np}"
    else
      echo "PROXY OF THIS MACHINE: none (no HTTPS_PROXY in the environment of OpenCode)"
    fi
    sh "$here/environments.sh" | grep -v '^WARNING:' | cut -f1 | while IFS= read -r n; do
      [ -n "$n" ] || continue
      p=$(prefix "$n")
      echo "VARIABLES OF $n: ${p}_CLIENT_ID ($(isset "${p}_CLIENT_ID")), ${p}_CLIENT_SECRET ($(isset "${p}_CLIENT_SECRET")), ${p}_PROXY_CREDENTIALS ($(isset "${p}_PROXY_CREDENTIALS")), API_TOKEN_$p ($(isset "API_TOKEN_$p"))"
    done
    echo "VARIABLES OF A NEW ENVIRONMENT <name>: <NAME>_CLIENT_ID, <NAME>_CLIENT_SECRET, <NAME>_PROXY_CREDENTIALS, API_TOKEN_<NAME> (recette: RECETTE_CLIENT_SECRET)"
    exit 0 ;;

  set|remove)
    action=$1
    name=$2
    [ -n "$name" ] || { echo "STOP: env-setup.sh $action <name> …"; exit 1; }
    case "$name" in
      [A-Za-z0-9]*) ;;
      *) echo "STOP: the name of an environment is letters, digits, . _ or - ($name)"; exit 1 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) echo "STOP: the name of an environment is letters, digits, . _ or - ($name)"; exit 1 ;; esac
    shift 2 ;;
  *)
    echo "STOP: env-setup.sh scan | set <name> --url <url> [<options>] | remove <name>"
    exit 1 ;;
esac

P=$(prefix "$name")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/env-setup.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# The section « ## Environnements » with <block> instead of the block of <name> (or with it added), the rest as it is
# write_block <file of the block, empty to remove>
write_block() {
  if [ ! -f "$agents" ]; then
    [ -s "$1" ] || { echo "STOP: no AGENTS.md: no environment to remove"; exit 1; }
    printf '# %s\n\n## Environnements\n' "$(basename "$root")" > "$agents"
    cat "$1" >> "$agents"
    created=1
    return 0
  fi
  awk -v name="$name" -v blockfile="$1" '
    function heading(l,   x) { x = tolower(l); return x ~ /^## +environnements[ \t]*$/ }
    function emit() { if (!done) { while ((getline b < blockfile) > 0) print b; close(blockfile); done = 1 } }
    # the blank lines at the end of a section wait: the block goes before them
    function flushblank() { for (i = 1; i <= blank; i++) print ""; blank = 0 }
    BEGIN { has = 0 }
    {
      lines[NR] = $0
      if (heading($0)) has = 1
    }
    END {
      for (n = 1; n <= NR; n++) {
        l = lines[n]
        if (l ~ /^## /) {
          if (insec) { emit(); flushblank() }
          if (!has && !done && l ~ /^## +Build/) { print "## Environnements"; emit(); print ""; }
          insec = heading(l)
          print l
          skipping = 0
          continue
        }
        if (insec) {
          if (l ~ /^ ?[-*][ \t]/) {
            # the line of an environment: is it the one replaced?
            q = l; skipping = 0
            if (match(q, /`[^`]*`/) && substr(q, RSTART + 1, RLENGTH - 2) == name) { skipping = 1; emit(); continue }
            flushblank(); print l; continue
          }
          if (skipping && l ~ /^([ \t][ \t]+|\t)[-*][ \t]/) continue
          if (l ~ /^[ \t]*$/) { blank++; continue }
          skipping = 0
          flushblank(); print l; continue
        }
        print l
      }
      if (insec) { emit(); flushblank() }
      if (!has && !done) { print ""; print "## Environnements"; emit() }
    }' "$agents" > "$tmp/agents.md" && cat "$tmp/agents.md" > "$agents"
}

if [ "$action" = remove ]; then
  sh "$here/environments.sh" --details "$name" > /dev/null 2>&1 || { echo "STOP: no environment $name in AGENTS.md"; exit 1; }
  : > "$tmp/block"
  write_block "$tmp/block"
  echo "REMOVED: $name from AGENTS.md « ## Environnements » (its variables stay in ~/.zshenv: remove them there if no other repository uses them)"
  exit 0
fi

# ---------- set ----------
url="" authority="" tokenurl="" client="" clientvar=0 scope="" audience="" resource="" clientauth="" tokenvar=0
proxy=system proxyauth=0 noproxy="" ca="" health="" writes=0 production=0 role=""
need() { [ -n "$2" ] || { echo "STOP: $1 needs a value"; exit 1; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --url) need "$1" "$2"; url=$2; shift 2 ;;
    --oidc|--authority) need "$1" "$2"; authority=$2; shift 2 ;;
    --token-url) need "$1" "$2"; tokenurl=$2; shift 2 ;;
    --client) need "$1" "$2"; client=$2; shift 2 ;;
    --client-var) clientvar=1; shift ;;
    --scope) need "$1" "$2"; scope=$2; shift 2 ;;
    --audience) need "$1" "$2"; audience=$2; shift 2 ;;
    --resource) need "$1" "$2"; resource=$2; shift 2 ;;
    --auth-client) need "$1" "$2"; clientauth=$2; shift 2 ;;
    --token-var) tokenvar=1; shift ;;
    --proxy) need "$1" "$2"; proxy=$2; shift 2 ;;
    --proxy-auth) proxyauth=1; shift ;;
    --no-proxy) need "$1" "$2"; noproxy=$2; shift 2 ;;
    --ca) need "$1" "$2"; ca=$2; shift 2 ;;
    --health) need "$1" "$2"; health=$2; shift 2 ;;
    --writes) writes=1; shift ;;
    --production) production=1; shift ;;
    --role) need "$1" "$2"; role=$2; shift 2 ;;
    *) echo "STOP: unknown option $1"; exit 1 ;;
  esac
done
httpurl() { printf '%s' "$1" | grep -q -E '^https?://[^[:space:]`@]+$'; }
[ -n "$url" ] || { echo "STOP: --url <the base URL of the API on $name>"; exit 1; }
httpurl "$url" || { echo "STOP: --url is an http(s) URL without user or password: $url"; exit 1; }
url=$(printf '%s' "$url" | sed 's#/*$##')
if [ "$production" -eq 1 ]; then
  [ "$writes" -eq 0 ] || { echo "STOP: production never allows writes"; exit 1; }
fi
oidc=0
{ [ -n "$authority" ] || [ -n "$tokenurl" ]; } && oidc=1
[ "$oidc" -eq 1 ] && [ "$tokenvar" -eq 1 ] && { echo "STOP: OpenID Connect (--oidc, --token-url) or a fixed token (--token-var), not both"; exit 1; }
[ -n "$authority" ] && { httpurl "$authority" || { echo "STOP: --oidc is the http(s) URL of the authority: $authority"; exit 1; }; authority=$(printf '%s' "$authority" | sed 's#/*$##'); }
[ -n "$tokenurl" ] && { httpurl "$tokenurl" || { echo "STOP: --token-url is the http(s) URL of the token endpoint: $tokenurl"; exit 1; }; }
if [ "$oidc" -eq 1 ]; then
  [ -n "$client" ] || [ "$clientvar" -eq 1 ] || { echo "STOP: OpenID Connect needs the client id: --client <id>, or --client-var ($P""_CLIENT_ID)"; exit 1; }
  [ -z "$client" ] || printf '%s' "$client" | grep -q -E '^[A-Za-z0-9._:/@-]+$' || { echo "STOP: --client: a client id is letters, digits and . _ : / @ - ($client)"; exit 1; }
  case "$clientauth" in ""|post|basic) ;; *) echo "STOP: --auth-client is post or basic"; exit 1 ;; esac
else
  { [ -n "$client" ] || [ "$clientvar" -eq 1 ] || [ -n "$scope" ] || [ -n "$audience" ] || [ -n "$resource" ] || [ -n "$clientauth" ]; } &&
    { echo "STOP: --client, --scope, --audience, --resource and --auth-client go with --oidc or --token-url"; exit 1; }
fi
for t in "$scope" "$audience" "$resource"; do
  case "$t" in *'`'*|*'
'*) echo "STOP: a backquote or a new line in a setting"; exit 1 ;; esac
done
case "$proxy" in
  system|système|systeme) proxy=system ;;
  none|aucun|direct) proxy=none ;;
  *) httpurl "$proxy" || { echo "STOP: --proxy is system, none, or http(s)://<host>:<port> without user or password (--proxy-auth for its credentials): $proxy"; exit 1; }
     proxy=$(printf '%s' "$proxy" | sed 's#/*$##') ;;
esac
[ "$proxyauth" -eq 1 ] && case "$proxy" in system|none) echo "STOP: --proxy-auth goes with --proxy <its URL> (the credentials of the proxy of this machine are in its HTTPS_PROXY)"; exit 1 ;; esac
[ -z "$noproxy" ] || printf '%s' "$noproxy" | grep -q -E '^[A-Za-z0-9.*:,_ -]+$' || { echo "STOP: --no-proxy: hosts separated by commas ($noproxy)"; exit 1; }
[ -z "$health" ] || printf '%s' "$health" | grep -q -E '^/?[A-Za-z0-9._~/-]*$' || { echo "STOP: --health is a path such as /health ($health)"; exit 1; }
[ -n "$health" ] && case "$health" in /*) ;; *) health="/$health" ;; esac
case "$role" in *'`'*|*'
'*) echo "STOP: a backquote or a new line in --role"; exit 1 ;; esac

# ---------- the block ----------
{
  opts=""
  [ "$writes" -eq 1 ] && opts="écriture permise"
  [ "$production" -eq 1 ] && opts="production"
  [ "$tokenvar" -eq 1 ] && opts="jeton : \`API_TOKEN_$P\`${opts:+, $opts}"
  printf -- '- `%s` : %s%s\n' "$name" "$url" "${opts:+ ($opts)}"
  if [ "$production" -eq 0 ]; then
    if [ "$oidc" -eq 1 ]; then
      [ -n "$authority" ] && printf '  - oidc : %s\n' "$authority"
      [ -n "$tokenurl" ] && printf '  - token-url : %s\n' "$tokenurl"
      if [ "$clientvar" -eq 1 ]; then printf '  - client : `%s_CLIENT_ID`\n' "$P"; else printf '  - client : %s\n' "$client"; fi
      printf '  - secret : `%s_CLIENT_SECRET`\n' "$P"
      [ -n "$scope" ] && printf '  - scope : %s\n' "$scope"
      [ -n "$audience" ] && printf '  - audience : %s\n' "$audience"
      [ -n "$resource" ] && printf '  - resource : %s\n' "$resource"
      [ -n "$clientauth" ] && [ "$clientauth" != post ] && printf '  - auth-client : %s\n' "$clientauth"
    fi
    case "$proxy" in
      system) ;;
      none) printf '  - proxy : aucun\n' ;;
      *) printf '  - proxy : %s\n' "$proxy"; [ "$proxyauth" -eq 1 ] && printf '  - proxy-identifiants : `%s_PROXY_CREDENTIALS`\n' "$P" ;;
    esac
    [ -n "$noproxy" ] && printf '  - sans-proxy : %s\n' "$(printf '%s' "$noproxy" | tr -d ' ')"
    [ -n "$ca" ] && printf '  - certificat : %s\n' "$ca"
    [ -n "$health" ] && printf '  - santé : %s\n' "$health"
  fi
  [ -n "$role" ] && printf '  - rôle : %s\n' "$role"
} > "$tmp/block"
before=new
sh "$here/environments.sh" --details "$name" > /dev/null 2>&1 && before=updated
created=0
write_block "$tmp/block"
# the token endpoint, from the discovery document, when the provider answers from here (Rider needs it: http-files.sh)
found=""
if [ "$oidc" -eq 1 ] && [ -z "$tokenurl" ] && [ "$production" -eq 0 ]; then
  d=$(sh "$here/env-tests.sh" --discover "$name" 2>&1)
  found=$(printf '%s\n' "$d" | sed -n 's/^TOKEN ENDPOINT: //p' | head -n 1)
  if [ -n "$found" ]; then
    awk -v ep="$found" '{ print } /^  - oidc : / && !added { print "  - token-url : " ep; added = 1 }' "$tmp/block" > "$tmp/block2" && mv "$tmp/block2" "$tmp/block"
    write_block "$tmp/block"
  else
    why=$(printf '%s\n' "$d" | grep -E '^(ENVIRONMENT PROBLEM|STOP):' | head -n 1)
  fi
fi
echo "WRITTEN: $agents « ## Environnements » — $name ($before$([ "$created" -eq 1 ] && echo ", AGENTS.md created: /outil setup completes it"))"
sed 's/^/  /' "$tmp/block"
sh "$here/environments.sh" --details "$name" | grep '^WARNING:'
if [ "$oidc" -eq 1 ] && [ -z "$tokenurl" ] && [ "$production" -eq 0 ]; then
  if [ -n "$found" ]; then echo "TOKEN URL: $found (discovery document of the authority)"
  else echo "TOKEN URL: not found from here (${why:-no answer}); env-tests.sh asks the discovery document at each run, and /tests env config $name writes it once the provider answers"
  fi
fi
if [ "$production" -eq 0 ]; then
  vars=""
  [ "$oidc" -eq 1 ] && [ "$clientvar" -eq 1 ] && vars="$vars ${P}_CLIENT_ID"
  [ "$oidc" -eq 1 ] && vars="$vars ${P}_CLIENT_SECRET"
  [ "$tokenvar" -eq 1 ] && vars="$vars API_TOKEN_$P"
  [ "$proxyauth" -eq 1 ] && vars="$vars ${P}_PROXY_CREDENTIALS"
  if [ -n "$vars" ]; then
    s=""
    for v in $vars; do s="$s${s:+, }$v ($(isset "$v"))"; done
    echo "VARIABLES: $s — in ~/.zshenv of this machine, never in AGENTS.md nor in a command (OpenCode reads ~/.zshenv again at each command):"
    for v in $vars; do
      case "$v" in
        *_CLIENT_ID) echo "  export $v='<the client id of $name>'" ;;
        *_CLIENT_SECRET) echo "  export $v='<the client secret of $name>'" ;;
        *_PROXY_CREDENTIALS) echo "  export $v='<user>:<password>'" ;;
        *) echo "  export $v='<the token of $name>'" ;;
      esac
    done
  fi
  echo "NEXT: env-tests.sh --check $name checks the access (variables, proxy, certificate, provider, token, API)"
fi
exit 0
