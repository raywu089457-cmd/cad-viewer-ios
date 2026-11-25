# Type-checking stubs — attempted, not yet finished

The app layer imports SwiftUI, WebKit, PDFKit, os, UIKit and UniformTypeIdentifiers, none of
which exist off Apple platforms. `swiftc -parse` is therefore the only check on that layer in
CI, and it accepts a stored property declared twice or a wrong argument type. Both have been in
this repository.

These stubs were an attempt to fix that: declare the platform surface, then type-check the app
against it plus the real DXFGeometry.

## How far it got

The stubs compile, DXFGeometry builds, and the check reached the app's own code. It then
reported real findings — one of them useful:

- `PDFViewer` imports UIKit by name, which the SwiftUI stub does not provide. Fixed with a
  separate `UIKit.swift`.

And then one that stopped it:

- `@Observable` and `@ObservationIgnored` are macros. A macro needs its plugin, which ships with
  the toolchain only for targets it was built for. The wasm SDK has `Observation.swiftmodule`
  but no plugin, so the two files that use `@Observable` cannot be type-checked this way.

Two of the seven app files use it, and the other five reference them, so the whole layer is
blocked.

## What would finish it

- A toolchain whose Observation plugin can be loaded for the target being checked. On a Mac
  with the iOS SDK this is moot: the real build already does it.
- Or splitting the two `@Observable` models into their own module behind a protocol, so the
  rest could be checked without them. That is a change to the app's structure for the sake of
  the test, which is the wrong trade at this size.

## What is kept

The stubs and `check-types.sh` stay in the tree. They are the closest thing to compiling this
layer that exists here, they document exactly which API surface the app uses, and if the
Observation problem is ever solved they work as they are.

They are not run on CI, because a check that cannot pass is not a check.
