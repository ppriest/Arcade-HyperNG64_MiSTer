// SPDX-License-Identifier: GPL-3.0-or-later
//
// CRT Adjust: H-Size, H-Position and V-Shift through crt_adjust.sv (rmonic79's, vendored via the
// Seta core), which moves and stretches the picture through a line buffer while the syncs stay
// native. After the MS32 core's ms32_crt.sv. The dot period here is fixed, five clk2x, so an
// H-Size step is a twentieth of a clock of read period: 1% of the line (a quarter clock, the
// other cores' step, would be 5% here).
//
// H-Position is an index into 0, +1..+48, -48..-1 (wraps at 97); H-Size and V-Shift are signed.

`default_nettype none

module hng64_crt (
    input  wire       clk,            // clk2x, 125 MHz
    input  wire       ce,             // the pixel enable, one clock in five
    input  wire       adjust,         // CRT Adjust On
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

    assign active = adjust;

    reg  signed [4:0] hsize = 5'sd0;
    reg         [6:0] hpos = 7'd0;
    always @(posedge clk) if (ce) begin
        hsize <= adjust ? $signed(hsize_idx) : 5'sd0;
        hpos  <= adjust ? hpos_idx : 7'd0;
    end
    wire signed [8:0] hoffset = (hpos <= 7'd48)
        ? $signed({2'b00, hpos})
        : $signed({2'b00, hpos}) - 9'sd97;
    wire signed [5:0] voffset = adjust ? $signed(vshift_idx) : 6'sd0;

    // read enable in twentieths of a clock: 100 per pixel, +1 per H-Size step; restarted on
    // hs_ref (crt_adjust's reference HSync)
    wire       hs_ref;
    reg        hs_ref_d = 1'b0;
    reg  [7:0] acc = 8'd0;
    wire [7:0] period = 8'd100 + {{3{hsize[4]}}, hsize};
    wire       tick   = (acc + 8'd20) >= period;
    always @(posedge clk) begin
        hs_ref_d <= hs_ref;
        if (hs_ref & ~hs_ref_d) acc <= 8'd0;
        else if (tick)          acc <= acc + 8'd20 - period;
        else                    acc <= acc + 8'd20;
    end
    wire pxl2_cen = (hsize == 5'sd0) ? ce : tick;
    assign ce_out = pxl2_cen;

    crt_adjust #(.VTOTAL(528), .HTOTAL(768), .HPOS_MODE(1), .LB_AW(11)) u_crt_adjust (
        .clk(clk), .pxl_cen(ce), .pxl2_cen(pxl2_cen),
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
