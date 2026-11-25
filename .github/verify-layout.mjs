// Checks that the repository tree matches what its manifests promise.
//
// This is the check that would have caught three real mistakes here: harness directories
// sitting under Sources/ without a target, a Package.swift depending on a product through
// a package that does not export it, and a resource folder that a fresh clone does not have.
//
// No dependencies, so it runs before any install step:
//
//   node .github/verify-layout.mjs
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
const problems = []
const checked = []

function fail(message) {
  problems.push(message)
}

function ok(message) {
  checked.push(message)
}

function mustExist(relative, why) {
  const path = join(root, relative)
  if (existsSync(path)) ok(relative)
  else fail(`${relative} is missing${why ? ` — ${why}` : ''}`)
}

/** Every Swift package in the tree, with the source root it uses. */
const packages = [
  { manifest: 'ios/DXFGeometry/Package.swift', sources: 'ios/DXFGeometry/Sources' },
  { manifest: 'ios/CADViewer/Package.swift', sources: 'ios/CADViewer/Sources' },
  {
    manifest: 'verification/dxf-geometry-harness/Package.swift',
    sources: 'verification/dxf-geometry-harness/Sources'
  }
]

// SwiftPM fails on a directory under Sources/ that no target claims, so check both ways:
// every declared target has a directory, and every directory belongs to a target.
for (const package_ of packages) {
  if (!existsSync(join(root, package_.manifest))) {
    fail(`${package_.manifest} is missing`)
    continue
  }
  const manifest = readFileSync(join(root, package_.manifest), 'utf8')

  const declared = new Set()
  // `.target(name: "X"` and `.executableTarget(name: "X"`.
  for (const match of manifest.matchAll(/\.(?:executable)?[tT]arget\(\s*name:\s*"([^"]+)"/g)) {
    declared.add(match[1])
  }

  for (const target of declared) {
    const path = join(root, package_.sources, target)
    if (!existsSync(path)) {
      fail(`${package_.manifest} declares target "${target}" but ${package_.sources}/${target} does not exist`)
    } else {
      ok(`${target} target directory`)
    }
  }

  if (existsSync(join(root, package_.sources))) {
    for (const entry of readdirSync(join(root, package_.sources), { withFileTypes: true })) {
      if (entry.isDirectory() && !declared.has(entry.name)) {
        fail(`${package_.sources}/${entry.name} has no target in ${package_.manifest}`)
      }
    }
  }

  // A local `.package(path:)` has to point at something that exists, and the product it is
  // asked for has to be one that package actually exports.
  for (const match of manifest.matchAll(/\.package\(path:\s*"([^"]+)"\)/g)) {
    const packageDir = resolve(root, dirname(package_.manifest), match[1])
    if (!existsSync(join(packageDir, 'Package.swift'))) {
      fail(`${package_.manifest} points at ${match[1]}, which has no Package.swift`)
    } else {
      ok(`${match[1]} local package`)
    }
  }
}

// The app's Package.swift asks DXFGeometry for products by name; they have to be exported.
{
  const geometry = readFileSync(join(root, 'ios/DXFGeometry/Package.swift'), 'utf8')
  const exported = new Set(
    [...geometry.matchAll(/\.library\(\s*name:\s*"([^"]+)"/g)].map(m => m[1])
  )
  const app = readFileSync(join(root, 'ios/CADViewer/Package.swift'), 'utf8')
  for (const match of app.matchAll(
    /\.product\(\s*name:\s*"([^"]+)",\s*package:\s*"DXFGeometry"\s*\)/g
  )) {
    if (!exported.has(match[1])) {
      fail(`CADViewer asks DXFGeometry for product "${match[1]}", which it does not export`)
    } else {
      ok(`DXFGeometry exports ${match[1]}`)
    }
  }
}

// SwiftPM needs the resource folder to exist, and it is generated rather than committed, so
// a fresh clone must still carry the placeholder.
mustExist(
  'ios/CADViewer/Sources/CADViewer/Resources/dwgviewer/index.html',
  'the DWG resource folder must exist for SwiftPM to build'
)

// Everything the docs and the app reference.
mustExist('LICENSE')
// The app redistributes a GPL-3.0 WebAssembly build. A licence that does not travel with the
// code is not honoured, so the notices are part of the deliverable.
mustExist('THIRD-PARTY-NOTICES.md')
mustExist('README.md')
mustExist('ios/project.yml')
mustExist('ios/CADViewer/Info.plist')
mustExist('ios/web/src/main.js')
mustExist('ios/web/vite.config.js')
mustExist('verification/parse-check.sh')
mustExist('verification/test-dwg-reopen.mjs')
// The independent coordinate check: its own DXF reader, sharing no code with the Swift side.
mustExist('verification/verify-coordinates.mjs')
// Checks the app layer's calls into the geometry against the real declarations, which is
// the part of that layer that can be verified without an Apple SDK.
mustExist('verification/check-api-usage.mjs')
// File reads on the main actor freeze the interface, which no screenshot would show.
mustExist('verification/check-main-thread-io.mjs')
// A committed snapshot that stops matching the pipeline turns the independent coordinate
// check into decoration.
mustExist('verification/check-fixture-fresh.mjs')
// A content controller holds its handler strongly; registering the view leaks the page.
mustExist('verification/check-retain-cycles.mjs')
// UI state that is not main-actor isolated is a data race the compiler only finds under Swift 6.
mustExist('verification/check-actor-isolation.mjs')
// Kept as a record of what was attempted and what is still missing. Not run on CI: the
// README there says why.
mustExist('verification/stubs/README.md')
mustExist('verification/check-types.sh')
// A workflow that does not parse runs no jobs at all, and the failure looks infrastructural.
mustExist('verification/check-workflow.mjs')
// Applied on CI so the Swift suites can run on Linux; a missing patch means no tests run.
mustExist('verification/patch-swiftdxf-for-linux.sh')
mustExist('verification/fixtures/circles.dxf')
mustExist('verification/fixtures/circles.json')
mustExist('verification/dxf-geometry-harness/run.sh')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/ViewTransform.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/FileRouting.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/BundleServing.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/ViewerEvent.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/ViewerEventTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/ViewportTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/DrawingHandoffTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/LoadGenerationTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/ResourceLocationTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/BlockAttributeTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/SkippedEntitiesTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/DrawingReadOptionsTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/PDFZoomTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/FilePickOutcomeTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/DrawBatchingTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/GestureSessionTests.swift')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/LoadReadinessTests.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/LoadOutcome.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/DrawingReadOptions.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/SkippedEntities.swift')
// The attribute test reads this fixture from the test bundle, so its absence silently
// turns the test into a no-op.
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/Fixtures/attributes.dxf')
mustExist('ios/DXFGeometry/Tests/DXFGeometryTests/FileRoutingTests.swift')
mustExist('ios/CADViewer/Sources/CADViewer/PDFViewer.swift')

// Each of the three formats must be routed and shown, which is the whole point of the app.
{
  // The routing decision lives with the geometry now, so it can be tested without Xcode.
  const loader = readFileSync(
    join(root, 'ios/DXFGeometry/Sources/DXFGeometry/FileRouting.swift'),
    'utf8'
  )
  for (const format of ['dxf', 'dwg', 'pdf']) {
    if (!new RegExp(`case ${format}`).test(loader)) {
      fail(`DrawingKind has no .${format} case`)
    } else {
      ok(`DrawingKind.${format}`)
    }
  }

  const readme = readFileSync(join(import.meta.dirname, '..', 'README.md'), 'utf8')
  const plist = readFileSync(
    join(import.meta.dirname, '..', 'ios/CADViewer/Info.plist'),
    'utf8'
  )
  for (const type of ['com.autodesk.dxf', 'com.autodesk.dwg', 'com.adobe.pdf']) {
    if (!plist.includes(type)) fail(`Info.plist does not declare ${type}`)
    else ok(`Info.plist declares ${type}`)
  }
  if (!readme.includes('PDFKit')) fail('the README does not mention PDF support')

  // The picker asks for types by identifier. One that Info.plist does not declare would not
  // resolve, and the drawing would be unselectable with nothing to say why — so the two lists
  // have to agree, and a new format added to one without the other is exactly the drift this
  // catches.
  {
    const picker = readFileSync(
      join(root, 'ios/CADViewer/Sources/CADViewer/RootView.swift'),
      'utf8'
    )
    const match = picker.match(/let identifiers = \[([^\]]+)\]/)
    if (!match) {
      fail('RootView does not list the types its file picker accepts')
    } else {
      const requested = [...match[1].matchAll(/"([^"]+)"/g)].map(m => m[1])
      for (const type of requested) {
        if (!plist.includes(type)) {
          fail(`the file picker asks for ${type}, which Info.plist does not declare`)
        } else {
          ok(`the picker's ${type} is declared`)
        }
      }
    }
  }
}

// A shell script that the docs tell people to run has to be executable in the index, or a
// fresh clone fails with "Permission denied" on the first command. This is not visible in
// the file's contents, so it needs checking separately.
//
// Only on a POSIX filesystem: Windows does not carry the execute bit, so `statSync` reports
// 666 for a file git records as 755, and the check would report every script as broken. The
// CI runs on Linux, which is where this check belongs.
if (process.platform !== 'win32') {
  // Enumerated, not listed. A hand-maintained list of scripts has missed a new one three times
  // now — each time the check passed while a script CI runs was not executable.
  const scripts = []
  const walkScripts = directory => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.name === 'node_modules' || entry.name === '.git' || entry.name.startsWith('.')) {
        continue
      }
      const full = join(directory, entry.name)
      if (entry.isDirectory()) walkScripts(full)
      else if (entry.name.endsWith('.sh')) {
        scripts.push(full.slice(root.length + 1).replace(/\\/g, '/'))
      }
    }
  }
  walkScripts(root)
  for (const script of scripts) {
    if (!existsSync(join(root, script))) {
      fail(script + ' is missing')
      continue
    }
    const mode = statSync(join(root, script)).mode
    // 0o111 is the execute bit for owner, group and other.
    if ((mode & 0o111) === 0) {
      fail(script + ' is not executable, so a fresh clone cannot run it')
    } else {
      ok(script + ' is executable')
    }
  }
}

// `npm ci` installs exactly the lockfile and fails when it disagrees with package.json, so a
// drifted lockfile breaks CI on a commit that looked unrelated. Checked here, where the
// message can say which package differs.
{
  const projects = ['ios/web', 'verification']
  for (const project of projects) {
    const manifestPath = join(root, project, 'package.json')
    const lockPath = join(root, project, 'package-lock.json')
    if (!existsSync(manifestPath) || !existsSync(lockPath)) {
      fail(`${project} is missing package.json or package-lock.json`)
      continue
    }
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
    const lock = JSON.parse(readFileSync(lockPath, 'utf8'))
    const rootEntry = (lock.packages && lock.packages['']) || {}
    for (const field of ['dependencies', 'devDependencies']) {
      const declared = Object.keys(manifest[field] || {}).sort()
      const locked = Object.keys(rootEntry[field] || {}).sort()
      if (JSON.stringify(declared) !== JSON.stringify(locked)) {
        const onlyManifest = declared.filter(name => !locked.includes(name))
        const onlyLock = locked.filter(name => !declared.includes(name))
        fail(
          `${project} ${field} out of sync with its lockfile` +
            (onlyManifest.length ? ` (in package.json only: ${onlyManifest.join(', ')})` : '') +
            (onlyLock.length ? ` (in lockfile only: ${onlyLock.join(', ')})` : '')
        )
      } else {
        ok(`${project} ${field} matches its lockfile`)
      }
    }
  }
}

if (problems.length > 0) {
  console.error(`layout problems (${problems.length}):`)
  for (const problem of problems) console.error(`  - ${problem}`)
  process.exit(1)
}

console.log(`layout ok (${checked.length} checks)`)
