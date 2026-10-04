// SPDX-License-Identifier: GPL-3.0-or-later
//
// CRT Adjust: H-Size, H-Position and V-Shift through crt_adjust.sv (rmonic79's, vendored via the
// Seta core), which moves and stretches the picture through a line buffer while the syncs stay
// native. After the MS32 core's ms32_crt.sv. The dot period here is fixed, two clocks at 50 MHz,
// so an H-Size step is a fiftieth of a clock of read period: 1% of the line (a quarter clock, the
// other cores' step, would be 12.5% here).
//
// H-Position is an index into 0, +1..+48, -48..-1 (wraps at 97); H-Size and V-Shift are signed.

`default_nettype none

module hng64_crt (
    input  wire       clk,            // CLK_VIDEO, 50 MHz
    input  wire       ce,             // the pixel enable, one clock in two
    input  wire       adjust,         // CRT Adjust On; this and the three below from clk1x
    input  wire [4:0] hsize_idx,
    input  wire [6:0] hpos_idx,
    input  wire [5:0] vshift_idx,

    input  wire [7:0] r_in, g_in, b_in,
    input  wire       hs_in, vs_in, hb_in, vb_in,

    output wire       active,         // module in the path
    output wire       ce_out,         // one clock
    output wire [7:0] r_out, g_out, b_out,
    output wire       hs_out, vs_out, hb_out, vb_out
);

    // The OSD's settings registered here before any logic: from clk1x the closest edge pair is
    // 4 ns apart, and crt_adjust takes V-Shift straight into a 528-way select.
    reg       adj = 1'b0;
    reg [4:0] hsize_q = 5'd0;
    reg [6:0] hpos_q = 7'd0;
    reg [5:0] vshift_q = 6'd0;
    always @(posedge clk) begin
        adj      <= adjust;
        hsize_q  <= hsize_idx;
        hpos_q   <= hpos_idx;
        vshift_q <= vshift_idx;
    end
    assign active = adj;

    // crt_adjust finds the HSync edge on every clock and takes pixels on its enable. hng64_vidcdc's
    // enable comes with its pixel; used as is, the picture lands a pixel right of CRT Adjust off
    // (sim/crt_tb), so it is taken a clock late.
    reg ce_d = 1'b0;
    always @(posedge clk) ce_d <= ce;

    reg  signed [4:0] hsize = 5'sd0;
    reg         [6:0] hpos = 7'd0;
    always @(posedge clk) if (ce_d) begin
        hsize <= adj ? $signed(hsize_q) : 5'sd0;
        hpos  <= adj ? hpos_q : 7'd0;
    end
    wire signed [8:0] hoffset = (hpos <= 7'd48)
        ? $signed({2'b00, hpos})
        : $signed({2'b00, hpos}) - 9'sd97;
    wire signed [5:0] voffset = adj ? $signed(vshift_q) : 6'sd0;

    // read enable in fiftieths of a clock: 100 per pixel, +1 per H-Size step; restarted on
    // hs_ref (crt_adjust's reference HSync)
    wire       hs_ref;
    reg        hs_ref_d = 1'b0;
    reg  [7:0] acc = 8'd0;
    wire [7:0] period = 8'd100 + {{3{hsize[4]}}, hsize};
    wire       tick   = (acc + 8'd50) >= period;
    always @(posedge clk) begin
        hs_ref_d <= hs_ref;
        if (hs_ref & ~hs_ref_d) acc <= 8'd0;
        else if (tick)          acc <= acc + 8'd50 - period;
        else                    acc <= acc + 8'd50;
    end
    wire pxl2_cen = (hsize == 5'sd0) ? ce_d : tick;
    assign ce_out = pxl2_cen;

    crt_adjust #(.VTOTAL(528), .HTOTAL(768), .HPOS_MODE(1), .LB_AW(11)) u_crt_adjust (
        .clk(clk), .pxl_cen(ce_d), .pxl2_cen(pxl2_cen),
        .active(active), .hsize(hsize),
        .hoffset(hoffset), .voffset(voffset),
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .hs_in(hs_in), .vs_in(vs_in), .hb_in(hb_in), .vb_in(vb_in),
        .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .hs_out(hs_out), .vs_out(vs_out), .hb_out(hb_out), .vb_out(vb_out),
        .hs_ref_out(hs_ref)
    );

endmodule

`default_nettype wire
