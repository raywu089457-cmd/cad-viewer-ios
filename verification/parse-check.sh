#!/usr/bin/env bash
# Syntax-checks the app layer without Xcode.
#
# `swiftc -parse` validates syntax, not types: SwiftUI, WebKit and PDFKit still need an Apple
# SDK to type-check. That is worth having anyway, because a stray brace or a broken multi-line
# string in a file written on a machine without Xcode costs a full round trip to find.
#
# It is a weak check and the output says so. Everything stronger, including the type check
# itself, needs macOS: see the header of .github/workflows/checks.yml.
#
# Usage: ./parse-check.sh
set -uo pipefail

# Paths are relative to the repository root, not to this script. An earlier version changed
# directory first and then looked for `ios/...`, found nothing, skipped every file and
# printed success — the one outcome a test must never produce.
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v swiftc >/dev/null 2>&1; then
    # Absence of a toolchain is not a pass and not a failure: nothing was checked.
    echo "SKIPPED: no swiftc on PATH, so no syntax was checked" >&2
    exit 77
fi

files=(
    ios/CADViewer/Sources/CADViewer/*.swift
    ios/CADViewer/Sources/CADViewerApp/*.swift
    ios/DXFGeometry/Sources/DXFGeometry/*.swift
)

failures=0
parsed=0
for file in "${files[@]}"; do
    [ -e "$file" ] || continue
    parsed=$((parsed + 1))
    if ! swiftc -parse "$file" 2>"$root/parse-error.txt"; then
        echo "PARSE FAIL: $file"
        cat "$root/parse-error.txt"
        failures=$((failures + 1))
    fi
done
rm -f "$root/parse-error.txt"

# Finding no files is a failure, not a pass.
if [ "$parsed" -eq 0 ]; then
    echo "no Swift files found to check; the paths are wrong" >&2
    exit 1
fi

if [ "$failures" -gt 0 ]; then
    echo "$failures of $parsed file(s) failed to parse"
    exit 1
fi

echo "$parsed file(s) parse (syntax only; types need macOS)"
