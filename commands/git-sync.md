---
description: "Bring the current branch up to date: commit local work locally (no push), pull the branch's own remote changes, merge develop, then offer to push. Merge only. Stops on conflicts and asks."
agent: git
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`

Bring the current branch up to date. Order: secure local work, retrieve remote changes, merge develop, and only then push. Merge only, never rebase. Never push before step 6.

Steps:
1. If the current branch is `develop`, `master` or `main`, run `git fetch origin`, then `git merge --ff-only origin/<branch>` and stop.
2. Local work. If the working tree above is not empty, ask me with the question tool:
   - "Commit local de tout, sans push" (recommandé): `git add -A`.
   - "Commit local des fichiers déjà suivis seulement, sans push": `git add -u`.
   - "Mettre de côté (stash) pendant la synchro": `git stash push -u -m "git-sync"` (asks for approval).
   - "Annuler".
   For a commit: write a Conventional Commits message in English from `git diff --staged` (`type(scope): summary`, max 72 characters, Jira key from the branch name in the summary, at most 5 bullets in the body, no backticks, `$` or double quotes), ask me with the question tool "Commiter avec ce message" (recommandé) / "Modifier le message" (free answer), then run `git commit -m "<summary>" -m "<body>"`. Do not push.
3. Run `git fetch origin`.
4. Retrieve the branch's own remote changes, `origin/<branch>` (skip if it does not exist yet):
   - Count with `git rev-list --left-right --count HEAD...origin/<branch>` (left = local only, right = remote only).
   - Remote only = 0: nothing to retrieve.
   - Remote only > 0 and local only = 0: run `git merge --ff-only origin/<branch>`.
   - Both > 0 (the branch was changed here and elsewhere): say it in one line, then run `git merge --no-edit origin/<branch>` (asks for approval).
5. Develop: count with `git rev-list --left-right --count HEAD...origin/develop`. If develop has new commits, list them (`git log --oneline HEAD..origin/develop`, at most 15) and ask me with the question tool: "Merger develop maintenant" (recommandé) / "Plus tard". If yes, run `git merge --no-edit origin/develop` (asks for approval).
6. Push. If the branch now has commits that are not on `origin/<branch>` (or `origin/<branch>` does not exist), ask me with the question tool: "Pousser maintenant" (recommandé) / "Plus tard". If yes, run `git push -u origin <branch>` (asks for approval). Never force.
7. On a merge conflict (in step 4 or 5): run `git diff --name-only --diff-filter=U`, list the files, and ask me with the question tool:
   - "Je résous dans Rider, préviens-moi ensuite" (recommandé): stop here. When I come back, check `git status`, finish the merge with `git commit --no-edit` only if no conflict remains, then continue with the next step.
   - "Annuler la synchro": run `git merge --abort` and stop. Do not push.
   Never edit the conflicting files yourself.
8. If a stash was made in step 2, run `git stash pop` (asks for approval); if it conflicts, list the files and stop.
9. If something was merged, suggest running the build and tests (`/build-fix` if the build breaks). End with the branch state.
