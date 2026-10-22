# Commandes à taper à la main (pack pour OpenCode v2)

Les commandes du pack à taper toi-même, à copier-coller, quand OpenCode v2 tourne à côté de ta 1.19 comme le dit `MIGRATION.md` : sa configuration est dans `~/oc2/config/opencode`, son journal dans `~/oc2/serve.log`, et son programme est `~/oc2/cli/package/bin/opencode` (le simple mot `opencode` reste ta 1.19). Sauf mention « dans OpenCode », elles se tapent dans un terminal de la machine qui héberge OpenCode. Aucune n'affiche de mot de passe ni de token.

**Aucun script à lancer toi-même.** Les commandes de ce guide sont des commandes git, dotnet ou système. Les scripts du pack (`~/.config/opencode/scripts`) sont lancés par les agents ; quand un diagnostic a besoin de l'un d'eux, ce guide te donne la phrase à écrire dans une session OpenCode, et c'est l'agent qui le lance.

## Installer

Tout est dans `MIGRATION.md` : téléchargement de la v2 sans rien installer, configuration collée depuis GitHub et vérifiée par empreintes, démarrage, vérifications. Si la v2 a déjà remplacé ta 1.19 (procédure interne), c'est son annexe A, de l'état des lieux à l'interface web démarrée par `opencode-web.sh` ; la section suivante donne alors tes chemins.

## Si ta v2 a remplacé la 1.19 (annexe A de `MIGRATION.md`)

Les autres sections de ce guide sont écrites pour l'essai côte à côte. Si tu as suivi l'annexe A, remplace dans leurs commandes :

| Dans ce guide | Chez toi |
|---|---|
| `~/oc2/config/opencode` | `~/.config/opencode` |
| `~/oc2/serve.log` | `~/.local/share/opencode/log/opencode.log` |
| `~/oc2/CHECKSUMS-config.txt` et `~/oc2/CHECKSUMS-scripts.txt` | `~/CHECKSUMS-config.txt` et `~/CHECKSUMS-scripts.txt` |
| `~/oc2/cli/package/bin/opencode` | `opencode` |
| redémarrer : Ctrl+C, puis l'étape 6 | `opencode-web.sh stop && opencode-web.sh start`, ou `oc-web restart` |
| `MIGRATION.md`, étapes 5.5 et 5.6 | annexe A.9 et A.10 |

Une exception : les lignes du plugin du pack, `event stream connected` et `refused by the pack`, ne vont pas dans `opencode.log`. Elles vont dans le journal de `opencode-web.sh` (annexe A.2.3), ou dans `~/.local/share/opencode/log/oc-web.log` avec `oc-web`.

Les plus utilisées, déjà adaptées :

Redémarrer OpenCode, depuis un terminal ouvert après l'annexe A.11 (il a le mot de passe) :
```sh
opencode-web.sh stop && opencode-web.sh start
```

Ce qui tourne (une seule ligne `opencode serve`, celle du port <port>, et peut-être celle de `opencode-web.sh start`) :
```sh
ps -eo pid,args | grep -i '[o]pencode'
```

Le serveur sur <port> : depuis combien de secondes il tourne (un petit nombre juste après un redémarrage), son programme, sa version, et s'il a reçu son mot de passe (annexe A.12, point 5) :
```sh
for p in $(pgrep -f -- '--port <port>'); do e=$(readlink -f /proc/$p/exe); case $e in */opencode*) echo "pid $p, démarré il y a $(ps -o etimes= -p $p | tr -d ' ') s"; echo "$e"; $e --version; tr '\0' '\n' < /proc/$p/environ | grep -c -E '^OPENCODE_(SERVER_)?PASSWORD=';; esac; done
```

Mettre à jour le pack (section suivante), avec tes chemins :
```sh
cd ~/.config/opencode && sha256sum --quiet --strict -c ~/CHECKSUMS-config.txt 2>/dev/null && echo "OK : la configuration est identique à GitHub"
```
```sh
cd ~/.config/opencode/scripts && sha256sum --quiet --strict -c ~/CHECKSUMS-scripts.txt 2>/dev/null && echo "OK : les scripts sont identiques à GitHub"
```

Le journal :
```sh
tail -n 200 ~/.local/share/opencode/log/opencode.log
```
```sh
grep -E 'level=(ERROR|WARN)' ~/.local/share/opencode/log/opencode.log | tail -30 | cut -c1-300
```
```sh
grep -c 'kind=invalid' ~/.local/share/opencode/log/opencode.log
```
```sh
grep -c 'loading plugin.*openrd-pack' ~/.local/share/opencode/log/opencode.log
```
```sh
grep 'configuration normalization diagnostic' ~/.local/share/opencode/log/opencode.log | grep -o 'path=[^ ]*' | sort -u
```
```sh
grep -c 'Gateway Time-out' ~/.local/share/opencode/log/opencode.log
```

Les règles « ask » (6 lignes attendues, section « Vérifier qu'aucune règle ne demande ») :
```sh
grep -n '"ask"' ~/.config/opencode/opencode.json
```

## Mettre à jour le pack

Quand j'annonce une nouvelle version, avec la liste des fichiers modifiés :
1. Recrée `~/oc2/CHECKSUMS-config.txt` et `~/oc2/CHECKSUMS-scripts.txt` depuis GitHub (vue Raw).
2. Ce qui a changé dans la configuration, puis dans les scripts : chaque ligne `FAILED` est un fichier à recoller depuis `opencode-v2/` ; tu as fini quand la commande affiche son `OK`.
```sh
cd ~/oc2/config/opencode && sha256sum --quiet --strict -c ~/oc2/CHECKSUMS-config.txt 2>/dev/null && echo "OK : la configuration est identique à GitHub"
```
```sh
cd ~/.config/opencode/scripts && sha256sum --quiet --strict -c ~/oc2/CHECKSUMS-scripts.txt 2>/dev/null && echo "OK : les scripts sont identiques à GitHub"
```
3. Si ma liste contient `AGENTS.global.md` ou `opencode.snippet.json` : `MIGRATION.md`, étape 5.5 ou 5.6.
4. Redémarre OpenCode (section « Redémarrer OpenCode »).

## Vérifier qu'aucune règle ne demande

Un clic sur « Toujours » à une demande d'autorisation vaut pour tous les agents jusqu'au redémarrage d'OpenCode, et ouvre bien plus large que la commande demandée (`rm *` pour un `rm -rf`, `dotnet *` pour un `dotnet run`, toute lecture pour un fichier `.env`). La v2 n'a donc plus aucune règle « ask » : seules restent les 6 lignes de publication Confluence (`*confluence*create*`, `update`, `upload`, en deux casses), dont l'outil n'est visible que de l'agent build. Cette commande doit afficher exactement ces 6 lignes :
```sh
grep -n '"ask"' ~/oc2/config/opencode/opencode.json
```

## Revenir à OpenCode 1.19

Arrête la v2 (Ctrl+C dans son terminal) et rouvre l'adresse de ta 1.19 : `MIGRATION.md`, étape 11. Rien d'autre à faire, sa configuration n'a pas été modifiée. Si la v2 a remplacé ta 1.19 : annexe A.17.

## Vérifier le nom de l'outil qui crée les MR

`/go` crée la MR en Draft avec l'outil `…create_merge_request` du MCP GitLab ; c'est le seul outil d'écriture GitLab permis, à l'agent `pilot` seulement. Si un `/go` s'arrête en disant que la création de la MR a été refusée, l'outil porte un autre nom chez toi : envoie-moi le nom qu'il cite.

## Redémarrer OpenCode

Après une modification d'`opencode.json`, du plugin, d'un agent, d'une commande ou d'un skill. Inutile après un `/outil pattern` (`/go` lit les fichiers des patterns lui-même) et après une modification de `~/.zshenv` (relu à chaque commande d'un agent).

Dans le terminal de la v2 : Ctrl+C, puis les étapes 6.1, 6.3 et 6.4 de `MIGRATION.md` (les dossiers, le mot de passe, le démarrage). Si la v2 a remplacé ta 1.19 : `opencode-web.sh stop && opencode-web.sh start`, ou `oc-web restart`.

## Trouver les chemins à mettre dans la config

Chemin de zsh, pour la clé `"shell"` de `~/oc2/config/opencode/opencode.json` :
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

Dossiers d'OpenCode v2 (config, données, logs), dans un terminal où tu as fait l'étape 6.1 de `MIGRATION.md` :
```sh
~/oc2/cli/package/bin/opencode debug paths
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

`opencode.json` accepté par la v2 (`0`), après une connexion et l'ouverture d'un projet. Plus que `0` : `MIGRATION.md`, étape 8, point 1. N'utilise pas `debug config` de la v2 pour ça : il affiche les valeurs de la configuration, clés comprises, et laisse un service tourner.
```sh
grep -c 'kind=invalid' ~/oc2/serve.log
```

La clé `shell` (le shell des commandes des agents ; sans elle, ton `$SHELL`) :
```sh
grep -n '"shell"' ~/oc2/config/opencode/opencode.json
```

Les agents, commandes et skills du pack sont ceux de GitHub, que mes tests valident, si cette commande affiche `OK` :
```sh
cd ~/oc2/config/opencode && sha256sum --quiet --strict -c ~/oc2/CHECKSUMS-config.txt 2>/dev/null && echo "OK : la configuration est identique à GitHub"
```

Taille de contexte réelle du serveur Qwen, à mettre dans `limit.context` d'`opencode.json` (vLLM la donne dans `max_model_len`). Remplace l'adresse par la `baseURL` de ton provider (elle finit en général par `/v1`) ; si le serveur demande une clé, ajoute `-H "Authorization: Bearer <ta clé>"` :
```sh
curl -s https://adresse-du-serveur/v1/models | grep -oE '"max_model_len": ?[0-9]+'
```
Rien ne s'affiche : la réponse ne vient pas directement de vLLM (passerelle) ; demande la valeur à l'équipe qui héberge le modèle.

Ce que `/outil pattern` et le coder savent des packages d'un dépôt : internes ou nuget.org, versions, framework de chaque projet, frameworks livrés et documentation XML des packages internes. Dans OpenCode, dans une session ouverte sur ce dépôt :
```text
lance `sh ~/.config/opencode/scripts/package-refs.sh`
```

Ce que `/outil pattern` voit du dépôt source pour un ticket (branche extraite comparée à develop, commits et fichiers de la MR) : dans une session ouverte sur le dépôt source, remplace la clé :
```text
lance `sh ~/.config/opencode/scripts/pattern-source.sh . ABC-123`
```

## Qwen 3.8 : le modèle servi, l'effort de réflexion, les « Gateway Time-out »

Le modèle qui répond vraiment (la plateforme peut envoyer un nom de modèle vers un autre). Remplace l'adresse par la `baseURL` de ton provider et le nom par celui de ton `opencode.json` ; si le serveur demande une clé, ajoute `-H "Authorization: Bearer <ta clé>"` :
```sh
curl -s https://adresse-du-serveur/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"<nom du modèle>","messages":[{"role":"user","content":"Réponds OK"}],"max_tokens":4000}' | grep -oE '"model": ?"[^"]*"|"completion_tokens": ?[0-9]+'
```
Une passerelle peut réécrire le nom affiché : en cas de doute, demande à l'équipe qui héberge le modèle sa taille exacte (27B ou autre) et son `max_model_len`.

L'effort de réflexion (`reasoning_effort`, nouveau dans Qwen 3.8) : la même requête avec un effort bas. Si `completion_tokens` baisse nettement par rapport à la commande précédente, le serveur en tient compte :
```sh
curl -s https://adresse-du-serveur/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"<nom du modèle>","messages":[{"role":"user","content":"Réponds OK"}],"max_tokens":4000,"chat_template_kwargs":{"reasoning_effort":"low"}}' | grep -oE '"completion_tokens": ?[0-9]+'
```
S'il en tient compte, l'effort se règle par agent dans `~/oc2/config/opencode/opencode.json`, section `agent`, par exemple pour le pilote, qui orchestre et n'a pas besoin de réfléchir longtemps : `"pilot": { "options": { "chat_template_kwargs": { "reasoning_effort": "medium" } } }`. À valider sur un `/go` réel avant de le garder ; le coder, l'analyste et le checker gardent l'effort par défaut.

Les « Gateway Time-out » (504) : combien, et les derniers :
```sh
grep -c 'Gateway Time-out' ~/oc2/serve.log
```
```sh
grep 'Gateway Time-out' ~/oc2/serve.log | tail -5 | cut -c1-200
```
OpenCode réessaie seul (la 1.19 faisait 5 essais, de 2 à 30 s d'attente ; le nombre exact de la v2 n'est pas encore mesuré), et chaque essai repart de zéro. À demander à l'équipe qui héberge le modèle, avec ces chiffres : le délai de la passerelle devant vLLM pour `/v1/chat/completions` (une réponse avec réflexion peut durer plusieurs minutes : 10 minutes laisse de la marge), et des réponses en streaming transmises sans mise en tampon (nginx : `proxy_read_timeout 600s` et `proxy_buffering off`).

## Logs d'OpenCode

Le journal de la v2 est `~/oc2/serve.log` (le même contenu va aussi dans `~/oc2/data/opencode/log/opencode.log`).

Les 200 dernières lignes :
```sh
tail -n 200 ~/oc2/serve.log
```

Les avertissements et erreurs récents :
```sh
grep -E 'level=(ERROR|WARN)' ~/oc2/serve.log | tail -30 | cut -c1-300
```

Les refus du plugin du pack (chemin hors du dépôt, dossier en lecture seule, commande qui écrit un identifiant, second `/go`), avec l'agent et le chemin, jamais la commande. C'est ce qu'il faut m'envoyer quand un agent bute sur un refus :
```sh
grep 'refused by the pack' ~/oc2/serve.log | tail -20
```

Les réglages de ta configuration que la v2 ignore ou refuse (`MIGRATION.md`, étapes 8 et 9) :
```sh
grep 'configuration normalization diagnostic' ~/oc2/serve.log | grep -o 'path=[^ ]*' | sort -u
```

Le détail des erreurs « Service Unavailable » ou de contexte du modèle (si le texte parle de « maximum context length », la session a dépassé la taille acceptée par le serveur : voir `limit.context`) :
```sh
grep -iE 'service unavailable|context length|maximum context|too long' ~/oc2/serve.log | tail -5 | cut -c1-300
```

Le chargement du plugin (`0` = pas d'erreur), puis sa connexion aux évènements d'OpenCode (`1` ou plus) :
```sh
grep -c 'failed to load plugin' ~/oc2/serve.log
```
```sh
grep -c 'event stream connected' ~/oc2/serve.log
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

Le `git fetch` que font les commandes au démarrage, dans le dépôt, dans les mêmes conditions qu'un agent (sans invite), avec son temps : `code 0` = OK, `code 124` = GitLab n'a pas répondu en 30 s (VPN, réseau), un autre code avec « terminal prompts disabled » ou « Authentication failed » = identifiants GitLab refusés ou absents (section « Identifiants GitLab »), autre chose = dépôt ou branche introuvable, réseau :
```sh
time timeout 30 env GIT_TERMINAL_PROMPT=0 git fetch -q --no-tags origin; echo "code $?"
```

## Un sous-agent qui semble bloqué

Avec la v2, le titre de la session ne montre pas l'avancement (`MIGRATION.md`, étape 14) : regarde la conversation du pilote, qui montre l'appel du sous-agent en cours. Un sous-agent ne pose jamais de question (le plugin la refuse) : il ne peut pas attendre une réponse de toi. Ce que le serveur du modèle a renvoyé, et les nouveaux essais :
```sh
grep -E 'Gateway|timed out|retry' ~/oc2/serve.log | tail -20 | cut -c1-220
```
Le pilote reprend une fois un checker en échec, puis livre sans auto-review en le disant dans la MR : un `/go` ne reste plus bloqué sur lui. Si les erreurs de passerelle reviennent souvent : section « Qwen 3.8 », la partie « Gateway Time-out ».

## Plusieurs tickets d'un même dépôt (espaces de travail)

Un espace de travail est un deuxième dossier du même dépôt (un worktree git), avec sa propre branche et ses propres sessions. La v2 les crée dans son interface, sans aucun script ; aucun agent n'a le droit d'en créer, d'en supprimer ou de déplacer une session. Organisation conseillée : le dépôt principal reste sur develop pour `/daily`, `/review`, `/compare` et tes questions ; chaque ticket a son dossier.

**1. Créer le dossier d'un ticket.** Sur le projet, « Nouvelle session ». Sous la zone de saisie, clique sur `Local` : un menu « Exécuter la session dans » propose « Dépôt local » et **« Nouvel espace de travail »**. Choisis ce dernier, puis tape `/go ABC-124`. À ce premier message, la v2 crée le dossier dans `~/oc2/data/opencode/worktree/`, à partir de la branche affichée (develop), et la session y travaille. La ligne d'état de la commande dit « Worktree: yes, folder … (main checkout: … ) » : c'est la preuve que la session travaille dans le bon dossier.

Les fichiers ignorés par git du dépôt principal (un `.env`, des réglages locaux) ne sont pas dans le nouveau dossier : copie ceux dont le build ou les tests ont besoin.

**2. Le lendemain.** Les sessions du dossier sont listées avec celles du projet. Pour reprendre : ouvre une de ses sessions, puis `/go` seul ; après la CI, `/fix` dans la même session.

**3. Un ticket en cours dans le dépôt principal, à passer dans un dossier.** Une branche ne s'ouvre que dans un dossier à la fois. Dans le dépôt principal, avec rien de non commité (`git status -s` n'affiche rien ; sinon `/fix` livre d'abord) :
```sh
git switch develop
```
Puis l'étape 1 : `/go ABC-123` dans le nouveau dossier reprend la branche existante, sa fiche et sa MR. Un ticket poussé seulement depuis le Mac : pareil, `/go` récupère la branche de GitLab.

**4. La liste des dossiers du dépôt**, avec leur branche :
```sh
git worktree list
```

**5. Supprimer un dossier, quand la MR est créée ou le ticket abandonné (`/outil abandon`)**, depuis le dépôt principal (remplace le chemin par celui de `git worktree list`) :
```sh
git worktree remove ~/oc2/data/opencode/worktree/<numéro>/<nom>
```
git refuse tant qu'il reste des fichiers non commités ; la branche, elle, reste (la MR en a besoin), avec sa fiche. Archive ensuite les sessions de ce dossier sur l'accueil : sans leur dossier, elles ne peuvent plus rien faire.

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

Le démarrage de ton environnement réécrit `~/.gitconfig` et y remet `cache --timeout=36000` à chaque lancement du serveur : un réglage écrit là ne tient pas. Celui-ci va dans `~/.config/git/config`, que git lit en plus de `~/.gitconfig` sans que le démarrage y touche ; git essaie alors `store` d'abord, le cache ensuite. Si ton équipe a choisi le cache exprès (aucun jeton en clair sur le disque), garde-le plutôt : après chaque démarrage, `git ls-remote --heads origin > /dev/null` dans un dépôt redemande le token, valable 10 heures.

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
3. Le gestionnaire durable, dans le fichier que le démarrage ne réécrit pas :
```sh
mkdir -p ~/.config/git && git config --file ~/.config/git/config --replace-all credential.helper store
```
4. Enregistre le token, une seule fois : git demande le nom d'utilisateur (ton identifiant GitLab), puis le mot de passe : colle le token.
```sh
git ls-remote --heads origin > /dev/null
```
5. Vérifie : le fichier n'est lisible que par toi (la ligne commence par `-rw-------`), et le test passe ; après le prochain redémarrage du serveur, la dernière commande doit toujours afficher `store` (puis `cache`) :
```sh
ls -l ~/.git-credentials
```
```sh
GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin > /dev/null && echo "identifiants OK"
```
```sh
git config --show-origin --get-all credential.helper
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
- Les commandes des agents de la v2 retrouvent ton cache d'identifiants et tes réglages git : le plugin du pack leur retire les dossiers `~/oc2` que la v2 utilise pour elle-même.
- Test OK mais l'agent échoue encore : le serveur OpenCode ne voit pas ces identifiants (démarré par un autre utilisateur, ou trousseau verrouillé) : redémarre-le depuis ce terminal (section « Redémarrer OpenCode »).
- Les agents ne peuvent pas lire ces identifiants : `~/.git-credentials`, `git credential`, le dossier du cache, `security` et `secret-tool` leur sont refusés.

## Todo list

Ta todo, telle qu'elle est enregistrée (tu peux aussi la modifier avec un éditeur : une ligne par tâche) :
```sh
cat ~/.config/opencode/todo.md
```

## Fiche ticket

La fiche du ticket est un fichier Markdown dans le `.git` du dépôt principal. Pour la lire, dans le dépôt (remplace la clé) :
```sh
cat "$(git rev-parse --git-common-dir)/opencode-tickets/ABC-123.md"
```
Pour cocher une étape à la main, ouvre ce fichier dans un éditeur et remplace `- [ ]` par `- [x]` sur sa ligne de « ## Plan ». `/go` vérifie la fiche lui-même après l'analyse.

Ce que `/go` et `/fix` ont fait sur les tickets du dépôt, dans OpenCode :
```text
/outil stats
```

## Contrôle avant push

Avant chaque push de `/go` et `/fix`, un script, sans le modèle, relit tout ce qui va partir : chaque commit pas encore poussé (même un secret retiré par un commit suivant part avec l'historique) et l'état de la branche. Il arrête tout, rien n'est poussé, sur : une clé privée, un token GitLab, GitHub, AWS ou Slack, un utilisateur et un mot de passe dans une URL, un mot de passe dans une chaîne de connexion, une valeur secrète dans un fichier de configuration, un fichier de clé ou `.env` ajouté, un marqueur de conflit, une version payante d'un package, et la valeur exacte d'une variable secrète de ton environnement (un nom avec PASSWORD, TOKEN, SECRET, API_KEY ou CREDENTIAL : le mot de passe Artifactory de `~/.zshenv`), où qu'elle soit. Dans un fichier de test, c'est un avertissement (valeurs factices), sauf pour la valeur d'une variable secrète : elle n'est jamais factice. La valeur n'est jamais affichée : seulement le type et l'endroit.

Il tourne tout seul avant chaque push de `/go` et `/fix`. Pour le lancer sans pousser, dans OpenCode, dans une session du dépôt :
```text
lance `sh ~/.config/opencode/scripts/diff-guard.sh`
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

`/go ABC-123 comme dans ancienne-api (ExportService)` : l'analyste lit l'implémentation de l'autre dépôt et la décrit dans la fiche (section « Référence »), le coder la reproduit. Personne n'écrit dans l'autre dépôt.

Avec la v2, un dossier cité dans un message ne devient pas lisible (`MIGRATION.md`, étape 14) : déclare l'autre dépôt comme référence dans `~/oc2/config/opencode/opencode.json` (au premier niveau, entre deux sections, en gardant les virgules ; le nom, sans espace ni `/`, sert dans `/go … comme dans ancienne-api`), puis redémarre OpenCode :
```json
"references": {
  "ancienne-api": { "path": "~/repos/ancienne-api", "description": "Ancienne API d'export : implémentation de référence de l'export SharePoint vers S3" }
},
```
Pour réutiliser la même implémentation sur plusieurs tickets ou la partager à l'équipe, capture-la plutôt en pattern (section suivante) : `/go` s'en sert ensuite tout seul.

## Documentation (/outil doc)

Ce que `/outil doc` reçoit, à demander dans OpenCode, dans une session du dépôt (lecture seule, aucune valeur de configuration affichée). L'inventaire du dépôt :
```text
lance `sh ~/.config/opencode/scripts/doc-inventory.sh`
```
Les endpoints calculés depuis le code (ajoute un dossier, par exemple `src/Api`, pour un gros dépôt) :
```text
lance `sh ~/.config/opencode/scripts/api-routes.sh`
```
Les clés de configuration, sans leurs valeurs :
```text
lance `sh ~/.config/opencode/scripts/config-keys.sh`
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

Un ticket, du début à la MR en Draft (tes consignes après la clé, facultatives). Relancé, il reprend où il s'était arrêté. La dernière réponse dit l'issue : ✅ MR créée ou rien à faire, ⛔ arrêté avec la raison, ❓ une question t'attend :
```text
/go ABC-123
```
```text
/go ABC-123 avec un Result, sans nouvelle lib
```
Comme une implémentation existante : un pattern de l'équipe, ou un autre dépôt déclaré en référence (section « Lire un autre dépôt ») :
```text
/go ABC-123 comme le pattern export-csv
```
```text
/go ABC-123 comme dans ancienne-api (ExportService)
```
Un gros ticket : l'analyse et le plan seulement, pour les relire avant le code (le `/go` suivant code) ; ou un arrêt après chaque étape :
```text
/go ABC-123 analyse seule
```
```text
/go ABC-123 pas à pas
```
Un changement sans ticket Jira (clé locale `LOCAL-<n>` pour la branche et la fiche ; ni dans les commits ni dans le titre de la MR) :
```text
/go sans ticket : l'export CSV perd le séparateur décimal quand la culture est fr-FR
```
Vérifier un problème sans rien changer : une simple question dans une session (« vérifie pourquoi… ») ; s'il faut corriger, `/go sans ticket : …` dans la même session reprend l'enquête.

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

## Fortify (`/fortify`)

Prérequis, vérifiés au début de chaque `/fortify`, qui s'arrête avec une ligne `STOP:` disant ce qui manque. Pour les voir avant, dans le dossier du dépôt, sans script :

`dotnet` (une version s'affiche) :
```sh
dotnet --version
```
Les projets de tests unitaires (au moins un doit s'afficher) :
```sh
git grep -il -e 'Microsoft.NET.Test.Sdk' -e 'MSTest.Sdk' -e 'xunit.v3' -- '*.csproj'
```
Où coverlet est déclaré : dans chacun de ces projets, ou dans un `Directory.Build.props` (ou `.targets`) d'un dossier au-dessus d'eux :
```sh
git grep -il 'coverlet.collector' -- '*.csproj' '*Directory.Build.props' '*Directory.Build.targets'
```
L'application Fortify SSC du dépôt (une ligne doit s'afficher) :
```sh
git grep -h '^APPSEC_PROJECT_NAME=' -- '*appsec-ci.env'
```
Le cas le plus courant est coverlet, à ajouter par toi, dans sa propre MR, à chaque projet de tests nommé :
```sh
dotnet add <chemin du projet de tests>.csproj package coverlet.collector
```
Lancer un lot depuis develop, dans une session du dépôt : `/fortify` (5 vulnérabilités au plus), `/fortify 3`, `/fortify 5 Path Manipulation`, `/fortify ABC-123` (avec un ticket Jira). Reprendre après une coupure : `/fortify` dans une session sur la branche du lot ; il repart de la vulnérabilité en cours.

Le travail d'une vulnérabilité abandonnée est mis de côté, jamais effacé. Pour le voir puis le ramener (sur la branche du lot, sans fichier non commité) :
```sh
git stash list | grep fortify
git stash pop stash@{<n>}
```
Les mesures d'une vulnérabilité (cartes, couvertures, sorties des tests rouges et verts) sont dans le dossier du lot, jamais commité :
```sh
ls "$(git rev-parse --git-common-dir)"/opencode-tickets/*.fortify/
```

