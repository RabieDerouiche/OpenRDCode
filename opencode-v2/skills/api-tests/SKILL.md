---
name: api-tests
description: The integration tests of an ASP.NET Core API - in memory with WebApplicationFactory (every endpoint called over HTTP, its ports faked, authentication by a test scheme, what stops the API from starting in a test - required settings, workers, a DbContext - handled in the test code) and against a deployed environment (Category Environment, run by env-tests.sh, with a fixed token or an OpenID Connect token by client credentials, through a proxy). Load for /tests api, and before writing or reviewing such tests.
compatibility: opencode
---
# API tests

Two kinds, never mixed in one class:
- **In memory** (the proof of the behavior): the API runs in the test process (`WebApplicationFactory<Program>`), each endpoint is called over HTTP: routing, model binding, validation, filters, authorization and serialization run for real. Its ports (repositories, clients of other systems, the clock) are replaced by fakes the test controls: no database server, no network, no file outside a temporary folder. They run with every build (`build-test.sh`) and in the CI.
- **On an environment** (the deployment and its configuration): the same endpoints called on the URL of a deployed environment, with checks that hold whatever its data: the status, the content type, the fields the contract promises, 401 without token. Skipped unless `API_BASE_URL` is set: `env-tests.sh <environment>` sets it (with the token, or what is needed to ask one), never another way.

## In memory
One factory per test project, next to the tests (copy the closest existing one when the project has one):
```csharp
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

// The API in memory: its ports replaced by the fakes of the tests, every authentication scheme by the test handler
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureTestServices(services =>
        {
            // the test scheme by default, and the handler of each scheme of the API (Bearer, ...) replaced by the test one
            services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            services.Configure<AuthenticationOptions>(options =>
            {
                foreach (var scheme in options.SchemeMap.Values)
                    scheme.HandlerType = typeof(TestAuthHandler);
            });
            // each port the endpoints use: services.RemoveAll<IOrderRepository>(); services.AddSingleton<IOrderRepository>(Orders);
        });
    }
}
```
```csharp
using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

// A user only when the test sends X-Test-User (and its roles in X-Test-Roles): without it, the API answers 401
public sealed class TestAuthHandler : AuthenticationHandler<AuthenticationSchemeOptions>
{
    public const string SchemeName = "Test";
    public const string UserHeader = "X-Test-User";
    public const string RolesHeader = "X-Test-Roles";

    public TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger, UrlEncoder encoder)
        : base(options, logger, encoder)
    {
    }

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(UserHeader, out var user))
            return Task.FromResult(AuthenticateResult.NoResult());
        var claims = new List<Claim> { new(ClaimTypes.Name, user.ToString()) };
        foreach (var role in Request.Headers[RolesHeader].ToString().Split(',', StringSplitOptions.RemoveEmptyEntries))
            claims.Add(new Claim(ClaimTypes.Role, role.Trim()));
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme.Name));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme.Name)));
    }
}
```
- The tests of an endpoint: one class per controller or group (`OrdersEndpointsTests`), `IClassFixture<ApiFactory>`, `factory.CreateClient()`; a scenario per test, named `<Verb>_<Route>_<Condition>_<Expected>` (`Get_OrderById_Unknown_Returns404`).
- Each test: the data of the scenario put in the fakes, the request (with `X-Test-User`, and `X-Test-Roles` when a role matters), then the status, then what the response says: the body read back as its DTO with its values (`ReadFromJsonAsync<OrderDto>()`), `Location` for a 201, the validation errors of a 400 (`ValidationProblemDetails.Errors` has the field), and what the fakes received (the order saved, with its values). Never only the status of a 2xx.
- The usual scenarios: the nominal one; 400 for each validation rule; 401 without user; 403 with a user that lacks the role or the policy; 404 for an unknown id; 409 when the code answers it. The scenarios the developer validated, no others.
- Every scheme of the API (`AddJwtBearer`, `AddMicrosoftIdentityWebApi`, an endpoint with `AuthenticationSchemes = "Bearer"`) is answered by the test handler: the factory replaces the handler of each scheme, never a second `AddScheme` under its name (« Scheme already exists » at start), so that the real handler never runs in a test.
- A policy on a claim of the token (`RequireClaim("scope", "orders.read")`): the test handler adds that claim from a header of the test (`X-Test-Scopes`), as it does the roles.
- Before .NET 10, `WebApplicationFactory<Program>` needs `public partial class Program { }` (test-guardian.sh setup --integration adds it); .NET 10 makes it public itself.
- The proof: `test-guardian.sh green <test project> <filter>`, twice, like any test.

### What stops the API from starting in a test (`api-preflight.sh` lists it), handled in the test code only
The one factory of the test project takes what the pre-flight lines name, and nothing else:
- a setting that Program.cs reads before `Build()` (SETTING AT START: a connection string, a section validated at start, `?? throw`): a value given with `UseSetting` (the code of Program.cs sees it; `ConfigureAppConfiguration` comes too late with minimal hosting);
- a worker (WORKER: `AddHostedService<T>`, the consumer of a broker, a loop on the database): removed by its implementation type (never every `IHostedService`: the server of the API is one of them);
- a DbContext that the endpoints use directly (DBCONTEXT, no port to fake), with the developer's choice « SQLite en mémoire »: `test-guardian.sh setup --integration --db sqlite` has added `Microsoft.EntityFrameworkCore.Sqlite` (the EF Core version of the API) to the test project; the context gets an in-memory SQLite database, kept open as long as the factory, its schema created from the model (and its `HasData`).

The factory of an API that has the three (it replaces the first `ApiFactory`, under the same name):
```csharp
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;

// The API in memory: the settings it reads at start, its worker out, its DbContext on an in-memory SQLite database
// (one per factory, its schema from the model), every authentication scheme by the test handler
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    private readonly SqliteConnection connection = new("DataSource=:memory:");

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Default", "Server=unused-by-the-tests");
        builder.UseSetting("Payments:BaseUrl", "http://payments.invalid");
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(TestAuthHandler.SchemeName)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.SchemeName, _ => { });
            services.Configure<AuthenticationOptions>(options =>
            {
                foreach (var scheme in options.SchemeMap.Values)
                    scheme.HandlerType = typeof(TestAuthHandler);
            });
            foreach (var worker in services.Where(d => d.ServiceType == typeof(IHostedService) && d.ImplementationType == typeof(OutboxWorker)).ToList())
                services.Remove(worker);
            // the provider of the API out (EF Core 9 and later also keep how AddDbContext configured it), SQLite in
            services.RemoveAll<DbContextOptions<ShopDbContext>>();
            foreach (var configuration in services.Where(d => d.ServiceType.IsGenericType
                         && d.ServiceType.Name.StartsWith("IDbContextOptionsConfiguration", StringComparison.Ordinal)
                         && d.ServiceType.GenericTypeArguments[0] == typeof(ShopDbContext)).ToList())
                services.Remove(configuration);
            connection.Open();
            services.AddDbContext<ShopDbContext>(options => options.UseSqlite(connection));
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<ShopDbContext>().Database.EnsureCreated();
        return host;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
            connection.Dispose();
    }
}
```
- Its names come from the pre-flight lines: the keys of SETTING AT START (a value that lets the code start, never a real address or secret), the type of each WORKER, the DbContext of DBCONTEXT. A part the API does not need is left out.
- The data of a scenario goes in the context before the request (`using var scope = factory.Services.CreateScope();` then `Add`, `SaveChanges`), and what the endpoint wrote is read back from it after.
- SQLite is not SQL Server: an endpoint whose query SQLite cannot run (raw SQL, a function of SQL Server, a schema, a sequence) is « BLOQUÉ : requête propre à <provider> » for that scenario, the others go on. Testcontainers (a real database in Docker) is the developer's decision, never taken here.
- A configuration provider that calls a remote system at start (Azure Key Vault, Azure App Configuration, AWS Secrets Manager) and that Program.cs does not skip for the environment `Testing`: no setting of the test code can stop it: the scenarios are « BLOQUÉ : <provider> appelé au démarrage », with the one-line change of Program.cs that would let them run (proposed, never made: `/go sans ticket` makes it).

## On an environment
```csharp
using Xunit;

// Runs only against a deployed environment: env-tests.sh <environment> sets API_BASE_URL (and how to get a token)
public sealed class EnvironmentFactAttribute : FactAttribute
{
    public EnvironmentFactAttribute()
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("API_BASE_URL")))
            Skip = "API_BASE_URL is not set: these tests run against a deployed environment (env-tests.sh <environment>)";
    }
}
```
```csharp
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

// The client of the environment: its URL, a timeout, and its token: asked to its OpenID Connect provider by client
// credentials (API_OIDC_*), again before it expires, or the fixed one (API_TOKEN). The proxy and the certificate
// authorities of the run come from the environment of the process (HTTPS_PROXY, NO_PROXY, SSL_CERT_FILE).
public static class EnvironmentClient
{
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static string? cached;
    private static DateTimeOffset renewAt;

    public static HttpClient Create(bool withToken = true)
    {
        HttpMessageHandler handler = withToken ? new BearerHandler { InnerHandler = new HttpClientHandler() } : new HttpClientHandler();
        return new HttpClient(handler)
        {
            BaseAddress = new Uri(Environment.GetEnvironmentVariable("API_BASE_URL")!),
            Timeout = TimeSpan.FromSeconds(30),
        };
    }

    private static string? Setting(string name) => Environment.GetEnvironmentVariable(name) is { Length: > 0 } value ? value : null;

    private static async Task<string?> TokenAsync(CancellationToken cancellationToken)
    {
        var tokenUrl = Setting("API_OIDC_TOKEN_URL");
        if (tokenUrl is null)
            return Setting("API_TOKEN");
        await Gate.WaitAsync(cancellationToken);
        try
        {
            if (cached is not null && DateTimeOffset.UtcNow < renewAt)
                return cached;
            var clientId = Setting("API_OIDC_CLIENT_ID") ?? throw new InvalidOperationException("API_OIDC_CLIENT_ID is not set");
            var secret = Setting("API_OIDC_CLIENT_SECRET") ?? throw new InvalidOperationException("API_OIDC_CLIENT_SECRET is not set");
            var form = new Dictionary<string, string> { ["grant_type"] = "client_credentials" };
            using var request = new HttpRequestMessage(HttpMethod.Post, tokenUrl);
            if (Setting("API_OIDC_CLIENT_AUTH") == "basic")
            {
                var pair = Uri.EscapeDataString(clientId) + ":" + Uri.EscapeDataString(secret);
                request.Headers.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.UTF8.GetBytes(pair)));
            }
            else
            {
                form["client_id"] = clientId;
                form["client_secret"] = secret;
            }
            foreach (var (field, variable) in new[] { ("scope", "API_OIDC_SCOPE"), ("audience", "API_OIDC_AUDIENCE"), ("resource", "API_OIDC_RESOURCE") })
            {
                if (Setting(variable) is { } value)
                    form[field] = value;
            }
            request.Content = new FormUrlEncodedContent(form);
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
            using var response = await http.SendAsync(request, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode)
                throw new InvalidOperationException($"The provider refused the token: {(int)response.StatusCode} {body}");
            using var answer = JsonDocument.Parse(body);
            cached = answer.RootElement.GetProperty("access_token").GetString();
            var lifetime = answer.RootElement.TryGetProperty("expires_in", out var expires)
                ? (expires.ValueKind == JsonValueKind.String ? int.Parse(expires.GetString()!, CultureInfo.InvariantCulture) : expires.GetInt32())
                : 60;
            renewAt = DateTimeOffset.UtcNow.AddSeconds(Math.Max(0, lifetime - 30));
            return cached;
        }
        finally
        {
            Gate.Release();
        }
    }

    private sealed class BearerHandler : DelegatingHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (await TokenAsync(cancellationToken) is { } token)
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            return await base.SendAsync(request, cancellationToken);
        }
    }
}
```
```csharp
using System.Net;
using System.Text.Json;
using Xunit;

[Trait("Category", "Environment")]
public class HealthEnvironmentTests
{
    [EnvironmentFact]
    public async Task Get_Health_Returns200()
    {
        using var client = EnvironmentClient.Create();
        var response = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [EnvironmentFact]
    public async Task Get_Orders_ReturnsAJsonArray()
    {
        using var client = EnvironmentClient.Create();
        var response = await client.GetAsync("/api/orders");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(JsonValueKind.Array, body.RootElement.ValueKind);
    }
}
```
- One class per controller (`<Controller>EnvironmentTests`), `[Trait("Category", "Environment")]` on the class (MSTest: `[TestCategory("Environment")]` and `Assert.Inconclusive` when `API_BASE_URL` is empty; NUnit: `[Category("Environment")]` and `Assert.Ignore`), `[EnvironmentFact]` on each test; the attribute and the client once per test project (an older client that only reads `API_TOKEN` keeps working: env-tests.sh gives it a fresh token).
- Checks that hold whatever the data of the environment: the status, the content type, the fields and their JSON kinds, 401 without token (`EnvironmentClient.Create(withToken: false)`), the time when the contract has one. Never a value that depends on its data, except data the test created itself.
- Read only: GET and HEAD. A scenario that writes is marked `[Trait("Category", "EnvironmentWrites")]` instead and undoes what it created in the same test (create, read, delete, in a `try/finally`); `env-tests.sh` runs it only with `--ecriture`, on an environment AGENTS.md marks « écriture permise ». Never production.
- Never a URL, a token, a client id, a secret or a proxy in the test code: `API_BASE_URL`, `API_TOKEN` and `API_OIDC_*` only, read from the environment of the run.
- The proof: `env-tests.sh <the first environment of AGENTS.md that is not production>` (read only). Unreachable from this machine, a variable not set, or a provider or proxy that refuses (« ENVIRONMENT PROBLEM »): the tests are « écrits, non lancés » with that reason, not « BLOQUÉ ».
- In the CI (a scheduled pipeline): `dotnet test <test project> --filter "Category=Environment"` with `API_BASE_URL` and, from masked variables of the project, `API_OIDC_TOKEN_URL`, `API_OIDC_CLIENT_ID`, `API_OIDC_CLIENT_SECRET` and `API_OIDC_SCOPE` (or `API_TOKEN` for a fixed token), `HTTPS_PROXY` when the runner needs one: the convention is the contract, not the script.
