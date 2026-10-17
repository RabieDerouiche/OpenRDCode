---
name: sync-procedure
description: "Procedure of the git agent to bring a feature branch up to date: commit local work locally, retrieve the branch remote changes (for example pushed from another computer), merge the base branch (develop), then offer to push. Merge only. Used by /sync and /next. Only for the git agent."
compatibility: opencode
---
# Sync procedure

## Inputs
The workflow state injected by the command (branch, ticket key, base branch, HEAD, remote copy and upstream, uncommitted, staged and untracked files). If no command injected it, run `sh ~/.config/opencode/scripts/workflow-state.sh` once. Use `git status --porcelain` only when you need the exact working tree.

Bring the current branch up to date. Order: secure local work, retrieve remote changes, merge the base branch (`<base>` below: the "Base branch" line of the workflow state, normally `origin/develop`), and only then push. Merge only, never rebase. Never push before step 6.

Calls: push, merge, pull and stash ask for my approval, so each of them runs alone in its call. The other git commands that must run in order go in one call, chained with `&&`, as written below.

Steps:
1. If the current branch is `develop`, `master` or `main`: run `git fetch -q origin && git merge --ff-only origin/<branch>` in one call and stop.
2. Local work. If the workflow state shows uncommitted or untracked files, ask me with the question tool:
   - "Commit local de tout, sans push" (recommandé): then, in one call, `git add -A && git diff --staged --stat && git diff --staged`.
   - "Commit local des fichiers déjà suivis seulement, sans push": then, in one call, `git add -u && git diff --staged --stat && git diff --staged`.
   - "Mettre de côté (stash) pendant la synchro": `git stash push -u -m "sync"` (asks for approval).
   - "Annuler".
   For a commit: write a Conventional Commits message in English from the staged diff (`type(scope): summary`, max 72 characters, Jira key from the branch name in the summary, at most 5 bullets in the body, no backticks, `$` or double quotes), and ask me with the question tool "Commiter avec ce message" (recommandé) / "Modifier le message" (free answer). The commit runs at the start of step 3. Do not push.
3. In one call, after the commit of step 2 when there is one (`git commit -m "<summary>" -m "<body>" && ...`): `git fetch -q origin && git rev-list --left-right --count HEAD...<base> && git log --oneline -15 HEAD..<base> && git rev-list --left-right --count HEAD...origin/<branch>`. Counts: left = local only, right = remote only. The last command fails when `origin/<branch>` does not exist yet: then skip step 4.
4. The branch's own remote changes, from the last count:
   - Remote only = 0: nothing to retrieve.
   - Remote only > 0 and local only = 0: run `git merge --ff-only origin/<branch>`.
   - Both > 0 (the branch was changed here and elsewhere): say it in one line, then run `git merge --no-edit origin/<branch>` (asks for approval).
5. Base branch: its new commits are the right count of `HEAD...<base>` and the log of step 3. Ask me, in ONE question tool call, the questions that apply:
   - `<base>` has new commits (list them): "Merger <base> maintenant" (recommandé) / "Plus tard";
   - the branch has, or will have after that merge, commits that are not on `origin/<branch>` (or `origin/<branch>` does not exist): "Pousser à la fin" (recommandé) / "Plus tard".
   If the merge is chosen, run `git merge --no-edit <base>` (asks for approval).
6. Push, if it was chosen in step 5 and no conflict is pending: `git push -u origin <branch>` (asks for approval). Never force.
7. On a merge conflict (in step 4 or 5): list the conflicting files given by `git diff --name-only --diff-filter=U`, and ask me with the question tool:
   - "Je résous dans Rider, préviens-moi ensuite" (recommandé): stop here. When I come back, check `git status`, finish the merge with `git commit --no-edit` only if no conflict remains, then continue with the next step.
   - "Annuler la synchro": run `git merge --abort` and stop. Do not push.
   Never edit the conflicting files yourself.
8. If a stash was made in step 2, run `git stash pop` (asks for approval); if it conflicts, list the files and stop.
9. If something was merged, say that the build and tests must be run again: "Prochaine étape : /check" (if the build breaks: ask the build agent « corrige le build », it uses the skill `build-fix`). End with the branch state.
