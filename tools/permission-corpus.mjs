// Commands the pack instructs (commands, skills, agents, AGENTS.global) and the reflexive ones a model reaches for,
// with the expected decision per agent. "allow" = runs without asking, "ask" = asks me, "deny" = refused.
const S = "sh ~/.config/opencode/scripts/"
const RO = ["reviewer", "test-writer", "analyst", "architect", "debugger", "release-writer"]
const ALL = ["build", "dev", "git", ...RO]

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
  "cd src && ls", "realpath src",
  // search strings with C# generics and lambdas (">" inside quotes is not a redirection)
  "git grep -n \"List<Order>\" abc1234 -- src", "grep -rn \"x => x.Id\" src", "git grep -n \"Task<IActionResult>\" -- '*.cs'",
  "git show abc1234:src/Foo.cs | grep -n \"Dictionary<string, List<int>>\"",
  // kebab-case paths and folders that contain words of the old substring rules
  "git diff -- src/app/auth/reset-password/reset-password.component.ts", "git log --oneline -- src/app/user-delete/",
  "git log -- src/app/job-executor/x.ts", "git diff -- src/app/used-items/x.ts", "git diff HEAD -- src/app/secret-santa/x.ts",
  "git log -- src/Infrastructure/credentials/", "git diff -- config/appsettings.json", "git log --oneline -- push-notifications/",
  "git diff -- src/app/api-key-form/x.ts",
  "dotnet nuget why src/App.sln Newtonsoft.Json",
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
  "rm src/Foo.cs", "mv a b", "cp a b", "touch x", "mkdir x", "awk '{print $1}' f", "xargs rm",
  "git log $(git merge-base HEAD origin/develop)..HEAD", "npm install", "curl https://example.com",
  "git reflog expire --expire=now --all", "git tag -d v1",
]

export const cases = []
const add = (agents, cmds, expect, extra = {}) => {
  for (const agent of agents) for (const cmd of cmds) cases.push({ agent, cmd, expect, ...extra })
}
add(ALL, READS, "allow")
add(ALL, SECRETS, "deny")
add(RO, RO_DENY, "deny")

// ---------- build / dev (build agent's freedom, minus secrets) ----------
const DEV = [
  "dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60", S + "build-test.sh", S + "build-test.sh src/App.sln",
  S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests", S + "build-test.sh --build-only",
  "dotnet restore", "dotnet restore --force --no-cache", "dotnet add src/Api/Api.csproj package Polly --version 8.5.0",
  "dotnet new xunit -o tests/App.Tests", "dotnet sln add tests/App.Tests/App.Tests.csproj", "npm install", "npm run build",
  "npm test -- src/app/foo.spec.ts", "mkdir -p src/Features/Orders", "git -C /home/dev/repos/other log --oneline -20 -- src/Health",
  "dotnet test --filter \"FullyQualifiedName~ResetPasswordTests\"", "git diff -- src/app/reset-password/x.ts",
  "git commit -m \"fix(security): remove hardcoded password (ABC-1)\"", "git -c core.quotePath=false status",
  S + "detect-project-type.sh", S + "workflow-state.sh --sheet", S + "review-target.sh '!42' ''",
  S + "release-commits.sh /home/dev/repos/front abc1234", S + "package-licenses.sh --diff",
  "dotnet test --no-build 2>&1 | tail -80", "node --version", "npx tsc --noEmit",
]
add(["build", "dev"], DEV, "allow")
add(["build", "dev"], ["rm -rf ~/.nuget/packages/inhouse.lib/1.2.0", "git push origin feature/x", "git reset --hard HEAD~1", "git rebase origin/develop"], "ask")

// ---------- git agent: /ticket, /sync, /ship, /next, /abandon ----------
const GIT_ALLOW = [
  "git add -A && git diff --staged --stat && git diff --staged", "git add -u && git diff --staged --stat && git diff --staged",
  "git add src/Foo.cs \"src/Bar Baz.cs\" && git diff --staged --stat && git diff --staged",
  "git commit -m \"feat(export): add PDF export (ABC-123)\" -m \"- add exporter\n- add tests\" && git fetch -q origin && git rev-list --left-right --count HEAD...origin/feature/ABC-123-pdf-export",
  "git commit -m \"fix(security): remove hardcoded password from the DocuSign client (ABC-9)\" -m \"- read the secret from configuration\"",
  "git commit -m \"fix(auth): read DOCUSIGN_SECRET and API_TOKEN from the environment (ABC-9)\"",
  "git commit -m \"fix(ui): reset-password form (ABC-7)\" && git fetch -q origin && git rev-list --left-right --count HEAD...origin/feature/ABC-7-reset-password",
  "git merge --ff-only origin/feature/ABC-123-pdf-export", "git fetch -q origin && git merge --ff-only origin/develop",
  "git fetch -q origin && git rev-list --left-right --count HEAD...origin/develop && git log --oneline -15 HEAD..origin/develop && git rev-list --left-right --count HEAD...origin/feature/ABC-1-x",
  "git diff --name-only --diff-filter=U", "git merge --abort", "git commit --no-edit",
  "git log --oneline origin/develop..HEAD && git diff --stat origin/develop...HEAD",
  "git switch feature/ABC-1-x", "git switch feature/ABC-1-x && " + S + "workflow-state.sh --sheet",
  "git fetch -q origin develop && git switch -c feature/ABC-1-pdf-export origin/develop",
  "git fetch -q origin develop && git switch -c feature/ABC-2-reset-password-secret-token origin/develop",
  "git switch develop && git merge --ff-only origin/develop", "git restore --staged src/Foo.cs",
  S + "workflow-state.sh", S + "workflow-state.sh --sheet --tickets", S + "detect-project-type.sh",
]
add(["git"], GIT_ALLOW, "allow")
const GIT_ASK = [
  "git merge --no-edit origin/feature/ABC-1-x", "git merge --no-edit origin/develop", "git merge origin/develop",
  "git push -u origin feature/ABC-1-x", "git push -u origin feature/ABC-2-reset-password", "git stash push -u -m \"sync\"",
  "git stash push -u -m \"ticket ABC-1\"", "git stash push -u -m \"next feature/ABC-1-x\"", "git stash pop", "git stash",
  "git pull", "git commit --amend --no-edit", "git commit -m \"x\" --amend",
  "git branch -d feature/ABC-1-x", "rm .git/opencode-tickets/ABC-1.md",
]
add(["git"], GIT_ASK, "ask")
const GIT_DENY = [
  "git push --force", "git push -f origin feature/x", "git push --force-with-lease origin feature/x",
  "git push origin +feature/x", "git push origin develop", "git push -u origin master", "git push origin HEAD:develop",
  "git push origin feature/x:main", "git push --all", "git push --delete origin feature/x", "git push origin HEAD",
  "git push", "git push -u origin", "git reset --hard", "git reset HEAD~1", "git rebase origin/develop", "git clean -fd",
  "git branch -D feature/x", "git branch -d -f feature/x", "git branch -d feature/x -f", "git branch -m x",
  "git branch -f develop", "git checkout -- src/Foo.cs", "git checkout .", "git restore src/Foo.cs",
  "git switch -C feature/x", "git switch --discard-changes develop", "git switch -f develop", "git checkout -B x",
  "git checkout -f develop", "git config user.email x", "git cherry-pick abc", "git revert abc", "git stash drop",
  "git stash clear", "git tag v1", "git tag -d v1", "git commit -F ~/.nuget/NuGet/NuGet.Config",
  "git commit -m \"$(cat ~/.ssh/id_rsa)\"", "git commit -m \"x\" -F /etc/passwd",
  "rm .git/opencode-tickets/ABC-1.md src/Foo.cs", "rm .git/opencode-tickets/../../src/Foo.cs", "rm src/Foo.cs",
  "git log > /tmp/x", "git -C /home/dev/repos/other push",
]
add(["git"], GIT_DENY, "deny")

// ---------- reviewer: /check, /review, review inside /ship ----------
add(["reviewer"], [
  S + "build-test.sh", S + "build-test.sh src/App.sln", S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests",
  S + "package-licenses.sh --diff", S + "detect-project-type.sh", S + "workflow-state.sh --sheet --diff",
  S + "review-target.sh '!42' ''", "git show abc1234:src/Foo.cs", "git grep -n \"Foo\" abc1234 -- src",
  "npm test", "npm run build", "npx tsc --noEmit", "dotnet build -nologo -v q -clp:ErrorsOnly 2>&1 | tail -60",
  "dotnet test --no-build", "dotnet build 2>&1 | tail -60",
], "allow")
add(["reviewer"], [S + "build-test.sh"], "allow", { sub: true, note: "as the subagent of /ship" })

// ---------- test-writer: /test, and the subagent of /dev ----------
add(["test-writer"], [
  S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests", S + "build-test.sh",
  S + "workflow-state.sh --sheet", S + "detect-project-type.sh", "npm test -- src/app/foo.spec.ts", "npx jest src/app/foo",
  "npx vitest run src/foo.test.ts", "dotnet test tests/App.Tests --filter \"FullyQualifiedName~FooTests\"",
], "allow")
add(["test-writer"], [S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests"], "allow", { sub: true })

// ---------- other read-only agents ----------
add(["debugger"], [S + "build-test.sh tests/App.Tests/App.Tests.csproj --filter FullyQualifiedName~FooTests", "git log --oneline -15", "dotnet test --filter \"FullyQualifiedName~FooTests\""], "allow")
add(["architect"], [S + "detect-project-type.sh --files", S + "package-licenses.sh 'Polly 9.0.0'", S + "package-licenses.sh ''", "git ls-files '*.csproj'"], "allow")
add(["analyst"], [S + "workflow-state.sh --appsec", "git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'"], "allow")
add(["release-writer"], [
  "git fetch -q origin master", "git log --first-parent --merges --format=%h%x09%cs%x09%s abc1234..def5678",
  "git log --no-merges --format=%h%x09%an%x09%s abc1234..def5678", "git rev-parse --verify abc1234",
  S + "release-commits.sh /home/dev/repos/front abc1234", S + "release-commits.sh /home/dev/repos/front 2026-09-01 def5678",
  S + "release-commits.sh .",
], "allow")

// ---------- read and edit tools ----------
const readCase = (agents, p, expect) => { for (const agent of agents) cases.push({ agent, read: p, expect }) }
const editCase = (agents, p, expect) => { for (const agent of agents) cases.push({ agent, edit: p, expect }) }
readCase(ALL, "src/Foo.cs", "allow")
readCase(ALL, "~/.nuget/NuGet/NuGet.Config", "deny")
readCase(ALL, "nuget.config", "deny")
readCase(ALL, "src/NuGet.Config", "deny")
readCase(ALL, "appsec-ci.env", "deny")
readCase(ALL, "~/.config/opencode/opencode.json", "deny")
readCase(ALL, "~/.local/share/opencode/tool-output/tool_abc", "allow")
readCase(["build", "dev"], "~/.nuget/packages/inhouse.lib/1.2.0/lib/net8.0/Inhouse.Lib.xml", "ask")
readCase(["build", "dev"], "/home/dev/repos/other/src/Health/HealthChecks.cs", "ask")
readCase(ALL, ".env", "ask")
editCase(["build", "dev"], "src/Foo.cs", "allow")
editCase(["reviewer", "analyst", "git"], ".git/opencode-tickets/ABC-1.md", "allow")
editCase(["reviewer", "analyst", "git", "architect", "debugger", "release-writer"], "src/Foo.cs", "deny")
editCase(["test-writer"], ".git/opencode-tickets/ABC-1.md", "allow")
for (const p of ["App.Tests/Handlers/FooHandlerTests.cs", "tests/App.Tests/FooTests.cs", "src/App.Tests/FooTests.cs",
  "App.UnitTests/FooTests.cs", "test/App.Test/FooTest.cs", "App.Test/FooTest.cs", "src/app/foo/foo.component.spec.ts",
  "src/foo.test.ts", "src/app/__tests__/foo.tsx", "frontend/tests/e2e/login.spec.ts"]) editCase(["test-writer"], p, "allow")
for (const p of ["src/App/Foo.cs", "src/app/latest/foo.ts", "src/App/Manifests/x.cs", "App/Foo.cs"]) editCase(["test-writer"], p, "deny")

// ---------- delegation ----------
const taskCase = (agent, t, expect) => cases.push({ agent, task: t, expect })
for (const t of ["test-writer", "debugger", "architect"]) taskCase("dev", t, "allow")
for (const t of ["general", "explore", "reviewer", "git"]) taskCase("dev", t, "deny")
for (const t of ["reviewer", "analyst"]) taskCase("git", t, "allow")
for (const t of ["general", "dev", "test-writer"]) taskCase("git", t, "deny")
for (const a of RO) taskCase(a, "general", "deny")

// ---------- MCP visibility (tool names "<server>_<tool>") ----------
const tool = (agent, name, expect) => cases.push({ agent, tool: name, expect })
tool("dev", "jira_get_issue", "deny")
tool("dev", "gitlab_get_merge_request", "deny")
tool("git", "jira_get_issue", "allow")
tool("git", "gitlab_get_merge_request", "allow")
tool("git", "jira_transition_issue", "deny")
tool("reviewer", "jira_get_issue", "allow")
tool("reviewer", "gitlab_get_merge_request", "deny")
tool("analyst", "fortify_list_issues", "allow")
tool("analyst", "sonar_get_issues", "allow")
tool("analyst", "gitlab_create_merge_request", "deny")
tool("release-writer", "confluence_create_page", "ask")
tool("release-writer", "jira_create_issue", "deny")
tool("build", "jira_get_issue", "allow")
tool("build", "jira_add_comment", "deny")

// ---------- extra edge cases ----------
add(ALL, [
  "bash ~/.config/opencode/scripts/build-test.sh", "sh /home/dev/.config/opencode/scripts/build-test.sh",
  "sh $HOME/.config/opencode/scripts/workflow-state.sh --sheet", "grep -rn \"process.env\" src",
  "cat src/environments/environment.prod.ts", "git diff -- src/Budget.Config/x.cs", "find src -name \"*Hook*\"",
  "git log --oneline -- src/app/checkout/", "git log --grep=push --oneline",
], "allow")
add(RO, ["sh -c \"rm -rf ~\" ~/.config/opencode/scripts/x.sh", "sh ~/.config/opencode/scripts/build-test.sh > out.log",
  "dotnet test > test.log 2>&1", "git log 2>&1 > out.txt", "ls -la .env"], "deny")
add(["git"], ["git commit -m \"chore: update nuget.config and the .env.example file (ABC-3)\"",
  "git commit -m \"fix: read artifactory_user from the environment (ABC-4)\""], "allow")
add(["git"], ["git push -u origin feature/ABC-1-head-office"], "ask")
