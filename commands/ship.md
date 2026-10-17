---
description: "Ship the current work: review (skipped if /check already validated this exact state), commit, retrieve the branch's remote changes, push with my approval, then give the merge request link and description. The push starts the CI (Sonar + Fortify): follow with /scans. Usage: /ship"
agent: git
---
Remote base branches: !`git branch -r --list origin/develop origin/main origin/master`
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`
HEAD: !`git rev-parse --short HEAD`
Uncommitted changes summary: !`git diff HEAD --shortstat`
Untracked files: !`git ls-files --others --exclude-standard`
Staged changes summary: !`git diff --staged --stat`
Unstaged changes summary: !`git diff --stat`
Existing ticket sheets: !`ls .git/opencode/tickets`

Load the skill `ship-procedure` and follow it exactly, using the values above as its inputs.
