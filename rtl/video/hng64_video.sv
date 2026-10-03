// SPDX-License-Identifier: GPL-3.0-or-later
//
// The video block: four tilemap line engines, the sprite line engine, the 3D buffer's line
// (hng64_fb3d), their line buffers and the mixer.
//
// The five engines run at the same time, not one after another: each fills its own line buffer,
// and the mixer reads all five when they are done. The four tilemap engines share one tile-VRAM
// port and one tile-ROM port, so each port has a round-robin arbiter in front of it and a queue
// behind it that remembers which engine each reply belongs to - the memories answer in order, so
// a queue of requester numbers is enough to route them.
//
// The line buffers are double-buffered and the block runs a line ahead: while the engines fill
// one bank for line N, the mixer reads the other and emits line N-1. So a line costs the longer
// of the two, not their sum, and the first line_start of a frame produces no pixels.
//
// Reading a line ahead means a mid-screen write to tile VRAM or the registers takes effect one
// line later than MAME would show it. Real hardware fills a line buffer during the previous
// scanline too, so this is closer to the board than to MAME; it is in docs/HACKS.md either way.
//
// The sprite line buffer is cleared as the mixer reads it, one cycle behind the read, rather
// than in a pass of its own: the sprite engine writes only the pixels it draws, so the buffer
// has to start each line empty, and a separate clear would cost 512 cycles of the line. The
// bank the mixer just read becomes the bank the engines write next, so it is clean when needed.
//
// Per-line cost, and what still exceeds the budget: docs/phase1_video.md.

module hng64_video (
    input  logic        clk,
    input  logic        reset,

    input  logic        frame_start,        // vblank start: the sprite list is snapshotted here
    input  logic        line_start,
    input  logic  [5:0] dbg_layer_off,      // the OSD's debug page: tilemaps 0-3, sprites, 3D; 0 = on
    input  logic  [8:0] line,
    output logic        busy,

    input  logic [31:0] videoregs [0:13],
    input  logic [31:0] tcram [0:23],
    input  logic [31:0] spriteregs0,
    input  logic [31:0] spriteregs1,
    input  logic [23:0] bg_rgb,
    input  logic        screen_dis,
    input  logic [25:0] scr_half,           // half the scrtile region; see the reorder below

    // Every port holds its request until `ready`: the memories below arbitrate too, and a
    // request this block has made may not be taken on the cycle it is made.
    output logic [16:0] vram_addr,          // tile VRAM in SDRAM, u32 words, read live per line
    output logic        vram_rd,
    input  logic        vram_ready,
    input  logic [31:0] vram_data,
    input  logic        vram_valid,

    output logic [25:0] srom_addr,          // "scrtile", in the region as the .mra loads it
    output logic        srom_rd,
    input  logic        srom_ready,
    input  logic [63:0] srom_data,
    input  logic        srom_valid,

    output logic [13:0] sram_addr,          // sprite list
    output logic        sram_rd,
    input  logic [31:0] sram_data,

    output logic [25:0] prom_addr,          // "sprtile"
    output logic        prom_rd,
    input  logic        prom_ready,
    input  logic [63:0] prom_data,
    input  logic        prom_valid,

    output logic [11:0] pal_a,
    input  logic [31:0] pal_d,

    // the 3D buffer (hng64_fb3d)
    input  logic  [9:0] vis_y0,
    input  logic  [9:0] vis_h,
    input  logic  [7:0] fbcontrol0,
    input  logic  [7:0] fbcontrol2,
    input  logic [31:0] fbscroll,
    input  logic        show_valid,
    input  logic        show_plane,
    output logic        shown_valid,
    output logic        shown_plane,
    input  logic [27:0] plane_base [0:1],
    output logic [27:0] d3_addr,
    output logic        d3_rd,
    input  logic        d3_ready,
    input  logic [63:0] d3_data,
    input  logic        d3_valid,

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [23:0] px_rgb,

    // sim only: what each engine wrote to its line buffer this line
    output logic  [7:0] dbg_busy,   // {line pass, sprites, 3D fetch, tilemaps 3:0, mixer}
    output logic [48:0] dbg_spr,    // hng64_sprite's dbg_q
    // the tilemap engines and their arbiters, for probe Q: {engine 1's dbg_q, engine 0's,
    // vq_w, vq_r, rq_w, rq_r, rq_n, e_vrd, e_rrd, e_run, e_busy, e_wait, e_pend, e_ph}
    output logic [185:0] dbg_tq,
    output logic  [59:0] dbg_sc,    // {mixed, passed, emitted} sprite pixels, the last frame
    // the sprite engine's ports, for probe R: {line, line start, pixels 1 and 0, their x, their
    // writes, ROM reply word (as the engine takes it), reply valid, ready, request, address}
    output logic [154:0] dbg_rc,
    output logic  [5:0] dbg_we,         // [3:0] the tilemaps, [4] and [5] the sprites' two pixels
    output logic  [8:0] dbg_x [0:5],
    output logic [15:0] dbg_pix [0:5]
);

    logic [15:0] tileregs [0:3];
    logic [13:0] scrollbase [0:3];
    always_comb
        for (int tm = 0; tm < 4; tm++) begin
            tileregs[tm]   = tm[0] ? videoregs[2 + (tm >> 1)][15:0]
                                   : videoregs[2 + (tm >> 1)][31:16];
            scrollbase[tm] = (tm[0] ? videoregs[4 + (tm >> 1)][15:0]
                                    : videoregs[4 + (tm >> 1)][31:16]) & 14'h3fff;
        end

    // ---- the tilemap layers: two engines, two layers each ------------------------------------------
    // Engine e draws layer 2e and then layer 2e+1 of each line. The per-layer signals below are what
    // four engines had, for the line buffers; the VRAM and ROM arbiters below are per engine. A
    // layer's replies are all back before its engine moves on (busy falls only then). Four engines were 5,880 ALUTs in quartus_map. Per layer the
    // captures' worst line is 2,621 cycles (fatfurwa f2500, layer 3) and most are 600-900, against
    // 3,840 a line at full speed.
    logic  [3:0] tm_start, tm_busy, tm_we;
    logic  [8:0] tm_x [0:3];
    logic [15:0] tm_pix [0:3];

    // DDR3 hands over a granule with the byte at its lowest address in bits 7:0, as MiSTer's DDRAM
    // port does everywhere (the skill's ddr_rom_loading.md; hng64_mainmem and the BIOS copy use it
    // that way). The engines decode MAME's layouts from the other end, the lowest address in bits
    // 63:56, so the granule is reversed here, once, for both tile ROMs - as the Psikyo core's
    // gfxrom_byte_reorder.sv does for the same reason. sim/sys_tb found this: the engines' own
    // benches, and video_tb, each served granules the engines' way round.
    function automatic logic [63:0] reverse_bytes(input logic [63:0] v);
        for (int k = 0; k < 8; k++) reverse_bytes[8*k +: 8] = v[8*(7 - k) +: 8];
    endfunction

    wire [63:0] srom_msb = reverse_bytes(srom_data);
    wire [63:0] prom_msb = reverse_bytes(prom_data);

    logic  [1:0] e_start, e_busy, e_we, e_vrd, e_rrd;
    logic  [1:0] e_ph;                      // the layer of its pair engine e is on
    logic  [1:0] e_run, e_wait;             // e_wait: the clock an engine takes to raise busy
    logic  [1:0] e_pend;                    // the second layer starts next clock
    // the layer's registers, registered from e_ph: through the layer mux into the engine's pixel
    // path missed clk2x by 3.4 ns. e_ph is back at 0 between lines and settles a clock before the
    // second layer starts, so these are current when an engine starts.
    logic [15:0] e_tr [0:1];
    logic [13:0] e_sb [0:1];
    logic  [1:0] e_lay [0:1];
    always_ff @(posedge clk)
        for (int e = 0; e < 2; e++) begin
            e_tr[e]  <= tileregs[{e[0], e_ph[e]}];
            e_sb[e]  <= scrollbase[{e[0], e_ph[e]}];
            e_lay[e] <= {e[0], e_ph[e]};
        end
    logic [16:0] e_vaddr [0:1];
    logic [25:0] e_raddr [0:1];
    logic  [8:0] e_x [0:1];
    logic [15:0] e_pix [0:1];
    logic        vsel, rsel;                // the engine each arbiter picked (below)
    logic  [1:0] vgrant_e, rgrant_e, vdeliver_e, rdeliver_e;

    // Each engine takes the tile ROM's reply from its own register, a clock late: from the DDR3
    // arbiter's one reply register (hng64_ddram's c_data) into both engines' word queues missed
    // clk2x by 1.7 ns. preserve keeps the two copies apart so each sits by its engine.
    (* preserve *) logic [63:0] e_rdata [0:1];
    logic [1:0] e_rval;
    always_ff @(posedge clk) begin
        e_rval <= rdeliver_e;
        for (int e = 0; e < 2; e++) e_rdata[e] <= srom_msb;
    end

    logic [67:0] e_dbg [0:1];

    genvar gtm;
    generate
        for (gtm = 0; gtm < 2; gtm++) begin : g_tm
            hng64_tilemap u_tm (
                .clk(clk), .reset(reset),
                .start(e_start[gtm]), .line(line), .tm_index(e_lay[gtm]), .busy(e_busy[gtm]),
                .tileregs(e_tr[gtm]), .scrollbase(e_sb[gtm]),
                .videoreg0(videoregs[0]), .videoreg1(videoregs[1]),
                .anim_mask(videoregs[11]), .anim_bits(videoregs[12]),
                .vram_addr(e_vaddr[gtm]), .vram_rd(e_vrd[gtm]), .vram_ready(vgrant_e[gtm]),
                .vram_data(vram_data), .vram_valid(vdeliver_e[gtm]),
                .rom_addr(e_raddr[gtm]), .rom_rd(e_rrd[gtm]), .rom_ready(rgrant_e[gtm]),
                .rom_data(e_rdata[gtm]), .rom_valid(e_rval[gtm]),
                .px_we(e_we[gtm]), .px_x(e_x[gtm]), .px_pix(e_pix[gtm]), .dbg_q(e_dbg[gtm]));
        end
    endgenerate

    always_comb begin
        tm_we  = 4'd0;
        for (int e = 0; e < 2; e++) begin
            tm_we[{e[0], e_ph[e]}]  = e_we[e];
            for (int k = 0; k < 2; k++) begin
                tm_x[2 * e + k]     = e_x[e];
                tm_pix[2 * e + k]   = e_pix[e];
                tm_busy[2 * e + k]  = e_run[e];
            end
        end
    end

    // a line's tm_start (all four bits together) starts each engine on its first layer, and the
    // second when the first is drawn; a disabled layer never raises busy
    always_ff @(posedge clk) begin
        e_start <= 2'd0;
        if (reset) begin
            e_run  <= 2'd0;
            e_wait <= 2'd0;
            e_pend <= 2'd0;
            e_ph   <= 2'd0;
        end else begin
            for (int e = 0; e < 2; e++) begin
                if (tm_start[0]) begin
                    e_run[e]   <= 1'b1;
                    e_start[e] <= 1'b1;
                    e_wait[e]  <= 1'b1;
                end else if (e_run[e]) begin
                    if (e_wait[e]) begin
                        e_wait[e] <= 1'b0;
                    end else if (e_pend[e]) begin
                        e_pend[e]  <= 1'b0;
                        e_start[e] <= 1'b1;
                        e_wait[e]  <= 1'b1;
                    end else if (!e_busy[e] && !e_start[e]) begin
                        if (!e_ph[e]) begin
                            e_ph[e]   <= 1'b1;
                            e_pend[e] <= 1'b1;
                        end else begin
                            e_ph[e]  <= 1'b0;
                            e_run[e] <= 1'b0;
                        end
                    end
                end
            end
        end
    end

    // MAME's init_reorder_gfx (hng64.cpp:1814) interleaves the region's two halves in 32-byte
    // units before decoding, and the engines address the decoded region. An .mra cannot express
    // that - the HPS writes DDR3 directly, and no `<interleave>` works in 32-byte chunks - so the
    // image is stored as the ROMs load and the address is translated here instead: a decoded
    // chunk is even for the upper half and odd for the lower, so dropping bit 5 gives the offset
    // within the half.
    wire [25:0] scr_dec = e_raddr[rsel];
    // scrtile is a power of two (scripts/build_mra.py refuses one that is not) and the offset in a
    // half is below scr_half, so adding scr_half is setting its bit: from the engines' requests
    // through a 26-bit add into the queue it missed clk2x by 1.3 ns
    wire [25:0] scr_raw = {1'b0, scr_dec[25:6], scr_dec[4:0]} | (scr_dec[5] ? 26'd0 : scr_half);

    // ---- round-robin arbiters between the two engines, and the queues that route replies back ---
    // Each engine bounds its own outstanding requests (16 tile words, 60 row words), so two of
    // them cannot outrun these queues. A queue entry is the engine; its layer is the one it is on,
    // which cannot change while it has replies outstanding.
    logic       vlast, rlast;
    // Tile ROM requests go to DDR3 from a two-entry queue, which takes an engine's request while
    // it has room (rq_n, a register): from an engine's request through the pick and the address
    // translation into the DDR3 issue missed clk2x by 2.1 ns, and from DDR3's grant back into an
    // engine by 1.9. Replies are tagged as requests enter it, so stay in order.
    // two entries and a read and a write pointer: a push writes its entry whatever the port does,
    // and a pop moves rq_rp (shifting a1 into a0 put the arbiter's ready in front of a0's 26
    // bits' select: 1.2 ns over clk2x)
    logic  [1:0] rq_n;
    logic [25:0] rq_e [0:1];
    logic        rq_rp, rq_wp;
    wire         rq_take = rq_n != 2'd2;
    wire         rq_push = rq_take && e_rrd != 2'd0;
    wire         rq_pop  = srom_ready;
    logic       vq [0:127];
    logic [7:0] vq_w, vq_r;
    // Each queue's head entry held in a register, refreshed every clock with the next one when a
    // reply takes this one: from the read pointer through the queue's RAM and its bypass into the
    // engines' valid it missed clk2x by 1.5 ns. An entry is written clocks before its reply.
    logic       vq_h, rq_h;
    logic [7:0] vq_r1;                      // vq_r + 1
    logic [8:0] rq_r1;                      // rq_r + 1
    logic       rq [0:255];
    logic [8:0] rq_w, rq_r;

    // The choice of whose request to pass on does not depend on whether the memory takes it -
    // that would be a loop - so the pick drives the port and the memory's `ready` decides which
    // engine sees its request accepted.

    always_comb begin
        vsel      = (e_vrd[0] && e_vrd[1]) ? !vlast : e_vrd[1];
        rsel      = (e_rrd[0] && e_rrd[1]) ? !rlast : e_rrd[1];
        vram_addr = e_vaddr[vsel];
        srom_addr = rq_e[rq_rp];
        vram_rd   = e_vrd != 2'd0;
        srom_rd   = rq_n != 2'd0;
        vgrant_e  = (vram_ready && vram_rd) ? (2'd1 << vsel) : 2'd0;
        rgrant_e  = (rq_take && e_rrd != 2'd0) ? (2'd1 << rsel) : 2'd0;
        vdeliver_e = vram_valid ? (2'd1 << vq_h) : 2'd0;
        rdeliver_e = srom_valid ? (2'd1 << rq_h) : 2'd0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            vlast <= 1'b1;
            rlast <= 1'b1;
            vq_w  <= 8'd0;
            vq_r  <= 8'd0;
            vq_r1 <= 8'd1;
            rq_w  <= 9'd0;
            rq_r  <= 9'd0;
            rq_r1 <= 9'd1;
            rq_n  <= 2'd0;
            rq_rp <= 1'b0;
            rq_wp <= 1'b0;
        end else begin
            if (rq_push) begin
                rq_e[rq_wp] <= scr_raw;
                rq_wp <= !rq_wp;
            end
            if (rq_pop) rq_rp <= !rq_rp;
            rq_n <= rq_n + 2'(rq_push) - 2'(rq_pop);
            if (vgrant_e != 2'd0) begin
                vq[vq_w[6:0]] <= vsel;
                vq_w  <= vq_w + 8'd1;
                vlast <= vsel;
            end
            if (vram_valid) begin
                vq_r  <= vq_r1;
                vq_r1 <= vq_r1 + 8'd1;
            end
            vq_h <= vq[vram_valid ? vq_r1[6:0] : vq_r[6:0]];
            if (rgrant_e != 2'd0) begin
                rq[rq_w[7:0]] <= rsel;
                rq_w  <= rq_w + 9'd1;
                rlast <= rsel;
            end
            if (srom_valid) begin
                rq_r  <= rq_r1;
                rq_r1 <= rq_r1 + 9'd1;
            end
            rq_h <= rq[srom_valid ? rq_r1[7:0] : rq_r[7:0]];
        end
    end

    assign dbg_tq = {e_dbg[1], e_dbg[0], vq_w, vq_r, rq_w, rq_r, rq_n, e_vrd, e_rrd,
                     e_run, e_busy, e_wait, e_pend, e_ph};

    // ---- the sprite engine, which has both its ports to itself -----------------------------------
    logic spr_start, spr_busy;
    logic  [1:0] spr_we;                    // [0] the even-x pixel, [1] the odd-x one
    logic  [1:0] spr_pbv;                   // probe S: the engine's pixels before its z-test
    logic        mix_spr_seen;
    logic  [8:0] spr_x [0:1];
    logic [15:0] spr_px [0:1];

    hng64_sprite u_spr (
        .clk(clk), .reset(reset),
        .frame_start(frame_start), .line_start(spr_start), .line(line), .busy(spr_busy),
        .spriteregs0(spriteregs0), .spriteregs1(spriteregs1),
        .ram_addr(sram_addr), .ram_rd(sram_rd), .ram_data(sram_data),
        .rom_addr(prom_addr), .rom_rd(prom_rd), .rom_ready(prom_ready),
        .rom_data(prom_msb), .rom_valid(prom_valid),
        .px_we(spr_we), .px_x(spr_x), .px_pix(spr_px),
        .dbg_ncand(), .dbg_xpos(), .dbg_dstwidth(), .dbg_xdrw(), .dbg_q(dbg_spr), .dbg_pbv(spr_pbv));

    // ---- line buffers -----------------------------------------------------------------------------
    // Each a hng64_bram: written as arrays these were built from 65,000 registers. A tilemap's two
    // banks are one RAM, the bank the top address bit. The sprite buffer is one RAM per bank: the
    // mixer clears what it has read, a clock behind, so its bank has two writers, and the bank the
    // engine is not writing has its write port free for the clear.
    logic [15:0] mix_tm [0:3];
    logic [15:0] mix_spr;
    logic  [8:0] mix_x, mix_x_q;
    logic        mixing, mixing_q;
    logic        bank;                      // engines write this one, the mixer reads the other
    logic        mix_bank;                  // the bank the mixer's last read went to

    genvar glb;
    generate
        for (glb = 0; glb < 4; glb++) begin : g_lbtm
            hng64_bram #(.AW(10), .DW(16)) u_lb (
                .a_clk(clk), .a_addr({bank, tm_x[glb]}), .a_be({2{tm_we[glb]}}),
                .a_wdata(dbg_layer_off[glb] ? 16'd0 : tm_pix[glb]), .a_rdata(),
                .b_clk(clk), .b_addr({~bank, mix_x}), .b_rdata(mix_tm[glb]));
        end
    endgenerate

    // The sprite engine writes two pixels a clock, x and x + 1, so each line bank is an even-x
    // and an odd-x half; the mixer reads and clears one pixel a clock from the half its x picks.
    logic [15:0] spr_q [0:1][0:1];          // [bank][half]
    generate
        for (glb = 0; glb < 4; glb++) begin : g_lbspr
            localparam int BK = glb / 2, HF = glb % 2;
            wire eng = (bank == 1'(BK));
            hng64_bram #(.AW(8), .DW(16)) u_lb (
                .a_clk(clk), .a_addr(eng ? spr_x[HF][8:1] : mix_x_q[8:1]),
                .a_be(eng ? {2{spr_we[HF]}} : {2{mixing_q && mix_x_q[0] == 1'(HF)}}),
                .a_wdata(eng ? (dbg_layer_off[4] ? 16'd0 : spr_px[HF]) : 16'd0), .a_rdata(),
                .b_clk(clk), .b_addr(mix_x[8:1]), .b_rdata(spr_q[BK][HF]));
        end
    endgenerate
    assign mix_spr = spr_q[mix_bank][mix_x_q[0]];

    always_ff @(posedge clk) begin
        mix_x_q  <= mix_x;
        mixing_q <= mixing;
        mix_bank <= ~bank;
    end

    // ---- the 3D buffer's line -------------------------------------------------------------------------
    typedef enum logic [1:0] { L_IDLE, L_RUN } lstate_t;
    lstate_t lst;
    logic        f3_busy;
    logic [15:0] mix_d3;

    hng64_fb3d u_fb3d (
        .clk(clk), .reset(reset),
        .frame_start(frame_start), .line_start(line_start && lst == L_IDLE && !spr_busy),
        .line(line), .bank(bank), .busy(f3_busy),
        .vis_y0(vis_y0), .vis_h(vis_h), .blit_off(fbcontrol0[0]), .fbscroll(fbscroll),
        .show_valid(show_valid), .show_plane(show_plane),
        .shown_valid(shown_valid), .shown_plane(shown_plane), .plane_base(plane_base),
        .d_addr(d3_addr), .d_rd(d3_rd), .d_ready(d3_ready), .d_data(d3_data), .d_valid(d3_valid),
        .mix_x(mix_x), .mix_pix(mix_d3));

    // ---- the mixer ---------------------------------------------------------------------------------
    logic mix_start, mix_busy;
    assign mixing = mix_busy;

    hng64_mixer u_mix (
        .clk(clk), .reset(reset), .start(mix_start), .rebuild(frame_start), .busy(mix_busy),
        .lb_x(mix_x), .tm_pix(mix_tm), .spr_pix(mix_spr),
        .d3_pix(dbg_layer_off[5] ? 16'd0 : mix_d3), .d3_palbase(fbcontrol2[5]),
        .tileregs(tileregs), .tcram(tcram), .bg_rgb(bg_rgb), .screen_dis(screen_dis),
        .pal_a(pal_a), .pal_d(pal_d),
        .px_we(px_we), .px_x(px_x), .px_rgb(px_rgb), .dbg_spr_seen(mix_spr_seen));

    assign dbg_rc = {line, spr_start, spr_px[1], spr_px[0], spr_x[1], spr_x[0], spr_we,
                     prom_msb, prom_valid, prom_ready, prom_rd, prom_addr};

    // sprite pixels a frame, latched at frame start: drawn by the engine, past its z-test into the
    // line buffer, and read back by the mixer (probe S)
    logic [19:0] c_emit, c_pass, c_mix;
    always_ff @(posedge clk) begin
        if (frame_start) begin
            dbg_sc <= {c_mix, c_pass, c_emit};
            c_emit <= 20'd0; c_pass <= 20'd0; c_mix <= 20'd0;
        end else begin
            c_emit <= c_emit + 20'(spr_pbv[0]) + 20'(spr_pbv[1]);
            c_pass <= c_pass + 20'(spr_we[0]) + 20'(spr_we[1]);
            c_mix  <= c_mix + 20'(mix_spr_seen);
        end
    end

    always_comb begin
        dbg_we = {spr_we, tm_we};
        for (int i = 0; i < 4; i++) begin
            dbg_x[i]   = tm_x[i];
            dbg_pix[i] = tm_pix[i];
        end
        for (int i = 0; i < 2; i++) begin
            dbg_x[4 + i]   = spr_x[i];
            dbg_pix[4 + i] = spr_px[i];
        end
    end

    // ---- the sequencer ------------------------------------------------------------------------------
    logic primed;                           // a line has been rendered, so there is one to mix

    // The sprite engine's frame-start pre-pass walks the whole list and takes longer than a line,
    // so the block stays busy through it: a line started during it would see an unfinished
    // candidate list.
    assign busy = (lst != L_IDLE) || spr_busy || f3_busy || mix_busy;   // mix_busy: the palette rebuild
    assign dbg_busy = {lst != L_IDLE, spr_busy, f3_busy, tm_busy, mix_busy};

    logic started, started0;

    always_ff @(posedge clk) begin
        tm_start  <= 4'd0;
        spr_start <= 1'b0;
        mix_start <= 1'b0;
        if (reset) begin
            lst    <= L_IDLE;
            bank   <= 1'b0;
            primed <= 1'b0;
        end else begin
            case (lst)
                L_IDLE: if (frame_start) begin
                    primed <= 1'b0;             // nothing rendered yet this frame
                end else if (line_start && !spr_busy) begin
                    tm_start  <= 4'hf;
                    spr_start <= 1'b1;
                    mix_start <= primed;
                    started   <= 1'b0;
                    started0  <= 1'b0;
                    lst       <= L_RUN;
                end
                // `started` covers the two clocks it takes the engines to raise busy (the sprite
                // engine's is registered); a layer that is
                // disabled never raises it at all, which is why the wait is on all five together
                L_RUN: begin
                    started0 <= 1'b1;
                    started  <= started0;
                    if (started && tm_busy == 4'd0 && !spr_busy && !mix_busy && !f3_busy) begin
                        bank   <= ~bank;
                        primed <= 1'b1;
                        lst    <= L_IDLE;
                    end
                end
                default: lst <= L_IDLE;
            endcase
        end
    end

endmodule
