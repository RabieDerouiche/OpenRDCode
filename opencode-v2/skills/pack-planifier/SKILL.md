---
name: pack-planifier
description: "Procédure de /outil planifier : les commandes qui n'écrivent rien (/daily, /outil audit, /outil licences, /tests env <environnement>) lancées toutes seules à heure fixe par le plugin ; sans argument, un QCM (quoi, quand, quels jours, ou retirer) ; avec une planification (/outil planifier 8h45 lun-ven /daily, /outil planifier suppr <n>), aussitôt."
compatibility: opencode
---
# /outil planifier

Started directly as the command `/pack-planifier` (this procedure is the message that started you, with no line « Skill : pack-planifier » printed before it): answer only « Lance `/outil planifier` : cette procédure a besoin de ce que /outil prépare. » and stop.

With arguments (a schedule, « liste », « suppr <n> »), the pack already ran `schedule.sh` and showed its result to me as my message: answer « OK » and nothing else, without any tool call.

Without arguments: the wizard. The facts above give the current schedules, the environments and the repository.
1. ONE question tool call, its questions together:
   - header « Quoi », the labels never starting with « / » (an option that is a command would start it at once, instead of planning it): « Le point du matin (daily) (recommandé) », « Tests d'environnement de <name> » for each environment that is not production (« /tests env <name>, en lecture seule »), « Audit des bonnes pratiques » (« /outil audit »), « Licences des packages » (« /outil licences »), and « Retirer une planification » when there is one; the developer may type another command (schedule.sh refuses what writes).
   - header « Heure »: « 8h45 (recommandé) », « 7h30 », « 12h30 », « 18h00 »; or typed (`9h10`, `22h`).
   - header « Jours »: « Du lundi au vendredi (recommandé) », « Tous les jours », « Le lundi » ; or typed (`lun,mer,ven`).
   - header « Retirer », `multiple: true`, only when there are schedules: one option per schedule (label « #<n> à <its time> : <its command without its slash> »), and « Aucune ».
2. ONE shell call with what was chosen: `sh ~/.config/opencode/scripts/schedule.sh add <time> <days: lun-ven, tous les jours, or the names> </command>` and/or `sh ~/.config/opencode/scripts/schedule.sh remove <n>[,<n>]` (joined with ` ; `). Its output in French goes as it is into the answer.
3. The answer: that output, then one line: OpenCode must run at that time (its service), and what it missed is not started later. No « Suite » question.

Outside /outil, in plain words (« lance /daily tous les matins à 8h45 », « mes planifications ») → `sh ~/.config/opencode/scripts/schedule.sh add <heure> <jours> </commande>` (or `schedule.sh`, or `schedule.sh remove <n>`) and show its output as it is. Never edit `~/.config/opencode/schedules.md` yourself, never plan a command that writes (/go, /fix, /push, /sync, /fortify) or a wizard (/tests env config): `schedule.sh` refuses it, and so does the plugin.
