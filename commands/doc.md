---
description: "Create or update the documentation of the repository from its code, in French: docs/ (architecture, API, configuration, integrations, data, operations), factual, with its sources, never a configuration value or a secret. Routes and configuration keys are computed by scripts, not guessed. After a first run, updates only what changed since. Optionally publishes it to Confluence, each page after my approval. Usage: /doc [architecture|api|configuration|integrations|donnees|exploitation] [confluence <SPACE KEY> [<parent page title>]]"
agent: doc-writer
---
Project detection and files:
[[run detect-project-type.sh --files]]

Packages and target frameworks:
[[run package-refs.sh]]

Inventory of the repository (facts found by text search, each with its file:line):
[[run doc-inventory.sh]]

[[run api-routes.sh]]

[[run config-keys.sh]]

Arguments: "$ARGUMENTS"

Write or update the documentation of this repository, from its code only.

## Step 1 - Scope
- Arguments: the topics named among architecture, api, configuration, integrations, donnees, exploitation; after the word `confluence`, the space key, then the parent page title (all the remaining words).
- Topics: the ones named, otherwise every topic of step 3 that applies to this repository (api only with endpoints, donnees only with a database or a storage, the front-end parts only with a front-end).
- Mode: if "Existing documentation" shows files of `docs/` with "généré par /doc depuis <commit>", update mode: only the topics touched by "Changes since the last /doc" (endpoints, controllers or handlers → api; options classes or configuration files → configuration; packages or registrations → integrations; DbContexts, entities or migrations → donnees; CI, Dockerfile or deployment files → exploitation; projects, Program.cs or middleware → architecture), plus the topics named in the arguments; say in one line which topics have nothing to update and leave them as they are. "Last /doc commit ...: not in this clone": update every topic. Otherwise creation mode.
- On `develop`, `master` or `main`: say in one line that these files will be uncommitted changes of this branch, and continue.

## Step 2 - Read
- The inventory, the HTTP endpoints and the configuration keys above are computed from the code: use them as they are. Never recompute a route, and never open `appsettings*.json`, `launchSettings.json`, `web.config`, `app.config`, `.env` or front-end `environment*.ts` files: the configuration keys above list every key, and the values must never reach the documentation.
- Read only what the topics need, every read of a turn sent together, at most two turns per topic: the registrations and the middleware order of Program.cs or Startup; for api, the actions and handlers (to say what each endpoint does) and the request and response types; for configuration, the options classes (properties, validation attributes, `ValidateOnStart`); for integrations, the clients and their registrations (timeouts, retries, health checks); for donnees, the DbContexts and the entity configurations; the existing files of `docs/` and the root README.md. Never read bin/, obj/, node_modules or package caches.
- The repository AGENTS.md is already in your instructions: use its "Build & test", "Architecture & conventions" and "Tests" sections.

## Step 3 - Files, in `docs/`, only those of the topics in scope
- `README.md` (always, short): what the application does and for whom (root README, AGENTS.md, code), how to build, test and run it locally (AGENTS.md "Build & test"), the list of the other files with one line each.
- `architecture.md`: the "Project graph" of the inventory as it is, plus the external systems of "Integrations" as nodes linked to the project that uses them; the layers and the patterns the code really uses (CQRS and its mediator, result type, validation); the request pipeline (middleware order of Program.cs); errors, logging and authentication.
- `api.md`: the tables of "HTTP endpoints" with their computed columns as they are (verb, route, authorization, parameters, returns), plus a "Description" column: one sentence per endpoint from its action or handler code. A route with `<...>`: look up the constant and write its value; "(conventional routing)": say which conventional route applies. The notes (global authorization, conventional routes, groups passed as arguments) in a short section. The API description (Swagger, OpenAPI) and its path, from Program.cs.
- `configuration.md`: one table per folder of "Configuration keys": key (as listed), role (the options class and property that bind it, or its use in the code), where it is set (its files: "base" is `appsettings.json`, another label is `appsettings.<label>.json`; "placeholder" means replaced at deployment; a key read from the environment in the code: environment variable), required or optional (validation of its options class, otherwise "À compléter"). A key marked "secret?" is written « secret », with where its value comes from in production (environment variable, secret store, CI variable), or "À compléter" when the code does not show it. No value, except the default of a number, a boolean or a duration written in an options class.
- `integrations.md`: per external system (S3, SharePoint, DocuSign, Piano, databases, HTTP APIs, messaging): what the application does with it, the library, its configuration keys, timeouts and retries, its health check, what happens when it is down.
- `donnees.md`: databases (DbContexts, main entities and their relations, migrations: how many, the latest, how to add and apply one per AGENTS.md), caches, file or object storage (its configuration key, never its name).
- `exploitation.md`: build, tests and local run (AGENTS.md), CI stages and jobs, deployment (master is deployed as it is), health checks, logs and monitoring, background jobs and their schedule, feature flags.
- Front-end: in `architecture.md` its modules, routing and state; in `configuration.md` the keys of its environment files; in `api.md` the back-end APIs it calls.

## Step 4 - Write
- Before each file, one line in French saying which file you write. The write tool for a new file, the edit tool for an existing one.
- First line of each file: `<!-- généré par /doc depuis <HEAD short sha of the inventory "Repository" line> le <"Today" line of the inventory> -->` (replace that line in update mode).
- Update mode: change only the sections whose facts changed, keep everything else as it is, hand-written parts included.
- Each section ends with "Sources : <paths>". What the code does not show: "À compléter : <question>".
- The root README.md: if it has no link to `docs/README.md`, add a short "## Documentation" section with that link; change nothing else in it.

## Step 5 - Check, in one turn
- One search with the grep tool, include `*.{cs,csproj,ts,tsx}`, for the class, project and type names that the written files cite (literal names, alternation `Name1|Name2|...`): remove or correct what is not found.
- One search with the grep tool in `docs/` and the root README.md for values: `://|[Pp]assword=|[Ss]erver=|[Ss]ecret=|AccountKey=|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}`: remove every value found.

## Step 6 - Confluence, only if the arguments ask for it
- Space key from the arguments; parent page from the arguments, otherwise ask me with the question tool (free answer).
- One page per file of `docs/` that has the /doc marker, title "<application name> - <topic>" (the application name from the root README or the solution name), as a child of the parent page: create it when no page with that title exists under the parent (one search, read-only, for all the titles); update it when this run wrote the file; otherwise leave it and say so in one line. Use the markdown format of the Confluence tool if it has one, otherwise its storage format; a Mermaid diagram becomes a code block followed by one sentence saying that the diagram is rendered in the repository.
- Before the first write, one line listing the pages to create or update. Each write asks for my approval; refusing one ends the command there (the pages already written stay, and the files of `docs/` are the content to paste by hand).

## Answer, in French
- One line per file created or updated, with what changed; the topics left as they were.
- "À compléter" : the questions of the files, numbered (I answer, then you complete them with the edit tool).
- Confluence: one line per page, with its link.
- Then the next step with the question tool (header "Suite"): on a feature branch "/ship (recommandé)" (description: « commit et push de la documentation »); on `develop`, `master` or `main` "/ticket (recommandé)" (description: « choisir le ticket de cette documentation et créer sa branche : les fichiers peuvent la suivre »); and "Rien pour l'instant". The pack plugin starts the command I choose by itself as soon as your turn ends: then answer only « Je lance <command>. ».
