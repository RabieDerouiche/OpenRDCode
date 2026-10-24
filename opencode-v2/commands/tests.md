---
description: "Tests unitaires sans ticket : pour les classes, fichiers ou dossiers que tu nommes, le test-guardian mesure la couverture, écrit les tests du comportement actuel dans le style du dépôt, les prouve (verts deux fois, aucun test instable), mesure la couverture après, puis un commit sur une branche test/… (ou ta branche). Rien n'est poussé : /push ensuite. Sans projet de tests, propose de le créer. Usage: /tests <classe, fichier ou dossier>… [directives, e.g. « seulement les cas d'erreur »]"
agent: pilot
subtask: false
---
[[command tests $ARGUMENTS]]
Request: « $ARGUMENTS » (the classes, files, folders or methods to test, and the developer's directives)

Workflow state (no fetch: nothing is pushed here):
[[run workflow-state.sh --no-fetch]]

Prerequisites (dotnet, the unit test projects and their coverage collector):
[[run fortify.sh prereq --tests]]

Write the missing unit tests of the code the request names, with their proof, in this single run, without a ticket: no ticket sheet, no Jira call, no merge request. The developer may be watching, but the run asks at most the one question of step 1, and its « Suite » at the end. The test-guardian writes and proves the tests; you never write a test yourself.

## 1. Before any work
- Nothing named in the request: stop with « ⛔ Dis-moi quoi tester : /tests <classe, fichier ou dossier> ».
- "Merge in progress: yes": stop with « ⛔ Une fusion est en cours : termine-la dans Rider (ou git merge --abort), puis relance /tests. »
- An "ENVIRONMENT PROBLEM" line or a "STOP:" line of the prerequisites (dotnet missing): stop with it. A front-end or legacy .NET Framework project (no .NET test project can build here): stop with « ⛔ /tests écrit des tests .NET qui tournent sur cette machine ; ici : <why>. » For a front-end, the « Suite » question offers « /go sans ticket : ajouter les tests unitaires de <what the request names> (recommandé) » (« le coder écrit les specs et les lance une fois avec build-test.sh <dossier> ; une MR à la fin ») and « Rien pour l'instant ».
- Uncommitted or untracked files outside the test projects (the "Uncommitted files" and "Untracked files" lines): the developer's own work; /tests never mixes it with its tests. One question (header « Modifications »), in the same call as the setup question when there is one: « Tu as des modifications non commitées hors des tests (<the files, 5 at most>). » with « Les commiter d'abord, dans leur propre commit (recommandé) » and « J'arrête : je les pousse moi-même (/push) ». The first: in step 3 the branch is named after their nature (`feature`, `bugfix`, `refactor`… with 3 to 6 words of what they do), and right after it, alone in its call, `sh ~/.config/opencode/scripts/ship.sh --no-push "<a conventional commit message in English that you write from their diff>"`: they are committed before any test is written.
- « PREREQ: SETUP NEEDED »: your first tool call is ONE question tool call (header « Tests unitaires »; with the question above when there is one, the only question call of the run before its « Suite »): « <Ce dépôt n'a pas de projet de tests unitaires | Le collecteur de couverture manque dans <projects>>. Je <le crée | l'ajoute> en premier commit ? » with « Oui, xUnit (recommandé) », « Oui, MSTest », « Oui, NUnit », « Non, j'arrête » (collector missing: « Oui (recommandé) », « Non, j'arrête »). « Non »: stop with « ⛔ Pas de projet de tests : rien n'est écrit. »

## 2. What to test
1. The production files of the request, in one turn of searches (glob and grep tools): a class or a method gives its file; a folder gives its files that hold logic (services, handlers, validators, mappers with rules, domain classes), never DTOs, options classes, migrations, generated code or pure wiring. At most 6 files per run: more, keep the 6 the request names first, and list the others in the answer for the next run. Files in a test project are not production files. Nothing found: stop with « ⛔ Introuvable : <names> ».
2. The test project of each file: the unit test project that references its project (`git grep -l "<project file name>" -- '*Tests*.csproj' '*Test*.csproj'`), otherwise the only unit test project of the solution. None and no setup in step 1: stop with « ⛔ Aucun projet de tests ne référence <project> : /tests ne crée pas de projet de tests à côté d'un existant ; ajoute la référence, ou dis-moi lequel utiliser. »

## 3. The branch, then the setup
ONE shell call, `sh ~/.config/opencode/scripts/branch.sh --here test "<3 to 6 words in English: what is tested>"` (on develop, master, main or a detached HEAD it creates `test/<words>`; on another branch, that branch is kept: the tests go with its work; the developer's uncommitted work of step 1: the branch takes its nature instead of `test`, then its own commit). A "STOP:" line: stop with it. Then, when the developer said « Oui » in step 1, ONE shell call: `sh ~/.config/opencode/scripts/test-guardian.sh setup <xunit | mstest | nunit: the answer; xunit when only the collector was missing> <the files of step 2> && sh ~/.config/opencode/scripts/ship.sh --no-push "test: add the unit test project"` ("test: add the coverage collector to the unit test projects" when only the collector was missing). A "STOP:" line: stop with it.

## 4. The tests, by the test-guardian
One line « Tests unitaires de <n> fichiers (test-guardian)… », then the `test-guardian` (description « Tests unitaires »): "Mission « tests ». Files to test: <the files of step 2, each with its test project>. Repository root: <root>. Coverage label: T1. Developer's directives: <directives or « aucune »>. No ticket: the expected behavior is the current behavior of the code (characterization), and its documentation (XML comments, README, docs/). Report in your format."
- Its report OK: in ONE shell call, `sh ~/.config/opencode/scripts/test-guardian.sh tests-only && sh ~/.config/opencode/scripts/ship.sh --no-push "test(<scope>): add unit tests of <what, in English>[ (<KEY>)]" "- <n> tests; coverage <file lines before -> after>, per file"` (the Jira key of the branch at the end, when it has one). A "STOP:" line of tests-only (a file outside the test projects changed): nothing is committed; stop with it.
- A bug found by a test (« Problème » with the input and what happens): the test-guardian kept that test out; the bug goes to the answer, never fixed here (« /go sans ticket : <the bug> » fixes it with its proof).
- ÉCHEC or BLOQUÉ: the SAME test-guardian session once, with its « Problème » line and « Corrige ce point, puis refais la preuve. »; still failing: commit what passed only if its report gives a filter whose tests are GREEN (`test-guardian.sh green <test project> <that filter>` first), otherwise nothing; then stop with its report.

## Answer, in French
Header line « **/tests** — <branch> », then « ✅ Tests ajoutés et prouvés » (or the « ⛔ » line), then a table | Fichier | Couverture avant | Couverture après | Tests ajoutés |, the filter that runs them, the bugs found (file:line, input, observed, expected), the files left for another run, and the commit (short hash, message). Last, the « Suite » question: « /push (recommandé) » (« il propose le nom de la branche, le message de commit et la MR »), « Rien pour l'instant ».
