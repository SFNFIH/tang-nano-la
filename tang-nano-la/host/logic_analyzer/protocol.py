"""Binary protocol for Tang Nano 9K Logic Analyzer."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import List, Optional

HOST_MAGIC = 0xA5
FPGA_MAGIC = 0x5A


class Cmd(IntEnum):
    START_CAPTURE = 0x01
    STOP_CAPTURE = 0x02
    READ_STATUS = 0x03
    READ_DATA = 0x04
    CONFIG_TRIGGER = 0x05
    CONFIG_CAPTURE = 0x06


class Resp(IntEnum):
    ACK = 0x00
    NAK = 0x01
    STATUS = 0x83
    DATA = 0x84


class TriggerType(IntEnum):
    RISING = 0
    FALLING = 1
    LEVEL_HIGH = 2
    LEVEL_LOW = 3
    PATTERN = 4


TRIGGER_NAME = {
    "rising": TriggerType.RISING,
    "falling": TriggerType.FALLING,
    "high": TriggerType.LEVEL_HIGH,
    "low": TriggerType.LEVEL_LOW,
    "pattern": TriggerType.PATTERN,
}


def checksum(cmd_or_resp: int, length: int, payload: bytes) -> int:
    c = cmd_or_resp ^ (length & 0xFF) ^ ((length >> 8) & 0xFF)
    for b in payload:
        c ^= b
    return c & 0xFF


def build_frame(cmd: int, payload: bytes = b"") -> bytes:
    length = len(payload)
    chk = checksum(cmd, length, payload)
    return bytes([HOST_MAGIC, cmd, length & 0xFF, (length >> 8) & 0xFF]) + payload + bytes([chk])


@dataclass
class Frame:
    resp: int
    payload: bytes


def parse_frames(buf: bytearray) -> List[Frame]:
    """Extract complete frames from a mutable RX buffer."""
    out: List[Frame] = []
    while True:
        if len(buf) < 5:
            break
        try:
            start = buf.index(FPGA_MAGIC)
        except ValueError:
            buf.clear()
            break
        if start:
            del buf[:start]
        if len(buf) < 5:
            break
        resp = buf[1]
        length = buf[2] | (buf[3] << 8)
        need = 5 + length
        if len(buf) < need:
            break
        payload = bytes(buf[4 : 4 + length])
        chk = buf[4 + length]
        if chk != checksum(resp, length, payload):
            # drop magic and resync
            del buf[0]
            continue
        out.append(Frame(resp=resp, payload=payload))
        del buf[:need]
    return out


@dataclass
class Status:
    pll_locked: bool
    armed: bool
    busy: bool
    done: bool
    state: int
    total_samples: int
    oldest_addr: int
    sample_div: int
    channel_mask: int

    @classmethod
    def from_payload(cls, p: bytes) -> "Status":
        if len(p) < 10:
            raise ValueError("status payload too short")
        flags = p[0]
        return cls(
            pll_locked=bool(flags & 0x80),
            armed=bool(flags & 0x40),
            busy=bool(flags & 0x20),
            done=bool(flags & 0x10),
            state=p[1] & 0x7,
            total_samples=p[2] | (p[3] << 8),
            oldest_addr=p[4] | (p[5] << 8),
            sample_div=p[6] | (p[7] << 8),
            channel_mask=p[8],
        )
