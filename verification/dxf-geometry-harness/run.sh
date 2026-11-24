#!/usr/bin/env bash
# Builds and runs the two command-line harnesses against a DXF.
#
#   ./run.sh verify                      # the 60 arithmetic/geometry checks
#   ./run.sh scenecheck --svg < file.dxf  # flatten a drawing, optionally to SVG
#
# This exists because the app layer needs Xcode but the geometry does not: the harnesses are
# how the flattening and the view maths were verified on a machine without one.
#
# Requires a Swift toolchain. On Apple platforms the plain one is enough; the Geometry
# package must be fetchable first (`swift package resolve` in ios/DXFGeometry).
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-verify}"
shift || true

GEOMETRY="../ios/DXFGeometry"
SOURCES="$GEOMETRY/Sources/DXFGeometry"

if [ ! -d "$SOURCES" ]; then
    echo "cannot find the geometry sources at $SOURCES" >&2
    exit 1
fi

# Collect the geometry sources and the harness entry point. The harness files import
# `DXFGeometry`/`SwiftDXF`, so they are compiled as one module with those imports stripped.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

stage() {
    local target="$1"
    mkdir -p "$WORK/$target"
    local index=0
    for file in "$SOURCES"/*.swift "$2"; do
        local name
        name="$(basename "$file")"
        # The entry point must stay `main.swift`, or Swift forbids top-level code.
        if [ "$name" != "main.swift" ]; then
            name="$(printf '%03d' "$index")_$name"
        fi
        sed '/^import DXFGeometry$/d' "$file" > "$WORK/$target/$name"
        index=$((index + 1))
    done
}

case "$MODE" in
    verify)
        stage verify "$PWD/verify/main.swift"
        swiftc -O "$WORK"/verify/*.swift -o "$WORK/verify" -I "$GEOMETRY/.build" 2>&1 \
            | grep -v "^$" || true
        "$WORK/verify"
        ;;
    scenecheck)
        stage scenecheck "$PWD/scenecheck/main.swift"
        swiftc -O "$WORK"/scenecheck/*.swift -o "$WORK/scenecheck" -I "$GEOMETRY/.build" 2>&1 \
            | grep -v "^$" || true
        exec "$WORK/scenecheck" "$@"
        ;;
    *)
        echo "usage: $0 [verify|scenecheck] [args...]" >&2
        exit 2
        ;;
esac
