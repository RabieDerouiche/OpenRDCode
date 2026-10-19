---
description: "Where am I and what next? Reads the branch, the working tree (including changes made outside OpenCode), the ticket sheet (plan, points of the last /check), the pipeline and the merge request (with its review discussions), then proposes the next step in a multiple-choice question and runs it: a git or ticket sheet action right away, a command (/dev, /check...) as soon as this answer ends. Usage: /next"
agent: git
---
Workflow state (one fetch, then the state of the branch, its ticket sheet and the other tickets):
[[run workflow-state.sh --sheet --tickets]]

My todo list, reminders (items overdue or due today):
[[run todo.sh due]]

Tell me where I am and get me to the next step as fast as possible. No review, no build, no full scan: read only what decides the next step. Everything about the tickets is printed above: never read a ticket sheet.

The workflow: /daily → /ticket → /dev (one plan step at a time, with its tests) → /test → /check → /ship → /scans → fixes (/fortify-fix, /sonar-fix) → back to /check; when reviewers comment on the merge request: /mr → /check → /ship. /sync brings develop, or what I pushed from my Mac, into the branch.

## Step 1 - Read the state
- Which ticket: the one whose Jira key is in the current branch name ("Jira key from branch"). The "Ticket sheets summary" lists the tickets started in this repository, most recent first (key, title, branch, branch exists, plan done/total, last Suivi line, then their Jira link and the first sentence of their Résumé). A ticket is "en cours" if its branch exists and its last Suivi line is not a /ship or /scans with the whole plan done.
- The ticket sheet of the current branch, printed above: unchecked steps of "Plan", "Tests attendus", "## Décisions", the unchecked points of the last block of "## Retours /check" (the points of the last /check), last lines of "## Suivi".
- Changes made outside OpenCode or outside /dev: uncommitted or untracked files that no "/dev étape" line of "Suivi" explains. For each unchecked plan step, decide whether these changes implement it: compare the file names with the step and the "Zones de code concernées"; if unsure, read `git diff HEAD -- <file>` for at most 3 files. Keep the steps that look done by hand.
- Only if the branch was pushed (it has a remote copy): the latest pipeline of the branch and its merge request (open or merged), with the GitLab MCP tools (read-only), in one turn together with the `git diff HEAD -- <file>` reads you need. Without a remote copy and without doubt about the changes, make no tool call before step 3.
- AGENTS.md drift: if "Files changed on the branch" or the uncommitted files add, remove or rename a project (`.csproj`, `.sln`, `.slnx`), change `Directory.*.props`, `package.json` dependencies, `Program.cs` / `Startup.cs` registration, or add a new top-level folder, note which AGENTS.md sections are probably outdated (Solution structure, Build & test, Architecture & conventions, Tests). Do not run /agents-md.

## Step 2 - Decide, first matching rule
1. On `develop`, `master` or `main`: if tickets are "en cours", next = ACTION "Reprendre <KEY>" for the most recent one (alternatives: the other ones, up to 2); otherwise next = "/daily". If there are uncommitted changes, warn that they must not be committed on this branch.
2. A merge is in progress ("Merge in progress: yes"): if the workflow state lists conflicted files, next = "Résous les conflits dans Rider" (name them); otherwise next = ACTION "Terminer le merge".
3. The branch is "behind" its remote copy (commits pushed from another computer, e.g. Rider on my Mac): next = ACTION "Synchroniser".
4. The branch has a Jira key but no ticket sheet: next = "/ticket <KEY>".
5. Plan steps that look done by hand (step 1): next = ACTION "Cocher l'étape <n> (faite à la main)".
6. The last `/check` line of "Suivi" has the "Code fingerprint" of the workflow state as `empreinte`, and the last block of "## Retours /check" still has unchecked points: next = "/dev corrections" (« <n> points du dernier /check : <the first ones> »). This comes before anything else of rules 7 and 8: the code was checked and is waiting for these fixes.
7. Uncommitted changes:
   - unchecked plan steps remain: next = "/dev" (step <n>);
   - "Tests attendus" rows still "à écrire" or "❌": next = "/test";
   - no `/check` line in "Suivi" whose `empreinte` is the "Code fingerprint" of the workflow state (the code changed since the last /check, for example its corrections, or it was never checked): next = "/check" (after a previous /check, it reviews only what changed);
   - otherwise: next = ACTION "Livrer (commit + push)". Without a ticket sheet (nothing records a /check), offer "/check" as the first alternative.
8. No uncommitted changes but local commits not pushed ("ahead" in the branch status): the same `/check` test as rule 7 → next = "/check"; otherwise next = ACTION "Livrer (push)".
9. The merge request of the branch is merged: next = "Ticket livré" with the options "/daily (recommandé)" and "Reprendre <other KEY>" for the tickets still "en cours".
10. Pushed: pipeline of the pushed commit running → next = "attends la fin du pipeline [#<pipeline id>](<its web_url>)" and "Ensuite" = "/scans"; failed, or success with no `/scans` line in "Suivi" for the pushed commit → next = "/scans"; a `/scans` line with points still to fix → next = the first fix command written at the end of that line (`/fortify-fix <id>` or `/sonar-fix <clé>`), the other ones as alternatives.
11. Merge request with unresolved discussions: if the last `/mr` line of "Suivi" says "0 corrigées" or is followed by a `/ship` line (its fixes are pushed), next = "Colle les réponses de /mr dans la MR <link> et résous les discussions" (then "/mr" if new comments came in); otherwise next = "/mr" (« <n> discussions ouvertes sur la MR <link> »). Approved, pipeline green, no discussion left: next = "MR prête à merger <link>".
12. Unchecked plan steps: next = "/dev" (step <n>).
13. Otherwise: next = "/daily".

## Step 3 - Answer and act
Write at most 8 lines, in French; the branch state is part of "Où tu en es", no separate block. First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name. Then "Où tu en es" (branch, ticket link, plan <checked>/<total>, tests, last /check, push, pipeline, MR: only what exists; every pipeline and merge request is a markdown link with a short text, `[#<pipeline id>](<web_url>)`, `[!<iid>](<web_url>)`, never a bare URL or a bare id), the changes made outside OpenCode if any, one line "Autres tickets en cours : [<KEY>](<its Jira link>) - <title> (<branch>), ..." if any, one line "Rappels : <the reminders as given>" if my todo list has some, and the AGENTS.md drift line if any: "AGENTS.md probablement à mettre à jour (<sections>) : /agents-md quand le ticket est livré".
Then:
- If the next step is an ACTION or a command, ask me with the question tool (header "Suite"): the next step first "(recommandé)", then up to 2 alternatives that make sense now (for example "/check" before "Livrer", "Cocher l'étape 2" and "/dev 3", or "Basculer sur <other KEY>"), and "Rien pour l'instant". A command option has the command itself as label, with its arguments (`/dev 3`, `/dev corrections`, `/check`, `/scans`, `/mr`, `/ticket ABC-123`) and what it will do as description. An option about a ticket always names it with its title, for example "Reprendre ABC-123 - Export PDF des contrats", and its description says in one line what the ticket is about (first sentence of its "Résumé") and where it stands (for example "étape 3/5, pas encore livré"). Then run the chosen ACTION right away:
  - "Synchroniser": load the skill `sync-procedure` and follow it.
  - "Livrer": load the skill `ship-procedure` and follow it.
  - "Terminer le merge": `git commit --no-edit`, then the branch state.
  - "Reprendre <KEY>" or "Basculer sur <KEY>": if the working tree is not empty, ask me first: "Annuler, je commite d'abord" (recommandé) / "Mettre de côté (stash) et basculer" (`git stash push -u -m "next <current branch>"`); then, in one call, `git switch <branch of that sheet> && sh ~/.config/opencode/scripts/workflow-state.sh --sheet`, and go back to step 1 for that ticket with this new state, starting your answer with its header line and the first sentence of its "Résumé".
  - "Cocher l'étape <n>": one shell call, never the edit tool: `sh ~/.config/opencode/scripts/ticket-sheet.sh tick <n> "/next - étape <n> faite à la main"` (it adds the date and prints the plan); then say that /test will write the missing tests for it.
  - A command (/dev, /test, /check, /scans, /mr, /ticket, /agents-md...): the pack plugin starts it by itself, in this session, as soon as your turn ends. Answer only « Je lance <command>. » and end your turn; never do its work yourself.
- Otherwise (nothing to run now, for example a pipeline still running) do not ask: end with exactly two lines, "**Prochaine étape : <ONE step only, the next one of step 2>**" then "Ensuite : <the step after it>". Never write "puis" in the first line and never name the same step on both lines. Example for a running pipeline:
  **Prochaine étape : attends la fin du pipeline [#9449687](https://gitlab.example.com/group/project/-/pipelines/9449687)**
  Ensuite : /scans
