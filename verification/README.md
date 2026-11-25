# Verification harness

The scripts used to check the two engines against real drawings. They are kept because the
claims in the top-level README are only worth anything if they can be re-run.

## What is here

| Script | Purpose |
|---|---|
| `serve.mjs` | static server for the mlightcad example build |
| `serve-cad.mjs` | static server that also answers `__dwg__`, like the app's scheme handler |
| `test-ml.mjs`, `test-ml2.mjs`, `test-ml3.mjs` | open DWG/DXF in mlightcad and screenshot |
| `test-ff.mjs` | the same for flyfish file-viewer |
| `test-webkit.mjs` | both of the above in WebKit at iPhone size |
| `test-ios-web.mjs` | the app's own DWG bundle in WebKit |
| `test-dwg-reopen.mjs` | the reopen path: a second DWG on an already-loaded page |
| `shot-html.mjs` | render an SVG to PNG, for comparing native output |
| `dbg.mjs` | inspect the SVG geometry a viewer produced |
| `parse-check.sh` | syntax-check the SwiftUI/WebKit/PDF files without Xcode |
| `verify-coordinates.mjs` | cross-check flattened geometry against the DXF, with its own reader |
| `check-api-usage.mjs` | the app layer's calls into the geometry, checked against the declarations |
| `check-main-thread-io.mjs` | file reads in the UI layer, which would freeze it |
| `check-retain-cycles.mjs` | strong message-handler registrations, which leak the page |
| `check-actor-isolation.mjs` | `@Observable` state without `@MainActor`, a data race on the UI |
| `dxf-geometry-harness/` | the geometry, routing and arithmetic harnesses |

## Running one

```bash
npm install                      # playwright
npx playwright install chromium webkit
node serve.mjs <dir> 8099 &
node test-ml2.mjs
```

## What the checks concluded

- LibreDWG's CLI reads R2000, R2013 and R2018 DWG.
- mlightcad opens all three plus DXF, with no console errors.
- flyfish opens them too, but only after `cad.wasmPath` and `cad.workerUrl` are set by hand.
- SwiftDXF parses DXF correctly but does not read DWG at all.
- Both web viewers behave the same in WebKit (Safari's engine) at iPhone size.

The geometry core has its own harness in `dxf-geometry-harness/`, with no
browser needed. Run it with `./run.sh verify` there, or `build-wasm.bat` if the machine has
no Apple SDK.

## Samples

`samples/` holds four files from LibreDWG's test data (`example_2000.dwg`,
`example_2013.dwg`, `example_2018.dwg`, `example_r12.dxf`), used by every script here.

## Running on Linux

Most of this runs anywhere, but the Swift checks do not: SwiftDXF decodes code pages through
CoreFoundation's `CFStringEncoding`, guarded by `canImport(CoreFoundation)`, which is true on
Linux where those symbols are absent. Upstream only tests on macOS. CI confirmed the same
failure, which is why the workflow here checks the repository layout and the DWG web bundle
instead of pretending to test Swift it cannot compile.
