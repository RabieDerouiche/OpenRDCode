---
description: "Review the whole current branch against develop with the read-only reviewer agent (before opening a MR)"
agent: reviewer
---
Current branch: !`git branch --show-current`

Commits since develop:
!`git fetch -q origin develop >/dev/null 2>&1; git log --oneline origin/develop..HEAD`

Full diff against develop:
!`git diff origin/develop...HEAD`

Review the full diff above as a merge request review.
Additionally check that the commits form a coherent change and flag files that seem unrelated to the branch goal.
