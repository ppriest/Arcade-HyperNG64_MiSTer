// SPDX-License-Identifier: GPL-3.0-or-later
//
// DDR3 read transport: several clients, many reads in flight, replies in order; and one writer.
//
// The four sibling cores' `ddram_phy.sv` runs one transaction at a time and waits for it
// (`BURSTCNT = 1`, its own header calls wider bursts "the obvious throughput improvement"), which
// is why LESSONS_LEARNED says not to fetch from DDR3 in real time. This core has no choice
// (docs/MEMORY.md): no set's ROM fits SDRAM. So the port is driven the way its Avalon interface
// allows - a new read whenever it is not busy, without waiting for the last one - and the reads
// come back in order, which is all the video engines ask for.
//
// Burst count stays 1 because nothing here reads consecutive granules: a tile row's four words
// are 32, 128 and 160 bytes apart, and a sprite's two rows 128. What buys the throughput is the
// depth in flight, not the width of each read.
//
// The HPS writes the ROM image before the core runs, so the clients only read. The one writer is
// the HDMI rotator (screen_rotate_two, through hng64_wfifo): single beats into its own window,
// issued when no read is, or before reads once its FIFO is half full, so a rotated picture loses
// no pixels to a busy video line. Writes take no place in the reply queue.

module hng64_ddram #(
    parameter int N = 2,                 // clients
    parameter int LIMIT = 48             // reads allowed in flight, under the reply queue's depth
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        DDRAM_BUSY,
    output logic  [7:0] DDRAM_BURSTCNT,
    output logic [28:0] DDRAM_ADDR,
    input  logic [63:0] DDRAM_DOUT,
    input  logic        DDRAM_DOUT_READY,
    output logic        DDRAM_RD,
    output logic [63:0] DDRAM_DIN,
    output logic  [7:0] DDRAM_BE,
    output logic        DDRAM_WE,

    // the writer: a FIFO head, held until w_ready. w_addr is a whole DDRAM address.
    input  logic [28:0] w_addr,
    input  logic [63:0] w_din,
    input  logic  [7:0] w_be,
    input  logic        w_valid,
    input  logic        w_urgent,        // the FIFO is half full: go before reads
    output logic        w_ready,

    // byte offsets from the core's DDR3 base, 8-aligned. A request is held until ready.
    input  logic [27:0] c_addr [0:N-1],
    input  logic        c_rd   [0:N-1],
    output logic        c_ready [0:N-1],
    output logic [63:0] c_data,
    output logic        c_valid [0:N-1]
);

    localparam int IW = (N <= 2) ? 1 : (N <= 4) ? 2 : 3;

    assign DDRAM_BURSTCNT = 8'd1;
    assign DDRAM_DIN      = w_din;
    assign c_data         = DDRAM_DOUT;

    // ---- which client to serve: round robin, so no client can be starved by a busier one -------
    logic [IW-1:0] last, pick;
    logic          any;

    always_comb begin
        pick = '0;
        any  = 1'b0;
        for (int k = 1; k <= N; k++) begin
            int unsigned i;
            i = (int'(last) + k) % N;
            if (!any && c_rd[i]) begin
                pick = IW'(i);
                any  = 1'b1;
            end
        end
    end

    // ---- in flight, and the queue that routes each reply back ------------------------------------
    logic [IW-1:0] q [0:127];
    logic    [7:0] q_w, q_r;
    wire     [7:0] inflight = q_w - q_r;
    wire           read_ok   = any && (inflight < 8'(LIMIT));
    wire           wr_sel    = w_valid && (w_urgent || !read_ok);
    wire           can_issue = read_ok && !wr_sel && !DDRAM_BUSY;

    assign w_ready    = wr_sel && !DDRAM_BUSY;
    assign DDRAM_WE   = w_ready;
    assign DDRAM_RD   = can_issue;
    assign DDRAM_BE   = wr_sel ? w_be : 8'hFF;
    assign DDRAM_ADDR = wr_sel ? w_addr : {4'b0011, c_addr[pick][27:3]};

    always_comb
        for (int i = 0; i < N; i++) begin
            c_ready[i] = can_issue && (pick == IW'(i));
            c_valid[i] = DDRAM_DOUT_READY && (q[q_r[6:0]] == IW'(i));
        end

    always_ff @(posedge clk) begin
        if (reset) begin
            last <= '0;
            q_w  <= 8'd0;
            q_r  <= 8'd0;
        end else begin
            if (can_issue) begin
                q[q_w[6:0]] <= pick;
                q_w  <= q_w + 8'd1;
                last <= pick;
            end
            if (DDRAM_DOUT_READY) q_r <= q_r + 8'd1;
        end
    end

endmodule
