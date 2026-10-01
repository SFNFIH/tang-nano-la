# Protocol

## Framing

Host → FPGA

```
A5 | CMD | LEN_L | LEN_H | PAYLOAD[LEN] | CHK
```

FPGA → Host

```
5A | RESP | LEN_L | LEN_H | PAYLOAD[LEN] | CHK
```

`CHK = XOR(CMD/RESP, LEN_L, LEN_H, PAYLOAD...)`

UART: **115200 8N1** (phase 1).

## Commands

| CMD  | Name            | Payload |
|------|-----------------|---------|
| 0x01 | START_CAPTURE   | — |
| 0x02 | STOP_CAPTURE    | — |
| 0x03 | READ_STATUS     | — |
| 0x04 | READ_DATA       | `addr_u16`, `count_u16` |
| 0x05 | CONFIG_TRIGGER  | `ch_u8`, `type_u8`, `pattern_u8`, `0`, `mask_u8`, `0` |
| 0x06 | CONFIG_CAPTURE  | `div_u16`, `mask_u8`, `0`, `pre_u16`, `post_u16` |

### Trigger type

| Value | Meaning |
|------:|---------|
| 0 | rising |
| 1 | falling |
| 2 | level high |
| 3 | level low |
| 4 | pattern `(sample & mask) == (pattern & mask)` |

### Capture config

Effective sample rate ≈ `99_000_000 / div` Hz (`div >= 1`).

## Responses

| RESP | Name   | Payload |
|------|--------|---------|
| 0x00 | ACK    | — |
| 0x01 | NAK    | — |
| 0x83 | STATUS | 10 bytes (see below) |
| 0x84 | DATA   | `count` sample bytes |

### STATUS payload

| Offset | Field |
|--------|-------|
| 0 | flags: `{pll, armed, busy, done, 0,0,0,0}` |
| 1 | capture FSM state |
| 2-3 | total_samples |
| 4-5 | oldest_addr |
| 6-7 | sample_div |
| 8 | channel_mask |
| 9 | reserved |

## Capture flow

```
CONFIG_TRIGGER / CONFIG_CAPTURE
        ↓
   START_CAPTURE
        ↓
   poll READ_STATUS until done
        ↓
   READ_DATA(oldest_addr, total_samples)
        ↓
   STOP_CAPTURE
        ↓
   save capture.bin
```

Sampling never streams over UART in real time: **sample → RAM → stop → UART**.
