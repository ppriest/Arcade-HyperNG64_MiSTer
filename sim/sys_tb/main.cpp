// SPDX-License-Identifier: GPL-3.0-or-later
//
// The whole board less its CPU, driven by MAME's bus trace.
//
//     scripts/run_verilator.sh sys_tb [+frames=400,800] [+n=4000000] [+fb=1] [+flip=1]
//
// The core is loaded the way MiSTer loads it: the layout blob as rom index 1 and the IO MCU's ROM
// as index 2 through the byte path, and an index-0 download with no bytes, because the HPS
// writes the image into DDR3 directly (the bench's DDR3 model holds it). The core then copies the
// BIOS into SDRAM and releases the game's reset. The BIOS region in the blob is cut to 16 KB: the
// copy is one SDRAM write per two bytes, and nothing here executes the BIOS.
//
// Then every access in MAME's trace to frame 900 is made through the CPU's own port, in order:
// the same bridge, I/O devices, DMA, backing store and video the CPU will use. Reads whose answer
// does not depend on timing are compared with MAME's; so is sound RAM, which is now plain memory
// behind the bridge. Writes MAME's handlers made as side effects of an earlier write - the DMA's
// copy, the sprite clears - are in the trace too; the core makes them itself, so they are
// skipped rather than made twice. Writes to the 3D buffers are skipped unless +fb=1: 1.2 million
// of them, and nothing here reads them.
//
// For each MAME frame N in +frames the replay stops at the trace's marker N + 1, the video renders a
// whole frame from the state as it stands - the sprite list is snapshotted at the vblank that
// starts it, as on the board - and that frame is compared pixel for pixel with the model's for
// MAME's frame N, debug/sams64-f<N>/model_rgb.bin, which is exact against MAME's screenshot for
// these 2D frames. N + 1 because the trace marks a frame as it starts, before its writes, and a
// capture of frame N is the state after it: marker 801 matches frame 800 exactly and marker 800
// does not, on a frame where the logo is fading in.
//
// +flip=1 runs with Flip Screen on from reset, and each frame is compared with the model's turned
// 180 degrees: MAME has no flip for this board, so the unflipped frame rotated is the reference.

#include "Vtb_sys.h"
#include "verilated.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <set>
#include <string>
#include <utility>
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
    if (!f) { fprintf(stderr, "cannot open %s\n", path.c_str()); exit(2); }
    fseek(f, 0, SEEK_END);
    std::vector<uint8_t> out(ftell(f));
    fseek(f, 0, SEEK_SET);
    if (fread(out.data(), 1, out.size(), f) != out.size()) exit(2);
    fclose(f);
    return out;
}

struct Ev {
    int frame;              // > 0 for a "# frame N" marker, else 0
    bool w;
    uint32_t addr, mask, data;
};

bool is_store(uint32_t a) {
    return a < 0x01000000 || (a >= 0x04000000 && a < 0x06000000) ||
           (a >= 0x1fc00000 && a < 0x1fc80000) || (a >= 0x20100000 && a < 0x20180000) ||
           (a >= 0x30100000 && a < 0x30160000) || (a >= 0x30200000 && a < 0x30260000) ||
           (a >= 0x60200000 && a < 0x60400000);
}

const char *device(uint32_t a) {
    if (a >= 0x1f700000 && a < 0x1f701100) return "sysregs";
    if (a >= 0x1f701100 && a < 0x1f701120) return "irqc";
    if (a >= 0x1f701200 && a < 0x1f701280) return "dmac";
    if (a >= 0x1f702100 && a < 0x1f702180) return "rtc";
    if (a >= 0x1f800000 && a < 0x1f804000) return "nvram";
    if (a >= 0x1f808000 && a < 0x1f808800) return "dualport";
    if (a >= 0x60000000 && a < 0x60200000) return "soundram2";
    if (a >= 0x60200000 && a < 0x60400000) return "soundram";
    if (a >= 0x68000000 && a < 0x68000010) return "mailbox";
    return "other";
}

uint32_t bswap32(uint32_t v) {
    return (v >> 24) | ((v >> 8) & 0xff00) | ((v << 8) & 0xff0000) | (v << 24);
}

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    const std::string set = arg("set", "sams64");
    const long limit = atol(arg("n", "4000000").c_str());
    const bool with_fb = atoi(arg("fb", "0").c_str()) != 0;
    const bool flip = atoi(arg("flip", "0").c_str()) != 0;
    std::set<int> frames;
    {
        std::string fl = arg("frames", "400,800");
        size_t p = 0;
        while (p < fl.size()) {
            size_t q = fl.find(',', p);
            if (q == std::string::npos) q = fl.size();
            if (q > p) frames.insert(atoi(fl.substr(p, q - p).c_str()));
            p = q + 1;
        }
    }

    // ---- the DDR3 image, laid out as scripts/build_mra.py lays it out ---------------------------------
    struct Region { const char *name; std::vector<uint8_t> data; uint32_t base, size; };
    std::vector<Region> reg;
    uint32_t pos = 0;
    for (const char *nm : {"gameprg", "bios", "scrtile", "sprtile"}) {
        Region r{nm, slurp("debug/rom/" + set + "-" + nm + ".bin"), pos, 0};
        r.size = uint32_t(r.data.size());
        pos += (r.size + 0xfffff) & ~0xfffffu;
        reg.push_back(std::move(r));
    }
    auto ddr_byte = [&](uint32_t a) -> uint8_t {
        for (const auto &r : reg)
            if (a >= r.base && a < r.base + r.size) return r.data[a - r.base];
        return 0;
    };
    const auto mcu = slurp("debug/rom/hng64-iomcu.bin");

    // the blob: "HNG2", then base and size per region, big-endian, then flags; the BIOS cut to 16 KB
    std::vector<uint8_t> blob = {'H', 'N', 'G', '2'};
    auto put32 = [&](uint32_t v) { for (int i = 3; i >= 0; i--) blob.push_back(uint8_t(v >> (8 * i))); };
    for (const auto &r : reg) {
        put32(r.base);
        put32(std::string(r.name) == "bios" ? 0x4000u : r.size);
    }
    for (int i = 0; i < 4; i++) put32(0);              // textures0, verts: not carried
    put32(0);                                          // flags

    // ---- the trace -----------------------------------------------------------------------------------
    std::vector<Ev> ev;
    {
        FILE *f = fopen(("debug/" + set + "-sys/" + set + "_sys.trace").c_str(), "r");
        if (!f) { fprintf(stderr, "no trace\n"); return 2; }
        char buf[256];
        while (long(ev.size()) < limit && fgets(buf, sizeof buf, f)) {
            Ev e{};
            if (buf[0] == '#') {
                int n;
                if (sscanf(buf, "# frame %d", &n) == 1) { e.frame = n; ev.push_back(e); }
                continue;
            }
            long seq;
            char rw;
            unsigned a, m, d;
            if (sscanf(buf, "%ld %c %x %x %x", &seq, &rw, &a, &m, &d) != 5) continue;
            e.w = (rw == 'w');
            e.addr = a; e.mask = m; e.data = d;
            ev.push_back(e);
        }
        fclose(f);
    }

    // ---- the core and its clocks ---------------------------------------------------------------------
    auto *dut = new Vtb_sys;
    dut->reset = 1;
    dut->mem_request = 0;
    dut->ioctl_download = 0;
    dut->ioctl_wr = 0;
    dut->inputs_flat = ~0ULL;                           // nothing pressed
    dut->flip = flip;
    dut->DDRAM_BUSY = 0;
    dut->DDRAM_DOUT_READY = 0;

    std::deque<std::pair<long, uint64_t>> ddr_q;
    long cyc = 0;
    uint32_t lfsr = 0xACE1u;

    // the frame being captured, if any
    bool capturing = false, cap_armed = false, cap_seen_blank = false, cap_seen_active = false;
    long nv_pulses = 0;                 // the core's NVRAM-written pulses, one per clk1x high
    std::vector<uint8_t> frame_rgb;
    int cap_x = 0, cap_y = 0;
    bool prev_hblank = true;

    auto step2x = [&]() {
        cyc++;
        dut->clk2x = 0;
        dut->eval();
        lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u);
        dut->DDRAM_BUSY = (lfsr % 100) < 10;
        // DDRAM_RD depends on BUSY combinationally: accept with the BUSY the core will see
        dut->eval();
        if (dut->DDRAM_WE && !dut->DDRAM_BUSY) {
            printf("sys: a DDR3 write, and nothing in the core writes DDR3: %08x\n",
                   uint32_t(dut->DDRAM_ADDR) << 3);
            exit(1);
        }
        if (dut->DDRAM_RD && !dut->DDRAM_BUSY) {
            uint32_t byte = uint32_t(dut->DDRAM_ADDR & 0x1ffffff) << 3;
            uint64_t d = 0;
            for (int i = 7; i >= 0; i--) d = (d << 8) | ddr_byte(byte + i);
            ddr_q.emplace_back(cyc + 12, d);
        }
        dut->DDRAM_DOUT_READY = 0;
        if (!ddr_q.empty() && ddr_q.front().first <= cyc) {
            dut->DDRAM_DOUT = ddr_q.front().second;
            dut->DDRAM_DOUT_READY = 1;
            ddr_q.pop_front();
        }
        const bool rise1x = (cyc & 1) == 0;
        dut->clk2x = 1;
        if (rise1x) dut->clk1x = 1;
        dut->eval();

        // a frame: from the first visible pixel after a vblank that BEGAN after arming (the
        // frame's sprite snapshot and palette rebuild happen as its vblank begins) to the next
        if (dut->ce_pix && (cap_armed || capturing)) {
            if (cap_armed && !dut->vblank) cap_seen_active = true;
            if (cap_armed && cap_seen_active && dut->vblank) cap_seen_blank = true;
            if (cap_armed && cap_seen_blank && !dut->vblank) {
                cap_armed = false;
                capturing = true;
                cap_x = cap_y = 0;
                prev_hblank = true;
            }
            if (capturing) {
                if (dut->vblank) {
                    capturing = false;
                } else if (!dut->hblank) {
                    if (prev_hblank && cap_x != 0) { cap_y++; cap_x = 0; }
                    if (cap_x < 512 && cap_y < 448) {
                        size_t o = (size_t(cap_y) * 512 + cap_x) * 3;
                        frame_rgb[o] = dut->r; frame_rgb[o + 1] = dut->g; frame_rgb[o + 2] = dut->b;
                    }
                    cap_x++;
                }
                prev_hblank = dut->hblank;
            }
        }

        dut->clk2x = 0;
        dut->eval();
        if (rise1x) { nv_pulses += dut->nv_written; dut->clk1x = 0; dut->eval(); }
    };
    auto step1x = [&]() { step2x(); step2x(); };

    for (int i = 0; i < 16; i++) step1x();

    // ---- loading, with the framework's reset held as MiSTer holds it --------------------------------
    auto download = [&](int index, const uint8_t *data, size_t n) {
        dut->ioctl_download = 1;
        dut->ioctl_index = index;
        step1x();
        for (size_t i = 0; i < n; i++) {
            dut->ioctl_addr = uint32_t(i);
            dut->ioctl_dout = data[i];
            dut->ioctl_wr = 1;
            step1x();
            dut->ioctl_wr = 0;
            step1x();
        }
        dut->ioctl_download = 0;
        step1x();
    };
    download(1, blob.data(), blob.size());
    download(2, mcu.data() + 0xc000, 0x4000);           // the top 16 KB, as the .mra sends it
    download(0, nullptr, 0);                            // the HPS writes DDR3; no bytes come
    for (int i = 0; i < 20000; i++) step1x();           // the SDRAM's initialisation
    dut->reset = 0;
    {
        long g = 0;
        while (dut->cpu_reset && ++g < 5000000) step1x();
        if (dut->cpu_reset) {
            printf("sys: the game never left reset (faults %02x; loader dl0_seen cfg_valid "
                   "pending done start active loaded mem_reset game_reset reset = %03x)\n",
                   dut->dbg_fault, dut->dbg_ldr);
            printf("sys: copy state/rd/ready/valid/swe/sready/DDRAM_RD = %02x\n", dut->dbg_copy);
            return 1;
        }
        printf("sys: loaded, BIOS copied, game out of reset at clk1x %ld\n", cyc / 2);
    }

    // ---- the replay ----------------------------------------------------------------------------------
    auto access = [&](bool w, uint32_t addr, uint32_t mask, uint32_t data) -> uint32_t {
        uint8_t wm = 0;
        for (int k = 0; k < 4; k++) if (mask & (0xffu << (24 - 8 * k))) wm |= uint8_t(1 << k);
        dut->mem_address = addr & ~3u;
        dut->mem_rnw = !w;
        dut->mem_writeMask = wm;
        dut->mem_dataWrite = bswap32(data);
        dut->mem_request = 1;
        step1x();
        dut->mem_request = 0;
        long g = 0;
        while (!dut->mem_done && ++g < 4000000) step1x();
        if (!dut->mem_done) {
            printf("sys: no completion for %c %08x (faults %02x)\n", w ? 'w' : 'r', addr, dut->dbg_fault);
            exit(1);
        }
        return bswap32(uint32_t(dut->mem_dataRead));
    };

    // A 64-bit I/O access, which MAME's trace never shows (its handlers are 32-bit) but the games
    // make (ld of the IO MCU's dual-port RAM): the bridge makes it two word accesses. Written as
    // a doubleword, read back as one and as two words, then cleared.
    {
        auto access64 = [&](bool w, uint32_t addr, uint64_t v) -> uint64_t {
            // the CPU's layout (cpu.vhd): the word at +0 byte-swapped in the high half on a write
            dut->mem_address = addr;
            dut->mem_rnw = !w;
            dut->mem_req64 = 1;
            dut->mem_writeMask = 0xff;
            dut->mem_dataWrite = (uint64_t(bswap32(uint32_t(v >> 32))) << 32) | bswap32(uint32_t(v));
            dut->mem_request = 1;
            step1x();
            dut->mem_request = 0;
            long g = 0;
            while (!dut->mem_done && ++g < 4000000) step1x();
            dut->mem_req64 = 0;
            // a doubleword load takes the word at +0 from the low half (cpu.vhd LOADTYPE_QWORD)
            const uint64_t r = dut->mem_dataRead;
            return (uint64_t(bswap32(uint32_t(r))) << 32) | bswap32(uint32_t(r >> 32));
        };
        const uint64_t pat = 0x0123456789abcdefull;
        access64(true, 0x1f808400, pat);
        const uint64_t got = access64(false, 0x1f808400, 0);
        const uint32_t w0 = access(false, 0x1f808400, 0xffffffff, 0), w1 = access(false, 0x1f808404, 0xffffffff, 0);
        const bool ok = got == pat && w0 == uint32_t(pat >> 32) && w1 == uint32_t(pat);
        printf("sys: 64-bit I/O: wrote %016llx, read %016llx, as words %08x %08x: %s%c",
               (unsigned long long)pat, (unsigned long long)got, w0, w1, ok ? "ok" : "FAIL", 10);
        access64(true, 0x1f808400, 0);
        if (!ok) return 1;
    }

    // the NVRAM as MAME's .nvm file would hold it after the trace's writes: its share is a u32
    // array saved little-endian, so the byte at CPU address A is file byte (A - base) ^ 3
    std::vector<uint8_t> nv_model(0x4000, 0);
    long nv_writes = 0;

    std::map<std::string, std::pair<long, long>> tally;
    long made = 0, skipped_fx = 0, skipped_fb = 0, bad_reads = 0, frames_bad = 0;
    int shown = 0;
    long skip = 0;
    auto t0 = std::chrono::steady_clock::now();

    for (size_t i = 0; i < ev.size(); i++) {
        const Ev &e = ev[i];
        if (e.frame) {
            if (!frames.count(e.frame - 1)) continue;
            const int mame_frame = e.frame - 1;
            frame_rgb.assign(448 * 512 * 3, 0);
            cap_armed = true;
            cap_seen_blank = false;
            cap_seen_active = false;
            long g = 0;
            while ((cap_armed || capturing) && ++g < 20000000) step1x();
            // every captured frame is kept, whether or not there is a model to compare with
            {
                FILE *o = fopen(("debug/" + set + "-sys/frame" + std::to_string(mame_frame) +
                                 (flip ? "-flip" : "") + ".rgb").c_str(), "wb");
                if (o) { fwrite(frame_rgb.data(), 1, frame_rgb.size(), o); fclose(o); }
            }
            const std::string ref = "debug/" + set + "-f" + std::to_string(mame_frame) + "/model_rgb.bin";
            FILE *f = fopen(ref.c_str(), "rb");
            if (!f) { printf("sys: frame %d captured; no %s to compare with\n", mame_frame, ref.c_str()); continue; }
            std::vector<uint8_t> want(448 * 512 * 3);
            size_t got_n = fread(want.data(), 1, want.size(), f);
            fclose(f);
            long diff = 0;
            // turned 180 degrees, pixel p of the frame is pixel N - 1 - p of the model's
            for (size_t p = 0; p < 448 * 512 && p * 3 + 2 < got_n; p++) {
                const size_t q = flip ? 448 * 512 - 1 - p : p;
                if (memcmp(&want[q * 3], &frame_rgb[p * 3], 3)) diff++;
            }
            printf("sys: frame %d%s: %ld of %d pixels differ from the model%s\n", mame_frame,
                   flip ? " flipped" : "", diff, 448 * 512, flip ? " turned 180 degrees" : "");
            if (diff) frames_bad++;
            continue;
        }
        if (skip) { skip--; skipped_fx++; continue; }
        if (!with_fb && e.w && e.addr >= 0x30100000 && e.addr < 0x30260000) { skipped_fb++; continue; }

        const uint32_t got = access(e.w, e.addr, e.mask, e.data);
        made++;

        if (e.w && device(e.addr) == "nvram") {
            nv_writes++;
            for (int k = 0; k < 4; k++)
                if (e.mask & (0xffu << (24 - 8 * k)))
                    nv_model[(((e.addr & ~3u) + k) - 0x1f800000) ^ 3] = uint8_t(e.data >> (24 - 8 * k));
        }
        if (e.w) {
            // what MAME's handler wrote next as a result is in the trace; the core writes it
            if ((e.addr & ~3u) == 0x1f701224 && e.mask == 0xffffffff && int32_t(e.data) >= 0)
                skip = long(e.data) + 1;
            else if (e.addr >= 0x2000d800 && e.addr < 0x2000e400)
                skip = ((e.mask & 0xffff0000) ? 4 : 0) + ((e.mask & 0x0000ff00) ? 4 : 0);
            else if (e.addr >= 0x2000e400 && e.addr < 0x2000f000)
                skip = ((e.mask & 0xffff0000) ? 3 : 0) + ((e.mask & 0x0000ffff) ? 3 : 0);
        } else {
            const std::string d = device(e.addr);
            const bool rtc_time = d == "rtc" && !((e.addr & 4) && ((e.addr >> 3) & 0xf) >= 0xd);
            if (d == "irqc" || rtc_time || d == "other") continue;
            auto &t = tally[d];
            t.first++;
            if ((got & e.mask) != (e.data & e.mask)) {
                t.second++;
                if (d != "dualport") {
                    bad_reads++;
                    if (shown++ < 10)
                        printf("  read %08x mask %08x: got %08x, MAME %08x\n", e.addr, e.mask,
                               got & e.mask, e.data & e.mask);
                }
            }
        }
        if (made % 200000 == 0) {
            double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
            printf("sys: %ld accesses, %.0f clk2x/s\n", made, cyc / s);
            fflush(stdout);
        }
    }

    printf("sys: %ld accesses made, %ld side-effect writes left to the core, %ld 3D-buffer writes skipped\n",
           made, skipped_fx, skipped_fb);
    for (const auto &t : tally)
        printf("  %-10s %7ld reads compared, %ld differ%s\n", t.first.c_str(), t.second.first,
               t.second.second, t.first == "dualport" ? " (the IO MCU's answers, timing dependent)" : "");
    // ---- the NVRAM's host port: the upload after the replay, then a download read back both ways ----
    auto upload = [&](std::vector<uint8_t> &out) {
        out.assign(0x4000, 0);
        for (uint32_t j = 0; j < 0x4000; j++) {
            dut->ioctl_addr = j;
            step1x();
            out[j] = dut->nv_rdata;
        }
    };
    std::vector<uint8_t> nv_got;
    upload(nv_got);
    long nv_bad = 0;
    for (int j = 0; j < 0x4000; j++) nv_bad += nv_got[j] != nv_model[j];
    printf("sys: nvram upload: %ld of 16384 bytes differ from the trace's writes (%ld writes, %ld "
           "written pulses)\n", nv_bad, nv_writes, nv_pulses);

    std::vector<uint8_t> pat(0x4000);
    for (int j = 0; j < 0x4000; j++) pat[j] = uint8_t(j * 37 + (j >> 8) + 1);
    dut->reset = 1;
    download(4, pat.data(), pat.size());
    dut->reset = 0;
    for (long g = 0; dut->cpu_reset && g < 100000; g++) step1x();
    upload(nv_got);
    long nv_bad_dl = 0, nv_bad_cpu = 0;
    for (int j = 0; j < 0x4000; j++) nv_bad_dl += nv_got[j] != pat[j];
    for (uint32_t i = 0; i < 0x1000; i++) {
        const uint32_t want = uint32_t(pat[4 * i]) | uint32_t(pat[4 * i + 1]) << 8 |
                              uint32_t(pat[4 * i + 2]) << 16 | uint32_t(pat[4 * i + 3]) << 24;
        nv_bad_cpu += access(false, 0x1f800000 + 4 * i, 0xffffffff, 0) != want;
    }
    printf("sys: nvram download: %ld of 16384 bytes read back wrong, %ld of 4096 CPU dwords wrong\n",
           nv_bad_dl, nv_bad_cpu);

    printf("sys: %ld clk2x in all; %u line passes, the longest %u clk2x (tilemaps busy %u of them), "
           "%u late\n", cyc, dut->passes, dut->pass_max, dut->pass_max_tm, dut->late_passes);
    printf("sys: faults %02x; %ld compared reads differ; %ld frames differ\n", dut->dbg_fault,
           bad_reads, frames_bad);
    const bool fail = bad_reads || frames_bad || (dut->dbg_fault & 0x1f) || nv_bad ||

                      nv_pulses != nv_writes || nv_bad_dl || nv_bad_cpu;
    delete dut;
    return fail ? 1 : 0;
}
