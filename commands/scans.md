---
description: "After a push: check the CI pipeline of the pushed commit, then merge the SonarQube and Fortify results of this branch into one prioritized, deduplicated list with the fixes to run (read-only). Usage: /scans [ssc-application:version]"
agent: analyst
subtask: false
---
Explicit Fortify target: "$ARGUMENTS"

Base branch: the "Base branch" line of the workflow state (origin/develop, otherwise origin/main or origin/master). If it says NONE, ask me with the question tool for the base branch (free answer).

Workflow state (one fetch, then the state of the branch, the SSC application line and the ticket sheets):
[[run workflow-state.sh --appsec]]

Sonar and Fortify both run in the CI on every pushed commit. Never read appsec-ci.env yourself: it may contain secrets; use only the "Fortify SSC application line" of the workflow state (the SSC application is the value after `=`, without quotes). Read-only everywhere: never mark an issue as false positive, never change a status, never comment.

Speed: send the independent MCP calls together. First turn: the pipeline of the pushed commit (step 2), the versions of the SSC application (step 3) and the search of the Sonar project (step 4). Second turn: the Fortify issues of the selected version, the Sonar issues and security hotspots of the branch, and the skill `fortify-remediation`. If step 2 stops, ignore the other results.

## Step 1 - Pushed or not
- If the workflow state says "Upstream: none", the branch was never pushed: say "Branche jamais poussée : lance /ship" and stop.
- If there are local commits not pushed, say in one line that the scans will not include them (suggest /ship), and continue with the pushed commit.

## Step 2 - Pipeline of the pushed commit
With the GitLab MCP tools (read-only), find the project from the "Remote URL" line of the workflow state (its path after the host, without `.git`), then the most recent pipeline for this branch whose commit SHA is the pushed commit.
- No pipeline for this SHA yet: say "Pipeline pas encore créé pour <short sha>, relance /scans dans quelques minutes" and stop.
- Running or pending: list the jobs by stage with their status, say "Relance /scans quand le pipeline est terminé" and stop.
- Failed: list the failed jobs. For each, read the end of the job log (last 50 lines) if the tools allow it and explain the cause in 2 lines. If the build or test job failed: "Corrige avec l'agent build (« corrige le build, voici l'erreur : ... »), puis /check et /ship". If a Sonar or Fortify job failed, say that its results are missing or outdated, and continue with step 3 for the other one.
- Success: continue.
Give the pipeline link (`web_url`).

## Step 3 - Fortify
1. If an explicit target is given above, use it as is and go to 4.
2. If the "Fortify SSC application line" of the workflow state says none, ask me with the question tool (multiple choice, recommended option first) for the SSC application name (free answer). Do not search for it yourself.
3. List ALL versions of that SSC application. Do not guess version names. Then select the version:
   a. Look for a version matching the current branch, in this order: the exact branch name, then the branch name with `/` replaced by `-`, then with `/` replaced by `_`.
   b. If a matching version exists AND it has at least one uploaded scan (artifact), use it.
   c. Otherwise use the `develop` version.
   d. If the current branch is empty (detached HEAD), use `develop`.
   e. If `develop` does not exist either, ask me with the question tool (multiple choice, recommended option first) with the available versions as options.
4. Freshness: compare the date of the latest uploaded artifact with the "Pushed commit date" of the workflow state. If the artifact is older, say "Scan Fortify pas encore à jour (dernier upload <date>) : relance /scans plus tard" and still show the current results, marked "anciens".
5. List the issues with the filter set "Security Auditor View". Never invent application, version, filter set or filter names; if one is rejected, list the valid ones and retry with a listed value. Use the skill `fortify-remediation` to classify each category and spot likely false positives.

## Step 4 - SonarQube
Find the Sonar project of this repository (search by repository name or by the SSC application name; if several match, ask me with the question tool with the candidates as options). Get the open issues and security hotspots of this branch. If the analysis exposes its revision or date, check it matches the pushed commit; otherwise say "Analyse Sonar pas encore à jour". If the branch is not analyzed, use the main branch and say so.

## Step 5 - Merge and prioritize
- If Fortify and Sonar report the same problem at the same file and line (or within 3 lines), keep one entry and mention both sources.
- Order: security first (Fortify Critical/High, Sonar vulnerabilities and hotspots), then bugs, then code smells. Inside each group, findings in files changed on this branch come first, then exploitability, then effort.

## Answer, in French
First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name.
- Then: "Pipeline <link> (<short sha>) : <status> — Fortify : <application:version> (raison : <explicit target | current branch has scans | fallback to develop: no version for branch | fallback to develop: branch version has no scan>) — Sonar : <project> / <branch>".
- Table: priorité, source (Fortify/Sonar/les deux), Fortify issue id ou Sonar issue key, règle ou catégorie, sévérité, fichier:ligne, modifié sur cette branche (oui/non).
- Counts per source and severity (Fortify: Critical, High, Medium, Low).
- "Faux positifs probables": issue ids with a one-line reason (e.g. the value never comes from user input).
- "À corriger en premier": the 5 findings to fix first, each with its command: `/fortify-fix <id>` for Fortify, `/sonar-fix <issue key>` for Sonar, `/fortify-fix` for a finding reported by both.
- If nothing is open on the files of this branch: "Rien à corriger sur cette branche : la MR est prête côté qualité."

## Ticket sheet
If the workflow state lists a current ticket sheet, append a line at the end of its "## Suivi" section, which ends the file, with the edit tool: insert it after the last Suivi line given by the "Ticket sheets summary" of the workflow state (read the sheet only if that edit fails). Date: the "Now" line of the workflow state.
`- <date> /scans - <short sha> - pipeline <success|failed|running> - <n> points à corriger sur la branche`
Write nothing else.
