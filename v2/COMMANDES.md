# Commandes à taper à la main (v2)

Toutes les commandes que le pack te demande de lancer toi-même, à copier-coller. Sauf mention « dans OpenCode », elles se tapent dans un terminal de la machine qui héberge OpenCode. Aucune n'affiche de mot de passe ni de token.

## Installer la v2

La v2 remplace la v1 : mêmes dossiers dans `~/.config/opencode/`, mais des commandes et des agents différents. La v1 est d'abord mise de côté HORS de `~/.config/opencode/` (OpenCode charge tout ce qui s'y trouve), avec tes réglages, pour pouvoir revenir en arrière. Tes skills `pattern-…`, ta todo et tes fiches ticket restent en place.

1. Mettre la v1 de côté, en une commande :
```sh
mkdir -p ~/opencode-v1/skills && cd ~/.config/opencode && cp AGENTS.md opencode.json ~/opencode-v1/ && mv agents commands scripts plugins ~/opencode-v1/ && for s in best-practices build-fix dotnet-cqrs-conventions explain-code fortify-remediation integrations-guardrails ship-procedure sync-procedure; do [ -d "skills/$s" ] && mv "skills/$s" ~/opencode-v1/skills/; done; ls ~/opencode-v1
```
2. Copier la v2 depuis ton clone du pack (remplace `~/OpenRDCode` par son chemin ; à la main, ce sont les dossiers `agents/`, `commands/`, `scripts/`, `plugins/` et les sous-dossiers de `skills/` de `v2/`) :
```sh
cd ~/OpenRDCode && cp -r v2/agents v2/commands v2/scripts v2/plugins ~/.config/opencode/ && cp -r v2/skills/. ~/.config/opencode/skills/ && ls ~/.config/opencode/commands
```
   La dernière ligne doit lister exactement : `compare.md daily.md fix.md go.md outil.md review.md`.
3. `~/.config/opencode/AGENTS.md` : remplace son contenu par `v2/AGENTS.global.md`, puis recopie tes valeurs des sections « Daily » et « Release groups » depuis `~/opencode-v1/AGENTS.md`.
4. `~/.config/opencode/opencode.json` : remplace ses sections `agent` et `permission` par celles de `v2/opencode.snippet.json`, et ajoute ses sections `experimental` et `compaction` ; garde `provider`, `model`, `shell` et le reste. Remplace bien la section `permission` entière : une règle `"ask"` de la v1 qui resterait rouvrirait la fuite du « Toujours » (section « Vérifier qu'aucune règle ne demande »).
5. Redémarre OpenCode (section suivante), puis dans une nouvelle session, sur un dépôt : `/outil` doit afficher la liste des outils.
6. Une fois par dépôt, pour que `/go` connaisse ses commandes de build et ses conventions : `/outil setup` (relis le diff d'`AGENTS.md`).

Le push et la MR de `/go` demandent des identifiants GitLab que git trouve seul : section « Identifiants GitLab » plus bas, à vérifier avant le premier `/go`.

## Mettre à jour une v2 déjà installée

Depuis ton clone du pack à jour (`git pull`), en une commande : agents, commandes, scripts, plugin et skills du pack sont remplacés ; tes skills `pattern-…`, ta todo et tes fiches ticket ne sont pas touchés.
```sh
cd ~/OpenRDCode && cp -r v2/agents v2/commands v2/scripts v2/plugins ~/.config/opencode/ && cp -r v2/skills/. ~/.config/opencode/skills/ && ls ~/.config/opencode/scripts/diff-guard.sh ~/.config/opencode/scripts/ticket-stats.sh ~/.config/opencode/skills/outil-stats
```
Puis :
1. `~/.config/opencode/opencode.json` : remplace les sections `agent` et `permission` par celles de `v2/opencode.snippet.json`, et ajoute ses deux nouvelles sections, `experimental` et `compaction`.
2. `~/.config/opencode/AGENTS.md` : reprends `v2/AGENTS.global.md` en gardant tes sections « Daily » et « Release groups ».
3. Section « Vérifier qu'aucune règle ne demande », puis redémarre OpenCode.

## Vérifier qu'aucune règle ne demande

Un clic sur « Toujours » à une demande d'autorisation vaut pour tous les agents jusqu'au redémarrage d'OpenCode, et ouvre bien plus large que la commande demandée (`rm *` pour un `rm -rf`, `dotnet *` pour un `dotnet run`, toute lecture pour un fichier `.env`). La v2 n'a donc plus aucune règle « ask » : seules restent les 6 lignes de publication Confluence (`*confluence*create*`, `update`, `upload`, en deux casses), dont l'outil n'est visible que de l'agent build. Cette commande doit afficher exactement ces 6 lignes :
```sh
grep -n '"ask"' ~/.config/opencode/opencode.json
```

## Revenir à la v1

```sh
cd ~/.config/opencode && rm -r agents commands scripts plugins && for s in best-practices build-fix dotnet-cqrs-conventions explain-code fortify-remediation integrations-guardrails outil-todo outil-licences outil-audit outil-cqrs outil-abandon outil-setup outil-doc outil-release-notes outil-pattern outil-stats; do rm -rf "skills/$s"; done && cp -r ~/opencode-v1/agents ~/opencode-v1/commands ~/opencode-v1/scripts ~/opencode-v1/plugins . && cp -r ~/opencode-v1/skills/. skills/ && cp ~/opencode-v1/AGENTS.md ~/opencode-v1/opencode.json .
```
Puis redémarre OpenCode.

## Vérifier le nom de l'outil qui crée les MR

`/go` crée la MR en Draft avec l'outil `…create_merge_request` du MCP GitLab ; c'est le seul outil d'écriture GitLab permis, à l'agent `pilot` seulement. Après un premier `/go`, ce que la permission a décidé pour lui (`allow` = créée ; `deny` = l'outil porte un autre nom chez toi, envoie-moi la ligne) :
```sh
grep 'message=evaluated' ~/.local/share/opencode/log/opencode.log | grep -i 'merge_request' | tail -5
```

## Redémarrer OpenCode

Après une modification d'`opencode.json`, du plugin, d'un agent, d'une commande ou d'un skill. Inutile après un `/outil pattern` (`/go` lit les fichiers des patterns lui-même) et après une modification de `~/.zshenv` (relu à chaque commande d'un agent).
```sh
opencode-web.sh stop && opencode-web.sh start
```

## Trouver les chemins à mettre dans la config

Chemin de zsh, pour la clé `"shell"` d'`opencode.json` :
```sh
command -v zsh
```

Dossier qui contient l'exécutable `dotnet`, pour `DOTNET_ROOT` dans `~/.zshenv` :
```sh
dirname "$(readlink -f "$(command -v dotnet)")"
```
Si elle affiche `.`, `dotnet` n'est pas non plus dans le PATH de ton terminal. Celle-ci liste alors les exécutables `dotnet` installés ; `DOTNET_ROOT` est le dossier de l'un d'eux :
```sh
find ~ /usr/share/dotnet /usr/lib/dotnet -maxdepth 4 -name dotnet -type f -perm -u+x 2>/dev/null
```

Si tu fais du front sur cette machine : dossier qui contient `node`, à ajouter au PATH de `~/.zshenv` quand Node vient de nvm (nvm s'initialise dans `~/.zshrc`, que l'agent ne lit pas). À refaire si tu changes de version de Node par défaut :
```sh
dirname "$(command -v node)"
```

Dossiers d'OpenCode (config, données, logs) :
```sh
opencode debug paths
```

## Vérifier ce que voit l'agent

Ce que le shell d'un agent obtient de `~/.zshenv` seul : chemin de `dotnet`, `DOTNET_ROOT`, et la présence (pas la valeur) des variables Artifactory, en minuscules et en majuscules :
```sh
env -i HOME="$HOME" PATH=/usr/bin:/bin "$(command -v zsh)" -c 'command -v dotnet; echo "DOTNET_ROOT=$DOTNET_ROOT"; for v in artifactory_user artifactory_password ARTIFACTORY_USER ARTIFACTORY_PASSWORD; do [ -n "${(P)v}" ] && echo "$v : définie" || echo "$v : absente"; done'
```
Les deux variables qui comptent sont celles que nomme le `nuget.config` du dépôt (`%artifactory_user%` ou `%ARTIFACTORY_USER%`, à lire dans Rider) : sous Linux, majuscules et minuscules sont deux variables différentes. Si `dotnet` ou l'une d'elles manque ici, un agent ne peut pas builder, et le pack lui interdit de les poser lui-même dans une commande : corrige `~/.zshenv`, puis redémarre OpenCode.

`~/.zshenv` ne doit rien afficher, sinon chaque sortie de commande d'un agent le contient. Doit afficher `0` :
```sh
env -i HOME="$HOME" "$(command -v zsh)" -c true 2>&1 | wc -c
```

`~/.zshenv` contient les identifiants Artifactory : lisible par toi seul.
```sh
chmod 600 ~/.zshenv
```

La config qu'OpenCode charge réellement (secrets masqués), puis sa clé `shell`. Elle va dans un fichier car la sortie dans un pipe est coupée à 64 Ko. Une erreur à la place veut dire qu'`opencode.json` est invalide, et elle donne la ligne :
```sh
opencode debug config > /tmp/opencode-config.json && grep -n '"shell"' /tmp/opencode-config.json
```

Les agents du pack se chargent sans erreur (un fichier d'agent invalide affiche son erreur) :
```sh
for a in pilot analyst coder checker debugger doc-writer; do opencode debug agent "$a" > /dev/null && echo "$a OK"; done
```

Le shell que les agents utilisent vraiment (après le redémarrage et une première commande d'agent) :
```sh
grep 'shell tool using shell' ~/.local/share/opencode/log/opencode.log | tail -1
```

Taille de contexte réelle du serveur Qwen, à mettre dans `limit.context` d'`opencode.json` (vLLM la donne dans `max_model_len`). Remplace l'adresse par la `baseURL` de ton provider (elle finit en général par `/v1`) ; si le serveur demande une clé, ajoute `-H "Authorization: Bearer <ta clé>"` :
```sh
curl -s https://adresse-du-serveur/v1/models | grep -oE '"max_model_len": ?[0-9]+'
```
Rien ne s'affiche : la réponse ne vient pas directement de vLLM (passerelle) ; demande la valeur à l'équipe qui héberge le modèle.

Ce que `/outil pattern` et le coder savent des packages d'un dépôt : internes ou nuget.org, versions, framework de chaque projet, frameworks livrés et documentation XML des packages internes. Remplace le chemin par celui du dépôt :
```sh
sh ~/.config/opencode/scripts/package-refs.sh /chemin/du/depot
```

Ce que `/outil pattern` voit du dépôt source pour un ticket : branche extraite comparée à develop, commits et fichiers de la MR. Remplace le chemin et la clé :
```sh
sh ~/.config/opencode/scripts/pattern-source.sh /chemin/du/depot/source ABC-123
```

## Logs d'OpenCode

Le fichier est `~/.local/share/opencode/log/opencode.log` (s'il n'existe pas : `opencode debug paths`, ligne `log`).

Les 200 dernières lignes :
```sh
tail -n 200 ~/.local/share/opencode/log/opencode.log
```

Les erreurs récentes :
```sh
grep -E 'level=(ERROR|WARN)' ~/.local/share/opencode/log/opencode.log | tail -30
```

Les commandes refusées aux agents, avec la règle qui a refusé (`action.pattern`). C'est ce qu'il faut m'envoyer quand un agent bute sur un refus :
```sh
grep 'message=evaluated' ~/.local/share/opencode/log/opencode.log | grep 'action.action=deny' | tail -20
```

Les commandes qui t'ont demandé une validation :
```sh
grep 'message=evaluated' ~/.local/share/opencode/log/opencode.log | grep 'action.action=ask' | tail -20
```

Le détail des erreurs « Service Unavailable » ou de contexte du modèle (si le texte parle de « maximum context length », la session a dépassé la taille acceptée par le serveur : voir `limit.context`) :
```sh
grep -iE 'service unavailable|context length|maximum context|too long' ~/.local/share/opencode/log/opencode.log | tail -5
```

Les 40 dernières commandes shell des agents, une par ligne (la commande suit `pattern=`, la décision suit `action.action=`). C'est ce qu'il faut m'envoyer quand un agent tourne en rond :
```sh
grep 'message=evaluated' ~/.local/share/opencode/log/opencode.log | grep 'permission=bash' | tail -40
```

Le chargement du plugin (rien = pas d'erreur) :
```sh
grep -i plugin ~/.local/share/opencode/log/opencode.log | grep -iE 'error|fail' | tail -10
```

## Après un agent qui a dérapé

Ce qu'il a laissé dans le dépôt (fichiers modifiés ou créés) :
```sh
git status --short
```

Ce qu'il a créé dans `/tmp` depuis 2 heures (à relire avant d'effacer quoi que ce soit) :
```sh
find /tmp -maxdepth 1 -newermt '-2 hours' -user "$USER" 2>/dev/null
```

Puis, pour chaque dossier de cette liste qui vient de lui (par exemple `/tmp/apidump`) :
```sh
rm -rf /tmp/apidump
```

Un dossier nommé `~` créé DANS le dépôt (un ancien `/extract-pattern` de la v1 y écrivait le skill, les outils d'OpenCode ne comprenant pas `~`). À taper depuis la racine du dépôt, guillemets et `./` compris : sans eux, `~` désigne ton dossier personnel.
```sh
ls -la -- './~'
```
S'il existe, récupère d'abord le skill qu'il contient (`./~/.config/opencode/skills/pattern-…/SKILL.md`), puis supprime ce dossier, toujours avec `./` et les guillemets :
```sh
rm -r -- './~'
```

Un skill `pattern-…` raté, créé par un `/outil pattern` qui a dérapé : à supprimer avant de relancer, sinon le prochain du même nom l'enrichit au lieu de repartir de zéro. La liste des skills, puis la suppression (remplace le nom) :
```sh
ls ~/.config/opencode/skills/
```
```sh
rm -r ~/.config/opencode/skills/pattern-nom-back
```

## Une commande qui met longtemps à démarrer

Le `git fetch` que font les commandes au démarrage, dans le dépôt, avec son temps : `0` = OK, `124` = GitLab n'a pas répondu en 30 s (VPN, réseau), `77` = identifiants GitLab refusés ou absents (section suivante), un autre code = dépôt ou branche introuvable, réseau :
```sh
time sh ~/.config/opencode/scripts/fetch.sh -q --no-tags origin; echo "code $?"
```

## Identifiants GitLab

Pour « could not read Username… terminal prompts disabled », « Authentication failed » ou « Fetch: AUTH FAILED ». Un agent ne peut jamais taper un identifiant : git doit trouver tout seul tes identifiants GitLab sur la machine qui héberge OpenCode. À taper dans un terminal de cette machine (le terminal de l'interface web d'OpenCode convient), dans un de tes dépôts. Aucune de ces commandes n'affiche de mot de passe ni de token.

Le test, dans les mêmes conditions qu'un agent : `identifiants OK`, sinon l'erreur de l'agent :
```sh
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' git ls-remote --heads origin > /dev/null && echo "identifiants OK"
```
Ce qui est réglé : le gestionnaire d'identifiants de git (une ligne par gestionnaire, rien si aucun), puis l'adresse du dépôt (`https://…`, ou `git@…` pour ssh), sans ce qu'elle contiendrait d'identifiant :
```sh
git config --show-origin --get-all credential.helper
git remote get-url origin | sed -E 's#://[^@/]*@#://***@#'
```

### Réglage durable (recommandé) : un token réservé à cette machine

Le token est gardé par git dans `~/.git-credentials`, lisible par toi seul et refusé aux agents. Il ne donne accès qu'au code des dépôts (ni aux MR, ni aux pipelines, ni au reste de GitLab) et s'arrête à sa date d'expiration. Plus rien à faire le matin : seulement le renouveler à son expiration. Sur un Mac, le trousseau le garde chiffré : `osxkeychain` à la place de `store` à l'étape 3.

1. Dans GitLab, la page des jetons d'accès : `https://<adresse de ton GitLab>/-/user_settings/personal_access_tokens` (ou ton avatar → Modifier le profil → Jetons d'accès), puis « Ajouter un nouveau jeton » :
   - nom : `opencode-<nom de la machine>`, pour pouvoir le révoquer seul ;
   - date d'expiration : la plus lointaine que GitLab accepte (un an au plus, en général) ;
   - droits : `read_repository` et `write_repository`, rien d'autre.

   Copie le token tout de suite : GitLab ne l'affiche qu'une fois.
2. Vide le cache en mémoire du dépannage :
```sh
git credential-cache exit
```
3. Le gestionnaire durable, à la place du cache :
```sh
git config --global --replace-all credential.helper store
```
```sh
git config --global --unset credentialCache.ignoreSIGHUP
```
4. Enregistre le token, une seule fois : git demande le nom d'utilisateur (ton identifiant GitLab), puis le mot de passe : colle le token.
```sh
git ls-remote --heads origin > /dev/null
```
5. Vérifie : le fichier n'est lisible que par toi (la ligne commence par `-rw-------`), et le test passe :
```sh
ls -l ~/.git-credentials
```
```sh
GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin > /dev/null && echo "identifiants OK"
```
6. Le rappel, dans OpenCode, une semaine avant la date d'expiration du token (il sortira dans `/daily` ce jour-là ; GitLab prévient aussi par mail) :
```text
/outil todo Renouveler le token GitLab d'OpenCode le 13/10/2027
```

Renouvellement : un nouveau token comme à l'étape 1, puis git oublie l'ancien (remplace `gitlab.example.com` par l'adresse de ton GitLab, sans `https://`) et enregistre le nouveau (colle-le quand git demande le mot de passe) ; enfin révoque l'ancien dans GitLab :
```sh
printf 'protocol=https\nhost=gitlab.example.com\n\n' | git credential reject
```
```sh
git ls-remote --heads origin > /dev/null
```
Machine compromise ou rendue : révoque le token dans GitLab (page de l'étape 1), il ne marche plus nulle part.

### Dépannage sans rien sur le disque : le cache en mémoire

Si ta sécurité interdit tout token enregistré : tes identifiants restent en mémoire 10 h, même si tu fermes le terminal, puis disparaissent ; chaque matin ou après un redémarrage de la machine, refais la dernière commande :
```sh
git config --global --replace-all credential.helper 'cache --timeout=36000'
```
```sh
git config --global credentialCache.ignoreSIGHUP true
```
```sh
git ls-remote --heads origin > /dev/null
```
Avec un gestionnaire déjà en place (`osxkeychain`, `manager`, `store`) qui a perdu ou refusé tes identifiants (mot de passe changé, token expiré), la dernière commande seule suffit : il garde ce que tu tapes.

Après un réglage : refais le test, puis dans OpenCode, dans la même session : « relance ».

- Avec une connexion d'entreprise (SSO), le mot de passe que git demande est un token d'accès personnel (étape 1 ci-dessus), pas ton mot de passe.
- Jamais de token dans l'adresse du dépôt (`https://nom:token@…`) ni dans `~/.zshenv` : il serait écrit en clair dans `.git/config`, affiché par `git remote -v`, ou visible de chaque commande des agents.
- Adresse en `git@…` (ssh) : une clé sans phrase de passe réservée à cette machine et ajoutée à ton profil GitLab, ou une clé chargée dans un agent ssh (`ssh-add`) avant le démarrage du serveur OpenCode.
- Test OK mais l'agent échoue encore : le serveur OpenCode ne voit pas ces identifiants (démarré par un autre utilisateur, ou trousseau verrouillé) : redémarre-le depuis ce terminal (section « Redémarrer OpenCode »).
- Les agents ne peuvent pas lire ces identifiants : `~/.git-credentials`, `git credential`, le dossier du cache, `security` et `secret-tool` leur sont refusés.

## Todo list

Ta todo, telle qu'elle est enregistrée (tu peux aussi la modifier avec un éditeur : une ligne par tâche) :
```sh
cat ~/.config/opencode/todo.md
```

## Fiche ticket

Le plan de la fiche de la branche courante, avec les étapes cochées. À taper dans le dépôt :
```sh
sh ~/.config/opencode/scripts/ticket-sheet.sh plan
```

Cocher une étape à la main (ici la 2), avec une ligne datée dans `## Suivi` :
```sh
sh ~/.config/opencode/scripts/ticket-sheet.sh tick 2 "cochée à la main"
```

Vérifier la fiche après l'avoir corrigée à la main (sections, étapes numérotées avec leurs fichiers et leurs tests, chaque critère couvert par un test attendu) ; `/go` fait la même vérification après l'analyse :
```sh
sh ~/.config/opencode/scripts/ticket-sheet.sh check
```

Ce que `/go` et `/fix` ont fait sur les tickets du dépôt (le même tableau que `/outil stats`) :
```sh
sh ~/.config/opencode/scripts/ticket-stats.sh
```

## Contrôle avant push

Avant chaque push de `/go` et `/fix`, un script, sans le modèle, relit tout ce qui va partir : chaque commit pas encore poussé (même un secret retiré par un commit suivant part avec l'historique) et l'état de la branche. Il arrête tout, rien n'est poussé, sur : une clé privée, un token GitLab, GitHub, AWS ou Slack, un utilisateur et un mot de passe dans une URL, un mot de passe dans une chaîne de connexion, une valeur secrète dans un fichier de configuration, un fichier de clé ou `.env` ajouté, un marqueur de conflit, une version payante d'un package, et la valeur exacte d'une variable secrète de ton environnement (un nom avec PASSWORD, TOKEN, SECRET, API_KEY ou CREDENTIAL : le mot de passe Artifactory de `~/.zshenv`), où qu'elle soit. Dans un fichier de test, c'est un avertissement (valeurs factices), sauf pour la valeur d'une variable secrète : elle n'est jamais factice. La valeur n'est jamais affichée : seulement le type et l'endroit.

Le même contrôle à la main, dans le dépôt :
```sh
sh ~/.config/opencode/scripts/diff-guard.sh
```

- Faux positif : ajoute le commentaire `gitleaks:allow` en fin de la ligne signalée (dans Rider), puis relance `/go` (ou `/fix`). Il ne lève pas « value of the environment variable » : cette valeur est réellement ton secret.
- Marqueur de conflit ou package payant : corrige dans Rider (le package : son option gratuite, `/outil licences <package>`), puis relance.
- Vrai secret : il n'est que dans tes commits locaux. Réécris-les sans lui : les commits locaux redeviennent des modifications non commitées, tu remplaces le secret (variable d'environnement, coffre de secrets, valeur factice), puis `/go` fait un seul commit propre et pousse. Branche déjà poussée une fois :
```sh
git reset --soft "@{u}"
```
  Branche jamais poussée :
```sh
git reset --soft "$(git merge-base HEAD origin/develop)"
```
  Si c'est un vrai secret, fais-le révoquer aussi : il a existé en clair sur cette machine.

## Lire un autre dépôt (« comme dans… »)

`/go ABC-123 comme dans ~/repos/ancienne-api (ExportService)` : l'analyste lit l'implémentation de l'autre dépôt et la décrit dans la fiche (section « Référence »), le coder la reproduit. Au début du `/go`, OpenCode te demande l'accès en lecture à ce dossier : réponds « Toujours » (une fois pour toute la session OpenCode, pour ce dossier seulement). Personne n'écrit dans l'autre dépôt.

Pour un dépôt que tu cites souvent, sans plus aucune demande : déclare-le comme référence dans `~/.config/opencode/opencode.json` (au premier niveau ; le nom, sans espace ni `/`, sert aussi dans `/go … comme dans ancienne-api`), puis redémarre OpenCode :
```json
"references": {
  "ancienne-api": { "path": "~/repos/ancienne-api", "description": "Ancienne API d'export : implémentation de référence de l'export SharePoint vers S3" }
}
```
Pour réutiliser la même implémentation sur plusieurs tickets ou la partager à l'équipe, capture-la plutôt en pattern (section suivante) : `/go` s'en sert ensuite tout seul.

## Documentation (/outil doc)

Ce que `/outil doc` reçoit, à taper dans le dépôt (lecture seule, aucune valeur de configuration affichée). L'inventaire du dépôt :
```sh
sh ~/.config/opencode/scripts/doc-inventory.sh
```
Les endpoints calculés depuis le code (ajoute un dossier, par exemple `src/Api`, pour un gros dépôt) :
```sh
sh ~/.config/opencode/scripts/api-routes.sh
```
Les clés de configuration, sans leurs valeurs :
```sh
sh ~/.config/opencode/scripts/config-keys.sh
```

## Avant un /outil pattern

`/outil pattern <nom> <chemin du dépôt source> [où : clé Jira, classes]` capture une bonne implémentation en skill `pattern-<nom>-back` (ou `-front`), avec les appels des packages internes tels que le code source les écrit. Ensuite, `/go` s'en sert tout seul quand un ticket s'y prête, ou sur consigne : `/go ABC-123 comme le pattern <nom>`.

L'agent lit les fichiers de la branche extraite du dépôt source, sans fetch : s'il te signale que le développement n'y est pas, ou que la branche est en retard sur develop, mets le dépôt source sur develop à jour (git refuse de changer de branche si une modification non commitée est en conflit, et `--ff-only` refuse si la branche a divergé), puis relance `/outil pattern`. Remplace le chemin :
```sh
git -C /chemin/du/depot/source switch develop && git -C /chemin/du/depot/source pull --ff-only
```

## Avant un /compare

Le dépôt de référence (celui où ça marche) doit être cloné sur la machine qui héberge OpenCode, sur la version qui tourne (en général master). Une seule fois, s'il n'y est pas encore (remplace l'URL et le chemin) :
```sh
git clone <url du dépôt> /chemin/du/depot/reference
```
Puis, avant chaque comparaison :
```sh
git -C /chemin/du/depot/reference switch master && git -C /chemin/du/depot/reference pull --ff-only
```
Pour comparer aussi les versions transitives des packages (celles que tirent les packages internes, par exemple la librairie SharePoint sous un package maison), restaure-le une fois après chaque pull (`dotnet restore <fichier>.sln` s'il y a plusieurs solutions) :
```sh
cd /chemin/du/depot/reference && dotnet restore
```
Ensuite, dans une nouvelle session ouverte sur le dépôt où ça ne marche plus (le chemin sans espace, puis une classe, une méthode ou une route, puis le symptôme) :
```text
/compare /chemin/du/depot/reference ExportService le fichier envoyé sur S3 n'a plus l'extension .csv
```
À sa première lecture dans le dépôt de référence, OpenCode demande l'autorisation : réponds « toujours », elle couvre tout ce dépôt.

## Dans OpenCode

L'environnement de build des agents, dans une nouvelle session :
```text
lance `sh ~/.config/opencode/scripts/build-test.sh --build-only`
```
`BUILD: OK` ou une erreur de compilation : l'environnement est bon. Une ligne `ENVIRONMENT PROBLEM` dit quoi corriger.

Une session devenue longue, ou qui répond « Service Unavailable » à chaque message : résume-la et continue dans la même session, au lieu d'en ouvrir une nouvelle :
```text
/compact
```

Un ticket, du début à la MR en Draft (tes consignes après la clé, facultatives). Relancé, il reprend où il s'était arrêté. Le titre de la session dit l'issue : ✅ MR créée ou rien à faire, ⛔ arrêté (la raison est dans la réponse), ❓ une question t'attend :
```text
/go ABC-123
```
```text
/go ABC-123 avec un Result, sans nouvelle lib
```
Comme une implémentation existante : un pattern de l'équipe, ou un autre dépôt (section « Lire un autre dépôt ») :
```text
/go ABC-123 comme le pattern export-csv
```
```text
/go ABC-123 comme dans ~/repos/ancienne-api (ExportService)
```
Un gros ticket : l'analyse et le plan seulement, pour les relire avant le code (le `/go` suivant code) ; ou un arrêt après chaque étape :
```text
/go ABC-123 analyse seule
```
```text
/go ABC-123 pas à pas
```

Après la CI ou la review (jobs en échec, Sonar, Fortify, discussions de la MR), ou pour pousser ce que tu as modifié toi-même sur cette machine :
```text
/fix
```
```text
/fix seulement la review
```

Ta todo : la voir, ajouter une tâche (l'échéance est lue dans le texte), la marquer faite, en supprimer une, voir seulement les rappels du jour :
```text
/outil todo
```
```text
/outil todo Relancer Paul pour la MEP vendredi
```
```text
/outil todo fait 3
```
```text
/outil todo suppr 3
```
```text
/outil todo rappels
```

Écrire ou mettre à jour la documentation du dépôt dans `docs/` (tout, ou un sujet : `architecture`, `api`, `configuration`, `integrations`, `donnees`, `exploitation`), puis la publier sur Confluence sous une page parente (chaque page demande ta validation) :
```text
/outil doc
```
```text
/outil doc api
```
```text
/outil doc confluence ESPACE Page parente
```

Capturer une implémentation d'un autre dépôt en pattern d'équipe (section « Avant un /outil pattern ») :
```text
/outil pattern export-csv /chemin/du/depot/source ExportService
```

Ce que `/go` et `/fix` ont fait sur tes tickets de ce dépôt : étapes, lancements, réponses aux questions, décisions de l'agent, arrêts, temps de l'analyse à la MR (plusieurs dépôts : leurs chemins après `stats`) :
```text
/outil stats
```

Les autres outils (audit, licences, release notes, cqrs, AGENTS.md du dépôt, abandon d'un ticket) :
```text
/outil
```
