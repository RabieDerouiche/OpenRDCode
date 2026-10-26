#!/bin/sh
# Tests of the environments of the pack and of its wizards' scripts, against a REAL OpenID Connect provider, a REAL API
# that checks its tokens and a REAL HTTP proxy with credentials, on this machine (tools/oidc-proxy-lab.mjs: curl and
# the scripts speak HTTP and TLS for real, through the proxy that alone resolves the names of the lab), and the fake
# dotnet for the test runs (tools/fake-dotnet.sh): environments.sh (the settings of an environment), env-setup.sh (the
# wizard of /tests env config), env-tests.sh (--check, --discover, a run: the token asked to the provider, the proxy,
# the certificate authorities, every secret masked), http-files.sh (the OAuth 2.0 of Rider), related-setup.sh and
# related-repos.sh (the wizard of /outil liens: AGENTS.md of both sides, the references of opencode.json), tests.sh
# (the facts of /tests), api-preflight.sh, schedule.sh (never a wizard planned). Needs node, curl and openssl.
# Usage, from opencode-v2/: sh tools/environments-test.sh [<shell>] (default sh).
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
for tool in node curl openssl git; do
  command -v "$tool" > /dev/null 2>&1 || { echo "environments-test: $tool is not on the PATH of this machine"; exit 2; }
done
work=$(mktemp -d "${TMPDIR:-/tmp}/environments-test.XXXXXX") || exit 1
lab=""
trap '[ -n "$lab" ] && kill "$lab" 2>/dev/null; rm -rf "$work"' EXIT
HOME="$work/home"
mkdir -p "$HOME" "$work/bin" "$work/state" "$work/tmp"
export HOME
cp "$pack/tools/fake-dotnet.sh" "$work/bin/dotnet"
chmod +x "$work/bin/dotnet"
PATH="$work/bin:$PATH"
FAKE_DOTNET_LOG="$work/dotnet.log"
FAKE_DOTNET_STATE="$work/state"
TMPDIR="$work/tmp"
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
OPENCODE_SCHEDULES="$work/schedules.md"
export PATH FAKE_DOTNET_LOG FAKE_DOTNET_STATE TMPDIR OPENCODE_CONFIG_DIR OPENCODE_SCHEDULES
# the proxies of this machine are not those of the lab
unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy SSL_CERT_FILE
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
printf '[init]\n\tdefaultBranch = develop\n' > "$GIT_CONFIG_GLOBAL"

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
    printf '%s\n' "$out" | sed 's/^/    /' | tail -n 40
  fi
}
run() {
  script=$1
  shift
  : > "$FAKE_DOTNET_LOG"
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
  # shellcheck disable=SC2034 # read in the eval of truth
  calls=$(cat "$FAKE_DOTNET_LOG")
}
truth() {
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 ($2)"; fi
}
# no secret of the lab in an output: the client secrets, the password of the proxy, a JWT
SECRETS='s3cr3t-|p@ss w0rd|p%40ss|w0rd|eyJ[A-Za-z0-9_-]{10,}'

# ---------- the lab: provider, API and proxy (TLS with an internal certificate authority) ----------
mkdir -p "$work/pki"
(
  cd "$work/pki" || exit 1
  openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.pem -days 2 -subj "/CN=Lab Internal CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" > /dev/null 2>&1
  openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=apis.lab.test" > /dev/null 2>&1
  printf 'subjectAltName=DNS:apis.lab.test,DNS:idps.lab.test\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' > ext.cnf
  openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out server.pem -days 2 -extfile ext.cnf > /dev/null 2>&1
)
[ -s "$work/pki/server.pem" ] || { echo "environments-test: openssl could not make the certificates of the lab"; exit 2; }
node "$pack/tools/oidc-proxy-lab.mjs" "$work/lab" --proxy-user 'dev:p@ss w0rd' --tls "$work/pki/server.pem" "$work/pki/server.key" > "$work/lab.out" 2>&1 &
lab=$!
for _ in $(seq 1 100); do [ -s "$work/lab/lab.json" ] && break; sleep 0.1; done
[ -s "$work/lab/lab.json" ] || { echo "environments-test: the lab did not start"; cat "$work/lab.out"; exit 2; }
P=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).proxy)' "$work/lab/lab.json")
echo "environments-test: lab up, proxy $P"

# ---------- a repository with an API, its environments and their settings ----------
mkdir -p "$work/repos/api-factures"
cd "$work/repos/api-factures" || exit 1
git init -q
mkdir -p src/Api/Controllers src/Api/Properties tests/Api.IntegrationTests
printf '<Project Sdk="Microsoft.NET.Sdk.Web">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/Api/Api.csproj
cat > src/Api/Controllers/OrdersController.cs <<'EOF'
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
namespace Shop.Api.Controllers;
[ApiController]
[Route("api/orders")]
[Authorize]
public class OrdersController : ControllerBase
{
    [HttpGet] public IActionResult List() => Ok();
    [HttpGet("{id:int}")] public IActionResult Get(int id) => Ok();
}
EOF
printf 'var app = WebApplication.CreateBuilder(args).Build();\napp.MapHealthChecks("/health");\napp.Run();\n' > src/Api/Program.cs
printf '{ "profiles": { "https": { "applicationUrl": "https://localhost:7123;http://localhost:5123" } } }\n' > src/Api/Properties/launchSettings.json
cat > src/Api/appsettings.json <<'EOF'
{
  "ConnectionStrings": { "Default": "Server=db;Password=SuperSecret123" },
  "Authentication": { "Schemes": { "Bearer": { "Authority": "http://idp.lab.test/realms/test", "ValidAudiences": [ "acme-api" ] } } },
  "Payments": { "ClientId": "payments", "ClientSecret": "hunter2hunter2" }
}
EOF
cat > .gitlab-ci.yml <<'EOF'
deploy_recette:
  stage: deploy
  environment:
    name: recette
    url: http://api.lab.test
EOF
cat > tests/Api.IntegrationTests/Api.IntegrationTests.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.0" />
  </ItemGroup>
</Project>
EOF
printf 'bin/\nobj/\n' > .gitignore
printf '# api-factures\n\n## Project overview\n- The invoices API.\n\n## Build & test\n- Solution : `Shop.slnx`\n\n## Repository-specific rules\n- Never call S3 directly.\n' > AGENTS.md
git add -A && git commit -q -m "FACT-1 the invoices API" && git commit -q --allow-empty -m "FACT-2 more"

# ---------- environments.sh: the settings of an environment ----------
cp AGENTS.md AGENTS.md.orig
cat >> AGENTS.md <<EOF

## Environnements
(a line of explanation)
- \`recette\` : http://api.lab.test/ (écriture permise)
  - oidc : http://idp.lab.test/realms/test/
  - client : \`RECETTE_CLIENT_ID\`
  - secret : \`RECETTE_CLIENT_SECRET\`
  - scope : api://acme-api/.default (celui de l'API)
  - Proxy : $P
  - proxy identifiants : \`RECETTE_PROXY_CREDENTIALS\`
  - sans-proxy : .internal, 10.0.0.1
  - certificat : ~/certs/acme-ca.pem
  - santé : health
- \`qa\` : https://qa.example.com
  - oidc : https://login.example.com/realms/qa
  - client : tests-qa
  - secret : s3cr3t-qa
  - proxy : http://user:pw@proxy:3128
- \`prod-eu\` : https://api-eu.example.com
- \`prd1\` : https://api-1.example.com
- \`live_fr\` : https://api-fr.example.com
- \`preproduction\` : https://pp.example.com
- \`prod\` : https://api.example.com (production)
- \`recette\` : https://dup.example.com
  - inconnu : x

## Environments
- \`confluence\` : https://api.example.com — from Confluence
EOF
run environments.sh
check "environments: OpenID Connect from its settings" 0 '^recette	http://api\.lab\.test	-	yes	no	oidc$'
check "environments: a name that starts with prod, prd or live is production" 0 '^prod-eu	.*	no	yes	none$'
check "environments: prd1 and live_fr are production" 0 '^live_fr	.*	yes	none$'
check "environments: preproduction is not production" 0 '^preproduction	https://pp\.example\.com	-	no	no	none$'
check "environments: a secret written as a value is refused, never printed" 0 '^WARNING: qa: a secret is never written in AGENTS\.md' "$SECRETS"
check "environments: credentials in the URL of a proxy refused" 0 '^WARNING: qa: a user or a password in the URL of the proxy'
check "environments: the first of two environments of the same name counts" 0 '^WARNING: recette: declared twice: the first one counts'
check "environments: the section « ## Environments » beside it is not read" 0 '^WARNING: the section « ## Environments » is not read' '^confluence	'
run environments.sh --details recette
check "environments --details: the authority" 0 '^authority=http://idp\.lab\.test/realms/test$'
check "environments --details: the client id from a variable, the secret from another" 0 '^client_var=RECETTE_CLIENT_ID$'
check "environments --details: the scope without its comment" 0 '^scope=api://acme-api/\.default$'
check "environments --details: the proxy and its credentials (a setting named with spaces and a capital)" 0 "^proxy_credentials_var=RECETTE_PROXY_CREDENTIALS$"
check "environments --details: the hosts without proxy, the certificate, the health path" 0 '^no_proxy=\.internal,10\.0\.0\.1$'
check "environments --details: santé is a path" 0 '^health=/health$'
run environments.sh --details qa
check "environments --details: an environment that is not complete says why" 0 '^invalid=secret-value,proxy$'
run environments.sh --details nowhere
check "environments --details: an environment not declared" 1 '^$|.'
cp AGENTS.md.orig AGENTS.md

# ---------- env-setup.sh: the wizard of /tests env config ----------
RECETTE_PROXY_CREDENTIALS='dev:p@ss w0rd'
export RECETTE_PROXY_CREDENTIALS
run env-setup.sh scan
check "env-setup scan: the URL of a deploy job" 0 '^HINT URL: recette http://api\.lab\.test \(\.gitlab-ci\.yml, job deploy_recette\)$'
check "env-setup scan: the authority the API checks" 0 '^HINT OIDC: Authority http://idp\.lab\.test/realms/test \(src/Api/appsettings\.json: Authentication:Schemes:Bearer\)$'
check "env-setup scan: never a value of another key (a password, a secret)" 0 '^HINT OIDC: ValidAudiences acme-api' 'SuperSecret|hunter2|payments'
check "env-setup scan: the names of the variables of a new environment" 0 '^VARIABLES OF A NEW ENVIRONMENT <name>: <NAME>_CLIENT_ID, <NAME>_CLIENT_SECRET, <NAME>_PROXY_CREDENTIALS, API_TOKEN_<NAME>'
check "env-setup scan: no proxy on this machine" 0 '^PROXY OF THIS MACHINE: none'
run env-setup.sh set recette --url http://api.lab.test/ --oidc http://idp.lab.test/realms/test --client tests-recette --scope "api://acme-api/.default" --proxy "$P" --proxy-auth --health /health --role "la recette de l'équipe"
check "env-setup set: the block written" 0 '^WRITTEN: AGENTS\.md « ## Environnements » — recette \(new\)$'
check "env-setup set: the token endpoint of the discovery document, through the proxy" 0 '^TOKEN URL: http://idp\.lab\.test/realms/test/protocol/openid-connect/token \(discovery document of the authority\)$'
check "env-setup set: the variables to set, names only" 0 "^  export RECETTE_CLIENT_SECRET='<the client secret of recette>'$" "$SECRETS"
truth "env-setup set: before « ## Build & test », the other sections kept" 'awk "/^## Environnements/ { e = NR } /^## Build/ { b = NR } /^## Repository-specific rules/ { r = NR } END { exit !(e && e < b && b < r) }" AGENTS.md && grep -q "^- Never call S3 directly\.$" AGENTS.md'
truth "env-setup set: what environments.sh reads back" '[ "$(sh "$scripts/environments.sh" recette)" = "$(printf "recette\thttp://api.lab.test\t-\tno\tno\toidc")" ]'
run env-setup.sh set recette --url http://api.lab.test --oidc http://idp.lab.test/realms/test --client-var --scope "api://acme-api/.default" --proxy "$P" --proxy-auth --health /health --writes
check "env-setup set: the same environment updated, not duplicated" 0 '^WRITTEN: AGENTS\.md « ## Environnements » — recette \(updated\)$'
truth "env-setup set: one block for recette, its client id in a variable now" '[ "$(grep -c "^- \`recette\`" AGENTS.md)" -eq 1 ] && grep -q "^  - client : \`RECETTE_CLIENT_ID\`$" AGENTS.md && grep -q "^- \`recette\` : http://api.lab.test (écriture permise)$" AGENTS.md'
run env-setup.sh set prod --url https://api.example.com --production
check "env-setup set: production, its line only" 0 '^  - `prod` : https://api\.example\.com \(production\)$' 'VARIABLES:|NEXT:'
run env-setup.sh set preprod --url https://api-preprod.example.com --token-var --proxy none
check "env-setup set: a fixed token, no proxy" 0 '^  - `preprod` : https://api-preprod\.example\.com \(jeton : `API_TOKEN_PREPROD`\)$'
run env-setup.sh set x --url https://u:p@x.example.com
check "env-setup set: a URL with credentials refused, nothing written" 1 '^STOP: --url is an http\(s\) URL without user or password'
run env-setup.sh set x --url https://x.example.com --production --writes
check "env-setup set: production never with writes" 1 '^STOP: production never allows writes$'
run env-setup.sh set x --url https://x.example.com --proxy-auth
check "env-setup set: proxy credentials need its URL" 1 '^STOP: --proxy-auth goes with --proxy <its URL>'
run env-setup.sh set 'a b' --url https://x.example.com
check "env-setup set: a name with a space refused" 1 '^STOP: the name of an environment'
run env-setup.sh remove preprod
check "env-setup remove" 0 '^REMOVED: preprod from AGENTS\.md'
truth "env-setup remove: its block gone, the others kept" '! grep -q preprod AGENTS.md && grep -q "^- \`prod\`" AGENTS.md && grep -q "^- \`recette\`" AGENTS.md'

# ---------- env-tests.sh --check and --discover against the lab ----------
RECETTE_CLIENT_ID=tests-recette RECETTE_CLIENT_SECRET=s3cr3t-recette
export RECETTE_CLIENT_ID RECETTE_CLIENT_SECRET
run env-tests.sh --discover recette
check "env-tests --discover: the token endpoint" 0 '^TOKEN ENDPOINT: http://idp\.lab\.test/realms/test/protocol/openid-connect/token$'
run env-tests.sh --check recette
check "env-tests --check: the access, step by step" 0 '^CHECK: OK$' "$SECRETS"
check "env-tests --check: the token and what it holds (audience, client, roles), never itself" 0 '^CHECK: token OK: expires in 300 s; issuer http://idp\.lab\.test/realms/test; audience acme-api; client tests-recette; scopes api://acme-api/\.default; roles orders\.read$'
check "env-tests --check: the API answers, then the endpoint of the code that needs a token" 0 '^CHECK: API GET /api/orders answers 200 with the token \(401 without\)$'
check "env-tests --check: how it is reached" 0 '^ENVIRONMENT: recette http://api\.lab\.test \(tests that write: allowed\) — token: OpenID Connect \(client credentials\); proxy http://127\.0\.0\.1:[0-9]+ \(credentials from RECETTE_PROXY_CREDENTIALS\)$'
truth "env-tests --check: every call went through the proxy" 'grep -q "^http GET idp.lab.test/realms/test/.well-known/openid-configuration$" "$work/lab/proxy.log" && grep -q "^token tests-recette post scope=api://acme-api/.default$" "$work/lab/proxy.log"'
(unset RECETTE_CLIENT_SECRET; "$SHELL_UNDER_TEST" "$scripts/env-tests.sh" --check recette > "$work/out" 2>&1; echo $? > "$work/status")
out=$(cat "$work/out") status=$(cat "$work/status")
check "env-tests --check: a variable not set, said with how to set it (nothing to restart)" 1 "^ENVIRONMENT PROBLEM: the variable RECETTE_CLIENT_SECRET, which holds the client secret of recette, is not set in the environment of OpenCode\. .*export RECETTE_CLIENT_SECRET='…'; OpenCode reads ~/\.zshenv again at each command: nothing to restart"
# add_envs <file>: its lines at the end of the section « ## Environnements » of AGENTS.md
add_envs() {
  awk -v add="$1" '
    function emit() { if (!done) { while ((getline l < add) > 0) print l; done = 1 } }
    /^## / { if (insec) emit(); insec = ($0 ~ /^## Environnements/) }
    /^[ \t]*$/ { blank++; next }
    { for (i = 0; i < blank; i++) print ""; blank = 0; print }
    END { if (insec) emit(); for (i = 0; i < blank; i++) print "" }' AGENTS.md > "$work/agents.md" && cat "$work/agents.md" > AGENTS.md
}
cat > "$work/more-envs" <<EOF
- \`badsecret\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`BAD_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`noproxyauth\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`RECETTE_CLIENT_SECRET\`
  - proxy : $P
- \`badscope\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`RECETTE_CLIENT_SECRET\`
  - scope : api://other/.default
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`nosa\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : no-sa
  - secret : \`NOSA_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`basic\` : http://api.lab.test
  - token-url : http://idp.lab.test/realms/test/protocol/openid-connect/token
  - client : tests-admin
  - secret : \`ADMIN_SECRET\`
  - auth-client : basic
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`otheraud\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-other
  - secret : \`OTHER_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`badauthority\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/nope
  - client : tests-recette
  - secret : \`RECETTE_CLIENT_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`legacy\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : legacy
  - secret : \`BAD_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`direct\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`RECETTE_CLIENT_SECRET\`
  - proxy : aucun
- \`bypass\` : http://api.lab.test
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
  - sans-proxy : api.lab.test
- \`blocked\` : https://blocked.lab.test
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`unknownhost\` : https://nowhere.lab.test
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`dnsfail\` : https://dnsfail.lab.test
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`deadproxy\` : https://apis.lab.test
  - proxy : http://127.0.0.1:$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).closedPort)' "$work/lab/lab.json")
- \`tls\` : https://apis.lab.test
  - oidc : https://idps.lab.test/realms/test
  - client : tests-recette
  - secret : \`RECETTE_CLIENT_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
  - certificat : $work/pki/ca.pem
  - santé : /health
- \`notrust\` : https://apis.lab.test
  - oidc : https://idps.lab.test/realms/test
  - client : tests-recette
  - secret : \`RECETTE_CLIENT_SECRET\`
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
- \`nocafile\` : https://apis.lab.test
  - certificat : ~/nope/ca.pem
- \`down\` : http://api.lab.test
  - proxy : $P
  - proxy-identifiants : \`RECETTE_PROXY_CREDENTIALS\`
  - santé : /down
EOF
add_envs "$work/more-envs"
truth "the environments of these tests are in the section" '[ "$(sh "$scripts/environments.sh" | grep -c -v "^WARNING:")" -ge 20 ]'
BAD_SECRET=wrong-secret-value NOSA_SECRET=s3cr3t-nosa ADMIN_SECRET=s3cr3t-admin OTHER_SECRET=s3cr3t-other
export BAD_SECRET NOSA_SECRET ADMIN_SECRET OTHER_SECRET
run env-tests.sh --check badsecret
check "env-tests --check: a wrong secret (invalid_client)" 1 '^ENVIRONMENT PROBLEM: the provider of badsecret refuses the client \(401 invalid_client' "$SECRETS|wrong-secret"
run env-tests.sh --check legacy
check "env-tests --check: a wrong secret answered unauthorized_client (older Keycloak): still a wrong client or secret" 1 '^ENVIRONMENT PROBLEM: the provider of legacy refuses the client \(400 unauthorized_client: Invalid client secret\): the client id or the secret \(BAD_SECRET\) is wrong' "$SECRETS|wrong-secret"
run env-tests.sh --check noproxyauth
check "env-tests --check: a proxy that wants credentials (407)" 1 '^ENVIRONMENT PROBLEM: the proxy refuses the connection to the OpenID Connect provider of noproxyauth .*407 Proxy Authentication Required'
run env-tests.sh --check badscope
check "env-tests --check: a scope the provider does not know (invalid_scope)" 1 '^ENVIRONMENT PROBLEM: the provider of badscope refuses the scope « api://other/\.default » \(400 invalid_scope'
run env-tests.sh --check nosa
check "env-tests --check: a client without service account (unauthorized_client)" 1 '^ENVIRONMENT PROBLEM: the client of nosa may not ask a token by client credentials \(400 unauthorized_client'
run env-tests.sh --check basic
check "env-tests --check: client_secret_basic, the token URL given" 0 '^CHECK: token OK: .*client tests-admin; .*roles orders\.read, admin$' "$SECRETS"
truth "env-tests --check: the provider got the client in Basic" 'grep -q "^token tests-admin basic " "$work/lab/proxy.log"'
run env-tests.sh --check otheraud
check "env-tests --check: a token the API refuses (its audience), with the reason of the API" 1 "^ENVIRONMENT PROBLEM: the API of otheraud refuses the token on GET /api/orders \(401: Bearer error=\"invalid_token\", error_description=\"The audience 'other-api' is invalid\"\)" "$SECRETS"
run env-tests.sh --check badauthority
check "env-tests --check: an authority without discovery document" 1 '^ENVIRONMENT PROBLEM: the provider of badauthority has no discovery document at http://idp\.lab\.test/realms/nope/\.well-known/openid-configuration \(404\)'
run env-tests.sh --check direct
check "env-tests --check: without the proxy, the names of the lab are unknown" 1 '^ENVIRONMENT PROBLEM: the OpenID Connect provider of direct \(http://idp\.lab\.test/realms/test\) cannot be reached from this machine: its name is unknown here'
run env-tests.sh --check bypass
check "env-tests --check: sans-proxy sends that host directly" 1 '^ENVIRONMENT PROBLEM: bypass \(http://api\.lab\.test\) cannot be reached from this machine: its name is unknown here'
run env-tests.sh --check blocked
check "env-tests --check: a host the proxy forbids (403 on CONNECT)" 1 '^ENVIRONMENT PROBLEM: the proxy forbids blocked \(https://blocked\.lab\.test\) \(403 on CONNECT\)'
run env-tests.sh --check unknownhost
check "env-tests --check: a host the proxy cannot reach (502)" 1 '^ENVIRONMENT PROBLEM: the proxy cannot reach unknownhost \(https://nowhere\.lab\.test\) \(502 on CONNECT'
run env-tests.sh --check dnsfail
check "env-tests --check: a name the proxy cannot resolve (503, as squid answers)" 1 '^ENVIRONMENT PROBLEM: the proxy cannot reach dnsfail \(https://dnsfail\.lab\.test\) \(503 on CONNECT'
run env-tests.sh --check deadproxy
check "env-tests --check: a proxy that does not answer" 1 '^ENVIRONMENT PROBLEM: the proxy of deadproxy refuses the connection or does not answer'
run env-tests.sh --check tls
check "env-tests --check: TLS through the proxy, with the internal certificate authority" 0 '^CHECK: discovery OK: token endpoint https://idps\.lab\.test/realms/test/protocol/openid-connect/token$'
check "env-tests --check: TLS, the API" 0 '^CHECK: API https://apis\.lab\.test/health answers 200 without a token$'
run env-tests.sh --check notrust
check "env-tests --check: an internal certificate without its authority" 1 '^ENVIRONMENT PROBLEM: the certificate of the OpenID Connect provider of notrust \(https://idps\.lab\.test/realms/test\) is not trusted on this machine \(SSL certificate problem: unable to get local issuer certificate\)\. Stop'
run env-tests.sh --check nocafile
check "env-tests --check: a certificate file that is not there" 1 '^ENVIRONMENT PROBLEM: the certificate file of nocafile \(~/nope/ca\.pem\) is not on this machine'
run env-tests.sh --check down
check "env-tests --check: an environment down behind its gateway" 1 '^ENVIRONMENT PROBLEM: down \(http://api\.lab\.test\) answers 503 on /down'
run env-tests.sh --check prod
check "env-tests --check: never production" 1 '^STOP: prod is a production environment'

# ---------- a secret kept in HashiCorp Vault (vault:<path>#<field>), read by the vault CLI of this machine ----------
# the fake CLI answers as the real one (messages of vault 1.x): kv get -field=<field> <path>, from a store file; the
# real Vault in Docker is tools/oidc-real-test.sh
cat > "$work/bin/vault" <<'EOF'
#!/bin/sh
[ "$1" = kv ] && [ "$2" = get ] || { echo "fake vault: kv get only" >&2; exit 1; }
field=${3#-field=} path=$4
echo "$*" >> "$FAKE_VAULT_LOG"
case "${FAKE_VAULT_MODE:-}" in
  notoken) printf 'Error making API request.\n\nURL: GET %s/v1/sys/internal/ui/mounts/%s\nCode: 403. Errors:\n\n* missing client token\n' "$VAULT_ADDR" "$path" >&2; exit 2 ;;
  denied) printf 'Error making API request.\n\nURL: GET %s/v1/%s\nCode: 403. Errors:\n\n* permission denied\n' "$VAULT_ADDR" "$path" >&2; exit 2 ;;
  down) printf 'Get "%s/v1/sys/internal/ui/mounts/%s": dial tcp 127.0.0.1:8200: connect: connection refused\n' "$VAULT_ADDR" "$path" >&2; exit 2 ;;
esac
grep -q "^$path#" "$FAKE_VAULT_STORE" || { printf 'No value found at %s\n' "$path" >&2; exit 2; }
line=$(grep "^$path#$field=" "$FAKE_VAULT_STORE" | head -n 1)
[ -n "$line" ] || { printf 'Field "%s" not present in secret\n' "$field" >&2; exit 1; }
printf '%s' "${line#*=}"
EOF
chmod +x "$work/bin/vault"
FAKE_VAULT_STORE="$work/vault-store" FAKE_VAULT_LOG="$work/vault.log" VAULT_ADDR=https://vault.lab.test:8200
export FAKE_VAULT_STORE FAKE_VAULT_LOG VAULT_ADDR
printf 'secret/lab/recette#client_secret=s3cr3t-recette\nsecret/lab/proxy#credentials=dev:p@ss w0rd\nsecret/lab/fixed#token=s3cr3t-fixed-token\n' > "$FAKE_VAULT_STORE"
cat > "$work/vault-envs" <<EOF
- \`vaulted\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`vault:secret/lab/recette#client_secret\`
  - scope : api://acme-api/.default
  - proxy : $P
  - proxy-identifiants : \`vault:secret/lab/proxy#credentials\`
- \`vaultnofield\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`vault:secret/lab/recette#nope\`
  - proxy : $P
  - proxy-identifiants : \`vault:secret/lab/proxy#credentials\`
- \`vaultnopath\` : http://api.lab.test
  - oidc : http://idp.lab.test/realms/test
  - client : tests-recette
  - secret : \`vault:secret/lab/nothing#client_secret\`
  - proxy : $P
- \`vaultbad\` : http://api.lab.test
  - secret : \`vault:secret/lab recette\`
EOF
add_envs "$work/vault-envs"
run environments.sh --details vaulted
check "environments --details: a secret and the proxy credentials in Vault" 0 '^secret_var=vault:secret/lab/recette#client_secret$'
check "environments --details: the proxy credentials in Vault" 0 '^proxy_credentials_var=vault:secret/lab/proxy#credentials$'
run environments.sh --details vaultbad
check "environments --details: a place in Vault that is not <path>#<field> is refused" 0 '^invalid=.*secret-value' "$SECRETS"
run env-tests.sh --check vaulted
check "env-tests --check: the secret and the proxy credentials read from Vault, never printed" 0 '^CHECK: OK$' "$SECRETS"
check "env-tests --check: where each secret was read" 0 '^CHECK: variables: Vault secret/lab/recette \(field client_secret\) read, Vault secret/lab/proxy \(field credentials\) read$'
truth "env-tests --check: the vault CLI was asked each field, once" '[ "$(grep -c "kv get -field=client_secret secret/lab/recette" "$work/vault.log")" -eq 1 ] && grep -q "kv get -field=credentials secret/lab/proxy" "$work/vault.log"'
run env-tests.sh --check vaultnofield
check "env-tests --check: Vault has the path, not the field" 1 '^ENVIRONMENT PROBLEM: the client secret of vaultnofield \(Vault secret/lab/recette \(field nope\)\) cannot be read: Vault has secret/lab/recette but no field nope in it' "$SECRETS"
run env-tests.sh --check vaultnopath
check "env-tests --check: nothing in Vault at that path" 1 '^ENVIRONMENT PROBLEM: the client secret of vaultnopath .*cannot be read: nothing in Vault at secret/lab/nothing .*never run vault yourself'
FAKE_VAULT_MODE=notoken
export FAKE_VAULT_MODE
run env-tests.sh --check vaulted
check "env-tests --check: not logged in to Vault" 1 'cannot be read: you are not logged in to Vault \(https://vault\.lab\.test:8200\): vault login, in your terminal'
FAKE_VAULT_MODE=denied
run env-tests.sh --check vaulted
check "env-tests --check: a token Vault refuses" 1 'cannot be read: Vault refuses secret/lab/recette to your token'
FAKE_VAULT_MODE=down
run env-tests.sh --check vaulted
check "env-tests --check: Vault out of reach" 1 'cannot be read: Vault cannot be reached from this machine \(https://vault\.lab\.test:8200\): VPN, or VAULT_ADDR'
unset FAKE_VAULT_MODE
mv "$work/bin/vault" "$work/vault-cli"
if command -v vault > /dev/null 2>&1; then
  echo "NOTE: a vault CLI on this machine ($(command -v vault)): the checks without one are left out"
else
  run env-tests.sh --check vaulted
  check "env-tests --check: no vault CLI on this machine" 1 'cannot be read: the vault CLI of HashiCorp is not on the PATH'
  run env-setup.sh scan
  check "env-setup scan: no vault CLI, the secrets go in ~/.zshenv" 0 '^VAULT: no vault CLI on this machine'
fi
mv "$work/vault-cli" "$work/bin/vault"
run env-setup.sh scan
check "env-setup scan: the vault CLI found, never called" 0 '^VAULT: the vault CLI is on this machine \(VAULT_ADDR set\)'
check "env-setup scan: the secrets in Vault of an environment" 0 '^  variables: vault:secret/lab/recette#client_secret in Vault, read at each run'
: > "$work/vault.log"
run env-setup.sh set coffre --url http://api.lab.test --oidc http://idp.lab.test/realms/test --client tests-recette --vault secret/lab/recette#client_secret --proxy "$P" --proxy-vault vault:secret/lab/proxy#credentials
check "env-setup set --vault: its place in Vault, never a value" 0 '^    - secret : `vault:secret/lab/recette#client_secret`$' "$SECRETS"
check "env-setup set --proxy-vault: the proxy credentials in Vault" 0 '^    - proxy-identifiants : `vault:secret/lab/proxy#credentials`$'
check "env-setup set --vault: no variable to set, how Vault is read" 0 '^VAULT: secret/lab/recette, field client_secret: read at each run by the vault CLI' "export COFFRE_CLIENT_SECRET"
truth "env-setup set: the wizard never reads the client secret (only the proxy credentials, to reach the discovery document)" '! grep -q client_secret "$work/vault.log" && grep -q "credentials secret/lab/proxy" "$work/vault.log"'
run env-tests.sh --check coffre
check "env-tests --check: the environment the wizard wrote with Vault" 0 '^CHECK: OK$' "$SECRETS"
run env-setup.sh set coffre2 --url http://api.lab.test --vault secret/lab/fixed#token
check "env-setup set --vault: neither OIDC nor a fixed token" 1 '^STOP: --vault goes with OpenID Connect'
run env-setup.sh set coffre2 --url http://api.lab.test --oidc http://idp.lab.test/realms/test --client x --vault 'secret/lab x'
check "env-setup set --vault: not <path>#<field>" 1 '^STOP: --vault is <path>#<field>'
run env-setup.sh remove coffre

# ---------- env-tests.sh: a run, with the fake dotnet ----------
cat > tests/Api.IntegrationTests/OrdersEnvironmentTests.cs <<EOF
using Xunit;
namespace Api.IntegrationTests;
[Trait("Category", "Environment")]
public class OrdersEnvironmentTests { }
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Url env API_BASE_URL=http://api.lab.test category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Bearer envset API_TOKEN category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.TokenUrl env API_OIDC_TOKEN_URL=http://idp.lab.test/realms/test/protocol/openid-connect/token category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.ClientId env API_OIDC_CLIENT_ID=tests-recette category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Secret env API_OIDC_CLIENT_SECRET=s3cr3t-recette category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Scope env API_OIDC_SCOPE=api://acme-api/.default category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Proxy env HTTPS_PROXY=http://dev:p%40ss%20w0rd@${P#http://} category=Environment -->
// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Echo fail The API answered 401 to Bearer \$API_TOKEN category=Environment -->
EOF
git add -A && git commit -q -m "environment tests"
sed -i.bak "s#^// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Echo .*#// <!-- fake-test: Api.IntegrationTests.OrdersEnvironmentTests.Echo pass category=Environment -->#" tests/Api.IntegrationTests/OrdersEnvironmentTests.cs && rm -f tests/Api.IntegrationTests/OrdersEnvironmentTests.cs.bak
git add -A && git commit -q -m "environment tests pass"
run env-tests.sh recette tests/Api.IntegrationTests/Api.IntegrationTests.csproj
check "env-tests: a token from the provider before the build" 0 '^TOKEN: OK from the provider of recette \(expires in 300 s\)$' "$SECRETS"
check "env-tests: the tests get the URL, the token, the provider and the proxy of the environment" 0 '^  OK  Api\.IntegrationTests\.OrdersEnvironmentTests\.Proxy \(' '^  FAILED  '
check "env-tests: the tests passed" 0 '^TESTS: OK$'
truth "env-tests: built once, then the tests without a build" '[ "$(printf "%s\n" "$calls" | grep -c "^dotnet build")" -eq 1 ] && printf "%s\n" "$calls" | grep -q "^dotnet test tests/Api.IntegrationTests/Api.IntegrationTests.csproj --no-build .*--filter Category=Environment"'
truth "env-tests: two tokens, one before the build and one just before the tests" '[ "$(grep -c "^token tests-recette post" "$work/lab/proxy.log")" -ge 3 ]'
run env-tests.sh recette tests/Api.IntegrationTests/Api.IntegrationTests.csproj --filter "FullyQualifiedName~Proxy"
check "env-tests: a filter on top of the category" 0 '^  OK  Api\.IntegrationTests\.OrdersEnvironmentTests\.Proxy' 'OrdersEnvironmentTests\.Url '
truth "env-tests: the filter given with the category" 'printf "%s\n" "$calls" | grep -qF -- "--filter (Category=Environment)&(FullyQualifiedName~Proxy)"'
run env-tests.sh badsecret tests/Api.IntegrationTests/Api.IntegrationTests.csproj
check "env-tests: a provider that refuses stops before any build" 1 '^ENVIRONMENT PROBLEM: the provider of badsecret refuses the client'
truth "env-tests: no dotnet call when the provider refuses" '[ -z "$calls" ]'
run env-tests.sh down tests/Api.IntegrationTests/Api.IntegrationTests.csproj
check "env-tests: an environment down stops before any build" 1 '^ENVIRONMENT PROBLEM: down \(http://api\.lab\.test\) answers 503'
truth "env-tests: no dotnet call when the environment is down" '[ -z "$calls" ]'
cat > tests/Api.IntegrationTests/ProxyEnvironmentTests.cs <<'EOF'
[Xunit.Trait("Category", "Environment")]
public class ProxyEnvironmentTests { }
// <!-- fake-test: Api.IntegrationTests.ProxyEnvironmentTests.Tunnel fail System.Net.Http.HttpRequestException : The proxy tunnel request to proxy 'http://127.0.0.1:3128/' failed with status code '407'. category=Environment -->
EOF
git add -A && git commit -q -m "a test that meets the proxy"
run env-tests.sh recette tests/Api.IntegrationTests/Api.IntegrationTests.csproj
check "env-tests: the 407 of the proxy in a test is the machine's problem" 1 '^ENVIRONMENT PROBLEM: the proxy refuses the tests. connection to recette'
git rm -q tests/Api.IntegrationTests/ProxyEnvironmentTests.cs && git commit -q -m "back"
run env-tests.sh tls tests/Api.IntegrationTests/Api.IntegrationTests.csproj --filter "FullyQualifiedName~Bearer"
check "env-tests: TLS and the internal authority for the tests too" 0 '^TESTS: OK$' "$SECRETS"
cat > tests/Api.IntegrationTests/CaEnvironmentTests.cs <<'EOF'
[Xunit.Trait("Category", "Environment")]
public class CaEnvironmentTests { }
// <!-- fake-test: Api.IntegrationTests.CaEnvironmentTests.Bundle envset SSL_CERT_FILE category=Environment -->
EOF
git add -A && git commit -q -m "ca"
run env-tests.sh tls tests/Api.IntegrationTests/Api.IntegrationTests.csproj --filter "FullyQualifiedName~Bundle"
check "env-tests: the tests get the certificate authorities (SSL_CERT_FILE)" 0 '^  OK  Api\.IntegrationTests\.CaEnvironmentTests\.Bundle'

# ---------- http-files.sh: the OAuth 2.0 of Rider for an OpenID Connect environment ----------
# two more environments for the private files: a fixed token kept in Vault, a secret with quotes and a backslash
cat > "$work/http-envs" <<'ENVS'
- `fixed` : http://api.lab.test (jeton : `vault:secret/lab/fixed#token`)
- `quoted` : http://api.lab.test
  - token-url : http://idp.lab.test/realms/test/protocol/openid-connect/token
  - client : tests-quoted
  - secret : `QUOTED_SECRET`
ENVS
add_envs "$work/http-envs"
# shellcheck disable=SC2089 # the quote and the backslash are the value
QUOTED_SECRET='s3cr3t-q"uo\te'
# shellcheck disable=SC2090
export QUOTED_SECRET
run http-files.sh --plan
check "http-files --plan: nothing written, the groups" 0 '^  GROUP: Orders — 2 request\(s\)' 'HTTP:'
check "http-files --plan: Rider asks the token of an OIDC environment" 0 '^  ENVIRONMENT: recette http://api\.lab\.test — OpenID Connect: Rider asks the token itself \(OAuth 2\.0 client credentials, token URL http://idp\.lab\.test/realms/test/protocol/openid-connect/token\)'
truth "http-files --plan: no file" '[ ! -d src/Api/http ]'
run http-files.sh --only Orders
check "http-files: the requests of a group" 0 '^HTTP: src/Api/http/Orders\.http \(2 requests\)$'
check "http-files: the secrets each environment needs, in the private file" 0 '^PRIVATE: src/Api/http/http-client\.private\.env\.json written, empty: local \(token\) recette \(clientId,clientSecret\)'
truth "http-files: the OAuth 2.0 client credentials of Rider, from AGENTS.md" 'node -e "const e = JSON.parse(require(\"fs\").readFileSync(\"src/Api/http/http-client.env.json\", \"utf8\")); const a = e.recette.Security.Auth.api; if (a.Type !== \"OAuth2\" || a[\"Grant Type\"] !== \"Client Credentials\" || a[\"Token URL\"] !== \"http://idp.lab.test/realms/test/protocol/openid-connect/token\" || a[\"Client Secret\"] !== \"{{clientSecret}}\" || a.Scope !== \"api://acme-api/.default\" || e.local.Security.Auth.api.Type !== \"Mock\") process.exit(1)"'
truth "http-files: every request asks the token of Rider" 'grep -q "^Authorization: Bearer {{\$auth.token(\"api\")}}$" src/Api/http/Orders.http'
truth "http-files: the private file is ignored by git" 'git check-ignore -q src/Api/http/http-client.private.env.json'
truth "http-files: no secret in the files written" '! grep -rqE "$SECRETS" src/Api/http'
run http-files.sh --plan
check "http-files --plan: where the token of an environment is (Vault), filled by --private" 0 '^  ENVIRONMENT: fixed http://api\.lab\.test — its token in the private file \(Vault secret/lab/fixed \(field token\): --private fills it\)$'
truth "http-files: Rider checks the status of each request (its response handler)" 'grep -q "^> {%$" src/Api/http/Orders.http'
# --private: the empty values of the private file, from the variables of this machine and from Vault, never printed
run http-files.sh --private
check "http-files --private: the client secret from its variable" 0 '^FILLED: src/Api/http/http-client\.private\.env\.json: recette clientSecret \(from the variable RECETTE_CLIENT_SECRET\)$' "$SECRETS"
check "http-files --private: the client id from its variable" 0 '^FILLED: src/Api/http/http-client\.private\.env\.json: recette clientId \(from the variable RECETTE_CLIENT_ID\)$'
check "http-files --private: a client secret from Vault" 0 '^FILLED: src/Api/http/http-client\.private\.env\.json: vaulted clientSecret \(from Vault secret/lab/recette \(field client_secret\)\)$'
check "http-files --private: a fixed token from Vault" 0 '^FILLED: src/Api/http/http-client\.private\.env\.json: fixed token \(from Vault secret/lab/fixed \(field token\)\)$'
check "http-files --private: the token URL Rider needs, from the provider" 0 '^FILLED: src/Api/http/http-client\.private\.env\.json: vaulted tokenUrl \(from AGENTS\.md and its provider\)$'
check "http-files --private: local stays to paste" 0 '^EMPTY: src/Api/http/http-client\.private\.env\.json: local token: a token of the API on this machine, to paste'
truth "http-files --private: the values in the file, as JSON, quotes and backslash included" 'node -e "const e = JSON.parse(require(\"fs\").readFileSync(\"src/Api/http/http-client.private.env.json\", \"utf8\")); if (e.recette.clientSecret !== \"s3cr3t-recette\" || e.recette.clientId !== \"tests-recette\" || e.vaulted.clientSecret !== \"s3cr3t-recette\" || e.fixed.token !== \"s3cr3t-fixed-token\" || e.quoted.clientSecret !== process.env.QUOTED_SECRET || e.local.token !== \"\") process.exit(1)"'
truth "http-files --private: the file stays ignored by git" 'git check-ignore -q src/Api/http/http-client.private.env.json'
run http-files.sh --private
check "http-files --private: a value already there is never replaced" 0 '^EMPTY: src/Api/http/http-client\.private\.env\.json: local token' 'recette clientSecret|vaulted clientSecret'
run http-files.sh --replace --client vs --only Orders
check "http-files: Visual Studio, its own private file (http-client.env.json.user)" 0 '^PRIVATE: src/Api/http/http-client\.env\.json\.user written, empty: local \(token\) recette \(token\)' '^KEPT: src/Api/http/Orders\.http'
truth "http-files: Visual Studio pastes a token" 'grep -q "^Authorization: Bearer {{token}}$" src/Api/http/Orders.http && ! grep -q Security src/Api/http/http-client.env.json'
truth "http-files: Visual Studio runs no response handler: none written" '! grep -q "{%" src/Api/http/Orders.http'
truth "http-files: the file of Visual Studio is ignored by git, the one of Rider kept as it was" 'git check-ignore -q src/Api/http/http-client.env.json.user && grep -q "s3cr3t-recette" src/Api/http/http-client.private.env.json'
run http-files.sh --private src/Api
check "http-files --private: Visual Studio, a fixed token from Vault" 0 '^FILLED: src/Api/http/http-client\.env\.json\.user: fixed token \(from Vault secret/lab/fixed \(field token\)\)$' "$SECRETS"
check "http-files --private: Visual Studio cannot ask an OIDC token" 0 '^EMPTY: src/Api/http/http-client\.env\.json\.user: recette token: recette asks a token to its OpenID Connect provider; Visual Studio cannot'
rm -rf src/Api/http
run http-files.sh --private
check "http-files --private: no private file yet" 1 '^STOP: no private file of an HTTP client'
git checkout -q -- . 2>/dev/null; rm -rf src/Api/http; git checkout -q -- .gitignore 2>/dev/null

# ---------- tests.sh: the facts of /tests ----------
run tests.sh --raw "env"
check "tests.sh: /tests env alone is the launch wizard" 0 '^Mode : env-launch$'
check "tests.sh: the environments, their access" 0 '^  - recette http://api\.lab\.test — OpenID Connect, écriture permise$'
check "tests.sh: the classes of environment tests" 0 '^  - OrdersEnvironmentTests$'
run tests.sh --raw "env config staging"
check "tests.sh: /tests env config is the configuration wizard" 0 '^Mode : env-config$'
check "tests.sh: the health path of the code" 0 '^Santé : /health \(MapHealthChecks dans le code\)$'
run tests.sh --raw "env recette Orders"
check "tests.sh: /tests env <environment>, its settings without a secret" 0 '^  auth=oidc$' "$SECRETS"
run tests.sh --raw "api OrdersController"
check "tests.sh: /tests api, the pre-flight and the endpoints" 0 '^Mode : api$'
check "tests.sh: /tests api, the pre-flight" 0 '^WEB PROJECT: src/Api/Api\.csproj \(net10\.0\)$'
check "tests.sh: /tests api, the endpoints" 0 '^\| GET \| /api/orders \|'
run tests.sh --raw ""
check "tests.sh: /tests alone is the menu" 0 '^Mode : menu$'
check "tests.sh: the menu, the API" 0 '^API ASP\.NET Core : 3 endpoint\(s\)'
run tests.sh --raw "InvoiceService"
check "tests.sh: a class: the unit tests" 0 '^Mode : unit$'

# ---------- api-preflight.sh: what would stop the API in memory ----------
mkdir -p "$work/repos/shop" && cd "$work/repos/shop" || exit 1
git init -q
mkdir -p src/Api/Controllers src/Infra
printf '<Project Sdk="Microsoft.NET.Sdk.Web">\n  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>\n  <ItemGroup><PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="8.0.11" /></ItemGroup>\n</Project>\n' > src/Api/Api.csproj
cat > src/Api/Program.cs <<'EOF'
var builder = WebApplication.CreateBuilder(args);
if (!builder.Environment.IsDevelopment())
    builder.Configuration.AddAzureKeyVault(new Uri("https://kv"), new DefaultAzureCredential());
builder.Configuration.AddAzureAppConfiguration("x");
builder.Services.AddAuthentication("Bearer").AddJwtBearer();
builder.Services.AddDbContext<ShopDbContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddHostedService<OutboxWorker>();
var app = builder.Build();
app.MapControllers();
app.Run();
if (builder.Environment.IsProduction())
{
    builder.Configuration.AddSecretsManager();
}
EOF
printf 'public class ShopDbContext(DbContextOptions<ShopDbContext> options) : DbContext(options) { }\n' > src/Infra/ShopDbContext.cs
printf '[ApiController, Route("api/orders"), Authorize(AuthenticationSchemes = "Bearer")]\npublic class OrdersController(ShopDbContext db) : ControllerBase { [HttpGet] public IActionResult Get() => Ok(); }\n' > src/Api/Controllers/OrdersController.cs
git add -A && git commit -q -m init
run api-preflight.sh
check "api-preflight: Program of top-level statements on .NET 8" 0 '^PROGRAM: src/Api/Program\.cs: top-level statements on \.NET 8: test-guardian\.sh setup --integration adds public partial class Program'
check "api-preflight: the schemes the endpoints name" 0 '^AUTHENTICATION: scheme Bearer named by an endpoint'
check "api-preflight: a DbContext used directly, its provider and its EF Core" 0 '^DBCONTEXT: ShopDbContext — registered at src/Api/Program\.cs:6, SqlServer, EF Core 8\.0\.11; used directly by the endpoints: src/Api/Controllers/OrdersController\.cs$'
check "api-preflight: a worker" 0 '^WORKER: OutboxWorker \(src/Api/Program\.cs:8\)'
check "api-preflight: a setting read at start, by its name" 0 '^SETTING AT START: ConnectionStrings:Default \(src/Api/Program\.cs:7\)'
check "api-preflight: skipped only in Development: the factory takes Development" 0 '^REMOTE CONFIGURATION: AddAzureKeyVault \(src/Api/Program\.cs:3\), skipped only in Development'
check "api-preflight: called at every start: a blocker" 0 '^REMOTE CONFIGURATION: AddAzureAppConfiguration \(src/Api/Program\.cs:4\), at every start'
check "api-preflight: inside a block on production: skipped in Testing" 0 '^REMOTE CONFIGURATION: AddSecretsManager \(src/Api/Program\.cs:14\), inside a condition on the environment'
check "api-preflight: the blockers for the first question" 0 '^- DbContext ShopDbContext utilisé directement par src/Api/Controllers/OrdersController\.cs'

# ---------- related-setup.sh and related-repos.sh: the wizard of /outil liens ----------
mkdir -p "$HOME/repos" "$HOME/elsewhere" "$OPENCODE_CONFIG_DIR"
mv "$work/repos/api-factures" "$HOME/repos/api-factures"
mkdir -p "$HOME/repos/front-factures/src/environments" "$HOME/repos/lib-montants" "$HOME/elsewhere/front-v2"
(cd "$HOME/repos/front-factures" && git init -q && printf '{ "dependencies": { "@angular/core": "19.0.0" } }\n' > package.json &&
  printf "export const environment = { api: 'https://localhost:7123' };\n" > src/environments/environment.ts &&
  printf '# front\n\n## Build & test\n- y\n' > AGENTS.md && git add -A && git commit -q -m "FACT-3 front" && git commit -q --allow-empty -m "FACT-4 more")
(cd "$HOME/repos/lib-montants" && git init -q && printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><PackageId>Acme.Montants</PackageId></PropertyGroup></Project>\n' > Lib.csproj && git add -A && git commit -q -m init)
(cd "$HOME/elsewhere/front-v2" && git init -q && echo x > a && git add -A && git commit -q -m init)
cd "$HOME/repos/api-factures" || exit 1
printf '<Project Sdk="Microsoft.NET.Sdk.Web"><ItemGroup><PackageReference Include="Acme.Montants" Version="2.3.0" /></ItemGroup></Project>\n' > src/Api/Api.csproj
git add -A && git commit -q -m "the library"
cat > "$OPENCODE_CONFIG_DIR/opencode.json" <<'EOF'
{
  // my settings
  "$schema": "https://opencode.ai/config.json",
  "model": "fake/qwen",
  "provider": { "fake": { "options": { "baseURL": "http://x/{a}" } } },
  "references": {
    "ancienne-api": { "path": "~/elsewhere/front-v2", "description": "old", },
  },
}
EOF
run related-setup.sh scan
check "related-setup scan: this repository" 0 '^THIS: api-factures — .* — API \.NET$'
check "related-setup scan: the front-end, by the same Jira projects, its name and the port of this API" 0 '^CANDIDATE: front-factures — ~/repos/front-factures — front Angular — evidence: the same Jira projects in their commits \(FACT\); a common name \(factures\); its front-end calls the local port 7123 of this API'
check "related-setup scan: the library, by its package" 0 '^CANDIDATE: lib-montants — ~/repos/lib-montants — librairie \.NET — evidence: this repository uses its package Acme\.Montants'
check "related-setup scan: the references of this machine" 0 '^REFERENCE: ancienne-api — .*/elsewhere/front-v2 \(opencode\.json of this machine\)$'
run related-setup.sh apply front-factures "$HOME/repos/front-factures" "le front Angular qui appelle cette API" --reference --reciprocal "l'API .NET que ce front appelle"
check "related-setup apply: its line in AGENTS.md, without the path of this machine" 0 '^AGENTS\.md: - `front-factures` : le front Angular qui appelle cette API$'
check "related-setup apply: the line of the other side" 0 "^RECIPROCAL: .*/front-factures/AGENTS\.md: - \`api-factures\` : l'API \.NET que ce front appelle"
check "related-setup apply: the reference of opencode.json, and the restart" 0 '^RESTART: restart OpenCode'
truth "related-setup apply: opencode.json reads as OpenCode reads it, its comment and its sections kept" 'node -e "
  const t = require(\"fs\").readFileSync(process.argv[1], \"utf8\")
  const S = String.raw\`\"(?:\\\\.|[^\"\\\\])*\"\`
  const nc = t.replace(new RegExp(S + String.raw\`|\/\/[^\n]*|\/\*[\s\S]*?\*\/\`, \"g\"), (m) => (m[0] === \"\\\"\" ? m : \"\"))
  const j = JSON.parse(nc.replace(new RegExp(S + String.raw\`|,(\s*[}\]])\`, \"g\"), (m, x) => (m[0] === \"\\\"\" ? m : x)))
  if (!t.includes(\"// my settings\") || j.model !== \"fake/qwen\" || j.references[\"front-factures\"].path !== \"~/repos/front-factures\" || j.references[\"ancienne-api\"].path !== \"~/elsewhere/front-v2\") process.exit(1)" "$OPENCODE_CONFIG_DIR/opencode.json"'
truth "related-setup apply: the copy of opencode.json before the change" '[ -f "$OPENCODE_CONFIG_DIR/opencode.json.before-outil-liens" ]'
truth "related-setup apply: the reciprocal line in the section of the other repository" 'grep -q "^## Dépôts liés$" "$HOME/repos/front-factures/AGENTS.md" && grep -q "^- \`api-factures\` : " "$HOME/repos/front-factures/AGENTS.md"'
run related-setup.sh apply front-v2 "$HOME/elsewhere/front-v2" "la future version du front"
check "related-setup apply: a repository elsewhere without reference keeps its path" 0 '^AGENTS\.md: - `front-v2` \(`~/elsewhere/front-v2`\) : la future version du front$'
run related-setup.sh apply home "$HOME" "x" --reference
check "related-setup apply: never the home folder" 1 '^STOP: .* cannot be a related repository: it is the home folder'
run related-setup.sh apply cfg "$OPENCODE_CONFIG_DIR" "x" --reference
check "related-setup apply: never a hidden folder of the home folder" 1 'it is a hidden folder of the home folder'
run related-setup.sh apply src "$HOME/repos/front-factures/src" "x" --reference
check "related-setup apply: the root of a repository only" 1 'it is a folder inside the repository'
run related-setup.sh apply sys /etc "x" --reference
check "related-setup apply: never a folder of the system" 1 'it is a folder of the system'
# the reference of this machine wins over the path of AGENTS.md (each machine its layout)
mv "$HOME/repos/lib-montants" "$HOME/elsewhere/lib-montants"
run related-setup.sh apply lib-montants "$HOME/elsewhere/lib-montants" "la librairie Acme.Montants que ce dépôt utilise" --reference
run related-repos.sh
check "related-repos: found through the reference of this machine" 0 '^RELATED: lib-montants — .*/elsewhere/lib-montants \(branch develop; reference of opencode\.json\): la librairie Acme\.Montants'
check "related-repos: next to this repository" 0 '^RELATED: front-factures — .*/repos/front-factures \(branch develop; reference of opencode\.json\)'
run related-setup.sh remove front-v2
check "related-setup remove: its line" 0 '^AGENTS\.md: front-v2 removed'
run related-setup.sh remove lib-montants --reference
check "related-setup remove: and its reference" 0 '^OPENCODE\.JSON: reference lib-montants removed'
truth "related-setup remove: opencode.json without it, the others kept" '! grep -q lib-montants "$OPENCODE_CONFIG_DIR/opencode.json" && grep -q "front-factures" "$OPENCODE_CONFIG_DIR/opencode.json" && grep -q "ancienne-api" "$OPENCODE_CONFIG_DIR/opencode.json"'
printf '{\n  "model": "x",\n' > "$OPENCODE_CONFIG_DIR/opencode.json"
run related-setup.sh apply front-factures "$HOME/repos/front-factures" "le front" --reference
check "related-setup apply: an opencode.json that does not read is never written" 0 '^OPENCODE\.JSON: .* does not read as JSON'
truth "related-setup apply: that file left as it was" '[ "$(cat "$OPENCODE_CONFIG_DIR/opencode.json")" = "$(printf "{\n  \"model\": \"x\",")" ]'

# ---------- schedule.sh: never a wizard planned; a last line removed ----------
run schedule.sh --raw "7h30 tous les jours /tests env config recette"
check "schedule: never the wizard of /tests env" 1 '^Refusé : /tests env config est un assistant'
run schedule.sh --raw "7h30 tous les jours /tests env recette"
check "schedule: /tests env <environment> planned" 0 '^Planifiée : #1, /tests env recette à 07:30'
printf -- '- #1 07:30 lun /daily — /r (ajoutée le 2026-10-24)\n' > "$OPENCODE_SCHEDULES"
run schedule.sh --raw "suppr 1"
check "schedule: the last line removed" 0 '^Retirée : #1$'
truth "schedule: the file has no schedule left" '! grep -q "^- #1 " "$OPENCODE_SCHEDULES"'

echo "environments-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
