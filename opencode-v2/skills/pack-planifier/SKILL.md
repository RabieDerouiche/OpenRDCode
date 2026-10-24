---
name: pack-planifier
description: "Procédure de /outil planifier : les commandes qui n'écrivent rien (/daily, /outil audit, /outil licences, /tests env <environnement>) lancées toutes seules à heure fixe par le plugin (/outil planifier 8h45 lun-ven /daily, /outil planifier suppr <n>, /outil planifier)."
compatibility: opencode
---
# /outil planifier

Started directly as the command `/pack-planifier` (this procedure is the message that started you, with no line « Skill : pack-planifier » printed before it): answer only « Lance `/outil planifier` : cette procédure a besoin de ce que /outil prépare. » and stop.

The pack already ran `schedule.sh` and showed its result to me as my message. Answer « OK » and nothing else, without any tool call.

Outside /outil, in plain words (« lance /daily tous les matins à 8h45 », « mes planifications ») → `sh ~/.config/opencode/scripts/schedule.sh add <heure> <jours> </commande>` (or `schedule.sh`, or `schedule.sh remove <n>`) and show its output as it is. Never edit `~/.config/opencode/schedules.md` yourself, never plan a command that writes (/go, /fix, /push, /sync, /fortify): `schedule.sh` refuses it, and so does the plugin.
