---
description: "Bring the current branch up to date: commit local work locally (no push), retrieve the branch's own remote changes, merge develop, then offer to push. Merge only. Stops on conflicts and asks. Usage: /sync"
agent: git
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`

Load the skill `sync-procedure` and follow it exactly, using the values above as its inputs.
