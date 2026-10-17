---
description: "Implement the next step of the ticket sheet (or step N) following my directives, write the unit tests of that step, build and run them, tick the step, then offer the next one. Asks multiple-choice questions whenever the approach is unclear. Usage: /dev [N] [directives, e.g. « comme dans ~/dev/dna-api », « avec un Result », « sans nouvelle lib », « tests avec fixtures xUnit »]"
agent: build
---
Arguments: "$ARGUMENTS"
Workflow state (one fetch, then the state of the branch and of the ticket sheet):
!`sh ~/.config/opencode/scripts/workflow-state.sh`
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Implement ONE step of the ticket plan, with its tests. Never commit or push: that is /ship.

## Step 0 - Before starting
- If the branch status above says "behind" its remote copy, commits were pushed from another computer (for example from Rider on my Mac): say "Lance /sync d'abord" and stop, unless I answer that I want to continue.
- On `develop`, `master` or `main`: stop and tell me to run `/ticket <KEY>`.

## Step 1 - Arguments
- A leading number is the step to implement. Without it, take the first unchecked step of the plan.
- Everything else is my directives for this step: a reference to follow ("comme dans <repository or pattern>"), an approach ("avec un Result", "derrière un feature flag", "sans nouvelle lib"), constraints on tests. Directives override the defaults of this command, but never the hard rules (security, secrets, no MediatR, never commit, never copy configuration values from another project).
- If a directive contradicts the conventions of this repository or an acceptance criterion, ask me with the question tool before writing code: "Suivre ta directive" / "Suivre la convention du repo (<what it does>)" / the recommended one first, with the reason in a few words.

## Step 2 - Ticket sheet
The Jira key is in the branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`). Read `.git/opencode/tickets/<KEY>.md` if it is in the list above: the step, the acceptance criteria it serves, the expected tests, and the "## Décisions" section (choices already made for this ticket: never ask them again).
- No sheet: ask me with the question tool: "Lancer /ticket <KEY> d'abord" (recommandé) / "Travailler sans fiche" (then I describe the task in a free answer, and steps 7 and 8 skip the sheet).
- Every step already checked: say "Toutes les étapes du plan sont faites : /test puis /check" and stop.

## Step 3 - Context
Read only what the step needs:
- The repository AGENTS.md: "Build & test", "Reference examples", "Tests", "Architecture & conventions", "Repository-specific rules".
- Skills, only those this step needs: every `pattern-` skill named in the step or in my directives; `dotnet-cqrs-conventions` for a cqrs-api; `integrations-guardrails` if the step touches SharePoint/CSOM, DocuSign, S3, Piano Analytics or authentication; `best-practices` only when a decision of step 4 is about error handling (Result pattern), a feature flag or performance.
- A directive "comme dans <repository>" without a matching skill: read ONLY the files of that implementation in the other repository, read-only, then for each library or mechanism it uses that this repository does not, ask me "Garder l'existant (<current>)" (recommandé) / "Introduire <item> comme dans <source>".
- The existing code the step changes, and the closest existing example of what the step creates.

## Step 4 - Doubts: ask, do not guess
Before writing code, list for yourself the decisions this step needs. For each one that is not settled by my directives, the "Décisions" of the sheet, AGENTS.md or the existing code, and where two reasonable options have different impact, ask me with the question tool, one question at a time, 2 to 4 short options, the recommended one first with its reason in a few words. Typical cases:
- where the code goes (existing class or service vs a new one; which project or folder);
- error handling for expected failures when the repository has no result type (introduce a minimal Result vs keep exceptions);
- a feature flag for a user-visible or unfinished change (production deploys master as is);
- a new package, or an in-house package version;
- a change to a public contract: API route, request or response shape, public library method, database schema;
- two conventions coexisting in the repository (which one is the reference for new code);
- an acceptance criterion that can be read two ways.
Never ask what you can find in the code, the sheet or AGENTS.md. Then show the step's mini-plan in 3 to 6 lines (files to create or modify) and go on without waiting.

## Step 5 - Implement
Only this step. Smallest change that does it, mirroring the existing code and the reference examples. Code comments and log messages in English. No unrelated refactoring, renaming or reformatting.

## Step 6 - Build
Run the build command (AGENTS.md "Build & test", otherwise the detection above), quietly: `dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60` for .NET. Fix compilation errors with the rules of the skill `build-fix`, at most 3 rounds. A legacy .NET Framework project that cannot build on this machine (.NET Framework needs Windows): say so and continue.

## Step 7 - Tests of this step
Unless the step has no testable behavior (pure configuration, documentation) or my directives say otherwise, invoke the `test-writer` subagent with the task tool and this prompt (fill the placeholders):
"Write the unit tests for step <N> of ticket <KEY>: <step text>. Files changed in this step: <list>. Acceptance criteria concerned: <list>. Directives about tests: <my directives about tests, or none>. Decisions already made (do not ask again): <the sheet's Décisions about tests>. Follow your rules (reference approach, existing style, questions before any new library or mechanism). Update the rows of these tests in the "Tests attendus" table of `.git/opencode/tickets/<KEY>.md`. Run only the tests of this step on the test project, which rebuilds incrementally: `dotnet test <test project> -nologo --filter FullyQualifiedName~<TestClass> 2>&1 | tail -60`, and report. The full suite runs later in /test and /check."
If a test it wrote fails because of a real bug in the code of this step, fix the production code (at most 2 rounds) and run the tests again.

## Step 8 - Ticket sheet
With the edit tool, in `.git/opencode/tickets/<KEY>.md`:
- tick the step (`- [x]`);
- add each answer I gave in step 1 or 4 to a "## Décisions" section (create it before "## Suivi" if missing): `- <topic> : <choice> (étape <N>)`;
- append to "## Suivi": `- <date> /dev étape <N> - <files changed count> fichiers - build <ok|ko> - tests <passed>/<total>` (date with `date "+%Y-%m-%d %H:%M"`).

## Step 9 - Answer, in French, then the next step
- First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name. Then the step: "Étape <N>/<total> : <step text>".
- Files created or modified (one line each), build result, tests added and result, decisions taken.
- Ask me with the question tool:
  - "Étape suivante : <text of the next unchecked step>" (recommandé) → go back to step 1 for that step, with the same directives unless they were specific to this step;
  - "Je reprends la main dans Rider" → remind me: on this machine, tell you « j'ai fait l'étape N à la main »; from my Mac, push from Rider then `/sync`;
  - "Passer à /check" → tell me to run `/test` if some expected tests are still missing, otherwise `/check`;
  - "Stop".
- When the last step is done: "Plan terminé : /test (vérification de la couverture des critères) puis /check."
