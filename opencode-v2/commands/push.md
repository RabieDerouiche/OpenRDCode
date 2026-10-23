---
description: "Commit and push the work of this folder, with or without a ticket (a POC, a quick test, an OpenCode workspace): on develop, main or a detached workspace it first gets a branch of its own; then the commits pushed from another computer are merged, the changes are checked before the push, and it is pushed. No merge request unless asked. Usage: /push [commit message] [« avec develop »] [« avec MR »] [« branche <name> »]"
agent: pilot
subtask: false
---
[[command push $ARGUMENTS]]
Request: « $ARGUMENTS »

Workflow state (no fetch here: ship.sh fetches what it needs):
[[run workflow-state.sh --no-fetch]]

Commit and push the work of this folder now, in this single run. This is not a ticket run: no ticket sheet, no subagent, no build or tests unless the request asks for them (« avec les tests »: `sh ~/.config/opencode/scripts/build-test.sh` first, and a failure stops the push). Never ask anything: decide and say what you decided.

1. Stop at once, with its line, when:
   - "Merge in progress: yes": « ⛔ Une fusion est en cours : termine-la dans Rider (ou git merge --abort), puis relance /push. »
   - "Uncommitted files" and "Untracked files" list nothing, and "Branch vs its remote copy" says up to date: « ✅ Rien à pousser : <branch> est à jour sur origin. »
2. The branch. On develop, master or main, on a detached HEAD (an OpenCode workspace starts so), or on a branch `opencode/…`: the work gets a branch of its own, in ONE shell call, `sh ~/.config/opencode/scripts/branch.sh --here <type> "<summary>"`. The type: `poc` by default; `feature`, `bugfix`, `hotfix` or `wip` when the request says so. The summary: the name the request gives (« branche <name> »), otherwise 3 to 6 words of what the changes do, from the request or from the file names of `git diff --stat HEAD`. A "STOP:" line: stop with it. On any other branch: it stays as it is.
3. The commit message: the one of the request, when it gives one (its text without the directives « avec develop », « avec MR », « avec les tests », « branche <name> »). Otherwise write it from the changes (`git diff --stat HEAD`, then `git diff HEAD -- <a few files>` when their names do not say enough): a conventional commit in English, `<type>(<scope>): <what>` (feat, fix, refactor, test, chore, docs, perf), with the Jira key of the branch at the end in parentheses when the branch has one. Never backticks, `$` or double quotes in it.
4. In ONE shell call: `sh ~/.config/opencode/scripts/ship.sh [--base] "<message>"`, with `--base` only when the request says « avec develop » (it also merges the base branch, the "Base branch" line). It commits everything, merges the commits pushed on the branch from another computer, checks the changes, then pushes. "GUARD: STOP": stop with « ⛔ Contrôle avant push : rien n'a été poussé », its lines, and « COMMANDES.md, section « Contrôle avant push » ». Another "STOP:" line: stop with it (a conflict is resolved in Rider; AUTH FAILED: COMMANDES.md, section « Identifiants GitLab »).
5. « avec MR » in the request: the merge request as your rules say (the open one of the branch first; none: create it as Draft, target the "Base branch" line, title `Draft: <commit summary>`, a short description in French of what the commits do, from `git log --oneline <base>..HEAD` and `git diff --stat <base>...HEAD`). Otherwise no merge request: the "MR LINK" line of ship.sh creates one in GitLab.

## Answer, in French
Header line « **/push** — <branch> », then the line of the outcome: « 🚀 Poussé sur origin/<branch> », or the « ⛔ » line of the step that stopped. Then the commit (short hash and message), the branch created by step 2 when there is one, what ship.sh merged (its REMOTE and BASE lines), the WARNING and PACKAGES lines when there are some, and the merge request link (or the link that creates it). No narration of the steps.
