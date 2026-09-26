// SPDX-License-Identifier: GPL-3.0-or-later
//
// The main CPU's I/O devices against MAME's own bus trace.
//
//     python scripts/mame_sys_trace.py sams64 ...      -> debug/sams64-sys/sams64_sys.trace
//     python scripts/rom_regions.py sams64 gameprg
//     scripts/run_verilator.sh io_tb
//
// The trace is every main-CPU write and every read of the I/O ranges, in order, from a boot to
// frame 900. Each I/O access in it is driven into hng64_io in the same order, and:
//
//   * a read is compared with MAME's answer wherever that answer does not depend on timing the
//     bench cannot reproduce. The interrupt level depends on when the video raised interrupts,
//     the dual-port RAM on what the IO MCU wrote, the RTC's time registers on the host clock:
//     those are driven but not compared, and counted apart.
//   * a write that MAME's handler turns into more writes - the DMA's copy, a sprite clear -
//     has those writes next in the trace, because MAME's taps see them as they happen. The
//     writes hng64_io makes (through the DMA onto the backing store, or onto the video port)
//     are compared with them one for one.
//   * a write to a video register is compared with what reaches the video port.
//
// The CPU's own accesses to plain memory are skipped: they do not come to hng64_io. The DMA's
// source is real, sams64's `gameprg`, in the DDR3 model, so its copy is compared byte for byte.

#include "Vtb_io.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <string>
#include <utility>
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

struct Ev {
    long seq;
    bool w;
    uint32_t addr, mask, data;
};

// hng64_bus.sv's is_store
bool is_store(uint32_t a) {
    return a < 0x01000000 || (a >= 0x04000000 && a < 0x06000000) ||
           (a >= 0x1fc00000 && a < 0x1fc80000) || (a >= 0x20100000 && a < 0x20180000) ||
           (a >= 0x30100000 && a < 0x30160000) || (a >= 0x30200000 && a < 0x30260000) ||
           (a >= 0x60200000 && a < 0x60400000);
}

// what each I/O read's answer depends on, for the tally
const char *device(uint32_t a) {
    if (a >= 0x1f700000 && a < 0x1f701100) return "sysregs";
    if (a >= 0x1f701100 && a < 0x1f701120) return "irqc";
    if (a >= 0x1f701200 && a < 0x1f701280) return "dmac";
    if (a >= 0x1f702100 && a < 0x1f702180) return "rtc";
    if (a >= 0x1f800000 && a < 0x1f804000) return "nvram";
    if (a >= 0x1f808000 && a < 0x1f808800) return "dualport";
    if (a >= 0x60000000 && a < 0x60200000) return "soundram2";
    if (a >= 0x68000000 && a < 0x68000010) return "mailbox";
    if (a >= 0xc0000000 && a < 0xc0001008) return "com";
    return "other";
}

// a read whose answer the bench can reproduce
bool checkable(uint32_t a) {
    std::string d = device(a);
    if (d == "irqc" || d == "dualport") return false;
    if (d == "rtc") {
        uint32_t reg = (a >> 3) & 0xf;                 // only the control registers
        return (a & 4) && reg >= 0xd;
    }
    return true;
}

// the video port's region bases, by v_sel
const uint32_t V_BASE[5] = {0x20000000, 0x20010000, 0x20190000, 0x20200000, 0x20208000};

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string trpath = arg("trace", "debug/sams64-sys/sams64_sys.trace");
    const std::string prgpath = arg("prg", "debug/rom/sams64-gameprg.bin");
    const long limit = atol(arg("n", "4000000").c_str());

    std::vector<uint8_t> prg;
    {
        FILE *f = fopen(prgpath.c_str(), "rb");
        if (!f) { fprintf(stderr, "cannot open %s\n", prgpath.c_str()); return 2; }
        fseek(f, 0, SEEK_END);
        prg.resize(ftell(f));
        fseek(f, 0, SEEK_SET);
        if (fread(prg.data(), 1, prg.size(), f) != prg.size()) return 2;
        fclose(f);
    }

    std::vector<Ev> ev;
    {
        FILE *f = fopen(trpath.c_str(), "r");
        if (!f) { fprintf(stderr, "cannot open %s\n", trpath.c_str()); return 2; }
        char buf[256];
        while (long(ev.size()) < limit && fgets(buf, sizeof buf, f)) {
            if (buf[0] == '#') continue;
            Ev e{};
            char rw;
            unsigned a, m, d;
            if (sscanf(buf, "%ld %c %x %x %x", &e.seq, &rw, &a, &m, &d) != 5) continue;
            e.w = (rw == 'w');
            e.addr = a;
            e.mask = m;
            e.data = d;
            ev.push_back(e);
        }
        fclose(f);
    }

    auto *dut = new Vtb_io;
    dut->reset = 1;
    dut->io_req = 0;
    dut->vblank = 0;
    dut->rtc = 0x04092612233059ULL;       // an arbitrary time; its registers are not compared
    dut->v_ack = 0;
    dut->DDRAM_BUSY = 0;
    dut->DDRAM_DOUT_READY = 0;

    // ---- the models around it ---------------------------------------------------------------------
    std::deque<std::pair<long, uint64_t>> ddr_q;
    std::vector<uint8_t> dpram(0x800, 0);
    std::map<uint64_t, uint32_t> vmem;                  // (sel << 32 | addr) -> dword
    uint8_t dp_q = 0;
    bool v_pending = false;

    // what hng64_io did besides answering: (address, data) writes, in order
    std::deque<std::pair<uint32_t, uint32_t>> effects;
    struct VWrite { uint32_t addr, data; uint8_t be; };
    std::vector<VWrite> vwrites;                        // this access's video-port writes

    long cyc = 0;
    auto step2x = [&]() {                               // one clk2x period
        cyc++;
        dut->clk2x = 0;
        dut->eval();
        // DDR3: gameprg at offset 0
        if (dut->DDRAM_RD && !dut->DDRAM_BUSY) {
            uint64_t byte = uint64_t(dut->DDRAM_ADDR & 0x1ffffff) << 3;
            uint64_t d = 0;
            for (int i = 7; i >= 0; i--) d = (d << 8) | (byte + i < prg.size() ? prg[byte + i] : 0);
            ddr_q.emplace_back(cyc + 8, d);
            static int dbg = 0;
            if (getenv("IO_DBG") && dbg++ < 4)
                printf("DBG ddr read byte %llx -> %016llx\n", (unsigned long long)byte,
                       (unsigned long long)d);
        }
        dut->DDRAM_DOUT_READY = 0;
        if (!ddr_q.empty() && ddr_q.front().first <= cyc) {
            dut->DDRAM_DOUT = ddr_q.front().second;
            dut->DDRAM_DOUT_READY = 1;
            ddr_q.pop_front();
        }
        const bool rise1x = (cyc & 1) == 0;
        dut->clk2x = 1;
        if (rise1x) dut->clk1x = 1;
        dut->eval();
        // the DMA's writes onto the backing store, as big-endian dwords
        if (getenv("IO_DBG") && dut->dma_st_req) {
            static int dbg = 0;
            if (dbg++ < 6)
                printf("DBG dma we=%d addr=%08x wdata=%016llx be=%02x rdata=%016llx\n",
                       dut->dma_st_we, dut->dma_st_addr, (unsigned long long)dut->dma_st_wdata,
                       dut->dma_st_be, (unsigned long long)dut->DDRAM_DOUT);
        }
        if (dut->dma_st_req && dut->dma_st_we) {
            const int lane = (dut->dma_st_be == 0xf0) ? 4 : 0;
            uint32_t v = 0;
            for (int k = 0; k < 4; k++)
                v = (v << 8) | uint8_t(dut->dma_st_wdata >> (8 * (lane + k)));
            effects.emplace_back(dut->dma_st_addr + lane, v);
        }
        if (rise1x) {
            // the dual-port RAM's MIPS side: a byte the clock after its address
            dut->dp_rdata = dp_q;
            if (dut->dp_we) dpram[dut->dp_addr] = dut->dp_wdata;
            dp_q = dpram[dut->dp_addr];
            // the video port: acknowledged the clock after the request
            dut->v_ack = 0;
            if (v_pending) { dut->v_ack = 1; v_pending = false; }
            if (dut->v_req) {
                const uint64_t key = (uint64_t(dut->v_sel) << 32) | dut->v_addr;
                if (dut->v_we) {
                    uint32_t old = vmem[key], nw = old;
                    for (int k = 0; k < 4; k++)
                        if (dut->v_be & (1 << k))
                            nw = (nw & ~(0xffu << (8 * k))) | (dut->v_wdata & (0xffu << (8 * k)));
                    vmem[key] = nw;
                    vwrites.push_back({V_BASE[dut->v_sel] + dut->v_addr * 4u, dut->v_wdata,
                                       uint8_t(dut->v_be)});
                }
                dut->v_rdata = vmem[key];
                v_pending = true;
            }
        }
        dut->eval();
        dut->clk2x = 0;
        dut->eval();
        if (rise1x) { dut->clk1x = 0; dut->eval(); }
    };

    for (int i = 0; i < 16; i++) step2x();
    dut->reset = 0;
    for (int i = 0; i < 20000; i++) step2x();           // the SDRAM's initialisation

    // ---- the replay -----------------------------------------------------------------------------------
    std::map<std::string, std::pair<long, long>> tally;  // device -> (compared, differing)
    std::map<std::string, long> driven;                  // reads driven but not compared
    long io_n = 0, bad = 0, eff_ok = 0, eff_bad = 0, vfwd_ok = 0, vfwd_bad = 0;
    int shown = 0;

    auto be_of = [](uint32_t mask) {
        uint8_t b = 0;
        for (int k = 0; k < 4; k++) if (mask & (0xffu << (8 * k))) b |= uint8_t(1 << k);
        return b;
    };

    size_t i = 0;
    while (i < ev.size()) {
        const Ev &e = ev[i];
        if (is_store(e.addr)) { i++; continue; }     // the CPU's own plain-memory traffic

        io_n++;
        vwrites.clear();
        dut->io_addr = e.addr & ~3u;
        dut->io_we = e.w;
        dut->io_be = be_of(e.mask);
        dut->io_wdata = e.data;
        dut->io_req = 1;
        step2x(); step2x();                               // one clk1x cycle
        dut->io_req = 0;
        long guard = 0;
        while (!dut->io_ack && ++guard < 2000000) step2x();
        if (guard >= 2000000) {
            printf("io: no ack for seq %ld %c %08x\n", e.seq, e.w ? 'w' : 'r', e.addr);
            return 1;
        }
        const uint32_t got = dut->io_rdata;
        step2x(); step2x();

        const std::string dev = device(e.addr);
        if (!e.w) {
            if (checkable(e.addr)) {
                auto &t = tally[dev];
                t.first++;
                if ((got & e.mask) != (e.data & e.mask)) {
                    t.second++;
                    bad++;
                    if (shown++ < 12)
                        printf("  seq %ld: read %08x mask %08x: got %08x, MAME %08x\n", e.seq,
                               e.addr, e.mask, got & e.mask, e.data & e.mask);
                }
            } else {
                driven[dev]++;
            }
        }

        // a write to a video register reaches the video port unchanged
        const bool vreg = (e.addr >= 0x20000000 && e.addr < 0x2000c000) ||
                          (e.addr >= 0x20010000 && e.addr < 0x20010014) ||
                          (e.addr >= 0x20190000 && e.addr < 0x20190038) ||
                          (e.addr >= 0x20200000 && e.addr < 0x20204000) ||
                          (e.addr >= 0x20208000 && e.addr < 0x20208060);
        if (e.w && vreg) {
            if (vwrites.size() == 1 && vwrites[0].addr == (e.addr & ~3u) &&
                vwrites[0].be == be_of(e.mask) &&
                (vwrites[0].data & e.mask) == (e.data & e.mask)) {
                vfwd_ok++;
            } else {
                vfwd_bad++;
                if (shown++ < 12)
                    printf("  seq %ld: video write %08x = %08x did not reach the port as one\n",
                           e.seq, e.addr, e.data);
            }
            vwrites.clear();
        }

        // what else it did: the sprite clears' writes, and the DMA's
        for (const auto &vw : vwrites) effects.emplace_back(vw.addr, vw.data);
        i++;
        while (!effects.empty()) {
            if (i >= ev.size()) break;
            const Ev &n = ev[i];
            const auto want = effects.front();
            effects.pop_front();
            if (n.w && n.addr == want.first && (n.data & n.mask) == (want.second & n.mask)) {
                eff_ok++;
            } else {
                eff_bad++;
                if (shown++ < 12)
                    printf("  after seq %ld: wrote %08x = %08x, MAME next has seq %ld %c %08x = "
                           "%08x\n", e.seq, want.first, want.second, n.seq, n.w ? 'w' : 'r',
                           n.addr, n.data);
            }
            i++;
        }
    }

    printf("io: %ld accesses driven; reads compared by device:\n", io_n);
    for (const auto &t : tally)
        printf("  %-10s %7ld compared, %ld differ\n", t.first.c_str(), t.second.first,
               t.second.second);
    for (const auto &d : driven)
        printf("  %-10s %7ld driven, not compared (timing or MCU dependent)\n", d.first.c_str(),
               d.second);
    printf("io: video writes forwarded %ld, wrong %ld; side-effect writes %ld match, %ld differ\n",
           vfwd_ok, vfwd_bad, eff_ok, eff_bad);
    if (dut->dma_err) printf("io: the DMA reached outside the backing store\n");
    printf("io: %ld of %ld compared reads differ\n", bad, [&] {
        long n = 0;
        for (const auto &t : tally) n += t.second.first;
        return n;
    }());
    delete dut;
    return (bad || vfwd_bad || eff_bad) ? 1 : 0;
}
