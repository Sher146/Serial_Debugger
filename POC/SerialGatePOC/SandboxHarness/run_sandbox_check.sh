#!/bin/bash
# D6 沙盒 + ad-hoc 签名验证脚本（01 文档步骤 7）。
#
# 用法：SandboxHarness/run_sandbox_check.sh <串口路径> [baud]
#   例：SandboxHarness/run_sandbox_check.sh /dev/cu.usbserial-XXXX 115200
#
# 流程：
#   1. swift build -c release 构建 poc-cli；
#   2. 复制两份：poc-cli-sandboxed-serial（app-sandbox + device.serial，ad-hoc 签名）
#      与 poc-cli-sandboxed-noserial（仅 app-sandbox，ad-hoc 签名，对照组）；
#   3. 带 serial entitlement 的构建执行 list / open：期望成功；
#   4. 对照构建执行 open：期望失败且错误分类为 permissionDenied。
#
# 产物（签名后的二进制）放在 .build/sandbox-harness/ 下，不入 git。
set -u
cd "$(dirname "$0")/.."

PORT_PATH="${1:-}"
BAUD="${2:-115200}"
if [ -z "$PORT_PATH" ]; then
    echo "usage: $0 <serial-port-path> [baud]" >&2
    exit 2
fi

OUT_DIR=".build/sandbox-harness"
mkdir -p "$OUT_DIR"

echo "== 1. release 构建（内嵌 Info.plist：secinitd 注册沙盒需要 CFBundleIdentifier，"
echo "   裸 CLI 无二者的会在 _libsecinit_appsandbox 里 SIGTRAP，实测见 POC 报告）=="
swift build -c release --product poc-cli \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
    -Xlinker SandboxHarness/Info.plist || exit 1

WITH_SERIAL="$OUT_DIR/poc-cli-sandboxed-serial"
NO_SERIAL="$OUT_DIR/poc-cli-sandboxed-noserial"
cp ".build/release/poc-cli" "$WITH_SERIAL"
cp ".build/release/poc-cli" "$NO_SERIAL"

echo "== 2. ad-hoc 签名（含 entitlements）=="
codesign -s - --force --entitlements SandboxHarness/entitlements-serial.plist "$WITH_SERIAL" || exit 1
codesign -s - --force --entitlements SandboxHarness/entitlements-noserial.plist "$NO_SERIAL" || exit 1
echo "-- 验证签名内嵌 entitlements --"
codesign -d --entitlements :- "$WITH_SERIAL" | grep -A1 'device.serial' || { echo "serial entitlement 未写入"; exit 1; }
codesign -d --entitlements :- "$NO_SERIAL" | grep 'device.serial' && { echo "对照包不应含 serial entitlement"; exit 1; }

echo "== 3. 带 serial entitlement：list / open（期望成功）=="
"$WITH_SERIAL" list
echo "list exit=$?"
"$WITH_SERIAL" open "$PORT_PATH" "$BAUD" 1
OPEN_OK=$?
echo "open exit=$OPEN_OK"

echo "== 4. 对照（无 serial entitlement）：open（期望失败且 category=permissionDenied）=="
CONTROL_OUTPUT=$("$NO_SERIAL" open "$PORT_PATH" "$BAUD" 1 2>&1)
CONTROL_EXIT=$?
echo "$CONTROL_OUTPUT"
echo "control open exit=$CONTROL_EXIT"

echo "== 判定 =="
if [ "$OPEN_OK" -eq 0 ] && [ "$CONTROL_EXIT" -ne 0 ] && echo "$CONTROL_OUTPUT" | grep -q 'category=permissionDenied'; then
    echo "PASS: 带 entitlement 打开成功；对照组失败且映射为 permissionDenied"
    exit 0
else
    echo "FAIL: 结果不符合预期（见上方输出）"
    exit 1
fi
