# Type-checking stubs

The app layer imports SwiftUI, WebKit and PDFKit, none of which exist on a Linux machine or in
this repository's CI. `swiftc -parse` therefore checks syntax and nothing else: it accepts a
stored property declared twice, a wrong argument type, a missing member — anything a real
build would reject.

These stubs declare the part of that surface the app actually uses. They render nothing and
implement nothing; every `body` is `Never`. What they buy is a real type check of the app's own
code: the compiler resolves every name, label and type against these signatures, so a mismatch
in the app is reported here instead of on a Mac nobody has.

`check-app-types.sh` builds them into modules and type-checks the app's sources against them.

## What this does not cover

- Only the declarations the app uses, so a new API call may need adding here first.
- No `@Observable` macro, so `@Observable` classes are checked as plain final classes. Their
  isolation is checked separately by `check-actor-isolation.mjs`.
- No behaviour: a wrong `VStack` is not caught, only a wrong use of one.
