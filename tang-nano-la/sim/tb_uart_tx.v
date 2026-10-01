`timescale 1ns / 1ps
`default_nettype none

module tb_uart_tx;
    reg clk = 0;
    reg rst_n = 0;
    reg tx_valid = 0;
    reg [7:0] tx_data = 0;
    wire tx_ready;
    wire tx_out;

    // Fast baud for sim: 100 MHz / 8 = 12.5 Mbaud
    uart_tx #(.CLK_HZ(100_000_000), .BAUD(12_500_000), .CLKS_PER_BAUD(8)) dut (
        .clk(clk), .rst_n(rst_n), .tx_valid(tx_valid), .tx_data(tx_data),
        .tx_ready(tx_ready), .tx_out(tx_out)
    );

    always #5 clk = ~clk;

    integer bit_i;
    reg [9:0] frame;
    integer errors = 0;

    initial begin
        $dumpfile("sim/tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        wait (tx_ready);
        @(negedge clk);
        tx_data = 8'hA5;
        tx_valid = 1;
        @(negedge clk);
        tx_valid = 0;

        // Wait for start bit
        wait (tx_out == 1'b0);
        // Mid of start
        repeat (4) @(posedge clk);
        frame[0] = tx_out;
        for (bit_i = 1; bit_i < 10; bit_i = bit_i + 1) begin
            repeat (8) @(posedge clk);
            frame[bit_i] = tx_out;
        end

        if (frame[0] !== 1'b0) begin $display("FAIL start"); errors=errors+1; end
        if (frame[8:1] !== 8'hA5) begin $display("FAIL data %02h", frame[8:1]); errors=errors+1; end
        if (frame[9] !== 1'b1) begin $display("FAIL stop"); errors=errors+1; end

        if (errors==0) $display("PASS: tb_uart_tx");
        else $display("FAIL: tb_uart_tx");
        $finish;
    end
endmodule
