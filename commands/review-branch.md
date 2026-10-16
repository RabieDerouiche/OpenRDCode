---
description: "Review the whole current branch against develop with the read-only reviewer agent (before opening a MR)"
agent: reviewer
---
Remote base branches: !`git branch -r --list origin/develop origin/main origin/master`

Base branch: `origin/develop` if it is listed above. Otherwise, if exactly one of `origin/main` / `origin/master` is listed, use it; if none or several, ask me with the question tool (multiple choice, recommended option first) with the listed branches as options. If the git output injected below failed because `origin/develop` does not exist, run the same git commands yourself with the chosen base, one command per call.

Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Current branch: !`git branch --show-current`

Fetch develop: !`git fetch -q origin develop`

Commits since develop:
!`git log --oneline origin/develop..HEAD`

Full diff against develop:
!`git diff origin/develop...HEAD`

Review the full diff above as a merge request review.
Additionally check that the commits form a coherent change and flag files that seem unrelated to the branch goal.
