// uart_rx.v
// 8N1 UART receiver with mid-bit sampling.

`timescale 1ns / 1ps
`default_nettype none

module uart_rx #(
    parameter CLK_HZ         = 99_000_000,
    parameter BAUD           = 115200,
    parameter CLKS_PER_BAUD  = CLK_HZ / BAUD
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_in,
    output reg        rx_valid,
    output reg  [7:0] rx_data
);

    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shifter;
    reg        rx_meta, rx_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx_in;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            baud_cnt <= 16'd0;
            bit_idx  <= 3'd0;
            shifter  <= 8'd0;
            rx_valid <= 1'b0;
            rx_data  <= 8'd0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (!rx_sync) begin
                        baud_cnt <= (CLKS_PER_BAUD[15:0] >> 1) - 16'd1;
                        state    <= ST_START;
                    end
                end

                ST_START: begin
                    if (baud_cnt == 16'd0) begin
                        if (!rx_sync) begin
                            baud_cnt <= CLKS_PER_BAUD[15:0] - 16'd1;
                            bit_idx  <= 3'd0;
                            state    <= ST_DATA;
                        end else begin
                            state <= ST_IDLE; // false start
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                end

                ST_DATA: begin
                    if (baud_cnt == 16'd0) begin
                        baud_cnt <= CLKS_PER_BAUD[15:0] - 16'd1;
                        shifter  <= {rx_sync, shifter[7:1]};
                        if (bit_idx == 3'd7)
                            state <= ST_STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                end

                ST_STOP: begin
                    if (baud_cnt == 16'd0) begin
                        if (rx_sync) begin
                            rx_data  <= shifter;
                            rx_valid <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt - 16'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
