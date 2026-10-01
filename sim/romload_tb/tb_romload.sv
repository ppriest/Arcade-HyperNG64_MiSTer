// SPDX-License-Identifier: GPL-3.0-or-later
//
// ROM loading end to end: the layout blob from rom index 1, the BIOS copy out of DDR3 into
// SDRAM, and the CPU reading it back through hng64_mainmem. Everything below the bench is the
// real stack - the vendored SDRAM controller and a chip model, and the DDR3 transport against
// the bench's model of MiSTer's DDRAM port.

module tb_romload (
    input  logic        clk,
    input  logic        reset,

    // the ioctl byte path, as hps_io drives it
    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,

    input  logic        ldr_start,
    output logic        ldr_active,
    output logic        ldr_done,
    output logic        cfg_valid,
    output logic [27:0] cfg_gameprg_base,
    output logic [27:0] cfg_bios_base,
    output logic [27:0] cfg_scrtile_base,
    output logic [27:0] cfg_scrtile_size,

    // the CPU's port
    input  logic        st_req,
    input  logic        st_we,
    input  logic [31:0] st_addr,
    input  logic  [2:0] st_beats,
    input  logic [63:0] st_wdata,
    input  logic  [7:0] st_be,
    output logic        st_rvalid,
    output logic [63:0] st_rdata,
    output logic        st_wdone,

    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,
    output logic        DDRAM_WE
);

    localparam int NREG = 6;

    logic [27:0] cfg_base [0:NREG-1];
    logic [27:0] cfg_size [0:NREG-1];

    assign cfg_gameprg_base = cfg_base[0];
    assign cfg_bios_base    = cfg_base[1];
    assign cfg_scrtile_base = cfg_base[2];
    assign cfg_scrtile_size = cfg_size[2];

    hng64_romcfg #(.N(NREG)) u_cfg (
        .clk(clk),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
        .base(cfg_base), .size(cfg_size), .flags(), .valid(cfg_valid));

    wire  [15:0] SDRAM_DQ;
    wire  [12:0] SDRAM_A;
    wire   [1:0] SDRAM_BA;
    wire         SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS;
    wire         SDRAM_CLK, SDRAM_CKE;

    logic [25:0] s_addr;
    logic        s_rd, s_we, s_ready, s_valid;
    logic [63:0] s_wdata, s_data;
    logic  [7:0] s_be;

    logic [24:0] ldr_daddr;
    logic [15:0] ldr_ddin;
    logic        ldr_dwe, d_ready;

    logic [27:0] m_addr, l_addr;
    logic        m_rd, m_ready, m_valid, l_rd, l_ready, l_valid;
    logic [63:0] c_data;

    logic [27:0] c_addr [0:1];
    logic        c_rd [0:1];
    logic        c_ready [0:1];
    logic        c_valid [0:1];

    always_comb begin
        c_addr[0] = m_addr;   c_rd[0] = m_rd;   m_ready = c_ready[0];   m_valid = c_valid[0];
        c_addr[1] = l_addr;   c_rd[1] = l_rd;   l_ready = c_ready[1];   l_valid = c_valid[1];
    end

    hng64_mainmem u_mem (
        .clk(clk), .reset(reset), .prg_base(cfg_base[0]),
        .st_req(st_req), .st_we(st_we), .st_addr(st_addr), .st_beats(st_beats),
        .st_wdata(st_wdata), .st_be(st_be),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .s_addr(s_addr), .s_rd(s_rd), .s_we(s_we), .s_wdata(s_wdata), .s_be(s_be),
        .s_ready(s_ready), .s_data(s_data), .s_valid(s_valid),
        .d_addr(m_addr), .d_rd(m_rd), .d_ready(m_ready), .d_data(c_data), .d_valid(m_valid));

    hng64_romload u_ldr (
        .clk(clk), .reset(reset),
        .start(ldr_start), .src_base(cfg_base[1]), .src_size(cfg_size[1]),
        .active(ldr_active), .done(ldr_done),
        .d_addr(l_addr), .d_rd(l_rd), .d_ready(l_ready), .d_data(c_data), .d_valid(l_valid),
        .s_addr(ldr_daddr), .s_din(ldr_ddin), .s_we(ldr_dwe), .s_ready(d_ready));

    hng64_sdram u_sdram (
        .clk(clk), .init(reset), .reset(reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .v_addr(17'd0), .v_rd(1'b0), .v_ready(), .v_data(), .v_valid(),
        .c_addr(s_addr), .c_rd(s_rd), .c_we(s_we), .c_wdata(s_wdata), .c_be(s_be),
        .c_ready(s_ready), .c_data(s_data), .c_valid(s_valid),
        .d_addr(ldr_daddr), .d_din(ldr_ddin), .d_we(ldr_dwe), .d_ready(d_ready));

    sdram_chip_model_wide #(.MB(32)) u_chip (
        .clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS));

    hng64_ddram #(.N(2)) u_ddr (
        .w_addr(29'd0), .w_din(64'd0), .w_be(8'd0), .w_valid(1'b0), .w_urgent(1'b0), .w_ready(),
        .clk(clk), .reset(reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(c_data), .c_valid(c_valid));

endmodule
