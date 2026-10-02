// SPDX-License-Identifier: GPL-3.0-or-later
//
// A FIFO between two unrelated clocks. Pointers cross as Gray code through two registers each
// (the SDC puts the clocks in asynchronous groups); the store is an hng64_bram, a port a clock.
// The read side is first-word-fall-through: r_valid/r_data show the head, r_ready takes it. The
// RAM answers a clock after its address, so the head comes from a two-entry queue that fetches
// ahead, and a FIFO drained every clock reads one word every clock.
//
// w_count is the write side's view of how many words are in the store (late by the synchroniser,
// so never low). A word leaves the store when it is fetched to the read side's head queue, before
// r_ready takes it, so zero does not mean everything written has been taken.

module hng64_afifo #(
    parameter int DW = 32,
    parameter int AW = 5                // 2^AW words
) (
    input  logic          wclk,
    input  logic          wrst,
    input  logic          w_valid,
    output logic          w_ready,      // not full
    input  logic [DW-1:0] w_data,
    output logic   [AW:0] w_count,

    input  logic          rclk,
    input  logic          rrst,
    output logic          r_valid,
    input  logic          r_ready,
    output logic [DW-1:0] r_data
);

    function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
        return b ^ (b >> 1);
    endfunction
    function automatic logic [AW:0] gray2bin(input logic [AW:0] g);
        logic [AW:0] b;
        b[AW] = g[AW];
        for (int i = AW - 1; i >= 0; i--) b[i] = b[i + 1] ^ g[i];
        return b;
    endfunction

    // ---- write side --------------------------------------------------------------------------------
    logic [AW:0] wb = '0, wg = '0;                  // the write pointer, binary and Gray
    logic [AW:0] rg = '0;                           // the read pointer, Gray (read side)
    logic [AW:0] rg_w1 = '0, rg_w2 = '0;            // the read pointer, synchronised here
    wire  [AW:0] rb_w = gray2bin(rg_w2);
    wire         push = w_valid && w_ready;

    assign w_count = wb - rb_w;
    assign w_ready = w_count != (AW+1)'(1 << AW);

    always_ff @(posedge wclk) begin
        rg_w1 <= rg;
        rg_w2 <= rg_w1;
        if (wrst) begin
            wb <= '0;
            wg <= '0;
        end else if (push) begin
            wb <= wb + 1'b1;
            wg <= bin2gray(wb + 1'b1);
        end
    end

    // ---- the store ---------------------------------------------------------------------------------
    localparam int SW = (DW + 7) / 8 * 8;          // hng64_bram's width is whole bytes
    logic [AW:0] rb = '0;                           // the next word to fetch
    logic [SW-1:0] q;

    hng64_bram #(.AW(AW), .DW(SW)) u_mem (
        .a_clk(wclk), .a_addr(wb[AW-1:0]), .a_be({(SW/8){push}}), .a_wdata(SW'(w_data)), .a_rdata(),
        .b_clk(rclk), .b_addr(rb[AW-1:0]), .b_rdata(q));

    // ---- read side ---------------------------------------------------------------------------------
    logic [AW:0] wg_r1 = '0, wg_r2 = '0;
    wire  [AW:0] wb_r = gray2bin(wg_r2);
    wire         empty = rb == wb_r;

    logic          p_v;                             // q holds the word fetched last clock
    logic    [1:0] h_n;                             // words in the head queue
    logic [DW-1:0] h0, h1;
    wire           pop   = r_ready && h_n != 2'd0;
    wire           fetch = !empty && (3'(h_n) + 3'(p_v) - 3'(pop)) < 3'd2;

    assign r_valid = h_n != 2'd0;
    assign r_data  = h0;

    always_ff @(posedge rclk) begin
        wg_r1 <= wg;
        wg_r2 <= wg_r1;
        if (rrst) begin
            rb  <= '0;
            rg  <= '0;
            p_v <= 1'b0;
            h_n <= 2'd0;
        end else begin
            p_v <= fetch;
            if (fetch) begin
                rb <= rb + 1'b1;
                rg <= bin2gray(rb + 1'b1);
            end
            // the head queue: pop the front, append the fetched word
            case ({p_v, pop})
                2'b10: begin
                    if (h_n == 2'd0) h0 <= q[DW-1:0]; else h1 <= q[DW-1:0];
                    h_n <= h_n + 2'd1;
                end
                2'b01: begin
                    h0  <= h1;
                    h_n <= h_n - 2'd1;
                end
                2'b11: begin
                    if (h_n == 2'd1) h0 <= q[DW-1:0];
                    else begin h0 <= h1; h1 <= q[DW-1:0]; end
                end
                default: ;
            endcase
        end
    end

endmodule
