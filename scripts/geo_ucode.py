#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The geometry engine's microcode (geo_engine.py has the instruction set).

`program()` returns (code, entries, regs): entries are `init` (constants, then `clear`), `clear`
(a clearing vblank: camera and projection to identity, the palette state to 0; hng64_3d.ipp
clear3d) and `upload` (dl_upload: the 16 packets of the display list). The glue sets `samsho`
(1 for sams64, sams64_2: init_ss64) and `vlen` (the vertex ROM's length in words) before `init`.

It is geom_int.py's IntMachine step for step, with one reordering (the culls before the lighting,
which they do not depend on) and one departure logged in docs/HACKS.md: a chunk of an unknown
type is skipped, where MAME transforms whatever its reused polygon slot last held.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from geo_engine import Asm  # noqa: E402


def program():
    A = Asm()
    R = A.reg

    # ---- registers --------------------------------------------------------------------------------
    ONE, C17, WONE, Q1, Y512, LCLAMP, THREE32, TWO33, P20 = (
        R(n) for n in ("one", "c17", "w_one", "q15_one", "y512", "lclamp", "three32", "two33", "p20"))
    TWO32, TWO25, TWO24 = R("two32"), R("two25"), R("two24")
    SAMSHO, VLEN = R("samsho"), R("vlen")
    CAM, PROJ = R("cam", 16), R("proj", 16)
    LV, LVN = R("lv", 3), R("lvn", 3)
    LST, LVOK = R("lst"), R("lvok")
    SCRX, SCRY, PALST, SCX, SCY, SCZ = (R(n) for n in ("scrx", "scry", "palst", "scx", "scy", "scz"))
    PK, PKS = R("pk", 16), R("pk_saved", 16)
    PKB, FLAGS = R("pkbase"), R("flags")
    OBJ, MV = R("obj", 16), R("mv", 16)
    T = R("t", 12)                                   # scratch
    HDR = R("hdr", 11)
    CHADDR, CHSIZE = R("chaddr", 4), R("chsize", 4)
    CI, CK, CN = R("ci"), R("ck"), R("cn")          # chunk list k, polygon i of size n
    # a polygon: three vertices of world (4), tex (2), normal (3); the face; the last polygon's
    # vertices 0 and 2 and face (strip chunks)
    VW = [R(f"v{m}w", 4) for m in range(3)]
    VT = [R(f"v{m}t", 2) for m in range(3)]
    VN = [R(f"v{m}n", 3) for m in range(3)]
    FACE = R("face", 3)
    FLAT, CIDX, PAL, W1, W2 = R("flat"), R("cidx"), R("pal"), R("w1"), R("w2")
    EYE0, FNRM = R("eye0", 3), R("fnrm", 3)
    LIGHT = R("light", 3)
    TN = R("tn", 3)
    EYE = R("eye", 4)
    BUFA, BUFB = R("bufa", 70), R("bufb", 70)       # the clipper's vertex lists, 7 words a vertex
    OUT = R("out", 70)                               # per vertex: x, y, z, 1/w, light/w, u/w, v/w
    PA, PB, NA, NB = R("pa"), R("pb"), R("na"), R("nb")   # list base addresses and counts
    RI, RP, FI, FP, TT = R("ri"), R("rp"), R("fi"), R("fp"), R("tt")
    RSQ_IN, RSQ_Y, RSQ_S = R("rsq_in"), R("rsq_y"), R("rsq_s")
    RCP_W, RCP_R, RCP_SH = R("rcp_w"), R("rcp_r"), R("rcp_sh")
    DEN, D2 = R("den"), R("d2")
    SZ, NEAR, FAR, FOK = R("sz"), R("near"), R("far"), R("fok")
    J1, OI, OB = R("j1"), R("oi"), R("ob")
    OUTS = R("outs", 7)
    SM, PALBITS, ASX, ASY = R("sm", 3), R("palbits"), R("asx"), R("asy")
    PLN, PAX, PSG, FIDX, FVAL = R("pln"), R("pax"), R("psg"), R("fidx"), R("fval")
    ADDR_BUFA, ADDR_BUFB, ADDR_OUT = R("addr_bufa"), R("addr_bufb"), R("addr_out")
    ADDR_OUT7, ADDR_OUT14 = R("addr_out7"), R("addr_out14")
    KI = [0] + R("kidx", 6)                          # constants 0-6, LDX's field index (R0 is 0)
    C27 = R("c27")

    # setup (the triangle's plane, for EMIT) works in the clipper's first list, which is dead by the
    # time the fan runs: the record G (22 words, EMIT's order), then its temporaries
    G = BUFA[0:22]
    SU = BUFA[22:70]
    S_SA, S_SB, S_SC, S_YA, S_YB, S_YC = SU[0:6]
    S_PB, S_PC = SU[6:11], SU[11:16]
    S_DX21, S_DX31, S_DY21, S_DY31 = SU[16:20]
    S_DP2, S_DP3 = SU[20:25], SU[25:30]
    S_DET, S_MAG, S_E, S_DN, S_RR, S_NEGF, S_HI, S_LO, S_NH, S_SWT = SU[30:40]

    L = A.label

    def movi(d, v):
        """Any constant: MOVI, then shifted into place."""
        if -32768 <= v <= 32767:
            A.movi(d, imm=v)
            return
        sh = (v & -v).bit_length() - 1
        assert -32768 <= (v >> sh) <= 32767, v
        A.movi(d, imm=v >> sh)
        A.shli(d, d, imm=sh)

    def beqi(a, v, target):
        movi(T[11], v)
        A.beq(a=a, b=T[11], imm=target)

    def matmul(dst, a, b, shift):
        """matmul4's layout: dst[4j+i] = sum_k a[4k+i] b[4j+k], rounded by `shift`."""
        for i in range(4):
            for j in range(4):
                A.mul(a=a[i], b=b[4 * j])
                for k in (1, 2, 3):
                    A.mac(a=a[4 * k + i], b=b[4 * j + k])
                A.st(dst[4 * j + i], imm=shift)

    def vm(dst, m, v, n_in, shift, comps=range(4)):
        """dst[i] = round(sum_k v[k] m[4k+i]) for k < n_in."""
        for i in comps:
            A.mul(a=v[0], b=m[i])
            for k in range(1, n_in):
                A.mac(a=v[k], b=m[4 * k + i])
            A.st(dst[i], imm=shift)

    def rdiv(q, den, bits):
        """q = ACC / den rounded half away from zero (geom_int.rdiv): ACC = 2 ACC +- |den| by ACC's
        sign, divided by 2 den; the quotient under 2^bits."""
        pos = L()
        done = L()
        A.abs(T[10], a=den)
        A.ashl(imm=1)
        A.baccn(imm=pos + "_neg")
        A.ada(a=T[10], imm=0)
        A.j(imm=done)
        A.here(pos + "_neg")
        A.movi(T[9], imm=-1)                          # ACC - |den|
        A.mac(a=T[10], b=T[9])
        A.here(done)
        A.add(D2, a=den, b=den)
        A.div(q, b=D2, imm=bits)

    # r0 reads 0: SUB d, r0, x is NEG d, x in one clock (NEG is a two-step ALU op in rtl/3d/hng64_geo.sv)
    R0 = 0

    # ---- init, clear --------------------------------------------------------------------------------
    entries = {}
    entries["init"] = len(A.code)
    A.here("init")
    movi(ONE, 1)
    for k in range(1, 7):
        A.movi(KI[k], imm=k)
    A.movi(C27, imm=27)
    movi(C17, gi_W_MIN)
    movi(WONE, 1 << 23)
    movi(Q1, 1 << 15)
    movi(Y512, 512 << 12)
    movi(LCLAMP, 255 << 8)
    movi(THREE32, 3 << 32)
    movi(TWO33, 1 << 33)
    movi(P20, 1 << 20)
    movi(TWO32, 1 << 32)
    movi(TWO25, 1 << 25)
    movi(TWO24, 1 << 24)
    movi(ADDR_BUFA, BUFA[0])
    movi(ADDR_BUFB, BUFB[0])
    movi(ADDR_OUT, OUT[0])
    movi(ADDR_OUT7, OUT[7])
    movi(ADDR_OUT14, OUT[14])
    A.here("clear")
    entries["clear"] = len(A.code)
    for k in range(16):
        A.movi(CAM[k], imm=0)
        A.movi(PROJ[k], imm=0)
    for k in (0, 5, 10, 15):
        A.add(CAM[k], a=Q1, b=R0)
        A.add(PROJ[k], a=P20, b=R0)
    A.movi(PALST, imm=0)
    A.halt()

    # ---- upload: 16 packets -------------------------------------------------------------------------
    entries["upload"] = len(A.code)
    A.here("upload")
    A.movi(PKB, imm=0)
    A.here("packet")
    for k in range(16):
        A.addi(T[0], a=PKB, imm=k)
        A.dl(PK[k], a=T[0])
    A.bz(a=PK[0], imm="upload_done")
    beqi(PK[0], 0x0001, "cmd_camera")
    beqi(PK[0], 0x0010, "cmd_light")
    beqi(PK[0], 0x0011, "cmd_scroll")
    beqi(PK[0], 0x0012, "cmd_proj")
    beqi(PK[0], 0x0100, "cmd_block")
    beqi(PK[0], 0x0101, "cmd_block")
    beqi(PK[0], 0x0102, "cmd_mini")
    A.here("next_packet")
    A.addi(PKB, a=PKB, imm=16)
    movi(T[11], 256)
    A.blt(a=PKB, b=T[11], imm="packet")
    A.here("upload_done")
    A.halt()

    # camera: c[0], c[4], c[8] = pk1-3; c[1], c[5], c[9] = pk4-6; c[2], c[6], c[10] = pk7-9;
    # c[12..14] = pk10-12; c[3] = c[7] = c[11] = 0, c[15] = 1.0
    A.here("cmd_camera")
    for dst, src in ((0, 1), (4, 2), (8, 3), (1, 4), (5, 5), (9, 6), (2, 7), (6, 8), (10, 9),
                     (12, 10), (13, 11), (14, 12)):
        A.sext16(CAM[dst], a=PK[src])
    for k in (3, 7, 11):
        A.movi(CAM[k], imm=0)
    A.add(CAM[15], a=Q1, b=R0)
    A.j(imm="next_packet")

    # light: the vector pk3-5 and strength pk9; its normalised form for every polygon after
    A.here("cmd_light")
    for k in range(3):
        A.sext16(LV[k], a=PK[3 + k])
    A.sext16(LST, a=PK[9])
    A.mul(a=LV[0], b=LV[0])
    A.mac(a=LV[1], b=LV[1])
    A.mac(a=LV[2], b=LV[2])
    A.st(RSQ_IN, imm=0)
    A.movi(LVOK, imm=0)
    A.bz(a=RSQ_IN, imm="next_packet")
    A.movi(LVOK, imm=1)
    A.jal(imm="rsq")
    A.addi(T[0], a=RSQ_S, imm=-16)
    for k in range(3):
        A.mul(a=LV[k], b=RSQ_Y)
        A.stv(LVN[k], b=T[0], imm=0)
    A.j(imm="next_packet")

    A.here("cmd_scroll")
    A.add(SCRX, a=PK[1], b=R0)
    A.add(SCRY, a=PK[2], b=R0)
    A.add(PALST, a=PK[8], b=R0)
    A.add(SCX, a=PK[5], b=R0)
    A.add(SCY, a=PK[6], b=R0)
    A.add(SCZ, a=PK[7], b=R0)
    A.j(imm="next_packet")

    # projection (geom_int.IntMachine.set_projection)
    A.here("cmd_proj")
    LEFT, RIGHT, TOP, BOT = T[0], T[1], T[2], T[3]
    A.sext16(LEFT, a=PK[11])
    A.sext16(RIGHT, a=PK[10])
    A.sext16(TOP, a=PK[12])
    A.sext16(BOT, a=PK[13])
    A.sext16(T[4], a=PK[4])
    A.sext16(T[5], a=PK[5])
    A.sext16(T[6], a=PK[6])
    A.mul(a=T[6], b=T[4])
    A.ada(a=T[6], imm=15)
    A.st(SZ, imm=0)
    A.mul(a=T[5], b=T[4])
    A.ada(a=T[5], imm=15)
    A.st(NEAR, imm=0)
    for k in range(16):
        A.movi(PROJ[k], imm=0)
    A.sub(PROJ[11], a=R0, b=P20)
    A.sub(T[7], a=RIGHT, b=LEFT)                     # rl
    A.sub(T[8], a=TOP, b=BOT)                        # tb
    # far = rdiv(-(sz near), sz - 2 near)
    A.movi(FOK, imm=0)
    A.sub(DEN, a=SZ, b=NEAR)
    A.sub(DEN, a=DEN, b=NEAR)
    A.bz(a=DEN, imm="proj_nofar")
    A.lda(a=R0, imm=0)
    A.msb(a=SZ, b=NEAR)
    rdiv(FAR, DEN, 46)
    A.movi(FOK, imm=1)
    A.here("proj_nofar")
    # m0 = rdiv(2 sz << 5, rl), m5 = rdiv(2 sz << 5, tb)
    A.bz(a=T[7], imm="proj_m0z")
    A.lda(a=SZ, imm=6)
    A.add(DEN, a=T[7], b=R0)
    rdiv(PROJ[0], DEN, 46)
    A.lda(a=RIGHT, imm=20)
    A.ada(a=LEFT, imm=20)
    rdiv(PROJ[8], DEN, 46)
    A.here("proj_m0z")
    A.bz(a=T[8], imm="proj_m5z")
    A.lda(a=SZ, imm=6)
    A.add(DEN, a=T[8], b=R0)
    rdiv(PROJ[5], DEN, 46)
    A.lda(a=TOP, imm=20)
    A.ada(a=BOT, imm=20)
    rdiv(PROJ[9], DEN, 46)
    A.here("proj_m5z")
    A.bz(a=FOK, imm="next_packet")
    A.sub(DEN, a=FAR, b=NEAR)
    A.bz(a=DEN, imm="next_packet")
    A.lda(a=R0, imm=0)                               # m10 = rdiv(-(far + near) << 20, far - near)
    A.movi(T[9], imm=-1)
    A.add(T[4], a=FAR, b=NEAR)
    A.mul(a=T[4], b=T[9])
    A.ashl(imm=20)
    rdiv(PROJ[10], DEN, 46)
    A.shli(DEN, a=DEN, imm=10)                       # m14 = rdiv(-(2 far near), (far - near) << 10)
    A.lda(a=R0, imm=0)
    A.msb(a=FAR, b=NEAR)
    A.ashl(imm=1)
    rdiv(PROJ[14], DEN, 46)
    A.j(imm="next_packet")

    # ---- polygon blocks ----------------------------------------------------------------------------
    A.here("cmd_block")
    A.jal(imm="block")
    A.j(imm="next_packet")

    # 0x0102: pk0-6 with an identity object matrix; a second from pk8-14 if pk7 = 1, pk8 = 0x0102
    A.here("cmd_mini")
    for k in range(16):
        A.add(PKS[k], a=PK[k], b=R0)
    def mini_matrix():
        for k in range(7, 16):
            A.movi(PK[k], imm=0x7FFF if k in (7, 11, 15) else 0)
    mini_matrix()
    A.jal(imm="block")
    movi(T[11], 1)
    A.bne(a=PKS[7], b=T[11], imm="next_packet")
    movi(T[11], 0x0102)
    A.bne(a=PKS[8], b=T[11], imm="next_packet")
    for k in range(7):
        A.add(PK[k], a=PKS[8 + k], b=R0)
    mini_matrix()
    A.jal(imm="block")
    A.j(imm="next_packet")

    # block: the object matrix, the model-view, the block's header in the vertex ROM, four chunk
    # lists; per block, what every polygon of it shares (scale, palette state, scroll)
    A.here("block")
    A.add(FLAGS, a=PK[1], b=R0)
    for dst, src in ((8, 7), (4, 8), (0, 9), (9, 10), (5, 11), (1, 12), (10, 13), (6, 14), (2, 15),
                     (12, 4), (13, 5), (14, 6)):
        A.sext16(OBJ[dst], a=PK[src])
    for k in (3, 7, 11):
        A.movi(OBJ[k], imm=0)
    A.add(OBJ[15], a=Q1, b=R0)
    A.bz(a=SAMSHO, imm="block_cam")
    for k in range(16):
        A.shli(MV[k], a=OBJ[k], imm=15)
    A.j(imm="block_mv")
    A.here("block_cam")
    matmul(MV, CAM, OBJ, 0)
    A.here("block_mv")
    # the polygon slots double as MAME's `last` (a strip chunk reads the previous polygon's
    # vertices 0 and 2 and face in place), so a block starts them as a new Poly(): all zero
    for m in range(3):
        for r_ in VW[m] + VT[m] + VN[m]:
            A.movi(r_, imm=0)
    for r_ in FACE:
        A.movi(r_, imm=0)
    # the world scale: x by scale z, y by y, z by x if flags & 0x40 (MAME's order), else 256
    A.andi(T[0], a=FLAGS, imm=0x40)
    A.movi(T[1], imm=256)
    for k in range(3):
        A.add(SM[k], a=T[1], b=R0)
    A.bz(a=T[0], imm="block_noscale")
    for k, sc in enumerate((SCZ, SCY, SCX)):
        A.add(SM[k], a=sc, b=R0)
    A.here("block_noscale")
    # the palette state's bits, if flags & 0x100
    A.movi(PALBITS, imm=0)
    A.andi(T[0], a=FLAGS, imm=0x100)
    A.bz(a=T[0], imm="block_nopal")
    A.shri(PALBITS, a=PALST, imm=8)
    A.andi(PALBITS, a=PALBITS, imm=0x3F)
    A.shli(PALBITS, a=PALBITS, imm=7)
    A.here("block_nopal")
    # the texture scroll, if flags & 0x80
    A.movi(ASX, imm=0)
    A.movi(ASY, imm=0)
    A.andi(T[0], a=FLAGS, imm=0x80)
    A.bz(a=T[0], imm="block_noscroll")
    A.andi(ASX, a=SCRX, imm=0x3FFF)
    A.shri(ASX, a=ASX, imm=5)
    A.andi(ASY, a=SCRY, imm=0x3FFF)
    A.shri(ASY, a=ASY, imm=5)
    A.here("block_noscroll")
    # off = pk2 << 16 | pk3; the header at off * 3, 11 words
    A.shli(T[0], a=PK[2], imm=16)
    A.emit("OR", T[0], T[0], PK[3], 0)
    A.shli(T[1], a=T[0], imm=1)
    A.add(T[0], a=T[0], b=T[1])
    A.bge(a=T[0], b=VLEN, imm="block_ret")
    A.vseek(a=T[0])
    for k in range(11):
        A.vrd(HDR[k])
    A.shli(T[2], a=HDR[2], imm=16)                   # megaoff << 16
    for k, h in enumerate((0, 1, 3, 4)):
        A.emit("OR", CHADDR[k], HDR[h], T[2], 0)
        A.shli(T[3], a=CHADDR[k], imm=1)
        A.add(CHADDR[k], a=CHADDR[k], b=T[3])        # * 3
    for k, h in enumerate((6, 7, 9, 10)):
        A.add(CHSIZE[k], a=HDR[h], b=R0)
    for k in range(4):
        A.vseek(a=CHADDR[k])
        A.movi(CI, imm=0)
        A.here(f"chunk{k}_loop")
        A.bge(a=CI, b=CHSIZE[k], imm=f"chunk{k}_done")
        A.jal(imm="poly")                            # T[0] = 1: the list stops
        A.bnz(a=T[0], imm=f"chunk{k}_done")
        A.addi(CI, a=CI, imm=1)
        A.j(imm=f"chunk{k}_loop")
        A.here(f"chunk{k}_done")
    A.here("block_ret")
    A.ret()

    def std(m):
        """recoverStandardVerts: world (times the block's scale), a skipped word, tex. The colour
        index (the first tex word >> 5) is taken always; only a flat polygon uses it."""
        for k in range(3):
            A.vrds(VW[m][k])
        A.vrd(T[3])
        A.vrd(T[4])
        A.sext16(VT[m][0], a=T[4])
        A.shri(CIDX, a=T[4], imm=5)
        A.vrds(VT[m][1])
        for k in range(3):
            A.mul(a=VW[m][k], b=SM[k])
            A.st(VW[m][k], imm=0)
        A.add(VW[m][3], a=WONE, b=R0)

    def rcp_body():
        """RCP_W > 0 -> RCP_R, RCP_SH (geom_int.rcp: 1/w = r / 2^(21 + e)); uses T[10], T[11]."""
        A.log2(T[10], a=RCP_W)
        A.addi(RCP_SH, a=T[10], imm=21)
        A.norm(T[10], a=RCP_W, imm=20)               # wn
        A.shri(T[11], a=T[10], imm=10)
        A.andi(T[11], a=T[11], imm=1023)
        A.trcp(RCP_R, a=T[11])                       # y0
        A.mul(a=T[10], b=RCP_R)
        A.stf(T[11], imm=0)
        A.sub(T[11], a=TWO33, b=T[11])
        A.mul(a=RCP_R, b=T[11])
        A.stf(RCP_R, imm=23)

    def outputs(X, Y, Z, U, V, LL, o):
        """x, y, z, 1/w, light/w, u/w, v/w of one vertex into o[0..6], given RCP_R, RCP_SH."""
        for f, src, sh in ((0, X, -20), (1, Y, -20), (2, Z, -27)):
            A.mul(a=src, b=RCP_R)
            A.adav(a=ONE, b=RCP_SH)
            A.stv(o[f], b=RCP_SH, imm=sh)
        A.sub(o[1], a=Y512, b=o[1])
        A.lda(a=RCP_R, imm=0)
        A.stv(o[3], b=RCP_SH, imm=-50)
        for f, src, sh in ((4, LL, -24), (5, U, -25), (6, V, -25)):
            A.mul(a=src, b=RCP_R)
            A.stv(o[f], b=RCP_SH, imm=sh)

    def rd3(dst):
        for k in range(3):
            A.vrds(dst[k])

    def copy(dst, src):
        for d, s_ in zip(dst, src):
            A.add(d, a=s_, b=R0)

    # ---- poly: one polygon of the current chunk list. Laid out so the usual case (chunk type 5,
    # visible, lit, unclipped, one triangle) falls through from start to end; returns T[0] = 1
    # when the list stops.
    A.here("poly")
    A.vrd(T[1])
    A.andi(T[2], a=T[1], imm=0xFF00 - 0x10000)
    A.bnz(a=T[2], imm="poly_stop")
    A.andi(CN, a=T[1], imm=0xFF)                     # ctype
    A.vrd(W1)
    A.vrd(W2)
    A.shri(T[3], a=W1, imm=15)                       # flat: not (w1 & 0x8000)
    A.andi(T[3], a=T[3], imm=1)
    A.sub(FLAT, a=ONE, b=T[3])
    A.andi(PAL, a=W1, imm=0x0FF0)                    # ((w1 & 0x0FF0) >> 4) << 3 | palette state
    A.shri(PAL, a=PAL, imm=1)
    A.emit("OR", PAL, PAL, PALBITS, 0)
    movi(T[11], 0x05)
    A.bne(a=CN, b=T[11], imm="ct_other")
    A.here("ct_full")
    for m in range(3):
        std(m)
        rd3(VN[m])
    rd3(FACE)
    A.here("poly_have")

    # culls: eye of vertex 0 (Q26) and the face normal (Q26); back face if flags & 0x10
    vm(EYE0, MV, VW[0], 4, 27, comps=range(3))
    vm(FNRM, MV, FACE, 3, 19, comps=range(3))
    A.andi(T[0], a=FLAGS, imm=0x10)
    A.bz(a=T[0], imm="cull_front")
    A.mul(a=EYE0[0], b=FNRM[0])
    A.mac(a=EYE0[1], b=FNRM[1])
    A.mac(a=EYE0[2], b=FNRM[2])
    A.baccnn(imm="poly_hidden")
    A.here("cull_front")
    A.bgtz(a=EYE0[2], imm="poly_hidden")

    # lighting (flags & 8, strength > 0, a non-zero light vector)
    for k in range(3):
        A.movi(LIGHT[k], imm=0)
    A.andi(T[0], a=FLAGS, imm=0x08)
    A.bz(a=T[0], imm="light_done")
    A.bltz(a=LST, imm="light_done")
    A.bz(a=LST, imm="light_done")
    A.bz(a=LVOK, imm="light_done")
    for vi in range(3):
        nxt = f"light_v{vi}_done"
        for i in range(3):                           # tn = round(obj3x3 . normal, 14): Q16
            A.mul(a=VN[vi][0], b=OBJ[i])
            A.mac(a=VN[vi][1], b=OBJ[4 + i])
            A.mac(a=VN[vi][2], b=OBJ[8 + i])
            A.st(TN[i], imm=14)
        A.mul(a=TN[0], b=TN[0])
        A.mac(a=TN[1], b=TN[1])
        A.mac(a=TN[2], b=TN[2])
        A.st(RSQ_IN, imm=0)
        A.lda(a=R0, imm=0)
        A.msb(a=TN[0], b=LVN[0])
        A.msb(a=TN[1], b=LVN[1])
        A.msb(a=TN[2], b=LVN[2])
        A.st(T[6], imm=0)                            # dot, Q32
        A.bz(a=RSQ_IN, imm=nxt)
        A.bltz(a=T[6], imm=nxt)
        A.bz(a=T[6], imm=nxt)
        # 1/length: 1 - (n - 1) / 2 within 1/128 of 1.0 (geom_int.rsq_normal), else rsq
        far = f"light_v{vi}_far"
        have = f"light_v{vi}_have"
        A.sub(T[7], a=RSQ_IN, b=TWO32)
        A.abs(T[8], a=T[7])
        A.bge(a=T[8], b=TWO25, imm=far)
        A.lda(a=T[7], imm=0)
        A.st(T[8], imm=9)
        A.sub(RSQ_Y, a=TWO24, b=T[8])
        A.movi(RSQ_S, imm=40)
        A.here(have)
        A.addi(T[7], a=RSQ_S, imm=-8)
        A.mul(a=T[6], b=RSQ_Y)
        A.stv(T[8], b=T[7], imm=0)                   # cos, Q24
        A.mul(a=T[8], b=LST)
        A.st(T[8], imm=17)
        A.min(LIGHT[vi], a=T[8], b=LCLAMP)
        A.here(nxt)
    A.here("light_done")

    # eye and clip per vertex, into list A: x, y, z, w (Q24), u, v (Q23), light (Q8). The eye's w
    # is 1.0 (Q26): the camera's and object's fourth rows are 0, 0, 0, 1 and the world's w 1.0; the
    # projection's entries other than 0, 5, 8-11, 14, 15 are 0 (a packet's and clear's alike).
    for m in range(3):
        if m == 0:
            copy(EYE[:3], EYE0)                      # the cull's
        else:
            vm(EYE, MV, VW[m], 4, 27, comps=range(3))
        base = BUFA[7 * m:7 * m + 7]
        for dst, (e1, p1), (e2, p2) in ((0, (0, 0), (2, 8)), (1, (1, 5), (2, 9))):
            A.mul(a=EYE[e1], b=PROJ[p1])
            A.mac(a=EYE[e2], b=PROJ[p2])
            A.st(base[dst], imm=22)
        for dst, p1, p2 in ((2, 10, 14), (3, 11, 15)):
            A.mul(a=EYE[2], b=PROJ[p1])
            A.ada(a=PROJ[p2], imm=26)
            A.st(base[dst], imm=22)
        A.shli(base[4], a=VT[m][0], imm=8)
        A.shli(base[5], a=VT[m][1], imm=8)
        A.add(base[6], a=LIGHT[m], b=R0)
    A.add(PA, a=ADDR_BUFA, b=R0)
    A.add(PB, a=ADDR_BUFB, b=R0)
    A.movi(NA, imm=3)
    # every vertex inside every plane: no clipping
    for m in range(3):
        x, y, z, w = BUFA[7 * m:7 * m + 4]
        A.blt(a=w, b=C17, imm="clip_slow")
        for c in (x, y, z):
            A.abs(T[0], a=c)
            A.blt(a=w, b=T[0], imm="clip_slow")
    # no clipping: three vertices in list A's first three slots, straight into OUT
    for m in range(3):
        X, Y, Z, W, U, V, LL = BUFA[7 * m:7 * m + 7]
        o = OUT[7 * m:7 * m + 7]
        A.add(RCP_W, a=W, b=R0)
        rcp_body()
        outputs(X, Y, Z, U, V, LL, o)
    A.here("out_done")

    # the attributes (Pixel.scala Attr): flat, blend, 4bpp, texture index, sub-page, h and v
    # page offsets, palette (a flat polygon's colour), scroll x and y, wrap exponents
    A.aout(0, a=FLAT)
    A.shri(T[0], a=W1, imm=14)
    A.andi(T[0], a=T[0], imm=1)
    A.aout(1, a=T[0])
    A.shri(T[0], a=W1, imm=12)
    A.andi(T[0], a=T[0], imm=1)
    A.aout(2, a=T[0])
    A.andi(T[5], a=W1, imm=15)
    A.aout(3, a=T[5])
    A.shri(T[0], a=W2, imm=14)
    A.andi(T[0], a=T[0], imm=3)
    A.aout(4, a=T[0])
    A.shri(T[0], a=W2, imm=7)
    A.andi(T[0], a=T[0], imm=0x7F)
    A.aout(5, a=T[0])
    A.andi(T[0], a=W2, imm=0x7F)
    A.aout(6, a=T[0])
    A.bnz(a=FLAT, imm="attr_flat")
    A.aout(7, a=PAL)
    A.here("attr_pal")
    A.aout(8, a=ASX)
    A.aout(9, a=ASY)
    A.movi(T[3], imm=31)
    A.add(T[2], a=T[5], b=T[5])
    A.wrap(T[0], a=T[2])
    A.min(T[0], a=T[0], b=T[3])
    A.aout(10, a=T[0])
    A.addi(T[2], a=T[2], imm=1)
    A.wrap(T[0], a=T[2])
    A.min(T[0], a=T[0], b=T[3])
    A.aout(11, a=T[0])

    # the fan: (0, j, j + 1); three vertices (nearly all) without the loop
    A.movi(T[0], imm=3)
    A.bne(a=NA, b=T[0], imm="fan_many")
    A.add(S_SA, a=ADDR_OUT, b=R0)
    A.add(S_SB, a=ADDR_OUT7, b=R0)
    A.add(S_SC, a=ADDR_OUT14, b=R0)
    A.jal(imm="setup")
    A.movi(T[0], imm=0)
    A.ret()

    # ---- the rest of poly, off the usual path ------------------------------------------------------
    A.here("poly_hidden")
    A.movi(T[0], imm=0)
    A.ret()
    A.here("poly_stop")
    A.movi(T[0], imm=1)                              # MAME re-reads the same word: the list ends
    A.ret()

    A.here("attr_flat")
    A.add(T[0], a=PAL, b=CIDX)
    A.andi(T[0], a=T[0], imm=0x7FFF)
    A.aout(7, a=T[0])
    A.j(imm="attr_pal")

    for vi in range(3):
        A.here(f"light_v{vi}_far")
        A.jal(imm="rsq")
        A.j(imm=f"light_v{vi}_have")

    A.here("ct_other")
    beqi(CN, 0x0F, "ct_full")
    for ct in (0x04, 0x0E, 0x24, 0x2E):
        beqi(CN, ct, "ct_flatn")
    for ct in (0x87, 0x97, 0xD7, 0xC7):
        beqi(CN, ct, "ct_strip")
    for ct in (0x86, 0x96, 0xB6, 0xC6, 0xD6):
        beqi(CN, ct, "ct_stripf")
    A.movi(T[0], imm=0)                              # unknown: skipped (docs/HACKS.md)
    A.ret()

    A.here("ct_flatn")
    for m in range(3):
        std(m)
    rd3(FACE)
    for m in range(3):
        copy(VN[m], FACE)
    A.j(imm="poly_have")

    A.here("ct_strip")                              # v1 = last v0, v2 = last v2 (in place)
    copy(VW[1], VW[0])
    copy(VT[1], VT[0])
    copy(VN[1], VN[0])
    std(0)
    rd3(VN[0])
    rd3(FACE)
    A.j(imm="poly_have")

    A.here("ct_stripf")                             # and normal 0 = face = last face (in place)
    copy(VW[1], VW[0])
    copy(VT[1], VT[0])
    copy(VN[1], VN[0])
    std(0)
    copy(VN[0], FACE)
    for k in range(3):
        A.vrd(T[k])
    A.j(imm="poly_have")

    # the clipper (geom_int._clip_all): seven planes in turn, f >= 0 inside, f = w - 17 for the
    # first, then w + x, w - x, w + y, w - y, w + z, w - z. One loop over the planes: the path is
    # rare (2% of polygons), so it is written for size.
    A.here("clip_slow")
    A.movi(PLN, imm=0)
    A.here("plane_loop")
    A.movi(T[0], imm=7)
    A.bge(a=PLN, b=T[0], imm="clip_done")
    A.bz(a=NA, imm="clip_done")
    # the plane's axis (0-2) and sign (0: w + x, 1: w - x); plane 0 is w - 17
    A.addi(PAX, a=PLN, imm=-1)
    A.andi(PSG, a=PAX, imm=1)
    A.shri(PAX, a=PAX, imm=1)
    # every vertex inside this plane: the list stands as it is (clip() would copy it unchanged)
    A.movi(RI, imm=0)
    A.here("plane_scan")
    A.bge(a=RI, b=NA, imm="plane_skip")
    A.add(FIDX, a=RI, b=R0)
    A.jal(imm="clip_f")
    A.bltz(a=FVAL, imm="plane_work")
    A.addi(RI, a=RI, imm=1)
    A.j(imm="plane_scan")
    A.here("plane_skip")
    A.addi(PLN, a=PLN, imm=1)
    A.j(imm="plane_loop")
    A.here("plane_work")
    A.movi(NB, imm=0)
    A.addi(RP, a=NA, imm=-1)                         # prev = n - 1
    A.movi(RI, imm=0)
    A.add(FIDX, a=RP, b=R0)
    A.jal(imm="clip_f")
    A.add(FP, a=FVAL, b=R0)
    A.here("plane_vloop")
    A.bge(a=RI, b=NA, imm="plane_end")
    A.add(FIDX, a=RI, b=R0)
    A.jal(imm="clip_f")
    A.add(FI, a=FVAL, b=R0)
    # s1 = fi >= 0, s2 = fp >= 0
    A.bltz(a=FI, imm="plane_s1n")
    A.bltz(a=FP, imm="plane_cross")                  # s1 in, s2 out
    A.j(imm="plane_in")
    A.here("plane_s1n")
    A.bltz(a=FP, imm="plane_next")                   # both out
    A.here("plane_cross")
    # t = rdiv(|fp| << 12, |fp - fi|)
    A.abs(T[5], a=FP)
    A.sub(T[6], a=FP, b=FI)
    A.abs(DEN, a=T[6])
    A.lda(a=T[5], imm=12)
    rdiv(TT, DEN, 14)
    # lerp(prev, i, t) appended to B
    A.shli(T[1], a=RP, imm=3)
    A.sub(T[1], a=T[1], b=RP)
    A.add(T[1], a=T[1], b=PA)                        # prev's base
    A.shli(T[7], a=RI, imm=3)
    A.sub(T[7], a=T[7], b=RI)
    A.add(T[7], a=T[7], b=PA)                        # i's base
    A.shli(T[8], a=NB, imm=3)
    A.sub(T[8], a=T[8], b=NB)
    A.add(T[8], a=T[8], b=PB)                        # the new vertex's base
    A.movi(T[2], imm=0)
    A.here("plane_lerp")
    A.ldx(T[3], a=T[1], b=T[2])
    A.ldx(T[4], a=T[7], b=T[2])
    A.sub(T[4], a=T[4], b=T[3])
    A.mul(a=T[4], b=TT)
    A.st(T[4], imm=12)
    A.add(T[4], a=T[4], b=T[3])
    A.stx(T[4], a=T[8], b=T[2])
    A.addi(T[2], a=T[2], imm=1)
    A.movi(T[9], imm=7)
    A.blt(a=T[2], b=T[9], imm="plane_lerp")
    A.addi(NB, a=NB, imm=1)
    A.bltz(a=FI, imm="plane_next")
    A.here("plane_in")
    # append vertex i to B
    A.shli(T[7], a=RI, imm=3)
    A.sub(T[7], a=T[7], b=RI)
    A.add(T[7], a=T[7], b=PA)
    A.shli(T[8], a=NB, imm=3)
    A.sub(T[8], a=T[8], b=NB)
    A.add(T[8], a=T[8], b=PB)
    A.movi(T[2], imm=0)
    A.here("plane_copy")
    A.ldx(T[3], a=T[7], b=T[2])
    A.stx(T[3], a=T[8], b=T[2])
    A.addi(T[2], a=T[2], imm=1)
    A.movi(T[9], imm=7)
    A.blt(a=T[2], b=T[9], imm="plane_copy")
    A.addi(NB, a=NB, imm=1)
    A.here("plane_next")
    A.add(RP, a=RI, b=R0)
    A.add(FP, a=FI, b=R0)
    A.addi(RI, a=RI, imm=1)
    A.j(imm="plane_vloop")
    A.here("plane_end")
    # B becomes A
    A.add(T[0], a=PA, b=R0)
    A.add(PA, a=PB, b=R0)
    A.add(PB, a=T[0], b=R0)
    A.add(NA, a=NB, b=R0)
    A.addi(PLN, a=PLN, imm=1)
    A.j(imm="plane_loop")

    # clip_f: FVAL = the current plane's f of vertex FIDX of list A
    A.here("clip_f")
    A.shli(T[1], a=FIDX, imm=3)
    A.sub(T[1], a=T[1], b=FIDX)
    A.add(T[1], a=T[1], b=PA)
    A.movi(T[2], imm=3)
    A.ldx(T[3], a=T[1], b=T[2])                      # w
    A.bnz(a=PLN, imm="clip_f_axis")
    A.sub(FVAL, a=T[3], b=C17)
    A.ret()
    A.here("clip_f_axis")
    A.ldx(T[4], a=T[1], b=PAX)
    A.bnz(a=PSG, imm="clip_f_minus")
    A.add(FVAL, a=T[3], b=T[4])
    A.ret()
    A.here("clip_f_minus")
    A.sub(FVAL, a=T[3], b=T[4])
    A.ret()
    A.here("clip_done")
    A.movi(T[0], imm=3)
    A.blt(a=NA, b=T[0], imm="poly_hidden")           # nothing left (or a line)

    # per vertex after clipping: 1/w, then x, y, z, 1/w, light/w, u/w, v/w into OUT
    A.here("out_loop_start")
    A.movi(OI, imm=0)
    A.here("out_loop")
    A.bge(a=OI, b=NA, imm="out_loop_end")
    A.shli(T[1], a=OI, imm=3)
    A.sub(T[1], a=T[1], b=OI)
    A.add(OB, a=T[1], b=ADDR_OUT)                    # OUT record
    A.add(T[1], a=T[1], b=PA)                        # clip record
    vals = T[2:9]                                    # x, y, z, w, u, v, l (loaded)
    for c in range(7):
        A.movi(T[9], imm=c)
        A.ldx(vals[c], a=T[1], b=T[9])
    X, Y, Z, W, U, V, LL = vals
    A.add(RCP_W, a=W, b=R0)
    A.jal(imm="rcp")                                 # RCP_R, RCP_SH (1/w = r / 2^sh)
    outputs(X, Y, Z, U, V, LL, OUTS)
    for f in range(7):
        A.movi(T[10], imm=f)
        A.stx(OUTS[f], a=OB, b=T[10])
    A.addi(OI, a=OI, imm=1)
    A.j(imm="out_loop")
    A.here("out_loop_end")
    A.j(imm="out_done")

    A.here("fan_many")
    A.movi(J1, imm=1)
    A.here("fan_loop")
    A.addi(T[0], a=J1, imm=1)
    A.bge(a=T[0], b=NA, imm="fan_done")
    A.add(S_SA, a=ADDR_OUT, b=R0)
    A.shli(T[1], a=J1, imm=3)
    A.sub(T[1], a=T[1], b=J1)
    A.add(S_SB, a=T[1], b=ADDR_OUT)
    A.addi(S_SC, a=S_SB, imm=7)
    A.jal(imm="setup")
    A.addi(J1, a=J1, imm=1)
    A.j(imm="fan_loop")
    A.here("fan_done")
    A.movi(T[0], imm=0)
    A.ret()

    # ---- subroutines -------------------------------------------------------------------------------
    # rsq: RSQ_IN > 0 -> RSQ_Y, RSQ_S (geom_int.rsq); uses T[9..11] only
    A.here("rsq")
    A.log2(T[9], a=RSQ_IN)
    A.addi(T[9], a=T[9], imm=-30)
    A.shri(T[9], a=T[9], imm=1)
    A.shli(T[9], a=T[9], imm=1)                      # k, even, floor
    A.sub(T[10], a=R0, b=T[9])
    A.shlv(T[10], a=RSQ_IN, b=T[10])                 # nn in [2^30, 2^32)
    A.shri(T[11], a=T[10], imm=24)
    A.trsq(RSQ_Y, a=T[11])                           # y0
    A.mul(a=T[10], b=RSQ_Y)
    A.stf(T[11], imm=13)
    A.mul(a=T[11], b=RSQ_Y)
    A.stf(T[11], imm=17)                             # t
    A.sub(T[11], a=THREE32, b=T[11])
    A.mul(a=RSQ_Y, b=T[11])
    A.stf(RSQ_Y, imm=33)
    A.shri(T[9], a=T[9], imm=1)
    A.addi(RSQ_S, a=T[9], imm=31)
    A.ret()

    # rcp: RCP_W > 0 -> RCP_R, RCP_SH (geom_int.rcp: 1/w = r / 2^(21 + e)); uses T[10], T[11]
    A.here("rcp")
    rcp_body()
    A.ret()

    # ---- setup: the triangle S_SA, S_SB, S_SC (vertex record addresses, fan order) to the rasteriser -------
    # geo_engine.setup_record is the definition; this is the rasteriser's old gradient unit
    # (Gradients.scala) in microcode.
    A.here("setup")
    for sp, yp in ((S_SA, S_YA), (S_SB, S_YB), (S_SC, S_YC)):
        A.ldx(yp, a=sp, b=KI[1])

    def swap(p, q, yp, yq):
        skip = L()
        A.bge(a=yq, b=yp, imm=skip)                  # stable: only a strictly lower y moves up
        for u, v in ((p, q), (yp, yq)):
            A.add(S_SWT, a=u, b=R0)
            A.add(u, a=v, b=R0)
            A.add(v, a=S_SWT, b=R0)
        A.here(skip)
    swap(S_SA, S_SB, S_YA, S_YB)
    swap(S_SB, S_SC, S_YB, S_YC)
    swap(S_SA, S_SB, S_YA, S_YB)

    for n, (sp, yp) in enumerate(((S_SA, S_YA), (S_SB, S_YB), (S_SC, S_YC))):
        A.ldx(G[2 * n], a=sp, b=KI[0])
        A.add(G[2 * n + 1], a=yp, b=R0)
    for k in range(5):
        A.ldx(G[7 + k], a=S_SA, b=KI[2 + k])
        A.ldx(S_PB[k], a=S_SB, b=KI[2 + k])
        A.ldx(S_PC[k], a=S_SC, b=KI[2 + k])
    A.sub(S_DX21, a=G[2], b=G[0])
    A.sub(S_DX31, a=G[4], b=G[0])
    A.sub(S_DY21, a=G[3], b=G[1])
    A.sub(S_DY31, a=G[5], b=G[1])
    for k in range(5):
        A.sub(S_DP2[k], a=S_PB[k], b=G[7 + k])
        A.sub(S_DP3[k], a=S_PC[k], b=G[7 + k])

    A.mul(a=S_DX21, b=S_DY31)
    A.msb(a=S_DX31, b=S_DY21)
    A.stf(S_DET, imm=0)
    A.bz(a=S_DET, imm="setup_none")
    A.movi(S_NEGF, imm=0)
    A.bgez(a=S_DET, imm="setup_pos")
    A.movi(S_NEGF, imm=1)
    A.here("setup_pos")
    A.add(G[6], a=S_NEGF, b=R0)
    # 1/|det| = r / 2^(21 + e): its top 21 bits dn, r = floor(2^41 / dn)
    A.abs(S_MAG, a=S_DET)
    A.log2(S_E, a=S_MAG)
    A.norm(S_DN, a=S_MAG, imm=20)
    A.lda(a=ONE, imm=41)
    A.div(S_RR, b=S_DN, imm=22)

    # each gradient: n r rounded half up by e + 9. n (the numerator, to 64 bits) is split at bit 35
    # so both products fit the multiplier: n = hi 2^35 + lo, 0 <= lo < 2^35. With e <= 26, n r
    # itself fits the accumulator (under 2^70 for gradients under 2^35); above, the sum is taken
    # as floor(n r / 2^35), which rounds the same: floor(floor(x / 2^35) / 2^k) = floor(x / 2^(35 + k)).
    def numerators(k):
        return (((S_DP2[k], S_DY31), (S_DP3[k], S_DY21), G[12 + k]),   # nx = dp2 dy31 - dp3 dy21
                ((S_DP3[k], S_DX21), (S_DP2[k], S_DX31), G[17 + k]))   # ny = dp3 dx21 - dp2 dx31

    def gradients(big):
        for k in range(5):
            for (a1, b1), (a2, b2), out in numerators(k):
                A.mul(a=a1, b=b1)
                A.msb(a=a2, b=b2)
                A.stf(S_HI, imm=35)
                A.sub(S_NH, a=R0, b=S_HI)
                A.ada(a=S_NH, imm=35)
                A.stf(S_LO, imm=0)
                if big:
                    A.mul(a=S_LO, b=S_RR)
                    A.ashl(imm=-35)
                    A.mac(a=S_HI, b=S_RR)
                    A.stvw(out, b=S_E, imm=9 - 35)
                else:
                    A.mul(a=S_HI, b=S_RR)
                    A.ashl(imm=35)
                    A.mac(a=S_LO, b=S_RR)
                    A.stvw(out, b=S_E, imm=9)
    A.bge(a=S_E, b=C27, imm="setup_big")
    gradients(False)
    A.j(imm="setup_sign")
    A.here("setup_big")
    gradients(True)
    A.here("setup_sign")
    A.bz(a=S_NEGF, imm="setup_emit")
    for k in range(10):
        A.sub(G[12 + k], a=R0, b=G[12 + k])
    A.here("setup_emit")
    A.emit("EMIT", a=G[0])
    A.here("setup_none")
    A.ret()

    code = A.assemble()
    return code, entries, A.reg_names


gi_W_MIN = 17


def export(out_dir):
    """The assembled microcode and tables for rtl/3d/hng64_geo.sv, into out_dir (rtl/3d):
    hng64_geo_ucode.hex, 2,048 words of 49 bits a line (op 6 | d 9 | a 9 | b 9 | imm 16, from the
    top), zero after the program; hng64_geo_rsq.hex and hng64_geo_rcp.hex, the tables;
    hng64_geo_ucode_pkg.sv, the entry points and the registers the glue sets."""
    import geom_int as gi
    from geo_engine import OP
    code, entries, regs = program()
    assert len(code) <= 2048, "the microcode is over 2,048 words"
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    with open(out / "hng64_geo_ucode.hex", "w", newline="\n") as f:
        for op, d, a, b, i in code:
            w = (OP[op] << 43) | (d << 34) | (a << 25) | (b << 16) | (i & 0xFFFF)
            f.write(f"{w:013x}\n")
        for _ in range(2048 - len(code)):
            f.write(f"{0:013x}\n")
    with open(out / "hng64_geo_rsq.hex", "w", newline="\n") as f:
        for k in range(256):
            f.write(f"{gi._RSQ_TABLE.get(k, 0):05x}\n")
    with open(out / "hng64_geo_rcp.hex", "w", newline="\n") as f:
        for v in gi._RCP_TABLE:
            f.write(f"{v:03x}\n")
    with open(out / "hng64_geo_ucode_pkg.sv", "w", newline="\n") as f:
        f.write("// SPDX-License-Identifier: GPL-3.0-or-later\n//\n")
        f.write("// GENERATED by scripts/geo_ucode.py --export; edit that, not this.\n//\n")
        f.write(f"// The geometry microcode's entry points and the registers the glue writes"
                f" ({len(code)} words).\n\n")
        f.write("package hng64_geo_ucode_pkg;\n")
        for k in ("init", "clear", "upload"):
            f.write(f"    localparam int GEO_ENTRY_{k.upper()} = {entries[k]};\n")
        for k in ("samsho", "vlen"):
            f.write(f"    localparam int GEO_REG_{k.upper()} = {regs[k]};\n")
        f.write("endpackage\n")
    return len(code)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--export"]:
        print(export(sys.argv[2]), "words")
