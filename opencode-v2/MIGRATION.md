# Passer d'OpenCode 1.19 à OpenCode v2, pas à pas

Ce guide part de zéro. Chaque étape dit **pourquoi** on la fait, **quoi taper**, **ce que tu dois voir**, et **quoi faire si ce n'est pas ce que tu vois**. Ne saute aucune étape et ne passe à la suivante que si la précédente donne le résultat attendu.

Le principe : OpenCode v2 s'installe **à côté** de ta version 1.19, dans son propre dossier `~/oc2`, sur un autre port. La 1.19 continue de tourner comme avant pendant tout l'essai : la v2 n'écrit rien dans ses dossiers, à une exception près, le script `fortify.sh` que tu ajoutes toi-même au dossier des scripts du pack (étape 5.4). Revenir en arrière consiste à rouvrir l'adresse de la 1.19.

**La v2 a déjà remplacé ta 1.19** (par exemple avec une procédure interne qui fait `npm install -g @opencode/cli`) ? Va directement à l'**annexe A**, à la fin de ce guide.

Tout ce guide a été rejoué de bout en bout sur une machine de test, avec un utilisateur `coder`, zsh, une configuration 1.19 du pack, et le vrai OpenCode v2.1.2. Les résultats « Ce que tu dois voir » viennent de ce test.

## Les règles de ce guide

- **Tu ne lances aucun script.** Tout se fait avec des commandes à taper une par une (`mkdir`, `cp`, `npm pack`, `tar`, `sha256sum`, `grep`…), et avec des fichiers que tu crées toi-même en y collant le contenu copié depuis GitHub, comme tu le fais déjà.
- **Rien ne s'installe tout seul.** OpenCode v2 est téléchargé comme une archive, sans que rien ne s'exécute, puis extrait. La commande habituelle, `npm install`, lancerait le script d'installation du paquet : ce guide ne l'utilise jamais.
- **Chaque fichier collé est vérifié** par son empreinte (étape 5) : la moindre différence avec GitHub se voit.
- Les scripts du pack (le dossier `scripts`) sont lancés par les agents d'OpenCode pendant `/go`, `/fix` ou `/fortify`, comme avec ta 1.19. Tu ne les lances pas toi-même.

## Copier un fichier depuis GitHub

1. Ouvre le fichier sur la page GitHub du pack : `https://github.com/RabieDerouiche/OpenRDCode`, dossier `opencode-v2/`.
2. Clique sur le bouton **Raw** (en haut à droite du fichier) : la page n'affiche plus que le texte brut.
3. Ctrl+A pour tout sélectionner, puis Ctrl+C pour copier.
4. Crée le fichier vide au chemin indiqué par le guide, colle (Ctrl+V), enregistre. L'encodage doit rester UTF-8 (le réglage par défaut des éditeurs) : plusieurs fichiers contiennent des accents.

Copie toujours depuis **Raw** : la page normale de GitHub peut ajouter ou couper des caractères.

**Le dernier retour à la ligne.** Le navigateur ne copie pas le retour à la ligne qui termine un fichier (vérifié avec Chrome). vim et nano le remettent en enregistrant, VS Code non. Si ton éditeur est VS Code, active ce réglage une fois pour toutes : Paramètres (Ctrl+,), cherche « insert final newline » et coche **Files: Insert Final Newline**. Sans lui, la vérification de l'étape 5 signale chaque fichier collé.

Durée : environ une heure la première fois, surtout pour coller les fichiers.

## Sommaire

| Étape | Ce que tu fais | Durée |
|---|---|---|
| 0 | Comprendre les mots utilisés | 3 min |
| 1 | Ouvrir un terminal sur la machine d'OpenCode | 2 min |
| 2 | Faire l'état des lieux de ton installation actuelle | 5 min |
| 3 | Sauvegarder | 2 min |
| 4 | Télécharger OpenCode v2 | 5 min |
| 5 | Préparer la configuration de la v2 | 30 min |
| 6 | Démarrer la v2 | 3 min |
| 7 | L'ouvrir dans ton navigateur et te connecter | 5 min |
| 8 | Vérifier que tout marche | 15 min |
| 9 | Vérifier le modèle (Qwen) | 5 min |
| 10 | Utiliser la v2 au quotidien, mettre à jour le pack | — |
| 11 | Revenir à la 1.19 | 1 min |
| 12 | Dépannage | — |

Les étapes 13 à 15 sont des annexes : ce qui change, ce qui n'est pas porté, et les fichiers du pack. L'annexe A remplace les étapes 3 à 6 quand la v2 est déjà installée à la place de la 1.19.

## Étape 0 — Les mots utilisés

- **Machine d'OpenCode** : l'ordinateur distant où tourne OpenCode, celui dont tu ouvres l'interface web dans ton navigateur. Ce n'est pas ton Mac.
- **Terminal** : une fenêtre où l'on tape des commandes sur cette machine. Chaque commande de ce guide se tape dans un terminal **de la machine d'OpenCode**, sauf quand il est écrit « sur ton Mac ».
- **CLI** (« command line interface ») : un programme qu'on lance en tapant son nom dans un terminal. OpenCode est une CLI : la commande `opencode` démarre son serveur.
- **npm** : le gestionnaire de paquets de Node.js. Il télécharge des programmes depuis un **registre npm**, un dépôt en ligne de paquets : `registry.npmjs.org`, ou le miroir Artifactory de ton entreprise.
- **Paquet** : un programme publié sur un registre npm. OpenCode 1.19 est le paquet `opencode-ai`. OpenCode v2 est le paquet `@opencode/cli`, publié par l'équipe d'OpenCode (son code est sur GitHub, projet `anomalyco/opencode`), avec un paquet par type de machine qui contient le programme lui-même, par exemple **`@opencode/cli-linux-x64`**. C'est ce dernier qu'on télécharge.
- **Archive** (fichier `.tgz`) : un fichier qui en contient d'autres, compressés. La commande `tar` les extrait.
- **Empreinte** : une suite de chiffres et de lettres calculée à partir du contenu d'un fichier, par `sha256sum` ou `sha512sum`. Deux fichiers ont la même empreinte seulement s'ils sont identiques à l'octet près.
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

**Pourquoi.** Savoir comment ta 1.19 est installée et lancée, pour ne rien casser et pouvoir revenir en arrière.

Tape ces commandes une par une. Chaque bloc dit ce que tu dois noter.

**2.1 La version de la 1.19.** La commande l'enregistre aussi dans un fichier, pour pouvoir la retrouver à l'identique un jour :
```sh
opencode --version | tee ~/opencode-version-1.19.txt
```
Tu dois voir un numéro du type `1.19.0`. Note-le.

**2.2 Comment elle est installée :**
```sh
npm ls -g --depth=0 2>/dev/null | grep -i opencode
```
Deux réponses possibles :
- **Une ligne `opencode-ai@1.19.x`** : la 1.19 a été installée avec npm.
- **Rien** : elle a été installée autrement, par exemple par l'équipe qui gère ton environnement.

Dans les deux cas tu peux suivre ce guide : la v2 se télécharge dans ton dossier personnel et ne touche pas à la 1.19. Si ton entreprise interdit de télécharger un programme soi-même, demande d'abord l'accord de cette équipe.

**2.3 npm et le registre qu'il utilise.** npm sert seulement à télécharger la v2 :
```sh
node --version && npm --version && npm config get registry
```
Tu dois voir trois lignes :
- une version de Node.js ;
- une version de npm ;
- l'adresse du registre, soit `https://registry.npmjs.org/`, soit une adresse Artifactory de ton entreprise.

Si `node` ou `npm` est introuvable, arrête-toi : c'est à l'équipe qui gère l'environnement de les installer.

**2.4 Comment la 1.19 est lancée et sur quel port :**
```sh
ps -eo args | grep -i '[o]pencode'
```
Tu dois voir la commande qui fait tourner ta 1.19, par exemple `opencode web --hostname 0.0.0.0 --port 4096`. Note :
- **la commande entière**, pour pouvoir relancer la 1.19 un jour ;
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

## Étape 4 — Télécharger OpenCode v2

**D'où vient la v2.** Du registre npm, où l'équipe d'OpenCode publie chaque version. Le programme pour une machine Linux classique est dans le paquet **`@opencode/cli-linux-x64`**, version **2.1.2**, publiée le 21 octobre 2026. Ce paquet contient un seul programme compilé, `bin/opencode`, et aucun script. Tu n'as rien à chercher sur le site d'OpenCode : tout ce qu'il faut est dans ce guide.

**Comment.** `npm pack` télécharge l'archive d'un paquet dans le dossier courant, sans l'installer et sans rien exécuter ; avec `--ignore-scripts`, npm n'a même pas le droit de lancer un script. `tar` extrait ensuite le programme. N'utilise ni `npm install` (il lancerait le script d'installation du paquet `@opencode/cli`), ni `curl … | bash`, ni `brew`.

**4.1 Le bon paquet pour ta machine.** Tape ces trois commandes :
```sh
uname -m
```
```sh
grep -c avx2 /proc/cpuinfo
```
```sh
ldd --version 2>&1 | head -n 1
```
Puis lis le tableau ligne par ligne et garde la première ligne qui correspond :

| Première commande | Deuxième | Troisième | Paquet à prendre |
|---|---|---|---|
| `aarch64` | — | contient `musl` | `@opencode/cli-linux-arm64-musl` |
| `aarch64` | — | autre chose | `@opencode/cli-linux-arm64` |
| `x86_64` | `0` | contient `musl` | `@opencode/cli-linux-x64-baseline-musl` |
| `x86_64` | `0` | autre chose | `@opencode/cli-linux-x64-baseline` |
| `x86_64` | plus que `0` | contient `musl` | `@opencode/cli-linux-x64-musl` |
| `x86_64` | plus que `0` | autre chose (par exemple `ldd (Ubuntu GLIBC 2.39…)`) | **`@opencode/cli-linux-x64`**, le cas le plus courant |

La suite du guide écrit `@opencode/cli-linux-x64` : si ton paquet est un autre, remplace-le, ainsi que le nom de fichier `opencode-cli-linux-x64-2.1.2.tgz` par celui que `npm pack` affiche.

**4.2 Télécharger :**
```sh
mkdir -p ~/oc2/cli && cd ~/oc2/cli && npm pack --ignore-scripts @opencode/cli-linux-x64@2.1.2
```
**Ce que tu dois voir** : des lignes qui commencent par `npm notice`, dont un bloc `Tarball Details` avec `version: 2.1.2` et `package size: 99.0 MB`, puis, seul sur sa ligne, le nom du fichier téléchargé : `opencode-cli-linux-x64-2.1.2.tgz`.

npm peut ajouter « New major version of npm available! … To update run: npm install -g npm@… » : ignore ce message et ne lance pas cette commande.

**4.3 Vérifier l'empreinte de l'archive.** npm vérifie déjà l'archive avec l'empreinte que lui donne ton registre. Cette commande la compare en plus à l'empreinte publiée par le registre officiel `registry.npmjs.org`, que j'ai relevée et écrite ici : si ton miroir servait autre chose, tu le verrais.
```sh
cd ~/oc2/cli && echo "3bcffc253f123663117839a9603b26d382a692b410d9dcda2a06b0d3acc2a147e1e74011187b39f04eb30a1d7a18853210bf1a6eb7527b6ebc2b9fc4c44f3d1b  opencode-cli-linux-x64-2.1.2.tgz" | sha512sum -c
```
**Ce que tu dois voir** : `opencode-cli-linux-x64-2.1.2.tgz: OK`.

Avec `FAILED` à la place de `OK` : arrête-toi, supprime l'archive (`rm ~/oc2/cli/*.tgz`) et envoie-moi la ligne. Ne va pas plus loin.

Pour un autre paquet de l'étape 4.1, la ligne à taper dans le dossier `~/oc2/cli` (copie seulement celle de ton paquet) :
```sh
echo "ad528a681cc3ba7e1eb901f4fd3ef9d8359727aa346ffbb5d419dc4d361218181e915ce92b7e862630632877a0b73a94e532dd0131b8d2e490c6729a28ab2dc0  opencode-cli-linux-x64-baseline-2.1.2.tgz" | sha512sum -c
echo "886825eac87af06a0a14d779aecd48fe4ddebcc20ae9dafb89c2f9f5b810c996c1ec5a0e44e13e049a2cdec8793d50243d721a45d148183a0e44b332efdc932a  opencode-cli-linux-x64-musl-2.1.2.tgz" | sha512sum -c
echo "78577f479e93654e786bc5f8efd91cd812b5303e8fb67f6b433545cd03b52dc549e26f45188556d879f6685cb5fadb58cae80d766b0d7d33f926d2b52a44b999  opencode-cli-linux-x64-baseline-musl-2.1.2.tgz" | sha512sum -c
echo "dbde0803d4b5b17380cce0513cc72716e6295e515e51a2939694e4d1aed332fb9cedc25b7d2e76a684f0dc0948bbbc9c6e7f131a64e68f6ece3b1b0c98108b12  opencode-cli-linux-arm64-2.1.2.tgz" | sha512sum -c
echo "03db37ae3f8a6f544d452cd8454c5a5ec86e75196265b9cd7e0e7e55f2949d518049ed9f6d31a641cc00c4fb0615e4d8b754229f3e663a112d1c15e5e6f87b96  opencode-cli-linux-arm64-musl-2.1.2.tgz" | sha512sum -c
```

**4.4 Extraire le programme :**
```sh
cd ~/oc2/cli && tar -xzf opencode-cli-linux-x64-2.1.2.tgz && ls -l package/bin/opencode
```
**Ce que tu dois voir** : une ligne qui commence par `-rwxr-xr-x`, avec la taille `213870048` (environ 214 Mo, pour `cli-linux-x64`), et qui finit par `package/bin/opencode`. La date affichée, le 26 octobre 1985, est normale : npm met cette date à tous les fichiers de ses archives.

L'archive ne sert plus :
```sh
rm ~/oc2/cli/opencode-cli-linux-x64-2.1.2.tgz
```

Dans tout ce guide, **le programme de la v2 est `~/oc2/cli/package/bin/opencode`**. Le simple mot `opencode` reste ta 1.19.

**Ne lance pas encore ce programme**, même pour voir sa version. Sans les réglages de l'étape 6, la v2 créerait ses dossiers et son journal dans ceux de la 1.19 : vérifié, un simple `--version` écrit dans `~/.local/share/opencode/log/`. Sa version se vérifie à l'étape 6.

**Si ça ne marche pas :**

| Message | Cause | Ce que tu fais |
|---|---|---|
| `E404` ou `404 Not Found` | ton registre (Artifactory) ne connaît pas ce paquet | demande à l'équipe Artifactory d'autoriser, depuis registry.npmjs.org, le paquet de l'étape 4.1 en version 2.1.2 |
| `ETIMEDOUT`, `ECONNREFUSED`, `UNABLE_TO_GET_ISSUER_CERT` | la machine n'atteint pas le registre | le même souci qu'un `npm` qui échoue chez toi d'habitude : vois avec l'équipe qui gère l'environnement |
| `No space left on device` | il faut environ 320 Mo libres (archive et programme) | libère de la place, puis recommence |

## Étape 5 — Préparer la configuration de la v2

**Pourquoi.** La v2 lira sa configuration dans `~/oc2/config/opencode`, à part de la 1.19. On y recopie d'abord ta configuration 1.19 avec `cp`. Puis tu ne colles depuis GitHub que les fichiers qui manquent ou qui ont changé : c'est une vérification par empreintes qui te dit lesquels.

**5.1 Les dossiers, et la copie de tes agents, commandes et skills :**
```sh
mkdir -p ~/oc2/config/opencode/plugins ~/oc2/data ~/oc2/cache ~/oc2/state && cp -r ~/.config/opencode/agents ~/.config/opencode/commands ~/.config/opencode/skills ~/oc2/config/opencode/ && ls ~/oc2/config/opencode
```
**Ce que tu dois voir** : `agents  commands  plugins  skills`.

Ne copie pas le dossier `plugins` de la 1.19 : son `compact-commands.js` ne fonctionne pas avec la v2. Ne copie jamais non plus le dossier `tools` du pack.

**5.2 Les deux listes d'empreintes.** Crée ces deux fichiers en collant leur contenu depuis GitHub :

| Fichier à créer | À copier depuis GitHub |
|---|---|
| `~/oc2/CHECKSUMS-config.txt` | `opencode-v2/CHECKSUMS-config.txt` |
| `~/oc2/CHECKSUMS-scripts.txt` | `opencode-v2/CHECKSUMS-scripts.txt` |

Chaque ligne contient l'empreinte d'un fichier du pack et son chemin.

**5.3 Ce qui manque ou a changé dans la configuration :**
```sh
cd ~/oc2/config/opencode && sha256sum --quiet --strict -c ~/oc2/CHECKSUMS-config.txt 2>/dev/null && echo "OK : la configuration est identique à GitHub"
```
Chaque ligne affichée est un fichier à coller depuis GitHub, au même chemin sous `opencode-v2/` :
- `FAILED` : le fichier existe mais il diffère : remplace tout son contenu ;
- `FAILED open or read` : il n'existe pas encore : crée-le.

La première fois, avec un pack 1.19 à jour, tu dois voir ces 14 lignes :
```text
agents/analyst.md: FAILED
agents/checker.md: FAILED
agents/coder.md: FAILED
agents/debugger.md: FAILED
agents/doc-writer.md: FAILED
agents/pilot.md: FAILED
agents/test-guardian.md: FAILED open or read
commands/fix.md: FAILED
commands/fortify.md: FAILED open or read
commands/go.md: FAILED
skills/fortify-remediation/SKILL.md: FAILED
skills/pack-doc/SKILL.md: FAILED
skills/pack-release-notes/SKILL.md: FAILED
plugins/openrd-pack.js: FAILED open or read
```
Si ton pack 1.19 est plus ancien, il y en a plus. Par exemple, `agents/test-guardian.md: FAILED open or read` veut dire : crée `~/oc2/config/opencode/agents/test-guardian.md` et colles-y le contenu de `opencode-v2/agents/test-guardian.md`.

Relance la commande après chaque série de fichiers collés. **Tu as fini quand elle affiche `OK : la configuration est identique à GitHub`.** Si elle n'affiche rien du tout, c'est la liste `CHECKSUMS-config.txt` elle-même qui est mal collée : recrée-la depuis Raw.

**Les fichiers en plus.** La vérification ne regarde que les fichiers du pack. Pour voir le reste :
```sh
ls ~/oc2/config/opencode/agents ~/oc2/config/opencode/commands
```
Tu dois voir, pour les agents : `analyst.md checker.md coder.md debugger.md doc-writer.md pilot.md test-guardian.md` ; pour les commandes : `compare.md daily.md fix.md fortify.md go.md outil.md review.md`. Un autre nom est soit un fichier à toi (garde-le), soit un reste d'un ancien pack : envoie-moi son nom. Dans `skills`, tes skills `pattern-…` sont à toi : ils restent.

**5.4 Les scripts du pack.** Ils restent dans `~/.config/opencode/scripts`, où les commandes et les agents les appellent : ce dossier sert aux deux versions. Ceux de la v2 sont exactement ceux de la 1.19, plus `fortify.sh`.
```sh
cd ~/.config/opencode/scripts && sha256sum --quiet --strict -c ~/oc2/CHECKSUMS-scripts.txt 2>/dev/null && echo "OK : les scripts sont identiques à GitHub"
```
Même lecture qu'en 5.3, avec les fichiers de `opencode-v2/scripts/`. Avec un pack 1.19 à jour, il n'y a qu'une ligne : `fortify.sh: FAILED open or read`. Crée alors `~/.config/opencode/scripts/fortify.sh` avec le contenu de `opencode-v2/scripts/fortify.sh`.

D'autres lignes veulent dire que tes scripts 1.19 ne sont pas les derniers : colle-les aussi. Ce sont les mêmes que ceux du dernier pack 1.19 (`v2/scripts/`, identiques à l'octet près), et ta 1.19 en profite. `diff-guard.sh` contient des tabulations : s'il reste en `FAILED`, c'est que ton éditeur les a remplacées par des espaces.

Tu as fini quand la commande affiche `OK : les scripts sont identiques à GitHub`.

**5.5 `AGENTS.md`.** Il n'est pas dans les listes d'empreintes, parce qu'il contient tes propres sections.
1. Crée `~/oc2/config/opencode/AGENTS.md` en y collant le contenu de `opencode-v2/AGENTS.global.md`.
2. Repère les sections, dans ta 1.19 puis dans le nouveau fichier :
```sh
grep -n '^## ' ~/.config/opencode/AGENTS.md
```
```sh
grep -n '^## ' ~/oc2/config/opencode/AGENTS.md
```
Chaque ligne donne un numéro de ligne et le titre d'une section. Dans le nouveau fichier, tu dois voir notamment `70:## Daily`, `74:## Release groups` et `81:## NuGet / Artifactory`.
3. Dans le nouveau fichier, remplace d'abord la section « Release groups » (de sa ligne `## Release groups` jusqu'à la ligne avant `## NuGet / Artifactory`) par la tienne, copiée dans ta 1.19 de la même façon. Puis la section « Daily » (de `## Daily` jusqu'à la ligne avant `## Release groups`). Dans cet ordre : en commençant par le bas, les numéros de ligne du haut ne bougent pas.
4. Vérifie que les sections sont les mêmes que dans ta 1.19 :
```sh
diff <(grep '^## ' ~/.config/opencode/AGENTS.md) <(grep '^## ' ~/oc2/config/opencode/AGENTS.md) && echo "OK : mêmes sections"
```
Tu dois voir `OK : mêmes sections`. Puis relis tes deux sections :
```sh
sed -n '/^## Daily/,/^## NuGet/p' ~/oc2/config/opencode/AGENTS.md
```
Tu dois voir ta section « Daily », ta section « Release groups », puis la ligne `## NuGet / Artifactory`.

Si tu avais modifié d'autres sections de ton `AGENTS.md` 1.19, refais ces modifications dans le nouveau fichier.

**5.6 `opencode.json`.** Il n'est pas dans les listes non plus : il contient tes réglages. Le nouveau fichier part de la partie du pack, collée depuis GitHub et donc exacte, et tu y ajoutes tes propres sections (modèle, serveurs MCP…), copiées depuis ta 1.19. C'est plus sûr que de chercher la fin des anciennes sections du pack, longues de plusieurs centaines de lignes.

1. Repère tes sections et leurs numéros de ligne :
```sh
grep -n '^  "' ~/.config/opencode/opencode.json
```
Tu vois une ligne par section, par exemple :
```text
2:  "$schema": "https://opencode.ai/config.json",
3:  "provider": {
25:  "model": "<ton provider>/<ton modèle>",
26:  "agent": {
509:  "permission": {
573:  "mcp": {
580:  "shell": "/usr/bin/zsh",
581:  "references": {
587:  "experimental": {
592:  "compaction": {
```
Tes sections sont toutes celles qui ne s'appellent ni `$schema`, ni `agent`, ni `permission`, ni `experimental`, ni `compaction` : dans l'exemple, `provider`, `model`, `mcp`, `shell` et `references`. Une section va de sa ligne jusqu'à la ligne avant la section suivante ; la dernière section du fichier s'arrête à l'avant-dernière ligne, juste avant le `}` final.

Si la commande n'affiche rien, ton fichier n'est pas indenté de 2 espaces. Envoie-moi alors la sortie de celle-ci, qui n'affiche que les noms des réglages, jamais leurs valeurs :
```sh
grep -n -o '^ *"[^"]*":' ~/.config/opencode/opencode.json | head -60
```
2. Crée `~/oc2/config/opencode/opencode.json` en y collant le contenu de `opencode-v2/opencode.snippet.json`.
3. Dans ce nouveau fichier, place le curseur au tout début de la ligne 3, celle de `  "agent": {`. Pour chacune de tes sections, dans l'ordre de la liste : sélectionne ses lignes dans ta 1.19 (`~/.config/opencode/opencode.json`), copie, et colle au curseur. La dernière ligne de chaque section collée doit finir par une virgule (`},` ou `",`) : ajoute-la quand elle manque, ce qui est le cas de la section qui était la dernière de ton fichier 1.19.
4. Si tu avais ajouté tes propres réglages dans la section `agent` de la 1.19 (par exemple `title`, ou `reasoning_effort` de la section « Qwen 3.8 » de `COMMANDES.md`), ajoute-les aussi dans la section `agent` du nouveau fichier.
5. Le fichier contient tes réglages de modèle, peut-être une clé : rends-le lisible par toi seul.
```sh
chmod 600 ~/oc2/config/opencode/opencode.json
```
6. **Ton provider.** La v2 exige deux réglages que la 1.19 n'exigeait pas :
   - dans ta section `provider`, chaque provider déclare son paquet. Pour une passerelle compatible OpenAI, comme vLLM, sa première ligne est `"npm": "@ai-sdk/openai-compatible",` : ajoute-la si elle manque ;
   - au premier niveau, juste après la ligne `$schema`, la liste des providers permis, avec le nom de ton provider (la partie avant le `/` de ta ligne `"model"`, et celui de ta ligne `"small_model"` s'il est différent) : `"enabled_providers": ["<ton provider>"],`.

   Pourquoi (vérifié avec la v2.1.2) : sans paquet déclaré, la v2 ne peut pas utiliser ton modèle et bascule sans prévenir sur un modèle gratuit d'OpenCode, hébergé chez eux, à qui elle envoie ta demande. Avec `enabled_providers`, elle refuse tout autre provider que le tien.
7. Vérifie :
```sh
grep -n '^  "' ~/oc2/config/opencode/opencode.json
```
Tu dois voir `$schema`, `enabled_providers`, puis tes sections, puis `agent`, `permission`, `experimental` et `compaction`, chacune une seule fois.
```sh
grep -c 'worktree_create' ~/oc2/config/opencode/opencode.json
```
Tu dois voir `1` : la section `permission` est bien celle de la v2.
```sh
grep -n '"npm"' ~/oc2/config/opencode/opencode.json
```
Tu dois voir une ligne par provider, par exemple `"npm": "@ai-sdk/openai-compatible",`.

Une virgule oubliée rend le fichier invalide, et la v2 l'ignorerait alors en entier : c'est vérifié à l'étape 8, point 1.

**5.7 Le dossier `plugins` ne doit contenir qu'un fichier :**
```sh
ls ~/oc2/config/opencode/plugins
```
Tu dois voir `openrd-pack.js` seul.

**Si un fichier collé reste en `FAILED`**, il a été :
- copié depuis la page normale de GitHub, et pas depuis **Raw** ;
- copié en partie seulement : vérifie sa dernière ligne ;
- enregistré sans retour à la ligne final (VS Code sans le réglage du début de ce guide) : place le curseur à la toute fin et appuie sur Entrée, ou active le réglage ;
- modifié par l'éditeur : tabulations changées en espaces, espaces de fin de ligne supprimés, enregistrement dans un autre encodage qu'UTF-8 ;
- collé dans le mauvais dossier.

## Étape 6 — Démarrer la v2

**Pourquoi.** Lancer le serveur de la v2 sur son propre port, avec un mot de passe et ses propres dossiers, sans arrêter la 1.19.

**Le mot de passe.** La v2 en exige un, pour que personne d'autre ne puisse utiliser ton OpenCode. Choisis-en un nouveau, sans espace au début ni à la fin : ni ton mot de passe d'entreprise, ni celui d'un autre service. Les commandes ci-dessous te le demandent sans l'afficher : il n'est écrit ni dans une commande, ni dans l'historique du terminal. Tu le retaperas dans le navigateur à l'étape 7.

Ouvre un terminal **réservé à la v2** et tape ces commandes une par une.

**6.1 Les dossiers de la v2**, pour ce terminal seulement :
```sh
export OPENCODE_CONFIG_DIR="$HOME/oc2/config/opencode" XDG_DATA_HOME="$HOME/oc2/data" XDG_CACHE_HOME="$HOME/oc2/cache" XDG_STATE_HOME="$HOME/oc2/state"
```
Rien ne s'affiche : c'est normal. Ces quatre réglages disent à la v2 de tout lire et tout écrire dans `~/oc2`. Ils ne valent que pour ce terminal et pour ce que tu y lances. Les commandes des agents, elles, retrouvent tes dossiers habituels : le plugin du pack leur retire ces réglages, pour que `git` (ton cache d'identifiants GitLab), `dotnet` et tes autres outils marchent comme dans ton terminal.

**6.2 La version et les dossiers de la v2 :**
```sh
~/oc2/cli/package/bin/opencode --version && ~/oc2/cli/package/bin/opencode debug paths
```
**Ce que tu dois voir** : `opencode v2.1.2`, puis dix lignes : `home` (ton dossier personnel), `tmp` (`/tmp/opencode`), et huit lignes dont le chemin commence par ton dossier personnel suivi de `/oc2/` : `data`, `cache`, `config`, `state`, `bin`, `log`, `repos` et `db`.

Si l'une de ces huit lignes montre `.config/opencode` ou `.local/share/opencode`, l'étape 6.1 n'a pas été faite dans ce terminal : refais-la, puis refais 6.2.

**6.3 Le mot de passe :**
```sh
printf 'Mot de passe de la v2 : '; stty -echo; read -r OPENCODE_SERVER_PASSWORD; stty echo; echo
```
Tape ton mot de passe : rien ne s'affiche, c'est normal. Puis Entrée.
```sh
export OPENCODE_SERVER_PASSWORD
```

**6.4 Le démarrage.** Dans le cas A de l'étape 2.5 :
```sh
cd ~ && ~/oc2/cli/package/bin/opencode serve --hostname 0.0.0.0 --port 4097 --print-logs 2>> ~/oc2/serve.log
```
Dans le cas B, si tu passeras par un tunnel SSH (étape 7), remplace `0.0.0.0` par `127.0.0.1`.

**Ce que tu dois voir** : une seule ligne, `server listening on http://0.0.0.0:4097`. Ensuite, **le terminal reste occupé** : c'est le serveur qui tourne, et son journal va dans `~/oc2/serve.log`. Laisse cette fenêtre ouverte, et ouvre un deuxième terminal pour les vérifications.

Pour arrêter la v2 : Ctrl+C dans cette fenêtre. Si tu la fermes, ou si ta connexion SSH coupe, la v2 s'arrête aussi : refais alors l'étape 6.

**Ne lance jamais la 1.19 depuis ce terminal** : les réglages de 6.1 lui feraient lire et écrire les dossiers de la v2. Ferme ce terminal après avoir arrêté la v2.

**Le mot de passe et les agents.** La v2.1.2, démarrée avec `serve`, laisse le mot de passe dans l'environnement des commandes qu'elle lance. Le plugin du pack le leur retire : les commandes des agents ne le reçoivent pas (vérifié).

**Si un message parle d'un port déjà utilisé** (`address already in use`, `EADDRINUSE`) : relance la commande de 6.4 avec un autre numéro, par exemple `--port 4098`.

## Étape 7 — Ouvrir la v2 dans ton navigateur et te connecter

**7.1 L'adresse :**
- **Cas A** : la même adresse que ta 1.19, avec `4097` à la place de son port. Par exemple, `http://machine:4096` devient `http://machine:4097`.
- **Cas B, avec le tunnel SSH** : dans un terminal **sur ton Mac**, tape la commande ci-dessous, en remplaçant `<utilisateur>` et `<machine>` par ce qu'affichait l'étape 1.
```sh
ssh -N -L 4097:127.0.0.1:4097 <utilisateur>@<machine>
```
Elle ne rend pas la main : c'est normal, laisse-la ouverte pendant que tu utilises la v2. Ouvre ensuite `http://localhost:4097` dans ton navigateur.
- **Cas B, avec ta plateforme** : si ta plateforme sait exposer un port (« port forwarding »), expose le port 4097 et ouvre l'adresse qu'elle te donne.

**7.2 La connexion**, telle qu'elle s'affiche avec la v2.1.2 :
1. Une page **« Se connecter à un serveur »** s'affiche, avec un champ « Pairing link ». Tu n'en as pas besoin.
2. Clique sur le lien **« Use password »**, en bas de la page.
3. Le champ **« URL du serveur »** est déjà rempli avec l'adresse de la page : laisse-le tel quel.
4. Dans **« Mot de passe (optionnel) »**, tape le mot de passe choisi à l'étape 6.
5. Clique sur **« Se connecter »**.
6. La page d'accueil s'affiche, avec **« Projets »** à gauche, vide au départ : la v2 a sa propre liste.

N'utilise jamais `opencode pair --remote` : cette commande expose ton serveur sur Internet.

**7.3 Ajouter un projet :**
1. Clique sur **« Ajouter un projet »**. Une fenêtre **« Ouvrir un projet »** s'ouvre, avec un champ déjà rempli avec ton dossier personnel.
2. Complète le chemin d'un de tes dépôts, par exemple `/home/dev/repos/mon-api`. Une liste de dossiers apparaît.
3. Clique la ligne qui est exactement ce chemin suivi de `/` (`/home/dev/repos/mon-api/`), et pas un sous-dossier comme `src/`.
4. Clique sur **« Sélectionner le dossier »**. Le projet apparaît sous « Projets ».
5. **« Nouvelle session »**, en haut à droite, ouvre la zone de saisie. Sous elle s'affichent le projet, `Local` et la branche, par exemple `mon-api / Local / develop`.

**Si la page ne s'ouvre pas :**
- dans le cas A, le port 4097 n'est sans doute pas ouvert sur la machine : passe par le tunnel SSH (cas B) ;
- si le mot de passe est refusé, arrête la v2 (Ctrl+C), refais l'étape 6 et retape ton mot de passe avec soin.

## Étape 8 — Vérifier que tout marche

Fais les dix points dans l'ordre, après t'être connecté et avoir ouvert un projet (étape 7) : la v2 ne lit sa configuration qu'à ce moment-là. **Si un point échoue, arrête-toi là et continue avec ta 1.19** : envoie-moi le point en échec et la dernière ligne de `tail -n 20 ~/oc2/serve.log` (sans mot de passe ni clé).

| # | Où | Ce que tu fais | Ce que tu dois voir |
|---|---|---|---|
| 1 | deuxième terminal | `grep -c 'kind=invalid' ~/oc2/serve.log` | `0` : ton `opencode.json` est accepté |
| 2 | deuxième terminal | `grep -c 'failed to load plugin' ~/oc2/serve.log` | `0` |
| 3 | deuxième terminal | `grep -c 'event stream connected' ~/oc2/serve.log` | `1` ou plus : le plugin du pack tourne |
| 4 | navigateur | dans une session d'un dépôt, tape `/` dans la zone de saisie | `go`, `fix`, `fortify`, `daily`, `review`, `compare`, `outil`, et `init`, la commande d'OpenCode |
| 5 | navigateur | écris « affiche le contenu de ~/.zshenv » | l'agent répond que c'est refusé : « Refused by the pack: ~/.zshenv is outside the repository… » |
| 6 | deuxième terminal | `grep -c 'refused by the pack' ~/oc2/serve.log` | `1` ou plus : le refus du point 5 est journalisé |
| 7 | navigateur | `/go` sur un petit ticket d'un dépôt de test | le message de la commande montre « Repository root: » suivi du chemin de ton dépôt, puis le travail va jusqu'à la MR Draft |
| 8 | navigateur | pendant que ce `/go` tourne, `/go` dans une autre session du même dépôt | « ⛔ /go refusé : /go tourne déjà dans ce dossier… » |
| 9 | navigateur | « liste mes tickets du sprint », puis « quelle est la dernière pipeline de ce dépôt ? » | des réponses venant de Jira et de GitLab ; une demande d'écriture, par exemple commenter une MR, est refusée |
| 10 | navigateur | « Nouvelle session », puis un clic sur `Local` sous la zone de saisie | un menu « Exécuter la session dans » : « Dépôt local » et « Nouvel espace de travail » |

**Si le point 1 donne plus que 0**, regarde ce qui est refusé :
```sh
grep 'kind=invalid' ~/oc2/serve.log | grep -o 'path=[^ ]*' | sort -u
```
`path=$` veut dire que tout le fichier est ignoré, à cause d'une erreur de syntaxe, le plus souvent une virgule manquante entre deux sections collées. **N'utilise pas la v2 dans cet état** : elle tournerait sans ton modèle et sans les règles globales du pack. Corrige l'étape 5.6, puis redémarre la v2 (Ctrl+C, étape 6). Une autre ligne nomme un réglage refusé : envoie-la-moi.

## Étape 9 — Vérifier le modèle (Qwen 3.8)

**Pourquoi.** La v2 relit la section `provider` de ta configuration, mais ignore sans erreur visible les réglages qu'elle ne connaît plus. Elle l'écrit seulement dans son journal.

**Quoi taper**, dans le deuxième terminal :
```sh
grep 'configuration normalization diagnostic' ~/oc2/serve.log | grep -o 'path=[^ ]*' | sort -u
```

**Ce que tu dois voir.** Une liste de réglages ignorés, sans aucune valeur. Ceux-ci sont attendus et sans effet :
- `path=$.compaction.prune` et `path=$.experimental.primary_tools` : deux réglages du pack pour la 1.19. `primary_tools` empêchait un sous-agent de poser une question ; avec la v2, c'est le plugin du pack qui le refuse (vérifié) ;
- `path=$.provider.<provider>.models.<modèle>.temperature` et `…reasoning` : des déclarations de la 1.19. La température est envoyée par les agents du pack, et la v2 affiche quand même la réflexion du modèle (vérifié avec un modèle de test qui réfléchit).

**Toute autre ligne**, par exemple `chat_template_kwargs`, `reasoning_effort`, `headerTimeout` ou `chunkTimeout` : envoie-moi la liste et je traduis ces réglages au format v2. En attendant, le modèle répond, mais peut-être sans son mode de raisonnement ou avec d'autres délais. `path=$` : voir l'étape 8, point 1.

Refais ensuite le test habituel de la section « Qwen 3.8 » de `COMMANDES.md`.

## Étape 10 — Utiliser la v2 au quotidien

**Démarrer la v2 chaque jour** : dans un terminal réservé à la v2, les étapes 6.1, 6.3 et 6.4 (6.2 est facultative). Dans le cas B, relance aussi ton tunnel SSH sur ton Mac.

Tant que tu valides la v2, garde les deux versions côte à côte : la 1.19 sur son port, la v2 sur 4097.

**Règles de cohabitation :**
- **Jamais de `/go`, `/fix` ou `/fortify` sur le même dépôt dans les deux versions en même temps.** Chacune protège ses dossiers, mais elles ne se voient pas l'une l'autre.
- **Les sessions ne sont pas partagées.** Celles de la 1.19 restent dans la 1.19. Les fiches ticket, elles, sont dans le `.git` de chaque dépôt : les deux versions les voient.

**Plusieurs tickets d'un même dépôt.** Dans une nouvelle session, clique `Local` sous la zone de saisie, puis **« Nouvel espace de travail »** : la session travaillera dans un dossier à part, créé à ton premier message dans `~/oc2/data/opencode/worktree/`, à partir de la branche affichée. `/go ABC-124` y travaille comme ailleurs (vérifié : la commande y affiche « Worktree: yes »), et les fiches ticket restent dans le `.git` du dépôt principal. Aucun script à lancer.

**Mettre à jour le pack**, quand je t'annonce une nouvelle version avec la liste des fichiers modifiés :
1. Recrée les deux listes d'empreintes depuis GitHub (étape 5.2).
2. Refais les étapes 5.3 et 5.4 : elles te montrent exactement les fichiers à coller.
3. Si ma liste contient `AGENTS.global.md` ou `opencode.snippet.json`, refais l'étape 5.5 ou 5.6.
4. Redémarre la v2 : Ctrl+C dans son terminal, puis l'étape 6.

**Ne mets pas à jour OpenCode v2 lui-même sans me demander.** Le pack est vérifié avec la 2.1.2, et la 2.1.0 a changé le fonctionnement des plugins. Le programme de la v2 a une commande `upgrade` : ne la lance jamais.

Quand la v2 t'a donné satisfaction plusieurs semaines, tu peux simplement arrêter de lancer la 1.19. Rien d'autre à faire : ne la désinstalle pas, c'est ton retour arrière.

## Étape 11 — Revenir à la 1.19

**Tant que tu n'as rien désinstallé** (c'est le cas si tu as suivi ce guide) :
1. Arrête la v2 : Ctrl+C dans son terminal.
2. Ouvre l'adresse de ta 1.19, comme avant. Si tu l'avais arrêtée, relance-la avec la commande notée à l'étape 2.4.

C'est tout : sa configuration et ses sessions n'ont jamais été modifiées.

**Le seul dossier partagé** : les scripts de `~/.config/opencode/scripts`, complétés à l'étape 5.4. Ce sont ceux de la 1.19, plus `fortify.sh` : la 1.19 fonctionne avec. Pour remettre exactement les anciens :
```sh
rm -rf ~/.config/opencode/scripts && cp -r ~/opencode-config-1.19/scripts ~/.config/opencode/scripts
```

**Pour supprimer complètement l'essai de la v2**, une fois la v2 arrêtée :
```sh
rm -rf ~/oc2
```

**Si un jour tu as désinstallé la 1.19**, retrouve son programme de la même façon que la v2, sans rien installer. Le paquet de la 1.19 pour ta machine porte le nom de celui de l'étape 4.1 sans `@opencode/cli-`, préfixé par `opencode-` : `opencode-linux-x64`, `opencode-linux-x64-baseline`, etc. Cette commande télécharge la version notée à l'étape 2.1 et l'extrait :
```sh
mkdir -p ~/oc119 && cd ~/oc119 && npm pack --ignore-scripts opencode-linux-x64@$(sed 's/[^0-9.]//g' ~/opencode-version-1.19.txt) && tar -xzf opencode-linux-x64-*.tgz && ls -l package/bin/opencode
```
Puis remets la configuration et les données sauvegardées à l'étape 3 :
```sh
rm -rf ~/.config/opencode ~/.local/share/opencode && cp -r ~/opencode-config-1.19 ~/.config/opencode && cp -r ~/opencode-data-1.19 ~/.local/share/opencode
```
Ta 1.19 se lance alors avec `~/oc119/package/bin/opencode` à la place de `opencode`, dans la commande notée à l'étape 2.4.

## Étape 12 — Dépannage

| Ce que tu vois | Pourquoi | Ce que tu fais |
|---|---|---|
| `~/oc2/cli/package/bin/opencode: No such file or directory` | l'archive n'a pas été extraite | refais l'étape 4.4 |
| plus rien ne s'affiche quand tu tapes, après un Ctrl+C pendant la question du mot de passe | l'affichage est resté coupé | tape `stty echo` à l'aveugle, puis Entrée |
| `address already in use` ou `EADDRINUSE` | le port est pris | relance l'étape 6.4 avec `--port 4098` |
| La page du navigateur ne répond pas | le port n'est pas joignable depuis ton poste | tunnel SSH (étape 7, cas B) |
| « Impossible de se connecter. Vérifiez l'adresse et le mot de passe du serveur » | mot de passe différent de celui de l'étape 6 | redémarre la v2 et retape le mot de passe |
| Point 1 de l'étape 8 plus grand que 0 | `opencode.json` invalide ou un réglage refusé | la lecture sous le tableau de l'étape 8 |
| Point 2 ou 3 de l'étape 8 en échec | le plugin n'a pas été chargé | refais les étapes 5.3 et 5.7, puis redémarre la v2 |
| Aucune commande `/go` dans la liste | les commandes du pack ne sont pas dans `~/oc2/config/opencode/commands` | refais les étapes 5.1 et 5.3, puis redémarre la v2 |
| Pas de réponse de Jira, GitLab, etc. | ta section `mcp` manque dans le nouvel `opencode.json` | refais l'étape 5.6 |
| L'agent ne répond pas du tout | modèle mal configuré | étape 9 |
| `/go` reste refusé alors que rien ne tourne | le verrou attend la fin d'un tour qu'il n'a pas vue | redémarre la v2 (Ctrl+C, puis étape 6) |
| Un processus `opencode … serve --service` tourne en plus | une commande de la v2 autre que `serve`, `--version` ou `debug paths` a lancé son service d'arrière-plan | dans un terminal où tu as fait l'étape 6.1 : `~/oc2/cli/package/bin/opencode service stop` |
| `Failed to fetch models.dev` dans `~/oc2/serve.log` | la v2 n'atteint pas Internet pour rafraîchir sa liste de modèles | sans effet : ton modèle est celui de ton `opencode.json` (vérifié avec un modèle de test) |

## Étape 13 — Ce qui ne change pas, ce qui change

**Ne change pas** :
- `/go`, `/fix`, `/daily`, `/review`, `/compare`, `/outil` ;
- tes fiches ticket ;
- les règles de sécurité des agents, y compris « un seul `/go`, `/fix` ou `/fortify` à la fois par dossier ».

**Change :**

| Avec la 1.19 | Avec la v2 |
|---|---|
| configuration dans `~/.config/opencode`, journal dans `~/.local/share/opencode/log/` | configuration dans `~/oc2/config/opencode`, journal dans `~/oc2/serve.log` (et `~/oc2/data/opencode/log/`) |
| redémarrer OpenCode : `opencode-web.sh stop && opencode-web.sh start` | Ctrl+C dans le terminal de la v2, puis l'étape 6 |
| le message d'une commande montre une ligne courte | il montre aussi l'état du dépôt (la v2 n'a pas de partie cachée dans un message) |
| le titre d'une session montre l'avancement et ✅ / ⛔ | le titre est celui d'OpenCode (étape 14) |
| un QCM qui propose une commande la lance tout seul | tape la commande proposée |
| `/go … comme dans ~/repos/old-api` rend ce dossier lisible | déclare ce dossier dans `references` de `~/oc2/config/opencode/opencode.json` |
| chaque skill était aussi une commande `/` | seul `/outil` reste |
| pas d'espace de travail dans l'interface | « Local » → « Nouvel espace de travail », sous la zone de saisie |
| les anciennes sorties d'outils étaient effacées des longues sessions (`compaction.prune`) | la v2 ignore ce réglage : une longue session est résumée plus tôt. Ouvre une session par ticket |
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
- les scripts des commandes lancés dans le bon dépôt, y compris dans un espace de travail ;
- le refus des outils v2 qui déplacent une session ou créent un worktree ;
- un sous-agent ne pose jamais de question (la 1.19 le faisait avec `experimental.primary_tools`, que la v2 ignore) ;
- ni le mot de passe du serveur ni les dossiers `~/oc2` dans l'environnement des commandes des agents et des scripts du pack.

Les vérifications automatiques passent :
- plugin : 484 sur 484 ;
- permissions : 1 760 cas sur 1 760 ;
- 30 fichiers d'agents, de commandes et de skills validés ;
- `shellcheck` sur tous les scripts ;
- ce guide, rejoué de bout en bout sur une machine de test.

## Étape 15 — Les fichiers de `opencode-v2/`

- **Nouveaux par rapport à `v2/`** :
  - `plugins/openrd-pack.js`, qui remplace `compact-commands.js` ;
  - `commands/fortify.md`, `agents/test-guardian.md`, `scripts/fortify.sh` ;
  - `CHECKSUMS-config.txt` et `CHECKSUMS-scripts.txt`, les listes d'empreintes de l'étape 5 ;
  - ce guide et `ANALYSE.md`.
- **Modifiés** :
  - les agents (vocabulaire des sous-agents, règles régénérées), `commands/go.md`, `commands/fix.md`, `AGENTS.global.md` ;
  - `skills/pack-doc/SKILL.md` (vocabulaire), `skills/pack-release-notes/SKILL.md` (un espace en fin de ligne retiré) et `skills/fortify-remediation/SKILL.md` (une ligne vide finale retirée), pour qu'un copier-coller les reproduise à l'identique ;
  - `opencode.snippet.json` ;
  - `COMMANDES.md` et `README.md`.
- **Identiques** : les autres scripts et les autres skills.
- **`tools/`** : mes outils de vérification. Ne les copie jamais dans ta configuration.

## Annexe A — La v2 a déjà remplacé ta 1.19

Pour toi si `opencode --version` affiche `opencode v2.1.2` et que ta 1.19 a été désinstallée, par exemple par une procédure interne. Tes dossiers sont alors ceux de la 1.19 : la configuration dans `~/.config/opencode`, les sessions dans `~/.local/share/opencode`. La v2 relit tes sessions 1.19 (vérifié). Mais tant que `~/.config/opencode` contient le pack 1.19, son plugin ne se charge pas dans la v2 : **aucun garde-fou du pack n'est actif. Ne lance ni `/go`, ni `/fix`, ni `/fortify` avant la fin de cette annexe.**

Cette annexe remplace les étapes 3 à 6. Les étapes 0 à 2, puis 7 à 15, restent valables, avec deux différences : ta configuration est dans `~/.config/opencode` (et non `~/oc2/config/opencode`), et le journal de la v2 est `~/.local/share/opencode/log/opencode.log`.

**A.1 Un seul OpenCode à la fois.** Si ta procédure interne démarre la v2 comme service (`opencode service start`, par exemple depuis `~/.zshrc_perso`), c'est ce service ton serveur : n'en lance pas un second avec `opencode-web.sh`. Pour l'instant, arrête tout : quitte les `opencode` ouverts dans un terminal (Ctrl+C), puis :
```sh
opencode service stop
```
```sh
opencode-web.sh stop
```
Vérifie qu'il ne reste rien :
```sh
ps -eo args | grep -i '[o]pencode'
```
Tu ne dois rien voir.

**A.2 Sauvegarder la configuration et les sessions telles qu'elles sont maintenant :**
```sh
cp -r ~/.config/opencode ~/opencode-config-avant-pack-v2 && cp -r ~/.local/share/opencode ~/opencode-data-avant-pack-v2 && ls -d ~/opencode-config-avant-pack-v2 ~/opencode-data-avant-pack-v2
```
Tu dois voir les deux chemins.

**A.3 Les deux listes d'empreintes.** Crée `~/CHECKSUMS-config.txt` et `~/CHECKSUMS-scripts.txt` en collant `opencode-v2/CHECKSUMS-config.txt` et `opencode-v2/CHECKSUMS-scripts.txt` (vue Raw).

**A.4 Le plugin 1.19 et les fichiers du pack :**
```sh
rm -f ~/.config/opencode/plugins/compact-commands.js && cd ~/.config/opencode && sha256sum --quiet --strict -c ~/CHECKSUMS-config.txt 2>/dev/null && echo "OK : la configuration est identique à GitHub"
```
Même lecture qu'à l'étape 5.3 : chaque ligne `FAILED` est un fichier à coller depuis `opencode-v2/`, au même chemin sous `~/.config/opencode/`. Relance la commande jusqu'au `OK`. Puis :
```sh
ls ~/.config/opencode/plugins
```
Tu dois voir `openrd-pack.js` seul.

**A.5 Les scripts :**
```sh
cd ~/.config/opencode/scripts && sha256sum --quiet --strict -c ~/CHECKSUMS-scripts.txt 2>/dev/null && echo "OK : les scripts sont identiques à GitHub"
```
Même lecture qu'à l'étape 5.4.

**A.6 `AGENTS.md`.** Comme l'étape 5.5, avec ta sauvegarde comme source de tes sections :
1. Remplace tout le contenu de `~/.config/opencode/AGENTS.md` par celui de `opencode-v2/AGENTS.global.md`.
2. Repère les sections :
```sh
grep -n '^## ' ~/opencode-config-avant-pack-v2/AGENTS.md
```
```sh
grep -n '^## ' ~/.config/opencode/AGENTS.md
```
3. Remets tes sections « Release groups » puis « Daily », copiées depuis `~/opencode-config-avant-pack-v2/AGENTS.md`.
4. Vérifie :
```sh
diff <(grep '^## ' ~/opencode-config-avant-pack-v2/AGENTS.md) <(grep '^## ' ~/.config/opencode/AGENTS.md) && echo "OK : mêmes sections"
```

**A.7 `opencode.json`.** Comme l'étape 5.6, avec ta sauvegarde comme source de tes sections :
1. Tes sections :
```sh
grep -n '^  "' ~/opencode-config-avant-pack-v2/opencode.json
```
2. Remplace tout le contenu de `~/.config/opencode/opencode.json` par celui de `opencode-v2/opencode.snippet.json`, puis colle tes sections au début de la ligne 3, chacune finie par une virgule.
3. Ton provider : `"npm": "@ai-sdk/openai-compatible",` en première ligne de chaque provider, et `"enabled_providers": ["<ton provider>"],` juste après la ligne `$schema` (étape 5.6, point 6).
4. Puis :
```sh
chmod 600 ~/.config/opencode/opencode.json
```
```sh
grep -n '^  "' ~/.config/opencode/opencode.json
```
```sh
grep -c 'worktree_create' ~/.config/opencode/opencode.json
```
```sh
grep -n '"npm"' ~/.config/opencode/opencode.json
```
Tu dois voir : `$schema`, `enabled_providers`, tes sections, `agent`, `permission`, `experimental` et `compaction` ; puis `1` ; puis une ligne `"npm"` par provider.

**A.8 Redémarrer avec un journal neuf.** Le journal de la v2 s'accumule d'un démarrage à l'autre : mets l'ancien de côté, pour que les vérifications ne lisent que le nouveau.
```sh
mv ~/.local/share/opencode/log/opencode.log ~/.local/share/opencode/log/opencode-avant-pack-v2.log
```
Puis redémarre ton seul serveur : `opencode service start` si ta procédure utilise le service, sinon `opencode-web.sh start`. Après chaque changement de configuration : `opencode service restart`.

**Le mot de passe du service.** Ne le mets pas dans `~/.zshenv` : chaque commande d'un agent passe par zsh, qui relit `~/.zshenv`, et recevrait donc le mot de passe, malgré le plugin qui le retire. Mets la ligne `export OPENCODE_PASSWORD=…` dans `~/.zshrc_perso`, avant les lignes `opencode service …` : seuls tes terminaux la lisent.

**A.9 L'adresse dans le navigateur.** L'interface de la v2 ne fonctionne qu'à la racine d'une adresse : rien après le nom de la machine et le port, par exemple `http://machine:<port>/`. Elle n'accepte que `/`, `/settings`, `/connect`, `/new-session` et `/server/…/session/…` ; toute autre adresse affiche « Unrecognised route! » (vérifié dans son code et à l'écran) :
- une ancienne adresse de la 1.19 (`/<longue suite>/session/…`), restée dans ton historique ou un favori : efface tout ce qui suit le port ;
- une adresse de ton environnement de travail qui ajoute un chemin, par exemple `…/user/<uid>/http/4096`, `…/proxy/<port>/` ou `…/apps/…` : l'interface web de la v2 ne peut pas fonctionner derrière elle. Le terminal, lui, si : `opencode --server <cette adresse>` depuis ton poste, comme le prévoit ta procédure interne. Utilise une adresse sans chemin, si ta plateforme en donne une pour le port <port>, ou le tunnel SSH de l'étape 7 (cas B), avec le port <port>.

**A.10 Vérifier.** Connecte-toi, ouvre un projet (étape 7), puis fais l'étape 8 avec ces trois lignes à la place des points 1 à 3 :

| # | Ce que tu fais | Ce que tu dois voir |
|---|---|---|
| 1 | `grep -c 'kind=invalid' ~/.local/share/opencode/log/opencode.log` | `0` |
| 2 | `grep -c 'failed to load plugin' ~/.local/share/opencode/log/opencode.log` | `0` |
| 3 | `grep -c 'loading plugin.*openrd-pack' ~/.local/share/opencode/log/opencode.log` | `1` ou plus |

Le point 6 de l'étape 8 ne s'applique pas : les refus du plugin ne vont pas dans ce journal. Le point 5 suffit : la réponse de l'agent montre le refus.

Pour le modèle, l'étape 9, avec ce journal :
```sh
grep 'configuration normalization diagnostic' ~/.local/share/opencode/log/opencode.log | grep -o 'path=[^ ]*' | sort -u
```

**Revenir à la 1.19** : étape 11, cas « Si un jour tu as désinstallé la 1.19 ». Pour la configuration, reprends la sauvegarde faite avant la désinstallation (par exemple `~/.config/opencode.backup`, celle de la procédure interne) : elle contient encore `compact-commands.js`. Pour les sessions, `~/opencode-data-avant-pack-v2` (étape A.2) : la 1.19 relit ses sessions après le passage de la v2 (vérifié).
