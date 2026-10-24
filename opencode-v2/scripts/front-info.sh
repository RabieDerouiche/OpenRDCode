#!/bin/sh
# What a front-end package is and how its tests run, read from its files (read-only): one "key=value" line each, for
# front-test.sh and detect-project-type.sh. Never eval these lines: the values come from package.json.
#   dir        the folder of the package (relative to the repository root, "." at the root)
#   pm         npm, yarn, yarn-berry or pnpm (from the lockfile of the folder or of the repository root)
#   lock       the lockfile, or "none"
#   framework  angular <major>, react <major>, vue <major>, svelte, next <major>, nuxt <major>, or "none"
#   test       the "test" script of package.json, or "none"
#   runner     karma-ng, vitest-ng, jest-ng, ng (Angular CLI with another builder), cra, vitest, jest, karma, mocha,
#              node, e2e (Playwright, Cypress, TestCafe: they need the application running), nx, none, other
#   watch      1 when the test script itself asks for a watch mode
#   build      the "build" script, or "none"
#   node       the version of node on this machine, or "none"
#   nodewant   the major version of node the package asks for (.nvmrc, .node-version, engines.node), or "none"
# Usage: front-info.sh [<folder with a package.json>] (default: the package of the repository root, otherwise the
# first package with a UI framework)

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$root" || exit 1
dir=${1:-}
dir=${dir%/}
dir=${dir%/package.json}
case "$dir" in "$root"/*) dir=${dir#"$root"/} ;; "$root") dir=. ;; esac
if [ -z "$dir" ]; then
  if [ -f package.json ]; then
    dir=.
  else
    dir=$(git ls-files 'package.json' '*/package.json' 2>/dev/null | grep -v node_modules |
      while IFS= read -r f; do grep -q -E '"(@angular/core|react|vue|svelte|next|nuxt)"[[:space:]]*:' "$f" && { dirname "$f"; break; }; done)
  fi
fi
[ -n "$dir" ] && [ -f "$dir/package.json" ] || { echo "dir=none"; exit 0; }
echo "dir=$dir"

# the package manager: the lockfile of the folder, otherwise of the repository root (a workspace)
pm=npm lock=none
for d in "$dir" .; do
  if [ -f "$d/pnpm-lock.yaml" ]; then pm=pnpm lock="$d/pnpm-lock.yaml"; break
  elif [ -f "$d/yarn.lock" ]; then
    pm=yarn lock="$d/yarn.lock"
    { [ -f "$d/.yarnrc.yml" ] || [ -f .yarnrc.yml ]; } && pm=yarn-berry
    break
  elif [ -f "$d/package-lock.json" ]; then pm=npm lock="$d/package-lock.json"; break
  elif [ -f "$d/npm-shrinkwrap.json" ]; then pm=npm lock="$d/npm-shrinkwrap.json"; break
  fi
done
echo "pm=$pm"
echo "lock=${lock#./}"

if command -v node >/dev/null 2>&1; then
  echo "node=$(node --version 2>/dev/null)"
  # package.json and angular.json read by node: their scripts, dependencies and the builder of the tests
  node - "$dir" <<'EOF'
const fs = require("fs")
const path = require("path")
const dir = process.argv[2]
const read = (f) => { try { return JSON.parse(fs.readFileSync(f, "utf8")) } catch { return undefined } }
const pkg = read(path.join(dir, "package.json")) || {}
const scripts = pkg.scripts || {}
const deps = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) }
const major = (v) => { const m = /(\d+)/.exec(String(v || "")); return m ? m[1] : "" }
let framework = "none"
for (const [name, label] of [["@angular/core", "angular"], ["next", "next"], ["nuxt", "nuxt"], ["react", "react"], ["vue", "vue"], ["svelte", "svelte"]]) {
  if (deps[name]) { framework = (label + " " + major(deps[name])).trim(); break }
}
const one = (s) => String(s || "").replace(/[\r\n]+/g, " ").trim()
const test = one(scripts.test)
const t = test.toLowerCase()
// the builder of "ng test": angular.json of the folder, otherwise of the repository root
let builder = ""
for (const f of [path.join(dir, "angular.json"), "angular.json"]) {
  const ng = read(f)
  if (!ng || !ng.projects) continue
  const projects = Object.values(ng.projects)
  const app = projects.find((p) => (p.projectType || "application") === "application") || projects[0]
  const targets = (app && (app.architect || app.targets)) || {}
  builder = (targets.test && targets.test.builder) || ""
  // the unit-test builder (Angular 21) runs Vitest, or Karma when its runner option says so
  const options = (targets.test && targets.test.options) || {}
  if (/unit-test/.test(builder) && options.runner === "karma") builder += " (runner karma)"
  break
}
let runner = "other"
if (!test || /no test specified/.test(t)) runner = "none"
else if (/\bng\s+test\b/.test(t)) runner = /karma/.test(builder) ? "karma-ng" : /unit-test/.test(builder) ? "vitest-ng" : /jest/.test(builder) ? "jest-ng" : "ng"
else if (/\b(react-scripts|craco|rescripts)\s+test\b/.test(t)) runner = "cra"
else if (/\bvitest\b/.test(t)) runner = "vitest"
else if (/\bjest\b/.test(t)) runner = "jest"
else if (/\bkarma\s+start\b/.test(t)) runner = "karma"
else if (/\bmocha\b/.test(t)) runner = "mocha"
else if (/\bnode\s+(--test|--experimental-test)/.test(t)) runner = "node"
else if (/\b(playwright\s+test|cypress\s+run|testcafe)\b/.test(t)) runner = "e2e"
else if (/\bnx\s+(run-many|affected|test|run)\b/.test(t)) runner = "nx"
const watch = /--watch(all)?(?![=:]false)\b/.test(t) && !/--watch(all)?[=:]false/.test(t) ? 1 : 0
let nodewant = ""
for (const f of [path.join(dir, ".nvmrc"), path.join(dir, ".node-version"), ".nvmrc", ".node-version"]) {
  try { const v = fs.readFileSync(f, "utf8").trim().replace(/^v/, ""); if (v) { nodewant = major(v) + " (" + f.replace(/^\.\//, "") + ")"; break } } catch {}
}
if (!nodewant && pkg.engines && pkg.engines.node) nodewant = one(pkg.engines.node) + " (engines.node)"
console.log("framework=" + framework)
console.log("test=" + (test || "none"))
console.log("runner=" + runner)
if (builder) console.log("builder=" + builder)
console.log("watch=" + watch)
console.log("build=" + (one(scripts.build) || "none"))
console.log("nodewant=" + (nodewant || "none"))
EOF
else
  echo "node=none"
  echo "framework=none"
  echo "test=$(sed -n 's/.*"test"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/package.json" | head -n 1 | grep . || echo none)"
  echo "runner=other"
  echo "watch=0"
  echo "build=$(sed -n 's/.*"build"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$dir/package.json" | head -n 1 | grep . || echo none)"
  echo "nodewant=none"
fi
exit 0
