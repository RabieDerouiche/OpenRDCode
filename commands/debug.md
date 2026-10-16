---
description: "Investigate a bug, a failing test, a stack trace or a log excerpt with the read-only debugger agent. Usage: /debug <description, test name or pasted stack trace>"
agent: debugger
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Find the root cause of the following problem:

$ARGUMENTS

Recent commits on this branch:
!`git log --oneline -15`

Do not modify any file. Give the root cause with evidence, a proposed fix and a regression test.
