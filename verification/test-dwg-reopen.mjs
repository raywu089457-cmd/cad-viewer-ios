// Checks the DWG viewer's reopen path in a real browser.
//
// The app keeps the wasm engine warm: opening a second drawing calls `window.cadOpenDwg`
// instead of reloading the page. That function did not exist for a while — the page only
// exposed `cadReload` — so Swift's `window.cadOpenDwg?.(...)` silently did nothing and a
// second DWG never opened. Nothing caught it, because the page still reported `ready`.
//
//   node test-dwg-reopen.mjs <viewer-dist> <first.dwg> <second.dwg>
//
// Prints the events the page posts for each load; both must end in `rendered`.
import { chromium } from 'playwright'
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'

const [root, first, second] = process.argv.slice(2)
if (!root || !first || !second) {
  console.error('usage: node test-dwg-reopen.mjs <viewer-dist> <first.dwg> <second.dwg>')
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
harness.drawing = second
const base64 = fs.readFileSync(second).toString('base64')
// A missing entry point must fail this test, not throw out of it.
try {
  await page.evaluate(
    ([data]) => window.cadOpenDwg(data, 'second.dwg', 100),
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

await browser.close()
harness.server.close()

const ok = hasEntry && firstLoad.includes('rendered') && reopen.includes('rendered')
console.log(ok ? 'PASS' : 'FAIL')
process.exit(ok ? 0 : 1)
