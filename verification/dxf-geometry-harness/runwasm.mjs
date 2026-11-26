// Runs a wasm build of the harnesses under Node's WASI.
//
//   node runwasm.mjs verify.wasm
//   node runwasm.mjs scenecheck.wasm --file ../fixtures/circles.dxf --preopen ..
//
// `--preopen <dir>` mounts a host directory into the guest, which is the only way a wasm module
// can open a file. Without it the checks that read a real drawing skip, and a skip reads as a pass
// — three of them did exactly that until this was added.
//
// WASI is still flagged experimental in Node, hence the warning on every run.
import { WASI } from 'node:wasi'
import { readFile } from 'node:fs/promises'
import { resolve } from 'node:path'

const argv = process.argv.slice(2)

// `--preopen` and its value are this script's, not the guest's.
let hostDir
const guestArgs = []
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === '--preopen') {
    hostDir = argv[i + 1]
    i += 1
    continue
  }
  guestArgs.push(argv[i])
}

const wasmPath = guestArgs.shift()
if (!wasmPath) {
  console.error('usage: node runwasm.mjs <file.wasm> [--preopen <dir>] [args...]')
  process.exit(2)
}

const preopens = hostDir ? { '/host': resolve(hostDir) } : {}

const wasi = new WASI({
  version: 'preview1',
  args: ['harness', ...guestArgs],
  preopens
})

const module = await WebAssembly.compile(await readFile(wasmPath))
const instance = await WebAssembly.instantiate(module, wasi.getImportObject())
process.exit(wasi.start(instance))
