---
description: "Pre-push check of the current work, local and read-only: review of the branch and of the uncommitted changes, build and tests, acceptance criteria, security pre-scan. Sonar and Fortify run in the CI: see /scans after /ship. Usage: /check"
agent: reviewer
---
Remote base branches: !`git branch -r --list origin/develop origin/main origin/master`

Base branch: `origin/develop` if it is listed above. Otherwise, if exactly one of `origin/main` / `origin/master` is listed, use it; if none or several, ask me with the question tool (multiple choice, recommended option first) with the listed branches as options. If the git output injected below failed because `origin/develop` does not exist, run the same git commands yourself with the chosen base, one command per call.

Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Current branch: !`git branch --show-current`
Existing ticket sheets: !`ls .git/opencode/tickets`
HEAD: !`git rev-parse --short HEAD`
Uncommitted changes summary: !`git diff HEAD --shortstat`
Untracked files: !`git ls-files --others --exclude-standard`

Fetch develop: !`git fetch -q origin develop`

Commits since develop:
!`git log --oneline origin/develop..HEAD`

Committed diff against develop:
!`git diff origin/develop...HEAD`

Uncommitted diff (staged and unstaged):
!`git diff HEAD`

Check the current work before it is pushed. Everything here is local: Sonar and Fortify results only exist after the push, in the CI.

## Step 1 - Scope
The committed diff, the uncommitted diff and the untracked files above (read the untracked source files with the read tool). If all three are empty, say "Rien à vérifier" and stop.

## Step 2 - Review
Review the whole scope as a merge request review, with your checks for the project type. Also check that the commits form a coherent change and flag files that seem unrelated to the branch goal.

## Step 3 - Build and tests
Run the build command, then the test command (AGENTS.md "Build & test" if present, otherwise the project detection above). Do not fix anything. If a legacy .NET Framework project cannot build on macOS, say so and continue. If restore fails with 401/403/NU1301, say "Problème d'accès Artifactory" and continue without retrying.

## Step 4 - Acceptance criteria
The Jira key is in the branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`). Use the "Critères d'acceptation" and "Tests attendus" of `.git/opencode/tickets/<KEY>.md` if it is in the list above; otherwise read the criteria of the ticket with the Jira MCP tools (read-only) and say "Pas de fiche ticket". For each criterion: implemented (file:line as evidence, or "non trouvé") and tested (test name, or "non testé").

## Step 5 - Security pre-scan
On the changed lines only, look for what Fortify or Sonar will most likely report after the push. Load the skill `fortify-remediation` to name the category:
- secrets, passwords, tokens or connection strings in code or configuration;
- user input reaching SQL, file paths, HTTP headers, redirects, HTML output or logs without validation or encoding;
- certificate validation disabled, weak hashing or encryption, non-cryptographic random used for security;
- personal or sensitive data written to logs;
- authorization removed or weakened (`[AllowAnonymous]`, wildcard CORS, disabled anti-forgery);
- resources not disposed (streams, HTTP responses, database readers).
This does not replace the CI scans: say so in one line.

## Step 6 - Suggestions (non-blocking)
Load the skill `best-practices`. On the code areas touched by this branch only, propose AT MOST 3 improvements: a best practice of the checklist that applies to this project type and is missing (for example a readiness health check for the new dependency this branch adds), or a clearly better approach for code written on this branch. For each one: what, why in one sentence, the evidence (file:line, and where you checked it is not already in place), the smallest change, and `/apply-pattern <name>` if a `pattern-` skill covers it. Never put a suggestion in the verdict. If nothing is worth it, write "Aucune".

## Step 7 - Ticket sheet
If the sheet exists, append to its "## Suivi" section with the edit tool (date with `date "+%Y-%m-%d %H:%M"`):
`- <date> /check - HEAD <HEAD above> - <uncommitted changes summary above, or "aucun changement non commité"> - <untracked files count> fichiers non suivis - <verdict> - build <ok|ko> - tests <passed>/<total>`
Write nothing else.

## Answer, in French
1. Your usual review output (project type, verdict, findings).
2. "Build et tests" : one line each.
3. "Critères d'acceptation" : table criterion / implemented / tested.
4. "Pré-scan sécurité" : findings with the probable Fortify or Sonar category, or "Rien de détecté".
5. "Suggestions (non bloquantes)" : the result of step 6.
6. One last line with the next step:
   - blocking findings or build/tests failing: "Corrige avec l'agent build (« corrige les points bloquants du /check »), puis relance /check."
   - criteria or changed code without tests: "/test"
   - otherwise: "Prêt : /ship"
