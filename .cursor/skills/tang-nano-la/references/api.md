# Host / Agent API cheat sheet

Package root: `tang-nano-la/host/`  
Import path: add that directory to `sys.path`, then `from logic_analyzer import LogicAnalyzer`.

## LogicAnalyzer methods

| Method | Purpose |
|--------|---------|
| `connect()` | Open serial port |
| `close()` | Close port |
| `configure(...)` | Set sample_rate, channel_mask, trigger_*, pre/post |
| `capture(timeout_s=10)` | Arm → wait trigger → read → stop |
| `status()` | Poll FPGA status flags |
| `read_samples()` / `read_capture()` | Fetch last / current buffer |
| `save_capture(path)` | Write `capture.bin` |
| `measure_frequency(ch)` | Host-side freq estimate (Hz) |
| `measure_duty(ch)` | Host-side high-time ratio 0..1 |
| `find_edges(ch)` | Sample indices where bit changes |

## configure() knobs

```python
logic.configure(
    sample_rate=99_000_000,   # effective ≈ 99e6 / div
    channel_mask=0xFF,        # bitmask of enabled channels
    trigger_channel=0,        # 0..7
    trigger_type="rising",    # rising|falling|high|low|pattern
    pre_samples=4096,
    post_samples=8192,
)
```

Effective rate uses integer divider from 99 MHz fabric clock.

## CLI equivalents

```bash
python cli.py --port /dev/ttyUSB1 status
python cli.py --port /dev/ttyUSB1 capture --trigger-channel 0 --trigger-type rising \
  --pre 4096 --post 8192 -o capture.bin --vcd capture.vcd
python cli.py measure --bin capture.bin --channel 0 --sample-rate 99000000
```

## CaptureResult

- `samples`: `bytes`, length = total samples; each byte is one time slot  
- `channel(ch) -> list[int]` of 0/1  
- Metadata: `sample_rate`, `pre_samples`, `post_samples`, `oldest_addr`

## Protocol reminder

Framed binary over UART (`A5`/`5A` + XOR checksum). Agents must not hand-roll bytes; see `docs/PROTOCOL.md` only when extending the FPGA protocol.
