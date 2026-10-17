---
description: "Create or update the repository AGENTS.md from the existing code (structure, build and test, architecture and conventions, handlers, tests, reference examples, in-house packages) and optionally from Confluence. Shows what is missing or outdated, asks when two conventions coexist, keeps manual lines, writes only AGENTS.md. Run once per repository, and again after big architecture or organization changes. Usage: /agents-md [Confluence root page, page URL or space key]"
agent: build
---
Confluence source given: "$ARGUMENTS"
Repository root: !`git rev-parse --show-toplevel`
Current AGENTS.md: !`ls AGENTS.md`
Last change of AGENTS.md: !`git log -1 --format='%h %cs' -- AGENTS.md`
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`
Solution and project files:
!`git ls-files '*.sln' '*.slnx' '*.csproj' 'package.json' 'Directory.Build.props' 'Directory.Packages.props' 'nuget.config'`

Create or update the AGENTS.md at the repository root so that every agent works like this repository, from the code as it is today.

Rules:
- The ONLY file you may create or modify is `AGENTS.md` at the repository root. Do not touch any other file. Do not commit it: /ship does.
- Never invent. Every line you write comes from the code (cite the file path in your report, not in AGENTS.md) or from a Confluence page (cite its title in your report).
- Keep every manual line and every section you do not manage unchanged, in place. Never delete a "Repository-specific rules" line.
- Never write secrets, passwords, tokens, connection strings, internal URLs with credentials or personal data.
- AGENTS.md is read at the start of every session: keep it under 200 lines, one fact per line, no prose.
- Read-only on Confluence, Jira and every other system.
- Never read appsec-ci.env or nuget.config credentials.

## Step 1 - What exists
- No AGENTS.md: creation mode.
- Otherwise read it. If it was last changed a while ago, list the structural changes since then: `git diff --stat <hash of the last change>..HEAD -- '*.sln' '*.slnx' '*.csproj' 'Directory.*.props' 'package.json'` and `git log --oneline <hash>..HEAD | head -30`. Sections touched by these changes are the first to re-check.

## Step 2 - Analyze the code, section by section
For each section below, determine its content from the code. Skip a section that does not apply to the project type.
1. `## Project type`: only if the detection above is wrong or the repository mixes several types (say which folder is which).
2. `## Project overview`: what it does and who calls it, 2-3 lines (from README, Program/Startup, controllers or endpoints, Confluence if given).
3. `## Solution structure`: one line per project or main folder with its role, and the dependency rules actually observed between projects (from project references).
4. `## Build & test`: the exact commands. Run them once to verify (build, then tests); with several solutions, give the solution path. Legacy .NET Framework that cannot build on this machine (.NET Framework needs Windows): say so, and write the Windows build command if the repository documents one. Front-end: the scripts of package.json. If restore fails with 401/403/NU1301, write the commands anyway and report an Artifactory access problem.
5. `## Architecture & conventions`, one line each, only what is observed:
   - how endpoints are declared (controllers, minimal APIs, endpoint classes) and where;
   - request flow (endpoint → handler / service → ports → infrastructure);
   - DI registration (extension methods per layer, where);
   - validation (FluentValidation, data annotations, where it runs);
   - error handling: result type (name, namespace) or exceptions + middleware, and how errors map to HTTP responses;
   - mapping (manual, Mapster, AutoMapper);
   - logging (library, message templates, correlation);
   - configuration: options classes, `appsettings.<Environment>.json` files present, where secrets come from (never their values);
   - feature flags mechanism, if any;
   - persistence and external integrations (SharePoint/CSOM, DocuSign, S3 storage interfaces, Piano Analytics…) with the interface or class that wraps each one;
   - in-house packages from the company feed (names only).
6. `## In-house mediator` (cqrs-api only): package, namespaces, request and handler interfaces, pipeline behaviors, registration.
7. `## Tests`: framework, assertions, mocks, fixtures (`IClassFixture`, `ICollectionFixture`, base classes), test data builders, naming convention, test project layout, integration tests (`WebApplicationFactory`) if any.
8. `## Reference examples`: for each kind of file the agents generate in this project type, ONE representative, recent, tested file (cqrs-api: command or query, handler, validator, endpoint, handler test, validator test; api: controller, service, service test; library: public class and its test; front-end: component, service, their tests). Prefer files changed recently, with tests, following the dominant convention.
9. `## Confluence` and `## Releases`: keep them; fill them only from Confluence (step 3) or my answers.
10. `## Repository-specific rules`: keep the existing lines. You may PROPOSE new rules for conventions that are clear in the code but easy to break (for example "never call S3 directly, always through IStorageService"); they are added only if I accept them in step 5.

## Step 3 - Confluence (only if a source is given above, or the `## Confluence` section has a root page)
From the root, list the child pages and read at most 15 relevant ones: architecture, conventions, environments, integrations, glossary, runbooks, decisions (ADR). Skip meeting notes and outdated pages (report which ones). Check each fact against the code; if they disagree, trust the code and report the disagreement (documentation to fix, not code to change). Add or update only: `## Business context` (3-5 lines), `## Glossary` (one line per domain term), `## Environments` (names and purpose, no URLs with credentials), `## External systems` (what each one is used for, with the code location), `## Architecture decisions` (one line each), `## Confluence` (space key and root page if empty).

## Step 4 - Doubts
Ask me with the question tool, one question at a time, recommended option first, when:
- two conventions coexist (controllers and minimal APIs, Moq and NSubstitute, exceptions and a result type, two folder layouts): "La plus récente : <x> (recommandé)" / "<y>" / "Les deux, selon le dossier";
- an existing line of AGENTS.md contradicts the code: "Mettre à jour selon le code" (recommandé) / "Garder la ligne actuelle";
- a section cannot be determined from the code: "Laisser [à compléter]" (recommandé) / free answer.

## Step 5 - Review then write
Show the plan of changes first: a table section | statut (ajoutée, mise à jour, inchangée, à compléter) | ce qui change en une ligne, then the proposed new repository rules. Ask me with the question tool: "Appliquer tout" (recommandé) / "Section par section" / "Annuler". Then write AGENTS.md with the edit or write tool.

## Answer, in French
- The table of step 5 with the final status.
- What I must fill myself (values only I know: Confluence pages, application name for release notes, `[à compléter]` lines).
- Confluence pages used and skipped, and the Confluence-versus-code disagreements.
- Last line: "AGENTS.md est un fichier du repo partagé avec l'équipe : relis le diff, puis /ship pour le commiter (sur une branche : /ship refuse develop). Relance /agents-md après un gros changement d'architecture ou d'organisation."
