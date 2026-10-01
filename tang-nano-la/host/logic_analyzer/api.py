"""Agent-facing Logic Analyzer API."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from .device import LogicAnalyzerDevice
from .protocol import Status


@dataclass
class CaptureResult:
    samples: bytes
    sample_rate: int
    channel_mask: int
    pre_samples: int
    post_samples: int
    oldest_addr: int

    def channel(self, ch: int) -> List[int]:
        return [((b >> ch) & 1) for b in self.samples]


class LogicAnalyzer:
    """High-level API used by Host / Agent tools."""

    def __init__(self, port: str = "/dev/ttyUSB1", baud: int = 115200):
        self.dev = LogicAnalyzerDevice(port, baud)
        self._cfg = {
            "sample_rate": 27_000_000,
            "channel_mask": 0xFF,
            "trigger_channel": 0,
            "trigger_type": "rising",
            "pre_samples": 4096,
            "post_samples": 8192,
        }
        self._last: Optional[CaptureResult] = None

    def connect(self) -> None:
        self.dev.connect()

    def close(self) -> None:
        self.dev.close()

    def configure(
        self,
        sample_rate: int = 27_000_000,
        channel_mask: int = 0xFF,
        trigger_channel: int = 0,
        trigger_type: str = "rising",
        pre_samples: int = 4096,
        post_samples: int = 8192,
    ) -> None:
        self._cfg.update(
            sample_rate=sample_rate,
            channel_mask=channel_mask,
            trigger_channel=trigger_channel,
            trigger_type=trigger_type,
            pre_samples=pre_samples,
            post_samples=post_samples,
        )
        self.dev.configure_trigger(trigger_channel, trigger_type)
        self.dev.configure_capture(sample_rate, channel_mask, pre_samples, post_samples)

    def status(self) -> Status:
        return self.dev.status()

    def capture(self, timeout_s: float = 10.0) -> CaptureResult:
        import time

        self.dev.configure_trigger(self._cfg["trigger_channel"], self._cfg["trigger_type"])
        self.dev.configure_capture(
            self._cfg["sample_rate"],
            self._cfg["channel_mask"],
            self._cfg["pre_samples"],
            self._cfg["post_samples"],
        )
        self.dev.start()
        t0 = time.time()
        while True:
            st = self.dev.status()
            if st.done:
                break
            if time.time() - t0 > timeout_s:
                self.dev.stop()
                raise TimeoutError("capture timeout")
            time.sleep(0.01)
        data = self.read_samples(st)
        self._last = data
        self.dev.stop()
        return data

    def read_samples(self, st: Optional[Status] = None) -> CaptureResult:
        st = st or self.dev.status()
        if not st.done:
            raise RuntimeError("capture not done")
        raw = self.dev.read_data(st.oldest_addr, st.total_samples)
        result = CaptureResult(
            samples=raw,
            sample_rate=self._cfg["sample_rate"],
            channel_mask=self._cfg["channel_mask"],
            pre_samples=self._cfg["pre_samples"],
            post_samples=self._cfg["post_samples"],
            oldest_addr=st.oldest_addr,
        )
        self._last = result
        return result

    def read_capture(self) -> CaptureResult:
        if self._last is None:
            return self.read_samples()
        return self._last

    def save_capture(self, path: str | Path = "capture.bin") -> Path:
        path = Path(path)
        data = self.read_capture()
        path.write_bytes(data.samples)
        return path

    # ---- Phase-2 placeholders (basic local analysis on last capture) ----

    def measure_frequency(self, channel: int) -> float:
        """Estimate frequency from last capture (host-side)."""
        data = self.read_capture()
        bits = data.channel(channel)
        edges = [i for i in range(1, len(bits)) if bits[i] and not bits[i - 1]]
        if len(edges) < 2:
            return 0.0
        periods = [edges[i] - edges[i - 1] for i in range(1, len(edges))]
        avg = sum(periods) / len(periods)
        return data.sample_rate / avg if avg else 0.0

    def measure_duty(self, channel: int) -> float:
        data = self.read_capture()
        bits = data.channel(channel)
        if not bits:
            return 0.0
        return sum(bits) / len(bits)

    def find_edges(self, channel: int) -> List[int]:
        data = self.read_capture()
        bits = data.channel(channel)
        return [i for i in range(1, len(bits)) if bits[i] != bits[i - 1]]


# Convenience alias
logic = None  # set by CLI / agent bootstrap
