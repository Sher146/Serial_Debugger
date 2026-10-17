#!/bin/bash
# Build a distributable Serial Monitor app: universal (arm64 + x86_64) Release
# bundle plus a .zip and .dmg. Ad-hoc signing is used by default so a package can
# be produced without an Apple Developer account; such builds are NOT notarized
# and macOS Gatekeeper will warn on first launch (see the release notes).
#
# Provide a Developer ID identity to sign, and a notarization keychain profile to
# notarize/staple:
#   DEVELOPMENT_IDENTITY="Developer ID Application: X (TEAMID)" \
#   DEVELOPMENT_TEAM=TEAMID \
#   NOTARY_PROFILE=<profile> \
#   bash Scripts/build_distribution.sh
#
# Credentials must come from the environment/keychain and are never written here.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
project="$repo_root/SerialMonitor.xcodeproj"
scheme="SerialMonitor"
output="${DIST_OUTPUT:-$repo_root/build/dist}"
derived="$output/DerivedData"

identity="${DEVELOPMENT_IDENTITY:--}"
team="${DEVELOPMENT_TEAM:-}"
version="${MARKETING_VERSION:-1.0}"

mkdir -p "$output"

sign_args=(
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
)
if [[ "$identity" == "-" ]]; then
  sign_args+=(CODE_SIGN_IDENTITY=-)
else
  sign_args+=(CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team")
fi

echo "==> Building universal Release (identity: ${identity})"
xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'platform=macOS' \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" \
  "${sign_args[@]}" \
  -derivedDataPath "$derived" \
  build

app="$derived/Build/Products/Release/SerialMonitor.app"
[[ -d "$app" ]] || { echo "未找到构建产物：$app" >&2; exit 1; }

if [[ -n "${NOTARY_PROFILE:-}" && "$identity" != "-" ]]; then
  echo "==> 公证并 staple"
  zip_for_notary="$output/SerialMonitor-notary.zip"
  rm -f "$zip_for_notary"
  ditto -c -k --keepParent "$app" "$zip_for_notary"
  xcrun notarytool submit "$zip_for_notary" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  rm -f "$zip_for_notary"
fi

artifact="SerialMonitor-${version}"
zip="$output/${artifact}.zip"
dmg="$output/${artifact}.dmg"
rm -f "$zip" "$dmg"

echo "==> 打包 .zip 与 .dmg"
ditto -c -k --keepParent "$app" "$zip"
hdiutil create -volname "SerialMonitor" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null

echo "APP=$app"
echo "ZIP=$zip"
echo "DMG=$dmg"
