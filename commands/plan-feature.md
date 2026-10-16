---
description: "Get an implementation plan for a feature or refactoring from the read-only architect agent. Usage: /plan-feature <description of the feature>"
agent: architect
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Design an implementation plan for the following request:

$ARGUMENTS

Solution projects:
!`git ls-files '*.csproj'`

Read these .csproj files with the read tool to get the project references before planning.

Follow your planning method. Each step must leave the solution in a building state and name the test that verifies it.
Finish with the list of open questions, if any.
