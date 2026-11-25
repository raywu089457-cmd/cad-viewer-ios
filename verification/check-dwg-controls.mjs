#!/usr/bin/env node
// Checks that every entry point Swift calls on the DWG page is one the page defines.
//
// `window.cadOpenDwg` did not exist for a while: the page only exposed `cadReload`, so Swift's
// optional-chained call did nothing and a second DWG silently never opened. Nothing caught it,
// because the page still reported `ready`. Adding a zoom-to-fit button is the same shape of
// risk — a native call into a name the page never defined.
//
//   node verification/check-dwg-controls.mjs

import { readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = join(here, '..')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

const page = readFileSync(join(repo, 'ios/web/src/main.js'), 'utf8')
const swift = readFileSync(
  join(repo, 'ios/CADViewer/Sources/CADViewer/DWGViewer.swift'),
  'utf8'
)

// What the page publishes.
const defined = new Set([...page.matchAll(/window\.(cad[A-Za-z0-9_]*)\s*=/g)].map(m => m[1]))
check(defined.size >= 2, `the page publishes ${[...defined].join(', ')}`)

// What Swift calls. Both the optional-chained form and the plain one.
const called = new Set(
  [...swift.matchAll(/window\.(cad[A-Za-z0-9_]*)\s*\??\.?\(/g)].map(m => m[1])
)
check(called.size > 0, `Swift calls ${[...called].join(', ') || 'nothing'}`)

for (const name of called) {
  check(defined.has(name), `the page defines ${name}, which Swift calls`)
}

// A published name that nothing calls is not an error, but it is worth knowing about: it is
// either dead or a call site that was renamed on one side.
const uncalled = [...defined].filter(name => !called.has(name))
if (uncalled.length > 0) console.log(`      published but not called from Swift: ${uncalled.join(', ')}`)

// And the built bundle has to contain them, or the source and what ships disagree.
const dist = join(repo, 'ios/web/dist')
if (existsSync(dist)) {
  const bundles = readFileSync(join(dist, 'index.html'), 'utf8')
  const scripts = [...bundles.matchAll(/src="\.?\/?([^"]+\.js)"/g)].map(m => m[1])
  const built = scripts.map(s => readFileSync(join(dist, s), 'utf8')).join('\n')
  for (const name of defined) {
    check(built.includes(name), `${name} is in the built bundle`)
  }
} else {
  console.log('      the bundle is not built; source only')
}

if (failures.length > 0) {
  console.log(`\n${failures.length} entry point(s) called but not defined`)
  process.exit(1)
}
console.log(`\nevery DWG entry point Swift calls exists on the page`)
