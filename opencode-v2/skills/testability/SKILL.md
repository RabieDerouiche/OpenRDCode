---
name: testability
description: Makes C# code testable without real time, files, network, environment, randomness or processes - the smallest seam (TimeProvider, a delegate, a minimal interface, a typed HttpClient), wired so production behaves exactly as before, then deterministic tests through it. Load when a test cannot be written or stays non-deterministic because the code calls DateTime.Now/UtcNow, Task.Delay, File/Directory, Environment, Guid.NewGuid, new Random, new HttpClient, Console or Process directly, when a safety net stays INSUFFISANT for that reason, or when reviewing such a seam.
compatibility: opencode
---
# Testability: the smallest seam, then deterministic tests

A test that needs the real clock, a real file, the network or the environment is slow, flaky or impossible. The fix is the smallest seam that lets the test control that one dependency; the production code keeps doing exactly what it did. The seam is a means to the test, never a redesign of the code around it.

Who does what in the pack: only the coder changes production code. The test-guardian never does: it names the obstacle and the seam in its report (« INSUFFISANT » lines, or a test « écarté »), and the pilot plans the seam as a step. In /tests (no production change), the obstacle goes to the answer with « /go sans ticket : ajouter <the seam> dans <class> ».

## 1. Prove the obstacle first
- Read the method and its tests. Name the exact ambient call (`DateTime.UtcNow` at `OrderService.cs:42`) and the behavior that depends on it.
- Look for a seam that already exists before adding one: an injected `TimeProvider`, `IClock`, `ISystemClock`, `IFileSystem`, `IHttpClientFactory`, a typed `HttpClient`, a `Func<DateTime>` field, an existing test fake. Use it.
- Calls that are not obstacles (no seam): `Path.Combine`, `Path.GetExtension`, `Math.*`, string helpers, an `HttpClient` or a service the class already receives by its constructor.
- Two reads of the clock in one operation (`CreatedAt = DateTime.UtcNow; ExpiresAt = DateTime.UtcNow.AddDays(30)`) is a defect of consistency: report it; a seam keeps the two reads as they are unless the step asks to fix it.

## 2. Choose the smallest seam
The target framework decides (the « Target frameworks » line of the detection). Never a new package: what the projects do not reference already is out (a step that needs one is « BLOQUÉ »).

| Dependency | .NET 8 and later | netstandard2.0, .NET 6-7, .NET Framework |
|---|---|---|
| Clock, delays, timers | inject `TimeProvider` (built in) | `TimeProvider` only if `Microsoft.Bcl.TimeProvider` is already referenced; otherwise a `Func<DateTimeOffset>` parameter or the repository's own clock interface |
| One file read or write | an injected delegate (`Func<string, string>` for one `File.ReadAllText`) or a one-member interface; `IFileSystem` only if `System.IO.Abstractions` is already referenced | same |
| HTTP | the typed `HttpClient` or `IHttpClientFactory` the class receives | same |
| Random, `Guid.NewGuid` | inject the one value (`Func<Guid>`, `Func<int>`); `Random` only when the code draws several values | same |
| Environment, console, process | a minimal interface with only the members the code uses (`IEnvironment.GetVariable(string)`) | same |

- Constructor injection is the default for an instance class. Keep the existing constructors working: the public constructor callers use stays, and passes the real dependency (`TimeProvider.System`, `File.ReadAllText`, `Guid.NewGuid`). A test-only constructor is `internal` when the project already declares `InternalsVisibleTo` for the test project, otherwise it is the new public constructor with the seam as a required parameter.
- A library (the « Library » line of the detection) is a contract: no public signature removed or changed; a new public constructor or overload goes into `PublicAPI.Unshipped.txt` when the project tracks its API.
- With dependency injection, register the real dependency once where the repository registers its services (`services.AddSingleton(TimeProvider.System);`), with the lifetime of its conventions. Every place that constructs the class by hand passes the real dependency explicitly.
- A static class or a static API whose signatures cannot change: an ambient seam, and only then. It flows across `await` (`AsyncLocal<T>`, never `[ThreadStatic]`), defaults to the real dependency, and its override returns an `IDisposable` that restores the previous value (nested scopes, an exception unwinding), never a setter, never a reset to `null`:
  ```csharp
  public static class Clock
  {
      private static readonly AsyncLocal<Func<DateTimeOffset>> s_override = new AsyncLocal<Func<DateTimeOffset>>();
      public static DateTimeOffset UtcNow => s_override.Value != null ? s_override.Value() : DateTimeOffset.UtcNow;

      internal static IDisposable Override(DateTimeOffset utcNow)
      {
          var previous = s_override.Value;
          s_override.Value = () => utcNow;
          return new Restore(() => s_override.Value = previous);
      }

      private sealed class Restore : IDisposable
      {
          private Action _restore;
          public Restore(Action restore) { _restore = restore; }
          public void Dispose() { _restore?.Invoke(); _restore = null; }
      }
  }
  ```
  Written in the C# of the project (this one compiles from C# 7.3: no primary constructor before C# 12, `?` annotations only where nullable is enabled).
- The seam wraps only the members the code calls, delegates to the original API, and keeps its behavior: its exceptions, its paths, its time zone and `DateTimeKind`:
  - `DateTime.UtcNow` becomes `timeProvider.GetUtcNow().UtcDateTime` (never `.DateTime`: its kind is `Unspecified`);
  - `DateTime.Now` becomes `timeProvider.GetLocalNow().LocalDateTime`, `DateTimeOffset.UtcNow` becomes `timeProvider.GetUtcNow()`, `DateTimeOffset.Now` becomes `timeProvider.GetLocalNow()`;
  - `Task.Delay(d, ct)` becomes `Task.Delay(d, timeProvider, ct)`, `new CancellationTokenSource(d)` becomes `new CancellationTokenSource(d, timeProvider)`, `new PeriodicTimer(p)` becomes `new PeriodicTimer(p, timeProvider)` (.NET 8 and later).
- No business logic in a seam. The build of the production project passes before any test is written: a compile error then is the seam's.

## 3. Deterministic tests through the seam
- Time: `FakeTimeProvider` when the test project already references `Microsoft.Extensions.TimeProvider.Testing`; otherwise a small fake in the test project:
  ```csharp
  internal sealed class FixedTimeProvider : TimeProvider
  {
      public FixedTimeProvider(DateTimeOffset utcNow) { UtcNow = utcNow; }
      public DateTimeOffset UtcNow { get; set; }
      public override DateTimeOffset GetUtcNow() => UtcNow;
      public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
  }
  ```
  (`LocalTimeZone` fixed: `GetLocalNow()` then gives the same value on every machine; code that converts with `.LocalDateTime` still depends on the zone of the machine, as `DateTime.Now` did: assert on the UTC values, or say it in the report.)
  A fixed instant written in the test (`new DateTimeOffset(2026, 1, 15, 9, 0, 0, TimeSpan.Zero)`), then the assertion of what depends on it (expired, overdue, the date written). A delay: start the operation, assert it is not complete, advance the fake time (`FakeTimeProvider.Advance`), then await. A deadline: just before it (still pending), then across it. Never a real wait.
- Files: the delegate or the fake returns the content written in the test; no real file, no temporary folder when a seam exists.
- HTTP: a hand-written `HttpMessageHandler` whose `SendAsync` returns the response of the test, given to `new HttpClient(handler) { BaseAddress = … }`; assert the request it received (method, path, body) and what the code did with the response. A typed client registered with `AddHttpClient<T>`: build it through the same registration with the handler as its primary handler.
- Environment: the fake interface returns the value; never `Environment.SetEnvironmentVariable` in a test (process-wide, parallel tests break).
- An ambient seam: a test of the override, a test that the previous value is back after the scope (and after an exception inside it), and two overlapping async flows that each see their own value.
- Every test asserts the business result AND one observable that proves the fake drove it (the instant written, the request sent). The skill `test-quality` gives the rest.

## Review
A finding when the diff: adds a seam where one existed; wraps a whole static API for one call; changes a public signature of a library; converts `UtcNow` with `.DateTime`; shares a mutable static fake between tests; sets environment variables or sleeps in a test; adds a package for a seam; leaves a constructor call or a registration without the real dependency (« bloquant »: production breaks or behaves differently).

Adapted for the pack from the skills testability-obstacle, detect-static-dependencies and generate-testability-wrappers of github.com/dotnet/skills (MIT License, Copyright (c) .NET Foundation and Contributors): NOTICE.md.
