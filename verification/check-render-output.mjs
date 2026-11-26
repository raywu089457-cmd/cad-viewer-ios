#!/usr/bin/env node
// Checks what the DXF renderer actually produces, not just that it produced something.
//
// `scenecheck --svg` has existed since the harness was built and no check ever ran it. The DXF
// path is the one format whose rendering is entirely this project's own code — the other two hand
// their drawing to PDFKit and to a bundled engine — so it is the one where a wrong coordinate or a
// dropped colour is this project's bug.
//
//   node verification/check-render-output.mjs <scenecheck binary> <fixture.dxf> <snapshot.svg>

import { execFileSync } from 'node:child_process'
import { readFileSync, existsSync } from 'node:fs'

const [binary, fixture, snapshot, runner] = process.argv.slice(2)
// A `.wasm` build has to go through the WASI runner; a native binary runs directly. Both forms
// are used — CI builds natively on Linux, the machine here builds for wasm.
const viaWasm = binary.endsWith('.wasm')
if (!binary || !fixture || !snapshot) {
  console.error('usage: node check-render-output.mjs <scenecheck> <fixture.dxf> <snapshot.svg>')
  process.exit(2)
}
if (!existsSync(binary)) {
  console.error(`no scenecheck binary at ${binary}`)
  process.exit(2)
}

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// stdin rather than `--file`: the wasm build's Foundation cannot open a path, and this check has
// to run wherever the harness does.
const args = viaWasm ? [runner ?? 'runwasm.mjs', binary, '--svg'] : [binary, '--svg']
const command = viaWasm ? process.execPath : binary
const svgOutput = execFileSync(command, args, {
  input: readFileSync(fixture),
  encoding: 'utf8'
})
// The tool prints its diagnostics first; the document starts at `<svg`.
const svg = svgOutput.slice(svgOutput.indexOf('<svg '))

// The document, then the shapes in it.
check(/^<svg /m.test(svg), 'the output is an SVG document')
check(/viewBox="[-\d. ]+"/.test(svg), 'and has a view box, so it can be scaled')

const paths = [...svg.matchAll(/<path d="([^"]+)"/g)].map(m => m[1])
const fixtureText = readFileSync(fixture, 'utf8')

// The fixture is two circles and two lines. Circles are tessellated into closed paths and lines
// into two-point paths, so the counts are the thing that can be stated without reimplementing the
// reader.
const closed = paths.filter(d => /Z\s*$/.test(d)).length
const open = paths.filter(d => !/Z\s*$/.test(d)).length
const circles = (fixtureText.match(/^CIRCLE$/gm) ?? []).length
const lines = (fixtureText.match(/^LINE$/gm) ?? []).length

check(
  closed === circles,
  `${closed} closed path(s) for ${circles} CIRCLE entit(ies) in the fixture`
)
check(open === lines, `${open} open path(s) for ${lines} LINE entit(ies)`)

// A path with no coordinates is a shape that draws nothing, which an element count would miss.
for (const [index, d] of paths.entries()) {
  check(/[-\d]/.test(d), `path ${index} carries coordinates`)
}

// The colours come from the ACI table. Every path has a stroke; a missing one is an invisible
// drawing, which no geometry check would notice because the geometry is right.
const stroked = [...svg.matchAll(/<path [^>]*stroke="(#[0-9a-fA-F]{6}|none)"/g)]
check(
  stroked.length === paths.length,
  `every path has a stroke attribute (${stroked.length} of ${paths.length})`
)
check(
  !stroked.some(m => m[1] === 'none'),
  'and no path is stroke-less, which would draw nothing'
)

// The fixture sits between these corners; a transform that lost them would still produce a
// plausible-looking document.
const numbers = [...svg.matchAll(/-?\d+\.\d+/g)].map(m => Number(m[0]))
const extent = numbers.length > 0 ? Math.max(...numbers.map(Math.abs)) : 0
check(extent > 100 && extent < 100000, `the coordinates are in drawing units (max ${extent.toFixed(1)})`)

// The output has to be stable, or a rendering change is invisible: the snapshot is what says so.
if (existsSync(snapshot)) {
  const committed = readFileSync(snapshot, 'utf8')
  check(svg === committed, 'the output matches the committed snapshot')
  if (svg !== committed) {
    console.log('      the snapshot needs regenerating if the change was intended:')
    console.log(`      node -e "…" > ${snapshot}`)
  }
} else {
  check(false, `${snapshot} does not exist, so nothing is compared against`)
}

if (failures.length > 0) {
  console.log(`\n${failures.length} rendering problem(s)`)
  process.exit(1)
}
console.log(`\nthe renderer produced ${paths.length} path(s) and they are all drawable`)
