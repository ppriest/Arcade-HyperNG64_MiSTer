// SPDX-License-Identifier: GPL-3.0-or-later
//
// Toshiba TLCS-870 (TMP87PH40AN), the HNG64's IO MCU. Transcribed from MAME's
// src/devices/cpu/tlcs870/, which is the accuracy reference: where MAME and the Toshiba manual
// disagree this follows MAME, and each place is in docs/MAME_KLUDGES.md.
//
// SHAPE
// -----
// MAME executes an instruction atomically and charges it a cycle count (`m_cycles`, one tick of
// the 8 MHz clock). This does the same: a microsequencer runs at the core clock and takes as
// many steps as the work needs, and the instruction retires only once `cycles` ticks of `ce`
// have passed since its fetch began. Instruction boundaries therefore land where MAME's do,
// which is what decides when an interrupt is taken. `dbg_overrun` fires if an instruction needs
// more core clocks than its budget allows: on clk1x (62.5 MHz) there are 7.8 clocks a tick and
// sim/iomcu_tb runs without one at 5, but a silent overrun would be a timing difference nothing
// else would show.
//
// BUS TIMING - THE ONE RULE TO KEEP IN MIND
// -----------------------------------------
// The port's outputs are registered, so a request set up on step S is on the port during S+1 and
// its data is on `din` during S+2. Every read below is written as "issue at S, use at S+2", and
// back-to-back issues pipeline: reads at S and S+1 give their bytes at S+2 and S+3.
//
// REGISTERS ARE MEMORY
// --------------------
// `get_reg8` is `intram[(RBS & 0xf) * 8 + (reg & 7)]` (tlcs870_ops_helper.cpp:17) and intram is
// mapped at 0x0040, so register r of bank RBS is the byte at 0x0040 + RBS*8 + r and the program
// can reach it as ordinary RAM. Register access goes through the same port, not a separate file.
//
// This module owns the SFRs that are CPU state rather than peripheral state - EIR (0x3a/0x3b),
// IL (0x3c/0x3d) and PSW/RBS (0x3f) - and answers them itself. Everything else leaves the port.
//
// A read of an I/O port normally sees the pins, but MAME clears `m_read_input_port` in a set of
// read-modify-write handlers so that they see the port's output latch instead (tlcs870.cpp:140).
// `mem_latch` marks those reads. They are: SET/CLR (x).b; CLR/CPL (pp).g; and from the source
// prefix XCH, SET/CLR/CPL (src).b, LD (src).b,CF and every ALUOP (src) form except CMP. SET
// (pp).g and LD (pp).g,CF read the pins, as MAME's do.
//
// All three prefix families are implemented: source (0xe0-0xe7), register (0xe8-0xef) and
// destination (0xf0-0xf7). An opcode with no handler raises `dbg_unimpl` and sim/iomcu_tb
// names the pair that did it.

module hng64_tlcs870 (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce,             // one pulse per MCU clock

    output logic [15:0] mem_addr,
    output logic        mem_rd,
    output logic        mem_we,
    output logic        mem_latch,      // with mem_rd: a port read sees the output latch
    output logic  [7:0] mem_wdata,
    input  logic  [7:0] mem_rdata,      // valid the clock after mem_rd

    input  logic [15:0] irq,            // level per IL bit; a rising edge latches

    // per-instruction export, for sim/iomcu_tb
    output logic        dbg_fetch,      // one clock, as an instruction's opcode arrives
    output logic [15:0] dbg_pc,         // that instruction's address
    output logic  [7:0] dbg_op,
    output logic  [7:0] dbg_op1,
    output logic        dbg_unimpl,     // sticky: an opcode this does not implement
    output logic        dbg_overrun,    // sticky: an instruction outran its cycle budget
    output logic [15:0] dbg_sp,
    output logic  [3:0] dbg_rbs,
    output logic  [7:0] dbg_f
);

    localparam logic [7:0] FLAG_J = 8'h80;
    localparam logic [7:0] FLAG_Z = 8'h40;
    localparam logic [7:0] FLAG_C = 8'h20;
    localparam logic [7:0] FLAG_H = 8'h10;

    localparam logic [2:0] REG_A = 3'd0, REG_W = 3'd1, REG_C = 3'd2, REG_L = 3'd6, REG_H = 3'd7;

    // ---- state ---------------------------------------------------------------------------------
    logic [15:0] pc;                    // MAME's m_addr: advances through the operand bytes
    logic [15:0] tmppc;                 // the instruction's own address, the base for branches
    logic [15:0] sp;
    logic  [7:0] f;
    logic  [3:0] rbs;
    logic [15:0] eir, il, irq_d;

    logic  [7:0] op0, op1;
    logic  [7:0] pimm;                  // a prefix's own address immediate, (x) or (HL+d)
    logic  [7:0] imm0, imm1, imm2;
    logic  [1:0] imm_need, imm_got;
    logic  [4:0] cycles;
    logic  [7:0] elapsed;
    logic  [5:0] step;
    logic [15:0] ea;
    logic  [7:0] tmp8;
    logic [15:0] tmp16;
    logic [15:0] acc;                   // MUL/DIV accumulator
    logic  [7:0] mcnt;

    typedef enum logic [3:0] { P_RESET, P_FETCH, P_PFX, P_EA, P_IMM, P_EXEC, P_PACE,
                               P_INT } phase_t;
    phase_t ph;

    assign dbg_sp  = sp;
    assign dbg_rbs = rbs;
    assign dbg_f   = f;
    assign dbg_op  = op0;
    assign dbg_op1 = op1;

    // ---- ALU: operands are registered, the result is valid the next step -----------------------
    logic  [2:0] alu_op;
    logic        alu_wide;
    logic [15:0] alu_a, alu_b;
    logic [15:0] alu_r;
    logic  [7:0] alu_f;

    hng64_tlcs870_alu u_alu (.op(alu_op), .wide(alu_wide), .a(alu_a), .b(alu_b), .f_in(f),
                             .result(alu_r), .f_out(alu_f));

    logic  [2:0] sh_op;
    logic  [7:0] sh_v;
    logic  [7:0] sh_r, sh_f;

    hng64_tlcs870_shift u_shift (.op(sh_op), .v(sh_v), .f_in(f), .result(sh_r), .f_out(sh_f));

    // ---- the memory port, and the SFRs this module answers itself ------------------------------
    logic [15:0] a_q;
    logic        rd_q, we_q, latch_q;
    logic  [7:0] wd_q;
    logic        sfr_rd;
    logic  [7:0] sfr_val;

    assign mem_addr  = a_q;
    assign mem_wdata = wd_q;

    function automatic logic own_sfr(input logic [15:0] a);
        own_sfr = (a == 16'h003a) || (a == 16'h003b) || (a == 16'h003c)
               || (a == 16'h003d) || (a == 16'h003f);
    endfunction

    assign mem_rd    = rd_q && !own_sfr(a_q);
    assign mem_we    = we_q && !own_sfr(a_q);
    assign mem_latch = latch_q;

    wire [7:0] din = sfr_rd ? sfr_val : mem_rdata;
    wire [7:0] psw = {f[7:4], rbs};

    function automatic logic [15:0] reg8_addr(input logic [3:0] bank, input logic [2:0] r);
        reg8_addr = 16'h0040 + {9'd0, bank, 3'd0} + {13'd0, r};
    endfunction

    wire [2:0] op_r  = op0[2:0];
    wire [1:0] op_rr = op0[1:0];
    wire [2:0] op_b  = op0[2:0];

    wire [15:0] ra_a   = reg8_addr(rbs, REG_A);
    wire [15:0] ra_w   = reg8_addr(rbs, REG_W);
    wire [15:0] ra_c   = reg8_addr(rbs, REG_C);
    wire [15:0] ra_r   = reg8_addr(rbs, op_r);
    wire [15:0] ra_hl0 = reg8_addr(rbs, REG_L);
    wire [15:0] ra_hl1 = reg8_addr(rbs, REG_H);
    wire [15:0] ra_rr0 = reg8_addr(rbs, {op_rr, 1'b0});
    wire [15:0] ra_rr1 = reg8_addr(rbs, {op_rr, 1'b1});

    wire [7:0]  bitmask = 8'd1 << op_b;
    wire [15:0] imm0_a  = {8'd0, imm0};

    // The prefix families name a register in the PREFIX byte - g = op0[2:0] for 8-bit forms,
    // gg = op0[1:0] for 16-bit ones - and a second register or a bit in the byte after it.
    wire        is_pfx = (op0 >= 8'he0) && (op0 <= 8'hf7);
    wire        is_reg_pfx = (op0[7:3] == 5'b11101);
    wire        is_src_pfx = (op0[7:3] == 5'b11100);
    wire  [2:0] alu1 = op1[2:0];
    wire [15:0] ra_g    = reg8_addr(rbs, op0[2:0]);
    wire [15:0] ra_gg0  = reg8_addr(rbs, {op0[1:0], 1'b0});
    wire [15:0] ra_gg1  = reg8_addr(rbs, {op0[1:0], 1'b1});
    wire [15:0] ra_1r   = reg8_addr(rbs, op1[2:0]);
    wire [15:0] ra_1rr0 = reg8_addr(rbs, {op1[1:0], 1'b0});
    wire [15:0] ra_1rr1 = reg8_addr(rbs, {op1[1:0], 1'b1});
    // (pp) is DE for an even second byte and HL for an odd one (tlcs870_ops_reg.cpp:470)
    wire [15:0] ra_pp0  = reg8_addr(rbs, {1'b1, op1[0], 1'b0});
    wire [15:0] ra_pp1  = reg8_addr(rbs, {1'b1, op1[0], 1'b1});
    wire  [7:0] bitmask1 = 8'd1 << op1[2:0];
    wire  [7:0] bitmask_g = 8'd1 << tmp8[2:0];      // a bit position held in a register
    wire        cf = |(f & FLAG_C);

    // get_addr (tlcs870_ops_helper.cpp:118). The mode is the prefix byte's low three bits:
    // 0 (x), 1 (PC+A), 2 (DE), 3 (HL), 4 (HL+d), 5 (HL+C), 6 (HL+), 7 (-HL).
    wire  [2:0] ea_mode = op0[2:0];
    wire        ea_imm  = (ea_mode == 3'd0) || (ea_mode == 3'd4);
    wire        pfx_lead_imm = !is_reg_pfx && ea_imm;
    // where P_EA leaves: after `ea` is computed, and after the (HL+)/(-HL)
    // writeback where there is one
    wire  [5:0] ea_done = (ea_mode == 3'd0) ? 6'd0
                        : (ea_mode == 3'd1) ? 6'd2
                        : (ea_mode == 3'd6 || ea_mode == 3'd7) ? 6'd6 : 6'd4;
    wire [15:0] ra_ea0  = reg8_addr(rbs, (ea_mode == 3'd2) ? 3'd4 : 3'd6);
    wire [15:0] ra_ea1  = reg8_addr(rbs, (ea_mode == 3'd2) ? 3'd5 : 3'd7);

    // get_base_srcdst_cycles (tlcs870.h:366)
    function automatic logic [4:0] base_cycles(input logic [2:0] m);
        case (m)
            3'd0: base_cycles = 5'd1;
            3'd1: base_cycles = 5'd2;
            3'd2, 3'd3: base_cycles = 5'd0;
            3'd4, 3'd5: base_cycles = 5'd2;
            default: base_cycles = 5'd1;
        endcase
    endfunction

    // ---- condition codes (check_jump_condition, tlcs870_ops_helper.cpp:163) --------------------
    function automatic logic cond_met(input logic [2:0] c, input logic [7:0] fl);
        case (c)
            3'd0: cond_met =  |(fl & FLAG_Z);                   // EQ / Z
            3'd1: cond_met = ~|(fl & FLAG_Z);                   // NE / NZ
            3'd2: cond_met =  |(fl & FLAG_C);                   // LT / CS
            3'd3: cond_met = ~|(fl & FLAG_C);                   // GE / CC
            3'd4: cond_met =  |(fl & (FLAG_C | FLAG_Z));        // LE
            3'd5: cond_met = ~|(fl & (FLAG_C | FLAG_Z));        // GT
            3'd6: cond_met =  |(fl & FLAG_J);                   // T
            default: cond_met = ~|(fl & FLAG_J);                // F
        endcase
    endfunction

    // flags for the "JF and ZF both follow zero-ness" pattern the INC/DEC/bit ops use
    function automatic logic [7:0] set_zj(input logic [7:0] fl, input logic z);
        set_zj = (fl & ~(FLAG_Z | FLAG_J)) | (z ? (FLAG_Z | FLAG_J) : 8'd0);
    endfunction

    // ---- decode: operand bytes, and the cycle count each handler's comment gives ---------------
    function automatic logic [1:0] imm_of(input logic [7:0] o);
        casez (o)
            8'h0f:        imm_of = 2'd1;                        // LD RBS, n
            8'b000101??:  imm_of = 2'd2;                        // LD rr, mn
            8'h24:        imm_of = 2'd3;                        // LDW (x), mn
            8'h25, 8'h26, 8'h2c: imm_of = 2'd2;                 // LDW (HL),mn / LD (x),(y) / (x),n
            8'h20, 8'h22, 8'h28, 8'h2a, 8'h2d, 8'h2e: imm_of = 2'd1;
            8'b00110???:  imm_of = 2'd1;                        // LD r, n
            8'b0100????:  imm_of = 2'd1;                        // SET/CLR (x).b
            8'b0111????:  imm_of = 2'd1;                        // ALUOP A,n / A,(x)
            8'b11010???:  imm_of = 2'd1;                        // JR cc, a
            8'b11011???:  imm_of = 2'd1;                        // LD CF, (x).b
            8'hfa, 8'hfc, 8'hfe: imm_of = 2'd2;                 // LD SP,mn / CALL mn / JP mn
            8'hfb, 8'hfd: imm_of = 2'd1;                        // JR a / CALLP n
            default:      imm_of = 2'd0;
        endcase
    endfunction

    function automatic logic [4:0] cycles_of(input logic [7:0] o);
        casez (o)
            8'h00:        cycles_of = 5'd1;
            8'h01:        cycles_of = 5'd3;
            8'h02, 8'h03: cycles_of = 5'd7;
            8'h04, 8'h05: cycles_of = 5'd6;
            8'h06:        cycles_of = 5'd3;
            8'h07:        cycles_of = 5'd2;
            8'h0a, 8'h0b: cycles_of = 5'd2;
            8'h0c, 8'h0d, 8'h0e: cycles_of = 5'd1;
            8'h0f:        cycles_of = 5'd4;
            8'b000100??, 8'b000110??: cycles_of = 5'd2;         // INC rr / DEC rr
            8'b000101??: cycles_of = 5'd3;                      // LD rr, mn
            8'b000111??: cycles_of = 5'd1;                      // SHLC/SHRC/ROLC/RORC A
            8'h20, 8'h28: cycles_of = 5'd5;
            8'h21, 8'h29: cycles_of = 5'd4;
            8'h22, 8'h2a: cycles_of = 5'd3;
            8'h23, 8'h2b, 8'h2f: cycles_of = 5'd2;
            8'h24:        cycles_of = 5'd6;
            8'h25, 8'h26: cycles_of = 5'd5;
            8'h2c, 8'h2e: cycles_of = 5'd4;
            8'h2d:        cycles_of = 5'd3;
            8'b00110???:  cycles_of = 5'd2;                     // LD r, n
            8'b0100????:  cycles_of = 5'd5;                     // SET/CLR (x).b
            8'b0101????, 8'b0110????: cycles_of = 5'd1;         // LD A,r / r,A / INC r / DEC r
            8'b01110???:  cycles_of = 5'd2;                     // ALUOP A, n
            8'b01111???:  cycles_of = 5'd4;                     // ALUOP A, (x)
            8'b10??????, 8'b11010???: cycles_of = 5'd2;         // JRS / JR, before a taken branch
            8'b1100????:  cycles_of = 5'd7;                     // CALLV n
            8'b11011???:  cycles_of = 5'd4;                     // LD CF, (x).b
            8'hfa:        cycles_of = 5'd3;
            8'hfb, 8'hfe: cycles_of = 5'd4;
            8'hfc, 8'hfd: cycles_of = 5'd6;
            8'hff:        cycles_of = 5'd9;
            default:      cycles_of = 5'd1;
        endcase
    endfunction

    // The second byte of a register-prefix op decides the operand bytes and the cycle count
    // (tlcs870_ops_reg.cpp, one line per handler's own comment block).
    function automatic logic [1:0] imm_of_reg(input logic [7:0] o);
        casez (o)
            8'b00111???: imm_of_reg = 2'd2;                     // ALUOP gg, mn
            8'b01110???: imm_of_reg = 2'd1;                     // ALUOP g, n
            default:     imm_of_reg = 2'd0;
        endcase
    endfunction

    function automatic logic [4:0] cycles_of_reg(input logic [7:0] o);
        casez (o)
            8'h01:        cycles_of_reg = 5'd4;                 // SWAP g
            8'h02, 8'h03: cycles_of_reg = 5'd8;                 // MUL gg / DIV gg, C
            8'h04:        cycles_of_reg = 5'd7;                 // RETN
            8'h06:        cycles_of_reg = 5'd5;                 // POP gg
            8'h07:        cycles_of_reg = 5'd4;                 // PUSH gg
            8'h0a, 8'h0b: cycles_of_reg = 5'd3;                 // DAA g / DAS g
            8'b000100??:  cycles_of_reg = 5'd3;                 // XCH rr, gg
            8'b000101??:  cycles_of_reg = 5'd2;                 // LD rr, gg
            8'b000111??:  cycles_of_reg = 5'd2;                 // SHLC/SHRC/ROLC/RORC g
            8'b0011????:  cycles_of_reg = 5'd4;                 // ALUOP WA,gg / gg,mn
            8'b0100????:  cycles_of_reg = 5'd3;                 // SET/CLR g.b
            8'b01011???:  cycles_of_reg = 5'd2;                 // LD r, g
            8'b01100???:  cycles_of_reg = 5'd2;                 // ALUOP A, g
            8'b01101???, 8'b01110???: cycles_of_reg = 5'd3;     // ALUOP g,A / g,n
            8'h9e, 8'h9f: cycles_of_reg = 5'd4;                 // LD CF, (pp).g
            8'h82, 8'h83, 8'h8a, 8'h8b, 8'h92, 8'h93,
            8'h9a, 8'h9b: cycles_of_reg = 5'd5;                 // SET/CLR/CPL/LD (pp).g
            8'b10101???:  cycles_of_reg = 5'd3;                 // XCH r, g
            8'b11000???:  cycles_of_reg = 5'd3;                 // CPL g.b
            8'b11001???, 8'b1101????: cycles_of_reg = 5'd2;     // LD g.b,CF / XOR CF / LD CF
            8'hfa, 8'hfb, 8'hfe: cycles_of_reg = 5'd3;          // LD SP,gg / LD gg,SP / JP gg
            8'hfc:        cycles_of_reg = 5'd6;                 // CALL gg
            default:      cycles_of_reg = 5'd1;                 // illegal
        endcase
    endfunction

    // The destination prefix (tlcs870_ops_dst.cpp) has three operations; anything else is
    // MAME's logged no-op, which costs one cycle and changes nothing.
    function automatic logic [1:0] imm_of_dst(input logic [7:0] o);
        imm_of_dst = (o == 8'h2c) ? 2'd1 : 2'd0;        // LD (dst), n
    endfunction

    function automatic logic [4:0] cycles_of_dst(input logic [2:0] m, input logic [7:0] o);
        casez (o)
            8'b000100??: cycles_of_dst = base_cycles(m) + 5'd4;     // LD (dst), rr
            8'h2c:       cycles_of_dst = base_cycles(m) + 5'd4;     // LD (dst), n
            8'b01011???: cycles_of_dst = base_cycles(m) + 5'd3;     // LD (dst), r
            default:     cycles_of_dst = base_cycles(m) + 5'd1;     // illegal
        endcase
    endfunction

    // The source prefix (tlcs870_ops_src.cpp). Two of its ALU forms charge CMP one cycle MORE
    // than the others, because MAME takes one off when it writes the result back (:534, :630).
    function automatic logic [1:0] imm_of_src(input logic [7:0] o);
        casez (o)
            8'h26, 8'h2f: imm_of_src = 2'd1;                    // LD (x),(src) / MCMP (src),n
            8'b01110???:  imm_of_src = 2'd1;                    // ALUOP (src), n
            default:      imm_of_src = 2'd0;
        endcase
    endfunction

    function automatic logic [4:0] cycles_of_src(input logic [2:0] m, input logic [7:0] o);
        casez (o)
            8'h08, 8'h09: cycles_of_src = base_cycles(m) + 5'd7;    // ROLD / RORD A, (src)
            8'b000101??: cycles_of_src = base_cycles(m) + 5'd4;     // LD rr, (src)
            8'h20, 8'h28: cycles_of_src = base_cycles(m) + 5'd4;    // INC / DEC (src)
            8'h26:       cycles_of_src = base_cycles(m) + 5'd5;     // LD (x), (src)
            8'h27:       cycles_of_src = base_cycles(m) + 5'd4;     // LD (HL), (src)
            8'h2f:       cycles_of_src = base_cycles(m) + 5'd5;     // MCMP (src), n
            8'b0100????: cycles_of_src = base_cycles(m) + 5'd4;     // SET / CLR (src).b
            8'b01011???: cycles_of_src = base_cycles(m) + 5'd3;     // LD r, (src)
            8'b01100???: cycles_of_src = base_cycles(m)
                                       + ((o[2:0] == 3'd7) ? 5'd6 : 5'd5);  // ALUOP (src),(HL)
            8'b01110???: cycles_of_src = base_cycles(m)
                                       + ((o[2:0] == 3'd7) ? 5'd5 : 5'd4);  // ALUOP (src), n
            8'b01111???: cycles_of_src = base_cycles(m) + 5'd3;     // ALUOP A, (src)
            8'b10101???: cycles_of_src = base_cycles(m) + 5'd4;     // XCH r, (src)
            8'b11000???: cycles_of_src = base_cycles(m) + 5'd4;     // CPL (src).b
            8'b11001???: cycles_of_src = base_cycles(m) + 5'd4;     // LD (src).b, CF
            8'b1101????: cycles_of_src = base_cycles(m) + 5'd3;     // XOR CF / LD CF, (src).b
            8'hfc:       cycles_of_src = base_cycles(m) + 5'd8;     // CALL (src)
            8'hfe:       cycles_of_src = base_cycles(m) + 5'd5;     // JP (src)
            default:     cycles_of_src = base_cycles(m) + 5'd1;     // illegal
        endcase
    endfunction

    // ---- interrupts (check_interrupts, tlcs870.cpp:954) ----------------------------------------
    // Priorities 0..2 are non-maskable and MAME does not implement them; 3..15 need EIR bit 0.
    // MAME's loop runs upwards and returns on the first match, so the lowest index wins.
    logic [3:0] int_pri;
    logic       int_pending;

    always_comb begin
        int_pri = 4'd0;
        int_pending = 1'b0;
        for (int p = 15; p >= 3; p--) begin
            if (eir[0] && il[p]) begin
                int_pri = 4'(p);
                int_pending = 1'b1;
            end
        end
    end

    // the JRS displacement is 5 bits signed, the JR one 8; both are added to tmppc + 2
    wire [15:0] jrs_target = tmppc + 16'd2 + {{11{op0[4]}}, op0[4:0]};
    wire [15:0] jr_target  = tmppc + 16'd2 + {{8{imm0[7]}}, imm0};

    // ---- the sequencer --------------------------------------------------------------------------
    logic [15:0] il_n, eir_n;

    task automatic finish;
        ph <= P_PACE;
        step <= 6'd0;
    endtask

    // The bus request is built with blocking assignments into these and registered once, at the
    // end of the process. These are macros rather than tasks because a task that assigns module
    // variables counts as a second driver of them, which buries a real multiple-driver warning
    // among false ones.
    logic [15:0] a_d;
    logic        rd_d, we_d, latch_d;
    logic  [7:0] wd_d;

`define RD(A)     begin a_d = (A); rd_d = 1'b1; end
`define RDX(A, L) begin a_d = (A); rd_d = 1'b1; latch_d = (L); end
`define WR(A, D)  begin a_d = (A); we_d = 1'b1; wd_d = (D); end
`define FIN       begin ph <= P_PACE; step <= 6'd0; end

    always_ff @(posedge clk) begin
        a_d  = 16'd0;
        rd_d = 1'b0;
        we_d = 1'b0;
        wd_d = 8'd0;
        latch_d = 1'b0;
        dbg_fetch <= 1'b0;

        // the reply pipeline: what was on the port last cycle decides what `din` carries now
        sfr_rd  <= rd_q && own_sfr(a_q);
        sfr_val <= (a_q == 16'h003a) ? eir[7:0]
                 : (a_q == 16'h003b) ? eir[15:8]
                 : (a_q == 16'h003c) ? il[7:0]
                 : (a_q == 16'h003d) ? il[15:8]
                 : psw;

        irq_d <= irq;
        il_n  = il | (irq & ~irq_d);            // set_irq_line: a rising edge latches
        eir_n = eir;

        if (we_q && own_sfr(a_q)) begin
            case (a_q)
                16'h003a: eir_n = {eir[15:8], wd_q};
                16'h003b: eir_n = {wd_q, eir[7:0]};
                16'h003c: il_n  = {il[15:8], wd_q};
                // MAME's il_h_w takes the low byte from EIR, not IL (tlcs870.cpp:887); see
                // docs/MAME_KLUDGES.md
                16'h003d: il_n  = {wd_q, eir[7:0]};
                default:  rbs   <= wd_q[3:0];   // rbs_w: the flags cannot be written here
            endcase
        end

        if (ce) elapsed <= elapsed + 8'd1;
        if (ph == P_EXEC && elapsed > {3'd0, cycles} + 8'd2) dbg_overrun <= 1'b1;

        if (reset) begin
            ph <= P_RESET;
            step <= 6'd0;
            sp <= 16'd0;
            f <= 8'd0;
            rbs <= 4'd0;
            eir_n = 16'd0;
            il_n = 16'd0;
            irq_d <= 16'd0;
            elapsed <= 8'd0;
            dbg_unimpl <= 1'b0;
            dbg_overrun <= 1'b0;
        end else begin
            case (ph)
                // device_reset: m_pc = RM16(0xfffe)
                P_RESET: begin
                    step <= step + 6'd1;
                    case (step)
                        6'd0: `RD(16'hfffe)
                        6'd1: `RD(16'hffff)
                        6'd2: tmp8 <= din;
                        default: begin
                            pc <= {din, tmp8};
                            ph <= P_FETCH;
                            step <= 6'd0;
                            elapsed <= 8'd0;
                        end
                    endcase
                end

                // take_interrupt (tlcs870.cpp:982). MAME charges it no cycles.
                P_INT: begin
                    step <= step + 6'd1;
                    case (step)
                        6'd0: `WR(sp, psw)
                        6'd1: `WR(sp - 16'd2, pc[7:0])
                        6'd2: begin `WR(sp - 16'd1, pc[15:8]) sp <= sp - 16'd3; end
                        6'd3: `RD(ea)
                        6'd4: `RD(ea + 16'd1)
                        6'd5: tmp8 <= din;
                        default: begin
                            pc <= {din, tmp8};
                            ph <= P_FETCH;
                            step <= 6'd0;
                            elapsed <= 8'd0;
                        end
                    endcase
                end

                P_FETCH: begin
                    step <= step + 6'd1;
                    case (step)
                        6'd0: begin
                            if (int_pending) begin
                                il_n[int_pri] = 1'b0;
                                eir_n[0] = 1'b0;
                                ea <= 16'hffe0 + {11'd0, ~int_pri, 1'b0};
                                ph <= P_INT;
                                step <= 6'd0;
                            end else begin
                                tmppc <= pc;
                                dbg_pc <= pc;
                                `RD(pc)
                                pc <= pc + 16'd1;
                            end
                        end
                        6'd1: ;
                        default: begin
                            op0 <= din;
                            imm_need <= imm_of(din);
                            imm_got <= 2'd0;
                            cycles <= cycles_of(din);
                            step <= 6'd0;
                            dbg_fetch <= 1'b1;
                            if (din >= 8'he0 && din <= 8'hf7) begin
                                ph <= P_PFX;                    // a prefix: more opcode bytes
                                `RD(pc)
                                pc <= pc + 16'd1;
                            end else begin
                                ph <= (imm_of(din) == 2'd0) ? P_EXEC : P_IMM;
                                if (imm_of(din) != 2'd0) begin
                                    `RD(pc)
                                    pc <= pc + 16'd1;
                                end
                            end
                        end
                    endcase
                end

                // A source or destination prefix whose mode is (x) or (HL+d) carries its
                // address immediate BEFORE the second opcode byte (tlcs870_ops_dst.cpp:38), so
                // that byte is taken first and the opcode read is issued behind it. The second
                // opcode byte therefore lands on step 1 or step 2, and decides the operands and
                // the cycle count.
                P_PFX: begin
                    step <= step + 6'd1;
                    if (pfx_lead_imm) begin
                        if (step == 6'd0) begin `RD(pc) pc <= pc + 16'd1; end
                        if (step == 6'd1) pimm <= din;
                    end
                    if (step == (pfx_lead_imm ? 6'd2 : 6'd1)) begin
                        op1 <= din;
                        imm_got <= 2'd0;
                        step <= 6'd0;
                        if (is_reg_pfx) begin
                            imm_need <= imm_of_reg(din);
                            cycles <= cycles_of_reg(din);
                            ph <= (imm_of_reg(din) == 2'd0) ? P_EXEC : P_IMM;
                            if (imm_of_reg(din) != 2'd0) begin
                                `RD(pc)
                                pc <= pc + 16'd1;
                            end
                        end else begin
                            imm_need <= is_src_pfx ? imm_of_src(din) : imm_of_dst(din);
                            // f1 and f5 are illegal for a destination, and MAME charges the
                            // extra cycle and then runs the opcode anyway (dst.cpp:49)
                            cycles <= is_src_pfx ? cycles_of_src(ea_mode, din)
                                   : (cycles_of_dst(ea_mode, din)
                                      + (((op0 == 8'hf1) || (op0 == 8'hf5)) ? 5'd1 : 5'd0));
                            // the read of any trailing immediate is issued at the END of
                            // P_EA, not here: its reply has to land in P_IMM
                            ph <= P_EA;
                        end
                    end
                end

                // The effective address a source or destination prefix names, shared by both
                // (get_addr, tlcs870_ops_helper.cpp:118). Every mode leaves through `ea_done`,
                // which is a step that makes no bus request of its own, so it can issue the read
                // of a trailing immediate for P_IMM.
                P_EA: begin
                    step <= step + 6'd1;
                    case (ea_mode)
                        3'd0: ea <= {8'd0, pimm};               // (x)
                        3'd1: case (step)                       // (PC+A)
                            6'd0: `RD(ra_a)
                            6'd1: ;
                            default: ea <= tmppc + 16'd2 + {8'd0, din};
                        endcase
                        default: case (step)                    // the register pair forms
                            6'd0: `RD(ra_ea0)
                            6'd1: `RD(ra_ea1)
                            6'd2: begin
                                if (ea_mode == 3'd5) `RD(ra_c)
                                tmp16[7:0] <= din;
                            end
                            6'd3: tmp16[15:8] <= din;
                            6'd4: begin
                                case (ea_mode)
                                    3'd4: ea <= tmp16 + {8'd0, pimm};
                                    3'd5: ea <= tmp16 + {8'd0, din};
                                    3'd6: begin ea <= tmp16; acc <= tmp16 + 16'd1; end
                                    3'd7: begin ea <= tmp16 - 16'd1; acc <= tmp16 - 16'd1; end
                                    default: ea <= tmp16;       // (DE) and (HL)
                                endcase
                                // (HL+) and (-HL) write the moved pointer back
                                if (ea_mode == 3'd6 || ea_mode == 3'd7)
                                    `WR(ra_ea0, (ea_mode == 3'd6) ? (tmp16[7:0] + 8'd1)
                                                                  : (tmp16[7:0] - 8'd1))
                            end
                            6'd5: `WR(ra_ea1, acc[15:8])
                            default: ;
                        endcase
                    endcase
                    if (step == ea_done) begin
                        if (imm_need != 2'd0) begin `RD(pc) pc <= pc + 16'd1; end
                        ph <= (imm_need == 2'd0) ? P_EXEC : P_IMM;
                        step <= 6'd0;
                    end
                end

                // the operand bytes, in the order the handlers READ8() them
                P_IMM: begin
                    step <= step + 6'd1;
                    if (step == 6'd0) begin
                        if (imm_need != 2'd1) begin `RD(pc) pc <= pc + 16'd1; end
                    end else begin
                        case (imm_got)
                            2'd0: imm0 <= din;
                            2'd1: imm1 <= din;
                            default: imm2 <= din;
                        endcase
                        if (imm_got + 2'd1 == imm_need) begin
                            ph <= P_EXEC;
                            step <= 6'd0;
                        end else begin
                            imm_got <= imm_got + 2'd1;
                            if (imm_got + 2'd2 < imm_need) begin
                                `RD(pc) pc <= pc + 16'd1;
                            end
                        end
                    end
                end

                // ---- execute ------------------------------------------------------------------
                // One branch per line of decode() (tlcs870_ops.cpp:17), in the same order.
                P_EXEC: begin
                    step <= step + 6'd1;
                    casez (op0)
                    8'h00: `FIN                                            // NOP

                    8'h01, 8'h0a, 8'h0b: begin                                  // SWAP/DAA/DAS A
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: ;
                            6'd2: begin
                                sh_v <= din;
                                sh_op <= (op0 == 8'h01) ? 3'd6 : (op0 == 8'h0a) ? 3'd4 : 3'd5;
                            end
                            default: begin f <= sh_f; `WR(ra_a, sh_r) `FIN end
                        endcase
                    end

                    8'h02: begin                                                // MUL W, A
                        // handle_mul: the product's high byte decides ZF and JF, and the
                        // registers are written back UNCHANGED (tlcs870_ops_helper.cpp:91), so
                        // only the flags are observable. Shift-and-add, no DSP (WORKFLOW 14).
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: `RD(ra_w)
                            6'd2: tmp8 <= din;                                  // A
                            6'd3: begin tmp16 <= {8'd0, din}; acc <= 16'd0; mcnt <= 8'd0; end
                            default: begin
                                if (mcnt == 8'd8) begin
                                    f <= set_zj(f, acc[15:8] == 8'd0);
                                    `FIN
                                end else begin
                                    if (tmp8[0]) acc <= acc + tmp16;
                                    tmp8  <= {1'b0, tmp8[7:1]};
                                    tmp16 <= {tmp16[14:0], 1'b0};
                                    mcnt  <= mcnt + 8'd1;
                                    step  <= step;                              // stay here
                                end
                            end
                        endcase
                    end

                    8'h03: begin                                                // DIV WA, C
                        // handle_div (tlcs870_ops_helper.cpp:52): WA / C, the quotient's low
                        // byte into A and the remainder into W. Restoring division, 16 steps.
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: `RD(ra_w)
                            6'd2: begin `RD(ra_c) tmp8 <= din; end        // A, the low half
                            6'd3: tmp16 <= {din, 8'd0};                         // W, the high half
                            6'd4: begin
                                tmp16 <= tmp16 | {8'd0, tmp8};                  // WA
                                ea <= {8'd0, din};                              // C
                                acc <= 16'd0;
                                mcnt <= 8'd0;
                            end
                            6'd5: begin
                                if (ea[7:0] == 8'd0) begin
                                    f <= f | FLAG_C;                            // divide by zero
                                    `FIN
                                end else if (mcnt == 8'd16) begin
                                    `WR(ra_a, tmp16[7:0])                       // quotient low
                                end else begin
                                    if ({acc[14:0], tmp16[15]} >= {8'd0, ea[7:0]}) begin
                                        acc <= {acc[14:0], tmp16[15]} - {8'd0, ea[7:0]};
                                        tmp16 <= {tmp16[14:0], 1'b1};
                                    end else begin
                                        acc <= {acc[14:0], tmp16[15]};
                                        tmp16 <= {tmp16[14:0], 1'b0};
                                    end
                                    mcnt <= mcnt + 8'd1;
                                    step <= step;
                                end
                            end
                            default: begin
                                `WR(ra_w, acc[7:0])                             // remainder
                                f <= (f & ~(FLAG_C | FLAG_Z | FLAG_J))
                                   | ((tmp16[15:8] != 8'd0) ? FLAG_C : 8'd0)
                                   | ((acc[7:0] == 8'd0) ? (FLAG_Z | FLAG_J) : 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h04: begin                                                // RETI
                        case (step)
                            6'd0: `RD(sp + 16'd1)
                            6'd1: `RD(sp + 16'd2)
                            6'd2: begin `RD(sp + 16'd3) tmp16[7:0] <= din; end
                            6'd3: tmp16[15:8] <= din;
                            default: begin
                                f <= {din[7:4], 4'd0};
                                rbs <= din[3:0];
                                pc <= tmp16;
                                sp <= sp + 16'd3;
                                eir_n[0] = 1'b1;                                // always re-enabled
                                `FIN
                            end
                        endcase
                    end

                    8'h05: begin                                                // RET
                        case (step)
                            6'd0: `RD(sp + 16'd1)
                            6'd1: `RD(sp + 16'd2)
                            6'd2: tmp8 <= din;
                            default: begin
                                pc <= {din, tmp8};
                                sp <= sp + 16'd2;
                                `FIN
                            end
                        endcase
                    end

                    8'h06: begin                                                // POP PSW
                        case (step)
                            6'd0: `RD(sp + 16'd1)
                            6'd1: ;
                            default: begin
                                f <= {din[7:4], 4'd0};
                                rbs <= din[3:0];
                                sp <= sp + 16'd1;
                                `FIN
                            end
                        endcase
                    end

                    8'h07: begin `WR(sp, psw) sp <= sp - 16'd1; `FIN end   // PUSH PSW

                    8'h0c: begin f <= (f & ~FLAG_C) | FLAG_J; `FIN end     // CLR CF
                    8'h0d: begin f <= (f & ~FLAG_J) | FLAG_C; `FIN end     // SET CF
                    8'h0e: begin                                                // CPL CF
                        f <= |(f & FLAG_C) ? ((f & ~FLAG_C) | FLAG_J)
                                           : ((f & ~FLAG_J) | FLAG_C);
                        `FIN
                    end

                    8'h0f: begin rbs <= imm0[3:0]; f <= f | FLAG_J; `FIN end   // LD RBS, n

                    8'b000100??, 8'b000110??: begin                             // INC rr / DEC rr
                        case (step)
                            6'd0: `RD(ra_rr0)
                            6'd1: `RD(ra_rr1)
                            6'd2: tmp16[7:0] <= din;
                            6'd3: tmp16[15:8] <= din;
                            6'd4: begin
                                ea <= op0[3] ? (tmp16 - 16'd1) : (tmp16 + 16'd1);
                                `WR(ra_rr0, op0[3] ? (tmp16[7:0] - 8'd1) : (tmp16[7:0] + 8'd1))
                            end
                            default: begin
                                `WR(ra_rr1, ea[15:8])
                                // INC: both flags follow zero. DEC: JF follows 0xffff, ZF zero.
                                f <= op0[3]
                                   ? ((f & ~(FLAG_Z | FLAG_J))
                                      | ((ea == 16'hffff) ? FLAG_J : 8'd0)
                                      | ((ea == 16'd0) ? FLAG_Z : 8'd0))
                                   : set_zj(f, ea == 16'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'b000101??: begin                                          // LD rr, mn
                        case (step)
                            6'd0: `WR(ra_rr0, imm0)
                            default: begin `WR(ra_rr1, imm1) f <= f | FLAG_J; `FIN end
                        endcase
                    end

                    8'b000111??: begin                                          // SHLC/SHRC/ROLC/RORC A
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: ;
                            6'd2: begin sh_v <= din; sh_op <= {1'b0, op0[1:0]}; end
                            default: begin f <= sh_f; `WR(ra_a, sh_r) `FIN end
                        endcase
                    end

                    8'h20, 8'h28: begin                                         // INC (x) / DEC (x)
                        case (step)
                            6'd0: `RD(imm0_a)
                            6'd1: ;
                            6'd2: tmp8 <= op0[3] ? (din - 8'd1) : (din + 8'd1);
                            default: begin
                                `WR(imm0_a, tmp8)
                                f <= op0[3]
                                   ? ((f & ~(FLAG_Z | FLAG_J))
                                      | ((tmp8 == 8'hff) ? FLAG_J : 8'd0)
                                      | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0))
                                   : set_zj(f, tmp8 == 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h21, 8'h29: begin                                         // INC/DEC (HL)
                        case (step)
                            6'd0: `RD(ra_hl0)
                            6'd1: `RD(ra_hl1)
                            6'd2: tmp16[7:0] <= din;
                            6'd3: tmp16[15:8] <= din;
                            6'd4: `RD(tmp16)
                            6'd5: ;
                            6'd6: tmp8 <= op0[3] ? (din - 8'd1) : (din + 8'd1);
                            default: begin
                                `WR(tmp16, tmp8)
                                f <= op0[3]
                                   ? ((f & ~(FLAG_Z | FLAG_J))
                                      | ((tmp8 == 8'hff) ? FLAG_J : 8'd0)
                                      | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0))
                                   : set_zj(f, tmp8 == 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h22: begin                                                // LD A, (x)
                        case (step)
                            6'd0: `RD(imm0_a)
                            6'd1: ;
                            default: begin
                                `WR(ra_a, din)
                                f <= (f & ~FLAG_Z) | FLAG_J | ((din == 8'd0) ? FLAG_Z : 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h23: begin                                                // LD A, (HL)
                        case (step)
                            6'd0: `RD(ra_hl0)
                            6'd1: `RD(ra_hl1)
                            6'd2: tmp16[7:0] <= din;
                            6'd3: tmp16[15:8] <= din;
                            6'd4: `RD(tmp16)
                            6'd5: ;
                            default: begin
                                `WR(ra_a, din)
                                f <= (f & ~FLAG_Z) | FLAG_J | ((din == 8'd0) ? FLAG_Z : 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h24: begin                                                // LDW (x), mn
                        case (step)
                            6'd0: `WR(imm0_a, imm1)
                            default: begin `WR(imm0_a + 16'd1, imm2) f <= f | FLAG_J; `FIN end
                        endcase
                    end

                    8'h25: begin                                                // LDW (HL), mn
                        case (step)
                            6'd0: `RD(ra_hl0)
                            6'd1: `RD(ra_hl1)
                            6'd2: tmp16[7:0] <= din;
                            6'd3: tmp16[15:8] <= din;
                            6'd4: `WR(tmp16, imm0)
                            default: begin `WR(tmp16 + 16'd1, imm1) f <= f | FLAG_J; `FIN end
                        endcase
                    end

                    8'h26: begin                                                // LD (x), (y)
                        case (step)
                            6'd0: `RD(imm0_a)
                            6'd1: ;
                            6'd2: tmp8 <= din;
                            default: begin
                                `WR({8'd0, imm1}, tmp8)
                                f <= (f & ~FLAG_Z) | FLAG_J | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h2a: begin                                                // LD (x), A
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: ;
                            default: begin
                                `WR(imm0_a, din)
                                f <= (f & ~FLAG_Z) | FLAG_J | ((din == 8'd0) ? FLAG_Z : 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'h2b: begin                                                // LD (HL), A
                        // MAME sets only JF here, unlike LD (x),A above (tlcs870_ops.cpp:676)
                        case (step)
                            6'd0: `RD(ra_hl0)
                            6'd1: `RD(ra_hl1)
                            6'd2: begin `RD(ra_a) tmp16[7:0] <= din; end
                            6'd3: tmp16[15:8] <= din;
                            default: begin `WR(tmp16, din) f <= f | FLAG_J; `FIN end
                        endcase
                    end

                    8'h2c: begin `WR(imm0_a, imm1) f <= f | FLAG_J; `FIN end   // LD (x), n

                    8'h2d, 8'h2f: begin                                         // LD (HL),n / CLR (HL)
                        case (step)
                            6'd0: `RD(ra_hl0)
                            6'd1: `RD(ra_hl1)
                            6'd2: tmp16[7:0] <= din;
                            6'd3: tmp16[15:8] <= din;
                            default: begin
                                `WR(tmp16, (op0 == 8'h2f) ? 8'd0 : imm0)
                                f <= f | FLAG_J;
                                `FIN
                            end
                        endcase
                    end

                    8'h2e: begin `WR(imm0_a, 8'd0) f <= f | FLAG_J; `FIN end    // CLR (x)

                    8'b00110???: begin `WR(ra_r, imm0) f <= f | FLAG_J; `FIN end // LD r, n

                    8'b0100????: begin                                          // SET/CLR (x).b
                        case (step)
                            6'd0: `RDX(imm0_a, 1'b1)
                            6'd1: ;
                            6'd2: tmp8 <= din;
                            default: begin
                                // the flags follow the bit's ORIGINAL value
                                f <= set_zj(f, (tmp8 & bitmask) == 8'd0);
                                `WR(imm0_a, op0[3] ? (tmp8 & ~bitmask) : (tmp8 | bitmask))
                                `FIN
                            end
                        endcase
                    end

                    8'b0101????: begin                                          // LD A,r / LD r,A
                        case (step)
                            6'd0: `RD(op0[3] ? ra_a : ra_r)
                            6'd1: ;
                            default: begin
                                `WR(op0[3] ? ra_r : ra_a, din)
                                f <= (f & ~FLAG_Z) | FLAG_J | ((din == 8'd0) ? FLAG_Z : 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'b0110????: begin                                          // INC r / DEC r
                        case (step)
                            6'd0: `RD(ra_r)
                            6'd1: ;
                            6'd2: tmp8 <= op0[3] ? (din - 8'd1) : (din + 8'd1);
                            default: begin
                                `WR(ra_r, tmp8)
                                f <= op0[3]
                                   ? ((f & ~(FLAG_Z | FLAG_J))
                                      | ((tmp8 == 8'hff) ? FLAG_J : 8'd0)
                                      | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0))
                                   : set_zj(f, tmp8 == 8'd0);
                                `FIN
                            end
                        endcase
                    end

                    8'b01110???: begin                                          // ALUOP A, n
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: ;
                            6'd2: begin
                                alu_a <= {8'd0, din};
                                alu_b <= {8'd0, imm0};
                                alu_op <= op0[2:0];
                                alu_wide <= 1'b0;
                            end
                            default: begin
                                f <= alu_f;
                                if (op0[2:0] != 3'd7) `WR(ra_a, alu_r[7:0])     // CMP writes nothing
                                `FIN
                            end
                        endcase
                    end

                    8'b01111???: begin                                          // ALUOP A, (x)
                        case (step)
                            6'd0: `RD(ra_a)
                            6'd1: `RD(imm0_a)
                            6'd2: tmp8 <= din;
                            6'd3: begin
                                alu_a <= {8'd0, tmp8};
                                alu_b <= {8'd0, din};
                                alu_op <= op0[2:0];
                                alu_wide <= 1'b0;
                            end
                            default: begin
                                f <= alu_f;
                                if (op0[2:0] != 3'd7) `WR(ra_a, alu_r[7:0])
                                `FIN
                            end
                        endcase
                    end

                    8'b10??????: begin                                          // JRS T,a / JRS F,a
                        if (cond_met(op0[5] ? 3'd7 : 3'd6, f)) begin
                            pc <= jrs_target;
                            cycles <= cycles + 5'd2;
                        end
                        f <= f | FLAG_J;
                        `FIN
                    end

                    8'b1100????: begin                                          // CALLV n
                        // MAME jumps to the vector's ADDRESS, not through it (tlcs870_ops.cpp:985)
                        case (step)
                            6'd0: `WR(sp - 16'd1, pc[7:0])
                            default: begin
                                `WR(sp, pc[15:8])
                                sp <= sp - 16'd2;
                                pc <= 16'hffc0 + {11'd0, op0[3:0], 1'b0};
                                `FIN
                            end
                        endcase
                    end

                    8'b11010???: begin                                          // JR cc, a
                        if (cond_met(op0[2:0], f)) begin
                            pc <= jr_target;
                            cycles <= cycles + 5'd2;
                        end
                        f <= f | FLAG_J;
                        `FIN
                    end

                    8'b11011???: begin                                          // LD CF, (x).b
                        case (step)
                            6'd0: `RD(imm0_a)
                            6'd1: ;
                            default: begin
                                // JF always ends up the inverse of CF for this form
                                f <= ((din & bitmask) != 8'd0)
                                   ? ((f & ~FLAG_J) | FLAG_C)
                                   : ((f & ~FLAG_C) | FLAG_J);
                                `FIN
                            end
                        endcase
                    end

                    8'hfa: begin sp <= {imm1, imm0}; f <= f | FLAG_J; `FIN end  // LD SP, mn

                    8'hfb: begin pc <= jr_target; f <= f | FLAG_J; `FIN end     // JR a

                    8'hfc, 8'hfd: begin                                         // CALL mn / CALLP n
                        case (step)
                            6'd0: `WR(sp - 16'd1, pc[7:0])
                            default: begin
                                `WR(sp, pc[15:8])
                                sp <= sp - 16'd2;
                                pc <= (op0 == 8'hfd) ? (16'hff00 + imm0_a) : {imm1, imm0};
                                `FIN
                            end
                        endcase
                    end

                    8'hfe: begin pc <= {imm1, imm0}; f <= f | FLAG_J; `FIN end  // JP mn

                    8'hff: begin il_n[1] = 1'b1; `FIN end                  // SWI

                    // ---- register prefix, 0xe8-0xef (tlcs870_ops_reg.cpp) ---------------------
                    // The prefix names g (op0[2:0]) or gg (op0[1:0]); the byte after it names
                    // the operation and, where there is one, a second register or a bit.
                    8'b11101???: begin
                        casez (op1)
                        8'h01, 8'h0a, 8'h0b, 8'b000111??: begin  // SWAP/DAA/DAS/SHLC/SHRC/ROLC/RORC g
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: ;
                                6'd2: begin
                                    sh_v <= din;
                                    sh_op <= (op1 == 8'h01) ? 3'd6 : (op1 == 8'h0a) ? 3'd4
                                           : (op1 == 8'h0b) ? 3'd5 : {1'b0, op1[1:0]};
                                end
                                default: begin f <= sh_f; `WR(ra_g, sh_r) `FIN end
                            endcase
                        end

                        8'h02: begin                            // MUL gg: only the flags show
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: tmp8 <= din;
                                6'd3: begin tmp16 <= {8'd0, din}; acc <= 16'd0; mcnt <= 8'd0; end
                                default: begin
                                    if (mcnt == 8'd8) begin
                                        f <= set_zj(f, acc[15:8] == 8'd0);
                                        `FIN
                                    end else begin
                                        if (tmp8[0]) acc <= acc + tmp16;
                                        tmp8  <= {1'b0, tmp8[7:1]};
                                        tmp16 <= {tmp16[14:0], 1'b0};
                                        mcnt  <= mcnt + 8'd1;
                                        step  <= step;
                                    end
                                end
                            endcase
                        end

                        8'h03: begin                            // DIV gg, C
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: begin `RD(ra_c) tmp8 <= din; end
                                6'd3: tmp16 <= {din, 8'd0};
                                6'd4: begin
                                    tmp16 <= tmp16 | {8'd0, tmp8};
                                    ea <= {8'd0, din};
                                    acc <= 16'd0;
                                    mcnt <= 8'd0;
                                end
                                6'd5: begin
                                    if (ea[7:0] == 8'd0) begin
                                        f <= f | FLAG_C;
                                        `FIN
                                    end else if (mcnt == 8'd16) begin
                                        `WR(ra_gg0, tmp16[7:0])
                                    end else begin
                                        if ({acc[14:0], tmp16[15]} >= {8'd0, ea[7:0]}) begin
                                            acc <= {acc[14:0], tmp16[15]} - {8'd0, ea[7:0]};
                                            tmp16 <= {tmp16[14:0], 1'b1};
                                        end else begin
                                            acc <= {acc[14:0], tmp16[15]};
                                            tmp16 <= {tmp16[14:0], 1'b0};
                                        end
                                        mcnt <= mcnt + 8'd1;
                                        step <= step;
                                    end
                                end
                                default: begin
                                    `WR(ra_gg1, acc[7:0])
                                    f <= (f & ~(FLAG_C | FLAG_Z | FLAG_J))
                                       | ((tmp16[15:8] != 8'd0) ? FLAG_C : 8'd0)
                                       | ((acc[7:0] == 8'd0) ? (FLAG_Z | FLAG_J) : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'h04: begin                            // RETN, with 0xe8 only
                            // MAME reads the PSW from sp+2, the same byte as the return
                            // address's high half, where RETI reads it from sp+3
                            // (tlcs870_ops_reg.cpp:150); see docs/MAME_KLUDGES.md
                            if (op0 != 8'he8) begin dbg_unimpl <= 1'b1; `FIN end
                            else case (step)
                                6'd0: `RD(sp + 16'd1)
                                6'd1: `RD(sp + 16'd2)
                                6'd2: tmp8 <= din;
                                default: begin
                                    pc <= {din, tmp8};
                                    f <= {din[7:4], 4'd0};
                                    rbs <= din[3:0];
                                    sp <= sp + 16'd3;
                                    `FIN
                                end
                            endcase
                        end

                        8'h06: begin                            // POP gg
                            case (step)
                                6'd0: `RD(sp + 16'd1)
                                6'd1: `RD(sp + 16'd2)
                                6'd2: tmp8 <= din;
                                6'd3: begin `WR(ra_gg0, tmp8) tmp8 <= din; end
                                default: begin `WR(ra_gg1, tmp8) sp <= sp + 16'd2; `FIN end
                            endcase
                        end

                        8'h07: begin                            // PUSH gg
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: tmp8 <= din;
                                6'd3: begin `WR(sp - 16'd1, tmp8) tmp8 <= din; end
                                default: begin `WR(sp, tmp8) sp <= sp - 16'd2; `FIN end
                            endcase
                        end

                        8'b000100??: begin                      // XCH rr, gg
                            // MAME dispatches 0x10-0x13 here and 0x14-0x17 to LD rr,gg, which is
                            // the other way round from its own comment blocks; see MAME_KLUDGES
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: begin `RD(ra_1rr0) tmp16[7:0] <= din; end
                                6'd3: begin `RD(ra_1rr1) tmp16[15:8] <= din; end
                                6'd4: ea[7:0] <= din;
                                6'd5: ea[15:8] <= din;
                                6'd6: `WR(ra_1rr0, tmp16[7:0])
                                6'd7: `WR(ra_1rr1, tmp16[15:8])
                                6'd8: `WR(ra_gg0, ea[7:0])
                                default: begin `WR(ra_gg1, ea[15:8]) f <= f | FLAG_J; `FIN end
                            endcase
                        end

                        8'b000101??: begin                      // LD rr, gg
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: tmp8 <= din;
                                6'd3: begin `WR(ra_1rr0, tmp8) tmp8 <= din; end
                                default: begin `WR(ra_1rr1, tmp8) f <= f | FLAG_J; `FIN end
                            endcase
                        end

                        8'b00110???: begin                      // ALUOP WA, gg
                            case (step)
                                6'd0: `RD(ra_a)
                                6'd1: `RD(ra_w)
                                6'd2: begin `RD(ra_gg0) tmp16[7:0] <= din; end
                                6'd3: begin `RD(ra_gg1) tmp16[15:8] <= din; end
                                6'd4: ea[7:0] <= din;
                                6'd5: ea[15:8] <= din;
                                6'd6: begin
                                    alu_a <= tmp16; alu_b <= ea;
                                    alu_op <= alu1; alu_wide <= 1'b1;
                                end
                                6'd7: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(ra_a, alu_r[7:0])
                                end
                                default: begin
                                    if (alu1 != 3'd7) `WR(ra_w, alu_r[15:8])
                                    `FIN
                                end
                            endcase
                        end

                        8'b00111???: begin                      // ALUOP gg, mn
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: tmp16[7:0] <= din;
                                6'd3: tmp16[15:8] <= din;
                                6'd4: begin
                                    alu_a <= tmp16; alu_b <= {imm1, imm0};
                                    alu_op <= alu1; alu_wide <= 1'b1;
                                end
                                6'd5: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(ra_gg0, alu_r[7:0])
                                end
                                default: begin
                                    if (alu1 != 3'd7) `WR(ra_gg1, alu_r[15:8])
                                    `FIN
                                end
                            endcase
                        end

                        8'b0100????, 8'b11000???: begin         // SET/CLR/CPL g.b
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: ;
                                6'd2: tmp8 <= din;
                                default: begin
                                    f <= set_zj(f, (tmp8 & bitmask1) == 8'd0);
                                    `WR(ra_g, op1[7] ? (tmp8 ^ bitmask1)
                                            : op1[3] ? (tmp8 & ~bitmask1) : (tmp8 | bitmask1))
                                    `FIN
                                end
                            endcase
                        end

                        8'b01011???: begin                      // LD r, g
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: ;
                                default: begin
                                    `WR(ra_1r, din)
                                    f <= (f & ~FLAG_Z) | FLAG_J | ((din == 8'd0) ? FLAG_Z : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'b0110????: begin                      // ALUOP A,g and ALUOP g,A
                            case (step)
                                6'd0: `RD(op1[3] ? ra_g : ra_a)
                                6'd1: `RD(op1[3] ? ra_a : ra_g)
                                6'd2: tmp8 <= din;
                                6'd3: begin
                                    alu_a <= {8'd0, tmp8}; alu_b <= {8'd0, din};
                                    alu_op <= alu1; alu_wide <= 1'b0;
                                end
                                default: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(op1[3] ? ra_g : ra_a, alu_r[7:0])
                                    `FIN
                                end
                            endcase
                        end

                        8'b01110???: begin                      // ALUOP g, n
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: ;
                                6'd2: begin
                                    alu_a <= {8'd0, din}; alu_b <= {8'd0, imm0};
                                    alu_op <= alu1; alu_wide <= 1'b0;
                                end
                                default: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(ra_g, alu_r[7:0])
                                    `FIN
                                end
                            endcase
                        end

                        8'h82, 8'h83, 8'h8a, 8'h8b, 8'h92, 8'h93,
                        8'h9a, 8'h9b, 8'h9e, 8'h9f: begin       // the (pp).g bit forms
                            // the bit position is in g, and (pp) is DE or HL
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: `RD(ra_pp0)
                                6'd2: begin `RD(ra_pp1) tmp8 <= {5'd0, din[2:0]}; end
                                6'd3: tmp16[7:0] <= din;
                                6'd4: tmp16[15:8] <= din;
                                // CLR (0x8a/b) and CPL (0x92/3) see the latch
                                6'd5: `RDX(tmp16, op1[7:1] == 7'h45 || op1[7:1] == 7'h49)
                                6'd6: ;
                                default: begin
                                    case (op1[6:3])
                                        4'b0000: begin          // SET (pp).g
                                            f <= set_zj(f, (din & bitmask_g) == 8'd0);
                                            `WR(tmp16, din | bitmask_g)
                                        end
                                        4'b0001: begin          // CLR (pp).g
                                            f <= set_zj(f, (din & bitmask_g) == 8'd0);
                                            `WR(tmp16, din & ~bitmask_g)
                                        end
                                        4'b0010: begin          // CPL (pp).g
                                            f <= set_zj(f, (din & bitmask_g) == 8'd0);
                                            `WR(tmp16, din ^ bitmask_g)
                                        end
                                        default: begin
                                            if (op1[2]) begin   // LD CF, (pp).g
                                                f <= ((din & bitmask_g) != 8'd0)
                                                   ? ((f & ~FLAG_J) | FLAG_C)
                                                   : ((f & ~FLAG_C) | FLAG_J);
                                            end else begin      // LD (pp).g, CF
                                                f <= f | FLAG_J;
                                                `WR(tmp16, cf ? (din | bitmask_g)
                                                              : (din & ~bitmask_g))
                                            end
                                        end
                                    endcase
                                    `FIN
                                end
                            endcase
                        end

                        8'b10101???: begin                      // XCH r, g
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: `RD(ra_1r)
                                6'd2: tmp8 <= din;
                                6'd3: begin `WR(ra_1r, tmp8) tmp16[7:0] <= din; end
                                default: begin
                                    `WR(ra_g, tmp16[7:0])
                                    f <= (f & ~FLAG_Z) | FLAG_J | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'b11001???: begin                      // LD g.b, CF
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: ;
                                default: begin
                                    `WR(ra_g, cf ? (din | bitmask1) : (din & ~bitmask1))
                                    f <= f | FLAG_J;
                                    `FIN
                                end
                            endcase
                        end

                        8'b1101????: begin                      // XOR CF, g.b and LD CF, g.b
                            case (step)
                                6'd0: `RD(ra_g)
                                6'd1: ;
                                default: begin
                                    // XOR: the new carry is the old one against the bit.
                                    // LD: the new carry IS the bit. JF follows for XOR and is
                                    // the inverse for LD (tlcs870_ops_reg.cpp:727, 771).
                                    if (op1[3]) begin           // LD CF, g.b
                                        f <= ((din & bitmask1) != 8'd0)
                                           ? ((f & ~FLAG_J) | FLAG_C)
                                           : ((f & ~FLAG_C) | FLAG_J);
                                    end else begin              // XOR CF, g.b
                                        f <= (cf ^ ((din & bitmask1) != 8'd0))
                                           ? (f | FLAG_C | FLAG_J)
                                           : (f & ~(FLAG_C | FLAG_J));
                                    end
                                    `FIN
                                end
                            endcase
                        end

                        8'hfa: begin                            // LD SP, gg
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: sp[7:0] <= din;
                                default: begin sp[15:8] <= din; f <= f | FLAG_J; `FIN end
                            endcase
                        end

                        8'hfb: begin                            // LD gg, SP
                            case (step)
                                6'd0: `WR(ra_gg0, sp[7:0])
                                default: begin `WR(ra_gg1, sp[15:8]) f <= f | FLAG_J; `FIN end
                            endcase
                        end

                        8'hfc, 8'hfe: begin                     // CALL gg / JP gg
                            case (step)
                                6'd0: `RD(ra_gg0)
                                6'd1: `RD(ra_gg1)
                                6'd2: tmp16[7:0] <= din;
                                6'd3: tmp16[15:8] <= din;
                                6'd4: begin
                                    if (op1 == 8'hfc) `WR(sp - 16'd1, pc[7:0])
                                    else begin pc <= tmp16; f <= f | FLAG_J; `FIN end
                                end
                                default: begin
                                    `WR(sp, pc[15:8])
                                    sp <= sp - 16'd2;
                                    pc <= tmp16;
                                    `FIN
                                end
                            endcase
                        end

                        default: begin dbg_unimpl <= 1'b1; `FIN end
                        endcase
                    end

                    // ---- destination prefix, 0xf0-0xf7 (tlcs870_ops_dst.cpp) -----------------
                    // P_EA has already put the address in `ea` and applied any HL writeback.
                    8'b11110???: begin
                        casez (op1)
                        8'b000100??: begin                      // LD (dst), rr
                            case (step)
                                6'd0: `RD(ra_1rr0)
                                6'd1: `RD(ra_1rr1)
                                6'd2: tmp8 <= din;
                                6'd3: begin `WR(ea, tmp8) tmp8 <= din; end
                                default: begin
                                    `WR(ea + 16'd1, tmp8)
                                    f <= f | FLAG_J;
                                    `FIN
                                end
                            endcase
                        end

                        8'h2c: begin                            // LD (dst), n
                            `WR(ea, imm0)
                            f <= f | FLAG_J;
                            `FIN
                        end

                        8'b01011???: begin                      // LD (dst), r
                            case (step)
                                6'd0: `RD(ra_1r)
                                6'd1: ;
                                default: begin
                                    `WR(ea, din)
                                    f <= f | FLAG_J;
                                    `FIN
                                end
                            endcase
                        end

                        // MAME logs anything else and changes nothing
                        default: `FIN
                        endcase
                    end

                    // ---- source prefix, 0xe0-0xe7 (tlcs870_ops_src.cpp) ----------------------
                    // P_EA has already put the address in `ea` and applied any HL writeback.
                    8'b11100???: begin
                        casez (op1)
                        8'h08, 8'h09: begin                     // ROLD / RORD A, (src)
                            // a 12-bit rotate through A's low nibble and the byte at (src)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: `RD(ra_a)
                                6'd2: tmp8 <= din;              // the byte at (src)
                                6'd3: begin
                                    `WR(ra_a, op1[0] ? {din[7:4], tmp8[3:0]}
                                                     : {din[7:4], tmp8[7:4]})
                                    tmp8 <= op1[0] ? {din[3:0], tmp8[7:4]}
                                                   : {tmp8[3:0], din[3:0]};
                                end
                                default: begin `WR(ea, tmp8) f <= f | FLAG_J; `FIN end
                            endcase
                        end

                        8'b000101??: begin                      // LD rr, (src)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: `RD(ea + 16'd1)
                                6'd2: tmp8 <= din;
                                6'd3: begin `WR(ra_1rr0, tmp8) tmp8 <= din; end
                                default: begin `WR(ra_1rr1, tmp8) f <= f | FLAG_J; `FIN end
                            endcase
                        end

                        8'h20, 8'h28: begin                     // INC / DEC (src)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: ;
                                6'd2: tmp8 <= op1[3] ? (din - 8'd1) : (din + 8'd1);
                                default: begin
                                    `WR(ea, tmp8)
                                    f <= op1[3]
                                       ? ((f & ~(FLAG_Z | FLAG_J))
                                          | ((tmp8 == 8'hff) ? FLAG_J : 8'd0)
                                          | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0))
                                       : set_zj(f, tmp8 == 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'h26: begin                            // LD (x), (src)
                            // MAME leaves ZF alone here and calls it undefined (src.cpp:294)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: ;
                                default: begin
                                    `WR({8'd0, imm0}, din)
                                    f <= f | FLAG_J;
                                    `FIN
                                end
                            endcase
                        end

                        8'h27: begin                            // LD (HL), (src)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: `RD(ra_hl0)
                                6'd2: begin `RD(ra_hl1) tmp8 <= din; end
                                6'd3: tmp16[7:0] <= din;
                                default: begin
                                    `WR({din, tmp16[7:0]}, tmp8)
                                    f <= (f & ~FLAG_Z) | FLAG_J
                                       | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'h2f: begin                            // MCMP (src), n
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: `RD(ra_a)
                                6'd2: tmp8 <= din & imm0;
                                default: begin
                                    f <= (f & ~(FLAG_Z | FLAG_J | FLAG_C))
                                       | ((din == tmp8) ? (FLAG_Z | FLAG_J) : 8'd0)
                                       | ((din < tmp8) ? FLAG_C : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'b0100????, 8'b11000???: begin         // SET / CLR / CPL (src).b
                            case (step)
                                6'd0: `RDX(ea, 1'b1)
                                6'd1: ;
                                6'd2: tmp8 <= din;
                                default: begin
                                    f <= set_zj(f, (tmp8 & bitmask1) == 8'd0);
                                    `WR(ea, op1[7] ? (tmp8 ^ bitmask1)
                                          : op1[3] ? (tmp8 & ~bitmask1) : (tmp8 | bitmask1))
                                    `FIN
                                end
                            endcase
                        end

                        8'b01011???: begin                      // LD r, (src)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: ;
                                default: begin
                                    `WR(ra_1r, din)
                                    f <= (f & ~FLAG_Z) | FLAG_J | ((din == 8'd0) ? FLAG_Z : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'b01100???: begin                      // ALUOP (src), (HL)
                            case (step)
                                6'd0: `RDX(ea, alu1 != 3'd7)
                                6'd1: `RD(ra_hl0)
                                6'd2: begin `RD(ra_hl1) tmp8 <= din; end
                                6'd3: tmp16[7:0] <= din;
                                6'd4: begin `RD({din, tmp16[7:0]}) tmp16[15:8] <= din; end
                                6'd5: ;
                                6'd6: begin
                                    alu_a <= {8'd0, tmp8}; alu_b <= {8'd0, din};
                                    alu_op <= alu1; alu_wide <= 1'b0;
                                end
                                default: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(ea, alu_r[7:0])
                                    `FIN
                                end
                            endcase
                        end

                        8'b01110???: begin                      // ALUOP (src), n
                            case (step)
                                6'd0: `RDX(ea, alu1 != 3'd7)
                                6'd1: ;
                                6'd2: begin
                                    alu_a <= {8'd0, din}; alu_b <= {8'd0, imm0};
                                    alu_op <= alu1; alu_wide <= 1'b0;
                                end
                                default: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(ea, alu_r[7:0])
                                    `FIN
                                end
                            endcase
                        end

                        8'b01111???: begin                      // ALUOP A, (src)
                            case (step)
                                6'd0: `RD(ra_a)
                                6'd1: `RD(ea)
                                6'd2: tmp8 <= din;
                                6'd3: begin
                                    alu_a <= {8'd0, tmp8}; alu_b <= {8'd0, din};
                                    alu_op <= alu1; alu_wide <= 1'b0;
                                end
                                default: begin
                                    f <= alu_f;
                                    if (alu1 != 3'd7) `WR(ra_a, alu_r[7:0])
                                    `FIN
                                end
                            endcase
                        end

                        8'b10101???: begin                      // XCH r, (src)
                            case (step)
                                6'd0: `RDX(ea, 1'b1)
                                6'd1: `RD(ra_1r)
                                6'd2: tmp8 <= din;              // the byte at (src)
                                6'd3: `WR(ea, din)              // r goes to (src)
                                default: begin
                                    `WR(ra_1r, tmp8)
                                    f <= (f & ~FLAG_Z) | FLAG_J | ((tmp8 == 8'd0) ? FLAG_Z : 8'd0);
                                    `FIN
                                end
                            endcase
                        end

                        8'b11001???: begin                      // LD (src).b, CF
                            case (step)
                                6'd0: `RDX(ea, 1'b1)
                                6'd1: ;
                                default: begin
                                    `WR(ea, cf ? (din | bitmask1) : (din & ~bitmask1))
                                    f <= f | FLAG_J;
                                    `FIN
                                end
                            endcase
                        end

                        8'b1101????: begin                      // XOR CF / LD CF, (src).b
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: ;
                                default: begin
                                    if (op1[3]) begin           // LD CF, (src).b
                                        f <= ((din & bitmask1) != 8'd0)
                                           ? ((f & ~FLAG_J) | FLAG_C)
                                           : ((f & ~FLAG_C) | FLAG_J);
                                    end else begin              // XOR CF, (src).b
                                        f <= (cf ^ ((din & bitmask1) != 8'd0))
                                           ? (f | FLAG_C | FLAG_J)
                                           : (f & ~(FLAG_C | FLAG_J));
                                    end
                                    `FIN
                                end
                            endcase
                        end

                        8'hfc, 8'hfe: begin                     // CALL (src) / JP (src)
                            case (step)
                                6'd0: `RD(ea)
                                6'd1: `RD(ea + 16'd1)
                                6'd2: tmp16[7:0] <= din;
                                6'd3: begin
                                    tmp16[15:8] <= din;
                                    if (op1 == 8'hfc) `WR(sp - 16'd1, pc[7:0])
                                    else begin
                                        pc <= {din, tmp16[7:0]};
                                        f <= f | FLAG_J;
                                        `FIN
                                    end
                                end
                                default: begin
                                    `WR(sp, pc[15:8])
                                    sp <= sp - 16'd2;
                                    pc <= tmp16;
                                    `FIN
                                end
                            endcase
                        end

                        // MAME logs anything else and changes nothing
                        default: `FIN
                        endcase
                    end

                    default: begin                                              // not implemented
                        dbg_unimpl <= 1'b1;
                        `FIN
                    end
                    endcase
                end

                default: begin                  // P_PACE
                    if (elapsed >= {3'd0, cycles}) begin
                        ph <= P_FETCH;
                        step <= 6'd0;
                        elapsed <= ce ? 8'd1 : 8'd0;
                    end
                end
            endcase
        end

        il  <= il_n;
        eir <= eir_n;
        a_q  <= a_d;
        rd_q <= rd_d;
        latch_q <= latch_d;
        we_q <= we_d;
        wd_q <= wd_d;
    end

`undef RD
`undef RDX
`undef WR
`undef FIN

endmodule
