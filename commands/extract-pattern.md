---
description: "Create or enrich a reusable skill (pattern-<name>-back or pattern-<name>-front) from a good implementation in a repository. Run it again on another repository to merge its approach into the same skill. Usage: /extract-pattern <name> <absolute path of the source repository> [back|front]"
agent: dev
---
Source repository detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh '$2'`

Extract the "$1" implementation from the repository at `$2` and save it as a reusable skill, or enrich the existing one.

Rules:
- Read-only on `$2`: never modify anything in the source repository.
- The ONLY file you may create or modify is the skill file defined in step 2. Do not touch the current repository.
- Never copy secrets, connection strings, internal URLs, hostnames, tokens, personal data or business data into the skill. Replace them with placeholders like `<HealthCheckUrl>`.
- Never invent code that is not in a source: generalize what exists, and mark any addition as "(suggestion)".
- Never delete content from an existing skill unless it is proven wrong by a source; when two sources differ, keep both as variants.

Steps:
1. Determine the scope:
   - If a third argument is given ("$3"), use it: `back` or `front`.
   - Otherwise use the source repository detection above: `frontend` or `blazor` (Razor components) → `front`; any other .NET type → `back`. If the repository is mixed (back and front, or a Blazor app with its own services), look where the "$1" implementation lives; if it exists on both sides, ask me with the question tool (multiple choice, recommended option first): "back" / "front".
2. The skill name is `pattern-$1-<scope>` in lowercase with hyphens only (letters, digits, single hyphens); if "$1" does not fit, ask me with the question tool (multiple choice, recommended option first) with 2 valid name proposals. The file is `~/.config/opencode/skills/pattern-$1-<scope>/SKILL.md`.
3. Locate the implementation of "$1" in `$2` with the grep, glob and read tools: registration / startup code, classes, configuration, endpoints, middleware, components, services, and the related tests. Read `git -C $2 log --oneline -20 -- <files>` for the history of these files. Send the searches together in one turn, with the read of the existing skill file of step 4 (it may not exist).
4. If the skill file does NOT exist: create it with the structure below.
   If it EXISTS: read it fully, then MERGE:
   - Add the repository to "Sources" (do not add it twice; if it is already listed, refresh its entry).
   - What both sources do the same way stays in "Code" as the common approach.
   - What differs goes to "Variants": one subsection per approach, with the source repository, its project type and test stack, the code and when to prefer it. Differences that only come from the test stack (e.g. Moq vs NSubstitute syntax) are not separate variants: note them in one line, since /apply-pattern translates tests to the target's stack.
   - Update "Recommended approach" and explain the choice in one or two sentences (more complete, better tested, more recent, simpler).
   - Add new pitfalls, prerequisites and tests; keep the existing ones.
   - Never mix front-end and back-end content in the same skill: if this source does not match the scope of the existing skill, ask me with the question tool (multiple choice, recommended option first): "Créer le skill de l'autre scope" / "Annuler".

Skill structure:

   ---
   name: pattern-$1-<scope>
   description: <one sentence: what the pattern does, back-end or front-end, and when to load it>
   compatibility: opencode
   metadata: { scope: <back|front> }
   ---
   # Pattern: <title> (<back-end|front-end>)
   ## Sources
   One line per source: repository folder name, project type, test stack (from the "Test stack" line of the detection script run on the source), date of extraction, files used.
   ## When to use
   ## Recommended approach
   Which approach to use by default, and why.
   ## Prerequisites
   Packages with the exact versions found in each source, target framework or framework version constraints. Mark in-house packages (from the company feed, e.g. Artifactory) as "interne" and keep their exact names: they are reused as is, never re-implemented.
   ## Files to create or modify
   One line per file, with its role.
   ## Code
   The common, generalized code with placeholders for project-specific names. Comments in English.
   ## Variants
   One subsection per differing approach, with its source and when to prefer it. "None" if all sources agree.
   ## Registration and configuration
   DI registration or module/provider setup, middleware or interceptor order. Configuration: one table of keys (full path, e.g. `Storage:S3:BucketName`) with, per environment file found in the source (`appsettings.json`, `appsettings.<Environment>.json`), whether the key is set there, and a placeholder value. Mark keys that hold secrets (keys, passwords, tokens) as "secret: environment variable or secret store, never in appsettings".
   ## Tests
   The test approach and generalized test code.
   ## Adapting to other project types
   Back-end: cqrs-api, api, dotnet-app, legacy (.NET Framework). Front-end: Angular, React, Vue, Blazor as relevant. "Not applicable" where it does not make sense.
   ## Pitfalls

5. Final answer in French: the skill path, "créé" or "enrichi", a 5-line summary, what changed compared to the previous version of the skill (if enriched), and what you deliberately left out as project-specific.
