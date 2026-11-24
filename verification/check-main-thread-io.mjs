// Checks that the UI layer does not read files on the main actor.
//
// The three viewers are @MainActor or @Observable, so a synchronous read inside them runs on
// the main thread. A real DWG is routinely tens of megabytes and a PDF of a drawing is not
// small either: reading one there freezes the interface for the whole read, including the
// spinner that exists to say the file is loading. This is invisible in a screenshot and in
// any test that does not measure responsiveness, which is why it is checked mechanically.
//
//   node check-main-thread-io.mjs
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')

/** Files that are bound to the main actor by construction. */
const uiFiles = [
  'ios/CADViewer/Sources/CADViewer/DWGViewer.swift',
  'ios/CADViewer/Sources/CADViewer/PDFViewer.swift',
  'ios/CADViewer/Sources/CADViewer/RootView.swift',
  'ios/CADViewer/Sources/CADViewer/DXFViewer.swift',
  'ios/CADViewer/Sources/CADViewer/DrawingCanvas.swift'
]

/**
 * Whether the code before `index` sits inside a `nonisolated` declaration.
 *
 * Approximate by design: it looks at the most recent isolation marker before the call. That
 * is enough to distinguish "read in a nonisolated helper" from "read in the view itself",
 * which is the distinction that matters.
 */
function isNonisolated(text, index) {
  const before = text.slice(0, index)
  const lastNonisolated = before.lastIndexOf('nonisolated')
  if (lastNonisolated < 0) return false
  const lastMainActor = before.lastIndexOf('@MainActor')
  return lastNonisolated > lastMainActor
}

const problems = []
let inspected = 0

for (const file of uiFiles) {
  const full = path.join(root, file)
  if (!fs.existsSync(full)) continue
  const text = fs.readFileSync(full, 'utf8')
  inspected += 1

  // Reading a whole file, which is the operation that can block.
  const patterns = [
    /Data\(contentsOf:\s*[A-Za-z_][\w.]*\)/g,
    /PDFDocument\(url:\s*[A-Za-z_][\w.]*\)/g
  ]
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      if (isNonisolated(text, match.index)) continue
      const line = text.slice(0, match.index).split('\n').length
      problems.push(`${file}:${line} ${match[0]} runs on the main actor`)
    }
  }
}

console.log(`inspected ${inspected} UI files`)
if (problems.length > 0) {
  console.error(`BLOCKING ${problems.length}:`)
  for (const problem of problems) console.error(`  ${problem}`)
  console.error('move the work into a nonisolated helper')
  process.exit(1)
}
console.log('no blocking file reads in the UI layer')
