---
description: "Fortify par lot : prend les 4-5 vulnérabilités les plus graves de l'application SSC du dépôt, vérifie que leur contexte est couvert par des tests unitaires (sinon les ajoute), ajoute un test qui montre chaque vulnérabilité, la corrige, puis pousse le lot et ouvre une MR Draft. Sans s'arrêter, une vulnérabilité par sous-agent. Usage: /fortify [nombre, 5 au plus] [catégorie, fichier ou ticket ABC-123] [directives]"
agent: pilot
subtask: false
---
Request: « $ARGUMENTS » (an optional count, 5 at most; an optional Fortify category, file name or Jira key; the developer's directives)

Workflow state (fetch of every branch, then the state of the branch, its ticket sheet and the Fortify SSC application line):
[[run workflow-state.sh --fetch-all --sheet --appsec]]

Project detection:
[[run detect-project-type.sh]]

Fix a batch of Fortify vulnerabilities, from the scan to a Draft merge request, in this single run. The developer is not watching: follow your autonomy contract. Read-only on Fortify, Sonar, Jira and GitLab (except the Draft merge request): never change an issue status, never suppress, audit or comment an issue.

## 1. Resume or start
- On a branch whose ticket sheet has the line « - Lot Fortify » with unchecked steps: resume it, like /go step 3 (`ticket-sheet.sh suivi "/fortify - reprise à l'étape <N>"`), then step 4 of this command.
- "Fetch:" AUTH FAILED, "Merge in progress: yes", or uncommitted files on another branch than the base: stop as /go does.
- No "Fortify SSC application" line (`none`): stop with « ⛔ Pas de ligne APPSEC_PROJECT_NAME dans appsec-ci.env : je ne sais pas quelle application SSC lire. »

## 2. Select the batch (you, with the Fortify tools, read-only)
1. The application: the value after `=` of the "Fortify SSC application" line. The version: `develop` (otherwise the base branch of the "Base branch" line, with `/` replaced by `-`); a version without an uploaded scan: say it and stop.
2. The issues of that version with the filter set "Security Auditor View", Critical first then High, 20 per page at most, never more than 2 pages. Never invent a project, version or filter name: a name rejected → list the valid ones and retry once.
3. Keep, in this order, up to the count of the request (5 when none, never more than 5): issues in a file of this repository (not in generated code, migrations or test projects), not already in an open « Lot Fortify » sheet (the "Existing ticket sheets" lines), and within the category or file of the request when one is given. Prefer issues of the same category, then of the same file: one kind of fix per batch is the easiest to review.
4. Nothing to keep: answer « ✅ Aucune vulnérabilité Critical ou High à corriger dans <application> / <version> » and stop.

## 3. Branch and analysis
1. In ONE shell call: `sh ~/.config/opencode/scripts/branch.sh <the Jira key of the request, or LOCAL> bugfix "Fortify <first category> lot <date>" && sh ~/.config/opencode/scripts/workflow-state.sh --no-fetch --sheet`. A "STOP:" line: stop with it. Without a Jira key, the "KEY:" line gives the key.
2. The `analyst` subagent with the subagent tool: "Analyze this batch of Fortify vulnerabilities and write its ticket sheet. Ticket sheet to write: <path of the "Current ticket sheet" line>. Repository root: <root>. Key: <KEY>. Project type: <type>. Add the line « - Lot Fortify : <application> / <version> » under the title. Vulnerabilities, one plan step each, in this order: <for each: Fortify issue id, category, severity, file:line, source and sink as Fortify gives them>. For each step, from the skill fortify-remediation and the code: the fix in one sentence; « Contexte couvert » with the existing unit tests that run this code (their test names, found by searching the test projects for the class and the method), or « non couvert »; the tests to add: characterization tests of the current behavior when the context is not covered, and one security test that shows the vulnerability (it fails before the fix and passes after it), or « non démontrable par un test unitaire : <reason> » (configuration, framework setting). Developer's directives: <directives or « aucune »>. Follow your procedure and answer in your format."
3. `sh ~/.config/opencode/scripts/ticket-sheet.sh check`, as /go step 4.2. The full suite of develop in the same turn as the analyst, as /go step 4 (the tests that already fail are never yours).

## 4. One vulnerability per step, one `coder` subagent each
For each unchecked step, a line « Vulnérabilité <N>/<total> : <category> dans <file>… », then the `coder` subagent:
"Fix step <N> of the batch <KEY> in the repository <root>: <full text of the step>. Do it in this order, and run only the tests named here after each part:
1. Context: when the step says « non couvert », write the characterization tests it lists, in the existing test project of this code, following its conventions; they describe the current behavior and MUST PASS before any change of the code. A failing one describes the behavior wrongly: fix the test, never the code.
2. Security test: write it; it MUST FAIL on the current code, for the reason of the vulnerability (show the failing line). When the step says it cannot be shown by a unit test, write a test of the safe behavior instead and say so.
3. Fix: the smallest change, from the skill fortify-remediation; no refactoring, no other file than the step needs.
4. Run the tests of parts 1 and 2 and the existing tests of the « Contexte couvert » line: all must pass; then the build.
Tests that already fail on develop (not yours, never touch them): <names>. Project type: <type>. Build and tests: <AGENTS.md "Build & test">. Report in your format, with one line per part: done, or not done and why."
Then:
- RÉSULTAT OK: in ONE shell call, `sh ~/.config/opencode/scripts/ship.sh --no-push "fix(security): <category in English> in <file name> (<KEY>)" "- Fortify <issue id>" "- tests: <n> context, 1 vulnerability"` then `&& sh ~/.config/opencode/scripts/ticket-sheet.sh tick <N> "/fortify <N> - corrigée - tests <n>+1"`. One commit per vulnerability: fix and tests together, reviewed one by one.
- ÉCHEC, a report without its RÉSULTAT line, or a subagent error: the `debugger`, then the SAME coder session (its `sessionID`) with the diagnosis, as /go step 5.3. Still failing: the same coder session again with « Annule tous tes changements de cette étape : remets chaque fichier comme avant. », then `git status --short`: nothing left → `ticket-sheet.sh tick <N> "/fortify <N> - non corrigée : <reason>"` and the NEXT step (one vulnerability never blocks the batch); files left → stop with your report, nothing pushed.

## 5. Verify and deliver
As /go steps 6 and 7: full build and tests, the `checker` on the diff of the batch (its blocking points: one coder round), then `ship.sh --base`, the Draft merge request (title « Fortify : <n> vulnérabilités <category> (<KEY>) »), and `ticket-sheet.sh suivi "/fortify - livré - MR !<iid>"`. Nothing corrected at all: nothing is pushed; say why for each one.

## Answer, in French, and the merge request description
- « 🔒 Lot Fortify <application> / <version> » and the merge request link.
- Table: | Fortify | Gravité | Fichier | Correction | Contexte | Test de la vulnérabilité | Commit |. « Contexte »: « déjà couvert (<n> tests) » or « <n> tests ajoutés ». « Test de la vulnérabilité »: « échouait avant, passe après » or « non démontrable : <reason> ».
- « Non corrigées », one line each with the reason: they go back to the next batch only once the reason is solved.
- « À vérifier après le merge : le scan Fortify de la CI doit les marquer corrigées ; un faux positif se déclare dans SSC par toi, jamais par moi. » Last line: « /fortify pour le lot suivant, une fois cette MR mergée. »
