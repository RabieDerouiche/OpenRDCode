---
description: "Morning brief for ONE Jira project or board: my tickets, my open merge requests, reviews waiting for me (read-only). Usage: /daily [Jira project key or board name]"
agent: analyst
---
Scope given: "$ARGUMENTS"

Build my morning brief with the Jira and GitLab MCP tools, limited to one scope. Use the identity of the authenticated user ("me").

1. Determine the scope:
   - If a scope is given above, use it: a Jira project key (e.g. `DNA`) or a board name.
   - Otherwise use the section "Daily" of AGENTS.md (default Jira project or board, GitLab group or projects).
   - Otherwise ask me with the question tool (multiple choice, recommended option first): propose as options the Jira projects where tickets assigned to me were updated in the last 30 days (at most 4, most recent first).
   - If the scope is a board name, find the board and use its project; if several boards match, ask me with the question tool.

2. Jira, only in that scope, with this JQL (adapt the project clause to the scope):
   `assignee = currentUser() AND project = <KEY> AND statusCategory != Done AND updated >= -60d ORDER BY priority DESC, updated DESC`
   If the scope is a board with an active sprint, also add `AND sprint in openSprints()` and say "Sprint en cours : <name>".
   Never include tickets from other projects, and never tickets not updated for more than 60 days.

3. GitLab, only merge requests updated in the last 30 days:
   - in the GitLab group or projects from AGENTS.md "Daily" if defined;
   - otherwise in the projects whose merge requests reference Jira keys of this scope (e.g. `DNA-123` in the title or branch name).

Sections, in this order:

## Mes tickets (<scope>)
Table: key, title, status, priority, last update. Flag tickets with no update for more than 5 working days.

## Mes merge requests
Table: MR number, title, target branch, pipeline status, unresolved discussions, approvals. Flag: failed pipeline, merge conflicts, unresolved discussions.

## Reviews en attente de moi
Merge requests where I am a reviewer and have not approved yet. Table: MR number, title, author, opened since.

## À faire en premier
The 3 most urgent actions for today, one line each, with the key or MR number.

Rules: read-only, no comment or status change anywhere.
