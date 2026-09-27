// SPDX-License-Identifier: GPL-3.0-or-later
//
// The whole 2D video block against the model's finished frame: four tilemap engines, the sprite
// engine, the line buffers and the mixer, with nothing from the model in between.
//
//     python scripts/render_model.py sams64 attract --dump
//     python scripts/rom_regions.py sams64 scrtile
//     python scripts/rom_regions.py sams64 sprtile
//     scripts/run_verilator.sh video_tb +cap=debug/sams64-attract \
//         +srom=debug/rom/sams64-scrtile.bin +prom=debug/rom/sams64-sprtile.bin
//
// The two tile ROMs go through rtl/memory/hng64_ddram.sv and a model of MiSTer's DDRAM port:
// +romlat sets how long a read takes, +ddrbusy how often the controller refuses one (a percentage),
// so the transport's arbitration and its reply routing are exercised, not assumed. Tile VRAM, the
// sprite list and the palette answer the cycle after the address, as SDRAM and M10K will.

#include "Vtb_video.h"
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

std::vector<uint8_t> slurp_opt(const std::string &path, size_t bytes) {
    FILE *f = fopen(path.c_str(), "rb");
    if (!f) return std::vector<uint8_t>(bytes, 0);
    fclose(f);
    return slurp(path);
}

uint32_t be32(const std::vector<uint8_t> &v, size_t byte) {
    if (byte + 4 > v.size()) return 0;
    return (uint32_t(v[byte]) << 24) | (uint32_t(v[byte + 1]) << 16) |
           (uint32_t(v[byte + 2]) << 8) | uint32_t(v[byte + 3]);
}

uint64_t be64(const std::vector<uint8_t> &v, size_t byte) {
    uint64_t d = 0;
    // byte k of the granule in bits 8k+7:8k, as MiSTer's DDRAM port delivers it
    for (int i = 7; i >= 0; i--) d = (d << 8) | (byte + i < v.size() ? v[byte + i] : 0);
    return d;
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
    const std::string sromf = arg("srom", "debug/rom/sams64-scrtile.bin");
    const std::string promf = arg("prom", "debug/rom/sams64-sprtile.bin");

    auto vram = slurp(cap + "/videoram.bin");
    auto vregs = slurp(cap + "/videoregs.bin");
    auto tcram = slurp(cap + "/tcram.bin");
    auto pal = slurp(cap + "/palette.bin");
    auto sram = slurp(cap + "/spriteram.bin");
    auto sregs = slurp(cap + "/spriteregs.bin");
    auto srom = slurp(sromf);
    auto prom = slurp(promf);
    auto want = slurp(cap + "/model_rgb.bin");
    auto fbctrl = slurp_opt(cap + "/reg_fbctrl.bin", 48);

    auto *dut = new Vtb_video;
    dut->reset = 1;
    dut->frame_start = 0;
    dut->line_start = 0;
    dut->vreg_we = 0;
    dut->tcram_we = 0;
    dut->spriteregs0 = be32(sregs, 0);
    dut->spriteregs1 = be32(sregs, 4);
    dut->bg_rgb = (fbctrl[0] & 1) ? (be32(pal, 0) & 0xffffff) : 0;
    // the tile ROM is stored as the ROMs load it; the core undoes MAME's reorder by address
    dut->scr_half = uint32_t(srom.size() / 2);

    // Every port takes a request a cycle and answers in order after a fixed latency: the SDRAM
    // side (tile VRAM) and the DDR3 side (both tile ROMs). +vramlat / +romlat set how long.
    const long ROM_LAT = atol(arg("romlat", "8").c_str());
    const long VRAM_LAT = atol(arg("vramlat", "4").c_str());
    const int  DDR_BUSY = atoi(arg("ddrbusy", "20").c_str());   // % of cycles the port refuses
    std::deque<std::pair<long, uint64_t>> ddr_q;
    long cyc = 0;
    uint32_t lfsr = 0xACE1u;
    int pal_q[5] = {0, 0, 0, 0, 0};

    auto tick = [&]() {
        // Registered reads. The address ports still hold the value they settled to last cycle,
        // so answering from them here presents the word one cycle after the address, which is
        // what the engines and the mixer expect (and what sim/tilemap_tb does).
        cyc++;
        dut->sram_data = be32(sram, size_t(dut->sram_addr) * 4);
        // the palette needs a full cycle of delay: serve the address this port held LAST cycle
        dut->pal_d0 = be32(pal, size_t(pal_q[0]) * 4);
        dut->pal_d1 = be32(pal, size_t(pal_q[1]) * 4);
        dut->pal_d2 = be32(pal, size_t(pal_q[2]) * 4);
        dut->pal_d3 = be32(pal, size_t(pal_q[3]) * 4);
        dut->pal_d4 = be32(pal, size_t(pal_q[4]) * 4);
        pal_q[0] = dut->pal_a0;
        pal_q[1] = dut->pal_a1;
        pal_q[2] = dut->pal_a2;
        pal_q[3] = dut->pal_a3;
        pal_q[4] = dut->pal_a4;

        // MiSTer's DDRAM port: a read is taken on any cycle RD is high and BUSY is not, and the
        // beats come back in order on DOUT_READY. The windows are the ones docs/MEMORY.md gives.
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u);
        dut->DDRAM_BUSY = (int(lfsr % 100) < DDR_BUSY);
        // DDRAM_RD is combinational from BUSY, so settle it before deciding what was taken
        dut->eval();
        if (dut->DDRAM_RD && !dut->DDRAM_BUSY) {
            uint64_t byte = uint64_t(dut->DDRAM_ADDR & 0x1ffffff) << 3;   // drop the 0x3 window tag
            uint64_t d;
            if (byte >= 0x5000000)      d = be64(prom, size_t(byte - 0x5000000));
            else if (byte >= 0x1000000) d = be64(srom, size_t(byte - 0x1000000));
            else                        d = 0;
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
    for (int i = 0; i < 64; i++) tick();        // let the chip finish initialising

    // Fill tile VRAM through the download port, the way the loader will: the region image byte
    // for byte, even byte in the low lane. Reading it back correctly through the video path is
    // what proves the byte order, rather than an argument about it.
    {
        const uint32_t VRAM_WORD_BASE = 0x1500000 >> 1;   // docs/MEMORY.md, in 16-bit words
        for (size_t i = 0; i + 1 < vram.size(); i += 2) {
            dut->d_addr = VRAM_WORD_BASE + uint32_t(i >> 1);
            dut->d_din = uint16_t(vram[i]) | (uint16_t(vram[i + 1]) << 8);
            dut->d_we = 1;
            tick();
            dut->d_we = 0;
            while (!dut->d_ready) tick();
        }
        printf("tile VRAM loaded: %zu bytes%c", vram.size(), 10);
    }
    tick();

    for (int i = 0; i < 14; i++) {
        dut->reg_a = i;
        dut->reg_w = be32(vregs, i * 4);
        dut->vreg_we = 1;
        tick();
    }
    dut->vreg_we = 0;
    for (int i = 0; i < 24; i++) {
        dut->reg_a = i;
        dut->reg_w = be32(tcram, i * 4);
        dut->tcram_we = 1;
        tick();
    }
    dut->tcram_we = 0;

    // vblank: the sprite list is snapshotted here, once
    dut->frame_start = 1;
    tick();
    dut->frame_start = 0;
    long guard = 0;
    while (dut->busy && ++guard < 5000000) tick();

    long bad = 0, checked = 0, total = 0, worst = 0;
    int first_bad_line = -1, first_bad_x = -1;
    std::vector<uint32_t> got(WIDTH);
    FILE *dump = fopen((cap + "/rtl_video_rgb.bin").c_str(), "wb");
    // what each engine put in its line buffer, for comparison with the model's per-layer dumps
    std::vector<std::vector<uint16_t>> eng(5, std::vector<uint16_t>(WIDTH));
    FILE *edump[5];
    for (int e = 0; e < 5; e++) {
        char nm[256];
        snprintf(nm, sizeof nm, "%s/rtl_eng%d.bin", cap.c_str(), e);
        edump[e] = fopen(nm, "wb");
    }

    // the block renders a line ahead: the pixels that come out while line y is being
    // rendered are line y-1's, so there is one extra pass to flush the last line
    for (int y = 0; y <= HEIGHT; y++) {
        std::fill(got.begin(), got.end(), 0xFFFFFFFF);
        dut->line = (y < HEIGHT) ? y : HEIGHT - 1;
        dut->line_start = 1;
        tick();
        dut->line_start = 0;
        guard = 0;
        for (int e = 0; e < 5; e++) std::fill(eng[e].begin(), eng[e].end(), 0);
        do {
            tick();
            if (dut->px_we && dut->px_x < WIDTH) got[dut->px_x] = dut->px_rgb;
            const int exs[5] = {dut->dbg_x0, dut->dbg_x1, dut->dbg_x2, dut->dbg_x3, dut->dbg_x4};
            const uint16_t eps[5] = {dut->dbg_p0, dut->dbg_p1, dut->dbg_p2,
                                     dut->dbg_p3, dut->dbg_p4};
            for (int e = 0; e < 5; e++)
                if (((dut->dbg_we >> e) & 1) && exs[e] < WIDTH) eng[e][exs[e]] = eps[e];
        } while (dut->busy && ++guard < 2000000);
        if (y < HEIGHT)
            for (int e = 0; e < 5; e++)
                if (edump[e]) fwrite(eng[e].data(), 2, WIDTH, edump[e]);
        if (guard >= 2000000) { printf("LINE %d never finished%c", y, 10); return 1; }
        total += guard;
        if (guard > worst) worst = guard;
        if (y == 0) continue;               // nothing came out yet

        for (int x = 0; x < WIDTH; x++) {
            size_t o = (size_t(y - 1) * WIDTH + x) * 3;
            uint32_t exp = (uint32_t(want[o]) << 16) | (uint32_t(want[o + 1]) << 8) | want[o + 2];
            if (dump) {
                uint8_t px[3] = {uint8_t(got[x] >> 16), uint8_t(got[x] >> 8), uint8_t(got[x])};
                fwrite(px, 1, 3, dump);
            }
            checked++;
            if (got[x] != exp) {
                if (first_bad_line < 0) { first_bad_line = y; first_bad_x = x; }
                bad++;
            }
        }
    }

    printf("cycles a line: %ld worst, %ld mean%c", worst, total / (HEIGHT + 1), 10);
    printf("video: %ld of %ld pixels differ from the model", bad, checked);
    if (bad) {
        size_t o = (size_t(first_bad_line) * WIDTH + first_bad_x) * 3;
        printf("; first at line %d x %d: model %02x%02x%02x", first_bad_line, first_bad_x,
               want[o], want[o + 1], want[o + 2]);
    }
    printf("%c", 10);
    if (dump) fclose(dump);
    for (int e = 0; e < 5; e++) if (edump[e]) fclose(edump[e]);
    delete dut;
    return bad ? 1 : 0;
}
