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
    scenecheck) exec swift run -c release scenecheck "$@" ;;
    *)
        echo "usage: $0 [verify|scenecheck] [args...]" >&2
        exit 2
        ;;
esac
