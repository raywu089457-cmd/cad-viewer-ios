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
// Images are not `](…)` links, so the loop above does not see them: a README whose first
// screen shows a broken image is broken in the place everyone looks first, and nothing
// reported it. Captured from `src="…"` and from `src=…` without quotes, which Markdown allows.
const images = [
  ...[...readme.matchAll(/<img[^>]+src="([^"]+)"/g)].map(m => m[1]),
  ...[...readme.matchAll(/!\[[^\]]*\]\(([^)]+)\)/g)].map(m => m[1]),
].filter(src => !/^https?:/.test(src))
check(images.length > 0, `the README shows ${images.length} local image(s)`)
for (const src of new Set(images)) {
  // A path may carry a title after a space, as in `![alt](path "title")`.
  const path = src.split(/\s+/)[0]
  check(existsSync(join(repo, path)), `${path} exists`)
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

// 6. The same claim checks apply to the sub-READMEs, and one of their claims is different: a
//    specific count of something a reader cannot recount. That is worse than vague, because it
//    invites trust and cannot be checked — `158 個實體` sat in `ios/README.md` for a drawing
//    converted into a gitignored directory that no fresh checkout has.
const subReadmes = ['ios/README.md', 'ios/CADViewer/README.md', 'ios/DXFGeometry/README.md',
  'ios/web/README.md', 'verification/dxf-geometry-harness/README.md', 'shots/README.md']
  .filter(file => existsSync(join(repo, file)))
check(subReadmes.length > 0, `found ${subReadmes.length} sub-README(s)`)

for (const file of subReadmes) {
  const text = readFileSync(join(repo, file), 'utf8')

  // A number attached to something in a gitignored directory cannot be reproduced by a reader.
  const countsTheUnreachable = /\d+\s*(該|個|entities?|實體)[^\n]{0,40}out\//.test(text)
  check(!countsTheUnreachable, `${file} does not count what only exists in a gitignored dir`)

  // A file it names in backticks has to be there: this is how the screenshot index stays true
  // after a picture is renamed.
  const named = [...text.matchAll(/`([a-z0-9][a-z0-9._-]*\.(?:png|svg|json|html))`/g)].map(m => m[1])
  for (const name of new Set(named)) {
    const beside = join(repo, dirname(file), name)
    check(existsSync(beside), `${file} names ${name}, and it is beside it`)
  }
  // Every command it tells a reader to run has to exist.
  for (const match of text.matchAll(/^\s*\.\/([a-z][a-z0-9-]*\.(?:sh|bat))$/gm)) {
    const name = match[1]
    const near = [join(repo, 'ios/web', name), join(repo, 'ios', name),
      join(repo, 'verification', name), join(repo, 'verification/dxf-geometry-harness', name)]
    check(near.some(existsSync), `${file}: ./${name} exists`)
  }
}

if (failures.length > 0) {
  console.log(`\n${failures.length} claim(s) in the README no longer hold`)
  process.exit(1)
}
console.log('\nthe README matches the tree it describes')
