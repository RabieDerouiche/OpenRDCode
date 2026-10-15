---
description: "Write a Conventional Commits message from the staged changes"
agent: plan
---
Staged files:
!`git diff --staged --stat`

Staged changes:
!`git diff --staged`

Write ONE commit message following Conventional Commits (feat, fix, refactor, test, chore, docs, perf, ci, build).
Format:
- First line: type(scope): summary, max 72 characters, imperative mood, in English. The scope is the feature or project name.
- Blank line
- Bullet list of the main changes (max 5 bullets), in English.
- If the changes include a breaking change for API consumers, add a `BREAKING CHANGE:` footer.

If nothing is staged, say "Nothing staged" and stop.
Output only the commit message in a code block. Do not run any command.
