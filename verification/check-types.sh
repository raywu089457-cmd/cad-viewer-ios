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

# Absolute: the script changes directory to build the package, and a relative path stops
# meaning the same thing once it does.
work="$(cd "$(dirname "$0")" && pwd)/.typecheck"
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

# DXFGeometry and SwiftDXF are real libraries. They are built here rather than stubbed: the
# app's use of them is exactly what wants checking, and a stub of a library that size would be
# its own source of wrong answers.
if ! ( cd ../ios/DXFGeometry && swift build > "$work/geometry-build.log" 2>&1 ); then
  echo "DXFGeometry did not build; the test step reports that, so it is not repeated here"
  tail -5 "$work/geometry-build.log"
  exit 1
fi

# `--show-bin-path` is where SwiftPM says its outputs are; the module sits one level up from
# the binaries, whichever spelling that takes on this toolchain.
bin_path="$( cd ../ios/DXFGeometry && swift build --show-bin-path 2>/dev/null )"
search=()
for dir in "$bin_path/Modules" "$bin_path/../Modules" \
           ../ios/DXFGeometry/.build/out/Modules \
           ../ios/DXFGeometry/.build/debug/Modules \
           ../ios/DXFGeometry/.build/release/Modules; do
  if [ -d "$dir" ] && compgen -G "$dir/DXFGeometry.swiftmodule" > /dev/null; then
    search=( -I "$dir" )
    break
  fi
done

if [ "${#search[@]}" -eq 0 ]; then
  echo "cannot find the DXFGeometry module; searched under $bin_path" >&2
  exit 1
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
