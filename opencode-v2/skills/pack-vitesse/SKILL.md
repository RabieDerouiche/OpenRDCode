---
name: pack-vitesse
description: "Procédure de /outil vitesse : le tableau du temps des derniers runs (modèle, sous-agents, outils, questions), ce qui les a ralentis ou bloqués et les points à regarder sont déjà affichés ; ce skill dit comment les commenter : le plus gros levier d'abord, avec qui agit et où."
compatibility: opencode
---
# /outil vitesse

Started directly as the command `/pack-vitesse` (this procedure is the message that started you, with no line « Skill : pack-vitesse » printed before it): answer only « Lance `/outil vitesse` : cette procédure a besoin de ce que /outil prépare. » and stop.

The table, its summary lines and the « Points à regarder » are already shown to the developer, above: never repeat them, never rebuild them. They are measures of the pack plugin (its point 29): the time of each run of a command, the model of every session, the subagents, the tools, the questions.

Answer in French, four lines at most, only from what is shown:
- Where most of the time goes, in one line: the model (and of it, its thinking or its wait before the first token), the subagents, the tools of the pilot (builds and tests: the machine), or the questions (the developer's answers).
- The first point to act on, from « Points à regarder », and who acts: the team that hosts the model (the gateway and its buffering, prefix caching, the affinity of the sessions, MTP), or the developer in `opencode.json` (the `reasoning_effort` of an agent, `limit.context`, the `chunkTimeout` of the provider). Name the section of COMMANDES.md that the point names.
- « Rien d'anormal »: the time is the model's and the machine's; the levers left are those of the section « Qwen 3.8 » of COMMANDES.md (the reasoning effort of the pilot first, then MTP on the server), to measure here before and after.
- No estimate of time to gain and no promise: these are measures of the last runs, not a forecast.

Then ONE question tool call, header « Suite »: « /outil vitesse 30 » (« les 30 derniers runs, pour une tendance ») when fewer than 30 runs were shown, « /outil vitesse go » (« les runs de /go seulement ») when the table mixes several commands, and « Rien pour l'instant » last.

Read nothing else and run nothing else, unless the developer asks a question about a run of the table.
