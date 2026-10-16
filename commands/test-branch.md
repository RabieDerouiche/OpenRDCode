---
description: "Find code changed on the current branch that has no tests, and write the missing tests with the test-writer agent (.NET or front-end)"
agent: test-writer
---
Fetch develop: !`git fetch -q origin develop`

Files changed on this branch compared to develop:
!`git diff --name-only origin/develop...HEAD`

Split this list yourself:
- Test files: paths containing `Tests/`, `.Tests/`, `tests/`, `test/`, `__tests__/`, or names ending in `.spec.*` / `.test.*`.
- Production source files: `.cs`, `.ts`, `.tsx`, `.js`, `.jsx`, `.vb` files that are not test files.
- Ignore everything else (configuration, assets, documentation, generated files, migrations).

Steps:
1. For each production source file, check whether the changed behavior is covered by a test (existing or changed on this branch).
2. List the uncovered behaviors as a table: file, method or component, missing scenario.
3. Write the missing tests, starting with the code that holds business logic.
4. Run the test command from AGENTS.md and report.

Ignore DTOs and models without logic, DI registration and generated files.
