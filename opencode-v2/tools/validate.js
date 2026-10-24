// Parses the frontmatter of every agent, command and skill with gray-matter, the parser used by OpenCode; then checks
// that FICHIERS.md describes every file of the pack (a "### `<path>`" heading each), describes no file that does not
// exist, and gives the right counts in its summary.
// Usage, from the repository root: npm install --no-save gray-matter@4.0.3 && node tools/validate.js
const matter = require("gray-matter")
const fs = require("fs")
const path = require("path")

const files = []
for (const dir of ["agents", "commands"]) {
  for (const f of fs.readdirSync(dir)) if (f.endsWith(".md")) files.push(path.join(dir, f))
}
for (const d of fs.readdirSync("skills")) files.push(path.join("skills", d, "SKILL.md"))

let failed = 0
for (const file of files) {
  try {
    const { data } = matter(fs.readFileSync(file, "utf8"))
    if (!data.description) throw new Error("missing description")
    if (file.startsWith("agents") && data.permission && typeof data.permission !== "object") {
      throw new Error("permission is not an object")
    }
  } catch (e) {
    failed++
    console.log("FAIL", file, "->", e.message.split("\n")[0])
  }
}
console.log(`${files.length - failed}/${files.length} files OK`)

// FICHIERS.md: every file of the pack has its heading, every heading names a file that exists
const IGNORED = new Set([".git", "node_modules"])
const pack = []
const walk = (dir) => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (IGNORED.has(entry.name)) continue
    const rel = dir === "." ? entry.name : path.join(dir, entry.name)
    if (entry.isDirectory()) walk(rel)
    else pack.push(rel.split(path.sep).join("/"))
  }
}
walk(".")
let problems = 0
const problem = (text) => {
  problems++
  console.log("FAIL FICHIERS.md ->", text)
}
let doc = ""
try {
  doc = fs.readFileSync("FICHIERS.md", "utf8")
} catch {
  problem("missing")
}
const described = new Set()
for (const line of doc.split("\n")) {
  if (!line.startsWith("### ")) continue
  for (const match of line.matchAll(/`([^`]+)`/g)) {
    // `/go`, `/outil abandon`: the command a heading names, not a file
    if (!match[1].startsWith("/")) described.add(match[1])
  }
}
for (const file of pack) if (!described.has(file)) problem(file + " is not described (a heading \"### `" + file + "`\")")
for (const name of described) if (!pack.includes(name)) problem("describes " + name + ", which does not exist")
const counts = { commandes: ["commands/", ".md"], agents: ["agents/", ".md"], skills: ["skills/", "/SKILL.md"], scripts: ["scripts/", ".sh"] }
for (const [word, [prefix, suffix]] of Object.entries(counts)) {
  const match = new RegExp("\\[Les " + word + "\\]\\([^)]*\\) \\((\\d+)\\)").exec(doc)
  const real = pack.filter((f) => f.startsWith(prefix) && f.endsWith(suffix)).length
  if (!match) problem("no count for « Les " + word + " » in its summary")
  else if (Number(match[1]) !== real) problem("« Les " + word + " » says " + match[1] + ", there are " + real)
}
console.log(problems ? `FICHIERS.md: ${problems} problem(s)` : `FICHIERS.md: the ${pack.length} files of the pack are described`)
process.exit(failed || problems ? 1 : 0)
