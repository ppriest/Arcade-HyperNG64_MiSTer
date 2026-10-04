// SPDX-License-Identifier: GPL-3.0-or-later
// hng64snd: the hng64 sound board on the MiSTer's ARM (docs/ROADMAP.md Phase 4).
//
// Started by games/<set>/_handler.sh while an HNG64 set is loaded. It shares a block of DDR3 with
// the core's hng64_sndbridge (rtl/hng64_sndbridge.sv has the layout): the main CPU's latches,
// interrupt-5 writes and sound CPU enables come in, the sound CPU's two latches and a heartbeat go
// out. At each enable it copies sound RAM and the sample ROM from DDR3 and starts the V53A, at
// 16 MHz (docs/MAME_KLUDGES.md), and the L7A1045. Its output goes to /dev/MrAudio, the framework's
// ALSA path, at 48 kHz, made against CLOCK_MONOTONIC: the game's speed never reaches the pitch.

#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>

#include "board.h"

namespace {

constexpr uint32_t DDR3_BASE = 0x30000000;      // the core's window
constexpr uint32_t SHM = 0x0F200000;            // hng64_sndbridge's SHM
constexpr uint32_t SHM_SIZE = 0x210000;
constexpr uint32_t OFF_SMP = 0x08, OFF_MBOX = 0x10, OFF_RUN = 0x18, OFF_STATUS = 0x40,
                   OFF_RAM = 0x10000;

constexpr s64 TICKS_PER_MS = 32000;              // the board's 32 MHz ticks
constexpr int64_t LEAD_NS = 40'000'000;          // audio made this far ahead of the clock
constexpr int OUT_RATE = 48000;

volatile sig_atomic_t g_stop = 0;
void on_signal(int) { g_stop = 1; }

int64_t now_ns()
{
	timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return int64_t(ts.tv_sec) * 1'000'000'000 + ts.tv_nsec;
}

void sleep_ns(int64_t ns)
{
	timespec ts{time_t(ns / 1'000'000'000), long(ns % 1'000'000'000)};
	nanosleep(&ts, nullptr);
}

// The shared block, uncached. The FPGA writes whole 64-bit words; a 32-bit read of a word's two
// halves can straddle its update, so a word is read until two reads agree.
struct shared
{
	volatile uint32_t *w = nullptr;

	uint64_t read64(uint32_t off) const
	{
		for (;;)
		{
			const uint32_t lo = w[off / 4], hi = w[off / 4 + 1];
			if (w[off / 4] == lo && w[off / 4 + 1] == hi) return uint64_t(hi) << 32 | lo;
		}
	}
	void write32(uint32_t off, uint32_t v) { w[off / 4] = v; }
	const volatile uint8_t *bytes(uint32_t off) const { return reinterpret_cast<const volatile uint8_t *>(w) + off; }
};

void copy_in(void *dst, const volatile uint8_t *src, size_t n)
{
	// 32-bit loads: the mapping is device memory, which takes no unaligned or wider access well
	auto *d = static_cast<uint32_t *>(dst);
	auto *s = reinterpret_cast<const volatile uint32_t *>(src);
	for (size_t i = 0; i < n / 4; i++) d[i] = s[i];
}

// 44.1 kHz to 48 kHz, linear between neighbours
struct resampler
{
	double phase = 0.0;              // position of the next output, in input samples past `prev`
	s32 prev_l = 0, prev_r = 0;

	void run(const std::vector<s32> &in, size_t frames, int stride, std::vector<int16_t> &out)
	{
		constexpr double step = 44100.0 / OUT_RATE;
		for (size_t i = 0; i < frames; i++)
		{
			const s32 l = in[i * stride + l7a1045::L6028_LEFT];
			const s32 r = in[i * stride + l7a1045::L6028_RIGHT];
			while (phase < 1.0)
			{
				const double a = prev_l + (l - prev_l) * phase;
				const double b = prev_r + (r - prev_r) * phase;
				out.push_back(int16_t(std::max(-32768.0, std::min(32767.0, a))));
				out.push_back(int16_t(std::max(-32768.0, std::min(32767.0, b))));
				phase += step;
			}
			phase -= 1.0;
			prev_l = l;
			prev_r = r;
		}
	}
};

}  // namespace

int main(int argc, char **argv)
{
	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);

	const int mem = open("/dev/mem", O_RDWR | O_SYNC);
	if (mem < 0) { perror("/dev/mem"); return 1; }
	void *p = mmap(nullptr, SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, mem, DDR3_BASE + SHM);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	shared sh{static_cast<volatile uint32_t *>(p)};

	const int audio = open("/dev/MrAudio", O_WRONLY);
	if (audio < 0) { perror("/dev/MrAudio"); return 1; }

	// a core of its own: the board runs about two thirds of one at 16 MHz
	sched_param sp{};
	sp.sched_priority = 50;
	if (sched_setscheduler(0, SCHED_FIFO, &sp) != 0) perror("SCHED_FIFO (running without)");

	std::vector<u8> samples(0x1000000, 0);
	std::unique_ptr<sound_board> board;
	resampler rs;
	std::vector<int16_t> pcm;
	uint16_t heartbeat = 0, last_en = 0, last_irq = 0, main0 = 0, main1 = 0;
	bool running = false;
	int64_t wall0 = 0;
	// -v's report every 5 s: interrupts taken, output RMS, time spent emulating
	int64_t rep_t = now_ns(), busy_ns = 0;
	uint32_t rep_irqs = 0;
	double rep_sq_l = 0, rep_sq_r = 0;
	uint64_t rep_frames = 0;
	const bool verbose = argc > 1 && !strcmp(argv[1], "-v");

	auto publish = [&] {
		uint32_t lo = 0;
		if (running) lo = board->main_comms_r(4) | uint32_t(board->main_comms_r(6)) << 16;
		sh.write32(OFF_STATUS, lo);
		sh.write32(OFF_STATUS + 4, uint32_t(heartbeat++) << 16 | 0xA500u | (running ? 1u : 0u));
	};

	while (!g_stop)
	{
		// nothing is ours to read or write until the bridge has written its magic: DDR3 keeps
		// whatever an earlier core left there
		if (uint32_t(sh.read64(0)) != 0x53474E48u)    // "HNGS"
		{
			if (running && verbose) fprintf(stderr, "hng64snd: the bridge's magic is gone\n");
			running = false;
			board.reset();
			sleep_ns(100'000'000);
			continue;
		}
		const uint64_t mbox = sh.read64(OFF_MBOX);
		const bool run = sh.read64(OFF_RUN) & 1;
		const uint16_t irq = mbox >> 32, en = mbox >> 48;

		if (running && !run)
		{
			running = false;
			board.reset();
			if (verbose) fprintf(stderr, "hng64snd: sound CPU held\n");
		}
		if (run && (!running || en != last_en))
		{
			// a 0x55AA: sound RAM and the samples as they are now, and the V53A from reset
			const uint64_t smp = sh.read64(OFF_SMP);
			const uint32_t smp_base = uint32_t(smp), smp_size = uint32_t(smp >> 32);
			std::fill(samples.begin(), samples.end(), 0);
			if (smp_size)
			{
				const uint32_t n = std::min<uint32_t>(smp_size, 0x1000000);
				void *s = mmap(nullptr, n, PROT_READ, MAP_SHARED, mem, DDR3_BASE + smp_base);
				if (s != MAP_FAILED)
				{
					copy_in(samples.data(), static_cast<const volatile uint8_t *>(s), n);
					munmap(s, n);
				}
			}
			board = std::make_unique<sound_board>(samples.data());
			board->set_cpu_divider(2);
			copy_in(board->ram(), sh.bytes(OFF_RAM), 0x200000);
			board->power_on(0);
			board->soundcpu_enable_w(0x55AA);
			running = true;
			last_en = en;
			last_irq = irq;
			main0 = main1 = 0;
			rs = resampler{};
			wall0 = now_ns();
			if (verbose) fprintf(stderr, "hng64snd: sound CPU started (enable %u, samples %u bytes at %08x)\n",
				en, smp_size, smp_base);
		}

		if (running)
		{
			// up to LEAD ahead of the clock, a millisecond at a time with the mailbox between
			const s64 target = (now_ns() - wall0 + LEAD_NS) * 32 / 1000;
			while (board->time() < target && !g_stop)
			{
				const uint64_t mb = sh.read64(OFF_MBOX);
				const uint16_t a0 = mb, a1 = mb >> 16, ai = mb >> 32;
				if (a0 != main0) { board->main_comms_w(0, a0, 0xffff); main0 = a0; }
				if (a1 != main1) { board->main_comms_w(2, a1, 0xffff); main1 = a1; }
				if (ai != last_irq) { board->main_comms_w(8, 1, 0xffff); last_irq = ai; rep_irqs++; }

				const int64_t t0 = now_ns();
				board->run_until(std::min(board->time() + TICKS_PER_MS, target));
				busy_ns += now_ns() - t0;

				l7a1045 &dsp = board->dsp();
				const size_t frames = dsp.m_out.size() / l7a1045::OUTPUTS;
				pcm.clear();
				rs.run(dsp.m_out, frames, l7a1045::OUTPUTS, pcm);
				dsp.discard();
				for (size_t i = 0; i + 1 < pcm.size(); i += 2)
				{
					rep_sq_l += double(pcm[i]) * pcm[i];
					rep_sq_r += double(pcm[i + 1]) * pcm[i + 1];
				}
				rep_frames += pcm.size() / 2;
				if (!pcm.empty())
					if (write(audio, pcm.data(), pcm.size() * sizeof(int16_t)) < 0) perror("MrAudio");
				publish();
			}
		}
		else
			publish();
		if (verbose && now_ns() - rep_t >= 5'000'000'000)
		{
			const double span = double(now_ns() - rep_t);
			fprintf(stderr, "hng64snd: %s, %u interrupts, enables %u, RMS %.0f/%.0f, busy %.0f%%\n",
				running ? "running" : "idle", rep_irqs, last_en,
				rep_frames ? std::sqrt(rep_sq_l / rep_frames) : 0.0,
				rep_frames ? std::sqrt(rep_sq_r / rep_frames) : 0.0, 100.0 * busy_ns / span);
			rep_t = now_ns();
			busy_ns = 0; rep_irqs = 0; rep_sq_l = rep_sq_r = 0; rep_frames = 0;
		}
		sleep_ns(1'000'000);
	}

	running = false;
	publish();
	return 0;
}
