---
description: "Apply a pattern saved with /extract-pattern to the current repository: pick the back or front version, compare, plan, then implement step 1 only. Usage: /apply-pattern <name> [back|front]"
agent: build
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Apply the pattern "$1" to the current repository.

Steps:
1. Choose the scope: "$2" if given (`back` or `front`); otherwise from the project type detected above (AGENTS.md "Project type" wins if present): `frontend` → `front`, any .NET type → `back`. If the repository is mixed and no scope is given, ask me with the question tool (multiple choice, recommended option first): "back" / "front".
2. Load the skill `pattern-$1-<scope>`. If it does not exist, ask me with the question tool (multiple choice, recommended option first) with the available skills whose name starts with `pattern-` as options.
3. Read "Recommended approach", "Variants" and "Adapting to other project types". Keep only what applies to this project type. If several variants could apply, ask me with the question tool (multiple choice, recommended option first) with the variants as options (the skill's recommended approach first). If the pattern does not apply to this type, say so and stop.
4. Look for what already exists in this repository for "$1" (partial or different implementation). Never duplicate an existing mechanism: adapt the plan to complete or align it instead.
5. Compare the libraries used by the pattern (test framework, mocking, assertions, validation, etc.) with this repository's (the "Test stack" line above and the existing packages). For each library the pattern uses that this repository does not, ask me with the question tool (multiple choice, recommended option first): "Garder l'existant (<current>)" (recommandé) or "Introduire <library>". Wait for the answers. Kept → translate the pattern's code and tests to the existing libraries (for example Moq syntax to NSubstitute). Introduced → add the package and use it for the new code only, without rewriting existing code. If this repository has no tests, ask me with the question tool (multiple choice, recommended option first) before creating a test project.
6. Check the prerequisites: packages already referenced, versions, framework compatibility (a legacy .NET Framework project cannot use packages that require .NET Core or newer: say so instead of proposing them). In-house packages ("interne" in the skill) are added with the same name; for the version, ask me with the question tool: "<version of the skill>" (recommandé) / "La dernière disponible". If `dotnet restore` fails with 401/403/NU1301, stop: it is an Artifactory access problem, never a reason to re-implement the package.
6b. Configuration: list the environment files of this repository (`appsettings*.json`, or `web.config` transforms for legacy). Add the keys of the skill to each environment file that needs them, with the placeholders as values, and give me the list of values to fill per environment. Never copy values from the source project; never put secrets in appsettings: secrets come from environment variables or the secret store, as the skill says.
7. Show the plan: files to create, files to modify, configuration keys to add, tests to write. Each step must leave the project building.
8. Implement ONLY step 1 of the plan, following the conventions of this repository (naming, folders, logging, DI style), not the source projects' conventions.
9. Run the build and test commands (AGENTS.md "Build & test" if present, otherwise the detection above), quietly for .NET: `dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60` then `dotnet test --no-build -nologo 2>&1 | tail -60`, and report. Then stop and wait: I will ask for the next step.

Rules:
- Placeholders from the skill must be replaced with values from this repository or its configuration; if a value is unknown, ask instead of inventing it.
- Never copy configuration values (URLs, hosts, keys) from another project.
