---
description: "Morning brief for ONE Jira project or board: my sprint first, reviews waiting for me, my merge requests linked to their tickets, what to pick next, and a plan for today, with links (read-only). Usage: /daily [Jira project key or board name]"
agent: pilot
subtask: false
---
[[command daily $ARGUMENTS]]
Scope given: "$ARGUMENTS"
Today: !`date +%Y-%m-%d`

My personal todo list (/outil todo, kept outside Jira):
[[run todo.sh list]]

Build my morning brief with the Jira and GitLab MCP tools. "Me" is the authenticated user.
Completeness matters more than brevity for this command: list every item returned by the queries, never cut a list to a few rows, and give the total count in each section heading.

## Step 1 - Scope
- If a scope is given above, use it: a Jira project key (e.g. `ABC`) or a board name.
- Otherwise use the section "Daily" of AGENTS.md.
- Otherwise ask me with the question tool (multiple choice, recommended option first): the Jira projects where tickets assigned to me were updated in the last 30 days, most recent first.
- If the scope is a board name, find the board and its project. If several boards match, ask me with the question tool.
- If the scope is a project key, find its board with an active sprint. If several, ask me with the question tool.

## Step 2 - Links
Every Jira key and every merge request in the output is a markdown link:
- Jira: `[ABC-123](<jira base url>/browse/ABC-123)`. Base URL: the "Jira URL" in AGENTS.md "Daily" if present, otherwise the scheme and host of the `self` URL returned by the Jira tools.
- GitLab: `[!42](<web_url>)` with the `web_url` returned by the GitLab tools.
Never invent a URL. If none is available, write the key alone.

## Step 3 - Jira
Speed: once the scope is known, send the Jira queries A to D and the two GitLab searches of step 4 together in one turn (they run in parallel), then fetch the next pages where needed.
Ask for at least 50 results per query (maxResults / limit parameter) and fetch the next page while there are more. Ask only the fields kept below (the `fields` parameter of the search, when the tool has one: `summary,status,issuetype,priority,updated,duedate,labels,flagged,issuelinks` and the story points field): 50 whole issues are cut by OpenCode, and the query would have to run again.
- A. Active sprint: name, start date, end date.
- B. My sprint tickets, Done included (for progress):
  `project = <KEY> AND sprint in openSprints() AND assignee = currentUser() ORDER BY Rank ASC`
- C. Sprint tickets nobody has taken yet:
  `project = <KEY> AND sprint in openSprints() AND assignee is EMPTY AND statusCategory = "To Do" ORDER BY Rank ASC`
- D. My tickets outside the sprint:
  `project = <KEY> AND assignee = currentUser() AND statusCategory != Done AND (sprint is EMPTY OR sprint not in openSprints()) ORDER BY priority DESC, updated DESC`
If the board has no active sprint (kanban), say "Pas de sprint actif", skip A and C, and run B without the sprint clause and with `statusCategory != Done`.
For each ticket keep: key, type, summary, status, priority, story points if present, flagged or blocked ("Flagged" field, a blocked status, or an open "is blocked by" link), last update, due date.

## Step 4 - GitLab
In the GitLab group or projects of AGENTS.md "Daily" if defined, otherwise in the projects whose merge requests reference keys of this Jira project:
- My open merge requests (author = me).
- Open merge requests where I am a reviewer and have not approved yet.
For each: web_url, project, title, source and target branch, draft, head pipeline status, merge conflicts, unresolved discussions, approvals given / required, creation date, and the Jira key found in the title or source branch (pattern `[A-Z][A-Z0-9_]+-[0-9]+`).
Match merge requests to tickets with that key.

## Step 5 - Signals (computed from the data, never guessed)
- 🔴 My merge request with a failed pipeline or merge conflicts.
- 🔴 Ticket flagged or blocked: name the blocker.
- 🟠 Review waiting for me for more than 1 working day.
- 🟠 Unresolved discussions on my merge request.
- 🟠 Ticket in progress with no merge request and no update for 3 working days or more.
- 🟠 Sprint ends within 3 working days and one of my tickets is still To Do.
- 🟢 My merge request approved, pipeline green, no discussion left: ready to merge.
- ⚪ Merge request without Jira key.

## Output, in French, in this order

# Daily - <date> - <scope>
One line: `Sprint <name> : J-<working days left> (fin le <dd/mm>) - mes tickets : <done>/<total> terminés`, plus remaining story points if the tickets have them.

## Ma todo (<n>)
Only when my todo list above has items: its items as they are (number, due date, text), overdue first, as a short list. Then go on with section 1.

## 1. Mon sprint (<n>)
Groups in this order: "En cours", "En revue / test" (statuses after development and before Done), "À faire". Inside a group, keep the sprint rank order.
Table: Ticket (link), Type, Titre, Statut, Prio, MR (link + pipeline: ✅ success, ❌ failed, ⏳ running or pending, - none), Signal.
Done tickets: a single line "Terminés : <links>".

## 2. Reviews en attente de moi (<n>)
Table: MR (link), Projet, Titre, Auteur, Ticket (link), Ouverte depuis, Pipeline, Commande (`/review !<iid>`, to run in a session opened on that project).

## 3. Mes merge requests (<n>)
Table: MR (link), Ticket (link), Cible, Pipeline, Conflits, Discussions non résolues, Approbations, Draft, Signal.

## 4. À prendre ensuite dans le sprint (<n>)
The first 5 tickets of query C in rank order. Table: Ticket (link), Type, Titre, Prio, Points.

## 5. Hors sprint (<n>)
Table: Ticket (link), Type, Titre, Statut, Prio, Dernière MAJ, Signal. If there are more than 20, show the 20 first and add a link to the full list: `<jira base url>/issues/?jql=<URL-encoded query D>`.

## 6. Plan du jour
3 to 5 numbered actions, one line each, with the link and the command to use when one applies. Order:
0. The items of my todo list that are overdue or due today (`/outil todo fait <n>` once done).
1. My merge requests with a failed pipeline, open discussions or conflicts with develop: `/fix` in a session on that branch (it fixes the jobs, the scans and the review comments, and merges develop).
2. Reviews waiting for me: they block teammates (`/review !<iid>` in a session on that project).
3. Merge requests approved with a green pipeline: ready to merge.
4. Blocked tickets: who to contact, with the blocker link.
5. Continue my in-progress sprint tickets, in rank order (`/go <KEY>` resumes where it stopped).
6. If nothing is in progress: start the first ticket of section 4 or the first To Do of section 1 with `/go <KEY>`.

## Then
Ask me with the question tool "Sur quoi tu bosses ?" (header "Ticket"): as options, the 3 tickets that come first in the plan of the day, each with the label `/go <KEY>` and the description `<summary>`, the first one "(recommandé)", plus "Rien pour l'instant". I can type another answer (for example `/go ABC-12 avec un feature flag`). The pack plugin starts the /go I choose by itself in this session as soon as your turn ends (it resumes the ticket if it is already started): then answer only « Je lance /go <KEY>. ».

Rules: read-only, no comment, assignment or status change anywhere. If a system is unreachable, say so in one line and build the rest.
