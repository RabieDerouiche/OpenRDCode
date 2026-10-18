---
description: "Undo a ticket started by mistake (wrong repository or wrong ticket): back to the base branch, then the ticket branch and its ticket sheet deleted, each with my approval. Refuses when the branch holds work of its own. Nothing changes in Jira. Usage: /abandon"
agent: git
---
Workflow state (one fetch, then the state of the branch and its ticket sheet):
!`sh ~/.config/opencode/scripts/workflow-state.sh`

Undo the ticket of the current branch, started by mistake. Never lose work.

## Step 1 - Checks
From the workflow state above, without any tool call:
- On `develop`, `master` or `main`: say "Rien à abandonner sur <branch>" and stop.
- The branch must hold nothing of its own: the "Commits behind / ahead of <base>" line says 0 ahead, and there is no uncommitted and no untracked file. Otherwise list what it holds (commits, files) and stop: "Cette branche contient du travail : je ne la supprime pas. Commite-le ailleurs ou supprime la branche toi-même."

## Step 2 - Confirm
Ask me with the question tool: "Abandonner <branch> dans <repository folder name, the last part of the Repository root line>" (recommandé) / "Annuler". Say in its description what will be deleted: the local branch and, if it exists, the ticket sheet `.git/opencode-tickets/<KEY>.md`.

## Step 3 - Undo
Each command alone in its call, in this order:
1. `git switch <base branch without origin/> && git merge --ff-only <base branch>` (the local base branch must contain the ticket branch for the next command to accept it).
2. `git branch -d <branch>` (asks for my approval; it refuses a branch with unmerged work: then say so and stop, never force).
3. Only if the workflow state lists a current ticket sheet: `rm .git/opencode-tickets/<KEY>.md` (asks for my approval).

## Answer, in French
One line per thing deleted. If the "Upstream" line shows the branch was pushed, add: "La branche existe aussi sur GitLab : supprime-la depuis la page Branches du projet (je ne supprime jamais rien sur GitLab)." Last line: "Rien n'a changé dans Jira. Pour repartir : ouvre une nouvelle session dans le bon dépôt, puis /ticket <KEY>."
