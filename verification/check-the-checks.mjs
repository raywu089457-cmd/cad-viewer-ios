#!/usr/bin/env node
// Checks that the checks fail when they should.
//
// Two of them were reporting clean for a reason that had nothing to do with the tree being
// clean: `check-main-thread-io` could not see a main-actor method following a nonisolated one,
// and `check-api-usage` had excluded the very name it needed to check. Both were verified by
// hand, defect by defect, over several rounds — and a hand verification is a thing you do once.
//
// This does it every time. For each check it copies the tree, breaks exactly one thing that
// check exists to notice, runs it, and requires a non-zero exit. A check that passes on a
// deliberately broken tree is not a check.
//
//   node verification/check-the-checks.mjs [--verbose]

import { execFileSync } from 'node:child_process'
import { cpSync, mkdtempSync, readFileSync as readRaw, rmSync, writeFileSync as writeRaw, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

/// A checkout on Windows has CRLF line endings; one on CI has LF. Every anchor below is written
/// with a plain newline, so on a developer's machine the edit would silently miss — and a
/// `replace` that matches nothing leaves the tree intact, which reads exactly like a check that
/// works. Reading normalised makes the anchors hold either way.
const readFileSync = path => readRaw(path, 'utf8').replace(/\r\n/g, '\n')
const writeFileSync = (path, text) => writeRaw(path, text, 'utf8')

const here = dirname(fileURLToPath(import.meta.url))
const repo = join(here, '..')
const verbose = process.argv.includes('--verbose')

/// One entry per check that can be shown to notice something.
///
/// `break` gets the copied tree's path and edits one file. It must introduce the defect the
/// check names, not merely an edit the check might not care about.
const cases = [
  {
    check: 'check-main-thread-io.mjs',
    what: 'a file read inside a main-actor method',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/DWGViewer.swift')
      const text = readFileSync(path, 'utf8')
      // `makeUIView` is main-actor through `UIViewRepresentable`, with no `@MainActor` in sight —
      // which is precisely the case the old marker-based rule could not see.
      assert(
        text,
        'func makeUIView(context: Context) -> UIView {',
        'main-thread-io: the anchor `makeUIView` is gone'
      )
      writeFileSync(
        path,
        text.replace(
          'func makeUIView(context: Context) -> UIView {',
          'func makeUIView(context: Context) -> UIView {\n        _ = try? Data(contentsOf: url)'
        )
      )
    }
  },
  {
    check: 'check-api-usage.mjs',
    what: 'a call to a geometry method that does not exist',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/DXFViewer.swift')
      const text = readFileSync(path, 'utf8')
      assert(text, 'ViewTransform.fitting(', 'api-usage: the anchor `ViewTransform.fitting` is gone')
      writeFileSync(path, text.replace('ViewTransform.fitting(', 'ViewTransform.fit('))
    }
  },
  {
    check: 'check-retain-cycles.mjs',
    what: 'a message handler registered strongly',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/DWGViewer.swift')
      const text = readFileSync(path, 'utf8')
      assert(
        text,
        'userContentController.add(proxy, name: "cadEvents")',
        'retain-cycles: the anchor registration is gone'
      )
      writeFileSync(
        path,
        text.replace(
          'userContentController.add(proxy, name: "cadEvents")',
          'userContentController.add(self, name: "cadEvents")'
        )
      )
    }
  },
  {
    check: 'check-actor-isolation.mjs',
    what: 'observable state without main-actor isolation',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/PDFViewer.swift')
      const text = readFileSync(path, 'utf8')
      assert(
        text,
        '@Observable\n@MainActor\nfinal class PDFViewerModel',
        'actor-isolation: the anchor declaration is gone'
      )
      writeFileSync(
        path,
        text.replace('@Observable\n@MainActor\nfinal class PDFViewerModel', '@Observable\nfinal class PDFViewerModel')
      )
    }
  },
  {
    check: 'check-viewer-identity.mjs',
    what: 'a viewer identified by file name',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/RootView.swift')
      const text = readFileSync(path, 'utf8')
      assert(text, '.id(drawing.source)', 'viewer-identity: the anchor .id is gone')
      writeFileSync(path, text.replace('.id(drawing.source)', '.id(drawing.name)'))
    }
  },
  {
    check: 'check-format-consistency.mjs',
    what: 'a format the plist does not declare',
    break: root => {
      const path = join(root, 'ios/CADViewer/Info.plist')
      const text = readFileSync(path, 'utf8')
      assert(text, 'com.adobe.pdf', 'format-consistency: PDF is not in the plist to remove')
      writeFileSync(path, text.replace(/<string>com\.adobe\.pdf<\/string>/g, '<string>com.adobe.removed</string>'))
    }
  },
  {
    check: 'check-pdf-reading-setup.mjs',
    what: 'an explicit scale set even when PDFKit is choosing one',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/PDFViewer.swift')
      const text = readFileSync(path, 'utf8')
      assert(
        text,
        'if !autoScales {',
        'pdf-reading: the anchor condition is gone'
      )
      writeFileSync(
        path,
        text.replace(
          '            if !autoScales {\n                view.scaleFactor = view.scaleFactorForSizeToFit\n            }',
          '            view.scaleFactor = view.scaleFactorForSizeToFit'
        )
      )
    }
  },
  {
    check: 'check-dwg-controls.mjs',
    what: 'a page entry point that Swift calls but the page does not define',
    break: root => {
      const path = join(root, 'ios/web/src/main.js')
      const text = readFileSync(path, 'utf8')
      assert(text, 'window.cadZoomToFit = ', 'dwg-controls: the anchor export is gone')
      writeFileSync(path, text.replace('window.cadZoomToFit = ', 'const removedExport = '))
    }
  },
  {
    check: 'check-inventory.mjs',
    what: 'a check that the README does not list',
    break: root => {
      const path = join(root, 'verification/README.md')
      const text = readFileSync(path, 'utf8')
      assert(text, 'check-mime-coverage.mjs', 'inventory: the row it removes is not there')
      writeFileSync(
        path,
        text
          .split('\n')
          .filter(line => !line.includes('check-mime-coverage.mjs'))
          .join('\n')
      )
    }
  },
  {
    check: 'check-mime-coverage.mjs',
    what: 'an extension in the bundle with no MIME type',
    requiresBuiltBundle: true,
    break: root => {
      const path = join(root, 'ios/DXFGeometry/Sources/DXFGeometry/BundleServing.swift')
      const text = readFileSync(path, 'utf8')
      assert(text, 'case "txt", "md"', 'mime-coverage: the .txt case is not there to remove')
      writeFileSync(path, text.replace('        case "txt", "md": return "text/plain; charset=utf-8"\n', ''))
    }
  }
]

/// Fails loudly when the anchor text is missing, because a `replace` that matched nothing
/// would leave the tree intact and the check would then pass — looking exactly like a check
/// that works.
function assert(text, anchor, message) {
  if (!text.includes(anchor)) throw new Error(message)
}

const failures = []
const results = []

for (const { check, what, break: breakIt, requiresBuiltBundle } of cases) {
  const script = join(here, check)
  if (!existsSync(script)) {
    failures.push(`${check}: no such check`)
    continue
  }
  if (requiresBuiltBundle && !existsSync(join(repo, 'ios', 'web', 'dist'))) {
    results.push({ check, what, outcome: 'skipped: the bundle is not built' })
    continue
  }

  const work = mkdtempSync(join(tmpdir(), 'check-the-checks-'))
  try {
    // Only what the checks read; copying `node_modules` would take minutes.
    for (const part of ['ios', 'verification', '.github', 'samples']) {
      const from = join(repo, part)
      if (existsSync(from)) cpSync(from, join(work, part), { recursive: true })
    }

    // A thunk that throws means the anchor it edits is gone, so this case cannot be verified at
    // all. Reported as its own failure rather than allowed to abort the run, because the anchors
    // drift as the app changes and the whole check would stop being useful.
    try {
      breakIt(work)
    } catch (error) {
      failures.push(`${check}: cannot be verified — ${error.message}. The anchor it edits has moved.`)
      continue
    }
    let passed = true
    let detail = ''
    try {
      execFileSync(process.execPath, [join(work, 'verification', check)], {
        cwd: work,
        stdio: 'pipe',
        timeout: 120_000
      })
    } catch (error) {
      passed = error.status === 0
      const output = `${error.stdout ?? ''}${error.stderr ?? ''}`
      detail = output.split('\n').filter(line => /FAIL|MISMATCH|BLOCKING|LEAKS|ISOLATION/.test(line)).slice(0, 1).join('')
      // 77 means "nothing was checked", which is not a finding either.
      if (error.status === 77) {
        results.push({ check, what, outcome: 'skipped by the check itself' })
        continue
      }
    }

    if (passed) {
      failures.push(`${check} passed on a tree where ${what} was broken${verbose ? `\n    ${detail}` : ''}`)
    } else {
      results.push({ check, what, outcome: 'reported it' })
    }
  } finally {
    rmSync(work, { recursive: true, force: true })
  }
}

for (const { check, what, outcome } of results) {
  console.log(`ok    ${check}: ${outcome} — ${what}`)
}

if (failures.length > 0) {
  console.log('')
  for (const failure of failures) console.log(`FAIL  ${failure}`)
  console.log(`\n${failures.length} check(s) cannot see what they exist for`)
  process.exit(1)
}

console.log(`\n${results.filter(r => r.outcome === 'reported it').length} check(s) confirmed to fail on the defect they name`)
const skipped = results.filter(r => r.outcome !== 'reported it')
if (skipped.length > 0) {
  // Said separately, because a skip is not a confirmation and counting them together would
  // overstate what was verified.
  console.log(`${skipped.length} not verified here: ${skipped.map(r => r.check).join(', ')}`)
}
