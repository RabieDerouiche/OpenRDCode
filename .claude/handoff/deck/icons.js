// The icons of the deck, rendered once to PNG (white, for colored circles), kept in icons.json
const React = require('react')
const S = require('react-dom/server')
const fa = require('react-icons/fa')
const sharp = require('sharp')
const fs = require('fs')
const names = ['FaBrain', 'FaTools', 'FaEye', 'FaUser', 'FaRobot', 'FaLaptop', 'FaLinux', 'FaDocker', 'FaCode', 'FaServer', 'FaPlug']
;(async () => {
  const out = {}
  for (const n of names) {
    const svg = S.renderToStaticMarkup(React.createElement(fa[n], { color: '#FFFFFF', size: 256 }))
    out[n] = 'image/png;base64,' + (await sharp(Buffer.from(svg)).resize(256, 256, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer()).toString('base64')
  }
  fs.writeFileSync('icons.json', JSON.stringify(out))
  console.log('icons', Object.keys(out).length)
})()
