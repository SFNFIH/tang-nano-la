// top.v
// Tang Nano 9K Logic Analyzer - phase 1 top level.

`timescale 1ns / 1ps
`default_nettype none

module top #(
    parameter CHANNELS     = 8,
    parameter DEPTH        = 16384,
    parameter CLK_IN_HZ    = 27_000_000,
    parameter CLK_SAMPLE_HZ= 99_000_000,
    parameter UART_BAUD    = 115200
) (
    input  wire                  clk_27m,
    input  wire [CHANNELS-1:0]   la_in,
    input  wire                  uart_rx,
    output wire                  uart_tx,
    output wire [5:0]            led
);

    localparam ADDR_W  = $clog2(DEPTH);
    localparam COUNT_W = 16;

    wire clk_sample;
    wire pll_locked;
    wire rst_n = pll_locked;

    clk_gen #(
        .CLK_IN_HZ(CLK_IN_HZ),
        .CLK_OUT_HZ(CLK_SAMPLE_HZ)
    ) u_clk_gen (
        .clk_in(clk_27m),
        .rst_n(1'b1),
        .clk_sample(clk_sample),
        .clk_locked(pll_locked)
    );

    // -------- config from host --------
    wire [15:0] sample_div;
    wire [CHANNELS-1:0] channel_mask;
    wire [$clog2(CHANNELS)-1:0] trigger_channel;
    wire [2:0] trigger_type;
    wire [CHANNELS-1:0] trig_pattern, trig_mask;
    wire [COUNT_W-1:0] pre_samples, post_samples;
    wire capt_start, capt_abort;

    // -------- sample path --------
    wire [CHANNELS-1:0] gpio_sync;
    input_sync #(.CHANNELS(CHANNELS)) u_input_sync (
        .clk(clk_sample),
        .rst_n(rst_n),
        .gpio_async(la_in),
        .gpio_sync(gpio_sync)
    );

    // Integer clock enable for sample_rate = CLK_SAMPLE_HZ / sample_div
    reg  [15:0] div_cnt;
    reg         sample_en;
    always @(posedge clk_sample or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt   <= 16'd0;
            sample_en <= 1'b0;
        end else begin
            if (div_cnt + 16'd1 >= sample_div) begin
                div_cnt   <= 16'd0;
                sample_en <= 1'b1;
            end else begin
                div_cnt   <= div_cnt + 16'd1;
                sample_en <= 1'b0;
            end
        end
    end

    wire triggered;
    wire arm_trigger;
    trigger_engine #(.CHANNELS(CHANNELS)) u_trigger (
        .clk(clk_sample),
        .rst_n(rst_n),
        .arm(arm_trigger),
        .sample(gpio_sync),
        .trigger_channel(trigger_channel),
        .trigger_type(trigger_type),
        .pattern(trig_pattern),
        .pattern_mask(trig_mask),
        .triggered(triggered)
    );

    wire wr_en;
    wire [ADDR_W-1:0] wr_addr;
    wire [CHANNELS-1:0] wr_data;
    wire capt_busy, capt_done;
    wire [ADDR_W-1:0] oldest_addr;
    wire [COUNT_W-1:0] total_samples;
    wire [2:0] capt_state;

    capture_engine #(
        .CHANNELS(CHANNELS),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .COUNT_W(COUNT_W)
    ) u_capture (
        .clk(clk_sample),
        .rst_n(rst_n),
        .start(capt_start),
        .abort(capt_abort),
        .sample_en(sample_en),
        .sample(gpio_sync),
        .triggered(triggered),
        .pre_samples(pre_samples),
        .post_samples(post_samples),
        .channel_mask(channel_mask),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .arm_trigger(arm_trigger),
        .busy(capt_busy),
        .done(capt_done),
        .oldest_addr(oldest_addr),
        .total_samples(total_samples),
        .state(capt_state)
    );

    wire ram_rd_en;
    wire [ADDR_W-1:0] ram_rd_addr;
    wire [CHANNELS-1:0] ram_rd_data;

    capture_ram #(
        .CHANNELS(CHANNELS),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W)
    ) u_ram (
        .wr_clk(clk_sample),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_clk(clk_sample),
        .rd_en(ram_rd_en),
        .rd_addr(ram_rd_addr),
        .rd_data(ram_rd_data)
    );

    // -------- UART --------
    wire rx_valid;
    wire [7:0] rx_data;
    wire tx_valid, tx_ready;
    wire [7:0] tx_data;

    uart_rx #(
        .CLK_HZ(CLK_SAMPLE_HZ),
        .BAUD(UART_BAUD)
    ) u_uart_rx (
        .clk(clk_sample),
        .rst_n(rst_n),
        .rx_in(uart_rx),
        .rx_valid(rx_valid),
        .rx_data(rx_data)
    );

    uart_tx #(
        .CLK_HZ(CLK_SAMPLE_HZ),
        .BAUD(UART_BAUD)
    ) u_uart_tx (
        .clk(clk_sample),
        .rst_n(rst_n),
        .tx_valid(tx_valid),
        .tx_data(tx_data),
        .tx_ready(tx_ready),
        .tx_out(uart_tx)
    );

    control_regs #(
        .CHANNELS(CHANNELS),
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .COUNT_W(COUNT_W)
    ) u_ctrl (
        .clk(clk_sample),
        .rst_n(rst_n),
        .rx_valid(rx_valid),
        .rx_data(rx_data),
        .tx_valid(tx_valid),
        .tx_data(tx_data),
        .tx_ready(tx_ready),
        .sample_div(sample_div),
        .channel_mask(channel_mask),
        .trigger_channel(trigger_channel),
        .trigger_type(trigger_type),
        .trig_pattern(trig_pattern),
        .trig_mask(trig_mask),
        .pre_samples(pre_samples),
        .post_samples(post_samples),
        .capt_start(capt_start),
        .capt_abort(capt_abort),
        .capt_busy(capt_busy),
        .capt_done(capt_done),
        .capt_armed(arm_trigger),
        .capt_state(capt_state),
        .oldest_addr(oldest_addr),
        .total_samples(total_samples),
        .pll_locked(pll_locked),
        .ram_rd_en(ram_rd_en),
        .ram_rd_addr(ram_rd_addr),
        .ram_rd_data(ram_rd_data)
    );

    // -------- Onboard LEDs (active-low) --------
    // Idle : LED0=PLL lock, LED3=done, LED5=heartbeat
    // Busy : 6-LED chase ("流水灯") while sampling (PRE/POST)
    reg [24:0] hb;
    reg [22:0] chase_div;
    reg [5:0]  chase_pat;

    localparam [22:0] CHASE_TICK = 23'd2_500_000; // ~25 ms @ 99 MHz

    always @(posedge clk_sample or negedge rst_n) begin
        if (!rst_n) begin
            hb        <= 25'd0;
            chase_div <= 23'd0;
            chase_pat <= 6'b000001;
        end else begin
            hb <= hb + 25'd1;

            if (capt_busy) begin
                if (chase_div == 23'd0) begin
                    chase_div <= CHASE_TICK;
                    // rotate left through 6 LEDs
                    chase_pat <= {chase_pat[4:0], chase_pat[5]};
                end else begin
                    chase_div <= chase_div - 23'd1;
                end
            end else begin
                chase_div <= 23'd0;
                chase_pat <= 6'b000001;
            end
        end
    end

    wire [5:0] led_idle = {
        ~hb[24],       // LED5 heartbeat
        1'b1,          // LED4 off
        ~capt_done,    // LED3 done
        1'b1,          // LED2 off
        1'b1,          // LED1 off
        ~pll_locked    // LED0 PLL locked
    };

    // capt_busy: drive active-low chase pattern
    assign led = capt_busy ? ~chase_pat : led_idle;

endmodule

`default_nettype wire
