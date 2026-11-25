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
 * Whether the call at `index` sits inside a `nonisolated` declaration.
 *
 * The previous version looked at the most recent isolation marker before the call, which is
 * wrong across a boundary: a main-actor method after a nonisolated one inherits the earlier
 * marker and its reads are skipped. That is how a synchronous read placed in a
 * `UIViewRepresentable`'s `makeUIView` reported as nonisolated — `makeUIView` carries no
 * `@MainActor` of its own, the protocol supplies it.
 *
 * This walks back through the braces instead, so the nearest enclosing declaration decides.
 */
function isNonisolated(text, index) {
  let depth = 0
  for (let i = index - 1; i > 0; i -= 1) {
    const c = text[i]
    if (c === '}') depth += 1
    else if (c === '{') {
      if (depth > 0) {
        depth -= 1
        continue
      }
      // The opening brace of an enclosing scope: read the declaration that starts it.
      const header = text.slice(Math.max(0, i - 400), i)
      const line = header.slice(header.lastIndexOf(String.fromCharCode(10)) + 1)
      return /nonisolated/.test(line)
    }
  }
  return false
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

// A check that inspected nothing is not a passing check.
if (inspected === 0) {
  console.error('no UI files found; the paths are wrong')
  process.exit(1)
}

console.log(`inspected ${inspected} UI files`)
if (problems.length > 0) {
  console.error(`BLOCKING ${problems.length}:`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log('no blocking file reads in the UI layer')
