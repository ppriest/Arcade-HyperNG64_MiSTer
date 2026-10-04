// SPDX-License-Identifier: GPL-3.0-or-later
//
// The display's pixel stream from clk2x (125 MHz, a pixel every five clocks) into CLK_VIDEO
// (50 MHz, every two). Both are the main PLL's and their rising edges meet every 40 ns, one pixel,
// so this is a synchronous crossing: clk2x holds each pixel for its five clocks with a toggle,
// the 50 MHz side registers both every clock and takes the pixel when the toggle has moved. The
// timing analysis checks the two registers' inputs against the closest edge pair, a clk2x edge
// 4 ns before a 50 MHz one; nothing else crosses. The output enable comes every second clock.

`default_nettype none

module hng64_vidcdc (
    input  wire       clk2x,
    input  wire       ce_in,          // one clock in five, the pixel valid
    input  wire [7:0] r_in, g_in, b_in,
    input  wire       hs_in, vs_in, hb_in, vb_in,

    input  wire       clk_vid,        // 50 MHz
    output reg        ce_out = 1'b0,  // one clock in two
    output reg  [7:0] r_out = 8'd0, g_out = 8'd0, b_out = 8'd0,
    output reg        hs_out = 1'b0, vs_out = 1'b0, hb_out = 1'b1, vb_out = 1'b1
);

    reg [27:0] h = 28'd0;
    reg        t = 1'b0;
    always @(posedge clk2x) if (ce_in) begin
        h <= {r_in, g_in, b_in, hs_in, vs_in, hb_in, vb_in};
        t <= ~t;
    end

    reg [27:0] h_q = 28'd0;
    reg        t_q = 1'b0, t_qq = 1'b0;
    always @(posedge clk_vid) begin
        h_q    <= h;
        t_q    <= t;
        t_qq   <= t_q;
        ce_out <= t_q != t_qq;
        if (t_q != t_qq) {r_out, g_out, b_out, hs_out, vs_out, hb_out, vb_out} <= h_q;
    end

endmodule

`default_nettype wire
