#!/bin/sh
# The environments where the API of the repository is deployed, as its AGENTS.md declares them, for env-tests.sh,
# env-setup.sh, http-files.sh and schedule.sh. Section « ## Environnements » (« ## Environments » only when the first
# is absent: a section of that name written beside it, from Confluence for example, is not read), one line per
# environment, then its settings on indented lines (/tests env config writes them):
#   - `recette` : https://api-recette.example.com (écriture permise)
#     - oidc : https://login.example.com/realms/acme
#     - client : `RECETTE_CLIENT_ID`
#     - secret : `RECETTE_CLIENT_SECRET`
#     - scope : api://acme-api/.default
#     - proxy : http://proxy.example.com:8080
#   - `preprod` : https://api-preprod.example.com (jeton : `API_TOKEN_PREPROD`)
#   - `prod` : https://api.example.com (production)
# On its line: its name between backquotes, its base URL, then optionally « jeton : `<VARIABLE>` » (a fixed token),
# « écriture permise » (tests that write may run there), « production ». Its settings, one per indented line
# « - <setting> : <value> »; between backquotes, the name of a variable of this machine (set outside OpenCode, in
# ~/.zshenv: never a secret in AGENTS.md, never in a command):
#   oidc            the authority (issuer) of the OpenID Connect provider: its token endpoint comes from its discovery
#                   document (/.well-known/openid-configuration); a token by client credentials
#   token-url       the token endpoint itself (a provider without discovery; /tests env config writes it beside oidc)
#   client          the client id: a value, or `<VARIABLE>`
#   secret          `<VARIABLE>` that holds the client secret (a value here is refused)
#   scope           the scopes asked (Entra ID: api://<application>/.default), audience, resource: what the provider needs
#   auth-client     how the client authenticates: post (client_secret_post, the default) or basic (client_secret_basic)
#   jeton           `<VARIABLE>` that holds a fixed token (instead of oidc)
#   proxy           système (the HTTPS_PROXY of this machine, the default), aucun (direct), or http://<host>:<port>
#   proxy-identifiants  `<VARIABLE>` that holds <user>:<password> of the proxy (never in its URL)
#   sans-proxy      the hosts reached without the proxy (NO_PROXY form: .example.com,10.0.0.1)
#   certificat      a PEM file of the internal certificate authorities (~ allowed): TLS through a proxy that
#                   re-signs, an environment with an internal certificate
#   santé           the path env-tests.sh --check calls to see the API answer (/health)
#   écriture        oui: same as « écriture permise »; production: oui; rôle: what it is for (kept, not used)
# A production environment (« production » on its line, « production : oui », or a name that starts with prod, prd,
# live or production: prod, prod-eu, prd1, live_fr; never preprod) is listed as such: no test of the pack ever runs
# there, and writes are never allowed. A URL with a user or a password (the API or the proxy) is refused: its secret
# comes from a variable. Read-only.
# Output: one line per environment, tab-separated:
#           <name> <url> <token variable or -> <writes: yes|no> <production: yes|no> <auth: none|token|oidc>
#         then "WARNING:" lines (a line of the section not understood, a URL with credentials, a secret written as a
#         value, an incomplete OpenID Connect setting)
# Usage: environments.sh [<name>]            with a name: its line only; exit 1 when it is not declared
#        environments.sh --details <name>    its settings, one "key=value" per line (name, url, auth, token_var,
#                                            authority, token_url, client, client_var, secret_var, scope, audience,
#                                            resource, client_auth, proxy, proxy_credentials_var, no_proxy, ca,
#                                            health, writes, production, purpose, invalid), then its WARNING lines;
#                                            exit 1 when it is not declared

LC_ALL=C
export LC_ALL

mode=list want=""
case "$1" in
  --details) mode=details; want=$2; [ -n "$want" ] || { echo "STOP: environments.sh --details <name>"; exit 1; } ;;
  -*) echo "STOP: unknown option $1 (environments.sh [<name>] | --details <name>)"; exit 1 ;;
  *) want=$1 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || root=.
file=$root/AGENTS.md
[ -f "$file" ] || { [ -n "$want" ] && exit 1; exit 0; }
# the file is read twice: the first pass says whether the French heading is there
awk -v want="$want" -v mode="$mode" '
  function trim(s) { gsub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
  # the key of a setting, without accents, case or spaces: « Proxy identifiants » -> proxy-identifiants
  function norm(s) {
    s = tolower(trim(s))
    gsub(/\303\251|\303\250|\303\252|\303\211|\303\210/, "e", s)
    gsub(/\303\240|\303\242/, "a", s)
    gsub(/\303\264/, "o", s)
    gsub(/\303\273|\303\271/, "u", s)
    gsub(/\303\247/, "c", s)
    gsub(/[ \t_]+/, "-", s)
    return s
  }
  function heading(line,   l) {
    l = tolower(line)
    if (l ~ /^## +environnements[ \t]*$/) return "fr"
    if (l ~ /^## +environments[ \t]*$/) return "en"
    return ""
  }
  function isvar(s) { return s ~ /^[A-Za-z_][A-Za-z0-9_]*$/ }
  # the text between the first pair of backquotes, or "" (bq: whether there was one)
  function quoted(s) {
    bq = 0
    if (!match(s, /`[^`]*`/)) return ""
    bq = 1
    return substr(s, RSTART + 1, RLENGTH - 2)
  }
  function firsturl(s) {
    if (!match(s, /https?:\/\/[^ \t`,;()<>"]+/)) return ""
    return substr(s, RSTART, RLENGTH)
  }
  function hascred(u,   h) {
    h = u
    sub(/^https?:\/\//, "", h)
    sub(/\/.*/, "", h)
    return h ~ /@/
  }
  function warn(msg) {
    if (mode == "details") { if (cur == want) warnings = warnings "WARNING: " msg "\n" }
    else print "WARNING: " msg
  }
  function reset() {
    cur = ""; url = ""; tokvar = ""; writes = "no"; prod = "no"; authority = ""; tokurl = ""; client = ""
    clientvar = ""; secretvar = ""; scope = ""; audience = ""; resource = ""; clientauth = "post"; proxy = "system"
    proxycred = ""; noproxy = ""; ca = ""; health = ""; purpose = ""; invalid = ""; skip = 0; warnings = ""
  }
  function prodname(n,   l) {
    l = tolower(n)
    return l ~ /^(prod|prd|live|production)([-_.0-9]|$)/
  }
  function flush(   auth) {
    if (cur == "" || skip) { reset(); return }
    if (prodname(cur)) prod = "yes"
    if (prod == "yes") writes = "no"
    auth = "none"
    if (authority != "" || tokurl != "" || secretvar != "" || clientvar != "" || client != "") auth = "oidc"
    else if (tokvar != "") auth = "token"
    if (auth == "oidc") {
      if (authority == "" && tokurl == "") { warn(cur ": OpenID Connect without its provider (oidc : <authority>, or token-url : <token endpoint>)"); invalid = invalid (invalid == "" ? "" : ",") "oidc" }
      if (client == "" && clientvar == "") { warn(cur ": OpenID Connect without its client id (client : <id>, or client : `<VARIABLE>`)"); invalid = invalid (invalid == "" ? "" : ",") "client" }
      if (secretvar == "" && invalid !~ /secret-value/) { warn(cur ": OpenID Connect without the variable of its client secret (secret : `<VARIABLE>`)"); invalid = invalid (invalid == "" ? "" : ",") "secret" }
    }
    if (seen[cur]++) { warn(cur ": declared twice: the first one counts"); reset(); return }
    if (want == "" || want == cur) {
      found = 1
      if (mode == "details") {
        printf "name=%s\nurl=%s\nauth=%s\ntoken_var=%s\nauthority=%s\ntoken_url=%s\nclient=%s\nclient_var=%s\nsecret_var=%s\n", cur, url, auth, tokvar, authority, tokurl, client, clientvar, secretvar
        printf "scope=%s\naudience=%s\nresource=%s\nclient_auth=%s\nproxy=%s\nproxy_credentials_var=%s\nno_proxy=%s\nca=%s\n", scope, audience, resource, clientauth, proxy, proxycred, noproxy, ca
        printf "health=%s\nwrites=%s\nproduction=%s\npurpose=%s\ninvalid=%s\n", health, writes, prod, purpose, invalid
        printf "%s", warnings
      } else {
        print cur "\t" url "\t" (tokvar == "" ? "-" : tokvar) "\t" writes "\t" prod "\t" auth
      }
    }
    reset()
  }
  # « - `recette` : https://… (jeton : `VAR`, écriture permise) »
  function start(line,   rest, after, low, t) {
    flush()
    cur = quoted(line)
    if (!bq || cur == "") { print_or_keep("not understood (no `name`): " trim(line)); cur = ""; return }
    rest = line
    sub(/^[^`]*`[^`]*`/, "", rest)
    url = firsturl(rest)
    if (url == "") { warn(cur ": no http(s) URL"); skip = 1; return }
    after = substr(rest, index(rest, url) + length(url))
    sub(/\/+$/, "", url)
    if (hascred(url)) { warn(cur ": a user or a password in its URL: never; its secret comes from a variable (jeton : `VARIABLE`, or secret : `VARIABLE`)"); skip = 1; return }
    low = tolower(after)
    if (match(low, /(jeton|token)[^`]*`[^`]*`/)) {
      t = substr(after, RSTART, RLENGTH)
      sub(/`$/, "", t)
      sub(/.*`/, "", t)
      if (isvar(t)) tokvar = t
      else warn(cur ": the token variable is not a variable name: " t)
    }
    if (low ~ /criture permise|writes allowed/) writes = "yes"
    if (low ~ /production/) prod = "yes"
  }
  function print_or_keep(msg) { if (mode != "details") print "WARNING: " msg }
  # « - <setting> : <value> »
  function setting(line,   s, i, key, value, v, q, u) {
    s = line
    sub(/^[ \t]*[-*][ \t]+/, "", s)
    i = index(s, ":")
    if (i == 0) { warn(cur ": setting not understood: " trim(s)); return }
    key = norm(substr(s, 1, i - 1))
    value = trim(substr(s, i + 1))
    q = quoted(value)
    # a comment after the value: « scope : api://x/.default (celui de l API) »
    v = value
    if (!bq) { sub(/[ \t]+(\(|\342\200\224 ).*$/, "", v); v = trim(v) }
    if (key == "oidc" || key == "authority" || key == "autorite" || key == "issuer") {
      u = firsturl(value); sub(/\/+$/, "", u)
      if (u == "") warn(cur ": oidc needs the URL of the authority: " value)
      else if (hascred(u)) warn(cur ": a user or a password in the URL of the authority: never")
      else authority = u
    } else if (key == "token-url" || key == "url-du-jeton" || key == "token-endpoint" || key == "url-jeton") {
      u = firsturl(value)
      if (u == "") warn(cur ": token-url needs the URL of the token endpoint: " value)
      else if (hascred(u)) warn(cur ": a user or a password in the URL of the token endpoint: never")
      else tokurl = u
    } else if (key == "client" || key == "client-id" || key == "clientid" || key == "id-client") {
      if (bq) { if (isvar(q)) clientvar = q; else warn(cur ": the client id variable is not a variable name: " q) }
      else if (v ~ /^[A-Za-z0-9._:\/@-]+$/) client = v
      else warn(cur ": client id not understood: " v)
    } else if (key == "secret" || key == "client-secret" || key == "secret-du-client" || key == "secret-client") {
      if (bq && isvar(q)) secretvar = q
      else { warn(cur ": a secret is never written in AGENTS.md: secret : `<VARIABLE>` names the variable of this machine that holds it"); invalid = invalid (invalid == "" ? "" : ",") "secret-value" }
    } else if (key == "scope" || key == "scopes") {
      scope = bq ? q : v
    } else if (key == "audience") {
      audience = bq ? q : v
    } else if (key == "resource" || key == "ressource") {
      resource = bq ? q : v
    } else if (key == "auth-client" || key == "authentification-du-client" || key == "client-auth" || key == "authentification-client") {
      v = tolower(bq ? q : v)
      if (v ~ /^(post|client_secret_post|in-body|in body|corps)$/) clientauth = "post"
      else if (v ~ /^(basic|client_secret_basic)$/) clientauth = "basic"
      else warn(cur ": auth-client is post or basic: " v)
    } else if (key == "jeton" || key == "token") {
      if (bq && isvar(q)) tokvar = q
      else { warn(cur ": a token is never written in AGENTS.md: jeton : `<VARIABLE>` names the variable of this machine that holds it"); invalid = invalid (invalid == "" ? "" : ",") "token-value" }
    } else if (key == "proxy") {
      v = bq ? q : v
      if (tolower(v) ~ /^(syst\303\250me|systeme|system|machine|d\303\251faut|defaut|default)$/) proxy = "system"
      else if (tolower(v) ~ /^(aucun|none|direct|sans|non|no)$/) proxy = "none"
      else {
        u = firsturl(v)
        if (u == "") { warn(cur ": proxy is système, aucun or http://<host>:<port>: " v); proxy = "invalid"; invalid = invalid (invalid == "" ? "" : ",") "proxy" }
        else if (hascred(u)) { warn(cur ": a user or a password in the URL of the proxy: never; proxy-identifiants : `<VARIABLE>` names the variable that holds <user>:<password>"); proxy = "invalid"; invalid = invalid (invalid == "" ? "" : ",") "proxy" }
        else { sub(/\/+$/, "", u); proxy = u }
      }
    } else if (key == "proxy-identifiants" || key == "identifiants-du-proxy" || key == "proxy-credentials" || key == "identifiants-proxy") {
      if (bq && isvar(q)) proxycred = q
      else { warn(cur ": the proxy credentials are never written in AGENTS.md: proxy-identifiants : `<VARIABLE>`"); invalid = invalid (invalid == "" ? "" : ",") "proxy-credentials-value" }
    } else if (key == "sans-proxy" || key == "no-proxy" || key == "noproxy") {
      noproxy = bq ? q : v
      gsub(/[ \t]+/, "", noproxy)
    } else if (key == "certificat" || key == "ca" || key == "certificate" || key == "autorite-de-certification" || key == "certificats") {
      ca = bq ? q : v
    } else if (key == "sante" || key == "health") {
      health = bq ? q : v
      if (health !~ /^\//) health = "/" health
    } else if (key == "ecriture" || key == "writes") {
      writes = (tolower(bq ? q : v) ~ /^(oui|yes|permise|allowed|true)$/) ? "yes" : "no"
    } else if (key == "production" || key == "prod") {
      if (tolower(bq ? q : v) ~ /^(oui|yes|true)$/) prod = "yes"
    } else if (key == "role" || key == "usage" || key == "description" || key == "but") {
      purpose = bq ? q : v
    } else warn(cur ": setting not understood: " trim(s))
  }
  NR == FNR { if (heading($0) == "fr") fr = 1; next }
  /^## / {
    if (insec) flush()
    h = heading($0)
    insec = (h == "fr") || (h == "en" && !fr)
    if (h == "en" && fr && !told) { told = 1; if (mode != "details") print "WARNING: the section « ## Environments » is not read: « ## Environnements » is (one section, merge them)" }
    next
  }
  !insec { next }
  # an environment: a list item at the start of the line (one space at most)
  /^ ?[-*][ \t]/ { start($0); next }
  # its settings: an indented list item
  /^([ \t][ \t]+|\t)[-*][ \t]/ { if (cur != "" && !skip) setting($0); next }
  END { if (insec) flush(); if (want != "" && !found) exit 1 }
' "$file" "$file"
