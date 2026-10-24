---
name: pack-abandon
description: "Procédure de /outil abandon : annule un ticket lancé par erreur (mauvais dépôt, mauvais ticket) : retour sur la branche de base, puis suppression de la branche locale du ticket et de sa fiche, après ma validation. Refuse quand la branche contient du travail. Rien ne change dans Jira ni dans GitLab."
compatibility: opencode
---
# /outil abandon

Started directly as the command `/pack-abandon` (this procedure is the message that started you, with no line « Skill : pack-abandon » printed before it): answer only « Lance `/outil abandon` : cette procédure a besoin de ce que /outil prépare. » and stop.

Undo the ticket of the current branch, started by mistake. Never lose work: `abandon.sh` refuses by itself a branch that holds anything of its own. The workflow state is printed above.

1. `sh ~/.config/opencode/scripts/abandon.sh --check`, alone in its call. A "STOP:" line: say it in French (what the branch holds, or why there is nothing to abandon) and stop: never delete anything yourself, never force.
2. Confirm, with the question tool: "Abandonner <branch> dans <repository folder name>" (recommandé) / "Annuler", with in its description the "WOULD DELETE" and "WOULD SWITCH" lines, said simply.
3. "Abandonner": `sh ~/.config/opencode/scripts/abandon.sh`, alone in its call. A "STOP:" line: say it and stop.

Answer, in French: one line per DELETED and SWITCHED line, said simply. A WARNING line: say it (the branch is kept). A "PUSHED" line: « La branche existe aussi sur GitLab : supprime-la depuis la page Branches du projet (je ne supprime jamais rien sur GitLab). » A "WORKTREE" line: « Ce dossier ne contient plus rien : supprime-le depuis le dépôt principal (`git worktree remove <its path>`), puis archive ses sessions. » Last line: « Rien n'a changé dans Jira. Pour repartir : nouvelle session dans le bon dépôt, puis /go <KEY>. »
