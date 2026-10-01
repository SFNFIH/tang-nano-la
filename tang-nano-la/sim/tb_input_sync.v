`timescale 1ns / 1ps
`default_nettype none

module tb_input_sync;
    localparam CHANNELS = 8;
    reg clk = 0;
    reg rst_n = 0;
    reg [CHANNELS-1:0] gpio_async = 0;
    wire [CHANNELS-1:0] gpio_sync;

    always #5 clk = ~clk; // 100 MHz

    input_sync #(.CHANNELS(CHANNELS)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .gpio_async(gpio_async),
        .gpio_sync(gpio_sync)
    );

    integer errors = 0;

    initial begin
        $dumpfile("sim/tb_input_sync.vcd");
        $dumpvars(0, tb_input_sync);

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Change async input mid-cycle; sync output must lag by 2 clocks
        gpio_async = 8'hA5;
        @(posedge clk);
        if (gpio_sync !== 8'h00) begin
            $display("FAIL: expected 00 after 1 clk, got %02h", gpio_sync);
            errors = errors + 1;
        end
        @(posedge clk);
        if (gpio_sync !== 8'hA5) begin
            $display("FAIL: expected A5 after 2 clks, got %02h", gpio_sync);
            errors = errors + 1;
        end

        gpio_async = 8'h00;
        repeat (2) @(posedge clk);
        if (gpio_sync !== 8'h00) begin
            $display("FAIL: expected clear, got %02h", gpio_sync);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: tb_input_sync");
        else
            $display("FAIL: tb_input_sync (%0d errors)", errors);
        $finish;
    end
endmodule

`default_nettype wire
