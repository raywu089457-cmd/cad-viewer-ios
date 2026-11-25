/**
 * DWG viewer for WKWebView (iOS).
 *
 * The page is loaded by the iOS app from a private scheme, so the DWG itself is
 * fetched from `./__dwg__` (served by the app's scheme handler) rather than
 * passed as a long query string. Messages go back to Swift via `cadEvents`.
 *
 * Only DWG goes through this page. DXF is rendered natively by SwiftDXF on the
 * iOS side, so there is no DXF path here.
 */
import {
  AcApDocManager,
  acedApplyUiTheme,
  layoutBackgroundColorFromRgb
} from '@mlightcad/cad-simple-viewer'
import {
  AcDbDatabaseConverterManager,
  AcDbFileType
} from '@mlightcad/data-model'
import { AcDbLibreDwgConverter } from '@mlightcad/libredwg-converter'

/** Worker files, copied next to the JS bundle by vite.config.js. */
const WORKER_URLS = {
  mtextRender: './assets/mtext-renderer-worker.js',
  dwgParser: './assets/libredwg-parser-worker.js'
}

const statusEl = document.getElementById('status')

/** Posts a message to the native side; a no-op in a plain browser. */
function post(event, detail = {}) {
  try {
    window.webkit?.messageHandlers?.cadEvents?.postMessage({
      type: 'cad',
      event,
      ...detail
    })
  } catch (error) {
    console.error('post failed', error)
  }
}

function setStatus(text, { error = false } = {}) {
  if (!statusEl) return
  if (!text) {
    statusEl.hidden = true
    return
  }
  statusEl.hidden = false
  statusEl.textContent = text
  statusEl.classList.toggle('error', error)
}

/** base64 → ArrayBuffer, without a network round trip. */
function base64ToArrayBuffer(base64) {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

/** View-only open options: model space, fitted to extents. */
function openOptions(circleSides) {
  return {
    mode: 0, // AcEdOpenMode.Read
    drawNoPlotLayers: false,
    progressiveRendering: true,
    circleSides,
    sysVars: { paperbkcolor: layoutBackgroundColorFromRgb(0x12161c) },
    openViewMode: 'extents'
  }
}

let docManager = null
let initialized = false

/** Creates the viewer once; later DWG opens reuse the same document manager. */
async function initializeViewer() {
  if (initialized) return
  initialized = true
  setStatus('Preparing DWG engine…')

  acedApplyUiTheme('dark', document.body)

  // LibreDWG is the GPL DWG parser, shipped as wasm and run in a worker.
  AcDbDatabaseConverterManager.instance.register(
    AcDbFileType.DWG,
    new AcDbLibreDwgConverter({
      convertByEntityType: false,
      useWorker: true,
      parserWorkerUrl: WORKER_URLS.dwgParser
    })
  )

  AcApDocManager.createInstance({
    container: document.getElementById('cad-container'),
    busyIndicatorHost: document.body,
    autoResize: true,
    webworkerFileUrls: WORKER_URLS,
    checkWorkersOnInit: true,
    useMainThreadDraw: false,
    disableExport: false
  })

  docManager = AcApDocManager.instance
  docManager.events.documentActivated.addEventListener(() => {
    setStatus('')
    post('activated')
  })
}

/**
 * Opens a DWG from raw bytes.
 *
 * @param {ArrayBuffer} buffer
 * @param {string} name
 * @param {number} circleSides - curve tessellation (iOS passes 100)
 */
async function openDwg(buffer, name, circleSides) {
  try {
    await initializeViewer()
    setStatus('Opening ' + name + '…')
    post('loading', { name, bytes: buffer.byteLength })

    const started = performance.now()
    const ok = await docManager.openDocument(
      name,
      buffer,
      openOptions(circleSides)
    )
    const ms = Math.round(performance.now() - started)

    if (!ok) {
      setStatus('Could not open ' + name, { error: true })
      post('error', { name, message: 'openDocument returned false' })
      return
    }
    setStatus('')
    post('rendered', { name, ms })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    setStatus('Could not open ' + name, { error: true })
    post('error', { name, message })
  }
}

/**
 * Fetches the drawing the native side is currently holding and opens it.
 *
 * Native sets the bytes, then calls this (on first load and on every re-open),
 * which avoids passing megabytes of base64 through a URL.
 */
async function openFromNative() {
  const params = new URLSearchParams(window.location.search)
  const name = params.get('name') || 'drawing.dwg'
  const circleSides = Number(params.get('circleSides')) || 100
  setStatus('Loading ' + name + '…')
  try {
    const response = await fetch('./__dwg__', { cache: 'no-store' })
    if (!response.ok) throw new Error('drawing not available (' + response.status + ')')
    await openDwg(await response.arrayBuffer(), name, circleSides)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    setStatus('Could not load ' + name, { error: true })
    post('error', { name, message })
  }
}

window.cadReload = openFromNative

/**
 * Frames the whole drawing again.
 *
 * The page has no chrome of its own — the toolbar is native, so a reader who pinches past the
 * edge of a drawing had no way back short of reopening the file. The engine's own fit call is
 * what runs once at open; this exposes the same thing to the button.
 *
 * Returns whether it ran, so a caller can tell a missing engine from a drawing that is already
 * framed.
 */
window.cadZoomToFit = () => {
  try {
    const view = docManager?.curView
    if (!view?.zoomToFitDrawing) return false
    view.zoomToFitDrawing()
    return true
  } catch (error) {
    console.error('zoom to fit failed', error)
    return false
  }
}

/**
 * Opens a drawing the native side passes in directly.
 *
 * The first open uses `cadReload`, which fetches from the scheme handler. This is for a
 * second drawing on a page that is already loaded: the wasm engine stays warm, so a reopen
 * is much faster than a reload. Native calls it with base64 because a `WKWebView` has no
 * other way to hand over bytes.
 *
 * @param {string} base64 - the drawing bytes
 * @param {string} name - file name, shown in the status text
 * @param {number} circleSides - curve tessellation
 */
window.cadOpenDwg = (base64, name, circleSides) =>
  openDwg(
    base64ToArrayBuffer(base64),
    name || 'drawing.dwg',
    circleSides || 100
  )

post('ready')
await openFromNative()
