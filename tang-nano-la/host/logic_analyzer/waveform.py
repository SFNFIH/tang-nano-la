"""Waveform helpers (ASCII / matplotlib optional)."""

from __future__ import annotations

from typing import Iterable, List


def ascii_wave(bits: Iterable[int], width: int = 80) -> str:
    bits = list(bits)[:width]
    if not bits:
        return ""
    hi = "".join("_" if b else " " for b in bits)
    lo = "".join(" " if b else "_" for b in bits)
    return f"1 {hi}\n0 {lo}"


def save_vcd(path: str, samples: bytes, sample_rate: int, channels: int = 8) -> None:
    """Minimal VCD for GTKWave."""
    dt_ps = int(1e12 / sample_rate)
    ids = [chr(ord("!") + i) for i in range(channels)]
    with open(path, "w", encoding="utf-8") as f:
        f.write("$timescale 1ps $end\n")
        f.write("$scope module la $end\n")
        for i, sid in enumerate(ids):
            f.write(f"$var wire 1 {sid} ch{i} $end\n")
        f.write("$upscope $end\n$enddefinitions $end\n")
        prev = None
        for n, s in enumerate(samples):
            if s == prev:
                continue
            f.write(f"#{n * dt_ps}\n")
            for i, sid in enumerate(ids):
                bit = (s >> i) & 1
                if prev is None or (((prev >> i) & 1) != bit):
                    f.write(f"{bit}{sid}\n")
            prev = s
        f.write(f"#{len(samples) * dt_ps}\n")
