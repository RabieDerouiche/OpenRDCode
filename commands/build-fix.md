---
description: "Build the solution and fix compilation errors only, with minimal changes"
agent: build
---
Build output (errors only):
!`dotnet build -nologo -v q 2>&1 | grep -E 'error [A-Z]+[0-9]+' | sort -u | head -60`

Fix the compilation errors listed above.

Rules:
- Fix only what is needed to compile. No refactoring, no renaming, no behavior change.
- If the list is empty, run `dotnet build` once to confirm and stop.
- If an error comes from NuGet restore (NU1101, NU1301, 401, 403), do not touch any file: tell me, credentials or Artifactory access are the cause.
- If an error comes from a missing MediatR reference, do not add MediatR back: list the files that still reference MediatR and stop.
- After fixing, run `dotnet build` again. Repeat at most 3 times, then report what remains.

Report: each error fixed (file:line, error code, change made) and the final build status.
