// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_mixer: sim/mixer_tb/main.cpp serves the five line buffers from the model's
// per-layer dumps and the palette from the capture, and compares the RGB against the model's
// finished frame.
//
// The array ports are flattened so the C++ driver can reach them.

module tb_mixer (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        rebuild,
    output logic        busy,

    output logic  [8:0] lb_x,
    input  logic [15:0] tm0_pix,
    input  logic [15:0] tm1_pix,
    input  logic [15:0] tm2_pix,
    input  logic [15:0] tm3_pix,
    input  logic [15:0] spr_pix,

    input  logic [15:0] tileregs0,
    input  logic [15:0] tileregs1,
    input  logic [15:0] tileregs2,
    input  logic [15:0] tileregs3,
    input  logic [23:0] bg_rgb,
    input  logic [31:0] tcram_w,
    input  logic  [4:0] tcram_a,
    input  logic        tcram_we,

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
    output logic [23:0] px_rgb
);

    logic [15:0] tm_pix [0:3];
    logic [15:0] tileregs [0:3];
    logic [31:0] tcram [0:23];
    logic [11:0] pal_a [0:4];
    logic [31:0] pal_d [0:4];

    always_comb begin
        tm_pix[0] = tm0_pix;
        tm_pix[1] = tm1_pix;
        tm_pix[2] = tm2_pix;
        tm_pix[3] = tm3_pix;
        tileregs[0] = tileregs0;
        tileregs[1] = tileregs1;
        tileregs[2] = tileregs2;
        tileregs[3] = tileregs3;
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

    always_ff @(posedge clk)
        if (tcram_we) tcram[tcram_a] <= tcram_w;

    hng64_mixer dut (
        .clk(clk), .reset(reset), .start(start), .rebuild(rebuild), .busy(busy),
        .lb_x(lb_x), .tm_pix(tm_pix), .spr_pix(spr_pix), .d3_pix(16'd0), .d3_palbase(1'b0),
        .tileregs(tileregs), .tcram(tcram), .bg_rgb(bg_rgb),
        .screen_dis(tcram[2][31:16] == 16'd0 || tcram[2][15:0] == 16'd0),
        .pal_a(pal_a[0]), .pal_d(pal_d[0]),     // one read a clock; the bench's other four ports idle
        .px_we(px_we), .px_x(px_x), .px_rgb(px_rgb));

endmodule
