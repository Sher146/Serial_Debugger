#!/usr/bin/env python3
"""Standalone PTY throughput stress harness for Serial Monitor.

This does not touch USB-UART hardware. It pairs a pseudo-terminal with a writer
and a reader so the serial data path can be exercised at a sustained rate while
collecting memory, CPU, throughput and stall metrics. P4 uses it as a companion
to the in-process `PTYStressTests` XCTest.

Example:
    python3 Scripts/pty_stress.py --baud 115200 --duration-min 30
"""

from __future__ import annotations

import argparse
import json
import os
import pty
import resource
import sys
import termios
import threading
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baud", type=int, default=115_200, help="nominal line rate")
    parser.add_argument("--duration-min", type=float, default=30.0, help="run length in minutes")
    parser.add_argument("--chunk-bytes", type=int, default=1_024, help="bytes written per tick")
    parser.add_argument("--stall-threshold", type=float, default=1.0, help="seconds without RX to count as a stall")
    parser.add_argument("--output", default="", help="optional path for the JSON metrics report")
    return parser.parse_args()


def bytes_per_second(baud: int) -> float:
    # 8N1 framing consumes ~10 bits per byte.
    return max(1.0, baud / 10.0)


def rss_bytes() -> int:
    usage = resource.getrusage(resource.RUSAGE_SELF)
    # ru_maxrss is reported in bytes on macOS.
    return int(usage.ru_maxrss)


def cpu_seconds() -> float:
    usage = resource.getrusage(resource.RUSAGE_SELF)
    return usage.ru_utime + usage.ru_stime


def main() -> int:
    args = parse_args()
    duration = max(0.1, args.duration_min * 60.0)
    rate = bytes_per_second(args.baud)
    tick = args.chunk_bytes / rate
    payload = bytes([0x55]) * args.chunk_bytes

    master, slave = pty.openpty()
    os.set_blocking(master, False)
    os.set_blocking(slave, False)
    try:
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~(termios.ICANON | termios.ECHO)
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
    except termios.error:  # raw mode is best-effort for metrics
        pass

    stop = threading.Event()
    sent = 0
    write_errors = 0

    def writer() -> None:
        nonlocal sent, write_errors
        deadline = time.monotonic() + duration
        next_tick = time.monotonic()
        while not stop.is_set() and time.monotonic() < deadline:
            try:
                written = os.write(slave, payload)
                sent += written
            except BlockingIOError:
                pass
            except OSError:
                write_errors += 1
                if write_errors > 100:
                    break
            next_tick += tick
            sleep_for = next_tick - time.monotonic()
            if sleep_for > 0:
                time.sleep(sleep_for)

    thread = threading.Thread(target=writer, name="pty-writer", daemon=True)
    start = time.monotonic()
    cpu_start = cpu_seconds()
    received = 0
    last_rx = start
    max_gap = 0.0
    stalls = 0
    thread.start()

    while time.monotonic() - start < duration and not stop.is_set():
        got = 0
        try:
            data = os.read(master, 65_536)
            got = len(data)
        except BlockingIOError:
            got = 0
        except OSError:
            break
        now = time.monotonic()
        if got:
            received += got
            gap = now - last_rx
            max_gap = max(max_gap, gap)
            if gap > args.stall_threshold:
                stalls += 1
            last_rx = now
        else:
            time.sleep(0.001)

    stop.set()
    thread.join(timeout=5)
    elapsed = time.monotonic() - start
    cpu_used = cpu_seconds() - cpu_start

    os.close(master)
    os.close(slave)

    report = {
        "baud": args.baud,
        "duration_seconds": round(elapsed, 3),
        "chunk_bytes": args.chunk_bytes,
        "sent_bytes": sent,
        "received_bytes": received,
        "throughput_bytes_per_second": round(received / elapsed, 1) if elapsed else 0,
        "max_gap_seconds": round(max_gap, 4),
        "stalls": stalls,
        "write_errors": write_errors,
        "peak_rss_bytes": rss_bytes(),
        "cpu_seconds": round(cpu_used, 3),
    }

    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")

    if sent == 0:
        print("pty_stress: no bytes written", file=sys.stderr)
        return 1
    if received < sent * 0.99:
        print(f"pty_stress: received {received} of {sent} bytes", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
