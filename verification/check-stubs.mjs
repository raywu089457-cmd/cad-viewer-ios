#!/usr/bin/env node
// Checks the platform stubs for the class of mistake that has cost the most CI rounds: a type
// declared twice, and a name the app uses that no stub declares.
//
// Neither needs a Swift compiler. The compiler finds them in nine minutes, one per run, which is
// the wrong exchange rate for something a regex can see. This is not a substitute for the type
// check — it is the part of it that can run on every save.
//
// Comments and string literals are stripped first. Every earlier attempt at a check like this
// drowned in its own false positives: a comment says "a View" and the checker reports a missing
// type named `View`, and a reader learns to ignore it.

import { readFileSync, readdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const stubsDir = join(here, 'stubs')
const appDir = join(here, '..', 'ios', 'CADViewer', 'Sources', 'CADViewer')

/// Comments and string contents, so that prose in a comment is not mistaken for code.
function stripSource(text) {
  let out = ''
  let i = 0
  while (i < text.length) {
    if (text.startsWith('//', i)) {
      const end = text.indexOf('\n', i)
      i = end < 0 ? text.length : end
    } else if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2)
      i = end < 0 ? text.length : end + 2
    } else if (text[i] === '"') {
      // A triple-quoted or interpolated string keeps its shape; only the contents go.
      let j = i + 1
      while (j < text.length && text[j] !== '"') j += text[j] === '\\' ? 2 : 1
      out += '""'
      i = j + 1
    } else {
      out += text[i]
      i += 1
    }
  }
  return out
}

const failures = []

const types = /^\s*(?:@[A-Za-z]+\s+)?(?:public |private |fileprivate |internal |open |package )?(?:nonisolated |final )*(struct|class|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)/gm
const extensions = /^\s*(?:public |private |internal )?(?:nonisolated )?(extension)\s+([A-Za-z_][A-Za-z0-9_]*)/gm

const stubs = readdirSync(stubsDir).filter(f => f.endsWith('.swift'))
const names = new Map() // name -> [file…]

for (const file of stubs) {
  const code = stripSource(readFileSync(join(stubsDir, file), 'utf8'))
  const seen = new Map()
  // A nested declaration is legal and shadows the outer name: `Alert.Button` inside `Alert`.
  // Tracking the brace depth is what tells the two apart, and reporting a nested type as a
  // redeclaration is how a check like this earns being ignored.
  let depth = 0
  let scanned = 0
  const at = (index) => {
    for (; scanned < index; scanned += 1) {
      if (code[scanned] === '{') depth += 1
      else if (code[scanned] === '}') depth -= 1
    }
    return depth
  }
  for (const m of code.matchAll(types)) {
    const [, , name] = m
    const line = code.slice(0, m.index).split('\n').length
    const scope = at(m.index)
    if (scope > 0) continue // nested, so the outer name is not being redeclared
    if (seen.has(name)) {
      failures.push(`${file}: '${name}' declared at line ${seen.get(name)} and again at ${line}`)
    } else {
      seen.set(name, line)
    }
    if (!names.has(name)) names.set(name, [])
    if (!names.get(name).includes(file)) names.get(name).push(file)
  }
  // Extensions are listed, since one that names a type no file declares is a typo, but repeating
  // a name is what an extension does — and extending a framework type (`extension URL`) is
  // ordinary Swift.
  for (const m of code.matchAll(extensions)) {
    const name = m[2]
    if (!seen.has(name) && !/^[A-Z]/.test(name)) {
      failures.push(`${file}: extension of '${name}', which is not a type`)
    }
  }
}

// A type declared in two stub files is not automatically wrong — UIKit re-exports UIKit's
// `UIColor` from SwiftUI — but it has to be a re-export, not a second declaration.
for (const [name, files] of names) {
  if (files.length > 1) failures.push(`'${name}' is declared in ${files.join(' and ')}`)
}

// A stub class that inherits from another stub class cannot redeclare what it inherits: Swift
// calls that an illegal override, and it cost three rounds to learn one member at a time.
const classDecl = /^\s*(?:public |)(?:final |)(?:class)\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*([A-Za-z_][A-Za-z0-9_]*))?/gm
const storedMember = /^\s{4}public (?:var|let) ([a-zA-Z_][A-Za-z0-9_]*)/gm
const membersOf = new Map() // class -> Set(member)
// Two passes: a class may inherit from one declared in a file scanned later, and a single pass
// silently checked nothing for it — which is how this went three rounds without noticing.
for (const collect of [true, false]) {
  for (const file of stubs) {
    const code = stripSource(readFileSync(join(stubsDir, file), 'utf8'))
    for (const m of code.matchAll(classDecl)) {
      const [, name, parent] = m
      const rest = code.slice(m.index + m[0].length)
      const end = rest.indexOf('\n}')
      const body = end < 0 ? rest : rest.slice(0, end)
      const own = new Set([...body.matchAll(storedMember)].map(x => x[1]))
      // `mutating` is illegal on a class member. It cost a round when the drawing context became
      // a class and one method kept the keyword.
      if (/\bclass\s+/.test(m[0])) {
        const body = rest.slice(0, end < 0 ? rest.length : end)
        if (/\bmutating\s+(?:func|var)\b/.test(body)) {
          const note = `${file}: '${name}' is a class but has a mutating member`
          if (!failures.includes(note)) failures.push(note)
        }
      }
      if (membersOf.has(parent)) {
        for (const member of own) {
          if (membersOf.get(parent).has(member)) {
            const note = `${file}: '${name}' declares '${member}', which it inherits from '${parent}'`
            if (!failures.includes(note)) failures.push(note)
          }
        }
      }
      // Inheriting across stub files needs `open`, not `public`: the stubs are separate modules,
      // and `public` only reaches the end of the defining one.
      if (parent) {
        const parentFile = stubs.find(f =>
          /(?:^|\n)\s*(?:open|public)\s+class\s+/.test(readFileSync(join(stubsDir, f), 'utf8')) &&
          new RegExp(`\\bclass\\s+${parent}\\b`).test(readFileSync(join(stubsDir, f), 'utf8')))
        if (parentFile && parentFile !== file) {
          const parentCode = readFileSync(join(stubsDir, parentFile), 'utf8')
          if (!new RegExp(`\\bopen\\s+class\\s+${parent}\\b`).test(parentCode)) {
            const note = `${parentFile}: '${parent}' is inherited by '${name}' in ${file}, so it has to be open`
            if (!failures.includes(note)) failures.push(note)
          }
        }
      }
      if (collect && !membersOf.has(name)) membersOf.set(name, own)
    }
  }
}

// Every type-like name the app names must exist in a stub, or the type check will say so in nine
// minutes. Framework names are modules, not types.
  // Framework names are modules, not types.
  const fromModules = /^(SwiftUI|WebKit|PDFKit|UIKit|os|Observation|Foundation|DXFGeometry|UniformTypeIdentifiers|CoreGraphics|Combine|Testing|DXF)$/
const builtins = new Set([
  'Int', 'Double', 'Float', 'String', 'Bool', 'Data', 'URL', 'Void', 'Never', 'Self', 'Any',
  'AnyObject', 'Error', 'Result', 'Array', 'Set', 'Dictionary', 'Optional', 'Task', 'Type',
  'Equatable', 'Hashable', 'Sendable', 'Codable', 'CaseIterable', 'Comparable', 'Identifiable',
  'CustomStringConvertible', 'RawRepresentable', 'OptionSet', 'Actor', 'MainActor',
  // Foundation errors and SwiftDXF types reached through DXFGeometry.
  'URLError', 'DXF',
  // Foundation and SwiftUI members the stubs re-export rather than declare.
  'Binding', 'ForEach', 'Date', 'FileManager', 'NSLock', 'HTTPURLResponse', 'Bundle', 'BundleServing',
  'URLRequest', 'URLResponse', 'URLComponents', 'URLQueryItem', 'NSError', 'DispatchQueue',
])
// Everything the app declares in any of its own files, since they compile as one module.
const appDeclared = new Set()
for (const file of readdirSync(appDir).filter(f => f.endsWith('.swift'))) {
  const code = stripSource(readFileSync(join(appDir, file), 'utf8'))
  for (const m of code.matchAll(types)) appDeclared.add(m[2])
}

// And everything DXFGeometry declares, which the app imports as a module rather than a stub:
// that is the real one, built by SwiftPM, and re-declaring it here would be the mistake.
const geometryDir = join(here, '..', 'ios', 'DXFGeometry', 'Sources', 'DXFGeometry')
for (const file of readdirSync(geometryDir).filter(f => f.endsWith('.swift'))) {
  const code = stripSource(readFileSync(join(geometryDir, file), 'utf8'))
  for (const m of code.matchAll(types)) appDeclared.add(m[2])
}

const declaredSomewhere = new Set([...names.keys(), ...appDeclared])
const missing = new Map()
for (const file of readdirSync(appDir).filter(f => f.endsWith('.swift'))) {
  const code = stripSource(readFileSync(join(appDir, file), 'utf8'))
  const own = new Set([...code.matchAll(types)].map(m => m[2]))
  // A capitalised identifier followed by `(` or `.` is a type in use; one inside a declaration
  // is already counted above.
  for (const m of code.matchAll(/\b([A-Z][A-Za-z0-9_]*)\b(?:\.|\()/g)) {
    const name = m[1]
    if (fromModules.test(name) || builtins.has(name)) continue
    if (declaredSomewhere.has(name) || own.has(name)) continue
    if (!missing.has(name)) missing.set(name, new Set())
    missing.get(name).add(file)
  }
}

for (const [name, files] of [...missing].sort()) {
  failures.push(`'${name}' is used by ${[...files].join(', ')} but no stub declares it`)
}

// Every app file that names a DXFGeometry type has to import DXFGeometry. Two of seven did not,
// and it stayed invisible because each compiled against a sibling file's import. A compiler that
// is handed every file at once still catches it; this says which file, in a second.
const geometryTypes = new Set()
for (const file of readdirSync(geometryDir).filter(f => f.endsWith('.swift'))) {
  const code = stripSource(readFileSync(join(geometryDir, file), 'utf8'))
  for (const m of code.matchAll(types)) {
    // Only public ones: the app cannot name anything else.
    if (new RegExp(`^\\s*public\\s+(?:nonisolated\\s+)?(?:final\\s+)?(?:struct|class|enum|protocol)\\s+${m[2]}\\b`, 'm')
          .test(code)) geometryTypes.add(m[2])
  }
}
for (const file of readdirSync(appDir).filter(f => f.endsWith('.swift'))) {
  const raw = readFileSync(join(appDir, file), 'utf8')
  const code = stripSource(raw)
  if (/^\s*import DXFGeometry\b/m.test(code)) continue
  const used = [...geometryTypes].filter(t => new RegExp(`\\b${t}\\b`).test(code))
  if (used.length > 0) {
    failures.push(`${file}: names ${used.join(', ')} but does not import DXFGeometry`)
  }
}

if (failures.length > 0) {
  for (const f of failures) console.log(f)
  console.log(`\n${failures.length} stub problem(s)`)
  process.exit(1)
}
console.log(`stubs declare ${names.size} type(s); no duplicates, nothing the app names is missing`)
