---
name: tang-nano-la
description: >
  Drive the Sipeed Tang Nano 9K FPGA logic analyzer for embedded MCU hardware
  debugging. Use when capturing GPIO/SPI/I2C/UART/PWM digital signals, measuring
  frequency or duty, checking edges/triggers, flashing the LA bitstream, or
  debugging MCU pins with Tang Nano 9K / GW1NR-9 logic analyzer tooling.
---

# Tang Nano 9K Logic Analyzer

Use this skill to operate the phase-1 FPGA logic analyzer in `tang-nano-la/`.
Do **not** invent a new UART protocol — always go through the Python Host API
or `host/cli.py`.

## When to use

- Capture digital waveforms from an MCU (GPIO / UART / SPI / I2C / PWM)
- Wait for a rising/falling/level trigger on a probe channel
- Measure approximate frequency / duty from a capture
- Flash or rebuild the LA bitstream
- Debug “is this pin toggling?” style hardware questions

## Hardware map (do not guess)

| Role | Value |
|------|-------|
| Board | Tang Nano 9K (`GW1NR-LV9QN88PC6/I5`) |
| Sample clock | **27 MHz** (crystal pass-through; rPLL 99 MHz optional via `USE_PLL_99`) |
| UART | 115200 8N1 via BL702/FT2232; FPGA TX=17, RX=18 |
| Default serial | `/dev/ttyUSB1` (UART; JTAG may be `ttyUSB0`) |
| Probes `la_in[0..7]` | pins **19, 20, 25, 26, 27, 28, 29, 30** (3.3 V only) |
| Capture buffer | 8 ch × 16K samples (BSRAM) |

Details: [references/pinout.md](references/pinout.md)

**Voltage warning:** probe only ≤3.3 V. Never attach 5 V MCU I/O without level shifting.

## Preconditions

1. Bitstream programmed (`impl/pnr/la.fs` via Gowin, or `build/oss/la.fs` via OSS).
2. Host deps installed: `pip install -r tang-nano-la/host/requirements.txt`
3. Serial port present (`ls /dev/ttyUSB*`). Prefer the BL702 UART port.
4. DUT signal wired to the correct `la_in[n]` pin and common GND.

## Standard agent workflow

### 1) Identify the question

Map the user ask to channels + trigger:

| User intent | Channel | Trigger |
|-------------|---------|---------|
| “Is GPIO X toggling?” | that probe | `rising` or `falling` |
| “UART TX baud / activity” | TX line | `falling` (start bit) |
| “PWM duty / frequency” | PWM pin | `rising` |
| “SPI CLK present?” | SCK | `rising` |

### 2) Capture

Prefer CLI for one-shot jobs:

```bash
cd tang-nano-la/host
python cli.py --port /dev/ttyUSB1 capture \
  --trigger-channel 0 \
  --trigger-type rising \
  --sample-rate 99000000 \
  --pre 4096 --post 8192 \
  -o capture.bin --vcd capture.vcd --show-channel 0
```

Or Python API:

```python
import sys
from pathlib import Path
sys.path.insert(0, str(Path("tang-nano-la/host").resolve()))
from logic_analyzer import LogicAnalyzer

logic = LogicAnalyzer("/dev/ttyUSB1")
logic.connect()
try:
    logic.configure(
        sample_rate=27_000_000,
        channel_mask=0xFF,
        trigger_channel=0,
        trigger_type="rising",  # rising|falling|high|low|pattern
        pre_samples=4096,
        post_samples=8192,
    )
    result = logic.capture(timeout_s=10.0)
    logic.save_capture("capture.bin")
    print("samples", len(result.samples))
    print("freq_hz", logic.measure_frequency(0))
    print("duty", logic.measure_duty(0))
    print("edges", logic.find_edges(0)[:20])
finally:
    logic.close()
```

API cheat sheet: [references/api.md](references/api.md)

### 3) Interpret results

- `measure_frequency(ch)` / `measure_duty(ch)` are **host-side estimates** from the last capture — good for square/PWM sanity checks (e.g. 1 MHz / 50%).
- For sparse or bursty signals, inspect `find_edges(ch)` and/or open `capture.vcd` in GTKWave.
- Each sample byte = 8 channels; bit0 = `la_in[0]`.
- Default window: 4096 pre + 8192 post = 12288 samples ≈ 455 µs at 27 MHz.

### 4) Report to the user

Always state:

1. Port + channel + trigger used  
2. Sample rate and pre/post  
3. Measured frequency / duty (with ≈)  
4. Whether trigger timed out or capture completed  
5. Path to `capture.bin` / `capture.vcd` if saved  

## Status / recovery

```bash
python cli.py --port /dev/ttyUSB1 status
```

| Symptom | Action |
|---------|--------|
| `TimeoutError: capture timeout` | No edge seen — check wiring, trigger channel/type, or stimulate DUT |
| `CONFIG_* failed` / NAK | Wrong port or bitstream not loaded — reflash `impl/pnr/la.fs` |
| Permission denied on tty | `sudo usermod -aG dialout $USER` or use appropriate access |
| No `/dev/ttyUSB*` | Cable / BL702 driver / board power |

Abort a stuck capture: `python cli.py --port /dev/ttyUSB1` is not enough alone — use API `logic.dev.stop()` or power-cycle; START is cleared by STOP in protocol (`CMD 0x02`).

## Rebuild / flash (only when needed)

```bash
cd tang-nano-la
# Gowin IDE (preferred on this machine)
export QT_QPA_PLATFORM=offscreen LD_LIBRARY_PATH=/opt/gowin/IDE/lib
/opt/gowin/IDE/bin/gw_sh scripts/gowin-build.tcl   # -> impl/pnr/la.fs
unset LD_LIBRARY_PATH
openFPGALoader -b tangnano9k impl/pnr/la.fs
# optional persistent image:
openFPGALoader -b tangnano9k -f impl/pnr/la.fs

# OSS alternative (needs oss-cad-suite):
# ./scripts/oss-build.sh && openFPGALoader -b tangnano9k build/oss/la.fs
```

Do not modify RTL for ordinary capture tasks. If the user asks for new LA features (16 ch, protocol decode, higher baud), extend modules in `rtl/` + host protocol and re-sim with `make sim` first.

## Hard rules

1. Never parse raw UART bytes ad hoc — use `logic_analyzer` or `cli.py`.
2. Never stream samples during capture; flow is configure → capture → RAM → read.
3. Current Gowin bitstream uses **27_000_000** crystal clock (rPLL 99 MHz not enabled). Use that as `sample_rate` base.
4. Never probe 5 V or 1.8 V bank pins (79–85) for this LA mapping.
5. Keep captures reproducible: record channel, trigger, rates, and output files.

## Phase-1 vs later

Implemented now: `connect`, `configure`, `capture`, `status`, `read_samples` / `read_capture`, plus host-side `measure_frequency` / `measure_duty` / `find_edges`.

Not in FPGA yet (do not claim hardware decode): `decode_uart` / `decode_spi` / `decode_i2c`. If asked, either implement as a follow-up or perform offline decode from `capture.bin` with clear caveats.
