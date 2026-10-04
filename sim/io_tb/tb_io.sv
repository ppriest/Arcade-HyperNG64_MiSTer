// SPDX-License-Identifier: GPL-3.0-or-later
//
// The main CPU's I/O devices against MAME's bus trace, with the DMA running through the real
// backing store: hng64_mainmem, the vendored SDRAM controller and a chip model, and the DDR3
// transport against the bench's model of the DDRAM port. The video port and the MCU's side of the
// dual-port RAM are served by sim/io_tb/main.cpp.

module tb_io (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        reset,

    input  logic        io_req,
    input  logic        io_we,
    input  logic [31:0] io_addr,
    input  logic  [3:0] io_be,
    input  logic [31:0] io_wdata,
    output logic        io_ack,
    output logic [31:0] io_rdata,

    input  logic        vblank,
    input  logic [55:0] rtc,
    output logic        cpu_irq,
    output logic        mcu_int0,

    output logic [10:0] dp_addr,
    output logic        dp_we,
    output logic  [7:0] dp_wdata,
    input  logic  [7:0] dp_rdata,

    output logic        v_req,
    output logic        v_we,
    output logic  [2:0] v_sel,
    output logic [13:0] v_addr,
    output logic  [3:0] v_be,
    output logic [31:0] v_wdata,
    input  logic        v_ack,
    input  logic [31:0] v_rdata,

    // the DMA's writes, as they reach the backing store
    output logic        dma_active,
    output logic        dma_st_req,
    output logic        dma_st_we,
    output logic [31:0] dma_st_addr,
    output logic [63:0] dma_st_wdata,
    output logic  [7:0] dma_st_be,
    output logic        dma_err,

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

    logic [31:0] dma_src, dma_dst, dma_count;
    logic        dma_go, dma_done;

    hng64_io u_io (
        .clk(clk1x), .reset(reset),
        .io_req(io_req), .io_we(io_we), .io_addr(io_addr), .io_be(io_be), .io_wdata(io_wdata),
        .io_ack(io_ack), .io_rdata(io_rdata),
        .cpu_irq(cpu_irq),
        .vblank_irq(1'b0), .raster_irq(1'b0), .net_irq(1'b0), .raster_pos(), .vblank(vblank),
        .mcu_int0(mcu_int0),
        .dp_addr(dp_addr), .dp_we(dp_we), .dp_wdata(dp_wdata), .dp_rdata(dp_rdata),
        .mcu_irq(1'b0),
        .rtc(rtc),
        .nv_addr(14'd0), .nv_we(1'b0), .nv_wdata(8'd0), .nv_rdata(), .nv_written(),
        .dma_src(dma_src), .dma_dst(dma_dst), .dma_count(dma_count),
        .dma_go(dma_go), .dma_done(dma_done),
        .v_req(v_req), .v_we(v_we), .v_sel(v_sel), .v_addr(v_addr), .v_be(v_be),
        .v_wdata(v_wdata), .v_ack(v_ack), .v_rdata(v_rdata),
        .fbcontrol(), .fbscroll(), .texwrap(),
        .dl_we(), .dl_addr(), .dl_be(), .dl_wdata(), .dl_up(),
        .dl_busy(1'b0), .dl_upbusy(1'b0), .dl_full(1'b0),
        .snd_main0(), .snd_main1(), .snd_irq(), .snd_en(), .snd_en_cmd(), .snd_live(1'b0),
        .snd_rep0(16'd0), .snd_rep1(16'd0),
        .dbg_mcu_en_0c(), .dbg_irq_pending(), .dbg_irq_level(),
        .dbg_rd(1'b0), .dbg_sel(3'd0), .dbg_addr(14'd0), .dbg_rdone(), .dbg_rdata());

    logic        st_rvalid, st_wdone;
    logic [63:0] st_rdata;
    logic  [2:0] dma_st_beats;

    hng64_dma u_dma (
        .clk(clk2x), .reset(reset),
        .src(dma_src), .dst(dma_dst), .count(dma_count), .go(dma_go), .done(dma_done),
        .active(dma_active),
        .st_req(dma_st_req), .st_we(dma_st_we), .st_addr(dma_st_addr), .st_beats(dma_st_beats),
        .st_wdata(dma_st_wdata), .st_be(dma_st_be),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .err_nonstore(dma_err));

    // ---- the backing store, as in sim/mainmem_tb ------------------------------------------------
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
        .clk(clk2x), .reset(reset), .prg_base(28'd0),
        .st_req(dma_st_req), .st_we(dma_st_we), .st_addr(dma_st_addr), .st_beats(dma_st_beats),
        .st_wdata(dma_st_wdata), .st_be(dma_st_be),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .s_addr(s_addr), .s_rd(s_rd), .s_we(s_we), .s_wdata(s_wdata), .s_be(s_be),
        .s_ready(s_ready), .s_data(s_data), .s_valid(s_valid),
        .d_addr(m_addr), .d_rd(m_rd), .d_ready(m_ready), .d_data(m_data), .d_valid(m_valid));

    hng64_sdram u_sdram (
        .clk(clk2x), .init(reset), .reset(reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .v_addr(17'd0), .v_rd(1'b0), .v_ready(), .v_data(), .v_valid(),
        .c_addr(s_addr), .c_rd(s_rd), .c_we(s_we), .c_wdata(s_wdata), .c_be(s_be),
        .c_ready(s_ready), .c_data(s_data), .c_valid(s_valid),
        .d_addr(25'd0), .d_din(16'd0), .d_we(1'b0), .d_ready());

    sdram_chip_model_wide #(.MB(32)) u_chip (
        .clk(clk2x), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS));

    hng64_ddram #(.N(1)) u_ddr (
        .w_addr(29'd0), .w_din(64'd0), .w_be(8'd0), .w_valid(1'b0), .w_urgent(1'b0), .w_ready(),
        .clk(clk2x), .reset(reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(m_data), .c_valid(c_valid));

endmodule
