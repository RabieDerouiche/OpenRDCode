---
description: "Review, commit and push the current work on the feature branch, with my approval at each sensitive step, then give the merge request link."
agent: git
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`
Staged changes summary: !`git diff --staged --stat`
Unstaged changes summary: !`git diff --stat`

Ship the current work of this branch.

Steps:
1. If the current branch is `develop`, `master` or `main`, stop and ask me with the question tool: "Créer une branche avec /git-start" (recommandé) / "Annuler". Never commit there.
2. If the working tree is empty and nothing is ahead of `origin/<branch>`, say "Rien à livrer" and stop. If the working tree is empty but local commits are not pushed, go to step 7.
3. Ask me with the question tool what to include: "Tous les fichiers modifiés" (recommandé) / "Seulement les fichiers déjà indexés" / "Je choisis les fichiers" (free answer). Stage accordingly (`git add -A` or `git add <files>`).
4. Review: invoke the `reviewer` subagent with the task tool on the staged changes (`git diff --staged`). If its verdict is "BLOCKING ISSUES", show the blocking findings and ask me with the question tool: "Corriger d'abord" (recommandé, stop here) / "Commiter quand même". For "CHANGES REQUESTED", show the findings in 3 lines max and continue.
5. Write a Conventional Commits message in English from the staged diff: `type(scope): summary` (max 72 characters), a blank line, at most 5 bullets. Put the Jira key from the branch name in the summary if there is one (e.g. `feat(export): add PDF export (DNA-123)`). Never use backticks, `$` or double quotes inside the message (they would be blocked by the shell rules). Ask me with the question tool: "Commiter avec ce message" (recommandé) / "Modifier le message" (free answer) / "Annuler".
6. Commit with `git commit -m "<summary>" -m "<body>"`.
7. Run `git fetch origin`. If `origin/<branch>` has commits that are not local, stop and suggest `/git-sync` first.
8. Push with `git push -u origin <branch>` (asks for approval). Never force.
9. Show the merge request link printed by GitLab in the push output, if any, and suggest `/mr-desc` for the description. End with the branch state.
