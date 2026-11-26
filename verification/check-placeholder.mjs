#!/usr/bin/env node
// Checks the placeholder the DWG viewer folder ships with.
//
// The real viewer is seventeen megabytes of generated JavaScript and is not committed, so the
// resource folder SwiftPM requires holds one hand-written page instead. That page is the whole of
// what a fresh clone can show for a DWG, and it is what says "run the build script" instead of
// leaving a spinner up for forty-five seconds.
//
// It is one file, easy to delete while tidying, and nothing else would notice: the app would open
// a DWG and wait.
//
//   node verification/check-placeholder.mjs

import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = join(here, '..')
const placeholder = join(
  repo, 'ios/CADViewer/Sources/CADViewer/Resources/dwgviewer/index.html'
)

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

check(existsSync(placeholder), 'the placeholder page exists, which SwiftPM needs')
if (!existsSync(placeholder)) {
  console.log(`\n1 placeholder problem`)
  process.exit(1)
}

const text = readFileSync(placeholder, 'utf8')

// It has to report the failure rather than wait to be asked. The app waits for `ready` or `error`
// before showing anything, and a page that does neither leaves the spinner up until the timeout.
check(
  /event:\s*["']error["']/.test(text),
  'it posts an error, so the app says why instead of waiting'
)
check(
  /build-for-ios\.sh/.test(text),
  'and names the script that fixes it'
)
check(
  /webkit\.messageHandlers\.cadEvents/.test(text),
  'through the channel the app listens on'
)
// A page opened outside the app has no message handler; the try/catch is what keeps it from
// throwing before the reader can read the message on screen.
check(/catch/.test(text), 'and survives being opened in a plain browser')

// It must not claim to be ready: the app would then wait for a rendering that cannot come.
check(
  !/event:\s*["']ready["']/.test(text),
  'and does not claim to be ready, which would leave the app waiting for a drawing'
)

// The resources folder has to exist and be non-empty for SwiftPM to accept the target.
const folder = join(repo, 'ios/CADViewer/Sources/CADViewer/Resources/dwgviewer')
check(existsSync(folder), 'the resource folder exists')

if (failures.length > 0) {
  console.log(`\n${failures.length} placeholder problem(s)`)
  process.exit(1)
}
console.log('\nthe placeholder says what to run and why')
