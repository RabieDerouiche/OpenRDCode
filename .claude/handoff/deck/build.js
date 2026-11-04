// The deck of the flows: native PowerPoint shapes only (rounded rectangles, diamonds, lines), short labels,
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
pres.title = 'Du ticket à la merge request'
pres.subject = '/fortify, /go, /fix, /tests, sans ticket'
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
pres.defineSlideMaster({ title: 'SCHEMA', background: { color: 'FFFFFF' }, slideNumber: pageNumber(), objects: [...header(), ...legend] })
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

// ================= Section 1: the principle =================
pres.addSection({ title: 'Le principe' })

// ---------- title ----------
{
  const s = pres.addSlide({ masterName: 'TITRE', sectionTitle: 'Le principe' })
  s.addText('Du ticket à la merge request', { placeholder: 'title' })
  s.addText('Les flux des agents OpenCode : /fortify, /go, /fix, /tests, le travail sans ticket, et ce qui se passe quand ça coince', { placeholder: 'body' })
  const chips = [['/fortify', 1.6], ['/go', 1.2], ['/fix', 1.2], ['/tests', 1.4], ['sans ticket', 1.9]]
  let x = 0.8
  for (const [t, w] of chips) {
    s.addText(t, {
      shape: pres.shapes.ROUNDED_RECTANGLE, x, y: 5.3, w, h: 0.55, rectRadius: 0.1,
      fill: { color: t === '/fortify' ? '7A2E27' : '2B3743' }, line: { color: t === '/fortify' ? 'B23A30' : '52606D', width: 1 }, fontFace: 'Calibri', fontSize: 16, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle', objectName: `chip-${t}`,
    })
    x += w + 0.25
  }
  s.addText('OpenCode v2 · Qwen 3.8 · octobre 2026', { x: 0.8, y: 6.55, w: 8, h: 0.4, fontSize: 13, color: '9AA5B1', fontFace: 'Calibri', margin: 0, isTextBox: true, objectName: 'date' })
  s.addNotes("Les agents prennent un ticket Jira, ou une demande sans ticket, et rendent une merge request en Draft, avec ses tests et ses preuves. On commence par le principe commun à tous les flux, puis /fortify, le flux le plus important pour nous : un lot de failles Fortify corrigées et prouvées dans une seule MR. Ensuite /go, le travail sans ticket, /fix après la CI, /tests, et ce qui se passe quand quelque chose coince.")
}

// ---------- who does what ----------
{
  const { s } = schema('Le principe', 'Qui fait quoi', 'Les agents écrivent et décident ; des scripts mesurent et contrôlent ; le développeur valide.',
    "Trois acteurs. Le développeur lance une commande, répond aux questions éventuelles du début, toutes en un seul QCM, puis relit la MR en Draft comme celle d'un collègue : c'est lui qui merge. Les agents IA tournent sur le modèle Qwen 3.8 de la plateforme : un pilote qui suit la procédure de la commande, et des agents spécialisés, chacun avec ses droits. L'analyst lit le ticket, Confluence et le code et écrit la fiche du ticket ; le coder écrit le code et ses tests ; le test-guardian écrit les tests de non-régression et les tests qui prouvent un bug ou une faille ; le checker relit la branche ; le debugger cherche la cause d'un échec. Tout ce qui se mesure passe par des scripts, sans IA : le build et les tests, la couverture, les contrôles après un correctif, le contrôle avant push (secrets, conflits, paquets payants), les commandes git. Ce que le modèle ne peut jamais faire, quelle que soit la consigne : pousser sur develop ou main, merger, écrire dans Jira ou Fortify, lire les secrets du poste.", 'TEXTE')
  card(s, 0.5, 1.65, 3.7, 4.3, 'you', 'Le développeur', ['Lance une commande', 'Répond au QCM du début', 'Relit la MR en Draft', 'Merge, comme d\'habitude'])
  card(s, 4.45, 1.65, 4.35, 4.3, 'agent', 'Les agents IA', ['pilot : suit la procédure', 'analyst : ticket → fiche', 'coder : code et ses tests', 'test-guardian : tests, preuves', 'checker : relecture', 'debugger : cause d\'un échec'], { step: 0.58, itemSize: 14 })
  card(s, 9.05, 1.65, 3.78, 4.3, 'step', 'Les scripts, sans IA', ['Build et tests', 'Couverture, contrôles', 'Contrôle avant push', 'Branche, commit, push', 'Bornes de temps, relances'])
  s.addText([{ text: '⛔  Jamais : ', options: { bold: true, color: 'B23A30' } }, { text: 'push sur develop ou main · merge · écriture dans Jira ou Fortify · lecture des secrets' }], {
    shape: pres.shapes.ROUNDED_RECTANGLE, x: 0.5, y: 6.2, w: 12.33, h: 0.6, rectRadius: 0.08, fill: { color: KIND.stop.fill }, line: { color: KIND.stop.line, width: 1.25 },
    fontSize: 16, color: INK, fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: 'never',
  })
}

// ---------- non-regression and proof ----------
{
  const { c } = schema('Le principe', 'Non-régression et preuve', 'Avant de corriger : protéger l\'existant, puis reproduire le problème. Après : un contrôle automatique.',
    "C'est le même mécanisme dans /fortify, /go et /fix, pour une faille, un bug ou une modification de code existant. Avant le correctif, le test-guardian mesure la couverture des méthodes que le correctif va toucher, et de celles qui y mènent. Sous 80 % des lignes, il écrit d'abord les tests de non-régression qui manquent : ils décrivent le comportement actuel, verts deux fois. Puis le test du problème : l'entrée hostile ou le cas du bug, rouge deux fois pour la bonne raison. S'il passe déjà, le code résiste : le test reste, comme preuve. Un test dont le résultat change d'une exécution à l'autre est refusé : un test instable est un défaut, jamais relancé jusqu'à passer. Tous ces tests sont verrouillés : le coder ne peut pas les modifier. Après le correctif, un script contrôle tout, sans IA : tests verrouillés intacts, verts deux fois, non-régression gardée, couverture sans perte. Tout vert : commit. Sinon le test-guardian reprend dans sa session ; une régression renvoie au coder.")
  c.group(0.5, 1.65, 5.85, 4.85, 'avant le correctif · test-guardian')
  c.group(6.75, 1.65, 6.08, 4.85, 'après le correctif')
  c.node('a', 0.8, 2.0, 2.5, 0.85, 'agent', 'Couverture mesurée', 'méthodes touchées')
  c.dia('b', 1.25, 3.05, 1.6, 1.0, '≥ 80 % ?')
  c.node('c', 3.6, 3.1, 2.5, 0.9, 'agent', 'Non-régression', 'tests ajoutés, verts ×2')
  c.node('d', 0.8, 4.4, 2.5, 0.9, 'agent', 'Test du problème', 'rouge deux fois ?')
  c.node('e', 3.6, 4.4, 2.5, 0.9, 'step', 'Tests verrouillés', 'le coder n\'y touche pas')
  c.node('r1', 0.7, 5.72, 2.3, 0.65, 'ok', 'Le code résiste', 'test gardé en preuve')
  c.node('r2', 3.3, 5.72, 2.3, 0.65, 'stop', 'Test instable', 'refusé')
  c.wire([c.P('a', 'b'), c.P('b', 't')])
  c.wire([c.P('b', 'r'), c.P('c', 'l')]).label('non', 2.95, 3.28, 0.5)
  c.wire([c.P('b', 'b'), [2.05, 4.4]]).label('oui', 2.12, 4.12, 0.5)
  c.wire([c.P('c', 'b'), [4.85, 4.2], [2.75, 4.2], [2.75, 4.4]])
  c.wire([c.P('d', 'r'), c.P('e', 'l')])
  c.wire([c.P('d', 'b'), [2.05, 5.52]], { arrow: false }).wire([[1.85, 5.52], [4.45, 5.52]], { arrow: false })
  c.wire([[1.85, 5.52], c.P('r1', 't')]).wire([[4.45, 5.52], c.P('r2', 't')])
  c.label('passe déjà', 0.62, 5.36, 1.1).label('instable', 4.55, 5.36, 1.0)
  c.node('f', 7.05, 4.4, 2.0, 0.9, 'agent', 'coder', 'corrige, tests intacts')
  c.dia('g', 9.35, 4.3, 1.6, 1.1, 'Contrôle\nauto')
  c.node('h', 11.25, 4.4, 1.45, 0.9, 'ok', 'Commit')
  c.node('i', 9.05, 2.45, 2.2, 0.9, 'agent', 'test-guardian', 'même session')
  c.wire([c.P('e', 'r'), c.P('f', 'l')])
  c.wire([c.P('f', 'r'), c.P('g', 'l')]).wire([c.P('g', 'r'), c.P('h', 'l')]).label('OK', 10.95, 4.58, 0.3, 'center')
  c.wire([c.P('g', 't'), c.P('i', 'b')]).label('pas vert', 10.25, 3.75, 0.9)
  c.wire([c.P('i', 'r'), [11.975, 2.9], c.P('h', 't')]).label('vert', 12.05, 3.6, 0.5)
  c.wire([c.P('i', 'l'), [8.05, 2.9], c.P('f', 't')], { dash: true }).label('régression', 7.05, 2.62, 0.95)
  c.tag('note', 6.95, 5.75, 5.7, 'le script vérifie : verrouillés intacts · verts ×2 · couverture sans perte', 0.42)
}

// ---------- a typical day ----------
{
  const { c } = schema('Le principe', 'Une journée type', 'Deux moments pour le développeur : les questions du début et la relecture de la MR.',
    "Le matin, /daily est lancé tout seul à l'heure choisie et donne le point : sprint, reviews, MR et pipelines. Le développeur lance /go sur son ticket. S'il y a des questions (un ticket ambigu, pas de projet de tests), elles arrivent toutes au début, en un seul QCM, puis il peut partir. Les agents analysent, codent étape par étape, prouvent, se relisent et poussent une MR en Draft. Un clic sur /fix dans les choix proposés à la fin : /fix attend la fin de la CI, corrige ce que Sonar, Fortify ou les jobs remontent, et met la MR à jour. Pourquoi 32 minutes : /fix regarde le statut du pipeline toutes les 4 minutes, 8 fois au plus ; ces pauses évitent d'interroger GitLab en boucle et laissent le développeur cliquer sur /fix tout de suite après /go. Si la CI tourne encore au bout de 32 minutes, /fix traite ce qui est fini et propose de le relancer ; la consigne « sans attendre » saute cette attente. Le développeur relit ensuite la MR comme celle d'un collègue ; après des commentaires, /fix à nouveau, qui prépare aussi les réponses à coller.")
  c.lane(1.55, 1.4, 'Développeur', 1.3).lane(3.03, 1.7, 'Agents').lane(4.81, 1.38, 'GitLab, CI')
  const X = (i) => 1.95 + i * 1.53
  const W = 1.4
  c.node('p1', X(0), 3.4, W, 0.95, 'step', '/daily', '08:45, planifié')
  c.node('t1', X(0), 1.78, W, 0.95, 'you', 'Point du matin', 'sprint, MR, CI')
  c.node('t2', X(1), 1.78, W, 0.95, 'you', '/go ABC-123')
  c.node('p2', X(1), 3.4, W, 0.95, 'step', '❓ Questions', 'toutes au début')
  c.node('t3', X(2), 1.78, W, 0.95, 'you', 'Un clic', 'par réponse')
  c.node('p3', X(3), 3.4, W, 0.95, 'agent', 'Analyse, code', 'preuves, relecture')
  c.node('g1', X(3), 5.0, W, 0.95, 'ok', '🚀 MR en Draft')
  c.node('t4', X(4), 1.78, W, 0.95, 'you', '/fix', 'un clic')
  c.node('p4', X(5), 3.4, W, 0.95, 'agent', 'Attend la CI', 'puis corrige')
  c.node('g2', X(5), 5.0, W, 0.95, 'ok', '🔁 MR à jour')
  c.node('t5', X(6), 1.78, W, 0.95, 'you', 'Relecture', 'puis /fix si besoin')
  c.wire([c.P('p1', 't'), c.P('t1', 'b')])
  c.wire([c.P('t1', 'r'), c.P('t2', 'l')])
  c.wire([c.P('t2', 'b'), c.P('p2', 't')])
  const elbow = (from, to, y) => {
    const a = c.P(from, 'r')
    c.wire([a, [a[0] + 0.065, a[1]], [a[0] + 0.065, y], c.P(to, 'l')])
  }
  elbow('p2', 't3', 2.255)
  elbow('t3', 'p3', 3.875)
  c.wire([c.P('p3', 'b'), c.P('g1', 't')])
  elbow('g1', 't4', 2.255)
  elbow('t4', 'p4', 3.875)
  c.wire([c.P('p4', 'b'), c.P('g2', 't')])
  elbow('g2', 't5', 2.255)
  c.corner('p4', 'time', 1.3, '≤ 32 min *')
  c.foot('* /fix attend la fin du pipeline : un coup d\'œil toutes les 4 min, 8 au plus. Au-delà, il traite ce qui est fini et propose de le relancer.', 6.3)
  c.foot('À tout moment : /tests, /push, /sync, /outil vitesse.', 6.6)
}

// ================= Section 2: /fortify =================
pres.addSection({ title: '/fortify' })

// ---------- /fortify: the batch in time ----------
{
  const { c, s } = schema('/fortify', '/fortify · un lot de failles, une MR', 'Ce qui peut avancer ensemble avance ensemble ; les correctifs passent un par un, chacun prouvé.',
    "Voici un lot de 5 failles dans le temps, de gauche à droite. Chaque barre est un agent ou un script au travail. Sélection : le pilote prend dans Fortify les failles Critical et High de l'application du dépôt, 5 au plus, la même catégorie d'abord : un seul type de correctif par MR. Analyse : trois analysts en même temps, un par faille, chacun écrit la carte de sa faille ; pendant ce temps, develop est buildé et testé, pour savoir quels tests étaient déjà rouges avant le lot. Puis les deux dernières analyses. Preuves : jusqu'à trois test-guardians en même temps, sur des fichiers qui ne se recoupent pas ; chacun pose les tests de non-régression et le test rouge de sa faille. Correctifs : un par un, parce qu'un seul build tourne à la fois dans le dossier, et pour que chaque commit ne contienne qu'un correctif et ses tests. Après chaque correctif, le contrôle automatique, puis le commit. Puis la vague suivante. À la fin, tous les tests et la relecture du checker en même temps, puis la MR en Draft. Le développeur n'intervient qu'au début, si le dépôt n'a pas de projet de tests unitaires, et à la relecture. Une faille dans du code front-end n'entre pas dans le lot : sa preuve serait un test front, et la MR propose /go sans ticket pour elle.")
  const T0 = 2.4
  const rows = [
    ['Pilote', 2.1, 0.42], ['Analyse\nanalyst', 2.6, 0.92], ['Build\nde develop', 3.6, 0.42], ['Preuves\ntest-guardian', 4.1, 0.92],
    ['Correctif\ncoder', 5.1, 0.42], ['Contrôle auto\nscript', 5.6, 0.42], ['Relecture\nchecker', 6.1, 0.42],
  ]
  rows.forEach(([label, y, h], i) => {
    if (i % 2 === 0) s.addShape(pres.shapes.RECTANGLE, { x: 0.5, y: y - 0.04, w: 12.33, h: h + 0.08, fill: { color: 'F7F8FA' }, line: { color: 'F7F8FA', width: 0 }, objectName: `row-${i}` })
    c.label(label, 0.6, y, 1.75, 'left', h, { size: 11, bold: true, color: MUTED })
  })
  const phases = [['Sélection', T0, 3.15], ['Analyse', 3.2, 5.0], ['Preuves V1-V3', 5.05, 6.35], ['Correctifs V1-V3', 6.4, 8.8], ['Preuves V4-V5', 8.85, 9.95], ['Correctifs V4-V5', 10.0, 11.6], ['Fin', 11.65, 12.83]]
  phases.forEach(([t, x1, x2], i) => {
    s.addText(t, { shape: pres.shapes.ROUNDED_RECTANGLE, x: x1, y: 1.58, w: x2 - x1, h: 0.36, rectRadius: 0.06, fill: { color: i % 2 ? '3E4C59' : '1F2933' }, line: { color: '1F2933', width: 0 }, fontSize: 11, bold: true, color: 'FFFFFF', fontFace: 'Calibri', align: 'center', valign: 'middle', margin: 0, objectName: `phase-${i}` })
    if (i) c.wire([[x1 - 0.025, 2.02], [x1 - 0.025, 6.56]], { arrow: false, dash: true, color: 'C7CCD3', width: 0.75 })
  })
  // the pilot
  c.bar(T0 + 0.05, 2.12, 0.7, 0.38, 'step', '5 failles')
  c.bar(12.15, 2.12, 0.66, 0.38, 'ok', 'MR')
  // the analyses: three at once, then two
  ;['V1', 'V2', 'V3'].forEach((v, i) => c.bar(3.25, 2.62 + i * 0.3, 1.1, 0.26, 'agent', v, 10))
  ;['V4', 'V5'].forEach((v, i) => c.bar(4.4, 2.62 + i * 0.3, 0.58, 0.26, 'agent', v, 10))
  c.bar(3.25, 3.62, 1.73, 0.38, 'step', 'build + tests')
  // the proofs: a wave of three, then two
  ;['V1', 'V2', 'V3'].forEach((v, i) => c.bar(5.1, 4.12 + i * 0.3, 1.2, 0.26, 'agent', v, 10))
  ;['V4', 'V5'].forEach((v, i) => c.bar(8.9, 4.12 + i * 0.3, 1.0, 0.26, 'agent', v, 10))
  // the fixes, one at a time, each followed by its check
  const fixes = [['V1', 6.45], ['V2', 7.25], ['V3', 8.05], ['V4', 10.05], ['V5', 10.85]]
  for (const [v, x] of fixes) {
    c.bar(x, 5.12, 0.5, 0.38, 'agent', v, 10)
    c.bar(x + 0.5, 5.62, 0.25, 0.38, 'ok', '✓', 10)
    c.wire([[x + 0.5, 5.31], [x + 0.625, 5.31], [x + 0.625, 5.62]], { width: 1 })
  }
  c.bar(11.7, 3.62, 0.62, 0.38, 'step', 'tests')
  c.label('3 analyses en même temps, puis 2', 5.15, 2.9, 3.0, 'left', 0.3, { italic: true })
  c.label('3 preuves en même temps, puis 2', 6.5, 4.4, 2.3, 'left', 0.3, { italic: true })
  c.bar(11.7, 6.12, 0.62, 0.38, 'agent', 'relit', 10)
  c.foot('En même temps : les analyses, le build de develop, les preuves.   Un par un : les correctifs, chacun contrôlé (✓) et commité seul.', 6.62)
}

// ---------- /fortify: one vulnerability ----------
{
  const { c } = schema('/fortify', '/fortify · une faille, de la carte au commit', 'Chaque faille finit de trois façons, toutes prouvées : corrigée, non exploitable, ou mise de côté.',
    "Pour chaque faille, l'analyst écrit une carte : ce qui est exploitable et par quel chemin, son verdict, le plus petit correctif, le module autour et les méthodes à protéger. Un faux positif probable n'est pas corrigé : la carte et ses arguments vont dans la MR, et c'est le développeur qui le déclare dans Fortify SSC, jamais l'agent. Sinon, le test-guardian pose les tests de non-régression des méthodes touchées, puis le test de la faille. Rouge : la faille est démontrée ; les tests sont verrouillés, le coder fait le plus petit correctif sans y toucher, le contrôle automatique vérifie, et c'est un commit fix(security), un par faille. Vert d'emblée : le code résiste déjà à l'entrée hostile ; le test est gardé comme preuve, dans un commit test(security). Quand aucun test unitaire ne peut montrer la faille (une configuration, un réglage du framework), le correctif passe sous la seule non-régression, et la MR le dit. Un correctif qui échoue deux fois est mis de côté dans git stash, récupérable, et le lot continue : une faille ne bloque jamais les autres.")
  c.node('a', 0.5, 2.05, 1.55, 0.9, 'step', 'Faille Fortify', 'Critical, High')
  c.node('b', 2.4, 2.05, 1.95, 0.9, 'agent', 'analyst', 'carte de la faille')
  c.dia('c', 4.7, 1.92, 1.6, 1.15, 'Verdict ?')
  c.node('d', 7.05, 2.05, 2.2, 0.9, 'agent', 'test-guardian', 'non-régression + test')
  c.dia('e', 9.55, 1.92, 1.5, 1.15, 'Le test\nde la faille')
  c.node('f', 11.4, 2.05, 1.43, 0.9, 'ok', 'test(security)', 'non exploitable')
  c.node('g', 4.35, 3.55, 2.3, 0.85, 'you', 'À déclarer dans SSC', 'par toi, carte à l\'appui')
  c.node('h', 9.45, 3.55, 1.7, 0.85, 'step', 'Tests verrouillés')
  c.node('i', 9.45, 4.95, 1.7, 0.85, 'agent', 'coder', 'plus petit correctif')
  c.dia('j', 6.85, 4.82, 1.6, 1.1, 'Contrôle\nauto')
  c.node('k', 4.35, 4.95, 2.3, 0.85, 'ok', 'fix(security)', 'un commit par faille')
  c.node('l', 6.8, 6.12, 1.7, 0.62, 'stop', 'Mise de côté', 'récupérable', 12)
  c.wire([c.P('a', 'r'), c.P('b', 'l')]).wire([c.P('b', 'r'), c.P('c', 'l')])
  c.wire([c.P('c', 'r'), c.P('d', 'l')]).label('vraie faille', 6.2, 2.2, 0.85, 'center')
  c.wire([c.P('c', 'b'), c.P('g', 't')]).label('faux positif', 5.6, 3.15, 1.1)
  c.wire([c.P('d', 'r'), c.P('e', 'l')])
  c.wire([c.P('e', 'r'), c.P('f', 'l')]).label('vert', 11.05, 2.2, 0.35, 'center')
  c.wire([c.P('e', 'b'), c.P('h', 't')]).label('rouge', 10.4, 3.15, 0.6)
  c.wire([c.P('h', 'b'), c.P('i', 't')])
  c.wire([c.P('i', 'l'), c.P('j', 'r')])
  c.wire([c.P('j', 'l'), c.P('k', 'r')]).label('OK', 6.68, 5.13, 0.3, 'center')
  c.wire([c.P('j', 'b'), c.P('l', 't')]).label('échec ×2', 7.8, 5.9, 0.9, 'left', 0.22)
  c.group(0.5, 3.4, 3.5, 3.35, 'dans la MR, pour chaque faille')
  ;['gravité, fichier, correctif', 'couverture avant → après', 'test : rouge avant, vert après', 'son commit', 'ce qui reste à faire, et pourquoi'].forEach((t, i) => c.tag('note', 0.7, 3.8 + i * 0.55, 3.1, t, 0.42))
}

// ---------- /fortify: what it changes ----------
{
  const { s } = schema('/fortify', '/fortify · ce que ça change', 'Une faille corrigée sans preuve est une faille dont on espère qu\'elle est corrigée.',
    "Six choses concrètes. Prouvée : chaque faille corrigée a un test qui la reproduit, rouge avant le correctif et vert après, deux fois chacun ; le scan Fortify de la CI confirme ensuite. Sans régression : avant de toucher au code, au moins 80 % des lignes des méthodes touchées sont couvertes par des tests du comportement actuel ; après, la couverture ne baisse jamais. Argumentée : un faux positif ou un code qui résiste déjà est montré par la carte ou par un test, et c'est toi qui le déclares dans SSC. Relisible : cinq failles au plus, de la même catégorie, un commit par faille, un tableau par faille dans la MR ; on peut revenir sur une faille sans toucher aux autres. Plus rapide : les analyses, le build de develop et les preuves avancent en même temps ; le développeur lance une commande et relit une MR. Robuste : une faille qui échoue est mise de côté, récupérable, et le lot continue ; un run interrompu reprend où il s'était arrêté, depuis les cartes. Et toujours en lecture seule sur Fortify : aucune faille n'est masquée ou commentée par un agent.", 'TEXTE')
  const items = [
    ['Prouvée', 'Un test par faille : rouge avant, vert après, deux fois.', 'ok'],
    ['Sans régression', '≥ 80 % des lignes touchées couvertes avant de corriger.', 'agent'],
    ['Argumentée', 'Faux positif ou code qui résiste : la preuve est dans la MR.', 'you'],
    ['Relisible', '5 failles max, même catégorie, un commit par faille.', 'step'],
    ['Plus rapide', 'Analyses et preuves en parallèle ; une commande, une relecture.', 'time'],
    ['Robuste', 'Une faille qui échoue ne bloque pas le lot ; reprise là où ça s\'est arrêté.', 'retry'],
  ]
  items.forEach(([head, line, kind], i) => {
    const x = 0.5 + (i % 3) * 4.18
    const y = 1.7 + Math.floor(i / 3) * 2.45
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 3.97, h: 2.2, rectRadius: 0.1, fill: { color: KIND[kind].fill }, line: { color: KIND[kind].line, width: 1.25, dashType: kind === 'time' ? 'dash' : 'solid' }, objectName: `benefit-${i}` })
    s.addText(head, { x: x + 0.25, y: y + 0.2, w: 3.5, h: 0.6, fontSize: 24, bold: true, color: INK, fontFace: 'Calibri', margin: 0, valign: 'middle', isTextBox: true, objectName: `benefit-head-${i}` })
    s.addText(line, { x: x + 0.25, y: y + 0.9, w: 3.5, h: 1.1, fontSize: 18, color: '3E4C59', fontFace: 'Calibri', margin: 0, valign: 'top', isTextBox: true, objectName: `benefit-line-${i}` })
  })
  s.addText('Lecture seule sur Fortify : aucune faille masquée ou commentée par un agent.', { x: 0.5, y: 6.62, w: 12.33, h: 0.3, fontSize: 13, italic: true, color: MUTED, fontFace: 'Calibri', align: 'center', margin: 0, isTextBox: true, objectName: 'readonly' })
}

// ================= Section 3: /go =================
pres.addSection({ title: '/go' })

// ---------- /go at a glance ----------
{
  const { c, s } = schema('/go', '/go en un coup d\'œil', 'Un ticket entre, une MR en Draft sort. Trois temps, chacun avec ses arrêts.',
    "Trois temps. Préparer : la branche, l'analyse du ticket en une fiche, et en parallèle le build et les tests de develop : develop doit compiler, et ses tests déjà rouges sont notés pour ne jamais être mis sur le dos du ticket ; puis le plan est relu par le checker, qui n'a pas vu l'analyse, avant la première ligne de code. Coder : une étape à la fois, chacune prouvée avant son commit. Livrer : tous les tests et la relecture en même temps, les corrections, le contrôle avant push, la MR en Draft. En dessous, ce qui arrête le run à chaque temps, avec sa raison dans la fiche : la commande reprend là où elle s'est arrêtée.")
  const heads = [['1 · Préparer', 0.5, 4.1, pres.shapes.PENTAGON, '1F2933'], ['2 · Coder, étape par étape', 4.35, 4.25, pres.shapes.CHEVRON, '3E4C59'], ['3 · Vérifier et livrer', 8.35, 4.48, pres.shapes.CHEVRON, '52606D']]
  heads.forEach(([t, x, w, shape, color], i) => {
    s.addText(t, { shape, x, y: 1.75, w, h: 0.85, fill: { color }, line: { color, width: 0 }, fontFace: 'Calibri', fontSize: 18, bold: true, color: 'FFFFFF', align: 'center', valign: 'middle', objectName: `phase-${i + 1}` })
  })
  const cols = [
    [0.7, ['Analyse → la fiche', 'Build et tests de develop', 'Plan relu par un œil neuf', 'Questions, une seule fois'], ['⛔ develop ne compile pas', 'ou tests trop longs']],
    [4.75, ['Non-régression, ou test du bug', 'Coder sans toucher aux tests', 'Contrôle auto (script)', 'Un commit par étape'], ['⛔ 2 échecs sur l\'étape', 'raison dans la fiche']],
    [8.85, ['Tous les tests ∥ relecture', 'Corrections, 2 tours max', 'Contrôle avant push', '🚀 MR en Draft'], ['⛔ Rien n\'est poussé', 'secret, conflit, identifiants']],
  ]
  const kinds = [['agent', 'step', 'agent', 'you'], ['agent', 'agent', 'step', 'ok'], ['step', 'agent', 'step', 'ok']]
  cols.forEach(([x, items, stop], ci) => {
    items.forEach((t, i) => c.node(`c${ci}-${i}`, x, 2.95 + i * 0.68, 3.5, 0.52, kinds[ci][i], t))
    c.node(`stop${ci}`, x, 5.8, 3.5, 0.8, 'stop', stop[0], stop[1])
  })
}

// ---------- /go: prepare ----------
{
  const { c } = schema('/go', '/go · 1. Préparer', 'Avant la première ligne de code : ce qui ferait échouer le ticket, et un plan relu par un œil neuf.',
    "Le pilote lit l'état git (un fetch) et crée la branche du ticket. Ensuite, deux choses en même temps : l'analyst lit le ticket Jira, ses pages Confluence et le code, et écrit la fiche (critères d'acceptation, plan de 2 à 7 étapes, tests attendus, décisions) ; pendant ce temps, develop est buildé et testé. Si develop ne compile pas, si ses tests ne tiennent pas dans le temps d'une commande sur ce poste, ou si le poste n'a pas le bon SDK ou n'atteint pas Artifactory, on s'arrête ici, avec ce qu'il faut régler : ce n'est pas au ticket de le corriger. Puis le plan est relu avant la moindre ligne de code. D'abord par un script : chaque fichier que le plan cite existe dans le dépôt, ou l'étape le crée. Puis par le checker, qui n'a pas vu l'analyse : il lit seulement la fiche, le ticket et le code, comme le coder les lira, et cherche ce qui ferait échouer le ticket : une exigence oubliée, un fichier ou une méthode qui n'existe pas, une étape qui s'appuie sur une suivante, une migration ou un filet de non-régression oublié. L'analyst corrige chaque point, ou l'écarte avec une preuve (un fichier et sa ligne, une phrase du ticket) : l'écart devient une décision de la MR. Un seul tour, le code et les tests prennent le relais. Les questions bloquantes arrivent ensuite toutes ensemble dans un QCM ; avec la consigne « sans question », les agents prennent les réponses recommandées et les notent « à valider en review ». Ce qui repart tout seul : un fetch coupé (après 3 s puis 10 s), un appel Jira en erreur serveur (un rappel après 20 s).")
  c.node('a', 0.45, 2.95, 1.3, 0.9, 'you', '/go ABC-123')
  c.node('b', 2.0, 2.95, 1.75, 0.9, 'step', 'État git, branche', 'un fetch, la branche')
  c.corner('b', 'retry', 1.55, '↻ fetch : 3 s, 10 s')
  c.group(3.95, 1.65, 2.65, 3.6, 'en même temps')
  c.node('an', 4.1, 2.05, 2.35, 0.95, 'agent', 'analyst', 'ticket, Confluence, code → la fiche')
  c.corner('an', 'retry', 1.5, '↻ Jira : 1 rappel')
  c.node('me', 4.1, 3.75, 2.35, 0.95, 'step', 'develop', 'build et tests')
  c.corner('me', 'time', 1.15, '≤ 42 min')
  c.node('rl', 6.95, 2.9, 2.0, 1.0, 'agent', 'checker', 'relit le plan à neuf : fiche, ticket, code')
  c.corner('rl', 'note', 1.45, 'sans voir l\'analyse')
  c.label('des points : l\'analyst corrige,\nou prouve qu\'il a raison · 1 tour', 6.95, 4.0, 2.0, 'center', 0.5)
  c.dia('q', 9.12, 2.7, 1.8, 1.4, 'Questions\nbloquantes ?', 11)
  c.node('qcm', 11.0, 1.85, 1.9, 0.9, 'you', '❓ Un seul QCM', 'ou « je demande au PO »', 12)
  c.node('plan', 11.0, 4.45, 1.9, 0.9, 'ok', 'Le plan', '2 à 7 étapes')
  c.node('s1', 2.25, 5.75, 2.15, 0.75, 'stop', '⛔ develop cassé', 'à régler hors du ticket')
  c.node('s2', 4.55, 5.75, 2.1, 0.75, 'stop', '⛔ Tests trop longs', 'pour ce poste')
  c.node('s3', 6.8, 5.75, 2.15, 0.75, 'stop', '⛔ Poste incomplet', 'SDK, Artifactory')
  c.wire([c.P('a', 'r'), c.P('b', 'l')])
  c.wire([c.P('b', 'r'), [3.85, 3.4]], { arrow: false }).wire([[3.85, 2.52], [3.85, 4.22]], { arrow: false })
  c.wire([[3.85, 2.52], c.P('an', 'l')]).wire([[3.85, 4.22], c.P('me', 'l')])
  c.wire([c.P('an', 'r'), [6.75, 2.52]], { arrow: false }).wire([c.P('me', 'r'), [6.75, 4.22]], { arrow: false })
  c.wire([[6.75, 2.52], [6.75, 4.22]], { arrow: false }).wire([[6.75, 3.4], c.P('rl', 'l')])
  c.wire([c.P('rl', 'r'), c.P('q', 'l')])
  c.wire([c.P('me', 'b'), [5.275, 5.35]], { arrow: false }).wire([[3.325, 5.35], [7.875, 5.35]], { arrow: false })
  c.wire([[3.325, 5.35], c.P('s1', 't')]).wire([[5.6, 5.35], c.P('s2', 't')]).wire([[7.875, 5.35], c.P('s3', 't')])
  c.wire([c.P('q', 't'), [10.02, 2.3], c.P('qcm', 'l')]).label('oui', 10.12, 2.38, 0.6)
  c.wire([c.P('q', 'b'), [10.02, 4.9], c.P('plan', 'l')]).label('non', 10.12, 4.55, 0.6)
  c.wire([c.P('qcm', 'b'), c.P('plan', 't')])
  c.label('« sans question » :\nréponses recommandées', 12.0, 3.2, 1.0, 'left', 0.55, { size: 9.5 })
}

// ---------- /go: one step ----------
{
  const { c } = schema('/go', '/go · 2. Une étape du plan', 'Chaque étape est prouvée avant son commit. Le coder ne touche jamais aux tests qui le jugent.',
    "Pour un bug, le test-guardian écrit d'abord le test qui le montre, rouge sur le code actuel. Pour une étape qui modifie du code existant, il pose d'abord les tests de non-régression : au moins 80 % des lignes touchées couvertes par des tests du comportement actuel. Ces tests sont verrouillés : le coder ne peut pas les modifier. Pour du code nouveau, le coder écrit le code et ses tests directement. Le coder fait l'étape et ses tests, jusqu'au vert. Puis le contrôle automatique, un script sans IA : tests verrouillés intacts, verts deux fois, non-régression gardée, couverture sans perte. Tout vert : commit de l'étape. Pas vert : le test-guardian reprend dans sa session. Un échec du coder : le debugger cherche la cause, puis un 2e essai ; encore en échec, le run s'arrête avec la raison dans la fiche, et /go reprend là. Si le serveur du modèle coupe un agent, il est repris une fois dans sa session, avec ce qu'il avait déjà lu.")
  c.node('a', 0.5, 2.2, 1.5, 0.95, 'step', 'Étape N', 'du plan')
  c.node('b', 2.45, 2.2, 2.2, 0.95, 'agent', 'test-guardian', 'non-régression, ou test du bug')
  c.node('c', 5.05, 2.2, 1.75, 0.95, 'step', 'Tests verrouillés')
  c.node('d', 7.2, 2.2, 1.9, 0.95, 'agent', 'coder', "l'étape + ses tests")
  c.corner('d', 'retry', 1.45, '↻ repris 1 fois')
  c.dia('e', 9.45, 2.07, 1.6, 1.2, 'Contrôle\nauto')
  c.node('f', 11.45, 2.2, 1.35, 0.95, 'ok', 'Commit', 'case cochée')
  c.node('g', 7.2, 4.15, 1.9, 0.95, 'agent', 'debugger', 'cause de l\'échec')
  c.node('h', 9.35, 4.15, 1.85, 0.95, 'agent', 'test-guardian', 'même session')
  c.node('s', 7.2, 5.6, 1.9, 0.8, 'stop', '⛔ Encore en échec', 'raison dans la fiche')
  c.wire([c.P('a', 'r'), c.P('b', 'l')]).wire([c.P('b', 'r'), c.P('c', 'l')])
  c.wire([c.P('c', 'r'), c.P('d', 'l')]).wire([c.P('d', 'r'), c.P('e', 'l')]).wire([c.P('e', 'r'), c.P('f', 'l')]).label('OK', 11.08, 2.38, 0.35, 'center')
  c.wire([[1.6, 2.2], [1.6, 1.8], [7.6, 1.8], [7.6, 2.2]], { dash: true }).label('code nouveau', 3.2, 1.83, 1.4)
  c.wire([c.P('d', 'b'), c.P('g', 't')]).label('échec', 8.25, 3.45, 0.7)
  c.wire([c.P('g', 'l'), [6.95, 4.62], [6.95, 2.95], [7.2, 2.95]]).label('2e essai', 6.0, 3.65, 0.9, 'right')
  c.wire([c.P('g', 'b'), c.P('s', 't')])
  c.wire([c.P('e', 'b'), [10.25, 4.15]]).label('pas vert', 10.38, 3.45, 0.9)
  c.wire([c.P('h', 'r'), [12.12, 4.62], [12.12, 3.15]]).label('vert', 12.2, 3.75, 0.6)
  c.label('régression → coder', 9.35, 5.15, 1.85, 'center')
  c.wire([[12.12, 2.2], [12.12, 1.52], [0.85, 1.52], [0.85, 2.2]], { dash: true }).label('étape suivante', 9.6, 1.26, 1.6, 'center')
}

// ---------- /go: deliver ----------
{
  const { c } = schema('/go', '/go · 3. Vérifier et livrer', 'Tous les tests et la relecture tournent ensemble. Rien ne part sans le contrôle avant push.',
    "Une fois le plan fini : tous les tests (build, tous les tests du dépôt, la couverture des lignes modifiées, le front touché) et la relecture du checker, en même temps. Un test rouge est rejoué une fois : s'il passe alors, il est signalé instable dans la MR, jamais caché. Les points bloquants et majeurs de la relecture sont corrigés, en deux tours au plus. Puis le contrôle avant push, un script sans IA : develop fusionné, aucun secret, aucun marqueur de conflit, aucun paquet payant, aucune sortie de build ; puis le push. Une coupure réseau est relancée après 3 puis 10 s ; si la branche a bougé sur GitLab entre-temps, ses commits sont ramenés et le push repart. Un secret ou un conflit : rien n'est poussé. Enfin la MR en Draft, avec ses décisions, ses tests et leur couverture, et les choix proposés pour la suite, /fix en tête.")
  c.node('a', 0.5, 3.0, 1.4, 0.9, 'step', 'Plan fini')
  c.group(2.3, 1.65, 2.9, 3.55, 'en même temps')
  c.node('su', 2.5, 2.05, 2.5, 1.0, 'step', 'Tous les tests', 'et couverture modifiée')
  c.corner('su', 'time', 1.15, '≤ 25 min')
  c.tag('note', 2.6, 3.2, 2.3, 'test rouge : rejoué 1 fois')
  c.node('ck', 2.5, 3.85, 2.5, 1.0, 'agent', 'checker', 'relecture')
  c.node('fx', 5.65, 3.0, 1.9, 0.9, 'agent', 'Corrections', '2 tours max')
  c.node('sh', 7.95, 3.0, 2.0, 0.9, 'step', 'Contrôle avant push', 'puis le push')
  c.tag('retry', 7.85, 2.2, 2.2, '↻ réseau : 3 s, 10 s')
  c.tag('retry', 7.85, 2.58, 2.2, '↻ branche bougée : re-push')
  c.node('mr', 10.4, 3.0, 2.4, 0.9, 'ok', '🚀 MR en Draft', 'décisions, tests')
  c.corner('mr', 'retry', 1.55, '↻ GitLab : 1 rappel')
  c.node('nx', 10.4, 4.75, 2.4, 0.8, 'you', '❓ Ensuite : /fix', 'après la CI')
  c.node('st', 7.95, 4.75, 2.0, 0.8, 'stop', '⛔ Rien n\'est poussé', 'secret, conflit')
  c.wire([c.P('a', 'r'), [2.15, 3.45]], { arrow: false }).wire([[2.15, 2.55], [2.15, 4.35]], { arrow: false })
  c.wire([[2.15, 2.55], c.P('su', 'l')]).wire([[2.15, 4.35], c.P('ck', 'l')])
  c.wire([c.P('su', 'r'), [5.4, 2.55]], { arrow: false }).wire([c.P('ck', 'r'), [5.4, 4.35]], { arrow: false })
  c.wire([[5.4, 2.55], [5.4, 4.35]], { arrow: false }).wire([[5.4, 3.45], c.P('fx', 'l')])
  c.wire([c.P('fx', 'r'), c.P('sh', 'l')]).wire([c.P('sh', 'r'), c.P('mr', 'l')])
  c.wire([c.P('sh', 'b'), c.P('st', 't')]).wire([c.P('mr', 'b'), c.P('nx', 't')])
}

// ================= Section 4: without a ticket =================
pres.addSection({ title: 'Sans ticket' })
{
  const { c } = schema('Sans ticket', 'Sans ticket Jira', 'Les mêmes garanties qu\'avec un ticket : la demande du développeur remplace le ticket.',
    "Quatre situations. Un changement à livrer sans ticket : /go sans ticket, suivi de ce qu'il faut faire, quoi, où et pourquoi. Le texte remplace le ticket pour l'analyst, aucun appel à Jira ; la clé est LOCAL-1, LOCAL-2…, et tout le reste est le /go habituel : plan, étapes prouvées, relecture, MR en Draft marquée « Sans ticket Jira ». /go sans clé propose aussi, dans son QCM, les tickets du sprint ou « Sans ticket ». Un problème à comprendre : on enquête d'abord dans la conversation, avec le debugger pour un échec ; rien n'est modifié. Si un correctif est nécessaire, le choix proposé est /go sans ticket, et les conclusions de l'enquête (la cause, les fichiers, un test qui reproduit) passent directement à l'analyst. Une petite modification, une doc, un POC : dans la conversation, avec le build et les tests, puis /push, qui propose en un QCM la branche, le message de commit et la MR, et passe par le même contrôle avant push. Des tests sur du code existant : /tests, sur une branche test/…, puis /push.")
  const rows = [['Un changement\nà livrer', 1.75], ['Un problème\nà comprendre', 3.1], ['Une petite modif,\nune doc, un POC', 4.45], ['Des tests sur\nl\'existant', 5.8]]
  for (const [t, y] of rows) c.label(t, 0.5, y, 1.9, 'left', 0.8, { size: 13, bold: true, color: INK })
  // a change to deliver
  c.node('g1', 2.5, 1.75, 2.45, 0.8, 'you', '/go sans ticket : …', 'quoi, où, pourquoi')
  c.node('g2', 5.35, 1.75, 2.3, 0.8, 'agent', 'Le /go habituel', 'analyse, plan, preuves')
  c.node('g3', 8.05, 1.75, 1.95, 0.8, 'step', 'Clé LOCAL-n', 'branche, fiche')
  c.node('g4', 10.4, 1.75, 2.43, 0.8, 'ok', '🚀 MR en Draft', '« Sans ticket Jira »')
  c.wire([c.P('g1', 'r'), c.P('g2', 'l')]).wire([c.P('g2', 'r'), c.P('g3', 'l')]).wire([c.P('g3', 'r'), c.P('g4', 'l')])
  // a problem to understand
  c.node('e1', 2.5, 3.1, 2.45, 0.8, 'agent', 'Enquête', 'conversation, debugger')
  c.node('e2', 5.35, 3.1, 2.3, 0.8, 'step', 'Les conclusions', 'cause, fichiers, test')
  c.wire([c.P('e1', 'r'), c.P('e2', 'l')])
  c.wire([c.P('e2', 't'), c.P('g2', 'b')]).label('passent à l\'analyst', 6.6, 2.68, 1.6)
  c.tag('note', 8.05, 3.35, 2.6, 'rien n\'est modifié pendant l\'enquête', 0.32)
  // a small change
  c.node('p1', 2.5, 4.45, 2.45, 0.8, 'you', 'Dans la conversation', 'build et tests')
  c.node('p2', 5.35, 4.45, 1.35, 0.8, 'you', '/push')
  c.node('p3', 7.1, 4.45, 2.2, 0.8, 'you', '❓ Un QCM', 'branche, commit, MR')
  c.node('p4', 9.7, 4.45, 1.55, 0.8, 'step', 'Contrôle', 'avant push')
  c.node('p5', 11.6, 4.45, 1.23, 0.8, 'ok', 'Poussé')
  c.wire([c.P('p1', 'r'), c.P('p2', 'l')]).wire([c.P('p2', 'r'), c.P('p3', 'l')]).wire([c.P('p3', 'r'), c.P('p4', 'l')]).wire([c.P('p4', 'r'), c.P('p5', 'l')])
  // tests
  c.node('t1', 2.5, 5.8, 2.45, 0.8, 'you', '/tests InvoiceService')
  c.node('t2', 5.35, 5.8, 2.3, 0.8, 'agent', 'test-guardian', 'branche test/…')
  c.node('t3', 8.05, 5.8, 1.95, 0.8, 'you', '/push')
  c.wire([c.P('t1', 'r'), c.P('t2', 'l')]).wire([c.P('t2', 'r'), c.P('t3', 'l')])
}

// ================= Section 5: after the merge request =================
pres.addSection({ title: 'Après la MR' })
{
  const { c } = schema('Après la MR', '/fix · après la CI ou la review', 'Il attend la fin de la CI, trie les retours, corrige avec la même rigueur que /go.',
    "Premier tour : la MR, le pipeline de ce push, les projets Sonar et Fortify, en lecture ; un appel en erreur serveur ou sans réponse est rappelé une fois après 20 s. Si la CI tourne encore, /fix attend : une pause de 4 minutes, puis le statut du pipeline seul, 8 fois au plus, soit 32 minutes. Ces pauses évitent d'interroger GitLab en boucle et permettent de cliquer sur /fix juste après /go. Au-delà, /fix traite ce qui est fini, marque les jobs encore en cours et propose de le relancer ; « sans attendre » saute l'attente. Puis le tri : à corriger, à répondre, hors périmètre. Un job tombé pour une raison d'infrastructure (runner, réseau, délai) se relance dans GitLab, jamais par un correctif. Les failles et les bugs passent par la non-régression et la preuve, trois au plus par run ; les autres points par le coder, par groupes de fichiers. Puis tous les tests et la relecture, le contrôle avant push, la MR mise à jour, et les réponses aux discussions, prêtes à coller.")
  c.node('a', 0.5, 2.05, 1.2, 0.9, 'you', '/fix')
  c.node('b', 2.05, 2.05, 2.2, 0.9, 'step', 'Lit les retours', 'MR, CI, Sonar, Fortify')
  c.corner('b', 'retry', 1.55, '↻ erreur : 1 rappel')
  c.dia('ci', 4.65, 1.9, 1.6, 1.2, 'La CI\ntourne ?')
  c.node('p', 4.7, 3.55, 1.5, 0.75, 'step', 'Pause 4 min')
  c.tag('time', 4.4, 4.4, 2.1, '≤ 8 fois · 32 min *')
  c.node('t', 6.75, 2.05, 1.7, 0.9, 'step', 'Tri', 'corriger, répondre')
  c.node('e', 9.0, 1.55, 2.3, 0.8, 'agent', 'Failles et bugs', 'non-régression + test')
  c.node('f', 9.0, 2.55, 2.3, 0.8, 'agent', 'Autres points', 'coder, par fichiers')
  c.node('g', 9.0, 3.55, 2.3, 0.8, 'you', 'Job hors du code', 'à relancer dans GitLab')
  c.node('h', 9.0, 5.0, 2.3, 0.85, 'step', 'Tous les tests', 'et relecture')
  c.node('i', 6.4, 5.0, 2.2, 0.85, 'step', 'Contrôle avant push', 'puis le push')
  c.corner('i', 'retry', 1.55, '↻ réseau : 3 s, 10 s')
  c.node('j', 3.3, 5.0, 2.6, 0.85, 'ok', '🔁 MR mise à jour', '+ réponses à coller')
  c.node('k', 0.5, 5.0, 2.3, 0.85, 'you', '❓ Ensuite : /fix', 'après la prochaine CI')
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
  c.foot('* Un coup d\'œil au pipeline toutes les 4 min, 8 au plus. Au-delà, /fix traite ce qui est fini et propose de le relancer ; « sans attendre » saute l\'attente.')
}

// ---------- /tests ----------
{
  const { c } = schema('Après la MR', '/tests · des tests sur du code existant', 'Des tests du comportement actuel, prouvés deux fois, sans toucher au code de production.',
    "On donne un fichier ou une classe, ou rien pour avoir le menu des fichiers sans tests. Un script relève les faits : les projets de tests, bUnit pour les pages Blazor, le travail non commité. S'il manque quelque chose, un seul QCM : créer le projet de tests, ajouter bUnit, commiter d'abord son travail. Puis le test-guardian : la couverture avant, les tests du comportement actuel dans le style du dépôt, verts deux fois et vérifiés par un script (une assertion par test, rien d'ignoré, pas d'horloge réelle), la couverture après. Un test qui révèle un bug est écarté et signalé, jamais corrigé au passage. Puis un commit test(...) avec la couverture avant et après, et /push proposé ensuite. Deux variantes : /tests api pour les endpoints d'une API (la factory d'abord, un scénario vert, puis les autres), et /tests env pour vérifier un déploiement en lecture seule, jamais la production ; un environnement qui répond 503 le temps de redémarrer est redemandé après 3 puis 10 s.")
  c.node('a', 0.5, 2.0, 2.0, 0.9, 'you', '/tests InvoiceService')
  c.node('b', 2.85, 2.0, 1.9, 0.9, 'step', 'Les faits', 'projets de tests, bUnit')
  c.dia('q', 5.1, 1.85, 1.8, 1.2, 'Il manque\nquelque chose ?')
  c.node('qcm', 5.15, 3.6, 1.7, 0.85, 'you', '❓ Un QCM', 'projet, bUnit')
  c.group(7.3, 1.55, 5.53, 2.75, 'test-guardian')
  c.node('t1', 7.5, 2.0, 1.55, 0.9, 'agent', 'Couverture', 'avant')
  c.node('t2', 9.25, 2.0, 1.7, 0.9, 'agent', 'Tests', 'du comportement')
  c.node('t3', 11.15, 2.0, 1.5, 0.9, 'agent', 'Verts ×2', 'sans test creux')
  c.node('t4', 11.15, 3.2, 1.5, 0.8, 'agent', 'Couverture', 'après')
  c.node('bug', 9.25, 3.2, 1.7, 0.8, 'stop', 'Un bug révélé', 'écarté, signalé')
  c.node('d', 9.0, 4.8, 2.4, 0.85, 'ok', '✅ commit test(…)', 'couverture avant, après')
  c.node('e', 6.3, 4.8, 2.3, 0.85, 'you', '❓ Ensuite : /push')
  c.label('Les variantes', 0.5, 4.45, 3.0)
  c.node('v1', 0.5, 4.8, 2.6, 0.85, 'step', '/tests api', 'factory, puis les scénarios')
  c.node('v2', 3.35, 4.8, 2.6, 0.85, 'step', '/tests env recette', 'lecture seule, jamais la prod')
  c.corner('v2', 'retry', 1.35, '↻ 503 : 3 s, 10 s')
  c.wire([c.P('a', 'r'), c.P('b', 'l')]).wire([c.P('b', 'r'), c.P('q', 'l')])
  c.wire([c.P('q', 'b'), c.P('qcm', 't')]).label('oui', 6.08, 3.22, 0.5)
  c.wire([c.P('q', 'r'), c.P('t1', 'l')]).label('non', 6.95, 2.18, 0.4, 'center')
  c.wire([c.P('qcm', 'r'), [8.27, 4.02], c.P('t1', 'b')])
  c.wire([c.P('t1', 'r'), c.P('t2', 'l')]).wire([c.P('t2', 'r'), c.P('t3', 'l')]).wire([c.P('t3', 'b'), c.P('t4', 't')])
  c.wire([c.P('t2', 'b'), c.P('bug', 't')])
  c.wire([c.P('t4', 'b'), [11.9, 5.22], c.P('d', 'r')])
  c.wire([c.P('d', 'l'), c.P('e', 'r')])
}

// ================= Section 6: when it gets stuck, and the questions =================
pres.addSection({ title: 'Quand ça coince' })
{
  const { s } = schema('Quand ça coince', 'Quand ça coince', 'Ce qui ne dépend que d\'un instant repart seul. Ce qui échouerait pareil s\'arrête, avec sa raison.',
    "Trois familles. Ce qui repart tout seul : une coupure du VPN pendant un fetch ou un push, un Artifactory ou un registre npm qui redémarre, un git status de Rider qui tient l'index au moment du commit, un appel Jira ou GitLab en erreur serveur, le serveur du modèle qui tombe quelques minutes. Un « trop de requêtes » (429) n'est pas une panne : le prochain essai vient quand le serveur le demande, sinon après quelques secondes, différentes pour chaque agent qui travaille en même temps, pour qu'ils ne redemandent pas tous au même instant. Chaque nouvel essai tient dans le temps de la commande, et une ligne le dit dans la sortie. Ce qui est borné : rien n'attend sans limite, et un script qui atteint sa borne dit ce qui a tourné avant de s'arrêter. Ce qui n'est jamais relancé : tout ce qui échouerait pareil. En particulier un test n'est jamais relancé pour passer au vert : instable, il reste un défaut. Après les essais, un message dit quoi régler, hors d'OpenCode.", 'TEXTE')
  const cols = [
    ['retry', '↻  Relancé tout seul', ['Fetch, push : 3 s, puis 10 s', 'Paquets NuGet : 20 s, puis 60 s', 'Registre npm : 15 s, puis 45 s', 'Index git tenu : 1, 2, 3 s', 'Jira, GitLab en erreur : 1 rappel', 'Serveur du modèle : 10 essais, 8 min', 'Trop de requêtes : selon le serveur']],
    ['time', '≤  Borné dans le temps', ['Build et tests : 42 min', 'Une exécution des tests : 25 min', 'Un test : 5 min', 'Attente d\'un autre build : 20 min', 'Appel Jira, GitLab… : 5 min', 'Reprise auto : 2 puis 5 min']],
    ['stop', '⛔  Jamais relancé', ['Un test rouge', 'Un test instable', 'Une erreur de compilation', 'Des identifiants refusés', 'Un conflit de merge', 'Des tests trop longs']],
  ]
  cols.forEach(([k, head, items], i) => card(s, 0.5 + i * 4.24, 1.7, 3.85, 4.75, k, head, items, { step: 0.55, itemSize: 14, headSize: 20 }))
  s.addText('Après les essais : un message dit quoi régler, et où.', { x: 0.5, y: 6.6, w: 12.33, h: 0.35, fontSize: 14, italic: true, color: MUTED, fontFace: 'Calibri', align: 'center', margin: 0, isTextBox: true, objectName: 'after' })
}

// ---------- the questions of the tech leads ----------
{
  const { s } = schema('Quand ça coince', 'Les questions qu\'on nous pose', 'Les réponses courtes ; le détail est dans les notes et dans la carte des flux.',
    "Qui valide ? Le développeur, toujours : les agents ouvrent une MR en Draft, ne mergent jamais et ne poussent jamais sur develop, main ou master. Et si un correctif casse autre chose ? Les tests de non-régression sont posés avant de toucher au code, tous les tests tournent avant le push, la relecture du checker vérifie les critères du ticket, et un test rouge n'est jamais relancé jusqu'à passer. L'IA voit-elle nos secrets ? Non : nuget.config, fichiers .env, identifiants git, ~/.zshenv sont refusés à tous les agents, comme toute commande qui afficherait l'environnement ; pas de recherche ni de page web ; Jira, Confluence et Fortify en lecture seule. Et si l'IA tourne en rond ? Une réponse qui se répète est coupée, un même appel répété trois fois est refusé, chaque agent a un nombre d'étapes borné ; au-delà, l'arrêt dit pourquoi. Le poste est-il bloqué ? Rien n'attend sans limite ; pendant un run, le développeur travaille ailleurs, par exemple dans un autre espace de travail. Et si ça s'arrête au milieu ? Tout est gardé : la fiche du ticket, les commits, le travail mis de côté ; relancer la commande reprend à la première étape non faite. Et les skills trouvés sur Internet ? OpenCode charge d'office les skills de ~/.claude/skills, de ~/.agents/skills et des dossiers .claude, .agents et .opencode du projet et de ses dossiers parents : ils sont retirés. Seuls nos skills, relus et versionnés dans le dépôt de notre configuration, et les patterns de l'équipe sont chargés ; un skill utile, même publié par Microsoft, est d'abord relu et réécrit chez nous. Et si l'IA comprend mal le ticket ? Avant la première ligne de code, le plan est relu par le checker, qui n'a pas vu l'analyse : il lit la fiche, le ticket et le code, et cherche une exigence oubliée, un fichier qui n'existe pas, une étape dans le mauvais ordre ; l'analyst corrige, ou prouve qu'il a raison, et la MR montre ce qui a été écarté. Le développeur peut aussi demander l'analyse seule et relire le plan avant que le code commence. Et une longue session ? Quand une requête approche de la taille que le modèle accepte, les plus anciennes sorties d'outils (un fichier lu, un build) sont effacées des requêtes, jamais les rapports des agents ; le modèle relit un fichier s'il en a besoin, et le résumé du contexte, plus long et qui garde moins, arrive plus tard ou jamais.", 'TEXTE')
  const qa = [
    ['Qui valide le code ?', 'Le développeur, en review. MR en Draft ; jamais de merge, jamais de push sur develop.'],
    ['Et si un correctif casse autre chose ?', 'Non-régression avant, tous les tests et une relecture après.'],
    ['L\'IA voit-elle nos secrets ?', 'Non : secrets et identifiants refusés, pas de web, Jira et Fortify en lecture.'],
    ['Et si l\'IA tourne en rond ?', 'Boucles coupées, étapes bornées ; l\'arrêt dit pourquoi.'],
    ['Le poste est-il bloqué ?', 'Rien n\'attend sans limite ; le développeur travaille ailleurs pendant le run.'],
    ['Et si ça s\'arrête au milieu ?', 'Fiche, commits, travail mis de côté : la commande reprend là.'],
    ['Et les skills trouvés sur Internet ?', 'Ignorés : seuls nos skills, relus et versionnés, sont chargés.'],
    ['Et si l\'IA comprend mal le ticket ?', 'Le plan est relu par un agent qui n\'a pas vu l\'analyse, avant le code.'],
  ]
  qa.forEach(([q, a], i) => {
    const x = 0.5 + (i % 2) * 6.24
    const y = 1.6 + Math.floor(i / 2) * 1.3
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 6.09, h: 1.18, rectRadius: 0.08, fill: { color: 'F7F8FA' }, line: { color: 'C7CCD3', width: 1 }, objectName: `qa-${i}` })
    s.addText(q, { x: x + 0.25, y: y + 0.1, w: 5.6, h: 0.4, fontSize: 17, bold: true, color: INK, fontFace: 'Calibri', margin: 0, valign: 'middle', isTextBox: true, objectName: `qa-q-${i}` })
    s.addText(a, { x: x + 0.25, y: y + 0.52, w: 5.6, h: 0.58, fontSize: 14, color: '3E4C59', fontFace: 'Calibri', margin: 0, valign: 'top', isTextBox: true, objectName: `qa-a-${i}` })
  })
}

// ---------- to remember ----------
pres.addSection({ title: 'Conclusion' })
{
  const s = pres.addSlide({ masterName: 'TITRE', sectionTitle: 'Conclusion' })
  s.addText('À retenir', { x: 0.8, y: 0.6, w: 11.7, h: 0.9, fontSize: 40, bold: true, color: 'FFFFFF', fontFace: 'Calibri', margin: 0, isTextBox: true, objectName: 'title-end' })
  const points = [
    ['2', 'moments pour le développeur', 'le QCM du début, la relecture de la MR', 'C3A6E0'],
    ['×2', 'chaque preuve, deux fois', 'un test instable est refusé, jamais relancé', '86B2E6'],
    ['1', 'commit par faille', '/fortify : 5 failles au plus, une MR', 'E58C83'],
    ['0', 'attente sans borne', 'ce qui coince un instant repart seul', 'E0A64A'],
  ]
  points.forEach(([big, head, sub, color], i) => {
    const x = 0.8 + i * 3.05
    s.addText(big, { x, y: 2.2, w: 2.8, h: 1.3, fontSize: 66, bold: true, color, fontFace: 'Calibri', margin: 0, isTextBox: true, objectName: `big-${i}` })
    s.addText([{ text: head, options: { bold: true, fontSize: 20, color: 'FFFFFF', breakLine: true } }, { text: sub, options: { fontSize: 15, color: 'C9D2DC' } }], { x, y: 3.6, w: 2.8, h: 1.6, fontFace: 'Calibri', margin: 0, valign: 'top', isTextBox: true, objectName: `point-${i}` })
  })
  s.addText('Le détail de chaque flux : docs/carte-des-flux.html', { x: 0.8, y: 6.55, w: 11.7, h: 0.4, fontSize: 13, color: '9AA5B1', fontFace: 'Calibri', margin: 0, isTextBox: true, objectName: 'more' })
  s.addNotes("Pour vous, quatre choses. Le développeur n'intervient qu'au début, s'il y a des questions, et à la review de la MR. Chaque preuve tourne deux fois, et un test instable est un défaut, pas un aléa. Avec /fortify, chaque faille a son commit et sa preuve, cinq failles au plus par MR. Enfin rien n'attend sans limite : ce qui coince un instant repart seul, le reste s'arrête avec un message qui dit quoi faire. Le détail de chaque flux, avec les chiffres, est dans la carte des flux du dépôt.")
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
