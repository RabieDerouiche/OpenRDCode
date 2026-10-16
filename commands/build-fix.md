---
description: "Build the project and fix compilation errors only, with minimal changes (.NET or front-end)"
agent: build
---
.NET build output (errors only, empty or "no project" if this is not a .NET repository):
!`dotnet build -nologo -v q 2>&1 | grep -E 'error [A-Z]+[0-9]+|MSB1003|MSB1011' | sort -u | head -60`

Fix the compilation errors of this project.

Rules:
- Read the sections "Project type" and "Build & test" of AGENTS.md first.
- If the output above mentions MSB1003 / MSB1011 or the project is not a .NET SDK project, ignore it: run the build command from AGENTS.md instead (front-end default: `npm run build`).
- Legacy .NET Framework projects may not build on macOS: if the build fails because the target framework is not supported, say so and stop. Do not change target frameworks or project files to make it build.
- Fix only what is needed to compile. No refactoring, no renaming, no behavior change.
- If an error comes from package restore (NU1101, NU1301, 401, 403, npm E401/E403), do not touch any file: tell me, credentials or registry access are the cause.
- If an error comes from a missing MediatR reference, do not add MediatR back: list the files that still reference MediatR and stop.
- After fixing, build again. Repeat at most 3 times, then report what remains.

Report: each error fixed (file:line, error code, change made) and the final build status.
