// trigger_engine.v
// Independent trigger detector on synchronized sample stream.
//
// trigger_type:
//   3'd0 RISING_EDGE
//   3'd1 FALLING_EDGE
//   3'd2 LEVEL_HIGH
//   3'd3 LEVEL_LOW
//   3'd4 PATTERN   (phase-1: match (sample & mask) == (pattern & mask))

`timescale 1ns / 1ps
`default_nettype none

module trigger_engine #(
    parameter CHANNELS = 8
) (
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire                      arm,           // level: look for trigger while high
    input  wire [CHANNELS-1:0]       sample,

    input  wire [$clog2(CHANNELS)-1:0] trigger_channel,
    input  wire [2:0]                trigger_type,
    input  wire [CHANNELS-1:0]       pattern,
    input  wire [CHANNELS-1:0]       pattern_mask,

    output reg                       triggered      // 1-cycle pulse when condition met
);

    localparam TRIG_RISING  = 3'd0;
    localparam TRIG_FALLING = 3'd1;
    localparam TRIG_HIGH    = 3'd2;
    localparam TRIG_LOW     = 3'd3;
    localparam TRIG_PATTERN = 3'd4;

    reg [CHANNELS-1:0] sample_d;
    reg armed_d;

    wire ch_now  = sample[trigger_channel];
    wire ch_prev = sample_d[trigger_channel];

    wire rising  =  ch_now & ~ch_prev;
    wire falling = ~ch_now &  ch_prev;
    wire pattern_hit = ((sample & pattern_mask) == (pattern & pattern_mask));

    reg hit;

    always @(*) begin
        case (trigger_type)
            TRIG_RISING:  hit = rising;
            TRIG_FALLING: hit = falling;
            TRIG_HIGH:    hit = ch_now;
            TRIG_LOW:     hit = ~ch_now;
            TRIG_PATTERN: hit = pattern_hit;
            default:      hit = rising;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_d  <= {CHANNELS{1'b0}};
            armed_d   <= 1'b0;
            triggered <= 1'b0;
        end else begin
            sample_d  <= sample;
            armed_d   <= arm;
            // Require arm stable at least one cycle so edge uses valid history
            triggered <= arm & armed_d & hit;
        end
    end

endmodule

`default_nettype wire
