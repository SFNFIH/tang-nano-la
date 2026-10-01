`timescale 1ns / 1ps
`default_nettype none

module tb_trigger_engine;
    localparam CHANNELS = 8;
    reg clk = 0;
    reg rst_n = 0;
    reg arm = 0;
    reg [CHANNELS-1:0] sample = 0;
    reg [$clog2(CHANNELS)-1:0] trigger_channel = 0;
    reg [2:0] trigger_type = 0;
    reg [CHANNELS-1:0] pattern = 0;
    reg [CHANNELS-1:0] pattern_mask = 8'hFF;
    wire triggered;

    always #5 clk = ~clk;

    trigger_engine #(.CHANNELS(CHANNELS)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .arm(arm),
        .sample(sample),
        .trigger_channel(trigger_channel),
        .trigger_type(trigger_type),
        .pattern(pattern),
        .pattern_mask(pattern_mask),
        .triggered(triggered)
    );

    integer errors = 0;

    task expect_pulse_within;
        input integer max_cycles;
        integer i;
        reg saw;
        begin
            saw = 0;
            for (i = 0; i < max_cycles; i = i + 1) begin
                @(posedge clk);
                #1; // allow NBA to settle
                if (triggered) saw = 1;
            end
            if (!saw) begin
                $display("FAIL: expected trigger pulse");
                errors = errors + 1;
            end
        end
    endtask

    task expect_no_pulse;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
                #1;
                if (triggered) begin
                    $display("FAIL: unexpected trigger");
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_trigger_engine.vcd");
        $dumpvars(0, tb_trigger_engine);

        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Rising edge on channel 3
        trigger_channel = 3;
        trigger_type = 3'd0; // rising
        @(negedge clk);
        sample = 8'h00;
        arm = 1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        sample = 8'h08; // bit3 rise
        expect_pulse_within(3);

        @(negedge clk);
        arm = 0;
        sample = 8'h08;
        trigger_type = 3'd1;
        @(negedge clk);
        arm = 1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        sample = 8'h00; // falling
        expect_pulse_within(3);

        // Level high: already high should fire while armed
        @(negedge clk);
        arm = 0;
        sample = 8'h08;
        trigger_type = 3'd2;
        @(negedge clk);
        arm = 1;
        expect_pulse_within(4);

        // Pattern: look for 0xA5 on masked bits
        @(negedge clk);
        arm = 0;
        trigger_type = 3'd4;
        pattern = 8'hA5;
        pattern_mask = 8'hFF;
        sample = 8'h00;
        @(negedge clk);
        arm = 1;
        expect_no_pulse(2);
        @(negedge clk);
        sample = 8'hA5;
        expect_pulse_within(3);

        if (errors == 0)
            $display("PASS: tb_trigger_engine");
        else
            $display("FAIL: tb_trigger_engine (%0d errors)", errors);
        $finish;
    end
endmodule

`default_nettype wire
