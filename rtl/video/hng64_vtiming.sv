// SPDX-License-Identifier: GPL-3.0-or-later
//
// Display timing, the order hng64_video.sv renders lines in, and the scanline interrupts.
//
// MAME's screen (hng64.h:218-229): a 25 MHz pixel clock, 768 x 528 total, 512 x 448 visible,
// 61.65 Hz. At clk2x, 125 MHz, a pixel is exactly five clocks. MAME gives no sync positions; the
// ones here are ours (HACKS.md). The board draws 264 lines a field, interlaced, which MAME runs
// as 528 progressive lines; this does the same.
//
// LINES ARE RENDERED TWO AHEAD. A pass of hng64_video with `line` = L renders line L into its
// line buffers while the mixer emits line L-1 at the block's own pace, not the pixel clock's.
// Those pixels go into an output line buffer, and the display reads the previous line's copy of
// it. So the pass started as display line d begins has L = d + 2: its output, line d + 1, is
// ready before d + 1 is shown. The passes for lines 0 and 1 run in the last two blanked lines,
// and a last pass at d = 446 re-renders 447 to flush it out, as sim/video_tb does.
//
// FLIP SCREEN turns the picture 180 degrees within the game's window, all layers at once: the pass
// for display line d renders the window's mirror line (447 - d for a 448-line window at 0), and the
// output buffer is read mirrored in x. The schedule is
// otherwise unchanged. `flip` is taken once a frame, in vblank, so no frame is drawn half each
// way. MAME has no flip for this board; the check is the unflipped frame rotated (sim/sys_tb).
//
// VBLANK. From line 448, once no pass is running or waiting, the sprite list is copied into the
// engine's copy (hng64_vbus.sv), and when
// that is done the engine's frame starts (`frame_start`), 78 blanked lines before line 0 is due.
//
// INTERRUPTS, as MAME's scanline timer raises them (hng64_irq, hng64.cpp:2128): it runs on every
// even line of the 528, as line/2 of 264. Vblank at 224 (line 448), network at 240 (line 480),
// and raster at m_raster_irq_pos[0] + 8 if below 224 - an unsigned sum, so the reset value
// 0xffffffff raises it at 7 until the game sets a position. Each is two clk2x clocks long, one
// clk1x clock, which is what hng64_io samples.

module hng64_vtiming (
    input  logic        clk,            // clk2x
    input  logic        reset,
    input  logic        flip,
    input  logic  [9:0] vis_x0,         // the game's window (hng64_vbus.sv), taken in vblank
    input  logic  [9:0] vis_y0,
    input  logic  [9:0] vis_w,
    input  logic  [9:0] vis_h,

    output logic        ce_pix,
    output logic        hsync,
    output logic        vsync,
    output logic        hblank,
    output logic        vblank,
    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,

    // the render passes
    output logic        line_start,
    output logic  [8:0] line,
    output logic        frame_start,
    input  logic        busy,
    output logic        snapshot,
    input  logic        snapshot_done,
    input  logic        px_we,
    input  logic  [8:0] px_x,
    input  logic [23:0] px_rgb,

    // interrupts, and what the CPU polls
    input  logic [31:0] raster_pos,
    output logic        vblank_irq,
    output logic        raster_irq,
    output logic        net_irq,
    output logic        vblank_level,

    output logic        dbg_late,      // sticky: a pass could not start when its line began
    output logic  [2:0] dbg_sched      // {a pass late this clock, frame_pend, pend}
);

    logic late_now;
    // the video block's busy, registered (from its engines into line_start it missed clk2x by
    // 1.5 ns). It rises a clock after the block sees a start, so the registered copy is current two
    // clocks after one: ls_d and fs_d cover the clock between.
    logic busy_q = 1'b0, ls_d = 1'b0, fs_d = 1'b0;
    always_ff @(posedge clk) begin
        busy_q <= busy;
        ls_d   <= line_start;
        fs_d   <= frame_start;
    end

    localparam logic [9:0] HTOTAL = 10'd768, HVIS = 10'd512, VTOTAL = 10'd528, VVIS = 10'd448;
    // ours, MAME gives none: centred in the blanking, 96-pixel porches. crt_adjust.sv anchors
    // its read at the HSync rise, so the front porch is the room CRT Adjust has to move the
    // picture right or widen it (sim/crt_tb).
    localparam logic [9:0] HS_START = 10'd608, HS_END = 10'd672;
    localparam logic [9:0] VS_START = 10'd452, VS_END = 10'd456;

    logic [2:0] div;
    logic [9:0] h;
    logic [9:0] v;

    // the window, taken once a frame in vblank as flip is
    logic [9:0] wx0 = 10'd0, wy0 = 10'd0, ww = 10'd512, wh = 10'd448;
    logic [9:0] wx1 = 10'd512, wy1 = 10'd448;   // wx0 + ww, wy0 + wh (10 bits, as the sum was), latched with them

    // ---- the pixel clock and the counters ------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (reset) begin
            div <= 3'd0;
            h <= 10'd0;
            v <= 10'd0;
        end else begin
            div <= (div == 3'd4) ? 3'd0 : div + 3'd1;
            if (div == 3'd4) begin
                if (h == HTOTAL - 10'd1) begin
                    h <= 10'd0;
                    v <= (v == VTOTAL - 10'd1) ? 10'd0 : v + 10'd1;
                end else begin
                    h <= h + 10'd1;
                end
            end
        end
    end

    // a line begins on the clock the counters show h = 0 with the pixel strobe about to fire
    // registered a clock ahead: div == 3 on the last pixel is the clock before div == 4 on it
    // (decoded in place it missed clk2x by 1.1 ns into the window registers)
    logic line_begin = 1'b0;
    always_ff @(posedge clk) line_begin <= !reset && (div == 3'd3) && (h == HTOTAL - 10'd1);
    wire [9:0] v_next = (v == VTOTAL - 10'd1) ? 10'd0 : v + 10'd1;

    // ---- render passes -----------------------------------------------------------------------------
    // the pass started as line v_next begins: its L, and whether there is one
    // registered: v holds for the whole line before line_begin, so they are current when used
    // (from v through the wrap and compare into pend missed clk2x by 2.6 ns)
    logic [9:0] pass_l;
    logic       pass_due;
    always_ff @(posedge clk) begin
        logic [9:0] l;
        l = v_next + 10'd2;
        if (l >= VTOTAL) l = l - VTOTAL;
        pass_l   <= l;
        pass_due <= (l <= VVIS);                        // 0..447, and 448 for the flush
    end

    logic       pend;                                   // a pass is due and has not started
    logic [8:0] pend_line;
    logic       pend_flush;
    logic [9:0] out_line;                               // what the running pass emits
    logic       out_valid;
    logic       frame_pend;                             // the engine's frame, waiting for idle
    // The list is copied once no pass is running or waiting (the flush pass of 447 goes first), and
    // no pass starts during the copy: a pass reading the engine's copy as it is rewritten saw a
    // candidate's zoom go to 0 under it (fatfurwa, hardware).
    logic       snap_pend, snap_run;
    logic       flip_f = 1'b0;                          // flip, for the frame being drawn

    always_ff @(posedge clk) if (line_begin && v_next == 10'd450) begin
        flip_f <= flip;
        wx0 <= vis_x0;
        wy0 <= vis_y0;
        ww <= vis_w;
        wh <= vis_h;
        wx1 <= vis_x0 + vis_w;
        wy1 <= vis_y0 + vis_h;
    end
    // flip turns the game's window, not the raster: line y of it shows y0 + y1 - y (fatfurwa's
    // lines 16-447 onto themselves); lines outside the window are not shown, so any line will do
    function automatic logic [8:0] flip_line(input logic [8:0] l);
        logic [9:0] m;
        m = wy0 + wy0 + wh - 10'd1 - {1'b0, l};
        flip_line = ({1'b0, l} >= wy0 && {1'b0, l} < wy0 + wh) ? m[8:0] : l;
    endfunction
    wire in_x = (h >= wx0) && (h < wx1) && (h < HVIS);
    wire in_y = (v >= wy0) && (v < wy1) && (v < VVIS);
    // registered for the output below: h and v change entering div 0 and are used at div 1, so a
    // clock late they are still this pixel's (from v through the compares into the 24 colour
    // registers it missed clk2x by 0.8 ns)
    logic in_x_q = 1'b0, in_y_q = 1'b0;
    always_ff @(posedge clk) begin
        in_x_q <= in_x;
        in_y_q <= in_y;
    end

    always_ff @(posedge clk) begin
        line_start <= 1'b0;
        frame_start <= 1'b0;
        snapshot <= 1'b0;
        late_now <= 1'b0;
        if (reset) begin
            pend <= 1'b0;
            dbg_late <= 1'b0;
            out_valid <= 1'b0;
            frame_pend <= 1'b0;
            snap_pend <= 1'b0;
            snap_run <= 1'b0;
        end else begin
            if (line_begin) begin
                // the last pass has not started, or has not finished, when the next is due
                if (pass_due && (pend || busy_q)) dbg_late <= 1'b1;
                late_now <= pass_due && (pend || busy_q);
                if (pass_due) begin
                    pend       <= 1'b1;
                    pend_flush <= (pass_l == VVIS);
                    pend_line  <= (pass_l == VVIS) ? 9'(VVIS - 1) : pass_l[8:0];
                end
                if (v_next == VVIS) snap_pend <= 1'b1;  // vblank begins
            end
            if (snap_pend && !pend && !busy_q && !line_start && !ls_d) begin
                snapshot  <= 1'b1;
                snap_pend <= 1'b0;
                snap_run  <= 1'b1;
            end
            if (pend && !busy_q && !line_start && !ls_d && !frame_pend && !frame_start && !fs_d
                && !snap_run && !snapshot) begin
                line_start <= 1'b1;
                line <= flip_f ? flip_line(pend_line) : pend_line;
                pend <= 1'b0;
                // the pixels this pass emits are the line before, except the flush's
                out_valid <= pend_flush || (pend_line != 9'd0);
                out_line  <= pend_flush ? 10'(VVIS - 1) : 10'(pend_line) - 10'd1;
            end
            // the block only takes frame_start when idle
            if (snapshot_done) begin
                frame_pend <= 1'b1;
                snap_run   <= 1'b0;
            end
            if (frame_pend && !busy_q && !line_start && !ls_d && !fs_d) begin
                frame_start <= 1'b1;
                frame_pend  <= 1'b0;
            end
        end
    end

    // ---- the output line buffer, two lines -----------------------------------------------------------
    logic [23:0] obuf [0:1023];
    logic [23:0] obuf_q;

    initial for (int i = 0; i < 1024; i++) obuf[i] = 24'd0;

    always_ff @(posedge clk) begin
        if (px_we && out_valid) obuf[{out_line[0], px_x}] <= px_rgb;     // px_x is 0-511
        obuf_q <= obuf[{v[0], flip_f ? 9'(wx0 + wx0 + ww - 10'd1 - h) : h[8:0]}];
    end

    // The buffer is read on every clock, so obuf_q holds pixel h from the clock after the
    // counters reach it. Everything the display sees is registered together a clock later, and
    // ce_pix marks the clock it is all valid on.
    always_ff @(posedge clk) begin
        ce_pix <= (div == 3'd1);
        if (div == 3'd1) begin
            hblank    <= !in_x_q;
            vblank    <= !in_y_q;
            hsync     <= (h >= 10'(HS_START)) && (h < 10'(HS_END));
            vsync     <= (v >= 10'(VS_START)) && (v < 10'(VS_END));
            {r, g, b} <= (in_x_q && in_y_q) ? obuf_q : 24'd0;
        end
    end

    // ---- scanline interrupts -----------------------------------------------------------------------
    logic [1:0] vb_hold, ra_hold, net_hold;
    // registered: from the CPU's register through the add and compare it missed clk2x by 1.4 ns
    logic [31:0] raster_at;
    always_ff @(posedge clk) raster_at <= raster_pos + 32'd8;
    wire  [8:0]  half = v_next[9:1];                    // MAME's scanline_shifted

    always_ff @(posedge clk) begin
        if (reset) begin
            vb_hold <= 2'd0; ra_hold <= 2'd0; net_hold <= 2'd0;
        end else begin
            if (vb_hold  != 2'd0) vb_hold  <= vb_hold  - 2'd1;
            if (ra_hold  != 2'd0) ra_hold  <= ra_hold  - 2'd1;
            if (net_hold != 2'd0) net_hold <= net_hold - 2'd1;
            if (line_begin && !v_next[0]) begin
                if (half == 9'd224)      vb_hold  <= 2'd2;
                else if (half == 9'd240) net_hold <= 2'd2;
                else if (raster_at == {23'd0, half} && half < 9'd224) ra_hold <= 2'd2;
            end
        end
    end

    assign vblank_irq   = (vb_hold != 2'd0);
    assign raster_irq   = (ra_hold != 2'd0);
    assign net_irq      = (net_hold != 2'd0);
    // the screen's vblank() as MAME reports it: outside the window's lines
    assign vblank_level = !in_y;

    assign dbg_sched = {late_now, frame_pend, pend};

endmodule
