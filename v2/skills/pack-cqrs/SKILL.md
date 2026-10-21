---
name: pack-cqrs
description: "Procédure de /outil cqrs : une command ou une query CQRS avec son handler, son validator et ses tests, dans un projet cqrs-api, en suivant les exemples du dépôt. Arguments : <command|query> <Nom> <Feature>."
compatibility: opencode
---
# /outil cqrs

Started directly as the command `/pack-cqrs` (this procedure is the message that started you, with no line « Skill : pack-cqrs » printed before it): answer only « Lance `/outil cqrs` : cette procédure a besoin de ce que /outil prépare. » and stop.

Arguments: `<command|query> <Name> <Feature>` (the "Arguments" line above). Create that CQRS command or query in the feature.

Only for `cqrs-api` projects (AGENTS.md "Project type", otherwise the detection above). Another type, or an argument missing: ask me once with the question tool, all questions in one call (for the type: "Implémenter sans CQRS en suivant le code existant" (recommandé) / "Annuler"; for the feature: the existing feature folders as options).

Before writing any code (the skill and the examples in the same turn):
1. Load the skill `dotnet-cqrs-conventions`.
2. Read the reference examples of AGENTS.md "Reference examples"; without them, the most recent existing command or query of the Application layer with its handler, validator and tests.
3. Mirror their structure exactly: folders, namespaces, naming, record vs class, response type, mediator interfaces.

Generate:
1. The command or query record (immutable, nullable reference types respected).
2. Its handler, with the in-house mediator interfaces (never MediatR), async, CancellationToken forwarded to every I/O call.
3. A FluentValidation validator with one rule per input constraint.
4. Unit tests for the handler (nominal, not found, failure of each dependency) and the validator (each rule).
5. When the examples show an endpoint per use case, the endpoint in the Api layer, in the existing style.

Rules:
- Do not modify existing files, except the DI registration or the endpoint mapping when strictly required; list every existing file you modified.
- A handler that needs a new port for an external system: declare it in Application and implement the Infrastructure side too, following the existing adapters; say so in the answer.
- Then `sh ~/.config/opencode/scripts/build-test.sh` (with the solution or project of AGENTS.md "Build & test") and report. Fix only the compilation or test errors of the files you created.
- Nothing is committed: on a ticket branch, `/fix` commits and pushes it with the rest.
