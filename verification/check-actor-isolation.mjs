// Checks that UI state is isolated to the main actor.
//
// `@Observable` is a change-tracking macro. It says nothing about which actor may touch the
// property, which is easy to misread — a comment in this project claimed otherwise, and two
// models were left without `@MainActor` while WebKit called into them from callbacks that do
// not promise a thread.
//
// The failure is a data race on view state: no crash, no error, just an interface that
// occasionally shows the wrong thing. That is exactly the kind of defect a compiler finds and
// a person does not.
//
//   node check-actor-isolation.mjs
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const sourceDir = path.join(root, 'ios/CADViewer/Sources/CADViewer')

const problems = []
let inspected = 0

for (const file of fs.readdirSync(sourceDir)) {
  if (!file.endsWith('.swift')) continue
  const text = fs.readFileSync(path.join(sourceDir, file), 'utf8')
  const lines = text.split('\n')
  inspected += 1

  for (const [index, line] of lines.entries()) {
    if (!/^\s*@Observable\s*$/.test(line)) continue

    // Look only at the runs of attribute lines immediately around the macro: before it,
    // skipping doc comments; after it, until the declaration. Doc comments mention
    // `@MainActor` by name, and counting those made this pass on a class without it.
    let hasMainActor = false
    for (let i = index - 1; i >= 0; i -= 1) {
      const candidate = lines[i].trim()
      if (candidate === '') continue
      if (candidate.startsWith('@MainActor')) { hasMainActor = true; break }
      if (candidate.startsWith('@')) continue
      break
    }
    if (!hasMainActor) {
      for (let i = index + 1; i < lines.length; i += 1) {
        const candidate = lines[i].trim()
        if (candidate === '') continue
        if (candidate.startsWith('@MainActor')) { hasMainActor = true; break }
        if (candidate.startsWith('@')) continue
        break
      }
    }
    if (hasMainActor) continue

    problems.push(`${file}:${index + 1} @Observable without @MainActor`)
  }

  // A UI model whose protocol conformance is not nonisolated cannot compile against a
  // @MainActor class, so the callbacks have to say so.
  if (/@MainActor\s*\n\s*final class/.test(text)) {
    for (const [index, line] of lines.entries()) {
      if (!/extension \w+: WK(ScriptMessageHandler|NavigationDelegate|UIDelegate)/.test(line)) {
        continue
      }
      const body = lines.slice(index + 1, index + 12).join('\n')
      if (!/nonisolated/.test(body)) {
        problems.push(
          `${file}:${index + 1} WebKit conformance on a @MainActor class without nonisolated`
        )
      }
    }
  }
}

console.log(`inspected ${inspected} files`)
if (problems.length > 0) {
  console.error(`ISOLATION ${problems.length}:`)
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log('UI state is main-actor isolated')
