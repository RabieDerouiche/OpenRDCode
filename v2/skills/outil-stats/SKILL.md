---
name: outil-stats
description: "Procédure de /outil stats : le tableau de ce que /go et /fix ont fait sur les tickets du dépôt (étapes, lancements, /fix, réponses du développeur, décisions de l'agent, arrêts, temps de l'analyse à la MR) est déjà affiché ; ce skill dit comment le commenter en trois lignes au plus."
compatibility: opencode
---
# /outil stats

The table and its "Total" line are already shown to the developer, above: never repeat them, never rebuild them.

Answer in French, three lines at most, only from the table:
- What stands out: the tickets stopped or still running (with their key), the ticket that needed the most interventions, and the median time from the analysis to the merge request when there is one.
- When a ticket has stops or several launches of /go, one line: « Pour voir pourquoi : `cat .git/opencode-tickets/<KEY>.md` (section Suivi) », or read its « ## Suivi » section yourself if the developer asks why.
- No advice, no praise, no estimate of time saved: these numbers are measures, not a comparison with work done by hand.

Read nothing else and run nothing else, unless the developer asks a question about a ticket of the table.
