// A committed snapshot is only worth anything if it still matches what the pipeline produces.
// This regenerates the fixture and fails when the committed copy is stale.
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const scenecheck = process.argv[2]
if (!scenecheck || !fs.existsSync(scenecheck)) {
  console.error('usage: node check-fixture-fresh.mjs <scenecheck binary>')
  process.exit(2)
}

const fixture = path.join(root, 'verification/fixtures/circles.dxf')
const committed = path.join(root, 'verification/fixtures/circles.json')

// The harness is a wasm build on machines without an Apple SDK, so it runs through Node's
// WASI loader rather than as an executable.
const runner = path.join(root, 'verification/dxf-geometry-harness/runwasm.mjs')
// stderr carries the harness's progress log and a WASI warning; stdout is the JSON alone.
const fresh = execFileSync(
  process.execPath,
  [runner, scenecheck, '--json'],
  {
    input: fs.readFileSync(fixture),
    maxBuffer: 32 * 1024 * 1024,
    stdio: ['pipe', 'pipe', 'ignore']
  }
).toString()

const a = JSON.parse(fs.readFileSync(committed, 'utf8'))
const b = JSON.parse(fresh)

// Compare the geometry, not the formatting.
const same =
  a.polylines.length === b.polylines.length &&
  a.polylines.every((polyline, i) => {
    const other = b.polylines[i]
    return (
      polyline.points.length === other.points.length &&
      polyline.points.every(
        (point, j) =>
          Math.abs(point.x - other.points[j].x) < 1e-9 &&
          Math.abs(point.y - other.points[j].y) < 1e-9
      )
    )
  })

if (!same) {
  console.error('the committed circles.json no longer matches the pipeline')
  console.error('regenerate it: scenecheck --json < verification/fixtures/circles.dxf')
  process.exit(1)
}
console.log('the fixture snapshot is current')
