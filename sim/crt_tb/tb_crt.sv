// SPDX-License-Identifier: GPL-3.0-or-later
//
// hng64_crt on HyperNG64's raster (768 x 528, 512 x 448 visible, a pixel every five clocks, the
// sync positions of rtl/video/hng64_vtiming.sv). Each probe measures one picture line: where
// the active pixels land in clocks from the HSync rise, how many there are and whether every
// source pixel (its hcount, carried in the RGB) comes out once and in order, and the line and
// VSync timing. After the Seta core's sim/seta_crt_tb.

`timescale 1ns/1ps
`default_nettype none

module crt_probe #(parameter bit ADJUST = 1,
                   parameter logic [4:0] HSIZE = 5'd0,
                   parameter logic [6:0] HPOS = 7'd0,
                   parameter logic [5:0] VSHIFT = 6'd0) (
    input  wire clk,
    input  wire ce,
    output int  first_c, last_c, npix, hs_period, vs_rise_c,
    output bit  ordered, done
);
    // the raster
    int h = 0, v = 0;
    always @(posedge clk) if (ce) begin
        if (h == 767) begin h <= 0; v <= (v == 527) ? 0 : v + 1; end
        else h <= h + 1;
    end
    wire hs = h >= 608 && h < 672;
    wire vs = v >= 452 && v < 456;
    wire hb = h >= 512;
    wire vb = v >= 448;

    wire [7:0] r, g, b;
    wire       hs_o, vs_o, hb_o, vb_o, act, ce_o;
    hng64_crt u_crt (
        .clk(clk), .ce(ce), .adjust(ADJUST),
        .hsize_idx(HSIZE), .hpos_idx(HPOS), .vshift_idx(VSHIFT),
        .r_in(8'(h)), .g_in(8'(h >> 8)), .b_in(8'(v)),
        .hs_in(hs), .vs_in(vs), .hb_in(hb), .vb_in(vb),
        .active(act), .ce_out(ce_o),
        .r_out(r), .g_out(g), .b_out(b),
        .hs_out(hs_o), .vs_out(vs_o), .hb_out(hb_o), .vb_out(vb_o)
    );

    int cyc = 0, hs_rise = 0, prev_rise = 0, lines = 0, expect_px = 0;
    bit hs_d = 0, hb_d = 1, vs_d = 0, meas = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        hs_d <= hs_o;
        hb_d <= hb_o;
        vs_d <= vs_o;
        // the first VSync rise of the third frame
        if (vs_o && !vs_d && cyc > 2 * 528 * 3840 && vs_rise_c == 0) vs_rise_c = cyc;
        if (hs_o && !hs_d) begin
            prev_rise = hs_rise;
            hs_rise   = cyc;
            lines     = lines + 1;
            if (meas) done <= 1'b1;
            meas = (lines == 3 * 528 + 200);    // a picture line in the fourth frame
            if (meas) begin
                hs_period = hs_rise - prev_rise;
                npix = 0; expect_px = 0; ordered = 1;
            end
        end
        if (meas && !hb_o && hb_d) first_c = cyc - hs_rise;
        if (meas && hb_o && !hb_d) last_c = cyc - hs_rise;
        if (meas && !hb_o && (npix == 0 || {g[1:0], r} != 10'(expect_px - 1))) begin
            if ({g[1:0], r} != 10'(expect_px)) ordered = 0;
            expect_px = {g[1:0], r} + 1;
            npix = npix + 1;
        end
    end
endmodule

module tb_crt;
    bit clk = 0;
    always #4 clk = ~clk;
    bit [2:0] div = 0;
    always @(posedge clk) div <= (div == 3'd4) ? 3'd0 : div + 3'd1;
    wire ce = (div == 3'd0);

    localparam int N = 9;
    int f[N], l[N], n[N], hp[N], vr[N];
    bit o[N], d[N];

    // 0 on, nothing moved; 1 off (bypass); 2 H-Size +10; 3 H-Size -16; 4 H-Position -8 (index 89);
    // 5 H-Position +48; 6 V-Shift +5; 7 V-Shift -5 (index 59); 8 H-Size +15 and H-Position -8,
    // the widest picture: 664 pixels from the HSync rise at 5.75 clocks is 3818 of 3840
    crt_probe #(.ADJUST(1))                    p0 (clk, ce, f[0], l[0], n[0], hp[0], vr[0], o[0], d[0]);
    crt_probe #(.ADJUST(0))                    p1 (clk, ce, f[1], l[1], n[1], hp[1], vr[1], o[1], d[1]);
    crt_probe #(.HSIZE(5'd10))                 p2 (clk, ce, f[2], l[2], n[2], hp[2], vr[2], o[2], d[2]);
    crt_probe #(.HSIZE(5'd16))                 p3 (clk, ce, f[3], l[3], n[3], hp[3], vr[3], o[3], d[3]);
    crt_probe #(.HPOS(7'd89))                  p4 (clk, ce, f[4], l[4], n[4], hp[4], vr[4], o[4], d[4]);
    crt_probe #(.HPOS(7'd48))                  p5 (clk, ce, f[5], l[5], n[5], hp[5], vr[5], o[5], d[5]);
    crt_probe #(.VSHIFT(6'd5))                 p6 (clk, ce, f[6], l[6], n[6], hp[6], vr[6], o[6], d[6]);
    crt_probe #(.VSHIFT(6'd59))                p7 (clk, ce, f[7], l[7], n[7], hp[7], vr[7], o[7], d[7]);
    crt_probe #(.HSIZE(5'd15), .HPOS(7'd89))   p8 (clk, ce, f[8], l[8], n[8], hp[8], vr[8], o[8], d[8]);

    string names[N] = '{"on      ", "off     ", "hsize+10", "hsize-16", "hpos-8  ", "hpos+48 ",
                        "vshift+5", "vshift-5", "widest  "};
    int fails = 0;
    task automatic check(bit ok, string what);
        if (!ok) begin $display("FAIL %s", what); fails++; end
    endtask
    initial begin
        wait (d.and() == 1'b1);
        for (int i = 0; i < N; i++)
            $display("%s  active %4d..%4d (%4d clocks)  pixels %3d  ordered %0d  line %4d  vsync rise %0d",
                     names[i], f[i], l[i], l[i] - f[i], n[i], o[i], hp[i], vr[i]);
        for (int i = 0; i < N; i++) begin
            check(n[i] == 512 && o[i], {names[i], ": not every source pixel once, in order"});
            check(hp[i] == 3840, {names[i], ": line is not 768 x 5 clocks"});
        end
        check(l[0] - f[0] == 2560, "on: 512 pixels are not 2560 clocks");
        check(l[2] - f[2] == 2816, "hsize+10: 512 pixels are not 512 x 5.5 clocks");
        check(l[3] - f[3] >= 2149 && l[3] - f[3] <= 2151, "hsize-16: 512 pixels are not 512 x 4.2 clocks");
        check(f[4] == f[0] - 40 && l[4] == l[0] - 40, "hpos-8: not 40 clocks left of on");
        check(f[5] == f[0] + 240 && l[5] == l[0] + 240, "hpos+48: not 240 clocks right of on");
        check(l[8] - f[8] >= 2943 && l[8] - f[8] <= 2945, "widest: 512 pixels are not 512 x 5.75 clocks");
        check(vr[6] - vr[0] == 5 * 3840, "vshift+5: vsync not 5 lines later");
        check(vr[0] - vr[7] == 5 * 3840 || vr[7] - vr[0] == 523 * 3840, "vshift-5: vsync not 5 lines earlier");
        if (fails) $display("crt: FAIL (%0d)", fails); else $display("crt: PASS");
        $finish;
    end
endmodule

`default_nettype wire
