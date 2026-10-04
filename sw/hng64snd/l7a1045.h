// license:BSD-3-Clause
// copyright-holders:R. Belmont, O. Galibert
// From MAME src/devices/sound/l7a1045_l6028_dsp_a.h (PROVENANCE.md).
#pragma once

#include <functional>
#include <vector>
#include "mame_shim.h"
#include "emu_sched.h"

class l7a1045
{
public:
	enum
	{
		L6028_LEFT = 0,     // left channel of main stereo pair
		L6028_RIGHT,        // right channel of main stereo pair
		L6028_OUT0,         // discrete outputs, numbered according to Akai usage
		L6028_OUT1,
		L6028_OUT2,
		L6028_OUT3,
		L6028_OUT4,
		L6028_OUT5,
		L6028_OUT6,
		L6028_OUT7,
		OUTPUTS
	};

	// rom: the 16 MB sample ROM (AS_IO); drq: the DMA request line
	l7a1045(sched &s, const u8 *rom, std::function<void(int)> drq);
	void reset() { m_key = 0; }

	// the 16-byte register map, as 16-bit handlers at byte offsets 0-0xe
	u16 read(offs_t offset, u16 mem_mask);
	void write(offs_t offset, u16 data, u16 mem_mask);
	uint16_t dma_r16_cb();
	void dma_w16_cb(uint16_t data);

	// the stream up to now: MAME's m_stream->update(). Sample n is at tick n * 320000 / 441,
	// tick 0 being MAME's time 0; m_lim, (m_next + 1) * 320000, is compared with now * 441 so the
	// ARM, which has no divide instruction, needs none.
	void update();
	// the samples made so far, OUTPUTS a sample, from sample index first()
	std::vector<s32> m_out;
	s64 first() const { return m_first; }
	void discard() { m_first = m_next; m_out.clear(); }
	void set_start(s64 tick) { m_next = m_first = tick * 441 / 320000; m_lim = (m_next + 1) * 320000; }

private:
	static const int NUM_VOICES = 32;
	static const int REGS_PER_VOICE = 16;

	struct l7a1045_voice
	{
		uint32_t loop_start = 0;
		uint32_t start = 0;
		uint32_t end = 0;
		uint32_t step = 0;
		uint32_t pos = 0;
		uint32_t frac = 0;
		uint16_t l_volume = 0;
		uint16_t r_volume = 0;
		uint16_t env_volume = 0;
		uint16_t env_target = 0;
		uint16_t env_step = 0;
		uint32_t env_pos = 0;
		uint16_t flt_freq = 0;
		uint16_t flt_target = 0;
		uint16_t flt_step = 0;
		uint32_t flt_pos = 0;
		uint8_t flt_resonance = 0;
		int32_t b = 0, l = 0; // filter state
		uint8_t send_dest = 0;
		uint8_t send_level = 0;
		uint8_t sample_type = 0; // 0 = 16-bit, 1 = 12-bit non-linear
	};

	void sound_stream_update(s64 from, int samples);
	void voice_select_w(offs_t offset, uint16_t data, uint16_t mem_mask);
	uint16_t voiceregs_r(offs_t offset);
	void voiceregs_w(offs_t offset, uint16_t data);
	uint16_t control_r();
	void control_w(uint16_t data);
	void atomic_w(uint16_t data);
	void recalc_loop_start(l7a1045_voice *vptr);
	void dma_timer_callback();

	// AS_DATA: 128 KB of RAM, reads above it 0; AS_IO: the sample ROM. Both 16-bit
	// little-endian, 25 address bits.
	uint16_t ram_read_word(offs_t a) const { a &= 0x1fffffe; return a < 0x20000 ? m_ram[a >> 1] : 0; }
	void ram_write_word(offs_t a, uint16_t d) { a &= 0x1fffffe; if (a < 0x20000) m_ram[a >> 1] = d; }
	uint8_t rom_read_byte(offs_t a) const { a &= 0x1ffffff; return a < 0x1000000 ? m_rom[a] : 0; }
	uint16_t rom_read_word(offs_t a) const { a &= 0x1fffffe; return a < 0x1000000 ? m_rom[a] | (m_rom[a + 1] << 8) : 0; }

	sched &m_sched;
	const u8 *m_rom;
	std::vector<uint16_t> m_ram;
	std::function<void(int)> m_drq_handler;

	l7a1045_voice   m_voice[NUM_VOICES];
	uint32_t        m_key = 0;
	uint16_t        m_control = 0;
	emu_timer       m_dma_timer;
	// the next request: tick m_dma_tick plus m_dma_rem / 1323
	s64             m_dma_tick = 0;
	s64             m_dma_rem = 0;

	uint8_t m_cur_channel = 0;
	uint8_t m_cur_register = 0;

	uint64_t m_regs[REGS_PER_VOICE][NUM_VOICES] = {};

	s64 m_next = 0;       // the next sample to make
	s64 m_lim = 320000;
	s64 m_first = 0;
};
