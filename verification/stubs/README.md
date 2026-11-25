# Type-checking the app layer

The app layer imports SwiftUI, WebKit, PDFKit, os, UIKit and UniformTypeIdentifiers, none of
which exist off Apple platforms. Before this, `swiftc -parse` was the only check on that layer,
and it accepts a stored property declared twice or an argument of the wrong type. Both had been
in this repository.

These stubs declare the platform surface the app uses, so the app can be type-checked against
them plus the real DXFGeometry. It runs on CI in the `Geometry tests and harness` job and reports:

```
7 app source(s) type-check against the stubs
```

## What it found

Real defects in the app, which no other check here could see:

- `DWGViewer` declared a local `webView` that shadowed its own stored property, so the reload
  path's `if let` bound a non-optional.
- `DWGViewer`, `PDFViewer` and `ViewerSchemeHandler` each named a `DXFGeometry` type without
  importing `DXFGeometry`. It stayed invisible because a whole-module build lets a file see its
  siblings' imports.
- `DrawingCanvas` mapped a drag's translation through `CGSize.screenPoint`, an extension that
  existed on `CGPoint` only.
- `webView.load(...)` was called on the optional stored property rather than the page just built.

## What it cannot check

- **The view bodies are never evaluated**, so anything that would only fail at runtime — a wrong
  gesture anchor, a missing asset — is out of reach. This proves the code compiles, not that it
  looks right.
- **The one response construction** in `ViewerSchemeHandler` is substituted before checking. Linux
  Foundation declares `HTTPURLResponse` as an alias of `AnyObject` with no initialiser, and a
  re-exported alias beats a declaration in a stub, so that call cannot be type-checked here. The
  script says so when it substitutes it.
- **`#Preview` blocks are removed.** A macro needs a plugin the stub set cannot ship; the previews
  are not part of what the app does at runtime, and mocking the expansion would only check the
  mock.
- **Nothing here replaces building for iOS.** No Mac runner is available to this repository, so
  this is the closest thing to compiling the layer that exists, not the real thing.

## The stub check

`verification/check-stubs.mjs` runs in seconds and catches the mistakes the type check finds in
nine minutes, one per round:

- a type declared twice, at the top level or twice under the same parent;
- a class member that redeclares what it inherits, and a `mutating` member on a class;
- a parent class that is not `open`, when another file inherits from it;
- a generic parameter that shadows a top-level type of the same name;
- an app file that names a DXFGeometry type without importing it;
- a name the app uses that no stub declares.

Each rule was verified by reintroducing the defect and watching the check fail. Two of them
initially passed while the defect was present, which is how the bugs in the check itself were
found — a check that reports nothing is indistinguishable from a correct tree.

## Layout

| File | What it declares |
| --- | --- |
| `SwiftUI.swift` | views, modifiers, gestures, `Canvas`, `Binding`/`State`, and the Foundation pieces SwiftUI re-exports |
| `WebKit.swift` | `WKWebView`, the scheme handler, script messages |
| `PDFKit.swift` | `PDFView` and its document |
| `UIKit.swift` | re-exports the SwiftUI stub, which owns `UIColor` |
| `os.swift` | `Logger` and its privacy marker |
| `UniformTypeIdentifiers.swift` | `UTType`, built before SwiftUI because that stub names it |
