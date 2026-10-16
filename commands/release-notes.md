---
description: "Draft release notes for what was deployed from master (or from a free-text description), enrich them with Jira, and publish to Confluence after approval. Usage: /release-notes [previous deployed commit or date YYYY-MM-DD] — or /release-notes <description of the changes>"
agent: release-writer
---
Fetch master: !`git fetch -q origin master`

Current master (what is deployed): !`git log -1 --format='%H %cs %s' origin/master`

Arguments: "$ARGUMENTS"

Production is deployed from the `master` branch as is; there are no release tags.

Steps:
1. Read AGENTS.md for the sections "Confluence" and "Releases" (space key, release notes parent page, application name). If they are missing, say which values are missing and stop.
2. Determine the starting point (`from`) of this release:
   - If the arguments are empty: read the most recent release note under the parent page in Confluence and take the commit hash written after "Commit master déployé". If there is no previous release note or no hash in it, ask me for the previous deployed commit or a date and stop.
   - If the arguments are a commit hash or ref: check it with `git rev-parse --verify <ref>` and use it as `from`.
   - If the arguments are a date `YYYY-MM-DD`: use the commits of `origin/master` since that date (`git log --since=<date> ...`).
   - Otherwise: the arguments are a free-text description of the changes. Use it as the source instead of git history and skip step 3.
3. Collect the changes, running one command per call:
   - Merged merge requests: `git log --first-parent --merges --format=%h%x09%cs%x09%s <from>..origin/master`
   - All commits: `git log --no-merges --format=%h%x09%an%x09%s <from>..origin/master`
   Collect every Jira key (pattern `[A-Z][A-Z0-9]+-[0-9]+`) from merge request titles, branch names in merge messages and commit messages.
4. For each Jira key, read the ticket with the Jira MCP tools: type, summary, status, epic. Do not change anything in Jira.
5. Read the most recent release note under the parent page and mirror its structure, title format and tone. If none exists, use the structure below.
6. Write the draft:

   # <Application name> — Release du <date of current master commit, YYYY-MM-DD>
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
   ## Informations de déploiement
   - Commit master déployé : <full hash of current master>
   - Depuis : <from, full hash or date>

   The "Commit master déployé" line is mandatory: the next run uses it as its starting point.

7. Show me the full draft.
8. Publish it as a child page of the release notes parent page, in the configured space, with the title from the draft. The publication will ask for my approval: if I refuse, stop and keep the draft as the final answer.
9. Final answer: the page title and link if published, otherwise the draft in a markdown code block.
