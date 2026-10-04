// SPDX-License-Identifier: GPL-3.0-or-later
// The sound board's bench against a MAME capture (scripts/mame_sound_trace.py):
//
//   hng64snd_bench <set>-sound/<set>_sound.trace <set>_sndram_0.bin <set>-l7a1045.bin out.wav
//
// Powers the board on at the capture's first 0x55AA, replays the main CPU's enable and mailbox
// writes at their MAME times, and checks
//   - the V53A's I/O below 0x300 (L7A1045, port 0x80, latches, banks), access by access, against
//     the capture's;
//   - every mailbox value the main CPU read, against what it read in MAME.
// out.wav is front left, front right, rear (OUT7) and subwoofer (OUT6) at 44.1 kHz from MAME's
// time 0, as MAME's -wavwrite lays them out; scripts/snd_compare.py compares it with MAME's.
//
// BENCH_DRIFT=1 prints the time difference along the matching accesses; BENCH_INTLOG=<file>
// logs the V53A's internal registers' traffic; built with -DNEC_PROFILE, it prints where the
// V53A spends its instructions.

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include "board.h"

struct ev
{
	double us;
	bool main;
	char rw;
	u32 addr, mask, data;
};

static std::vector<u8> load(const char *path, size_t size)
{
	std::vector<u8> v(size, 0);
	FILE *f = std::fopen(path, "rb");
	if (!f) { std::fprintf(stderr, "cannot open %s\n", path); std::exit(1); }
	const size_t n = std::fread(v.data(), 1, size, f);
	std::fclose(f);
	if (n != size) { std::fprintf(stderr, "%s: %zu bytes, expected %zu\n", path, n, size); std::exit(1); }
	return v;
}

static s64 ticks(double us) { return std::llround(us * 32.0); }

static void put16(FILE *f, u16 v) { std::fputc(v & 0xff, f); std::fputc(v >> 8, f); }
static void put32(FILE *f, u32 v) { put16(f, v & 0xffff); put16(f, v >> 16); }

int main(int argc, char **argv)
{
	if (argc != 5)
	{
		std::fprintf(stderr, "usage: %s trace sndram.bin l7a1045.bin out.wav\n", argv[0]);
		return 2;
	}

	// the capture
	std::ifstream tf(argv[1]);
	if (!tf) { std::fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
	double t_enable = -1;
	std::vector<ev> evs;
	std::string line;
	while (std::getline(tf, line))
	{
		if (line.rfind("# sound RAM 0 at ", 0) == 0)
		{
			t_enable = std::atof(line.c_str() + 17);
			continue;
		}
		if (line.empty() || line[0] == '#') continue;
		std::istringstream is(line);
		int frame;
		ev e{};
		std::string side, rw, a, m, d;
		is >> frame >> e.us >> side >> rw >> a >> m >> d;
		e.main = side == "main";
		e.rw = rw[0];
		e.addr = u32(std::stoul(a, nullptr, 16));
		e.mask = u32(std::stoul(m, nullptr, 16));
		e.data = u32(std::stoul(d, nullptr, 16));
		if (t_enable >= 0) evs.push_back(e);
	}
	if (t_enable < 0) { std::fprintf(stderr, "no '# sound RAM 0' line in the trace\n"); return 1; }

	std::vector<u8> rom = load(argv[3], 0x1000000);
	sound_board b(rom.data());
	{
		std::vector<u8> ram = load(argv[2], 0x200000);
		std::memcpy(b.ram(), ram.data(), ram.size());
	}

	struct io { s64 t; char rw; u32 addr, mask, data; };
	std::vector<io> ours;
	b.m_io_log = [&](s64 t, char rw, offs_t a, u16 m, u16 d) { ours.push_back({t, rw, a, m, d}); };

	// the image is sound RAM at the first 0x55AA, which the trace logs just before it
	FILE *intlog = std::getenv("BENCH_INTLOG") ? std::fopen(std::getenv("BENCH_INTLOG"), "w") : nullptr;
	if (intlog)
		b.cpu().m_int_log = [&](char rw, offs_t a, u8 d) {
			std::fprintf(intlog, "%.3f %c %04X %02X\n", b.cpu_now() / 32.0, rw, a, d);
		};
	if (const char *div = std::getenv("BENCH_CPU_DIV")) b.set_cpu_divider(std::atoi(div));
	b.power_on(ticks(t_enable));
	b.soundcpu_enable_w(0x55AA);
	const auto wall0 = std::chrono::steady_clock::now();

	// the main CPU's 32-bit bus to the board's 16-bit handlers: the upper half is the lower address
	auto half = [](const ev &e, offs_t base, offs_t &off, u16 &data, u16 &mask) {
		const bool hi = e.mask & 0xffff0000u;
		off = (e.addr - base) + (hi ? 0 : 2);
		data = hi ? e.data >> 16 : e.data & 0xffff;
		mask = hi ? e.mask >> 16 : e.mask & 0xffff;
	};

	std::vector<io> theirs;
	// BENCH_PROGRESS: wall time every 2 s of game time, for the rate after start-up
	const bool progress = std::getenv("BENCH_PROGRESS") != nullptr;
	double next_report = t_enable + 2e6;
	int reads = 0, read_bad = 0;
	double t_end = t_enable;
	for (const ev &e : evs)
	{
		t_end = e.us;
		if (!e.main)
		{
			if (e.addr < 0x300) theirs.push_back({ticks(e.us), e.rw, e.addr, e.mask, e.data});
			continue;
		}
		b.run_until(ticks(e.us));
		if (progress && e.us >= next_report)
		{
			const double w = std::chrono::duration<double>(std::chrono::steady_clock::now() - wall0).count();
			std::printf("  at %6.2f s: %6.2f s wall\n", (e.us - t_enable) / 1e6, w);
			next_report += 2e6;
		}
		offs_t off;
		u16 data, mask;
		if (e.addr >= 0x6f000000 && e.addr < 0x6f000004)
		{
			if (e.rw == 'w' && (e.mask & 0xffff0000u)) b.soundcpu_enable_w(e.data >> 16);
		}
		else if (e.addr >= 0x68000000 && e.addr < 0x68000010)
		{
			half(e, 0x68000000, off, data, mask);
			if (e.rw == 'w')
				b.main_comms_w(off, data, mask);
			else
			{
				reads++;
				const u16 got = b.main_comms_r(off) & mask;
				if (got != (data & mask))
				{
					if (read_bad < 40)
						std::printf("main read %08X at %.3f us: MAME %04X, here %04X\n", e.addr, e.us,
							data & mask, got);
					read_bad++;
				}
			}
		}
	}
	b.run_until(ticks(t_end));
	const double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - wall0).count();

#ifdef NEC_PROFILE
	{
		extern uint32_t nec_profile[0x100000];
		std::vector<std::pair<uint32_t, uint32_t>> top;
		for (uint32_t a = 0; a < 0x100000; a++)
			if (nec_profile[a]) top.push_back({nec_profile[a], a});
		std::sort(top.rbegin(), top.rend());
		uint64_t total = 0;
		std::vector<uint64_t> blk(0x1000, 0);
		for (auto &t : top) { total += t.first; blk[t.second >> 8] += t.first; }
		std::printf("  instructions %llu\n", (unsigned long long)total);
		std::vector<std::pair<uint64_t, uint32_t>> tb;
		for (uint32_t i = 0; i < 0x1000; i++) if (blk[i]) tb.push_back({blk[i], i << 8});
		std::sort(tb.rbegin(), tb.rend());
		for (size_t i = 0; i < tb.size() && i < 12; i++)
			std::printf("  block %05X %5.1f%%\n", tb[i].second, 100.0 * tb[i].first / total);
		for (size_t i = 0; i < top.size() && i < 24; i++)
			std::printf("  pc %05X %10u\n", top[i].second, top[i].first);
	}
#endif

	// the V53A's I/O, access by access
	size_t n = std::min(ours.size(), theirs.size()), same = 0;
	while (same < n && ours[same].rw == theirs[same].rw && ours[same].addr == theirs[same].addr &&
	       ours[same].mask == theirs[same].mask && ours[same].data == theirs[same].data)
		same++;
	double dmax = 0, dsum = 0;
	for (size_t i = 0; i < same; i++)
	{
		const double d = double(ours[i].t - theirs[i].t) / 32.0;
		dmax = std::max(dmax, std::fabs(d));
		dsum += d;
	}
	if (std::getenv("BENCH_DRIFT"))
		for (size_t i = 1; i < same; i = i < 100 ? i + 1 : i * 11 / 10)
			std::printf("  drift %7zu %14.3f us %+9.3f us\n", i, theirs[i].t / 32.0,
				(ours[i].t - theirs[i].t) / 32.0);
	std::printf("V53A I/O: MAME %zu accesses, here %zu, the first %zu the same", theirs.size(), ours.size(),
		same);
	if (same) std::printf(" (time here - MAME: mean %.2f us, max |%.2f| us)", dsum / same, dmax);
	std::printf("\n");
	if (same < std::max(ours.size(), theirs.size()))
	{
		const size_t from = same > 5 ? same - 5 : 0;
		for (size_t i = from; i < same + 5; i++)
		{
			auto p = [](const char *who, const std::vector<io> &v, size_t i) {
				if (i < v.size())
					std::printf("  %-4s %6zu %14.3f us %c %04X %04X %04X\n", who, i, v[i].t / 32.0, v[i].rw,
						v[i].addr, v[i].mask, v[i].data);
			};
			p("MAME", theirs, i);
			p("here", ours, i);
		}
	}
	std::printf("main CPU mailbox reads: %d, %d differ\n", reads, read_bad);
	const double emulated = (t_end - t_enable) / 1e6;
	std::printf("emulated %.2f s in %.2f s; V53A busy %.1f%% of its cycles; SCU accesses %u\n", emulated,
		wall, 100.0 * b.m_cycles_run / std::max<s64>(1, b.m_cycles_run + b.m_cycles_halted),
		b.cpu().scu_accesses());

	// the WAV: MAME's speaker routing (hng64_audio)
	l7a1045 &dsp = b.dsp();
	const s64 total = dsp.first() + s64(dsp.m_out.size() / l7a1045::OUTPUTS);
	FILE *w = std::fopen(argv[4], "wb");
	if (!w) { std::fprintf(stderr, "cannot write %s\n", argv[4]); return 1; }
	const u32 bytes = u32(total) * 8;
	std::fwrite("RIFF", 1, 4, w); put32(w, 36 + bytes); std::fwrite("WAVEfmt ", 1, 8, w);
	put32(w, 16); put16(w, 1); put16(w, 4); put32(w, 44100); put32(w, 44100 * 8); put16(w, 8); put16(w, 16);
	std::fwrite("data", 1, 4, w); put32(w, bytes);
	static const int route[4] = { l7a1045::L6028_LEFT, l7a1045::L6028_RIGHT, l7a1045::L6028_OUT7,
		l7a1045::L6028_OUT6 };
	for (s64 i = 0; i < total; i++)
		for (int c = 0; c < 4; c++)
		{
			s32 v = i < dsp.first() ? 0 : dsp.m_out[size_t(i - dsp.first()) * l7a1045::OUTPUTS + route[c]];
			v = std::max(-32768, std::min(32767, v));
			put16(w, u16(v));
		}
	std::fclose(w);
	std::printf("-> %s, %lld samples\n", argv[4], (long long)total);
	return same == theirs.size() && same == ours.size() && read_bad == 0 ? 0 : 1;
}
