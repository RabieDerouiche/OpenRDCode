---
name: pack-todo
description: "Procédure de /outil todo : ma todo list personnelle, hors Jira et hors dépôts, avec des rappels (/outil todo, /outil todo <texte avec une échéance>, /outil todo fait <n>, /outil todo suppr <n>, /outil todo rappels)."
compatibility: opencode
---
# /outil todo

Started directly as the command `/pack-todo` (this procedure is the message that started you, with no line « Skill : pack-todo » printed before it): answer only « Lance `/outil todo` : cette procédure a besoin de ce que /outil prépare. » and stop.

The pack already ran `todo.sh` and showed its result to me as my message. Answer « OK » and nothing else, without any tool call.

Outside /outil, in plain words: « rappelle-moi de … », « ajoute à ma todo … » → `sh ~/.config/opencode/scripts/todo.sh add "<the item as I said it, with its due date in plain words>"` and show its output; « ma todo », « mes rappels » → `sh ~/.config/opencode/scripts/todo.sh` (or `… todo.sh due`). Never in Jira.
