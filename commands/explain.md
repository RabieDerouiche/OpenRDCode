---
description: "Explain a file, an endpoint, a page or a feature flow end to end, for onboarding or legacy code (read-only). Usage: /explain <file path, route, page or feature name>"
agent: plan
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Explain the following in French: $ARGUMENTS

Steps:
1. Use the "Project type" section of AGENTS.md if it exists, otherwise the project detection above.
2. Locate the entry point: endpoint, controller action, page, component, route, consumer, background job, public library method or file.
3. Follow the flow through the layers that actually exist in this project, for example:
   - CQRS API: endpoint → request → validator → handler → ports → infrastructure → external systems.
   - Classic or legacy .NET: controller / page code-behind → services → data access → external systems.
   - Front-end: route → component → services / store → HTTP calls → API.
   - Library: public API → internal classes → dependencies.
4. Read the real code. Never describe code you did not read.

Output:
- Résumé: what it does in 3 sentences.
- Flux: numbered steps with file paths and method or component names.
- Données: what is read, written or sent, and where.
- Erreurs: how failures are handled at each step (validation, not found, external errors, retries).
- Points fragiles: hard-coded values, missing tests, swallowed exceptions, missing cancellation or async misuse (.NET), memory leaks or missing cleanup (front-end), TODOs.

Do not modify any file.
