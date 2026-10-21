---
name: pack-licences
description: "Procédure de /outil licences : les packages NuGet devenus payants ou copyleft à partir d'une version (licence commerciale, frais de maintenance, AGPL), avec leur option gratuite, depuis le résultat du script du pack. Lecture seule, aucun autre appel."
compatibility: opencode
---
# /outil licences

Started directly as the command `/pack-licences` (this procedure is the message that started you, with no line « Skill : pack-licences » printed before it): answer only « Lance `/outil licences` : cette procédure a besoin de ce que /outil prépare. » and stop.

The result of `package-licenses.sh` is printed above (whole repository with the transitive packages, `branche` for the packages changed on the branch, or one package and version before adding or upgrading it). Answer in French from this result only, without any tool call:
- One table: package, version, fichier, verdict (payant, frais de maintenance, AGPL, ou version gratuite à ne pas monter), à partir de quelle version, option gratuite. Paid packages first, then the transitive ones (with the `dotnet nuget why <solution or project> <package>` command that finds which reference brings them), then the free versions not to upgrade.
- If nothing is flagged: one line saying so, with what was checked.
- One last line: « Liste de règles datée (en tête du script), pas un scan complet des licences : pour un autre package, vérifie sa licence sur nuget.org ou dans Artifactory. »
