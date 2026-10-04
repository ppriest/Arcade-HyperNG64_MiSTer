// SPDX-License-Identifier: GPL-3.0-or-later
//
// The geometry engine (user decision: microcoded; docs/phase3_3d.md). It runs the microcode
// scripts/geo_ucode.py assembles (hng64_geo_ucode.hex and hng64_geo_ucode.svh, beside this), with
// the instruction set scripts/geo_engine.py defines and simulates; that simulator is the reference
// this is checked against (sim/geo_tb). Written from GeoEngine.scala, its SpinalHDL source before.
//
// Pipeline, one instruction a clock:
//   F  the microcode ROM is read at `fetch`: the branch target, or the next address
//   D  the instruction; the register file's reads (copies A and B of a 512 x 48 RAM, read every
//      clock so a held instruction sees writes made while it waited)
//   E  operands (forwarded from M and W), the ALU, branches (resolved here, the fetch redirected
//      the clock after: two instructions dropped), the multiplier
//   M  the accumulator (MUL MAC MSB LDA ADA ADAV ASHL), and every register write
// The multi-cycle ops hold E: LDX STX TRSQ TRCP DL a clock more (copy X of the register file
// serves the indexed reads); SHLV LOG2 NORM three; MIN MAX SHLI SHRI NEG ABS SEXT16 WRAP two; LDA
// ADA ADAV one; DIV its quotient bits and three; VRD VRDS until their word is there; EMIT 24 while
// the setup record (22 words) is read out through copy X. An accumulator branch or DIV straight
// after an accumulator op waits a clock. The accumulator stores (ST STF STV STVW) go in a clock to
// the store unit beside E, whose result is M's three clocks after; what reads or writes it waits
// for that, LDX STX EMIT for every store in the unit, and an op writing through M on that clock
// one more.
//
// Ports keep the names the SpinalHDL version had, which rtl/hng64_3d.sv connects.

`default_nettype none

module hng64_geo (
    input  wire          clk,
    input  wire          reset,             // synchronous
    input  wire          io_start,          // one clock: run from io_entry
    input  wire  [1:0]   io_entry,          // 0 init, 1 clear, 2 upload
    input  wire          io_samsho,         // written into the microcode's registers at init
    input  wire  [23:0]  io_vlen,
    output wire          io_busy,
    output wire  [7:0]   io_dlAddr,         // the display list, data the clock after
    input  wire  [15:0]  io_dlData,
    input  wire  [7:0]   io_wrap_0,  io_wrap_1,  io_wrap_2,  io_wrap_3,
    input  wire  [7:0]   io_wrap_4,  io_wrap_5,  io_wrap_6,  io_wrap_7,
    input  wire  [7:0]   io_wrap_8,  io_wrap_9,  io_wrap_10, io_wrap_11,
    input  wire  [7:0]   io_wrap_12, io_wrap_13, io_wrap_14, io_wrap_15,
    input  wire  [7:0]   io_wrap_16, io_wrap_17, io_wrap_18, io_wrap_19,
    input  wire  [7:0]   io_wrap_20, io_wrap_21, io_wrap_22, io_wrap_23,
    input  wire  [7:0]   io_wrap_24, io_wrap_25, io_wrap_26, io_wrap_27,
    input  wire  [7:0]   io_wrap_28, io_wrap_29, io_wrap_30, io_wrap_31,
    input  wire  [27:0]  io_vBase,          // the vertex ROM's byte offset in DDR3
    output wire          io_vRd_valid,      // hng64_ddram's client port
    input  wire          io_vRd_ready,
    output wire  [27:0]  io_vRd_payload,
    input  wire          io_vData_valid,
    input  wire  [63:0]  io_vData_payload,
    output wire          io_tri_valid,      // the setup record (geo_engine.setup_record)
    input  wire          io_tri_ready,
    output wire  [23:0]  io_tri_payload_v_0_0, io_tri_payload_v_0_1,
    output wire  [23:0]  io_tri_payload_v_1_0, io_tri_payload_v_1_1,
    output wire  [23:0]  io_tri_payload_v_2_0, io_tri_payload_v_2_1,
    output wire          io_tri_payload_neg,
    output wire  [29:0]  io_tri_payload_p0_v_0,
    output wire  [33:0]  io_tri_payload_p0_v_1,
    output wire  [23:0]  io_tri_payload_p0_v_2,
    output wire  [31:0]  io_tri_payload_p0_v_3,
    output wire  [31:0]  io_tri_payload_p0_v_4,
    output wire  [41:0]  io_tri_payload_dx_v_0,
    output wire  [45:0]  io_tri_payload_dx_v_1,
    output wire  [35:0]  io_tri_payload_dx_v_2,
    output wire  [43:0]  io_tri_payload_dx_v_3,
    output wire  [43:0]  io_tri_payload_dx_v_4,
    output wire  [41:0]  io_tri_payload_dy_v_0,
    output wire  [45:0]  io_tri_payload_dy_v_1,
    output wire  [35:0]  io_tri_payload_dy_v_2,
    output wire  [43:0]  io_tri_payload_dy_v_3,
    output wire  [43:0]  io_tri_payload_dy_v_4,
    output wire  [66:0]  io_tri_payload_attr
);

    import hng64_geo_ucode_pkg::*;          // GEO_ENTRY_*, GEO_REG_*: scripts/geo_ucode.py

    localparam int W  = 48;
    localparam int AW = 72;                 // the widest value measured is 58 (sams64 3500)

    // opcodes: scripts/geo_engine.py OPS, in order
    localparam logic [5:0] NOP = 0, MUL = 1, MAC = 2, MSB = 3, LDA = 4, ADA = 5, ADAV = 6, ASHL = 7,
        ST = 8, STF = 9, STV = 10, DIV = 11, ADD = 12, SUB = 13, MIN = 14, MAX = 15, OR_ = 16,
        AND_ = 17, ADDI = 18, ANDI = 19, SHLI = 20, SHRI = 21, SHLV = 22, MOVI = 23, NEG = 24,
        ABS = 25, SEXT16 = 26, LOG2 = 27, NORM = 28, LDX = 29, STX = 30, TRSQ = 31, TRCP = 32,
        WRAP = 33, DL = 34, VSEEK = 35, VRD = 36, VRDS = 37, AOUT = 38, VOUT = 39, EMIT = 40,
        J = 41, JAL = 42, RET = 43, BZ = 44, BNZ = 45, BLTZ = 46, BGEZ = 47, BLT = 48, BGE = 49,
        BEQ = 50, BNE = 51, BACCN = 52, BACCNN = 53, BGTZ = 54, HALT = 55, STVW = 56;

    function automatic logic [5:0] fOp(input logic [48:0] i); return i[48:43]; endfunction
    function automatic logic [8:0] fD (input logic [48:0] i); return i[42:34]; endfunction
    function automatic logic [8:0] fA (input logic [48:0] i); return i[33:25]; endfunction
    function automatic logic [8:0] fB (input logic [48:0] i); return i[24:16]; endfunction

    wire [31:0][7:0] wrap = {io_wrap_31, io_wrap_30, io_wrap_29, io_wrap_28, io_wrap_27, io_wrap_26,
                             io_wrap_25, io_wrap_24, io_wrap_23, io_wrap_22, io_wrap_21, io_wrap_20,
                             io_wrap_19, io_wrap_18, io_wrap_17, io_wrap_16, io_wrap_15, io_wrap_14,
                             io_wrap_13, io_wrap_12, io_wrap_11, io_wrap_10, io_wrap_9,  io_wrap_8,
                             io_wrap_7,  io_wrap_6,  io_wrap_5,  io_wrap_4,  io_wrap_3,  io_wrap_2,
                             io_wrap_1,  io_wrap_0};

    // ---- the microcode, the tables, the register file -----------------------------------------
    logic [48:0] rom [0:2047];
    logic [16:0] rsqRom [0:255];
    logic [11:0] rcpRom [0:1023];
    initial begin
        $readmemh("rtl/3d/hng64_geo_ucode.hex", rom);
        $readmemh("rtl/3d/hng64_geo_rsq.hex", rsqRom);
        $readmemh("rtl/3d/hng64_geo_rcp.hex", rcpRom);
    end
    (* ramstyle = "M10K" *) logic signed [W-1:0] rfA [0:511];
    (* ramstyle = "M10K" *) logic signed [W-1:0] rfB [0:511];
    (* ramstyle = "M10K" *) logic signed [W-1:0] rfX [0:511];    // indexed reads and EMIT's

    // ---- state ----------------------------------------------------------------------------------
    logic        running, brPending, validD, validE, mValid, mWrites, mAccOp, wValid;
    logic  [1:0] cfgStep, mulOp, accOp;     // mulOp: 0 none, 1 MUL, 2 MAC, 3 MSB; accOp: 0, set, add, shift
    logic [10:0] pcSeq, brTarget, pcD, pcE;
    logic [48:0] instrD, instrE, mInstr;
    logic signed [W-1:0]  mVal, wVal, rdA, rdB, rdXraw, rdXq, stxD;
    logic  [8:0] wReg;
    logic signed [AW-1:0] acc, prod, accVal;
    logic signed [7:0]    mSh;

    logic stall;                            // E holds: F, D and E keep their instructions
    logic suV1, suV2, mSu, suHaz;           // the store unit (below)
    logic [8:0] suD1, suD2, mSuD;
    assign io_busy = running || cfgStep != 2'd0 || suV1 || suV2 || mSu;

    wire [10:0] fetch = brPending ? brTarget : pcSeq;
    always_ff @(posedge clk) if (!stall) instrD <= rom[fetch];

    // ---- E --------------------------------------------------------------------------------------
    wire        eLive = validE && !brPending;      // the instruction after a taken branch is dropped
    wire  [5:0] o  = fOp(instrE);
    wire  [8:0] d  = fD(instrE);
    wire  [8:0] ra = fA(instrE);
    wire  [8:0] rb = fB(instrE);
    wire signed [15:0] imm = instrE[15:0];
    wire signed [W-1:0] immW = W'(imm);

    // Forwarding: M's result, else W's, else the register file; r0 reads 0. Which one is decided a
    // clock early, into registers (below, from what E, M and W will hold), so E's path is a mux.
    logic selMA, selMB, selWA, selWB, zeroA, zeroB;
    wire signed [W-1:0] a = zeroA ? '0 : (selMA ? mVal : (selWA ? wVal : rdA));
    wire signed [W-1:0] b = zeroB ? '0 : (selMB ? mVal : (selWB ? wVal : rdB));
    // A register branch's operands without M's value: mVal reaches everything, and through the
    // compares into brPending it missed clk3d (2373ebe seed 1, -0.099 ns). A branch whose operand
    // is M's result waits a clock (brFwd) and takes it from W.
    logic brFwd;
    wire signed [W-1:0] aBr = zeroA ? '0 : (selWA ? wVal : rdA);
    wire signed [W-1:0] bBr = zeroB ? '0 : (selWB ? wVal : rdB);

    // E's op classes, decoded from D's instruction and loaded with it, so what picks a result is
    // registers and not E's opcode.
    //   eAlu: ADD SUB OR AND ADDI ANDI MOVI
    //   eMc:  LDX TRSQ TRCP DL VRD VRDS, slowR's ops (DIV SHLV LOG2 NORM), the alu2 ones
    //   eAlu2: MIN MAX SHLI SHRI NEG ABS SEXT16 WRAP
    //   eIsMc: every op that holds E (header); eAccBr: BACCN BACCNN DIV, which wait on M's accumulator
    //   eSt: the stores; eWrM: an op that writes a register through M (eAlu or eMc)
    function automatic logic regBr(input logic [5:0] op);
        regBr = op == BZ || op == BNZ || op == BLTZ || op == BGEZ || op == BGTZ || twoBr(op);
    endfunction
    function automatic logic twoBr(input logic [5:0] op);
        twoBr = op == BLT || op == BGE || op == BEQ || op == BNE;
    endfunction
    function automatic logic isSt(input logic [5:0] op);
        isSt = op == ST || op == STF || op == STV || op == STVW;
    endfunction
    function automatic logic isMcOp(input logic [5:0] op);
        case (op)
            LDX, STX, TRSQ, TRCP, DL, VRD, VRDS, DIV, EMIT, SHLV, LOG2, NORM,
            MIN, MAX, SHLI, SHRI, NEG, ABS, SEXT16, WRAP, LDA, ADA, ADAV: isMcOp = 1'b1;
            default:                                                       isMcOp = 1'b0;
        endcase
    endfunction
    wire  [5:0] dOp = fOp(instrD);
    logic [6:0] eAlu;
    logic [7:0] eMc;
    logic [7:0] eAlu2;
    logic       eDiv, eLog2, eIsMc, eAccBr, eStx, eEmit, eSt, eWrM;
    always_ff @(posedge clk)
        if (reset) begin
            eAlu <= '0; eMc <= '0; eAlu2 <= '0; eDiv <= 1'b0; eLog2 <= 1'b0;
            eIsMc <= 1'b0; eAccBr <= 1'b0; eStx <= 1'b0; eEmit <= 1'b0; eSt <= 1'b0; eWrM <= 1'b0;
        end else if (!stall) begin
            eDiv   <= dOp == DIV;
            eLog2  <= dOp == LOG2;
            eIsMc  <= isMcOp(dOp);
            eAccBr <= dOp == BACCN || dOp == BACCNN || dOp == DIV;
            eStx   <= dOp == STX;
            eEmit  <= dOp == EMIT;
            eSt    <= isSt(dOp);
            eWrM   <= dOp == MOVI || dOp == ANDI || dOp == ADDI || dOp == AND_ || dOp == OR_ || dOp == SUB ||
                      dOp == ADD || (isMcOp(dOp) && !(dOp == STX || dOp == EMIT || dOp == LDA || dOp == ADA ||
                      dOp == ADAV));
            eAlu  <= {dOp == MOVI, dOp == ANDI, dOp == ADDI, dOp == AND_, dOp == OR_, dOp == SUB, dOp == ADD};
            eMc   <= {dOp == MIN || dOp == MAX || dOp == SHLI || dOp == SHRI || dOp == NEG || dOp == ABS ||
                          dOp == SEXT16 || dOp == WRAP,
                      dOp == DIV || dOp == SHLV || dOp == LOG2 || dOp == NORM,
                      dOp == VRDS, dOp == VRD, dOp == DL, dOp == TRCP, dOp == TRSQ, dOp == LDX};
            eAlu2 <= {dOp == WRAP, dOp == SEXT16, dOp == ABS, dOp == NEG, dOp == SHRI, dOp == SHLI,
                      dOp == MAX, dOp == MIN};
        end

    // ALU
    function automatic logic [5:0] topBit(input logic [W-1:0] v);    // the highest set bit's index
        topBit = '0;
        for (int i = 0; i < W; i++) if (v[i]) topBit = 6'(i);
    endfunction
    function automatic logic signed [W-1:0] shiftBy(input logic signed [W-1:0] v, input logic signed [7:0] sh);
        logic signed [7:0] nsh;                                      // sh > 0 left, < 0 arithmetic right
        nsh = -sh;
        shiftBy = (sh >= 0) ? (v <<< sh[5:0]) : (v >>> nsh[5:0]);
    endfunction
    logic signed [W-1:0] alu;
    always_comb begin
        alu = '0;
        if (eAlu[0]) alu |= a + b;
        if (eAlu[1]) alu |= a - b;
        if (eAlu[2]) alu |= a | b;
        if (eAlu[3]) alu |= a & b;
        if (eAlu[4]) alu |= a + immW;
        if (eAlu[5]) alu |= a & immW;
        if (eAlu[6]) alu |= immW;
    end
    wire aluWrites = |eAlu;
    wire mcWrites  = |eMc;
    wire eVrd      = eMc[4] || eMc[5];
    wire accBranchHazard = mValid && mAccOp && eAccBr;

    // ---- multi-cycle operations -------------------------------------------------------------------
    logic  [1:0] mcStep;
    logic        mcDone, mcFinal, stxWrite, vWordReady;
    logic  [8:0] xAddr, stxAddr;
    always_ff @(posedge clk) rdXraw <= rfX[xAddr];
    // the bypass from the write just made: decided a clock early from this clock's write and read
    // addresses (W's register next clock and xAddr's)
    logic bypX;
    wire signed [W-1:0] rdX = bypX ? wVal : rdXraw;
    always_ff @(posedge clk) rdXq <= rdX;                            // EMIT's copy, a clock later
    logic [16:0] rsqV;
    logic [11:0] rcpV;
    always_ff @(posedge clk) begin
        rsqV <= rsqRom[a[7:0]];
        rcpV <= rcpRom[a[9:0]];
    end
    assign io_dlAddr = a[7:0];

    logic        vWordValid;
    logic [15:0] vWordPayload;

    logic [AW-1:0]  divRem;
    logic [47:0]    divDen, divQ;
    logic           divNeg;
    logic  [5:0]    divLeft;
    logic [109:0]   divD;                   // den << (divLeft - 1): 48 bits shifted up to 62

    // the triangle out, and the attributes AOUT sets, at their own widths
    logic        aFlat, aBlend, aTex4bpp;
    logic  [3:0] aTexIndex;
    logic  [1:0] aSub;
    logic  [6:0] aHoff, aVoff;
    logic [15:0] aPal;
    logic  [8:0] aScrollX, aScrollY;
    logic  [4:0] aWrapX, aWrapY;
    wire  [66:0] attrBits = {aWrapY, aWrapX, aScrollY, aScrollX, aPal, aVoff, aHoff, aSub, aTexIndex,
                             aTex4bpp, aBlend, aFlat};
    logic [23:0] tV00, tV01, tV10, tV11, tV20, tV21;
    logic        tNeg;
    logic [29:0] tP0_0;  logic [33:0] tP0_1;  logic [23:0] tP0_2;  logic [31:0] tP0_3;  logic [31:0] tP0_4;
    logic [41:0] tDx_0;  logic [45:0] tDx_1;  logic [35:0] tDx_2;  logic [43:0] tDx_3;  logic [43:0] tDx_4;
    logic [41:0] tDy_0;  logic [45:0] tDy_1;  logic [35:0] tDy_2;  logic [43:0] tDy_3;  logic [43:0] tDy_4;
    logic [66:0] tAttr;
    logic  [4:0] emitCount;
    logic        triValid;

    // SHLV, LOG2 and NORM take their operands a clock before they compute and find the top bit and
    // the shift a clock before they shift. The alu2 ops take a step for their operands. LDA, ADA and
    // ADAV latch their operand and shift a step before the shift into accVal.
    logic signed [W-1:0]  alu2B, slowA, slowR, alu2R;
    logic [15:0]          alu2I;
    logic  [6:0]          accSh;
    logic signed [7:0]    slowB, slowSh;
    logic [48:0]          stT;
    logic  [6:0]          stAmt;
    logic                 stLeft, stRnd;
    logic  [5:0]          slowTop;

    // suHaz: E's op names a store's register, or reads copy X, while the store is in the unit
    // (decided a clock early, below); portHaz: a store's result takes M next clock, so an op that
    // would write through M then waits
    wire portHaz = suV2 && eWrM && (!eIsMc || mcFinal || eVrd);
    wire mcGo = eLive && eIsMc && !accBranchHazard && !suHaz && !portHaz;

    // An op's last step is known the clock before (VRD's and VRDS's, which wait on their word, aside),
    // so its completion is a register: mcFinal, from E's op, its next step and EMIT's next count.
    function automatic logic finalAt(input logic [5:0] op, input logic [1:0] step, input logic [4:0] cnt);
        case (op)
            LDX, TRSQ, TRCP, DL, LDA, ADA, ADAV:            finalAt = step != 0;
            STX, MIN, MAX, SHLI, SHRI, NEG, ABS, SEXT16, WRAP:
                                                            finalAt = step == 2;
            SHLV, LOG2, NORM, DIV:                          finalAt = step == 3;
            EMIT:                                           finalAt = step != 0 && cnt == 5'd23;
            default:                                        finalAt = 1'b0;
        endcase
    endfunction
    assign mcDone     = mcGo && (mcFinal || (eVrd && vWordValid));
    assign vWordReady = mcGo && eVrd && vWordValid;

    // the indexed read's address: STX's source at step 0, EMIT's record from step 1, else a + b. The
    // read is used only by a live op, so it need not wait for mcGo.
    always_comb begin
        xAddr = 9'(a + b);
        if (eStx && mcStep == 2'd0) xAddr = d;
        if (eEmit && mcStep != 2'd0) xAddr = ra + 9'(emitCount);
    end

    // the steps' registers
    wire [AW-1:0] accAbs = acc[AW-1] ? AW'(-acc) : AW'(acc);
    wire [47:0]   bAbs   = b[W-1] ? 48'(-b) : 48'(b);
    wire          divTake = divD[109:AW] == 0 && divRem >= divD[AW-1:0];
    always_ff @(posedge clk)
        if (mcGo)
            case (o)
                STX:
                    if (mcStep == 1) begin
                        stxD    <= (d == 0) ? '0 : rdX;
                        stxAddr <= 9'(a + b);
                    end
                SHLV, LOG2, NORM:
                    if (mcStep == 0) begin
                        slowA <= a;
                        slowB <= (o == SHLV) ? b[7:0] : imm[7:0];
                    end else if (mcStep == 1) begin
                        slowTop <= topBit(slowA);
                        slowSh  <= (o == SHLV) ? slowB : slowB - $signed({2'b00, topBit(slowA)});
                    end
                MIN, MAX, SHLI, SHRI, NEG, ABS, SEXT16, WRAP:
                    if (mcStep == 0) begin
                        slowA <= a;
                        alu2B <= b;
                        alu2I <= imm;
                    end
                LDA, ADA, ADAV:
                    if (mcStep == 0) begin
                        slowA <= a;
                        alu2B <= b;
                        alu2I <= imm;
                        accSh <= (o == ADAV) ? b[6:0] : imm[6:0];
                    end
                DIV:
                    // restoring, on magnitudes; the quotient under 2^imm. den << k is held and
                    // shifted down a bit a step, so a step is one compare and one subtract.
                    if (mcStep == 0) begin
                        divRem  <= accAbs;
                        divDen  <= bAbs;
                        divNeg  <= (acc < 0) != (b < 0);
                        divQ    <= '0;
                        divLeft <= imm[5:0];
                    end else if (mcStep == 1) begin
                        divD <= 110'(divDen) << 6'(divLeft - 6'd1);
                    end else if (mcStep != 3 && divLeft != 0) begin
                        if (divTake) divRem <= divRem - divD[AW-1:0];
                        divQ    <= {divQ[46:0], divTake};
                        divD    <= divD >> 1;
                        divLeft <= divLeft - 6'd1;
                    end
                EMIT:
                    // step 0: wait for the output to be free; 1: read the setup record, R[a .. a + 21],
                    // out through copy X and rdXq (address at count c, data at c + 2); then offer it
                    if (mcStep != 0) begin
                        if (emitCount >= 5'd2)
                            case (5'(emitCount - 5'd2))
                                5'd0:  tV00  <= rdXq[23:0];
                                5'd1:  tV01  <= rdXq[23:0];
                                5'd2:  tV10  <= rdXq[23:0];
                                5'd3:  tV11  <= rdXq[23:0];
                                5'd4:  tV20  <= rdXq[23:0];
                                5'd5:  tV21  <= rdXq[23:0];
                                5'd6:  tNeg  <= rdXq[0];
                                5'd7:  tP0_0 <= rdXq[29:0];
                                5'd8:  tP0_1 <= rdXq[33:0];
                                5'd9:  tP0_2 <= rdXq[23:0];
                                5'd10: tP0_3 <= rdXq[31:0];
                                5'd11: tP0_4 <= rdXq[31:0];
                                5'd12: tDx_0 <= rdXq[41:0];
                                5'd13: tDx_1 <= rdXq[45:0];
                                5'd14: tDx_2 <= rdXq[35:0];
                                5'd15: tDx_3 <= rdXq[43:0];
                                5'd16: tDx_4 <= rdXq[43:0];
                                5'd17: tDy_0 <= rdXq[41:0];
                                5'd18: tDy_1 <= rdXq[45:0];
                                5'd19: tDy_2 <= rdXq[35:0];
                                5'd20: tDy_3 <= rdXq[43:0];
                                5'd21: tDy_4 <= rdXq[43:0];
                                default: ;
                            endcase
                        if (emitCount == 5'd23) tAttr <= attrBits;
                    end
                default: ;
            endcase

    // the step counter and the triangle's valid
    logic [1:0] mcStepNext;
    always_comb begin
        mcStepNext = mcStep;
        if (mcGo)
            case (o)
                LDX, TRSQ, TRCP, DL, LDA, ADA, ADAV:
                                        if (mcStep == 0) mcStepNext = 2'd1;
                STX, MIN, MAX, SHLI, SHRI, NEG, ABS, SEXT16, WRAP:
                                        if (mcStep == 0) mcStepNext = 2'd1;
                                        else if (mcStep == 1) mcStepNext = 2'd2;
                SHLV, LOG2, NORM:       if (mcStep != 3) mcStepNext = mcStep + 2'd1;
                DIV:                    if (mcStep == 0) mcStepNext = 2'd1;
                                        else if (mcStep == 1) mcStepNext = 2'd2;
                                        else if (mcStep != 3 && divLeft == 0) mcStepNext = 2'd3;
                EMIT:                   if (mcStep == 0 && !triValid) mcStepNext = 2'd1;
                default: ;
            endcase
        if (mcDone) mcStepNext = 2'd0;
    end
    logic [4:0] emitCountNext;
    always_comb begin
        emitCountNext = emitCount;
        if (mcGo && eEmit)
            if (mcStep != 0)    emitCountNext = emitCount + 5'd1;
            else if (!triValid) emitCountNext = '0;
    end
    always_ff @(posedge clk) emitCount <= emitCountNext;
    wire triFire = triValid && io_tri_ready;
    always_ff @(posedge clk)
        if (reset) begin
            mcStep   <= '0;
            mcFinal  <= 1'b0;
            stxWrite <= 1'b0;
            triValid <= 1'b0;
        end else begin
            mcStep   <= mcStepNext;
            // E holds its op next clock only on a stall
            mcFinal  <= stall && finalAt(o, mcStepNext, emitCountNext);
            stxWrite <= mcGo && eStx && mcStep == 2'd1;
            if (mcGo && o == EMIT && mcStep != 0 && emitCount == 5'd23) triValid <= 1'b1;
            if (triFire) triValid <= 1'b0;
        end

    // ---- E's hold, branches, and the hand-over to M ------------------------------------------------
    assign stall = eLive && (accBranchHazard || brFwd || suHaz || portHaz || (eIsMc && !mcDone)) ||
                   cfgStep != 2'd0;
    wire eGo = eLive && !stall;
    // The go of an op that is not multi-cycle: for it eIsMc is false and stall is the hazards alone
    // (portHaz is never an op's that does not write through M). The branches, AOUT and VSEEK go on it.
    wire goNotMc = eLive && !accBranchHazard && !brFwd && !suHaz && cfgStep == 2'd0;

    logic        taken;
    logic [10:0] target;
    logic [10:0] retStack [0:3];
    logic  [1:0] retSp;
    always_comb begin
        taken  = 1'b0;
        target = imm[10:0];
        if (goNotMc)
            case (o)
                J, JAL:  taken = 1'b1;
                RET:     begin taken = 1'b1; target = retStack[2'(retSp - 2'd1)]; end
                BZ:      taken = aBr == 0;
                BNZ:     taken = aBr != 0;
                BLTZ:    taken = aBr < 0;
                BGEZ:    taken = aBr >= 0;
                BGTZ:    taken = aBr > 0;
                BLT:     taken = aBr < bBr;
                BGE:     taken = aBr >= bBr;
                BEQ:     taken = aBr == bBr;
                BNE:     taken = aBr != bBr;
                BACCN:   taken = acc < 0;
                BACCNN:  taken = acc >= 0;
                HALT:    begin taken = 1'b1; target = pcE; end
                default: ;
            endcase
    end
    always_ff @(posedge clk) begin
        if (goNotMc && o == JAL) retStack[retSp] <= pcE + 11'd1;
        if (goNotMc && o == AOUT)
            case (d[3:0])
                4'd0:  aFlat     <= a[0];
                4'd1:  aBlend    <= a[0];
                4'd2:  aTex4bpp  <= a[0];
                4'd3:  aTexIndex <= a[3:0];
                4'd4:  aSub      <= a[1:0];
                4'd5:  aHoff     <= a[6:0];
                4'd6:  aVoff     <= a[6:0];
                4'd7:  aPal      <= a[15:0];
                4'd8:  aScrollX  <= a[8:0];
                4'd9:  aScrollY  <= a[8:0];
                4'd10: aWrapX    <= a[4:0];
                4'd11: aWrapY    <= a[4:0];
                default: ;
            endcase
        // brTarget is read only while brPending is set, so it loads on every eGo and the branch
        // compares reach brPending alone
        if (eGo) brTarget <= target;
    end

    // slowR, DIV's quotient or SHLV, LOG2 and NORM's result, every clock by E's class: each reads it
    // the clock after the step that makes it, so the step need not pick the load.
    always_ff @(posedge clk)
        slowR <= eDiv  ? (divNeg ? -$signed(W'(divQ)) : $signed(W'(divQ))) :
                 eLog2 ? ((slowA > 0) ? $signed(W'(slowTop)) : $signed({W{1'b1}})) :
                         shiftBy(slowA, slowSh);

    // the alu2 ops' result, from their operands latched at step 0, every clock and picked by E's
    // class; taken at step 2
    logic signed [W-1:0] alu2Next;
    always_comb begin
        alu2Next = '0;
        if (eAlu2[0]) alu2Next |= (slowA < alu2B) ? slowA : alu2B;
        if (eAlu2[1]) alu2Next |= (slowA > alu2B) ? slowA : alu2B;
        if (eAlu2[2]) alu2Next |= slowA <<< alu2I[5:0];
        if (eAlu2[3]) alu2Next |= slowA >>> alu2I[5:0];
        if (eAlu2[4]) alu2Next |= -slowA;
        if (eAlu2[5]) alu2Next |= (slowA < 0) ? -slowA : slowA;
        if (eAlu2[6]) alu2Next |= W'($signed(slowA[15:0]));
        if (eAlu2[7]) alu2Next |= $signed(W'(wrap[slowA[4:0]]));
    end
    always_ff @(posedge clk) alu2R <= alu2Next;

    // ---- the store unit ---------------------------------------------------------------------------
    // A store's shift s is STV's and STVW's b + i, else i. Rounded half up, acc / 2^s is
    // (acc >>> (s - 1)) with its bit 0 added to the bits above, so U1 shifts by s - 1 (left by -s for
    // s <= 0, bit 0 then clear) and U2 adds. U1's registers load from E every clock and count only
    // with suV1, so stall is not their enable. A store issued at c reads the accumulator at c + 1:
    // the op before it has left M by then and the op after it has not.
    logic signed [7:0] stSh1;
    always_comb stSh1 = (o == STV || o == STVW) ? b[7:0] + imm[7:0] : imm[7:0];
    wire signed [AW-1:0] stRight = acc >>> stAmt;
    logic stRnd2;
    always_ff @(posedge clk) begin
        stLeft <= stSh1 <= 0;
        stAmt  <= (stSh1 <= 0) ? 7'(-stSh1) : 7'(stSh1 - 8'sd1);
        stRnd  <= o != STF;
        suD1   <= d;
        stT    <= stLeft ? {acc[47:0] << stAmt, 1'b0} : stRight[48:0];
        stRnd2 <= stRnd;
        suD2   <= suD1;
        mSuD   <= suD2;
    end
    always_ff @(posedge clk)
        if (reset) begin
            suV1 <= 1'b0;
            suV2 <= 1'b0;
            mSu  <= 1'b0;
        end else begin
            suV1 <= eGo && eSt && d != 0;
            suV2 <= suV1;
            mSu  <= suV2;
        end
    wire [W-1:0] stOut = stT[48:1] + W'(stRnd2 & stT[0]);

    // the multi-cycle result, by class: taken only on the clock the op completes
    logic signed [W-1:0] mcVal;
    always_comb begin
        mcVal = '0;
        if (eMc[0]) mcVal |= rdX;
        if (eMc[1]) mcVal |= W'(rsqV);
        if (eMc[2]) mcVal |= W'(rcpV);
        if (eMc[3]) mcVal |= W'(io_dlData);
        if (eMc[4]) mcVal |= W'(vWordPayload);
        if (eMc[5]) mcVal |= W'($signed(vWordPayload));
        if (eMc[6]) mcVal |= slowR;
        if (eMc[7]) mcVal |= alu2R;
    end
    always_ff @(posedge clk) begin
        mVal <= suV2 ? $signed(stOut) : mcVal | alu;
        if (eGo) begin
            prod   <= $signed(a[35:0]) * $signed(b[35:0]);
            accVal <= AW'(slowA) <<< accSh;
            mSh    <= imm[7:0];                                      // only ASHL uses it
        end
    end

    // ---- M ---------------------------------------------------------------------------------------
    wire  [8:0] mDst = fD(mInstr);
    logic signed [7:0] nMSh;
    always_comb nMSh = -mSh;
    logic signed [AW-1:0] accNext;
    always_comb begin
        accNext = acc;
        case (mulOp)
            2'd1: accNext = prod;
            2'd2: accNext = acc + prod;
            2'd3: accNext = acc - prod;
            default: ;
        endcase
        case (accOp)
            2'd1: accNext = accVal;
            2'd2: accNext = acc + accVal;
            2'd3: accNext = (mSh >= 0) ? (acc <<< mSh[6:0]) : (acc >>> nMSh[6:0]);
            default: ;
        endcase
    end

    // the one write port: the configuration at init, STX, or M (E's op or a store's result)
    logic        wrEn;
    logic  [8:0] wrAddr;
    logic signed [W-1:0] wrData;
    always_comb begin
        wrEn   = (mValid && mWrites && mDst != 0) || mSu;
        wrAddr = mSu ? mSuD : mDst;
        wrData = mVal;
        if (stxWrite) begin
            wrEn   = 1'b1;
            wrAddr = stxAddr;
            wrData = stxD;
        end
        if (cfgStep == 2'd1) begin
            wrEn   = 1'b1;
            wrAddr = 9'(GEO_REG_SAMSHO);
            wrData = W'(io_samsho);
        end
        if (cfgStep == 2'd2) begin
            wrEn   = 1'b1;
            wrAddr = 9'(GEO_REG_VLEN);
            wrData = W'(io_vlen);
        end
    end
    always_ff @(posedge clk)
        if (wrEn) begin
            rfA[wrAddr] <= wrData;
            rfB[wrAddr] <= wrData;
            rfX[wrAddr] <= wrData;
        end
    wire [8:0] rdAddrA = stall ? ra : fA(instrD);
    wire [8:0] rdAddrB = stall ? rb : fB(instrD);
    always_ff @(posedge clk) begin
        rdA  <= rfA[rdAddrA];
        rdB  <= rfB[rdAddrB];
        wReg <= wrAddr;
        wVal <= wrData;
    end

    // fwdSel: next clock's E instruction is the one read above; next clock's M is E if it goes (a
    // writing op), and next clock's W is this clock's register-file write. Worked out for both read
    // addresses (E's again on a stall, else D's) and picked by stall, so stall is the last select.
    wire mNextGo = eLive && eWrM;
    wire [8:0] dA = fA(instrD), dB = fB(instrD), dD = fD(instrD);
    // suHit: an op naming register r in a, b or d (d but a store's: the unit keeps their order), or
    // reading copy X (LDX, STX, EMIT: the register is a sum)
    function automatic logic suHit(input logic [5:0] op, input logic [8:0] fa, fb, fd, r);
        suHit = fa == r || fb == r || (!isSt(op) && fd == r) || op == LDX || op == STX || op == EMIT;
    endfunction

    // ---- the registers with a reset ------------------------------------------------------------------
    wire [10:0] entryPc = io_entry == 2'd0 ? 11'(GEO_ENTRY_INIT) :
                          io_entry == 2'd1 ? 11'(GEO_ENTRY_CLEAR) : 11'(GEO_ENTRY_UPLOAD);
    wire        startNow = io_start && !running && cfgStep == 2'd0;
    always_ff @(posedge clk)
        if (reset) begin
            running   <= 1'b0;
            cfgStep   <= '0;
            pcSeq     <= '0;
            brPending <= 1'b0;
            validD    <= 1'b0;
            validE    <= 1'b0;
            instrE    <= '0;
            mValid    <= 1'b0;
            mInstr    <= '0;
            mWrites   <= 1'b0;
            mAccOp    <= 1'b0;
            wValid    <= 1'b0;
            acc       <= '0;
            mulOp     <= '0;
            accOp     <= '0;
            {selMA, selMB, selWA, selWB, zeroA, zeroB} <= '0;
            brFwd     <= 1'b0;
            suHaz     <= 1'b0;
            bypX      <= 1'b0;
            retSp     <= '0;
        end else begin
            brPending <= goNotMc && taken;
            mValid    <= eGo;
            if (eGo) mInstr <= instrE;
            mWrites   <= eGo && (aluWrites || mcWrites);
            mulOp     <= '0;
            accOp     <= '0;
            mAccOp    <= 1'b0;
            if (eGo)
                case (o)
                    MUL:       begin mulOp <= 2'd1; mAccOp <= 1'b1; end
                    MAC:       begin mulOp <= 2'd2; mAccOp <= 1'b1; end
                    MSB:       begin mulOp <= 2'd3; mAccOp <= 1'b1; end
                    LDA:       begin accOp <= 2'd1; mAccOp <= 1'b1; end
                    ADA, ADAV: begin accOp <= 2'd2; mAccOp <= 1'b1; end
                    ASHL:      begin accOp <= 2'd3; mAccOp <= 1'b1; end
                    default: ;
                endcase
            acc    <= accNext;
            wValid <= wrEn;
            bypX   <= wrEn && wrAddr == xAddr && xAddr != 0;
            // M's next result: E's op if it goes, or the store in U2 (never both: portHaz)
            selMA  <= stall ? suV2 && suD2 == ra : (mNextGo && d == dA) || (suV2 && suD2 == dA);
            selMB  <= stall ? suV2 && suD2 == rb : (mNextGo && d == dB) || (suV2 && suD2 == dB);
            // a clock: in it E holds, M's result moves to W, and selWA or selWB is set for it
            brFwd  <= stall ? suV2 && regBr(o) && (suD2 == ra || (twoBr(o) && suD2 == rb)) :
                      regBr(dOp) && ((mNextGo && d != 0 && (d == dA || (twoBr(dOp) && d == dB))) ||
                                     (suV2 && (suD2 == dA || (twoBr(dOp) && suD2 == dB))));
            // the unit next clock: U2 holds U1's store, U1 the one E issues now
            suHaz  <= stall ? suV1 && suHit(o, ra, rb, d, suD1) :
                      (suV1 && suHit(dOp, dA, dB, dD, suD1)) || (eLive && eSt && d != 0 && suHit(dOp, dA, dB, dD, d));
            selWA  <= wrEn && (stall ? wrAddr == ra : wrAddr == dA);
            selWB  <= wrEn && (stall ? wrAddr == rb : wrAddr == dB);
            zeroA  <= stall ? ra == 0 : dA == 0;
            zeroB  <= stall ? rb == 0 : dB == 0;
            if (goNotMc && o == JAL) retSp <= retSp + 2'd1;
            if (goNotMc && o == RET) retSp <= retSp - 2'd1;
            if (goNotMc && o == HALT) running <= 1'b0;
            // the pc
            if (!stall) begin
                validD <= running;
                pcSeq  <= fetch + 11'd1;
                validE <= validD && !brPending;
                instrE <= instrD;
            end
            if (startNow) begin
                pcSeq   <= entryPc;
                validD  <= 1'b0;
                validE  <= 1'b0;
                retSp   <= '0;
                running <= 1'b1;
                if (io_entry == 2'd0) cfgStep <= 2'd1;
            end
            if (cfgStep == 2'd1) cfgStep <= 2'd2;
            if (cfgStep == 2'd2) cfgStep <= 2'd0;
        end
    always_ff @(posedge clk)
        if (!stall) begin
            pcD <= fetch;
            pcE <= pcD;
        end

    // ---- the vertex ROM stream: VSEEK restarts it at a word; reads run ahead, replies in order ------
    logic        seeked;
    logic [25:0] vReq;                      // the next beat's first word to request
    logic  [5:0] vDrop;                     // replies still owed to an older seek
    logic  [5:0] vOut;                      // requests in flight
    logic  [1:0] vSkip;                     // words of the head beat already used
    wire         seek = goNotMc && o == VSEEK;
    logic  [4:0] fifoAvail;
    logic        fifoPopValid;
    logic [63:0] fifoPopPayload;
    wire         room = fifoAvail > vOut[4:0];
    // a request goes out through a register: its valid follows E's stall logic through seek. One
    // held there is already counted in vOut, so a seek's vDrop covers it.
    wire         reqValid = seeked && room && !seek;
    wire  [27:0] reqPayload = io_vBase + 28'({vReq[25:2], 3'b000});
    logic        reqRValid;
    logic [27:0] reqRData;
    wire         reqReady = io_vRd_ready || !reqRValid;
    wire         reqFire = reqValid && reqReady;
    assign io_vRd_valid   = reqRValid;
    assign io_vRd_payload = reqRData;
    assign vWordValid     = fifoPopValid;
    assign vWordPayload   = fifoPopPayload[16 * vSkip +: 16];
    wire         vWordFire = vWordValid && vWordReady;
    wire  [25:0] seekW = a[25:0];
    always_ff @(posedge clk)
        if (reset) begin
            seeked    <= 1'b0;
            vDrop     <= '0;
            vOut      <= '0;
            vSkip     <= '0;
            reqRValid <= 1'b0;
        end else begin
            if (reqReady) reqRValid <= reqValid;
            vOut <= vOut + 6'(reqFire) - 6'(io_vData_valid);
            if (io_vData_valid && vDrop != 0) vDrop <= vDrop - 6'd1;
            if (vWordFire) vSkip <= vSkip + 2'd1;
            if (seek) begin
                seeked <= 1'b1;
                vSkip  <= seekW[1:0];
                vDrop  <= vOut - 6'(io_vData_valid);
            end
        end
    always_ff @(posedge clk) begin
        if (reqReady) reqRData <= reqPayload;
        if (reqFire) vReq <= vReq + 26'd4;
        if (seek) vReq <= {seekW[25:2], 2'b00};
    end

    hng64_geo_fifo u_vfifo (
        .clk(clk), .reset(reset), .flush(seek),
        .push_valid(io_vData_valid && vDrop == 0 && !seek), .push_payload(io_vData_payload),
        .pop_valid(fifoPopValid), .pop_ready(vWordFire && vSkip == 2'd3), .pop_payload(fifoPopPayload),
        .availability(fifoAvail));

    // ---- the triangle out: three records of x, y, z, 1/w, light/w, u/w, v/w and the attributes -----
    assign io_tri_valid          = triValid;
    assign io_tri_payload_v_0_0  = tV00;
    assign io_tri_payload_v_0_1  = tV01;
    assign io_tri_payload_v_1_0  = tV10;
    assign io_tri_payload_v_1_1  = tV11;
    assign io_tri_payload_v_2_0  = tV20;
    assign io_tri_payload_v_2_1  = tV21;
    assign io_tri_payload_neg    = tNeg;
    assign io_tri_payload_p0_v_0 = tP0_0;
    assign io_tri_payload_p0_v_1 = tP0_1;
    assign io_tri_payload_p0_v_2 = tP0_2;
    assign io_tri_payload_p0_v_3 = tP0_3;
    assign io_tri_payload_p0_v_4 = tP0_4;
    assign io_tri_payload_dx_v_0 = tDx_0;
    assign io_tri_payload_dx_v_1 = tDx_1;
    assign io_tri_payload_dx_v_2 = tDx_2;
    assign io_tri_payload_dx_v_3 = tDx_3;
    assign io_tri_payload_dx_v_4 = tDx_4;
    assign io_tri_payload_dy_v_0 = tDy_0;
    assign io_tri_payload_dy_v_1 = tDy_1;
    assign io_tri_payload_dy_v_2 = tDy_2;
    assign io_tri_payload_dy_v_3 = tDy_3;
    assign io_tri_payload_dy_v_4 = tDy_4;
    assign io_tri_payload_attr   = tAttr;

endmodule

// The vertex words' FIFO: 16 beats, the read registered (a pop is out the clock after its address),
// the occupancy against the last beat popped. As SpinalHDL's StreamFifo, which it was.
module hng64_geo_fifo (
    input  wire         clk,
    input  wire         reset,
    input  wire         flush,
    input  wire         push_valid,
    input  wire  [63:0] push_payload,
    output wire         pop_valid,
    input  wire         pop_ready,
    output wire  [63:0] pop_payload,
    output wire   [4:0] availability
);
    logic [63:0] ram [0:15];
    logic  [4:0] pushPtr, popPtr, popReg;
    logic        rValid;
    logic [63:0] rdata;
    wire         full  = ((pushPtr ^ popReg) ^ 5'h10) == 5'h0;
    wire         empty = pushPtr == popPtr;
    wire  [4:0]  occupancy = pushPtr - popReg;
    wire         doPush = push_valid && !full;
    wire         genReady = pop_ready || !rValid;   // the address stage moves when its slot frees
    wire         doPop = !empty && genReady;
    assign pop_valid    = rValid;
    assign pop_payload  = rdata;
    assign availability = 5'h10 - occupancy;
    always_ff @(posedge clk) begin
        if (doPush) ram[pushPtr[3:0]] <= push_payload;
        if (doPop) rdata <= ram[popPtr[3:0]];
    end
    always_ff @(posedge clk)
        if (reset) begin
            pushPtr <= '0;
            popPtr  <= '0;
            rValid  <= 1'b0;
            popReg  <= '0;
        end else begin
            if (doPush) pushPtr <= pushPtr + 5'd1;
            if (doPop) popPtr <= popPtr + 5'd1;
            if (genReady) rValid <= !empty;
            if (rValid && pop_ready) popReg <= popPtr;
            if (flush) begin
                pushPtr <= '0;
                popPtr  <= '0;
                rValid  <= 1'b0;
                popReg  <= '0;
            end
        end
endmodule

`default_nettype wire
