// control_regs.v
// Host binary protocol + configuration / status registers.
//
// Host -> FPGA:  A5 | CMD | LEN_L | LEN_H | PAYLOAD[LEN] | CHK
// FPGA -> Host:  5A | RESP | LEN_L | LEN_H | PAYLOAD[LEN] | CHK
// CHK = XOR(CMD/RESP .. last payload byte)

`timescale 1ns / 1ps
`default_nettype none

module control_regs #(
    parameter CHANNELS = 8,
    parameter DEPTH    = 16384,
    parameter ADDR_W   = $clog2(DEPTH),
    parameter COUNT_W  = 16
) (
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        rx_valid,
    input  wire [7:0]                  rx_data,
    output reg                         tx_valid,
    output reg  [7:0]                  tx_data,
    input  wire                        tx_ready,

    output reg  [15:0]                 sample_div,
    output reg  [CHANNELS-1:0]         channel_mask,
    output reg  [$clog2(CHANNELS)-1:0] trigger_channel,
    output reg  [2:0]                  trigger_type,
    output reg  [CHANNELS-1:0]         trig_pattern,
    output reg  [CHANNELS-1:0]         trig_mask,
    output reg  [COUNT_W-1:0]          pre_samples,
    output reg  [COUNT_W-1:0]          post_samples,

    output reg                         capt_start,
    output reg                         capt_abort,

    input  wire                        capt_busy,
    input  wire                        capt_done,
    input  wire                        capt_armed,
    input  wire [2:0]                  capt_state,
    input  wire [ADDR_W-1:0]           oldest_addr,
    input  wire [COUNT_W-1:0]          total_samples,
    input  wire                        pll_locked,

    output reg                         ram_rd_en,
    output reg  [ADDR_W-1:0]           ram_rd_addr,
    input  wire [CHANNELS-1:0]         ram_rd_data
);

    localparam CMD_START    = 8'h01;
    localparam CMD_STOP     = 8'h02;
    localparam CMD_STATUS   = 8'h03;
    localparam CMD_READ     = 8'h04;
    localparam CMD_CFG_TRIG = 8'h05;
    localparam CMD_CFG_CAPT = 8'h06;

    localparam RESP_ACK     = 8'h00;
    localparam RESP_NAK     = 8'h01;
    localparam RESP_STATUS  = 8'h83;
    localparam RESP_DATA    = 8'h84;

    localparam RX_MAGIC = 8'hA5;
    localparam TX_MAGIC = 8'h5A;

    localparam RS_MAGIC = 3'd0;
    localparam RS_CMD   = 3'd1;
    localparam RS_LENL  = 3'd2;
    localparam RS_LENH  = 3'd3;
    localparam RS_PL    = 3'd4;
    localparam RS_CHK   = 3'd5;

    localparam TS_IDLE  = 4'd0;
    localparam TS_MAGIC = 4'd1;
    localparam TS_RESP  = 4'd2;
    localparam TS_LENL  = 4'd3;
    localparam TS_LENH  = 4'd4;
    localparam TS_PL    = 4'd5;
    localparam TS_CHK   = 4'd6;
    localparam TS_RAM0  = 4'd7; // issue read
    localparam TS_RAM1  = 4'd8; // data valid

    reg [2:0]  rs;
    reg [7:0]  cmd;
    reg [15:0] len;
    reg [15:0] pl_idx;
    reg [7:0]  chk;
    reg [7:0]  payload [0:15];
    reg        frame_go;

    reg [3:0]  ts;
    reg [7:0]  resp;
    reg [15:0] tx_len;
    reg [15:0] tx_idx;
    reg [7:0]  tx_chk;
    reg [7:0]  tx_buf [0:15];

    reg        streaming;
    reg [ADDR_W-1:0] stream_base;
    reg [15:0] stream_count;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rs <= RS_MAGIC;
            cmd <= 8'd0;
            len <= 16'd0;
            pl_idx <= 16'd0;
            chk <= 8'd0;
            frame_go <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                payload[i] <= 8'd0;
                tx_buf[i] <= 8'd0;
            end

            ts <= TS_IDLE;
            tx_valid <= 1'b0;
            tx_data <= 8'd0;
            resp <= 8'd0;
            tx_len <= 16'd0;
            tx_idx <= 16'd0;
            tx_chk <= 8'd0;
            streaming <= 1'b0;
            stream_base <= {ADDR_W{1'b0}};
            stream_count <= 16'd0;

            sample_div <= 16'd1;
            channel_mask <= {CHANNELS{1'b1}};
            trigger_channel <= {($clog2(CHANNELS)){1'b0}};
            trigger_type <= 3'd0;
            trig_pattern <= {CHANNELS{1'b0}};
            trig_mask <= {CHANNELS{1'b1}};
            pre_samples <= 16'd4096;
            post_samples <= 16'd8192;
            capt_start <= 1'b0;
            capt_abort <= 1'b0;
            ram_rd_en <= 1'b0;
            ram_rd_addr <= {ADDR_W{1'b0}};
        end else begin
            frame_go   <= 1'b0;
            capt_abort <= 1'b0;
            ram_rd_en  <= 1'b0;

            if (tx_valid && tx_ready)
                tx_valid <= 1'b0;

            // ---------------- RX parser ----------------
            if (rx_valid) begin
                case (rs)
                    RS_MAGIC: if (rx_data == RX_MAGIC) rs <= RS_CMD;
                    RS_CMD: begin
                        cmd <= rx_data;
                        chk <= rx_data;
                        rs  <= RS_LENL;
                    end
                    RS_LENL: begin
                        len[7:0] <= rx_data;
                        chk <= chk ^ rx_data;
                        rs  <= RS_LENH;
                    end
                    RS_LENH: begin
                        len[15:8] <= rx_data;
                        chk <= chk ^ rx_data;
                        pl_idx <= 16'd0;
                        if ({rx_data, len[7:0]} == 16'd0)
                            rs <= RS_CHK;
                        else
                            rs <= RS_PL;
                    end
                    RS_PL: begin
                        if (pl_idx < 16)
                            payload[pl_idx[3:0]] <= rx_data;
                        chk <= chk ^ rx_data;
                        if ((pl_idx + 16'd1) >= len)
                            rs <= RS_CHK;
                        pl_idx <= pl_idx + 16'd1;
                    end
                    RS_CHK: begin
                        rs <= RS_MAGIC;
                        if (rx_data == chk)
                            frame_go <= 1'b1;
                        else if (ts == TS_IDLE)
                            begin resp <= RESP_NAK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_NAK; ts <= TS_MAGIC; end
                    end
                    default: rs <= RS_MAGIC;
                endcase
            end

            // ---------------- Command dispatch ----------------
            if (frame_go && ts == TS_IDLE) begin
                case (cmd)
                    CMD_START: begin
                        capt_start <= 1'b1;
                        begin resp <= RESP_ACK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_ACK; ts <= TS_MAGIC; end
                    end
                    CMD_STOP: begin
                        capt_start <= 1'b0;
                        capt_abort <= 1'b1;
                        begin resp <= RESP_ACK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_ACK; ts <= TS_MAGIC; end
                    end
                    CMD_STATUS: begin
                        tx_buf[0] <= {pll_locked, capt_armed, capt_busy, capt_done, 4'b0};
                        tx_buf[1] <= {5'b0, capt_state};
                        tx_buf[2] <= total_samples[7:0];
                        tx_buf[3] <= total_samples[15:8];
                        tx_buf[4] <= oldest_addr[7:0];
                        tx_buf[5] <= (ADDR_W > 8) ? oldest_addr >> 8 : 8'd0;
                        tx_buf[6] <= sample_div[7:0];
                        tx_buf[7] <= sample_div[15:8];
                        tx_buf[8] <= channel_mask | 8'h00;
                        tx_buf[9] <= 8'd0;
                        begin resp <= RESP_STATUS; tx_len <= 16'd10; tx_idx <= 16'd0; tx_chk <= RESP_STATUS; ts <= TS_MAGIC; end
                    end
                    CMD_CFG_TRIG: begin
                        if (len >= 16'd6) begin
                            trigger_channel <= payload[0][$clog2(CHANNELS)-1:0];
                            trigger_type    <= payload[1][2:0];
                            trig_pattern    <= payload[2][CHANNELS-1:0];
                            trig_mask       <= payload[4][CHANNELS-1:0];
                            begin resp <= RESP_ACK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_ACK; ts <= TS_MAGIC; end
                        end else begin resp <= RESP_NAK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_NAK; ts <= TS_MAGIC; end
                    end
                    CMD_CFG_CAPT: begin
                        if (len >= 16'd8) begin
                            sample_div   <= ({payload[1], payload[0]} == 16'd0) ? 16'd1 : {payload[1], payload[0]};
                            channel_mask <= payload[2][CHANNELS-1:0];
                            pre_samples  <= {payload[5], payload[4]};
                            post_samples <= {payload[7], payload[6]};
                            begin resp <= RESP_ACK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_ACK; ts <= TS_MAGIC; end
                        end else begin resp <= RESP_NAK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_NAK; ts <= TS_MAGIC; end
                    end
                    CMD_READ: begin
                        if (len >= 16'd4 && capt_done && !capt_busy) begin
                            stream_base  <= {payload[1], payload[0]}; // low ADDR_W bits used
                            stream_count <= {payload[3], payload[2]};
                            streaming    <= 1'b1;
                            begin resp <= RESP_DATA; tx_len <= {payload[3], payload[2]}; tx_idx <= 16'd0; tx_chk <= RESP_DATA; ts <= TS_MAGIC; end
                        end else begin resp <= RESP_NAK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_NAK; ts <= TS_MAGIC; end
                    end
                    default: begin resp <= RESP_NAK; tx_len <= 16'd0; tx_idx <= 16'd0; tx_chk <= RESP_NAK; ts <= TS_MAGIC; end
                endcase
            end

            // ---------------- TX engine ----------------
            if (!tx_valid) begin
                case (ts)
                    TS_MAGIC: begin
                        tx_data  <= TX_MAGIC;
                        tx_valid <= 1'b1;
                        ts       <= TS_RESP;
                    end
                    TS_RESP: begin
                        tx_data  <= resp;
                        tx_valid <= 1'b1;
                        tx_chk   <= resp;
                        ts       <= TS_LENL;
                    end
                    TS_LENL: begin
                        tx_data  <= tx_len[7:0];
                        tx_valid <= 1'b1;
                        tx_chk   <= tx_chk ^ tx_len[7:0];
                        ts       <= TS_LENH;
                    end
                    TS_LENH: begin
                        tx_data  <= tx_len[15:8];
                        tx_valid <= 1'b1;
                        tx_chk   <= tx_chk ^ tx_len[15:8];
                        tx_idx   <= 16'd0;
                        if (tx_len == 16'd0)
                            ts <= TS_CHK;
                        else if (streaming)
                            ts <= TS_RAM0;
                        else
                            ts <= TS_PL;
                    end
                    TS_PL: begin
                        tx_data  <= tx_buf[tx_idx[3:0]];
                        tx_valid <= 1'b1;
                        tx_chk   <= tx_chk ^ tx_buf[tx_idx[3:0]];
                        if (tx_idx + 16'd1 >= tx_len)
                            ts <= TS_CHK;
                        tx_idx <= tx_idx + 16'd1;
                    end
                    TS_RAM0: begin
                        ram_rd_en   <= 1'b1;
                        ram_rd_addr <= stream_base + tx_idx[ADDR_W-1:0];
                        ts          <= TS_RAM1;
                    end
                    TS_RAM1: begin
                        tx_data  <= {{(8-CHANNELS){1'b0}}, ram_rd_data};
                        tx_valid <= 1'b1;
                        tx_chk   <= tx_chk ^ {{(8-CHANNELS){1'b0}}, ram_rd_data};
                        if (tx_idx + 16'd1 >= tx_len) begin
                            streaming <= 1'b0;
                            ts <= TS_CHK;
                        end else begin
                            ts <= TS_RAM0;
                        end
                        tx_idx <= tx_idx + 16'd1;
                    end
                    TS_CHK: begin
                        tx_data    <= tx_chk;
                        tx_valid   <= 1'b1;
                        streaming  <= 1'b0;
                        ts         <= TS_IDLE;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
