// SPDX-License-Identifier: GPL-3.0-or-later
//
// The HNG64 board, less its CPU and the MiSTer framework: everything HyperNG64.sv connects to
// hps_io, the SDRAM and DDR3 ports and the video output. The VR4300 stays in HyperNG64.sv because
// it is VHDL and this module has to build in Verilator, where a bench drives the CPU's port.
//
// CLOCKS, all from one PLL (docs/HARDWARE_NOTES.md):
//   clk1x   62.5 MHz   the CPU's bus side, hng64_bus's clk1x, the I/O devices, hps_io
//   clk2x   125 MHz    SDRAM, DDR3, the video (a pixel every five clocks), the IO MCU
// clk2x is exactly twice clk1x, so registers cross between them as they are and a one-clock
// clk2x pulse bound for clk1x is stretched to two.
//
// RESET AND LOADING (the skill's ddr_rom_loading.md, the Seta/MS32 block). The .mra's
// `<rom index="0" address="0x30000000">` has the HPS write the whole image into DDR3; the core
// sees index 0's download start and end with no bytes. `<rom index="1">` is the layout
// (hng64_romcfg), `<rom index="2">` the IO MCU's ROM and index 4 the NVRAM, all through the
// byte path. On the next reset release the BIOS is copied from DDR3 into SDRAM (hng64_romload),
// once per index-0 download, with the game held in reset. The memory path's own reset leaves out
// the download, because MiSTer holds reset for the whole of it and SDRAM must stay live.

module hng64_core #(
    parameter logic [7:0] NO_MACHINE_ERROR_CODE = 8'h01    // the fight sets'
) (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        reset,          // the framework's reset, clk1x
    input  logic        sdram_init,     // PLL not locked yet

    // the CPU's memory port (rtl/cpu/hng64_cpu.vhd)
    input  logic        mem_request,
    input  logic        mem_rnw,
    input  logic [31:0] mem_address,
    input  logic        mem_req64,
    input  logic  [2:0] mem_size,
    input  logic  [7:0] mem_writeMask,
    input  logic [63:0] mem_dataWrite,
    output logic [63:0] mem_dataRead,
    output logic        mem_done,
    output logic        rdram_granted2x,
    output logic [63:0] ddr3_DOUT,
    output logic        ddr3_DOUT_READY,
    output logic        cpu_irq,
    output logic        cpu_reset,      // the game's reset, clk1x

    // hps_io, clk1x
    input  logic        ioctl_download,
    input  logic [15:0] ioctl_index,
    input  logic        ioctl_wr,
    input  logic [26:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,
    input  logic [55:0] rtc,
    output logic  [7:0] nv_rdata,       // NVRAM byte at ioctl_addr, the clock after (upload)
    output logic        nv_written,     // one clock per CPU write to NVRAM

    input  logic  [7:0] inputs [0:7],   // IN0-IN7, active low, as MAME's hng64_fight ports
    input  logic        flip,           // the picture turned 180 degrees, from the next frame

    // SDRAM
    output logic [12:0] SDRAM_A,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    output logic  [1:0] SDRAM_BA,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_CLK,
    output logic        SDRAM_CKE,

    // DDR3, the core's window at 0x30000000
    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,
    output logic        DDRAM_WE,

    // the HDMI rotator's writes (screen_rotate_two in HyperNG64.sv), clk2x: one clock each, queued
    input  logic        rot_we,
    input  logic [28:0] rot_addr,
    input  logic [63:0] rot_din,
    input  logic  [7:0] rot_be,
    output logic        rot_overflow,   // sticky: a rotated pixel was lost

    // video, clk2x
    output logic        ce_pix,
    output logic        hsync,
    output logic        vsync,
    output logic        hblank,
    output logic        vblank,
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,

    output logic        lamp_we,
    output logic  [2:0] lamp_addr,
    output logic  [7:0] lamp_data,

    // debug: sticky faults, for the OSD page and the ISSP probe
    output logic  [5:0] dbg_fault,      // bus 64-bit I/O, DMA outside store, MCU opcode,
                                        // MCU overrun, video line late, layout blob invalid
    input  logic  [4:0] dbg_layer_off,  // the OSD's debug page: tilemaps 0-3, sprites; 0 = on
    output logic  [7:0] dbg_load,       // {dl0_seen, cfg_valid, ldr_pending, ldr_done,
                                        //  ldr_active, rom_loaded, mem_reset, game_reset}
    output logic [15:0] dbg_mcu_pc,
    output logic        dbg_mcu_fetch   // one clk2x clock per MCU instruction
);

    // declared ahead of the instances that share them
    logic        dma_active, dma_req, dma_we, dma_err;
    logic [31:0] dma_addr, dma_src, dma_dst, dma_count;
    logic  [2:0] dma_beats;
    logic [63:0] dma_wdata;
    logic  [7:0] dma_be;
    logic        dma_go, dma_done;
    logic [25:0] srom_addr, prom_addr;
    logic        srom_rd, prom_rd;
    logic [63:0] ddr_data;
    logic [27:0] c_addr [0:3];
    logic        c_rd [0:3];
    logic        c_ready [0:3];
    logic        c_valid [0:3];

    // ---- loading and resets ----------------------------------------------------------------------
    localparam int NREG = 6;            // gameprg, bios, scrtile, sprtile, textures0, verts
    logic [27:0] cfg_base [0:NREG-1];
    logic [27:0] cfg_size [0:NREG-1];
    logic        cfg_valid;

    hng64_romcfg #(.N(NREG)) u_cfg (
        .clk(clk1x),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
        .base(cfg_base), .size(cfg_size), .valid(cfg_valid));

    wire dl0 = ioctl_download && (ioctl_index == 16'd0);
    logic game_reset, mem_reset;

    // power-up values: nothing loaded, nothing copied
    logic dl0_seen = 1'b0, ldr_done = 1'b0, rom_loaded = 1'b0, ldr_pending = 1'b0;
    logic dl0_d, ldr_start;
    logic ldr_active, ldr_active_d, ldr_fin;

    always_ff @(posedge clk1x) begin
        ldr_start    <= 1'b0;
        dl0_d        <= dl0;
        ldr_active_d <= ldr_active;
        if (dl0 && !dl0_d) begin                // a new image: copy its BIOS again
            dl0_seen <= 1'b1;
            ldr_done <= 1'b0;
            rom_loaded <= 1'b0;
        end
        if (ldr_active_d && !ldr_active) rom_loaded <= 1'b1;
        // The copy starts on the release of the reset MiSTer holds through every download. It
        // is the raw reset, not mem_reset: mem_reset drops for a download, and between two
        // downloads the copy would start inside the reset. The raw reset falls on the same edge
        // that mem_reset, which the copy engine sees, is registered low.
        if (reset) ldr_pending <= 1'b1;
        else if (ldr_pending && !ioctl_download && !ldr_active) begin
            ldr_pending <= 1'b0;
            if (dl0_seen && cfg_valid && !ldr_done) begin
                ldr_start <= 1'b1;
                ldr_done  <= 1'b1;
            end
        end
    end

    // registered, so both clock domains see one clean edge (clk2x samples a clk1x register)
    always_ff @(posedge clk1x) begin
        game_reset <= reset || ioctl_download || !rom_loaded || ldr_active;
        mem_reset  <= reset && !ioctl_download;
    end
    assign cpu_reset = game_reset;

    // ---- the CPU's bus, and the backing store behind it ------------------------------------------
    logic        st_req_b, st_we_b, st_rvalid, st_wdone;
    logic [31:0] st_addr_b;
    logic  [2:0] st_beats_b;
    logic [63:0] st_wdata_b, st_rdata;
    logic  [7:0] st_be_b;
    logic        io_req, io_we, io_ack;
    logic [31:0] io_addr, io_wdata, io_rdata;
    logic  [3:0] io_be;
    logic        err64;

    hng64_bus u_bus (
        .clk1x(clk1x), .clk2x(clk2x), .reset(game_reset),
        .mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
        .mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
        .mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
        .rdram_granted2x(rdram_granted2x), .ddr3_DOUT(ddr3_DOUT), .ddr3_DOUT_READY(ddr3_DOUT_READY),
        .st_req(st_req_b), .st_we(st_we_b), .st_addr(st_addr_b), .st_beats(st_beats_b),
        .st_wdata(st_wdata_b), .st_be(st_be_b),
        .st_rvalid(st_rvalid && !dma_active), .st_rdata(st_rdata),
        .st_wdone(st_wdone && !dma_active),
        .io_req(io_req), .io_we(io_we), .io_addr(io_addr), .io_be(io_be), .io_wdata(io_wdata),
        .io_ack(io_ack), .io_rdata(io_rdata),
        .err_unmapped64(err64));

    // The DMA has the store port while it runs: the CPU is waiting on the I/O write that
    // started it, so the bridge cannot be using the port then.

    hng64_dma u_dma (
        .clk(clk2x), .reset(game_reset),
        .src(dma_src), .dst(dma_dst), .count(dma_count), .go(dma_go), .done(dma_done),
        .active(dma_active),
        .st_req(dma_req), .st_we(dma_we), .st_addr(dma_addr), .st_beats(dma_beats),
        .st_wdata(dma_wdata), .st_be(dma_be),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .err_nonstore(dma_err));

    logic [25:0] s_addr;
    logic        s_rd, s_we, s_ready, s_valid;
    logic [63:0] s_wdata, s_data;
    logic  [7:0] s_be;
    logic [27:0] prg_addr;
    logic        prg_rd, prg_ready, prg_valid;

    hng64_mainmem u_mem (
        .clk(clk2x), .reset(mem_reset), .prg_base(cfg_base[0]),
        .st_req(dma_active ? dma_req : st_req_b),
        .st_we(dma_active ? dma_we : st_we_b),
        .st_addr(dma_active ? dma_addr : st_addr_b),
        .st_beats(dma_active ? dma_beats : st_beats_b),
        .st_wdata(dma_active ? dma_wdata : st_wdata_b),
        .st_be(dma_active ? dma_be : st_be_b),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .s_addr(s_addr), .s_rd(s_rd), .s_we(s_we), .s_wdata(s_wdata), .s_be(s_be),
        .s_ready(s_ready), .s_data(s_data), .s_valid(s_valid),
        .d_addr(prg_addr), .d_rd(prg_rd), .d_ready(prg_ready), .d_data(ddr_data),
        .d_valid(prg_valid));

    // ---- the BIOS copy ----------------------------------------------------------------------------
    logic [27:0] ldr_addr;
    logic        ldr_rd, ldr_ready, ldr_valid;
    logic [24:0] ldr_saddr;
    logic [15:0] ldr_sdin;
    logic        ldr_swe, ldr_sready, ldr_done_2x;

    hng64_romload u_ldr (
        .clk(clk2x), .reset(mem_reset),
        .start(ldr_start), .src_base(cfg_base[1]), .src_size(cfg_size[1]),
        .active(ldr_active), .done(ldr_done_2x),
        .d_addr(ldr_addr), .d_rd(ldr_rd), .d_ready(ldr_ready), .d_data(ddr_data),
        .d_valid(ldr_valid),
        .s_addr(ldr_saddr), .s_din(ldr_sdin), .s_we(ldr_swe), .s_ready(ldr_sready));

    // ---- SDRAM: tile VRAM for the video, the CPU, and the BIOS copy ------------------------------------
    logic [16:0] vram_addr;
    logic        vram_rd, vram_ready, vram_valid;
    logic [31:0] vram_data;

    hng64_sdram u_sdram (
        .clk(clk2x), .init(sdram_init), .reset(mem_reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .v_addr(vram_addr), .v_rd(vram_rd), .v_ready(vram_ready), .v_data(vram_data),
        .v_valid(vram_valid),
        .c_addr(s_addr), .c_rd(s_rd), .c_we(s_we), .c_wdata(s_wdata), .c_be(s_be),
        .c_ready(s_ready), .c_data(s_data), .c_valid(s_valid),
        .d_addr(ldr_saddr), .d_din(ldr_sdin), .d_we(ldr_swe), .d_ready(ldr_sready));

    // ---- DDR3: the two tile ROMs, gameprg, and the BIOS copy -------------------------------------------

    always_comb begin
        c_addr[0] = cfg_base[2] + {2'd0, srom_addr};    c_rd[0] = srom_rd;
        c_addr[1] = cfg_base[3] + {2'd0, prom_addr};    c_rd[1] = prom_rd;
        c_addr[2] = prg_addr;                           c_rd[2] = prg_rd;
        c_addr[3] = ldr_addr;                           c_rd[3] = ldr_rd;
        prg_ready = c_ready[2];  prg_valid = c_valid[2];
        ldr_ready = c_ready[3];  ldr_valid = c_valid[3];
    end

    logic [28:0] w_addr;
    logic [63:0] w_din;
    logic  [7:0] w_be;
    logic        w_valid, w_urgent, w_ready;

    hng64_wfifo u_rotq (
        .clk(clk2x), .reset(mem_reset),
        .in_we(rot_we), .in_addr(rot_addr), .in_din(rot_din), .in_be(rot_be),
        .w_addr(w_addr), .w_din(w_din), .w_be(w_be), .w_valid(w_valid), .w_urgent(w_urgent),
        .w_ready(w_ready), .overflow(rot_overflow));

    hng64_ddram #(.N(4)) u_ddr (
        .clk(clk2x), .reset(mem_reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .w_addr(w_addr), .w_din(w_din), .w_be(w_be), .w_valid(w_valid), .w_urgent(w_urgent),
        .w_ready(w_ready),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(ddr_data), .c_valid(c_valid));

    // ---- the main board's I/O -----------------------------------------------------------------------
    logic        v_req, v_we, v_ack;
    logic  [2:0] v_sel;
    logic [13:0] v_addr;
    logic  [3:0] v_be;
    logic [31:0] v_wdata, v_rdata;
    logic [31:0] raster_pos;
    logic        vblank_irq, raster_irq, net_irq, vblank_level;
    logic        mcu_int0, mcu_irq_2x, mcu_irq;
    logic [10:0] dp_addr;
    logic        dp_we;
    logic  [7:0] dp_wdata, dp_rdata, fbcontrol0;

    // the .nvm file: downloaded as index 4, read back through ioctl_addr on an upload
    wire nv_dl_we = ioctl_download && ioctl_index == 16'd4 && ioctl_wr && ioctl_addr < 27'h4000;

    hng64_io #(.NO_MACHINE_ERROR_CODE(NO_MACHINE_ERROR_CODE)) u_io (
        .clk(clk1x), .reset(game_reset),
        .io_req(io_req), .io_we(io_we), .io_addr(io_addr), .io_be(io_be), .io_wdata(io_wdata),
        .io_ack(io_ack), .io_rdata(io_rdata),
        .cpu_irq(cpu_irq),
        .vblank_irq(vblank_irq), .raster_irq(raster_irq), .net_irq(net_irq),
        .raster_pos(raster_pos), .vblank(vblank_level),
        .mcu_int0(mcu_int0),
        .dp_addr(dp_addr), .dp_we(dp_we), .dp_wdata(dp_wdata), .dp_rdata(dp_rdata),
        .mcu_irq(mcu_irq),
        .rtc(rtc),
        .nv_addr(ioctl_addr[13:0]), .nv_we(nv_dl_we), .nv_wdata(ioctl_dout),
        .nv_rdata(nv_rdata), .nv_written(nv_written),
        .dma_src(dma_src), .dma_dst(dma_dst), .dma_count(dma_count),
        .dma_go(dma_go), .dma_done(dma_done),
        .v_req(v_req), .v_we(v_we), .v_sel(v_sel), .v_addr(v_addr), .v_be(v_be),
        .v_wdata(v_wdata), .v_ack(v_ack), .v_rdata(v_rdata),
        .fbcontrol0(fbcontrol0), .dbg_mcu_en_0c());

    // ---- the IO MCU: 8 MHz from 125, as an accumulator (8/125 exactly) ----------------------------------
    logic [6:0] mcu_acc;
    logic       mcu_ce;
    logic [1:0] mcu_irq_hold;
    logic       mcu_unimpl, mcu_overrun;

    always_ff @(posedge clk2x) begin
        if (game_reset) begin
            mcu_acc <= 7'd0;
            mcu_ce  <= 1'b0;
            mcu_irq_hold <= 2'd0;
        end else begin
            if (mcu_acc >= 7'd117) begin mcu_acc <= mcu_acc - 7'd117; mcu_ce <= 1'b1; end
            else                   begin mcu_acc <= mcu_acc + 7'd8;   mcu_ce <= 1'b0; end
            // a one-clock clk2x pulse, held two so clk1x sees it once
            if (mcu_irq_2x) mcu_irq_hold <= 2'd2;
            else if (mcu_irq_hold != 2'd0) mcu_irq_hold <= mcu_irq_hold - 2'd1;
        end
    end
    assign mcu_irq = (mcu_irq_hold != 2'd0);

    // the MCU ROM through the byte path: file offsets 0x4000-0x7fff arrive as index 2, 0-0x3fff
    wire mcu_rom_we = ioctl_download && ioctl_index == 16'd2 && ioctl_wr && ioctl_addr < 27'h4000;

    hng64_iomcu u_mcu (
        .clk(clk2x), .reset(game_reset), .ce(mcu_ce),
        .rom_we(mcu_rom_we), .rom_addr(ioctl_addr[13:0]), .rom_data(ioctl_dout),
        .inputs(inputs), .analog('{8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff}),
        .int0(mcu_int0),
        .lamp_we(lamp_we), .lamp_addr(lamp_addr), .lamp_data(lamp_data), .mips_irq(mcu_irq_2x),
        .dp_clk(clk1x), .dp_addr(dp_addr), .dp_we(dp_we), .dp_wdata(dp_wdata),
        .dp_rdata(dp_rdata),
        .dbg_fetch(dbg_mcu_fetch), .dbg_pc(dbg_mcu_pc), .dbg_op(), .dbg_op1(), .dbg_unimpl(mcu_unimpl),
        .dbg_overrun(mcu_overrun), .dbg_sp(), .dbg_rbs(), .dbg_f(),
        .dbg_we(), .dbg_addr(), .dbg_wdata());

    // ---- video ------------------------------------------------------------------------------------
    logic [31:0] videoregs [0:13];
    logic [31:0] tcram [0:23];
    logic [31:0] spriteregs0, spriteregs1;
    logic [23:0] bg_rgb;
    logic        snapshot, snapshot_done;
    logic [13:0] sram_addr;
    logic        sram_rd;
    logic [31:0] sram_data;
    logic [11:0] pal_a [0:4];
    logic [31:0] pal_d [0:4];
    logic        line_start, frame_start, vbusy, px_we, vlate;
    logic  [8:0] line, px_x;
    logic [23:0] px_rgb;

    hng64_vbus u_vbus (
        .clk1x(clk1x), .clk2x(clk2x), .reset(game_reset),
        .v_req(v_req), .v_we(v_we), .v_sel(v_sel), .v_addr(v_addr), .v_be(v_be),
        .v_wdata(v_wdata), .v_ack(v_ack), .v_rdata(v_rdata), .fbcontrol0(fbcontrol0),
        .videoregs(videoregs), .tcram(tcram), .spriteregs0(spriteregs0),
        .spriteregs1(spriteregs1), .bg_rgb(bg_rgb),
        .snapshot(snapshot), .snapshot_done(snapshot_done),
        .sram_addr(sram_addr), .sram_data(sram_data), .pal_a(pal_a), .pal_d(pal_d));

    hng64_video u_video (
        .clk(clk2x), .reset(game_reset),
        .frame_start(frame_start), .line_start(line_start), .line(line), .busy(vbusy),
        .dbg_layer_off(dbg_layer_off),
        .videoregs(videoregs), .tcram(tcram),
        .spriteregs0(spriteregs0), .spriteregs1(spriteregs1), .bg_rgb(bg_rgb),
        .scr_half(cfg_size[2][26:1]),
        .vram_addr(vram_addr), .vram_rd(vram_rd), .vram_ready(vram_ready), .vram_data(vram_data),
        .vram_valid(vram_valid),
        .srom_addr(srom_addr), .srom_rd(srom_rd), .srom_ready(c_ready[0]),
        .srom_data(ddr_data), .srom_valid(c_valid[0]),
        .sram_addr(sram_addr), .sram_rd(sram_rd), .sram_data(sram_data),
        .prom_addr(prom_addr), .prom_rd(prom_rd), .prom_ready(c_ready[1]),
        .prom_data(ddr_data), .prom_valid(c_valid[1]),
        .pal_a(pal_a), .pal_d(pal_d),
        .px_we(px_we), .px_x(px_x), .px_rgb(px_rgb),
        .dbg_we(), .dbg_x(), .dbg_pix());

    hng64_vtiming u_timing (
        .clk(clk2x), .reset(game_reset), .flip(flip),
        .ce_pix(ce_pix), .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
        .r(r), .g(g), .b(b),
        .line_start(line_start), .line(line), .frame_start(frame_start), .busy(vbusy),
        .snapshot(snapshot), .snapshot_done(snapshot_done),
        .px_we(px_we), .px_x(px_x), .px_rgb(px_rgb),
        .raster_pos(raster_pos), .vblank_irq(vblank_irq), .raster_irq(raster_irq),
        .net_irq(net_irq), .vblank_level(vblank_level),
        .dbg_late(vlate));

    assign dbg_fault = {!cfg_valid, vlate, mcu_overrun, mcu_unimpl, dma_err, err64};
    assign dbg_load  = {dl0_seen, cfg_valid, ldr_pending, ldr_done, ldr_active, rom_loaded,
                        mem_reset, game_reset};

endmodule
