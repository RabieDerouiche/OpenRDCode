---
name: best-practices
description: Checklist of best practices by project type (modern .NET API, CQRS API, legacy .NET Framework, library, front-end), including the Result pattern, feature flags and performance, with how to detect whether each one is already in place. Load to suggest improvements in /check, for a repository audit (/audit), or when asked "is there a better approach".
compatibility: opencode
---
# Best practices by project type

## How to use this checklist
- Only suggest a practice when it APPLIES to the project type and the context (for example no health check for a library, no rate limiting for an internal batch).
- Always check first that it is not already in place, with the "Detect" hint. Quote the evidence (file:line) for "absent" as well as for "present". Never suggest something you did not verify.
- A suggestion is never blocking. It names the benefit in one sentence and the smallest change that brings it.
- If it needs a package the repository does not use yet, say so: the developer decides ("Garder l'existant" or "Introduire").
- If a skill whose name starts with `pattern-` covers the practice (e.g. `pattern-healthchecks-back`), point to it: `/apply-pattern <name>`.
- Follow the existing architecture. Never suggest CQRS, a mediator or Clean Architecture to a project that does not use them.

## Modern .NET API (types api, cqrs-api, dotnet-app with ASP.NET Core)
| Practice | Why | Detect |
|---|---|---|
| Health checks: liveness (process only) and readiness (critical dependencies: database, storage, mandatory external APIs) on separate endpoints | Orchestrators and monitoring know when to restart or stop routing | `AddHealthChecks`, `MapHealthChecks`; readiness checks must not call slow optional dependencies |
| Global error handling returning ProblemDetails, without stack traces in responses | Consistent errors, no information leak | `AddProblemDetails`, `IExceptionHandler`, `UseExceptionHandler`; try/catch in every endpoint is a smell |
| Options validated at startup | A bad configuration fails at boot, not at the first request | `AddOptions<T>().Bind(...).ValidateDataAnnotations().ValidateOnStart()` or a validator; `IConfiguration["..."]` read deep in the code is a smell |
| Outbound HTTP through `IHttpClientFactory` (typed or named clients) with timeouts and resilience (retry, circuit breaker) | No socket exhaustion, controlled failures of external systems | `AddHttpClient`, `new HttpClient(` in a service is a smell; resilience: `AddStandardResilienceHandler` (package Microsoft.Extensions.Http.Resilience) or an existing Polly setup |
| CancellationToken accepted by endpoints and forwarded to every I/O call | Aborted requests stop consuming resources | async methods doing I/O without a `CancellationToken` parameter |
| Structured logging with message templates, correlation id, no personal data or secrets | Searchable logs, GDPR | `_logger.LogInformation($"...")` (interpolation) is a smell; scopes or correlation middleware |
| Secure by default: authorization fallback policy, explicit `[AllowAnonymous]`, restricted CORS | A new endpoint is not public by mistake | `FallbackPolicy`, `RequireAuthorization`, `AllowAnyOrigin` |
| Large files streamed, never fully buffered (S3, SharePoint, DocuSign documents) | Memory | `ToArray()`, `ReadAllBytes`, `MemoryStream` on downloads |
| Nullable reference types enabled, warnings treated seriously | Fewer null bugs | `<Nullable>enable</Nullable>`; many `!` operators are a smell |
| Rate limiting on public endpoints | Abuse protection | `AddRateLimiter`; only if the API is exposed outside |
| Integration tests on the HTTP pipeline | Routing, serialization, auth tested together | `WebApplicationFactory` in the test projects |
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

## Library (type library)
| Practice | Why | Detect |
|---|---|---|
| Public API documented (XML comments) and versioned with SemVer, breaking changes announced | Consumers can upgrade safely | `<GenerateDocumentationFile>`, version in the csproj |
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
