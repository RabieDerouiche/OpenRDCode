---
description: "Apply a pattern saved with /extract-pattern to the current repository: pick the back or front version, compare, plan, then implement step 1 only. Usage: /apply-pattern <name> [back|front]"
agent: build
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Apply the pattern "$1" to the current repository.

Steps:
1. Choose the scope: "$2" if given (`back` or `front`); otherwise from the project type detected above (AGENTS.md "Project type" wins if present): `frontend` → `front`, any .NET type → `back`. If the repository is mixed and no scope is given, ask me which one and stop.
2. Load the skill `pattern-$1-<scope>`. If it does not exist, list the available skills whose name starts with `pattern-` and stop.
3. Read "Recommended approach", "Variants" and "Adapting to other project types". Keep only what applies to this project type. If several variants could apply, say which one you choose and why. If the pattern does not apply to this type, say so and stop.
4. Look for what already exists in this repository for "$1" (partial or different implementation). Never duplicate an existing mechanism: adapt the plan to complete or align it instead.
5. Compare the libraries used by the pattern (test framework, mocking, assertions, validation, etc.) with this repository's (the "Test stack" line above and the existing packages). For each library the pattern uses that this repository does not, ask me ONE question: "Garder l'existant (<current>) ou introduire <library> ?". Wait for the answers. Kept → translate the pattern's code and tests to the existing libraries (for example Moq syntax to NSubstitute). Introduced → add the package and use it for the new code only, without rewriting existing code. If this repository has no tests, ask before creating a test project.
6. Check the prerequisites: packages already referenced, versions, framework compatibility (a legacy .NET Framework project cannot use packages that require .NET Core or newer: say so instead of proposing them).
7. Show the plan: files to create, files to modify, configuration keys to add, tests to write. Each step must leave the project building.
8. Implement ONLY step 1 of the plan, following the conventions of this repository (naming, folders, logging, DI style), not the source projects' conventions.
9. Run the build and test commands (AGENTS.md "Build & test" if present, otherwise the detection above) and report. Then stop and wait: I will ask for the next step.

Rules:
- Placeholders from the skill must be replaced with values from this repository or its configuration; if a value is unknown, ask instead of inventing it.
- Never copy configuration values (URLs, hosts, keys) from another project.
