# Probe pinout

Tang Nano 9K logic analyzer default mapping (`cst/tangnano9k.cst`).

## Channels

| Channel | FPGA pin | Net | Notes |
|---------|----------|-----|-------|
| LA0 | 19 | IOB4A | default trigger example |
| LA1 | 20 | IOB4B | |
| LA2 | 25 | IOB8A | |
| LA3 | 26 | IOB8B | |
| LA4 | 27 | IOB11A | |
| LA5 | 28 | IOB11B | |
| LA6 | 29 | IOB13A | |
| LA7 | 30 | IOB13B | |

All above are **3.3 V** bank header pins.

## Board I/O used by firmware

| Signal | Pin |
|--------|-----|
| `clk_27m` | 52 |
| `uart_tx` | 17 |
| `uart_rx` | 18 |
| LED0..5 | 10,11,13,14,15,16 (active-low status) |

## Wiring checklist

1. Common GND between MCU and Tang Nano 9K  
2. DUT signal → chosen `la_in[n]`  
3. Confirm MCU I/O voltage is 3.3 V (or level-shifted)  
4. USB cable provides JTAG+UART via BL702  
