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
// The tile ROM is in DDR3 and its latency is not bounded (docs/MEMORY.md), so a sprite's whole
// chain of tiles is asked for before any of it is drawn: the fetch loop walks the chain reading
// tile numbers and palettes from the on-chip list and issuing the row reads back to back, and the
// draw loop then takes rows off a queue. A sprite-line waits for memory once, not twice per
// chained tile.

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

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [15:0] px_pix,

    output logic  [8:0] dbg_ncand,     // candidates kept by the pre-pass; for the bench
    output logic [11:0] dbg_xpos,
    output logic  [9:0] dbg_dstwidth,
    output logic  [3:0] dbg_xdrw
);

    wire        zsort      = ~spriteregs0[24];
    wire        four_bpp   = spriteregs0[23];
    wire [4:0]  zoom_shift = spriteregs0[27] ? 5'd4 : 5'd8;
    wire [15:0] offs_x     = spriteregs1[15:0];
    wire [15:0] offs_y     = spriteregs1[31:16];

    typedef enum logic [4:0] {
        P_IDLE, P_W0, P_W1, P_W2, P_W4, P_HEIGHT, P_STORE,
        L_CLEAR, L_PICK, L_W0, L_W1, L_W2, L_W4, L_MULY, L_MULO,
        F_TILE, F_TILE_W, F_PAL, F_ISSUE, L_POP, L_WIDTH, L_MULX, L_EMIT
    } state_t;
    state_t st;

    // candidates from the pre-pass
    logic [10:0] cand_idx [0:MAXCAND-1];
    logic signed [11:0] cand_y [0:MAXCAND-1];
    logic [10:0] cand_h [0:MAXCAND-1];
    logic  [8:0] ncand, ci;

    logic [10:0] sp, cur;
    logic [31:0] w0, w1, w2, w4;

    // fields of the sprite being handled
    wire signed [11:0] raw_y = $signed({{4{1'b0}}, w0[25:16]}) - (w0[25] ? 12'sd1024 : 12'sd0)
                             + $signed({{4{1'b0}}, offs_y[9:0]});
    wire signed [11:0] raw_x = $signed({{4{1'b0}}, w0[9:0]})  - (w0[9]  ? 12'sd1024 : 12'sd0)
                             + $signed({{4{1'b0}}, offs_x[9:0]});
    wire [15:0] zoomy  = w1[31:16], zoomx = w1[15:0];
    wire [10:0] zval   = w2[26:16];
    wire [3:0]  chainy = w2[3:0], chainx = w2[7:4];
    wire        chaini = w2[8];
    wire        blend  = w4[23], checkerbd = w4[26];
    wire [3:0]  mosaic = w4[31:28];
    wire        yflip  = w4[24], xflip = w4[25];
    wire [2:0]  group  = w4[22:20];

    logic [31:0] dx, dy, acc;
    logic [10:0] height;

    logic signed [11:0] xpos;
    logic [10:0] rely, mrely;
    logic [31:0] srcy, srcx, cursrcx;
    logic signed [31:0] dxs;   // +dx, or -dx when the sprite is x-flipped
    logic [3:0]  xdrw, ytile, tline;
    logic [9:0]  dstwidth, curx;
    logic [18:0] tileno;
    logic [15:0] colour;
    logic [63:0] row0, row1;
    logic        wi;
    logic [25:0] rowbase;
    logic [7:0]  base_ofs, tile_ofs;
    logic [3:0]  mos_x;
    logic [7:0]  held;

    logic [10:0] zbuf [0:511];
    logic  [9:0] zclr;

    // the chain's rows, and one colour a tile, filled by the fetch loop and drained by the draw
    // loop. A chain is at most 16 tiles of 2 rows, so both are sized for the worst case and
    // neither can overrun.
    logic [63:0] qrow [0:31];
    logic  [5:0] qrow_w, qrow_r;
    wire   [5:0] qrow_n = qrow_w - qrow_r;
    logic [15:0] qcol [0:15];
    logic  [4:0] qcol_w, qcol_r;
    wire   [4:0] qcol_n = qcol_w - qcol_r;
    wire   [5:0] rows_per_tile = four_bpp ? 6'd1 : 6'd2;

    // serial products, one bit a cycle
    logic [31:0] mul_acc, mul_add;
    logic [4:0]  mul_i;
    logic [7:0]  omul_acc, omul_add;
    logic [3:0]  omul_i;

    assign busy = st != P_IDLE;   // the z-buffer clear is part of the line, not idle
    assign dbg_ncand = ncand;
    assign dbg_xpos = xpos;
    assign dbg_dstwidth = dstwidth;
    assign dbg_xdrw = xdrw;

    // A sprite tile is 16x16: 4bpp 128 bytes, 8bpp 256 (with the code halved first). Rows are
    // 8 bytes apart; an 8bpp row's second half sits 128 bytes on (hng64.cpp:1729-1750).
    // 4bpp: code * 128. 8bpp: the code is halved when it is read, and the tile is 256 bytes,
    // so the stored value shifts by 8, not 7.
    wire [25:0] tile_base = four_bpp ? {tileno[18:0], 7'd0} : {tileno[17:0], 8'd0};
    wire [3:0]  row_y     = yflip ? (4'd15 - tline) : tline;
    wire [25:0] word_addr = tile_base + {19'd0, row_y, 3'b000} + (wi ? 26'd128 : 26'd0);

    // A tile ends when its source has stepped a whole tile on. Unflipped, that counter runs in
    // the same loop that draws, so the tile is walked once; x-flip has to know the width before
    // it starts, because it draws from the tile's last source pixel backwards, and keeps the
    // separate counting pass.
    wire tile_done = xflip ? (curx == dstwidth) : (srcx >= 32'h0010_0000);
    wire [9:0] tile_w = xflip ? dstwidth : curx;

    wire signed [11:0] dstx = xpos + $signed({2'b0, curx});
    wire [8:0] zx = dstx[8:0];
    wire ztest = zsort ? (zval >= zbuf[zx]) : (zval < zbuf[zx]);

    // Row beats land in the queue as they come back, in order. Neither pointer is reset per
    // sprite: a sprite issues exactly as many reads as it draws rows, so the two stay in step,
    // and a sprite cannot start drawing until the rows it asked for have arrived.
    always_ff @(posedge clk) begin
        if (reset) qrow_w <= 6'd0;
        else if (rom_valid) begin
            qrow[qrow_w[4:0]] <= rom_data;
            qrow_w <= qrow_w + 6'd1;
        end
    end

    // Pixel from the fetched row. 4bpp: one 64-bit beat is the whole 16-pixel row, nibbles in
    // MAME's order (hng64.cpp:1735). 8bpp: two beats, bytes in the same order.
    wire [3:0]  sx  = cursrcx[19:16];   // the step is already negated when flipped
    wire [63:0] rw  = (!four_bpp && sx[3]) ? row1 : row0;
    logic [7:0] sprite_pix;
    always_comb begin
        if (four_bpp) begin
            case (sx)
                4'd0:  sprite_pix = {4'd0, rw[7:4]};
                4'd1:  sprite_pix = {4'd0, rw[3:0]};
                4'd2:  sprite_pix = {4'd0, rw[39:36]};
                4'd3:  sprite_pix = {4'd0, rw[35:32]};
                4'd4:  sprite_pix = {4'd0, rw[15:12]};
                4'd5:  sprite_pix = {4'd0, rw[11:8]};
                4'd6:  sprite_pix = {4'd0, rw[47:44]};
                4'd7:  sprite_pix = {4'd0, rw[43:40]};
                4'd8:  sprite_pix = {4'd0, rw[23:20]};
                4'd9:  sprite_pix = {4'd0, rw[19:16]};
                4'd10: sprite_pix = {4'd0, rw[55:52]};
                4'd11: sprite_pix = {4'd0, rw[51:48]};
                4'd12: sprite_pix = {4'd0, rw[31:28]};
                4'd13: sprite_pix = {4'd0, rw[27:24]};
                4'd14: sprite_pix = {4'd0, rw[63:60]};
                default: sprite_pix = {4'd0, rw[59:56]};
            endcase
        end else begin
            case (sx[2:0])
                3'd0: sprite_pix = rw[7:0];
                3'd1: sprite_pix = rw[39:32];
                3'd2: sprite_pix = rw[15:8];
                3'd3: sprite_pix = rw[47:40];
                3'd4: sprite_pix = rw[23:16];
                3'd5: sprite_pix = rw[55:48];
                3'd6: sprite_pix = rw[31:24];
                default: sprite_pix = rw[63:56];
            endcase
        end
    end

    // mosaic holds the last fetched pixel; checkerboard drops every other pixel of every other line
    wire [7:0] mos_pix = (mosaic == 4'd0 || mos_x == 4'd0) ? sprite_pix : held;
    wire       drop    = checkerbd && ((dstx[0] && !line[0]) || (!dstx[0] && line[0]));
    wire [7:0] out_pix = drop ? 8'd0 : mos_pix;

    always_ff @(posedge clk) begin
        if (reset) begin
            px_we  <= 1'b0;
            ram_rd <= 1'b0;
            rom_rd <= 1'b0;
            st     <= P_IDLE;
            ncand  <= 9'd0;
            zclr   <= 10'd512;
        end else if (rom_rd && !rom_ready) begin
            px_we  <= 1'b0;                 // the port has not taken the row read yet
            ram_rd <= 1'b0;
        end else begin
            px_we  <= 1'b0;
            ram_rd <= 1'b0;
            rom_rd <= 1'b0;
            case (st)
                P_IDLE: begin
                    if (frame_start) begin
                        sp       <= 11'd0;
                        ncand    <= 9'd0;
                        ram_addr <= 14'd0;
                        ram_rd   <= 1'b1;
                        st       <= P_W0;
                    end else if (line_start) begin
                        zclr <= 10'd0;
                        st   <= L_CLEAR;
                    end
                end

                P_W0: begin w0 <= ram_data; ram_addr <= {sp, 3'd1}; ram_rd <= 1'b1; st <= P_W1; end
                P_W1: begin w1 <= ram_data; ram_addr <= {sp, 3'd2}; ram_rd <= 1'b1; st <= P_W2; end
                P_W2: begin w2 <= ram_data; ram_addr <= {sp, 3'd4}; ram_rd <= 1'b1; st <= P_W4; end
                P_W4: begin
                    w4     <= ram_data;
                    acc    <= 32'd0;
                    height <= 11'd0;
                    st     <= P_HEIGHT;
                end

                // destination height: step the source until it covers the chained tiles
                P_HEIGHT: begin
                    if (zoomx == 16'd0 || zoomy == 16'd0 || (zsort && zval == 11'd0)) begin
                        height <= 11'd0;
                        st     <= P_STORE;
                    end else if (acc < (({28'd0, chainy} + 32'd1) << 20)) begin
                        acc    <= acc + ({16'd0, zoomy} << zoom_shift);
                        height <= height + 11'd1;
                    end else begin
                        st <= P_STORE;
                    end
                end

                P_STORE: begin
                    if (height != 11'd0 && ncand != MAXCAND[8:0]
                        && raw_y < 12'sd448 && (raw_y + $signed({1'b0, height})) > 12'sd0) begin
                        cand_idx[ncand] <= sp;
                        cand_y[ncand]   <= raw_y;
                        cand_h[ncand]   <= height;
                        ncand           <= ncand + 9'd1;
                    end
                    if (sp == 11'd1535) begin
                        st <= P_IDLE;
                    end else begin
                        sp       <= sp + 11'd1;
                        ram_addr <= {sp + 11'd1, 3'd0};
                        ram_rd   <= 1'b1;
                        st       <= P_W0;
                    end
                end

                // ------------------------------------------------------ per line
                L_CLEAR: begin
                    zbuf[zclr[8:0]] <= zsort ? 11'd0 : 11'h7ff;
                    if (zclr == 10'd511) begin
                        ci <= 9'd0;
                        st <= L_PICK;
                    end else begin
                        zclr <= zclr + 10'd1;
                    end
                end

                L_PICK: begin
                    if (ci >= ncand) begin
                        st <= P_IDLE;
                    end else if (cand_y[ci] <= $signed({3'b0, line})
                              && $signed({3'b0, line}) < cand_y[ci] + $signed({1'b0, cand_h[ci]})) begin
                        cur      <= cand_idx[ci];
                        rely     <= {2'b0, line} - cand_y[ci][10:0];
                        ram_addr <= {cand_idx[ci], 3'd0};
                        ram_rd   <= 1'b1;
                        st       <= L_W0;
                    end else begin
                        ci <= ci + 9'd1;
                    end
                end

                L_W0: begin w0 <= ram_data; ram_addr <= {cur, 3'd1}; ram_rd <= 1'b1; st <= L_W1; end
                L_W1: begin w1 <= ram_data; ram_addr <= {cur, 3'd2}; ram_rd <= 1'b1; st <= L_W2; end
                L_W2: begin w2 <= ram_data; ram_addr <= {cur, 3'd4}; ram_rd <= 1'b1; st <= L_W4; end
                L_W4: begin
                    w4      <= ram_data;
                    dx      <= {16'd0, zoomx} << zoom_shift;
                    dy      <= {16'd0, zoomy} << zoom_shift;
                    mul_acc <= 32'd0;
                    mul_add <= {16'd0, zoomy} << zoom_shift;
                    mul_i   <= 5'd0;
                    // mosaic keeps the first line of each group (hng64_sprite.ipp:349)
                    mrely   <= (ram_data[31:28] == 4'd0) ? rely
                                                         : (rely - (rely % ({7'd0, ram_data[31:28]} + 11'd1)));
                    st      <= L_MULY;
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
                        xpos     <= raw_x;
                        xdrw     <= 4'd0;
                        srcx     <= 32'd0;
                        mos_x    <= 4'd0;
                        st       <= L_MULO;
                    end else begin
                        if (mrely[mul_i]) mul_acc <= mul_acc + mul_add;
                        mul_add <= mul_add << 1;
                        mul_i   <= mul_i + 5'd1;
                    end
                end

                // base_ofs = (yflip ? chainy - ytile : ytile) * (chainx + 1)
                L_MULO: begin
                    if (omul_i == 4'd4) begin
                        base_ofs <= omul_acc;
                        st       <= F_TILE;
                    end else begin
                        if (yflip ? ((chainy - ytile) >> omul_i) & 1 : (ytile >> omul_i) & 1)
                            omul_acc <= omul_acc + omul_add;
                        omul_add <= omul_add << 1;
                        omul_i   <= omul_i + 4'd1;
                    end
                end

                // ---- fetch loop: the whole chain, without waiting for any of it -------------
                F_TILE: begin
                    tile_ofs <= base_ofs + (xflip ? ({4'd0, chainx} - {4'd0, xdrw}) : {4'd0, xdrw});
                    ram_addr <= chaini ? ({cur, 3'd4} + {base_ofs + (xflip ? ({4'd0, chainx} - {4'd0, xdrw})
                                                                           : {4'd0, xdrw}), 3'd0})
                                       : {cur, 3'd4};
                    ram_rd   <= 1'b1;
                    st       <= F_TILE_W;
                end
                F_TILE_W: begin
                    // without chaining the tile number walks with the offset instead
                    // 8bpp halves the code BEFORE the chain offset is added
                    // (hng64_sprite.ipp:219-235), not after
                    tileno   <= (four_bpp ? ram_data[18:0] : {1'b0, ram_data[18:1]})
                              + (chaini ? 19'd0 : {11'd0, tile_ofs});
                    ram_addr <= chaini ? ({cur, 3'd3} + {tile_ofs, 3'd0}) : {cur, 3'd3};
                    ram_rd   <= 1'b1;
                    st       <= F_PAL;
                end
                F_PAL: begin
                    qcol[qcol_w[3:0]] <= four_bpp ? {4'd0, ram_data[23:16], 4'd0}
                                                  : {4'd0, ram_data[19:16], 8'd0};
                    qcol_w <= qcol_w + 5'd1;
                    wi     <= 1'b0;
                    st     <= F_ISSUE;
                end
                F_ISSUE: begin
                    rom_addr <= {word_addr[25:3], 3'b000};
                    rom_rd   <= 1'b1;
                    if (four_bpp || wi) begin
                        if (xdrw == chainx) begin
                            xdrw <= 4'd0;
                            st   <= L_POP;
                        end else begin
                            xdrw <= xdrw + 4'd1;
                            st   <= F_TILE;
                        end
                    end else begin
                        wi <= 1'b1;
                    end
                end

                // ---- draw loop: take one tile's colour and rows off the queues --------------
                L_POP: if (qcol_n != 5'd0 && qrow_n >= rows_per_tile) begin
                    colour   <= qcol[qcol_r[3:0]];
                    row0     <= qrow[qrow_r[4:0]];
                    row1     <= qrow[(qrow_r + 6'd1) & 6'd31];
                    qcol_r   <= qcol_r + 5'd1;
                    qrow_r   <= qrow_r + rows_per_tile;
                    dstwidth <= 10'd0;
                    curx     <= 10'd0;
                    mos_x    <= 4'd0;
                    if (xflip) begin
                        st <= L_WIDTH;
                    end else begin
                        cursrcx <= 32'd0;
                        dxs     <= $signed(dx);
                        st      <= L_EMIT;
                    end
                end

                // dstwidth: destination pixels this tile covers (hng64_sprite.ipp:390)
                L_WIDTH: begin
                    if (srcx < 32'h0010_0000) begin
                        srcx     <= srcx + dx;
                        dstwidth <= dstwidth + 10'd1;
                    end else begin
                        srcx    <= srcx & 32'h000f_ffff;
                        curx    <= 10'd0;
                        // x-flip starts at the tile's last source pixel and steps back
                        // (hng64_sprite.ipp:180): cursrcx = (dstwidth - 1) * dx, dx negated
                        mul_acc <= 32'd0;
                        mul_add <= dx;
                        mul_i   <= 5'd0;
                        st      <= xflip ? L_MULX : L_EMIT;
                        if (!xflip) begin
                            cursrcx <= 32'd0;
                            dxs     <= $signed(dx);
                        end
                    end
                end

                L_MULX: begin
                    if (mul_i == 5'd10) begin
                        cursrcx <= mul_acc;
                        dxs     <= -$signed(dx);
                        st      <= L_EMIT;
                    end else begin
                        if ((dstwidth - 10'd1) >> mul_i & 1'b1) mul_acc <= mul_acc + mul_add;
                        mul_add <= mul_add << 1;
                        mul_i   <= mul_i + 5'd1;
                    end
                end

                L_EMIT: begin
                    if (tile_done) begin
                        if (!xflip) srcx <= srcx & 32'h000f_ffff;
                        if (xdrw == chainx) begin
                            ci <= ci + 9'd1;
                            st <= L_PICK;
                        end else begin
                            xdrw <= xdrw + 4'd1;
                            xpos <= xpos + $signed({2'b0, tile_w});
                            st   <= L_POP;
                        end
                    end else begin
                        curx    <= curx + 10'd1;
                        cursrcx <= cursrcx + dxs;
                        if (!xflip) srcx <= srcx + dx;
                        if (mosaic == 4'd0 || mos_x == 4'd0) begin
                            held  <= sprite_pix;
                            mos_x <= mosaic;
                        end else begin
                            mos_x <= mos_x - 4'd1;
                        end
                        if (dstx >= 12'sd0 && dstx < 12'sd512 && out_pix != 8'd0 && ztest) begin
                            px_we    <= 1'b1;
                            px_x     <= zx;
                            px_pix   <= colour | {blend, group, 4'd0, out_pix};
                            zbuf[zx] <= zval;
                        end
                    end
                end

                default: st <= P_IDLE;
            endcase
        end
    end

endmodule
