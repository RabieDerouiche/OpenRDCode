#!/bin/sh
# Tests of the pack's git scripts (branch.sh, base.sh, ship.sh, workflow-state.sh, diff-guard.sh) against a bare
# repository standing for GitLab, in a temporary home folder. Usage, from opencode-v2/: sh tools/scripts-test.sh
# [<shell>] (default sh; the pack's scripts run with that shell too: dash, bash, busybox sh).
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
work=$(mktemp -d "${TMPDIR:-/tmp}/scripts-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
HOME="$work/home"
mkdir -p "$HOME"
export HOME
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
git config --global init.defaultBranch develop
git config --global advice.detachedHead false

pass=0
fail=0
check() {
  # check <name> <expected exit: 0|1|any> <grep pattern of the output> [<pattern that must not appear>]
  name=$1 want=$2 pattern=$3 absent=$4
  ok=1
  case "$want" in
    any) ;;
    *) [ "$status" -eq "$want" ] || ok=0 ;;
  esac
  printf '%s\n' "$out" | grep -qE -- "$pattern" || ok=0
  [ -n "$absent" ] && printf '%s\n' "$out" | grep -qE -- "$absent" && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
}
run() {
  script=$1
  shift
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
}
truth() {
  # truth <name> <shell test>: a check on the repository itself
  if eval "$2"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1 ($2)"; fi
}

# ---------- origin, with develop, master and a teammate's branch ----------
git init -q --bare "$work/origin.git"
git clone -q "$work/origin.git" "$work/seed" 2>/dev/null
cd "$work/seed" || exit 1
printf 'one\n' > a.txt
printf 'shared\n' > shared.txt
git add -A && git commit -q -m "init"
git push -q origin develop
git push -q origin develop:master
git switch -q -c feature/TEAM-9-teammate
printf 'teammate\n' > team.txt
git add -A && git commit -q -m "teammate work"
git push -q origin feature/TEAM-9-teammate
git switch -q develop

git clone -q "$work/origin.git" "$work/repo" 2>/dev/null
cd "$work/repo" || exit 1
git switch -q develop

# ---------- base.sh ----------
run base.sh
check "base: develop by default" 0 '^develop$'
run base.sh --why
check "base: why default" 0 '^default$'

# ---------- /go: a new ticket branch from origin/develop ----------
run branch.sh ABC-1 feature "Ajout de l'export CSV"
check "go: new branch from develop" 0 '^BRANCH: feature/ABC-1-ajout-export-csv \(created from origin/develop'
run base.sh
check "go: base stays develop" 0 '^develop$'
git switch -q develop

# ---------- /go … depuis <branch> ----------
run branch.sh ABC-2 feature "Suite du travail" --from feature/TEAM-9-nope
check "from: unknown branch stops, with close names" 1 'STOP: no branch feature/TEAM-9-nope on origin \(close names: feature/TEAM-9-teammate'
git switch -q -c local-only && git switch -q develop
run branch.sh ABC-2 feature "Suite du travail" --from local-only
check "from: a local-only branch stops" 1 'STOP: the branch local-only is not on origin'
run branch.sh ABC-2 feature "Suite du travail" --from origin/feature/TEAM-9-teammate
check "from: new branch from the teammate branch" 0 'BRANCH: feature/ABC-2-suite-travail \(created from origin/feature/TEAM-9-teammate'
check "from: base recorded" 0 'BASE: origin/feature/TEAM-9-teammate instead of origin/develop'
truth "from: the branch holds the teammate work" '[ -f team.txt ]'
run base.sh --why
check "from: base.sh gives the recorded base" 0 '^feature/TEAM-9-teammate$'
run workflow-state.sh --no-fetch
check "from: workflow-state shows the recorded base" 0 'Base branch: origin/feature/TEAM-9-teammate \(the base recorded'
printf 'mine\n' > mine.txt
run ship.sh --no-push "feat: my change (ABC-2)"
check "from: local commit" 0 'COMMIT: .* feat: my change'
# the teammate pushes again: --base merges his branch, not develop
cd "$work/seed" && git switch -q feature/TEAM-9-teammate && printf 'more\n' >> team.txt && git commit -q -am "teammate more" && git push -q origin feature/TEAM-9-teammate
git switch -q develop && printf 'dev\n' > dev-only.txt && git add -A && git commit -q -m "develop moves" && git push -q origin develop
cd "$work/repo" || exit 1
run ship.sh --sync-only --base
check "from: --base merges the recorded base" 0 'BASE: the 1 new commits of origin/feature/TEAM-9-teammate merged'
truth "from: develop is not merged" '[ ! -f dev-only.txt ]'
run ship.sh "feat: deliver (ABC-2)"
check "from: push, guard against the recorded base" 0 'GUARD: OK .* since origin/feature/TEAM-9-teammate'
check "from: pushed" 0 'PUSH: OK'
run branch.sh ABC-2 feature "Suite du travail" --from develop
check "from: develop given again on the branch: the record goes" 0 'already checked out'
run base.sh --why
check "from: back to the default base" 0 '^default$'
git switch -q develop

# ---------- an OpenCode workspace: detached HEAD, work done before any command ----------
git worktree add -q --detach "$work/ws1" origin/develop
cd "$work/ws1" || exit 1
printf 'poc\n' > poc.txt
run ship.sh "wip"
check "workspace: ship.sh on a detached HEAD says what to do" 1 'STOP: detached HEAD .*/push creates one'
run branch.sh --here poc "Essai du cache Redis"
check "workspace: /push makes a branch at the current commit" 0 '^BRANCH: poc/essai-cache-redis \(created from the detached HEAD'
check "workspace: the changes come along" 0 'CARRIED: .*poc.txt'
run ship.sh "feat: try a redis cache"
check "workspace: first push of the POC" 0 'PUSH: OK, origin/poc/essai-cache-redis'
truth "workspace: upstream set" 'git rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1'

# a /go in a workspace that already holds uncommitted work
git worktree add -q --detach "$work/ws2" origin/develop
cd "$work/ws2" || exit 1
printf 'started\n' > started.txt
run branch.sh ABC-3 bugfix "Corriger le total"
check "workspace /go: ticket branch from origin/develop with the changes" 0 '^BRANCH: bugfix/ABC-3-corriger-total \(created from origin/develop'
check "workspace /go: carried" 0 'CARRIED: .*started.txt'

# the changes touch a file origin/develop changed since the workspace started: the branch starts at its commit
git worktree add -q --detach "$work/ws3" develop~0
cd "$work/seed" && git switch -q develop && printf 'upstream\n' >> shared.txt && git commit -q -am "shared changed upstream" && git push -q origin develop
cd "$work/repo" && git fetch -q origin
cd "$work/ws3" || exit 1
git reset -q --hard "$(git -C "$work/repo" rev-parse develop)"
printf 'local edit\n' >> shared.txt
run branch.sh ABC-4 feature "Partage"
check "workspace /go: conflicting changes: branch at the current commit" 0 'BRANCH: feature/ABC-4-partage \(created at the current commit'
truth "workspace /go: the local edit is still there" 'grep -q "local edit" shared.txt'

# ---------- /push from develop: a POC branch ----------
cd "$work/repo" || exit 1
git switch -q develop
git merge -q --ff-only origin/develop
printf 'quick\n' > quick.txt
run branch.sh --here poc "Essai du cache Redis"
check "develop: a POC branch, the name taken gets -2" 0 '^BRANCH: poc/essai-cache-redis-2 \(created from develop'
run ship.sh "feat: another try"
check "develop: pushed" 0 'PUSH: OK, origin/poc/essai-cache-redis-2'
run branch.sh --here poc "anything"
check "here: a normal branch is kept" 0 '^BRANCH: poc/essai-cache-redis-2 \(kept'

# ---------- /push: the branch the developer chose, its name given as is ----------
git switch -q develop
printf 'tests\n' > tests.txt
run branch.sh --here --name develop
check "name: develop refused" 1 'STOP: develop is not a branch for this work'
run branch.sh --here --name "///"
check "name: an invalid name refused" 1 'STOP: "///" is not a branch name'
run branch.sh --here --name "Feature/Mon essai: cache"
check "name: a typed name made valid, said so" 0 '^BRANCH: Feature/Mon-essai-cache \(created from develop.*\(the name given, made valid: Feature/Mon essai: cache\)'
git switch -q develop
git branch -q -D Feature/Mon-essai-cache
run branch.sh --here --name poc/essai-cache-redis
check "name: a name taken on origin stops" 1 'STOP: the branch poc/essai-cache-redis exists already'
run branch.sh --here --name feature/export-csv-par-mail
check "name: the branch of the given name" 0 '^BRANCH: feature/export-csv-par-mail \(created from develop'
check "name: the changes come along" 0 'CARRIED: .*tests.txt'
git switch -q develop
run branch.sh --here test "Tests unitaires du calcul de la TVA"
check "here: a test branch" 0 '^BRANCH: test/tests-unitaires-calcul-tva \(created from develop'
git switch -q develop
rm -f tests.txt

# ---------- what must still stop ----------
git switch -q -c feature/OTHER-1-x origin/develop 2>/dev/null
printf 'dirty\n' > dirty.txt
run branch.sh ABC-5 feature "Autre"
check "dirty changes on another branch stop" 1 'STOP: uncommitted changes on feature/OTHER-1-x .*commit them \(/push\)'
rm -f dirty.txt
git switch -q develop
run ship.sh "nope"
check "develop stays protected" 1 'STOP: develop is a protected branch'
run branch.sh NOTAKEY feature "x"
check "bad key" 1 'is not a Jira key'
run branch.sh ABC-6 feature "x" --from "bad..name"
check "bad branch name" 1 'is not a branch name'

# ---------- ship.sh: a conflict with the base is aborted, a secret is never pushed ----------
git switch -q -c feature/ABC-7-conflict origin/develop 2>/dev/null
printf 'mine\n' > shared.txt
run ship.sh --no-push "feat: mine (ABC-7)"
cd "$work/seed" && git switch -q develop && printf 'theirs\n' > shared.txt && git commit -q -am "theirs" && git push -q origin develop
cd "$work/repo" || exit 1
run ship.sh --base "feat: deliver (ABC-7)"
check "conflict with develop: aborted" 1 'STOP: CONFLICT while merging .* in shared.txt: merge aborted'
truth "conflict: no merge left in progress" '[ ! -f .git/MERGE_HEAD ]'
git switch -q -c feature/ABC-8-secret origin/develop 2>/dev/null
printf 'url = "https://user:Sup3rSecretValue@gitlab.example.com/x.git"\n' > settings.txt
run ship.sh "feat: secret (ABC-8)"
check "secret: nothing pushed" 1 'GUARD: STOP'
truth "secret: the branch is not on origin" '! git ls-remote --exit-code --heads origin feature/ABC-8-secret >/dev/null 2>&1'
# installed dependencies and build outputs that the .gitignore misses: never pushed
git switch -q -c feature/ABC-8-modules origin/develop 2>/dev/null
mkdir -p ClientApp/node_modules/left-pad ClientApp/dist/shop src/Api/obj/Debug
printf 'module.exports = 1\n' > ClientApp/node_modules/left-pad/index.js
printf 'x\n' > ClientApp/node_modules/left-pad/package.json
printf '<html></html>\n' > ClientApp/dist/shop/index.html
printf '{}\n' > src/Api/obj/project.assets.json
run ship.sh "feat: with an install (ABC-8)"
check "node_modules: nothing pushed" 1 'GUARD: STOP'
check "node_modules: said once, with the count" 1 '2 file\(s\) of node_modules added \(ClientApp/node_modules/left-pad/[a-z.]*, …\)'
check "obj: said" 1 '1 file\(s\) of obj added \(src/Api/obj/project.assets.json\)'
check "dist: a warning" 1 'WARNING: 1 file\(s\) of dist added'
truth "node_modules: the branch is not on origin" '! git ls-remote --exit-code --heads origin feature/ABC-8-modules >/dev/null 2>&1'

# ---------- /sync on develop: a fast-forward to origin, never a merge ----------
git switch -q develop
git reset -q --hard "$(git rev-parse develop)"
git clean -qfd
behind=$(git rev-list --count develop..origin/develop)
cd "$work/seed" && printf 'later\n' > later.txt && git add -A && git commit -q -m "later on develop" && git push -q origin develop
cd "$work/repo" || exit 1
run ship.sh --sync-only
check "sync develop: fast-forward" 0 "REMOTE: $((behind + 1)) commits of origin/develop brought in"
run ship.sh --sync-only --base
check "sync develop: never with --base" 1 'STOP: develop is a protected branch'
printf 'local\n' > local.txt && git add -A && git commit -q -m "local commit on develop"
cd "$work/seed" && printf 'more\n' >> later.txt && git commit -q -am "more on develop" && git push -q origin develop
cd "$work/repo" || exit 1
run ship.sh --sync-only
check "sync develop: local commits stop, nothing merged" 1 'STOP: the local develop has 1 commits that origin/develop does not have'
truth "sync develop: no merge commit" '[ "$(git rev-list --merges --count develop)" = 0 ]'

# ---------- /sync on a work branch: the commits pushed from another computer, then develop on request ----------
git reset -q --hard origin/develop
git switch -q -c feature/ABC-9-sync origin/develop
git push -q -u origin feature/ABC-9-sync 2>/dev/null
git clone -q "$work/origin.git" "$work/mac" 2>/dev/null
cd "$work/mac" || exit 1
git switch -q feature/ABC-9-sync
printf 'from the mac\n' > mac.txt && git add -A && git commit -q -m "work from the mac" && git push -q origin feature/ABC-9-sync
cd "$work/repo" || exit 1
printf 'not committed\n' > wip.txt
run ship.sh --sync-only
check "sync: the commits pushed from another computer" 0 'REMOTE: '
truth "sync: their file is here" '[ -f mac.txt ]'
truth "sync: the uncommitted work stays" '[ -f wip.txt ] && [ -n "$(git status --porcelain -- wip.txt)" ]'
truth "sync: nothing pushed" '[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/feature/ABC-9-sync)" ]'
cd "$work/seed" && git pull -q origin develop 2>/dev/null; printf 'develop moves\n' > dev2.txt && git add -A && git commit -q -m "develop moves" && git push -q origin develop
cd "$work/repo" || exit 1
run ship.sh --sync-only --base
check "sync --base: develop merged" 0 'BASE: '
truth "sync --base: its file is here" '[ -f dev2.txt ]'
truth "sync --base: still nothing pushed" '! git merge-base --is-ancestor HEAD origin/feature/ABC-9-sync'
rm -f wip.txt

# ---------- /outil abandon: a ticket started by mistake, never any work lost ----------
cd "$work/repo" || exit 1
git switch -q develop && git reset -q --hard origin/develop && git clean -qfd
run abandon.sh --check
check "abandon: nothing on develop" 1 'STOP: nothing to abandon on develop'
run branch.sh ABC-77 feature "Mauvais ticket"
mkdir -p .git/opencode-tickets && printf '# ABC-77\n' > .git/opencode-tickets/ABC-77.md
printf 'wip\n' > wip.txt
run abandon.sh
check "abandon: an untracked file stops it" 1 'STOP: uncommitted or untracked files: wip.txt'
rm -f wip.txt
run abandon.sh --check
check "abandon: what it would delete" 0 'WOULD DELETE: the local branch feature/ABC-77-mauvais-ticket'
check "abandon: and the sheet" 0 'WOULD DELETE: its ticket sheet .*ABC-77.md'
truth "abandon --check: nothing changed" '[ "$(git branch --show-current)" = feature/ABC-77-mauvais-ticket ] && [ -f .git/opencode-tickets/ABC-77.md ]'
run abandon.sh
check "abandon: back to develop" 0 '^SWITCHED: to develop, at origin/develop'
check "abandon: sheet deleted" 0 '^DELETED: the ticket sheet'
check "abandon: branch deleted" 0 '^DELETED: the local branch feature/ABC-77-mauvais-ticket'
truth "abandon: the branch is gone" '! git rev-parse -q --verify refs/heads/feature/ABC-77-mauvais-ticket >/dev/null'
run branch.sh ABC-78 feature "Un vrai debut"
printf 'work\n' > work.txt && git add work.txt && git commit -q -m "real work"
run abandon.sh
check "abandon: a commit of its own stops it" 1 'STOP: feature/ABC-78-vrai-debut has 1 commits that origin/develop does not have'
truth "abandon: the work is still there" '[ "$(git branch --show-current)" = feature/ABC-78-vrai-debut ] && [ -f work.txt ]'
git switch -q develop
git worktree add -q --detach "$work/wt-abandon" origin/develop
cd "$work/wt-abandon" || exit 1
run branch.sh ABC-79 bugfix "Erreur de depot"
run abandon.sh
check "abandon in a worktree: detached at the base" 0 '^SWITCHED: this worktree to a detached HEAD at origin/develop'
check "abandon in a worktree: says the folder can go" 0 '^WORKTREE: wt-abandon holds nothing now'
cd "$work/repo" || exit 1
git worktree remove --force "$work/wt-abandon"

# ---------- /outil carte: the map of the flows of the pack, made from its own files ----------
pack=$(dirname "$scripts")
run pack-map.sh --pack "$pack" --out "$work/map/carte.html"
check "carte: the page and what it counts" 0 "^CARTE: $work/map/carte\\.html \\([0-9]+ commandes, [0-9]+ outils de /outil, [0-9]+ agents, [0-9]+ skills, [0-9]+ fonctions du plugin, [0-9]+ scripts\\)$"
check "carte: /go, its steps, its agents and its questions" 0 '^COMMANDE: /go — pilot — .* — [0-9]+ étapes — agents : analyst, .* — questions : Ticket, Ticket ambigu'
truth "carte: the commands in the order of their families, /go first" 'printf "%s\n" "$out" | grep "^COMMANDE:" | head -n 1 | grep -q "^COMMANDE: /go "'
check "carte: a tool whose arguments hold « : »" 0 '^OUTIL: pattern — capture une bonne implémentation'
check "carte: an agent and what it may write" 0 '^AGENT: test-guardian — subagent — écrit : les projets de tests$'
check "carte: the tools of /outil, as outil.sh lists them" 0 '^OUTIL: carte — '
check "carte: the functions of the plugin, in plain words" 0 '^PLUGIN: 7\. Garde les agents dans le dépôt'
check "carte: an answer header is no question" 0 '^COMMANDE: /tests ' 'questions : [^—]*\*\*'
for c in "$pack"/commands/*.md; do
  n=$(basename "$c" .md)
  grep -q "<section id=\"cmd-$n\">" "$work/map/carte.html" || { fail=$((fail + 1)); echo "FAIL: carte: no section for /$n"; }
done
pass=$((pass + 1))
truth "carte: one diagram per command that has steps" '[ "$(grep -c "<pre class=\"mermaid\">" "$work/map/carte.html")" -ge 8 ]'
truth "carte: no raw < in a diagram but its line breaks" '! awk "/<pre class=\"mermaid\">/{on=1;next} /<\/pre>/{on=0} on" "$work/map/carte.html" | sed "s#<br/>##g" | grep -q "<"'
truth "carte: the page is UTF-8 and complete" 'tail -n 1 "$work/map/carte.html" | grep -q "^</html>$" && iconv -f UTF-8 -t UTF-8 "$work/map/carte.html" > /dev/null 2>&1'
run pack-map.sh --pack "$work/repo" --out "$work/map/x.html"
check "carte: a folder that is not a pack" 1 '^STOP: .* is not a pack of OpenCode'
run pack-map.sh --pack "$pack" --out "$work/map/carte.txt"
check "carte: an .html page only" 1 '^STOP: the map is an \.html page'
run outil.sh carte ../dehors
check "outil carte: never outside the repository" 0 "^Carte : « \\.\\./dehors » n'est pas un chemin du dépôt"
run outil.sh carte docs
check "outil carte docs: the page in the repository, to push it" 0 "^CARTE: $work/repo/docs/carte-des-flux\\.html "
truth "outil carte docs: written there" '[ -s "$work/repo/docs/carte-des-flux.html" ]'
rm -rf "$work/repo/docs"
# the pack this OpenCode reads, found as its plugin finds it: OpenCode v2 next to 1.19 (OPENCODE_CONFIG_DIR in ~/oc2,
# without the scripts, common to both in ~/.config/opencode/scripts), then the usual configuration folder
unset XDG_CONFIG_HOME
mkdir -p "$work/oc2/config/opencode" "$HOME/.config/opencode"
cp -R "$pack/commands" "$pack/agents" "$pack/skills" "$pack/plugins" "$work/oc2/config/opencode/"
rm "$work/oc2/config/opencode/commands/compare.md"
cp -R "$pack/commands" "$pack/agents" "$HOME/.config/opencode/"
rm "$HOME/.config/opencode/commands/compare.md" "$HOME/.config/opencode/commands/review.md"
nscripts=$(set -- "$scripts"/*.sh; echo "$#")
OPENCODE_CONFIG_DIR="$work/oc2/config/opencode"
export OPENCODE_CONFIG_DIR
run pack-map.sh
check "carte: v2 next to 1.19, its configuration folder and the common scripts" 0 "^CARTE: $work/oc2/config/opencode/carte-des-flux\\.html \\(9 commandes, .* $nscripts scripts\\)$"
truth "carte: written in the configuration folder of v2" '[ -s "$work/oc2/config/opencode/carte-des-flux.html" ]'
unset OPENCODE_CONFIG_DIR
run pack-map.sh --out "$work/map/usual.html"
check "carte: otherwise the usual configuration folder" 0 "^CARTE: $work/map/usual\\.html \\(8 commandes, "
rm -rf "$HOME/.config/opencode"
run pack-map.sh --out "$work/map/above.html"
check "carte: otherwise the folder above the scripts" 0 "^CARTE: $work/map/above\\.html \\(10 commandes, "

echo "$pass checks passed, $fail failed ($SHELL_UNDER_TEST)"
[ "$fail" -eq 0 ]
