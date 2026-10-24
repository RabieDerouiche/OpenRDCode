---
name: pack-setup
description: "Procédure de /outil setup : crée ou met à jour l'AGENTS.md du dépôt depuis le code, court et utile aux agents : comment builder et tester ici (build-test.sh, la cible et les filtres), ce que la CI et le build imposent, les conventions avec le fichier à imiter, les exemples de référence, les conventions git ; Confluence si on lui donne une page. Une fois par dépôt, puis après un gros changement."
compatibility: opencode
---
# /outil setup

Started directly as the command `/pack-setup` (this procedure is the message that started you, with no line « Skill : pack-setup » printed before it): answer only « Lance `/outil setup` : cette procédure a besoin de ce que /outil prépare. » and stop.

Create or update the AGENTS.md at the repository root so that every agent works like this repository, from the code as it is today. The arguments, when there are some, are a Confluence root page, page URL or space key. The project detection, the repository root, the state of AGENTS.md, the solution, build, CI and code style files, and the test projects with their test runner are printed above.

This is what makes /go autonomous: the coder follows what is written here without asking. An agent reads AGENTS.md at the start of EVERY session: each line costs its attention every time, so a line earns its place only if an agent would get something wrong without it, or would spend several tool calls to find it.

Rules:
- The ONLY file you may create or modify is `AGENTS.md` at the repository root. Do not touch any other file. Do not commit it: on a ticket branch, /fix commits and pushes it; otherwise the developer does.
- Never invent. Every line you write comes from the code (cite the file path in your report, not in AGENTS.md) or from a Confluence page (cite its title in your report).
- Keep every manual line and every section you do not manage unchanged, in place. Never delete a "Repository-specific rules" line.
- Never write secrets, passwords, tokens, connection strings, internal URLs with credentials or personal data.
- Short and actionable: 40 to 120 lines, one fact per line, no prose, no line about generic .NET or framework knowledge, no package versions, no inventory of files or classes an agent can list itself. Write rules and "like `<file>`", not descriptions: « Nouvel endpoint : une classe par endpoint dans `src/Api/Endpoints/<Feature>/`, comme `src/Api/Endpoints/Orders/CreateOrder.cs` » rather than a paragraph on how endpoints work.
- Read-only on Confluence, Jira and every other system.
- Never read appsec-ci.env or nuget.config credentials.

## Step 1 - What exists
- "AGENTS.md: none": creation mode.
- Otherwise read it. If it was last changed a while ago, list the structural changes since then: `git diff --stat <hash of the last change>..HEAD -- '*.sln' '*.slnx' '*.csproj' 'Directory.*.props' 'global.json' '.editorconfig' '.gitlab-ci.yml' 'package.json'` and `git log --oneline <hash>..HEAD | head -30`. Sections touched by these changes are the first to re-check.
- A line that runs builds or tests another way than the commands of step 2.4 (`dotnet run`, `dotnet exec`, a path under `bin/`, `dotnet vstest`), or that says the tests cannot run with dotnet test: it is wrong (build-test.sh runs the Microsoft.Testing.Platform tests itself). Replace it without asking, and say so in the table.
- A line that is generic knowledge, a description an agent gets from one file, or a duplicate: remove it (except in "Repository-specific rules"), and say so in the table.

## Step 2 - Analyze the code, section by section
For each section below, determine its content from the code. Skip a section that does not apply to the project type. Send the reads and searches of several sections together in one turn (the files listed above: project files, `Directory.Build.props`, `Directory.Packages.props`, `global.json`, `.editorconfig`, `.gitlab-ci.yml`, test settings, merge request template).
1. `## Project type`: only if the detection above is wrong or the repository mixes several types (say which folder is which).
2. `## Project overview`: what it does and who calls it, 2 lines (from README, Program/Startup, controllers or endpoints, Confluence if given).
3. `## Solution structure`: one line per project or main folder with its role in a few words; its target framework only when it differs from the others (a `netstandard2.0` or `net48` project limits the APIs the code may use); the dependency rule between projects in one line ("Domain ne référence rien ; Application → Domain ; Infrastructure → Application"), from the project references.
4. `## Build & test`. The agents build and test ONLY through the pack's `build-test.sh` (their global rules), which takes the solution or project and the test options written here, and runs the tests of each project with its runner (VSTest, or Microsoft.Testing.Platform: xUnit v3, MSTest.Sdk, NUnit or TUnit runners). One line each:
   - `- Solution : <path>`: what build-test.sh builds and tests, when the root has several solutions or none (otherwise leave the line out);
   - `- Tests locaux : <options>`: only when some tests cannot run on a developer machine (Docker, database, network): the filter that leaves them out (`--filter "Category!=Integration"`), then `- CI seulement : <those projects or categories>`;
   - `- Lanceur de tests : <VSTest | Microsoft.Testing.Platform (xUnit v3 | MSTest | NUnit | TUnit)>` from the "Projets de tests" lines above; several runners: one line per runner with its projects;
   - `- Terminal (développeurs) : dotnet build <solution>` and `dotnet test <solution> [<options>]`. With Microsoft.Testing.Platform on the .NET 10 SDK, `dotnet test` works in a terminal only when `global.json` opts in (`"test": { "runner": "Microsoft.Testing.Platform" }`): when it does not, write only `dotnet build` here and put the opt-in in the answer as a suggestion for the developer (never a file you create);
   - front-end: the scripts of package.json, and the test command as ONE run that ends (no watch mode, headless browser; for example `npm test -- --watch=false --browsers=ChromeHeadless` for Karma, `npx vitest run`);
   - `- La CI vérifie aussi : …` from `.gitlab-ci.yml` (and its included files when they are in the repository): formatting or lint with their read-only command (`dotnet format --verify-no-changes`, `npx eslint src`, `npx prettier --check src`), coverage threshold; a template included from another project: its name, "détails hors du repo";
   - `- Filet de non-régression : <n> %`: only when the team asks another minimum than the pack's 80 % (the share of the lines of the methods a fix or a change touches that tests must run before it: the test-guardian of /go, /fix and /fortify writes the missing non-regression tests first);
   - EF Core, only if the repository uses it: the exact migration command (`dotnet ef migrations add <Name> --project <...> --startup-project <...>`), after `dotnet tool restore` when `.config/dotnet-tools.json` exists.
   Verify once, in one call: `sh ~/.config/opencode/scripts/build-test.sh [<solution>] [<the local test options>]`, and a front-end test command once (it must end by itself). Its BUILD/TESTS result goes in the answer, never in AGENTS.md. Never write in AGENTS.md a way around a failure or a refusal (`dotnet run`, `dotnet exec`, `bin/…`, `--no-build` tricks, a script of your own): a failing build or test is a finding for the answer, an "ENVIRONMENT PROBLEM" line stops you (tell me in one line), a 401/403/NU1301 is an Artifactory access problem for the answer (the commands are written anyway). Legacy .NET Framework that cannot build on this machine (.NET Framework needs Windows): say so in one line, with the Windows build command if the repository documents one.
5. `## Code style enforced by the build`, only what is configured and breaks the build or the CI, one line each: `Nullable`, `TreatWarningsAsErrors` / `WarningsAsErrors` (from `Directory.Build.props` or the project files), the analyzers that fail the build (StyleCop, SonarAnalyzer, Roslynator...), the `.editorconfig` rules at `error` (or `warning` with warnings as errors) that new code most often breaks (namespace style, `var`, braces, naming), the formatter the CI checks. Nothing that is a default of the SDK.
6. `## Architecture & conventions`, one rule per line, each with the file to imitate, only what is observed and what a new file must follow:
   - endpoints (controllers, minimal APIs, endpoint classes): where a new one goes, like which file;
   - authorization: how a new endpoint is protected (`[Authorize]` and its policy, fallback policy, ABP permission) and where a new policy or permission is declared;
   - request flow (endpoint → handler / service → ports → infrastructure) in one line;
   - DI registration: where a new service is registered;
   - validation, error handling (result type and namespace, or exceptions + middleware) and how an error becomes an HTTP response;
   - mapping, logging (message templates), configuration (options classes; where secrets come from, never their values), feature flags;
   - each external integration (SharePoint/CSOM, DocuSign, S3, Piano Analytics…): the interface that wraps it, which the code must use;
   - packages: central package management (`Directory.Packages.props`: a new package gets its `<PackageVersion>` there and a `<PackageReference>` without version) or a version in each project; the in-house packages used (names only): their API comes from the existing calls and the package's XML documentation (package-refs.sh), never from guessing.
7. `## In-house mediator` (cqrs-api only): package, namespaces, request and handler interfaces, pipeline behaviors, registration.
8. `## Tests`: framework, assertions, mocks, fixtures (`IClassFixture`, `ICollectionFixture`, base classes), test data builders and where they are, naming convention (`Method_State_Expected`…), where a new test file goes, integration tests (`WebApplicationFactory`, Testcontainers) and what they need.
9. `## Reference examples`: for each kind of file the agents generate in this project type, ONE representative, recent, tested file (cqrs-api: command or query, handler, validator, endpoint, handler test, validator test; api: controller, service, service test; library: public class and its test; blazor: component, its test; front-end: component, service, their tests). Prefer files changed recently, with tests, following the dominant convention. This section is the most useful one: an agent that imitates the right file writes the right code.
10. `## Git conventions`: the commit message format actually used in the last 30 commits of the base branch (for example Conventional Commits with the Jira key, or `<KEY> <summary>`; `git log --oneline -30 <base branch>`), and the merge request template if `.gitlab/merge_request_templates/` has one (its path). /go and /fix follow them.
11. `## Confluence` and `## Releases`: keep them; fill them only from Confluence (step 3) or my answers.
12. `## Repository-specific rules`: keep the existing lines. You may PROPOSE new rules for conventions that are clear in the code but easy to break (for example "never call S3 directly, always through IStorageService"); they are added only if I accept them in step 5.

## Step 3 - Confluence (only if a source is given in the arguments, or the `## Confluence` section has a root page)
From the root, list the child pages and read at most 15 relevant ones: architecture, conventions, environments, integrations, glossary, runbooks, decisions (ADR). Skip meeting notes and outdated pages (report which ones). Check each fact against the code; if they disagree, trust the code and report the disagreement (documentation to fix, not code to change). Add or update only, a few lines each: `## Business context` (3-5 lines), `## Glossary` (one line per domain term an agent would misread), `## Environments` (names and purpose, no URLs with credentials), `## External systems` (what each one is used for, with the code location), `## Architecture decisions` (one line each), `## Confluence` (space key and root page if empty).

## Step 4 - Doubts
Ask me with the question tool, recommended option first, all the questions in ONE call (one question per doubt), only when:
- two conventions coexist (controllers and minimal APIs, Moq and NSubstitute, exceptions and a result type, two folder layouts, two commit message formats): "La plus récente : <x> (recommandé)" / "<y>" / "Les deux, selon le dossier";
- an existing line of AGENTS.md contradicts the code: "Mettre à jour selon le code" (recommandé) / "Garder la ligne actuelle";
- a section cannot be determined from the code: "Laisser [à compléter]" (recommandé) / free answer.

## Step 5 - Write
Write AGENTS.md with the edit or write tool, without asking: the diff is reviewed in Rider before the commit. Before writing, read your draft once as the coder of /go would: remove every line it would not use. The proposed new repository rules are NOT written now: they are listed in the answer and offered in its last question, and only the ones I choose there are added.

## Answer, in French
- A table: section | statut (ajoutée, mise à jour, inchangée, retirée, à compléter) | ce qui change en une ligne.
- The result of the build-test.sh run (BUILD, TESTS, FAILED TESTS lines), and what fails when something does.
- The proposed repository rules, numbered, not written; with Microsoft.Testing.Platform and no `global.json` opt-in, the opt-in as a suggestion (« pour que `dotnet test` marche aussi dans ton terminal »).
- What I must fill myself (values only I know: Confluence pages, application name for release notes, `[à compléter]` lines).
- Confluence pages used and skipped, and the Confluence-versus-code disagreements.
- Last line: « AGENTS.md est un fichier du dépôt partagé avec l'équipe : relis le diff avant de l'envoyer. Relance /outil setup après un gros changement d'architecture ou d'organisation. », then ONE question tool call. When rules are proposed, its first question (header « Règles », `multiple: true`): « Quelles règles proposées j'ajoute à AGENTS.md ? », one option per rule (label « Règle <n> : <the rule in 8 words at most> », description the whole rule), plus « Aucune ». Then, in the same call, the « Suite » question (header « Suite »): « Rien pour l'instant (recommandé) » (« je relis le diff d'abord »), « /push » (« une branche chore/… pour l'AGENTS.md, son commit et sa MR ; sur une branche de ticket, il le pousse avec elle »). The rules I choose: add them at once, in the same turn, at the end of `## Repository-specific rules` (one edit), then one line « Ajouté à AGENTS.md : règles <n>, <n> ». Then /push chosen: answer only « Je lance /push. » (the pack starts it as soon as your turn ends, with these rules); otherwise « D'accord. ».
