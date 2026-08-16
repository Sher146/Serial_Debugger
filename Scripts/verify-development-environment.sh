#!/bin/zsh
set -euo pipefail

readonly repository_root="${0:A:h:h}"
readonly project_path="$repository_root/SerialMonitor.xcodeproj"
readonly scheme="SerialMonitor"

fail() {
  print -u2 -- "环境未就绪：$1"
  exit 1
}

developer_directory="$(/usr/bin/xcode-select -p)"
if [[ "$developer_directory" != *.app/Contents/Developer ]]; then
  fail "当前选择的是 $developer_directory。请安装完整 Xcode，并执行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

[[ -d "$project_path" ]] || fail "未找到 $project_path"
/usr/bin/xcodebuild -version
/usr/bin/xcrun --find notarytool >/dev/null || fail "完整 Xcode 中未找到 notarytool"
/usr/bin/xcrun --find simctl >/dev/null || fail "完整 Xcode 中未找到 simctl"

print -- "解析本地 Swift Package…"
/usr/bin/xcodebuild -resolvePackageDependencies -project "$project_path" -scheme "$scheme"

print -- "验证 Debug 无签名构建…"
/usr/bin/xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

identity_count="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk '/valid identities found/ { print $1 }')"
if [[ "${identity_count:-0}" == "0" ]]; then
  print -u2 -- "提示：未配置代码签名身份。无签名构建已验证；P0 沙盒签名测试与 P4 发布仍不可执行。"
else
  print -- "检测到 $identity_count 个代码签名身份。"
fi

print -- "开发环境检查完成。硬件/PTY/签名测试请按 Docs/DevelopmentEnvironment.md 执行。"
