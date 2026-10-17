#!/bin/bash
# Submit an exported app (or zip/pkg/dmg) for notarization and staple it.
#
# Credentials must live in a notarytool keychain profile created separately,
# e.g.:
#   xcrun notarytool store-credentials "serial-monitor" \
#     --apple-id <id> --team-id <team> --password <app-specific-password>
# This script never stores or echoes secrets.
#
#   NOTARY_PROFILE=serial-monitor bash Scripts/notarize.sh build/release/export/SerialMonitor.app
set -euo pipefail

profile="${NOTARY_PROFILE:-}"
target="${1:-}"

usage() {
  echo "Usage: NOTARY_PROFILE=<profile> bash Scripts/notarize.sh <app-path|zip|pkg|dmg>"
}

if [[ -z "$profile" ]]; then
  echo "缺少 NOTARY_PROFILE；公证被阻塞。" >&2
  usage >&2
  exit 2
fi
if [[ -z "$target" || ! -e "$target" ]]; then
  usage >&2
  exit 2
fi

submit_path="$target"
cleanup_zip=""
if [[ -d "$target" && "$target" == *.app ]]; then
  submit_path="${target}.zip"
  echo "==> 打包 $target"
  ditto -c -k --keepParent "$target" "$submit_path"
  cleanup_zip="$submit_path"
fi

echo "==> 提交公证"
xcrun notarytool submit "$submit_path" --keychain-profile "$profile" --wait

if [[ -d "$target" && "$target" == *.app ]]; then
  echo "==> staple"
  xcrun stapler staple "$target"
  xcrun stapler validate "$target"
fi

[[ -n "$cleanup_zip" ]] && rm -f "$cleanup_zip"
echo "公证完成。"
