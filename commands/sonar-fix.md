---
description: "Fix ONE SonarQube issue or security hotspot with a minimal change, then build and test. Usage: /sonar-fix <issue key or hotspot key>"
agent: build
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Current git branch: !`git branch --show-current`

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
4. Decide, and tell me before editing:
   - "To fix": explain in two sentences what is wrong and the risk.
   - "Likely not relevant": explain why (e.g. the code is generated, the value is never user-controlled, the rule does not fit this context), propose the justification text I can put in SonarQube, and STOP without editing.
   - For a security hotspot: say whether the code is "Safe" or "To fix", with the reason. If it is safe, propose the justification text and STOP.
5. For a fix:
   - If the rule is a security one (vulnerability or hotspot), load the skill `fortify-remediation` and apply the matching pattern.
   - If the code touches SharePoint/CSOM, DocuSign, AWS S3, Piano Analytics or authentication, load `integrations-guardrails` and ask for confirmation before editing.
   - For a code smell, change only what the rule asks (e.g. remove the unused variable, reduce the nesting of this method), keeping the behavior identical.
6. If the fix changes behavior (bug or vulnerability), add or update a unit test proving it, if the project has tests. Code smells need no new test.
7. Run the build and test commands (AGENTS.md "Build & test" if present, otherwise the project detection above). If a legacy .NET Framework project cannot build on macOS, say so instead of changing project files.
8. Report: rule key and title, the change (file:line), the test added if any, build/test result, and a commit message:
   - bug or vulnerability: `fix(sonar): <summary> (<rule key>)`
   - security hotspot: `fix(security): <summary> (<rule key>)`
   - code smell: `refactor(sonar): <summary> (<rule key>)`
