#!/usr/bin/env node
// Catches literal control characters where a Swift escape was meant.
//
// Writing Swift through a Node here-doc has repeatedly turned a backslash-n into a real newline
// inside a string literal, and a backslash-t into a real tab. The file then fails to compile with
// "unterminated string literal" — but only on CI, because the local harness compiles a copy of the
// geometry sources and does not build the test targets at all. Two of these got through before
// anyone noticed, and both times CI was the thing that found it.
//
// The rule: no raw tab, carriage return, form feed or vertical tab inside a single-line Swift
// string literal. Multi-line literals (triple quote) are exempt — a newline there is the point.

import { readFileSync, readdirSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const root = process.cwd()
const targets = [
  'ios/DXFGeometry/Sources/DXFGeometry',
  'ios/DXFGeometry/Tests/DXFGeometryTests',
  'ios/CADViewer/Sources/CADViewer',
  'ios/CADViewer/Tests/CADViewerTests',
  'verification/dxf-geometry-harness/Sources',
]

function walk(dir, out = []) {
  let entries
  try {
    entries = readdirSync(dir)
  } catch {
    return out
  }
  for (const name of entries) {
    const full = join(dir, name)
    if (statSync(full).isDirectory()) walk(full, out)
    else if (name.endsWith('.swift')) out.push(full)
  }
  return out
}

// Count of double quotes that are not backslash-escaped.
function unescapedQuotes(text) {
  let count = 0
  for (let i = 0; i < text.length; i += 1) {
    if (text[i] === '\\') {
      i += 1
      continue
    }
    if (text[i] === '"') count += 1
  }
  return count
}

const problems = []
let scanned = 0

for (const target of targets) {
  for (const file of walk(join(root, target))) {
    scanned += 1
    const lines = readFileSync(file, 'utf8').split(/\r?\n/)
    let inMultiline = false

    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i]

      // Triple-quoted blocks may contain anything, including real newlines.
      const triple = (line.match(/"""/g) || []).length
      if (inMultiline) {
        if (triple % 2 === 1) inMultiline = false
        continue
      }
      if (triple % 2 === 1) {
        inMultiline = true
        continue
      }

      const body = line.replace(/^[ \t]+/, '')

      const control = body.match(/[\t\v\f\r]/)
      if (control) {
        const at = body.indexOf(control[0])
        const before = body.slice(0, at)
        if (unescapedQuotes(before) % 2 === 1) {
          problems.push(
            `${relative(root, file)}:${i + 1}: a raw ${JSON.stringify(control[0])} inside a ` +
              'string literal — write the Swift escape instead'
          )
        }
      }

      // An odd number of quotes means the literal never closes on that line. Comments are
      // stripped from the end so an apostrophe or quote in prose cannot trip it.
      const code = body.split('//')[0]
      if (unescapedQuotes(code) % 2 === 1) {
        problems.push(
          `${relative(root, file)}:${i + 1}: an odd number of quotes — the literal runs off the line`
        )
      }
    }
  }
}

if (problems.length > 0) {
  console.error(`${problems.length} raw character(s) where a Swift escape was meant:`)
  for (const problem of problems.slice(0, 20)) console.error(`  ${problem}`)
  process.exit(1)
}

console.log(`${scanned} Swift file(s) have no raw control characters inside a string literal`)
