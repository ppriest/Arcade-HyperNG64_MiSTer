// SPDX-License-Identifier: GPL-3.0-or-later
//
// Replays a capture's display-list events through hng64_geo and compares every triangle it emits
// with the one scripts/geo_engine.py's simulator emitted for the same event.
//
//     python scripts/geo_engine.py sams64 600 --dump        # writes debug/sams64-f600/geo_events.txt
//     scripts/run_verilator.sh geo_tb +cap=debug/sams64-f600 +verts=debug/rom/sams64-verts.bin
//         [+lat=60] [+busy=20] [+stall=1]
//
// geo_events.txt: "I samsho vlen", then per event "C" (a clearing vblank: the engine's clear
// entry) or "U" + 256 display-list words and 32 wrap bytes (hex; the upload entry), each followed
// by the triangles expected ("T" + the 22 words of the setup record + 12 attribute fields) and "E". The display
// list is served as a synchronous RAM; the vertex ROM's reads are answered in order +lat clocks
// on, +busy percent refused. +stall=1 drops the triangle output's ready on pseudo-random clocks.

#include "Vtb_geo.h"
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

int64_t sext(uint64_t v, int bits) { return int64_t(v << (64 - bits)) >> (64 - bits); }

struct Event {
    char kind;                               // 'C' or 'U'
    std::vector<uint16_t> dl;
    std::vector<uint8_t> wrap;
    std::vector<std::vector<int64_t>> tris;  // 34 values each
    uint64_t est = 0;                        // the simulator's clock estimate for it
};

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string cap = arg("cap", "");
    const std::vector<uint8_t> verts = slurp(arg("verts", ""));
    const int lat = atoi(arg("lat", "60").c_str());
    const int busy_pct = atoi(arg("busy", "20").c_str());
    const bool stall = atoi(arg("stall", "0").c_str()) != 0;

    FILE *f = fopen((cap + "/geo_events.txt").c_str(), "r");
    if (!f) { fprintf(stderr, "no geo_events.txt in %s%c", cap.c_str(), 10); return 2; }
    std::vector<Event> evs;
    int samsho = 0;
    long vlen = 0;
    std::string line;
    char buf[65536];
    while (fgets(buf, sizeof buf, f)) {
        char *s = buf + 1;
        if (buf[0] == 'I') {
            samsho = int(strtol(s, &s, 10));
            vlen = strtol(s, &s, 10);
        } else if (buf[0] == 'C') {
            evs.push_back(Event{'C', {}, {}, {}});
        } else if (buf[0] == 'U') {
            Event e{'U', {}, {}, {}};
            for (int k = 0; k < 256; k++) e.dl.push_back(uint16_t(strtoul(s, &s, 16)));
            for (int k = 0; k < 32; k++) e.wrap.push_back(uint8_t(strtoul(s, &s, 16)));
            evs.push_back(e);
        } else if (buf[0] == 'E' && !evs.empty()) {
            evs.back().est = strtoull(s, &s, 10);
        } else if (buf[0] == 'T') {
            std::vector<int64_t> t;
            for (int k = 0; k < 34; k++) t.push_back(strtoll(s, &s, 10));
            evs.back().tris.push_back(t);
        }
    }
    fclose(f);

    Vtb_geo *dut = new Vtb_geo;
    uint64_t cycles = 0;
    std::vector<uint16_t> dl(256, 0);
    uint32_t dl_prev = 0;
    std::deque<std::pair<uint64_t, uint64_t>> vq;
    uint32_t rnd = 0x1234u, lfsr = 0xACE1u;
    std::vector<std::vector<int64_t>> got;

    auto tick = [&]() {
        dut->clk = 0;
        dut->dl_data = dl[dl_prev & 0xFF];
        rnd = rnd * 1103515245u + 12345u;
        dut->v_rd_ready = int((rnd >> 16) % 100) >= busy_pct;
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u);
        dut->tri_ready = stall ? (lfsr & 3) != 0 : 1;
        dut->v_data_valid = !vq.empty() && vq.front().first <= cycles;
        if (dut->v_data_valid) { dut->v_data = vq.front().second; vq.pop_front(); }
        dut->eval();
        dl_prev = dut->dl_addr;
        if (dut->v_rd && dut->v_rd_ready) {
            uint64_t w = 0;
            const uint32_t a = dut->v_rd_addr;
            for (int k = 0; k < 8; k++) w |= uint64_t(a + k < verts.size() ? verts[a + k] : 0) << (8 * k);
            vq.emplace_back(cycles + lat, w);
        }
        if (dut->tri_valid && dut->tri_ready) {
            std::vector<int64_t> t;
            for (int k = 0; k < 22; k++) t.push_back(int64_t(dut->rec[k]));
            // Pixel.scala Attr, first field lowest: 1 1 1 4 2 7 7 16 9 9 5 5
            const int aw[12] = {1, 1, 1, 4, 2, 7, 7, 16, 9, 9, 5, 5};
            int pos = 0;
            for (int k = 0; k < 12; k++) {
                uint64_t v = 0;
                for (int b = 0; b < aw[k]; b++, pos++)
                    v |= uint64_t((dut->tri_attr[pos / 32] >> (pos % 32)) & 1) << b;
                t.push_back(int64_t(v));
            }
            got.push_back(t);
        }
        dut->clk = 1;
        dut->eval();
        cycles++;
    };

    dut->reset = 1;
    dut->start = 0;
    dut->samsho = samsho;
    dut->vlen = uint32_t(vlen);
    dut->vbase = 0;
    for (int i = 0; i < 4; i++) tick();
    dut->reset = 0;

    auto run = [&](int entry) {
        dut->entry = entry;
        dut->start = 1;
        tick();
        dut->start = 0;
        uint64_t guard = 0;
        while ((dut->busy || dut->tri_valid) && guard++ < 50000000ull) tick();
        return guard < 50000000ull;
    };

    if (!run(0)) { printf("geo: init did not finish%c", 10); return 1; }
    size_t ev_n = 0, tris = 0, bad = 0;
    uint64_t upload_cycles = 0, upload_est = 0;
    for (const Event &e : evs) {
        got.clear();
        const uint64_t c0 = cycles;
        bool ok;
        if (e.kind == 'C') {
            ok = run(1);
        } else {
            dl = e.dl;
            for (int k = 0; k < 32; k++) {
                dut->wrap[k / 4] = (dut->wrap[k / 4] & ~(0xFFu << (8 * (k % 4)))) | (uint32_t(e.wrap[k]) << (8 * (k % 4)));
            }
            ok = run(2);
            upload_cycles += cycles - c0;
            upload_est += e.est;
        }
        if (!ok) { printf("geo: event %zu did not finish%c", ev_n, 10); return 1; }
        tris += e.tris.size();
        const size_t n = std::max(got.size(), e.tris.size());
        for (size_t t = 0; t < n; t++) {
            const bool same = t < got.size() && t < e.tris.size() && got[t] == e.tris[t];
            if (!same && bad++ < 5) {
                printf("geo: event %zu triangle %zu:%c  rtl   ", ev_n, t, 10);
                if (t < got.size()) for (int64_t v : got[t]) printf(" %" PRId64, v);
                printf("%c  model ", 10);
                if (t < e.tris.size()) for (int64_t v : e.tris[t]) printf(" %" PRId64, v);
                printf("%c", 10);
            }
        }
        ev_n++;
    }
    const bool pass = bad == 0;
    printf("geo: %zu events, %zu triangles, %zu differ, %" PRIu64 " clocks in uploads (the simulator's estimate %" PRIu64
           "; latency %d, %d%% refused%s): %s%c", ev_n, tris, bad, upload_cycles, upload_est, lat, busy_pct,
           stall ? ", output stalled" : "", pass ? "PASS" : "FAIL", 10);
    delete dut;
    return pass ? 0 : 1;
}
