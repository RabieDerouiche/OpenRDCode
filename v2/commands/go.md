---
description: "From a Jira ticket to a Draft merge request, without stopping: analysis and a measure of develop in parallel, plan, code and tests step by step, full build and tests, self-review and its fixes, a check of the changes before the push, commit, push, merge request with its report. Asks only when the ticket is ambiguous, all questions at once. Run it again to resume. Usage: /go [JIRA-KEY] [directives, e.g. « avec un Result, sans nouvelle lib », « comme le pattern export-csv », « comme dans ~/repos/old-api », « analyse seule », « pas à pas »]"
agent: pilot
subtask: false
---
Request: « $ARGUMENTS » (an optional Jira key, then the developer's directives)

Workflow state (fetch of every branch, then the state of the branch and its ticket sheet):
[[run workflow-state.sh --fetch-all --sheet]]

Project detection:
[[run detect-project-type.sh]]

Take the ticket from its analysis to its Draft merge request, in this single run. The developer is not watching: follow your autonomy contract.

## 1. Ticket and directives
- The key: the first word of the request when it looks like `ABC-123`; otherwise the key of the current branch ("Jira key from branch" line); otherwise ask, in ONE question tool call (header "Ticket"), among my open tickets of the active sprint (Jira, read-only: `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done ORDER BY Rank ASC`, project of AGENTS.md "Daily" when it is set): up to 4 options `<KEY> - <summary>`, in-progress first, the first one « (recommandé) ».
- Directives: the rest of the request. They reach every subagent prompt. Recognize:
  - « comme le pattern <name> »: a pattern skill of the team, given to the analyst.
  - « comme dans <folder> » (a path, or the alias of a reference of opencode.json): a reference implementation in another repository. A path that is not a configured reference: your first tool call, ALONE in its turn, is one `glob` with pattern `*` on that folder, after the line « Lecture de <folder> : réponds « Toujours » à la demande d'accès (une fois pour toute la session OpenCode). » Refused or not found: go on without it and say so in the final answer.
  - « analyse seule »: stop after step 4 (the developer reviews the plan; the next /go codes it).
  - « pas à pas »: stop after each plan step.
  - « refais l'analyse »: step 4 again on an existing sheet (its decisions and its log are kept).

## 2. Before any work
- "Fetch:" says AUTH FAILED: stop (your stop conditions): nothing could be pushed at the end.
- "Merge in progress: yes": stop with « ⛔ Une fusion est en cours sur la branche : termine-la dans Rider (ou git merge --abort), puis relance /go. »

## 3. Resume or start
- On the branch of the key with its ticket sheet printed above: resume, and record it first: `sh ~/.config/opencode/scripts/ticket-sheet.sh suivi "/go - reprise à l'étape <N>"` (or « reprise : vérification », « reprise : livraison »). Unchecked plan steps → step 5 from the first one. Every step checked and no « /go - livré » line in « ## Suivi » → step 6. Already delivered → answer « ✅ Déjà livré (MR <link from the sheet>) : /fix pour la CI ou la review » and stop. « refais l'analyse » → step 4.
- Files listed under "Uncommitted files" when you resume: an interrupted attempt left them. They go to the prompt of the next coder (step 5.1).
- Otherwise, start: read the ticket summary and type with the Jira tools (one call), then in ONE shell call: `sh ~/.config/opencode/scripts/branch.sh <KEY> <feature | bugfix for a Bug | hotfix for an urgent production incident> "<ticket summary>" && sh ~/.config/opencode/scripts/workflow-state.sh --no-fetch --sheet`. A "STOP:" line: stop with it. The sheet of the key exists: resume as above; otherwise step 4.

## 4. Analysis, with a measure of develop in parallel
One line « Analyse du ticket, et build + tests de develop en parallèle… », then in ONE turn, both together:
- the `analyst` subagent with the task tool: "Analyze Jira ticket <KEY> and write its ticket sheet. Repository root: <Repository root line>. Branch: <branch>. Project type: <type from AGENTS.md "Project type" or the detection above>. Now: <Now line>. Developer's directives: <directives or « aucune »>. Pattern named by the developer: <name or « aucun »>. Reference repository named by the developer: <absolute folder, or « aucun »>. Follow your procedure and answer in your format."
- the full suite of the base, the measure of develop: `sh ~/.config/opencode/scripts/build-test.sh` with the solution or project and the options of AGENTS.md "Build & test" (front-end: its test command). Not when the project is legacy .NET Framework (it does not build here), not on « refais l'analyse » when the branch already has commits ahead of the base.

Then:
1. The measure: "ENVIRONMENT PROBLEM": stop (your stop conditions). "BUILD: FAILED": stop with « ⛔ develop ne compile pas sur cette machine : <first error line> ». Otherwise record it: `sh ~/.config/opencode/scripts/ticket-sheet.sh suivi "/go - base develop : build ok - tests <passed>/<total> - en échec avant le ticket : <the names of the FAILED TESTS line, or aucun>"`. These tests already fail without the ticket: never yours to fix, listed in the merge request.
2. The sheet, in ONE turn: `sh ~/.config/opencode/scripts/ticket-sheet.sh check` and the read of the sheet (its path is the FICHE line of the analyst). No sheet: retry the analyst once; still none: stop. "problem(s)": one more `analyst` round ("Fix these problems of the ticket sheet <path>, and only them: <the problem lines>."), then check again; still problems: go on if the plan has numbered steps, otherwise stop.
3. QUESTIONS BLOQUANTES > 0: ask them ALL in ONE question tool call (header "Ticket ambigu" or a short topic), one question per blocking question, its options as given, the recommended one first, plus a last option « Je demande au PO » for business questions. Record each answer: `sh ~/.config/opencode/scripts/ticket-sheet.sh decision "<topic> : <answer> (réponse du dev)"`, all chained with `&&` in one call. « Je demande au PO » on a question: record `/go - en attente du PO : <question>` with `ticket-sheet.sh suivi`, stop, and say that /go resumes once I have the answer (I give it in the directives: `/go <KEY> <the answer>`).
4. « analyse seule »: answer « ✅ Analyse prête : <N> étapes », the plan as a numbered list, the decisions, and « Relis la fiche `.git/opencode-tickets/<KEY>.md` (corrige-la si besoin), puis /go <KEY> pour coder. » Stop.

## 5. Plan steps, one subagent each
For each unchecked step of « ## Plan », in order:
1. One line « Étape <N>/<total> : <step in a few words>… », then invoke the `coder` subagent with the task tool:
   "Implement step <N> of ticket <KEY> in the repository <Repository root>. Step: <full text of the step line>. Acceptance criteria concerned: <the C lines it serves>. Expected tests for this step: <the rows of « Tests attendus » it covers>. Decisions already taken (follow them, never reopen them): <every line of « ## Décisions »>. To follow: <the pattern skill the step names (pattern-skills.sh gives its file), and/or « the « ## Référence » section of the ticket sheet <path> and the reference files it lists, read-only », or « rien »>. Files already modified before you started (an interrupted attempt; keep what serves this step): <list, or « aucun »>. Tests that already fail on develop (not yours, never touch them): <names from the base line, or « aucun »>. Developer's directives: <directives or « aucune »>. Project type: <type>. Build and tests: <AGENTS.md "Build & test", otherwise the detection above>. Do only this step, then report in your format."
2. RÉSULTAT OK: in ONE shell call, `sh ~/.config/opencode/scripts/ship.sh --no-push "<type>(<scope>): <the step in English, imperative> (<KEY>)" "<one line per file group>"` then `&& sh ~/.config/opencode/scripts/ticket-sheet.sh tick <N> "/go étape <N> - <files count> fichiers - <Build and Tests of the report, short>"`, followed by `&& sh ~/.config/opencode/scripts/ticket-sheet.sh decision "<topic> : <choice> — <reason> (étape <N>)"` for each decision of the report. Commit types: feat, fix, refactor, test, chore, docs, perf; never backticks, `$` or double quotes inside the texts.
3. RÉSULTAT ÉCHEC, a report without its RÉSULTAT line (the coder reached its step limit), or a task error (« Subagent failed (task_id: …) »): invoke the `debugger` subagent: "Find the root cause of this failure in the repository <root>, for step <N> of ticket <KEY>: <the Problème line and the failing BUILD/TESTS lines of the coder, or the error>. Files of the step: <list>. Nobody answers questions during your work: if the cause is not certain, give your best hypothesis with its evidence." Then the SAME coder session again: the task tool with the `task_id` of its report (the id of the `<task id=…>` line) and the prompt « Diagnostic du debugger : <its root cause and proposed fix>. Corrige l'étape <N> en conséquence, puis rapporte dans ton format. » (it keeps what it already read). Still ÉCHEC, or BLOQUÉ at any time: record `ticket-sheet.sh suivi "/go - bloqué à l'étape <N> : <reason>"`, commit what builds with `ship.sh --no-push` only if the last report says the build is OK, and stop with your report.
4. « pas à pas »: stop after this step: « ✅ Étape <N>/<total> faite (pas à pas) » and its report; the next /go continues.

## 6. Verification of the whole branch
1. One line « Build et tests complets… », then the full suite in one call: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" and the options of its full test suite (front-end: the commands of AGENTS.md). Failed tests listed in the base line of « ## Suivi » are not the ticket's: they are not fixed, they go to the merge request. Any other failure: one `coder` round with the failing lines (prompt: "Fix these build or test failures of the branch of ticket <KEY>, without changing the expected behavior: <lines>. Tests that already fail on develop (not yours, never touch them): <names>…"), commit it with `ship.sh --no-push`, run the suite again; a new failure still there: stop as in step 5.3.
2. One line « Auto-review… », then invoke the `checker` subagent: "Self-review of the branch of ticket <KEY> in the repository <root>, before it is pushed. Diff: `git diff <Base branch line>...HEAD` (everything is committed). Ticket sheet: <path> (acceptance criteria, decisions). Project type: <type>. The full build and tests passed just before (<BUILD and TESTS lines>): never run them again. Use your output for a self-review."
3. Points « bloquant » or « majeur », and criteria « non trouvé » or « non testé »: one `coder` round with all of them ("Fix these review findings of the branch of ticket <KEY>: <the numbered points and criteria>. Decisions already taken: <…>. Report in your format."), commit (`ship.sh --no-push "fix(<scope>): address the self-review findings (<KEY>)"`), then the full suite again. At most 2 rounds in all; what remains goes to « Points d'attention » of the merge request. « mineur » and « question » points are not fixed: they go to the merge request.

## 7. Delivery
1. One line « Mise à jour avec develop… », then `sh ~/.config/opencode/scripts/ship.sh --sync-only --base`: it brings, by merge, the commits pushed on the branch from another computer and the new commits of develop. A "STOP:" line: stop with it (a conflict is resolved by the developer in Rider, then /go delivers).
2. « REMOTE: » or « BASE: » says something was merged: the full suite again, as in step 6.1, before anything is pushed.
3. One line « Contrôle et push… », then `sh ~/.config/opencode/scripts/ship.sh "<type>(<scope>): <ticket summary in English> (<KEY>)"`: it commits what remains, checks the changes (GUARD lines), then pushes. "GUARD: STOP": stop with « ⛔ Contrôle avant push : rien n'a été poussé » and its lines, and « COMMANDES.md, section « Contrôle avant push » ». Another "STOP:" line: stop with it. Keep the WARNING and PACKAGES lines: they go to the merge request.
4. The merge request, as your rules say: find it, or create it as Draft with its description; otherwise give the MR LINK and the description to paste.
5. `sh ~/.config/opencode/scripts/ticket-sheet.sh suivi "/go - livré - MR <link> - build ok - tests <passed>/<total> - auto-review <verdict>"`.

## Answer, in French
- Header line, then « 🚀 MR en Draft : <link> » (or « 🚀 MR à créer : <link> »).
- « Étapes » table: | # | Étape | Fichiers | Tests | ✅ |.
- « Décisions prises (à valider en review) »: one line each, with its reason; the developer's answers first.
- « Vérifications »: base develop (tests already failing before the ticket, if any), build, tests passed/total, auto-review verdict and what was fixed, security pre-scan, the check before the push.
- « Points d'attention » when there are some (minor findings, questions of the review, packages added, warnings of the check, what is left).
- Last line: « La CI tourne (Sonar, Fortify). Ensuite : /fix quand elle est terminée, ou après les retours de review. »
