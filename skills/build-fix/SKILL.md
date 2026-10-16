---
name: build-fix
description: Rules for fixing compilation errors with minimal changes in .NET (modern or legacy) and front-end projects, including restore/Artifactory errors and the MediatR ban. Load when asked to fix the build, compilation errors or a failed CI build job.
compatibility: opencode
---
# Fixing the build

## Get the errors
- Build command: the "Build & test" section of the repository AGENTS.md if it exists, otherwise `sh ~/.config/opencode/scripts/detect-project-type.sh` (line "Build").
- .NET, errors only: `dotnet build -nologo -v q 2>&1 | grep -E 'error [A-Z]+[0-9]+|MSB1003|MSB1011' | sort -u | head -60`.
- If the output mentions MSB1003 / MSB1011 or the project is not a .NET SDK project, ignore it and use the build command from AGENTS.md instead (front-end default: `npm run build`).
- For a failed CI job, start from the error lines of the job log given by the user or by /scans.

## Rules
- Fix only what is needed to compile. No refactoring, no renaming, no behavior change.
- Legacy .NET Framework projects may not build on macOS: if the build fails because the target framework is not supported, say so and stop. Do not change target frameworks or project files to make it build.
- Restore errors (NU1101, NU1301, 401, 403, npm E401/E403): do not touch any file. Tell the user that credentials or registry access are the cause (Artifactory).
- Missing MediatR reference: never add MediatR back. List the files that still reference MediatR and stop.
- After fixing, build again. Repeat at most 3 times, then report what remains.

## Report
Each error fixed (file:line, error code, change made) and the final build status. Then: "Prochaine étape : /check".
