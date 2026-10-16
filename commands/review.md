---
description: "Review staged changes (or unstaged if nothing is staged) with the read-only reviewer agent"
agent: reviewer
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Staged changes:
!`git diff --staged`

Unstaged changes:
!`git diff`

Review the staged changes. If there are no staged changes, review the unstaged changes instead.
If both are empty, say "Nothing to review" and stop.
