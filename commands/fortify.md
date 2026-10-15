---
description: "List and triage Fortify SSC issues for the current branch, falling back to develop (read-only). Usage: /fortify [ssc-application:version]"
agent: fortify
---
SSC application line (from appsec-ci.env): !`git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'`
Current git branch: !`git branch --show-current`

Explicit target: "$ARGUMENTS"

Rules:
- Never read appsec-ci.env yourself: it may contain secrets. Use only the line injected above: the SSC application is the value after `=`, without quotes.

Steps:
1. If an explicit target is given above, use it as is and go to step 4.
2. If the SSC application above is empty, say "APPSEC_PROJECT_NAME not found in appsec-ci.env" and stop. Do not search for the application.
3. List ALL versions of that SSC application. Do not guess version names. Then select the version:
   a. Look for a version matching the current branch, in this order:
      the exact branch name, then the branch name with `/` replaced by `-`, then with `/` replaced by `_`.
   b. If a matching version exists AND it has at least one uploaded scan (artifact), use it.
   c. Otherwise use the `develop` version.
   d. If the current branch is empty (detached HEAD), use `develop`.
   e. If `develop` does not exist either, list the available versions and stop.
4. List and triage the issues of the selected application version.
5. Start your answer with one line:
   "Version used: <application:version> — reason: <explicit target | current branch has scans | fallback to develop: no version for branch | fallback to develop: branch version has no scan>".
