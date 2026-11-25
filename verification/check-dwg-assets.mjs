#!/usr/bin/env node
// Checks that every asset the DWG page asks for is in the built bundle.
//
// The page names two worker files by path. They are copied by `vite.config.js`, not imported, so
// nothing in the module graph knows they are needed: a change to the copy step produces a bundle
// that loads, reports ready, and then fails the first time a drawing has multi-line text or needs
// the DWG parser on a worker. The failure is a console error inside a web view, which is the
// hardest place to see one.
//
//   node verification/check-dwg-assets.mjs [--require-bundle]

import { readFileSync, existsSync, statSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = join(here, '..')
const dist = join(repo, 'ios/web/dist')
const requireBundle = process.argv.includes('--require-bundle')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// What the page asks for at runtime, read out of the source rather than restated: a worker added
// without a check would be exactly the case this exists for.
const source = readFileSync(join(repo, 'ios/web/src/main.js'), 'utf8')
const wanted = [...source.matchAll(/'(\.\/assets\/[^']+\.(?:js|wasm))'/g)].map(m => m[1])
check(wanted.length > 0, `the page names ${wanted.length} bundled asset(s)`)

if (!existsSync(dist)) {
  if (requireBundle) {
    console.log('FAIL  the bundle is not built, and this run requires it')
    process.exit(1)
  }
  console.log('SKIPPED: the bundle is not built (run `npm run build` in ios/web)')
  process.exit(77)
}

for (const path of wanted) {
  const file = join(dist, path.replace(/^\.\//, ''))
  const there = existsSync(file)
  check(there, `${path} is in the bundle`)
  if (there) {
    // A zero-byte worker is in the bundle and useless, which is a worse state than absent: it is
    // found by every existence check and fails at runtime.
    check(statSync(file).size > 1024, `${path} is a real file, not an empty placeholder`)
  }
}

// The engine itself. `WebAssembly.instantiateStreaming` needs this to be `application/wasm`, which
// `check-mime-coverage` covers; here it only has to be present and plausible.
const wasm = join(dist, 'assets/libredwg-web.wasm')
check(existsSync(wasm), 'the LibreDWG engine is in the bundle')
if (existsSync(wasm)) {
  check(statSync(wasm).size > 1_000_000, 'the engine is the real binary, not a stub')
  // A wasm module starts with `\0asm`; a 200 response carrying an error page would not.
  const head = readFileSync(wasm).subarray(0, 4)
  check(
    head[0] === 0x00 && head[1] === 0x61 && head[2] === 0x73 && head[3] === 0x6d,
    'the engine file is a wasm module'
  )
}

// And the HTML has to load the entry script, or the page is a blank document that reports nothing.
const html = readFileSync(join(dist, 'index.html'), 'utf8')
check(/<script[^>]+src="[^"]*\.js"/.test(html), 'the page loads a script')
check(/id="status"/.test(html), 'and has the element its status messages write to')

if (failures.length > 0) {
  console.log(`\n${failures.length} asset(s) the page needs are missing or wrong`)
  process.exit(1)
}
console.log(`\nevery asset the DWG page asks for is in the bundle`)
