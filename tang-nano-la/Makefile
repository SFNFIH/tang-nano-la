# Tang Nano 9K Logic Analyzer
CHANNEL ?= 8
DEPTH   ?= 16384

IVERILOG = iverilog -g2012 -DSIMULATION
VVP      = vvp

RTL = rtl/clk_gen.v rtl/gowin_pll_99.v rtl/input_sync.v rtl/trigger_engine.v \
      rtl/capture_ram.v rtl/capture_engine.v \
      rtl/uart_tx.v rtl/uart_rx.v rtl/control_regs.v rtl/top.v

.PHONY: all sim sim-input sim-trigger sim-capture sim-uart sim-top clean

all: sim

sim: sim-input sim-trigger sim-capture sim-uart sim-top

sim-input:
	$(IVERILOG) -o sim/tb_input_sync.out rtl/input_sync.v sim/tb_input_sync.v
	$(VVP) sim/tb_input_sync.out

sim-trigger:
	$(IVERILOG) -o sim/tb_trigger_engine.out rtl/trigger_engine.v sim/tb_trigger_engine.v
	$(VVP) sim/tb_trigger_engine.out

sim-capture:
	$(IVERILOG) -o sim/tb_capture_engine.out rtl/capture_engine.v sim/tb_capture_engine.v
	$(VVP) sim/tb_capture_engine.out

sim-uart:
	$(IVERILOG) -o sim/tb_uart_tx.out rtl/uart_tx.v sim/tb_uart_tx.v
	$(VVP) sim/tb_uart_tx.out

sim-top:
	$(IVERILOG) -o sim/tb_top.out $(RTL) sim/tb_top.v
	$(VVP) sim/tb_top.out

clean:
	rm -f sim/*.out sim/*.vcd
