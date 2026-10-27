// A real OpenID Connect provider, a real API that checks its tokens, and a real HTTP proxy, on this machine, for the
// tests of env-tests.sh, env-setup.sh and http-files.sh without Docker (tools/environments-test.sh). Node only, no
// package. Everything speaks HTTP for real: curl and .NET go through the proxy, the provider signs RS256 JWTs that the
// API checks with its JWKS (signature, issuer, audience, expiry, roles).
//   provider  /realms/<realm>/.well-known/openid-configuration, /realms/<realm>/protocol/openid-connect/certs and
//             /token (client credentials, client_secret_post or client_secret_basic): invalid_client, a client
//             without service account (unauthorized_client), a scope it does not know (invalid_scope)
//   API       GET /health (anonymous), GET /api/orders (a token of its audience), GET /api/admin (role admin, else 403),
//             401 with WWW-Authenticate: Bearer error="invalid_token", error_description=… as ASP.NET Core says it
//   proxy     CONNECT (https) and absolute URLs (http), Basic credentials when asked (407 otherwise), 403 for the
//             hosts it refuses, 502 for a host it does not know (503 for dnsfail.lab.test, as squid answers a failed
//             lookup); it alone resolves the lab's host names (*.lab.test): a client that does not go through
//             it cannot even resolve them. Each request it forwards is written to its log.
// Usage: node tools/oidc-proxy-lab.mjs <state folder> [--proxy-user <user:password>] [--tls <cert.pem> <key.pem>]
//   writes <state folder>/lab.json (ports, names, clients) once everything listens, and runs until it is killed.
//   Clients (realm "test", audience "acme-api"): tests-recette / s3cr3t-recette (service account, roles orders.read),
//   tests-admin / s3cr3t-admin (roles orders.read, admin), no-sa / s3cr3t-nosa (no service account), tests-other /
//   s3cr3t-other (its tokens are for the audience other-api: the API refuses them), legacy / s3cr3t-legacy (a wrong
//   secret answered unauthorized_client, as older Keycloak versions did). GET /down answers 503; GET /waking answers 503
//   once, then 200 (an environment that restarts: the retry of env-tests.sh). Scopes known:
//   openid, profile, email, api://acme-api/.default. Access tokens live 300 s (Keycloak's default).
import { createServer as http } from "node:http"
import { createServer as https } from "node:https"
import { connect, createServer as tcp } from "node:net"
import { generateKeyPairSync, randomUUID, sign, verify } from "node:crypto"
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"

const state = process.argv[2]
if (!state) {
  console.error("usage: node oidc-proxy-lab.mjs <state folder> [--proxy-user <user:password>] [--tls <cert> <key>]")
  process.exit(2)
}
mkdirSync(state, { recursive: true })
const arg = (name) => {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv.slice(i + 1, i + 3) : undefined
}
const proxyUser = (arg("--proxy-user") || [])[0]
const tls = arg("--tls")
const log = (line) => appendFileSync(join(state, "proxy.log"), line + "\n")

// ---------- the provider ----------
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 })
const kid = randomUUID()
const jwk = { ...publicKey.export({ format: "jwk" }), kid, use: "sig", alg: "RS256" }
const b64 = (data) => Buffer.from(typeof data === "string" ? data : JSON.stringify(data)).toString("base64url")
const CLIENTS = {
  "tests-recette": { secret: "s3cr3t-recette", serviceAccount: true, roles: ["orders.read"] },
  "tests-admin": { secret: "s3cr3t-admin", serviceAccount: true, roles: ["orders.read", "admin"] },
  "no-sa": { secret: "s3cr3t-nosa", serviceAccount: false, roles: [] },
  // a client whose tokens are for another API (the API refuses them: its audience)
  "tests-other": { secret: "s3cr3t-other", serviceAccount: true, roles: ["orders.read"], audience: "other-api" },
  // a provider that answers a wrong secret as older Keycloak versions did (unauthorized_client, "Invalid client secret")
  legacy: { secret: "s3cr3t-legacy", serviceAccount: true, roles: ["orders.read"], legacyErrors: true },
}
const SCOPES = new Set(["openid", "profile", "email", "api://acme-api/.default"])
const AUDIENCE = "acme-api"
const LIFETIME = 300
let issuerBase = ""
function token(clientId, scope) {
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: "RS256", typ: "JWT", kid }
  const payload = {
    iss: issuerBase + "/realms/test", aud: CLIENTS[clientId].audience || AUDIENCE, azp: clientId, sub: "service-account-" + clientId, iat: now,
    exp: now + LIFETIME, jti: randomUUID(), scope: scope || "profile email", roles: CLIENTS[clientId].roles,
  }
  const body = b64(header) + "." + b64(payload)
  return body + "." + sign("sha256", Buffer.from(body), privateKey).toString("base64url")
}
function checkToken(auth) {
  const m = /^Bearer\s+([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/.exec(auth || "")
  if (!m) return { error: "invalid_token", description: "The token is missing or is not a JWT" }
  const ok = verify("sha256", Buffer.from(m[1] + "." + m[2]), publicKey, Buffer.from(m[3], "base64url"))
  if (!ok) return { error: "invalid_token", description: "The signature is invalid" }
  const payload = JSON.parse(Buffer.from(m[2], "base64url").toString())
  if (payload.iss !== issuerBase + "/realms/test") return { error: "invalid_token", description: `The issuer '${payload.iss}' is invalid` }
  if (payload.aud !== AUDIENCE) return { error: "invalid_token", description: `The audience '${payload.aud}' is invalid` }
  if (payload.exp < Date.now() / 1000) return { error: "invalid_token", description: "The token expired" }
  return { payload }
}
const json = (res, status, data, headers = {}) => {
  res.writeHead(status, { "Content-Type": "application/json", ...headers })
  res.end(JSON.stringify(data))
}
async function body(req) {
  let text = ""
  for await (const chunk of req) text += chunk
  return text
}
const provider = (base) => async (req, res) => {
  const url = new URL(req.url, base)
  if (url.pathname === "/realms/test/.well-known/openid-configuration") {
    return json(res, 200, {
      issuer: base + "/realms/test",
      token_endpoint: base + "/realms/test/protocol/openid-connect/token",
      jwks_uri: base + "/realms/test/protocol/openid-connect/certs",
      grant_types_supported: ["client_credentials"],
      token_endpoint_auth_methods_supported: ["client_secret_post", "client_secret_basic"],
    })
  }
  if (url.pathname === "/realms/test/protocol/openid-connect/certs") return json(res, 200, { keys: [jwk] })
  if (url.pathname === "/realms/test/protocol/openid-connect/token" && req.method === "POST") {
    const form = new URLSearchParams(await body(req))
    let id = form.get("client_id")
    let secret = form.get("client_secret")
    const basic = /^Basic\s+(.+)$/.exec(req.headers.authorization || "")
    if (basic) {
      const [u, p] = Buffer.from(basic[1], "base64").toString().split(":")
      id = decodeURIComponent(u)
      secret = decodeURIComponent(p || "")
    }
    if (form.get("grant_type") !== "client_credentials") return json(res, 400, { error: "unsupported_grant_type" })
    const client = CLIENTS[id]
    if (client && client.legacyErrors && client.secret !== secret) return json(res, 400, { error: "unauthorized_client", error_description: "Invalid client secret" })
    if (!client || client.secret !== secret) return json(res, 401, { error: "invalid_client", error_description: "Invalid client or Invalid client credentials" })
    if (!client.serviceAccount) return json(res, 400, { error: "unauthorized_client", error_description: "Client not enabled to retrieve service account" })
    const scope = form.get("scope") || ""
    const unknown = scope.split(/\s+/).filter((s) => s && !SCOPES.has(s))
    if (unknown.length) return json(res, 400, { error: "invalid_scope", error_description: "Invalid scopes: " + unknown.join(" ") })
    log(`token ${id} ${basic ? "basic" : "post"} scope=${scope || "-"}`)
    return json(res, 200, { access_token: token(id, scope), expires_in: LIFETIME, token_type: "Bearer", scope: scope || "profile email" })
  }
  json(res, 404, { error: "not found" })
}
let waking = 0
const api = async (req, res) => {
  const url = new URL(req.url, "http://api")
  if (url.pathname === "/health") return json(res, 200, { status: "Healthy" })
  // an environment down behind its gateway
  if (url.pathname === "/down") return json(res, 503, { error: "Service Unavailable" })
  // an environment that restarts: its first answer is a 503
  if (url.pathname === "/waking") {
    waking += 1
    return waking === 1 ? json(res, 503, { error: "Service Unavailable" }) : json(res, 200, { status: "Healthy" })
  }
  if (url.pathname === "/api/orders" || url.pathname === "/api/admin") {
    const check = checkToken(req.headers.authorization)
    if (check.error) {
      res.writeHead(401, { "WWW-Authenticate": `Bearer error="${check.error}", error_description="${check.description}"` })
      return res.end()
    }
    if (url.pathname === "/api/admin" && !check.payload.roles.includes("admin")) {
      res.writeHead(403)
      return res.end()
    }
    return json(res, 200, url.pathname === "/api/orders" ? [{ id: 1, total: 12.5 }] : { admin: true })
  }
  json(res, 404, { error: "not found" })
}

// ---------- listen: the provider and the API in plain HTTP, and in TLS when a certificate is given ----------
const listen = (server) => new Promise((done) => server.listen(0, "127.0.0.1", () => done(server.address().port)))
const routes = new Map()
const idpPort = await listen(http((req, res) => provider("http://idp.lab.test")(req, res)))
const apiPort = await listen(http(api))
routes.set("idp.lab.test", idpPort)
routes.set("api.lab.test", apiPort)
issuerBase = "http://idp.lab.test"
let tlsPorts = {}
if (tls) {
  const options = { cert: readFileSync(tls[0]), key: readFileSync(tls[1]) }
  const idps = await listen(https(options, (req, res) => provider("https://idps.lab.test")(req, res)))
  const apis = await listen(https(options, api))
  routes.set("idps.lab.test", idps)
  routes.set("apis.lab.test", apis)
  tlsPorts = { idps, apis }
}

// ---------- the proxy ----------
const REFUSED = new Set(["blocked.lab.test"])
// a name whose lookup fails at the proxy: squid answers 503 (ERR_DNS_FAIL) where other proxies answer 502
const DNS_FAIL = new Set(["dnsfail.lab.test"])
function authorized(req) {
  if (!proxyUser) return true
  const m = /^Basic\s+(.+)$/.exec(req.headers["proxy-authorization"] || "")
  return !!m && Buffer.from(m[1], "base64").toString() === proxyUser
}
// a lab host goes to its port on 127.0.0.1 (as https on 443 or http on 80); any other host is unknown
const target = (host, port) => {
  const lab = routes.get(host)
  if (lab) return { host: "127.0.0.1", port: lab }
  return undefined
}
const proxy = http(async (req, res) => {
  // a plain http request through the proxy: an absolute URL
  if (!authorized(req)) {
    log(`407 ${req.method} ${req.url}`)
    res.writeHead(407, { "Proxy-Authenticate": 'Basic realm="lab"' })
    return res.end()
  }
  let url
  try {
    url = new URL(req.url)
  } catch {
    res.writeHead(400)
    return res.end()
  }
  if (REFUSED.has(url.hostname)) {
    log(`403 ${req.method} ${url.hostname}`)
    res.writeHead(403)
    return res.end()
  }
  const to = target(url.hostname, url.port)
  if (!to) {
    log(`502 ${req.method} ${url.hostname}`)
    res.writeHead(502)
    return res.end()
  }
  log(`http ${req.method} ${url.hostname}${url.pathname}`)
  const headers = { ...req.headers }
  delete headers["proxy-authorization"]
  delete headers["proxy-connection"]
  const upstream = (await import("node:http")).request({ host: to.host, port: to.port, method: req.method, path: url.pathname + url.search, headers }, (up) => {
    res.writeHead(up.statusCode, up.headers)
    up.pipe(res)
  })
  upstream.on("error", () => {
    res.writeHead(502)
    res.end()
  })
  req.pipe(upstream)
})
proxy.on("connect", (req, socket, head) => {
  const [host] = String(req.url).split(":")
  if (!authorized(req)) {
    log(`407 CONNECT ${host}`)
    socket.end('HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="lab"\r\nContent-Length: 0\r\n\r\n')
    return
  }
  if (REFUSED.has(host)) {
    log(`403 CONNECT ${host}`)
    socket.end("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
    return
  }
  if (DNS_FAIL.has(host)) {
    log(`503 CONNECT ${host}`)
    socket.end("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n")
    return
  }
  const to = target(host)
  if (!to) {
    log(`502 CONNECT ${host}`)
    socket.end("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
    return
  }
  log(`connect ${host}`)
  const upstream = connect(to.port, to.host, () => {
    socket.write("HTTP/1.1 200 Connection Established\r\n\r\n")
    if (head && head.length) upstream.write(head)
    upstream.pipe(socket)
    socket.pipe(upstream)
  })
  upstream.on("error", () => socket.destroy())
  socket.on("error", () => upstream.destroy())
})
const proxyPort = await listen(proxy)
// a port where nothing listens (the connection is refused)
const spare = tcp()
const closed = await listen(spare)
await new Promise((done) => spare.close(done))
const lab = {
  proxy: `http://127.0.0.1:${proxyPort}`,
  authority: "http://idp.lab.test/realms/test",
  api: "http://api.lab.test",
  authorityTls: tls ? "https://idps.lab.test/realms/test" : "",
  apiTls: tls ? "https://apis.lab.test" : "",
  direct: { idp: `http://127.0.0.1:${idpPort}`, api: `http://127.0.0.1:${apiPort}`, ...tlsPorts },
  closedPort: closed,
}
writeFileSync(join(state, "lab.json"), JSON.stringify(lab, null, 2))
process.on("SIGTERM", () => process.exit(0))
process.on("SIGINT", () => process.exit(0))
