// Checks the app layer's calls into DXFGeometry against the real declarations.
//
// The app layer cannot be type-checked here: SwiftUI, WebKit and PDFKit need an Apple SDK.
// But most of what it calls is DXFGeometry, which compiles on this machine. So the argument
// labels and arities of those calls can be checked against the source, which is exactly the
// class of mistake that `swiftc -parse` misses and that would otherwise surface only on a Mac.
//
//   node check-api-usage.mjs
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')

/** Declarations exported by DXFGeometry: name to the labels it accepts. */
function readDeclarations() {
  const sourceDir = path.join(root, 'ios/DXFGeometry/Sources/DXFGeometry')
  const declarations = new Map()

  for (const file of fs.readdirSync(sourceDir)) {
    if (!file.endsWith('.swift')) continue
    const text = fs.readFileSync(path.join(sourceDir, file), 'utf8')

    // func name(label: Type, label: Type = default) -> Type
    for (const match of text.matchAll(/\bfunc\s+([a-zA-Z]+)\s*\(([^)]*)\)/g)) {
      const [, name, rawParameters] = match
      const labels = []
      let depth = 0
      let current = ''
      for (const character of rawParameters) {
        if (character === '(') depth += 1
        if (character === ')') depth -= 1
        if (character === ',' && depth === 0) {
          labels.push(current)
          current = ''
          continue
        }
        current += character
      }
      if (current.trim()) labels.push(current)

      const parsed = labels
        .map(parameter => parameter.split("=")[0].trim())
        .filter(Boolean)
        .map(parameter => {
          // A parameter is written "label name: Type", or "_ name: Type" when the call site
          // takes no label. Split on whitespace, not on ":", or "_ rect" stays one token.
          const [declaration] = parameter.split(":")
          const words = declaration.trim().split(/\s+/)
          if (words.length === 0) return null
          // The first word is the label; "_" means there is none.
          return words[0] === "_" ? null : words[0]
        })
      // Defaulted parameters may be omitted.
      const required = labels
        .map((parameter, index) => ({ parameter, label: parsed[index] }))
        .filter(({ parameter }) => !parameter.includes('='))
        .map(({ label }) => label)

      if (!declarations.has(name)) declarations.set(name, [])
      declarations.get(name).push({ labels: parsed, required })
    }
  }
  return declarations
}

/** Calls the app layer makes into DXFGeometry, with the labels it uses. */
function readCalls() {
  const appDir = path.join(root, 'ios/CADViewer/Sources/CADViewer')
  const calls = []
  // Only the names DXFGeometry owns; a call with any other name belongs to SwiftUI or WebKit.
  // Names that DXFGeometry shares with something else: Logger.add, a view's own fit. A
  // checker that matches on the name alone cannot tell which type a receiver has, so
  // including them would produce false reports rather than findings. Listed rather than
  // guessed at, so the exclusion is visible.
  const ambiguous = new Set(["add", "fit", "open"])
  const owned = new Set(
    [...readDeclarations().keys()].filter(name => !ambiguous.has(name))
  )

  for (const file of fs.readdirSync(appDir)) {
    if (!file.endsWith('.swift')) continue
    const text = fs.readFileSync(path.join(appDir, file), 'utf8')

    for (const match of text.matchAll(/([A-Za-z_][A-Za-z0-9_]*)\(/g)) {
      const name = match[1]
      // A call written `Type.name(` names the type, so the ambiguous-name exclusion does not
      // apply to it: there is no other `fit` it could be. Without this distinction,
      // `ViewTransform.fit` — a typo for `fitting` — was excluded along with a view's own
      // `fit` and went unreported.
      const receiver = text.slice(Math.max(0, match.index - 40), match.index)
      // Only a *type* receiver counts: `ViewTransform.fitting`, not `configuration.userContent
      // Controller.add` — `userContentController` is a value, and its `add` is WebKit's. The
      // identifier immediately before the dot has to start with a capital.
      const lastIdentifier = receiver.match(/([A-Za-z_][A-Za-z0-9_]*)\.$/)
      const qualified = lastIdentifier !== null && /^[A-Z]/.test(lastIdentifier[1])
      if (!owned.has(name) && !(ambiguous.has(name) && qualified)) continue

      // Collect the argument list, balancing brackets.
      let depth = 0
      let index = match.index + match[0].length - 1
      let argumentsText = ''
      for (; index < text.length; index += 1) {
        const character = text[index]
        if (character === '(') {
          depth += 1
          if (depth === 1) continue
        }
        if (character === ')') {
          depth -= 1
          if (depth === 0) break
        }
        argumentsText += character
      }

      // Top-level labels only.
      const labels = []
      let nesting = 0
      let current = ''
      for (const character of argumentsText) {
        if ('([{'.includes(character)) nesting += 1
        if (')]}'.includes(character)) nesting -= 1
        if (character === ',' && nesting === 0) {
          labels.push(current)
          current = ''
          continue
        }
        current += character
      }
      if (current.trim()) labels.push(current)

      const used = labels
        .map(argument => argument.trim())
        .filter(Boolean)
        .map(argument => {
          const colon = argument.indexOf(':')
          // An unlabelled argument (a bare expression) has no colon; it still occupies a
          // parameter position, so it is recorded as null rather than dropped.
          if (colon < 0) return null
          return argument.slice(0, colon).trim()
        })

      calls.push({ name, labels: used, line: text.slice(0, match.index).split('\n').length, file })
    }
  }
  return calls
}

const declarations = readDeclarations()
const calls = readCalls()

const problems = []
for (const call of calls) {
  const candidates = declarations.get(call.name) ?? []
  // A call matches if some overload accepts exactly these labels in order, allowing a
  // trailing run of defaulted parameters to be omitted.
  const matches = candidates.some(candidate => {
    if (call.labels.length > candidate.labels.length) return false
    for (let i = 0; i < call.labels.length; i += 1) {
      if (call.labels[i] !== candidate.labels[i]) return false
    }
    // Any parameters not supplied must be optional.
    const omitted = candidate.labels.slice(call.labels.length)
    return omitted.every(label => !candidate.required.includes(label))
  })
  if (!matches) {
    const expected = candidates
      .map(candidate => candidate.labels.map(label => label ?? '_').join(', '))
      .join(' | ')
    problems.push(
      `${call.file}:${call.line} ${call.name}(${call.labels.map(l => l ?? '_').join(', ')})` +
      ` — declared as ${call.name}(${expected})`
    )
  }
}

console.log(`checked ${calls.length} DXFGeometry calls against ${declarations.size} names`)
if (problems.length > 0) {
  console.error(`MISMATCHED ${problems.length}:`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log('all argument labels match the declarations')
