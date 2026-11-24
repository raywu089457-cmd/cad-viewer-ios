#!/usr/bin/env bash
# Syntax-checks the app layer without Xcode.
#
# `swiftc -parse` only validates syntax, not types: SwiftUI, WebKit and PDFKit still need
# an Apple SDK to type-check. That is worth having anyway, because a stray brace or a
# broken multi-line string in a file that was written on a machine without Xcode is a
# failure that costs a full round trip to find otherwise.
#
# Usage: ./parse-check.sh
set -uo pipefail
cd "$(dirname "$0")"

failures=0
for file in ios/CADViewer/Sources/CADViewer/*.swift \
            ios/CADViewer/Sources/CADViewerApp/*.swift; do
    [ -e "$file" ] || continue
    if ! swiftc -parse "$file" 2>/tmp/parse-error.txt; then
        echo "PARSE FAIL: $file"
        cat /tmp/parse-error.txt
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    echo "$failures file(s) failed to parse"
    exit 1
fi
echo "all app-layer files parse"
