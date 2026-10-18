---
description: "On demand: licenses of the NuGet packages, to find those that became paid or copyleft from a given version (commercial license, maintenance fee, AGPL), with their free option. Read-only, one script, no other tool call. Usage: /licences (whole repository, transitive packages included) | /licences branche (packages added or changed on the branch) | /licences <PackageId> [version] (before adding or upgrading one)"
agent: architect
subtask: false
---
Result of `package-licenses.sh $ARGUMENTS`:
[[run package-licenses.sh '$ARGUMENTS']]

Answer in French from this result only, without any tool call:
- One table: package, version, fichier, verdict (payant, frais de maintenance, AGPL, ou version gratuite à ne pas monter), à partir de quelle version, option gratuite. Paid packages first, then the transitive ones (with the `dotnet nuget why <solution or project> <package>` command to find which reference brings them), then the free versions not to upgrade.
- If nothing is flagged: one line saying so, with what was checked.
- One last line: "Liste de règles datée (en tête du script), pas un scan complet des licences : pour un autre package, vérifie sa licence sur nuget.org ou dans Artifactory."
