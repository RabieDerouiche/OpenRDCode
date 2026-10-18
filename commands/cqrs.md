---
description: "Scaffold a CQRS command or query with handler, validator and tests. Usage: /cqrs <command|query> <Name> <Feature>"
agent: dev
---
Project detection:
[[run detect-project-type.sh]]

Create a new CQRS $1 named $2 in the feature $3.

This command is only for `cqrs-api` projects (AGENTS.md "Project type" if present, otherwise the project detection above). If it is another type, ask me with the question tool (multiple choice, recommended option first): "Implémenter sans CQRS en suivant le code existant" (recommandé) or "Annuler".

Before writing any code (load the skill and read the examples in the same turn):
1. Load the skill `dotnet-cqrs-conventions`.
2. Read the reference examples listed in AGENTS.md (section "Reference examples"). If there are none, find the most recent existing $1 in the Application layer and read it with its handler, validator and tests.
3. Mirror their structure exactly: folders, namespaces, naming, record vs class, response type, mediator interfaces.

Generate:
1. The $1 record (immutable, nullable reference types respected).
2. Its handler, using our in-house mediator interfaces (never MediatR). Async, CancellationToken forwarded to every I/O call.
3. A FluentValidation validator with one rule per input constraint.
4. Unit tests for the handler (nominal, not found, failure of each dependency) and the validator (each rule).
5. If the existing examples show an endpoint per use case, the endpoint in the Api layer, following the existing endpoint style.

Rules:
- Do not modify existing files, except DI registration or endpoint mapping if strictly required. List every existing file you modified.
- If the handler needs a new port (interface) for an external system, declare it in Application, then ask me with the question tool (multiple choice, recommended option first): "Implémenter aussi l'Infrastructure" or "M'arrêter là".
- If an argument is missing or unclear, ask me with the question tool (multiple choice, recommended option first) before generating (for the feature, propose the existing feature folders as options).

When done, run `sh ~/.config/opencode/scripts/build-test.sh` (quiet build, then the tests if the build passed, in one call; with the solution or project of AGENTS.md "Build & test" as first argument if it names one) and report the result. Fix only compilation or test errors in the files you created.
