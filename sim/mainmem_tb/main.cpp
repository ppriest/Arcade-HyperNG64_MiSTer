// SPDX-License-Identifier: GPL-3.0-or-later
//
// The CPU's backing store against real memory.
//
//     scripts/run_verilator.sh mainmem_tb
//
// Main RAM and the BIOS are filled through the SDRAM download port, `gameprg` into the model of
// the DDRAM window, both with a pattern that makes a wrong address or a swapped byte obvious.
// Then every combination the bridge can ask for is read back and compared: 1, 2 and 4 beats from
// each region, and byte-enabled writes to main RAM read back through the same path.

#include "Vtb_mainmem.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <utility>
#include <vector>

namespace {

// a byte that depends on its own address, so a misdirected read cannot look right
// A multiply alone leaves the low byte blind to large power-of-two address differences - the
// original form here gave identical bytes 128 MB apart, which hid a gameprg address bug - so the
// product is folded back on itself until every address bit reaches the byte.
uint8_t pattern(uint32_t byte_addr) {
    uint32_t v = byte_addr * 2654435761u;
    v ^= v >> 16;
    v *= 0x85ebca6bu;
    v ^= v >> 13;
    v *= 0xc2b2ae35u;
    v ^= v >> 16;
    return uint8_t(v);
}

std::string arg(const char *key, const char *def) {
    const char *v = Verilated::commandArgsPlusMatch(key);
    if (v && v[0]) {
        const char *eq = strchr(v, '=');
        if (eq) return std::string(eq + 1);
    }
    return def;
}

constexpr uint32_t RAM_BYTES   = 0x8000;      // enough to exercise, not the whole 16 MB
constexpr uint32_t BIOS_CPU    = 0x1fc00000;
constexpr uint32_t BIOS_SDRAM  = 0x1400000;
constexpr uint32_t PRG_CPU     = 0x04000000;
constexpr uint32_t PRG_BYTES   = 0x8000;

// the plain-memory regions outside RAM, at the SDRAM offsets docs/MEMORY.md gives them
struct Region { const char *name; uint32_t cpu, sdram; };
constexpr Region PLAIN[] = {
    {"sound RAM", 0x60200000, 0x1000000},
    {"tile VRAM", 0x20100000, 0x1500000},
    {"3D buffer A", 0x30100000, 0x1580000},
    {"3D buffer B", 0x30200000, 0x15e0000},
};
constexpr uint32_t PLAIN_BYTES = 0x400;

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const long ROM_LAT = atol(arg("romlat", "8").c_str());
    const int DDR_BUSY = atoi(arg("ddrbusy", "20").c_str());

    auto *dut = new Vtb_mainmem;
    dut->reset = 1;
    dut->st_req = 0;
    dut->d_we = 0;
    dut->DDRAM_BUSY = 0;
    dut->DDRAM_DOUT_READY = 0;

    std::deque<std::pair<long, uint64_t>> ddr_q;
    long cyc = 0;
    uint32_t lfsr = 0xBEEFu;

    auto tick = [&]() {
        cyc++;
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u);
        dut->DDRAM_BUSY = (int(lfsr % 100) < DDR_BUSY);
        dut->eval();
        if (dut->DDRAM_RD && !dut->DDRAM_BUSY) {
            uint64_t byte = uint64_t(dut->DDRAM_ADDR & 0x1ffffff) << 3;
            uint64_t d = 0;
            // gameprg sits at DDR3 offset 0 (prg_base), so DDR3 byte b is CPU byte 0x04000000 + b
            for (int i = 7; i >= 0; i--) d = (d << 8) | pattern(PRG_CPU + uint32_t(byte) + i);
            ddr_q.emplace_back(cyc + ROM_LAT, d);
        }
        dut->DDRAM_DOUT_READY = 0;
        if (!ddr_q.empty() && ddr_q.front().first <= cyc) {
            dut->DDRAM_DOUT = ddr_q.front().second;
            dut->DDRAM_DOUT_READY = 1;
            ddr_q.pop_front();
        }
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    };

    for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;
    for (int i = 0; i < 64; i++) tick();

    // fill main RAM and the BIOS through the download port, the way the loader will
    auto load = [&](uint32_t sdram_byte, uint32_t cpu_byte, uint32_t n) {
        for (uint32_t i = 0; i < n; i += 2) {
            dut->d_addr = (sdram_byte + i) >> 1;
            dut->d_din = uint16_t(pattern(cpu_byte + i)) |
                         (uint16_t(pattern(cpu_byte + i + 1)) << 8);
            dut->d_we = 1;
            tick();
            dut->d_we = 0;
            while (!dut->d_ready) tick();
        }
    };
    load(0, 0, RAM_BYTES);
    load(BIOS_SDRAM, BIOS_CPU, 0x2000);
    // Each region is filled at its SDRAM offset with the pattern of its CPU address, so a read
    // through the CPU path only comes back right if the address translation is right. The
    // regions' ends are filled too, which catches a base that is off by the region's size.
    for (const auto &r : PLAIN) {
        load(r.sdram, r.cpu, PLAIN_BYTES);
    }
    load(0x1000000 + 0x1ffc00, 0x60200000 + 0x1ffc00, 0x400);   // sound RAM's last 1 KB
    load(0x15e0000 + 0x5fc00, 0x30200000 + 0x5fc00, 0x400);     // 3D buffer B's last 1 KB

    // the reference: byte k of a beat sits at bits [8k+7:8k]
    auto want = [&](uint32_t a) {
        uint64_t d = 0;
        for (int i = 7; i >= 0; i--) d = (d << 8) | pattern(a + i);
        return d;
    };

    long bad = 0, checked = 0;
    std::map<uint32_t, uint8_t> written;      // what the writes should have changed

    auto request = [&](uint32_t a, int beats, bool we, uint64_t wdata, uint8_t be) {
        dut->st_addr = a;
        dut->st_beats = beats;
        dut->st_we = we;
        dut->st_wdata = wdata;
        dut->st_be = be;
        dut->st_req = 1;
        tick();
        dut->st_req = 0;
        std::vector<uint64_t> got;
        long guard = 0;
        while (++guard < 20000) {
            tick();
            if (dut->st_rvalid) got.push_back(dut->st_rdata);
            if (dut->st_wdone) break;
            if (!we && int(got.size()) == beats) break;
        }
        if (guard >= 20000) {
            printf("request at %08x never finished: mst=%d cst=%d s_ready=%d%c", a,
                   dut->dbg_mst, dut->dbg_cst, dut->dbg_sready, 10);
            exit(1);
        }
        return got;
    };

    auto check = [&](const char *what, uint32_t a, int beats) {
        auto got = request(a, beats, false, 0, 0);
        if (int(got.size()) != beats) {
            printf("%s at %08x: %d beats, expected %d%c", what, a, int(got.size()), beats, 10);
            bad++;
            return;
        }
        for (int b = 0; b < beats; b++) {
            uint64_t exp = want(a + 8 * b);
            for (int k = 0; k < 8; k++) {
                auto it = written.find(a + 8 * b + k);
                if (it != written.end())
                    exp = (exp & ~(0xffULL << (8 * k))) | (uint64_t(it->second) << (8 * k));
            }
            checked++;
            if (got[b] != exp) {
                if (bad < 8)
                    printf("%s at %08x beat %d: got %016llx want %016llx%c", what, a, b,
                           (unsigned long long)got[b], (unsigned long long)exp, 10);
                bad++;
            }
        }
    };

    for (int beats : {1, 2, 4}) {
        for (uint32_t a = 0; a < 0x400; a += 8 * beats)      check("ram", a, beats);
        for (uint32_t a = 0; a < 0x400; a += 8 * beats)      check("bios", BIOS_CPU + a, beats);
        for (uint32_t a = 0; a < 0x400; a += 8 * beats)      check("gameprg", PRG_CPU + a, beats);
    }
    for (const auto &r : PLAIN)
        for (uint32_t a = 0; a < PLAIN_BYTES; a += 32) check(r.name, r.cpu + a, 4);
    check("sound RAM end", 0x60200000 + 0x1ffc00 + 0x3e0, 4);
    check("3D buffer B end", 0x30200000 + 0x5fc00 + 0x3e0, 4);
    // further in, so a base that is merely plausible still fails
    check("ram high", 0x7000, 4);
    check("bios high", BIOS_CPU + 0x1800, 4);
    check("gameprg high", PRG_CPU + 0x7000, 4);

    printf("reads: %ld of %ld beats differ%c", bad, checked, 10);

    // byte-enabled writes to main RAM, read back through the same path
    struct { uint32_t a; uint64_t d; uint8_t be; } writes[] = {
        {0x100, 0x1122334455667788ULL, 0xff},
        {0x108, 0xaabbccddeeff0011ULL, 0x0f},
        {0x110, 0x0123456789abcdefULL, 0xf0},
        {0x118, 0xdeadbeefcafebabeULL, 0x24},
    };
    for (auto &w : writes) {
        request(w.a, 1, true, w.d, w.be);
        for (int k = 0; k < 8; k++)
            if (w.be & (1 << k)) written[w.a + k] = uint8_t(w.d >> (8 * k));
    }
    for (auto &w : writes) check("readback", w.a, 1);

    // every plain region is writable, and a write lands where a read finds it
    for (const auto &r : PLAIN) {
        const uint64_t d = 0x0f1e2d3c4b5a6978ULL ^ r.cpu;
        request(r.cpu + 0x40, 1, true, d, 0xff);
        for (int k = 0; k < 8; k++) written[r.cpu + 0x40 + k] = uint8_t(d >> (8 * k));
        check(r.name, r.cpu + 0x40, 1);
    }
    // and main RAM at the same low offsets is untouched by those writes
    check("ram under the regions", 0x40, 1);

    // a write outside main RAM is dropped, not applied
    request(BIOS_CPU + 0x40, 1, true, 0xffffffffffffffffULL, 0xff);
    check("bios after write", BIOS_CPU + 0x40, 1);

    printf("mainmem: %ld of %ld beats differ%c", bad, checked, 10);
    delete dut;
    return bad ? 1 : 0;
}
