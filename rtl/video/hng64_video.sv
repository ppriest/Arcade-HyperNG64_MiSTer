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
    output logic  [4:0] dbg_we,
    output logic  [8:0] dbg_x [0:4],
    output logic [15:0] dbg_pix [0:4]
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

    // ---- the four tilemap engines ---------------------------------------------------------------
    logic  [3:0] tm_start, tm_busy, tm_vrd, tm_rrd, tm_we;
    logic [16:0] tm_vaddr [0:3];
    logic [25:0] tm_raddr [0:3];
    logic  [8:0] tm_x [0:3];
    logic [15:0] tm_pix [0:3];
    logic  [3:0] vgrant, rgrant;            // one-hot: whose request the port took this cycle
    logic  [3:0] vdeliver, rdeliver;        // one-hot: whose reply is on the bus this cycle

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

    genvar gtm;
    generate
        for (gtm = 0; gtm < 4; gtm++) begin : g_tm
            hng64_tilemap u_tm (
                .clk(clk), .reset(reset),
                .start(tm_start[gtm]), .line(line), .tm_index(2'(gtm)), .busy(tm_busy[gtm]),
                .tileregs(tileregs[gtm]), .scrollbase(scrollbase[gtm]),
                .videoreg0(videoregs[0]), .videoreg1(videoregs[1]),
                .anim_mask(videoregs[11]), .anim_bits(videoregs[12]),
                .vram_addr(tm_vaddr[gtm]), .vram_rd(tm_vrd[gtm]), .vram_ready(vgrant[gtm]),
                .vram_data(vram_data), .vram_valid(vdeliver[gtm]),
                .rom_addr(tm_raddr[gtm]), .rom_rd(tm_rrd[gtm]), .rom_ready(rgrant[gtm]),
                .rom_data(srom_msb), .rom_valid(rdeliver[gtm]),
                .px_we(tm_we[gtm]), .px_x(tm_x[gtm]), .px_pix(tm_pix[gtm]));
        end
    endgenerate

    // MAME's init_reorder_gfx (hng64.cpp:1814) interleaves the region's two halves in 32-byte
    // units before decoding, and the engines address the decoded region. An .mra cannot express
    // that - the HPS writes DDR3 directly, and no `<interleave>` works in 32-byte chunks - so the
    // image is stored as the ROMs load and the address is translated here instead: a decoded
    // chunk is even for the upper half and odd for the lower, so dropping bit 5 gives the offset
    // within the half.
    wire [25:0] scr_dec = tm_raddr[onehot_num(rpick)];
    wire [25:0] scr_raw = {1'b0, scr_dec[25:6], scr_dec[4:0]} + (scr_dec[5] ? 26'd0 : scr_half);

    // ---- round-robin arbiters, and the queues that route the replies back ------------------------
    // Each engine bounds its own outstanding requests (16 tile words, 60 row words), so four of
    // them cannot outrun these queues.
    function automatic [3:0] pick(input logic [3:0] req, input logic [1:0] last);
        logic [1:0] i;
        pick = 4'd0;
        for (int k = 1; k <= 4; k++) begin
            i = last + k[1:0];
            if (pick == 4'd0 && req[i]) pick = 4'd1 << i;
        end
    endfunction

    function automatic [1:0] onehot_num(input logic [3:0] h);
        onehot_num = h[1] ? 2'd1 : h[2] ? 2'd2 : h[3] ? 2'd3 : 2'd0;
    endfunction

    logic [1:0] vlast, rlast;
    logic [1:0] vq [0:127];
    logic [7:0] vq_w, vq_r;
    logic [1:0] rq [0:255];
    logic [8:0] rq_w, rq_r;

    // The choice of whose request to pass on does not depend on whether the memory takes it -
    // that would be a loop - so the pick drives the port and the memory's `ready` decides which
    // engine sees its request accepted.
    logic [3:0] vpick, rpick;

    always_comb begin
        vpick     = pick(tm_vrd, vlast);
        rpick     = pick(tm_rrd, rlast);
        vram_addr = tm_vaddr[onehot_num(vpick)];
        srom_addr = scr_raw;
        vram_rd   = vpick != 4'd0;
        srom_rd   = rpick != 4'd0;
        vgrant    = vram_ready ? vpick : 4'd0;
        rgrant    = srom_ready ? rpick : 4'd0;
        vdeliver  = vram_valid ? (4'd1 << vq[vq_r[6:0]]) : 4'd0;
        rdeliver  = srom_valid ? (4'd1 << rq[rq_r[7:0]]) : 4'd0;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            vlast <= 2'd3;
            rlast <= 2'd3;
            vq_w  <= 8'd0;
            vq_r  <= 8'd0;
            rq_w  <= 9'd0;
            rq_r  <= 9'd0;
        end else begin
            if (vgrant != 4'd0) begin
                vq[vq_w[6:0]] <= onehot_num(vgrant);
                vq_w  <= vq_w + 8'd1;
                vlast <= onehot_num(vgrant);
            end
            if (vram_valid) vq_r <= vq_r + 8'd1;
            if (rgrant != 4'd0) begin
                rq[rq_w[7:0]] <= onehot_num(rgrant);
                rq_w  <= rq_w + 9'd1;
                rlast <= onehot_num(rgrant);
            end
            if (srom_valid) rq_r <= rq_r + 9'd1;
        end
    end

    // ---- the sprite engine, which has both its ports to itself -----------------------------------
    logic spr_start, spr_busy, spr_we;
    logic  [8:0] spr_x;
    logic [15:0] spr_px;

    hng64_sprite u_spr (
        .clk(clk), .reset(reset),
        .frame_start(frame_start), .line_start(spr_start), .line(line), .busy(spr_busy),
        .spriteregs0(spriteregs0), .spriteregs1(spriteregs1),
        .ram_addr(sram_addr), .ram_rd(sram_rd), .ram_data(sram_data),
        .rom_addr(prom_addr), .rom_rd(prom_rd), .rom_ready(prom_ready),
        .rom_data(prom_msb), .rom_valid(prom_valid),
        .px_we(spr_we), .px_x(spr_x), .px_pix(spr_px),
        .dbg_ncand(), .dbg_xpos(), .dbg_dstwidth(), .dbg_xdrw());

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

    logic [15:0] spr_q [0:1];
    generate
        for (glb = 0; glb < 2; glb++) begin : g_lbspr
            wire eng = (bank == 1'(glb));
            hng64_bram #(.AW(9), .DW(16)) u_lb (
                .a_clk(clk), .a_addr(eng ? spr_x : mix_x_q),
                .a_be(eng ? {2{spr_we}} : {2{mixing_q}}),
                .a_wdata(eng ? (dbg_layer_off[4] ? 16'd0 : spr_px) : 16'd0), .a_rdata(),
                .b_clk(clk), .b_addr(mix_x), .b_rdata(spr_q[glb]));
        end
    endgenerate
    assign mix_spr = spr_q[mix_bank];

    always_ff @(posedge clk) begin
        mix_x_q  <= mix_x;
        mixing_q <= mixing;
        mix_bank <= ~bank;
    end

    // ---- the 3D buffer's line -------------------------------------------------------------------------
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
        .clk(clk), .reset(reset), .start(mix_start), .busy(mix_busy),
        .lb_x(mix_x), .tm_pix(mix_tm), .spr_pix(mix_spr),
        .d3_pix(dbg_layer_off[5] ? 16'd0 : mix_d3), .d3_palbase(fbcontrol2[5]),
        .tileregs(tileregs), .tcram(tcram), .bg_rgb(bg_rgb), .screen_dis(screen_dis),
        .pal_a(pal_a), .pal_d(pal_d),
        .px_we(px_we), .px_x(px_x), .px_rgb(px_rgb));

    always_comb begin
        dbg_we = {spr_we, tm_we};
        for (int i = 0; i < 4; i++) begin
            dbg_x[i]   = tm_x[i];
            dbg_pix[i] = tm_pix[i];
        end
        dbg_x[4]   = spr_x;
        dbg_pix[4] = spr_px;
    end

    // ---- the sequencer ------------------------------------------------------------------------------
    typedef enum logic [1:0] { L_IDLE, L_RUN } lstate_t;
    lstate_t lst;
    logic primed;                           // a line has been rendered, so there is one to mix

    // The sprite engine's frame-start pre-pass walks the whole list and takes longer than a line,
    // so the block stays busy through it: a line started during it would see an unfinished
    // candidate list.
    assign busy = (lst != L_IDLE) || spr_busy || f3_busy;

    logic started;

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
                    lst       <= L_RUN;
                end
                // `started` covers the cycle it takes the engines to raise busy; a layer that is
                // disabled never raises it at all, which is why the wait is on all five together
                L_RUN: begin
                    started <= 1'b1;
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
