# Global rules (merge into ~/.config/opencode/AGENTS.md)

## Language
- Answer me in French.
- Code, code comments, log messages, commit messages and test names are in English.

## Deciding and asking
- Inside /go and /fix, nobody watches: the agents decide and document, as their rules say. The only questions are the choice of the ticket and the blocking questions of the analysis, all at once.
- In a free conversation, ask me only when the answer changes what you do and nothing settles it (the code, the git history, AGENTS.md, the ticket sheet): all the questions in ONE question tool call, 2 to 4 short options each, the recommended one first and marked "(recommandé)". Otherwise decide like the existing code and say what you decided.
- A command I can run next is offered with the question tool (header "Suite"), its label being the command itself (`/go ABC-123`, `/fix`, `/outil doc`), the recommended one first, plus "Rien pour l'instant": the pack plugin starts the command I choose as soon as your turn ends; answer only « Je lance <command>. ».

## Working style
- Read existing code before writing new code, and mirror its conventions.
- Smallest change that solves the request. No unrelated refactoring, renaming or reformatting.
- Never claim success without running the build and test commands of the repository when code was changed.
- Never invent file paths, types, methods, package names, application names or filter names. Look them up.
- The API of a package (in-house or not) comes, in this order, from: the pattern skill or AGENTS.md, the existing calls in this repository, the XML documentation shipped with the package (grep tool on the member name, in the file given by `sh ~/.config/opencode/scripts/package-refs.sh`, which also tells the in-house packages, their versions and their frameworks). Never list or search `~/.nuget` yourself, never decompile or dump an assembly.
- If several tool calls in a row do not move the task forward (no file written, no build or test run, the same kind of search repeated), stop and tell me in two lines what blocks and what you need.
- Before a long action (a subagent, several files read at once, a long file written, the build or the tests), write ONE short line in French saying what starts. No other narration.
- Never end a turn silently: if you stop (blocked, refused permission, nothing to do), say why in one line.

## Speed
- .NET build and tests in one call: `sh ~/.config/opencode/scripts/build-test.sh [<solution or project>] [<dotnet test options>]`: quiet build, tests only if the build passed, explicit "BUILD:" and "TESTS:" lines. Some tests only: `… build-test.sh <test project> --filter FullyQualifiedName~<TestClass>`. Build only: `… build-test.sh --build-only [<solution or project>]`. With the solution or project and the test options of AGENTS.md "Build & test" when it names them. Front-end: the commands of AGENTS.md (a test command that ends by itself, never a watch mode).
- A line "ENVIRONMENT PROBLEM" in an output is final: tell me in one line and stop. I fix it outside OpenCode.
- A failed build lists every error of the projects it compiled; a project that references a failing one is not compiled at all. Fix the errors shown, then build again: never run the same build twice without changing a file.
- A prompt of a command that still starts with a line `[[command <name> …]]` was not prepared by the pack plugin: the plugin is not loaded and its guards are off. Answer only « ⚠ Le plugin du pack n'est pas chargé : ses garde-fous sont inactifs. Redémarre OpenCode, puis vérifie son journal (COMMANDES.md, « Logs d'OpenCode »). » and run nothing.
- A line `[[run <script> <arguments>]]` left in the prompt of a command means that the pack plugin did not run it: run `sh ~/.config/opencode/scripts/<script> <arguments>` yourself for each such line, all in one turn, and use their outputs in their place.
- Long outputs through `| tail -60`; `git diff --stat` before a full diff.
- A file of more than 300 lines is read in ranges (the read tool's offset and limit, around what you need), never whole: every line read stays in your context until the end of your task, and an oversized request is cut by the model server.
- A tool answer that says it was truncated and saved to a file (often one long line of JSON, from an MCP tool) is not worth searching: call the same tool again with a smaller page (20 results or fewer) or stricter filters. Never run several searches on that file.
- Use the shell only for the build, the tests, git reads and the `~/.config/opencode/scripts` commands. For everything else the tools: `read`, `grep`, `glob`, `edit`, `write`. Shell commands already run in the project folder: never `cd <project>` or `git -C <project>`. The read, grep, glob, edit and write tools do not expand `~`: absolute paths (`realpath ~` gives the home folder).
- Refused shell forms (never try them, never look for another form that would pass): a path outside the repository (`~`, `$HOME`, `/home/…`, `../..`, a bare `cd`), unless I named that folder in my message or in the command; anything that prints or reads the environment or credentials (`env`, `printenv`, `export`, `set`, `echo $…`, `git config`, `git remote -v`, nuget.config, `.env` files, `~/.nuget/NuGet`, `~/.z*` files); anything that looks inside packages or assemblies (`~/.nuget/packages`, `.dll`, `.nupkg`, `/tmp`, `mktemp`, `dotnet new console`, `dotnet fsi`, ilspy, ildasm, `strings`); a recursive `rm`; `git commit`, `push`, `merge`, `pull`, `rebase`, `reset` (only /go and /fix write the history); starting the application or any program (`dotnet run`, `npm start`, `func start`): check a behavior with a test instead (an integration test with WebApplicationFactory when the project has some); changing anything outside the repository, the pack's scripts and skills included (they are read-only); for the agents that only read: a redirection to a file, `$(...)` and backticks.
- Tools by their name only (`dotnet`, `node`, `npm`, `git`), never by their path (`~/.bin/dotnet`): not found is an ENVIRONMENT PROBLEM.
- A tool that answers an error (an MCP tool, a refused command): never the same call again (a timeout: once more at most); do without it, and say what is missing.
- Independent tool calls go together in ONE turn: they run in parallel. AGENTS.md files are already in your instructions: never read them again, except to edit one.

## Project types
- .NET 10 APIs with Clean Architecture + CQRS, classic .NET APIs (some on ABP Framework), Blazor applications, legacy .NET Framework web projects, libraries, front-end projects. Detected by `sh ~/.config/opencode/scripts/detect-project-type.sh`; a "Project type" section in the repository AGENTS.md overrides it.
- Follow the conventions of the existing code. Never introduce CQRS, a mediator or Clean Architecture layers where they are not. CQRS APIs: in-house mediator, NEVER MediatR; load the skill `dotnet-cqrs-conventions` before writing or reviewing handlers.
- New libraries: by default what the repository already uses. Licenses: MediatR 13+, AutoMapper 15+, FluentAssertions 8+, MassTransit 9+, NPOI 2.8+, EPPlus 5+, QuestPDF, SixLabors.ImageSharp 3+, Blazorise, Duende IdentityServer, iText, and Polly from its next major version are paid or copyleft: never such a version, always the free option first (in-house mediator or plain services, Mapperly or manual mapping, AwesomeAssertions or Shouldly, MassTransit 8, ClosedXML…).
- Legacy .NET Framework projects may not build on this machine (.NET Framework needs Windows): say so instead of changing project files.
- Integrations: SharePoint (CSOM), DocuSign, AWS S3, Piano Analytics: load the skill `integrations-guardrails` before touching them. Never modify authentication or credentials handling without asking.

## Workflow
- My day: /daily → /go <KEY> (ticket to Draft merge request, in one run) → the CI runs → /fix (CI, Sonar, Fortify and review feedback, in one run) → review and merge. /review !<iid> reviews a teammate's merge request. /compare finds the cause of a regression against another repository. /outil gives the other tools: doc, audit, licences, release-notes, pattern (a team pattern from another repository, that /go then uses), cqrs, setup (AGENTS.md of the repository), abandon, todo, stats (what /go and /fix did on my tickets).
- Merge requests target `develop`. Production is deployed from `master` as is; there are no release tags. Sonar and Fortify run in the CI on every push.
- You may run on a remote machine while I sometimes code in Rider on my Mac: we do NOT share files. My Mac changes reach you only through git (I push from Rider; /go and /fix merge them first), and yours reach my Mac only after /go or /fix pushed them.
- Ticket sheet: `<git folder>/opencode-tickets/<KEY>.md` (`.git/opencode-tickets/` in the main checkout, the same folder from every worktree; never committed) holds the analysis, the plan, the decisions and the log of the ticket of the current branch. Updated with `sh ~/.config/opencode/scripts/ticket-sheet.sh tick|decision|suivi …`, never by hand.

## Git
- Git writes go through /go and /fix (their scripts commit, merge the remote copy and develop, check the changes, and push the ticket branch). Commit, push, merge, pull, rebase and reset are refused to every agent in a conversation: offer /fix (it commits and pushes the local changes of the ticket branch). Never force-push; never anything on develop, master or main. The team keeps branches up to date with develop by MERGE, never by rebase.

## Routing (when I ask in plain words; "offer" = the question tool with the command as option, which then starts by itself)
- "prends le ticket ABC-123", "fais le ticket", "continue le ticket" → offer `/go <KEY>` (with my words as directives). A change I want without a Jira ticket → offer `/go sans ticket : <the change in my words>`.
- "corrige les retours", "la CI est rouge", "Sonar", "Fortify", "les commentaires de la MR", "pousse", "commite", "j'ai poussé depuis mon Mac" → offer `/fix`.
- "merge la branche X", "intègre le hotfix X" on a ticket branch → offer `/fix merge X` (it merges, builds, tests and pushes).
- "pourquoi ça plante", a stack trace, a failing test → invoke the `debugger` subagent with the subagent tool.
- A worktree, « un espace de travail », several tickets of one repository at the same time → you never create, remove or move one (the pack refuses worktree_create, worktree_remove and session_move to every agent): tell me to click « Local » under the prompt of a new session, then « Nouvel espace de travail », in the OpenCode v2 web interface (COMMANDES.md, « Plusieurs tickets d'un même dépôt »). Never give me a script to run for it.
- « corrige les vulnérabilités Fortify », « les failles du scan », « un lot Fortify » → offer `/fortify` (with my words as directives: a count, a category, a file or a Jira key). One batch of 5 vulnerabilities at most per merge request; the next batch once it is merged.
- A problem to check without a ticket ("vérifie si…", "est-ce que…", "regarde pourquoi…") → investigate here, in this conversation (the `debugger` subagent for a failure): no branch, no commit. When it needs a fix, say so with the cause and the files, and offer `/go sans ticket : <the fix>` (or `/go <KEY>` if I create a Jira ticket): /go in this same session hands your findings to the analysis.
- "explique", "comment marche" → load the skill `explain-code` and follow it.
- "corrige le build", compilation errors → load the skill `build-fix` and follow it.
- "corrige le point Fortify <id>" or "Sonar <key>", one finding → load `fortify-remediation`, fix it with its test, build and test; /fix then commits it.
- "compare avec l'ancien dépôt", "ça marchait dans l'ancienne API" → offer `/compare <path of the repository where it works> <class, method or route> <symptom>` (ask me for the path or the identifier if missing). Never compare two repositories by reading them freely.
- "fais comme dans <repo>", "inspire-toi de <repo>" → offer `/go <KEY> comme dans <repo path>` (it reads that repository for this ticket), and, when the same implementation will serve several tickets or teammates, `/outil pattern <name> <repo path>` first (a team pattern that /go then uses by itself).
- "documente le projet", "audit", "vérifie les licences", "release note", "génère l'AGENTS.md", "annule ce ticket", "mes stats", "combien de tickets" → offer `/outil doc`, `/outil audit`, `/outil licences`, `/outil release-notes`, `/outil setup`, `/outil abandon`, `/outil stats`.
- "rappelle-moi de …", "ajoute à ma todo …" → run `sh ~/.config/opencode/scripts/todo.sh add "<the item as I said it, with its due date in plain words>"` and show its output; "ma todo", "mes rappels" → `sh ~/.config/opencode/scripts/todo.sh` (or `… todo.sh due`). Never in Jira.
- "relis la MR de …", "review la MR !42" → `/review !<iid>`, in a session opened on that repository.
- Do not invoke subagents for anything else unless I ask.

## Daily
- Default scope of /daily and /go: Jira project or board `[KEY or board name]`, GitLab group or projects `[group/path]`. Replace the placeholders, or delete this section to be asked each time.
- Jira URL (for the ticket links): `[https://jira.mycompany.com]`. Optional: without it, the URL returned by the Jira tools is used.

## Release groups
- Used by `/outil release-notes <group name>` to write one release note for several repositories deployed together. One block per group:
- `[GROUP]`: Confluence space `[SPACEKEY]`, release notes parent page `[page title]`, application name `[name]`, repositories:
  - `[Back]`: `[absolute path on the machine where OpenCode runs]/[back-repo]`
  - `[Front]`: `[absolute path on the machine where OpenCode runs]/[front-repo]`
  - `[Lib Infra]`: `[absolute path on the machine where OpenCode runs]/[lib-repo]`

## NuGet / Artifactory
- NuGet restore authenticates to Artifactory through environment variables already set on this machine: you never need their names or values.
- Never print, echo, log or read these values or the files that define them: no NuGet.Config or nuget.config through the shell (the user one, `~/.nuget/NuGet/NuGet.Config`, never at all), no `echo`, `test -n` or `printenv` on environment variables, no search for passwords, tokens or credentials anywhere. Never modify nuget.config to hardcode credentials.
- `dotnet restore` failing with 401/403/NU1301, or `dotnet`, `node` or `npm` not found ("ENVIRONMENT PROBLEM"): stop and tell me in one line. Never investigate it, never change PATH, DOTNET_ROOT or any variable.
- Never write `export`, `PATH=`, `DOTNET_ROOT=` or a credential (user name, password, token, in a variable, a URL or an option) in a command, even one I gave you: the pack refuses such commands.

## Jira (MCP)
- An issue is read by its key: the ticket, then its parent or epic and its linked issues by their keys (they are in the ticket). A JQL search only for a list (/daily, the choice of a ticket).
- A Jira error (JQL refused, unknown field, server error): never another form of the same search. Say it in one line and go on without it, or stop when nothing can be done without it.

## Fortify SSC (MCP)
- The SSC application name of each repository is the value of APPSEC_PROJECT_NAME in its appsec-ci.env file, printed by the workflow state of /fix; never read appsec-ci.env entirely: it may contain secrets.
- Version: the branch version if it has scans, otherwise develop; never guess application or version names. Filter set "Security Auditor View" unless I ask otherwise.
