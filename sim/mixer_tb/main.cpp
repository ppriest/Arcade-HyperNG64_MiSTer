// SPDX-License-Identifier: GPL-3.0-or-later
//
// Drives hng64_mixer against the model's finished frame, line by line.
//
//     python scripts/render_model.py sams64 attract --dump
//     scripts/run_verilator.sh mixer_tb +cap=debug/sams64-attract
//
// The five line buffers come from the model's per-layer dumps, so this checks the mixer alone:
// the layer engines are checked by sim/tilemap_tb and sim/sprite_tb.

#include "Vtb_mixer.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
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

std::vector<uint8_t> slurp_opt(const std::string &path, size_t bytes) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) return std::vector<uint8_t>(bytes, 0);
    fclose(f);
    return slurp(path);
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

    auto vregs = slurp(cap + "/videoregs.bin");
    auto tcram = slurp(cap + "/tcram.bin");
    auto pal = slurp(cap + "/palette.bin");
    auto spr = slurp(cap + "/sprites.bin");
    auto want = slurp(cap + "/model_rgb.bin");

    std::vector<std::vector<uint8_t>> layer(4);
    for (int tm = 0; tm < 4; tm++)
        layer[tm] = slurp_opt(cap + "/layer" + std::to_string(tm) + ".bin", HEIGHT * WIDTH * 2);

    uint16_t tileregs[4];
    for (int tm = 0; tm < 4; tm++) {
        uint32_t w = be32(vregs, (0x02 + (tm >> 1)) * 4);
        tileregs[tm] = (tm & 1) ? (w & 0xffff) : (w >> 16);
    }

    // the background is palette entry 0 when fbcontrol bit 0 is set, black otherwise
    auto fbctrl = slurp_opt(cap + "/reg_fbctrl.bin", 48);
    uint32_t bg = (fbctrl[0] & 1) ? (be32(pal, 0) & 0xffffff) : 0;

    auto *dut = new Vtb_mixer;
    dut->bg_rgb = bg;
    dut->tileregs0 = tileregs[0];
    dut->tileregs1 = tileregs[1];
    dut->tileregs2 = tileregs[2];
    dut->tileregs3 = tileregs[3];
    dut->reset = 1;
    dut->start = 0;
    dut->rebuild = 0;
    dut->tcram_we = 0;

    auto tick = [&]() {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    };

    for (int i = 0; i < 4; i++) tick();
    dut->reset = 0;

    // tcram: 24 words, big-endian in the capture
    for (int i = 0; i < 24; i++) {
        dut->tcram_a = i;
        dut->tcram_w = (size_t(i) * 4 + 4 <= tcram.size()) ? be32(tcram, i * 4) : 0;
        dut->tcram_we = 1;
        tick();
    }
    dut->tcram_we = 0;

    // the modified palette is rebuilt at frame start, from the palette port
    {
        int pal_q = 0;
        dut->rebuild = 1;
        long guard = 0;
        do {
            dut->pal_d0 = be32(pal, size_t(pal_q) * 4);
            dut->eval();
            pal_q = dut->pal_a0;
            tick();
            dut->rebuild = 0;
        } while ((dut->busy || guard == 0) && ++guard < 100000);
        if (guard >= 100000) { printf("palette rebuild never finished%c", 10); return 1; }
        printf("palette rebuild: %ld clocks%c", guard, 10);
    }

    long bad = 0, checked = 0;
    FILE *dump = fopen((cap + "/rtl_rgb.bin").c_str(), "wb");
    int first_bad_line = -1, first_bad_x = -1;
    std::vector<uint32_t> got(WIDTH);

    for (int y = 0; y < HEIGHT; y++) {
        std::fill(got.begin(), got.end(), 0xFFFFFFFF);
        // both RAMs answer a cycle after their address: lb_q and pal_q hold the addresses from the
        // previous cycle (the mixer's palette address comes from its registers, so it has to be
        // taken after eval(), as the line-buffer address is)
        int lb_q = 0, pal_q = 0;
        auto serve = [&]() {
            size_t o = (size_t(y) * WIDTH + lb_q) * 2;
            auto rd = [&](const std::vector<uint8_t> &v) -> uint16_t {
                return uint16_t(v[o]) | (uint16_t(v[o + 1]) << 8);
            };
            dut->tm0_pix = rd(layer[0]);
            dut->tm1_pix = rd(layer[1]);
            dut->tm2_pix = rd(layer[2]);
            dut->tm3_pix = rd(layer[3]);
            dut->spr_pix = rd(spr);
            dut->pal_d0 = be32(pal, size_t(pal_q) * 4);
            dut->eval();
            lb_q = dut->lb_x;
            pal_q = dut->pal_a0;
        };

        dut->start = 1;
        serve();
        tick();
        dut->start = 0;
        long guard = 0;
        do {
            serve();
            tick();
            if (dut->px_we && dut->px_x < WIDTH) got[dut->px_x] = dut->px_rgb;
        } while (dut->busy && ++guard < 10000);
        if (guard >= 10000) { printf("LINE %d never finished%c", y, 10); return 1; }

        for (int x = 0; x < WIDTH; x++) {
            size_t o = (size_t(y) * WIDTH + x) * 3;
            if (dump) { uint8_t px[3] = {uint8_t(got[x] >> 16), uint8_t(got[x] >> 8), uint8_t(got[x])};
                        fwrite(px, 1, 3, dump); }
            uint32_t exp = (uint32_t(want[o]) << 16) | (uint32_t(want[o + 1]) << 8) | want[o + 2];
            checked++;
            if (got[x] != exp) {
                if (first_bad_line < 0) { first_bad_line = y; first_bad_x = x; }
                bad++;
            }
        }
    }

    printf("mixer: %ld of %ld pixels differ from the model", bad, checked);
    if (bad) {
        size_t o = (size_t(first_bad_line) * WIDTH + first_bad_x) * 3;
        printf("; first at line %d x %d: model %02x%02x%02x", first_bad_line, first_bad_x,
               want[o], want[o + 1], want[o + 2]);
    }
    printf("%c", 10);
    if (dump) fclose(dump);
    delete dut;
    return bad ? 1 : 0;
}
