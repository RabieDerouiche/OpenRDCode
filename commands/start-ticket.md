---
description: "Prepare work on a Jira ticket: read it with linked Confluence pages, list acceptance criteria and tests, propose a branch name and a plan (read-only). Usage: /start-ticket <JIRA-KEY>"
agent: analyst
---
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Prepare the work on Jira ticket $1.

Steps:
1. Read the ticket $1 with the Jira MCP tools: summary, description, acceptance criteria, comments, linked issues, attachments list, epic.
2. Read the Confluence pages linked from the ticket or its epic. If none are linked, search Confluence for the 3 most relevant pages using the ticket's key terms. Read only what is relevant.
3. Search the current repository (read, grep, glob tools) for the code areas involved: endpoints, handlers, integrations.

Output, in French:

## Résumé
What is asked, in 3 sentences.

## Critères d'acceptation
Numbered list. If the ticket has none, deduce them and mark each "(déduit)".

## Questions ouvertes
Ambiguities or missing information to clarify with the product owner before coding. Write them ready to paste as a Jira comment (do not post it).

## Zones de code concernées
File paths and why.

## Tests à écrire
One line per test: class, scenario, expected result. Covers every acceptance criterion.

## Branche
Suggested branch name: `feature/$1-<short-kebab-summary>` (or `hotfix/` / `bugfix/` according to the ticket type).

## Plan
Ordered steps, each leaving the solution building. Mention when to use /test-for and /review, and /cqrs only if the project type (AGENTS.md or detection above) is cqrs-api.

Rules: read-only. Do not create the branch, do not comment on Jira, do not change the ticket status.
