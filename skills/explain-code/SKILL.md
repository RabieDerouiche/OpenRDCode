---
name: explain-code
description: Method to explain a file, an endpoint, a page or a feature flow end to end (onboarding, legacy code), adapted to the project type. Load when asked to explain how some code or a feature works. Read-only.
compatibility: opencode
---
# Explaining code

Read-only: never modify a file while explaining.

## Steps
1. Project type: the "Project type" section of the repository AGENTS.md if it exists, otherwise `sh ~/.config/opencode/scripts/detect-project-type.sh`.
2. Locate the entry point: endpoint, controller action, page, component, route, consumer, background job, public library method or file.
3. Follow the flow through the layers that actually exist in this project, for example:
   - CQRS API: endpoint → request → validator → handler → ports → infrastructure → external systems.
   - Classic or legacy .NET: controller / page code-behind → services → data access → external systems.
   - Front-end: route → component → services / store → HTTP calls → API.
   - Library: public API → internal classes → dependencies.
4. Read the real code. Never describe code you did not read.

## Output, in French
- Résumé: what it does in 3 sentences.
- Flux: numbered steps with file paths and method or component names.
- Données: what is read, written or sent, and where.
- Erreurs: how failures are handled at each step (validation, not found, external errors, retries).
- Points fragiles: hard-coded values, missing tests, swallowed exceptions, missing cancellation or async misuse (.NET), memory leaks or missing cleanup (front-end), TODOs.
