#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 3D geometry engine: its instruction set, an assembler, a simulator, and its microcode.

The geometry RTL is a small microcoded engine (user decision, docs/phase3_3d.md). This file
defines what it executes. The microcode (`program()`) implements geom_int.py's IntMachine: the
display-list commands of an upload, the polygon blocks and their chunks from the vertex ROM, the
culls, lighting, clipper and per-vertex outputs, and the fan of triangles to the rasteriser. The
simulator is functional (one instruction at a time, no timing) and raises on any value that would
not fit the hardware: a multiplier operand wider than 36 bits signed, a register wider than 48.

    python scripts/geo_engine.py sams64 2500      # the engine beside IntMachine, triangle by triangle

Machine state
    R0..R511   48-bit signed; R0 reads 0
    ACC        72-bit signed accumulator (the widest value measured is 58 bits; `acc_check`
               stops the run if a value, or a shifted operand on its way in, needs more)

Instructions (d, a, b register numbers; i a signed 16-bit immediate)
    MUL a,b    ACC = Ra * Rb            MAC a,b    ACC += Ra * Rb          MSB a,b   ACC -= Ra * Rb
    LDA a,i    ACC = Ra << i            ADA a,i    ACC += Ra << i          ADAV a,b  ACC += Ra << Rb
    ASHL i     ACC = ACC << i (i < 0: an arithmetic right shift)
    ST d,i     Rd = round(ACC / 2^i)    STF d,i    Rd = floor(ACC / 2^i)   STV d,b,i Rd = round(ACC / 2^(Rb+i))
               (round: half up; a shift <= 0 is a left shift)
    STVW d,b,i as STV, keeping the low 48 bits (the hardware's store does for every op; the
               simulator allows it only here: the setup's gradients, whose fields are narrower)
    DIV d,b,i  Rd = |ACC| / |Rb| truncated, signed as ACC * Rb; the quotient under 2^i (i + 1 clocks)
    ADD SUB MIN MAX OR AND d,a,b  ADDI ANDI SHLI SHRI d,a,i     SHLV d,a,b (Rb < 0 shifts right)
    MOVI d,i   NEG ABS SEXT16 d,a        LOG2 d,a (the top bit's index; -1 for Ra <= 0)
    NORM d,a,i Ra (> 0) shifted so its top bit is bit i
    LDX d,a,b  Rd = R[Ra + Rb]          STX d,a,b  R[Ra + Rb] = Rd
    TRSQ d,a / TRCP d,a     Rd = the 1/sqrt / reciprocal table's entry Ra
    WRAP d,a   Rd = the wrap table's byte Ra (written by the CPU at 0x30000010)
    DL d,a     Rd = display list word Ra (u16)
    VSEEK a    the vertex ROM stream from word Ra      VRD d   Rd = the next word (u16)
    VRDS d     the next word, sign-extended
    AOUT f,a   triangle field f := Ra   (attributes, Pixel.scala Attr order)
    VOUT       unused (was: a vertex slot for EMIT; the opcode keeps its number)
    EMIT a     the setup record R[a .. a + 21] and the attributes to the rasteriser: the vertices'
               x, y sorted by y, det's sign, the top vertex's z, 1/w, light/w, u/w, v/w, their five
               d/dx, their five d/dy (TriangleSetup.Input; `setup_record` is its definition)
    J t  JAL t  RET  BZ a,t  BNZ a,t  BLTZ a,t  BGEZ a,t  BGTZ a,t  BLT a,b,t  BGE a,b,t  BEQ a,b,t
    BNE a,b,t  BACCN t  BACCNN t (branch if ACC < 0, ACC >= 0)       HALT  the upload is done
"""
import collections
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import geom_int as gi  # noqa: E402

OPS = ["NOP", "MUL", "MAC", "MSB", "LDA", "ADA", "ADAV", "ASHL", "ST", "STF", "STV", "DIV",
       "ADD", "SUB", "MIN", "MAX", "OR", "AND", "ADDI", "ANDI", "SHLI", "SHRI", "SHLV", "MOVI", "NEG", "ABS",
       "SEXT16", "LOG2", "NORM", "LDX", "STX", "TRSQ", "TRCP", "WRAP", "DL", "VSEEK", "VRD", "VRDS",
       "AOUT", "VOUT", "EMIT", "J", "JAL", "RET", "BZ", "BNZ", "BLTZ", "BGEZ", "BLT", "BGE",
       "BEQ", "BNE", "BACCN", "BACCNN", "BGTZ", "HALT", "STVW"]
OP = {n: k for k, n in enumerate(OPS)}
BRANCH = {"J", "JAL", "BZ", "BNZ", "BLTZ", "BGEZ", "BGTZ", "BLT", "BGE", "BEQ", "BNE", "BACCN",
          "BACCNN"}


class Asm:
    """Instructions as (op, d, a, b, imm); labels resolved at the end."""

    def __init__(self):
        self.code = []
        self.labels = {}
        self.fix = []
        self.nlab = 0
        self.next_reg = 1
        self.reg_names = {}

    def reg(self, name, n=1):
        """n consecutive registers; returns the first (or a list for n > 1)."""
        r = self.next_reg
        self.next_reg += n
        assert self.next_reg <= 512, "out of registers"
        self.reg_names[name] = r
        return r if n == 1 else list(range(r, r + n))

    def label(self, name=None):
        if name is None:
            self.nlab += 1
            name = f"_L{self.nlab}"
        return name

    def here(self, name):
        assert name not in self.labels, name
        self.labels[name] = len(self.code)

    def emit(self, op, d=0, a=0, b=0, imm=0):
        assert op in BRANCH or -32768 <= imm <= 32767, (op, imm)
        if op in BRANCH:
            self.fix.append(len(self.code))
        self.code.append([op, d, a, b, imm])

    def __getattr__(self, name):
        if name.upper() in OP:
            def f(d=0, a=0, b=0, imm=0, op=name.upper()):
                self.emit(op, d, a, b, imm)
            return f
        raise AttributeError(name)

    def assemble(self):
        for k in self.fix:
            self.code[k][4] = self.labels[self.code[k][4]]
        return [tuple(c) for c in self.code]


# ---- the setup record ---------------------------------------------------------------------------------
GRAD_M = 20          # render_3d_fx.GRAD_RCP: the reciprocal's mantissa bits
XY_F = 12            # render_3d_fx.XY_F: vertex fraction bits


# EMIT's words at the rasteriser's widths (TriangleSetup.Input): x, y; the sign; p0; d/dx; d/dy
RECORD_BITS = [24] * 6 + [1] + [30, 34, 24, 32, 32] + [42, 46, 36, 44, 44] * 2


def wrap(v, bits):
    """v in two's complement at `bits` (1 bit: unsigned), as a narrower register holds it."""
    if bits == 1:
        return v & 1
    m = 1 << bits
    return ((v + (m >> 1)) % m) - (m >> 1)


def setup_record(vs):
    """What EMIT gives the rasteriser for three vertices (x, y, z, 1/w, light/w, u/w, v/w) in the
    order the fan gives them, or None for a zero determinant (nothing drawn): render_3d_fx.py's
    triangle() up to its spans, which the rasteriser's setup takes from here. Sorted by y, stably;
    the plane's numerators from differences to the top vertex; one reciprocal of |det|, its top
    GRAD_M + 1 bits (truncated) into 2^(2 GRAD_M + 1); each gradient n r rounded half up by
    GRAD_M + 1 + e - XY_F and given det's sign."""
    v = sorted(vs, key=lambda t: t[1])
    (x1, y1), (x2, y2), (x3, y3) = [(t[0], t[1]) for t in v]
    det = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)
    if det == 0:
        return None
    d = abs(det)
    e = d.bit_length() - 1
    dn = d >> (e - GRAD_M) if e >= GRAD_M else d << (GRAD_M - e)
    r = (1 << (2 * GRAD_M + 1)) // dn
    sh = GRAD_M + 1 + e - XY_F

    def g(n):
        q = (n * r + (1 << (sh - 1))) >> sh
        return -q if det < 0 else q
    p1, p2, p3 = ([t[k] for k in range(2, 7)] for t in v)
    dx = [g((p2[k] - p1[k]) * (y3 - y1) - (p3[k] - p1[k]) * (y2 - y1)) for k in range(5)]
    dy = [g((p3[k] - p1[k]) * (x2 - x1) - (p2[k] - p1[k]) * (x3 - x1)) for k in range(5)]
    rec = [x1, y1, x2, y2, x3, y3, int(det < 0)] + p1 + dx + dy
    # the fields' widths: a near-degenerate triangle's gradient can be wider, and the setup takes
    # its low bits, as the old gradient unit's resize did
    return [wrap(v, w) for v, w in zip(rec, RECORD_BITS)]


# ---- the simulator ------------------------------------------------------------------------------------
def _fits(v, bits):
    return -(1 << (bits - 1)) <= v < (1 << (bits - 1))


class Sim:
    def __init__(self, code, dl, vrom, wrap):
        self.code = code
        self.r = [0] * 512
        self.acc = 0
        self.dl = dl
        self.vrom = vrom
        self.wrap = wrap
        self.vptr = 0
        self.out_v = [[0] * 7 for _ in range(3)]
        self.out_a = [0] * 12
        self.tris = []
        self.steps = 0
        self.cycles = 0          # the planned pipeline's estimate (Sim.run's timing notes)
        self.why = {"st": 0, "idx": 0, "div": 0, "vout": 0, "branch": 0, "brfwd": 0}
        self.brfwd_at = collections.Counter()

    def w(self, d, v):
        if not _fits(v, 48):
            raise OverflowError(f"R{d} = {v} at pc {self.pc}")
        if d:
            self.r[d] = v

    ACC_BITS = 72

    def acc_check(self, v):
        lim = 1 << (self.ACC_BITS - 1)
        assert -lim < v < lim, f"accumulator value {v} over {self.ACC_BITS} bits at pc {self.pc}"

    def op36(self, a):
        v = self.r[a]
        if not _fits(v, 36):
            raise OverflowError(f"operand R{a} = {v} at pc {self.pc}")
        return v

    MULS = {"MUL", "MAC", "MSB"}
    REGBR = {"BZ", "BNZ", "BLTZ", "BGEZ", "BGTZ", "BLT", "BGE", "BEQ", "BNE"}
    TWOBR = {"BLT", "BGE", "BEQ", "BNE"}
    # no register result through M: what the result forward cannot come from
    NOWRITE = {"NOP", "MUL", "MAC", "MSB", "LDA", "ADA", "ADAV", "ASHL", "STX", "VSEEK", "AOUT",
               "VOUT", "EMIT", "J", "JAL", "RET", "BZ", "BNZ", "BLTZ", "BGEZ", "BGTZ", "BLT", "BGE",
               "BEQ", "BNE", "BACCN", "BACCNN", "HALT"}
    STS = {"ST", "STF", "STV", "STVW"}

    def run(self, pc):
        """Timing estimate (self.cycles): one instruction a clock, and a taken branch, jump, call
        or return 2 more (resolved in execute); the accumulator stores execute at the
        accumulator's stage, so an instruction reading a store's result in the very next slot
        waits 1; LDX, STX, TRSQ, TRCP, DL, SHLV, LOG2 and NORM 1 more; DIV its quotient bits + 1. EMIT
        holds the engine while the record, 22 words, is read out of the register file (22). A
        register branch reading the result of the instruction before it waits 1 (hng64_geo.sv,
        brFwd); self.brfwd_at counts those by pc."""
        self.pc = pc
        stack = []
        r = self.r
        prev = None
        prev_st = 0
        prev_wd = 0
        while True:
            op, d, a, b, i = self.code[self.pc]
            self.steps += 1
            self.cycles += 1
            if prev_wd and op in self.REGBR and (a == prev_wd or (op in self.TWOBR and b == prev_wd)):
                self.cycles += 1
                self.why["brfwd"] += 1
                self.brfwd_at[self.pc] += 1
            prev_wd = 0 if op in self.NOWRITE else d
            if prev_st and prev_st in (a, b) and op not in ("J", "JAL", "MOVI", "HALT", "EMIT"):
                self.cycles += 1
                self.why["st"] += 1
            prev_st = d if op in self.STS else 0
            if op in ("LDX", "STX", "TRSQ", "TRCP", "DL", "SHLV", "LOG2", "NORM"):
                self.cycles += 1
                self.why["idx"] += 1
            elif op == "DIV":
                self.cycles += i
                self.why["div"] += i
            elif op == "EMIT":
                self.cycles += 21
                self.why["vout"] += 21

            prev = op
            nxt = self.pc + 1
            if op in ("LDA", "ADA"):
                self.acc_check(r[a] << i)
            elif op == "ADAV":
                self.acc_check(r[a] << r[b])
            if op == "MUL":
                self.acc = self.op36(a) * self.op36(b)
            elif op == "MAC":
                self.acc += self.op36(a) * self.op36(b)
            elif op == "MSB":
                self.acc -= self.op36(a) * self.op36(b)
            elif op == "LDA":
                self.acc = r[a] << i
            elif op == "ADA":
                self.acc += r[a] << i
            elif op == "ADAV":
                self.acc += r[a] << r[b]
            elif op == "ASHL":
                self.acc = self.acc << i if i >= 0 else self.acc >> -i
            if op in ("MUL", "MAC", "MSB", "LDA", "ADA", "ADAV", "ASHL"):
                self.acc_check(self.acc)
            elif op == "ST":
                self.w(d, gi.rnd(self.acc, i))
            elif op == "STF":
                self.w(d, self.acc >> i if i >= 0 else self.acc << -i)
            elif op == "STV":
                self.w(d, gi.rnd(self.acc, r[b] + i))
            elif op == "STVW":
                self.w(d, wrap(gi.rnd(self.acc, r[b] + i), 48))
            elif op == "DIV":
                q = abs(self.acc) // abs(r[b])
                assert q < (1 << i), f"quotient {q} over 2^{i} at pc {self.pc}"
                self.w(d, -q if (self.acc < 0) != (r[b] < 0) else q)
            elif op == "ADD":
                self.w(d, r[a] + r[b])
            elif op == "SUB":
                self.w(d, r[a] - r[b])
            elif op == "MIN":
                self.w(d, min(r[a], r[b]))
            elif op == "MAX":
                self.w(d, max(r[a], r[b]))
            elif op == "OR":
                self.w(d, r[a] | r[b])
            elif op == "AND":
                self.w(d, r[a] & r[b])
            elif op == "ADDI":
                self.w(d, r[a] + i)
            elif op == "ANDI":
                self.w(d, r[a] & i)
            elif op == "SHLI":
                self.w(d, r[a] << i)
            elif op == "SHRI":
                self.w(d, r[a] >> i)
            elif op == "SHLV":
                self.w(d, r[a] << r[b] if r[b] >= 0 else r[a] >> -r[b])
            elif op == "MOVI":
                self.w(d, i)
            elif op == "NEG":
                self.w(d, -r[a])
            elif op == "ABS":
                self.w(d, abs(r[a]))
            elif op == "SEXT16":
                v = r[a] & 0xFFFF
                self.w(d, v - 0x10000 if v & 0x8000 else v)
            elif op == "LOG2":
                self.w(d, r[a].bit_length() - 1 if r[a] > 0 else -1)
            elif op == "NORM":
                e = r[a].bit_length() - 1
                self.w(d, r[a] >> (e - i) if e >= i else r[a] << (i - e))
            elif op == "LDX":
                self.w(d, r[r[a] + r[b]])
            elif op == "STX":
                k = r[a] + r[b]
                assert 0 < k < 512
                r[k] = r[d]
            elif op == "TRSQ":
                self.w(d, gi._RSQ_TABLE[r[a]])
            elif op == "TRCP":
                self.w(d, gi._RCP_TABLE[r[a]])
            elif op == "WRAP":
                self.w(d, self.wrap[r[a] & 0x1F])
            elif op == "DL":
                self.w(d, self.dl[r[a] & 0xFF])
            elif op == "VSEEK":
                self.vptr = r[a]
            elif op == "VRD":
                self.w(d, int(self.vrom[self.vptr]) if self.vptr < len(self.vrom) else 0)
                self.vptr += 1
            elif op == "VRDS":
                v = int(self.vrom[self.vptr]) & 0xFFFF if self.vptr < len(self.vrom) else 0
                self.w(d, v - 0x10000 if v & 0x8000 else v)
                self.vptr += 1
            elif op == "AOUT":
                self.out_a[d] = r[a]
            elif op == "EMIT":
                self.tris.append(([wrap(r[a + k], w) for k, w in enumerate(RECORD_BITS)], list(self.out_a)))
            elif op == "J":
                nxt = i
            elif op == "JAL":
                stack.append(nxt)
                assert len(stack) <= 4
                nxt = i
            elif op == "RET":
                nxt = stack.pop()
            elif op == "BZ":
                nxt = i if r[a] == 0 else nxt
            elif op == "BNZ":
                nxt = i if r[a] != 0 else nxt
            elif op == "BLTZ":
                nxt = i if r[a] < 0 else nxt
            elif op == "BGEZ":
                nxt = i if r[a] >= 0 else nxt
            elif op == "BLT":
                nxt = i if r[a] < r[b] else nxt
            elif op == "BGE":
                nxt = i if r[a] >= r[b] else nxt
            elif op == "BEQ":
                nxt = i if r[a] == r[b] else nxt
            elif op == "BNE":
                nxt = i if r[a] != r[b] else nxt
            elif op == "BACCN":
                nxt = i if self.acc < 0 else nxt
            elif op == "BACCNN":
                nxt = i if self.acc >= 0 else nxt
            elif op == "BGTZ":
                nxt = i if r[a] > 0 else nxt
            elif op == "HALT":
                return
            elif op == "NOP":
                pass
            else:
                raise ValueError(op)
            if nxt != self.pc + 1:
                self.cycles += 2
                self.why["branch"] += 2
            self.pc = nxt


# ---- the check: the engine beside geom_int.IntMachine ----------------------------------------------------
def check(game, frames, dump=False):
    """The engine beside IntMachine on every upload of the trace. dump: also write
    debug/<game>-f<frame>/geo_events.txt for sim/geo_tb: "I samsho vlen", then per event "C" (a
    clearing vblank) or "U" + the display list's 256 words and the wrap table's 32 bytes, in hex,
    followed by the triangles this simulator emits for it ("T" + the 22 words of the setup record
    + 12 attribute fields, decimal) and "E"."""
    import numpy as np
    import render_3d as r3
    import render_3d_fx as fx
    import geo_ucode

    code, entries, regs = geo_ucode.program()
    found = {"uploads": 0, "tris": 0, "bad": 0, "steps": 0, "cycles": 0}
    expect = []
    checked_sim = []

    def attr_of(p):
        wx = min(int(p.tex_mask_x).bit_length() - 1, 31) if p.tex_mask_x else 0
        wy = min(int(p.tex_mask_y).bit_length() - 1, 31) if p.tex_mask_y else 0
        pal = (p.pal_offset + p.color_index) & 0xFFFF if p.flat else p.pal_offset & 0xFFFF
        return [int(bool(p.flat)), int(bool(p.blend)), int(p.tex4bpp), p.tex_index & 15,
                (p.tex_page_small >> 14) & 3, (p.tex_page_small >> 7) & 0x7F, p.tex_page_small & 0x7F,
                pal, (p.texscrollx & 0x3FFF) >> 5, (p.texscrolly & 0x3FFF) >> 5, wx, wy]

    orig_draw = fx.FxRenderer.draw_shaded

    def draw_shaded(self, p):
        iv = getattr(p, "iv", None)
        if iv is not None:
            for j in range(1, len(iv) - 1):
                vs = [[v[k] for k in ("x", "y", "z", "rw", "l", "u", "v")] for v in (iv[0], iv[j], iv[j + 1])]
                rec = setup_record(vs)
                if rec is not None:                    # a zero determinant draws nothing
                    expect.append((rec, attr_of(p)))
        return orig_draw(self, p)
    fx.FxRenderer.draw_shaded = draw_shaded

    class Checked(gi.IntMachine):
        def __init__(self, *a, **k):
            self.sim = None
            super().__init__(*a, **k)
            self.sim = Sim(code, self.dl, self.verts, self.wrap)
            checked_sim.append(self.sim)
            self.sim.r[regs["samsho"]] = int(self.samsho_hack)
            self.sim.r[regs["vlen"]] = len(self.verts)
            self.sim.run(entries["init"])
            if ev:
                ev[0].write(f"I {int(self.samsho_hack)} {len(self.verts)}\n")

        def clear3d(self):
            super().clear3d()
            if self.sim is not None:
                self.sim.run(entries["clear"])
                if ev:
                    ev[0].write("C\n")

        def write(self, addr, mask, data, vpos=None):
            if addr != 0x20300200:
                return super().write(addr, mask, data, vpos)
            expect.clear()
            super().write(addr, mask, data, vpos)
            s = self.sim
            s.tris = []
            s.dl, s.wrap = self.dl, self.wrap
            before = s.steps
            cyc_before = s.cycles
            s.run(entries["upload"])
            found["uploads"] += 1
            if ev:
                f = ev[0]
                f.write("U " + " ".join(f"{int(w) & 0xFFFF:x}" for w in self.dl) + " "
                        + " ".join(f"{int(b) & 0xFF:x}" for b in self.wrap) + "\n")
                for rec, at in s.tris:
                    f.write("T " + " ".join(str(v) for v in rec) + " "
                            + " ".join(str(v) for v in at) + "\n")
                f.write(f"E {s.cycles - cyc_before}\n")
            if not self.draw:
                return
            found["steps"] += s.steps - before
            found["cycles"] += s.cycles - cyc_before
            got = s.tris
            found["tris"] += len(expect)
            n = max(len(got), len(expect))
            for t in range(n):
                g = got[t] if t < len(got) else None
                e = expect[t] if t < len(expect) else None
                same = g is not None and e is not None and g[1] == e[1]
                if same:
                    # flat: positions, sign and z only (its other channels are not drawn)
                    idx = [0, 1, 2, 3, 4, 5, 6, 7, 12, 17] if e[1][0] else range(22)
                    same = all(g[0][k] == e[0][k] for k in idx)
                if not same:
                    found["bad"] += 1
                    if found["bad"] <= 5:
                        print(f"triangle {t} of upload {found['uploads']}:")
                        print(f"  engine {g}")
                        print(f"  model  {e}")

    ev = []
    r3.Machine = Checked
    r3.Renderer = fx.FxRenderer
    for f in frames:
        d = Path(__file__).resolve().parent.parent / "debug" / f"{game}-f{f}"
        wl = d / "wlog.trace"
        if dump:
            ev[:] = [open(d / "geo_events.txt", "w")]
        r3.run(game, [f], trace=wl, capture=True) if wl.exists() else r3.run(game, [f])
        if ev:
            ev[0].close()
            ev.clear()
    print(f"{game} {frames}: {found['uploads']} uploads, {found['tris']} triangles drawn by the model, "
          f"{found['bad']} differ; {found['steps']} engine instructions in drawn uploads, "
          f"{found['cycles']} clocks estimated")
    print("  extra clocks over the whole run, by cause:", checked_sim[0].why if checked_sim else "")
    if checked_sim and checked_sim[0].brfwd_at:
        print("  branch-forward waits by pc:", ", ".join(
            f"{pc}: {n}" for pc, n in checked_sim[0].brfwd_at.most_common(12)))
    return found["bad"] == 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--dump"]
    ok = check(args[0], [int(f) for f in args[1:]], dump="--dump" in sys.argv)
    sys.exit(0 if ok else 1)
