# Screenshots

Two of these are shown on the front page of the repository. The rest are the record of how the DWG
engine was chosen — the same four drawings through each candidate, at iPhone size — and a few
comparisons between the native DXF rendering and each web viewer.

Nothing here is checked by CI: they are pictures, and the claims they support are in
`verification/engine-bakeoff/README.md`.

## Shown in the top-level README

| File | What it shows |
| --- | --- |
| `native-dxf-drawing.png` | `example_r12.dxf` drawn by this app's own Canvas renderer |
| `dwg-webview-ios.png` | a DWG in the bundled web viewer, at iPhone size |

## The three candidates, same drawings

`ml-` is mlightcad, `ff-` is flyfish file-viewer, `webkit-` is either of them in Safari's engine at
iPhone size. The suffix is the drawing.

| | R2000 | R2013 | R2018 | R12 DXF | other |
| --- | --- | --- | --- | --- | --- |
| mlightcad | `ml-example_2000.dwg.png` | `ml-example_2013.dwg.png` | — | `ml-example_r12.dxf.png` | `ml-dwg.png`, `ml-libredwg-converted-dxf.png` |
| flyfish | `ff-example_2000.dwg.png` | — | `ff-example_2018.dwg.png` | `ff-example_r12.dxf.png` | — |
| WebKit | — | — | `webkit-ml-2018.png` | — | `webkit-ff-2018.png` |

The gaps are the comparison: flyfish was tried on R2000 and R2018 but not R2013, and mlightcad was
not tried on R2018 because it was already the one being kept.

## Native versus web

| File | What it shows |
| --- | --- |
| `native-dxf-r12.png` | the app's renderer on the R12 drawing |
| `swiftdxf-svg.png` | SwiftDXF's own SVG for the same file, before this project's colour and framing |
| `cmp-native-r12.png`, `cmp-native-2018.png` | native rendering beside the web one, for comparing |

The `.svg` files are the vector originals those PNGs came from; `dim3.*` and `cmp-native-*.svg`
were the dimension-text investigation, and `e2018.json` is the flattened scene for
`example_2018.dwg`.
