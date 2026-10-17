---
description: "Pre-push check of the current work, local and read-only: review of the branch and of the uncommitted changes, licenses of the packages added, build and tests, acceptance criteria, security pre-scan. Sonar and Fortify run in the CI: see /scans after /ship. Usage: /check"
agent: reviewer
subtask: false
---
Base branch: the "Base branch" line of the workflow state (origin/develop, otherwise origin/main or origin/master). If it says NONE, ask me with the question tool for the base branch (free answer).

Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Workflow state (one fetch, then the state of the branch, its commits, its diffs and its package changes):
!`sh ~/.config/opencode/scripts/workflow-state.sh --diff --packages`

Check the current work before it is pushed. Everything here is local: Sonar and Fortify results only exist after the push, in the CI.

Speed: unless step 0 or step 1 stops, send these calls together in your FIRST turn: the build and tests of step 3, the read of the ticket sheet (step 4), the reads of the untracked source files (step 1), and the skills you will need: `fortify-remediation` and `best-practices`, plus `dotnet-cqrs-conventions` for a cqrs-api and `integrations-guardrails` if the diff touches SharePoint/CSOM, DocuSign, S3 or Piano Analytics. Then do steps 2 to 7 with all the results in hand.

## Step 0 - Changes pushed from another computer
If the branch status above says "behind" its remote copy, commits were pushed from another computer (for example from Rider on my Mac) and are not here yet. Stop and say: "<n> commit(s) poussé(s) depuis un autre poste ne sont pas ici : lance /sync d'abord". Continue only if I ask.

## Step 1 - Scope
The committed diff, the uncommitted diff and the untracked files of the workflow state (read the untracked source files with the read tool). If all three are empty, say "Rien à vérifier" and stop.

## Step 2 - Review
Review the whole scope as a merge request review, with your checks for the project type. Also check that the commits form a coherent change and flag files that seem unrelated to the branch goal.
Packages: the "=== Packages" block of the workflow state lists the NuGet packages added or changed on the branch. A package marked COMMERCIAL, MAINTENANCE FEE or AGPL is a blocking finding (fix: the free option the block gives), unless the sheet's "## Décisions" records that I accepted it.

## Step 3 - Build and tests
.NET: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" as first argument if it names one: quiet build, then the tests only if the build passed, in one call. Front-end: the commands of AGENTS.md "Build & test", otherwise those of the project detection. Do not fix anything. If a legacy .NET Framework project cannot build on this machine (.NET Framework needs Windows), say so and continue. If restore fails with 401/403/NU1301, say "Problème d'accès Artifactory" and continue without retrying.

## Step 4 - Acceptance criteria
The Jira key is in the branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`). Use the "Critères d'acceptation" and "Tests attendus" of `.git/opencode/tickets/<KEY>.md` if it is in the list above; otherwise read the criteria of the ticket with the Jira MCP tools (read-only) and say "Pas de fiche ticket". For each criterion: implemented (file:line as evidence, or "non trouvé") and tested (test name, or "non testé").

## Step 5 - Security pre-scan
On the changed lines only, look for what Fortify or Sonar will most likely report after the push, and name the category with the skill `fortify-remediation`:
- secrets, passwords, tokens or connection strings in code or configuration;
- user input reaching SQL, file paths, HTTP headers, redirects, HTML output or logs without validation or encoding;
- certificate validation disabled, weak hashing or encryption, non-cryptographic random used for security;
- personal or sensitive data written to logs;
- authorization removed or weakened (`[AllowAnonymous]`, wildcard CORS, disabled anti-forgery);
- resources not disposed (streams, HTTP responses, database readers).
This does not replace the CI scans: say so in one line.

## Step 6 - Suggestions (non-blocking)
With the skill `best-practices`, on the code areas touched by this branch only, propose AT MOST 5 improvements: a best practice of the checklist that applies to this project type and is missing (for example a readiness health check for the new dependency this branch adds, the result type for a new expected failure, a feature flag for an unfinished user-visible change, a performance issue), or a clearly better approach for code written on this branch. For each one: what, why in one sentence, the evidence (file:line, and where you checked it is not already in place), the smallest change, and `/apply-pattern <name>` if a `pattern-` skill covers it. Never put a suggestion in the verdict. If nothing is worth it, write "Aucune".
AGENTS.md drift (not counted in the 5): if the scope adds, removes or renames a project (`.csproj`, `.sln`, `.slnx`), changes `Directory.*.props`, test or logging packages, `Program.cs` / `Startup.cs` registration, the error handling convention or the folder organization, and the repository AGENTS.md does not reflect it, add one line: "AGENTS.md à mettre à jour (<sections>) : /agents-md une fois le ticket livré".

## Step 7 - Ticket sheet
If the sheet exists, append to its "## Suivi" section with the edit tool (date: the "Now" line of the workflow state):
`- <date> /check - HEAD <HEAD above> - <uncommitted changes summary above, or "aucun changement non commité"> - <untracked files count> fichiers non suivis - <verdict> - build <ok|ko> - tests <passed>/<total>`
Write nothing else.

## Answer, in French
First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name.
1. Your usual review output (project type, verdict, findings).
2. "Build et tests" : one line each.
3. "Packages" : one line per package added or changed, with its license verdict, or "Aucun changement".
4. "Critères d'acceptation" : table criterion / implemented / tested.
5. "Pré-scan sécurité" : findings with the probable Fortify or Sonar category, or "Rien de détecté".
6. "Suggestions (non bloquantes)" : the result of step 6.
7. One last line with the next step:
   - blocking findings or build/tests failing: "Corrige avec l'agent build (« corrige les points bloquants du /check »), puis relance /check."
   - criteria or changed code without tests: "/test"
   - otherwise: "Prêt : /ship"
