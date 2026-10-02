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
    parameter logic [N-1:0] ORD = '0,    // clients whose reads must not pass the writer's writes
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

    // Replies go out a clock after the port gives them, registered: decoded from the queue's head
    // straight into every client's valid, they missed clk2x by up to 3.2 ns (fb3d's line buffer,
    // the loader, the backing store). Clients take replies in order and at any latency.
    always_ff @(posedge clk) c_data <= DDRAM_DOUT;

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
    // A spare register beside the issue register: a new request is accepted whenever the spare is
    // empty (sp_v, a register), and waits there if the port cannot take it this clock. So no
    // client's ready depends on DDRAM_BUSY (into the backing store's address it missed clk2x by
    // 1.8 ns). The spare goes out before anything newer is accepted, so order is kept.
    logic          sp_v, sp_we;
    logic   [28:0] sp_addr;
    logic   [63:0] sp_din;
    logic    [7:0] sp_be;
    wire           acc = !sp_v;

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
    // The next grant is chosen from the requests as they were a clock ago: from the live ones, a
    // client's decode reached the grant register through the round robin (the geometry engine's
    // vertex read, 3.2 ns over clk2x). A request that has since been served or withdrawn only
    // costs the grant a clock (g_rd low moves it on).
    logic          c_rd_q [0:N-1];
    always_ff @(posedge clk) for (int i = 0; i < N; i++) c_rd_q[i] <= c_rd[i];

    // round robin as two lowest-set-bit picks: among those above the grant, else among all (the
    // rotating loops it replaces missed clk2x by 1.8 ns into g_pri)
    function automatic logic [IW-1:0] lowest(input logic [N-1:0] v);
        lowest = '0;
        for (int i = N - 1; i >= 0; i--) if (v[i]) lowest = IW'(i);
    endfunction

    logic [N-1:0] reqv, reqp, above;
    always_comb begin
        for (int i = 0; i < N; i++) begin
            reqv[i]  = c_rd_q[i];
            above[i] = i > int'(gnt);
        end
        reqp    = reqv & PRIO;
        nxt_pri = reqp != '0;
        nxt_any = reqv != '0;
        if (nxt_pri)      nxt = ((reqp & above) != '0) ? lowest(reqp & above) : lowest(reqp);
        else if (nxt_any) nxt = ((reqv & above) != '0) ? lowest(reqv & above) : lowest(reqv);
        else              nxt = gnt;
    end

    // ---- in flight, and the queue that routes each reply back ------------------------------------
    logic [IW-1:0] q [0:127];
    logic    [7:0] q_w, q_r;
    wire     [7:0] inflight = q_w - q_r;      // taken into the issue register, not yet answered
    assign dbg_inflight = inflight;
    logic          g_pri;                    // the granted client is in PRIO
    // room is registered, a read short so that one taken in the clock it is stale still fits
    // (from the queue pointers into every client's ready it missed clk2x by 2.1 ns)
    logic          room_all, room_np;
    always_ff @(posedge clk) begin
        room_all <= inflight < 8'(LIMIT - 1);
        room_np  <= inflight < 8'(LIMIT - RESERVE - 1);
    end
    wire           room     = g_pri ? room_all : room_np;
    wire           g_rd     = c_rd[gnt];
    logic          asked;                    // some client asked last clock
    logic          pasked;                   // some PRIO client asked last clock
    // The writer's head is taken into a holding register, refilled in the clock it issues, so
    // the write/read choice is made from registers: from the writer's FIFO through it into every
    // client's ready missed clk2x by 1.9 ns.
    logic          h_v, h_urg;
    logic   [28:0] h_addr;
    logic   [63:0] h_din;
    logic    [7:0] h_be;
    // An ORD client's read is not taken while a write is held: the 3D's reads and writes share one
    // ordered queue (hng64_3d_bridge), and a read taken after a held write could be issued before it
    // (a depth line read back stale; g3d_tb, one pixel). Nor does an ORD client's request keep a
    // held write waiting (oasked, the others' requests): it is waiting for that write.
    logic          oasked;
    wire           wr_sel   = h_v && !pasked && (h_urg || !oasked || !room);
    wire           w_issue  = acc && wr_sel;
    wire           rd_ok    = acc && !wr_sel && room;      // registers only
    logic          g_ord;                    // the granted client is in ORD
    wire           g_blk    = g_ord && h_v;  // ... and is held back by a held write
    wire           rd_take  = rd_ok && g_rd && !g_blk;

    assign w_ready = !h_v || w_issue;

    always_ff @(posedge clk) begin
        h_urg <= w_urgent;
        if (reset) h_v <= 1'b0;
        else if (w_ready) begin
            h_v    <= w_valid;
            h_addr <= w_addr;
            h_din  <= w_din;
            h_be   <= w_be;
        end
    end

    // each ready from its own request: rd_take's mux of all of them would put every client's
    // request in front of every other client's ready as far as timing analysis can tell
    always_comb
        for (int i = 0; i < N; i++) c_ready[i] = rd_ok && (gnt == IW'(i)) && c_rd[i] && !(ORD[i] && h_v);

    always_ff @(posedge clk)
        for (int i = 0; i < N; i++) c_valid[i] <= !reset && DDRAM_DOUT_READY && (q[q_r[6:0]] == IW'(i));

    always_ff @(posedge clk) begin
        if (reset) begin
            gnt     <= '0;
            q_w     <= 8'd0;
            q_r     <= 8'd0;
            o_valid <= 1'b0;
            sp_v    <= 1'b0;
            asked   <= 1'b0;
            pasked  <= 1'b0;
            oasked  <= 1'b0;
            g_pri   <= PRIO[0];
            g_ord   <= ORD[0];
        end else begin
            if (load) begin
                if (sp_v) begin
                    o_valid <= 1'b1;
                    o_we    <= sp_we;
                    o_addr  <= sp_addr;
                    o_din   <= sp_din;
                    o_be    <= sp_be;
                    sp_v    <= 1'b0;
                end else begin
                    o_valid <= w_issue || rd_take;
                    o_we    <= w_issue;
                    o_addr  <= w_issue ? h_addr : {4'b0011, c_addr[gnt][27:3]};
                    o_din   <= h_din;
                    o_be    <= w_issue ? h_be : 8'hFF;
                end
            end else if (w_issue || rd_take) begin
                sp_v    <= 1'b1;
            end
            // the spare's fields load whenever it is empty and are used only once sp_v is set, so
            // only sp_v waits on rd_take (a client's live request; into all of them -1.2 ns)
            if (acc) begin
                sp_we   <= w_issue;
                sp_addr <= w_issue ? h_addr : {4'b0011, c_addr[gnt][27:3]};
                sp_din  <= h_din;
                sp_be   <= w_issue ? h_be : 8'hFF;
            end
            if (rd_take) begin
                q[q_w[6:0]] <= gnt;
                q_w <= q_w + 8'd1;
            end
            if (DDRAM_DOUT_READY) q_r <= q_r + 8'd1;
            // a blocked ORD client gives the grant up, so a PRIO client is not stuck behind it
            if (rd_take || !g_rd || g_blk) begin
                gnt   <= nxt;
                g_pri <= PRIO[nxt];
                g_ord <= ORD[nxt];
            end
            asked  <= nxt_any;
            pasked <= nxt_pri;
            oasked <= (reqv & ~ORD) != '0;
        end
    end

endmodule
