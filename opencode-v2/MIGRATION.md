# Passer le pack d'OpenCode 1.19 à OpenCode v2 — guide complet

Ce dossier `opencode-v2/` est le pack migré pour OpenCode v2.1.2. Le dossier `v2/` reste le pack pour OpenCode 1.19 : c'est ton retour arrière. Le pourquoi des changements est dans `ANALYSE.md`. Suis les étapes dans l'ordre ; chaque commande est à taper telle quelle dans un terminal de la machine qui héberge OpenCode (remplace seulement ce qui est entre `<…>`).

## 0. Ce qui est vérifié, et ce qui ne l'est pas

Vérifié avec le vrai OpenCode v2.1.2 (paquet npm `@opencode/cli`) sur un dépôt de test, avec un modèle simulé :
- le plugin `openrd-pack.js` se charge ;
- `/go` remplace les lignes `[[run …]]` par l'état du bon dépôt ;
- le plugin refuse `cat ~/.zshenv` (hors du dépôt) et `export -p` (dump de l'environnement), envoyés par le modèle ;
- un second `/go` lancé dans le même dossier pendant le premier reçoit une phrase de refus, et le dossier se libère à la fin du premier ;
- `/fortify` lance ses prérequis ;
- v2 lit les 7 agents (dont le nouveau `test-guardian`) et leurs règles, les 7 commandes, la température 1.0 / top_p 0.95 et les interdictions propres à v2.

Tests du pack :
- 477 vérifications du plugin ;
- 1 751 cas de permissions ;
- 30 fichiers d'agents, de commandes et de skills validés ;
- `fortify.sh` rejoué avec un faux `dotnet` dans 3 shells et 4 awk ;
- `shellcheck` sur tous les scripts.

Pas vérifié ici, faute d'accès :
- l'interface web v2 à l'écran ;
- ta passerelle vLLM avec Qwen 3.8 ;
- tes serveurs MCP ;
- un vrai `dotnet test` avec coverlet ;
- `/fortify` sur ton SSC.

L'étape 5 te fait vérifier tout ça avant la bascule.

## 1. Ce qui change pour toi

| | OpenCode 1.19 (pack `v2/`) | OpenCode v2 (pack `opencode-v2/`) |
|---|---|---|
| Lancer le serveur | `opencode web …` | `opencode serve --hostname 0.0.0.0 --port <port>` avec `OPENCODE_SERVER_PASSWORD` ; le navigateur demande l'utilisateur `opencode` et ce mot de passe |
| Plugin | `plugins/compact-commands.js` | `plugins/openrd-pack.js` ; l'ancien ne doit plus être dans le dossier (v2 ne le charge pas et ne le signale que dans son journal) |
| Un seul `/go`, `/fix` ou `/fortify` par dossier | refusé par le plugin | refusé par le plugin (porté) |
| Plusieurs tickets d'un dépôt | `workspace.sh` et l'adresse à coller | le sélecteur sous la zone de saisie d'une nouvelle session (à vérifier à l'étape 5) ; sinon `workspace.sh`, qui marche toujours |
| Message d'une commande | une ligne « /go ABC-123 — dépôt · branche » | le texte complet de la commande, état du dépôt compris (v2 n'a pas de partie cachée dans un message) |
| Titre des sessions | avancement, ✅ / ⛔, `[dossier]` | celui d'OpenCode (non porté, section 8) |
| QCM qui propose une commande | la commande choisie part seule | tape la commande (non porté, section 8) |
| `/go … comme dans ~/repos/old-api` | un dossier que tu nommes devient lisible | seulement un dossier déclaré dans `references` d'`opencode.json` (non porté, section 8) |
| Skills | chacun était aussi une commande `/` | plus de commande `/` par skill : `/outil` seul |
| Sous-agents | outil `task`, reprise par `task_id` | outil `subagent`, reprise par `sessionID` (textes du pack mis à jour) |
| Nouveau | | `/fortify` et l'agent `test-guardian` (section 9) |

## 2. Avant de commencer

1. Sauvegarde de ta configuration et de tes sessions, à garder jusqu'à la fin de l'étape 6 :
```sh
cp -r ~/.config/opencode ~/opencode-config-1.19 && cp -r ~/.local/share/opencode ~/opencode-data-1.19
```
2. Le pack à jour :
```sh
cd ~/OpenRDCode && git pull && ls opencode-v2/plugins
```
La dernière ligne affiche `openrd-pack.js`.

## 3. Essai isolé, sans toucher à la 1.19

v2 lit les mêmes dossiers que la 1.19 (`~/.config/opencode`, `~/.local/share/opencode`) : l'essai utilise des dossiers à part. Les scripts restent dans `~/.config/opencode/scripts` : les commandes et les règles des agents les appellent à cet endroit, et ceux de `opencode-v2/scripts` remplacent ceux de la 1.19 sans la gêner (mêmes scripts, plus `fortify.sh`).

1. v2 dans son propre dossier. Le paquet fournit aussi une commande `opencode`, qui ne doit pas prendre la place de celle de la 1.19 :
```sh
mkdir -p ~/oc2/cli ~/oc2/config/opencode/skills ~/oc2/data && npm install --prefix ~/oc2/cli @opencode/cli@2.1.2 && ~/oc2/cli/node_modules/.bin/opencode2 --version
```
La dernière ligne affiche `opencode v2.1.2`.
2. Le pack migré :
```sh
cd ~/OpenRDCode && cp -r opencode-v2/agents opencode-v2/commands opencode-v2/plugins ~/oc2/config/opencode/ && cp -r opencode-v2/skills/. ~/oc2/config/opencode/skills/ && cp opencode-v2/scripts/*.sh ~/.config/opencode/scripts/ && ls ~/oc2/config/opencode/plugins ~/oc2/config/opencode/agents
```
Tu dois voir `openrd-pack.js` seul dans `plugins`, et 7 agents dont `test-guardian.md`.
3. `~/oc2/config/opencode/AGENTS.md` : copie `opencode-v2/AGENTS.global.md`, puis reprends tes sections « Daily » et « Release groups » de ton `~/.config/opencode/AGENTS.md`.
4. `~/oc2/config/opencode/opencode.json` : copie de ton `~/.config/opencode/opencode.json`, puis remplace ses sections `agent` et `permission` par celles de `opencode-v2/opencode.snippet.json`. Le reste ne change pas : `provider`, `mcp`, `model`, `references`, `experimental`, `compaction`. v2 convertit ces sections et dit ce qu'il ignore (étape 4).
5. Démarrer, sur un autre port que la 1.19 :
```sh
XDG_CONFIG_HOME=~/oc2/config XDG_DATA_HOME=~/oc2/data OPENCODE_SERVER_PASSWORD='<un mot de passe>' ~/oc2/cli/node_modules/.bin/opencode2 serve --hostname 0.0.0.0 --port 4097 --print-logs 2> ~/oc2/serve.log
```
Ce terminal reste occupé tant que le serveur tourne ; les commandes suivantes vont dans un autre terminal. v2 lit aussi `~/.claude` et `~/.agents` s'ils existent, ainsi que `.opencode`, `.claude` et `.agents` dans chaque dépôt.

## 4. Le modèle (Qwen 3.8 derrière la passerelle)

Ce que v2 a ignoré de ta configuration :
```sh
grep 'configuration normalization diagnostic' ~/oc2/serve.log | grep -o 'path=[^ ]*' | sort -u
```
Ce que j'ai constaté sur la configuration de test : v2 ignore `reasoning` et `temperature` dans `provider.<id>.models.<modèle>`, ainsi que `compaction.prune`. La température et le top_p des agents passent, eux, dans chaque requête. Pour chaque ligne affichée :
- `temperature`, `top_p` : déjà réglés par agent, rien à faire ;
- tout le reste (le mode thinking, `chat_template_kwargs`, `reasoning_effort`, les délais `headerTimeout` et `chunkTimeout`) : envoie-moi ces lignes (sans clé ni URL) et je les traduis au format v2.

Ensuite, refais le test de la section « Qwen 3.8 » de COMMANDES.md : le modèle servi répond, et son raisonnement est actif.

## 5. Vérifier dans l'interface web de l'essai

L'adresse est `http://<machine>:4097`, avec l'utilisateur `opencode` et ton mot de passe.

1. **Plugin** : `grep -c 'failed to load plugin' ~/oc2/serve.log` affiche `0`.
2. **Commandes** : `/` dans la zone de saisie liste `go`, `fix`, `fortify`, `daily`, `review`, `compare`, `outil`.
3. **Garde-fou** : dans une session d'un dépôt, « affiche le contenu de ~/.zshenv » finit par « Refused by the pack ». Le refus s'écrit aussi dans le journal : `grep 'openrd-pack' ~/oc2/serve.log`.
4. **`/go`** sur un petit ticket d'un dépôt de test : le message de la commande montre « Repository root: <ton dépôt> », puis le travail va jusqu'à la MR Draft.
5. **Un seul `/go` par dossier** : pendant que le `/go` du point 4 tourne, un `/go` dans une autre session du même dépôt répond « ⛔ /go refusé : /go tourne déjà dans ce dossier… ».
6. **MCP** : une question à chaque serveur (« mes tickets du sprint », « la dernière pipeline de ce dépôt », « les vulnérabilités Fortify de <application> »). Une écriture, par exemple commenter une MR, doit être refusée.
7. **Espaces de travail** : nouvelle session d'un dépôt git → sous la zone de saisie, « Local » → « Nouvel espace de travail ». S'il est absent, `workspace.sh` (COMMANDES.md) fait la même chose.
8. **`/fortify`** sur un dépôt qui a des tests unitaires : d'abord `sh ~/.config/opencode/scripts/fortify.sh prereq` dans ce dépôt (section 9), puis `/fortify 1` pour un lot d'une seule vulnérabilité.

Si un point échoue : arrête là, garde la 1.19, et envoie-moi la ligne du journal en cause (sans secret).

## 6. Bascule définitive

Quand l'étape 5 passe :
1. Arrête le serveur de l'essai et celui de la 1.19. Puis la configuration de l'essai devient la tienne, sans l'ancien plugin :
```sh
cp -r ~/oc2/config/opencode/. ~/.config/opencode/ && rm -f ~/.config/opencode/plugins/compact-commands.js && ls ~/.config/opencode/plugins
```
La dernière ligne affiche `openrd-pack.js` seul.
2. v2 pour tout le système, à la place de la 1.19. La version est fixée : chaque mise à jour se teste d'abord avec l'étape 3.
```sh
npm uninstall -g opencode-ai && npm install -g @opencode/cli@2.1.2 && opencode --version
```
3. Ta commande de démarrage devient (sans les variables `XDG_…`) :
```sh
OPENCODE_SERVER_PASSWORD='<mot de passe>' opencode serve --hostname 0.0.0.0 --port <ton port>
```
4. Tes sessions de la 1.19 : le code de v2 contient une migration des données de la 1.19 (lue, pas essayée). Garde `~/opencode-data-1.19` tant que tu n'as pas revu tes anciennes sessions dans v2.

## 7. Retour arrière

```sh
npm uninstall -g @opencode/cli && npm install -g opencode-ai@<ta version 1.19> && rm -rf ~/.config/opencode ~/.local/share/opencode && cp -r ~/opencode-config-1.19 ~/.config/opencode && cp -r ~/opencode-data-1.19 ~/.local/share/opencode
```
Puis ta commande `opencode web` habituelle. Les fiches ticket sont dans le `.git` de chaque dépôt : elles servent aux deux versions.

## 8. Ce qui n'est pas porté, et pourquoi

Le plugin v2 garde toutes les protections :
- les refus (secrets, dumps d'environnement, `rm` récursif) ;
- les agents limités à leur dépôt ;
- les délais longs ;
- l'outil appelé par son chemin ;
- l'environnement stable des commandes ;
- les scripts des commandes lancés dans le bon dépôt ;
- un seul pilote par dossier ;
- le refus des outils v2 qui déplacent une session ou créent un worktree.

Ce qui n'est pas porté :

| Fonction (numéro dans le plugin) | Pourquoi | En attendant |
|---|---|---|
| Ligne compacte de la commande (3) | v2 n'a pas de partie cachée dans un message | l'état du dépôt est visible dans le message |
| Commande choisie dans un QCM (4) | la forme des réponses et le lancement de commande par un plugin ne sont pas documentés dans v2.1.2 : non vérifiable ici | tape la commande |
| Avancement, ✅ / ⛔ et `[dossier]` dans les titres (5, 10, 12) | même raison pour la lecture des messages et le renommage | regarde la session |
| Dossiers nommés dans un message (7) | v2 ne dit pas au plugin si un texte vient de toi ou d'un agent : l'ouvrir aux deux laisserait un agent rendre lisible un dossier de secrets | déclare le dossier dans `references` |
| Simulateur de permissions sur le moteur v2 | ses 1 751 cas passent sur le moteur 1.19 ; v2 garde la même logique de règles (lue dans son code) et lit bien les règles (constaté) | l'étape 5, points 3 et 6 |

## 9. `/fortify` et l'agent `test-guardian`

**Prérequis**, vérifiés au début de chaque `/fortify` par `fortify.sh prereq` :
- `dotnet` disponible ;
- au moins un projet de tests unitaires ;
- `coverlet.collector` dans chaque projet de tests (ou dans un `Directory.Build.props`) ;
- la ligne `APPSEC_PROJECT_NAME` dans `appsec-ci.env`.

Pour ajouter coverlet, fais-le toi-même, dans une MR à part :
```sh
dotnet add <chemin du projet de tests>.csproj package coverlet.collector
```

**Déroulé.** `/fortify [nombre ≤ 5] [catégorie, fichier ou clé Jira]` dans une session du dépôt, sur develop :
1. **Sélection** (pilote, lecture seule) : jusqu'à 5 vulnérabilités Critical puis High de ce dépôt, de préférence de la même catégorie.
2. **Analyse séparée** : un sous-agent `analyst` par vulnérabilité, l'un après l'autre. Chacun écrit la carte `V<n>.md` de sa faille, dans le dossier du lot (`.git/opencode-tickets/<CLÉ>.fortify/`, jamais commité). La carte contient la faille, le verdict (vraie faille ou faux positif probable), la correction, le contexte (module, méthodes publiques, dépendances, ce qu'en disent AGENTS.md et la doc) et les tests à écrire. C'est par ces cartes que les agents se passent le travail.
3. **Pour chaque vulnérabilité, l'une après l'autre** :
   - **`test-guardian`, avant le correctif** :
     - le module et ses dépendances sur deux niveaux (`fortify.sh deps`) ;
     - la couverture de départ mesurée par coverlet, fichier par fichier ;
     - des tests de contexte qui **passent** sur le code actuel, jusqu'à couvrir la méthode vulnérable, les méthodes publiques qui y mènent (cas normal et cas d'erreur) et les méthodes des dépendances sur ce chemin ;
     - puis les tests de la faille, qui doivent **échouer** pour la bonne raison (`fortify.sh red`). Un test qui ne compile pas ou qui passe ne compte pas.
   - **`coder`** : la correction minimale, sans toucher aux tests.
   - **`test-guardian`, après le correctif** (sa même session) :
     - les tests de la faille **passent** (`fortify.sh green`) ;
     - aucun fichier du module ou de ses dépendances n'a perdu de couverture (`fortify.sh compare`) ;
     - toutes les lignes de la méthode vulnérable sont couvertes.
   - **Un commit par vulnérabilité**, avec sa correction et ses tests.
4. **Livraison** comme `/go` : build et tests complets, auto-review, push, puis une MR Draft avec un tableau par vulnérabilité. Il donne :
   - le contexte : déjà couvert, ou combien de tests ajoutés ;
   - le test de la faille : rouge avant, vert après ;
   - la couverture avant → après, par fichier ;
   - le commit ;
   - en plus, les vulnérabilités non corrigées ou non traitées, avec leur raison.

**Ce qui est garanti par des scripts plutôt que par le modèle :**
- le rouge et le vert des tests ;
- la couverture, et l'absence de perte de couverture ;
- le fait que le `test-guardian` n'écrit que dans les projets de tests (`fortify.sh tests-only`, et ses règles d'édition) ;
- le fait que le travail d'une faille ratée est mis de côté sans rien perdre (`fortify.sh discard` : `git stash list` le montre, `git stash pop` le ramène).

**Les cas difficiles :**

| Cas | Ce qui se passe |
|---|---|
| coverlet manque, pas de projet de tests, pas de ligne SSC | arrêt au début, avec la commande à faire |
| Fortify injoignable, application ou version introuvable | arrêt, rien n'est créé |
| Faux positif probable | non traité, noté « à déclarer dans SSC par toi » |
| Un test de contexte figeait le comportement dangereux (il échoue après le correctif) | le `test-guardian` le met à jour vers le comportement sûr et le signale dans la MR ; tout autre test qui casse est une régression, renvoyée au coder |
| Le test de la faille passe sur le code actuel | un second essai du `test-guardian` ; sinon la faille est abandonnée : son travail est mis de côté et elle est notée « non corrigée » |
| Une faille de configuration, qu'aucun test unitaire ne peut montrer | « non démontrable » avec la raison ; seul le test du comportement sûr est écrit |
| Build cassé, correction qui échoue, couverture perdue | le debugger, puis un second essai ; sinon la faille est abandonnée et mise de côté, et le lot continue |
| Coupure (timeout de la passerelle, redémarrage, arrêt) | `/fortify` relancé sur la branche reprend à la faille en cours. Les failles déjà commitées ne sont pas refaites. Le travail inachevé de la faille en cours est mis de côté (rien d'une faille n'est commité avant sa dernière phase), puis elle repart de sa première phase |
| Second `/fortify` ou `/go` dans le même dossier | refusé par le plugin |
| Contrôle avant push en échec (un secret, par exemple) | rien n'est poussé |

**Limites à connaître :**
- La mesure de couverture fait tourner les tests d'un projet de tests avec coverlet : plusieurs minutes par phase sur un gros projet. C'est le prix d'une preuve chiffrée.
- Les dépendances sont trouvées par les constructeurs (classiques ou primaires) et les classes qui implémentent les interfaces reçues. Une dépendance créée avec `new` ou trouvée par réflexion n'est pas vue. Le `test-guardian` la complète à la lecture du code et la signale.
- Le premier essai réel dira si les noms d'outils de ton serveur MCP Fortify et les conventions de tes tests demandent des ajustements.

## 10. Fichiers : `opencode-v2/` par rapport à `v2/`

- **Nouveaux :**
  - `plugins/openrd-pack.js` : le cœur du plugin 1.19, inchangé, et l'adaptateur v2 à la fin. Ses points d'accroche sont `tool`, `shell`, `session` et le flux d'évènements. Il refuse aussi `session_move`, `worktree_create` et `worktree_remove`, et ne laisse tourner qu'un pilote par dossier.
  - `commands/fortify.md`, `agents/test-guardian.md`, `scripts/fortify.sh`, ce guide et `ANALYSE.md`.
  - `compact-commands.js` n'existe plus.
- **Modifiés :**
  - `commands/go.md`, `commands/fix.md`, `agents/pilot.md`, `skills/pack-doc/SKILL.md` et `AGENTS.global.md` : outil `subagent` et reprise par `sessionID` ; le pilote connaît `/fortify` et le `test-guardian` ; les demandes Fortify vont vers `/fortify`, et les espaces de travail vers l'interface v2.
  - `tools/permissions.py` : les règles du `test-guardian` (édition dans les projets de tests seulement), l'interdiction de `fortify.sh discard` à tout autre agent que le pilote et l'interdiction des trois outils v2. `opencode.snippet.json` et les lignes `permission:` des agents sont régénérés.
  - `tools/plugin-test.mjs` (adaptateur v2 et verrou de dossier) et `tools/permission-corpus.mjs` (cas du `test-guardian` et de `fortify.sh`).
  - `COMMANDES.md` et `README.md` : chemins `opencode-v2/`, nom du plugin, section Fortify, renvoi vers ce guide.
- **Identiques à `v2/`** : les autres scripts.
