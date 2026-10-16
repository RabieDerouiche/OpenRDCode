---
description: "Start a Jira ticket: create the branch from an up-to-date develop, named from the ticket type and summary. Usage: /git-start <JIRA-KEY>"
agent: git
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`

Start the work on Jira ticket $1.

Steps:
1. If the working tree above is not empty, ask me with the question tool: "Mettre de côté (stash) et continuer" / "Annuler, je commite d'abord" (recommandé). Stash only if I choose it.
2. Read ticket $1 with the Jira MCP tools (read only): type and summary. If it is not found, ask me for the key again.
3. Propose the branch name: `feature/$1-<summary in 3 to 5 kebab-case words, ASCII, lowercase>`; use `bugfix/` for a bug and `hotfix/` if the ticket is marked urgent or as a production incident. Ask me with the question tool: "<proposed name>" (recommandé) / "Autre nom" (free answer).
4. If a local or remote branch with that name already exists (`git branch -a --list "*<name>"`), ask me: "Basculer sur la branche existante" / "Choisir un autre nom".
5. Run `git fetch origin develop`, then `git switch -c <name> origin/develop`.
6. Ask me with the question tool: "Publier la branche maintenant (git push -u)" / "Plus tard, au premier /git-ship" (recommandé).
7. If a stash was made in step 1, ask me: "Réappliquer mes modifications sur la nouvelle branche" / "Les laisser dans le stash".
8. End with the branch state, then suggest: `/start-ticket $1` for the analysis and the plan.
