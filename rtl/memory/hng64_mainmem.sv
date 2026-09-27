// SPDX-License-Identifier: GPL-3.0-or-later
//
// The CPU's backing store: `rtl/hng64_bus.sv`'s `st_*` contract met by real memory.
//
// The bridge asks for 1, 2 or 4 beats of 64 bits from a byte address, and expects the beats back
// in address order. Where they come from depends on the address (docs/MEMORY.md):
//
//   0x00000000  16 MB   main RAM        SDRAM 0x0000000
//   0x04000000  32 MB   `gameprg`       DDR3, read only (MAME maps it `nopw`)
//   0x1fc00000  512 KB  `bios`          SDRAM 0x1400000, read only
//   0x20100000  512 KB  tile VRAM       SDRAM 0x1500000, which the video also reads
//   0x30100000  384 KB  3D buffer A     SDRAM 0x1580000
//   0x30200000  384 KB  3D buffer B     SDRAM 0x15e0000
//   0x60200000  2 MB    sound RAM       SDRAM 0x1000000
//
// The last four are plain memory in MAME too (`videoram_w` only marks MAME's own tile cache
// dirty, and `soundram_w`'s word swap is undone by `soundram_r`), so they come through here
// rather than through the I/O port, which would put a second clock crossing in their way.
//
// Beats are issued one at a time to SDRAM, which serves one transaction per port, and pipelined
// to DDR3, which does not. A write to `gameprg` or the BIOS is dropped, as MAME drops it.
//
// Every request to either memory is held until that memory takes it. The SDRAM port can still be
// finishing the previous transaction - a write returns `st_wdone` when the last lane is issued,
// not when it lands - and a request merely pulsed at it then is lost.
//
// Writes are always one beat: the CPU only ever writes with `mem_size` 001 (cache lines are
// filled, not written back, on this path).

module hng64_mainmem #(
    // in SDRAM (docs/MEMORY.md)
    parameter logic [25:0] SND_BASE  = 26'h100_0000,
    parameter logic [25:0] BIOS_BASE = 26'h140_0000,
    parameter logic [25:0] VRAM_BASE = 26'h150_0000,
    parameter logic [25:0] FB1_BASE  = 26'h158_0000,
    parameter logic [25:0] FB2_BASE  = 26'h15e_0000
) (
    input  logic        clk,
    input  logic        reset,

    // where `gameprg` sits in DDR3, from hng64_romcfg: the image is packed per set
    // (docs/MEMORY.md), so this is not a parameter.
    input  logic [27:0] prg_base,

    // from the bridge
    input  logic        st_req,
    input  logic        st_we,
    input  logic [31:0] st_addr,
    input  logic  [2:0] st_beats,
    input  logic [63:0] st_wdata,
    input  logic  [7:0] st_be,
    output logic        st_rvalid,
    output logic [63:0] st_rdata,
    output logic        st_wdone,

    // SDRAM, the CPU's port
    output logic [25:0] s_addr,
    output logic        s_rd,
    output logic        s_we,
    output logic [63:0] s_wdata,
    output logic  [7:0] s_be,
    input  logic        s_ready,
    input  logic [63:0] s_data,
    input  logic        s_valid,

    // DDR3, one client of hng64_ddram
    output logic [27:0] d_addr,
    output logic        d_rd,
    input  logic        d_ready,
    input  logic [63:0] d_data,
    input  logic        d_valid
);

    // Where a store address lives: `prg` for DDR3, else the SDRAM byte address; `ro` drops a
    // write. The bridge only sends addresses in these ranges (hng64_bus.sv, is_store).
    typedef struct packed { logic prg; logic ro; logic [25:0] sd; } map_t;

    function automatic map_t map_of(input logic [31:0] a);
        map_of = '0;
        if (a < 32'h0100_0000)
            map_of.sd = a[25:0];
        else if (a >= 32'h0400_0000 && a < 32'h0600_0000) begin
            map_of.prg = 1'b1;
            map_of.ro  = 1'b1;
        end
        else if (a >= 32'h1fc0_0000 && a < 32'h1fc8_0000) begin
            map_of.ro = 1'b1;
            map_of.sd = BIOS_BASE + {7'd0, a[18:0]};
        end
        else if (a >= 32'h2010_0000 && a < 32'h2018_0000)
            map_of.sd = VRAM_BASE + {7'd0, a[18:0]};
        else if (a >= 32'h3010_0000 && a < 32'h3016_0000)
            map_of.sd = FB1_BASE + {7'd0, a[18:0]};
        else if (a >= 32'h3020_0000 && a < 32'h3026_0000)
            map_of.sd = FB2_BASE + {7'd0, a[18:0]};
        else if (a >= 32'h6020_0000 && a < 32'h6040_0000)
            map_of.sd = SND_BASE + {5'd0, a[20:0]};
        else
            map_of.ro = 1'b1;
    endfunction

    map_t req_map;                          // decides the state on a new request
    assign req_map = map_of(st_addr);

    typedef enum logic [1:0] { M_IDLE, M_SDRAM, M_DDR, M_WRITE } state_t;
    state_t st;

    logic [31:0] addr;
    logic  [2:0] left;                  // beats still to ask for
    logic  [2:0] due;                   // beats still to come back
    logic        to_ddr;
    logic        ro;                    // read-only region: swallow the write
    logic        inflight;              // an SDRAM beat has been asked for and not answered

    // from the LATCHED address, which advances a beat at a time; the request's own address may
    // have moved on
    map_t cur_map;
    assign cur_map = map_of(addr);

    assign s_addr  = cur_map.sd;
    assign s_wdata = st_wdata;
    assign s_be    = st_be;
    // gameprg is 0x04000000-0x05ffffff, so the offset into it is the low 25 bits
    assign d_addr  = prg_base + {3'd0, addr[24:0]};

    always_ff @(posedge clk) begin
        st_rvalid <= 1'b0;
        st_wdone  <= 1'b0;
        s_rd      <= 1'b0;
        s_we      <= 1'b0;
        d_rd      <= 1'b0;
        if (reset) begin
            st <= M_IDLE;
        end else begin
            case (st)
                M_IDLE: if (st_req) begin
                    addr   <= st_addr;
                    left   <= st_beats;
                    due    <= st_beats;
                    to_ddr <= req_map.prg;
                    ro     <= req_map.ro;
                    inflight <= 1'b0;
                    if (st_we)             st <= M_WRITE;
                    else if (req_map.prg)  st <= M_DDR;
                    else                   st <= M_SDRAM;
                end

                // one transaction at a time: ask for the next beat only once the last reply is
                // in, and hold the request until the port takes it
                M_SDRAM: begin
                    // the address only advances when a beat comes back, so the next one is not
                    // asked for until then
                    if (left != 3'd0 && !inflight) s_rd <= 1'b1;
                    if (s_rd && s_ready) begin
                        s_rd     <= 1'b0;
                        left     <= left - 3'd1;
                        inflight <= 1'b1;
                    end
                    if (s_valid) begin
                        st_rvalid <= 1'b1;
                        st_rdata  <= s_data;
                        due       <= due - 3'd1;
                        inflight  <= 1'b0;
                        if (due == 3'd1) st <= M_IDLE;
                        else             addr <= addr + 32'd8;
                    end
                end

                // DDR3 takes requests as fast as it will accept them and answers in order, so
                // the whole line is asked for before the first beat arrives
                M_DDR: begin
                    if (left != 3'd0) d_rd <= 1'b1;
                    if (d_rd && d_ready) begin
                        left <= left - 3'd1;
                        addr <= addr + 32'd8;
                        if (left == 3'd1) d_rd <= 1'b0;
                    end
                    if (d_valid) begin
                        st_rvalid <= 1'b1;
                        st_rdata  <= d_data;
                        due       <= due - 3'd1;
                        if (due == 3'd1) st <= M_IDLE;
                    end
                end

                // only main RAM is writable; elsewhere the write is swallowed and acknowledged
                M_WRITE: begin
                    if (ro) begin
                        st_wdone <= 1'b1;
                        st       <= M_IDLE;
                    end else begin
                        s_we <= 1'b1;
                        if (s_we && s_ready) begin
                            s_we     <= 1'b0;
                            st_wdone <= 1'b1;
                            st       <= M_IDLE;
                        end
                    end
                end

                default: st <= M_IDLE;
            endcase
        end
    end

endmodule
