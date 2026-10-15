---
description: "Find code changed on the current branch that has no tests, and write the missing tests with the test-writer agent"
agent: test-writer
---
Production files changed on this branch compared to develop:
!`git fetch -q origin develop >/dev/null 2>&1; git diff --name-only origin/develop...HEAD -- '*.cs' | grep -viE '(tests?|\.tests?)/' || true`

Test files changed on this branch:
!`git diff --name-only origin/develop...HEAD -- '*.cs' | grep -iE '(tests?|\.tests?)/' || true`

Steps:
1. For each production file above, check whether the changed behavior is covered by a test (existing or changed on this branch).
2. List the uncovered behaviors as a table: file, method, missing scenario.
3. Write the missing tests, starting with handlers and validators.
4. Run `dotnet test` and report.

Ignore DTOs without logic, DI registration and generated files.
