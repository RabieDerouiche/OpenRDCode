---
description: "One release note for a production deployment spanning several repositories (back, front, libraries), grouped by Jira ticket, published to Confluence after approval. Usage: /release-notes-group <group name> [previous deployment date YYYY-MM-DD]"
agent: release-writer
---
Release group: "$1"
Date argument: "$2"

Write ONE release note covering every repository of the release group "$1".

Rules:
- Collect data only with `sh ~/.config/opencode/scripts/release-commits.sh <repository path> <from> [<to>]`, one call per repository. Never run git yourself in these repositories.
- Never write anything in the repositories, Jira, GitLab, SonarQube or Fortify.

Steps:
1. Read the section "Release groups" of AGENTS.md and find the group "$1": Confluence space key, release notes parent page, application name, and the list of repositories (label + absolute path). If the group is missing, ask me with the question tool (multiple choice, recommended option first) with the existing groups as options; if there is none, ask me for the values (free answer) and remind me to add them to AGENTS.md.
2. Determine `from` for each repository:
   - If a date is given ("$2"), use it for every repository.
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
