// Parses the frontmatter of every agent, command and skill with gray-matter, the parser used by OpenCode.
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
process.exit(failed ? 1 : 0)
