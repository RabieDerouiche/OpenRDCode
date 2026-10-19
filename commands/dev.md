---
description: "Implement the next step of the ticket sheet (or step N) following my directives, write the unit tests of that step, build and run them, tick the step, then offer the next one. Asks multiple-choice questions whenever the approach is unclear. Usage: /dev [N] [directives, e.g. « comme dans ~/dev/autre-api », « avec un Result », « sans nouvelle lib », « tests avec fixtures xUnit »]"
agent: dev
---
Arguments: "$ARGUMENTS"
Workflow state (one fetch, then the state of the branch and its ticket sheet):
[[run workflow-state.sh --sheet]]
Project detection:
[[run detect-project-type.sh]]

Implement ONE step of the ticket plan, with its tests. Never commit or push: that is /ship.

Tools over shell: read files with the `read` tool, search with `grep` and `glob`, change files with `edit`/`write`. Use the shell only for the build, the tests, git reads and the `~/.config/opencode/scripts` commands. Never inspect the environment or the NuGet configuration (`cat`/`grep` on `nuget.config`, `~/.nuget`, `.env`, `~/.zshenv`, `env`, `export`, `printenv`): a failed `dotnet restore` (401/403/NU1301), a missing `dotnet` or an "ENVIRONMENT PROBLEM" line of a script is an environment problem I fix outside OpenCode: say so in one line and stop, never work around it.

## Step 0 - Before starting
- If the "Branch vs its remote copy" line above says "behind", commits were pushed from another computer (for example from Rider on my Mac): say "Lance /sync d'abord" and stop, unless I answer that I want to continue.
- On `develop`, `master` or `main`: stop and tell me to run `/ticket <KEY>`.

## Step 1 - Arguments
- A leading number is the step to implement. Without it, take the first unchecked step of the plan.
- Everything else is my directives for this step: a reference to follow ("comme dans <repository or pattern>"), an approach ("avec un Result", "derrière un feature flag", "sans nouvelle lib"), constraints on tests. Directives override the defaults of this command, but never the hard rules (security, secrets, no MediatR, never commit, never copy configuration values from another project).
- If a directive contradicts the conventions of this repository or an acceptance criterion, ask me before writing code, in the same question tool call as the questions of step 4: "Suivre ta directive" / "Suivre la convention du repo (<what it does>)", the recommended one first, with the reason in a few words.

## Step 2 - Ticket sheet
Use the ticket sheet printed in the workflow state (do not read it again): the step, the acceptance criteria it serves, the expected tests, and the "## Décisions" section (choices already made for this ticket: never ask them again).
- No sheet: ask me with the question tool: "Lancer /ticket <KEY> d'abord" (recommandé) / "Travailler sans fiche" (then I describe the task in a free answer, and steps 7 and 8 skip the sheet).
- Every step already checked: say "Toutes les étapes du plan sont faites : /test puis /check" and stop.

## Step 3 - Context
Read only what the step needs, and send these reads and skill loads together in one turn:
- The repository AGENTS.md is already in your instructions (do not read it again): use its "Build & test", "Reference examples", "Tests", "Architecture & conventions" and "Repository-specific rules" sections.
- Skills, only those this step needs: every `pattern-` skill named in the step or in my directives (a pattern skill the skill tool does not know was created after OpenCode opened this project: `sh ~/.config/opencode/scripts/pattern-skills.sh` gives its file, read it); `dotnet-cqrs-conventions` for a cqrs-api; `integrations-guardrails` if the step touches SharePoint/CSOM, DocuSign, S3, Piano Analytics or authentication; `best-practices` only when a decision of step 4 is about error handling (Result pattern), a feature flag or performance.
- A directive "comme dans <repository>" without a matching skill: read ONLY the files of that implementation in the other repository, read-only, then for each library or mechanism it uses that this repository does not, ask me "Garder l'existant (<current>)" (recommandé) / "Introduire <item> comme dans <source>", in the same question tool call as the questions of step 4.
- The existing code the step changes, and the closest existing example of what the step creates.
- A pattern skill is self-sufficient: never read the source repository it was extracted from (its "Sources" line is history, and reading another repository asks me for a permission). Something the skill does not say is a question for me, in step 4.
- A step that uses an in-house package (a pattern skill's "In-house API used", or a package of the company feed): also run `sh ~/.config/opencode/scripts/package-refs.sh` in this turn (in-house packages of this repository, versions, frameworks, XML documentation path). Write the skill's calls as they are; a compilation error on them is fixed from the compiler message, then from that XML documentation (grep tool on the member name), at most 2 rounds, then ask me with the question tool quoting the error ("Je colle la signature depuis Rider" first). Never look inside the package.

## Step 4 - Doubts: ask, do not guess
Before writing code, list for yourself the decisions this step needs. For each one that is not settled by my directives, the "Décisions" of the sheet, AGENTS.md or the existing code, and where two reasonable options have different impact, ask me: all these questions in ONE question tool call, one question per decision, 2 to 4 short options each, the recommended one first with its reason in a few words (a question that depends on another answer comes after). Typical cases:
- where the code goes (existing class or service vs a new one; which project or folder);
- error handling for expected failures when the repository has no result type (introduce a minimal Result vs keep exceptions);
- a feature flag for a user-visible or unfinished change (production deploys master as is);
- a new package, or an in-house package version (for a package of the "Licenses" list of your instructions, say in the option that the version is paid and propose its free option first);
- a change to a public contract: API route, request or response shape, public library method, database schema;
- two conventions coexisting in the repository (which one is the reference for new code);
- an acceptance criterion that can be read two ways.
Never ask what you can find in the code, the sheet or AGENTS.md. Then show the step's mini-plan in 3 to 6 lines (files to create or modify) and go on without waiting.

## Step 5 - Implement
A step written "(test d'abord)" fixes a bug: before changing the code, invoke the `test-writer` subagent with the prompt of step 7 ("Files changed in this step: none yet, the code to test is <files of the bug>"), adding: "This test must reproduce the bug, so it must FAIL on the current code: run it, report its failure message, do not make it pass and do not mark it as a suspected bug. In "Tests attendus", give its row the status `⏳ <TestName> (rouge avant correction)`." If it passes, it does not reproduce the bug: say so and ask me with the question tool "Ajuster le test" (recommandé) / "Corriger sans test rouge". Then fix the code.
Only this step. Smallest change that does it, mirroring the existing code and the reference examples. Code comments and log messages in English. No unrelated refactoring, renaming or reformatting.

## Step 6 - Build
Run the build command (AGENTS.md "Build & test", otherwise the detection above), quietly: `sh ~/.config/opencode/scripts/build-test.sh --build-only [<solution or project>]` for .NET (errors only, then "BUILD: OK" or "BUILD: FAILED"). Fix compilation errors with the rules of the skill `build-fix`, at most 3 rounds. A legacy .NET Framework project that cannot build on this machine (.NET Framework needs Windows): say so and continue.

## Step 7 - Tests of this step
Unless the step has no testable behavior (pure configuration, documentation) or my directives say otherwise, invoke the `test-writer` subagent with the task tool and this prompt (fill the placeholders):
"Write the unit tests for step <N> of ticket <KEY>: <step text>. Files changed in this step: <list>. Acceptance criteria concerned: <list>. Test project and closest existing test file, if known: <paths>. Directives about tests: <my directives about tests, or none>. Decisions already made (do not ask again): <the sheet's Décisions about tests>. Follow your rules (reference approach, existing style, questions before any new library or mechanism). Update the rows of these tests in the "Tests attendus" table of `.git/opencode-tickets/<KEY>.md`. Run only the tests of this step, in one call that rebuilds the test project quietly first: `sh ~/.config/opencode/scripts/build-test.sh <test project> --filter FullyQualifiedName~<TestClass>`, and report. The full suite runs later in /test and /check."
If a test it wrote fails because of a real bug in the code of this step, fix the production code (at most 2 rounds) and run the tests again.
For a step written "(test d'abord)", the reproducing test was written in step 5: do not invoke `test-writer` again, run that test class with the command above; it must now pass.

## Step 8 - Ticket sheet
If AGENTS.md says the CI checks formatting, first format the files changed in this step, code and tests, with its formatter (`dotnet format --include <files>`, `npx prettier --write <files>`, `npx eslint --fix <files>`).
Then record the step with ONE shell call, never with the edit tool (the script writes the exact lines and the date, whatever changed in the sheet since you read it): the tick and its "## Suivi" line, then one `decision` per answer I gave in step 1 or 4, chained with `&&`. Texts between double quotes, without `"`, `$` or backticks inside:
`sh ~/.config/opencode/scripts/ticket-sheet.sh tick <N> "/dev étape <N> - <files changed count> fichiers - build <ok|ko> - tests <passed>/<total>" && sh ~/.config/opencode/scripts/ticket-sheet.sh decision "<topic> : <choice> (étape <N>)"`
Its output prints the plan: step <N> must be checked there. If it says "NOT FOUND", the plan has no step <N>: say so in your answer.
For a step written "(test d'abord)" whose test now passes: with the edit tool, replace `⏳ <TestName> (rouge avant correction)` with `✅ <TestName>` in "Tests attendus".

## Step 9 - Answer, in French, then the next step
- First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, the branch name. Then the step: "Étape <N>/<total> : <step text>".
- Files created or modified (one line each), build result, tests added and result, decisions taken.
- Only after step 8, ask me with the question tool (the steps come from the plan printed by ticket-sheet.sh):
  - "Étape suivante : <text of the next unchecked step>" (recommandé) → go back to step 1 for that step, with the same directives unless they were specific to this step;
  - "Je reprends la main dans Rider" → remind me: on this machine, tell you « j'ai fait l'étape N à la main »; from my Mac, push from Rider then `/sync`;
  - "Passer à /check" → tell me to run `/test` if some expected tests are still missing, otherwise `/check`;
  - "Stop".
- When the last step is done: "Plan terminé : /test (vérification de la couverture des critères) puis /check."
