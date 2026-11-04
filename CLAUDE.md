# Passation entre sessions (pack OpenCode v2)

Ce fichier est chargé au début de chaque session Claude Code. Il dit le cadre de travail, l'état au 4 novembre 2026 (fin de matinée) et ce qui reste à faire. Mets-le à jour à la fin d'une session qui change l'un de ces points.

## Le cadre (consignes durables de l'utilisateur)

- **Où travailler** : uniquement dans `opencode-v2/`, le pack pour OpenCode v2. La racine (`agents/`, `commands/`, `scripts/`… et `v2/`) est l'ancien pack 1.19 : n'y touche pas. Seules exceptions : ce fichier et `.claude/handoff/`.
- **Langue** : réponds en français. Les commits, les procédures et les scripts du pack sont en anglais ; les docs du pack (README, FICHIERS, COMMANDES, MIGRATION, RELEASE-NOTES) sont en français.
- **Style de réponse** : les préférences du compte s'appliquent. En bref :
  - la première phrase remet en cause une hypothèse ou montre un manque, jamais d'accord d'entrée ;
  - chaque affirmation porte (certain), (Likely) ou (guessing) ;
  - la vérité désagréable vient en premier, sans paragraphe d'échauffement ;
  - un désaccord se dit en structure (raison, alternative, risque) ;
  - on ne cède pas à une relance sans information nouvelle.
- **Priorités** : 1) la qualité, 2) la vitesse, 3) la fluidité.
- **Branche** : celle que la session désigne. Les dernières sessions travaillaient sur `claude/opencode-flux-optimization-ayqbgr`.
- **Merge** : autorisation durable de faire avancer `main` en fast-forward, par `git push origin <sha>:main`, jamais de force. Seulement quand la CI GitHub du commit (workflow `opencode-v2`) est verte et que les suites locales passent. Une PR n'est créée que si l'utilisateur la demande.
- **COMMANDES.md** :
  - Le bloc qu'on est en train de déboguer va **tout en haut**, sous `## En cours : …`.
  - Il est poussé **directement sur `main`**, tout de suite : « sinon ça sert à rien ». Un commit à part, avec seulement COMMANDES.md et son entrée de RELEASE-NOTES, peut partir sur `main` sans attendre la CI.
  - Quand c'est résolu, retire le bloc.
- **Commits** :
  - Titre `opencode-v2: …` en anglais, un corps qui explique.
  - Les lignes d'attribution que donne la session (`Co-Authored-By` et `Claude-Session`).
  - Aucun identifiant de modèle ailleurs.
- **Chaque commit qui change `opencode-v2/`** :
  - Il a son entrée dans `opencode-v2/RELEASE-NOTES.md` : la plus récente en haut, date et heure croissantes, avec les lignes Ajouté, Changé, Retiré et But. Vérifier avec `sh tools/release-notes.sh check`.
  - Tenir à jour en même temps :
    - les md concernés : README, FICHIERS (chaque fichier y est décrit, compteurs de contrôles compris), COMMANDES, MIGRATION ;
    - `docs/carte-des-flux.html`, puis `node tools/carte-render.mjs` ;
    - les présentations ;
    - les empreintes `CHECKSUMS-config.txt` et `CHECKSUMS-scripts.txt`, avec la commande du README, section « Pour la maintenance du pack ».
- **Sécurité** :
  - On ne récupère pas de skills n'importe où.
  - On ne publie jamais de secret.
  - Une commande de diagnostic n'affiche jamais la valeur d'un jeton.
  - Les présentations ne nomment ni OpenRDCode, ni le pack, ni un générateur, et doivent avoir l'air faites à la main : pas d'emoji, pas de légende répétée.
- **Modèles** : on écrit « Qwen 3.8 ou GLM 5.3 », servis par la plateforme IA interne.

## L'installation de l'utilisateur

- Sa v2 a **remplacé** l'ancien OpenCode. Les chemins à utiliser dans toute commande donnée à l'utilisateur, jamais de `~/oc2/…` :
  - la configuration : `~/.config/opencode` (`/home/coder/.config/opencode`) ;
  - les journaux : `~/.local/share/opencode/log/` ;
  - le journal du plugin : `~/.local/share/opencode/log/openrd-pack.log` ;
  - les empreintes : `~/CHECKSUMS-config.txt`.

  Pour redémarrer : `opencode service restart`.
- **Mise à jour** : il colle les fichiers depuis GitHub (vue Raw), puis vérifie avec `cd ~/.config/opencode && sha256sum --strict -c ~/CHECKSUMS-config.txt 2>/dev/null | grep -v ': OK$'`. Chaque fichier `FAILED` est à recoller.
- **Serveur MCP interne `itg-devops`** :
  - distant, environ 81 outils ;
  - les jetons passent en en-têtes `{env:PAT_TOKEN}`, `{env:TOKEN_CONFLUENCE}`, `{env:GITLAB_WORKFLOW_TOKEN}`, `{env:TOKEN_SONARQUBE}`, `{env:TOKEN_FORTIFY}`, lus dans l'environnement du serveur OpenCode (vide si la variable manque) ;
  - les outils s'appellent `itg-devops_<outil>`, par exemple `itg-devops_create_gitlab_merge_request`, `itg-devops_transition_jira_issue`, `itg-devops_log_jira_work`.
- **DevX Studio Next Gen** : le poste de dev distant de l'équipe. Un pod par développeur, un bureau Linux par XPRA, des outils à la carte (VS Code, Docker), sur IBM ROKS OpenShift. OpenCode y tourne en service.

## Ce qui est fait (les derniers jours)

- **Création de MR par `/go`** (1da1985) : **résolu, confirmé par l'utilisateur**. La règle de permission `*create*` cachait au pilote l'outil `itg-devops_create_gitlab_merge_request`. Les corrections :
  - la liste `MR_CREATE` de `tools/permissions.py` ;
  - la fonction 33 du plugin, qui détecte l'outil de MR par nom ;
  - le rappel quand `ship.sh` affiche `MR LINK: …merge_requests/new…`.
- **Présentation aux tech leads** (`opencode-v2/docs/presentation-tech-leads.pptx`, 90cb8bd) : 14 diapositives qui racontent une journée.
  - Le déroulé : Titre → L'agentique en deux phrases → DevX Studio Next Gen → Pourquoi on l'a fait → Notre équipe d'agents → Le grand schéma → « Une journée avec nos agents » → `/daily` → `/go` → `/go` : la preuve avant le code → `/fix` → `/fortify` → Et quand ça coince ? → Questions ?
  - L'utilisateur la présentait le 3 novembre.
- **Loggers de tests de la CI** (79f22e3, sur `main`). Le problème : un projet de tests créé par `test-guardian.sh setup` (le filet bUnit d'un retrait de Blazorise dans un dépôt sans tests) n'avait pas `JunitXml.TestLogger`. La CI de l'utilisateur, `dotnet test --logger junit`, s'arrêtait alors sur « Could not find a test logger … 'junit' ». Les corrections :
  - `setup` donne maintenant ces loggers à un nouveau projet : ceux des autres projets de tests, sinon ceux qu'un fichier de CI nomme, en version 6.1.0 par défaut ;
  - `setup --loggers` les ajoute là où ils manquent ;
  - `/fix` lance `setup --loggers` sur ce message, et `AGENTS.global.md` interdit les projets sondes (l'agent avait créé un dossier `.junit-probe`).

- **Jamais de sonde** (464e6af, e07c204, sur `main`) : après `.junit-probe`, un `/fix` avait ajouté un test « ProbeTest » pour vérifier le logger JUnit (probablement traité comme un bug à prouver). Les corrections :
  - `/fix` : l'échec du logger est de la configuration, jamais un bug (ni preuve, ni filet, ni test-guardian, ni coder) ;
  - `setup --loggers` lance les tests de chaque projet changé avec le logger, comme la CI : lignes `LOGGER:` ;
  - point 34 du plugin : un agent ne peut écrire ni fichier, ni dossier, ni test sonde ; `diff-guard.sh` arrête le push d'une sonde.
- **`~/oc2`** (e50cb12) : retiré de COMMANDES ; MIGRATION dit que l'annexe A est le parcours, les étapes 1 à 12 restent pour mémoire. Les replis du code vers `~/oc2` restent.

## Ce qui reste à faire

1. **Pipeline de l'utilisateur** : il doit retirer le test sonde, recoller les fichiers que liste le bloc en tête de `opencode-v2/COMMANDES.md` (« En cours : la CI s'arrête sur … 'junit' »), puis pousser. **Pas encore de confirmation que la pipeline repasse.** Quand il confirme, retire ce bloc de COMMANDES.md, avec son entrée de RELEASE-NOTES, sur `main`.
2. **Paquets devenus payants** : l'utilisateur demande une passe pour faciliter leur retrait vers du natif. Existent déjà : Blazorise (`blazor-native.sh`, skill `blazorise`), AutoMapper (`automapper.sh`, skills `automapper`, `mapster`), MediatR (conventions CQRS : médiateur maison). Rien pour NPOI 2.8+ (frais de maintenance), EPPlus 5+, FluentAssertions 8+, MassTransit 9+, QuestPDF, ImageSharp 3+ (`package-licenses.sh` les signale seulement). Question posée : lesquels sont dans ses dépôts.
3. **Cas non couvert pour les loggers** : un modèle de CI hébergé dans un autre dépôt GitLab, dans un dépôt dont aucun projet de tests n'a encore de logger. Le pack ne peut pas le deviner ; il le dit (« SETUP: no test logger to add ») et nomme le paquet à ajouter.

## Vérifier avant de pousser (depuis `opencode-v2/`)

```sh
node tools/validate.js && sh tools/release-notes.sh check
node tools/plugin-test.mjs                      # 897 vérifications
(cd tools && node permission-sim.mjs ..)        # 3 210 cas ; python3 tools/permissions.py régénère les permissions
sh tools/scripts-test.sh sh                     # puis dash et bash
sh tools/dotnet-test.sh sh                      # 474 contrôles, faux dotnet ; puis dash et bash (plus de 2 minutes : en arrière-plan)
sh tools/scenarios-test.sh sh
sh tools/fortify-test.sh sh
```
Les suites avec les vrais SDK .NET et Docker ne tournent que dans la CI GitHub. Il n'y a pas de `dotnet` dans le conteneur de la session.

## Les présentations : sources et reconstruction

Les sources sont dans `.claude/handoff/deck/` :
- `build-tl.js` : la présentation aux tech leads ;
- `build.js` : `docs/presentation-flux.pptx` ;
- `icons.js` et `icons.json` : les icônes react-icons rendues en PNG.

Le 4 novembre, elles redonnaient à l'identique le texte des deux fichiers de `docs/`. Pour reconstruire :
```sh
D=<dossier de travail>; mkdir -p $D && cp .claude/handoff/deck/* $D/ && cd $D && npm install   # pptxgenjs, react, react-dom, react-icons, sharp ; jszip vient avec pptxgenjs
node build-tl.js tl.pptx          # APPLY_THEME=<chemin de apply_theme.js> si le skill pptx n'est pas trouvé tout seul
python3 <skill pptx>/scripts/office/validate.py tl.pptx
python3 <skill pptx>/scripts/office/soffice.py --headless --convert-to pdf tl.pptx && pdftoppm -r 110 -jpeg tl.pdf p
```
- **Vérifier à chaque reconstruction** :
  - regarder chaque image rendue : aucun chevauchement, rien de coupé, aucune ligne orpheline ;
  - aucun nom interdit ni emoji dans `slide_text.py` ;
  - autant de notes de l'orateur que de diapositives.
- **Livrer** : copier le fichier dans `opencode-v2/docs/presentation-tech-leads.pptx` et mettre à jour FICHIERS, README et RELEASE-NOTES.
- **Les retours de l'utilisateur sur la présentation** :
  - une histoire simple du début à la fin ;
  - des mots compréhensibles sans l'orateur (il a demandé ce que voulaient dire « signaux », « relisible », « contexte maîtrisé ») ;
  - `/go` et `/fortify` sont les flux les plus importants : clairs, visuels, concis ;
  - pas de « refonte » ni d'OpenShift sur la diapositive DevX ;
  - pas de `/outil vitesse` dans le grand schéma.

## Repères techniques d'OpenCode v2 (lus dans son code source, v2.1.3 et v2.1.4)

- **Limites de sortie** : `session/model-request.ts` (`OUTPUT_TOKEN_FALLBACK=32000`, `OUTPUT_TOKEN_MAX=256000`). Le résumé du contexte se déclenche à fenêtre − max(15 %, 16000), ou à fenêtre − `compaction.buffer` ; `limit.output` n'y joue pas.
- **Permissions** :
  - la dernière règle qui correspond l'emporte, et les règles d'un agent passent après les globales ;
  - un outil refusé en entier disparaît de la liste de l'agent (`tool.ts`, `whollyDisabled`) ;
  - l'id d'un outil MCP est `<serveur>_<outil>`.
- **Variables** : `{env:NOM}` se lit dans l'environnement du processus serveur ; une variable manquante donne une valeur vide.
- **API des plugins** : `ctx.tool.list()`, `ctx.mcp.list()`. À la limite d'étapes, le modèle reçoit `MAX_STEPS_PROMPT` avec `toolChoice: "none"`.
