#!/usr/bin/env node
// Checks that a viewer's identity is the file it opened, not the file's name.
//
// Each viewer is given `.id(…)` so SwiftUI rebuilds it for a new drawing: its `@State` model
// holds a web view or a pdf document, and reusing the instance keeps the previous one on screen.
// The identity used to be the file name, so opening `drawings/plan.dwg` and then
// `archive/plan.dwg` left the first drawing displayed — the `.id` was unchanged, so nothing was
// rebuilt, and the second file never appeared.
//
//   node verification/check-viewer-identity.mjs

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

// Every `.id(…)` that identifies a viewer, with what it is given.
// `.id(…)` as a line, because the argument contains parentheses of its own —
// `ViewerID(file: …, open: …)` — and a bracket-matching pattern split one call into two.
const ids = root
  .split('\n')
  .filter(line => /^\s*\.id\(/.test(line))
  .map(line => line.trim().replace(/^\.id\(/, '').replace(/\)$/, '').trim())
check(ids.length === 3, `three viewers are identified (${ids.length} found)`)

for (const id of ids) {
  // A bare name is the bug. A URL is what a viewer's identity has to be.
  check(!/^(name|fileName|drawing\.name)$/.test(id), `.id(${id}) is not a bare file name`)

  // And the identity has to change when the same file is opened twice. Without the open counter
  // a drawing edited on disk and reopened here showed the version from before the edit: the id
  // was unchanged, so SwiftUI kept the viewer and its loaded page. For DWG and PDF the reset and
  // the reopen happen in one run loop tick, so nothing rendered the intermediate state that would
  // have forced a rebuild.
  check(/open:\s*openCount/.test(id), `.id(${id}) changes on every open`)
}

// A URL identity has to be standardised, or the same file reached two ways is two identities.
for (const id of ids.filter(i => i.endsWith('.standardizedFileURL'))) {
  check(true, `.id(${id}) is standardised`)
}
for (const id of ids.filter(i => i === 'url')) {
  check(false, `.id(url) is not standardised, so two paths to one file differ`)
}

// The loaded drawing has to carry where it came from, which is what `.id(drawing.source)` reads.
const loader = readFileSync(
  join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer', 'DrawingLoader.swift'),
  'utf8'
)
check(/var source: URL/.test(loader), 'a loaded drawing records its source')
check(/source: url\.standardizedFileURL/.test(loader), 'and records it standardised')

if (failures.length > 0) {
  console.log(`\n${failures.length} identity problem(s)`)
  process.exit(1)
}
console.log(`\nevery viewer is identified by the file it opened`)
