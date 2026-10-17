#!/usr/bin/env python3
"""CH340 / CP210x / FTDI / CDC-ACM hardware smoke test for Serial Monitor.

Runs on the real device path (no PTY). Requires a TX-RX loopback jumper for the
loopback check. It validates the parts of the P0/P4 matrix that can be automated
once hardware is attached:

  * open + configure at each requested baud rate
  * loopback write/read over the jumper
  * exclusive-open (占用) behaviour
  * optional physical hot-unplug polling

Results are printed and can also be written as JSON to feed
Docs/RealDeviceTestMatrix.md. Physical unplug and sandbox permission still
require human/signed-app confirmation.
"""

from __future__ import annotations

import argparse
import errno
import json
import os
import stat
import sys
import termios
import time

try:
    import termios as _termios

    HAS_TERMIOS = True
except ImportError:  # pragma: no cover - macOS always has termios
    HAS_TERMIOS = False


BAUD_CONSTANTS = {
    9600: "B9600",
    19200: "B19200",
    38400: "B38400",
    57600: "B57600",
    115200: "B115200",
    230400: "B230400",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="device path, e.g. /dev/cu.usbserial-XXXX")
    parser.add_argument("--bauds", default="9600,115200", help="comma-separated baud rates to verify")
    parser.add_argument("--pattern", default="SerialMonitorLoopback", help="loopback payload")
    parser.add_argument("--timeout", type=float, default=1.5, help="read timeout in seconds")
    parser.add_argument("--skip-loopback", action="store_true", help="skip the TX-RX jumper check")
    parser.add_argument("--wait-unplug", type=float, default=0.0, help="seconds to poll for physical unplug")
    parser.add_argument("--output", default="", help="optional JSON report path")
    return parser.parse_args()


def resolve_baud(speed: int) -> int:
    name = BAUD_CONSTANTS.get(speed)
    if name is None or not hasattr(termios, name):
        raise ValueError(f"unsupported standard baud {speed}; use a PTY/standard rate")
    return getattr(termios, name)


def configure(fd: int, speed: int) -> None:
    attrs = termios.tcgetattr(fd)
    speed_const = resolve_baud(speed)
    attrs[4] = speed_const  # ispeed
    attrs[5] = speed_const  # ospeed
    attrs[0] = 0  # iflag: raw
    attrs[1] = 0  # oflag
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0  # lflag: raw
    attrs[6] = attrs[6][:]
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)


def open_port(path: str) -> int:
    return os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)


def check_open(path: str, speed: int) -> dict:
    result = {"baud": speed, "opened": False, "error": None}
    try:
        fd = open_port(path)
    except OSError as error:
        result["error"] = f"open failed: {error.strerror or error}"
        return result
    try:
        configure(fd, speed)
        result["opened"] = True
    except OSError as error:
        result["error"] = f"configure failed: {error.strerror or error}"
    except ValueError as error:
        result["error"] = str(error)
    finally:
        os.close(fd)
    return result


def check_loopback(path: str, speed: int, payload: bytes, timeout: float) -> dict:
    result = {"baud": speed, "sent": len(payload), "received": 0, "matched": False, "error": None}
    try:
        fd = open_port(path)
    except OSError as error:
        result["error"] = f"open failed: {error.strerror or error}"
        return result
    try:
        configure(fd, speed)
        os.set_blocking(fd, True)
        if hasattr(termios, "TCSBRK"):
            termios.tcflush(fd, termios.TCIOFLUSH)
        os.write(fd, payload)
        deadline = time.monotonic() + timeout
        received = bytearray()
        while time.monotonic() < deadline and len(received) < len(payload):
            try:
                chunk = os.read(fd, len(payload) - len(received))
            except BlockingIOError:
                chunk = b""
            if chunk:
                received.extend(chunk)
            else:
                time.sleep(0.01)
        result["received"] = len(received)
        result["matched"] = payload in bytes(received) or bytes(received) == payload
    except OSError as error:
        result["error"] = f"loopback failed: {error.strerror or error}"
    finally:
        os.close(fd)
    return result


def check_exclusive(path: str) -> dict:
    result = {"shared_open_allowed": None, "second_error": None}
    first = None
    second = None
    try:
        first = open_port(path)
        try:
            second = open_port(path)
            result["shared_open_allowed"] = True
        except OSError as error:
            result["shared_open_allowed"] = False
            result["second_error"] = errno.errorcode.get(error.errno, str(error.errno))
    except OSError as error:
        result["second_error"] = f"first open failed: {error.strerror or error}"
    finally:
        for fd in (second, first):
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
    return result


def wait_for_unplug(path: str, seconds: float) -> dict:
    print(f"请在 {seconds:g}s 内物理拔出设备（{path}）…", flush=True)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if not os.path.exists(path):
            return {"unplugged": True}
        time.sleep(0.25)
    return {"unplugged": False}


def main() -> int:
    args = parse_args()
    if not HAS_TERMIOS:
        print("termios 不可用，仅支持 macOS", file=sys.stderr)
        return 2

    if not os.path.exists(args.port):
        print(f"端口不存在：{args.port}", file=sys.stderr)
        print("可用端口：", file=sys.stderr)
        for name in sorted(os.listdir("/dev")):
            if name.startswith("cu."):
                print(f"  /dev/{name}", file=sys.stderr)
        return 2

    try:
        mode = os.stat(args.port).st_mode
        if not stat.S_ISCHR(mode):
            print(f"{args.port} 不是字符设备", file=sys.stderr)
            return 2
    except OSError:
        pass

    bauds = [int(value) for value in args.bauds.split(",") if value.strip()]
    payload = args.pattern.encode("utf-8")
    failures: list[str] = []

    report: dict = {"port": args.port, "opens": [], "loopbacks": [], "exclusive": None, "unplug": None}

    print(f"== 打开与配置 {args.port}")
    for speed in bauds:
        row = check_open(args.port, speed)
        report["opens"].append(row)
        status = "OK" if row["opened"] else f"FAIL ({row['error']})"
        print(f"   {speed} bps: {status}")
        if not row["opened"]:
            failures.append(f"open {speed}")

    if not args.skip_loopback:
        print("== 回环（需 TX-RX 跳线）")
        for speed in bauds:
            row = check_loopback(args.port, speed, payload, args.timeout)
            report["loopbacks"].append(row)
            status = "OK" if row["matched"] else f"FAIL (收到 {row['received']}/{row['sent']} 字节)"
            print(f"   {speed} bps: {status}")
            if not row["matched"]:
                failures.append(f"loopback {speed}")

    print("== 占用（二次打开）")
    exclusive = check_exclusive(args.port)
    report["exclusive"] = exclusive
    if exclusive["shared_open_allowed"] is True:
        print("   警告：驱动允许共享打开，占用错误无法在此设备上验证")
    elif exclusive["shared_open_allowed"] is False:
        print(f"   OK：第二次打开被拒绝（{exclusive['second_error']}）")
    else:
        print(f"   FAIL：{exclusive['second_error']}")
        failures.append("exclusive")

    if args.wait_unplug > 0:
        print("== 热拔出")
        unplug = wait_for_unplug(args.port, args.wait_unplug)
        report["unplug"] = unplug
        print(f"   拔出检测：{'OK' if unplug['unplugged'] else 'FAIL'}")
        if not unplug["unplugged"]:
            failures.append("unplug")

    report["failures"] = failures
    text = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")

    if failures:
        print(f"\n硬件冒烟失败：{', '.join(failures)}", file=sys.stderr)
        return 1
    print("\n硬件冒烟通过（沙盒与物理拔出仍需人工确认）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
