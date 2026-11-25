# Third-party notices

This app bundles other people's work. Their licences are reproduced here and inside the app
bundle, because a licence that does not travel with the code is not honoured.

## Shipped inside the app

These end up in the app bundle and are distributed to whoever installs it.

| Component | Version | Licence | Where |
|---|---|---|---|
| [LibreDWG](https://github.com/LibreDWG/libredwg) (WebAssembly build) | via `@mlightcad/libredwg-converter` | **GPL-3.0** | `assets/libredwg-web.wasm`, `assets/libredwg-parser-worker.js`, `assets/LICENSE-LibreDWG.txt` |
| [SwiftDXF](https://github.com/SecondMouseAU/SwiftDXF) | 0.6.0 | MIT | linked into the app |
| [MLightCAD cad-simple-viewer](https://github.com/mlightcad/cad-simple-viewer) | 1.7.8 | MIT | `assets/`, `assets/LICENSE-cad-simple-viewer.txt` |
| MLightCAD `data-model` | via cad-simple-viewer | MIT | `assets/data-model-*.js` |
| MLightCAD `mtext-parser`, `mtext-renderer` | via cad-simple-viewer | MIT | `assets/mtext-*.js`, `assets/mtext-renderer-worker.js` |
| MLightCAD `three-renderer` | via cad-simple-viewer | MIT | `assets/three-renderer-*.js` |
| MLightCAD `emf-converter` | via cad-simple-viewer | Apache-2.0 | inside the renderer chunk; attribution in `assets/NOTICE-mlightcad-emf-converter.md` |
| [three.js](https://threejs.org) | via cad-simple-viewer | MIT | `assets/three-*.js` |
| [lodash-es](https://lodash.com) | via cad-simple-viewer | MIT | tree-shaken into the chunks above; no copy of it ships as a file |
| [PDFKit](https://developer.apple.com/documentation/pdfkit) | iOS system framework | Apple SDK terms | not redistributed |

## What GPL-3.0 means here

`libredwg-web.wasm` is GPL-3.0. This repository is MIT, but **the bundled wasm is not**, and
linking it into an app makes that app subject to the GPL as far as that component is
concerned. Shipping this as it stands is fine for personal use, for internal tools, and for
anything published under a GPL-compatible licence. Shipping it as a closed-source App Store
app is not, and the fix is to replace the DWG engine rather than to argue with the licence.

The replacement is one file: `DWGViewer` talks to the page over a small message protocol, so
an ODA Drawings SDK implementation would slot in beside it. `DrawingKind` and everything else
is unaffected.

## Development only

Not shipped, only used to build or to test.

| Component | Licence | Used for |
|---|---|---|
| [Playwright](https://playwright.dev) | Apache-2.0 | the browser regression test |
| [Vite](https://vitejs.dev) | MIT | building the web viewer |
| [vite-plugin-static-copy](https://github.com/sapphi-red/vite-plugin-static-copy) | MIT | copying the workers and the engine into the bundle |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | generating the Xcode project |

## The samples

`samples/` holds four drawings from LibreDWG's `test/test-data`, used by the verification
scripts. They are LibreDWG's test fixtures and carry its licence.
