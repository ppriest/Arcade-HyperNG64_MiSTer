// SPDX-License-Identifier: GPL-3.0-or-later
//
// hng64_3d as the core has it: the display list and uploads in through the CPU side (clk1x), the
// geometry engine and rasteriser behind the queue, every DDR3 access through hng64_ddram's one
// DDRAM port (clk2x). The last two frames of a capture are played in and the colour plane the
// display is given at the end is compared with the fixed-point model's 3D buffer.
//
//     python scripts/geo_engine.py sams64 2500 --dump      # debug/sams64-f2500/geo_events.txt
//     python scripts/render_3d_fx.py sams64 2500 --dump    # raster_color.bin
//     scripts/run_verilator.sh g3d_tb +cap=debug/sams64-f2500 +tex=debug/rom/sams64-textures0.bin
//         +verts=debug/rom/sams64-verts.bin [+lat=60] [+busy=20] [+back=2]
//
// From geo_events.txt: the events from the +back'th clearing vblank from the end on, then one more clearing
// vblank to finish the capture's frame. The start-up (texture blocking, the engine's init, the
// first frame's full depth scrub) runs first, as after a reset. The DDRAM port is busy on +busy
// percent of clocks and answers reads in order +lat clocks later. The display takes an offered
// plane 2,000 clocks after it is offered.

#include "Vtb_g3d.h"
#include "verilated.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
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

struct Event {
    char kind;
    std::vector<uint16_t> dl;
    std::vector<uint8_t> wrap;
};

constexpr uint32_t VERTS = 0x1000000;
constexpr uint32_t COLOUR[2] = {0xF100000, 0xF180000};

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string cap = arg("cap", "");
    const std::vector<uint8_t> tex = slurp(arg("tex", ""));
    const std::vector<uint8_t> verts = slurp(arg("verts", ""));
    const std::vector<uint8_t> ref = slurp(cap + "/raster_color.bin");
    const int lat = atoi(arg("lat", "60").c_str());
    const int busy_pct = atoi(arg("busy", "20").c_str());
    const int back = atoi(arg("back", "2").c_str());

    FILE *f = fopen((cap + "/geo_events.txt").c_str(), "r");
    if (!f) { fprintf(stderr, "no geo_events.txt in %s%c", cap.c_str(), 10); return 2; }
    std::vector<Event> all;
    int samsho = 0;
    long vlen = 0;
    static char buf[65536];
    while (fgets(buf, sizeof buf, f)) {
        char *s = buf + 1;
        if (buf[0] == 'I') {
            samsho = int(strtol(s, &s, 10));
            vlen = strtol(s, &s, 10);
        } else if (buf[0] == 'C') {
            all.push_back(Event{'C', {}, {}});
        } else if (buf[0] == 'U') {
            Event e{'U', {}, {}};
            for (int k = 0; k < 256; k++) e.dl.push_back(uint16_t(strtoul(s, &s, 16)));
            for (int k = 0; k < 32; k++) e.wrap.push_back(uint8_t(strtoul(s, &s, 16)));
            all.push_back(e);
        }
    }
    fclose(f);
    size_t first = 0;
    int seen = 0;
    for (size_t i = all.size(); i-- > 0;)
        if (all[i].kind == 'C' && ++seen == back) { first = i; break; }
    if (seen < back) { printf("g3d: fewer than %d clearing vblanks in the events%c", back, 10); return 2; }
    std::vector<Event> evs(all.begin() + long(first), all.end());
    evs.push_back(Event{'C', {}, {}});
    size_t uploads = 0, clears = 0;
    for (const Event &e : evs) (e.kind == 'U' ? uploads : clears)++;

    // DDR3: textures0 at 0, the vertex ROM at 16 MB, everything else noise
    std::vector<uint8_t> mem(0x10000000);
    uint32_t rnd = 0x2468ACEu;
    for (size_t a = 0; a < mem.size(); a += 4) {
        rnd = rnd * 1103515245u + 12345u;
        memcpy(&mem[a], &rnd, 4);
    }
    std::copy(tex.begin(), tex.end(), mem.begin());
    std::copy(verts.begin(), verts.end(), mem.begin() + VERTS);

    Vtb_g3d *dut = new Vtb_g3d;
    dut->samsho = samsho;
    dut->vert_base = VERTS;
    dut->vert_len = uint32_t(vlen);
    dut->tex_rom = 0;
    dut->tex_groups = uint32_t(tex.size() >> 13);
    dut->vblank = 0;
    dut->clear_en = 1;
    dut->dl_we = 0;
    dut->dl_up = 0;
    dut->shown_valid = 0;
    dut->shown_plane = 0;
    dut->DDRAM_BUSY = 0;
    dut->DDRAM_DOUT_READY = 0;

    std::deque<std::pair<uint64_t, uint64_t>> rq;
    uint64_t cycles = 0, reads = 0, writes = 0;
    int show_delay = -1;
    // clk2x 125 MHz and clk3d 100 MHz, unrelated as on the board: times in ns, clk2x toggling every
    // 4 and clk3d every 5; clk3d's edges between clk2x's are made in time order
    uint64_t tns = 0, t3 = 0;
    int clk3 = 0;
    auto run3 = [&](uint64_t until) {
        while (t3 <= until) {
            clk3 ^= 1;
            dut->clk3d = clk3;
            dut->eval();
            t3 += 5;
        }
    };
    auto tick = [&](bool rst) {
        dut->reset = rst;
        run3(tns);
        rnd = rnd * 1103515245u + 12345u;
        dut->DDRAM_BUSY = int((rnd >> 16) % 100) < busy_pct;
        dut->DDRAM_DOUT_READY = !rq.empty() && rq.front().first <= cycles;
        if (dut->DDRAM_DOUT_READY) { dut->DDRAM_DOUT = rq.front().second; rq.pop_front(); }
        dut->clk2x = 0;
        dut->clk1x = (cycles & 1) ? 1 : 0;   // clk1x falls on odd clk2x edges, rises on even ones
        dut->eval();
        if (!rst && !dut->DDRAM_BUSY) {
            const uint64_t a = uint64_t(dut->DDRAM_ADDR & 0x1FFFFFF) << 3;
            if (dut->DDRAM_WE) {
                for (int k = 0; k < 8; k++)
                    if ((dut->DDRAM_BE >> k) & 1) mem[a + k] = uint8_t(dut->DDRAM_DIN >> (8 * k));
                writes++;
            } else if (dut->DDRAM_RD) {
                uint64_t w = 0;
                for (int k = 0; k < 8; k++) w |= uint64_t(mem[a + k]) << (8 * k);
                rq.emplace_back(cycles + lat, w);
                reads++;
            }
        }
        // the display: takes an offered plane a while later
        const bool differ = dut->show_valid != dut->shown_valid || dut->show_plane != dut->shown_plane;
        if (differ && show_delay < 0) show_delay = 2000;
        if (show_delay == 0) {
            dut->shown_valid = dut->show_valid;
            dut->shown_plane = dut->show_plane;
        }
        if (show_delay >= 0) show_delay--;
        run3(tns + 4);
        dut->clk2x = 1;
        dut->clk1x = (cycles & 1) ? 0 : 1;
        dut->eval();
        cycles++;
        tns += 8;
    };

    for (int i = 0; i < 8; i++) tick(true);

    // the CPU side, one step per clk1x clock (even clk2x cycles)
    size_t ei = 0, wi = 0;
    int vb = 0;
    int swaps = 0;
    int prev_sv = 0, prev_sp = 0;
    bool fed = false;
    const uint64_t limit = 400000000ull;
    uint64_t fed_at = 0;
    while (cycles < limit) {
        if ((cycles & 1) == 0) {
            dut->dl_we = 0;
            dut->dl_up = 0;
            if (ei < evs.size()) {
                const Event &e = evs[ei];
                if (e.kind == 'C') {
                    dut->vblank = vb < 4;
                    if (++vb == 8) { vb = 0; ei++; }
                } else if (wi < 128) {
                    if (!dut->dl_busy) {
                        dut->dl_we = 1;
                        dut->dl_addr = uint32_t(wi);
                        dut->dl_be = 0xF;
                        dut->dl_wdata = (uint32_t(e.dl[2 * wi]) << 16) | e.dl[2 * wi + 1];
                        wi++;
                    }
                } else if (!dut->dl_upbusy) {
                    for (int k = 0; k < 8; k++) {
                        uint32_t w = 0;
                        for (int b = 0; b < 4; b++) w |= uint32_t(e.wrap[4 * k + b]) << (8 * b);
                        dut->texwrap[k] = w;
                    }
                    dut->dl_up = 1;
                    wi = 0;
                    ei++;
                }
            } else if (!fed) {
                fed = true;
                fed_at = cycles;
            }
        }
        tick(false);
        if (dut->show_valid != prev_sv || dut->show_plane != prev_sp) {
            swaps++;
            prev_sv = dut->show_valid;
            prev_sp = dut->show_plane;
        }
        if (fed && swaps == int(clears) && dut->state == 6 && dut->queued == 0) break;
    }

    // the display reads an offered plane at a vblank, long after; let the arbiter's last writes out
    for (int i = 0; i < 2000; i++) tick(false);
    const bool finished = fed && swaps == int(clears);
    const uint32_t plane = COLOUR[dut->show_plane];
    size_t bad = 0;
    for (int i = 0; i < 512 * 512; i++) {
        const uint16_t want = uint16_t(ref[2 * i] | (ref[2 * i + 1] << 8));
        const uint16_t got = uint16_t(mem[plane + 2 * i] | (mem[plane + 2 * i + 1] << 8));
        if (got != want && bad++ < 20)
            printf("g3d: (%d,%d) %04x, the model %04x%c", i % 512, i / 512, got, want, 10);
    }
    const bool pass = finished && bad == 0;
    printf("g3d: %zu uploads and %zu clearing vblanks from event %zu, %d planes shown, %zu of 262144 pixels "
           "differ; %" PRIu64 " clocks (events in by %" PRIu64 "), %" PRIu64 " reads, %" PRIu64
           " writes (latency %d, %d%% busy): %s%c", uploads, clears, first, swaps, bad, cycles, fed_at, reads,
           writes, lat, busy_pct, pass ? "PASS" : "FAIL", 10);
    delete dut;
    return pass ? 0 : 1;
}
