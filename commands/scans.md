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

Speed: send the independent MCP calls together. First turn: the pipeline of the pushed commit (step 2), the versions of the SSC application (step 3) and the search of the Sonar project (step 4). Second turn: the jobs of that pipeline, the Fortify issues of the selected version, the first page of Sonar issues and the security hotspots of the branch (step 4), and the skill `fortify-remediation`. If step 2 stops, ignore the other results.

## Step 1 - Pushed or not
- If the workflow state says "Upstream: none", the branch was never pushed: say "Branche jamais poussée" and ask me with the question tool (header "Suite"): "/ship (recommandé)" (description: « commit et push : la CI lance Sonar et Fortify ») / "Rien pour l'instant"; the pack plugin starts the command I choose by itself as soon as your turn ends: then answer only « Je lance <command>. » and stop.
- If there are local commits not pushed, say in one line that the scans will not include them (suggest /ship), and continue with the pushed commit.

## Step 2 - Pipeline of the pushed commit
With the GitLab MCP tools (read-only), find the project from the "Remote URL" line of the workflow state (its path after the host, without `.git`), then the most recent pipeline for this branch whose commit SHA is the pushed commit, and its jobs.
- No pipeline for this SHA yet: say "Pipeline pas encore créé pour <short sha>, relance /scans dans quelques minutes" and stop.
- The scan jobs are the jobs whose name contains `sonar` or `fortify` (any case). The other jobs (container scan, deployment...) never make you wait: when the scan jobs are finished, continue even if the pipeline is still running, and name the jobs still running in the pipeline line of the answer.
  - A scan job still running, pending or created: continue with the other tool only, and end its line of the answer (see below) with « ⏳ en cours (job <name>) : relance /scans quand il est fini ». Both still running: list the remaining jobs in one line, say "Relance /scans quand ils sont finis" and stop.
  - No job name contains `sonar` or `fortify`: the scans run inside other jobs; if the pipeline is running or pending, list its remaining jobs in one line, say "Relance /scans quand le pipeline est terminé" and stop.
- Failed: list the failed jobs. For each, read the end of the job log (last 50 lines) if the tools allow it and explain the cause in 2 lines. If the build or test job failed: "Corrige avec l'agent build (« corrige le build, voici l'erreur : ... »), puis /check et /ship". If a Sonar or Fortify job failed, say that its results are missing or outdated, and continue with step 3 for the other one.
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
5. List the issues with the filter set "Security Auditor View", at most 20 per call as in step 4 (Critical and High first, then the others while there is room). Never invent application, version, filter set or filter names; if one is rejected, list the valid ones and retry with a listed value. Use the skill `fortify-remediation` to classify each category and spot likely false positives.

## Step 4 - SonarQube
Find the Sonar project of this repository (search by repository name or by the SSC application name; if several match, ask me with the question tool with the candidates as options). Get the open issues and the security hotspots of this branch:
- At most 20 issues per call (`pageSize` 20 or less), with the tool's filters on status (open), severity and type when it has them: a bigger answer is cut by OpenCode and saved to a file that is one long line of JSON, useless to search. If an answer still says it was truncated or saved to a file, never search that file: call the tool again with a smaller page or stricter filters.
- Pages: first the issues of severity BLOCKER, CRITICAL and MAJOR (or impact BLOCKER and HIGH), then, while there is room, the others; say how many were not read.
If the analysis exposes its revision or date, check it matches the pushed commit; otherwise say "Analyse Sonar pas encore à jour". If the branch is not analyzed, use the main branch and say so.

## Step 5 - Merge and prioritize
- If Fortify and Sonar report the same problem at the same file and line (or within 3 lines), keep one entry and mention both sources.
- Order: security first (Fortify Critical/High, Sonar vulnerabilities and hotspots), then bugs, then code smells. Inside each group, findings in files changed on this branch come first, then exploitability, then effort.

## Answer, in French
Markdown, in this order and exactly this shape (an empty section is left out, except the counts).

First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, both from Jira; without a Jira key, the branch name.

Then a quote block of three lines, kept apart by the lines with `>` alone (without them, Markdown joins the three lines into one):
> <🟢 | 🟡 | 🔴> **Pipeline** [#<id>](<web_url>) · `<short sha>` · <réussi | en cours (jobs restants : <names>) | échoué (<failed jobs>)>
>
> 🏰 **Fortify** `<application:version>` · <cible explicite | version de la branche | develop : pas de version pour la branche | develop : la version de la branche n'a pas de scan> · scan du <date>
>
> 📊 **Sonar** `<project>` / `<branch>` · analyse du <date>

A tool whose results are missing or outdated says it at the end of its line: « ⏳ en cours (job <name>) : relance /scans quand il est fini », « ⚠️ scan pas encore à jour (dernier upload <date>) : résultats anciens », « ❌ job en échec : résultats manquants ».

Severities, one scale for both tools (to classify, never printed):
| | Fortify | Sonar (sévérité ou impact) |
|---|---|---|
| 🔴 Critique | Critical | BLOCKER, CRITICAL |
| 🟠 Haute | High | MAJOR, HIGH |
| 🟡 Moyenne | Medium | MINOR, MEDIUM |
| 🔵 Basse | Low | INFO, LOW |
Kinds: 🛡️ vulnérabilité, 🔥 hotspot à revoir, 🐞 bug, 🧹 maintenabilité.

### 📋 Bilan
The counts of open findings, one row per tool that gave results:
| | 🔴 Critique | 🟠 Haute | 🟡 Moyenne | 🔵 Basse | 🔥 Hotspots |
|---|:-:|:-:|:-:|:-:|:-:|
| 🏰 Fortify | <n> | <n> | <n> | <n> | — |
| 📊 Sonar | <n> | <n> | <n> | <n> | <n> |
For each tool, the counts it gives for the whole version or branch, even when not every issue was read.

### 🎯 À corriger sur cette branche
The findings in the files of the "Files changed on the branch" list of the workflow state, in the order of step 5, at most 15 rows:
| | Problème | Commande |
|:-:|---|---|
| 🔴 | 🛡️ <rule or category, 5 words at most><br>`<file name>:<line>` | `/fortify-fix <id>` |
First column: the severity emoji alone. "Problème": the kind emoji and the rule, plus « (+ Sonar) » for a Fortify finding that Sonar reports too, then `<br>` and the place: the `<br>` puts the file under the rule, which leaves the "Commande" column room for a whole command on one line. The place is the file name without its folders, unless two files share it. "Commande": `/fortify-fix <id>` for Fortify, `/sonar-fix <issue key>` for Sonar: the command says the tool, and the id is nowhere else. More than 15: one line « … et <n> autres (<n> 🔴, <n> 🟠…) ».
Nothing open on the files of this branch: instead of the table, « ✅ Rien à corriger sur cette branche : la MR est prête côté qualité. »

### 📦 Ailleurs dans le dépôt
Only the 🔴 and 🟠 findings outside the files of this branch, same table with an "Id" column (`<id>` or `<issue key>`) instead of "Commande", at most 5 rows, then « … et <n> autres » if any. They are not to fix in this ticket.

### 🤔 Faux positifs probables
One line each: `<id>` <kind emoji> <rule> (`<file>:<line>`) — <the reason in one sentence, e.g. the value never comes from user input>.

Then, after the ticket sheet line below, the next step with the question tool (header "Suite"): the commands of the first rows of « À corriger sur cette branche » as options, their label being the command itself (`/fortify-fix <id>`, `/sonar-fix <issue key>`), the first one "(recommandé)", up to 3, the finding as description (severity emoji, rule, file:line), and "Rien pour l'instant". The pack plugin starts the command I choose by itself as soon as your turn ends: then answer only « Je lance <command>. ». Nothing to fix: no question.

## Ticket sheet
If the workflow state lists a current ticket sheet, record this run with one shell call (never the edit tool: the script dates the line and appends it to "## Suivi"); text between double quotes, without `"`, `$` or backticks:
`sh ~/.config/opencode/scripts/ticket-sheet.sh suivi "/scans - <short sha> - pipeline <success|failed|running> - <n> points à corriger sur la branche"`, the text followed, when there are points, by ` : ` and the commands of the first 5 rows of « À corriger sur cette branche », comma-separated (`/fortify-fix 123, /sonar-fix AX-1`), so that /next can offer them.
Write nothing else.
