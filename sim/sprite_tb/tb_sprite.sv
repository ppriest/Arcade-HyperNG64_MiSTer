// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_sprite: sim/sprite_tb/main.cpp serves the sprite RAM snapshot and the sprite
// tile ROM from a MAME capture and compares each line with the model's sprites.bin.

module tb_sprite (
    input  logic        clk,
    input  logic        reset,
    input  logic        frame_start,
    input  logic        line_start,
    input  logic  [8:0] line,
    output logic        busy,

    input  logic [31:0] spriteregs0,
    input  logic [31:0] spriteregs1,

    output logic [13:0] ram_addr,
    output logic        ram_rd,
    input  logic [31:0] ram_data,

    output logic [25:0] rom_addr,
    output logic        rom_rd,
    input  logic        rom_ready,
    input  logic [63:0] rom_data,
    input  logic        rom_valid,

    output logic  [1:0] px_we,
    output logic  [8:0] px_x0, px_x1,
    output logic [15:0] px_pix0, px_pix1,
    output logic  [8:0] dbg_ncand,
    output logic [11:0] dbg_xpos,
    output logic  [9:0] dbg_dstwidth,
    output logic  [3:0] dbg_xdrw,
    output logic  [4:0] dbg_st,
    output logic  [2:0] dbg_dst,
    output logic        dbg_vis
);

    logic  [8:0] px_x [0:1];
    logic [15:0] px_pix [0:1];
    assign px_x0 = px_x[0];
    assign px_x1 = px_x[1];
    assign px_pix0 = px_pix[0];
    assign px_pix1 = px_pix[1];

    hng64_sprite dut (
        .clk(clk), .reset(reset), .frame_start(frame_start), .line_start(line_start),
        .line(line), .busy(busy),
        .spriteregs0(spriteregs0), .spriteregs1(spriteregs1),
        .ram_addr(ram_addr), .ram_rd(ram_rd), .ram_data(ram_data),
        .rom_addr(rom_addr), .rom_rd(rom_rd), .rom_ready(rom_ready), .rom_data(rom_data), .rom_valid(rom_valid),
        .px_we(px_we), .px_x(px_x), .px_pix(px_pix), .dbg_ncand(dbg_ncand), .dbg_xpos(dbg_xpos), .dbg_dstwidth(dbg_dstwidth), .dbg_xdrw(dbg_xdrw), .dbg_st(dbg_st), .dbg_dst(dbg_dst), .dbg_vis(dbg_vis));

endmodule
