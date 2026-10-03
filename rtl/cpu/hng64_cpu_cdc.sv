// SPDX-License-Identifier: GPL-3.0-or-later
//
// The CPU's memory port across to the board when the CPU runs on its own PLL (rtl/pll/pll_cpu.v).
// The vendored VR4300 clocks logic on all three of its clocks, and assumes them related (3:2:4);
// so the CPU gets its own three, and this bridge carries its port (cpu.vhd's mem_*, the fill grant
// and beats) between them and the board's clk1x/clk2x, which hng64_bus uses.
//
// One access is out at a time (the CPU waits for mem_done), so:
//   - a request crosses as a toggle; its fields are held until it completes;
//   - the fill grant, the fill beats and the completion come back through one dual-clock FIFO, as
//     tokens in the order hng64_bus made them, so the completion never passes the last beat.

module hng64_cpu_cdc (
    // the CPU's side
    input  logic        c1x,
    input  logic        c2x,
    input  logic        c_rst,          // c1x
    input  logic        c_request,
    input  logic        c_rnw,
    input  logic [31:0] c_address,
    input  logic        c_req64,
    input  logic  [2:0] c_size,
    input  logic  [7:0] c_mask,
    input  logic [63:0] c_wdata,
    output logic [63:0] c_dataRead,
    output logic        c_done,
    output logic        c_granted2x,
    output logic [63:0] c_DOUT,
    output logic        c_DOUT_READY,

    // the board's side
    input  logic        b1x,
    input  logic        b2x,
    input  logic        b_rst,          // b1x
    output logic        b_request,
    output logic        b_rnw,
    output logic [31:0] b_address,
    output logic        b_req64,
    output logic  [2:0] b_size,
    output logic  [7:0] b_mask,
    output logic [63:0] b_wdata,
    input  logic [63:0] b_dataRead,
    input  logic        b_done,
    input  logic        b_granted2x,
    input  logic [63:0] b_DOUT,
    input  logic        b_DOUT_READY
);

    localparam logic [1:0] T_GRANT = 2'd1, T_BEAT = 2'd2, T_DONE = 2'd3;

    // ---- the request -----------------------------------------------------------------------------------
    logic rq_t = 1'b0;
    always_ff @(posedge c1x) begin
        if (c_rst) rq_t <= 1'b0;
        else if (c_request) begin
            rq_t      <= ~rq_t;
            b_rnw     <= c_rnw;
            b_address <= c_address;
            b_req64   <= c_req64;
            b_size    <= c_size;
            b_mask    <= c_mask;
            b_wdata   <= c_wdata;
        end
    end

    logic rq_1 = 1'b0, rq_2 = 1'b0, rq_3 = 1'b0;
    always_ff @(posedge b1x) begin
        rq_1 <= rq_t;
        rq_2 <= rq_1;
        rq_3 <= rq_2;
        b_request <= !b_rst && rq_2 != rq_3;
    end

    // ---- the replies -----------------------------------------------------------------------------------
    // b_done is a clk1x pulse, two clk2x clocks long; its first clk2x clock makes the completion
    // pending, and it is queued in the first clock no grant or beat is (hng64_bus can give the last
    // beat in the clock the completion arrives: boot_tb hung on a dropped one)
    logic        done_q = 1'b0, done_pend = 1'b0;
    logic [63:0] done_data;
    wire         done_new = b_done && !done_q;

    logic        tk_push;
    logic [65:0] tk_in;
    always_comb begin
        tk_push = 1'b1;
        if (b_granted2x)                   tk_in = {T_GRANT, 64'd0};
        else if (b_DOUT_READY)             tk_in = {T_BEAT, b_DOUT};
        else if (done_pend)                tk_in = {T_DONE, done_data};
        else if (done_new)                 tk_in = {T_DONE, b_dataRead};
        else begin
            tk_push = 1'b0;
            tk_in   = 66'd0;
        end
    end

    always_ff @(posedge b2x) begin
        done_q <= b_done;
        if (b_rst) done_pend <= 1'b0;
        else if (done_new && (b_granted2x || b_DOUT_READY)) begin
            done_pend <= 1'b1;
            done_data <= b_dataRead;
        end else if (done_pend && !b_granted2x && !b_DOUT_READY) begin
            done_pend <= 1'b0;
        end
    end

    // the token a clock before the FIFO: from hng64_bus's DOUT_READY through the select of four
    // 64-bit sources into the FIFO's storage it missed clk2x by 0.8 ns
    logic        tk_push_q = 1'b0;
    logic [65:0] tk_in_q;
    always_ff @(posedge b2x) begin
        tk_push_q <= !b_rst && tk_push;
        tk_in_q   <= tk_in;
    end

    logic        tk_valid;
    logic [65:0] tk_out;
    hng64_afifo #(.DW(66), .AW(3)) u_tok (
        .wclk(b2x), .wrst(b_rst), .w_valid(tk_push_q), .w_ready(), .w_data(tk_in_q), .w_count(),
        .rclk(c2x), .rrst(c_rst), .r_valid(tk_valid), .r_ready(1'b1), .r_data(tk_out));

    logic        dn_t = 1'b0;
    logic [63:0] dn_data;
    always_ff @(posedge c2x) begin
        c_granted2x  <= tk_valid && tk_out[65:64] == T_GRANT;
        c_DOUT_READY <= tk_valid && tk_out[65:64] == T_BEAT;
        c_DOUT       <= tk_out[63:0];
        if (c_rst) dn_t <= 1'b0;
        else if (tk_valid && tk_out[65:64] == T_DONE) begin
            dn_t    <= ~dn_t;
            dn_data <= tk_out[63:0];
        end
    end

    // c2x is twice c1x from the same PLL: the toggle is held until the next access
    logic dn_q = 1'b0;
    always_ff @(posedge c1x) begin
        dn_q   <= dn_t;
        c_done <= !c_rst && dn_t != dn_q;
        if (dn_t != dn_q) c_dataRead <= dn_data;
    end

endmodule
