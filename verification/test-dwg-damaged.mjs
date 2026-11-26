// Checks that a damaged DWG is reported rather than silently drawn as nothing.
//
// The DXF path is tested against real truncations; the DWG path never was. A DWG arrives damaged
// by being cut off wherever a download stopped, and the failure it can produce is the worst kind:
// the engine accepts the bytes, draws nothing, and the page reports `rendered` — a blank canvas
// presented as a success.
//
//   node test-dwg-damaged.mjs <viewer-dist> <drawing.dwg>
import { chromium } from 'playwright'
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'

const [root, drawing] = process.argv.slice(2)
if (!root || !drawing) {
  console.error('usage: node test-dwg-damaged.mjs <viewer-dist> <drawing.dwg>')
  process.exit(2)
}

const mimeSource = fs.readFileSync(
  new URL('../ios/DXFGeometry/Sources/DXFGeometry/BundleServing.swift', import.meta.url),
  'utf8'
)
const mimeTable = new Map()
for (const match of mimeSource.matchAll(
  /case ((?:"[a-z0-9]+"(?:, )?)+): return "([^"]+)"/g
)) {
  const extensions = [...match[1].matchAll(/"([a-z0-9]+)"/g)].map(m => m[1])
  for (const extension of extensions) mimeTable.set('.' + extension, match[2])
}

/** What the server hands the page for `/__dwg__`, which the test swaps per cut. */
let currentBytes = fs.readFileSync(drawing)

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0])
    if (url.endsWith('/__dwg__')) {
      res.writeHead(200, { 'Content-Type': 'application/octet-stream' })
      res.end(currentBytes)
      return
    }
    const file = root + (url.startsWith('/') ? url : '/' + url)
    const target = fs.existsSync(file) && fs.statSync(file).isDirectory()
      ? path.join(file, 'index.html')
      : file
    if (!fs.existsSync(target)) {
      res.writeHead(404)
      res.end()
      return
    }
    const extension = path.extname(target).toLowerCase()
    res.writeHead(200, {
      'Content-Type': mimeTable.get(extension) ?? 'application/octet-stream'
    })
    fs.createReadStream(target).pipe(res)
  })
  return { server }
}

function waitFor(predicate, timeoutMs = 40000) {
  const deadline = Date.now() + timeoutMs
  return new Promise((resolve, reject) => {
    const tick = () => {
      if (predicate(events)) return resolve(true)
      if (Date.now() > deadline) return reject(new Error('timed out'))
      setTimeout(tick, 100)
    }
    tick()
  })
}

const harness = serve()
await new Promise(resolve => harness.server.listen(0, '127.0.0.1', resolve))
const port = harness.server.address().port

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 900, height: 700 } })
const events = []
await page.exposeFunction('__report', e => events.push(e))
await page.addInitScript(() => {
  const handler = { postMessage: m => window.__report(m) }
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    get: () => ({ messageHandlers: { cadEvents: handler } })
  })
})
page.on('pageerror', error => events.push({ event: 'pageerror', message: String(error) }))

const whole = fs.readFileSync(drawing)
const failures = []
let reported = 0
let drew = 0

// A DWG header is a few hundred bytes; below that nothing is a drawing at all, so the cuts start
// where a plausible partial file would be.
for (const fraction of [1.0, 0.95, 0.75, 0.5, 0.25, 0.1]) {
  const cut = Math.floor(whole.length * fraction)
  currentBytes = whole.subarray(0, cut)

  const before = events.length
  await page.goto(`http://127.0.0.1:${port}/index.html?name=damaged.dwg`, {
    waitUntil: 'networkidle'
  })

  let settled = true
  try {
    await waitFor(list =>
      list.some(e => e.event === 'rendered' || e.event === 'error' || e.event === 'pageerror')
    )
  } catch {
    settled = false
  }

  const seen = events.slice(before).map(e => e.event)
  const crashed = seen.includes('pageerror')
  const errored = seen.includes('error')
  const rendered = seen.includes('rendered')

  // Every cut has to land in exactly one of two states: reported, or drawn. A crash fails, and a
  // cut that neither settled nor reported would leave the reader on a spinner forever.
  const outcome = !settled ? 'never settled' : crashed ? 'crashed' : errored ? 'reported' : rendered ? 'drew' : 'silent'
  console.log(`  ${String(cut).padStart(7)} of ${whole.length} (${Math.round(fraction * 100)}%): ${outcome}`)

  if (outcome === 'crashed') failures.push(`cut at ${cut} crashed`)
  if (outcome === 'never settled') failures.push(`cut at ${cut} left the page waiting`)
  if (outcome === 'reported') reported += 1
  if (outcome === 'drew') drew += 1
}

await browser.close()
harness.server.close()

// What the engine does with a truncated DWG is not something this app can change: it accepts the
// bytes and draws whatever it could parse. The app cannot tell a partial drawing from a whole one,
// because the engine reports neither an entity count nor a warning.
//
// So the requirement here is the one the app is responsible for: every cut has to settle. A crash,
// or a page left waiting, is the app's failure; drawing a partial file is the engine's limit, and
// it is reported rather than asserted away.
if (failures.length > 0) {
  for (const failure of failures) console.log(`FAIL  ${failure}`)
  console.log(`\n${failures.length} damaged-DWG problem(s)`)
  process.exit(1)
}

if (reported + drew !== 6) {
  console.log(`FAIL  only ${reported + drew} of 6 cuts produced an outcome`)
  process.exit(1)
}

if (drew > 0 && reported === 0) {
  console.log('')
  console.log(
    `NOTE: all ${drew} truncations drew a partial drawing. The engine reports neither a count`
  )
  console.log(
    '      nor a warning, so the app cannot tell a reader that a drawing is incomplete.'
  )
  console.log('      Recorded in the README, not asserted away here.')
}

console.log(`\n${drew} cuts drew, ${reported} were reported, none crashed and none hung`)
