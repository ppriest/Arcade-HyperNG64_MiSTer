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
// A pixel therefore has up to six contributors - four layer indices, one sprite value (whatever
// won the sprite z-buffer) and the 3D buffer's pixel, which MAME blits after step 0x10
// (hng64_v.cpp:868). They are ranked by the same key MAME's walk implies, then composited in that
// order.
//
// ONE CONTRIBUTOR A CLOCK. A pixel takes six clocks: its words are ranked once, then each
// contributor in rank order reads the palette and goes down one pipeline - the eight region
// modifiers one to a stage, the 3D's brightness, the fade, then the blend into the pixel's
// accumulator. 512 pixels are about 3,080 clocks of the line's 3,840, beside the engines'
// 1,171-2,363. The first form did all of them in one clock: about 5,200 ALUTs for five, five
// palette copies, and the likely clk2x path that missed timing by 34.8 ns.
//
// The 3D pixel is `llll appp pppp pppp`: m_palette_3d (render_3d.py palette3d) is the modified
// palette entry p | fbcontrol[2] bit 5 << 11, plus l << 2 on each channel (saturating), through
// fade 0; a is MAME's fixed half-alpha.
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
    input  logic [15:0] d3_pix,             // the 3D buffer's pixel, 0 where it draws nothing
    input  logic        d3_palbase,         // fbcontrol[2] bit 5

    input  logic [15:0] tileregs [0:3],     // enable, priority, fade select
    input  logic [31:0] tcram [0:23],
    input  logic [23:0] bg_rgb,             // palette entry 0, or black: see fbcontrol bit 0
    input  logic        screen_dis,         // tcram_w's m_screen_dis: the background only

    output logic [11:0] pal_a,              // one read a clock; the word is back next cycle
    input  logic [31:0] pal_d,

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
    // bits 27:24, then b, g, r in 23:16, 15:8, 7:0. Mode 2 adds, 3 subtracts, applied in order;
    // this is modifier i, of eight.
    function automatic [23:0] modify1(input logic [23:0] rgb, input logic [3:0] region, input int i);
        logic [7:0]  r, g, b;
        logic [31:0] m;
        logic [1:0]  mode;
        {r, g, b} = rgb;
        m    = tcram[10 + i];
        mode = (m[27:24] == region) ? tcram[9][2 * i +: 2] : 2'd0;
        if (mode == 2'd2) begin
            r = addsat(r, m[7:0]);
            g = addsat(g, m[15:8]);
            b = addsat(b, m[23:16]);
        end else if (mode == 2'd3) begin
            r = subsat(r, m[7:0]);
            g = subsat(g, m[15:8]);
            b = subsat(b, m[23:16]);
        end
        modify1 = {r, g, b};
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

    // ---- the six contributors of the words just read, and their rank ---------------------------
    // Rank is MAME's walk: priority counts down, layers before the sprite group at the same
    // step, layers among themselves in index order (hng64_v.cpp:838-846), the 3D after step 0x10's
    // sprite group. The keys are distinct, so the ranks are a permutation; a contributor with
    // nothing to draw ranks after all that do.
    localparam int NC = 6;
    logic [11:0] idx_c [0:NC-1];
    logic        val_c [0:NC-1];
    logic  [8:0] key_c [0:NC-1];            // {nothing to draw, MAME's order}
    logic  [1:0] mode_c [0:NC-1];
    logic        fen_c [0:NC-1], fsel_c [0:NC-1];
    logic  [3:0] br_c [0:NC-1];             // the 3D's brightness
    logic  [2:0] rank_c [0:NC-1];

    wire [4:0] spr_inv = 5'h1f - {spr_pix[14:12], 2'b00};
    wire       spr_alpha = tcram[19][16];       // tcram 0x4c bit 16: alpha rather than additive

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            val_c[i]  = tileregs[i][6] && tm_pix[i] != 16'd0;
            idx_c[i]  = tm_pix[i][11:0];
            key_c[i]  = {!val_c[i], 5'h1f - tileregs[i][4:0], 1'b0, i[1:0]};
            mode_c[i] = tcram[3][tileregs[i][5] ? 2 : 26] ? M_ADD : M_COPY;
            fen_c[i]  = tileregs[i][7];
            fsel_c[i] = tileregs[i][5];
            br_c[i]   = 4'd0;
        end
        val_c[4]  = spr_pix[11:0] != 12'd0;
        idx_c[4]  = spr_pix[11:0];
        key_c[4]  = {!val_c[4], spr_inv, 1'b1, 2'b00};
        mode_c[4] = !spr_pix[15] ? M_COPY : (spr_alpha ? M_ALPHA : M_ADD);
        fen_c[4]  = 1'b0;
        fsel_c[4] = 1'b0;
        br_c[4]   = 4'd0;
        val_c[5]  = d3_pix[10:0] != 11'd0;
        idx_c[5]  = {d3_palbase, d3_pix[10:0]};
        key_c[5]  = {!val_c[5], 5'h0f, 1'b1, 2'b11};
        mode_c[5] = d3_pix[11] ? M_ALPHA : M_COPY;
        fen_c[5]  = 1'b1;
        fsel_c[5] = 1'b1;                   // fade 0
        br_c[5]   = d3_pix[15:12];
        for (int i = 0; i < NC; i++) begin
            rank_c[i] = 3'd0;
            for (int j = 0; j < NC; j++)
                if (j != i && key_c[j] < key_c[i]) rank_c[i] = rank_c[i] + 3'd1;
        end
    end

    // ---- the pixel being issued: its contributors in rank order -------------------------------
    logic        s_val [0:NC-1];
    logic [11:0] s_idx [0:NC-1];
    logic  [1:0] s_mode [0:NC-1];
    logic        s_fen [0:NC-1], s_fsel [0:NC-1];
    logic  [3:0] s_br [0:NC-1];
    logic  [8:0] s_x;

    // Phases: the line buffers are read at phase 4 for the next pixel, their words ranked and
    // taken at the end of phase 5, and the pixel's slots issued at phases 0-5 of the next period.
    // lb_x moves only in the clock of a read and otherwise holds the pixel last read: hng64_video
    // clears the sprite buffer a clock behind lb_x, so it must never point ahead of the read.
    logic [2:0] ph;
    logic       reading;                // pixels are still to be read
    logic       rd_pend;                // read at phase 4, to be taken at phase 5
    logic       have;                   // a pixel is being issued
    logic [8:0] x;                      // the next pixel to read
    logic [8:0] x_last;                 // the pixel last read

    assign lb_x  = (reading && ph == 3'(NC - 2)) ? x : x_last;
    assign pal_a = s_idx[ph];

    // the pipeline's tag, one a clock: which pixel, and what to do with its palette word
    typedef struct packed {
        logic        go;                // a slot was issued
        logic        val;               // the contributor draws
        logic  [1:0] mode;
        logic        fen, fsel;
        logic  [3:0] br;
        logic  [3:0] region;
        logic        first, last;
        logic  [8:0] x;
    } tag_t;

    tag_t t0, t4b, t5;
    tag_t tm [0:7];                     // after modifier i
    logic [23:0] cm [0:7];
    logic [23:0] c4b, c5;               // the colour after each stage
    logic [23:0] c4;
    tag_t        t4;
    assign c4 = cm[7];
    assign t4 = tm[7];
    logic [23:0] acc;

    logic mod_go;
    always_comb begin
        mod_go = 1'b0;
        for (int i = 0; i < 8; i++) mod_go = mod_go || tm[i].go;
    end
    assign busy = reading || rd_pend || have || t0.go || mod_go || t4b.go || t5.go;

    always_ff @(posedge clk) begin
        px_we <= 1'b0;
        if (reset) begin
            reading <= 1'b0;
            rd_pend <= 1'b0;
            have    <= 1'b0;
            ph      <= 3'd0;
            x       <= 9'd0;
            x_last  <= 9'd0;
            t0 <= '0; t4b <= '0; t5 <= '0;
            for (int i = 0; i < 8; i++) tm[i] <= '0;
        end else begin
            // ---- issue --------------------------------------------------------------------
            if (start) begin
                reading <= 1'b1;
                x       <= 9'd0;
                ph      <= 3'(NC - 2);      // read pixel 0 now
            end else if (reading || rd_pend || have) begin
                ph <= (ph == 3'(NC - 1)) ? 3'd0 : ph + 3'd1;
                if (ph == 3'(NC - 2) && reading) begin
                    rd_pend <= 1'b1;
                    x_last  <= x;
                    if (x == 9'd511) reading <= 1'b0;
                    else x <= x + 9'd1;
                end
                if (ph == 3'(NC - 1)) begin
                    have    <= rd_pend;     // the words read at phase 4 become the next pixel
                    rd_pend <= 1'b0;
                    if (rd_pend) begin
                        for (int i = 0; i < NC; i++) begin
                            s_val[rank_c[i]]  <= val_c[i];
                            s_idx[rank_c[i]]  <= idx_c[i];
                            s_mode[rank_c[i]] <= mode_c[i];
                            s_fen[rank_c[i]]  <= fen_c[i];
                            s_fsel[rank_c[i]] <= fsel_c[i];
                            s_br[rank_c[i]]   <= br_c[i];
                        end
                        s_x <= x_last;
                    end
                end
            end

            // the slot issued this clock (its palette word comes back next clock)
            t0.go     <= have;
            t0.val    <= s_val[ph];
            t0.mode   <= s_mode[ph];
            t0.fen    <= s_fen[ph];
            t0.fsel   <= s_fsel[ph];
            t0.br     <= s_br[ph];
            t0.region <= s_idx[ph][11:8];
            t0.first  <= ph == 3'd0;
            t0.last   <= ph == 3'(NC - 1);
            t0.x      <= s_x;

            // ---- the colour: modifiers one to a stage, the brightness, the fade, the blend -------
            // one modifier a stage: two in series missed clk2x by 5.3 ns in the first full fit
            tm[0] <= t0;
            cm[0] <= modify1(pal_d[23:0], t0.region, 0);
            for (int i = 1; i < 8; i++) begin
                tm[i] <= tm[i - 1];
                cm[i] <= modify1(cm[i - 1], tm[i - 1].region, i);
            end
            t4b <= t4;
            c4b <= {addsat(c4[23:16], {2'd0, t4.br, 2'd0}), addsat(c4[15:8], {2'd0, t4.br, 2'd0}),
                    addsat(c4[7:0], {2'd0, t4.br, 2'd0})};
            t5 <= t4b;
            c5 <= t4b.fen ? fade(c4b, t4b.fsel) : c4b;

            if (t5.go) begin
                acc <= t5.val ? blend(t5.first ? bg_rgb : acc, c5, t5.mode)
                              : (t5.first ? bg_rgb : acc);
                if (t5.last) begin
                    px_we  <= 1'b1;
                    px_x   <= t5.x;
                    // screen_update returns after the background fill when the screen is
                    // disabled or tcram 0x24 bit 17 is set ("disable all palette output")
                    px_rgb <= (screen_dis || tcram[9][17]) ? bg_rgb
                            : (t5.val ? blend(t5.first ? bg_rgb : acc, c5, t5.mode) : acc);
                end
            end
        end
    end

endmodule
