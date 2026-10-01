// SPDX-License-Identifier: GPL-3.0-or-later
//
// Drives hng64_raster (setup, rasteriser, pixel unit, texture cache, render buffer) with
// the triangles of a captured frame and compares the colour plane it writes to DDR3 with the
// fixed-point model's 3D buffer.
//
//     python scripts/render_3d_fx.py sams64 2500 --dump
//     scripts/run_verilator.sh raster_tb +cap=debug/sams64-f2500 +tex=debug/rom/sams64-textures0.bin
//         [+lat=60] [+busy=20] [+noblock=1]
//
// raster.txt holds, per triangle, a line "A" with the pixel unit's fields (Pixel.scala Attr), a
// line "V" with the vertices as the geometry gave them, a line "T" with the setup record (what the
// geometry engine emits: geo_engine.setup_record), and a line "S" per span drawn. A and T drive the RTL;
// the spans' pixel count is checked against the fragments. raster_color.bin is the model's 3D
// buffer after the same triangles.
//
// The DDR3 ports (texture reads, depth reads, writes) are served from one memory image laid out as
// the bench chooses: replies in order per client, +lat clocks after the request, +busy percent of
// requests and writes refused. The frame is rendered twice: over noise with the whole depth plane
// scrubbed (tag 1), then again into the other colour plane over the first frame's depth (tag 2),
// and each colour plane is compared with the model's 3D buffer.

#include "Vtb_raster.h"
#include "verilated.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

namespace {

constexpr int NP = 5;
constexpr int PW[NP] = {30, 34, 24, 32, 32};    // RasterConfig.paramBits
constexpr int NA = 12;                          // Attr's fields

uint64_t mask(int bits) { return bits >= 64 ? ~0ull : (1ull << bits) - 1; }

struct In {
    int64_t rec[22];                             // the setup record, EMIT's order
    int64_t a[NA];
};

std::string arg(const char *key, const char *def) {
    const char *v = Verilated::commandArgsPlusMatch(key);
    if (v && v[0]) {
        const char *eq = strchr(v, '=');
        if (eq) return std::string(eq + 1);
    }
    return def;
}

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

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string cap = arg("cap", "");
    const std::vector<uint8_t> tex = slurp(arg("tex", ""));
    const std::vector<uint8_t> ref = slurp(cap + "/raster_color.bin");
    const int lat = atoi(arg("lat", "60").c_str());
    const int busy_pct = atoi(arg("busy", "20").c_str());
    // DDR3 as the bench lays it out: textures0 as loaded, its blocked copy (TexCache.scala's layout:
    // row A >> 10, column A & 1023), the depth plane, two colour planes. All but the ROM start as
    // noise, as DDR3 does. The RTL's TexBlock makes the copy (+noblock=1: the bench makes it).
    constexpr uint32_t ROM = 0, TEX = 0x1000000, DEPTH = 0x2000000, COLOUR[2] = {0x2100000, 0x2180000};
    const bool noblock = atoi(arg("noblock", "0").c_str()) != 0;
    std::vector<uint8_t> mem(0x2200000);
    std::vector<uint8_t> blocked(0x1000000);
    for (size_t a = 0; a < tex.size() && a < 0x1000000; a++) {
        const size_t row = a >> 10, col = a & 1023;
        mem[ROM + a] = tex[a];
        blocked[((row >> 3) << 13) | ((col >> 2) << 5) | ((row & 7) << 2) | (col & 3)] = tex[a];
    }
    uint32_t noise = 0x9E3779B9u;
    for (size_t a = TEX; a < mem.size(); a++) {
        noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5;
        mem[a] = uint8_t(noise);
    }

    const std::string path = cap + "/raster.txt";
    FILE *f = fopen(path.c_str(), "r");
    if (!f) { fprintf(stderr, "cannot open %s%c", path.c_str(), 10); return 2; }
    std::vector<In> ins;
    int64_t attr[NA] = {};
    size_t span_pixels = 0;
    char line[1024];
    while (fgets(line, sizeof line, f)) {
        char *s = line + 1;
        if (line[0] == 'A') {
            for (auto &v : attr) v = strtoll(s, &s, 10);
        } else if (line[0] == 'T') {
            // xa ya xb yb xc yc neg, then (p0 dx dy) per channel
            In in;
            for (int k = 0; k < 7; k++) in.rec[k] = strtoll(s, &s, 10);
            for (int k = 0; k < NP; k++) {
                in.rec[7 + k] = strtoll(s, &s, 10);
                in.rec[12 + k] = strtoll(s, &s, 10);
                in.rec[17 + k] = strtoll(s, &s, 10);
            }
            memcpy(in.a, attr, sizeof attr);
            ins.push_back(in);
        } else if (line[0] == 'S') {
            strtol(s, &s, 10);
            const long x0 = strtol(s, &s, 10), x1 = strtol(s, &s, 10);
            span_pixels += size_t(x1 - x0 + 1);
        }
    }
    fclose(f);

    Vtb_raster *dut = new Vtb_raster;
    auto tick = [&]() {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    };
    dut->reset = 1;
    dut->tri_valid = 0;
    dut->start = 0;
    dut->finish = 0;
    for (int i = 0; i < 4; i++) tick();
    dut->reset = 0;
    dut->tex_base = TEX;
    dut->depth_base = DEPTH;
    dut->block_start = 0;
    dut->block_src = ROM;
    dut->block_groups = 0x1000000 >> 13;

    auto load = [&](const In &t) {
        for (int k = 0; k < 22; k++) dut->rec[k] = uint64_t(t.rec[k]);
        dut->a_flat = t.a[0]; dut->a_blend = t.a[1]; dut->a_tex4bpp = t.a[2]; dut->a_tex_index = t.a[3];
        dut->a_sub = t.a[4]; dut->a_hoff = t.a[5]; dut->a_voff = t.a[6]; dut->a_pal = t.a[7];
        dut->a_scroll_x = t.a[8]; dut->a_scroll_y = t.a[9]; dut->a_wrap_x = t.a[10]; dut->a_wrap_y = t.a[11];
    };
    auto rd64 = [&](uint32_t a) {
        uint64_t w = 0;
        for (int k = 0; k < 8; k++) w |= uint64_t(a + k < mem.size() ? mem[a + k] : 0) << (8 * k);
        return w;
    };

    // hng64_ddram's ports: each client's replies in order, +lat clocks on, the data as of the
    // read's issue (a later write is behind it in DDR3); +busy percent of requests refused
    std::deque<std::pair<uint64_t, uint64_t>> tex_q, depth_q;
    uint64_t tex_reads = 0, depth_reads = 0, writes = 0;
    uint32_t rnd = 0x1234u;
    auto refuse = [&]() {
        rnd = rnd * 1103515245u + 12345u;
        return int((rnd >> 16) % 100) < busy_pct;
    };

    bool pass_all = true;
    if (noblock) {
        std::copy(blocked.begin(), blocked.end(), mem.begin() + TEX);
    } else {
        // TexBlock: textures0 into its blocked copy, through the texture read port and the writer
        uint64_t cycles = 0, reads = 0, writes = 0;
        bool done = false;
        while (!done && cycles < 100000000ull) {
            dut->clk = 0;
            dut->block_start = cycles == 0;
            dut->tri_valid = 0;
            dut->tex_rd_ready = !refuse();
            dut->wr_ready = !refuse();
            dut->tex_data_valid = !tex_q.empty() && tex_q.front().first <= cycles;
            if (dut->tex_data_valid) { dut->tex_data = tex_q.front().second; tex_q.pop_front(); }
            dut->eval();
            if (dut->wr && dut->wr_ready) {
                for (int k = 0; k < 8; k++)
                    if ((dut->wr_be >> k) & 1) mem[dut->wr_addr + k] = uint8_t(dut->wr_data >> (8 * k));
                writes++;
            }
            if (dut->tex_rd && dut->tex_rd_ready) {
                tex_q.emplace_back(cycles + lat, rd64(dut->tex_rd_addr));
                reads++;
            }
            dut->clk = 1;
            dut->eval();
            cycles++;
            if (dut->block_done) done = true;
        }
        dut->block_start = 0;
        size_t bad = 0;
        for (size_t a = 0; a < blocked.size(); a++) bad += mem[TEX + a] != blocked[a];
        const bool ok = done && bad == 0;
        pass_all = pass_all && ok;
        printf("raster: texture blocking: %" PRIu64 " reads, %" PRIu64 " writes, %zu of %zu bytes differ, %" PRIu64
               " clocks: %s%c", reads, writes, bad, blocked.size(), cycles, ok ? "PASS" : "FAIL", 10);
        tick();
    }
    for (int frame = 0; frame < 2; frame++) {
        // frame 0: tag 1 over noise, the whole depth plane scrubbed; frame 1: tag 2, over frame 0
        dut->full = frame == 0;
        dut->tag = frame + 1;
        dut->scrub = frame;
        dut->colour_base = COLOUR[frame];
        size_t ti = 0;
        uint64_t cycles = 0;
        bool started = false, finished = false, done = false;
        while (!done && cycles < 400000000ull) {
            dut->clk = 0;
            dut->start = !started;
            dut->finish = started && !finished && ti == ins.size() && !dut->busy;
            if (ti < ins.size()) { load(ins[ti]); dut->tri_valid = 1; } else dut->tri_valid = 0;
            dut->tex_rd_ready = !refuse();
            dut->depth_rd_ready = !refuse();
            dut->wr_ready = !refuse();
            dut->tex_data_valid = !tex_q.empty() && tex_q.front().first <= cycles;
            if (dut->tex_data_valid) { dut->tex_data = tex_q.front().second; tex_q.pop_front(); }
            dut->depth_data_valid = !depth_q.empty() && depth_q.front().first <= cycles;
            if (dut->depth_data_valid) { dut->depth_data = depth_q.front().second; depth_q.pop_front(); }
            dut->eval();
            const bool tri_fire = dut->tri_valid && dut->tri_ready;
            if (dut->wr && dut->wr_ready) {
                for (int k = 0; k < 8; k++)
                    if ((dut->wr_be >> k) & 1) mem[dut->wr_addr + k] = uint8_t(dut->wr_data >> (8 * k));
                writes++;
            }
            if (dut->tex_rd && dut->tex_rd_ready) {
                tex_q.emplace_back(cycles + lat, rd64(dut->tex_rd_addr));
                tex_reads++;
            }
            if (dut->depth_rd && dut->depth_rd_ready) {
                depth_q.emplace_back(cycles + lat, rd64(dut->depth_rd_addr));
                depth_reads++;
            }
            if (dut->finish) finished = true;
            started = true;
            dut->clk = 1;
            dut->eval();
            cycles++;
            if (tri_fire) ti++;
            if (dut->done) done = true;
        }

        size_t bad = 0;
        for (int i = 0; i < 512 * 512; i++) {
            const uint16_t want = uint16_t(ref[2 * i] | (ref[2 * i + 1] << 8));
            const uint32_t a = COLOUR[frame] + 2 * i;
            const uint16_t got = uint16_t(mem[a] | (mem[a + 1] << 8));
            if (got != want && bad++ < 40)
                printf("raster: frame %d (%d,%d) %04x, the model %04x%c", frame, i % 512, i / 512, got, want, 10);
        }
        const bool pass = done && bad == 0 && ti == ins.size();
        pass_all = pass_all && pass;
        printf("raster: frame %d (tag %d%s): %zu triangles, %zu of 262144 buffer pixels differ, %" PRIu64
               " texture reads, %" PRIu64 " depth reads, %" PRIu64 " writes, %" PRIu64
               " clocks (latency %d, %d%% refused): %s%c", frame, frame + 1, frame ? "" : ", full scrub",
               ti, bad, tex_reads, depth_reads, writes, cycles, lat, busy_pct, pass ? "PASS" : "FAIL", 10);
        tex_reads = depth_reads = writes = 0;
        tick();                              // the render buffer back to idle before the next start
    }
    printf("raster: %zu fragments in the model's spans: %s%c", span_pixels, pass_all ? "PASS" : "FAIL", 10);
    delete dut;
    return pass_all ? 0 : 1;
}
