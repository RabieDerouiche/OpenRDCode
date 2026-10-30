# Notes de version du pack OpenCode v2

Une entrée par commit qui change `opencode-v2/`, la plus récente en haut : sa date et son heure, ce qui a été ajouté, changé et retiré, et le but. Le hash du commit est noté quand l'entrée a été écrite après coup ; une entrée écrite avec son commit n'en a pas (il n'existe pas encore). La CI refuse un commit du pack sans son entrée (`tools/release-notes.sh`).

Format d'une entrée (vérifié par la CI) :

```
## AAAA-MM-JJ HH:MM — titre
- **Ajouté** : …
- **Changé** : …
- **Retiré** : … (ou « rien »)
- **But** : …
```

## 2026-10-30 16:05 — La limite de sortie d'un modèle (`limit.output`) : ce qu'elle fait vraiment dans OpenCode v2
- **Ajouté** : COMMANDES.md : la commande qui montre les limites déclarées pour le modèle (`context`, `output`), et quoi faire d'un `output` à 4096. 1 vérification de plugin (878) : `compaction.buffer` d'`opencode.json` (ou `reserved`, son ancien nom) déplace le seuil de la fonction 13 comme il déplace le résumé d'OpenCode.
- **Changé** : plugin, fonction 13 : le seuil d'effacement dans un run se calcule comme OpenCode v2.1.3 et v2.1.4 calculent le moment du résumé (`compaction.ts`) : la fenêtre du modèle (`limit.input`, sinon `limit.context`) moins 15 %, au moins 16 000 tokens, ou moins `compaction.buffer` ; il ne dépend plus de `limit.output` (avant : `context - output`, la règle de la 1.x). Avec 131072 et 32768, le seuil passe de 98 304 à 111 412 tokens, ce que la v2 prend vraiment avant de résumer. README.md, « Réglages du modèle » : `output` = 32768, la longueur maximale d'une réponse, réflexion comprise ; OpenCode la réduit lui-même à la place qui reste dans `context` (32000 quand elle manque) ; un `output` à 4096 coupe les réponses d'un modèle qui réfléchit, et chaque coupure coûte une requête de plus ; `defaultCompletionOptions.maxTokens` est le réglage de Continue, qu'OpenCode ignore. FICHIERS.md (fonction 13, compte des vérifications), MIGRATION.md (compte).
- **Retiré** : la règle « `output` = le quart de `context` sous 128K » et la phrase « OpenCode compacte la session quand elle dépasse `context - output` » : fausses pour la v2, dont le code ne se sert de `limit.output` que pour le `max_tokens` des requêtes.
- **But** : répondre avec le code source, pas avec la 1.x, à « faut-il passer de 4096 à 32000 ? » : oui pour `limit.output` dans OpenCode, sans perdre de place pour le contexte ; et que le plugin efface au bon moment, quel que soit `output`.

## 2026-10-29 14:00 — Moins de requêtes au modèle : la mesure par agent, et les appels indépendants envoyés ensemble
- **Ajouté** : plugin, fonction 29 : pour chaque agent d'un run, ses requêtes au modèle, celles qui ont appelé des outils et le nombre de ces appels (champ `batch` de `openrd-pack-runs.tsv`, l'agent d'un sous-agent connu par son appel). `/outil vitesse` : « Requêtes au modèle, par agent : coder 80 requêtes (1,1 appel d'outil par requête)… », et un point à regarder quand un agent reste à un appel par requête (20 requêtes avec outils au moins) ; tous les agents à un appel : le serveur ne renvoie peut-être qu'un appel par réponse (le parser des appels d'outils du modèle dans vLLM, la passerelle), à vérifier avec l'équipe qui l'héberge. 1 contrôle de plus dans `tools/plugin-test.mjs` (877), 3 dans `tools/scripts-test.sh` (215).
- **Changé** : `agents/coder.md` : les modifications qui n'ont pas besoin du résultat l'une de l'autre (des fichiers différents, déjà lus) partent dans une seule réponse, puis le build et les tests en un appel ; ce qui dépend d'un build ou d'une lecture l'attend. `agents/test-guardian.md` et `agents/debugger.md` : les lectures, et les fichiers de tests indépendants, ensemble. `agents/pilot.md` : la ligne qui annonce une action longue va dans la même réponse que l'appel (une ligne seule termine le tour, et coûte une requête et une reprise). COMMANDES (`/outil vitesse`), FICHIERS, README, MIGRATION, les empreintes.
- **Retiré** : rien.
- **But** : chaque réponse d'un agent est une requête au serveur, qui renvoie tout le contexte et compte dans sa limite de débit : regrouper ce qui est indépendant en fait moins, sans rien envoyer avant d'avoir vu ce dont une action dépend ; et mesurer, par agent, si le modèle le fait vraiment.

## 2026-10-29 12:45 — Un nom de branche et « depuis » ensemble
- **Ajouté** : 7 contrôles dans `tools/scripts-test.sh` (212) des deux ensemble : « nouvelle branche <nom> depuis <branche> » et « sur <nouveau nom> depuis <branche> » créent la branche de ce nom à partir de l'autre, qui devient sa base (`base.sh` la donne) ; sans nom, la branche au nom du changement part de l'autre branche. `branch.sh` arrête une branche qui partirait d'elle-même (« sur X depuis X »), avant tout changement de branche, et `record_base` ne l'enregistre jamais.
- **Changé** : `commands/go.md` : sans ticket sur une branche à moi, le travail reste dessus sauf avec « depuis <branche> », qui demande une nouvelle branche ; la combinaison d'un nom et de « depuis » dite en clair. COMMANDES (deux exemples), FICHIERS, les empreintes.
- **Retiré** : rien.
- **But** : partir d'une release ou de la branche d'un collègue sous le nom que je choisis, sans surprise.

## 2026-10-29 12:15 — Le nom d'une nouvelle branche donné à /go : elle est créée sous ce nom
- **Ajouté** : `branch.sh --on <branche>` crée la branche sous ce nom quand elle n'existe ni ici ni sur origin (depuis la base, ou `--from`), la clé enregistrée pour elle ; sauf si une branche existante a presque le même nom (deux lettres d'écart au plus, majuscules comprises : une faute de frappe mettrait le travail à côté de la branche voulue), qui arrête en citant les deux noms et la façon de créer quand même. `--new <branche>` (« nouvelle branche <nom> », « crée la branche <nom> ») crée toujours, s'arrête sur un nom pris. 8 contrôles de plus dans `tools/scripts-test.sh` (205).
- **Changé** : `commands/go.md` : « sur <branche> » (aussi « branche <branche> ») prend la branche existante ou la crée ; « nouvelle branche <nom> ». COMMANDES (deux exemples), README, FICHIERS, la carte des flux, les empreintes.
- **Retiré** : l'arrêt « no branch … here nor on origin » sur un nom nouveau.
- **But** : donner à `/go` le nom de la branche à créer, sans retaper ni renommer ensuite, et sans qu'une faute de frappe crée une branche parasite.

## 2026-10-29 11:30 — Sans ticket, la branche garde son nom : plus de LOCAL-1 dedans
- **Ajouté** : `branch.sh --on <branche>` (`/go … sur <branche>`, avec ou sans ticket) : le travail va sur cette branche, sous son nom (ici, sinon depuis origin) ; jamais develop, main, master, la base ni une branche d'espace de travail ; un nom inconnu arrête avec les noms proches. La clé est enregistrée pour la branche dans la config git (`branch.<nom>.opencode-key`), comme la base l'était déjà (`opencode-base`) ; `ticket-sheet.sh`, `workflow-state.sh` (« Jira key from branch: LOCAL-2 (recorded for this branch…) »), `test-guardian.sh`, `fortify.sh`, `abandon.sh` et `workspace.sh` la lisent quand le nom de la branche ne porte pas de clé ; `/go <clé>` relancé depuis develop revient sur la branche enregistrée. 15 contrôles de plus dans `tools/scripts-test.sh` (197), 1 dans `tools/scenarios-test.sh`.
- **Changé** : sans ticket, `LOCAL-<n>` ne nomme plus que la fiche du ticket : une nouvelle branche s'appelle `<type>/<mots du résumé>` (`-2`, `-3`… quand le nom est pris, même par un `/go` d'un autre espace de travail au même instant), la clé enregistrée pour elle ; le lot de `/fortify` sans clé Jira aussi (`bugfix/fortify-path-manipulation-lot-2026`). `commands/go.md` : la consigne « sur <branche> » (« dans <branche> ») ; sans ticket, sur une branche à moi (ni develop, main, master, ni `opencode/…`, sans clé dans son nom), le travail reste sur elle, comme `/push`. `agents/pilot.md` : la clé locale ne nomme jamais une branche. MIGRATION 5.4 (`workspace.sh` plus récent, 41 lignes vérifiées sur une copie de la 1.19), README, COMMANDES, FICHIERS, la carte des flux, les empreintes.
- **Retiré** : `LOCAL-<n>` dans le nom des nouvelles branches (les branches qui l'ont déjà marchent toujours).
- **But** : la branche que je donne reste la mienne, sous son nom ; la clé technique de la fiche ne se voit plus dans GitLab.

## 2026-10-29 10:30 — Une demande tapée au QCM « Suite » est traitée, plus un « D'accord » qui arrête tout
- **Ajouté** : plugin, fonction 4 : une phrase tapée à la question « Suite » au lieu d'un choix (« le test X échoue », « reprends la tâche C1 ») fait démarrer la commande de l'option que le pilote a nommée dans sa réponse (« Je lance /fix avec ta demande : … »), la phrase après ses arguments, comme consigne ; jamais une commande que le QCM ne proposait pas, jamais un accent grave ni un `$` (OpenCode exécuterait ce qu'ils contiennent) ; la phrase n'est jamais écrite dans le journal. `commands/go.md` : une demande de travail sur ce que le run a déjà fait (un test qui échoue, un critère ou une étape à reprendre, un comportement à changer) passe en premier : le debugger d'abord pour un test qui échoue, puis un tour du coder, un commit, une ligne de suivi, puis la reprise du run (les étapes restantes, ou la vérification et la livraison qui met la MR à jour). `commands/fix.md` : une telle consigne est un point « À corriger » à part, source 👤, en tête de liste. 2 contrôles de plus dans `tools/plugin-test.mjs` (876).
- **Changé** : `agents/pilot.md`, la question « Suite » : une demande tapée → l'option qui s'en charge, « Je lance <commande> avec ta demande : « <ta phrase> » » ; aucune option ne le fait → la ligne de commande à taper ; seul ce qui ne demande rien (« Rien pour l'instant », « merci ») donne « D'accord. ». Les descriptions « Diagnostic demande » et « Demande du dev ». COMMANDES, FICHIERS, la carte des flux (« La suite d'un clic »), README, MIGRATION, les empreintes.
- **Retiré** : le « D'accord. » qui terminait le run sur toute réponse tapée qui n'était pas une commande.
- **But** : répondre au QCM par ce qu'il reste à faire, en mots, et que ce soit fait, sans retaper une commande.

## 2026-10-29 09:45 — La MR créée par le pilote, le lien seulement en dernier recours et avec sa raison
- **Ajouté** : plugin, fonction 33 : le journal du plugin dit ce qu'est devenue la MR de chaque run (`/go`, `/fix`, `/fortify`, `/push`) : l'outil qui crée les MR qu'avait le pilote, ou son absence (avec le nombre d'outils GitLab qu'il avait), une fois par run ; puis la réponse de chaque appel : créée, ou l'erreur de l'outil ou des règles de permission (type, statut HTTP, 160 premiers caractères), jamais le titre ni la description. 3 contrôles de plus dans `tools/plugin-test.mjs` (874). COMMANDES.md, « Vérifier le nom de l'outil qui crée les MR » : la commande qui lit ces lignes, et ce que chacune veut dire.
- **Changé** : `agents/pilot.md`, la MR : la créer est le travail du pilote ; une erreur qui nomme un paramètre (400, 422, un projet ou une branche introuvable à cause de leur écriture) est corrigée une fois (le projet par son chemin `groupe/nom` ou son identifiant, les branches telles que sur origin) ; le lien pour créer la MR à la main seulement après un second refus, un refus des permissions ou sans outil, et la ligne qui suit l'en-tête dit pourquoi, l'erreur mot pour mot. `commands/go.md` : l'en-tête « 🚀 MR à créer » toujours suivi de cette raison. `AGENTS.global.md` : une erreur qui nomme un paramètre est réessayée une fois, ce paramètre corrigé (jamais le même appel). README, FICHIERS, la carte (33 fonctions), les empreintes.
- **Retiré** : rien.
- **But** : une MR que le pilote crée, comme convenu ; et, quand il ne le peut vraiment pas, la raison sous les yeux du développeur et la preuve dans le journal, au lieu d'un lien à suivre sans savoir pourquoi.

## 2026-10-28 23:30 — Un « trop de requêtes » (429) attend ce que demande le serveur, pas une panne
- **Ajouté** : plugin, fonction 18 : un 429 (erreur `provider.rate-limit`) a son propre rythme. Avec un en-tête `Retry-After` (ou `retry-after-ms`), le prochain essai vient après l'attente que demande le serveur, qu'OpenCode suit déjà (lu dans le code de la v2.1.4 : `model-retry.ts`, au moins le délai du serveur, 15 minutes au plus), sans rien de plus. Sans lui : 3 s, 5 s, 10 s, 15 s, 20 s, puis 30 s, plus longues de 0 à 25 % au hasard, pour que les sous-agents refusés ensemble (les analyses de `/fortify`, une vague de `/fix`) ne redemandent pas au même instant ; 3 min 30 à 4 min en tout au lieu d'environ 8. Le titre dit « nouvel essai <n> dans <délai> (serveur du modèle : trop de requêtes) ». 4 contrôles de plus dans `tools/plugin-test.mjs` (871).
- **Changé** : rien pour une panne du serveur (5xx, délai, connexion) : toujours 10 s, 20 s, 30 s, 45 s, puis 1 min, environ 8 minutes. README, COMMANDES (« Le serveur du modèle », le tableau des nouveaux essais), MIGRATION, FICHIERS, la carte des flux (« Un échec »), la présentation (« Quand ça coince »), les empreintes.
- **Retiré** : l'attente de 10 s à 1 min que le plugin imposait aussi à un 429, même quand le serveur demandait 1 s.
- **But** : un run qui reprend dès que la passerelle le permet, au lieu d'attendre jusqu'à une minute ce qu'elle accordait en quelques secondes ; et des sous-agents qui ne se font plus refuser ensemble à chaque essai.

## 2026-10-27 11:55 — Une suite arrêtée faute de temps n'est plus prise pour des tests en échec
- **Ajouté** : `tools/dotnet-test.sh` vérifie qu'un run normal n'écrit jamais « Terminated » et qu'une suite arrêtée faute de temps ne dit jamais « TESTS: FAILED ».
- **Changé** : le chien de garde de `build-test.sh`, `test-guardian.sh`, `fetch.sh` et `ship.sh` dit lui-même qu'il a arrêté la commande (son code 124), au lieu que le script le devine par `kill -0` : un chien de garde qui vient de finir, pas encore récupéré par le shell, répond encore à `kill -0`, et l'arrêt passait pour un échec ordinaire (« TESTS: FAILED (exit 143) » au lieu de « TESTS: TIMEOUT »). Vu une fois dans la CI (bash), reproduit ici : 1 arrêt mal classé sur 30 sous bash avec la machine chargée, aucun avec la correction.
- **Retiré** : rien.
- **But** : une suite trop longue arrête `/go` avec la bonne raison et la marche à suivre ; avant, ses tests passaient pour cassés et un coder pouvait être envoyé « corriger » des tests justes. Un fetch ou un push sans réponse est dit comme tel.

## 2026-10-27 11:30 — Le plan relu par un œil neuf avant la première ligne de code
- **Ajouté** : dans `/go`, entre la fiche et le code, la relecture du plan par le `checker` à contexte neuf (nouvelle section « Review of a plan » de `agents/checker.md`) : il lit la fiche, le ticket et le code, jamais l'analyse, et ne rapporte que ce qui ferait échouer le coder, bâtir la mauvaise chose ou laisser passer une régression (une exigence du ticket sans critère, un test attendu sans valeurs, un choix laissé au coder, un fichier ou un membre qui n'existe pas, une étape qui s'appuie sur une suivante, un « test d'abord » ou un « filet d'abord » oublié, une migration ou une ligne de « ## Contrat » absente, une décision contredite), « bloquant » ou « majeur », jamais un style. L'analyste, dans sa session (nouvelle section « Review of your sheet » de `agents/analyst.md`), corrige chaque point, ou le rejette avec une preuve vérifiable écrite dans « ## Décisions » (« Relecture : … non retenu — <preuve> »), ou en fait une question bloquante ; un seul tour, consigné dans « ## Suivi ». `ticket-sheet.sh check --files` : chaque fichier d'une étape à faire est dans le dépôt, ou suivi de « (nouveau) » (l'analyste marque les fichiers qu'une étape crée). 6 contrôles de plus dans `tools/scripts-test.sh` (182), le contrôle de la fiche n'en avait aucun.
- **Changé** : `commands/go.md` étape 4 (2 : le contrôle ; 3 : la relecture et sa correction ; 4 : les questions, qui viennent de la dernière réponse de l'analyste ; 5 : « analyse seule », qui donne le plan relu) ; un `/go` arrêté pendant l'étape 4 (une suite trop longue, une base qui ne compile pas) puis relancé refait l'étape 4 sans nouvelle analyse (la mesure de la base si elle manque, le contrôle, la relecture, les questions sans réponse) au lieu de passer au code. `agents/pilot.md` : la description « Relecture du plan », la relecture dans les vérifications de la MR. Le `/go` de la 1.19, qui partage le dossier des scripts, garde `ticket-sheet.sh check` tel qu'il était. MIGRATION.md 5.4 : la liste des scripts vérifiée sur une copie de la 1.19 (`ticket-sheet.sh` plus récent, `transient.sh` qui manquait, 40 lignes). README, COMMANDES, FICHIERS, ANALYSE (les leçons d'architecture d'Anthropic, Cognition, Manus, OpenAI, Spotify, Cursor et du modèle « Elephant-Goldfish » de Google : ce qui est pris, ce qui ne l'est pas), la carte des flux (schéma et faits de `/go`), la présentation (« /go · 1. Préparer », « /go en un coup d'œil », une question des tech leads), les empreintes.
- **Retiré** : rien.
- **But** : une erreur du plan se paie à chaque étape, et celui qui a écrit le plan le relit avec ses propres hypothèses ; un relecteur qui ne les a jamais vues trouve ce qu'il a oublié, avant qu'une ligne soit écrite, et le mécanique (un chemin inventé) est vérifié sans le modèle.

## 2026-10-27 10:45 — Seuls les skills relus, deux skills de tests, un contexte qui ne sature pas, la présentation revue
- **Ajouté** : `skills/testability/SKILL.md` (rendre testable un code qui lit l'horloge, un fichier, le réseau ou l'environnement : le plus petit point d'injection selon la version de .NET, sans paquet, le comportement de production gardé, puis des tests déterministes) et `skills/test-quality/SKILL.md` (pour chaque test, la version fausse du code qu'il ferait échouer : l'accepté et le refusé, les bornes, la valeur exacte, les tests qui ne font que passer sur des lignes), adaptés des skills officiels `dotnet/skills` (licence MIT, leurs `NOTICE.md`) et réécrits pour les agents du pack : le coder, le test-guardian, le checker et l'analyste les chargent, le test-guardian nomme le point d'injection qui manque dans ses lignes « INSUFFISANT ». Plugin, fonction 32 : seuls les skills du dossier de skills d'OpenCode (ceux du pack, les patterns de l'équipe) et du dossier système ; ceux qu'OpenCode v2.1.4 charge d'office ailleurs (`~/.claude/skills`, `~/.agents/skills`, les dossiers `.claude`, `.agents`, `.opencode` du projet et de chaque dossier au-dessus, les URL) sont retirés, un homonyme d'un skill du pack compris. Plugin, fonction 13 : dans un run, les plus anciennes sorties des outils locaux (un fichier lu, une commande, une recherche) effacées des requêtes au-delà de 60 % de ce que prend le modèle (sa limite dans `opencode.json`), jusqu'à 35 %, jamais un skill, un rapport de sous-agent, une réponse, un appel MCP ni les 3 dernières, et effacées de même aux requêtes suivantes. ANALYSE.md : les articles d'Anthropic de 2026 sur les skills, le contexte et les harnais, ce qui s'applique au pack et ce qui ne se transpose pas.
- **Changé** : la `permission` globale ne permet plus que les skills du pack et `pattern-*` (`tools/permissions.py`, 3 156 cas simulés). Plugin, fonction 31 : les analysts de `/fortify` sans aucun outil MCP (ils écrivent la carte d'une faille depuis le code et les détails Fortify). `efcore` complété (dates comparées par intervalle, pagination par clé, filtres dynamiques sans constante, `IEnumerable` différé, limites d'`ExecuteUpdateAsync`, `SaveChanges` caché dans une boucle, une relecture qui apporte sa preuve). La présentation PowerPoint : 17 diapositives, sans le jargon (« pack », « suite », « filet », « base ») ; qui fait quoi ; le principe de non-régression et de preuve ; une journée type avec la note des 32 minutes de CI ; `/fortify` en tête, avec le déroulé dans le temps (ce qui tourne en même temps, ce qui passe un par un), une faille de la carte au commit et ce que ça change ; le travail sans ticket ; les questions des tech leads ; aucun nom du pack ni de l'outil qui l'a construite dans le fichier. Plugin 867 vérifications ; README (dont la mention restée de l'ancienne présentation HTML), FICHIERS, MIGRATION (les deux skills à créer, les comptes), COMMANDES, la carte des flux (le garde-fou des skills, le contexte qui ne sature pas, les tests qui prouvent, les chiffres), les listes d'empreintes.
- **Retiré** : rien.
- **But** : qu'un skill trouvé sur Internet ou apporté par un dépôt ne guide jamais un agent sans avoir été relu ; des tests qui échoueraient vraiment si le code était faux, et du code rendu testable sans paquet ; un `/go` ou un `/fortify` long qui garde un contexte léger au lieu d'attendre un résumé ; une présentation que les tech leads comprennent sans le vocabulaire du pack et qui répond à leurs questions.

## 2026-10-27 06:45 — La présentation des flux en PowerPoint
- **Ajouté** : `docs/presentation-flux.pptx`, les flux qu'on présente aux tech leads et aux chapter leads en 12 diapositives PowerPoint, des schémas faits de blocs, de losanges et de flèches PowerPoint, modifiables un à un : une journée avec le pack, `/go` en un coup d'œil puis en trois temps (préparer, une étape du plan, vérifier et livrer), le filet de test et la preuve, `/fix`, `/fortify`, `/tests` (avec `api` et `env`), ce qui est relancé tout seul, borné dans le temps ou jamais relancé, ce qu'il faut retenir. Quelques mots par bloc, le détail dans les notes de l'orateur ; la couleur d'un bloc dit ce qu'il est (un agent, toi, livré, un arrêt, relancé tout seul avec ses pauses, borné dans le temps), avec sa légende sur chaque schéma.
- **Changé** : `tools/carte-render.mjs` ne dessine et ne vérifie plus que la carte, comme avant la présentation en HTML (les couleurs des classes, la disposition en arbre des mindmaps et les identifiants tirés de l'empreinte de la source restent ; aucun schéma de la carte n'est redessiné). Le lien de la carte, README, COMMANDES, FICHIERS et le commentaire du workflow pointent vers le fichier PowerPoint ; un changement d'un des flux qu'il montre se reporte dans PowerPoint, avec la date de sa couverture.
- **Retiré** : `docs/presentation-flux.html` (22 diapositives HTML de mindmaps et de schémas Mermaid dessinés par script).
- **But** : une présentation qu'on montre et qu'on reprend dans PowerPoint, limitée aux flux qui comptent pour une équipe, avec ce qui repart tout seul et ce qui est borné dans le temps, plutôt qu'une page de schémas générés que personne ne peut retoucher.

## 2026-10-27 06:40 — Une source de paquets en HTTP, dite comme un problème de la machine
- **Ajouté** : `dotnet-problem.sh` reconnaît NU1302 (une source NuGet en HTTP, que le NuGet du SDK .NET 10 refuse avant toute connexion) : un `ENVIRONMENT PROBLEM` qui dit quoi faire (la source en HTTPS, ou `allowInsecureConnections`), jamais un nouvel essai, jamais `nuget.config` touché par un agent. Tests : son message dans `dotnet-test.sh` (459 contrôles) ; dans la CI, avec le vrai SDK, la même source en HTTP.
- **Changé** : le test réel du flux de paquets muet passe par une source en HTTPS (le vrai SDK 10.0.403 refusait la source en HTTP avant d'essayer de la joindre, NU1302 au lieu de NU1301 : c'est ce run de la CI qui l'a montré). README, MIGRATION, FICHIERS, la carte et la présentation (459).
- **Retiré** : rien.
- **But** : un Artifactory interne encore en HTTP fait échouer chaque restore dès le passage au SDK 10 ; l'agent l'aurait pris pour une erreur du code à corriger.

## 2026-10-27 06:20 — La présentation des flux, à côté de la carte
- **Ajouté** : `docs/presentation-flux.html`, les flux du pack en 22 diapositives faites seulement de schémas, pour les tech leads et les chapter leads : sept mindmaps (le pack, quelle commande, ce qui est relancé ou non, les bornes de temps, les droits des agents, ce qui est refusé, les limites connues), des flowcharts (`/go` en trois temps, le filet et la preuve, `/fix`, `/fortify`, `/tests`, `/tests env`, `/push` et `/sync`, `ship.sh`, le build et les tests, la CI du pack) et des séquences (une journée, le serveur du modèle qui flanche, deux tickets en parallèle) ; chaque nœud coloré selon ce qu'il est (un agent, toi, relancé tout seul, borné dans le temps, un arrêt, livré), une phrase par diapositive. Une diapositive à la fois dans un navigateur large, un document sur un téléphone, une page par schéma à l'impression. Dans la carte : la section « Ce qui est relancé tout seul » et sa mindmap, les nouveaux essais dans les schémas de `/go`, du front-end, des versions, de `/tests env` et des deux dossiers en parallèle, un lien vers la présentation.
- **Changé** : `tools/carte-render.mjs` dessine les deux pages et `--check` les vérifie toutes les deux ; les classes des nœuds et les branches des mindmaps (disposées en arbre, `layout: tidy-tree`) prennent leurs couleurs dans des variables de la page, la forme `rgb()` des couleurs comprise ; l'identifiant de chaque SVG vient de l'empreinte de sa source, plus de sa place (un schéma ajouté au milieu de la carte prenait l'identifiant, donc les styles, du suivant) ; tous les schémas de la carte redessinés. Les nombres de contrôles de la carte, FICHIERS, README, COMMANDES, le commentaire du workflow.
- **Retiré** : rien.
- **But** : montrer les flux à ceux qui ne liront pas la carte en entier, avec ce qui est relancé, borné ou arrêté visible d'un coup d'œil, et des schémas lisibles projetés (12 px au moins à 1600 × 900, souvent 14 à 20).

## 2026-10-27 01:10 — Ce qui passe tout seul est relancé tout seul
- **Ajouté** : `scripts/transient.sh`, qui décide pour les scripts si un échec mérite un nouvel essai après une pause : un build .NET dont toutes les erreurs sont le flux de paquets (NU1301, NU1900, jamais un 401 ou un 403) ou un fichier tenu par un autre processus (CS2012, MSB3021, MSB3027, MSB4166) ; une installation npm, yarn ou pnpm tombée sur le registre (ECONNRESET, ETIMEDOUT, 5xx) ou sur un dossier tenu (EBUSY) ; un fetch, un push ou une requête curl tombés sur le réseau (pas de réponse, connexion coupée, nom non résolu, 429, 5xx). Deux nouveaux essais au plus, seulement s'ils tiennent dans le temps de la commande, une ligne `RETRY:` à chacun. Et `transient.sh git`, qui attend 1, 2 puis 3 s qu'un autre git libère l'index (`index.lock`). `dotnet-problem.sh` nomme le processus qui tient un fichier du build, et MSB4166, une fois les essais passés. Tests : le classement sur les sorties réelles des outils, l'index tenu, un fetch et un push qui tombent sur le réseau, un push refusé par une branche qui a bougé, le flux de paquets et un fichier tenus, un registre qui coupe, un environnement qui redémarre (`/waking` du labo) ; dans la CI, le vrai NU1301 d'une source qui ne répond pas, avec les vrais .NET 10 et 8.
- **Changé** : `fetch.sh` (75 s pour tous ses essais, 45 s dans `workflow-state.sh`, qui ne relance jamais un fetch resté sans réponse), `ship.sh` (index, push relancé, branche qui a bougé pendant le push : ses commits ramenés par merge, `diff-guard.sh` refait, un nouveau push ; 270 s en tout ; un push refusé par un hook n'est plus pris pour une branche qui a bougé), `branch.sh`, `abandon.sh`, `build-test.sh`, `test-guardian.sh` (ses builds et ses mesures, maintenant bornés aussi dans `setup`), `front-test.sh` (l'installation relancée, bornée à 15 minutes comme les tests, et une borne même sans `timeout` ni `gtimeout` sur la machine), `env-tests.sh`. AGENTS.global.md : un appel MCP tombé sur un délai, un 429 ou un 5xx est rappelé une fois après `pause.sh 20`, une écriture seulement après avoir vérifié qu'elle n'a pas eu lieu (avant : jamais, sauf un délai). Le pilote reprend une fois dans sa session un sous-agent arrêté par le serveur du modèle, avant le debugger (`/go`, `/fix`). Fonction 18 du plugin : la patience face au serveur du modèle pour toute commande du pack (`/push`, `/sync`, `/daily`…), plus seulement pour le pilote. README, COMMANDES (« Ce qui est relancé tout seul »), FICHIERS, MIGRATION, empreintes ; les suites sans pause de retry (`RETRY_PAUSES`).
- **Retiré** : rien.
- **But** : qu'une coupure d'une seconde du VPN, un Artifactory ou un environnement qui redémarre, ou un `git status` de Rider au mauvais moment n'arrêtent plus un `/go` lancé sans toi, sans jamais relancer ce qui échouerait pareil ni un test pour le faire passer au vert.

## 2026-10-26 23:05 — Le contrôle après un correctif par script, les outils MCP du pilote par commande, les grosses suites bornées, le skill efcore
- **Ajouté** : `test-guardian.sh verify` : les contrôles de la phase « après » (scellé, preuve et filet verts deux fois, couverture après sans test qui passait et qui échoue ni fichier qui perd de la couverture, filet au minimum, chaque ligne de la méthode du problème), par script, sur ce que le scellé garde (`seal --problem`, la mesure `<label>-before`, le dernier filet) : `VERIFY: OK` ou `VERIFY: TEST-GUARDIAN (<raison>)`, jamais une ligne `STOP:`. Fonction 31 du plugin : le pilote ne reçoit que les outils MCP des serveurs de sa commande. Le budget de temps des scripts qui buildent et testent (`build-test.sh`, `test-guardian.sh`, `test-platform.sh` : 42 minutes attente du verrou comprise, 25 pour une exécution des tests) et les lignes `BUILD: TIMEOUT`, `TESTS: TIMEOUT` et `TIMEOUT:`. La ligne « Fortify batches in progress » de l'état git. La ligne « EF Core » de la détection. Le skill `efcore`. L'analyse « des sous-agents ou des skills ? » dans ANALYSE.md. Tests : `verify` et chacun de ses cas, les dépassements de temps, la fonction 31, les sorties de build hors du commit, les listes bornées, le menu de `/tests`, la ligne EF Core.
- **Changé** : `/go` (5.3, et un `TIMEOUT` de la mesure arrête avant la première ligne de code), `/fix` et `/fortify` : le contrôle après chaque correctif par `verify` d'abord, le test-guardian seulement quand ce n'est pas vert ; pilot, test-guardian, coder, analyst, checker, debugger, `/review`, `/push`, AGENTS.global.md, skill `pack-setup` (le filtre « Tests locaux » sur un `TIMEOUT`). Le pilote n'a plus Confluence. Le plugin donne 45 minutes à chaque script du pack qui se borne lui-même (20 aux commandes lancées directement). `ship.sh` laisse hors du commit les sorties de build et dépendances qu'un `.gitignore` oublie (`obj`, `bin/Debug`, `node_modules`…), avec une ligne `WARNING`. `workflow-state.sh` : listes bornées, fiches comptées. L'attente du verrou de build va jusqu'à 20 minutes. Le menu de `/tests` lit les noms des tests une seule fois. Microsoft.Testing.Platform : une exécution entière trop longue est un `TIMEOUT`, plus un test bloqué. README, COMMANDES, FICHIERS, MIGRATION, la carte des flux (5 schémas), `pack-map.sh`, empreintes.
- **Retiré** : la liste brute des fiches dans l'état git ; Confluence des outils du pilote.
- **But** : moins de tours de modèle sans rien retirer aux preuves, des requêtes du pilote plus courtes et un choix d'outil plus sûr, plus de commande coupée sans un mot ni de push arrêté à la fin d'un `/go` par un `obj/` commité, des faits courts sur les gros dépôts, et Entity Framework Core sans perte de données.

## 2026-10-26 22:08 — Remplacer AutoMapper par Mapperly ou Mapster, chaque profil traduit par un script
- **Ajouté** : `scripts/automapper.sh` : `inventory` (les paquets et la CVE, chaque profil dans l'ordre où le remplacer, ses maps et leurs options, les projets, les resolvers à services, les réglages globaux, les appels, l'enregistrement, les tests ; ce que `scaffold` laisse à la main pour chaque cible ; deux lignes TARGET, les faits du choix entre Mapperly et Mapster ; le plan), `setup [--mapster]` (Mapperly : à la compilation seulement, `Mapperly.globalconfig`, `MapperDefaults.cs` ; Mapster : `Mapster`, `Mapster.DependencyInjection`, `MapsterSetup.cs` avec les règles d'AutoMapper et `AddMapsterMaps`, refusé sans rien changer devant une `Microsoft.Extensions.DependencyInjection.Abstractions` antérieure à la 9.0.0 ; un build en échec remet tout), `scaffold [--mapster]` (chaque map traduite : le mapper de Mapperly avec BeforeMap, AfterMap et Condition autour de la méthode générée, `ApplyTo`, la projection ; ou le Register de Mapster, Condition en `IgnoreIf` pour laisser le membre tel quel comme AutoMapper ; ce qui reste à la main cité avec une ligne TODO), `helpers` et `record` (les tests instantanés et leurs fichiers de référence écrits depuis AutoMapper), `switch` (Mapster, la dernière étape : les `using`, `ProjectToType`, `AddMapsterMaps`, les configurations des tests ; `IMapper`, ses appels et ses mocks gardés), `check`. Les skills `automapper` (le choix de la cible, le filet, la cible Mapperly) et `mapster` (la cible Mapster). `tools/automapper-test.sh` et son job de CI : les deux cibles depuis le même filet, avec les vrais .NET 10 et 8 (152 contrôles).
- **Changé** : `/go` (la question « Cible » : Mapperly recommandé, Mapster, à la main ; un STOP de `setup` arrête avant la première étape), analyst, coder, test-guardian, checker, debugger, `/review`, AGENTS.global.md ; les permissions (`setup` au pilote, `helpers` et `record` au test-guardian, `scaffold` et `switch` au coder) ; `detect-project-type.sh` (Mapster), `package-licenses.sh`, `pack-map.sh` ; FICHIERS, README, COMMANDES, MIGRATION, la carte des flux ; le workflow (six jobs).
- **Retiré** : rien.
- **But** : retirer AutoMapper (payant depuis la 15.0, vulnérable avant) d'un grand projet avec ce que Qwen ne doit pas improviser fait par un script, la cible choisie sur les faits du dépôt, et la preuve que la nouvelle cible donne ce qu'AutoMapper donnait, membre par membre.

## 2026-10-26 15:58 — Blazorise 100 % natif, secrets des clients HTTP et Vault, moins de tokens, carte des flux dans le dépôt
- **Ajouté** : `scripts/blazor-native.sh` : `inventory` (chaque page qui utilise Blazorise, ses balises et leur famille dans l'ordre où les remplacer, les services, enregistrements, liens, paquets et clés de licence par leur nom seulement, l'équivalent natif de chaque balise), `scaffold` (les composants natifs de l'application, sans aucun paquet : `NativeGrid` et ses colonnes avec tri, pages et pager en français, données d'un serveur, ligne sélectionnée ; `NativeModal` ; `NativeDialogService` et `NativeDialogHost` pour les questions et messages ; `NativeToastService` et `NativeToastHost` ; `NativeFieldCssClassProvider`), `check` (ce qui reste, fichier et ligne, ou « BLAZORISE: GONE »). `scripts/secrets.sh` : les secrets d'un environnement lus dans une variable de la machine ou dans HashiCorp Vault (`vault:<chemin>#<champ>`), jamais affichés, avec une phrase claire pour chaque refus de Vault (pas connecté, refusé par la politique, rien à ce chemin, pas ce champ, scellé, injoignable, certificat inconnu). `env-setup.sh set --vault` et `--proxy-vault` ; `http-files.sh --private` remplit le fichier privé du client HTTP depuis `~/.zshenv` ou Vault (FILLED, EMPTY, jamais une valeur). Fonction 30 du plugin : les parties d'AGENTS.global.md utiles à la seule conversation ne partent plus aux agents du pack. `docs/carte-des-flux.html`, la carte des flux du pack, ses schémas dessinés dans la page par `tools/carte-render.mjs` ; ce fichier et `tools/release-notes.sh`. Tests : `dotnet-test.sh` (inventaire, composants, contrôle), `blazor-native-test.sh` (la page en `NativeGrid` et treize tests bUnit des composants, avec les vrais .NET 10 et 8), un vrai Vault dans `oidc-real-test.sh`, un Vault simulé et les fichiers privés dans `environments-test.sh`, le contrôle avant push dans `scripts-test.sh`.
- **Changé** : skill `blazorise` réécrit autour de `blazor-native.sh` (plus court d'un quart) ; analyst, coder et checker l'appellent pour le plan, la première et la dernière étape. Visual Studio lit son fichier privé `http-client.env.json.user` (et non celui de Rider) et n'a pas de gestionnaire de réponse ; skill `pack-http` et `/tests env config` avec la question « Secret ». `/fix` attend la CI par pauses de 4 minutes en ne relisant que le statut du pipeline (8 tours au plus au lieu de 18) et lit la fin du journal d'un job en échec ; `/daily` et `/go` demandent à Jira les seuls champs utiles ; `pause.sh` jusqu'à 290 s, que le plugin laisse durer 6 minutes. `diff-guard.sh` refuse les fichiers privés des clients HTTP ; `test-guardian.sh` reconnaît aussi les erreurs de Razor, de NuGet et du SDK quand des tests ne buildent pas. Permissions : ces fichiers jamais lus, les coffres de secrets (`vault`, `op`, `bw`, `az keyvault`, `aws secretsmanager`, `gcloud secrets`, `kubectl get secret`) refusés aux agents, `blazor-native.sh scaffold` au coder seul, les procédures `pack-*` cachées aux sous-agents. README, COMMANDES, FICHIERS, MIGRATION, empreintes.
- **Retiré** : QuickGrid et le pager `FrenchPager` du remplacement de Blazorise (plus aucun paquet) ; l'attente de `/fix` qui relisait les jobs du pipeline toutes les 100 s.
- **But** : retirer Blazorise sans paquet ni licence, avec ce que Qwen ne sait pas faire seul fait par des scripts ; garder les secrets hors du modèle et du dépôt, Vault compris ; moins de tokens par requête et moins de tours d'attente ; une carte des flux à jour, lisible dans tous les navigateurs, hors ligne ; tracer chaque changement du pack.

## 2026-10-26 06:10 — Un flux muet, près d'une heure figée (`00d8b93`)
- **Ajouté** : rien.
- **Changé** : ANALYSE.md : un flux muet est réessayé 3 fois au plus, soit près d'une heure figée.
- **Retiré** : rien.
- **But** : une analyse exacte de ce qui bloque un run.

## 2026-10-26 05:53 — Docs : 2 587 cas de permissions (`677b0f0`)
- **Ajouté** : `pack-vitesse` dans l'inventaire des nouveaux dossiers de MIGRATION.md.
- **Changé** : les nombres de cas de permissions (2 587, dont 219 commandes prescrites) dans la documentation.
- **Retiré** : rien.
- **But** : une documentation qui dit ce qui est vérifié.

## 2026-10-26 05:41 — Aucune attente sans fin, options des agents envoyées, runs chronométrés (`43f8c84`)
- **Ajouté** : fonctions 27 (un serveur MCP sans limite propre coupé après 5 min au lieu de 12 h), 28 (la température, le top_p et les options de chaque agent envoyés au modèle), 29 (chaque run chronométré dans `openrd-pack-runs.tsv`, jamais le texte des demandes) ; `/outil vitesse` (`vitesse.sh`, skill `pack-vitesse`) ; `/go` seul propose les tickets du sprint ; « sans question » dans `/go`, `/fix` et `/fortify` ; `/fix` attend la fin de la CI (`pause.sh`).
- **Changé** : fonction 8 : une commande d'un agent du pack n'est jamais sans limite (20 min, 2 h au plus) ; l'analyste ne planifie que ce qui reste sur une branche commencée ; un test en échec est relancé une fois avant tout correctif. ANALYSE.md (v2.1.3 et v2.1.4), MIGRATION, README, COMMANDES, FICHIERS, empreintes.
- **Retiré** : rien.
- **But** : plus de run figé pendant des heures, des réglages de modèle réellement appliqués, savoir où passe le temps.

## 2026-10-25 19:05 — Le vrai Keycloak accepte 299 s comme 300 s (`c13554a`)
- **Ajouté** : rien.
- **Changé** : `oidc-real-test.sh` accepte une durée de jeton de 299 s (Keycloak la calcule au moment où il répond).
- **Retiré** : rien.
- **But** : un test réel stable.

## 2026-10-25 18:58 — pack-map.sh passe shellcheck (`7168932`)
- **Ajouté** : rien.
- **Changé** : `pack-map.sh` et son test : entités HTML pour les apostrophes, aucune variable inutilisée.
- **Retiré** : rien.
- **But** : des scripts propres au niveau warning de shellcheck.

## 2026-10-25 18:46 — Docs : les 43 contrôles de l'histoire Blazor (`985ff3b`)
- **Ajouté** : rien.
- **Changé** : la documentation dit que les 43 contrôles couvrent .NET 10 et 8 ensemble.
- **Retiré** : rien.
- **But** : des chiffres exacts.

## 2026-10-25 18:44 — `/outil carte`, la carte des flux générée depuis le pack (`0af5546`)
- **Ajouté** : `scripts/pack-map.sh` et le skill `pack-carte` : `/outil carte` écrit la carte des flux du pack installé en une page en français ; `/outil carte docs` l'écrit dans le dépôt.
- **Changé** : `package-licenses.sh` propose le Razor natif comme première alternative gratuite à Blazorise ; `setup --components` au pilote seul (2 582 cas) ; `scripts-test.sh` (95 contrôles) ; FICHIERS, COMMANDES, README, MIGRATION.
- **Retiré** : rien.
- **But** : montrer le pack à qui ne l'a jamais utilisé, toujours à jour.

## 2026-10-25 15:08 — Les tests de page libèrent bUnit en asynchrone (`01c90a6`)
- **Ajouté** : la question « Composants » de `/go` et `/tests`, puis `test-guardian.sh setup --components`.
- **Changé** : les tests du skill construisent leur contexte par une aide et le libèrent avec `await using` (Blazorise ne se libère qu'en asynchrone) ; `net` dit « not measured » pour un balisage que coverlet ne mesure pas.
- **Retiré** : rien.
- **But** : des tests de page qui passent pour de vrai.

## 2026-10-25 15:00 — Les composants Razor sous filet bUnit, le skill blazorise (`f938391`)
- **Ajouté** : `tools/blazor-native-test.sh` (l'histoire pour de vrai, .NET 10 et 8) ; `deps`, `net` et `changes` d'une page `.razor` ; `setup --components`.
- **Changé** : skill `blazorise` : renommages de la 2.0, inventaire, tests de ce que voient les utilisateurs, équivalents, page en Razor natif ; `fortify.sh prereq --tests` dit quel projet a bUnit.
- **Retiré** : rien.
- **But** : remplacer Blazorise page par page sans régression.

## 2026-10-25 13:30 — Docs des assistants de `/tests env` (`8a2c007`)
- **Ajouté** : rien.
- **Changé** : la documentation des assistants telle qu'ils se comportent ; ce que couvrent les vrais SDK.
- **Retiré** : rien.
- **But** : une documentation fidèle.

## 2026-10-25 13:28 — environments-test, shellcheck lit les appels de truth (`0f2cc28`)
- **Ajouté** : une directive shellcheck.
- **Changé** : rien d'autre.
- **Retiré** : rien.
- **But** : shellcheck propre.

## 2026-10-25 13:23 — `/tests env config` : des questions plus claires (`ff969f4`)
- **Ajouté** : des lignes NOTE de ce qui a vraiment tourné dans le laboratoire réel.
- **Changé** : l'accès recommandé est celui de l'environnement modifié, sinon OIDC ; `--proxy-auth` seulement avec une URL de proxy saisie ; empreintes.
- **Retiré** : rien.
- **But** : moins d'erreurs de saisie dans l'assistant.

## 2026-10-25 13:21 — `/tests env` ne s'arrête plus sur des variables vues au démarrage (`6b77e1e`)
- **Ajouté** : `tests.sh` dit d'où vient la présence des variables.
- **Changé** : l'assistant lance `env-tests.sh` même quand les faits disent qu'une variable manque (chaque commande relit `~/.zshenv`) ; empreintes et lignes attendues de MIGRATION.md.
- **Retiré** : rien.
- **But** : plus d'arrêt à tort.

## 2026-10-25 13:17 — Docs des assistants, des environnements et du laboratoire réel (`cf95cc6`)
- **Ajouté** : cartes mentales du pack dans le README ; chaque constat de shellcheck devient une annotation de la CI.
- **Changé** : COMMANDES (`/tests`, `/tests api`, `/tests env config`, `/outil http`, `/outil liens`, `/outil planifier`), FICHIERS, MIGRATION, AGENTS.global.md (routage), AGENTS.repo-template.md.
- **Retiré** : rien.
- **But** : documenter les nouveaux flux.

## 2026-10-25 13:04 — Un vrai laboratoire OIDC et proxy dans la CI (`a5b7d69`)
- **Ajouté** : `tools/oidc-real-test.sh` : Keycloak, squid avec identifiants, une autorité de certification interne, SQL Server et une API derrière le proxy, avec les vrais .NET 10 et 8.
- **Changé** : skill `api-tests` (une factory par projet, le gestionnaire de chaque schéma remplacé) ; `env-tests.sh` (503 de squid, `unauthorized_client`, identifiants masqués) ; `env-setup.sh` (la raison d'une URL de jeton introuvable).
- **Retiré** : rien.
- **But** : prouver les environnements en situation réelle.

## 2026-10-25 09:22 — OIDC, proxy et certificats pour les tests d'environnement ; assistants (`174bb5c`)
- **Ajouté** : `api-preflight.sh`, `env-setup.sh`, `related-setup.sh`, `tests.sh`, skill `pack-liens`, `tools/environments-test.sh` et `tools/oidc-proxy-lab.mjs` ; les assistants de `/tests`, `/outil liens`, `/outil http`, `/outil planifier`.
- **Changé** : `env-tests.sh` et `environments.sh` : client credentials OIDC, proxy, certificats internes.
- **Retiré** : rien.
- **But** : tester un environnement réel derrière le proxy de l'entreprise.

## 2026-10-25 00:23 — Tests d'API, tests d'environnement, commandes planifiées, fichiers .http (`509e711`)
- **Ajouté** : `/tests api` (skill `api-tests`, `setup --integration`), `/tests env` (`env-tests.sh`, `environments.sh`), `/outil planifier` (`schedule.sh`, fonction 26), `/outil http` (`http-files.sh`, skill `pack-http`).
- **Changé** : `test-platform.sh` (catégories xUnit v3), `test-lint.sh`, permissions (2 493 cas), docs.
- **Retiré** : rien.
- **But** : tester une API en mémoire et un environnement déployé, sans secret dans le code.

## 2026-10-24 23:12 — Dépendances laissées au développeur, npm qui échoue de lui-même, skill blazorise (`f4c7ab4`)
- **Ajouté** : fonction 25 (un changement de dépendances par un agent refusé en une phrase) ; skill `blazorise`.
- **Changé** : `npm install` retiré au coder et au test-guardian ; formes .NET 10 « nom d'abord » permises ; `front-test.sh` reconnaît npm qui échoue de lui-même ; `frontend-test --real`.
- **Retiré** : `npm install` des permissions du coder et du test-guardian.
- **But** : jamais de lockfile réécrit ni de paquet payant ajouté au passage.

## 2026-10-24 19:14 — La liste réelle des SDK, où que l'hôte l'affiche (`cafab29`)
- **Ajouté** : rien.
- **Changé** : `dotnet-problem.sh` lit la liste des SDK après le message de l'hôte .NET 10 ; `detect-project-type.sh` ; `frontend-test.sh --real` sans interaction ; docs.
- **Retiré** : rien.
- **But** : un diagnostic exact de la machine.

## 2026-10-24 19:04 — Front-end, .NET 8 à 10, librairies et dépôts liés ; des tests qui prouvent (`2c1885d`)
- **Ajouté** : `front-test.sh`, `front-info.sh`, `dotnet-problem.sh`, `dotnet-targets.sh`, `api-surface.sh`, `related-repos.sh`, `test-lint.sh`, fonction 24 (commandes sans fin refusées), `tools/frontend-test.sh`, `tools/fake-npm.sh`, `tools/real-dotnet-test.sh`.
- **Changé** : `build-test.sh <dossier>` et `--pack` ; `/review` lit les contrats ; `diff-guard.sh` arrête `node_modules`, `obj`, `bin/Debug`.
- **Retiré** : rien.
- **But** : chaque type de projet de l'équipe, sans mode watch ni version devinée.

## 2026-10-24 14:20 — Les tests qui ont tourné sont OK à côté d'un projet vide (`ba1a726`)
- **Ajouté** : rien.
- **Changé** : `build-test.sh` compte les tests de chaque assemblage ; `fake-dotnet.sh` comme coverlet sur un projet vide ; scénarios exacts ; docs et empreintes.
- **Retiré** : rien.
- **But** : plus de « TESTS: NONE RUN » à tort.

## 2026-10-24 14:00 — Un filet même sans tests unitaires, chaque proposition un QCM (`addd2b9`)
- **Ajouté** : la mise en place des tests demandée avec les questions du début, premier commit de la branche.
- **Changé** : une étape « (filet d'abord) » dans tout projet .NET ; `test-guardian.sh` sur un projet sans test ; `pack-audit` propose « /go sans ticket » ; `pack-setup`.
- **Retiré** : `/outil pattern apply`.
- **But** : protéger le code existant même dans un dépôt sans tests.

## 2026-10-24 13:38 — Le filet vérifié à la ligne près contre le vrai coverlet (`8c85c24`)
- **Ajouté** : `validate.js` vérifie les numéros de ligne que MIGRATION.md donne.
- **Changé** : les chiffres des filets exacts dans les deux modes ; le QCM « Suite » libère le dossier seulement pour les commandes qui le tiennent.
- **Retiré** : rien.
- **But** : des preuves de couverture exactes.

## 2026-10-24 13:18 — Un filet avant chaque correctif, la suite en un clic (`0e2ab47`)
- **Ajouté** : `test-guardian.sh net` (la couverture des méthodes touchées, OK ou THIN) ; la mission « filet » ; le QCM « Suite » à la fin de chaque commande.
- **Changé** : le test-guardian mesure le filet avant chaque correctif et écrit d'abord les tests du comportement actuel ; le plugin libère le dossier pendant le « Suite ».
- **Retiré** : rien.
- **But** : jamais de régression silencieuse.

## 2026-10-24 09:22 — De vraies solutions dans les scénarios (`5175c68`)
- **Ajouté** : rien.
- **Changé** : `scenarios-test` écrit les projets d'une seule liste ; `build-test.sh` dit pourquoi aucun test n'a tourné.
- **Retiré** : rien.
- **But** : comprendre un « NONE RUN ».

## 2026-10-24 09:04 — Corrections de CI, les journées avec le vrai dotnet (`b654c66`)
- **Ajouté** : `scenarios-test --real`.
- **Changé** : `plugin-test` dans un faux dossier personnel ; journaux de la CI hors du pack.
- **Retiré** : rien.
- **But** : une CI fiable.

## 2026-10-24 08:57 — Simulations de bout en bout, `/fortify` de A à Z, vrai dotnet dans la CI (`7fcb171`)
- **Ajouté** : `tools/scenarios-test.sh`, `tools/fortify-test.sh`, `scripts/abandon.sh`, FICHIERS.md, `.github/workflows/opencode-v2.yml`.
- **Changé** : `fetch.sh` relancé quand deux espaces de travail se croisent ; `/push` builde avant sa question ; preuve vide d'une faille non démontrable ; `branch.sh`.
- **Retiré** : rien.
- **But** : vérifier les journées réelles d'un développeur.

## 2026-10-24 01:42 — `/push` propose ses choix, `/tests` sans ticket (`4d17f8c`)
- **Ajouté** : la commande `/tests` ; `build-test.sh --if-changed`.
- **Changé** : `/push` pose une seule question (branche, message, MR) ; `/fix` sans ticket ; awk, du et xargs grep permis pour lire.
- **Retiré** : rien.
- **But** : travailler hors ticket avec les mêmes règles.

## 2026-10-24 00:36 — Boucles de réflexion coupées, travail hors ticket, plateforme de test .NET 10 (`958c644`)
- **Ajouté** : fonctions 21 (boucles coupées), 22 (« continue »), 23 (`dotnet run` limité) ; `/push`, `/sync`, `base.sh`, `test-platform.sh`, AGENTS.repo-template.md, `tools/dotnet-test.sh`, `tools/fake-dotnet.sh`, `tools/scripts-test.sh`.
- **Changé** : `build-test.sh` et `test-guardian.sh` sur Microsoft.Testing.Platform ; `package-refs.sh --doc`.
- **Retiré** : rien.
- **But** : plus d'heure perdue dans une boucle, .NET 10 pris en charge.

## 2026-10-23 04:44 — HTTP 400 à chaque tour d'outil corrigé (`c296718`)
- **Ajouté** : rien.
- **Changé** : le plugin envoie `""` au lieu de `null` pour un message fait d'appels d'outils ; les valeurs réelles de la machine retirées des docs.
- **Retiré** : les noms réels d'utilisateur, de machine et de ports dans la documentation.
- **But** : des commandes qui marchent derrière la passerelle de la plateforme.

## 2026-10-23 01:04 — `/fortify` met en place les tests, preuves en parallèle (`3fabf7c`)
- **Ajouté** : `test-guardian.sh setup` et `build` ; les vagues de trois test-guardians.
- **Changé** : redirections inoffensives retirées avant la vérification des permissions ; `build-test.sh` arrête un test bloqué.
- **Retiré** : la réautorisation de toute commande contenant `2>&1`.
- **But** : `/fortify` sans blocage, une faille de permissions fermée.

## 2026-10-22 20:03 — OpenCode 2.1.3, des runs qui reprennent seuls, des preuves scellées (`81a1a3f`)
- **Ajouté** : `scripts/test-guardian.sh` (deps, coverage, compare, red, green, changes, seal) ; les reprises automatiques.
- **Changé** : `/fortify` analyse trois failles à la fois ; `/go` et `/fix` ont le test-guardian.
- **Retiré** : rien.
- **But** : des runs qui vont au bout, des preuves inaltérables.

## 2026-10-22 14:42 — Les garde-fous de la 1.19 portés en v2.1.2 (`163b87c`)
- **Ajouté** : l'attente des serveurs MCP, le verrou du dossier en fichier, le journal du plugin.
- **Changé** : les titres, la question qui lance une commande, le nettoyage des sorties anciennes ; partage, mise à jour et recherche web coupés.
- **Retiré** : le mode code et les outils de session et d'espace de travail de la v2.
- **But** : retrouver en v2 la sécurité de la 1.19.

## 2026-10-22 07:57 — Annexe A : la v2 installée à la place de la 1.19 (`2502014`)
- **Ajouté** : le chemin complet d'une v2 installée sur place, l'interface web par `opencode-web.sh`.
- **Changé** : MIGRATION.md et COMMANDES.md.
- **Retiré** : rien.
- **But** : une migration sans surprise.

## 2026-10-22 05:18 — Annexe A, mot de passe hors de `~/.zshenv` (`01ebea7`)
- **Ajouté** : rien.
- **Changé** : la v2 lancée en service, son mot de passe ailleurs que dans `~/.zshenv`.
- **Retiré** : rien.
- **But** : un secret de moins lisible.

## 2026-10-22 05:06 — Annexe pour une v2 installée sur place, paquet du provider (`7cec473`)
- **Ajouté** : l'annexe A ; `npm` et `enabled_providers` dans chaque provider.
- **Changé** : COMMANDES.md.
- **Retiré** : rien.
- **But** : jamais de repli silencieux sur le modèle gratuit d'opencode.ai.

## 2026-10-22 03:40 — Migration sans script, garde-fous v2 des questions (`ad1a662`)
- **Ajouté** : CHECKSUMS-config.txt et CHECKSUMS-scripts.txt.
- **Changé** : MIGRATION.md sans aucun script lancé à la main ; isolation par `OPENCODE_CONFIG_DIR` ; le plugin ne donne plus le mot de passe du serveur aux commandes.
- **Retiré** : `tools/prepare-v2.mjs` et `tools/start-v2.sh`.
- **But** : une migration vérifiable par empreintes.

## 2026-10-21 21:34 — Un guide de migration pas à pas (`8fc0ab0`)
- **Ajouté** : `tools/prepare-v2.mjs`, `tools/start-v2.sh`.
- **Changé** : MIGRATION.md réécrit pas à pas.
- **Retiré** : rien.
- **But** : une migration accessible.

## 2026-10-21 19:27 — Rien à télécharger hors du guide (`8663dab`)
- **Ajouté** : rien.
- **Changé** : MIGRATION.md : les deux versions côte à côte, un retour arrière exact.
- **Retiré** : rien.
- **But** : pouvoir revenir à la 1.19.

## 2026-10-21 19:16 — `fortify.sh batch` crée son dossier d'abord (`4694c0c`)
- **Ajouté** : rien.
- **Changé** : le dossier du lot est créé avant les fiches.
- **Retiré** : rien.
- **But** : corriger un échec du premier lot.

## 2026-10-21 19:15 — `/fortify` avec un agent test-guardian (`9e67b51`)
- **Ajouté** : `agents/test-guardian.md`, `scripts/fortify.sh`.
- **Changé** : `/fortify` : une fiche par faille, preuve avant puis après ; un pilote par dossier.
- **Retiré** : rien.
- **But** : chaque correctif de faille prouvé.

## 2026-10-21 17:04 — Le pack migré vers OpenCode v2 (`b28c1fc`)
- **Ajouté** : le pack complet pour OpenCode v2 : plugin, agents, commandes (dont `/fortify`), scripts, skills, outils de vérification, guide de migration.
- **Changé** : les garde-fous de la 1.19 derrière un adaptateur v2.
- **Retiré** : rien.
- **But** : passer à OpenCode v2 sans perdre de sécurité.

## 2026-10-21 16:14 — Ce que le passage à OpenCode v2 change (`2c76de3`)
- **Ajouté** : README.md (l'analyse, vérifiée sur la v2.1.2).
- **Changé** : rien.
- **Retiré** : rien.
- **But** : décider de la migration en connaissance de cause.
