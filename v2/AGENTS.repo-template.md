# AGENTS.md (template for one repository — the simplest is to run /outil setup, which fills it from the code; otherwise copy it to the repo root, fill the [...] parts and delete the sections that do not apply)

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
- [2-3 lines: what this API does, who calls it]

## Solution structure
- [One line per project or main folder, e.g. for a CQRS API:]
- `src/[Project].Api` — endpoints, DI wiring
- `src/[Project].Application` — commands, queries, handlers, validators, ports
- `src/[Project].Domain` — entities, value objects, domain rules
- `src/[Project].Infrastructure` — SharePoint/CSOM, DocuSign, S3, persistence
- `tests/[...]` — unit tests
- Target frameworks: `[net10.0]` everywhere, except `[src/[Project].Contracts: netstandard2.0]`

## Architecture & conventions
- Endpoints: `[controllers | minimal APIs | endpoint classes]` in `[folder]`
- Authorization: `[[Authorize(Policy = ...)] on each controller | fallback policy | ABP permissions]`, policies declared in `[file]`
- Error handling: `[Result<T> in namespace X | exceptions + middleware]`, mapped to HTTP responses in `[file]`
- Validation: `[FluentValidation in Application | data annotations]`
- Configuration: options classes in `[folder]`, files `appsettings.json`, `appsettings.[Env].json`; secrets from `[environment variables | secret store]`
- Feature flags: `[mechanism | none]`
- Integrations: `[S3 via IStorageService (in-house package X), SharePoint via ...]`
- Packages: `[central package management: versions in Directory.Packages.props, PackageReference without version | version in each project]`

## Code style enforced by the build
- `[Nullable enable, ImplicitUsings enable, TreatWarningsAsErrors true]` (Directory.Build.props)
- Analyzers: `[StyleCop.Analyzers, SonarAnalyzer.CSharp]`; .editorconfig errors: `[file-scoped namespaces, var for built-in types]`
- Formatter: `[dotnet format | CSharpier | Prettier | none]`

## Build & test
- Build: `[dotnet build path/to/App.sln | npm run build | not buildable here: .NET Framework needs Windows]`
- Test (full suite that runs on this machine): `[dotnet test path/to/App.sln --filter "Category!=Integration" | npm test -- --watch=false | none]`
- CI only: `[tests/App.IntegrationTests (Docker, Testcontainers)]`
- CI also checks: `[dotnet format --verify-no-changes | npx eslint src | coverage >= 80%]`
- EF Core migration: `[dotnet tool restore && dotnet ef migrations add <Name> --project src/[Project].Infrastructure --startup-project src/[Project].Api]`

## In-house mediator (cqrs-api only)
- Package: `[package name]`
- Namespace: `[namespace]`
- Request / handler interfaces: `[IRequest<T>]`, `[IRequestHandler<TRequest, TResponse>]`

## Tests
- Framework: [xUnit / NUnit / MSTest]
- Assertions: [AwesomeAssertions / FluentAssertions 7.x / Shouldly / built-in]
- Mocks: [NSubstitute / Moq / FakeItEasy]
- Fixtures and builders: [IClassFixture / ICollectionFixture / base class / builders in `[folder]`]
- Integration tests: [WebApplicationFactory / Testcontainers in `[project]`, need `[Docker | database | network]`]

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

## Repository-specific rules
- [Add here every mistake the agent made twice]
