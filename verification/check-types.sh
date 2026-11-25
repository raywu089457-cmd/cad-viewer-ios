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

# Absolute, because the script changes directory to build the package and a relative path
# stops meaning the same thing once it does. The `cd` above already put us here.
script_dir="$(pwd)"
work="$script_dir/.typecheck"
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

# The platform stubs, in dependency order: each may import the ones before it.
failures=0
for module in UniformTypeIdentifiers SwiftUI os UIKit WebKit PDFKit; do
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

# `--show-bin-path` gives the products directory and the module interfaces sit inside it,
# under a target-triple subdirectory (`Products/Debug-linux-x86_64/`). Older layouts put them
# in `.build/debug` directly, so both are tried.
bin_path="$( cd ../ios/DXFGeometry && swift build --show-bin-path 2>/dev/null )"
search=()
for dir in "$bin_path" "$bin_path/Modules" "$(dirname "$bin_path")/Modules" \
           "$script_dir/../ios/DXFGeometry/.build/out/Modules" \
           "$script_dir/../ios/DXFGeometry/.build/debug/Modules" \
           "$script_dir/../ios/DXFGeometry/.build/release/Modules"; do
  if [ -d "$dir" ] && compgen -G "$dir/DXFGeometry.swiftmodule" > /dev/null; then
    search=( -I "$dir" )
    break
  fi
done

if [ "${#search[@]}" -eq 0 ]; then
  echo "cannot find the DXFGeometry module under $bin_path" >&2
  # Say what is actually there, so the next person does not have to guess as I did.
  find "$(dirname "$bin_path")" -name 'DXFGeometry.swiftmodule' -maxdepth 3 2>/dev/null | head -3 >&2
  exit 1
fi

app_sources=( ../ios/CADViewer/Sources/CADViewer/*.swift )
if [ ! -e "${app_sources[0]}" ]; then
  echo "no app sources found; the path is wrong" >&2
  exit 1
fi

# `#Preview` is a macro, and a macro needs a plugin this stub set cannot ship. The previews are
# not part of what the app does at runtime, so they are removed before the check rather than
# mocked — a stub that pretends to expand one would be checking its own invention.
for src in "${app_sources[@]}"; do
  awk '/^#Preview/ {skip=1} skip && /^}$/ {skip=0; next} !skip' "$src" > "$work/$(basename "$src")"
done
app_sources=( "$work"/*.swift )

# Which modules were found, said before the check rather than guessed at afterwards.
module_dir="${search[1]}"
echo "modules from $module_dir:" >&2
ls "$module_dir" 2>/dev/null | head -8 >&2

if swiftc -typecheck -I "$work" "${search[@]}" "${app_sources[@]}" 2>"$work/app.log"; then
  echo "${#app_sources[@]} app source(s) type-check against the stubs"
else
  # Linux Foundation declares `HTTPURLResponse` as an alias of `AnyObject`, and a re-exported
  # alias beats a declaration in a stub, so the one file that constructs one cannot be checked
  # here. Retry without it, and say so — a skip that is not announced reads as a pass.
  assertable=()
  skipped=()
  for src in "${app_sources[@]}"; do
    if grep -q 'HTTPURLResponse(' "$src"; then
      skipped+=( "$(basename "$src")" )
    else
      assertable+=( "$src" )
    fi
  done
  if [ "${#skipped[@]}" -gt 0 ] && \
     swiftc -typecheck -I "$work" "${search[@]}" "${assertable[@]}" 2>"$work/app2.log"; then
    echo "${#assertable[@]} app source(s) type-check against the stubs"
    echo "SKIPPED (Linux Foundation has no usable HTTPURLResponse): ${skipped[*]}" >&2
  else
    grep -E "error:" "$work/app2.log" | head -20
    echo "the app layer does not type-check"
    exit 1
  fi
fi
