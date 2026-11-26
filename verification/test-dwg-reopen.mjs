// Checks the DWG viewer's reopen path in a real browser.
//
// The app keeps the wasm engine warm: opening a second drawing calls `window.cadOpenDwg`
// instead of reloading the page. That function did not exist for a while — the page only
// exposed `cadReload` — so Swift's `window.cadOpenDwg?.(...)` silently did nothing and a
// second DWG never opened. Nothing caught it, because the page still reported `ready`.
//
//   node test-dwg-reopen.mjs <viewer-dist> <first.dwg> <next.dwg>...
//
// Every file after the first is opened through the reopen path, in order. A DWG format the
// samples cover but this test never opened was a format nothing ran — R2000 sat in the tree
// while only R2013 and R2018 were exercised.
import { chromium } from 'playwright'
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'

const [root, first, ...rest] = process.argv.slice(2)
if (!root || !first || rest.length === 0) {
  console.error('usage: node test-dwg-reopen.mjs <viewer-dist> <first.dwg> <next.dwg>...')
  process.exit(2)
}

// The MIME table the app uses, read from the source of truth rather than kept in step by
// hand: WebKit refuses to stream-compile the wasm unless it is served as application/wasm,
// and a test server that guessed a type would pass while the app failed.
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
if (mimeTable.size === 0) {
  console.error('could not read the MIME table from BundleServing.swift')
  process.exit(1)
}

/** Serves the built viewer and answers the drawing endpoint the app uses. */
function serve() {
  let current = first
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0])
    if (url.endsWith('/__dwg__')) {
      res.writeHead(200, {
        'Content-Type': mimeTable.get('.bin') ?? 'application/octet-stream'
      })
      fs.createReadStream(current).pipe(res)
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
    // The same headers the app's scheme handler sends. A test that omits them is testing a
    // server the app never runs: the wasm worker depends on the cross-origin policy pair.
    res.writeHead(200, {
      'Content-Type':
        mimeTable.get(path.extname(target)) ?? 'application/octet-stream',
      'Cache-Control': 'no-store',
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp'
    })
    fs.createReadStream(target).pipe(res)
  })
  return { server, set drawing(value) { current = value } }
}

const harness = serve()
await new Promise(resolve => harness.server.listen(0, '127.0.0.1', resolve))
const port = harness.server.address().port

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 900, height: 700 } })
const events = []
await page.exposeFunction('__report', e => events.push(e))
// Mimic the WKWebView message handler.
await page.addInitScript(() => {
  const handler = { postMessage: m => window.__report(m) }
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    get: () => ({ messageHandlers: { cadEvents: handler } }),
    set: () => {}
  })
})
page.on('pageerror', e => events.push({ event: 'pageerror', message: String(e) }))

/** Resolves once any of the given events has been reported, or after a timeout. */
function waitFor(predicate, timeoutMs = 25000) {
  const started = Date.now()
  return new Promise(resolve => {
    const tick = () => {
      if (predicate(events)) return resolve(true)
      if (Date.now() - started > timeoutMs) return resolve(false)
      setTimeout(tick, 200)
    }
    tick()
  })
}

await page.goto(`http://127.0.0.1:${port}/index.html?name=first.dwg`, {
  waitUntil: 'networkidle'
})
// The page reports rendered when the first frame is drawn; error means it gave up.
await waitFor(list =>
  list.some(e => e.event === 'rendered' || e.event === 'error' || e.event === 'pageerror')
)

const names = list => list.map(e => e.event).filter(n =>
  ['ready', 'loading', 'activated', 'rendered', 'error', 'pageerror'].includes(n))
const firstLoad = names(events)
console.log('first load :', firstLoad.join(' -> '))

// The open page must expose the reopen entry point.
const hasEntry = await page.evaluate(() => typeof window.cadOpenDwg === 'function')
console.log('cadOpenDwg :', hasEntry ? 'present' : 'MISSING')

const before = events.length
harness.drawing = rest[0]
const base64 = fs.readFileSync(rest[0]).toString('base64')
// A missing entry point must fail this test, not throw out of it.
try {
  await page.evaluate(
    ([data]) => window.cadOpenDwg(data, 'next.dwg', 100),
    [base64]
  )
} catch (error) {
  // A missing entry point must fail this test, not throw out of it.
  console.log('reopen     : threw,', String(error).split(String.fromCharCode(10))[0])
}
await waitFor(list =>
  list.slice(before).some(e => e.event === 'rendered' || e.event === 'error' || e.event === 'pageerror')
)
const reopen = names(events.slice(before))
console.log('reopen     :', reopen.join(' -> '))

// Every further file goes through the same path, so a format that only the engine mishandles
// is caught rather than inferred from the first pair.
let restOk = reopen.includes('rendered')
for (const file of rest.slice(1)) {
  const mark = events.length
  harness.drawing = file
  try {
    await page.evaluate(
      ([data, name]) => window.cadOpenDwg(data, name, 100),
      [fs.readFileSync(file).toString('base64'), path.basename(file)]
    )
  } catch (error) {
    console.log('reopen     : threw,', String(error).split(String.fromCharCode(10))[0])
    restOk = false
    continue
  }
  await waitFor(list =>
    list.slice(mark).some(e => e.event === 'rendered' || e.event === 'error' || e.event === 'pageerror')
  )
  const seen = names(events.slice(mark))
  const drew = seen.includes('rendered')
  console.log(`reopen     : ${path.basename(file)} ${drew ? 'rendered' : 'FAILED'} (${seen.join(' -> ')})`)
  if (!drew) restOk = false
}

// Zoom to fit, the button the native toolbar now offers.
//
// The native layer draws no zoom controls for DWG — the page's canvas handles pinch and drag —
// so a reader who pinched past the edge had no way back. This asks the page to frame the whole
// drawing and requires it to say it did: `false` means the entry point or the engine's fit is
// missing, which is the failure mode a native call into a page cannot otherwise see.
const zoomEntry = await page.evaluate(() => typeof window.cadZoomToFit === 'function')
console.log('cadZoomToFit:', zoomEntry ? 'present' : 'MISSING')
const zoomed = zoomEntry ? await page.evaluate(() => window.cadZoomToFit()) : false
console.log('zoom to fit :', zoomed ? 'ran' : 'did NOT run')

// A second call must also work: the first one can be swallowed by a layout that is still
// settling, and a button that works only once is a button that is broken.
const zoomedAgain = zoomEntry ? await page.evaluate(() => window.cadZoomToFit()) : false
console.log('zoom again  :', zoomedAgain ? 'ran' : 'did NOT run')

// An error that escapes a promise has to reach the native side. Without the listeners the page
// would sit on "Opening…" with nothing said, and the reader would be left guessing between a
// slow engine and a broken one — the two cases look identical from the outside.
const beforeError = events.length
await page.evaluate(() => {
  Promise.reject(new Error('deliberate, from the test'))
})
await waitFor(list => list.slice(beforeError).some(e => e.event === 'error'))
const reported = events.slice(beforeError).filter(e => e.event === 'error')
console.log('rejection   :', reported.length > 0 ? 'reported' : 'SILENT')
if (reported.length > 0) {
  console.log('              "' + String(reported[0].message).slice(0, 60) + '"')
}

// A page that reports `rendered` and draws nothing satisfies every check above. Take a screenshot
// and count what is on it: the engine draws into a WebGL canvas, which cannot be read back
// through `drawImage` without `preserveDrawingBuffer`, so the screenshot is what reached the
// screen.
// The canvas element, not the page: the status line and buttons are lit either way, so a
// full-page screenshot passes on a blank canvas.
const element = await page.$('canvas')
const shot = element ? await element.screenshot({ type: 'png' }) : null
const painted = shot === null ? { count: 0, total: 0 } : await page.evaluate(async base64 => {
  const image = new Image()
  image.src = 'data:image/png;base64,' + base64
  await image.decode()
  const copy = document.createElement('canvas')
  copy.width = image.width
  copy.height = image.height
  const context = copy.getContext('2d')
  context.drawImage(image, 0, 0)
  const data = context.getImageData(0, 0, copy.width, copy.height).data
  let count = 0
  for (let i = 0; i < data.length; i += 4) {
    if (data[i] + data[i + 1] + data[i + 2] > 180) count += 1
  }
  return { count, total: copy.width * copy.height }
}, shot.toString('base64'))
console.log('canvas      :', painted.count + ' lit pixel(s) of ' + painted.total)
// What this can and cannot say. It separates "something was drawn" from "nothing was", which is
// the difference the event stream cannot express — a page that reports `rendered` and paints
// nothing passes every other check in this file.
//
// It cannot tell a complete drawing from a half-drawn one: clipping 90% of the canvas still left
// 2584 lit pixels, and no threshold separates that from a sparse drawing. A share of the canvas
// rather than a flat count, because a phone canvas and a tablet canvas differ in area.
//
// The samples light 0.4% to 1.5%; a twentieth of a percent is below any of them and above a few
// stray strokes.
const floor = Math.max(500, Math.round(painted.total * 0.0005))
const drew = painted.count >= floor
console.log(
  '             ',
  drew
    ? 'has a drawing on it (' + ((100 * painted.count) / painted.total).toFixed(2) + '% of the canvas)'
    : 'BLANK or a fraction of one (floor ' + floor + ')'
)
await browser.close()
harness.server.close()

const ok = hasEntry && firstLoad.includes('rendered') && restOk && zoomEntry && zoomed && zoomedAgain && reported.length > 0 && drew
console.log(ok ? 'PASS' : 'FAIL')
process.exit(ok ? 0 : 1)
