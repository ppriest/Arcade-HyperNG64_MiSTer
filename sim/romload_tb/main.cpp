// SPDX-License-Identifier: GPL-3.0-or-later
//
// ROM loading end to end.
//
//     scripts/run_verilator.sh romload_tb [+bios=0x4000] [+romlat=8] [+ddrbusy=20]
//
// The layout blob goes in on the ioctl byte path as rom index 1, exactly as
// scripts/build_mra.py emits it. DDR3 holds a pattern that depends on the byte's own address,
// so a wrong base, a swapped byte or a lane written twice cannot look right. The copy runs, and
// the BIOS is read back through hng64_mainmem -- the path the CPU uses -- and compared.
//
// `bios` is small by default because the copy is one 16-bit SDRAM write per 2 bytes: a real
// 1 MB region is 512K transactions, minutes of simulation for the same evidence. The byte just
// past the region is checked to be untouched, which is what would catch a copy that runs long.

#include "Vtb_romload.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <utility>
#include <vector>

namespace {

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

// scripts/build_mra.py's blob: "HNG1" then a base and a size per region, big-endian.
void put32(std::vector<uint8_t> &b, uint32_t v) {
    for (int i = 3; i >= 0; i--) b.push_back(uint8_t(v >> (8 * i)));
}

constexpr uint32_t BIOS_CPU = 0x1fc00000;

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const long ROM_LAT = atol(arg("romlat", "8").c_str());
    const int DDR_BUSY = atoi(arg("ddrbusy", "20").c_str());
    const uint32_t BIOS_SIZE = strtoul(arg("bios", "0x4000").c_str(), nullptr, 0);

    // a layout of the shape build_mra.py produces, with bases that are not zero and not equal
    const uint32_t PRG_BASE = 0x0000000, PRG_SIZE = 0x2000000;
    const uint32_t BIOS_BASE = 0x2000000;
    const uint32_t SCR_BASE = 0x2100000, SCR_SIZE = 0x2000000;
    const uint32_t SPR_BASE = 0x4100000, SPR_SIZE = 0x2000000;

    std::vector<uint8_t> blob = {'H', 'N', 'G', '1'};
    put32(blob, PRG_BASE);  put32(blob, PRG_SIZE);
    put32(blob, BIOS_BASE); put32(blob, BIOS_SIZE);
    put32(blob, SCR_BASE);  put32(blob, SCR_SIZE);
    put32(blob, SPR_BASE);  put32(blob, SPR_SIZE);
    put32(blob, 0);         put32(blob, 0);
    put32(blob, 0);         put32(blob, 0);

    auto *dut = new Vtb_romload;
    dut->reset = 1;
    dut->st_req = 0;
    dut->ioctl_download = 0;
    dut->ioctl_wr = 0;
    dut->ldr_start = 0;
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

    // rom index 1, byte by byte, the way hps_io delivers it
    dut->ioctl_download = 1;
    dut->ioctl_index = 1;
    for (size_t i = 0; i < blob.size(); i++) {
        dut->ioctl_addr = uint32_t(i);
        dut->ioctl_dout = blob[i];
        dut->ioctl_wr = 1;
        tick();
        dut->ioctl_wr = 0;
        tick();
    }
    dut->ioctl_download = 0;
    tick();

    long bad = 0;
    if (!dut->cfg_valid) { printf("cfg: not valid after the blob%c", 10); bad++; }
    if (dut->cfg_gameprg_base != PRG_BASE) {
        printf("cfg: gameprg base %08x, want %08x%c", dut->cfg_gameprg_base, PRG_BASE, 10); bad++;
    }
    if (dut->cfg_bios_base != BIOS_BASE) {
        printf("cfg: bios base %08x, want %08x%c", dut->cfg_bios_base, BIOS_BASE, 10); bad++;
    }
    if (dut->cfg_scrtile_base != SCR_BASE || dut->cfg_scrtile_size != SCR_SIZE) {
        printf("cfg: scrtile %08x/%08x, want %08x/%08x%c", dut->cfg_scrtile_base,
               dut->cfg_scrtile_size, SCR_BASE, SCR_SIZE, 10);
        bad++;
    }

    // the copy
    dut->ldr_start = 1;
    tick();
    dut->ldr_start = 0;
    long guard = 0;
    while (!dut->ldr_done && ++guard < 40000000) tick();
    if (guard >= 40000000) { printf("copy never finished%c", 10); return 1; }
    if (dut->ldr_active) { printf("copy still active at done%c", 10); bad++; }
    printf("copy: %ld cycles for %u bytes (%.1f a byte)%c", guard, BIOS_SIZE,
           double(guard) / BIOS_SIZE, 10);
    for (int i = 0; i < 64; i++) tick();

    // read it back the way the CPU does
    auto read = [&](uint32_t a, int beats) {
        dut->st_addr = a;
        dut->st_beats = beats;
        dut->st_we = 0;
        dut->st_req = 1;
        tick();
        dut->st_req = 0;
        std::vector<uint64_t> got;
        long g = 0;
        while (++g < 20000) {
            tick();
            if (dut->st_rvalid) got.push_back(dut->st_rdata);
            if (int(got.size()) == beats) break;
        }
        return got;
    };

    long checked = 0;
    auto check = [&](const char *what, uint32_t cpu, uint32_t ddr, int beats) {
        auto got = read(cpu, beats);
        if (int(got.size()) != beats) {
            printf("%s at %08x: %d beats, expected %d%c", what, cpu, int(got.size()), beats, 10);
            bad++;
            return;
        }
        for (int b = 0; b < beats; b++) {
            uint64_t want = 0;
            for (int i = 7; i >= 0; i--) want = (want << 8) | pattern(ddr + 8 * b + i);
            checked++;
            if (got[b] != want) {
                if (bad < 8)
                    printf("%s at %08x beat %d: got %016llx want %016llx%c", what, cpu, b,
                           (unsigned long long)got[b], (unsigned long long)want, 10);
                bad++;
            }
        }
    };

    for (uint32_t off = 0; off < BIOS_SIZE; off += 32)
        check("bios", BIOS_CPU + off, BIOS_BASE + off, 4);

    // the granule past the region must still be the erased SDRAM, not the next DDR3 bytes
    {
        auto got = read(BIOS_CPU + BIOS_SIZE, 1);
        uint64_t next = 0;
        for (int i = 7; i >= 0; i--) next = (next << 8) | pattern(BIOS_BASE + BIOS_SIZE + i);
        if (!got.empty() && got[0] == next) {
            printf("the copy ran past the region: %08x holds DDR3's next granule%c",
                   BIOS_CPU + BIOS_SIZE, 10);
            bad++;
        }
    }

    printf("romload: %ld of %ld beats differ%c", bad, checked, 10);
    delete dut;
    return bad ? 1 : 0;
}
