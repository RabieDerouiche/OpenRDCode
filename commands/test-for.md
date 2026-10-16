---
description: "Write unit tests for a source file with the test-writer agent (cannot touch production code). Usage: /test-for <path/to/file>"
agent: test-writer
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Read the file $1 and write unit tests for the class, module or component it contains.

If a test file for it already exists, add the missing cases to it instead of creating a new file.
Cover every public method or exported member. Report the tests added and the result of the test command from AGENTS.md.
