#!/usr/bin/env node
// Checks that the root screen offers what a reader needs while a drawing is open.
//
// With only "Close" in the toolbar, switching between drawings was: tap Close, land on the welcome
// screen, tap Open, choose a file. CAD work is done across a set of sheets, so that is the common
// path rather than an edge case — and the app made it the slow one.
//
//   node verification/check-root-toolbar.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = readFileSync(
  join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer', 'RootView.swift'),
  'utf8'
)

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// The toolbar block, which is where these buttons live.
const toolbar = root.match(/\.toolbar \{([\s\S]*?)\n            \}/)
check(toolbar !== null, 'the root screen has a toolbar')

if (toolbar) {
  const body = toolbar[1]
  // Both actions while a drawing is open. `opened != nil` guards them, so they only appear when
  // there is something to close or replace.
  check(/opened != nil/.test(body), 'the buttons appear only when a drawing is open')
  check(/Button\("Close"/.test(body), 'closing is offered')
  check(
    /Button\("Open another"/.test(body),
    'opening another drawing is offered without closing first'
  )
  // The button has to set the same flag the importer reads, or it opens nothing.
  check(
    /isPickingFile = true/.test(body),
    'and the button shows the picker the importer is bound to'
  )
}

// The importer the button drives.
check(/\.fileImporter\(\s*isPresented: \$isPickingFile/.test(root), 'the picker is bound to that flag')

// A file picked while one is open has to replace it, which `open` does by calling `reset` first.
check(
  /private func open\(_ url: URL\) \{\s*\n\s*reset\(\)/.test(root),
  'opening replaces what is on screen rather than stacking it'
)

if (failures.length > 0) {
  console.log(`\n${failures.length} toolbar problem(s)`)
  process.exit(1)
}
console.log('\nthe root screen offers closing and replacing')
