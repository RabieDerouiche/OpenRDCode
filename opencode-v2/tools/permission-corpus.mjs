// v2 pack: commands the pack instructs and the reflexive ones a model reaches for, with the expected decision per agent.
// "allow" = runs without asking, "ask" = asks me, "deny" = refused. No shell command, read or edit may ask, for any
// agent: an "always" answer would be stored for the whole OpenCode instance and lift the rule for every agent. Paths
// outside the repository are refused by the pack plugin before these rules (tools/plugin-test.mjs).
const S = "sh ~/.config/opencode/scripts/"
const RO = ["analyst", "checker", "debugger", "doc-writer"]
const AUTONOMOUS = ["pilot", "analyst", "coder", "checker", "doc-writer"]
const ALL = ["build", "pilot", "coder", ...RO]

// Reflexive read-only commands: every agent must be able to run them (a refusal costs a turn and invites a workaround)
const READS = [
  "git status", "git status -sb", "git status --porcelain",
  "git log --oneline -15", "git log --oneline -20 -- src/Api/Controllers/OrdersController.cs",
  "git log --oneline origin/develop..HEAD | head -20", "git log -1 --format='%H %cs %s' origin/master",
  "git diff", "git diff --stat", "git diff HEAD -- src/Foo.cs", "git diff --staged", "git diff --staged --stat",
  "git diff origin/develop...HEAD -- src/Foo.cs", "git diff --name-only --diff-filter=U",
  "git show HEAD:src/Foo.cs", "git show abc1234 --stat", "git blame -L 10,40 src/Foo.cs",
  "git branch --show-current", "git branch -a --list \"*ABC-123*\"", "git branch -r", "git branch --contains abc1234",
  "git rev-parse --show-toplevel", "git rev-parse --verify abc1234",
  "git ls-files '*.csproj'", "git grep -n \"IStorageService\" -- '*.cs'",
  "git fetch -q origin develop", "git merge-base HEAD origin/develop",
  "git rev-list --left-right --count HEAD...origin/develop", "git worktree list", "git stash list", "git remote",
  "git diff-tree --no-commit-id --name-only -r HEAD", "git --no-pager log --oneline -5",
  "ls", "ls -la src", "pwd", "cat src/Foo.cs", "head -50 src/Foo.cs", "tail -60 src/Foo.cs", "wc -l src/Foo.cs",
  "find . -name \"*.csproj\"", "find src -name \"*Handler.cs\" | head -20", "grep -rn \"IStorageService\" src",
  "grep -rn \"Foo\" src | head -20", "rg -n \"Foo\" src", "tree -L 2 src", "sort a.txt | uniq -c",
  "date \"+%Y-%m-%d %H:%M\"", "date +%Y-%m-%d", "which dotnet", "command -v dotnet", "dotnet --version",
  "dotnet --info", "dotnet --list-sdks", "dotnet list package", "dotnet list src/Api/Api.csproj reference",
  "jq '.scripts' package.json", "sed -n '10,40p' src/Foo.cs", "test -f AGENTS.md", "[ -f AGENTS.md ] && echo yes",
  "echo \"---\"", "cat src/a.cs src/b.cs", "ls src/ 2>/dev/null", "git log --oneline -5 2>&1 | head",
  "cd src && ls", "realpath src", "comm -12 a.txt b.txt", "paste a.txt b.txt", "nl src/Foo.cs | head", "tac a.txt | head -5",
  "git diff --name-only HEAD | sort | column -c 120",
  // search strings with C# generics and lambdas (">" inside quotes is not a redirection)
  "git grep -n \"List<Order>\" abc1234 -- src", "grep -rn \"x => x.Id\" src", "git grep -n \"Task<IActionResult>\" -- '*.cs'",
  "git show abc1234:src/Foo.cs | grep -n \"Dictionary<string, List<int>>\"",
  // kebab-case paths and folders that contain words of the old substring rules
  "git diff -- src/app/auth/reset-password/reset-password.component.ts", "git log --oneline -- src/app/user-delete/",
  "git log -- src/app/job-executor/x.ts", "git diff -- src/app/used-items/x.ts", "git diff HEAD -- src/app/secret-santa/x.ts",
  "git log -- src/Infrastructure/credentials/", "git diff -- config/appsettings.json", "git log --oneline -- push-notifications/",
  "git diff -- src/app/api-key-form/x.ts",
  "dotnet nuget why src/App.sln Newtonsoft.Json",
  // the "noun first" forms of .NET 10
  "dotnet package list", "dotnet package list --vulnerable --include-transitive", "dotnet reference list --project src/Api/Api.csproj",
]

// Secrets, environment dumps, credential-bearing git output: refused for EVERY agent, build and dev included
const SECRETS = [
  "cat ~/.nuget/NuGet/NuGet.Config", "grep -c ClearTextPassword ~/.nuget/NuGet/NuGet.Config",
  "grep -o 'key=\"[^\"]*\"' ~/.nuget/NuGet/NuGet.Config | sort -u", "head -20 ~/.nuget/NuGet/NuGet.Config",
  "cat nuget.config", "cat NuGet.Config", "head src/NuGet.config", "grep -i source Nuget.Config",
  "echo $artifactory_password", "echo \"$artifactory_user\"", "printf '%s' \"$artifactory_password\"",
  "printenv", "printenv artifactory_user", "env", "env | grep -i art", "set", "compgen -v",
  "test -n \"$MVNW_PASSWORD\" && echo set", "echo $GITLAB_TOKEN",
  "cat /proc/self/environ", "tr '\\0' '\\n' < /proc/1/environ",
  "cat ~/.zshenv", "grep artifactory ~/.zshrc_perso", "cat ~/.zshrc_perso", "cat ~/.zshrc", "cat ~/.bashrc",
  "cat ~/.ssh/id_rsa", "cat ~/.aws/credentials", "cat ~/.npmrc", "cat ~/.netrc", "cat ~/.git-credentials",
  "cat .npmrc", "cat ClientApp/.npmrc", "cat .yarnrc.yml", "grep -i token .yarnrc.yml",
  "cat appsec-ci.env", "grep APPSEC appsec-ci.env",
  "git config --list", "git config --get remote.origin.url", "git remote -v", "git remote get-url origin",
  "cat ~/.config/opencode/opencode.json", "grep -i token ~/.config/opencode/opencode.json",
  "cat ~/.local/share/opencode/auth.json", "cat .env", "cat src/Api/.env.local", "dotnet user-secrets list",
  "python3 -c \"import os; print(os.environ['ARTIFACTORY_PASSWORD'])\"",
]

// Destructive or out-of-role commands for the read-only agents
const RO_DENY = [
  "git commit -m \"x\"", "git add -A", "git push", "git push -u origin feature/ABC-1-x", "git reset --hard",
  "git checkout -- src/Foo.cs", "git restore src/Foo.cs", "git clean -fd", "git stash", "git stash push -m x",
  "git merge origin/develop", "git rebase origin/develop", "git branch -D feature/x", "git branch -f develop HEAD~1",
  "git branch -m new", "git cherry-pick abc", "git revert abc", "git -C /home/dev/repos/other push",
  "git -c core.sshCommand=\"cat ~/.ssh/id_rsa\" fetch", "git log --oneline > /tmp/out.txt", "dotnet build > build.log",
  "git show HEAD:src/Foo.cs > src/Foo.cs", "git diff >> changes.txt", "cat src/Foo.cs | tee copy.cs",
  "find . -name \"*.tmp\" -delete", "find . -name x -exec rm {} \\;", "sed -i 's/a/b/' src/Foo.cs",
  "rm src/Foo.cs", "mv a b", "cp a b", "touch x", "mkdir x", "awk 'BEGIN { system(\"rm x\") }'", "xargs rm",
  "git log $(git merge-base HEAD origin/develop)..HEAD", "npm install", "curl https://example.com",
  "git reflog expire --expire=now --all", "git tag -d v1", "sort -o out.txt in.txt", "sort -u in.txt -o in.txt",
  "tree -o tree.txt src",
]

export const cases = []
const add = (agents, cmds, expect, extra = {}) => {
  for (const agent of agents) for (const cmd of cmds) cases.push({ agent, cmd, expect, ...extra })
}
add(ALL.filter((a) => a !== "doc-writer"), READS, "allow")
// doc-writer: the configuration files stay closed, through git too
add(["doc-writer"], READS.filter((c) => !c.includes("appsettings")), "allow")
add(["doc-writer"], READS.filter((c) => c.includes("appsettings")), "deny")
add(ALL, SECRETS, "deny")
add([...RO, "pilot"], RO_DENY, "deny")

// ---------- pilot: /go, /fix, /daily. Git writes only through branch.sh and ship.sh ----------
const PILOT_ALLOW = [
  S + "workflow-state.sh --fetch-all --sheet", S + "workflow-state.sh --sheet --appsec", S + "detect-project-type.sh",
  S + "branch.sh ABC-123 feature \"Export PDF des factures\"", S + "branch.sh ABC-9 bugfix \"Reset password token expiry\"",
  S + "ship.sh --no-push \"feat(export): add the PDF exporter (ABC-123)\" \"- exporter service\" \"- unit tests\"",
  S + "ship.sh --base \"feat(export): add the PDF export (ABC-123)\"",
  S + "ship.sh --base \"fix(auth): read API_TOKEN and DOCUSIGN_SECRET from the environment (ABC-9)\"",
  S + "ship.sh --no-push \"chore: update nuget.config sources in the docs (ABC-3)\"",
  S + "ship.sh --no-push \"fix(ui): handle a > b and x => y (ABC-5)\"", S + "ship.sh --sync-only --base", S + "ship.sh --sync-only --base --merge hotfix/fortify-cleanup",
  S + "branch.sh LOCAL bugfix \"Corriger l'arrondi\"", S + "ticket-sheet.sh delete",
  S + "ship.sh \"feat(export): add the PDF export (ABC-123)\"", S + "outil.sh --raw 'todo fait 3'",
  S + "ticket-sheet.sh tick 2 \"/go étape 2 - 3 fichiers - build ok - tests 12/12\"",
  S + "ticket-sheet.sh decision \"Erreur métier : Result existant (étape 2) — le dépôt en a déjà un\"",
  S + "ticket-sheet.sh suivi \"/go - livré - MR !42\"", S + "ticket-sheet.sh plan",
  S + "build-test.sh", S + "build-test.sh src/App.sln", "dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60",
  "dotnet test --no-build 2>&1 | tail -80", "dotnet format --verify-no-changes --include src/Foo.cs",
  S + "compare-repos.sh --raw '/home/dev/repos/legacy-api ExportService le titre perd son extension'",
  "git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'", "git log --oneline origin/develop..HEAD && git diff --stat origin/develop...HEAD",
  S + "todo.sh list", S + "todo.sh due",
]
add(["pilot"], PILOT_ALLOW, "allow")
const PILOT_DENY = [
  "git commit -m \"feat: x (ABC-1)\"", "git add -A", "git push -u origin feature/ABC-1-x", "git push", "git merge origin/develop",
  "git merge --no-edit origin/feature/ABC-1-x", "git switch -c feature/ABC-1-x origin/develop", "git switch develop",
  "git stash push -u -m x", "git pull", "git reset --hard", "git rebase origin/develop", "git branch -D feature/x",
  S + "ship.sh \"$(cat ~/.ssh/id_rsa)\"", S + "ship.sh \"feat: `cat ~/.git-credentials`\"",
  S + "ship.sh --base \"x\" && git push --force", S + "ticket-sheet.sh decision \"${HOME}\"",
  "dotnet format", "dotnet format --include src/Foo.cs", "npx eslint --fix src", "npm install", "rm src/Foo.cs",
  "sh -c \"git push --force\"", "bash -c \"git push\"", "cat ~/.git-credentials | " + S + "ship.sh x",
]
add(["pilot"], PILOT_DENY, "deny")
// /fortify, /go and /fix: the measures and proofs of the test-guardian; putting work aside (git stash) is the pilot's
add(["test-guardian"], [S + "test-guardian.sh deps src/Api/Services/ExportService.cs",
  S + "test-guardian.sh coverage V1-before tests/Api.Tests/Api.Tests.csproj src/Api/Services/ExportService.cs src/Api/Storage/FileStore.cs",
  S + "test-guardian.sh red tests/Api.Tests/Api.Tests.csproj FullyQualifiedName~Security_PathTraversal_V1",
  S + "test-guardian.sh green tests/Api.Tests/Api.Tests.csproj FullyQualifiedName~Security_PathTraversal_V1",
  S + "test-guardian.sh red tests/Api.Tests/Api.Tests.csproj \"FullyQualifiedName~InvoiceServiceTests.Total_NegativeDiscount|FullyQualifiedName~InvoiceServiceTests.Total_ZeroLines\"",
  S + "test-guardian.sh compare V1-before V1-after", S + "test-guardian.sh tests-only", S + "test-guardian.sh folder", S + "fortify.sh prereq",
  S + "test-guardian.sh build tests/Api.Tests/Api.Tests.csproj", S + "test-guardian.sh build tests/Api.Tests/Api.Tests.csproj 2>&1 | tail -40",
  "git status --short", "git diff --stat"], "allow")
// the test-guardians of a wave build at the same time: only through the scripts, which run one build at a time. A
// harmless redirection (2>&1, >/dev/null) never re-opens a command the agent may not run: the plugin removes it, so
// the base command is what the rules see (an earlier version re-allowed anything containing "2>&1").
add(["test-guardian"], ["dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60", "dotnet build tests/Api.Tests/Api.Tests.csproj",
  "dotnet test tests/Api.Tests/Api.Tests.csproj --filter FullyQualifiedName~Security_PathTraversal_V1", "dotnet restore",
  "dotnet clean", "dotnet build >/dev/null 2>&1", "dotnet build -nologo >/dev/null", "dotnet restore 2>&1 | tail -20",
  "dotnet test tests/Api.Tests/Api.Tests.csproj >/dev/null 2>&1"], "deny")
add(["coder"], [S + "test-guardian.sh green tests/Api.Tests/Api.Tests.csproj FullyQualifiedName~Security_PathTraversal_V1",
  S + "test-guardian.sh build src/Api/Api.csproj", "dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60",
  "dotnet build >/dev/null 2>&1", "dotnet build -nologo -v q -clp:ErrorsOnly >/dev/null"], "allow")
// the unit test project of a repository that has none, and the proofs of a wave put away until their turn: the pilot only
add(["pilot"], [S + "test-guardian.sh setup xunit src/Api/Services/ExportService.cs src/Api/Storage/FileStore.cs && " + S + "ship.sh --no-push \"test: add the unit test project (ABC-123)\" \"- tests/Api.UnitTests/Api.UnitTests.csproj (xunit, net10.0)\"",
  S + "test-guardian.sh setup mstest src/Api/Services/ExportService.cs", S + "test-guardian.sh park V1 && " + S + "test-guardian.sh park V2 && " + S + "test-guardian.sh park V3",
  S + "test-guardian.sh unpark V2 && " + S + "test-guardian.sh red tests/Api.Tests/Api.Tests.csproj FullyQualifiedName~Security_PathTraversal_V2",
  S + "test-guardian.sh unpark F1 && " + S + "ship.sh --no-push \"test(security): show that path traversal in FileStore.cs is not exploitable (ABC-123)\"",
  S + "fortify.sh discard V2-V3", S + "fortify.sh discard reprise"], "allow")
add(["test-guardian", "coder", ...RO], [S + "test-guardian.sh setup xunit src/Api/Services/ExportService.cs", S + "test-guardian.sh park V1",
  S + "test-guardian.sh unpark V1", "bash ~/.config/opencode/scripts/test-guardian.sh setup nunit src/Api/Api.csproj",
  S + "test-guardian.sh setup --components xunit src/Web/Components/Pages/Orders.razor"], "deny")
// bUnit for the tests of Razor components (the safety net of a page): the pilot only, once the developer agreed
const P_COMPONENTS = (agents, cmds) => add(agents, cmds, "allow", { note: "prescribed by the pack" })
P_COMPONENTS(["pilot"], [S + "test-guardian.sh setup --components xunit src/Web/Components/Pages/Orders.razor src/Web/Components/Pages/Invoices.razor && " + S + "ship.sh --no-push \"test: add bUnit for the tests of the components (ABC-123)\" \"- SETUP: bunit 2.11.3 added to tests/Web.UnitTests/Web.UnitTests.csproj; build OK\"",
  S + "test-guardian.sh setup --components nunit src/Web/Components/Pages/Orders.razor && " + S + "ship.sh --no-push \"test: add bUnit for the tests of the components\""])
// the safety net of a page: the test-guardian measures and proves it, like the net of a C# method
P_COMPONENTS(["test-guardian"], [S + "test-guardian.sh deps src/Web/Components/Pages/Orders.razor",
  S + "test-guardian.sh net F1-before src/Web/Components/Pages/Orders.razor:OnInitialized src/Web/Components/Pages/Orders.razor:BuildRenderTree",
  S + "test-guardian.sh coverage F1-net tests/Web.UnitTests/Web.UnitTests.csproj src/Web/Components/Pages/Orders.razor"])
// the seal of a proof: the test-guardian seals its tests before the fix and checks them after; the coder never seals
// its own version of them nor puts them back, and no other agent of the pack writes a test file through it. Checking
// a seal is open: the pilot does it before each commit, the coder may look
add(["test-guardian"], [S + "test-guardian.sh seal V1 tests/Api.Tests/Security/PathTraversalV1Tests.cs tests/Api.Tests/Services/ExportServiceTests.cs",
  S + "test-guardian.sh sealed V1", S + "test-guardian.sh restore V1", S + "test-guardian.sh seal S2 \"tests/Api.Tests/Invoice Tests.cs\""], "allow")
add(["coder", "pilot", ...RO], [S + "test-guardian.sh seal V1 tests/Api.Tests/Security/PathTraversalV1Tests.cs",
  S + "test-guardian.sh restore V1", "bash ~/.config/opencode/scripts/test-guardian.sh seal V1 tests/Api.Tests/X.cs",
  "cd tests && " + S + "test-guardian.sh restore V1", S + "test-guardian.sh seal V3"], "deny")
add(["coder", "pilot", "test-guardian"], [S + "test-guardian.sh sealed V1"], "allow")
add(["pilot"], [S + "test-guardian.sh sealed V2 && " + S + "ship.sh --no-push \"fix(security): path traversal in FileStore.cs (V2, ABC-123)\" \"- Fortify 4F2A\" \"- tests: 3 context, 2 vulnerability (red before, green after, twice each)\" && " + S + "ticket-sheet.sh tick 2 \"/fortify V2 - corrigée - tests 3+2 - couverture sans perte\"",
  S + "test-guardian.sh sealed S3 && " + S + "ship.sh --no-push \"fix(invoices): reject a negative discount (ABC-123)\" \"- InvoiceService: discount validated\" && " + S + "ticket-sheet.sh tick 3 \"/go étape 3 - 2 fichiers - build ok, tests 41/41\""], "allow")
add(["test-guardian", "coder", ...RO], [S + "fortify.sh discard V1", S + "ship.sh --no-push \"test: x (ABC-1)\""], "deny")
add(["test-guardian"], ["git commit -m x", "git push", "git stash", S + "workspace.sh new ABC-1", "rm -rf tests"], "deny")
add(["pilot"], [S + "fortify.sh prereq", S + "fortify.sh discard V2", S + "fortify.sh discard V3-interrupted", S + "fortify.sh batch",
  S + "branch.sh LOCAL bugfix \"Fortify Path Manipulation lot 2026-10-21\" && " + S + "workflow-state.sh --no-fetch --sheet && " + S + "fortify.sh batch",
  S + "test-guardian.sh changes origin/develop src/Api.sln", S + "test-guardian.sh changes origin/develop"], "allow")
// worktree folders are made and removed by the developer only (workspace.sh), never by an agent
add(ALL, [S + "workspace.sh new ABC-124", S + "workspace.sh remove ABC-124", S + "workspace.sh list",
  "sh $HOME/.config/opencode/scripts/workspace.sh new ABC-124"], "deny")
// a commit message or a search that names the script is not a run of it
add(["pilot"], [S + "ship.sh --no-push \"docs: explain workspace.sh in the guide (ABC-7)\""], "allow")
add(["pilot", "coder", ...RO], ["grep -n workspace.sh COMMANDES.md"], "allow")

// ---------- coder: code, tests, build; no git write, nothing that would ask ----------
const CODER_ALLOW = [
  "dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60", S + "build-test.sh", S + "build-test.sh --build-only",
  S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests", S + "package-refs.sh",
  S + "pattern-skills.sh s3-archive", S + "detect-project-type.sh", "dotnet restore", "dotnet clean",
  "dotnet format --include src/Foo.cs tests/FooTests.cs", "npx prettier --write src/app/foo.ts", "npx eslint --fix src/app/foo.ts",
  "npm test -- src/app/foo.spec.ts", "npx jest src/app/foo", "npm run build", "npx tsc --noEmit", "mkdir -p src/Features/Orders",
  "rm src/Features/Old/OldHandler.cs", "mv src/A.cs src/B.cs", "dotnet test --filter \"FullyQualifiedName~ResetPasswordTests\"",
  "dotnet add src/Api/Api.csproj reference src/Domain/Domain.csproj", "git diff", "git status --porcelain",
  "dotnet ef migrations add AddInvoiceStatus --project src/Infrastructure --startup-project src/Api",
  "dotnet ef migrations script --idempotent --project src/Infrastructure", "dotnet ef migrations has-pending-model-changes",
  "dotnet tool restore", "npx ng generate component invoices/invoice-list", "npm ci", "npx ng lint",
  "dotnet reference add src/Domain/Domain.csproj --project src/Api/Api.csproj",
  "dotnet reference remove src/Old/Old.csproj --project src/Api/Api.csproj",
  "npm run lint -- --fix", "find src -name \"*.cs\" | xargs grep -l \"IStorageService\"", "touch src/Features/Orders/.gitkeep",
  "cp src/Templates/Base.cs src/Features/Orders/OrderTemplate.cs", "rm -f src/Features/Old/OldHandler.cs",
  "chmod +x scripts/generate.sh", "dotnet build-server shutdown", "dotnet sln list",
  S + "build-test.sh src/App.sln", "dotnet test --no-build --filter \"FullyQualifiedName~Orders\" 2>&1 | tail -80",
]
add(["coder"], CODER_ALLOW, "allow")
add(["coder"], CODER_ALLOW.slice(0, 4), "allow", { sub: true, note: "as the subagent of /go" })
const CODER_DENY = [
  "git commit -m \"x\"", "git add -A && git commit -m x", "git push", "git push origin feature/x", "git merge origin/develop",
  "git pull", "git stash", "git stash push -u", "git checkout -- src/Foo.cs", "git checkout develop", "git switch develop",
  "git restore src/Foo.cs", "git reset --hard", "git reset HEAD~1", "git rebase origin/develop", "git clean -fd",
  "git cherry-pick abc", "git revert abc", "git branch -D feature/x", "git branch -d feature/x", "git tag v1",
  "git remote set-url origin https://x", "git -c core.hooksPath=/tmp commit -m x", "git -C /home/dev/repos/other push",
  "rm -rf bin obj", "rm -rf ~/.nuget/packages/inhouse.lib/1.2.0", "rm -r src/Old", "dotnet run --project src/Api",
  "dotnet tool install -g dotnet-ef", "mkdir -p /tmp/apidump", "dotnet new console -o apidump",
  "strings ~/.nuget/packages/inhouse.crypto/2.1.0/lib/net8.0/Inhouse.Crypto.dll", "ls ~/.nuget/packages/inhouse.crypto",
  "git credential fill", "security find-generic-password -s gitlab",
  // allowlist: everything that is not code, tests, build or a read is refused at once
  "curl -s https://example.com -o x", "wget https://example.com/x.zip", "dotnet add package Polly",
  "dotnet add src/Api/Api.csproj package Polly --version 8.5.0", "dotnet remove src/Api/Api.csproj package Newtonsoft.Json",
  "npm install lodash", "npm i -S axios", "yarn add dayjs", "pnpm add zod", "dotnet ef database update",
  // the lockfile is rewritten: the dependencies are installed from it by build-test.sh (npm ci)
  "npm install", "npm i", "npm install --legacy-peer-deps", "npx --yes npm@11 install", "npm update", "npm audit fix",
  "dotnet package add Polly --project src/Api/Api.csproj", "dotnet package remove Newtonsoft.Json --project src/Api/Api.csproj",
  "dotnet ef database drop --force", "dotnet ef migrations remove", "dotnet ef migrations list",
  "bash -c 'cd ~ && cat .zshenv'", "sh -c \"git push\"", "eval \"git push\"",
  "python3 -c \"print(open('x').read())\"", "node -e \"require('fs').readFileSync('x')\"", "perl -e 'print 1'",
  "aws s3 ls s3://my-bucket", "kubectl get pods", "docker ps", "glab mr list", "gh pr list", "ssh gitlab.example.com",
  "scp x host:/tmp", "sqlcmd -S server -Q \"select 1\"", "psql -c \"select 1\"",
  "printf 'x' > ~/.config/opencode/agents/coder.md", "printf '[remote origin]' >> .git/config",
  "echo 'exit 0' > .git/hooks/pre-commit", "cat src/Foo.cs | tee src/Bar.cs", "sed -i 's/a/b/' src/Foo.cs",
  "find . -name '*.log' | xargs rm", "find . -name '*.tmp' -delete", "awk '{ system($0) }' cmds.txt",
  "rm -rf src/Old", "rm -fr src/Old", "rm -r src/Old", "rm -R src/Old", "rm src/Old -r", "rm ../other-repo/x.cs",
  "dotnet test $(cat tests.txt)", "dotnet run",
  S + "ship.sh \"feat: x (ABC-1)\"", S + "ship.sh --no-push \"feat: x (ABC-1)\"", S + "branch.sh ABC-1 feature x",
  S + "ticket-sheet.sh tick 1", "npm run deploy", "npx some-random-tool", "dotnet nuget push x.nupkg",
]
add(["coder"], CODER_DENY, "deny")
// the scripts of package.json: the repository's own commands (a generated API client, a check), never what publishes,
// deploys, needs the running application or never ends; a name in the arguments is not the name of a script
add(["coder"], ["npm run generate:api", "npm run lint", "yarn run build", "pnpm run lint", "npm run build:dev", "npm run build:release",
  "npm run test -- src/app/stop-watch/stop-watch.component.spec.ts", "npm test -- src/app/release-notes/release-notes.component.spec.ts",
  "npm test -- src/app/deploy-status/deploy-status.spec.ts", "npm run lint -- --fix src/app/publish-dialog", "npm run test:ci"], "allow")
add(["coder", "test-guardian"], ["npm start", "npm run start", "npm run start:prod", "npm run dev", "npm run dev:ssr", "npm run serve:ssr",
  "npm run watch", "npm run test:e2e", "npm run e2e", "npm run cypress:open", "npm run playwright", "npm publish", "npm run release",
  "npm run deploy:prod", "npm run docker:build", "yarn run deploy", "yarn start", "pnpm dev", "pnpm run docker:build", "pnpm test:e2e",
  "yarn test:e2e", "npx some-random-tool"], "deny")
// what never ends is refused by the pack plugin, which reads what the script runs (24, tools/plugin-test.mjs): these
// names reach it
add(["coder"], ["npm run build:watch", "npm run preview", "yarn run dev", "yarn test:watch", "npm run storybook"], "allow",
  { note: "refused by the pack plugin (24): it never ends" })
add(["checker", "debugger"], ["npm run test:e2e", "yarn test:e2e", "pnpm run test:e2e"], "deny")

// ---------- pilot: /push and /sync (work outside a ticket, the commits of another computer) ----------
add(["pilot"], [S + "branch.sh --here poc \"Essai cache Redis\"", S + "branch.sh ABC-1 feature \"x\" --from feature/TEAM-9-socle",
  S + "ship.sh \"feat: try a redis cache\"", S + "ship.sh --base \"feat: try a redis cache\"", S + "ship.sh --sync-only",
  S + "ship.sh --sync-only --base", S + "ship.sh --sync-only --merge hotfix/x", S + "base.sh --why",
  "git diff --stat HEAD", "git diff HEAD -- src/Foo.cs", "git log --oneline origin/develop..HEAD"], "allow")
add(["pilot"], ["git push", "git commit -m x", "git switch -c poc/x", "git checkout -b poc/x", "git merge origin/develop",
  "git pull"], "deny")

// A path outside the repository: the pack plugin refuses the command before OpenCode would ask (tools/plugin-test.mjs);
// without the plugin, OpenCode asks (the run waits, nothing is done silently)
add(["coder"], ["rm /home/dev/notes.txt", "rm ~/notes.txt", "cp src/Foo.cs /home/dev/Foo.cs", "mkdir ~/x"], "ask",
  { note: "refused first by the plugin" })

// ---------- checker: self-review in /go, /review ----------
add(["checker"], [S + "build-test.sh", S + "build-test.sh src/App.sln", S + "detect-project-type.sh",
  S + "review-target.sh '!42' ''", "git show abc1234:src/Foo.cs", "git grep -n \"Foo\" abc1234 -- src",
  "git diff origin/develop...HEAD", "git diff HEAD", "git diff origin/develop...HEAD --stat", "npm test", "npx tsc --noEmit",
  "dotnet format --verify-no-changes", "npx eslint src/app", "npx prettier --check src/app/foo.ts"], "allow")
add(["checker"], [S + "build-test.sh", "git diff origin/develop...HEAD"], "allow", { sub: true })
add(["checker"], ["dotnet format", "npx eslint --fix src", "npx prettier --write src", "git commit -m x"], "deny")

// ---------- analyst, debugger, doc-writer ----------
add(["analyst"], [S + "workflow-state.sh --sheet", S + "detect-project-type.sh --files", "git log --oneline -20 -- src/Exports"], "allow", { sub: true })
add(["debugger"], [S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests", "dotnet test --filter \"FullyQualifiedName~FooTests\"",
  S + "compare-repos.sh --raw '/home/dev/repos/legacy-api ExportService'", "ls src/bin/Debug/net8.0/*.dll"], "allow")
add(["doc-writer"], [S + "doc-inventory.sh", S + "api-routes.sh", S + "config-keys.sh", S + "package-refs.sh", S + "detect-project-type.sh --files"], "allow", { sub: true })
add(["doc-writer"], ["cat src/Api/appsettings.json", "grep -rn Bucket src/Api/appsettings.Production.json", "cat web.config"], "deny")
add(["analyst", "doc-writer"], ["npx eslint src/app", S + "build-test.sh --build-only"].slice(0, 1), "deny")

// ---------- build: free conversation and /outil ----------
const BUILD_ALLOW = [
  S + "outil.sh --raw 'doc api'", S + "todo.sh add \"relancer Paul vendredi\"", S + "package-licenses.sh branche",
  S + "release-commits.sh /home/dev/repos/front abc1234", S + "pattern-source.sh /home/dev/repos/source-api 'DNA-1234'",
  "dotnet build", "dotnet test", "npm install", "dotnet add src/Api/Api.csproj package Polly --version 8.5.0",
  "git switch develop", "git branch -d feature/ABC-1-x", "rm docs/old/page.md",
]
add(["build"], BUILD_ALLOW, "allow")
// the diagnostics COMMANDES.md tells the developer to ask in a session, so that he never runs a script himself
add(["build"], [S + "package-refs.sh", S + "pattern-source.sh . ABC-123", S + "doc-inventory.sh", S + "api-routes.sh",
  S + "config-keys.sh", S + "diff-guard.sh", S + "build-test.sh --build-only"], "allow")
// they used to ask: refused now, since an "always" answer would have allowed them to every agent
// build may run a project of the repository (a POC, the tests of a Microsoft.Testing.Platform project); the pack
// plugin refuses a project the last commit does not hold (tools/plugin-test.mjs)
add(["build"], ["dotnet run --project src/Api", "dotnet run --project tests/App.Tests/App.Tests.csproj --no-build",
  "timeout 90 dotnet run --project src/Api"], "allow")
add(["general", "explore"], ["dotnet run --project src/Api", "dotnet run"], "deny")
// /push, /tests: the branch the developer chose, the build and tests not run again on the same code
add(["pilot"], [S + "branch.sh --here --name feature/export-csv && " + S + "ship.sh \"feat(export): add the CSV export\"",
  S + "branch.sh --here test \"unit tests of the VAT calculation\"", S + "fortify.sh prereq --tests",
  S + "build-test.sh --if-changed src/App.sln --filter \"Category!=Integration\"",
  S + "test-guardian.sh setup xunit src/Billing/VatCalculator.cs && " + S + "ship.sh --no-push \"test: add the unit test project\""], "allow")
add(["build", "coder", "test-guardian", ...RO], [S + "branch.sh --here --name feature/export-csv"], "deny")
add(["build", "coder", "checker", "debugger"], [S + "build-test.sh --if-changed"], "allow")
add(["test-guardian"], [S + "test-guardian.sh compare T1-before T1-after", S + "test-guardian.sh coverage T1-before tests/A/A.csproj src/A.cs"], "allow")
// awk, du and xargs for reading (Qwen reaches for them); the forms of awk that run, write or read the environment refused
add([...ALL, "test-guardian"], ["awk 'NR>=10 && NR<=40' src/Foo.cs", "awk -F, '{print $1}' data.csv | sort -u", "du -sh src",
  "find src -name '*.cs' | xargs grep -l 'IFoo'", "git ls-files '*.cs' | xargs wc -l | tail -1"], "allow")
// (build, the conversation the developer watches, keeps its wider rules)
add(["pilot", "coder", "test-guardian", ...RO], ["awk 'BEGIN { system(\"curl x\") }'", "awk '{ print | \"sh\" }' a.txt", "awk '{ print >\"src/x.cs\" }' a.txt",
  "awk 'BEGIN { print ENVIRON[\"HOME\"] }'", "awk -f prog.awk a.txt", "awk 'BEGIN { \"id\" | getline x }'"], "deny")
// the XML documentation of a package, in-house or public (the API of a Blazorise DataGrid), for every agent
add(ALL, [S + "package-refs.sh --doc Blazorise.DataGrid", S + "package-refs.sh --doc MudBlazor"], "allow")
add(["build"], ["git push origin feature/x", "git reset --hard HEAD~1", "git rebase origin/develop", "rm -rf docs/old",
  "rm -rf ~/.nuget/packages/inhouse.lib/1.2.0", "dotnet tool install -g dotnet-ef",
  "git commit -m \"docs: x\"", "git merge origin/develop", "git pull", "rm -r docs/old", "rm docs/old -rf"], "deny")
// git history is written by /go and /fix only, through their scripts
add(["build", "analyst", "checker", "debugger", "doc-writer", "coder"], [S + "ship.sh \"feat: x (ABC-1)\"",
  S + "ship.sh --sync-only --base", S + "branch.sh ABC-1 feature \"x\"", S + "ticket-sheet.sh decision \"x\"", S + "ship.sh --sync-only --merge hotfix/x",
  "bash ~/.config/opencode/scripts/ship.sh x", "sh $HOME/.config/opencode/scripts/ship.sh x"], "deny")
add(["build"], ["mkdir -p /tmp/apidump", "dotnet new console -o apidump", "git credential fill", "cat ~/.git-credentials"], "deny")

// ---------- read and edit tools ----------
const readCase = (agents, p, expect) => { for (const agent of agents) cases.push({ agent, read: p, expect }) }
const editCase = (agents, p, expect) => { for (const agent of agents) cases.push({ agent, edit: p, expect }) }
readCase(ALL, "src/Foo.cs", "allow")
for (const p of ["~/.nuget/NuGet/NuGet.Config", "nuget.config", "src/NuGet.Config", "appsec-ci.env", "~/.config/opencode/opencode.json", "~/.git-credentials"]) readCase(ALL, p, "deny")
readCase(ALL, "~/.local/share/opencode/tool-output/tool_abc", "allow")
for (const p of ["src/Api/.env", ".env", "src/web/.env.local", "src/web/.env.production"]) readCase([...ALL, "plan"], p, "deny")
// the registry credentials of a front-end package (an auth token in .npmrc or .yarnrc.yml)
for (const p of [".npmrc", "ClientApp/.npmrc", ".yarnrc.yml", "web/.yarnrc.yml"]) readCase(ALL, p, "deny")
readCase(ALL, "ClientApp/package.json", "allow")
readCase(["build", "pilot", "coder", "analyst", "checker", "debugger", "plan"], "src/web/.env.example", "allow")
readCase(ALL, "~/.nuget/packages/inhouse.lib/1.2.0/lib/net8.0/Inhouse.Lib.xml", "allow")
readCase(ALL.filter((a) => a !== "doc-writer"), "src/Api/appsettings.json", "allow")
readCase(["doc-writer"], "src/Api/appsettings.json", "deny")
readCase(["doc-writer"], "src/Api/appsettings.Production.json", "deny")
readCase(["build", "pilot", "coder", "debugger"], "/home/dev/repos/legacy-api/src/Exports/ExportService.cs", "ask")
// the pack's scripts: read without asking (no secret in them; asking made me answer "always" again in every project
// and after every restart), never written (the edit rules, and the plugin for the shell)
readCase([...ALL, "plan"], "~/.config/opencode/scripts/build-test.sh", "allow")
editCase(["coder", "build"], "~/.config/opencode/scripts/diff-guard.sh", "deny")
// from a worktree (an OpenCode workspace), the ticket sheets are in the git folder of the main checkout, outside it
const SHEET_OUTSIDE = "/home/dev/repos/main-api/.git/opencode-tickets/ABC-1.md"
readCase(["pilot", "analyst", "checker", "coder", "debugger"], SHEET_OUTSIDE, "allow")
editCase(["pilot", "analyst"], SHEET_OUTSIDE, "allow")
editCase(["coder", "checker", "debugger", "doc-writer", "build"], SHEET_OUTSIDE, "deny")
add(ALL, ["cat ~/.config/opencode/scripts/build-test.sh", "cd ~/.config/opencode/scripts && ls"], "allow")
editCase(["coder", "build"], "src/Foo.cs", "allow")
editCase(["coder"], "tests/App.Tests/FooTests.cs", "allow")
editCase(["coder"], "src/Api/appsettings.json", "allow")
editCase(["coder"], ".git/opencode-tickets/ABC-1.md", "deny")
editCase(["coder"], ".git/config", "deny")
editCase(["coder"], "/home/dev/repos/other/src/Foo.cs", "deny")
editCase(["coder"], "~/.config/opencode/skills/build-fix/SKILL.md", "deny")
editCase(["coder"], "~/.nuget/packages/inhouse.lib/1.2.0/lib/net8.0/Inhouse.Lib.xml", "deny")
editCase(["pilot", "analyst"], ".git/opencode-tickets/ABC-1.md", "allow")
editCase(["pilot", "analyst", "checker", "debugger", "doc-writer"], "src/Foo.cs", "deny")
editCase(["checker", "debugger", "doc-writer"], ".git/opencode-tickets/ABC-1.md", "deny")
editCase(["doc-writer"], "docs/api.md", "allow")
editCase(["doc-writer"], "README.md", "allow")
editCase(["doc-writer"], "src/Api/README.md", "deny")
editCase(["build"], "~/.config/opencode/skills/pattern-s3-archive-back/SKILL.md", "allow")
editCase(["build"], "~/.config/opencode/skills/build-fix/SKILL.md", "deny")

// ---------- delegation ----------
const taskCase = (agent, t, expect) => cases.push({ agent, task: t, expect })
for (const t of ["analyst", "coder", "checker", "debugger"]) taskCase("pilot", t, "allow")
for (const t of ["general", "explore", "doc-writer", "build", "pilot"]) taskCase("pilot", t, "deny")
for (const a of ["analyst", "coder", "checker", "debugger", "doc-writer"]) taskCase(a, "general", "deny")
for (const t of ["doc-writer", "debugger", "coder", "general"]) taskCase("build", t, "allow")

// ---------- questions: only the pilot (ticket choice, blocking questions), the debugger (/compare) and build ----------
const questionCase = (agent, expect, extra = {}) => cases.push({ agent, tool: "question", expect, ...extra })
for (const a of ["pilot", "debugger", "build"]) questionCase(a, "allow")
for (const a of ["analyst", "coder", "checker", "doc-writer"]) questionCase(a, "deny")
// as a subagent of /go or /fix, nobody answers: experimental.primary_tools removes the tool
for (const a of ["debugger", "analyst", "coder", "checker", "doc-writer"]) questionCase(a, "deny", { sub: true })

// ---------- a loop (same tool call three times) is refused, never asked ----------
for (const a of ["build", "pilot", "analyst", "coder", "checker", "debugger", "doc-writer"]) {
  for (const t of ["bash", "read", "edit", "task"]) cases.push({ agent: a, perm: "doom_loop", pattern: t, expect: "deny" })
}

// ---------- every command the pack prescribes, run by the agent it prescribes it to (commands, agents, skills,
// AGENTS.global.md: tools/prescribed inventory). A refusal here is a run that stops on a rule of the pack itself. ----------
const P = (agents, cmds) => add(agents, cmds, "allow", { note: "prescribed by the pack" })
// ---------- the API tests, the environments, the .http files and the schedules ----------
P(["pilot"], [S + "api-routes.sh", S + "api-routes.sh src/Api/Features/Orders", S + "environments.sh",
  S + "env-tests.sh recette", S + "env-tests.sh recette --ecriture",
  S + "test-guardian.sh setup --integration xunit src/Api/Api.csproj && " + S + "ship.sh --no-push \"test: add the integration test project\""])
P(["test-guardian"], [S + "env-tests.sh recette"])
add(["debugger", "checker"], [S + "env-tests.sh recette", S + "environments.sh"], "allow")
add(["coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"],
  [S + "env-tests.sh recette --ecriture", S + "env-tests.sh recette --écriture", S + "env-tests.sh recette --allow-writes"], "deny")
add(["pilot", "coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"],
  [S + "schedule.sh add 8h45 lun-ven /daily", S + "schedule.sh remove 2", S + "http-files.sh", S + "http-files.sh src/Api"], "deny")
add(["build"], [S + "schedule.sh --raw \"8h45 lun-ven /daily\"", S + "schedule.sh", S + "http-files.sh",
  S + "env-tests.sh recette --ecriture", S + "environments.sh"], "allow")

// ---------- the wizards: /tests (its facts, the setup of /tests api, the access of an environment), /outil liens,
// /outil http, /outil planifier ----------
const ENV_SET = S + "env-setup.sh set recette --url https://api-recette.example.com --oidc https://login.example.com/realms/acme --client-var --scope \"api://acme-api/.default\" --proxy http://proxy.example.com:8080 --proxy-auth --health /health ; " + S + "env-tests.sh --check recette"
const LIENS = S + "related-setup.sh apply front-factures ~/repos/front-factures \"le front Angular qui appelle cette API\" --reference --reciprocal \"l'API .NET que ce front appelle\" && " + S + "related-setup.sh apply lib-montants ~/repos/lib-montants \"la librairie Acme.Montants que ce dépôt utilise\""
P(["pilot"], [S + "tests.sh --raw \"api OrdersController\"", S + "api-preflight.sh", S + "api-preflight.sh src/Api/Features/Orders",
  S + "env-tests.sh --check recette", S + "env-tests.sh --discover recette", ENV_SET,
  S + "env-setup.sh set prod --url https://api.example.com --production",
  S + "env-setup.sh set preprod --url https://api-preprod.example.com --token-var --proxy none ; " + S + "env-tests.sh --check preprod",
  S + "env-tests.sh recette --filter \"FullyQualifiedName~OrdersEnvironmentTests\"",
  S + "test-guardian.sh setup --integration --db sqlite xunit src/Api/Api.csproj && " + S + "ship.sh --no-push \"test: add the integration test project\"",
  S + "test-guardian.sh setup --integration --db sqlite xunit src/Api/Api.csproj && " + S + "ship.sh --no-push \"test: add SQLite to the integration test project\""])
P(["test-guardian"], [S + "env-tests.sh --check recette", S + "api-preflight.sh"])
P(["build"], [LIENS, S + "related-setup.sh scan", S + "related-setup.sh remove lib-montants --reference",
  S + "http-files.sh --plan", S + "http-files.sh --only Orders,Customers --replace --client vs src/Api",
  S + "schedule.sh add 8h45 lun-ven /daily ; " + S + "schedule.sh remove 2", ENV_SET])
add(["analyst", "checker", "debugger", "doc-writer"], [S + "api-preflight.sh", S + "tests.sh --raw \"env\"", S + "env-tests.sh --check recette"], "allow")
// what writes AGENTS.md or opencode.json: never an agent of a run but the pilot of /tests for its environments
add(["coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"],
  [ENV_SET, S + "env-setup.sh scan", S + "env-setup.sh remove recette"], "deny")
add(["pilot", "coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"],
  [LIENS, S + "related-setup.sh scan", S + "related-setup.sh apply x ~/repos/x \"r\"", S + "http-files.sh --plan"], "deny")

// /go, /fix, /fortify, /push, /sync, /tests: the pilot
P(["pilot"], [
  S + "ticket-sheet.sh suivi \"/go - reprise à l'étape 2\"",
  S + "branch.sh ABC-123 feature \"Export CSV des factures\" --from feature/ABC-100-socle && " + S + "workflow-state.sh --no-fetch --sheet",
  S + "branch.sh ABC-123 feature \"Export CSV des factures\" --from feature/ABC-100-socle",
  S + "build-test.sh src/App.sln", S + "build-test.sh", S + "ticket-sheet.sh check",
  S + "ticket-sheet.sh decision \"Base : feature/ABC-100-socle au lieu de develop (consigne du dev)\"",
  S + "ticket-sheet.sh suivi \"/go - base develop : build ok - tests 12/12 - en échec avant le ticket : aucun\"",
  S + "test-guardian.sh setup xunit src/Billing/VatCalculator.cs && " + S + "ship.sh --no-push \"test: add the unit test project (ABC-123)\" \"- SETUP: tests/App.UnitTests\"",
  S + "test-guardian.sh green tests/App.Tests/App.Tests.csproj FullyQualifiedName~InvoiceServiceTests",
  S + "test-guardian.sh sealed S2 && " + S + "ship.sh --no-push \"fix(billing): round the VAT per line (ABC-123)\" \"- src/Billing: VatCalculator\" && " +
    S + "ticket-sheet.sh tick 2 \"/go étape 2 - 2 fichiers - build ok, tests 14/14\" && " + S + "ticket-sheet.sh decision \"Arrondi : par ligne — comme la facture papier (étape 2)\"",
  // /go and /fix: the unit tests of a repository that has none, or no coverage collector, asked before any fix
  S + "fortify.sh prereq --tests",
  S + "test-guardian.sh setup xunit src/Billing/Invoice.cs && " + S + "ship.sh --no-push \"test: add the coverage collector to the unit test projects (ABC-123)\" \"- SETUP: coverlet.collector 6.0.4 added to tests/App.Tests/App.Tests.csproj; build OK\"",
  S + "test-guardian.sh setup nunit src/Billing/Invoice.cs src/Billing/Vat.cs && " + S + "ship.sh --no-push \"test: add the unit test project\" \"- SETUP: tests/App.UnitTests/App.UnitTests.csproj created (nunit, net10.0)\"",
  S + "ticket-sheet.sh decision \"Tests unitaires : projet App.UnitTests créé (réponse du dev)\"",
  S + "ticket-sheet.sh decision \"Tests unitaires : aucun projet, correctifs sans test ni filet (réponse du dev)\"",
  // /go: a step « (filet d'abord) », committed with its net
  S + "test-guardian.sh sealed S3 && " + S + "ship.sh --no-push \"refactor(billing): compute the discount in one expression (ABC-123)\" \"- src/Billing: Invoice\" \"- safety net: 0% -> 100% of the lines of 1 methods\" && " +
    S + "ticket-sheet.sh tick 3 \"/go étape 3 - 1 fichiers - build ok, tests 17/17 - filet 0 -> 100 %\"",
  S + "package-refs.sh --doc Blazorise.DataGrid",
  S + "test-guardian.sh changes origin/develop src/App.sln", "git diff origin/develop...HEAD", "git diff --stat origin/develop...HEAD",
  S + "ship.sh --sync-only --base", S + "ship.sh --sync-only --base --merge hotfix/ABC-130-urgent",
  S + "ship.sh \"feat(billing): export the invoices as CSV (ABC-123)\"",
  S + "ticket-sheet.sh suivi \"/go - livré - MR https://gitlab.example.com/g/p/-/merge_requests/42 - build ok - tests 14/14 - auto-review ok\"",
  S + "workflow-state.sh --no-fetch --sheet",
  // /fix
  S + "test-guardian.sh park F1 && " + S + "test-guardian.sh park F2", S + "fortify.sh discard F1",
  S + "test-guardian.sh unpark F2 && " + S + "ship.sh --no-push \"test(security): show that path manipulation in FileStore.cs is not exploitable (ABC-123)\"",
  S + "test-guardian.sh unpark F2 && " + S + "test-guardian.sh red tests/App.Tests/App.Tests.csproj FullyQualifiedName~Security_PathManipulation_F2",
  S + "test-guardian.sh sealed F2 && " + S + "ship.sh --no-push \"fix(security): path manipulation in FileStore.cs (ABC-123)\" \"- tests: 3 context, 2 vulnerability (red before, green after, twice each)\" \"- safety net: 20% -> 100% of the lines of 2 methods\"",
  // /fix: the bugs with their net and their proof, the groups with a net
  S + "test-guardian.sh park F1 && " + S + "test-guardian.sh park B2", S + "fortify.sh discard B2 N1",
  S + "test-guardian.sh unpark B2 && " + S + "test-guardian.sh red tests/App.Tests/App.Tests.csproj \"FullyQualifiedName~InvoiceTests.Discount_Negative\"",
  S + "test-guardian.sh sealed B2 && " + S + "ship.sh --no-push \"fix(billing): keep the amount of a negative discount (ABC-123)\" \"- tests: 2 context, 1 bug (red before, green after, twice each)\" \"- safety net: 40% -> 100% of the lines of 2 methods\"",
  S + "test-guardian.sh sealed N1 && " + S + "ship.sh --no-push \"fix(billing): split the VAT computation (ABC-123)\" \"- safety net: 50% -> 90% of the lines of 3 methods\" && " + S + "ticket-sheet.sh decision \"Découpage : une méthode par taux — demande de la review (/fix)\"",
  S + "ship.sh --no-push \"fix(billing): address the review (ABC-123)\" && " + S + "ticket-sheet.sh decision \"Nommage : Total plutôt que Sum — demande de la review (/fix)\"",
  "git diff abc1234..HEAD", S + "ship.sh --base \"fix(billing): address the CI, scan and review feedback (ABC-123)\"",
  // /fix: a pause while the CI of the pushed commit runs, then the pipeline again
  S + "pause.sh 100", S + "pause.sh 60",
  // /go and /fix: the full suite once more, before a coder round on tests that failed in it (unstable or not)
  S + "build-test.sh src/App.sln --filter \"Category!=Integration\"",
  S + "ticket-sheet.sh suivi \"/fix - 3 corrigés, 1 réponses, 0 hors périmètre - build ok - tests 14/14\"",
  // /fortify
  S + "test-guardian.sh park V2", S + "fortify.sh discard reprise", S + "fortify.sh discard V1 V2",
  S + "branch.sh LOCAL bugfix \"Fortify Path Manipulation lot 2026-10-24\" && " + S + "workflow-state.sh --no-fetch --sheet && " + S + "fortify.sh batch",
  S + "test-guardian.sh unpark V2 && " + S + "ship.sh --no-push \"test(security): show that path manipulation in FileStore.cs is not exploitable (V2, LOCAL-3)\" \"- Fortify 4512\" && " +
    S + "ticket-sheet.sh tick 2 \"/fortify V2 - non exploitable - tests 3 - à déclarer dans SSC par toi\"",
  S + "test-guardian.sh unpark V2 && " + S + "test-guardian.sh red tests/App.Tests/App.Tests.csproj FullyQualifiedName~Security_PathManipulation_V2",
  // /push
  "git status --porcelain", "git diff --stat HEAD", "git log --oneline @{upstream}..HEAD",
  "git diff HEAD -- src/Billing/VatCalculator.cs src/Billing/Invoice.cs | head -300",
  S + "build-test.sh --if-changed src/App.sln --filter \"Category!=Integration\"", S + "build-test.sh --if-changed",
  S + "branch.sh --here --name feature/export-csv && " + S + "ship.sh --base \"feat(export): add the CSV export\"",
  S + "ship.sh \"docs: explain the export settings\"", "git log --oneline origin/develop..HEAD",
  // /tests
  "git grep -l \"Billing.csproj\" -- '*Tests*.csproj' '*Test*.csproj'", S + "branch.sh --here test \"unit tests of the VAT calculation\"",
  S + "test-guardian.sh tests-only && " + S + "ship.sh --no-push \"test(billing): add unit tests of the VAT calculation\" \"- 12 tests; coverage VatCalculator.cs 40% -> 92%\"",
  S + "test-guardian.sh green tests/App.Tests/App.Tests.csproj \"FullyQualifiedName~VatCalculatorTests\"",
])
add(["pilot", "coder", "test-guardian", ...RO], [S + "abandon.sh", S + "abandon.sh --check"], "deny")
// the subagents of the runs
P(["coder"], [
  S + "pattern-skills.sh", S + "package-refs.sh --doc Blazorise.DataGrid", S + "package-refs.sh",
  S + "test-guardian.sh green tests/App.Tests/App.Tests.csproj FullyQualifiedName~InvoiceServiceTests",
  S + "test-guardian.sh green tests/App.Tests/App.Tests.csproj \"FullyQualifiedName~Security_PathManipulation_V1|FullyQualifiedName~PathServiceContextTests\"",
  "dotnet format --include src/Billing/VatCalculator.cs", "npx prettier --write src/app/invoice.ts", "npx eslint --fix src/app/invoice.ts",
  S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceServiceTests", S + "build-test.sh --build-only src/App.sln",
  S + "build-test.sh tests/App.Tests/App.Tests.csproj",
  "dotnet ef migrations add AddInvoiceStatus --project src/Infrastructure --startup-project src/Api", "dotnet ef migrations list --no-connect",
  "dotnet add src/Api/Api.csproj reference src/Billing/Billing.csproj", "npm ci", "dotnet restore --force --no-cache",
  S + "detect-project-type.sh", "npm run build",
])
P(["test-guardian"], [
  S + "test-guardian.sh deps src/Billing/FileStore.cs", S + "test-guardian.sh coverage V2-before tests/App.Tests/App.Tests.csproj src/Billing/FileStore.cs",
  S + "test-guardian.sh net V2-before src/Billing/FileStore.cs:Read src/Billing/FileStore.cs:FileStore.Open",
  S + "test-guardian.sh coverage V2-net tests/App.Tests/App.Tests.csproj src/Billing/FileStore.cs", S + "test-guardian.sh net S3-net --min 70 src/Billing/Invoice.cs:Discount",
  S + "test-guardian.sh seal N1", S + "test-guardian.sh seal B2 tests/App.Tests/InvoiceDiscountTests.cs tests/App.Tests/InvoiceTests.cs",
  S + "test-guardian.sh red tests/App.Tests/App.Tests.csproj FullyQualifiedName~Security_PathManipulation_V2",
  S + "test-guardian.sh green tests/App.Tests/App.Tests.csproj FullyQualifiedName~Security_PathManipulation_V2",
  S + "test-guardian.sh seal V2 tests/App.Tests/Security/FileStoreTests.cs", S + "test-guardian.sh seal V3", S + "test-guardian.sh sealed V2", S + "test-guardian.sh restore V2",
  S + "test-guardian.sh compare V2-before V2-after", S + "test-guardian.sh tests-only", S + "test-guardian.sh build tests/App.Tests/App.Tests.csproj",
  S + "test-guardian.sh changes origin/develop", "git grep InternalsVisibleTo",
])
P(["coder"], [S + "build-test.sh ClientApp", S + "build-test.sh ClientApp --filter src/app/invoice/invoice.component.spec.ts",
  S + "build-test.sh --build-only ClientApp", S + "build-test.sh --pack", S + "build-test.sh --build-only --pack src/Billing/Billing.csproj",
  S + "test-lint.sh tests/App.Tests/VatCalculatorTests.cs ClientApp/src/app/invoice/invoice.component.spec.ts", S + "test-lint.sh --changed origin/develop",
  "npm run generate:api"])
P(["test-guardian"], [S + "test-lint.sh tests/App.Tests/Security/FileStoreTests.cs", S + "test-lint.sh --changed origin/develop"])
P(["pilot"], [S + "build-test.sh src/App.sln --filter \"Category!=Integration\" ; " + S + "build-test.sh ClientApp",
  S + "test-guardian.sh changes origin/develop src/App.sln ; " + S + "build-test.sh --build-only --pack ; " + S + "build-test.sh ClientApp",
  S + "build-test.sh --if-changed src/App.sln ; " + S + "build-test.sh --if-changed ClientApp", S + "build-test.sh --build-only --pack"])
P(["pilot"], [S + "related-repos.sh ABC-123", S + "related-repos.sh", S + "api-surface.sh origin/develop", S + "test-lint.sh --changed origin/develop",
  S + "build-test.sh --if-changed --pack", S + "build-test.sh --if-changed ClientApp", S + "build-test.sh ClientApp", S + "build-test.sh --pack src/App.sln"])
P(["analyst"], [S + "pattern-skills.sh", S + "package-refs.sh --doc Blazorise.DataGrid", S + "detect-project-type.sh",
  S + "related-repos.sh ABC-123", S + "api-surface.sh origin/develop"])
P(["checker"], [S + "api-surface.sh origin/develop", S + "test-lint.sh --changed origin/develop", S + "build-test.sh ClientApp", S + "related-repos.sh ABC-123",
  S + "review-target.sh '!42' ''", S + "api-surface.sh origin/develop abc1234", S + "test-lint.sh --changed origin/develop abc1234"])
P(["build"], [S + "build-test.sh --build-only ClientApp", S + "build-test.sh src/App.sln ; " + S + "build-test.sh ClientApp"])
P(["checker"], ["git diff origin/develop...HEAD", "git diff HEAD", "git diff --stat", "git diff -U10 origin/develop...HEAD -- src/Billing/VatCalculator.cs",
  S + "detect-project-type.sh", "git show abc1234:src/Billing/VatCalculator.cs", "git grep -n IStorageService abc1234 -- src/Billing/VatCalculator.cs"])
P(["debugger"], [S + "build-test.sh ClientApp --filter src/app/cart/cart.service.spec.ts", S + "detect-project-type.sh"])
P(["debugger"], ["git log --oneline -15", "git log -5 --format='%h %an %s' -- src/Billing/VatCalculator.cs | head -20", S + "detect-project-type.sh",
  S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~Total_WithVat_Rounds"])
P(["doc-writer"], [S + "doc-inventory.sh", S + "api-routes.sh", S + "config-keys.sh", S + "package-refs.sh", S + "detect-project-type.sh --files"])
// the conversation (build) and the procedures of /outil, run by build
P(["build"], [
  "realpath ~", S + "package-refs.sh --doc Blazorise.DataGrid", S + "build-test.sh src/App.sln --filter \"Category!=Integration\"",
  S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~InvoiceServiceTests", S + "build-test.sh --build-only src/App.sln",
  "dotnet run --project src/Api", "timeout 60 dotnet run --project src/Api", S + "todo.sh add \"call Paul on Friday\"", S + "todo.sh", S + "todo.sh due",
  S + "related-repos.sh", S + "build-test.sh ClientApp", S + "test-lint.sh --changed origin/develop", S + "api-surface.sh origin/develop",
  S + "detect-project-type.sh", S + "workflow-state.sh --no-fetch",
  // /outil abandon: its script checks that the branch holds nothing, then deletes it and its sheet
  S + "abandon.sh --check", S + "abandon.sh",
  // /outil vitesse: where the time of the last runs went (it only reads the measures of the plugin)
  S + "vitesse.sh", S + "vitesse.sh 30 go",
  // /outil licences, release-notes, setup, doc, cqrs; build-fix
  "dotnet nuget why src/App.sln Newtonsoft.Json", "git rev-parse --verify origin/master",
  "git log --first-parent --merges --format=%h%x09%cs%x09%s origin/master..origin/develop",
  "git log --no-merges --format=%h%x09%an%x09%s origin/master..origin/develop",
  "git diff --stat abc1234..HEAD -- '*.sln' '*.slnx' '*.csproj' 'Directory.*.props' 'global.json' '.editorconfig' '.gitlab-ci.yml' 'package.json'",
  "git log --oneline abc1234..HEAD | head -30", "git log --oneline -30 origin/develop", "npm test -- --watch=false --browsers=ChromeHeadless",
  "npx vitest run", S + "detect-project-type.sh --files", S + "doc-inventory.sh", S + "api-routes.sh", S + "config-keys.sh", "npm run build",
  "dotnet restore --force --no-cache",
])

// ---------- MCP (tool names "<server>_<tool>") ----------
const tool = (agent, name, expect) => cases.push({ agent, tool: name, expect })
for (const t of ["gitlab_create_merge_request", "jira_get_issue", "jira_search", "confluence_get_page", "gitlab_get_merge_request",
  "gitlab_list_merge_request_discussions", "gitlab_get_pipeline", "sonar_search_issues", "fortify_list_issues"]) tool("pilot", t, "allow")
for (const t of ["gitlab_create_merge_request_note", "gitlab_create_issue", "gitlab_update_merge_request", "gitlab_merge_merge_request",
  "gitlab_approve_merge_request", "jira_add_comment", "jira_transition_issue", "jira_create_issue", "jira_update_issue",
  "confluence_create_page", "sonar_change_issue_status", "fortify_set_issue_suppressed", "kibana_search"]) tool("pilot", t, "deny")
for (const t of ["jira_get_issue", "confluence_get_page", "gitlab_get_file"]) tool("analyst", t, "allow")
for (const t of ["gitlab_create_merge_request", "sonar_search_issues", "jira_add_comment"]) tool("analyst", t, "deny")
for (const t of ["jira_get_issue", "gitlab_get_merge_request", "sonar_search_issues"]) tool("coder", t, "deny")
tool("checker", "jira_get_issue", "allow")
tool("checker", "gitlab_get_merge_request", "deny")
tool("doc-writer", "confluence_get_page", "deny")
tool("doc-writer", "confluence_create_page", "deny")
for (const t of ["confluence_create_page", "confluence_update_page", "confluence_upload_attachment"]) tool("build", t, "ask")

// ---------- OpenCode v2: code mode (JavaScript that calls any address), the web search, the tools that move a session
// or create a worktree (also by their code mode names), and the built-in skill that publishes a GitHub issue ----------
for (const a of [...ALL, "plan", "test-guardian"]) {
  for (const t of ["execute", "websearch", "opencode_session_move", "opencode_worktree_create", "opencode_worktree_remove",
    "session_move", "worktree_create", "worktree_remove"]) tool(a, t, "deny")
  cases.push({ agent: a, perm: "skill", pattern: "report", expect: "deny" })
  cases.push({ agent: a, perm: "skill", pattern: "best-practices", expect: "allow" })
}
for (const t of ["jira_create_issue", "jira_add_comment", "gitlab_create_merge_request", "jira_update_issue"]) tool("build", t, "deny")
tool("build", "jira_get_issue", "allow")

// ---------- the secrets of the HTTP clients that /outil http prepares, and the clients of secret stores ----------
// Rider keeps the client secret and the tokens in http-client.private.env.json, Visual Studio in http-client.env.json.user:
// in the repository (ignored by git), never read by an agent, through the read tool or the shell
for (const p of ["src/Api/http/http-client.private.env.json", "http/http-client.private.env.json", "src/Api/http/http-client.env.json.user"]) {
  readCase([...ALL, "plan", "test-guardian"], p, "deny")
}
add([...ALL, "test-guardian"], ["cat src/Api/http/http-client.private.env.json", "grep -n clientSecret src/Api/http/http-client.private.env.json",
  "head -5 http/http-client.private.env.json", "cat src/Api/http/http-client.env.json.user", "jq . http/http-client.private.env.json"], "deny")
// a secret printed by the client of a secret store would reach the model server and the session history: refused to the
// conversation agents as well (env-tests.sh and http-files.sh --private read a Vault secret themselves, never printed)
const SECRET_CLIS = ["vault kv get secret/recette/api", "vault kv get -field=client_secret secret/recette/api", "vault read secret/x",
  "vault token lookup", "op read op://Dev/recette/secret", "op item get recette", "bw get password recette",
  "az keyvault secret show --vault-name kv-acme --name client-secret", "aws secretsmanager get-secret-value --secret-id recette/api",
  "aws ssm get-parameter --name /recette/api/secret --with-decryption", "gcloud secrets versions access latest --secret=api-secret",
  "kubectl get secret api -o yaml", "kubectl get secrets -n recette -o json", "kubectl describe secret api", "doppler secrets get API_KEY",
  "sops -d secrets.enc.yaml", "gh auth token", "glab auth status --show-token", "glab config get token",
  "npm config get //registry.npmjs.org/:_authToken", "yarn config get npmAuthToken", "dotnet nuget config get all"]
add([...ALL, "general", "explore", "test-guardian"], SECRET_CLIS, "deny")
// the procedures of /outil (skills pack-*) are the conversation's: hidden from the agents of the pack, which keep the
// skills of their work
for (const a of ["pilot", "analyst", "coder", "test-guardian", "checker", "debugger", "doc-writer"]) {
  for (const s of ["pack-http", "pack-carte", "pack-setup"]) cases.push({ agent: a, perm: "skill", pattern: s, expect: "deny" })
  for (const s of ["blazorise", "automapper", "api-tests", "fortify-remediation"]) cases.push({ agent: a, perm: "skill", pattern: s, expect: "allow" })
}
cases.push({ agent: "build", perm: "skill", pattern: "pack-http", expect: "allow" })
cases.push({ agent: "build", perm: "skill", pattern: "pack-carte", expect: "allow" })
// Blazorise replaced by native Razor: the inventory and the check of what is left only read; the native components
// are production code, written by the coder (and the conversation), never by an agent that reads or by the test-guardian
P(["analyst"], [S + "blazor-native.sh inventory"])
P(["coder"], [S + "blazor-native.sh scaffold src/Web", S + "blazor-native.sh check"])
P(["checker"], [S + "blazor-native.sh check"])
add(["build"], [S + "blazor-native.sh inventory", S + "blazor-native.sh scaffold src/Web", S + "blazor-native.sh check"], "allow")
add(["debugger", "pilot"], [S + "blazor-native.sh inventory", S + "blazor-native.sh check"], "allow")
add(["pilot", "analyst", "checker", "debugger", "doc-writer", "test-guardian"], [S + "blazor-native.sh scaffold src/Web"], "deny")
// AutoMapper replaced by Mapperly: the inventory and the check only read; Mapperly in a project is a package, set up by
// the pilot once the developer agreed; the snapshot tests and their golden files written from AutoMapper are the
// test-guardian's (the coder never writes a golden file from its own mapper); the skeleton of a mapper is production
// code, the coder's
P(["analyst"], [S + "mapperly.sh inventory"])
P(["pilot"], [S + "mapperly.sh setup src/Shop/Shop.csproj && " + S + "ship.sh --no-push \"build: add Mapperly (ABC-123)\" \"- SETUP: Riok.Mapperly 4.3.1 added to src/Shop/Shop.csproj, compile time only; build OK\""])
P(["test-guardian"], [S + "mapperly.sh helpers tests/Shop.Tests/Shop.Tests.csproj", S + "mapperly.sh record tests/Shop.Tests/Shop.Tests.csproj"])
P(["coder"], [S + "mapperly.sh scaffold src/Shop/Mapping/OrderProfile.cs", S + "mapperly.sh check"])
P(["checker"], [S + "mapperly.sh check"])
add(["build"], [S + "mapperly.sh inventory", S + "mapperly.sh setup src/Shop", S + "mapperly.sh scaffold src/Shop/Mapping/OrderProfile.cs",
  S + "mapperly.sh helpers tests/Shop.Tests/Shop.Tests.csproj", S + "mapperly.sh record tests/Shop.Tests/Shop.Tests.csproj", S + "mapperly.sh check"], "allow")
add(["debugger", "pilot", "test-guardian"], [S + "mapperly.sh inventory", S + "mapperly.sh check"], "allow")
add(["pilot", "analyst", "checker", "debugger", "doc-writer", "test-guardian"], [S + "mapperly.sh scaffold src/Shop/Mapping/OrderProfile.cs"], "deny")
add(["coder", "analyst", "checker", "debugger", "doc-writer", "test-guardian"], [S + "mapperly.sh setup src/Shop"], "deny")
add(["coder", "pilot", "analyst", "checker", "debugger", "doc-writer"], [S + "mapperly.sh record tests/Shop.Tests/Shop.Tests.csproj",
  S + "mapperly.sh helpers tests/Shop.Tests/Shop.Tests.csproj"], "deny")
// /fix waits for the CI of its push in fewer, longer pauses
P(["pilot"], [S + "pause.sh 240"])
// an environment whose secret is in HashiCorp Vault (env-setup.sh --vault), and the private file of the HTTP client filled
// from the variables of this machine or from Vault (http-files.sh --private: the developer's, in the conversation)
P(["pilot"], [S + "env-setup.sh set recette --url https://api-recette.example.com --oidc https://login.example.com/realms/acme --client shop-tests --vault secret/recette/api#client_secret ; " + S + "env-tests.sh --check recette"])
add(["build"], [S + "env-setup.sh set recette --url https://api-recette.example.com --token-var --vault secret/recette/api#token",
  S + "http-files.sh --private", S + "http-files.sh --private src/Api"], "allow")
add(["pilot", "coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"], [S + "http-files.sh --private"], "deny")

// ---------- nothing an autonomous agent is told to run may ask ----------
add(["pilot"], [S + "ship.sh --base \"feat(export): add the PDF export (ABC-123)\""], "allow", { note: "never asks: the run is unattended" })
