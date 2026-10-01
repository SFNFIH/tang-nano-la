// capture_ram.v
// Dual-port capture buffer (write @ sample clk, read @ host clk).
// Maps to Gowin BSRAM via block-ram inference.

`timescale 1ns / 1ps
`default_nettype none

module capture_ram #(
    parameter CHANNELS = 8,
    parameter DEPTH    = 16384,
    parameter ADDR_W   = $clog2(DEPTH)
) (
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [ADDR_W-1:0]     wr_addr,
    input  wire [CHANNELS-1:0]   wr_data,

    input  wire                  rd_clk,
    input  wire                  rd_en,
    input  wire [ADDR_W-1:0]     rd_addr,
    output reg  [CHANNELS-1:0]   rd_data
);

    (* ram_style = "block" *)
    (* syn_ramstyle = "block_ram" *)
    reg [CHANNELS-1:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {CHANNELS{1'b0}};
    end

    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge rd_clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

endmodule

`default_nettype wire
