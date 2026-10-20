---
description: "Start (or resume) a Jira ticket: pick it from my sprint if no key is given, create the branch from an up-to-date develop, analyze the ticket, its Confluence pages and the code, and save the ticket sheet used by /dev, /test, /check, /ship and /next. Usage: /ticket [JIRA-KEY]"
agent: git
---
Ticket given: "$1"
Workflow state (fetch of every branch, then the state of the branch and of its ticket sheet):
[[run workflow-state.sh --fetch-all --sheet]]
Project detection:
[[run detect-project-type.sh]]

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
- "Reprendre la fiche existante" (recommandé): use the sheet printed in the workflow state when I am on its branch; otherwise run step 3 to get there and read the sheet; show the sections "Critères d'acceptation", "Plan" (unchecked steps) and the last 3 lines of "Suivi", then tell me the next step (last line of step 5) and stop.
- "Refaire l'analyse": continue; step 4 rewrites the sheet and keeps its "## Décisions" and "## Suivi" sections.

## Step 3 - Branch
- If the "Fetch:" line of the workflow state says AUTH FAILED and the branch must be created or switched: stop before it, as your rule on GitLab credentials says (develop could not be brought up to date).
- If the current branch name already contains the key, keep it and say "Branche déjà en place".
- Otherwise:
  1. In one turn: read the ticket type and summary with the Jira MCP tools, and list the branches of this key with `git branch -a --list "*<KEY>*"`.
  2. Ask me everything in ONE question tool call:
     - "Branche", with the repository folder name in the question ("Branche dans <folder name of the Repository root line>"), so that I notice a wrong repository before anything is created: if a local or remote branch of this key exists, "Basculer sur <existing branch>" (recommandé) and "Créer <proposed name>"; otherwise "<proposed name>" (recommandé). Proposed name: `feature/<KEY>-<summary in 3 to 5 kebab-case words, ASCII, lowercase>`, `bugfix/` for a bug, `hotfix/` if the ticket is marked urgent or as a production incident. I can type another name.
     - "Publication", only for a new branch: "Publier plus tard, au premier /ship" (recommandé) / "Publier la branche maintenant (git push -u)".
     - "Modifications en cours", only if the workflow state shows uncommitted or untracked files: "Annuler, je commite d'abord" (recommandé) / "Les emporter sur la branche du ticket" / "Les laisser de côté (stash)".
  3. Then run, in this order:
     - "Annuler, je commite d'abord": stop.
     - "Les emporter" or "Les laisser de côté": `git stash push -u -m "ticket <KEY>"`.
     - Existing branch: `git switch <existing branch without remotes/origin/>`. New branch, from the base branch of the workflow state (normally `origin/develop`), in one call: `git fetch -q origin <base without origin/> && git switch -c <name> <base>`.
     - "Publier la branche maintenant": `git push -u origin <name>`.
     - "Les emporter": `git stash pop`.

## Step 4 - Analysis and ticket sheet
Invoke the `analyst` subagent with the task tool, with this prompt (replace the placeholders; the date is the "Now" line of the workflow state):

"Analyze Jira ticket <KEY> for the repository at <repository root>, project type <type from the detection above, or the "Project type" section of AGENTS.md>, branch <branch>. Read-only everywhere, except the ticket sheet of step 4. Send independent calls together in one turn: first the ticket, its epic and its linked issues; then the Confluence pages and the code searches.
1. Read the ticket with the Jira MCP tools: summary, description, acceptance criteria, comments, linked issues, attachments list, epic.
2. Read the Confluence pages linked from the ticket or its epic. If none are linked, search Confluence for the 3 most relevant pages using the ticket's key terms. Read only what is relevant.
3. Search the repository (read, grep, glob tools) for the code areas involved: endpoints, controllers, handlers, services, components, integrations.
4. Write the ticket sheet `<repository root>/.git/opencode-tickets/<KEY>.md` with the write tool, in French, complete (do not shorten), exactly in this format. If the file already exists, read it first: keep its "Créée le" date and its "## Décisions" lines, keep its "## Suivi" lines and add `- <date> /ticket - analyse refaite`.

# <KEY> - <summary>
- Jira : <link to the ticket: Jira URL of the "Daily" section of AGENTS.md, otherwise scheme and host of the self URL returned by the Jira tools, + /browse/<KEY>>
- Branche : <branch>
- Type de projet : <type>
- Créée le : <date>

## Résumé
What is asked, in 3 sentences.
## Critères d'acceptation
Numbered list (C1, C2...). If the ticket has none, deduce them and mark each "(déduit)".
## Questions ouvertes
Ambiguities to clarify with the product owner before coding, written ready to paste as a Jira comment (do not post it). "Aucune" if none.
## Zones de code concernées
File paths and why.
## Tests attendus
Table | # | Critère | Test (class and scenario) | Statut |, one row per test, every criterion covered at least once, Statut = "à écrire".
## Plan
Ordered checklist `- [ ] 1. ...`, each step leaving the project building. Mention /cqrs only if the project type is cqrs-api and a step creates a command or query. If an available skill whose name starts with `pattern-` matches a step (e.g. health checks, unit tests), name it in that step: "(s'appuyer sur le skill pattern-<name>)". For a Bug that a unit test can reproduce, the fix step ends with "(test d'abord)": /dev then writes the test that reproduces the bug and checks that it fails before fixing it. If no unit test can reproduce it (configuration, environment, external system), write in "Zones de code concernées" how to reproduce it (request and payload, logs to search).
## Sources
The Jira key and the Confluence page titles used.

## Décisions
(choix faits pendant le développement, ajoutés par /dev)

## Suivi
- <date> /ticket - fiche créée

5. Answer with ONLY the sections "Résumé", "Critères d'acceptation", "Questions ouvertes" and "Plan" as written in the sheet, then one last line: "Fiche écrite : <path>"."

If the analyst's answer does not end with "Fiche écrite", write the sheet yourself with the write tool from its answer, in the same format. Never write any other file.

## Step 5 - Answer, in French
- First line: "**[<KEY>](<Jira link>) - <summary>**".
- The branch state (see your general rules).
- The sections "Résumé", "Critères d'acceptation", "Questions ouvertes" and "Plan" returned by the analyst, unchanged.
- One line: "Ensuite : /dev étape par étape, puis /test, /check et /ship. Pour reprendre plus tard : nouvelle session puis /next."
- Then the next step with the question tool (header "Suite"): "/dev 1 (recommandé)" (description: « Étape 1 : <its text> ; pour ajouter des directives, tape-la en réponse libre : /dev 1 avec un Result… ») and "Rien pour l'instant"; the pack plugin starts the command I choose by itself as soon as your turn ends: then answer only « Je lance <command>. ».
