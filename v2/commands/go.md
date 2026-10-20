---
description: "From a Jira ticket to a Draft merge request, without stopping: analysis, plan, code and tests step by step, full build and tests, self-review and its fixes, commit, push, merge request with its report. Asks only when the ticket is ambiguous, all questions at once. Run it again to resume. Usage: /go [JIRA-KEY] [directives, e.g. « avec un Result, sans nouvelle lib », « pas à pas »]"
agent: pilot
subtask: false
---
Request: « $ARGUMENTS » (an optional Jira key, then the developer's directives)

Workflow state (fetch of every branch, then the state of the branch and its ticket sheet):
[[run workflow-state.sh --fetch-all --sheet]]

Project detection:
[[run detect-project-type.sh]]

Take the ticket from its analysis to its Draft merge request, in this single run. The developer is not watching: follow your autonomy contract.

## 1. Ticket
- The key: the first word of the request when it looks like `ABC-123`; otherwise the key of the current branch ("Jira key from branch" line); otherwise ask, in ONE question tool call (header "Ticket"), among my open tickets of the active sprint (Jira, read-only: `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done ORDER BY Rank ASC`, project of AGENTS.md "Daily" when it is set): up to 4 options `<KEY> - <summary>`, in-progress first, the first one « (recommandé) ».
- Directives: the rest of the request. They reach every subagent prompt.

## 2. Before any work
The "Fetch:" line of the workflow state says AUTH FAILED: stop now (your stop conditions): nothing could be pushed at the end.

## 3. Resume or start
- On the branch of the key with its ticket sheet printed above: resume. Unchecked plan steps → step 5 from the first one. Every step checked and no « /go - livré » line in « ## Suivi » → step 6. Already delivered → say « Déjà livré (MR <link from the sheet>) : /fix pour la CI ou la review » and stop. « refais l'analyse » in the directives → step 4.
- Otherwise: read the ticket summary and type with the Jira tools (one call), then `sh ~/.config/opencode/scripts/branch.sh <KEY> <feature | bugfix for a Bug | hotfix for an urgent production incident> "<ticket summary>"`. A "STOP:" line: stop with it. Then `sh ~/.config/opencode/scripts/workflow-state.sh --no-fetch --sheet`: if the sheet of the key exists, resume as above; otherwise step 4.

## 4. Analysis
One line « Analyse du ticket… », then invoke the `analyst` subagent with the task tool:
"Analyze Jira ticket <KEY> and write its ticket sheet. Repository root: <Repository root line>. Branch: <branch>. Project type: <type from AGENTS.md "Project type" or the detection above>. Now: <Now line>. Developer's directives: <directives or « aucune »>. Follow your procedure and answer in your format."
Then read the sheet (one read). If it does not exist, retry the analyst once; still missing: stop.
- QUESTIONS BLOQUANTES > 0: ask them ALL in ONE question tool call (header "Ticket ambigu" or a short topic), one question per blocking question, its options as given, the recommended one first, plus a last option « Je demande au PO » for business questions. Record each answer: `sh ~/.config/opencode/scripts/ticket-sheet.sh decision "<topic> : <answer> (réponse du dev)"`, all chained with `&&` in one call. « Je demande au PO » on a question: record `- <date> /go - en attente du PO : <question>` with `ticket-sheet.sh suivi`, stop, and say that /go resumes once I have the answer (I give it in the directives: `/go <KEY> <the answer>`).
- Otherwise do not stop: go on.

## 5. Plan steps, one subagent each
For each unchecked step of « ## Plan », in order:
1. One line « Étape <N>/<total> : <step in a few words>… », then invoke the `coder` subagent with the task tool:
   "Implement step <N> of ticket <KEY> in the repository <Repository root>. Step: <full text of the step line>. Acceptance criteria concerned: <the C lines it serves>. Expected tests for this step: <the rows of « Tests attendus » it covers>. Decisions already taken (follow them, never reopen them): <every line of « ## Décisions »>. Developer's directives: <directives or « aucune »>. Project type: <type>. Build and tests: <AGENTS.md "Build & test", otherwise the detection above>. Do only this step, then report in your format."
2. RÉSULTAT OK: in one call, `sh ~/.config/opencode/scripts/ship.sh --no-push "<type>(<scope>): <the step in English, imperative> (<KEY>)" "<one line per file group>"` then `&& sh ~/.config/opencode/scripts/ticket-sheet.sh tick <N> "/go étape <N> - <files count> fichiers - <Build and Tests of the report, short>"`, followed by `&& sh ~/.config/opencode/scripts/ticket-sheet.sh decision "<topic> : <choice> — <reason> (étape <N>)"` for each decision of the report. Commit types: feat, fix, refactor, test, chore, docs, perf; never backticks, `$` or double quotes inside the texts.
3. RÉSULTAT ÉCHEC: invoke the `debugger` subagent: "Find the root cause of this failure in the repository <root>, for step <N> of ticket <KEY>: <the Problème line and the failing BUILD/TESTS lines of the coder>. Files of the step: <list>. Do not ask me anything: if the cause is not certain, give your best hypothesis with its evidence." Then invoke the `coder` again with the same prompt plus « Diagnostic du debugger : <its root cause and proposed fix>. Previous attempt: <what failed>. » Still ÉCHEC, or BLOQUÉ at any time: record `ticket-sheet.sh suivi "/go - bloqué à l'étape <N> : <reason>"`, commit what builds with `ship.sh --no-push` only if the last report says the build is OK, and stop with your report.
4. « pas à pas » in the directives: stop after this step with its report (the next /go continues).

## 6. Verification of the whole branch
1. One line « Build et tests complets… », then the full suite in one call: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" and the options of its full test suite (front-end: the commands of AGENTS.md). A failure: one `coder` round with the failing lines (prompt: "Fix these build or test failures of the branch of ticket <KEY>, without changing the expected behavior: <lines>…"), commit it with `ship.sh --no-push`, run the suite again; still failing: stop as in step 5.3.
2. One line « Auto-review… », then invoke the `checker` subagent: "Self-review of the branch of ticket <KEY> in the repository <root>, before it is pushed. Diff: `git diff <Base branch line>...HEAD` (everything is committed). Ticket sheet: <path> (acceptance criteria, decisions). Project type: <type>. Use your output for a self-review."
3. Points « bloquant » or « majeur », and criteria « non trouvé » or « non testé »: one `coder` round with all of them ("Fix these review findings of the branch of ticket <KEY>: <the numbered points and criteria>. Decisions already taken: <…>. Report in your format."), commit (`ship.sh --no-push "fix(<scope>): address the self-review findings (<KEY>)"`), then the full suite again. At most 2 rounds in all; what remains goes to « Points d'attention » of the merge request. « mineur » and « question » points are not fixed: they go to the merge request.

## 7. Delivery
1. One line « Mise à jour avec develop… », then `sh ~/.config/opencode/scripts/ship.sh --sync-only --base`: it brings, by merge, the commits pushed on the branch from another computer and the new commits of develop. A "STOP:" line: stop with it (a conflict is resolved by the developer, then /fix).
2. « REMOTE: » or « BASE: » says something was merged: the full suite again, as in step 6.1, before anything is pushed.
3. One line « Push et merge request… », then `sh ~/.config/opencode/scripts/ship.sh "<type>(<scope>): <ticket summary in English> (<KEY>)"` (it commits what remains and pushes). A "STOP:" line: stop with it.
4. The merge request, as your rules say: find it, or create it as Draft with its description; otherwise give the MR LINK and the description to paste.
5. `sh ~/.config/opencode/scripts/ticket-sheet.sh suivi "/go - livré - MR <link> - build ok - tests <passed>/<total> - auto-review <verdict>"`.

## Answer, in French
- Header line, then « 🚀 MR en Draft : <link> » (or « MR à créer : <link> »).
- « Étapes » table: | # | Étape | Fichiers | Tests | ✅ |.
- « Décisions prises (à valider en review) »: one line each, with its reason; the developer's answers first.
- « Vérifications »: build, tests passed/total, auto-review verdict and what was fixed, security pre-scan.
- « Points d'attention » when there are some (minor findings, questions of the review, what is left).
- Last line: « La CI tourne (Sonar, Fortify). Ensuite : /fix quand elle est terminée, ou après les retours de review. »
