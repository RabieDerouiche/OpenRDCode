# Commandes à taper à la main

Toutes les commandes que le pack te demande de lancer toi-même, à copier-coller. Sauf mention « dans OpenCode », elles se tapent dans un terminal de la machine qui héberge OpenCode. Aucune n'affiche de mot de passe ni de token. Ce fichier est complété à chaque évolution du pack.

## Redémarrer OpenCode

Après une modification d'`opencode.json`, du plugin, d'un agent, d'une commande ou d'un skill. Inutile après une modification de `~/.zshenv` : il est relu à chaque commande d'un agent.
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

Ce que le shell d'un agent obtient de `~/.zshenv` seul : chemin de `dotnet`, `DOTNET_ROOT`, et la présence (pas la valeur) des variables Artifactory :
```sh
env -i HOME="$HOME" PATH=/usr/bin:/bin "$(command -v zsh)" -c 'command -v dotnet; echo "DOTNET_ROOT=$DOTNET_ROOT"; [ -n "$artifactory_user" ] && [ -n "$artifactory_password" ] && echo "artifactory: OK" || echo "artifactory: MANQUANT"'
```

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
for a in analyst architect debugger dev git release-writer reviewer test-writer; do opencode debug agent "$a" > /dev/null && echo "$a OK"; done
```

Le shell que les agents utilisent vraiment (après le redémarrage et une première commande d'agent) :
```sh
grep 'shell tool using shell' ~/.local/share/opencode/log/opencode.log | tail -1
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

Le chargement du plugin (rien = pas d'erreur) :
```sh
grep -i plugin ~/.local/share/opencode/log/opencode.log | grep -iE 'error|fail' | tail -10
```

## Dans OpenCode (à taper dans une nouvelle session)

L'environnement de build des agents :
```text
lance `sh ~/.config/opencode/scripts/build-test.sh --build-only`
```
`BUILD: OK` ou une erreur de compilation : l'environnement est bon. Une ligne `ENVIRONMENT PROBLEM` dit quoi corriger.
