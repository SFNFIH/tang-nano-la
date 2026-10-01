/**
 * PLL configuration for Tang Nano 9K (GW1NR-9C)
 * 27.000 MHz -> 99.000 MHz
 * Fout = Fin * (FBDIV_SEL+1) / (IDIV_SEL+1) = 27 * 11 / 3 = 99
 */
`ifndef SIMULATION
module gowin_pll_99 (
    input  clock_in,
    output clock_out,
    output locked
);

    wire clkoutp_o;
    wire clkoutd_o;
    wire clkoutd3_o;
    wire gw_gnd;

    assign gw_gnd = 1'b0;

    rPLL rpll_inst (
        .CLKOUT(clock_out),
        .LOCK(locked),
        .CLKOUTP(clkoutp_o),
        .CLKOUTD(clkoutd_o),
        .CLKOUTD3(clkoutd3_o),
        .RESET(gw_gnd),
        .RESET_P(gw_gnd),
        .CLKIN(clock_in),
        .CLKFB(gw_gnd),
        .FBDSEL(6'b000000),
        .IDSEL(6'b000000),
        .ODSEL(6'b000000),
        .PSDA(4'b0000),
        .DUTYDA(4'b0000),
        .FDLY(4'b0000)
    );

    defparam rpll_inst.FCLKIN = "27";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 2;
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 10;
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 8;
    defparam rpll_inst.PSDA_SEL = "0000";
    defparam rpll_inst.DYN_DA_EN = "false";
    defparam rpll_inst.DUTYDA_SEL = "1000";
    defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
    defparam rpll_inst.CLKFB_SEL = "internal";
    defparam rpll_inst.CLKOUT_BYPASS = "false";
    defparam rpll_inst.CLKOUTP_BYPASS = "false";
    defparam rpll_inst.CLKOUTD_BYPASS = "false";
    defparam rpll_inst.DYN_SDIV_SEL = 2;
    defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
    defparam rpll_inst.DEVICE = "GW1N-9C";

endmodule
`endif
