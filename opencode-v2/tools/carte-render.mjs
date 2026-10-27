// The diagrams of the flow map (docs/carte-des-flux.html) and of the deck of the flows (docs/presentation-flux.html),
// drawn once into each page: each <div class="diagram"> keeps
// its Mermaid source (<pre class="mermaid-src" hidden>) and gets its SVG next to it, so that the page shows its
// diagrams in every browser, offline, with no script and no CDN (a page that loads Mermaid from a CDN or from the
// runtime of a host shows none where that address is out of reach). The colors of the SVG are CSS variables of the
// page (--mm-…): its light and dark themes apply to the diagrams too. The labels are SVG text (no foreignObject), in
// Arial or its metric twin Liberation Sans, so that they fit their boxes on Windows, macOS and Linux alike.
//   node tools/carte-render.mjs [<page>]          draws the diagrams whose source changed, in both pages or in the one
//                                                 given (mmdc of @mermaid-js/mermaid-cli on the PATH: npm install -g
//                                                 @mermaid-js/mermaid-cli)
//   node tools/carte-render.mjs --check [<page>]  no drawing: each diagram has its SVG, drawn from its source as it is
//                                                 now (the hash of the source); exit 1 otherwise (the CI runs it)
// A node of a flowchart takes its color from a class of its source (classDef retry, time, stop, ok, agent, you, with
// the sentinel colors below), and each branch of a mind map from the scale of the theme: both become variables of the
// page, so that the two themes apply to them too.
// Output: "CARTE: <n> diagrams, <k> drawn, <size> KB (<page>)" per page, or "CARTE CHECK: OK (<n> diagrams: <page>
// <k>, …)"; "STALE:" lines then exit 1.
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// The version of the drawing: changing the settings below changes every hash, so that every diagram is drawn again
const RENDER = 'mermaid-11.16 base svg-labels v5 classes mindmap ids'
const FONT = 'Arial, "Liberation Sans", Helvetica, sans-serif'
// Sentinel colors given to Mermaid, then replaced by the variables of the page
const PALETTE = {
  '#fffdf8': 'var(--mm-bg)',
  '#f4efe4': 'var(--mm-surface)',
  '#42392e': 'var(--mm-text)',
  '#8a7f6d': 'var(--mm-line)',
  '#7a6c52': 'var(--mm-border)',
  '#fbf3df': 'var(--mm-note)',
  // the classes of the nodes of a flowchart (classDef <name> fill:…,stroke:…,color:#42392e)
  '#fdf0d5': 'var(--mm-retry)', '#b7791f': 'var(--mm-retry-line)',
  '#e7ecf3': 'var(--mm-time)', '#4a5b78': 'var(--mm-time-line)',
  '#fbe4e1': 'var(--mm-stop)', '#b23a30': 'var(--mm-stop-line)',
  '#e2f0e6': 'var(--mm-ok)', '#2f7d4f': 'var(--mm-ok-line)',
  '#e6edf7': 'var(--mm-agent)', '#3b6ea8': 'var(--mm-agent-line)',
  '#f1e8f6': 'var(--mm-you)', '#7b4f96': 'var(--mm-you-line)',
  // the branches of a mind map (cScale0 is its root)
  '#e9e1f6': 'var(--mm-c0)', '#dceaf6': 'var(--mm-c1)', '#dff1e7': 'var(--mm-c2)', '#f8ecd4': 'var(--mm-c3)',
  '#f6dedb': 'var(--mm-c4)', '#dcefee': 'var(--mm-c5)', '#eee6d8': 'var(--mm-c6)', '#e5e5f3': 'var(--mm-c7)',
}
const SCALE = ['#e9e1f6', '#dceaf6', '#dff1e7', '#f8ecd4', '#f6dedb', '#dcefee', '#eee6d8', '#e5e5f3']
const CONFIG = {
  theme: 'base',
  htmlLabels: false,
  flowchart: { htmlLabels: false, useMaxWidth: true, curve: 'basis', wrappingWidth: 320 },
  sequence: { useMaxWidth: true, mirrorActors: false },
  fontFamily: FONT,
  themeVariables: {
    fontFamily: FONT, fontSize: '14px', background: '#fffdf8',
    primaryColor: '#f4efe4', primaryTextColor: '#42392e', primaryBorderColor: '#7a6c52', lineColor: '#8a7f6d',
    secondaryColor: '#f4efe4', tertiaryColor: '#fffdf8', mainBkg: '#f4efe4', nodeBorder: '#7a6c52',
    clusterBkg: '#fffdf8', clusterBorder: '#7a6c52', titleColor: '#42392e', edgeLabelBackground: '#fffdf8',
    textColor: '#42392e', nodeTextColor: '#42392e',
    actorBkg: '#f4efe4', actorBorder: '#7a6c52', actorTextColor: '#42392e', actorLineColor: '#8a7f6d',
    signalColor: '#8a7f6d', signalTextColor: '#42392e', labelBoxBkgColor: '#f4efe4', labelBoxBorderColor: '#7a6c52',
    labelTextColor: '#42392e', loopTextColor: '#42392e', noteBkgColor: '#fbf3df', noteBorderColor: '#7a6c52',
    noteTextColor: '#42392e', activationBkgColor: '#f4efe4', activationBorderColor: '#7a6c52',
    sequenceNumberColor: '#fffdf8',
    // the root of a mind map
    git0: SCALE[0], gitBranchLabel0: '#42392e',
    ...Object.fromEntries(Array.from({ length: 12 }, (_, i) => [
      ['cScale' + i, SCALE[i % SCALE.length]], ['cScaleLabel' + i, '#42392e'], ['cScalePeer' + i, '#7a6c52'],
    ]).flat()),
  },
}

const args = process.argv.slice(2)
const check = args.includes('--check')
const here = dirname(fileURLToPath(import.meta.url))
const given = args.find((a) => !a.startsWith('--'))
const pages = given ? [resolve(given)] : ['carte-des-flux.html', 'presentation-flux.html'].map((p) => join(here, '..', 'docs', p)).filter(existsSync)

const DIAGRAM = /<div class="diagram"(?: data-hash="([0-9a-f]*)")?>\s*<pre class="mermaid-src" hidden>([\s\S]*?)<\/pre>\s*(?:<!-- svg -->[\s\S]*?<!-- \/svg -->\s*)?<\/div>/g
const unescape = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&')
const hashOf = (src) => createHash('sha256').update(RENDER + '\n' + src).digest('hex').slice(0, 16)

// the id of an SVG: carte-<hash> in the map, flux-<hash> in the deck; from the hash of its source, never from its
// place: a diagram added between two others must not take the id, and so the styles, of one that is not drawn again
const prefixOf = (page) => (basename(page).startsWith('presentation') ? 'flux' : 'carte')

if (check) {
  const stale = []
  const counts = []
  for (const page of pages) {
    const found = [...readFileSync(page, 'utf8').matchAll(DIAGRAM)]
    if (found.length === 0) stale.push(`STALE: no <div class="diagram"> with its <pre class="mermaid-src" hidden> in ${page}`)
    found.forEach((m, i) => {
      const src = unescape(m[2]).trim()
      if (!m[0].includes('<!-- svg -->')) stale.push(`STALE: ${basename(page)}: diagram ${i + 1} has no SVG (${src.split('\n')[0]})`)
      else if (m[1] !== hashOf(src)) stale.push(`STALE: ${basename(page)}: diagram ${i + 1} was drawn from another source (${src.split('\n')[0]})`)
    })
    counts.push(`${basename(page)} ${found.length}`)
  }
  if (stale.length) {
    for (const line of stale) console.log(line)
    console.log('Draw them again: node tools/carte-render.mjs (mmdc on the PATH)')
    process.exit(1)
  }
  console.log(`CARTE CHECK: OK (${counts.join(', ')} diagrams)`)
  process.exit(0)
}

// The SVG of a source: drawn by mmdc, its colors made variables, its numbers rounded, its id unique in the page
function draw(src, id, work) {
  const input = join(work, `${id}.mmd`)
  const output = join(work, `${id}.svg`)
  writeFileSync(input, src + '\n')
  execFileSync('mmdc', ['-q', '-i', input, '-o', output, '-c', join(work, 'config.json'), '-b', 'transparent', '-I', id], { stdio: ['ignore', 'ignore', 'inherit'] })
  let svg = readFileSync(output, 'utf8').replace(/^<\?xml[^>]*>\s*/, '')
  for (const [color, variable] of Object.entries(PALETTE)) {
    svg = svg.split(color).join(variable)
    // the rules of a class of nodes (classDef) carry the same color as rgb(r, g, b)
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(color.slice(i, i + 2), 16))
    svg = svg.replace(new RegExp(`rgb\\(\\s*${r},\\s*${g},\\s*${b}\\s*\\)`, 'g'), variable)
  }
  // a label background drawn half transparent over the page: the same variable, in both themes
  svg = svg.replace(/rgba\(255, ?253, ?248, ?0\.5\)/g, 'var(--mm-bg)')
  // the coordinates to 2 decimals (a third of the size), never a number of a label
  svg = svg.replace(/(\s(?:d|points|transform|x|y|x1|x2|y1|y2|width|height|viewBox|style|cx|cy|r|rx|ry|dx|dy)=")([^"]*)"/g,
    (all, name, value) => name + value.replace(/(\d+\.\d{2})\d+/g, '$1') + '"')
  if (/foreignObject/.test(svg)) throw new Error(`${id}: a label in HTML (foreignObject): the diagram needs SVG text labels`)
  // a mind map computes some colors from its scale (the line under a node, the text of the root): the variables too
  if (/aria-roledescription="mindmap"|class="mindmapDiagram"/.test(svg)) {
    svg = svg.replace(/stroke:rgb\([^)]*\)/g, 'stroke:var(--mm-line)').replace(/fill:rgb\([^)]*\)/g, 'fill:var(--mm-text)')
    // the tidy-tree layout leaves the label of the root and of a branch starting at the center of its shape
    svg = svg.replace(/(<g class="label" style="" transform="translate\(0, [-\d.]+\)"><rect\/><g><rect class="background" style="stroke: none"\/><text )/g, '$1text-anchor="middle" ')
  }
  return slim(svg)
}

// What a static diagram of this page never uses: a <tspan> per word (the words of a line are one text), the arrow
// heads no edge points to, the rules of other looks, of animations, of formulas and of tooltips; the empty styles
function slim(svg) {
  svg = svg.replace(/<tspan font-style="normal" class="text-inner-tspan" font-weight="normal">([^<]*)<\/tspan>/g, '$1')
  svg = svg.replace(/<marker id="([^"]+)"[\s\S]*?<\/marker>/g, (marker, markerId) => (svg.includes(`url(#${markerId})`) ? marker : ''))
  svg = svg.replace(/<style>([\s\S]*?)<\/style>/, (all, css) => {
    css = css.replace(/@keyframes[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/g, '')
    const rules = css.split('}').filter((rule) => rule.trim() && !/data-look|katex|edge-animation|mermaidTooltip|:root\{/.test(rule))
    return `<style>${rules.join('}')}}</style>`
  })
  return svg.replace(/ style=""/g, '')
}

const work = mkdtempSync(join(tmpdir(), 'carte-render-'))
try {
  writeFileSync(join(work, 'config.json'), JSON.stringify(CONFIG))
  for (const page of pages) {
    const html = readFileSync(page, 'utf8')
    const found = [...html.matchAll(DIAGRAM)]
    if (found.length === 0) {
      console.log(`STOP: no <div class="diagram"> with its <pre class="mermaid-src" hidden> in ${page}`)
      process.exit(1)
    }
    let drawn = 0
    const out = html.replace(DIAGRAM, (whole, hash, escaped) => {
      const src = unescape(escaped).trim()
      const want = hashOf(src)
      if (hash === want && whole.includes('<!-- svg -->')) return whole
      drawn += 1
      const svg = draw(src, `${prefixOf(page)}-${want}`, work)
      return `<div class="diagram" data-hash="${want}">\n<pre class="mermaid-src" hidden>${escaped}</pre>\n<!-- svg -->${svg}<!-- /svg -->\n</div>`
    })
    writeFileSync(page, out)
    console.log(`CARTE: ${found.length} diagrams, ${drawn} drawn, ${Math.round(Buffer.byteLength(out) / 1024)} KB (${page})`)
  }
} finally {
  rmSync(work, { recursive: true, force: true })
}
