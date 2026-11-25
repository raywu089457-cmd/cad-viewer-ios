#!/usr/bin/env node
// Checks the PDF fixtures against the verdict the viewer would reach.
//
// There was no PDF fixture at all: the verdict was tested with made-up page counts, and nothing
// established that a real file reaches those counts. These two files are what a reader would
// hand the app — one that opens, one that parses to nothing — and the check asks each what the
// viewer would say.
//
//   node verification/check-pdf-fixtures.mjs

import { readFileSync } from 'node:fs'

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

/// The page count a PDF declares, read the way PDFKit would at its simplest: the `/Count` of
/// the root page tree. Enough for these fixtures, and it says so rather than pretending to be a
/// PDF parser.
function declaredPageCount(bytes) {
  const text = bytes.toString('latin1')
  if (!text.startsWith('%PDF-')) return null
  if (!/\/Type\s*\/Catalog/.test(text)) return null
  const count = text.match(/\/Type\s*\/Pages[^>]*\/Count\s+(\d+)/)
  if (!count) return null
  // A tree whose `/Count` disagrees with its `/Kids` is malformed; PDFKit honours `/Count`, and
  // these fixtures are built so the two agree.
  return Number(count[1])
}

// The same decision the app makes, imported rather than restated. It lives in a Swift file, so
// the rule is read from the source: a copy here would be a second definition to keep in step.
const swift = readFileSync(
  new URL('../ios/DXFGeometry/Sources/DXFGeometry/ViewerEvent.swift', import.meta.url),
  'utf8'
)
check(
  /guard pageCount > 0 else \{ return \.noPages \}/.test(swift),
  'the app treats zero pages as its own failure'
)
check(
  /guard let pageCount else \{ return \.notAPDF \}/.test(swift),
  'and a missing document as not a PDF at all'
)

const verdict = count =>
  count === null ? 'notAPDF' : count > 0 ? 'readable' : 'noPages'

const dir = new URL('./fixtures/pdf/', import.meta.url)
for (const [file, expected] of [
  ['one-page.pdf', 'readable'],
  ['no-pages.pdf', 'noPages'],
]) {
  const bytes = readFileSync(new URL(file, dir))
  const count = declaredPageCount(bytes)
  const actual = verdict(count)
  check(
    actual === expected,
    `${file} reads as ${expected} (declared count ${count}, verdict ${actual})`
  )
}

// A file that is not a PDF must not be reported as one. This is the case a reader hits by
// renaming a document, and the message says so.
const notPdf = Buffer.from('this is not a pdf at all\n', 'latin1')
check(
  verdict(declaredPageCount(notPdf)) === 'notAPDF',
  'a file that is not a PDF reads as notAPDF'
)

if (failures.length > 0) {
  console.log(`\n${failures.length} PDF fixture problem(s)`)
  process.exit(1)
}
console.log('\nPDF fixtures match the verdicts')
