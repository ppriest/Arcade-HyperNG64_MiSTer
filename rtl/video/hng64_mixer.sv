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
// contributor in rank order reads the modified palette and goes down one pipeline - the 3D's
// brightness, the fade, then the blend into the pixel's accumulator. 512 pixels are about 3,080 clocks of the line's 3,840, beside the engines'
// 1,171-2,363. The first form did all of them in one clock: about 5,200 ALUTs for five, five
// palette copies, and the likely clk2x path that missed timing by 34.8 ns.
//
// The 3D pixel is `llll appp pppp pppp`: m_palette_3d (render_3d.py palette3d) is the modified
// palette entry p | fbcontrol[2] bit 5 << 11, plus l << 2 on each channel (saturating), through
// fade 0; a is MAME's fixed half-alpha.
//
// THE MODIFIED PALETTE is built at each frame_start, as MAME builds its palette state at
// screen_update: every entry through the eight region modifiers, one modifier a clock with one
// unit, into a RAM the pixel path reads. 4,096 entries at ten clocks, about 41,000 clocks, inside
// the vblank; busy covers it, so the frame's first pass waits. A palette or tcram write during the
// frame shows from the next frame, as in MAME (except at its video-register splits). The
// modifiers were eight pipeline stages on every pixel before (about 750 ALUTs).
//
// No multiplies or divides (WORKFLOW 14): every blend is a saturating add, or a halving add for
// alpha at MAME's fixed level of 0x80.

module hng64_mixer (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,              // one cycle, before the line is mixed
    input  logic        rebuild,            // one cycle at frame_start: rebuild the modified palette
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

    output logic [11:0] pal_a,              // the palette, read by the rebuild; data next cycle
    input  logic [31:0] pal_d,

    output logic        px_we,
    output logic  [8:0] px_x,
    output logic [23:0] px_rgb,             // r, g, b
    output logic        dbg_spr_seen        // a pixel read with a sprite word in it, once a pixel
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

    // One modifier, its word and mode already selected (the rebuild preloads them a step ahead:
    // the eight-way tcram select in front of the add missed clk2x by 1.9 ns)
    function automatic [23:0] modify_r(input logic [23:0] rgb, input logic [3:0] region,
                                       input logic [31:0] m, input logic [1:0] mode_in);
        logic [7:0] r, g, b;
        logic [1:0] mode;
        {r, g, b} = rgb;
        mode = (m[27:24] == region) ? mode_in : 2'd0;
        if (mode == 2'd2) begin
            r = addsat(r, m[7:0]);
            g = addsat(g, m[15:8]);
            b = addsat(b, m[23:16]);
        end else if (mode == 2'd3) begin
            r = subsat(r, m[7:0]);
            g = subsat(g, m[15:8]);
            b = subsat(b, m[23:16]);
        end
        modify_r = {r, g, b};
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

    logic [2:0] ph;                     // the phase of six, below

    // the words read at phase 1, held from the end of phase 2
    logic [15:0] w_tm [0:3];
    logic [15:0] w_spr, w_d3;
    always_ff @(posedge clk)
        if (ph == 3'(NC - 4)) begin
            for (int i = 0; i < 4; i++) w_tm[i] <= tm_pix[i];
            w_spr <= spr_pix;
            w_d3  <= d3_pix;
        end

    wire [4:0] spr_inv = 5'h1f - {w_spr[14:12], 2'b00};
    wire       spr_alpha = tcram[19][16];       // tcram 0x4c bit 16: alpha rather than additive

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            val_c[i]  = tileregs[i][6] && w_tm[i] != 16'd0;
            idx_c[i]  = w_tm[i][11:0];
            key_c[i]  = {!val_c[i], 5'h1f - tileregs[i][4:0], 1'b0, i[1:0]};
            mode_c[i] = tcram[3][tileregs[i][5] ? 2 : 26] ? M_ADD : M_COPY;
            fen_c[i]  = tileregs[i][7];
            fsel_c[i] = tileregs[i][5];
            br_c[i]   = 4'd0;
        end
        val_c[4]  = w_spr[11:0] != 12'd0;
        idx_c[4]  = w_spr[11:0];
        key_c[4]  = {!val_c[4], spr_inv, 1'b1, 2'b00};
        mode_c[4] = !w_spr[15] ? M_COPY : (spr_alpha ? M_ALPHA : M_ADD);
        fen_c[4]  = 1'b0;
        fsel_c[4] = 1'b0;
        br_c[4]   = 4'd0;
        val_c[5]  = w_d3[10:0] != 11'd0;
        idx_c[5]  = {d3_palbase, w_d3[10:0]};
        key_c[5]  = {!val_c[5], 5'h0f, 1'b1, 2'b11};
        mode_c[5] = w_d3[11] ? M_ALPHA : M_COPY;
        fen_c[5]  = 1'b1;
        fsel_c[5] = 1'b1;                   // fade 0
        br_c[5]   = w_d3[15:12];
    end

    // the contributors and their keys, registered at the end of phase 3; ranked from those
    logic        val_k [0:NC-1];
    logic [11:0] idx_k [0:NC-1];
    logic  [1:0] mode_k [0:NC-1];
    logic        fen_k [0:NC-1], fsel_k [0:NC-1];
    logic  [3:0] br_k [0:NC-1];
    logic  [8:0] key_k [0:NC-1];
    always_ff @(posedge clk)
        if (ph == 3'(NC - 3))
            for (int i = 0; i < NC; i++) begin
                val_k[i]  <= val_c[i];
                idx_k[i]  <= idx_c[i];
                mode_k[i] <= mode_c[i];
                fen_k[i]  <= fen_c[i];
                fsel_k[i] <= fsel_c[i];
                br_k[i]   <= br_c[i];
                key_k[i]  <= key_c[i];
            end

    always_comb
        for (int i = 0; i < NC; i++) begin
            rank_c[i] = 3'd0;
            for (int j = 0; j < NC; j++)
                if (j != i && key_k[j] < key_k[i]) rank_c[i] = rank_c[i] + 3'd1;
        end

    // the contributors and their ranks, registered at the end of phase 4
    logic        val_q [0:NC-1];
    logic [11:0] idx_q [0:NC-1];
    logic  [1:0] mode_q [0:NC-1];
    logic        fen_q [0:NC-1], fsel_q [0:NC-1];
    logic  [3:0] br_q [0:NC-1];
    // the ranks as one-hot slots: slot_q[k][i], contributor i goes to slot k. The keys are distinct
    // (their low bits name the contributor), so each slot has one; scattered by a 3-bit rank through
    // the loop's priority it missed clk2x by 0.74 ns into a_idx (a10b85c seed 1).
    logic [NC-1:0] slot_q [0:NC-1];
    always_ff @(posedge clk)
        if (ph == 3'(NC - 2))
            for (int i = 0; i < NC; i++) begin
                val_q[i]  <= val_k[i];
                idx_q[i]  <= idx_k[i];
                mode_q[i] <= mode_k[i];
                fen_q[i]  <= fen_k[i];
                fsel_q[i] <= fsel_k[i];
                br_q[i]   <= br_k[i];
                for (int k = 0; k < NC; k++) slot_q[k][i] <= rank_c[i] == 3'(k);
            end
    logic        sc_val [0:NC-1];
    logic [11:0] sc_idx [0:NC-1];
    logic  [1:0] sc_mode [0:NC-1];
    logic        sc_fen [0:NC-1], sc_fsel [0:NC-1];
    logic  [3:0] sc_br [0:NC-1];
    always_comb
        for (int k = 0; k < NC; k++) begin
            sc_val[k] = 1'b0; sc_idx[k] = '0; sc_mode[k] = '0;
            sc_fen[k] = 1'b0; sc_fsel[k] = 1'b0; sc_br[k] = '0;
            for (int i = 0; i < NC; i++)
                if (slot_q[k][i]) begin
                    sc_val[k]  = sc_val[k]  | val_q[i];
                    sc_idx[k]  = sc_idx[k]  | idx_q[i];
                    sc_mode[k] = sc_mode[k] | mode_q[i];
                    sc_fen[k]  = sc_fen[k]  | fen_q[i];
                    sc_fsel[k] = sc_fsel[k] | fsel_q[i];
                    sc_br[k]   = sc_br[k]   | br_q[i];
                end
        end

    // ---- the pixel being issued: its contributors in rank order -------------------------------
    logic        s_val [0:NC-1];
    logic [11:0] s_idx [0:NC-1];
    logic  [1:0] s_mode [0:NC-1];
    logic        s_fen [0:NC-1], s_fsel [0:NC-1];
    logic  [3:0] s_br [0:NC-1];
    logic  [8:0] s_x;

    // Phases: the line buffers are read at phase 1 for the next pixel, their words registered at
    // the end of phase 2 (w_*), keyed at the end of phase 3 (*_k), ranked at the end of phase 4
    // (*_q), scattered into the slots at the end of phase 5, and the pixel's slots issued at phases 0-5 of the next
    // period. Ranking straight off the RAMs' outputs missed clk2x by 3.8 ns, and rank and scatter
    // in one clock by 3.0 ns.
    // lb_x moves only in the clock of a read and otherwise holds the pixel last read: hng64_video
    // clears the sprite buffer a clock behind lb_x, so it must never point ahead of the read.
    logic       reading;                // pixels are still to be read
    logic       rd_pend;                // read at phase 1, to be taken at phase 5
    assign dbg_spr_seen = ph == 3'(NC - 3) && rd_pend && w_spr[11:0] != 12'd0;
    logic       have;                   // a pixel is being issued
    logic [8:0] x;                      // the next pixel to read
    logic [8:0] x_last;                 // the pixel last read

    // lb_x is a register: x from the clock before the read, held until the next (decoded from ph
    // into every line buffer's address it missed clk2x by 2.1 ns)
    always_ff @(posedge clk)
        if (start) lb_x <= 9'd0;
        else if (reading && ph == 3'(NC - 6)) lb_x <= x;

    // the pipeline's tag, one a clock: which pixel, and what to do with its palette word
    typedef struct packed {
        logic        go;                // a slot was issued
        logic        val;               // the contributor draws
        logic  [1:0] mode;
        logic        fen, fsel;
        logic  [3:0] br;
        logic        first, last;
        logic  [8:0] x;
    } tag_t;

    tag_t t0, t1, t4b, t5;
    logic [23:0] c4b, c5;               // the colour after each stage
    logic [23:0] acc;

    // ---- the modified palette, and its rebuild -------------------------------------------------
    logic [23:0] mpal_d;                // the entry at s_idx[ph], two clocks after
    // s_idx in phase order: a_idx[0] is s_idx[ph]. From ph through s_idx's select into the RAM's
    // address it missed clk2x by 0.95 ns; this shifts a slot each time ph moves on.
    logic [11:0] a_idx [0:NC-1];
    logic        rb_run, rb_we;
    logic [11:0] rb_k, rb_wk;
    logic  [3:0] rb_step;               // 0 read issued, 1 word back, 2-9 modifier 0-7
    logic [23:0] rb_c, rb_wc;
    logic [31:0] rb_m;                  // the modifier the next step applies, and its mode
    logic  [1:0] rb_md;
    logic  [2:0] rb_ni;                 // the one to load next (kept, not added each step: 2.0 ns)

    hng64_bram #(.AW(12), .DW(24), .OUTREG_B(1'b1)) u_mpal (
        .a_clk(clk), .a_addr(rb_wk), .a_be({3{rb_we}}), .a_wdata(rb_wc), .a_rdata(),
        .b_clk(clk), .b_addr(a_idx[0]), .b_rdata(mpal_d));

    assign pal_a = rb_k;

    always_ff @(posedge clk) begin
        rb_we <= 1'b0;
        if (reset) begin
            rb_run <= 1'b0;
        end else if (rebuild) begin
            rb_run  <= 1'b1;
            rb_k    <= 12'd0;
            rb_step <= 4'd0;
            rb_ni   <= 3'd0;
        end else if (rb_run) begin
            rb_step <= rb_step + 4'd1;
            // modifier i is applied at step i + 2 and loaded the step before
            if (rb_step == 4'd0 || (rb_step >= 4'd2 && rb_step <= 4'd8)) begin   // index 7 then wraps to 0
                rb_m  <= tcram[10 + int'(rb_ni)];
                rb_md <= tcram[9][2 * int'(rb_ni) +: 2];
                rb_ni <= rb_ni + 3'd1;
            end
            if (rb_step == 4'd1) rb_c <= pal_d[23:0];
            else if (rb_step >= 4'd2) rb_c <= modify_r(rb_c, rb_k[11:8], rb_m, rb_md);
            if (rb_step == 4'd9) begin
                rb_we   <= 1'b1;
                rb_wk   <= rb_k;
                rb_wc   <= modify_r(rb_c, rb_k[11:8], rb_m, rb_md);
                rb_step <= 4'd0;
                if (rb_k == 12'hFFF) rb_run <= 1'b0;
                rb_k <= rb_k + 12'd1;
            end
        end
    end

    assign busy = rb_run || rb_we || reading || rd_pend || have || t0.go || t1.go || t4b.go || t5.go;

    always_ff @(posedge clk) begin
        px_we <= 1'b0;
        if (reset) begin
            reading <= 1'b0;
            rd_pend <= 1'b0;
            have    <= 1'b0;
            ph      <= 3'd0;
            x       <= 9'd0;
            x_last  <= 9'd0;
            t0 <= '0; t1 <= '0; t4b <= '0; t5 <= '0;
        end else begin
            // ---- issue --------------------------------------------------------------------
            if (start) begin
                reading <= 1'b1;
                x       <= 9'd0;
                ph      <= 3'(NC - 5);      // read pixel 0 now
            end else if (reading || rd_pend || have) begin
                ph <= (ph == 3'(NC - 1)) ? 3'd0 : ph + 3'd1;
                for (int k = 0; k < NC - 1; k++) a_idx[k] <= a_idx[k + 1];
                if (ph == 3'(NC - 5) && reading) begin
                    rd_pend <= 1'b1;
                    x_last  <= x;
                    if (x == 9'd511) reading <= 1'b0;
                    else x <= x + 9'd1;
                end
                if (ph == 3'(NC - 1)) begin
                    have    <= rd_pend;     // the words read at phase 1 become the next pixel
                    rd_pend <= 1'b0;
                    for (int k = 0; k < NC; k++) a_idx[k] <= s_idx[k];
                    if (rd_pend) begin
                        for (int k = 0; k < NC; k++) begin
                            s_val[k]  <= sc_val[k];
                            s_idx[k]  <= sc_idx[k];
                            a_idx[k]  <= sc_idx[k];
                            s_mode[k] <= sc_mode[k];
                            s_fen[k]  <= sc_fen[k];
                            s_fsel[k] <= sc_fsel[k];
                            s_br[k]   <= sc_br[k];
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
            t0.first  <= ph == 3'd0;
            t0.last   <= ph == 3'(NC - 1);
            t0.x      <= s_x;

            // ---- the colour: the modified entry, the brightness, the fade, the blend --------------
            // the palette word is registered at the RAM (u_mpal OUTREG_B): it comes back two clocks
            // after its slot, so the slot waits a clock in t1 (from the RAM straight into the
            // brightness add it missed clk2x by 0.8 ns)
            t1  <= t0;
            t4b <= t1;
            c4b <= {addsat(mpal_d[23:16], {2'd0, t1.br, 2'd0}), addsat(mpal_d[15:8], {2'd0, t1.br, 2'd0}),
                    addsat(mpal_d[7:0], {2'd0, t1.br, 2'd0})};
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
