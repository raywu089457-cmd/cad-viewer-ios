# Engine bake-off scripts

These are how the DWG engine was chosen. They are kept because the claim in the top-level README
— that the three candidate viewers were compared on real drawings — is only worth something if
it can be re-run. They are **not checks**, none of them runs on CI, and several will not run at
all on a fresh checkout.

They used to sit in `verification/` beside the checks, where every one of them exits non-zero for
one reason or another and a reader had no way to tell a broken check from a historical script.
That is why they are here.

## What each one did

| Script | Purpose | Runs today? |
| --- | --- | --- |
| `test-ml.mjs` | open a drawing in mlightcad's example build and screenshot it | needs `ml-example/`, which is gitignored |
| `test-ml2.mjs` | the same across all four samples | needs `ml-example/` |
| `test-ml3.mjs` | the same on a converted DXF | needs `ml-example/dist/` |
| `test-ff.mjs` | the same for flyfish file-viewer | needs its own checkout |
| `test-webkit.mjs` | both of the above in WebKit at iPhone size | needs both |
| `test-ios-web.mjs` | the app's own DWG bundle in WebKit | needs `ios/web/dist` |
| `serve.mjs` | static server for the mlightcad example build | needs `ml-example/` |
| `serve-cad.mjs` | a server that also answers `__dwg__`, like the app's scheme handler | yes |
| `shot-html.mjs` | render an SVG to PNG, to compare native output | yes |
| `dbg.mjs` | dump the SVG geometry a viewer produced | yes |

## What was compared, and how

Each candidate was given the same four drawings — R12 DXF, and the R2000, R2013 and R2018 DWG
samples — at iPhone size, and the screenshots were compared against the native DXF rendering.
The results are in `shots/` at the repository root.

The conclusion was that the web-based viewer drawing through LibreDWG was the only one that
opened all three DWG formats, and that is what the app ships. `verification/test-dwg-reopen.mjs`
is what checks it now; these scripts are the record of why.

## Running them

Install `playwright` (`npm i` in `verification/` before this moved — there is no `package.json`
here), make sure whatever checkout the script needs exists, and run it from the repository root.
The relative paths are written for that.
