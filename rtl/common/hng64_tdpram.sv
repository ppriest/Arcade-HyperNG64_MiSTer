// SPDX-License-Identifier: GPL-3.0-or-later
//
// True dual-port RAM, one clock, read data the clock after the address. Written in the form
// Quartus infers as an M10K with two read/write ports.
//
// Both ports write the same array from their own process, which is what that inference needs
// and what a linter reports as a second driver; the warning is switched off for this array only.
// A write on both ports to the same address in the same clock leaves the result undefined, as
// on the chip.

module hng64_tdpram #(
    parameter int AW = 11,
    parameter int DW = 8
) (
    input  logic          clk,

    input  logic [AW-1:0] a_addr,
    input  logic          a_we,
    input  logic [DW-1:0] a_wdata,
    output logic [DW-1:0] a_rdata,

    input  logic [AW-1:0] b_addr,
    input  logic          b_we,
    input  logic [DW-1:0] b_wdata,
    output logic [DW-1:0] b_rdata
);

    /* verilator lint_off MULTIDRIVEN */
    logic [DW-1:0] mem [0:(1<<AW)-1];
    /* verilator lint_on MULTIDRIVEN */

    initial begin
        for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
    end

    always_ff @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_wdata;
        a_rdata <= mem[a_addr];
    end

    always_ff @(posedge clk) begin
        if (b_we) mem[b_addr] <= b_wdata;
        b_rdata <= mem[b_addr];
    end

endmodule
