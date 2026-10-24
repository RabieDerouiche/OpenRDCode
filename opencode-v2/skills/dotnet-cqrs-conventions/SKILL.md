---
name: dotnet-cqrs-conventions
description: Only for repositories whose project type is cqrs-api (AGENTS.md or the detection), whatever their .NET version (8, 9 or 10). Conventions for Clean Architecture + CQRS APIs with an in-house mediator and FluentValidation; never for a REST API with controllers or services. Load before writing, reviewing or testing commands, queries, handlers, validators, endpoints or their tests.
compatibility: opencode
---
# .NET Clean Architecture + CQRS conventions

These rules apply only to CQRS APIs (AGENTS.md project type `cqrs-api`). For other projects, follow the existing code instead.

These are defaults. AGENTS.md of the repository and its reference examples always win over this file.

## Layers
- Domain: entities, value objects, domain errors. No reference to other projects, no framework dependency.
- Application: commands, queries, handlers, validators, DTOs, ports (interfaces for external systems). References Domain only.
- Infrastructure: implementations of ports (SharePoint/CSOM, DocuSign, AWS S3, Piano Analytics, persistence, HTTP clients). References Application and Domain.
- Api: endpoints, DI wiring, middleware. Endpoints only map HTTP to a request, send it through the mediator and map the result to HTTP. No business logic.

## Mediator
- The repository uses an IN-HOUSE mediator, not MediatR (MediatR v13+ is commercially licensed).
- Never add a MediatR package, `using MediatR`, `AddMediatR` or MediatR types.
- Before writing a handler, find the in-house interfaces by reading an existing handler (namespace and generic signature) and copy them exactly.
- MassTransit / RabbitMQ are message brokers for inter-service messaging. They are NOT a replacement for the in-process mediator.

## One use case = one folder
Typical layout (adapt to the existing one):
```
Application/Features/<Feature>/<UseCase>/
  <UseCase>Command.cs or <UseCase>Query.cs
  <UseCase>Handler.cs
  <UseCase>Validator.cs
  <UseCase>Response.cs (if needed)
tests/<...>.Application.Tests/Features/<Feature>/<UseCase>/
  <UseCase>HandlerTests.cs
  <UseCase>ValidatorTests.cs
```

## Requests
- Commands change state, queries never do.
- Requests are immutable `record` types. Use nullable reference types honestly: if a field can be absent in the JSON, make it nullable and validate it.
- Enums coming from HTTP: validate with `IsInEnum()`; never trust the integer value.
- Do not mix ASP.NET DataAnnotations and FluentValidation on the same DTO: non-nullable reference properties can trigger ASP.NET's implicit [Required] before FluentValidation runs. Follow how the repository already handles this.

## Handlers
- `async` all the way, no `.Result`, `.Wait()`, `async void`.
- Every I/O call receives the CancellationToken.
- Depend on ports (interfaces), never on Infrastructure classes.
- Return the same result type as the existing handlers (result object, response DTO or exception-based errors). Do not introduce a new error-handling style.
- Log with message templates: `logger.LogInformation("Envelope {EnvelopeId} sent", id)`, never interpolation. Messages and comments in English. No secrets, tokens or personal data in logs.

## Validators
- One `AbstractValidator<TRequest>` per request.
- One rule per input constraint, with an explicit error message when the default is unclear.
- File uploads: validate size, extension AND content (magic number), never the extension alone.
- Async rules hitting external systems only if the existing code already does it.

## Tests
- Mirror the existing test project: framework, assertion library, mocking library, naming.
- Handler tests: nominal case, not found, each dependency failure, cancellation.
- Validator tests: each rule, valid and invalid values, boundaries. Prefer `TestValidate` + `ShouldHaveValidationErrorFor`.
- No real network, file system or clock.

## Checklist before saying "done"
- [ ] `dotnet build` passes with no new warning.
- [ ] `dotnet test` passes.
- [ ] No MediatR reference.
- [ ] No Infrastructure reference from Domain or Application.
- [ ] CancellationToken forwarded everywhere.
- [ ] Validator and tests exist for every new request.
