---
description: "Turn a good implementation from another repository into a reusable skill (pattern-<name>) that can be applied to any project later. Usage: /extract-pattern <name> <absolute path of the source repository>"
agent: build
---
Extract the "$1" implementation from the repository at `$2` and save it as a reusable skill.

Rules:
- Read-only on `$2`: never modify anything in the source repository.
- The ONLY file you may create or modify is `~/.config/opencode/skills/pattern-$1/SKILL.md`. Do not touch the current repository.
- The skill name must be `pattern-$1` in lowercase with hyphens only (letters, digits, single hyphens). If "$1" does not fit, propose a valid name and ask before writing.
- Never copy secrets, connection strings, internal URLs, hostnames, tokens, personal data or business data into the skill. Replace them with placeholders like `<HealthCheckUrl>`.
- Never invent code that is not in the source: generalize what exists, and mark any addition as "(suggestion)".

Steps:
1. Locate the implementation of "$1" in `$2` with the grep, glob and read tools: registration / startup code, classes, configuration (appsettings, options classes), endpoints, middleware, and the related tests.
2. Detect the source project type by reading its project files (.csproj target framework and SDK, package.json).
3. Separate what is essential to the pattern from what is specific to that project (business names, specific dependencies, environment values).
4. Write `~/.config/opencode/skills/pattern-$1/SKILL.md` with exactly this structure:

   ---
   name: pattern-$1
   description: <one sentence: what the pattern does and when to load it>
   compatibility: opencode
   ---
   # Pattern: <title>
   ## Source
   Repository name (folder name only), date of extraction, files the pattern comes from.
   ## When to use
   ## Prerequisites
   NuGet / npm packages with the exact versions found in the source, target framework constraints.
   ## Files to create or modify
   One line per file, with its role.
   ## Code
   Generalized code for each file, with placeholders for project-specific names. Comments in English.
   ## Registration and configuration
   DI registration, middleware order, configuration keys with placeholder values.
   ## Tests
   The test approach and generalized test code from the source.
   ## Adapting to other project types
   What changes for cqrs-api, api, dotnet-app, legacy (.NET Framework) and frontend, or "not applicable" when it does not make sense.
   ## Pitfalls
   Mistakes to avoid, deduced from the source code and its history (`git -C $2 log` on these files).

5. Final answer in French: the path of the skill, a 5-line summary of the pattern, and what you deliberately left out as project-specific.
