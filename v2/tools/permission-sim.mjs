// Faithful port of the OpenCode 1.19.0 permission checks used by the pack:
// - core/src/util/wildcard.ts (match), opencode/src/permission/index.ts (fromConfig, merge, evaluate, disabled)
// - opencode/src/agent/agent.ts (defaults, build/plan, custom agents from markdown)
// - opencode/src/agent/subagent-permissions.ts (session rules of a subagent spawned by the task tool)
// - opencode/src/tool/shell.ts (tree-sitter scan: command nodes, source(), FILES/CWD, external_directory)
// - opencode/src/tool/read.ts, edit.ts, write.ts (pattern = path relative to the worktree, external_directory)
// Usage, from tools/: npm install --no-save web-tree-sitter@0.25.10 tree-sitter-bash@0.25.0 gray-matter@4.0.3 && node permission-sim.mjs .. [--verbose]
import fs from "node:fs"
import path from "node:path"
import matter from "gray-matter"
import { Parser, Language } from "web-tree-sitter"
import { cases } from "./permission-corpus.mjs"

const pack = process.argv[2]
const verbose = process.argv.includes("--verbose")
const HOME = "/home/dev"
const PROJECT = "/home/dev/repos/my-api"

// ---------- wildcard / rules ----------
function match(input, pattern) {
  const normalized = input.replaceAll("\\", "/")
  let escaped = pattern.replaceAll("\\", "/").replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".")
  if (escaped.endsWith(" .*")) escaped = escaped.slice(0, -3) + "( .*)?"
  return new RegExp("^" + escaped + "$", "s").test(normalized)
}
function expand(p) {
  if (p.startsWith("~/")) return HOME + p.slice(1)
  if (p === "~") return HOME
  if (p.startsWith("$HOME/")) return HOME + p.slice(5)
  if (p.startsWith("$HOME")) return HOME + p.slice(5)
  return p
}
function fromConfig(cfg) {
  const out = []
  for (const [key, value] of Object.entries(cfg ?? {})) {
    if (typeof value === "string") out.push({ permission: key, action: value, pattern: "*" })
    else for (const [pattern, action] of Object.entries(value)) out.push({ permission: key, pattern: expand(pattern), action })
  }
  return out
}
function evaluate(permission, pattern, ...rulesets) {
  return rulesets.flat().findLast((r) => match(permission, r.permission) && match(pattern, r.pattern)) ?? { action: "ask", permission, pattern: "*" }
}

// ---------- agents ----------
const snippet = JSON.parse(fs.readFileSync(path.join(pack, "opencode.snippet.json"), "utf8"))
const TRUNC = path.join(HOME, ".local/share/opencode/tool-output/*")
const whitelisted = [TRUNC, "/tmp/opencode/*", path.join(HOME, ".config/opencode/skills/*")]
const defaults = fromConfig({
  "*": "allow",
  doom_loop: "ask",
  external_directory: { "*": "ask", ...Object.fromEntries(whitelisted.map((d) => [d, "allow"])) },
  question: "deny",
  plan_enter: "deny",
  plan_exit: "deny",
  read: { "*": "allow", "*.env": "ask", "*.env.*": "ask", "*.env.example": "allow" },
})
const user = fromConfig(snippet.permission)
const agents = {}
agents.build = [...defaults, ...fromConfig({ question: "allow", plan_enter: "allow" }), ...user]
agents.plan = [...defaults, ...fromConfig({ question: "allow", plan_exit: "allow", task: { general: "deny" }, edit: { "*": "deny" } }), ...user]
for (const [name, value] of Object.entries(snippet.agent ?? {})) {
  if (!agents[name]) agents[name] = [...defaults, ...user]
  agents[name] = [...agents[name], ...fromConfig(value.permission)]
}
for (const file of fs.readdirSync(path.join(pack, "agents"))) {
  const name = file.replace(/\.md$/, "")
  const { data } = matter(fs.readFileSync(path.join(pack, "agents", file), "utf8"))
  agents[name] = [...defaults, ...user, ...fromConfig(data.permission)]
}
for (const name of Object.keys(agents)) agents[name].push({ permission: "external_directory", pattern: TRUNC, action: "allow" })
// A subagent spawned by the task tool gets session rules that come after its own (last match wins)
function subSession(name) {
  const own = agents[name]
  const out = []
  if (!own.some((r) => r.permission === "todowrite")) out.push({ permission: "todowrite", pattern: "*", action: "deny" })
  if (!own.some((r) => r.permission === "task")) out.push({ permission: "task", pattern: "*", action: "deny" })
  return out
}

// ---------- shell scan ----------
await Parser.init()
const parser = new Parser()
parser.setLanguage(await Language.load(new URL("./node_modules/tree-sitter-bash/tree-sitter-bash.wasm", import.meta.url).pathname))
const CWD = new Set(["cd", "chdir", "popd", "pushd", "push-location", "set-location"])
const FILES = new Set([...CWD, "rm", "cp", "mv", "mkdir", "touch", "chmod", "chown", "cat"])
function parts(node) {
  const out = []
  for (let i = 0; i < node.childCount; i++) {
    const child = node.child(i)
    if (!child) continue
    if (!["command_name", "command_name_expr", "word", "string", "raw_string", "concatenation"].includes(child.type)) continue
    out.push({ type: child.type, text: child.text })
  }
  return out
}
const source = (node) => (node.parent?.type === "redirected_statement" ? node.parent.text : node.text).trim()
const unquote = (t) => (t.length >= 2 && (t[0] === '"' || t[0] === "'") && t[0] === t[t.length - 1] ? t.slice(1, -1) : t)
const home = (t) => (t === "~" ? HOME : t.startsWith("~/") ? path.join(HOME, t.slice(2)) : t)
function prefix(t) {
  const m = /[?*[]/.exec(t)
  if (!m) return t
  if (m.index === 0) return
  return t.slice(0, m.index)
}
const dynamic = (t) => t.startsWith("(") || t.startsWith("@(") || t.includes("$(") || t.includes("${") || t.includes("`") || t.includes("$")
const inside = (p) => p === PROJECT || p.startsWith(PROJECT + "/")
function scan(command, cwd = PROJECT) {
  const tree = parser.parse(command)
  const dirs = new Set()
  const patterns = new Set()
  for (const node of tree.rootNode.descendantsOfType("command")) {
    const list = parts(node)
    const tokens = list.map((p) => p.text)
    const cmd = tokens[0]
    if (cmd && FILES.has(cmd)) {
      for (const arg of tokens.slice(1).filter((a) => !a.startsWith("-") && !(cmd === "chmod" && a.startsWith("+")))) {
        const text = home(unquote(arg))
        const file = text && prefix(text)
        if (!file || dynamic(file)) continue
        const resolved = path.resolve(cwd, file)
        if (inside(resolved)) continue
        dirs.add(/\.[A-Za-z0-9]+$/.test(resolved) ? path.dirname(resolved) : resolved)
      }
    }
    if (tokens.length && (!cmd || !CWD.has(cmd))) patterns.add(source(node))
  }
  if (!inside(cwd)) dirs.add(cwd)
  tree.delete()
  return { dirs: [...dirs], patterns: [...patterns] }
}

const RANK = { allow: 0, ask: 1, deny: 2 }
function check(c) {
  const rules = c.sub ? [...agents[c.agent], ...subSession(c.agent)] : agents[c.agent]
  if (!rules) throw new Error("unknown agent " + c.agent)
  const why = []
  let worst = "allow"
  const bump = (action, text) => {
    if (RANK[action] > RANK[worst]) worst = action
    if (action !== "allow") why.push(text)
  }
  if (c.cmd !== undefined) {
    const s = scan(c.cmd, c.cwd)
    for (const dir of s.dirs) {
      const r = evaluate("external_directory", path.join(dir, "*"), rules)
      bump(r.action, `external_directory ${dir}/* -> ${r.action}`)
    }
    // Permission.ask stops at the first deny; otherwise ask if any pattern asks
    for (const p of s.patterns) {
      const r = evaluate("bash", p, rules)
      bump(r.action, `"${p}" -> ${r.action} (rule ${JSON.stringify(r.pattern)})`)
    }
  } else if (c.read || c.edit) {
    const target = path.resolve(PROJECT, home(c.read ?? c.edit))
    if (!inside(target)) {
      const r = evaluate("external_directory", path.join(path.dirname(target), "*"), rules)
      bump(r.action, `external_directory -> ${r.action}`)
    }
    const perm = c.read ? "read" : "edit"
    const rel = path.relative(PROJECT, target)
    const r = evaluate(perm, rel, rules)
    bump(r.action, `${perm} ${rel} -> ${r.action} (rule ${JSON.stringify(r.pattern)})`)
  } else if (c.task) {
    const r = evaluate("task", c.task, rules)
    bump(r.action, `task ${c.task} -> ${r.action}`)
  } else if (c.tool) {
    // visibility of a tool (disabled(): last rule whose permission matches decides when its pattern is "*" and deny)
    const r = rules.findLast((rule) => match(c.tool, rule.permission))
    const hidden = r?.pattern === "*" && r.action === "deny"
    worst = hidden ? "deny" : r?.action === "ask" ? "ask" : "allow"
    why.push(`tool ${c.tool} ${hidden ? "hidden" : "visible"} (last rule ${JSON.stringify(r)})`)
  }
  return { result: worst, why }
}

let failed = 0
const counts = {}
for (const c of cases) {
  const { result, why } = check(c)
  counts[c.agent] = (counts[c.agent] ?? 0) + 1
  const ok = result === c.expect
  if (!ok) failed++
  if (!ok || verbose) {
    const what = c.cmd ?? c.read ?? c.edit ?? c.task ?? c.tool
    console.log(`${ok ? "ok  " : "FAIL"} [${c.agent}${c.sub ? " (sub)" : ""}] expect ${c.expect}, got ${result}: ${what}${c.note ? "   # " + c.note : ""}`)
    if (!ok) for (const w of why) console.log("       " + w)
  }
}
// size of the rules dumped into the model context by a bash denial (DeniedError lists every rule whose permission matches "bash")
const dump = Object.fromEntries(Object.entries(agents).map(([n, r]) => [n, JSON.stringify(r.filter((x) => match("bash", x.permission))).length]))
console.log(`\n${cases.length - failed}/${cases.length} cases as expected`)
console.log("bash rules dumped on a denial (characters):", JSON.stringify(dump))
process.exit(failed ? 1 : 0)
