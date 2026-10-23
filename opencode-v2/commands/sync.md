---
description: "Bring this branch up to date, without committing or pushing anything: the commits pushed on it from another computer (Rider on the Mac); with « develop », also the new commits of its base branch; with « merge <branch> », another branch. By merge, a conflict is aborted and listed. On develop: a fast-forward to origin. Usage: /sync [develop] [merge <branch>]"
agent: pilot
subtask: false
---
[[command sync $ARGUMENTS]]
Request: « $ARGUMENTS »

Workflow state (no fetch here: ship.sh fetches what it needs):
[[run workflow-state.sh --no-fetch]]

Bring the branch up to date now, in this single run, without asking anything. Nothing is committed and nothing is pushed: the uncommitted changes stay as they are.

1. Stop at once, with its line, when:
   - the HEAD is detached ("Current branch: (detached HEAD)", an OpenCode workspace starts so): « ⛔ HEAD détachée : il n'y a pas de branche à synchroniser. /push crée une branche pour ce travail et la pousse. »
   - "Merge in progress: yes": « ⛔ Une fusion est en cours : termine-la dans Rider (ou git merge --abort), puis relance /sync. »
2. In ONE shell call: `sh ~/.config/opencode/scripts/ship.sh --sync-only [--base] [--merge <branch>]`. `--base` when the request names develop, main, master or « la base » (it merges the "Base branch"), never on develop, master or main themselves; `--merge <branch>` when the request names another branch to merge (« merge <branch> », « intègre <branch> »). On develop, master or main, ship.sh brings them to origin by fast-forward only.
3. A "STOP:" line: stop with it. A conflict: « ⛔ Conflit avec <what was merged> dans <files> : fusion annulée, rien n'est perdu. Résous-la dans Rider (git merge <ref>), puis relance /sync. ». A merge that git refuses because of uncommitted changes on the same files: « ⛔ Tes modifications non commitées touchent les mêmes fichiers : /push d'abord, puis /sync. »

## Answer, in French
Header line « **/sync** — <branch> », then « ✅ À jour » with what came in (the REMOTE, BASE and MERGED lines of ship.sh, said simply: « 3 commits poussés depuis l'autre poste », « 5 nouveaux commits de develop fusionnés »), or the « ⛔ » line. When something came in that changes the code, the last line is « Rien n'est poussé : /push quand tu veux l'envoyer. »
