// Independent cross-check of the flattened geometry.
//
// Everything else in this repository checks the pipeline against itself: the harness and the
// app share SceneBuilder, so a bug in the flattening passes both. This reads the DXF text
// directly — its own small parser, sharing no code with the Swift side — and compares the
// LINE and CIRCLE geometry with what the pipeline claims.
//
//   node verify-coordinates.mjs <file.dxf> <geometry.json>
//
// The JSON comes from: scenecheck --json < file.dxf
import fs from 'node:fs'

const [dxfPath, jsonPath] = process.argv.slice(2)
if (!dxfPath || !jsonPath) {
  console.error('usage: node verify-coordinates.mjs <file.dxf> <geometry.json>')
  process.exit(2)
}

/** Reads the DXF as (group code, value) pairs. */
function readPairs(text) {
  const lines = text.split(/\r?\n/)
  const pairs = []
  for (let i = 0; i + 1 < lines.length; i += 2) {
    const code = Number.parseInt(lines[i].trim(), 10)
    if (Number.isNaN(code)) break
    pairs.push([code, lines[i + 1]])
  }
  return pairs
}

/**
 * Extracts LINE segments and CIRCLE centres from the ENTITIES section.
 *
 * Deliberately minimal: only the entity types whose coordinates the check compares, and only
 * the model-space ones, matching what the pipeline reads.
 */
function readEntities(pairs) {
  const lines = []
  const circles = []
  let inEntities = false
  let current = null

  const finish = () => {
    if (!current) return
    if (current.type === 'LINE' && current.v[10] !== undefined && current.v[11] !== undefined) {
      lines.push({
        a: [current.v[10], current.v[20]],
        b: [current.v[11], current.v[21]]
      })
    }
    if (current.type === 'CIRCLE' && current.v[10] !== undefined && current.v[40] !== undefined) {
      circles.push({ c: [current.v[10], current.v[20]], r: current.v[40] })
    }
    current = null
  }

  for (let i = 0; i < pairs.length; i += 1) {
    const [code, value] = pairs[i]
    if (code === 0) {
      finish()
      const name = value.trim()
      if (name === 'SECTION') {
        inEntities = pairs[i + 1]?.[0] === 2 && pairs[i + 1]?.[1].trim() === 'ENTITIES'
        continue
      }
      if (name === 'ENDSEC') {
        inEntities = false
        continue
      }
      current = inEntities ? { type: name, v: {} } : null
      continue
    }
    if (current && code !== undefined) {
      const number = Number.parseFloat(value)
      if (!Number.isNaN(number)) current.v[code] = number
    }
  }
  finish()
  return { lines, circles }
}

const dxf = fs.readFileSync(dxfPath, 'utf8')
const geometry = JSON.parse(fs.readFileSync(jsonPath, 'utf8'))
const { lines, circles } = readEntities(readPairs(dxf))

const failures = []
let checks = 0

function check(ok, label) {
  checks += 1
  if (!ok) failures.push(label)
}

/** Every LINE in the file must appear as a polyline with the same two endpoints. */
const flattenedSegments = new Set()
for (const polyline of geometry.polylines) {
  if (polyline.points.length !== 2) continue
  const [a, b] = polyline.points
  // Both orders: the pipeline may follow the file or normalise.
  flattenedSegments.add(`${round(a.x)},${round(a.y)}|${round(b.x)},${round(b.y)}`)
  flattenedSegments.add(`${round(b.x)},${round(b.y)}|${round(a.x)},${round(a.y)}`)
}

function round(value) {
  return Math.abs(value) < 1e-6 ? 0 : Number(value.toFixed(6))
}

for (const line of lines) {
  const key = `${round(line.a[0])},${round(line.a[1])}|${round(line.b[0])},${round(line.b[1])}`
  check(
    flattenedSegments.has(key),
    `LINE ${key} is missing from the flattened geometry`
  )
}

/**
 * Every CIRCLE must appear as a closed run whose points are all on its radius.
 *
 * Matched by centre rather than by order, because blocks and expansion can reorder them.
 */
const closedRuns = geometry.polylines.filter(polyline => polyline.closed)
for (const circle of circles) {
  const match = closedRuns.find(polyline =>
    polyline.points.every(point => {
      const dx = point.x - circle.c[0]
      const dy = point.y - circle.c[1]
      return Math.abs(Math.hypot(dx, dy) - circle.r) < 1e-6
    })
  )
  check(
    match !== undefined,
    `CIRCLE at ${circle.c} r=${circle.r} is missing or off-radius`
  )
}

console.log(
  `${dxfPath.split(/[\\/]/).pop()}: ${lines.length} LINE, ${circles.length} CIRCLE ` +
  `against ${geometry.polylines.length} polylines`
)
if (failures.length > 0) {
  console.error(`FAILED ${failures.length} of ${checks}`)
  for (const failure of failures.slice(0, 10)) console.error(`  ${failure}`)
  process.exit(1)
}
console.log(`PASS ${checks} coordinate checks`)
