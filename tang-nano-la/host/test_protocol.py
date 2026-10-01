#!/usr/bin/env python3
"""Offline protocol unit tests (no hardware)."""

from logic_analyzer.protocol import (
    Cmd,
    Resp,
    build_frame,
    checksum,
    parse_frames,
    Status,
)


def test_roundtrip_ack():
    frame = build_frame(Cmd.START_CAPTURE, b"")
    assert frame[0] == 0xA5
    assert frame[1] == Cmd.START_CAPTURE
    assert checksum(frame[1], 0, b"") == frame[-1]


def test_parse_status():
    payload = bytes(
        [
            0xF0,  # flags
            0x03,  # state DONE
            0x00,
            0x30,  # 12288
            0x10,
            0x00,  # oldest
            0x01,
            0x00,  # div
            0xFF,
            0x00,
        ]
    )
    body = bytes([0x5A, Resp.STATUS, len(payload) & 0xFF, 0x00]) + payload
    body += bytes([checksum(Resp.STATUS, len(payload), payload)])
    frames = parse_frames(bytearray(body))
    assert len(frames) == 1
    st = Status.from_payload(frames[0].payload)
    assert st.done and st.total_samples == 0x3000


if __name__ == "__main__":
    test_roundtrip_ack()
    test_parse_status()
    print("PASS: protocol unit tests")
