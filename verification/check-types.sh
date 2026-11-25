#!/usr/bin/env bash
# Type-checks the app layer.
#
# The app imports SwiftUI, WebKit, PDFKit, os and UniformTypeIdentifiers, none of which exist
# off Apple platforms. `swiftc -parse` checks syntax only, and accepts a stored property
# declared twice or a wrong argument type — both of which have been in this repository.
#
# The stubs in `stubs/` declare the part of that surface the app uses. They are plain Swift, so
# this runs on any Swift toolchain, including the Linux one in CI. DXFGeometry and SwiftDXF are
# reusing the modules SwiftPM already built there.
#
#   ./check-types.sh
#
# Exit codes: 0 checked and clean, 1 checked and failing, 77 skipped (nothing was checked).
set -uo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "SKIPPED: no swiftc on PATH" >&2
  exit 77
fi

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
  if ! swiftc -emit-module -module-name "$module" -I "$work" \
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

# DXFGeometry and SwiftDXF are real libraries. Where SwiftPM has built them, their module
# interfaces are reused — the app's use of them is exactly what wants checking, and a stub of a
# library that size would be its own source of wrong answers.
search=()
for candidate in \
    ../ios/DXFGeometry/.build/out/Modules \
    ../ios/DXFGeometry/.build/release/Modules \
    ../ios/DXFGeometry/.build/debug/Modules \
    ../ios/DXFGeometry/.build/*/release/Modules \
    ../ios/DXFGeometry/.build/*/debug/Modules; do
  for dir in $candidate; do
    if [ -d "$dir" ] && compgen -G "$dir/DXFGeometry.swiftmodule" > /dev/null; then
      search+=( -I "$dir" )
      break 2
    fi
  done
done

if [ "${#search[@]}" -eq 0 ]; then
  echo "SKIPPED: DXFGeometry has not been built, so the app cannot be checked against it" >&2
  exit 77
fi

app_sources=( ../ios/CADViewer/Sources/CADViewer/*.swift )
if [ ! -e "${app_sources[0]}" ]; then
  echo "no app sources found; the path is wrong" >&2
  exit 1
fi

if swiftc -typecheck -I "$work" "${search[@]}" "${app_sources[@]}" 2>"$work/app.log"; then
  echo "${#app_sources[@]} app source(s) type-check against the stubs"
else
  grep -E "error:" "$work/app.log" | head -20
  echo "the app layer does not type-check"
  exit 1
fi
