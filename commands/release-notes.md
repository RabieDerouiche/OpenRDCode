---
description: "Release note of a production deployment, published to Confluence after approval. One repository (deployed from master), or a release group of several repositories (back, front, libraries) grouped by Jira ticket, or a free-text description. Usage: /release-notes [group name [YYYY-MM-DD]] | [previous-deployed-commit|YYYY-MM-DD] [deployed-commit] | <description of the changes>"
agent: release-writer
subtask: false
---
Arguments: "$ARGUMENTS"
Current repository and its production branch (after fetch):
[[run release-commits.sh . --head]]

## Step 0 - Mode
Use the section "Release groups" of AGENTS.md (already in your instructions: do not read the file).
- If the first argument is the name of a group there: GROUP MODE with that group (the optional second argument is a date `YYYY-MM-DD`).
- Otherwise, if there are no arguments and the "Repository path" above is listed in a group: ask me with the question tool: "Release note du groupe <group>" (recommandé) / "Seulement ce dépôt". 
- Otherwise: SINGLE REPOSITORY MODE with the arguments as given.
Say the mode in one line before anything else.

# SINGLE REPOSITORY MODE

Production is deployed from the `master` branch as is; there are no release tags.

Steps (single repository mode):
1. Use the sections "Confluence" and "Releases" of the repository AGENTS.md, already in your instructions (space key, release notes parent page, application name). For each missing value, ask me with the question tool (multiple choice, recommended option first) (free answer), then remind me to add it to AGENTS.md.
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
   Collect every Jira key (pattern `[A-Z][A-Z0-9_]+-[0-9]+`) from merge request titles, branch names in merge messages and commit messages.
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

# GROUP MODE

Write ONE release note covering every repository of the release group "<group name>".

Rules:
- Collect data only with `sh ~/.config/opencode/scripts/release-commits.sh <repository path> <from> [<to>]`, one call per repository. Never run git yourself in these repositories.
- Never write anything in the repositories, Jira, GitLab, SonarQube or Fortify.

Steps:
1. In the section "Release groups" of AGENTS.md, find the group "<group name>": Confluence space key, release notes parent page, application name, and the list of repositories (label + absolute path). If the group is missing, ask me with the question tool (multiple choice, recommended option first) with the existing groups as options; if there is none, ask me for the values (free answer) and remind me to add them to AGENTS.md.
2. Determine `from` for each repository:
   - If a date is given (second argument), use it for every repository.
   - Otherwise read the most recent release note of this group under the parent page in Confluence: its section "Informations de déploiement" has one line per repository "<label> : <full hash>". Use that hash as `from` for that repository.
   - For a repository with no previous hash (new repository, first release note), ask me with the question tool: "Depuis une date" / "Depuis un commit" / "Ne pas inclure ce dépôt", then ask for the value.
   - `to` is the current production branch of each repository (default of the script). If I say some commits on master are not deployed yet, ask me for the deployed commit of each repository and pass it as `<to>`.
3. Run the script for each repository and keep its output. If a repository returns an ERROR line, say so and ask me how to proceed (fix the value / skip the repository).
4. Merge across repositories BY JIRA TICKET, not by repository:
   - Collect every Jira key from all repositories, read each ticket once with the Jira MCP tools (type, summary, status, epic).
   - One line per ticket, followed by the repositories it touched, e.g. `[Back] [Front]`. A ticket touching several repositories appears ONCE.
   - Commits without a Jira key stay listed per repository at the end.
   - Library repositories: report their version change (from the "Version changes" section). If another repository of the group bumped its reference to that library in the same release, say it on the library line ("utilisée par Back en 2.3.0").
5. Read the most recent release note of this group under the parent page and mirror its structure, title format and tone. Otherwise use:

   # <Application name> — Release du <latest deployed commit date among repositories, YYYY-MM-DD>
   ## Résumé
   2-3 sentences for business readers.
   ## Nouveautés
   One line per feature ticket: what changes for users, (JIRA-KEY) [repositories].
   ## Corrections
   One line per bug ticket, (JIRA-KEY) [repositories].
   ## Sécurité et qualité
   Fortify / Sonar / dependency fixes, without vulnerability details that could help an attacker.
   ## Technique
   Refactorings, dependency and library version upgrades, configuration changes, migrations.
   ## Points d'attention pour le déploiement
   Deployment order between repositories if one depends on another (for example library before back, back before front when the API contract changed), configuration to add, breaking API changes, or "Aucun".
   ## Commits sans ticket
   Per repository: short hash + message.
   ## Informations de déploiement
   One line per repository, mandatory for the next release note: `<label> : <full hash of the deployed commit>`.

6. Before the draft, write one line per repository: "<label> : <range from the script>, <n> commits".
7. Show me the full draft, then publish it as a child page of the parent page in the configured space. The publication asks for my approval: if I refuse, stop and keep the draft as the final answer.
