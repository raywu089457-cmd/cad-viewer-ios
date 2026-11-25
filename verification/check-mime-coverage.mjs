#!/usr/bin/env node
// Checks that every file the viewer bundle actually contains has a MIME type the scheme handler
// knows.
//
// The handler serves the bundle over `cadviewer://`, and an extension it does not recognise
// becomes `application/octet-stream`, which a browser downloads instead of rendering. Nothing
// compared the table with the bundle, so an unknown extension was invisible: `.txt` was being
// served that way for two licence files.
//
//   node verification/check-mime-coverage.mjs

import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, extname, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const dist = join(here, '..', 'ios', 'web', 'dist')
const swift = join(here, '..', 'ios', 'DXFGeometry', 'Sources', 'DXFGeometry', 'BundleServing.swift')

const failures = []

// The extensions the handler names, read from the source rather than restated.
const source = readFileSync(swift, 'utf8')
const known = new Set()
for (const match of source.matchAll(/case ((?:"[a-z0-9]+"(?:, )?)+): return/g)) {
  for (const ext of match[1].matchAll(/"([a-z0-9]+)"/g)) known.add(ext[1])
}
if (known.size === 0) {
  console.log('FAIL  no MIME types could be read from BundleServing.swift')
  process.exit(1)
}

// What the bundle contains.
const found = new Map() // extension -> [file…]
const walk = dir => {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) walk(path)
    else {
      // A file with no extension is served by name and needs no table entry.
      const ext = extname(path).slice(1).toLowerCase()
      if (!ext) continue
      if (!found.has(ext)) found.set(ext, [])
      found.get(ext).push(path.slice(dist.length + 1))
    }
  }
}

try {
  walk(dist)
} catch (error) {
  // `dist/` is generated and not committed, so a fresh checkout has none. Exit 77 to say
  // "nothing was checked" rather than 1, which would claim a failure — the same convention the
  // other checks use, and the reason a skip has a code of its own.
  console.log(`SKIPPED: the bundle is not built (${error.code || error.message})`)
  console.log('         run `npm run build` in ios/web to check it')
  // On CI the bundle is built just before this runs, so a missing one there is a failure, not a
  // skip. Anywhere else it is simply not built yet.
  process.exit(process.argv.includes('--require-bundle') ? 1 : 77)
}

for (const [ext, files] of [...found].sort()) {
  if (known.has(ext)) {
    console.log(`ok    .${ext} -> ${files.length} file(s)`)
  } else {
    failures.push(`.${ext} is in the bundle but has no MIME type (${files.join(', ')})`)
    console.log(`FAIL  .${ext} -> octet-stream (${files.join(', ')})`)
  }
}

// A type declared but never produced is not an error — the bundle changes — but saying so keeps
// the table from growing entries nobody needs.
const unused = [...known].filter(ext => !found.has(ext))
if (unused.length > 0) console.log(`      declared but unused in this bundle: ${unused.join(', ')}`)

if (failures.length > 0) {
  console.log(`\n${failures.length} extension(s) would be served as octet-stream`)
  process.exit(1)
}
console.log(`\nevery extension in the bundle has a MIME type (${found.size} of ${known.size} named)`)
