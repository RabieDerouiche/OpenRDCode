---
description: "Where am I and what next? Reads the branch, the working tree (including changes made outside OpenCode), the ticket sheet, the pipeline and the merge request, then proposes the next step in a multiple-choice question. Runs it right away when it is a git or ticket sheet action (sync, ship, finish a merge, tick a step done by hand); otherwise gives the command to type. Usage: /next"
agent: git
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`
Merge in progress: !`git rev-parse -q --verify MERGE_HEAD`
Fetch: !`git fetch -q origin`
Branch vs its remote copy: !`git status -sb`
Commits behind / ahead of develop: !`git rev-list --left-right --count origin/develop...HEAD`
HEAD: !`git rev-parse --short HEAD`
Uncommitted changes summary: !`git diff HEAD --shortstat`
Uncommitted files: !`git diff HEAD --name-status`
Untracked files: !`git ls-files --others --exclude-standard`
Files changed on the branch: !`git diff --name-status origin/develop...HEAD`
Last change of AGENTS.md: !`git log -1 --format='%h %cs' -- AGENTS.md`
Existing ticket sheets: !`ls .git/opencode/tickets`

Tell me where I am and get me to the next step as fast as possible. No review, no build, no full scan: read only what decides the next step.

The workflow: /daily → /ticket → /dev (one plan step at a time, with its tests) → /test → /check → /ship → /scans → fixes (/fortify-fix, /sonar-fix) → back to /check. /sync brings develop, or what I pushed from my Mac, into the branch.

## Step 1 - Read the state
- Which ticket: the one whose Jira key is in the current branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`). The other sheets listed above are other tickets started in this repository: for each, read only its title line (`# <KEY> - <title>`), the first sentence of its "## Résumé", its "Branche :" line, its count of unchecked plan steps and its last "## Suivi" line. A ticket is "en cours" if its branch still exists (`git branch --list <branch>`) and its last Suivi line is not a /ship with every plan step checked.
- The ticket sheet `.git/opencode/tickets/<KEY>.md` (Jira key from the branch name, pattern `[A-Z][A-Z0-9]+-[0-9]+`) if it is listed: unchecked steps of "Plan", "Tests attendus", "## Décisions", last lines of "## Suivi".
- Changes made outside OpenCode or outside /dev: uncommitted or untracked files that no "/dev étape" line of "Suivi" explains. For each unchecked plan step, decide whether these changes implement it: compare the file names with the step and the "Zones de code concernées"; if unsure, read `git diff HEAD -- <file>` for at most 3 files. Keep the steps that look done by hand.
- Only if the branch was pushed (it has a remote copy): the latest pipeline of the branch and its open merge request, with the GitLab MCP tools (read-only).
- AGENTS.md drift: if "Files changed on the branch" or the uncommitted files add, remove or rename a project (`.csproj`, `.sln`, `.slnx`), change `Directory.*.props`, `package.json` dependencies, `Program.cs` / `Startup.cs` registration, or add a new top-level folder, note which AGENTS.md sections are probably outdated (Solution structure, Build & test, Architecture & conventions, Tests). Do not run /agents-md.

## Step 2 - Decide, first matching rule
1. On `develop`, `master` or `main`: if tickets are "en cours", next = ACTION "Reprendre <KEY>" for the most recent one (alternatives: the other ones, up to 2); otherwise next = "/daily, puis /ticket <KEY>". If there are uncommitted changes, warn that they must not be committed on this branch.
2. A merge is in progress (MERGE_HEAD above is a hash): if the working tree still has conflict lines (`UU`, `AA`, `DU`, `UD`), next = "Résous les conflits dans Rider"; otherwise next = ACTION "Terminer le merge".
3. The branch is "behind" its remote copy (commits pushed from another computer, e.g. Rider on my Mac): next = ACTION "Synchroniser".
4. The branch has a Jira key but no ticket sheet: next = "/ticket <KEY>".
5. Plan steps that look done by hand (step 1): next = ACTION "Cocher l'étape <n> (faite à la main)".
6. Uncommitted changes:
   - unchecked plan steps remain: next = "/dev" (step <n>);
   - no `/test` line in "Suivi" after the last change, or "Tests attendus" rows still "à écrire" or "❌": next = "/test";
   - no `/check` line with the current HEAD and the current uncommitted changes summary, or its verdict is BLOCKING: next = "/check";
   - otherwise: next = ACTION "Livrer (commit + push)".
7. No uncommitted changes but local commits not pushed ("ahead" in the branch status): next = ACTION "Livrer (push)".
8. Pushed: pipeline of the pushed commit running → next = "Attends la fin du pipeline (<link>), puis /scans"; failed or success without a later /scans → next = "/scans".
9. Merge request with unresolved discussions: next = "Réponds aux discussions de la MR <link>". Approved, pipeline green, no discussion left: next = "MR prête à merger <link>".
10. Unchecked plan steps: next = "/dev" (step <n>).
11. Otherwise: next = "/daily pour la suite".

## Step 3 - Answer and act
Write at most 8 lines, in French. First line: "**Ticket <KEY> - <title>**" with the title taken from the first line of the ticket sheet (`# <KEY> - <title>`), or from Jira if there is no sheet, or the branch name if there is no key. Then "Où tu en es" (branch, ticket link, plan <checked>/<total>, tests, last /check, push, pipeline, MR: only what exists), the changes made outside OpenCode if any, one line "Autres tickets en cours : <KEY> - <title> (<branch>), ..." if any, and the AGENTS.md drift line if any: "AGENTS.md probablement à mettre à jour (<sections>) : /agents-md quand le ticket est livré".
Then:
- If the next step or a reasonable alternative is an ACTION, ask me with the question tool: the next step first "(recommandé)", then up to 2 alternatives. An option about a ticket always names it with its title, for example "Reprendre DNA-123 - Export PDF des contrats", and its description says in one line what the ticket is about (first sentence of its "Résumé") and where it stands (for example "étape 3/5, pas encore livré") that make sense now (for example "/check d'abord" before "Livrer", "Cocher l'étape 2" and "/dev étape 3", or "Basculer sur <other KEY>"), and "Rien pour l'instant". Then run the chosen ACTION right away:
  - "Synchroniser": load the skill `sync-procedure` and follow it.
  - "Livrer": load the skill `ship-procedure` and follow it.
  - "Terminer le merge": `git commit --no-edit`, then the branch state.
  - "Reprendre <KEY>" or "Basculer sur <KEY>": if the working tree is not empty, ask me first: "Annuler, je commite d'abord" (recommandé) / "Mettre de côté (stash) et basculer" (`git stash push -u -m "next <current branch>"`); then `git switch <branch of that sheet>`, and go back to step 1 for that ticket, starting your answer with its header line and the first sentence of its "Résumé".
  - "Cocher l'étape <n>": with the edit tool, tick the step in the sheet and append to "## Suivi" `- <date> /next - étape <n> faite à la main` (date with `date "+%Y-%m-%d %H:%M"`); then say that /test will write the missing tests for it.
  A chosen command (/dev, /test, /check, /scans, /ticket, /agents-md) cannot be launched from here: answer with one line "Tape `<command>`".
- Otherwise do not ask: end with "**Prochaine étape : <command>**" and one line "Ensuite : <step after>".
