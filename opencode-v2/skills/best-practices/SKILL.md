---
name: best-practices
description: Checklist of best practices by project type (modern .NET API on .NET 8, 9 or 10, CQRS API, REST contract, Blazor, legacy .NET Framework, library published as a NuGet package, front-end, tests), including the Result pattern, feature flags, performance, running on several instances, package validation and tests that prove behaviors, with how to detect whether each one is already in place. Load for a decision about error handling, a feature flag or performance (the coder), for a repository audit (/outil audit), or when asked "is there a better approach".
compatibility: opencode
---
# Best practices by project type

## How to use this checklist
- Only suggest a practice when it APPLIES to the project type and the context (for example no health check for a library, no rate limiting for an internal batch).
- Always check first that it is not already in place, with the "Detect" hint. Quote the evidence (file:line) for "absent" as well as for "present". Never suggest something you did not verify.
- A suggestion is never blocking. It names the benefit in one sentence and the smallest change that brings it.
- If it needs a package the repository does not use yet, say so: the developer decides ("Garder l'existant" or "Introduire").
- If a skill whose name starts with `pattern-` covers the practice (e.g. `pattern-healthchecks-back`), point to it: `/go <KEY> comme le pattern <name>` (a pattern skill is applied by /go).
- Follow the existing architecture. Never suggest CQRS, a mediator or Clean Architecture to a project that does not use them.
- Every suggestion needs a current, concrete benefit: a real bug, a production risk that is measured or likely for this load and this deployment, or a requirement of the ticket. "If one day…" is not a reason: no abstraction, layer, pattern or package for a hypothetical need (for example no `IHttpClientFactory` for a call made once a day, no interface or service that only forwards calls).

## Modern .NET API (types api, cqrs-api, dotnet-app with ASP.NET Core)
| Practice | Why | Detect |
|---|---|---|
| Health checks: liveness (process only) and readiness (critical dependencies: database, storage, mandatory external APIs) on separate endpoints | Orchestrators and monitoring know when to restart or stop routing | `AddHealthChecks`, `MapHealthChecks`; readiness checks must not call slow optional dependencies |
| Global error handling returning ProblemDetails, without stack traces in responses | Consistent errors, no information leak | `AddProblemDetails`, `IExceptionHandler`, `UseExceptionHandler`; try/catch in every endpoint is a smell |
| Options validated at startup | A bad configuration fails at boot, not at the first request | `AddOptions<T>().Bind(...).ValidateDataAnnotations().ValidateOnStart()` or a validator; `IConfiguration["..."]` read deep in the code is a smell |
| Registration code never builds a second container | `BuildServiceProvider()` during registration creates another container: duplicated singletons, warning ASP0000 | `BuildServiceProvider(` outside tests; to use a registered service while configuring options: `AddOptions<T>().Configure<TDep>(...)`, `IConfigureOptions<T>` or `IConfigureNamedOptions<T>` |
| Lists that differ per environment are not JSON arrays | Arrays of `appsettings.<Environment>.json` merge with the base file by index (item 0 replaces item 0, the other base items stay): Serilog sinks or allowed origins get silently mixed or lost | arrays redefined in environment files; prefer objects keyed by name (`"Sinks": { "Console": {...} }`) |
| Safe with several instances (Kubernetes pods) | Each pod has its own memory and disk | shared state in static fields or a memory cache, uploads written to `wwwroot` or the local disk (use the database or object storage), Data Protection keys not persisted (`PersistKeysTo...`), in-memory locks or sessions |
| Outbound HTTP through `IHttpClientFactory` (typed or named clients) with timeouts and resilience (retry, circuit breaker) | No socket exhaustion, controlled failures of external systems | `AddHttpClient`, `new HttpClient(` in a service is a smell; resilience: `AddStandardResilienceHandler` (package Microsoft.Extensions.Http.Resilience) or an existing Polly setup |
| CancellationToken accepted by endpoints and forwarded to every I/O call | Aborted requests stop consuming resources | async methods doing I/O without a `CancellationToken` parameter |
| Structured logging with message templates, correlation id, no personal data or secrets | Searchable logs, GDPR | `_logger.LogInformation($"...")` (interpolation) is a smell; scopes or correlation middleware |
| Secure by default: authorization fallback policy, explicit `[AllowAnonymous]`, restricted CORS | A new endpoint is not public by mistake | `FallbackPolicy`, `RequireAuthorization`, `AllowAnyOrigin` |
| Large files streamed, never fully buffered (S3, SharePoint, DocuSign documents) | Memory | `ToArray()`, `ReadAllBytes`, `MemoryStream` on downloads |
| Nullable reference types enabled, warnings treated seriously | Fewer null bugs | `<Nullable>enable</Nullable>`; many `!` operators are a smell |
| Rate limiting on public endpoints | Abuse protection | `AddRateLimiter`; only if the API is exposed outside |
| Integration tests on the HTTP pipeline | Routing, serialization, auth tested together | `WebApplicationFactory` in the test projects (package Microsoft.AspNetCore.Mvc.Testing of the same major version as the API) |
| Time through `TimeProvider` (.NET 8 and later), never `DateTime.Now` / `UtcNow` in business code | Time-dependent rules (expiry, deadlines, schedules) testable with `FakeTimeProvider` (Microsoft.Extensions.TimeProvider.Testing) | `DateTime.Now`, `DateTime.UtcNow`, `DateTimeOffset.UtcNow` in services or handlers; an in-house `IClock` or `IDateTimeProvider` already there: keep it |
| The HTTP contract described and stable: OpenAPI document generated from the code, a field or route removed or renamed only with its consumers | The front-end and the other clients keep working | `AddOpenApi` (.NET 9 and later) or Swashbuckle / NSwag; `api-surface.sh <base>` lists the routes and contract fields a branch removes or changes |
| Result pattern for expected business failures (not found, validation, conflict, forbidden, failure of an external system that the caller must handle): methods return a result (success value or typed error), exceptions stay for unexpected failures; the result is mapped to ProblemDetails / status codes in one place at the endpoint | Explicit failure paths, no exceptions for control flow, cheaper than throwing | An existing result type (in-house `Result<T>`, FluentResults, ErrorOr, Ardalis.Result, OneOf): if there is one, every new handler or service with expected failures must use it. If there is none, introducing one is a decision for the developer: propose a minimal in-house `Result<T>` / `Error` or keep exceptions. Smells: `throw new NotFoundException` caught in the controller, `null` returned to mean "not found", `bool` + `out` error message |
| Feature flags for changes that must not be visible as soon as they reach master (production deploys master as is), progressive rollouts, or behavior that business may switch off | Merge unfinished or risky work without exposing it; instant rollback without redeploy | An existing mechanism (`Microsoft.FeatureManagement`, `IFeatureManager`, a `FeatureFlags` / `Features` section in appsettings, an in-house service): reuse it. If there is none, introducing one is a decision for the developer. Only suggest a flag when the change is user-visible, risky, or not finished for the next deployment; never for internal refactorings. Every flag needs an owner and a removal ticket |

## Performance (every .NET project)
| Practice | Why | Detect |
|---|---|---|
| No N+1: no query or HTTP call inside a loop over results | Latency grows with the data | `foreach` containing `await _repository...`, `await _client...`, lazy-loaded navigation properties |
| Bounded queries: pagination or limits on lists, projection of the needed columns only | Memory and database load | `ToListAsync()` without `Take`/paging on large tables, `Include` chains loading whole graphs; with EF Core reads, `AsNoTracking` |
| No sync over async, no blocking in request paths | Thread pool starvation | `.Result`, `.Wait()`, `GetAwaiter().GetResult()`, `Thread.Sleep` |
| Payloads streamed, not buffered (files, S3, SharePoint, exports) | Memory peaks, large object heap | `ToArray()`, `ReadAllBytes`, `MemoryStream` on large content, `ReadAsStringAsync` on large responses |
| Cache for data that is read often and changes rarely (reference data, configuration from external systems), with an expiration | Fewer calls to slow systems | repeated identical calls per request; `IMemoryCache`, `HybridCache` or an existing cache service |
| Independent I/O calls run concurrently when the order does not matter | Latency | sequential awaits of unrelated calls; `Task.WhenAll` with a bounded degree of parallelism |
| Cheap logging and string handling in hot paths | CPU and allocations | string interpolation in log calls, string concatenation in loops, `new Regex(` per call (use a static or generated regex) |
| Outbound clients reused (`IHttpClientFactory`, singleton SDK clients such as the S3 client) | Socket and connection exhaustion | `new AmazonS3Client(`, `new HttpClient(` per call |

## CQRS API (type cqrs-api), in addition
| Practice | Why | Detect |
|---|---|---|
| One request per use case with its validator and handler tests | Rules of `dotnet-cqrs-conventions` | handler without validator or tests |
| Cross-cutting concerns (validation, logging) in pipeline behaviors of the in-house mediator, not repeated in handlers | No duplication | the same validation or logging code at the start of many handlers |
| Handlers return the repository's result type for expected failures; validators' errors map to the same error model | One error contract for every endpoint | handlers throwing for "not found" or business rules |

## Blazor (type blazor), in addition to the .NET API practices that apply to the host
| Practice | Why | Detect |
|---|---|---|
| Untrusted HTML sanitized before `MarkupString` | XSS | `(MarkupString)` or `new MarkupString(` on data from users, templates or external systems; reuse the sanitizer the repository already has |
| No user state in singletons or static fields (Blazor Server) | A singleton is shared by every user of the server | `AddSingleton<` services holding user data, `static` mutable fields in components or services; per-user state is scoped (one scope per circuit) |
| Subscriptions, timers and JS objects released | Memory leaks and errors after the circuit closes | `+=` without `-=` in `Dispose`, `new Timer(`, `DotNetObjectReference.Create`, `IJSObjectReference` without `DisposeAsync` |
| Typed route parameters | Free validation, and Fortify does not credit route constraints on a `string` parameter | `@page "/x/{Id}"` with `string Id` instead of `{Id:guid}` and `Guid Id` |
| Large lists virtualized or paged | Render time and circuit memory | `@foreach` over large collections, grids without paging; `<Virtualize>` or the paging of the component library |
| Error boundaries around components that can fail | One failing component does not break the page | `<ErrorBoundary>` |
| JS interop after the first render | Exceptions during prerendering | `IJSRuntime` calls in `OnInitializedAsync` instead of `OnAfterRenderAsync(firstRender)` |

## Legacy .NET Framework (type legacy)
Keep the existing patterns. Suggest only what the target framework supports.
| Practice | Why | Detect |
|---|---|---|
| Global error handling (`Application_Error`, `customErrors` mode On or RemoteOnly) | No yellow screen with stack traces | `Global.asax`, `web.config` |
| Request validation and anti-forgery kept on | XSS and CSRF | `validateRequest="false"`, `[ValidateInput(false)]`, missing `@Html.AntiForgeryToken()` / `[ValidateAntiForgeryToken]` on POST |
| A single shared `HttpClient`, TLS 1.2 or more | Socket exhaustion, security | `new HttpClient(` per call, `ServicePointManager.SecurityProtocol` |
| Secrets out of `web.config` (config transforms or environment) | Leaks through the repository | connection strings or passwords in plain text |
| A simple health endpoint (for example `/health` returning 200 after a dependency check) | Monitoring | no such route or handler |
| Feature switches through `appSettings` keys when a change must stay hidden in production | Same reason as for modern APIs | existing keys such as `Feature.*` or `Enable*` in `web.config` |

## Library (type library, a NuGet package of the team)
| Practice | Why | Detect |
|---|---|---|
| Public API documented (XML comments) and versioned with SemVer, breaking changes announced | Consumers can upgrade safely | `<GenerateDocumentationFile>`, version in the csproj (the « Library » line of `detect-project-type.sh` says where it comes from) |
| Package validation against the last published version | `dotnet pack` fails on a breaking change of the public API (CP0002…), before the consumers find it | `<EnablePackageValidation>true</EnablePackageValidation>` and `<PackageValidationBaselineVersion>`; `build-test.sh --pack` runs it; a `CompatibilitySuppressions.xml` that hides a break is a smell |
| Public API tracked in files (Microsoft.CodeAnalysis.PublicApiAnalyzers) | Every change of the public API is visible in the merge request | `PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt`; RS0016 for a new member |
| Multi-targeting only for real consumers (netstandard2.0 for .NET Framework consumers), the code compiling for each target | No API used that one target lacks | `<TargetFrameworks>`; `#if NET8_0_OR_GREATER` where the APIs differ |
| Source Link and symbols, deterministic build | Consumers debug into the package | the Source Link tooling is part of the .NET 8 SDK and later (older SDKs: a `Microsoft.SourceLink.*` package), `<IncludeSymbols>`, `ContinuousIntegrationBuild` in the CI |
| `ConfigureAwait(false)` on awaits in library code | No deadlocks in legacy or UI consumers | awaits without it |
| Depends on abstractions only (`Microsoft.Extensions.Logging.Abstractions`, options), no static mutable state | Consumers choose the implementation | references to concrete logging frameworks, static fields |
| CancellationToken on public async methods | Consumers can cancel | public async methods without it |

## Front-end (type frontend)
| Practice | Why | Detect |
|---|---|---|
| Environment configuration, no hard-coded API URLs | Same build for every environment | `http://` or `https://` literals in services |
| Central HTTP error handling (interceptor) and user-facing error states | Consistent errors | many components handling the same HTTP errors |
| Subscriptions and effects cleaned up | Memory leaks | `subscribe(` without `takeUntil`/`async` pipe/`DestroyRef` (Angular), `useEffect` without cleanup (React) |
| Strict TypeScript and lint in CI | Fewer runtime bugs | `"strict": true` in tsconfig, lint script |
| No tokens in `localStorage` unless the existing code already does it | XSS exposure | `localStorage.setItem` with tokens |
| Accessible new UI (labels, roles, keyboard) | Users and compliance | inputs without labels, click handlers on non-interactive elements |
| Unit tests that run once in the CI (headless browser or jsdom), never focused | A `fit` or `.only` silently skips the rest of the suite | `fdescribe(`, `fit(`, `.only(` in specs; Karma with `ChromeHeadless`, Vitest `run`; `build-test.sh <folder>` runs them as the CI does |
| The API calls typed from the contract of the back-end (a client generated from its OpenAPI document, or interfaces kept in step with it) | A field renamed on one side breaks at compile time, not in production | a generator script in package.json (`openapi-generator`, `orval`, `ng-openapi-gen`, `nswag`); hand-written DTO interfaces far from the API |

## Tests (every project type)
| Practice | Why | Detect |
|---|---|---|
| A test per behavior the code promises (an acceptance criterion, a business rule, an error path), with concrete values and the expected result written in the test | A test that only runs lines raises the coverage and proves nothing | `test-lint.sh <files>`: a test without assertion, an assertion that cannot fail; an expected value recomputed with the code under test |
| Deterministic tests: no real clock, delay, network, random or shared state | A test that fails once in ten is ignored, then hides a real failure | `test-lint.sh`: `DateTime.Now`, `Thread.Sleep`, `Task.Delay`, `new Random()`, `setTimeout`, a real `HttpClient` |
| No skipped or focused test left in the code | A skipped test is a forgotten failure; a focused one hides the others | `[Fact(Skip`, `[Ignore]`, `xit(`, `it.skip(`, `fit(`, `.only(` |
| The right level: unit tests for the rules, integration tests (WebApplicationFactory, Testcontainers in the CI) for the wiring, the queries and the HTTP contract | Each kind of defect is found where it is cheap to find | only unit tests that mock everything around an endpoint; only end-to-end tests |
