// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_3d behind hng64_ddram, as hng64_core connects them: sim/g3d_tb/main.cpp plays
// a capture's display-list events in through the CPU side and serves the DDRAM port. Arrays are
// packed here for the C++ side.

module tb_g3d (
    input  logic         clk1x,
    input  logic         clk2x,
    input  logic         reset,

    input  logic         dl_we,
    input  logic   [6:0] dl_addr,
    input  logic   [3:0] dl_be,
    input  logic  [31:0] dl_wdata,
    input  logic         dl_up,
    output logic         dl_busy,
    output logic         dl_upbusy,
    output logic         dl_full,
    input  logic [255:0] texwrap,           // byte k at bits 8k+7:8k
    input  logic         vblank,
    input  logic         clear_en,

    input  logic         samsho,
    input  logic  [27:0] vert_base,
    input  logic  [23:0] vert_len,
    input  logic  [27:0] tex_rom,
    input  logic  [11:0] tex_groups,

    output logic         show_valid,
    output logic         show_plane,
    input  logic         shown_valid,
    input  logic         shown_plane,

    input  logic         DDRAM_BUSY,
    output logic   [7:0] DDRAM_BURSTCNT,
    output logic  [28:0] DDRAM_ADDR,
    input  logic  [63:0] DDRAM_DOUT,
    input  logic         DDRAM_DOUT_READY,
    output logic         DDRAM_RD,
    output logic  [63:0] DDRAM_DIN,
    output logic   [7:0] DDRAM_BE,
    output logic         DDRAM_WE,

    output logic   [3:0] state,
    output logic   [5:0] queued
);

    localparam logic [27:0] D3_TEX = 28'hE000000, D3_DEPTH = 28'hF000000,
                            D3_COL0 = 28'hF100000, D3_COL1 = 28'hF180000;

    logic  [7:0] wrap [0:31];
    always_comb for (int k = 0; k < 32; k++) wrap[k] = texwrap[8 * k +: 8];

    logic [27:0] plane_base [0:1];
    assign plane_base[0] = D3_COL0;
    assign plane_base[1] = D3_COL1;

    logic [27:0] c_addr [0:2];
    logic        c_rd [0:2], c_ready [0:2], c_valid [0:2];
    logic [63:0] d_data;
    logic [27:0] w_addr;
    logic [63:0] w_data;
    logic  [7:0] w_be;
    logic        w_valid, w_urgent, w_ready;

    hng64_3d u_3d (
        .clk1x(clk1x), .clk2x(clk2x), .reset(reset),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_be(dl_be), .dl_wdata(dl_wdata), .dl_up(dl_up),
        .dl_busy(dl_busy), .dl_upbusy(dl_upbusy), .dl_full(dl_full), .texwrap(wrap),
        .vblank(vblank), .clear_en(clear_en),
        .have3d(1'b1), .samsho(samsho), .vert_base(vert_base), .vert_len(vert_len),
        .tex_rom(tex_rom), .tex_groups(tex_groups), .tex_blocked(D3_TEX),
        .depth_base(D3_DEPTH), .plane_base(plane_base),
        .show_valid(show_valid), .show_plane(show_plane),
        .shown_valid(shown_valid), .shown_plane(shown_plane),
        .v_addr(c_addr[0]), .v_rd(c_rd[0]), .v_ready(c_ready[0]), .v_valid(c_valid[0]),
        .t_addr(c_addr[1]), .t_rd(c_rd[1]), .t_ready(c_ready[1]), .t_valid(c_valid[1]),
        .z_addr(c_addr[2]), .z_rd(c_rd[2]), .z_ready(c_ready[2]), .z_valid(c_valid[2]),
        .d_data(d_data),
        .w_addr(w_addr), .w_data(w_data), .w_be(w_be), .w_valid(w_valid),
        .w_urgent(w_urgent), .w_ready(w_ready),
        .dbg_state(state), .dbg_queued(queued));

    hng64_ddram #(.N(3)) u_ddr (
        .clk(clk2x), .reset(reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .w_addr({4'b0011, w_addr[27:3]}), .w_din(w_data), .w_be(w_be), .w_valid(w_valid),
        .w_urgent(w_urgent), .w_ready(w_ready),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(d_data), .c_valid(c_valid));

endmodule
