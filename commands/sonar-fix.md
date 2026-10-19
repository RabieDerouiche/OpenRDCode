---
description: "Fix ONE SonarQube issue or security hotspot with a minimal change, then build and test. Usage: /sonar-fix <issue key or hotspot key>"
agent: build
---
Project detection:
[[run detect-project-type.sh]]

Workflow state (no fetch: the branch, the code fingerprint and the ticket sheet):
[[run workflow-state.sh --no-fetch --sheet]]

Fix the SonarQube issue or security hotspot with key $1, and only this one.

Rules:
- Read-only on SonarQube and every other system: never change an issue status, never mark it as false positive or won't fix, never comment. Only the code changes.
- Never invent project keys, rule keys or issue keys. Look them up with the SonarQube MCP tools.
- Smallest possible change. No refactoring around it, no reformatting of unrelated lines.
- Never suppress the finding with `// NOSONAR`, `#pragma warning disable`, `[SuppressMessage]` or an exclusion in the Sonar configuration.

Speed: get the issue first; then, in one turn, the description of its rule and the code at its location.

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
   - Known traps of the obvious fix: a property whose getter builds a collection (LINQ, `ToList()`) becomes a method (`GetActiveItems()`), never a property with a cache field (stale data); a URL path segment is encoded with `Uri.EscapeDataString` (or becomes a typed `Guid` parameter), not `HttpUtility.UrlEncode` (meant for query strings: spaces become `+`).
6. If the fix changes behavior (bug or vulnerability), add or update a unit test proving it, if the project has tests. Code smells need no new test.
7. Run the build and tests in one call. .NET: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" as first argument if it names one; front-end: the commands of AGENTS.md "Build & test", otherwise those of the project detection. If a legacy .NET Framework project cannot build on this machine (.NET Framework needs Windows), say so instead of changing project files.
8. Report: rule key and title, the change (file:line), the test added if any, build/test result, and a commit message:
   - bug or vulnerability: `fix(sonar): <summary> (<rule key>)`
   - security hotspot: `fix(security): <summary> (<rule key>)`
   - code smell: `refactor(sonar): <summary> (<rule key>)`
9. If the workflow state printed a ticket sheet, append at the end of its "## Suivi" section (`.git/opencode-tickets/<KEY>.md`, exact lines from the sheet printed above): `- <date> /sonar-fix $1 - <corrigé | non pertinent | passé>` (date: the "Now" line of the workflow state), followed for a fix by `- build <ok|ko> - tests <passed>/<total> - empreinte <the "Code fingerprint of this run" line of step 7, or ->`: /check then reuses that build and test run while the code does not change.
10. Then one line "Ensuite : /check, /ship (avec ce message de commit), puis /scans pour vérifier que l'issue a disparu.", and the next step with the question tool (header "Suite"): "/check (recommandé)" and "Rien pour l'instant"; the pack plugin starts the command I choose by itself as soon as your turn ends: then answer only « Je lance <command>. ».
