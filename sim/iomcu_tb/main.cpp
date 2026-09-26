// SPDX-License-Identifier: GPL-3.0-or-later
//
// The IO MCU subsystem against MAME's own instruction trace.
//
//     python scripts/rom_regions.py hng64 iomcu
//     python scripts/mame_insn_trace.py sams64 3000000 --cpu iomcu \
//         --regs A,W,B,C,D,E,H,L,SP,RB --width 4
//     scripts/run_verilator.sh iomcu_tb +n=3000000
//
// Every instruction the core fetches is compared with the trace line at the same index: the PC,
// the eight registers of the current bank, SP and RBS. The trace's values are the state BEFORE
// that instruction runs, which is what the core exports as the opcode arrives.
//
// NOTHING IS TAKEN FROM THE TRACE BUT THE COMPARISON. The interrupts come from the subsystem's
// own timer 2, so the instruction at which each one is taken depends on every instruction's
// cycle count and on the timer's period: a wrong count anywhere before an interrupt moves it
// to a different instruction, and the comparison fails there. In the traced window the MIPS
// never commands the MCU (no INT0) and serial 1 never starts, so this is a complete account of
// what MAME ran. The inputs are held idle (0xff, active low), as MAME's are with nothing
// pressed.
//
// The registers live in internal RAM (0x0040 + RBS*8 + r). The bench keeps its own copy from the
// core's write port rather than reading the RAM, which would need a second read port on it.

#include "Vtb_iomcu.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

std::string arg(const char *key, const char *def) {
    const char *v = Verilated::commandArgsPlusMatch(key);
    if (v && v[0]) {
        const char *eq = strchr(v, '=');
        if (eq) return std::string(eq + 1);
    }
    return def;
}

struct Line {
    uint16_t pc;
    uint16_t reg[8];        // in MAME's _regs8 order: A W C B E D L H
    uint16_t sp;
    uint16_t rbs;
    std::string text;
};

// the trace's column order is the --regs order, A W B C D E H L; _regs8 is A W C B E D L H
const int COL_TO_REG[8] = {0, 1, 3, 2, 5, 4, 7, 6};

const char *REGNAME[8] = {"A", "W", "C", "B", "E", "D", "L", "H"};

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string rompath = arg("rom", "debug/rom/hng64-iomcu.bin");
    const std::string trpath = arg("trace", "debug/sams64-insn/sams64.tr");
    const long limit = atol(arg("n", "200000").c_str());
    // 93.75 MHz against 8 MHz is 11.7 core clocks a tick; 12 gives every instruction its full
    // budget. The comparison depends on ticks, not on this ratio.
    const int CE_DIV = atoi(arg("cediv", "12").c_str());

    std::vector<uint8_t> region(0x10000, 0);
    {
        FILE *f = fopen(rompath.c_str(), "rb");
        if (!f) { fprintf(stderr, "cannot open %s\n", rompath.c_str()); return 2; }
        if (fread(region.data(), 1, 0x10000, f) != 0x10000) {
            fprintf(stderr, "%s is not a 64 KB region image\n", rompath.c_str());
            return 2;
        }
        fclose(f);
    }

    std::vector<Line> tr;
    {
        FILE *f = fopen(trpath.c_str(), "r");
        if (!f) { fprintf(stderr, "cannot open %s\n", trpath.c_str()); return 2; }
        char buf[512];
        while (tr.size() < size_t(limit) && fgets(buf, sizeof buf, f)) {
            Line l{};
            unsigned v[10];
            char rest[400];
            if (sscanf(buf, "%x %x %x %x %x %x %x %x %x %x %399[^\n]",
                       &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9],
                       rest) != 11)
                continue;
            for (int c = 0; c < 8; c++) l.reg[COL_TO_REG[c]] = uint16_t(v[c]);
            l.sp = uint16_t(v[8]);
            l.rbs = uint16_t(v[9]);
            unsigned pc;
            if (sscanf(rest, "%x:", &pc) != 1) continue;
            l.pc = uint16_t(pc);
            l.text = rest;
            tr.push_back(l);
        }
        fclose(f);
    }
    if (tr.empty()) { fprintf(stderr, "no usable lines in %s\n", trpath.c_str()); return 2; }

    auto *dut = new Vtb_iomcu;
    dut->reset = 1;
    dut->ce = 0;
    dut->int0 = 0;
    dut->in_all = 0xff;
    dut->rom_we = 0;

    std::vector<uint8_t> iram(0x200, 0);        // the bench's copy of 0x0040-0x023f
    long cyc = 0;

    auto tick = [&]() {
        cyc++;
        dut->ce = (cyc % CE_DIV) == 0;
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
        if (dut->dbg_we && dut->dbg_addr >= 0x40 && dut->dbg_addr <= 0x23f)
            iram[dut->dbg_addr - 0x40] = dut->dbg_wdata;
    };

    // the ROM through the load port, with the core held in reset
    for (int i = 0; i < 0x4000; i++) {
        dut->rom_we = 1;
        dut->rom_addr = i;
        dut->rom_data = region[0xc000 + i];
        tick();
    }
    dut->rom_we = 0;
    for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    // the interrupt vectors, only to count the interrupts the run takes
    uint16_t vec[16];
    for (int pri = 0; pri < 16; pri++) {
        uint32_t a = 0xffe0 + (15 - pri) * 2;
        vec[pri] = uint16_t(region[a] | (region[a + 1] << 8));
    }

    size_t idx = 0;
    long bad = 0;
    long taken = 0;
    const long guard_max = 400L * long(tr.size()) + 10000;
    long guard = 0;

    while (idx < tr.size() && ++guard < guard_max) {
        tick();
        if (dut->dbg_unimpl) {
            printf("iomcu: opcode %02x %02x at %04x is not implemented (trace line %zu: %s)\n",
                   dut->dbg_op, dut->dbg_op1, dut->dbg_pc, idx,
                   idx < tr.size() ? tr[idx].text.c_str() : "");
            delete dut;
            return 1;
        }
        if (!dut->dbg_fetch) continue;

        const Line &l = tr[idx];
        bool ok = dut->dbg_pc == l.pc && dut->dbg_sp == l.sp && dut->dbg_rbs == l.rbs;
        for (int r = 0; r < 8 && ok; r++)
            if (iram[dut->dbg_rbs * 8 + r] != uint8_t(l.reg[r])) ok = false;
        if (!ok) {
            printf("iomcu: diverged at trace line %zu\n", idx);
            printf("  want pc=%04x sp=%04x rb=%x", l.pc, l.sp, l.rbs);
            for (int r = 0; r < 8; r++) printf(" %s=%02x", REGNAME[r], uint8_t(l.reg[r]));
            printf("\n  got  pc=%04x sp=%04x rb=%x", dut->dbg_pc, dut->dbg_sp, dut->dbg_rbs);
            for (int r = 0; r < 8; r++) printf(" %s=%02x", REGNAME[r], iram[dut->dbg_rbs * 8 + r]);
            printf("\n  trace: %s\n", l.text.c_str());
            if (idx) printf("  after: %s\n", tr[idx - 1].text.c_str());
            bad++;
            break;
        }
        if (idx) {
            const Line &p = tr[idx - 1];
            if (uint16_t(l.sp + 3) == p.sp)
                for (int pri = 3; pri < 16; pri++)
                    if (l.pc == vec[pri]) { taken++; break; }
        }
        idx++;
    }

    if (dut->dbg_overrun) printf("iomcu: an instruction outran its cycle budget\n");
    if (guard >= guard_max) printf("iomcu: stalled after %zu instructions\n", idx);
    printf("iomcu: %zu of %zu instructions match MAME, %ld interrupts from the timer\n",
           idx, tr.size(), taken);
    // an overrun means an instruction took longer than MAME charges it, so timing is not MAME's
    const bool overrun = dut->dbg_overrun;
    delete dut;
    return (bad || idx != tr.size() || overrun) ? 1 : 0;
}
