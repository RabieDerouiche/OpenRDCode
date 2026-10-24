---
name: build-fix
description: Rules for fixing compilation errors with minimal changes in .NET (10, 9, 8, netstandard, legacy) and front-end projects, including a C# feature or an API too new for the target framework, public API and package validation errors, restore/Artifactory errors and the MediatR ban. Load when asked to fix the build, compilation errors or a failed CI build job.
compatibility: opencode
---
# Fixing the build

## Get the errors
- Build command: the "Build & test" section of the repository AGENTS.md if it exists, otherwise `sh ~/.config/opencode/scripts/detect-project-type.sh` (line "Build").
- .NET, errors only: `sh ~/.config/opencode/scripts/build-test.sh --build-only [<solution or project>]` (each error once, then "BUILD: OK" or "BUILD: FAILED"). A line "ENVIRONMENT PROBLEM" means that `dotnet` or the package feed is not reachable from OpenCode: say it in one line and stop.
- Front-end, the folder of its package.json: `sh ~/.config/opencode/scripts/build-test.sh --build-only <folder>` (its build script; "BUILD: OK" or "BUILD: FAILED (exit <n>, <k> errors)" after the error lines). A repository without .NET: `… build-test.sh --build-only` alone.
- For a failed CI job, start from the error lines of the job log given by the user or gathered by /fix.

## Rules
- Fix only what is needed to compile. No refactoring, no renaming, no behavior change.
- Legacy .NET Framework projects may not build on this machine (.NET Framework needs Windows): if the build fails because the target framework is not supported, say so and stop. Do not change target frameworks or project files to make it build.
- Restore errors (NU1301, 401, 403, npm E401/E403): do not touch any file and do not investigate (never read nuget.config, NuGet.Config, `.npmrc` or environment variables). Tell the user in one line that registry access is the cause (Artifactory), then stop. NU1101 (package not found) is different: check the package name and version in the project file.
- An in-house package behaves like an older build although its version did not change (the package was republished in Artifactory with the same version): the NuGet cache keeps the first copy of each version. Ask me before deleting `~/.nuget/packages/<package id in lowercase>/<version>/`, then run `dotnet restore --force --no-cache`. The real fix is a new version number: say so.
- Missing MediatR reference: never add MediatR back. List the files that still reference MediatR and stop.
- A C# feature newer than the project's language version (CS9202 « Feature … is not available in C# 12.0. Please use language version 13 or greater » in a net8.0 project, CS9260 for C# 13, CS9058 for C# 11, CS8652 a preview feature), or an API the target framework lacks (CS0117, CS1061, CS0246 on a .NET 9 or 10 type in a net8.0 project, a netstandard2.0 target of a multi-target project): rewrite the code with what the project's version has (the « C# » and « Target frameworks » lines of `detect-project-type.sh`). Never raise LangVersion, change a TargetFramework or global.json, or add a polyfill package.
- RS0016 / RS0017 (PublicApiAnalyzers): a public member added or removed: add its line to `PublicAPI.Unshipped.txt` (the code fix of the analyzer writes it), never a suppression; a removed member is a breaking change: say so.
- CP0001 to CP0021 at `dotnet pack` (package validation): the public API breaks the last published package. Restore what was removed or changed (an overload, the old signature kept and marked `[Obsolete]`), unless the ticket decided a major version: never a `CompatibilitySuppressions.xml` written to hide it.
- NETSDK1045 (an SDK too old for the target framework), NETSDK1147 (a workload), NETSDK1100 (a Windows project), MSB3644 (.NET Framework reference assemblies), a missing runtime of the tests: `build-test.sh` says ENVIRONMENT PROBLEM: the machine, not the code: stop.
- Front-end: TypeScript errors (TS2304, TS2339, TS2345…) are fixed in the code like C# errors; a module not found after a change of package.json, or a lockfile out of sync ("STOP: the lockfile"), is the developer's: never install or upgrade a package.
- After fixing, build again. Repeat at most 3 times, then report what remains.

## Report
Each error fixed (file:line, error code, change made) and the final build status. In the conversation (not in a run of /go or /fix, whose report format wins): then the « Suite » question (question tool, header « Suite »): « /push (recommandé) » (« il builde, teste, commite et pousse »), « Rien pour l'instant »; the pack starts the command I choose: answer only « Je lance /push. ».
