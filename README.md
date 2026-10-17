# Pack OpenCode — dev senior .NET

Agents, commandes et skills pour OpenCode (1.19, interface web) avec Qwen. Ils couvrent les API .NET 10 (CQRS ou non), le legacy .NET Framework, les librairies et le front, avec GitLab, Jira, Confluence, SonarQube, Fortify SSC et Artifactory.

## Installation et mise à jour

```bash
cd ~/opencode-pack && git pull && ./install.sh
opencode-web.sh stop && opencode-web.sh start
```

Le script copie `agents/`, `commands/`, `skills/` et `scripts/` dans `~/.config/opencode/`. Seuls les fichiers qui changent sont sauvegardés, dans `~/.config/opencode/backup-<date>/` (les 5 dernières sauvegardes sont gardées), et les commandes des anciennes versions du pack sont retirées. Le script ne touche **jamais** à `AGENTS.md` ni à `opencode.json` :
- `AGENTS.global.md` est à fusionner dans `~/.config/opencode/AGENTS.md`.
- `opencode.snippet.json` est à fusionner dans `~/.config/opencode/opencode.json`, en particulier les réglages de `build` et `plan` (`temperature` 0.6, `top_p` 0.95, recommandés pour Qwen 3.6).
- `AGENTS.repo-template.md` sert de modèle pour le `AGENTS.md` à la racine de chaque repo (facultatif).

## La journée type

| Moment | Commande | Ce qu'elle fait |
|---|---|---|
| Matin | `/daily [DNA]` | Ton sprint d'abord, tes MR et les reviews qui t'attendent, avec des liens, des signaux et un plan du jour. Termine par « Sur quoi tu bosses ? ». |
| Début de ticket | `/ticket [DNA-123]` | Choix du ticket (dans ton sprint si tu ne donnes pas de clé), branche depuis develop (ou main/master s'il n'y a pas de develop), analyse du ticket, de Confluence et du code, puis **fiche ticket** enregistrée. |
| Dev | `/dev [N] [directives]` | Implémente l'étape suivante du plan (ou l'étape N) selon tes directives (« comme dans ~/dev/x », « avec un Result », « sans nouvelle lib »), pose un QCM dès qu'un choix d'approche n'est pas tranché, compile, écrit et lance les tests de l'étape, coche l'étape, note tes choix dans la fiche, puis propose l'étape suivante. Tu peux aussi parler librement à `build` (« pourquoi ça plante », « explique ce flux », « corrige le build ») ou coder dans Rider. |
| Tests | `/test [fichier] [comme <repo ou pattern>]` | Critères d'acceptation et code modifié → tests manquants écrits dans le style du projet (ou d'une référence) et lancés jusqu'au vert. La fiche est mise à jour. |
| Avant de pousser | `/check` | Review, build, tests, critères d'acceptation, pré-scan sécurité, au plus 5 suggestions de bonnes pratiques non bloquantes, et alerte si `AGENTS.md` n'est plus à jour. En local et en lecture seule. |
| Livrer | `/ship` | Commit, récupération des changements distants, push (avec ta validation), lien et description de la MR. |
| Après la CI | `/scans` | Pipeline du commit poussé, puis Sonar et Fortify fusionnés et priorisés, avec la commande de correction de chaque point. |
| Corriger | `/fortify-fix <id>` · `/sonar-fix <clé>` | Corrige UN point, avec test, build et message de commit. Puis `/check` → `/ship` → `/scans`. |
| Perdu ? | `/next` | Lit l'état (y compris ce que tu as modifié hors d'OpenCode ou poussé depuis ton Mac), la fiche, le pipeline et la MR, puis te propose la suite en QCM. Il exécute directement les actions git et fiche (synchroniser, livrer, terminer un merge, cocher une étape faite à la main) ; pour le reste il te donne la commande à taper. Il signale aussi quand `AGENTS.md` est à mettre à jour. |

**La fiche ticket** est le fichier `.git/opencode/tickets/<CLÉ>.md` du repo. Comme elle est dans `.git`, elle n'est jamais commitée. Elle contient les critères d'acceptation, les tests attendus, le plan et un historique (`## Suivi`). `/dev`, `/test`, `/check`, `/ship`, `/scans` et `/next` la lisent et y notent leur passage, ce qui leur évite de tout redemander. La section `## Décisions` garde tes choix (Result, feature flag, librairie…) pour qu'ils ne te soient pas reposés.

## Commandes ponctuelles

| Commande | Usage |
|---|---|
| `/audit [domaine]` | Audit des bonnes pratiques de tout le repo selon son type (health checks, gestion d'erreurs, config, résilience, logs, sécurité, tests), avec preuves et la plus petite façon d'ajouter ce qui manque. |
| `/sync` | Met la branche à jour : commit local, changements distants de la branche, merge de develop (jamais de rebase), puis push si tu veux. |
| `/release-notes` | Release note d'une MEP depuis master. Avec un nom de groupe (`/release-notes DNA`), une seule note pour plusieurs repos, regroupée par ticket. |
| `/cqrs command CreateInvoice Invoices` | Command ou query, handler, validator et tests (projets CQRS uniquement). |
| `/extract-pattern <nom> <repo>` · `/apply-pattern <nom>` | Réutilise une bonne implémentation d'un repo dans un autre. |
| `/agents-md [page Confluence]` | Crée ou met à jour le `AGENTS.md` du repo à partir du code (structure, build et test, conventions, gestion des erreurs, handlers, tests, exemples de référence, packages internes) et de Confluence si tu donnes une page. Une fois par repo, puis après un gros changement d'architecture ou d'organisation. |

## Agents

| Agent | Peut écrire | Rôle |
|---|---|---|
| `git` | la fiche ticket ; git avec validation pour push, merge, pull, stash | `/ticket`, `/ship`, `/sync`, `/next`. Jamais de force-push, rien sur develop, master ou main. Masqué du sélecteur d'agents : on passe par les commandes. |
| `reviewer` | la fiche ticket (ligne de suivi) | `/check`, review dans `/ship`. Lance le build et les tests. |
| `test-writer` | les dossiers de tests et la fiche ticket | `/test`. Ne touche jamais au code de production. |
| `analyst` | la fiche ticket (ligne de suivi de `/scans`) | `/daily`, `/scans`, analyse de `/ticket`. Lecture seule sur Jira, Confluence, GitLab, Sonar et Fortify. |
| `debugger` · `architect` | rien | Appelés par l'agent `build` quand tu demandes « pourquoi ça plante » ou « fais-moi un plan ». `architect` fait aussi `/audit`. |
| `release-writer` | une page Confluence, avec ta validation | `/release-notes`. |

## Skills (chargés à la demande)

`dotnet-cqrs-conventions`, `fortify-remediation`, `integrations-guardrails`, `build-fix`, `explain-code`, `best-practices`, `ship-procedure` et `sync-procedure` (la logique de `/ship` et `/sync`, partagée avec `/next`), et les `pattern-*` créés par `/extract-pattern`.

## Scripts (copiés dans `~/.config/opencode/scripts/`)

- `workflow-state.sh` : l'état complet de la branche en une seule passe, après un seul `git fetch` (branche, ticket et fiche, résumé des autres fiches, base, copie distante, fichiers modifiés, diffs avec `--diff`, remplacés par la liste des fichiers au-delà de 1500 lignes). OpenCode lance les commandes injectées en parallèle : tout regrouper ici évite des références distantes périmées et accélère `/next`, `/dev`, `/test`, `/check`, `/ship`, `/sync`, `/ticket` et `/scans`.
- `detect-project-type.sh` : type de projet, commandes de build et de test, stack de test.
- `release-commits.sh` : commits, MR et tickets d'une plage de MEP pour `/release-notes`.

Chaque réponse du flux commence par le ticket en cours : **[DNA-123](lien Jira) - titre**.

## Réglages liés à OpenCode 1.19 et Qwen 3.6

- Les commandes dont l'agent est un sous-agent (`/daily`, `/scans`, `/check`, `/test`, `/audit`, `/release-notes`) tournent directement dans ta session (`subtask: false`) : sinon OpenCode ajoute un tour où l'agent `build` résume la réponse, ce qui coûte du temps et abîme les tableaux.
- Build et tests silencieux : `dotnet build -nologo -v q -clp:ErrorsOnly` (erreurs et résumé seulement), puis `dotnet test --no-build`.
- Chaque agent ne voit que les MCP dont il a besoin. Seuls `build` (`test-writer` dans `/dev`, `debugger`, `architect`) et `git` (`analyst` dans `/ticket`, `reviewer` dans `/ship`) délèguent à d'autres agents, sur un seul niveau comme l'impose OpenCode.

## Pour la maintenance du pack

- `tools/permissions.py` régénère les lignes `permission:` des agents. Ne les modifie pas à la main.
- Avant chaque push, tous les fichiers sont validés avec `gray-matter`, le parseur YAML d'OpenCode : il refuse par exemple les clés en double.
