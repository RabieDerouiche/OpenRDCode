---
name: sync-procedure
description: "Procedure of the git agent to bring a feature branch up to date: commit local work locally, retrieve the branch remote changes (for example pushed from another computer), merge the base branch (develop), then offer to push. Merge only. Used by /sync and /next. Only for the git agent."
compatibility: opencode
---
# Sync procedure

## Inputs
The workflow state injected by the command (branch, ticket key and sheet, base branch, HEAD, remote copy and upstream, uncommitted, staged and untracked files). If no command injected it, run `sh ~/.config/opencode/scripts/workflow-state.sh` once. Use `git status --porcelain` when you need the exact working tree.

Bring the current branch up to date. Order: secure local work, retrieve remote changes, merge the base branch (the "Base branch" line of the workflow state, normally `origin/develop`), and only then push. Merge only, never rebase. Never push before step 6.

Steps:
1. If the current branch is `develop`, `master` or `main`, run `git fetch origin`, then `git merge --ff-only origin/<branch>` and stop.
2. Local work. If the workflow state shows uncommitted or untracked files, ask me with the question tool:
   - "Commit local de tout, sans push" (recommandé): `git add -A`.
   - "Commit local des fichiers déjà suivis seulement, sans push": `git add -u`.
   - "Mettre de côté (stash) pendant la synchro": `git stash push -u -m "sync"` (asks for approval).
   - "Annuler".
   For a commit: write a Conventional Commits message in English from `git diff --staged` (`type(scope): summary`, max 72 characters, Jira key from the branch name in the summary, at most 5 bullets in the body, no backticks, `$` or double quotes), ask me with the question tool "Commiter avec ce message" (recommandé) / "Modifier le message" (free answer), then run `git commit -m "<summary>" -m "<body>"`. Do not push.
3. Run `git fetch origin`.
4. Retrieve the branch's own remote changes, `origin/<branch>` (skip if it does not exist yet):
   - Count with `git rev-list --left-right --count HEAD...origin/<branch>` (left = local only, right = remote only).
   - Remote only = 0: nothing to retrieve.
   - Remote only > 0 and local only = 0: run `git merge --ff-only origin/<branch>`.
   - Both > 0 (the branch was changed here and elsewhere): say it in one line, then run `git merge --no-edit origin/<branch>` (asks for approval).
5. Base branch (`<base>` below, normally `origin/develop`): count with `git rev-list --left-right --count HEAD...<base>`; if it has new commits, list them (`git log --oneline HEAD..<base>`, at most 15). Then ask me, in ONE question tool call, the questions that apply:
   - `<base>` has new commits: "Merger <base> maintenant" (recommandé) / "Plus tard";
   - the branch has, or will have after that merge, commits that are not on `origin/<branch>` (or `origin/<branch>` does not exist): "Pousser à la fin" (recommandé) / "Plus tard".
   If the merge is chosen, run `git merge --no-edit <base>` (asks for approval).
6. Push, if it was chosen in step 5 and no conflict is pending: `git push -u origin <branch>` (asks for approval). Never force.
7. On a merge conflict (in step 4 or 5): run `git diff --name-only --diff-filter=U`, list the files, and ask me with the question tool:
   - "Je résous dans Rider, préviens-moi ensuite" (recommandé): stop here. When I come back, check `git status`, finish the merge with `git commit --no-edit` only if no conflict remains, then continue with the next step.
   - "Annuler la synchro": run `git merge --abort` and stop. Do not push.
   Never edit the conflicting files yourself.
8. If a stash was made in step 2, run `git stash pop` (asks for approval); if it conflicts, list the files and stop.
9. If something was merged, say that the build and tests must be run again: "Prochaine étape : /check" (if the build breaks: ask the build agent « corrige le build », it uses the skill `build-fix`). End with the branch state.
