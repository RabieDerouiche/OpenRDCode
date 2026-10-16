# AGENTS.md (template for one repository — copy to the repo root and fill the [...] parts)

## Project overview
- [2-3 lines: what this API does, who calls it]

## Solution structure
- `src/[Project].Api` — endpoints, DI wiring
- `src/[Project].Application` — commands, queries, handlers, validators, ports
- `src/[Project].Domain` — entities, value objects, domain rules
- `src/[Project].Infrastructure` — SharePoint/CSOM, DocuSign, S3, persistence
- `tests/[...]` — unit tests

## Build & test
- Build: `dotnet build`
- Test: `dotnet test`

## In-house mediator
- Package: `[package name]`
- Namespace: `[namespace]`
- Request / handler interfaces: `[IRequest<T>]`, `[IRequestHandler<TRequest, TResponse>]`

## Tests
- Framework: [xUnit / NUnit / MSTest]
- Assertions: [FluentAssertions / Shouldly / built-in]
- Mocks: [NSubstitute / Moq / FakeItEasy]

## Reference examples (read these before generating similar code)
- Command: `[path/to/Command.cs]`
- Handler: `[path/to/Handler.cs]`
- Validator: `[path/to/Validator.cs]`
- Endpoint: `[path/to/Endpoint.cs]`
- Handler test: `[path/to/HandlerTests.cs]`
- Validator test: `[path/to/ValidatorTests.cs]`

## Confluence
- Space key: `[SPACEKEY]`
- Project documentation root page: `[page title]`
- Release notes parent page: `[page title]`

## Releases
- Production releases are marked by: `[git tags like v1.2.3 | merges to main | release/* branches]`
- Application name in release notes: `[name]`

## Repository-specific rules
- [Add here every mistake the agent made twice]
