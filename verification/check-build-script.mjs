#!/usr/bin/env node
// Checks the script a reader is told to run first.
//
// `ios/web/build-for-ios.sh` is step one of the README. If it copies to the wrong place, or leaves
// the destination in a state SwiftPM rejects, the app builds without its engine — and the failure
// surfaces much later, as a DWG that opens to the placeholder.
//
// The script is not run here: it takes minutes and writes seventeen megabytes. What is checked is
// that it would do the right things, and that the things it writes are in the ignore list.
//
//   node verification/check-build-script.mjs

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

const scriptPath = join(repo, 'ios/web/build-for-ios.sh')
check(existsSync(scriptPath), 'the build script exists, which the README names')
if (!existsSync(scriptPath)) {
  console.log('\n1 build-script problem')
  process.exit(1)
}

const script = readFileSync(scriptPath, 'utf8')

// It has to fail loudly. Half a copy is a worse state than no copy: SwiftPM finds a folder, the
// app opens a page, and nothing says which half is missing.
check(/set -euo pipefail/.test(script), 'it stops on the first error')

// It runs from its own directory, so the relative paths below resolve wherever it is invoked.
check(/cd "\$\(dirname "\$0"\)"/.test(script), 'and works from any directory')

// The destination SwiftPM is told to copy in Package.swift. A wrong path here means the build
// succeeds and the app ships without the viewer.
const destination = script.match(/^DEST="([^"]+)"/m)?.[1]
check(destination !== undefined, `it names a destination (${destination})`)
check(
  destination === '../CADViewer/Sources/CADViewer/Resources/dwgviewer',
  'and that destination is the folder Package.swift copies'
)

const manifest = readFileSync(join(repo, 'ios/CADViewer/Package.swift'), 'utf8')
check(
  /\.copy\("Resources\/dwgviewer"\)/.test(manifest),
  'Package.swift does copy that folder into the bundle'
)

// The old contents are cleared first, or a stale chunk from a previous build ships alongside the
// new ones and the page loads whichever it finds.
check(/rm -rf "\$DEST"/.test(script), 'it clears the destination before copying')
check(/cp -R dist\/\./.test(script), 'and copies the built output into it')

// A reader following the README needs the dependencies, and `npm ci` fails on a missing lockfile.
check(/npm ci/.test(script), 'it installs the exact dependencies from the lockfile')
check(existsSync(join(repo, 'ios/web/package-lock.json')), 'and that lockfile is committed')

// The generated files must not be committed: seventeen megabytes of build output in every clone.
const ignore = readFileSync(join(repo, '.gitignore'), 'utf8')
check(
  /ios\/CADViewer\/Sources\/CADViewer\/Resources\/dwgviewer\/\*/.test(ignore),
  'the generated files are ignored, so only the placeholder is committed'
)
check(
  /!ios\/CADViewer\/Sources\/CADViewer\/Resources\/dwgviewer\/index\.html/.test(ignore),
  'and the placeholder that SwiftPM needs is not'
)

if (failures.length > 0) {
  console.log(`\n${failures.length} build-script problem(s)`)
  process.exit(1)
}
console.log('\nthe build script writes where the manifest says to look')
