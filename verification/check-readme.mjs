#!/usr/bin/env node
// Checks that the README's claims about this repository are still true.
//
// The README is the only thing a visitor reads, and it was wrong in the most consequential way
// for several rounds: it said the app layer could only be syntax-checked, while CI had been
// type-checking it against platform stubs. A reader would have concluded the coverage was weaker
// than it is — or, if the two had drifted the other way, stronger.
//
// Only claims that can be checked mechanically are checked. Prose about why the app is built this
// way is not a claim about the current tree.
//
//   node verification/check-readme.mjs

import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = join(here, '..')
const readme = readFileSync(join(repo, 'README.md'), 'utf8')
const workflow = readFileSync(join(repo, '.github/workflows/checks.yml'), 'utf8')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// 1. The job count. `push:` and `workflow_dispatch:` sit at the same indent and are triggers.
const jobs = [...workflow.matchAll(/^  ([a-z][a-z-]*):$/gm)]
  .map(m => m[1])
  .filter(name => !['push', 'pull_request', 'workflow_dispatch', 'schedule', 'on'].includes(name))
const claimed = readme.match(/(\d+) 個 job/)
check(claimed !== null, 'the README says how many jobs CI runs')
if (claimed) {
  check(
    Number(claimed[1]) === jobs.length,
    `the README's ${claimed[1]} matches the ${jobs.length} jobs in the workflow`
  )
}

// 2. Every file the README links to has to exist. A dead link is the one staleness a reader
//    notices immediately and forgives least.
const linked = [...readme.matchAll(/\]\(([^)#][^)]*)\)/g)]
  .map(m => m[1])
  .filter(link => !/^https?:/.test(link))
check(linked.length > 0, `the README links to ${linked.length} local file(s)`)
for (const link of new Set(linked)) {
  check(existsSync(join(repo, link)), `${link} exists`)
}

// 3. A claim that the app layer is type-checked has to be backed by the stubs and the step.
const claimsTypeCheck = /swiftc -typecheck|型別檢查/.test(readme)
if (claimsTypeCheck) {
  check(existsSync(join(repo, 'verification/stubs')), 'the stubs the type check needs are present')
  check(
    /verification\/check-types\.sh/.test(workflow),
    'and the workflow runs the type check the README describes'
  )
  // The old README said this could not be done; if that sentence returns, the claim is a
  // contradiction rather than a stale fact.
  check(
    !/證實做不到/.test(readme),
    'and the README does not also say it was found impossible'
  )
}

// 4. Licence claims name the components that ship. A component in the notices but not in the
//    table is the sort of omission a reader relies on this section to avoid.
const notices = readFileSync(join(repo, 'THIRD-PARTY-NOTICES.md'), 'utf8')
for (const component of ['LibreDWG', 'SwiftDXF', 'mlightcad']) {
  check(readme.includes(component), `the README names ${component}, which ships`)
  check(notices.includes(component), `and so do the notices`)
}

// 5. The scripts the README tells a reader to run.
for (const match of readme.matchAll(/`([a-z][a-z0-9-]*\.(?:mjs|sh|bat))`/g)) {
  const name = match[1]
  const found = existsSync(join(repo, 'verification', name)) ||
    existsSync(join(repo, '.github', name)) ||
    existsSync(join(repo, 'ios/web', name))
  check(found, `${name} is where the README implies`)
}

if (failures.length > 0) {
  console.log(`\n${failures.length} claim(s) in the README no longer hold`)
  process.exit(1)
}
console.log('\nthe README matches the tree it describes')
