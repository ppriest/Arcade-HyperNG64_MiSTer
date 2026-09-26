// SPDX-License-Identifier: GPL-3.0-or-later
//
// The IO MCU subsystem - core, memories, peripherals and the board's port wiring - against
// MAME's instruction trace. The ROM is loaded through the load port, as the core will be.

module tb_iomcu (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce,

    input  logic        rom_we,
    input  logic [13:0] rom_addr,
    input  logic  [7:0] rom_data,

    input  logic  [7:0] in_all,         // every input byte, for a bench that holds them idle
    input  logic        int0,

    output logic        lamp_we,
    output logic        mips_irq,

    output logic        dbg_fetch,
    output logic [15:0] dbg_pc,
    output logic  [7:0] dbg_op,
    output logic  [7:0] dbg_op1,
    output logic        dbg_unimpl,
    output logic        dbg_overrun,
    output logic [15:0] dbg_sp,
    output logic  [3:0] dbg_rbs,
    output logic  [7:0] dbg_f,
    output logic        dbg_we,
    output logic [15:0] dbg_addr,
    output logic  [7:0] dbg_wdata
);

    logic [7:0] inputs [0:7];
    logic [7:0] analog [0:7];

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            inputs[i] = in_all;
            analog[i] = 8'hff;
        end
    end

    hng64_iomcu dut (
        .clk(clk), .reset(reset), .ce(ce),
        .rom_we(rom_we), .rom_addr(rom_addr), .rom_data(rom_data),
        .inputs(inputs), .analog(analog), .int0(int0),
        .lamp_we(lamp_we), .lamp_addr(), .lamp_data(), .mips_irq(mips_irq),
        .dp_addr(11'd0), .dp_we(1'b0), .dp_wdata(8'd0), .dp_rdata(),
        .dbg_fetch(dbg_fetch), .dbg_pc(dbg_pc), .dbg_op(dbg_op), .dbg_op1(dbg_op1),
        .dbg_unimpl(dbg_unimpl), .dbg_overrun(dbg_overrun),
        .dbg_sp(dbg_sp), .dbg_rbs(dbg_rbs), .dbg_f(dbg_f),
        .dbg_we(dbg_we), .dbg_addr(dbg_addr), .dbg_wdata(dbg_wdata));

endmodule
