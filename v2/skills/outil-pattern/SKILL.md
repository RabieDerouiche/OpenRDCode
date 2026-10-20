---
name: outil-pattern
description: "Procédure de /outil pattern : extract crée ou enrichit un skill pattern-<nom>-<back|front> depuis une bonne implémentation d'un autre dépôt (packages internes décrits par leurs appels dans le code, jamais en ouvrant les DLL) ; apply ajoute au plan du ticket les étapes qui appliquent ce pattern au dépôt courant, puis /go les code. Arguments : extract <nom> <dépôt source> [où] | apply <nom> [back|front] [consignes]."
compatibility: opencode
---
# /outil pattern

The "Action" line above says which part applies. An action missing: say « Précise l'action : `/outil pattern extract <nom> <dépôt source> [où]` ou `/outil pattern apply <nom> [back|front] [consignes]` » and stop.

## extract

Extract the "<name>" implementation of the source repository into a reusable skill, or enrich the existing one. The name and the source repository are on the "Action" line above; my indications are the rest of the "Arguments" line (optional: `back` or `front`, and where the implementation is: a Jira key, class, interface or folder names).

Paths: the source repository is the "Repository root" line of the source detection above. Use that absolute path in every tool call, never `~` (the read, grep, glob and write tools do not expand it). The skill file is written at its absolute path, given above.

Rules:
- Read-only on the source repository. The ONLY file you create or modify is the skill file of step 3; nothing in the current repository.
- Packages: everything the skill needs about them (ids, versions, in-house or not, frameworks they ship, XML documentation, dependencies) is in "Packages du dépôt source" above. Never list, search, open, run or decompile anything under `~/.nuget`, a `.dll` or a `.nupkg` (no reflection program, no project in /tmp, no ildasm, ilspy or `strings`): these commands are refused, and the skill does not need them.
- In-house packages are described by what the SOURCE CODE does with them, copied verbatim: the namespaces it imports, what it registers, injects, creates and calls, and the configuration it gives them. What the source code does not show (the type behind a `var`, whether a type is an interface, a member it never calls, how the package works inside) is never searched for: write `(à vérifier : <question>)` in the skill and list the question in your final answer; I answer it from Rider. One exception: for a member the source calls, the XML documentation file listed in "Packages" may be searched with the grep tool on that member name, to get its parameter types.
- A package "Not in the package cache of this machine" is in-house when its id starts like an in-house package above or like the source's own namespaces; otherwise it comes from nuget.org; when unsure, write "(à vérifier : interne ?)" next to it. Front-end: the dependencies of `package.json`; a package of the company's npm scope is in-house, and for a member the source calls, its type declarations (`node_modules/<package>/**/*.d.ts`) may be searched with the grep tool.
- Keep verbatim everything that comes from a package: ids and versions, namespaces, type and member names, extension methods (`services.AddXxx(...)`), attributes, and the configuration sections the package reads. Placeholders (`<FeatureName>`, `<BucketName>`) replace only what belongs to the source project: its namespaces, feature and entity names, and every value.
- Never copy secrets, connection strings, URLs, hostnames, cloud resource identifiers (bucket names, KMS key ids or ARNs, account ids, role names), encryption keys, initialization vectors, salts, certificates or their thumbprints, tokens, personal or business data: placeholders instead. For a secret, write where the source gets it (configuration key, environment variable name, secret store), never its value.
- Never invent code that is not in a source: generalize what exists, and mark any addition as "(suggestion)".
- Never delete content from an existing skill unless a source proves it wrong; when two sources differ, keep both as variants.
- Reading budget: the three turns of step 4, nothing more. If the implementation is larger, the skill covers its core (registration, the classes that call the in-house packages, their configuration and their tests) and your final answer lists what was left out.

Steps:
1. Before reading anything:
   - A line above says "folder not found" or "not a git repository": answer « Dépôt source introuvable : relance `/outil pattern extract <name> <chemin absolu du dépôt source> …` » and stop.
   - The "Compared with" line says BEHIND, or a "Development" block says the checked-out branch does NOT contain the development (or only part of it): ask me with the question tool: "Continuer avec cette version (<checked-out branch>)" / "J'arrête : je fais le checkout de <the base branch, or the branch of the development> dans le dépôt source puis je relance" (recommended when the development is not in the checkout). For the second answer, stop.
2. Scope: `back` or `front` if my indications say so; otherwise from the detection above: `frontend` or `blazor` (Razor components) → `front`; any other .NET type → `back`. In a mixed repository (back and front, or a Blazor app with its own services), the scope is the side where the implementation lives; if it exists on both sides, extract the back-end one and say so.
3. Name: `pattern-<name>-<scope>`, in lowercase with hyphens only (letters, digits, single hyphens); if the name does not fit, take the closest valid one and say so. Its file is the "Skill file" line above for this scope.
4. Locate and read, in at most three turns, all the calls of a turn sent together:
   - Turn 1, in this order:
     a. FIRST, one `grep` whose path is the source root, on `using <id>` of each in-house package above and on the names of my indications (otherwise the main names of the pattern: classes, interfaces, configuration sections). Being the first call on that folder, its approval covers the whole source repository (I answer "always"); a read sent before it would ask again for every subfolder.
     b. If a "Development" block above lists files: the reads of its code, configuration and test files that are in the checkout, at most 12, the most central first (registration, the classes that use the in-house packages, configuration, tests).
     c. The read of the existing skill file, if the line above says it exists.
   - Turn 2. The files that turn 1 points to and that a section of the skill needs: registration / startup (Program.cs, DI extension methods), the classes that use the in-house packages, options classes, configuration (`appsettings*.json`: keys only), endpoints or components, and their tests; at most 12. In the same turn: `git -C <source root> log --oneline -10 -- <the main files>`.
   - Turn 3, only if a section of the skill is still empty: the files it needs, at most 6. Then stop reading, even if something is missing: it becomes `(à vérifier : …)`.
5. If the skill file does NOT exist: prepare it with the structure below. If it EXISTS: MERGE:
   - Add the repository to "Sources" (do not add it twice; if it is already listed, refresh its entry).
   - What both sources do the same way stays in "Code" as the common approach.
   - What differs goes to "Variants": one subsection per approach, with the source repository, its project type and test stack, the code and when to prefer it. Differences that only come from the test stack (e.g. Moq vs NSubstitute syntax) are not separate variants: note them in one line, since /outil pattern apply translates tests to the target's stack.
   - "In-house API used": add the packages and calls of this source; a package whose version differs keeps one subsection per version.
   - Update "Recommended approach" and explain the choice in one or two sentences (more complete, better tested, more recent, simpler).
   - Add new pitfalls, prerequisites and tests; keep the existing ones. An "(à vérifier : …)" that this source answers is replaced by the answer.
   - Never mix front-end and back-end content in the same skill: if this source does not match the scope of the existing skill, ask me with the question tool (multiple choice, recommended option first): "Créer le skill de l'autre scope" / "Annuler".
6. Check: one `grep` in the source root with every in-house namespace, type, member and configuration section the skill names (alternation `Name1|Name2|...`). Remove what is not found, or mark it `(à vérifier : introuvable dans la source)`.
7. Write the skill file with the write tool, at its absolute path.

Skill structure:

   ---
   name: pattern-<name>-<scope>
   description: <one sentence: what the pattern does, back-end or front-end, and when to load it>
   compatibility: opencode
   metadata: { scope: <back|front> }
   ---
   # Pattern: <title> (<back-end|front-end>)
   ## Sources
   One line per source: repository folder name, project type, test stack (the "Test stack" line of the detection above), checked-out branch and commit, Jira key if given, date of extraction, files used.
   ## When to use
   ## Recommended approach
   Which approach to use by default, and why.
   ## Prerequisites
   - Packages with the exact versions of "Packages du dépôt source", nuget.org and in-house; in-house ones marked "interne": they are reused as is, never re-implemented.
   - Target frameworks of the source projects, and for each in-house package the frameworks it ships (from "Packages"): a project whose framework none of them supports cannot use the package (`netstandard2.0` works from .NET Framework 4.7.2 and .NET Core 2.0; `net8.0` needs .NET 8 or newer).
   ## In-house API used
   One subsection per in-house package that the implementation uses:
   ### <package id> <version> (interne)
   - Ships: <frameworks> · XML documentation: <yes or no> · Depends on: <dependencies, from "Packages">
   - Namespaces: the `using` lines of the source.
   - Registration: the DI calls as written (e.g. `services.AddXxx(configuration.GetSection("Xxx"));`), with the file they come from.
   - Configuration it reads: sections and keys; values as placeholders; for a secret, where it comes from.
   - Types used: each type, and how the source gets it (injected into <class>, created with `new`, static call).
   - Calls: each call as the source writes it, with the lines that prepare its arguments and use its result (`await`, `using` / `await using`, cancellation token, stream position, try/catch around it), in a code block.
   - In tests: how the tests fake it or use it, as written.
   - À vérifier: the questions the source cannot answer, or "rien".
   /outil pattern apply writes these calls as they are: they are the reference, not a description.
   ## Files to create or modify
   One line per file, with its role.
   ## Code
   The common code, with placeholders for the names of the source project only. Comments in English.
   ## Variants
   One subsection per differing approach, with its source and when to prefer it. "None" if all sources agree.
   ## Registration and configuration
   DI registration or module/provider setup, middleware or interceptor order. Configuration: one table of keys (full path, e.g. `Storage:S3:BucketName`) with, per environment file found in the source (`appsettings.json`, `appsettings.<Environment>.json`), whether the key is set there, and a placeholder value. Mark keys that hold secrets (keys, passwords, tokens) as "secret: environment variable or secret store, never in appsettings".
   ## Tests
   The test approach and the test code, with how the in-house types are faked.
   ## Adapting to other project types
   Back-end: cqrs-api, api, dotnet-app, legacy (.NET Framework: only with in-house packages that ship `netstandard2.0` or `net4x`). Front-end: Angular, React, Vue, Blazor as relevant. "Not applicable" where it does not make sense.
   ## Pitfalls

8. Final answer in French:
   - the skill path, "créé" or "enrichi", and a 5-line summary;
   - the in-house packages and their versions;
   - what changed compared with the previous version of the skill (if enriched);
   - what you deliberately left out: project-specific, or beyond the reading budget;
   - "Questions pour toi": every `(à vérifier : …)` of the skill, numbered, or "aucune". I answer from Rider, then tell you « complète le skill avec : … », and you edit the skill file only;
   - last line: « Pour l'appliquer : nouvelle session sur le dépôt cible, sur la branche du ticket, puis /outil pattern apply <name>. Pour que /go le propose dans ses plans, redémarre OpenCode : il charge les skills à l'ouverture d'un projet. »

## apply

Apply the pattern "<name>" (the "Action" line above) to the current repository. My indications: the rest of the "Arguments" line (optional: `back` or `front`, and directives for this application). Decide, do not ask: every choice is a decision with its reason, recorded in the ticket sheet, that the merge request will show; the only questions are the `(à vérifier : …)` of the skill this application depends on, all in ONE question tool call.

Rules:
- The pattern is the skill FILE listed above ("Skills de pattern de cette machine"), read with the read tool at its absolute path; never through the skill tool, which only knows the skills that existed when OpenCode opened this project.
- Packages: compare with "Packages de ce dépôt" above. Never list, search, open, run or decompile anything under `~/.nuget`, a `.dll` or a `.nupkg` (no reflection program, no project in /tmp, no ildasm, ilspy or `strings`): these commands are refused.
- In-house packages: their calls are the ones of the skill's "In-house API used" (older skills: its "Code"), written as they are; /go's coder fixes a compilation error on them from the compiler message and the XML documentation of the package, never by decompiling or re-implementing it.
- The skill's `(à vérifier : …)` questions that this application depends on are the only questions: one call, free answers; never guess them.
- Placeholders of the skill are replaced with values of this repository or its configuration; an unknown value is a question for me, never invented, never copied from another project.
- My directives override the defaults of this command, never the hard rules (security, secrets, no MediatR, never commit, never copy configuration values from another project).

Steps:
0. No ticket sheet in the workflow state (not on a ticket branch): show the plan of step 7 only and say « Démarre le ticket avec /go <KEY>, puis relance /outil pattern apply <name> : les étapes s'ajouteront à son plan. » Write no code.
1. Scope: `back` or `front` if my indications say so; otherwise from the project type (AGENTS.md "Project type" wins): `frontend` → `front`, any .NET type → `back`. A mixed repository without scope: `back`, said in the answer.
2. Skill: the "Skill file" line of this scope above. If it does not exist, say which pattern skills exist and stop. Read it fully, in the same turn as the searches of step 4; if the pattern touches SharePoint/CSOM, DocuSign, AWS S3 or Piano Analytics, also load the skill `integrations-guardrails` in that turn.
3. Approach: from "Recommended approach", "Variants" and "Adapting to other project types", keep only what applies to this project type: the skill's recommended approach unless it does not fit, with the reason. If the pattern does not apply to this type, say so and stop.
4. Existing code, searched in one turn: what this repository already has for this pattern (partial or different implementation: never duplicate a mechanism, complete or align it instead), and the files the pattern touches here (Program.cs or Startup, DI extensions, `appsettings*.json` or `web.config` transforms, the project files).
5. Libraries, decided: a library of the pattern that this repository does not use (test framework, mocking, assertions, validation…) → keep the existing one and translate the pattern's code and tests to it (for example Moq syntax to NSubstitute); no test project here → no tests, said in the answer.
6. Prerequisites, compared with "Packages de ce dépôt":
   - Framework: an in-house package whose shipped frameworks support none of the target frameworks of the project that will use it cannot be used there (`net8.0` needs .NET 8 or newer; `netstandard2.0` works from .NET Framework 4.7.2 and .NET Core 2.0): say so and stop. A legacy .NET Framework project cannot use packages that require .NET Core or newer either.
   - In-house packages, same ids: same version → nothing to decide; older here → move to the version of the skill (its calls are written for it); newer here → keep it; not referenced → the version of the skill. Other packages: the same, and a package of the "Licenses" list of your instructions in a paid version → its free version or option.
   - Packages are added the way this repository does it: central package management (`Directory.Packages.props`) or the project file, following AGENTS.md.
7. Plan: steps that each leave the project building, with their files and their tests, configuration keys to add per environment file with the skill's placeholders (secrets come from environment variables or the secret store, never from appsettings).
8. With the edit tool, in one turn (exact lines of the sheet printed above): append the steps to "## Plan" as unchecked steps, numbered after the existing ones, `- [ ] <n>. <step> — fichiers : <paths> — tests : <names> (s'appuyer sur le skill pattern-<name>-<scope>)`; add their tests to "Tests attendus" with the status « à écrire »; add the decisions of steps 3, 5 and 6 to "## Décisions" (`- <topic> : <choice> — <reason> (pattern <name>)`, the section created before "## Suivi" if missing); append to "## Suivi" `- <date> /outil pattern apply <name> - <n> étapes ajoutées au plan` (date: the "Now" line of the workflow state).
9. Answer in French: the steps added, the decisions with their reasons, the answers to the `(à vérifier : …)` questions; then ask me with the question tool (header "Suite"): "/go <KEY> (recommandé)" (description: « code ces étapes, les teste, pousse et met la MR à jour ») and "Rien pour l'instant"; the pack plugin starts the command I choose by itself as soon as your turn ends: then answer only « Je lance /go <KEY>. ».
