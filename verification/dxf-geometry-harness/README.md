# Geometry harnesses

Two command-line tools that check the parts which do not need Xcode. They are a separate
package, not targets inside `ios/DXFGeometry`, for two reasons:

- They are executables with top-level code in `main.swift`. SwiftPM would build them for
  every consumer of the library, and they would clash with the library's entry points.
- Living outside means they import `DXFGeometry` the way an app does. That is not academic:
  it is how a self-import and a missing `import Foundation` were caught.

| Tool | Purpose |
|---|---|
| `verify` | tessellation, the ACI palette, viewport framing, pan/zoom maths, file routing, failure messages, bundle path escapes, MIME types, colour batching. Prints its own count. |
| `scenecheck` | flattens a real DXF; `--svg` renders it, `--json` dumps the geometry, `--verify-fresh <path>` compares it with a committed snapshot |

## Running

```bash
./run.sh verify
./run.sh scenecheck --svg < ../../out/example_2018.dxf > drawing.svg
./run.sh scenecheck --json < ../../out/example_2018.dxf | jq .counts
```

The first run fetches SwiftDXF from GitHub.

### Without an Apple SDK

`build-wasm.bat` compiles the same harnesses for `wasm32-wasip1`, which is how they were
developed on Windows. It needs the Swift 6.4.3 toolchain, the WebAssembly SDK, Node, and a
local `SwiftDXF` checkout at the repository root, then:

```bash
./build-wasm.bat
node runwasm.mjs verify.wasm
```

One caveat it papers over: SwiftDXF's `CodePage` guards its CoreFoundation path with
`canImport(CoreFoundation)`, which is true on wasm but lacks `CFStringEncoding`. `mkfiles.js`
narrows that guard to `!os(WASI)` in the staged copy only. Apple platforms are untouched,
which is why the patch lives here rather than in the package.

## What the checks cover

The checks cover what a screenshot cannot prove: that a fit centres the drawing,
that a pinch keeps the point under the fingers fixed, that zooming in and back out returns
to the same view, that panning follows the finger in both axes, that the zoom limits hold
under a hundred gestures, and that a zero-size drawing does not divide by zero.

The canonical suites are `ios/DXFGeometry/Tests` and `ios/CADViewer/Tests` (Swift Testing).
These harnesses mirror the first for machines that cannot run those.
