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

if (!/^jobs:/m.test(text)) problems.push('no jobs section')

if (problems.length > 0) {
  console.error('checks.yml is malformed:')
  for (const problem of problems) console.error(`  ${problem}`)
  process.exit(1)
}
console.log('checks.yml structure looks sound')
