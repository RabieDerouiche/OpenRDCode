---
name: ship-procedure
description: "Procedure of the git agent to ship the current work of a feature branch: review (skipped if /check validated this exact state), commit, retrieve the remote changes of the branch, push with approval, merge request link and description. Used by /ship and /next. Only for the git agent."
compatibility: opencode
---
# Ship procedure

## Inputs
The workflow state injected by the command (branch, ticket key and sheet, base branch, HEAD, remote copy and upstream, uncommitted, staged and untracked files). If no command injected it, run `sh ~/.config/opencode/scripts/workflow-state.sh` once. Use `git status --porcelain` when you need the exact working tree.

Ship the current work of this branch. The Jira key is in the branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`); the ticket sheet is `.git/opencode/tickets/<KEY>.md` if the workflow state lists it. Read it now if it exists.

Base branch for the merge request: the "Base branch" line of the workflow state. If it says NONE, ask me with the question tool for the base branch (free answer).

Steps:
1. If the current branch is `develop`, `master` or `main`, stop and ask me with the question tool: "Créer une branche avec /ticket" (recommandé) / "Annuler". Never commit there.
2. If the working tree is empty and nothing is ahead of `origin/<branch>`, say "Rien à livrer" and stop. If the working tree is empty but local commits are not pushed, go to step 7.
3. Ask me with the question tool what to include: "Tous les fichiers modifiés" (recommandé) / "Seulement les fichiers déjà indexés" / "Je choisis les fichiers" (free answer). Stage accordingly (`git add -A` or `git add <files>`).
4. Review. Skip it, and say "Review déjà faite par /check sur cet état", only if ALL of these are true:
   - the last `/check` line of the sheet's "## Suivi" has the same HEAD and the same uncommitted changes summary as above (both read before staging),
   - its untracked files count is the same as the number of untracked files above,
   - its verdict is not "BLOCKING ISSUES".
   Otherwise invoke the `reviewer` subagent with the task tool and this prompt: "Review the staged changes of the repository for ticket <KEY or branch>. The diff is not in this prompt: get it with `git diff --staged` (if it is very long, start with `git diff --staged --stat` and review file by file). Use your usual output format." If its verdict is "BLOCKING ISSUES", show the blocking findings and ask me with the question tool: "Corriger d'abord" (recommandé, stop here) / "Commiter quand même". For "CHANGES REQUESTED", show the findings in 3 lines max and continue.
5. Write a Conventional Commits message in English from the staged diff (types: feat, fix, refactor, test, chore, docs, perf, ci, build): `type(scope): summary` (max 72 characters, imperative mood, the scope is the feature or project name), a blank line, at most 5 bullets. Put the Jira key in the summary if there is one (e.g. `feat(export): add PDF export (DNA-123)`). If the changes include a breaking change for API consumers, add a `BREAKING CHANGE:` line at the end of the body. Never use backticks, `$` or double quotes inside the message (they would be blocked by the shell rules). Ask me with the question tool: "Commiter avec ce message" (recommandé) / "Modifier le message" (free answer) / "Annuler".
6. Commit with `git commit -m "<summary>" -m "<body>"`.
7. Retrieve the branch's remote changes before pushing. Run `git fetch origin`, then, if `origin/<branch>` exists, `git rev-list --left-right --count HEAD...origin/<branch>` (left = local only, right = remote only):
   - Remote only = 0: go to step 8.
   - Local only = 0: run `git merge --ff-only origin/<branch>`.
   - Both > 0: say it in one line, then run `git merge --no-edit origin/<branch>` (asks for approval).
   - On a conflict: run `git diff --name-only --diff-filter=U`, list the files, and ask me with the question tool: "Je résous dans Rider, préviens-moi ensuite" (recommandé: stop; when I come back, check `git status`, run `git commit --no-edit` only if no conflict remains, then go to step 8) / "Annuler" (run `git merge --abort` and stop without pushing). Never edit the conflicting files yourself.
   Do not merge the base branch here: that is /sync.
8. Push with `git push -u origin <branch>` (asks for approval). Never force.
9. Merge request:
   - The link: the one printed by GitLab in the push output, otherwise look for an open merge request of this branch with the GitLab MCP tools (read-only). Never create the merge request yourself: if none exists, give the creation link from the push output.
   - The description, in French, in a markdown code block, built from `git log --oneline <base>..HEAD`, `git diff --stat <base>...HEAD` and the ticket sheet, with exactly these sections:
     - `## Contexte`: why this change exists, from the sheet's "Résumé" with the Jira link; without a sheet, deduced from commits and code, or "À compléter".
     - `## Changements`: bullet list grouped by project, layer or folder, following the structure of this repository.
     - `## Critères d'acceptation`: checklist from the sheet, `- [x]` for criteria with a passing test in "Tests attendus", `- [ ]` otherwise. Omit without a sheet.
     - `## Impacts`: breaking changes for API consumers (routes, contracts, status codes), configuration or environment variables to add, database or external integration changes (SharePoint, DocuSign, S3, Piano): each one or "Aucun".
     - `## Points d'attention pour la review`: the 1 to 3 places where a reviewer should look carefully, with file paths.
     - `## Comment tester`: concrete steps (endpoint + payload, or test names).
     Only describe what is in the diff. Never invent ticket numbers, features or tests.
10. If the sheet exists, append to its "## Suivi": `- <date> /ship - <short hash> poussé - MR <link or "à créer">` (date: the "Now" line of the workflow state).
11. Start the final answer with the header line "**[<KEY>](<Jira link>) - <title>**" (title from the "Ticket title line" of the workflow state, link from its "Ticket Jira line"; the branch name if there is no sheet). End with the branch state, then: "La CI tourne (build, tests, Sonar, Fortify). Lance /scans quand le pipeline est terminé."
