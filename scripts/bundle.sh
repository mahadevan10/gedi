#!/usr/bin/env bash
# Builds build/Gedi.app (release) and code-signs it.
# Ad-hoc signing (the default) changes the signature on every build, so macOS asks for
# microphone/automation permission again after each rebuild. To avoid that, create a
# "Code Signing" certificate in Keychain Access and run: GEDI_SIGN_IDENTITY="Gedi Dev" scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Gedi
BIN="$(swift build -c release --show-bin-path)/Gedi"

APP=build/Gedi.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Gedi"
cp App/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${GEDI_SIGN_IDENTITY:--}" "$APP"
echo "built $APP"
