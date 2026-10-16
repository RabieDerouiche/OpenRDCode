---
description: "Bring the current branch up to date: first with its own remote copy (changes pushed from elsewhere), then with develop, by merge. Stops on conflicts and asks."
agent: git
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`

Bring the current branch up to date. Merge only, never rebase.

Steps:
1. If the current branch is `develop`, `master` or `main`, run `git fetch origin`, then `git merge --ff-only origin/<branch>` and stop.
2. If the working tree above is not empty, ask me with the question tool: "Commiter d'abord avec /git-ship" (recommandé) / "Mettre de côté (stash) pendant la synchro" / "Annuler".
3. Run `git fetch origin`.
4. The branch's own remote copy, `origin/<branch>` (if it exists):
   - Count with `git rev-list --left-right --count HEAD...origin/<branch>` (left = local only, right = remote only).
   - Remote only > 0 and local only = 0: run `git merge --ff-only origin/<branch>`.
   - Both > 0 (the branch was changed here and elsewhere): explain it in one line, then run `git merge --no-edit origin/<branch>` (asks for approval).
5. Develop: count with `git rev-list --left-right --count HEAD...origin/develop`. If develop has new commits, list them (`git log --oneline HEAD..origin/develop`, at most 15) and ask me with the question tool: "Merger develop maintenant" (recommandé) / "Plus tard". If yes, run `git merge --no-edit origin/develop` (asks for approval).
6. On a merge conflict (in step 4 or 5): run `git diff --name-only --diff-filter=U`, list the files, and ask me with the question tool:
   - "Je résous dans Rider, préviens-moi ensuite" (recommandé): stop here. When I come back, check `git status` and finish the merge with `git commit --no-edit` only if no conflict remains.
   - "Annuler la synchro": run `git merge --abort`.
   Never edit the conflicting files yourself.
7. If a stash was made in step 2, run `git stash pop` (asks for approval); if it conflicts, list the files and stop.
8. If something was merged, suggest running the build and tests (`/build-fix` if the build breaks). End with the branch state.
