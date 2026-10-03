// SPDX-License-Identifier: GPL-3.0-or-later
//
// Sprite engine: the NEO64-SPR list as MAME draws it (hng64_sprite.ipp, transcribed in
// scripts/render_model.py draw_sprites), per line instead of per frame.
//
// MAME walks the list once and draws each sprite's whole height into a screen-sized bitmap with a
// z-buffer. That bitmap would be 3.6 Mbit here, so the same work is done per line: a pre-pass in
// vblank keeps the sprites that touch the screen, and each line walks those, drawing the ones
// that cover it into the line buffer, guarded by a 512-entry z-buffer. Order within a line is
// list order, as MAME's is.
//
// The sprite list is the snapshot taken at vblank start (docs/phase1_video.md, write timing).
//
// Output word: palette index [11:0], group [14:12], blend [15], as the model emits.
//
// Products (WORKFLOW 14): a sprite is a GPU-like chip, but the two needed here are small and
// once-per-sprite-line, so they are serial shift-adds rather than DSP blocks.
//
// TWO LOOPS. The front end walks the candidates, reads each sprite's words, works out its row and
// issues the reads for its whole chain of tiles (the tile ROM is in DDR3, its latency unbounded),
// the colours and rows landing in queues; it then hands the sprite to the draw loop as a record
// and goes on to the next. The draw loop takes a record and the tiles' colours and rows off the
// queues and draws them, a pixel a clock. The two overlap: while one sprite is drawn the next is
// set up and its rows come back. In one loop the setup, fetch and row waits were 2,550 of the
// 6,050 clocks a line buriki f2500 took (sprite_tb +prof=1). The queues hold two whole chains, so
// the front end runs a sprite ahead; the records keep list order.
//
// TWO PIXELS A CLOCK. The draw loop draws destination pixels x and x + 1 together; consecutive x
// are always one even and one odd, so the z-buffer and the line buffer (hng64_video) are each
// split into an even and an odd half, and each half takes one read and one write a clock. The
// second pixel is drawn when it is still inside the tile, and never under mosaic, which holds
// pixels from one to the next. At a pixel a clock drawing was 3,486 of buriki f2500's 3,804.

module hng64_sprite #(
    parameter int MAXCAND = 256
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        frame_start,        // one cycle in vblank: run the pre-pass
    input  logic        line_start,         // one cycle per line
    input  logic  [8:0] line,
    output logic        busy,

    input  logic [31:0] spriteregs0,
    input  logic [31:0] spriteregs1,

    output logic [13:0] ram_addr,           // sprite RAM snapshot, word address
    output logic        ram_rd,
    input  logic [31:0] ram_data,

    output logic [25:0] rom_addr,           // sprite tile ROM, 8-aligned; 64 MB needs 26 bits
    output logic        rom_rd,
    input  logic        rom_ready,          // the port took the request this cycle
    input  logic [63:0] rom_data,
    input  logic        rom_valid,

    output logic  [1:0] px_we,              // [0] the even-x pixel, [1] the odd-x one
    output logic  [8:0] px_x [0:1],
    output logic [15:0] px_pix [0:1],

    output logic  [8:0] dbg_ncand,     // candidates kept by the pre-pass; for the bench
    output logic [11:0] dbg_xpos,
    output logic  [9:0] dbg_dstwidth,
    output logic  [3:0] dbg_xdrw,
    output logic  [4:0] dbg_st,        // the front end's state, for the bench's profile
    output logic  [2:0] dbg_dst,       // the draw loop's
    output logic        dbg_vis,       // a D_EMIT clock on a pixel inside the line
    // for the stp revision's probe: {ncand, ci, rows asked not drawn, rows arrived not drawn,
    // colours queued, records queued, the draw loop's state, the front end's}
    output logic [48:0] dbg_q,
    output logic  [1:0] dbg_pbv        // stage B's pixels this clock, before the z-test
);

    // registered once: the sprite registers are the frame's, taken with the list (hng64_vbus), and
    // spriteregs0 straight into the pixel decode into the z-test's stage A missed clk2x by 2.0 ns
    logic        zsort, four_bpp;
    logic [4:0]  zoom_shift;
    logic [15:0] offs_x, offs_y;
    always_ff @(posedge clk) begin
        zsort      <= ~spriteregs0[24];
        four_bpp   <= spriteregs0[23];
        zoom_shift <= spriteregs0[27] ? 5'd4 : 5'd8;
        offs_x     <= spriteregs1[15:0];
        offs_y     <= spriteregs1[31:16];
    end

    // the front end
    typedef enum logic [4:0] {
        P_IDLE, P_WA, P_WB, P_WC, P_W0, P_W1, P_W2, P_W4, P_HEIGHT, P_STORE, P_SKIP,
        L_CLEAR, L_PICK, L_TEST, L_WA, L_WB, L_WC, L_W0, L_W1, L_W2, L_W4, L_MOS, L_MULY, L_MULO,
        F_TILE, F_TILE_A, F_TILE_B, F_TILE_C, F_TILE_W, F_PAL, F_ISSUE, F_PUSH
    } state_t;
    state_t st;

    // the draw loop
    typedef enum logic [2:0] { D_IDLE, D_POP, D_WIDTH, D_MULX, D_EMIT } dstate_t;
    dstate_t dst;

    // candidates from the pre-pass, in a RAM read one ahead of the scan: {sprite, top row, the row
    // after its last} (the end as the 12-bit sum the test was written with, wrap and all)
    logic [34:0] cand_mem [0:MAXCAND-1];
    logic [34:0] cand_q;
    logic        cand_we;
    logic  [8:0] cand_wa;
    logic [34:0] cand_wd;
    logic  [8:0] ncand, ci;
    logic        ci_end;                // ci >= ncand, set with ci (ncand holds through the line)
    wire   [8:0] cand_ra = (st == L_TEST) ? ci + 9'd1 : ci;   // L_TEST: the next candidate, ahead
    always_ff @(posedge clk) begin
        if (cand_we) cand_mem[cand_wa] <= cand_wd;
        cand_q <= cand_mem[cand_ra];
    end
    wire        [10:0] cq_idx = cand_q[34:24];
    wire signed [11:0] cq_y   = cand_q[23:12];
    wire signed [11:0] cq_end = cand_q[11:0];

    logic [10:0] sp, cur;
    logic [31:0] w0, w1, w2, w4;

    // fields of the sprite the front end has
    // MAME adds the offset and then sign-extends to 10 bits (hng64_sprite.ipp:284-289), so a
    // position wraps at 1024: sams64's ranking title sits at 480 + 0xfe40, on screen at 32
    wire  [9:0] sum_y = w0[25:16] + offs_y[9:0];
    wire  [9:0] sum_x = w0[9:0] + offs_x[9:0];
    wire signed [11:0] raw_y = $signed({{2{sum_y[9]}}, sum_y});
    wire signed [11:0] raw_x = $signed({{2{sum_x[9]}}, sum_x});
    logic        zoom0;                 // w1's zoom is 0, taken in L_W2 for L_W4 (1.1 ns)
    logic        p_skip;                // P_W4's: not a candidate
    logic        clearing = 1'b0;       // st is L_CLEAR, as a flag for the z-buffer's write select
                                        // (the state decode into it missed clk2x by 1.2 ns)
    logic [31:0] hlim, zstep;           // P_W4's: the height loop's limit and step
    logic [25:0] wa_q;                  // the next ROM read's address, worked out a state ahead
    logic  [1:0] rq_n;                  // ROM reads queued (below)
    logic signed [11:0] ry_q, rx_q;     // taken the clock after w0 (the add into the candidate's
                                        // compares and write missed clk2x by 1.1 ns)
    wire [15:0] zoomy  = w1[31:16], zoomx = w1[15:0];
    wire [10:0] zval   = w2[26:16];
    wire [3:0]  chainy = w2[3:0], chainx = w2[7:4];
    wire        chaini = w2[8];
    wire        yflip  = w4[24];

    logic [31:0] dx, dy, acc;
    logic [10:0] height;
    logic [10:0] rely, mrely;
    logic [31:0] srcy;
    logic [3:0]  fxdrw, ytile, tline;
    logic [18:0] tileno;
    logic        wi;
    // nofs: the next tile's offset, the row's (L_MULO) + (x-flipped ? chainx - fxdrw : fxdrw), kept as fxdrw
    // steps (from fxdrw through the subtract and two adds into ram_addr it missed clk2x by 1.26 ns,
    // 380 endpoints, bc6546a seed 1)
    logic [7:0]  nofs, tile_ofs;
    logic  [9:0] zclr;
    logic  [8:0] skip_acc;                  // P_SKIP: (chainx + 1) * (chainy + 1), shift-add
    logic  [8:0] skip_add;
    logic  [2:0] skip_i;
    wire  [11:0] skip_next = {1'b0, sp} + {3'd0, skip_acc};
    logic  [8:0] zline;                     // the line being drawn, the z-buffer's tag

    // ---- the record a sprite is drawn from, front end to draw loop, list order ---------------------
    typedef struct packed {
        logic signed [11:0] xpos;
        logic [31:0] dx;
        logic  [3:0] chainx;
        logic        xflip, blend, checkerbd;
        logic  [3:0] mosaic;
        logic  [2:0] group;
        logic [10:0] zval;
    } rec_t;
    rec_t        sq [0:3];
    logic  [2:0] sq_w, sq_r;
    wire   [2:0] sq_n = sq_w - sq_r;
    // F_PUSH fills push_rec and the queue takes it the clock after: from the state decode into
    // the four records' enables it missed clk2x by 0.85 ns. F_PUSH comes round again only clocks
    // later, so sq_n has counted it by then.
    rec_t        push_rec;
    logic        push_req;              // F_PUSH's clock, from the front end
    // push_rec loads every clock: push_req picks the one the queue takes (from the state decode
    // into its 70 bits' enables it missed clk2x by 1.2 ns)
    always_ff @(posedge clk) begin
        push_rec.xpos      <= rx_q;
        push_rec.dx        <= dx;
        push_rec.chainx    <= chainx;
        push_rec.xflip     <= w4[25];
        push_rec.blend     <= w4[23];
        push_rec.checkerbd <= w4[26];
        push_rec.mosaic    <= w4[31:28];
        push_rec.group     <= w4[22:20];
        push_rec.zval      <= zval;
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            sq_w <= 3'd0;
        end else if (push_req) begin
            sq[sq_w[1:0]] <= push_rec;
            sq_w <= sq_w + 3'd1;
        end
    end

    // the sprite the draw loop has
    rec_t        d;
    logic signed [11:0] xpos;
    // each with its value a pixel on beside it (_n), so the second pixel needs no adder
    logic [31:0] srcx, srcx_n, cursrcx, cursrcx_n;
    logic signed [31:0] dxs, dxs2;   // +dx, or -dx when the sprite is x-flipped; and twice it
    logic [31:0] dx2;
    logic signed [11:0] ex, ex_n;    // the destination x of the pixel and the next
    logic  [9:0] dwm1;               // dstwidth - 1, for x-flip's second pixel
    logic [3:0]  xdrw;
    logic [9:0]  dstwidth, curx;
    logic [15:0] colour;
    logic [63:0] row0, row1;
    logic [3:0]  mos_x;
    logic [7:0]  held;

    // the chains' rows, and one colour a tile, filled by the front end and drained by the draw
    // loop. A chain is at most 16 tiles of 2 rows; both hold two, and the front end issues a tile
    // only when its colour and rows have room (counting rows asked for, not yet arrived).
    logic  [6:0] qrow_w, qrow_r, qrow_i;
    wire   [6:0] qrow_n = qrow_w - qrow_r;     // arrived, not drawn
    logic  [5:0] qcol_w, qcol_r;
    // The colour entry is written a clock after F_PAL from registers (sprite RAM straight into the
    // MLAB missed clk2x by 2.2 ns), so the count D_POP sees follows qcol_w a clock late too.
    logic  [5:0] qcol_wq;
    wire   [5:0] qcol_n = qcol_wq - qcol_r;
    wire   [6:0] rows_per_tile = four_bpp ? 7'd1 : 7'd2;
    wire         q_room = (qrow_i - qrow_r) <= 7'd62 && (qcol_w - qcol_r) <= 6'd31;

    // serial products, one bit a cycle
    logic [31:0] mul_acc, mul_add;          // the front end's
    logic [4:0]  mul_i;
    logic [7:0]  omul_acc, omul_add;
    logic [3:0]  omul_i;
    logic [3:0]  omul_m;                    // L_MULO's multiplier, shifted a bit a step
    logic [31:0] xmul_acc, xmul_add;        // the draw loop's
    logic [4:0]  xmul_i;

    assign dbg_ncand = ncand;
    assign dbg_xpos = xpos;
    assign dbg_dstwidth = dstwidth;
    assign dbg_xdrw = xdrw;
    // The debug codes come from compares, not the state registers' bits, so synthesis can still
    // take st and dst as state machines and choose their encoding: with the bits on an output the
    // front end's st stayed five binary bits, decoded in front of every register it enables
    // (3f20971 to a10b85c: into w0, rq_head, rq_tail, cand_wa, wa_q, up to 0.7 ns over clk2x).
    logic [4:0] st_code;
    logic [2:0] dst_code;
    always_comb begin
        st_code = '0;
        for (int k = 0; k <= int'(F_PUSH); k++) if (st == state_t'(k)) st_code = 5'(k);
        dst_code = '0;
        for (int k = 0; k <= int'(D_EMIT); k++) if (dst == dstate_t'(k)) dst_code = 3'(k);
    end
    assign dbg_st = st_code;
    assign dbg_dst = dst_code;
    assign dbg_q = {ncand, ci, 7'(qrow_i - qrow_r), qrow_n, qcol_n, sq_n, dst_code, st_code};

    // A sprite tile is 16x16: 4bpp 128 bytes, 8bpp 256 (with the code halved first). Rows are
    // 8 bytes apart; an 8bpp row's second half sits 128 bytes on (hng64.cpp:1729-1750).
    // 4bpp: code * 128. 8bpp: the code is halved when it is read, and the tile is 256 bytes,
    // so the stored value shifts by 8, not 7.
    wire [25:0] tile_base = four_bpp ? {tileno[18:0], 7'd0} : {tileno[17:0], 8'd0};
    wire [3:0]  row_y     = yflip ? (4'd15 - tline) : tline;

    // A tile ends when its source has stepped a whole tile on. Unflipped, that counter runs in
    // the same loop that draws, so the tile is walked once; x-flip has to know the width before
    // it starts, because it draws from the tile's last source pixel backwards, and keeps the
    // separate counting pass.
    wire tile_done = d.xflip ? (curx == dstwidth) : (srcx >= 32'h0010_0000);
    wire [9:0] tile_w = d.xflip ? dstwidth : curx;
    // the pixel after this one is in the tile too, and may be drawn in the same clock
    wire second = d.mosaic == 4'd0 && (d.xflip ? (curx != dwm1) : (srcx_n < 32'h0010_0000));

    // OFF-SCREEN PIXELS RIGHT OF THE LINE ARE NOT WALKED. x only grows along a sprite's row, so
    // the first pixel at x >= 512 ends the row: the tiles left are taken off the queues unseen, one
    // a clock (D_POP with xpos at 512), which also keeps the 12-bit x from wrapping back on screen.
    // The x-flip width count steps 16 source pixels a clock while all 16 stay in the tile: srcx
    // against a limit taken per tile, as an add and compare there missed clk2x by 1.2 ns.
    wire [35:0] dx16 = {4'd0, d.dx} << 4;
    logic        w16_ok;                // 16 steps are less than a tile
    logic [20:0] lim16;                 // 0x100000 - 16 dx
    wire         src16 = w16_ok && srcx[31:21] == 11'd0 && srcx[20:0] < lim16;

    // The z-buffer and the two queues are read in the clock they are addressed, so each is an
    // MLAB (hng64_mlab): in registers they were 8,000 of the engine's 11,700. The z-buffer's two
    // writes, the frame's clear and a drawn pixel, happen in different states and share its port.
    // The z-buffer is two halves, [0] even x and [1] odd, each 256 entries.
    logic  [1:0] z_we;
    logic  [7:0] z_waddr [0:1];
    logic [10:0] z_wdata [0:1];
    wire  [63:0] qrow_a, qrow_b;
    wire  [15:0] qcol_q;
    logic        qcol_we, qcol_we_q;
    logic [15:0] qcol_wd, qcol_wd_q;
    logic  [4:0] qcol_wa_q;
    always_ff @(posedge clk) begin
        qcol_we_q <= qcol_we;
        qcol_wa_q <= qcol_w[4:0];
        qcol_wd_q <= qcol_wd;
        qcol_wq   <= qcol_w;
    end

    // THE Z-BUFFER IS NOT CLEARED A LINE. Each entry carries the line that wrote it, and one with
    // another line's tag reads as cleared; the whole buffer is cleared once a frame, before the
    // pre-pass, so a tag cannot survive to the same line of the next frame (a line is drawn once
    // a frame; the flush pass's re-render of 447 is not shown). The per-line clear was 512 of the
    // line's clocks (sprite_tb +prof=1, buriki f2500).
    //
    // A drawn pixel goes through three stages: D_EMIT works out its x and pixel and addresses the
    // z-buffer (A0); the pixel is registered (A); the z is there, registered at the M10K's output,
    // and B compares and writes. In one clock through an MLAB the x adder, the read, the compare and
    // the write missed clk2x by 4.4 ns, and a 512-deep MLAB is sixteen blocks behind a read mux,
    // which alone missed by 4.5 ns; so the z-buffer is an M10K read two clocks early. The two
    // writes B makes meanwhile, in the clock of the read and the next, are bypassed: a pixel at an
    // address just written takes the written z. (Read a clock early, the RAM's unregistered output
    // through the compare into its own write missed clk2x by up to 1.3 ns, 8d5f748 seed 1.)
    logic  [8:0] z_wtag [0:1];
    logic  [7:0] z_raddr [0:1];             // stage A0's: the half's pixel, this one or the next
    logic  [7:0] z_raddr_q [0:1];           // the same, a clock on
    wire  [23:0] zq_full [0:1];
    logic  [1:0] zbyp1, zbyp1_q, zbyp2;     // written in the read's clock; in the next
    logic [10:0] zd1 [0:1], zd1_q [0:1], zd2 [0:1];
    logic  [1:0] ztest;

    // stage B, a pixel a half: which of the two it is, its x and its word
    logic  [1:0] pbv;
    logic        a_v0, a_v1;                // stage A0's pixels in the line: drawn unless 0
    logic  [8:0] pbx [0:1];
    logic [15:0] pbp [0:1];
    logic [10:0] pb_zval;
    // registered: from the state decode into hng64_video's sequencer it missed clk2x by 0.9 ns.
    // It rises a clock after the engine starts, which the sequencer allows for.
    always_ff @(posedge clk) busy <= st != P_IDLE || dst != D_IDLE || sq_n != 3'd0 || pbv != 2'd0
                                    || rq_n != 2'd0 || a_v0 || a_v1;
    assign dbg_pbv = pbv;

    genvar gz;
    generate
        for (gz = 0; gz < 2; gz++) begin : g_z
            hng64_bram #(.AW(8), .DW(24), .OUTREG_B(1'b1)) u_zbuf (
                .a_clk(clk), .a_addr(z_waddr[gz]), .a_be({3{z_we[gz]}}),
                .a_wdata({4'd0, z_wtag[gz], z_wdata[gz]}), .a_rdata(),
                .b_clk(clk), .b_addr(z_raddr[gz]), .b_rdata(zq_full[gz]));
            always_ff @(posedge clk) begin
                zbyp1[gz]     <= z_we[gz] && z_waddr[gz] == z_raddr[gz];
                zd1[gz]       <= z_wdata[gz];
                z_raddr_q[gz] <= z_raddr[gz];
                zbyp1_q[gz]   <= zbyp1[gz];
                zd1_q[gz]     <= zd1[gz];
                zbyp2[gz]     <= z_we[gz] && z_waddr[gz] == z_raddr_q[gz];
                zd2[gz]       <= z_wdata[gz];
            end
            // the three compares, then the bypass select (through the select first missed clk2x
            // by 1.6 ns), the later write first; an entry from another line is the cleared value:
            // 0 under zsort (>= always passes), else 0x7ff
            wire [10:0] zq    = zq_full[gz][10:0];
            wire        mine  = zq_full[gz][19:11] == zline;
            wire        t_ram = !mine ? (zsort || pb_zval < 11'h7ff)
                                      : zsort ? (pb_zval >= zq) : (pb_zval < zq);
            wire        t_b1  = zsort ? (pb_zval >= zd1_q[gz]) : (pb_zval < zd1_q[gz]);
            wire        t_b2  = zsort ? (pb_zval >= zd2[gz]) : (pb_zval < zd2[gz]);
            assign ztest[gz] = zbyp2[gz] ? t_b2 : zbyp1_q[gz] ? t_b1 : t_ram;
        end
    endgenerate
    hng64_mlab #(.AW(6), .DW(64)) u_qrow_a (
        .clk(clk), .we(rom_valid), .waddr(qrow_w[5:0]), .wdata(rom_data),
        .raddr(qrow_r[5:0]), .rdata(qrow_a));
    hng64_mlab #(.AW(6), .DW(64)) u_qrow_b (          // the same rows, for the second read
        .clk(clk), .we(rom_valid), .waddr(qrow_w[5:0]), .wdata(rom_data),
        .raddr(6'(qrow_r + 7'd1)), .rdata(qrow_b));
    hng64_mlab #(.AW(5), .DW(16)) u_qcol (
        .clk(clk), .we(qcol_we_q), .waddr(qcol_wa_q), .wdata(qcol_wd_q),
        .raddr(qcol_r[4:0]), .rdata(qcol_q));

    // Row beats land in the queue as they come back, in order. Neither pointer is reset per
    // sprite: a sprite issues exactly as many reads as it draws rows, so the two stay in step,
    // and a tile cannot start drawing until its rows have arrived.
    always_ff @(posedge clk) begin
        if (reset) qrow_w <= 7'd0;
        else if (rom_valid) qrow_w <= qrow_w + 7'd1;
    end

    // Pixel from the fetched row. 4bpp: one 64-bit beat is the whole 16-pixel row, nibbles in
    // MAME's order (hng64.cpp:1735). 8bpp: two beats, bytes in the same order.
    function automatic logic [7:0] pix_at(input logic [3:0] sx, input logic fourbpp,
                                          input logic [63:0] r0, input logic [63:0] r1);
        logic [63:0] rw;
        rw = (!fourbpp && sx[3]) ? r1 : r0;
        if (fourbpp) begin
            case (sx)
                4'd0:  return {4'd0, rw[7:4]};
                4'd1:  return {4'd0, rw[3:0]};
                4'd2:  return {4'd0, rw[39:36]};
                4'd3:  return {4'd0, rw[35:32]};
                4'd4:  return {4'd0, rw[15:12]};
                4'd5:  return {4'd0, rw[11:8]};
                4'd6:  return {4'd0, rw[47:44]};
                4'd7:  return {4'd0, rw[43:40]};
                4'd8:  return {4'd0, rw[23:20]};
                4'd9:  return {4'd0, rw[19:16]};
                4'd10: return {4'd0, rw[55:52]};
                4'd11: return {4'd0, rw[51:48]};
                4'd12: return {4'd0, rw[31:28]};
                4'd13: return {4'd0, rw[27:24]};
                4'd14: return {4'd0, rw[63:60]};
                default: return {4'd0, rw[59:56]};
            endcase
        end else begin
            case (sx[2:0])
                3'd0: return rw[7:0];
                3'd1: return rw[39:32];
                3'd2: return rw[15:8];
                3'd3: return rw[47:40];
                3'd4: return rw[23:16];
                3'd5: return rw[55:48];
                3'd6: return rw[31:24];
                default: return rw[63:56];
            endcase
        end
    endfunction
    // the step is already negated when flipped
    wire [7:0] sprite_pix  = pix_at(cursrcx[19:16], four_bpp, row0, row1);
    wire [7:0] sprite_pix1 = pix_at(cursrcx_n[19:16], four_bpp, row0, row1);

    // mosaic holds the last fetched pixel; checkerboard drops every other pixel of every other line
    wire [7:0] mos_pix  = (d.mosaic == 4'd0 || mos_x == 4'd0) ? sprite_pix : held;
    wire       drop     = d.checkerbd && (ex[0] ^ zline[0]);
    wire       drop1    = d.checkerbd && (ex_n[0] ^ zline[0]);
    wire [7:0] out_pix  = drop ? 8'd0 : mos_pix;
    wire [7:0] out_pix1 = drop1 ? 8'd0 : sprite_pix1;

    // the first line of a mosaic group, for a sprite that has mosaic (L_MOS)
    logic        mos_start;
    wire         mos_done;
    wire  [10:0] mos_base;
    hng64_mosaic #(.W(11)) u_mos (
        .clk(clk), .start(mos_start), .x(rely), .m(w4[31:28]), .done(mos_done), .base(mos_base));

    // ROM reads go out through two entries: the front end waits in F_ISSUE only while both are
    // full (rq_n, a register). It used to stop whole while the port had not taken its read, which
    // put the arbiter's ready in front of every front-end register (0.7 ns over clk2x).
    // a head and a tail register, so the port's address is a register (a select by read pointer
    // into the DDR3 queue missed clk2x by 1.2 ns)
    logic [25:0] rq_head, rq_tail;
    wire         rq_push = !reset && st == F_ISSUE && rq_n != 2'd2;
    wire         rq_pop  = rq_n != 2'd0 && rom_ready;
    wire  [25:0] rq_new  = {wa_q[25:3], 3'b000};
    assign rom_rd   = rq_n != 2'd0;
    assign rom_addr = rq_head;
    always_ff @(posedge clk) begin
        if (reset) begin
            rq_n <= 2'd0;
        end else begin
            case ({rq_push, rq_pop})
                2'b10: if (rq_n == 2'd0) rq_head <= rq_new; else rq_tail <= rq_new;
                2'b01: rq_head <= rq_tail;
                2'b11: if (rq_n == 2'd1) rq_head <= rq_new;
                       else begin rq_head <= rq_tail; rq_tail <= rq_new; end
                default: ;
            endcase
            rq_n <= rq_n + 2'(rq_push) - 2'(rq_pop);
        end
    end

    // the writes the front end makes, for the MLABs' registered write ports, and the drawn pixel's
    always_comb begin
        qcol_we = 1'b0;
        qcol_wd = four_bpp ? {4'd0, ram_data[23:16], 4'd0} : {4'd0, ram_data[19:16], 8'd0};
        if (!reset && st == F_PAL) qcol_we = 1'b1;
        for (int b = 0; b < 2; b++) begin
            z_we[b]    = 1'b0;
            z_waddr[b] = pbx[b][8:1];
            z_wdata[b] = pb_zval;
            z_wtag[b]  = zline;
            if (!reset && clearing && zclr[0] == 1'(b)) begin
                z_we[b]    = 1'b1;
                z_waddr[b] = zclr[8:1];
                z_wdata[b] = zsort ? 11'd0 : 11'h7ff;
                z_wtag[b]  = 9'h1ff;        // no line's: lines are 0-447
            end
            if (!reset && pbv[b] && ztest[b]) z_we[b] = 1'b1;
        end
    end

    // stage A0: the loop's two pixels, registered before their zero test and the z-buffer read
    // (from cursrcx through the row's pixel select and the zero test into pbv it missed clk2x by
    // up to 0.81 ns, 8d5f748 seed 1)
    wire in0 = ex >= 12'sd0 && ex < 12'sd512;
    wire in1 = ex_n >= 12'sd0 && ex_n < 12'sd512;
    assign dbg_vis = dst == D_EMIT && !tile_done && in0;
    logic [11:0] a_ex, a_exn;
    logic  [7:0] a_pix0, a_pix1;
    logic [15:0] a_col;
    logic [10:0] a_z;
    always_ff @(posedge clk) begin
        a_v0   <= !reset && dst == D_EMIT && !tile_done && in0;
        a_v1   <= !reset && dst == D_EMIT && !tile_done && second && in1;
        a_ex   <= ex;
        a_exn  <= ex_n;
        a_pix0 <= out_pix;
        a_pix1 <= out_pix1;
        a_col  <= colour | {d.blend, d.group, 12'd0};
        a_z    <= d.zval;
    end

    // stage A: the pixel at a_ex and, when there was a second, the one at a_exn, each to its half
    wire emit0 = a_v0 && a_pix0 != 8'd0;
    wire emit1 = a_v1 && a_pix1 != 8'd0;
    always_comb
        for (int b = 0; b < 2; b++)
            z_raddr[b] = (ex[0] == 1'(b)) ? ex[8:1] : ex_n[8:1];
    always_ff @(posedge clk) begin
        pb_zval <= a_z;
        for (int b = 0; b < 2; b++) begin
            if (a_ex[0] == 1'(b)) begin
                pbv[b] <= !reset && emit0;
                pbx[b] <= a_ex[8:0];
                pbp[b] <= a_col | {8'd0, a_pix0};
            end else begin
                pbv[b] <= !reset && emit1;
                pbx[b] <= a_exn[8:0];
                pbp[b] <= a_col | {8'd0, a_pix1};
            end
        end
    end

    // ---- the front end ----------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        mos_start <= 1'b0;
        cand_we   <= 1'b0;
        push_req  <= 1'b0;
        if (reset) begin
            ram_rd <= 1'b0;
            clearing <= 1'b0;
            st     <= P_IDLE;
            ncand  <= 9'd0;
            zclr   <= 10'd512;
            qcol_w <= 6'd0;
            qrow_i <= 7'd0;
        end else begin
            ram_rd <= 1'b0;
            case (st)
                P_IDLE: begin
                    if (frame_start) begin
                        zclr <= 10'd0;
                        st   <= L_CLEAR;
                        clearing <= 1'b1;
                    end else if (line_start) begin
                        zline  <= line;
                        ci     <= 9'd0;
                        ci_end <= ncand == 9'd0;
                        st     <= L_PICK;
                    end
                end

                // A word is on ram_data four clocks after the state that addresses it: ram_addr is
                // a register, hng64_vbus registers it again, and the list is an M10K that registers
                // the address and its output. So addresses go out three states ahead.
                P_WA: begin ram_addr <= {sp, 3'd1}; ram_rd <= 1'b1; st <= P_WB; end
                P_WB: begin ram_addr <= {sp, 3'd2}; ram_rd <= 1'b1; st <= P_WC; end
                P_WC: begin ram_addr <= {sp, 3'd4}; ram_rd <= 1'b1; st <= P_W0; end
                P_W0: begin w0 <= ram_data; st <= P_W1; end
                P_W1: begin w1 <= ram_data; ry_q <= raw_y; st <= P_W2; end
                P_W2: begin w2 <= ram_data; st <= P_W4; end
                // the height loop's decision, limit and step from w1 and w2 here, a state ahead (from
                // w1 through the compares into the loop's registers it missed clk2x by 1.4 ns)
                P_W4: begin
                    w4     <= ram_data;
                    acc    <= 32'd0;
                    height <= 11'd0;
                    p_skip <= zoomx == 16'd0 || zoomy == 16'd0 || (zsort && zval == 11'd0)
                              || (!zsort && zval == 11'h7ff);
                    hlim   <= ({28'd0, chainy} + 32'd1) << 20;
                    zstep  <= {16'd0, zoomy} << zoom_shift;
                    st     <= P_HEIGHT;
                end

                // destination height: step the source until it covers the chained tiles
                // Not a candidate: zoom 0 and zsort's zval 0 (hng64_sprite.ipp:319-334), and without
                // zsort zval 0x7ff, which no z-test passes (the buffer clears to 0x7ff, `<` after):
                // fatfurwa keeps 1,280 of them in the list, buriki 93 on screen
                P_HEIGHT: begin
                    if (p_skip) begin
                        height <= 11'd0;
                        st     <= P_STORE;
                    end else if (acc < hlim) begin
                        acc    <= acc + zstep;
                        height <= height + 11'd1;
                    end else begin
                        st <= P_STORE;
                    end
                end

                P_STORE: begin
                    if (height != 11'd0 && ncand != MAXCAND[8:0]
                        && ry_q < 12'sd448 && (ry_q + $signed({1'b0, height})) > 12'sd0) begin
                        cand_we <= 1'b1;
                        cand_wa <= ncand;
                        cand_wd <= {sp, ry_q, 12'(ry_q + $signed({1'b0, height}))};
                        ncand   <= ncand + 9'd1;
                    end
                    // a chained sprite's tiles are the entries after it (hng64_sprite.ipp:303):
                    // the next sprite is (chainx + 1) * (chainy + 1) on
                    if (chaini) begin
                        skip_acc <= 9'd0;
                        skip_add <= {5'd0, chainx} + 9'd1;
                        skip_i   <= 3'd0;
                        st       <= P_SKIP;
                    end else if (sp == 11'd1535) begin
                        st <= P_IDLE;
                    end else begin
                        sp       <= sp + 11'd1;
                        ram_addr <= {sp + 11'd1, 3'd0};
                        ram_rd   <= 1'b1;
                        st       <= P_WA;
                    end
                end

                P_SKIP: begin
                    if (skip_i == 3'd5) begin
                        if (skip_next >= 12'd1536) begin
                            st <= P_IDLE;
                        end else begin
                            sp       <= skip_next[10:0];
                            ram_addr <= {skip_next[10:0], 3'd0};
                            ram_rd   <= 1'b1;
                            st       <= P_WA;
                        end
                    end else begin
                        if ((({1'b0, chainy} + 5'd1) >> skip_i) & 5'd1) skip_acc <= skip_acc + skip_add;
                        skip_add <= skip_add << 1;
                        skip_i   <= skip_i + 3'd1;
                    end
                end

                // the frame's z-buffer clear, then the pre-pass
                L_CLEAR: begin
                    if (zclr == 10'd511) begin
                        clearing <= 1'b0;
                        sp       <= 11'd0;
                        ncand    <= 9'd0;
                        ram_addr <= 14'd0;
                        ram_rd   <= 1'b1;
                        st       <= P_WA;
                    end else begin
                        zclr <= zclr + 10'd1;
                    end
                end

                // ------------------------------------------------------ per line
                // the RAM is read at ci here; L_TEST tests it and reads ci + 1 meanwhile
                L_PICK: st <= L_TEST;

                L_TEST: begin
                    if (ci_end) begin
                        st <= P_IDLE;               // the draw loop finishes the line
                    end else if (cq_y <= $signed({3'b0, zline}) && $signed({3'b0, zline}) < cq_end) begin
                        cur      <= cq_idx;
                        rely     <= {2'b0, zline} - cq_y[10:0];
                        ram_addr <= {cq_idx, 3'd0};
                        ram_rd   <= 1'b1;
                        st       <= L_WA;
                    end else begin
                        ci     <= ci + 9'd1;
                        ci_end <= {1'b0, ci} + 10'd1 >= {1'b0, ncand};
                    end
                end

                L_WA: begin ram_addr <= {cur, 3'd1}; ram_rd <= 1'b1; st <= L_WB; end
                L_WB: begin ram_addr <= {cur, 3'd2}; ram_rd <= 1'b1; st <= L_WC; end
                L_WC: begin ram_addr <= {cur, 3'd4}; ram_rd <= 1'b1; st <= L_W0; end
                L_W0: begin w0 <= ram_data; st <= L_W1; end
                L_W1: begin w1 <= ram_data; rx_q <= raw_x; st <= L_W2; end
                L_W2: begin w2 <= ram_data; zoom0 <= zoomx == 16'd0 || zoomy == 16'd0; st <= L_W4; end
                // MAME tests zoom where it draws, not only in a list walk: a zoom of 0 here would
                // never finish an x-flipped tile's width count (D_WIDTH)
                L_W4: if (zoom0) begin
                    ci     <= ci + 9'd1;
                    ci_end <= {1'b0, ci} + 10'd1 >= {1'b0, ncand};
                    st     <= L_PICK;
                end else begin
                    w4      <= ram_data;
                    dx      <= {16'd0, zoomx} << zoom_shift;
                    dy      <= {16'd0, zoomy} << zoom_shift;
                    mul_acc <= 32'd0;
                    mul_add <= {16'd0, zoomy} << zoom_shift;
                    mul_i   <= 5'd0;
                    // mosaic keeps the first line of each group (hng64_sprite.ipp:349): found by
                    // hng64_mosaic in L_MOS, only when the sprite has mosaic
                    mrely   <= rely;
                    if (ram_data[31:28] == 4'd0) st <= L_MULY;
                    else begin
                        mos_start <= 1'b1;
                        st        <= L_MOS;
                    end
                end

                L_MOS: if (mos_done) begin
                    mrely <= mos_base;
                    st    <= L_MULY;
                end

                // srcy = mrely * dy
                L_MULY: begin
                    if (mul_i == 5'd11) begin
                        srcy     <= mul_acc;
                        ytile    <= mul_acc[23:20];
                        tline    <= mul_acc[19:16];
                        omul_acc <= 8'd0;
                        omul_add <= {4'd0, chainx} + 8'd1;
                        omul_i   <= 4'd0;
                        omul_m   <= yflip ? chainy - mul_acc[23:20] : mul_acc[23:20];
                        fxdrw    <= 4'd0;
                        st       <= L_MULO;
                    end else begin
                        // mrely shifts a bit a step: tested as mrely[mul_i], the select and the
                        // state decode into mul_acc missed clk2x by 0.43 ns (bc6546a seed 1)
                        if (mrely[0]) mul_acc <= mul_acc + mul_add;
                        mrely   <= mrely >> 1;
                        mul_add <= mul_add << 1;
                        mul_i   <= mul_i + 5'd1;
                    end
                end

                // the row's offset, (yflip ? chainy - ytile : ytile) * (chainx + 1), into nofs
                L_MULO: begin
                    if (omul_i == 4'd4) begin
                        nofs     <= omul_acc + (w4[25] ? {4'd0, chainx} : 8'd0);    // fxdrw is 0
                        st       <= F_TILE;
                    end else begin
                        if (omul_m[0]) omul_acc <= omul_acc + omul_add;
                        omul_m   <= omul_m >> 1;
                        omul_add <= omul_add << 1;
                        omul_i   <= omul_i + 4'd1;
                    end
                end

                // ---- fetch loop: the whole chain, without waiting for any of it -------------
                // a tile goes ahead when the queues have room for its colour and rows
                F_TILE: if (q_room) begin
                    tile_ofs <= nofs;
                    ram_addr <= chaini ? ({cur, 3'd4} + {nofs, 3'd0}) : {cur, 3'd4};
                    ram_rd   <= 1'b1;
                    st       <= F_TILE_A;
                end
                // the colour word's address, while the tile word is on its way
                F_TILE_A: begin
                    ram_addr <= chaini ? ({cur, 3'd3} + {tile_ofs, 3'd0}) : {cur, 3'd3};
                    ram_rd   <= 1'b1;
                    st       <= F_TILE_B;
                end
                F_TILE_B: st <= F_TILE_C;
                F_TILE_C: st <= F_TILE_W;
                F_TILE_W: begin
                    // without chaining the tile number walks with the offset instead
                    // 8bpp halves the code BEFORE the chain offset is added
                    // (hng64_sprite.ipp:219-235), not after
                    tileno   <= (four_bpp ? ram_data[18:0] : {1'b0, ram_data[18:1]})
                              + (chaini ? 19'd0 : {11'd0, tile_ofs});
                    st       <= F_PAL;
                end
                F_PAL: begin
                    qcol_w <= qcol_w + 6'd1;
                    wi     <= 1'b0;
                    wa_q   <= tile_base + {19'd0, row_y, 3'b000};   // word_addr with wi 0
                    st     <= F_ISSUE;
                end
                F_ISSUE: if (rq_n != 2'd2) begin    // rq_push takes the read
                    qrow_i   <= qrow_i + 7'd1;
                    wa_q     <= wa_q + 26'd128;             // an 8bpp row's second half
                    if (four_bpp || wi) begin
                        if (fxdrw == chainx) begin
                            st <= F_PUSH;
                        end else begin
                            fxdrw <= fxdrw + 4'd1;
                            nofs  <= w4[25] ? nofs - 8'd1 : nofs + 8'd1;
                            st    <= F_TILE;
                        end
                    end else begin
                        wi <= 1'b1;
                    end
                end

                // the sprite to the draw loop, then the next candidate
                F_PUSH: if (sq_n != 3'd4) begin
                    push_req <= 1'b1;
                    ci     <= ci + 9'd1;
                    ci_end <= {1'b0, ci} + 10'd1 >= {1'b0, ncand};
                    st     <= L_PICK;
                end

                default: st <= P_IDLE;
            endcase
        end
    end

    // ---- the draw loop ----------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            dst    <= D_IDLE;
            sq_r   <= 3'd0;
            qcol_r <= 6'd0;
            qrow_r <= 7'd0;
        end else begin
            case (dst)
                D_IDLE: if (sq_n != 3'd0) begin
                    d      <= sq[sq_r[1:0]];
                    xpos   <= sq[sq_r[1:0]].xpos;
                    dx2    <= sq[sq_r[1:0]].dx << 1;
                    sq_r   <= sq_r + 3'd1;
                    xdrw   <= 4'd0;
                    srcx   <= 32'd0;
                    dst    <= D_POP;
                end

                // take one tile's colour and rows off the queues
                // the tile's starting values are set whether or not it is taken this clock: they
                // are used only after D_POP, and gating them on the queues missed clk2x by 1 ns
                D_POP: begin
                    dstwidth <= 10'd0;
                    curx     <= 10'd0;
                    mos_x    <= 4'd0;
                    ex       <= xpos;
                    ex_n     <= xpos + 12'sd1;
                    w16_ok   <= dx16 < 36'h0010_0000;
                    lim16    <= 21'h10_0000 - dx16[20:0];
                    if (qcol_n != 6'd0 && qrow_n >= rows_per_tile && xpos >= 12'sd512) begin
                        qcol_r <= qcol_r + 6'd1;
                        qrow_r <= qrow_r + rows_per_tile;
                        if (xdrw == d.chainx) dst <= D_IDLE;
                        else                  xdrw <= xdrw + 4'd1;
                    end else if (qcol_n != 6'd0 && qrow_n >= rows_per_tile) begin
                        colour   <= qcol_q;
                        row0     <= qrow_a;
                        row1     <= qrow_b;
                        qcol_r   <= qcol_r + 6'd1;
                        qrow_r   <= qrow_r + rows_per_tile;
                        if (d.xflip) begin
                            dst <= D_WIDTH;
                        end else begin
                            cursrcx   <= 32'd0;
                            cursrcx_n <= d.dx;
                            srcx_n    <= srcx + d.dx;
                            dxs       <= $signed(d.dx);
                            dxs2      <= $signed(dx2);
                            dst       <= D_EMIT;
                        end
                    end
                end

                // dstwidth: destination pixels this tile covers (hng64_sprite.ipp:390)
                D_WIDTH: begin
                    if (src16) begin
                        srcx     <= srcx + dx16[31:0];
                        dstwidth <= dstwidth + 10'd16;
                    end else if (srcx < 32'h0010_0000) begin
                        srcx     <= srcx + d.dx;
                        dstwidth <= dstwidth + 10'd1;
                    end else begin
                        srcx     <= srcx & 32'h000f_ffff;
                        curx     <= 10'd0;
                        // x-flip starts at the tile's last source pixel and steps back
                        // (hng64_sprite.ipp:180): cursrcx = (dstwidth - 1) * dx, dx negated
                        xmul_acc <= 32'd0;
                        xmul_add <= d.dx;
                        xmul_i   <= 5'd0;
                        dst      <= D_MULX;
                    end
                end

                D_MULX: begin
                    if (xmul_i == 5'd10) begin
                        cursrcx   <= xmul_acc;
                        cursrcx_n <= xmul_acc - d.dx;
                        dxs       <= -$signed(d.dx);
                        dxs2      <= -$signed(dx2);
                        dwm1      <= dstwidth - 10'd1;
                        dst       <= D_EMIT;
                    end else begin
                        if ((dstwidth - 10'd1) >> xmul_i & 1'b1) xmul_acc <= xmul_acc + xmul_add;
                        xmul_add <= xmul_add << 1;
                        xmul_i   <= xmul_i + 5'd1;
                    end
                end

                D_EMIT: begin
                    if (!tile_done && ex >= 12'sd512) begin
                        if (!d.xflip) srcx <= srcx & 32'h000f_ffff;
                        if (xdrw == d.chainx) begin
                            dst <= D_IDLE;
                        end else begin
                            xdrw <= xdrw + 4'd1;
                            xpos <= 12'sd512;
                            dst  <= D_POP;
                        end
                    end else if (tile_done) begin
                        if (!d.xflip) srcx <= srcx & 32'h000f_ffff;
                        if (xdrw == d.chainx) begin
                            dst <= D_IDLE;
                        end else begin
                            xdrw <= xdrw + 4'd1;
                            xpos <= xpos + $signed({2'b0, tile_w});
                            dst  <= D_POP;
                        end
                    end else if (second) begin
                        curx      <= curx + 10'd2;
                        cursrcx   <= cursrcx + dxs2;
                        cursrcx_n <= cursrcx_n + dxs2;
                        if (!d.xflip) begin
                            srcx   <= srcx + dx2;
                            srcx_n <= srcx_n + dx2;
                        end
                        ex   <= ex + 12'sd2;
                        ex_n <= ex_n + 12'sd2;
                    end else begin
                        curx      <= curx + 10'd1;
                        cursrcx   <= cursrcx + dxs;
                        cursrcx_n <= cursrcx_n + dxs;
                        if (!d.xflip) begin
                            srcx   <= srcx + d.dx;
                            srcx_n <= srcx_n + d.dx;
                        end
                        ex   <= ex + 12'sd1;
                        ex_n <= ex_n + 12'sd1;
                        if (d.mosaic == 4'd0 || mos_x == 4'd0) begin
                            held  <= sprite_pix;
                            mos_x <= d.mosaic;
                        end else begin
                            mos_x <= mos_x - 4'd1;
                        end
                    end
                end

                default: dst <= D_IDLE;
            endcase
        end
        // stage B: a pixel a half
        for (int b = 0; b < 2; b++) begin
            px_we[b]  <= !reset && pbv[b] && ztest[b];
            px_x[b]   <= pbx[b];
            px_pix[b] <= pbp[b];
        end
    end

endmodule
