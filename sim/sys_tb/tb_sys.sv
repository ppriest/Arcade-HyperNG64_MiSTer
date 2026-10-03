// SPDX-License-Identifier: GPL-3.0-or-later
//
// hng64_core, the whole board less its CPU, with MAME's bus trace driven into the CPU's port by
// sim/sys_tb/main.cpp. The SDRAM is the vendored controller over a chip model; DDR3 is the bench's
// model of the DDRAM port, holding the image the .mra would put there.

module tb_sys (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        reset,

    input  logic        mem_request,
    input  logic        mem_rnw,
    input  logic        mem_req64,
    input  logic [31:0] mem_address,
    input  logic  [7:0] mem_writeMask,
    input  logic [63:0] mem_dataWrite,
    output logic [63:0] mem_dataRead,
    output logic        mem_done,
    output logic        cpu_irq,
    output logic        cpu_reset,

    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,
    input  logic [63:0] inputs_flat,    // IN0 in bits 7:0
    input  logic        flip,
    output logic  [7:0] nv_rdata,
    output logic        nv_written,

    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD,
    output logic        DDRAM_WE,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,

    output logic        ce_pix,
    output logic        hblank,
    output logic        vblank,
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,
    output logic  [5:0] dbg_fault,
    output logic  [9:0] dbg_ldr,        // the loading and reset state, for the bench's messages
    output logic  [7:0] dbg_copy        // the copy engine's state and handshakes
);

    assign dbg_copy = {dut.u_ldr.st, dut.ldr_rd, dut.ldr_ready, dut.ldr_valid, dut.ldr_swe,
                       dut.ldr_sready, dut.DDRAM_RD};

    assign dbg_ldr = {dut.dl0_seen, dut.cfg_valid, dut.ldr_pending, dut.ldr_done, dut.ldr_start,
                      dut.ldr_active, dut.rom_loaded, dut.mem_reset, dut.game_reset, dut.reset};

    logic [7:0] inputs [0:7];
    always_comb for (int i = 0; i < 8; i++) inputs[i] = inputs_flat[8*i +: 8];

    wire  [15:0] SDRAM_DQ;
    wire  [12:0] SDRAM_A;
    wire   [1:0] SDRAM_BA;
    wire         SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS;
    wire         SDRAM_CLK, SDRAM_CKE;

    hng64_core dut (
        .clk1x(clk1x), .clk2x(clk2x), .clk3d(clk2x), .reset(reset), .sdram_init(reset),
        .mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
        .mem_req64(mem_req64), .mem_size(3'b001), .mem_writeMask(mem_writeMask),
        .mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
        .rdram_granted2x(), .ddr3_DOUT(), .ddr3_DOUT_READY(),
        .cpu_irq(cpu_irq), .cpu_reset(cpu_reset),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
        .rtc(56'h04092612233059), .nv_rdata(nv_rdata), .nv_written(nv_written), .inputs(inputs), .flip(flip), .game_speed(3'd0),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),

        .ce_pix(ce_pix), .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
        .r(r), .g(g), .b(b),
        .lamp_we(), .lamp_addr(), .lamp_data(),
        .dbg_fault(dbg_fault), .dbg_layer_off(6'd0), .dbg_load(), .dbg_mcu_pc(),
        .dbg_mcu_fetch(), .dbg_rd(1'b0), .dbg_rsel(3'd0), .dbg_raddr(14'd0));

    sdram_chip_model_wide #(.MB(32)) u_chip (
        .clk(clk2x), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS));

endmodule
