# Les fichiers du pack, un par un

Chaque fichier de `opencode-v2/` : ce qu'il fait exactement, qui le lance et quand, ce qu'il a le droit de modifier, et à quoi il sert. Tout est tiré du fichier lui-même (son en-tête, ses règles, son code) : en cas de doute, c'est le fichier qui fait foi. `node tools/validate.js` échoue si un fichier du pack manque ici.

| Dossier | Où il va sur ta machine | Qui le lit |
|---|---|---|
| `plugins/` | `~/oc2/config/opencode/plugins/` (ou `~/.config/opencode/plugins/`, annexe A de `MIGRATION.md`) | OpenCode v2, à son démarrage |
| `commands/` | `…/opencode/commands/` | OpenCode : chaque fichier est une commande `/<nom>` |
| `agents/` | `…/opencode/agents/` | OpenCode : chaque fichier est un agent, avec ses règles (`permission:`) |
| `skills/` | `…/opencode/skills/<nom>/SKILL.md` | les agents, qui les chargent quand leur description le dit |
| `scripts/` | `~/.config/opencode/scripts/`, commun à la 1.19 et à la v2 | les commandes (lignes `[[run …]]`), les agents, les autres scripts |
| `AGENTS.global.md`, `opencode.snippet.json` | fusionnés dans `…/opencode/AGENTS.md` et `…/opencode/opencode.json` | OpenCode, à chaque requête |
| `tools/` | **nulle part** : jamais copié | moi, pour vérifier le pack avant de le pousser |

Les mots utilisés : le **pilote** est l'agent qui mène `/go`, `/fix`, `/fortify`, `/tests`, `/push`, `/sync` et `/daily` ; un **sous-agent** travaille pour lui avec un contexte neuf, sans jamais poser de question ; la **conversation** est l'agent `build` d'OpenCode, celui à qui tu écris sans commande ; la **fiche** d'un ticket est `.git/opencode-tickets/<CLÉ>.md`, commune à tous les espaces de travail du dépôt, jamais commitée ; la **base** d'une branche est la branche d'où elle part (develop, ou celle de `/go … depuis <branche>`).

## Sommaire
- [Le plugin](#le-plugin)
- [Les commandes](#les-commandes) (10)
- [Les agents](#les-agents) (7)
- [Les skills](#les-skills) (16)
- [Les scripts](#les-scripts) (28)
- [Configuration et documentation](#configuration-et-documentation)
- [Les outils de vérification](#les-outils-de-vérification-tools) (`tools/`)

## Le plugin

### `plugins/openrd-pack.js`
- **Ce qu'il fait** : le code du pack dans OpenCode v2 (écrit pour la v2.1.3). Il voit chaque prompt, chaque appel d'outil et chaque requête au modèle, et ajoute ce que les règles d'OpenCode ne savent pas faire. Ses 23 fonctions, numérotées comme dans son en-tête :

| N° | Ce qu'il fait | Pourquoi |
|---|---|---|
| 1 | exécute les lignes `[[run <script> …]]` des commandes, dans le dépôt de la session, avant que le modèle ne lise le prompt ; sans terminal, arrêtées au bout de 3 minutes | l'état git, la fiche, la détection du projet arrivent tout calculés : le modèle ne les cherche pas |
| 2 | donne aux commandes des agents un environnement stable (messages .NET en anglais, sans bannière ni télémétrie, git qui n'attend jamais un mot de passe) et en retire le mot de passe du serveur OpenCode, les tokens MCP et les dossiers `~/oc2` | une commande ne bloque jamais sur une invite ; aucun secret dans ce que lance un agent |
| 3 | affiche `/<commande> <arguments> — <dossier> · branche <branche>` au lieu du prompt déroulé (plus « ⏰ n rappel(s) » de ta todo) ; nomme la session sans requête au modèle | la conversation reste lisible, le modèle reçoit tout |
| 4 | lance tout seul la commande choisie dans un QCM (« /go ABC-123 », « /push »…) à la fin du tour | un clic suffit pour enchaîner |
| 5 | montre l'avancement dans le titre de la session : « ⏳ 1:42 réflexion 2,3k tokens », l'outil ou les sous-agents en cours, « nouvel essai », « rien reçu depuis 4 min » | tu vois où en est un long run sans ouvrir la session |
| 6 | refuse une commande qui change `PATH` ou `DOTNET_ROOT`, ou qui écrit un identifiant (mot de passe, token, variable Artifactory) | un secret tapé dans une commande resterait dans l'historique |
| 7 | garde les agents du pack dans le dépôt : un chemin hors du dépôt est refusé, même entre guillemets, dans `sh -c` ou après une redirection ; sont permis en lecture seule les scripts et skills du pack, la fiche, le cache NuGet (outils de fichiers), les `references` d'`opencode.json` et les dossiers que tu nommes toi-même ; refuse aussi les dumps d'environnement et les `rm` récursifs | aucun agent ne lit `~/.zshenv` ni ne touche un autre dépôt ; les règles d'OpenCode ne voient pas dans les guillemets |
| 8 | donne 20 minutes à un build ou des tests, 5 à `ship.sh` et `branch.sh` ; jamais rien en arrière-plan | OpenCode coupe une commande au bout de 2 minutes |
| 9 | un seul `/go`, `/fix`, `/fortify`, `/tests`, `/push` ou `/sync` à la fois par dossier (verrou dans le dossier git de l'espace de travail, vu aussi par un second OpenCode) ; le second reçoit une ligne « ⛔ … refusé » | deux pilotes dans un même dossier commiteraient le travail l'un de l'autre ; deux espaces de travail, eux, travaillent en parallèle |
| 10 | laisse l'issue d'un `/go`, `/fix`, `/fortify` ou `/tests` dans le titre : ✅, ⏸ (attend le PO), ↻ (reprend tout seul), ⛔ | l'accueil d'OpenCode montre l'état de chaque run |
| 11 | lance un outil appelé par son chemin complet (`/usr/bin/git log`) par son nom | les règles nomment les outils, pas leurs dossiers |
| 12 | ferme ce que la v2 ouvre : le « code mode » (`execute`, qui appelle n'importe quelle adresse), la recherche web, les outils qui déplacent une session ou créent un espace de travail, la question d'un sous-agent | rien ne part vers l'extérieur sans toi ; personne ne répond pendant un run |
| 13 | efface des requêtes les sorties des anciens outils (`compaction.prune`, que la v2 ignore) ; l'historique garde tout | des requêtes plus courtes sur les longues sessions |
| 14 | attend jusqu'à 30 s les serveurs MCP encore en connexion, pendant les 5 premières minutes d'OpenCode | un `/go` lancé juste après le démarrage a bien Jira et GitLab |
| 15 | met le nom du dossier d'un espace de travail en tête de ses titres : « [crisp-river] … » | l'accueil mélange les sessions de tous les dossiers d'un dépôt |
| 16 | refuse le troisième appel identique d'outil dans une même réponse (l'ancienne règle `doom_loop`) | un modèle qui tourne en rond change d'approche |
| 17 | quand le contexte est plein et résumé : le résumé garde l'état du run, puis chaque requête reçoit de nouveau la procédure de la commande (pilote) ou la tâche (sous-agent) | un run long ne perd pas ses consignes |
| 18 | étale les 10 nouveaux essais d'OpenCode sur environ 8 minutes au lieu d'une et demie, pour un run | une passerelle du modèle qui redémarre n'arrête pas le run |
| 19 | reprend tout seul un run arrêté avant sa réponse finale (panne du serveur du modèle : 2 puis 5 minutes plus tard ; pilote arrêté à mi-chemin), deux fois au plus d'affilée, depuis la fiche | un run va au bout sans toi |
| 20 | remplace le contenu `null` des messages d'appels d'outils par `""` | la passerelle refusait toute la requête (HTTP 400) |
| 21 | coupe une réponse du modèle qui se répète (même phrase en boucle), annule la requête, puis renvoie la demande avec une pénalité de présence de 1.0 puis 1.5 jusqu'à une réponse normale (cette session seulement) | la réflexion qui tournait une heure sans résultat |
| 22 | « continue » (« reprends », « vas-y »…) dans la session d'un run arrêté le reprend avec le pilote | l'interface envoyait ce message à `build`, sans les règles du pilote |
| 23 | permet `dotnet run` à la conversation seulement sur un projet que le dernier commit contient | jamais un programme de sonde ou de réflexion fait pour l'occasion |

- **Journal** : chaque refus (6, 7, 9, 12, 16, 23), résumé, reprise et boucle coupée est écrit dans `~/.local/share/opencode/log/openrd-pack.log` (dossier de données XDG de l'OpenCode qui tourne : COMMANDES.md, « Logs d'OpenCode »). Une erreur du plugin laisse toujours passer le prompt ou l'appel tel quel.
- **Utilité** : sans lui, les commandes n'ont pas leurs faits calculés, les agents peuvent sortir du dépôt, un run s'arrête à la première panne du modèle, et une boucle de réflexion bloque le serveur.

## Les commandes

Chaque fichier commence par `[[command <nom> $ARGUMENTS]]` (lu par le plugin), puis les lignes `[[run …]]` qui calculent les faits, puis la procédure que suit l'agent. Le pilote répond toujours en français, avec une première ligne d'issue : 🚀, 🔁, ✅, ⏸ ou ⛔.

### `commands/go.md` — `/go`
- **Ce qu'il fait** : d'un ticket Jira à une MR en Draft, en un seul run : l'analyste écrit la fiche (critères, plan, tests attendus, décisions) pendant que la base est buildée et testée ; puis chaque étape du plan par un coder (un bug : son test écrit d'abord par le test-guardian, rouge puis vert) ; build et tests complets avec la couverture des lignes modifiées, tests des lignes qu'aucun test n'exécute, auto-review par le checker et ses corrections, contrôle avant push, commit, push, MR avec son rapport. Sans ticket : `/go sans ticket : <ce qu'il faut faire>` (clé `LOCAL-<n>`).
- **Agent** : pilot. **Faits calculés** : `detect-project-type.sh`, `workflow-state.sh --fetch-all --sheet`.
- **Quand** : pour un ticket. Consignes : « depuis <branche> », « analyse seule », « pas à pas », « comme le pattern <nom> », « comme dans <dépôt> ». Relancé, il reprend à sa dernière étape faite.
- **Utilité** : le travail d'un ticket sans toi ; il ne pose de questions que si le ticket est ambigu, toutes à la fois.

### `commands/fix.md` — `/fix`
- **Ce qu'il fait** : après la CI ou la review, rassemble en une passe les jobs en échec du pipeline, les failles Sonar et Fortify des fichiers de la branche et les discussions ouvertes de la MR ; trie (à corriger, à répondre, hors périmètre) ; corrige (une faille avec ses tests écrits d'abord par le test-guardian) ; teste avec la couverture des lignes modifiées ; commit, push avec le contrôle avant push ; écrit les réponses à coller. Ramène aussi les commits poussés d'un autre poste et ceux de develop.
- **Agent** : pilot. **Faits calculés** : `detect-project-type.sh`, `workflow-state.sh --sheet --appsec`.
- **Quand** : après chaque pipeline ou review, avec ou sans ticket (pas de MR créée sur une branche `poc/` ou `wip/`).
- **Utilité** : les retours de la CI et de la review traités sans aller-retour.

### `commands/fortify.md` — `/fortify`
- **Ce qu'il fait** : les 4 ou 5 vulnérabilités Fortify les plus graves de l'application SSC du dépôt : analysées en parallèle (3 à la fois), prouvées par vagues par le test-guardian (tests du module rouges, deux fois, scellés), corrigées une à une par le coder (verts deux fois, sans perte de couverture), un commit par vulnérabilité, puis une MR Draft. Sans projet de tests, propose d'abord de le créer.
- **Agent** : pilot. **Faits calculés** : `fortify.sh prereq`, `workflow-state.sh --fetch-all --sheet --appsec`.
- **Quand** : depuis develop ou un nouvel espace de travail, sans fichier non commité. Reprend où il s'est arrêté.
- **Utilité** : la dette Fortify réduite par lots, chaque correctif prouvé par un test.

### `commands/tests.md` — `/tests`
- **Ce qu'il fait** : des tests unitaires sans ticket, pour les classes, fichiers ou dossiers que tu nommes (6 fichiers au plus par run) : le test-guardian mesure la couverture, écrit les tests du comportement actuel dans le style du dépôt, les prouve (verts deux fois, aucun test instable), mesure la couverture après ; un commit sur une branche `test/…` (ou ta branche). Ton travail non commité qui n'est pas un test est d'abord commité à part, si tu le veux. Rien n'est poussé.
- **Agent** : pilot. **Faits calculés** : `fortify.sh prereq --tests`, `workflow-state.sh --no-fetch`.
- **Quand** : pour ajouter des tests hors Jira ; ensuite `/push`.
- **Utilité** : la couverture qui monte sans ticket, avec les mêmes preuves que dans `/go`.

### `commands/push.md` — `/push`
- **Ce qu'il fait** : commit et push du travail de ce dossier, avec ou sans ticket. Lit les changements (non commités et commits pas encore poussés), builde et teste d'abord quand du code a changé (pas de nouveau si ce même code est déjà passé), puis pose UNE question : la branche (quand il en faut une), le message de commit en conventional commit, la MR ; chaque fois la recommandation d'abord, et ta propre réponse possible. Un build ou des tests en échec : la question propose « Ne rien pousser, je corrige » (recommandé). Puis `branch.sh --here` et `ship.sh`, et la MR en Draft si tu l'as choisie.
- **Agent** : pilot. **Faits calculés** : `workflow-state.sh --no-fetch`, `detect-project-type.sh`.
- **Quand** : après un travail fait dans la conversation, un POC, de la doc, des tests ; « vite » prend les recommandations sans question ; « sans les tests » saute le build.
- **Utilité** : pousser hors Jira sans bloquer, sans jamais pousser sur develop, ni un secret, ni du code non buildé sans le savoir.

### `commands/sync.md` — `/sync`
- **Ce qu'il fait** : met la branche à jour sans rien commiter ni pousser : les commits poussés d'un autre poste (Rider sur le Mac) ; avec « develop », les nouveaux commits de sa base ; avec « merge <branche> », une autre branche. Par merge ; un conflit est annulé et ses fichiers nommés. Sur develop : une avance rapide sur origin seulement.
- **Agent** : pilot. **Faits calculés** : `workflow-state.sh --no-fetch`.
- **Utilité** : reprendre sur cette machine ce que tu as fait ailleurs, sans risque.

### `commands/daily.md` — `/daily`
- **Ce qu'il fait** : le point du matin pour un projet ou un board Jira : ta todo, ton sprint, les reviews qui t'attendent, tes MR reliées à leurs tickets, quoi prendre ensuite, hors sprint, et un plan du jour, avec les liens. Lecture seule. Finit par un QCM « Sur quoi tu bosses ? » dont chaque option lance `/go <CLÉ>`.
- **Agent** : pilot. **Faits calculés** : `todo.sh list`.
- **Utilité** : savoir par quoi commencer, en une commande.

### `commands/review.md` — `/review`
- **Ce qu'il fait** : la review d'une MR d'un collègue (`!<iid>`, son URL ou sa branche), sans toucher ta branche ni tes fichiers : commentaires prêts à coller dans GitLab, avec fichier:ligne et gravité. Remplace le `/review` d'OpenCode, fait pour GitHub.
- **Agent** : checker. **Faits calculés** : `detect-project-type.sh`, `review-target.sh`.
- **Utilité** : une review complète en lecture seule, adaptée au type du projet.

### `commands/compare.md` — `/compare`
- **Ce qu'il fait** : compare une fonctionnalité avec un dépôt où elle marche (code migré, ancienne version) : packages, code et historique d'abord par un script, puis l'agent suit la valeur qui diffère jusqu'à sa cause (code, package, configuration, données, correctif jamais reporté). Lecture seule.
- **Agent** : debugger. **Faits calculés** : `compare-repos.sh --raw`.
- **Utilité** : trouver pourquoi « ça marchait avant » sans tout relire.

### `commands/outil.md` — `/outil`
- **Ce qu'il fait** : les autres outils, derrière une seule commande : `doc`, `audit`, `licences`, `release-notes`, `pattern`, `cqrs`, `setup`, `abandon`, `todo`, `stats`. `outil.sh` reconnaît l'outil, calcule ses faits et nomme le skill `pack-<outil>` qui porte la procédure ; `/outil` seul donne la liste.
- **Agent** : build (la conversation). **Faits calculés** : `outil.sh --raw`.
- **Utilité** : dix outils sans dix commandes à retenir.

## Les agents

La ligne `permission:` de chaque agent est générée par `tools/permissions.py` (ne la modifie jamais à la main) : tout ce qui n'y est pas permis est refusé, sans question. Aucun agent du pack ne commite, ne pousse ni n'écrit dans Jira, Confluence ou GitLab, sauf le pilote, et seulement par les scripts du pack (et la MR en Draft).

### `agents/pilot.md`
- **Rôle** : mène `/go`, `/fix`, `/fortify`, `/daily`, et le travail hors ticket `/push`, `/sync`, `/tests`. Délègue l'analyse, chaque étape, la review et les diagnostics à des sous-agents ; n'écrit jamais de code.
- **Peut** : écrire la fiche (seulement par `ticket-sheet.sh`), lancer `branch.sh` et `ship.sh` (ses seules écritures git), `test-guardian.sh setup`, `park` et `unpark`, `fortify.sh discard` ; appeler analyst, coder, checker, debugger et test-guardian ; poser des questions, seulement celles que sa commande prévoit ; créer la MR en Draft. 100 étapes au plus par tour, caché dans le choix des agents.
- **Utilité** : un run qui va au bout sans toi et s'arrête net (⛔) sur ce qu'il ne doit pas trancher.

### `agents/analyst.md`
- **Rôle** : lit le ticket Jira, ses pages Confluence et le code, puis écrit la fiche : critères d'acceptation, plan numéroté avec ses fichiers et ses tests, tests attendus, décisions avec leur raison, questions bloquantes seulement. Lecture seule partout ailleurs. Sous-agent de `/go` et `/fortify`.
- **Utilité** : un plan vérifiable avant la première ligne de code.

### `agents/coder.md`
- **Rôle** : réalise UNE étape du plan, ou une liste de corrections donnée, avec ses tests unitaires, puis builde et teste (par `build-test.sh`). Ne pose jamais de question : décide comme le code existant et rapporte ses décisions. Écrit dans le dépôt (jamais dans `.git`) ; jamais de commit, push ou merge. Sous-agent du pilote.
- **Utilité** : un changement petit, testé et relisible à chaque étape.

### `agents/checker.md`
- **Rôle** : relecteur senior strict, en lecture seule : l'auto-review d'une branche avant que `/go`, `/fix` ou `/fortify` la pousse (constats, critères d'acceptation, pré-scan sécurité), et `/review` d'une MR d'un collègue. Adapte ses contrôles au type du projet.
- **Utilité** : une review avant la tienne.

### `agents/debugger.md`
- **Rôle** : enquêteur en lecture seule : traces, tests en échec, logs, rapports de bug ; peut lancer builds et tests ; trouve la cause racine, ne modifie jamais le code. Sous-agent du pilote dans `/go`, `/fix` et `/fortify` (le diagnostic de ce qui échoue), et agent de `/compare`, où il peut te poser une question.
- **Utilité** : la cause d'un échec, prouvée, avant toute correction.

### `agents/test-guardian.md`
- **Rôle** : gardien des tests unitaires d'un travail à la fois, avec quatre missions : « faille » (`/fortify`, faille de `/fix`), « bug » (étape « test d'abord » de `/go`, bug de `/fix`), « couverture » (lignes modifiées qu'aucun test n'exécute) et « tests » (`/tests`). Toute mesure et toute preuve passent par `test-guardian.sh` (jamais un résultat jugé en lisant le code) ; seul à pouvoir sceller ou remettre les tests d'une preuve. N'écrit que dans les projets de tests ; ne lance jamais `dotnet` lui-même.
- **Utilité** : des tests qui prouvent quelque chose : rouges avant, verts deux fois après, aucune perte de couverture.

### `agents/doc-writer.md`
- **Rôle** : écrit et met à jour `docs/` et le `README.md` racine, en français, depuis le code, pour `/outil doc`. N'ouvre jamais un fichier de configuration, ne copie jamais une valeur, ne touche ni au code, ni aux tests, ni à Confluence.
- **Utilité** : une documentation factuelle, avec ses sources, sans fuite de configuration.

## Les skills

Un skill est une procédure ou un savoir qu'un agent charge quand sa description le dit. Les `pack-<outil>` portent la procédure de `/outil <outil>` ; les autres, des règles que les agents chargent selon le travail.

### `skills/pack-abandon/SKILL.md` — `/outil abandon`
Annule un ticket lancé par erreur : `abandon.sh --check` dit ce qui serait supprimé, une question te le fait confirmer, puis `abandon.sh` le fait. Refuse toute branche qui contient du travail (un commit que sa base n'a pas, un fichier non commité). Rien ne change dans Jira ni GitLab.

### `skills/pack-audit/SKILL.md` — `/outil audit`
Audit des bonnes pratiques de tout le dépôt selon son type (charge `best-practices`) : chaque pratique présente, partielle ou absente avec sa preuve (fichier:ligne), et la plus petite façon d'ajouter ce qui manque. Lecture seule.

### `skills/pack-cqrs/SKILL.md` — `/outil cqrs`
Une command ou une query CQRS avec son handler, son validator, ses tests et, si le dépôt le fait, son endpoint, en imitant les exemples de référence du dépôt (charge `dotnet-cqrs-conventions`) ; puis build et tests.

### `skills/pack-doc/SKILL.md` — `/outil doc`
Délègue au doc-writer l'écriture de `docs/` (architecture, API, configuration, intégrations, données, exploitation) depuis l'inventaire calculé (`doc-inventory.sh`, `api-routes.sh`, `config-keys.sh`) ; en mise à jour, seulement les sujets touchés depuis la dernière fois. Puis, si tu le demandes, la publication sur Confluence, chaque page après ta validation.

### `skills/pack-licences/SKILL.md` — `/outil licences`
Lit le résultat de `package-licenses.sh` : les packages NuGet devenus payants ou copyleft à partir d'une version, avec leur option gratuite. Aucun autre appel.

### `skills/pack-pattern/SKILL.md` — `/outil pattern`
Capture une bonne implémentation d'un autre dépôt en skill d'équipe `pattern-<nom>-<back|front>` (créé ou enrichi), avec les packages internes décrits par leurs appels dans le code, jamais en ouvrant une DLL ; `/go` s'en sert ensuite tout seul, ou avec « comme le pattern <nom> ».

### `skills/pack-release-notes/SKILL.md` — `/outil release-notes`
La note de version d'une mise en production depuis master (`release-commits.sh`, tickets Jira lus), d'un dépôt ou d'un groupe de dépôts regroupé par ticket, dans la forme de la dernière note ; publiée sur Confluence après ta validation.

### `skills/pack-setup/SKILL.md` — `/outil setup`
Crée ou met à jour l'`AGENTS.md` du dépôt depuis le code : court et utile aux agents (builder et tester ici avec `build-test.sh`, ce que la CI impose, les conventions avec le fichier à imiter, les exemples de référence, les conventions git). Une fois par dépôt, puis après un gros changement.

### `skills/pack-stats/SKILL.md` — `/outil stats`
Le tableau de `ticket-stats.sh` est déjà affiché ; le skill dit comment le commenter en trois lignes au plus.

### `skills/pack-todo/SKILL.md` — `/outil todo`
La todo personnelle (`todo.sh`), hors Jira et hors dépôts : ajouter avec une échéance en français, marquer fait, supprimer, rappels. La liste s'affiche tout de suite, sans attendre le modèle.

### `skills/best-practices/SKILL.md`
Les bonnes pratiques par type de projet (API .NET, CQRS, Blazor, .NET Framework, librairie, front-end), avec comment détecter si chacune est déjà en place, et la règle : aucune suggestion sans bénéfice actuel et concret. Chargé par le coder pour une décision de gestion d'erreurs, de feature flag ou de performance, et par `/outil audit`.

### `skills/build-fix/SKILL.md`
Corriger une erreur de compilation avec le plus petit changement : obtenir les erreurs (`build-test.sh --build-only`), ne jamais toucher aux fichiers pour une erreur d'Artifactory, ne jamais remettre MediatR, trois tours au plus. Chargé par le coder et par la conversation (« corrige le build »).

### `skills/dotnet-cqrs-conventions/SKILL.md`
Les conventions des API .NET 10 Clean Architecture + CQRS avec le médiateur interne et FluentValidation : couches, un cas d'usage par dossier, requêtes, handlers, validators, tests, et la liste à vérifier avant de dire « fini ». Seulement pour un dépôt de type `cqrs-api`.

### `skills/explain-code/SKILL.md`
La méthode pour expliquer un fichier, un endpoint, une page ou un flux de bout en bout, en suivant les couches qui existent vraiment dans le projet. Lecture seule.

### `skills/fortify-remediation/SKILL.md`
Les corrections des catégories Fortify courantes en C# et en TypeScript (log forging, path manipulation, SSRF, privacy violation, en-têtes, open redirect, injection, XSS, crypto faible…) et comment juger un faux positif. Chargé avant de trier ou de corriger une faille, dans `/fortify` et `/fix`.

### `skills/integrations-guardrails/SKILL.md`
Les garde-fous et pièges connus de SharePoint (CSOM), DocuSign, AWS S3 et Piano Analytics dans les API .NET. Chargé avant de lire, déboguer, relire ou modifier du code qui les touche.

## Les scripts

Ils font ce que le modèle ne doit pas faire lui-même : écrire dans git, mesurer, calculer. Leur sortie est en anglais, en lignes `MOT-CLÉ: …` que les agents lisent (`STOP:` arrête toujours), sauf ce qui t'est montré tel quel (la todo, les stats, la liste des outils) ; ils ne demandent jamais rien. « Écrit » dit ce qu'un script peut modifier ; les autres ne modifient rien.

### `scripts/abandon.sh`
- **Ce qu'il fait** : annule le ticket de la branche courante sans jamais perdre de travail : refuse (`STOP:`) une branche avec un commit que sa base n'a pas ou un fichier non commité ; sinon revient sur la base (dossier principal : la branche de base amenée à origin en avance rapide seulement ; espace de travail : HEAD détachée sur `origin/<base>`), supprime la fiche, puis la branche locale par `git branch -d`. `--check` dit ce qu'il ferait, sans rien toucher.
- **Lancé par** : `/outil abandon` (skill `pack-abandon`), seulement par la conversation : refusé à tous les agents du pack. **Écrit** : la branche courante, la fiche, la branche locale. Rien sur GitLab.
- **Utilité** : défaire un `/go` lancé sur le mauvais dépôt ou le mauvais ticket.

### `scripts/base.sh`
- **Ce qu'il fait** : affiche la base d'une branche : celle enregistrée par `/go … depuis <branche>` (`branch.<nom>.opencode-base` de la config git) tant qu'origin l'a, sinon origin/develop, main ou master. `--why` dit d'où elle vient, `--default` donne la base par défaut. Sans fetch.
- **Lancé par** : `branch.sh`, `ship.sh`, `diff-guard.sh`, `workflow-state.sh`, `abandon.sh`.
- **Utilité** : une seule définition de la base pour le diff, la review, le contrôle avant push, le merge de `ship.sh --base` et la cible de la MR.

### `scripts/branch.sh`
- **Ce qu'il fait** : met le dépôt sur la bonne branche, sans rien demander.
  - Mode ticket (`/go`) : garde la branche qui porte la clé, sinon reprend celle de la clé (locale, puis origin), sinon crée `<type>/<CLÉ>-<mots du résumé>` depuis la base à jour (ou `--from <branche>`, enregistrée comme base). `LOCAL` devient la prochaine clé `LOCAL-<n>` libre, réservée tout de suite pour que deux `/go` de deux espaces de travail n'aient jamais la même.
  - Mode ici (`--here`, `/push` et `/tests`) : sur develop, master, main, une HEAD détachée ou une branche `opencode/…`, crée `<type>/<mots>` ou le nom donné (`--name`, rendu valide s'il le faut : il le dit) au commit courant, avec les changements non commités ; ailleurs, garde la branche. Des commits faits par erreur sur develop partent sur la nouvelle branche et develop revient à origin (`MOVED:`).
  - Des changements non commités ne voyagent jamais en silence : hors des cas ci-dessus, il s'arrête et les liste.
- **Lancé par** : le pilote seul (`/go`, `/fortify`, `/push`, `/tests`). **Écrit** : les branches locales, la config git (base), les réservations `LOCAL-<n>`.
- **Utilité** : jamais de travail sur develop, jamais deux tickets dans un même dossier, jamais un changement perdu.

### `scripts/build-test.sh`
- **Ce qu'il fait** : builde une solution ou un projet .NET en silence, puis lance ses tests seulement si le build passe, en un appel ; finit par des lignes `BUILD:` et `TESTS:` explicites, `FAILED TESTS (<n>): <noms>` après un échec, `ENVIRONMENT PROBLEM` quand la machine ne peut pas (dotnet absent, Artifactory qui refuse). Un test de plus de 5 minutes est arrêté et nommé (`HANG:`). Les projets Microsoft.Testing.Platform (MSTest.Sdk, xUnit v3, TUnit…) sont lancés comme les applications qu'ils sont (`test-platform.sh`). Options : `--build-only`, `--no-build`, `--if-changed` (rien de relancé quand ce même code a déjà passé ce même run : `TESTS: OK (not run again…)`). Un seul build ou test à la fois par dossier (`WAIT:` sinon).
- **Lancé par** : `/go`, `/fix`, `/fortify`, `/push`, le coder, le debugger, la conversation (ses règles le demandent), `test-guardian.sh`. **Écrit** : dans le dossier git seulement (verrou `opencode-dotnet.lock`, cache `opencode-green`, fichiers d'un test bloqué), jamais dans le dépôt.
- **Utilité** : une sortie courte et sûre pour le modèle, au lieu de milliers de lignes de `dotnet test` ; jamais `dotnet run`.

### `scripts/diff-guard.sh`
- **Ce qu'il fait** : le dernier contrôle avant chaque push, sans le modèle. `STOP` (rien n'est poussé) : un secret dans une ligne ajoutée par un des commits à pousser, même retiré par un commit suivant (clé privée, token cloud ou GitLab, mot de passe dans une URL ou une chaîne de connexion…), un fichier de clé ou `.env` ajouté, un marqueur de conflit, un package payant ou copyleft ajouté, la valeur d'une variable secrète de l'environnement n'importe où. `WARNING` : les mêmes constats dans les tests, un binaire ou un fichier de plus de 1 Mo. `PACKAGES` : les packages ajoutés ou changés, pour la MR. Ne montre jamais la valeur d'un secret.
- **Lancé par** : `ship.sh`, avant chaque push. **Utilité** : `/go` et `/fix` poussent sans humain entre les deux : c'est la porte.

### `scripts/fetch.sh`
- **Ce qu'il fait** : un `git fetch` borné (30 s) qui n'attend jamais un mot de passe ; code 77 quand GitLab refuse les identifiants, 124 après le délai. Relance jusqu'à 3 fois, avec une pause qui grandit, un fetch qui croise le verrou d'une référence qu'un autre espace de travail met à jour au même moment.
- **Lancé par** : `ship.sh`, `branch.sh`, `workflow-state.sh`, `abandon.sh`, `review-target.sh`, `release-commits.sh`, `workspace.sh`. **Écrit** : les références distantes (`origin/…`).
- **Utilité** : une commande ne reste jamais bloquée sur GitLab, et deux espaces de travail peuvent fetcher ensemble (sans lui, chaque fetch simultané échouait).

### `scripts/ship.sh`
- **Ce qu'il fait** : la seule façon dont les agents écrivent dans git, en un appel : commit de tout (`git add -A`), intégration des commits poussés entre-temps sur la copie distante (un autre poste), avec `--base` les nouveaux commits de la base, avec `--merge <branche>` une autre branche ; puis `diff-guard.sh` et push (l'upstream au premier push). `--no-push` : le commit seul (fin d'une étape). `--sync-only` : les merges seuls (`/sync`), une avance rapide seulement sur develop, master ou main. Toujours par merge : jamais de rebase, de force-push, ni de push sur develop, master ou main. Un conflit est annulé et ses fichiers nommés ; des identifiants absents donnent `STOP: AUTH FAILED`. Sortie : `COMMIT`, `REMOTE`, `BASE`, `GUARD`, `PUSH`, `MR LINK`, `RESULT: OK`.
- **Lancé par** : le pilote seul (`/go`, `/fix`, `/fortify`, `/push`, `/sync`, `/tests`). **Écrit** : commits, merges, push.
- **Utilité** : chaque écriture git est contrôlée et réversible.

### `scripts/workflow-state.sh`
- **Ce qu'il fait** : l'état git dont les commandes ont besoin, en un passage après un seul fetch : racine, espace de travail, branche, clé Jira, base, empreinte du code, upstream, commits non poussés, avance ou retard sur la copie distante, merge en cours, fichiers non commités et non suivis, fiches existantes. Options : `--sheet` (la fiche), `--tickets`, `--diff`, `--appsec` (la seule ligne `APPSEC_PROJECT_NAME`, jamais le reste du fichier), `--no-fetch`, `--fetch-all`.
- **Lancé par** : les lignes `[[run]]` de `/go`, `/fix`, `/fortify`, `/push`, `/sync`, `/tests` ; le pilote qui a perdu le fil. **Écrit** : les références distantes (fetch) ; une fois, le déplacement des fiches d'une ancienne version.
- **Utilité** : des faits exacts au premier tour, sans courses entre commandes git parallèles.

### `scripts/state-fingerprint.sh`
- **Ce qu'il fait** : l'empreinte du code du dossier (fichiers suivis avec leur contenu actuel, plus les non suivis non ignorés) : le même code donne la même valeur, commité ou non. N'écrit rien.
- **Lancé par** : `workflow-state.sh`, `build-test.sh`. **Utilité** : savoir si un build, des tests ou une review valent encore pour le code d'aujourd'hui.

### `scripts/ticket-sheet.sh`
- **Ce qu'il fait** : met à jour la fiche du ticket de la branche en un appel : `tick <N>` (coche l'étape N du plan et ajoute une ligne de suivi datée), `decision`, `suivi`, `plan`, `check` (la structure dont `/go` a besoin : sections, étapes numérotées avec fichiers et tests, chaque critère couvert par un test attendu), `delete` ; `fixed` sert à la 1.19. Chaque écriture réaffiche le plan.
- **Lancé par** : le pilote seul. **Écrit** : la fiche.
- **Utilité** : une étape cochée ne dépend pas d'une édition exacte du fichier par le modèle ; la fiche est le point de reprise de chaque run.

### `scripts/test-guardian.sh`
- **Ce qu'il fait** : les mesures et les preuves des tests unitaires. `deps` (le module d'un fichier et ses dépendances, deux niveaux), `coverage` (couverture ligne et branche par fichier, avec coverlet ou l'extension de la plateforme), `compare` (`STOP` si un fichier perd de la couverture), `red` (les nouveaux tests échouent, deux fois de la même façon), `green` (ils passent deux fois : sinon `FLAKY`), `build`, `tests-only`, `seal`/`sealed`/`restore` (la preuve scellée avant le correctif ; vide, sans aucun fichier, pour une faille qu'aucun test unitaire ne peut montrer), `park`/`unpark` (les preuves d'une vague), `setup xunit|mstest|nunit` (crée le projet de tests, ou ajoute le collecteur de couverture ; un échec défait tout), `changes <base>` (toute la suite, puis les lignes modifiées qu'aucun test n'exécute), `folder`.
- **Lancé par** : le test-guardian (mesures, preuves, scellés), le coder (`green`, pour finir un correctif sur les tests scellés), le pilote (`setup`, `park`, `unpark`, `changes`) ; seul le test-guardian peut sceller ou remettre, seul le pilote peut créer ou garer. **Écrit** : le dossier des mesures `<dossier git>/opencode-tickets/<CLÉ ou nom de branche>.tests`, commun aux espaces de travail ; avec `setup`, un projet de tests dans le dépôt ; avec `restore`/`park`/`unpark`, les fichiers de tests d'une preuve.
- **Utilité** : aucun agent ne juge une couverture ou un résultat de test en lisant du code.

### `scripts/test-platform.sh`
- **Ce qu'il fait** : comment les tests d'un dépôt .NET tournent : VSTest ou Microsoft.Testing.Platform. `scope` (les projets de tests d'une cible et leur lanceur), `kind` (lanceur, framework, extension de couverture), `projects`, `run` (lance un projet MTP comme une application, `dotnet exec`, avec les options du pack traduites : filtre, couverture, délai). Sans `dotnet run`, sans modifier le dépôt.
- **Lancé par** : `build-test.sh`, `test-guardian.sh`, `fortify.sh`, `outil.sh setup`. **Utilité** : le SDK .NET 10 refuse ces projets dans le mode par défaut de `dotnet test`.

### `scripts/fortify.sh`
- **Ce qu'il fait** : ce dont `/fortify` a besoin en plus des mesures. `prereq` : dotnet, la ligne de l'application SSC, puis les projets de tests unitaires et leur collecteur de couverture (`PREREQ: OK`, `NO TEST PROJECT`, `COVERLET MISSING`, `SETUP NEEDED`) ; avec `--tests`, sans la ligne SSC (pour `/tests`). `batch` : le dossier du lot de la branche. `discard <label>` : met de côté (`git stash`, récupérable) le travail d'une faille qui a échoué, jamais sur develop, master, main ni une HEAD détachée.
- **Lancé par** : `/fortify`, `/fix` (`discard`), `/tests` (`prereq --tests`) ; `discard` par le pilote seul. **Écrit** : le dossier du lot ; un stash.
- **Utilité** : un lot qui démarre seulement quand il peut prouver, et un échec qui ne laisse rien traîner.

### `scripts/detect-project-type.sh`
- **Ce qu'il fait** : le type du dépôt (cqrs-api, api, blazor, dotnet-app, legacy, library, frontend) et sa commande de build, depuis les seuls fichiers suivis ; `--files` ajoute la racine, l'état de l'AGENTS.md, les solutions et projets, et ce qui définit le build, la CI et les conventions. La section « Project type » d'AGENTS.md l'emporte.
- **Lancé par** : `/go`, `/fix`, `/push`, `/review`, le checker, le debugger, `outil.sh`, les skills `build-fix`, `explain-code`, `pack-doc`. **Utilité** : chaque agent adapte ses règles au bon type de projet.

### `scripts/outil.sh`
- **Ce qu'il fait** : le répartiteur de `/outil` : reconnaît l'outil (et ses synonymes), affiche le skill `pack-<outil>` qui porte sa procédure et les faits qu'il lui faut, calculés par les autres scripts (détection, packages, commits de master, projets de tests…). `todo` et `stats` affichent leur résultat tout de suite. Sans outil connu : la liste.
- **Lancé par** : `/outil`. **Écrit** : seulement la todo, pour `todo`.
- **Utilité** : chaque outil part avec ses faits au premier tour.

### `scripts/package-refs.sh`
- **Ce qu'il fait** : les packages NuGet du dépôt, internes et publics distingués par la signature nuget.org du cache ; pour chaque package interne : frameworks, documentation XML, dépendances, dépôt source, lus dans son `.nuspec`, jamais dans une DLL. `--doc <package>` : le fichier de documentation XML d'un package (interne ou public, Blazorise.DataGrid, MudBlazor…) pour le framework le plus proche.
- **Lancé par** : `/go`, l'analyste, le coder, `outil.sh` (audit, pattern), `compare-repos.sh`, les skills `pack-doc` et `pack-setup`. **Utilité** : l'API exacte d'un package, au lieu de la deviner, de sonder une DLL ou de chercher sur le web.

### `scripts/package-licenses.sh`
- **Ce qu'il fait** : les packages NuGet dont la licence les rend payants ou copyleft (licence commerciale, frais de maintenance, AGPL), par version : tout le dépôt, `--diff` (ajoutés ou changés depuis la base), ou un package avant de l'ajouter. Règles vérifiées en octobre 2026.
- **Lancé par** : `/outil licences`, `diff-guard.sh` (un package payant ajouté arrête le push). **Utilité** : ne jamais introduire sans le savoir un package qui devient payant.

### `scripts/compare-repos.sh`
- **Ce qu'il fait** : ce qui diffère entre un dépôt de référence (la version qui marche) et le dépôt courant, avant que l'agent lise le code : branches, frameworks et SDK, packages de versions différentes (directs, puis transitifs), et avec un identifiant : les fichiers qui le contiennent, leurs diffs, leur historique, dont les commits de la référence jamais reportés. Lecture seule, jamais une valeur de configuration.
- **Lancé par** : `/compare`. **Utilité** : la piste de la cause en un appel.

### `scripts/review-target.sh`
- **Ce qu'il fait** : prépare `/review` sans toucher ton dossier, ton index ni ta branche : fetch de la MR (`refs/merge-requests/<iid>/head`) ou de sa branche, puis la révision à relire, ses commits, ses clés Jira et son diff contre la branche cible.
- **Lancé par** : `/review`. **Écrit** : les références distantes (fetch). **Utilité** : relire la MR d'un collègue en plein milieu de ton propre travail.

### `scripts/doc-inventory.sh`
- **Ce qu'il fait** : les faits du dépôt dont sa documentation a besoin, chacun avec son fichier et sa ligne : documentation existante (et ce qui a changé depuis la dernière génération), projets et références (graphe Mermaid), points d'entrée, handlers, options, intégrations, données, tâches de fond, authentification, CI, front-end ; les endpoints viennent d'`api-routes.sh`, les clés de configuration de `config-keys.sh`. Aucune valeur de configuration.
- **Lancé par** : le skill `pack-doc` (le doc-writer). **Utilité** : la documentation ne dit que ce que le code montre.

### `scripts/api-routes.sh`
- **Ce qu'il fait** : les endpoints HTTP calculés depuis le C# : contrôleurs (routes de classe et d'action, `[Authorize]` hérités) et minimal APIs (`MapGet`… avec les préfixes de leurs `MapGroup`), avec verbe, route, handler et sa ligne, autorisation, paramètres, type de réponse ; ce qui ne se calcule pas est listé avec son fichier et sa ligne.
- **Lancé par** : `doc-inventory.sh`, le skill `pack-doc`. **Utilité** : la page API de la doc, exacte.

### `scripts/config-keys.sh`
- **Ce qu'il fait** : chaque clé de configuration du dépôt (appsettings, launchSettings, web.config, `.env.example`, environnements front), jamais une valeur : son type, « secret? » quand elle en a l'air, et son état dans chaque fichier (renseignée, vide, remplacée au déploiement).
- **Lancé par** : `doc-inventory.sh`, le skill `pack-doc`. **Utilité** : documenter la configuration sans qu'une valeur sorte du script.

### `scripts/pattern-source.sh`
- **Ce qu'il fait** : où est une implémentation dans le dépôt source, sans chercher : la branche extraite comparée à sa base, puis pour chaque clé Jira du texte ses branches, ses commits (MR comprises), s'ils sont dans la copie extraite, et les fichiers qu'ils ont changés.
- **Lancé par** : `outil.sh` pour `/outil pattern`. **Utilité** : capturer le bon code, pas une copie qui ne contient pas encore le développement.

### `scripts/pattern-skills.sh`
- **Ce qu'il fait** : les skills `pattern-*` de cette machine avec leurs chemins absolus, lus sur le disque.
- **Lancé par** : `/go`, l'analyste, le coder, `outil.sh`. **Utilité** : OpenCode ne connaît un skill créé qu'après un redémarrage ; les agents lisent le fichier lui-même.

### `scripts/release-commits.sh`
- **Ce qu'il fait** : ce qui a changé sur la branche de production d'un dépôt entre deux points (commit ou date) : MR fusionnées, commits, clés Jira, changements de version ; `--head` : la racine et la tête de la branche de production.
- **Lancé par** : `outil.sh`, le skill `pack-release-notes`. **Écrit** : les références distantes (fetch). **Utilité** : la note de version part des faits.

### `scripts/ticket-stats.sh`
- **Ce qu'il fait** : ce que `/go` et `/fix` ont fait sur les tickets du dépôt (ou des dépôts donnés), lu dans leurs fiches : étapes, lancements, `/fix`, réponses du développeur, décisions de l'agent, arrêts, temps de l'analyse à la MR. En français, affiché tel quel.
- **Lancé par** : `outil.sh` pour `/outil stats`. **Utilité** : mesurer ce que l'agent fait vraiment, et où il s'arrête.

### `scripts/todo.sh`
- **Ce qu'il fait** : ta todo personnelle, un fichier Markdown hors de tout dépôt (`~/.config/opencode/todo.md`, ou `$OPENCODE_TODO`) : ajouter (l'échéance est lue dans le texte en français : demain, vendredi, fin du mois, 24/10…), `done`, `remove`, `due` (rappels), `count` ; les lignes faites sont gardées 30 jours. Modifiable à la main.
- **Lancé par** : `/outil todo`, `/daily` ; le plugin lit le même fichier pour afficher « ⏰ n rappel(s) » dans la ligne d'une commande. **Écrit** : le fichier de la todo.
- **Utilité** : tes rappels là où tu travailles, sans Jira.

### `scripts/workspace.sh`
- **Ce qu'il fait** : `new`, `list` et `remove` des espaces de travail (git worktrees) d'un dépôt, lancé par toi dans un terminal ; refusé à tous les agents.
- **Pour qui** : la 1.19, dont l'interface web n'offre plus de créer un espace de travail. Avec la v2, crée-les dans l'interface : ce script n'y sert plus (`ANALYSE.md`).

## Configuration et documentation

### `AGENTS.global.md`
Les règles globales de tous les agents, à fusionner dans `…/opencode/AGENTS.md` (avec tes sections « Daily » et « Release groups ») : réponses en français, code en anglais ; quand poser une question (dans un run : jamais, sauf ce que la commande prévoit ; dans la conversation : seulement quand la réponse change ce qu'on fait, en un QCM) ; le style de travail (lire avant d'écrire, le plus petit changement, ne jamais inventer un nom) ; la vitesse (builder et tester par `build-test.sh`, les formes de commandes refusées) ; le routage de tes demandes vers la bonne commande (`/go`, `/push`, `/tests`, `/outil …`) et les écritures git, seulement par ces commandes ; l'API d'un package par `package-refs.sh --doc` ; NuGet et Artifactory sans jamais lire leurs identifiants ; Jira et Fortify SSC.

### `AGENTS.repo-template.md`
Le modèle de l'`AGENTS.md` d'un dépôt (type, structure, build et tests, conventions, exemples de référence, git, Confluence). Le plus simple est `/outil setup`, qui le remplit depuis le code.

### `opencode.snippet.json`
La partie du pack d'`opencode.json`, à compléter avec tes propres sections (provider, modèle, MCP) comme le dit `MIGRATION.md`, étape 5.6 : les règles des agents d'OpenCode (`build`, `general`, `explore`, `plan`) générées par `tools/permissions.py`, la `permission` globale (outils de la v2 refusés, écritures MCP refusées, publication Confluence soumise à ta validation), `experimental`, `compaction.prune`, et `share`, `autoupdate` et `websearch` coupés.

### `CHECKSUMS-config.txt` et `CHECKSUMS-scripts.txt`
Les empreintes SHA-256 des agents, commandes, skills et du plugin, puis des scripts : avec `sha256sum -c`, l'étape 5 de `MIGRATION.md` te dit quels fichiers coller depuis GitHub, et quand tout est identique. Régénérées à chaque version (la commande est dans `README.md`, « Pour la maintenance du pack »).

### `README.md`
Ce que fait le pack, ses commandes, ce qui change par rapport à la v1, les réglages du modèle, les limites connues, et comment il est vérifié (« Pour la maintenance du pack »).

### `COMMANDES.md`
Le mode d'emploi au quotidien : chaque commande avec ses exemples, le travail hors ticket, les espaces de travail en parallèle, les identifiants GitLab, les logs, Qwen 3.8, le dépannage.

### `MIGRATION.md`
Le passage de la 1.19 à la v2, pas à pas, sans lancer de script : télécharger, configurer à côté de la 1.19, vérifier par empreintes, démarrer, revenir en arrière ; l'annexe A quand la v2 a déjà remplacé la 1.19.

### `ANALYSE.md`
L'analyse d'origine d'OpenCode v2 (21 et 22 octobre 2026), gardée pour l'historique : ce que la v2 change pour le pack, constaté ou lu dans son code.

### `FICHIERS.md`
Ce document.

## Les outils de vérification (`tools/`)

Jamais copiés dans ta configuration. Ils vérifient le pack avant chaque push ; `README.md`, « Pour la maintenance du pack », donne leurs commandes. Hors de `opencode-v2/`, `.github/workflows/opencode-v2.yml` les lance sur GitHub à chaque push qui change le pack, et le flux Fortify avec le vrai SDK .NET.

### `tools/permissions.py`
Génère la ligne `permission:` de chaque agent et les règles d'`opencode.snippet.json`, depuis des listes nommées (lectures permises, git en lecture, scripts d'écriture réservés au pilote, secrets, décompilation, `dotnet run`…). Jamais de règle « ask » sur le shell, la lecture ou l'écriture : une réponse « toujours » vaudrait pour tous les agents. À relancer après chaque changement de règle.

### `tools/permission-sim.mjs`
Le moteur de permissions d'OpenCode, porté fidèlement (correspondance des motifs, fusion des règles, analyse du shell par tree-sitter, chemins hors du dépôt, sous-sessions) : rejoue chaque cas de `permission-corpus.mjs` avec les vrais fichiers du pack.

### `tools/permission-corpus.mjs`
Les 2 216 cas : chaque commande que le pack prescrit à un agent (126, chacune permise à l'agent qui la lance), les réflexes du modèle, les secrets, les écritures git interdites, la liste blanche du coder, les outils MCP, les outils que la v2 ajoute ; avec la décision attendue pour chaque agent.

### `tools/plugin-test.mjs`
Les 695 vérifications du plugin, contre un faux OpenCode v2 dans un faux dossier personnel : les gardes du shell et des fichiers (dépôt, refus, délais), les commandes prescrites passées aux gardes, le verrou (deux runs en même temps dans un dépôt et son espace de travail), les titres, les QCM, la boucle coupée, la pénalité de présence, les reprises, les résumés de contexte, ce que la v2 ouvre.

### `tools/scripts-test.sh`
Les 69 contrôles des scripts git (`branch.sh`, `base.sh`, `ship.sh`, `workflow-state.sh`, `diff-guard.sh`, `abandon.sh`) contre un dépôt nu qui joue GitLab, avec dash, bash ou busybox sh.

### `tools/scenarios-test.sh`
Les 104 contrôles des journées d'un développeur, au niveau des scripts : `/go`, `/fix`, `/push`, `/sync`, `/tests` dans l'ordre de leurs commandes, sur un dépôt avec tests, un sans tests, un second poste qui pousse aussi, puis deux et quatre espaces de travail d'un même dépôt qui buildent, fetchent et poussent en même temps, chacun sur sa branche, jusqu'au conflit et sa résolution. La part du modèle (le code qu'il écrit, les noms qu'il choisit) y est jouée par des réponses fixes.

### `tools/fortify-test.sh`
Les 157 contrôles du flux de `/fortify` et de son test-guardian, de A à Z, avec les lignes de commande de `commands/fortify.md` dans l'ordre de ses étapes, sur de vrais projets C# et de vrais tests (xUnit, et MSTest sur Microsoft.Testing.Platform) : prérequis, mise en place des tests, branche et fiche du lot, mesure de develop, preuves d'une vague en parallèle, rouge, instable, bloqué, preuves rangées, correctifs, tests scellés remis, couverture perdue, le code qui résiste, preuve vide d'une faille non démontrable, abandon mis de côté, chaque reprise, livraison ; un second lot dans un espace de travail. Avec `--real`, le vrai SDK .NET de la machine (à lancer sur la machine d'OpenCode : rien de ta configuration n'est touché) ; sans, le `dotnet` simulé. GitHub le lance avec le vrai SDK à chaque push.

### `tools/dotnet-test.sh`
Les 113 contrôles des scripts .NET (`build-test.sh`, `test-platform.sh`, `test-guardian.sh`, `fortify.sh prereq`, `outil.sh setup`, `package-refs.sh --doc`) avec le faux `dotnet` : VSTest, Microsoft.Testing.Platform (xUnit v3, MSTest.Sdk, TUnit), solution mixte, projet refusé par le SDK .NET 10.

### `tools/fake-dotnet.sh`
Un `dotnet` simulé, pour vérifier les scripts sur une machine sans SDK .NET (jamais installé par le pack) : `build`, `test`, `exec`, `new`, `add reference`, `sln add`, `msbuild -getProperty`, aux formats de sortie réels de VSTest et de Microsoft.Testing.Platform ; les tests d'un projet sont déclarés en commentaires, dans le projet ou dans ses fichiers de tests (`fake-test`, dont `requires`, un test qui passe selon le code de production ; `fake-cover`, `fake-build-error`…), à côté du vrai code C# que `--real` compile.

### `tools/validate.js`
Analyse l'en-tête de chaque agent, commande et skill avec `gray-matter`, le parseur d'OpenCode, et vérifie que chaque fichier du pack est décrit dans ce document.

`tools/node_modules` n'est pas un fichier du pack : il est créé par le `npm install` des vérifications, et n'est jamais commité.
