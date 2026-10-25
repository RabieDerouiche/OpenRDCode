#!/bin/sh
# Runs the environment tests of the repository against one of its environments (AGENTS.md « ## Environnements »,
# environments.sh): the tests marked with the category Environment (xUnit [Trait("Category", "Environment")], NUnit
# [Category("Environment")], MSTest [TestCategory("Environment")]), and those marked EnvironmentWrites with --ecriture,
# where the environment allows it. Never a production environment. Read-only by default: the GET of the API, and what
# the tests themselves undo. Outside this script they are skipped: they need API_BASE_URL.
# The access to the environment, as its settings say (/tests env config writes them):
#   - its token: a fixed one (jeton : `VAR`), or an OpenID Connect token by client credentials (oidc, or token-url;
#     client; secret : `VAR`; scope, audience, resource; auth-client post or basic), asked to the provider just before
#     the tests run (a token lives 5 minutes on a default Keycloak), its discovery document read first;
#   - its proxy: the one of this machine (HTTPS_PROXY, the default), none, or its own URL with its credentials from a
#     variable (proxy-identifiants : `VAR`, <user>:<password>), and the hosts reached without it (sans-proxy);
#   - its certificate authorities (certificat : <PEM file>): added to those of the system for curl and, on Linux, for
#     .NET (SSL_CERT_FILE); on macOS, .NET trusts the keychain only.
# A check of all that comes first, before the build: a variable not set, a proxy that refuses (407, 403), a provider
# that refuses the client (invalid_client, unauthorized_client, invalid_scope), an environment out of reach (name,
# network, VPN, certificate) stop at once with one "ENVIRONMENT PROBLEM:" line, instead of failing every test.
# The tests get, for this run only: API_BASE_URL (its URL), API_TOKEN (the token: fixed, or fresh from the provider),
# API_ENVIRONMENT (its name), API_WRITES (0 or 1), the settings of its provider when it has one (API_OIDC_TOKEN_URL,
# API_OIDC_CLIENT_ID, API_OIDC_CLIENT_SECRET, API_OIDC_SCOPE, API_OIDC_AUDIENCE, API_OIDC_RESOURCE, API_OIDC_CLIENT_AUTH:
# the client of the skill api-tests asks a new token itself when a run outlives it), and its proxy and certificate
# (HTTPS_PROXY, HTTP_PROXY, NO_PROXY, SSL_CERT_FILE). A secret is never printed: the token, the client secret and the
# proxy credentials are masked in every output (***), never on a command line (curl reads them from its standard input).
# Usage: env-tests.sh <environment> [--ecriture] [<test project>] [--filter <VSTest filter>]
#        env-tests.sh --check <environment>      the access only, no test: variables, proxy, certificate, provider,
#                                                token (its claims, never itself), the API with and without the token
#        env-tests.sh --discover <environment>   "TOKEN ENDPOINT: <url>" of its provider (its discovery document)
# Output: "ENVIRONMENT: <name> <url> (read only | writes allowed)" and how it is reached, "PROJECT: <test project>", the
# BUILD and TESTS lines of build-test.sh, then one line per test (VSTest projects: "  OK  <name> (<s> s)" or
# "  FAILED  <name> (<s> s)", the name carrying the endpoint); --check: "CHECK:" lines, then "CHECK: OK". An
# "ENVIRONMENT PROBLEM:" line when the environment, its provider or its proxy cannot be used from this machine, or a
# variable is not set; "STOP:" otherwise. Exit 0 when every test (or every check) passed.
# ENV_TESTS_PREFLIGHT=0 leaves out the call to the API before the build (the pack's own tests, without network).

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
mode=run name="" project="" writes=0 extra=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check; shift ;;
    --discover) mode=discover; shift ;;
    --ecriture|--écriture|--allow-writes) writes=1; shift ;;
    --filter) extra=$2; shift 2 ;;
    -*) echo "STOP: unknown option $1 (env-tests.sh <environment> [--ecriture] [<test project>] [--filter <filter>] | --check <environment> | --discover <environment>)"; exit 1 ;;
    *) if [ -z "$name" ]; then name=$1; else project=$1; fi; shift ;;
  esac
done
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1

all=$(sh "$here/environments.sh")
envs=$(printf '%s\n' "$all" | grep -v '^WARNING:' | grep .)
names=$(printf '%s\n' "$envs" | cut -f1 | tr '\n' ' ' | sed 's/ $//')
if [ -z "$envs" ]; then
  printf '%s\n' "$all" | grep '^WARNING:'
  echo "STOP: no environment declared in AGENTS.md. Add a section « ## Environnements », one line per environment, for example: - \`recette\` : https://api-recette.example.com, then its settings (oidc, client, secret, proxy): /tests env config writes them — COMMANDES.md, « Tests sur un environnement »"
  exit 1
fi
if [ -z "$name" ]; then
  echo "STOP: which environment? env-tests.sh <environment>: $names"
  exit 1
fi
details=$(sh "$here/environments.sh" --details "$name") || { echo "STOP: no environment $name in AGENTS.md (declared: $names)"; exit 1; }
printf '%s\n' "$details" | grep '^WARNING:'
url="" auth="" tokenvar="" authority="" tokenurl="" client="" clientvar="" secretvar="" scope="" audience="" resource=""
clientauth=post proxy=system proxycredvar="" noproxy="" ca="" health="" allow=no prod=no invalid=""
while IFS= read -r l; do
  v=${l#*=}
  case "$l" in
    url=*) url=$v ;;
    auth=*) auth=$v ;;
    token_var=*) tokenvar=$v ;;
    authority=*) authority=$v ;;
    token_url=*) tokenurl=$v ;;
    client=*) client=$v ;;
    client_var=*) clientvar=$v ;;
    secret_var=*) secretvar=$v ;;
    scope=*) scope=$v ;;
    audience=*) audience=$v ;;
    resource=*) resource=$v ;;
    client_auth=*) clientauth=$v ;;
    proxy=*) proxy=$v ;;
    proxy_credentials_var=*) proxycredvar=$v ;;
    no_proxy=*) noproxy=$v ;;
    ca=*) ca=$v ;;
    health=*) health=$v ;;
    writes=*) allow=$v ;;
    production=*) prod=$v ;;
    invalid=*) invalid=$v ;;
  esac
done <<EOF
$details
EOF
if [ "$prod" = yes ]; then
  echo "STOP: $name is a production environment: the pack never runs tests there (a check of production is the CI's, with its own approval)"
  exit 1
fi
if [ "$writes" -eq 1 ] && [ "$allow" != yes ]; then
  echo "STOP: $name does not allow writes (AGENTS.md: « écriture permise » on its line): its read-only tests only, without --ecriture"
  exit 1
fi
if [ -n "$invalid" ]; then
  echo "STOP: the settings of $name in AGENTS.md are not complete or not valid ($invalid: the WARNING lines above say why): /tests env config $name writes them again"
  exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/env-tests.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM HUP

# ---------- what is never printed ----------
# the values to mask (token, client secret, proxy credentials and their encoded forms), one per line of a file of the
# temporary folder of this run (readable by this user only, removed at the end): never in the environment of the tests
masks="$tmp/masks"
: > "$masks"
hide() {
  [ "${#1}" -ge 4 ] || return 0
  printf '%s\n' "$1" >> "$masks"
}
mask() {
  awk -v file="$masks" '
    BEGIN { while ((getline line < file) > 0) if (line != "") t[++n] = line; close(file) }
    { for (k = 1; k <= n; k++) while ((i = index($0, t[k])) > 0) $0 = substr($0, 1, i - 1) "***" substr($0, i + length(t[k])); print }' "$@"
}
# the value of a variable of this machine (printenv: never through the shell of an agent)
var() { printenv "$1" 2>/dev/null; }
missing() {
  echo "ENVIRONMENT PROBLEM: the variable $1, which holds $2 of $name, is not set in the environment of OpenCode. Stop and tell the user in one line: set it in ~/.zshenv (export $1='…'; OpenCode reads ~/.zshenv again at each command: nothing to restart), then /tests env config $name checks the access. Never set it in a command, never read ~/.zshenv."
  exit 1
}
# percent-encoding (a password in the URL of a proxy)
urlenc() {
  printf '%s' "$1" | awk 'BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
    { for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); if (c ~ /[A-Za-z0-9._~-]/) printf "%s", c; else printf "%%%02X", ord[c] } }'
}
# a value inside a curl configuration line, between double quotes
cesc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# ---------- the variables of the token (not for --discover: its document is public) ----------
token="" clientid="" secret=""
[ "$mode" = discover ] || case "$auth" in
  token)
    case "$tokenvar" in *[!A-Za-z0-9_]*|[0-9]*) echo "STOP: the token variable of $name is not a variable name: $tokenvar"; exit 1 ;; esac
    token=$(var "$tokenvar")
    [ -n "$token" ] || missing "$tokenvar" "the token"
    hide "$token" ;;
  oidc)
    if [ -n "$clientvar" ]; then
      clientid=$(var "$clientvar")
      [ -n "$clientid" ] || missing "$clientvar" "the client id"
    else
      clientid=$client
    fi
    secret=$(var "$secretvar")
    [ -n "$secret" ] || missing "$secretvar" "the client secret"
    hide "$secret"
    hide "$(urlenc "$secret")" ;;
esac

# ---------- the proxy and the certificates, for curl and for the tests ----------
proxyshown=""
case "$proxy" in
  system)
    sys=${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-$http_proxy}}}
    if [ -n "$sys" ]; then
      # its credentials, when its URL holds some, are masked like the others
      case "$sys" in
        *://*@*) userinfo=${sys#*://}; userinfo=${userinfo%%@*}; hide "$userinfo"; hide "${userinfo#*:}" ;;
      esac
      proxyshown="proxy of this machine $(printf '%s' "$sys" | sed -E 's#://[^/@]*@#://***@#')"
    else
      proxyshown="no proxy (none on this machine)"
    fi ;;
  none)
    unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy
    proxyshown="no proxy (direct)" ;;
  *)
    full=$proxy
    if [ -n "$proxycredvar" ]; then
      cred=$(var "$proxycredvar")
      [ -n "$cred" ] || missing "$proxycredvar" "the credentials (<user>:<password>) of the proxy"
      case "$cred" in *:*) ;; *) echo "ENVIRONMENT PROBLEM: the variable $proxycredvar does not hold <user>:<password> (the credentials of the proxy of $name). Stop and tell the user in one line; never read it."; exit 1 ;; esac
      puser=$(urlenc "${cred%%:*}") ppass=$(urlenc "${cred#*:}")
      hide "$cred"
      hide "${cred#*:}"
      hide "$ppass"
      # built by the shell itself: the password never reaches the command line of a program
      full="${proxy%%://*}://$puser:$ppass@${proxy#*://}"
      hide "$full"
      proxyshown="proxy $proxy (credentials from $proxycredvar)"
    else
      proxyshown="proxy $proxy"
    fi
    HTTPS_PROXY=$full https_proxy=$full HTTP_PROXY=$full http_proxy=$full
    export HTTPS_PROXY https_proxy HTTP_PROXY http_proxy
    unset ALL_PROXY all_proxy ;;
esac
if [ -n "$noproxy" ]; then
  NO_PROXY=$noproxy no_proxy=$noproxy
  export NO_PROXY no_proxy
  proxyshown="$proxyshown, without it for $noproxy"
fi
cacert="" catext=""
if [ -n "$ca" ]; then
  # shellcheck disable=SC2088 # a literal ~ written in AGENTS.md is expanded on purpose
  case "$ca" in '~/'*) cafile="$HOME/${ca#'~/'}" ;; /*) cafile=$ca ;; *) cafile="$root/$ca" ;; esac
  if [ ! -f "$cafile" ]; then
    echo "ENVIRONMENT PROBLEM: the certificate file of $name ($ca) is not on this machine. Stop and tell the user in one line: put the PEM file of the internal certificate authorities there, or change « certificat » (/tests env config $name)."
    exit 1
  fi
  # added to those of the system, never instead of them (the provider may be public)
  cacert="$tmp/ca-bundle.pem"
  for s in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    [ -f "$s" ] && { cat "$s"; echo; break; }
  done > "$cacert"
  cat "$cafile" >> "$cacert"
  SSL_CERT_FILE=$cacert
  export SSL_CERT_FILE
  catext=", certificate $ca"
fi

if [ "$mode" = check ]; then
  how="tests that write: $([ "$allow" = yes ] && echo allowed || echo "not allowed")"
else
  how=$([ "$writes" -eq 1 ] && echo "writes allowed" || echo "read only")
fi
ENVLINE="ENVIRONMENT: $name $url ($how) — token: $(case "$auth" in oidc) echo "OpenID Connect (client credentials)" ;; token) echo "fixed ($tokenvar)" ;; *) echo none ;; esac); $proxyshown$catext"

# ---------- HTTP with curl ----------
have_curl=0
command -v curl >/dev/null 2>&1 && have_curl=1
need_curl() {
  [ "$have_curl" -eq 1 ] && return 0
  echo "ENVIRONMENT PROBLEM: curl is not on the PATH of OpenCode's shell: it is needed to ask the token of $name to its provider. Stop and tell the user in one line."
  exit 1
}
# req <output file> <curl configuration lines...>: the HTTP status and the status of the proxy's CONNECT, then the
# exit code of curl, in $code $connect $cexit; its errors in $tmp/curl.err
req() {
  rout=$1
  shift
  : > "$rout"
  # the configuration (with a secret, sometimes) goes to curl by a pipe: never on its command line, never on the disk
  w=$( {
    printf '%s\n' "$@"
    printf 'silent\nshow-error\nconnect-timeout = 15\nmax-time = 45\nwrite-out = "%%{http_code} %%{http_connect}"\noutput = "%s"\n' "$(cesc "$rout")"
    [ -n "$cacert" ] && printf 'cacert = "%s"\n' "$(cesc "$cacert")"
    [ "$proxy" = none ] && printf 'noproxy = "*"\n'
  } | curl -K - 2> "$tmp/curl.err")
  cexit=$?
  code=${w%% *} connect=${w#* }
  [ -n "$code" ] || code=000
  [ -n "$connect" ] || connect=000
}
# Why a request to <what> (<where>) did not answer, as an ENVIRONMENT PROBLEM line, or nothing when it did
unreachable() {
  what=$1 where=$2
  # the first sentence of curl's message (its explanation of certificates is long)
  err=$(mask "$tmp/curl.err" | tr '\n' ' ' | sed 's/^curl: ([0-9]*) //; s/ More details here.*//; s/ *$//' | cut -c1-200)
  # the host of the proxy in use, to tell the proxy that does not answer from the environment that does not
  inuse=""
  case "$proxy" in
    system) inuse=${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-$http_proxy}}} ;;
    none) ;;
    *) inuse=$proxy ;;
  esac
  phost=${inuse#*://}; phost=${phost#*@}; phost=${phost%%/*}; phost=${phost%:*}
  # a plain http URL goes through the proxy without CONNECT: its 407 is the status of the answer itself (no server
  # but a proxy answers 407)
  [ "$code" = 407 ] && connect=407
  case "$connect" in
    407) echo "ENVIRONMENT PROBLEM: the proxy refuses the connection to $what ($where) without credentials, or with these (407 Proxy Authentication Required): $proxyshown. Stop and tell the user in one line: proxy-identifiants of $name (/tests env config $name), or the variable that holds them."; return 0 ;;
    403) echo "ENVIRONMENT PROBLEM: the proxy forbids $what ($where) (403 on CONNECT): $proxyshown. Stop and tell the user in one line: the proxy does not let this machine reach it, or « sans-proxy » should name this host."; return 0 ;;
    000|200) ;;
    502|504) echo "ENVIRONMENT PROBLEM: the proxy cannot reach $what ($where) ($connect on CONNECT: a name it does not know, or a host it does not reach from where it is): $proxyshown. Stop and tell the user in one line."; return 0 ;;
    *) echo "ENVIRONMENT PROBLEM: the proxy answers $connect to the connection to $what ($where): $proxyshown. Stop and tell the user in one line."; return 0 ;;
  esac
  case "$cexit" in
    0) return 1 ;;
    5) echo "ENVIRONMENT PROBLEM: the proxy of $name cannot be found from this machine ($proxyshown): $err. Stop and tell the user in one line." ;;
    6) echo "ENVIRONMENT PROBLEM: $what ($where) cannot be reached from this machine: its name is unknown here ($err). Stop and tell the user in one line: VPN, DNS, or a proxy to give in the settings of $name (/tests env config $name); never retry another way." ;;
    7)
      if [ -n "$phost" ] && printf '%s' "$err" | grep -q -F -- "$phost"; then
        echo "ENVIRONMENT PROBLEM: the proxy of $name refuses the connection or does not answer ($proxyshown: $err). Stop and tell the user in one line: the proxy is down, or « proxy » of the settings of $name is wrong (/tests env config $name)."
      else
        echo "ENVIRONMENT PROBLEM: $what ($where) cannot be reached from this machine: the connection is refused or cut ($err). Stop and tell the user in one line: VPN, firewall, or a proxy to give in the settings of $name; never retry another way."
      fi ;;
    28) echo "ENVIRONMENT PROBLEM: $what ($where) did not answer within the time allowed ($err). Stop and tell the user in one line: VPN, proxy, or an environment that is down; never retry another way." ;;
    35|51|53|54|58|59|60|64|66|77|80|82|83|90|91) echo "ENVIRONMENT PROBLEM: the certificate of $what ($where) is not trusted on this machine ($err). Stop and tell the user in one line: « certificat » in the settings of $name names the PEM file of the internal certificate authorities (/tests env config $name); never disable the check." ;;
    56|97) echo "ENVIRONMENT PROBLEM: the connection to $what ($where) failed through the proxy ($err): $proxyshown. Stop and tell the user in one line." ;;
    *) echo "ENVIRONMENT PROBLEM: $what ($where) cannot be reached from this machine (curl $cexit: $err). Stop and tell the user in one line; never retry another way." ;;
  esac
  return 0
}
# An environment that answers, but that is down behind its gateway (502, 503, 504): no test can pass there
down() {
  case "$code" in
    502|503|504) echo "ENVIRONMENT PROBLEM: $name ($url) answers $code on $1: the environment, or the gateway or proxy in front of it, is down. Stop and tell the user in one line: the tests are run once it is up again."; return 0 ;;
  esac
  return 1
}
# jstr <field> <file>: the string value of a field of a JSON object (escapes undone); jnum: a number, quoted or not
jstr() {
  awk -v f="$1" 'BEGIN { RS = "\001" }
    {
      re = "\"" f "\"[ \t\r\n]*:[ \t\r\n]*\"([^\"\\\\]|\\\\.)*\""
      if (match($0, re)) {
        s = substr($0, RSTART, RLENGTH); sub(/^"[^"]*"[ \t\r\n]*:[ \t\r\n]*"/, "", s); sub(/"$/, "", s)
        gsub(/\\\//, "/", s); gsub(/\\"/, "\"", s); gsub(/\\n/, " ", s); gsub(/\\\\/, "\\", s); print s
      }
    }' "$2"
}
jnum() {
  awk -v f="$1" 'BEGIN { RS = "\001" }
    { re = "\"" f "\"[ \t\r\n]*:[ \t\r\n]*\"?[0-9]+"; if (match($0, re)) { s = substr($0, RSTART, RLENGTH); sub(/^"[^"]*"[^0-9]*/, "", s); print s } }' "$2"
}

# ---------- the provider: its token endpoint, then a token by client credentials ----------
endpoint=""
discover() {
  [ -n "$endpoint" ] && return 0
  if [ -n "$tokenurl" ]; then endpoint=$tokenurl; return 0; fi
  need_curl
  wk="$authority/.well-known/openid-configuration"
  req "$tmp/discovery.json" "url = \"$(cesc "$wk")\""
  unreachable "the OpenID Connect provider of $name" "$authority" && exit 1
  case "$code" in
    200) ;;
    404) echo "ENVIRONMENT PROBLEM: the provider of $name has no discovery document at $wk (404): « oidc » is not its authority (Keycloak: https://<host>/realms/<realm>; Entra ID: https://login.microsoftonline.com/<tenant>/v2.0), or give « token-url » (/tests env config $name)."; exit 1 ;;
    *) echo "ENVIRONMENT PROBLEM: the discovery document of the provider of $name answers $code ($wk). Stop and tell the user in one line."; exit 1 ;;
  esac
  endpoint=$(jstr token_endpoint "$tmp/discovery.json")
  if [ -z "$endpoint" ]; then
    echo "ENVIRONMENT PROBLEM: the discovery document of the provider of $name ($wk) gives no token_endpoint. Stop and tell the user in one line: give « token-url » (/tests env config $name)."
    exit 1
  fi
}
expires=""
get_token() {
  need_curl
  discover
  set -- "url = \"$(cesc "$endpoint")\"" 'data-urlencode = "grant_type=client_credentials"'
  if [ "$clientauth" = basic ]; then
    # RFC 6749 2.3.1: the id and the secret are form-encoded, then given as the user and the password
    set -- "$@" "user = \"$(cesc "$(urlenc "$clientid"):$(urlenc "$secret")")\""
  else
    set -- "$@" "data-urlencode = \"client_id=$(cesc "$clientid")\"" "data-urlencode = \"client_secret=$(cesc "$secret")\""
  fi
  [ -n "$scope" ] && set -- "$@" "data-urlencode = \"scope=$(cesc "$scope")\""
  [ -n "$audience" ] && set -- "$@" "data-urlencode = \"audience=$(cesc "$audience")\""
  [ -n "$resource" ] && set -- "$@" "data-urlencode = \"resource=$(cesc "$resource")\""
  req "$tmp/token.json" "$@" 'header = "Accept: application/json"'
  set --
  unreachable "the token endpoint of $name" "$endpoint" && exit 1
  if [ "$code" != 200 ]; then
    e=$(jstr error "$tmp/token.json" | mask)
    d=$(jstr error_description "$tmp/token.json" | mask | cut -c1-300)
    case "$e" in
      invalid_client) echo "ENVIRONMENT PROBLEM: the provider of $name refuses the client ($code invalid_client${d:+: $d}): the client id$([ -n "$clientvar" ] && echo " ($clientvar)") or the secret ($secretvar) is wrong, or the client does not authenticate by « auth-client : $clientauth ». Stop and tell the user in one line." ;;
      unauthorized_client) echo "ENVIRONMENT PROBLEM: the client of $name may not ask a token by client credentials ($code unauthorized_client${d:+: $d}): the provider must allow it for this client (Keycloak: « Service accounts roles » of the client). Stop and tell the user in one line." ;;
      invalid_scope) echo "ENVIRONMENT PROBLEM: the provider of $name refuses the scope « $scope » ($code invalid_scope${d:+: $d}): « scope » of its settings (Entra ID: api://<application>/.default). Stop and tell the user in one line." ;;
      invalid_grant|unsupported_grant_type) echo "ENVIRONMENT PROBLEM: the provider of $name refuses the client credentials grant ($code $e${d:+: $d}). Stop and tell the user in one line." ;;
      ?*) echo "ENVIRONMENT PROBLEM: the provider of $name refuses the token ($code $e${d:+: $d}). Stop and tell the user in one line." ;;
      *) echo "ENVIRONMENT PROBLEM: the token endpoint of $name answers $code without a token ($endpoint). Stop and tell the user in one line." ;;
    esac
    exit 1
  fi
  token=$(jstr access_token "$tmp/token.json")
  if [ -z "$token" ]; then
    echo "ENVIRONMENT PROBLEM: the token endpoint of $name answers 200 without access_token ($endpoint). Stop and tell the user in one line."
    exit 1
  fi
  hide "$token"
  expires=$(jnum expires_in "$tmp/token.json")
  rm -f "$tmp/token.json"
}
# The claims of a JWT that tell what the provider gave (never the token): issuer, audience, client, scopes, roles
claims() {
  printf '%s' "$1" | awk -F. 'NF == 3 { print $2 }' | awk '
    BEGIN { a = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"; for (i = 1; i <= 64; i++) v[substr(a, i, 1)] = i - 1; v["+"] = 62; v["/"] = 63 }
    {
      bits = 0; n = 0; out = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1); if (!(c in v)) continue
        bits = bits * 64 + v[c]; n += 6
        if (n >= 8) { n -= 8; p = 2 ^ n; b = int(bits / p); bits -= b * p; out = out sprintf("%c", b) }
      }
      print out
    }' > "$tmp/claims.json"
  [ -s "$tmp/claims.json" ] || { echo "opaque (not a JWT)"; return 0; }
  iss=$(jstr iss "$tmp/claims.json")
  aud=$(awk 'BEGIN { RS = "\001" } { if (match($0, /"aud"[ \t]*:[ \t]*(\[[^]]*\]|"[^"]*")/)) { s = substr($0, RSTART, RLENGTH); sub(/^"aud"[ \t]*:[ \t]*/, "", s); gsub(/[]["]/, "", s); gsub(/,/, ", ", s); print s } }' "$tmp/claims.json")
  who=$(jstr azp "$tmp/claims.json"); [ -n "$who" ] || who=$(jstr client_id "$tmp/claims.json"); [ -n "$who" ] || who=$(jstr appid "$tmp/claims.json")
  scp=$(jstr scope "$tmp/claims.json"); [ -n "$scp" ] || scp=$(jstr scp "$tmp/claims.json")
  roles=$(awk 'BEGIN { RS = "\001" } { if (match($0, /"roles"[ \t]*:[ \t]*\[[^]]*\]/)) { s = substr($0, RSTART, RLENGTH); sub(/^"roles"[ \t]*:[ \t]*/, "", s); gsub(/[]["]/, "", s); gsub(/,/, ", ", s); print s } }' "$tmp/claims.json")
  rm -f "$tmp/claims.json"
  printf 'issuer %s; audience %s; client %s; scopes %s; roles %s\n' "${iss:-none}" "${aud:-none}" "${who:-none}" "${scp:-none}" "${roles:-none}" | mask
}

# ---------- --discover: the token endpoint of the provider ----------
if [ "$mode" = discover ]; then
  [ "$auth" = oidc ] || { echo "STOP: $name has no OpenID Connect provider (oidc or token-url in its settings)"; exit 1; }
  discover
  echo "TOKEN ENDPOINT: $endpoint"
  exit 0
fi

# ---------- --check: the access, step by step ----------
if [ "$mode" = check ]; then
  echo "$ENVLINE"
  case "$auth" in
    oidc) echo "CHECK: variables: $([ -n "$clientvar" ] && echo "$clientvar set, ")$secretvar set$([ -n "$proxycredvar" ] && echo ", $proxycredvar set")" ;;
    token) echo "CHECK: variables: $tokenvar set$([ -n "$proxycredvar" ] && echo ", $proxycredvar set")" ;;
    *) [ -n "$proxycredvar" ] && echo "CHECK: variables: $proxycredvar set" ;;
  esac
  need_curl
  if [ "$auth" = oidc ]; then
    if [ -n "$tokenurl" ]; then echo "CHECK: token endpoint (token-url): $tokenurl"; else discover; echo "CHECK: discovery OK: token endpoint $endpoint"; fi
    get_token
    echo "CHECK: token OK: expires in ${expires:-?} s; $(claims "$token")"
  fi
  # the API without the token: does it answer at all
  probe=${health:-/}
  req "$tmp/probe" "url = \"$(cesc "$url$probe")\""
  unreachable "$name" "$url" && exit 1
  down "$probe" && exit 1
  echo "CHECK: API $url$probe answers $code without a token"
  # an endpoint that needs authentication, read from the code: a GET without route parameter
  path=""
  [ -n "$token" ] && path=$(sh "$here/api-routes.sh" 2>/dev/null | awk -F '|' 'NF >= 9 { v = $2; r = $3; a = $5; gsub(/^[ \t]+|[ \t]+$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", r); gsub(/^[ \t]+|[ \t]+$/, "", a)
      if (v == "GET" && r ~ /^\// && r !~ /[{<]/ && a != "-" && a !~ /[Aa]nonymous/) { print r; exit } }')
  if [ -n "$token" ] && [ -z "$path" ]; then
    echo "CHECK: no GET endpoint with authentication and without route parameter in the code: the environment tests check the token on the API"
  elif [ -n "$token" ]; then
    req "$tmp/probe" "url = \"$(cesc "$url$path")\""
    without=$code
    req "$tmp/probe" "url = \"$(cesc "$url$path")\"" "header = \"Authorization: Bearer $(cesc "$token")\"" 'dump-header = "'"$(cesc "$tmp/headers")"'"'
    unreachable "$name" "$url" && exit 1
    case "$code" in
      401)
        why=$(grep -i '^www-authenticate:' "$tmp/headers" 2>/dev/null | head -n 1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' | mask)
        echo "ENVIRONMENT PROBLEM: the API of $name refuses the token on GET $path (401${why:+: $why}): the token is not the one this API expects (its audience, its issuer or its scope: « scope » or « audience » of the settings of $name). Stop and tell the user in one line."
        exit 1 ;;
      403) echo "CHECK: API GET $path answers 403 with the token ($without without): the client is known but lacks the role or the policy of this endpoint: the environment tests of such endpoints fail until the provider gives it" ;;
      *) echo "CHECK: API GET $path answers $code with the token ($without without)" ;;
    esac
  fi
  echo "CHECK: OK"
  exit 0
fi

# ---------- the environment tests ----------
# The projects of the environment tests: those whose test files carry the category
if [ -z "$project" ]; then
  project=$(git grep -l -E '(Trait|Category|TestCategory)[[:space:]]*\([[:space:]]*("Category",[[:space:]]*)?"Environment(Writes)?"' -- '*.cs' 2>/dev/null |
    while IFS= read -r f; do
      d=$(dirname "$f")
      while [ "$d" != . ] && [ -z "$(ls "$d"/*.csproj 2>/dev/null)" ]; do d=$(dirname "$d"); done
      ls "$d"/*.csproj 2>/dev/null | head -n 1
    done | sed 's#^\./##' | sort -u)
fi
if [ -z "$project" ]; then
  echo "STOP: no environment test in this repository (tests marked with the category Environment): /tests api writes them"
  exit 1
fi

echo "$ENVLINE"
# before any build: the provider gives a token, the API answers (an environment out of reach stops here, in seconds)
if [ "$auth" = oidc ]; then
  get_token
  echo "TOKEN: OK from the provider of $name (expires in ${expires:-?} s)"
fi
if [ "${ENV_TESTS_PREFLIGHT:-1}" != 0 ] && [ "$have_curl" -eq 1 ]; then
  req "$tmp/probe" "url = \"$(cesc "$url${health:-/}")\""
  unreachable "$name" "$url" && exit 1
  down "${health:-/}" && exit 1
fi

final=0 i=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  i=$((i + 1))
  echo "PROJECT: $p"
  kind=$(sh "$here/test-platform.sh" kind "$p" 2>/dev/null)
  case "$kind" in *" mstest "*) prop=TestCategory ;; *) prop=Category ;; esac
  filter="$prop=Environment"
  [ "$writes" -eq 1 ] && filter="$filter|$prop=EnvironmentWrites"
  [ -n "$extra" ] && filter="($filter)&($extra)"
  res="$tmp/results-$i"
  out="$tmp/out-$i"
  sh "$here/build-test.sh" --build-only "$p" > "$out" 2>&1
  status=$?
  mask "$out"
  if [ "$status" -ne 0 ]; then
    final=1
    continue
  fi
  # a token asked just before the tests: it lives from their start (5 minutes on a default Keycloak)
  [ "$auth" = oidc ] && get_token
  # one result per test (VSTest: a TRX report; a Microsoft.Testing.Platform project gives its summary only)
  set -- --no-build "$p" --filter "$filter"
  case "$kind" in vstest*) set -- "$@" --logger "trx;LogFileName=env-tests.trx" --results-directory "$res" ;; esac
  API_BASE_URL=$url API_TOKEN=$token API_ENVIRONMENT=$name API_WRITES=$writes \
    API_OIDC_TOKEN_URL=$endpoint API_OIDC_CLIENT_ID=$clientid API_OIDC_CLIENT_SECRET=$secret API_OIDC_SCOPE=$scope \
    API_OIDC_AUDIENCE=$audience API_OIDC_RESOURCE=$resource API_OIDC_CLIENT_AUTH=$([ "$auth" = oidc ] && echo "$clientauth") \
    sh "$here/build-test.sh" "$@" > "$out" 2>&1
  status=$?
  set --
  mask "$out" > "$out.masked"
  cat "$out.masked"
  if [ -f "$res/env-tests.trx" ]; then
    mask "$res/env-tests.trx" | awk '
      function attr(name,   r) { if (match($0, name "=\"[^\"]*\"")) { r = substr($0, RSTART + length(name) + 2, RLENGTH - length(name) - 3); return r } return "" }
      /<UnitTestResult / {
        n = attr("testName"); o = attr("outcome"); d = attr("duration")
        split(d, t, ":"); secs = t[1] * 3600 + t[2] * 60 + t[3]
        printf "  %s  %s (%.2f s)\n", (o == "Passed" ? "OK" : o == "NotExecuted" ? "SKIPPED" : "FAILED"), n, secs
      }'
  fi
  if grep -q -E "proxy tunnel request to proxy '[^']*' failed with status code '407'|Proxy Authentication Required" "$out.masked"; then
    echo "ENVIRONMENT PROBLEM: the proxy refuses the tests' connection to $name ($url) without credentials, or with these (407): $proxyshown. Stop and tell the user in one line: proxy-identifiants of $name (/tests env config $name)."
    status=1
  elif grep -q -E "proxy tunnel request to proxy '[^']*' failed with status code '[0-9]+'" "$out.masked"; then
    echo "ENVIRONMENT PROBLEM: the proxy refuses the tests' connection to $name ($url): $proxyshown. Stop and tell the user in one line."
    status=1
  elif grep -q -E 'HttpRequestException|SocketException|AuthenticationException' "$out.masked" &&
    grep -q -E 'No such host is known|Name or service not known|nodename nor servname|Temporary failure in name resolution|Connection refused|actively refused|No route to host|Network is unreachable|SSL connection could not be established|remote certificate is invalid|UntrustedRoot|RemoteCertificateChainErrors|RemoteCertificateNameMismatch' "$out.masked"; then
    echo "ENVIRONMENT PROBLEM: $name ($url) cannot be reached from this machine (name resolution, network, VPN, proxy or certificate). Stop and tell the user in one line; never retry another way."
    status=1
  elif grep -q -E 'TaskCanceledException.*(HttpClient\.Timeout|timeout)' "$out.masked"; then
    echo "ENVIRONMENT PROBLEM: $name ($url) did not answer within the timeout of the tests. Stop and tell the user in one line."
    status=1
  fi
  [ "$status" -eq 0 ] || final=1
done <<EOF
$project
EOF
exit $final
