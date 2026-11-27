#!/usr/bin/env node
// Checks that ios/BUILD-ON-MAC.md still describes the tree it describes.
//
// A setup guide is the one document nobody re-reads before trusting it. Every count in it —
// the size of the bundle, the number of packages, which samples exist — can go stale silently
// as the project changes, and the reader finds out by following a step that no longer works.
//
// Each claim is checked against the thing it describes, not against another sentence.

import { readFileSync, existsSync, statSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const root = process.cwd()
const doc = readFileSync(join(root, 'ios/BUILD-ON-MAC.md'), 'utf8')

const problems = []
let checked = 0

function claim(ok, what) {
  checked += 1
  if (!ok) problems.push(what)
}

// ── The paths the guide tells you to run must exist ────────────────────────────────
for (const path of ['ios/web/build-for-ios.sh', 'ios/project.yml', 'ios/CADViewer/Info.plist']) {
  claim(existsSync(join(root, path)), `the guide names ${path}, which is not there`)
}

// ── The deployment target it quotes ───────────────────────────────────────────────
const spec = readFileSync(join(root, 'ios/project.yml'), 'utf8')
const target = spec.match(/iOS:\s*"([0-9.]+)"/)
claim(Boolean(target), 'project.yml no longer declares an iOS deployment target')
if (target) {
  claim(
    doc.includes('iOS ' + target[1]),
    `the guide should quote the deployment target project.yml declares (${target[1]})`
  )
  const major = Number(target[1].split('.')[0])
  // Xcode releases ship the SDK one major version on from the year before; a guide that says
  // "15" for an iOS 17 target would send the reader to an Xcode that cannot build it.
  const expectedXcode = major - 2
  claim(
    doc.includes('Xcode** | ' + expectedXcode) || doc.includes('Xcode | ' + expectedXcode) ||
      doc.includes(String(expectedXcode) + ' 或更新'),
    `an iOS ${target[1]} target needs Xcode ${expectedXcode} or newer, and the guide does not say so`
  )
}

// ── The bundle id the reader is told to change ────────────────────────────────────
const prefix = spec.match(/bundleIdPrefix:\s*(\S+)/)
const bundleId = spec.match(/PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)/)
claim(Boolean(bundleId), 'project.yml no longer sets PRODUCT_BUNDLE_IDENTIFIER')
if (bundleId) {
  claim(
    doc.includes(bundleId[1]),
    `the guide should name the placeholder bundle id the reader has to change (${bundleId[1]})`
  )
}
if (prefix) {
  claim(
    bundleId && bundleId[1].startsWith(prefix[1]),
    'the placeholder bundle id no longer starts with bundleIdPrefix, so the guide\'s story is wrong'
  )
}

// ── The package count it quotes ──────────────────────────────────────────────────
const lock = JSON.parse(readFileSync(join(root, 'ios/web/package-lock.json'), 'utf8'))
const packages = Object.keys(lock.packages || {}).filter(Boolean).length
const quoted = doc.match(/([0-9]+) 個套件/)
claim(Boolean(quoted), 'the guide no longer quotes a package count')
if (quoted) {
  claim(
    Number(quoted[1]) === packages,
    `the guide says ${quoted[1]} packages; package-lock.json has ${packages}`
  )
}

// ── The size it quotes for the built bundle ──────────────────────────────────────
const bundleDir = join(root, 'ios/CADViewer/Sources/CADViewer/Resources/dwgviewer')
function bytes(dir) {
  let total = 0
  for (const name of readdirSync(dir)) {
    const full = join(dir, name)
    const st = statSync(full)
    total += st.isDirectory() ? bytes(full) : st.size
  }
  return total
}
if (existsSync(bundleDir)) {
  const mb = bytes(bundleDir) / (1024 * 1024)
  const sizeClaim = doc.match(/約 ([0-9]+) MB/)
  claim(Boolean(sizeClaim), 'the guide no longer quotes a size for the bundle')
  if (sizeClaim) {
    // The bundle in a fresh clone is the placeholder; a built one is tens of megabytes. Both
    // are legitimate states, so the claim is checked only when the directory is not the
    // placeholder — otherwise the guide is describing a build the reader has not run yet.
    const built = readdirSync(bundleDir).includes('assets')
    if (built) {
      const stated = Number(sizeClaim[1])
      claim(
        Math.abs(stated - mb) <= 4,
        `the guide says about ${stated} MB; the built bundle is ${mb.toFixed(1)} MB`
      )
    }
  }
}

// ── The samples it names ─────────────────────────────────────────────────────────
const samples = readdirSync(join(root, 'samples'))
for (const name of doc.match(/samples\/[A-Za-z0-9_.-]+/g) || []) {
  const base = name.replace('samples/', '')
  claim(samples.includes(base), `the guide tells the reader to open ${name}, which is not there`)
}
claim(
  !samples.some(s => s.endsWith('.pdf')),
  'the guide says samples has no PDF; one has been added, so that paragraph is now wrong'
)
claim(
  doc.includes('樣本裡沒有 PDF'),
  'the note about samples having no PDF is gone, and step 3 depends on it'
)

// ── The document types it implies by telling the reader to open three formats ────
const plist = readFileSync(join(root, 'ios/CADViewer/Info.plist'), 'utf8')
for (const uti of ['com.autodesk.dxf', 'com.autodesk.dwg', 'com.adobe.pdf']) {
  claim(plist.includes(uti), `the guide's three formats need ${uti} in Info.plist, and it is gone`)
}

if (problems.length > 0) {
  console.error(`${problems.length} claim(s) in BUILD-ON-MAC.md no longer match the tree:`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}

console.log(`BUILD-ON-MAC.md matches the tree (${checked} claims)`)
