#!/usr/bin/env node
// Checks that the three viewers fill the same space.
//
// PDF called `ignoresSafeArea(edges: .bottom)` from the day it was written; DXF and DWG did not.
// The same drawing therefore sat differently depending on its format — a strip of it cut off at
// the home indicator in two of the three, while the third ran to the bottom of the screen.
//
// There is a second half to it. On the DXF reader the modifier has to sit on the `GeometryReader`,
// not on the canvas inside it: the canvas would extend under the indicator while `proxy.size` —
// which `fit` frames the drawing into — still excluded that strip, so the drawing would be scaled
// to fit a space it no longer occupied.
//
//   node verification/check-safe-area.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const app = name => join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer', name)
const CR = String.fromCharCode(13)
const read = name => readFileSync(app(name), 'utf8').split(CR + String.fromCharCode(10)).join('\n')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

for (const file of ['DXFViewer.swift', 'DWGViewer.swift', 'PDFViewer.swift']) {
  const text = read(file)
  check(
    /\.ignoresSafeArea\(edges: \.bottom\)/.test(text),
    `${file} lets the drawing reach the bottom of the screen`
  )
  // The top stays inside the navigation bar, which is where the title and buttons are.
  check(
    !/\.ignoresSafeArea\(edges: \.top\)/.test(text),
    `${file} keeps the navigation bar where it is`
  )
}

// The DXF reader's modifier has to be outside the GeometryReader, or `proxy.size` and the painted
// area disagree.
const dxf = read('DXFViewer.swift')
const geometryAt = dxf.indexOf('GeometryReader { proxy in')
const modifierAt = dxf.indexOf('.ignoresSafeArea(edges: .bottom)')
check(geometryAt >= 0, 'the DXF reader measures its space with a GeometryReader')
check(
  modifierAt > geometryAt,
  'and the safe-area modifier is outside it, so the measured size matches the painted one'
)
// Anything that reads `proxy.size` has to be inside, which it is by construction; the check that
// matters is that the modifier comes after the closing brace of the reader.
if (geometryAt >= 0 && modifierAt > geometryAt) {
  const between = dxf.slice(geometryAt, modifierAt)
  const opens = (between.match(/{/g) ?? []).length
  const closes = (between.match(/}/g) ?? []).length
  check(
    opens === closes,
    'the modifier is applied after the reader closes, not inside it'
  )
}

if (failures.length > 0) {
  console.log(`\n${failures.length} viewer(s) do not fill the same space`)
  process.exit(1)
}
console.log('\nall three viewers fill the screen the same way')
