---
description: "After the CI or the review: gathers in one pass the failed jobs of the pipeline, the Sonar and Fortify findings in the files of the branch and the open discussions of the merge request, fixes what is clear, tests, commits and pushes, and writes the replies to paste. Without stopping. Also brings the commits pushed from another computer and the new commits of develop. Usage: /fix [directives, e.g. « seulement la review »]"
agent: pilot
subtask: false
---
Directives: « $ARGUMENTS »

Workflow state (one fetch, then the state of the branch, its ticket sheet and the Fortify SSC application line):
[[run workflow-state.sh --sheet --appsec]]

Project detection:
[[run detect-project-type.sh]]

Bring the branch to a green, review-ready state in this single run. The developer is not watching: follow your autonomy contract. Read-only on GitLab (except the Draft merge request if none exists yet), Jira, Sonar and Fortify: never comment, resolve, change a status or mark a false positive.

## 1. Before any work
- On develop, master or main: say « /fix travaille sur la branche d'un ticket : /go <KEY> pour en démarrer un » and stop.
- "Fetch:" AUTH FAILED: stop (your stop conditions).
- "Upstream: none": nothing was pushed, so there is no CI and no merge request yet: say « Rien de poussé : /go <KEY> livre d'abord la branche » and stop.
- The branch is behind its remote copy, or the base branch has new commits: `sh ~/.config/opencode/scripts/ship.sh --sync-only --base`. A conflict: stop with its line. Local changes that block the merge: go on, they are merged at the end (step 6).

## 2. Gather, in two turns
Speed: every call of a turn is sent together. Pages of 20 results at most, with the tools' filters on status and severity: a bigger answer is cut by OpenCode and saved to a file that you never search.
- Turn 1: with the GitLab tools, the project from the "Remote URL" line (its path after the host, without `.git`), the open merge request of this branch, and the latest pipeline of the pushed commit ("Pushed commit" line) with its jobs; the Sonar project of this repository (search by repository name or by the SSC application name); the versions of the SSC application (the value after `=` of the "Fortify SSC application" line; never read appsec-ci.env yourself); the skill `fortify-remediation`.
- Turn 2: the unresolved discussions of the merge request (author, text, file and line, replies); the last 50 lines of the log of every failed job; the open Sonar issues and the security hotspots of this branch (severities BLOCKER, CRITICAL and MAJOR first, then the others while there is room); the Fortify issues of the selected version with the filter set "Security Auditor View" (Critical and High first). Fortify version: the exact branch name, then with `/` replaced by `-`, then by `_`, if it has an uploaded scan; otherwise `develop`. Never invent a project, version or filter name: a name rejected → list the valid ones and retry once.
- Scan jobs (name containing `sonar` or `fortify`) still running or pending: their results are not in yet; note « ⏳ <Sonar | Fortify> en cours » and go on with the rest. A scan whose last analysis is older than the pushed commit: its results are old, say so.
- A system that does not answer: one line, and go on with the others.

## 3. Sort, without asking
Build one list, each item with its source (🧪 CI, 📊 Sonar, 🏰 Fortify, 💬 review):
- **À corriger**: a failed build, test or lint job (from its log); a Sonar or Fortify finding in a file of the "Files changed on the branch" list (🔴 🟠 always, 🟡 🔵 when the fix is local and safe); a hotspot on those files that is a real problem; a review discussion that asks a clear and right change.
- **À répondre**: a discussion that asks a question, asks something already done (say where), or contradicts AGENTS.md, an acceptance criterion or a « ## Décisions » line of the sheet (an argued reply with its evidence, never applied silently); a finding judged a false positive (its reason, from the skill).
- **Hors périmètre**: findings in files the branch does not change (listed, not fixed: another ticket).
The developer's directives narrow the list (« seulement la review », « pas Sonar »…). Nothing at all to fix or answer and no scan running: with local changes (uncommitted files, or commits not pushed yet: the documentation of /outil doc, an AGENTS.md of /outil setup, work done in Rider on this machine), go to step 6 to deliver them; otherwise say « Rien à corriger : pipeline <status>, aucun point Sonar ni Fortify sur la branche, aucune discussion ouverte » with the merge request link, and stop.

## 4. Fix
In groups of 15 items at most, grouped by file, one `coder` subagent per group, a line « Corrections : <n> points… » before each:
"Fix these items of the branch of ticket <KEY> in the repository <Repository root>, with the smallest change for each and a test when the behavior changes: <numbered items: source, file:line, problem, expected fix; for a CI failure its error lines; for a Sonar or Fortify finding its rule or category and the fix of the skill fortify-remediation>. Decisions already taken (never reopen them): <« ## Décisions » lines>. Directives: <…>. Project type: <type>. Build and tests: <AGENTS.md "Build & test">. Report in your format, with one line per item: corrigé, ou non corrigé et pourquoi."
After each report: `sh ~/.config/opencode/scripts/ship.sh --no-push "fix(<scope>): <what this group fixes, in English> (<KEY>)"`, then `&& sh ~/.config/opencode/scripts/ticket-sheet.sh decision "<topic> : <choice> — <reason> (/fix)"` for each decision of the report. ÉCHEC: the `debugger` then the `coder` once more, as /go does; still failing: stop with the report.

## 5. Verify
When something was fixed: the full suite in one call (`sh ~/.config/opencode/scripts/build-test.sh` with the solution or project and the options of AGENTS.md "Build & test"); a failure: one `coder` round with the failing lines, then the suite again; still failing: stop. More than 30 lines changed by the fixes: the `checker` subagent on `git diff <Pushed commit line>..HEAD`; its « bloquant » and « majeur » points: one `coder` round.

## 6. Deliver
1. `sh ~/.config/opencode/scripts/ship.sh --base "fix(<scope>): address the CI, scan and review feedback (<KEY>)"` (it also commits the local changes made by the developer on this machine). A "STOP:" line: stop with it.
2. No open merge request (it was closed or never created): create it as Draft, as your rules say.
3. `sh ~/.config/opencode/scripts/ticket-sheet.sh suivi "/fix - <n> corrigés, <n> réponses, <n> hors périmètre - build ok - tests <passed>/<total>"`.

## Answer, in French
- Header line, then « 🔁 MR : <link> » and the pipeline that the push started.
- « Corrigé » table: | | Point | Où | Commit |, the first column the source emoji, then the severity emoji for a finding (🔴 🟠 🟡 🔵); the place as `<file name>:<line>`.
- « Réponses à coller dans GitLab »: per discussion, `**<file>:<line>** (<author>)` then the reply in French, 1 to 3 sentences, factual and courteous: what changed (it is in this push), where it is already done, the answer to the question, or the argument with its evidence and an alternative. Then the rules of the team stated in these discussions that AGENTS.md lacks, if any: « Règle à ajouter à AGENTS.md : <rule> » (not added: the developer decides).
- « Hors périmètre » and « Faux positifs probables », one line each, when there are some.
- « En attente »: the scans still running. Last line: « Relance /fix quand la CI de ce push est terminée. » when a scan was running or this run pushed fixes; otherwise « Plus rien à corriger de ton côté : la MR attend la review. »
