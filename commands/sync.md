---
description: "Bring the current branch up to date: commit local work locally (no push), retrieve the branch's own remote changes, merge develop, then offer to push. Merge only. Stops on conflicts and asks. Usage: /sync"
agent: git
---
Workflow state (one fetch, then the state of the branch):
[[run workflow-state.sh]]

Load the skill `sync-procedure` and follow it exactly, using the values above as its inputs.
