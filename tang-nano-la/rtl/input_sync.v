// input_sync.v
// 2-flop synchronizer for asynchronous digital probe inputs.
// Never feed raw async GPIO into trigger/capture combinatorial logic.

`timescale 1ns / 1ps
`default_nettype none

module input_sync #(
    parameter CHANNELS = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [CHANNELS-1:0]   gpio_async,
    output reg  [CHANNELS-1:0]   gpio_sync
);

    reg [CHANNELS-1:0] meta;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta      <= {CHANNELS{1'b0}};
            gpio_sync <= {CHANNELS{1'b0}};
        end else begin
            meta      <= gpio_async; // FF1
            gpio_sync <= meta;       // FF2
        end
    end

endmodule

`default_nettype wire
