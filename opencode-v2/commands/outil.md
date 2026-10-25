---
description: "Les autres outils du pack, à la demande : doc, audit, licences, release-notes, pattern (capturer une implémentation d'un autre dépôt pour /go), cqrs, setup (AGENTS.md du dépôt), liens (les dépôts de la même application, pas à pas), abandon, todo, stats (ce que /go et /fix ont fait), http (les requêtes de l'API pour Rider, pas à pas), planifier (une commande qui n'écrit rien, lancée à heure fixe, pas à pas). Usage: /outil <nom> [arguments] ; /outil seul donne la liste"
agent: build
subtask: false
---
[[command outil $ARGUMENTS]]
[[run outil.sh --raw $ARGUMENTS]]

My request: « /outil $ARGUMENTS »

- The output above starts with "Outils disponibles" (no tool, or an unknown one): show that list as it is, then ask me with the question tool (header "Outil") which one I want: up to 4 options whose label is the command (`/outil doc`, `/outil audit`, `/outil licences`, `/outil setup`), plus "Rien pour l'instant". The pack plugin starts the command I choose: then answer only « Je lance <command>. ».
- Otherwise: load the skill of the "Skill :" line with the skill tool (a skill it does not know, added since OpenCode started: read the file of the line "Fichier du skill :" with the read tool) and follow it, with the arguments and the facts printed above: never compute them again.
