// SPDX-License-Identifier: GPL-3.0-or-later
// hng64snd: the hng64 sound board on the MiSTer's ARM (docs/ROADMAP.md Phase 4).
//
// Started by games/<set>/_handler.sh while an HNG64 set is loaded. It shares a block of DDR3 with
// the core's hng64_sndbridge (rtl/hng64_sndbridge.sv has the layout): the main CPU's latches,
// interrupt-5 writes and sound CPU enables come in, the sound CPU's two latches and a heartbeat go
// out. At each enable it copies sound RAM and the sample ROM from DDR3 and starts the V53A, at
// 16 MHz (docs/MAME_KLUDGES.md), and the L7A1045. Its output goes to /dev/MrAudio, the framework's
// ALSA path, at 48 kHz, kept a fixed depth ahead of the FPGA's playback: the game's speed never
// reaches the pitch, and time the ARM falls behind is a gap, not a delay. It goes quiet at every
// core load (the bridge's count stopping, or /tmp/CORENAME rewritten) until a set's bridge has reset,
// and one copy runs at a time.

#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/stat.h>
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
constexpr uint32_t OFF_SMP = 0x08, OFF_MBOX = 0x10, OFF_RUN = 0x18, OFF_BEAT = 0x20, OFF_STATUS = 0x40,
                   OFF_RAM = 0x10000;

constexpr s64 TICKS_PER_MS = 32000;              // the board's 32 MHz ticks
constexpr int OUT_RATE = 48000;
// sys/alsa.sv plays its buffer at 48 kHz, faster (at most 0.53%) only past 16 KB, 85 ms, and holds
// the last sample when it is empty. /dev/MrAudio takes all it is given (LESSONS_LEARNED), so the
// buffer's level is modelled: frames written less those played since. The model plays 0.02% fast,
// so a slower FPGA clock leaves the real level above it, where alsa.sv's speed-up holds it, not
// below, where it would run dry.
constexpr double LEAD_FRAMES = OUT_RATE * 0.080;
constexpr double PLAY_PER_NS = OUT_RATE * 1.0002 / 1e9;
const char *const SETS[] = {"sams64", "sams64_2", "fatfurwa", "buriki", "roadedge", "xrally", "bbust2"};

volatile sig_atomic_t g_stop = 0;
void on_signal(int) { g_stop = 1; }

int64_t cpu_ns()
{
	timespec ts;
	clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts);
	return int64_t(ts.tv_sec) * 1'000'000'000 + ts.tv_nsec;
}

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

// Main_MiSTer's /tmp/CORENAME: whether it names a set, and when it was written, which it is at
// every core load (one set straight to another, or the same again, included). Without MiSTer
// Frontier's daemon nothing else stops this process when the core changes, and DDR3 keeps the
// bridge's block.
struct core_name
{
	bool ours = false;
	int64_t written = -1;
};

core_name read_core_name()
{
	core_name c;
	struct stat st;
	if (stat("/tmp/CORENAME", &st) != 0) return c;
	c.written = int64_t(st.st_mtim.tv_sec) * 1'000'000'000 + st.st_mtim.tv_nsec;
	char name[64] = {};
	FILE *f = fopen("/tmp/CORENAME", "r");
	if (!f) return c;
	const size_t n = fread(name, 1, sizeof name - 1, f);
	fclose(f);
	name[n] = 0;
	name[strcspn(name, "\r\n")] = 0;
	for (const char *s : SETS)
		if (!strcmp(name, s)) c.ours = true;
	return c;
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

	// -watch <seconds>: print the FPGA's words as they change, touching nothing
	if (argc > 2 && !strcmp(argv[1], "-watch"))
	{
		const int64_t end = now_ns() + int64_t(atoi(argv[2])) * 1'000'000'000;
		uint64_t last[4] = {~0ull, ~0ull, ~0ull, ~0ull};
		const uint32_t offs[4] = {0, OFF_MBOX, OFF_RUN, OFF_STATUS};
		const int64_t t0 = now_ns();
		while (now_ns() < end)
		{
			for (int i = 0; i < 4; i++)
			{
				const uint64_t v = sh.read64(offs[i]);
				if (v != last[i] && (i != 3 || (v & 0xffffffffffffull) != (last[i] & 0xffffffffffffull)))
					printf("%8.3f s  +%02x  %016llx\n", (now_ns() - t0) / 1e9, offs[i], (unsigned long long)v);
				last[i] = v;
			}
			sleep_ns(200'000);
		}
		return 0;
	}

	// -dump <file>: the shared block as it stands, for a look from the host
	if (argc > 2 && !strcmp(argv[1], "-dump"))
	{
		std::vector<uint8_t> b(SHM_SIZE);
		copy_in(b.data(), sh.bytes(0), SHM_SIZE);
		FILE *f = fopen(argv[2], "wb");
		if (!f) { perror(argv[2]); return 1; }
		fwrite(b.data(), 1, b.size(), f);
		fclose(f);
		return 0;
	}

	// one copy: two writing /dev/MrAudio interleave
	const int lock = open("/tmp/hng64snd.lock", O_RDWR | O_CREAT, 0644);
	if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0)
	{
		fprintf(stderr, "hng64snd: another copy is running\n");
		return 1;
	}

	// ahead of the daemons, not of the system: a real-time priority, once the process fell
	// behind, starved Main_MiSTer and sshd. Core 0: Main_MiSTer's main thread is pinned to core 1
	// and takes most of it.
	if (setpriority(PRIO_PROCESS, 0, -10) != 0) perror("setpriority");
	cpu_set_t cpus;
	CPU_ZERO(&cpus);
	CPU_SET(0, &cpus);
	if (sched_setaffinity(0, sizeof cpus, &cpus) != 0) perror("sched_setaffinity");

	// Held only while a set's sound runs, so the process can stay resident (README, Sound) in
	// under 1 MB: the sample ROM's copy, the board, and the audio device, which never waits (what it
	// cannot take is dropped).
	std::vector<u8> samples;
	std::unique_ptr<sound_board> board;
	int audio = -1;
	resampler rs;
	std::vector<int16_t> pcm;
	uint16_t heartbeat = 0, last_en = 0, last_irq = 0, main0 = 0, main1 = 0;
	int beat_seen = -1;                          // the bridge's count at +0x20, -1 none yet
	int64_t beat_t = 0;                          // when it last moved
	bool running = false;
	// Interrupt 5 is held back until the V53A has written its status latch once: one raised
	// while it initialises its ICU is cleared by ICW1 in edge mode with the line left high, and
	// no later raise is an edge again (docs/HACKS.md). The game retries.
	bool v53_ready = false;
	// left: a core was loaded since the block was written, so it is stale until the bridge writes
	// it again (run 0)
	core_name cname = read_core_name();
	bool left = false;
	int64_t name_t = now_ns();
	double level = 0;                // alsa.sv's buffer, modelled, in frames
	int64_t level_t = now_ns();
	int16_t last_l = 0, last_r = 0;
	// -v's report every 5 s: interrupts taken, output RMS, time spent emulating, the buffer's gaps
	int64_t rep_t = now_ns(), busy_ns = 0, rep_cpu = cpu_ns(), rep_gap_ns = 0;
	uint32_t rep_irqs = 0, rep_gaps = 0;
	double rep_sq_l = 0, rep_sq_r = 0;
	uint64_t rep_frames = 0;
	const bool verbose = argc > 1 && !strcmp(argv[1], "-v");

	// the model's level after what alsa.sv has played since it was last taken; an empty buffer
	// while the sound CPU runs is a gap
	auto drain = [&] {
		const int64_t t = now_ns();
		const double played = (t - level_t) * PLAY_PER_NS;
		if (running && played > level)
		{
			if (level > 0) rep_gaps++;
			rep_gap_ns += int64_t((played - level) / PLAY_PER_NS);
		}
		level = std::max(0.0, level - played);
		level_t = t;
	};
	// written 5 ms at a time (now: at once): a write a millisecond took CPU the emulation needs
	std::vector<int16_t> outq;
	auto put = [&](const std::vector<int16_t> &pcm, bool now) {
		if (pcm.empty()) return;
		outq.insert(outq.end(), pcm.begin(), pcm.end());
		last_l = pcm[pcm.size() - 2];
		last_r = pcm[pcm.size() - 1];
		if (!now && outq.size() < 2 * 240) return;
		const ssize_t n = audio < 0 ? 0 : write(audio, outq.data(), outq.size() * sizeof(int16_t));
		if (n < 0) perror("MrAudio");
		else level += double(n / 4);
		outq.clear();
	};
	// stopped: 5 ms down to 0 from the last sample, which alsa.sv would otherwise hold
	auto fade = [&] {
		std::vector<int16_t> f;
		for (int i = 1; i <= 240; i++)
		{
			f.push_back(int16_t(last_l * (240 - i) / 240));
			f.push_back(int16_t(last_r * (240 - i) / 240));
		}
		put(f, true);
	};
	auto stop = [&](const char *why) {
		if (!running) return;
		running = false;
		board.reset();
		std::vector<u8>().swap(samples);
		fade();
		if (audio >= 0) close(audio);
		audio = -1;
		if (verbose) fprintf(stderr, "hng64snd: %s\n", why);
	};

	auto publish = [&] {
		uint32_t lo = 0;
		if (running) lo = board->main_comms_r(4) | uint32_t(board->main_comms_r(6)) << 16;
		sh.write32(OFF_STATUS, lo);
		sh.write32(OFF_STATUS + 4, uint32_t(heartbeat++) << 16 | 0xA500u | (running ? 1u : 0u));
	};

	while (!g_stop)
	{
		if (now_ns() - name_t >= 250'000'000)
		{
			name_t = now_ns();
			const core_name c = read_core_name();
			if (c.written != cname.written || c.ours != cname.ours)
			{
				stop("a core was loaded");
				left = true;
			}
			cname = c;
		}
		// nothing is ours to read or write until a set is loaded and the bridge has written its
		// magic: DDR3 keeps whatever an earlier core left there
		const uint64_t magic = sh.read64(0);
		if (!cname.ours || uint32_t(magic) != 0x53474E48u)    // "HNGS"
		{
			stop("the bridge's magic is gone");
			beat_seen = -1;
			sleep_ns(100'000'000);
			continue;
		}
		// from version 2 the bridge counts every 10 ms while the core runs: stopped for 200 ms, the
		// FPGA is being loaded, or a set's ROMs (the core held in reset), well before /tmp/CORENAME
		// changes, so the sound goes too, and waits for the sound CPU to be held as at a core load
		if ((magic >> 32) >= 2)
		{
			const int b = int(uint16_t(sh.read64(OFF_BEAT)));
			const int64_t t = now_ns();
			if (b != beat_seen)
			{
				beat_seen = b;
				beat_t = t;
			}
			else if (t - beat_t >= 200'000'000)
			{
				stop("the core stopped");
				left = true;
				sleep_ns(20'000'000);
				continue;
			}
		}
		const uint64_t mbox = sh.read64(OFF_MBOX);
		const bool run = sh.read64(OFF_RUN) & 1;
		const uint16_t irq = mbox >> 32, en = mbox >> 48;

		if (!run)
		{
			left = false;
			stop("sound CPU held");
		}
		if (run && !left && (!running || en != last_en))
		{
			// a 0x55AA: sound RAM and the samples as they are now, and the V53A from reset
			const uint64_t smp = sh.read64(OFF_SMP);
			const uint32_t smp_base = uint32_t(smp), smp_size = uint32_t(smp >> 32);
			samples.assign(0x1000000, 0);
			if (audio < 0)
			{
				audio = open("/dev/MrAudio", O_WRONLY | O_NONBLOCK);
				if (audio < 0) perror("/dev/MrAudio");
			}
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
			v53_ready = false;
			last_en = en;
			last_irq = irq;
			main0 = main1 = 0;
			rs = resampler{};
			if (verbose) fprintf(stderr, "hng64snd: sound CPU started (enable %u, samples %u bytes at %08x)\n",
				en, smp_size, smp_base);
		}

		drain();
		if (running)
		{
			// the buffer filled to LEAD, a millisecond at a time with the mailbox between; the
			// loop sleeps at least every 20 ms
			const int64_t loop_end = now_ns() + 20'000'000;
			while (level + outq.size() / 2 < LEAD_FRAMES && !g_stop && now_ns() < loop_end)
			{
				const uint64_t mb = sh.read64(OFF_MBOX);
				const uint16_t a0 = mb, a1 = mb >> 16, ai = mb >> 32;
				if (a0 != main0) { board->main_comms_w(0, a0, 0xffff); main0 = a0; }
				if (a1 != main1) { board->main_comms_w(2, a1, 0xffff); main1 = a1; }
				if (!v53_ready && board->main_comms_r(6) != 0) v53_ready = true;
				if (ai != last_irq)
				{
					if (v53_ready) board->main_comms_w(8, 1, 0xffff);
					last_irq = ai;
					rep_irqs++;
				}

				const int64_t t0 = now_ns();
				board->run_until(board->time() + TICKS_PER_MS);
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
				put(pcm, false);
				publish();
				drain();
			}
		}
		else
			publish();
		if (verbose && now_ns() - rep_t >= 5'000'000'000)
		{
			const double span = double(now_ns() - rep_t);
			fprintf(stderr, "hng64snd: %s, %u interrupts, enables %u, RMS %.0f/%.0f, busy %.0f%% (CPU %.0f%%), %u gaps (%.0f ms)",
				running ? "running" : "idle", rep_irqs, last_en,
				rep_frames ? std::sqrt(rep_sq_l / rep_frames) : 0.0,
				rep_frames ? std::sqrt(rep_sq_r / rep_frames) : 0.0, 100.0 * busy_ns / span,
				100.0 * (cpu_ns() - rep_cpu) / span, rep_gaps, rep_gap_ns / 1e6);
			rep_cpu = cpu_ns();
			if (running)
				fprintf(stderr, "; V53A pc %05x IF %d pending %x, ICU imr/irr/isr/lines %08x, latches %04x %04x",
					board->cpu().pc(), board->cpu().iflag(), board->cpu().pending(), board->cpu().icu_state(),
					board->main_comms_r(4), board->main_comms_r(6));
			fprintf(stderr, "\n");
			rep_t = now_ns();
			busy_ns = 0; rep_irqs = 0; rep_gaps = 0; rep_gap_ns = 0; rep_sq_l = rep_sq_r = 0; rep_frames = 0;
		}
		// behind, straight on; the 20 ms cap is only for the checks above
		if (!running || level + outq.size() / 2 >= LEAD_FRAMES) sleep_ns(1'000'000);
	}

	stop("stopped");
	publish();
	return 0;
}
