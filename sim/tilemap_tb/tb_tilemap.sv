// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_tilemap so sim/tilemap_tb/main.cpp can drive it: VRAM and tile ROM are
// served from C++ out of a MAME capture, and every emitted pixel is compared with the software
// model's dump for the same layer (scripts/render_model.py --dump).

module tb_tilemap (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic  [8:0] line,
    input  logic  [1:0] tm_index,
    output logic        busy,

    input  logic [15:0] tileregs,
    input  logic [13:0] scrollbase,
    input  logic [31:0] videoreg0,
    input  logic [31:0] videoreg1,
    input  logic [31:0] anim_mask,
    input  logic [31:0] anim_bits,

    output logic [16:0] vram_addr,
    output logic        vram_rd,
    input  logic [31:0] vram_data,
    input  logic        vram_valid,

    output logic [25:0] rom_addr,
    output logic        rom_rd,
    input  logic [63:0] rom_data,
    input  logic        rom_valid,

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [15:0] px_pix
);

    hng64_tilemap dut (
        .clk(clk), .reset(reset), .start(start), .line(line), .tm_index(tm_index), .busy(busy),
        .tileregs(tileregs), .scrollbase(scrollbase), .videoreg0(videoreg0),
        .videoreg1(videoreg1), .anim_mask(anim_mask), .anim_bits(anim_bits),
        .vram_addr(vram_addr), .vram_rd(vram_rd), .vram_ready(1'b1), .vram_data(vram_data), .vram_valid(vram_valid),
        .rom_addr(rom_addr), .rom_rd(rom_rd), .rom_ready(1'b1), .rom_data(rom_data), .rom_valid(rom_valid),
        .px_we(px_we), .px_x(px_x), .px_pix(px_pix));

endmodule
