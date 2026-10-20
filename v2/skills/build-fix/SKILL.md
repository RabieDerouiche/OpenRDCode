---
name: build-fix
description: Rules for fixing compilation errors with minimal changes in .NET (modern or legacy) and front-end projects, including restore/Artifactory errors and the MediatR ban. Load when asked to fix the build, compilation errors or a failed CI build job.
compatibility: opencode
---
# Fixing the build

## Get the errors
- Build command: the "Build & test" section of the repository AGENTS.md if it exists, otherwise `sh ~/.config/opencode/scripts/detect-project-type.sh` (line "Build").
- .NET, errors only: `sh ~/.config/opencode/scripts/build-test.sh --build-only [<solution or project>]` (each error once, then "BUILD: OK" or "BUILD: FAILED"). A line "ENVIRONMENT PROBLEM" means that `dotnet` or the package feed is not reachable from OpenCode: say it in one line and stop.
- If the output mentions MSB1003 / MSB1011 or the project is not a .NET SDK project, ignore it and use the build command from AGENTS.md instead (front-end default: `npm run build`).
- For a failed CI job, start from the error lines of the job log given by the user or by /scans.

## Rules
- Fix only what is needed to compile. No refactoring, no renaming, no behavior change.
- Legacy .NET Framework projects may not build on this machine (.NET Framework needs Windows): if the build fails because the target framework is not supported, say so and stop. Do not change target frameworks or project files to make it build.
- Restore errors (NU1301, 401, 403, npm E401/E403): do not touch any file and do not investigate (never read nuget.config, NuGet.Config, `.npmrc` or environment variables). Tell the user in one line that registry access is the cause (Artifactory), then stop. NU1101 (package not found) is different: check the package name and version in the project file.
- An in-house package behaves like an older build although its version did not change (the package was republished in Artifactory with the same version): the NuGet cache keeps the first copy of each version. Ask me before deleting `~/.nuget/packages/<package id in lowercase>/<version>/`, then run `dotnet restore --force --no-cache`. The real fix is a new version number: say so.
- Missing MediatR reference: never add MediatR back. List the files that still reference MediatR and stop.
- After fixing, build again. Repeat at most 3 times, then report what remains.

## Report
Each error fixed (file:line, error code, change made) and the final build status. Then: "Prochaine étape : /check".
