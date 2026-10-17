#!/bin/bash
# Real-device smoke test wrapper for Serial Monitor.
#
# Requires a USB-UART adapter (CH340/CP210x/FTDI/CDC-ACM) and, for the loopback
# check, a TX-RX jumper. This never runs during automated regression.
#
#   bash Scripts/hardware-smoke.sh                       # list /dev/cu.* and exit
#   bash Scripts/hardware-smoke.sh --port /dev/cu.usbserial-XXXX
#   bash Scripts/hardware-smoke.sh --port /dev/cu.xxx --wait-unplug 20
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
  echo "Usage: bash Scripts/hardware-smoke.sh --port /dev/cu.<device> [options]"
  echo "Options are forwarded to hardware_smoke.py:"
  echo "  --bauds 9600,115200   --pattern <text>   --timeout <seconds>"
  echo "  --skip-loopback       --wait-unplug <seconds>   --output <json>"
  echo
  echo "可用的 /dev/cu.* 设备："
  ls /dev/cu.* 2>/dev/null || echo "  （未发现；请插入 USB-UART 适配器）"
  exit 0
fi

exec /usr/bin/python3 "$script_dir/hardware_smoke.py" "$@"
