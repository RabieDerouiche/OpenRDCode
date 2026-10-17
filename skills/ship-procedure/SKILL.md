---
name: ship-procedure
description: "Procedure of the git agent to ship the current work of a feature branch: review (skipped if /check validated this exact state), commit, retrieve the remote changes of the branch, push with approval, merge request link and description. Used by /ship and /next. Only for the git agent."
compatibility: opencode
---
# Ship procedure

## Inputs
The workflow state injected by the command (branch, ticket key and sheet content, base branch, HEAD, remote copy and upstream, uncommitted, staged and untracked files). If no command injected it, run `sh ~/.config/opencode/scripts/workflow-state.sh --sheet` once. Use `git status --porcelain` only when you need the exact working tree.

Ship the current work of this branch. The Jira key is in the branch name (pattern `[A-Z][A-Z0-9_]+-[0-9]+`); its ticket sheet is printed in the workflow state when it exists: do not read it again.

Base branch for the merge request: the "Base branch" line of the workflow state. If it says NONE, ask me with the question tool for the base branch (free answer).

Calls: push, merge, pull and stash ask for my approval, so each of them runs alone in its call. The other git commands that must run in order go in one call, chained with `&&`, as written below.

Steps:
1. If the current branch is `develop`, `master` or `main`, stop and ask me with the question tool: "Créer une branche avec /ticket" (recommandé) / "Annuler". Never commit there.
2. If the working tree is empty:
   - No commit to push (the "Branch vs its remote copy" line says "up to date", or "none" while there is no commit since the base branch): say "Rien à livrer" and stop.
   - Otherwise there are commits to push. If the branch has a ticket sheet and no `/check` line of its "## Suivi" has `empreinte <value>` equal to the "Code fingerprint" of the workflow state with a verdict other than "BLOCKING ISSUES", this code was never checked (for example a local commit of /sync, or a merge of develop): ask me with the question tool "Lancer /check d'abord" (recommandé: stop and say "Tape /check") / "Pousser quand même". Then go to step 7.
3. Ask me with the question tool what to include: "Tous les fichiers modifiés" (recommandé) / "Seulement les fichiers déjà indexés" / "Je choisis les fichiers" (free answer). Then stage and show what will be committed, in one call: `git add -A && git diff --staged --stat && git diff --staged` (`git add <files> && ...` for chosen files; `git diff --staged --stat && git diff --staged` alone for the files already staged).
4. Review. Skip it, and say "Review déjà faite par /check sur ce code exact", only if a `/check` line of the sheet's "## Suivi" has `empreinte <value>` equal to the "Code fingerprint" of the workflow state and a verdict other than "BLOCKING ISSUES" (the fingerprint changes with any edit of the code, committed or not, and does not change when the same code is staged or committed).
   Otherwise invoke the `reviewer` subagent with the task tool and this prompt: "Review the staged changes of the repository for ticket <KEY or branch>. The diff is not in this prompt: get it with `git diff --staged` (if it is very long, start with `git diff --staged --stat` and review file by file). Use your usual output format." If its verdict is "BLOCKING ISSUES", show the blocking findings and ask me with the question tool: "Corriger d'abord" (recommandé, stop here) / "Commiter quand même". For "CHANGES REQUESTED", show the findings in 3 lines max and continue.
5. Write a Conventional Commits message in English from the staged diff (types: feat, fix, refactor, test, chore, docs, perf, ci, build): `type(scope): summary` (max 72 characters, imperative mood, the scope is the feature or project name), a blank line, at most 5 bullets. Put the Jira key in the summary if there is one (e.g. `feat(export): add PDF export (ABC-123)`). If the changes include a breaking change for API consumers, add a `BREAKING CHANGE:` line at the end of the body. Never use backticks, `$` or double quotes inside the message (they would be blocked by the shell rules). Ask me with the question tool: "Commiter avec ce message" (recommandé) / "Modifier le message" (free answer) / "Annuler".
6. Commit, then retrieve the branch's remote changes, in one call: `git commit -m "<summary>" -m "<body>" && git fetch -q origin && git rev-list --left-right --count HEAD...origin/<branch>`. The last command fails when `origin/<branch>` does not exist yet: then go to step 8. Otherwise (left = local only, right = remote only):
   - Remote only = 0: go to step 8.
   - Local only = 0: run `git merge --ff-only origin/<branch>`.
   - Both > 0: say it in one line, then run `git merge --no-edit origin/<branch>` (asks for approval).
   - On a conflict: list the conflicting files given by `git diff --name-only --diff-filter=U`, and ask me with the question tool: "Je résous dans Rider, préviens-moi ensuite" (recommandé: stop; when I come back, check `git status`, run `git commit --no-edit` only if no conflict remains, then go to step 8) / "Annuler" (run `git merge --abort` and stop without pushing). Never edit the conflicting files yourself.
   Do not merge the base branch here: that is /sync.
7. Nothing to commit but local commits to push: run `git fetch -q origin && git rev-list --left-right --count HEAD...origin/<branch>` in one call, then apply the cases of step 6.
8. Push with `git push -u origin <branch>` (asks for approval). Never force.
9. Merge request. In one turn: look for the open merge request of this branch with the GitLab MCP tools (read-only), and run `git log --oneline <base>..HEAD && git diff --stat <base>...HEAD`.
   - The link: the one printed by GitLab in the push output, otherwise the open merge request found. Never create the merge request yourself: if none exists, give the creation link from the push output.
   - The description, in French, in a markdown code block, built from that log, that stat and the ticket sheet, with exactly these sections:
     - `## Contexte`: why this change exists, from the sheet's "Résumé" with the Jira link; without a sheet, deduced from commits and code, or "À compléter".
     - `## Changements`: bullet list grouped by project, layer or folder, following the structure of this repository.
     - `## Critères d'acceptation`: checklist from the sheet, `- [x]` for criteria with a passing test in "Tests attendus", `- [ ]` otherwise. Omit without a sheet.
     - `## Impacts`: breaking changes for API consumers (routes, contracts, status codes), configuration or environment variables to add, database or external integration changes (SharePoint, DocuSign, S3, Piano): each one or "Aucun".
     - `## Points d'attention pour la review`: the 1 to 3 places where a reviewer should look carefully, with file paths.
     - `## Comment tester`: concrete steps (endpoint + payload, or test names).
     Only describe what is in the diff. Never invent ticket numbers, features or tests.
10. If the sheet exists, append at the end of its "## Suivi" section, which ends the file (after its last line as printed in the workflow state), with the edit tool: `- <date> /ship - <short hash> poussé - MR <link or "à créer">` (date: the "Now" line of the workflow state).
11. Start the final answer with the header line "**[<KEY>](<Jira link>) - <title>**" (title from the "Ticket title line" of the workflow state, link from its "Ticket Jira line"; the branch name if there is no sheet). End with the branch state, then: "La CI tourne (build, tests, Sonar, Fortify). Lance /scans quand le pipeline est terminé."
