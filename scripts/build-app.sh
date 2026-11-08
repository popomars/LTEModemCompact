#!/bin/zsh
set -eu
cd "${0:A:h}/.."
swift build -c release
mkdir -p dist
swift scripts/render-installer-assets.swift dist/installer-artwork
iconutil -c icns dist/installer-artwork/AppIcon.iconset -o dist/installer-artwork/AppIcon.icns
cp .build/release/ModemDiagnostics dist/ModemDiagnostics
app="$PWD/dist/LTEModemCompact.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp dist/installer-artwork/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp .build/release/LTEModemCompact "$app/Contents/MacOS/LTEModemCompact"
cp Resources/Info.plist "$app/Contents/Info.plist"
launcher="$app/Contents/Library/LoginItems/LTEModemCompact USB Launcher.app"
mkdir -p "$launcher/Contents/MacOS" "$app/Contents/Library/LaunchAgents"
cp .build/release/USBLauncher "$launcher/Contents/MacOS/USBLauncher"
cp Resources/USBLauncher-Info.plist "$launcher/Contents/Info.plist"
cp Resources/live.lepus.NativeModem.USBLaunch.plist "$app/Contents/Library/LaunchAgents/"
xcrun strip -S "$launcher/Contents/MacOS/USBLauncher"
codesign --force --sign "${LTE_MODEM_COMPACT_SIGN_IDENTITY:-${NATIVE_MODEM_SIGN_IDENTITY:--}}" --identifier live.lepus.NativeModem.USBLauncher "$launcher"
codesign --verify --strict "$launcher"
# C object debug-map entries can retain build-machine paths in release binaries.
xcrun strip -S "$app/Contents/MacOS/LTEModemCompact"
codesign --force --sign "${LTE_MODEM_COMPACT_SIGN_IDENTITY:-${NATIVE_MODEM_SIGN_IDENTITY:--}}" --identifier live.lepus.NativeModem "$app"
codesign --verify --strict "$app"
print -r -- "$app"
