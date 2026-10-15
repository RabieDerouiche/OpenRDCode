# Pack OpenCode — dev senior .NET

Agents, commandes et skills pour OpenCode + Qwen, adaptés à : .NET 10, Clean Architecture + CQRS, médiateur maison, FluentValidation, SharePoint/CSOM, DocuSign, S3, Piano Analytics, GitLab, Artifactory, Fortify SSC.

## Installation (5 min)

```bash
git clone <url-du-repo> opencode-pack
cd opencode-pack
./install.sh
```

Pour mettre à jour plus tard : `git pull && ./install.sh`.

Le script copie `agents/`, `commands/` et `skills/` dans `~/.config/opencode/`. Il sauvegarde les fichiers existants qui portent le même nom. Il ne touche **jamais** à `AGENTS.md` ni à `opencode.json` : ces deux fichiers sont à fusionner à la main.

1. **`AGENTS.global.md`** → copie son contenu dans `~/.config/opencode/AGENTS.md`. Remplace l'ancien bloc Fortify et l'ancien bloc NuGet s'ils y sont déjà.
2. **`opencode.snippet.json`** → fusionne-le dans `~/.config/opencode/opencode.json`. Garde ta config du provider Qwen.
3. **`AGENTS.repo-template.md`** → copie-le à la racine de chaque repo sous le nom `AGENTS.md`, et remplis les `[...]`. La section *Reference examples* est la plus importante.
4. Quitte complètement OpenCode, puis relance-le. Tape `/` : les commandes doivent apparaître. Tape `@` : les agents doivent apparaître.

## Commandes

| Commande | Agent | Modifie le code ? | Usage |
|---|---|---|---|
| `/commit-msg` | plan | non | Message de commit à partir du staged |
| `/mr-desc` | plan | non | Description de MR GitLab de la branche vs develop |
| `/review` | reviewer | non | Review du staged, ou du non-staged s'il n'y a rien de staged |
| `/review-branch` | reviewer | non | Review de toute la branche avant d'ouvrir la MR |
| `/cqrs command CreateInvoice Invoices` | build | oui | Command/query + handler + validator + tests |
| `/test-for src/.../InvoiceService.cs` | test-writer | tests uniquement | Tests unitaires pour une classe |
| `/test-branch` | test-writer | tests uniquement | Repère le code de la branche sans test et écrit les tests manquants |
| `/fortify` | fortify | non | Liste et trie les issues Fortify (branche courante, sinon develop) |
| `/fortify-fix 1234` | build | oui | Corrige UNE issue Fortify + test + build |
| `/build-fix` | build | oui | Corrige uniquement les erreurs de compilation |
| `/debug <stack trace / test / description>` | debugger | non | Cause racine avec preuves + fix proposé |
| `/plan-feature <description>` | architect | non | Plan d'implémentation étape par étape |
| `/explain <fichier / route / feature>` | plan | non | Explique un flux de bout en bout |

## Agents (invocables avec `@nom`)

| Agent | Droits |
|---|---|
| `reviewer` | Lecture + git diff/log/show |
| `architect` | Lecture + git log/diff + `dotnet list` (plans de features) |
| `debugger` | Lecture + `dotnet build/test` + git log/blame + grep |
| `test-writer` | Écrit uniquement dans les dossiers de tests + `dotnet build/test` |
| `fortify` | Lecture + outils MCP Fortify |

## Skills (chargés à la demande par les agents)

- `dotnet-cqrs-conventions` : couches, CQRS, médiateur maison, validators, tests, checklist.
- `fortify-remediation` : corrections .NET par catégorie Fortify, et quand c'est un faux positif.
- `integrations-guardrails` : pièges connus SharePoint/CSOM, DocuSign, S3, Piano Analytics.

## Ordre de mise en route conseillé

N'active pas tout le même jour. Si quelque chose se comporte mal, tu dois savoir quoi.

1. **Jour 1** : `AGENTS.md` du repo + `/review` + `/commit-msg`. Ce sont des commandes sans risque, en lecture seule.
2. **Jour 2** : `/fortify` + `/explain` + `/debug`.
3. **Jour 3** : `/test-for` sur une classe simple. Vérifie que `test-writer` n'écrit bien **que** dans les tests.
4. **Jour 4+** : `/cqrs`, `/fortify-fix`, `/build-fix`, en relisant chaque diff.

Chaque fois que Qwen répète la même erreur, ajoute une ligne dans la section *Repository-specific rules* du `AGENTS.md` du repo.

## Points à vérifier (non testés sur ton environnement)

- **`test-writer`** : les droits d'écriture reposent sur des motifs de chemin (`**/*Tests/**`, `tests/**`…). Si tes projets de tests ont un autre nommage, adapte la ligne `permission` de `agents/test-writer.md`. Teste-le une première fois sur une branche jetable.
- **Médiateur maison** : je ne connais pas les noms exacts de ses interfaces. Remplis la section *In-house mediator* du `AGENTS.md` du repo, sinon `/cqrs` devra les chercher.
- **Commandes qui comparent à `develop`** (`/mr-desc`, `/review-branch`, `/test-branch`) : elles lancent un `git fetch origin develop` silencieux. Si ta branche cible est différente, remplace `develop` dans ces fichiers.
- **Frontmatter YAML** : les permissions sont écrites sur une seule ligne (`{ ... }`) pour résister aux problèmes d'indentation au copier-coller.
