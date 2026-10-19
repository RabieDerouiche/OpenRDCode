---
description: "Apply a pattern saved with /extract-pattern to the current repository: pick the back or front version, compare, ask the decisions, plan. With a ticket sheet, the plan goes into it and /dev implements it step by step; without one, step 1 is implemented here. Usage: /apply-pattern <name> [back|front] [directives, e.g. « sans nouvelle lib »]"
agent: dev
---
Workflow state (no fetch: the branch and its ticket sheet):
[[run workflow-state.sh --no-fetch --sheet]]
Project detection:
[[run detect-project-type.sh]]
Packages of this repository:
[[run package-refs.sh]]
Pattern skills on this machine:
[[run pattern-skills.sh '$1']]

Apply the pattern "$1" to the current repository. My indications: "$2" (optional: `back` or `front`, and directives for this application).

Rules:
- The pattern is the skill FILE listed above, read with the read tool at its absolute path; never through the skill tool, which only knows the skills that existed when OpenCode opened this project.
- Packages: compare with "Packages of this repository" above. Never list, search, open, run or decompile anything under `~/.nuget`, a `.dll` or a `.nupkg` (no reflection program, no project in /tmp, no ildasm, ilspy or `strings`): these commands are refused.
- In-house packages: their calls are the ones of the skill's "In-house API used" (older skills: its "Code"), written as they are. A compilation error on them: first compare the version of the skill with the one used here; then fix from the compiler message, and if needed from the XML documentation of the package (its path is in "Packages of this repository": grep tool on the member name); at most 2 rounds. Then stop and ask me with the question tool, quoting the compiler error: "Je colle la signature depuis Rider" (recommandé) / "Utiliser la version <version of the skill>" / "Arrêter". The version or the skill may be wrong: never work around it by decompiling or by re-implementing the package.
- The skill's `(à vérifier : …)` questions that this application depends on are asked in the question call of step 6 (free answers); never guess them.
- Placeholders of the skill are replaced with values of this repository or its configuration; an unknown value is a question for me, never invented, never copied from another project.
- My directives override the defaults of this command, never the hard rules (security, secrets, no MediatR, never commit, never copy configuration values from another project).

Steps:
0. On `develop`, `master` or `main`: say "Lance /ticket <KEY> d'abord" and stop, unless I answer that I want to continue. If the "Branch vs its remote copy" line says "behind": say "Lance /sync d'abord" and stop, unless I answer that I want to continue.
1. Scope: `back` or `front` if my indications say so; otherwise from the project type (AGENTS.md "Project type" wins): `frontend` → `front`, any .NET type → `back`. A mixed repository without scope: ask me with the question tool (multiple choice, recommended option first): "back" / "front".
2. Skill: the "Skill file" line of this scope above. If it does not exist, ask me with the question tool with the existing pattern skills listed above as options. Read it fully, in the same turn as the searches of step 4; if the pattern touches SharePoint/CSOM, DocuSign, AWS S3 or Piano Analytics, also load the skill `integrations-guardrails` in that turn.
3. Approach: from "Recommended approach", "Variants" and "Adapting to other project types", keep only what applies to this project type. If several variants could apply, prepare a question with the variants as options (the skill's recommended approach first). If the pattern does not apply to this type, say so and stop.
4. Existing code, searched in one turn: what this repository already has for "$1" (partial or different implementation: never duplicate a mechanism, complete or align it instead), and the files the pattern touches here (Program.cs or Startup, DI extensions, `appsettings*.json` or `web.config` transforms, the project files).
5. Libraries: compare those of the pattern (test framework, mocking, assertions, validation...) with this repository's (the "Test stack" line above and "Packages of this repository"). For each library the pattern uses that this repository does not, prepare a question: "Garder l'existant (<current>)" (recommandé) / "Introduire <library>". Kept → translate the pattern's code and tests to the existing libraries (for example Moq syntax to NSubstitute). Introduced → add the package and use it for the new code only. If this repository has no tests, prepare a question: "Créer un projet de tests" / "Ne pas écrire de tests".
6. Prerequisites, compared with "Packages of this repository":
   - Framework: an in-house package whose shipped frameworks (skill's "Prerequisites" or "In-house API used") support none of the target frameworks of the project that will use it cannot be used there (`net8.0` needs .NET 8 or newer; `netstandard2.0` works from .NET Framework 4.7.2 and .NET Core 2.0): say so and stop. A legacy .NET Framework project cannot use packages that require .NET Core or newer either.
   - In-house packages ("interne" in the skill), same ids: already referenced here in the same version → nothing to ask; in an older version → question "Passer à <version of the skill> (version du skill)" (recommandé) / "Garder <version here> (les appels du skill peuvent ne pas exister)"; in a newer version → keep it, no question (the build tells if a call changed); not referenced → question "<version of the skill>" (recommandé) / "La dernière disponible" (then one call: `dotnet package search <id> --exact-match`) / free answer.
   - Other packages of the pattern: the same; a package of the "Licenses" list of your instructions in a paid version is a question with its free version or free option first.
   - Packages are added the way this repository does it: the "Central package management" line (`Directory.Packages.props`) or the project file, following AGENTS.md.
   Ask the questions of steps 3, 5 and 6 together, in one question tool call, and wait for the answers. If `dotnet restore` or the search fails with 401/403/NU1301, stop: it is an Artifactory access problem, never a reason to re-implement the package.
7. Plan: files to create, files to modify, configuration keys to add (per environment file, with the skill's placeholders: secrets come from environment variables or the secret store, never from appsettings), and the tests of each step. Each step leaves the project building. Show it.
8. With a ticket sheet (printed in the workflow state): ask me with the question tool: "Ajouter ces étapes au plan du ticket, puis /dev" (recommandé) / "Implémenter l'étape 1 ici, sans la fiche". For the first answer, with the edit tool, in one turn (exact lines of the sheet printed above):
   - append the steps to "## Plan" as unchecked steps, numbered after the existing ones: `- [ ] <n>. <step> (s'appuyer sur le skill pattern-$1-<scope>)`;
   - add their tests to "Tests attendus" with the status "à écrire";
   - add my answers of step 6 and the questions before it to "## Décisions" (created before "## Suivi" if missing): `- <topic> : <choice> (pattern $1)`;
   - append to "## Suivi": `- <date> /apply-pattern $1 - <n> étapes ajoutées au plan` (date: the "Now" line of the workflow state).
   Then stop with one last line: "Prochaine étape : /dev (étape <first added step>)".
9. Without a ticket sheet, or for the second answer: implement ONLY step 1 of the plan, following the conventions of this repository (naming, folders, logging, DI style), not those of the source projects. Then run the build and tests in one call and report. .NET: `sh ~/.config/opencode/scripts/build-test.sh`, with the solution or project of AGENTS.md "Build & test" as first argument if it names one, and the options of its full test suite; front-end: the commands of AGENTS.md "Build & test", otherwise those of the detection above. Then stop: I will ask for the next step.
