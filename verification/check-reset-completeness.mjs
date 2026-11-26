#!/usr/bin/env node
// Checks that closing a drawing clears the state that closing it is supposed to clear.
//
// `reset()` set `opened` and `failure` to nil and bumped the load generation, but left `isLoading`
// alone. That flag disables the open button and shows the spinner, so picking a second file while
// the first was still parsing left the screen on a spinner that would never finish: the abandoned
// task returns early without resetting it, and the button that would let you recover from that is
// disabled by the same flag.
//
// Every `@State` that a load can set has to be cleared here, or closing is not closing.
//
//   node verification/check-reset-completeness.mjs

import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))

// A Windows checkout has CRLF; the patterns below are written with plain newlines.
const raw = readFileSync(
  join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer', 'RootView.swift'),
  'utf8'
)
const CR = String.fromCharCode(13)
const LF = String.fromCharCode(10)
const root = raw.split(CR + LF).join(LF)

const failures = []
const check = (ok, what) => {
  if (!ok) failures.push(what)
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}`)
}

// The body of `reset`: from its opening brace to the matching closing one. Counting braces is
// enough here because the function contains no nested closure.
const start = root.indexOf('private func reset()')
check(start >= 0, 'the root screen has a reset')

let body = ''
if (start >= 0) {
  const open = root.indexOf('{', start)
  let depth = 0
  for (let i = open; i < root.length; i += 1) {
    if (root[i] === '{') depth += 1
    else if (root[i] === '}') {
      depth -= 1
      if (depth === 0) {
        body = root.slice(open + 1, i)
        break
      }
    }
  }
}
check(body.length > 0, 'reset has a body')

if (body) {
  // State that has to be cleared, and why each one matters if it is not.
  const required = [
    ['opened', 'the drawing on screen'],
    ['failure', 'the error being shown'],
    ['isLoading', 'the spinner, and the button it disables']
  ]
  for (const [name, why] of required) {
    check(
      new RegExp(`${name}\\s*=\\s*(nil|false)`).test(body),
      `reset clears ${name} — ${why}`
    )
  }

  // A load in flight has to be invalidated, or it lands on the next drawing.
  check(/loadGeneration\.begin\(\)/.test(body), 'reset invalidates a load that is still running')

  // Anything else `@State` that a load can set and reset does not clear is one drawing's state
  // leaking into the next. Two are expected to be absent: the picker's own flag, and the open
  // counter, which is an identity rather than state.
  const exempt = new Set(['isPickingFile', 'openCount'])
  for (const match of root.matchAll(/@State private var (\w+)/g)) {
    const name = match[1]
    if (exempt.has(name)) continue
    check(
      // An assignment or a mutating call: `loadGeneration.begin()` invalidates without
      // assigning, and that is the right thing for that type.
      new RegExp(`${name}\\s*=|${name}\\.\\w+\\(`).test(body),
      `reset handles ${name}, declared as @State`
    )
  }
}

if (failures.length > 0) {
  console.log(`\n${failures.length} piece(s) of state survive a close`)
  process.exit(1)
}
console.log('\nclosing a drawing clears what a close is meant to clear')
