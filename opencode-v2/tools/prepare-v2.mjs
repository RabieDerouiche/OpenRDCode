// Prepares the configuration of OpenCode v2 for the pack, next to OpenCode 1.19 and without touching it.
// Reads ~/.config/opencode (the 1.19 configuration) and writes ~/oc2/config/opencode (the v2 configuration):
// - opencode.json: a copy of the 1.19 one whose "agent" and "permission" sections come from opencode.snippet.json
//   ("experimental" and "compaction" too when the 1.19 file has none); everything else (provider, mcp, model,
//   references...) is kept as it is. An existing v2 file is first saved as opencode.json.bak-<date>.
// - agents, commands, plugins (openrd-pack.js only) and skills of this folder.
// - AGENTS.md: AGENTS.global.md of this folder, with the "## Daily" and "## Release groups" sections of the 1.19
//   AGENTS.md when it has them.
// - the pack's scripts into ~/.config/opencode/scripts, where the commands and the rules call them (the same scripts
//   as the 1.19 pack, plus fortify.sh).
// Never prints a value of the configuration (it may hold keys): only section names and counts.
// Usage, from the clone of the pack: node opencode-v2/tools/prepare-v2.mjs
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const pack = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const home = homedir()
const oldDir = join(home, ".config", "opencode")
const newDir = join(home, "oc2", "config", "opencode")
const fail = (message) => {
  console.error("STOP: " + message)
  process.exit(1)
}
const readJson = (file) => {
  const text = readFileSync(file, "utf8")
  try {
    return JSON.parse(text)
  } catch {
    // opencode.json may hold // comments (JSONC): removed outside strings
    return JSON.parse(text.replace(/("(?:\\.|[^"\\])*")|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, (m, s) => s || ""))
  }
}

if (!existsSync(join(pack, "opencode.snippet.json")) || !existsSync(join(pack, "plugins", "openrd-pack.js"))) {
  fail("run it from the clone of the pack: node opencode-v2/tools/prepare-v2.mjs")
}
const oldConfigFile = ["opencode.json", "opencode.jsonc"].map((n) => join(oldDir, n)).find((f) => existsSync(f))
if (!oldConfigFile) fail("no opencode.json in " + oldDir + ": the configuration of OpenCode 1.19 is needed")
let config
try {
  config = readJson(oldConfigFile)
} catch (error) {
  fail("cannot read " + oldConfigFile + " (" + String(error.message).split("\n")[0] + ")")
}
const snippet = readJson(join(pack, "opencode.snippet.json"))

// 1. folders
for (const sub of ["agents", "commands", "plugins", "skills"]) mkdirSync(join(newDir, sub), { recursive: true })
mkdirSync(join(home, "oc2", "data"), { recursive: true })

// 2. opencode.json
const merged = { ...config, agent: snippet.agent, permission: snippet.permission }
const added = []
for (const key of ["experimental", "compaction"]) {
  if (merged[key] === undefined && snippet[key] !== undefined) {
    merged[key] = snippet[key]
    added.push(key)
  }
}
const newConfigFile = join(newDir, "opencode.json")
if (existsSync(newConfigFile)) {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").slice(0, 15)
  copyFileSync(newConfigFile, newConfigFile + ".bak-" + stamp)
  console.log("SAVED: the previous v2 opencode.json as opencode.json.bak-" + stamp)
}
writeFileSync(newConfigFile, JSON.stringify(merged, null, 2) + "\n", { mode: 0o600 })
const kept = Object.keys(config).filter((k) => !["agent", "permission"].includes(k))
console.log("CONFIG: " + newConfigFile + " — agent and permission from the pack" + (added.length ? ", " + added.join(" and ") + " added" : "") + "; kept from 1.19: " + (kept.join(", ") || "nothing"))

// 3. agents, commands, plugins, skills
for (const sub of ["agents", "commands", "skills"]) cpSync(join(pack, sub), join(newDir, sub), { recursive: true, force: true })
for (const old of ["compact-commands.js"]) rmSync(join(newDir, "plugins", old), { force: true })
copyFileSync(join(pack, "plugins", "openrd-pack.js"), join(newDir, "plugins", "openrd-pack.js"))
const plugins = readdirSync(join(newDir, "plugins"))
console.log("PACK: " + readdirSync(join(newDir, "agents")).length + " agents, " + readdirSync(join(newDir, "commands")).length + " commands, " + readdirSync(join(newDir, "skills")).length + " skills, plugins: " + plugins.join(", "))
if (plugins.some((p) => p !== "openrd-pack.js")) console.log("WARNING: other files in " + join(newDir, "plugins") + ": OpenCode v2 loads every .js there; keep openrd-pack.js only")

// 4. AGENTS.md
const section = (text, title) => {
  const start = text.search(new RegExp("^## " + title + "\\b", "m"))
  if (start < 0) return undefined
  const next = text.slice(start + 3).search(/^## /m)
  return next < 0 ? text.slice(start) : text.slice(start, start + 3 + next)
}
let agents = readFileSync(join(pack, "AGENTS.global.md"), "utf8")
const oldAgentsFile = join(oldDir, "AGENTS.md")
const oldAgents = existsSync(oldAgentsFile) ? readFileSync(oldAgentsFile, "utf8") : ""
const taken = []
for (const title of ["Daily", "Release groups"]) {
  const mine = section(oldAgents, title)
  const theirs = section(agents, title)
  if (mine && theirs) {
    agents = agents.replace(theirs, mine.endsWith("\n") ? mine : mine + "\n")
    taken.push(title)
  }
}
writeFileSync(join(newDir, "AGENTS.md"), agents)
console.log("AGENTS.md: from the pack" + (taken.length ? ", with your sections " + taken.map((t) => "« " + t + " »").join(" and ") : "; no « Daily » or « Release groups » section found in your 1.19 AGENTS.md: fill them by hand"))

// 5. scripts, shared with 1.19
const scripts = join(oldDir, "scripts")
mkdirSync(scripts, { recursive: true })
const shell = readdirSync(join(pack, "scripts")).filter((f) => f.endsWith(".sh"))
for (const f of shell) copyFileSync(join(pack, "scripts", f), join(scripts, f))
console.log("SCRIPTS: " + shell.length + " scripts in " + scripts + " (fortify.sh included)")
console.log("DONE: the configuration of OpenCode 1.19 was only read, never changed")
