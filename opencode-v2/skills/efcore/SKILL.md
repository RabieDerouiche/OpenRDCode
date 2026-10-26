---
name: efcore
description: Entity Framework Core in .NET 8, 9 and 10 applications - queries that stay fast (no N+1, projections, AsNoTracking, split queries, pagination, bulk updates), writes and transactions (one SaveChanges per unit of work, concurrency, the retrying execution strategy), migrations that never lose data (with the only EF commands the agents of the pack may run), and the tests of code that uses a DbContext (SQLite, never the InMemory provider for a query). Load before writing, reviewing or debugging code that touches a DbContext, an entity or its configuration, a LINQ query on a DbSet or a migration.
compatibility: opencode
---
# Entity Framework Core

The version comes first: the « EF Core » line of the project detection (`detect-project-type.sh`) gives it, with the providers. EF Core 8 runs on .NET 8, EF Core 9 on .NET 8 and 9, EF Core 10 on .NET 10 only. Write for the version the project references; never change an EF Core package version or add a provider: a step that needs it is « BLOQUÉ » with what is needed. The conventions of the repository win (its repositories, its `DbContext` configuration, its query style): read the closest existing query or migration first.

## Queries
| Rule | Why | Smell |
|---|---|---|
| A read that changes nothing is `AsNoTracking()` (or projects with `Select`), unless the context is already configured with `QueryTrackingBehavior.NoTracking` | No change tracker cost, no stale entity kept in the context | `ToListAsync()` on entities that are only returned |
| Project to what is returned: `Select(o => new OrderDto(o.Id, o.Total))` | Only the needed columns travel; a projection is never tracked | entities loaded, then mapped in memory to a DTO of three fields |
| No query inside a loop over results: one query with `Include` or a projection, or one query with `Contains` on the ids | N+1: one round trip per row | `foreach` with `await _db.X.FirstOrDefaultAsync(…)` inside; a navigation read in a loop with lazy loading (`UseLazyLoadingProxies`) |
| Several collection `Include` on one query: `AsSplitQuery()` (or the global `UseQuerySplittingBehavior` the repository already uses) | One SQL join of two collections multiplies rows (cartesian explosion) | `Include(o => o.Lines).Include(o => o.Payments)` on large data; EF warns « MultipleCollectionIncludeWarning » |
| A page is ordered: `OrderBy(…).ThenBy(x => x.Id).Skip(n).Take(size)` | Without a total order, rows move between pages (and a split query needs it) | `Skip`/`Take` without `OrderBy` (EF warns « row limiting operator without OrderBy ») |
| Lists are bounded: a page, or a `Take` the caller cannot exceed | Memory and database load grow with the data | `ToListAsync()` on a table that grows, behind an endpoint |
| Existence is `AnyAsync`, a count is `CountAsync`, one row by key is `FirstOrDefaultAsync` (or `FindAsync`, which looks in the change tracker first) | `SingleOrDefaultAsync` reads two rows to check uniqueness; `ToList().Count` loads everything | `(await q.ToListAsync()).Count > 0` |
| The query stays in SQL up to its end: no `AsEnumerable()` or `ToList()` in the middle | Everything before it is loaded, the rest filtered in memory | `.AsEnumerable().Where(…)` on a DbSet |
| A filter on a column keeps its index: compare the column as stored (`x.Email == email`, the database collation decides the case) | `ToLower()` or a function on the column disables the index | `Where(u => u.Email.ToLower() == …)` |
| Raw SQL is parameterized: `FromSql($"… {id}")` (EF Core 7 and later) or `FromSqlInterpolated`, `ExecuteSql($"…")` | `FromSqlRaw` or `ExecuteSqlRaw` with a concatenated string is a SQL injection (Fortify « SQL Injection ») | `FromSqlRaw("… WHERE Name = '" + name + "'")` |
| `Contains` on a list of values (SQL Server): EF Core 8 and later send it as one JSON parameter (`OPENJSON`); a database at a compatibility level below 130 refuses it: `UseSqlServer(…, o => o.UseCompatibilityLevel(<its level>))`, the setting of the repository | The query fails only on that database | an error near `OPENJSON` on one environment only |

## Writes and transactions
- One unit of work, one `SaveChangesAsync` (it is a transaction): never inside a loop. `AddRange` and the changes of many entities go in one call; EF batches the statements.
- An update loads, changes and saves (`var o = await _db.Orders.FindAsync(id); o.Status = …; await _db.SaveChangesAsync();`). `Update(entity)` on a detached object marks every column modified: only where the repository already does it.
- Many rows at once: `ExecuteUpdateAsync` / `ExecuteDeleteAsync` (EF Core 7 and later): one SQL statement, no entity loaded. They bypass the change tracker, `SaveChanges`, its interceptors and its audit fields, and do not update the entities already loaded: only where none of that matters, and say so in the decisions. EF Core 10 takes the setters as a plain lambda (`s => s.SetProperty(o => o.Status, OrderStatus.Closed)` compiles on 8, 9 and 10); code that builds them as an expression tree must be rewritten on 10: the compiler says it.
- Several `SaveChangesAsync` that must succeed together: one transaction (`BeginTransactionAsync`). When the context enables retries (`EnableRetryOnFailure`), the whole unit runs inside `_db.Database.CreateExecutionStrategy().ExecuteAsync(async () => { … })`: a user-initiated transaction outside it throws « does not support user-initiated transactions ».
- Concurrency: an entity with a concurrency token (`[Timestamp]` / `IsRowVersion()`, or `IsConcurrencyToken()`) throws `DbUpdateConcurrencyException` when someone changed it meanwhile: map it to 409 where the API maps its conflicts, never retry blindly. A unique index violation is a `DbUpdateException` (the provider's exception inside): a duplicate is a 409 too; a check-then-insert without the index is a race.
- A `DbContext` is scoped and not thread safe: never two operations on the same context at once (`Task.WhenAll` over one context throws « A second operation was started on this context instance »). Concurrent database work uses `IDbContextFactory<T>` (one context per task) when the repository registers it, otherwise sequential awaits. A singleton or a hosted service creates a scope (`IServiceScopeFactory`) per unit of work, never holds a context.
- `EnableSensitiveDataLogging` never outside the development environment: it writes parameter values (personal data) to the logs.

## Migrations
The agents of the pack run only these EF commands (permission rules), with the projects of AGENTS.md « Build & test » (its « EF Core migration » line; otherwise `--project <the project of the DbContext> --startup-project <the web or host project>`):
- `dotnet ef migrations add <Name>`: after any change of an entity, its configuration or the `DbContext`, in the same step. A name that says the change (`AddOrderStatus`, `RenameCustomerEmail`).
- `dotnet ef migrations has-pending-model-changes` (EF Core 8 and later): the model and the last migration agree. With EF Core 9 and later, `Database.Migrate()` throws at start when they do not (`PendingModelChangesWarning`), and so does a `HasData` seeded with a value that changes at each build (`DateTime.Now`, `Guid.NewGuid()`): use constants.
- `dotnet ef migrations script` (with `--idempotent` when the team deploys by script) and `dotnet ef migrations list --no-connect`.
Never `database update`, `migrations remove` or a command that connects to a database: refused, and a database of the machine is not the team's.

Read the migration EF generated before the report, every time:
- A rename EF did not recognize is a `DropColumn` + `AddColumn`: the data is lost. Write `RenameColumn` (or `RenameTable`) by hand in the migration, and keep the model snapshot as EF wrote it.
- A column made required (`nullable: false`) on a table with rows: a value for the existing rows first, `migrationBuilder.Sql("UPDATE … SET … WHERE … IS NULL")` before the `AlterColumn`, or a `defaultValue`.
- A narrowed type or length (`nvarchar(max)` to `nvarchar(100)`, `decimal(18,4)` to `decimal(18,2)`): truncation; the step says it in « Décisions ».
- A `DropTable` or `DropColumn` the ticket asks for: in its own migration, said in « Décisions » and in the merge request (« Points d'attention »).
- Never edit the model snapshot by hand, nor a migration that is already on develop: a new migration changes what an old one did.
- After a merge of develop, two migrations with the same parent (the branch's and develop's): take the snapshot as develop has it (`git show origin/develop:<the snapshot file>`, written back with the write tool), delete the two files of the branch's migration (`<timestamp>_<Name>.cs` and its `.Designer.cs`), then `migrations add <Name>` again: it is built on develop's last migration.

## Tests of code that uses a DbContext
- The InMemory provider (`UseInMemoryDatabase`) is not a relational database: no SQL translation, no constraint, no transaction, no unique index. A query test on it can pass while the same query fails in SQL: never for a query, a constraint or a transaction. Keep it only where the repository's existing tests use it for something else.
- SQLite in memory is the default for these tests (the skill `api-tests` gives the factory of an API): one open `SqliteConnection("DataSource=:memory:")` kept for the test, `UseSqlite(connection)`, `EnsureCreated()` (the schema from the model; the migrations target the real database). SQLite has no native `decimal`, `DateTimeOffset` or `TimeSpan`: comparisons, ordering and sums on them may not translate (« could not be translated »): a limit of the test database, not a bug of the code; such a query is checked where the CI runs the real database, and said so.
- A test that only needs what a repository returns mocks the repository (the port), never the `DbContext` or a `DbSet`.
- What the test checks is what the user sees: the rows written (read back with a new context), the status returned, the conflict raised; never only that `SaveChangesAsync` was called.

## Review
- Every point above is a finding when the diff breaks it: a query in a loop, an unbounded list behind an endpoint, a raw SQL concatenation (« bloquant »), a migration that loses data without its step (« bloquant »), an entity change without its migration (« bloquant »), a context shared between tasks (« bloquant »), `ExecuteUpdate` where the audit fields or interceptors matter (« majeur »).
- Generated files (`*.Designer.cs` of migrations, `*ModelSnapshot.cs`) are named, never read in full: the migration itself (`Up`, `Down`) is read.
