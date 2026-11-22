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
| `shot-html.mjs` | render an SVG to PNG, for comparing native output |
| `dbg.mjs` | inspect the SVG geometry a viewer produced |

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

The geometry core has its own harness (`ios/DXFGeometry/Sources/verify`) with 60 checks;
that one needs no browser.

## Samples

`samples/` holds four files from LibreDWG's test data (`example_2000.dwg`,
`example_2013.dwg`, `example_2018.dwg`, `example_r12.dxf`), used by every script here.
