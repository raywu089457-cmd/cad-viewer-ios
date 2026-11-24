# Geometry harnesses

Two command-line tools for checking the parts that do not need Xcode, kept out of
`ios/DXFGeometry` so SwiftPM does not try to build them as library targets.

| Tool | Purpose |
|---|---|
| `verify` | the 60 checks: tessellation, ACI palette, viewport framing, pan/zoom maths |
| `scenecheck` | flattens a real DXF; `--svg` renders it, `--json` dumps the geometry |

```bash
./run.sh verify
./run.sh scenecheck --svg < ../../out/example_2018.dxf > drawing.svg
./run.sh scenecheck --json < ../../out/example_2018.dxf | jq .counts
```

`run.sh` stages the geometry sources and the harness into one module, strips the
`import DXFGeometry` lines that would be circular, and compiles with the local toolchain.
Nothing is left behind.

## Why these were built

The app layer needs Xcode for SwiftUI, WebKit and PDFKit. The geometry does not, so the
geometry is where the arithmetic lives — and this is how it was checked: 60 passing checks,
plus a real drawing (`example_2018.dwg` converted to DXF) flattening to 262 polylines,
2 fills and 12 text items with no non-finite coordinates.

The canonical suites are `ios/DXFGeometry/Tests` (Swift Testing) and
`ios/CADViewer/Tests`; these harnesses mirror the first one for machines that cannot run
them.
