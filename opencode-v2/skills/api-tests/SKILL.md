---
name: api-tests
description: The integration tests of an ASP.NET Core API - in memory with WebApplicationFactory (every endpoint called over HTTP, its ports faked, authentication by a test scheme) and against a deployed environment (Category Environment, run by env-tests.sh). Load for /tests api, and before writing or reviewing such tests.
compatibility: opencode
---
# API tests

Two kinds, never mixed in one class:
- **In memory** (the proof of the behavior): the API runs in the test process (`WebApplicationFactory<Program>`), each endpoint is called over HTTP: routing, model binding, validation, filters, authorization and serialization run for real. Its ports (repositories, clients of other systems, the clock) are replaced by fakes the test controls: no database, no network, no file outside a temporary folder. They run with every build (`build-test.sh`) and in the CI.
- **On an environment** (the deployment and its configuration): the same endpoints called on the URL of a deployed environment, with checks that hold whatever its data: the status, the content type, the fields the contract promises, 401 without token. Skipped unless `API_BASE_URL` is set: `env-tests.sh <environment>` sets it (with `API_TOKEN`), never another way.

## In memory
One factory per test project, next to the tests (copy the closest existing one when the project has one):
```csharp
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

// The API in memory: its ports replaced by the fakes of the tests, authentication by the test scheme
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication(TestAuthHandler.Scheme)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.Scheme, _ => { });
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
    public const string Scheme = "Test";
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
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme));
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, Scheme)));
    }
}
```
- The tests of an endpoint: one class per controller or group (`OrdersEndpointsTests`), `IClassFixture<ApiFactory>`, `factory.CreateClient()`; a scenario per test, named `<Verb>_<Route>_<Condition>_<Expected>` (`Get_OrderById_Unknown_Returns404`).
- Each test: the data of the scenario put in the fakes, the request (with `X-Test-User`, and `X-Test-Roles` when a role matters), then the status, then what the response says: the body read back as its DTO with its values (`ReadFromJsonAsync<OrderDto>()`), `Location` for a 201, the validation errors of a 400 (`ValidationProblemDetails.Errors` has the field), and what the fakes received (the order saved, with its values). Never only the status of a 2xx.
- The usual scenarios: the nominal one; 400 for each validation rule; 401 without user; 403 with a user that lacks the role or the policy; 404 for an unknown id; 409 when the code answers it. The scenarios the developer validated, no others.
- An endpoint that a policy ties to its own scheme (`[Authorize(AuthenticationSchemes = "Bearer")]`): register the test handler under that scheme name. An endpoint that needs a database the fakes cannot replace (a DbContext used directly): « BLOQUÉ : base de données » in the report (Testcontainers or SQLite are packages: the developer's decision), never a real database.
- Before .NET 10, `WebApplicationFactory<Program>` needs `public partial class Program { }` (test-guardian.sh setup --integration adds it); .NET 10 makes it public itself.
- The proof: `test-guardian.sh green <test project> <filter>`, twice, like any test.

## On an environment
```csharp
using Xunit;

// Runs only against a deployed environment: env-tests.sh <environment> sets API_BASE_URL (and API_TOKEN)
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
using System.Net.Http.Headers;

// The client of the environment: its URL, its token when it has one, and a timeout
public static class EnvironmentClient
{
    public static HttpClient Create(bool withToken = true)
    {
        var client = new HttpClient
        {
            BaseAddress = new Uri(Environment.GetEnvironmentVariable("API_BASE_URL")!),
            Timeout = TimeSpan.FromSeconds(30),
        };
        var token = Environment.GetEnvironmentVariable("API_TOKEN");
        if (withToken && !string.IsNullOrEmpty(token))
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
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
- One class per controller (`<Controller>EnvironmentTests`), `[Trait("Category", "Environment")]` on the class (MSTest: `[TestCategory("Environment")]` and `Assert.Inconclusive` when `API_BASE_URL` is empty; NUnit: `[Category("Environment")]` and `Assert.Ignore`), `[EnvironmentFact]` on each test; the attribute and the client once per test project.
- Checks that hold whatever the data of the environment: the status, the content type, the fields and their JSON kinds, 401 without token (`EnvironmentClient.Create(withToken: false)`), the time when the contract has one. Never a value that depends on its data, except data the test created itself.
- Read only: GET and HEAD. A scenario that writes is marked `[Trait("Category", "EnvironmentWrites")]` instead and undoes what it created in the same test (create, read, delete, in a `try/finally`); `env-tests.sh` runs it only with `--ecriture`, on an environment AGENTS.md marks « écriture permise ». Never production.
- Never a URL, a token or an account in the test code: `API_BASE_URL` and `API_TOKEN` only.
- The proof: `env-tests.sh <the first environment of AGENTS.md that is not production>` (read only). Unreachable from this machine or its token not set (« ENVIRONMENT PROBLEM »): the tests are « écrits, non lancés » with that reason, not « BLOQUÉ ».
- In the CI (a scheduled pipeline): `dotnet test <test project> --filter "Category=Environment"` with `API_BASE_URL` and `API_TOKEN` from masked variables of the project: the convention is the contract, not the script.
