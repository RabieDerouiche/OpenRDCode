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

Write the missing unit tests of the code the request names, with their proof, in this single run, without a ticket: no ticket sheet, no Jira call, no merge request. The developer may be watching, but the run asks at most the one question of step 1. The test-guardian writes and proves the tests; you never write a test yourself.

## 1. Before any work
- Nothing named in the request: stop with « ⛔ Dis-moi quoi tester : /tests <classe, fichier ou dossier> ».
- "Merge in progress: yes": stop with « ⛔ Une fusion est en cours : termine-la dans Rider (ou git merge --abort), puis relance /tests. »
- An "ENVIRONMENT PROBLEM" line or a "STOP:" line of the prerequisites (dotnet missing): stop with it. A front-end or legacy .NET Framework project (no .NET test project can build here): stop with « ⛔ /tests écrit des tests .NET qui tournent sur cette machine ; ici : <why>. »
- « PREREQ: SETUP NEEDED »: your first tool call is ONE question tool call (header « Tests unitaires », the only question of the run): « <Ce dépôt n'a pas de projet de tests unitaires | Le collecteur de couverture manque dans <projects>>. Je <le crée | l'ajoute> en premier commit ? » with « Oui, xUnit (recommandé) », « Oui, MSTest », « Oui, NUnit », « Non, j'arrête » (collector missing: « Oui (recommandé) », « Non, j'arrête »). « Non »: stop with « ⛔ Pas de projet de tests : rien n'est écrit. »

## 2. What to test
1. The production files of the request, in one turn of searches (glob and grep tools): a class or a method gives its file; a folder gives its files that hold logic (services, handlers, validators, mappers with rules, domain classes), never DTOs, options classes, migrations, generated code or pure wiring. At most 6 files per run: more, keep the 6 the request names first, and list the others in the answer for the next run. Files in a test project are not production files. Nothing found: stop with « ⛔ Introuvable : <names> ».
2. The test project of each file: the unit test project that references its project (`git grep -l "<project file name>" -- '*Tests*.csproj' '*Test*.csproj'`), otherwise the only unit test project of the solution. None and no setup in step 1: stop with « ⛔ Aucun projet de tests ne référence <project> : /tests ne crée pas de projet de tests à côté d'un existant ; ajoute la référence, ou dis-moi lequel utiliser. »

## 3. The branch, then the setup
ONE shell call, `sh ~/.config/opencode/scripts/branch.sh --here test "<3 to 6 words in English: what is tested>"` (on develop, master, main or a detached HEAD it creates `test/<words>` with the uncommitted changes; on another branch, that branch is kept: the tests go with its work). A "STOP:" line: stop with it. Then, when the developer said « Oui » in step 1, ONE shell call: `sh ~/.config/opencode/scripts/test-guardian.sh setup <xunit | mstest | nunit: the answer; xunit when only the collector was missing> <the files of step 2> && sh ~/.config/opencode/scripts/ship.sh --no-push "test: add the unit test project"` ("test: add the coverage collector to the unit test projects" when only the collector was missing). A "STOP:" line: stop with it.

## 4. The tests, by the test-guardian
One line « Tests unitaires de <n> fichiers (test-guardian)… », then the `test-guardian` (description « Tests unitaires »): "Mission « tests ». Files to test: <the files of step 2, each with its test project>. Repository root: <root>. Coverage label: T1. Developer's directives: <directives or « aucune »>. No ticket: the expected behavior is the current behavior of the code (characterization), and its documentation (XML comments, README, docs/). Report in your format."
- Its report OK: in ONE shell call, `sh ~/.config/opencode/scripts/test-guardian.sh tests-only && sh ~/.config/opencode/scripts/ship.sh --no-push "test(<scope>): add unit tests of <what, in English>" "- <n> tests; coverage <file lines before -> after>, per file"`. A "STOP:" line of tests-only (a file outside the test projects changed): nothing is committed; stop with it.
- A bug found by a test (« Problème » with the input and what happens): the test-guardian kept that test out; the bug goes to the answer, never fixed here (« /go sans ticket : <the bug> » fixes it with its proof).
- ÉCHEC or BLOQUÉ: the SAME test-guardian session once, with its « Problème » line and « Corrige ce point, puis refais la preuve. »; still failing: commit what passed only if its report gives a filter whose tests are GREEN (`test-guardian.sh green <test project> <that filter>` first), otherwise nothing; then stop with its report.

## Answer, in French
Header line « **/tests** — <branch> », then « ✅ Tests ajoutés et prouvés » (or the « ⛔ » line), then a table | Fichier | Couverture avant | Couverture après | Tests ajoutés |, the filter that runs them, the bugs found (file:line, input, observed, expected), the files left for another run, and the commit (short hash, message). Last, the question tool (header « Suite »): « /push (recommandé) » (it proposes the branch name, the commit message and the merge request), « Rien pour l'instant ».
