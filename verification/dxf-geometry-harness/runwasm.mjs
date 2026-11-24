// Runs a wasm build of the harnesses under Node's WASI.
//
//   node runwasm.mjs verify.wasm
//   node runwasm.mjs scenecheck.wasm --svg < ../../out/example_2018.dxf
//
// WASI is still flagged experimental in Node, hence the warning on every run.
import { WASI } from 'node:wasi'
import { readFile } from 'node:fs/promises'

const [wasmPath, ...args] = process.argv.slice(2)
if (!wasmPath) {
  console.error('usage: node runwasm.mjs <file.wasm> [args...]')
  process.exit(2)
}

const wasi = new WASI({
  version: 'preview1',
  args: ['harness', ...args],
  // The WASI build reads its input from stdin, so no preopens are needed.
  preopens: {}
})

const module = await WebAssembly.compile(await readFile(wasmPath))
const instance = await WebAssembly.instantiate(module, wasi.getImportObject())
process.exit(wasi.start(instance))
