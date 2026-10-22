---
description: "Fortify par lot : les 4-5 vulnérabilités les plus graves de l'application SSC du dépôt, chacune analysée par son sous-agent, ses tests gardés par le test-guardian (couverture coverlet du module et de ses dépendances avant et après, tests de contexte verts, tests de la faille rouges puis verts), corrigée par le coder, un commit par vulnérabilité, puis une MR Draft. Reprend où il s'est arrêté. Usage: /fortify [nombre, 5 au plus] [catégorie, fichier ou ticket ABC-123] [directives]"
agent: pilot
subtask: false
---
[[command fortify $ARGUMENTS]]
Request: « $ARGUMENTS » (an optional count, 5 at most; an optional Fortify category, file name or Jira key; the developer's directives)

Workflow state (fetch of every branch, then the state of the branch, its ticket sheet and the Fortify SSC application line):
[[run workflow-state.sh --fetch-all --sheet --appsec]]

Prerequisites of /fortify (dotnet, unit test projects with coverlet.collector, the SSC application):
[[run fortify.sh prereq]]

Fix a batch of Fortify vulnerabilities, from the scan to a Draft merge request, in this single run. The developer is not watching: follow your autonomy contract. Read-only on Fortify, Sonar, Jira and GitLab (except the Draft merge request): never change, suppress, audit or comment a Fortify issue. You orchestrate: the subagents do the analysis, the tests and the fixes, each for ONE vulnerability with a fresh context; the vulnerability cards on disk carry what one subagent tells the next. Batch folder: `<git folder>/opencode-tickets/<KEY>.fortify/` (cards `V<n>.md`, coverage, logs); never commit it.

## 1. Before any work
- A "STOP:" line of the prerequisites: stop with it, and with « Prérequis de /fortify : COMMANDES.md, section « Fortify ». »
- "Fetch:" AUTH FAILED, or "Merge in progress: yes": stop as /go does.
- On a branch whose ticket sheet has the line « - Lot Fortify »: RESUME (step 5 from the first unchecked step; its card says which phases are done). Uncommitted files at resume belong to the interrupted vulnerability: `sh ~/.config/opencode/scripts/fortify.sh discard V<n>-interrupted` (nothing of a vulnerability is committed before its last phase), record `- reprise : travail interrompu mis de côté` in its card, then that vulnerability again from phase 1. Record `ticket-sheet.sh suivi "/fortify - reprise : V<n>"`.
- Otherwise on another branch than the base, or with uncommitted files: stop with « ⛔ /fortify démarre depuis develop, sans fichier non commité. »

## 2. Select the batch (you, Fortify tools, read-only)
1. Application: the value after `=` of the "Fortify SSC application" line. Version: `develop` (otherwise the base branch, `/` replaced by `-`); no uploaded scan: say it and stop. Never invent a project, version or filter name: a name rejected → list the valid ones and retry once.
2. Issues of that version, filter set "Security Auditor View", Critical then High, 20 per page, 2 pages at most.
3. Keep up to the count of the request (5 when none, never more): in a file of this repository (not generated code, migrations or test projects), not in an open « Lot Fortify » sheet of the "Existing ticket sheets" (unless the request names it again), within the category or file of the request when one is given. Prefer the same category, then the same file: one kind of fix per merge request.
4. Nothing kept: « ✅ Aucune vulnérabilité Critical ou High à corriger dans <application> / <version> » and stop.

## 3. Branch and batch sheet
1. ONE shell call: `sh ~/.config/opencode/scripts/branch.sh <Jira key of the request, or LOCAL> bugfix "Fortify <first category> lot <date>" && sh ~/.config/opencode/scripts/workflow-state.sh --no-fetch --sheet && sh ~/.config/opencode/scripts/fortify.sh batch`. A "STOP:" line: stop with it. Without a Jira key, the "KEY:" line gives the key. The "BATCH:" line is the batch folder (on resume: `fortify.sh batch` alone gives it again).
2. Write the ticket sheet yourself, at the path of the "Current ticket sheet" line: `# Lot Fortify <application> / <version>`, the line `- Lot Fortify : <application> / <version> - <date>`, `## Plan` with one line per vulnerability `- [ ] <n>. V<n> : <category> - <file>:<line> - Fortify <issue id> - <severity>` (the number is the one `ticket-sheet.sh tick` uses), and empty `## Décisions` and `## Suivi` sections.

## 4. Analysis, one `analyst` subagent per vulnerability, one after the other
For each V<n>, the `analyst` with the subagent tool: "Analyze ONE Fortify vulnerability and write its card. Card to write: <batch folder>/V<n>.md. Repository root: <root>. Project type: <type>. Vulnerability: <issue id, category, severity, file:line, source and sink, the Fortify details and trace as the Fortify tools give them>. The card, in French: « ## Faille » (what is exploitable, from where to where, the lines of the vulnerable method), « ## Verdict » (vraie faille, or « faux positif probable » with the evidence), « ## Correction » (the smallest fix, from the skill fortify-remediation), « ## Contexte » (the module: the class, its public methods on the path, its injected dependencies on the path, what AGENTS.md and the docs say of this behavior), « ## Tests » (the unit test project of this code, its existing test classes for the module, and the hostile input and the safe behavior a vulnerability test must assert; « non démontrable par un test unitaire : <reason> » when it is configuration or a framework setting), « ## État » empty. This is not a Jira ticket: skip the Jira steps of your procedure, write no ticket sheet, only this card, with exactly these sections. Read in narrow ranges. Answer with one line: « CARTE : <path> - <vraie faille | faux positif probable> - projet de tests <path> »."
No card, or a card without « ## Tests »: retry once; still none: tick V<n> « non traitée : analyse impossible » and go on. « faux positif probable »: tick V<n> « non traitée : faux positif probable — à déclarer dans SSC par toi » and go on.

## 5. One vulnerability at a time, through four phases recorded in its card (« ## État » lines, written by you)
A line « Vulnérabilité <N>/<total> : <category> dans <file>… » first.
1. **Tests before the fix**: the `test-guardian`: "Phase « avant le correctif ». Card: <path>. Repository root: <root>. Test project: <from the card>. Coverage label: V<n>. Tests that already fail on develop (never yours): <names or « aucun »>." Its report OK, with « RED » or « non démontrable »: record `- tests : <RED | non démontrable> - contexte <added n | déjà couvert> - couverture avant <files a/b>` in the card.
2. **Fix**: the `coder`: "Fix vulnerability V<n> of the batch <KEY> in <root>, with the smallest change of the card « ## Correction » (card: <path>). Never change a test of the module, never a project file or a package. Then run `sh ~/.config/opencode/scripts/fortify.sh green <test project> FullyQualifiedName~Security_<Category>_V<n>` and the build. Report in your format."
3. **Tests after the fix**: the SAME test-guardian session (its `sessionID`) with « Phase « après le correctif ». » Its report OK: record `- correctif : GREEN - couverture après <files a/b> - perte aucune` in the card.
4. **Commit**: ONE shell call: `sh ~/.config/opencode/scripts/ship.sh --no-push "fix(security): <category in English> in <file name> (V<n>, <KEY>)" "- Fortify <issue id>" "- tests: <n> context, <n> vulnerability (red before, green after)"` then `&& sh ~/.config/opencode/scripts/ticket-sheet.sh tick <N> "/fortify V<n> - corrigée - tests <n>+<n> - couverture sans perte"`. The fix and its tests together: one commit per vulnerability.
Failures, never more than these rounds, a vulnerability never blocks the batch:
- A phase ÉCHEC, a report without its RÉSULTAT line, or a subagent error: the `debugger` with the failure, then the SAME subagent session with its diagnosis. For the test-guardian, « RED » not reached (its tests pass on the current code): the same session once with « Tes tests passent sur le code actuel : ils ne montrent pas la faille. Reprends l'entrée hostile de la carte. »
- Still failing, or BLOQUÉ: `sh ~/.config/opencode/scripts/fortify.sh discard V<n>` (the work is kept in git stash, recoverable), record `- abandon : <phase> - <reason>` in the card, tick V<n> « non corrigée : <reason> », next vulnerability.
- The coder changed a test or the after-phase reports a lost coverage: one coder round with the test-guardian's lines, then phase 3 again; still failing: abandon as above.
- `fortify.sh discard` says STOP, or files remain after it: stop the batch with your report (nothing pushed).

## 6. Verify and deliver
1. Nothing corrected: nothing is pushed; answer with the reason of each vulnerability.
2. As /go steps 6 and 7: the full suite once (`build-test.sh`), the `checker` on the diff of the batch (its blocking points: one coder round, then phase 3 of the vulnerabilities it touched), then `ship.sh --base`, the Draft merge request « Fortify : <n> vulnérabilités <category> (<KEY>) », `ticket-sheet.sh suivi "/fortify - livré - MR !<iid>"`.

## Answer, in French, and the merge request description
- « 🔒 Lot Fortify <application> / <version> » and the merge request link.
- Table: | V | Fortify | Gravité | Fichier | Correction | Contexte | Test de la faille | Couverture module + dépendances | Commit |. « Contexte »: « déjà couvert » or « <n> tests ajoutés ». « Test de la faille »: « rouge avant, vert après » or « non démontrable : <reason> ». « Couverture »: before → after per file, from the card.
- « Non corrigées » and « Non traitées », one line each with the reason (they come back in the next batch only once the reason is solved); « Hors périmètre » (methods of the dependencies not tested), from the reports.
- « À vérifier après le merge : le scan Fortify de la CI doit les marquer corrigées ; un faux positif se déclare dans SSC par toi, jamais par moi. » Work put aside: « git stash list » shows it. Last line: « /fortify pour le lot suivant, une fois cette MR mergée. »
