// Tests of the guards of the pack plugin (plugins/compact-commands.js): the repository jail (7), the refusals of
// environment dumps and recursive rm, the long timeouts (8), one /go or /fix at a time (9) and the outcome in the
// session title (10). The plugin runs against a fake OpenCode client, in a fake home folder.
// Usage, from v2/: node tools/plugin-test.mjs
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs"
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

const { CompactCommands } = await import(join(pack, "plugins", "compact-commands.js"))

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
}
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

console.log(`\n${count - failures}/${count} plugin checks as expected`)
process.exit(failures ? 1 : 0)
