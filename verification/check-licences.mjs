#!/usr/bin/env node
// Checks that the notices match what the app actually ships.
//
// A licence that does not travel with the code is not honoured, and the failure is legal rather
// than technical — nothing crashes, nothing looks wrong, and the omission is discovered by
// whoever reads the terms later. This repository bundles a GPL-3.0 WebAssembly engine, so the
// stakes here are higher than for most of what the checks cover.
//
//   node verification/check-licences.mjs [--require-bundle]

import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = join(here, '..')
const notices = readFileSync(join(repo, 'THIRD-PARTY-NOTICES.md'), 'utf8')
const requireBundle = process.argv.includes('--require-bundle')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// 1. Every licence file the notices point at has to be in the bundle.
const claimed = [...notices.matchAll(/`(assets\/[^`]*(?:LICENSE|NOTICE)[^`]*)`/g)].map(m => m[1])
check(claimed.length > 0, `the notices point at ${claimed.length} licence file(s)`)

// 2. Every direct dependency has to be named somewhere in the notices — shipped or development.
//    A dependency nobody wrote down is one nobody assessed.
const packageJson = JSON.parse(readFileSync(join(repo, 'ios/web/package.json'), 'utf8'))
const runtime = Object.keys(packageJson.dependencies ?? {})
const dev = Object.keys(packageJson.devDependencies ?? {})
check(runtime.length > 0, `the web bundle has ${runtime.length} runtime dependency(ies)`)

for (const name of [...runtime, ...dev]) {
  // A scoped package is listed by its scope's project name in the notices more often than by the
  // full path, so either form counts.
  const short = name.replace(/^@[^/]+\//, '')
  check(
    notices.includes(name) || notices.includes(short),
    `${name} is named in THIRD-PARTY-NOTICES.md`
  )
}

// 3. A copyleft licence has to be called out as one rather than listed quietly: it changes what
//    a reader may do with their own build, and burying it in a table is how that gets missed.
const copyleft = notices.match(/GPL-3\.0/g) ?? []
check(copyleft.length > 0, `GPL-3.0 is named ${copyleft.length} time(s) in the notices`)
check(
  /What GPL-3\.0 means here/.test(notices),
  'and the notices say what it means for someone shipping this'
)

// 4. The bundle, when there is one.
const dist = join(repo, 'ios/web/dist')
if (!existsSync(dist)) {
  if (requireBundle) {
    console.log('FAIL  the bundle is not built, and this run requires it')
    process.exit(1)
  }
  console.log('SKIPPED: the bundle is not built (run `npm run build` in ios/web)')
  process.exit(77)
}

for (const path of claimed) {
  const file = join(dist, path)
  check(existsSync(file), `${path} is in the bundle, as the notices say`)
  if (existsSync(file)) {
    const text = readFileSync(file, 'utf8')
    check(text.length > 200, `${path} has licence text in it, not a placeholder`)
    // The file has to be the licence it is named for.
    if (/LibreDWG/.test(path)) {
      check(/GNU GENERAL PUBLIC LICENSE|GPL/.test(text), 'the LibreDWG file holds the GPL text')
    }
  }
}

// 5. A bundled asset with no notice is the failure this exists for. Everything in `assets/` that
//    is third-party code should be accounted for by one of the entries above.
const assets = readdirSync(join(dist, 'assets')).filter(f => f.endsWith('.js') || f.endsWith('.wasm'))
const accountedFor = assets.filter(file => {
  if (/LICENSE/i.test(file)) return true
  // The entry bundle and the engine are named in the notices; the chunks named after a library
  // are that library.
  return notices.includes(file) || /^(index|libredwg-web|three|mtext|data-model)/.test(file)
})
check(
  accountedFor.length === assets.length,
  `every bundled asset is accounted for (${accountedFor.length} of ${assets.length})`
)
for (const file of assets.filter(f => !accountedFor.includes(f))) {
  check(false, `assets/${file} ships but no notice mentions it`)
}

if (failures.length > 0) {
  console.log(`\n${failures.length} licensing problem(s)`)
  process.exit(1)
}
console.log('\nthe notices match what the app ships')
