---
name: pack-doc
description: "Procédure de /outil doc : écrit ou met à jour la documentation du dépôt depuis son code, en français : docs/ (architecture, API, configuration, intégrations, données, exploitation), factuelle, avec ses sources, jamais une valeur de configuration ni un secret, puis la publie sur Confluence si on le demande, chaque page après ma validation. Arguments : [sujets] [confluence <ESPACE> [<page parente>]]."
compatibility: opencode
---
# /outil doc

Started directly as the command `/pack-doc` (this procedure is the message that started you, with no line « Skill : pack-doc » printed before it): answer only « Lance `/outil doc` : cette procédure a besoin de ce que /outil prépare. » and stop.

Two parts: the writing is done by the `doc-writer` subagent, which never opens a configuration file and never copies a value; the publishing on Confluence, when asked, by the agent that runs /outil, each page after my approval.

## Part A0, by the agent that runs /outil: delegate the writing
Arguments (the "Arguments" line): the topics among architecture, api, configuration, integrations, donnees, exploitation; after the word `confluence`, the space key, then the parent page title (all the remaining words). On develop, master or main: say in one line that the files will be uncommitted changes of this branch.
One line « Rédaction de la documentation (doc-writer)… », then invoke the `doc-writer` subagent with the subagent tool:
"Write or update the documentation of the repository <repository root>. Topics: <the topics, or « tous ceux qui s'appliquent »>. Load the skill `pack-doc` and follow its part A, then report in its format."
Then Part B if the arguments ask for Confluence, then the answer.

## Part A, by the doc-writer subagent
First turn, all together: `sh ~/.config/opencode/scripts/detect-project-type.sh --files`, `sh ~/.config/opencode/scripts/package-refs.sh`, `sh ~/.config/opencode/scripts/doc-inventory.sh`, `sh ~/.config/opencode/scripts/api-routes.sh`, `sh ~/.config/opencode/scripts/config-keys.sh`. Then:

### Step 1 - Scope
- Arguments (given in your prompt): the topics named among architecture, api, configuration, integrations, donnees, exploitation.
- Topics: the ones named, otherwise every topic of step 3 that applies to this repository (api only with endpoints, donnees only with a database or a storage, the front-end parts only with a front-end).
- Mode: if "Existing documentation" shows files of `docs/` with "généré par /outil doc depuis <commit>" (or "généré par /doc depuis <commit>", from the first version of the pack), update mode: only the topics touched by "Changes since the last /doc" of the inventory (endpoints, controllers or handlers → api; options classes or configuration files → configuration; packages or registrations → integrations; DbContexts, entities or migrations → donnees; CI, Dockerfile or deployment files → exploitation; projects, Program.cs or middleware → architecture), plus the topics named in the arguments; say in one line which topics have nothing to update and leave them as they are. "Last /doc commit ...: not in this clone": update every topic. Otherwise creation mode.

### Step 2 - Read
- The inventory, the HTTP endpoints and the configuration keys of your first turn are computed from the code: use them as they are. Never recompute a route, and never open `appsettings*.json`, `launchSettings.json`, `web.config`, `app.config`, `.env` or front-end `environment*.ts` files: the configuration keys above list every key, and the values must never reach the documentation.
- Read only what the topics need, every read of a turn sent together, at most two turns per topic: the registrations and the middleware order of Program.cs or Startup; for api, the actions and handlers (to say what each endpoint does) and the request and response types; for configuration, the options classes (properties, validation attributes, `ValidateOnStart`); for integrations, the clients and their registrations (timeouts, retries, health checks); for donnees, the DbContexts and the entity configurations; the existing files of `docs/` and the root README.md. Never read bin/, obj/, node_modules or package caches.
- The repository AGENTS.md is already in your instructions: use its "Build & test", "Architecture & conventions" and "Tests" sections.

### Step 3 - Files, in `docs/`, only those of the topics in scope
- `README.md` (always, short): what the application does and for whom (root README, AGENTS.md, code), how to build, test and run it locally (AGENTS.md "Build & test"), the list of the other files with one line each.
- `architecture.md`: the "Project graph" of the inventory as it is, plus the external systems of "Integrations" as nodes linked to the project that uses them; the layers and the patterns the code really uses (CQRS and its mediator, result type, validation); the request pipeline (middleware order of Program.cs); errors, logging and authentication.
- `api.md`: the tables of "HTTP endpoints" with their computed columns as they are (verb, route, authorization, parameters, returns), plus a "Description" column: one sentence per endpoint from its action or handler code. A route with `<...>`: look up the constant and write its value; "(conventional routing)": say which conventional route applies. The notes (global authorization, conventional routes, groups passed as arguments) in a short section. The API description (Swagger, OpenAPI) and its path, from Program.cs.
- `configuration.md`: one table per folder of "Configuration keys": key (as listed), role (the options class and property that bind it, or its use in the code), where it is set (its files: "base" is `appsettings.json`, another label is `appsettings.<label>.json`; "placeholder" means replaced at deployment; a key read from the environment in the code: environment variable), required or optional (validation of its options class, otherwise "À compléter"). A key marked "secret?" is written « secret », with where its value comes from in production (environment variable, secret store, CI variable), or "À compléter" when the code does not show it. No value, except the default of a number, a boolean or a duration written in an options class.
- `integrations.md`: per external system (S3, SharePoint, DocuSign, Piano, databases, HTTP APIs, messaging): what the application does with it, the library, its configuration keys, timeouts and retries, its health check, what happens when it is down.
- `donnees.md`: databases (DbContexts, main entities and their relations, migrations: how many, the latest, how to add and apply one per AGENTS.md), caches, file or object storage (its configuration key, never its name).
- `exploitation.md`: build, tests and local run (AGENTS.md), CI stages and jobs, deployment (master is deployed as it is), health checks, logs and monitoring, background jobs and their schedule, feature flags.
- Front-end: in `architecture.md` its modules, routing and state; in `configuration.md` the keys of its environment files; in `api.md` the back-end APIs it calls.

### Step 4 - Write
- Before each file, one line in French saying which file you write. The write tool for a new file, the edit tool for an existing one.
- First line of each file: `<!-- généré par /outil doc depuis <HEAD short sha of the inventory "Repository" line> le <"Today" line of the inventory> -->` (replace that line in update mode).
- Update mode: change only the sections whose facts changed, keep everything else as it is, hand-written parts included.
- Each section ends with "Sources : <paths>". What the code does not show: "À compléter : <question>".
- The root README.md: if it has no link to `docs/README.md`, add a short "## Documentation" section with that link; change nothing else in it.

### Step 5 - Check, in one turn
- One search with the grep tool, include `*.{cs,csproj,ts,tsx}`, for the class, project and type names that the written files cite (literal names, alternation `Name1|Name2|...`): remove or correct what is not found.
- One search with the grep tool in `docs/` and the root README.md for values: `://|[Pp]assword=|[Ss]erver=|[Ss]ecret=|AccountKey=|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}`: remove every value found.

### Report
Only these lines: one per file created or updated, with what changed; the topics left as they were; « À compléter : » followed by the questions of the files, numbered.

## Part B, by the agent that runs /outil: Confluence, only if the arguments ask for it
- Space key from the arguments; parent page from the arguments, otherwise ask me with the question tool (free answer).
- One page per file of `docs/` that has the /outil doc marker, title "<application name> - <topic>" (the application name from the root README or the solution name), as a child of the parent page: create it when no page with that title exists under the parent (one search, read-only, for all the titles); update it when this run wrote the file; otherwise leave it and say so in one line. Use the markdown format of the Confluence tool if it has one, otherwise its storage format; a Mermaid diagram becomes a code block followed by one sentence saying that the diagram is rendered in the repository.
- Before the first write, one line listing the pages to create or update. Each write asks for my approval; refusing one ends the command there (the pages already written stay, and the files of `docs/` are the content to paste by hand).

## Answer, in French
- The lines of the doc-writer's report.
- Confluence: one line per page, with its link.
- Last, the « Suite » question (question tool, header « Suite »): on a ticket branch « /fix (recommandé) » (« il commite et pousse les fichiers de docs/ avec la branche »); on develop, master or main « /push (recommandé) » (« une branche docs/… pour ces fichiers, son commit et sa MR »); then « Rien pour l'instant ». The pack starts the command I choose: answer only « Je lance <the command>. ».
