import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { basename, resolve } from 'node:path'
import { defineConfig } from 'vite'

const LIBREDWG_DIST = 'node_modules/@mlightcad/libredwg-converter/dist'
const VIEWER_DIST = 'node_modules/@mlightcad/cad-simple-viewer/dist'

/**
 * Files the viewer fetches at runtime by URL, not by import.
 *
 * They must land in `assets/` under their bare names: the LibreDWG worker
 * resolves `libredwg-web.wasm` relative to its own URL, and the MTEXT worker is
 * requested by the name passed in `webworkerFileUrls`.
 */
const WORKER_ASSETS = [
  `${VIEWER_DIST}/mtext-renderer-worker.js`,
  `${LIBREDWG_DIST}/libredwg-parser-worker.js`,
  `${LIBREDWG_DIST}/libredwg-web.wasm`
]

/**
 * Licences that have to travel with the bytes.
 *
 * The LibreDWG wasm is GPL-3.0. Shipping it in an app bundle without its licence is a
 * licence violation rather than a formality, and the licence file sits beside the package
 * rather than inside `dist` unless something copies it there.
 */
const LICENCE_ASSETS = [
  { source: `${LIBREDWG_DIST}/../LICENSE`, name: 'LICENSE-LibreDWG.txt' },
  { source: `${VIEWER_DIST}/../LICENSE`, name: 'LICENSE-cad-simple-viewer.txt' },
  // Apache-2.0 asks for a NOTICE file to travel with the work when one exists. This package is a
  // fork with its own attribution in `NOTICE.md`, and its code is inside the renderer chunk —
  // so the notice has to be in the bundle even though no file is named after it.
  {
    source: 'node_modules/@mlightcad/emf-converter/NOTICE.md',
    name: 'NOTICE-mlightcad-emf-converter.md'
  }
]

/** Copies the runtime worker bytes and their licences after Vite writes the bundle. */
const workerAssetsPlugin = {
  name: 'cad-worker-assets',
  apply: 'build',
  closeBundle() {
    const outDir = resolve('dist/assets')
    mkdirSync(outDir, { recursive: true })
    for (const file of WORKER_ASSETS) {
      if (!existsSync(file)) throw new Error(`missing worker asset: ${file}`)
      copyFileSync(file, resolve(outDir, basename(file)))
    }
    for (const licence of LICENCE_ASSETS) {
      if (!existsSync(licence.source)) {
        throw new Error(`missing licence: ${licence.source}`)
      }
      copyFileSync(licence.source, resolve(outDir, licence.name))
    }
  }
}

export default defineConfig({
  // Relative paths: the bundle is loaded through a WKURLSchemeHandler, which
  // has no notion of a server root.
  base: './',
  build: {
    outDir: 'dist',
    target: 'safari15',
    modulePreload: false,
    rollupOptions: {
      output: {
        // Split the heavy rendering stack so opening a drawing does not block
        // the first paint of the loading overlay.
        manualChunks(id) {
          const path = id.replace(/\\/g, '/')
          if (path.includes('/node_modules/three/')) return 'three'
          if (path.includes('/@mlightcad/three-renderer/')) return 'three-renderer'
          if (
            path.includes('/@mlightcad/mtext-renderer/') ||
            path.includes('/@mlightcad/mtext-parser/')
          ) {
            return 'mtext'
          }
          if (
            path.includes('/@mlightcad/data-model/') ||
            path.includes('/@mlightcad/geometry-engine/') ||
            path.includes('/@mlightcad/graphic-interface/') ||
            path.includes('/@mlightcad/common/')
          ) {
            return 'data-model'
          }
          return undefined
        }
      }
    }
  },
  plugins: [workerAssetsPlugin],
  resolve: {
    alias: {
      '@': resolve(process.cwd(), 'src')
    }
  }
})
