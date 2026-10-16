---
description: "Where am I and what do I do next? Reads the branch, the working tree, the ticket sheet, the pipeline and the merge request, then gives the next command to run (read-only). Usage: /next"
agent: analyst
---
Current branch: !`git branch --show-current`
Working tree: !`git status --porcelain`
Merge in progress: !`git rev-parse -q --verify MERGE_HEAD`
Fetch: !`git fetch -q origin`
Branch vs its remote copy: !`git status -sb`
Commits behind / ahead of develop: !`git rev-list --left-right --count origin/develop...HEAD`
HEAD: !`git rev-parse --short HEAD`
Uncommitted changes summary: !`git diff HEAD --shortstat`
Last commit: !`git log -1 --format=%cr`
Existing ticket sheets: !`ls .git/opencode/tickets`

Tell me where I am in my workflow and the ONE next step. Read-only. Be fast: no review, no build, no full scan.

Read the ticket sheet `.git/opencode/tickets/<KEY>.md` if the Jira key of the branch name (pattern `[A-Z][A-Z0-9]+-[0-9]+`) has one in the list above: its "Plan" checklist and its "## Suivi" lines (/test, /check, /ship) are the history of the work. If the branch was pushed, read with the GitLab MCP tools the latest pipeline of the branch (status, commit SHA) and its open merge request (unresolved discussions, approvals, conflicts).

The workflow is: /daily → /ticket → code with the build agent → /test → /check → /ship → /scans → fixes (/fortify-fix, /sonar-fix) → back to /check. /sync brings develop into the branch.

Decide with the FIRST matching rule:
1. On `develop`, `master` or `main`: "/daily, puis /ticket <KEY>". If there are uncommitted changes, warn that they must not be committed on this branch.
2. A merge is in progress (MERGE_HEAD above is a hash) or the working tree has conflicts (`UU`, `AA`, `DU`, `UD` lines): "Résous les conflits dans Rider, puis préviens l'agent git (« conflits résolus, termine le merge »)".
3. The branch has a Jira key but no ticket sheet: "/ticket <KEY>" (it keeps the branch and creates the sheet).
4. Uncommitted changes exist:
   - no `/test` line in "Suivi" after the last code change, or rows of "Tests attendus" still "à écrire" or "❌": "/test";
   - no `/check` line with the current HEAD and the current uncommitted changes summary, or its verdict is BLOCKING: "/check";
   - otherwise: "/ship".
5. No uncommitted changes but local commits not pushed ("ahead" in the branch status): "/ship".
6. Pushed: pipeline of the pushed commit running → "Attends la fin du pipeline (<link>), puis /scans"; failed → "/scans (il te dira quel job a échoué)"; success and no `/scans` asked since the last /ship → "/scans".
7. Merge request with unresolved discussions: "Réponds aux discussions de la MR <link>". Approved, pipeline green, no discussion left: "MR prête à merger <link>".
8. Plan steps still unchecked: "Continue l'étape <n> : <text> (avec l'agent build)".
9. Otherwise: "Rien en attente sur cette branche : /daily pour la suite".
In addition, if develop has 10 commits or more that are not in the branch, add: "develop a avancé de <n> commits : /sync quand tu peux".

## Answer, in French, at most 8 lines
- "Où tu en es" : branch, ticket (link if known), plan progress (<checked>/<total>), tests, last /check, push, pipeline, MR — one short line each, only the ones that exist.
- "Prochaine étape" : the command or action, in bold.
- "Ensuite" : the step after, in one line.
