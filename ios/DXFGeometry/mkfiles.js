// Builds one flat file list for the WASI toolchain.
//
// SwiftPM would compile three modules; the fallback harness here compiles everything into a
// single module, so the `import SwiftDXF` / `import DXFGeometry` lines have to go: inside one
// module they would name nothing.
const fs = require('fs'), path = require('path')
const root = path.resolve('..', '..')
const libRoot = path.join(root, 'SwiftDXF-wasm', 'Sources', 'SwiftDXF')
const staging = path.resolve('.staging')

function walk(d, out) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const f = path.join(d, e.name)
    if (e.isDirectory()) walk(f, out)
    else if (e.name.endsWith('.swift')) out.push(f)
  }
  return out
}

function stage(files, target) {
  const dir = path.join(staging, target)
  fs.rmSync(dir, { recursive: true, force: true })
  fs.mkdirSync(dir, { recursive: true })
  return files.map((file, index) => {
    const body = fs
      .readFileSync(file, 'utf8')
      .split('\n')
      .filter(line => !/^import (SwiftDXF|DXFGeometry)\s*$/.test(line))
      .join('\n')
    // The entry point must keep the name `main.swift`, or Swift forbids top-level code.
    const base = path.basename(file)
    const name = base === 'main.swift'
      ? base
      : `${String(index).padStart(3, '0')}_${base}`
    const out = path.join(dir, name)
    fs.writeFileSync(out, body)
    return out
  })
}

const lib = walk(libRoot, [])
const geom = walk(path.resolve('Sources', 'DXFGeometry'), [])
const tool = walk(path.resolve('Sources', 'scenecheck'), [])
const verify = walk(path.resolve('Sources', 'verify'), [])
const q = list => list.map(f => '"' + f + '"').join('\r\n')

fs.writeFileSync('files-exe.txt', q(stage(lib.concat(geom, tool), 'exe')))
fs.writeFileSync('files-verify.txt', q(stage(lib.concat(geom, verify), 'verify')))
console.log('lib', lib.length, 'geom', geom.length, 'tool', tool.length, 'verify', verify.length)
