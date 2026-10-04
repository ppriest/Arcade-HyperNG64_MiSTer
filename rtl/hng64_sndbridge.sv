// SPDX-License-Identifier: GPL-3.0-or-later
//
// The sound board's bridge to the ARM process (sw/hng64snd, docs/ROADMAP.md Phase 4). The V53A
// and the L7A1045 run there; this side carries what the main CPU gives them, and their replies.
//
// The shared block is at SHM in the core's DDR3 window (0x3F200000 to the ARM), little-endian
// 64-bit words:
//
//   +0x00     "HNGS" (bytes 0-3), version (4-7)                     FPGA, once after reset
//   +0x08     the sample ROM: DDR3 offset (bytes 0-3), size (4-7)    FPGA, once
//   +0x10     main latch 0 (0-1), main latch 1 (2-3), interrupt-5    FPGA, on every change
//             writes (4-5), sound CPU enables (6-7)
//   +0x18     bit 0: the sound CPU runs (0x55AA last, not 0xAA55)    FPGA, on every change
//   +0x40     sound latch 0 (0-1) and 1 (2-3); flags (4-5): byte 5   the process
//             0xA5, bit 0 the process runs the V53A; heartbeat (6-7)
//   +0x10000  sound RAM, 2 MB, as the V53A sees it                   FPGA, every main-CPU write
//
// The main CPU's sound RAM writes are copied as hng64_mainmem takes them: a beat's lanes are in
// address order, as DDR3's are, so the copy is byte for byte. The +0x10 word, whose enable count
// tells the process to start, goes out only once the copy's queue is empty: one writer, in order,
// so the process never reads a sound RAM older than the enable.
//
// The process's word is read every POLL clocks. Once the sound CPU is enabled, its replies stand
// in the mailbox while its heartbeat moved in the last LIVE polls, whether or not it has started
// its V53A yet: until then its latches read 0, as MAME's V53A held in reset leaves them, and the
// game waits. The stand-in's "ready" there let the game raise interrupt 5 while the V53A set up
// its ICU, and the line stayed high with no edge left to see (docs/HACKS.md). Without a process,
// hng64_io's stand-in answers, as before the process existed. DDR3 is not cleared between cores,
// so the flags carry 0xA5 and the first read only primes the heartbeat.

module hng64_sndbridge #(
    parameter logic [27:0] SHM  = 28'hF200000,
    parameter int          POLL = 1024,         // clk2x clocks between reads of the status word
    parameter int          LIVE = 12207         // polls in 0.1 s at 125 MHz
) (
    input  logic        clk,                    // clk2x
    input  logic        reset,

    input  logic        cfg_valid,
    input  logic [27:0] smp_base,
    input  logic [27:0] smp_size,

    // the main CPU's backing-store requests (hng64_mainmem's st_*)
    input  logic        st_req,
    input  logic        st_we,
    input  logic [31:0] st_addr,
    input  logic [63:0] st_wdata,
    input  logic  [7:0] st_be,

    // hng64_io's mailbox, clk1x registers; irq and en are one clk1x clock, two of these
    input  logic [15:0] main0,
    input  logic [15:0] main1,
    input  logic        irq,
    input  logic        en,
    input  logic [15:0] en_cmd,

    // to hng64_io: the process's replies, and whether to use them
    output logic        live,
    output logic [15:0] rep0,
    output logic [15:0] rep1,

    // DDR3: a write queue head (byte offsets in the core's window) and a read client
    output logic [27:0] w_addr,
    output logic [63:0] w_data,
    output logic  [7:0] w_be,
    output logic        w_valid,
    input  logic        w_ready,
    output logic [27:0] r_addr,
    output logic        r_rd,
    input  logic        r_ready,
    input  logic        r_valid,
    input  logic [63:0] r_data,

    output logic        dbg_overflow            // a sound RAM write found the queue full
);

    localparam logic [27:0] OFF_MAGIC = 28'h00, OFF_SMP = 28'h08, OFF_MBOX = 28'h10,
                            OFF_RUN = 28'h18, OFF_STATUS = 28'h40, OFF_RAM = 28'h10000;

    // ---- the sound RAM copy: a queue of beats --------------------------------------------------
    // The queue's RAM is read a clock ahead, at the pointer it will have, so its head is ready
    // every clock; an entry counts as there once it was written a clock before its read.
    localparam int QW = 8;                      // 256 beats
    logic [89:0] q_mem [0:(1 << QW) - 1];       // {beat index (18), be, data}
    logic [QW:0] q_wp, q_wp_d, q_rp;
    logic [89:0] q_head;
    wire         q_full  = (q_wp - q_rp) == (QW + 1)'(1 << QW);
    wire         q_empty = q_wp == q_rp;
    wire         head_ok = q_wp_d != q_rp;
    wire         snd_wr  = st_req && st_we && st_addr >= 32'h6020_0000 && st_addr < 32'h6040_0000;

    // the one output, a register stage: the copy first, then the words
    wire         out_free = !w_valid || w_ready;
    wire         pop      = out_free && head_ok;
    wire [QW:0]  q_rp_n   = q_rp + (QW + 1)'(pop);

    always_ff @(posedge clk) begin
        if (snd_wr && !q_full) q_mem[q_wp[QW-1:0]] <= {st_addr[20:3], st_be, st_wdata};
        q_head <= q_mem[q_rp_n[QW-1:0]];
    end

    // ---- the mailbox, from clk1x --------------------------------------------------------------------
    logic irq_q, en_q;
    wire  irq_rise = irq && !irq_q;
    wire  en_rise  = en && !en_q;

    logic [15:0] irq_cnt, en_cnt;
    logic        running;
    logic [15:0] main0_q, main1_q;
    logic        d_magic, d_smp, d_mbox, d_run;     // words owed to DDR3

    // what changes a word this clock; one going out this clock is owed again if its word changed
    wire en_run  = en_rise && en_cmd == 16'h55AA;
    wire en_hold = en_rise && en_cmd == 16'hAA55;
    wire c_mbox  = main0 != main0_q || main1 != main1_q || irq_rise || en_run;
    wire c_run   = en_run || en_hold;

    always_ff @(posedge clk) begin
        if (reset) begin
            q_wp <= '0; q_wp_d <= '0; q_rp <= '0;
            irq_q <= 1'b0; en_q <= 1'b0;
            irq_cnt <= '0; en_cnt <= '0; running <= 1'b0;
            main0_q <= '0; main1_q <= '0;
            d_magic <= 1'b1; d_smp <= 1'b1; d_mbox <= 1'b1; d_run <= 1'b1;
            w_valid <= 1'b0;
            dbg_overflow <= 1'b0;
        end else begin
            irq_q <= irq;
            en_q  <= en;

            if (snd_wr) begin
                if (q_full) dbg_overflow <= 1'b1;
                else        q_wp <= q_wp + 1'd1;
            end
            q_wp_d <= q_wp;
            q_rp   <= q_rp_n;

            main0_q <= main0;
            main1_q <= main1;
            if (irq_rise) irq_cnt <= irq_cnt + 1'd1;
            // MAME's soundcpu_enable_w: 0x55AA releases the V53A from reset, 0xAA55 holds it
            if (en_run) begin
                en_cnt  <= en_cnt + 1'd1;
                running <= 1'b1;
            end
            if (en_hold) running <= 1'b0;
            if (c_mbox) d_mbox <= 1'b1;
            if (c_run)  d_run  <= 1'b1;

            // a word goes out only once every beat before it has: the queue is empty, and the
            // stage holds nothing but what is loaded behind its last beat
            if (out_free) begin
                w_valid <= 1'b0;
                w_be    <= 8'hFF;
                if (head_ok) begin
                    w_addr  <= SHM + OFF_RAM + {7'd0, q_head[89:72], 3'd0};
                    w_be    <= q_head[71:64];
                    w_data  <= q_head[63:0];
                    w_valid <= 1'b1;
                end else if (q_empty && cfg_valid && d_magic) begin
                    w_addr  <= SHM + OFF_MAGIC;
                    w_data  <= {32'd1, "S", "G", "N", "H"};       // "HNGS" in bytes 0-3, version 1
                    w_valid <= 1'b1;
                    d_magic <= 1'b0;
                end else if (q_empty && cfg_valid && d_smp) begin
                    w_addr  <= SHM + OFF_SMP;
                    w_data  <= {4'd0, smp_size, 4'd0, smp_base};
                    w_valid <= 1'b1;
                    d_smp   <= 1'b0;
                end else if (q_empty && d_mbox) begin
                    w_addr  <= SHM + OFF_MBOX;
                    w_data  <= {en_cnt, irq_cnt, main1, main0};
                    w_valid <= 1'b1;
                    d_mbox  <= c_mbox;
                end else if (q_empty && d_run) begin
                    w_addr  <= SHM + OFF_RUN;
                    w_data  <= {63'd0, running};
                    w_valid <= 1'b1;
                    d_run   <= c_run;
                end
            end
        end
    end

    // ---- the process's word -------------------------------------------------------------------------
    logic [$clog2(POLL)-1:0] poll_t;
    logic                    r_wait;
    logic [15:0]             hb;
    logic [$clog2(LIVE+1)-1:0] age;
    logic                    p_runs, primed;

    assign r_addr = SHM + OFF_STATUS;

    always_ff @(posedge clk) begin
        if (reset) begin
            poll_t <= '0; r_rd <= 1'b0; r_wait <= 1'b0;
            hb <= '0; age <= ($clog2(LIVE+1))'(LIVE); p_runs <= 1'b0; primed <= 1'b0;
            rep0 <= '0; rep1 <= '0; live <= 1'b0;
        end else begin
            poll_t <= poll_t + 1'd1;
            if (poll_t == '0 && !r_rd && !r_wait) r_rd <= 1'b1;
            if (r_rd && r_ready) begin
                r_rd   <= 1'b0;
                r_wait <= 1'b1;
            end
            if (r_valid) begin
                r_wait <= 1'b0;
                rep0   <= r_data[15:0];
                rep1   <= r_data[31:16];
                p_runs <= r_data[47:40] == 8'hA5;
                hb     <= r_data[63:48];
                primed <= 1'b1;
                if (primed && r_data[63:48] != hb) age <= '0;
                else if (age != ($clog2(LIVE+1))'(LIVE)) age <= age + 1'd1;
            end
            live <= running && p_runs && age != ($clog2(LIVE+1))'(LIVE);
        end
    end

endmodule
