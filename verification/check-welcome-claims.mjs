#!/usr/bin/env node
// Checks that the welcome screen describes what the app actually does.
//
// The first screen is the only place the app explains itself, and one of its three lines was
// wrong in a way that matters: it said PDF "opens in the system reader", while the viewer embeds
// PDFKit and draws its own continuous, gap-free pages with a fit toggle. A reader would have
// expected a different app to open.
//
// Only claims that map to code are checked. A claim about how something feels is not.
//
//   node verification/check-welcome-claims.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const app = name => join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer', name)

const root = readFileSync(app('RootView.swift'), 'utf8')
const dxf = readFileSync(app('DXFViewer.swift'), 'utf8')
const dwg = readFileSync(app('DWGViewer.swift'), 'utf8')
const pdf = readFileSync(app('PDFViewer.swift'), 'utf8')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// The three lines the welcome screen shows, and the code each one describes.
const welcome = root.match(/private var welcome:[\s\S]*?\n    \}/)
check(welcome !== null, 'the welcome screen exists')
const text = welcome ? welcome[0] : ''

check(/Open a DXF, DWG or PDF file/.test(text), 'it names the three formats it opens')

// DXF: "drawn natively, with pinch, pan and fit."
check(/DXF/.test(text), 'it mentions DXF')
check(
  /MagnifyGesture/.test(dxf) && /DragGesture/.test(dxf) && /fit\(to:/.test(dxf),
  'and DXF really has pinch, pan and fit'
)

// DWG: "uses a bundled engine, so it takes a moment to start."
check(/DWG/.test(text), 'it mentions DWG')
check(
  /ViewerSchemeHandler/.test(dwg) && /Preparing the DWG engine/.test(dwg),
  'and DWG really bundles an engine and waits for it'
)

// PDF: this is the one that was wrong. The claim is now about continuous pages and a fit toggle,
// so those are what have to be true. The old sentence is checked against too, because "opens in
// the system reader" would now be a contradiction rather than a stale fact.
check(/PDF/.test(text), 'it mentions PDF')
check(
  !/system reader/.test(text),
  'and does not claim PDF opens in another app, which the embedded viewer contradicts'
)
check(
  /singlePageContinuous/.test(pdf) && /displaysPageBreaks = false/.test(pdf),
  'and PDF really reads continuously with no page gap'
)
check(/autoScales\.toggle/.test(pdf), 'and really offers a fit toggle')

if (failures.length > 0) {
  console.log(`\n${failures.length} claim(s) on the welcome screen the code does not support`)
  process.exit(1)
}
console.log('\nthe welcome screen describes what the app does')
