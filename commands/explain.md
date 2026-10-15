---
description: "Explain a file, an endpoint or a feature flow end to end, for onboarding or legacy code (read-only). Usage: /explain <file path, endpoint route or feature name>"
agent: plan
---
Explain the following in French: $ARGUMENTS

Steps:
1. Locate the entry point (endpoint, controller action, consumer, background job or file).
2. Follow the flow layer by layer: endpoint → request → validator → handler → ports → infrastructure implementations → external systems (SharePoint, DocuSign, S3, Piano Analytics, database).
3. Read the real code. Never describe code you did not read.

Output:
- Résumé: what it does in 3 sentences.
- Flux: numbered steps with file paths and method names.
- Données: what is read, written or sent, and where.
- Erreurs: how failures are handled at each step (validation, not found, external errors, retries).
- Points fragiles: hard-coded values, missing tests, missing CancellationToken, swallowed exceptions, TODOs.

Do not modify any file.
