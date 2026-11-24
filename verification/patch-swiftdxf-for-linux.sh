#!/usr/bin/env bash
# Patches the resolved SwiftDXF checkouts so the package tests can run on Linux.
#
# SwiftDXF's `CodePage` decodes code pages through CoreFoundation's `CFStringEncoding`, behind
# `#if canImport(CoreFoundation)`. On Linux that import succeeds — swift-corelibs-foundation
# provides the module — but the CFString* symbols are absent, so the build fails. The guard is
# the wrong question; the right one is whether those symbols exist.
#
# Rather than fork the dependency, this narrows the guard in the checkouts SwiftPM already
# fetched. It is the same patch `mkfiles.js` applies for the wasm harness, for the same
# reason, and it runs on CI only: a Mac build is untouched.
#
# There is usually more than one checkout — DXFGeometry and the harness each resolve SwiftDXF
# separately — and patching only the first leaves the second failing with the same symbols.
#
#   ./patch-swiftdxf-for-linux.sh [checkout ...]
set -euo pipefail

if [ "$#" -gt 0 ]; then
  checkouts="$*"
else
  checkouts="$(find . -path '*/.build/checkouts/SwiftDXF' -type d)"
fi

if [ -z "$checkouts" ]; then
  echo "cannot find a SwiftDXF checkout; run this from the repository root" >&2
  exit 1
fi

patched=0
for checkout in $checkouts; do
  file="$checkout/Sources/SwiftDXF/CodePage.swift"
  if [ ! -f "$file" ]; then
    echo "cannot find CodePage.swift under $checkout" >&2
    exit 1
  fi

  if grep -q 'canImport(CoreFoundation) && !os(Linux)' "$file"; then
    echo "already patched: $file"
    continue
  fi

  # The guard, narrowed to the platforms where those symbols are actually present.
  sed -i 's/#if canImport(CoreFoundation)$/#if canImport(CoreFoundation) \&\& !os(Linux)/' "$file"

  if ! grep -q 'canImport(CoreFoundation) && !os(Linux)' "$file"; then
    echo "the patch did not apply to $file; CodePage.swift may have changed" >&2
    exit 1
  fi
  echo "patched $file"
  patched=$((patched + 1))
done

echo "$patched checkout(s) patched"
