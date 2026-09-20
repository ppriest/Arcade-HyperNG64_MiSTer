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
uint8_t pattern(uint32_t byte_addr) {
    uint32_t v = byte_addr * 2654435761u;
    return uint8_t((v >> 13) ^ (byte_addr & 0xff));
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
            for (int i = 7; i >= 0; i--) d = (d << 8) | pattern(uint32_t(byte) + i);
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

    // a write outside main RAM is dropped, not applied
    request(BIOS_CPU + 0x40, 1, true, 0xffffffffffffffffULL, 0xff);
    check("bios after write", BIOS_CPU + 0x40, 1);

    printf("mainmem: %ld of %ld beats differ%c", bad, checked, 10);
    delete dut;
    return bad ? 1 : 0;
}
