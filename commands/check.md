---
description: "Pre-push check of the current work, local and read-only: review of the branch and of the uncommitted changes, build and tests, acceptance criteria, security pre-scan, and on request the licenses of the packages the branch changes. Sonar and Fortify run in the CI: see /scans after /ship. Usage: /check"
agent: reviewer
subtask: false
---
Base branch: the "Base branch" line of the workflow state (origin/develop, otherwise origin/main or origin/master). If it says NONE, ask me with the question tool for the base branch (free answer).

Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Workflow state (one fetch, then the state of the branch, its ticket sheet, its commits and its diffs):
!`sh ~/.config/opencode/scripts/workflow-state.sh --sheet --diff`

Check the current work before it is pushed. Everything here is local: Sonar and Fortify results only exist after the push, in the CI. The ticket sheet is printed above: do not read it again.

Speed: unless step 0 or step 1 stops, send these calls together in your FIRST turn: the build and tests of step 3 (unless step 3 reuses an earlier run), the reads of the untracked source files (step 1), the skills you will need (`fortify-remediation` and `best-practices`, plus `dotnet-cqrs-conventions` for a cqrs-api and `integrations-guardrails` if the diff touches SharePoint/CSOM, DocuSign, S3 or Piano Analytics), and the license question of step 2 when it applies. Then do steps 2 to 7 with all the results in hand.

## Step 0 - Changes pushed from another computer
If the "Branch vs its remote copy" line says "behind", commits were pushed from another computer (for example from Rider on my Mac) and are not here yet. Stop and say: "<n> commit(s) poussé(s) depuis un autre poste ne sont pas ici : lance /sync d'abord". Continue only if I ask.

## Step 1 - Scope
The committed diff, the uncommitted diff and the untracked files of the workflow state (read the untracked source files with the read tool). If all three are empty, say "Rien à vérifier" and stop.

## Step 2 - Review
Review the whole scope as a merge request review, with your checks for the project type. Also check that the commits form a coherent change and flag files that seem unrelated to the branch goal.
Licenses, optional: only if the scope changes a project file (`.csproj`, `.fsproj`, `.vbproj`, `.props`, `.targets`, `packages.config`), ask me with the question tool, in the first turn: "Vérifier les licences des packages modifiés ?" with "Oui" (recommandé) / "Non". If I answer "Oui", run `sh ~/.config/opencode/scripts/package-licenses.sh --diff` in the same turn as step 7. Its verdicts do not change the review verdict: they go in the "Licences" line of the answer.

## Step 3 - Build and tests
Reuse first: if a line of the sheet's "## Suivi" printed above ends with `empreinte <value>` where the value is the "Code fingerprint" of the workflow state, with `build ok` and every test passed (`tests <n>/<n>`), this exact code was already built and tested: do not run them again, and write "déjà OK sur ce code exact (<command of that line> du <its date>)" in the answer.
Otherwise, .NET: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" as first argument if it names one: quiet build, then the tests only if the build passed, in one call. Front-end: the commands of AGENTS.md "Build & test", otherwise those of the project detection. Do not fix anything. If a legacy .NET Framework project cannot build on this machine (.NET Framework needs Windows), say so and continue. If restore fails with 401/403/NU1301, say "Problème d'accès Artifactory" and continue without retrying.

## Step 4 - Acceptance criteria
Use the "Critères d'acceptation" and "Tests attendus" of the ticket sheet printed above; without a sheet, read the criteria of the ticket with the Jira MCP tools (read-only, Jira key from the branch name) and say "Pas de fiche ticket". For each criterion: implemented (file:line as evidence, or "non trouvé") and tested (test name, or "non testé").

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
If the sheet exists, append at the end of its "## Suivi" section, which ends the file, with the edit tool (after its last line, as printed above; date: the "Now" line of the workflow state):
`- <date> /check - <verdict> - build <ok|ko> - tests <passed>/<total> - empreinte <Code fingerprint of the workflow state>`
Write nothing else. /ship skips its review and /next proposes to ship only while the code keeps this fingerprint.

## Answer, in French
First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name.
1. Your usual review output (project type, verdict, findings).
2. "Build et tests" : one line each.
3. "Critères d'acceptation" : table criterion / implemented / tested.
4. "Pré-scan sécurité" : findings with the probable Fortify or Sonar category, or "Rien de détecté".
5. "Suggestions (non bloquantes)" : the result of step 6.
6. Only if the license check ran: "Licences" : one line per package added or changed, with its verdict and, for a paid one, its free option.
7. One last line with the next step:
   - blocking findings or build/tests failing: "Corrige avec l'agent build (« corrige les points bloquants du /check »), puis relance /check."
   - criteria or changed code without tests: "/test"
   - otherwise: "Prêt : /ship"
