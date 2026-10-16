---
description: "Best-practice audit of the whole repository for its project type (health checks, error handling, configuration, resilience, logging, security defaults, tests...), with evidence and the smallest way to add what is missing (read-only). Usage: /audit [area, e.g. health checks, logging, tests]"
agent: architect
---
Focus given: "$ARGUMENTS"

Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Solution projects:
!`git ls-files '*.csproj'`

Audit this repository against the best practices of its project type. Read-only: never modify a file.

Steps:
1. Project type: the "Project type" section of AGENTS.md wins, otherwise the detection above. If several types apply, audit each part with its own section of the checklist.
2. Load the skill `best-practices`. If a focus is given above, audit only that area.
3. For each practice that applies to this project type, check it in the code with the "Detect" hint (read, grep and glob tools). Status: "en place" (with file:line), "partiel" (what is missing, with file:line) or "absent" (where you looked). Never mark a practice absent without having searched for it.
4. For each "partiel" or "absent" practice: the benefit in one sentence, the smallest change (files to create or modify), the packages it needs that the repository does not use yet (the developer decides), and `/apply-pattern <name>` if a skill whose name starts with `pattern-` covers it.

Answer, in French:
- First line: "Type de projet : <type>".
- Table: pratique, statut, preuve (file:line), priorité (haute / moyenne / basse: security and production failures first).
- "À faire en premier": the 3 to 5 most useful improvements, each with its smallest change and how to do it: `/apply-pattern <name>`, or "demande à l'agent build : « <phrase prête à coller> »". If the work is large, suggest creating a Jira ticket for it (write the summary and description ready to paste; do not create it).
