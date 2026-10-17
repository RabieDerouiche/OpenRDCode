---
description: "Fix ONE Fortify SSC issue with a minimal change, then build and test. Usage: /fortify-fix <issueId>"
agent: build
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

SSC application line (from appsec-ci.env): !`git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'`
Current git branch: !`git branch --show-current`
Now: !`date "+%Y-%m-%d %H:%M"`

Fix the Fortify issue with id $1, and only this one.

Rules:
- Never read appsec-ci.env yourself. Use the line injected above: the SSC application is the value after `=`, without quotes.
- Never invent application, version, filter set or filter names. Version selection: list ALL versions of the application; use the version matching the current branch (exact name, then `/` replaced by `-`, then by `_`) if it has at least one uploaded scan, otherwise `develop`; if `develop` does not exist either, ask me with the question tool (multiple choice, recommended option first) with the versions as options. Use the filter set "Security Auditor View".

Steps:
1. Load the skill `fortify-remediation`.
2. Retrieve the details of issue $1 with the Fortify SSC MCP tools: category, file, line, source and sink of the data flow.
3. Read the code at that location and follow the data flow from source to sink.
4. Give your diagnosis in two sentences ("Real issue": how it could be exploited; or "Likely false positive": why, e.g. the value never comes from user input), then ask me with the question tool (multiple choice, recommended option first):
   - "Corriger" (recommandé for a real issue)
   - "Faux positif : donne-moi la justification SSC" (recommandé for a likely false positive) → write the justification text and stop without editing.
   - "Passer cette issue" → stop without editing.
5. For a real issue: apply the remediation pattern from the skill matching the category, with the smallest possible change. Do not refactor around it. Do not suppress the warning with comments or attributes.
6. Add or update a unit test proving the fix (e.g. malicious input rejected or sanitized), if the project has tests.
7. Run the build and tests in one call. .NET: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" as first argument if it names one; front-end: the commands of AGENTS.md (default `npm test`). In the same turn, read the ticket sheet if the branch has one (step 9). If a legacy .NET Framework project cannot build on this machine (.NET Framework needs Windows), say so instead of changing project files.
8. Report: the category, the change (file:line), the test added, build/test result, and a commit message `fix(security): <summary> (Fortify #$1)`.
9. If the branch has a ticket sheet (`.git/opencode/tickets/<KEY>.md`, key from the branch name), append to its "## Suivi": `- <date> /fortify-fix $1 - <corrigé | faux positif | passé>` (date: the "Now" line above).
10. Last line: "Prochaine étape : /check puis /ship (avec ce message de commit), puis /scans pour vérifier que l'issue a disparu."

If the fix touches authentication, SharePoint/CSOM, DocuSign or S3 code, load `integrations-guardrails` and ask me with the question tool (multiple choice, recommended option first) ("Appliquer le correctif" / "Me montrer le diff d'abord" / "Annuler") before editing.
