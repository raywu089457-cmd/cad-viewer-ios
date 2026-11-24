// Checks that the repository tree matches what its manifests promise.
//
// This is the check that would have caught three real mistakes here: harness directories
// sitting under Sources/ without a target, a Package.swift depending on a product through
// a package that does not export it, and a resource folder that a fresh clone does not have.
//
// No dependencies, so it runs before any install step:
//
//   node .github/verify-layout.mjs
import { existsSync, readFileSync, readdirSync } from 'node:fs'
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
mustExist('README.md')
mustExist('ios/project.yml')
mustExist('ios/CADViewer/Info.plist')
mustExist('ios/web/src/main.js')
mustExist('ios/web/vite.config.js')
mustExist('verification/parse-check.sh')
mustExist('verification/dxf-geometry-harness/run.sh')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/ViewTransform.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/FileRouting.swift')
mustExist('ios/DXFGeometry/Sources/DXFGeometry/BundleServing.swift')
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
}

if (problems.length > 0) {
  console.error(`layout problems (${problems.length}):`)
  for (const problem of problems) console.error(`  - ${problem}`)
  process.exit(1)
}

console.log(`layout ok (${checked.length} checks)`)
