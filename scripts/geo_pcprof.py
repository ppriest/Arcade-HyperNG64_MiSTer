# SPDX-License-Identifier: GPL-3.0-or-later
# The geometry engine's clocks by microcode routine and instruction, from g3d_tb's +pcprof file:
#     scripts/run_verilator.sh g3d_tb +cap=... +prof +pcprof=FILE
#     python scripts/geo_pcprof.py FILE
# Each instruction's clocks are issued, stalled (E held) or bubble (E empty, or after a taken branch).
import sys, bisect
sys.path.insert(0, "scripts")
import geo_ucode, geo_engine
seen = []
_init = geo_engine.Asm.__init__
def _cap(self, *a, **k):
    _init(self, *a, **k); seen.append(self)
geo_engine.Asm.__init__ = _cap
geo_ucode.Asm.__init__ = _cap
code, entries, names = geo_ucode.program()
A = seen[-1]
labs = sorted((v, k) for k, v in A.labels.items())
pcs = [v for v, _ in labs]
def lab(pc):
    i = bisect.bisect_right(pcs, pc) - 1
    return labs[i][1] if i >= 0 else "?"
rows = [list(map(int, l.split())) for l in open(sys.argv[1])]
tot = [sum(r[k] for r in rows) for k in (1, 2, 3)]
print("total go %d stall %d bubble %d = %d" % (*tot, sum(tot)))
by = {}
for pc, g, s, b in rows:
    d = by.setdefault(lab(pc), [0, 0, 0]); d[0] += g; d[1] += s; d[2] += b
print("by routine (go/stall/bubble):")
for k, v in sorted(by.items(), key=lambda kv: -sum(kv[1]))[:20]:
    print("  %-22s %8d  %7d %7d %7d" % (k, sum(v), *v))
print("top bubble pcs:")
for pc, g, s, b in sorted(rows, key=lambda r: -r[3])[:12]:
    op = A.code[pc][0] if pc < len(A.code) else "?"
    print("  %4d %-18s %-6s go %7d stall %7d bubble %7d" % (pc, lab(pc), geo_engine.OPS[op] if isinstance(op, int) else op, g, s, b))
print("top stall pcs (op d a b imm):")
for pc, g, s, b in sorted(rows, key=lambda r: -r[2])[:25]:
    ins = A.code[pc]; prev = A.code[pc-1]
    nm = lambda i: geo_engine.OPS[i[0]] if isinstance(i[0], int) else i[0]
    print("  %4d %-16s %-5s %s  stall %6d go %6d  | prev %-5s %s" % (pc, lab(pc), nm(ins), ins[1:], s, g, nm(prev), prev[1:]))
