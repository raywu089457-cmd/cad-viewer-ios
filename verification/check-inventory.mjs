#!/usr/bin/env node
// Checks that the README's list of checks matches what is on disk, in both directions.
//
// The directory used to hold eleven scripts that exit non-zero for historical reasons beside
// the real checks, and the README listed them together. A reader could not tell a broken check
// from a record of a past experiment, which is the same failure as a check that reports nothing:
// the signal and the noise look alike.
//
//   node verification/check-inventory.mjs

import { readdirSync, readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

const readme = readFileSync(join(here, 'README.md'), 'utf8')
const listed = new Set([...readme.matchAll(/\|\s+`([a-z0-9.-]+\.(?:mjs|sh))`/g)].map(m => m[1]))

// Everything at the top of this directory that is a check, by name — including this one, which is
// documented like any other. Excluding it from the disk side made the two counts disagree by one
// in a way that looked like a missing file.
const onDisk = readdirSync(here).filter(f => f.endsWith('.mjs') || f.endsWith('.sh'))

// Against the workflow: whatever CI runs has to be documented, and vice versa.
const workflow = readFileSync(join(here, '..', '.github', 'workflows', 'checks.yml'), 'utf8')
const run = new Set(
  // Two forms: from the repository root, and from inside a working directory such as the harness.
  [...workflow.matchAll(/(?:verification\/|\.\.\/)([a-z0-9.-]+\.(?:mjs|sh))/g)].map(m => m[1])
)

for (const file of [...listed].sort()) {
  check(existsSync(join(here, file)), `README lists ${file}, and it exists`)
}
for (const file of [...run].sort()) {
  check(listed.has(file), `CI runs ${file}, and the README lists it`)
}
// Generators run when their input changes, not on every push. Listed here so the distinction is
// visible rather than implied by an absence.
// `check-render-output` needs node and the Swift CI image has none. Kept in the tree, run by hand
// on a machine that has both, and named here so the absence is a decision rather than an oversight.
const generators = new Set(['make-pdf.mjs', 'check-render-output.mjs'])
for (const file of onDisk.sort()) {
  // A check that only runs when someone remembers to type its name is a check that stops
  // running. `check-fixture-fresh.mjs` sat on disk long after it was superseded, and
  // `check-workflow.mjs` was never wired in at all — the one that catches a workflow with no
  // jobs. Two of them, in opposite directions, both invisible.
  // Generators run when their input changes, not on every push. The exclusion is named rather
  // than implied by an absence.
  if (generators.has(file)) {
    check(listed.has(file), `${file} is a generator, and the README says so`)
    continue
  }
  check(run.has(file), `${file} runs on CI, not only by hand`)
  check(listed.has(file), `${file} is listed in the README`)
}

// A check that needs an argument cannot be run by hand the way the README implies. Either the
// README should say what it takes, or the check should find its own input.
for (const file of onDisk.filter(f => f.endsWith('.mjs'))) {
  const source = readFileSync(join(here, file), 'utf8')
  const takesArgs = /process\.argv\[2\]/.test(source) && /usage:/.test(source)
  if (!takesArgs) continue
  const documented = new RegExp(`\`${file}\`[^|]*\|[^|]*argument`).test(readme)
  check(
    documented || run.has(file),
    `${file} needs an argument, so either CI passes one or the README says which`
  )
}

// The bake-off scripts are not checks. If one is ever put in the workflow, that is a decision
// worth seeing rather than something to leave in place.
const bakeoff = readdirSync(join(here, 'engine-bakeoff')).filter(f => f.endsWith('.mjs'))
for (const file of bakeoff) {
  check(!run.has(file), `${file} stays out of CI, being a record rather than a check`)
}

// Where the skip convention is used, it should be 77. A script that skips with 1 cannot be told
// from a script that failed. This file is excluded: its own source contains the pattern it
// searches for, so it would report itself.
const skips = onDisk
  .filter(f => f !== 'check-inventory.mjs')
  .filter(f => /process\.exit\(77\)|exit 77/.test(readFileSync(join(here, f), 'utf8')))
console.log(`      ${skips.length} check(s) can skip: ${skips.join(', ') || 'none'}`)

if (failures.length > 0) {
  console.log(`\n${failures.length} inventory problem(s)`)
  process.exit(1)
}
console.log(`\n${listed.size} checks documented, ${onDisk.length} on disk, ${run.size} on CI`)
