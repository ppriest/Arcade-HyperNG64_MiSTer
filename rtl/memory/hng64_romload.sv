// SPDX-License-Identifier: GPL-3.0-or-later
//
// The start-up copy of `bios` from DDR3 into SDRAM (docs/MEMORY.md).
//
// The HPS writes the whole ROM image into DDR3 (`<rom index="0" address="0x30000000">`), so the
// core never sees those bytes on the ioctl port. Everything the CPU reads at run time is served
// from DDR3 except the BIOS, which shares the SDRAM port with main RAM so that the reset vector
// and the boot code do not compete with the video for DDR3 in the first frames. This copies it.
//
// It is one granule at a time on purpose: the SDRAM download port writes a 16-bit word per
// transaction, so four writes cost far more than one DDR3 read and there is nothing to gain from
// keeping reads in flight. 1 MB is 512K words, milliseconds, once.
//
// Byte order: a DDR3 granule holds byte k at bits [8k+7:8k], and the SDRAM download port takes a
// 16-bit word with the even byte in the low lane, so word k of a granule goes straight to word
// address (byte_addr >> 1) + k. This is asserted by sim/romload_tb, not by reasoning.
//
// The core is held in reset while `active` is high; `done` sticks so an OSD reset does not
// recopy (the sibling cores' `ldr_done`, see the skill's ddr_rom_loading.md).

module hng64_romload #(
    parameter logic [25:0] DST_BASE = 26'h140_0000      // where the BIOS lives in SDRAM
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        start,          // one pulse, once the image is in DDR3
    input  logic [27:0] src_base,       // from hng64_romcfg
    input  logic [27:0] src_size,
    output logic        active,
    output logic        done,

    // one client of hng64_ddram
    output logic [27:0] d_addr,
    output logic        d_rd,
    input  logic        d_ready,
    input  logic [63:0] d_data,
    input  logic        d_valid,

    // the SDRAM download port
    output logic [24:0] s_addr,         // 16-bit word address
    output logic [15:0] s_din,
    output logic        s_we,
    input  logic        s_ready
);

    typedef enum logic [1:0] { L_IDLE, L_RD, L_RDW, L_WR } state_t;
    state_t st;

    logic [27:0] src, left;
    logic [24:0] dst;
    logic [63:0] gran;
    logic  [1:0] word;

    assign active = (st != L_IDLE);
    assign d_addr = src;

    always_ff @(posedge clk) begin
        d_rd <= 1'b0;
        s_we <= 1'b0;
        if (reset) begin
            st   <= L_IDLE;
            done <= 1'b0;
        end else begin
            case (st)
                L_IDLE: if (start && !done) begin
                    src  <= src_base;
                    left <= src_size;
                    dst  <= DST_BASE[25:1];
                    st   <= (src_size == 28'd0) ? L_IDLE : L_RD;
                    done <= (src_size == 28'd0);
                end

                // the request is held until the transport takes it
                L_RD: begin
                    d_rd <= 1'b1;
                    if (d_rd && d_ready) begin
                        d_rd <= 1'b0;
                        st   <= L_RDW;
                    end
                end

                L_RDW: if (d_valid) begin
                    gran <= d_data;
                    word <= 2'd0;
                    st   <= L_WR;
                end

                // four 16-bit writes; the port takes one when s_ready
                L_WR: begin
                    s_we  <= 1'b1;
                    s_din <= gran[{word, 4'd0} +: 16];
                    if (s_we && s_ready) begin
                        s_we <= 1'b0;
                        dst  <= dst + 25'd1;
                        word <= word + 2'd1;
                        if (word == 2'd3) begin
                            src  <= src + 28'd8;
                            left <= left - 28'd8;
                            if (left <= 28'd8) begin
                                st   <= L_IDLE;
                                done <= 1'b1;
                            end else begin
                                st <= L_RD;
                            end
                        end
                    end
                end

                default: st <= L_IDLE;
            endcase
        end
    end

    assign s_addr = dst;

endmodule
