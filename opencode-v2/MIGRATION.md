# Passer d'OpenCode 1.19 à OpenCode v2, pas à pas

Ce guide part de zéro. Chaque étape dit **pourquoi** on la fait, **quoi taper**, **ce que tu dois voir**, et **quoi faire si ce n'est pas ce que tu vois**. Ne saute aucune étape et ne passe à la suivante que si la précédente donne le résultat attendu.

Le principe : OpenCode v2 s'installe **à côté** de ta version 1.19, dans son propre dossier `~/oc2`, sur un autre port. La 1.19 continue de tourner comme avant pendant tout l'essai : la v2 n'écrit rien dans ses dossiers, à une exception près, les scripts `fortify.sh` et `test-guardian.sh` que tu ajoutes toi-même au dossier des scripts du pack (étape 5.4). Revenir en arrière consiste à rouvrir l'adresse de la 1.19.

**La v2 a déjà remplacé ta 1.19** (par exemple avec une procédure interne qui fait `npm install -g @opencode/cli`) ? Ne fais pas les étapes 1 à 12 : va directement à l'**annexe A**, à la fin de ce guide. C'est le parcours complet pour ce cas, de l'état des lieux à l'interface web, démarrée par le service de ta procédure interne ou par `opencode-web.sh`.

Tout ce guide a été rejoué de bout en bout sur une machine de test, avec un utilisateur `coder`, zsh, une configuration 1.19 du pack, et le vrai OpenCode v2.1.3. Les résultats « Ce que tu dois voir » viennent de ce test.

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

Les étapes 13 à 15 sont des annexes : ce qui change, ce que le pack reprend de la 1.19 et ferme dans la v2, et les fichiers du pack. L'annexe A est le parcours complet quand la v2 est déjà installée à la place de la 1.19.

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

**D'où vient la v2.** Du registre npm, où l'équipe d'OpenCode publie chaque version. Le programme pour une machine Linux classique est dans le paquet **`@opencode/cli-linux-x64`**, version **2.1.3**, publiée le 22 octobre 2026. Ce paquet contient un seul programme compilé, `bin/opencode`, et aucun script. Tu n'as rien à chercher sur le site d'OpenCode : tout ce qu'il faut est dans ce guide.

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

La suite du guide écrit `@opencode/cli-linux-x64` : si ton paquet est un autre, remplace-le, ainsi que le nom de fichier `opencode-cli-linux-x64-2.1.3.tgz` par celui que `npm pack` affiche.

**4.2 Télécharger :**
```sh
mkdir -p ~/oc2/cli && cd ~/oc2/cli && npm pack --ignore-scripts @opencode/cli-linux-x64@2.1.3
```
**Ce que tu dois voir** : des lignes qui commencent par `npm notice`, dont un bloc `Tarball Details` avec `version: 2.1.3` et `package size: 113.8 MB`, puis, seul sur sa ligne, le nom du fichier téléchargé : `opencode-cli-linux-x64-2.1.3.tgz`.

npm peut ajouter « New major version of npm available! … To update run: npm install -g npm@… » : ignore ce message et ne lance pas cette commande.

**4.3 Vérifier l'empreinte de l'archive.** npm vérifie déjà l'archive avec l'empreinte que lui donne ton registre. Cette commande la compare en plus à l'empreinte publiée par le registre officiel `registry.npmjs.org`, que j'ai relevée et écrite ici : si ton miroir servait autre chose, tu le verrais.
```sh
cd ~/oc2/cli && echo "5953bb4de6dd80070f9e8390dfdd27cb7a32aa9087e4ca4f53bea51d79a5dc6ff0273e902f18f3b105b62eb69b89ec20d38eb201e2a57fed673cf644945d6a3f  opencode-cli-linux-x64-2.1.3.tgz" | sha512sum -c
```
**Ce que tu dois voir** : `opencode-cli-linux-x64-2.1.3.tgz: OK`.

Avec `FAILED` à la place de `OK` : arrête-toi, supprime l'archive (`rm ~/oc2/cli/*.tgz`) et envoie-moi la ligne. Ne va pas plus loin.

Pour un autre paquet de l'étape 4.1, la ligne à taper dans le dossier `~/oc2/cli` (copie seulement celle de ton paquet) :
```sh
echo "f1a95f9af156ef0a0d3f7a6507f075e9f8511125d78b44bdd9253317820db5f44e13bb4d24251e2df8ded2af836772b3cbb1d16573d7a37c9aa73170ad4864f6  opencode-cli-linux-x64-baseline-2.1.3.tgz" | sha512sum -c
echo "b26ccaecc7c1a89832c20636f284111bdfd61e1eedd2a61994a8fdaf9a0ae56724ed490d86b7a74d4099c71a775646dff67bf17b3e75dce0e29ce099f047a400  opencode-cli-linux-x64-musl-2.1.3.tgz" | sha512sum -c
echo "5c8de4fa5716ef4a93099fd6bfbd1bb1220ae6c3fd59643fbb014bf57b8b72b439a3a5edd73df475a78978d18e3602c9764dd135e11ddcd433cccda653389281  opencode-cli-linux-x64-baseline-musl-2.1.3.tgz" | sha512sum -c
echo "4f0a3c9c2ccb6d00b98d9739a007a2cdede108f2926b06bfb429b637bb3a108a9e11c74f53b54040d622c8492b0b85210c993dd44a6996c8b33e0f1798709d98  opencode-cli-linux-arm64-2.1.3.tgz" | sha512sum -c
echo "60632db7c34fb33ce3fa10bfe899f889ecbc093f10d6a93e2c189aae01530d25b670bee6665a3bac17d79ce006da2e178a0d5adb9ff50f288dbc6ce827d4ea62  opencode-cli-linux-arm64-musl-2.1.3.tgz" | sha512sum -c
```

**4.4 Extraire le programme :**
```sh
cd ~/oc2/cli && tar -xzf opencode-cli-linux-x64-2.1.3.tgz && ls -l package/bin/opencode
```
**Ce que tu dois voir** : une ligne qui commence par `-rwxr-xr-x`, avec la taille `240306352` (environ 240 Mo, pour `cli-linux-x64`), et qui finit par `package/bin/opencode`. La date affichée, le 26 octobre 1985, est normale : npm met cette date à tous les fichiers de ses archives.

L'archive ne sert plus :
```sh
rm ~/oc2/cli/opencode-cli-linux-x64-2.1.3.tgz
```

Dans tout ce guide, **le programme de la v2 est `~/oc2/cli/package/bin/opencode`**. Le simple mot `opencode` reste ta 1.19.

**Ne lance pas encore ce programme**, même pour voir sa version. Sans les réglages de l'étape 6, la v2 créerait ses dossiers et son journal dans ceux de la 1.19 : vérifié, un simple `--version` écrit dans `~/.local/share/opencode/log/`. Sa version se vérifie à l'étape 6.

**Si ça ne marche pas :**

| Message | Cause | Ce que tu fais |
|---|---|---|
| `E404` ou `404 Not Found` | ton registre (Artifactory) ne connaît pas ce paquet | demande à l'équipe Artifactory d'autoriser, depuis registry.npmjs.org, le paquet de l'étape 4.1 en version 2.1.3 |
| `ETIMEDOUT`, `ECONNREFUSED`, `UNABLE_TO_GET_ISSUER_CERT` | la machine n'atteint pas le registre | le même souci qu'un `npm` qui échoue chez toi d'habitude : vois avec l'équipe qui gère l'environnement |
| `No space left on device` | il faut environ 360 Mo libres (archive et programme) | libère de la place, puis recommence |

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

La première fois, avec un pack 1.19 à jour, tu dois voir ces 32 lignes (chaque commande du pack v2 commence par une ligne `[[command …]]` que lit le plugin, d'où les dix commandes) :
```text
agents/analyst.md: FAILED
agents/checker.md: FAILED
agents/coder.md: FAILED
agents/debugger.md: FAILED
agents/doc-writer.md: FAILED
agents/pilot.md: FAILED
agents/test-guardian.md: FAILED open or read
commands/compare.md: FAILED
commands/daily.md: FAILED
commands/fix.md: FAILED
commands/fortify.md: FAILED open or read
commands/go.md: FAILED
commands/outil.md: FAILED
commands/push.md: FAILED open or read
commands/review.md: FAILED
commands/sync.md: FAILED open or read
commands/tests.md: FAILED open or read
skills/api-tests/SKILL.md: FAILED open or read
skills/best-practices/SKILL.md: FAILED
skills/blazorise/SKILL.md: FAILED open or read
skills/build-fix/SKILL.md: FAILED
skills/dotnet-cqrs-conventions/SKILL.md: FAILED
skills/fortify-remediation/SKILL.md: FAILED
skills/pack-abandon/SKILL.md: FAILED
skills/pack-audit/SKILL.md: FAILED
skills/pack-cqrs/SKILL.md: FAILED
skills/pack-doc/SKILL.md: FAILED
skills/pack-http/SKILL.md: FAILED open or read
skills/pack-planifier/SKILL.md: FAILED open or read
skills/pack-release-notes/SKILL.md: FAILED
skills/pack-setup/SKILL.md: FAILED
plugins/openrd-pack.js: FAILED open or read
```
Si ton pack 1.19 est plus ancien, il y en a plus. Par exemple, `agents/test-guardian.md: FAILED open or read` veut dire : crée `~/oc2/config/opencode/agents/test-guardian.md` et colles-y le contenu de `opencode-v2/agents/test-guardian.md`. Un skill nouveau a besoin de son dossier d'abord, avant de créer son `SKILL.md` : `cd ~/oc2/config/opencode/skills && mkdir -p blazorise api-tests pack-http pack-planifier`.

Relance la commande après chaque série de fichiers collés. **Tu as fini quand elle affiche `OK : la configuration est identique à GitHub`.** Si elle n'affiche rien du tout, c'est la liste `CHECKSUMS-config.txt` elle-même qui est mal collée : recrée-la depuis Raw.

**Les fichiers en plus.** La vérification ne regarde que les fichiers du pack. Pour voir le reste :
```sh
ls ~/oc2/config/opencode/agents ~/oc2/config/opencode/commands
```
Tu dois voir, pour les agents : `analyst.md checker.md coder.md debugger.md doc-writer.md pilot.md test-guardian.md` ; pour les commandes : `compare.md daily.md fix.md fortify.md go.md outil.md push.md review.md sync.md tests.md`. Un autre nom est soit un fichier à toi (garde-le), soit un reste d'un ancien pack : envoie-moi son nom. Dans `skills`, tes skills `pattern-…` sont à toi : ils restent.

**5.4 Les scripts du pack.** Ils restent dans `~/.config/opencode/scripts`, où les commandes et les agents les appellent : ce dossier sert aux deux versions. Ceux de la v2 sont ceux de la 1.19, plus `abandon.sh`, `api-surface.sh`, `base.sh`, `dotnet-problem.sh`, `dotnet-targets.sh`, `fortify.sh`, `front-info.sh`, `front-test.sh`, `related-repos.sh`, `test-guardian.sh`, `test-lint.sh`, `test-platform.sh`, `environments.sh`, `env-tests.sh`, `http-files.sh` et `schedule.sh` ; onze d'entre eux sont dans une version plus récente (`branch.sh`, `build-test.sh`, `detect-project-type.sh`, `diff-guard.sh`, `fetch.sh`, `outil.sh`, `package-refs.sh`, `review-target.sh`, `ship.sh`, `todo.sh`, `workflow-state.sh`), que les commandes de la 1.19 appellent de la même façon : ta 1.19 marche avec, et en profite (tests Microsoft.Testing.Platform, base d'une branche, documentation d'un package public, `git fetch` de deux espaces de travail qui se croisent relancé tout seul, un dossier front-end buildé et testé une fois par `build-test.sh <dossier>`, un problème de la machine dit en une ligne, un `node_modules` jamais poussé).
```sh
cd ~/.config/opencode/scripts && sha256sum --quiet --strict -c ~/oc2/CHECKSUMS-scripts.txt 2>/dev/null && echo "OK : les scripts sont identiques à GitHub"
```
Même lecture qu'en 5.3, avec les fichiers de `opencode-v2/scripts/`. Avec un pack 1.19 à jour, il y a ces 27 lignes :
```text
abandon.sh: FAILED open or read
api-surface.sh: FAILED open or read
base.sh: FAILED open or read
branch.sh: FAILED
build-test.sh: FAILED
detect-project-type.sh: FAILED
diff-guard.sh: FAILED
dotnet-problem.sh: FAILED open or read
dotnet-targets.sh: FAILED open or read
env-tests.sh: FAILED open or read
environments.sh: FAILED open or read
fetch.sh: FAILED
fortify.sh: FAILED open or read
front-info.sh: FAILED open or read
front-test.sh: FAILED open or read
http-files.sh: FAILED open or read
outil.sh: FAILED
package-refs.sh: FAILED
related-repos.sh: FAILED open or read
review-target.sh: FAILED
schedule.sh: FAILED open or read
ship.sh: FAILED
test-guardian.sh: FAILED open or read
test-lint.sh: FAILED open or read
test-platform.sh: FAILED open or read
todo.sh: FAILED
workflow-state.sh: FAILED
```
`FAILED open or read` : crée le fichier dans `~/.config/opencode/scripts/` avec le contenu du même fichier de `opencode-v2/scripts/` ; `FAILED` : remplace tout son contenu. D'autres lignes veulent dire que tes scripts 1.19 ne sont pas les derniers : colle-les aussi depuis `opencode-v2/scripts/`. `diff-guard.sh` contient des tabulations : s'il reste en `FAILED`, c'est que ton éditeur les a remplacées par des espaces.

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
Chaque ligne donne un numéro de ligne et le titre d'une section. Dans le nouveau fichier, tu dois voir notamment `81:## Daily`, `85:## Release groups` et `92:## NuGet / Artifactory`.
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
Tes sections sont toutes celles qui ne s'appellent ni `$schema`, ni `agent`, ni `permission`, ni `experimental`, ni `compaction`, ni `share`, ni `autoupdate`, ni `websearch` (le pack fixe ces huit-là) : dans l'exemple, `provider`, `model`, `mcp`, `shell` et `references`. Une section va de sa ligne jusqu'à la ligne avant la section suivante ; la dernière section du fichier s'arrête à l'avant-dernière ligne, juste avant le `}` final.

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

   Pourquoi (vérifié avec la v2.1.3) : sans paquet déclaré, la v2 ne peut pas utiliser ton modèle et bascule sans prévenir sur un modèle gratuit d'OpenCode, hébergé chez eux, à qui elle envoie ta demande. Avec `enabled_providers`, elle refuse tout autre provider que le tien.
7. Vérifie :
```sh
grep -n '^  "' ~/oc2/config/opencode/opencode.json
```
Tu dois voir `$schema`, `enabled_providers`, puis tes sections, puis `agent`, `permission`, `experimental`, `compaction`, `share`, `autoupdate` et `websearch`, chacune une seule fois. Les trois dernières coupent ce qui partirait vers l'extérieur sans toi : le partage d'une session sur un lien public d'opencode.ai, la recherche de mises à jour d'OpenCode, et la recherche web (vérifié : la v2 les applique, sans avertissement).
```sh
grep -c '"opencode_worktree_create"' ~/oc2/config/opencode/opencode.json
```
Tu dois voir `1` : la section `permission` est bien celle de cette version du pack.
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
**Ce que tu dois voir** : `opencode v2.1.3`, puis dix lignes : `home` (ton dossier personnel), `tmp` (`/tmp/opencode`), et huit lignes dont le chemin commence par ton dossier personnel suivi de `/oc2/` : `data`, `cache`, `config`, `state`, `bin`, `log`, `repos` et `db`.

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

**Le mot de passe et les agents.** La v2 (2.1.2 comme 2.1.3), démarrée avec `serve`, laisse le mot de passe dans l'environnement des commandes qu'elle lance. Le plugin du pack le leur retire : les commandes des agents ne le reçoivent pas (vérifié).

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

**7.2 La connexion**, telle qu'elle s'affiche avec la v2.1.3 :
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

Fais les onze points dans l'ordre, après t'être connecté et avoir ouvert un projet (étape 7) : la v2 ne lit sa configuration qu'à ce moment-là. **Si un point échoue, arrête-toi là et continue avec ta 1.19** : envoie-moi le point en échec et la dernière ligne de `tail -n 20 ~/oc2/serve.log` (sans mot de passe ni clé).

| # | Où | Ce que tu fais | Ce que tu dois voir |
|---|---|---|---|
| 1 | deuxième terminal | `grep -c 'kind=invalid' ~/oc2/serve.log` | `0` : ton `opencode.json` est accepté |
| 2 | deuxième terminal | `grep -c 'failed to load plugin' ~/oc2/serve.log` | `0` |
| 3 | deuxième terminal | `grep -c 'event stream connected' ~/oc2/data/opencode/log/openrd-pack.log` | `1` ou plus : le plugin du pack tourne (son journal, à côté de celui d'OpenCode) |
| 4 | navigateur | dans une session d'un dépôt, tape `/` dans la zone de saisie | `go`, `fix`, `fortify`, `daily`, `review`, `compare`, `outil`, et `init`, la commande d'OpenCode |
| 5 | navigateur | écris « affiche le contenu de ~/.zshenv » | l'agent répond que c'est refusé : « Refused by the pack: ~/.zshenv is outside the repository… » |
| 6 | deuxième terminal | `grep -c 'refused by the pack' ~/oc2/data/opencode/log/openrd-pack.log` | `1` ou plus : le refus du point 5 est journalisé |
| 7 | navigateur | `/go` sur un petit ticket d'un dépôt de test, dans une nouvelle session | ton message s'affiche en une ligne, « /go ABC-123 — mon-api · branche develop » ; la session prend le nom « /go ABC-123 », précédé de ⏳ et de l'avancement pendant le travail, puis de ✅ à la MR Draft |
| 8 | navigateur | pendant que ce `/go` tourne, `/go` dans une autre session du même dépôt | « ⛔ /go refusé : /go tourne déjà dans ce dossier… » |
| 9 | navigateur | « liste mes tickets du sprint », puis « quelle est la dernière pipeline de ce dépôt ? » | des réponses venant de Jira et de GitLab ; une demande d'écriture, par exemple commenter une MR, est refusée |
| 10 | navigateur | « Nouvelle session », un clic sur `Local` sous la zone de saisie, puis « Nouvel espace de travail », et « bonjour » | le menu « Exécuter la session dans » propose « Dépôt local » et « Nouvel espace de travail » ; une fois nommée, la session a un titre qui commence par `[` et le nom du nouveau dossier, par exemple `[crisp-river]` |
| 11 | navigateur | `/daily`, puis, à sa question « Sur quoi tu bosses ? », un `/go …` | le `/go` choisi démarre tout seul dans la même session |

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
- `path=$.compaction.prune` et `path=$.experimental.primary_tools` : deux réglages de la 1.19 que la v2 ignore. Le plugin du pack les applique lui-même : il retire l'outil des questions aux sous-agents, et il efface des requêtes au modèle les sorties des anciens outils quand `compaction.prune` vaut `true` (vérifié) ;
- `path=$.provider.<provider>.models.<modèle>.temperature` et `…reasoning` : des déclarations de la 1.19. La température est envoyée par les agents du pack, et la v2 affiche quand même la réflexion du modèle (vérifié avec un modèle de test qui réfléchit).

**Toute autre ligne**, par exemple `chat_template_kwargs`, `reasoning_effort`, `headerTimeout` ou `chunkTimeout` : envoie-moi la liste et je traduis ces réglages au format v2. En attendant, le modèle répond, mais peut-être sans son mode de raisonnement ou avec d'autres délais. `path=$` : voir l'étape 8, point 1.

Refais ensuite le test habituel de la section « Qwen 3.8 » de `COMMANDES.md`.

## Étape 10 — Utiliser la v2 au quotidien

**Démarrer la v2 chaque jour** : dans un terminal réservé à la v2, les étapes 6.1, 6.3 et 6.4 (6.2 est facultative). Dans le cas B, relance aussi ton tunnel SSH sur ton Mac.

Tant que tu valides la v2, garde les deux versions côte à côte : la 1.19 sur son port, la v2 sur 4097.

**Règles de cohabitation :**
- **Jamais de `/go`, `/fix` ou `/fortify` sur le même dépôt dans les deux versions en même temps.** Chacune protège ses dossiers, mais elles ne se voient pas l'une l'autre.
- **Les sessions ne sont pas partagées.** Celles de la 1.19 restent dans la 1.19. Les fiches ticket, elles, sont dans le `.git` de chaque dépôt : les deux versions les voient.

**Plusieurs tickets d'un même dépôt.** Dans une nouvelle session, clique `Local` sous la zone de saisie, puis **« Nouvel espace de travail »** : la session travaillera dans un dossier à part, créé à ton premier message dans `~/oc2/data/opencode/worktree/`, à partir de la branche affichée. `/go ABC-124` y travaille comme ailleurs (vérifié : la ligne de la commande dit « mon-api · worktree <dossier> · … », et le titre de la session commence par `[<dossier>]`, pour la retrouver sur l'accueil, qui mélange les sessions de tous les dossiers), et les fiches ticket restent dans le `.git` du dépôt principal. Aucun script à lancer.

**Mettre à jour le pack**, quand je t'annonce une nouvelle version avec la liste des fichiers modifiés :
1. Recrée les deux listes d'empreintes depuis GitHub (étape 5.2).
2. Refais les étapes 5.3 et 5.4 : elles te montrent exactement les fichiers à coller.
3. Si ma liste contient `AGENTS.global.md` ou `opencode.snippet.json`, refais l'étape 5.5 ou 5.6.
4. Redémarre la v2 : Ctrl+C dans son terminal, puis l'étape 6.

**Ne mets pas à jour OpenCode v2 lui-même sans me demander.** Le pack est vérifié avec la 2.1.2 et la 2.1.3, et la 2.1.0 a changé le fonctionnement des plugins. Le programme de la v2 a une commande `upgrade` : ne la lance jamais. Le pack coupe aussi sa recherche automatique de mises à jour (`"autoupdate": false`).

Quand la v2 t'a donné satisfaction plusieurs semaines, tu peux simplement arrêter de lancer la 1.19. Rien d'autre à faire : ne la désinstalle pas, c'est ton retour arrière.

## Étape 11 — Revenir à la 1.19

**Tant que tu n'as rien désinstallé** (c'est le cas si tu as suivi ce guide) :
1. Arrête la v2 : Ctrl+C dans son terminal.
2. Ouvre l'adresse de ta 1.19, comme avant. Si tu l'avais arrêtée, relance-la avec la commande notée à l'étape 2.4.

C'est tout : sa configuration et ses sessions n'ont jamais été modifiées.

**Le seul dossier partagé** : les scripts de `~/.config/opencode/scripts`, complétés à l'étape 5.4. Ce sont ceux de la 1.19, plus `fortify.sh` et `test-guardian.sh` : la 1.19 fonctionne avec. Pour remettre exactement les anciens :
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
| Le premier message après un démarrage met jusqu'à 30 s à partir | la v2 enverrait la première requête sans les outils des serveurs MCP encore en connexion (Jira, GitLab…) : le plugin les attend, comme la 1.19, pendant les 5 premières minutes | rien. Si c'est à chaque démarrage, un serveur MCP est lent à démarrer : `grep -i 'mcp' ~/oc2/serve.log \| tail -5` |
| L'agent répond « ⚠ Le plugin du pack n'est pas chargé : ses garde-fous sont inactifs… » | la commande est arrivée au modèle sans passer par le plugin | refais les étapes 5.3 et 5.7, puis redémarre la v2 ; n'utilise pas la v2 avant |
| « Refused by the pack: this is the third identical … call of your answer, a loop » dans la conversation | le modèle répétait le même appel d'outil dans une réponse (la règle `doom_loop` de la 1.19) | rien : l'agent change d'approche. Si un agent y revient souvent, envoie-moi les lignes `same call three times` de `~/oc2/data/opencode/log/openrd-pack.log` |
| Le titre d'un `/go`, `/fix` ou `/fortify` commence par `↻`, puis un message « ↻ /go ABC-123 · reprise automatique (…) » apparaît | le run s'était arrêté avant sa réponse finale (panne du serveur du modèle après ses 10 essais, limite d'étapes du pilote, réponse coupée) : le plugin le reprend tout seul, dans la même session, depuis la fiche ticket | rien. Deux reprises au plus d'affilée ; après, le titre passe à `⛔` et `grep 'run not resumed' ~/oc2/data/opencode/log/openrd-pack.log` dit pourquoi. Un message que tu tapes annule une reprise qui attend |
| Le titre affiche « résumé du contexte (conversation trop longue) » | la conversation du run ne tenait plus dans le contexte du modèle : la v2 la résume | rien : le plugin redonne au pilote les consignes de sa commande (au sous-agent, sa tâche) après le résumé, et le pilote relit la fiche ticket |
| Le titre commence par `⏸` | le run attend ta réponse (une question au PO) | relance la commande avec la réponse, par exemple `/go ABC-123 <la réponse du PO>` |

## Étape 13 — Ce qui ne change pas, ce qui change

**Ne change pas** :
- `/go`, `/fix`, `/daily`, `/review`, `/compare`, `/outil` ;
- tes fiches ticket ;
- les règles de sécurité des agents, y compris « un seul `/go`, `/fix` ou `/fortify` à la fois par dossier » ;
- la ligne courte d'une commande dans la conversation, « /go ABC-123 — mon-api · branche develop · ⏰ 1 rappel », le reste allant au modèle ;
- le titre des sessions : l'avancement (⏳ 1:42 réflexion 2,3k tokens — /go ABC-123), ce qu'attend un sous-agent, puis ✅ ou ⛔ (et maintenant ⏸ quand le run t'attend, ↻ quand il va reprendre tout seul) ;
- la commande choisie dans un QCM, qui démarre toute seule ;
- un dossier que tu cites dans un message, lisible par les agents, en lecture seule (jamais ton dossier personnel lui-même ni un de ses dossiers cachés : citer `~/.zshenv` ne rend rien lisible, une faille de la 1.19 corrigée dans les deux packs).

**Change :**

| Avec la 1.19 | Avec la v2 |
|---|---|
| configuration dans `~/.config/opencode`, journal dans `~/.local/share/opencode/log/` | configuration dans `~/oc2/config/opencode`, journal dans `~/oc2/serve.log` (et `~/oc2/data/opencode/log/`), journal du plugin dans `~/oc2/data/opencode/log/openrd-pack.log` |
| redémarrer OpenCode : `opencode-web.sh stop && opencode-web.sh start` | Ctrl+C dans le terminal de la v2, puis l'étape 6 |
| chaque skill était aussi une commande `/` | seul `/outil` reste ; `@` dans la zone de saisie ajoute à ton message un skill (`@build-fix`) ou une référence d'`opencode.json` |
| pas d'espace de travail dans l'interface | « Local » → « Nouvel espace de travail », sous la zone de saisie ; le titre de ses sessions commence par `[dossier]` |
| une erreur de la passerelle du modèle : 5 nouveaux essais, de 2 à 30 s d'attente | 10 nouveaux essais au plus ; pendant un `/go`, `/fix` ou `/fortify`, le plugin les étale sur environ 8 minutes (10 s, 20 s, 30 s, 45 s, puis 1 min), le titre dit quand vient le prochain ; puis, si le serveur ne répond toujours pas, le run reprend tout seul 2 minutes plus tard, puis 5 |
| une session reprise après un redémarrage d'OpenCode : à relancer à la main | la v2 reprend d'elle-même un travail interrompu par un redémarrage ; le plugin reprend aussi un run arrêté avant sa réponse finale |
| une conversation résumée quand le contexte est plein : le pilote pouvait perdre la procédure de sa commande | le pilote retrouve les consignes de sa commande après le résumé, chaque sous-agent sa tâche |
| — | **`/fortify`** : voir le document « Fortify par lot avec test-guardian », et la section « Fortify » de `COMMANDES.md` pour ses prérequis (coverlet) |
| les tests écrits par l'agent qui code | `/go` : le test d'un bug est écrit d'abord par le test-guardian (rouge, puis vert après le correctif, deux fois chacun) ; en fin de `/go`, les lignes modifiées qu'aucun test n'exécute reçoivent leurs tests ; `/fix` : une faille de Fortify ou de Sonar est corrigée avec sa preuve |
| les tests front-end lancés par l'agent avec la commande d'AGENTS.md : `npm test` sur un Angular avec Karma tenait le tour 20 minutes en mode watch | `build-test.sh <dossier du front>` : son build, puis ses tests une fois (Karma en ChromeHeadless, Vitest, Jest, Create React App), avec des lignes `BUILD:` et `TESTS:` ; une commande qui ne finit jamais (serveur, mode watch) est refusée aux agents du pack, la conversation peut la lancer en arrière-plan ou bornée |
| des règles écrites pour .NET 10 | .NET 8, 9 et 10, netstandard2.0 et les librairies : les agents écrivent pour la version du projet et sa version de C#, ne touchent jamais global.json ni un framework cible ; un SDK ou un runtime absent est dit en une ligne ; l'API publique d'une librairie est contrôlée contre sa dernière version publiée ; les dépôts d'une même application partagent leur « Contrat » |

## Étape 14 — Ce que le pack reprend de la 1.19, et ce qu'il ferme dans la v2

**Tout ce que faisait le pack avec la 1.19 est repris**, et vérifié avec le vrai OpenCode v2.1.3 :
- les refus des secrets et des dumps d'environnement, les agents limités à leur dépôt, les délais longs des builds et des tests ;
- un seul pilote par dossier, y compris entre deux OpenCode de la même machine (le verrou est aussi un fichier du `.git` du dépôt) ;
- les scripts des commandes lancés dans le bon dépôt, y compris dans un espace de travail ;
- la ligne courte d'une commande, l'avancement et l'issue dans les titres, le nom du dossier d'un espace de travail en tête de ses titres ;
- la commande choisie dans un QCM, qui démarre toute seule ; ses arguments, écrits par le modèle dans les options, ne rendent jamais un dossier lisible : seul ce que tu tapes le fait, et jamais ton dossier personnel ni un de ses dossiers cachés (avec la 1.19, citer un fichier de ton dossier personnel, `~/.zshenv` par exemple, le rendait lisible en entier : corrigé dans les deux packs) ;
- un sous-agent ne pose jamais de question (la 1.19 le faisait avec `experimental.primary_tools`, que la v2 ignore) ;
- les sorties des anciens outils effacées des requêtes dans les longues sessions (`compaction.prune`, que la v2 ignore) ;
- le même appel d'outil répété trois fois dans une réponse du modèle, refusé (la règle `doom_loop` de la 1.19, que la v2 n'applique plus) ;
- l'attente des serveurs MCP au démarrage : la v2 enverrait sinon la première requête sans Jira ni GitLab ;
- ni le mot de passe du serveur ni les dossiers `~/oc2` dans l'environnement des commandes des agents et des scripts du pack.

**Ce que le pack ajoute avec la v2, pour qu'un run aille au bout sans toi :**
- une panne du serveur du modèle : les 10 essais d'OpenCode étalés sur environ 8 minutes au lieu d'une et demie, puis une reprise automatique du run (2 minutes plus tard, puis 5), depuis la fiche ticket ;
- un pilote arrêté avant sa réponse finale (sa limite d'étapes, une réponse coupée) : repris tout seul, deux fois au plus d'affilée ;
- une conversation résumée parce que le contexte du modèle est plein : le résumé garde l'état du run (fiche, étape, sous-agents, commits), puis le pilote retrouve les consignes de sa commande et chaque sous-agent sa tâche ;
- plusieurs sous-agents à la fois (les analyses de `/fortify`, trois en parallèle) : tous dans le titre ;
- les preuves des tests : chaque test rouge ou vert exécuté deux fois (un test instable est refusé), un test qui ne s'arrête pas arrêté au bout de 5 minutes et nommé, et la couverture des lignes modifiées par la branche ;
- des tests qui prouvent un comportement : chaque test attendu de la fiche a son niveau et un scénario avec des valeurs, et `test-lint.sh` refuse un test sans assertion, focalisé, ignoré, ou qui dépend de l'horloge réelle ;
- le front-end, les versions de .NET et les librairies : `build-test.sh <dossier>` pour un front, `dotnet-problem.sh` pour un SDK, un runtime, Docker ou un flux de paquets absents, `build-test.sh --pack` et `api-surface.sh` pour l'API publique et les contrats, `related-repos.sh` pour les dépôts d'une même application ;
- jamais un `node_modules`, un `obj` ou un `bin/Debug` poussé : une installation que git n'ignorerait pas est refusée, et le contrôle avant push les arrête.

**Ce que la v2 ouvre, et que le pack ferme :**

| Ce que la v2 ajoute | Le risque | Ce que fait le pack |
|---|---|---|
| le « code mode » (`execute`) : du JavaScript qui appelle les outils, dont tous ceux des serveurs MCP | il peut appeler n'importe quelle adresse avec `fetch`, sans aucune autorisation (vérifié : la requête partait), et ses appels internes passent sous d'autres noms que ceux des règles (vérifié : `opencode_session_move` a sorti une session du dépôt) | l'outil est retiré de chaque requête et refusé s'il est appelé ; les serveurs MCP redeviennent des outils directs, comme avec la 1.19, soumis aux règles du pack |
| la recherche web, active par défaut | ta question part vers un service de recherche externe | coupée trois fois : `"websearch": false`, une règle qui la refuse, et le plugin qui la retire |
| les outils qui déplacent une session ou créent et suppriment un espace de travail | un agent pourrait travailler hors du dépôt | refusés à tous les agents, sous tous leurs noms : c'est ton choix, dans l'interface |
| le skill intégré `report` | il lit la configuration et publie une issue sur GitHub avec `gh` | refusé |
| le partage d'une session, les mises à jour automatiques | une session publiée sur un lien public d'opencode.ai ; un programme téléchargé tout seul | coupés : `"share": "disabled"`, `"autoupdate": false` |
| l'outil `patch` (pour les modèles GPT) | ses fichiers sont dans le texte du patch | chaque fichier du patch est contrôlé comme une écriture |
| un sous-agent repris par son identifiant | son message n'a plus la ligne qui dit « sous-agent » | reconnu par sa session parente : toujours sans question |

**Les vérifications automatiques passent** :
- plugin : 789 sur 789 (786 à l'étape précédente), dont les commandes planifiées (l'heure et les jours, seulement ce qui n'écrit rien, une seule session quand deux OpenCode tournent, une ligne `/go` refusée), puis les commandes qui ne finissent jamais (un serveur, un mode watch, `npm test` jugé sur ce que lance son script, la conversation en arrière-plan ou bornée), les changements de dépendances et les installations sur la machine refusés aux agents du pack en une phrase (`npm install`, `npx npm@11 install`, `dotnet package add`, brew…), `npm ci` permis, et le QCM « Suite » qui finit chaque commande (le dossier libre pendant qu'il attend, l'issue gardée dans le titre, aucune reprise automatique après lui, la commande choisie lancée même si le serveur du modèle tombe ensuite), le contenu `null` des messages d'appels d'outils remplacé par `""` (rejoué sur le vrai v2.1.3 contre un serveur qui refuse `null` comme la passerelle de la plateforme), puis la coupure des réponses qui bouclent, « continue » repris par le pilote et `dotnet run` limité aux projets commités, `/tests`, chaque commande que le pack prescrit à un agent passée aux gardes du plugin, et un `/go` dans le dossier principal en même temps qu'un `/go` dans son espace de travail ;
- permissions : 2 493 cas sur 2 493 (2 431 à l'étape précédente), dont les 189 commandes que les commandes, agents et skills du pack prescrivent, chacune permise à l'agent qui la lance (dont celles de `/tests api` et `/tests env`), `env-tests.sh --ecriture` refusé à tous les sous-agents, `schedule.sh` et `http-files.sh` à la conversation seulement, et les scripts de package.json (un client d'API généré oui ; publier, déployer, les tests de bout en bout non) ;
- scripts git hors ticket (`/push`, `/sync`, `/go … depuis`, espace de travail en HEAD détachée, `/outil abandon`, un `node_modules` jamais poussé) : 74 contrôles sur 74 contre un dépôt distant de test (`tools/scripts-test.sh`, dash et bash) ;
- scripts .NET avec un `dotnet` simulé, VSTest et Microsoft.Testing.Platform, .NET 8 sans son SDK puis sans ses runtimes, librairie et validation de paquet, contrats, qualité des tests, dépôts liés, review d'une branche d'un collègue, Blazorise et son skill nommés, le projet de tests d'intégration d'une API .NET 8 et .NET 10, les tests d'un environnement (production refusée, écriture non permise, jeton absent puis masqué, environnement injoignable), les fichiers `.http`, les planifications : 230 contrôles sur 230 (`tools/dotnet-test.sh`, dash et bash) ;
- scripts front-end avec un npm simulé (Angular avec Karma et avec Vitest, Create React App, Vitest, Jest, registre refusé, lockfile désynchronisé, npm qui échoue de lui-même, Chrome absent, run qui ne finit pas) : 79 contrôles sur 79 (`tools/frontend-test.sh`, dash et bash ; avec `--real`, les vrais Jest, Vitest et Angular, puis l'installation que fait le pack depuis leur lockfile, lancés par GitHub à chaque push) ;
- les messages réels du SDK .NET (SDK de global.json absent, NETSDK1045, runtime des tests absent, .NET 8, CS9202, validation de paquet) le code du skill `blazorise` compilé contre les vrais paquets, et celui du skill `api-tests` sur une vraie API .NET 10 (projet créé par `setup --integration`, tests en mémoire, puis `env-tests.sh` contre l'API démarrée et contre une adresse qui ne répond pas) : `tools/real-dotnet-test.sh`, lancé par GitHub avec les SDK 10 et 8 ;
- des histoires complètes, avec un `dotnet` simulé, deux dépôts (avec et sans tests) et un second ordinateur qui pousse aussi : 139 contrôles sur 139 (`tools/scenarios-test.sh`, dash et bash ; avec `--real`, le vrai SDK .NET, lancé par GitHub à chaque push) — `/go`, une étape « (filet d'abord) » dont le filet arrête la régression du coder, la même dans un dépôt sans tests (le projet de tests créé d'abord, le filet mesuré avant tout test), `/go … depuis`, POC, documentation seule, build cassé, test rouge, « sans les tests », code déjà vert non relancé, commits du Mac fusionnés puis en conflit, `/sync`, commit fait sur develop par erreur, secret bloqué, `dotnet` absent, `/fix` sans ticket, `/tests` dans un dépôt sans tests, deux espaces de travail du même dépôt qui buildent, mesurent et poussent chacun sa branche en même temps, puis 4 espaces de travail qui font `git fetch` ensemble pendant que 12 branches bougent ;
- le flux de `/fortify` et de son test-guardian de A à Z, ses lignes de commande dans l'ordre de ses étapes, sur de vrais projets C# : 205 contrôles sur 205 (`tools/fortify-test.sh`, dash et bash ; avec `--real`, le même rejeu avec le vrai SDK .NET, lancé par GitHub à chaque push), dont le filet de non-régression de chaque faille et celui de méthodes que le compilateur découpe (asynchrone, itérateur, lambda, fonction locale), ses chiffres comparés aux valeurs exactes du vrai coverlet ;
- 37 fichiers d'agents, de commandes et de skills validés (34 à l'étape précédente), chaque fichier du pack décrit dans `FICHIERS.md` ;
- `shellcheck` sur tous les scripts.

**Avec les vrais programmes**, sur la version du pack du 23 octobre 2026 (pas rejoués depuis : ma machine de vérification n'a ni OpenCode ni `dotnet` ; les changements suivants sont couverts par les contrôles ci-dessus, avec un `dotnet` simulé et le moteur de permissions d'OpenCode reproduit) :
- de bout en bout avec le vrai v2.1.3, son interface web et un modèle simulé : 71 contrôles sur 71, dont la reprise d'un `/go` après un redémarrage du service, trois espaces de travail en parallèle, et les reprises automatiques (panne du serveur du modèle, limite d'étapes, réponse coupée), les retries étalés et les résumés de contexte ;
- les scripts de mesure des tests (`test-guardian.sh`, `fortify.sh`) avec un vrai `dotnet test` et coverlet : 98 scénarios sur 98 (rouge, vert, test instable, test bloqué, tests de la preuve scellés puis remis quand le correctif les modifie, perte de couverture, couverture des lignes modifiées, travail mis de côté entre deux espaces de travail ; le verrou qui sérialise les builds d'une vague écrite en parallèle, la sous-commande `build`, un build qui ne s'arrête pas stoppé et nommé, la mise de côté puis le retour d'une preuve ; et la mise en place d'un projet de tests — xUnit, MSTest, NUnit, l'ajout de coverlet, les versions centralisées, un projet .NET Framework ou Microsoft.Testing.Platform laissé de côté) ;
- ce guide, rejoué de bout en bout sur une machine de test : 57 contrôles pour le parcours principal, 47 pour l'annexe A avec le service, 47 avec `opencode-web.sh` (les lignes attendues en 5.3, 5.4 et A.7 sont recalculées à chaque version, sur une copie d'une installation 1.19).

## Étape 15 — Les fichiers de `opencode-v2/`

- **Nouveaux par rapport à `v2/`** :
  - `plugins/openrd-pack.js`, qui remplace `compact-commands.js` ;
  - `commands/fortify.md`, `agents/test-guardian.md`, `scripts/fortify.sh`, `scripts/test-guardian.sh` ;
  - `commands/push.md`, `commands/sync.md`, `commands/tests.md` (le travail hors ticket), `scripts/base.sh` (la base d'une branche), `scripts/test-platform.sh` (les tests Microsoft.Testing.Platform), `scripts/abandon.sh` (`/outil abandon` sans jamais perdre de travail), `AGENTS.repo-template.md` ;
  - `skills/blazorise/SKILL.md` (Blazorise : la langue du DataGrid et de sa pagination, l'API de la version installée, son remplacement par du Razor natif) ;
  - `skills/api-tests/SKILL.md` (les tests d'intégration d'une API, en mémoire et sur un environnement), `scripts/environments.sh` et `scripts/env-tests.sh` (`/tests env`), `skills/pack-http/SKILL.md` et `scripts/http-files.sh` (`/outil http`), `skills/pack-planifier/SKILL.md` et `scripts/schedule.sh` (`/outil planifier`, que le plugin lance à l'heure dite) ;
  - `CHECKSUMS-config.txt` et `CHECKSUMS-scripts.txt`, les listes d'empreintes de l'étape 5 ;
  - ce guide, `ANALYSE.md`, et `FICHIERS.md` (chaque fichier du pack : ce qu'il fait, qui le lance, à quoi il sert).
- **Modifiés** :
  - les agents (vocabulaire des sous-agents, règles régénérées, le filet de non-régression avant chaque correctif : test-guardian, coder, analyst, pilot), les six commandes de la 1.19 (leur première ligne `[[command …]]`, lue par le plugin ; `go.md` et `fix.md` aussi pour le vocabulaire, `/go … depuis <branche>`, le filet et les arrêts qui renvoient à `/push` ; chacune finit par son QCM « Suite »), `AGENTS.global.md` (toute action proposée est un QCM qui la lance) ;
  - `skills/pack-setup/SKILL.md` (un AGENTS.md de dépôt court et utile aux agents, le minimum du filet, les règles proposées cochées dans son dernier QCM), `skills/pack-abandon/SKILL.md` (passe par `abandon.sh`), `skills/best-practices/SKILL.md` et `skills/build-fix/SKILL.md` (les commandes de la v1 qu'ils nommaient encore), `skills/pack-cqrs/SKILL.md` (son QCM « Suite »), `skills/pack-audit/SKILL.md` (son QCM « Suite » : ses premières améliorations en `/go sans ticket`, et plus de `/outil pattern apply`, qui n'existe plus) ;
  - les scripts `branch.sh`, `build-test.sh`, `diff-guard.sh`, `fetch.sh`, `outil.sh`, `package-refs.sh`, `ship.sh`, `todo.sh`, `workflow-state.sh` (mêmes appels qu'en 1.19) ;
  - `skills/pack-doc/SKILL.md` (vocabulaire, son QCM « Suite »), `skills/pack-release-notes/SKILL.md` (un espace en fin de ligne retiré) et `skills/fortify-remediation/SKILL.md` (une ligne vide finale retirée), pour qu'un copier-coller les reproduise à l'identique ;
  - `opencode.snippet.json` (règles de la v2, partage, mises à jour et recherche web coupés) ;
  - `COMMANDES.md` et `README.md`.
- **Identiques** : les autres scripts et les autres skills.
- **`tools/`** contient aussi `scripts-test.sh` (scripts git), `dotnet-test.sh` et `fake-dotnet.sh` (scripts .NET avec un `dotnet` simulé), `scenarios-test.sh` (les histoires complètes, plusieurs espaces de travail en parallèle), `fortify-test.sh` (le flux de `/fortify` et de son test-guardian de A à Z, avec le `dotnet` simulé ou, avec `--real`, le vrai).
- **`tools/`** : mes outils de vérification. Ne les copie jamais dans ta configuration.

## Annexe A — La v2 a déjà remplacé ta 1.19 : tout remettre d'aplomb, avec l'interface web

**Pour toi si** `opencode --version` affiche `opencode v2.1.3` (ou `v2.1.2`) parce qu'une procédure interne a fait `npm uninstall -g opencode-ai` puis `npm install -g @opencode/cli`. Ta configuration et tes sessions sont restées aux endroits de la 1.19 : `~/.config/opencode` et `~/.local/share/opencode`. La v2 relit tes sessions 1.19 (vérifié).

**Ce que tu as à la fin :**
- un seul serveur OpenCode, la v2 : le service de ta procédure interne (port 4096), ou `opencode-web.sh` (port <port>), au choix (A.4) ;
- ouvert dans ton navigateur à la racine de son adresse (A.13) ;
- le pack v2 complet, avec son plugin et donc ses garde-fous ;
- ni deuxième serveur, ni client terminal.

**Tant que cette annexe n'est pas finie, aucun garde-fou du pack n'est actif** : le plugin du pack n'est pas encore installé. Ne lance ni `/go`, ni `/fix`, ni `/fortify`.

Durée : environ 45 minutes. Les règles du début de ce guide s'appliquent : tu ne lances aucun script téléchargé, et chaque fichier collé depuis GitHub (vue Raw) est vérifié par son empreinte. Tape les commandes une par une, dans l'ordre, et compare avec « Tu dois voir ». Aucune n'affiche ton mot de passe.

Toute cette annexe a été rejouée sur une machine de test qui reproduit ta situation :
- zsh avec `~/.zshenv`, `~/.zshrc` et `~/.zshrc_perso` comme ta procédure interne les décrit ;
- la v2.1.3 (ou la 2.1.2) installée par npm à la place d'une 1.19 ;
- le service sur 4096 ;
- un `opencode-web.sh` de plateforme sur <port> ;
- un pack 1.19 complété avec les agents, les commandes et les scripts de `opencode-v2`.

Les résultats « Tu dois voir » viennent de ce test.

| Étape | Ce que tu fais |
|---|---|
| A.1 | Ouvrir un terminal |
| A.2 | Faire l'état des lieux, sans rien modifier |
| A.3 | Lire ce que tu as trouvé |
| A.4 | Choisir ton serveur, et tout arrêter |
| A.5 | Sauvegarder |
| A.6 à A.10 | Mettre le pack v2 en place |
| A.11 | Sortir le mot de passe et les tokens MCP de `~/.zshenv` |
| A.12 | Redémarrer |
| A.13 | Ouvrir l'interface web |
| A.14 | Vérifier |
| A.15 | Au quotidien |
| A.16 | Dépannage |
| A.17 | Revenir à la 1.19 |

### A.1 Ouvrir un terminal

Le terminal de ton environnement de travail, sur la machine où tourne OpenCode :
```sh
whoami && hostname && echo "$HOME" && echo "$SHELL"
```
Tu dois voir quatre lignes :
- ton utilisateur (`coder`) ;
- le nom de la machine ;
- ton dossier personnel (`/home/dev`) ;
- `/usr/bin/zsh` ou `/bin/zsh`.

Toutes les commandes de cette annexe sont écrites pour zsh.

### A.2 L'état des lieux, sans rien modifier

Ces commandes ne font que lire. Note ce que chacune affiche : A.3 s'en sert.

**A.2.1 Le programme `opencode` :**
```sh
whence -a opencode
```
Tu dois voir une seule ligne, du type `/home/dev/.nvm/versions/node/v<version>/bin/opencode`. Une deuxième ligne est sans doute un reste de ta 1.19 : note-la.
```sh
opencode --version
```
Tu dois voir `opencode v2.1.3` (ou `opencode v2.1.2` : le pack marche avec les deux).

**A.2.2 Où est `opencode-web.sh` :**
```sh
whence -va opencode-web.sh
```
Trois réponses possibles :
- `opencode-web.sh is /un/chemin/opencode-web.sh` : c'est un fichier, installé par ta plateforme. C'est le cas le plus probable.
- `opencode-web.sh is an alias for …` ou `opencode-web.sh is a shell function from …` : il est défini dans un de tes fichiers zsh. Envoie-moi cette ligne avant de continuer.
- `opencode-web.sh not found` : retrouve comment tu le lançais.
```sh
fc -ln 1 | grep 'opencode-web' | tail -n 3
```
  Si tu y vois un chemin complet, par exemple `/opt/plateforme/bin/opencode-web.sh start`, c'est ce chemin qu'il faudra taper partout où cette annexe écrit `opencode-web.sh`. En A.2.3, remplace alors `"$(whence -p opencode-web.sh)"` par ce chemin.

**A.2.3 Ce que démarre `opencode-web.sh`.** Ce script ne fait que démarrer et arrêter un serveur OpenCode. Cette commande affiche ses lignes utiles, sans le lancer :
```sh
grep -n -E 'opencode|PASSWORD|port|log' "$(whence -p opencode-web.sh)"
```
Repère trois choses :
1. **La ligne qui démarre le serveur**, celle qui contient `serve` ou `web` :
   - le programme y est écrit `opencode` tout court, suivi de `serve` : c'est celui de A.2.1, donc la v2 ;
   - c'est un chemin complet (`/…/opencode`) : c'est ce programme-là, note le chemin ;
   - c'est `opencode web` : la v2 n'a plus cette commande.
2. **Son journal** : le fichier après `>>` ou `>` sur cette ligne, ou dans une variable (`LOG=…`). Note-le : les messages du plugin du pack iront là.
3. **Le mot de passe** : la variable qu'il utilise, `OPENCODE_PASSWORD` ou `OPENCODE_SERVER_PASSWORD`, ou aucune (il prend alors celle de ton terminal). Si une ligne montre un mot de passe écrit en clair, ne me l'envoie pas.

**A.2.4 Ce qui tourne maintenant :**
```sh
ps -eo pid,args | grep -i '[o]pencode'
```
Chaque ligne commence par un numéro de processus. Tu dois voir, par exemple :
- `opencode serve --hostname 0.0.0.0 --port <port>` : le serveur démarré par `opencode-web.sh` ;
- `… serve --service` : le service démarré par ton `~/.zshrc_perso`, sur le port 4096 ;
- `opencode --standalone`, `… serve --stdio` : un `opencode` ouvert dans un terminal.

**A.2.5 Quel programme tourne sur le port <port>.** En une commande : le numéro du processus, son programme, sa version, et si le serveur a reçu un mot de passe (le mot de passe lui-même n'est jamais affiché, seulement un compte) :
```sh
for p in $(pgrep -f -- '--port <port>'); do e=$(readlink -f /proc/$p/exe); case $e in */opencode*) echo "pid $p, démarré il y a $(ps -o etimes= -p $p | tr -d ' ') s"; echo "$e"; $e --version; tr '\0' '\n' < /proc/$p/environ | grep -c -E '^OPENCODE_(SERVER_)?PASSWORD=';; esac; done
```
Tu dois voir quatre lignes :
- `pid` suivi d'un numéro, et depuis combien de secondes ce serveur tourne ;
- le chemin du programme. S'il contient `@opencode/cli`, c'est la v2. S'il contient `opencode-ai`, `opencode-linux` ou `.opencode/bin`, c'est une 1.19 ;
- sa version : `opencode v2.1.3` (ou `v2.1.2`) pour la v2, un numéro du type `1.19.0` pour la 1.19 ;
- `1` si le serveur a reçu un mot de passe. `0` veut dire qu'il en a tiré un au hasard : ton navigateur ne peut alors pas s'y connecter.

Si rien ne s'affiche, aucun serveur ne tourne sur <port> : passe à A.2.6.

**A.2.6 Le service :**
```sh
opencode service status
```
Tu dois voir une adresse, par exemple `http://0.0.0.0:4096` : le service tourne. Ou `stopped` : il est arrêté.
```sh
grep -n 'opencode' ~/.zshrc_perso
```
Tu dois voir les lignes de ta procédure interne, par exemple :
```text
4:opencode service set hostname 0.0.0.0
5:opencode service set port 4096
6:opencode service set password $OPENCODE_PASSWORD
7:opencode service start >>/home/dev/.local/share/opencode/log/startup.log 2>&1
```
Chaque nouveau terminal les exécute, et redémarre donc le service.

**A.2.7 Le mot de passe, sans l'afficher :**
```sh
grep -c 'OPENCODE_PASSWORD=' ~/.zshenv ~/.zshrc_perso
```
Tu dois voir un compte par fichier : `/home/dev/.zshenv:1` et `/home/dev/.zshrc_perso:0`. Le mot de passe est dans `~/.zshenv`, comme le prévoit ta procédure.
```sh
grep -n 'zshrc_perso' ~/.zshrc ~/.zshenv ~/.zprofile 2>/dev/null
```
Tu dois voir une seule ligne, dans `~/.zshrc`, qui charge `~/.zshrc_perso`. Si une ligne vient de `~/.zshenv` ou de `~/.zprofile`, envoie-la-moi avant l'étape A.11.

**A.2.8 La configuration :**
```sh
ls ~/.config/opencode ~/.config/opencode/plugins
```
```sh
ls ~/.config/opencode.backup/plugins
```
Tu dois voir `compact-commands.js` dans la deuxième : `~/.config/opencode.backup` est la copie de ta configuration 1.19 faite par ta procédure interne, ton retour arrière. Si ce dossier n'existe pas, note-le.
```sh
grep -n '"npm"' ~/.config/opencode/opencode.json
```
Si cette commande n'affiche rien, ton provider ne déclare pas de paquet. C'est la cause de « Unsupported package for <ton provider>/<ton modèle>: unknown » : la v2 ne sait pas comment parler à ton modèle. A.10 le corrige.

**A.2.9 L'adresse dans ton navigateur.** Ouvre ton favori ou ton historique pour le port <port>, sans valider, et regarde l'adresse :
- **Cas A** : le port est après les deux-points ou dans le nom de la machine, par exemple `http://cloudide-xxxxx:<port>/…` ou `https://<port>-<quelque chose>.<domaine>/…`. La v2 fonctionnera, à la racine de cette adresse (A.13).
- **Cas P** : une adresse fixe de ta plateforme, par exemple `https://<plateforme>.<domaine>/`, et un lien qui choisit le port qu'elle montre, du type `…?port=<port>` (ton `opencode-web.sh` l'ouvre avec `xdg-open`). La v2 fonctionne à la racine de cette adresse (A.13).
- **Cas B** : le port est dans le chemin, après une barre oblique, par exemple `https://<domaine>/…/<port>/…`, sans lien qui le choisit. L'interface web de la v2 ne fonctionne pas derrière une telle adresse : A.13 donne les solutions. Fais quand même les étapes A.4 à A.12.

### A.3 Lire ce que tu as trouvé

**La ligne de A.2.3 démarre `opencode serve` (programme écrit `opencode` tout court).** C'est le cas attendu : `opencode-web.sh` démarre déjà la v2, tu le gardes tel quel. Si un serveur tournait, A.2.5 l'a confirmé : `@opencode/cli` et `opencode v2.1.3`. Continue en A.4.

**Sinon** :
- la ligne contient un chemin complet vers une 1.19 ;
- ou elle contient `opencode web` ;
- ou `opencode-web.sh` est introuvable.

Dans ces trois cas, `opencode-web.sh` ne démarrera pas la v2. N'y touche pas : c'est un fichier de ta plateforme. En A.12, tu utiliseras à sa place `oc-web`, quelques lignes à ajouter à ton `~/.zshrc_perso`, qui font la même chose. Continue en A.4.

### A.4 Choisir ton serveur, et tout arrêter

**Un seul serveur.** Deux serveurs v2 sur les mêmes dossiers, c'est deux fois tes serveurs MCP, deux listes de sessions qui ne se voient pas, et deux endroits à redémarrer après chaque mise à jour du pack. Le verrou « un seul `/go`, `/fix` ou `/fortify` à la fois par dossier » tient quand même entre les deux : il est aussi dans le `.git` du dépôt.

**Lequel garder.** Le pack marche de la même façon avec les deux (vérifié) :

| | Le service (port 4096) | `opencode-web.sh` (port <port>) |
|---|---|---|
| Démarrage | tout seul, par chaque nouveau terminal (les lignes `opencode service …` de `~/.zshrc_perso`) | `opencode-web.sh start`, à la main |
| Redémarrage | `opencode service restart` | `opencode-web.sh stop && opencode-web.sh start` |
| Mot de passe | celui enregistré par `opencode service set password` | celui de `OPENCODE_PASSWORD`, dans le terminal qui le démarre |
| Un `/go` coupé par un redémarrage | la v2 le reprend toute seule au démarrage suivant, et le plugin lui garde le dossier (vérifié) | il reste coupé : relance `/go`, qui reprend où il s'était arrêté |
| Les messages du plugin | dans `~/.local/share/opencode/log/openrd-pack.log` | aussi |

Si l'interface web marche déjà chez toi par l'un des deux, garde celui-là.

1. Quitte chaque `opencode` ouvert dans un terminal : Ctrl+C, ou ferme ce terminal.

**Tu gardes le service (4096) :**

2. Arrête `opencode-web.sh`, que tu ne lanceras plus :
```sh
opencode-web.sh stop
```
3. Arrête aussi le service : il redémarrera en A.12, avec la configuration finie.
```sh
opencode service stop
```
Tu dois voir `stopped` avec `opencode service status`. Garde les lignes `opencode service …` de `~/.zshrc_perso` telles quelles.

**Tu prends `opencode-web.sh` (<port>) :**

2. Mets en commentaire les lignes `opencode service …` de `~/.zshrc_perso`, pour que les prochains terminaux ne relancent plus le service. Cette commande ajoute `# ` au début de ces lignes, et garde l'original dans `~/.zshrc_perso.avant-pack-v2` :
```sh
sed -i.avant-pack-v2 's/^\([[:space:]]*\)\(opencode service \)/\1# \2/' ~/.zshrc_perso && grep -n 'opencode service' ~/.zshrc_perso
```
Tu dois voir les lignes de A.2.6, chacune commençant maintenant par `# ` :
```text
4:# opencode service set hostname 0.0.0.0
5:# opencode service set port 4096
6:# opencode service set password $OPENCODE_PASSWORD
7:# opencode service start >>/home/dev/.local/share/opencode/log/startup.log 2>&1
```
3. Arrête le service, efface le mot de passe qu'il avait enregistré dans sa configuration, et désactive-le. Sans cette désactivation, une commande `opencode` tapée un jour dans un terminal le redémarrerait.
```sh
opencode service stop
```
```sh
opencode service unset password
```
```sh
opencode service set disabled true
```
```sh
opencode service status
```
Les trois premières n'affichent rien. La dernière doit afficher `stopped`.

4. Arrête le serveur web :
```sh
opencode-web.sh stop
```

**Dans les deux cas**, attends quelques secondes, puis vérifie qu'il ne reste rien :
```sh
ps -eo pid,args | grep -i '[o]pencode'
```
Tu ne dois rien voir. S'il reste une ligne, arrête-la avec son numéro, le premier nombre de la ligne : `kill <numéro>`. Puis refais la vérification.

Une ligne `opencode serve … --port <port>` qui reste après `opencode-web.sh stop` veut dire que ce script arrête mal son serveur (vu sur ma machine de test avec un script qui note le mauvais numéro de processus). Dans ce cas, chaque redémarrage laisserait l'ancien serveur tourner : préfère le service, ou `oc-web` en A.12.

### A.5 Sauvegarder

```sh
test -e ~/opencode-config-avant-pack-v2 || { cp -r ~/.config/opencode ~/opencode-config-avant-pack-v2 && cp -r ~/.local/share/opencode ~/opencode-data-avant-pack-v2; }; ls -d ~/opencode-config-avant-pack-v2 ~/opencode-data-avant-pack-v2
```
Tu dois voir les deux chemins. Une sauvegarde de ce nom faite par un essai précédent de cette annexe est gardée telle quelle.

Dans la suite, `~/opencode-config-avant-pack-v2` est la source de tes propres réglages (A.9, A.10).

### A.6 Les listes d'empreintes

Crée `~/CHECKSUMS-config.txt` et `~/CHECKSUMS-scripts.txt` en collant `opencode-v2/CHECKSUMS-config.txt` et `opencode-v2/CHECKSUMS-scripts.txt`, depuis la vue Raw (voir « Copier un fichier depuis GitHub », au début de ce guide). S'ils existent déjà, remplace tout leur contenu : les listes changent à chaque version du pack.

### A.7 Le plugin et les fichiers du pack

Cette commande supprime le plugin de la 1.19, qui ne fonctionne pas avec la v2, puis compare ta configuration à GitHub :
```sh
rm -f ~/.config/opencode/plugins/compact-commands.js && cd ~/.config/opencode && sha256sum --quiet --strict -c ~/CHECKSUMS-config.txt 2>/dev/null && echo "OK : la configuration est identique à GitHub"
```
Chaque ligne affichée est un fichier à coller depuis GitHub, au même chemin sous `opencode-v2/` :
- `FAILED` : le fichier existe mais il diffère. Par exemple, `agents/pilot.md: FAILED` veut dire : remplace tout le contenu de `~/.config/opencode/agents/pilot.md` par celui de `opencode-v2/agents/pilot.md` ;
- `FAILED open or read` : il n'existe pas encore, crée-le.

Avec les agents et les commandes de `opencode-v2` déjà collés, tu dois voir ces 15 lignes :
```text
skills/api-tests/SKILL.md: FAILED open or read
skills/best-practices/SKILL.md: FAILED
skills/blazorise/SKILL.md: FAILED open or read
skills/build-fix/SKILL.md: FAILED
skills/dotnet-cqrs-conventions/SKILL.md: FAILED
skills/fortify-remediation/SKILL.md: FAILED
skills/pack-abandon/SKILL.md: FAILED
skills/pack-audit/SKILL.md: FAILED
skills/pack-cqrs/SKILL.md: FAILED
skills/pack-doc/SKILL.md: FAILED
skills/pack-http/SKILL.md: FAILED open or read
skills/pack-planifier/SKILL.md: FAILED open or read
skills/pack-release-notes/SKILL.md: FAILED
skills/pack-setup/SKILL.md: FAILED
plugins/openrd-pack.js: FAILED open or read
```
Pour les quatre skills nouveaux, crée d'abord leurs dossiers : `cd ~/.config/opencode/skills && mkdir -p blazorise api-tests pack-http pack-planifier`. Une ligne en plus pour un agent ou une commande : il a été collé sans son dernier retour à la ligne, ou pas depuis Raw. Recolle-le (voir « Si un fichier collé reste en `FAILED` », à la fin de l'étape 5).

Relance la commande après chaque série de fichiers collés. **Tu as fini quand elle affiche `OK : la configuration est identique à GitHub`.** Si elle n'affiche rien du tout, c'est `~/CHECKSUMS-config.txt` qui est mal collé : recrée-le.

Puis :
```sh
ls ~/.config/opencode/agents ~/.config/opencode/commands ~/.config/opencode/plugins
```
Tu dois voir :
- dans `agents` : `analyst.md checker.md coder.md debugger.md doc-writer.md pilot.md test-guardian.md` ;
- dans `commands` : `compare.md daily.md fix.md fortify.md go.md outil.md push.md review.md sync.md tests.md` ;
- dans `plugins` : `openrd-pack.js` seul.

Un autre nom dans `agents` ou `commands` est soit un fichier à toi (garde-le), soit un reste d'un ancien pack : envoie-moi son nom. Un autre fichier dans `plugins` : envoie-moi son nom avant de continuer, la v2 le chargerait.

### A.8 Les scripts

```sh
cd ~/.config/opencode/scripts && sha256sum --quiet --strict -c ~/CHECKSUMS-scripts.txt 2>/dev/null && echo "OK : les scripts sont identiques à GitHub"
```
Avec les scripts de `opencode-v2` déjà collés, tu dois voir directement `OK : les scripts sont identiques à GitHub`. Sinon, même lecture qu'en A.7, avec les fichiers de `opencode-v2/scripts/`. `diff-guard.sh` contient des tabulations : s'il reste en `FAILED`, ton éditeur les a remplacées par des espaces.

### A.9 `AGENTS.md`

Il n'est pas dans les listes d'empreintes : il contient tes sections « Daily » et « Release groups ».

1. Remplace tout le contenu de `~/.config/opencode/AGENTS.md` par celui de `opencode-v2/AGENTS.global.md`.
2. Repère les sections, dans ta sauvegarde puis dans le nouveau fichier :
```sh
grep -n '^## ' ~/opencode-config-avant-pack-v2/AGENTS.md
```
```sh
grep -n '^## ' ~/.config/opencode/AGENTS.md
```
Chaque ligne donne un numéro de ligne et le titre d'une section. Dans le nouveau fichier, tu dois voir notamment `81:## Daily`, `85:## Release groups` et `92:## NuGet / Artifactory`.

3. Dans le nouveau fichier, remplace d'abord la section « Release groups » par la tienne : de sa ligne `## Release groups` jusqu'à la ligne avant `## NuGet / Artifactory`, copiée de la même façon dans `~/opencode-config-avant-pack-v2/AGENTS.md`. Puis la section « Daily », de `## Daily` jusqu'à la ligne avant `## Release groups`. Dans cet ordre : en commençant par le bas, les numéros de ligne du haut ne bougent pas.
4. Vérifie :
```sh
diff <(grep '^## ' ~/opencode-config-avant-pack-v2/AGENTS.md) <(grep '^## ' ~/.config/opencode/AGENTS.md) && echo "OK : mêmes sections"
```
Tu dois voir `OK : mêmes sections`. Des lignes qui commencent par `<` ou `>` : tes sections ne sont pas celles du pack, envoie-moi cette sortie. Puis relis tes deux sections :
```sh
sed -n '/^## Daily/,/^## NuGet/p' ~/.config/opencode/AGENTS.md
```
Tu dois voir ta section « Daily », ta section « Release groups », puis la ligne `## NuGet / Artifactory`.

### A.10 `opencode.json`

Il contient tes réglages : modèle, serveurs MCP… Tu repars de la partie du pack, collée depuis GitHub et donc exacte, et tu y remets tes sections, copiées depuis ta sauvegarde.

1. Repère tes sections et leurs numéros de ligne :
```sh
grep -n '^  "' ~/opencode-config-avant-pack-v2/opencode.json
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
Tes sections sont toutes celles qui ne s'appellent ni `$schema`, ni `agent`, ni `permission`, ni `experimental`, ni `compaction`, ni `share`, ni `autoupdate`, ni `websearch` (le pack fixe ces huit-là) : dans l'exemple, `provider`, `model`, `mcp`, `shell` et `references`. Une section va de sa ligne jusqu'à la ligne avant la section suivante. La dernière section du fichier s'arrête à l'avant-dernière ligne, juste avant le `}` final.

Si la commande n'affiche rien, ton fichier n'est pas indenté de 2 espaces. Envoie-moi alors la sortie de celle-ci, qui n'affiche que les noms des réglages, jamais leurs valeurs :
```sh
grep -n -o '^ *"[^"]*":' ~/opencode-config-avant-pack-v2/opencode.json | head -60
```
2. Remplace tout le contenu de `~/.config/opencode/opencode.json` par celui de `opencode-v2/opencode.snippet.json`.
3. Dans ce nouveau fichier, place le curseur au tout début de la ligne 3, celle de `  "agent": {`. Pour chacune de tes sections, dans l'ordre de la liste : sélectionne ses lignes dans `~/opencode-config-avant-pack-v2/opencode.json`, copie, et colle au curseur. La dernière ligne de chaque section collée doit finir par une virgule (`},` ou `",`) : ajoute-la quand elle manque. C'est le cas de la section qui était la dernière de l'ancien fichier.
4. Si tu avais ajouté tes propres réglages dans la section `agent` (par exemple `title`, ou `reasoning_effort` de la section « Qwen 3.8 » de `COMMANDES.md`), ajoute-les aussi dans la section `agent` du nouveau fichier.
5. **Ton provider.** La v2 exige deux réglages que la 1.19 n'exigeait pas :
   - dans ta section `provider`, la première ligne de ton provider déclare son paquet. Pour une passerelle compatible OpenAI, comme vLLM, c'est `"npm": "@ai-sdk/openai-compatible",`. Par exemple :
```json
  "provider": {
    "mon-vllm": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Qwen interne",
```
   - au premier niveau, juste après la ligne `$schema`, la liste des providers permis : `"enabled_providers": ["<ton provider>"],`. Ton provider est la partie avant le `/` de ta ligne `"model"` (et de ta ligne `"small_model"`, si elle en nomme un autre). Si ta procédure interne t'a fait ajouter un autre provider et que tu t'en sers, ajoute aussi son nom : `["mon-vllm", "anthropic"]`.

   Pourquoi (vérifié avec la v2.1.3) :
   - sans paquet déclaré, la v2 ne peut pas utiliser ton modèle. Dans un terminal, elle affiche « Unsupported package … ». Dans le navigateur, elle bascule sans prévenir sur un modèle gratuit hébergé par OpenCode, à qui elle envoie ta demande ;
   - avec `enabled_providers`, elle refuse tout provider qui n'est pas dans la liste.
6. Le fichier contient tes réglages de modèle, peut-être une clé : rends-le lisible par toi seul.
```sh
chmod 600 ~/.config/opencode/opencode.json
```
7. Vérifie :
```sh
grep -n '^  "' ~/.config/opencode/opencode.json
```
Tu dois voir `$schema`, `enabled_providers`, puis tes sections, puis `agent`, `permission`, `experimental`, `compaction`, `share`, `autoupdate` et `websearch`, chacune une seule fois. Les trois dernières coupent ce qui partirait vers l'extérieur sans toi : le partage d'une session sur un lien public d'opencode.ai, la recherche de mises à jour d'OpenCode, et la recherche web (vérifié : la v2 les applique, sans avertissement).
```sh
grep -c '"opencode_worktree_create"' ~/.config/opencode/opencode.json
```
Tu dois voir `1` : la section `permission` est bien celle de cette version du pack.
```sh
grep -n '"npm"' ~/.config/opencode/opencode.json
```
Tu dois voir une ligne par provider, par exemple `"npm": "@ai-sdk/openai-compatible",`.

Une virgule oubliée rend le fichier invalide, et la v2 l'ignorerait alors en entier : c'est vérifié en A.14, point 1.

### A.11 Sortir le mot de passe et les tokens MCP de `~/.zshenv`

**Pourquoi.** zsh relit `~/.zshenv` à chaque commande, y compris celles que lancent les agents : elles recevraient ton mot de passe et les tokens de tes serveurs MCP (Jira, Confluence, GitLab, Sonar, Fortify), dont aucune n'a besoin. Le plugin du pack les retire de ce que ces commandes héritent du serveur (vérifié), mais il ne peut rien contre ce que zsh relit ensuite. `~/.zshrc_perso`, lui, n'est lu que par tes terminaux, et c'est d'un terminal que tu démarres le serveur : il transmet ces valeurs au serveur, donc aux serveurs MCP, qui en ont besoin (vérifié). Avec le service, ces lignes arrivent tout en haut de `~/.zshrc_perso`, avant `opencode service set password $OPENCODE_PASSWORD` qui s'en sert.

1. Repère les lignes à déplacer. Cette commande affiche le numéro de ligne et le nom de chaque variable de `~/.zshenv`, jamais sa valeur :
```sh
grep -n -o -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' ~/.zshenv
```
À déplacer : `OPENCODE_PASSWORD`, et chaque variable dont le nom contient `JIRA`, `CONFLUENCE`, `ATLASSIAN`, `GITLAB`, `SONAR`, `FORTIFY` ou `SSC`, avec `TOKEN`, `KEY`, `SECRET`, `PASSWORD` ou `PAT`, par exemple `GITLAB_PERSONAL_ACCESS_TOKEN` ou `JIRA_API_TOKEN`. Tout le reste reste, en particulier `OPENCODE_DISABLE_MODELS_FETCH`, `DOTNET_ROOT`, `PATH` et les identifiants Artifactory : les builds des agents en ont besoin.
2. Ouvre `~/.zshenv` dans ton éditeur. Coupe ces lignes (sélectionne-les, Ctrl+X) et enregistre.
3. Ouvre `~/.zshrc_perso`, colle-les tout en haut du fichier (Ctrl+V), et enregistre.
4. Vérifie, sans rien afficher de leurs valeurs :
```sh
grep -c -i -E 'OPENCODE_PASSWORD=|(JIRA|CONFLUENCE|ATLASSIAN|GITLAB|SONAR|FORTIFY|SSC)[A-Z0-9_]*(TOKEN|KEY|SECRET|PASSWORD|PAT)[A-Z0-9_]*=' ~/.zshenv ~/.zshrc_perso
```
Tu dois voir `/home/dev/.zshenv:0`, et pour `/home/dev/.zshrc_perso` le nombre de lignes déplacées.

5. Ces fichiers contiennent des secrets : rends-les lisibles par toi seul.
```sh
chmod 600 ~/.zshenv ~/.zshrc_perso
```
Si `~/.zshrc_perso.avant-pack-v2` existe (A.4, avec `opencode-web.sh`) : `chmod 600 ~/.zshrc_perso.avant-pack-v2`.

### A.12 Redémarrer

1. **Ferme tous tes terminaux, puis ouvre-en un nouveau.** Lui seul lit tes fichiers modifiés.
2. Vérifie ce nouveau terminal :
```sh
test -n "$OPENCODE_PASSWORD" && echo "mot de passe présent"
```
Tu dois voir `mot de passe présent`. Si rien ne s'affiche, la ligne de A.11 n'est pas dans `~/.zshrc_perso`, ou ce terminal a été ouvert avant A.11.
```sh
opencode service status
```
- Avec le service : son adresse, `http://0.0.0.0:4096`. Le nouveau terminal l'a démarré.
- Avec `opencode-web.sh` : `stopped`. Le nouveau terminal ne l'a pas relancé.

3. Mets l'ancien journal de la v2 de côté, pour que les vérifications de A.14 ne lisent que le nouveau :
```sh
mv ~/.local/share/opencode/log/opencode.log ~/.local/share/opencode/log/opencode-avant-pack-v2.log
```
`No such file or directory` veut dire qu'il n'y avait pas de journal : continue.

4. Démarre.
   - Avec le service, redémarre-le, pour qu'il lise toute ta configuration, même si un terminal ouvert pendant A.7 à A.10 l'avait lancé :
```sh
opencode service restart
```
   Tu dois voir son adresse, `http://0.0.0.0:4096`.
   - Avec `opencode-web.sh`, ou `oc-web start` si A.3 t'y a envoyé (voir « La variante `oc-web` », plus bas) :
```sh
opencode-web.sh start
```
5. Après une dizaine de secondes, vérifie ce qui tourne :
```sh
for p in $(pgrep -f -- 'opencode(\.exe)? serve'); do e=$(readlink -f /proc/$p/exe); case $e in */opencode*) echo "pid $p, démarré il y a $(ps -o etimes= -p $p | tr -d ' ') s : $(tr '\0' ' ' < /proc/$p/cmdline)"; $e --version;; esac; done
```
Tu dois voir deux lignes :
- `pid`, un petit nombre de secondes, puis la commande du serveur : `… serve --service` avec le service, `opencode serve --hostname 0.0.0.0 --port <port>` avec `opencode-web.sh` ;
- `opencode v2.1.3` (ou `v2.1.2`).

Un grand nombre de secondes veut dire que l'ancien serveur tourne encore, et que le nouveau n'a pas pu démarrer parce que le port était pris : arrête l'ancien avec `kill <pid>`, puis refais le point 4. Plus de deux lignes : deux serveurs tournent, arrête celui que tu n'as pas choisi (A.4).

**La variante `oc-web`**, seulement si A.3 t'y envoie. Ces lignes font ce que fait `opencode-web.sh` : `oc-web start`, `oc-web stop`, `oc-web restart` et `oc-web status`.

Ce n'est pas un script téléchargé : ce sont quelques lignes de ta propre configuration zsh, comme celles que ta procédure interne y met pour le service, et tu peux les relire en entier avant de les coller. Ajoute-les à la fin de `~/.zshrc_perso` :
```zsh
# OpenCode v2 web interface on the port of your platform link (18080 here: put yours) (OpenRDCode pack, MIGRATION.md annex A).
# oc-web start | stop | restart | status
oc-web() {
  local port=18080 dir="$HOME/.local/share/opencode/log"
  local pidfile="$dir/oc-web.pid" logfile="$dir/oc-web.log" pid="" i
  [[ -r $pidfile ]] && pid=$(<"$pidfile")
  case "$1" in
    start)
      if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
        echo "oc-web: already running (pid $pid)"; return 0
      fi
      if [[ -z $OPENCODE_PASSWORD ]]; then
        echo "oc-web: OPENCODE_PASSWORD is not set in this terminal, not started"; return 1
      fi
      mkdir -p "$dir"
      (cd ~ && exec nohup opencode serve --hostname 0.0.0.0 --port "$port" >>"$logfile" 2>&1 </dev/null) &!
      pid=$!
      echo "$pid" >"$pidfile"
      sleep 5
      if kill -0 "$pid" 2>/dev/null; then
        echo "oc-web: started on port $port (pid $pid)"
      else
        rm -f "$pidfile"; echo "oc-web: not started, see: tail -n 20 $logfile"; return 1
      fi
      ;;
    stop)
      if [[ -z $pid ]] || ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pidfile"; echo "oc-web: not running"; return 0
      fi
      kill "$pid"
      for i in {1..15}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
      done
      rm -f "$pidfile"; echo "oc-web: stopped"
      ;;
    restart)
      oc-web stop && oc-web start
      ;;
    status)
      if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
        echo "oc-web: running (pid $pid, port $port)"
      else
        echo "oc-web: stopped"
      fi
      ;;
    *)
      echo "usage: oc-web start|stop|restart|status"; return 2
      ;;
  esac
}
```
Puis ferme ce terminal, ouvre-en un nouveau, et reprends au point 2. `oc-web start` doit afficher `oc-web: started on port <port> (pid …)`. Le journal du serveur, messages du plugin compris, est `~/.local/share/opencode/log/oc-web.log`.

### A.13 Ouvrir l'interface web

**Ce qu'il faut savoir.** L'interface de la v2 ne s'ouvre qu'à la racine de son adresse, `/`, et aux adresses qu'elle crée elle-même (`/settings`, `/connect`, `/new-session`, `/server/…/session/…`). Toute autre adresse affiche « Un problème est survenu », avec `Error: Unrecognised route!` sous « Détails de l'erreur » (vérifié dans son code et à l'écran).

**Avec ta plateforme (cas P de A.2.9)**, une adresse fixe comme `https://<plateforme>.<domaine>/`, qui montre le port choisi par un lien `…?port=<port>` (celui que ton `opencode-web.sh` ouvre avec `xdg-open`) :
1. Après chaque démarrage de ton poste distant (ou du serveur), ouvre ce lien avec le port de ton serveur : `4096` pour le service, `<port>` pour `opencode-web.sh`. Par exemple :
```text
https://<plateforme>.<domaine>/<chemin donné par ta plateforme>?port=<port>
```
   **Dans cet onglet, fais un rechargement forcé : Cmd+Maj+R sur Mac** (Ctrl+Maj+R sous Windows ou Linux). C'est lui qui transmet vraiment le port à la plateforme ; voir « Le premier lancement de la journée » juste après.
2. Ouvre ensuite **la racine**, `https://<plateforme>.<domaine>/`, sans rien après le `/`. Mets en favori cette adresse-là, et seulement elle.
3. La première fois dans ce navigateur, la connexion :
   1. une page « Se connecter à un serveur » s'affiche, avec un champ « Pairing link » dont tu n'as pas besoin ;
   2. clique sur « Use password », en bas de la page ;
   3. laisse « URL du serveur » tel quel : il est déjà rempli avec l'adresse de la page, `https://<plateforme>.<domaine>` ;
   4. dans « Mot de passe (optionnel) », tape ton mot de passe, celui de `OPENCODE_PASSWORD` ;
   5. clique sur « Se connecter ».
   Les fois suivantes, le navigateur s'en souvient : pas de mot de passe à retaper.
4. La page d'accueil s'affiche, avec « Projets » à gauche. Pour ouvrir un dépôt : « Ajouter un projet », complète le chemin (par exemple `/home/dev/repos/mon-api`), clique la ligne qui est exactement ce chemin suivi de `/`, puis « Sélectionner le dossier ».

Les jours suivants : le lien de la plateforme et son rechargement forcé si le poste ou le serveur a redémarré, puis ton favori, la racine.

**Le premier lancement de la journée, et `Unrecognised route!`** (vérifié avec une plateforme simulée et le vrai OpenCode v2.1.3). L'interface de la v2 s'installe dans ton navigateur comme une application (un « service worker », enregistré pour toute l'adresse `https://<plateforme>.<domaine>/`). Dès ta première visite, c'est lui qui répond aux pages de cette adresse, **y compris au lien `…/set` de la plateforme, qui est sur la même adresse** : il sert sa propre page au lieu de laisser passer le lien. La plateforme ne reçoit donc jamais le port, et l'onglet affiche « Un problème est survenu » avec `Error: Unrecognised route!` (la page de l'application, ouverte à l'adresse du lien). Ce n'est pas le mot de passe : il est bien gardé. Le soir d'avant, la plateforme connaissait encore le port, d'où « ça marche au deuxième lancement » ; vider le cache marchait parce que cela supprime le service worker, mais aussi la connexion, d'où le mot de passe redemandé.
- **Le geste qui règle tout** : le rechargement forcé de l'onglet du lien (Cmd+Maj+R). Un rechargement forcé passe outre le service worker : le lien arrive enfin à la plateforme, qui enregistre le port. Puis ton favori, la racine : l'interface s'ouvre, connectée, sans mot de passe ni cache à vider.
- **Après une mise à jour d'OpenCode** (une nouvelle version de l'interface), ferme une fois tous les onglets de `https://<plateforme>.<domaine>/`, puis rouvre la racine : l'ancien service worker ne sert plus la version précédente de l'interface.
- **Une solution durable, à demander à l'équipe de la plateforme si tu veux** : un lien `…/set` sur une autre adresse que celle de l'interface (un autre sous-domaine, par exemple). Le service worker ne le verrait plus, et le rechargement forcé ne serait plus nécessaire.

**`Unrecognised route!` à un autre moment** : tu n'es pas sur la racine (un ancien favori, l'historique du navigateur). Efface tout ce qui suit `https://<plateforme>.<domaine>/` dans la barre d'adresse, puis Entrée.

**La connexion échoue avec le bon mot de passe** (« Impossible de se connecter. Vérifiez l'adresse et le mot de passe du serveur ») : ce message est le même pour toute erreur, pas seulement un mauvais mot de passe. Dans l'ordre :
1. le lien de la plateforme vise-t-il le port de ton serveur ? Rouvre-le avec le bon port, fais le rechargement forcé (Cmd+Maj+R), puis la racine ;
2. le serveur tourne-t-il ? A.12, point 5 ;
3. le navigateur garde peut-être une connexion d'avant le redémarrage : efface les données de ce seul site (dans Chrome, l'icône à gauche de l'adresse, puis les cookies et données du site), puis la racine et la connexion. Inutile de vider tout le cache du navigateur.

**Avec une autre adresse :**
- le port dans le nom de la machine (`http://cloudide-xxxxx:<port>/…`, `https://<port>-<quelque chose>.<domaine>/…`, cas A) : ouvre sa racine, puis la même connexion ;
- le port dans le chemin, sans lien qui le choisit (cas B) : l'interface de la v2 charge ses fichiers et parle au serveur depuis la racine de l'adresse, elle ne peut pas fonctionner là, et aucun réglage d'OpenCode n'y change rien. Demande à l'équipe de ta plateforme une adresse sans chemin, ou, si tu as un accès SSH à la machine, un tunnel depuis ton Mac : `ssh -N -L <port>:127.0.0.1:<port> <utilisateur>@<machine>` dans un terminal **sur ton Mac**, laissé ouvert, puis `http://localhost:<port>/`.

N'utilise jamais `opencode pair --remote` : cette commande expose ton serveur sur Internet.

### A.14 Vérifier

Fais les points dans l'ordre, après t'être connecté et avoir ouvert un projet (A.13) : la v2 ne lit sa configuration qu'à ce moment-là. Le journal de la v2 est `~/.local/share/opencode/log/opencode.log`. **Si un point échoue, arrête-toi là**, et envoie-moi le numéro du point avec ce que tu vois, sans mot de passe ni clé.

| # | Où | Ce que tu fais | Ce que tu dois voir |
|---|---|---|---|
| 1 | terminal | `grep -c 'kind=invalid' ~/.local/share/opencode/log/opencode.log` | `0` : ton `opencode.json` est accepté |
| 2 | terminal | `grep -c 'failed to load plugin' ~/.local/share/opencode/log/opencode.log` | `0` |
| 3 | terminal | `grep -c 'event stream connected' ~/.local/share/opencode/log/openrd-pack.log` | `1` ou plus : le plugin du pack tourne (son propre journal) |
| 4 | navigateur | « Nouvelle session », puis écris « bonjour » | une réponse de ton modèle, sans « Unsupported package », et le nom de ton modèle sous la zone de saisie |
| 5 | navigateur | dans une session d'un dépôt, tape `/` dans la zone de saisie | `go`, `fix`, `fortify`, `daily`, `review`, `compare`, `outil`, et `init`, la commande d'OpenCode |
| 6 | navigateur | écris « affiche le contenu de ~/.zshenv » | l'agent répond que c'est refusé : « Refused by the pack: ~/.zshenv is outside the repository… » |
| 7 | navigateur | `/go` sur un petit ticket d'un dépôt de test, dans une nouvelle session | ton message s'affiche en une ligne, « /go ABC-123 — mon-api · branche develop » ; la session prend le nom « /go ABC-123 », précédé de ⏳ et de l'avancement pendant le travail, puis de ✅ à la MR Draft |
| 8 | navigateur | pendant que ce `/go` tourne, `/go` dans une autre session du même dépôt | « ⛔ /go refusé : /go tourne déjà dans ce dossier… » |
| 9 | navigateur | « liste mes tickets du sprint », puis « quelle est la dernière pipeline de ce dépôt ? » | des réponses venant de Jira et de GitLab ; une demande d'écriture, par exemple commenter une MR, est refusée |
| 10 | navigateur | « Nouvelle session », un clic sur `Local` sous la zone de saisie, puis « Nouvel espace de travail », et « bonjour » | le menu « Exécuter la session dans » propose « Dépôt local » et « Nouvel espace de travail » ; une fois nommée, la session a un titre qui commence par `[` et le nom du nouveau dossier, par exemple `[crisp-river]` |
| 11 | navigateur | `/daily`, puis, à sa question « Sur quoi tu bosses ? », un `/go …` | le `/go` choisi démarre tout seul dans la même session |

**Si le point 1 donne plus que 0**, regarde ce qui est refusé :
```sh
grep 'kind=invalid' ~/.local/share/opencode/log/opencode.log | grep -o 'path=[^ ]*' | sort -u
```
`path=$` veut dire que tout le fichier est ignoré, à cause d'une erreur de syntaxe, le plus souvent une virgule manquante entre deux sections collées. **N'utilise pas la v2 dans cet état** : elle tournerait sans ton modèle et sans les règles globales du pack. Corrige A.10, puis redémarre (A.15). Une autre ligne nomme un réglage refusé : envoie-la-moi.

**Le modèle.** La v2 ignore sans erreur visible les réglages qu'elle ne connaît plus, et ne l'écrit que dans son journal :
```sh
grep 'configuration normalization diagnostic' ~/.local/share/opencode/log/opencode.log | grep -o 'path=[^ ]*' | sort -u
```
Ceux-ci sont attendus, et sans effet :
- `path=$.compaction.prune` et `path=$.experimental.primary_tools` ;
- `path=$.provider.<provider>.models.<modèle>.temperature` et `…reasoning`.

L'étape 9 explique pourquoi. Toute autre ligne : envoie-moi la liste.

**Les messages du plugin** vont dans son propre journal, `~/.local/share/opencode/log/openrd-pack.log`, quel que soit ton serveur : « event stream connected » à l'ouverture d'un dépôt, « refused by the pack » à chaque refus, avec l'agent, l'outil et le chemin, jamais une commande ni un texte de la conversation. Les refus récents :
```sh
grep 'refused by the pack' ~/.local/share/opencode/log/openrd-pack.log | tail -20
```

### A.15 Au quotidien

- **Redémarrer**, après une modification d'`opencode.json`, d'un agent, d'une commande, d'un skill ou du plugin, ou quand `/go` reste refusé alors que rien ne tourne. Toujours depuis un terminal ouvert après A.11 : il a le mot de passe et les tokens.
  - Avec le service : `opencode service restart`.
  - Avec `opencode-web.sh` : `opencode-web.sh stop && opencode-web.sh start`, ou `oc-web restart`.

  Puis la commande de A.12, point 5 (`démarré il y a` doit montrer un petit nombre de secondes), et l'adresse comme en A.13 : le lien de la plateforme et son rechargement forcé (Cmd+Maj+R), puis la racine.
- **Un `/go`, `/fix` ou `/fortify` coupé par un redémarrage** : avec le service, la v2 le reprend toute seule là où il en était, et le plugin lui garde son dossier (vérifié) ; avec `opencode-web.sh`, relance la commande dans sa session, elle reprend à sa dernière étape faite.
- **Un run arrêté avant sa réponse finale**, sans redémarrage (le serveur du modèle en panne au-delà de ses essais, la limite d'étapes du pilote, une réponse coupée) : le titre passe à `↻` et le plugin le reprend tout seul, dans la même session, depuis la fiche ticket (vérifié). Deux reprises au plus d'affilée, puis `⛔` ; ce que tu tapes dans la session annule une reprise qui attend.
- **Un seul serveur.** Ne démarre pas l'autre (A.4). Avec `opencode-web.sh`, ne remets pas les lignes du service dans `~/.zshrc_perso`.
- **Ne mets pas à jour OpenCode lui-même** : ni `opencode upgrade`, ni `npm update -g`, ni `npm install -g @opencode/cli@…`. Le pack est vérifié avec la 2.1.2 et la 2.1.3, et la 2.1.0 a changé le fonctionnement des plugins. Si ta procédure interne passe à une autre version, préviens-moi avant de la suivre. La configuration du pack coupe la recherche automatique de mises à jour (`"autoupdate": false`).
- **Mettre à jour le pack**, quand j'annonce une nouvelle version :
  1. recrée les deux listes d'empreintes (A.6) ;
  2. refais A.7 et A.8 : elles montrent exactement les fichiers à coller ;
  3. si ma liste des fichiers modifiés contient `AGENTS.global.md` ou `opencode.snippet.json`, refais A.9 ou A.10 ;
  4. redémarre.
- **`COMMANDES.md`** est écrit pour l'essai côte à côte. Sa section « Si ta v2 a remplacé la 1.19 » donne les mêmes commandes avec tes chemins.

### A.16 Dépannage

| Ce que tu vois | Pourquoi | Ce que tu fais |
|---|---|---|
| `Unrecognised route!` juste après le lien de ta plateforme, au premier lancement de la journée (il fallait vider le cache et retaper le mot de passe) | l'interface déjà installée dans le navigateur (son service worker) intercepte le lien, qui n'arrive pas à la plateforme : le port n'est pas transmis | dans cet onglet, rechargement forcé : Cmd+Maj+R (Ctrl+Maj+R sous Windows ou Linux), puis ton favori, la racine. Ni cache à vider, ni mot de passe (A.13, « Le premier lancement de la journée ») |
| « Un problème est survenu », avec `Error: Unrecognised route!` dans « Détails de l'erreur », à un autre moment | l'adresse a quelque chose après le port | ouvre la racine, `https://<plateforme>.<domaine>/` (A.13) |
| L'interface s'affiche mal, ou à moitié, après une mise à jour d'OpenCode | l'ancienne version de l'interface est encore servie par son service worker | ferme tous les onglets de l'adresse, puis rouvre la racine |
| La page de connexion revient, ou « Impossible de se connecter. Vérifiez l'adresse et le mot de passe du serveur » avec le bon mot de passe | le lien de la plateforme vise un autre port ou n'a pas été rechargé de force, ou le navigateur garde une connexion d'avant le redémarrage, ou le serveur n'a pas reçu ton mot de passe | les trois vérifications de A.13 ; avec `opencode-web.sh`, la dernière se voit avec `for p in $(pgrep -f -- '--port <port>'); do tr '\0' '\n' < /proc/$p/environ \| grep -c -E '^OPENCODE_(SERVER_)?PASSWORD='; done` (`0` : démarré depuis un terminal sans `OPENCODE_PASSWORD` ; un nouveau terminal, puis redémarre) |
| « Unsupported package for <provider>/<modèle>: unknown » | pas de `"npm"` dans ton provider | A.10, point 5, puis redémarre |
| Une réponse arrive, mais pas de ton modèle | `"npm"` ou `enabled_providers` manque | A.10, point 5, puis redémarre |
| Avec `opencode-web.sh`, le service revient sur 4096 | une ligne `opencode service …` sans `#` dans `~/.zshrc_perso`, ou le service pas désactivé | A.4, points 2 et 3 de `opencode-web.sh` |
| A.12 point 5 n'affiche rien ; `address already in use` ou `EADDRINUSE` dans le journal | un autre serveur occupait déjà <port>, par exemple un `opencode-web.sh` démarré par ta plateforme | `ps -eo pid,args \| grep -i '[o]pencode'` montre son numéro ; arrête-le (`opencode-web.sh stop`, ou `kill <numéro>`), puis redémarre |
| A.12 point 5 : `démarré il y a` un grand nombre de secondes | l'ancien serveur tourne encore : `opencode-web.sh stop` ne l'a pas arrêté, et le nouveau n'a pas pu démarrer | `kill <pid>`, puis `opencode-web.sh start` ; si cela se répète à chaque redémarrage, passe à `oc-web` (A.12) |
| Point 1 de A.14 plus grand que 0 | `opencode.json` invalide, ou un réglage refusé | la lecture sous le tableau de A.14 |
| Point 2 ou 3 de A.14 en échec | le plugin n'a pas été chargé | refais A.7, puis redémarre |
| Aucune commande `/go` dans la liste | les commandes du pack manquent | refais A.7, puis redémarre |
| Pas de réponse de Jira, GitLab, etc. | ta section `mcp` manque dans le nouvel `opencode.json` | refais A.10 |
| Plus de réponse de Jira, GitLab, etc. depuis A.11 | le serveur a démarré sans les tokens : depuis un terminal ouvert avant A.11, ou autrement que depuis un terminal | un nouveau terminal, puis redémarre (A.15) |
| Le premier message après un démarrage met jusqu'à 30 s à partir | la v2 enverrait la première requête sans les outils des serveurs MCP encore en connexion : le plugin les attend, comme la 1.19, pendant les 5 premières minutes | rien ; si c'est à chaque démarrage, un serveur MCP est lent : `grep -i 'mcp' ~/.local/share/opencode/log/opencode.log \| tail -5` |
| L'agent répond « ⚠ Le plugin du pack n'est pas chargé : ses garde-fous sont inactifs… » | la commande est arrivée au modèle sans passer par le plugin | refais A.7, puis redémarre ; n'utilise pas OpenCode avant |
| « Refused by the pack: this is the third identical … call of your answer, a loop » | le modèle répétait le même appel d'outil dans une réponse (la règle `doom_loop` de la 1.19) | rien : l'agent change d'approche. Si un agent y revient souvent, envoie-moi les lignes `same call three times` de `~/.local/share/opencode/log/openrd-pack.log` |

### A.17 Revenir à la 1.19

1. Arrête la v2 :
   - avec le service : `opencode service stop`, puis `opencode service set disabled true` et la commande `sed` de A.4 (point 2 de `opencode-web.sh`), pour que tes terminaux ne le relancent plus ;
   - avec `opencode-web.sh` : `opencode-web.sh stop`, ou `oc-web stop`.

   Vérifie avec `ps -eo pid,args | grep -i '[o]pencode'` qu'il ne reste rien. S'il reste une ligne, arrête-la avec son numéro, le premier nombre de la ligne : `kill <numéro>` (le cas de A.4, quand `opencode-web.sh stop` arrête mal son serveur).
2. Retrouve le programme de la 1.19 sans rien installer, de la même façon que l'étape 4 : `npm pack` télécharge l'archive sans rien exécuter, `tar` l'extrait. Prends le paquet de ta machine (étape 4.1, sans `@opencode/cli-` et préfixé par `opencode-` : `opencode-linux-x64`, `opencode-linux-x64-baseline`…) et la version que tu avais, `1.19.0` si tu ne la connais pas :
```sh
mkdir -p ~/oc119 && cd ~/oc119 && npm pack --ignore-scripts opencode-linux-x64@1.19.0 && tar -xzf opencode-linux-x64-1.19.0.tgz && package/bin/opencode --version
```
Tu dois voir, à la fin, `1.19.0`.
3. Remets la configuration 1.19, celle que ta procédure interne a sauvegardée : elle contient encore `compact-commands.js`. Ta configuration v2 reste de côté dans `~/opencode-config-pack-v2`.
```sh
mv ~/.config/opencode ~/opencode-config-pack-v2 && cp -r ~/.config/opencode.backup ~/.config/opencode
```
4. Les sessions : rien à faire. La 1.19 relit ses sessions après le passage de la v2 (vérifié), et `~/opencode-data-avant-pack-v2` (A.5) reste ta copie de secours.
5. Démarre la 1.19 sur <port>. `opencode-web.sh` démarre le `opencode` de ton PATH, qui est la v2 : utilise cette commande à la place. La 1.19 lit son mot de passe dans `OPENCODE_SERVER_PASSWORD` :
```sh
cd ~ && OPENCODE_SERVER_PASSWORD="$OPENCODE_PASSWORD" nohup ~/oc119/package/bin/opencode serve --hostname 0.0.0.0 --port <port> >> ~/oc119/serve.log 2>&1 < /dev/null &!
```
Pour l'arrêter : `pkill -f 'oc119/package/bin/opencode serve'`.

Le navigateur retrouve alors la 1.19 à la même adresse, et le navigateur affiche sa propre fenêtre de connexion : utilisateur `opencode`, et ton mot de passe.
