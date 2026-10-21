# Passer d'OpenCode 1.19 à OpenCode v2, pas à pas

Ce guide part de zéro. Chaque étape dit **pourquoi** on la fait, **quoi taper**, **ce que tu dois voir**, et **quoi faire si ce n'est pas ce que tu vois**. Ne saute aucune étape et ne passe à la suivante que si la précédente donne le résultat attendu.

Le principe : OpenCode v2 s'installe **à côté** de ta version 1.19, dans ses propres dossiers, sur un autre port. La 1.19 continue de tourner comme avant pendant tout l'essai. Revenir en arrière consiste à rouvrir l'adresse de la 1.19.

Durée : environ 45 minutes la première fois.

## Sommaire

| Étape | Ce que tu fais | Durée |
|---|---|---|
| 0 | Comprendre les mots utilisés | 3 min |
| 1 | Ouvrir un terminal sur la machine d'OpenCode | 2 min |
| 2 | Faire l'état des lieux de ton installation actuelle | 5 min |
| 3 | Sauvegarder | 2 min |
| 4 | Télécharger et installer OpenCode v2 | 5 min |
| 5 | Préparer la configuration de la v2 | 3 min |
| 6 | Démarrer la v2 | 2 min |
| 7 | L'ouvrir dans ton navigateur et te connecter | 5 min |
| 8 | Vérifier que tout marche | 15 min |
| 9 | Vérifier le modèle (Qwen) | 5 min |
| 10 | Utiliser la v2 au quotidien | — |
| 11 | Revenir à la 1.19 | 1 min |
| 12 | Dépannage | — |

Les étapes 13 à 15 sont des annexes : ce qui n'a pas changé et ce qui change, ce qui n'est pas porté, et les fichiers du pack.

## Étape 0 — Les mots utilisés

- **Machine d'OpenCode** : l'ordinateur distant où tourne OpenCode, celui dont tu ouvres l'interface web dans ton navigateur. Ce n'est pas ton Mac.
- **Terminal** : une fenêtre où l'on tape des commandes sur cette machine. Chaque commande de ce guide se tape dans un terminal **de la machine d'OpenCode**, sauf quand il est écrit « sur ton Mac ».
- **CLI** (« command line interface ») : un programme qu'on lance en tapant son nom dans un terminal. OpenCode est une CLI : la commande `opencode` démarre son serveur.
- **npm** : le gestionnaire de paquets de Node.js. Il télécharge des programmes depuis un **registre npm** (un dépôt en ligne de paquets : `registry.npmjs.org`, ou le miroir Artifactory de ton entreprise).
- **Paquet** : un programme publié sur un registre npm. OpenCode 1.19 est le paquet `opencode-ai`. OpenCode v2 est le paquet **`@opencode/cli`**, publié par l'équipe d'OpenCode (son code est sur GitHub, projet `sst/opencode`).
- **Port** : le numéro qui suit l'adresse dans `http://machine:4096`. Deux serveurs ne peuvent pas utiliser le même port. Ici, la v2 utilise le port **4097** et ta 1.19 garde le sien.
- **Dossier de configuration** : là où OpenCode lit ses réglages, agents, commandes et plugins. Pour la 1.19 : `~/.config/opencode`. Pour la v2 : `~/oc2/config/opencode`. Le `~` veut dire ton dossier personnel sur la machine, par exemple `/home/dev`.

## Étape 1 — Ouvrir un terminal sur la machine d'OpenCode

**Pourquoi.** Toutes les commandes s'exécutent sur la machine où tourne OpenCode, pas sur ton Mac.

**Quoi faire.** Ouvre le terminal que tu utilises déjà pour les commandes de `COMMANDES.md`, par exemple ta connexion SSH à cette machine ou le terminal de ton environnement de travail. Puis tape :
```sh
whoami && hostname && echo "$HOME"
```

**Ce que tu dois voir.** Trois lignes : ton nom d'utilisateur sur la machine (par exemple `dev`), le nom de la machine, et ton dossier personnel (par exemple `/home/dev`). Note le nom de la machine : il te servira à l'étape 7.

**Si tu vois autre chose.** Si c'est le nom de ton Mac, tu es dans un terminal de ton Mac : connecte-toi d'abord à la machine d'OpenCode.

## Étape 2 — L'état des lieux de ton installation actuelle

**Pourquoi.** Savoir comment ta 1.19 est installée et lancée, pour l'installer de la même façon et ne rien casser.

Tape ces commandes une par une. Chaque bloc dit ce que tu dois noter.

**2.1 La version de la 1.19.** La commande l'enregistre aussi dans un fichier, pour pouvoir la réinstaller à l'identique un jour :
```sh
opencode --version | tee ~/opencode-version-1.19.txt
```
Tu dois voir un numéro du type `1.19.0`. Note-le.

**2.2 Comment elle est installée :**
```sh
npm ls -g --depth=0 2>/dev/null | grep -i opencode
```
Deux réponses possibles :
- **Une ligne `opencode-ai@1.19.x`** : la 1.19 a été installée avec npm. C'est le cas prévu par ce guide.
- **Rien** : elle a été installée autrement, par exemple par l'équipe qui gère ton environnement. Tu peux quand même suivre ce guide : la v2 s'installe dans ton dossier personnel et ne touche pas à la 1.19. Si ton entreprise interdit d'installer un programme soi-même, demande d'abord l'accord de cette équipe.

**2.3 npm et le registre qu'il utilise :**
```sh
node --version && npm --version && npm config get registry
```
Tu dois voir trois lignes :
- une version de Node.js (`v20…` ou plus) ;
- une version de npm ;
- l'adresse du registre, soit `https://registry.npmjs.org/`, soit une adresse Artifactory de ton entreprise.

Si `node` ou `npm` est introuvable, arrête-toi : il faut Node.js sur la machine, et c'est à l'équipe qui gère l'environnement de l'installer.

**2.4 Comment la 1.19 est lancée et sur quel port :**
```sh
ps -eo args | grep -i '[o]pencode'
```
Tu dois voir la commande qui fait tourner ta 1.19, par exemple `opencode web --hostname 0.0.0.0 --port 4096`. Note :
- **le port**, le nombre après `--port`. S'il n'y en a pas, prends le nombre après les deux-points dans l'adresse de ton navigateur (étape 2.5) ;
- **si le port 4097 est libre** : il ne doit apparaître dans aucune ligne. S'il apparaît, choisis un autre numéro libre (par exemple `4098`) et utilise-le partout où ce guide écrit `4097`.

**2.5 L'adresse de la 1.19 dans ton navigateur.** Regarde ce qui est écrit dans la barre d'adresse quand tu utilises OpenCode aujourd'hui, et retiens dans quel cas tu es :
- **Cas A** : une adresse du type `http://<nom ou IP de la machine>:4096`. Tu ouvriras la v2 de la même façon, avec `:4097`.
- **Cas B** : une adresse d'une plateforme (un nom de domaine de ton entreprise sans numéro de port, une page d'environnement de travail). Il faudra exposer le port 4097 avec ta plateforme, ou passer par un tunnel SSH (étape 7).

## Étape 3 — Sauvegarder

**Pourquoi.** Une assurance : la v2 ne touche pas à ces dossiers, mais une copie ne coûte rien.

```sh
cp -r ~/.config/opencode ~/opencode-config-1.19 && cp -r ~/.local/share/opencode ~/opencode-data-1.19 && ls -d ~/opencode-config-1.19 ~/opencode-data-1.19
```

**Ce que tu dois voir.** Les deux chemins des copies, sur deux lignes.

**Si tu vois `No such file or directory`.** Ton OpenCode 1.19 range ses données ailleurs. Envoie-moi la ligne d'erreur avant de continuer.

## Étape 4 — Télécharger et installer OpenCode v2

**D'où vient la v2.** C'est le paquet npm **`@opencode/cli`**, version **2.1.2** (sortie le 21 octobre 2026), publié par l'équipe d'OpenCode. npm le télécharge depuis ton registre (étape 2.3) avec, automatiquement, le programme compilé pour ta machine (par exemple `@opencode/cli-linux-x64`). Tu n'as rien à chercher sur le site d'OpenCode.

N'utilise ni la commande `curl … | bash` du site d'OpenCode, ni `brew` : elles téléchargent et exécutent un script, ce que ton environnement interdit.

**Pourquoi un dossier à part.** Ce paquet fournit lui aussi une commande `opencode`. Installé dans `~/oc2/cli`, il ne remplace pas celle de ta 1.19. Il ne demande pas non plus de droits administrateur.

**Quoi taper :**
```sh
mkdir -p ~/oc2/cli && npm install --prefix ~/oc2/cli @opencode/cli@2.1.2
```

**Ce que tu dois voir.** Après quelques secondes, une ligne du type `added 5 packages in 14s`.

Vérifie ensuite :
```sh
~/oc2/cli/node_modules/.bin/opencode2 --version && opencode --version
```
Tu dois voir **deux** versions : `opencode v2.1.2` (la nouvelle) puis ta version 1.19 (l'ancienne, inchangée).

**Si ça ne marche pas :**

| Message | Cause | Ce que tu fais |
|---|---|---|
| `E404` ou `404 Not Found` sur `@opencode/cli` | ton registre (Artifactory) ne connaît pas ce paquet | demande à l'équipe Artifactory d'autoriser depuis registry.npmjs.org les paquets `@opencode/cli` et `@opencode/cli-linux-x64` (et ses variantes `-baseline`, `-musl`), version 2.1.2 |
| `ETIMEDOUT`, `ECONNREFUSED`, `UNABLE_TO_GET_ISSUER_CERT` | la machine n'atteint pas le registre | même problème qu'une installation npm qui échoue chez toi d'habitude : vois avec l'équipe qui gère l'environnement |
| `EACCES` | droits sur un dossier | vérifie que la commande contient bien `--prefix ~/oc2/cli` ; n'utilise jamais `sudo` |
| `opencode2: not found` après l'installation | l'installation a échoué plus haut | relis le message d'erreur de `npm install` |

## Étape 5 — Préparer la configuration de la v2

**Pourquoi.** La v2 lit sa configuration dans `~/oc2/config/opencode`. Un script du pack la prépare pour toi à partir de ta configuration 1.19, sans la modifier :
- il copie `opencode.json` en y mettant les règles du pack, et garde tes réglages du modèle (`provider`, `model`), de tes serveurs MCP (`mcp`) et tes références ;
- il copie les agents, les commandes, les skills et le plugin `openrd-pack.js` ;
- il crée `AGENTS.md` à partir de celui du pack, en reprenant tes sections « Daily » et « Release groups » ;
- il met à jour les scripts du pack dans `~/.config/opencode/scripts` : ce sont les mêmes que ceux de la 1.19, plus `fortify.sh`.

Le script n'affiche jamais le contenu de ta configuration, qui peut contenir des clés : seulement le nom des sections.

**Quoi taper.** Remplace `~/OpenRDCode` par le chemin de ton clone du pack s'il est ailleurs :
```sh
cd ~/OpenRDCode && git pull && node opencode-v2/tools/prepare-v2.mjs
```

**Ce que tu dois voir** (tes noms de sections peuvent différer) :
```
CONFIG: /home/dev/oc2/config/opencode/opencode.json — agent and permission from the pack; kept from 1.19: $schema, provider, model, mcp, …
PACK: 7 agents, 7 commands, 16 skills, plugins: openrd-pack.js
AGENTS.md: from the pack, with your sections « Daily » and « Release groups »
SCRIPTS: 24 scripts in /home/dev/.config/opencode/scripts (fortify.sh included)
DONE: the configuration of OpenCode 1.19 was only read, never changed
```

Vérifie dans la ligne `CONFIG:` que `provider`, `model` et `mcp` figurent après « kept from 1.19 ». Sans eux, la v2 n'aura ni modèle, ni Jira, GitLab, Sonar et Fortify.

**Si tu vois `STOP:`**, la ligne dit pourquoi :
- `no opencode.json in …` : ta configuration 1.19 n'est pas dans `~/.config/opencode` ; envoie-moi la ligne ;
- `run it from the clone of the pack` : la commande n'a pas été lancée depuis le clone du pack ;
- `cannot read …` : ton `opencode.json` contient une erreur de syntaxe.

Si la ligne `AGENTS.md:` dit qu'aucune section n'a été trouvée, ouvre `~/oc2/config/opencode/AGENTS.md` et remplis à la main les sections « Daily » et « Release groups ».

Ce script peut être relancé sans risque : il garde chaque fois une copie de l'ancien `opencode.json` de la v2 (ligne `SAVED:`).

## Étape 6 — Démarrer la v2

**Pourquoi.** Lancer le serveur de la v2 sur son propre port, avec un mot de passe, sans arrêter la 1.19.

**Le mot de passe.** La v2 en exige un, pour que personne d'autre ne puisse utiliser ton OpenCode. Choisis-en un nouveau : ni ton mot de passe d'entreprise, ni celui d'un autre service. Le script te le demande sans l'afficher, et il n'est jamais écrit dans une commande ni dans l'historique du terminal. Tu le retaperas dans le navigateur à l'étape 7.

**Quoi taper.** Dans le cas A de l'étape 2.5 :
```sh
cd ~ && sh ~/OpenRDCode/opencode-v2/tools/start-v2.sh 4097
```
Dans le cas B, si tu passeras par un tunnel SSH (étape 7) :
```sh
cd ~ && sh ~/OpenRDCode/opencode-v2/tools/start-v2.sh 4097 127.0.0.1
```

**Ce que tu dois voir :**
```
Password of OpenCode v2 (typed, not shown):
opencode v2.1.2 starts on port 4097; the log goes to ~/oc2/serve.log. Ctrl+C stops it.
server listening on http://0.0.0.0:4097
```
Après la ligne `server listening`, **le terminal reste occupé** : c'est normal, c'est le serveur qui tourne. Laisse cette fenêtre ouverte et ouvre un **deuxième terminal** pour les commandes suivantes. Pour arrêter la v2 : `Ctrl+C` dans cette fenêtre.

**Si tu vois `STOP:`** : la ligne dit quelle étape refaire (4 ou 5).

**Si un message parle d'un port déjà utilisé** (`address already in use`, `EADDRINUSE`) : relance avec un autre numéro, par exemple `4098`.

## Étape 7 — Ouvrir la v2 dans ton navigateur et te connecter

**7.1 L'adresse :**
- **Cas A** : la même adresse que ta 1.19, avec `4097` à la place de son port. Par exemple, `http://machine:4096` devient `http://machine:4097`.
- **Cas B, avec le tunnel SSH** : dans un terminal **sur ton Mac**, tape la commande ci-dessous. Remplace `<utilisateur>` et `<machine>` par ce qu'affichait l'étape 1.
```sh
ssh -N -L 4097:127.0.0.1:4097 <utilisateur>@<machine>
```
Elle ne rend pas la main : c'est normal, laisse-la ouverte pendant que tu utilises la v2. Ouvre ensuite `http://localhost:4097` dans ton navigateur.
- **Cas B, avec ta plateforme** : si ta plateforme sait exposer un port (« port forwarding »), expose le port 4097 et ouvre l'adresse qu'elle te donne.

**7.2 La connexion.** C'est ce que j'ai vu en ouvrant la v2.1.2 dans un navigateur :
1. Une page **« Se connecter à un serveur »** s'affiche, avec un champ « Pairing link ». Tu n'en as pas besoin.
2. Clique sur le lien **« Use password »**, en bas de la page.
3. Le champ **« URL du serveur »** est déjà rempli avec l'adresse de la page : laisse-le tel quel.
4. Dans **« Mot de passe (optionnel) »**, tape le mot de passe choisi à l'étape 6.
5. Clique sur **« Se connecter »**.
6. La page d'accueil s'affiche, avec **« Projets »** à gauche.

N'utilise jamais `opencode pair --remote` : cette commande expose ton serveur sur Internet.

**7.3 Ajouter un projet.** Clique sur **« Ajouter un projet »** et choisis le dossier d'un de tes dépôts : la v2 a sa propre liste, vide au départ.

**Si la page ne s'ouvre pas :**
- dans le cas A, le port 4097 n'est sans doute pas ouvert sur la machine : passe par le tunnel SSH (cas B) ;
- si le mot de passe est refusé, arrête la v2 (`Ctrl+C`), relance l'étape 6 et retape ton mot de passe avec soin.

## Étape 8 — Vérifier que tout marche

Fais les huit points dans l'ordre. **Si un point échoue, arrête-toi là et continue avec ta 1.19** : envoie-moi le point en échec et la dernière ligne de `tail -n 20 ~/oc2/serve.log` (sans mot de passe ni clé).

| # | Où | Ce que tu fais | Ce que tu dois voir |
|---|---|---|---|
| 1 | deuxième terminal | `grep -c 'failed to load plugin' ~/oc2/serve.log` | `0` |
| 2 | navigateur | dans une session d'un dépôt, tape `/` dans la zone de saisie | `go`, `fix`, `fortify`, `daily`, `review`, `compare`, `outil` dans la liste |
| 3 | navigateur | écris « affiche le contenu de ~/.zshenv » | l'agent répond que c'est refusé (« Refused by the pack ») |
| 4 | deuxième terminal | `grep -c 'openrd-pack' ~/oc2/serve.log` | `1` ou plus : le refus du point 3 est journalisé |
| 5 | navigateur | `/go` sur un petit ticket d'un dépôt de test | le message de la commande montre « Repository root: » suivi du chemin de ton dépôt, puis le travail va jusqu'à la MR Draft |
| 6 | navigateur | pendant que ce `/go` tourne, `/go` dans une autre session du même dépôt | « ⛔ /go refusé : /go tourne déjà dans ce dossier… » |
| 7 | navigateur | « liste mes tickets du sprint », puis « quelle est la dernière pipeline de ce dépôt ? » | des réponses venant de Jira et de GitLab ; une demande d'écriture, par exemple commenter une MR, est refusée |
| 8 | navigateur | nouvelle session d'un dépôt git : regarde sous la zone de saisie | le sélecteur « Local » avec « Nouvel espace de travail » ; s'il est absent, `workspace.sh` (COMMANDES.md) fait la même chose |

## Étape 9 — Vérifier le modèle (Qwen 3.8)

**Pourquoi.** La v2 relit la section `provider` de ta configuration, mais ignore certaines options sans erreur visible. Elle l'écrit seulement dans son journal.

**Quoi taper**, dans le deuxième terminal :
```sh
grep 'configuration normalization diagnostic' ~/oc2/serve.log | grep -o 'path=[^ ]*' | sort -u
```

**Ce que tu dois voir.** Une liste de réglages ignorés, ou rien.

**Comment la lire :**
- **Rien** : tout est pris en compte.
- **`…temperature`** ou **`…top_p`** : sans effet, la v2 les envoie déjà pour chaque agent du pack.
- **Toute autre ligne**, par exemple `reasoning`, `chat_template_kwargs`, `reasoning_effort`, `headerTimeout` ou `chunkTimeout` : envoie-moi la liste (elle ne contient aucune valeur) et je traduis ces réglages au format v2. En attendant, le modèle répond, mais peut-être sans son mode de raisonnement ou avec d'autres délais.

Refais ensuite le test habituel de la section « Qwen 3.8 » de `COMMANDES.md`.

## Étape 10 — Utiliser la v2 au quotidien

Tant que tu valides la v2, garde les deux versions côte à côte : la 1.19 sur son port, la v2 sur 4097. Pour démarrer la v2 chaque jour :
```sh
cd ~ && sh ~/OpenRDCode/opencode-v2/tools/start-v2.sh 4097
```
Ajoute `127.0.0.1` à la fin dans le cas B, et relance ton tunnel SSH sur ton Mac.

**Règles de cohabitation :**
- **Jamais de `/go`, `/fix` ou `/fortify` sur le même dépôt dans les deux versions en même temps.** Chacune protège ses dossiers, mais elles ne se voient pas l'une l'autre.
- **Les sessions ne sont pas partagées.** Celles de la 1.19 restent dans la 1.19. Les fiches ticket, elles, sont dans le `.git` de chaque dépôt : les deux versions les voient.
- **Mettre à jour le pack** : `cd ~/OpenRDCode && git pull && node opencode-v2/tools/prepare-v2.mjs`, puis redémarrer la v2.
- **Passer à une version plus récente d'OpenCode v2** : n'y touche pas sans me demander. Le pack est vérifié avec la 2.1.2, et la 2.1.0 a changé le fonctionnement des plugins.

Quand la v2 t'a donné satisfaction plusieurs semaines, tu peux simplement arrêter de lancer la 1.19. Rien d'autre à faire : ne la désinstalle pas, c'est ton retour arrière.

## Étape 11 — Revenir à la 1.19

**Tant que tu n'as rien désinstallé** (c'est le cas si tu as suivi ce guide) :
1. Arrête la v2 : `Ctrl+C` dans son terminal.
2. Ouvre l'adresse de ta 1.19, comme avant. Si tu l'avais arrêtée, relance-la avec la commande notée à l'étape 2.4.

C'est tout : sa configuration et ses sessions n'ont jamais été modifiées.

**Le seul fichier partagé** : les scripts de `~/.config/opencode/scripts`, mis à jour à l'étape 5. Ce sont ceux de la 1.19, plus `fortify.sh` : la 1.19 fonctionne avec. Pour remettre exactement les anciens :
```sh
rm -rf ~/.config/opencode/scripts && cp -r ~/opencode-config-1.19/scripts ~/.config/opencode/scripts
```

**Si un jour tu as désinstallé la 1.19**, une copie ne suffit pas : il faut aussi réinstaller le programme. Cette commande réinstalle la version notée à l'étape 2.1 et remet la configuration et les données sauvegardées à l'étape 3 :
```sh
npm install -g opencode-ai@$(sed 's/[^0-9.]//g' ~/opencode-version-1.19.txt) && rm -rf ~/.config/opencode ~/.local/share/opencode && cp -r ~/opencode-config-1.19 ~/.config/opencode && cp -r ~/opencode-data-1.19 ~/.local/share/opencode && opencode --version
```
La dernière ligne doit afficher ta version 1.19.

## Étape 12 — Dépannage

| Ce que tu vois | Pourquoi | Ce que tu fais |
|---|---|---|
| `opencode2: not found` | la v2 n'est pas installée dans `~/oc2/cli` | refais l'étape 4 |
| `STOP: no configuration for OpenCode v2 yet` | l'étape 5 n'a pas été faite | refais l'étape 5 |
| `address already in use` ou `EADDRINUSE` | le port est pris | un autre port : `start-v2.sh 4098` |
| La page du navigateur ne répond pas | le port n'est pas joignable depuis ton poste | tunnel SSH (étape 7, cas B) |
| « Impossible de se connecter. Vérifiez l'adresse et le mot de passe du serveur » | mot de passe différent de celui de l'étape 6 | redémarre la v2 et retape le mot de passe |
| Point 1 de l'étape 8 > 0 | un plugin n'a pas été chargé | `ls ~/oc2/config/opencode/plugins` doit montrer `openrd-pack.js` seul ; sinon, refais l'étape 5 |
| Aucune commande `/go` dans la liste | les commandes du pack n'ont pas été copiées | refais l'étape 5, puis redémarre la v2 |
| Pas de réponse de Jira, GitLab, etc. | la section `mcp` n'a pas été reprise | la ligne `CONFIG:` de l'étape 5 doit contenir `mcp` |
| L'agent ne répond pas du tout | modèle mal configuré | étape 9 |
| `/go` reste refusé alors que rien ne tourne | le verrou attend la fin d'un tour qu'il n'a pas vue | redémarre la v2 (`Ctrl+C` puis étape 6) |
| Un processus `opencode … serve --service` tourne en plus | une autre commande `opencode2` qu'à l'étape 6 a lancé le service d'arrière-plan de la v2 | `~/oc2/cli/node_modules/.bin/opencode2 service stop` |

## Étape 13 — Ce qui ne change pas, ce qui change

**Ne change pas** :
- `/go`, `/fix`, `/daily`, `/review`, `/compare`, `/outil` ;
- tes fiches ticket ;
- les règles de sécurité des agents, y compris « un seul `/go`, `/fix` ou `/fortify` à la fois par dossier ».

**Change :**

| Avec la 1.19 | Avec la v2 |
|---|---|
| le message d'une commande montre une ligne courte | il montre aussi l'état du dépôt (la v2 n'a pas de partie cachée dans un message) |
| le titre d'une session montre l'avancement et ✅ / ⛔ | le titre est celui d'OpenCode (section 14) |
| un QCM qui propose une commande la lance tout seul | tape la commande proposée |
| `/go … comme dans ~/repos/old-api` rend ce dossier lisible | déclare ce dossier dans `references` d'`opencode.json` |
| chaque skill était aussi une commande `/` | seul `/outil` reste |
| plusieurs tickets d'un dépôt : `workspace.sh` | le sélecteur « Nouvel espace de travail » (étape 8, point 8) |
| — | **`/fortify`** : voir le document « Fortify par lot avec test-guardian », et la section « Fortify » de `COMMANDES.md` pour ses prérequis (coverlet) |

## Étape 14 — Ce qui n'est pas porté, et pourquoi

| Fonction | Pourquoi | En attendant |
|---|---|---|
| Ligne courte du message d'une commande | la v2 n'a pas de partie cachée dans un message | l'état du dépôt est visible |
| Commande lancée par un choix de QCM | la v2.1.2 ne documente pas comment un plugin lit une réponse ou lance une commande : je n'ai pas pu le vérifier | tape la commande |
| Avancement et ✅ / ⛔ dans les titres | même raison pour la lecture des messages et le renommage | regarde la session |
| Dossiers nommés dans un message | la v2 ne dit pas au plugin si un texte vient de toi ou d'un agent : ouvrir aux deux laisserait un agent rendre lisible un dossier de secrets | `references` dans `opencode.json` |

Tout ce qui protège est porté et vérifié dans le vrai OpenCode v2.1.2 :
- les refus des secrets et des dumps d'environnement ;
- les agents limités à leur dépôt ;
- un seul pilote par dossier ;
- les délais longs ;
- les scripts des commandes lancés dans le bon dépôt ;
- le refus des outils v2 qui déplacent une session ou créent un worktree.

Les vérifications automatiques passent :
- plugin : 477 sur 477 ;
- permissions : 1 753 cas sur 1 753 ;
- 30 fichiers d'agents, de commandes et de skills validés ;
- `shellcheck` sur tous les scripts.

## Étape 15 — Les fichiers de `opencode-v2/`

- **Nouveaux par rapport à `v2/`** :
  - `plugins/openrd-pack.js` (remplace `compact-commands.js`) ;
  - `commands/fortify.md`, `agents/test-guardian.md`, `scripts/fortify.sh` ;
  - `tools/prepare-v2.mjs` (étape 5) et `tools/start-v2.sh` (étape 6) ;
  - ce guide et `ANALYSE.md`.
- **Modifiés** :
  - les agents (vocabulaire des sous-agents, règles régénérées), `commands/go.md`, `commands/fix.md`, `AGENTS.global.md` ;
  - `opencode.snippet.json` et les outils de test ;
  - `COMMANDES.md` et `README.md`.
- **Identiques** : les autres scripts.
