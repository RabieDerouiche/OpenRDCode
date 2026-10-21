---
description: "Les autres outils du pack, à la demande : doc, audit, licences, release-notes, pattern (capturer une implémentation d'un autre dépôt pour /go), cqrs, setup (AGENTS.md du dépôt), abandon, todo, stats (ce que /go et /fix ont fait). Usage: /outil <nom> [arguments] ; /outil seul donne la liste"
agent: build
subtask: false
---
[[run outil.sh --raw $ARGUMENTS]]

My request: « /outil $ARGUMENTS »

- The output above starts with "Outils disponibles" (no tool, or an unknown one): show that list as it is, then ask me with the question tool (header "Outil") which one I want: up to 4 options whose label is the command (`/outil doc`, `/outil audit`, `/outil licences`, `/outil setup`), plus "Rien pour l'instant". The pack plugin starts the command I choose: then answer only « Je lance <command>. ».
- Otherwise: load the skill of the "Skill :" line with the skill tool (a skill it does not know: read `~/.config/opencode/skills/<that name>/SKILL.md` at its absolute path, `realpath ~` gives the home folder) and follow it, with the arguments and the facts printed above: never compute them again.
