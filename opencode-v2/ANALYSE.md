# Passer le pack à OpenCode v2

Analyse du 21 octobre 2026, faite sur OpenCode v2.1.2 (paquet npm `@opencode/cli`, sorti le 21 octobre) : lecture de son code source, puis la configuration actuelle du pack (v2 du pack, faite pour OpenCode 1.19) chargée par le vrai binaire v2 (`opencode debug config`, `opencode debug agents`, `opencode serve`). Chaque point dit d'où vient l'information : **constaté** (vu en faisant tourner v2), **code** (lu dans son source, pas encore vu tourner), **à vérifier**.

> **Document d'origine, gardé pour l'historique.** La migration faite depuis, et vérifiée, est dans `MIGRATION.md`. Points tranchés depuis cette analyse : les espaces de travail de l'interface v2 existent et marchent avec le pack (vérifié à l'écran : « Local » → « Nouvel espace de travail ») ; la v2 tourne à côté de la 1.19 avec `OPENCODE_CONFIG_DIR` et ses propres dossiers XDG dans `~/oc2`, sans toucher à ceux de la 1.19 (vérifié par leurs empreintes) ; `experimental.primary_tools` et `compaction.prune` sont ignorés par la v2, et le plugin refuse lui-même les questions des sous-agents ; la v2 démarrée avec `serve` laisse son mot de passe dans l'environnement des commandes, et le plugin le leur retire.

> **Mise à jour du 22 octobre 2026.** Les fonctions 3, 4, 5, 10 et 12 du tableau « Le plugin, fonction par fonction » sont portées et vérifiées avec le vrai v2.1.2 (ligne courte, QCM, avancement, issue, dossier de l'espace de travail dans les titres), ainsi que `compaction.prune`, la règle `doom_loop` et l'attente des serveurs MCP au démarrage, que la v2 n'applique plus. Ce que la v2 ouvre est fermé : le code mode (`execute`, du JavaScript qui appelait n'importe quelle adresse et passait sous les règles, vérifié), la recherche web, les outils `opencode_*` de déplacement de session et de worktree, le skill `report`, le partage et les mises à jour automatiques. Avec la v2, c'est l'interface qui crée les espaces de travail ; `workspace.sh` reste identique à celui de la 1.19 (le dossier des scripts est partagé par les deux versions), et ses actions `list` et `remove` marchent aussi pour les dossiers créés par la v2. Détail : `MIGRATION.md`, étape 14.

> **OpenCode v2.1.3 (publiée le 22 octobre 2026).** 50 changements depuis la 2.1.2 ; aucun ne touche ce dont le pack dépend (API des plugins, crochets, évènements, permissions des agents) : le pack est vérifié avec la 2.1.3 comme avec la 2.1.2, tous les contrôles de bout en bout rejoués. Ce qui peut se voir : un résumé de contexte a maintenant la même limite de sortie qu'un tour normal (un long résumé n'est plus coupé) ; une `baseURL` déclarée dans un provider l'emporte sur l'adresse du catalogue de modèles (utile pour un vLLM déclaré sous le nom d'un provider connu) ; les anciennes permissions `apply_patch` sont lues comme `edit` ; l'interface colore le code avec une autre bibliothèque. Sans effet ici : le port du service sous Windows, un service hébergé d'OpenCode, la facturation.

> **Analyse du 26 octobre 2026 : la vitesse et les blocages (code de la v2.1.3 et de la v2.1.4).** Lu dans le code source, chaque point corrigé par le plugin ou documenté :
> - **Un appel MCP peut attendre 12 heures** (`packages/core/src/mcp/client.ts` : `DEFAULT_EXECUTION_TIMEOUT = 12 * 60 * 60 * 1_000` ; la v2.1.4 donne 10 minutes aux seuls serveurs « attachés » par un client). Un serveur Jira, GitLab ou Fortify qui ne répondait plus figeait le run. Le plugin borne chaque serveur sans `timeout.execution` à 5 minutes (point 27).
> - **Les options des agents ne partent pas.** La configuration d'un agent (sa température, son top_p, ses `options`) devient le `request.body` de l'agent (`v1/config/migrate.ts`, `config/plugin/agent.ts`), mais aucune requête ne le lit : `session/model-request.ts` construit le corps avec les seules options des crochets, et `temperature` n'arrive au corps que par `generation` (`ai/src/protocols/openai-chat.ts`). `opencode debug agents` les montre, d'où le « passés dans la requête » du 21 octobre (point 2 ci-dessous), qui était faux. L'effort de réflexion par agent et le titre sans réflexion de COMMANDES.md n'avaient donc aucun effet. Le plugin les envoie (point 28).
> - **Une commande sans limite** : l'outil shell accepte `timeout: 0` (« Set to 0 to disable the timeout », `tool/plugin/shell.ts`). Une commande d'un agent du pack reçoit alors 20 minutes, et aucune plus de 2 heures (point 8).
> - **Un flux muet attend 15 minutes** (`provider.ts` : `DEFAULT_CHUNK_TIMEOUT_MS = 900_000` entre deux évènements du flux, `DEFAULT_TIMEOUT_MS = 300_000` pour les en-têtes), et un délai dépassé est réessayé 3 fois au plus (`model-retry.ts` : `MAX_TIMEOUT_RETRIES = 3`) : près d'une heure figée quand le serveur ne ferme pas la connexion. Documenté : `chunkTimeout` dans les options du provider (README, COMMANDES.md « Qwen 3.8 »).
> - **Le titre d'une conversation** est écrit par la variante `none`, `minimal` ou `low` du modèle quand elle existe, sinon par le modèle lui-même (`session/context.ts`, `selectTitle`) ; une commande du pack nomme sa session sans requête (plugin, point 3). Documenté : une variante `none` sans réflexion, ou les options de l'agent `title`.
> - **Le cache de préfixe du serveur** : la v2 range son prompt du plus partagé au moins partagé (les instructions, puis la date et l'environnement, mis à jour par des messages ajoutés plutôt que réécrits : `session/context.ts`, `instructions/builtins.ts`). Les transformations du plugin gardent le début de la conversation identique d'une requête à la suivante dans un tour (vérifié par `tools/plugin-test.mjs`).
> - **La v2.1.4** (23 octobre) : aucun changement de l'API des plugins ni des évènements dont le pack se sert (les deux sources comparées). Elle corrige des défauts MCP qui pouvaient bloquer un run : les formulaires d'élicitation d'un serveur MCP jamais affichés (l'appel attendait sans fin), des serveurs MCP démarrés deux fois, des outils MCP refusés pour leur schéma de sortie, une requête MCP distante coupée après 5 minutes par Bun ; et elle ajoute `experimental.background_compaction` (le résumé du contexte préparé en arrière-plan). Pas lancée ici : la vérification de bout en bout reste à faire sur ta machine (MIGRATION.md, étape 4).
> - **Ce qui ne se mesure pas d'ici** : la vitesse du serveur du modèle (attente du premier token, tokens par seconde, prefix caching, passerelle). Le plugin la mesure maintenant sur tes runs (point 29) et `/outil vitesse` la lit.

## En bref

1. **Le plugin du pack ne se charge pas, et v2 démarre quand même** (constaté). Son journal dit seulement `WARN failed to load plugin … Plugin must export a default definition with an id and an effect or setup function`. Tout ce que fait le plugin disparaît sans autre signe : le dossier du dépôt comme limite des agents, le refus des secrets et des dumps d'environnement, les délais longs, un seul `/go` à la fois, les lignes `[[run …]]` des commandes (le modèle les lancerait lui-même), les titres d'avancement. **C'est le chantier principal, et il bloque : ne lance pas v2 sur ta configuration actuelle avant qu'il soit fait.**
2. **Le reste du pack est lu et converti tout seul** (constaté) : les 6 agents du pack et leurs règles (`bash` devient `shell`, `task` devient `subagent`, `write` devient `edit`), la température et le top_p (1.0 et 0.95 : lus, mais pas envoyés au modèle, voir l'analyse du 26 octobre ; le plugin les envoie), les règles globales, les règles MCP (même nom d'action `<serveur>_<outil>`, donc `*create*` etc. continuent de s'appliquer, code), et les commandes `/go`, `/fix`, `/daily`, `/review`, `/compare`, `/outil`.
3. **v2 lit les mêmes dossiers que la 1.19** : `~/.config/opencode` et `~/.local/share/opencode` (code). L'installer à côté sans précaution, c'est le pack sans son plugin (point 1). Pour l'essayer : des dossiers à part (section « Essayer sans risque »).
4. **Ce que v2 apporte au pack** :
   - les espaces de travail dans l'interface web, affichés pour tout projet git, sans restriction de version (code, à vérifier à l'écran) ; et des outils pour les agents : `worktree_create`, `worktree_list`, `worktree_remove`, `session_move` (déplace une session dans un autre dossier) et `session_rename` (code). `workspace.sh` devient inutile.
   - les injections `` !`…` `` des commandes tournent dans le dossier de la session (code : `cwd: location.directory`) : le défaut de la 1.19 qui a imposé les lignes `[[run …]]` du plugin semble corrigé (à vérifier).
   - un point d'accroche sur chaque commande shell avant son lancement, avec sa commande, son dossier, son délai et ses variables modifiables (`shell` → `create.before`), et un autre sur chaque décision de permission (`permission` → `evaluate`) : plus propres que ce que la 1.19 permet (code).
   - un sous-agent peut être repris par son `sessionID` (l'équivalent du `task_id` actuel) ou lancé en arrière-plan (code).
   - les skills ne deviennent plus des commandes `/` (constaté : seules les 6 commandes du pack et `init` sont listées).

## Ce qu'il faut changer, pièce par pièce

| Pièce | Avec OpenCode 1.19 | Avec OpenCode v2.1 | Travail |
|---|---|---|---|
| Plugin `compact-commands.js` | fonction qui renvoie des hooks (`tool.execute.before`, `command.execute.before`, `chat.params`, `event`…) | `Plugin.define({ id, setup })`, des hooks par domaine (`tool`, `shell`, `permission`, `session`, `aisdk`) et des transformations (`command`, `agent`, `skill`…) | Réécriture complète (détail ci-dessous). |
| Règles de permission | snippet au format 1.19, converti par v2 | format natif : liste `{ action, resource, effect }`, même ordre « la dernière règle qui correspond gagne » | Générer le format natif avec `tools/permissions.py` plutôt que compter sur la conversion. |
| Simulateur de permissions (1 721 cas) | moteur 1.19 recopié | v2 découpe toujours la commande avec tree-sitter, mais la ressource d'une commande redirigée inclut la redirection et les dossiers d'une commande passent par `external_directory` (code) | Porter le simulateur sur le moteur v2, puis rejouer le corpus. |
| Textes des agents et des commandes | « l'outil task », « son task_id » | outil `subagent`, reprise par `sessionID` | Remplacer dans `pilot.md`, `go.md`, `fix.md`, `AGENTS.global.md`. |
| Lignes `[[run …]]` des commandes | exécutées par le plugin | `` !`sh ~/.config/opencode/scripts/…` `` natif si le point 4 se confirme | Les convertir ; sinon, une commande définie par le plugin (`command.transform`). |
| `opencode.json`, section provider | options de modèle 1.19 | `reasoning` et `temperature` dans `provider.<id>.models.<modèle>`, et `compaction.prune`, sont ignorés (constaté, avertissement au démarrage) | Réécrire la partie provider (passerelle vLLM, `chat_template_kwargs`, délais) au format v2, avec ta vraie configuration. |
| Serveur | `opencode web` | `opencode serve` (API v2 et interface web) ; un mot de passe est généré à chaque démarrage, sauf si `OPENCODE_SERVER_PASSWORD` est fixé (constaté) | Nouvelle commande de démarrage dans COMMANDES.md. |
| `workspace.sh` et la marque `[dossier]` dans les titres | contournement de l'option absente | option native | Fait : l'interface v2 est vérifiée, `workspace.sh` n'est plus utile avec la v2. |
| Tests du plugin (461) et essais de bout en bout | faux client 1.19, API `/session/…` | autre forme de plugin, API `/api/…` | À réécrire avec le plugin. |

### Le plugin, fonction par fonction

| N° | Fonction | Où la mettre en v2 | Statut |
|---|---|---|---|
| 6, 7, 11 | Refus (secrets, dump d'environnement, `rm` récursif), agents limités au dépôt, outil appelé par son chemin | `tool` → `execute.before` (peut refuser l'appel et modifier son entrée) et `permission` → `evaluate` | code : les deux points d'accroche existent |
| 2, 8 | Environnement stable des commandes, délais longs (build, tests) | `shell` → `create.before` (variables, délai, dossier) | code |
| 1 | Scripts des commandes lancés dans le bon dossier | injections natives ou commande définie par le plugin | à vérifier |
| 9 | Un seul `/go` ou `/fix` à la fois par dossier | `session` → `prompt` | à vérifier |
| 5, 10, 12 | Titres d'avancement, d'issue (✅ ⛔) et du dossier | abonnement aux évènements et renommage de session | à vérifier |
| 4 | QCM qui lance la commande choisie | évènements et API de session | à vérifier |
| 3 | Ligne compacte de la commande avec la branche | `session` → `prompt` | à vérifier ; peut-être inutile si l'interface v2 affiche la branche |

Ordre conseillé : d'abord 6, 7, 11, 2 et 8 (sécurité et build), puis 1 (sans lui, `/go` ne marche plus), puis 9, puis le confort (5, 10, 12, 4, 3).

## Essayer sans risque

v2 prend ses dossiers dans les variables XDG (code) : avec des dossiers à part, il ne voit ni ta configuration 1.19 ni tes sessions.

```sh
mkdir -p ~/oc2/config/opencode ~/oc2/data ~/oc2/cli && npm install --prefix ~/oc2/cli @opencode/cli@2.1.2
XDG_CONFIG_HOME=~/oc2/config XDG_DATA_HOME=~/oc2/data OPENCODE_SERVER_PASSWORD='<un mot de passe>' ~/oc2/cli/node_modules/.bin/opencode2 serve --hostname 0.0.0.0 --port 4097
```
Installé dans `~/oc2/cli` plutôt qu'en global : le paquet fournit aussi une commande `opencode`, qui pourrait prendre la place de celle de la 1.19 dans ton PATH. L'interface web demande l'utilisateur `opencode` et ce mot de passe.
Il lit aussi `~/.claude` et `~/.agents` s'ils existent, ainsi que `.opencode`, `.claude` et `.agents` dans le dépôt (code).

## Risques

- v2 change vite : la 2.1.0 du 20 octobre a modifié volontairement les contrats des plugins et du SDK, douze jours après la 2.0.26. Le plugin réécrit devra viser une version précise, et chaque mise à jour se teste avant d'être installée.
- Pendant la bascule, le pack ne doit jamais tourner sans son plugin : en v2, un plugin qui ne se charge pas ne laisse qu'un avertissement dans le journal.
- La configuration du modèle (Qwen 3.8 derrière la passerelle vLLM) change de format : à refaire et à tester sur ta machine, je n'ai pas ta configuration.
