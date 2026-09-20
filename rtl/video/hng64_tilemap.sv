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
    output logic [15:0] px_pix          // palette index, 0 transparent
);

    wire       enable   = tileregs[6];
    wire       big      = tileregs[9];      // 16x16 tiles
    wire       eightbpp = tileregs[10];
    wire       linemode = ~tileregs[11];
    wire [3:0] mosaic   = tileregs[15:12];
    wire       alt      = big && (videoreg0[25:24] != 2'b00);
    wire       wrap     = tileregs[8];

    // mosaic: every (mosaic+1)th line is the source line for the group
    logic [8:0] src_line;
    always_comb begin
        src_line = line;
        if (mosaic != 0) src_line = line - (line % (mosaic + 1));
    end

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

    // (mid - topleft) / 512 * 2, with C division truncating toward zero
    function automatic signed [31:0] step2(input logic signed [31:0] d);
        step2 = ((d + (d[31] ? 32'sd511 : 32'sd0)) >>> 9) <<< 1;
    endfunction

    wire signed [31:0] w_incxx = step2(xmid - xtl);
    wire signed [31:0] w_incyy = (linemode && alt_fmt) ? 32'sd0 : step2(ymid - ytl);
    wire signed [31:0] w_incyx = roz ? step2($signed(sb_w[1]) - xtl) : 32'sd0;
    wire signed [31:0] w_incxy = roz ? step2($signed(sb_w[6]) - ytl)
                                     : (linemode && alt_fmt) ? step2(ymid - ytl) : 32'sd0;
    // MAME's optimised loop: no rotation and no wrap, so the line starts at the first in-range
    // pixel and stops at the first one past the map
    wire optimised = (w_incxy == 32'sd0) && (w_incyx == 32'sd0) && !wrap;

    logic signed [31:0] incxx, incxy;
    logic signed [31:0] acc_x, acc_y, add_x, add_y;
    logic [3:0]  mul_i;

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

    wire [1:0] words_m1 = big ? (eightbpp ? 2'd3 : 2'd1) : (eightbpp ? 2'd1 : 2'd0);

    // ================= stage A: walk the line, issue tile-word reads ============================
    typedef enum logic [2:0] { A_IDLE, A_SCROLL, A_MUL, A_FIRST, A_WALK, A_DONE } astate_t;
    astate_t ast;

    logic signed [31:0] fcx, fcy;
    logic  [9:0] fx;
    logic  [8:0] f_tx, f_ty;
    logic  [3:0] f_py;
    logic  [3:0] scroll_i;              // scroll words issued
    logic  [3:0] scroll_got;            // scroll words returned

    wire signed [31:0] fnext_cx = fcx + incxx;
    wire signed [31:0] fnext_cy = fcy + incxy;
    wire  [8:0] f_ntx = tile_x(fnext_cx), f_nty = tile_y(fnext_cy);
    wire  [3:0] f_npy = pix_y(fnext_cy);
    wire        f_newtile = (f_ntx != f_tx) || (f_nty != f_ty) || (f_npy != f_py);
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
    wire [3:0] rows_m1 = big ? 4'd15 : 4'd7;
    wire [3:0] b_row_y = bword[23] ? (rows_m1 - b_py) : b_py;    // bit 23 is flipy
    // A row is a 32-bit word every 4 bytes, but the layouts skip: rows 8-15 of a 16-tall tile
    // start 8 rows further on (hng64.cpp yoffsets 0..7*32 then 16..23*32), and the pixels of one
    // row are spread over up to four words 32 bytes apart (xoffsets 0, 256, 1024, 1280 bits).
    wire [4:0] b_row_sel = (b_row_y >= 4'd8) ? ({1'b0, b_row_y} + 5'd8) : {1'b0, b_row_y};
    wire [6:0] b_row_ofs = {b_row_sel, 2'b00};
    wire [25:0] b_word_addr = tile_base + {19'd0, b_row_ofs}
                            + (b_wi == 2'd0 ? 26'd0 : b_wi == 2'd1 ? 26'd32
                               : b_wi == 2'd2 ? 26'd128 : 26'd160);

    // B -> E: colour and x flip, one entry a tile
    logic [16:0] qb [0:15];             // {colour[15:0], flipx}
    logic  [4:0] qb_w, qb_r;
    wire   [4:0] qb_n = qb_w - qb_r;
    wire         qb_full = qb_n >= 5'd15;

    // B -> C: which half of the 64-bit beat each outstanding read wants
    logic        qh [0:63];
    logic  [6:0] qh_w, qh_r;
    wire   [6:0] qh_n = qh_w - qh_r;
    wire         qh_full = qh_n >= 7'd63;

    // ================= stage C: beats -> 32-bit row words =======================================
    // The port has no back-pressure, so stage C must always have somewhere to put a beat. Stage B
    // therefore issues only while the words already queued plus the replies still owed leave
    // room; a rotating layer, which wants a tile a pixel, reaches this limit every line.
    logic [31:0] qw [0:63];
    logic  [6:0] qw_w, qw_r;
    wire   [6:0] qw_n = qw_w - qw_r;
    wire   [7:0] qw_owed = {1'b0, qw_n} + {1'b0, qh_n};
    wire         qw_room = qw_owed < 8'd60;

    // ================= stage E: pixels ==========================================================
    typedef enum logic [1:0] { E_IDLE, E_WAIT, E_EMIT, E_DONE } estate_t;
    estate_t est;

    logic signed [31:0] cx, cy;
    logic  [8:0] x;
    logic  [8:0] cur_tx, cur_ty;
    logic  [3:0] cur_py;
    logic [31:0] rowwords [0:3];
    logic [15:0] colour;
    logic        flipx;
    logic  [3:0] mos_x;
    logic [15:0] held;
    logic        started, stopped;
    logic  [1:0] pop_i;

    wire signed [31:0] next_cx = cx + incxx;
    wire signed [31:0] next_cy = cy + incxy;
    wire [8:0] ntx = tile_x(next_cx), nty = tile_y(next_cy);
    wire [3:0] npy = pix_y(next_cy);
    wire [3:0] px_in_tile = big ? cx[19:16] : {1'b0, cx[18:16]};

    wire x_in_map = wrap ? 1'b1
                  : big ? (alt ? (cx[31:28] == 4'd0) : (cx[31:27] == 5'd0))
                        : (cx[31:26] == 6'd0);
    wire y_in_map = wrap ? 1'b1
                  : big ? (alt ? (cy[31:26] == 6'd0) : (cy[31:27] == 5'd0))
                        : (cy[31:26] == 6'd0);
    wire in_range = x_in_map && y_in_map;
    wire draw_ok  = in_range && !stopped;
    // A tile is ready when its colour entry and all of its row words have arrived. The test
    // holds only before the first word is taken: after that the rest are already queued, and
    // re-testing would stall the last tile of the line for words that will never come.
    wire tile_ready = (qb_n != 5'd0) && (qw_n > {5'd0, words_m1});

    assign busy = (ast != A_IDLE) || (est != E_IDLE);

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
    wire [15:0] pixel_out = (pix == 8'd0) ? 16'd0 : (colour | {8'd0, pix});

    // ---- stage A ------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
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
                A_IDLE: if (start && enable) begin
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
                        incxx <= w_incxx;
                        incxy <= w_incxy;
                        acc_x <= 32'sd0;
                        acc_y <= 32'sd0;
                        add_x <= w_incyx;
                        add_y <= w_incyy;
                        mul_i <= 4'd1;
                    end else if (mul_i <= 4'd9) begin
                        if (src_line[mul_i - 4'd1]) begin
                            acc_x <= acc_x + add_x;
                            acc_y <= acc_y + add_y;
                        end
                        add_x <= add_x <<< 1;
                        add_y <= add_y <<< 1;
                        mul_i <= mul_i + 4'd1;
                    end else begin
                        fcx <= xtl + acc_x;
                        fcy <= ytl + acc_y;
                        fx  <= 10'd0;
                        ast <= A_FIRST;
                    end
                end

                // the first tile of the line: nothing to compare against yet
                A_FIRST: if (!qa_full) begin
                    vram_addr <= tile_index(tile_x(fcx), tile_y(fcy));
                    vram_rd   <= 1'b1;
                    f_tx      <= tile_x(fcx);
                    f_ty      <= tile_y(fcy);
                    f_py      <= pix_y(fcy);
                    qa[qa_w[3:0]] <= pix_y(fcy);
                    qa_w      <= qa_w + 5'd1;
                    ast       <= A_WALK;
                end

                A_WALK: begin
                    if (fx == 10'd511) begin
                        ast <= A_DONE;
                    end else if (!(f_newtile && qa_full)) begin
                        fx  <= fx + 10'd1;
                        fcx <= fnext_cx;
                        fcy <= fnext_cy;
                        if (f_newtile) begin
                            vram_addr <= tile_index(f_ntx, f_nty);
                            vram_rd   <= 1'b1;
                            f_tx      <= f_ntx;
                            f_ty      <= f_nty;
                            f_py      <= f_npy;
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
    always_ff @(posedge clk) begin
        if (reset) begin
            rom_rd <= 1'b0;
            b_busy <= 1'b0;
            qa_r   <= 5'd0;
            qb_w   <= 5'd0;
            qh_w   <= 7'd0;
        end else if (rom_rd && !rom_ready) begin
            // held until the port takes it
        end else if (ast == A_IDLE && est == E_IDLE) begin
            rom_rd <= 1'b0;
            b_busy <= 1'b0;
            qa_r   <= 5'd0;
            qb_w   <= 5'd0;
            qh_w   <= 7'd0;
        end else begin
            rom_rd <= 1'b0;
            if (!b_busy) begin
                if (qt_ready) begin
                    bword  <= qt[qa_r[3:0]];
                    b_py   <= qa[qa_r[3:0]];
                    qa_r   <= qa_r + 5'd1;
                    b_wi   <= 2'd0;
                    b_busy <= 1'b1;
                end
            end else if (!qb_full && !qh_full && qw_room) begin
                rom_addr <= {b_word_addr[25:3], 3'b000};
                rom_rd   <= 1'b1;
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
        if (reset || (ast == A_IDLE && est == E_IDLE)) begin
            qt_w <= 5'd0;
        end else if (vram_valid && ast != A_SCROLL) begin
            qt[qt_w[3:0]] <= vram_data;
            qt_w <= qt_w + 5'd1;
        end
    end

    // ---- stage C ------------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset || (ast == A_IDLE && est == E_IDLE)) begin
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
        px_we <= 1'b0;
        if (reset) begin
            est  <= E_IDLE;
            qb_r <= 5'd0;
            qw_r <= 7'd0;
        end else begin
            case (est)
                E_IDLE: if (ast == A_MUL && mul_i > 4'd9) begin
                    cx      <= xtl + acc_x;
                    cy      <= ytl + acc_y;
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
                        cur_tx <= tile_x(cx);
                        cur_ty <= tile_y(cy);
                        cur_py <= pix_y(cy);
                        est    <= E_EMIT;
                    end else begin
                        pop_i <= pop_i + 2'd1;
                    end
                end

                E_EMIT: begin
                    px_we <= 1'b1;
                    px_x  <= x;
                    if (!draw_ok) begin
                        px_pix <= 16'd0;
                    end else begin
                        started <= 1'b1;
                        if (mos_x == 4'd0) begin
                            px_pix <= pixel_out;
                            held   <= pixel_out;
                            mos_x  <= mosaic;
                        end else begin
                            px_pix <= held;
                            mos_x  <= mos_x - 4'd1;
                        end
                    end
                    if (optimised && started && !in_range) stopped <= 1'b1;
                    cx <= next_cx;
                    cy <= next_cy;
                    if (x == 9'd511) begin
                        est <= E_DONE;
                    end else begin
                        x <= x + 9'd1;
                        // another tile, or another row of the same one when the line rotates
                        if (ntx != cur_tx || nty != cur_ty || npy != cur_py) est <= E_WAIT;
                    end
                end

                E_DONE: est <= E_IDLE;
                default: est <= E_IDLE;
            endcase
        end
    end


endmodule
