#!/usr/bin/env node
// Checks that the three viewers tell a reader the same things about the file that is open.
//
// DXF has had a details sheet since it was written. DWG and PDF had nothing, so a reader could
// not find out how big the file was, how long it took, or — for a PDF — whether the sheet they
// were looking at was the whole drawing or the first of six. The app knew all of it and said none
// of it.
//
// What each format can report differs, so the check asks for what exists rather than for identical
// rows: every viewer needs a sheet reachable from the toolbar and a file size, and each one needs
// the fact only it can know.
//
//   node verification/check-details-parity.mjs

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

const viewers = {
  'DXFViewer.swift': {
    draws: 'entity counts, extents and read time',
    needs: [/drawing\.scene\.polylines\.count/, /drawing\.viewport/, /drawing\.duration/]
  },
  'DWGViewer.swift': {
    draws: 'file size and how long the engine took to draw',
    needs: [/attributesOfItem/, /renderedMilliseconds/]
  },
  'PDFViewer.swift': {
    draws: 'file size and page count',
    needs: [/attributesOfItem/, /pageCount/]
  }
}

for (const [file, { draws, needs }] of Object.entries(viewers)) {
  const text = read(file)

  // Reachable from the toolbar, or it may as well not exist.
  check(/Button\("Details"|showsDetails = true/.test(text) || /Details", systemImage/.test(text),
    `${file} can open its details from the toolbar`)
  check(/\.sheet\(isPresented: \$showsDetails\)/.test(text), `${file} presents the sheet`)
  check(/private var detailsSheet/.test(text), `${file} has a details sheet`)

  // The size is what every one of them can say.
  if (file !== 'DXFViewer.swift') {
    check(/attributesOfItem/.test(text), `${file} reports the file's size`)
  }

  // And the fact only this format knows.
  for (const pattern of needs) {
    check(pattern.test(text), `${file} reports ${draws}`)
  }
}

if (failures.length > 0) {
  console.log(`\n${failures.length} gap(s) between how the formats describe themselves`)
  process.exit(1)
}
console.log('\nevery viewer can tell a reader about the file it has open')
