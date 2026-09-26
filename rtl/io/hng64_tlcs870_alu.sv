// SPDX-License-Identifier: GPL-3.0-or-later
//
// TLCS-870 ALU and the single-operand transforms, transcribed from MAME's
// src/devices/cpu/tlcs870/tlcs870_ops_helper.cpp.
//
// Combinational: an operand pair and the flags in, the result and the flags out. The sequencer
// in hng64_tlcs870.sv supplies the operands and decides what to do with the result.
//
// Flags are PSW bits: J 0x80, Z 0x40, C 0x20, H 0x10 (tlcs870.h:344-347).
//
// TWO PLACES FOLLOW MAME RATHER THAN THE MANUAL, and both are in docs/MAME_KLUDGES.md:
//
//  * ADD/ADDC/SUB/SUBB end with `is_ZF() ? set_CF() : clear_CF()` under a comment that says
//    "JF is copied from CF" (tlcs870_ops_helper.cpp:280, 318, 355, 388). The manual's table in
//    the same file gives ADD as `C Z C H` - JF from the carry, CF from the carry. MAME instead
//    overwrites the carry with zero-ness and never touches JF. The difference is visible: a
//    `jr` after an add branches on it.
//  * ADDC and SUBB add the carry to the SOURCE operand in 16-bit arithmetic before an 8-bit
//    operation (do_alu_8bit, :531), so `ADDC A,0xff` with the carry set compares against 0x100
//    and sets the carry whatever A holds. Reproduced by keeping the operands 17 bits wide.

module hng64_tlcs870_alu (
    input  logic  [2:0] op,             // 0 ADDC, 1 ADD, 2 SUBB, 3 SUB, 4 AND, 5 XOR, 6 OR, 7 CMP
    input  logic        wide,           // 16-bit operands
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic  [7:0] f_in,
    output logic [15:0] result,
    output logic  [7:0] f_out
);

    localparam logic [7:0] FLAG_J = 8'h80;
    localparam logic [7:0] FLAG_Z = 8'h40;
    localparam logic [7:0] FLAG_C = 8'h20;
    localparam logic [7:0] FLAG_H = 8'h10;

    wire cf_in = |(f_in & FLAG_C);

    // param2 += is_CF() before the add or subtract, at the C type's width, not the operand's
    wire        addc_in = (op == 3'd0 || op == 3'd2) && cf_in;
    wire [16:0] a17 = {1'b0, a};
    wire [16:0] b17 = {1'b0, b} + {16'd0, addc_in};

    wire [16:0] sum  = a17 + b17;
    wire [16:0] diff = a17 - b17;

    wire [15:0] logic_res = (op == 3'd4) ? (a & b) : (op == 3'd5) ? (a ^ b) : (a | b);

    // The carry out is computed by MAME and then thrown away: see the header. Only the
    // zero-ness, which replaces it, and the half carry survive.
    wire [4:0] h_lo = {1'b0, a[3:0]} + {1'b0, b17[3:0]};
    wire [8:0] h_hi = {1'b0, a[7:0]} + {1'b0, b17[7:0]};

    wire add_z = wide ? (sum[15:0] == 16'd0) : (sum[7:0] == 8'd0);
    wire add_h = wide ? h_hi[8] : h_lo[4];

    wire sub_z = wide ? (diff[15:0] == 16'd0) : (diff[7:0] == 8'd0);
    wire sub_h = wide ? (a[7:0] < b17[7:0]) : (a[3:0] < b17[3:0]);

    wire cmp_c = a17 < b17;
    wire cmp_z = wide ? (a == b) : (a[7:0] == b[7:0]);
    wire cmp_h = wide ? (a[7:0] < b[7:0]) : (a[3:0] < b[3:0]);

    wire logic_z = wide ? (logic_res == 16'd0) : (logic_res[7:0] == 8'd0);

    always_comb begin
        result = 16'd0;
        f_out  = f_in;
        case (op)
            3'd0, 3'd1: begin                       // ADDC, ADD
                result = sum[15:0];
                f_out = (f_in & ~(FLAG_Z | FLAG_C | FLAG_H))
                      | (add_z ? FLAG_Z : 8'd0)
                      | (add_h ? FLAG_H : 8'd0)
                      | (add_z ? FLAG_C : 8'd0);    // MAME: CF from ZF, see the header
            end
            3'd2, 3'd3: begin                       // SUBB, SUB
                result = diff[15:0];
                f_out = (f_in & ~(FLAG_Z | FLAG_C | FLAG_H))
                      | (sub_z ? FLAG_Z : 8'd0)
                      | (sub_h ? FLAG_H : 8'd0)
                      | (sub_z ? FLAG_C : 8'd0);    // MAME: CF from ZF, see the header
            end
            3'd4, 3'd5, 3'd6: begin                 // AND, XOR, OR
                result = logic_res;
                f_out = (f_in & ~(FLAG_Z | FLAG_J))
                      | (logic_z ? (FLAG_Z | FLAG_J) : 8'd0);
            end
            default: begin                          // CMP: no result
                f_out = (f_in & ~(FLAG_Z | FLAG_C | FLAG_H | FLAG_J))
                      | (cmp_z ? (FLAG_Z | FLAG_J) : 8'd0)
                      | (cmp_c ? FLAG_C : 8'd0)
                      | (cmp_h ? FLAG_H : 8'd0);
            end
        endcase
    end

endmodule


// The single-operand transforms: handle_SHLC, handle_SHRC, handle_ROLC, handle_RORC,
// handle_DAA, handle_DAS and handle_swap, in the same order as the helper file.
module hng64_tlcs870_shift (
    input  logic  [2:0] op,             // 0 SHLC, 1 SHRC, 2 ROLC, 3 RORC, 4 DAA, 5 DAS, 6 SWAP
    input  logic  [7:0] v,
    input  logic  [7:0] f_in,
    output logic  [7:0] result,
    output logic  [7:0] f_out
);

    localparam logic [7:0] FLAG_J = 8'h80;
    localparam logic [7:0] FLAG_Z = 8'h40;
    localparam logic [7:0] FLAG_C = 8'h20;
    localparam logic [7:0] FLAG_H = 8'h10;

    wire cf_in = |(f_in & FLAG_C);
    wire hf_in = |(f_in & FLAG_H);

    // DAA and DAS are two dependent steps: the low nibble first, then the test on the ALREADY
    // adjusted value (`val > 0x9f`), which is why this is written as two stages.
    wire       daa_lo = (v[3:0] > 4'd9) || hf_in;
    wire [7:0] daa_a  = daa_lo ? (v + 8'h06) : v;
    wire       daa_hi = (daa_a > 8'h9f) || cf_in;
    wire [7:0] daa_r  = daa_hi ? (daa_a + 8'h60) : daa_a;

    wire       das_lo = (v[3:0] > 4'd9) || hf_in;
    wire [7:0] das_a  = das_lo ? (v - 8'h06) : v;
    wire       das_hi = (das_a > 8'h9f) || cf_in;
    wire [7:0] das_r  = das_hi ? (das_a - 8'h60) : das_a;

    logic       c_out;
    logic [7:0] shifted;

    always_comb begin
        result = v;
        f_out  = f_in;
        c_out  = cf_in;
        shifted = v;
        case (op)
            3'd0: begin c_out = v[7]; shifted = {v[6:0], 1'b0}; end            // SHLC
            3'd1: begin c_out = v[0]; shifted = {1'b0, v[7:1]}; end            // SHRC
            3'd2: begin c_out = v[7]; shifted = {v[6:0], cf_in}; end           // ROLC
            3'd3: begin c_out = v[0]; shifted = {cf_in, v[7:1]}; end           // RORC
            default: ;
        endcase
        case (op)
            3'd0, 3'd1, 3'd2, 3'd3: begin
                result = shifted;
                // CF from the bit shifted out, then JF from CF and ZF from the result
                f_out = (f_in & ~(FLAG_C | FLAG_J | FLAG_Z))
                      | (c_out ? (FLAG_C | FLAG_J) : 8'd0)
                      | ((shifted == 8'd0) ? FLAG_Z : 8'd0);
            end
            3'd4: begin                                                        // DAA
                result = daa_r;
                f_out = (f_in & ~(FLAG_H | FLAG_C))
                      | (daa_lo ? FLAG_H : 8'd0) | (daa_hi ? FLAG_C : 8'd0);
            end
            3'd5: begin                                                        // DAS
                result = das_r;
                f_out = (f_in & ~(FLAG_H | FLAG_C))
                      | (das_lo ? FLAG_H : 8'd0) | (das_hi ? FLAG_C : 8'd0);
            end
            default: begin                                                     // SWAP
                result = {v[3:0], v[7:4]};
                f_out  = f_in | FLAG_J;
            end
        endcase
    end

endmodule
