# Commandes à taper à la main (pack pour OpenCode v2)

Les commandes du pack à taper toi-même, à copier-coller, quand OpenCode v2 tourne à côté de ta 1.19 comme le dit `MIGRATION.md` : sa configuration est dans `~/oc2/config/opencode`, son journal dans `~/oc2/serve.log`, et son programme est `~/oc2/cli/package/bin/opencode` (le simple mot `opencode` reste ta 1.19). Sauf mention « dans OpenCode », elles se tapent dans un terminal de la machine qui héberge OpenCode. Aucune n'affiche de mot de passe ni de token.

**Aucun script à lancer toi-même.** Les commandes de ce guide sont des commandes git, dotnet ou système. Les scripts du pack (`~/.config/opencode/scripts`) sont lancés par les agents ; quand un diagnostic a besoin de l'un d'eux, ce guide te donne la phrase à écrire dans une session OpenCode, et c'est l'agent qui le lance.

## Installer

Tout est dans `MIGRATION.md` : téléchargement de la v2 sans rien installer, configuration collée depuis GitHub et vérifiée par empreintes, démarrage, vérifications. Si la v2 a déjà remplacé ta 1.19 (procédure interne), c'est son annexe A, de l'état des lieux à l'interface web, démarrée par le service de ta procédure (port 4096) ou par `opencode-web.sh` (port <port>) ; la section suivante donne alors tes chemins.

## Si ta v2 a remplacé la 1.19 (annexe A de `MIGRATION.md`)

Les autres sections de ce guide sont écrites pour l'essai côte à côte. Si tu as suivi l'annexe A, remplace dans leurs commandes :

| Dans ce guide | Chez toi |
|---|---|
| `~/oc2/config/opencode` | `~/.config/opencode` |
| `~/oc2/serve.log` | `~/.local/share/opencode/log/opencode.log` |
| `~/oc2/CHECKSUMS-config.txt` et `~/oc2/CHECKSUMS-scripts.txt` | `~/CHECKSUMS-config.txt` et `~/CHECKSUMS-scripts.txt` |
| `~/oc2/cli/package/bin/opencode` | `opencode` |
| `~/oc2/data/opencode/log/openrd-pack.log` (le journal du plugin) | `~/.local/share/opencode/log/openrd-pack.log` |
| redémarrer : Ctrl+C, puis l'étape 6 | avec le service : `opencode service restart` ; avec `opencode-web.sh` : `opencode-web.sh stop && opencode-web.sh start`, ou `oc-web restart` |
| `MIGRATION.md`, étapes 5.5 et 5.6 | annexe A.9 et A.10 |

Les plus utilisées, déjà adaptées :

Redémarrer OpenCode, depuis un terminal ouvert après l'annexe A.11 (il a le mot de passe et les tokens), puis rouvrir l'adresse : le lien de ta plateforme et son rechargement forcé (Cmd+Maj+R), puis la racine (section « Ouvrir l'interface web », annexe A.13). Avec le service :
```sh
opencode service restart
```
Avec `opencode-web.sh` :
```sh
opencode-web.sh stop && opencode-web.sh start
```

Ce qui tourne (une seule ligne de serveur : `… serve --service`, ou `opencode serve … --port <port>`, et peut-être celle de `opencode-web.sh start`) :
```sh
ps -eo pid,args | grep -i '[o]pencode'
```

Le serveur : depuis combien de secondes il tourne (un petit nombre juste après un redémarrage), sa commande et sa version (annexe A.12, point 5) :
```sh
for p in $(pgrep -f -- 'opencode(\.exe)? serve'); do e=$(readlink -f /proc/$p/exe); case $e in */opencode*) echo "pid $p, démarré il y a $(ps -o etimes= -p $p | tr -d ' ') s : $(tr '\0' ' ' < /proc/$p/cmdline)"; $e --version;; esac; done
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
grep -c 'event stream connected' ~/.local/share/opencode/log/openrd-pack.log
```
```sh
grep 'refused by the pack' ~/.local/share/opencode/log/openrd-pack.log | tail -20
```
```sh
grep -E 'run resumed|run not resumed|resume cancelled|summarized|summary of a run failed' ~/.local/share/opencode/log/openrd-pack.log | tail -20
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
2. Ce qui a changé dans la configuration, puis dans les scripts : chaque ligne `FAILED` est un fichier à recoller depuis `opencode-v2/` ; tu as fini quand la commande affiche son `OK`. Un skill nouveau (`skills/<nom>/SKILL.md: FAILED open or read`) a besoin de son dossier d'abord : `mkdir -p ~/oc2/config/opencode/skills/<nom>` (dans cette version : `pack-vitesse`).
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

Dans le terminal de la v2 : Ctrl+C, puis les étapes 6.1, 6.3 et 6.4 de `MIGRATION.md` (les dossiers, le mot de passe, le démarrage). Si la v2 a remplacé ta 1.19 : `opencode service restart` avec le service, `opencode-web.sh stop && opencode-web.sh start` (ou `oc-web restart`) sinon.

Un `/go`, `/fix` ou `/fortify` qui tournait est coupé par le redémarrage. Avec le service, la v2 le reprend toute seule là où il en était, et le plugin lui garde son dossier ; sinon, relance la commande dans sa session : elle reprend à sa dernière étape faite.

## Ouvrir l'interface web (plateforme `<plateforme>.<domaine>`)

Après chaque démarrage de ton poste distant ou du serveur : le lien de ta plateforme qui choisit le port (`…?port=<port>`, celui qu'ouvre `opencode-web.sh`), puis, **dans cet onglet, un rechargement forcé : Cmd+Maj+R** (Ctrl+Maj+R sous Windows ou Linux), puis ton favori, la racine `https://<plateforme>.<domaine>/`. Ni cache à vider, ni mot de passe à retaper.

Pourquoi : l'interface de la v2 s'installe dans le navigateur (un « service worker », pour toute l'adresse `https://<plateforme>.<domaine>/`) et répond elle-même au lien de la plateforme, qui est sur la même adresse. Sans rechargement forcé, le lien n'arrive pas à la plateforme : le port n'est pas transmis, et l'onglet affiche `Unrecognised route!`. Le rechargement forcé passe outre le service worker (vérifié avec une plateforme simulée et le vrai OpenCode v2.1.3). Les lancements suivants de la journée marchaient parce que la plateforme connaissait déjà le port.

Après une mise à jour d'OpenCode : ferme une fois tous les onglets de l'adresse, puis rouvre la racine. Détails et dépannage : annexe A.13 et A.16 de `MIGRATION.md`.

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
S'il en tient compte, l'effort se règle par agent dans `~/oc2/config/opencode/opencode.json`, section `agent`, par exemple pour le pilote, qui orchestre et n'a pas besoin de réfléchir longtemps : `"pilot": { "options": { "chat_template_kwargs": { "reasoning_effort": "medium" } } }`. La v2 lit ces options sans les envoyer : c'est le plugin du pack qui les met dans chaque requête de l'agent (point 28 ; le journal du plugin le dit une fois par agent : `grep 'options of the agent' ~/oc2/data/opencode/log/openrd-pack.log`). C'est le levier de vitesse qui ne touche à rien d'autre : mesure avec `/outil vitesse` (section suivante) avant et après, sur quelques `/go`, et relis les MR comme d'habitude ; le coder, l'analyste et le checker gardent l'effort par défaut tant que la qualité de leurs MR n'est pas confirmée.

Les « Gateway Time-out » (504) : combien, et les derniers :
```sh
grep -c 'Gateway Time-out' ~/oc2/serve.log
```
```sh
grep 'Gateway Time-out' ~/oc2/serve.log | tail -5 | cut -c1-200
```
OpenCode réessaie seul, et chaque essai repart de zéro : la v2 fait jusqu'à 10 nouveaux essais (la 1.19 en faisait 5). Seule, elle les fait en environ 1 min 30 ; pendant un `/go`, `/fix` ou `/fortify` et ses sous-agents, le plugin les étale sur environ 8 minutes (10 s, 20 s, 30 s, 45 s, puis 1 min), pour qu'une passerelle qui redémarre ou une série de 504 n'arrête pas un run. Le titre de la session dit « nouvel essai <n> dans <délai> (serveur du modèle) ». Si le serveur ne répond toujours pas, le run s'arrête, puis le plugin le reprend tout seul 2 minutes plus tard, puis 5 (section « Un run qui reprend tout seul »). À demander à l'équipe qui héberge le modèle, avec ces chiffres : le délai de la passerelle devant vLLM pour `/v1/chat/completions` (une réponse avec réflexion peut durer plusieurs minutes : 10 minutes laisse de la marge), et des réponses en streaming transmises sans mise en tampon (nginx : `proxy_read_timeout 600s` et `proxy_buffering off`).

Un run qui ne reçoit plus rien du serveur (le titre dit « rien reçu depuis <n> min ») : OpenCode attend 15 minutes sans un octet avant de réessayer, et réessaie 3 fois au plus dans ce cas, près d'une heure figée quand le serveur est tombé sans fermer la connexion. Avec vLLM, la réflexion de Qwen arrive token par token : plusieurs minutes de silence au milieu d'une réponse ne sont pas normales. Dans les `options` de ton provider (au même niveau que `baseURL`) : `"chunkTimeout": 300000` (5 minutes). Garde plus long si `/outil vitesse` montre des attentes du premier token de plusieurs minutes : ce délai couvre aussi la file d'attente du serveur avant le premier token. `"headerTimeout"` (5 minutes par défaut) borne l'attente du début de la réponse.

**`Provider request failed with HTTP 400` … `Request doesn't match the schema` … `/messages/<n>/content` … `expected string, received null`**, sur toutes les commandes, dès que l'agent a appelé un outil. OpenCode v2 envoie un message de l'assistant qui ne contient que des appels d'outils avec un contenu `null` (le format OpenAI l'autorise) ; la passerelle de la plateforme exige une chaîne ou un tableau et refuse toute la requête. Le plugin du pack (point 20) envoie ces messages avec un contenu vide `""` : vérifie que tu as bien collé le `openrd-pack.js` de cette version (empreintes de l'étape 5), puis redémarre OpenCode. Une fois corrigé, le log du plugin contient une fois par démarrage :
```sh
grep 'empty content instead of null' ~/.local/share/opencode/log/openrd-pack.log | tail -1
```
Une session déjà en erreur repart avec un simple message (« continue ») : l'historique n'est pas abîmé, c'est la requête qui était refusée.

## Où passe le temps, ce qui bloque (`/outil vitesse`)

Le plugin mesure chaque run d'une commande du pack (point 29) et en écrit une ligne, sans un mot du prompt, dans `openrd-pack-runs.tsv`, à côté de son journal. `/outil vitesse` les lit (les 10 derniers runs ; `/outil vitesse 30`, `/outil vitesse go` pour les seuls `/go`) et affiche tout de suite :
- un tableau par run : sa durée, le temps du modèle du pilote, de ses sous-agents, de ses outils (builds, tests, scripts), de tes réponses aux questions, l'attente moyenne et maximale du premier token, les nouveaux essais, l'issue ;
- où passe le temps, en pourcentages, sur le chemin des runs ;
- le modèle de toutes les sessions : l'attente du premier token pour la première requête d'une session (le serveur lit tout le prompt) et pour les suivantes (il ne devrait relire que ce qui s'ajoute), la part de réflexion et de rédaction, les tokens par seconde ;
- les sous-agents et les outils les plus longs ;
- les points à regarder, chacun avec qui agit : le serveur qui échoue (504, 503 : délai de la passerelle), une passerelle qui garde le streaming en tampon (rien ne s'affiche, puis tout d'un coup : `proxy_buffering off`), un flux qui s'arrête au milieu d'une réponse (`chunkTimeout`), les requêtes suivantes aussi lentes que la première (le prefix caching de vLLM, l'affinité de session quand il y a plusieurs répliques), une file d'attente, une génération lente (MTP, charge), une réflexion longue (l'effort de réflexion par agent, section précédente), des résumés du contexte (`limit.context`, `background_compaction` de la v2.1.4), une préparation lente (`git fetch`), un appel MCP lent, des boucles, tes réponses.

Ce qui revient à l'équipe qui héberge le modèle (passerelle, tampon, prefix caching, répliques, MTP), donne-lui la ligne de `/outil vitesse` et ses chiffres. Ce qui revient à ton `opencode.json` (effort de réflexion, `chunkTimeout`, `limit.context`) : section « Qwen 3.8 » ci-dessus. Les mesures brutes :
```sh
tail -5 ~/oc2/data/opencode/log/openrd-pack-runs.tsv | tr '\t' '\n' | grep -E '^(command|total|top_|wait|think|write|ttft|retries|buffered|stall)'
```

## Logs d'OpenCode

Le journal de la v2 est `~/oc2/serve.log` (le même contenu va aussi dans `~/oc2/data/opencode/log/opencode.log`). Le plugin du pack a le sien, `~/oc2/data/opencode/log/openrd-pack.log` : ce qu'il a refusé et pourquoi, jamais une commande ni un texte de la conversation.

Les 200 dernières lignes :
```sh
tail -n 200 ~/oc2/serve.log
```

Les avertissements et erreurs récents :
```sh
grep -E 'level=(ERROR|WARN)' ~/oc2/serve.log | tail -30 | cut -c1-300
```

Les refus du plugin du pack (chemin hors du dépôt, dossier en lecture seule, commande qui écrit un identifiant, second `/go`, outil fermé de la v2, même appel répété trois fois, commande qui ne finit jamais, changement des dépendances ou installation sur la machine par un agent), avec l'agent et le chemin, jamais la commande. C'est ce qu'il faut m'envoyer quand un agent bute sur un refus :
```sh
grep 'refused by the pack' ~/oc2/data/opencode/log/openrd-pack.log | tail -20
```

Les réponses du modèle coupées parce qu'elles bouclaient (la même phrase répétée pendant la réflexion), avec la session et l'agent ; puis les « continue » repris par le pilote :
```sh
grep 'repeated itself was cut' ~/oc2/data/opencode/log/openrd-pack.log | tail -20
```
```sh
grep "resumed at the developer's request" ~/oc2/data/opencode/log/openrd-pack.log | tail -10
```
Une coupure de temps en temps est normale (le modèle repart, sans la boucle, avec une pénalité de présence). Plusieurs par heure sur le même agent : envoie-moi ces lignes.

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
grep -c 'event stream connected' ~/oc2/data/opencode/log/openrd-pack.log
```

## Après un agent qui a dérapé

Ce qu'il a laissé dans le dépôt (fichiers modifiés ou créés) :
```sh
git status --short
```

Un fichier « sonde » laissé dans le dépôt pour deviner l'API d'un package (un `Probe.cs`, un projet console, un test qui fait de la réflexion sur un assembly) : il apparaît dans la liste ci-dessus ; supprime-le avant `/push`. L'API d'un package se lit dans sa documentation XML : dans une session, « lance `sh ~/.config/opencode/scripts/package-refs.sh --doc Blazorise.DataGrid` », puis demande-lui de chercher le membre dans ce fichier.

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

**Ce qui ne peut plus bloquer pour toujours.** Un appel d'un serveur MCP (Jira, GitLab, Sonar, Fortify) qui ne répond pas finit en erreur après 5 minutes (la v2 attendait jusqu'à 12 heures ; plugin, point 27 ; `"timeout": { "execution": <ms> }` dans la configuration d'un serveur pour un autre délai), et l'agent continue sans lui. Une commande d'un agent du pack a toujours une limite de temps (20 minutes pour un build ou des tests lancés directement, 45 minutes pour un script du pack qui se borne lui-même, 2 heures au plus). Un script du pack qui build et teste s'arrête de lui-même avant cette limite, attente du verrou du dossier comprise, et le dit : `TESTS: TIMEOUT` (section « Une suite trop longue pour la machine »). Le serveur du modèle qui n'envoie plus rien : OpenCode réessaie au bout de 15 minutes, 5 avec `"chunkTimeout": 300000` dans les `options` du provider (section « Qwen 3.8 »). Une question ou une autorisation qui t'attend : le titre commence par ❓.

**L'interface qui ne bouge plus** alors que le titre de la session avance dans la liste de l'accueil : l'interface a perdu son flux d'évènements (une passerelle ou un proxy devant OpenCode qui le coupe ou le garde en tampon) ; recharge la page, le run, lui, a continué.

Le titre de la session du pilote dit ce que fait le sous-agent en cours, par exemple « ⏳ 31:02 outil · Auto-review · nouvel essai 3 dans 45 s (serveur du modèle) — /go ABC-123 », « … · rien reçu depuis 4 min », « … · résumé du contexte », ou « ❓ … · autorisation attendue ». Plusieurs sous-agents à la fois (les analyses de `/fortify`) : « ⏳ 3:10 outils (3) · Analyse V1, Analyse V2, Analyse V3 ». Le titre suit dans la seconde quand un outil démarre ou finit. Un sous-agent ne pose jamais de question (le plugin la refuse) : il ne peut pas attendre une réponse de toi. Ce que le serveur du modèle a renvoyé, et les nouveaux essais :
```sh
grep -E 'Gateway|timed out|retry' ~/oc2/serve.log | tail -20 | cut -c1-220
```
Le pilote reprend une fois un checker en échec, puis livre sans auto-review en le disant dans la MR : un `/go` ne reste plus bloqué sur lui. Pour gagner du temps en fin de run, `/go`, `/fix` et `/fortify` lancent le build et les tests complets **en parallèle** de l'auto-review : la suite tourne dans le même tour que le `checker`, qui ne relance jamais ni build ni tests et revoit en lisant le diff (`git diff <base>...HEAD`, tout est commité). Dans `/fix` et `/fortify`, les failles de sécurité de la branche sont prouvées comme dans `/fortify`, par vagues de test-guardians en parallèle. Un build qui ne s'arrête pas (test qui boucle) est stoppé par `build-test.sh` (`--blame-hang-timeout`) et sa ligne `HANG`/`CRASH` le dit, au lieu de faire attendre tout le run. Si les erreurs de passerelle reviennent souvent : section « Qwen 3.8 », la partie « Gateway Time-out ».

## Un run qui reprend tout seul (↻), un contexte plein

**La reprise automatique.** Un `/go`, `/fix` ou `/fortify` qui s'arrête avant sa réponse finale est repris par le plugin, dans la même session, sans toi : le titre passe à `↻`, puis la conversation montre « ↻ /go ABC-123 · reprise automatique (<raison>) ». Le pilote relit la fiche ticket (et, pour `/fortify`, la carte de la vulnérabilité en cours) et repart de la première étape non faite : rien n'est refait. Les raisons :
- le serveur du modèle ne répond plus, après les essais d'OpenCode : reprise 2 minutes plus tard, puis 5 ;
- le pilote a atteint sa limite d'étapes (100) : reprise dans les 5 secondes ;
- sa dernière réponse n'est pas une réponse finale (aucune ligne qui commence par 🚀, 🔁, ✅, ⏸ ou ⛔ : une réponse coupée en route) : reprise dans les 5 secondes.

Deux reprises au plus d'affilée ; à la troisième panne, le titre passe à `⛔`. Jamais de reprise après un arrêt que tu as demandé (bouton stop), un `⛔` écrit par le pilote (une vraie raison d'arrêt : conflit, identifiants, build de develop…), un refus, ni une erreur qu'une reprise ne règle pas (identifiants du provider refusés, modèle introuvable). Un message que tu tapes dans la session annule une reprise qui attend. Pourquoi une reprise a eu lieu, ou pas :
```sh
grep -E 'run resumed|run not resumed|resume cancelled' ~/oc2/data/opencode/log/openrd-pack.log | tail -10
```

**Un contexte plein.** Quand la conversation d'un run ne tient plus dans le contexte du modèle, la v2 la résume (titre « résumé du contexte ») et repart du seul résumé, qu'elle donne au modèle comme « historique, pas consignes ». Le plugin demande au résumé de garder l'état du run (fiche, dossier du lot, étape et phase en cours, sous-agents à reprendre, commits), puis redonne au pilote les consignes de sa commande, et à chaque sous-agent la tâche que le pilote lui a donnée. Les résumés des runs :
```sh
grep -E 'summarized|summary of a run failed' ~/oc2/data/opencode/log/openrd-pack.log | tail -10
```

**Les marques du titre** : `⏳` en cours, `❓` une question ou une autorisation t'attend, `✅` livré ou rien à faire, `⏸` le run t'attend (une réponse du PO : relance avec la réponse, `/go ABC-123 <réponse>`), `↻` il va reprendre tout seul, `⛔` arrêté.

## Ce qui est relancé tout seul (`RETRY:`)

Une ligne `RETRY:` dans la sortie d'un script, c'est le script qui refait la même chose après une courte pause, parce que l'échec venait d'un instant et pas du code ni de la machine :
```text
RETRY: the package feed did not answer (NU1301): again in 20 s (attempt 2 of 3)
RETRY: GitLab did not answer (Could not resolve host): again in 3 s (attempt 2 of 3)
RETRY: none left: the package registry did not answer (ECONNRESET), at each of the 3 attempts
```
Rien à faire : les dernières lignes donnent le résultat. Ce qui est relancé, et combien de fois (`scripts/transient.sh`) :

| Quoi | Quand | Pauses |
|---|---|---|
| `git fetch` (toutes les commandes) | pas de réponse, connexion coupée ou refusée, nom non résolu, HTTP 429 ou 5xx | 3 puis 10 s, 75 s en tout ; une absence totale de réponse une fois seulement, et jamais au début d'une commande (`workflow-state.sh` continue sans) |
| `git push` (`ship.sh`) | les mêmes ; et la branche qui a bougé sur GitLab pendant le push : ses commits ramenés par merge, le contrôle avant push refait, un nouveau push | 3 puis 10 s, dans les 5 minutes de `ship.sh` |
| `git add`, `commit`, `merge`, `switch` | un autre git tient l'index (`index.lock` : Rider, VS Code) | 1, 2 puis 3 s ; un verrou qui reste est nommé, tu le supprimes toi-même |
| un build .NET, une mesure de couverture | toutes ses erreurs sont le flux de paquets qui ne répond pas (NU1301), ou un fichier tenu par un autre processus (CS2012, MSB3027), ou MSBuild qui perd un nœud (MSB4166) | 20 puis 60 s (10 puis 30 pour un fichier tenu) |
| `npm ci`, `yarn`, `pnpm install` | le registre coupe ou ne répond pas (ECONNRESET, ETIMEDOUT, 5xx), un dossier tenu (EBUSY) | 15 puis 45 s ; l'installation est bornée à 15 minutes |
| `/tests env` (curl) | le fournisseur ou l'environnement coupe, ne répond pas, répond 429, 502, 503 ou 504 | 3 puis 10 s |
| un appel MCP (règle des agents) | pas de réponse, 429, 5xx, connexion coupée | un seul rappel, après 20 s (`pause.sh`) ; une écriture seulement après avoir vérifié qu'elle n'a pas eu lieu |
| un sous-agent arrêté par le serveur du modèle | « Subagent failed » au lieu d'un rapport | repris une fois dans sa session, avant le diagnostic |
| le serveur du modèle (plugin, 18 et 19) | 5xx, délai, connexion | 10 essais étalés sur 8 minutes pour toute commande du pack ; puis le run reprend tout seul 2 puis 5 minutes plus tard (`/go`, `/fix`, `/fortify`, `/tests`) |

Jamais relancé : un test qui échoue (un test qui change de résultat est `FLAKY`, un défaut à corriger), une erreur de compilation, des identifiants refusés (401, 403, `AUTH FAILED`), un paquet ou une référence qui n'existent pas, un conflit, un push refusé par un hook ou une branche protégée, un `TIMEOUT` de suite. Après les essais, la ligne habituelle suit (`ENVIRONMENT PROBLEM`, `STOP`) : c'est un vrai problème, à régler hors d'OpenCode.

## Plusieurs tickets d'un même dépôt (espaces de travail)

Un espace de travail est un deuxième dossier du même dépôt (un worktree git), avec sa propre branche et ses propres sessions. La v2 les crée dans son interface, sans aucun script ; aucun agent n'a le droit d'en créer, d'en supprimer ou de déplacer une session. Organisation conseillée : le dépôt principal reste sur develop pour `/daily`, `/review`, `/compare` et tes questions ; chaque ticket a son dossier.

**1. Créer le dossier d'un ticket.** Sur le projet, « Nouvelle session ». Sous la zone de saisie, clique sur `Local` : un menu « Exécuter la session dans » propose « Dépôt local » et **« Nouvel espace de travail »**. Choisis ce dernier, puis tape `/go ABC-124`. À ce premier message, la v2 crée le dossier dans `~/oc2/data/opencode/worktree/` (`~/.local/share/opencode/worktree/` si la v2 a remplacé ta 1.19), à partir de la branche affichée (develop), et la session y travaille. Ta commande s'affiche « /go ABC-124 — mon-api · worktree <dossier> · … » : c'est la preuve que la session travaille dans le bon dossier. Le titre de la session commence par `[<dossier>]`, pour la retrouver sur l'accueil, qui liste ensemble les sessions de tous les dossiers.

Les fichiers ignorés par git du dépôt principal (un `.env`, des réglages locaux) ne sont pas dans le nouveau dossier : copie ceux dont le build ou les tests ont besoin.

Un espace de travail démarre sur une HEAD détachée (c'est ainsi que la v2 crée ses worktrees). `/go` y crée la branche du ticket ; un travail sans ticket (un POC, un essai) se pousse avec `/push`, qui lui crée d'abord une branche `poc/<résumé>` à partir de ce qui est là (`/push branche essai-cache` pour choisir le nom, `/push feature …` pour un autre préfixe).

**Deux dossiers qui poussent en même temps**, chacun sur sa branche : rien à faire de spécial. Chaque dossier a son verrou de build, son dossier de mesures et sa fiche ; leurs `git fetch` simultanés sont relancés tout seuls s'ils se croisent. Si les deux branches modifient la même ligne, rien ne se voit au push (deux branches différentes) : le conflit apparaît quand la première MR est fusionnée, au prochain `/sync develop` ou `/fix` de la seconde, qui annulent la fusion et nomment le fichier. Tu la refais dans Rider, dans le dossier de la seconde (`git merge origin/develop`), puis `/push`. Une fusion sans conflit (les deux branches touchent des fichiers ou des lignes différents, le cas courant) n'arrête rien : `/fix` ou `/go` de la seconde fusionnent develop tout seuls, puis le build et les tests de toute la suite tournent sur le résultat avant le push. Seul un vrai conflit, ou des tests que la fusion casse, arrête le run, avec le fichier ou le test nommé.

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

## Une suite trop longue pour la machine

Chaque script du pack qui build et teste se borne lui-même : 42 minutes en tout, l'attente du verrou du dossier comprise (un autre build du même dossier : 20 minutes au plus), dont 25 au plus pour une exécution des tests. Au-delà, il arrête les tests et le dit, au lieu d'être coupé par le plugin sans un mot :
```text
TESTS: TIMEOUT (the tests ran until the time of this command ran out, 42 min with the build and the wait for another build of this folder, and were stopped: no result for the whole run)
NOTE: a test run this long cannot prove a change on this machine: AGENTS.md « Build & test », « Tests locaux », gives a filter that leaves its slow tests to the CI …
```
`/go` (et `/fortify`) s'arrêtent alors dès la mesure de la base, avant la première ligne de code : aucun travail perdu, aucune MR sans suite verte. Ce qu'il faut faire : les tests lents (intégration, bout en bout, ceux qui demandent Docker, une base ou le réseau) dans la ligne « Tests locaux » de la section « Build & test » d'`AGENTS.md` ; `/outil setup` la propose, et la CI les lance tous. Jamais une limite relevée, jamais les tests lancés autrement. Avec Microsoft.Testing.Platform, une exécution entière trop longue est dite `TIMEOUT:`, jamais prise pour un test bloqué (`HANG:`, un test à corriger).

## Contrôle avant push

Avant chaque push de `/go` et `/fix`, un script, sans le modèle, relit tout ce qui va partir : chaque commit pas encore poussé (même un secret retiré par un commit suivant part avec l'historique) et l'état de la branche. Il arrête tout, rien n'est poussé, sur : une clé privée, un token GitLab, GitHub, AWS ou Slack, un utilisateur et un mot de passe dans une URL, un mot de passe dans une chaîne de connexion, une valeur secrète dans un fichier de configuration, un fichier de clé ou `.env` ajouté, un marqueur de conflit, une version payante d'un package, des dépendances installées ou des sorties de build qu'un `.gitignore` oublie (`node_modules`, `obj`, `bin/Debug`, `TestResults` ; `dist` et `coverage` : un avertissement), et la valeur exacte d'une variable secrète de ton environnement (un nom avec PASSWORD, TOKEN, SECRET, API_KEY ou CREDENTIAL : le mot de passe Artifactory de `~/.zshenv`), où qu'elle soit. Dans un fichier de test, c'est un avertissement (valeurs factices), sauf pour la valeur d'une variable secrète : elle n'est jamais factice. La valeur n'est jamais affichée : seulement le type et l'endroit.

Il tourne tout seul avant chaque push de `/go` et `/fix`. Pour le lancer sans pousser, dans OpenCode, dans une session du dépôt :
```text
lance `sh ~/.config/opencode/scripts/diff-guard.sh`
```

- Faux positif : ajoute le commentaire `gitleaks:allow` en fin de la ligne signalée (dans Rider), puis relance `/go` (ou `/fix`). Il ne lève pas « value of the environment variable » : cette valeur est réellement ton secret.
- Marqueur de conflit ou package payant : corrige dans Rider (le package : son option gratuite, `/outil licences <package>`), puis relance.
- `node_modules`, `obj`… : les scripts du pack ne les commitent plus (`ship.sh` les laisse hors du commit, avec une ligne `WARNING` : « add obj/ to .gitignore »). S'ils arrivent quand même au contrôle, c'est qu'un commit fait à la main les contient : ajoute le dossier au `.gitignore` du dépôt, puis retire-le des commits pas encore poussés comme pour un secret (ci-dessous), et relance.
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

Le dossier que tu cites, dans un message ou dans les arguments d'une commande que tu tapes, devient lisible par les agents de cette session, en lecture seule : `/go ABC-123 comme dans ~/repos/ancienne-api (ExportService)`. Pas celui d'une option de QCM : ses options sont écrites par le modèle. Un fichier cité rend lisible son dossier, jamais ton dossier personnel lui-même ni un de ses dossiers cachés (`~/.ssh`, `~/.config`…), ni `/proc` : citer `~/.zshenv` ne rend rien lisible. Pour l'avoir dans toutes les sessions, déclare-le comme référence dans `~/oc2/config/opencode/opencode.json` (au premier niveau, entre deux sections, en gardant les virgules ; le nom, sans espace ni `/`, sert dans `/go … comme dans ancienne-api`, et `@ancienne-api` l'ajoute à un message), puis redémarre OpenCode :
```json
"references": {
  "ancienne-api": { "path": "~/repos/ancienne-api", "description": "Ancienne API d'export : implémentation de référence de l'export SharePoint vers S3" }
},
```
Pour réutiliser la même implémentation sur plusieurs tickets ou la partager à l'équipe, capture-la plutôt en pattern (section suivante) : `/go` s'en sert ensuite tout seul.

## Plusieurs dépôts d'une même application (une API et son front, une librairie et ses consommateurs)

Déclare-les une fois, dans une session du dépôt, pas à pas :
```text
/outil liens
```
Il cherche les dépôts git à côté de celui-ci et ce qui les lie (un paquet de l'un utilisé par l'autre, les mêmes clés Jira dans leurs commits, un nom commun, le port local de l'API qu'appelle le front), puis UN QCM : le rôle de chacun (« Le front Angular qui appelle cette API (recommandé) », « La librairie Acme.Montants que ce dépôt utilise »…, ou le tien, ou « Pas lié à ce dépôt »), lesquels les agents peuvent lire (leur code, en lecture seule, par une référence d'`opencode.json` de cette machine), et dans lesquels écrire aussi la ligne réciproque. Un dépôt sans lien visible n'est pas proposé : nomme-le dans un message, puis relance `/outil liens`. Il écrit :
```text
## Dépôts liés
- `front-factures` : le front Angular qui appelle cette API
- `lib-commun` : la librairie NuGet interne des montants
```
et, dans l'`AGENTS.md` du front, la ligne réciproque (« - `api-factures` : l'API .NET que ce front appelle »), jamais commitée : chacun part avec son propre `/push`. Le chemin n'est écrit que pour un dépôt qui n'est ni à côté de celui-ci, ni une référence : chaque développeur range ses dépôts où il veut, sans chemin de sa machine dans un fichier partagé. `opencode.json` est copié avant d'être modifié (`opencode.json.before-outil-liens`, à côté), gardé avec ses commentaires, puis relu : une modification qui le casserait est annulée. Après une référence ajoutée : redémarre OpenCode (il lit ses références à son démarrage).

Rien d'autre à déclarer : c'est la même application parce que chacun nomme l'autre ; le rôle (« le front Angular qui appelle cette API », « l'API que ce front appelle ») dit qui fournit le contrat. Ensuite, pour un ticket qui touche les deux (la même clé Jira, ou deux tickets liés) :
1. **Le dépôt qui fournit le contrat d'abord** (l'API, la librairie) : `/go ABC-123` dans une session de ce dépôt. L'analyste écrit dans la fiche une section « ## Contrat » : chaque route, champ ou membre public ajouté, modifié ou retiré, et ce que les consommateurs doivent faire. L'auto-review compare avec ce que la branche change vraiment (`api-surface.sh`) : une rupture non annoncée est un point bloquant. La MR a une section « Contrat », et la réponse finale dit ce que l'autre dépôt doit suivre.
2. **Le consommateur ensuite** : `/go ABC-123` dans une session du front (ou de l'application qui utilise la librairie). L'analyste lit, par `related-repos.sh ABC-123`, la branche de l'API pour ce ticket, sa fiche, sa ligne « livré » et son « Contrat » : le plan s'appuie sur ce que l'API donne vraiment, jamais sur un champ qu'elle ne donne pas.
3. **Une librairie consommée en paquet** : son changement est livré et publié d'abord (sa propre MR, sa CI, sa version) ; dans le consommateur, monter la version du paquet est une étape du plan que tu valides, jamais un paquet ajouté par le coder.

Les agents lisent toujours la fiche de l'autre dépôt (elle est dans son dossier git) ; son code, quand il est une référence d'`opencode.json`. Pour voir ce qu'ils voient, dans une session :
```text
lance `sh ~/.config/opencode/scripts/related-repos.sh ABC-123`
```

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

Un ticket, du début à la MR en Draft (tes consignes après la clé, facultatives). Relancé, il reprend où il s'était arrêté. Ta commande s'affiche en une ligne, « /go ABC-123 — mon-api · branche develop », le titre de la session montre l'avancement (⏳), et l'issue reste dans le titre et dans la dernière réponse : ✅ MR créée ou rien à faire, ⏸ une réponse du PO t'attend, ⛔ arrêté avec la raison, ❓ une question t'attend. Avant qu'une étape touche du code existant, son filet de non-régression (section « Le filet de non-régression ») : les tests du comportement actuel des méthodes touchées, écrits d'abord par le test-guardian s'il en manque. Un bug se corrige preuve à l'appui : le test-guardian écrit d'abord le test qui le reproduit (rouge), le coder corrige (vert), le test-guardian vérifie (vert deux fois, filet intact, couverture sans perte). À la fin, un QCM « Suite » : `/fix` d'un clic, tout de suite (il attend la fin de la CI, 32 minutes au plus). En fin de `/go`, la suite complète mesure la couverture des lignes modifiées par la branche, et les lignes qu'aucun test n'exécute reçoivent leurs tests (le chiffre va dans la MR : Sonar demande 80 % sur le nouveau code) :
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
Tu ne seras pas là : aucune question, chacune prend sa réponse recommandée (les questions du ticket ambigu, celle du PO, la création du projet de tests ou de bUnit), notée comme décision « choix recommandé, sans question : à valider en review » et listée en tête des décisions de la MR. Aussi pour `/fix` et `/fortify` (« vite » et « en autonomie » veulent dire la même chose) :
```text
/go ABC-123 sans question
```
Sans clé : un QCM avec tes tickets ouverts du sprint et « Sans ticket » (puis une question : ce qu'il faut faire) ; tu peux aussi écrire directement une clé, ou ce qu'il faut faire, à la place de choisir :
```text
/go
```
Une branche de ticket qui porte déjà du travail (commencé sur ton Mac, ou repris d'un collègue) : l'analyste le lit et le plan ne garde que ce qui reste. Un test qui échoue dans la suite complète mais passe à la seconde suite est dit « instable » dans la MR, jamais « corrigé » par le coder.

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
Un ticket qui part d'une autre branche que develop (la branche d'un collègue, une branche de release) : la branche du ticket part de `origin/<branche>`, qui devient sa base pour tout le run (mesure de départ, review, contrôle avant push, fusion de la base, cible de la MR). La branche doit être sur GitLab ; un nom inconnu arrête `/go` avec les noms proches. Une branche de ticket qui existe déjà garde ses commits et prend cette base :
```text
/go ABC-123 depuis feature/ABC-100-socle
```
Vérifier un problème sans rien changer : une simple question dans une session (« vérifie pourquoi… ») ; s'il faut corriger, `/go sans ticket : …` dans la même session reprend l'enquête.

Un POC, un essai, sans ticket : demande-le dans une session (« fais un POC de cache Redis sur GET /orders »). L'agent code et teste dans la conversation, sans branche ni fiche ; il peut lancer un projet du dépôt déjà commité, borné dans le temps (`timeout 60 dotnet run --project src/Api`), jamais un projet ou un fichier créé pour l'occasion. Pour le garder ou le partager : `/push`.

Un run de `/go`, `/fix` ou `/fortify` qui s'est arrêté avant sa fin, ou sur un ⛔ dont tu as réglé la cause (un conflit résolu dans Rider, par exemple) : « continue » (ou « reprends », « vas-y ») dans sa session le reprend avec le pilote, depuis la fiche, quel que soit l'agent choisi sous la zone de saisie. Après ✅ ou ⏸, « continue » est un message ordinaire.

Pousser ton travail, avec ou sans ticket : `/push` lit tes changements et te pose UNE question (trois au plus dedans, un clic ou ton propre texte pour chacune) :
- **Branche**, seulement s'il en faut une (sur develop, main ou une HEAD détachée ; jamais de commit sur develop) : la recommandée d'après la nature du travail (`test/…` pour des tests seuls, `docs/…` pour de la doc, `bugfix/…`, `feature/…`, `refactor/…`, `chore/…`, `poc/…` pour un essai), puis une ou deux autres ;
- **Commit** : deux ou trois messages au format conventional commit (`feat(export): add the CSV export`), le recommandé d'abord ;
- **MR** : en Draft vers la base (recommandée, sauf pour un POC) ou pas de MR. Pas posée si la branche a déjà sa MR : le push la met à jour.

Ce que tu dis dans ta commande n'est pas redemandé ; `vite` prend les choix recommandés sans question. Avant la question, le code modifié est buildé et testé (`build-test.sh --if-changed` : pas relancé si ce même code vient de passer au vert dans la conversation ; rien pour de la doc seule ; pas de build ici pour un projet .NET Framework). En échec, la question commence par « Build » ou « Tests » : « Ne rien pousser, je corrige » (recommandé) ou « Pousser quand même » (un travail en cours, ou des tests déjà rouges sur develop) ; avec `vite`, rien n'est poussé. `sans les tests` saute le build. Le nom de branche que tu tapes est rendu valide s'il le faut (espaces, caractères refusés par git), et la réponse le dit. Un commit fait par erreur sur develop part sur la nouvelle branche, et develop revient à origin/develop. Puis il fusionne ce que tu as poussé sur la branche depuis ton autre poste, passe le contrôle avant push, et pousse ; « avec develop » fusionne aussi la base :
```text
/push
```
```text
/push fix(export): keep the decimal separator avec MR
```
```text
/push branche poc/essai-cache-redis sans MR vite
```
Après la CI d'une branche poussée par `/push` : `/fix`, comme pour un ticket (jobs en échec, Sonar, Fortify, discussions de la MR). Sans ticket, il ne remplit pas de fiche et ses commits n'ont pas de clé ; sur une branche `poc/…` ou `wip/…`, il ne crée pas de MR.

Des tests unitaires sans ticket : `/tests` avec une classe, un fichier ou un dossier. Le test-guardian mesure la couverture, écrit les tests du comportement actuel dans le style des tests existants, les prouve (verts deux fois, aucun test instable), et mesure la couverture après. Un test qui révèle un bug n'est pas gardé : le bug est dans la réponse, à corriger avec `/go sans ticket : …`. Le tout est commité sur une branche `test/…` (ou sur ta branche si tu en as une), rien n'est poussé : la réponse te propose `/push`. Sans projet de tests, il propose de le créer en premier commit :
```text
/tests InvoiceService
```
```text
/tests src/Billing seulement les cas d'erreur
```
Les endpoints d'une API, scénario par scénario : `/tests api` ; un environnement déployé, déclaré puis vérifié : `/tests env config recette`, puis `/tests env recette` ; et `/tests` seul pour son menu (section « Tests d'API »).
Récupérer ce que tu as poussé depuis ton Mac (Rider), sans rien commiter ni pousser : tes modifications non commitées restent là. Avec « develop », les nouveaux commits de la base aussi ; « merge <branche> » pour une autre branche. Sur develop lui-même : une avance rapide sur origin, jamais une fusion. Un conflit : la fusion est annulée et les fichiers listés, tu la fais dans Rider :
```text
/sync
```
```text
/sync develop
```
```text
/sync merge hotfix/ABC-130-urgent
```

Après la CI ou la review (jobs en échec, Sonar, Fortify, discussions de la MR), sur la branche d'un ticket (pour simplement pousser : `/push`). Une faille Fortify ou Sonar des fichiers de la branche, ou un bug qu'un test peut reproduire (3 au plus par `/fix`), est corrigé avec son filet de non-régression et sa preuve, comme dans `/fortify` ; un refactoring demandé (complexité Sonar, duplication, une discussion qui change le fonctionnement d'une méthode) a son filet d'abord ; une faille que le test-guardian ne parvient pas à montrer (le code résiste déjà) garde ses tests et part en « Faux positifs probables ». Lancé pendant que la CI du commit poussé tourne encore (juste après `/go`, par exemple), il l'attend d'abord, 32 minutes au plus, par pauses de 4 minutes après chacune desquelles il ne relit que le statut du pipeline, sans ses jobs (le titre montre « pause.sh ») : 8 tours au plus, peu de tokens ; puis il traite ses retours, et lit la fin du journal de chaque job en échec, là où est l'erreur ; « sans attendre » ne l'attend pas. Un job en échec pour une raison hors du code (runner, réseau, délai du job, registre ou flux de paquets muet) n'est jamais « corrigé » : la réponse dit de le relancer dans GitLab :
```text
/fix
```
```text
/fix seulement la review
```
```text
/fix sans attendre
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

Les requêtes de chaque endpoint pour Rider, `/daily` ou les tests d'un environnement lancés tout seuls chaque matin, et les dépôts d'une même application (sections « Requêtes `.http` pour Rider », « Planifier une commande » et « Plusieurs dépôts d'une même application ») :
```text
/outil http
```
```text
/outil planifier 8h45 lun-ven /daily
```
```text
/outil liens
```

Les autres outils (audit, licences, release notes, cqrs, AGENTS.md du dépôt, abandon d'un ticket) :
```text
/outil
```

Un QCM qui propose des commandes (`/daily` : « Sur quoi tu bosses ? » ; et le « Suite » qui finit chaque commande : `/fix` après `/go`, `/push` après `/tests`…) : l'option choisie démarre toute seule dans la même session, dès que l'agent a fini sa réponse. Tu peux aussi taper ta propre réponse, par exemple `/go ABC-12 avec un feature flag`. Pendant qu'un « Suite » attend, le run est fini : le dossier est libre pour une autre commande, et le titre garde son issue. Dans la conversation, toute action proposée est un QCM de même : ton choix est le feu vert, l'agent la fait sans redemander.

Ajouter un skill ou une référence à ton message : tape `@`, la liste s'affiche (les skills du pack, tes `pattern-…`, les références d'`opencode.json`). Par exemple :
```text
@build-fix pourquoi ce build casse ?
```

## Front-end (Angular, React, Vue)

Les agents buildent et testent un front avec le même script que .NET, en lui donnant le dossier de son `package.json` (`.` pour un dépôt sans .NET) :
```text
lance `sh ~/.config/opencode/scripts/build-test.sh ClientApp`
```
Il installe les dépendances quand elles manquent, depuis le lockfile seulement (`npm ci`, `yarn --frozen-lockfile`, `pnpm --frozen-lockfile` : jamais un paquet ajouté ni monté), lance le script `build`, puis les tests **une fois** : Karma dans ChromeHeadless avec `--watch=false` (Angular jusqu'à la 20), Vitest avec `--watch=false` (Angular 21), `--watchAll=false` (Create React App), `--run` (Vitest), Jest tel quel. Il finit par `BUILD:` et `TESTS:` comme pour .NET ; une spec seule : `build-test.sh ClientApp --filter src/app/x/x.component.spec.ts`. Un test focalisé (`fit`, `fdescribe`, `.only`) fait échouer le run : le reste de la suite ne tournerait pas. Les tests de bout en bout (Playwright, Cypress) sont laissés à la CI. Un run qui ne finit pas est arrêté au bout de 15 minutes (`HANG:`).

Ce qu'il faut sur la machine d'OpenCode : node (une version que le projet accepte : `.nvmrc` ou `engines`, sinon un avertissement), le gestionnaire de paquets du lockfile (`corepack enable` pour yarn ou pnpm), Chrome ou Chromium pour Karma, et l'accès au registre npm (Artifactory). Une ligne `ENVIRONMENT PROBLEM` dit ce qui manque ; `STOP: the lockfile … is not in sync` veut dire que `package.json` a changé sans son lockfile (à toi de lancer `npm install`) ; `STOP: git does not ignore node_modules` veut dire que le `.gitignore` du dépôt doit ignorer `node_modules` avant toute installation. `ENVIRONMENT PROBLEM: npm … failed inside itself` (« Cannot read properties of null (reading 'edgesOut') ») : un bug de npm 10, connu sur l'arbre de Vitest 4 (Angular 21) quand il résout les dépendances sans lockfile ; mets à jour npm sur la machine, hors d'OpenCode (sa dernière version que ta version de node accepte, ou node avec son npm) ; jamais `--legacy-peer-deps`, qui peut produire un lockfile que `npm ci` refuse ensuite.

Un agent ne change jamais les dépendances : `npm install` (même sans paquet : il réécrit `package-lock.json`), `yarn add`, `dotnet add package` ou `dotnet package add` lui sont refusés en une phrase, comme une installation sur la machine (`npm i -g`, brew, `corepack enable`) ; une étape qui a besoin d'un paquet revient « BLOQUÉ » avec le paquet, sa version et pourquoi, et c'est toi qui l'ajoutes. En conversation, ces commandes restent les tiennes.

**Les commandes qui ne finissent jamais sont refusées aux agents du pack** : `npm start`, `ng serve`, `vite`, `next dev`, un `--watch`, `ng test` sans `--watch=false`, `npm test` quand son script regarde les fichiers (le plugin lit `package.json` : `npm test` d'un projet Jest passe, celui d'un Angular avec Karma est refusé), `dotnet watch`, `dotnet run` d'une API. Le refus donne la bonne commande. À savoir : `npm test --watch=false` ne passe pas l'option au script (npm la garde pour lui) ; c'est `npm test -- --watch=false`, et le refus le dit. Dans la conversation, tu peux en lancer une toi-même : l'agent la lance en arrière-plan (l'option d'arrière-plan de l'outil shell de la v2), ou bornée : `timeout 60 npm run dev`.

## Blazorise (DataGrid, langue, remplacement par du Razor natif)

Quand le dépôt référence Blazorise, `detect-project-type.sh` le dit avec sa version (`Blazorise 2.2.2: the skill blazorise …`) et les agents chargent le skill `blazorise` dès que le code touche ses composants : la langue du DataGrid et de sa pagination, ses textes, l'API de la version installée (jamais un membre inventé : il se lit dans la documentation XML du paquet ; la 2.0 de février 2026 a renommé beaucoup de choses, `TextEdit` devenu `TextInput`, `CurrentPage` devenu `Page`…), puis son remplacement par du Razor natif.
```text
/go ABC-123            (« le DataGrid des commandes en français, pagination comprise »)
```
- La langue : les textes de Blazorise en français pour chaque utilisateur, sans changer les formats de dates et de nombres de l'application ; les textes à corriger (« items », « Sauvegarder »…) dans une seule instance de `DataGridLocalizers` que chaque grille reprend.
- Blazorise est payant pour une entreprise (une licence par développeur front, les prestataires compris ; la licence Community gratuite est réservée à des développeurs individuels éligibles), et sans licence son DataGrid s'arrête à 1 000 lignes : une grille qui « perd » des lignes au-delà, c'est la licence, pas un bug. Aucun agent n'ajoute ni ne monte un paquet Blazorise ; `/outil licences` le signale avec son alternative gratuite.

### Remplacer Blazorise par du Razor natif, page par page

100 % natif, sans aucun paquet (pas même QuickGrid) : `EditForm` et ses `Input…` pour les formulaires, le HTML avec les classes Bootstrap que l'application charge déjà, et les composants natifs que `blazor-native.sh scaffold` écrit une fois dans le code de l'application, dans `Components/Native` : `NativeGrid` avec `NativeColumn` et `NativeTemplateColumn` (tri d'un clic, pages et pager en français avec les mots du DataGrid, texte d'une liste vide, clic sur une ligne et ligne sélectionnée, données d'un serveur), `NativeModal`, `NativeDialogService` et son hôte (les questions et les messages d'`IMessageService`), `NativeToastService` et son hôte (les notifications), et les classes Bootstrap d'un champ. Ils appartiennent ensuite à l'application : à adapter comme le reste de son code.
```text
/go sans ticket : remplacer Blazorise par du Razor natif dans toute l'application
```
```text
/go ABC-124            (« retirer Blazorise de l'application »)
```
Ce qui se passe :
1. **L'inventaire** : l'analyste lance `blazor-native.sh inventory`, qui lit chaque page (jamais une liste apprise par cœur) : ses balises Blazorise, leur famille, les services injectés et leur remplaçant, les enregistrements de `Program.cs`, les liens `_content/Blazorise…`, les paquets et leur version, les clés de licence (leur nom, jamais leur valeur), l'équivalent natif de chaque balise, et l'ordre des pages : les plus simples d'abord (icônes, boutons, mise en page), puis les formulaires, les fenêtres et les messages, puis les grilles. Une balise qu'il ne connaît pas va dans « Décisions », à vérifier.
2. **bUnit** : les tests d'une page Blazor passent par bUnit (il affiche la page dans le test, sans navigateur). Quand aucun projet de tests ne l'a (`fortify.sh prereq --tests` : « COMPONENT TESTS: none »), une question « Composants » arrive avec celles de l'analyse : « Oui (recommandé) » l'ajoute en premier commit (`test-guardian.sh setup --components`) ; « Non » laisse ces pages sans filet, et la MR le dit.
3. **Les composants natifs** : la première étape du coder lance `blazor-native.sh scaffold <le projet web>` (refusé à tout autre agent) ; ils compilent à côté de Blazorise, tous nommés `Native…` pour n'en croiser aucun nom. Il enregistre aussi ce que les pages demanderont (`NativeDialogService`, `NativeToastService` et leurs hôtes dans la mise en page).
4. **Le filet d'abord, pour chaque page** : le test-guardian écrit les tests de ce que voient ses utilisateurs (les titres des colonnes dans l'ordre, la première page, les dates et montants en français, la page suivante, un tri par un clic), verts deux fois sur Blazorise, puis scellés. Ils cherchent des textes, jamais une classe CSS, un id ou un type Blazorise : les mêmes tests doivent passer tels quels sur la page native.
5. **La page en natif** : le coder la réécrit avec les équivalents du skill ; l'étape est finie quand les tests scellés passent, sans une ligne changée, deux fois, sans couverture perdue.
6. **La dernière étape** retire les paquets, les `@using`, `AddBlazorise…`, `ProductToken` (le jeton de licence : c'est toi qui le retires de la configuration et des coffres de secrets), les liens `_content/Blazorise…` et les lignes Blazorise de l'aide des tests ; elle finit quand `blazor-native.sh check` dit « BLAZORISE: GONE », le build et tous les tests verts. Le checker refait la même vérification.

Ce qui change sans erreur de compilation (le skill le donne au coder, les tests l'attrapent) :

| Sur Blazorise | Avec les composants natifs | À vérifier dans l'étape |
|---|---|---|
| un champ change sa valeur à chaque frappe | `InputText` la change quand on quitte le champ | une recherche qui filtre en tapant : `<input @bind="search" @bind:event="oninput">` |
| chaque colonne se trie d'un clic | `NativeColumn` aussi, un second clic du plus grand | une colonne de boutons se trie avec `SortBy` ; `Sortable="false"` pour l'en empêcher |
| les pages, 10 lignes par défaut | `NativeGrid ShowPager PageSize`, les mêmes | le premier test de la page dit combien de lignes Blazorise montrait |
| les textes du pager en français | « Première », « Précédente », « Suivante », « Dernière », « Page 1 sur 3 · 12 éléments » | rien |
| un clic sur une ligne, la ligne sélectionnée, la liste vide | `RowClicked`, `@bind-SelectedItem`, `EmptyText` | un bouton dans une ligne cliquable : `@onclick:stopPropagation="true"` |
| les messages de validation en rouge Bootstrap (`is-invalid`) | `NativeFieldCssClassProvider` | `editContext.SetFieldCssClassProvider(…)` dans la page |
| une fenêtre avec ses boutons | `NativeModal` | son contenu et ses boutons nommés tous les deux : `<ChildContent>…</ChildContent><Footer>…</Footer>` |
| une confirmation, une notification | `NativeDialogService.ConfirmAsync`, `NativeToastService.Success` | leurs hôtes dans la mise en page ; les tests de la page les affichent avec elle |
| les dates : le sélecteur de Blazorise | `InputDate` : celui du navigateur, dans sa langue | la valeur est la même |

Pour poser le filet d'une page à la main, sans rien changer : `/tests Components/Pages/Orders.razor` (avec la question « Composants » quand bUnit manque). Pour voir où en est le retrait, dans une session : « lance `blazor-native.sh check` » (lecture seule).

**Prouvé pour de vrai à chaque push** (`tools/blazor-native-test.sh`, dans la CI, avec .NET 10 et .NET 8) : l'inventaire d'une application, une page des commandes sur le DataGrid de Blazorise 2.2.2, le projet de tests créé avec bUnit par `setup --components`, quatre tests de ce que voient ses utilisateurs écrits sur Blazorise (verts deux fois, scellés), les composants natifs écrits par `scaffold` qui buildent à côté de Blazorise, la même page réécrite avec `NativeGrid` : les quatre tests passent sans une ligne changée, rien n'est perdu ; puis treize tests bUnit des composants eux-mêmes (données d'un serveur, tri, pages, colonne sous condition, sélection, fenêtre, questions, messages, toasts, classes d'un champ) ; enfin Blazorise retiré entièrement et `check` « GONE », avec le code du skill tel qu'il est écrit.

## AutoMapper (remplacement par Mapperly ou Mapster)

AutoMapper est payant depuis la 15.0 (juillet 2025 : licence commerciale ; l'édition Community gratuite seulement sous 5 M$ de chiffre d'affaires annuel, avec une clé), et toutes ses versions gratuites (14 et avant) ont la CVE-2026-32933 (élevée : un graphe d'objets profond fait déborder la pile, un déni de service), corrigée seulement dans les versions payantes 15.1.1 et 16.1.1. Rester en 14, c'est garder une faille connue ; monter de version, c'est payer. Quand le dépôt le référence, `detect-project-type.sh` le dit (`AutoMapper 14.0.0: paid from 15.0, CVE-2026-32933 …`) et les agents chargent le skill `automapper`.

Deux remplaçants, au choix du développeur (la question « Cible ») :
- **Mapperly** (Apache-2.0), recommandé : un générateur de code, le mapping est du C# ordinaire écrit à la compilation (lisible, pas à pas dans le débogueur), sans paquet à l'exécution ni réflexion, le plus rapide, compatible AOT ; un membre de destination oublié refuse le build, là où AutoMapper ne le voyait qu'à l'exécution (et seulement si un test appelait `AssertConfigurationIsValid`). Ce que ça coûte : chaque appel d'`IMapper` réécrit (`order.ToOrderDto()`), chaque test qui mocke `IMapper` réécrit avec le vrai mapper.
- **Mapster** (MIT), le plus proche d'AutoMapper : le même modèle (une configuration au démarrage, chaque map compilée à son premier usage), un `IMapper` aux mêmes méthodes : les appels, les constructeurs et les mocks d'`IMapper` restent, seuls leurs `using` changent (`automapper.sh switch`) ; BeforeMap, AfterMap, Condition, les resolvers à services et `Items` ont leur équivalent un pour un. Ce que ça coûte : un membre oublié est trouvé par un test (le test des Registers), pas par le build ; le paquet tourne avec l'application ; pas d'AOT.
- **À la main** : les mêmes méthodes que Mapperly générerait, sous les mêmes tests ; rien ne dit qu'un membre ajouté plus tard n'est pas mappé.

Les faits du choix sont dans l'inventaire (ses deux lignes TARGET : appels à réécrire ou à garder, mocks d'`IMapper`, BeforeMap/AfterMap/Condition, resolvers à services, `Items`) : beaucoup d'appels et de mocks d'`IMapper`, d'`Items` ou de `ResolutionContext` dans les maps, Mapster change le moins de code ; une librairie, l'AOT, ou le build comme garde-fou, Mapperly. Dans les deux cas, ce sont les tests enregistrés sur AutoMapper qui prouvent que rien n'a changé.
```text
/go sans ticket : remplacer AutoMapper dans toute l'application
```
```text
/go sans ticket : remplacer AutoMapper par Mapster dans toute l'application
```
```text
/go ABC-125            (« retirer AutoMapper »)
```
Ce qui se passe :
1. **L'inventaire** : l'analyste lance `automapper.sh inventory`, qui lit chaque profil (jamais une liste apprise par cœur) : les profils dans l'ordre où les remplacer (les plus simples d'abord), chaque map avec ses options (`ForMember`, `ReverseMap`, `BeforeMap`…), les projets à équiper, les resolvers et converters (ceux qui prennent des services font un mapper d'instance), les réglages globaux, les appels (`Map<T>`, `Map(source, destination)`, `ProjectTo`, `IMapper` injecté), l'enregistrement (`AddAutoMapper`), les tests qui dépendent d'AutoMapper, ce que `scaffold` laisse à la main pour chaque cible et les faits du choix.
2. **La question « Cible »**, avec celles de l'analyse (sauf si ta demande la nomme) : « Mapperly (recommandé) » ajoute `Riok.Mapperly` en premier commit (`automapper.sh setup`, lancé par le pilote seul : à la compilation seulement, rien dans les binaires ; `Mapperly.globalconfig` fait d'un mapping incomplet ou ambigu une erreur de build ; `MapperDefaults.cs` reprend les règles d'AutoMapper : noms sans casse, aplatissement, enums par nom). « Mapster » ajoute `Mapster` et `Mapster.DependencyInjection` (`automapper.sh setup --mapster` : `MapsterSetup.cs` reprend les mêmes règles, `AddMapsterMaps` remplacera `AddAutoMapper` ; refusé, sans rien changer, si un projet référence `Microsoft.Extensions.DependencyInjection.Abstractions` avant la 9.0.0 : tu la montes, puis `/go` à nouveau). « À la main » : les mêmes méthodes écrites à la main, sous les mêmes tests.
3. **Le filet d'abord, pour chaque profil** : le test-guardian écrit les tests instantanés de ses maps (`automapper.sh helpers` : une source dont chaque membre a sa propre valeur, une autre dont les membres qui peuvent être nuls le sont), sur AutoMapper ; `automapper.sh record` écrit ce qu'AutoMapper donne dans des fichiers de référence (`Mapping/Snapshots/*.json`), jamais réécrits ensuite ; verts deux fois, scellés avec eux. Avec Mapster, au premier profil : le test des Registers, qui remplace `AssertConfigurationIsValid`.
4. **La traduction** : la première chose de l'étape du coder est `automapper.sh scaffold <le profil>` (`--mapster` pour Mapster ; refusé à tout autre agent), qui traduit chaque map à côté du profil (Mapperly : le mapper, BeforeMap, AfterMap et Condition dans une méthode autour de la méthode générée ; Mapster : le Register, Condition en `IgnoreIf`) ; ce qu'il ne sait pas traduire (un resolver, un converter en classe…) est cité au-dessus avec une ligne TODO, que le coder finit avec le skill ; puis l'adaptateur des tests (`Mapped.cs`, le seul fichier de test qui change), et, avec Mapperly, les appelants. L'étape est finie quand le build passe (Mapster : et le test des Registers) et que les tests scellés passent tels quels, deux fois : la nouvelle cible donne ce qu'AutoMapper donnait, membre par membre.
5. **La dernière étape** : avec Mapster, `automapper.sh switch` bascule le code qui utilisait AutoMapper (les `using`, `ProjectTo` en `ProjectToType`, `AddAutoMapper` en `AddMapsterMaps`, les configurations des tests ; ce qu'il ne réécrit pas, il le liste) ; puis les profils, resolvers et converters, `AddAutoMapper`, les derniers `IMapper` (Mapperly), le test de `AssertConfigurationIsValid` et le paquet partent ; elle finit quand `automapper.sh check` dit « AUTOMAPPER: GONE ».

| AutoMapper | Mapperly | Mapster |
|---|---|---|
| `CreateMap<S, D>()` | `public static partial D ToD(this S source);` dans le mapper du profil | `config.NewConfig<S, D>()` dans le Register du profil |
| membres de même nom, aplatissement (`CustomerName` ← `Customer.Name`) | rien à écrire | rien à écrire |
| `ForMember(d => d.X, o => o.MapFrom(s => s.A.B))` | `[MapProperty("A.B", nameof(D.X))]` | `.Map(d => d.X, s => s.A.B)` |
| `MapFrom(une expression)`, `NullSubstitute(v)` | `[MapPropertyFromSource(nameof(D.X), Use = nameof(Helper))]`, `[MapProperty(…, Use = nameof(OrNone))]` | `.Map(d => d.X, s => …)`, `.Map(d => d.X, s => s.X ?? v)` |
| `Ignore()` | `[MapperIgnoreTarget(nameof(D.X))]` | `.Ignore(d => d.X)` |
| `ReverseMap()` | une seconde méthode ; l'inverse de l'aplatissement par `[MapProperty]` | un second `NewConfig<D, S>()` avec `.Unflattening(true)` |
| `BeforeMap`, `AfterMap` | une méthode autour de la méthode générée, `[UserMapping(Default = true)]` | `.BeforeMapping(...)`, `.AfterMapping(...)` |
| `Condition(...)` | dans la méthode autour : le membre laissé tel quel sinon | `.IgnoreIf((s, d) => !(...), d => d.X)` : le membre laissé tel quel sinon |
| `ConvertUsing(...)` | une méthode `[UserMapping(Default = true)]` | `.MapWith(...)` |
| `Include<S1, D1>()` | `[MapDerivedType<S1, D1>]` | `.Include<S1, D1>()` |
| `ForCtorParam("p", ...)` | `[MapProperty]` ou `[MapPropertyFromSource]` vers le paramètre | `.Map("p", ...)` |
| `MapFrom<TResolver>()` dont le resolver prend des services | un mapper d'instance, ces services dans son constructeur | `MapContext.Current.GetService<T>()` dans la map |
| `ProjectTo<D>()` | `ProjectToD(this IQueryable<S>)`, traduit dans la requête SQL | `ProjectToType<D>(mapper.Config)` |
| `Map(source, destination)` | une méthode `ApplyTo` qui mappe sur l'objet existant | inchangé |
| `AddAutoMapper(...)`, `IMapper` injecté | rien (mapper statique) ou `services.AddScoped<InvoiceMapper>()` | `AddMapsterMaps(typeof(XRegister))`, `IMapper` inchangé |
| `opts.Items["k"]` | un paramètre de plus de la méthode | `mapper.From(s).AddParameters("k", v).AdaptToType<D>()` |

Ce qui pourrait changer sans erreur, et que les tests instantanés attrapent (les skills donnent la correction) : une liste nulle (AutoMapper donnait une liste vide : `MapsterSetup.cs` et les helpers de Mapperly la rendent vide), un membre qui peut être nul vers un membre qui ne le peut pas, une expression de `MapFrom` qui rencontre un null (AutoMapper donnait la valeur par défaut, Mapperly et Mapster lèvent une exception), une date ou un nombre mis en texte dans la culture du thread, la liste d'un objet existant (AutoMapper la vidait et la remplissait, Mapperly et Mapster en mettent une nouvelle). Une valeur d'enum source sans valeur de même nom dans la cible : Mapperly refuse le build ; Mapster lève une exception quand il la mappe (AutoMapper donnait la valeur) : le skill `mapster` dit comment la mapper.

Pour poser le filet d'un profil à la main, sans rien changer : `/tests src/Shop/Mapping/OrderProfile.cs`. Pour voir où en est le retrait, dans une session : « lance `automapper.sh check` » (lecture seule).

**Prouvé pour de vrai à chaque push** (`tools/automapper-test.sh`, dans la CI, avec .NET 10 et .NET 8) : une application dont les deux profils utilisent chaque forme du tableau (resolver avec service, projection, map sur un objet existant avec une condition — un « patch » — compris) et un service qui mappe avec `IMapper` ; l'inventaire ; les tests instantanés écrits et enregistrés sur AutoMapper 14.0.0, verts deux fois, scellés. Puis, depuis ce même filet, les deux cibles. Mapperly 4.3.1 : ajouté (et son échec, qui remet tout) ; le mapper que `scaffold` a traduit passe les tests tel quel, le TODO laissé (le resolver) est refusé par le build ; les mappers du skill : les mêmes tests verts deux fois et la même requête SQL de projection dans une vraie base SQLite ; un membre oublié et une valeur d'enum sans cible refusés par le build ; AutoMapper retiré, `check` « GONE », aucune assembly de Mapperly dans les binaires. Mapster 10.0.13 : ajouté (et son refus d'une `Microsoft.Extensions.DependencyInjection.Abstractions` 8) ; le Register que `scaffold --mapster` écrit, exactement celui du skill ; le TODO refusé par le test des Registers ; les mêmes tests verts deux fois ; un membre oublié refusé par le test des Registers ; `switch`, AutoMapper retiré, `check` « GONE », tout vert, l'enregistrement par le conteneur compris.

## Versions de .NET, environnement et librairies

`detect-project-type.sh` (en tête de chaque `/go`, `/fix`, `/push`) donne, depuis les fichiers du dépôt :
```text
Target frameworks: net8.0 (src/Api, tests/Api.Tests), netstandard2.0 (src/Contracts)
C#: 12 for net8.0, 7.3 for netstandard2.0 (the defaults: no LangVersion): never a feature of a newer C# version; a project with several targets compiles for each
.NET SDK: global.json asks for 8.0.400 (rollForward latestFeature): 8.0.404 is installed
Test runtimes: installed (net8.0: Microsoft.AspNetCore.App, Microsoft.NETCore.App)
Support: net8.0 (ends on 2026-11-10); .NET 10 (LTS) is supported until 2028-11-10. Moving to it is a ticket of its own, never part of another change
Front-end: ClientApp — angular 19, npm, tests: Karma through the Angular CLI (ChromeHeadless, --watch=false); Node: v22.12.0
```
Et pour une librairie :
```text
Library: src/Lib/Lib.csproj packable; version: 2.3.0 (Version in src/Lib/Lib.csproj); package validation: on, against 2.2.0: dotnet pack fails on a breaking change (build-test.sh --pack)
```
Le coder écrit pour cette version : C# 12 et les API de .NET 8 dans un projet net8.0 (jamais `LangVersion` relevé, jamais un framework cible ni `global.json` changés, jamais un paquet ajouté pour une fonctionnalité plus récente). Une machine incomplète s'arrête en une ligne `ENVIRONMENT PROBLEM` au lieu d'être « réparée » dans le dépôt : le SDK que demande `global.json` absent, le runtime des tests absent (un projet net8.0 sur une machine qui n'a que .NET 10 : installe le runtime .NET 8, et ASP.NET Core 8 pour les tests d'une API), un workload, un projet Windows, un projet .NET Framework, Docker arrêté pour des tests Testcontainers, LocalDB, Artifactory.

**Une librairie** (un paquet NuGet interne) : son API publique est un contrat. Les agents ajoutent (une surcharge, un membre) et ne retirent ni ne changent jamais un membre public sans que le ticket le dise ; un nouveau membre public va dans `PublicAPI.Unshipped.txt` quand le projet suit son API (RS0016). Pour que le build lui-même vérifie la compatibilité avec la dernière version publiée, ajoute au projet (une décision d'équipe) :
```xml
<EnablePackageValidation>true</EnablePackageValidation>
<PackageValidationBaselineVersion>2.2.0</PackageValidationBaselineVersion>
```
Puis `/go` et `/fix` lancent `build-test.sh --build-only --pack` : une rupture donne des lignes `BREAKING CHANGE: CP0002 …` et `PACK: FAILED`, corrigées avant le push (ou annoncées comme version majeure dans la fiche, jamais cachées par un fichier de suppression). Le paquet est fait dans le dossier git, jamais dans le dépôt.

## Des tests qui prouvent quelque chose

La couverture n'est pas le but : un test qui exécute des lignes sans rien vérifier fait monter Sonar et ne protège de rien. Les agents écrivent des tests qui prouvent un comportement :
- la fiche donne pour chaque critère d'acceptation son test attendu, avec son niveau (unitaire, intégration avec `WebApplicationFactory`, composant front) et un scénario avec des valeurs : « 2 lignes à 10 € et 20 €, TVA 20 % → total 36 € » ; puis les cas limites et d'erreur qu'il implique ;
- le résultat attendu est écrit dans le test, jamais recalculé avec le code testé ; l'assertion porte sur ce que le comportement décide (la valeur, l'état, l'appel au port avec ses arguments), jamais seulement « pas d'exception » ;
- `test-lint.sh` relit les tests avant chaque rapport et dans l'auto-review : un test sans assertion ou focalisé est bloquant ; une horloge réelle (`DateTime.Now`, `Date.now()`), une attente (`Thread.Sleep`, `Task.Delay`, `setTimeout`), un appel HTTP réel, un `Random` sans graine ou un test ignoré est majeur. Pour le lancer toi-même sur ta branche :
```text
lance `sh ~/.config/opencode/scripts/test-lint.sh --changed origin/develop`
```

## Tests d'API (`/tests api`) et tests d'un environnement (`/tests env`)

Deux sortes de tests d'intégration, jamais mêlées (skill `api-tests`) :
- **En mémoire**, la preuve du comportement : l'API tourne dans le processus des tests (`WebApplicationFactory<Program>`), chaque endpoint est appelé en HTTP (routage, validation, autorisation, sérialisation pour de vrai), ses ports (dépôts de données, clients d'autres systèmes, horloge) remplacés par des fakes. Aucun serveur de base, aucun réseau : ils tournent à chaque build, dans la CI, comme les tests unitaires.
- **Sur un environnement**, la preuve du déploiement : les mêmes endpoints appelés sur l'URL d'une recette ou d'une préproduction, avec des contrôles vrais quelles que soient ses données (statut, type de contenu, champs promis, 401 sans jeton). Lecture seule ; jamais la production.

Sans savoir par où commencer : `/tests` seul te propose, en un QCM, les fichiers modifiés récemment qu'aucun test ne nomme, les endpoints de l'API, les tests d'un environnement et la configuration d'un environnement.
```text
/tests
```

### `/tests api` : les endpoints, en deux QCM

Avant d'écrire quoi que ce soit, il lit dans le code ce qui empêcherait l'API de démarrer dans un test (`api-preflight.sh`) : un réglage lu au démarrage (`GetConnectionString`, `?? throw`, `ValidateOnStart`), un worker (`AddHostedService`), un `DbContext` que les endpoints utilisent directement, une configuration distante appelée à chaque démarrage (Key Vault, App Configuration). Puis :
1. **La mise en place**, un QCM : le projet de tests d'intégration à créer en premier commit (`Microsoft.AspNetCore.Mvc.Testing` de ta version de .NET ; avant .NET 10, `public partial class Program { }` ajouté à ton `Program.cs`), la base que les endpoints utilisent directement (« SQLite en mémoire » : `Microsoft.EntityFrameworkCore.Sqlite` de la version d'EF Core de l'API, une base neuve par factory, son schéma créé depuis le modèle ; ou ces endpoints laissés de côté), une configuration distante appelée à chaque démarrage (l'arrêter d'abord par `/go sans ticket`, ou continuer), et les tests d'environnement quand AGENTS.md déclare un environnement.
2. **Les scénarios**, un QCM : pour chaque endpoint, ses scénarios lus dans son code (nominal avec des valeurs, 400 par règle de validation, 401, 403, 404, 409 quand le code le renvoie), que tu coches un à un.

Le test-guardian écrit d'abord la factory qui fait démarrer l'API en mémoire (les réglages par `UseSetting`, les workers retirés par leur type, le `DbContext` sur SQLite, le gestionnaire de chaque schéma d'authentification remplacé par celui des tests), fait passer un premier scénario, puis écrit les autres et les prouve verts deux fois ; un test qui révèle un bug n'est pas gardé, le bug est dans la réponse. Un commit, rien n'est poussé :
```text
/tests api
```
```text
/tests api OrdersController
```
```text
/tests api src/Api/Features/Orders seulement les erreurs
```

### `/tests env config` : déclarer un environnement, pas à pas

Une fois par environnement, dans une session du dépôt :
```text
/tests env config recette
```
Ses questions partent de ce que le code dit déjà (`env-setup.sh scan`) : les URL des jobs de déploiement de `.gitlab-ci.yml`, l'autorité et l'audience que l'API vérifie dans ses appsettings, le scope Entra ID qu'elles donnent, le proxy de ta machine. Deux QCM :
1. le nom, l'URL de base de l'API, l'accès (un client OpenID Connect, recommandé quand l'API vérifie des jetons ; un jeton fixe dans une variable ; ou aucun), le proxy (celui de ta machine, avec les identifiants que porte déjà son `HTTPS_PROXY` ; aucun ; ou un autre, et alors s'il demande des identifiants), l'usage (lecture seule, écriture permise, production : jamais testée) ;
2. avec OIDC : l'autorité (Keycloak : `https://<hôte>/realms/<realm>` ; Entra ID : `https://login.microsoftonline.com/<tenant>/v2.0`), le client id (dans une variable, ou tel quel : ce n'est pas un secret), le scope (Entra ID : `api://<application>/.default`), le fichier PEM des autorités de certification internes quand un proxy re-signe le TLS ou que le certificat est interne, et l'authentification du client en Basic quand le fournisseur l'exige ; et « Secret » : dans une variable de ta machine (recommandé quand tu n'as pas de coffre), ou dans HashiCorp Vault (son chemin et son champ, par exemple `secret/acme/recette` et `client_secret` ; de même pour les identifiants du proxy).

Il écrit le bloc de cet environnement dans la section « ## Environnements » d'AGENTS.md, jamais un secret : seulement les noms des variables de ta machine, déduits du nom de l'environnement. Pour `recette` :
```text
## Environnements
- `recette` : https://api-recette.example.com (écriture permise)
  - oidc : https://login.example.com/realms/acme
  - token-url : https://login.example.com/realms/acme/protocol/openid-connect/token
  - client : shop-tests
  - secret : `RECETTE_CLIENT_SECRET`
  - scope : api://acme-api/.default
  - proxy : http://proxy.example.com:8080
  - proxy-identifiants : `RECETTE_PROXY_CREDENTIALS`
  - certificat : certs/acme-ca.pem
  - santé : /health
- `preprod` : https://api-preprod.example.com (jeton : `API_TOKEN_PREPROD`)
- `prod` : https://api.example.com (production)
```
Avec Vault, la ligne garde la place du secret, jamais sa valeur : `` - secret : `vault:secret/acme/recette#client_secret` `` (et `` - proxy-identifiants : `vault:secret/acme/proxy#credentials` ``).

Les réglages possibles : `oidc` (l'autorité ; l'URL du jeton vient de son document de découverte, écrite à côté dans `token-url` quand le fournisseur répond) ou `token-url` seul, `client` (une valeur, ou `` `RECETTE_CLIENT_ID` ``), `secret` (une variable, ou `vault:<chemin>#<champ>`), `scope`, `audience` et `resource` (Auth0, ADFS), `auth-client : basic` ; `jeton : `<VARIABLE>`` sur la ligne pour un jeton fixe ; `proxy` (`aucun`, ou son URL sans identifiants), `proxy-identifiants`, `sans-proxy` (les hôtes joints sans lui), `certificat` (relatif au dépôt, ou `~/…`), `santé` (le chemin qui dit que l'API répond).

Les secrets, dans `~/.zshenv` de la machine d'OpenCode, jamais dans un message ni une commande (le secret du client de service de l'environnement, jamais le tien ; les identifiants du proxy : `<utilisateur>:<mot de passe>`, un mot de passe avec `@`, `:` ou `#` tel quel, le script l'encode) :
```sh
export RECETTE_CLIENT_SECRET='…'
export RECETTE_PROXY_CREDENTIALS='jdupont:…'
```
Ou dans Vault, que les scripts lisent avec le CLI `vault` de la machine, déjà connecté (le CLI installé, `VAULT_ADDR` dans `~/.zshenv`, `vault login` une fois dans ton terminal, comme ton Vault le demande) :
```sh
export VAULT_ADDR='https://vault.example.com'     # dans ~/.zshenv ; VAULT_CACERT si son autorité est interne
vault login -method=oidc
vault kv put secret/acme/recette client_secret='…'
```
Seuls `env-tests.sh` et `http-files.sh` lisent Vault, au moment où il le faut, sans jamais rien afficher ; un agent ne lance jamais `vault` (ce qu'il affiche irait au modèle). Ce que Vault refuse est dit en une ligne : pas connecté (`vault login`), un chemin que la politique de ton jeton ne donne pas ou un jeton expiré, rien à ce chemin ou pas ce champ, Vault scellé, injoignable (VPN, `VAULT_ADDR`), ou son certificat inconnu (`VAULT_CACERT`).

`~/.zshenv` est relu à chaque commande d'un agent : rien à redémarrer. Puis il vérifie l'accès, étape par étape (`env-tests.sh --check recette`) : les variables, le document de découverte, un jeton (son émetteur, son audience, son client, ses scopes et ses rôles, jamais le jeton lui-même), l'API sans le jeton, puis un GET authentifié du code avec le jeton. Relance `/tests env config recette` après avoir réglé ce qu'il dit.

### `/tests env` : lancer les tests d'un environnement

Sans environnement nommé, un QCM : lequel (son URL et son accès), tous ses tests ou une classe, avec ou sans les tests qui écrivent. Une variable qu'OpenCode n'a pas vue à son démarrage ne l'arrête pas (`~/.zshenv` est relu à chaque commande) : si l'une manque vraiment, `env-tests.sh` le dit, avec sa ligne `export` :
```text
/tests env
```
Ou tout de suite :
```text
/tests env recette
```
Il vérifie d'abord l'accès, avant tout build (un environnement hors d'atteinte s'arrête en secondes), puis demande un jeton frais à son fournisseur juste avant les tests (il vit 5 minutes sur un Keycloak par défaut), et lance les tests de la catégorie `Environment` contre l'URL d'AGENTS.md : un tableau test par test (OK, en échec, durée) ; un échec dit ce que l'environnement a répondu : c'est un fait sur ce déploiement (sa version, sa configuration, ses données), pas un correctif à faire. Les tests qui écrivent (`EnvironmentWrites` : créer, relire, supprimer ce qu'ils ont créé) ne tournent qu'avec `--écriture`, sur un environnement marqué « écriture permise » ; quelques mots après le nom en restreignent la portée :
```text
/tests env recette --écriture
```
```text
/tests env recette OrdersEnvironmentTests
```
Pour le voir sans agent, dans une session :
```text
lance `sh ~/.config/opencode/scripts/env-tests.sh --check recette`
```

**Ce qu'il peut te dire** (une ligne `ENVIRONMENT PROBLEM`, l'agent s'arrête et te le dit ; il ne réessaie jamais autrement) :

| Message | Ce qu'il faut régler |
|---|---|
| la variable `RECETTE_CLIENT_SECRET` n'est pas définie | l'`export` dans `~/.zshenv`, puis `/tests env config recette` |
| le proxy refuse la connexion (407) | `proxy-identifiants`, ou la variable qui les tient |
| le proxy interdit l'hôte (403) | le proxy ne laisse pas passer : `sans-proxy`, ou l'équipe réseau |
| le proxy ne joint pas l'hôte (502, 503, 504) | un nom que le proxy ne connaît pas, ou un environnement arrêté |
| le fournisseur refuse le client (`invalid_client`) | le client id ou le secret, ou `auth-client` |
| le client ne peut pas demander de jeton (`unauthorized_client`) | côté fournisseur : le compte de service du client (Keycloak : « Service accounts roles ») |
| le fournisseur refuse le scope (`invalid_scope`) | `scope` (Entra ID : `api://<application>/.default`) |
| l'API refuse le jeton (401, avec sa raison : l'audience, l'émetteur) | `scope` ou `audience`, ou la configuration de l'API |
| le certificat n'est pas reconnu | `certificat` : le fichier PEM des autorités internes ; jamais la vérification désactivée |
| le nom est inconnu ici | VPN, DNS, ou un proxy à donner |

Le secret, le jeton et les identifiants du proxy sont masqués (`***`) dans tout ce qu'il affiche, même encodés ; le contrôle avant push arrête tout commit qui contiendrait la valeur d'une de ces variables. La production est toujours refusée.

**Dans la CI, chaque nuit** (sans OpenCode) : la convention est le contrat, pas le script. Dans GitLab, un pipeline planifié (CI/CD > Schedules) et des variables masquées du projet, par environnement (Settings > CI/CD > Variables, « Masked ») : `API_BASE_URL`, `API_OIDC_TOKEN_URL`, `API_OIDC_CLIENT_ID`, `API_OIDC_CLIENT_SECRET`, `API_OIDC_SCOPE` (ou `API_TOKEN` pour un jeton fixe), et `HTTPS_PROXY` quand le runner en a besoin. Le client des tests (`EnvironmentClient` du skill) demande lui-même son jeton :
```yaml
env-tests:
  image: mcr.microsoft.com/dotnet/sdk:10.0
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
  script:
    - dotnet test tests/Api.IntegrationTests --filter "Category=Environment"
```
Un projet xUnit v3 sur Microsoft.Testing.Platform filtre par `--filter-trait "Category=Environment"` ; MSTest, par `--filter "TestCategory=Environment"`. Une autorité de certification interne : `SSL_CERT_FILE` vers un fichier qui contient celles du système et la tienne (image Linux).

## Requêtes `.http` pour Rider et Visual Studio (`/outil http`)

Pour appeler toi-même chaque endpoint dans Rider (ou Visual Studio), sans Postman :
```text
/outil http
```
Il te montre d'abord ce qu'il écrirait (rien n'est encore écrit), puis UN QCM : les contrôleurs (tous, ou ceux que tu coches), le client (Rider, ou Visual Studio), quand des fichiers existent déjà, les garder (tes requêtes modifiées restent telles quelles) ou les remplacer, et quand AGENTS.md dit où sont les secrets, « Secrets » : les remplir depuis `~/.zshenv` et Vault (recommandé), ou les coller toi-même. Il écrit, depuis le code, un fichier `.http` par contrôleur dans `<projet de l'API>/http/`, chaque requête avec sa route, son jeton quand l'endpoint l'exige, un corps rempli depuis son DTO et un contrôle de son statut ; `http-client.env.json` avec `local` (l'URL de `launchSettings.json`) et tes environnements d'AGENTS.md (jamais la production) ; le fichier privé de tes secrets (`http-client.private.env.json` pour Rider, `http-client.env.json.user` pour Visual Studio, qui ne lit pas celui de Rider), ajouté au `.gitignore`, jamais réécrit. Avec « Les remplir », `http-files.sh --private` y met chaque secret qu'AGENTS.md nomme, lu dans la variable ou dans Vault : il te dit lesquels (FILLED) et ce qui reste à coller (EMPTY), jamais une valeur ; une valeur déjà là n'est jamais remplacée (un secret changé : vide sa valeur, puis `/outil http`). Aucun agent ne lit ni n'écrit un fichier privé, et le contrôle avant push le refuse s'il était ajouté de force.

Dans Rider : ouvre un `.http`, choisis l'environnement en haut de l'éditeur, puis ▶ sur une requête ou « Run All Requests in File ». Pour un environnement OIDC, Rider demande le jeton lui-même (OAuth 2.0 client credentials de son client HTTP, renouvelé tout seul), avec ce qu'`http-client.env.json` dit :
```json
"recette": {
  "baseUrl": "https://api-recette.example.com",
  "id": "1",
  "Security": {
    "Auth": {
      "api": {
        "Type": "OAuth2",
        "Grant Type": "Client Credentials",
        "Token URL": "https://login.example.com/realms/acme/protocol/openid-connect/token",
        "Client ID": "shop-tests",
        "Client Secret": "{{clientSecret}}",
        "Client Credentials": "in body",
        "Scope": "api://acme-api/.default"
      }
    }
  }
}
```
Chaque requête dit `Authorization: Bearer {{$auth.token("api")}}`. Le secret, une fois, dans `http-client.private.env.json` (jamais commité) ; un environnement à jeton fixe ou `local` y attend son jeton :
```json
{ "recette": { "clientSecret": "…" }, "local": { "token": "…" } }
```
Rider passe par le proxy de ses réglages (Settings > Appearance & Behavior > System Settings > HTTP Proxy). Visual Studio ne lit pas la configuration OAuth de Rider : avec le client « Visual Studio », chaque requête dit `Bearer {{token}}`, un jeton à coller par environnement dans `http-client.env.json.user` (sans gestionnaire de réponse `> {% %}`, propre à Rider).

## Planifier une commande (`/outil planifier`)

OpenCode v2 n'a pas de planificateur : le plugin du pack en fait un (fonction 26). À l'heure dite, il ouvre une nouvelle session dans le dépôt et y lance la commande ; la session est sur l'accueil, avec son issue dans le titre. Seulement ce qui n'écrit rien, ni dans git ni dans Jira : `/daily`, `/outil audit`, `/outil licences`, `/tests env <environnement>` (lecture seule) ; `/go`, `/fix`, `/push`, un assistant (`/tests env config`) et les autres sont refusés, même écrits à la main dans le fichier. Sans argument, un QCM : quoi (le point du matin, les tests d'un environnement, l'audit, les licences, ou retirer une planification), l'heure, les jours. Depuis le dossier principal du dépôt :
```text
/outil planifier 8h45 lun-ven /daily
```
```text
/outil planifier 7h30 tous les jours /tests env recette
```
```text
/outil planifier
```
```text
/outil planifier suppr 2
```
Les planifications sont dans `~/.config/opencode/schedules.md` (modifiable à la main), à l'heure de la machine d'OpenCode. OpenCode doit tourner à cette heure (son service, COMMANDES.md « Redémarrer OpenCode ») : ce qu'il a manqué n'est pas rattrapé. Chaque lancement, ou la raison pour laquelle il n'est pas parti, est dans le journal du plugin (« Logs d'OpenCode » : `grep scheduled ~/.local/share/opencode/log/openrd-pack.log`). Pour tout arrêter, vide le fichier.

## La carte des flux du pack (`/outil carte`)

Pour voir d'un coup d'œil ce que fait le pack, ou le présenter à quelqu'un qui ne code pas :
```text
/outil carte
```
`pack-map.sh` lit le pack tel qu'il est installé (ses commandes, leurs étapes, les agents qui y travaillent, leurs questions, les outils de `/outil`, les skills, les fonctions du plugin, les scripts) et écrit une page HTML en français : « En une minute » (le pack expliqué sans jargon), la carte d'ensemble, puis une section par commande (à quoi elle sert, comment la lancer, ses étapes en schéma et en liste avec qui travaille et ce qu'il te demande, comment elle peut finir), les agents et ce qu'ils ont le droit d'écrire, les skills et les garde-fous. Rien n'est lu dans ton dépôt. L'agent te dit où est la page (par défaut dans le dossier de configuration d'OpenCode : `~/oc2/config/opencode/carte-des-flux.html` pendant l'essai à côté de la 1.19, `~/.config/opencode/carte-des-flux.html` sinon) et la résume en un tableau. Ouvre-la dans un navigateur ; quand OpenCode tourne sur une autre machine que la tienne, copie-la chez toi (`scp <machine>:<fichier> .`) ou écris-la dans le dépôt (ci-dessous). Les schémas de cette page générée viennent de Mermaid, chargé depuis `cdn.jsdelivr.net` : sans Internet, ou quand le proxy de l'entreprise bloque ce site, la liste des étapes reste. La carte tenue à la main, elle, a ses schémas dessinés dans la page : `docs/carte-des-flux.html` du dépôt du pack (`opencode-v2/docs/`), à ouvrir dans n'importe quel navigateur, hors ligne aussi. Pour une réunion, les flux principaux en diapositives : `docs/presentation-flux.pptx` (PowerPoint ; le détail de chaque schéma dans les notes de l'orateur).

Pour la mettre dans un dépôt (la partager, la pousser) :
```text
/outil carte docs
```
```text
/outil carte docs/pack/carte.html
```
Un chemin du dépôt seulement (relatif à sa racine, jamais `..` ni `/…`). Elle se régénère en une seconde : relance-la après chaque mise à jour du pack, elle est toujours exacte. Sans agent, dans un terminal de la machine d'OpenCode (pendant l'essai à côté de la 1.19, ajoute `--pack ~/oc2/config/opencode`, sinon c'est le pack 1.19 qui est lu) :
```sh
sh ~/.config/opencode/scripts/pack-map.sh --out /tmp/carte.html
```

## Bonnes pratiques et patterns du pack

Appliqués automatiquement, sans question ni réglage :
- **Une seule porte pour builder et tester** (`build-test.sh`, .NET et front-end) : une exécution, des lignes `BUILD:`/`TESTS:` explicites, jamais un mode watch, un problème de la machine dit en une ligne.
- **Échouer tôt, sur la machine et pas sur le code** : `dotnet-problem.sh` et les lignes de `detect-project-type.sh` (SDK, runtimes, node, Chrome) arrêtent un run avant qu'un agent « corrige » le dépôt pour une machine incomplète.
- **Le lockfile fait foi** : `npm ci` et ses équivalents, jamais un paquet ajouté ou monté par un agent (le plugin refuse `npm install`, `yarn add`, `dotnet package add` en disant quoi faire) ; un lockfile désynchronisé arrête.
- **Un savoir chargé seulement quand il sert** : les skills (CQRS, intégrations, Blazorise, AutoMapper, EF Core, Fortify) ne coûtent rien tant que le code n'en a pas besoin ; `detect-project-type.sh` nomme celui d'une bibliothèque qu'il trouve (« Blazorise 2.2.2: the skill blazorise », « EF Core 8.0.11 (SqlServer): the skill efcore »).
- **Des outils seulement quand ils servent** : le pilote ne reçoit que les outils MCP des serveurs de sa commande (`/go` : Jira et GitLab), ses sous-agents ceux de leurs règles (le coder et le test-guardian aucun) ; et ce qu'un script vérifie, le modèle ne le refait pas (`test-guardian.sh verify` : le contrôle après un correctif, le test-guardian rappelé seulement quand ce n'est pas vert).
- **La version du projet fait foi** : C# et API du framework cible ; une migration de framework est un ticket à part.
- **Contrats d'abord** : `api-surface.sh` (API publique, routes, champs des DTO), la validation de paquet d'une librairie, la section « Contrat » des fiches entre dépôts liés.
- **Des tests qui prouvent** : scénarios avec valeurs dans la fiche, `test-lint.sh`, le filet de non-régression avant un correctif, la preuve rouge puis verte deux fois d'un bug ou d'une faille.
- **Le temps injectable** : un test ne lit jamais l'horloge réelle ; `FakeTimeProvider` quand le code prend un `TimeProvider` (.NET 8 et plus).
- **Rien d'inutile dans un push** : `node_modules`, `obj`, `bin/Debug`, `TestResults` jamais commités par les scripts du pack (`ship.sh` les laisse hors du commit et le dit), arrêtés par le contrôle avant push s'ils sont commités à la main, une installation refusée quand git n'ignore pas `node_modules`.
- **Les commandes bornées** : ce qui ne finit jamais est refusé aux agents ; le reste a 20 minutes (45 pour un script du pack, qui se borne lui-même et dit `TESTS: TIMEOUT`), un test bloqué est arrêté et nommé.

Proposés par `/outil audit` (skill `best-practices`), chacun avec sa preuve dans le dépôt et le plus petit changement qui l'apporte, jamais imposés : validation de paquet et `PublicApiAnalyzers` pour une librairie, Source Link, `TimeProvider` au lieu de `DateTime.Now`, un client front généré depuis l'OpenAPI de l'API, tests d'intégration avec `WebApplicationFactory`, health checks, ProblemDetails, options validées au démarrage, `IHttpClientFactory` et résilience, et les autres pratiques par type de projet du skill.

## Le filet de non-régression

Avant chaque correctif de code existant (une faille de `/fortify` ou de `/fix`, un bug de `/go` ou de `/fix`, un refactoring demandé à `/fix`, une étape de `/go` marquée « (filet d'abord) » par l'analyste), le test-guardian mesure le **filet** : la part des lignes des méthodes que le correctif va toucher, et des méthodes publiques qui y mènent, que des tests exécutent (le code d'une méthode asynchrone, d'un itérateur, d'une lambda ou d'une fonction locale compte dans sa méthode). Il le mesure par script, `test-guardian.sh coverage` puis `test-guardian.sh net`, jamais en lisant le code :
```text
NET: src/App/PathService.cs:Preview lines 0/4 (0%) branches 0/2 uncovered 10-13
SAFETY NET: THIN (1/5 lines of these 2 methods run by the tests, 20% < 80%): …
```
Sous le minimum (80 % de leurs lignes), il écrit d'abord les tests du comportement **actuel** qui manquent (jamais celui de la faille ou du bug : leurs propres tests le font), les prouve verts deux fois, et les scelle avec la preuve : le coder ne peut pas les modifier, et son correctif est fini quand eux aussi passent. Après le correctif, la même vérification (le filet passe toujours, deux fois, et n'est pas descendu sous le minimum ; aucun fichier ne perd de couverture ; chaque ligne de la méthode d'une faille ou d'un bug est exécutée) est d'abord faite par un script que lance le pilote, `test-guardian.sh verify` : tout vert, l'étape est commitée sans un tour du modèle ; sinon, le test-guardian reprend dans sa session, lui seul remettant un test scellé ou mettant à jour un test du filet que le correctif change exprès. Un test du filet qui échoue alors est une régression (le coder reprend), sauf si l'étape change ce comportement exprès : le test-guardian le met à jour et la MR le liste.

Une page `.razor` : coverlet mesure le C# de la page (son `@code`, et dans son balisage les `@if`, `@foreach` et gestionnaires d'événements), jamais ses balises et leurs attributs. `test-guardian.sh net` le dit (`NET: … BuildRenderTree not measured`) sans s'arrêter : le filet d'une page, ce sont les tests bUnit de ce que voient ses utilisateurs, qui doivent exister et passer avant qu'on la touche, quel que soit le chiffre.
```text
NET: src/Web/Components/Pages/Orders.razor:OnInitialized lines 1/1 (100%)
NET: src/Web/Components/Pages/Orders.razor:BuildRenderTree not measured: coverlet counts the C# statements of a component …
```

Ce qu'aucun test ne peut exécuter sans changer le code de production (l'horloge réelle, une dépendance que le code crée lui-même, le réseau) est nommé : « Filet : INSUFFISANT (lignes … : raison) ». Le run continue, et la MR le montre pour que la review le regarde de près. Le filet ne pose aucune question.

Sans projet de tests unitaires (ou sans collecteur de couverture), aucun filet ne peut se mesurer. La question de le créer est posée au début, jamais en cours de route : `/fortify` et `/tests` d'abord, `/go` avec les questions de son analyse quand le plan corrige un bug ou modifie du code existant, `/fix` avant son premier correctif. « Oui » : `test-guardian.sh setup` crée le projet (ou ajoute le collecteur) en premier commit, puis le filet est mesuré sur ce projet encore vide (« no test in <projet> yet », 0 %) et ses tests sont écrits avant le correctif. « Non » : la décision est notée dans la fiche (plus redemandée pour ce ticket), les correctifs se font sans filet ni preuve, et la MR le dit dans « Points d'attention ».

Le minimum se change par dépôt, dans la section « Build & test » de son `AGENTS.md` :
```text
- Filet de non-régression : 70 %
```
Dans la MR : la colonne « Filet » du tableau de `/fortify` (avant → avec ses tests → après le correctif), et les filets de `/go` et `/fix` dans « Vérifications » ; dans le commit, une ligne « - safety net: 20% -> 100% of the lines of 2 methods ».

## Fortify (`/fortify`)

Prérequis, vérifiés au début de chaque `/fortify`. S'il manque `dotnet` ou l'application Fortify SSC, le run s'arrête avec une ligne `STOP:` disant ce qui manque. S'il manque **le projet de tests** (le dépôt n'en a aucun) ou **coverlet** dans un projet de tests, le run ne s'arrête plus : sa première action est une question (la seule du run avant son QCM « Suite ») qui te propose de le mettre en place en premier commit du lot — xUnit, MSTest ou NUnit s'il n'y a pas de projet, l'ajout de coverlet sinon — ou d'arrêter. « Oui » : le pilote lance `test-guardian.sh setup`, qui crée le projet (modèle `dotnet new`, `coverlet.collector`, référence au projet testé, ajout à la solution) ou ajoute coverlet, le compile, et le commite (« test: add the unit test project (CLÉ) ») ; puis le lot continue. « Non » : le run s'arrête et renvoie à la mise en place manuelle ci-dessous. Pour voir les prérequis avant, dans le dossier du dépôt, sans script :

`dotnet` (une version s'affiche) :
```sh
dotnet --version
```
Les projets de tests unitaires (au moins un doit s'afficher ; un projet nommé `….Tests.csproj` ou `….UnitTests.csproj` compte aussi) :
```sh
git grep -il -e 'Microsoft.NET.Test.Sdk' -e 'MSTest.Sdk' -e 'xunit.v3' -e '<IsTestProject>' -- '*.csproj'
```
Où coverlet est déclaré : dans chacun de ces projets, ou dans un `Directory.Build.props` (ou `.targets`, ou `Directory.Packages.props`) d'un dossier au-dessus d'eux :
```sh
git grep -il 'coverlet.collector' -- '*.csproj' '*Directory.Build.props' '*Directory.Build.targets' '*Directory.Packages.props'
```
L'application Fortify SSC du dépôt (une ligne doit s'afficher) :
```sh
git grep -h '^APPSEC_PROJECT_NAME=' -- '*appsec-ci.env'
```
Le cas le plus courant est coverlet manquant : `/fortify` te propose de l'ajouter lui-même (voir ci-dessus). Pour le faire à la main, dans sa propre MR, à chaque projet de tests nommé :
```sh
dotnet add <chemin du projet de tests>.csproj package coverlet.collector
```

### Mettre en place les tests unitaires (un dépôt qui n'en a pas)

Depuis la v2.1.3, `/fortify` te propose de le faire lui-même en premier commit du lot (la question du début), avec ton accord et le framework que tu choisis : tu n'as plus rien à taper. Ce qui suit est la méthode **manuelle**, si tu préfères la faire toi-même dans sa propre MR, ou pour comprendre ce que fait `test-guardian.sh setup`. Depuis la racine du dépôt, sur une branche à toi (remplace `MonApi` par le nom du projet testé, `MonApi.sln` par la solution, et `xunit` par le framework de tes autres dépôts : `mstest` ou `nunit`) :
```sh
dotnet new xunit -o tests/MonApi.Tests
```
```sh
dotnet sln MonApi.sln add tests/MonApi.Tests/MonApi.Tests.csproj
```
```sh
dotnet add tests/MonApi.Tests/MonApi.Tests.csproj reference src/MonApi/MonApi.csproj
```
Le modèle de projet ajoute déjà `coverlet.collector` ; vérifie-le (une ligne doit s'afficher), et sinon ajoute-le :
```sh
grep -i coverlet.collector tests/MonApi.Tests/MonApi.Tests.csproj
```
```sh
dotnet add tests/MonApi.Tests/MonApi.Tests.csproj package coverlet.collector
```
Puis, pour vérifier : `dotnet test tests/MonApi.Tests/MonApi.Tests.csproj` (le test d'exemple de `dotnet new xunit` passe), et `dotnet test tests/MonApi.Tests/MonApi.Tests.csproj --collect:"XPlat Code Coverage"` (une ligne `coverage.cobertura.xml` s'affiche à la fin). Avec la gestion centralisée des versions (`Directory.Packages.props`), `dotnet add package` y ajoute la version : garde ce fichier dans la même MR. Les packages viennent d'Artifactory : une erreur `NU1301` est un problème d'accès, pas du projet.

Une méthode `internal` à tester sans passer par une méthode publique : le test-guardian n'ajoute jamais `InternalsVisibleTo` (c'est du code de production) ; s'il en a besoin, son rapport le dit, et c'est à toi de l'ajouter dans le projet testé, dans cette même MR.

### Lancer, reprendre, suivre

Lancer un lot depuis develop, dans une session du dépôt : `/fortify` (5 vulnérabilités au plus), `/fortify 3`, `/fortify 5 Path Manipulation`, `/fortify ABC-123` (avec un ticket Jira). Les analyses tournent trois à la fois, avec le build et les tests de develop (les tests déjà en échec sur develop ne sont jamais ceux du lot) ; le titre les montre ensemble : « ⏳ 3:10 outils (4) · Analyse V1, Analyse V2, Analyse V3… ». Puis le lot avance par **vagues** : jusqu'à trois preuves (fichiers disjoints) écrites **en parallèle** par autant de test-guardians, puis les correctifs appliqués et commités un par un. Chaque test-guardian écrit ses tests et les lance par `test-guardian.sh` ; aucun ne lance `dotnet` lui-même, et les builds d'une même vague sont sérialisés par un verrou du dossier (un test-guardian qui attend affiche « WAIT: another build or test run of this folder is in progress »), pour qu'un build n'en casse pas un autre. Reprendre après une coupure : `/fortify` dans une session sur la branche du lot ; il repart de la vulnérabilité en cours — une preuve déjà rangée est reprise au correctif, une preuve en cours sans correctif est refaite (une panne du serveur du modèle ou une réponse coupée : le plugin le reprend tout seul, section « Un run qui reprend tout seul »). Deux lots en même temps : dans deux espaces de travail, avec chacun une catégorie ou un fichier (`/fortify 3 Log Forging`), pour qu'ils ne prennent pas les mêmes vulnérabilités.

Avant la preuve, le filet de non-régression des méthodes que le correctif va toucher (la carte de la faille les nomme dans sa ligne « Filet : ») : sous le minimum, le test-guardian écrit d'abord les tests de leur comportement actuel, verts deux fois, scellés avec la preuve (section « Le filet de non-régression »). Chaque preuve est faite par `test-guardian.sh`, jamais à l'œil : les tests de la faille rouges sur le code actuel puis verts après le correctif, **chacun exécuté deux fois** (un test qui change de résultat est instable, `FLAKY`, et n'est jamais gardé), un test qui ne s'arrête pas stoppé au bout de 5 minutes et nommé, et aucune perte de couverture du module et de ses dépendances. Une faille dont les tests passent **déjà** sur le code actuel (le code résiste : un correctif précédent du lot l'a close, ou c'est un faux positif) garde ses tests et part en un commit « test(security): show that … is not exploitable », sans correctif. Les tests de la preuve sont scellés avant le correctif (`test-guardian.sh seal`) : si le coder les modifie ou les supprime, le test-guardian le voit avant sa vérification, les remet tels quels et fait la preuve sur eux (si elle échoue, le coder reprend son correctif). Et le pilote vérifie le sceau dans le même appel que le commit (`test-guardian.sh sealed V<n> && ship.sh …`) : aucun commit ne part avec des tests de preuve modifiés. À la fin, le build et les tests complets, la couverture des lignes modifiées et l'auto-review (le `checker`) tournent **dans le même tour** : la suite complète tourne en parallèle du checker, qui ne relance jamais ni build ni tests et revoit en lisant le diff. La couverture des lignes modifiées par le lot va dans la MR.

Un repère technique : les mesures lisent les exécutions **VSTest** (`dotnet test`) et **Microsoft.Testing.Platform** (MSTest.Sdk, xUnit v3, les lanceurs MSTest et NUnit, TUnit, ou `global.json` en mode MTP) : chaque projet de tests tourne avec son lanceur, un projet MTP comme l'application qu'il est (`dotnet exec` de sa sortie, par `test-platform.sh`), avec la couverture de son extension (Microsoft.Testing.Extensions.CodeCoverage, ou coverlet.MTP). Un projet MTP sans extension de couverture : `fortify.sh prereq` le signale, et `test-guardian.sh setup` ajoute Microsoft.Testing.Extensions.CodeCoverage. Pour lancer ces tests toi-même dans un terminal avec le SDK .NET 10, `dotnet test` demande `"test": { "runner": "Microsoft.Testing.Platform" }` dans `global.json` ; sinon, dans une session : « lance `sh ~/.config/opencode/scripts/build-test.sh` ».

Le travail d'une vulnérabilité abandonnée est mis de côté, jamais effacé. La liste est commune à tous les espaces de travail du dépôt : chaque mise de côté porte la clé du lot, la vulnérabilité et le dossier, et sa carte (et la réponse du pilote) donne son commit, qui la désigne quoi qu'il arrive ensuite dans la liste. Utilise le **hash complet** (40 caractères) de la carte, pas une version raccourcie : un hash court tout en chiffres est lu par git comme `stash@{n}`. Pour la voir puis la ramener (sur la branche du lot, sans fichier non commité) :
```sh
git stash list | grep fortify
```
```sh
git stash show -p <hash complet>
```
```sh
git stash apply <hash complet>
```
Les cartes des vulnérabilités sont dans le dossier du lot, et les mesures des tests (couvertures, sorties des tests rouges et verts, deux par preuve) dans celui des tests, jamais commités :
```sh
ls "$(git rev-parse --git-common-dir)"/opencode-tickets/*.fortify/ "$(git rev-parse --git-common-dir)"/opencode-tickets/*.tests/
```
