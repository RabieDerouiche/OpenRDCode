---
description: "Review a teammate's merge request, read-only and without touching your branch or your files: comments ready to paste in GitLab, with file:line and severity. Replaces OpenCode's built-in /review (made for GitHub). Usage: /review !<iid> | <merge request URL> | <source branch> [<target branch>, default develop]"
agent: checker
subtask: false
---
[[command review $ARGUMENTS]]
Merge request to review: "$1" (target branch given: "$2")

Project detection (this repository):
[[run detect-project-type.sh]]

Merge request, fetched without touching my working tree:
[[run review-target.sh '$1' '$2']]

Review this merge request of a teammate. It is someone else's code: write nothing anywhere (no file, no ticket sheet, nothing in GitLab or Jira). This answer format replaces your usual output format, and so does its scope: this is not a self-review.

Rules:
- If the output above says "No revision", give its message in French and stop.
- My working tree is MY branch, not the reviewed one. Read every file of this review at the reviewed revision, one `git show <revision>:<path>` call per file, and search it with `git grep -n <pattern> <revision> -- <paths>`. Never use the read, grep or glob tools for this review: they show my files.
- No build and no tests: the pipeline of the merge request runs them.
- In your first turn, send together: the reads of the changed files you need beyond the diff, the skills your checks need (`dotnet-cqrs-conventions` for a cqrs-api, `integrations-guardrails` if the diff touches SharePoint/CSOM, DocuSign, S3 or Piano Analytics, `blazorise` if it touches Blazorise components, `automapper` if it touches AutoMapper, Mapperly or Mapster (`mapster` too for Mapster), `fortify-remediation` for a security finding), and the Jira tickets of the "Jira keys" line (read-only: summary and acceptance criteria).
- The « Contracts » and « Tests it adds or changes » sections above are facts read from git: a REMOVED or CHANGED line of the public API, a route or a contract field that the ticket does not announce is a finding (« bloquant » for a library, « majeur » otherwise); a « blocking » line of the tests (no assertion, a focused test) is « bloquant », a « major » one « majeur ».
- Review only what the merge request changes, never older code it does not touch. Apply your checks for the project type, plus: does it do what the ticket asks (criteria not covered, behavior outside the ticket), and are the new behaviors tested?
- Be certain: a finding is a real problem in a realistic scenario, and you say which one. When you are not sure, write it as a question, never as a bug. Style only when it breaks AGENTS.md or the conventions of the surrounding code.

Answer, in French:
- First line: "**Review de <!iid or branch> - [<KEY>](<Jira link>) - <ticket summary>**" (without a Jira key: the summary of its first commit).
- One line: "Verdict : <bloquant | changements demandés | OK pour moi> - <n> commits", plus "- <target branch> a <n> commits non mergés dans la MR" when the "not merged into it" count is above 0.
- The comments ready to paste, most severe first, one per finding:
  `### <n>. <file>:<line> - <bloquant | majeur | mineur | question>`
  then the comment: 2 to 5 sentences, factual and courteous, in an impersonal style ("Ici, si … est null, …", "Proposition : …"), with a short code suggestion when it helps.
- If there is nothing to report: "Rien à signaler sur le diff", and a one-line comment to paste with the approval.
