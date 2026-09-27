// SPDX-License-Identifier: GPL-3.0-or-later
//
// True dual-port RAM, a clock per port, read data the clock after the address on that port's
// clock; the two clocks may be the same net. A write returns the data written on its own port
// (write-through): the only form Quartus 17 infers as a two-clock M10K. Returning the old data, it
// stops with 276001 (a one-RAM test synthesis of each form).
//
// Both ports write the same array from their own process, which is what that inference needs
// and what a linter reports as a second driver; the warning is switched off for this array only.
// A write on both ports to the same address in the same clock leaves the result undefined, as
// on the chip.

module hng64_tdpram #(
    parameter int AW = 11,
    parameter int DW = 8
) (
    input  logic          a_clk,
    input  logic [AW-1:0] a_addr,
    input  logic          a_we,
    input  logic [DW-1:0] a_wdata,
    output logic [DW-1:0] a_rdata,

    input  logic [AW-1:0] b_addr,
    input  logic          b_we,
    input  logic          b_clk,
    input  logic [DW-1:0] b_wdata,
    output logic [DW-1:0] b_rdata
);

    /* verilator lint_off MULTIDRIVEN */
    logic [DW-1:0] mem [0:(1<<AW)-1];
    /* verilator lint_on MULTIDRIVEN */

    // Zero for the benches; an M10K is zero at configuration, so synthesis is not given it.
    // synthesis translate_off
    initial begin
        for (int i = 0; i < (1 << AW); i++) mem[i] = '0;
    end
    // synthesis translate_on

    always_ff @(posedge a_clk) begin
        if (a_we) begin
            mem[a_addr] <= a_wdata;
            a_rdata <= a_wdata;
        end else begin
            a_rdata <= mem[a_addr];
        end
    end

    always_ff @(posedge b_clk) begin
        if (b_we) begin
            mem[b_addr] <= b_wdata;
            b_rdata <= b_wdata;
        end else begin
            b_rdata <= mem[b_addr];
        end
    end

endmodule
