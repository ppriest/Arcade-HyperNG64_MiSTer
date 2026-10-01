// SPDX-License-Identifier: GPL-3.0-or-later
//
// HNG64 main bus: the N64 core's VR4300 memory port (rtl/cpu/vr4300/cpu.vhd) to
//   - a 64-bit backing store for RAM, program ROM and BIOS (mem_*), which also feeds cache
//     fills on the clk2x beat bus, and
//   - a 32-bit I/O port (io_*) for everything else, in MAME's convention: word-aligned
//     physical address, big-endian data, be[3] = the byte at addr+0.
//
// Contract (docs/HARDWARE_NOTES.md, "N64 CPU memory port" and byte order):
//   - backing store beats hold bytes in address order, byte k at [8k+7:8k];
//   - a request is a one-cycle mem_request on clk1x; mem_size 001 single, 010 dcache line
//     (2 beats), 100 icache line (4 beats); completion is a rising edge of mem_done;
//   - fills: one-cycle rdram_granted2x on clk2x, then one beat per ddr3_DOUT_READY;
//   - single reads are right-justified into mem_dataRead as the N64 memorymux does.
// clk2x is exactly twice clk1x from the same PLL; the domains exchange toggles and
// registers without synchronisers.

module hng64_bus (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        reset,

    // CPU (clk1x)
    input  logic        mem_request,
    input  logic        mem_rnw,
    input  logic [31:0] mem_address,
    input  logic        mem_req64,
    input  logic  [2:0] mem_size,
    input  logic  [7:0] mem_writeMask,
    input  logic [63:0] mem_dataWrite,
    output logic [63:0] mem_dataRead,
    output logic        mem_done,

    // CPU cache fills (clk2x)
    output logic        rdram_granted2x,
    output logic [63:0] ddr3_DOUT,
    output logic        ddr3_DOUT_READY,

    // Backing store (clk2x): RAM, program ROM, BIOS. Byte address, 8-aligned.
    output logic        st_req,          // one cycle
    output logic        st_we,
    output logic [31:0] st_addr,
    output logic  [2:0] st_beats,        // 1, 2 or 4
    output logic [63:0] st_wdata,
    output logic  [7:0] st_be,
    input  logic        st_rvalid,       // one per beat, in address order
    input  logic [63:0] st_rdata,
    input  logic        st_wdone,

    // I/O (clk1x): everything outside the backing store.
    output logic        io_req,          // one cycle
    output logic        io_we,
    output logic [31:0] io_addr,
    output logic  [3:0] io_be,
    output logic [31:0] io_wdata,
    input  logic        io_ack,          // one cycle; io_rdata valid with it
    input  logic [31:0] io_rdata,

    output logic        err_unmapped64   // never set now: a 64-bit I/O access is two 32-bit ones
);

    // Plain memory in MAME's map, kept in SDRAM or DDR3 by hng64_mainmem, which has the same
    // table. Everything else is a device and goes to the I/O port.
    function automatic logic is_store(input logic [31:0] a);
        return (a < 32'h0100_0000)                              // work RAM, 16 MB
            || (a >= 32'h0400_0000 && a < 32'h0600_0000)        // program ROM
            || (a >= 32'h1FC0_0000 && a < 32'h1FC8_0000)        // BIOS
            || (a >= 32'h2010_0000 && a < 32'h2018_0000)        // tile VRAM
            || (a >= 32'h3010_0000 && a < 32'h3016_0000)        // 3D buffer A
            || (a >= 32'h3020_0000 && a < 32'h3026_0000)        // 3D buffer B
            || (a >= 32'h6020_0000 && a < 32'h6040_0000);       // sound RAM
    endfunction

    function automatic logic [31:0] bswap32(input logic [31:0] v);
        return {v[7:0], v[15:8], v[23:16], v[31:24]};
    endfunction

    // ---------------------------------------------------------------- clk1x side
    logic        req_tgl, done_tgl_1x, done_tgl_q;
    logic        r_rnw, r_req64, r_fill;
    logic [31:0] r_addr;
    logic  [2:0] r_beats;
    logic [63:0] r_wdata;
    logic  [7:0] r_be;
    logic [63:0] beat_1x;        // single-read beat, from clk2x
    logic        busy_io;
    logic        io_second;      // a 64-bit I/O access: the +4 word is on the port
    logic [31:0] io_first;       // its +0 word, read

    // Write data and lanes into beat layout (memorymux.vhd:296-311).
    logic [63:0] wbeat;
    logic  [7:0] wbe;
    always_comb begin
        wbeat = {mem_dataWrite[31:0], mem_dataWrite[63:32]};
        wbe   = {mem_writeMask[3:0], mem_writeMask[7:4]};
        if (!mem_req64) begin
            wbeat = {mem_dataWrite[31:0], mem_dataWrite[31:0]};
            wbe   = mem_address[2] ? {mem_writeMask[3:0], 4'h0} : {4'h0, mem_writeMask[3:0]};
        end
    end

    // Read justification (memorymux.vhd:489-505).
    function automatic logic [63:0] justify(input logic [63:0] b, input logic [2:0] a);
        case (a)
            3'd0: return b;
            3'd1: return {56'd0, b[15:8]};
            3'd2: return {48'd0, b[31:16]};
            3'd3: return {56'd0, b[31:24]};
            3'd4: return {32'd0, b[63:32]};
            3'd5: return {56'd0, b[47:40]};
            3'd6: return {48'd0, b[63:48]};
            default: return {56'd0, b[63:56]};
        endcase
    endfunction

    always_ff @(posedge clk1x) begin
        mem_done       <= 1'b0;
        io_req         <= 1'b0;
        done_tgl_q     <= done_tgl_1x;
        if (reset) begin
            req_tgl        <= 1'b0;
            busy_io        <= 1'b0;
            io_second      <= 1'b0;
            err_unmapped64 <= 1'b0;
        end else begin
            if (mem_request) begin
                r_rnw   <= mem_rnw;
                r_req64 <= mem_req64;
                r_addr  <= mem_address;
                r_wdata <= wbeat;
                r_be    <= wbe;
                r_fill  <= (mem_size != 3'b001);
                r_beats <= (mem_size == 3'b100) ? 3'd4 : (mem_size == 3'b010) ? 3'd2 : 3'd1;
                if (is_store(mem_address)) begin
                    req_tgl <= ~req_tgl;
                end else begin
                    // A 64-bit access (the games read the IO MCU's dual-port RAM with ld) is two
                    // word accesses, +0 then +4, as MAME's 32-bit handlers see it; this is the +0.
                    busy_io   <= 1'b1;
                    io_second <= 1'b0;
                    io_req   <= 1'b1;
                    io_we    <= ~mem_rnw;
                    io_addr  <= {mem_address[31:2], 2'b00};
                    // beat half the access lands in, as big-endian word and lanes
                    io_wdata <= bswap32(mem_address[2] ? wbeat[63:32] : wbeat[31:0]);
                    io_be    <= mem_address[2] ? {wbe[4], wbe[5], wbe[6], wbe[7]}
                                               : {wbe[0], wbe[1], wbe[2], wbe[3]};
                    if (mem_rnw) io_be <= 4'hF;
                end
            end
            if (busy_io && io_ack && r_req64 && !io_second) begin
                // the +0 word is in; issue the +4 word
                io_first  <= io_rdata;
                io_second <= 1'b1;
                io_req    <= 1'b1;
                io_addr   <= {r_addr[31:3], 3'b100};
                io_wdata  <= bswap32(r_wdata[63:32]);
                io_be     <= r_rnw ? 4'hF : {r_be[4], r_be[5], r_be[6], r_be[7]};
            end else if (busy_io && io_ack) begin
                busy_io      <= 1'b0;
                io_second    <= 1'b0;
                mem_done     <= 1'b1;
                mem_dataRead <= r_req64 ? {bswap32(io_rdata), bswap32(io_first)}
                              : justify(r_addr[2] ? {bswap32(io_rdata), 32'd0}
                                                  : {32'd0, bswap32(io_rdata)}, r_addr[2:0]);
            end
            if (done_tgl_1x != done_tgl_q) begin
                mem_done     <= 1'b1;
                mem_dataRead <= justify(beat_1x, r_addr[2:0]);
            end
        end
    end

    // ---------------------------------------------------------------- clk2x side
    typedef enum logic [1:0] {IDLE, WAIT_READ, WAIT_WRITE} state_t;
    state_t      st2;
    logic        req_tgl_2x;
    logic  [2:0] left;

    always_ff @(posedge clk2x) begin
        st_req          <= 1'b0;
        rdram_granted2x <= 1'b0;
        ddr3_DOUT_READY <= 1'b0;
        if (reset) begin
            st2         <= IDLE;
            req_tgl_2x  <= 1'b0;
            done_tgl_1x <= 1'b0;
        end else begin
            case (st2)
                IDLE: if (req_tgl != req_tgl_2x) begin
                    req_tgl_2x <= req_tgl;
                    st_req     <= 1'b1;
                    st_we      <= ~r_rnw;
                    st_addr    <= {r_addr[31:3], 3'b000};
                    st_beats   <= r_beats;
                    st_wdata   <= r_wdata;
                    st_be      <= r_be;
                    left       <= r_beats;
                    if (r_rnw) begin
                        st2 <= WAIT_READ;
                        if (r_fill) rdram_granted2x <= 1'b1;   // beats follow from the next cycle
                    end else begin
                        st2 <= WAIT_WRITE;
                    end
                end
                WAIT_READ: if (st_rvalid) begin
                    beat_1x         <= st_rdata;
                    ddr3_DOUT       <= st_rdata;
                    ddr3_DOUT_READY <= r_fill;
                    left            <= left - 3'd1;
                    if (left == 3'd1) begin
                        st2         <= IDLE;
                        done_tgl_1x <= ~done_tgl_1x;
                    end
                end
                WAIT_WRITE: if (st_wdone) begin
                    st2         <= IDLE;
                    done_tgl_1x <= ~done_tgl_1x;
                end
                default: st2 <= IDLE;
            endcase
        end
    end

endmodule
