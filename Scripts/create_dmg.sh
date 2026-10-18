#!/bin/bash
# Uses native Finder automation to persist the install window's icon layout.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: bash Scripts/create_dmg.sh <SerialMonitor.app> <output.dmg>" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$1"
[[ -d "$app" ]] || { echo "应用不存在：$app" >&2; exit 1; }
mkdir -p "$(dirname "$2")"
output_dir="$(cd "$(dirname "$2")" && pwd)"
dmg="$output_dir/$(basename "$2")"
work="$(mktemp -d "$output_dir/.dmg-work.XXXXXX")"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then
    hdiutil detach "$work/mount" >/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/staging/.background" "$work/mount"
ditto "$app" "$work/staging/SerialMonitor.app"
ln -s /Applications "$work/staging/Applications"
swift "$script_dir/render_dmg_background.swift" "$work/staging/.background/installer.png"
hdiutil create -volname "SerialMonitor" -srcfolder "$work/staging" \
  -fs HFS+ -format UDRW "$work/install.dmg" >/dev/null
hdiutil attach "$work/install.dmg" -mountpoint "$work/mount" -nobrowse -noautoopen >/dev/null
mounted=1

# Failure is intentional if Finder automation is unavailable: don't silently
# publish a plain file-browser window in place of the designed installer.
osascript - "$work/mount" <<'APPLESCRIPT'
on run argv
    set installFolder to (POSIX file (item 1 of argv)) as alias
    tell application "Finder"
        open installFolder
        set installWindow to container window of installFolder
        set current view of installWindow to icon view
        set toolbar visible of installWindow to false
        set statusbar visible of installWindow to false
        set bounds of installWindow to {160, 160, 840, 640}
        set viewOptions to icon view options of installWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:installer.png" of installFolder
        set position of item "SerialMonitor.app" of installFolder to {170, 220}
        set position of item "Applications" of installFolder to {510, 220}
        update installFolder without registering applications
        delay 2
        close installWindow
        delay 1
    end tell
end run
APPLESCRIPT

[[ -f "$work/mount/.DS_Store" ]] || { echo "Finder 未保存安装窗口布局" >&2; exit 1; }
sync
hdiutil detach "$work/mount" >/dev/null
mounted=0
hdiutil convert "$work/install.dmg" -format UDZO -ov -o "$dmg" >/dev/null
echo "DMG=$dmg"
