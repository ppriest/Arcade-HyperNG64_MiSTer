// SPDX-License-Identifier: GPL-3.0-or-later
//
// rtl/hng64_sndbridge.sv against a DDR3 model and a process model.
//
//     scripts/run_verilator.sh sndbridge_tb
//
// The DDR3 model takes writes with a random ready and answers reads 20 clocks later. The bench
// writes sound RAM (and other memory, which must not be copied), raises interrupt 5 and enables
// and holds the sound CPU, and plays the process: it writes the status word with its latches,
// flags and a heartbeat. Checked:
//   - every sound RAM write is in the copy, byte for byte, and nothing else is;
//   - the +0x10 word with a new enable count is written only after every sound RAM write made
//     before the enable is in the copy;
//   - the magic, the sample ROM's base and size, the latches and counts, and the run word;
//   - live: not on DDR3's stale contents (a static heartbeat, flags 0xA501); on once the
//     heartbeat moves, whether or not the process has started its V53A; the replies follow the
//     status word; off when it stops, and on 0xAA55.

#include "Vtb_sndbridge.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <vector>

namespace {

constexpr uint32_t SHM = 0xF200000;

int fails = 0;
void check(bool ok, const char *what)
{
	printf("  %-62s %s\n", what, ok ? "ok" : "FAIL");
	if (!ok) fails++;
}

}  // namespace

double sc_time_stamp() { return 0; }

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);
	auto *dut = new Vtb_sndbridge;

	std::vector<uint8_t> ddr(0x210000, 0);
	auto shm64 = [&](uint32_t off) {
		uint64_t v = 0;
		for (int k = 7; k >= 0; k--) v = (v << 8) | ddr[off + k];
		return v;
	};
	auto shm_put64 = [&](uint32_t off, uint64_t v) {
		for (int k = 0; k < 8; k++) ddr[off + k] = uint8_t(v >> (8 * k));
	};
	std::deque<std::pair<long, uint64_t>> rq;
	std::map<uint32_t, uint8_t> want;          // sound RAM offset -> byte, as written
	uint32_t lfsr = 0xACE1;
	long cyc = 0;
	bool order_bad = false, outside = false;
	uint16_t en_seen = 0;
	std::map<uint32_t, uint8_t> want_at_enable;
	bool snap_pending = false;

	auto tick = [&] {
		lfsr = (lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u);
		dut->w_ready = (lfsr & 3) != 0;
		dut->r_ready = (lfsr & 4) != 0;
		dut->clk = 0;
		dut->eval();
		if (dut->w_valid && dut->w_ready) {
			const uint32_t a = dut->w_addr;
			if (a < SHM || a >= SHM + 0x210000) outside = true;
			else {
				for (int k = 0; k < 8; k++)
					if (dut->w_be & (1 << k)) ddr[a - SHM + k] = uint8_t(dut->w_data >> (8 * k));
				// a new enable count: everything written before the enable must be in the copy
				if (a == SHM + 0x10 && uint16_t(dut->w_data >> 48) != en_seen) {
					en_seen = uint16_t(dut->w_data >> 48);
					for (const auto &kv : want_at_enable)
						if (ddr[0x10000 + kv.first] != kv.second) order_bad = true;
				}
			}
		}
		if (dut->r_rd && dut->r_ready) rq.emplace_back(cyc + 20, shm64(dut->r_addr - SHM));
		dut->r_valid = 0;
		if (!rq.empty() && rq.front().first <= cyc) {
			dut->r_valid = 1;
			dut->r_data = rq.front().second;
			rq.pop_front();
		}
		dut->clk = 1;
		dut->eval();
		cyc++;
	};
	auto run = [&](int n) { for (int i = 0; i < n; i++) tick(); };

	// the main CPU's sound RAM write, as the backing store takes it
	auto st_write = [&](uint32_t addr, uint64_t data, uint8_t be) {
		dut->st_req = 1; dut->st_we = 1; dut->st_addr = addr; dut->st_wdata = data; dut->st_be = be;
		tick();
		dut->st_req = 0; dut->st_we = 0;
		if (addr >= 0x60200000 && addr < 0x60400000)
			for (int k = 0; k < 8; k++)
				if (be & (1 << k)) want[(addr & ~7u) - 0x60200000 + k] = uint8_t(data >> (8 * k));
		run(1 + (lfsr & 7));
	};
	// hng64_io's one-clk1x pulses are two of these clocks
	auto pulse_irq = [&] { dut->irq = 1; run(2); dut->irq = 0; run(4); };
	auto pulse_en = [&](uint16_t cmd) { dut->en_cmd = cmd; dut->en = 1; run(2); dut->en = 0; run(4); };

	// DDR3 as an earlier session left it: a heartbeat that does not move, flags saying "runs"
	shm_put64(0x40, uint64_t(0x1234) << 48 | uint64_t(0xA501) << 32 | 0xBEEF0042u);

	dut->reset = 1;
	run(10);
	dut->reset = 0;
	dut->cfg_valid = 1;
	dut->smp_base = 0x9900000;
	dut->smp_size = 0x1000000;
	run(50);

	printf("sndbridge:\n");
	check(!memcmp(ddr.data(), "HNGS", 4) && ddr[4] == 2, "magic and version");
	{
		// the count at +0x20 (BEAT 100 here): up while the core runs, still while it is held in reset
		const uint64_t b0 = shm64(0x20);
		run(1000);
		const uint64_t b1 = shm64(0x20);
		check(b1 >= b0 + 8 && b1 <= b0 + 11, "the count moves every BEAT clocks");
		dut->reset = 1;
		run(1000);
		check(shm64(0x20) == b1, "the count stops in reset");
		dut->reset = 0;
		run(50);
	}
	check(shm64(0x08) == (uint64_t(0x1000000) << 32 | 0x9900000), "the sample ROM's base and size");

	// the upload: sound RAM and some other memory, with a full queue's worth at once
	for (int i = 0; i < 3000; i++) {
		const uint32_t off = (lfsr * 8u) & 0x1ffff8u;
		st_write(0x60200000 + off, (uint64_t(lfsr) << 40) ^ (uint64_t(i) * 0x9E3779B97F4A7C15ull),
		         uint8_t(lfsr | 1));
		if (i % 7 == 0) st_write(0x00100000 + off, 0x1111111111111111ull, 0xff);   // main RAM
	}
	// a burst a write every four clocks, faster than the backing store's SDRAM writes go
	for (int i = 0; i < 2000; i++) {
		dut->st_req = 1; dut->st_we = 1; dut->st_addr = 0x60300000 + 8 * i;
		dut->st_wdata = 0x0102030405060708ull + i; dut->st_be = 0xff;
		for (int k = 0; k < 8; k++) want[0x100000 + 8 * i + k] = uint8_t((0x0102030405060708ull + i) >> (8 * k));
		tick();
		dut->st_req = 0; dut->st_we = 0;
		run(3);
	}
	const bool overflow = dut->dbg_overflow;

	// the enable, straight after the last write: its count must land behind the copy
	want_at_enable = want;
	dut->main0 = 0x1234; dut->main1 = 0x5678;
	pulse_en(0x55AA);
	run(5000);
	long copy_bad = 0;
	for (const auto &kv : want) copy_bad += ddr[0x10000 + kv.first] != kv.second;
	long extra = 0;
	for (uint32_t off = 0; off < 0x200000; off++)
		if (ddr[0x10000 + off] && !want.count(off)) extra++;
	printf("  (%zu sound RAM bytes written)\n", want.size());
	if (overflow) printf("  the copy's queue overflowed: the back-to-back writes are not all kept\n");
	check(!overflow && copy_bad == 0, "the copy matches every sound RAM write");
	check(extra == 0, "nothing else is copied");
	check(!order_bad && en_seen == 1, "the enable count lands after the copy's writes");
	check(!outside, "no write outside the block");
	check(shm64(0x10) == (uint64_t(1) << 48 | uint64_t(0) << 32 | 0x56781234u), "latches, counts");
	check((shm64(0x18) & 1) == 1, "run word set by 0x55AA");

	pulse_irq(); pulse_irq(); run(200);
	check(uint16_t(shm64(0x10) >> 32) == 2, "two interrupt-5 writes counted");
	dut->main0 = 0xAAAA; run(200);
	check(uint16_t(shm64(0x10)) == 0xAAAA, "a latch change rewrites the word");

	// live: not on the stale word
	run(64 * 40);
	check(!dut->live, "not live on a static heartbeat left in DDR3");

	// the process starts: heartbeat moving, flags 0xA501, its latches
	uint16_t hb = 1;
	auto proc = [&](int polls, bool beat, uint16_t r0, uint16_t r1, uint16_t flags) {
		for (int i = 0; i < polls; i++) {
			if (beat) hb++;
			shm_put64(0x40, uint64_t(hb) << 48 | uint64_t(flags) << 32 | uint32_t(r1) << 16 | r0);
			run(64);
		}
	};
	proc(40, true, 0x55AA, 0x0082, 0xA501);
	check(dut->live && dut->rep0 == 0x55AA && dut->rep1 == 0x0082, "live once the heartbeat moves; its latches");
	proc(5, true, 0x38FF, 0x0083, 0xA501);
	check(dut->live && dut->rep0 == 0x38FF && dut->rep1 == 0x0083, "the replies follow the status word");
	proc(40, false, 0x38FF, 0x0083, 0xA501);
	check(!dut->live, "not live once the heartbeat stops");
	proc(40, true, 0x38FF, 0x0083, 0xA501);
	check(dut->live, "live again when it moves");
	proc(10, true, 0x0000, 0x0000, 0xA500);
	check(dut->live && dut->rep1 == 0, "live before the process runs its V53A: its zero latches");
	proc(10, true, 0x38FF, 0x0083, 0xA501);
	pulse_en(0xAA55);
	run(500);
	check(!dut->live && (shm64(0x18) & 1) == 0, "0xAA55: not live, run word clear");
	check(uint16_t(shm64(0x10) >> 48) == 1, "0xAA55 leaves the enable count");

	printf("sndbridge: %s, %ld clocks\n", fails ? "FAIL" : "PASS", cyc);
	delete dut;
	return fails ? 1 : 0;
}
