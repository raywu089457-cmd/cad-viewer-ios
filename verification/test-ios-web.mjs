import { webkit } from 'playwright'
const b = await webkit.launch()
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
const p = await ctx.newPage()
const logs = []
p.on('console', m => logs.push(m.type() + ': ' + m.text().slice(0, 200)))
p.on('pageerror', e => logs.push('PAGEERR ' + String(e).slice(0, 250)))
await p.goto('http://127.0.0.1:8097/index.html?name=example_2018.dwg', { waitUntil: 'load' })
await p.waitForTimeout(22000)
await p.screenshot({ path: 'shots/ios-web-dwg.png' })
console.log('logs:'); logs.slice(0, 12).forEach(l => console.log('  ', l))
const st = await p.evaluate(() => ({ status: document.getElementById('status')?.textContent, hidden: document.getElementById('status')?.hidden, canvases: document.querySelectorAll('canvas').length }))
console.log('status:', JSON.stringify(st))
await b.close()
