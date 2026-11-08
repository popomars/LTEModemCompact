#!/bin/zsh
set -eu
cd "${0:A:h}/.."
swift build -c release
mkdir -p dist
cp .build/release/ModemDiagnostics dist/ModemDiagnostics
app="$PWD/dist/LTEModemCompact.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/LTEModemCompact "$app/Contents/MacOS/LTEModemCompact"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign "${LTE_MODEM_COMPACT_SIGN_IDENTITY:-${NATIVE_MODEM_SIGN_IDENTITY:--}}" --identifier live.lepus.NativeModem "$app"
codesign --verify --strict "$app"
print -r -- "$app"
