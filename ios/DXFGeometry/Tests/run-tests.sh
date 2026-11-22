#!/usr/bin/env bash
# Runs the geometry test suites.
#
# The SwiftUI and WebKit layers need Xcode; this package does not, which is why the
# geometry, the viewport maths and the transform live in plain Swift and can be tested on
# any machine with a Swift toolchain.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --parallel
