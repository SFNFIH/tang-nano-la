// uart_tx.v
// 8N1 UART transmitter. Idle-high. Bit timing from CLKS_PER_BAUD.

`timescale 1ns / 1ps
`default_nettype none

module uart_tx #(
    parameter CLK_HZ         = 99_000_000,
    parameter BAUD           = 115200,
    parameter CLKS_PER_BAUD  = CLK_HZ / BAUD
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    output reg        tx_ready,
    output reg        tx_out
);

    localparam ST_IDLE = 2'd0;
    localparam ST_DATA = 2'd1; // start + 8 data + stop tracked by bit_idx

    reg [1:0]  state;
    reg [15:0] baud_cnt;
    reg [3:0]  bit_idx;
    reg [9:0]  shifter; // {stop, data[7:0], start}

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            baud_cnt <= 16'd0;
            bit_idx  <= 4'd0;
            shifter  <= 10'h3FF;
            tx_out   <= 1'b1;
            tx_ready <= 1'b1;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx_out   <= 1'b1;
                    tx_ready <= 1'b1;
                    if (tx_valid) begin
                        shifter  <= {1'b1, tx_data, 1'b0};
                        bit_idx  <= 4'd0;
                        baud_cnt <= CLKS_PER_BAUD[15:0] - 16'd1;
                        tx_ready <= 1'b0;
                        tx_out   <= 1'b0; // start bit immediately
                        state    <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    tx_ready <= 1'b0;
                    if (baud_cnt == 16'd0) begin
                        baud_cnt <= CLKS_PER_BAUD[15:0] - 16'd1;
                        bit_idx  <= bit_idx + 4'd1;
                        // shift out next bit (after start already on wire)
                        shifter  <= {1'b1, shifter[9:1]};
                        tx_out   <= shifter[1];
                        if (bit_idx == 4'd9) begin
                            // finished stop bit period
                            tx_out   <= 1'b1;
                            tx_ready <= 1'b1;
                            state    <= ST_IDLE;
                        end
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
