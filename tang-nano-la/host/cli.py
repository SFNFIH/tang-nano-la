#!/usr/bin/env python3
"""CLI for Tang Nano 9K logic analyzer host."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Allow running without install
sys.path.insert(0, str(Path(__file__).resolve().parent))

from logic_analyzer import LogicAnalyzer
from logic_analyzer.waveform import ascii_wave, save_vcd


def main() -> int:
    ap = argparse.ArgumentParser(description="Tang Nano 9K Logic Analyzer Host")
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_cap = sub.add_parser("capture", help="Configure, capture, save capture.bin")
    p_cap.add_argument("--sample-rate", type=int, default=27_000_000)
    p_cap.add_argument("--channel-mask", type=lambda x: int(x, 0), default=0xFF)
    p_cap.add_argument("--trigger-channel", type=int, default=0)
    p_cap.add_argument("--trigger-type", default="rising")
    p_cap.add_argument("--pre", type=int, default=4096)
    p_cap.add_argument("--post", type=int, default=8192)
    p_cap.add_argument("-o", "--output", default="capture.bin")
    p_cap.add_argument("--vcd", default="capture.vcd")
    p_cap.add_argument("--show-channel", type=int, default=0)

    sub.add_parser("status", help="Read device status")

    p_meas = sub.add_parser("measure", help="Measure freq/duty on last capture.bin")
    p_meas.add_argument("--bin", default="capture.bin")
    p_meas.add_argument("--channel", type=int, default=0)
    p_meas.add_argument("--sample-rate", type=int, default=27_000_000)

    args = ap.parse_args()
    logic = LogicAnalyzer(args.port, args.baud)

    if args.cmd == "measure":
        data = Path(args.bin).read_bytes()
        bits = [((b >> args.channel) & 1) for b in data]
        edges = [i for i in range(1, len(bits)) if bits[i] and not bits[i - 1]]
        if len(edges) >= 2:
            periods = [edges[i] - edges[i - 1] for i in range(1, len(edges))]
            avg = sum(periods) / len(periods)
            freq = args.sample_rate / avg
        else:
            freq = 0.0
        duty = (sum(bits) / len(bits)) if bits else 0.0
        print(f"frequency ≈ {freq:.3f} Hz")
        print(f"duty ≈ {duty * 100:.2f} %")
        print(ascii_wave(bits, 80))
        return 0

    logic.connect()
    try:
        if args.cmd == "status":
            print(logic.status())
            return 0

        if args.cmd == "capture":
            logic.configure(
                sample_rate=args.sample_rate,
                channel_mask=args.channel_mask,
                trigger_channel=args.trigger_channel,
                trigger_type=args.trigger_type,
                pre_samples=args.pre,
                post_samples=args.post,
            )
            result = logic.capture()
            Path(args.output).write_bytes(result.samples)
            save_vcd(args.vcd, result.samples, result.sample_rate)
            print(f"saved {len(result.samples)} samples -> {args.output}, {args.vcd}")
            print(f"freq≈{logic.measure_frequency(args.show_channel):.3f} Hz")
            print(f"duty≈{logic.measure_duty(args.show_channel) * 100:.2f} %")
            print(ascii_wave(result.channel(args.show_channel), 80))
            return 0
    finally:
        logic.close()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
