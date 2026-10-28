// Tests of the pack plugin (plugins/openrd-pack.js, OpenCode v2): the guards of the shell and file tools (the repository
// jail 7, the refusals 6, the long timeouts 8, the tool called by its path 11), then the v2 hooks against a fake OpenCode
// v2 context (prompt, context, tools, events): the command line and its title (3), the command chosen in a question
// (4), the progress (5), one pilot per folder (9), the outcome (10), what v2 opens that the pack closes (12) and the
// pruning of old tool outputs (13). In a fake home folder.
// Usage, from opencode-v2/: node tools/plugin-test.mjs
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const pack = resolve(process.argv[2] || ".")
const home = mkdtempSync(join(tmpdir(), "plugin-test-"))
process.env.HOME = home
// the folders of the fake home only, whatever this machine sets (a CI runner sets XDG_CONFIG_HOME)
process.env.XDG_DATA_HOME = join(home, ".local", "share")
process.env.XDG_CONFIG_HOME = join(home, ".config")
process.env.XDG_CACHE_HOME = join(home, ".cache")
process.env.XDG_STATE_HOME = join(home, ".local", "state")
delete process.env.OPENCODE_CONFIG_DIR
const repo = join(home, "repos", "my-api")
const other = join(home, "repos", "old-api")
const legacy = join(home, "repos", "legacy")
for (const dir of [join(repo, "src"), join(other, "src"), join(legacy, "src"), join(home, ".config", "opencode", "scripts"),
  join(home, ".config", "opencode", "skills", "build-fix"), join(home, ".nuget", "packages", "inhouse.lib", "1.0.0"),
  join(home, ".nuget", "NuGet"), join(home, ".local", "share", "opencode", "tool-output")]) mkdirSync(dir, { recursive: true })
writeFileSync(join(home, ".zshenv"), "export artifactory_password=secret\n")
writeFileSync(join(repo, "src", "Foo.cs"), "class Foo {}\n")
execFileSync("git", ["init", "-q", repo])

// the plugin imports @opencode/plugin, which OpenCode v2 provides: a stub next to a copy of it, for these tests
const stub = join(home, "plugin-under-test")
mkdirSync(join(stub, "node_modules", "@opencode", "plugin"), { recursive: true })
writeFileSync(join(stub, "node_modules", "@opencode", "plugin", "package.json"), '{"name":"@opencode/plugin","type":"module","main":"index.js"}')
writeFileSync(join(stub, "node_modules", "@opencode", "plugin", "index.js"), "export const Plugin = { define: (definition) => definition }\n")
writeFileSync(join(stub, "openrd-pack.js"), readFileSync(join(pack, "plugins", "openrd-pack.js"), "utf8"))
const { Guards, prune, fillNullContent, withAgentOptions, withoutConversationOnly, stripConversationOnly, narrowPilotTools,
  clearOldOutputs, requestTokens, usableTokens, reviewedSkill, default: v2Plugin } = await import(join(stub, "openrd-pack.js"))

// ---------- fake OpenCode client ----------
const sessions = new Map()
const messages = new Map()
let references = {}
const client = {
  session: {
    get: async ({ path }) => ({ data: sessions.get(path.id) }),
    update: async ({ path, body }) => {
      sessions.get(path.id).title = body.title
      return { data: sessions.get(path.id) }
    },
    messages: async ({ path }) => ({ data: messages.get(path.id) || [] }),
    list: async () => ({ data: [...sessions.values()] }),
    command: async () => ({}),
  },
  config: { get: async () => ({ data: { references } }) },
  app: { log: async ({ body }) => logs.push(body) },
}
const logs = []
const session = (id, extra = {}) => sessions.set(id, { id, title: "Session " + id, ...extra })

references = { legacy: { path: "~/repos/legacy", description: "legacy export" } }
const guards = await Guards({ client, directory: repo, worktree: repo })

let failures = 0
let count = 0
async function check(label, fn) {
  count++
  try {
    await fn()
  } catch (error) {
    failures++
    console.log("FAIL " + label + "\n     " + String(error && error.message).split("\n")[0])
  }
}
async function agent(sessionID, name) {
  guards.agent(sessionID, name)
}
async function tool(sessionID, name, args) {
  const output = { args: { ...args } }
  await guards.before({ tool: name, sessionID, callID: "c" + count }, output)
  return output.args
}
const refused = (sessionID, name, args, why = /outside the repository|Refused by the pack/) =>
  assert.rejects(() => tool(sessionID, name, args), why)
const allowed = (sessionID, name, args) => tool(sessionID, name, args)

session("pilot-1")
session("coder-1", { parentID: "pilot-1" })
session("analyst-1", { parentID: "pilot-1" })
session("build-1")
session("debugger-1")
await agent("pilot-1", "pilot")
await agent("coder-1", "coder")
await agent("analyst-1", "analyst")
await agent("build-1", "build")
await agent("debugger-1", "debugger")
const S = "sh ~/.config/opencode/scripts/"

// ---------- 7. shell commands outside the repository ----------
const OUTSIDE = [
  "grep -r export ~", "grep -ri artifactory " + home, "cat $HOME/.zshenv", "cat ${HOME}/.zshenv", "cat \"$HOME\"/.zshenv",
  "bash -c 'cd ~ && cat .zshenv'", "sh -c \"grep -r export ~\"", "cd .. && ls", "cd", "ls ../old-api",
  "printf x > ~/.config/opencode/agents/coder.md", "echo x >> " + join(home, ".config", "opencode", "opencode.json"),
  "git -C ~/repos/old-api log --oneline", "find / -name '*.env'", "D=~; cat $D/.zshenv", "cat ~root/.ssh/id_rsa",
  "dotnet build --output=" + join(home, "out"), "tail -n 5 <" + join(home, ".zshenv"), "xargs grep -l x < ~/list.txt",
  "git diff > ../patch.diff", "cp src/Foo.cs ~/Foo.cs", "eval \"cat ~/.zshenv\"", "pushd ~",
]
for (const who of ["pilot-1", "coder-1", "analyst-1"]) {
  for (const command of OUTSIDE) await check(`[${who}] refused: ${command}`, () => refused(who, "bash", { command }))
}
for (const command of ["grep -r export ~", "cat $HOME/.zshenv", "bash -c 'cd ~ && cat .zshenv'", "ls ~/repos/old-api"]) {
  await check(`[build] refused: ${command}`, () => refused("build-1", "bash", { command }))
}
await check("[coder] refused: workdir outside", () => refused("coder-1", "bash", { command: "ls", workdir: home }))
await check("[coder] refused: workdir ..", () => refused("coder-1", "bash", { command: "ls", workdir: ".." }))
if (process.platform === "linux") {
  await check("[pilot] refused: /proc", () => refused("pilot-1", "bash", { command: "cat /proc/self/environ" }))
}

const INSIDE = [
  S + "build-test.sh", S + "build-test.sh src/App.sln --filter FullyQualifiedName~FooTests",
  "sh $HOME/.config/opencode/scripts/package-refs.sh", "sh " + join(home, ".config", "opencode", "scripts", "detect-project-type.sh"),
  "grep -rn \"/api/v1/orders\" src", "grep -rn '/orders/{id}' src", "realpath ~", "echo ~", "git diff -- src/../src/Foo.cs",
  "ls src 2>/dev/null", "dotnet build " + join(repo, "App.sln"), "cat ~/.config/opencode/skills/build-fix/SKILL.md",
  "grep -c Foo " + join(home, ".local", "share", "opencode", "tool-output", "tool_abc"), "git log --oneline -5 | head",
  "grep -rn \"x => x.Id\" src", "git show HEAD:src/Foo.cs | grep -n \"List<int>\"", "dotnet test 2>&1 | tail -80",
  "cd src && ls", "git log --format='%H %s' -3", "sed -n '1,20p' src/Foo.cs", "find src -name '*.cs' | xargs grep -l Foo",
]
for (const who of ["pilot-1", "coder-1", "analyst-1", "build-1"]) {
  for (const command of INSIDE) await check(`[${who}] allowed: ${command}`, () => allowed(who, "bash", { command }))
}
// the arguments of the pack's scripts are free text: a commit message may name any path
for (const command of [S + "ship.sh \"fix(io): accept ../ and ~ in paths (ABC-1)\" \"- see /home and $HOME\"",
  S + "ticket-sheet.sh decision \"Chemin : ~/data refusé — hors dépôt (étape 2)\"",
  S + "compare-repos.sh --raw '" + other + " ExportService le titre perd son extension'"]) {
  await check(`[pilot] allowed: ${command}`, () => allowed("pilot-1", "bash", { command }))
}

// ---------- 7. file tools of the agents of the pack ----------
for (const who of ["pilot-1", "coder-1", "analyst-1", "debugger-1"]) {
  for (const [name, args] of [["read", { filePath: join(home, ".zshenv") }], ["read", { filePath: "~/.zshenv" }],
    ["read", { filePath: join(home, ".nuget", "NuGet", "NuGet.Config") }], ["grep", { pattern: "export", path: home }],
    ["glob", { pattern: "**/*.env", path: join(home, "repos") }], ["edit", { filePath: join(home, ".config", "opencode", "agents", "coder.md"), oldString: "a", newString: "b" }],
    ["write", { filePath: "../old-api/src/x.cs", content: "x" }], ["read", { filePath: join(other, "src", "x.cs") }]]) {
    await check(`[${who}] refused: ${name} ${args.filePath || args.path}`, () => refused(who, name, args))
  }
  for (const [name, args] of [["read", { filePath: join(repo, "src", "Foo.cs") }], ["read", { filePath: "src/Foo.cs" }],
    ["read", { filePath: join(home, ".nuget", "packages", "inhouse.lib", "1.0.0", "inhouse.lib.xml") }],
    ["read", { filePath: join(home, ".config", "opencode", "skills", "build-fix", "SKILL.md") }],
    ["grep", { pattern: "Foo", path: join(repo, "src") }], ["grep", { pattern: "Foo" }], ["glob", { pattern: "**/*.cs" }],
    ["read", { filePath: join(legacy, "src", "Export.cs") }], ["grep", { pattern: "Export", path: legacy }]]) {
    await check(`[${who}] allowed: ${name} ${args.filePath || args.path || "(repository)"}`, () => allowed(who, name, args))
  }
}
// the conversation agents keep OpenCode's own approval for their file tools
await check("[build] read outside: left to OpenCode", () => allowed("build-1", "read", { filePath: join(other, "src", "x.cs") }))
// a reference configured in opencode.json: readable through the shell by the read-only agents, never by the coder
await check("[analyst] shell on a reference", () => allowed("analyst-1", "bash", { command: "git -C ~/repos/legacy log --oneline -5" }))
await check("[coder] shell on a reference", () => refused("coder-1", "bash", { command: "git -C ~/repos/legacy log --oneline -5" }))

// ---------- 7. folders I name ----------
// in the arguments of /compare (the debugger is the agent of that command)
await guards.named("debugger-1", other + " ExportService le titre")
await check("[debugger] shell on the named reference", () => allowed("debugger-1", "bash", { command: "git -C " + other + " log --oneline -5" }))
await check("[debugger] file tool on the named reference", () => allowed("debugger-1", "read", { filePath: join(other, "src", "x.cs") }))
await check("[debugger] home still refused", () => refused("debugger-1", "bash", { command: "grep -r export ~" }))
// in the arguments of /go: the subagents of the run read it with the file tools; the coder never through the shell
session("pilot-2")
session("coder-2", { parentID: "pilot-2" })
session("analyst-2", { parentID: "pilot-2" })
await agent("pilot-2", "pilot")
await agent("coder-2", "coder")
await agent("analyst-2", "analyst")
await guards.named("pilot-2", "ABC-12 comme dans ~/repos/old-api (ExportService)")
await check("[coder of /go] read in the named folder", () => allowed("coder-2", "read", { filePath: join(other, "src", "x.cs") }))
await check("[analyst of /go] shell in the named folder", () => allowed("analyst-2", "bash", { command: "git -C ~/repos/old-api log -3" }))
await check("[coder of /go] shell in the named folder", () => refused("coder-2", "bash", { command: "ls ~/repos/old-api" }))
await check("[pilot of /go] glob of the named folder", () => allowed("pilot-2", "glob", { pattern: "*", path: other }))
// in a message I type (top-level session only)
await check("[build] before naming", () => refused("build-1", "bash", { command: "ls ~/repos/old-api" }))
await guards.named("build-1", "Regarde l'implémentation dans ~/repos/old-api, merci.")
await check("[build] after naming", () => allowed("build-1", "bash", { command: "ls ~/repos/old-api" }))
await guards.named("coder-1", "Read " + home + " now")
await check("[coder] a subagent prompt names nothing", () => refused("coder-1", "bash", { command: "ls " + home }))

// ---------- 7. the folders outside the repository are read-only ----------
const P = "~/.config/opencode/scripts/"
const K = "~/.config/opencode/skills/build-fix/"
const READ_ONLY = [
  "cp src/Foo.cs " + P + "ship.sh", "rm " + P + "diff-guard.sh", "mv " + P + "diff-guard.sh src/",
  "echo 'exit 0' > " + P + "diff-guard.sh", "printf x >> " + P + "diff-guard.sh", "cd " + P + " && rm diff-guard.sh",
  "cd ~/.config/opencode/scripts && echo x > diff-guard.sh", "ls -d " + P + "* | xargs rm", "find " + P + " -name '*.sh' -delete",
  "sed -i 's/STOP/OK/' " + P + "diff-guard.sh", "python3 " + P + "outil.sh", "touch " + K + "x", "chmod +x " + P + "x.sh",
  "tee " + K + "SKILL.md < src/Foo.cs", "cd " + K + " && touch x",
]
for (const who of ["pilot-1", "coder-1", "analyst-1", "build-1"]) {
  for (const command of READ_ONLY) await check(`[${who}] read-only: ${command}`, () => refused(who, "bash", { command }, /never change it/))
}
const READS = [
  "cat " + P + "ship.sh", "grep -n Usage " + P + "ship.sh", "ls " + P, "sed -n '1,20p' " + P + "ship.sh", "head -5 " + K + "SKILL.md",
  "cd " + K + " && grep -rn Foo .", "find ~/.config/opencode/skills -name SKILL.md", "diff " + K + "SKILL.md src/Foo.cs",
  P + "workflow-state.sh --no-fetch", "cd " + P + " && sh workflow-state.sh --no-fetch", "wc -l < " + K + "SKILL.md",
  "ls " + P + " | xargs echo", "cd src && cat ../src/Foo.cs",
]
for (const who of ["pilot-1", "coder-1", "analyst-1", "build-1"]) {
  for (const command of READS) await check(`[${who}] reads: ${command}`, () => allowed(who, "bash", { command }))
}
// a reference: read, never changed or built
for (const command of ["git -C ~/repos/legacy checkout -b x", "dotnet build ~/repos/legacy/Legacy.sln", "cd ~/repos/legacy && dotnet build",
  "cd ~/repos/legacy && git checkout -b x", "rm ~/repos/legacy/src/Export.cs"]) {
  await check(`[analyst] read-only reference: ${command}`, () => refused("analyst-1", "bash", { command }, /never change it/))
}
for (const command of ["cd ~/repos/legacy && git log --oneline -5", "grep -rn Export ~/repos/legacy/src", "git -C ~/repos/legacy diff HEAD~1 --stat"]) {
  await check(`[analyst] reads the reference: ${command}`, () => allowed("analyst-1", "bash", { command }))
}
// a cd that cannot be followed
for (const command of ["cd - && ls", "popd", "pushd +1"]) {
  await check(`[coder] refused: ${command}`, () => refused("coder-1", "bash", { command }))
}
// the agents of the pack write only in the repository, even in a folder they may read
for (const [name, args] of [["write", { filePath: join(home, ".config", "opencode", "skills", "build-fix", "SKILL.md"), content: "x" }],
  ["edit", { filePath: join(home, ".config", "opencode", "scripts", "ship.sh"), oldString: "a", newString: "b" }]]) {
  await check(`[coder] read-only: ${name} ${args.filePath}`, () => refused("coder-1", name, args, /never change it/))
}

// ---------- 11. a build tool called by its full path runs by its name ----------
const command = async (text) => (await tool("coder-1", "bash", { command: text })).command
await check("~/.bin/dotnet becomes dotnet", async () => assert.equal(await command("~/.bin/dotnet build src/App.sln"), "dotnet build src/App.sln"))
await check("an absolute dotnet becomes dotnet", async () => assert.equal(await command(join(home, ".bin", "dotnet") + " test --no-build"), "dotnet test --no-build"))
await check("after &&", async () => assert.equal(await command("cd src && $HOME/.dotnet/dotnet --info"), "cd src && dotnet --info"))
await check("/usr/bin/git becomes git", async () => assert.equal(await command("/usr/bin/git status"), "git status"))
await check("a path in a search stays", async () => assert.equal(await command("grep -rn /api/v1/node src"), "grep -rn /api/v1/node src"))

// ---------- 6/7. harmless redirections are removed; a redirection to a file is refused for the agents of the pack ----------
// 2>&1 and /dev/null are dropped before the command is checked and run (OpenCode combines the two channels anyway)
await check("2>&1 is removed", async () => assert.equal(await command("cat src/Foo.cs 2>&1"), "cat src/Foo.cs"))
await check("2>&1 before a pipe is removed", async () => assert.equal(await command("dotnet build src/App.sln 2>&1 | tail -60"), "dotnet build src/App.sln | tail -60"))
await check(">/dev/null is removed", async () => assert.equal(await command("ls src 2>/dev/null"), "ls src"))
await check(">/dev/null 2>&1 is removed", async () => assert.equal(await command("dotnet build 2>&1 >/dev/null"), "dotnet build"))
await check(">&2 is removed", async () => assert.equal(await command("echo oops >&2"), "echo oops"))
await check("a noise redirection without a space on /dev/null stays (harmless device)", async () => assert.equal(await command("ls>/dev/null"), "ls>/dev/null"))
// a 2>&1 written inside a quoted search string is left alone
await check("a quoted 2>&1 is kept", async () => assert.equal(await command("grep -n '2>&1' src/Foo.cs"), "grep -n '2>&1' src/Foo.cs"))
await check("a quoted > is kept", async () => assert.equal(await command("grep -n \"a > b\" src/Foo.cs"), "grep -n \"a > b\" src/Foo.cs"))
// a redirection to a real file, inside the repository, is refused for every agent of the pack
const REDIRECTS = ["echo x > notes.txt", "cat src/Foo.cs > copy.cs", "git diff >> changes.txt", "dotnet test > out.log",
  "cat src/Foo.cs 2> err.log", "cat src/Foo.cs >out.txt", "echo x &> both.log", "sort a.txt > a.txt"]
for (const who of ["pilot-1", "coder-1", "analyst-1", "debugger-1"]) {
  for (const cmd of REDIRECTS) await check(`[${who}] redirection refused: ${cmd}`, () => refused(who, "bash", { command: cmd }, /redirection/))
}
// /dev/null and 2>&1 are never refused, even without a space
for (const who of ["pilot-1", "coder-1", "analyst-1"]) {
  for (const cmd of ["cat src/Foo.cs >/dev/null", "cat src/Foo.cs > /dev/null 2>&1", "dotnet test 2>&1 | tail", "echo hi >&2"]) {
    await check(`[${who}] allowed: ${cmd}`, () => allowed(who, "bash", { command: cmd }))
  }
}
// the conversation agents keep OpenCode's own rules for a redirection (build writes files for /outil)
await check("[build] a redirection in the repository is left to OpenCode", () => allowed("build-1", "bash", { command: "echo x > notes.txt" }))

// ---------- refusals written to OpenCode's log, without the command ----------
logs.length = 0
await check("an outside path is logged", async () => {
  await refused("coder-1", "bash", { command: "cat ~/.zshenv" })
  const last = logs.at(-1)
  assert.equal(last.service, "pack")
  assert.equal(last.extra.agent, "coder")
  assert.equal(last.extra.path, "~/.zshenv")
})
await check("a credential refusal is logged without the command", async () => {
  await refused("coder-1", "bash", { command: "export GITLAB_TOKEN=glpat-abc123 && git fetch" }, /Refused by the pack/)
  const last = logs.at(-1)
  assert.match(last.extra.reason, /credential/)
  assert.ok(!JSON.stringify(last).includes("glpat-abc123"))
})

// ---------- environment dumps and recursive rm (every agent) ----------
for (const command of ["export -p", "export", "declare -p", "declare -x", "typeset -x", "readonly", "set", "dotnet build; export -p",
  "rm -rf bin", "rm -fr obj", "rm -r src/Old", "rm -Rf src/Old", "rm src/Old -r", "rm -v -r src/Old", "rm --recursive src/Old",
  "find . -name obj | xargs rm -rf", "export PATH=/usr/local/dotnet:$PATH", "artifactory_password=x dotnet restore"]) {
  for (const who of ["build-1", "coder-1"]) await check(`[${who}] refused: ${command}`, () => refused(who, "bash", { command }, /Refused by the pack/))
}
for (const command of ["set -e; dotnet build", "export DOTNET_CLI_TELEMETRY_OPTOUT=1 && dotnet build", "rm -f src/order-repository.cs",
  "rm src/Features/Old/OldHandler.cs", "grep -rn 'rm -rf' docs", "git log --grep \"export\""]) {
  await check(`[coder] allowed: ${command}`, () => allowed("coder-1", "bash", { command }))
}

// ---------- 8. timeouts ----------
const timeout = async (command, given) => (await tool("coder-1", "bash", given ? { command, timeout: given } : { command })).timeout
await check("build-test.sh gets 45 min: it bounds its own run (42 min with the wait for the lock) and says what ran", async () =>
  assert.equal(await timeout(S + "build-test.sh"), 2700000))
await check("two scripts of the pack in one call get 45 min each (the measure of a .NET repository and its front-end)", async () =>
  assert.equal(await timeout(S + "build-test.sh src/App.sln ; " + S + "build-test.sh ClientApp"), 5400000))
await check("…three or more: 2 hours at most", async () =>
  assert.equal(await timeout(S + "build-test.sh ; " + S + "build-test.sh a ; " + S + "build-test.sh b"), 7200000))
await check("dotnet test gets 20 min", async () => assert.equal(await timeout("dotnet test --no-build 2>&1 | tail -80"), 1200000))
await check("npm test gets 20 min", async () => assert.equal(await timeout("npm test -- src/app/foo.spec.ts"), 1200000))
await check("ship.sh gets 5 min", async () => assert.equal(await tool("pilot-1", "bash", { command: S + "ship.sh --no-push \"feat: x (ABC-1)\"" }).then((a) => a.timeout), 300000))
await check("git status keeps the default", async () => assert.equal(await timeout("git status"), undefined))
await check("a longer timeout is kept", async () => assert.equal(await timeout(S + "build-test.sh", 3600000), 3600000))
await check("the pause of /fix while its CI runs gets 6 min", async () => assert.equal(await timeout(S + "pause.sh 240"), 360000))
// a command of an agent of the pack never runs without a limit (OpenCode v2: timeout 0 turns it off)
await check("[coder] timeout 0 of a short command: 20 min, never no limit", async () =>
  assert.equal((await tool("coder-1", "bash", { command: "git log --oneline", timeout: 0 })).timeout, 1200000))
await check("[coder] timeout 0 of a build script of the pack: 45 min", async () =>
  assert.equal((await tool("coder-1", "bash", { command: S + "build-test.sh", timeout: 0 })).timeout, 2700000))
await check("[coder] timeout 0 of a dotnet build: 20 min", async () =>
  assert.equal((await tool("coder-1", "bash", { command: "dotnet build", timeout: 0 })).timeout, 1200000))
await check("[pilot] timeout 0 of ship.sh: 5 min (what it needs)", async () =>
  assert.equal((await tool("pilot-1", "bash", { command: S + "ship.sh --no-push \"feat: x (ABC-1)\"", timeout: 0 })).timeout, 300000))
await check("[analyst] a negative or invalid timeout: 20 min", async () => {
  assert.equal((await tool("analyst-1", "bash", { command: "git log", timeout: -5 })).timeout, 1200000)
  assert.equal((await tool("analyst-1", "bash", { command: "git log", timeout: "never" })).timeout, 1200000)
})
await check("[coder] 5 hours asked: 2 hours at most", async () =>
  assert.equal((await tool("coder-1", "bash", { command: "dotnet test", timeout: 18000000 })).timeout, 7200000))
await check("[coder] a short timeout it asks is kept", async () =>
  assert.equal((await tool("coder-1", "bash", { command: "git status", timeout: 30000 })).timeout, 30000))
await check("[build] the conversation keeps its own timeout 0 (its background and bounded commands are mine)", async () =>
  assert.equal((await tool("build-1", "bash", { command: "git log", timeout: 0 })).timeout, 0))
for (const command of [S + "test-guardian.sh red tests/Api.Tests/Api.Tests.csproj FullyQualifiedName~Security_X_V1",
  S + "test-guardian.sh green tests/Api.Tests/Api.Tests.csproj FullyQualifiedName~Security_X_V1",
  S + "test-guardian.sh coverage V1-before tests/Api.Tests/Api.Tests.csproj src/A.cs", S + "test-guardian.sh changes origin/develop",
  S + "test-guardian.sh build tests/Api.Tests/Api.Tests.csproj", S + "test-guardian.sh setup xunit src/A.cs",
  S + "test-guardian.sh verify V1 FullyQualifiedName~Security_X_V1", S + "fortify.sh prereq"]) {
  await check("the tests of the test-guardian get 45 min (bounded by the script): " + command.split("/").pop(), async () => assert.equal(await timeout(command), 2700000))
}
for (const command of [S + "test-guardian.sh deps src/A.cs", S + "test-guardian.sh compare V1-before V1-after", S + "fortify.sh batch"]) {
  await check("a quick measure keeps the default: " + command.split("/").pop(), async () => assert.equal(await timeout(command), undefined))
}

// ---------- 7. the patch tool (offered by OpenCode v2 to some models instead of edit and write) ----------
const patchOf = (path) => "*** Begin Patch\n*** Update File: " + path + "\n@@\n-a\n+b\n*** End Patch"
await check("[coder] refused: patch outside", () => refused("coder-1", "patch", { patchText: patchOf("../old-api/src/x.cs") }))
await check("[coder] refused: patch adding a file in the skills", () =>
  refused("coder-1", "patch", { patchText: "*** Begin Patch\n*** Add File: " + join(home, ".config", "opencode", "skills", "x", "SKILL.md") + "\n+x\n*** End Patch" }, /never change it/))
await check("[coder] refused: patch moving a file outside", () =>
  refused("coder-1", "patch", { patchText: "*** Begin Patch\n*** Update File: src/Foo.cs\n*** Move to: " + join(home, "Foo.cs") + "\n@@\n-a\n+b\n*** End Patch" }))
await check("[coder] allowed: patch in the repository", () => allowed("coder-1", "patch", { patchText: patchOf("src/Foo.cs") }))

// ---------- 7. a worktree (an OpenCode workspace): the ticket sheets are in the git folder of the main checkout ----------
const mainRepo = join(home, "repos", "main-api")
const workspace = join(home, ".local", "share", "opencode", "worktree", "p1", "brave-fox")
mkdirSync(join(mainRepo, "src"), { recursive: true })
writeFileSync(join(mainRepo, "src", "A.cs"), "class A {}\n")
const gitIn = (cwd, args) => execFileSync("git", args, { cwd, stdio: "ignore", env: { ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@x", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@x" } })
gitIn(home, ["init", "-q", mainRepo])
gitIn(mainRepo, ["add", "-A"])
gitIn(mainRepo, ["commit", "-q", "-m", "init"])
gitIn(mainRepo, ["worktree", "add", "-q", "-b", "opencode/brave-fox", workspace])
mkdirSync(join(mainRepo, ".git", "opencode-tickets"), { recursive: true })
const guardsWt = await Guards({ client, directory: workspace, worktree: workspace })
const sheetOut = join(mainRepo, ".git", "opencode-tickets", "ABC-9.md")
for (const [id, name] of [["wt-analyst", "analyst"], ["wt-coder", "coder"], ["wt-checker", "checker"], ["wt-pilot", "pilot"]]) {
  session(id)
  guardsWt.agent(id, name)
}
const toolWt = async (sessionID, name, args) => {
  const output = { args: { ...args } }
  await guardsWt.before({ tool: name, sessionID, callID: "w" + count }, output)
  return output.args
}
await check("[worktree analyst] writes the sheet in the main .git", () => toolWt("wt-analyst", "write", { filePath: sheetOut, content: "# ABC-9" }))
await check("[worktree pilot] edits the sheet", () => toolWt("wt-pilot", "edit", { filePath: sheetOut, oldString: "a", newString: "b" }))
await check("[worktree checker] reads the sheet", () => toolWt("wt-checker", "read", { filePath: sheetOut }))
await check("[worktree coder] cat of the sheet", () => toolWt("wt-coder", "bash", { command: "cat " + sheetOut }))
await check("[worktree coder] never writes the sheet", () => assert.rejects(() => toolWt("wt-coder", "write", { filePath: sheetOut, content: "x" }), /never change it/))
await check("[worktree coder] never removes the sheet", () => assert.rejects(() => toolWt("wt-coder", "bash", { command: "rm " + sheetOut }), /never change it/))
await check("[worktree coder] the main checkout is outside", () => assert.rejects(() => toolWt("wt-coder", "write", { filePath: join(mainRepo, "src", "A.cs"), content: "x" }), /outside the repository/))
await check("[worktree coder] the rest of the main .git is outside", () => assert.rejects(() => toolWt("wt-coder", "bash", { command: "cat " + join(mainRepo, ".git", "config") }), /outside the repository/))
await check("[worktree coder] its own files", () => toolWt("wt-coder", "write", { filePath: join(workspace, "src", "B.cs"), content: "x" }))

// ---------- OpenCode v2: a fake v2 context ----------
const ensure = (dir) => (mkdirSync(dir, { recursive: true }), dir)
const configDir = ensure(join(home, ".config", "opencode"))
// a model whose context is far larger than the conversations of these tests: the clearing within a run (13) has its
// own tests, with a smaller model
writeFileSync(join(configDir, "opencode.json"), JSON.stringify({ compaction: { prune: true }, references: { legacy: { path: "~/repos/legacy" } },
  provider: { fake: { models: { qwen: { limit: { context: 1000000, output: 32768 } } } } } }))
writeFileSync(join(home, ".config", "opencode", "scripts", "hello.sh"), 'echo "hello from $(basename "$PWD")"\n')
function fakeV2(directory, { sessionsAt = new Map(), options = { tickMs: 25, mcpWaitMs: 600, resumeFailureMs: [600000], resumeUnfinishedMs: 600000 }, agents } = {}) {
  const fake = { runCommands: false, runPrompts: false }
  const hooks = {}
  const queue = []
  let wake
  const stream = {
    subscribe: () => ({
      [Symbol.asyncIterator]() {
        return { next: () => new Promise((r) => { if (queue.length) r({ value: queue.shift(), done: false }); else wake = () => r({ value: queue.shift(), done: false }) }) }
      },
    }),
  }
  const push = (type, data) => { queue.push({ type, data }); if (wake) { const w = wake; wake = undefined; w() } }
  const calls = { update: [], command: [], prompt: [], create: [] }
  const servers = [["gitlab", { type: "local", command: ["node", "x"] }], ["jira", { type: "remote", url: "https://jira.invalid/mcp", codemode: true }],
    ["fortify", { type: "local", command: ["node", "f"], timeout: { startup: 20000, execution: 900000 } }]]
  // the agents as OpenCode v2 reads them (28: their options in request.body, from 1.19's temperature, top_p and options)
  const agentList = agents || [
    { id: "build", request: { settings: {}, headers: {}, body: { temperature: 1, top_p: 0.95 } } },
    { id: "pilot", request: { settings: {}, headers: {}, body: { temperature: 1, top_p: 0.95, chat_template_kwargs: { reasoning_effort: "medium" } } } },
    { id: "coder", request: { settings: {}, headers: {}, body: { temperature: 1, top_p: 0.95 } } },
    { id: "title", request: { settings: {}, headers: {}, body: { chat_template_kwargs: { enable_thinking: false } } } },
    { id: "explore", request: { settings: {}, headers: {}, body: {} } },
  ]
  const agentCalls = { list: 0 }
  const mcpState = { status: "connected" }
  const domain = (name) => ({ hook: async (hook, fn) => { hooks[name + "." + hook] = fn } })
  const ctx = {
    location: { directory },
    options,
    tool: domain("tool"),
    shell: domain("shell"),
    session: {
      hook: async (hook, fn) => { hooks["session." + hook] = fn },
      // a new session (26: the scheduled commands), in the location it is given
      create: async (input) => {
        calls.create.push(input)
        const id = "created-" + calls.create.length
        sessionsAt.set(id, { id })
        return { id }
      },
      get: async ({ sessionID }) => {
        const s = sessionsAt.get(sessionID)
        if (!s) throw new Error("Session not found: " + sessionID)
        return { ...s }
      },
      update: async ({ sessionID, title }) => {
        calls.update.push({ sessionID, title })
        const s = sessionsAt.get(sessionID)
        if (s) s.title = title
      },
      // v2 expands the command and prompts the session with it (only when a test asks for it)
      command: async (input) => {
        calls.command.push(input)
        if (fake.runCommands) {
          await hooks["session.prompt"]({ sessionID: input.sessionID, messageID: "cmd", prompt: { text: "[[command " + input.name + " " + input.text + "]]\nRun." }, delivery: "steer" })
        }
      },
      // a prompt sent by the plugin (19): it goes through the prompt hook (only when a test asks for it)
      prompt: async (input) => {
        const event = { sessionID: input.sessionID, messageID: "auto", prompt: { text: input.text }, delivery: "steer" }
        calls.prompt.push({ ...input, event })
        if (fake.runPrompts) await hooks["session.prompt"](event)
      },
    },
    event: stream,
    mcp: {
      transform: async (fn) => fn({ list: () => servers }),
      list: async () => ({ location: { directory }, data: [{ name: "gitlab", status: { status: mcpState.status } }] }),
    },
    agent: {
      list: async () => {
        agentCalls.list++
        return { location: { directory }, data: agentList }
      },
    },
  }
  return Object.assign(fake, { ctx, hooks, push, sessions: sessionsAt, calls, servers, mcpState, agentList, agentCalls })
}
const wait = (ms = 60) => new Promise((r) => setTimeout(r, ms))
const v2 = fakeV2(repo)
await v2Plugin.setup(v2.ctx)
const top = (id, title) => v2.sessions.set(id, { id, ...(title === undefined ? {} : { title }) })
const child = (id, parentID, title = "Sous-tâche") => v2.sessions.set(id, { id, parentID, title })
const before = async (sessionID, tool, input, agent = "coder") => {
  const event = { tool, sessionID, agent, messageID: "m", id: "c" + count, input }
  await v2.hooks["tool.execute.before"](event)
  return event.input
}
const prompt = async (sessionID, text, metadata) => {
  const event = { sessionID, messageID: "msg", prompt: { text }, metadata, delivery: "steer" }
  await v2.hooks["session.prompt"](event)
  return event
}
const context = async (sessionID, tools, agent = "build", messages = []) => {
  const event = { sessionID, agent, model: { id: "qwen", providerID: "fake" }, system: [], messages, options: {}, tools: Object.fromEntries(tools.map((t) => [t, { description: t, input: {} }])) }
  await v2.hooks["session.context"](event)
  return event
}
const TOOLS = ["edit", "glob", "grep", "question", "read", "shell", "skill", "subagent", "webfetch", "websearch", "write", "execute"]

await check("[v2] the setup registers its hooks", () => assert.deepEqual(Object.keys(v2.hooks).sort(),
  ["session.compaction", "session.context", "session.http.request", "session.http.response", "session.prompt", "session.retry", "shell.create.before", "tool.execute.after", "tool.execute.before"]))
await check("[v2 12] the MCP servers are plain tools, never code mode", () => assert.deepEqual(v2.servers.map(([, s]) => s.codemode), [false, false, false]))
// ---------- 27. the calls of the MCP servers bounded (OpenCode v2 waits 12 hours) ----------
await check("[v2 27] a server without its own limit: its calls end after 5 minutes", () => {
  assert.equal(v2.servers[0][1].timeout.execution, 300000)
  assert.equal(v2.servers[1][1].timeout.execution, 300000)
})
await check("[v2 27] a server that sets its own limit keeps it, and its other limits", () =>
  assert.deepEqual(v2.servers[2][1].timeout, { startup: 20000, execution: 900000 }))
await check("[v2 27] the servers bounded are logged once", () => {
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("calls of the MCP servers bounded"))
  assert.ok(lines.length >= 1 && lines[0].includes('"gitlab","jira"') && !lines[0].includes("fortify"), lines[0])
})

// ---------- 32. only the skills reviewed with the pack ----------
const skillAt = (dir) => {
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, "SKILL.md"), "---\nname: x\ndescription: x\n---\nx\n")
  return join(dir, "SKILL.md")
}
const skills32 = [
  { id: "efcore", name: "efcore", path: skillAt(join(configDir, "skills", "efcore")) },
  { id: "pattern-orders", name: "pattern-orders", path: skillAt(join(configDir, "skills", "pattern-orders")) },
  { id: "clever", name: "clever", path: skillAt(join(home, ".claude", "skills", "clever")) },
  { id: "agentic", name: "agentic", path: skillAt(join(home, ".agents", "skills", "agentic")) },
  { id: "cloned", name: "cloned", path: skillAt(join(repo, ".opencode", "skills", "cloned")) },
  { id: "above", name: "above", path: skillAt(join(home, "repos", ".claude", "skills", "above")) },
  { id: "efcore-twin", name: "efcore", path: skillAt(join(repo, ".claude", "skills", "efcore")) },
]
const s32 = fakeV2(repo)
s32.ctx.skill = {
  transform: async (fn) => fn({
    list: () => skills32.slice(),
    remove: (id) => {
      const at = skills32.findIndex((s) => s.id === id)
      if (at >= 0) skills32.splice(at, 1)
    },
  }),
}
await v2Plugin.setup(s32.ctx)
await check("[v2 32] the skills of the skills folder of OpenCode stay: the pack's and the team's patterns", () =>
  assert.deepEqual(skills32.map((s) => s.id), ["efcore", "pattern-orders"]))
await check("[v2 32] a skill of ~/.claude, ~/.agents, the project or a folder above it is taken out, a namesake of the pack's too, logged", () => {
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("skills found outside the skills folder"))
  assert.equal(lines.length, 1)
  for (const name of ["clever", "agentic", "cloned", "above", "efcore ("]) assert.ok(lines[0].includes(name), name + ": " + lines[0])
})
await check("[v2 32] a folder that only starts like the skills folder is not it; the system folder is", () => {
  assert.equal(reviewedSkill(skillAt(join(configDir, "skills-extra", "x"))), false)
  assert.equal(reviewedSkill(join(configDir, "skills", "efcore", "SKILL.md")), true)
  assert.equal(reviewedSkill("/etc/opencode/skills/team/SKILL.md"), true)
  assert.equal(reviewedSkill(""), false)
  assert.equal(reviewedSkill(undefined), false)
})
await check("[v2 32] without the skill domain (an older v2): the setup goes on", async () => {
  const bare = fakeV2(repo)
  await v2Plugin.setup(bare.ctx)
  assert.ok(bare.hooks["session.context"])
})

// ---------- 20. an assistant message made only of tool calls: "" instead of null ----------
const chatBody = (messages) => JSON.stringify({ model: "qwen", stream: true, messages })
const toolTurn = [{ role: "system", content: "s" }, { role: "user", content: "/fix" },
  { role: "assistant", content: null, tool_calls: [{ id: "a", type: "function", function: { name: "shell", arguments: "{}" } }] },
  { role: "tool", tool_call_id: "a", content: "ok" }]
await check("[v2 20] a null content of a tool-call message becomes \"\"", () => {
  const out = JSON.parse(fillNullContent(chatBody(toolTurn)))
  assert.equal(out.messages[2].content, "")
  assert.deepEqual(out.messages[2].tool_calls, toolTurn[2].tool_calls)
  assert.equal(out.messages[3].content, "ok")
})
await check("[v2 20] nothing to change: null returned", () => {
  assert.equal(fillNullContent(chatBody([{ role: "user", content: "hi" }, { role: "assistant", content: "x" }])), null)
  assert.equal(fillNullContent("not json, but \"content\":null"), null)
  assert.equal(fillNullContent(JSON.stringify({ input: [{ content: null }] })), null)
})
await check("[v2 20] the hook rewrites the body of the request it gets", async () => {
  const event = { sessionID: "t-1", agent: "pilot", kind: "primary", request: new Request("https://gateway.example/api/v1/chat/completions",
    { method: "POST", headers: { "content-type": "application/json", authorization: "Bearer x" }, body: chatBody(toolTurn) }) }
  await v2.hooks["session.http.request"](event)
  const sent = JSON.parse(await event.request.text())
  assert.equal(sent.messages[2].content, "")
  assert.equal(event.request.headers.get("authorization"), "Bearer x")
  assert.equal(event.request.url, "https://gateway.example/api/v1/chat/completions")
})
await check("[v2 20] a request without null content, of an agent without options, is left as it is", async () => {
  const original = new Request("https://gateway.example/api/v1/chat/completions",
    { method: "POST", headers: { "content-type": "application/json" }, body: chatBody([{ role: "user", content: "hi" }]) })
  const event = { sessionID: "t-1", agent: "explore", kind: "primary", request: original }
  await v2.hooks["session.http.request"](event)
  assert.equal(event.request, original)
})

// ---------- 28. the options of each agent in its requests (OpenCode v2 reads them, never sends them) ----------
const chatRequest = (body) => new Request("https://gateway.example/api/v1/chat/completions",
  { method: "POST", headers: { "content-type": "application/json", authorization: "Bearer k" }, body: JSON.stringify(body) })
const sentBy = async (agent, body, kind = "primary") => {
  const event = { sessionID: "t-1", agent, kind, request: chatRequest(body) }
  await v2.hooks["session.http.request"](event)
  return { body: JSON.parse(await event.request.text()), request: event.request }
}
const plainChat = (extra = {}) => ({ model: "qwen", stream: true, stream_options: { include_usage: true }, max_tokens: 32000,
  messages: [{ role: "system", content: "s" }, { role: "user", content: "x" }], ...extra })
await check("[v2 28] the temperature and top_p of the agent go with each of its requests", async () => {
  const { body, request } = await sentBy("coder", plainChat())
  assert.equal(body.temperature, 1)
  assert.equal(body.top_p, 0.95)
  assert.equal(body.max_tokens, 32000)
  assert.deepEqual(body.messages, plainChat().messages)
  assert.equal(request.headers.get("authorization"), "Bearer k")
  assert.equal(request.headers.get("content-length"), null)
})
await check("[v2 28] the options of the agent merge with those of the model (chat_template_kwargs key by key)", async () => {
  const { body } = await sentBy("pilot", plainChat({ top_k: 20, chat_template_kwargs: { preserve_thinking: true } }))
  assert.deepEqual(body.chat_template_kwargs, { preserve_thinking: true, reasoning_effort: "medium" })
  assert.equal(body.top_k, 20)
  assert.equal(body.temperature, 1)
})
await check("[v2 28] a title is written with the options of the title agent: no thinking", async () => {
  const { body } = await sentBy("title", plainChat(), "title")
  assert.deepEqual(body.chat_template_kwargs, { enable_thinking: false })
  assert.equal(body.temperature, undefined)
})
await check("[v2 28] the presence penalty of a loop cut stays when it is higher", async () => {
  const { body } = await sentBy("coder", plainChat({ presence_penalty: 1.5 }))
  assert.equal(body.presence_penalty, 1.5)
})
await check("[v2 28] what OpenCode builds never changes: messages, tools, model, stream, output limit", () => {
  const out = JSON.parse(withAgentOptions(JSON.stringify(plainChat({ tools: [{ type: "function" }] })),
    { messages: [], model: "other", max_tokens: 5, max_completion_tokens: 5, tools: [], tool_choice: "none", stream: false, n: 3, temperature: 0.2 }))
  assert.deepEqual(out.messages, plainChat().messages)
  assert.deepEqual(out.tools, [{ type: "function" }])
  assert.equal(out.model, "qwen")
  assert.equal(out.max_tokens, 32000)
  assert.equal(out.stream, true)
  assert.equal(out.tool_choice, undefined)
  assert.equal(out.n, undefined)
  assert.equal(out.temperature, 0.2)
})
await check("[v2 28] nothing to change: null (no option, the same values, not a chat completions body)", () => {
  assert.equal(withAgentOptions(JSON.stringify(plainChat({ temperature: 1 })), { temperature: 1 }), null)
  assert.equal(withAgentOptions(JSON.stringify(plainChat()), {}), null)
  assert.equal(withAgentOptions(JSON.stringify({ input: "x" }), { temperature: 1 }), null)
  assert.equal(withAgentOptions("not json", { temperature: 1 }), null)
})
await check("[v2 28] null content filled and options added in the same request", async () => {
  const { body } = await sentBy("coder", { model: "qwen", stream: true, messages: toolTurn })
  assert.equal(body.messages[2].content, "")
  assert.equal(body.temperature, 1)
})
await check("[v2 28] the agents are read once, not at each request", () => assert.equal(v2.agentCalls.list, 1))
await check("[v2 28] the options sent are logged once per agent, by their names only", () => {
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("the options of the agent are sent"))
  const pilot = lines.filter((l) => l.includes('"agent":"pilot"'))
  assert.equal(pilot.length, 1)
  assert.ok(pilot[0].includes('"options":["temperature","top_p","chat_template_kwargs"]') && !pilot[0].includes("medium"), pilot[0])
})

// ---------- 30. the instructions of the free conversation, out of the requests of the agents of the pack ----------
const GLOBAL_MD = "# Global rules\n\n## Language\n- Answer me in French.\n\n<!-- conversation only: the routing of plain words -->\n## Routing\n- \"pousse\" -> offer /push.\n<!-- /conversation only -->\n\n## Git\n- Never force-push.\n" +
  "  <!-- conversation only -->\n## Release groups\n- [GROUP]\n  <!-- /conversation only -->\n## NuGet\n- No credential.\n"
const STRIPPED_MD = "# Global rules\n\n## Language\n- Answer me in French.\n\n\n## Git\n- Never force-push.\n## NuGet\n- No credential.\n"
const contextWith = async (sessionID, agent, system) => {
  const event = { sessionID, agent, model: { id: "qwen", providerID: "fake" }, system, messages: [], options: {}, tools: {} }
  await v2.hooks["session.context"](event)
  return event
}
await check("[v2 30] the conversation-only parts of AGENTS.md: out of a text that has them, null for one that has none", () => {
  assert.equal(withoutConversationOnly(GLOBAL_MD), STRIPPED_MD)
  assert.equal(withoutConversationOnly("## Git\n- x\n"), null)
  assert.equal(withoutConversationOnly(undefined), null)
})
for (const agent of ["pilot", "analyst", "coder", "checker", "debugger", "doc-writer", "test-guardian"]) {
  await check(`[v2 30] ${agent}: its requests without the routing and the release groups, the rest as it is`, async () => {
    const shared = { type: "text", text: GLOBAL_MD }
    const event = await contextWith("t-30-" + agent, agent, [{ type: "text", text: "You are OpenCode." }, shared])
    assert.equal(event.system[1].text, STRIPPED_MD)
    assert.equal(event.system[0].text, "You are OpenCode.")
    assert.equal(shared.text, GLOBAL_MD, "the part OpenCode keeps is not changed in place")
  })
}
await check("[v2 30] the conversation keeps every instruction (build, general, plan)", async () => {
  for (const agent of ["build", "general", "plan", ""]) {
    const event = await contextWith("t-30-c", agent, [{ type: "text", text: GLOBAL_MD }])
    assert.equal(event.system[0].text, GLOBAL_MD)
  }
})
await check("[v2 30] a system part given as a string, and an AGENTS.md without the marks", async () => {
  const event = await contextWith("t-30-s", "coder", [GLOBAL_MD, "## Git\n- no marks here\n"])
  assert.equal(event.system[0], STRIPPED_MD)
  assert.equal(event.system[1], "## Git\n- no marks here\n")
  assert.equal(stripConversationOnly(undefined), 0)
})
await check("[v2 30] the same request text from one call to the next (the prefix cache of the server)", async () => {
  const a = await contextWith("t-30-p", "coder", [{ type: "text", text: GLOBAL_MD }])
  const b = await contextWith("t-30-p", "coder", [{ type: "text", text: GLOBAL_MD }])
  assert.equal(a.system[0].text, b.system[0].text)
})
await check("[v2 30] logged once per agent, with the characters taken out", () => {
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("conversation-only instructions taken out"))
  const coder = lines.filter((l) => l.includes('"agent":"coder"'))
  assert.equal(coder.length, 1)
  assert.ok(coder[0].includes('"chars":' + (GLOBAL_MD.length - STRIPPED_MD.length)), coder[0])
})
await check("[v2 30] the global AGENTS.md of the pack marks the routing, the day and the questions of the conversation for it only", () => {
  const text = readFileSync(join(pack, "AGENTS.global.md"), "utf8")
  const out = withoutConversationOnly(text)
  assert.ok(out && !out.includes("## Routing") && !out.includes("My day: /daily") && !out.includes("In a free conversation, ask me"), "marked parts")
  // Daily and Release groups are replaced by the developer's own (MIGRATION.md): never marked, their marks would go
  for (const kept of ["## Language", "## Working style", "## Speed", "## Project types", "## Git", "## Daily", "## Release groups", "## NuGet / Artifactory", "## Jira (MCP)", "## Fortify SSC (MCP)"]) assert.ok(out.includes(kept), kept)
  assert.ok(text.length - out.length > 8000, "about 2 700 tokens taken out: " + (text.length - out.length) + " characters")
})

// ---------- 31. the pilot gets the tools of the MCP servers of the command under way only ----------
const MCP_TOOLS = ["read", "shell", "subagent", "question", "jira_get_issue", "jira_search", "gitlab_get_merge_request",
  "gitlab_create_merge_request", "sonar_search_issues", "SonarQube_get_hotspots", "fortify_list_issues", "atlassian_jira_get_issue",
  "atlassian_confluence_get_page", "kibana_search", "artifactory_get_package"]
const narrowed = (command) => {
  const tools = Object.fromEntries(MCP_TOOLS.map((t) => [t, { description: t }]))
  const out = narrowPilotTools(tools, command)
  return { kept: Object.keys(tools).filter((t) => !["read", "shell", "subagent", "question"].includes(t)), out }
}
await check("[v2 31] /go: Jira and GitLab, and a server of another name", () => assert.deepEqual(narrowed("go").kept,
  ["jira_get_issue", "jira_search", "gitlab_get_merge_request", "gitlab_create_merge_request", "atlassian_jira_get_issue", "artifactory_get_package"]))
await check("[v2 31] /fix: Jira, GitLab, Sonar and Fortify", () => assert.deepEqual(narrowed("fix").kept,
  ["jira_get_issue", "jira_search", "gitlab_get_merge_request", "gitlab_create_merge_request", "sonar_search_issues", "SonarQube_get_hotspots",
    "fortify_list_issues", "atlassian_jira_get_issue", "artifactory_get_package"]))
await check("[v2 31] /fortify: Fortify and GitLab (its merge request)", () => assert.deepEqual(narrowed("fortify").kept,
  ["gitlab_get_merge_request", "gitlab_create_merge_request", "fortify_list_issues", "artifactory_get_package"]))
await check("[v2 31] /daily: Jira and GitLab; /push: GitLab", () => {
  assert.deepEqual(narrowed("daily").kept, ["jira_get_issue", "jira_search", "gitlab_get_merge_request", "gitlab_create_merge_request", "atlassian_jira_get_issue", "artifactory_get_package"])
  assert.deepEqual(narrowed("push").kept, ["gitlab_get_merge_request", "gitlab_create_merge_request", "artifactory_get_package"])
})
await check("[v2 31] /tests and /sync: no server of the pack, the built-in tools kept", () => {
  for (const command of ["tests", "sync"]) {
    const tools = Object.fromEntries(MCP_TOOLS.map((t) => [t, {}]))
    narrowPilotTools(tools, command)
    assert.deepEqual(Object.keys(tools), ["read", "shell", "subagent", "question", "artifactory_get_package"])
  }
})
await check("[v2 31] the servers taken out are named; a command it does not know changes nothing", () => {
  assert.deepEqual(narrowed("go").out.sort(), ["confluence", "fortify", "kibana", "sonar"])
  assert.equal(narrowed("review").kept.length, MCP_TOOLS.length - 4)
  assert.deepEqual(narrowPilotTools(undefined, "go"), [])
})
const mcp31 = fakeV2(repo)
await v2Plugin.setup(mcp31.ctx)
const pilotContext = async (sessionID, agent = "pilot") => {
  const event = { sessionID, agent, model: { id: "qwen", providerID: "fake" }, system: [], messages: [], options: {}, tools: Object.fromEntries(MCP_TOOLS.map((t) => [t, { description: t }])) }
  await mcp31.hooks["session.context"](event)
  return Object.keys(event.tools)
}
const endRun = async (sessionID) => { mcp31.push("session.execution.succeeded", { sessionID }); await wait(150) }
mcp31.sessions.set("m31-go", { id: "m31-go", title: "/go ABC-31" })
await mcp31.hooks["session.prompt"]({ sessionID: "m31-go", messageID: "m", prompt: { text: "[[command go ABC-31]]\nRequest: « ABC-31 »" }, delivery: "steer" })
await check("[v2 31] a /go of the pilot: its requests without Sonar, Fortify, Confluence nor Kibana", async () => {
  const tools = await pilotContext("m31-go")
  assert.ok(tools.includes("jira_get_issue") && tools.includes("gitlab_create_merge_request") && tools.includes("read"))
  assert.ok(!tools.some((t) => /sonar|fortify|confluence|kibana/i.test(t)), tools.join(","))
})
await check("[v2 31] the same tools from one request of the run to the next (the prefix cache of the server)", async () =>
  assert.deepEqual(await pilotContext("m31-go"), await pilotContext("m31-go")))
await check("[v2 31] another agent of the session is left to its own rules", async () =>
  assert.equal((await pilotContext("m31-go", "coder")).length, MCP_TOOLS.length))
await check("[v2 31] logged once per command, with the servers taken out", () => {
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("MCP servers the command does not use"))
  assert.equal(lines.filter((l) => l.includes('"/go"')).length, 1)
  assert.ok(lines[0].includes('"servers":["sonar","fortify","confluence","kibana"]') || lines[0].includes("sonar"), lines[0])
})
await endRun("m31-go")
await check("[v2 31] the run over: nothing narrowed any more", async () => assert.equal((await pilotContext("m31-go")).length, MCP_TOOLS.length))
await mcp31.hooks["session.prompt"]({ sessionID: "m31-go", messageID: "m2", prompt: { text: "[[command fix]]\nDirectives: « »" }, delivery: "steer" })
await check("[v2 31] /fix chosen next in the same session: Sonar and Fortify back, Confluence and Kibana still out", async () => {
  const tools = await pilotContext("m31-go")
  assert.ok(tools.includes("sonar_search_issues") && tools.includes("fortify_list_issues") && tools.includes("jira_search"))
  assert.ok(!tools.some((t) => /confluence|kibana/i.test(t)))
})
await endRun("m31-go")
await mcp31.hooks["session.prompt"]({ sessionID: "m31-go", messageID: "m3", prompt: { text: "[[command tests InvoiceService]]\nRequest: « InvoiceService »" }, delivery: "steer" })
await check("[v2 31] /tests: no server of the pack at all", async () =>
  assert.ok(!(await pilotContext("m31-go")).some((t) => /jira|gitlab|sonar|fortify|confluence|kibana/i.test(t))))
await endRun("m31-go")
// the analysts of /fortify write a vulnerability card from the code and the Fortify details of their prompt
mcp31.sessions.set("m31-fortify", { id: "m31-fortify", title: "/fortify" })
mcp31.sessions.set("m31-an1", { id: "m31-an1", parentID: "m31-fortify", title: "Analyse V1" })
await mcp31.hooks["session.prompt"]({ sessionID: "m31-fortify", messageID: "m", prompt: { text: "[[command fortify]]\nRequest: « »" }, delivery: "steer" })
await check("[v2 31] an analyst of /fortify: no tool of Jira, Confluence, GitLab or any server of the pack", async () => {
  const tools = await pilotContext("m31-an1", "analyst")
  assert.ok(tools.includes("read") && tools.includes("shell") && tools.includes("artifactory_get_package"), tools.join(","))
  assert.ok(!tools.some((t) => /jira|confluence|gitlab|sonar|fortify|kibana/i.test(t)), tools.join(","))
})
await check("[v2 31] the same tools from one request of the analyst to the next", async () =>
  assert.deepEqual(await pilotContext("m31-an1", "analyst"), await pilotContext("m31-an1", "analyst")))
// (a subagent never gets the question tool: 12)
const withoutQuestion = MCP_TOOLS.filter((t) => t !== "question")
await check("[v2 31] another subagent of /fortify keeps its own rules", async () =>
  assert.deepEqual(await pilotContext("m31-an1", "checker"), withoutQuestion))
await check("[v2 31] the analysts of /fortify logged once", () => {
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("taken out of the requests of the analyst"))
  assert.equal(lines.length, 1)
  assert.ok(lines[0].includes('"/fortify"') && lines[0].includes("jira") && lines[0].includes("gitlab"), lines[0])
})
await endRun("m31-fortify")
mcp31.sessions.set("m31-go2", { id: "m31-go2", title: "/go ABC-32" })
mcp31.sessions.set("m31-an2", { id: "m31-an2", parentID: "m31-go2", title: "Analyse du ticket" })
await mcp31.hooks["session.prompt"]({ sessionID: "m31-go2", messageID: "m", prompt: { text: "[[command go ABC-32]]\nRequest: « ABC-32 »" }, delivery: "steer" })
await check("[v2 31] the analyst of a /go keeps Jira, Confluence and GitLab (its permission rules decide)", async () =>
  assert.deepEqual(await pilotContext("m31-an2", "analyst"), withoutQuestion))
await endRun("m31-go2")

// ---------- 12. what v2 opens that the pack closes ----------
top("t-1", "Conversation")
child("sub-1", "t-1")
await check("[v2 12] code mode and the web search are taken out of every request", async () => {
  const event = await context("t-1", TOOLS)
  assert.ok(!("execute" in event.tools) && !("websearch" in event.tools))
  assert.ok("question" in event.tools && "shell" in event.tools && "webfetch" in event.tools)
})
await check("[v2 12] a subagent's requests have no question tool", async () => {
  const event = await context("sub-1", TOOLS, "general")
  assert.ok(!("question" in event.tools) && !("execute" in event.tools))
  assert.ok("read" in event.tools)
})
for (const tool of ["opencode_session_move", "opencode_worktree_create", "opencode_worktree_remove", "session_move", "worktree_create", "worktree_remove"]) {
  await check(`[v2 12] refused: ${tool}`, () => assert.rejects(() => before("t-1", tool, { directory: home }, "build"), /for the developer/))
}
for (const tool of ["execute", "websearch"]) {
  await check(`[v2 12] refused if called anyway: ${tool}`, () => assert.rejects(() => before("t-1", tool, { code: "await fetch('https://x.invalid')" }, "build"), /not available/))
}
await check("[v2 12] a subagent never asks a question (known by its parent)", () =>
  assert.rejects(() => before("sub-1", "question", { questions: [] }, "general"), /a subagent never asks a question/))
await prompt("sub-2", "You are a subagent spawned by another session.\nFind why the test fails.")
await check("[v2 12] a subagent never asks a question (known by its first prompt)", () =>
  assert.rejects(() => before("sub-2", "question", { questions: [] }, "debugger"), /a subagent never asks a question/))
await check("[v2 12] a top-level session may ask", () => before("t-1", "question", { questions: [] }, "pilot"))

// ---------- 6, 7, 8, 11 through the v2 tool names ----------
await check("[v2] a shell command outside the repository is refused", () => assert.rejects(() => before("t-1", "shell", { command: "cat ~/.zshenv" }), /outside the repository/))
await check("[v2] an environment dump is refused", () => assert.rejects(() => before("t-1", "shell", { command: "export -p" }), /prints the environment/))
await check("[v2] a read outside the repository is refused (path)", () => assert.rejects(() => before("t-1", "read", { path: join(home, ".zshenv") }), /outside the repository/))
await check("[v2] a patch outside the repository is refused", () =>
  assert.rejects(() => before("t-1", "patch", { patchText: "*** Begin Patch\n*** Add File: " + join(home, "x.cs") + "\n+x\n*** End Patch" }), /outside the repository/))
await check("[v2] a build gets 20 minutes and a tool path is rewritten", async () => {
  const input = await before("t-1", "shell", { command: "~/.bin/dotnet build -nologo" })
  assert.equal(input.command, "dotnet build -nologo")
  assert.equal(input.timeout, 1200000)
})
await check("[v2 8] a command of an agent of the pack with timeout 0 (no limit in v2) gets 20 minutes", async () =>
  assert.equal((await before("t-1", "shell", { command: "git fetch origin", timeout: 0 }, "coder")).timeout, 1200000))
await check("[v2 8] the conversation keeps its timeout 0", async () =>
  assert.equal((await before("t-1", "shell", { command: "git fetch origin", timeout: 0 }, "build")).timeout, 0))
await check("[v2 8] the agents of the pack never run a command in the background", async () => {
  assert.equal((await before("t-1", "shell", { command: "dotnet test", background: true }, "coder")).background, false)
  assert.equal((await before("t-1", "subagent", { agent: "coder", description: "x", prompt: "y", background: true }, "pilot")).background, false)
})
await check("[v2 8] a conversation agent keeps its background command", async () =>
  assert.equal((await before("t-1", "shell", { command: "npm run dev", background: true }, "build")).background, true))

// ---------- 16. the same call three times in one answer of the model ----------
const call16 = (messageID, input, tool = "read") => v2.hooks["tool.execute.before"]({ tool, sessionID: "t-1", agent: "coder", messageID, id: "l" + count, input })
await check("[v2 16] two identical calls of one answer run", async () => {
  await call16("loop-1", { path: "src/Foo.cs" })
  await call16("loop-1", { path: "src/Foo.cs" })
})
await check("[v2 16] the third one is refused", () => assert.rejects(() => call16("loop-1", { path: "src/Foo.cs" }), /third identical read call of your answer, a loop/))
await check("[v2 16] another input in the same answer runs", () => call16("loop-1", { path: "src/Bar.cs" }))
await check("[v2 16] the same call in the next answer runs", () => call16("loop-2", { path: "src/Foo.cs" }))

// ---------- 2. the environment of the commands ----------
await check("[v2] the commands of the agents get a stable environment", async () => {
  const invocation = { command: "git fetch", env: {} }
  await v2.hooks["shell.create.before"](invocation)
  assert.equal(invocation.env.GIT_TERMINAL_PROMPT, "0")
  assert.equal(invocation.env.DOTNET_CLI_UI_LANGUAGE, "en")
})
await check("[v2] the commands of the agents never get the server password", async () => {
  const invocation = { command: "git status", env: { PATH: "/usr/bin", OPENCODE_SERVER_PASSWORD: "pw", OPENCODE_PASSWORD: "pw" } }
  await v2.hooks["shell.create.before"](invocation)
  assert.equal(invocation.env.OPENCODE_SERVER_PASSWORD, undefined)
  assert.equal(invocation.env.OPENCODE_PASSWORD, undefined)
  assert.equal(invocation.env.PATH, "/usr/bin")
})
await check("[v2 2] the commands of the agents never get a token of the MCP servers, and keep the Artifactory credentials", async () => {
  const env = { PATH: "/usr/bin", GITLAB_PERSONAL_ACCESS_TOKEN: "t", JIRA_API_TOKEN: "t", confluence_personal_token: "t",
    SONAR_TOKEN: "t", FORTIFY_SSC_TOKEN: "t", SSC_PASSWORD: "t", ATLASSIAN_API_KEY: "t",
    artifactory_user: "u", artifactory_password: "p", ARTIFACTORY_PASSWORD: "p", JIRA_URL: "https://jira.invalid", GITLAB_HOST: "x",
    DB_PASSWORD: "test", NPM_TOKEN: "n" }
  await v2.hooks["shell.create.before"]({ command: "dotnet restore", env })
  for (const gone of ["GITLAB_PERSONAL_ACCESS_TOKEN", "JIRA_API_TOKEN", "confluence_personal_token", "SONAR_TOKEN", "FORTIFY_SSC_TOKEN", "SSC_PASSWORD", "ATLASSIAN_API_KEY"]) {
    assert.equal(env[gone], undefined, gone)
  }
  for (const kept of ["PATH", "artifactory_user", "artifactory_password", "ARTIFACTORY_PASSWORD", "JIRA_URL", "GITLAB_HOST", "DB_PASSWORD", "NPM_TOKEN"]) {
    assert.ok(kept in env, kept)
  }
})
await check("[v2] the commands of the agents get the developer's folders back, not the XDG ones of ~/oc2", async () => {
  const env = { XDG_DATA_HOME: join(home, "oc2", "data"), XDG_CACHE_HOME: join(home, "oc2", "cache"), XDG_STATE_HOME: join(home, "oc2", "state"),
    XDG_CONFIG_HOME: "/etc/xdg-of-the-developer" }
  await v2.hooks["shell.create.before"]({ command: "git fetch", env })
  assert.equal(env.XDG_DATA_HOME, undefined)
  assert.equal(env.XDG_CACHE_HOME, undefined)
  assert.equal(env.XDG_STATE_HOME, undefined)
  assert.equal(env.XDG_CONFIG_HOME, "/etc/xdg-of-the-developer")
})
await check("[v2] the [[run]] scripts get neither the server password nor the XDG folders of ~/oc2", async () => {
  writeFileSync(join(home, ".config", "opencode", "scripts", "envcheck.sh"), 'echo "PW=${OPENCODE_SERVER_PASSWORD:-unset} CACHE=${XDG_CACHE_HOME:-unset} HOME_OK=$([ -n "$HOME" ] && echo yes)"\n')
  const saved = { pw: process.env.OPENCODE_SERVER_PASSWORD, cache: process.env.XDG_CACHE_HOME }
  process.env.OPENCODE_SERVER_PASSWORD = "pw"
  process.env.XDG_CACHE_HOME = join(home, "oc2", "cache")
  try {
    top("env-1", "Env")
    const event = await prompt("env-1", "[[command outil env]]\nState:\n[[run envcheck.sh]]")
    assert.match(event.prompt.text, /PW=unset CACHE=unset HOME_OK=yes/)
  } finally {
    if (saved.pw === undefined) delete process.env.OPENCODE_SERVER_PASSWORD
    else process.env.OPENCODE_SERVER_PASSWORD = saved.pw
    if (saved.cache === undefined) delete process.env.XDG_CACHE_HOME
    else process.env.XDG_CACHE_HOME = saved.cache
  }
})

// ---------- 1 and 3. the command line, the scripts, what the conversation shows, the title ----------
top("cmd-1")
const daily = await prompt("cmd-1", "[[command daily ABC]]\nScope: ABC\nState:\n[[run hello.sh]]\nBuild my morning brief.")
await check("[v2 3] the [[command]] line is removed", () => assert.ok(!daily.prompt.text.includes("[[command")))
await check("[v2 1] the [[run]] lines run in the repository", () => assert.match(daily.prompt.text, /hello from my-api/))
await check("[v2 3] the conversation shows the command, the folder and the branch", () =>
  assert.match(daily.metadata.displayText, /^\/daily ABC — my-api · (branche \S+|HEAD détachée.*)$/))
await check("[v2 3] the presentation is complete for the web interface", () => assert.deepEqual([daily.metadata.comments, daily.metadata.attachments], [[], []]))
await check("[v2 3] a session with no title takes the name of the command", () => assert.deepEqual(v2.calls.update.find((u) => u.sessionID === "cmd-1"), { sessionID: "cmd-1", title: "/daily ABC" }))
await check("[v2 5] then shows the preparation of the command", () => assert.match(v2.sessions.get("cmd-1").title, /^⏳ 0:0\d (préparation|attente du modèle) — \/daily ABC$/))
top("cmd-2", "Mon travail du jour")
await prompt("cmd-2", "[[command daily]]\nBuild my morning brief.")
await check("[v2 3] a session with a title keeps it", () => assert.equal(v2.sessions.get("cmd-2").title.replace(/^⏳ [^—]*— /, ""), "Mon travail du jour"))
for (const id of ["cmd-1", "cmd-2"]) v2.push("session.execution.succeeded", { sessionID: id })
top("cmd-3", "Todo")
const todo = await prompt("cmd-3", "[[command outil todo]]\n- [ ] #1 2026-10-22 relancer\n[[visible]]\nOutil : todo\nSkill : pack-todo")
await check("[v2 3] [[visible]]: what is above is shown, the rest goes to the model", () => {
  assert.equal(todo.metadata.displayText, "- [ ] #1 2026-10-22 relancer")
  assert.equal(todo.prompt.text, "Outil : todo\nSkill : pack-todo")
})
const typed = await prompt("cmd-3", "explique-moi ce service", { displayText: "explique-moi ce service", comments: [], attachments: [], agent: "build" })
await check("[v2 3] a message I type is left as it is", () => {
  assert.equal(typed.prompt.text, "explique-moi ce service")
  assert.equal(typed.metadata.agent, "build")
})
await check("[v2 3] the reminders of my todo list are counted", async () => {
  writeFileSync(join(home, ".config", "opencode", "todo.md"), "- [ ] #1 2020-01-01 vieux rappel\n- [ ] #2 2999-01-01 plus tard\n")
  top("cmd-4", "Todo")
  const event = await prompt("cmd-4", "[[command daily]]\nGo.")
  assert.match(event.metadata.displayText, /· ⏰ 1 rappel$/)
})

// ---------- 7. the folders I name, through the prompt ----------
top("named-1", "Conversation")
await before("named-1", "shell", { command: "git status" }, "build")
await check("[v2 7] before naming a folder", () => assert.rejects(() => before("named-1", "shell", { command: "ls ~/repos/old-api" }, "build"), /outside the repository/))
await prompt("named-1", "Regarde ~/repos/old-api, merci.")
await check("[v2 7] after naming it in a message", () => before("named-1", "shell", { command: "ls ~/repos/old-api" }, "build"))
child("named-sub", "named-1")
await prompt("named-sub", "You are a subagent spawned by another session.\nLook at " + home)
await check("[v2 7] a subagent's prompt names nothing", () => assert.rejects(() => before("named-sub", "shell", { command: "ls " + home }, "analyst"), /outside the repository/))
top("named-2", "Comparaison")
await prompt("named-2", "[[command compare " + other + " ExportService le titre]]\nComparison report: x\nRead-only.")
await check("[v2 7] a folder in the arguments of a command", () => before("named-2", "read", { path: join(other, "src", "x.cs") }, "debugger"))
await check("[v2 7] a file named directly in my home opens nothing: neither my home nor the file", async () => {
  writeFileSync(join(home, ".zshenv"), "export X=1\n")
  writeFileSync(join(home, "notes.txt"), "x\n")
  top("named-3", "Conversation")
  await prompt("named-3", "affiche le contenu de ~/.zshenv et de ~/notes.txt")
  await assert.rejects(() => before("named-3", "shell", { command: "cat ~/.zshenv" }, "build"), /outside the repository/)
  await assert.rejects(() => before("named-3", "shell", { command: "grep -r password ~" }, "build"), /outside the repository/)
  await assert.rejects(() => before("named-3", "read", { path: join(home, "notes.txt") }, "coder"), /outside the repository/)
})
await check("[v2 7] nor a hidden folder of my home, nor the folders of the processes", async () => {
  mkdirSync(join(home, ".ssh"), { recursive: true })
  writeFileSync(join(home, ".ssh", "config"), "Host x\n")
  top("named-4", "Conversation")
  await prompt("named-4", "regarde ~/.ssh/config et /proc/self/environ")
  await assert.rejects(() => before("named-4", "shell", { command: "ls ~/.ssh" }, "build"), /outside the repository/)
  await assert.rejects(() => before("named-4", "shell", { command: "cat /proc/self/environ" }, "build"), /outside the repository|prints the environment/)
})
await check("[v2 7] a file named in another repository names its folder", async () => {
  mkdirSync(join(other, "src"), { recursive: true })
  writeFileSync(join(other, "src", "x.cs"), "class X {}\n")
  top("named-5", "Conversation")
  await prompt("named-5", "regarde " + join(other, "src", "x.cs"))
  await before("named-5", "shell", { command: "ls " + join(other, "src") }, "build")
})

// ---------- 9. one /go, /fix or /fortify at a time per folder ----------
const goText = (args) => "[[command go " + args + "]]\nRequest: « " + args + " »\nTake the ticket from its analysis to its Draft merge request, in this single run."
const lockFile = join(repo, ".git", "opencode-pilot.lock")
top("lock-a")
top("lock-b")
top("lock-c")
const first = await prompt("lock-a", goText("ABC-1"))
await check("[v2 9] a first /go starts", () => assert.doesNotMatch(first.prompt.text, /refusé/))
await check("[v2 9] its lock is a file in the git folder", () => assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "lock-a"))
const second = await prompt("lock-b", goText("ABC-2"))
await check("[v2 9] a second /go in the same folder gets the refusal sentence", () => assert.match(second.prompt.text, /⛔ \/go refusé : \/go tourne déjà dans ce dossier/))
await check("[v2 9] the refused command is still shown as typed", () => assert.equal(second.metadata.displayText, "/go ABC-2"))
await check("[v2 9] and still names its untitled session (no model request for its title)", () =>
  assert.deepEqual(v2.calls.update.find((u) => u.sessionID === "lock-b"), { sessionID: "lock-b", title: "/go ABC-2" }))
await check("[v2 9] no tool runs in the refused turn", () => assert.rejects(() => before("lock-b", "shell", { command: "git status" }, "pilot"), /this run was refused/))
const again = await prompt("lock-a", goText("ABC-1"))
await check("[v2 9] the running session itself may go on", () => assert.doesNotMatch(again.prompt.text, /refusé/))
const fortify = await prompt("lock-c", "[[command fortify 3]]\nFix a batch of Fortify vulnerabilities, from the scan to a Draft merge request")
await check("[v2 9] /fortify is refused while /go runs", () => assert.match(fortify.prompt.text, /⛔ \/fortify refusé : \/go tourne déjà/))
v2.push("session.execution.succeeded", { sessionID: "lock-b" })
v2.push("session.execution.succeeded", { sessionID: "lock-a" })
await wait()
await check("[v2 9] the end of the turn frees the folder and removes the lock file", () => assert.ok(!existsSync(lockFile)))
const third = await prompt("lock-b", goText("ABC-2"))
await check("[v2 9] once the first run is over, another session may run /go", () => assert.doesNotMatch(third.prompt.text, /refusé/))
await check("[v2 9] and the tools of that session run again", () => before("lock-b", "shell", { command: "git status" }, "pilot"))
v2.push("session.execution.failed", { sessionID: "lock-b", error: { type: "provider", message: "x" } })
await wait()
const chat = await prompt("lock-c", "explique-moi ce service")
await check("[v2 9] a conversation is never refused", () => assert.equal(chat.prompt.text, "explique-moi ce service"))
await check("[v2 9] a subagent prompt that quotes a pilot command is not a run of it", async () => {
  child("lock-sub", "lock-a")
  const sub = await prompt("lock-sub", "You are a subagent spawned by another session.\nThe command says: Take the ticket from its analysis to its Draft merge request.")
  assert.doesNotMatch(sub.prompt.text, /refusé/)
  assert.ok(!existsSync(lockFile))
})
await check("[v2 9] nor the prompt of a subagent taken up again (no first line, but a parent)", async () => {
  const sub = await prompt("lock-sub", "Take the ticket from its analysis to its Draft merge request: continue.")
  assert.doesNotMatch(sub.prompt.text, /refusé/)
  assert.ok(!existsSync(lockFile))
})
await check("[v2 9] an older command file, without its [[command]] line, is still a run", async () => {
  top("lock-old")
  await prompt("lock-old", "Request: ABC-5\nTake the ticket from its analysis to its Draft merge request, in this single run.")
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "lock-old")
  v2.push("session.execution.succeeded", { sessionID: "lock-old" })
  await wait()
  assert.ok(!existsSync(lockFile))
})
await check("[v2 9] a /go running in another OpenCode of the machine (the terminal client) holds the folder", async () => {
  writeFileSync(lockFile, JSON.stringify({ session: "ses-elsewhere", command: "fix", since: Date.now() - 120000, pid: process.ppid, host: (await import("node:os")).hostname() }))
  top("lock-d")
  const event = await prompt("lock-d", goText("ABC-3"))
  assert.match(event.prompt.text, /⛔ \/go refusé : \/fix tourne déjà dans ce dossier \(dans un autre OpenCode de cette machine\) depuis 2 min/)
})
await check("[v2 9] a lock left by an OpenCode that stopped is ignored", async () => {
  writeFileSync(lockFile, JSON.stringify({ session: "ses-dead", command: "go", since: Date.now() - 60000, pid: 2147483646, host: (await import("node:os")).hostname() }))
  top("lock-e")
  const event = await prompt("lock-e", goText("ABC-4"))
  assert.doesNotMatch(event.prompt.text, /refusé/)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "lock-e")
  v2.push("session.execution.interrupted", { sessionID: "lock-e", reason: "user" })
  await wait()
  assert.ok(!existsSync(lockFile))
})

await check("[v2 9] OpenCode's background service resumes an interrupted run: the plugin keeps its folder until the run ends", async () => {
  const os = await import("node:os")
  writeFileSync(lockFile, JSON.stringify({ session: "ses-resumed", command: "fix", since: Date.now() - 300000, pid: 2147483646, host: os.hostname() }))
  const svc = fakeV2(repo, { options: { tickMs: 25, mcpWaitMs: 600, service: true, adoptMs: 400 } })
  await v2Plugin.setup(svc.ctx)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "ses-resumed")
  svc.sessions.set("lock-f", { id: "lock-f" })
  const refused = { sessionID: "lock-f", messageID: "m", prompt: { text: goText("ABC-6") }, delivery: "steer" }
  await svc.hooks["session.prompt"](refused)
  assert.match(refused.prompt.text, /⛔ \/go refusé : \/fix tourne déjà dans ce dossier depuis 5 min/)
  svc.sessions.set("ses-resumed", { id: "ses-resumed", title: "/fix" })
  svc.push("session.execution.started", { sessionID: "ses-resumed" })
  await wait(600)
  assert.ok(existsSync(lockFile), "a resumed run keeps the folder past the 2 minutes (here 400 ms)")
  svc.push("session.step.started", { sessionID: "ses-resumed", assistantMessageID: "r1" })
  svc.push("session.text.ended", { sessionID: "ses-resumed", assistantMessageID: "r1", ordinal: 0, text: "🔁 MR mise à jour" })
  svc.push("session.execution.succeeded", { sessionID: "ses-resumed" })
  await wait(150)
  assert.ok(!existsSync(lockFile))
  assert.equal(svc.sessions.get("ses-resumed").title, "✅ /fix")
})
await check("[v2 9] a run that the service does not resume frees the folder after 2 minutes (here 400 ms)", async () => {
  const os = await import("node:os")
  writeFileSync(lockFile, JSON.stringify({ session: "ses-gone", command: "go", since: Date.now() - 60000, pid: 2147483646, host: os.hostname() }))
  const svc = fakeV2(repo, { options: { tickMs: 25, mcpWaitMs: 600, service: true, adoptMs: 400 } })
  await v2Plugin.setup(svc.ctx)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "ses-gone")
  await wait(600)
  assert.ok(!existsSync(lockFile))
})
await check("[v2 9] OpenCode run with serve resumes nothing: the lock of a stopped OpenCode stays ignored", async () => {
  const os = await import("node:os")
  writeFileSync(lockFile, JSON.stringify({ session: "ses-old", command: "go", since: Date.now() - 60000, pid: 2147483646, host: os.hostname() }))
  const plain = fakeV2(repo, { options: { tickMs: 25, mcpWaitMs: 600, service: false } })
  await v2Plugin.setup(plain.ctx)
  plain.sessions.set("lock-g", { id: "lock-g" })
  const event = { sessionID: "lock-g", messageID: "m", prompt: { text: goText("ABC-8") }, delivery: "steer" }
  await plain.hooks["session.prompt"](event)
  assert.doesNotMatch(event.prompt.text, /refusé/)
  plain.push("session.execution.succeeded", { sessionID: "lock-g" })
  await wait()
  assert.ok(!existsSync(lockFile))
})

// ---------- 4. the command chosen in a question ----------
const answered = async (sessionID, labels) => v2.hooks["tool.execute.after"]({ tool: "question", sessionID, agent: "pilot", messageID: "m", id: "q", input: {},
  status: "completed", result: { output: { answers: [labels] }, content: [{ type: "text", text: "x" }], metadata: { answers: [labels] } } })
top("qcm-1", "Daily")
await answered("qcm-1", ["/go ABC-7 (recommandé)"])
v2.push("session.execution.succeeded", { sessionID: "qcm-1" })
await wait()
await check("[v2 4] the chosen command starts when the turn ends", () => assert.deepEqual(v2.calls.command.at(-1), { sessionID: "qcm-1", name: "go", text: "ABC-7" }))
const commands = v2.calls.command.length
top("qcm-2", "Daily")
await answered("qcm-2", ["/fix"])
v2.push("session.execution.failed", { sessionID: "qcm-2", error: { type: "x", message: "y" } })
await wait()
await check("[v2 4] never after a failed turn", () => assert.equal(v2.calls.command.length, commands))
top("qcm-3", "Daily")
await answered("qcm-3", ["/fix"])
v2.push("session.execution.interrupted", { sessionID: "qcm-3", reason: "user" })
await wait()
await check("[v2 4] never after a stopped turn", () => assert.equal(v2.calls.command.length, commands))
child("qcm-sub", "qcm-1")
await answered("qcm-sub", ["/go ABC-8"])
v2.push("session.execution.succeeded", { sessionID: "qcm-sub" })
await wait()
await check("[v2 4] never in a subagent's session", () => assert.equal(v2.calls.command.length, commands))
top("qcm-4", "Daily")
for (const label of ["/init", "/go ABC-9 `rm -rf ~`", "Rien pour l'instant", "/go $(whoami)"]) await answered("qcm-4", [label])
v2.push("session.execution.succeeded", { sessionID: "qcm-4" })
await wait()
await check("[v2 4] only a command of the pack, and never one that would run something", () => assert.equal(v2.calls.command.length, commands))
top("qcm-5", "Outils")
await answered("qcm-5", ["/outil doc"])
v2.push("session.execution.succeeded", { sessionID: "qcm-5" })
await wait()
await check("[v2 4] /outil doc", () => assert.deepEqual(v2.calls.command.at(-1), { sessionID: "qcm-5", name: "outil", text: "doc" }))
top("qcm-6", "Daily")
await answered("qcm-6", ["/daily (recommandé)"])
v2.push("session.execution.succeeded", { sessionID: "qcm-6" })
await wait()
await check("[v2 4] the mark of the recommended option is no argument", () => assert.deepEqual(v2.calls.command.at(-1), { sessionID: "qcm-6", name: "daily", text: "" }))
top("qcm-7", "Daily")
await answered("qcm-7", ["/go ABC-12 avec un feature flag"])
v2.push("session.execution.succeeded", { sessionID: "qcm-7" })
await wait()
await check("[v2 4] an answer I type keeps all its words", () => assert.deepEqual(v2.calls.command.at(-1), { sessionID: "qcm-7", name: "go", text: "ABC-12 avec un feature flag" }))
await check("[v2 7] the arguments of a command chosen in a question never name a folder (the model writes the options)", async () => {
  v2.runCommands = true
  try {
    top("qcm-8", "Outils")
    await answered("qcm-8", ["/outil " + other])
    v2.push("session.execution.succeeded", { sessionID: "qcm-8" })
    await wait()
    assert.deepEqual(v2.calls.command.at(-1), { sessionID: "qcm-8", name: "outil", text: other })
    await assert.rejects(() => before("qcm-8", "shell", { command: "ls " + other }, "build"), /outside the repository/)
    // the prompt of the chained command reaches the plugin first (a loaded machine delays it: the next prompt, mine,
    // would otherwise be taken for it)
    await wait(400)
    await prompt("qcm-8", "[[command outil " + other + "]]\nRun.")
    await before("qcm-8", "shell", { command: "ls " + other }, "build")
  } finally {
    v2.runCommands = false
  }
})

// ---------- 14. the MCP servers still connecting ----------
top("mcp-1", "Jira")
await check("[v2 14] a prompt waits for the MCP servers still connecting", async () => {
  v2.mcpState.status = "pending"
  setTimeout(() => { v2.mcpState.status = "connected" }, 300)
  const started = Date.now()
  await prompt("mcp-1", "lis ABC-1")
  const took = Date.now() - started
  assert.ok(took >= 300 && took < 2000, String(took))
})
await check("[v2 14] no wait when they are connected, failed, disabled or wait for a sign-in", async () => {
  for (const status of ["connected", "failed", "disabled", "needs_auth"]) {
    v2.mcpState.status = status
    const started = Date.now()
    await prompt("mcp-1", "encore")
    assert.ok(Date.now() - started < 250, status)
  }
})
await check("[v2 14] the wait has a limit", async () => {
  v2.mcpState.status = "pending"
  try {
    const started = Date.now()
    await prompt("mcp-1", "et alors ?")
    const took = Date.now() - started
    assert.ok(took >= 600 && took < 2500, String(took))
  } finally {
    v2.mcpState.status = "connected"
  }
})
await check("[v2 14] and only during the first minutes of an instance", async () => {
  const late = fakeV2(repo, { options: { tickMs: 25, mcpWaitMs: 600, mcpBootMs: 0 } })
  await v2Plugin.setup(late.ctx)
  late.mcpState.status = "pending"
  late.sessions.set("mcp-2", { id: "mcp-2", title: "x" })
  await wait(5)
  const started = Date.now()
  await late.hooks["session.prompt"]({ sessionID: "mcp-2", messageID: "m", prompt: { text: "bonjour" }, delivery: "steer" })
  assert.ok(Date.now() - started < 250)
})

// ---------- 5 and 10. progress and outcome in the title ----------
const title = (id) => v2.sessions.get(id).title
top("run-1")
await prompt("run-1", goText("ABC-11"))
v2.push("session.execution.started", { sessionID: "run-1" })
v2.push("session.step.started", { sessionID: "run-1", assistantMessageID: "a1" })
v2.push("session.reasoning.delta", { sessionID: "run-1", assistantMessageID: "a1", delta: "x".repeat(8000) })
await wait()
await check("[v2 5] the title shows the reasoning", () => assert.match(title("run-1"), /^⏳ 0:0\d réflexion 2,0k tokens — \/go ABC-11$/))
v2.push("session.tool.input.started", { sessionID: "run-1", assistantMessageID: "a1", id: "t1", name: "subagent" })
v2.push("session.tool.called", { sessionID: "run-1", assistantMessageID: "a1", id: "t1", input: { agent: "checker", description: "Auto-review", prompt: "x" } })
v2.push("session.tool.progress", { sessionID: "run-1", assistantMessageID: "a1", id: "t1", metadata: { sessionID: "run-1-child", status: "running" } })
child("run-1-child", "run-1", "Auto-review")
v2.push("session.execution.started", { sessionID: "run-1-child" })
v2.push("session.retry.scheduled", { sessionID: "run-1-child", assistantMessageID: "c1", attempt: 3, at: 1, error: { type: "provider", message: "Gateway Time-out" } })
await wait()
await check("[v2 5] a retry of the subagent shows in the parent title", () =>
  assert.match(title("run-1"), /^⏳ \d+:\d\d outil · Auto-review · nouvel essai 3 \(serveur du modèle\) — \/go ABC-11$/))
v2.push("permission.asked", { sessionID: "run-1-child", id: "per1", action: "external_directory" })
await wait()
await check("[v2 5] an approval the subagent waits for shows in the parent title", () =>
  assert.match(title("run-1"), /^❓ \d+:\d\d Auto-review · autorisation attendue — \/go ABC-11$/))
await check("[v2 5] the subagent's title is never touched", () => assert.equal(title("run-1-child"), "Auto-review"))
v2.push("permission.replied", { sessionID: "run-1-child", requestID: "per1" })
v2.push("session.execution.succeeded", { sessionID: "run-1-child" })
v2.push("session.tool.success", { sessionID: "run-1", assistantMessageID: "a1", id: "t1", content: [{ type: "text", text: "ok" }], metadata: { sessionID: "run-1-child", status: "completed" } })
v2.push("form.created", { form: { id: "f1", sessionID: "run-1", title: "Questions", fields: [] } })
await wait()
await check("[v2 5] a question that waits for me", () => assert.match(title("run-1"), /^❓ \d+:\d\d réponse attendue — \/go ABC-11$/))
v2.push("form.replied", { id: "f1", sessionID: "run-1", answer: {} })
v2.push("session.step.started", { sessionID: "run-1", assistantMessageID: "a2" })
v2.push("session.text.ended", { sessionID: "run-1", assistantMessageID: "a2", ordinal: 0, text: "**[ABC-11](x) - Export**\n🚀 MR en Draft : https://gitlab/x/-/merge_requests/42" })
v2.push("session.execution.succeeded", { sessionID: "run-1" })
await wait(150)
await check("[v2 10] delivered: ✅ and the progress is gone", () => assert.equal(title("run-1"), "✅ /go ABC-11"))
await prompt("run-1", goText("ABC-11"))
v2.push("session.execution.started", { sessionID: "run-1" })
v2.push("session.step.started", { sessionID: "run-1", assistantMessageID: "a3" })
await wait()
await check("[v2 10] the mark goes away when the next turn starts", () => assert.match(title("run-1"), /^⏳ \d+:\d\d (attente du modèle|préparation) — \/go ABC-11$/))
v2.push("session.text.ended", { sessionID: "run-1", assistantMessageID: "a3", ordinal: 0, text: "**[ABC-11](x)**\n⛔ Arrêt à l'étape 3 : build en échec.\n| # | Étape | ✅ |\n| 1 | a | ✅ |" })
v2.push("session.execution.succeeded", { sessionID: "run-1" })
await wait(150)
await check("[v2 10] a stop after a table of done steps: ⛔", () => assert.equal(title("run-1"), "⛔ /go ABC-11"))
top("run-2")
await prompt("run-2", "[[command fix]]\nBring the branch to a green, review-ready state.")
v2.push("session.execution.started", { sessionID: "run-2" })
v2.push("session.execution.failed", { sessionID: "run-2", error: { type: "provider.auth", message: "Unauthorized", status: 401 } })
await wait(150)
await check("[v2 10] a run that failed for good (the provider refuses the credentials): ⛔", () => assert.equal(title("run-2"), "⛔ /fix"))
top("run-3")
await prompt("run-3", "[[command fortify]]\nFix a batch of Fortify vulnerabilities.")
v2.push("session.execution.started", { sessionID: "run-3" })
v2.push("session.execution.interrupted", { sessionID: "run-3", reason: "user" })
await wait(150)
await check("[v2 10] a run I stopped: ⛔", () => assert.equal(title("run-3"), "⛔ /fortify"))
top("run-4", "Une question")
await prompt("run-4", "explique-moi le service")
v2.push("session.execution.started", { sessionID: "run-4" })
v2.push("session.step.started", { sessionID: "run-4", assistantMessageID: "b1" })
v2.push("session.text.ended", { sessionID: "run-4", assistantMessageID: "b1", ordinal: 0, text: "🚀 voilà" })
await wait()
await check("[v2 5] a conversation shows its progress too", () => assert.match(title("run-4"), /^⏳ \d+:\d\d attente du modèle — Une question$/))
v2.push("session.execution.succeeded", { sessionID: "run-4" })
await wait(150)
await check("[v2 10] a conversation is never marked", () => assert.equal(title("run-4"), "Une question"))
top("run-5")
await prompt("run-5", "bonjour")
v2.push("session.execution.started", { sessionID: "run-5" })
await wait()
await check("[v2 5] never on a session OpenCode has not named yet", () => assert.equal(title("run-5"), undefined))
v2.push("session.execution.succeeded", { sessionID: "run-5" })
await check("[v2 5] another folder's sessions are left alone", async () => {
  top("foreign-1", "Ailleurs")
  v2.push("session.execution.started", { sessionID: "foreign-1" })
  await wait()
  assert.equal(title("foreign-1"), "Ailleurs")
})

// ---------- 13. the outputs of old tool calls ----------
// each output: 80 000 characters, about 20 000 tokens
const result = (n, name = "shell") => ({ type: "tool-result", id: "r" + n, name, result: { type: "text", value: "o".repeat(80000) } })
const call = (n, name = "shell") => ({ type: "tool-call", id: "r" + n, name, input: {} })
const turn = (n, name) => [{ role: "assistant", content: [call(n, name)] }, { role: "tool", content: [result(n, name)] }]
const conversation = () => [
  { role: "user", content: [{ type: "text", text: "/go ABC-1" }] },
  ...turn(1), ...turn(2, "skill"), ...turn(3), ...turn(4), ...turn(5), ...turn(6),
  { role: "user", content: [{ type: "text", text: "et maintenant /fix" }] },
  ...turn(7),
  { role: "user", content: [{ type: "text", text: "merci" }] },
  ...turn(8),
]
const cleared = (messages) => messages.flatMap((m) => (m.role === "tool" ? m.content : [])).filter((p) => p.result.value === "[Old tool result content cleared]").map((p) => p.id)
await check("[v2 13] old outputs beyond the 40k most recent tokens are cleared", () => {
  const messages = conversation()
  prune(messages)
  assert.deepEqual(cleared(messages), ["r1", "r3", "r4"])
})
await check("[v2 13] the skills and the last two messages I typed are kept", () => {
  const messages = conversation()
  prune(messages)
  const kept = messages.flatMap((m) => (m.role === "tool" ? m.content : [])).filter((p) => p.result.value !== "[Old tool result content cleared]").map((p) => p.id)
  assert.deepEqual(kept.sort(), ["r2", "r5", "r6", "r7", "r8"])
})
await check("[v2 13] nothing is cleared below 20k tokens to free", () => {
  const messages = [{ role: "user", content: [{ type: "text", text: "a" }] }, ...turn(1), ...turn(3), ...turn(4),
    { role: "user", content: [{ type: "text", text: "b" }] }, { role: "user", content: [{ type: "text", text: "c" }] }]
  assert.equal(prune(messages), 0)
})
await check("[v2 13] a request is pruned when opencode.json says compaction.prune", async () => {
  const event = await context("t-1", ["shell"], "build", conversation())
  assert.deepEqual(cleared(event.messages), ["r1", "r3", "r4"])
})
// the prefix cache of the server (vLLM): a request reuses what the server computed for the previous one only as far as
// they are the same from the start. Within a turn (no new message of mine), what the plugin sends never changes the
// part of the conversation it already sent: only what is new is read again
await check("[v2 13, 17, 21] within a turn, each request starts with the whole previous one, as the plugin sent it", async () => {
  const sent = []
  let messages = conversation()
  for (let n = 9; n <= 14; n++) {
    const event = await context("t-1", ["shell", "read"], "build", structuredClone(messages))
    sent.push(JSON.stringify(event.messages))
    messages = [...messages, ...turn(n)]
  }
  for (let i = 1; i < sent.length; i++) {
    const before = JSON.parse(sent[i - 1])
    const after = JSON.parse(sent[i])
    assert.deepEqual(after.slice(0, before.length), before, "request " + i + " rewrote what request " + (i - 1) + " sent")
  }
})
await check("[v2 28] the options of an agent never touch the conversation: the same messages from one request to the next", async () => {
  const body = plainChat({ messages: conversation().map((m) => ({ role: m.role, content: "x" })) })
  const { body: first } = await sentBy("pilot", body)
  const { body: second } = await sentBy("pilot", { ...body, messages: [...body.messages, { role: "user", content: "y" }] })
  assert.deepEqual(second.messages.slice(0, first.messages.length), first.messages)
})
// ---------- 13. within a run: the oldest tool outputs, once a request passes 60 % of what the model takes ----------
const CLEARED_TEXT = "[Old tool result content cleared to keep the context small: call the tool again if you need it]"
const output13 = (n, chars, name = "shell") => ({ type: "tool-result", id: "q" + n, name, result: { type: "text", value: "x".repeat(chars) } })
const step13 = (n, chars, name = "shell") => [{ role: "assistant", content: [{ type: "tool-call", id: "q" + n, name, input: {} }] }, { role: "tool", content: [output13(n, chars, name)] }]
// a run: the command, then <count> tool outputs of <chars> characters (32 000: 8 000 tokens)
const run13 = (count, chars, names = {}) => [{ role: "user", content: [{ type: "text", text: "/go ABC-13" }] },
  ...Array.from({ length: count }, (_, i) => step13(i + 1, chars, names[i + 1])).flat()]
const ids13 = (messages, value = CLEARED_TEXT) => messages.flatMap((m) => (m.role === "tool" ? m.content : [])).filter((p) => p.result.value === value).map((p) => p.id)
await check("[v2 13 run] past 60 % of 98 304 tokens: the oldest outputs cleared down to 35 %", () => {
  const messages = run13(10, 32000)
  const freed = clearOldOutputs(messages, [], 98304, new Set())
  assert.deepEqual(ids13(messages), ["q1", "q2", "q3", "q4", "q5", "q6"])
  assert.equal(freed, 48000)
  assert.ok(requestTokens(messages, []) <= 98304 * 0.35, String(requestTokens(messages, [])))
})
await check("[v2 13 run] never a skill, the report of a subagent, an answer, an MCP call, nor the 3 most recent outputs", () => {
  const messages = run13(12, 32000, { 1: "skill", 2: "subagent", 3: "question", 4: "jira_get_issue", 5: "gitlab_get_job_log", 6: "read", 7: "grep" })
  clearOldOutputs(messages, [], 98304, new Set())
  assert.deepEqual(ids13(messages), ["q6", "q7", "q8", "q9"])
})
await check("[v2 13 run] below 60 %: nothing cleared", () => {
  const messages = run13(6, 32000)
  assert.equal(clearOldOutputs(messages, [], 98304, new Set()), 0)
  assert.deepEqual(ids13(messages), [])
})
await check("[v2 13 run] less than 10 000 tokens to free: nothing cleared (the start of the request stays as it was)", () => {
  const messages = run13(5, 400, { 1: "skill", 2: "shell" })
  messages[2].content[0].result.value = "x".repeat(240000)
  messages[4].content[0].result.value = "x".repeat(8000)
  assert.equal(clearOldOutputs(messages, [], 98304, new Set()), 0)
  assert.deepEqual(ids13(messages), [])
})
await check("[v2 13 run] what is cleared stays cleared: the next requests start as the previous one did", () => {
  const cleared = new Set()
  const first = run13(10, 32000)
  clearOldOutputs(first, [], 98304, cleared)
  const sent = JSON.stringify(first)
  const next = [...run13(10, 32000), ...step13(11, 400)]
  assert.equal(clearOldOutputs(next, [], 98304, cleared), 0)
  assert.deepEqual(next.slice(0, first.length), JSON.parse(sent))
})
await check("[v2 13 run] what the model takes: limit.context - limit.output of its model in opencode.json", () => {
  const model = { providerID: "fake", id: "qwen" }
  assert.equal(usableTokens({ "fake/qwen": { context: 65536, output: 16384 } }, model), 49152)
  assert.equal(usableTokens({ "fake/qwen": { context: 200000 } }, model), 167232)
  assert.equal(usableTokens({ "fake/qwen": { context: 40000, output: 32768 } }, model), 20000)
  assert.equal(usableTokens({}, model), 98304)
  assert.equal(usableTokens(undefined, undefined), 98304)
})
await check("[v2 13 run] the hook clears within a run, from the limit of the model, and logs it once", async () => {
  writeFileSync(join(configDir, "opencode.json"), JSON.stringify({ compaction: { prune: true }, provider: { fake: { models: { qwen: { limit: { context: 40000, output: 32768 } } } } } }))
  const small = fakeV2(repo)
  await v2Plugin.setup(small.ctx)
  small.sessions.set("t13", { id: "t13", title: "/go ABC-13" })
  for (let i = 0; i < 2; i++) {
    const event = { sessionID: "t13", agent: "pilot", model: { id: "qwen", providerID: "fake" }, system: [], messages: run13(6, 32000), tools: {} }
    await small.hooks["session.context"](event)
    assert.deepEqual(ids13(event.messages), ["q1", "q2", "q3"])
  }
  const lines = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8").split("\n").filter((l) => l.includes("old tool outputs cleared"))
  assert.equal(lines.length, 1)
  assert.ok(lines[0].includes('"agent":"pilot"') && lines[0].includes('"tokens":24000'), lines[0])
})
await check("[v2 13] and left whole otherwise", async () => {
  writeFileSync(join(configDir, "opencode.json"), JSON.stringify({ compaction: { prune: false } }))
  const other2 = fakeV2(repo)
  await v2Plugin.setup(other2.ctx)
  const event = { sessionID: "t-x", agent: "build", messages: conversation(), tools: {} }
  other2.sessions.set("t-x", { id: "t-x", title: "x" })
  await other2.hooks["session.context"](event)
  assert.deepEqual(cleared(event.messages), [])
})

// ---------- the log of the plugin: a file next to the log of OpenCode (the background service drops the server output) ----------
await check("[v2] the refusals are written to <XDG data>/opencode/log/openrd-pack.log, without the command", () => {
  const text = readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8")
  assert.match(text, /^\d{4}-\d\d-\d\dT[\d:.]+Z \[openrd-pack\] event stream connected for /m)
  assert.match(text, /\[openrd-pack\] refused by the pack \{"agent":"coder","tool":"bash","reason":"it prints the environment"\}/)
  assert.doesNotMatch(text, /export -p/)
})

// ---------- 15. the folder of a worktree (an OpenCode workspace) in the titles of its sessions ----------
const wt = fakeV2(workspace)
await v2Plugin.setup(wt.ctx)
const wtPrompt = async (sessionID, text) => {
  const event = { sessionID, messageID: "m", prompt: { text }, delivery: "steer" }
  await wt.hooks["session.prompt"](event)
  return event
}
wt.sessions.set("wt-1", { id: "wt-1" })
await wtPrompt("wt-1", "[[command go ABC-21]]\nRequest: « ABC-21 »\nTake the ticket from its analysis to its Draft merge request, in this single run.")
await check("[v2 15] a command names its session after the folder of the worktree", () => assert.equal(wt.calls.update[0].title, "[brave-fox] /go ABC-21"))
wt.push("session.execution.started", { sessionID: "wt-1" })
await wait()
await check("[v2 15] the progress keeps the folder", () => assert.match(wt.sessions.get("wt-1").title, /^⏳ \d+:\d\d [^—]+ — \[brave-fox\] \/go ABC-21$/))
wt.push("session.step.started", { sessionID: "wt-1", assistantMessageID: "w1" })
wt.push("session.text.ended", { sessionID: "wt-1", assistantMessageID: "w1", ordinal: 0, text: "🚀 MR en Draft : https://gitlab/x/-/merge_requests/7" })
wt.push("session.execution.succeeded", { sessionID: "wt-1" })
await wait(150)
await check("[v2 15] the outcome comes before the folder", () => assert.equal(wt.sessions.get("wt-1").title, "✅ [brave-fox] /go ABC-21"))
wt.sessions.set("wt-2", { id: "wt-2", title: "New session - 2026-10-22T10:00:00.000Z" })
await wtPrompt("wt-2", "explique-moi ce service")
wt.push("session.execution.started", { sessionID: "wt-2" })
wt.push("session.execution.succeeded", { sessionID: "wt-2" })
await wait(150)
await check("[v2 15] never on a title OpenCode has not generated yet", () => assert.equal(wt.sessions.get("wt-2").title, "New session - 2026-10-22T10:00:00.000Z"))
wt.sessions.get("wt-2").title = "Explication du service"
wt.push("session.renamed", { sessionID: "wt-2", title: "Explication du service" })
await wait(150)
await check("[v2 15] a title OpenCode generates after the turn gets the folder", () => assert.equal(wt.sessions.get("wt-2").title, "[brave-fox] Explication du service"))
wt.sessions.set("wt-3", { id: "wt-3", title: "New session - 2026-10-22T10:01:00.000Z" })
await wtPrompt("wt-3", "bonjour")
wt.push("session.execution.started", { sessionID: "wt-3" })
await wait(10)
wt.sessions.get("wt-3").title = "Salutations"
wt.push("session.renamed", { sessionID: "wt-3", title: "Salutations" })
wt.push("session.execution.succeeded", { sessionID: "wt-3" })
await wait(200)
await check("[v2 15] so does a title generated during a short turn", () => assert.equal(wt.sessions.get("wt-3").title, "[brave-fox] Salutations"))
wt.sessions.set("wt-sub", { id: "wt-sub", parentID: "wt-1", title: "Auto-review" })
await wtPrompt("wt-sub", "You are a subagent spawned by another session.\nReview the diff.")
wt.push("session.renamed", { sessionID: "wt-sub", title: "Auto-review" })
await wait(100)
await check("[v2 15] never in a subagent's session", () => assert.equal(wt.sessions.get("wt-sub").title, "Auto-review"))
await check("[v2 15] never in the main checkout", () => assert.equal(v2.sessions.get("run-1").title.startsWith("⛔ /go"), true))

// ---------- 9 and 15. two runs at the same time, one in the main checkout and one in its worktree ----------
await check("[v2 9] a /go in the main checkout and a /go in its worktree run together, each with its own lock", async () => {
  const main = fakeV2(mainRepo)
  await v2Plugin.setup(main.ctx)
  const mainPrompt = async (sessionID, text) => {
    const event = { sessionID, messageID: "m", prompt: { text }, delivery: "steer" }
    await main.hooks["session.prompt"](event)
    return event
  }
  main.sessions.set("par-main", { id: "par-main", title: "/go ABC-30" })
  wt.sessions.set("par-wt", { id: "par-wt", title: "/go ABC-31" })
  wt.sessions.set("par-wt2", { id: "par-wt2", title: "/push" })
  const a = await mainPrompt("par-main", goText("ABC-30"))
  const b = await wtPrompt("par-wt", goText("ABC-31"))
  assert.doesNotMatch(a.prompt.text, /refusé/)
  assert.doesNotMatch(b.prompt.text, /refusé/)
  const mainLock = join(mainRepo, ".git", "opencode-pilot.lock")
  const wtLock = join(mainRepo, ".git", "worktrees", "brave-fox", "opencode-pilot.lock")
  assert.equal(JSON.parse(readFileSync(mainLock, "utf8")).session, "par-main")
  assert.equal(JSON.parse(readFileSync(wtLock, "utf8")).session, "par-wt")
  // a second git command in the worktree waits for its own run only
  const c = await wtPrompt("par-wt2", "[[command push feat: x]]\nCommit and push the work of this folder now.")
  assert.match(c.prompt.text, /⛔ \/push refusé : \/go tourne déjà dans ce dossier/)
  wt.push("session.execution.succeeded", { sessionID: "par-wt2" })
  main.push("session.execution.started", { sessionID: "par-main" })
  wt.push("session.execution.started", { sessionID: "par-wt" })
  main.push("session.step.started", { sessionID: "par-main", assistantMessageID: "pm" })
  main.push("session.text.ended", { sessionID: "par-main", assistantMessageID: "pm", ordinal: 0, text: "🚀 MR en Draft : https://gitlab/x/-/merge_requests/30" })
  main.push("session.execution.succeeded", { sessionID: "par-main" })
  await wait(150)
  // the end of the run of the main checkout frees its folder only
  assert.ok(!existsSync(mainLock))
  assert.equal(JSON.parse(readFileSync(wtLock, "utf8")).session, "par-wt")
  wt.push("session.step.started", { sessionID: "par-wt", assistantMessageID: "pw" })
  wt.push("session.text.ended", { sessionID: "par-wt", assistantMessageID: "pw", ordinal: 0, text: "🚀 MR en Draft : https://gitlab/x/-/merge_requests/31" })
  wt.push("session.execution.succeeded", { sessionID: "par-wt" })
  await wait(150)
  assert.ok(!existsSync(wtLock))
  assert.equal(main.sessions.get("par-main").title, "✅ /go ABC-30")
  assert.equal(wt.sessions.get("par-wt").title, "✅ [brave-fox] /go ABC-31")
})

// ---------- the references of opencode.json, in OPENCODE_CONFIG_DIR, with comments and trailing commas ----------
await check("[v2] the references of opencode.json in OPENCODE_CONFIG_DIR are readable, comments and trailing commas included", async () => {
  const ocDir = join(home, "oc2", "config", "opencode")
  const referenced = join(home, "repos", "legacy-ref")
  mkdirSync(ocDir, { recursive: true })
  mkdirSync(referenced, { recursive: true })
  writeFileSync(join(referenced, "README.md"), "legacy\n")
  writeFileSync(join(ocDir, "opencode.json"), '{\n  // my settings\n  "model": "fake/qwen",\n  "references": { "legacy": { "path": "' + referenced + '", }, },\n}\n')
  process.env.OPENCODE_CONFIG_DIR = ocDir
  try {
    const ref = fakeV2(repo)
    await v2Plugin.setup(ref.ctx)
    ref.sessions.set("ref-s", { id: "ref-s", title: "x" })
    const read = (path, id) => ref.hooks["tool.execute.before"]({ tool: "read", sessionID: "ref-s", agent: "coder", messageID: "m", id, input: { path } })
    await read(join(referenced, "README.md"), "r1")
    await assert.rejects(() => read(join(home, "repos", "unreferenced", "README.md"), "r2"), /outside the repository/)
  } finally {
    delete process.env.OPENCODE_CONFIG_DIR
  }
})

// ---------- 5. several tools at once, the time before a retry, the summary of the context ----------
const quick = { tickMs: 25, mcpWaitMs: 600, resumeFailureMs: [600000], resumeUnfinishedMs: 600000 }
const par = fakeV2(repo, { options: quick })
await v2Plugin.setup(par.ctx)
const parPrompt = (sessionID, text) => par.hooks["session.prompt"]({ sessionID, messageID: "m", prompt: { text }, delivery: "steer" })
const parTitle = () => par.sessions.get("par-1").title
par.sessions.set("par-1", { id: "par-1", agent: "pilot" })
await parPrompt("par-1", "[[command fortify 3]]\nFix a batch of Fortify vulnerabilities.")
par.push("session.execution.started", { sessionID: "par-1" })
par.push("session.step.started", { sessionID: "par-1", assistantMessageID: "p1" })
for (const [id, description] of [["a1", "Analyse V1"], ["a2", "Analyse V2"], ["a3", "Analyse V3"]]) {
  par.push("session.tool.input.started", { sessionID: "par-1", assistantMessageID: "p1", id, name: "subagent" })
  par.push("session.tool.called", { sessionID: "par-1", assistantMessageID: "p1", id, input: { agent: "analyst", description, prompt: "x" } })
  par.push("session.tool.progress", { sessionID: "par-1", assistantMessageID: "p1", id, metadata: { sessionID: "par-1-" + id, status: "running" } })
}
await wait()
await check("[v2 5] several subagents at once: all of them in the title", () => assert.match(parTitle(), /^⏳ \d+:\d\d outils \(3\) · Analyse V1, Analyse V2, Analyse V3 — \/fortify 3$/))
par.push("session.retry.scheduled", { sessionID: "par-1-a2", assistantMessageID: "c", attempt: 4, at: Date.now() + 45000, error: { type: "provider.internal", message: "Gateway Time-out", status: 504 } })
await wait()
await check("[v2 5 and 18] the one that waits for a retry, and when it comes", () =>
  assert.match(parTitle(), /^⏳ \d+:\d\d outils \(3\) · Analyse V1, Analyse V2, Analyse V3 · nouvel essai 4 dans 4\d s \(serveur du modèle\) — \/fortify 3$/))
par.push("session.retry.scheduled", { sessionID: "par-1-a2", assistantMessageID: "c", attempt: 5, at: Date.now() + 12000, error: { type: "provider.rate-limit", message: "Too Many Requests", status: 429 } })
await wait()
await check("[v2 5 and 18] a rate limit is said as such, not as a failure of the server", () =>
  assert.match(parTitle(), /^⏳ \d+:\d\d outils \(3\) · Analyse V1, Analyse V2, Analyse V3 · nouvel essai 5 dans 1\d s \(serveur du modèle : trop de requêtes\) — \/fortify 3$/))
par.push("session.retry.scheduled", { sessionID: "par-1-a2", assistantMessageID: "c", attempt: 4, at: Date.now() + 45000, error: { type: "provider.internal", message: "Gateway Time-out", status: 504 } })
await wait()
par.push("permission.asked", { sessionID: "par-1-a3", id: "per", action: "external_directory" })
await wait()
await check("[v2 5] the one that waits for me first", () => assert.match(parTitle(), /^❓ \d+:\d\d Analyse V3 · autorisation attendue — \/fortify 3$/))
par.push("permission.replied", { sessionID: "par-1-a3", requestID: "per" })
par.push("session.tool.success", { sessionID: "par-1", assistantMessageID: "p1", id: "a1", content: [], metadata: { sessionID: "par-1-a1", status: "completed" } })
await wait()
await check("[v2 5] one done: the others still run", () => assert.match(parTitle(), /^⏳ \d+:\d\d outils \(2\) · Analyse V2, Analyse V3 · nouvel essai 4 dans \d+ s \(serveur du modèle\) — \/fortify 3$/))
par.push("session.tool.success", { sessionID: "par-1", assistantMessageID: "p1", id: "a2", content: [], metadata: { sessionID: "par-1-a2", status: "completed" } })
await wait()
await check("[v2 5] one left: the title of one tool", () => assert.match(parTitle(), /^⏳ \d+:\d\d outil · Analyse V3 — \/fortify 3$/))
par.push("session.tool.failed", { sessionID: "par-1", assistantMessageID: "p1", id: "a3", error: { type: "tool.execution", message: "x" }, metadata: { sessionID: "par-1-a3" } })
await wait()
await check("[v2 5] all done: the pilot again", () => assert.match(parTitle(), /^⏳ \d+:\d\d attente du modèle — \/fortify 3$/))
par.push("session.compaction.started", { sessionID: "par-1", reason: "auto" })
await wait()
await check("[v2 5 and 17] the summary of a full context", () => assert.match(parTitle(), /^⏳ \d+:\d\d résumé du contexte \(conversation trop longue\) — \/fortify 3$/))
par.push("session.compaction.ended", { sessionID: "par-1", reason: "auto", text: "## Objective" })
par.push("session.step.started", { sessionID: "par-1", assistantMessageID: "p2" })
par.push("session.text.ended", { sessionID: "par-1", assistantMessageID: "p2", ordinal: 0, text: "🔒 Lot Fortify app / develop\n🚀 MR en Draft : https://gitlab/x/-/merge_requests/9\n| V1 | ✅ |" })
par.push("session.execution.succeeded", { sessionID: "par-1" })
await wait(150)
await check("[v2 10] /fortify delivered: ✅", () => assert.equal(parTitle(), "✅ /fortify 3"))

// ---------- 17. a run that goes on after a summary of its conversation ----------
const sum = fakeV2(repo, { options: { ...quick, random: () => 0.4 } })
await v2Plugin.setup(sum.ctx)
const sumPrompt = async (sessionID, text) => {
  const event = { sessionID, messageID: "m", prompt: { text }, delivery: "steer" }
  await sum.hooks["session.prompt"](event)
  return event
}
const sumHook = async (hook, sessionID, messages, agent = "pilot") => {
  const event = { sessionID, agent, model: { id: "qwen", providerID: "fake" }, system: [{ type: "text", text: "agent prompt" }], messages, options: {}, tools: {} }
  await sum.hooks["session." + hook](event)
  return event
}
const checkpoint = [{ role: "user", content: [{ type: "text", text: "<conversation-checkpoint>\nThe following is a summary...\n<summary>\n## Objective\n- /go ABC-30\n</summary>\n</conversation-checkpoint>" }] },
  { role: "assistant", content: [{ type: "text", text: "Étape 3/5…" }] }]
const plain = [{ role: "user", content: [{ type: "text", text: "Request: « ABC-30 »" }] }, { role: "assistant", content: [{ type: "text", text: "ok" }] }]
sum.sessions.set("sum-1", { id: "sum-1", title: "/go ABC-30", agent: "pilot" })
const started = await sumPrompt("sum-1", "[[command go ABC-30]]\nRequest: « ABC-30 »\nWorkflow state:\n[[run hello.sh]]\nTake the ticket from its analysis to its Draft merge request, in this single run.\n## 5. Plan steps\nOne subagent each.")
await check("[v2 1] the scripts of the command still run", () => assert.match(started.prompt.text, /hello from my-api/))
await check("[v2 17] no instruction added before a summary", async () => assert.equal((await sumHook("context", "sum-1", plain)).system.length, 1))
const after = await sumHook("context", "sum-1", checkpoint)
await check("[v2 17] after a summary, the run gets its procedure back as instructions", () => {
  assert.equal(after.system.length, 2)
  const note = after.system[1].text
  assert.match(note, /^## The run of \/go goes on after a summary\n/)
  assert.match(note, /workflow-state\.sh --no-fetch --sheet/)
  assert.match(note, /<instructions of \/go>\nRequest: « ABC-30 »\nWorkflow state:\n\(output of hello\.sh: printed when the run started\)\nTake the ticket/)
  assert.match(note, /## 5\. Plan steps\nOne subagent each\.\n<\/instructions of \/go>$/)
  assert.doesNotMatch(note, /hello from my-api/)
})
await check("[v2 17] the summary of a run is asked to keep its state", async () => {
  const event = await sumHook("compaction", "sum-1", checkpoint)
  assert.equal(event.system.length, 2)
  assert.match(event.system[1].text, /^## Summary of a run of the pack\nThis session runs \/go ABC-30 of the pack/)
  assert.match(event.system[1].text, /sessionID and the role of each subagent/)
})
sum.sessions.set("sum-sub", { id: "sum-sub", parentID: "sum-1", title: "Étape 3/5" })
await sumPrompt("sum-sub", "You are a subagent spawned by another session.\nImplement step 3 of ticket ABC-30 in /repo. Report in your format.")
await check("[v2 17] after a summary, a subagent gets its task back", async () => {
  const event = await sumHook("context", "sum-sub", checkpoint, "coder")
  assert.match(event.system[1].text, /^## Your task goes on after a summary\n/)
  assert.match(event.system[1].text, /<task>\nImplement step 3 of ticket ABC-30 in \/repo\. Report in your format\.\n<\/task>$/)
})
await sumPrompt("sum-sub", "Diagnostic du debugger : la date est en UTC. Corrige l'étape 3.")
await check("[v2 17] with what the pilot added when it took it up again", async () => {
  const event = await sumHook("context", "sum-sub", checkpoint, "coder")
  assert.match(event.system[1].text, /Report in your format\.\n\n\(Then the pilot wrote:\)\nDiagnostic du debugger : la date est en UTC\. Corrige l'étape 3\.\n<\/task>$/)
})
await check("[v2 17] the summary of a subagent is asked to keep its work", async () => {
  const event = await sumHook("compaction", "sum-sub", checkpoint, "coder")
  assert.match(event.system[1].text, /^## Summary of the work of a subagent\n/)
})
await check("[v2 18] a run gets more time from the model server: the retries are spread", async () => {
  const event = { sessionID: "sum-1", agent: "pilot", attempt: 2, error: { type: "provider.transport", message: "x" }, decision: { retry: true, delay: 2100 } }
  await sum.hooks["session.retry"](event)
  assert.equal(event.decision.delay, 10000)
  const later = { ...event, attempt: 7, decision: { retry: true, delay: 9800 } }
  await sum.hooks["session.retry"](later)
  assert.equal(later.decision.delay, 60000)
})
await check("[v2 18] and so do its subagents", async () => {
  const event = { sessionID: "sum-sub", agent: "coder", attempt: 3, error: { type: "provider.internal", message: "504" }, decision: { retry: true, delay: 4000 } }
  await sum.hooks["session.retry"](event)
  assert.equal(event.decision.delay, 20000)
})
await check("[v2 18] a rate limit with the wait of the server (Retry-After): that wait, which OpenCode already takes, nothing more", async () => {
  const event = { sessionID: "sum-1", agent: "pilot", attempt: 7, error: { type: "provider.rate-limit", message: "x", status: 429, retryAfterMs: 1500 }, decision: { retry: true, delay: 9800 } }
  await sum.hooks["session.retry"](event)
  assert.equal(event.decision.delay, 9800)
  const zero = { ...event, attempt: 2, error: { ...event.error, retryAfterMs: 0 }, decision: { retry: true, delay: 2100 } }
  await sum.hooks["session.retry"](zero)
  assert.equal(zero.decision.delay, 2100)
})
await check("[v2 18] a rate limit without it: short waits, longer by 0 to 25 % at random (the subagents that run together never ask again at the same moment)", async () => {
  const first = { sessionID: "sum-1", agent: "pilot", attempt: 2, error: { type: "provider.rate-limit", message: "x", status: 429 }, decision: { retry: true, delay: 2100 } }
  await sum.hooks["session.retry"](first)
  assert.equal(first.decision.delay, 3300)
  const later = { ...first, attempt: 7, decision: { retry: true, delay: 9800 } }
  await sum.hooks["session.retry"](later)
  assert.equal(later.decision.delay, 33000)
  const sub = { ...first, sessionID: "sum-sub", agent: "coder", attempt: 11, decision: { retry: true, delay: 10200 } }
  await sum.hooks["session.retry"](sub)
  assert.equal(sub.decision.delay, 33000)
  const failure = { ...later, error: { type: "provider.internal", message: "504", status: 504 }, decision: { retry: true, delay: 9800 } }
  await sum.hooks["session.retry"](failure)
  assert.equal(failure.decision.delay, 60000)
})
await check("[v2 18] the 10 retries of a rate limit: under 4 minutes of waits in all before the run fails (about 8 for a failure of the server)", async () => {
  // OpenCode's own waits for the attempts 2 to 11 (2, 4, 8, then 10 s), through the hook
  const total = async (error) => {
    let waited = 0
    for (const [i, delay] of [2000, 4000, 8000, 10000, 10000, 10000, 10000, 10000, 10000, 10000].entries()) {
      const event = { sessionID: "sum-1", agent: "pilot", attempt: i + 2, error, decision: { retry: true, delay } }
      await sum.hooks["session.retry"](event)
      waited += event.decision.delay
    }
    return waited
  }
  assert.equal(await total({ type: "provider.rate-limit", message: "x", status: 429 }), 223300)
  assert.equal(await total({ type: "provider.internal", message: "504", status: 504 }), 465000)
})
await check("[v2 18] a longer wait the provider asks for stays, and a retry OpenCode refuses stays refused", async () => {
  const asked = { sessionID: "sum-1", agent: "pilot", attempt: 2, error: { type: "provider.rate-limit", message: "x" }, decision: { retry: true, delay: 600000 } }
  await sum.hooks["session.retry"](asked)
  assert.equal(asked.decision.delay, 600000)
  const refused = { sessionID: "sum-1", agent: "pilot", attempt: 2, error: { type: "provider.auth", message: "x" }, decision: { retry: false } }
  await sum.hooks["session.retry"](refused)
  assert.deepEqual(refused.decision, { retry: false })
})
sum.sessions.set("sum-3", { id: "sum-3", title: "Daily" })
await sumPrompt("sum-3", "[[command daily]]\nThe day of the developer.")
await check("[v2 18] every command of the pack gets that time (/daily, /push, /sync), not only the pilot's", async () => {
  const event = { sessionID: "sum-3", agent: "build", attempt: 2, error: { type: "provider.transport", message: "x" }, decision: { retry: true, delay: 2100 } }
  await sum.hooks["session.retry"](event)
  assert.equal(event.decision.delay, 10000)
})
sum.sessions.set("sum-2", { id: "sum-2", title: "Question" })
await sumPrompt("sum-2", "explique-moi ce service")
await check("[v2 17 and 18] a conversation: nothing added, OpenCode's own retry timing", async () => {
  assert.equal((await sumHook("context", "sum-2", checkpoint, "build")).system.length, 1)
  assert.equal((await sumHook("compaction", "sum-2", checkpoint, "build")).system.length, 1)
  const event = { sessionID: "sum-2", agent: "build", attempt: 2, error: { type: "provider.transport", message: "x" }, decision: { retry: true, delay: 2100 } }
  await sum.hooks["session.retry"](event)
  assert.equal(event.decision.delay, 2100)
})
sum.push("session.step.started", { sessionID: "sum-1", assistantMessageID: "s9" })
sum.push("session.text.ended", { sessionID: "sum-1", assistantMessageID: "s9", ordinal: 0, text: "**[ABC-30](x) - Export**\n🚀 MR en Draft : https://gitlab/x/-/merge_requests/30" })
sum.push("session.execution.succeeded", { sessionID: "sum-1" })
await wait(150)
await check("[v2 17] once the run is over, a later summary of the session brings nothing back", async () => {
  await sumPrompt("sum-1", "et ce service, il fait quoi ?")
  assert.equal((await sumHook("context", "sum-1", checkpoint)).system.length, 1)
})
await check("[v2 17] a run this instance did not see start (resumed by the service after a restart): the procedure of its command file", async () => {
  const os = await import("node:os")
  mkdirSync(join(configDir, "commands"), { recursive: true })
  writeFileSync(join(configDir, "commands", "go.md"), "---\ndescription: \"x\"\nagent: pilot\n---\n[[command go $ARGUMENTS]]\nRequest: « $ARGUMENTS »\n[[run workflow-state.sh --fetch-all --sheet]]\nTake the ticket from its analysis to its Draft merge request, in this single run.\n")
  writeFileSync(lockFile, JSON.stringify({ session: "ses-adopted", command: "go", args: "ABC-31 sans nouvelle lib", since: Date.now() - 60000, pid: 2147483646, host: os.hostname() }))
  const svc = fakeV2(repo, { options: { ...quick, service: true, adoptMs: 5000 } })
  await v2Plugin.setup(svc.ctx)
  svc.sessions.set("ses-adopted", { id: "ses-adopted", title: "/go ABC-31", agent: "pilot" })
  try {
    const event = { sessionID: "ses-adopted", agent: "pilot", system: [], messages: checkpoint, tools: {} }
    await svc.hooks["session.context"](event)
    assert.match(event.system[0].text, /<instructions of \/go>\nRequest: « ABC-31 sans nouvelle lib »\n\(output of workflow-state\.sh --fetch-all --sheet: printed when the run started\)\nTake the ticket/)
  } finally {
    // the run ends: the folder is free for the next checks
    svc.push("session.step.started", { sessionID: "ses-adopted", assistantMessageID: "ad" })
    svc.push("session.text.ended", { sessionID: "ses-adopted", assistantMessageID: "ad", ordinal: 0, text: "✅ Déjà livré" })
    svc.push("session.execution.succeeded", { sessionID: "ses-adopted" })
    await wait(100)
  }
})
await check("[v2 9] the lock file keeps the arguments of the run", async () => {
  sum.sessions.set("sum-3", { id: "sum-3", title: "/fix", agent: "pilot" })
  await sumPrompt("sum-3", "[[command fix seulement la review]]\nBring the branch to a green, review-ready state.")
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).args, "seulement la review")
  sum.push("session.step.started", { sessionID: "sum-3", assistantMessageID: "s3" })
  sum.push("session.text.ended", { sessionID: "sum-3", assistantMessageID: "s3", ordinal: 0, text: "✅ Rien à corriger" })
  sum.push("session.execution.succeeded", { sessionID: "sum-3" })
  await wait(100)
  assert.ok(!existsSync(lockFile))
})

// ---------- 19. a run that ended before its final answer resumes by itself ----------
const res = fakeV2(repo, { options: { tickMs: 25, mcpWaitMs: 600, resumeFailureMs: [150, 300], resumeUnfinishedMs: 60 } })
await v2Plugin.setup(res.ctx)
res.runPrompts = true
const resPrompt = async (sessionID, text) => {
  const event = { sessionID, messageID: "m", prompt: { text }, delivery: "steer" }
  await res.hooks["session.prompt"](event)
  return event
}
const resTitle = (id) => res.sessions.get(id).title
const answer = (sessionID, text) => {
  res.push("session.step.started", { sessionID, assistantMessageID: "x-" + sessionID })
  res.push("session.text.ended", { sessionID, assistantMessageID: "x-" + sessionID, ordinal: 0, text })
}
const pluginLog = () => readFileSync(join(home, ".local", "share", "opencode", "log", "openrd-pack.log"), "utf8")
res.sessions.set("res-1", { id: "res-1", title: "/fix", agent: "pilot" })
await resPrompt("res-1", "[[command fix]]\nBring the branch to a green, review-ready state.")
res.push("session.execution.started", { sessionID: "res-1" })
res.push("session.execution.failed", { sessionID: "res-1", error: { type: "provider.transport", message: "connect ECONNREFUSED 10.0.0.5:443" } })
await wait(60)
await check("[v2 19] a run the model server stopped: ↻ while its resume waits", () => {
  assert.equal(resTitle("res-1"), "↻ /fix")
  assert.equal(res.calls.prompt.length, 0)
})
await wait(200)
const resumed = res.calls.prompt[0]
await check("[v2 19] then the pilot gets a message that resumes the run, in the same session", () => {
  assert.equal(resumed.sessionID, "res-1")
  assert.match(resumed.text, /^\[\[command fix\]\]\n\[\[resume panne du serveur du modèle\]\]\nThe run of \/fix stopped before its end: the model server failed after OpenCode's retries \(connect ECONNREFUSED 10\.0\.0\.5:443\)\. Continue it now/)
  assert.match(resumed.text, /workflow-state\.sh --no-fetch --sheet/)
  assert.match(resumed.text, /`git log` shows the fixes this run already committed/)
})
await check("[v2 19] the resume is a run of the command: shown as such, the folder held, the lines of the plugin removed", () => {
  assert.match(resumed.event.metadata.displayText, /^↻ \/fix · reprise automatique \(panne du serveur du modèle\) — my-api · /)
  assert.match(resumed.event.prompt.text, /^The run of \/fix stopped before its end/)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "res-1")
})
res.push("session.execution.started", { sessionID: "res-1" })
res.push("session.execution.failed", { sessionID: "res-1", error: { type: "provider.timeout", message: "timeout" } })
await wait(400)
await check("[v2 19] a second failure: a second resume, later", () => {
  assert.equal(res.calls.prompt.length, 2)
  assert.match(res.calls.prompt[1].text, /\(timeout\)/)
})
res.push("session.execution.started", { sessionID: "res-1" })
res.push("session.execution.failed", { sessionID: "res-1", error: { type: "provider.internal", message: "Bad Gateway", status: 502 } })
await wait(400)
await check("[v2 19] a third failure in a row: stopped, ⛔, and the log says why", () => {
  assert.equal(res.calls.prompt.length, 2)
  assert.equal(resTitle("res-1"), "⛔ /fix")
  assert.match(pluginLog(), /run not resumed: 2 automatic resumes in a row already \{"command":"\/fix"/)
  assert.ok(!existsSync(lockFile))
})
await check("[v2 19] a message I type starts the count again, and replaces a resume that waits", async () => {
  await resPrompt("res-1", "[[command fix]]\nBring the branch to a green, review-ready state.")
  res.push("session.execution.started", { sessionID: "res-1" })
  res.push("session.execution.failed", { sessionID: "res-1", error: { type: "provider.transport", message: "reset" } })
  await wait(60)
  assert.equal(resTitle("res-1"), "↻ /fix")
  await resPrompt("res-1", "laisse tomber, je regarde")
  res.push("session.execution.started", { sessionID: "res-1" })
  res.push("session.execution.succeeded", { sessionID: "res-1" })
  await wait(300)
  assert.equal(res.calls.prompt.length, 2)
  assert.match(pluginLog(), /automatic resume cancelled: a new message in the session/)
})
res.sessions.set("res-2", { id: "res-2", title: "/go ABC-41", agent: "pilot" })
await resPrompt("res-2", goText("ABC-41"))
res.push("session.execution.started", { sessionID: "res-2" })
answer("res-2", "Étape 3/5 : validation du montant (coder)…")
res.push("session.execution.succeeded", { sessionID: "res-2" })
await wait(150)
await check("[v2 19] a turn that ended without the final answer: resumed at once", () => {
  assert.equal(res.calls.prompt.length, 3)
  assert.match(res.calls.prompt[2].text, /^\[\[command go ABC-41\]\]\n\[\[resume réponse finale manquante\]\]\nThe run of \/go ABC-41 stopped before its end: your last answer did not end the run/)
})
res.push("session.execution.started", { sessionID: "res-2" })
await res.hooks["session.context"]({ sessionID: "res-2", agent: "pilot", system: [], tools: {}, messages: [...plain, { role: "assistant", content: [{ type: "text", text: "CRITICAL - MAXIMUM STEPS REACHED\n\nThe maximum number of steps..." }] }] })
answer("res-2", "⛔ Nombre maximum d'étapes atteint : il reste les étapes 4 et 5.")
res.push("session.execution.succeeded", { sessionID: "res-2" })
await wait(150)
await check("[v2 19] the step limit of the pilot reached: resumed, whatever its answer says", () => {
  assert.equal(res.calls.prompt.length, 4)
  assert.match(res.calls.prompt[3].text, /\[\[resume limite d'étapes du pilote atteinte\]\]\nThe run of \/go ABC-41 stopped before its end: you reached the step limit of your agent/)
})
res.push("session.execution.started", { sessionID: "res-2" })
answer("res-2", "**[ABC-41](x) - Export**\n⏸ En attente du PO : le format du fichier d'export.")
res.push("session.execution.succeeded", { sessionID: "res-2" })
await wait(150)
await check("[v2 10 and 19] a run that waits for the product owner: ⏸, not resumed", () => {
  assert.equal(resTitle("res-2"), "⏸ /go ABC-41")
  assert.equal(res.calls.prompt.length, 4)
})
for (const [id, text, why] of [
  ["res-3", "**[ABC-42](x)**\n⛔ Contrôle avant push : rien n'a été poussé", "a stop of the run"],
  ["res-4", "**[ABC-43](x)**\n✅ Déjà livré (MR https://gitlab/x/-/merge_requests/3) : /fix pour la CI ou la review", "a final answer"],
]) {
  res.sessions.set(id, { id, title: "/go", agent: "pilot" })
  await resPrompt(id, goText(id))
  res.push("session.execution.started", { sessionID: id })
  answer(id, text)
  res.push("session.execution.succeeded", { sessionID: id })
  await wait(150)
  await check(`[v2 19] never resumed: ${why}`, () => assert.equal(res.calls.prompt.length, 4))
}
res.sessions.set("res-5", { id: "res-5", title: "/go", agent: "pilot" })
await resPrompt("res-5", goText("ABC-44"))
res.push("session.execution.started", { sessionID: "res-5" })
res.push("session.execution.interrupted", { sessionID: "res-5", reason: "user" })
await wait(400)
await check("[v2 19] never resumed: a run I stopped", () => {
  assert.equal(res.calls.prompt.length, 4)
  assert.equal(resTitle("res-5"), "⛔ /go")
})
res.sessions.set("res-6", { id: "res-6", title: "/go", agent: "pilot" })
await resPrompt("res-6", goText("ABC-45"))
res.push("session.execution.started", { sessionID: "res-6" })
res.push("session.execution.failed", { sessionID: "res-6", error: { type: "provider.no-route", message: "Model not found: fake/qwen" } })
await wait(400)
await check("[v2 19] never resumed: a failure a resume cannot solve (no model)", () => {
  assert.equal(res.calls.prompt.length, 4)
  assert.equal(resTitle("res-6"), "⛔ /go")
})
res.sessions.set("res-7", { id: "res-7", title: "/go", agent: "pilot" })
await resPrompt("res-7", goText("ABC-46"))
res.push("session.execution.started", { sessionID: "res-7" })
res.push("session.execution.failed", { sessionID: "res-7", error: { type: "provider.transport", message: "x" } })
await wait(50)
res.sessions.get("res-7").agent = "build"
await wait(300)
await check("[v2 19] never resumed: another agent was chosen in the session meanwhile (I am there)", () => {
  assert.equal(res.calls.prompt.length, 4)
  assert.equal(resTitle("res-7"), "⛔ /go")
})
await check("[v2 19] a conversation that ends without a mark is never resumed", async () => {
  res.sessions.set("res-8", { id: "res-8", title: "Question", agent: "build" })
  await resPrompt("res-8", "explique-moi le service")
  res.push("session.execution.started", { sessionID: "res-8" })
  res.push("session.execution.failed", { sessionID: "res-8", error: { type: "provider.transport", message: "x" } })
  await wait(400)
  assert.equal(res.calls.prompt.length, 4)
  assert.equal(resTitle("res-8"), "Question")
})

// ---------- 21. an answer that repeats itself ----------
const pack21 = await import(join(stub, "openrd-pack.js"))
const { segmentsOf, loopAtEnd, collapseRepeats, sanitizeLoops, watchStream, isContinue, dotnetRunTarget, dependencyChange, scheduleEntries, scheduleAllowed, dueSchedules } = pack21
const loopSentence = "Je vérifie l'API réelle de Blazorise.DataGrid 2.2.2 avant de trancher."
const intro = "Le coder est BLOQUÉ : le mécanisme DataGridLocalization n'existe pas dans Blazorise.DataGrid 2.2.2. "
const looping = intro + Array(20).fill(loopSentence).join(" ")
// a long reasoning that repeats a line here and there: code drafted twice, eight tests with the same set-up line
const drafted = ["Let me write the handler first.", "public async Task<Result> Handle(CreateOrder command, CancellationToken token)",
  "{", "    var order = Order.Create(command.CustomerId, command.Lines);", "    await repository.AddAsync(order, token);", "}",
  "Hmm, the validation must come first, let me rewrite it.",
  "public async Task<Result> Handle(CreateOrder command, CancellationToken token)", "{",
  "    var order = Order.Create(command.CustomerId, command.Lines);", "    await repository.AddAsync(order, token);", "}"].join("\n")
const tests8 = Array.from({ length: 8 }, (_, i) => [
  `[Fact] public async Task Handle_Case${i}_ReturnsExpected()`, "{",
  "    var sut = new OrderService(repository.Object, logger.Object, clock.Object);",
  `    var result = await sut.Handle(Command${i}(), CancellationToken.None);`, `    result.Value.Should().Be(${i});`, "}"].join("\n")).join("\n")
const table = Array.from({ length: 12 }, (_, i) => `| C${i + 1} | implémenté src/Orders/Handler.cs:${10 + i} | testé Handle_Case${i} |`).join("\n")
await check("[v2 21] a sentence repeated again and again: a loop", () => assert.ok(loopAtEnd(looping)))
await check("[v2 21] a cycle of three sentences repeated: a loop", () => {
  const cycle = "Je relis la fiche du ticket. Je vérifie la décision sur la pagination. Puis je relance le coder sur l'étape 1. "
  assert.ok(loopAtEnd("Début. " + cycle.repeat(7)))
})
await check("[v2 21] a loop without any sentence boundary: a loop", () =>
  assert.ok(loopAtEnd("x " + "verifier le parametre Localization de la grille puis ".repeat(30))))
await check("[v2 21] a long reasoning with lines repeated here and there: no loop", () => {
  assert.equal(loopAtEnd(drafted + "\n" + tests8 + "\nNow the table:\n" + table + "\nAll criteria are covered."), null)
  assert.equal(collapseRepeats(drafted + "\n" + tests8 + "\n" + table), null)
})
await check("[v2 21] a sentence said three times is no loop", () =>
  assert.equal(loopAtEnd(intro + Array(3).fill(loopSentence).join(" ")), null))
await check("[v2 21] a stream: the last sentence, still being written, is left out", () => {
  const segments = segmentsOf(looping + " Je vérif")
  assert.equal(segments.at(-1), "je vérif")
  assert.ok(loopAtEnd(looping + " Je vérif", true))
})
await check("[v2 21] a loop in the history is kept once, with a note", () => {
  const text = "Analyse.\n" + Array(15).fill(loopSentence).join("\n") + "\nFin de l'analyse : je lance le coder."
  const short = collapseRepeats(text)
  assert.ok(short.startsWith("Analyse.\n" + loopSentence + "\n[the same sentence repeated 14 more times: removed by the pack]"))
  assert.ok(short.endsWith("Fin de l'analyse : je lance le coder."))
  assert.equal(short.split(loopSentence).length - 1, 1)
})
const NOTE = "Your last response hit the output token limit (stop reason: length). Do not apologize, recap, or repeat yourself. Break the remaining work into smaller pieces."
await check("[v2 21] an answer cut in a loop and the note that followed it leave the request", () => {
  const messages = [
    { role: "system", content: [{ type: "text", text: "s" }] },
    { role: "user", content: [{ type: "text", text: "/go ABC-1" }] },
    { role: "assistant", content: [{ type: "reasoning", text: looping }] },
    { role: "user", content: [{ type: "text", text: NOTE }] },
    { role: "assistant", content: [{ type: "reasoning", text: looping + " " + loopSentence }] },
    { role: "user", content: NOTE },
  ]
  const out = sanitizeLoops(messages)
  assert.deepEqual(out, { dropped: 2, collapsed: 0 })
  assert.deepEqual(messages.map((m) => m.role), ["system", "user"])
})
await check("[v2 21] a loop in an answer with tool calls stays, kept once", () => {
  const messages = [
    { role: "user", content: [{ type: "text", text: "/go ABC-1" }] },
    { role: "assistant", content: [{ type: "reasoning", text: looping + " Je lance le coder." }, { type: "tool-call", id: "t", name: "subagent", input: {} }] },
    { role: "tool", content: [{ type: "tool-result", id: "t", name: "subagent", result: { type: "text", value: looping } }] },
  ]
  const out = sanitizeLoops(messages)
  assert.deepEqual(out, { dropped: 0, collapsed: 1 })
  assert.equal(messages.length, 3)
  assert.match(messages[1].content[0].text, /repeated 19 more times: removed by the pack\]\nJe lance le coder\.$/)
  assert.equal(messages[2].content[0].result.value, looping)
})
await check("[v2 21] a note after an answer that did not loop stays (an answer that was only long)", () => {
  const messages = [{ role: "assistant", content: [{ type: "text", text: drafted }] }, { role: "user", content: NOTE }]
  assert.deepEqual(sanitizeLoops(messages), { dropped: 0, collapsed: 0 })
  assert.equal(messages.length, 2)
})
// a fake model server stream
const sse = (deltas, { finish = "stop", slow = false } = {}) => {
  const enc = new TextEncoder()
  const events = deltas.map((d, i) => "data: " + JSON.stringify({ id: "chatcmpl-1", model: "qwen", choices: [{ index: 0, delta: d, finish_reason: null }] }) + "\n\n")
  events.push("data: " + JSON.stringify({ id: "chatcmpl-1", model: "qwen", choices: [{ index: 0, delta: {}, finish_reason: finish }], usage: { prompt_tokens: 10, completion_tokens: 20 } }) + "\n\n", "data: [DONE]\n\n")
  const state = { sent: 0, cancelled: false }
  const stream = new ReadableStream({
    async pull(controller) {
      if (state.sent >= events.length) return controller.close()
      if (slow) await new Promise((r) => setTimeout(r, 1))
      // split an event in two chunks now and then, as a network does
      const event = events[state.sent++]
      if (state.sent % 3 === 0) { controller.enqueue(enc.encode(event.slice(0, 7))); controller.enqueue(enc.encode(event.slice(7))) }
      else controller.enqueue(enc.encode(event))
    },
    cancel() { state.cancelled = true },
  })
  return { stream, state, events }
}
const readAll = async (stream) => new Response(stream).text()
const reasoningDeltas = (text, size = 37) => { const out = []; for (let i = 0; i < text.length; i += size) out.push({ reasoning_content: text.slice(i, i + size) }); return out }
await check("[v2 21] a stream that loops ends at once as cut at the output limit, and the server request is cancelled", async () => {
  const long = intro + Array(400).fill(loopSentence).join(" ")
  const source = sse(reasoningDeltas(long))
  let found
  const text = await readAll(watchStream(source.stream, { onLoop: (f) => { found = f } }))
  assert.ok(found && found.repeats >= 5, "loop found")
  assert.ok(found.total < 4000, "cut early: " + found.total)
  assert.ok(source.state.cancelled, "upstream cancelled")
  assert.ok(source.state.sent < source.events.length / 2)
  assert.match(text, /"finish_reason":"length"\}\]\}\n\ndata: \[DONE\]\n\n$/)
  // every event sent before the cut is whole
  for (const block of text.trim().split("\n\n")) assert.match(block, /^data: (\{.*\}|\[DONE\])$/)
})
await check("[v2 21] a stream without a loop goes through unchanged", async () => {
  const source = sse([...reasoningDeltas(drafted + "\n" + tests8), { content: "RÉSULTAT : OK\n" + table }], { slow: true })
  let ended = false, found = false
  const text = await readAll(watchStream(source.stream, { onLoop: () => { found = true }, onEnd: () => { ended = true } }))
  assert.equal(text, source.events.join(""))
  assert.ok(ended && !found && !source.state.cancelled)
})
// the hooks, end to end: the cut, the penalty of the next requests, back to normal
const lp = fakeV2(repo)
await v2Plugin.setup(lp.ctx)
lp.sessions.set("loop-1", { id: "loop-1", title: "Étape 1/6", parentID: "p" })
const streamed = async (sessionID, source, kind = "primary") => {
  const event = { sessionID, agent: "coder", kind, request: new Request("https://gw.example/v1/chat/completions"), response: new Response(source.stream, { status: 200, headers: { "content-type": "text/event-stream" } }) }
  await lp.hooks["session.http.response"](event)
  return readAll(event.response.body)
}
const lpContext = async (sessionID, messages = []) => {
  const event = { sessionID, agent: "coder", model: { id: "qwen", providerID: "fake" }, system: [], messages, options: { maxTokens: 32000 }, tools: {} }
  await lp.hooks["session.context"](event)
  return event
}
await check("[v2 21] hooks: a looping answer is cut, the log says so", async () => {
  const text = await streamed("loop-1", sse(reasoningDeltas(intro + Array(400).fill(loopSentence).join(" "))))
  assert.match(text, /"finish_reason":"length"/)
  assert.match(pluginLog(), /an answer that repeated itself was cut \{"agent":"coder","repeats":\d+,"block":\d+,"chars":\d+,"cut":1\}/)
  assert.doesNotMatch(pluginLog(), /Blazorise/)
})
await check("[v2 21] hooks: the next request has presence penalty 1.0, and the cut answer is out", async () => {
  const event = await lpContext("loop-1", [{ role: "user", content: "step" }, { role: "assistant", content: [{ type: "reasoning", text: looping }] }, { role: "user", content: NOTE }])
  assert.equal(event.options.presencePenalty, 1.0)
  assert.equal(event.options.maxTokens, 32000)
  assert.equal(event.messages.length, 1)
})
await check("[v2 21] hooks: a second cut in a row: 1.5", async () => {
  await streamed("loop-1", sse(reasoningDeltas(Array(400).fill(loopSentence).join(" "))))
  assert.equal((await lpContext("loop-1")).options.presencePenalty, 1.5)
})
await check("[v2 21] hooks: an answer that ends normally: the model card's sampling again", async () => {
  await streamed("loop-1", sse(reasoningDeltas(drafted)))
  assert.equal((await lpContext("loop-1")).options.presencePenalty, undefined)
})
await check("[v2 21] hooks: other sessions, titles and summaries are never touched", async () => {
  assert.equal((await lpContext("other")).options.presencePenalty, undefined)
  const source = sse(reasoningDeltas(Array(400).fill(loopSentence).join(" ")))
  const event = { sessionID: "loop-2", agent: "coder", kind: "compaction", request: new Request("https://gw.example/v1/chat/completions"), response: new Response(source.stream, { status: 200, headers: { "content-type": "text/event-stream" } }) }
  await lp.hooks["session.http.response"](event)
  assert.equal(event.response.body, source.stream)
  const json = { sessionID: "loop-2", agent: "coder", kind: "primary", request: new Request("https://gw.example/v1/chat/completions"), response: new Response("{\"error\":\"x\"}", { status: 400, headers: { "content-type": "application/json" } }) }
  const original = json.response
  await lp.hooks["session.http.response"](json)
  assert.equal(json.response, original)
})
await check("[v2 19 and 21] three cuts in a row stop the turn: the run resumes at once, the reason said", async () => {
  const rl = fakeV2(repo, { options: { tickMs: 25, mcpWaitMs: 600, resumeFailureMs: [600000], resumeUnfinishedMs: 40 } })
  await v2Plugin.setup(rl.ctx)
  rl.sessions.set("rl-1", { id: "rl-1", title: "/go ABC-70", agent: "pilot" })
  await rl.hooks["session.prompt"]({ sessionID: "rl-1", messageID: "m", prompt: { text: goText("ABC-70") }, delivery: "steer" })
  rl.push("session.execution.started", { sessionID: "rl-1" })
  rl.push("session.execution.failed", { sessionID: "rl-1", error: { type: "output-limit", message: "Response still truncated after two output token limit continuations" } })
  await wait(200)
  assert.equal(rl.calls.prompt.length, 1)
  assert.match(rl.calls.prompt[0].text, /^\[\[command go ABC-70\]\]\n\[\[resume réponses coupées en boucle\]\]\nThe run of \/go ABC-70 stopped before its end: your answers were cut three times/)
})

// ---------- 22. « continue » after a run that stopped ----------
await check("[v2 22] the words that ask to go on", () => {
  for (const yes of ["continue", "Continue.", "continue stp", "ok continue", "vas-y", "Reprends", "go", "on continue !", "oui, continue", "poursuis"]) assert.ok(isContinue(yes), yes)
  for (const no of ["continue avec un Result", "pourquoi ça plante", "go to the file", "continue la doc de l'API demain", ""]) assert.ok(!isContinue(no), no)
})
const ct = fakeV2(repo)
ct.calls.switch = []
ct.ctx.session.switchAgent = async (input) => { ct.calls.switch.push(input); const s = ct.sessions.get(input.sessionID); if (s) s.agent = input.agent }
await v2Plugin.setup(ct.ctx)
const ctPrompt = async (sessionID, text) => {
  const event = { sessionID, messageID: "m", prompt: { text }, delivery: "steer" }
  await ct.hooks["session.prompt"](event)
  return event
}
await check("[v2 22] « continue » after a /go that stopped: back to the pilot, the run resumes", async () => {
  ct.sessions.set("ct-1", { id: "ct-1", title: "/go ABC-80", agent: "pilot" })
  await ctPrompt("ct-1", goText("ABC-80 avec un Result"))
  ct.push("session.execution.started", { sessionID: "ct-1" })
  ct.push("session.execution.interrupted", { sessionID: "ct-1", reason: "user" })
  await wait(150)
  assert.equal(ct.sessions.get("ct-1").title, "⛔ /go ABC-80")
  ct.sessions.get("ct-1").agent = "build"
  const event = await ctPrompt("ct-1", "continue")
  assert.deepEqual(ct.calls.switch, [{ sessionID: "ct-1", agent: "pilot" }])
  assert.match(event.prompt.text, /^The run of \/go ABC-80 avec un Result stopped before its end: it stopped before its end, and the developer asks you to continue it\. Continue it now/)
  assert.match(event.metadata.displayText, /^↻ \/go ABC-80 avec un Result · reprise demandée — my-api · /)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "ct-1")
  assert.match(pluginLog(), /run resumed at the developer's request \{"command":"\/go"\}/)
  ct.push("session.execution.started", { sessionID: "ct-1" })
  ct.push("session.step.started", { sessionID: "ct-1", assistantMessageID: "c1" })
  ct.push("session.text.ended", { sessionID: "ct-1", assistantMessageID: "c1", ordinal: 0, text: "**[ABC-80](x) - Export**\n🚀 MR en Draft : x" })
  ct.push("session.execution.succeeded", { sessionID: "ct-1" })
  await wait(150)
})
await check("[v2 22] « continue » after a delivered run: a message like any other", async () => {
  assert.equal(ct.sessions.get("ct-1").title, "✅ /go ABC-80")
  const event = await ctPrompt("ct-1", "continue")
  assert.equal(event.prompt.text, "continue")
  assert.equal(ct.calls.switch.length, 1)
})
await check("[v2 22] after a restart of OpenCode: the run named in the title", async () => {
  ct.sessions.set("ct-2", { id: "ct-2", title: "↻ [crisp-river] /fix seulement la review", agent: "build" })
  const event = await ctPrompt("ct-2", "vas-y")
  assert.equal(ct.calls.switch.at(-1).sessionID, "ct-2")
  assert.match(event.prompt.text, /^The run of \/fix seulement la review stopped before its end/)
  ct.push("session.execution.succeeded", { sessionID: "ct-2" })
  await wait(100)
})
await check("[v2 22] never: a run that waits for the PO, a conversation, a longer message, a subagent", async () => {
  ct.sessions.set("ct-3", { id: "ct-3", title: "⏸ /go ABC-81", agent: "build" })
  ct.sessions.set("ct-4", { id: "ct-4", title: "Question sur le cache", agent: "build" })
  ct.sessions.set("ct-5", { id: "ct-5", title: "⛔ /go ABC-82", agent: "build" })
  ct.sessions.set("ct-6", { id: "ct-6", title: "⛔ /go ABC-83", parentID: "ct-5" })
  for (const [id, text] of [["ct-3", "continue"], ["ct-4", "continue"], ["ct-5", "continue mais avec un Result"], ["ct-6", "continue"]]) {
    const event = await ctPrompt(id, text)
    assert.equal(event.prompt.text, text, id)
  }
  assert.equal(ct.calls.switch.length, 2)
})

// ---------- 9. /push and /sync: one git command at a time per folder ----------
await check("[v2 9] /push while a /go runs in the folder: refused, the /go goes on", async () => {
  ct.sessions.set("ct-7", { id: "ct-7", title: "/go ABC-84", agent: "pilot" })
  ct.sessions.set("ct-8", { id: "ct-8", title: "POC", agent: "pilot" })
  await ctPrompt("ct-7", goText("ABC-84"))
  ct.push("session.execution.started", { sessionID: "ct-7" })
  const event = await ctPrompt("ct-8", "[[command push feat: try]]\nCommit and push the work of this folder now.")
  assert.match(event.prompt.text, /^Answer exactly this sentence and nothing else, without any tool: « ⛔ \/push refusé : \/go tourne déjà dans ce dossier/)
  ct.push("session.execution.succeeded", { sessionID: "ct-8" })
  ct.push("session.step.started", { sessionID: "ct-7", assistantMessageID: "c7" })
  ct.push("session.text.ended", { sessionID: "ct-7", assistantMessageID: "c7", ordinal: 0, text: "✅ Déjà livré" })
  ct.push("session.execution.succeeded", { sessionID: "ct-7" })
  await wait(150)
})
await check("[v2 9] /sync takes the folder, and frees it at its end; it is never resumed", async () => {
  const event = await ctPrompt("ct-8", "[[command sync develop]]\nBring the branch up to date now.")
  assert.match(event.metadata.displayText, /^\/sync develop — my-api · /)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).command, "sync")
  ct.push("session.execution.started", { sessionID: "ct-8" })
  ct.push("session.execution.failed", { sessionID: "ct-8", error: { type: "provider.transport", message: "x" } })
  await wait(150)
  assert.ok(!existsSync(lockFile))
  assert.equal(ct.calls.prompt.length, 0)
})
await check("[v2 4] /push chosen in a question starts by itself", async () => {
  ct.sessions.set("ct-9", { id: "ct-9", title: "Conversation", agent: "build" })
  await ctPrompt("ct-9", "pousse mon POC")
  await ct.hooks["tool.execute.after"]({ tool: "question", sessionID: "ct-9", status: "completed", result: { output: { answers: [["/push (recommandé)"]] } } })
  ct.push("session.execution.succeeded", { sessionID: "ct-9" })
  await wait(100)
  assert.deepEqual(ct.calls.command.at(-1), { sessionID: "ct-9", name: "push", text: "" })
})

await check("[v2 4] /tests chosen in a question starts by itself", async () => {
  ct.sessions.set("ct-10", { id: "ct-10", title: "Conversation", agent: "build" })
  await ctPrompt("ct-10", "ajoute des tests à InvoiceService")
  await ct.hooks["tool.execute.after"]({ tool: "question", sessionID: "ct-10", status: "completed", result: { output: { answers: [["/tests InvoiceService (recommandé)"]] } } })
  ct.push("session.execution.succeeded", { sessionID: "ct-10" })
  await wait(100)
  assert.deepEqual(ct.calls.command.at(-1), { sessionID: "ct-10", name: "tests", text: "InvoiceService" })
})
await check("[v2 9] /tests takes the folder like /go; « continue » after it stopped resumes it with the pilot", async () => {
  ct.sessions.set("ct-11", { id: "ct-11", title: "Tests", agent: "pilot" })
  const event = await ctPrompt("ct-11", "[[command tests InvoiceService]]\nWrite the missing unit tests of the code the request names.")
  assert.match(event.metadata.displayText, /^\/tests InvoiceService — my-api · /)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).command, "tests")
  ct.push("session.execution.started", { sessionID: "ct-11" })
  ct.push("session.execution.succeeded", { sessionID: "ct-11" })
  await wait(150)
  ct.sessions.set("ct-12", { id: "ct-12", title: "⛔ /tests InvoiceService", agent: "build" })
  const again = await ctPrompt("ct-12", "continue")
  assert.equal(ct.calls.switch.at(-1).sessionID, "ct-12")
  assert.match(again.prompt.text, /^The run of \/tests InvoiceService stopped before its end/, JSON.stringify(again.prompt.text).slice(0, 300))
  assert.match(again.prompt.text, /there is no ticket sheet/)
  ct.push("session.execution.succeeded", { sessionID: "ct-12" })
  await wait(150)
})

// ---------- 4, 9, 10 and 19. the « Suite » question that ends a run ----------
const suiteQuestion = (sessionID, labels, header = "Suite") => ct.hooks["tool.execute.before"]({ tool: "question", sessionID, agent: "pilot", messageID: "m", id: "q-" + sessionID,
  input: { questions: [{ header, question: "Et maintenant ?", options: labels.map((label) => ({ label, description: "…" })) }] } })
const suiteAnswer = (sessionID, labels) => ct.hooks["tool.execute.after"]({ tool: "question", sessionID, status: "completed", result: { output: { answers: [labels] } } })
await check("[v2 4] the « Suite » question of a run: the folder is free while it waits; « Rien pour l'instant »: the outcome of its final answer, no resume", async () => {
  const logged = pluginLog().length
  ct.sessions.set("ct-20", { id: "ct-20", title: "/tests InvoiceService", agent: "pilot" })
  await ctPrompt("ct-20", "[[command tests InvoiceService]]\nWrite the missing unit tests of the code the request names.")
  ct.push("session.execution.started", { sessionID: "ct-20" })
  ct.push("session.step.started", { sessionID: "ct-20", assistantMessageID: "s1" })
  ct.push("session.text.ended", { sessionID: "ct-20", assistantMessageID: "s1", ordinal: 0, text: "**/tests** — test/vat\n✅ Tests ajoutés et prouvés\n| Fichier | Couverture |" })
  // the question in the next request of the model, without text
  ct.push("session.step.started", { sessionID: "ct-20", assistantMessageID: "s2" })
  await wait(50)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "ct-20")
  await suiteQuestion("ct-20", ["/push (recommandé)", "Rien pour l'instant"])
  assert.ok(!existsSync(lockFile), "the folder is free while the question waits")
  ct.push("form.created", { form: { id: "f20", sessionID: "ct-20", title: "Questions", fields: [] } })
  await wait(1200)
  assert.match(ct.sessions.get("ct-20").title, /^❓ \d+:\d\d réponse attendue — ✅ \/tests InvoiceService$/)
  // another command of the folder runs meanwhile, and its own « Suite » frees the folder too
  ct.sessions.set("ct-21", { id: "ct-21", title: "POC", agent: "pilot" })
  const other = await ctPrompt("ct-21", "[[command push feat: try]]\nCommit and push the work of this folder now.")
  assert.doesNotMatch(other.prompt.text, /refusé/)
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).command, "push")
  ct.push("session.execution.started", { sessionID: "ct-21" })
  ct.push("session.step.started", { sessionID: "ct-21", assistantMessageID: "p1" })
  ct.push("session.text.ended", { sessionID: "ct-21", assistantMessageID: "p1", ordinal: 0, text: "**/push** — feature/try\n🚀 Poussé sur origin/feature/try" })
  await suiteQuestion("ct-21", ["/fix (recommandé)", "Rien pour l'instant"])
  assert.ok(!existsSync(lockFile))
  await suiteAnswer("ct-21", ["Rien pour l'instant"])
  ct.push("session.execution.succeeded", { sessionID: "ct-21" })
  // I answer the first one: « Rien pour l'instant », and the pilot says one line
  ct.push("form.replied", { id: "f20", sessionID: "ct-20", answer: {} })
  await suiteAnswer("ct-20", ["Rien pour l'instant"])
  ct.push("session.step.started", { sessionID: "ct-20", assistantMessageID: "s3" })
  ct.push("session.text.ended", { sessionID: "ct-20", assistantMessageID: "s3", ordinal: 0, text: "D'accord." })
  const commands = ct.calls.command.length
  ct.push("session.execution.succeeded", { sessionID: "ct-20" })
  await wait(200)
  assert.equal(ct.sessions.get("ct-20").title, "✅ /tests InvoiceService")
  assert.equal(ct.calls.command.length, commands)
  const log = pluginLog().slice(logged)
  assert.doesNotMatch(log, /run resumed in/)
  assert.match(log, /the run ended with its « Suite » question: the folder is free \{"command":"\/tests"\}/)
  assert.match(log, /the run ended with its « Suite » question: the folder is free \{"command":"\/push"\}/)
})
await check("[v2 4] the command chosen in the « Suite » question starts, even when the model server fails after my answer", async () => {
  const logged = pluginLog().length
  ct.sessions.set("ct-22", { id: "ct-22", title: "/go ABC-90", agent: "pilot" })
  await ctPrompt("ct-22", goText("ABC-90"))
  ct.push("session.execution.started", { sessionID: "ct-22" })
  ct.push("session.step.started", { sessionID: "ct-22", assistantMessageID: "g1" })
  ct.push("session.text.ended", { sessionID: "ct-22", assistantMessageID: "g1", ordinal: 0, text: "**[ABC-90](x) - Export**\n🚀 MR en Draft : x" })
  await suiteQuestion("ct-22", ["/fix (recommandé)", "Rien pour l'instant"])
  await suiteAnswer("ct-22", ["/fix (recommandé)"])
  ct.push("session.step.started", { sessionID: "ct-22", assistantMessageID: "g2" })
  ct.push("session.execution.failed", { sessionID: "ct-22", error: { type: "provider.transport", message: "502 Bad Gateway" } })
  await wait(200)
  assert.equal(ct.sessions.get("ct-22").title, "✅ /go ABC-90")
  assert.deepEqual(ct.calls.command.at(-1), { sessionID: "ct-22", name: "fix", text: "" })
  assert.doesNotMatch(pluginLog().slice(logged), /run resumed in/)
})
await check("[v2 4] a question of the run before its final answer keeps the folder; after the « Suite », a stop I asked for starts nothing", async () => {
  ct.sessions.set("ct-23", { id: "ct-23", title: "/go ABC-91", agent: "pilot" })
  await ctPrompt("ct-23", goText("ABC-91"))
  ct.push("session.execution.started", { sessionID: "ct-23" })
  ct.push("session.step.started", { sessionID: "ct-23", assistantMessageID: "h1" })
  ct.push("session.text.ended", { sessionID: "ct-23", assistantMessageID: "h1", ordinal: 0, text: "Analyse du ticket, et build + tests de develop en parallèle…" })
  // the blocking questions of the analysis, even with a header « Suite » by chance: the run goes on after them
  await suiteQuestion("ct-23", ["Un Result (recommandé)", "Une exception"], "Ticket ambigu")
  await suiteQuestion("ct-23", ["Oui (recommandé)", "Non"])
  assert.equal(JSON.parse(readFileSync(lockFile, "utf8")).session, "ct-23")
  await suiteAnswer("ct-23", ["Un Result (recommandé)"])
  ct.push("session.step.started", { sessionID: "ct-23", assistantMessageID: "h2" })
  ct.push("session.text.ended", { sessionID: "ct-23", assistantMessageID: "h2", ordinal: 0, text: "**[ABC-91](x) - Export**\n🚀 MR en Draft : x" })
  await suiteQuestion("ct-23", ["/fix (recommandé)", "Rien pour l'instant"])
  assert.ok(!existsSync(lockFile))
  await suiteAnswer("ct-23", ["/fix (recommandé)"])
  const commands = ct.calls.command.length
  ct.push("session.execution.interrupted", { sessionID: "ct-23", reason: "user" })
  await wait(200)
  assert.equal(ct.sessions.get("ct-23").title, "✅ /go ABC-91")
  assert.equal(ct.calls.command.length, commands)
})

await check("[v2 4] /compare ends with its « Suite »: the command chosen starts, there is no folder to free", async () => {
  const logged = pluginLog().length
  ct.sessions.set("ct-24", { id: "ct-24", title: "/compare", agent: "debugger" })
  await ctPrompt("ct-24", "[[command compare /srv/old-api ExportService le séparateur]]\nCompare a feature with a repository where it works.")
  ct.push("session.execution.started", { sessionID: "ct-24" })
  ct.push("session.step.started", { sessionID: "ct-24", assistantMessageID: "k1" })
  ct.push("session.text.ended", { sessionID: "ct-24", assistantMessageID: "k1", ordinal: 0, text: "**Cause** : la culture du serveur.\n**Correctif proposé** (non appliqué) : …" })
  await suiteQuestion("ct-24", ["/go sans ticket : garder le séparateur décimal (recommandé)", "Rien pour l'instant"])
  await suiteAnswer("ct-24", ["/go sans ticket : garder le séparateur décimal (recommandé)"])
  ct.push("session.execution.succeeded", { sessionID: "ct-24" })
  await wait(150)
  assert.deepEqual(ct.calls.command.at(-1), { sessionID: "ct-24", name: "go", text: "sans ticket : garder le séparateur décimal" })
  assert.doesNotMatch(pluginLog().slice(logged), /the folder is free/)
})

await check("[v2 4] /outil setup: its rules to add and its « Suite » in one call; the rules chosen are no command, /push starts", async () => {
  const logged = pluginLog().length
  ct.sessions.set("ct-25", { id: "ct-25", title: "/outil setup", agent: "build" })
  await ctPrompt("ct-25", "[[command outil setup]]\nSkill : pack-setup")
  ct.push("session.execution.started", { sessionID: "ct-25" })
  ct.push("session.step.started", { sessionID: "ct-25", assistantMessageID: "u1" })
  ct.push("session.text.ended", { sessionID: "ct-25", assistantMessageID: "u1", ordinal: 0, text: "| Section | Statut |\n…\n1. Jamais S3 en direct : IStorageService." })
  await ct.hooks["tool.execute.before"]({ tool: "question", sessionID: "ct-25", agent: "build", messageID: "m", id: "q-ct-25",
    input: { questions: [
      { header: "Règles", question: "Quelles règles proposées j'ajoute à AGENTS.md ?", multiple: true,
        options: [{ label: "Règle 1 : jamais S3 en direct", description: "…" }, { label: "Règle 2 : dates en UTC", description: "…" }, { label: "Aucune", description: "…" }] },
      { header: "Suite", question: "Et maintenant ?", options: [{ label: "Rien pour l'instant (recommandé)", description: "…" }, { label: "/push", description: "…" }] },
    ] } })
  await ct.hooks["tool.execute.after"]({ tool: "question", sessionID: "ct-25", status: "completed",
    result: { output: { answers: [["Règle 1 : jamais S3 en direct", "Règle 2 : dates en UTC"], ["/push"]] } } })
  // the rules added in the same turn, after the question
  ct.push("session.step.started", { sessionID: "ct-25", assistantMessageID: "u2" })
  ct.push("session.text.ended", { sessionID: "ct-25", assistantMessageID: "u2", ordinal: 0, text: "Ajouté à AGENTS.md : règles 1, 2\nJe lance /push." })
  ct.push("session.execution.succeeded", { sessionID: "ct-25" })
  await wait(150)
  assert.deepEqual(ct.calls.command.at(-1), { sessionID: "ct-25", name: "push", text: "" })
  assert.doesNotMatch(pluginLog().slice(logged), /the folder is free/)
})

await check("[v2 4] /outil audit: « /go sans ticket : … » chosen in its « Suite » starts /go", async () => {
  ct.sessions.set("ct-26", { id: "ct-26", title: "/outil audit", agent: "build" })
  await ctPrompt("ct-26", "[[command outil audit]]\nSkill : pack-audit")
  ct.push("session.execution.started", { sessionID: "ct-26" })
  ct.push("session.step.started", { sessionID: "ct-26", assistantMessageID: "a1" })
  ct.push("session.text.ended", { sessionID: "ct-26", assistantMessageID: "a1", ordinal: 0, text: "Type de projet : api\n« À faire en premier » : 1. health checks" })
  await suiteQuestion("ct-26", ["/go sans ticket : ajouter les health checks de la base (recommandé)", "/go sans ticket : journaliser les erreurs des jobs", "Rien pour l'instant"])
  await suiteAnswer("ct-26", ["/go sans ticket : ajouter les health checks de la base (recommandé)"])
  ct.push("session.execution.succeeded", { sessionID: "ct-26" })
  await wait(150)
  assert.deepEqual(ct.calls.command.at(-1), { sessionID: "ct-26", name: "go", text: "sans ticket : ajouter les health checks de la base" })
})

// ---------- 23. dotnet run: a project of the repository that the last commit holds ----------
const runRepo = join(home, "repos", "run-api")
mkdirSync(join(runRepo, "src", "Api"), { recursive: true })
mkdirSync(join(runRepo, "tests", "Api.Tests"), { recursive: true })
writeFileSync(join(runRepo, "src", "Api", "Api.csproj"), "<Project Sdk=\"Microsoft.NET.Sdk.Web\" />\n")
writeFileSync(join(runRepo, "tests", "Api.Tests", "Api.Tests.csproj"), "<Project Sdk=\"Microsoft.NET.Sdk\" />\n")
execFileSync("git", ["init", "-q", runRepo])
execFileSync("git", ["-C", runRepo, "add", "-A"])
execFileSync("git", ["-C", runRepo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"])
mkdirSync(join(runRepo, "Probe"), { recursive: true })
writeFileSync(join(runRepo, "Probe", "Probe.csproj"), "<Project Sdk=\"Microsoft.NET.Sdk\" />\n")
writeFileSync(join(runRepo, "Probe.cs"), "System.Console.WriteLine(1);\n")
await check("[23] which project a dotnet run starts", () => {
  assert.deepEqual(dotnetRunTarget("dotnet run --project src/Api", runRepo, runRepo), { project: "src/Api", ok: true })
  assert.deepEqual(dotnetRunTarget("timeout 90 dotnet run --project tests/Api.Tests/Api.Tests.csproj --no-build -- --filter-class *Foo*", runRepo, runRepo), { project: "tests/Api.Tests/Api.Tests.csproj", ok: true })
  assert.deepEqual(dotnetRunTarget("dotnet run", join(runRepo, "src", "Api"), runRepo), { project: ".", ok: true })
  assert.equal(dotnetRunTarget("dotnet build && dotnet test", runRepo, runRepo), "")
  assert.equal(dotnetRunTarget("dotnet run --project Probe", runRepo, runRepo).ok, false)
  assert.equal(dotnetRunTarget("dotnet run Probe.cs", runRepo, runRepo).ok, false)
  assert.equal(dotnetRunTarget("dotnet run", runRepo, runRepo).ok, false)
})
const runGuards = await Guards({ client, directory: runRepo, worktree: runRepo })
runGuards.agent("run-build", "build")
const runTool = async (command, extra = {}) => { const output = { args: { command, ...extra } }; await runGuards.before({ tool: "bash", sessionID: "run-build", agent: "build", callID: "r" }, output); return output.args }
// src/Api is a web project: it serves until it is stopped (24), so the conversation runs it in the background or bounded
await check("[23] build runs a committed project (a web API: in the background)", () => runTool("dotnet run --project src/Api", { background: true }))
await check("[23] build runs a committed project (bounded)", () => runTool("timeout 60 dotnet run --project src/Api"))
await check("[23/24] a committed web API run in the foreground is refused: it never ends", () =>
  assert.rejects(() => runTool("dotnet run --project src/Api"), /dotnet run of a web, worker or Aspire project does not end by itself.*in the background \(background: true\), or bounded: timeout 60/))
await check("[23] build runs the tests of a committed test project", () => runTool("dotnet run --project tests/Api.Tests/Api.Tests.csproj --no-build"))
for (const command of ["dotnet run --project Probe", "dotnet run --project Probe/Probe.csproj", "dotnet run Probe.cs", "cd Probe && dotnet run"]) {
  await check(`[23] refused: ${command}`, () => assert.rejects(() => runTool(command), /dotnet run runs only a project of this repository that the last commit holds/))
}

// ---------- 24. commands that never end by themselves ----------
// An application with an Angular front-end (Karma: ng test watches), a Next.js package (jest runs once) and a web API
const shop = join(home, "repos", "shop")
mkdirSync(join(shop, "ClientApp"), { recursive: true })
mkdirSync(join(shop, "web"), { recursive: true })
mkdirSync(join(shop, "src", "Api"), { recursive: true })
writeFileSync(join(shop, "ClientApp", "package.json"), JSON.stringify({ scripts: { test: "ng test", "test:ci": "ng test --no-watch --browsers=ChromeHeadless", build: "ng build", "build:dev": "ng build --configuration development", start: "ng serve", "generate:api": "openapi-generator-cli generate -i ../api.json -g typescript-angular -o src/app/api" } }))
writeFileSync(join(shop, "web", "package.json"), JSON.stringify({ scripts: { test: "jest", dev: "next dev", build: "next build", storybook: "storybook dev -p 6006" } }))
writeFileSync(join(shop, "src", "Api", "Api.csproj"), "<Project Sdk=\"Microsoft.NET.Sdk.Web\" />\n")
execFileSync("git", ["init", "-q", shop])
execFileSync("git", ["-C", shop, "add", "-A"])
execFileSync("git", ["-C", shop, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"])
const g24 = await Guards({ client, directory: shop, worktree: shop })
session("g24-pilot")
session("g24-build")
for (const name of ["coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"]) {
  session("g24-" + name, { parentID: "g24-pilot" })
  g24.agent("g24-" + name, name)
}
g24.agent("g24-pilot", "pilot")
g24.agent("g24-build", "build")
const run24 = async (who, command, extra = {}) => {
  const output = { args: { command, ...extra } }
  await g24.before({ tool: "bash", sessionID: "g24-" + who, callID: "n" + count }, output)
  return output.args
}
const NEVER = /Refused by the pack: .* does not end by itself \(a server or a watch mode\).*build-test\.sh \[<folder>\]/
for (const who of ["pilot", "coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"]) {
  for (const command of ["cd ClientApp && npm start", "cd ClientApp && npm test", "timeout 60 npm run dev --prefix web", "npx ng serve", "dotnet watch run --project src/Api", "dotnet run --project src/Api"]) {
    await check(`[24] ${who} is refused: ${command}`, () => assert.rejects(() => run24(who, command), (error) => NEVER.test(error.message) && !/in the conversation/.test(error.message)))
  }
}
await check("[24] the background is no way out for an agent of the pack", () => assert.rejects(() => run24("coder", "npm run dev --prefix web", { background: true }), NEVER))
await check("[24] the refusal of npm test names the script that watches", () =>
  assert.rejects(() => run24("coder", "npm test", { workdir: "ClientApp" }), /npm test \(its script "ng test": ng test without --watch=false\)/))
await check("[24] npm keeps for itself the options before --: the refusal says where they go", () =>
  assert.rejects(() => run24("coder", "npm test --watch=false", { workdir: "ClientApp" }), /npm passes to the script only the options after --: npm test -- <option>/))
for (const [command, workdir] of [["npm test -- --watch=false --browsers=ChromeHeadless", "ClientApp"], ["npm run test:ci", "ClientApp"], ["npm run build:dev", "ClientApp"],
  ["npm run generate:api", "ClientApp"], ["npx ng test --watch=false", "ClientApp"], ["npm test", "web"], ["npm test -- src/cart.spec.ts", "web"], ["npm run build", "web"],
  ["npm ci", "ClientApp"], ["dotnet test", ""], ["dotnet build src/Api", ""], [S + "build-test.sh ClientApp", ""]]) {
  await check(`[24] the coder runs: ${command}${workdir ? " (in " + workdir + ")" : ""}`, () => run24("coder", command, workdir ? { workdir } : {}))
}
await check("[24] npm test of a package whose tests run once gets 20 minutes", async () => assert.equal((await run24("coder", "npm test", { workdir: "web" })).timeout, 1200000))
// the free conversation: a server in the background, or bounded by timeout (5 minutes at most)
await check("[24] the conversation is refused a server in the foreground, and told how", () =>
  assert.rejects(() => run24("build", "npm run dev", { workdir: "web" }), /npm run dev does not end by itself.*Here, in the conversation: in the background \(background: true\), or bounded: timeout 60 <the command>/))
await check("[24] the conversation runs a server in the background", () => run24("build", "npm run dev", { workdir: "web", background: true }))
await check("[24] the conversation runs a server bounded by timeout", () => run24("build", "timeout 60 npm run storybook", { workdir: "web" }))
await check("[24] the conversation is refused a bound longer than 5 minutes", () => assert.rejects(() => run24("build", "timeout 10m npm run dev", { workdir: "web" }), NEVER))
await check("[24] the conversation runs a web API in the background", () => run24("build", "dotnet run --project src/Api", { background: true }))
await check("[24] a refusal is written to the log of the plugin, never the scripts of package.json", () => {
  const found = logs.filter((entry) => entry && entry.extra && /never ends/.test(String(entry.extra.reason)))
  assert.ok(found.length > 0, "no log entry")
  assert.ok(found.some((entry) => /npm test \(its script: ng test without --watch=false\)/.test(entry.extra.reason)), "the refusal of npm test")
  assert.ok(!found.some((entry) => /"ng test"|storybook dev -p/.test(JSON.stringify(entry))), "a script in the log")
})

// ---------- 25. a change of the dependencies, an install on the machine ----------
mkdirSync(join(shop, "tools-ui"), { recursive: true })
writeFileSync(join(shop, "tools-ui", "package.json"), JSON.stringify({ scripts: { setup: "npm install && npm run build", build: "tsc -p .", lint: "eslint ." } }))
await check("[25] what changes the dependencies of the repository, or a tool of the machine", () => {
  const d = (command, cwd = shop) => dependencyChange(command, cwd, shop)
  for (const [command, what] of [
    ["npm install", "npm install"], ["npm i", "npm i"], ["npm install lodash", "npm install"], ["npm i -S axios", "npm i"],
    ["npm --prefix ClientApp install", "npm install"], ["npm install --legacy-peer-deps", "npm install"], ["npm update", "npm update"],
    ["npm audit fix --force", "npm audit fix"], ["npm pkg set dependencies.x=1.0.0", "npm pkg set"], ["npm uninstall rxjs", "npm uninstall"],
    ["npm it", "npm it"], ["yarn add dayjs", "yarn add"], ["yarn", "yarn without --frozen-lockfile"],
    ["yarn install", "yarn install without --frozen-lockfile"], ["yarn workspace web add zod", "yarn workspace web add"], ["pnpm add zod", "pnpm add"],
    ["pnpm install", "pnpm install without --frozen-lockfile"], ["pnpm --filter web add zod", "pnpm add"], ["npx --yes npm@11 install", "npm install"],
    ["npm exec --package=npm@11 -- npm install", "npm install"], ["corepack yarn add dayjs", "yarn add"], ["cd ClientApp && npm install", "npm install"],
    ["sh -c \"cd ClientApp && npm i\"", "npm i"], ["CI=true npm install", "npm install"], ["timeout 300 npm install", "npm install"],
    ["npm ci || npm install", "npm install"], ["dotnet add src/Api/Api.csproj package Polly --version 8.5.0", "dotnet add package"],
    ["dotnet add package Polly", "dotnet add package"], ["dotnet package add Polly --project src/Api/Api.csproj", "dotnet package add"],
    ["dotnet remove src/Api/Api.csproj package Newtonsoft.Json", "dotnet remove package"], ["dotnet tool install dotnet-ef", "dotnet tool install"],
  ]) assert.equal(d(command).what, what, command)
  assert.deepEqual(d("npm run setup", join(shop, "tools-ui")), { what: "npm run setup (its script runs npm install)", log: "npm run setup (its script: npm install)", machine: false })
  for (const command of ["npm i -g npm@11", "npm install --global @angular/cli", "yarn global add serve", "pnpm add -g pnpm", "brew install --cask chromium",
    "sudo apt-get install -y chromium", "pip install requests", "corepack enable", "nvm install 22", "dotnet tool install -g dotnet-ef"]) {
    assert.equal(d(command).machine, true, command)
  }
  for (const command of ["npm ci", "npm ci --prefix ClientApp", "yarn install --frozen-lockfile", "yarn install --immutable", "pnpm install --frozen-lockfile",
    "pnpm i --frozen-lockfile", "npm test", "npm run build", "npm ls", "npm outdated", "npm --version", "yarn --version", "yarn test", "pnpm test",
    "dotnet restore", "dotnet tool restore", "dotnet package list --vulnerable", "dotnet list package", "dotnet reference add src/Domain/Domain.csproj --project src/Api/Api.csproj",
    "git commit -m \"npm install lodash\"", "grep -rn \"npm install\" docs", "echo npm install", "dotnet build", "brew list", "pip list"]) {
    assert.equal(d(command), "", command)
  }
  assert.equal(d("npm run lint", join(shop, "tools-ui")), "")
})
const DEPS = /Refused by the pack: .* changes the dependencies of the repository .*« BLOQUÉ » with what is needed.*build-test\.sh \[<folder>\] when they are missing \(npm ci, dotnet restore\)\. Never try another form/
const MACHINE = /Refused by the pack: .* installs or changes a tool of this machine: an agent never does.*ENVIRONMENT PROBLEM: tell the user in one line and stop/
for (const who of ["pilot", "coder", "test-guardian", "analyst", "checker", "debugger", "doc-writer"]) {
  await check(`[25] ${who} is refused npm install, and told what to do`, () => assert.rejects(() => run24(who, "npm install", { workdir: "ClientApp" }), DEPS))
}
await check("[25] the coder is refused a package added through npx npm@11", () => assert.rejects(() => run24("coder", "npx --yes npm@11 install"), DEPS))
await check("[25] the coder is refused dotnet package add (.NET 10)", () => assert.rejects(() => run24("coder", "dotnet package add Polly --project src/Api/Api.csproj"), DEPS))
await check("[25] the coder is refused a tool of the machine", () => assert.rejects(() => run24("coder", "brew install --cask chromium"), MACHINE))
await check("[25] a script of package.json that installs is refused, by its name", () =>
  assert.rejects(() => run24("coder", "npm run setup", { workdir: "tools-ui" }), /npm run setup \(its script runs npm install\) changes the dependencies/))
for (const command of ["npm ci", "npm ci --prefix ClientApp", "yarn install --frozen-lockfile", "dotnet restore", "dotnet reference add src/Domain/Domain.csproj --project src/Api/Api.csproj"]) {
  await check(`[25] the coder runs: ${command}`, () => run24("coder", command))
}
await check("[25] the free conversation is mine: npm install lodash passes the plugin", () => run24("build", "npm install lodash", { workdir: "web" }))
await check("[25] a refusal is written to the log of the plugin, never the scripts of package.json", () => {
  const found = logs.filter((entry) => entry && entry.extra && /a change of the dependencies|an install on the machine/.test(String(entry.extra.reason)))
  assert.ok(found.some((entry) => /npm run setup \(its script: npm install\)/.test(entry.extra.reason)), "the refusal of npm run setup")
  assert.ok(found.some((entry) => /an install on the machine: brew install/.test(entry.extra.reason)), "the refusal of brew install")
  assert.ok(!found.some((entry) => /npm install && npm run build|tsc -p/.test(JSON.stringify(entry))), "a script in the log")
})

// ---------- 26. scheduled commands ----------
await check("[26] the schedules of /outil planifier, as schedule.sh writes them", () => {
  const text = "# Planifications\n\n- #1 08:45 lun,mar,mer,jeu,ven /daily — /home/dev/repos/api (ajoutée le 2026-10-24)\n" +
    "- #2 22:00 lun,ven /tests env recette — /home/dev/repos/api (ajoutée le 2026-10-24)\n- #3 07:00 lun /outil audit tests — /home/dev/repos/x y (ajoutée le 2026-10-24)\nnot a line\n"
  const entries = scheduleEntries(text)
  assert.equal(entries.length, 3)
  assert.deepEqual({ ...entries[0], days: [...entries[0].days] }, { id: "1", hour: 8, minute: 45, days: [1, 2, 3, 4, 5], command: "daily", args: "", directory: "/home/dev/repos/api" })
  assert.equal(entries[1].args, "env recette")
  assert.equal(entries[2].directory, "/home/dev/repos/x y")
  // Monday 26 October 2026 at 08:45 (local time), then the Sunday before
  assert.deepEqual(dueSchedules(text, new Date(2026, 9, 26, 8, 45, 10)).map((e) => e.id), ["1"])
  assert.deepEqual(dueSchedules(text, new Date(2026, 9, 25, 8, 45, 10)).map((e) => e.id), [])
  assert.deepEqual(dueSchedules(text, new Date(2026, 9, 26, 8, 46, 0)).map((e) => e.id), [])
})
await check("[26] only what writes nothing starts without the developer, even a line written by hand", () => {
  const ok = (command) => scheduleAllowed(scheduleEntries("- #1 08:00 lun " + command + " — /r (ajoutée le 2026-10-24)")[0])
  for (const command of ["/daily", "/outil audit", "/outil licences branche", "/tests env recette"]) assert.equal(ok(command), true, command)
  for (const command of ["/go ABC-1", "/push", "/fix", "/sync", "/fortify", "/outil setup", "/outil abandon", "/tests api", "/tests InvoiceService",
    "/tests env", "/tests env recette --ecriture", "/tests env recette écriture", "/tests env recette --allow-writes",
    // the wizards of /tests env ask questions and write AGENTS.md: never without the developer
    "/tests env config", "/tests env config recette", "/tests env configurer recette", "/tests env setup", "/tests env Réglages recette"]) assert.equal(ok(command), false, command)
})
await check("[26] a schedule due now starts once, in a new session of its repository, whatever the number of instances", async () => {
  let now = new Date()
  if (now.getSeconds() >= 56) {
    await wait(4500)
    now = new Date()
  }
  const day = ["dim", "lun", "mar", "mer", "jeu", "ven", "sam"][now.getDay()]
  const at = String(now.getHours()).padStart(2, "0") + ":" + String(now.getMinutes()).padStart(2, "0")
  const file = join(home, "schedules-test.md")
  writeFileSync(file, "- #1 " + at + " " + day + " /daily — " + repo + " (ajoutée le 2026-10-24)\n" +
    "- #2 " + at + " " + day + " /go ABC-1 — " + repo + " (ajoutée le 2026-10-24)\n" +
    "- #3 " + at + " " + day + " /outil audit — " + join(home, "nowhere") + " (ajoutée le 2026-10-24)\n")
  const options = { tickMs: 25, mcpWaitMs: 600, resumeFailureMs: [600000], resumeUnfinishedMs: 600000, schedulesFile: file, scheduleMs: 40 }
  const first = fakeV2(repo, { options })
  const stopFirst = await v2Plugin.setup(first.ctx)
  const second = fakeV2(repo, { options })
  const stopSecond = await v2Plugin.setup(second.ctx)
  await wait(500)
  if (typeof stopFirst === "function") stopFirst()
  if (typeof stopSecond === "function") stopSecond()
  const created = [...first.calls.create, ...second.calls.create]
  const commands = [...first.calls.command, ...second.calls.command]
  assert.deepEqual(created, [{ location: { directory: repo } }])
  assert.deepEqual(commands, [{ sessionID: "created-1", name: "daily", text: "" }])
  assert.match(pluginLog(), /scheduled command started .*"command":"\/daily"/)
  assert.match(pluginLog(), /scheduled command refused: it may write .*"command":"\/go ABC-1"/)
  assert.match(pluginLog(), /scheduled command not started: its folder is missing .*"command":"\/outil audit"/)
})

// ---------- 29. where the time of a run goes: a simulated /go, on a clock of the test ----------
{
  const tmRepo = join(home, "repos", "timing-api")
  mkdirSync(tmRepo, { recursive: true })
  execFileSync("git", ["init", "-q", tmRepo])
  let clock = 1_800_000_000_000
  const base = clock
  const tm = fakeV2(tmRepo, { options: { tickMs: 25, mcpWaitMs: 600, resumeFailureMs: [600000], resumeUnfinishedMs: 600000, now: () => clock } })
  await v2Plugin.setup(tm.ctx)
  // an event at <seconds> after the start of the run, handled before the clock moves on
  const at = async (seconds, type, data) => {
    clock = base + Math.round(seconds * 1000)
    tm.push(type, data)
    await wait(8)
  }
  const P = "tm-1"
  const C = "tm-1-coder"
  tm.sessions.set(P, { id: P, title: "x", agent: "pilot" })
  await tm.hooks["session.prompt"]({ sessionID: P, messageID: "m", prompt: { text: "[[command go ABC-50 avec un Result]]\nTake the ticket from its analysis to its Draft merge request, in this single run." }, delivery: "steer" })
  await at(0, "session.execution.started", { sessionID: P })
  // the pilot: 2 s before its first token, it thinks, writes, then calls the coder
  await at(0, "session.step.started", { sessionID: P, assistantMessageID: "p1", agent: "pilot", started: base })
  await at(2, "session.reasoning.started", { sessionID: P, assistantMessageID: "p1" })
  await at(2, "session.reasoning.delta", { sessionID: P, assistantMessageID: "p1", ordinal: 0, delta: "r".repeat(400) })
  await at(12, "session.text.delta", { sessionID: P, assistantMessageID: "p1", ordinal: 0, delta: "Étape 1/2…" })
  await at(13, "session.tool.input.started", { sessionID: P, assistantMessageID: "p1", id: "c1", name: "subagent" })
  await at(14, "session.tool.called", { sessionID: P, assistantMessageID: "p1", id: "c1", input: { agent: "coder", description: "Étape 1/2", prompt: "x" }, executed: true })
  await at(14, "session.tool.progress", { sessionID: P, assistantMessageID: "p1", id: "c1", metadata: { sessionID: C, status: "running" } })
  await at(15, "session.step.streamed", { sessionID: P, assistantMessageID: "p1" })
  // the coder: 4 s before its first token, a build of 60 s, then an answer a gateway held back 58 s and gave at once
  await at(16, "session.step.started", { sessionID: C, assistantMessageID: "c1", agent: "coder", started: base + 16000 })
  await at(20, "session.reasoning.delta", { sessionID: C, assistantMessageID: "c1", ordinal: 0, delta: "r".repeat(800) })
  await at(30, "session.text.delta", { sessionID: C, assistantMessageID: "c1", ordinal: 0, delta: "Je lance le build." })
  await at(31, "session.tool.input.started", { sessionID: C, assistantMessageID: "c1", id: "k1", name: "shell" })
  await at(32, "session.tool.called", { sessionID: C, assistantMessageID: "c1", id: "k1", input: { command: "sh ~/.config/opencode/scripts/build-test.sh src/A.sln --filter X" }, executed: true })
  await at(32, "session.step.streamed", { sessionID: C, assistantMessageID: "c1" })
  await at(92, "session.tool.success", { sessionID: C, assistantMessageID: "c1", id: "k1", content: [{ type: "text", text: "BUILD: OK" }], executed: true })
  await at(92, "session.step.ended", { sessionID: C, assistantMessageID: "c1", finish: "tool-calls", tokens: { input: 5000, output: 300, reasoning: 1500, cache: { read: 15000, write: 0 } } })
  await at(92, "session.step.started", { sessionID: C, assistantMessageID: "c2", agent: "coder", started: base + 92000 })
  await at(150, "session.text.delta", { sessionID: C, assistantMessageID: "c2", ordinal: 0, delta: "x".repeat(1500) })
  await at(150.3, "session.text.delta", { sessionID: C, assistantMessageID: "c2", ordinal: 0, delta: "RÉSULTAT : OK" })
  await at(150.6, "session.step.streamed", { sessionID: C, assistantMessageID: "c2" })
  await at(150.6, "session.step.ended", { sessionID: C, assistantMessageID: "c2", finish: "stop", tokens: { input: 1000, output: 400, reasoning: 0, cache: { read: 21000, write: 0 } } })
  await at(152, "session.tool.success", { sessionID: P, assistantMessageID: "p1", id: "c1", content: [{ type: "text", text: "RÉSULTAT : OK" }], metadata: { sessionID: C }, executed: true })
  await at(152, "session.step.ended", { sessionID: P, assistantMessageID: "p1", finish: "tool-calls", tokens: { input: 2000, output: 100, reasoning: 400, cache: { read: 30000, write: 0 } } })
  // a 504 of the gateway: a retry 10 s later, then the final answer
  await at(152, "session.retry.scheduled", { sessionID: P, assistantMessageID: "p2", attempt: 2, at: base + 162000, error: { type: "provider.internal", message: "Gateway Time-out" } })
  await at(162, "session.step.started", { sessionID: P, assistantMessageID: "p2", agent: "pilot", started: base + 162000 })
  await at(165, "session.text.delta", { sessionID: P, assistantMessageID: "p2", ordinal: 0, delta: "🚀 MR en Draft" })
  await at(165, "session.text.ended", { sessionID: P, assistantMessageID: "p2", ordinal: 0, text: "**ABC-50**\n🚀 MR en Draft : https://gitlab/x/-/merge_requests/50" })
  await at(166, "session.step.streamed", { sessionID: P, assistantMessageID: "p2" })
  await at(166, "session.step.ended", { sessionID: P, assistantMessageID: "p2", finish: "stop", tokens: { input: 500, output: 50, reasoning: 0, cache: { read: 33000, write: 0 } } })
  await at(166, "session.execution.succeeded", { sessionID: P })
  await wait(150)
  const runsFile = join(home, ".local", "share", "opencode", "log", "openrd-pack-runs.tsv")
  const line = readFileSync(runsFile, "utf8").trim().split("\n").filter((l) => l.includes("\tkey=ABC-50\t")).pop() || ""
  const field = (name) => (new RegExp("\\t" + name + "=([^\\t]*)").exec(line) || [])[1]
  await check("[v2 29] one line per run, its command, its key and its outcome", () => {
    assert.match(line, /^\d{4}-\d\d-\d\dT[\d:.]+Z\trun\t/)
    assert.equal(field("command"), "go")
    assert.equal(field("key"), "ABC-50")
    assert.equal(field("outcome"), "✅")
    assert.equal(field("total"), "166")
  })
  await check("[v2 29] the path of the run: the model of the pilot, its subagents, its tools", () => {
    // the pilot: 15 s to its first answer, 4 s to its last one; the coder kept it 137 s
    assert.equal(field("top_model"), "19")
    assert.equal(field("top_subagents"), "137")
    assert.equal(field("top_tools"), "0")
    assert.equal(field("questions"), "0")
  })
  await check("[v2 29] the model in all: requests, wait before the first token, thinking, writing", () => {
    assert.equal(field("steps"), "4")
    assert.equal(field("wait"), "67")
    // the answer the gateway held back 58 s is not a time to the first token: the pilot 2 s and 3 s, the coder 4 s
    assert.equal(field("ttft_avg"), "3")
    assert.equal(field("ttft_cold"), "3")
    assert.equal(field("cold_n"), "2")
    assert.equal(field("ttft_warm"), "3")
    assert.equal(field("warm_n"), "1")
    assert.equal(field("ttft_max"), "4")
    assert.equal(field("think"), "20")
    assert.equal(field("write"), "7")
  })
  await check("[v2 29] the retries, the answers a gateway held back, the silences", () => {
    assert.equal(field("retries"), "1")
    assert.equal(field("retry_wait"), "10")
    assert.equal(field("buffered"), "1")
    assert.equal(field("stall_max"), "10")
    assert.equal(field("stalls"), "0")
  })
  await check("[v2 29] the subagents by agent, the tools by script, the longest call", () => {
    assert.equal(field("agents"), "coder:1:138")
    assert.equal(field("tools"), "build-test.sh:1:60")
    assert.equal(field("tool_max"), "build-test.sh:60")
  })
  await check("[v2 29] the tokens the server counted, and the characters streamed", () => {
    assert.equal(field("tokens_in"), String(5000 + 15000 + 1000 + 21000 + 2000 + 30000 + 500 + 33000))
    assert.equal(field("tokens_cached"), String(15000 + 21000 + 30000 + 33000))
    assert.equal(field("tokens_out"), String(300 + 400 + 100 + 50))
    assert.equal(field("tokens_reasoning"), String(1500 + 400))
  })
  await check("[v2 29] never a prompt, a command or a directive in the line", () => {
    assert.ok(!line.includes("avec un Result") && !line.includes("--filter") && !line.includes("Étape") && !line.includes("src/A.sln"), line)
  })
}

// ---------- every command the pack prescribes passes the guards of the plugin, for the agent that runs it ----------
// (tools/permission-corpus.mjs, the cases noted "prescribed by the pack": the permission rules check them too)
const { cases: corpus } = await import(join(pack, "tools", "permission-corpus.mjs"))
const prescribed = corpus.filter((c) => c.note === "prescribed by the pack" && typeof c.cmd === "string" && !/\bdotnet run\b/.test(c.cmd))
for (const agent of [...new Set(prescribed.map((c) => c.agent))]) {
  await check(`[prescribed] every command prescribed to ${agent} passes the guards`, async () => {
    guards.agent("presc-" + agent, agent)
    const refused = []
    for (const c of prescribed.filter((x) => x.agent === agent)) {
      try {
        await guards.before({ tool: "bash", sessionID: "presc-" + agent, agent, callID: "p" }, { args: { command: c.cmd } })
      } catch (error) {
        refused.push(c.cmd + " -> " + String(error && error.message).slice(0, 120))
      }
    }
    assert.deepEqual(refused, [])
  })
}

console.log(`\n${count - failures}/${count} plugin checks as expected`)
process.exit(failures ? 1 : 0)
