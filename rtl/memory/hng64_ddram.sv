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
// The HPS writes the ROM image before the core runs. The one write port, the 3D's (hng64_3d),
// takes single beats from a FIFO head, issued when the granted client is not reading, or before
// reads once the FIFO reports itself half full. Writes take no place in the reply queue.
//
// Clients in PRIO (the video engines, which must finish a line before it is shown) go before
// every other client and before the writer, and the other clients leave RESERVE of the in-flight
// limit to them. Round robin alone gave a video engine one read in eight while the 3D was busy:
// on hardware buriki's top 66 lines were mostly repeats of earlier lines, a new line every 14.

module hng64_ddram #(
    parameter int N = 2,                 // clients
    parameter int LIMIT = 48,            // reads allowed in flight, under the reply queue's depth
    parameter logic [N-1:0] PRIO = '0,   // clients served first
    parameter int RESERVE = 8            // of LIMIT, kept for PRIO clients
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
    output logic        c_valid [0:N-1],
    output logic  [7:0] dbg_inflight
);

    localparam int IW = (N <= 2) ? 1 : (N <= 4) ? 2 : 3;

    assign DDRAM_BURSTCNT = 8'd1;
    assign c_data         = DDRAM_DOUT;

    // ---- the issue register --------------------------------------------------------------------------
    // What goes to the port is a register, loaded when it is empty or its contents are being
    // taken this clock. So nothing a client computes reaches DDRAM_ADDR, or another client's
    // ready, in the same clock: the first full fit had the geometry engine's decode in front of
    // the HPS port (-9.6 ns) and every video engine (docs/phase3_3d.md, Timing).
    logic          o_valid, o_we;
    logic   [28:0] o_addr;
    logic   [63:0] o_din;
    logic    [7:0] o_be;

    wire load = !o_valid || !DDRAM_BUSY;

    assign DDRAM_RD   = o_valid && !o_we;
    assign DDRAM_WE   = o_valid && o_we;
    assign DDRAM_ADDR = o_addr;
    assign DDRAM_DIN  = o_din;
    assign DDRAM_BE   = o_be;

    // ---- which client: a registered round-robin grant ------------------------------------------------
    // Only the granted client can be taken, so a client's ready depends on its own request and on
    // registers. The grant moves to the next client asking once its holder is served or stops
    // asking; with requests held until ready, that loses no clock while others are waiting.
    logic [IW-1:0] gnt, nxt;
    logic          nxt_any, nxt_pri;

    always_comb begin
        nxt = gnt;
        nxt_any = 1'b0;
        nxt_pri = 1'b0;
        for (int k = 1; k <= N; k++) begin
            int unsigned i;
            i = (int'(gnt) + k) % N;
            if (!nxt_pri && PRIO[i] && c_rd[i]) begin
                nxt = IW'(i);
                nxt_pri = 1'b1;
            end
        end
        for (int k = 1; k <= N; k++) begin
            int unsigned i;
            i = (int'(gnt) + k) % N;
            if (!nxt_any && c_rd[i]) begin
                if (!nxt_pri) nxt = IW'(i);
                nxt_any = 1'b1;
            end
        end
    end

    // ---- in flight, and the queue that routes each reply back ------------------------------------
    logic [IW-1:0] q [0:127];
    logic    [7:0] q_w, q_r;
    wire     [7:0] inflight = q_w - q_r;      // taken into the issue register, not yet answered
    assign dbg_inflight = inflight;
    logic          g_pri;                    // the granted client is in PRIO
    wire           room     = inflight < (g_pri ? 8'(LIMIT) : 8'(LIMIT - RESERVE));
    wire           g_rd     = c_rd[gnt];
    logic          asked;                    // some client asked last clock
    logic          pasked;                   // some PRIO client asked last clock
    wire           wr_sel   = w_valid && !pasked && (w_urgent || !asked || !room);
    wire           rd_ok    = load && !wr_sel && room;     // registers and w_valid only
    wire           rd_take  = rd_ok && g_rd;

    assign w_ready = load && wr_sel;

    // each ready from its own request: rd_take's mux of all of them would put every client's
    // request in front of every other client's ready as far as timing analysis can tell
    always_comb
        for (int i = 0; i < N; i++) begin
            c_ready[i] = rd_ok && (gnt == IW'(i)) && c_rd[i];
            c_valid[i] = DDRAM_DOUT_READY && (q[q_r[6:0]] == IW'(i));
        end

    always_ff @(posedge clk) begin
        if (reset) begin
            gnt     <= '0;
            q_w     <= 8'd0;
            q_r     <= 8'd0;
            o_valid <= 1'b0;
            asked   <= 1'b0;
            pasked  <= 1'b0;
            g_pri   <= PRIO[0];
        end else begin
            if (load) begin
                o_valid <= w_ready || rd_take;
                o_we    <= w_ready;
                o_addr  <= w_ready ? w_addr : {4'b0011, c_addr[gnt][27:3]};
                o_din   <= w_din;
                o_be    <= w_ready ? w_be : 8'hFF;
            end
            if (rd_take) begin
                q[q_w[6:0]] <= gnt;
                q_w <= q_w + 8'd1;
            end
            if (DDRAM_DOUT_READY) q_r <= q_r + 8'd1;
            if (rd_take || !g_rd) begin
                gnt   <= nxt;
                g_pri <= PRIO[nxt];
            end
            asked  <= nxt_any;
            pasked <= nxt_pri;
        end
    end

endmodule
