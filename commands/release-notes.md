---
description: "Draft release notes from the commits between two git refs (or from a free-text description), enrich them with Jira, and publish to Confluence after approval. Usage: /release-notes [from-ref] [to-ref] — or /release-notes <description of the changes>"
agent: release-writer
---
Fetch tags: !`git fetch -q --tags origin`

Most recent tags:
!`git for-each-ref --sort=-creatordate --count=10 --format='%(refname:short)' refs/tags`

Arguments: "$ARGUMENTS"

Steps:
1. Read AGENTS.md for the sections "Confluence" and "Releases" (space key, release notes parent page, how production releases are marked, application name). If they are missing, say which values are missing and stop.
2. Determine the input:
   - If the arguments are empty: the range is from the second most recent tag to the most recent tag listed above. If there are fewer than 2 tags, ask me for the range and stop.
   - If the arguments are one or two valid git refs (check each with `git rev-parse --verify <ref>`): from = first ref, to = second ref (default: the most recent tag).
   - Otherwise: the arguments are a free-text description of the changes. Use it as the source instead of git history, and skip step 3.
3. Run `git log --no-merges --format=%h%x09%an%x09%s <from>..<to>` and collect every Jira key (pattern `[A-Z][A-Z0-9]+-[0-9]+`) from the commit messages.
4. For each Jira key, read the ticket with the Jira MCP tools: type, summary, status, epic. Do not change anything in Jira.
5. Read the most recent release note under the parent page in Confluence and mirror its structure, title format and tone. If none exists, use the structure below.
6. Write the draft:

   # <Application name> — Release <to-ref> — <date of the to-ref tag, YYYY-MM-DD>
   ## Résumé
   2-3 sentences for business readers.
   ## Nouveautés
   One line per feature ticket: what changes for users, then (JIRA-KEY).
   ## Corrections
   One line per bug ticket: what was wrong, now fixed, then (JIRA-KEY).
   ## Sécurité et qualité
   Fortify / Sonar / dependency fixes, without vulnerability details that could help an attacker.
   ## Technique
   Refactorings, dependency upgrades, configuration changes, migrations.
   ## Points d'attention pour le déploiement
   Configuration or environment variables to add, migrations, breaking API changes, or "Aucun".
   ## Commits sans ticket
   Commits with no Jira key, one line each (short hash + message), so a human can classify them.

7. Show me the full draft.
8. Publish it as a child page of the release notes parent page, in the configured space, with the title from the draft. The publication will ask for my approval: if I refuse, stop and keep the draft as the final answer.
9. Final answer: the page title and link if published, otherwise the draft in a markdown code block.
