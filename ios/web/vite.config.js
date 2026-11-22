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

/** Copies the runtime worker bytes after Vite has written the bundle. */
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
