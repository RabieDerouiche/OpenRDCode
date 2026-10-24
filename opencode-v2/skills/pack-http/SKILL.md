---
name: pack-http
description: "Procédure de /outil http : les requêtes des endpoints de l'API pour le client HTTP de Rider (et de Visual Studio), écrites depuis le code, un fichier .http par contrôleur, les environnements d'AGENTS.md, les jetons dans un fichier privé jamais commité ; le corps des requêtes rempli depuis les DTO."
compatibility: opencode
---
# /outil http

Started directly as the command `/pack-http` (this procedure is the message that started you, with no line « Skill : pack-http » printed before it): answer only « Lance `/outil http` : cette procédure a besoin de ce que /outil prépare. » and stop.

The pack already ran `http-files.sh` (the lines above): the files are written, never written again here. A "STOP:" line: answer with it and stop.

1. The bodies: each request with a line « # body: <Type>, to fill in » has `{}` as its body. Find each type in one turn of searches (grep tool on `record <Type>` and `class <Type>`), then replace each `{}` with one JSON object: the properties of the type in camelCase (or the naming of the repository's JSON options), realistic values that pass its validation (its attributes, its validator), never a real person, e-mail or secret. A type found nowhere: leave `{}` and say it.
2. Never open, read or write `http-client.private.env.json`: the developer's tokens go there, by hand.
3. The answer, in French: the files written or kept, the bodies filled, then how to use them: open a `.http` file in Rider, pick the environment at the top of the editor (`local`, then those of AGENTS.md; production is never there), run one request or all of them (each checks its status); the token of each environment, once, in `http-client.private.env.json` next to them (ignored by git: the line was added to `.gitignore` when it was missing); the route values (`id`…) in `http-client.env.json`. Last, the « Suite » question: « /push (recommandé) » (« les fichiers .http et le .gitignore partent dans un commit »), « Rien pour l'instant ».
