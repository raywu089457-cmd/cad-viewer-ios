// Checks that the UI layer does not read files on the main actor.
//
// The viewers are @MainActor or @Observable, so a synchronous read inside them runs on the main
// thread. A real DWG is routinely tens of megabytes and a PDF of a drawing is not small either:
// reading one there freezes the interface for the whole read, including the spinner that exists
// to say the file is loading. This is invisible in a screenshot and in any test that does not
// measure responsiveness, which is why it is checked mechanically.
//
//   node check-main-thread-io.mjs
import { readdirSync, readFileSync as read, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..')
const appDir = join(root, 'ios/CADViewer/Sources/CADViewer')

/**
 * Every file in the app layer.
 *
 * This used to be a hand-written list of five files out of seven. `ViewerSchemeHandler.swift` was
 * outside it and read the ten-megabyte engine synchronously on the main thread from
 * `WKURLSchemeHandler`, which WebKit calls there — the same defect the viewers had, in the file
 * nobody looked at. A list of files to check will always be one file out of date.
 */
const uiFiles = readdirSync(appDir)
  .filter(file => file.endsWith('.swift'))
  .map(file => join(appDir, file))

/**
 * Whether the call at `offset` sits inside a `nonisolated` declaration.
 *
 * Walks back line by line, tracking brace depth, and stops at the first declaration it meets with
 * no unclosed block between it and the call. Two earlier versions of this got it wrong in
 * instructive ways:
 *
 * - The first looked at the nearest isolation marker anywhere before the call. Across a boundary
 *   that is wrong: a main-actor method following a nonisolated one inherits the earlier marker.
 * - The second walked to the first `{` and read that line. `do`, `if` and `for` open a brace too,
 *   and when the brace is on its own line the line read as `do` — so a read inside `do { … }` in a
 *   nonisolated function reported as main-actor.
 *
 * This one reads the enclosing declaration, which is what the question actually asks.
 */
function isNonisolated(text, offset) {
  const lines = text.slice(0, offset).split('\n')
  // The nearest member-level declaration, which is the function the call belongs to. Local
  // declarations inside it are indented deeper and are skipped by the indent limit.
  //
  // Brace counting was tried and is wrong here: `defer { … }`, `if { … }` and a `do {` whose brace
  // is on its own line all made the depth disagree with what was being looked for.
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const raw = lines[i]
    const indent = raw.length - raw.trimStart().length
    if (indent > 8) continue
    const statement = raw.trim()
    if (!/^(nonisolated\s+)?(public\s+|private\s+|fileprivate\s+|static\s+|final\s+|@\w+\s+)*(func|init)\b/.test(statement)) {
      continue
    }
    // Attributes sit on the lines just above the declaration.
    const above = lines.slice(Math.max(0, i - 3), i + 1).join('\n')
    return /\bnonisolated\b/.test(above)
  }
  return false
}

const problems = []
let inspected = 0

for (const file of uiFiles) {
  if (!existsSync(file)) continue
  const text = read(file, 'utf8')
  inspected += 1

  // Reading a whole file, which is the operation that can block.
  const patterns = [
    /Data\(contentsOf:\s*[A-Za-z_][\w.]*\)/g,
    /PDFDocument\(url:\s*[A-Za-z_][\w.]*\)/g
  ]
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      if (isNonisolated(text, match.index)) continue
      // A read handed to a background queue does not block the caller, whatever the caller's
      // isolation. Looking back a short way for the queue is enough: the closure is always opened
      // within a few lines of the read it contains.
      const window = text.slice(Math.max(0, match.index - 400), match.index)
      if (/DispatchQueue\.global\([^)]*\)\.async|Task\.detached/.test(window)) continue
      const line = text.slice(0, match.index).split('\n').length
      problems.push(`${file.slice(root.length + 1)}:${line} ${match[0]} runs on the main actor`)
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
