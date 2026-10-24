---
name: pack-audit
description: "Procédure de /outil audit : audit des bonnes pratiques de tout le dépôt selon son type (health checks, gestion d'erreurs, configuration, résilience, logs, sécurité, tests, Result pattern, feature flags, performance), avec preuves et la plus petite façon d'ajouter ce qui manque. Lecture seule."
compatibility: opencode
---
# /outil audit

Started directly as the command `/pack-audit` (this procedure is the message that started you, with no line « Skill : pack-audit » printed before it): answer only « Lance `/outil audit` : cette procédure a besoin de ce que /outil prépare. » and stop.

Audit this repository against the best practices of its project type. Read-only: never modify a file. The arguments, when there are some, are the area to audit (« health checks », « logging », « tests »…); the project detection and the packages are printed above.

Steps:
1. Project type: the "Project type" section of AGENTS.md wins, otherwise the detection above. If several types apply, audit each part with its own section of the checklist.
2. Load the skill `best-practices`. With an area in the arguments, audit only that area.
3. For each practice that applies to this project type, check it in the code with its "Detect" hint (read, grep and glob tools; the searches of several practices together in one turn). Status: « en place » (file:line), « partiel » (what is missing, file:line) or « absent » (where you looked). Never mark a practice absent without having searched for it.
4. For each « partiel » or « absent » practice: the benefit in one sentence, the smallest change (files to create or modify), the packages it needs that the repository does not use yet (the developer decides), and « comme le pattern <name> » when a skill whose name starts with `pattern-` covers it (/go applies it).

Answer, in French:
- First line: « Type de projet : <type> ».
- Table: pratique, statut, preuve (file:line), priorité (haute / moyenne / basse: security and production failures first).
- « À faire en premier » : up to 10 improvements, most useful first, each with its smallest change and how to do it: a Jira ticket to create, written ready to paste (summary and description; never create it), that `/go <KEY>` will then implement, with « comme le pattern <name> » when a pattern skill of this machine does it.
- Last, when « À faire en premier » lists something, the « Suite » question (question tool, header « Suite »): its first 3 improvements, each with the label « /go sans ticket : <the improvement, in one sentence of my words>[ comme le pattern <name>] » and the description « <its smallest change> : analyse, filet de non-régression, code et tests, jusqu'à une MR en Draft, sans ticket Jira », the first one marked « (recommandé) », then « Rien pour l'instant » (« je crée d'abord les tickets Jira, puis /go <KEY> »). The pack starts the command I choose as soon as your turn ends: answer only « Je lance <the command>. ».
