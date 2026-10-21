---
name: pack-abandon
description: "Procédure de /outil abandon : annule un ticket lancé par erreur (mauvais dépôt, mauvais ticket) : retour sur la branche de base, puis suppression de la branche locale du ticket et de sa fiche, après ma validation. Refuse quand la branche contient du travail. Rien ne change dans Jira ni dans GitLab."
compatibility: opencode
---
# /outil abandon

Started directly as the command `/pack-abandon` (this procedure is the message that started you, with no line « Skill : pack-abandon » printed before it): answer only « Lance `/outil abandon` : cette procédure a besoin de ce que /outil prépare. » and stop.

Undo the ticket of the current branch, started by mistake. Never lose work. The workflow state is printed above.

1. Checks, from the workflow state, without any tool call:
   - On develop, master or main: say « Rien à abandonner sur <branch> » and stop.
   - The branch must hold nothing of its own: the "Commits behind / ahead of <base>" line says 0 ahead, and there is no uncommitted and no untracked file. Otherwise list what it holds and stop: « Cette branche contient du travail : je ne la supprime pas. Commite-le ailleurs ou supprime la branche toi-même. »
2. Confirm, with the question tool: "Abandonner <branch> dans <repository folder name>" (recommandé) / "Annuler", with in its description what will be deleted: the local branch and, when it exists, the ticket sheet `.git/opencode-tickets/<KEY>.md`.
3. Undo, each command alone in its call, in this order: `git switch <base without origin/> && git merge --ff-only <base>`; then `git branch -d <branch>` (it refuses a branch with unmerged work: say so and stop, never force); then, only if the sheet exists, `rm .git/opencode-tickets/<KEY>.md`.

Answer, in French: one line per thing deleted. If the "Upstream" line shows the branch was pushed: « La branche existe aussi sur GitLab : supprime-la depuis la page Branches du projet (je ne supprime jamais rien sur GitLab). » Last line: « Rien n'a changé dans Jira. Pour repartir : nouvelle session dans le bon dépôt, puis /go <KEY>. »
