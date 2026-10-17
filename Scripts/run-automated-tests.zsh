#!/bin/zsh
# Serial Monitor local regression pipeline.
#
# It never touches physical serial hardware: PTYs and the deterministic UI
# scenario client stand in for devices. Reports, coverage and raw `.xcresult`
# bundles are written to the gitignored `TestArtifacts/<timestamp>/` directory.
#
#   zsh Scripts/run-automated-tests.zsh                 # SerialCore + unit/PTY + UI
#   zsh Scripts/run-automated-tests.zsh --quick         # skip UI
#   zsh Scripts/run-automated-tests.zsh --ui-only       # UI only
#   zsh Scripts/run-automated-tests.zsh --all           # explicit full non-stress run
#   zsh Scripts/run-automated-tests.zsh --stress        # full run + Py PTY 30-minute stress
#   zsh Scripts/run-automated-tests.zsh --xctest-stress # full run + XCTest PTYStressTests
#   zsh Scripts/run-automated-tests.zsh --release       # unit tests against Release config
set -u
set -o pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}

mode=standard          # standard | quick | ui-only
run_py_stress=0
run_xctest_stress=0
stress_minutes=30
configuration=Debug

usage() {
  print "Usage: zsh Scripts/run-automated-tests.zsh [options]"
  print "  --quick              SerialCore + App unit/PTY only (skip UI)."
  print "  --ui-only            Only run XCUITest."
  print "  --all, --ci          Full non-stress run (default)."
  print "  --stress             Full run plus Scripts/pty_stress.py."
  print "  --stress-minutes N   Py PTY stress duration (default 30)."
  print "  --xctest-stress      Additionally run PTYStressTests (30 minutes)."
  print "  --release            Build/test the App with Release configuration."
  print "  -h, --help           Show this help."
}

while (( $# > 0 )); do
  case "$1" in
    --quick) mode=quick ;;
    --ui-only) mode=ui-only ;;
    --all|--ci) mode=standard ;;
    --stress) run_py_stress=1 ;;
    --stress-minutes) shift; stress_minutes=${1:-30} ;;
    --xctest-stress) run_xctest_stress=1 ;;
    --release) configuration=Release ;;
    --hardware)
      print -u2 "真实设备测试未纳入本地自动化体系；请使用 PTY 压测。"
      exit 64 ;;
    -h|--help) usage; exit 0 ;;
    *) print -u2 "未知参数：$1"; usage; exit 64 ;;
  esac
  shift
done

timestamp=$(date +%Y%m%d-%H%M%S)
artifact_dir="$repo_root/TestArtifacts/$timestamp"
# Shared across runs so a full DerivedData is not duplicated (and accumulated)
# inside every timestamped artifact directory.
derived_data="$repo_root/TestArtifacts/DerivedData"
mkdir -p "$artifact_dir"

typeset -a stage_names stage_status stage_logs stage_seconds
typeset -a failed_stages

record_stage() {
  # name, status, log, seconds
  stage_names+=("$1"); stage_status+=("$2"); stage_logs+=("$3"); stage_seconds+=("$4")
  if [[ "$2" != "passed" && "$2" != "skipped" ]]; then
    failed_stages+=("$1")
  fi
}

run_logged() {
  local name=$1
  shift
  local log="$artifact_dir/$name.log"
  print "\n==> $name ($configuration)"
  local start=$SECONDS
  "$@" 2>&1 | tee "$log"
  local command_status=${pipestatus[1]}
  local elapsed=$(( SECONDS - start ))
  if (( command_status == 0 )); then
    record_stage "$name" "passed" "$log" "$elapsed"
  else
    print -u2 "失败：$name（日志：$log）"
    record_stage "$name" "failed" "$log" "$elapsed"
  fi
  return $command_status
}

write_coverage() {
  local bundle=$1 prefix=$2
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
/usr/bin/xcode-select -p > "$artifact_dir/xcode-select.txt" 2>&1 || true

run_serialcore() {
  /usr/bin/swift test --package-path "$repo_root/Packages/SerialCore"
}

run_app_unit() {
  local bundle="$artifact_dir/AppUnit.xcresult"
  /usr/bin/xcodebuild \
    -project "$repo_root/SerialMonitor.xcodeproj" \
    -scheme SerialMonitor \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$bundle" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 45 \
    -only-testing:SerialMonitorTests \
    -skip-testing:SerialMonitorTests/PTYStressTests \
    test
  local cmd_status=$?
  write_coverage "$bundle" app-unit
  return $cmd_status
}

run_app_ui() {
  local bundle="$artifact_dir/AppUI.xcresult"
  /usr/bin/xcodebuild \
    -project "$repo_root/SerialMonitor.xcodeproj" \
    -scheme SerialMonitor \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$bundle" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 45 \
    -only-testing:SerialMonitorUITests \
    test
  local cmd_status=$?
  write_coverage "$bundle" app-ui
  return $cmd_status
}

run_pty_stress() {
  /usr/bin/python3 "$repo_root/Scripts/pty_stress.py" \
    --baud 115200 \
    --duration-min "$stress_minutes" \
    --output "$artifact_dir/pty-stress-report.json"
}

run_xctest_stress() {
  local bundle="$artifact_dir/PTYStress.xcresult"
  /usr/bin/xcodebuild \
    -project "$repo_root/SerialMonitor.xcodeproj" \
    -scheme SerialMonitor \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    'OTHER_SWIFT_FLAGS=$(inherited) -DPTY_STRESS' \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$bundle" \
    -enableCodeCoverage YES \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 1900 \
    -only-testing:SerialMonitorTests/PTYStressTests \
    test
  local cmd_status=$?
  write_coverage "$bundle" pty-stress
  return $cmd_status
}

overall_start=$SECONDS

if [[ "$mode" != "ui-only" ]]; then
  run_logged serialcore-swift-test run_serialcore || true
  run_logged app-unit-pty run_app_unit || true
fi

if [[ "$mode" == "standard" || "$mode" == "ui-only" ]]; then
  run_logged app-ui run_app_ui || true
fi

if (( run_py_stress )); then
  run_logged pty-stress-python run_pty_stress || true
fi

if (( run_xctest_stress )); then
  run_logged pty-stress-xctest run_xctest_stress || true
fi

overall_seconds=$(( SECONDS - overall_start ))

# --- Reports -----------------------------------------------------------------
summary_json="$artifact_dir/summary.json"
summary_md="$artifact_dir/summary.md"
{
  print "{"
  print "  \"timestamp\": \"$timestamp\","
  print "  \"mode\": \"$mode\","
  print "  \"configuration\": \"$configuration\","
  print "  \"duration_seconds\": $overall_seconds,"
  print "  \"stages\": ["
  local_i=1
  while (( local_i <= ${#stage_names} )); do
    comma=","
    (( local_i == ${#stage_names} )) && comma=""
    print "    {\"name\": \"${stage_names[$local_i]}\", \"status\": \"${stage_status[$local_i]}\", \"seconds\": ${stage_seconds[$local_i]}, \"log\": \"${stage_logs[$local_i]}\"}$comma"
    (( local_i++ ))
  done
  print "  ]"
  print "}"
} > "$summary_json"

{
  print "# Serial Monitor 自动化报告 ($timestamp)"
  print ""
  print -- "- 模式：\`$mode\`"
  print -- "- 配置：\`$configuration\`"
  print -- "- 总耗时：${overall_seconds}s"
  print ""
  print "| 阶段 | 状态 | 秒 |"
  print "|---|---|---|"
  local_i=1
  while (( local_i <= ${#stage_names} )); do
    print "| ${stage_names[$local_i]} | ${stage_status[$local_i]} | ${stage_seconds[$local_i]} |"
    (( local_i++ ))
  done
} > "$summary_md"

print "\n自动化报告：$summary_md"
print "JSON：$summary_json"

if (( ${#failed_stages} > 0 )); then
  print -u2 "\n失败阶段：${(j:, :)failed_stages}"
  exit 1
fi

print "\n自动化测试通过。产物目录：$artifact_dir"
