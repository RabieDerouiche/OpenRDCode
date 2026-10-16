---
description: "Write a GitLab merge request description for the current branch against develop"
agent: plan
---
Remote base branches: !`git branch -r --list origin/develop origin/main origin/master`

Base branch: `origin/develop` if it is listed above. Otherwise, if exactly one of `origin/main` / `origin/master` is listed, use it; if none or several, ask me with the question tool (multiple choice, recommended option first) with the listed branches as options. If the git output injected below failed because `origin/develop` does not exist, run the same git commands yourself with the chosen base, one command per call.

Current branch: !`git branch --show-current`

Commits since develop:
!`git fetch -q origin develop >/dev/null 2>&1; git log --oneline origin/develop..HEAD`

Changed files:
!`git diff --stat origin/develop...HEAD`

Full diff:
!`git diff origin/develop...HEAD`

Write a GitLab merge request description in French with exactly these sections:

## Contexte
Why this change exists, deduced from commits and code. If the reason is not visible in the diff, write "À compléter".

## Changements
Bullet list grouped by project, layer or folder, following the structure of this repository.

## Impacts
- Breaking changes for API consumers (routes, contracts, status codes), or "Aucun".
- Configuration or environment variables to add, or "Aucun".
- Database or external integration changes (SharePoint, DocuSign, S3, Piano), or "Aucun".

## Points d'attention pour la review
The 1 to 3 places where a reviewer should look carefully, with file paths.

## Comment tester
Concrete steps (endpoint + payload, or test names).

Rules: only describe what is in the diff. Do not invent ticket numbers, features or tests. Output the description in a markdown code block.
