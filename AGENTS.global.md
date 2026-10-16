# Global rules (merge into ~/.config/opencode/AGENTS.md)

## Language
- Answer me in French.
- Code, code comments, log messages, commit messages and test names are in English.

## Asking me
- When a decision is mine (which option, which version, which base branch, keep or change a library, fix or skip), do not stop and do not guess: ask me with the question tool, as a multiple-choice question with 2 to 4 short options, the recommended one first and marked "(recommandé)". I can always type another answer.
- One question at a time, only when the answer changes what you do. Do not ask for things you can find in the code, the git history or AGENTS.md.

## Working style
- Read existing code before writing new code, and mirror its conventions.
- Smallest change that solves the request. No unrelated refactoring, renaming or reformatting.
- Never claim success without running the build and test commands of the repository when code was changed.
- Never invent file paths, types, methods, package names, application names or filter names. Look them up, or ask.

## Project types
- I work on several kinds of repositories: .NET 10 APIs with Clean Architecture + CQRS, classic .NET APIs without CQRS, legacy .NET Framework web projects, libraries, and front-end projects.
- The project type is auto-detected by `sh ~/.config/opencode/scripts/detect-project-type.sh` (types: cqrs-api, api, dotnet-app, legacy, library, frontend; several can apply). A "Project type" section in the repository AGENTS.md overrides the detection.
- Follow the conventions of the existing code of the repository. Never introduce CQRS, a mediator or Clean Architecture layers in a project that does not already use them.
- For CQRS APIs only: in-house mediator, NOT MediatR (never add MediatR); load the skill `dotnet-cqrs-conventions` before writing or reviewing handlers.
- New libraries or approaches: by default, use what the repository already uses (the "Test stack" line of the project detection for tests; the existing packages for the rest). When a task would bring something the repository does not use yet (for example Moq, FluentValidation, a mediator, a new test framework), ask me before writing code with the question tool: "Garder l'existant (<what is used today>)" (recommandé) or "Introduire <new thing> (<packages to add, files impacted>)". Wait for my answer. If I choose the new thing: add it, use it for the new code only, and do not rewrite existing code unless I ask.
- If the repository has no tests at all, ask me with the question tool before creating a test project.
- Build and test with the commands from the section "Build & test" of the repository AGENTS.md if it exists, otherwise from the detection script. Legacy .NET Framework projects may not build on macOS: say so instead of changing project files.
- Integrations: SharePoint (CSOM), DocuSign, AWS S3, Piano Analytics. Load the skill `integrations-guardrails` before touching them. Never modify authentication or credentials handling without asking.

## Branches and releases
- Merge requests target `develop`. Production is deployed from `master` as is; there are no release tags.

## Available helpers (use them instead of improvising)
- Read-only review: `@reviewer`. Read-only debugging: `@debugger`. Read-only design: `@architect`. Tests only: `@test-writer`. Fortify: `@fortify`.
- Do not invoke these subagents on your own initiative unless I ask for a review, a plan, a debug investigation, tests or a Fortify analysis.

## NuGet / Artifactory
- NuGet restore authenticates to Artifactory through the env vars `artifactory_user` and `artifactory_password`, already exported in the environment.
- Never print, echo, log or read these values or the files that define them.
- Never modify nuget.config to hardcode credentials.
- If `dotnet restore` fails with 401/403/NU1301, stop and tell me instead of trying workarounds.

## Fortify SSC (MCP)
- The SSC application name of each repository is the value of APPSEC_PROJECT_NAME in its appsec-ci.env file.
- Use the /fortify command to resolve the application version; never guess application or version names.
- Never read appsec-ci.env entirely: it may contain secrets.
- Always use the filter set "Security Auditor View" unless I ask otherwise. If a filter or filter set is rejected, list the valid ones and retry with a listed value.

## Git
- Never push, force-push, rebase, reset or delete branches unless I explicitly ask.
- Never commit unless I explicitly ask.
