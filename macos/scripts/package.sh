#!/bin/bash
# Builds a Release "ProTask.app" and packages it as dist/ProTask.dmg (drag-to-Applications layout).
set -euo pipefail
cd "$(dirname "$0")/.."

# The generated project is committed; regenerate it only if XcodeGen is installed.
if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

./scripts/check-icons.sh
echo "Building Release…"
xcodebuild -project Top3.xcodeproj -scheme Top3 -configuration Release -derivedDataPath build -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY=- build -quiet

APP="build/Build/Products/Release/ProTask.app"
[ -d "$APP" ] || { echo "Build output not found at $APP"; exit 1; }
codesign --verify --deep "$APP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f dist/ProTask.dmg dist/Top3.dmg
hdiutil create -volname "ProTask" -srcfolder "$STAGE" -ov -format UDZO dist/ProTask.dmg >/dev/null
echo "Created $(pwd)/dist/ProTask.dmg"
