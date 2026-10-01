// clk_gen.v
// Sample clock from Tang Nano 9K 27 MHz crystal.
// Gowin IDE bitstream currently uses crystal pass-through.
// rPLL 99 MHz module remains in gowin_pll_99.v (enable with USE_PLL_99).

`timescale 1ns / 1ps
`default_nettype none

module clk_gen #(
    parameter real CLK_IN_HZ  = 27_000_000.0,
    parameter real CLK_OUT_HZ = 27_000_000.0
) (
    input  wire clk_in,
    input  wire rst_n,
    output wire clk_sample,
    output wire clk_locked
);

`ifdef SIMULATION
    reg clk_s = 1'b0;
    reg locked = 1'b0;

    initial begin
        wait (rst_n === 1'b1);
        repeat (8) @(posedge clk_in);
        locked = 1'b1;
    end

    // 100 MHz in simulation for clean timing
    always #5 clk_s = ~clk_s;

    assign clk_sample = clk_s;
    assign clk_locked = locked;
`else
`ifdef USE_PLL_99
    gowin_pll_99 u_pll (
        .clock_in(clk_in),
        .clock_out(clk_sample),
        .locked(clk_locked)
    );
`else
    assign clk_sample = clk_in;
    assign clk_locked = 1'b1;
`endif
`endif

endmodule

`default_nettype wire
