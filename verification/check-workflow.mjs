// A workflow that does not parse runs no jobs at all: the run reports a failure with an empty
// job list, which reads like an infrastructure problem rather than a syntax error. That is how
// a broken heredoc in checks.yml went unnoticed for two commits.
//
// This is a structural check, not a YAML parse — adding a YAML dependency to a layout script
// that runs on every push is not worth it. It looks for the specific thing that broke.
import fs from 'node:fs'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const file = path.join(root, '.github/workflows/checks.yml')
const text = fs.readFileSync(file, 'utf8')
const lines = text.split('\n')

const problems = []
const opens = lines.filter(line => /<<'?[A-Z]+'?/.test(line)).length
const closes = lines.filter(line => /^[A-Z]+$/.test(line.trim())).length
if (opens !== closes) {
  problems.push(`heredocs: ${opens} opening, ${closes} closing`)
}

// Every line inside a `run: |` block must be indented past the `run:` key. An unindented one
// ends the block, which is the shape the heredoc left behind.
let inRunBlock = false
let runIndent = 0
for (const [index, line] of lines.entries()) {
  if (/\brun:\s*\|/.test(line)) {
    inRunBlock = true
    runIndent = line.match(/^( *)/)[1].length
    continue
  }
  if (!inRunBlock) continue
  if (line.trim() === '') continue
  const indent = line.match(/^( *)/)[1].length
  if (indent <= runIndent) inRunBlock = false
  else if (/^[ ]*(import [a-z]|def [a-z_]+[(])/.test(line)) {
    // Python at the block's own indentation, which only a stray heredoc body looks like.
    problems.push(`line ${index + 1}: looks like a stray heredoc body inside a run block`)
    break
  }
}

// A step is introduced by `- name:` at six spaces. A `run:` or `working-directory:` at the same
// indentation with no `- name:` above it is a key with no step to belong to, which makes the
// whole document unparseable — GitHub then reports a run with no jobs and names it after the
// file, which reads like an infrastructure problem rather than a syntax error.
// A `- name:` introduces a step, and the keys under it belong to that step. When one of them
// appears at the same indentation as a step key with no `- name:` since the last one, a step
// has lost its header — which is what happened when an edit deleted a `- name:` line and left
// its `working-directory:` behind. GitHub then reports a run with no jobs named after the file.
// Inside one step a key may appear once. A repeated `run:` at the same indentation means a
// step header was deleted and its body joined the step above — which is what happened here:
// an edit removed `- name: Check the committed snapshot is current` and left its
// `working-directory:` and `run:` behind, so the document still parsed but the job described
// something nobody wrote.
let currentStepKeys = new Set()
for (const [index, line] of lines.entries()) {
  if (/^ {6}- /.test(line)) { currentStepKeys = new Set(); continue }
  const key = line.match(/^ {8}([a-z][a-z-]*):/)
  if (!key) continue
  if (currentStepKeys.has(key[1])) {
    problems.push(
      "line " + (index + 1) + ": a second " + key[1] + ": in one step, which means a step header"
        + " was deleted and its body joined the one above"
    )
    break
  }
  currentStepKeys.add(key[1])
}
let sawName = true
for (const [index, line] of lines.entries()) {
  // A step may start with `- name:` or with `- uses:`; either begins one.
  if (/^ {6}- (name|uses):/.test(line)) { sawName = true; continue }
  // A step key at eight spaces with no `- name:` since the last step or job boundary.
  if (/^ {8}(run|uses|working-directory|with|env):/.test(line) && !sawName) {
    problems.push("line " + (index + 1) + ": a step key with no - name: before it")
    break
  }
  // A job boundary resets it: the next step starts with its own name.
  if (/^ {2}[a-z][a-z0-9-]*:$/.test(line)) sawName = true
}
let stepOpen = false
for (const [index, line] of lines.entries()) {
  if (/^ {6}- name:/.test(line)) { stepOpen = true; continue }
  if (/^ {2}[a-z][a-z0-9-]*:$/.test(line) || /^ {4}[a-z][a-z-]*:$/.test(line)) { stepOpen = false; continue }
  if (/^ {8}(run|uses|working-directory):/.test(line) && !stepOpen) {
    problems.push("line " + (index + 1) + ": a step key with no name above it")
    break
  }
}
if (!/^jobs:/m.test(text)) problems.push('no jobs section')

if (problems.length > 0) {
  console.error('checks.yml is malformed:')
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log('checks.yml structure looks sound')
