// SPDX-License-Identifier: GPL-3.0-or-later
//
// Mosaic's first line of a group: x rounded down to a multiple of m + 1, which MAME writes as
// x - x % (m + 1) (hng64_v.cpp, hng64_sprite.ipp:349). A divide is not wanted in 2D video
// (WORKFLOW 14), so the remainder is taken by restoring subtraction: (m + 1) << k is subtracted
// where it fits, for k from W - 1 down to 0, one step a clock. done rises W + 1 clocks after
// start. The engines only start it when m is not 0.

module hng64_mosaic #(
    parameter int W = 11
) (
    input  logic         clk,
    input  logic         start,         // one cycle: x and m are taken
    input  logic [W-1:0] x,
    input  logic   [3:0] m,             // groups of m + 1 lines
    output logic         done,          // one cycle; base holds until the next start
    output logic [W-1:0] base
);

    localparam int KW = $clog2(W);

    logic [W-1:0]  x_q, r;
    logic [W+4:0]  d;                   // (m + 1) << k
    logic [KW-1:0] k;
    logic          run, fin;

    always_ff @(posedge clk) begin
        done <= 1'b0;
        fin  <= 1'b0;
        if (start) begin
            x_q <= x;
            r   <= x;
            d   <= (W+5)'({1'b0, m} + 5'd1) << (W - 1);
            k   <= KW'(W - 1);
            run <= 1'b1;
        end else if (run) begin
            if ({5'd0, r} >= d) r <= r - W'(d);
            d <= d >> 1;
            k <= k - 1'b1;
            if (k == '0) begin
                run <= 1'b0;
                fin <= 1'b1;
            end
        end
        if (fin) begin
            base <= x_q - r;
            done <= 1'b1;
        end
    end

endmodule
