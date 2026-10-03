// SPDX-License-Identifier: GPL-3.0-or-later
//
// One tilemap layer, one line at a time: NEO64-SCC as MAME models it (hng64_v.cpp:49-685,
// transcribed in scripts/render_model.py).
//
// Both memories this engine reads are off chip and slow (docs/MEMORY.md): tile VRAM is in SDRAM
// because 512 KB would be 74% of the device's M10K, and the tile ROM is in DDR3 because no set's
// ROM fits SDRAM. Neither latency is small and DDR3's is not even bounded, so nothing here waits
// for a read. The engine is a pipeline whose stages pass work forward through queues:
//
//   A  walk the line one pixel a clock; at each new tile issue a VRAM read and queue the pixel
//      row within the tile, which is all stage B needs that the tile word does not give it
//   B  as tile words come back, work out the tile's ROM address and issue its one to four row
//      reads, and queue the tile's colour and flip for the emitter
//   C  as ROM beats come back, take the 32-bit half each one carries and queue it
//   E  emit one pixel a clock, taking a tile's colour and rows off the queues at each boundary
//
// A line therefore costs about 512 cycles plus one VRAM latency plus one ROM latency, instead of
// stalling once per tile row. Both ports return in order, which is what lets the queues pair
// replies with requests by counting rather than by tagging.
//
// Live, not buffered: tile VRAM and the registers are read as the line is drawn, because the
// games write them mid-screen (docs/phase1_video.md, write timing). Only the sprite list is
// snapshotted, elsewhere.
//
// The tile ROM is the region AFTER MAME's init reorder (hng64.cpp:1814); the .mra applies the
// same reorder when loading, so the ROM here is what the decoder expects.
//
// No multiplies (WORKFLOW 14) except the one genuine product, line * ystep, which a serial
// shift-add does once per line.

module hng64_tilemap (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,          // one cycle, before the line is drawn
    input  logic  [8:0] line,           // 0..447
    input  logic  [1:0] tm_index,       // which of the four maps: selects the VRAM quarter
    output logic        busy,

    input  logic [15:0] tileregs,       // videoregs[2]/[3] half (hng64_v.cpp:585)
    input  logic [13:0] scrollbase,     // videoregs[4]/[5] half
    input  logic [31:0] videoreg0,      // global dimensions, zoom disable, alt scroll
    input  logic [31:0] videoreg1,      // bit 16: auto-animation enable
    input  logic [31:0] anim_mask,      // videoregs[0x0b]
    input  logic [31:0] anim_bits,      // videoregs[0x0c]

    // tile VRAM: u32 words. A request is held until `ready`, because four of these engines
    // share one port; replies come back in order, whatever the latency.
    output logic [16:0] vram_addr,
    output logic        vram_rd,
    input  logic        vram_ready,
    input  logic [31:0] vram_data,
    input  logic        vram_valid,

    // tile ROM: byte address, 8-aligned, same handshake
    output logic [25:0] rom_addr,
    output logic        rom_rd,
    input  logic        rom_ready,
    input  logic [63:0] rom_data,
    input  logic        rom_valid,

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [15:0] px_pix,         // palette index, 0 transparent
    // for the stp revision's probe Q: {ast, est, s1_v, b_busy, qa_w, qa_r, qt_w, qb_w, qb_r,
    // qh_w, qh_r, qw_w, qw_r, scroll_i, scroll_got}
    output logic [67:0] dbg_q
);

    // the walk's (stage A) and the pixels' (stage E) states
    typedef enum logic [2:0] { A_IDLE, A_GO, A_MOS, A_SCROLL, A_MUL, A_FIRST, A_WALK, A_DONE } astate_t;
    astate_t ast;
    typedef enum logic [1:0] { E_IDLE, E_WAIT, E_EMIT, E_DONE } estate_t;
    estate_t est;

    // The layer's mode, a register here: from hng64_video's tileregs into the walk's and the
    // scroll words' logic they missed clk2x by 1.1 ns, and into the start's decision by 1.3 ns.
    // tileregs are set a clock before a start, and the start is decided a clock after it (A_GO).
    // It loads only while the engine is idle, so it holds for the pass: tileregs follow the CPU's
    // writes, and a mode written mid-pass changed the words a tile between stage B, which asked
    // for them, and stage E, which takes them, and E waited for ever (fatfurwa's intro on the
    // board, probe Q: 32 tiles' colours against 120 words, mod 128).
    logic      enable = 1'b0, big = 1'b0, eightbpp = 1'b0, linemode = 1'b0, alt = 1'b0, wrap = 1'b0;
    logic [3:0] mosaic = 4'd0;
    always_ff @(posedge clk) if (ast == A_IDLE && est == E_IDLE) begin
        enable   <= tileregs[6];
        mosaic   <= tileregs[15:12];
        big      <= tileregs[9];                // 16x16 tiles
        eightbpp <= tileregs[10];
        linemode <= ~tileregs[11];
        alt      <= tileregs[9] && (videoreg0[25:24] != 2'b00);
        wrap     <= tileregs[8];
    end

    // mosaic: every (mosaic+1)th line is the source line for the group, found by hng64_mosaic
    // while the line waits in A_MOS
    logic       mos_start;
    wire        mos_done;
    wire  [8:0] mos_base;
    hng64_mosaic #(.W(9)) u_mos (
        .clk(clk), .start(mos_start), .x(line), .m(mosaic), .done(mos_done), .base(mos_base));
    // the line the layer is drawn from, a register set as the scroll words are asked for: chosen
    // by mosaic straight into the walk's multiply it missed clk2x by 1.0 ns
    logic [8:0] src_line;

    // ---- the layer's scroll words, and the four steps they give -------------------------------
    // Three layouts (hng64_v.cpp:143-318): plain, per line, and the rotating "alt" one buriki's
    // title screen uses. All three live in the same eight words at the layer's scrollbase, with
    // four more per line in line mode.
    logic [31:0] sb_w [0:7];
    logic [31:0] ln_w [0:3];

    wire [16:0] base_addr = 17'h10000 + {1'b0, scrollbase, 2'b00};
    wire [16:0] line_addr = base_addr + {6'd0, src_line, 2'b00};

    wire alt_fmt  = videoreg0[26];
    wire zoom_off = videoreg0[16];
    wire roz      = !linemode && alt_fmt;      // rotation: both increments have two terms

    // in line mode a line word is used only when its low byte is 0 (hng64_v.cpp:298)
    wire [31:0] lxtl  = (ln_w[0][7:0] == 8'd0) ? ln_w[0] : sb_w[0];
    wire [31:0] lxmid = (ln_w[1][7:0] == 8'd0) ? ln_w[1] : sb_w[1];

    wire signed [31:0] xtl  = roz ? sb_w[0] : zoom_off ? 32'sd0 : linemode ? lxtl  : sb_w[0];
    wire signed [31:0] xmid = roz ? sb_w[4] : zoom_off ? 32'sh0100_0000
                                            : linemode ? lxmid : sb_w[1];
    wire signed [31:0] ytl  = roz ? sb_w[2] : zoom_off ? 32'sd0 : linemode ? ln_w[2] : sb_w[2];
    wire signed [31:0] ymid = roz ? sb_w[3] : zoom_off ? 32'sh0100_0000
                                            : linemode ? ln_w[3] : sb_w[3];

    // xtl/ytl a clock late: the scroll and line words are all in before A_MUL starts, so these
    // hold the same values when the multiply ends and the start position is added
    logic signed [31:0] s_xtl, s_ytl;
    always_ff @(posedge clk) begin
        s_xtl <= xtl;
        s_ytl <= ytl;
    end

    // (mid - topleft) / 512 * 2, with C division truncating toward zero
    function automatic signed [31:0] step2(input logic signed [31:0] d);
        step2 = ((d + (d[31] ? 32'sd511 : 32'sd0)) >>> 9) <<< 1;
    endfunction

    // A_MUL's first step latches the selected words (q_*), the second their differences (d_*),
    // the third the increments: from the video registers through the selects, a subtract and a
    // shift in one clock missed clk2x by 3.1 ns, and the subtract with step2's rounding add into
    // add_y by 0.39 ns (bc6546a seed 1).
    logic signed [31:0] q_xtl, q_xmid, q_ytl, q_ymid, q_sb1, q_sb6;
    logic               q_roz, q_lalt;
    logic signed [31:0] d_xx, d_yy, d_yx, d_xy;
    wire signed [31:0] w_incxx = step2(d_xx);
    wire signed [31:0] w_incyy = q_lalt ? 32'sd0 : step2(d_yy);
    wire signed [31:0] w_incyx = q_roz ? step2(d_yx) : 32'sd0;
    wire signed [31:0] w_incxy = q_roz ? step2(d_xy) : q_lalt ? step2(d_yy) : 32'sd0;
    // MAME's optimised loop: no rotation and no wrap, so the line starts at the first in-range
    // pixel and stops at the first one past the map. Latched from the registered increments, on
    // A_MUL's first step: from the scroll words to `stopped` missed clk2x by 3.9 ns, and to a
    // latch beside the increments by 3.6 ns.
    logic optimised;

    logic signed [31:0] incxx, incxy;
    logic signed [31:0] acc_x, acc_y, add_x, add_y;
    logic [3:0]  mul_i;
    logic [8:0]  mul_sh;                // src_line, shifted a bit a step

    // ---- coordinate helpers, used by both walkers ---------------------------------------------
    // 16.16 source position -> tile number: pixel is v[31:16], so a 16-wide tile is v[27:20]
    // and an 8-wide one v[26:19]. The map is 128 tiles square, or 256x64 in alt mode.
    function automatic [8:0] tile_x(input logic signed [31:0] v);
        tile_x = big ? (alt ? {1'b0, v[27:20]} : {2'b0, v[26:20]}) : {2'b0, v[25:19]};
    endfunction
    function automatic [8:0] tile_y(input logic signed [31:0] v);
        tile_y = big ? (alt ? {3'd0, v[25:20]} : {2'b0, v[26:20]}) : {2'b0, v[25:19]};
    endfunction
    function automatic [3:0] pix_y(input logic signed [31:0] v);
        pix_y = big ? v[19:16] : {1'b0, v[18:16]};
    endfunction
    // each layer owns 0x4000 words of VRAM (hng64_v.cpp:49, tile_index + (Which << 14))
    function automatic [16:0] tile_index(input logic [8:0] itx, input logic [8:0] ity);
        tile_index = (alt ? {2'd0, ity[5:0], itx[7:0]} : {3'd0, ity[6:0], itx[6:0]})
                   + {1'b0, tm_index, 14'd0};
    endfunction

    // registered: tileregs settle before a start, and the first use is after the multiply
    logic [1:0] words_m1;
    always_ff @(posedge clk) words_m1 <= big ? (eightbpp ? 2'd3 : 2'd1) : (eightbpp ? 2'd1 : 2'd0);

    // ================= stage A: walk the line, issue tile-word reads ============================

    logic signed [31:0] fcx, fcy;
    logic  [9:0] fx;
    logic        fx_end;                // fx is 511, set as it gets there (the compare: 0.45 ns)
    logic  [3:0] scroll_i;              // scroll words issued
    logic  [3:0] scroll_got;            // scroll words returned

    // the next position, a register ahead of fcx/fcy so the tile compare does not follow the add
    logic signed [31:0] fnx, fny;
    wire  [8:0] f_ntx = tile_x(fnx), f_nty = tile_y(fny);
    wire  [3:0] f_npy = pix_y(fny);
    // A new tile is a difference between fnx/fny and fcx/fcy in the bits that pick the tile (and
    // y's pixel row): bits 27:16 under a mask set from the mode. Compared through tile_x/tile_y
    // from `big` it missed clk2x by 0.8 ns (00a9080 seed 1).
    logic [11:0] f_mx, f_my;
    always_ff @(posedge clk) begin
        f_mx <= big ? (alt ? 12'hFF0 : 12'h7F0) : 12'h3F8;
        f_my <= big ? (alt ? 12'h3FF : 12'h7FF) : 12'h3FF;
    end
    wire        f_newtile = |((fnx[27:16] ^ fcx[27:16]) & f_mx) || |((fny[27:16] ^ fcy[27:16]) & f_my);
    wire  [3:0] scroll_last = linemode ? 4'd11 : 4'd7;
    wire [16:0] scroll_addr = (scroll_i < 4'd8) ? (base_addr + {13'd0, scroll_i})
                                                : (line_addr + {15'd0, scroll_i[1:0]});

    // A -> B: the pixel row inside the tile, and beside it the tile word when it arrives.
    // The word has to be queued, not taken on the spot: B is busy issuing row reads for up to
    // four cycles a tile, and a rotating layer asks for a tile a pixel, so a reply landing
    // during that burst would otherwise be dropped and the queues would lose step.
    logic [3:0]  qa [0:15];
    logic [31:0] qt [0:15];
    logic [4:0]  qa_w, qa_r, qt_w;
    wire  [4:0]  qa_n = qa_w - qa_r;
    wire         qa_full = qa_n >= 5'd15;
    wire         qt_ready = qt_w != qa_r;      // a tile word has arrived for the entry at qa_r

    // ================= stage B: tile word -> row reads ==========================================
    logic [31:0] bword;
    logic [3:0]  b_py;
    logic [1:0]  b_wi;
    logic        b_busy;

    wire [31:0] btile = (videoreg1[16] && bword[21]) ? ((bword & anim_mask) | anim_bits) : bword;
    wire [20:0] tileno = btile[20:0];
    // every case is tileno << 5 with the low bits of the code cleared first:
    //   8x8x4 code<<5, 8x8x8 (code>>1)<<6, 16x16x4 (code>>2)<<7, 16x16x8 (code>>3)<<8
    wire [25:0] tile_base = big
        ? (eightbpp ? {tileno[20:3], 8'd0} : {tileno[20:2], 7'd0})
        : (eightbpp ? {tileno[20:1], 6'd0} : {tileno[20:0], 5'd0});
    // bit 23 is flipy: 15 - row, or 7 - row
    wire [3:0] b_row_y = bword[23] ? (big ? ~b_py : {1'b0, ~b_py[2:0]}) : b_py;
    // A row is a 32-bit word every 4 bytes, but the layouts skip: rows 8-15 of a 16-tall tile
    // start 8 rows further on (hng64.cpp yoffsets 0..7*32 then 16..23*32), and the pixels of one
    // row are spread over up to four words at 0, 32, 128 and 160 bytes (xoffsets 0, 256, 1024,
    // 1280 bits). Every offset a mode uses is below its tile's size, so they are ORed in: the
    // adds missed clk2x by 1.3 ns into bq (00a9080 seed 2).
    wire [25:0] b_word_addr = tile_base | {18'd0, b_wi[1], b_row_y[3], b_wi[0], b_row_y[2:0], 2'b00};

    // B -> E: colour and x flip, one entry a tile
    logic [16:0] qb [0:15];             // {colour[15:0], flipx}
    logic  [4:0] qb_w, qb_r;
    wire   [4:0] qb_n = qb_w - qb_r;

    // B -> C: which half of the 64-bit beat each outstanding read wants
    logic        qh [0:63];
    logic  [6:0] qh_w, qh_r;
    wire   [6:0] qh_n = qh_w - qh_r;

    // ================= stage C: beats -> 32-bit row words =======================================
    // The port has no back-pressure, so stage C must always have somewhere to put a beat. Stage B
    // therefore issues only while the words already queued plus the replies still owed leave
    // room; a rotating layer, which wants a tile a pixel, reaches this limit every line.
    logic [31:0] qw [0:63];
    logic  [6:0] qw_w, qw_r;
    wire   [6:0] qw_n = qw_w - qw_r;
    wire   [7:0] qw_owed = {1'b0, qw_n} + {1'b0, qh_n};
    // Stage B's room, registered: from the queue pointers through the subtracts, the sum and the
    // compares into every qb entry's write it missed clk2x by 1.0 ns. A clock late it has not seen
    // the read B issued in the clock before, so each limit is one lower; B issues one a clock.
    logic        b_room = 1'b0;
    always_ff @(posedge clk) b_room <= qb_n < 5'd14 && qh_n < 7'd62 && qw_owed < 8'd59;

    // ================= stage E: pixels ==========================================================

    logic signed [31:0] cx, cy;
    logic  [8:0] x;
    logic [31:0] rowwords [0:3];
    logic [15:0] colour;
    logic        flipx;
    logic  [3:0] mos_x;
    logic [15:0] held;
    logic        started, stopped;
    logic  [1:0] pop_i;

    wire signed [31:0] next_cx = cx + incxx;
    wire signed [31:0] next_cy = cy + incxy;
    // another tile, or another row of the same one: stage A's test, on cx/cy (through tile_x and
    // tile_y from the mode bits into est it missed clk2x by 0.38 ns, f52fa64 seed 2)
    wire e_newtile = |((next_cx[27:16] ^ cx[27:16]) & f_mx) || |((next_cy[27:16] ^ cy[27:16]) & f_my);
    wire [3:0] px_in_tile = big ? cx[19:16] : {1'b0, cx[18:16]};

    // inside the map: the position's top bits under a mask set from the mode, 0 with wrap (through
    // wrap, big and alt's selects into mos_x it missed clk2x by 0.85 ns, f52fa64 seed 2)
    logic [5:0] e_mx, e_my;                 // bits 31:26 that must be 0
    always_ff @(posedge clk) begin
        e_mx <= wrap ? 6'b000000 : big ? (alt ? 6'b111100 : 6'b111110) : 6'b111111;
        e_my <= wrap ? 6'b000000 : (big && !alt) ? 6'b111110 : 6'b111111;
    end
    wire x_in_map = (cx[31:26] & e_mx) == 6'd0;
    wire y_in_map = (cy[31:26] & e_my) == 6'd0;
    wire in_range = x_in_map && y_in_map;
    wire draw_ok  = in_range && !stopped;
    // A tile is ready when its colour entry and all of its row words have arrived. The test
    // holds only before the first word is taken: after that the rest are already queued, and
    // re-testing would stall the last tile of the line for words that will never come.
    wire tile_ready = (qb_n != 5'd0) && (qw_n > {5'd0, words_m1});

    // E_EMIT picks the pixel (stage 1, s1_*); the next clock adds the tile colour, applies mosaic
    // and writes (stage 2). Selecting and combining in one clock missed clk2x by 3.35 ns.
    logic        s1_v, s1_draw, s1_hold;
    logic  [8:0] s1_x;
    logic  [7:0] s1_pix;
    logic [15:0] s1_colour;

    assign busy = (ast != A_IDLE) || (est != E_IDLE) || s1_v;
    // A and E both idle, a clock late: the B stage and the reply queues clear on it, and nothing
    // is in flight in that clock either way (from the state decodes into the queues' writes it
    // missed clk2x by 1.3 ns)
    logic eng_idle = 1'b1;
    always_ff @(posedge clk) eng_idle <= ast == A_IDLE && est == E_IDLE;
    // from compares, not ast's and est's bits, so synthesis can still choose their encoding
    logic [2:0] ast_code;
    logic [1:0] est_code;
    always_comb begin
        ast_code = '0;
        for (int k = 0; k <= int'(A_DONE); k++) if (ast == astate_t'(k)) ast_code = 3'(k);
        est_code = '0;
        for (int k = 0; k <= int'(E_DONE); k++) if (est == estate_t'(k)) est_code = 2'(k);
    end
    assign dbg_q = {ast_code, est_code, s1_v, b_busy, qa_w, qa_r, qt_w, qb_w, qb_r,
                    qh_w, qh_r, qw_w, qw_r, scroll_i, scroll_got};

    // Pixel out of the fetched row. Bit offsets are MSB-first across the word, so offset k is
    // word[31-k]: 4bpp xoffsets 24,28,8,12,16,20,0,4 (hng64.cpp:1678) and 8bpp 24,8,16,0.
    wire [3:0]  xt   = flipx ? (big ? ~px_in_tile : {1'b0, ~px_in_tile[2:0]}) : px_in_tile;
    wire [31:0] word = eightbpp ? rowwords[xt[3:2]] : rowwords[{1'b0, xt[3]}];
    logic [7:0] pix;
    always_comb begin
        if (eightbpp) begin
            case (xt[1:0])
                2'd0: pix = word[7:0];
                2'd1: pix = word[23:16];
                2'd2: pix = word[15:8];
                default: pix = word[31:24];
            endcase
        end else begin
            case (xt[2:0])
                3'd0: pix = {4'd0, word[7:4]};
                3'd1: pix = {4'd0, word[3:0]};
                3'd2: pix = {4'd0, word[23:20]};
                3'd3: pix = {4'd0, word[19:16]};
                3'd4: pix = {4'd0, word[15:12]};
                3'd5: pix = {4'd0, word[11:8]};
                3'd6: pix = {4'd0, word[31:28]};
                default: pix = {4'd0, word[27:24]};
            endcase
        end
    end
    wire [15:0] pixel_out = (s1_pix == 8'd0) ? 16'd0 : (s1_colour | {8'd0, s1_pix});

    always_ff @(posedge clk) begin
        px_we <= s1_v;
        px_x  <= s1_x;
        if (s1_v) begin
            if (!s1_draw) begin
                px_pix <= 16'd0;
            end else if (!s1_hold) begin
                px_pix <= pixel_out;
                held   <= pixel_out;
            end else begin
                px_pix <= held;
            end
        end
    end

    // ---- stage A ------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        mos_start <= 1'b0;
        if (reset) begin
            vram_rd <= 1'b0;
            ast     <= A_IDLE;
            qa_w    <= 5'd0;
        end else begin
            if (vram_rd && !vram_ready) begin
            // the port has not taken it yet: hold the request and the walk
            end else begin
            vram_rd <= 1'b0;
            case (ast)
                A_IDLE: if (start) ast <= A_GO;

                A_GO: if (!enable) begin
                    ast <= A_IDLE;
                end else begin
                    if (mosaic != 4'd0) begin
                        mos_start  <= 1'b1;
                        ast        <= A_MOS;
                    end else begin
                        src_line   <= line;
                        scroll_i   <= 4'd1;
                        scroll_got <= 4'd0;
                        vram_addr  <= base_addr;
                        vram_rd    <= 1'b1;
                        qa_w       <= 5'd0;
                        ast        <= A_SCROLL;
                    end
                end

                A_MOS: if (mos_done) begin
                    src_line   <= mos_base;
                    scroll_i   <= 4'd1;
                    scroll_got <= 4'd0;
                    vram_addr  <= base_addr;
                    vram_rd    <= 1'b1;
                    qa_w       <= 5'd0;
                    ast        <= A_SCROLL;
                end

                // all twelve scroll words are asked for back to back; they are collected below,
                // outside the stall, because a reply is a single cycle and waiting for the port
                // to take the next request must not make us miss one
                A_SCROLL: if (scroll_i <= scroll_last) begin
                    vram_addr <= scroll_addr;
                    vram_rd   <= 1'b1;
                    scroll_i  <= scroll_i + 4'd1;
                end

                // startx and starty are topleft + line * the down-screen increments: two serial
                // shift-adds, one line's worth (WORKFLOW 14)
                A_MUL: begin
                    if (mul_i == 4'd0) begin
                        q_xtl  <= xtl;
                        q_xmid <= xmid;
                        q_ytl  <= ytl;
                        q_ymid <= ymid;
                        q_sb1  <= $signed(sb_w[1]);
                        q_sb6  <= $signed(sb_w[6]);
                        q_roz  <= roz;
                        q_lalt <= linemode && alt_fmt;
                        mul_i  <= 4'd1;
                    end else if (mul_i == 4'd1) begin
                        d_xx  <= q_xmid - q_xtl;
                        d_yy  <= q_ymid - q_ytl;
                        d_yx  <= q_sb1 - q_xtl;
                        d_xy  <= q_sb6 - q_ytl;
                        mul_i <= 4'd2;
                    end else if (mul_i == 4'd2) begin
                        incxx <= w_incxx;
                        incxy <= w_incxy;
                        acc_x <= 32'sd0;
                        acc_y <= 32'sd0;
                        add_x <= w_incyx;
                        add_y <= w_incyy;
                        mul_sh <= src_line;
                        mul_i <= 4'd3;
                    end else if (mul_i <= 4'd11) begin
                        // add_x is still w_incyx on the first step
                        if (mul_i == 4'd3) optimised <= (incxy == 32'sd0) && (add_x == 32'sd0) && !wrap;
                        if (mul_sh[0]) begin   // src_line[mul_i - 3]: 0.8 ns over clk2x
                            acc_x <= acc_x + add_x;
                            acc_y <= acc_y + add_y;
                        end
                        mul_sh <= mul_sh >> 1;
                        add_x <= add_x <<< 1;
                        add_y <= add_y <<< 1;
                        mul_i <= mul_i + 4'd1;
                    end else begin
                        fcx <= s_xtl + acc_x;
                        fcy <= s_ytl + acc_y;
                        fx  <= 10'd0;
                        fx_end <= 1'b0;
                        ast <= A_FIRST;
                    end
                end

                // the first tile of the line: nothing to compare against yet
                A_FIRST: if (!qa_full) begin
                    fnx       <= fcx + incxx;
                    fny       <= fcy + incxy;
                    vram_addr <= tile_index(tile_x(fcx), tile_y(fcy));
                    vram_rd   <= 1'b1;
                    qa[qa_w[3:0]] <= pix_y(fcy);
                    qa_w      <= qa_w + 5'd1;
                    ast       <= A_WALK;
                end

                A_WALK: begin
                    if (fx_end) begin
                        ast <= A_DONE;
                    end else if (!(f_newtile && qa_full)) begin
                        fx  <= fx + 10'd1;
                        fx_end <= fx == 10'd510;
                        fcx <= fnx;
                        fcy <= fny;
                        fnx <= fnx + incxx;
                        fny <= fny + incxy;
                        if (f_newtile) begin
                            vram_addr <= tile_index(f_ntx, f_nty);
                            vram_rd   <= 1'b1;
                            qa[qa_w[3:0]] <= f_npy;
                            qa_w      <= qa_w + 5'd1;
                        end
                    end
                end

                A_DONE: if (est == E_IDLE) ast <= A_IDLE;
                default: ast <= A_IDLE;
            endcase
            end

            // scroll words come back whether or not the port has taken the next request, so this
            // sits outside the stall and after the case, whose A_SCROLL arm only issues
            if (ast == A_SCROLL && vram_valid) begin
                if (scroll_got < 4'd8) sb_w[scroll_got[2:0]] <= vram_data;
                else                   ln_w[scroll_got[1:0]] <= vram_data;
                if (scroll_got == scroll_last) begin
                    mul_i <= 4'd0;
                    ast   <= A_MUL;
                end
                scroll_got <= scroll_got + 4'd1;
            end
        end
    end

    // ---- stage B ------------------------------------------------------------------------------
    // Its ROM reads go out through two entries (bq): B waits only while both are full, a register,
    // where it used to stop whole until the port took its read (from the port's ready through
    // that hold into rom_addr and the queues: 1.1 ns over clk2x).
    logic [25:0] bq_head, bq_tail;
    logic  [1:0] bq_n;
    logic        bq_v;                  // bq_n != 0, a register: compared, into hng64_video's pick
                                        // and its queue it missed clk2x by 0.73 ns (8d5f748 s1)
    wire         b_issue = !reset && !eng_idle && b_busy && b_room && bq_n != 2'd2;
    wire         bq_pop  = bq_v && rom_ready;
    wire  [25:0] bq_new  = {b_word_addr[25:3], 3'b000};
    assign rom_rd   = bq_v;
    assign rom_addr = bq_head;
    always_ff @(posedge clk) begin
        if (reset) begin
            bq_n <= 2'd0;
            bq_v <= 1'b0;
        end else begin
            case ({b_issue, bq_pop})
                2'b10: if (bq_n == 2'd0) bq_head <= bq_new; else bq_tail <= bq_new;
                2'b01: bq_head <= bq_tail;
                2'b11: if (bq_n == 2'd1) bq_head <= bq_new;
                       else begin bq_head <= bq_tail; bq_tail <= bq_new; end
                default: ;
            endcase
            bq_n <= bq_n + 2'(b_issue) - 2'(bq_pop);
            bq_v <= bq_n + 2'(b_issue) - 2'(bq_pop) != 2'd0;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            b_busy <= 1'b0;
            qa_r   <= 5'd0;
            qb_w   <= 5'd0;
            qh_w   <= 7'd0;
        end else if (eng_idle) begin
            b_busy <= 1'b0;
            qa_r   <= 5'd0;
            qb_w   <= 5'd0;
            qh_w   <= 7'd0;
        end else begin
            if (!b_busy) begin
                if (qt_ready) begin
                    bword  <= qt[qa_r[3:0]];
                    b_py   <= qa[qa_r[3:0]];
                    qa_r   <= qa_r + 5'd1;
                    b_wi   <= 2'd0;
                    b_busy <= 1'b1;
                end
            end else if (b_issue) begin             // bq takes the read
                qh[qh_w[5:0]] <= b_word_addr[2];
                qh_w     <= qh_w + 7'd1;
                if (b_wi == words_m1) begin
                    qb[qb_w[3:0]] <= {eightbpp ? {4'd0, bword[31:28], 8'd0}
                                               : {4'd0, bword[31:24], 4'd0}, bword[22]};
                    qb_w   <= qb_w + 5'd1;
                    b_busy <= 1'b0;
                end else begin
                    b_wi <= b_wi + 2'd1;
                end
            end
        end
    end

    // ---- tile words in, as they come back --------------------------------------------------
    // A scroll word is not a tile word: stage A takes those itself while it is in A_SCROLL.
    always_ff @(posedge clk) begin
        if (reset || (eng_idle)) begin
            qt_w <= 5'd0;
        end else if (vram_valid && ast != A_SCROLL) begin
            qt[qt_w[3:0]] <= vram_data;
            qt_w <= qt_w + 5'd1;
        end
    end

    // ---- stage C ------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset || (eng_idle)) begin
            qw_w <= 7'd0;
            qh_r <= 7'd0;
        end else if (rom_valid) begin
            qw[qw_w[5:0]] <= qh[qh_r[5:0]] ? rom_data[31:0] : rom_data[63:32];
            qw_w <= qw_w + 7'd1;
            qh_r <= qh_r + 7'd1;
        end
    end

    // ---- stage E ------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        s1_v <= 1'b0;
        if (reset) begin
            est  <= E_IDLE;
            qb_r <= 5'd0;
            qw_r <= 7'd0;
        end else begin
            case (est)
                E_IDLE: if (ast == A_MUL && mul_i > 4'd11) begin   // the multiply is done
                    cx      <= s_xtl + acc_x;
                    cy      <= s_ytl + acc_y;
                    x       <= 9'd0;
                    mos_x   <= 4'd0;
                    started <= 1'b0;
                    stopped <= 1'b0;
                    qb_r    <= 5'd0;
                    qw_r    <= 7'd0;
                    pop_i   <= 2'd0;
                    est     <= E_WAIT;
                end

                // take one tile's colour and its row words off the queues
                E_WAIT: if (pop_i != 2'd0 || tile_ready) begin
                    rowwords[pop_i] <= qw[qw_r[5:0]];
                    qw_r <= qw_r + 7'd1;
                    if (pop_i == words_m1) begin
                        colour <= qb[qb_r[3:0]][16:1];
                        flipx  <= qb[qb_r[3:0]][0];
                        qb_r   <= qb_r + 5'd1;
                        pop_i  <= 2'd0;
                        est    <= E_EMIT;
                    end else begin
                        pop_i <= pop_i + 2'd1;
                    end
                end

                E_EMIT: begin
                    s1_v      <= 1'b1;
                    s1_x      <= x;
                    s1_draw   <= draw_ok;
                    s1_hold   <= mos_x != 4'd0;
                    s1_pix    <= pix;
                    s1_colour <= colour;
                    if (draw_ok) begin
                        started <= 1'b1;
                        if (mos_x == 4'd0) mos_x <= mosaic;
                        else               mos_x <= mos_x - 4'd1;
                    end
                    if (optimised && started && !in_range) stopped <= 1'b1;
                    cx <= next_cx;
                    cy <= next_cy;
                    if (x == 9'd511) begin
                        est <= E_DONE;
                    end else begin
                        x <= x + 9'd1;
                        // another tile, or another row of the same one when the line rotates
                        if (e_newtile) est <= E_WAIT;
                    end
                end

                E_DONE: est <= E_IDLE;
                default: est <= E_IDLE;
            endcase
        end
    end


endmodule
