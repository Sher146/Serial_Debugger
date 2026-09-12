#!/bin/zsh
# Local regression runner. It deliberately does not retry failures or access
# physical serial devices; PTYs and deterministic UI scenarios provide coverage.
set -u
set -o pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
mode=full

usage() {
  print "Usage: zsh Scripts/run-automated-tests.zsh [--quick | --stress]"
  print "  --quick   Run SerialCore and App unit/PTY tests, skipping XCUITest."
  print "  --stress  Run the default suite plus a 30-minute 115200-bps PTY stress test."
}

while (( $# > 0 )); do
  case "$1" in
    --quick) mode=quick ;;
    --stress) mode=stress ;;
    --hardware)
      print -u2 "真实设备测试未纳入本地自动化体系；请使用 PTY 压测。"
      exit 64
      ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "未知参数：$1"; usage; exit 64 ;;
  esac
  shift
done

timestamp=$(date +%Y%m%d-%H%M%S)
artifact_dir="$repo_root/TestArtifacts/$timestamp"
derived_data="$artifact_dir/DerivedData"
mkdir -p "$artifact_dir"

run_logged() {
  local name=$1
  shift
  print "\n==> $name"
  "$@" 2>&1 | tee "$artifact_dir/$name.log"
  local command_status=${pipestatus[1]}
  if (( command_status != 0 )); then
    print -u2 "失败：$name（日志：$artifact_dir/$name.log）"
  fi
  return $command_status
}

write_reports() {
  local bundle=$1
  local prefix=$2
  /usr/bin/xcrun xcresulttool get test-results summary --path "$bundle" \
    > "$artifact_dir/$prefix-test-summary.json" 2> "$artifact_dir/$prefix-result-reader.log" || true
  /usr/bin/xcrun xccov view --report "$bundle" \
    > "$artifact_dir/$prefix-coverage.txt" 2>> "$artifact_dir/$prefix-result-reader.log" || true
}

cd "$repo_root" || exit 1
if ! /usr/bin/xcodebuild -version > "$artifact_dir/xcode-version.txt" 2>&1; then
  print -u2 "需要完整 Xcode；详情见 $artifact_dir/xcode-version.txt"
  exit 1
fi

if ! run_logged serialcore-swift-test /usr/bin/swift test --package-path "$repo_root/Packages/SerialCore"; then
  exit 1
fi

unit_bundle="$artifact_dir/AppUnit.xcresult"
unit_command=(
  /usr/bin/xcodebuild
  -project "$repo_root/SerialMonitor.xcodeproj"
  -scheme SerialMonitor
  -destination 'platform=macOS,arch=arm64'
  ONLY_ACTIVE_ARCH=YES
  CODE_SIGNING_ALLOWED=NO
  -derivedDataPath "$derived_data"
  -resultBundlePath "$unit_bundle"
  -enableCodeCoverage YES
  -parallel-testing-enabled NO
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 45
  -only-testing:SerialMonitorTests
  -skip-testing:SerialMonitorTests/PTYStressTests
  test
)

if ! run_logged app-unit-pty "${unit_command[@]}"; then
  write_reports "$unit_bundle" app-unit-pty
  exit 1
fi
write_reports "$unit_bundle" app-unit-pty

if [[ "$mode" != quick ]]; then
  ui_bundle="$artifact_dir/AppUI.xcresult"
  ui_command=(
    /usr/bin/xcodebuild
    -project "$repo_root/SerialMonitor.xcodeproj"
    -scheme SerialMonitor
    -destination 'platform=macOS,arch=arm64'
    ONLY_ACTIVE_ARCH=YES
    # XCUITest needs an executable Runner. Ad-hoc signing does not require a
    # developer account and is kept separate so PTY tests remain unsandboxed.
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    -derivedDataPath "$derived_data"
    -resultBundlePath "$ui_bundle"
    -enableCodeCoverage YES
    -parallel-testing-enabled NO
    -test-timeouts-enabled YES
    -default-test-execution-time-allowance 45
    -only-testing:SerialMonitorUITests
    test
  )
  if ! run_logged app-ui "${ui_command[@]}"; then
    write_reports "$ui_bundle" app-ui
    exit 1
  fi
  write_reports "$ui_bundle" app-ui
fi

if [[ "$mode" == stress ]]; then
  stress_bundle="$artifact_dir/PTYStress.xcresult"
  stress_command=(
    /usr/bin/xcodebuild
    -project "$repo_root/SerialMonitor.xcodeproj"
    -scheme SerialMonitor
    -destination 'platform=macOS,arch=arm64'
    ONLY_ACTIVE_ARCH=YES
    CODE_SIGNING_ALLOWED=NO
    'OTHER_SWIFT_FLAGS=$(inherited) -DPTY_STRESS'
    -derivedDataPath "$derived_data"
    -resultBundlePath "$stress_bundle"
    -enableCodeCoverage YES
    -parallel-testing-enabled NO
    -test-timeouts-enabled YES
    -default-test-execution-time-allowance 1900
    -only-testing:SerialMonitorTests/PTYStressTests
    test
  )
  if ! run_logged pty-stress "${stress_command[@]}"; then
    write_reports "$stress_bundle" pty-stress
    exit 1
  fi
  write_reports "$stress_bundle" pty-stress
fi

print "\n自动化测试通过。报告与原始结果：$artifact_dir"
