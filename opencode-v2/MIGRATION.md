# Passer le pack d'OpenCode 1.19 à OpenCode v2 — guide complet

Ce dossier `opencode-v2/` est le pack migré. Le dossier `v2/` reste le pack pour OpenCode 1.19 : c'est ton retour arrière. Le pourquoi de chaque changement est dans `ANALYSE.md`.

## 0. Ce qui est vérifié, et ce qui ne l'est pas

Vérifié avec OpenCode v2.1.2 (paquet npm `@opencode/cli`), sur un dépôt de test avec un modèle simulé :
- le plugin `openrd-pack.js` se charge (aucun « failed to load plugin » dans le journal) ;
- `/go ABC-123` lancé par l'API v2 : les lignes `[[run …]]` sont remplacées par l'état du bon dépôt (« Repository root: … ») ;
- deux commandes interdites, envoyées par le modèle, sont refusées par le plugin avec son message : `cat ~/.zshenv` (hors du dépôt) et `export -p` (dump de l'environnement) ;
- les 6 agents, leurs règles converties (`bash` → `shell`, `task` → `subagent`), leur température 1.0 / top_p 0.95, les 7 commandes du pack (`/fortify` comprise) et les nouvelles interdictions (`session_move`, `worktree_create`, `worktree_remove`) sont lus par v2 ;
- 469 vérifications du plugin (dont 8 de l'adaptateur v2), 1 721 cas de permissions, 29 fichiers d'agents, de commandes et de skills validés.

Pas vérifié ici, faute d'accès : l'interface web v2 à l'écran (le sélecteur d'espaces de travail est lu dans le code), ta passerelle vLLM avec Qwen 3.8, tes serveurs MCP (GitLab, Jira, Sonar, Fortify), un `/go` avec un vrai modèle, et `/fortify` de bout en bout (il faut SSC et un projet .NET). La section 5 te fait vérifier tout ça en une fois.

## 1. Ce qui change pour toi

| | OpenCode 1.19 (pack `v2/`) | OpenCode v2 (pack `opencode-v2/`) |
|---|---|---|
| Lancer le serveur | `opencode web …` | `opencode2 serve --hostname 0.0.0.0 --port <port>`, avec `OPENCODE_SERVER_PASSWORD` ; le navigateur demande l'utilisateur `opencode` et ce mot de passe |
| Plugin | `plugins/compact-commands.js` | `plugins/openrd-pack.js` (l'ancien ne doit plus être dans le dossier : v2 ne le charge pas et le signale seulement dans le journal) |
| Plusieurs tickets d'un dépôt | `workspace.sh` et l'adresse à coller | le sélecteur sous la zone de saisie d'une nouvelle session (à vérifier, section 5) ; `workspace.sh` marche toujours |
| Message d'une commande | une ligne « /go ABC-123 — dépôt · branche » | le texte complet de la commande, état du dépôt compris (v2 n'a pas de partie cachée dans un message) |
| Titre des sessions | avancement, ✅ / ⛔, `[dossier]` | pas encore porté : le titre est celui d'OpenCode |
| QCM qui propose une commande | la commande choisie part seule | pas encore porté : tape la commande |
| Deux `/go` dans le même dossier | le second est refusé | pas encore porté : un espace de travail par ticket |
| `/go … comme dans ~/repos/old-api` | un dossier que tu nommes devient lisible | seulement un dossier déclaré dans `references` d'`opencode.json` |
| Skills | chacun était aussi une commande `/` | plus de commande `/` par skill : `/outil` seul |
| Sous-agents | outil `task`, reprise par `task_id` | outil `subagent`, reprise par `sessionID` (textes du pack mis à jour) |
| Nouveau | | `/fortify` (section 9) |

## 2. Avant de commencer

1. Sauvegarde de ta configuration et de tes sessions (à garder jusqu'à la fin de la section 6) :
```sh
cp -r ~/.config/opencode ~/opencode-config-1.19 && cp -r ~/.local/share/opencode ~/opencode-data-1.19
```
2. `cd ~/OpenRDCode && git pull` : le pack migré est dans `opencode-v2/`.

## 3. Essai isolé, sans toucher à la 1.19

v2 lit les mêmes dossiers que la 1.19 (`~/.config/opencode`, `~/.local/share/opencode`) : l'essai utilise des dossiers à part. Les scripts restent dans `~/.config/opencode/scripts` (ce sont les mêmes fichiers dans les deux packs ; les commandes et les règles les appellent à cet endroit).

1. Installer v2 dans son propre dossier (le paquet fournit aussi une commande `opencode`, qui ne doit pas prendre la place de celle de la 1.19) :
```sh
mkdir -p ~/oc2/cli ~/oc2/config/opencode ~/oc2/data && npm install --prefix ~/oc2/cli @opencode/cli@2.1.2 && ~/oc2/cli/node_modules/.bin/opencode2 --version
```
2. Copier le pack migré, sans l'ancien plugin :
```sh
cd ~/OpenRDCode && cp -r opencode-v2/agents opencode-v2/commands opencode-v2/plugins ~/oc2/config/opencode/ && mkdir -p ~/oc2/config/opencode/skills && cp -r opencode-v2/skills/. ~/oc2/config/opencode/skills/ && cp -r opencode-v2/scripts/. ~/.config/opencode/scripts/ && ls ~/oc2/config/opencode/plugins
```
La dernière ligne doit afficher `openrd-pack.js` seul.
3. `~/oc2/config/opencode/AGENTS.md` : `opencode-v2/AGENTS.global.md`, avec tes sections « Daily » et « Release groups » reprises de ton `~/.config/opencode/AGENTS.md`.
4. `~/oc2/config/opencode/opencode.json` : une copie de ton `~/.config/opencode/opencode.json`, dont tu remplaces les sections `agent` et `permission` par celles de `opencode-v2/opencode.snippet.json`. Le reste (`provider`, `mcp`, `model`, `references`…) ne change pas : v2 le convertit (section 4).
5. Démarrer (un autre port que la 1.19) :
```sh
XDG_CONFIG_HOME=~/oc2/config XDG_DATA_HOME=~/oc2/data OPENCODE_SERVER_PASSWORD='<un mot de passe>' ~/oc2/cli/node_modules/.bin/opencode2 serve --hostname 0.0.0.0 --port 4097 --print-logs 2> ~/oc2/serve.log
```
v2 lit aussi `~/.claude` et `~/.agents` s'ils existent, et `.opencode`, `.claude`, `.agents` dans chaque dépôt.

## 4. Le modèle (Qwen 3.8 derrière la passerelle)

v2 convertit la section `provider`, mais ignore certaines options en le disant au démarrage. Ce qu'il a ignoré :
```sh
grep 'configuration normalization diagnostic' ~/oc2/serve.log | grep -o 'path=[^ ]*' | sort -u
```
Constaté sur la configuration de test : `reasoning` et `temperature` dans `provider.<id>.models.<modèle>`, et `compaction.prune`, sont ignorés. La température et le top_p des agents passent, eux (dans la requête). Pour chaque ligne de ta configuration :
- `temperature`, `top_p` : déjà réglés par agent, rien à faire ;
- les options du mode thinking (`chat_template_kwargs`, `reasoning_effort`) et les délais (`headerTimeout`, `chunkTimeout`) : vérifie qu'ils ne sont pas dans la liste ; s'ils y sont, montre-moi les lignes (sans clé ni URL) et je les traduis au format v2 ;
- puis le test habituel de la section « Qwen 3.8 » de COMMANDES.md : le modèle servi répond, et le raisonnement est actif.

## 5. Vérifier, dans l'interface web de l'essai (`http://<machine>:4097`)

1. Plugin chargé : `grep -c 'failed to load plugin' ~/oc2/serve.log` affiche `0`.
2. Commandes : `/` dans la zone de saisie liste `go`, `fix`, `fortify`, `daily`, `review`, `compare`, `outil`.
3. Garde-fou : dans une session d'un dépôt, « affiche le contenu de ~/.zshenv » doit finir par « Refused by the pack ».
4. `/go` sur un petit ticket d'un dépôt de test : le message de la commande montre « Repository root: <ton dépôt> », puis le travail suit son cours habituel jusqu'à la MR Draft.
5. MCP : une question simple à chaque serveur (« mes tickets du sprint », « la dernière pipeline de ce dépôt »). Une écriture (commenter une MR) doit être refusée.
6. Espaces de travail : nouvelle session d'un dépôt git → sous la zone de saisie, le sélecteur « Local » → « Nouvel espace de travail ». Absent : `workspace.sh` (COMMANDES.md) fait la même chose.
7. Un refus du pack s'écrit dans le journal : `grep 'openrd-pack' ~/oc2/serve.log`.

Un point qui échoue : arrête là, garde la 1.19, et envoie-moi la ligne du journal (sans secret).

## 6. Bascule définitive

Quand la section 5 passe :
1. Arrête le serveur 1.19, puis remplace la configuration par celle de l'essai, et retire l'ancien plugin :
```sh
cp -r ~/oc2/config/opencode/. ~/.config/opencode/ && rm -f ~/.config/opencode/plugins/compact-commands.js && ls ~/.config/opencode/plugins
```
2. Installe v2 pour tout le système à la place de la 1.19 (version fixée : chaque mise à jour se teste d'abord avec la section 3) :
```sh
npm uninstall -g opencode-ai && npm install -g @opencode/cli@2.1.2 && opencode --version
```
3. Démarre comme à la section 3, sans les variables `XDG_…` : ta commande de démarrage habituelle devient `OPENCODE_SERVER_PASSWORD='<mot de passe>' opencode serve --hostname 0.0.0.0 --port <ton port>`.
4. Tes sessions de la 1.19 : v2 contient une migration des données de la 1.19 (lue dans son code, pas essayée ici). Garde `~/opencode-data-1.19` tant que tu n'as pas vu tes anciennes sessions dans v2.

## 7. Retour arrière

```sh
npm uninstall -g @opencode/cli && npm install -g opencode-ai@<ta version 1.19> && rm -rf ~/.config/opencode && cp -r ~/opencode-config-1.19 ~/.config/opencode
```
Puis ta commande `opencode web` habituelle. Les fiches ticket sont dans le `.git` de chaque dépôt : elles servent aux deux versions.

## 8. Ce qui n'est pas encore porté

Le plugin v2 garde tout ce qui protège : refus des secrets et des dumps d'environnement, agents limités à leur dépôt, délais longs, outil appelé par son chemin, environnement stable des commandes, scripts des commandes lancés dans le bon dépôt. Le confort suit, avec les points d'accroche de v2 déjà repérés :

| Fonction (numéro dans le plugin) | En attendant | Pour la porter |
|---|---|---|
| Ligne compacte de la commande (3) | l'état du dépôt est visible dans le message | `ctx.session.synthetic` |
| Commande choisie dans un QCM (4) | tape la commande | évènements de session et `ctx.session.command` |
| Avancement, ✅ / ⛔ et `[dossier]` dans les titres (5, 10, 12) | regarde la session | `ctx.event.subscribe` et `ctx.session.update` |
| Un seul `/go` ou `/fix` par dossier (9) | un espace de travail par ticket | `session` → `prompt` et les évènements de fin de tour |
| Dossiers nommés dans un message (7) | déclare le dossier dans `references` | `session` → `prompt`, en ne lisant que ton texte |
| Simulateur de permissions | ses 1 721 cas passent avec le moteur de la 1.19, et v2 garde la même logique de règles (lue dans son code) | porter le simulateur sur le moteur v2 |
| Format des règles | v2 convertit le format 1.19 (constaté) | générer le format natif `{ action, resource, effect }` |

## 9. `/fortify` : le lot de vulnérabilités du chapter lead

`/fortify [nombre ≤ 5] [catégorie, fichier ou clé Jira] [directives]`, dans une session du dépôt, sur develop :
1. **Sélection** (pilote, Fortify en lecture seule) : application SSC du dépôt, version `develop`, filtre « Security Auditor View », Critical puis High, jusqu'à 5 vulnérabilités de ce dépôt, de préférence de la même catégorie (une seule sorte de correction par MR : la plus simple à relire).
2. **Analyse** (analyste) : une étape par vulnérabilité dans la fiche, avec la correction, les tests unitaires qui couvrent déjà ce code (trouvés dans les projets de tests), ou « non couvert », et les tests à écrire.
3. **Une vulnérabilité, un sous-agent `coder`** (contexte frais, adapté aux limites de Qwen), toujours dans cet ordre :
   - le contexte : si rien ne le couvre, des tests de caractérisation qui **passent** sur le code actuel ;
   - la vulnérabilité : un test qui **échoue** sur le code actuel, pour la raison de la faille (ou « non démontrable par un test unitaire » quand c'est de la configuration) ;
   - la correction minimale, puis tous ces tests au vert.
   - Un commit par vulnérabilité, la correction avec ses tests : la relecture se fait commit par commit.
4. **En cas d'échec** : le debugger, puis la même session du coder une fois. Toujours en échec : le coder défait ses changements, la vulnérabilité est notée « non corrigée » avec sa raison, et le lot continue. Une vulnérabilité ne bloque jamais les autres. Relancé, `/fortify` reprend où il s'est arrêté (la fiche du lot).
5. **Livraison** comme `/go` : build et tests complets, auto-review, push, MR Draft avec un tableau par vulnérabilité (contexte déjà couvert ou tests ajoutés, test de la faille rouge puis vert, commit), les non corrigées, et le rappel : le scan Fortify de la CI doit les marquer corrigées ; un faux positif se déclare dans SSC par toi, jamais par l'agent.

À vérifier au premier essai : les noms des outils MCP de ton serveur Fortify (le pilote les découvre), et les conventions de tests de tes dépôts. Amélioration possible ensuite : mesurer la couverture du code vulnérable avec coverlet (`dotnet test --collect:"XPlat Code Coverage"`) au lieu de chercher les tests par nom.

## 10. Fichiers : `opencode-v2/` par rapport à `v2/`

- `plugins/openrd-pack.js` : nouveau. Le cœur du plugin 1.19, inchangé, plus l'adaptateur v2 à la fin (`Plugin.define`, points d'accroche `tool`, `shell` et `session`), et le refus de `session_move`, `worktree_create` et `worktree_remove`. `compact-commands.js` n'existe plus.
- `commands/fortify.md` : nouveau.
- `commands/go.md`, `commands/fix.md`, `agents/pilot.md`, `skills/pack-doc/SKILL.md`, `AGENTS.global.md` : outil `subagent` et reprise par `sessionID` ; le pilote connaît `/fortify` ; `AGENTS.global.md` route « corrige les vulnérabilités Fortify » vers `/fortify` et les espaces de travail vers l'interface v2.
- `tools/permissions.py` : interdiction des trois outils v2 ; `opencode.snippet.json` et les lignes `permission:` des agents régénérés.
- `tools/plugin-test.mjs` : charge `openrd-pack.js` avec une imitation de `@opencode/plugin`, plus 8 vérifications de l'adaptateur.
- `COMMANDES.md`, `README.md` : chemins `opencode-v2/`, nom du plugin, renvoi vers ce guide.
- `scripts/` : identiques à `v2/scripts/`.
- `ANALYSE.md` : l'analyse de départ.
