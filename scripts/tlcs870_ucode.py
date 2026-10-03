#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the TLCS-870 core's microcode ROM and opcode dispatch.

    python scripts/tlcs870_ucode.py        # writes rtl/io/hng64_tlcs870_ucode.sv and .hex

rtl/io/hng64_tlcs870.sv runs every instruction's execute phase from this ROM: one word a step,
the step sequences each instruction family had as hand-written logic, with the same bus timing
(a read issued at step S has its data at S+2). The dispatch gives, for a (prefix family, opcode
byte), the program's address, the operand bytes to fetch and MAME's cycle count.

The field codes below are the ones hng64_tlcs870.sv decodes; change both together.
"""
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "rtl" / "io" / "hng64_tlcs870_ucode.sv"
HEX = REPO / "rtl" / "io" / "hng64_tlcs870_ucode.hex"

# ---- field codes --------------------------------------------------------------------------------
BUS = dict(N=0, RD=1, RDX=2, WR=3)
ASEL = dict(REG=0, IMM0=1, IMM0P1=2, IMM1=3, T16=4, T16P1=5, EA=6, EAP1=7,
            SP=8, SPM1=9, SPP1=10, SPP2=11, SPP3=12, DT16=13)
# register index: 0-7 a fixed register (A W C B E D L H), or from the opcode bytes
RSEL = dict(A=0, W=1, C=2, L=6, H=7, R0=8, RR0L=9, RR0H=10, R1=11, RR1L=12, RR1H=13,
            PPL=14, PPH=15)
WSEL = dict(DIN=0, TMP8=1, IMM0=2, IMM1=3, IMM2=4, ZERO=5, ALUL=6, ALUH=7, SHR=8, PSW=9,
            PCL=10, PCH=11, T16L=12, T16H=13, EAL=14, EAH=15, ACCL=16, SPL=17, SPH=18,
            BIT=19, ROT0=20, ROT1=21, INC16L=22, DEC16L=23)
LD = dict(N=0, T8_DIN=1, T8_INC=2, T8_DEC=3, T8_ANDIMM=4, T8_BITPOS=5, T16L_DIN=6,
          T16H_DIN=7, EAL_DIN=8, EAH_DIN=9, SH=10, ALU_DIN_IMM0=11, ALU_T8_DIN=12,
          ALU_T16_EA=13, ALU_T16_IMM=14, MUL_INIT=15, DIV_T16H=16, DIV_INIT=17,
          EA_INC16=18, EA_DEC16=19, ROT0=20, ROT1=21, SPL_DIN=22, SPH_DIN=23)
FLAG = dict(KEEP=0, J=1, LDZ_DIN=2, LDZ_T8=3, ALU=4, SH=5, INC_T8=6, DEC_T8=7, BITZ=8,
            LDCF=9, XORCF=10, CLRCF=11, SETCF=12, CPLCF=13, DIVF=14, INC16=15, DEC16=16,
            MCMP=17, PSW_DIN=18, RBS_IMM=19)
SPOP = dict(N=0, M1=1, M2=2, M3=3, P1=4, P2=5, P3=6, IMM=7)
PCOP = dict(N=0, T16=1, DIN_T8=2, IMM=3, JRC=4, JRS=5, JRU=6, CALLV=7, FFIMM=8, DIN_T16L=9)
SEQ = dict(NEXT=0, FIN=1, MUL=2, DIV=3)
MISC = dict(N=0, EIR0=1, SWI=2, UNIMPL=3, CHKE8=4)
ALUSRC = dict(OP0=0, OP1=1)
BOP = dict(SET=0, CLR=1, CPL=2, LDCF=3)
MSEL = dict(OP0=0, OP1=1, T8=2)
BSRC = dict(DIN=0, T8=1)

FIELDS = [  # name, width, codes; packed from bit 0 upwards in this order
    ("bus", 2, BUS), ("asel", 4, ASEL), ("rsel", 4, RSEL), ("wsel", 5, WSEL), ("ld", 5, LD),
    ("flag", 5, FLAG), ("sp", 3, SPOP), ("pc", 4, PCOP), ("seq", 2, SEQ), ("misc", 3, MISC),
    ("alusrc", 1, ALUSRC), ("bop", 2, BOP), ("msel", 2, MSEL), ("bsrc", 1, BSRC), ("shop", 3, None),
]
WIDTH = sum(w for _, w, _ in FIELDS)


def S(**kw):
    """One step. Unnamed fields are zero (no bus, keep, next)."""
    return kw


def rd(a, r=None, x=False, **kw):
    s = dict(bus="RDX" if x else "RD", asel=a, **kw)
    if r is not None:
        s["rsel"] = r
    return s


def wr(a, w, r=None, **kw):
    s = dict(bus="WR", asel=a, wsel=w, **kw)
    if r is not None:
        s["rsel"] = r
    return s


def fin(**kw):
    return dict(seq="FIN", **kw)


def enc(step):
    v, pos = 0, 0
    for name, w, codes in FIELDS:
        x = step.get(name, 0)
        if isinstance(x, str):
            x = codes[x]
        assert 0 <= x < (1 << w), (name, x)
        v |= x << pos
        pos += w
    for k in step:
        assert k in [f[0] for f in FIELDS], k
    return v


# ---- the programs ---------------------------------------------------------------------------------
P = {}


def prog(name, *steps):
    P[name] = list(steps)
    return name


WAIT = S()

# a register read into the ALU and back, 8-bit, with and without the write (CMP is op 7)
def alu8_reg_imm(name, reg, src, cmp):
    return prog(name, rd("REG", reg), WAIT, S(ld="ALU_DIN_IMM0", alusrc=src),
                fin(flag="ALU") if cmp else wr("REG", "ALUL", reg, flag="ALU", seq="FIN"))


# -- no prefix
NOP = prog("nop", fin())
for op, sh in ((0x01, 6), (0x0a, 4), (0x0b, 5)):
    prog(f"sh_a_{op:02x}", rd("REG", "A"), WAIT, S(ld="SH", shop=sh),
         wr("REG", "SHR", "A", flag="SH", seq="FIN"))
for k in range(4):
    prog(f"shc_a_{k}", rd("REG", "A"), WAIT, S(ld="SH", shop=k),
         wr("REG", "SHR", "A", flag="SH", seq="FIN"))


def mul(name, lo, hi):
    return prog(name, rd("REG", lo), rd("REG", hi), S(ld="T8_DIN"), S(ld="MUL_INIT"), S(seq="MUL"))


def div(name, lo, hi):
    return prog(name, rd("REG", lo), rd("REG", hi), rd("REG", "C", ld="T8_DIN"),
                S(ld="DIV_T16H"), S(ld="DIV_INIT"), S(seq="DIV", rsel=lo),
                wr("REG", "ACCL", hi, flag="DIVF", seq="FIN"))


mul("mul_wa", "A", "W")
div("div_wa", "A", "W")
prog("reti", rd("SPP1"), rd("SPP2"), rd("SPP3", ld="T16L_DIN"), S(ld="T16H_DIN"),
     fin(flag="PSW_DIN", pc="T16", sp="P3", misc="EIR0"))
prog("ret", rd("SPP1"), rd("SPP2"), S(ld="T8_DIN"), fin(pc="DIN_T8", sp="P2"))
prog("pop_psw", rd("SPP1"), WAIT, fin(flag="PSW_DIN", sp="P1"))
prog("push_psw", wr("SP", "PSW", sp="M1", seq="FIN"))
prog("clr_cf", fin(flag="CLRCF"))
prog("set_cf", fin(flag="SETCF"))
prog("cpl_cf", fin(flag="CPLCF"))
prog("ld_rbs", fin(flag="RBS_IMM"))
for dec in (0, 1):
    prog(f"incdec_rr_{dec}", rd("REG", "RR0L"), rd("REG", "RR0H"), S(ld="T16L_DIN"),
         S(ld="T16H_DIN"),
         wr("REG", "DEC16L" if dec else "INC16L", "RR0L", ld="EA_DEC16" if dec else "EA_INC16"),
         wr("REG", "EAH", "RR0H", flag="DEC16" if dec else "INC16", seq="FIN"))
prog("ld_rr_mn", wr("REG", "IMM0", "RR0L"), wr("REG", "IMM1", "RR0H", flag="J", seq="FIN"))
for dec in (0, 1):
    t8, fl = ("T8_DEC", "DEC_T8") if dec else ("T8_INC", "INC_T8")
    prog(f"incdec_x_{dec}", rd("IMM0"), WAIT, S(ld=t8), wr("IMM0", "TMP8", flag=fl, seq="FIN"))
    prog(f"incdec_hl_{dec}", rd("REG", "L"), rd("REG", "H"), S(ld="T16L_DIN"),
         S(ld="T16H_DIN"), rd("T16"), WAIT, S(ld=t8), wr("T16", "TMP8", flag=fl, seq="FIN"))
    prog(f"incdec_r_{dec}", rd("REG", "R0"), WAIT, S(ld=t8),
         wr("REG", "TMP8", "R0", flag=fl, seq="FIN"))
    prog(f"incdec_src_{dec}", rd("EA"), WAIT, S(ld=t8), wr("EA", "TMP8", flag=fl, seq="FIN"))
prog("ld_a_x", rd("IMM0"), WAIT, wr("REG", "DIN", "A", flag="LDZ_DIN", seq="FIN"))
HL = [rd("REG", "L"), rd("REG", "H"), S(ld="T16L_DIN"), S(ld="T16H_DIN")]
prog("ld_a_hl", *HL, rd("T16"), WAIT, wr("REG", "DIN", "A", flag="LDZ_DIN", seq="FIN"))
prog("ldw_x_mn", wr("IMM0", "IMM1"), wr("IMM0P1", "IMM2", flag="J", seq="FIN"))
prog("ldw_hl_mn", *HL, wr("T16", "IMM0"), wr("T16P1", "IMM1", flag="J", seq="FIN"))
prog("ld_x_y", rd("IMM0"), WAIT, S(ld="T8_DIN"), wr("IMM1", "TMP8", flag="LDZ_T8", seq="FIN"))
prog("ld_x_a", rd("REG", "A"), WAIT, wr("IMM0", "DIN", flag="LDZ_DIN", seq="FIN"))
prog("ld_hl_a", rd("REG", "L"), rd("REG", "H"), rd("REG", "A", ld="T16L_DIN"),
     S(ld="T16H_DIN"), wr("T16", "DIN", flag="J", seq="FIN"))
prog("ld_x_n", wr("IMM0", "IMM1", flag="J", seq="FIN"))
prog("ld_hl_n", *HL, wr("T16", "IMM0", flag="J", seq="FIN"))
prog("clr_hl", *HL, wr("T16", "ZERO", flag="J", seq="FIN"))
prog("clr_x", wr("IMM0", "ZERO", flag="J", seq="FIN"))
prog("ld_r_n", wr("REG", "IMM0", "R0", flag="J", seq="FIN"))
for clr in (0, 1):
    prog(f"setclr_x_{clr}", rd("IMM0", x=True), WAIT, S(ld="T8_DIN"),
         wr("IMM0", "BIT", bop="CLR" if clr else "SET", msel="OP0", bsrc="T8",
            flag="BITZ", seq="FIN"))
prog("ld_a_r", rd("REG", "R0"), WAIT, wr("REG", "DIN", "A", flag="LDZ_DIN", seq="FIN"))
prog("ld_r_a", rd("REG", "A"), WAIT, wr("REG", "DIN", "R0", flag="LDZ_DIN", seq="FIN"))
for cmp in (0, 1):
    alu8_reg_imm(f"alu_a_n_{cmp}", "A", "OP0", cmp)
    prog(f"alu_a_x_{cmp}", rd("REG", "A"), rd("IMM0"), S(ld="T8_DIN"),
         S(ld="ALU_T8_DIN", alusrc="OP0"),
         fin(flag="ALU") if cmp else wr("REG", "ALUL", "A", flag="ALU", seq="FIN"))
prog("jrs", fin(pc="JRS", flag="J"))
prog("callv", wr("SPM1", "PCL"), wr("SP", "PCH", sp="M2", pc="CALLV", seq="FIN"))
prog("jr_cc", fin(pc="JRC", flag="J"))
prog("ld_cf_x", rd("IMM0"), WAIT, fin(flag="LDCF", msel="OP0", bsrc="DIN"))
prog("ld_sp_mn", fin(sp="IMM", flag="J"))
prog("jr", fin(pc="JRU", flag="J"))
prog("call_mn", wr("SPM1", "PCL"), wr("SP", "PCH", sp="M2", pc="IMM", seq="FIN"))
prog("callp", wr("SPM1", "PCL"), wr("SP", "PCH", sp="M2", pc="FFIMM", seq="FIN"))
prog("jp_mn", fin(pc="IMM", flag="J"))
prog("swi", fin(misc="SWI"))
prog("unimpl", fin(misc="UNIMPL"))

# -- register prefix: g is op0[2:0], gg op0[1:0]; the second byte names the operation
for op, sh in ((0x01, 6), (0x0a, 4), (0x0b, 5)):
    prog(f"sh_g_{op:02x}", rd("REG", "R0"), WAIT, S(ld="SH", shop=sh),
         wr("REG", "SHR", "R0", flag="SH", seq="FIN"))
for k in range(4):
    prog(f"shc_g_{k}", rd("REG", "R0"), WAIT, S(ld="SH", shop=k),
         wr("REG", "SHR", "R0", flag="SH", seq="FIN"))
mul("mul_gg", "RR0L", "RR0H")
div("div_gg", "RR0L", "RR0H")
# RETN is 0xe8 0x04 only; MAME reads the PSW from sp+2, the return address's high byte
prog("retn", rd("SPP1", misc="CHKE8"), rd("SPP2"), S(ld="T8_DIN"),
     fin(pc="DIN_T8", flag="PSW_DIN", sp="P3"))
prog("pop_gg", rd("SPP1"), rd("SPP2"), S(ld="T8_DIN"), wr("REG", "TMP8", "RR0L", ld="T8_DIN"),
     wr("REG", "TMP8", "RR0H", sp="P2", seq="FIN"))
prog("push_gg", rd("REG", "RR0L"), rd("REG", "RR0H"), S(ld="T8_DIN"),
     wr("SPM1", "TMP8", ld="T8_DIN"), wr("SP", "TMP8", sp="M2", seq="FIN"))
prog("xch_rr_gg", rd("REG", "RR0L"), rd("REG", "RR0H"), rd("REG", "RR1L", ld="T16L_DIN"),
     rd("REG", "RR1H", ld="T16H_DIN"), S(ld="EAL_DIN"), S(ld="EAH_DIN"),
     wr("REG", "T16L", "RR1L"), wr("REG", "T16H", "RR1H"), wr("REG", "EAL", "RR0L"),
     wr("REG", "EAH", "RR0H", flag="J", seq="FIN"))
prog("ld_rr_gg", rd("REG", "RR0L"), rd("REG", "RR0H"), S(ld="T8_DIN"),
     wr("REG", "TMP8", "RR1L", ld="T8_DIN"), wr("REG", "TMP8", "RR1H", flag="J", seq="FIN"))
for cmp in (0, 1):
    prog(f"alu_wa_gg_{cmp}", rd("REG", "A"), rd("REG", "W"), rd("REG", "RR0L", ld="T16L_DIN"),
         rd("REG", "RR0H", ld="T16H_DIN"), S(ld="EAL_DIN"), S(ld="EAH_DIN"),
         S(ld="ALU_T16_EA", alusrc="OP1"),
         S(flag="ALU") if cmp else wr("REG", "ALUL", "A", flag="ALU"),
         fin() if cmp else wr("REG", "ALUH", "W", seq="FIN"))
    prog(f"alu_gg_mn_{cmp}", rd("REG", "RR0L"), rd("REG", "RR0H"), S(ld="T16L_DIN"),
         S(ld="T16H_DIN"), S(ld="ALU_T16_IMM", alusrc="OP1"),
         S(flag="ALU") if cmp else wr("REG", "ALUL", "RR0L", flag="ALU"),
         fin() if cmp else wr("REG", "ALUH", "RR0H", seq="FIN"))
    prog(f"alu_a_g_{cmp}", rd("REG", "A"), rd("REG", "R0"), S(ld="T8_DIN"),
         S(ld="ALU_T8_DIN", alusrc="OP1"),
         fin(flag="ALU") if cmp else wr("REG", "ALUL", "A", flag="ALU", seq="FIN"))
    prog(f"alu_g_a_{cmp}", rd("REG", "R0"), rd("REG", "A"), S(ld="T8_DIN"),
         S(ld="ALU_T8_DIN", alusrc="OP1"),
         fin(flag="ALU") if cmp else wr("REG", "ALUL", "R0", flag="ALU", seq="FIN"))
    alu8_reg_imm(f"alu_g_n_{cmp}", "R0", "OP1", cmp)
for b in ("SET", "CLR", "CPL"):
    prog(f"bit_g_{b}", rd("REG", "R0"), WAIT, S(ld="T8_DIN"),
         wr("REG", "BIT", "R0", bop=b, msel="OP1", bsrc="T8", flag="BITZ", seq="FIN"))
prog("ld_r_g", rd("REG", "R0"), WAIT, wr("REG", "DIN", "R1", flag="LDZ_DIN", seq="FIN"))
PP = [rd("REG", "R0"), rd("REG", "PPL"), rd("REG", "PPH", ld="T8_BITPOS"), S(ld="T16L_DIN"),
      S(ld="T16H_DIN")]
for b in ("SET", "CLR", "CPL"):
    prog(f"bit_pp_{b}", *PP, rd("T16", x=(b != "SET")), WAIT,
         wr("T16", "BIT", bop=b, msel="T8", bsrc="DIN", flag="BITZ", seq="FIN"))
prog("ldcf_pp", *PP, rd("T16"), WAIT, fin(flag="LDCF", msel="T8", bsrc="DIN"))
prog("ld_pp_cf", *PP, rd("T16"), WAIT,
     wr("T16", "BIT", bop="LDCF", msel="T8", bsrc="DIN", flag="J", seq="FIN"))
prog("xch_r_g", rd("REG", "R0"), rd("REG", "R1"), S(ld="T8_DIN"),
     wr("REG", "TMP8", "R1", ld="T16L_DIN"), wr("REG", "T16L", "R0", flag="LDZ_T8", seq="FIN"))
prog("ld_g_cf", rd("REG", "R0"), WAIT,
     wr("REG", "BIT", "R0", bop="LDCF", msel="OP1", bsrc="DIN", flag="J", seq="FIN"))
prog("xorcf_g", rd("REG", "R0"), WAIT, fin(flag="XORCF", msel="OP1", bsrc="DIN"))
prog("ldcf_g", rd("REG", "R0"), WAIT, fin(flag="LDCF", msel="OP1", bsrc="DIN"))
prog("ld_sp_gg", rd("REG", "RR0L"), rd("REG", "RR0H"), S(ld="SPL_DIN"),
     fin(ld="SPH_DIN", flag="J"))
prog("ld_gg_sp", wr("REG", "SPL", "RR0L"), wr("REG", "SPH", "RR0H", flag="J", seq="FIN"))
GG = [rd("REG", "RR0L"), rd("REG", "RR0H"), S(ld="T16L_DIN"), S(ld="T16H_DIN")]
prog("call_gg", *GG, wr("SPM1", "PCL"), wr("SP", "PCH", sp="M2", pc="T16", seq="FIN"))
prog("jp_gg", *GG, fin(pc="T16", flag="J"))

# -- destination prefix: P_EA has put the address in ea
prog("ld_dst_rr", rd("REG", "RR1L"), rd("REG", "RR1H"), S(ld="T8_DIN"),
     wr("EA", "TMP8", ld="T8_DIN"), wr("EAP1", "TMP8", flag="J", seq="FIN"))
prog("ld_dst_n", wr("EA", "IMM0", flag="J", seq="FIN"))
prog("ld_dst_r", rd("REG", "R1"), WAIT, wr("EA", "DIN", flag="J", seq="FIN"))

# -- source prefix: P_EA has put the address in ea
for k in (0, 1):
    prog(f"rot_{k}", rd("EA"), rd("REG", "A"), S(ld="T8_DIN"),
         wr("REG", f"ROT{k}", "A", ld=f"ROT{k}"), wr("EA", "TMP8", flag="J", seq="FIN"))
prog("ld_rr_src", rd("EA"), rd("EAP1"), S(ld="T8_DIN"), wr("REG", "TMP8", "RR1L", ld="T8_DIN"),
     wr("REG", "TMP8", "RR1H", flag="J", seq="FIN"))
prog("ld_x_src", rd("EA"), WAIT, wr("IMM0", "DIN", flag="J", seq="FIN"))
prog("ld_hl_src", rd("EA"), rd("REG", "L"), rd("REG", "H", ld="T8_DIN"), S(ld="T16L_DIN"),
     wr("DT16", "TMP8", flag="LDZ_T8", seq="FIN"))
prog("mcmp", rd("EA"), rd("REG", "A"), S(ld="T8_ANDIMM"), fin(flag="MCMP"))
for b in ("SET", "CLR", "CPL"):
    prog(f"bit_src_{b}", rd("EA", x=True), WAIT, S(ld="T8_DIN"),
         wr("EA", "BIT", bop=b, msel="OP1", bsrc="T8", flag="BITZ", seq="FIN"))
prog("ld_r_src", rd("EA"), WAIT, wr("REG", "DIN", "R1", flag="LDZ_DIN", seq="FIN"))
for cmp in (0, 1):
    prog(f"alu_src_hl_{cmp}", rd("EA", x=not cmp), rd("REG", "L"), rd("REG", "H", ld="T8_DIN"),
         S(ld="T16L_DIN"), rd("DT16", ld="T16H_DIN"), WAIT, S(ld="ALU_T8_DIN", alusrc="OP1"),
         fin(flag="ALU") if cmp else wr("EA", "ALUL", flag="ALU", seq="FIN"))
    prog(f"alu_src_n_{cmp}", rd("EA", x=not cmp), WAIT, S(ld="ALU_DIN_IMM0", alusrc="OP1"),
         fin(flag="ALU") if cmp else wr("EA", "ALUL", flag="ALU", seq="FIN"))
    prog(f"alu_a_src_{cmp}", rd("REG", "A"), rd("EA"), S(ld="T8_DIN"),
         S(ld="ALU_T8_DIN", alusrc="OP1"),
         fin(flag="ALU") if cmp else wr("REG", "ALUL", "A", flag="ALU", seq="FIN"))
prog("xch_r_src", rd("EA", x=True), rd("REG", "R1"), S(ld="T8_DIN"), wr("EA", "DIN"),
     wr("REG", "TMP8", "R1", flag="LDZ_T8", seq="FIN"))
prog("ld_src_cf", rd("EA", x=True), WAIT,
     wr("EA", "BIT", bop="LDCF", msel="OP1", bsrc="DIN", flag="J", seq="FIN"))
prog("xorcf_src", rd("EA"), WAIT, fin(flag="XORCF", msel="OP1", bsrc="DIN"))
prog("ldcf_src", rd("EA"), WAIT, fin(flag="LDCF", msel="OP1", bsrc="DIN"))
SRC2 = [rd("EA"), rd("EAP1"), S(ld="T16L_DIN")]
prog("call_src", *SRC2, wr("SPM1", "PCL", ld="T16H_DIN"),
     wr("SP", "PCH", sp="M2", pc="T16", seq="FIN"))
prog("jp_src", *SRC2, fin(pc="DIN_T16L", flag="J"))


# ---- dispatch: (family, byte) -> program, operand bytes, cycles ---------------------------------
# families: 0 no prefix, 1 register prefix (e8-ef), 2 source prefix (e0-e7), 3 destination (f0-f7)
# The cycle counts are the handlers' own (as the hand-written decode had them); for the source and
# destination families the address mode's base cycles are added in hng64_tlcs870.sv.
def d_base(o):
    imm, cyc = 0, 1
    if o == 0x00: return NOP, 0, 1
    if o in (0x01, 0x0a, 0x0b): return f"sh_a_{o:02x}", 0, {0x01: 3, 0x0a: 2, 0x0b: 2}[o]
    if o == 0x02: return "mul_wa", 0, 7
    if o == 0x03: return "div_wa", 0, 7
    if o == 0x04: return "reti", 0, 6
    if o == 0x05: return "ret", 0, 6
    if o == 0x06: return "pop_psw", 0, 3
    if o == 0x07: return "push_psw", 0, 2
    if o == 0x0c: return "clr_cf", 0, 1
    if o == 0x0d: return "set_cf", 0, 1
    if o == 0x0e: return "cpl_cf", 0, 1
    if o == 0x0f: return "ld_rbs", 1, 4
    if o & 0xfc == 0x10: return "incdec_rr_0", 0, 2
    if o & 0xfc == 0x18: return "incdec_rr_1", 0, 2
    if o & 0xfc == 0x14: return "ld_rr_mn", 2, 3
    if o & 0xfc == 0x1c: return f"shc_a_{o & 3}", 0, 1
    if o in (0x20, 0x28): return f"incdec_x_{(o >> 3) & 1}", 1, 5
    if o in (0x21, 0x29): return f"incdec_hl_{(o >> 3) & 1}", 0, 4
    if o == 0x22: return "ld_a_x", 1, 3
    if o == 0x23: return "ld_a_hl", 0, 2
    if o == 0x24: return "ldw_x_mn", 3, 6
    if o == 0x25: return "ldw_hl_mn", 2, 5
    if o == 0x26: return "ld_x_y", 2, 5
    if o == 0x2a: return "ld_x_a", 1, 3
    if o == 0x2b: return "ld_hl_a", 0, 2
    if o == 0x2c: return "ld_x_n", 2, 4
    if o == 0x2d: return "ld_hl_n", 1, 3
    if o == 0x2e: return "clr_x", 1, 4
    if o == 0x2f: return "clr_hl", 0, 2
    if o & 0xf8 == 0x30: return "ld_r_n", 1, 2
    if o & 0xf0 == 0x40: return f"setclr_x_{(o >> 3) & 1}", 1, 5
    if o & 0xf8 == 0x50: return "ld_a_r", 0, 1
    if o & 0xf8 == 0x58: return "ld_r_a", 0, 1
    if o & 0xf0 == 0x60: return f"incdec_r_{(o >> 3) & 1}", 0, 1
    if o & 0xf8 == 0x70: return f"alu_a_n_{int(o & 7 == 7)}", 1, 2
    if o & 0xf8 == 0x78: return f"alu_a_x_{int(o & 7 == 7)}", 1, 4
    if o & 0xc0 == 0x80: return "jrs", 0, 2
    if o & 0xf0 == 0xc0: return "callv", 0, 7
    if o & 0xf8 == 0xd0: return "jr_cc", 1, 2
    if o & 0xf8 == 0xd8: return "ld_cf_x", 1, 4
    if o == 0xfa: return "ld_sp_mn", 2, 3
    if o == 0xfb: return "jr", 1, 4
    if o == 0xfc: return "call_mn", 2, 6
    if o == 0xfd: return "callp", 1, 6
    if o == 0xfe: return "jp_mn", 2, 4
    if o == 0xff: return "swi", 0, 9
    return "unimpl", 0, 1


def d_reg(o):
    if o in (0x01, 0x0a, 0x0b): return f"sh_g_{o:02x}", 0, {0x01: 4, 0x0a: 3, 0x0b: 3}[o]
    if o == 0x02: return "mul_gg", 0, 8
    if o == 0x03: return "div_gg", 0, 8
    if o == 0x04: return "retn", 0, 7
    if o == 0x06: return "pop_gg", 0, 5
    if o == 0x07: return "push_gg", 0, 4
    if o & 0xfc == 0x10: return "xch_rr_gg", 0, 3
    if o & 0xfc == 0x14: return "ld_rr_gg", 0, 2
    if o & 0xfc == 0x1c: return f"shc_g_{o & 3}", 0, 2
    if o & 0xf8 == 0x30: return f"alu_wa_gg_{int(o & 7 == 7)}", 0, 4
    if o & 0xf8 == 0x38: return f"alu_gg_mn_{int(o & 7 == 7)}", 2, 4
    if o & 0xf0 == 0x40: return f"bit_g_{'CLR' if o & 8 else 'SET'}", 0, 3
    if o & 0xf8 == 0x58: return "ld_r_g", 0, 2
    if o & 0xf8 == 0x60: return f"alu_a_g_{int(o & 7 == 7)}", 0, 2
    if o & 0xf8 == 0x68: return f"alu_g_a_{int(o & 7 == 7)}", 0, 3
    if o & 0xf8 == 0x70: return f"alu_g_n_{int(o & 7 == 7)}", 1, 3
    if o in (0x82, 0x83): return "bit_pp_SET", 0, 5
    if o in (0x8a, 0x8b): return "bit_pp_CLR", 0, 5
    if o in (0x92, 0x93): return "bit_pp_CPL", 0, 5
    if o in (0x9a, 0x9b): return "ld_pp_cf", 0, 5
    if o in (0x9e, 0x9f): return "ldcf_pp", 0, 4
    if o & 0xf8 == 0xa8: return "xch_r_g", 0, 3
    if o & 0xf8 == 0xc0: return "bit_g_CPL", 0, 3
    if o & 0xf8 == 0xc8: return "ld_g_cf", 0, 2
    if o & 0xf8 == 0xd0: return "xorcf_g", 0, 2
    if o & 0xf8 == 0xd8: return "ldcf_g", 0, 2
    if o == 0xfa: return "ld_sp_gg", 0, 3
    if o == 0xfb: return "ld_gg_sp", 0, 3
    if o == 0xfc: return "call_gg", 0, 6
    if o == 0xfe: return "jp_gg", 0, 3
    return "unimpl", 0, 1


def d_src(o):
    if o in (0x08, 0x09): return f"rot_{o & 1}", 0, 7
    if o & 0xfc == 0x14: return "ld_rr_src", 0, 4
    if o in (0x20, 0x28): return f"incdec_src_{(o >> 3) & 1}", 0, 4
    if o == 0x26: return "ld_x_src", 1, 5
    if o == 0x27: return "ld_hl_src", 0, 4
    if o == 0x2f: return "mcmp", 1, 5
    if o & 0xf0 == 0x40: return f"bit_src_{'CLR' if o & 8 else 'SET'}", 0, 4
    if o & 0xf8 == 0x58: return "ld_r_src", 0, 3
    if o & 0xf8 == 0x60: return f"alu_src_hl_{int(o & 7 == 7)}", 0, 6 if o & 7 == 7 else 5
    if o & 0xf8 == 0x70: return f"alu_src_n_{int(o & 7 == 7)}", 1, 5 if o & 7 == 7 else 4
    if o & 0xf8 == 0x78: return f"alu_a_src_{int(o & 7 == 7)}", 0, 3
    if o & 0xf8 == 0xa8: return "xch_r_src", 0, 4
    if o & 0xf8 == 0xc0: return "bit_src_CPL", 0, 4
    if o & 0xf8 == 0xc8: return "ld_src_cf", 0, 4
    if o & 0xf8 == 0xd0: return "xorcf_src", 0, 3
    if o & 0xf8 == 0xd8: return "ldcf_src", 0, 3
    if o == 0xfc: return "call_src", 0, 8
    if o == 0xfe: return "jp_src", 0, 5
    return NOP, 0, 1                                    # MAME logs it and does nothing


def d_dst(o):
    if o & 0xfc == 0x10: return "ld_dst_rr", 0, 4
    if o == 0x2c: return "ld_dst_n", 1, 4
    # MAME's dispatch (tlcs870_ops_dst.cpp) takes LD (dst),r at 0x50-0x57; the comment table beside
    # it says 0101 1rrr, and the decode followed that until the IO MCU's own `ld (HL),D` (f3 55,
    # 0xc53b) did nothing and Start never reached the main CPU
    if o & 0xf8 == 0x50: return "ld_dst_r", 0, 3
    return NOP, 0, 1


def main():
    # place the programs, sharing identical ones
    addr, words, seen = {}, [], {}
    for name, steps in P.items():
        code = tuple(enc(s) for s in steps)
        if code in seen:
            addr[name] = seen[code]
            continue
        addr[name] = seen[code] = len(words)
        words.extend(code)
    assert len(words) <= 1024, len(words)
    disp = []
    for fam, fn in enumerate((d_base, d_reg, d_src, d_dst)):
        for o in range(256):
            name, imm, cyc = fn(o)
            assert cyc < 32 and imm < 4
            disp.append((addr[name], imm, cyc))

    W = WIDTH
    lines = [
        "// SPDX-License-Identifier: GPL-3.0-or-later",
        "//",
        "// GENERATED by scripts/tlcs870_ucode.py; edit that, not this.",
        "//",
        f"// The TLCS-870 core's microcode ({len(words)} words of {W} bits, {len(P)} programs) and its",
        "// opcode dispatch. Field layout and codes: the script.",
        "",
        "module hng64_tlcs870_ucode (",
        "    input  logic        clk,",
        "    input  logic  [9:0] uaddr,          // read: the word is out the clock after",
        f"    output logic [{W - 1}:0] uword,",
        "    input  logic  [1:0] fam,            // 0 none, 1 register, 2 source, 3 destination prefix",
        "    input  logic  [7:0] op,",
        "    output logic  [9:0] entry,",
        "    output logic  [1:0] imm,",
        "    output logic  [4:0] cyc",
        ");",
        "",
        "    // an M10K ROM from the hex file: written as a case statement it was built in logic",
        f"    (* romstyle = \"M10K\" *) logic [{W - 1}:0] rom [0:1023];",
        f"    initial $readmemh(\"rtl/io/{HEX.name}\", rom);",
        "    always_ff @(posedge clk) uword <= rom[uaddr];",
        "",
        "    always_comb",
        "        case ({fam, op})",
    ]
    for i, (a, imm, cyc) in enumerate(disp):
        lines.append(f"            10'h{i:03x}: {{entry, imm, cyc}} = {{10'd{a}, 2'd{imm}, 5'd{cyc}}};")
    lines += [
        "            default: {entry, imm, cyc} = 17'd0;",
        "        endcase",
        "",
        "endmodule",
        "",
    ]
    OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    HEX.write_text("\n".join(f"{w:0{(W + 3) // 4}x}" for w in words + [0] * (1024 - len(words)))
                   + "\n", encoding="utf-8", newline="\n")
    print(f"{len(words)} words x {W} bits, {len(P)} programs -> {OUT}, {HEX.name}")
    pos = 0
    for name, w, _ in FIELDS:
        print(f"  [{pos + w - 1}:{pos}] {name}")
        pos += w


if __name__ == "__main__":
    main()
