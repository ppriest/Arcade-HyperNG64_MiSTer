// SPDX-License-Identifier: GPL-3.0-or-later
//
// hng64_crt on HyperNG64's raster (768 x 528, 512 x 448 visible, the sync positions of
// rtl/video/hng64_vtiming.sv) at CLK_VIDEO, 50 MHz, a pixel every two clocks. Each probe measures
// one picture line: where the active pixels land in clocks from the HSync rise, how many there are
// and whether every source pixel (its hcount, carried in the RGB) comes out once and in order, and
// the line and VSync timing. The raster is made at clk2x (125 MHz, a pixel every five clocks,
// rising edges meeting the 50 MHz ones every 40 ns as on the PLL) and comes through hng64_vidcdc,
// as in HyperNG64.sv; enables out of the crossing that are not two clocks apart are counted, and
// CRT Adjust on is run at each of the five phases of the pixel enable against the shared edge.
// After the Seta core's sim/seta_crt_tb.

`timescale 1ns/1ps
`default_nettype none

module crt_probe #(parameter bit ADJUST = 1,
                   parameter logic [4:0] HSIZE = 5'd0,
                   parameter logic [6:0] HPOS = 7'd0,
                   parameter logic [5:0] VSHIFT = 6'd0,
                   parameter int PH = 0) (       // the clk2x divider's start, 0-4
    input  wire clk,
    input  wire clk2x,
    output int  first_c, last_c, npix, hs_period, vs_rise_c, ce_bad,
    output bit  ordered, done
);
    wire [7:0] ri, gi, bi;
    wire       hsi, vsi, hbi, vbi, cei;

    int h = 0, v = 0;
    bit [2:0] div = 3'(PH);
    always @(posedge clk2x) div <= (div == 3'd4) ? 3'd0 : div + 3'd1;
    wire ce2 = (div == 3'd0);
    always @(posedge clk2x) if (ce2) begin
        if (h == 767) begin h <= 0; v <= (v == 527) ? 0 : v + 1; end
        else h <= h + 1;
    end
    hng64_vidcdc u_cdc (
        .clk2x(clk2x), .ce_in(ce2),
        .r_in(8'(h)), .g_in(8'(h >> 8)), .b_in(8'(v)),
        .hs_in(h >= 608 && h < 672), .vs_in(v >= 452 && v < 456), .hb_in(h >= 512), .vb_in(v >= 448),
        .clk_vid(clk), .ce_out(cei),
        .r_out(ri), .g_out(gi), .b_out(bi),
        .hs_out(hsi), .vs_out(vsi), .hb_out(hbi), .vb_out(vbi)
    );

    wire [7:0] r, g, b;
    wire       hs_o, vs_o, hb_o, vb_o, act, ce_o;
    hng64_crt u_crt (
        .clk(clk), .ce(cei), .adjust(ADJUST),
        .hsize_idx(HSIZE), .hpos_idx(HPOS), .vshift_idx(VSHIFT),
        .r_in(ri), .g_in(gi), .b_in(bi),
        .hs_in(hsi), .vs_in(vsi), .hb_in(hbi), .vb_in(vbi),
        .active(act), .ce_out(ce_o),
        .r_out(r), .g_out(g), .b_out(b),
        .hs_out(hs_o), .vs_out(vs_o), .hb_out(hb_o), .vb_out(vb_o)
    );

    int cyc = 0, hs_rise = 0, prev_rise = 0, lines = 0, expect_px = 0, last_ce = 0;
    bit hs_d = 0, hb_d = 1, vs_d = 0, meas = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        hs_d <= hs_o;
        hb_d <= hb_o;
        vs_d <= vs_o;
        if (cei) begin
            if (last_ce != 0 && cyc - last_ce != 2) ce_bad = ce_bad + 1;
            last_ce = cyc;
        end
        // the first VSync rise of the third frame
        if (vs_o && !vs_d && cyc > 2 * 528 * 1536 && vs_rise_c == 0) vs_rise_c = cyc;
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
    // 50 MHz and 125 MHz with rising edges together every 40 ns, from 4 ns
    bit clk = 0, clk2x = 0;
    always #4 clk2x = ~clk2x;
    initial begin #4; forever begin clk = 1; #10; clk = 0; #10; end end

    localparam int N = 13;
    int f[N], l[N], n[N], hp[N], vr[N], cb[N];
    bit o[N], d[N];

    // 0 on, nothing moved; 1 off (bypass); 2 H-Size +10; 3 H-Size -16; 4 H-Position -8 (index 89);
    // 5 H-Position +48; 6 V-Shift +5; 7 V-Shift -5 (index 59); 8 H-Size +15 and H-Position -8,
    // the widest picture: 664 pixels from the HSync rise at 2.3 clocks is 1527 of 1536;
    // 9-12 on, the pixel enable's other four phases
    crt_probe #(.ADJUST(1))                  p0 (clk, clk2x, f[0], l[0], n[0], hp[0], vr[0], cb[0], o[0], d[0]);
    crt_probe #(.ADJUST(0))                  p1 (clk, clk2x, f[1], l[1], n[1], hp[1], vr[1], cb[1], o[1], d[1]);
    crt_probe #(.HSIZE(5'd10))               p2 (clk, clk2x, f[2], l[2], n[2], hp[2], vr[2], cb[2], o[2], d[2]);
    crt_probe #(.HSIZE(5'd16))               p3 (clk, clk2x, f[3], l[3], n[3], hp[3], vr[3], cb[3], o[3], d[3]);
    crt_probe #(.HPOS(7'd89))                p4 (clk, clk2x, f[4], l[4], n[4], hp[4], vr[4], cb[4], o[4], d[4]);
    crt_probe #(.HPOS(7'd48))                p5 (clk, clk2x, f[5], l[5], n[5], hp[5], vr[5], cb[5], o[5], d[5]);
    crt_probe #(.VSHIFT(6'd5))               p6 (clk, clk2x, f[6], l[6], n[6], hp[6], vr[6], cb[6], o[6], d[6]);
    crt_probe #(.VSHIFT(6'd59))              p7 (clk, clk2x, f[7], l[7], n[7], hp[7], vr[7], cb[7], o[7], d[7]);
    crt_probe #(.HSIZE(5'd15), .HPOS(7'd89)) p8 (clk, clk2x, f[8], l[8], n[8], hp[8], vr[8], cb[8], o[8], d[8]);
    crt_probe #(.PH(1))                   p9 (clk, clk2x, f[9], l[9], n[9], hp[9], vr[9], cb[9], o[9], d[9]);
    crt_probe #(.PH(2))                   pa (clk, clk2x, f[10], l[10], n[10], hp[10], vr[10], cb[10], o[10], d[10]);
    crt_probe #(.PH(3))                   pb (clk, clk2x, f[11], l[11], n[11], hp[11], vr[11], cb[11], o[11], d[11]);
    crt_probe #(.PH(4))                   pc (clk, clk2x, f[12], l[12], n[12], hp[12], vr[12], cb[12], o[12], d[12]);

    string names[N] = '{"on      ", "off     ", "hsize+10", "hsize-16", "hpos-8  ", "hpos+48 ",
                        "vshift+5", "vshift-5", "widest  ", "on ph1  ", "on ph2  ", "on ph3  ",
                        "on ph4  "};
    int fails = 0;
    task automatic check(bit ok, string what);
        if (!ok) begin $display("FAIL %s", what); fails++; end
    endtask
    initial begin
        wait (d.and() == 1'b1);
        for (int i = 0; i < N; i++)
            $display("%s  active %4d..%4d (%4d clocks)  pixels %3d  ordered %0d  line %4d  vsync rise %0d  enables off by %0d",
                     names[i], f[i], l[i], l[i] - f[i], n[i], o[i], hp[i], vr[i], cb[i]);
        for (int i = 0; i < N; i++) begin
            check(n[i] == 512 && o[i], {names[i], ": not every source pixel once, in order"});
            check(hp[i] == 1536, {names[i], ": line is not 768 x 2 clocks"});
            check(cb[i] == 0, {names[i], ": pixel enables not every two clocks"});
        end
        check(l[0] - f[0] == 1024, "on: 512 pixels are not 1024 clocks");
        check(l[2] - f[2] >= 1126 && l[2] - f[2] <= 1127, "hsize+10: 512 pixels are not 512 x 2.2 clocks");
        check(l[3] - f[3] >= 859 && l[3] - f[3] <= 861, "hsize-16: 512 pixels are not 512 x 1.68 clocks");
        check(f[4] == f[0] - 16 && l[4] == l[0] - 16, "hpos-8: not 16 clocks left of on");
        check(f[5] == f[0] + 96 && l[5] == l[0] + 96, "hpos+48: not 96 clocks right of on");
        check(l[8] - f[8] >= 1177 && l[8] - f[8] <= 1178, "widest: 512 pixels are not 512 x 2.3 clocks");
        check(vr[6] - vr[0] == 5 * 1536, "vshift+5: vsync not 5 lines later");
        check(vr[0] - vr[7] == 5 * 1536 || vr[7] - vr[0] == 523 * 1536, "vshift-5: vsync not 5 lines earlier");
        check(f[0] == f[1] && l[0] == l[1], "on: not where off puts it");
        for (int i = 9; i < N; i++)
            check(f[i] == f[0] && l[i] == l[0], {names[i], ": not where on at phase 0 puts it"});
        if (fails) $display("crt: FAIL (%0d)", fails); else $display("crt: PASS");
        $finish;
    end
endmodule

`default_nettype wire
