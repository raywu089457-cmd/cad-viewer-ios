#!/usr/bin/env bash
# Type-checks the app layer.
#
# The app imports SwiftUI, WebKit, PDFKit, os and UniformTypeIdentifiers, none of which exist
# off Apple platforms. `swiftc -parse` checks syntax only, and accepts a stored property
# declared twice or a wrong argument type — both of which have been in this repository.
#
# The stubs in `stubs/` declare the part of that surface the app uses. On CI the real
# DXFGeometry and SwiftDXF are resolved by SwiftPM, so the app is checked against them; the
# platform surface is stubbed either way, because no Apple SDK is available there.
#
#   ./check-types.sh
#
# Needs a Swift toolchain and the Swift SDK for WebAssembly.
set -uo pipefail
cd "$(dirname "$0")"

SW="${SWIFT_TOOLCHAIN:-$HOME/AppData/Local/Programs/Swift/Toolchains/6.4.3+Asserts}"
SDK="${SWIFT_WASM_SDK:-${TEMP:-/tmp}/wasmsdk/swift-6.4.3-RELEASE_wasm.artifactbundle/swift-6.4.3-RELEASE_wasm/wasm32-unknown-wasip1}"

if [ ! -d "$SW" ]; then
  echo "SKIPPED: Swift toolchain not found at $SW" >&2
  exit 77
fi
if [ ! -d "$SDK" ]; then
  echo "SKIPPED: wasm SDK not found at $SDK" >&2
  exit 77
fi

PATH="$SW/usr/bin:$PATH"
TARGET=( -target wasm32-unknown-wasip1 -sdk "$SDK/WASI.sdk"
         -resource-dir "$SDK/swift.xctoolchain/usr/lib/swift_static" )

work="$(dirname "$0")/.typecheck"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# The platform stubs, in dependency order: each may import the ones before it.
failures=0
for module in SwiftUI os UniformTypeIdentifiers WebKit PDFKit; do
  stub="stubs/$module.swift"
  if [ ! -f "$stub" ]; then
    echo "STUB MISSING: $stub" >&2
    failures=$((failures + 1))
    continue
  fi
  if ! swiftc "${TARGET[@]}" -emit-module -module-name "$module" -I "$work" \
      -emit-module-path "$work/$module.swiftmodule" "$stub" 2>"$work/$module.log"; then
    echo "STUB FAILED: $module"
    grep -E "error:" "$work/$module.log" | head -6
    failures=$((failures + 1))
  fi
done
if [ "$failures" -gt 0 ]; then
  echo "the stubs do not compile, so nothing was checked" >&2
  exit 1
fi

# DXFGeometry and SwiftDXF are built by SwiftPM where it can, and reused from its build
# directory. They are not stubbed: the app's use of them is exactly what wants checking, and a
# stub of a library this size would be its own source of wrong answers.
modules=()
for candidate in \
    ../ios/DXFGeometry/.build/release/Modules \
    ../ios/DXFGeometry/.build/debug/Modules \
    ../ios/DXFGeometry/.build/*/release/Modules \
    ../ios/DXFGeometry/.build/*/debug/Modules \
    ../verification/dxf-geometry-harness/.build/release/Modules \
    ../verification/dxf-geometry-harness/.build/debug/Modules; do
  for dir in $candidate; do
    if [ -d "$dir" ] && compgen -G "$dir/DXFGeometry.swiftmodule" > /dev/null; then
      modules+=("$dir")
      break 2
    fi
  done
done

if [ "${#modules[@]}" -eq 0 ]; then
  echo "SKIPPED: DXFGeometry has not been built here, so the app cannot be checked against it" >&2
  echo "         run \`swift build\` in ios/DXFGeometry first" >&2
  exit 77
fi

app_sources=( ../ios/CADViewer/Sources/CADViewer/*.swift )
if [ ! -e "${app_sources[0]}" ]; then
  echo "no app sources found; the path is wrong" >&2
  exit 1
fi

search=( "$work" )
for dir in "${modules[@]}"; do search+=( -I "$dir" ); done

if swiftc "${TARGET[@]}" -typecheck -I "$work" "${search[@]}" "${app_sources[@]}" \
    2>"$work/app.log"; then
  echo "${#app_sources[@]} app source(s) type-check against the stubs and DXFGeometry"
else
  grep -E "error:" "$work/app.log" | head -20
  echo "the app layer does not type-check"
  exit 1
fi
