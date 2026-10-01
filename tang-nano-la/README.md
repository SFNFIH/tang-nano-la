# Tang Nano 9K Logic Analyzer (Phase 1)

FPGA digital logic analyzer for AI-agent MCU debugging.

```
MCU GPIO / SPI / I2C / UART / PWM
        ↓
 Tang Nano 9K (GW1NR-9)
  sync → trigger → capture → BSRAM
        ↓
   USB-UART (BL702 @ 115200)
        ↓
   Python Host / Agent API
```

## Hardware baseline (from schematic + Wiki)

| Item | Value |
|------|-------|
| FPGA | GW1NR-LV9QN88PC6/I5 |
| Clock | 27 MHz pin 52 → rPLL **99 MHz** sample clock |
| UART | FPGA TX pin 17, RX pin 18 → BL702 USB-UART |
| Probes | pins 19,20,25,26,27,28,29,30 (`la_in[7:0]`) |
| Capture | 8 ch × 16K samples in BSRAM |

Details: [`docs/HARDWARE.md`](docs/HARDWARE.md)

## Repository layout

```
tang-nano-la/
  rtl/           Verilog modules
  cst/           Gowin constraints
  sim/           Icarus testbenches
  host/          Python protocol + Agent API
  docs/          hardware / protocol / timing
```

## Simulation

```bash
sudo apt-get install -y iverilog   # if needed
cd tang-nano-la
make sim
```

Verified: `input_sync`, `trigger_engine`, `capture_engine`, `uart_tx`, `tb_top`.

## Bitstream

### Open-source flow (verified)

```bash
# needs yosys + nextpnr-himbaechel + apicula (oss-cad-suite)
./scripts/oss-build.sh
# -> build/oss/la.fs
openFPGALoader -b tangnano9k build/oss/la.fs
```

Latest OSS build on this tree:

| Metric | Value |
|--------|------:|
| LUT4 | 1134 / 8640 (13%) |
| BSRAM | 8 / 26 (30%) |
| Fmax (`clk_sample`) | **~115 MHz** (PASS vs 90 MHz constraint) |
| PLL output | **99.000 MHz** |

### Gowin IDE (optional)

1. Project device `GW1NR-LV9QN88PC6/I5`
2. Add `rtl/*.v` (**without** `-DSIMULATION`)
3. Add `cst/tangnano9k.cst`
4. Run synth / P&R / bitstream

## Agent Skill

Cursor Agent skill (auto-discovered from the project):

```
.cursor/skills/tang-nano-la/SKILL.md
```

Invoke with `/tang-nano-la`, or ask the agent to capture/measure MCU pins — it should load this skill and use the Host API instead of raw UART.

## Python Host

```bash
cd host
pip install -r requirements.txt
python cli.py --port /dev/ttyUSB1 capture \
  --trigger-channel 0 --trigger-type rising \
  --pre 4096 --post 8192 -o capture.bin
```

### Agent API

```python
from logic_analyzer import LogicAnalyzer

logic = LogicAnalyzer("/dev/ttyUSB1")
logic.connect()
logic.configure(
    sample_rate=99_000_000,
    channel_mask=0xFF,
    trigger_channel=0,
    trigger_type="rising",
    pre_samples=4096,
    post_samples=8192,
)
result = logic.capture()
logic.save_capture("capture.bin")
print(logic.status())
samples = logic.read_samples()
# Phase-2 style helpers already usable on captured data:
print(logic.measure_frequency(0), logic.measure_duty(0))
```

Protocol: [`docs/PROTOCOL.md`](docs/PROTOCOL.md)  
Timing / FSM: [`docs/TIMING.md`](docs/TIMING.md)

## Acceptance test (1 MHz square / 50% duty)

1. Program bitstream
2. Drive MCU 1 MHz 50% square into `la_in[0]` (pin 19)
3. Run host capture with rising trigger on ch0
4. Expect `measure_frequency ≈ 1e6`, `measure_duty ≈ 0.5`

## Probe voltage warning

Pins 19–30 are **3.3 V** bank. Do not probe 5 V MCU I/O without level shifting.
1.8 V header pins (79–85) are not used for probes.
