// SPDX-License-Identifier: GPL-3.0-or-later
//
// The main CPU's I/O space: everything in MAME's main_map (hng64.cpp:1182) that is a device
// rather than plain memory. Plain memory - RAM, ROM, sound RAM, tile VRAM, the 3D buffers - goes
// through the bridge's backing store instead (hng64_bus.sv, is_store).
//
// The port is hng64_bus.sv's io_*: a one-clock request, word-aligned, big-endian, be[3] the byte
// at addr+0; one ack when the answer is ready. Everything here runs on the bridge's clk1x.
//
//   0x1f700000  system registers    RAM, with 0x1c reading 0, 0x1084 reading 2, and writes to
//                                   0x100c (raster position) and 0x1084 (MCU command) acted on
//   0x1f701100  interrupt control   0x04 reads the level, 0x1c acknowledges
//   0x1f701200  DMA                 0x24 starts a copy, done before the write is acknowledged
//   0x1f702100  RTC, MSM6242        one nibble in every eight bytes
//   0x1f7021c4  MCU command irq     a write pulses the MCU's INT0
//   0x1f800000  NVRAM, 16 KB
//   0x1f808000  dual-port RAM       shared with the IO MCU, one byte per lane
//   0x20000000  sprite RAM, sprite clears, sprite regs, video regs, palette, tcram: the video
//                                   block's, through the v_* port. tcram 0x48 reads vblank.
//   0x20300000  3D display list     written through to hng64_3d's copy; an upload queues it there
//                                   and raises interrupt 3 a fixed time later as MAME's does
//   0x30000000  3D buffer control   stored; 0x08 the buffer's x scroll
//   0x60000000  sound RAM "2"       reads 0 (MAME: "actually seems unmapped")
//   0x68000000  sound mailbox       the ARM process's replies through hng64_sndbridge while it
//                                   runs, else a stand-in (HACKS.md)
//   0x6f000000  sound CPU enable    passed to hng64_sndbridge
//   0xc0000000  network board RAM   plain RAM: there is no network CPU (HACKS.md)
//   anything else                   reads 0, writes ignored
//
// Times MAME gives in main-CPU cycles are its 50 MHz clock (hng64.h:218); they are counted here
// in clk1x cycles at 62.5 MHz, which is 5/4 as many and exact for every value used.

module hng64_io (
    input  logic        clk,            // the bridge's clk1x
    input  logic        reset,
    // m_no_machine_error_code, the board's: 1 fight, 2 drive, 3 shoot (hng64.cpp init_*), from the .mra
    input  logic  [7:0] no_machine_error_code,

    input  logic        io_req,
    input  logic        io_we,
    input  logic [31:0] io_addr,
    input  logic  [3:0] io_be,
    input  logic [31:0] io_wdata,
    output logic        io_ack,
    output logic [31:0] io_rdata,

    // the CPU's interrupt input (MAME's input line 0)
    output logic        cpu_irq,

    // interrupt sources from the video timing, one clock each
    input  logic        vblank_irq,     // bit 0: line 224 of 264
    input  logic        raster_irq,     // bit 1: line raster_pos + 8, before line 224
    input  logic        net_irq,        // bit 11: line 240
    output logic [31:0] raster_pos,     // m_raster_irq_pos[0], for the video timing to compare
    input  logic        vblank,         // what tcram 0x48 reads

    // the IO MCU
    output logic        mcu_int0,
    output logic [10:0] dp_addr,
    output logic        dp_we,
    output logic  [7:0] dp_wdata,
    input  logic  [7:0] dp_rdata,       // the clock after dp_addr
    input  logic        mcu_irq,        // bit 17, one clock

    // hps_io's RTC: BCD seconds, minutes, hours, date, month, year, and weekday 1-7
    input  logic [55:0] rtc,

    // the host's port on the NVRAM (the .nvm file, ioctl index 4), in bytes in MAME's file order:
    // its share is a u32 array saved little-endian, so byte j is bits 8(j%4)+7:8(j%4) of dword
    // j/4 as the CPU sees it. Read data the clock after the address.
    input  logic [13:0] nv_addr,
    input  logic        nv_we,
    input  logic  [7:0] nv_wdata,
    output logic  [7:0] nv_rdata,
    output logic        nv_written,     // one clock per CPU write

    // the DMA engine, on clk2x (hng64_dma.sv). go and done are toggles.
    output logic [31:0] dma_src,
    output logic [31:0] dma_dst,
    output logic [31:0] dma_count,      // dwords
    output logic        dma_go,
    input  logic        dma_done,

    // the video block's CPU port, in dwords
    output logic        v_req,
    output logic        v_we,
    output logic  [2:0] v_sel,          // 0 sprites, 1 sprite regs, 2 video regs, 3 palette, 4 tcram
    output logic [13:0] v_addr,
    output logic  [3:0] v_be,
    output logic [31:0] v_wdata,
    input  logic        v_ack,
    input  logic [31:0] v_rdata,

    output logic  [7:0] fbcontrol [0:3],    // m_fbcontrol; [0] picks the video's background
    output logic [31:0] fbscroll,
    output logic  [7:0] texwrap [0:31],

    // the display list, held in hng64_3d: a write of a u32 (two u16 entries), and the upload.
    // dl_busy holds a write back while an upload's copy runs, dl_upbusy an upload until a slot is
    // free; dl_full holds interrupt 3 back until the queue has a free slot again (docs/HACKS.md).
    output logic        dl_we,
    output logic  [6:0] dl_addr,
    output logic  [3:0] dl_be,
    output logic [31:0] dl_wdata,
    output logic        dl_up,
    input  logic        dl_busy,
    input  logic        dl_upbusy,
    input  logic        dl_full,
    // the sound bridge (hng64_sndbridge): the main CPU's latches, one-clock pulses for a write
    // raising interrupt 5 and for a write to the sound CPU enable, and the process's replies
    output logic [15:0] snd_main0,
    output logic [15:0] snd_main1,
    output logic        snd_irq,
    output logic        snd_en,
    output logic [15:0] snd_en_cmd,
    input  logic        snd_live,
    input  logic [15:0] snd_rep0,
    input  logic [15:0] snd_rep1,
    output logic        dbg_mcu_en_0c,  // m_mcu_en == 0x0c, for the bench
    output logic [31:0] dbg_irq_pending,
    output logic  [4:0] dbg_irq_level,
    // the stp revision's readback (HyperNG64.sv, ISSP M): a read of the v_* port between CPU
    // requests. dbg_rd toggles to ask; dbg_rdone follows it once dbg_rdata holds the word.
    input  logic        dbg_rd,
    input  logic  [2:0] dbg_sel,
    input  logic [13:0] dbg_addr,
    output logic        dbg_rdone,
    output logic [31:0] dbg_rdata
);

    localparam logic [2:0] V_SPR = 3'd0, V_SPRREG = 3'd1, V_VREG = 3'd2, V_PAL = 3'd3,
                           V_TCRAM = 3'd4;

    // ---- decode -----------------------------------------------------------------------------------
    typedef enum logic [4:0] {
        D_NONE, D_SYS, D_IRQC, D_DMAC, D_RTC, D_MCUIRQ, D_NVRAM, D_DP,
        D_SPR, D_CLR_EVEN, D_CLR_ODD, D_SPRREG, D_VREG, D_PAL, D_TCRAM,
        D_DL, D_DLUP, D_DLVREG, D_FBCTL, D_FBSCROLL, D_TEXWRAP, D_SNDCOM, D_SNDEN, D_COM
    } dev_t;

    function automatic dev_t decode(input logic [31:0] a);
        if      (a >= 32'h1f70_0000 && a < 32'h1f70_1100) decode = D_SYS;
        else if (a >= 32'h1f70_1100 && a < 32'h1f70_1120) decode = D_IRQC;
        else if (a >= 32'h1f70_1200 && a < 32'h1f70_1280) decode = D_DMAC;
        else if (a >= 32'h1f70_2100 && a < 32'h1f70_2180) decode = D_RTC;
        else if (a == 32'h1f70_21c4)                      decode = D_MCUIRQ;
        else if (a >= 32'h1f80_0000 && a < 32'h1f80_4000) decode = D_NVRAM;
        else if (a >= 32'h1f80_8000 && a < 32'h1f80_8800) decode = D_DP;
        else if (a >= 32'h2000_0000 && a < 32'h2000_c000) decode = D_SPR;
        else if (a >= 32'h2000_d800 && a < 32'h2000_e400) decode = D_CLR_EVEN;
        else if (a >= 32'h2000_e400 && a < 32'h2000_f000) decode = D_CLR_ODD;
        else if (a >= 32'h2001_0000 && a < 32'h2001_0014) decode = D_SPRREG;
        else if (a >= 32'h2019_0000 && a < 32'h2019_0038) decode = D_VREG;
        else if (a >= 32'h2020_0000 && a < 32'h2020_4000) decode = D_PAL;
        else if (a >= 32'h2020_8000 && a < 32'h2020_8060) decode = D_TCRAM;
        else if (a >= 32'h2030_0000 && a < 32'h2030_0200) decode = D_DL;
        else if (a == 32'h2030_0200)                      decode = D_DLUP;
        else if (a == 32'h2030_0218)                      decode = D_DLVREG;
        else if (a == 32'h3000_0000)                      decode = D_FBCTL;
        else if (a == 32'h3000_0008)                      decode = D_FBSCROLL;
        else if (a >= 32'h3000_0010 && a < 32'h3000_0030) decode = D_TEXWRAP;
        else if (a >= 32'h6800_0000 && a < 32'h6800_0010) decode = D_SNDCOM;
        else if (a >= 32'h6f00_0000 && a < 32'h6f00_0004) decode = D_SNDEN;
        else if (a >= 32'hc000_0000 && a < 32'hc000_1008) decode = D_COM;
        else                                              decode = D_NONE;
    endfunction

    // ---- the request, latched -------------------------------------------------------------------------
    logic [31:0] a, wd;
    logic  [3:0] be;
    logic        we;
    dev_t        dev;

    // MAME's COMBINE_DATA with a big-endian mem_mask: be[3] is bits 31:24
    function automatic logic [31:0] combine(input logic [31:0] old, input logic [31:0] d,
                                            input logic [3:0] lanes);
        for (int k = 0; k < 4; k++) combine[8*k +: 8] = lanes[k] ? d[8*k +: 8] : old[8*k +: 8];
    endfunction

    // the latched write merged over the registers it can land on
    logic [31:0] dma_len_reg;
    logic [15:0] main_latch0, main_latch1;
    wire  [31:0] len_new   = combine(dma_len_reg, wd, be);
    wire  [31:0] latch_new = combine({main_latch0, main_latch1}, wd, be);
    assign snd_main0 = main_latch0;
    assign snd_main1 = main_latch1;
    wire   [2:0] tw_i      = 3'(a[5:2] - 4'd4);        // 0x30000010 is word 0

    // ---- system registers, NVRAM, network RAM: dword RAMs with byte enables ---------------------------
    // hng64_bram: written as arrays of 1,088 and 1,026 words these were built from 68,000 registers
    logic [31:0] sys_q, nv_q, com_q;

    wire [10:0] sys_i = 11'((a - 32'h1f70_0000) >> 2);
    wire [11:0] nv_i  = a[13:2];
    wire [10:0] com_i = 11'((a - 32'hc000_0000) >> 2);
    logic       mem_we;                 // one clock, from the state machine

    hng64_bram #(.AW(11), .DW(32), .WORDS(1088)) u_sys (
        .a_clk(clk), .a_addr(sys_i), .a_be((mem_we && dev == D_SYS) ? be : 4'd0), .a_wdata(wd),
        .a_rdata(sys_q),
        .b_clk(clk), .b_addr(11'd0), .b_rdata());

    // one byte-lane RAM each, so the host's byte port is a plain second port (all 0 at power-up:
    // nvram_device::DEFAULT_ALL_0)
    logic [7:0] nv_lane_q [4];
    genvar gk;
    generate
    for (gk = 0; gk < 4; gk++) begin : g_nv
        hng64_tdpram #(.AW(12), .DW(8)) u_lane (
            .a_clk(clk), .a_addr(nv_i), .a_we(mem_we && dev == D_NVRAM && be[gk]),
            .a_wdata(wd[8*gk +: 8]), .a_rdata(nv_q[8*gk +: 8]),
            .b_clk(clk), .b_addr(nv_addr[13:2]), .b_we(nv_we && nv_addr[1:0] == 2'(gk)),
            .b_wdata(nv_wdata), .b_rdata(nv_lane_q[gk]));
    end
    endgenerate
    logic [1:0] nv_lane;
    always_ff @(posedge clk) begin
        nv_lane    <= nv_addr[1:0];
        nv_written <= mem_we && dev == D_NVRAM;
    end
    assign nv_rdata = nv_lane_q[nv_lane];

    hng64_bram #(.AW(11), .DW(32), .WORDS(1026)) u_com (
        .a_clk(clk), .a_addr(com_i), .a_be((mem_we && dev == D_COM) ? be : 4'd0), .a_wdata(wd),
        .a_rdata(com_q),
        .b_clk(clk), .b_addr(11'd0), .b_rdata());

    // MAME's comhack (hng64.cpp comhack_callback): 400,000,000 of its 50 MHz CPU clocks after reset,
    // 500,000,000 clk1x, the word at 0xc0001000 gets bit 0, the network id the drive sets' network
    // check waits for, as the KL5C80 would answer (MAME_KLUDGES.md). It is MAME's |= on RAM: read
    // ORed with com_hack, which a CPU write to that byte clears, so a later write stands.
    logic [28:0] com_hack_cnt;
    logic        com_hack, com_at_hack;
    always_ff @(posedge clk) begin
        com_at_hack <= com_i == 11'h400;
        if (reset) begin
            com_hack_cnt <= '0;
            com_hack     <= 1'b0;
        end else begin
            if (com_hack_cnt != 29'd500_000_000) com_hack_cnt <= com_hack_cnt + 1'd1;
            if (com_hack_cnt == 29'd499_999_999) com_hack <= 1'b1;
            if (mem_we && dev == D_COM && com_i == 11'h400 && be[0]) com_hack <= 1'b0;
        end
    end

    // ---- interrupt controller (set_irq, hng64.cpp:1871) -------------------------------------------------
    logic [31:0] irq_pending;
    logic  [4:0] irq_level;
    logic        irq_ack;               // a write to 0x1c, this clock
    logic [12:0] fifo3d_cnt;            // the 3D FIFO timer, 0 when idle

    wire  [31:0] irq_set = {14'd0, mcu_irq, 5'd0, net_irq, 7'd0,
                            (fifo3d_cnt == 13'd1), 1'b0, raster_irq, vblank_irq};
    wire  [31:0] irq_next = (irq_ack ? (irq_pending & ~combine(32'd0, wd, be)) : irq_pending)
                          | irq_set;

    // m_irq_level is the lowest pending bit, and holds its last value once nothing is pending
    function automatic logic [4:0] lowest(input logic [31:0] v);
        lowest = 5'd0;
        for (int i = 30; i >= 0; i--) if (v[i]) lowest = 5'(i);
    endfunction

    always_ff @(posedge clk) begin
        if (reset) begin
            irq_pending <= 32'd0;
            irq_level   <= 5'd0;
        end else begin
            irq_pending <= irq_next;
            if (irq_next[30:0] != 31'd0) irq_level <= lowest(irq_next);
        end
    end

    // MAME's loop stops at bit 30, so bit 31 alone asserts the line with a stale level
    assign cpu_irq = (irq_pending != 32'd0);

    // ---- RTC, MSM6242 (msm6242.cpp) --------------------------------------------------------------------
    logic [3:0] rtc_cd, rtc_ce, rtc_cf;

    // 12-hour mode (CF bit 2 clear): the hour as BCD 1-12, and whether it is PM
    function automatic logic [8:0] hour12(input logic [7:0] h);   // {pm, BCD 01-12}
        logic [7:0] b;
        case (h)
            8'h00, 8'h12: b = 8'h12;
            8'h13: b = 8'h01; 8'h14: b = 8'h02; 8'h15: b = 8'h03; 8'h16: b = 8'h04;
            8'h17: b = 8'h05; 8'h18: b = 8'h06; 8'h19: b = 8'h07; 8'h20: b = 8'h08;
            8'h21: b = 8'h09; 8'h22: b = 8'h10; 8'h23: b = 8'h11;
            default: b = h;
        endcase
        hour12 = {h >= 8'h12, b};
    endfunction

    wire [8:0] h12 = hour12(rtc[23:16]);

    function automatic logic [3:0] rtc_read(input logic [3:0] r);
        case (r)
            4'h0: rtc_read = rtc[3:0];
            4'h1: rtc_read = rtc[7:4];
            4'h2: rtc_read = rtc[11:8];
            4'h3: rtc_read = rtc[15:12];
            4'h4: rtc_read = rtc_cf[2] ? rtc[19:16] : h12[3:0];
            4'h5: rtc_read = rtc_cf[2] ? rtc[23:20] : {1'b0, h12[8], 1'b0, h12[4]};
            4'h6: rtc_read = rtc[27:24];
            4'h7: rtc_read = rtc[31:28];
            4'h8: rtc_read = rtc[35:32];
            4'h9: rtc_read = rtc[39:36];
            4'ha: rtc_read = rtc[43:40];
            4'hb: rtc_read = rtc[47:44];
            4'hc: rtc_read = rtc[51:48] - 4'd1;         // day of week, 0-6
            4'hd: rtc_read = rtc_cd;                    // BUSY and IRQ FLAG never set: HACKS.md
            4'he: rtc_read = rtc_ce;
            default: rtc_read = rtc_cf;
        endcase
    endfunction

    // the block is 32 dwords; the odd ones carry registers 0-15 (rtc_r, hng64.cpp:788)
    wire [3:0] rtc_reg = a[6:3];
    wire       rtc_odd = a[2];

    // ---- state machine ------------------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE, S_MEM, S_MEM2, S_DP, S_DPLAST, S_DPLAST2, S_VWAIT, S_CLR, S_DMA, S_SPIN, S_ACK,
        S_DBG
    } state_t;
    state_t st;

    logic [31:0] result;
    logic  [1:0] lane;                  // dual-port byte loop: 3 is addr+0
    logic        dp_pending, dp_pend2;
    logic  [1:0] dp_lane_q, dp_lane_q2;
    logic  [3:0] clr_i;                 // sprite-clear writes done
    logic  [8:0] spin;                  // the mailbox's 5 us
    logic  [1:0] dbg_rd_s;
    logic        dbg_seen = 1'b0;
    logic        io_req_q = 1'b0;           // a CPU request that arrived during S_DBG
    initial dbg_rdone = 1'b0;

    logic  [7:0] mcu_en;                // m_mcu_en
    logic        raster_half;           // m_irq_pos_half
    logic [31:0] raster_pos1;
    logic [10:0] int0_cnt;              // tempio_irqoff: INT0 held this many clocks
    logic [15:0] sound_data;

    assign mcu_int0       = (int0_cnt != 11'd0);
    assign dbg_mcu_en_0c  = (mcu_en == 8'h0c);
    assign dbg_irq_pending = irq_pending;
    assign dbg_irq_level   = irq_level;

    // The sprite clears (sprite_clear_even_w / _odd_w, hng64.cpp:1075): each write clears four
    // dwords of one sprite or of two, 0x40 bytes a pair. The odd form skips +0x0c on purpose
    // (MAME_KLUDGES.md), and tests bits 0-15 for its second sprite where the even form tests
    // only bits 8-15.
    logic [13:0] clr_list [0:7];
    logic  [3:0] clr_count;

    always_comb begin
        logic        odd, first, second;
        logic [13:0] base;
        odd    = (dev == D_CLR_ODD);
        base   = 14'(((a - (odd ? 32'h2000_e400 : 32'h2000_d800)) >> 2) << 4);
        first  = be[3] || be[2];
        second = odd ? (be[1] || be[0]) : be[1];
        clr_count = 4'd0;
        for (int i = 0; i < 8; i++) clr_list[i] = 14'd0;
        if (odd) begin
            if (first) begin
                clr_list[clr_count[2:0]] = base + 14'h01; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h05; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h07; clr_count = clr_count + 4'd1;
            end
            if (second) begin
                clr_list[clr_count[2:0]] = base + 14'h09; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h0d; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h0f; clr_count = clr_count + 4'd1;
            end
        end else begin
            if (first) begin
                clr_list[clr_count[2:0]] = base + 14'h00; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h02; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h04; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h06; clr_count = clr_count + 4'd1;
            end
            if (second) begin
                clr_list[clr_count[2:0]] = base + 14'h08; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h0a; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h0c; clr_count = clr_count + 4'd1;
                clr_list[clr_count[2:0]] = base + 14'h0e; clr_count = clr_count + 4'd1;
            end
        end
    end

    logic clr_busy;                     // a clear is on the video port, waiting for its ack
    logic dp_hack_q, dp_hack_q2;        // the byte in flight is at 0x600

    always_ff @(posedge clk) begin
        io_ack   <= 1'b0;
        mem_we   <= 1'b0;
        irq_ack  <= 1'b0;
        dp_we    <= 1'b0;
        v_req    <= 1'b0;
        dp_pending <= 1'b0;
        // a dual-port read's byte is on dp_rdata two clocks after it is issued: dp_addr is a
        // register here and the RAM registers it again (hng64_tdpram)
        dp_pend2   <= dp_pending;
        dp_lane_q2 <= dp_lane_q;
        dp_hack_q2 <= dp_hack_q;

        if (int0_cnt != 11'd0) int0_cnt <= int0_cnt - 11'd1;
        dbg_rd_s <= {dbg_rd_s[0], dbg_rd};
        dl_we    <= 1'b0;
        dl_up    <= 1'b0;
        snd_irq  <= 1'b0;
        snd_en   <= 1'b0;
        // held at 2 while the queue is full, so interrupt 3 waits for a free slot
        if (fifo3d_cnt != 13'd0 && !(fifo3d_cnt == 13'd2 && dl_full)) fifo3d_cnt <= fifo3d_cnt - 13'd1;

        if (reset) begin
            st <= S_IDLE;
            mcu_en <= 8'd0;
            raster_half <= 1'b0;
            raster_pos  <= 32'hffff_ffff;
            raster_pos1 <= 32'hffff_ffff;
            int0_cnt <= 11'd0;
            fifo3d_cnt <= 13'd0;
            fbscroll   <= 32'd0;
            for (int i = 0; i < 32; i++) texwrap[i] <= 8'h08;   // MAME's machine_start (hng64.cpp:2179)
            rtc_cd <= 4'h0; rtc_ce <= 4'h6; rtc_cf <= 4'h4;   // msm6242 device_start
            main_latch0 <= 16'd0; main_latch1 <= 16'd0; sound_data <= 16'd0;
            snd_en_cmd <= 16'd0;
            dma_go <= 1'b0;
        end else begin
            case (st)
                S_IDLE: if (io_req || io_req_q) begin
                    io_req_q <= 1'b0;
                    a   <= io_addr;
                    we  <= io_we;
                    be  <= io_be;
                    wd  <= io_wdata;
                    dev <= decode(io_addr);
                    result <= 32'd0;
                    st  <= S_MEM;
                end else if (dbg_rd_s[1] != dbg_seen) begin
                    dbg_seen <= dbg_rd_s[1];
                    v_req    <= 1'b1;
                    v_we     <= 1'b0;
                    v_sel    <= dbg_sel;
                    v_addr   <= dbg_addr;
                    v_be     <= 4'hf;
                    st       <= S_DBG;
                end

                // io_req is one clock: one that lands here is taken from S_IDLE
                S_DBG: begin
                    if (io_req) io_req_q <= 1'b1;
                    if (v_ack) begin
                        dbg_rdata <= v_rdata;
                        dbg_rdone <= dbg_seen;
                        st        <= S_IDLE;
                    end
                end

                // the RAM reads have landed by the next clock; everything else decides here
                S_MEM: begin
                    st <= S_ACK;
                    case (dev)
                        D_SYS: begin
                            if (we) begin
                                mem_we <= 1'b1;
                                case (a[12:0])
                                    13'h100c: begin                     // raster_irq_pos_w
                                        if (raster_half) raster_pos1 <= wd;
                                        else             raster_pos  <= wd;
                                        raster_half <= !raster_half;
                                    end
                                    13'h1084: mcu_en <= wd[7:0];        // MIPS->MCU latch
                                    default: ;
                                endcase
                            end else begin
                                st <= S_MEM2;
                            end
                        end

                        D_IRQC: begin
                            if (we) irq_ack <= (a[4:0] == 5'h1c);
                            else    result  <= (a[4:0] == 5'h04) ? {27'd0, irq_level} : 32'hffff_ffff;
                        end

                        D_DMAC: begin
                            if (we) begin
                                case (a[6:0])
                                    7'h04: dma_src <= combine(dma_src, wd, be);
                                    7'h14: dma_dst <= combine(dma_dst, wd, be);
                                    7'h24: begin
                                        // do_dma: dwords while m_dma_len >= 0, so len + 1 of them
                                        dma_len_reg <= len_new;
                                        dma_count   <= len_new + 32'd1;
                                        if (!len_new[31]) begin
                                            dma_go <= !dma_go;
                                            st <= S_DMA;
                                        end
                                    end
                                    default: ;
                                endcase
                            end else begin
                                result <= (a[6:0] == 7'h54) ? 32'd0 : 32'hffff_ffff;
                            end
                        end

                        D_RTC: begin
                            if (!rtc_odd) begin
                                result <= 32'hffff_ffff;
                            end else if (we) begin
                                case (rtc_reg)
                                    4'hd: rtc_cd <= (wd[3:0] & 4'h9) | (rtc_cd & 4'h6);
                                    4'he: rtc_ce <= wd[3:0];
                                    4'hf: rtc_cf <= (!wd[0] && rtc_cf[0])
                                                  ? ((rtc_cf & 4'hb) | (wd[3:0] & 4'h4))
                                                  : ((wd[3:0] & 4'hb) | (rtc_cf & 4'h4));
                                    default: ;                          // time: HACKS.md
                                endcase
                            end else begin
                                result <= {27'd0, (rtc_reg == 4'hd), rtc_read(rtc_reg)};
                            end
                        end

                        D_MCUIRQ: if (we && (be[3] || be[2])) int0_cnt <= 11'd1250;

                        D_NVRAM, D_COM: begin
                            if (we) mem_we <= 1'b1;
                            else    st <= S_MEM2;
                        end

                        D_DP: begin
                            lane <= 2'd3;
                            st <= S_DP;
                        end

                        D_SPR, D_SPRREG, D_VREG, D_PAL, D_TCRAM: begin
                            if (dev == D_TCRAM && !we && a[6:0] == 7'h48) begin
                                // tcram_r: the VBLANK port is all 32 bits; sams64's palette
                                // copy waits for lhu 0x2020804a == 0xffff
                                result <= {32{vblank}};
                            end else begin
                                v_req  <= 1'b1;
                                v_we   <= we;
                                v_be   <= be;
                                v_wdata <= wd;
                                case (dev)
                                    D_SPR:    begin v_sel <= V_SPR;    v_addr <= a[15:2]; end
                                    D_SPRREG: begin v_sel <= V_SPRREG; v_addr <= {9'd0, a[6:2]}; end
                                    D_VREG:   begin v_sel <= V_VREG;   v_addr <= {9'd0, a[6:2]}; end
                                    D_PAL:    begin v_sel <= V_PAL;    v_addr <= {2'd0, a[13:2]}; end
                                    default:  begin v_sel <= V_TCRAM;  v_addr <= {9'd0, a[6:2]}; end
                                endcase
                                st <= S_VWAIT;
                            end
                        end

                        D_CLR_EVEN, D_CLR_ODD: begin
                            if (we) begin
                                clr_i <= 4'd0;
                                clr_busy <= 1'b0;
                                st <= S_CLR;
                            end
                        end

                        D_DL: if (we) begin                             // dl_w: u16 halves
                            if (dl_busy) st <= S_MEM;
                            else begin
                                dl_we    <= 1'b1;
                                dl_addr  <= a[8:2];
                                dl_be    <= be;
                                dl_wdata <= wd;
                            end
                        end

                        D_DLUP: if (we) begin
                            if (dl_upbusy) st <= S_MEM;
                            else begin
                                dl_up      <= 1'b1;
                                fifo3d_cnt <= 13'd5120;                 // 0x200 * 8 CPU cycles
                            end
                        end

                        D_DLVREG: ;                                     // reads 0

                        D_FBCTL: begin
                            if (we) begin
                                for (int k = 0; k < 4; k++) if (be[k]) fbcontrol[3 - k] <= wd[8*k +: 8];
                            end else begin
                                result <= {fbcontrol[0], fbcontrol[1], fbcontrol[2], fbcontrol[3]};
                            end
                        end

                        D_FBSCROLL: if (we) fbscroll <= combine(fbscroll, wd, be);   // write-only

                        D_TEXWRAP: begin
                            if (we) begin
                                for (int k = 0; k < 4; k++)
                                    if (be[k]) texwrap[{tw_i, 2'(3 - k)}] <= wd[8*k +: 8];
                            end else begin
                                result <= {texwrap[{tw_i, 2'd0}], texwrap[{tw_i, 2'd1}],
                                           texwrap[{tw_i, 2'd2}], texwrap[{tw_i, 2'd3}]};
                            end
                        end

                        // main_sound_comms (hng64.cpp:1137), 16 bits wide, with the stand-in for
                        // the missing sound CPU: status 0x0080, and the data latch holding the
                        // command before the last trigger (HARDWARE_NOTES "Sound mailbox")
                        D_SNDCOM: begin
                            if (we) begin
                                case (a[3:2])
                                    2'd0: begin
                                        main_latch0 <= latch_new[31:16];
                                        main_latch1 <= latch_new[15:0];
                                    end
                                    2'd2: if ((be[3] || be[2]) && wd[16]) begin
                                        sound_data <= main_latch0;
                                        snd_irq <= 1'b1;
                                        spin <= 9'd313;                 // spin_until_time(5 us)
                                        st <= S_SPIN;
                                    end
                                    default: ;
                                endcase
                            end else begin
                                case (a[3:2])
                                    2'd0: result <= {main_latch0, main_latch1};
                                    2'd1: result <= snd_live ? {snd_rep0, snd_rep1}
                                                             : {sound_data, 16'h0080};
                                    default: result <= 32'd0;
                                endcase
                            end
                        end

                        // soundcpu_enable_w (hng64_a.cpp): the upper half is the command; MAME
                        // maps no read
                        D_SNDEN: if (we && (be[3] || be[2])) begin
                            snd_en     <= 1'b1;
                            snd_en_cmd <= wd[31:16];
                        end

                        default: ;                                      // unmapped: reads 0
                    endcase
                end

                S_MEM2: begin
                    result <= (dev == D_SYS) ? ((a[12:0] == 13'h001c) ? 32'd0
                                              : (a[12:0] == 13'h1084) ? 32'd2 : sys_q)
                            : (dev == D_NVRAM) ? nv_q : (com_q | {31'd0, com_hack && com_at_hack});
                    st <= S_ACK;
                end

                // dualport_r / dualport_w (hng64.cpp:1017): one byte per enabled lane, addr+0 first.
                // A read issued here has its byte on dp_rdata two clocks later (dp_pend2). Taking it
                // one clock later read the previous address's byte: every lane one place late on
                // hardware, the BIOS's I/O sequence 1 failed and its RAM test flagged the whole RAM.
                // No bench compared dual-port reads; io_tb now reads them back.
                S_DP: begin
                    // m_no_machine_error_code at 0x600, unless the MIPS has said 0x0c
                    if (dp_pend2)
                        result[8*dp_lane_q2 +: 8] <= (dp_hack_q2 && mcu_en != 8'h0c)
                                                   ? no_machine_error_code : dp_rdata;
                    if (be[lane]) begin
                        dp_addr    <= {a[10:2], 2'(3 - lane)};
                        dp_wdata   <= wd[8*lane +: 8];
                        dp_we      <= we;
                        dp_pending <= !we;
                        dp_lane_q  <= lane;
                        dp_hack_q  <= ({a[10:2], 2'(3 - lane)} == 11'h600);
                    end
                    if (lane == 2'd0) st <= we ? S_ACK : S_DPLAST;
                    else lane <= lane - 2'd1;
                end

                // the loop's last two reads land after it
                S_DPLAST, S_DPLAST2: begin
                    if (dp_pend2)
                        result[8*dp_lane_q2 +: 8] <= (dp_hack_q2 && mcu_en != 8'h0c)
                                                   ? no_machine_error_code : dp_rdata;
                    st <= (st == S_DPLAST) ? S_DPLAST2 : S_ACK;
                end

                S_VWAIT: if (v_ack) begin
                    if (!we) result <= v_rdata;
                    st <= S_ACK;
                end

                S_CLR: begin
                    if (clr_busy) begin
                        if (v_ack) clr_busy <= 1'b0;
                    end else if (clr_i == clr_count) begin
                        st <= S_ACK;
                    end else begin
                        v_req    <= 1'b1;
                        v_we     <= 1'b1;
                        v_sel    <= V_SPR;
                        v_addr   <= clr_list[clr_i[2:0]];
                        v_be     <= 4'hf;
                        v_wdata  <= 32'd0;
                        clr_i    <= clr_i + 4'd1;
                        clr_busy <= 1'b1;
                    end
                end

                // the copy runs on clk2x; the write is not acknowledged until it is done, so
                // the CPU sees it as atomic, as MAME's is
                S_DMA: if (dma_done == dma_go) begin
                    dma_src     <= dma_src + {dma_count[29:0], 2'b00};
                    dma_dst     <= dma_dst + {dma_count[29:0], 2'b00};
                    dma_len_reg <= 32'hffff_ffff;
                    st <= S_ACK;
                end

                S_SPIN: begin
                    if (spin == 9'd0) st <= S_ACK;
                    else spin <= spin - 9'd1;
                end

                default: begin                                          // S_ACK
                    io_ack   <= 1'b1;
                    io_rdata <= result;
                    st <= S_IDLE;
                end
            endcase
        end
    end

endmodule
