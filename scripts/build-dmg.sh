#!/bin/zsh
set -eu
cd "${0:A:h}/.."

zsh scripts/build-app.sh
app="$PWD/dist/LTEModemCompact.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
archs=$(/usr/bin/lipo -archs "$app/Contents/MacOS/LTEModemCompact")
if [[ "$archs" != "arm64" ]]; then
  print -u2 -- "This package is for arm64; build it on an Apple Silicon Mac."
  exit 1
fi
if [[ "$version" != [0-9]* || "$version" == *[^0-9.]* ]]; then
  print -u2 -- "Invalid bundle version."
  exit 1
fi
stage=$(mktemp -d "$PWD/dist/.dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
/usr/bin/ditto "$app" "$stage/LTEModemCompact.app"
/bin/ln -s /Applications "$stage/Applications"
/bin/cp Resources/INSTALL.md "$stage/安装说明.txt"
/usr/bin/codesign --verify --strict "$stage/LTEModemCompact.app"
dmg="$PWD/dist/LTEModemCompact-${version}-macOS-arm64.dmg"
/usr/bin/hdiutil create -ov -volname LTEModemCompact -fs HFS+ -srcfolder "$stage" -format UDZO "$dmg"
/usr/bin/hdiutil verify "$dmg"
(cd dist && /usr/bin/shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
print -r -- "$dmg"
