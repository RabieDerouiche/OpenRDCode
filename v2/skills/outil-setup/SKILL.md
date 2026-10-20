---
name: outil-setup
description: "Procédure de /outil setup : crée ou met à jour l'AGENTS.md du dépôt depuis le code (structure et frameworks, commandes de build et de test qui tournent ici, contrôles de la CI, style imposé par le build, architecture et conventions, autorisations, packages, tests, exemples de référence, conventions git) et Confluence si on lui donne une page. Une fois par dépôt, puis après un gros changement."
compatibility: opencode
---
# /outil setup
Create or update the AGENTS.md at the repository root so that every agent works like this repository, from the code as it is today. The arguments, when there are some, are a Confluence root page, page URL or space key. The project detection, the repository root, the state of AGENTS.md and the solution, build, CI and code style files are printed above.

This is what makes /go autonomous: the build and test commands, the conventions and the reference examples written here are what the coder follows without asking.

Rules:
- The ONLY file you may create or modify is `AGENTS.md` at the repository root. Do not touch any other file. Do not commit it: on a ticket branch, /fix commits and pushes it; otherwise the developer does.
- Never invent. Every line you write comes from the code (cite the file path in your report, not in AGENTS.md) or from a Confluence page (cite its title in your report).
- Keep every manual line and every section you do not manage unchanged, in place. Never delete a "Repository-specific rules" line.
- Never write secrets, passwords, tokens, connection strings, internal URLs with credentials or personal data.
- AGENTS.md is read at the start of every session: keep it under 200 lines, one fact per line, no prose. Write what an agent needs to produce code that builds, passes the CI and the review at the first try; leave out what it can read in one file when it needs it.
- Read-only on Confluence, Jira and every other system.
- Never read appsec-ci.env or nuget.config credentials.

## Step 1 - What exists
- "AGENTS.md: none": creation mode.
- Otherwise read it. If it was last changed a while ago, list the structural changes since then: `git diff --stat <hash of the last change>..HEAD -- '*.sln' '*.slnx' '*.csproj' 'Directory.*.props' 'global.json' '.editorconfig' '.gitlab-ci.yml' 'package.json'` and `git log --oneline <hash>..HEAD | head -30`. Sections touched by these changes are the first to re-check.

## Step 2 - Analyze the code, section by section
For each section below, determine its content from the code. Skip a section that does not apply to the project type. Send the reads and searches of several sections together in one turn (the files listed above: project files, `Directory.Build.props`, `Directory.Packages.props`, `global.json`, `.editorconfig`, `.gitlab-ci.yml`, test settings, merge request template).
1. `## Project type`: only if the detection above is wrong or the repository mixes several types (say which folder is which).
2. `## Project overview`: what it does and who calls it, 2-3 lines (from README, Program/Startup, controllers or endpoints, Confluence if given).
3. `## Solution structure`: one line per project or main folder with its role, its target framework(s) when they are not the same for every project (a `netstandard2.0` or `net48` project limits the APIs the code may use), and the dependency rules actually observed between projects (from project references).
4. `## Build & test`, one line each:
   - the build command, with the solution or project path when the root has several;
   - the full test suite that runs on this machine: the command, with the filter or the projects that leave out the tests needing Docker, a database or the network; then one line naming those tests "CI only";
   - front-end: the scripts of package.json, and the test command as ONE run that ends (no watch mode, headless browser; for example `npm test -- --watch=false --browsers=ChromeHeadless` for Karma, `npx vitest run`);
   - what the CI checks besides build and tests, from `.gitlab-ci.yml` (and its included files when they are in the repository): formatting or lint with their read-only command (`dotnet format --verify-no-changes`, `npx eslint src`, `npx prettier --check src`), coverage threshold; a template included from another project: its name, "détails hors du repo";
   - EF Core, only if the repository uses it: the exact migration command (`dotnet ef migrations add <Name> --project <...> --startup-project <...>`), after `dotnet tool restore` when `.config/dotnet-tools.json` exists.
   Verify the build and the full suite once with `sh ~/.config/opencode/scripts/build-test.sh <solution or project> [<test options>]` (build, then tests, in one call), and a front-end test command once (it must end by itself), but write the plain `dotnet build` / `dotnet test` / npm commands: AGENTS.md is shared with the team. Legacy .NET Framework that cannot build on this machine (.NET Framework needs Windows): say so, and write the Windows build command if the repository documents one. If restore fails with 401/403/NU1301, write the commands anyway and report an Artifactory access problem.
5. `## Code style enforced by the build`, only what is configured, one line each: `Nullable`, `ImplicitUsings`, `LangVersion`, `TreatWarningsAsErrors` / `WarningsAsErrors` (from `Directory.Build.props` or the project files), analyzer packages (StyleCop, SonarAnalyzer, Roslynator...), the `.editorconfig` rules set to `error` or `warning` that new code most often breaks (namespace style, `var`, braces, naming), and the formatter (dotnet format, CSharpier, Prettier). This section is what lets the agents write code that compiles without a new warning at the first try.
6. `## Architecture & conventions`, one line each, only what is observed:
   - how endpoints are declared (controllers, minimal APIs, endpoint classes) and where;
   - authorization: how endpoints are protected (`[Authorize]` and its policies, a fallback policy, ABP permissions) and where policies or permissions are declared;
   - request flow (endpoint → handler / service → ports → infrastructure);
   - DI registration (extension methods per layer, where);
   - validation (FluentValidation, data annotations, where it runs);
   - error handling: result type (name, namespace) or exceptions + middleware, and how errors map to HTTP responses;
   - mapping (manual, Mapster, AutoMapper);
   - logging (library, message templates, correlation);
   - configuration: options classes, `appsettings.<Environment>.json` files present, where secrets come from (never their values);
   - feature flags mechanism, if any;
   - persistence and external integrations (SharePoint/CSOM, DocuSign, S3 storage interfaces, Piano Analytics…) with the interface or class that wraps each one;
   - packages: central package management (`Directory.Packages.props`: a new package gets its `<PackageVersion>` there and a `<PackageReference>` without version in the project) or a version in each project; in-house packages from the company feed (names only).
7. `## In-house mediator` (cqrs-api only): package, namespaces, request and handler interfaces, pipeline behaviors, registration.
8. `## Tests`: framework, assertions, mocks, fixtures (`IClassFixture`, `ICollectionFixture`, base classes), test data builders, naming convention, test project layout, integration tests (`WebApplicationFactory`, Testcontainers) and what they need.
9. `## Reference examples`: for each kind of file the agents generate in this project type, ONE representative, recent, tested file (cqrs-api: command or query, handler, validator, endpoint, handler test, validator test; api: controller, service, service test; library: public class and its test; front-end: component, service, their tests). Prefer files changed recently, with tests, following the dominant convention.
10. `## Git conventions`: the commit message format actually used in the last 30 commits of the base branch (for example Conventional Commits with the Jira key, or `<KEY> <summary>`; `git log --oneline -30 <base branch>`), and the merge request template if `.gitlab/merge_request_templates/` has one (its path). /go and /fix follow them.
11. `## Confluence` and `## Releases`: keep them; fill them only from Confluence (step 3) or my answers.
12. `## Repository-specific rules`: keep the existing lines. You may PROPOSE new rules for conventions that are clear in the code but easy to break (for example "never call S3 directly, always through IStorageService"); they are added only if I accept them in step 5.

## Step 3 - Confluence (only if a source is given in the arguments, or the `## Confluence` section has a root page)
From the root, list the child pages and read at most 15 relevant ones: architecture, conventions, environments, integrations, glossary, runbooks, decisions (ADR). Skip meeting notes and outdated pages (report which ones). Check each fact against the code; if they disagree, trust the code and report the disagreement (documentation to fix, not code to change). Add or update only: `## Business context` (3-5 lines), `## Glossary` (one line per domain term), `## Environments` (names and purpose, no URLs with credentials), `## External systems` (what each one is used for, with the code location), `## Architecture decisions` (one line each), `## Confluence` (space key and root page if empty).

## Step 4 - Doubts
Ask me with the question tool, recommended option first, all the questions in ONE call (one question per doubt), only when:
- two conventions coexist (controllers and minimal APIs, Moq and NSubstitute, exceptions and a result type, two folder layouts, two commit message formats): "La plus récente : <x> (recommandé)" / "<y>" / "Les deux, selon le dossier";
- an existing line of AGENTS.md contradicts the code: "Mettre à jour selon le code" (recommandé) / "Garder la ligne actuelle";
- a section cannot be determined from the code: "Laisser [à compléter]" (recommandé) / free answer.

## Step 5 - Write
Write AGENTS.md with the edit or write tool, without asking: the diff is reviewed in Rider before the commit. The proposed new repository rules are NOT written: they are listed in the answer, the developer adds the ones he wants (« ajoute la règle 2 à AGENTS.md »).

## Answer, in French
- A table: section | statut (ajoutée, mise à jour, inchangée, à compléter) | ce qui change en une ligne.
- The proposed repository rules, numbered, not written.
- What I must fill myself (values only I know: Confluence pages, application name for release notes, `[à compléter]` lines).
- Confluence pages used and skipped, and the Confluence-versus-code disagreements.
- Last line: « AGENTS.md est un fichier du dépôt partagé avec l'équipe : relis le diff ; sur une branche de ticket, /fix le commite et le pousse. Relance /outil setup après un gros changement d'architecture ou d'organisation. »
