#!/usr/bin/env node
// Checks that the PDF view is configured for reading a drawing.
//
// `PDFView`'s defaults are for reading a document — one page at a time, with a gap between pages
// so you can see where one ends. A drawing is the opposite: often one sheet split across several
// pages, read as a continuous whole. Four settings are the difference, and three of them are
// wrong by default:
//
//   displayMode           .singlePageContinuous, so scrolling moves through the sheets
//   displayDirection      .vertical, the way a drawing is longer than it is wide
//   displaysPageBreaks    false, or a grey band interrupts the drawing between pages
//   autoScales            the reader's choice, toggled from the toolbar
//
//   node verification/check-pdf-reading-setup.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(
  join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer', 'PDFViewer.swift'),
  'utf8'
)

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// Only the code that configures a real view counts; a mention in a comment is not a setting.
const code = source
  .split('\n')
  .filter(line => !line.trim().startsWith('//'))
  .join('\n')

check(/view\.displayMode\s*=\s*\.singlePageContinuous/.test(code),
  'scrolling moves through the sheets, rather than one page at a time')
check(/view\.displayDirection\s*=\s*\.vertical/.test(code),
  'the sheets stack the way a drawing is read')
check(/view\.displaysPageBreaks\s*=\s*false/.test(code),
  'no grey band between the sheets of one drawing')
check(/view\.autoScales\s*=/.test(code),
  'the fit setting is driven by the reader, not left at its default')

// The pinch range has to come from a measured view, which is checked elsewhere; here it is only
// worth confirming the view gets limits at all.
check(/minScaleFactor\s*=/.test(code) && /maxScaleFactor\s*=/.test(code),
  'the pinch range is set from the fit scale')

if (failures.length > 0) {
  console.log(`\n${failures.length} setting(s) still at their document-reading default`)
  process.exit(1)
}
console.log('\nthe PDF view is set up to read a drawing')
