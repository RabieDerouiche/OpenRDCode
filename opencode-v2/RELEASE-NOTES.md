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

## 2026-10-26 14:30 — Blazorise 100 % natif, secrets des clients HTTP et Vault, moins de tokens, carte des flux dans le dépôt
- **Ajouté** : `scripts/blazor-native.sh` : `inventory` (chaque page qui utilise Blazorise, ses balises et leur famille dans l'ordre où les remplacer, les services, enregistrements, liens, paquets et clés de licence par leur nom seulement, l'équivalent natif de chaque balise), `scaffold` (les composants natifs de l'application, sans aucun paquet : `NativeGrid` et ses colonnes avec tri, pages et pager en français, données d'un serveur, ligne sélectionnée ; `NativeModal` ; `NativeDialogService` et `NativeDialogHost` pour les questions et messages ; `NativeToastService` et `NativeToastHost` ; `NativeFieldCssClassProvider`), `check` (ce qui reste, fichier et ligne, ou « BLAZORISE: GONE »). `scripts/secrets.sh` : les secrets d'un environnement lus dans une variable de la machine ou dans HashiCorp Vault (`vault:<chemin>#<champ>`), jamais affichés, avec une phrase claire pour chaque refus de Vault. `env-setup.sh set --vault` et `--proxy-vault` ; `http-files.sh --private` remplit le fichier privé du client HTTP depuis `~/.zshenv` ou Vault (FILLED, EMPTY, jamais une valeur). Fonction 30 du plugin : les parties d'AGENTS.global.md utiles à la seule conversation ne partent plus aux agents du pack. `docs/carte-des-flux.html`, la carte des flux du pack, ses schémas dessinés dans la page par `tools/carte-render.mjs` ; ce fichier et `tools/release-notes.sh`. Tests : `dotnet-test.sh` (inventaire, composants, contrôle), `blazor-native-test.sh` (la page en `NativeGrid` et treize tests bUnit des composants, avec les vrais .NET 10 et 8), un vrai Vault dans `oidc-real-test.sh`, un Vault simulé et les fichiers privés dans `environments-test.sh`, le contrôle avant push dans `scripts-test.sh`.
- **Changé** : skill `blazorise` réécrit autour de `blazor-native.sh` (plus court d'un quart) ; analyst, coder et checker l'appellent pour le plan, la première et la dernière étape. Visual Studio lit son fichier privé `http-client.env.json.user` (et non celui de Rider) et n'a pas de gestionnaire de réponse ; skill `pack-http` et `/tests env config` avec la question « Secret ». `/fix` attend la CI par pauses de 4 minutes en ne relisant que le statut du pipeline (8 tours au plus au lieu de 18) et lit la fin du journal d'un job en échec ; `/daily` et `/go` demandent à Jira les seuls champs utiles ; `pause.sh` jusqu'à 290 s, que le plugin laisse durer 6 minutes. `diff-guard.sh` refuse les fichiers privés des clients HTTP. Permissions : ces fichiers jamais lus, les coffres de secrets (`vault`, `op`, `bw`, `az keyvault`, `aws secretsmanager`, `gcloud secrets`, `kubectl get secret`) refusés aux agents, `blazor-native.sh scaffold` au coder seul, les procédures `pack-*` cachées aux sous-agents. README, COMMANDES, FICHIERS, MIGRATION, empreintes.
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
