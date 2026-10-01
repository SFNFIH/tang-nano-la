# Architecture, FSM, Timing

## Module hierarchy

```
top
 ├── clk_gen          27 MHz → ~99 MHz sample clock (rPLL)
 ├── input_sync       2-FF synchronizer per channel
 ├── trigger_engine   edge / level / pattern detect
 ├── capture_engine   pre/post circular capture FSM
 ├── capture_ram      dual-port BSRAM buffer
 ├── uart_rx / uart_tx
 └── control_regs    binary host protocol + config regs
```

## Clocking

| Clock | Source | Use |
|-------|--------|-----|
| `clk_27m` | pin 52 crystal | PLL input only |
| `clk_sample` | rPLL ≈ **99 MHz** | sync, trigger, capture, UART, control |

MCU I/O is asynchronous to `clk_sample`. All probe inputs pass through
`input_sync` before any decision logic.

Exact 100.000 MHz is not reachable with one Gowin rPLL stage (`FBDIV≤64`).
Phase-1 uses `27 × 33 / 9 = 99 MHz`.

## Capture FSM

```
        start_rise
 IDLE ─────────────► PRE
  ▲                   │ armed when filled >= pre_samples
  │                   │ triggered
  │                   ▼
  │                  POST
  │                   │ post_count == post_samples
  │                   ▼
  └──── !start ──── DONE
```

### Semantics

- Rolling circular write in `PRE`
- Trigger sample = last written sample when `triggered` pulses
  (pulse is one cycle after the edge appears on synchronized data)
- Then exactly `post_samples` further writes
- `total_samples = pre_samples + post_samples`
- `oldest_addr = trig_addr - pre_samples + 1` (wraps with RAM depth)

## Trigger timing (sample domain)

```
clk_sample  : /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
gpio_async  : ______/──────────
gpio_sync   : ________/────────   (2 FF later)
sample_d    : __________/──────
triggered   : ____________/-\__   (1-cycle pulse)
capture     :   PRE........|POST....|DONE
```

## Input synchronizer

```
GPIO (async) → FF1 (meta) → FF2 (gpio_sync) → trigger/capture
```

Never use `gpio_async` in combinatorial trigger logic.

## RAM ports

| Port | Clock | Role |
|------|-------|------|
| write | `clk_sample` | capture_engine only, while busy |
| read  | `clk_sample` | control_regs READ_DATA after DONE |

Phase-1 uses one clock for both ports; protocol forbids READ during capture so
UART traffic cannot steal sample bandwidth.

## Resources (phase-1 defaults)

- Channels = 8, Depth = 16384 → **128 Kbit** BSRAM (board has 468 Kbit)
- Parameterized for `16 × 8192` without RTL rewrite
