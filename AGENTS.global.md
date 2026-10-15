# Global rules (merge into ~/.config/opencode/AGENTS.md)

## Language
- Answer me in French.
- Code, code comments, log messages, commit messages and test names are in English.

## Working style
- Read existing code before writing new code, and mirror its conventions.
- Smallest change that solves the request. No unrelated refactoring, renaming or reformatting.
- Never claim success without running `dotnet build` and `dotnet test` when code was changed.
- If a request is ambiguous, ask one question before acting.
- Never invent file paths, types, methods, package names, application names or filter names. Look them up, or ask.

## .NET stack
- .NET 10, C#, Clean Architecture with CQRS, FluentValidation.
- In-house mediator, NOT MediatR. Never add MediatR. Load the skill `dotnet-cqrs-conventions` before writing or reviewing handlers.
- Integrations: SharePoint (CSOM), DocuSign, AWS S3, Piano Analytics. Load the skill `integrations-guardrails` before touching them. Never modify authentication or credentials handling without asking.

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
