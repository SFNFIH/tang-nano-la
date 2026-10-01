// capture_engine.v
// Circular pre-trigger store + post-trigger fill, then DONE.
//
// FSM: IDLE -> PRE -> POST -> DONE -> IDLE
//
// Semantics:
//   total_samples = pre_samples + post_samples
//   Trigger sample is the last sample of the pre window.
//   oldest_addr points to (trigger_addr - pre_samples + 1).

`timescale 1ns / 1ps
`default_nettype none

module capture_engine #(
    parameter CHANNELS = 8,
    parameter DEPTH    = 16384,
    parameter ADDR_W   = $clog2(DEPTH),
    parameter COUNT_W  = 16
) (
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire                      start,
    input  wire                      abort,
    input  wire                      sample_en,
    input  wire [CHANNELS-1:0]       sample,
    input  wire                      triggered,

    input  wire [COUNT_W-1:0]        pre_samples,
    input  wire [COUNT_W-1:0]        post_samples,
    input  wire [CHANNELS-1:0]       channel_mask,

    output reg                       wr_en,
    output reg  [ADDR_W-1:0]         wr_addr,
    output reg  [CHANNELS-1:0]       wr_data,

    output reg                       arm_trigger,
    output wire                      busy,
    output wire                      done,
    output reg  [ADDR_W-1:0]         oldest_addr,
    output reg  [COUNT_W-1:0]        total_samples,
    output reg  [2:0]                state
);

    localparam ST_IDLE = 3'd0;
    localparam ST_PRE  = 3'd1;
    localparam ST_POST = 3'd2;
    localparam ST_DONE = 3'd3;

    reg start_d;
    wire start_rise = start & ~start_d;

    reg [ADDR_W-1:0]  wr_ptr;
    reg [COUNT_W-1:0] filled;
    reg [COUNT_W-1:0] post_count;
    reg [ADDR_W-1:0]  trig_addr;

    assign busy = (state == ST_PRE) || (state == ST_POST);
    assign done = (state == ST_DONE);

    wire [CHANNELS-1:0] masked = sample & channel_mask;
    wire pre_ready = (pre_samples == {COUNT_W{1'b0}}) || (filled >= pre_samples);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            start_d       <= 1'b0;
            wr_en         <= 1'b0;
            wr_addr       <= {ADDR_W{1'b0}};
            wr_data       <= {CHANNELS{1'b0}};
            wr_ptr        <= {ADDR_W{1'b0}};
            filled        <= {COUNT_W{1'b0}};
            post_count    <= {COUNT_W{1'b0}};
            trig_addr     <= {ADDR_W{1'b0}};
            arm_trigger   <= 1'b0;
            oldest_addr   <= {ADDR_W{1'b0}};
            total_samples <= {COUNT_W{1'b0}};
        end else begin
            start_d <= start;
            wr_en   <= 1'b0;

            case (state)
                ST_IDLE: begin
                    arm_trigger <= 1'b0;
                    filled      <= {COUNT_W{1'b0}};
                    post_count  <= {COUNT_W{1'b0}};
                    if (start_rise) begin
                        wr_ptr <= {ADDR_W{1'b0}};
                        state  <= ST_PRE;
                    end
                end

                ST_PRE: begin
                    arm_trigger <= pre_ready;

                    if (abort) begin
                        state <= ST_IDLE;
                    end else if (triggered && pre_ready) begin
                        // Last committed sample is the trigger sample.
                        trig_addr   <= wr_ptr - 1'b1;
                        arm_trigger <= 1'b0;

                        // If a sample is presented this cycle, it is the first POST sample.
                        if (sample_en && (post_samples != {COUNT_W{1'b0}})) begin
                            wr_en      <= 1'b1;
                            wr_addr    <= wr_ptr;
                            wr_data    <= masked;
                            wr_ptr     <= wr_ptr + 1'b1;
                            post_count <= {{(COUNT_W-1){1'b0}}, 1'b1};
                            if (post_samples == {{(COUNT_W-1){1'b0}}, 1'b1}) begin
                                oldest_addr   <= (wr_ptr - 1'b1) - pre_samples[ADDR_W-1:0] + 1'b1;
                                total_samples <= pre_samples + post_samples;
                                state         <= ST_DONE;
                            end else begin
                                state <= ST_POST;
                            end
                        end else if (post_samples == {COUNT_W{1'b0}}) begin
                            oldest_addr   <= (wr_ptr - 1'b1) - pre_samples[ADDR_W-1:0] + 1'b1;
                            total_samples <= pre_samples;
                            post_count    <= {COUNT_W{1'b0}};
                            state         <= ST_DONE;
                        end else begin
                            post_count <= {COUNT_W{1'b0}};
                            state      <= ST_POST;
                        end
                    end else if (sample_en) begin
                        wr_en   <= 1'b1;
                        wr_addr <= wr_ptr;
                        wr_data <= masked;
                        wr_ptr  <= wr_ptr + 1'b1;
                        if (filled != {COUNT_W{1'b1}})
                            filled <= filled + 1'b1;
                    end
                end

                ST_POST: begin
                    arm_trigger <= 1'b0;
                    if (abort) begin
                        state <= ST_IDLE;
                    end else if (sample_en) begin
                        wr_en      <= 1'b1;
                        wr_addr    <= wr_ptr;
                        wr_data    <= masked;
                        wr_ptr     <= wr_ptr + 1'b1;
                        post_count <= post_count + 1'b1;

                        if ((post_count + 1'b1) >= post_samples) begin
                            oldest_addr   <= trig_addr - pre_samples[ADDR_W-1:0] + 1'b1;
                            total_samples <= pre_samples + post_samples;
                            state         <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    arm_trigger <= 1'b0;
                    if (abort || !start)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
