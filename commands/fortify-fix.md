---
description: "Fix ONE Fortify SSC issue with a minimal change, then build and test. Usage: /fortify-fix <issueId>"
agent: build
---
SSC application (from appsec-ci.env): !`f=$(git ls-files '*appsec-ci.env' | head -1); if [ -n "$f" ]; then grep -E '^APPSEC_PROJECT_NAME=' "$f" | head -1 | cut -d= -f2- | tr -d '"\r'; fi`
Current git branch: !`git branch --show-current`

Fix the Fortify issue with id $1, and only this one.

Rules:
- Never read appsec-ci.env yourself. Use the application name injected above.
- Never invent application, version, filter set or filter names. Use the same version selection as the /fortify command (current branch version if it has scans, otherwise develop).

Steps:
1. Load the skill `fortify-remediation`.
2. Retrieve the details of issue $1 with the Fortify SSC MCP tools: category, file, line, source and sink of the data flow.
3. Read the code at that location and follow the data flow from source to sink.
4. Decide, and tell me before editing:
   - "Real issue": explain in two sentences how it could be exploited.
   - "Likely false positive": explain why (e.g. the value never comes from user input), propose the justification text for the SSC audit, and STOP without editing.
5. For a real issue: apply the remediation pattern from the skill matching the category, with the smallest possible change. Do not refactor around it. Do not suppress the warning with comments or attributes.
6. Add or update a unit test proving the fix (e.g. malicious input rejected or sanitized).
7. Run `dotnet build` then `dotnet test`.
8. Report: the category, the change (file:line), the test added, build/test result, and a commit message `fix(security): <summary> (Fortify #$1)`.

If the fix touches authentication, SharePoint/CSOM, DocuSign or S3 code, load `integrations-guardrails` and ask for confirmation before editing.
