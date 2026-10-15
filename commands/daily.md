---
description: "Morning brief: my Jira tickets, my open merge requests, reviews waiting for me, failed pipelines (read-only)"
agent: analyst
---
Current git branch: !`git branch --show-current`

Build my morning brief using the Jira and GitLab MCP tools. Use the identity of the authenticated user ("me") for every query.

Sections, in this order:

## Mes tickets Jira
Tickets assigned to me that are not done, sorted by priority. Table: key, title, status, priority, last update. Flag tickets with no update for more than 5 working days.

## Mes merge requests
My open merge requests. Table: MR number, title, target branch, pipeline status, unresolved discussions count, approvals. Flag: failed pipeline, merge conflicts, unresolved discussions.

## Reviews en attente de moi
Merge requests where I am a reviewer and have not approved yet. Table: MR number, title, author, opened since.

## À faire en premier
The 3 most urgent actions for today, one line each, with the key or MR number.

Rules: read-only, no comment or status change anywhere.
