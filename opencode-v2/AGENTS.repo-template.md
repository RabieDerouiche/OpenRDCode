# AGENTS.md (template for one repository — the simplest is to run /outil setup, which fills it from the code; otherwise copy it to the repo root, fill the [...] parts and delete the sections and lines that do not apply. Every agent reads this file at the start of every session: keep it short, rules and files to imitate, no generic knowledge)

## Project type (optional: auto-detected, fill only if the detection is wrong)
- `[cqrs-api | api | blazor | dotnet-app | legacy | library | frontend]`
  - cqrs-api: .NET API with Clean Architecture + CQRS and the in-house mediator
  - api: .NET API without CQRS (controllers / services, or ABP application services)
  - blazor: Blazor application or Razor component library (`.razor` components)
  - dotnet-app: .NET console or worker application
  - legacy: .NET Framework web project (WebForms, MVC 5, WCF)
  - library: shared .NET package published to Artifactory
  - frontend: web front-end (Angular, React, Vue...)

## Project overview
- [2 lines: what this API does, who calls it]

## Dépôts liés (optional: the other repositories of the same application, one line each: name, path when it is not next to this one, role)
- `[front-factures]` (`[~/repos/front-factures]`) : [le front Angular qui appelle cette API]
- `[lib-commun]` : [la librairie NuGet interne des montants, utilisée en version [2.3]]

## Environnements
(optional, an API only: where it is deployed, for /tests env and /outil http. One line each: its name, its base URL, then « jeton : `<VARIABLE>` », the variable of the developer's machine (~/.zshenv) that holds its token, never the token itself; « écriture permise » where tests that write may run; « production » for production, where no test of the pack ever runs. Keep the heading exactly « ## Environnements ».)
- `[recette]` : [https://api-recette.example.com] (jeton : `[API_TOKEN_RECETTE]`, écriture permise)
- `[preprod]` : [https://api-preprod.example.com] (jeton : `[API_TOKEN_PREPROD]`)
- `[prod]` : [https://api.example.com] (production)

## Build & test
- Solution : `[src/App.sln]` (only when the root has several solutions or none)
- Tests locaux : `[--filter "Category!=Integration"]` (only when some tests need Docker, a database or the network)
- CI seulement : `[tests/App.IntegrationTests (Docker, Testcontainers)]`
- Lanceur de tests : `[VSTest | Microsoft.Testing.Platform (xUnit v3 | MSTest | NUnit | TUnit)]`
- Terminal (développeurs) : `[dotnet build src/App.sln]`, `[dotnet test src/App.sln]` (with Microsoft.Testing.Platform on the .NET 10 SDK, `dotnet test` needs `"test": { "runner": "Microsoft.Testing.Platform" }` in global.json; the agents run the tests with the pack's build-test.sh either way)
- La CI vérifie aussi : `[dotnet format --verify-no-changes | npx eslint src | coverage >= 80%]`
- Filet de non-régression : `[80 %]` (only to change the pack's minimum: the share of the lines of the methods a fix touches that tests must run before it)
- EF Core migration : `[dotnet tool restore && dotnet ef migrations add <Name> --project src/[Project].Infrastructure --startup-project src/[Project].Api]`
- Front-end : `[ClientApp]` (the folder of its package.json: the agents build and test it with `build-test.sh [ClientApp]`, its tests once); terminal: `[npm run build]`, `[npm test -- --watch=false --browsers=ChromeHeadless | npx vitest run]`

## Solution structure
- `src/[Project].Api` — endpoints, DI wiring
- `src/[Project].Application` — commands, queries, handlers, validators, ports
- `src/[Project].Domain` — entities, value objects, domain rules
- `src/[Project].Infrastructure` — SharePoint/CSOM, DocuSign, S3, persistence
- `tests/[...]` — unit tests
- Dependencies: `[Domain references nothing; Application → Domain; Infrastructure → Application; Api → all]`
- Target frameworks: `[net10.0]` everywhere, except `[src/[Project].Contracts: netstandard2.0]`

## Code style enforced by the build
- `[Nullable enable, TreatWarningsAsErrors true]` (Directory.Build.props)
- Analyzers that fail the build: `[StyleCop.Analyzers, SonarAnalyzer.CSharp]`; .editorconfig errors: `[file-scoped namespaces, var for built-in types]`
- Formatter checked by the CI: `[dotnet format | CSharpier | Prettier | none]`

## Architecture & conventions
- New endpoint: `[one class per endpoint in src/Api/Endpoints/<Feature>/]`, like `[src/Api/Endpoints/Orders/CreateOrder.cs]`
- Authorization: `[[Authorize(Policy = ...)] on each endpoint | fallback policy | ABP permission]`; new policies in `[file]`
- Errors: `[Result<T> (namespace X) | exceptions + middleware]`, turned into HTTP responses in `[file]`
- Validation: `[FluentValidation validator next to the command | data annotations]`
- New service: registered in `[src/Application/DependencyInjection.cs]`
- Configuration: options classes in `[folder]`; secrets from `[environment variables | secret store]`
- Integrations: always through `[IStorageService (in-house package X) for S3, ISharePointClient for SharePoint]`
- Packages: `[versions in Directory.Packages.props, PackageReference without version | version in each project]`; in-house: `[names]` (their API: existing calls and the XML documentation of the package)

## In-house mediator (cqrs-api only)
- Package: `[package name]`
- Namespace: `[namespace]`
- Request / handler interfaces: `[IRequest<T>]`, `[IRequestHandler<TRequest, TResponse>]`

## Tests
- Framework: [xUnit / NUnit / MSTest / TUnit]; assertions: [AwesomeAssertions / FluentAssertions 7.x / Shouldly / built-in]; mocks: [NSubstitute / Moq / FakeItEasy]
- Naming: `[Method_State_Expected]`; a new test file goes in `[tests/[Project].UnitTests/<same folders as src>]`
- Fixtures and builders: [IClassFixture / ICollectionFixture / base class / builders in `[folder]`]
- Integration tests: [WebApplicationFactory / Testcontainers in `[project]`, need `[Docker | database | network]`]
- Front-end tests: [Jasmine + Karma | Jest | Vitest], [TestBed | Testing Library], specs next to their component (`*.spec.ts`)

## Reference examples (read these before generating similar code)
- Command: `[path/to/Command.cs]`
- Handler: `[path/to/Handler.cs]`
- Validator: `[path/to/Validator.cs]`
- Endpoint: `[path/to/Endpoint.cs]`
- Handler test: `[path/to/HandlerTests.cs]`
- Validator test: `[path/to/ValidatorTests.cs]`

## Git conventions
- Commit messages: `[type(scope): summary (KEY-123) | KEY-123 summary]`
- Merge request template: `[.gitlab/merge_request_templates/Default.md | none]`

## Confluence
- Space key: `[SPACEKEY]`
- Project documentation root page: `[page title]`
- Release notes parent page: `[page title]`

## Releases
- Production is deployed from `master` as is (no tags). Merge requests target `develop`.
- Application name in release notes: `[name]`

## Library (library only)
- Package: `[Company.Lib]`, version `[in src/Lib/Lib.csproj | Directory.Build.props | GitVersion | set by the CI]`; consumers: `[repositories or applications]`
- Compatibility: `[package validation against the last published version (EnablePackageValidation) | PublicAPI.Shipped.txt | none]`; a breaking change: `[a major version, announced to the consumers]`

## Repository-specific rules
- [Add here every mistake the agent made twice]
