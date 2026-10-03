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
    // +realtime=N: the board's frame timing, for N video frames. A vblank every 2,083,333 clocks
    // (60 Hz), at whose rising edge the RTL queues a clearing event whatever the game has done;
    // the game's uploads go in as the queue takes them, and after a capture frame's last upload
    // the game waits for the next vblank (the capture's frames, from the +back'th, played round
    // and round); the display takes an offered plane only as a frame starts (the vblank's end).
    // Reports how many capture frames the game got through and how many planes were shown.
    const long rt_frames = atol(arg("realtime", "0").c_str());
    // +vid=K, +cpu=K: the port's other readers, a PRIO one and a plain one, each raising a request
    // with K% chance a clock and holding it until it is taken (their replies are dropped)
    const int vid_pct = atoi(arg("vid", "0").c_str());
    const int cpu_pct = atoi(arg("cpu", "0").c_str());
    uint32_t orng = 0x13579BDu;
    uint64_t vid_n = 0, cpu_n = 0;

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
        // the display: takes an offered plane a while later (in realtime mode, as a frame starts)
        const bool differ = dut->show_valid != dut->shown_valid || dut->show_plane != dut->shown_plane;
        if (rt_frames > 0) {
            if (differ && (cycles % 2083333) == 120000) {
                dut->shown_valid = dut->show_valid;
                dut->shown_plane = dut->show_plane;
            }
        } else if (differ && show_delay < 0) show_delay = 2000;
        if (show_delay == 0) {
            dut->shown_valid = dut->show_valid;
            dut->shown_plane = dut->show_plane;
        }
        if (show_delay >= 0) show_delay--;
        run3(tns + 4);
        // the other readers: a request ready at this edge is taken
        const bool vid_taken = !rst && dut->vid_rd && dut->vid_ready;
        const bool cpu_taken = !rst && dut->cpu_rd && dut->cpu_ready;
        dut->clk2x = 1;
        dut->clk1x = (cycles & 1) ? 0 : 1;
        dut->eval();
        cycles++;
        tns += 8;
        if (vid_taken) { dut->vid_rd = 0; vid_n++; }
        if (cpu_taken) { dut->cpu_rd = 0; cpu_n++; }
        // and new ones are raised by chance, for the next clock
        if (!rst) {
            orng = orng * 1103515245u + 12345u;
            if (!dut->vid_rd && int((orng >> 16) % 100) < vid_pct) {
                dut->vid_rd = 1;
                dut->vid_addr = (orng & 0xFFFFF8u) | 0x1000000u;
            }
            orng = orng * 1103515245u + 12345u;
            if (!dut->cpu_rd && int((orng >> 16) % 100) < cpu_pct) {
                dut->cpu_rd = 1;
                dut->cpu_addr = (orng & 0xFFFFF8u) | 0x2000000u;
            }
        }
    };

    for (int i = 0; i < 8; i++) tick(true);

    if (rt_frames > 0) {
        // the capture's frames from `first`, without the closing C the default mode appends
        std::vector<Event> game(all.begin() + long(first), all.end());
        size_t gi = 0, wi = 0;
        bool waiting = false;          // the game has sent a frame and waits for a vblank
        bool vb_prev = false;
        long game_frames = 0, shown = 0, video = 0;
        int prev_sv = 0, prev_sp = 0;
        long started = -1;             // the first video frame counted (after the start-up)
        bool ready_seen = false;       // the 3D has been idle once: its start-up is over
        const uint64_t P = 2083333, VBL = 120000;
        while (true) {
            const bool vbl = (cycles % P) < VBL;
            if ((cycles & 1) == 0) {
                dut->dl_we = 0;
                dut->dl_up = 0;
                dut->vblank = vbl;
                if (dut->state == 6) ready_seen = true;
                if (vbl && !vb_prev) {
                    if (ready_seen) {          // the 3D's start-up is over
                        if (started < 0) started = 0;
                        video++;
                    }
                    waiting = false;
                }
                vb_prev = vbl;
                if (!waiting && started >= 0) {
                    const Event &e = game[gi];
                    if (e.kind == 'C') {
                        game_frames++;
                        waiting = true;
                        gi = (gi + 1) % game.size();
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
                        gi = (gi + 1) % game.size();
                    }
                }
            }
            tick(false);
            if (dut->shown_valid != prev_sv || dut->shown_plane != prev_sp) {
                if (started >= 0) shown++;
                prev_sv = dut->shown_valid;
                prev_sp = dut->shown_plane;
            }
            if (video > rt_frames) break;
            if (cycles > uint64_t(rt_frames + 20) * P) {
                printf("g3d realtime: stopped at clock %llu, %ld video frames counted, state %d%c",
                       (unsigned long long)cycles, video, int(dut->state), 10);
                break;
            }
        }
        printf("g3d realtime: %ld video frames: the game through %ld capture frames (%.0f%%), %ld planes shown "
               "(latency %d, %d%% busy)%c", video - 1, game_frames, 100.0 * game_frames / double(video - 1),
               shown, lat, busy_pct, 10);
        delete dut;
        return 0;
    }

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
            printf("g3d: plane %d shown at clock %llu%c", int(dut->show_plane),
                   (unsigned long long)cycles, 10);
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
           " writes (latency %d, %d%% busy; other readers %" PRIu64 " PRIO, %" PRIu64 " plain): %s%c", uploads,
           clears, first, swaps, bad, cycles, fed_at, reads, writes, lat, busy_pct, vid_n, cpu_n,
           pass ? "PASS" : "FAIL", 10);
    delete dut;
    return pass ? 0 : 1;
}
