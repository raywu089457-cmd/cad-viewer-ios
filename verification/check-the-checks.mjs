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
import { cpSync, mkdtempSync, mkdirSync, readFileSync as readRaw, rmSync, writeFileSync as writeRaw, existsSync } from 'node:fs'
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
    what: 'a viewer whose identity does not change when the same file is reopened',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/RootView.swift')
      const text = readFileSync(path, 'utf8')
      const anchor = '.id(ViewerID(file: drawing.source, open: openCount))'
      assert(text, anchor, 'viewer-identity: the anchor .id is gone')
      // The file alone was the identity before, which meant reopening an edited drawing kept the
      // viewer and its loaded page.
      writeFileSync(path, text.replace(anchor, '.id(drawing.source)'))
    }
  },
  {
    check: 'check-format-consistency.mjs',
    what: 'a UTI naming an extension the router does not draw',
    break: root => {
      const path = join(root, 'ios/CADViewer/Info.plist')
      const text = readFileSync(path, 'utf8')
      assert(text, '<string>dxf</string>', 'format-consistency: the dxf extension is not there')
      // The typo a UTI is most likely to carry: right type, wrong tag. The app then registers a
      // type no file maps to, and Files shows a generic icon with nothing offering to open it.
      writeFileSync(path, text.replace('<string>dxf</string>', '<string>dxff</string>'))
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
    check: 'check-licences.mjs',
    what: 'a runtime dependency no notice names',
    break: root => {
      const path = join(root, 'THIRD-PARTY-NOTICES.md')
      const text = readFileSync(path, 'utf8')
      assert(text, 'lodash-es', 'licences: the anchor dependency is not named')
      // A dependency dropped from the notices is the failure: the code still ships, and nothing
      // says under what terms.
      writeFileSync(path, text.replace('lodash-es', 'lodash-removed'))
    }
  },
  {
    check: 'check-dwg-assets.mjs',
    what: 'a worker file the page names, missing from the bundle',
    requiresBuiltBundle: true,
    break: root => {
      const path = join(root, 'ios/web/dist/assets/mtext-renderer-worker.js')
      // Removing it is the whole defect: the page names a path and nothing is there.
      rmSync(path, { force: true })
    }
  },
  {
    check: 'check-project-spec.mjs',
    what: 'an Info.plist key a drawing needs, removed',
    break: root => {
      const path = join(root, 'ios/CADViewer/Info.plist')
      const text = readFileSync(path, 'utf8')
      assert(text, 'LSSupportsOpeningDocumentsInPlace', 'project-spec: the anchor key is gone')
      // The plist is tab-indented XML; a literal newline in the pattern would have to match
      // the file byte for byte. Removing the key by regex keeps the edit readable.
      writeFileSync(path, text.replace(/\s*<key>LSSupportsOpeningDocumentsInPlace<\/key>\s*<true\/>/, ''))
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
    check: 'scenecheck-verify-svg',
    what: 'a renderer that drops an entity the file contains',
    // The check lives inside the Swift tool: `--verify-svg` renders and asserts in one run.
    command: [
      'verification/dxf-geometry-harness/runwasm.mjs',
      'work:verification/dxf-geometry-harness/scenecheck.wasm',
      '--verify-svg',
      'work:verification/fixtures/circles.svg'
    ],
    // The drawing goes in on stdin, the same way the tool is fed everywhere else.
    input: 'work:verification/fixtures/circles.dxf',
    break: root => {
      const path = join(root, 'verification/fixtures/circles.dxf')
      const text = readFileSync(path, 'utf8')
      assert(text, 'CIRCLE', 'render-output: the fixture has no CIRCLE to break')
      // A file that says two circles while the renderer draws one is the defect: the counts no
      // longer agree with what the file asked for.
      const at = text.indexOf('CIRCLE')
      writeFileSync(path, text.slice(0, at) + 'REMOVED' + text.slice(at + 6))
    }
  },
  {
    check: 'check-placeholder.mjs',
    what: 'a placeholder page that claims to be ready',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/Resources/dwgviewer/index.html')
      const text = readFileSync(path, 'utf8')
      const anchorText = 'event: "error"'
      assert(text, anchorText, 'placeholder: the error post is gone')
      // A page that says ready leaves the app waiting for a drawing that cannot come.
      writeFileSync(path, text.replace(anchorText, 'event: "ready"'))
    }
  },
  {
    check: 'check-safe-area.mjs',
    what: 'a viewer that stops at the home indicator',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/DWGViewer.swift')
      const text = readFileSync(path, 'utf8')
      const anchorText = '.ignoresSafeArea(edges: .bottom)'
      assert(text, anchorText, 'safe-area: the anchor modifier is gone')
      writeFileSync(path, text.split(anchorText).join('// removed'))
    }
  },
  {
    check: 'check-details-parity.mjs',
    what: 'a viewer with no way to describe the file it has open',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/DWGViewer.swift')
      const text = readFileSync(path, 'utf8')
      const anchorText = 'private var detailsSheet'
      assert(text, anchorText, 'details-parity: the anchor sheet is gone')
      writeFileSync(path, text.replace(anchorText, 'private var removedSheet'))
    }
  },
  {
    check: 'check-reset-completeness.mjs',
    what: 'closing a drawing while leaving the load flag set',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/RootView.swift')
      const text = readFileSync(path, 'utf8')
      const start = text.indexOf('private func reset()')
      const line = '        isLoading = false'
      const at = text.indexOf(line, start)
      if (at < start) throw new Error('reset-completeness: the anchor line is gone')
      // Removing it is the defect: the flag stays set, and the open button is disabled by it.
      writeFileSync(path, text.slice(0, at) + text.slice(at + line.length + 1))
    }
  },
  {
    check: 'check-welcome-claims.mjs',
    what: 'a welcome line describing an app this is not',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/RootView.swift')
      const text = readFileSync(path, 'utf8')
      const anchor = '**PDF** pages are read continuously'
      assert(text, anchor, 'welcome-claims: the anchor line is gone')
      // The sentence that was there: it described a viewer that hands PDFs to another app, while
      // this one embeds PDFKit and draws its own continuous pages.
      writeFileSync(
        path,
        text.replace(anchor, '**PDF** opens in the system reader\n                        //')
      )
    }
  },
  {
    check: 'check-root-toolbar.mjs',
    what: 'a root screen with no way to switch drawings without closing first',
    break: root => {
      const path = join(root, 'ios/CADViewer/Sources/CADViewer/RootView.swift')
      const text = readFileSync(path, 'utf8')
      const anchor = 'Button("Open another", systemImage: "folder")'
      assert(text, anchor, 'root-toolbar: the anchor button is gone')
      writeFileSync(path, text.replace(anchor, 'Button("X", systemImage: "folder")'))
    }
  },
  {
    check: 'check-readme.mjs',
    what: 'a README claim the tree no longer supports',
    break: root => {
      const path = join(root, 'README.md')
      const text = readFileSync(path, 'utf8')
      assert(text, '**仍然未驗證**', 'readme: the anchor section is gone')
      // The sentence that was wrong for several rounds: the README said the app layer could only
      // be syntax-checked while CI was type-checking it.
      writeFileSync(path, text.replace('**仍然未驗證**', '**仍然未驗證，而且證實做不到**'))
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

for (const { check, what, break: breakIt, requiresBuiltBundle, args: extraArgs, command, input } of cases) {
  const script = join(here, check)
  // A case may be a script in this directory, or a command run against the copied tree. The
  // second form is for a check that lives inside a Swift tool, which has no script file.
  if (!command && !existsSync(script)) {
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
    // The root-level files a check reads. Copied by name rather than by copying the root, which
    // would pull in `.git` and every screenshot.
    for (const file of ['THIRD-PARTY-NOTICES.md', 'README.md', 'LICENSE']) {
      const from = join(repo, file)
      if (existsSync(from)) cpSync(from, join(work, file))
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
      // Some checks take arguments: a binary to run, a fixture to feed it. `extraArgs` are
      // resolved against the copied tree so a relative path points at the copy.
      const argv = command
        ? [join(work, command[0]), ...command.slice(1)]
        : [join(work, 'verification', check)]
      for (const arg of extraArgs ?? []) {
        argv.push(arg.startsWith('work:') ? join(work, arg.slice(5)) : arg)
      }
      const stdin = input ? readFileSync(join(work, input.slice(5))) : undefined
      execFileSync(process.execPath, argv, {
        cwd: work,
        input: stdin,
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
