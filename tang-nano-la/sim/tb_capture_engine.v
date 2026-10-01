`timescale 1ns / 1ps
`default_nettype none

module tb_capture_engine;
    localparam CHANNELS = 8;
    localparam DEPTH    = 64;
    localparam ADDR_W   = $clog2(DEPTH);
    localparam COUNT_W  = 16;

    reg clk = 0;
    reg rst_n = 0;
    reg start = 0;
    reg abort = 0;
    reg sample_en = 1;
    reg [CHANNELS-1:0] sample = 0;
    reg triggered = 0;
    reg [COUNT_W-1:0] pre_samples = 8;
    reg [COUNT_W-1:0] post_samples = 16;
    reg [CHANNELS-1:0] channel_mask = 8'hFF;

    wire wr_en;
    wire [ADDR_W-1:0] wr_addr;
    wire [CHANNELS-1:0] wr_data;
    wire arm_trigger, busy, done;
    wire [ADDR_W-1:0] oldest_addr;
    wire [COUNT_W-1:0] total_samples;
    wire [2:0] state;

    reg [CHANNELS-1:0] mem [0:DEPTH-1];
    integer i;
    initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = 8'h00;
    // Sample write after NBA settle (wr_en/addr/data are registered outputs)
    always @(posedge clk) begin
        #1;
        if (wr_en)
            mem[wr_addr] = wr_data;
    end
    always #5 clk = ~clk;

    capture_engine #(
        .CHANNELS(CHANNELS), .DEPTH(DEPTH), .ADDR_W(ADDR_W), .COUNT_W(COUNT_W)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .abort(abort),
        .sample_en(sample_en), .sample(sample), .triggered(triggered),
        .pre_samples(pre_samples), .post_samples(post_samples),
        .channel_mask(channel_mask),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .arm_trigger(arm_trigger), .busy(busy), .done(done),
        .oldest_addr(oldest_addr), .total_samples(total_samples), .state(state)
    );

    integer errors = 0;
    integer n, k;
    reg [ADDR_W-1:0] a;
    reg [7:0] val, first;
    reg fired;

    initial begin
        $dumpfile("sim/tb_capture_engine.vcd");
        $dumpvars(0, tb_capture_engine);
        fired = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        @(negedge clk);
        start = 1;
        n = 0;
        sample = 0;
        triggered = 0;

        for (n = 1; n < 300; n = n + 1) begin
            @(negedge clk);
            sample = n[7:0];
            triggered = 0;
            if (arm_trigger && !fired && n >= 14) begin
                triggered = 1;
                fired = 1;
            end
            @(posedge clk);
            #2; // after DUT NBA and TB mem model update
            if (done) begin
                $display("done: oldest=%0d total=%0d trig_addr=%0d n=%0d",
                         oldest_addr, total_samples, dut.trig_addr, n);
                if (total_samples !== (pre_samples + post_samples)) begin
                    $display("FAIL: total=%0d expected %0d",
                             total_samples, pre_samples + post_samples);
                    errors = errors + 1;
                end
                a = oldest_addr;
                first = mem[a];
                for (k = 0; k < total_samples; k = k + 1) begin
                    val = mem[a];
                    if (val !== (first + k[7:0])) begin
                        $display("FAIL: idx %0d addr %0d got %0d expected %0d",
                                 k, a, val, first + k[7:0]);
                        errors = errors + 1;
                    end
                    a = a + 1'b1;
                end
                @(negedge clk);
                start = 0;
                @(posedge clk); #1;
                if (state !== 3'd0) begin
                    $display("FAIL: expected IDLE got %0d", state);
                    errors = errors + 1;
                end
                if (errors == 0) $display("PASS: tb_capture_engine");
                else $display("FAIL: tb_capture_engine (%0d errors)", errors);
                $finish;
            end
        end
        $display("FAIL: timeout");
        $finish;
    end
endmodule

`default_nettype wire
