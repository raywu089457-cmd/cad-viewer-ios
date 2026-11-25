# Verification

Two different things live under this directory, and they are worth keeping apart:

- **Checks**, which run on every push and can fail a build. They say whether the tree is right.
- **Record**, which says why the app is built the way it is. Nothing here runs them.

`engine-bakeoff/` holds the second. Everything else is the first.

## The checks

| Script | What it catches |
| --- | --- |
| `check-workflow.mjs` | a workflow that would silently run no jobs |
| `check-stubs.mjs` | a stub type declared twice, a member that redeclares what it inherits, a generic parameter shadowing a type, an app file using `DXFGeometry` without importing it |
| `check-types.sh` | the app layer failing to type-check against the platform stubs — needs a toolchain with the Observation plugin |
| `check-api-usage.mjs` | the app calling the geometry with the wrong argument labels |
| `check-main-thread-io.mjs` | a file read on the UI layer, which freezes it |
| `check-retain-cycles.mjs` | a message handler registered strongly, which leaks the page and its wasm engine |
| `check-actor-isolation.mjs` | `@Observable` state without `@MainActor`, a data race on the UI |
| `check-mime-coverage.mjs` | an extension in the built bundle with no MIME type, which WebKit downloads instead of rendering |
| `check-pdf-fixtures.mjs` | the PDF open verdict disagreeing with the files it judges |
| `check-fixture-fresh.mjs` | the committed geometry snapshot drifting from the fixture — takes the `scenecheck` binary as its argument, which `dxf-geometry-harness/run.sh` supplies |
| `check-viewer-identity.mjs` | a viewer identified by file name, so a same-named file in another folder is not rebuilt |
| `check-inventory.mjs` | this list drifting from what is on disk, or a bake-off script creeping into CI |
| `make-pdf.mjs` | regenerates the PDF fixtures, so a change to either is reviewable in a diff |
| `parse-check.sh` | a Swift syntax error, on a machine with no Apple SDK |
| `verify-coordinates.mjs` | flattened geometry disagreeing with the DXF, read by a second independent reader |
| `patch-swiftdxf-for-linux.sh` | the dependency's `canImport(CoreFoundation)` guard, which is wrong on Linux |
| `test-dwg-reopen.mjs` | a second DWG failing to open on an already-loaded page, for each format the samples cover |

Two conventions matter here:

- **77 means skipped, 1 means failed.** A check that cannot run says which; it does not pass
  quietly and it does not cry wolf.
- **A check that has never been seen to fail is not known to work.** Each rule in
  `check-stubs.mjs` and each new check was verified by reintroducing the defect it exists for.

## The geometry harness

`dxf-geometry-harness/` holds the checks that need no browser and no Apple SDK: the geometry, the
file routing, the load verdicts, the gesture arithmetic, the PDF zoom range. It compiles the same
sources the app uses, for wasm, so it runs on a Windows machine.

```bash
cd verification/dxf-geometry-harness
./run.sh verify            # on a Mac
build-wasm.bat && node runwasm.mjs verify.wasm   # everywhere else
```

`ios/DXFGeometry` also has its own Swift Testing suite, which CI runs on Linux with the
SwiftDXF dependency patched for that platform.

## Samples

`samples/` holds four files from LibreDWG's test data — `example_2000.dwg`, `example_2013.dwg`,
`example_2018.dwg`, `example_r12.dxf`. Every DWG format there is opened by
`test-dwg-reopen.mjs` on CI, because the engine handles them differently and a format nothing
opens is a format nothing checks.

## Why the app looks like this

`engine-bakeoff/` has the scripts that compared three DWG viewers on those four drawings, and its
README says what each one did and what the comparison concluded. Those scripts are not checks and
several need a checkout that is not committed.
