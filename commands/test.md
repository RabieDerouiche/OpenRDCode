---
description: "Check and complete the unit tests of the current work: map the acceptance criteria and the changed code to tests, write the missing ones in the project's style (or like a pattern or another repository), run them until green, and update the ticket sheet (.NET or front-end). Usage: /test [path/to/file] [comme <pattern name or repository path>]"
agent: test-writer
subtask: false
---
Arguments: "$ARGUMENTS" (optional: a file path to test only that file, and/or "comme <pattern name or repository path>" for the reference approach)

Base branch: the "Base branch" line of the workflow state (origin/develop, otherwise origin/main or origin/master). If it says NONE, ask me with the question tool for the base branch (free answer).

Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Workflow state (one fetch, then the state of the branch and of the ticket sheet):
!`sh ~/.config/opencode/scripts/workflow-state.sh`

## Step 0 - Changes pushed from another computer
If the branch status above says "behind" its remote copy, commits were pushed from another computer (for example from Rider on my Mac) and are not here yet. Stop and say: "<n> commit(s) poussé(s) depuis un autre poste ne sont pas ici : lance /sync d'abord". Continue only if I ask.

## Step 1 - Scope
- If a reference is given ("comme ..."), apply step 5 of your rules with it (pattern skill or other repository) before writing any test.
- If a file is given above: test only that file. Read it and write unit tests for the class, module or component it contains. If a test file for it already exists, add the missing cases to it instead of creating a new file. Cover every public method or exported member. Skip step 2 and go to step 4.
- Otherwise: the scope is every file changed on the branch plus the uncommitted and untracked files of the workflow state. Split this list yourself:
  - Test files: paths containing `Tests/`, `.Tests/`, `tests/`, `test/`, `__tests__/`, or names ending in `.spec.*` / `.test.*`.
  - Production source files: `.cs`, `.ts`, `.tsx`, `.js`, `.jsx`, `.vb` files that are not test files.
  - Ignore everything else (configuration, assets, documentation, generated files, migrations), and ignore DTOs and models without logic and DI registration.
  If there is no production source file, say "Aucun code à tester sur cette branche" and stop.

## Step 2 - Acceptance criteria
- The Jira key is in the branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`). If `<KEY>.md` is in the list of ticket sheets above, read `.git/opencode/tickets/<KEY>.md`: its "Critères d'acceptation" and "Tests attendus" sections are the reference.
- If there is no sheet, read the acceptance criteria of the ticket with the Jira MCP tools (read-only) and say "Pas de fiche ticket : lance /ticket <KEY> pour en créer une". If there is no key, skip the criteria.

## Step 3 - What is missing
For each production source file, check whether the changed behavior is covered by a test (existing, changed on this branch, or uncommitted). Show one table:
| Critère ou comportement | Fichier / méthode ou composant | Test existant | Scénario manquant |
Every acceptance criterion appears at least once. Business logic first.

## Step 4 - Write the missing tests
Follow your rules (project type, existing test style, reference approach and its questions, test stack question before any new library, no test project creation without asking, which test project to use).

## Step 5 - Run until green
Run the build and test commands (AGENTS.md "Build & test" if present, otherwise the project detection above). Fast runs (.NET): build once with `dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60`, then run the tests on that build with `dotnet test --no-build -nologo 2>&1 | tail -60`. Use the AGENTS.md commands when they exist, with the same options. While fixing your own tests, rerun only them, without `--no-build` since the test files changed: `dotnet test <test project> -nologo --filter FullyQualifiedName~<TestClass> 2>&1 | tail -60`; run the full suite once at the end. If tests you wrote fail, fix the tests only and run again, at most 3 rounds. A failure that reveals a real bug in production code stays failing, with a clear English comment, and is reported.

## Step 6 - Ticket sheet
If the sheet exists, update it with the edit tool:
- In "Tests attendus", set Statut of each row: `✅ <TestName>`, `❌ manquant` or `🐞 bug suspecté`; add rows for tests written for behaviors that were not listed.
- Append to "## Suivi": `- <date> /test - <n> tests ajoutés - <passed>/<total> tests verts` (date with `date "+%Y-%m-%d %H:%M"`).
Never write any other file outside the test folders.

## Answer, in French
First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name.
The table of step 3 with the final status, the tests added (name + one line each), the test command result, the suspected bugs, then one line: "Prochaine étape : /check" (or "corrige le bug avec l'agent build, puis /test" if a bug was found).
