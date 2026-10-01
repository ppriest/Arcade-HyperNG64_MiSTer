// SPDX-License-Identifier: GPL-3.0-or-later
//
// The 3D buffer's line for the mixer: the sixth line engine of hng64_video.
//
// MAME's blit (hng64_v.cpp:868-923, render_3d.py blit_line) stretches the buffer's 512 lines over
// the game's visible ones: screen line y shows buffer row ((y - min_y) * yinc) >> 16, with
// yinc = (512 << 16) / (visible height - 1), and fbscroll moves it in x. Here the row of each
// screen line is a table, rebuilt at every frame start: one restoring divide (a shift and a
// subtract a clock) for yinc, then an accumulator stepping it down the visible lines (WORKFLOW 14:
// no multiplies or divides in 2D video). Lines come in any order (flip screen renders them
// backwards), which is why it is a table and not a running sum.
//
// A pass reads the displayed colour plane's row, 1 KB, as 128 DDR3 reads into this pass's bank of
// the line buffer, while the other engines run; the mixer reads the other bank, the x scroll added
// to its address. A line outside the window, a disabled blit (fbcontrol[0] bit 0) or no finished
// 3D frame yet reads as nothing.
//
// The displayed plane changes only between frame_start and the first pass of the frame (in
// vblank, before any of the frame is read), from `show_*`; hng64_3d waits for `shown_*` to follow
// before it draws into the plane that was on screen.

module hng64_fb3d (
    input  logic        clk,
    input  logic        reset,

    input  logic        frame_start,
    input  logic        line_start,
    input  logic  [8:0] line,
    input  logic        bank,               // the bank this pass writes; the mixer reads ~bank
    output logic        busy,

    input  logic  [9:0] vis_y0,
    input  logic  [9:0] vis_h,
    input  logic        blit_off,           // fbcontrol[0] bit 0
    input  logic [31:0] fbscroll,

    input  logic        show_valid,         // a finished frame is in show_plane
    input  logic        show_plane,
    output logic        shown_valid = 1'b0,
    output logic        shown_plane = 1'b0,
    input  logic [27:0] plane_base [0:1],

    output logic [27:0] d_addr,
    output logic        d_rd,
    input  logic        d_ready,
    input  logic [63:0] d_data,
    input  logic        d_valid,

    input  logic  [8:0] mix_x,              // the mixer's read; the pixel is out the clock after
    output logic [15:0] mix_pix
);

    // ---- the row table: yinc by a restoring divide, then an accumulator ------------------------------
    typedef enum logic [1:0] { T_IDLE, T_DIV, T_FILL } tstate_t;
    tstate_t     ts;
    logic  [9:0] y0, h;
    logic  [9:0] div_d;                     // visible height - 1
    logic [25:0] rem;
    logic [25:0] quo;
    logic  [4:0] step;
    logic  [8:0] fl;                        // the line being filled
    logic [31:0] acc;
    logic        win;                       // frame_start seen, first pass not yet

    logic  [9:0] row_q;                     // {in the window, row} of the line looked up
    logic  [5:0] row_hi;
    wire   [9:0] in_win = {1'b0, fl} - y0;
    wire         t_in = ({1'b0, fl} >= y0) && (in_win < h) && (div_d != 10'd0);

    hng64_bram #(.AW(9), .DW(16)) u_rows (
        .a_clk(clk), .a_addr(fl), .a_be({2{ts == T_FILL}}),
        .a_wdata({6'd0, t_in, acc[24:16]}), .a_rdata(),
        .b_clk(clk), .b_addr(line), .b_rdata({row_hi, row_q}));

    always_ff @(posedge clk) begin
        if (reset) begin
            ts <= T_IDLE;
            win <= 1'b0;
            shown_valid <= 1'b0;
        end else begin
            if (frame_start) win <= 1'b1;
            else if (line_start) win <= 1'b0;
            if (win) begin
                shown_valid <= show_valid;
                shown_plane <= show_plane;
            end
            case (ts)
                T_IDLE: if (frame_start) begin
                    y0    <= vis_y0;
                    h     <= vis_h;
                    div_d <= (vis_h > 10'd1) ? vis_h - 10'd1 : 10'd0;
                    rem   <= 26'd0;
                    quo   <= 26'd0;
                    step  <= 5'd25;
                    ts    <= T_DIV;
                end
                // 2^25 / div_d, one quotient bit a clock from the top: the dividend is a single 1
                T_DIV: begin
                    logic [25:0] r;
                    r = {rem[24:0], step == 5'd25};
                    if (div_d != 10'd0 && r >= {16'd0, div_d}) begin
                        rem <= r - {16'd0, div_d};
                        quo <= {quo[24:0], 1'b1};
                    end else begin
                        rem <= r;
                        quo <= {quo[24:0], 1'b0};
                    end
                    if (step == 5'd0) begin
                        fl  <= 9'd0;
                        acc <= 32'd0;
                        ts  <= T_FILL;
                    end
                    step <= step - 5'd1;
                end
                T_FILL: begin
                    if (t_in) acc <= acc + {6'd0, quo};
                    fl <= fl + 9'd1;
                    if (fl == 9'd511) ts <= T_IDLE;
                end
                default: ts <= T_IDLE;
            endcase
        end
    end

    // ---- a pass: the row into this bank -----------------------------------------------------------------
    typedef enum logic [2:0] { P_IDLE, P_WAIT, P_SETTLE, P_LOOK, P_READ } pstate_t;
    pstate_t    ps;
    logic       wbank;
    logic [7:0] issued, landed;             // 128 each
    logic [8:0] row;
    logic       have [0:1];                 // the bank holds a row

    assign busy   = (ps != P_IDLE) || (ts != T_IDLE);
    assign d_rd   = (ps == P_READ) && !issued[7];
    assign d_addr = plane_base[shown_plane] + {9'd0, row, issued[6:0], 3'd0};

    always_ff @(posedge clk) begin
        if (reset) begin
            ps <= P_IDLE;
            have[0] <= 1'b0;
            have[1] <= 1'b0;
        end else begin
            case (ps)
                // `line` holds for the pass; the table is read with it once it is built
                P_IDLE: if (line_start) begin
                    wbank <= bank;
                    ps    <= P_WAIT;
                end
                P_WAIT:   if (ts == T_IDLE) ps <= P_SETTLE;
                P_SETTLE: ps <= P_LOOK;
                P_LOOK: begin
                    row    <= row_q[8:0];
                    issued <= 8'd0;
                    landed <= 8'd0;
                    if (row_q[9] && shown_valid && !blit_off) begin
                        have[wbank] <= 1'b1;
                        ps <= P_READ;
                    end else begin
                        have[wbank] <= 1'b0;
                        ps <= P_IDLE;
                    end
                end
                P_READ: begin
                    if (d_rd && d_ready) issued <= issued + 8'd1;
                    if (d_valid) landed <= landed + 8'd1;
                    if (landed == 8'd127 && d_valid) ps <= P_IDLE;
                end
                default: ps <= P_IDLE;
            endcase
        end
    end

    // ---- the line buffer: a 64-bit beat a write, one 16-bit pixel a read ----------------------------------
    wire  [8:0] sx = mix_x + {~fbscroll[29], fbscroll[28:21]};    // (x + (fbscroll >> 21) + 256) & 511
    logic [1:0] sel_q;
    logic       have_q;
    logic [63:0] word;

    hng64_bram #(.AW(8), .DW(64)) u_lb (
        .a_clk(clk), .a_addr({wbank, landed[6:0]}), .a_be({8{d_valid && ps == P_READ}}),
        .a_wdata(d_data), .a_rdata(),
        .b_clk(clk), .b_addr({~bank, sx[8:2]}), .b_rdata(word));

    always_ff @(posedge clk) begin
        sel_q  <= sx[1:0];
        have_q <= have[~bank];
    end
    assign mix_pix = have_q ? word[16 * sel_q +: 16] : 16'd0;

endmodule
