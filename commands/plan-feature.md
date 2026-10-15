---
description: "Get an implementation plan for a feature or refactoring from the read-only architect agent. Usage: /plan-feature <description of the feature>"
agent: architect
---
Design an implementation plan for the following request:

$ARGUMENTS

Solution projects and their references:
!`for p in $(git ls-files '*.csproj'); do echo "== $p"; grep -oE 'ProjectReference Include="[^"]+"' "$p" | sed 's/ProjectReference Include=//'; done`

Follow your planning method. Each step must leave the solution in a building state and name the test that verifies it.
Finish with the list of open questions, if any.
