"""Serial device driver for Tang Nano 9K LA."""

from __future__ import annotations

import time
from typing import Optional

import serial

from .protocol import (
    Cmd,
    Frame,
    Resp,
    Status,
    TriggerType,
    TRIGGER_NAME,
    build_frame,
    parse_frames,
)


class LogicAnalyzerDevice:
    def __init__(self, port: str, baud: int = 115200, timeout: float = 1.0):
        self.port = port
        self.baud = baud
        self.timeout = timeout
        self.ser: Optional[serial.Serial] = None
        self._rx = bytearray()
        self.sample_rate_hz = 99_000_000
        self.channels = 8

    def connect(self) -> None:
        self.ser = serial.Serial(self.port, self.baud, timeout=self.timeout)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        self._rx.clear()

    def close(self) -> None:
        if self.ser:
            self.ser.close()
            self.ser = None

    def _write(self, data: bytes) -> None:
        assert self.ser is not None
        self.ser.write(data)
        self.ser.flush()

    def _read_frame(self, deadline: float) -> Frame:
        assert self.ser is not None
        while time.time() < deadline:
            chunk = self.ser.read(self.ser.in_waiting or 1)
            if chunk:
                self._rx.extend(chunk)
                frames = parse_frames(self._rx)
                if frames:
                    return frames[0]
            else:
                time.sleep(0.001)
        raise TimeoutError("UART response timeout")

    def transact(self, cmd: int, payload: bytes = b"", timeout: Optional[float] = None) -> Frame:
        self._write(build_frame(cmd, payload))
        return self._read_frame(time.time() + (timeout or self.timeout))

    def configure_trigger(
        self,
        channel: int = 0,
        trigger_type: str | int = "rising",
        pattern: int = 0,
        mask: int = 0xFF,
    ) -> None:
        if isinstance(trigger_type, str):
            trigger_type = TRIGGER_NAME[trigger_type.lower()]
        payload = bytes(
            [
                channel & 0xFF,
                int(trigger_type) & 0xFF,
                pattern & 0xFF,
                0x00,
                mask & 0xFF,
                0x00,
            ]
        )
        fr = self.transact(Cmd.CONFIG_TRIGGER, payload)
        if fr.resp != Resp.ACK:
            raise RuntimeError(f"CONFIG_TRIGGER failed: {fr.resp:#x}")

    def configure_capture(
        self,
        sample_rate: int = 99_000_000,
        channel_mask: int = 0xFF,
        pre_samples: int = 4096,
        post_samples: int = 8192,
    ) -> None:
        div = max(1, int(round(self.sample_rate_hz / sample_rate)))
        payload = bytes(
            [
                div & 0xFF,
                (div >> 8) & 0xFF,
                channel_mask & 0xFF,
                0x00,
                pre_samples & 0xFF,
                (pre_samples >> 8) & 0xFF,
                post_samples & 0xFF,
                (post_samples >> 8) & 0xFF,
            ]
        )
        fr = self.transact(Cmd.CONFIG_CAPTURE, payload)
        if fr.resp != Resp.ACK:
            raise RuntimeError(f"CONFIG_CAPTURE failed: {fr.resp:#x}")

    def start(self) -> None:
        fr = self.transact(Cmd.START_CAPTURE)
        if fr.resp != Resp.ACK:
            raise RuntimeError("START failed")

    def stop(self) -> None:
        fr = self.transact(Cmd.STOP_CAPTURE)
        if fr.resp != Resp.ACK:
            raise RuntimeError("STOP failed")

    def status(self) -> Status:
        fr = self.transact(Cmd.READ_STATUS)
        if fr.resp != Resp.STATUS:
            raise RuntimeError(f"STATUS failed: {fr.resp:#x}")
        return Status.from_payload(fr.payload)

    def read_data(self, addr: int, count: int, timeout: float = 30.0) -> bytes:
        payload = bytes(
            [
                addr & 0xFF,
                (addr >> 8) & 0xFF,
                count & 0xFF,
                (count >> 8) & 0xFF,
            ]
        )
        fr = self.transact(Cmd.READ_DATA, payload, timeout=timeout)
        if fr.resp != Resp.DATA:
            raise RuntimeError(f"READ_DATA failed: {fr.resp:#x}")
        if len(fr.payload) != count:
            raise RuntimeError(f"READ_DATA length {len(fr.payload)} != {count}")
        return fr.payload
