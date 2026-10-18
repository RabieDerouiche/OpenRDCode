---
description: "Handle the review comments on the merge request of this branch: reads its open discussions (read-only), proposes for each one to fix, answer or argue, applies the fixes I choose with build and tests, writes the replies to paste in GitLab (nothing is posted), and offers to add the team's general rules to the repository AGENTS.md so that /check applies them from now on. Then /check and /ship. Usage: /mr"
agent: build
---
Workflow state (one fetch, then the state of the branch and its ticket sheet):
[[run workflow-state.sh --sheet]]
Project detection:
[[run detect-project-type.sh]]

Handle the review comments on my merge request. Read-only on GitLab and every other system: never post a reply, resolve a discussion, approve or change anything there; I paste the replies myself. Never commit or push: /ship does. The ticket sheet is printed above: do not read it again.

## Step 0 - Before starting
- On `develop`, `master` or `main`, or "Upstream: none" (the branch was never pushed): say "Pas de MR pour cette branche : /ship d'abord" and stop.
- If the "Branch vs its remote copy" line says "behind": say "Lance /sync d'abord : des commits poussés depuis un autre poste répondent peut-être déjà aux commentaires" and stop, unless I answer that I want to continue.

## Step 1 - Discussions
With the GitLab MCP tools (read-only): the project from the "Remote URL" line (its path after the host, without `.git`), the open merge request whose source branch is the current branch, then its unresolved discussions: author, text, file and line when the comment is on the diff, and the replies already in the thread.
- No open merge request: say "Pas de MR ouverte pour cette branche : le lien de création est dans la sortie de /ship" and stop.
- No unresolved discussion: say so with the merge request link, its approvals and its pipeline status, then stop.
- If the tools cannot return the discussions, say so in one line and stop.

## Step 2 - Analyze
In one turn, read the code of every discussion at its current version (the line may have moved: find it from the quoted code or the context of the comment). For each discussion, decide:
- "à corriger": a clear and right request;
- "déjà fait": the current code already does it (say where);
- "question": the reviewer asks something: prepare the answer from the code;
- "à discuter": the request contradicts AGENTS.md, an acceptance criterion or a "## Décisions" line of the ticket sheet, or the conventions of the existing code, or adds complexity without a current benefit: prepare a short, factual argument with its evidence (file:line, criterion, rule) and an alternative if there is one. Never apply such a request silently, never reject it silently: the decision is mine.
Also spot the comments that state a general rule of the team, beyond this code (for example "pas de service qui ne fait que relayer", "pas de booléen isV2 dans les services"): they are candidates for AGENTS.md.

## Step 3 - Ask
Show one table: # | auteur | fichier:ligne | demande (one line) | proposition. Then ask me with the question tool, one question per discussion and up to 4 questions per call (several calls in a row if needed), with the option that matches your analysis first and marked "(recommandé)":
- "Corriger comme demandé" / "Répondre sans changer le code" / "Argumenter (je rédige la réponse)" / "Passer" ("Répondre que c'est déjà fait" instead of "Corriger comme demandé" for "déjà fait");
- for each candidate rule, in the same calls: "Ajouter à AGENTS.md (partagé avec l'équipe, part avec cette MR) : « <the rule in one line, in English> »" (recommandé) / "Non".

## Step 4 - Apply
- In one turn: the fixes I chose (the smallest change for each, following AGENTS.md and the existing code, nothing else; a fix that changes behavior comes with its unit tests, added or updated in the existing style), and the rules I accepted, appended to the "## Repository-specific rules" section of the repository AGENTS.md (the section is created at the end if missing; no other line changes).
- Then, if code changed, the build and the full test suite in one call: `sh ~/.config/opencode/scripts/build-test.sh` (the solution or project of AGENTS.md "Build & test" as first argument if it names one; front-end: the commands of AGENTS.md). If the build or tests fail because of these fixes: fix them, at most 3 rounds.

## Step 5 - Replies to paste
For each discussion except "Passer", the reply in French, ready to paste under its thread in GitLab: 1 to 3 sentences, factual and courteous, no filler, no AI tone. "Corriger": what changed (it will be in the next push). "déjà fait": where. "question": the answer. "Argumenter": the reason with its evidence, and the alternative if there is one.

## Step 6 - Ticket sheet
After the build and tests, if the sheet exists, with the edit tool, in one turn (exact lines from the sheet printed above):
- in "## Décisions" (created before "## Suivi" if missing), each answer of mine that settles a design question: `- <topic> : <choice> (review de la MR !<iid>)`;
- at the end of "## Suivi": `- <date> /mr - !<iid> - <n> discussions : <x> corrigées, <y> réponses, <z> passées`, followed when the build ran by `- build <ok|ko> - tests <passed>/<total> - empreinte <the "Code fingerprint of this run" line of step 4, or ->` (date: the "Now" line of the workflow state).

## Answer, in French
First line: "**[<KEY>](<Jira link>) - <title>**", with the title from the "Ticket title line" of the workflow state (`# <KEY> - <title>`) and the link from its "Ticket Jira line"; without a ticket sheet, the branch name. Then the merge request link, the table of step 3 with the final status, the replies to paste (one block per discussion, under its file:line), the build and tests, and the rules added to AGENTS.md. Last line: when files changed, "Prochaine étape : /check puis /ship (le push met la MR à jour), puis colle les réponses dans GitLab."; otherwise "Prochaine étape : colle les réponses dans GitLab."
