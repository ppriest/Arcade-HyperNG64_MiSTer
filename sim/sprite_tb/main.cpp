// SPDX-License-Identifier: GPL-3.0-or-later
//
// Drives hng64_sprite against the software model, line by line.
//
//     python scripts/render_model.py sams64 attract --dump
//     python scripts/rom_regions.py sams64 sprtile
//     scripts/run_verilator.sh sprite_tb +cap=debug/sams64-attract \
//                              +rom=debug/rom/sams64-sprtile.bin
//
// The sprite tile ROM is NOT reordered: MAME's init_reorder_gfx touches "scrtile" only.

#include "Vtb_sprite.h"
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
    if (!f) { fprintf(stderr, "cannot open %s%c", path.c_str(), 10); exit(2); }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> out(n);
    if (fread(out.data(), 1, n, f) != size_t(n)) { fprintf(stderr, "short read%c", 10); exit(2); }
    fclose(f);
    return out;
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

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string cap = arg("cap", "debug/sams64-attract");
    const std::string rompath = arg("rom", "debug/rom/sams64-sprtile.bin");
    const int dbg_line = arg("tline", "").empty() ? -1 : atoi(arg("tline", "0").c_str());

    auto ram = slurp(cap + "/spriteram.bin");
    // +only=N keeps one sprite: the others get zoom 0, which both MAME and the model skip
    if (!arg("only", "").empty()) {
        int keep = atoi(arg("only", "0").c_str());
        for (int i = 0; i < 1536; i++)
            if (i != keep) { ram[i * 32 + 4] = 0; ram[i * 32 + 5] = 0;
                             ram[i * 32 + 6] = 0; ram[i * 32 + 7] = 0; }
    }
    auto regs = slurp(cap + "/spriteregs.bin");
    auto rom = slurp(rompath);
    auto want = slurp(cap + "/sprites.bin");
    FILE *dump = fopen((cap + "/rtl_sprites.bin").c_str(), "wb");

    auto *dut = new Vtb_sprite;
    dut->spriteregs0 = be32(regs, 0);
    dut->spriteregs1 = be32(regs, 4);
    dut->reset = 1;
    dut->frame_start = 0;
    dut->line_start = 0;

    // the ROM takes a request a cycle and answers in order after +romlat cycles, as DDR3 will
    const long ROM_LAT = atol(arg("romlat", "8").c_str());
    std::deque<std::pair<long, uint64_t>> rom_q;
    std::vector<uint16_t> got(WIDTH);
    long bad = 0, checked = 0, cyc = 0, worst = 0, total = 0, nrom = 0, nvram = 0, romworst = 0, romprev = 0;
    int first_bad_line = -1, first_bad_x = -1;
    int cur_line = -1;

    auto tick = [&]() {
        cyc++;
        if (dut->ram_rd) {
            nvram++;
            size_t byte = size_t(dut->ram_addr) * 4;
            dut->ram_data = byte + 4 <= ram.size() ? be32(ram, byte) : 0;
        }
        if (dut->rom_rd) {
            nrom++;
            size_t byte = size_t(dut->rom_addr) & ~size_t(7);
            uint64_t d = 0;
            for (int i = 0; i < 8; i++)
                d = (d << 8) | (byte + i < rom.size() ? rom[byte + i] : 0);
            rom_q.emplace_back(cyc + ROM_LAT, d);
        }
        dut->rom_valid = 0;
        if (!rom_q.empty() && rom_q.front().first <= cyc) {
            dut->rom_data = rom_q.front().second;
            dut->rom_valid = 1;
            rom_q.pop_front();
        }
        if (dbg_line >= 0 && cur_line == dbg_line) {
            if (dut->ram_rd) printf("c%-7ld ram  %04x%c", cyc, dut->ram_addr, 10);
            if (dut->rom_rd) printf("c%-7ld rom %07x xdrw=%d xpos=%d w=%d%c", cyc,
                                     dut->rom_addr, dut->dbg_xdrw, (int16_t)(dut->dbg_xpos << 4) >> 4,
                                     dut->dbg_dstwidth, 10);
        }
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
        if (dbg_line >= 0 && cur_line == dbg_line && dut->px_we)
            printf("c%-7ld px x=%3d pix=%04x%c", cyc, dut->px_x, dut->px_pix, 10);
        if (dut->px_we && dut->px_x < WIDTH) got[dut->px_x] = dut->px_pix;
    };

    for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;
    tick();

    // pre-pass over the list, once
    dut->frame_start = 1; tick();
    dut->frame_start = 0;
    long guard = 0;
    while (dut->busy && ++guard < 5000000) tick();
    printf("pre-pass took %ld cycles, kept %d candidates%c", guard, dut->dbg_ncand, 10);

    for (int y = 0; y < HEIGHT; y++) {
        cur_line = y;
        std::fill(got.begin(), got.end(), 0);
        dut->line = y;
        dut->line_start = 1; tick();
        dut->line_start = 0;
        guard = 0;
        while (dut->busy && ++guard < 2000000) tick();
        if (guard > worst) worst = guard;
        if (nrom - romprev > romworst) romworst = nrom - romprev;
        romprev = nrom;
        total += guard;
        if (guard >= 2000000) { printf("LINE %d never finished%c", y, 10); return 1; }
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
    printf("rom reads a line: %ld worst, %ld mean; list reads %ld mean%c",
           romworst, nrom / HEIGHT, nvram / HEIGHT, 10);
    printf("sprites: %ld of %ld pixels differ from the model", bad, checked);
    if (bad) {
        const uint16_t *exp = reinterpret_cast<const uint16_t *>(want.data()) +
                              size_t(first_bad_line) * WIDTH;
        printf("; first at line %d x %d: model %04x", first_bad_line, first_bad_x,
               exp[first_bad_x]);
    }
    printf("%c", 10);
    if (dump) fclose(dump);
    delete dut;
    return bad ? 1 : 0;
}
