---
description: "Draft release notes for a production deployment from master (or from a free-text description), enrich them with Jira, and publish to Confluence after approval. Usage: /release-notes [previous-deployed-commit|YYYY-MM-DD] [deployed-commit] — or /release-notes <description of the changes>"
agent: release-writer
---
Fetch master: !`git fetch -q origin master`

Current master: !`git log -1 --format='%H %cs %s' origin/master`

Arguments: "$ARGUMENTS"

Production is deployed from the `master` branch as is; there are no release tags.

Steps:
1. Read AGENTS.md for the sections "Confluence" and "Releases" (space key, release notes parent page, application name). For each missing value, ask me with the question tool (multiple choice, recommended option first) (free answer), then remind me to add it to AGENTS.md.
2. Determine the range of this release. `from` is the commit of the PREVIOUS deployment (excluded: it belongs to the previous release); `to` is the commit deployed in THIS release (included).
   - No arguments: `from` = the commit hash written after "Commit master déployé" in the most recent release note under the parent page in Confluence; `to` = current `origin/master`. If there is no previous release note or no hash in it, ask me with the question tool (multiple choice, recommended option first): "Depuis une date" / "Depuis un commit" / "Je décris les changements en texte libre", then ask for the value.
   - One argument that is a commit hash or ref: `from` = that commit, `to` = current `origin/master`.
   - Two arguments that are commit hashes or refs: `from` = first argument, `to` = second argument. Commits after `to` are NOT part of this release.
   - First argument is a date `YYYY-MM-DD`: commits of `to` (second argument, or `origin/master`) committed after that date.
   - Check every ref with `git rev-parse --verify <ref>`; if one is invalid, say so and ask me with the question tool (multiple choice, recommended option first) for the correct one (free answer).
   - Otherwise: the arguments are a free-text description of the changes. Use it as the source instead of git history and skip step 3.
   - Always state the resolved range in one line before the draft: "Plage : <from> (exclu) → <to> (inclus), <n> commits".
3. Collect the changes, running one command per call:
   - Merged merge requests: `git log --first-parent --merges --format=%h%x09%cs%x09%s <from>..<to>`
   - All commits: `git log --no-merges --format=%h%x09%an%x09%s <from>..<to>`
   Collect every Jira key (pattern `[A-Z][A-Z0-9]+-[0-9]+`) from merge request titles, branch names in merge messages and commit messages.
4. For each Jira key, read the ticket with the Jira MCP tools: type, summary, status, epic. Do not change anything in Jira.
5. Read the most recent release note under the parent page and mirror its structure, title format and tone. If none exists, use the structure below.
6. Write the draft:

   # <Application name> — Release du <date of the `to` commit, YYYY-MM-DD>
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
   - Commit master déployé : <full hash of `to`>
   - Depuis : <from, full hash or date>

   The "Commit master déployé" line is mandatory: the next run uses it as its starting point.

7. Show me the full draft.
8. Publish it as a child page of the release notes parent page, in the configured space, with the title from the draft. The publication will ask for my approval: if I refuse, stop and keep the draft as the final answer.
9. Final answer: the page title and link if published, otherwise the draft in a markdown code block.
