// SPDX-License-Identifier: GPL-3.0-or-later
//
// The CPU's backing store against real memory: hng64_mainmem over hng64_sdram (with the
// vendored controller and a chip model) and hng64_ddram (with the bench's model of the DDRAM
// port). sim/mainmem_tb/main.cpp fills both and checks every beat.

module tb_mainmem (
    input  logic        clk,
    input  logic        reset,

    input  logic        st_req,
    input  logic        st_we,
    input  logic [31:0] st_addr,
    input  logic  [2:0] st_beats,
    input  logic [63:0] st_wdata,
    input  logic  [7:0] st_be,
    output logic        st_rvalid,
    output logic [63:0] st_rdata,
    output logic        st_wdone,

    input  logic [24:0] d_addr,
    input  logic [15:0] d_din,
    input  logic        d_we,
    output logic        d_ready,

    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,
    output logic        DDRAM_WE,
    output logic  [1:0] dbg_mst,
    output logic  [1:0] dbg_cst,
    output logic        dbg_sready
);

    assign dbg_mst = u_mem.st;
    assign dbg_cst = u_sdram.cst;
    assign dbg_sready = s_ready;

    wire  [15:0] SDRAM_DQ;
    wire  [12:0] SDRAM_A;
    wire   [1:0] SDRAM_BA;
    wire         SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS;
    wire         SDRAM_CLK, SDRAM_CKE;

    logic [25:0] s_addr;
    logic        s_rd, s_we, s_ready, s_valid;
    logic [63:0] s_wdata, s_data;
    logic  [7:0] s_be;

    logic [27:0] m_addr;
    logic        m_rd, m_ready, m_valid;
    logic [63:0] m_data;

    logic [27:0] c_addr [0:0];
    logic        c_rd [0:0];
    logic        c_ready [0:0];
    logic        c_valid [0:0];

    always_comb begin
        c_addr[0] = m_addr;
        c_rd[0]   = m_rd;
        m_ready   = c_ready[0];
        m_valid   = c_valid[0];
    end

    hng64_mainmem u_mem (
        .clk(clk), .reset(reset), .prg_base(28'd0),
        .st_req(st_req), .st_we(st_we), .st_addr(st_addr), .st_beats(st_beats),
        .st_wdata(st_wdata), .st_be(st_be),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .s_addr(s_addr), .s_rd(s_rd), .s_we(s_we), .s_wdata(s_wdata), .s_be(s_be),
        .s_ready(s_ready), .s_data(s_data), .s_valid(s_valid),
        .d_addr(m_addr), .d_rd(m_rd), .d_ready(m_ready), .d_data(m_data), .d_valid(m_valid));

    hng64_sdram u_sdram (
        .clk(clk), .init(reset), .reset(reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .v_addr(17'd0), .v_rd(1'b0), .v_ready(), .v_data(), .v_valid(),
        .c_addr(s_addr), .c_rd(s_rd), .c_we(s_we), .c_wdata(s_wdata), .c_be(s_be),
        .c_ready(s_ready), .c_data(s_data), .c_valid(s_valid),
        .d_addr(d_addr), .d_din(d_din), .d_we(d_we), .d_ready(d_ready));

    sdram_chip_model_wide #(.MB(32)) u_chip (
        .clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS));

    hng64_ddram #(.N(1)) u_ddr (
        .w_addr(29'd0), .w_din(64'd0), .w_be(8'd0), .w_valid(1'b0), .w_urgent(1'b0), .w_ready(),
        .clk(clk), .reset(reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(m_data), .c_valid(c_valid));

endmodule
