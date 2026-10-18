---
description: "Ship the current work: review (skipped if /check already validated this exact state), commit, retrieve the branch's remote changes, push with my approval, then give the merge request link and description. The push starts the CI (Sonar + Fortify): follow with /scans. Usage: /ship"
agent: git
---
Workflow state (one fetch, then the state of the branch and its ticket sheet):
[[run workflow-state.sh --sheet]]

Load the skill `ship-procedure` and follow it exactly, using the values above as its inputs.
