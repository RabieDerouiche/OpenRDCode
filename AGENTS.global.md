# Global rules (merge into ~/.config/opencode/AGENTS.md)

## Language
- Answer me in French.
- Code, code comments, log messages, commit messages and test names are in English.

## Asking me
- When a decision is mine (which option, which version, which base branch, keep or change a library, fix or skip), do not stop and do not guess: ask me with the question tool, as multiple-choice questions with 2 to 4 short options each, the recommended one first and marked "(recommandé)". I can always type another answer.
- Ask only when the answer changes what you do; never ask for things you can find in the code, the git history or AGENTS.md. Put all the questions you already need into ONE question tool call (one question per decision, up to 4): I answer them in a row. Ask separately only a question that depends on a previous answer.

## Working style
- Read existing code before writing new code, and mirror its conventions.
- Smallest change that solves the request. No unrelated refactoring, renaming or reformatting.
- Never claim success without running the build and test commands of the repository when code was changed.
- Never invent file paths, types, methods, package names, application names or filter names. Look them up, or ask.

## Speed
- .NET build and tests in one call: `sh ~/.config/opencode/scripts/build-test.sh [<solution or project>] [<dotnet test options>]`. It builds quietly (errors only), runs the tests only if the build passed, and ends with explicit "BUILD:" and "TESTS:" lines. Some tests only: `sh ~/.config/opencode/scripts/build-test.sh <test project> --filter FullyQualifiedName~<TestClass>`. Build only, to fix compilation errors: `dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60`. When AGENTS.md "Build & test" names a solution or project, pass it as the first argument. Front-end: the commands of AGENTS.md or of the project detection.
- Other long outputs through `| tail -60`; `git diff --stat` before a full diff.
- Independent tool calls (reads, searches, MCP queries, skills to load, the build and tests) go together in ONE turn: they run in parallel. Chain calls only when one needs the result of another.
- AGENTS.md files are already in your instructions: never read them again, except to edit one. Read only the files and sections a step needs; do not re-read a file you already read unless it may have changed (for example after I edited it in Rider).

## Project types
- I work on several kinds of repositories: .NET 10 APIs with Clean Architecture + CQRS, classic .NET APIs without CQRS, legacy .NET Framework web projects, libraries, and front-end projects.
- The project type is auto-detected by `sh ~/.config/opencode/scripts/detect-project-type.sh` (types: cqrs-api, api, dotnet-app, legacy, library, frontend; several can apply). A "Project type" section in the repository AGENTS.md overrides the detection.
- Follow the conventions of the existing code of the repository. Never introduce CQRS, a mediator or Clean Architecture layers in a project that does not already use them.
- For CQRS APIs only: in-house mediator, NOT MediatR (never add MediatR); load the skill `dotnet-cqrs-conventions` before writing or reviewing handlers.
- New libraries or approaches: by default, use what the repository already uses (the "Test stack" line of the project detection for tests; the existing packages for the rest). When a task would bring something the repository does not use yet (for example Moq, FluentValidation, a mediator, a new test framework), ask me before writing code with the question tool: "Garder l'existant (<what is used today>)" (recommandé) or "Introduire <new thing> (<packages to add, files impacted>)". Wait for my answer. If I choose the new thing: add it, use it for the new code only, and do not rewrite existing code unless I ask.
- If the repository has no tests at all, ask me with the question tool before creating a test project.
- Licenses: these NuGet packages became paid or copyleft from a given version: MediatR 13+, AutoMapper 15+, FluentAssertions 8+, MassTransit 9+, NPOI 2.8+, EPPlus 5+, QuestPDF, SixLabors.ImageSharp 3+, Duende IdentityServer, iText, and Polly from its next major version. Never propose such a version without saying it is paid, with its free option first (in-house mediator or plain services, Mapperly or manual mapping, AwesomeAssertions or Shouldly, MassTransit 8, ClosedXML...). Checking the repository's packages is on demand only: /licences.
- Build and test with the commands from the section "Build & test" of the repository AGENTS.md if it exists, otherwise from the detection script. Legacy .NET Framework projects may not build on this machine (.NET Framework needs Windows): say so instead of changing project files.
- Integrations: SharePoint (CSOM), DocuSign, AWS S3, Piano Analytics. Load the skill `integrations-guardrails` before touching them. Never modify authentication or credentials handling without asking.

## Branches and releases
- Merge requests target `develop`. Production is deployed from `master` as is; there are no release tags.

## Workflow
- My day: /daily → /ticket <KEY> → /dev (one plan step at a time, with its tests; or I code myself) → /test → /check → /ship → /scans (after the CI) → /fortify-fix or /sonar-fix → /check again. /sync brings develop or my Mac pushes into the branch. /next tells me where I am and resumes a ticket. /agents-md keeps the repository AGENTS.md up to date. One OpenCode session per ticket: to resume, new session then /next.
- Sonar and Fortify run in the CI on every pushed commit: their results exist only after /ship, never before.
- You may run on a remote machine while I sometimes code in Rider on my Mac: then we do NOT share the same files. My Mac changes reach you only through git (I push from Rider, then /sync), and your changes reach my Mac only after /ship or /sync pushed them (then I pull in Rider). The ticket sheet exists only on your side.
- Ticket sheet: on a branch whose name contains a Jira key (pattern `[A-Z][A-Z0-9]+-[0-9]+`), the file `.git/opencode/tickets/<KEY>.md` holds the analysis of the ticket: acceptance criteria, expected tests, plan, and a "## Suivi" log. Read it before working on the ticket, unless the command already printed it in the workflow state. When you finish a step of its "Plan", tick it (`- [x]`) with the edit tool. Never commit it (it lives inside `.git`).
- When I ask "implémente l'étape N de la fiche" without /dev, follow the same rules as /dev: only that step, questions when the approach is unclear, build, tests, tick the step, record my answers in the sheet's "## Décisions", then stop.

## Routing (when I ask in plain words instead of a command)
- "pourquoi ça plante", a stack trace, a failing test → invoke the `debugger` subagent with the task tool.
- "fais-moi un plan", "comment tu ferais" for a feature or refactoring → invoke the `architect` subagent.
- "explique", "comment marche" → load the skill `explain-code` and follow it.
- "corrige le build", compilation errors, failed CI build job → load the skill `build-fix` and follow it.
- "fais comme dans <repo>", "inspire-toi de ce que j'ai fait sur <repo>" →
  1. If a skill `pattern-<name>-back` or `pattern-<name>-front` matches, load it: it is the reference (same as /apply-pattern).
  2. Otherwise read ONLY the files of that implementation in the other repository, read-only, with the read, grep and glob tools (ask me for its path if I did not give it).
  3. For each library or mechanism the source uses and this repository does not (Moq vs NSubstitute, FluentAssertions, AutoFixture, xUnit fixtures, Testcontainers, a mediator, FluentValidation…), ask me with the question tool, one question per item, all in one call: "Garder l'existant (<current>)" (recommandé) / "Introduire <thing> comme dans <source>". Wait for the answers.
  4. Adapt to this repository's conventions (naming, folders, DI, logging), never copy configuration values, URLs, hosts or secrets from the other repository, then plan and implement step by step with a build after each step.
  5. At the end, if no skill existed, suggest `/extract-pattern <name> <source repo path>` so the approach is reusable next time.
- "j'ai poussé depuis mon Mac", "j'ai commité dans Rider" → tell me to run `/sync` first (it retrieves the branch's remote changes), then continue.
- "j'ai fait l'étape N à la main", "j'ai modifié X dans Rider" → if the branch is behind its remote copy, tell me to run `/sync` first; then re-read the files from disk (never trust an older version you read earlier), read `git diff` for them, check the change against the step and the acceptance criteria of the ticket sheet, report what is missing or wrong in a few lines, tick the step if it is complete. Do not rewrite my code unless I ask.
- "où j'en suis", "on en est où", "et maintenant" → tell me to run `/next`.
- "y a-t-il une meilleure approche", "bonnes pratiques", "il manque quoi" → load the skill `best-practices`; for the whole repository, tell me to run `/audit`.
- "écris les tests", "teste ce fichier", "fais les tests comme dans <repo>" → tell me to run `/test`, `/test <file>` or `/test comme <repo or pattern>`.
- "vérifie les licences", "ce package est-il payant" → run `sh ~/.config/opencode/scripts/package-licenses.sh` (whole repository), `... branche` (packages changed on the branch) or `... <PackageId> [<version>]`, and summarize its result; this is what /licences does.
- "review", "vérifie avant de pousser" → tell me to run `/check`.
- commit, push, branch, merge, sync → tell me to run `/ship`, `/sync` or `/ticket`: you never run git writes yourself.
- Do not invoke subagents for anything else unless I ask.

## Daily
- Default scope of /daily: Jira project or board `[KEY or board name]`, GitLab group or projects `[group/path]`. Replace the placeholders, or delete this section to be asked each time.
- Jira URL (for the ticket links of /daily, /ticket and the other commands): `[https://jira.mycompany.com]`. Optional: without it, the URL returned by the Jira tools is used.

## Release groups
- Used by `/release-notes <group name>` to write one release note for several repositories deployed together. One block per group:
- `[GROUP]`: Confluence space `[SPACEKEY]`, release notes parent page `[page title]`, application name `[name]`, repositories:
  - `[Back]`: `[absolute path on the machine where OpenCode runs]/[back-repo]`
  - `[Front]`: `[absolute path on the machine where OpenCode runs]/[front-repo]`
  - `[Lib Infra]`: `[absolute path on the machine where OpenCode runs]/[lib-repo]`

## NuGet / Artifactory
- NuGet restore authenticates to Artifactory through the env vars `artifactory_user` and `artifactory_password`, already exported in the environment.
- Never print, echo, log or read these values or the files that define them.
- Never modify nuget.config to hardcode credentials.
- If `dotnet restore` fails with 401/403/NU1301, stop and tell me instead of trying workarounds.

## Fortify SSC (MCP)
- The SSC application name of each repository is the value of APPSEC_PROJECT_NAME in its appsec-ci.env file.
- /scans resolves the application version (current branch version if it has scans, otherwise develop); never guess application or version names.
- Never read appsec-ci.env entirely: it may contain secrets.
- Always use the filter set "Security Auditor View" unless I ask otherwise. If a filter or filter set is rejected, list the valid ones and retry with a listed value.

## Git
- Git writes (branch creation, commit, merge, push) go through the `git` agent and the /ticket, /sync and /ship commands. The team keeps branches up to date with develop by MERGE, never by rebase.
- Outside of them: never commit, push, merge, rebase, reset or delete branches unless I explicitly ask. Never force-push.
