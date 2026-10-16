---
description: "Read the project's Confluence documentation and complete the repository AGENTS.md with business context, glossary, environments and external systems. Only writes AGENTS.md. Usage: /agents-from-confluence <root page title, page URL or space key>"
agent: build
---
Complete the AGENTS.md of this repository with knowledge from the project's Confluence documentation: $ARGUMENTS

Rules:
- The ONLY file you may create or modify is `AGENTS.md` at the repository root. Do not touch any other file.
- Read-only on Confluence, Jira and every other system: never create, update or comment anything there.
- Never invent facts. Every item you add must come from a Confluence page (cite its title) or from the code (cite the file path).
- Never copy secrets, passwords, tokens, internal URLs with credentials or personal data from Confluence into AGENTS.md.
- Keep AGENTS.md short: it is read at the start of every session. Target under 200 lines in total.

Steps:
1. Read the current AGENTS.md. Keep every existing section and every manual line unchanged.
2. From the Confluence root given above, list the child pages and read at most 15 relevant ones: architecture, conventions, environments, integrations, glossary, runbooks, decisions (ADR). Skip meeting notes and outdated pages (say which ones you skipped).
3. Check each fact against the code when possible (project names, endpoints, configuration keys). If Confluence and code disagree, trust the code and list the disagreement in step 5.
4. Add or update only these sections in AGENTS.md:
   - `## Business context`: what the API is for, its consumers, in 3-5 lines.
   - `## Glossary`: domain terms used in code and tickets, one line each.
   - `## Environments`: environment names and their purpose (no URLs with credentials).
   - `## External systems`: SharePoint, DocuSign, S3, Piano Analytics and others: what each is used for in this API, with the code location.
   - `## Architecture decisions`: decisions that constrain the code, one line each, with the source page title.
   - `## Confluence`: space key and root page, if not already filled.
5. Final answer in French: the sections added or changed, the Confluence pages used, the pages skipped, and the Confluence-versus-code disagreements found (these are documentation to fix, not code to change).
