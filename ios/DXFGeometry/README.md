# DXFGeometry

Turns a DXF file into something a renderer can draw, plus the view maths a viewer needs.

Plain Swift with no UIKit, CoreGraphics or SwiftUI, so it builds and is fully testable
without Xcode — which is why the pan/zoom arithmetic, the part that is hardest to eyeball,
lives here rather than in the view.

```swift
import DXFGeometry
import SwiftDXF

var options = DXF.ReadOptions()
options.expandBlocks = true      // flatten INSERTs
options.skipPaperSpace = true    // model space only

let drawing = try DXF.read(data: fileData, options: options)
let scene = SceneBuilder().build(drawing)
let viewport = Viewport.fit(points: scene.samplePoints, fallback: scene.bounds)

var transform = ViewTransform.fitting(viewport!.bounds, in: ScreenSize(width: 390, height: 844))
transform.zoom(by: 2, around: ScreenPoint(x: 195, y: 422))
transform.pan(by: ScreenPoint(x: -40, y: 10))
```

## What it handles

`SceneBuilder` flattens every entity SwiftDXF models:

- `LINE`, `CIRCLE`, `ARC`, `ELLIPSE`, `POINT`
- `LWPOLYLINE` / `POLYLINE` including bulges (the arcs between vertices)
- `SPLINE`, sampled with de Boor's algorithm, rational and non-rational
- `HATCH` solids, with islands as holes
- `SOLID`, `3DFACE`, `WIPEOUT`, `LEADER`
- `TEXT` / `MTEXT`, positioned and rotated
- `DIMENSION`, rebuilt from its definition points

Curves are tessellated to a chord tolerance expressed as a fraction of the drawing
diagonal, so a millimetre drawing and a metre drawing look equally smooth.

## Coordinates

Drawing space is y-up, screen space is y-down, and `ViewTransform` is the only place the
flip happens. `scale` is screen points per drawing unit, so zooming in multiplies it.

## Testing

```bash
swift test
```

`Sources/verify` is a dependency-free harness with the same assertions, for machines
without XCTest/Swift Testing; it exists because the geometry was developed and checked on
Linux and Windows before ever reaching Xcode.
