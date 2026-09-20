// SPDX-License-Identifier: GPL-3.0-or-later
//
// Drives hng64_tilemap against the software model, line by line.
//
//     python scripts/mame_capture.py sams64 --frame 1200 --name attract
//     python scripts/render_model.py sams64 attract --dump
//     python scripts/rom_regions.py sams64 scrtile
//     scripts/run_verilator.sh tilemap_tb +cap=debug/sams64-attract +tm=3 \
//                              +rom=debug/rom/sams64-scrtile.bin
//
// Both ports take a request a cycle and answer in order after a fixed latency (+vramlat,
// +romlat), as the SDRAM and DDR3 sides will, so the engine's pipelining is exercised
// rather than assumed away. The tile ROM image is the region as the ROMs load it, and the
// address is translated here the way hng64_video does, so the bench and the block see the
// same bytes at the same addresses.

#include "Vtb_tilemap.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr int WIDTH = 512;
constexpr int HEIGHT = 448;

std::vector<uint8_t> slurp(const std::string &path) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) {
        fprintf(stderr, "cannot open %s\n", path.c_str());
        exit(2);
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> out(n);
    if (fread(out.data(), 1, n, f) != size_t(n)) {
        fprintf(stderr, "short read on %s\n", path.c_str());
        exit(2);
    }
    fclose(f);
    return out;
}

// hng64_video's undo of MAME's init_reorder_gfx: a decoded 32-byte chunk is even for the
// upper half of the raw region and odd for the lower.
size_t scr_raw(size_t dec, size_t half) {
    return ((dec >> 6) << 5) + (dec & 31) + ((dec & 32) ? 0 : half);
}

uint32_t be32(const std::vector<uint8_t> &v, size_t byte) {
    return (uint32_t(v[byte]) << 24) | (uint32_t(v[byte + 1]) << 16) |
           (uint32_t(v[byte + 2]) << 8) | uint32_t(v[byte + 3]);
}

std::string arg(const char *key, const char *def) {
    const char *v = Verilated::commandArgsPlusMatch(key);
    if (v && v[0]) {
        const char *eq = strchr(v, '=');
        if (eq) return std::string(eq + 1);
    }
    return def;
}

}  // namespace

// Verilator's runtime still references this when a model has no --timing.
double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string cap = arg("cap", "debug/sams64-attract");
    const int tm = atoi(arg("tm", "3").c_str());
    const std::string rompath = arg("rom", "debug/rom/sams64-scrtile.bin");

    auto vram = slurp(cap + "/videoram.bin");
    auto vregs = slurp(cap + "/videoregs.bin");
    auto rom = slurp(rompath);
    auto want = slurp(cap + "/layer" + std::to_string(tm) + ".bin");   // u16 little-endian
    FILE *dump = fopen((cap + "/rtl_layer" + std::to_string(tm) + ".bin").c_str(), "wb");

    const uint32_t vr0 = be32(vregs, 0x00 * 4);
    const uint32_t vr1 = be32(vregs, 0x01 * 4);
    const uint32_t vr2 = be32(vregs, (0x02 + (tm >> 1)) * 4);
    const uint32_t vr4 = be32(vregs, (0x04 + (tm >> 1)) * 4);
    const uint16_t tileregs = (tm & 1) ? (vr2 & 0xffff) : (vr2 >> 16);
    const uint16_t scrollbase = ((tm & 1) ? (vr4 & 0xffff) : (vr4 >> 16)) & 0x3fff;

    auto *dut = new Vtb_tilemap;
    dut->tm_index = tm;
    dut->tileregs = tileregs;
    dut->scrollbase = scrollbase;
    dut->videoreg0 = vr0;
    dut->videoreg1 = vr1;
    dut->anim_mask = be32(vregs, 0x0b * 4);
    dut->anim_bits = be32(vregs, 0x0c * 4);
    dut->reset = 1;
    dut->start = 0;

    const long ROM_LAT = atol(arg("romlat", "8").c_str());
    const long VRAM_LAT = atol(arg("vramlat", "4").c_str());
    std::deque<std::pair<long, uint64_t>> rom_q, vram_q;
    std::vector<uint16_t> got(WIDTH);
    long bad = 0, checked = 0, worst = 0, total = 0, nrom = 0, nvram = 0, romworst = 0, romprev = 0;
    int first_bad_line = -1, first_bad_x = -1;

    const int dbg_line = arg("tline", "").empty() ? -1 : atoi(arg("tline", "0").c_str());
    bool dbg = !arg("debug", "").empty();
    int cur_line = -1;
    long cyc = 0;
    auto tick = [&]() {
        cyc++;
        if (dut->vram_rd) {
            nvram++;
            size_t byte = size_t(dut->vram_addr) * 4;
            vram_q.emplace_back(cyc + VRAM_LAT, uint64_t(byte + 4 <= vram.size()
                                                         ? be32(vram, byte) : 0));
        }
        if (dut->rom_rd) {
            nrom++;
            size_t byte = scr_raw(size_t(dut->rom_addr) & ~size_t(7), rom.size() / 2);
            uint64_t d = 0;
            for (int i = 0; i < 8; i++)
                d = (d << 8) | (byte + i < rom.size() ? rom[byte + i] : 0);
            rom_q.emplace_back(cyc + ROM_LAT, d);
        }
        dut->vram_valid = 0;
        dut->rom_valid = 0;
        if (!vram_q.empty() && vram_q.front().first <= cyc) {
            dut->vram_data = uint32_t(vram_q.front().second);
            dut->vram_valid = 1;
            vram_q.pop_front();
        }
        if (!rom_q.empty() && rom_q.front().first <= cyc) {
            dut->rom_data = rom_q.front().second;
            dut->rom_valid = 1;
            rom_q.pop_front();
        }
        if (dbg && (dbg_line < 0 ? cyc < 400 : cur_line == dbg_line)) {
            if (dut->vram_rd) printf("c%-5ld vram_rd  %05x%c", cyc, dut->vram_addr, 10);
            if (dut->rom_rd)  printf("c%-5ld rom_rd   %07x%c", cyc, dut->rom_addr, 10);
        }
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
        if (dbg && (dbg_line < 0 ? cyc < 400 : cur_line == dbg_line) && dut->px_we && dut->px_x < 24)
            printf("c%-5ld px x=%3d pix=%04x%c", cyc, dut->px_x, dut->px_pix, 10);
        if (dut->px_we && dut->px_x < WIDTH) got[dut->px_x] = dut->px_pix;
    };

    for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    if (dbg_line >= 0) dbg = true;
    for (int y = 0; y < HEIGHT; y++) {
        cur_line = y;
        std::fill(got.begin(), got.end(), 0);
        dut->line = y;
        dut->start = 1;
        tick();
        dut->start = 0;
        long guard = 0;
        while (dut->busy && ++guard < 200000) tick();
        if (guard > worst) worst = guard;
        if (nrom - romprev > romworst) romworst = nrom - romprev;
        romprev = nrom;
        total += guard;
        if (guard >= 200000) {
            printf("LINE %d: engine never finished\n", y);
            return 1;
        }
        if (dump) fwrite(got.data(), 2, WIDTH, dump);
        const uint16_t *exp = reinterpret_cast<const uint16_t *>(want.data()) + size_t(y) * WIDTH;
        for (int x = 0; x < WIDTH; x++) {
            checked++;
            if (got[x] != exp[x]) {
                if (first_bad_line < 0) { first_bad_line = y; first_bad_x = x; }
                bad++;
            }
        }
    }

    printf("cycles a line: %ld worst, %ld mean%c", worst, total / HEIGHT, 10);
    printf("rom reads a line: %ld worst, %ld mean; vram %ld mean%c",
           romworst, nrom / HEIGHT, nvram / HEIGHT, 10);
    printf("tilemap %d: %ld of %ld pixels differ from the model", tm, bad, checked);
    if (bad) {
        const uint16_t *exp = reinterpret_cast<const uint16_t *>(want.data()) +
                              size_t(first_bad_line) * WIDTH;
        printf("; first at line %d x %d: model %04x", first_bad_line, first_bad_x,
               exp[first_bad_x]);
    }
    printf("\n");
    if (dump) fclose(dump);
    delete dut;
    return bad ? 1 : 0;
}
