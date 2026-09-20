// SPDX-License-Identifier: GPL-3.0-or-later
//
// SDRAM: everything the CPU writes, plus the tile VRAM the video reads every line
// (docs/MEMORY.md). One chip through the vendored controller's three fixed-priority ports:
//
//   port 0  tile VRAM, read by the video engines   -- the only hard deadline here
//   port 1  the CPU: main RAM, sound RAM, BIOS     -- 64-bit granules, byte-enabled writes
//   port 2  the download that fills it             -- load time only
//
// The controller runs one transaction at a time per port and answers with a 64-bit granule, so
// port 0 keeps the last few granules it fetched: a line walks consecutive tile words, two to a
// granule, so every other tile word is already in hand. Four entries, not one, because the four
// tilemap engines take turns on this port and a single entry is evicted by the next engine
// before its owner comes back to it.
//
// Byte order. The controller's granule is four 16-bit words in ascending address order, packed
// low word first, and the download writes the region image byte for byte with the even byte in
// the low lane. A big-endian 32-bit word of the image therefore comes back byte-reversed, which
// is what `swap32` undoes. This is asserted by the bench, not by reasoning: LESSONS_LEARNED is
// explicit that every interleave derived by argument on these cores was wrong.

module hng64_sdram #(
    parameter logic [25:0] VRAM_BASE = 26'h150_0000
) (
    input  logic        clk,
    input  logic        init,           // ~pll_locked: chip initialisation
    input  logic        reset,

    output logic [12:0] SDRAM_A,
    inout  wire  [15:0] SDRAM_DQ,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    output logic  [1:0] SDRAM_BA,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nWE,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_CLK,
    output logic        SDRAM_CKE,

    // tile VRAM, u32 words within the region. The request is held until ready; the reply
    // follows in order, as the video block's ports expect.
    input  logic [16:0] v_addr,
    input  logic        v_rd,
    output logic        v_ready,
    output logic [31:0] v_data,
    output logic        v_valid,

    // the CPU, in bytes. A read returns the 8-byte granule holding c_addr; a write puts the
    // enabled bytes of c_wdata there. Byte k of a granule is bits [8k+7:8k], which is the order
    // the CPU bridge uses (docs/HARDWARE_NOTES.md), so no swapping on this path.
    input  logic [25:0] c_addr,
    input  logic        c_rd,
    input  logic        c_we,
    input  logic [63:0] c_wdata,
    input  logic  [7:0] c_be,
    output logic        c_ready,
    output logic [63:0] c_data,
    output logic        c_valid,

    // download: one 16-bit word at a time, anywhere in the chip
    input  logic [24:0] d_addr,         // 16-bit word address
    input  logic [15:0] d_din,
    input  logic        d_we,
    output logic        d_ready
);

    function automatic [31:0] swap32(input logic [31:0] v);
        swap32 = {v[7:0], v[15:8], v[23:16], v[31:24]};
    endfunction

    // The controller takes a request on the cycle it notices `ack != req`, which is after the
    // toggle, so the address, the data and the write strobes must be held until it does. Driving
    // them straight from a client that has already moved on gives the wrong address.
    logic [25:1] addr0, addr2;
    logic        req0, req2;
    logic        ack0, ack2;
    logic [63:0] dout;
    logic [15:0] d_din_r;
    logic        d_busy;
    logic [25:1] addr1;
    logic [15:0] din1;
    logic        wrl1, wrh1, req1, ack1;
    logic [63:0] dout1;

    sdram u_sdram (
        .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .init(init), .clk(clk),
        .addr0(addr0), .wrl0(1'b0), .wrh0(1'b0), .din0(16'd0),
        .dout0(dout), .req0(req0), .ack0(ack0),
        .addr1(addr1), .wrl1(wrl1), .wrh1(wrh1), .din1(din1),
        .dout1(dout1), .req1(req1), .ack1(ack1),
        .addr2(addr2), .wrl2(d_busy), .wrh2(d_busy), .din2(d_din_r),
        .dout2(), .req2(req2), .ack2(ack2));

    // ---- port 2: download ------------------------------------------------------------------
    // req toggles to start a transaction; it is done when ack has caught up.
    assign d_ready = !d_busy;

    always_ff @(posedge clk) begin
        if (reset) begin
            req2   <= 1'b0;
            d_busy <= 1'b0;
        end else if (!d_busy) begin
            if (d_we) begin
                addr2   <= d_addr;
                d_din_r <= d_din;
                req2    <= ~req2;
                d_busy  <= 1'b1;
            end
        end else if (ack2 == req2) begin
            d_busy <= 1'b0;
        end
    end

    // ---- port 1: the CPU -----------------------------------------------------------------------
    // A read is one transaction. A write is up to four, one per enabled 16-bit lane of the
    // granule, because the controller writes a word at a time.
    typedef enum logic [1:0] { C_IDLE, C_READ, C_WRITE, C_WRITE_W } cstate_t;
    cstate_t cst;
    logic [63:0] c_wdata_r;
    logic  [7:0] c_be_r;
    logic [25:3] c_gran;
    logic  [1:0] c_word;                // which 16-bit lane of the granule is being written

    wire [1:0] c_next = c_word + 2'd1;
    wire       c_lane_on = c_be_r[{c_word, 1'b0}] || c_be_r[{c_word, 1'b1}];

    assign c_ready = (cst == C_IDLE);

    always_ff @(posedge clk) begin
        c_valid <= 1'b0;
        if (reset) begin
            cst  <= C_IDLE;
            req1 <= 1'b0;
            wrl1 <= 1'b0;
            wrh1 <= 1'b0;
        end else begin
            case (cst)
                C_IDLE: if (c_rd || c_we) begin
                    c_gran    <= c_addr[25:3];
                    c_wdata_r <= c_wdata;
                    c_be_r    <= c_be;
                    if (c_rd) begin
                        addr1 <= {c_addr[25:3], 2'b00};
                        wrl1  <= 1'b0;
                        wrh1  <= 1'b0;
                        req1  <= ~req1;
                        cst   <= C_READ;
                    end else begin
                        c_word <= 2'd0;
                        cst    <= C_WRITE;
                    end
                end

                C_READ: if (ack1 == req1) begin
                    c_data  <= dout1;
                    c_valid <= 1'b1;
                    cst     <= C_IDLE;
                end

                C_WRITE: begin
                    if (c_lane_on) begin
                        addr1 <= {c_gran, c_word};
                        din1  <= c_wdata_r[{c_word, 4'd0} +: 16];
                        wrl1  <= c_be_r[{c_word, 1'b0}];
                        wrh1  <= c_be_r[{c_word, 1'b1}];
                        req1  <= ~req1;
                        cst   <= C_WRITE_W;
                    end else if (c_word == 2'd3) begin
                        cst <= C_IDLE;
                    end else begin
                        c_word <= c_next;
                    end
                end

                C_WRITE_W: if (ack1 == req1) begin
                    wrl1 <= 1'b0;
                    wrh1 <= 1'b0;
                    if (c_word == 2'd3) begin
                        cst <= C_IDLE;
                    end else begin
                        c_word <= c_next;
                        cst    <= C_WRITE;
                    end
                end

                default: cst <= C_IDLE;
            endcase
        end
    end

    // ---- port 0: tile VRAM ------------------------------------------------------------------
    wire [25:0] vbyte = VRAM_BASE + {7'd0, v_addr, 2'b00};
    wire [25:3] vgran = vbyte[25:3];

    localparam int WAYS = 4;

    logic [25:3] have [0:WAYS-1];
    logic        have_v [0:WAYS-1];
    logic [63:0] cache [0:WAYS-1];
    logic  [1:0] fill;                  // next entry to replace, round robin
    logic        busy;
    logic [25:3] pend;
    logic        pend_hi;               // which half of the granule the pending request wants

    logic        hit;
    logic [63:0] hit_data;
    always_comb begin
        hit = 1'b0;
        hit_data = 64'd0;
        for (int w = 0; w < WAYS; w++)
            if (have_v[w] && have[w] == vgran) begin
                hit = 1'b1;
                hit_data = cache[w];
            end
    end

    assign v_ready = v_rd && !busy;     // one transaction in flight, hit or miss

    always_ff @(posedge clk) begin
        v_valid <= 1'b0;
        if (reset) begin
            req0 <= 1'b0;
            busy <= 1'b0;
            fill <= 2'd0;
            for (int w = 0; w < WAYS; w++) have_v[w] <= 1'b0;
        end else begin
            if (v_rd && !busy) begin
                pend    <= vgran;
                pend_hi <= vbyte[2];
                if (hit) begin
                    v_data  <= swap32(vbyte[2] ? hit_data[63:32] : hit_data[31:0]);
                    v_valid <= 1'b1;
                end else begin
                    addr0 <= {vgran, 2'b00};
                    req0  <= ~req0;
                    busy  <= 1'b1;
                end
            end else if (busy && ack0 == req0) begin
                cache[fill]  <= dout;
                have[fill]   <= pend;
                have_v[fill] <= 1'b1;
                fill         <= fill + 2'd1;
                v_data  <= swap32(pend_hi ? dout[63:32] : dout[31:0]);
                v_valid <= 1'b1;
                busy    <= 1'b0;
            end
        end
    end

endmodule
