`timescale 1ns / 1ps
`define SIMULATION
`default_nettype none

module tb_top;
    localparam CHANNELS = 8;
    localparam DEPTH = 256;

    reg clk_27m = 0;
    reg [CHANNELS-1:0] la_in = 0;
    reg uart_rx = 1;
    wire uart_tx;
    wire [5:0] led;

    always #20 clk_27m = ~clk_27m;

    top #(
        .CHANNELS(CHANNELS),
        .DEPTH(DEPTH),
        .CLK_IN_HZ(27_000_000),
        .CLK_SAMPLE_HZ(100_000_000),
        .UART_BAUD(10_000_000)
    ) dut (
        .clk_27m(clk_27m),
        .la_in(la_in),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led)
    );

    integer errors = 0;
    localparam BIT_CLKS = 10; // sample-clk cycles / bit

    task uart_send_byte;
        input [7:0] b;
        integer k;
        begin
            uart_rx = 0;
            #(BIT_CLKS * 10);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx = b[k];
                #(BIT_CLKS * 10);
            end
            uart_rx = 1;
            #(BIT_CLKS * 10);
        end
    endtask

    task uart_send_frame;
        input [7:0] cmd;
        input [15:0] len;
        input [127:0] pl;
        integer k;
        reg [7:0] c;
        begin
            c = cmd ^ len[7:0] ^ len[15:8];
            for (k = 0; k < len; k = k + 1)
                c = c ^ pl[k*8 +: 8];
            uart_send_byte(8'hA5);
            uart_send_byte(cmd);
            uart_send_byte(len[7:0]);
            uart_send_byte(len[15:8]);
            for (k = 0; k < len; k = k + 1)
                uart_send_byte(pl[k*8 +: 8]);
            uart_send_byte(c);
        end
    endtask

    reg [7:0] rx_bytes [0:1023];
    integer rx_count;
    integer bi;
    reg [7:0] cur;
    initial rx_count = 0;

    initial begin
        forever begin
            @(negedge uart_tx);
            // center of bit0 = 1.5 bit times from start edge
            #(BIT_CLKS*10 + (BIT_CLKS*10)/2);
            cur = 0;
            for (bi = 0; bi < 8; bi = bi + 1) begin
                cur[bi] = uart_tx;
                if (bi != 7)
                    #(BIT_CLKS*10);
            end
            // do not burn the stop/next-start period; wait for next negedge
            rx_bytes[rx_count] = cur;
            rx_count = rx_count + 1;
        end
    end

    reg [127:0] payload;

    initial begin
        $dumpfile("sim/tb_top.vcd");
        $dumpvars(0, tb_top);

        wait (dut.pll_locked == 1);
        repeat (50) @(posedge dut.clk_sample);
        rx_count = 0;

        // CFG_TRIG channel=0 type=rising
        payload = 128'h0;
        payload[7:0]   = 8'h00;
        payload[15:8]  = 8'h00;
        payload[23:16] = 8'h00;
        payload[31:24] = 8'h00;
        payload[39:32] = 8'hFF;
        payload[47:40] = 8'h00;
        uart_send_frame(8'h05, 16'd6, payload);
        #20000;
        if (rx_count < 5 || rx_bytes[1] !== 8'h00) begin
            $display("FAIL: CFG_TRIG resp (count=%0d b1=%02h)", rx_count, rx_bytes[1]);
            errors = errors + 1;
        end else $display("OK CFG_TRIG ACK");

        // CFG_CAPT: div=1, mask=FF, pre=16, post=32
        rx_count = 0;
        payload = 128'h0;
        payload[7:0]   = 8'h01;
        payload[15:8]  = 8'h00;
        payload[23:16] = 8'hFF;
        payload[31:24] = 8'h00;
        payload[39:32] = 8'd16;
        payload[47:40] = 8'h00;
        payload[55:48] = 8'd32;
        payload[63:56] = 8'h00;
        uart_send_frame(8'h06, 16'd8, payload);
        #20000;
        if (rx_count < 5 || rx_bytes[1] !== 8'h00) begin
            $display("FAIL: CFG_CAPT resp");
            errors = errors + 1;
        end else $display("OK CFG_CAPT ACK");

        // START
        rx_count = 0;
        uart_send_frame(8'h01, 16'd0, 128'h0);
        #20000;
        if (rx_count < 5 || rx_bytes[1] !== 8'h00) begin
            $display("FAIL: START resp");
            errors = errors + 1;
        end else $display("OK START ACK");

        wait (dut.arm_trigger == 1);
        @(negedge dut.clk_sample);
        la_in = 8'h00;
        repeat (4) @(posedge dut.clk_sample);
        @(negedge dut.clk_sample);
        la_in = 8'h01;
        wait (dut.capt_done == 1);
        $display("OK capture done total=%0d oldest=%0d", dut.total_samples, dut.oldest_addr);

        if (dut.total_samples !== 16'd48) begin
            $display("FAIL: total %0d expected 48", dut.total_samples);
            errors = errors + 1;
        end

        // STATUS
        rx_count = 0;
        uart_send_frame(8'h03, 16'd0, 128'h0);
        #50000;
        if (rx_count < 5 || rx_bytes[1] !== 8'h83) begin
            $display("FAIL: STATUS resp %02h count=%0d", rx_bytes[1], rx_count);
            errors = errors + 1;
        end else $display("OK STATUS");

        if (errors == 0) $display("PASS: tb_top");
        else $display("FAIL: tb_top (%0d errors)", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule

`default_nettype wire
