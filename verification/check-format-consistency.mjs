#!/usr/bin/env node
// Checks that the three places a file format is declared agree.
//
// A format has to appear in three places to be openable:
//
//   1. `DrawingKind` — decides which engine draws it. A format missing here reaches
//      `.unsupported` and the app refuses a file it was built for.
//   2. `Info.plist` — makes the app appear in the share sheet and Files for that type. Missing
//      here, the file can still be dragged in but the app never offers itself.
//   3. `RootView.allowedTypes` — what the document picker lets the reader select. Missing here,
//      the format is openable in principle and greyed out in the picker, with nothing to say why.
//
// Each of the three has drifted from the others at some point in this file's history, and none of
// the checks looked at more than one at a time.
//
//   node verification/check-format-consistency.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const read = p => readFileSync(join(here, '..', p), 'utf8')

const routing = read('ios/DXFGeometry/Sources/DXFGeometry/FileRouting.swift')
const plist = read('ios/CADViewer/Info.plist')
const root = read('ios/CADViewer/Sources/CADViewer/RootView.swift')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// 1. The formats the router draws.
const drawn = new Set(
  [...routing.matchAll(/case "([a-z0-9]+)": self = \.(\w+)/g)]
    .filter(m => m[2] !== 'unsupported')
    .map(m => m[1])
)
check(drawn.size === 3, `the router draws three formats (${[...drawn].join(', ')})`)

// 2. What the plist claims the app can open: the document types it registers plus any UTIs it
//    declares itself.
const documentTypes = new Set(
  [...plist.matchAll(/<key>LSItemContentTypes<\/key>\s*<array>([\s\S]*?)<\/array>/g)]
    .flatMap(m => [...m[1].matchAll(/<string>([^<]+)<\/string>/g)].map(x => x[1]))
)
const imported = new Set(
  [...plist.matchAll(/<key>UTTypeIdentifier<\/key>\s*<string>([^<]+)<\/string>/g)].map(m => m[1])
)
const declaredUTIs = new Set([...documentTypes, ...imported])

// The extensions each declared UTI stands for.
const plistExtensions = new Map()
for (const m of plist.matchAll(
  /<key>UTTypeIdentifier<\/key>\s*<string>([^<]+)<\/string>[\s\S]*?<key>public\.filename-extension<\/key>\s*<array>([\s\S]*?)<\/array>/g
)) {
  for (const ext of [...m[2].matchAll(/<string>([^<]+)<\/string>/g)]) {
    plistExtensions.set(ext[1], m[1])
  }
}
// A system UTI (`com.adobe.pdf`) carries its own tag; the extension is the last component.
for (const uti of documentTypes) {
  if (plistExtensions.has(uti)) continue
  const guess = uti.split('.').pop()
  if (!plistExtensions.has(guess)) plistExtensions.set(guess, uti)
}

for (const ext of drawn) {
  check(plistExtensions.has(ext), `Info.plist declares .${ext}, which the router draws`)
}

// 3. What the picker offers.
const allowed = new Set(
  [...root.matchAll(/"(com\.[a-z.]+)"/g)].map(m => m[1]).filter(u => u.startsWith('com.'))
)
for (const [ext, uti] of plistExtensions) {
  check(allowed.has(uti), `the picker offers ${uti} for .${ext}`)
  check(declaredUTIs.has(uti), `${uti} is a type the plist names`)
}

// And in the other direction: nothing is offered that no engine draws.
for (const [ext, uti] of plistExtensions) {
  if (drawn.has(ext)) continue
  check(false, `Info.plist declares .${ext} (${uti}) but the router does not draw it`)
}

check(drawn.size === plistExtensions.size && drawn.size === allowed.size,
  `all three lists are the same size (${drawn.size} drawn, ${plistExtensions.size} declared, ${allowed.size} offered)`)

if (failures.length > 0) {
  console.log(`\n${failures.length} inconsistency(ies) between the three format lists`)
  process.exit(1)
}
console.log(`\n${drawn.size} formats agree across the router, the plist and the picker`)
