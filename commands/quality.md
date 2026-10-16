---
description: "Merge SonarQube and Fortify findings for the current branch into one prioritized, deduplicated list (read-only)"
agent: analyst
---
Remote base branches: !`git branch -r --list origin/develop origin/main origin/master`

Base branch: `origin/develop` if it is listed above. Otherwise, if exactly one of `origin/main` / `origin/master` is listed, use it; if none or several, ask me with the question tool (multiple choice, recommended option first) with the listed branches as options. If the git output injected below failed because `origin/develop` does not exist, run the same git commands yourself with the chosen base, one command per call.

SSC application line (from appsec-ci.env): !`git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'`
Current git branch: !`git branch --show-current`
Files changed on this branch: !`git diff --name-only origin/develop...HEAD`

Build one prioritized list of quality and security findings for this branch.

Steps:
1. Fortify: the SSC application is the value after `=` in the line above, without quotes. List its versions, use the version matching the current branch (exact name, then `/` replaced by `-`, then by `_`) if it has at least one scan, otherwise `develop`. Use the filter set "Security Auditor View". Never invent names.
2. SonarQube: find the Sonar project for this repository (search by repository name or by the SSC application name). Get the open issues and security hotspots for the current branch or its merge request; if the branch is not analyzed, use the main branch and say so.
3. Merge: if Fortify and Sonar report the same problem at the same file and line (or within 3 lines), keep one entry and mention both sources.
4. Prioritize: security first (Fortify Critical/High, Sonar vulnerabilities and hotspots), then bugs, then code smells. Inside each group, findings in files changed on this branch come first.

Output, in French:
- First line: "Fortify: <application:version> — Sonar: <project> / <branch>".
- Table: priority, source (Fortify/Sonar/both), Fortify issue id or Sonar issue key, rule or category, file:line, changed on this branch (oui/non).
- Counts per source and severity.
- The 5 findings to fix first, with the command to use: `/fortify-fix <id>` for Fortify, `/sonar-fix <issue key>` for Sonar. For a finding reported by both, use `/fortify-fix`.

Rules: read-only. Never mark issues as false positive or change any status.
