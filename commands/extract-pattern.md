---
description: "Create or enrich a reusable skill (pattern-<name>-back or pattern-<name>-front) from a good implementation in a repository. Run it again on another repository to merge its approach into the same skill. Usage: /extract-pattern <name> <path of the source repository> [back|front]"
agent: dev
---
Source repository (detection, absolute root, build and CI files):
[[run detect-project-type.sh --files '$2']]

Pattern skills on this machine:
[[run pattern-skills.sh '$1']]

Extract the "$1" implementation from the source repository and save it as a reusable skill, or enrich the existing one. The source repository is the "Repository root" line above: use that absolute path in every tool call, never `~` (the read, grep, glob and write tools do not expand it). The skill file is written at its absolute path, given above.

Rules:
- Read-only on the source repository: never modify anything there.
- The ONLY file you may create or modify is the skill file of step 2. Do not touch the current repository.
- In-house packages are described from the outside: what the source code imports, injects, calls and configures, copied from the source code. Never open, list, run or decompile a package or an assembly (no reflection program, no project in /tmp, no ildasm, ilspy or `strings`), and never read a package's internals: what the source code does not show is not needed. Their XML documentation (`~/.nuget/packages/...`) only when a call of the source cannot be understood without it.
- Keep verbatim everything that comes from a package: package ids and versions, namespaces, type and member names, extension methods (`services.AddXxx(...)`), attributes, and the configuration sections the package reads. Placeholders (`<FeatureName>`, `<BucketName>`) only replace what belongs to the source project: its namespaces, feature and entity names, and every value.
- Never copy secrets, connection strings, URLs, hostnames, cloud resource identifiers (bucket names, KMS key ids or ARNs, account ids, role names), encryption keys or initialization vectors, tokens, personal or business data: placeholders instead.
- Never invent code that is not in a source: generalize what exists, and mark any addition as "(suggestion)".
- Never delete content from an existing skill unless a source proves it wrong; when two sources differ, keep both as variants.

Steps:
1. Scope: "$3" if given (`back` or `front`); otherwise from the detection above: `frontend` or `blazor` (Razor components) → `front`; any other .NET type → `back`. In a mixed repository (back and front, or a Blazor app with its own services), look where the "$1" implementation lives; if it exists on both sides, ask me with the question tool (multiple choice, recommended option first): "back" / "front".
2. Name: `pattern-$1-<scope>`, in lowercase with hyphens only (letters, digits, single hyphens); if "$1" does not fit, ask me with the question tool with 2 valid name proposals. Its file is the "Skill file" line above for this scope.
3. Locate the implementation, in ONE turn: one `grep` whose path is the source root, on the main names of "$1" (classes, interfaces, configuration sections, package ids) — OpenCode asks me once for this folder, I answer "Toujours"; the read of the source project files that reference the in-house packages; and the read of the existing skill file if the line above says it exists. Then, in one turn, read the files of the implementation: registration / startup, the classes that use the in-house packages, configuration (`appsettings*.json`: keys only), endpoints or components, and their tests. History: `git -C <source root> log --oneline -20 -- <files>`.
   Stop reading as soon as every section of the skill can be filled: no file outside this implementation, no package internals.
4. If the skill file does NOT exist: prepare it with the structure below. If it EXISTS: MERGE:
   - Add the repository to "Sources" (do not add it twice; if it is already listed, refresh its entry).
   - What both sources do the same way stays in "Code" as the common approach.
   - What differs goes to "Variants": one subsection per approach, with the source repository, its project type and test stack, the code and when to prefer it. Differences that only come from the test stack (e.g. Moq vs NSubstitute syntax) are not separate variants: note them in one line, since /apply-pattern translates tests to the target's stack.
   - Update "Recommended approach" and explain the choice in one or two sentences (more complete, better tested, more recent, simpler).
   - Add new pitfalls, prerequisites and tests; keep the existing ones.
   - Never mix front-end and back-end content in the same skill: if this source does not match the scope of the existing skill, ask me with the question tool (multiple choice, recommended option first): "Créer le skill de l'autre scope" / "Annuler".
5. Check: one `grep` in the source root with every in-house type, member and configuration section the skill names (alternation `Name1|Name2|...`). Remove what is not found, or mark it "(à vérifier)".
6. Write the skill file with the write tool, at its absolute path.

Skill structure:

   ---
   name: pattern-$1-<scope>
   description: <one sentence: what the pattern does, back-end or front-end, and when to load it>
   compatibility: opencode
   metadata: { scope: <back|front> }
   ---
   # Pattern: <title> (<back-end|front-end>)
   ## Sources
   One line per source: repository folder name, project type, test stack (the "Test stack" line of the detection above), date of extraction, files used.
   ## When to use
   ## Recommended approach
   Which approach to use by default, and why.
   ## Prerequisites
   Packages with the exact versions found in each source, target framework or framework version constraints. In-house packages (company feed, e.g. Artifactory) are marked "interne", with their exact ids and versions: they are reused as is, never re-implemented.
   ## In-house API used
   For each in-house package: the namespaces imported, the types injected or created, and every call as the source writes it (arguments, how the result is used, `await` and cancellation token included), copied from the source code. /apply-pattern writes these calls as they are: they are the reference, not a description.
   ## Files to create or modify
   One line per file, with its role.
   ## Code
   The common code, with placeholders for the names of the source project only. Comments in English.
   ## Variants
   One subsection per differing approach, with its source and when to prefer it. "None" if all sources agree.
   ## Registration and configuration
   DI registration or module/provider setup, middleware or interceptor order. Configuration: one table of keys (full path, e.g. `Storage:S3:BucketName`) with, per environment file found in the source (`appsettings.json`, `appsettings.<Environment>.json`), whether the key is set there, and a placeholder value. Mark keys that hold secrets (keys, passwords, tokens) as "secret: environment variable or secret store, never in appsettings".
   ## Tests
   The test approach and the test code, with how the in-house interfaces are faked.
   ## Adapting to other project types
   Back-end: cqrs-api, api, dotnet-app, legacy (.NET Framework). Front-end: Angular, React, Vue, Blazor as relevant. "Not applicable" where it does not make sense.
   ## Pitfalls

7. Final answer in French: the skill path, "créé" or "enrichi", a 5-line summary, the in-house packages and versions, what changed compared to the previous version of the skill (if enriched), and what you deliberately left out as project-specific. Last line: "/apply-pattern lit ce fichier directement. Pour que /ticket et /dev le proposent dans leurs plans, redémarre OpenCode : il charge les skills à l'ouverture d'un projet."
