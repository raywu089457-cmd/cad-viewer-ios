#!/usr/bin/env node
// Checks the XcodeGen spec against the tree it describes.
//
// `ios/project.yml` is the only file that turns these packages into an app, and nothing has ever
// read it. A path in it that does not exist produces a project that builds without the code it
// names; a target declared twice produces a duplicate `@main`; a missing Info.plist key produces
// an app that installs and never appears for a DWG.
//
//   node verification/check-project-spec.mjs

import { readFileSync, readdirSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const ios = join(here, '..', 'ios')

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// Normalised: a checkout on Windows has CRLF and the patterns below are written with plain
// newlines, so a redirect would silently stop matching.
// Normalised: a Windows checkout has CRLF and the patterns below are written with plain
// newlines, so a redirect would stop matching without saying so.
// Normalised: a Windows checkout has CRLF and the patterns below are written with plain
// newlines, so a redirect would stop matching without saying so.
const spec = readFileSync(join(ios, 'project.yml'), 'utf8')
  .replace(new RegExp('\r\n', 'g'), '\n')
const pkgRaw = readFileSync(join(ios, 'CADViewer', 'Package.swift'), 'utf8')
// Comments name the thing being avoided. Reading them as code turns a deliberate note into the
// defect it is explaining.
const pkg = pkgRaw
  .split('\n')
  .filter(line => !line.trim().startsWith('//'))
  .join('\n')

// 1. Every path it names has to exist, or XcodeGen writes a project that silently omits it.
const paths = [
  ...[...spec.matchAll(/^\s*- path: (\S+)$/gm)].map(m => m[1]),
  ...[...spec.matchAll(/^\s{4}(\S+):\n\s{6}path: (\S+)$/gm)].map(m => m[2]),
  ...[...spec.matchAll(/^\s*INFOPLIST_FILE: (\S+)$/gm)].map(m => m[1])
]
check(paths.length > 0, `the spec names ${paths.length} path(s)`)
for (const path of new Set(paths)) {
  check(existsSync(join(ios, path)), `${path} exists`)
}

// 2. A target must not be both a SwiftPM target and a directory compiled into the app.
//
// `CADViewerApp` was declared as an `executableTarget` in the package *and* listed under the
// spec's `sources`. Both produce a `@main`, which is a duplicate symbol at link time — the kind
// of failure that only a device build shows, and there is no device build here.
const executableTargets = new Set(
  [...pkg.matchAll(/\.executableTarget\(\s*name:\s*"([^"]+)"/g)].map(m => m[1])
)
const sourceDirs = [...spec.matchAll(/^\s*- path: (\S+)$/gm)].map(m => m[1])
check(
  executableTargets.size <= 1,
  `the package declares ${executableTargets.size} executable target(s)`
)

for (const dir of sourceDirs) {
  for (const target of executableTargets) {
    if (!existsSync(join(ios, dir))) continue
    // A source directory holds files; `@main` is what makes it an app entry point.
    const holdsMain = readdirSync(join(ios, dir))
      .filter(f => f.endsWith('.swift'))
      .some(f => readFileSync(join(ios, dir, f), 'utf8').includes('@main'))
    check(
      !holdsMain || !new RegExp(`name: "${target}"`).test(pkg),
      `${dir} is compiled into the app and is not also the package's "${target}"`
    )
  }
}

// 3. The app target has to depend on the package that holds the views it starts from.
check(
  /dependencies:\s*\n\s*- package: CADViewer\n\s*product: CADViewer/.test(spec),
  'the app target depends on the CADViewer package'
)

// 4. The Info.plist is hand-written and must not be generated over.
check(/GENERATE_INFOPLIST_FILE: NO/.test(spec), 'XcodeGen does not generate an Info.plist')
check(/INFOPLIST_FILE: CADViewer\/Info\.plist/.test(spec), 'and points at the hand-written one')

// 5. The plist it points at has to declare what opening a file needs.
const plist = readFileSync(join(ios, 'CADViewer', 'Info.plist'), 'utf8')
check(/CFBundleDocumentTypes/.test(plist), 'the plist declares the document types it opens')
check(/LSSupportsOpeningDocumentsInPlace/.test(plist), 'and supports opening files in place')
check(/UISupportsDocumentBrowser|UIFileSharingEnabled/.test(plist), 'and shows them in Files')

// 6. The bundle identifier the spec writes has to be one a device will take.
const bundleId = spec.match(/PRODUCT_BUNDLE_IDENTIFIER: (\S+)/)?.[1]
check(bundleId !== undefined, `the app has a bundle identifier (${bundleId})`)
check(
  bundleId === undefined || /^[A-Za-z][A-Za-z0-9.-]+$/.test(bundleId),
  'the bundle identifier is a reverse-DNS name'
)

if (failures.length > 0) {
  console.log(`\n${failures.length} problem(s) in the XcodeGen spec`)
  process.exit(1)
}
console.log('\nthe XcodeGen spec matches the tree it describes')
