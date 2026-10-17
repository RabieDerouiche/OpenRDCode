---
description: "After a push: check the CI pipeline of the pushed commit, then merge the SonarQube and Fortify results of this branch into one prioritized, deduplicated list with the fixes to run (read-only). Usage: /scans [ssc-application:version]"
agent: analyst
---
Explicit Fortify target: "$ARGUMENTS"

Remote base branches: !`git branch -r --list origin/develop origin/main origin/master`

Base branch: `origin/develop` if it is listed above. Otherwise, if exactly one of `origin/main` / `origin/master` is listed, use it; if none or several, ask me with the question tool (multiple choice, recommended option first) with the listed branches as options. If the git output injected below failed because `origin/develop` does not exist, run the same git commands yourself with the chosen base, one command per call.

SSC application line (from appsec-ci.env): !`git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'`
Current git branch: !`git branch --show-current`
Remote: !`git remote get-url origin`
Fetch: !`git fetch -q origin`
Local HEAD: !`git rev-parse HEAD`
Pushed commit (origin of this branch): !`git rev-parse @{u}`
Local commits not pushed: !`git log --oneline @{u}..HEAD`
Files changed on this branch: !`git diff --name-only origin/develop...HEAD`

Sonar and Fortify both run in the CI on every pushed commit. Never read appsec-ci.env yourself: it may contain secrets; use only the line injected above (the SSC application is the value after `=`, without quotes). Read-only everywhere: never mark an issue as false positive, never change a status, never comment.

## Step 1 - Pushed or not
- If "Pushed commit" above is an error (no upstream), the branch was never pushed: say "Branche jamais poussée : lance /ship" and stop.
- If there are local commits not pushed, say in one line that the scans will not include them (suggest /ship), and continue with the pushed commit.

## Step 2 - Pipeline of the pushed commit
With the GitLab MCP tools (read-only), find the project from the remote URL above (its path after the host, without `.git`), then the most recent pipeline for this branch whose commit SHA is the pushed commit.
- No pipeline for this SHA yet: say "Pipeline pas encore créé pour <short sha>, relance /scans dans quelques minutes" and stop.
- Running or pending: list the jobs by stage with their status, say "Relance /scans quand le pipeline est terminé" and stop.
- Failed: list the failed jobs. For each, read the end of the job log (last 50 lines) if the tools allow it and explain the cause in 2 lines. If the build or test job failed: "Corrige avec l'agent build (« corrige le build, voici l'erreur : ... »), puis /check et /ship". If a Sonar or Fortify job failed, say that its results are missing or outdated, and continue with step 3 for the other one.
- Success: continue.
Give the pipeline link (`web_url`).

## Step 3 - Fortify
1. If an explicit target is given above, use it as is and go to 4.
2. If the SSC application line above is empty, ask me with the question tool (multiple choice, recommended option first) for the SSC application name (free answer). Do not search for it yourself.
3. List ALL versions of that SSC application. Do not guess version names. Then select the version:
   a. Look for a version matching the current branch, in this order: the exact branch name, then the branch name with `/` replaced by `-`, then with `/` replaced by `_`.
   b. If a matching version exists AND it has at least one uploaded scan (artifact), use it.
   c. Otherwise use the `develop` version.
   d. If the current branch is empty (detached HEAD), use `develop`.
   e. If `develop` does not exist either, ask me with the question tool (multiple choice, recommended option first) with the available versions as options.
4. Freshness: compare the date of the latest uploaded artifact with the date of the pushed commit (`git log -1 --format=%cI @{u}`). If the artifact is older, say "Scan Fortify pas encore à jour (dernier upload <date>) : relance /scans plus tard" and still show the current results, marked "anciens".
5. List the issues with the filter set "Security Auditor View". Never invent application, version, filter set or filter names; if one is rejected, list the valid ones and retry with a listed value. Load the skill `fortify-remediation` to classify each category and spot likely false positives.

## Step 4 - SonarQube
Find the Sonar project of this repository (search by repository name or by the SSC application name; if several match, ask me with the question tool with the candidates as options). Get the open issues and security hotspots of this branch. If the analysis exposes its revision or date, check it matches the pushed commit; otherwise say "Analyse Sonar pas encore à jour". If the branch is not analyzed, use the main branch and say so.

## Step 5 - Merge and prioritize
- If Fortify and Sonar report the same problem at the same file and line (or within 3 lines), keep one entry and mention both sources.
- Order: security first (Fortify Critical/High, Sonar vulnerabilities and hotspots), then bugs, then code smells. Inside each group, findings in files changed on this branch come first, then exploitability, then effort.

## Answer, in French
First line: "**Ticket <KEY> - <title>**" with the title taken from the first line of the ticket sheet (`# <KEY> - <title>`), or from Jira if there is no sheet, or the branch name if there is no key.
- Then: "Pipeline <link> (<short sha>) : <status> — Fortify : <application:version> (raison : <explicit target | current branch has scans | fallback to develop: no version for branch | fallback to develop: branch version has no scan>) — Sonar : <project> / <branch>".
- Table: priorité, source (Fortify/Sonar/les deux), Fortify issue id ou Sonar issue key, règle ou catégorie, sévérité, fichier:ligne, modifié sur cette branche (oui/non).
- Counts per source and severity (Fortify: Critical, High, Medium, Low).
- "Faux positifs probables": issue ids with a one-line reason (e.g. the value never comes from user input).
- "À corriger en premier": the 5 findings to fix first, each with its command: `/fortify-fix <id>` for Fortify, `/sonar-fix <issue key>` for Sonar, `/fortify-fix` for a finding reported by both.
- If nothing is open on the files of this branch: "Rien à corriger sur cette branche : la MR est prête côté qualité."
