#!/bin/bash
# Verify a release app bundle: code signature, entitlements, Gatekeeper,
# notarization and that no user data leaked into the package.
#
#   bash Scripts/verify_release.sh build/release/export/SerialMonitor.app
set -euo pipefail

app="${1:-}"
usage() { echo "Usage: bash Scripts/verify_release.sh <SerialMonitor.app>"; }

if [[ -z "$app" || ! -d "$app" ]]; then
  usage >&2
  exit 2
fi

fail=0
note() { echo "==> $1"; }
ok() { echo "    OK: $1"; }
bad() { echo "    FAIL: $1" >&2; fail=1; }

note "Code signature"
if codesign --verify --deep --strict --verbose=2 "$app" 2>/dev/null; then
  ok "codesign --verify"
else
  bad "codesign --verify"
fi

note "Entitlements"
entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"
for key in "com.apple.security.app-sandbox" "com.apple.security.device.serial"; do
  if grep -q "$key" <<<"$entitlements"; then
    ok "$key 已声明"
  else
    bad "$key 缺失"
  fi
done

note "Gatekeeper"
if spctl -a -vvv -t exec "$app" 2>&1 | tee /dev/stderr | grep -q "accepted"; then
  ok "spctl accepted"
else
  bad "spctl 未接受"
fi

note "Notarization staple"
if xcrun stapler validate "$app" 2>/dev/null; then
  ok "stapler validate"
else
  bad "stapler validate"
fi

note "包内无用户数据"
leaks="$(find "$app" \( -name '*.ndjson' -o -name '*.log' -o -name 'com.serialmonitor.app.plist' \) -print 2>/dev/null || true)"
if [[ -n "$leaks" ]]; then
  bad "发现可能的用户数据：$leaks"
else
  ok "未发现日志/偏好文件"
fi

if (( fail )); then
  echo "发布验证失败。" >&2
  exit 1
fi
echo "发布验证通过。"
