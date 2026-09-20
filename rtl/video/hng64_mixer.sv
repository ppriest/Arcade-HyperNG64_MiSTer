// SPDX-License-Identifier: GPL-3.0-or-later
//
// Line mixer: the four tilemap layers and the sprite layer to RGB, as MAME's screen_update does
// (hng64_v.cpp:743-940, transcribed in scripts/render_model.py).
//
// MAME walks priority 0x1f down to 0x00; at each step the layers with that priority draw, and
// every fourth step one sprite group draws. So a sprite group is not simply above or below the
// tilemaps: it sits between two priorities, and that matters because a layer or a sprite can be
// additive or half-alpha, and then what is underneath it shows through.
//
// A pixel therefore has up to five contributors - four layer indices and one sprite value, the
// sprite being whatever won its z-buffer. They are ranked by the same key MAME's walk implies,
// then composited in that order. Five palette lookups happen at once, so the palette is three
// dual-port M10K copies.
//
// No multiplies or divides (WORKFLOW 14): every blend is a saturating add, or a halving add for
// alpha at MAME's fixed level of 0x80.

module hng64_mixer (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,              // one cycle, before the line is mixed
    output logic        busy,

    output logic  [8:0] lb_x,               // line-buffer read address; the word arrives NEXT cycle
    input  logic [15:0] tm_pix [0:3],       // palette index, 0 transparent
    input  logic [15:0] spr_pix,            // index | group << 12 | blend << 15

    input  logic [15:0] tileregs [0:3],     // enable, priority, fade select
    input  logic [31:0] tcram [0:23],
    input  logic [23:0] bg_rgb,             // palette entry 0, or black: see fbcontrol bit 0

    output logic [11:0] pal_a [0:4],        // four layers then the sprite; words back next cycle
    input  logic [31:0] pal_d [0:4],

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [23:0] px_rgb              // r, g, b
);

    localparam logic [1:0] M_COPY = 2'd0, M_ADD = 2'd1, M_ALPHA = 2'd2;

    // ---- palette arithmetic ----------------------------------------------------------------
    function automatic [7:0] addsat(input logic [7:0] a, input logic [7:0] b);
        logic [8:0] s;
        s = {1'b0, a} + {1'b0, b};
        addsat = s[8] ? 8'hFF : s[7:0];
    endfunction

    function automatic [7:0] subsat(input logic [7:0] a, input logic [7:0] b);
        logic [8:0] s;
        s = {1'b0, a} - {1'b0, b};
        subsat = s[8] ? 8'h00 : s[7:0];
    endfunction

    // tcram 0x24 holds eight two-bit modes and 0x28.. the eight modifiers: the palette region in
    // bits 27:24, then b, g, r in 23:16, 15:8, 7:0. Mode 2 adds, 3 subtracts, applied in order.
    function automatic [23:0] modify(input logic [23:0] rgb, input logic [11:0] idx);
        logic [7:0]  r, g, b;
        logic [31:0] m;
        logic [1:0]  mode;
        {r, g, b} = rgb;
        for (int i = 0; i < 8; i++) begin
            m    = tcram[10 + i];
            mode = (m[27:24] == idx[11:8]) ? tcram[9][2 * i +: 2] : 2'd0;
            if (mode == 2'd2) begin
                r = addsat(r, m[7:0]);
                g = addsat(g, m[15:8]);
                b = addsat(b, m[23:16]);
            end else if (mode == 2'd3) begin
                r = subsat(r, m[7:0]);
                g = subsat(g, m[15:8]);
                b = subsat(b, m[23:16]);
            end
        end
        modify = {r, g, b};
    endfunction

    // tcram 0x14 holds the six fade modes, 0x18 and 0x1c the two fade values. Mode 1 adds,
    // 3 subtracts (hng64_v.cpp:1209). sel0 picks fade0, as tileregs bit 5 does.
    function automatic [23:0] fade(input logic [23:0] rgb, input logic sel0);
        logic [7:0]  r, g, b;
        logic [31:0] val;
        logic [1:0]  mr, mg, mb;
        {r, g, b} = rgb;
        val = sel0 ? tcram[6] : tcram[7];
        mr  = sel0 ? tcram[5][11:10] : tcram[5][5:4];
        mg  = sel0 ? tcram[5][9:8]   : tcram[5][3:2];
        mb  = sel0 ? tcram[5][7:6]   : tcram[5][1:0];
        if (mr == 2'd1) r = addsat(r, val[23:16]);
        else if (mr == 2'd3) r = subsat(r, val[23:16]);
        if (mg == 2'd1) g = addsat(g, val[15:8]);
        else if (mg == 2'd3) g = subsat(g, val[15:8]);
        if (mb == 2'd1) b = addsat(b, val[7:0]);
        else if (mb == 2'd3) b = subsat(b, val[7:0]);
        fade = {r, g, b};
    endfunction

    // alpha_blend_r32 at MAME's fixed level of 0x80 is (s + d) >> 1 per channel
    function automatic [7:0] halve(input logic [7:0] a, input logic [7:0] b);
        logic [8:0] t;
        t = {1'b0, a} + {1'b0, b};
        halve = t[8:1];
    endfunction

    function automatic [23:0] blend(input logic [23:0] d, input logic [23:0] s,
                                    input logic [1:0] mode);
        case (mode)
            M_ADD:   blend = {addsat(d[23:16], s[23:16]), addsat(d[15:8], s[15:8]),
                              addsat(d[7:0], s[7:0])};
            M_ALPHA: blend = {halve(d[23:16], s[23:16]), halve(d[15:8], s[15:8]),
                              halve(d[7:0], s[7:0])};
            default: blend = s;
        endcase
    endfunction

    // ---- stage 1: the five contributors, their rank and their palette address ---------------
    // Rank is MAME's walk: priority counts down, layers before the sprite group at the same
    // step, layers among themselves in index order (hng64_v.cpp:838-846).
    logic [11:0] idx_c [0:4];
    logic        val_c [0:4];
    logic  [7:0] key_c [0:4];
    logic  [1:0] mode_c [0:4];
    logic        fen_c [0:4], fsel_c [0:4];

    wire [4:0] spr_inv = 5'h1f - {spr_pix[14:12], 2'b00};
    wire       spr_alpha = tcram[19][16];       // tcram 0x4c bit 16: alpha rather than additive

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            val_c[i]  = tileregs[i][6] && tm_pix[i] != 16'd0;
            idx_c[i]  = tm_pix[i][11:0];
            key_c[i]  = {5'h1f - tileregs[i][4:0], 1'b0, i[1:0]};
            mode_c[i] = tcram[3][tileregs[i][5] ? 2 : 26] ? M_ADD : M_COPY;
            fen_c[i]  = tileregs[i][7];
            fsel_c[i] = tileregs[i][5];
        end
        val_c[4]  = spr_pix[11:0] != 12'd0;
        idx_c[4]  = spr_pix[11:0];
        key_c[4]  = {spr_inv, 1'b1, 2'b00};
        mode_c[4] = !spr_pix[15] ? M_COPY : (spr_alpha ? M_ALPHA : M_ADD);
        fen_c[4]  = 1'b0;
        fsel_c[4] = 1'b0;
    end

    always_comb for (int i = 0; i < 5; i++) pal_a[i] = idx_c[i];

    // ---- stage 2: palette words are back; rank, then composite in that order ----------------
    logic        v1 [0:4];
    logic  [7:0] k1 [0:4];
    logic  [1:0] m1 [0:4];
    logic [11:0] i1 [0:4];
    logic        fe1 [0:4], fs1 [0:4];
    logic  [8:0] x1;
    logic        val1;

    logic [23:0] src [0:4];
    always_comb
        for (int i = 0; i < 5; i++) begin
            src[i] = modify(pal_d[i][23:0], i1[i]);
            if (fe1[i]) src[i] = fade(src[i], fs1[i]);
        end

    logic [23:0] mixed;
    always_comb begin
        logic [4:0] used;
        logic [2:0] pick;
        logic [7:0] best;
        mixed = bg_rgb;
        used  = 5'd0;
        for (int step = 0; step < 5; step++) begin
            pick = 3'd5;
            best = 8'hff;
            for (int i = 0; i < 5; i++)
                if (v1[i] && !used[i] && k1[i] <= best) begin
                    best = k1[i];
                    pick = i[2:0];
                end
            if (pick != 3'd5) begin
                used[pick] = 1'b1;
                mixed = blend(mixed, src[pick], m1[pick]);
            end
        end
    end

    // ---- the line ---------------------------------------------------------------------------
    // Three stages, because both RAMs answer a cycle after their address: address the line
    // buffers, rank the words that come back and address the palette, composite what the palette
    // returns. x0 carries the address the words belong to, so a pixel is labelled with the x that
    // produced it rather than the x being fetched.
    logic [9:0] x;
    logic       running, val0;
    logic [8:0] x0;

    assign busy = running || val0 || val1;
    assign lb_x = x[8:0];

    always_ff @(posedge clk) begin
        px_we <= 1'b0;
        if (reset) begin
            running <= 1'b0;
            val0    <= 1'b0;
            val1    <= 1'b0;
            x       <= 10'd0;
        end else begin
            if (val1) begin
                px_we  <= 1'b1;
                px_x   <= x1;
                px_rgb <= mixed;
            end
            val1 <= 1'b0;

            // stage 2: the line-buffer words are back, so rank them and address the palette
            if (val0) begin
                val1 <= 1'b1;
                x1   <= x0;
                for (int i = 0; i < 5; i++) begin
                    v1[i]  <= val_c[i];
                    k1[i]  <= key_c[i];
                    m1[i]  <= mode_c[i];
                    i1[i]  <= idx_c[i];
                    fe1[i] <= fen_c[i];
                    fs1[i] <= fsel_c[i];
                end
            end
            val0 <= 1'b0;

            // stage 1: address the line buffers
            if (start) begin
                x       <= 10'd0;
                running <= 1'b1;
            end else if (running) begin
                val0 <= 1'b1;
                x0   <= x[8:0];
                if (x == 10'd511) running <= 1'b0;
                x <= x + 10'd1;
            end
        end
    end

endmodule
