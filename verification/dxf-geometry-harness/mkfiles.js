// Builds one flat file list for a single-module wasm compile.
//
// The wasm path cannot use SwiftPM: it needs a wasm SDK, and SwiftDXF is fetched as an SPM
// dependency that the Swift 6.4.3 Windows toolchain will not resolve for wasm32-wasip1.
// So this compiles everything into one module, which means the `import` lines that name
// those modules have to go.
//
// Used only by build-wasm.bat. On a Mac, `./run.sh` uses SwiftPM and does the same job
// properly, through the real module boundaries.
const fs = require('fs'), path = require('path')

const root = path.resolve('..', '..')
const libRoot = path.join(root, 'SwiftDXF', 'Sources', 'SwiftDXF')
const geomRoot = path.join(root, 'ios', 'DXFGeometry', 'Sources', 'DXFGeometry')
const staging = path.resolve('.staging')

for (const [dir, hint] of [
  [libRoot, 'git clone https://github.com/SecondMouseAU/SwiftDXF.git ../../SwiftDXF'],
  [geomRoot, 'run this from verification/dxf-geometry-harness']
]) {
  if (!fs.existsSync(dir)) {
    console.error(`missing ${dir}\n  ${hint}`)
    process.exit(1)
  }
}

function walk(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name)
    if (entry.isDirectory()) walk(file, out)
    else if (entry.name.endsWith('.swift')) out.push(file)
  }
  return out
}

function stage(files, target) {
  const dir = path.join(staging, target)
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(dir, { recursive: true })
  return files.map((file, index) => {
    let body = fs
      .readFileSync(file, 'utf8')
      .split('\n')
      .filter(line => !/^import (SwiftDXF|DXFGeometry)\s*$/.test(line))
      .join('\n')

    // SwiftDXF's CodePage decodes code pages through CoreFoundation's CFStringEncoding.
    // wasm32-wasip1 ships a Foundation whose `canImport(CoreFoundation)` is true but which
    // has no CFStringEncoding, so the guard has to be narrowed for this build only. Apple
    // platforms are unaffected, which is why this lives here and not in the package.
    body = body.replace(
      '#if canImport(CoreFoundation)',
      '#if canImport(CoreFoundation) && !os(WASI)'
    )
    // The entry point must keep the name `main.swift`, or Swift forbids top-level code.
    const base = path.basename(file)
    const name = base === 'main.swift' ? base : `${String(index).padStart(3, '0')}_${base}`
    const out = path.join(dir, name)
    fs.writeFileSync(out, body)
    return out
  })
}

const lib = walk(libRoot, [])
const geometry = walk(geomRoot, [])
const scenecheck = walk(path.resolve('Sources', 'scenecheck'), [])
const verify = walk(path.resolve('Sources', 'verify'), [])
const quote = list => list.map(file => '"' + file + '"').join('\r\n')

fs.writeFileSync('files-exe.txt', quote(stage(lib.concat(geometry, scenecheck), 'exe')))
fs.writeFileSync('files-verify.txt', quote(stage(lib.concat(geometry, verify), 'verify')))
console.log(
  `lib ${lib.length} geometry ${geometry.length} ` +
  `scenecheck ${scenecheck.length} verify ${verify.length}`
)
