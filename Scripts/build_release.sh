#!/bin/bash
# Archive and export a Developer ID build for Serial Monitor.
#
# Credentials are never stored here: the team ID comes from $DEVELOPMENT_TEAM
# and signing is handled by Xcode's keychain. Use --smoke to validate that the
# Release configuration compiles without any signing identity.
#
#   DEVELOPMENT_TEAM=ABCDE12345 bash Scripts/build_release.sh
#   bash Scripts/build_release.sh --smoke
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
scheme="SerialMonitor"
project="$repo_root/SerialMonitor.xcodeproj"
output="${RELEASE_OUTPUT:-$repo_root/build/release}"

usage() {
  echo "Usage: DEVELOPMENT_TEAM=<id> bash Scripts/build_release.sh [output-dir]"
  echo "       bash Scripts/build_release.sh --smoke [output-dir]"
}

smoke=0
if [[ "${1:-}" == "--smoke" ]]; then
  smoke=1
  shift
fi
[[ $# -gt 0 ]] && output="$1"

mkdir -p "$output"

if (( smoke )); then
  echo "==> Release 无签名构建冒烟（不替代签名/公证）"
  xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$output/DerivedData" \
    build
  echo "Release 构建通过。签名/归档/公证仍被阻塞。"
  exit 0
fi

team="${DEVELOPMENT_TEAM:-}"
if [[ -z "$team" ]]; then
  echo "缺少 DEVELOPMENT_TEAM；Developer ID 归档被阻塞。" >&2
  usage >&2
  exit 2
fi

archive="$output/SerialMonitor.xcarchive"
options="$output/ExportOptions.plist"
sed "s/TEAM_ID_PLACEHOLDER/$team/" "$script_dir/ExportOptions.plist" > "$options"

echo "==> Archive"
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$team" \
  archive

echo "==> Export"
xcodebuild \
  -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$options" \
  -exportPath "$output/export"

echo "导出完成：$output/export"
