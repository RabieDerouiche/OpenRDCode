# Pack OpenCode — dev senior .NET

Agents, commandes et skills pour OpenCode (1.19, interface web) avec Qwen. Ils couvrent les API .NET 10 (CQRS ou non, ABP), Blazor, le legacy .NET Framework, les librairies et le front, avec GitLab, Jira, Confluence, SonarQube, Fortify SSC et Artifactory.

## Installation et mise à jour

```bash
cd ~/opencode-pack && git pull && ./install.sh
opencode-web.sh stop && opencode-web.sh start
```

Le script copie `agents/`, `commands/`, `skills/` et `scripts/` dans `~/.config/opencode/`. Seuls les fichiers qui changent sont sauvegardés, dans `~/.config/opencode/backup-<date>/` (les 5 dernières sauvegardes sont gardées), et les commandes des anciennes versions du pack sont retirées. Le script ne touche **jamais** à `AGENTS.md` ni à `opencode.json` :
- `AGENTS.global.md` est à fusionner dans `~/.config/opencode/AGENTS.md`.
- `opencode.snippet.json` est à fusionner dans `~/.config/opencode/opencode.json` : réglages de `build` et `plan` (`temperature` 0.6, `top_p` 0.95), et règles de `permission` pour tous les agents (outils MCP d'écriture masqués, secrets, git destructif).
- Le modèle lui-même se règle dans la section `provider` de `opencode.json` : voir « Réglages du modèle » plus bas, sinon la température n'est pas envoyée.
- `AGENTS.repo-template.md` sert de modèle pour le `AGENTS.md` à la racine de chaque repo (facultatif).

## La journée type

| Moment | Commande | Ce qu'elle fait |
|---|---|---|
| Matin | `/daily [ABC]` | Ton sprint d'abord, tes MR et les reviews qui t'attendent, avec des liens, des signaux et un plan du jour. Termine par « Sur quoi tu bosses ? ». |
| Début de ticket | `/ticket [ABC-123]` | Choix du ticket (dans ton sprint si tu ne donnes pas de clé), branche depuis develop (ou main/master s'il n'y a pas de develop), analyse du ticket, de Confluence et du code, puis **fiche ticket** enregistrée. |
| Dev | `/dev [N] [directives]` | Implémente l'étape suivante du plan (ou l'étape N) selon tes directives (« comme dans ~/dev/x », « avec un Result », « sans nouvelle lib »), pose un QCM dès qu'un choix d'approche n'est pas tranché, compile, écrit et lance les tests de l'étape, coche l'étape, note tes choix dans la fiche, puis propose l'étape suivante. Tu peux aussi parler librement à `build` (« pourquoi ça plante », « explique ce flux », « corrige le build ») ou coder dans Rider. |
| Tests | `/test [fichier] [comme <repo ou pattern>]` | Critères d'acceptation et code modifié → tests manquants écrits dans le style du projet (ou d'une référence) et lancés jusqu'au vert. La fiche est mise à jour. |
| Avant de pousser | `/check` | Review, build et tests, critères d'acceptation, pré-scan sécurité, au plus 5 suggestions de bonnes pratiques non bloquantes, et alerte si `AGENTS.md` n'est plus à jour. Si la branche touche un fichier projet (`.csproj`, `.props`…), un QCM te propose de vérifier les licences des packages modifiés. Build et tests ne sont pas relancés si `/test` (ou un correctif) vient de les passer sur exactement le même code. En local et en lecture seule. |
| Livrer | `/ship` | Commit, récupération des changements distants, push (avec ta validation), lien et description de la MR. La review est sautée seulement si `/check` a validé exactement ce code (empreinte du code, pas un simple nombre de lignes). |
| Après la CI | `/scans` | Pipeline du commit poussé, puis Sonar et Fortify fusionnés et priorisés, avec la commande de correction de chaque point. |
| Corriger | `/fortify-fix <id>` · `/sonar-fix <clé>` | Corrige UN point, avec test, build et message de commit. Puis `/check` → `/ship` → `/scans`. |
| Retours de review | `/mr` | Lit les discussions ouvertes de ta MR, te propose pour chacune corriger / répondre / argumenter (QCM), applique tes choix avec build et tests, rédige les réponses à coller dans GitLab (rien n'est posté) et te propose d'ajouter les règles générales de l'équipe à l'`AGENTS.md` du repo, pour que `/check` les applique ensuite. Puis `/check` → `/ship`. |
| Perdu ? | `/next` | Lit l'état (y compris ce que tu as modifié hors d'OpenCode ou poussé depuis ton Mac), la fiche, le pipeline et la MR, puis te propose la suite en QCM. Il exécute directement les actions git et fiche (synchroniser, livrer, terminer un merge, cocher une étape faite à la main) ; pour le reste il te donne la commande à taper. Il signale aussi quand `AGENTS.md` est à mettre à jour. |

**La fiche ticket** est le fichier `.git/opencode/tickets/<CLÉ>.md` du repo. Comme elle est dans `.git`, elle n'est jamais commitée. Elle contient les critères d'acceptation, les tests attendus, le plan et un historique (`## Suivi`). `/dev`, `/test`, `/check`, `/ship`, `/mr`, `/scans` et `/next` la reçoivent avec l'état de la branche (sans la relire) et y notent leur passage, ce qui leur évite de tout redemander. La section `## Décisions` garde tes choix (Result, feature flag, librairie…) pour qu'ils ne te soient pas reposés.

## Commandes ponctuelles

| Commande | Usage |
|---|---|
| `/audit [domaine]` | Audit des bonnes pratiques de tout le repo selon son type (health checks, gestion d'erreurs, config, résilience, logs, sécurité, tests), avec preuves et la plus petite façon d'ajouter ce qui manque. |
| `/licences` · `/licences branche` · `/licences <package> [version]` | À la demande : les packages NuGet devenus payants ou copyleft à partir d'une version (tout le repo avec les dépendances transitives, ce que la branche change, ou un package avant de l'ajouter), avec l'option gratuite. Un script, une réponse, aucun autre appel. |
| `/review !42` · `/review <branche> [cible]` | Review de la MR d'un collègue, en lecture seule et sans toucher à ta branche ni à tes fichiers (la MR est récupérée par sa référence GitLab) : commentaires prêts à coller, avec fichier:ligne et gravité. Remplace le `/review` intégré d'OpenCode, fait pour GitHub. `/daily` donne la commande de chaque review qui t'attend. |
| `/sync` | Met la branche à jour : commit local, changements distants de la branche, merge de develop (jamais de rebase), puis push si tu veux. |
| `/release-notes` | Release note d'une MEP depuis master. Avec un nom de groupe (`/release-notes MONAPP`), une seule note pour plusieurs repos, regroupée par ticket. |
| `/cqrs command CreateInvoice Invoices` | Command ou query, handler, validator et tests (projets CQRS uniquement). |
| `/extract-pattern <nom> <repo>` · `/apply-pattern <nom>` | Réutilise une bonne implémentation d'un repo dans un autre. |
| `/agents-md [page Confluence]` | Crée ou met à jour le `AGENTS.md` du repo à partir du code (structure, build et test, conventions, gestion des erreurs, handlers, tests, exemples de référence, packages internes) et de Confluence si tu donnes une page. Une fois par repo, puis après un gros changement d'architecture ou d'organisation. |

## Agents

| Agent | Peut écrire | Rôle |
|---|---|---|
| `git` | la fiche ticket ; git avec validation pour push, merge, pull, stash | `/ticket`, `/ship`, `/sync`, `/next`. Jamais de force-push, rien sur develop, master ou main. Masqué du sélecteur d'agents : on passe par les commandes. |
| `dev` | le code, comme `build` | `/dev`, `/cqrs`, `/apply-pattern`, `/extract-pattern` : l'agent `build` sans aucun outil MCP, pour que chaque requête reste légère. Masqué du sélecteur ; `build` garde tout pour la discussion libre, `/fortify-fix`, `/sonar-fix`, `/mr` et `/agents-md`. |
| `reviewer` | la fiche ticket (ligne de suivi) | `/check`, review dans `/ship`, `/review` (là, il n'écrit rien). Lance le build et les tests. |
| `test-writer` | les dossiers de tests et la fiche ticket | `/test`. Ne touche jamais au code de production. |
| `analyst` | la fiche ticket (écrite dans `/ticket`, ligne de suivi de `/scans`) | `/daily`, `/scans`, analyse de `/ticket`. Lecture seule sur Jira, Confluence, GitLab, Sonar et Fortify. |
| `debugger` · `architect` | rien | Appelés par l'agent `build` quand tu demandes « pourquoi ça plante » ou « fais-moi un plan ». `architect` fait aussi `/audit` et `/licences`. |
| `release-writer` | une page Confluence, avec ta validation | `/release-notes`. |

## Skills (chargés à la demande)

`dotnet-cqrs-conventions`, `fortify-remediation`, `integrations-guardrails`, `build-fix`, `explain-code`, `best-practices`, `ship-procedure` et `sync-procedure` (la logique de `/ship` et `/sync`, partagée avec `/next`), et les `pattern-*` créés par `/extract-pattern`.

## Plugin (copié dans `~/.config/opencode/plugins/`)

- `compact-commands.js` : quand tu lances une commande, la conversation affiche seulement `/next` (ou `/dev 2 …`) au lieu du gros bloc injecté (état de la branche, fiche, diffs). Le bloc part toujours au modèle, en partie « synthétique » que l'interface web n'affiche pas. Pour revoir le bloc, retire le fichier et redémarre. Ne mets jamais d'autre fichier `.js` ou `.ts` dans `plugins/` ou `tools/` : OpenCode les exécute tous.

## Scripts (copiés dans `~/.config/opencode/scripts/`)

- `workflow-state.sh` : l'état complet de la branche en une seule passe (date et heure, branche, ticket, base, copie distante, conflits, fichiers modifiés, résumé des fiches ; contenu de la fiche avec `--sheet`, lien Jira et résumé des autres tickets avec `--tickets`, diffs avec `--diff`, remplacés par la liste des fichiers au-delà de 1500 lignes). Il ne récupère que develop et la branche courante (`--fetch-all` pour `/ticket`, qui cherche les branches existantes d'un ticket), et force les messages de git en anglais. OpenCode lance les commandes injectées en parallèle : tout regrouper ici évite des références distantes périmées et des allers-retours avec le modèle.
- `build-test.sh [solution ou projet] [options de dotnet test]` : build silencieux puis tests seulement si le build passe, en un seul appel, avec des lignes `BUILD:` et `TESTS:` explicites (OpenCode ne montre pas le code retour d'une commande au modèle). Après un passage sur toute la solution, il donne l'empreinte du code testé : `/test` et les correctifs la notent dans la fiche, et `/check` ne relance pas build et tests tant que le code garde cette empreinte.
- `state-fingerprint.sh` : l'empreinte du code de la copie de travail (fichiers suivis avec leur contenu actuel, et fichiers non suivis non ignorés), sans rien écrire. Même code, même empreinte, qu'il soit commité ou non ; la moindre modification la change. C'est ce qui permet à `/ship` de sauter la review et à `/next` de proposer de livrer sans risque.
- `review-target.sh` : pour `/review`, récupère la MR d'un collègue (référence GitLab `refs/merge-requests/<n>/head`) ou sa branche sans toucher à ta copie de travail, puis donne ses commits, ses tickets et son diff.
- `package-licenses.sh` : lancé seulement à la demande (`/licences`, le QCM de `/check`, ou « vérifie les licences »). Les packages NuGet devenus payants ou copyleft à partir d'une version (MediatR 13+, AutoMapper 15+, FluentAssertions 8+, MassTransit 9+, NPOI 2.8+, EPPlus 5+, QuestPDF, ImageSharp 3+, Blazorise, Duende IdentityServer, iText, Polly à sa prochaine version majeure). Trois modes : tout le repo, références directes puis transitives d'après `obj/project.assets.json` ; `branche` pour ce que la branche ajoute ou change ; `<package> [version]` pour un package. Il lit les `.csproj`, `Directory.Packages.props` (versions centralisées, `VersionOverride`), les propriétés `$(...)` et `packages.config`. Les règles, datées, sont en tête du script : à mettre à jour quand un package connu change de licence. NuGet seulement (pas npm). En dehors de ça, les agents connaissent la liste par `AGENTS.md` et le disent dans le QCM s'ils proposent une version payante, sans aucun appel.
- `detect-project-type.sh` : type de projet (dont Blazor, avec la part de composants en code-behind, et ABP signalé), commandes de build et de test, stack de test (dont bUnit).
- `release-commits.sh` : commits, MR et tickets d'une plage de MEP pour `/release-notes`.

Chaque réponse du flux commence par le ticket en cours : **[ABC-123](lien Jira) - titre**.

## Réglages du modèle (section `provider` de `opencode.json`)

OpenCode 1.19 n'envoie la température d'un agent que si le modèle déclare `"temperature": true`. Pour un modèle déclaré à la main dans `provider` (cas d'un serveur interne), la valeur par défaut est `false` : sans cette ligne, le `temperature: 0.6` des agents est ignoré et le serveur applique la sienne. `top_p` est toujours envoyé ; `top_k` jamais, sauf dans les `options` du modèle, qui sont ajoutées telles quelles à chaque requête et l'emportent sur les valeurs des agents.

```json
"provider": {
  "<ton provider>": {
    "models": {
      "<ton modèle Qwen>": {
        "temperature": true,
        "limit": { "context": 131072, "output": 32768 },
        "options": { "top_k": 20, "chat_template_kwargs": { "preserve_thinking": true } }
      }
    }
  }
}
```
- `temperature: true` : à ajouter dans tous les cas.
- `limit` : `context` = la taille de contexte réelle du serveur (à demander, ou `max_model_len` dans la réponse de `/v1/models` pour vLLM), au plus 131072 pour garder des tours rapides ; `output` = 32768, ou le quart de `context` s'il est plus petit que 128K. OpenCode compacte la session quand elle dépasse `context - output` ; sans `limit`, il ne la compacte jamais et elle peut finir en erreur de contexte.
- `options` (à tester une commande, puis à retirer si le serveur répond par une erreur) : `top_k` 20 est la valeur recommandée par Qwen ; `preserve_thinking` garde le raisonnement des tours précédents, ce que Qwen recommande pour les agents (moins de raisonnement répété, meilleur cache du serveur).
- Côté serveur (pour l'équipe qui l'héberge, pas dans `opencode.json`) : Qwen 3.6 27B sait générer plusieurs tokens à la fois (MTP), mais vLLM ne l'active pas par défaut. Avec vLLM 0.17 ou plus : `--speculative-config '{"method": "mtp", "num_speculative_tokens": 1}'` (la recette vLLM du modèle mesure environ ×2,4 en génération sur de vraies requêtes d'agent de code), sans changement de qualité : la sortie suit la même distribution. Le prefix caching est actif par défaut sur les versions récentes.
- Si le serveur tourne sans le mode thinking (aucun bloc de réflexion dans l'interface), les réglages recommandés par Qwen sont `temperature` 0.7, `top_p` 0.8, `top_k` 20 et `presence_penalty` 1.5 : mets-les dans les `options` du modèle, elles s'appliquent alors à tous les agents.
- Titre des sessions : OpenCode le fait écrire par le même modèle, en parallèle de ta première commande, et Qwen réfléchit avant d'écrire ce titre, ce qui occupe le serveur pour rien. À tester de la même façon (si le serveur refuse, la session garde juste son titre par défaut) : dans la section `agent` de `opencode.json`, `"title": { "options": { "chat_template_kwargs": { "enable_thinking": false } } }`. Si la plateforme propose un modèle plus petit, `"small_model": "<provider>/<modèle>"` fait encore mieux.

## Réglages liés à OpenCode 1.19 et Qwen 3.6

- Les commandes dont l'agent est un sous-agent (`/daily`, `/scans`, `/check`, `/test`, `/review`, `/audit`, `/licences`, `/release-notes`) tournent directement dans ta session (`subtask: false`) : sinon OpenCode ajoute un tour où l'agent `build` résume la réponse, ce qui coûte du temps et abîme les tableaux.
- Ce qui coûte le plus avec un modèle qui réfléchit avant chaque action, c'est le nombre d'allers-retours, bien plus que la taille du prompt, que le serveur garde en général en cache. D'où :
  - tout ce qu'un script peut donner est injecté avant le premier tour : état de la branche, fiche ticket, autres tickets, date ;
  - build et tests en un appel (`build-test.sh`) ;
  - appels indépendants envoyés ensemble (lectures, recherches, requêtes MCP, skills : `/check`, `/scans`, `/daily` et les commandes de correction le disent étape par étape) ;
  - commandes git enchaînées avec `&&` quand elles doivent se suivre, sauf celles qui demandent ta validation ;
  - questions regroupées dans un seul QCM ;
  - `AGENTS.md` jamais relu (OpenCode l'injecte déjà) ;
  - dans `/ticket`, l'analyste écrit lui-même la fiche au lieu de la faire recopier par l'agent `git` ;
  - build et tests ne tournent pas deux fois sur le même code (empreinte notée dans la fiche) ;
  - la vérification des licences n'est jamais automatique.
- Chaque agent ne voit que les MCP dont il a besoin (aucun pour `dev`, qui fait `/dev`), et les outils MCP d'écriture sont masqués pour tous les agents (snippet) : moins de descriptions d'outils envoyées à chaque requête, et moins d'outils parmi lesquels le modèle doit choisir. Seuls `build` et `dev` (`test-writer`, `debugger`, `architect`) et `git` (`analyst` dans `/ticket`, `reviewer` dans `/ship`) délèguent à d'autres agents, sur un seul niveau comme l'impose OpenCode.
- Le mode thinking reste actif : le couper serait le gain de vitesse le plus fort, mais au prix de la qualité.

## Pour la maintenance du pack

- `tools/permissions.py` régénère les lignes `permission:` des agents et `opencode.snippet.json`. Ne les modifie pas à la main.
- Avant chaque push, tous les fichiers sont validés avec `gray-matter`, le parseur YAML d'OpenCode : il refuse par exemple les clés en double.
- Les scripts sont vérifiés avec `shellcheck` et testés avec dash, bash et busybox sh, et avec les awk mawk, gawk, BWK (celui de macOS) et busybox.
