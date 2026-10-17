---
description: "Fix ONE SonarQube issue or security hotspot with a minimal change, then build and test. Usage: /sonar-fix <issue key or hotspot key>"
agent: build
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Current git branch: !`git branch --show-current`
Now: !`date "+%Y-%m-%d %H:%M"`

Fix the SonarQube issue or security hotspot with key $1, and only this one.

Rules:
- Read-only on SonarQube and every other system: never change an issue status, never mark it as false positive or won't fix, never comment. Only the code changes.
- Never invent project keys, rule keys or issue keys. Look them up with the SonarQube MCP tools.
- Smallest possible change. No refactoring around it, no reformatting of unrelated lines.
- Never suppress the finding with `// NOSONAR`, `#pragma warning disable`, `[SuppressMessage]` or an exclusion in the Sonar configuration.

Steps:
1. Retrieve issue or hotspot $1 with the SonarQube MCP tools: type (bug, vulnerability, code smell, security hotspot), severity, rule key, message, file, line.
2. Retrieve the description of the rule to understand what it expects.
3. Read the code at that location.
4. Give your diagnosis in two sentences ("To fix": what is wrong and the risk; "Likely not relevant": why, e.g. generated code, value never user-controlled; for a security hotspot: "Safe" or "To fix" with the reason), then ask me with the question tool (multiple choice, recommended option first):
   - "Corriger" (recommandé when the finding is relevant)
   - "Non pertinent : donne-moi la justification Sonar" (recommandé when it is not) → write the justification text and stop without editing.
   - "Passer cette issue" → stop without editing.
5. For a fix:
   - If the rule is a security one (vulnerability or hotspot), load the skill `fortify-remediation` and apply the matching pattern.
   - If the code touches SharePoint/CSOM, DocuSign, AWS S3, Piano Analytics or authentication, load `integrations-guardrails` and ask me with the question tool (multiple choice, recommended option first) ("Appliquer le correctif" / "Me montrer le diff d'abord" / "Annuler") before editing.
   - For a code smell, change only what the rule asks (e.g. remove the unused variable, reduce the nesting of this method), keeping the behavior identical.
6. If the fix changes behavior (bug or vulnerability), add or update a unit test proving it, if the project has tests. Code smells need no new test.
7. Run the build and tests in one call. .NET: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" as first argument if it names one; front-end: the commands of AGENTS.md "Build & test", otherwise those of the project detection. In the same turn, read the ticket sheet if the branch has one (step 9). If a legacy .NET Framework project cannot build on this machine (.NET Framework needs Windows), say so instead of changing project files.
8. Report: rule key and title, the change (file:line), the test added if any, build/test result, and a commit message:
   - bug or vulnerability: `fix(sonar): <summary> (<rule key>)`
   - security hotspot: `fix(security): <summary> (<rule key>)`
   - code smell: `refactor(sonar): <summary> (<rule key>)`
9. If the branch has a ticket sheet (`.git/opencode/tickets/<KEY>.md`, key from the branch name), append to its "## Suivi": `- <date> /sonar-fix $1 - <corrigé | non pertinent | passé>` (date: the "Now" line above).
10. Last line: "Prochaine étape : /check puis /ship (avec ce message de commit), puis /scans pour vérifier que l'issue a disparu."
