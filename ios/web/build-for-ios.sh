#!/usr/bin/env bash
# Builds the DWG viewer bundle and copies it where the app expects it.
#
# The app looks for a `dwgviewer` folder in its bundle; this puts the built viewer there,
# so a release build does not depend on a web build step at Xcode time.
set -euo pipefail
cd "$(dirname "$0")"

npm ci --no-audit --no-fund
npm run build

DEST="../CADViewer/Sources/CADViewer/Resources/dwgviewer"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R dist/. "$DEST"

echo "viewer copied to $DEST ($(du -sh "$DEST" | cut -f1))"
