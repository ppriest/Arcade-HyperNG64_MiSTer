// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_video: sim/video_tb/main.cpp serves tile VRAM, both tile ROMs, the sprite
// list and the palette from a capture, and compares the whole frame with the model's.
//
// Array ports are flattened, and the register files are loaded through a write port, so the
// C++ driver can reach them.

module tb_video (
    input  logic        clk,
    input  logic        reset,
    input  logic        frame_start,
    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,

    input  logic [31:0] reg_w,
    input  logic  [5:0] reg_a,
    input  logic        vreg_we,
    input  logic        tcram_we,
    input  logic [31:0] spriteregs0,
    input  logic [31:0] spriteregs1,
    input  logic [23:0] bg_rgb,
    input  logic [25:0] scr_half,

    // tile VRAM goes through the real SDRAM stack and a chip model, so the bench fills it
    // through the download port first
    input  logic [24:0] d_addr,
    input  logic [15:0] d_din,
    input  logic        d_we,
    output logic        d_ready,

    output logic [13:0] sram_addr,
    output logic        sram_rd,
    input  logic [31:0] sram_data,

    // the two tile ROMs go through the real DDR3 transport, so the bench models DDRAM itself
    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,
    output logic        DDRAM_WE,

    output logic [11:0] pal_a0,
    output logic [11:0] pal_a1,
    output logic [11:0] pal_a2,
    output logic [11:0] pal_a3,
    output logic [11:0] pal_a4,
    input  logic [31:0] pal_d0,
    input  logic [31:0] pal_d1,
    input  logic [31:0] pal_d2,
    input  logic [31:0] pal_d3,
    input  logic [31:0] pal_d4,

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [23:0] px_rgb,
    output logic  [4:0] dbg_we,
    output logic  [8:0] dbg_x0, dbg_x1, dbg_x2, dbg_x3, dbg_x4,
    output logic [15:0] dbg_p0, dbg_p1, dbg_p2, dbg_p3, dbg_p4
);

    logic  [8:0] dbg_x [0:4];
    logic [15:0] dbg_pix [0:4];
    always_comb begin
        dbg_x0 = dbg_x[0]; dbg_x1 = dbg_x[1]; dbg_x2 = dbg_x[2];
        dbg_x3 = dbg_x[3]; dbg_x4 = dbg_x[4];
        dbg_p0 = dbg_pix[0]; dbg_p1 = dbg_pix[1]; dbg_p2 = dbg_pix[2];
        dbg_p3 = dbg_pix[3]; dbg_p4 = dbg_pix[4];
    end

    // the windows docs/MEMORY.md gives the two tile regions
    localparam logic [27:0] SROM_BASE = 28'h100_0000;
    localparam logic [27:0] PROM_BASE = 28'h500_0000;

    logic [16:0] vram_addr;
    logic        vram_rd, vram_ready, vram_valid;
    logic [31:0] vram_data;

    wire  [15:0] SDRAM_DQ;
    wire  [12:0] SDRAM_A;
    wire   [1:0] SDRAM_BA;
    wire         SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS;
    wire         SDRAM_CLK, SDRAM_CKE;

    hng64_sdram u_sdram (
        .clk(clk), .init(reset), .reset(reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .v_addr(vram_addr), .v_rd(vram_rd), .v_ready(vram_ready),
        .v_data(vram_data), .v_valid(vram_valid),
        .d_addr(d_addr), .d_din(d_din), .d_we(d_we), .d_ready(d_ready));

    sdram_chip_model_wide #(.MB(32)) u_chip (
        .clk(clk), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS));

    logic [25:0] srom_addr, prom_addr;
    logic        srom_rd, prom_rd;
    logic [63:0] ddr_data;
    logic        srom_valid, prom_valid;
    logic [27:0] c_addr [0:1];
    logic        c_rd [0:1];
    logic        c_ready [0:1];
    logic        c_valid [0:1];

    always_comb begin
        c_addr[0] = SROM_BASE + {2'd0, srom_addr};
        c_addr[1] = PROM_BASE + {2'd0, prom_addr};
        c_rd[0]   = srom_rd;
        c_rd[1]   = prom_rd;
        srom_valid = c_valid[0];
        prom_valid = c_valid[1];
    end

    hng64_ddram #(.N(2)) u_ddr (
        .w_addr(29'd0), .w_din(64'd0), .w_be(8'd0), .w_valid(1'b0), .w_urgent(1'b0), .w_ready(),
        .clk(clk), .reset(reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(ddr_data), .c_valid(c_valid));

    logic [31:0] videoregs [0:13];
    logic [31:0] tcram [0:23];
    logic [11:0] pal_a [0:4];
    logic [31:0] pal_d [0:4];

    always_ff @(posedge clk) begin
        if (vreg_we && reg_a < 6'd14) videoregs[reg_a[3:0]] <= reg_w;
        if (tcram_we && reg_a < 6'd24) tcram[reg_a[4:0]] <= reg_w;
    end

    always_comb begin
        pal_d[0] = pal_d0;
        pal_d[1] = pal_d1;
        pal_d[2] = pal_d2;
        pal_d[3] = pal_d3;
        pal_d[4] = pal_d4;
        pal_a0 = pal_a[0];
        pal_a1 = 12'd0;
        pal_a2 = 12'd0;
        pal_a3 = 12'd0;
        pal_a4 = 12'd0;
    end

    hng64_video dut (
        .dbg_layer_off(6'd0),
        .clk(clk), .reset(reset),
        .frame_start(frame_start), .line_start(line_start), .line(line), .busy(busy),
        .videoregs(videoregs), .tcram(tcram),
        .spriteregs0(spriteregs0), .spriteregs1(spriteregs1), .bg_rgb(bg_rgb),
        .screen_dis(tcram[2][31:16] == 16'd0 || tcram[2][15:0] == 16'd0),
        .scr_half(scr_half),
        .vram_addr(vram_addr), .vram_rd(vram_rd), .vram_ready(vram_ready), .vram_data(vram_data),
        .vram_valid(vram_valid),
        .srom_addr(srom_addr), .srom_rd(srom_rd), .srom_ready(c_ready[0]),
        .srom_data(ddr_data), .srom_valid(srom_valid),
        .sram_addr(sram_addr), .sram_rd(sram_rd), .sram_data(sram_data),
        .prom_addr(prom_addr), .prom_rd(prom_rd), .prom_ready(c_ready[1]),
        .prom_data(ddr_data), .prom_valid(prom_valid),
        .pal_a(pal_a[0]), .pal_d(pal_d[0]),     // one read a clock; the bench's other four ports idle
        // no 3D: no plane is ever shown, so the fetcher reads nothing
        .vis_y0(10'd0), .vis_h(10'd448), .fbcontrol0(8'd0), .fbcontrol2(8'd0), .fbscroll(32'd0),
        .show_valid(1'b0), .show_plane(1'b0), .shown_valid(), .shown_plane(),
        .plane_base('{28'd0, 28'd0}),
        .d3_addr(), .d3_rd(), .d3_ready(1'b0), .d3_data(64'd0), .d3_valid(1'b0),
        .px_we(px_we), .px_x(px_x), .px_rgb(px_rgb),
        .dbg_we(dbg_we), .dbg_x(dbg_x), .dbg_pix(dbg_pix));

endmodule
