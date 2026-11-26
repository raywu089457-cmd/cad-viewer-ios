#!/usr/bin/env bash
# Runs the geometry harnesses.
#
#   ./run.sh verify                      # the 60 arithmetic/geometry checks
#   ./run.sh scenecheck --svg < file.dxf  # flatten a drawing, optionally to SVG
#
# These are separate executables in a separate package, so they exercise DXFGeometry the way
# an app does: through the module boundary. That matters, because the harnesses caught a
# self-import and a missing `import Foundation` that a same-module build would have hidden.
#
# The first run fetches SwiftDXF from GitHub.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-verify}"
shift || true

case "$MODE" in
    verify) exec swift run -c release verify ;;
    freshness)
        # The comparison lives in the tool rather than in a script: the Swift CI image carries
        # neither node nor python, and doing it there means one implementation instead of two.
        # There was a Node version of this (check-fixture-fresh.mjs) that nothing on CI ran.
        swift build -c release --product scenecheck
        exec "$(swift build -c release --show-bin-path)/scenecheck" --verify-fresh ../fixtures/circles.json < ../fixtures/circles.dxf
        ;;
    scenecheck) exec swift run -c release scenecheck "$@" ;;
    *)
        echo "usage: $0 [verify|freshness|scenecheck] [args...]" >&2
        exit 2
        ;;
esac
