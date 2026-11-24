#!/usr/bin/env bash
# Patches the resolved SwiftDXF checkout so the package tests can run on Linux.
#
# SwiftDXF's `CodePage` decodes code pages through CoreFoundation's `CFStringEncoding`, behind
# `#if canImport(CoreFoundation)`. On Linux that import succeeds — swift-corelibs-foundation
# provides the module — but the CFString* symbols are absent, so the build fails. The guard is
# the wrong question; the right one is whether those symbols exist.
#
# Rather than fork the dependency, this narrows the guard in the checkout SwiftPM already
# fetched. It is the same patch `mkfiles.js` applies for the wasm harness, for the same
# reason, and it is applied at build time on CI only: a Mac build is untouched.
#
#   ./patch-swiftdxf-for-linux.sh [checkout-path]
set -euo pipefail

checkout="${1:-}"
if [ -z "$checkout" ]; then
  # Where SwiftPM puts a resolved dependency.
  checkout="$(find . -path '*/.build/checkouts/SwiftDXF' -type d -print -quit)"
fi

if [ -z "$checkout" ] || [ ! -d "$checkout" ]; then
  echo "cannot find the SwiftDXF checkout; pass its path as an argument" >&2
  exit 1
fi

file="$checkout/Sources/SwiftDXF/CodePage.swift"
if [ ! -f "$file" ]; then
  echo "cannot find CodePage.swift under $checkout" >&2
  exit 1
fi

if grep -q 'canImport(CoreFoundation) && !os(Linux)' "$file"; then
  echo "already patched"
  exit 0
fi

# The guard, narrowed to the platforms where those symbols are actually present.
sed -i 's/#if canImport(CoreFoundation)$/#if canImport(CoreFoundation) \&\& !os(Linux)/' "$file"

if ! grep -q 'canImport(CoreFoundation) && !os(Linux)' "$file"; then
  echo "the patch did not apply; CodePage.swift may have changed" >&2
  exit 1
fi

echo "patched $file"
