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
    // the loader, the backing store). Clients take replies in order and at any latency. The register
    // is copied for its loads (maxfan): one copy for all of them missed clk2x by 1.05 ns into
    // hng64_video's e_rdata and 0.83 ns into the sprite's row buffer (a10b85c seed 2).
    (* maxfan = 4 *) logic [63:0] c_data_r;
    always_ff @(posedge clk) c_data_r <= DDRAM_DOUT;
    assign c_data = c_data_r;

    // ---- the issue queue -----------------------------------------------------------------------------
    // What goes to the port comes from a two-entry queue of registers, its head picked by a read
    // pointer. So nothing a client computes reaches DDRAM_ADDR, or another client's ready, in the
    // same clock (the first full fit had the geometry engine's decode in front of the HPS port,
    // -9.6 ns): a request is accepted while the queue is not full (acc, from registers). And
    // DDRAM_BUSY, which comes from the HPS's own registers across the chip, moves only the read
    // pointer and the count: as the enable of one issue register's 100 bits it missed clk2x by
    // 0.76 ns (an issue register and a spare before this). Order is kept.
    // An entry keeps the writer's and the reader's fields side by side, and the port picks by the
    // entry's f_we: choosing on the way in put the write-or-read decision (wr_sel, from the held
    // write) in front of 100 bits' selects (1.1 ns over clk2x).
    logic          f_we   [0:1];
    logic   [28:0] f_waddr [0:1];
    logic   [28:0] f_raddr [0:1];
    logic   [63:0] f_din  [0:1];
    logic    [7:0] f_be   [0:1];
    logic    [1:0] f_n;
    logic          f_rp, f_wp;
    // acc is f_n != 2, a register set from f_n's next value: compared, it was in front of every
    // client's take into the held requests (0.46 ns over clk2x, 102 endpoints, bc6546a seed 1)
    logic          acc;
    wire           f_pop = f_n != 2'd0 && !DDRAM_BUSY;

    assign DDRAM_RD   = f_n != 2'd0 && !f_we[f_rp];
    assign DDRAM_WE   = f_n != 2'd0 && f_we[f_rp];
    assign DDRAM_ADDR = f_we[f_rp] ? f_waddr[f_rp] : f_raddr[f_rp];
    assign DDRAM_DIN  = f_din[f_rp];
    assign DDRAM_BE   = f_we[f_rp] ? f_be[f_rp] : 8'hFF;

    // ---- each client's requests, held here ---------------------------------------------------------
    // A client's requests go into two entries of its own (o_h the head, o_t behind it, o_n of them),
    // and the issue queue loads from the heads: from the clients' address logic through the base
    // add and the grant's select into the queue it missed clk2x by up to 1.0 ns (mainmem, the
    // sprite and tile ROM queues, the 3D bridge; 3f20971). A client's ready is its own request and
    // whether its entries are full, a register: with one entry, taken or not, the grant and the
    // room reached every client's queues through it (1.1 ns into the sprite's, a10b85c seed 2).
    // A read costs a clock more.
    logic   [27:3] o_h [0:N-1], o_t [0:N-1];
    logic    [1:0] o_n [0:N-1];
    logic          o_v  [0:N-1];             // o_n != 0
    logic          take [0:N-1];
    logic          push [0:N-1];
    always_comb for (int i = 0; i < N; i++) o_v[i] = o_n[i] != 2'd0;

    // ---- which client: a registered round-robin grant ------------------------------------------------
    // Only the granted client can be taken. The grant moves to the next client asking once its
    // holder is served or stops asking; the picks read the held requests, so no client's decode
    // reaches the grant register (the geometry engine's vertex read missed clk2x by 3.2 ns there).
    logic [IW-1:0] gnt, nxt;
    logic          nxt_any, nxt_pri;

    // round robin as two lowest-set-bit picks: among those above the grant, else among all (the
    // rotating loops it replaces missed clk2x by 1.8 ns into g_pri)
    function automatic logic [IW-1:0] lowest(input logic [N-1:0] v);
        lowest = '0;
        for (int i = N - 1; i >= 0; i--) if (v[i]) lowest = IW'(i);
    endfunction

    logic [N-1:0] reqv, reqp, above;
    always_comb begin
        for (int i = 0; i < N; i++) begin
            reqv[i]  = o_v[i];
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
    wire           g_rd     = o_v[gnt];
    logic          asked;                    // some client asked last clock
    logic          pasked;                   // some PRIO client asked last clock
    // The writer's head is taken into a holding register, refilled in the clock it issues, so
    // the write/read choice is made from registers: from the writer's FIFO through it into every
    // client's ready missed clk2x by 1.9 ns.
    logic          h_v;
    (* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) logic h_urg;  // hng64_3d_bridge
    logic   [28:0] h_addr;
    logic   [63:0] h_din;
    logic    [7:0] h_be;
    // An ORD client's read is not taken while a write is held: the 3D's reads and writes share one
    // ordered queue (hng64_3d_bridge), and a read taken after a held write could be issued before it
    // (a depth line read back stale; g3d_tb, one pixel). Nor does an ORD client's request keep a
    // held write waiting (oasked, the others' requests): it is waiting for that write. And no write
    // is taken while an ORD read is held (o_ord): it was asked for first.
    logic          oasked;
    // A held write gives way to the other readers (a PRIO client asking, or another reader while
    // the writer is not urgent) for one clock at most (wturn): the 3D's reads queue behind its
    // writes (hng64_3d_bridge), so a write held while the video and the CPU kept asking stalled the
    // whole 3D. On the board fatfurwa's intro got through 45 to 91 display-list uploads a second
    // with the port idle 78% of the time (probes D, E), where g3d_tb, which has no other readers,
    // draws f1600's 6 in 1.49 M clk3d clocks (about 400 a second).
    logic          wturn;
    wire           wr_sel   = h_v && (wturn || (!pasked && (h_urg || !oasked || !room)));
    wire           w_issue  = acc && wr_sel;
    wire           rd_ok    = acc && !wr_sel && room;      // registers only
    logic          g_ord;                    // the granted client is in ORD
    wire           g_blk    = g_ord && h_v;  // ... and is held back by a held write
    wire           rd_take  = rd_ok && g_rd && !g_blk;
    logic          o_ord;
    always_comb begin
        o_ord = 1'b0;
        for (int i = 0; i < N; i++) if (ORD[i] && o_v[i]) o_ord = 1'b1;
    end

    assign w_ready = (!h_v || w_issue) && !o_ord;

    always_ff @(posedge clk) begin
        h_urg <= w_urgent;
        wturn <= !reset && h_v && !w_issue;
        if (reset) h_v <= 1'b0;
        else if (w_ready) begin
            h_v    <= w_valid;
            h_addr <= w_addr;
            h_din  <= w_din;
            h_be   <= w_be;
        end else if (w_issue) h_v <= 1'b0;
    end

    always_comb
        for (int i = 0; i < N; i++) begin
            // rd_ok with client i's own room: g_pri is PRIO[gnt], so for the granted client it is
            // the constant PRIO[i] (from g_pri through the room select into every client's queue:
            // 0.81 ns over clk2x, 109 endpoints, f52fa64 seed 2)
            take[i]    = acc && !wr_sel && (PRIO[i] ? room_all : room_np) && (gnt == IW'(i)) && o_v[i]
                         && !(ORD[i] && h_v);
            push[i]    = c_rd[i] && o_n[i] != 2'd2;
            c_ready[i] = push[i];
        end

    always_ff @(posedge clk)
        for (int i = 0; i < N; i++) begin
            if (reset) o_n[i] <= 2'd0;
            else o_n[i] <= o_n[i] + 2'(push[i]) - 2'(take[i]);
            case ({push[i], take[i]})
                2'b10: if (o_n[i] == 2'd0) o_h[i] <= c_addr[i][27:3]; else o_t[i] <= c_addr[i][27:3];
                2'b01: o_h[i] <= o_t[i];
                2'b11: if (o_n[i] == 2'd1) o_h[i] <= c_addr[i][27:3];
                       else begin o_h[i] <= o_t[i]; o_t[i] <= c_addr[i][27:3]; end
                default: ;
            endcase
        end

    // The head's client, held in a register (q_h): from q_r through the queue's select and the
    // compare into every client's valid it missed clk2x by 0.9 ns. It is refreshed every clock,
    // with the next entry when this one is answered; a tag is read clocks after it is written, as
    // no reply comes back that soon after its read.
    logic [IW-1:0] q_h;
    logic    [7:0] q_r1;                     // q_r + 1
    always_ff @(posedge clk) begin
        q_h <= DDRAM_DOUT_READY ? q[q_r1[6:0]] : q[q_r[6:0]];
        for (int i = 0; i < N; i++) c_valid[i] <= !reset && DDRAM_DOUT_READY && (q_h == IW'(i));
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            gnt     <= '0;
            q_w     <= 8'd0;
            q_r     <= 8'd0;
            q_r1    <= 8'd1;
            f_n     <= 2'd0;
            acc     <= 1'b1;
            f_rp    <= 1'b0;
            f_wp    <= 1'b0;
            asked   <= 1'b0;
            pasked  <= 1'b0;
            oasked  <= 1'b0;
            g_pri   <= PRIO[0];
            g_ord   <= ORD[0];
        end else begin
            // the free entry's fields load whenever the queue has room and count only once the
            // write pointer passes them, so only the pointer and count wait on rd_take
            if (acc) begin
                f_we[f_wp]    <= w_issue;
                f_waddr[f_wp] <= h_addr;
                f_raddr[f_wp] <= {4'b0011, o_h[gnt]};
                f_din[f_wp]   <= h_din;
                f_be[f_wp]    <= h_be;
            end
            if (w_issue || rd_take) f_wp <= !f_wp;
            if (f_pop) f_rp <= !f_rp;
            f_n <= f_n + 2'(w_issue || rd_take) - 2'(f_pop);
            acc <= f_n + 2'(w_issue || rd_take) - 2'(f_pop) != 2'd2;
            if (rd_take) begin
                q[q_w[6:0]] <= gnt;
                q_w <= q_w + 8'd1;
            end
            if (DDRAM_DOUT_READY) begin
                q_r  <= q_r1;
                q_r1 <= q_r1 + 8'd1;
            end
            // a blocked ORD client gives the grant up, so a PRIO client is not stuck behind it
            // g_pri without the pick: a PRIO client asking means one is picked, any other asking
            // means a non-PRIO one is, and none means the grant stays (from gnt through the picks
            // into PRIO[nxt] it missed clk2x by 1.1 ns)
            if (rd_take || !g_rd || g_blk) begin
                gnt   <= nxt;
                g_pri <= nxt_pri ? 1'b1 : nxt_any ? 1'b0 : g_pri;
                g_ord <= ORD[nxt];
            end
            asked  <= nxt_any;
            pasked <= nxt_pri;
            oasked <= (reqv & ~ORD) != '0;
        end
    end

endmodule
