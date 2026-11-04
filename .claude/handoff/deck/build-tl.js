// The deck for the tech leads: agentic AI, DevX, then the flows; native PowerPoint shapes only (rounded rectangles, diamonds, lines), short labels,
// the details in the speaker notes. node build.js <output.pptx>
const pptxgen = require('pptxgenjs')
const JSZip = require('jszip')
const fs = require('fs')
// apply_theme.js comes with the pptx skill; its folder changes from one session to the next
const { applyTheme } = require(process.env.APPLY_THEME || require('child_process').execSync('ls -d /root/.claude/skills/*/*/pptx/scripts/apply_theme.js /root/.claude/skills/*/pptx/scripts/apply_theme.js 2>/dev/null | head -n 1').toString().trim())

const OUT = process.argv[2] || 'flux.pptx'
const THEME = {
  name: 'Flux',
  headFontFace: 'Calibri',
  bodyFontFace: 'Calibri',
  colors: {
    dk1: '1F2933', lt1: 'FFFFFF', dk2: '3E4C59', lt2: 'F4F5F7',
    accent1: '2E6DA4', accent2: '7B4F96', accent3: 'B7791F', accent4: 'B23A30', accent5: '2F7D4F', accent6: '4A5B78',
    hlink: '2E6DA4', folHlink: '7B4F96',
  },
}
const INK = '1F2933'
const MUTED = '5B6470'
const WIRE = '6B7280'
const KIND = {
  step: { fill: 'F4F5F7', line: '7A828C' },
  agent: { fill: 'E4EEF8', line: '2E6DA4' },
  you: { fill: 'F1E9F7', line: '7B4F96' },
  ok: { fill: 'E3F2E7', line: '2F7D4F' },
  stop: { fill: 'FBE6E3', line: 'B23A30' },
  retry: { fill: 'FDF0D5', line: 'B7791F', text: '6B4A0E' },
  time: { fill: 'EEF1F6', line: '4A5B78', text: '2F3B52' },
  note: { fill: 'FFFFFF', line: 'A3AAB3', text: MUTED },
}

const pres = new pptxgen()
pres.layout = 'LAYOUT_WIDE'
pres.title = 'Des agents IA, du ticket à la merge request'
pres.subject = "L'IA agentique, DevX, /daily, /go, /fix, /fortify"
pres.theme = { headFontFace: 'Calibri', bodyFontFace: 'Calibri' }

// ---------- layouts ----------
pres.defineSlideMaster({
  title: 'TITRE',
  background: { color: '1F2933' },
  objects: [
    { placeholder: { options: { name: 'title', type: 'title', x: 0.8, y: 1.9, w: 11.7, h: 1.6, fontSize: 44, bold: true, color: 'FFFFFF', valign: 'bottom', align: 'left', fontFace: 'Calibri', margin: 0 }, text: '' } },
    { placeholder: { options: { name: 'body', type: 'body', x: 0.8, y: 3.7, w: 11.7, h: 1.2, fontSize: 20, color: 'C9D2DC', valign: 'top', align: 'left', fontFace: 'Calibri', margin: 0 }, text: '' } },
  ],
})
// the legend of the diagrams, the same on every diagram slide
const legend = []
const legendItems = [
  ['agent', 'un agent IA'], ['step', 'une étape automatique'], ['you', 'le développeur'], ['ok', 'livré'],
  ['stop', 'arrêt, avec sa raison'], ['retry', '↻ relancé tout seul'], ['time', '≤ borné dans le temps'],
]
let lx = 0.5
for (const [k, label] of legendItems) {
  legend.push({ rect: { x: lx, y: 7.04, w: 0.3, h: 0.18, fill: { color: KIND[k].fill }, line: { color: KIND[k].line, width: 1, dashType: k === 'time' ? 'dash' : 'solid' } } })
  const w = label.length * 0.062 + 0.1
  legend.push({ text: { text: label, options: { x: lx + 0.34, y: 6.98, w, h: 0.3, fontSize: 10, color: MUTED, fontFace: 'Calibri', margin: 0, valign: 'middle' } } })
  lx += 0.34 + w + 0.14
}
// pptxgenjs converts the options it is given in place: each layout gets its own objects
const header = () => [
  { placeholder: { options: { name: 'title', type: 'title', x: 0.5, y: 0.3, w: 12.33, h: 0.7, fontSize: 30, bold: true, color: INK, valign: 'middle', align: 'left', fontFace: 'Calibri', margin: 0 }, text: '' } },
  { placeholder: { options: { name: 'body', type: 'body', x: 0.5, y: 0.98, w: 12.33, h: 0.45, fontSize: 15, color: MUTED, valign: 'top', align: 'left', fontFace: 'Calibri', margin: 0 }, text: '' } },
]
const pageNumber = () => ({ x: 12.35, y: 6.98, w: 0.5, h: 0.3, fontSize: 10, color: '8A939C', fontFace: 'Calibri', align: 'right' })
pres.defineSlideMaster({ title: 'SCHEMA', background: { color: 'FFFFFF' }, slideNumber: pageNumber(), objects: header() })
pres.defineSlideMaster({ title: 'TEXTE', background: { color: 'FFFFFF' }, slideNumber: pageNumber(), objects: header() })

// ---------- drawing ----------
function canvas(slide) {
  const B = {}
  let n = 0
  const name = (p) => `${p}-${++n}`
  const api = {
    // a block: its name in bold, a short second line
    node(id, x, y, w, h, kind, title, sub, size = 13) {
      const runs = [{ text: title, options: { bold: true, fontSize: size, breakLine: !!sub } }]
      if (sub) runs.push({ text: sub, options: { fontSize: size - 2, color: '3E4C59' } })
      slide.addText(runs, {
        shape: pres.shapes.ROUNDED_RECTANGLE, x, y, w, h, rectRadius: 0.08,
        fill: { color: KIND[kind].fill }, line: { color: KIND[kind].line, width: 1.25 },
        fontFace: 'Calibri', color: INK, align: 'center', valign: 'middle', margin: 3, objectName: id,
      })
      B[id] = { x, y, w, h }
      return api
    },
    dia(id, x, y, w, h, text, size = 12) {
      slide.addText(text, {
        shape: pres.shapes.DIAMOND, x, y, w, h, fill: { color: 'FFFFFF' }, line: { color: '7A828C', width: 1.25 },
        fontFace: 'Calibri', fontSize: size, bold: true, color: INK, align: 'center', valign: 'middle', margin: 0, objectName: id,
      })
      B[id] = { x, y, w, h }
      return api
    },
    // a small tag stuck on a block: a retry, a time limit, a note
    tag(kind, x, y, w, text, h = 0.3) {
      slide.addText(text, {
        shape: pres.shapes.ROUNDED_RECTANGLE, x, y, w, h, rectRadius: 0.15,
        fill: { color: KIND[kind].fill }, line: { color: KIND[kind].line, width: 1, dashType: kind === 'time' ? 'dash' : 'solid' },
        fontFace: 'Calibri', fontSize: 10.5, bold: true, color: KIND[kind].text || INK, align: 'center', valign: 'middle', margin: 0, objectName: name('tag'),
      })
      return api
    },
    // the tag in the top right corner of a block
    corner(id, kind, w, text) {
      const b = B[id]
      return api.tag(kind, b.x + b.w - w + 0.12, b.y - 0.17, w, text)
    },
    group(x, y, w, h, label) {
      slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
        x, y, w, h, rectRadius: 0.1, fill: { color: 'FFFFFF', transparency: 100 }, line: { color: 'A3AAB3', width: 1, dashType: 'dash' }, objectName: name('group'),
      })
      if (label) slide.addText(label, { x: x + 0.12, y: y + 0.04, w: w - 0.24, h: 0.26, fontSize: 10.5, italic: true, color: MUTED, fontFace: 'Calibri', margin: 0, isTextBox: true, objectName: name('group-label') })
      return api
    },
    lane(y, h, label, w = 1.15) {
      slide.addShape(pres.shapes.RECTANGLE, { x: 0.5, y, w: 12.33, h, fill: { color: 'F7F8FA' }, line: { color: 'F7F8FA', width: 0 }, objectName: name('lane') })
      slide.addText(label, { x: 0.6, y, w, h, fontSize: 13, bold: true, color: MUTED, fontFace: 'Calibri', valign: 'middle', margin: 0, isTextBox: true, objectName: name('lane-label') })
      return api
    },
    // a point on the side of a block: l, r, t, b, with an offset along the side
    P(id, side, off = 0) {
      const b = B[id]
      if (side === 'l') return [b.x, b.y + b.h / 2 + off]
      if (side === 'r') return [b.x + b.w, b.y + b.h / 2 + off]
      if (side === 't') return [b.x + b.w / 2 + off, b.y]
      return [b.x + b.w / 2 + off, b.y + b.h]
    },
    // a wire through points, an arrow at its end
    wire(points, opts = {}) {
      for (let i = 0; i < points.length - 1; i++) {
        const [x1, y1] = points[i]
        const [x2, y2] = points[i + 1]
        const line = { color: opts.color || WIRE, width: opts.width || 1.25, dashType: opts.dash ? 'dash' : 'solid' }
        if (i === points.length - 2 && opts.arrow !== false) line.endArrowType = 'triangle'
        const o = { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1), line, objectName: name('wire') }
        if (x2 < x1) o.flipH = true
        if (y2 < y1) o.flipV = true
        slide.addShape(pres.shapes.LINE, o)
      }
      return api
    },
    label(text, x, y, w, align = 'left', h = 0.26, opts = {}) {
      slide.addText(text, { x, y, w, h, fontSize: opts.size || 10.5, italic: !!opts.italic, bold: !!opts.bold, color: opts.color || MUTED, fontFace: 'Calibri', align, valign: 'middle', margin: 0, isTextBox: true, objectName: name('label') })
      return api
    },
    // a bar of a timeline: a rounded block with one short word
    bar(x, y, w, h, kind, text, size = 10.5) {
      slide.addText(text, {
        shape: pres.shapes.ROUNDED_RECTANGLE, x, y, w, h, rectRadius: 0.05,
        fill: { color: KIND[kind].fill }, line: { color: KIND[kind].line, width: 1 },
        fontFace: 'Calibri', fontSize: size, bold: true, color: INK, align: 'center', valign: 'middle', margin: 0, objectName: name('bar'),
      })
      return api
    },
    // a footnote at the bottom of the slide, above the legend
    foot(text, y = 6.62) {
      slide.addText(text, { x: 0.5, y, w: 12.33, h: 0.28, fontSize: 11, italic: true, color: MUTED, fontFace: 'Calibri', align: 'left', valign: 'middle', margin: 0, isTextBox: true, objectName: name('foot') })
      return api
    },
  }
  return api
}

function schema(section, title, sub, notes, master = 'SCHEMA') {
  const s = pres.addSlide({ masterName: master, sectionTitle: section })
  s.addText(title, { placeholder: 'title' })
  s.addText(sub, { placeholder: 'body' })
  s.addNotes(notes)
  return { s, c: canvas(s) }
}

// a card of a text slide: a frame, a title, then short lines
function card(s, x, y, w, h, kind, head, items, opts = {}) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, rectRadius: 0.1, fill: { color: KIND[kind].fill }, line: { color: KIND[kind].line, width: 1.25, dashType: kind === 'time' ? 'dash' : 'solid' }, objectName: `card-${head}` })
  s.addText(head, { x: x + 0.22, y: y + 0.14, w: w - 0.44, h: 0.5, fontSize: opts.headSize || 19, bold: true, color: INK, fontFace: 'Calibri', margin: 0, valign: 'middle', isTextBox: true, objectName: `card-head-${head}` })
  const step = opts.step || 0.58
  items.forEach((t, j) => {
    s.addText(t, { shape: pres.shapes.ROUNDED_RECTANGLE, x: x + 0.18, y: y + 0.78 + j * step, w: w - 0.36, h: step - 0.12, rectRadius: 0.06, fill: { color: 'FFFFFF' }, line: { color: KIND[kind].line, width: 0.75 }, fontSize: opts.itemSize || 14, color: INK, fontFace: 'Calibri', align: 'left', valign: 'middle', margin: [9, 8, 0, 0], objectName: `item-${head}-${j}` })
  })
}

const ICON = JSON.parse(fs.readFileSync(__dirname + '/icons.json', 'utf8'))
// a colored disc with a white icon in it
function disc(s, cx, cy, d, color, icon, name) {
  s.addShape(pres.shapes.OVAL, { x: cx - d / 2, y: cy - d / 2, w: d, h: d, fill: { color }, line: { color, width: 0 }, objectName: `disc-${name}` })
  const i = d * 0.52
  s.addImage({ data: ICON[icon], x: cx - i / 2, y: cy - i / 2, w: i, h: i, altText: name, objectName: `icon-${name}` })
}
const line = (s, x1, y1, x2, y2, opts = {}) => {
  const o = { x: Math.min(x1, x2), y: Math.min(y1, y2), w: Math.abs(x2 - x1), h: Math.abs(y2 - y1), line: { color: opts.color || WIRE, width: opts.width || 2, endArrowType: opts.arrow === false ? undefined : 'triangle', dashType: opts.dash ? 'dash' : 'solid' } }
  if (x2 < x1) o.flipH = true
  if (y2 < y1) o.flipV = true
  s.addShape(pres.shapes.LINE, o)
}
const text = (s, t, x, y, w, h, opts = {}) => s.addText(t, { x, y, w, h, fontSize: opts.size || 14, bold: !!opts.bold, italic: !!opts.italic, color: opts.color || INK, fontFace: 'Calibri', align: opts.align || 'left', valign: opts.valign || 'middle', margin: 0, isTextBox: true, objectName: opts.name })
// a block: a bold head, a lighter line under it
const block = (s, x, y, w, h, kind, head, sub, opts = {}) => {
  const runs = [{ text: head, options: { bold: true, fontSize: opts.size || 16, color: opts.color || INK, breakLine: !!sub } }]
  if (sub) runs.push({ text: sub, options: { fontSize: opts.subSize || 13, color: opts.subColor || '3E4C59' } })
  s.addText(runs, { shape: pres.shapes.ROUNDED_RECTANGLE, x, y, w, h, rectRadius: 0.08, fill: { color: opts.fill || KIND[kind].fill }, line: { color: opts.line || KIND[kind].line, width: 1.25 }, fontFace: 'Calibri', align: opts.align || 'center', valign: 'middle', margin: opts.margin === undefined ? 6 : opts.margin, objectName: opts.name })
}
// where we are in the day: /daily, /go, /fix, /fortify, the current one dark
function journey(s, current) {
  ;['/daily', '/go', '/fix', '/fortify'].forEach((t, i) => {
    const on = t === current
    s.addText(t, { shape: pres.shapes.ROUNDED_RECTANGLE, x: 9.05 + i * 0.95, y: 0.42, w: 0.88, h: 0.36, rectRadius: 0.12, fill: { color: on ? '2B3743' : 'F4F5F7' }, line: { color: on ? '2B3743' : 'D5D9DE', width: 1 }, fontSize: 12, bold: on, color: on ? 'FFFFFF' : '8A939C', fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: `journey-${t}` })
  })
}

// ================= Opening =================
pres.addSection({ title: 'Ouverture' })
{
  const s = pres.addSlide({ masterName: 'TITRE', sectionTitle: 'Ouverture' })
  s.addText('Des agents IA, du ticket à la merge request', { placeholder: 'title' })
  s.addText("L'agentique, DevX Studio, et ce que nos agents font pour l'équipe", { placeholder: 'body' })
  s.addNotes("L'histoire en une phrase : l'IA ne se contente plus de répondre, elle agit ; on a construit une équipe d'agents qui prend un ticket et rend une merge request prouvée par des tests, et le développeur garde la décision. On commence par ce qu'est un agent, on passe par DevX où ils tournent, puis on suit une journée : le matin, un ticket, la CI, la dette sécurité, et ce qui se passe quand ça coince.")
}

// ================= Introduction: agentic AI, DevX =================
pres.addSection({ title: 'Introduction' })
{
  const s = pres.addSlide({ masterName: 'TEXTE', sectionTitle: 'Introduction' })
  s.addText("L'agentique, en deux phrases", { placeholder: 'title' })
  s.addText([
    { text: 'Un assistant IA répond à vos questions ; ', options: {} },
    { text: 'un agent IA reçoit un objectif et le réalise lui-même.', options: { bold: true, breakLine: true } },
    { text: 'Il avance en boucle : il réfléchit, utilise un outil, regarde le résultat, et recommence jusqu\'à ce que ce soit fini.', options: {} },
  ], { x: 0.5, y: 1.15, w: 12.33, h: 1.4, fontSize: 21, color: INK, fontFace: 'Calibri', margin: 0, valign: 'top', paraSpaceAfter: 6, isTextBox: true, objectName: 'two-sentences' })
  // the assistant: you ask, it answers
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 0.5, y: 2.9, w: 4.75, h: 3.95, rectRadius: 0.1, fill: { color: 'F7F8FA' }, line: { color: 'C7CCD3', width: 1 }, objectName: 'assistant-panel' })
  text(s, 'Un assistant', 0.75, 3.02, 3, 0.45, { size: 20, bold: true, name: 'assistant-head' })
  disc(s, 1.2, 4.15, 0.9, '7B4F96', 'FaUser', 'dev')
  disc(s, 4.55, 4.15, 0.9, '2E6DA4', 'FaRobot', 'assistant')
  s.addText('« Pourquoi ça plante ? »', { shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.75, y: 4.95, w: 2.75, h: 0.6, rectRadius: 0.12, fill: { color: KIND.you.fill }, line: { color: KIND.you.line, width: 1 }, fontSize: 15, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'question' })
  s.addText('« Essayez plutôt ceci… »', { shape: pres.shapes.ROUNDED_RECTANGLE, x: 2.25, y: 5.8, w: 2.75, h: 0.6, rectRadius: 0.12, fill: { color: KIND.agent.fill }, line: { color: KIND.agent.line, width: 1 }, fontSize: 15, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'answer' })
  // the agent: an objective, a loop, a result
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: 5.55, y: 2.9, w: 7.28, h: 3.95, rectRadius: 0.1, fill: { color: 'F4F8FC' }, line: { color: KIND.agent.line, width: 1 }, objectName: 'agent-panel' })
  text(s, 'Un agent', 5.8, 3.02, 3, 0.45, { size: 20, bold: true, name: 'agent-head' })
  block(s, 5.85, 3.75, 1.45, 0.75, 'you', 'Objectif', null, { size: 16, name: 'goal' })
  block(s, 11.1, 3.75, 1.45, 0.75, 'ok', 'Résultat', null, { size: 16, name: 'result' })
  const B = [9.2, 4.12], T = [10.35, 5.7], E = [8.05, 5.7], D = 0.95
  disc(s, B[0], B[1], D, '2E6DA4', 'FaBrain', 'think')
  disc(s, T[0], T[1], D, '2F7D4F', 'FaTools', 'act')
  disc(s, E[0], E[1], D, 'B7791F', 'FaEye', 'look')
  line(s, 7.3, 4.12, B[0] - 0.5, B[1])
  line(s, B[0] + 0.5, B[1], 11.1, 4.12)
  line(s, B[0] + 0.3, B[1] + 0.42, T[0] - 0.25, T[1] - 0.45)
  line(s, T[0] - 0.52, T[1], E[0] + 0.52, E[1])
  line(s, E[0] + 0.25, E[1] - 0.45, B[0] - 0.3, B[1] + 0.42)
  text(s, 'réfléchit', B[0] - 0.75, 3.33, 1.5, 0.3, { size: 15, bold: true, align: 'center', name: 'think-label' })
  text(s, 'utilise un outil', T[0] - 1.2, 6.25, 2.4, 0.3, { size: 15, bold: true, align: 'center', name: 'act-label' })
  text(s, 'regarde le résultat', E[0] - 1.2, 6.25, 2.4, 0.3, { size: 15, bold: true, align: 'center', name: 'look-label' })
  s.addNotes("Deux phrases à retenir. Un assistant répond, et c'est vous qui exécutez : vous copiez, vous lancez, vous revenez avec l'erreur ; vous êtes la boucle. Un agent tient la boucle lui-même : il réfléchit, il utilise un outil (lire un fichier, lancer le build ou les tests, interroger Jira), il regarde le résultat, et il recommence jusqu'à ce que l'objectif soit atteint, ou il s'arrête en disant pourquoi. Le terme technique est ReAct : raisonner, agir, observer ; l'appel d'un outil par le modèle s'appelle le tool calling. Chaque tour de boucle est une requête au modèle.")
}

// ---------- DevX Studio ----------
{
  const { s, c } = schema('Introduction', 'DevX Studio Next Gen', 'Le poste de dev distant de chacun ; nos agents y travaillent comme un développeur.',
    "DevX Studio Next Gen est la nouvelle version de DevX Studio : elle tourne sur IBM ROKS, l'OpenShift managé d'IBM (DMZR-AS-CODE), au lieu de l'IBM Kubernetes actuel, avec de meilleures performances réseau et disque. Chaque développeur a son environnement dans un conteneur, un pod. On y accède par un bureau Linux léger affiché à distance avec XPRA, un serveur d'affichage distant persistant : la session continue quand on se déconnecte, et on la retrouve depuis Windows, un poste virtuel HVD ou un Mac. Chacun installe à la carte ses IDE et ses outils grâce à un nouveau gestionnaire de paquets ; VS Code reste installable, et Docker est là, avec Docker Compose. La version Next Gen est pensée pour le développement assisté par IA : mode agent, Continue en ligne de commande, accès aux derniers modèles, orchestration de plusieurs agents. Pour nous, c'est là que tournent nos agents : OpenCode y tourne en service, les agents travaillent dans les dépôts du pod, isolés du poste du développeur, avec exactement ses outils : ce qui compile pour l'agent compile pour lui.", 'TEXTE')
  const pts = [['FaServer', '2B3743', 'Un pod par développeur'], ['FaLinux', '2E6DA4', 'Un bureau Linux à distance'], ['FaTools', '2F7D4F', 'Outillé à la carte'], ['FaBrain', '7B4F96', "Pensé pour l'IA"]]
  pts.forEach(([icon, color, t], i) => {
    const y = 1.95 + i * 1.25
    disc(s, 0.95, y + 0.4, 0.85, color, icon, `devx-${i}`)
    text(s, t, 1.6, y, 4.6, 0.8, { size: 23, bold: true, name: `devx-point-${i}` })
  })
  c.node('pc', 7.15, 1.7, 2.3, 0.95, 'you', 'Ton poste', null, 18)
  c.group(6.35, 3.2, 3.95, 3.65, 'DevX Studio')
  c.node('desk', 6.55, 3.65, 1.7, 0.9, 'step', 'Bureau Linux', null, 16)
  c.node('ide', 8.4, 3.65, 1.7, 0.9, 'step', 'IDE, Docker', null, 16)
  c.node('ag', 6.55, 4.75, 3.55, 1.0, 'agent', 'Nos agents', 'dans les dépôts du pod', 17)
  c.node('rep', 6.55, 5.95, 3.55, 0.7, 'step', 'Les dépôts et l\'outillage', null, 15)
  c.wire([c.P('pc', 'b'), [8.3, 3.2]]).label('à distance', 8.42, 2.78, 1.3, 'left', 0.3, { size: 13 })
  c.node('llm', 10.7, 3.65, 2.13, 1.1, 'step', 'Plateforme IA', 'Qwen 3.8 · GLM 5.3', 16)
  c.node('mcp', 10.7, 5.05, 2.13, 1.1, 'step', 'itg-devops', 'Jira, GitLab, Sonar…', 16)
  c.wire([c.P('ag', 'r'), [10.45, 5.25]], { arrow: false }).wire([[10.45, 4.2], [10.45, 5.6]], { arrow: false })
  c.wire([[10.45, 4.2], c.P('llm', 'l')]).wire([[10.45, 5.6], c.P('mcp', 'l')])
}

// ================= Our work =================
pres.addSection({ title: 'Nos travaux' })
{
  const { s } = schema('Nos travaux', 'Pourquoi on l\'a fait', "Rendre du temps au développeur, sans rien lâcher sur la qualité : il décide et valide, les agents font le reste, et le prouvent.",
    "Le point de départ : beaucoup de temps part dans le répétitif (tickets simples, retours Sonar et Fortify, CI rouge, tests manquants), la dette de tests grossit, le backlog Fortify aussi. Ce qu'on vise : rendre ce temps, et une qualité constante, prouvée par des tests plutôt que promise. Le tout avec un modèle interne, plus petit que les modèles du marché : c'est pour ça que tout est cadré par des procédures et des scripts. Côté développeur, trois gestes. Il lance la commande. S'il y a des questions, elles arrivent toutes au début, en un seul QCM ; avec « sans question », les agents prennent les réponses recommandées et les notent « à valider en review ». Puis il relit la merge request en Draft comme celle d'un collègue, et il merge. Ce que les agents ne peuvent jamais faire, quelle que soit la consigne : pousser sur develop ou main, merger, écrire dans Jira ou Fortify, lire les secrets.", 'TEXTE')
  card(s, 0.5, 1.7, 5.0, 4.35, 'ok', 'Ce qu\'on vise', ['Le répétitif : tickets, Sonar, CI rouge', 'La dette de tests, le backlog Fortify', 'Une qualité prouvée, pas promise', 'Un modèle interne, bien cadré'], { step: 0.85, itemSize: 17, headSize: 21 })
  const gestures = [['1', 'Lancer', '/go ABC-123, ou sans ticket'], ['2', 'Répondre, une fois', 'un seul QCM, au début (ou « sans question »)'], ['3', 'Relire la MR', 'en Draft, comme celle d\'un collègue, puis merger']]
  text(s, 'Le développeur : 3 gestes', 5.85, 1.75, 6.9, 0.5, { size: 21, bold: true, name: 'gestures-head' })
  gestures.forEach(([n, h, d], i) => {
    const y = 2.4 + i * 1.02
    s.addText(n, { shape: pres.shapes.OVAL, x: 5.85, y, w: 0.8, h: 0.8, fill: { color: KIND.you.fill }, line: { color: KIND.you.line, width: 1.5 }, fontSize: 26, bold: true, color: KIND.you.line, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: `gesture-${n}` })
    s.addText([{ text: h, options: { bold: true, fontSize: 19, color: INK, breakLine: true } }, { text: d, options: { fontSize: 15, color: '3E4C59' } }], { x: 6.85, y: y - 0.05, w: 5.95, h: 0.9, fontFace: 'Calibri', margin: 0, valign: 'middle', isTextBox: true, objectName: `gesture-text-${n}` })
  })
  s.addText('Entre les deux : analyse, code, tests, relecture, push, MR. Tout seul.', { shape: pres.shapes.ROUNDED_RECTANGLE, x: 5.85, y: 5.45, w: 6.98, h: 0.6, rectRadius: 0.08, fill: { color: KIND.agent.fill }, line: { color: KIND.agent.line, width: 1 }, fontSize: 15, bold: true, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'between' })
  s.addText([{ text: 'Jamais : ', options: { bold: true, color: 'B23A30' } }, { text: 'push sur develop ou main · merge · écriture dans Jira ou Fortify · lecture des secrets' }], {
    shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.5, y: 6.3, w: 12.33, h: 0.55, rectRadius: 0.08, fill: { color: KIND.stop.fill }, line: { color: KIND.stop.line, width: 1.25 },
    fontSize: 15, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'never',
  })
}

// ---------- our agents ----------
{
  const { c } = schema('Nos travaux', 'Notre réponse : une équipe d\'agents', "Comme une équipe de dev : un chef d'orchestre, cinq spécialistes, et celui qui relit n'a jamais écrit.",
    "Plutôt qu'un agent qui fait tout, une équipe. Le pilote est le chef d'orchestre : il suit la procédure de la commande et confie chaque tâche à un spécialiste, sans coder lui-même. L'analyst lit le ticket, les pages Confluence et le code, et écrit la fiche du ticket : critères, plan, tests attendus. Le coder écrit le code et ses tests. Le test-guardian pose les tests qui protègent l'existant et ceux qui prouvent un bug ou une faille. Le checker relit à neuf : il n'a pas vu l'analyse ; il relit le plan avant la première ligne de code, puis le code avant le push. Le debugger cherche la cause d'un échec. Tout ce qui se mesure passe par des scripts, sans IA : git, build, tests, couverture, contrôle avant push. Le modèle, Qwen 3.8 ou GLM 5.3, est servi par la plateforme IA interne. Les agents parlent à Jira, Confluence, GitLab, SonarQube et Fortify par MCP, le protocole standard des outils d'agents, via notre serveur interne itg-devops ; chacun n'a que les droits de son métier.", 'TEXTE')
  c.node('p', 4.9, 1.7, 3.5, 1.15, 'agent', 'pilot', "le chef d'orchestre, ne code pas", 18)
  c.node('scripts', 0.5, 1.7, 3.6, 1.15, 'step', 'Scripts, sans IA', 'git, build, tests, contrôles', 16)
  c.wire([c.P('p', 'l'), c.P('scripts', 'r')], { dash: true })
  c.node('sheet', 9.2, 1.7, 3.63, 1.15, 'step', 'La fiche du ticket', 'le plan, coché étape par étape', 16)
  c.wire([c.P('p', 'r'), c.P('sheet', 'l')], { dash: true })
  const subs = [['analyst', 'ticket → fiche'], ['coder', 'le code et ses tests'], ['test-guardian', 'les tests qui protègent et prouvent'], ['checker', 'relit à neuf'], ['debugger', "la cause d'un échec"]]
  subs.forEach(([n, d], i) => c.node(`s${i}`, 0.5 + i * 2.5, 3.75, 2.33, 1.3, 'agent', n, d, 17))
  c.wire([c.P('p', 'b'), [6.65, 3.3]], { arrow: false }).wire([[1.665, 3.3], [11.665, 3.3]], { arrow: false })
  subs.forEach((_, i) => c.wire([[1.665 + i * 2.5, 3.3], c.P(`s${i}`, 't')]))
  const base = [['Le modèle', 'Qwen 3.8 ou GLM 5.3, plateforme IA interne'], ['Les outils', 'Jira, GitLab, Sonar, Fortify via itg-devops (MCP)'], ['Les droits', 'ceux du métier ; aucune écriture hors de la MR']]
  base.forEach(([h, d], i) => c.node(`b${i}`, 0.5 + i * 4.18, 5.6, 3.97, 1.15, 'note', h, d, 17))
}

// ---------- the big picture: which command, when ----------
{
  const { s, c } = schema('Nos travaux', 'Le grand schéma : quelle commande, quand', 'Une question : que veux-tu obtenir ? Une réponse, une commande. Suivons une journée.',
    "C'est la carte qui nous guide au quotidien. Une seule question : que veux-tu obtenir ? Faire le point le matin : /daily. Coder : avec un ticket Jira, /go et sa clé ; un vrai changement sans ticket, /go sans ticket suivi de la demande, le même déroulé jusqu'à la MR ; un essai, une doc, un petit correctif, la conversation, puis /push. Tester et sécuriser : des failles Fortify, /fortify ; des tests sur du code existant, /tests ; les endpoints d'une API ou un déploiement, /tests api et /tests env. Et tout ce qui est poussé finit au même endroit : la CI tourne, la review arrive, et /fix traite tous les retours en une fois, puis le cycle recommence au pipeline suivant. Les quatre flux en couleur, on les suit maintenant sur une journée : le matin, un ticket, les retours de la CI, la dette sécurité. Un ticket déjà commencé ? On relance la même commande : elle reprend à la première étape non faite.", 'TEXTE')
  const featured = (id, x, y, w, h, title, sub) => c.node(id, x, y, w, h, 'agent', title, sub, 14)
  const other = (id, x, y, w, h, title, sub) => c.node(id, x, y, w, h, 'note', title, sub, 13)
  c.dia('q', 0.4, 3.25, 1.88, 1.35, 'Que veux-tu\nobtenir ?', 11)
  const bands = [['l1', 1.78, 'Le point du matin'], ['l2', 2.98, 'Coder'], ['l3', 4.58, 'Tester, sécuriser'], ['l4', 5.88, 'Autre chose']]
  for (const [id, y, t] of bands) c.node(id, 2.55, y, 1.7, 0.55, 'step', t, null, 13)
  c.wire([c.P('q', 'r'), [2.38, 3.925]], { arrow: false }).wire([[2.38, 2.055], [2.38, 6.155]], { arrow: false })
  for (const [id, y] of bands) c.wire([[2.38, y + 0.275], c.P(id, 'l')])
  // the morning
  featured('daily', 6.55, 1.72, 3.3, 0.66, '/daily', 'sprint, MR, reviews · planifié')
  c.wire([c.P('l1', 'r'), c.P('daily', 'l')])
  // coding
  const coding = [['go', 2.5, '/go ABC-123', 'un ticket Jira', true], ['gos', 3.05, '/go sans ticket : …', 'un vrai changement, sans ticket', true], ['conv', 3.6, 'La conversation, puis /push', 'un essai, une doc, un petit correctif', false]]
  c.wire([c.P('l2', 'r'), [4.4, 3.255]], { arrow: false }).wire([[4.4, 2.725], [4.4, 3.825]], { arrow: false })
  for (const [id, y, title, cond, f] of coding) {
    ;(f ? featured : other)(id, 6.55, y, 3.3, 0.45, title, null)
    c.wire([[4.4, y + 0.225], c.P(id, 'l')]).label(cond, 4.5, y - 0.02, 2.0, 'left', 0.24, { size: 10 })
  }
  // testing and security
  const testing = [['fort', 4.15, '/fortify', 'des failles Fortify', true], ['tests', 4.7, '/tests', 'du code existant', false], ['tenv', 5.25, '/tests api · /tests env', 'une API, un déploiement', false]]
  c.wire([c.P('l3', 'r'), [4.4, 4.855]], { arrow: false }).wire([[4.4, 4.375], [4.4, 5.475]], { arrow: false })
  for (const [id, y, title, cond, f] of testing) {
    ;(f ? featured : other)(id, 6.55, y, 3.3, 0.45, title, null)
    c.wire([[4.4, y + 0.225], c.P(id, 'l')]).label(cond, 4.5, y - 0.02, 2.0, 'left', 0.24, { size: 10 })
  }
  // anything else
  other('misc', 6.55, 5.88, 3.3, 0.55, '/sync · /outil abandon', null)
  c.wire([c.P('l4', 'r'), c.P('misc', 'l')])
  // then, for everything that is pushed
  c.group(10.25, 1.65, 2.58, 4.85, 'puis, pour tout ce qui est poussé')
  c.node('push', 10.45, 2.1, 2.2, 0.8, 'step', 'Push, MR', '/go, /fortify, /push')
  c.node('ci', 10.45, 3.45, 2.2, 0.8, 'step', 'La CI, la review', 'Sonar, Fortify, discussions')
  featured('fix', 10.45, 4.8, 2.2, 0.8, '/fix', 'tous les retours, une fois')
  c.wire([c.P('push', 'b'), c.P('ci', 't')]).wire([c.P('ci', 'b'), c.P('fix', 't')])
  c.wire([c.P('fix', 'r'), [12.75, 5.2], [12.75, 3.85], c.P('ci', 'r')]).label('nouveau pipeline', 11.15, 5.72, 1.6, 'center', 0.24, { size: 10 })
  c.wire([[9.85, 2.725], [10.05, 2.725], [10.05, 2.5], c.P('push', 'l')])
}

// ================= /daily =================
pres.addSection({ title: '/daily' })
{
  const s = pres.addSlide({ masterName: 'TITRE', sectionTitle: '/daily' })
  s.addText('Une journée avec nos agents', { placeholder: 'title' })
  s.addText('8 h 45 /daily  ·  9 h /go  ·  la CI et la review : /fix  ·  la dette sécurité : /fortify', { placeholder: 'body' })
  s.addNotes("Place à l'histoire : une journée de développeur avec nos agents. Le matin, /daily fait le point. Le ticket choisi part en /go, jusqu'à la merge request. La CI et la review renvoient des retours : /fix les traite en une fois. Et la dette sécurité avance en parallèle avec /fortify. Pour chacun : ce que fait le développeur, ce que font les agents, et ce que ça change.")
}
{
  const { s, c } = schema('/daily', '/daily : le point du matin', "8 h 45 : où en est mon sprint, et qu'est-ce qui m'attend aujourd'hui ?",
    "La journée commence par /daily, lancé tout seul à l'heure choisie, ou à la main. Il lit Jira et GitLab en lecture seule : le sprint actif, mes tickets, ceux que personne n'a pris, mes merge requests et les reviews qui m'attendent, reliées à leur ticket par la clé Jira. Les listes sont complètes, avec leur total. Puis il pose un signal sur chaque ticket et chaque MR : une couleur, rouge, orange ou verte, qui dit quoi en faire, calculée à partir des données, jamais devinée. En rouge, ce qui est à traiter tout de suite : une de mes MR a un pipeline en échec ou un conflit avec sa branche cible, un de mes tickets est bloqué dans Jira (le drapeau Jira, un statut bloqué, ou un lien « est bloqué par » encore ouvert), avec ce qui le bloque. En orange, ce qui est à surveiller : une review qui m'attend depuis plus d'un jour ouvré, une discussion ouverte sur ma MR, un ticket en cours sans MR depuis trois jours, un sprint qui finit avec un de mes tickets pas commencé. En vert, ce qui est prêt : une MR approuvée, pipeline vert, sans discussion ouverte, qu'on peut merger. Le point du matin donne tout cela avec des liens et un plan du jour. À la fin, un QCM : le ticket choisi lance /go, et la journée continue.", 'TEXTE')
  journey(s, '/daily')
  const flow = [['you', 'Planifié, 8 h 45', 'ou lancé à la main'], ['agent', 'Lit Jira et GitLab', 'en lecture seule'], ['step', 'Colore chaque ligne', 'rouge, orange ou vert'], ['ok', 'Le point du matin', 'sprint, MR, reviews, liens'], ['you', 'Tu choisis un ticket', 'il lance /go']]
  flow.forEach(([k, h, d], i) => c.node(`f${i}`, 0.5 + i * 2.53, 1.7, 2.2, 0.95, k, h, d, 15))
  for (let i = 0; i < 4; i++) c.wire([c.P(`f${i}`, 'r'), c.P(`f${i + 1}`, 'l')])
  s.addText([{ text: 'Les signaux', options: { bold: true, fontSize: 20, color: INK } }, { text: '   la couleur de chaque ticket et de chaque MR, qui dit quoi en faire ; calculée à partir de Jira et GitLab, jamais devinée', options: { italic: true, fontSize: 15, color: MUTED } }], { x: 0.5, y: 3.0, w: 12.33, h: 0.45, fontFace: 'Calibri', margin: 0, valign: 'middle', isTextBox: true, objectName: 'signals-head' })
  const cols = [
    ['stop', 'B23A30', 'À traiter tout de suite', ['Ma MR : pipeline en échec', 'Ma MR : conflit avec la branche cible', 'Un de mes tickets bloqué dans Jira : drapeau, statut ou lien de blocage']],
    ['retry', 'B7791F', 'À surveiller', ["Une review m'attend depuis plus d'un jour", 'Une discussion ouverte sur ma MR', 'Un ticket en cours, sans MR ni mise à jour depuis 3 jours', 'Le sprint finit dans 3 jours, un de mes tickets pas commencé']],
    ['ok', '2F7D4F', 'Prêt', ['Ma MR est approuvée, le pipeline est vert, plus de discussion : à merger']],
  ]
  cols.forEach(([k, strong, head, items], i) => {
    const x = 0.5 + i * 4.18
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 3.6, w: 3.97, h: 3.1, rectRadius: 0.1, fill: { color: KIND[k].fill }, line: { color: KIND[k].line, width: 1.25 }, objectName: `signal-${i}` })
    s.addShape(pres.shapes.OVAL, { x: x + 0.25, y: 3.78, w: 0.32, h: 0.32, fill: { color: strong }, line: { color: strong, width: 0 }, objectName: `signal-dot-${i}` })
    text(s, head, x + 0.7, 3.68, 3.1, 0.5, { size: 18, bold: true, name: `signal-head-${i}` })
    s.addText(items.map((t, j) => ({ text: t, options: { bullet: true, breakLine: j < items.length - 1 } })), { x: x + 0.25, y: 4.35, w: 3.5, h: 2.25, fontSize: 15, color: INK, fontFace: 'Calibri', margin: 0, valign: 'top', paraSpaceAfter: 8, isTextBox: true, objectName: `signal-items-${i}` })
  })
}

// ================= /go =================
pres.addSection({ title: '/go' })
{
  const { s } = schema('/go', '/go : un ticket, une MR', '9 h : le ticket choisi part en /go. Tu lances, tu réponds une fois, tu relis ; entre les deux, tout se fait seul.',
    "C'est le flux principal, en cinq temps. Comprendre : l'analyst lit le ticket, ses pages Confluence et le code, et écrit la fiche du ticket : les critères d'acceptation, un plan de 2 à 7 étapes, les tests attendus ; en parallèle, develop est buildé et testé, pour connaître les tests déjà rouges ; puis le plan est relu par le checker, qui n'a pas vu l'analyse, avant la première ligne de code. Questions : s'il y en a, toutes en un seul QCM, au début ; avec « sans question », les agents prennent les réponses recommandées et les notent dans la MR. Coder : étape par étape, chacune avec ses tests et sa preuve, puis son commit ; c'est le zoom de la slide suivante. Vérifier : tous les tests et la relecture du checker en même temps, puis les corrections, deux tours au plus. Livrer : le contrôle avant push, un script sans IA (aucun secret, aucun conflit, aucun paquet payant), le push, et la merge request en Draft, avec ses décisions, ses tests et leur couverture. Si quelque chose bloque, develop qui ne compile pas, deux échecs sur la même étape, un secret avant le push, le run s'arrête et dit pourquoi ; relancer /go reprend là où il s'était arrêté.", 'TEXTE')
  journey(s, '/go')
  const stages = [['1 · Comprendre', "L'analyst lit le ticket et le code, écrit la fiche ; le plan est relu à neuf"], ['2 · Questions', "Un seul QCM, et seulement s'il le faut"], ['3 · Coder', "Étape par étape : tests d'abord, code, contrôle, commit"], ['4 · Vérifier', 'Tous les tests et une relecture, puis les corrections'], ['5 · Livrer', 'Contrôle avant push, push, MR en Draft avec ses preuves']]
  const colors = ['1F2933', '2B3743', '3E4C59', '4A5B78', '2F7D4F']
  stages.forEach(([t, d], i) => {
    const x = 0.5 + i * 2.455
    s.addText(t, { shape: i ? pres.shapes.CHEVRON : pres.shapes.PENTAGON, x, y: 1.75, w: 2.5, h: 1.0, fill: { color: colors[i] }, line: { color: colors[i], width: 0 }, fontFace: 'Calibri', fontSize: 17, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle', objectName: `stage-${i + 1}` })
    text(s, d, x + 0.2, 3.0, 2.1, 1.5, { size: 17, valign: 'top', name: `stage-text-${i + 1}` })
  })
  s.addText('à chaque étape, la preuve avant le code', { shape: pres.shapes.ROUNDED_RECTANGLE, x: 5.48, y: 4.85, w: 2.36, h: 0.65, rectRadius: 0.12, fill: { color: KIND.retry.fill }, line: { color: KIND.retry.line, width: 1.25 }, fontSize: 14, bold: true, color: KIND.retry.text, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'per-step' })
  const you = [[0, 'Tu lances /go ABC-123'], [1, 'Tu réponds, une fois'], [4, 'Tu relis, tu merges']]
  you.forEach(([i, t]) => s.addText(t, { shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.6 + i * 2.455, y: 4.85, w: 2.25, h: 0.65, rectRadius: 0.12, fill: { color: KIND.you.fill }, line: { color: KIND.you.line, width: 1.25 }, fontSize: 15, bold: true, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: `you-${i}` }))
  s.addText("S'il bloque (develop cassé, deux échecs sur une étape, un secret avant le push), il s'arrête et dit pourquoi ; /go relancé reprend là.", { shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.5, y: 5.95, w: 12.33, h: 0.65, rectRadius: 0.08, fill: { color: KIND.stop.fill }, line: { color: KIND.stop.line, width: 1 }, fontSize: 16, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'stop-line' })
}

// ---------- /go: inside each step, the proof ----------
{
  const { s } = schema('/go', '/go : la preuve avant le code', 'Le zoom sur « 3 · Coder » : protéger ce qui marche, prouver le problème, puis corriger. /fix et /fortify font pareil.',
    "Ce qui fait la qualité, c'est ce qui se passe dans chaque étape. Protéger : avant de toucher du code existant, le test-guardian mesure la couverture des méthodes touchées ; sous 80 % des lignes, il écrit d'abord des tests du comportement actuel, verts deux fois. Prouver : pour un bug ou une faille, un test qui le montre, rouge deux fois pour la bonne raison ; s'il passe déjà, le code résiste, et le test reste comme preuve. Verrouiller : ces tests sont gelés, le coder ne peut pas les modifier pour se faciliter la vie. Corriger : le coder fait l'étape jusqu'au vert. Contrôler : un script, sans IA, vérifie que les tests gelés sont intacts, verts deux fois, que la couverture n'a pas baissé ; alors seulement, le commit. Sinon, le test-guardian reprend, ou le coder s'il y a une régression. Un test dont le résultat change d'une exécution à l'autre est refusé : c'est un défaut, jamais relancé jusqu'à passer. Le même mécanisme sert /fix pour un bug remonté par la review, et /fortify pour chaque faille.", 'TEXTE')
  journey(s, '/go')
  const steps = [
    ['1', 'Protéger', 'Moins de 80 % des lignes touchées couvertes : des tests du comportement actuel', 'test-guardian', 'agent', '2E6DA4'],
    ['2', 'Prouver', 'Un test qui montre le bug ou la faille : rouge, deux fois', 'test-guardian', 'agent', '2E6DA4'],
    ['3', 'Verrouiller', 'Ces tests sont gelés : le coder ne peut pas les modifier', 'script', 'step', '52606D'],
    ['4', 'Corriger', "Le coder fait l'étape, jusqu'au vert", 'coder', 'agent', '2E6DA4'],
    ['5', 'Contrôler', 'Tests intacts, verts deux fois, couverture sans perte : commit', 'script, sans IA', 'ok', '2F7D4F'],
  ]
  steps.forEach(([n, h, d, who, k, strong], i) => {
    const x = 0.5 + i * 2.52
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 1.95, w: 2.25, h: 3.0, rectRadius: 0.1, fill: { color: KIND[k].fill }, line: { color: KIND[k].line, width: 1.25 }, objectName: `proof-${n}` })
    s.addText(n, { shape: pres.shapes.OVAL, x: x + 0.78, y: 1.6, w: 0.7, h: 0.7, fill: { color: strong }, line: { color: 'FFFFFF', width: 2 }, fontSize: 20, bold: true, color: 'FFFFFF', fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: `proof-num-${n}` })
    text(s, h, x + 0.15, 2.45, 1.95, 0.45, { size: 19, bold: true, align: 'center', name: `proof-head-${n}` })
    text(s, d, x + 0.18, 2.95, 1.9, 1.35, { size: 14, align: 'center', valign: 'top', name: `proof-text-${n}` })
    text(s, who, x + 0.15, 4.45, 1.95, 0.35, { size: 12, italic: true, color: MUTED, align: 'center', name: `proof-who-${n}` })
    if (i < 4) line(s, x + 2.25, 3.45, x + 2.52, 3.45)
  })
  line(s, 11.7, 4.95, 11.7, 5.35, { arrow: false })
  line(s, 11.7, 5.35, 9.1, 5.35, { arrow: false })
  line(s, 9.1, 5.35, 9.1, 4.95)
  text(s, 'pas vert : on reprend', 9.4, 5.38, 2.2, 0.3, { size: 12, italic: true, color: MUTED, align: 'center', name: 'not-green' })
  s.addText([{ text: 'Le test passe déjà, avant tout correctif ? ', options: { bold: true } }, { text: 'Le problème n\'existe pas : rien à corriger, le test reste comme preuve.', options: { breakLine: true } }, { text: 'Un test instable, vert puis rouge sans aucun changement, est refusé : jamais relancé jusqu\'à passer.' }], { shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.5, y: 5.85, w: 12.33, h: 0.9, rectRadius: 0.08, fill: { color: 'F7F8FA' }, line: { color: 'C7CCD3', width: 1 }, fontSize: 15, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'proof-note' })
}

// ================= /fix =================
pres.addSection({ title: '/fix' })

{
  const { c, s } = schema('/fix', '/fix : les retours de la CI et de la review', 'La MR est poussée, la CI tourne, la review arrive : /fix attend la fin, trie les retours, corrige tout en une fois.',
    "Premier tour : la MR, le pipeline de ce push, les projets Sonar et Fortify, en lecture ; un appel en erreur serveur ou sans réponse est rappelé une fois après 20 s. Si la CI tourne encore, /fix attend : une pause de 4 minutes, puis le statut du pipeline seul, 8 fois au plus, soit 32 minutes. Ces pauses évitent d'interroger GitLab en boucle et permettent de cliquer sur /fix juste après /go. Au-delà, /fix traite ce qui est fini, marque les jobs encore en cours et propose de le relancer ; « sans attendre » saute l'attente. Puis le tri : à corriger, à répondre, hors périmètre. Un job tombé pour une raison d'infrastructure (runner, réseau, délai) se relance dans GitLab, jamais par un correctif. Les failles et les bugs passent par la non-régression et la preuve, trois au plus par run ; les autres points par le coder, par groupes de fichiers. Puis tous les tests et la relecture, le contrôle avant push, la MR mise à jour, et les réponses aux discussions, prêtes à coller.")
  journey(s, '/fix')
  c.node('a', 0.5, 2.05, 1.2, 0.9, 'you', '/fix')
  c.node('b', 2.05, 2.05, 2.2, 0.9, 'step', 'Lit les retours', 'MR, CI, Sonar, Fortify')
  c.corner('b', 'retry', 1.55, 'erreur : 1 rappel')
  c.dia('ci', 4.65, 1.9, 1.6, 1.2, 'La CI\ntourne ?')
  c.node('p', 4.7, 3.55, 1.5, 0.75, 'step', 'Pause 4 min')
  c.node('t', 6.75, 2.05, 1.7, 0.9, 'step', 'Tri', 'corriger, répondre')
  c.node('e', 9.0, 1.55, 2.3, 0.8, 'agent', 'Failles et bugs', 'non-régression + test')
  c.node('f', 9.0, 2.55, 2.3, 0.8, 'agent', 'Autres points', 'coder, par fichiers')
  c.node('g', 9.0, 3.55, 2.3, 0.8, 'you', 'Job hors du code', 'à relancer dans GitLab')
  c.node('h', 9.0, 5.0, 2.3, 0.85, 'step', 'Tous les tests', 'et relecture')
  c.node('i', 6.4, 5.0, 2.2, 0.85, 'step', 'Contrôle avant push', 'puis le push')
  c.corner('i', 'retry', 1.55, 'réseau : 3 s, 10 s')
  c.node('j', 3.3, 5.0, 2.6, 0.85, 'ok', 'MR mise à jour', '+ réponses à coller')
  c.node('k', 0.5, 5.0, 2.3, 0.85, 'you', 'Ensuite : /fix', 'après la prochaine CI')
  c.wire([c.P('a', 'r'), c.P('b', 'l')]).wire([c.P('b', 'r'), c.P('ci', 'l')])
  c.wire([[5.15, 2.88], [5.15, 3.55]]).label('oui', 4.75, 3.08, 0.38, 'right')
  c.wire([[5.75, 3.55], [5.75, 2.88]])
  c.wire([c.P('ci', 'r'), c.P('t', 'l')]).label('finie', 6.25, 2.22, 0.5, 'center')
  c.wire([c.P('t', 'r'), [8.7, 2.5]], { arrow: false }).wire([[8.7, 1.95], [8.7, 3.95]], { arrow: false })
  c.wire([[8.7, 1.95], c.P('e', 'l')]).wire([[8.7, 2.95], c.P('f', 'l')]).wire([[8.7, 3.95], c.P('g', 'l')])
  c.wire([c.P('e', 'r'), [11.6, 1.95]], { arrow: false }).wire([c.P('f', 'r'), [11.6, 2.95]], { arrow: false })
  c.wire([[11.6, 1.95], [11.6, 5.42], c.P('h', 'r')])
  c.wire([c.P('h', 'l'), c.P('i', 'r')]).wire([c.P('i', 'l'), c.P('j', 'r')]).wire([c.P('j', 'l'), c.P('k', 'r')])
  c.label('3 max par run', 11.7, 1.6, 1.1)
}

// ================= /fortify =================
pres.addSection({ title: '/fortify' })
{
  const { s } = schema('/fortify', '/fortify : la dette sécurité, par lot', "Et la dette sécurité : jusqu'à 5 failles Fortify d'une même catégorie, corrigées et prouvées une par une, dans une seule MR.",
    "Le flux le plus attendu. Choisir : le pilote prend dans Fortify les failles Critical et High de l'application, cinq au plus, d'une même catégorie : un seul type de correctif par MR, plus facile à relire. Analyser : trois analysts en même temps, un par faille, puis les deux suivantes ; chacun écrit la carte de sa faille : est-elle exploitable, par quel chemin, quel est le plus petit correctif. Un faux positif probable n'est pas corrigé : sa carte et ses arguments vont dans la MR, pour le déclarer dans Fortify. Prouver : jusqu'à trois test-guardians en même temps, sur des fichiers qui ne se recoupent pas ; chacun pose le filet de non-régression des méthodes touchées, puis le test de la faille, rouge avant le correctif. Corriger : un par un, parce qu'un seul build tourne à la fois et pour qu'un commit ne contienne qu'une faille : le coder corrige, le contrôle automatique vérifie, puis le commit fix(security). Livrer : tous les tests et la relecture du checker, puis la MR en Draft, avec, pour chaque faille, sa gravité, son correctif, sa couverture avant et après, son test rouge puis vert. Ce que ça change : chaque correctif est prouvé par le test de sa faille, rouge avant, vert après ; rien ne casse, l'existant est testé avant d'y toucher ; un faux positif est justifié dans la MR, par son analyse ou par un test qui passe déjà, à déclarer dans Fortify ; la MR se relit commit par commit, et ce qui peut avancer en parallèle avance en parallèle. Lecture seule sur Fortify : aucun agent ne masque ni ne commente une faille.", 'TEXTE')
  journey(s, '/fortify')
  const phases = [['1 · Choisir', 0.5, 2.25, 'le pilote'], ['2 · Analyser', 2.65, 2.55, 'en parallèle, 3 à la fois'], ['3 · Prouver', 5.1, 2.55, 'en parallèle'], ['4 · Corriger', 7.55, 2.95, 'une faille à la fois'], ['5 · Livrer', 10.4, 2.43, 'à la fin']]
  const colors = ['1F2933', '2B3743', '3E4C59', '4A5B78', '2F7D4F']
  phases.forEach(([t, x, w, mode], i) => {
    s.addText(t, { shape: i ? pres.shapes.CHEVRON : pres.shapes.PENTAGON, x, y: 1.65, w, h: 0.62, fill: { color: colors[i] }, line: { color: colors[i], width: 0 }, fontFace: 'Calibri', fontSize: 16, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle', objectName: `phase-${i + 1}` })
    text(s, mode, x + 0.15, 2.32, w - 0.3, 0.3, { size: 12, italic: true, color: MUTED, align: 'center', name: `phase-mode-${i + 1}` })
  })
  // 1. choose
  block(s, 0.6, 2.75, 1.95, 1.25, 'step', '5 failles max', 'Critical, High · même catégorie', { size: 15, name: 'choose' })
  // 2. analyse and 3. prove: three at a time
  ;[[2.95, 'analyse'], [5.4, 'preuve']].forEach(([x, w]) => {
    ;[1, 2, 3].forEach((n, j) => block(s, x, 2.72 + j * 0.42, 1.95, 0.36, 'agent', `faille ${n}`, null, { size: 13, name: `${w}-${n}`, margin: 0 }))
    text(s, 'puis 4 et 5', x, 3.98, 1.95, 0.28, { size: 12, italic: true, color: MUTED, align: 'center', name: `${w}-next` })
  })
  // 4. fix: one after the other
  ;[1, 2, 3, 4, 5].forEach((n, j) => {
    block(s, 7.8 + j * 0.5, 2.72 + j * 0.27, 0.46, 0.34, 'agent', String(n), null, { size: 13, name: `fix-${n}`, margin: 0 })
  })
  // 5. deliver
  block(s, 10.55, 2.75, 2.15, 1.25, 'ok', 'MR en Draft', 'tous les tests + relecture', { size: 15, name: 'deliver' })
  const captions = [[0.5, 2.25, 'une catégorie, un seul type de correctif'], [2.65, 2.55, 'chaque faille : exploitable, ou faux positif ?'], [5.1, 2.55, "tests de l'existant, puis un test qui montre la faille : rouge"], [7.55, 2.95, 'le correctif, le test passe au vert, un commit'], [10.4, 2.43, 'un commit par faille, ses preuves dans la MR']]
  captions.forEach(([x, w, t], i) => text(s, t, x + 0.15, 4.35, w - 0.3, 0.8, { size: 13, align: 'center', valign: 'top', name: `phase-caption-${i + 1}` }))
  const gains = [['Correctif prouvé', 'le test de la faille : rouge avant, vert après'], ['Rien ne casse', "l'existant testé avant d'y toucher"], ['Faux positifs justifiés', 'la preuve dans la MR, à déclarer dans Fortify'], ['Facile à relire', 'un commit par faille'], ['Plus rapide', 'analyses et preuves en parallèle']]
  text(s, 'Ce que ça change', 0.5, 5.2, 6, 0.4, { size: 18, bold: true, name: 'gains-head' })
  gains.forEach(([h, d], i) => block(s, 0.5 + i * 2.497, 5.65, 2.35, 1.15, 'ok', h, d, { size: 16, subSize: 13, name: `gain-${i}` }))
}

// ================= when it gets stuck =================
pres.addSection({ title: 'Garde-fous' })
{
  const { s } = schema('Garde-fous', 'Et quand ça coince ?', "Ça repart tout seul, ou ça s'arrête en disant pourquoi ; et ça reprend là où ça en était.",
    "Quatre mécanismes. Ce qui repart tout seul : une coupure réseau pendant un fetch ou un push (un essai après 3 secondes, puis 10), un Artifactory ou un registre npm qui redémarre, un appel Jira ou GitLab en erreur serveur, le serveur du modèle qui tombe quelques minutes (10 essais étalés sur environ 8 minutes) ; un « trop de requêtes » attend le délai que le serveur demande. Ce qui est borné : rien n'attend sans limite ; build et tests 42 minutes, un test 5 minutes, un appel à Jira ou GitLab 5 minutes. La mémoire : le contexte, c'est tout ce que le modèle relit à chaque tour (la consigne, les échanges, les sorties des outils), et sa taille est limitée ; chaque sous-agent démarre avec une mémoire vide et sa seule tâche ; dans un long run, les plus anciennes sorties d'outils (un fichier lu, un build) sont effacées avant que le contexte ne déborde, jamais les rapports des agents ; une réponse qui boucle est coupée, chaque agent a un nombre d'étapes borné. La reprise : la fiche du ticket coche chaque étape, chaque étape a son commit ; un run coupé avant la fin est repris tout seul, deux fois au plus ; après un redémarrage, le service reprend le run ; relancer /go reprend à la première étape non faite. Ce qui n'est jamais relancé : ce qui échouerait pareil, un test rouge, un test instable, une compilation cassée ; un message dit alors quoi régler.", 'TEXTE')
  const cols = [
    ['retry', 'Relancé tout seul', ['Une coupure réseau', 'Artifactory, npm qui redémarre', 'Le modèle, indisponible un moment']],
    ['time', 'Borné dans le temps', ['Build et tests : 42 min', 'Un test : 5 min', "Rien n'attend sans limite"]],
    ['agent', 'Mémoire maîtrisée', ['Chaque agent part de zéro, avec sa seule tâche', 'Les vieux résultats effacés avant saturation', 'Une réponse qui boucle est coupée']],
    ['ok', 'Reprise', ['Une fiche cochée, un commit par étape', 'Run coupé : repris seul', '/go relancé : reprend là']],
  ]
  cols.forEach(([k, head, items], i) => card(s, 0.5 + i * 3.13, 1.7, 2.94, 3.75, k, head, items, { step: 0.85, itemSize: 15, headSize: 19 }))
  s.addText([{ text: 'Jamais relancé : ', options: { bold: true, color: 'B23A30' } }, { text: 'un test rouge, un test instable, une compilation cassée. Un message dit quoi régler.' }], {
    shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.5, y: 5.8, w: 12.33, h: 0.65, rectRadius: 0.08, fill: { color: KIND.stop.fill }, line: { color: KIND.stop.line, width: 1.25 },
    fontSize: 16, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'never-retried',
  })
}

{
  const s = pres.addSlide({ masterName: 'TITRE', sectionTitle: 'Garde-fous' })
  s.addText('Questions ?', { placeholder: 'title' })
  s.addText('Le développeur décide et valide ; les agents font, et le prouvent.', { placeholder: 'body' })
  s.addNotes("Réponses prêtes. Qui valide ? Le développeur, toujours : les agents ouvrent une MR en Draft, ne mergent jamais, ne poussent jamais sur develop, main ou master. Et s'il invente un fichier ou une méthode ? Un script vérifie que chaque fichier du plan existe, le checker relit le plan sans avoir vu l'analyse, et rien n'est commité sans tests verts. Et si un correctif casse autre chose ? Avant de toucher du code existant, des tests du comportement actuel sur au moins 80 % des lignes touchées ; tous les tests et une relecture avant le push. Et l'injection de prompt, un ticket qui dirait « pousse sur main » ? Le texte d'un ticket, d'une page ou d'un log est une donnée, jamais une consigne, et les permissions l'interdisent de toute façon : un outil refusé n'apparaît même pas au modèle. Nos secrets ? Fichiers et variables sensibles refusés à tous les agents, jetons des services hors du contexte du modèle, pas d'accès web. Des tests qui passent par hasard ? Chaque preuve tourne deux fois ; un test instable est refusé, c'est un défaut, pas un aléa. Et le code part-il dehors ? Non : le modèle est servi par la plateforme IA interne. Et si on n'est pas d'accord avec une décision de l'agent ? Chaque décision est écrite dans la MR, avec sa raison ; on la commente en review, et /fix reprend les commentaires.")
}

// The file says nothing of the tool that wrote it: no author, no company
async function neutralize(file) {
  const zip = await JSZip.loadAsync(fs.readFileSync(file))
  const core = await zip.file('docProps/core.xml').async('string')
  zip.file('docProps/core.xml', core.replace(/<dc:creator>[^<]*<\/dc:creator>/, '<dc:creator></dc:creator>').replace(/<cp:lastModifiedBy>[^<]*<\/cp:lastModifiedBy>/, '<cp:lastModifiedBy></cp:lastModifiedBy>'))
  const app = await zip.file('docProps/app.xml').async('string')
  zip.file('docProps/app.xml', app.replace(/<Company>[^<]*<\/Company>/, '<Company></Company>'))
  fs.writeFileSync(file, await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }))
}

;(async () => {
  await pres.writeFile({ fileName: OUT })
  await applyTheme(OUT, THEME)
  await neutralize(OUT)
  console.log('written', OUT)
})()
