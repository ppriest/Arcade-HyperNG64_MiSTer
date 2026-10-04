// license:LGPL-2.1+
// copyright-holders:David Haywood, Angelo Salese, ElSemi, Andrew Gardner
// The hng64 sound board around the V53A and the L7A1045: from MAME src/mame/snk/hng64_a.cpp and
// the sound parts of hng64.cpp (PROVENANCE.md), with the run loop MAME's scheduler gave it.
#pragma once

#include <functional>
#include <memory>
#include <vector>
#include "l7a1045.h"
#include "emu_sched.h"
#include "v53.h"

class sound_board
{
public:
	// rom: the 16 MB l7a1045 region
	explicit sound_board(const u8 *rom);

	// sound RAM as the V53A sees it, byte n at its address n
	u8 *ram() { return m_ram.get(); }

	// the main CPU's side, at the board's current time: 0x6f000000's upper half, and the mailbox
	// at 0x68000000 by byte offset 0-0xe
	void soundcpu_enable_w(u16 cmd);
	void main_comms_w(offs_t offset, u16 data, u16 mem_mask);
	u16 main_comms_r(offs_t offset);

	// machine start and reset at tick t, the V53A held in reset
	void power_on(s64 t);
	// runs the V53A and the timers to tick t
	void run_until(s64 t);
	// The V33 core's clock as the 32 MHz input over div, 1 or 2. MAME runs it at the input (1);
	// a V53A runs its core at half its input (2).
	void set_cpu_divider(int div) { m_div = div; m_div_shift = div == 2; }
	s64 time() const { return m_time; }
	s64 cpu_now() const { return now(); }

	l7a1045 &dsp() { return m_dsp; }
	v53a &cpu() { return m_cpu; }

	// the V53A's I/O writes and reads below 0x300, as the bench logs them
	std::function<void(s64, char, offs_t, u16, u16)> m_io_log;

	// V53A cycles run and halted, for the bench's load figure
	s64 m_cycles_run = 0, m_cycles_halted = 0;

private:
	s64 now() const;
	void timer_armed(s64 t);

	u16 io_r16(offs_t a, u16 mem_mask);
	void io_w16(offs_t a, u16 data, u16 mem_mask);
	void sound_bank_w(offs_t offset, u16 data);
	void set_bank(int i, int entry);

	std::unique_ptr<u8[]> m_ram;
	sched m_sched;
	nec_space m_space;
	v53a m_cpu;
	l7a1045 m_dsp;

	u16 main_latch[2] = {};
	u16 sound_latch[2] = {};

	bool m_running = false;     // RESET released
	int m_div = 1, m_div_shift = 0;
	s64 m_time = 0;
	bool m_in_cpu = false;
	bool m_in_timer = false;
	s64 m_slice_start = 0, m_slice_end = 0;
};
