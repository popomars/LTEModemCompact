#!/bin/zsh
set -eu
cd "${0:A:h}/.."

# These small Python packages are build tools only; never copied into the app/DMG.
python="$PWD/.build/dmg-tools/bin/python"
if [[ ! -x "$python" ]]; then
  python3 -m venv .build/dmg-tools
fi
if ! "$python" -c 'from importlib.metadata import version; assert version("ds-store") == "1.3.3" and version("mac-alias") == "2.2.2"' 2>/dev/null; then
  "$python" -m pip install 'ds-store==1.3.3' 'mac-alias==2.2.2'
fi
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
mount=/Volumes/LTEModemCompact
if [[ -e "$mount" ]]; then
  print -u2 -- "Eject the existing LTEModemCompact installer volume before building."
  exit 1
fi
stage=$(mktemp -d "$PWD/dist/.dmg-stage.XXXXXX")
mounted=0
cleanup() {
  if (( mounted )); then /usr/bin/hdiutil detach "$mount" -quiet || return; fi
  rm -rf "$stage"
}
trap cleanup EXIT
mkdir -p "$stage/root/.background"
/usr/bin/ditto "$app" "$stage/root/LTEModemCompact.app"
/bin/ln -s /Applications "$stage/root/Applications"
/bin/cp Resources/INSTALL.md "$stage/root/安装说明.txt"
/bin/cp dist/installer-artwork/installer-background.tiff "$stage/root/.background/installer.tiff"
/usr/bin/codesign --verify --strict "$stage/root/LTEModemCompact.app"
/usr/bin/hdiutil create -ov -volname LTEModemCompact -fs HFS+ -srcfolder "$stage/root" -format UDRW "$stage/editable.dmg"
/usr/bin/hdiutil attach -nobrowse -noautoopen -readwrite -mountpoint "$mount" "$stage/editable.dmg"
mounted=1
"$python" scripts/configure-dmg-layout.py "$mount"
/usr/bin/hdiutil detach "$mount"
mounted=0
dmg="$PWD/dist/LTEModemCompact-${version}-macOS-arm64.dmg"
/usr/bin/hdiutil convert -ov "$stage/editable.dmg" -format UDZO -o "$dmg"
/usr/bin/hdiutil verify "$dmg"
(cd dist && /usr/bin/shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
print -r -- "$dmg"
