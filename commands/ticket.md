---
description: "Start (or resume) a Jira ticket: pick it from my sprint if no key is given, create the branch from an up-to-date develop, analyze the ticket, its Confluence pages and the code, and save the ticket sheet used by /test, /check, /ship and /next. Usage: /ticket [JIRA-KEY]"
agent: git
---
Ticket given: "$1"
Workflow state (one fetch, then the state of the branch and of the ticket sheet):
!`sh ~/.config/opencode/scripts/workflow-state.sh`
Project detection:
!`sh ~/.config/opencode/scripts/detect-project-type.sh`

Start or resume the work on a Jira ticket. Read-only on Jira, Confluence and GitLab.

## Step 1 - Pick the ticket
- If a ticket is given above, use it.
- Otherwise, if the current branch name contains a Jira key, propose it first.
- Otherwise read my open tickets of the active sprint with the Jira MCP tools (project from the "Daily" section of AGENTS.md if defined):
  `assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done ORDER BY Rank ASC`
  and ask me with the question tool: up to 4 tickets as options, in-progress ones first, the first one "(recommandé)", each option as `<KEY> - <summary>`. I can type another key.
- If the ticket does not exist in Jira, say so and ask me for the key again.

## Step 2 - Existing ticket sheet
If `<KEY>.md` is in the list of existing ticket sheets above, ask me with the question tool:
- "Reprendre la fiche existante" (recommandé): read it, make sure I am on its branch (go to step 3 only if I am not), show the sections "Critères d'acceptation", "Plan" (unchecked steps) and the last 3 lines of "Suivi", then tell me the next step (step 6) and stop.
- "Refaire l'analyse": continue; the sheet will be rewritten in step 5, keeping its "## Suivi" section.

## Step 3 - Branch
- If the current branch name already contains the key, keep it and say "Branche déjà en place".
- Otherwise:
  1. If there are uncommitted or untracked files in the workflow state, ask me with the question tool: "Annuler, je commite d'abord" (recommandé) / "Mettre de côté (stash) et continuer". Stash only if I choose it (`git stash push -u -m "ticket <KEY>"`).
  2. Read the ticket type and summary with the Jira MCP tools.
  3. Propose the branch name: `feature/<KEY>-<summary in 3 to 5 kebab-case words, ASCII, lowercase>`; `bugfix/` for a bug; `hotfix/` if the ticket is marked urgent or as a production incident. Ask me with the question tool: "<proposed name>" (recommandé) / "Autre nom" (free answer).
  4. If a local or remote branch for this key already exists (`git branch -a --list "*<KEY>*"`), ask me with the question tool: "Basculer sur <existing branch>" (recommandé) → `git switch <existing branch without remotes/origin/>` / "Créer une nouvelle branche".
  5. New branch from the base branch of the workflow state (normally `origin/develop`): `git fetch origin <base without origin/>`, then `git switch -c <name> <base>`.
  6. Ask me with the question tool: "Publier plus tard, au premier /ship" (recommandé) / "Publier la branche maintenant (git push -u)".
  7. If a stash was made, ask me with the question tool: "Réappliquer mes modifications sur la branche" (recommandé) → `git stash pop` / "Les laisser dans le stash".

## Step 4 - Analysis
Invoke the `analyst` subagent with the task tool, with this prompt (replace the placeholders):

"Analyze Jira ticket <KEY> for the repository at <repository root>, project type <type from the detection above, or the "Project type" section of AGENTS.md>. Read-only everywhere.
1. Read the ticket with the Jira MCP tools: summary, description, acceptance criteria, comments, linked issues, attachments list, epic.
2. Read the Confluence pages linked from the ticket or its epic. If none are linked, search Confluence for the 3 most relevant pages using the ticket's key terms. Read only what is relevant.
3. Search the repository (read, grep, glob tools) for the code areas involved: endpoints, controllers, handlers, services, components, integrations.
Answer in French, complete (do not shorten), in markdown, with exactly these sections:
## Résumé — what is asked, in 3 sentences.
## Critères d'acceptation — numbered list (C1, C2...). If the ticket has none, deduce them and mark each "(déduit)".
## Questions ouvertes — ambiguities to clarify with the product owner before coding, written ready to paste as a Jira comment (do not post it). "Aucune" if none.
## Zones de code concernées — file paths and why.
## Tests attendus — table | # | Critère | Test (class and scenario) | Statut |, one row per test, every criterion covered at least once, Statut = "à écrire".
## Plan — ordered checklist `- [ ] 1. ...`, each step leaving the project building. Mention /cqrs only if the project type is cqrs-api and a step creates a command or query. If an available skill whose name starts with `pattern-` matches a step (e.g. health checks, unit tests), name it in that step: "(s'appuyer sur le skill pattern-<name>)".
## Sources — the Jira key and the Confluence page titles used."

## Step 5 - Ticket sheet
Write the file `<repository root>/.git/opencode/tickets/<KEY>.md` with the write tool, exactly:

```
# <KEY> - <summary>
- Jira : <link to the ticket: Jira URL of the "Daily" section of AGENTS.md, otherwise scheme and host of the self URL returned by the Jira tools, + /browse/<KEY>>
- Branche : <branch>
- Type de projet : <type>
- Créée le : <date from `date "+%Y-%m-%d %H:%M"`>

<the analyst answer, sections unchanged>

## Décisions
(choix faits pendant le développement, ajoutés par /dev)

## Suivi
- <date> /ticket - fiche créée
```
When the analysis is redone, keep the previous "## Suivi" lines and add `- <date> /ticket - analyse refaite`. Never write any other file.

## Step 6 - Answer, in French
- First line: "**[<KEY>](<Jira link>) - <summary>**".
- The branch state (see your general rules).
- The sections "Résumé", "Critères d'acceptation", "Questions ouvertes" and "Plan" of the sheet.
- One last line: "Prochaine étape : /dev (étape 1, tu peux ajouter des directives : /dev comme dans <repo>, /dev avec un Result…), puis /test, /check et /ship. En cas de doute : /next. Astuce : une session OpenCode par ticket ; pour reprendre plus tard, nouvelle session puis /next."
