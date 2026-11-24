// Checks for the retain cycles that leak a whole web view.
//
// `WKUserContentController.add(_:name:)` holds its handler strongly. Registering `self` from
// an object that also holds the web view makes the two keep each other alive, so dismissing
// the viewer never frees the page — and a DWG page holds a wasm engine of tens of megabytes.
// `tearDown` is not enough on its own either: it only runs if the view is dismissed, and
// `onDisappear` is not guaranteed when a parent is torn down.
//
//   node check-retain-cycles.mjs
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const sourceDir = path.join(root, 'ios/CADViewer/Sources/CADViewer')

const problems = []
let inspected = 0

for (const file of fs.readdirSync(sourceDir)) {
  if (!file.endsWith('.swift')) continue
  const text = fs.readFileSync(path.join(sourceDir, file), 'utf8')
  inspected += 1

  // Registering self as a script message handler, directly.
  for (const match of text.matchAll(
    /userContentController\.add\(\s*self\s*,/g
  )) {
    const line = text.slice(0, match.index).split('\n').length
    problems.push(
      `${file}:${line} registers self with the content controller, which retains it`
    )
  }

  // A view being its own delegate is fine (delegates are weak) but being its own handler is
  // not, and the two look similar in review.
  const registersSelf = /add\(\s*self\s*,\s*name:/.test(text)
  const hasWeakProxy = /class WeakScriptMessageHandler/.test(text) ||
    /WeakScriptMessageHandler\(/.test(text)
  if (registersSelf && !hasWeakProxy) {
    problems.push(`${file} registers self without a weak proxy in sight`)
  }
}

console.log(`inspected ${inspected} files`)
if (problems.length > 0) {
  console.error(`LEAKS ${problems.length}:`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log('no strong handler registrations')
