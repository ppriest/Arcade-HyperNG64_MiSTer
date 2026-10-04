// license:LGPL-2.1+
// copyright-holders:David Haywood, Angelo Salese, ElSemi, Andrew Gardner
// From MAME src/mame/snk/hng64_a.cpp and hng64.cpp (PROVENANCE.md); see board.h.

#include "board.h"
#include <cstdarg>
#include <cstdlib>

static bool s_log = std::getenv("HNG64SND_LOG") != nullptr;

void logerror(const char *fmt, ...)
{
	if (!s_log) return;
	va_list ap;
	va_start(ap, fmt);
	std::vfprintf(stderr, fmt, ap);
	va_end(ap);
}

#define COMBINE_DATA(varptr) (*(varptr) = (*(varptr) & ~mem_mask) | (data & mem_mask))

sound_board::sound_board(const u8 *rom)
	: m_ram(new u8[0x200000]())
	, m_cpu(m_space, m_sched, v53_board{
		[this](offs_t a, u16 m) { return io_r16(a, m); },
		[this](offs_t a, u16 d, u16 m) { io_w16(a, d, m); },
		// tcu_tm0_cb and tcu_tm1_cb do nothing; TOUT2 is INT2
		[this](int n, int st) { if (n == 2) m_cpu.set_input(2, st ? ASSERT_LINE : CLEAR_LINE); },
		dmau_bus{
			// dma_hreq_cb: the bus is granted at once, whatever the request
			[this](int) { m_cpu.hack_w(1); },
			// dma_memr_cb: the program space, unbanked addresses
			[this](offs_t a) -> u8 { return m_space.read_byte(a); },
			[this](int ch, offs_t) -> u16 { return ch == 3 ? m_dsp.dma_r16_cb() : 0; },
			[this](int ch, offs_t, u16 d) { if (ch == 3) m_dsp.dma_w16_cb(d); },
		}})
	, m_dsp(m_sched, rom, [this](int st) { m_cpu.dreq_w(3, st); })
{
	m_sched.m_now = [this] { return now(); };
	m_sched.m_armed = [this](s64 t) { timer_armed(t); };
}

void sound_board::power_on(s64 t)
{
	m_time = t;
	m_dsp.set_start(t);
	m_cpu.start();
	// reset_sound: every bank on 0x1f, the CPU held in reset
	for (int i = 0; i < 16; i++) set_bank(i, 0x1f);
	m_cpu.reset();
	m_dsp.reset();
	m_running = false;
}

s64 sound_board::now() const
{
	if (m_in_timer) return m_sched.m_firing;
	if (m_in_cpu) return m_slice_start + s64(m_cpu.cycles_run()) * m_div;
	return m_time;
}

// a timer armed inside the slice ends it after this instruction: abort_timeslice
void sound_board::timer_armed(s64 t)
{
	if (m_in_cpu && t < m_slice_end)
		m_cpu.abort_slice();
}

void sound_board::set_bank(int i, int entry)
{
	m_space.bank[i] = m_ram.get() + (entry & 0x1f) * 0x10000;
}

void sound_board::soundcpu_enable_w(u16 cmd)
{
	// I guess it's only one of the bits, the commands are inverse of each other
	if (cmd == 0x55AA)
	{
		if (!m_running)
		{
			// the RESET line's release resets the device and its children
			m_cpu.reset();
			m_running = true;
		}
	}
	else if (cmd == 0xAA55)
	{
		m_running = false;
	}
}

void sound_board::main_comms_w(offs_t offset, u16 data, u16 mem_mask)
{
	switch (offset)
	{
		case 0x00:
			COMBINE_DATA(&main_latch[0]);
			break;
		case 0x02:
			COMBINE_DATA(&main_latch[1]);
			break;
		case 0x08:
			if (data & 1)
				m_cpu.set_input(5, ASSERT_LINE);
			break;
	}
}

u16 sound_board::main_comms_r(offs_t offset)
{
	switch (offset)
	{
		case 0x00: return main_latch[0];
		case 0x02: return main_latch[1];
		case 0x04: return sound_latch[0];
		case 0x06: return sound_latch[1];
	}
	return 0;
}

// ---- the V53A's I/O map (sound_io_map) ----------------------------------------------------------

u16 sound_board::io_r16(offs_t a, u16 mem_mask)
{
	u16 data = 0;
	if (a < 0x10)
		data = m_dsp.read(a, mem_mask);
	else if (a >= 0x100 && a < 0x110)
	{
		switch (a - 0x100)
		{
			case 0x00: data = sound_latch[0]; break;
			case 0x02: data = sound_latch[1]; break;
			case 0x04: data = main_latch[0]; break;
			case 0x06: data = main_latch[1]; break;
		}
	}
	if (m_io_log && a < 0x300) m_io_log(now(), 'r', a, mem_mask, data & mem_mask);
	return data;
}

void sound_board::io_w16(offs_t a, u16 data, u16 mem_mask)
{
	if (m_io_log && a < 0x300) m_io_log(now(), 'w', a, mem_mask, data & mem_mask);

	if (a < 0x10)
		m_dsp.write(a, data, mem_mask);
	else if (a >= 0x100 && a < 0x110)
	{
		switch (a - 0x100)
		{
			// Data to main CPU
			case 0x0:
				COMBINE_DATA(&sound_latch[0]);
				return;
			// Latch status to main CPU
			case 0x2:
				COMBINE_DATA(&sound_latch[1]);
				return;
			case 0xa:
				m_cpu.set_input(5, CLEAR_LINE);
				return;
		}
	}
	else if (a >= 0x200 && a < 0x220)
		sound_bank_w((a - 0x200) >> 1, data);
	// 0x80: sound_port_0080_w, which only logs
}

void sound_board::sound_bank_w(offs_t offset, u16 data)
{
	// buriki writes 0x3f to 0x200 before jumping to the low addresses..
	// where it expects to find data from 0x1f0000
	set_bank(offset & 0xf, data & 0x1f);
}

// ---- the run loop ------------------------------------------------------------------------------------

void sound_board::run_until(s64 t)
{
	while (m_time < t)
	{
		const s64 next = std::min(t, m_sched.next_event());
		if (next > m_time)
		{
			if (m_running)
			{
				m_slice_start = m_time;
				m_slice_end = next;
				m_in_cpu = true;
				const bool halted = m_cpu.halted();
				const s64 cycles = (std::min<s64>(next - m_time, 1 << 30) + m_div - 1) >> m_div_shift;
				const s64 used = s64(m_cpu.execute_run(int(cycles))) * m_div;
				m_in_cpu = false;
				m_time += used;
				(halted ? m_cycles_halted : m_cycles_run) += used;
			}
			else
				m_time = next;
		}
		m_in_timer = true;
		while (m_sched.fire_one(m_time)) {}
		m_in_timer = false;
	}
	m_dsp.update();
}
