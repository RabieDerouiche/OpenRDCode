#!/bin/sh
# /tests api, /tests env and /outil http in a real situation: the real .NET SDKs 10 and 8, and real servers in Docker:
# an OpenID Connect provider (Keycloak), a company proxy that asks credentials (squid, Basic), an internal certificate
# authority, SQL Server, and an ASP.NET Core API deployed behind the proxy that checks the tokens of Keycloak (JwtBearer:
# signature, issuer, audience, roles). The API and the provider are on an internal Docker network: from this machine,
# their names resolve only through the proxy, as an environment reached through the proxy of a company.
#   - /tests api on a realistic API (settings read at start, a worker, a DbContext its endpoints use, a scheme named by
#     an endpoint): api-preflight.sh names them; the first factory of the skill api-tests cannot start it;
#     test-guardian.sh setup --integration --db sqlite, then the factory of the skill that handles them: the tests in
#     memory pass, on .NET 10 (EF Core 10) and on .NET 8 (EF Core 8, public partial class Program added by the setup)
#   - /tests env config: env-setup.sh scan (what the code says) and set (the block of AGENTS.md, the token URL read
#     through the proxy), env-tests.sh --check (variables, proxy, certificate, provider, token and its claims, the API)
#   - /tests env: env-tests.sh, read only then --ecriture, the environment tests of the skill on the deployed API with a
#     token of Keycloak asked through the proxy; the client of the skill alone (API_OIDC_* only: post, then basic)
#   - what goes wrong, each with its ENVIRONMENT PROBLEM line: a wrong secret, a client without service account, a scope
#     the provider does not know, a token for another audience, a wrong proxy password, no proxy, no certificate
#     authority, a host the proxy forbids, a name it cannot resolve, a variable not set, the API stopped; and the
#     messages of .NET that env-tests.sh reads (the 407 of the proxy tunnel, an unknown name, a certificate not trusted)
#   - /outil http: the requests written for Rider (OAuth 2.0 client credentials of its HTTP client), sent as Rider sends
#     them: the token asked as their Security.Auth says, through the proxy, each GET answered by the deployed API; their
#     private file filled by http-files.sh --private, from a variable and from HashiCorp Vault
#   - HashiCorp Vault (a real Vault server and its own CLI): the secret of the client and the credentials of the proxy
#     kept there (env-setup.sh --vault, --proxy-vault), read by env-tests.sh with a token whose policy gives them, and
#     what Vault answers otherwise (no token, a token of another policy, a path or a field that does not exist)
# The secrets of the lab (client secrets, a proxy password with characters that need encoding) and the tokens are never
# printed by the pack's scripts: every output is checked for them.
# Needs Docker, the .NET 10 and 8 SDKs, curl, openssl, node and git, and the registries (quay.io, mcr.microsoft.com,
# Docker Hub, the Ubuntu archive, nuget.org): the CI. Only Docker objects named openrd-lab-<pid> are created, and removed
# at the end; OIDC_LAB_LOGS=<folder> keeps the logs of the servers there.
# Usage, from opencode-v2/: sh tools/oidc-real-test.sh [<shell>] (default sh).
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
for c in docker dotnet curl openssl node git; do
  command -v "$c" >/dev/null 2>&1 || { echo "oidc-real-test: $c is not on the PATH of this machine"; exit 2; }
done
docker info >/dev/null 2>&1 || { echo "oidc-real-test: the Docker daemon does not answer"; exit 2; }

# the images, and the versions of the packages of the API (ASP.NET Core and EF Core of each .NET)
KEYCLOAK_IMAGE=quay.io/keycloak/keycloak:26.6.1
VAULT_IMAGE=hashicorp/vault:1.17
SQL_IMAGE=mcr.microsoft.com/mssql/server:2022-latest
ASPNET_IMAGE=mcr.microsoft.com/dotnet/aspnet:10.0
UBUNTU_IMAGE=ubuntu:24.04
V10=10.0.0
V8=8.0.11

work=$(mktemp -d "${TMPDIR:-/tmp}/oidc-real-test.XXXXXX") || exit 1
chmod 755 "$work"
lab=openrd-lab-$$
keep=${OIDC_LAB_LOGS:-}
cleanup() {
  if [ -n "$keep" ]; then
    mkdir -p "$keep"
    for c in idp api sql squid vault; do docker logs "$lab-$c" > "$keep/$c.log" 2>&1; done
    docker exec "$lab-squid" cat /var/log/squid/access.log > "$keep/squid-access.log" 2>&1
    docker exec "$lab-squid" cat /var/log/squid/cache.log > "$keep/squid-cache.log" 2>&1
  fi
  docker rm -f "$lab-idp" "$lab-api" "$lab-sql" "$lab-squid" "$lab-vault" > /dev/null 2>&1
  docker network rm "$lab-int" "$lab-edge" > /dev/null 2>&1
  docker image rm "$lab-squid" > /dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
mkdir -p "$work/tmp"
TMPDIR="$work/tmp"
MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_UI_LANGUAGE=en
export TMPDIR MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO DOTNET_CLI_UI_LANGUAGE
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
# the pauses of the retries of the scripts (transient.sh): none, a check of a failure that passes by itself does not wait
RETRY_PAUSES="0 0"
export RETRY_PAUSES
printf '[init]\n\tdefaultBranch = develop\n' > "$GIT_CONFIG_GLOBAL"
# no proxy of this machine: the proxy of the lab is the one of the environments
unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy NO_PROXY no_proxy
echo "oidc-real-test: SDKs $(dotnet --list-sdks | awk '{ printf "%s%s", sep, $1; sep = ", " }'); Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
started=$(date +%s)
# note <what> <output>: its TESTS line, as a NOTE of the run (what really ran, in the annotations of the CI)
note() { echo "NOTE: $1: $(printf '%s\n' "$2" | grep -m 1 -E '^TESTS: ' || echo "no TESTS line")"; }

pass=0
fail=0
check() {
  # check <name> <expected exit: 0|1|any> <grep pattern of the output> [<pattern that must not appear>]
  name=$1 want=$2 pattern=$3 absent=$4
  ok=1
  case "$want" in
    any) ;;
    0) [ "$status" -eq 0 ] || ok=0 ;;
    *) [ "$status" -ne 0 ] || ok=0 ;;
  esac
  printf '%s\n' "$out" | grep -qE -- "$pattern" || ok=0
  [ -n "$absent" ] && printf '%s\n' "$out" | grep -qE -- "$absent" && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /' | tail -n 60
  fi
}
verdict() {
  # verdict <name> <exit status of the condition, just run>
  if [ "$2" -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi
}
run() {
  script=$1
  shift
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
}
commit() { git add -A >/dev/null 2>&1 && git commit -q -m x >/dev/null 2>&1; }
# stop <message> [<log file>]: the lab cannot be used, nothing after this makes sense
stop() {
  fail=$((fail + 1))
  echo "FAIL: $1"
  [ -n "$2" ] && [ -f "$2" ] && tail -n 40 "$2" | sed 's/^/    /'
  echo "oidc-real-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
  exit 1
}
urlenc() {
  printf '%s' "$1" | awk 'BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i }
    { for (i = 1; i <= length($0); i++) { c = substr($0, i, 1); if (c ~ /[A-Za-z0-9._~-]/) printf "%s", c; else printf "%%%02X", ord[c] } }'
}

# ---------- the secrets of the lab, and what no output of the pack may contain ----------
SECRET_TESTS=$(openssl rand -hex 20) SECRET_ADMIN=$(openssl rand -hex 20)
SECRET_NOSA=$(openssl rand -hex 20) SECRET_OTHER=$(openssl rand -hex 20)
PROXY_USER=tester
PROXY_PASS='Pr0xy@Lab:20#26!%'
SQL_PASS="Lab-$(openssl rand -hex 12)-Sql1"
SECRETS="$SECRET_TESTS|$SECRET_ADMIN|$SECRET_NOSA|$SECRET_OTHER|Pr0xy@Lab|Pr0xy%40Lab|eyJ[A-Za-z0-9_-]{16,}\\.eyJ"

# ---------- the internal certificate authority, and the certificates of the provider and of the API ----------
pki="$work/lab/certs"
mkdir -p "$pki"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=OpenRD Lab Internal CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -keyout "$pki/ca.key" -out "$pki/ca.pem" > "$work/pki.log" 2>&1 || stop "openssl: the certificate authority" "$work/pki.log"
for h in idp api; do
  openssl req -newkey rsa:2048 -nodes -subj "/CN=$h.lab.test" -keyout "$pki/$h.key" -out "$pki/$h.csr" >> "$work/pki.log" 2>&1
  printf 'subjectAltName=DNS:%s.lab.test\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' "$h" > "$pki/$h.ext"
  openssl x509 -req -in "$pki/$h.csr" -CA "$pki/ca.pem" -CAkey "$pki/ca.key" -CAcreateserial -days 2 \
    -extfile "$pki/$h.ext" -out "$pki/$h.pem" >> "$work/pki.log" 2>&1 || stop "openssl: the certificate of $h.lab.test" "$work/pki.log"
done
# what the API trusts to reach the provider: the authorities of the system and the internal one
cat /etc/ssl/certs/ca-certificates.crt "$pki/ca.pem" > "$pki/bundle.pem"
chmod 755 "$work/lab" "$pki"
chmod 644 "$pki"/*

# ---------- the provider: realm acme, its clients ----------
# shop-tests: service account, its tokens for the audience shop-api; shop-admin: the same, with the role orders-admin
# (client_secret_basic in the tests); shop-noservice: no service account; other-app: tokens without the audience shop-api
mkdir -p "$work/lab/realm"
mapper_aud='{ "name": "audience shop-api", "protocol": "openid-connect", "protocolMapper": "oidc-audience-mapper", "config": { "included.custom.audience": "shop-api", "access.token.claim": "true", "id.token.claim": "false" } }'
mapper_roles='{ "name": "realm roles", "protocol": "openid-connect", "protocolMapper": "oidc-usermodel-realm-role-mapper", "config": { "claim.name": "roles", "jsonType.label": "String", "multivalued": "true", "access.token.claim": "true", "id.token.claim": "false", "userinfo.token.claim": "false" } }'
cat > "$work/lab/realm/acme.json" <<EOF
{
  "realm": "acme",
  "enabled": true,
  "sslRequired": "external",
  "accessTokenLifespan": 300,
  "roles": { "realm": [ { "name": "orders-admin", "description": "Reads the statistics of the orders" } ] },
  "clients": [
    { "clientId": "shop-tests", "enabled": true, "protocol": "openid-connect", "publicClient": false,
      "clientAuthenticatorType": "client-secret", "secret": "$SECRET_TESTS", "serviceAccountsEnabled": true,
      "standardFlowEnabled": false, "implicitFlowEnabled": false, "directAccessGrantsEnabled": false,
      "protocolMappers": [ $mapper_aud, $mapper_roles ] },
    { "clientId": "shop-admin", "enabled": true, "protocol": "openid-connect", "publicClient": false,
      "clientAuthenticatorType": "client-secret", "secret": "$SECRET_ADMIN", "serviceAccountsEnabled": true,
      "standardFlowEnabled": false, "implicitFlowEnabled": false, "directAccessGrantsEnabled": false,
      "protocolMappers": [ $mapper_aud, $mapper_roles ] },
    { "clientId": "shop-noservice", "enabled": true, "protocol": "openid-connect", "publicClient": false,
      "clientAuthenticatorType": "client-secret", "secret": "$SECRET_NOSA", "serviceAccountsEnabled": false,
      "standardFlowEnabled": true, "redirectUris": [ "https://localhost:7043/*" ], "directAccessGrantsEnabled": false },
    { "clientId": "other-app", "enabled": true, "protocol": "openid-connect", "publicClient": false,
      "clientAuthenticatorType": "client-secret", "secret": "$SECRET_OTHER", "serviceAccountsEnabled": true,
      "standardFlowEnabled": false, "implicitFlowEnabled": false, "directAccessGrantsEnabled": false }
  ],
  "users": [
    { "username": "service-account-shop-admin", "enabled": true, "serviceAccountClientId": "shop-admin",
      "realmRoles": [ "orders-admin" ] }
  ]
}
EOF
chmod 755 "$work/lab/realm"
chmod 644 "$work/lab/realm/acme.json"

# ---------- the proxy: squid, Basic credentials, a forbidden host; the names of the lab are resolved by it only ----------
mkdir -p "$work/lab/squid"
cat > "$work/lab/squid/Dockerfile" <<EOF
FROM $UBUNTU_IMAGE
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends squid > /dev/null && rm -rf /var/lib/apt/lists/*
COPY squid.conf /etc/squid/squid.conf
COPY lab.passwd /etc/squid/lab.passwd
CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
EOF
cat > "$work/lab/squid/squid.conf" <<'EOF'
http_port 3128
pid_filename none
cache deny all
access_log stdio:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
logfile_rotate 0
positive_dns_ttl 1 second
negative_dns_ttl 1 second
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/lab.passwd
auth_param basic children 3
auth_param basic realm lab
acl SSL_ports port 443 8443
acl Safe_ports port 80 443 8080 8443
acl CONNECT method CONNECT
acl blocked dstdomain blocked.lab.test
acl lab_users proxy_auth REQUIRED
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny blocked
http_access allow lab_users
http_access deny all
EOF
printf '%s:%s\n' "$PROXY_USER" "$(printf '%s\n' "$PROXY_PASS" | openssl passwd -apr1 -stdin)" > "$work/lab/squid/lab.passwd"

# ---------- the lab: an internal network (the API, the provider, the database) and the proxy, the only way in ----------
docker network create --internal "$lab-int" > "$work/docker.log" 2>&1 || stop "docker network create --internal" "$work/docker.log"
docker network create "$lab-edge" >> "$work/docker.log" 2>&1 || stop "docker network create" "$work/docker.log"
printf 'ACCEPT_EULA=Y\nMSSQL_SA_PASSWORD=%s\n' "$SQL_PASS" > "$work/lab/sql.env"
docker run -d --name "$lab-sql" --network "$lab-int" --network-alias sql.lab.test --env-file "$work/lab/sql.env" \
  "$SQL_IMAGE" >> "$work/docker.log" 2>&1 || stop "SQL Server ($SQL_IMAGE)" "$work/docker.log"
docker run -d --name "$lab-idp" --network "$lab-int" --network-alias idp.lab.test \
  -v "$pki:/certs:ro" -v "$work/lab/realm:/opt/keycloak/data/import:ro" \
  -e KC_HTTPS_CERTIFICATE_FILE=/certs/idp.pem -e KC_HTTPS_CERTIFICATE_KEY_FILE=/certs/idp.key \
  "$KEYCLOAK_IMAGE" start-dev --import-realm >> "$work/docker.log" 2>&1 || stop "Keycloak ($KEYCLOAK_IMAGE)" "$work/docker.log"
docker build -q -t "$lab-squid" "$work/lab/squid" > "$work/squid-build.log" 2>&1 || stop "the image of squid ($UBUNTU_IMAGE + squid)" "$work/squid-build.log"
docker run -d --name "$lab-squid" --network "$lab-edge" -p 127.0.0.1::3128 "$lab-squid" >> "$work/docker.log" 2>&1 || stop "squid" "$work/docker.log"
docker network connect "$lab-int" "$lab-squid" >> "$work/docker.log" 2>&1 || stop "squid on the internal network" "$work/docker.log"
pport=$(docker port "$lab-squid" 3128/tcp | head -n 1 | sed 's/.*://')
P="http://127.0.0.1:$pport"
CRED="$PROXY_USER:$PROXY_PASS"
# lab_curl <url> [<curl options>]: through the proxy of the lab with its credentials (by standard input, with the
# header LAB_HEADER when it is set), its CA trusted
lab_curl() {
  u=$1
  shift
  {
    printf 'proxy = "%s"\nproxy-user = "%s"\n' "$P" "$CRED"
    [ -n "${LAB_HEADER:-}" ] && printf 'header = "%s"\n' "$LAB_HEADER"
  } | curl -K - -sS --cacert "$pki/ca.pem" --max-time 20 "$@" "$u"
}
# wait_for <what> <seconds> <command...>: until the command succeeds
wait_for() {
  what=$1 limit=$2
  shift 2
  t=0
  until "$@" > /dev/null 2>&1; do
    t=$((t + 3))
    [ "$t" -le "$limit" ] || return 1
    sleep 3
  done
  echo "NOTE: $what ready after ${t} s"
  return 0
}
proxy_asks() { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -x "$P" http://idp.lab.test:8080/)" = 407 ]; }
wait_for "squid" 60 proxy_asks || stop "squid does not answer on $P" "$work/docker.log"
proxy_asks
verdict "the proxy asks credentials (407 without them)" $?
echo "NOTE: $(docker exec "$lab-squid" squid -v 2>/dev/null | head -n 1); $KEYCLOAK_IMAGE; $SQL_IMAGE"

# ---------- the API of the repositories: a shop, its settings, its worker, its DbContext, its endpoints ----------
# shop_repo <folder> <target framework> <version of ASP.NET Core and EF Core>
shop_repo() {
  dir=$1 tfm=$2 v=$3
  mkdir -p "$dir/src/Shop.Api/Properties" "$dir/certs"
  cd "$dir" || exit 1
  git init -q .
  printf 'bin/\nobj/\n' > .gitignore
  cat > src/Shop.Api/Shop.Api.csproj <<EOF
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="$v" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="$v" />
  </ItemGroup>
</Project>
EOF
  cat > src/Shop.Api/Program.cs <<'EOF'
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Shop.Api;

var builder = WebApplication.CreateBuilder(args);

// what the API cannot start without: given by the environment where it runs
var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException("ConnectionStrings:Default is missing");
var paymentsUrl = builder.Configuration["Payments:BaseUrl"] ?? throw new InvalidOperationException("Payments:BaseUrl is missing");

builder.Services.AddDbContext<ShopDbContext>(options => options.UseSqlServer(connectionString));
builder.Services.AddHttpClient("payments", client => client.BaseAddress = new Uri(paymentsUrl));
builder.Services.AddHostedService<OutboxWorker>();
builder.Services.AddHealthChecks();
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Oidc:Authority"];
        options.Audience = builder.Configuration["Oidc:Audience"];
        options.MapInboundClaims = false;
        options.TokenValidationParameters.RoleClaimType = "roles";
    });
builder.Services.AddAuthorization(options =>
    options.AddPolicy("OrdersAdmin", policy => policy.RequireRole("orders-admin")));

var app = builder.Build();
if (app.Configuration.GetValue<bool>("Database:CreateAtStart"))
{
    using var scope = app.Services.CreateScope();
    scope.ServiceProvider.GetRequiredService<ShopDbContext>().Database.EnsureCreated();
}
app.UseAuthentication();
app.UseAuthorization();
app.MapHealthChecks("/health");
app.MapOrders();
app.Run();
EOF
  cat > src/Shop.Api/OrdersEndpoints.cs <<'EOF'
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;

namespace Shop.Api;

public record OrderDto(int Id, string Customer, decimal Total);

public record CreateOrder(string? Customer, decimal Total);

public static class OrdersEndpoints
{
    public static void MapOrders(this IEndpointRouteBuilder app)
    {
        var orders = app.MapGroup("/api/orders").RequireAuthorization();
        orders.MapGet("/", async (ShopDbContext db) =>
            await db.Orders.OrderBy(o => o.Id).Select(o => new OrderDto(o.Id, o.Customer, o.Total)).ToListAsync());
        orders.MapGet("/{id:int}", async (int id, ShopDbContext db) =>
            await db.Orders.FindAsync(id) is { } order ? Results.Ok(new OrderDto(order.Id, order.Customer, order.Total)) : Results.NotFound());
        orders.MapGet("/export", async (ShopDbContext db) =>
                Results.Text(string.Join('\n', (await db.Orders.OrderBy(o => o.Id).ToListAsync()).Select(o => $"{o.Id};{o.Customer};{o.Total}")), "text/csv"))
            .RequireAuthorization(new AuthorizeAttribute { AuthenticationSchemes = "Bearer" });
        orders.MapPost("/", async (CreateOrder request, ShopDbContext db) =>
        {
            var errors = new Dictionary<string, string[]>();
            if (string.IsNullOrWhiteSpace(request.Customer))
                errors["customer"] = ["The customer is required."];
            if (request.Total <= 0)
                errors["total"] = ["The total must be greater than 0."];
            if (errors.Count > 0)
                return Results.ValidationProblem(errors);
            var order = new Order { Customer = request.Customer!, Total = request.Total };
            db.Orders.Add(order);
            await db.SaveChangesAsync();
            return Results.Created($"/api/orders/{order.Id}", new OrderDto(order.Id, order.Customer, order.Total));
        });
        orders.MapDelete("/{id:int}", async (int id, ShopDbContext db) =>
        {
            if (await db.Orders.FindAsync(id) is not { } order)
                return Results.NotFound();
            db.Orders.Remove(order);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
        app.MapGet("/api/admin/stats", async (ShopDbContext db) => Results.Ok(new { orders = await db.Orders.CountAsync() }))
            .RequireAuthorization("OrdersAdmin");
    }
}
EOF
  cat > src/Shop.Api/ShopDbContext.cs <<'EOF'
using Microsoft.EntityFrameworkCore;

namespace Shop.Api;

public class ShopDbContext(DbContextOptions<ShopDbContext> options) : DbContext(options)
{
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Order>(order =>
        {
            order.Property(o => o.Customer).HasMaxLength(100);
            order.Property(o => o.Total).HasPrecision(10, 2);
            order.HasData(new Order { Id = 1, Customer = "Ada", Total = 12.50m, Sent = true });
        });
    }
}

public class Order
{
    public int Id { get; set; }
    public string Customer { get; set; } = "";
    public decimal Total { get; set; }
    public bool Sent { get; set; }
}
EOF
  cat > src/Shop.Api/OutboxWorker.cs <<'EOF'
using Microsoft.EntityFrameworkCore;

namespace Shop.Api;

// Sends the new orders to the payment service, every 5 seconds
public sealed class OutboxWorker(IServiceScopeFactory scopes, IHttpClientFactory clients, ILogger<OutboxWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ShopDbContext>();
                foreach (var order in await db.Orders.Where(o => !o.Sent).ToListAsync(stoppingToken))
                {
                    using var response = await clients.CreateClient("payments").PostAsJsonAsync("/payments", new { order.Id, order.Total }, stoppingToken);
                    response.EnsureSuccessStatusCode();
                    order.Sent = true;
                }
                await db.SaveChangesAsync(stoppingToken);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                logger.LogWarning(error, "The outbox could not send the new orders");
            }
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }
}
EOF
  cat > src/Shop.Api/appsettings.json <<'EOF'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "Oidc": {
    "Authority": "https://idp.lab.test:8443/realms/acme",
    "Audience": "shop-api"
  }
}
EOF
  cat > src/Shop.Api/Properties/launchSettings.json <<'EOF'
{
  "profiles": {
    "https": {
      "commandName": "Project",
      "applicationUrl": "https://localhost:7043;http://localhost:5043",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
EOF
  # the internal certificate authority of the company, committed with the code (a public certificate, never a key)
  cp "$pki/ca.pem" certs/lab-ca.pem
  printf '# Shop\n\nThe API of the shop: ASP.NET Core, SQL Server, Keycloak.\n\n## Build\n- `dotnet build`, `dotnet test`\n' > AGENTS.md
  if [ "$tfm" = net8.0 ] && dotnet --list-sdks | grep -q '^8\.'; then
    printf '{\n  "sdk": { "version": "8.0.100", "rollForward": "latestFeature" }\n}\n' > global.json
  fi
  { dotnet new sln -n Shop && dotnet sln add src/Shop.Api/Shop.Api.csproj; } > "$work/sln.log" 2>&1 || echo "NOTE: no solution in $dir ($(tail -n 1 "$work/sln.log"))"
  commit
}

# the code blocks of the skill api-tests, in order: 1 the factory, 2 the test authentication, 3 the factory of an API
# with settings at start, a worker and a DbContext, 4 the environment attribute, 5 the environment client, 6 tests on
# an environment
blocks="$work/blocks"
mkdir -p "$blocks"
awk -v dir="$blocks" '
  /^ *```[a-z]+$/ { n++; inblock = 1; file = dir "/" n; next }
  /^ *```$/ && inblock { inblock = 0; close(file); next }
  inblock { sub(/^   /, ""); print > file }' "$pack/skills/api-tests/SKILL.md"
[ -s "$blocks/6" ] && [ ! -e "$blocks/7" ]
verdict "the skill api-tests has its 6 code blocks" $?

# the tests of the developer: in memory (the data in SQLite, the authentication of the test handler), and on an
# environment (401 without a token, an order created then deleted when writes are allowed)
write_tests() {
  t=$1
  cat > "$t/OrdersEndpointsTests.cs" <<'EOF'
using System.Net;
using System.Net.Http.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Shop.Api;
using Xunit;

public class OrdersEndpointsTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory factory;

    public OrdersEndpointsTests(ApiFactory factory) => this.factory = factory;

    private HttpClient User(string? roles = null)
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add(TestAuthHandler.UserHeader, "dev");
        if (roles is not null)
            client.DefaultRequestHeaders.Add(TestAuthHandler.RolesHeader, roles);
        return client;
    }

    [Fact]
    public async Task Get_Orders_WithoutUser_Returns401()
    {
        var response = await factory.CreateClient().GetAsync("/api/orders");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Get_OrderById_Seeded_Returns200WithItsValues()
    {
        var order = await User().GetFromJsonAsync<OrderDto>("/api/orders/1");
        Assert.Equal(new OrderDto(1, "Ada", 12.50m), order);
    }

    [Fact]
    public async Task Get_OrderById_Unknown_Returns404()
    {
        var response = await User().GetAsync("/api/orders/999");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Get_Export_BearerScheme_Returns200WithTheOrders()
    {
        var response = await User().GetAsync("/api/orders/export");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.StartsWith("1;Ada;", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task Get_Export_WithoutUser_Returns401()
    {
        var response = await factory.CreateClient().GetAsync("/api/orders/export");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Post_Order_Valid_Returns201AndSavesIt()
    {
        var response = await User().PostAsJsonAsync("/api/orders", new { customer = "Grace", total = 30.25m });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<OrderDto>();
        Assert.Equal($"/api/orders/{created!.Id}", response.Headers.Location!.OriginalString);
        using var scope = factory.Services.CreateScope();
        var saved = await scope.ServiceProvider.GetRequiredService<ShopDbContext>().Orders.FindAsync(created.Id);
        Assert.Equal(("Grace", 30.25m, false), (saved!.Customer, saved.Total, saved.Sent));
    }

    [Fact]
    public async Task Post_Order_WithoutCustomer_Returns400WithTheField()
    {
        var response = await User().PostAsJsonAsync("/api/orders", new { customer = "", total = 5m });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var problem = await response.Content.ReadFromJsonAsync<Problem>();
        Assert.Contains("customer", problem!.Errors.Keys);
    }

    [Fact]
    public async Task Get_AdminStats_WithoutTheRole_Returns403()
    {
        var response = await User().GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Get_AdminStats_WithTheRole_Returns200()
    {
        var response = await User("orders-admin").GetAsync("/api/admin/stats");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public void Factory_LeavesTheOutboxWorkerOut()
    {
        Assert.DoesNotContain(factory.Services.GetServices<IHostedService>(), service => service is OutboxWorker);
    }

    private sealed record Problem(Dictionary<string, string[]> Errors);
}
EOF
  cat > "$t/OrdersEnvironmentTests.cs" <<'EOF'
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Xunit;

[Trait("Category", "Environment")]
public class OrdersEnvironmentTests
{
    [EnvironmentFact]
    public async Task Get_Orders_WithoutToken_Returns401()
    {
        using var client = EnvironmentClient.Create(withToken: false);
        var response = await client.GetAsync("/api/orders");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }
}

[Trait("Category", "EnvironmentWrites")]
public class OrdersWritesEnvironmentTests
{
    [EnvironmentFact]
    public async Task Post_Order_Valid_Returns201ThenDeleteReturns204()
    {
        using var client = EnvironmentClient.Create();
        var response = await client.PostAsJsonAsync("/api/orders", new { customer = "Environment test", total = 1.5m });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var id = body.RootElement.GetProperty("id").GetInt32();
        try
        {
            var read = await client.GetAsync($"/api/orders/{id}");
            Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        }
        finally
        {
            var deleted = await client.DeleteAsync($"/api/orders/{id}");
            Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        }
    }
}
EOF
}

# api_tests <folder> <target framework> <version>: /tests api from the pre-flight to the tests in memory
api_tests() {
  dir=$1 tfm=$2 v=$3
  shop_repo "$dir" "$tfm" "$v"
  run api-preflight.sh
  check "$tfm: api-preflight, the settings read at start" 0 '^SETTING AT START: ConnectionStrings:Default \(src/Shop\.Api/Program\.cs:[0-9]+\)'
  check "$tfm: api-preflight, Payments:BaseUrl ?? throw" 0 '^SETTING AT START: Payments:BaseUrl \(src/Shop\.Api/Program\.cs:[0-9]+\)'
  check "$tfm: api-preflight, the worker" 0 '^WORKER: OutboxWorker \(src/Shop\.Api/Program\.cs:[0-9]+\): removed in the factory by its type'
  check "$tfm: api-preflight, the DbContext of the endpoints, its provider and its EF Core" 0 "^DBCONTEXT: ShopDbContext — registered at src/Shop\\.Api/Program\\.cs:[0-9]+, SqlServer, EF Core $(printf '%s' "$v" | sed 's/\./\\./g'); used directly by the endpoints: src/Shop\\.Api/OrdersEndpoints\\.cs$"
  check "$tfm: api-preflight, the scheme named by an endpoint" 0 '^AUTHENTICATION: scheme Bearer named by an endpoint \(src/Shop\.Api/OrdersEndpoints\.cs:[0-9]+\)'
  check "$tfm: api-preflight, the blocker the developer decides" 0 '^- DbContext ShopDbContext utilisé directement par src/Shop\.Api/OrdersEndpoints\.cs'
  case "$tfm" in
    net8.0) check "net8.0: api-preflight, Program before .NET 10" 0 '^PROGRAM: src/Shop\.Api/Program\.cs: top-level statements on \.NET 8: test-guardian\.sh setup --integration adds public partial class Program' ;;
    *) check "$tfm: api-preflight, Program public on .NET 10" 0 '^PROGRAM: src/Shop\.Api/Program\.cs: top-level statements, public by itself on \.NET 10' ;;
  esac
  run tests.sh --raw "api"
  check "$tfm: tests.sh api, the facts of the wizard" 0 '^Mode : api$' "$SECRETS"
  run test-guardian.sh setup --integration --db sqlite xunit src/Shop.Api/Shop.Api.csproj
  check "$tfm: setup --integration --db sqlite, the project of the API tests with SQLite of the EF Core of the API" 0 "^SETUP: tests/Shop\\.IntegrationTests/Shop\\.IntegrationTests\\.csproj created \\(xunit, $tfm\\).*Microsoft\\.EntityFrameworkCore\\.Sqlite $(printf '%s' "$v" | sed 's/\./\\./g').*build OK"
  [ "$tfm" = net8.0 ] && check "net8.0: setup, public partial class Program for WebApplicationFactory" 0 'public partial class Program added to src/Shop\.Api/Program\.cs'
  commit
  t=tests/Shop.IntegrationTests
  [ -d "$t" ] || return 1
  cp "$blocks/2" "$t/TestAuthHandler.cs"
  cp "$blocks/4" "$t/EnvironmentFactAttribute.cs"
  cp "$blocks/5" "$t/EnvironmentClient.cs"
  cp "$blocks/6" "$t/HealthEnvironmentTests.cs"
  write_tests "$t"
  if [ "$tfm" = net10.0 ]; then
    # the first factory of the skill: the API does not start in memory (what the pre-flight named)
    cp "$blocks/1" "$t/ApiFactory.cs"
    commit
    run build-test.sh "$t/Shop.IntegrationTests.csproj" --filter "FullyQualifiedName~OrdersEndpointsTests"
    check "$tfm: the first factory cannot start this API: the setting read at start" 1 'ConnectionStrings:Default is missing'
  fi
  # the factory of the skill that handles them (the types of the API come from its namespace)
  { printf 'using Shop.Api;\n'; cat "$blocks/3"; } > "$t/ApiFactory.cs"
  commit
  run build-test.sh "$t/Shop.IntegrationTests.csproj"
  check "$tfm: the factory of the skill: settings, worker out, DbContext on SQLite, the Bearer scheme answered by the test handler" 0 '^TESTS: OK' 'FAILED TESTS|ENVIRONMENT PROBLEM'
  note "$tfm, the API tests in memory ($(sh "$scripts/test-platform.sh" kind "$t/Shop.IntegrationTests.csproj" 2>/dev/null | cut -d' ' -f1))" "$out"
  run test-lint.sh "$t/OrdersEnvironmentTests.cs" "$t/HealthEnvironmentTests.cs"
  check "$tfm: test-lint, the environment tests" 0 '^TEST LINT: OK'
  return 0
}

cd "$work" || exit 1
api_tests "$work/shop10" net10.0 "$V10" || stop "net10.0: no integration test project"
if dotnet --list-sdks | grep -q '^8\.'; then
  api_tests "$work/shop8" net8.0 "$V8" || stop "net8.0: no integration test project"
else
  echo "NOTE: no .NET 8 SDK here: the .NET 8 API is not tried"
fi

# ---------- the lab, ready ----------
discovery_up() { [ "$(lab_curl https://idp.lab.test:8443/realms/acme/.well-known/openid-configuration -o /dev/null -w '%{http_code}')" = 200 ]; }
wait_for "Keycloak (its discovery document, through the proxy)" 300 discovery_up || { docker logs "$lab-idp" > "$work/idp.log" 2>&1; stop "Keycloak does not answer through the proxy" "$work/idp.log"; }
sql_up() {
  docker exec "$lab-sql" sh -c 'for s in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do [ -x "$s" ] && exec "$s" -C -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1"; done; exit 1'
}
wait_for "SQL Server" 180 sql_up || { docker logs "$lab-sql" > "$work/sql.log" 2>&1; stop "SQL Server does not answer" "$work/sql.log"; }

# the API deployed: .NET 10, published, in the ASP.NET Core image, HTTPS with the certificate of the internal authority
cd "$work/shop10" || exit 1
dotnet publish src/Shop.Api/Shop.Api.csproj -c Release -o "$work/lab/api" -nologo > "$work/publish.log" 2>&1 || stop "dotnet publish of the API" "$work/publish.log"
chmod -R a+rX "$work/lab/api"
printf 'ConnectionStrings__Default=Server=sql.lab.test;Database=Shop;User Id=sa;Password=%s;TrustServerCertificate=True\n' "$SQL_PASS" > "$work/lab/api.env"
docker run -d --name "$lab-api" --network "$lab-int" --network-alias api.lab.test \
  -v "$work/lab/api:/app:ro" -v "$pki:/certs:ro" -w /app --env-file "$work/lab/api.env" \
  -e ASPNETCORE_URLS=https://+:8443 -e Kestrel__Certificates__Default__Path=/certs/api.pem \
  -e Kestrel__Certificates__Default__KeyPath=/certs/api.key -e SSL_CERT_FILE=/certs/bundle.pem \
  -e Payments__BaseUrl=http://payments.lab.test -e Database__CreateAtStart=true \
  "$ASPNET_IMAGE" dotnet Shop.Api.dll >> "$work/docker.log" 2>&1 || stop "the API ($ASPNET_IMAGE)" "$work/docker.log"
api_up() { [ "$(lab_curl https://api.lab.test:8443/health -o /dev/null -w '%{http_code}')" = 200 ]; }
wait_for "the API (/health, through the proxy)" 120 api_up || { docker logs "$lab-api" > "$work/api.log" 2>&1; stop "the API does not answer through the proxy" "$work/api.log"; }
! curl -s -o /dev/null --max-time 10 --cacert "$pki/ca.pem" https://api.lab.test:8443/health
verdict "the API cannot be reached without the proxy (its name resolves through the proxy only)" $?

# ---------- /tests env config: what the code says, the block of AGENTS.md, the access checked ----------
RECETTE_CLIENT_SECRET=$SECRET_TESTS RECETTE_PROXY_CREDENTIALS=$CRED
export RECETTE_CLIENT_SECRET RECETTE_PROXY_CREDENTIALS
run env-setup.sh scan
check "env-setup scan: the authority the API checks, from its appsettings" 0 '^HINT OIDC: Authority https://idp\.lab\.test:8443/realms/acme \(src/Shop\.Api/appsettings\.json: Oidc\)$'
check "env-setup scan: the audience the API checks" 0 '^HINT OIDC: Audience shop-api \(src/Shop\.Api/appsettings\.json: Oidc\)$'
check "env-setup scan: the local address of the API" 0 '^HINT LOCAL: https://localhost:7043 '
check "env-setup scan: no proxy on this machine" 0 '^PROXY OF THIS MACHINE: none'
run tests.sh --raw "env config recette"
check "tests.sh env config: the facts of the wizard, the health path of the code" 0 '^Santé : /health \(MapHealthChecks dans le code\)$' "$SECRETS"
run env-setup.sh set recette --url https://api.lab.test:8443 --oidc https://idp.lab.test:8443/realms/acme --client shop-tests \
  --scope profile --proxy "$P" --proxy-auth --ca certs/lab-ca.pem --health /health --writes
check "env-setup set: the block of recette" 0 '^WRITTEN: AGENTS\.md « ## Environnements » — recette \(new\)$' "$SECRETS"
check "env-setup set: the token URL read through the proxy, with the internal authority" 0 '^TOKEN URL: https://idp\.lab\.test:8443/realms/acme/protocol/openid-connect/token \(discovery document of the authority\)$'
check "env-setup set: the variables, set" 0 '^VARIABLES: RECETTE_CLIENT_SECRET \(set\), RECETTE_PROXY_CREDENTIALS \(set\)'
grep -q '^  - token-url : https://idp\.lab\.test:8443/realms/acme/protocol/openid-connect/token$' AGENTS.md && ! grep -q -E "$SECRETS" AGENTS.md
verdict "env-setup set: AGENTS.md has the token URL and never a secret" $?
TOKEN_URL=https://idp.lab.test:8443/realms/acme/protocol/openid-connect/token
commit
run env-tests.sh --check recette
check "env-tests --check: how recette is reached" 0 "^ENVIRONMENT: recette https://api\\.lab\\.test:8443 \\(tests that write: allowed\\) — token: OpenID Connect \\(client credentials\\); proxy http://127\\.0\\.0\\.1:$pport \\(credentials from RECETTE_PROXY_CREDENTIALS\\), certificate certs/lab-ca\\.pem$" "$SECRETS"
# Keycloak gives expires_in from the clock of its answer: 300 s for this realm, 299 s when a second turns meanwhile
check "env-tests --check: a token of Keycloak through the proxy, its claims" 0 '^CHECK: token OK: expires in (299|300) s; issuer https://idp\.lab\.test:8443/realms/acme; audience [^;]*shop-api[^;]*; client shop-tests; scopes [^;]*profile' "$SECRETS"
check "env-tests --check: the API through the proxy, its certificate trusted" 0 '^CHECK: API https://api\.lab\.test:8443/health answers 200 without a token$'
check "env-tests --check: the token accepted by the API (JwtBearer: signature, issuer, audience)" 0 '^CHECK: API GET /api/orders answers 200 with the token \(401 without\)$'
check "env-tests --check: OK" 0 '^CHECK: OK$' "$SECRETS"

# ---------- HashiCorp Vault: the secrets of an environment kept there, read by its own CLI ----------
# a Vault server (dev mode: KV version 2 at secret/), its CLI copied from its image (a static binary), a policy that
# gives the developer's token the secrets of the lab only, as the team that runs Vault would set it
VAULT_ROOT=$(openssl rand -hex 16)
docker run -d --name "$lab-vault" --cap-add=IPC_LOCK -p 127.0.0.1::8200 -e VAULT_DEV_ROOT_TOKEN_ID="$VAULT_ROOT" \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 "$VAULT_IMAGE" >> "$work/docker.log" 2>&1 || stop "Vault ($VAULT_IMAGE)" "$work/docker.log"
mkdir -p "$work/bin"
vault_bin=$(docker exec "$lab-vault" sh -c 'command -v vault' 2>/dev/null)
docker cp "$lab-vault:${vault_bin:-/bin/vault}" "$work/bin/vault" >> "$work/docker.log" 2>&1 || stop "the vault CLI from its image" "$work/docker.log"
PATH="$work/bin:$PATH"
VAULT_ADDR="http://127.0.0.1:$(docker port "$lab-vault" 8200/tcp | head -n 1 | sed 's/.*://')"
export PATH VAULT_ADDR
vault_up() { VAULT_TOKEN=$VAULT_ROOT vault status > /dev/null 2>&1; }
wait_for "Vault" 60 vault_up || stop "Vault does not answer on $VAULT_ADDR" "$work/docker.log"
echo "NOTE: $(vault version 2>/dev/null | head -n 1)"
printf 'path "secret/data/lab/*" {\n  capabilities = ["read"]\n}\n' > "$work/lab-read.hcl"
printf 'path "secret/data/other/*" {\n  capabilities = ["read"]\n}\n' > "$work/other-read.hcl"
{
  VAULT_TOKEN=$VAULT_ROOT vault kv put secret/lab/recette client_secret="$SECRET_TESTS"
  VAULT_TOKEN=$VAULT_ROOT vault kv put secret/lab/proxy credentials="$CRED"
  VAULT_TOKEN=$VAULT_ROOT vault policy write lab-read "$work/lab-read.hcl"
  VAULT_TOKEN=$VAULT_ROOT vault policy write other-read "$work/other-read.hcl"
} > "$work/vault-setup.log" 2>&1 || stop "the secrets and the policies of Vault" "$work/vault-setup.log"
DEV_TOKEN=$(VAULT_TOKEN=$VAULT_ROOT vault token create -policy=lab-read -field=token 2>/dev/null)
OTHER_TOKEN=$(VAULT_TOKEN=$VAULT_ROOT vault token create -policy=other-read -field=token 2>/dev/null)
[ -n "$DEV_TOKEN" ] && [ -n "$OTHER_TOKEN" ] || stop "the tokens of Vault"
SECRETS="$SECRETS|$VAULT_ROOT|$DEV_TOKEN|$OTHER_TOKEN"
# the developer's login: the token in the environment, as a token helper would give it
VAULT_TOKEN=$DEV_TOKEN
export VAULT_TOKEN
run env-setup.sh scan
check "Vault: env-setup scan sees its CLI, never calls it" 0 '^VAULT: the vault CLI is on this machine \(VAULT_ADDR set\)'
run env-setup.sh set coffre --url https://api.lab.test:8443 --oidc https://idp.lab.test:8443/realms/acme --client shop-tests \
  --scope profile --vault secret/lab/recette#client_secret --proxy "$P" --proxy-vault secret/lab/proxy#credentials --ca certs/lab-ca.pem --health /health
check "Vault: env-setup set writes the places in Vault, never a secret" 0 '^    - secret : `vault:secret/lab/recette#client_secret`$' "$SECRETS"
check "Vault: the token URL read through the proxy, its credentials from Vault" 0 '^TOKEN URL: https://idp\.lab\.test:8443/realms/acme/protocol/openid-connect/token \(discovery document of the authority\)$'
! grep -q -E "$SECRETS" AGENTS.md
verdict "Vault: AGENTS.md holds no secret" $?
run env-tests.sh --check coffre
check "Vault: env-tests --check reads both secrets from Vault, through the proxy, with Keycloak" 0 '^CHECK: OK$' "$SECRETS"
check "Vault: where each secret was read" 0 '^CHECK: variables: Vault secret/lab/recette \(field client_secret\) read, Vault secret/lab/proxy \(field credentials\) read$'
check "Vault: the token of Keycloak, asked with the secret of Vault" 0 '^CHECK: token OK: expires in (299|300) s; .*client shop-tests' "$SECRETS"
# what Vault answers otherwise: no token, a token of another policy, a path or a field that does not exist
commit
vault_case() {
  # vault_case <token, or "" for none> <environment>: env-tests.sh --check with that login, in an empty home (no token
  # helper file)
  mkdir -p "$work/vault-home"
  if [ -n "$1" ]; then
    out=$(HOME="$work/vault-home" VAULT_TOKEN="$1" "$SHELL_UNDER_TEST" "$scripts/env-tests.sh" --check "$2" 2>&1)
  else
    out=$(HOME="$work/vault-home" env -u VAULT_TOKEN "$SHELL_UNDER_TEST" "$scripts/env-tests.sh" --check "$2" 2>&1)
  fi
  status=$?
}
# what the real Vault answered, for the notes of the run
vnote() { echo "NOTE: $1: $(printf '%s\n' "$2" | grep -m 1 '^ENVIRONMENT PROBLEM' | sed 's/.*cannot be read: //' | cut -c1-200)"; }
vault_case "" coffre
vnote "Vault without a token" "$out"
check "Vault: no token (not logged in)" 1 'ENVIRONMENT PROBLEM: the client secret of coffre \(Vault secret/lab/recette \(field client_secret\)\) cannot be read: you are not logged in to Vault' "$SECRETS"
vault_case "$OTHER_TOKEN" coffre
vnote "Vault with a token of another policy" "$out"
check "Vault: a token whose policy does not give the secret" 1 'cannot be read: Vault refuses secret/lab/recette to your token' "$SECRETS"
# two more environments, declared as /tests env config declares them: a path and a field that Vault does not have
vault_env() {
  "$SHELL_UNDER_TEST" "$scripts/env-setup.sh" set "$1" --url https://api.lab.test:8443 --oidc https://idp.lab.test:8443/realms/acme \
    --client shop-tests --vault "$2" --proxy "$P" --proxy-vault secret/lab/proxy#credentials --ca certs/lab-ca.pem > "$work/set-$1.log" 2>&1
}
vault_env coffrevide secret/lab/nothing#client_secret
vault_env coffrechamp secret/lab/recette#nope
grep -q '^- `coffrechamp` : ' AGENTS.md
verdict "Vault: the environments of the cases declared" $?
vault_case "$DEV_TOKEN" coffrevide
vnote "Vault, a path that does not exist" "$out"
check "Vault: nothing at that path" 1 'cannot be read: nothing in Vault at secret/lab/nothing' "$SECRETS"
vault_case "$DEV_TOKEN" coffrechamp
vnote "Vault, a field that does not exist" "$out"
check "Vault: no such field" 1 'cannot be read: Vault has secret/lab/recette but no field nope in it' "$SECRETS"
git checkout -q -- AGENTS.md 2>/dev/null || true

# ---------- /tests env: the environment tests of the skill on the deployed API ----------
tp=tests/Shop.IntegrationTests/Shop.IntegrationTests.csproj
kind=$(sh "$scripts/test-platform.sh" kind "$tp" 2>/dev/null)
run env-tests.sh recette
check "env-tests: the token before the build" 0 '^TOKEN: OK from the provider of recette \(expires in (299|300) s\)$' "$SECRETS"
case "$kind" in
  vstest*)
    check "env-tests: the environment tests, one line each, read only" 0 '^  OK  HealthEnvironmentTests\.Get_Orders_ReturnsAJsonArray \([0-9.]+ s\)$' "$SECRETS|^  (FAILED|SKIPPED)  |OrdersWritesEnvironmentTests"
    check "env-tests: 401 without a token, through the proxy" 0 '^  OK  OrdersEnvironmentTests\.Get_Orders_WithoutToken_Returns401 \(' ;;
  *) check "env-tests: the environment tests, read only" 0 '^TESTS: OK' "$SECRETS" ;;
esac
run env-tests.sh recette --ecriture
note "env-tests.sh recette --ecriture, .NET 10" "$out"
case "$kind" in
  vstest*) check "env-tests --ecriture: the test that creates then deletes an order" 0 '^  OK  OrdersWritesEnvironmentTests\.Post_Order_Valid_Returns201ThenDeleteReturns204 \(' "$SECRETS|^  (FAILED|SKIPPED)  " ;;
  *) check "env-tests --ecriture: the tests that write too" 0 '^TESTS: OK' "$SECRETS" ;;
esac

# the client of the skill alone (a CI pipeline): API_OIDC_* only, no API_TOKEN; post, then basic
squid_tunnels() { sleep 1; docker exec "$lab-squid" cat /var/log/squid/access.log 2>/dev/null | grep -c -E "TCP_TUNNEL/200 [0-9]+ CONNECT $1:8443 $PROXY_USER "; }
penc="http://$PROXY_USER:$(urlenc "$PROXY_PASS")@127.0.0.1:$pport"
for how in post basic; do
  before=$(squid_tunnels idp.lab.test)
  rm -rf "$work/client"
  set --
  case "$kind" in vstest*) set -- --logger "trx;LogFileName=client.trx" --results-directory "$work/client" ;; esac
  out=$(API_BASE_URL=https://api.lab.test:8443 API_OIDC_TOKEN_URL=$TOKEN_URL API_OIDC_CLIENT_ID=shop-tests \
    API_OIDC_CLIENT_SECRET=$SECRET_TESTS API_OIDC_SCOPE=profile API_OIDC_CLIENT_AUTH=$how HTTPS_PROXY=$penc \
    SSL_CERT_FILE="$pki/bundle.pem" "$SHELL_UNDER_TEST" "$scripts/build-test.sh" --no-build "$tp" --filter "Category=Environment" "$@" 2>&1)
  status=$?
  set --
  check "EnvironmentClient alone ($how): its own token, through the proxy (credentials encoded in HTTPS_PROXY), the internal authority" 0 '^TESTS: OK'
  if [ -f "$work/client/client.trx" ]; then
    if [ "$(grep -c 'outcome="Passed"' "$work/client/client.trx")" -eq 3 ]; then passed=0; else passed=1; fi
    verdict "EnvironmentClient alone ($how): the 3 environment tests passed" "$passed"
  fi
  [ "$(squid_tunnels idp.lab.test)" -gt "$before" ]
  verdict "EnvironmentClient alone ($how): it asked its token to Keycloak through the proxy" $?
done

# the messages of .NET that env-tests.sh reads, as .NET really writes them
grep -q -F "proxy tunnel request to proxy '[^']*' failed with status code '407'" "$scripts/env-tests.sh" || { fail=$((fail + 1)); echo "FAIL: env-tests.sh no longer reads the 407 of .NET's proxy tunnel"; }
dotnet_env() {
  # dotnet_env <HTTPS_PROXY or ""> <SSL_CERT_FILE or "">: the environment tests run by .NET alone (an empty value: the
  # variable is not set at all)
  out=$(env API_BASE_URL=https://api.lab.test:8443 API_OIDC_TOKEN_URL="$TOKEN_URL" API_OIDC_CLIENT_ID=shop-tests \
    API_OIDC_CLIENT_SECRET="$SECRET_TESTS" ${1:+"HTTPS_PROXY=$1"} ${2:+"SSL_CERT_FILE=$2"} \
    "$SHELL_UNDER_TEST" "$scripts/build-test.sh" --no-build "$tp" --filter "Category=Environment" 2>&1)
  status=$?
}
dotnet_env "http://$PROXY_USER:wrong-password@127.0.0.1:$pport" "$pki/bundle.pem"
check ".NET: a wrong proxy password, the message env-tests.sh reads (407 of the tunnel)" 1 "proxy tunnel request to proxy '[^']*' failed with status code '407'"
dotnet_env "" "$pki/bundle.pem"
check ".NET: without the proxy, the message env-tests.sh reads (an unknown name)" 1 'Name or service not known|No such host is known|nodename nor servname|Temporary failure in name resolution'
dotnet_env "$penc" ""
check ".NET: without the internal authority, the message env-tests.sh reads (a certificate not trusted)" 1 'SSL connection could not be established|remote certificate is invalid|UntrustedRoot|RemoteCertificateChainErrors'

# ---------- .NET 8: the same environment, from the tests of the .NET 8 API ----------
if [ -d "$work/shop8/tests/Shop.IntegrationTests" ]; then
  cd "$work/shop8" || exit 1
  run env-setup.sh set recette --url https://api.lab.test:8443 --oidc https://idp.lab.test:8443/realms/acme --client shop-tests \
    --scope profile --proxy "$P" --proxy-auth --ca certs/lab-ca.pem --health /health --writes
  check "net8.0: env-setup set recette, the token URL through the proxy" 0 '^TOKEN URL: https://idp\.lab\.test:8443/realms/acme/protocol/openid-connect/token ' "$SECRETS"
  commit
  run env-tests.sh recette --ecriture
  note "env-tests.sh recette --ecriture, .NET 8" "$out"
  case "$(sh "$scripts/test-platform.sh" kind tests/Shop.IntegrationTests/Shop.IntegrationTests.csproj 2>/dev/null)" in
    vstest*) check "net8.0: env-tests, the environment tests of a .NET 8 client through the proxy" 0 '^  OK  OrdersWritesEnvironmentTests\.Post_Order_Valid_Returns201ThenDeleteReturns204 \(' "$SECRETS|^  (FAILED|SKIPPED)  " ;;
    *) check "net8.0: env-tests, the environment tests of a .NET 8 client through the proxy" 0 '^TESTS: OK' "$SECRETS" ;;
  esac
  cd "$work/shop10" || exit 1
fi

# ---------- /outil http: the requests for Rider, sent as Rider sends them ----------
run http-files.sh --plan
check "http-files --plan: the folder and the group" 0 '^  GROUP: OrdersEndpoints — 6 request\(s\) \(src/Shop\.Api/OrdersEndpoints\.cs\)'
check "http-files --plan: recette, its token asked by Rider" 0 '^  ENVIRONMENT: recette https://api\.lab\.test:8443 — OpenID Connect: Rider asks the token itself \(OAuth 2\.0 client credentials, token URL https://idp\.lab\.test:8443/realms/acme/protocol/openid-connect/token\)'
run http-files.sh
check "http-files: the requests of the endpoints" 0 '^HTTP: src/Shop\.Api/http/OrdersEndpoints\.http \(6 requests, 1 with a body to fill in\)$' "$SECRETS"
check "http-files: the private file, never committed" 0 '^IGNORED: src/Shop\.Api/http/http-client\.private\.env\.json added to \.gitignore'
h=src/Shop.Api/http
node -e 'const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const a = e.recette.Security.Auth.api
  process.exit(a.Type === "OAuth2" && a["Grant Type"] === "Client Credentials" && a["Token URL"] === process.argv[2] && a["Client ID"] === "shop-tests" &&
    a["Client Secret"] === "{{clientSecret}}" && a["Client Credentials"] === "in body" && a.Scope === "profile" && e.recette.id === "1" ? 0 : 1)' "$h/http-client.env.json" "$TOKEN_URL"
verdict "http-files: http-client.env.json is JSON, recette with the OAuth 2.0 client credentials of Rider" $?
# the private file filled by the pack: the secret of recette from its variable, the one of coffre from Vault
run http-files.sh --private
check "http-files --private: the secret of recette, from its variable" 0 '^FILLED: src/Shop\.Api/http/http-client\.private\.env\.json: recette clientSecret \(from the variable RECETTE_CLIENT_SECRET\)$' "$SECRETS"
check "http-files --private: the secret of coffre, from Vault" 0 '^FILLED: src/Shop\.Api/http/http-client\.private\.env\.json: coffre clientSecret \(from Vault secret/lab/recette \(field client_secret\)\)$' "$SECRETS"
git check-ignore -q "$h/http-client.private.env.json"
verdict "http-files --private: the private file stays ignored by git" $?
cat > "$work/rider.mjs" <<'EOF'
// What the HTTP client of Rider does with the files of http-files.sh, for one environment: the token request of its
// Security.Auth "api" (OAuth 2.0 client credentials) as a curl configuration, then the GET requests of the .http files
import { readFileSync, readdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
const [dir, name, curlFile] = process.argv.slice(2)
const env = JSON.parse(readFileSync(join(dir, "http-client.env.json"), "utf8"))[name]
const priv = JSON.parse(readFileSync(join(dir, "http-client.private.env.json"), "utf8"))[name] || {}
const vars = { ...env, ...priv }
const subst = (s) => String(s).replace(/\{\{([A-Za-z0-9_]+)\}\}/g, (m, k) => (k in vars ? String(vars[k]) : m))
const auth = env.Security.Auth.api
const form = new URLSearchParams({ grant_type: "client_credentials" })
const lines = [`url = "${subst(auth["Token URL"])}"`, 'header = "Accept: application/json"']
if (auth["Client Credentials"] === "basic") lines.push(`user = "${encodeURIComponent(subst(auth["Client ID"]))}:${encodeURIComponent(subst(auth["Client Secret"]))}"`)
else { form.set("client_id", subst(auth["Client ID"])); form.set("client_secret", subst(auth["Client Secret"])) }
if (auth.Scope) form.set("scope", subst(auth.Scope))
for (const [k, v] of Object.entries(auth["Custom Request Parameters"] || {})) if (typeof v !== "object" || v.Use !== "In Auth Request") form.set(k, subst(typeof v === "object" ? v.Value : v))
lines.push(`data = "${form.toString()}"`)
writeFileSync(curlFile, lines.join("\n") + "\n", { mode: 0o600 })
for (const f of readdirSync(dir).filter((f) => f.endsWith(".http")).sort()) {
  for (const block of readFileSync(join(dir, f), "utf8").split(/^###/m).slice(1)) {
    const request = block.split("\n").find((l) => /^(GET|POST|PUT|PATCH|DELETE) /.test(l))
    if (!request || !request.startsWith("GET ")) continue
    const token = /^Authorization: Bearer \{\{\$auth\.token\("api"\)\}\}$/m.test(block)
    console.log(subst(request.slice(4)) + "\t" + (token ? "token" : "-"))
  }
}
EOF
requests=$(node "$work/rider.mjs" "$h" recette "$work/rider-token.curl" 2>&1)
token=$(printf 'proxy = "%s"\nproxy-user = "%s"\n' "$P" "$CRED" | curl -K "$work/rider-token.curl" -K - -sS --cacert "$pki/ca.pem" --max-time 20 2>&1 |
  node -e 'let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => { try { console.log(JSON.parse(s).access_token || "") } catch { console.log("") } })')
if [ -n "$token" ]; then asked=0; else asked=1; fi
verdict "http-files: the token, asked as the Security.Auth of recette says" "$asked"
seen=$(printf '%s\n' "$requests" | while IFS="$(printf '\t')" read -r u auth; do
  [ -n "$u" ] || continue
  LAB_HEADER=""
  [ "$auth" = token ] && LAB_HEADER="Authorization: Bearer $token"
  c=$(lab_curl "$u" -o /dev/null -w '%{http_code}')
  LAB_HEADER=""
  printf '%s %s, ' "${u#https://api.lab.test:8443}" "$c"
done)
out=$seen status=0
check "http-files: each GET written by /outil http, answered by the deployed API as Rider sends it" 0 '^/api/orders 200, /api/orders/1 200, /api/orders/export 200, /api/admin/stats 403, /health 200, $'
token=""

# ---------- what goes wrong, each said once, before any build ----------
ADMIN_CLIENT_SECRET=$SECRET_ADMIN ADMIN_PROXY_CREDENTIALS=$CRED
AUTRE_CLIENT_ID=other-app AUTRE_CLIENT_SECRET=$SECRET_OTHER AUTRE_PROXY_CREDENTIALS=$CRED
SANSSERVICE_CLIENT_SECRET=$SECRET_NOSA SANSSERVICE_PROXY_CREDENTIALS=$CRED
PORTEE_CLIENT_SECRET=$SECRET_TESTS PORTEE_PROXY_CREDENTIALS=$CRED
DIRECT_CLIENT_SECRET=$SECRET_TESTS
SANSCA_CLIENT_SECRET=$SECRET_TESTS SANSCA_PROXY_CREDENTIALS=$CRED
INTERDIT_PROXY_CREDENTIALS=$CRED INCONNU_PROXY_CREDENTIALS=$CRED
export ADMIN_CLIENT_SECRET ADMIN_PROXY_CREDENTIALS AUTRE_CLIENT_ID AUTRE_CLIENT_SECRET AUTRE_PROXY_CREDENTIALS
export SANSSERVICE_CLIENT_SECRET SANSSERVICE_PROXY_CREDENTIALS PORTEE_CLIENT_SECRET PORTEE_PROXY_CREDENTIALS
export DIRECT_CLIENT_SECRET SANSCA_CLIENT_SECRET SANSCA_PROXY_CREDENTIALS INTERDIT_PROXY_CREDENTIALS INCONNU_PROXY_CREDENTIALS
A=https://idp.lab.test:8443/realms/acme
U=https://api.lab.test:8443
run env-setup.sh set admin --url "$U" --oidc "$A" --client shop-admin --auth-client basic --proxy "$P" --proxy-auth --ca certs/lab-ca.pem --health /health
run env-tests.sh --check admin
check "env-tests --check: client_secret_basic, the role of the client in the token" 0 '^CHECK: token OK: .*client shop-admin; .*roles [^;]*orders-admin' "$SECRETS"
check "env-tests --check: client_secret_basic, the API accepts it" 0 '^CHECK: API GET /api/orders answers 200 with the token \(401 without\)$'
run env-setup.sh set autre --url "$U" --oidc "$A" --client-var --proxy "$P" --proxy-auth --ca certs/lab-ca.pem --health /health
run env-tests.sh --check autre
check "env-tests --check: a token for another audience, refused by the API with its reason" 1 "^ENVIRONMENT PROBLEM: the API of autre refuses the token on GET /api/orders \\(401: Bearer error=\"invalid_token\", error_description=\"The audience" "$SECRETS"
run env-setup.sh set sansservice --url "$U" --oidc "$A" --client shop-noservice --proxy "$P" --proxy-auth --ca certs/lab-ca.pem
run env-tests.sh --check sansservice
check "env-tests --check: a client without service account" 1 '^ENVIRONMENT PROBLEM: the client of sansservice may not ask a token by client credentials \([0-9]+ unauthorized_client' "$SECRETS"
run env-setup.sh set portee --url "$U" --oidc "$A" --client shop-tests --scope orders:write --proxy "$P" --proxy-auth --ca certs/lab-ca.pem
run env-tests.sh --check portee
check "env-tests --check: a scope the provider does not know" 1 '^ENVIRONMENT PROBLEM: the provider of portee refuses the scope « orders:write » \([0-9]+ invalid_scope' "$SECRETS"
run env-setup.sh set direct --url "$U" --oidc "$A" --client shop-tests --proxy none
check "env-setup set: without the proxy, the token URL cannot be read, said" 0 '^TOKEN URL: not found from here \(the OpenID Connect provider of direct \(https://idp\.lab\.test:8443/realms/acme\) cannot be reached from this machine: its name is unknown here \([^)]*\)\); env-tests\.sh asks'
run env-tests.sh --check direct
check "env-tests --check: without the proxy, the names of the lab are unknown" 1 '^ENVIRONMENT PROBLEM: the OpenID Connect provider of direct \(https://idp\.lab\.test:8443/realms/acme\) cannot be reached from this machine: its name is unknown here'
run env-setup.sh set sansca --url "$U" --oidc "$A" --client shop-tests --proxy "$P" --proxy-auth
run env-tests.sh --check sansca
check "env-tests --check: the internal authority missing, the certificate of the provider not trusted" 1 '^ENVIRONMENT PROBLEM: the certificate of the OpenID Connect provider of sansca \(https://idp\.lab\.test:8443/realms/acme\) is not trusted on this machine'
run env-setup.sh set interdit --url https://blocked.lab.test:8443 --proxy "$P" --proxy-auth
run env-tests.sh --check interdit
check "env-tests --check: a host the proxy forbids (403 of squid)" 1 '^ENVIRONMENT PROBLEM: the proxy forbids interdit \(https://blocked\.lab\.test:8443\) \(403 on CONNECT\)'
run env-setup.sh set inconnu --url https://nowhere.lab.test:8443 --proxy "$P" --proxy-auth
run env-tests.sh --check inconnu
check "env-tests --check: a name the proxy cannot resolve (squid)" 1 '^ENVIRONMENT PROBLEM: the proxy cannot reach inconnu \(https://nowhere\.lab\.test:8443\) \(50[234] on CONNECT'
RECETTE_CLIENT_SECRET=not-the-secret-of-recette
run env-tests.sh --check recette
check "env-tests --check: a wrong secret, said by Keycloak" 1 '^ENVIRONMENT PROBLEM: the provider of recette refuses the client \([0-9]+ [a-z_]+[^)]*\): the client id or the secret \(RECETTE_CLIENT_SECRET\) is wrong' "$SECRETS|not-the-secret"
RECETTE_CLIENT_SECRET=$SECRET_TESTS RECETTE_PROXY_CREDENTIALS="$PROXY_USER:wrong-password"
run env-tests.sh --check recette
check "env-tests --check: a wrong proxy password (407 of squid)" 1 '^ENVIRONMENT PROBLEM: the proxy refuses the connection to the token endpoint of recette \(https://idp\.lab\.test:8443/realms/acme/protocol/openid-connect/token\) without credentials, or with these \(407 Proxy Authentication Required\)' "$SECRETS|wrong-password"
RECETTE_PROXY_CREDENTIALS=$CRED
(unset RECETTE_CLIENT_SECRET; "$SHELL_UNDER_TEST" "$scripts/env-tests.sh" --check recette > "$work/out" 2>&1; echo $? > "$work/status")
out=$(cat "$work/out") status=$(cat "$work/status")
check "env-tests --check: a variable not set, said with how to set it" 1 '^ENVIRONMENT PROBLEM: the variable RECETTE_CLIENT_SECRET, which holds the client secret of recette, is not set'
# the API stopped: the proxy cannot reach it, before any build
docker stop -t 5 "$lab-api" > /dev/null 2>&1
run env-tests.sh recette
check "env-tests: the API stopped, said before any build" 1 '^ENVIRONMENT PROBLEM: the proxy cannot reach recette \(https://api\.lab\.test:8443\) \(50[234] on CONNECT' '^PROJECT:'

echo "NOTE: $(( $(date +%s) - started )) s, the lab included"
echo "oidc-real-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
