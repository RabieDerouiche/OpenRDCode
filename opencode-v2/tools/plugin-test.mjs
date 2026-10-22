// Tests of the guards of the pack plugin (plugins/openrd-pack.js, the 1.19 guards behind the OpenCode v2 adapter): the repository jail (7), the refusals of
// environment dumps and recursive rm, the long timeouts (8), one /go or /fix at a time (9) and the outcome in the
// session title (10). The plugin runs against a fake OpenCode client, in a fake home folder.
// Usage, from v2/: node tools/plugin-test.mjs
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const pack = resolve(process.argv[2] || ".")
const home = mkdtempSync(join(tmpdir(), "plugin-test-"))
process.env.HOME = home
process.env.XDG_DATA_HOME = join(home, ".local", "share")
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
const { CompactCommands, default: v2Plugin } = await import(join(stub, "openrd-pack.js"))

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
const hooks = await CompactCommands({ client, directory: repo, worktree: repo })

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
  await hooks["chat.params"]({ sessionID, agent: name }, {})
}
async function tool(sessionID, name, args) {
  const output = { args: { ...args } }
  await hooks["tool.execute.before"]({ tool: name, sessionID, callID: "c" + count }, output)
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
await hooks["command.execute.before"]({ command: "compare", sessionID: "debugger-1", arguments: other + " ExportService le titre" }, { parts: [] })
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
await hooks["command.execute.before"]({ command: "go", sessionID: "pilot-2", arguments: "ABC-12 comme dans ~/repos/old-api (ExportService)" }, { parts: [] })
await check("[coder of /go] read in the named folder", () => allowed("coder-2", "read", { filePath: join(other, "src", "x.cs") }))
await check("[analyst of /go] shell in the named folder", () => allowed("analyst-2", "bash", { command: "git -C ~/repos/old-api log -3" }))
await check("[coder of /go] shell in the named folder", () => refused("coder-2", "bash", { command: "ls ~/repos/old-api" }))
await check("[pilot of /go] glob of the named folder", () => allowed("pilot-2", "glob", { pattern: "*", path: other }))
await hooks.event({ event: { type: "session.idle", properties: { sessionID: "pilot-2" } } })
// in a message I type (top-level session only)
await check("[build] before naming", () => refused("build-1", "bash", { command: "ls ~/repos/old-api" }))
await hooks["chat.message"]({ sessionID: "build-1", agent: "build" }, { message: {}, parts: [{ type: "text", text: "Regarde l'implémentation dans ~/repos/old-api, merci." }] })
await check("[build] after naming", () => allowed("build-1", "bash", { command: "ls ~/repos/old-api" }))
await hooks["chat.message"]({ sessionID: "coder-1", agent: "coder" }, { message: {}, parts: [{ type: "text", text: "Read " + home + " now" }] })
await check("[coder] a subagent prompt names nothing", () => refused("coder-1", "bash", { command: "ls " + home }))
await hooks["chat.message"]({ sessionID: "pilot-1", agent: "pilot" }, { message: {}, parts: [{ type: "text", synthetic: true, text: "Repository root: " + home }] })
await check("[pilot] the expanded text of a command names nothing", () => refused("pilot-1", "bash", { command: "ls " + home }))

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
await check("build-test.sh gets 20 min", async () => assert.equal(await timeout(S + "build-test.sh"), 1200000))
await check("dotnet test gets 20 min", async () => assert.equal(await timeout("dotnet test --no-build 2>&1 | tail -80"), 1200000))
await check("npm test gets 20 min", async () => assert.equal(await timeout("npm test -- src/app/foo.spec.ts"), 1200000))
await check("ship.sh gets 5 min", async () => assert.equal(await tool("pilot-1", "bash", { command: S + "ship.sh --no-push \"feat: x (ABC-1)\"" }).then((a) => a.timeout), 300000))
await check("git status keeps the default", async () => assert.equal(await timeout("git status"), undefined))
await check("a longer timeout is kept", async () => assert.equal(await timeout(S + "build-test.sh", 3600000), 3600000))

// ---------- 9. one /go or /fix at a time ----------
session("go-a")
session("go-b")
const run = (command, sessionID) => hooks["command.execute.before"]({ command, sessionID, arguments: "ABC-1" }, { parts: [{ type: "text", text: "x" }] })
await check("first /go starts", () => run("go", "go-a"))
const refusedRun = async (command) => {
  const parts = [{ type: "text", text: "Workflow state: [[run workflow-state.sh --fetch-all --sheet]]" }]
  await hooks["command.execute.before"]({ command, sessionID: "go-b", arguments: "ABC-9" }, { parts })
  return parts
}
await check("second /go: replaced by its refusal", async () => {
  const parts = await refusedRun("go")
  assert.equal(parts[0].text, "/go ABC-9")
  assert.match(parts[1].text, /⛔ \/go refusé : \/go tourne déjà/)
  assert.ok(parts[1].synthetic)
  assert.ok(!parts.some((p) => /\[\[run/.test(p.text)))
})
await check("no tool runs in the refused turn", () => refused("go-b", "bash", { command: "git status" }, /was refused/))
await check("/fix refused too", async () => assert.match((await refusedRun("fix"))[1].text, /⛔ \/fix refusé/))
await hooks.event({ event: { type: "session.idle", properties: { sessionID: "go-b" } } })
await check("tools again after the refused turn", () => allowed("go-b", "bash", { command: "git status" }))
await check("/daily is not a pilot run", () => run("daily", "go-b"))
await check("the same session may start again", () => run("go", "go-a"))

// ---------- 10. outcome in the title ----------
const idle = async (sessionID, type = "session.idle") => {
  await hooks.event({ event: { type, properties: { sessionID } } })
  await new Promise((r) => setTimeout(r, 50))
}
const answer = (sessionID, text, error) => messages.set(sessionID, [{ info: { role: "assistant", time: { created: 2 }, ...(error ? { error } : {}) }, parts: [{ type: "text", text }] }])
answer("go-a", "**[ABC-1](x) - Export**\n🚀 MR en Draft : https://gitlab/x/-/merge_requests/42")
await idle("go-a")
await check("delivered: ✅", () => assert.equal(sessions.get("go-a").title, "✅ Session go-a"))
await check("after the end, another session may run /go", () => run("go", "go-b"))
answer("go-b", "⛔ Arrêt à l'étape 3 : le build échoue après deux essais.")
await idle("go-b")
await check("stopped: ⛔", () => assert.equal(sessions.get("go-b").title, "⛔ Session go-b"))
await check("next /go keeps one mark", () => run("go", "go-b"))
answer("go-b", "**[ABC-1](x)** ✅ Déjà livré (MR !42) : /fix pour la CI ou la review")
await idle("go-b")
await check("already delivered: ✅ replaces ⛔", () => assert.equal(sessions.get("go-b").title, "✅ Session go-b"))
answer("go-b", "**[ABC-1](x)**\n⛔ Arrêt à l'étape 3 : build en échec.\n| # | Étape | ✅ |\n| 1 | a | ✅ |")
await run("go", "go-b")
await idle("go-b")
await check("a stop after a table of done steps: ⛔", () => assert.equal(sessions.get("go-b").title, "⛔ Session go-b"))
session("go-c")
await run("fix", "go-c")
await idle("go-c", "session.error")
await check("error: ⛔", () => assert.equal(sessions.get("go-c").title, "⛔ Session go-c"))
session("chat-1")
answer("chat-1", "🚀 voilà")
await idle("chat-1")
await check("a conversation is never marked", () => assert.equal(sessions.get("chat-1").title, "Session chat-1"))

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
const hooksWt = await CompactCommands({ client, directory: workspace, worktree: workspace })
const sheetOut = join(mainRepo, ".git", "opencode-tickets", "ABC-9.md")
for (const [id, name] of [["wt-analyst", "analyst"], ["wt-coder", "coder"], ["wt-checker", "checker"], ["wt-pilot", "pilot"]]) {
  session(id)
  await hooksWt["chat.params"]({ sessionID: id, agent: name }, {})
}
const toolWt = async (sessionID, name, args) => {
  const output = { args: { ...args } }
  await hooksWt["tool.execute.before"]({ tool: name, sessionID, callID: "w" + count }, output)
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

// ---------- 12. the folder of the worktree in the session titles and on the command line ----------
const updated = async (h, info) => {
  await h.event({ event: { type: "session.updated", properties: { info } } })
  await new Promise((r) => setTimeout(r, 30))
}
for (const [id, title, extra] of [["wt-t1", "Export PDF des factures"], ["wt-t2", "New session - 2026-10-21T10:00:00.000Z"],
  ["wt-t3", "✅ Export PDF"], ["wt-t4", "⏳ 0:05 réflexion 1,2k tokens — Export"], ["wt-t5", "Revue", { parentID: "wt-t1" }],
  ["wt-t6", "[brave-fox] Déjà marqué"], ["main-t1", "Export PDF"]]) {
  session(id, { title, ...(extra || {}) })
  await updated(id.startsWith("main") ? hooks : hooksWt, sessions.get(id))
}
await check("[worktree title] a generated title gets the folder", () => assert.equal(sessions.get("wt-t1").title, "[brave-fox] Export PDF des factures"))
await check("[worktree title] a default title is left for OpenCode", () => assert.equal(sessions.get("wt-t2").title, "New session - 2026-10-21T10:00:00.000Z"))
await check("[worktree title] after the outcome mark", () => assert.equal(sessions.get("wt-t3").title, "✅ [brave-fox] Export PDF"))
await check("[worktree title] a progress title is left as it is", () => assert.match(sessions.get("wt-t4").title, /^⏳ 0:05/))
await check("[worktree title] never a subagent's session", () => assert.equal(sessions.get("wt-t5").title, "Revue"))
await check("[worktree title] once only", () => assert.equal(sessions.get("wt-t6").title, "[brave-fox] Déjà marqué"))
await check("[worktree title] never in the main checkout", () => assert.equal(sessions.get("main-t1").title, "Export PDF"))
await check("[worktree] the command line names the worktree folder", async () => {
  session("wt-cmd")
  const output = { parts: [{ type: "text", text: "Fais le point." }] }
  await hooksWt["command.execute.before"]({ command: "daily", sessionID: "wt-cmd", arguments: "" }, output)
  assert.ok(output.parts.some((p) => /main-api · worktree brave-fox · branche opencode\/brave-fox/.test(p.text)), JSON.stringify(output.parts).slice(0, 300))
})

// ---------- 5. what a subagent waits for, in the title of its parent ----------
session("go-p")
session("chk-1", { parentID: "go-p" })
const emit = (type, properties) => hooks.event({ event: { type, properties } })
const tick = () => new Promise((r) => setTimeout(r, 5600))
const task = (status) => ({ part: { id: "t1", sessionID: "go-p", type: "tool", tool: "task",
  state: { status, title: "Auto-review", input: { description: "Auto-review" }, metadata: { sessionId: "chk-1" } } } })
await emit("session.status", { sessionID: "go-p", status: { type: "busy" } })
await emit("message.part.updated", task("running"))
await emit("session.status", { sessionID: "chk-1", status: { type: "busy" } })
await emit("session.status", { sessionID: "chk-1", status: { type: "retry", attempt: 3, message: "Gateway Time-out" } })
await tick()
await check("a retry of the subagent shows in the parent title", () =>
  assert.match(sessions.get("go-p").title, /^⏳ \d+:\d\d outil · Auto-review · nouvel essai 3 \(serveur du modèle\) — Session go-p$/))
await emit("permission.asked", { sessionID: "chk-1", id: "per1", permission: "external_directory" })
await tick()
await check("an approval the subagent waits for shows in the parent title", () =>
  assert.match(sessions.get("go-p").title, /^❓ \d+:\d\d Auto-review · autorisation attendue — Session go-p$/))
await emit("permission.replied", { sessionID: "chk-1", requestID: "per1", reply: "once" })
await emit("message.part.updated", task("completed"))
await emit("session.idle", { sessionID: "chk-1" })
await check("the subagent title is never touched", () => assert.equal(sessions.get("chk-1").title, "Session chk-1"))
await emit("session.idle", { sessionID: "go-p" })
await new Promise((r) => setTimeout(r, 200))
await check("the parent gets its title back", () => assert.equal(sessions.get("go-p").title, "Session go-p"))

// ---------- OpenCode v2 adapter ----------
const v2hooks = {}
const on = (domain) => ({ hook: async (name, fn) => { v2hooks[domain + "." + name] = fn } })
writeFileSync(join(home, ".config", "opencode", "scripts", "hello.sh"), 'echo "hello from $(basename "$PWD")"\n')
await v2Plugin.setup({ location: { directory: repo }, tool: on("tool"), shell: on("shell"), session: on("session") })
const v2call = async (tool, input, agent = "coder") => {
  const event = { tool, sessionID: "v2-s", agent, messageID: "m", id: "c" + count, input }
  await v2hooks["tool.execute.before"](event)
  return event.input
}
await check("[v2] the setup registers its three hooks", () => assert.deepEqual(Object.keys(v2hooks).sort(), ["session.prompt", "shell.create.before", "tool.execute.before"]))
await check("[v2] a shell command outside the repository is refused", () => assert.rejects(() => v2call("shell", { command: "cat ~/.zshenv" }), /outside the repository/))
await check("[v2] an environment dump is refused", () => assert.rejects(() => v2call("shell", { command: "export -p" }), /prints the environment/))
await check("[v2] a read outside the repository is refused (path)", () => assert.rejects(() => v2call("read", { path: join(home, ".zshenv") }), /outside the repository/))
await check("[v2] a build gets 20 minutes and a tool path is rewritten", async () => {
  const input = await v2call("shell", { command: "~/.bin/dotnet build -nologo" })
  assert.equal(input.command, "dotnet build -nologo")
  assert.equal(input.timeout, 1200000)
})
await check("[v2] moving a session or creating a worktree is refused", () => assert.rejects(() => v2call("session_move", { directory: "/tmp" }), /for the developer/))
await check("[v2] the commands of the agents get a stable environment", async () => {
  const invocation = { command: "git fetch", env: {} }
  await v2hooks["shell.create.before"](invocation)
  assert.equal(invocation.env.GIT_TERMINAL_PROMPT, "0")
})
await check("[v2] the commands of the agents never get the server password", async () => {
  const invocation = { command: "git status", env: { PATH: "/usr/bin", OPENCODE_SERVER_PASSWORD: "pw", OPENCODE_PASSWORD: "pw" } }
  await v2hooks["shell.create.before"](invocation)
  assert.equal(invocation.env.OPENCODE_SERVER_PASSWORD, undefined)
  assert.equal(invocation.env.OPENCODE_PASSWORD, undefined)
  assert.equal(invocation.env.PATH, "/usr/bin")
})
await check("[v2] the commands of the agents get the developer's folders back, not the XDG ones of ~/oc2", async () => {
  const env = { XDG_DATA_HOME: join(home, "oc2", "data"), XDG_CACHE_HOME: join(home, "oc2", "cache"), XDG_STATE_HOME: join(home, "oc2", "state"),
    XDG_CONFIG_HOME: "/etc/xdg-of-the-developer", OPENCODE_CONFIG_DIR: join(home, "oc2", "config", "opencode") }
  const invocation = { command: "git fetch", env }
  await v2hooks["shell.create.before"](invocation)
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
    const event = { sessionID: "v2-env", prompt: { text: "State:\n[[run envcheck.sh]]" } }
    await v2hooks["session.prompt"](event)
    assert.match(event.prompt.text, /PW=unset CACHE=unset HOME_OK=yes/)
  } finally {
    if (saved.pw === undefined) delete process.env.OPENCODE_SERVER_PASSWORD
    else process.env.OPENCODE_SERVER_PASSWORD = saved.pw
    if (saved.cache === undefined) delete process.env.XDG_CACHE_HOME
    else process.env.XDG_CACHE_HOME = saved.cache
  }
})
await check("[v2] [[run]] lines of a command run in the repository", async () => {
  const event = { sessionID: "v2-s", prompt: { text: "State:\n[[run hello.sh]]\nGo." } }
  await v2hooks["session.prompt"](event)
  assert.match(event.prompt.text, /hello from my-api/)
})
await check("[v2] a subagent session never asks a question (OpenCode v2 ignores experimental.primary_tools)", async () => {
  const sub = { sessionID: "v2-sub", prompt: { text: "You are a subagent spawned by another session.\nFind why the test fails." } }
  await v2hooks["session.prompt"](sub)
  await assert.rejects(() => v2hooks["tool.execute.before"]({ tool: "question", sessionID: "v2-sub", agent: "debugger", messageID: "m", id: "q1", input: { questions: [] } }), /a subagent never asks a question/)
})
await check("[v2] a primary session may still ask a question", () =>
  v2hooks["tool.execute.before"]({ tool: "question", sessionID: "v2-s", agent: "pilot", messageID: "m", id: "q2", input: { questions: [] } }))
await check("[v2] a subagent prompt that quotes a pilot command is not a run of it", async () => {
  const sub = { sessionID: "v2-sub2", prompt: { text: "You are a subagent spawned by another session.\nThe command says: Take the ticket from its analysis to its Draft merge request." } }
  await v2hooks["session.prompt"](sub)
  assert.doesNotMatch(sub.prompt.text, /refusé/)
  const pilot = { sessionID: "v2-pilot", prompt: { text: "Take the ticket from its analysis to its Draft merge request, now." } }
  await v2hooks["session.prompt"](pilot)
  assert.doesNotMatch(pilot.prompt.text, /refusé/)
})
await check("[v2] the references of opencode.json in OPENCODE_CONFIG_DIR are readable, comments and trailing commas included", async () => {
  const configDir = join(home, "oc2", "config", "opencode")
  const referenced = join(home, "repos", "legacy-ref")
  mkdirSync(configDir, { recursive: true })
  mkdirSync(referenced, { recursive: true })
  writeFileSync(join(referenced, "README.md"), "legacy\n")
  writeFileSync(join(configDir, "opencode.json"), '{\n  // my settings\n  "model": "fake/qwen",\n  "references": { "legacy": { "path": "' + referenced + '", }, },\n}\n')
  const refHooks = {}
  const onRef = (domain) => ({ hook: async (name, fn) => { refHooks[domain + "." + name] = fn } })
  const read = (path, id) => refHooks["tool.execute.before"]({ tool: "read", sessionID: "ref-s", agent: "coder", messageID: "m", id, input: { path } })
  process.env.OPENCODE_CONFIG_DIR = configDir
  try {
    await v2Plugin.setup({ location: { directory: repo }, tool: onRef("tool"), shell: onRef("shell"), session: onRef("session") })
    await read(join(referenced, "README.md"), "r1")
    await assert.rejects(() => read(join(home, "repos", "unreferenced", "README.md"), "r2"), /outside the repository/)
  } finally {
    delete process.env.OPENCODE_CONFIG_DIR
  }
})

// ---------- OpenCode v2 adapter: one /go, /fix or /fortify at a time per folder (9) ----------
const lockHooks = {}
const onLock = (domain) => ({ hook: async (name, fn) => { lockHooks[domain + "." + name] = fn } })
const queue = []
let wake
const stream = {
  subscribe: () => ({
    [Symbol.asyncIterator]() {
      return { next: () => new Promise((r) => { if (queue.length) r({ value: queue.shift(), done: false }); else wake = () => r({ value: queue.shift(), done: false }) }) }
    },
  }),
}
const push = (e) => { queue.push(e); if (wake) { const w = wake; wake = undefined; w() } }
await v2Plugin.setup({ location: { directory: repo }, tool: onLock("tool"), shell: onLock("shell"), session: onLock("session"), event: stream })
const goPrompt = (sessionID) => ({ sessionID, prompt: { text: "Request: ABC-1\nTake the ticket from its analysis to its Draft merge request, in this single run." } })
const first = goPrompt("lock-a")
await lockHooks["session.prompt"](first)
const second = goPrompt("lock-b")
await lockHooks["session.prompt"](second)
await check("[v2 lock] a second /go in the same folder gets the refusal sentence", () => assert.match(second.prompt.text, /⛔ \/go refusé : \/go tourne déjà dans ce dossier/))
await check("[v2 lock] no tool runs in the refused turn", () => assert.rejects(() => lockHooks["tool.execute.before"]({ tool: "shell", sessionID: "lock-b", agent: "pilot", id: "x", input: { command: "git status" } }), /this run was refused/))
const again = goPrompt("lock-a")
await lockHooks["session.prompt"](again)
await check("[v2 lock] the running session itself may go on", () => assert.doesNotMatch(again.prompt.text, /refusé/))
push({ type: "session.status", data: { sessionID: "lock-a", status: { type: "idle" } } })
await new Promise((r) => setTimeout(r, 20))
const third = goPrompt("lock-b")
await lockHooks["session.prompt"](third)
await check("[v2 lock] once the first session is idle, the folder is free", () => assert.doesNotMatch(third.prompt.text, /refusé/))
await check("[v2 lock] and the tools of that session run again", () => lockHooks["tool.execute.before"]({ tool: "shell", sessionID: "lock-b", agent: "pilot", id: "y", input: { command: "git status" } }))
const fortify = { sessionID: "lock-c", prompt: { text: "Fix a batch of Fortify vulnerabilities, from the scan to a Draft merge request" } }
await lockHooks["session.prompt"](fortify)
await check("[v2 lock] /fortify is refused while /go runs", () => assert.match(fortify.prompt.text, /⛔ \/fortify refusé : \/go tourne déjà/))
push({ type: "session.error", properties: { sessionID: "lock-b" } })
await new Promise((r) => setTimeout(r, 20))
const fortify2 = { sessionID: "lock-c", prompt: { text: "Fix a batch of Fortify vulnerabilities, from the scan to a Draft merge request" } }
await lockHooks["session.prompt"](fortify2)
await check("[v2 lock] an error of the running session frees the folder too", () => assert.doesNotMatch(fortify2.prompt.text, /refusé/))
const chat = { sessionID: "lock-d", prompt: { text: "explique-moi ce service" } }
await lockHooks["session.prompt"](chat)
await check("[v2 lock] a conversation is never refused", () => assert.equal(chat.prompt.text, "explique-moi ce service"))

console.log(`\n${count - failures}/${count} plugin checks as expected`)
process.exit(failures ? 1 : 0)
