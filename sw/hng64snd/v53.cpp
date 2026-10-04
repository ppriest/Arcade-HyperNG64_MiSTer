// license:BSD-3-Clause
// copyright-holders:Patrick Mackinlay, Wilbert Pol, Nathan Woods, Curt Coder
// From MAME (PROVENANCE.md); see v53.h. MAME's attotime becomes ticks of the 32 MHz clock,
// machine().time() the scheduler's now(), and side_effects_disabled() is always false.

#include "v53.h"

// ============================================================================================
// TCU: pit8253.cpp, the 8254
// ============================================================================================

#define CTRL_ACCESS(control)        (((control) >> 4) & 0x03)
#define CTRL_MODE(control)          (((control) >> 1) & (((control) & 0x04) ? 0x03 : 0x07))
#define CTRL_BCD(control)           (((control) >> 0) & 0x01)

pit_counter::pit_counter(sched &s, int index, std::function<void(int)> out)
	: m_sched(s), m_index(index), m_out(std::move(out)), m_update_timer(s, [this] { update(); })
{
}

void pit_counter::start()
{
	adjust_timer(NEVER);

	/* zerofill */
	m_gate = 1;
	m_gate_input = 1;
	m_gate_rose = 0;
	m_phase = 0;

	m_control = m_status = 0x30;
	m_rmsb = m_wmsb = false;
	m_count = m_value = m_latch = 0;
	m_lowcount = 0;

	m_output = 0;
	m_output_pin = 0;
	m_latched_count = 0;
	m_latched_status = 0;
	m_null_count = 1;

	m_last_updated = m_sched.now();
}

void pit_counter::reset()
{
	/* According to Intel's 8254 docs, the state of a timer is undefined
	 until the first mode control word is written. Here we define this
	 undefined behaviour */
	m_control = m_status = 0x30;
	m_rmsb = m_wmsb = false;
	m_count = m_value = m_latch = 0;
	m_lowcount = 0;

	m_output = 2; /* output is undetermined */
	m_output_pin = 2;
	m_latched_count = 0;
	m_latched_status = 0;
	m_null_count = 1;

	m_last_updated = m_sched.now();

	update();
}

void pit_counter::adjust_timer(s64 target)
{
	m_next_update = target;
	m_update_timer.adjust_at(target);
}

uint32_t pit_counter::adjusted_count() const
{
	uint16_t val = m_value;

	if (!CTRL_BCD(m_control))
		return (val == 0) ? 0x10000 : val;
	else if (val == 0)
		return 10000;

	return
		((val>>12) & 0xF) *  1000 +
		((val>> 8) & 0xF) *   100 +
		((val>> 4) & 0xF) *    10 +
		( val      & 0xF);
}

/* This function subtracts 1 from m_value "cycles" times, taking into
   account binary or BCD operation, and wrapping around from 0 to 0xFFFF or
   0x9999 as necessary. */
void pit_counter::decrease_counter_value(int64_t cycles)
{
	if (CTRL_BCD(m_control) == 0)
	{
		m_value -= (cycles & 0xffff);
		return;
	}

	uint8_t units     =  m_value        & 0xf;
	uint8_t tens      = (m_value >>  4) & 0xf;
	uint8_t hundreds  = (m_value >>  8) & 0xf;
	uint8_t thousands = (m_value >> 12) & 0xf;

	if (cycles <= units)
	{
		units -= cycles;
	}
	else
	{
		cycles -= units;
		units = (10 - cycles % 10) % 10;

		cycles = (cycles + 9) / 10; /* the +9 is so we get a carry if cycles%10 wasn't 0 */
		if (cycles <= tens)
		{
			tens -= cycles;
		}
		else
		{
			cycles -= tens;
			tens = (10 - cycles % 10) % 10;

			cycles = (cycles + 9) / 10;
			if (cycles <= hundreds)
			{
				hundreds -= cycles;
			}
			else
			{
				cycles -= hundreds;
				hundreds = (10 - cycles % 10) % 10;
				cycles = (cycles + 9) / 10;
				thousands = (10 + thousands - cycles % 10) % 10;
			}
		}
	}

	m_value = (thousands << 12) | (hundreds << 8) | (tens << 4) | units;
}

/* Counter loading: transfer of a count from the CR to the CE */
void pit_counter::load_counter_value()
{
	m_value = m_count;
	m_null_count = 0;
}

void pit_counter::set_output(int output)
{
	if (output != m_output)
	{
		m_output = output;
		flush_output();
	}
}

void pit_counter::flush_output()
{
	int new_output = m_output;
	if (m_period == 0)
	{
		const int mode = CTRL_MODE(m_control);
		if ((mode == 2 || mode == 3) && m_gate_input == 0)
			new_output = 1;
	}

	if (new_output != m_output_pin)
	{
		m_output_pin = new_output;
		m_out(new_output);
	}
}

/* This emulates timer "timer" for "elapsed_cycles" cycles and assumes no
   callbacks occur during that time. */
void pit_counter::simulate(int64_t elapsed_cycles)
{
	uint32_t adjusted_value;
	int mode = CTRL_MODE(m_control);
	static const uint32_t CYCLES_NEVER = (0xffffffff);
	uint32_t cycles_to_output = 0;

	switch (mode)
	{
	case 0:
		/* Mode 0: (Interrupt on Terminal Count) */
		if (m_phase == 0)
		{
			cycles_to_output = CYCLES_NEVER;
		}
		else
		{
			if (elapsed_cycles >= 0 && m_phase == 1)
			{
				/* Counter load cycle */
				if (elapsed_cycles > 0)
				{
					--elapsed_cycles;
					m_phase = 2;
				}
				load_counter_value();
			}

			if (m_gate == 0)
			{
				cycles_to_output = CYCLES_NEVER;
			}
			else
			{
				if (m_phase == 2)
				{
					adjusted_value = adjusted_count();
					if (elapsed_cycles >= adjusted_value)
					{
						/* Counter wrapped, output goes high */
						elapsed_cycles -= adjusted_value;
						m_phase = 3;
						m_value = 0;
						set_output(1);
					}
				}

				decrease_counter_value(elapsed_cycles);

				switch (m_phase)
				{
				case 1:  cycles_to_output = 1; break;
				case 2:  cycles_to_output = adjusted_count(); break;
				case 3:  cycles_to_output = adjusted_count(); break;
				}
			}
		}
		break;

	case 1:
		/* Mode 1: (Hardware Retriggerable One-Shot a.k.a. Programmable One-Shot) */
		if (elapsed_cycles >= 0 && m_phase == 1)
		{
			/* Counter load cycle, output goes low */
			if (elapsed_cycles > 0)
			{
				--elapsed_cycles;
				m_phase = 2;
			}
			load_counter_value();
			set_output(0);
		}

		if (m_phase == 2)
		{
			adjusted_value = adjusted_count();
			if (elapsed_cycles >= adjusted_value)
			{
				/* Counter wrapped, output goes high */
				m_phase = 3;
				set_output(1);
			}
		}

		decrease_counter_value(elapsed_cycles);

		switch (m_phase)
		{
		case 1:   cycles_to_output = 1; break;
		case 2:   cycles_to_output = adjusted_count(); break;
		default:  cycles_to_output = CYCLES_NEVER; break;
		}
		break;

	case 2:
		/* Mode 2: (Rate Generator) */
		if (m_gate == 0 || m_phase == 0)
		{
			/* Gate low or mode control write forces output high */
			set_output(1);
			cycles_to_output = CYCLES_NEVER;
		}
		else
		{
			if (elapsed_cycles >= 0 && m_phase == 1)
			{
				if (elapsed_cycles > 0)
				{
					--elapsed_cycles;
					m_phase = 2;
				}
				load_counter_value();
			}

			adjusted_value = adjusted_count();

			do
			{
				if (m_phase == 2)
				{
					if (elapsed_cycles + 1 >= adjusted_value)
					{
						/* Counter hits 1, output goes low */
						m_phase = 3;
						set_output(0);
					}
				}

				if (elapsed_cycles >= adjusted_value && m_phase == 3)
				{
					/* Reload counter, output goes high */
					elapsed_cycles -= adjusted_value;
					m_phase = 2;
					load_counter_value();
					adjusted_value = adjusted_count();
					set_output(1);
				}
			}
			while (elapsed_cycles >= adjusted_value);

			/* Calculate counter value */
			decrease_counter_value(elapsed_cycles);

			switch (m_phase)
			{
			case 1:   cycles_to_output = 1; break;
			default:  cycles_to_output = (m_value == 1) ? 1 : (adjusted_count() - 1); break;
			}
		}
		break;

	case 3:
		/* Mode 3: (Square Wave Generator) */
		if (m_gate == 0 || m_phase == 0)
		{
			/* Gate low or mode control write forces output high */
			set_output(1);
			cycles_to_output = CYCLES_NEVER;
		}
		else
		{
			if (elapsed_cycles >= 0 && m_phase == 1)
			{
				if (elapsed_cycles > 0)
				{
					--elapsed_cycles;
					m_phase = 2;
				}
				load_counter_value();
			}

			if (elapsed_cycles > 0)
			{
				adjusted_value = adjusted_count();

				do
				{
					if (m_phase == 2 && elapsed_cycles >= ((adjusted_value + 1) >> 1))
					{
						/* High phase expired, output goes low */
						elapsed_cycles -= ((adjusted_value + 1) >> 1);
						m_phase = 3;
						load_counter_value();
						adjusted_value = adjusted_count();
						set_output(0);
					}

					if (m_phase == 3 && elapsed_cycles >= (adjusted_value >> 1))
					{
						/* Low phase expired, output goes high */
						elapsed_cycles -= (adjusted_value >> 1);
						m_phase = 2;
						load_counter_value();
						adjusted_value = adjusted_count();
						set_output(1);
					}
				}
				while ((m_phase == 2 && elapsed_cycles >= ((adjusted_value + 1) >> 1)) ||
						(m_phase == 3 && elapsed_cycles >= (adjusted_value >> 1)));

				decrease_counter_value(elapsed_cycles * 2);

				switch (m_phase)
				{
				case 1:  cycles_to_output = 1; break;
				case 2:  cycles_to_output = (adjusted_count() + 1) >> 1; break;
				case 3:  cycles_to_output = adjusted_count() >> 1; break;
				}
			}
		}
		break;

	case 4:
	case 5:
		/* Mode 4: (Software Trigger Strobe)
		   Mode 5: (Hardware Trigger Strobe) */
		if (m_gate == 0 && mode == 4)
		{
			cycles_to_output = CYCLES_NEVER;
		}
		else
		{
			if (elapsed_cycles >= 0 && m_phase == 1)
			{
				if (elapsed_cycles > 0)
				{
					--elapsed_cycles;
					m_phase = 2;
				}
				load_counter_value();
			}

			if (m_value == 0 && m_phase == 2)
				adjusted_value = 0;
			else
				adjusted_value = adjusted_count();

			if (m_phase == 2 && elapsed_cycles >= adjusted_value)
			{
				/* Counter has hit zero, set output to low */
				elapsed_cycles -= adjusted_value;
				m_phase = 3;
				m_value = 0;
				set_output(0);
			}

			if (elapsed_cycles > 0 && m_phase == 3)
			{
				--elapsed_cycles;
				m_phase = 0;
				decrease_counter_value(1);
				set_output(1);
			}

			decrease_counter_value(elapsed_cycles);

			switch (m_phase)
			{
			case 1:  cycles_to_output = 1; break;
			case 2:  cycles_to_output = adjusted_count(); break;
			case 3:  cycles_to_output = 1; break;
			}
		}
		break;
	}

	if (cycles_to_output == CYCLES_NEVER || m_period == 0)
		adjust_timer(NEVER);
	else
		adjust_timer(m_last_updated + s64(cycles_to_output) * m_period);
}

/* This brings timer "timer" up to date */
void pit_counter::update()
{
	s64 now = m_sched.now();
	int64_t elapsed_cycles = 0;
	if (m_period != 0)
	{
		if (now > m_last_updated)
		{
			elapsed_cycles = (now - m_last_updated) >> m_period_shift;
			m_last_updated += elapsed_cycles * m_period;
		}
	}
	else
		m_last_updated = now;

	/* This emulates timer "timer" for "elapsed_cycles" cycles, broken down into
	   sections punctuated by callbacks. */
	if (elapsed_cycles > 0)
		simulate(elapsed_cycles);
	else if (m_period != 0)
		adjust_timer(m_last_updated + m_period);
}

/* Since read commands in mode 3 always return even numbers,
   we need to mask bit 0 off. */
uint16_t pit_counter::masked_value() const
{
	if (CTRL_MODE(m_control) == 3)
		return m_value & 0xfffe;
	return m_value;
}

u8 pit_counter::read()
{
	uint8_t data;

	update();

	if (m_latched_status)
	{
		/* Read status register (8254 only) */
		data = m_status;
		m_latched_status = 0;
	}
	else
	{
		if (m_latched_count != 0)
		{
			/* Read back latched count */
			data = (m_latch >> (m_rmsb ? 8 : 0)) & 0xff;
			m_rmsb = !m_rmsb;
			--m_latched_count;
		}
		else
		{
			uint16_t value = masked_value();

			/* Read back current count */
			switch (CTRL_ACCESS(m_control))
			{
			case 0:
			default:
				/* This should never happen */
				data = 0; /* Appease compiler */
				break;

			case 1:
				/* read counter bits 0-7 only */
				data = (value >> 0) & 0xff;
				break;

			case 2:
				/* read counter bits 8-15 only */
				data = (value >> 8) & 0xff;
				break;

			case 3:
				/* read bits 0-7 first, then 8-15 */

				// reading back the current count while in the middle of a
				// 16-bit write returns a xor'ed version of the value written
				// (apricot diagnostic timer test tests this)
				if (m_wmsb)
					data = ~m_lowcount;
				else
					data = value >> (m_rmsb ? 8 : 0);

				m_rmsb = !m_rmsb;
				break;
			}
		}
	}

	return data;
}

/* Loads a new value from the bus to the count register (CR) */
void pit_counter::load_count(uint16_t newcount)
{
	int mode = CTRL_MODE(m_control);

	if (newcount == 1)
	{
		/* Count of 1 is illegal in modes 2 and 3. What happens here was
		   determined experimentally. */
		if (mode == 2)
			newcount = 2;
		if (mode == 3)
			newcount = 0;
	}

	m_count = newcount;

	if (mode == 2 || mode == 3)
	{
		if (m_phase == 0)
			m_phase = 1;
	}
	else
	{
		if (mode == 0 || mode == 4)
			m_phase = 1;
	}
}

void pit_counter::readback(int command)
{
	update();

	if ((command & 1) == 0)
	{
		/* readback status command */
		if (!m_latched_status)
		{
			m_status = (m_control & 0x3f) | ((m_output != 0) ? 0x80 : 0) | (m_null_count ? 0x40 : 0);
			m_latched_status = 1;
		}
	}

	/* Experimentally determined: the read latch command seems to have no
	   effect if we're halfway through a 16-bit read */
	if ((command & 2) == 0 && !m_rmsb)
	{
		/* readback count command */
		if (m_latched_count == 0)
		{
			uint16_t value = masked_value();
			switch (CTRL_ACCESS(m_control))
			{
			case 0:
				/* This should never happen */
				break;

			case 1:
				/* latch bits 0-7 only */
				m_latch = ((value << 8) & 0xff00) | (value & 0xff);
				m_latched_count = 1;
				break;

			case 2:
				/* read bits 8-15 only */
				m_latch = (value & 0xff00) | ((value >> 8) & 0xff);
				m_latched_count = 1;
				break;

			case 3:
				/* latch all 16 bits */
				m_latch = value;
				m_latched_count = 2;
				break;
			}
		}
	}
}

// MAME defers control_w, count_w and gate_w with synchronize(); the deferred call runs at the
// write's own time, which is now() here.
void pit_counter::control_w(u8 data)
{
	update();
	if (CTRL_ACCESS(data) == 0)
	{
		/* Latch current timer value */
		/* Experimentally verified: this command does not affect the mode control register */
		readback(1);
	}
	else
	{
		m_control = (data & 0x3f);
		m_null_count = 1;
		m_wmsb = m_rmsb = false;
		/* Phase 0 is always the phase after a mode control write */
		m_phase = 0;
		set_output(CTRL_MODE(m_control) ? 1 : 0);
	}
}

void pit_counter::count_w(u8 data)
{
	update();
	bool middle_of_a_cycle = (m_sched.now() > m_last_updated && m_period != 0);

	switch (CTRL_ACCESS(m_control))
	{
	case 0:
		/* This should never happen */
		break;

	case 1:
		/* read/write counter bits 0-7 only */

		/* check if we should compensate for not being on a cycle boundary */
		if (middle_of_a_cycle)
			m_last_updated += m_period;

		load_count(data);
		if (m_period != 0)
			simulate(0);

		if (CTRL_MODE(m_control) == 0)
			set_output(0);
		break;

	case 2:
		/* read/write counter bits 8-15 only */

		/* check if we should compensate for not being on a cycle boundary */
		if (middle_of_a_cycle)
			m_last_updated += m_period;

		load_count(data << 8);
		if (m_period != 0)
			simulate(0);

		if (CTRL_MODE(m_control) == 0)
			set_output(0);
		break;

	case 3:
		/* read/write bits 0-7 first, then 8-15 */
		if (m_wmsb)
		{
			/* check if we should compensate for not being on a cycle boundary */
			if (middle_of_a_cycle)
				m_last_updated += m_period;

			load_count(m_lowcount | (data << 8));
			if (m_period != 0)
				simulate(0);
		}
		else
		{
			m_lowcount = data;
			if (CTRL_MODE(m_control) == 0)
			{
				/* The Intel docs say that writing the MSB in mode 0, phase
				   2 won't stop the count, but this was experimentally
				   determined to be false. */
				m_phase = 0;
				set_output(0);
			}
		}
		m_wmsb = !m_wmsb;
		break;
	}
}

bool pit_counter::edge_sensitive_gate() const
{
	const int mode = CTRL_MODE(m_control);
	return mode == 1 || mode == 2 || (mode == 3 && m_period == 0) || mode == 5;
}

void pit_counter::gate_w(int state)
{
	update();

	if (state != m_gate_input)
	{
		update();
		m_gate_input = state;
		if (m_period != 0)
			m_gate = state;
		if (state != 0 && edge_sensitive_gate())
		{
			if (m_period != 0)
				m_phase = 1;
			else
				m_gate_rose = 1;
		}
		if (m_period == 0)
			flush_output();
		update();
	}
}

void pit_counter::set_period(s64 ticks)
{
	update();
	m_period = ticks;
	m_period_shift = 0;
	while (ticks > 1) { ticks >>= 1; m_period_shift++; }
	update();
}

pit8254::pit8254(sched &s, std::function<void(int, int)> out)
	: m_c0(s, 0, [out](int st) { out(0, st); })
	, m_c1(s, 1, [out](int st) { out(1, st); })
	, m_c2(s, 2, [out](int st) { out(2, st); })
	, m_counter{&m_c0, &m_c1, &m_c2}
{
}

void pit8254::start()
{
	for (auto *c : m_counter) c->start();
}

void pit8254::reset()
{
	for (auto *c : m_counter) c->reset();
}

u8 pit8254::read(offs_t offset)
{
	offset &= 3;

	if (offset == 3)
	{
		/* Reading mode control register is illegal according to docs */
		/* Experimentally determined: reading it returns 0 */
		return 0;
	}
	else
		return m_counter[offset]->read();
}

void pit8254::write(offs_t offset, u8 data)
{
	offset &= 3;

	if (offset == 3)
	{
		/* Write to mode control register */
		int timer = (data >> 6) & 3;
		if (timer == 3)
		{
			/* Bit 0 of data must be 0. Todo: find out what the hardware does if it isn't. */
			int read_command = (data >> 4) & 3;
			for (int t = 0; t < 3; t++)
				if (BIT(data, t + 1) != 0)
					m_counter[t]->readback(read_command);
		}
		else
			m_counter[timer]->control_w(data);
	}
	else
		m_counter[offset]->count_w(data);
}

// ============================================================================================
// ICU: pic8259.cpp, x86 mode (v5x_icu_device)
// ============================================================================================

void pic8259::irq_timer_tick()
{
	/* check the various IRQs */
	for (int n = 0, irq = m_prio; n < 8; n++, irq = (irq + 1) & 7)
	{
		uint8_t mask = 1 << irq;

		/* is this IRQ in service and not cascading and sfnm? */
		if ((m_isr & mask) && !(m_master && m_cascade && m_nested && (m_slave & mask)))
		{
			break;
		}

		/* is this IRQ pending and enabled? */
		if ((m_state == state_t::READY) && (m_irr & mask) && !(m_imr & mask))
		{
			m_current_level = irq;
			m_out_int_func(1);
			return;
		}
		// if sfnm and in-service don't continue
		if((m_isr & mask) && m_master && m_cascade && m_nested && (m_slave & mask))
			break;
	}
	m_current_level = -1;
	m_out_int_func(0);
}

void pic8259::set_irq_line(int irq, int state)
{
	uint8_t mask = (1 << irq);

	if (state && !(m_irq_lines & mask))
	{
		/* setting IRQ line */
		m_irr |= mask;
		m_irq_lines |= mask;
	}
	else if (!state && (m_irq_lines & mask))
	{
		/* clearing IRQ line */
		m_irq_lines &= ~mask;
		m_irr &= ~mask;
	}

	if (m_inta_sequence == 0)
		m_irq_timer.adjust_at(m_sched.now());
}

u8 pic8259::acknowledge()
{
	/* is this IRQ pending and enabled? */
	if (m_current_level != -1)
	{
		uint8_t mask = 1 << m_current_level;
		if (!m_level_trig_mode && (!m_master || !(m_slave & mask)))
			m_irr &= ~mask;
		if (!m_auto_eoi)
			m_isr |= mask;
		m_irq_timer.adjust_at(m_sched.now());
		// no slave on the V53A's ICU (get_pic_ack returns 0)
		if ((m_cascade!=0) && (m_master!=0) && (mask & m_slave))
			return 0;
		else
			return m_current_level + m_base;
	}
	else
	{
		logerror("Spurious INTA\n");
		return m_base + 7;
	}
}

u8 pic8259::read(offs_t offset)
{
	/* NPW 18-May-2003 - Changing 0xFF to 0x00 as per Ruslan */
	uint8_t data = 0x00;

	switch(offset)
	{
		case 0: /* PIC acknowledge IRQ */
			if ( m_ocw3 & 0x04 )
			{
				/* Polling mode */
				if (m_current_level != -1)
				{
					data = 0x80 | m_current_level;

					if (!m_level_trig_mode && (!m_master || !BIT(m_slave, m_current_level)))
						m_irr &= ~(1 << m_current_level);

					if (!m_auto_eoi)
						m_isr |= 1 << m_current_level;

					m_irq_timer.adjust_at(m_sched.now());
				}

				m_ocw3 &= 0xfb;
			}
			else
			{
				switch ( m_ocw3 & 0x01 )
				{
				case 0:
					data = m_irr;
					break;

				case 1:
					data = m_isr & ~m_imr;
					break;
				}
			}
			break;

		case 1: /* PIC mask register */
			data = m_imr;
			break;
	}
	return data;
}

void pic8259::write(offs_t offset, u8 data)
{
	switch(offset)
	{
		case 0:    /* PIC acknowledge IRQ */
			if (data & 0x10)
			{
				/* write ICW1 - this pretty much resets the chip */
				m_imr                = 0x00;
				m_isr                = 0x00;
				m_slave              = 0x00;
				m_level_trig_mode    = (data & 0x08) ? 1 : 0;
				m_vector_size        = (data & 0x04) ? 1 : 0;
				m_cascade            = (data & 0x02) ? 0 : 1;
				m_icw4_needed        = (data & 0x01) ? 1 : 0;
				m_vector_addr_low    = (data & 0xe0);
				m_state              = state_t::ICW2;
				m_current_level      = -1;
				m_inta_sequence      = 0;
				m_irr                = m_level_trig_mode ? m_irq_lines : 0;
				m_out_int_func(0);
			}
			else if (m_state == state_t::READY)
			{
				if ((data & 0x98) == 0x08)
				{
					/* write OCW3 */
					if (BIT(data, 1))
						m_ocw3 = (m_ocw3 & 0xfe) | (data & 0x01);
					if (BIT(data, 2))
						m_ocw3 |= 0x04;
					// TODO: special mask mode
					if (BIT(data, 6))
						m_ocw3 = (m_ocw3 & 0xdf) | (data & 0x20);
				}
				else if ((data & 0x18) == 0x00)
				{
					int n = data & 7;
					uint8_t mask = 1 << n;

					/* write OCW2 */
					switch (data & 0xe0)
					{
						case 0x00:
							m_prio = 0;
							break;
						case 0x20:
							for (n = 0, mask = 1<<m_prio; n < 8; n++, mask = (mask<<1) | (mask>>7))
							{
								if (m_isr & mask)
								{
									m_isr &= ~mask;
									break;
								}
							}
							break;
						case 0x40:
							break;
						case 0x60:
							if( m_isr & mask )
							{
								m_isr &= ~mask;
							}
							break;
						case 0x80:
							m_prio = (m_prio + 1) & 7;
							break;
						case 0xa0:
							for (n = 0, mask = 1<<m_prio; n < 8; n++, mask = (mask<<1) | (mask>>7))
							{
								if( m_isr & mask )
								{
									m_isr &= ~mask;
									m_prio = (m_prio + 1) & 7;
									break;
								}
							}
							break;
						case 0xc0:
							m_prio = (n + 1) & 7;
							break;
						case 0xe0:
							if( m_isr & mask )
							{
								m_isr &= ~mask;
								m_prio = (n + 1) & 7;
							}
							break;
					}
				}
			}
			break;

		case 1:
			switch(m_state)
			{
				case state_t::ICW1:
					break;

				case state_t::ICW2:
					/* write ICW2 */
					m_base = data & 0xf8;
					m_vector_addr_high = data ;
					if (m_cascade)
					{
						m_state = state_t::ICW3;
					}
					else
					{
						m_state = m_icw4_needed ? state_t::ICW4 : state_t::READY;
					}
					break;

				case state_t::ICW3:
					/* write ICW3 */
					m_slave = data;
					m_state = m_icw4_needed ? state_t::ICW4 : state_t::READY;
					break;

				case state_t::ICW4:
					/* write ICW4 */
					m_nested = (data & 0x10) ? 1 : 0;
					m_mode = (data >> 2) & 3;
					m_auto_eoi = (data & 0x02) ? 1 : 0;
					m_is_x86 = (data & 0x01) ? 1 : 0;
					m_state = state_t::READY;
					break;

				case state_t::READY:
					/* write OCW1 - set interrupt mask register */
					m_imr = data;
					break;
			}
			break;
	}
	m_irq_timer.adjust_at(m_sched.now());
}

void pic8259::reset()
{
	m_state = state_t::READY;
	m_isr = 0;
	m_irr = 0;
	m_irq_lines = 0;
	m_prio = 0;
	m_imr = 0;
	m_input = 0;
	m_ocw3 = 0;
	m_level_trig_mode = 0;
	m_vector_size = 0;
	m_cascade = 0;
	m_icw4_needed = 0;
	m_base = 0;
	m_slave = 0;
	m_nested = 0;
	m_mode = 0;
	m_auto_eoi = 0;
	m_is_x86 = 0;
	m_vector_addr_low = 0;
	m_vector_addr_high = 0;
	m_current_level = -1;
	m_inta_sequence = 0;
	m_master = 1;   // in_sp is 1 on the V5x
}

// ============================================================================================
// DMAU: am9517a.cpp (am9517a_device, upd71071_device, v5x_dmau_device)
// ============================================================================================

#define COMMAND_MEM_TO_MEM          BIT(m_command, 0)
#define COMMAND_CH0_ADDRESS_HOLD    BIT(m_command, 1)
#define COMMAND_DISABLE             BIT(m_command, 2)
#define COMMAND_COMPRESSED_TIMING   BIT(m_command, 3)
#define COMMAND_ROTATING_PRIORITY   BIT(m_command, 4)
#define COMMAND_EXTENDED_WRITE      BIT(m_command, 5)
#define COMMAND_DREQ_ACTIVE_LOW     BIT(m_command, 6)
#define COMMAND_DACK_ACTIVE_HIGH    BIT(m_command, 7)

#define MODE_TRANSFER_MASK          (m_channel[m_current_channel].m_mode & 0x0c)
#define MODE_TRANSFER_VERIFY        0x00
#define MODE_TRANSFER_WRITE         0x04
#define MODE_TRANSFER_READ          0x08
#define MODE_TRANSFER_ILLEGAL       0x0c
#define MODE_AUTOINITIALIZE         BIT(m_channel[m_current_channel].m_mode, 4)
#define MODE_ADDRESS_DECREMENT      BIT(m_channel[m_current_channel].m_mode, 5)
#define MODE_MASK                   (m_channel[m_current_channel].m_mode & 0xc0)
#define MODE_DEMAND                 0x00
#define MODE_SINGLE                 0x40
#define MODE_BLOCK                  0x80
#define MODE_CASCADE                0xc0

enum
{
	STATE_SI,
	STATE_S0,
	STATE_SC,
	STATE_S1,
	STATE_S2,
	STATE_S3,
	STATE_SW,
	STATE_S4,
	STATE_S11,
	STATE_S12,
	STATE_S13,
	STATE_S14,
	STATE_S21,
	STATE_S22,
	STATE_S23,
	STATE_S24
};

// the DMAU's clock is the 32 MHz clock over 4 (DERIVED_CLOCK(1, 4))
static constexpr s64 DMAU_TICKS = 4;

v5x_dmau::v5x_dmau(sched &s, dmau_bus bus)
	: m_sched(s), m_bus(std::move(bus)), m_step(s, [this] { execute_step(); })
{
}

void v5x_dmau::start()
{
	for (auto &elem : m_channel)
	{
		elem.m_address = 0;
		elem.m_count = 0;
		elem.m_base_address = 0;
		elem.m_base_count = 0;
		elem.m_mode = 0;
	}
	m_address_mask = 0x00ffffff;
	// force clear upon initial reset
	m_eop = ASSERT_LINE;
	m_suspended = false;
	m_step.adjust_at(m_sched.now());
}

// MAME's trigger(1): a device suspended until it resumes from now
void v5x_dmau::trigger()
{
	if (m_suspended)
	{
		m_suspended = false;
		m_step.adjust_at(((m_sched.now() >> 2) + 1) << 2);   // the next DMAU clock, DMAU_TICKS 4
	}
}

void v5x_dmau::dma_request(int channel, bool state)
{
	if (state)
		m_status |= (1 << (channel + 4));
	else
		m_status &= ~(1 << (channel + 4));

	trigger();
}

void v5x_dmau::mask_channel(int channel, bool state)
{
	if (state)
		m_mask |= 1 << channel;
	else
		m_mask &= ~(1 << channel);
}

bool v5x_dmau::is_request_active(int channel)
{
	return (BIT(COMMAND_DREQ_ACTIVE_LOW ? ~m_status : m_status, channel + 4) && !BIT(m_mask, channel)) ? true : false;
}

bool v5x_dmau::is_software_request_active(int channel)
{
	return BIT(m_request, channel) && ((m_channel[channel].m_mode & 0xc0) == MODE_BLOCK);
}

void v5x_dmau::set_hreq(int state)
{
	if (m_hreq != state)
	{
		m_bus.out_hreq(state);

		m_hreq = state;
	}
}

int v5x_dmau::get_state1(bool msb_changed)
{
	if (COMMAND_MEM_TO_MEM)
	{
		return msb_changed ? STATE_S11 : STATE_S12;
	}
	else
	{
		return msb_changed ? STATE_S1 : STATE_S2;
	}
}

// upd71071_device::dma_read, then am9517a_device::dma_read for 8-bit transfers. Unbound
// callbacks: mem16r and ior read 0.
void v5x_dmau::dma_read()
{
	if (m_channel[m_current_channel].m_mode & 0x1)
	{
		offs_t const offset = m_channel[m_current_channel].m_address >> 1;

		switch (MODE_TRANSFER_MASK)
		{
		case MODE_TRANSFER_VERIFY:
		case MODE_TRANSFER_WRITE:
			m_temp = m_bus.in_io16r(m_current_channel, offset);
			break;

		case MODE_TRANSFER_READ:
			m_temp = 0;   // m_in_mem16r_cb, unbound on hng64
			break;
		}
	}
	else
	{
		offs_t offset = m_channel[m_current_channel].m_address;

		switch (MODE_TRANSFER_MASK)
		{
		case MODE_TRANSFER_VERIFY:
		case MODE_TRANSFER_WRITE:
			m_temp = 0;   // m_in_ior_cb, unbound on hng64
			break;

		case MODE_TRANSFER_READ:
			m_temp = m_bus.in_memr(offset);
			break;
		}
	}
}

// upd71071_device::dma_write, then am9517a_device::dma_write. Unbound callbacks: mem16w, memw
// and iow do nothing.
void v5x_dmau::dma_write()
{
	if (m_channel[m_current_channel].m_mode & 0x1)
	{
		offs_t const offset = m_channel[m_current_channel].m_address >> 1;

		switch (MODE_TRANSFER_MASK)
		{
		case MODE_TRANSFER_VERIFY:
		case MODE_TRANSFER_WRITE:
			break;

		case MODE_TRANSFER_READ:
			m_bus.out_io16w(m_current_channel, offset, m_temp);
			break;
		}
	}
	else
	{
		switch (MODE_TRANSFER_MASK)
		{
		case MODE_TRANSFER_VERIFY:
			m_bus.in_memr(m_channel[m_current_channel].m_address);
			break;

		case MODE_TRANSFER_WRITE:
		case MODE_TRANSFER_READ:
			break;
		}
	}
}

void v5x_dmau::dma_advance()
{
	bool msb_changed = false;

	if (m_current_channel || !COMMAND_MEM_TO_MEM || !COMMAND_CH0_ADDRESS_HOLD)
	{
		if (MODE_ADDRESS_DECREMENT)
		{
			m_channel[m_current_channel].m_address -= transfer_size(m_current_channel);
			m_channel[m_current_channel].m_address &= m_address_mask;

			if ((m_channel[m_current_channel].m_address & 0xff) == 0xff)
			{
				msb_changed = true;
			}
		}
		else
		{
			m_channel[m_current_channel].m_address += transfer_size(m_current_channel);
			m_channel[m_current_channel].m_address &= m_address_mask;

			if ((m_channel[m_current_channel].m_address & 0xff) == 0x00)
			{
				msb_changed = true;
			}
		}
	}

	if (m_channel[m_current_channel].m_count-- == 0)
	{
		end_of_process();
	}
	else
	{
		switch (MODE_MASK)
		{
		case MODE_DEMAND:
			if (!is_request_active(m_current_channel))
			{
				set_hreq(0);
				set_dack();
				m_state = STATE_SI;
			}
			else
			{
				m_state = get_state1(msb_changed);
			}
			break;

		case MODE_SINGLE:
			set_hreq(0);
			set_dack();
			m_state = STATE_SI;
			break;

		case MODE_BLOCK:
			m_state = get_state1(msb_changed);
			break;

		case MODE_CASCADE:
			break;
		}
	}
}

void v5x_dmau::end_of_process()
{
	// terminal count
	if (COMMAND_MEM_TO_MEM)
	{
		m_status |= 1 << 0;
		m_status |= 1 << 1;
		m_request &= ~(1 << 0);
		m_request &= ~(1 << 1);
	}
	else
	{
		m_status |= 1 << m_current_channel;
		m_request &= ~(1 << m_current_channel);
	}

	if (MODE_AUTOINITIALIZE)
	{
		// autoinitialize
		m_channel[m_current_channel].m_address = m_channel[m_current_channel].m_base_address;
		m_channel[m_current_channel].m_count = m_channel[m_current_channel].m_base_count;
	}
	else
	{
		// mask out channel
		mask_channel(m_current_channel, true);
	}

	set_eop(CLEAR_LINE);
	set_hreq(0);

	m_current_channel = -1;
	set_dack();

	m_state = STATE_SI;
}

void v5x_dmau::soft_reset()
{
	m_state = STATE_SI;
	m_command = 0;
	m_status &= 0xf0;
	m_request = 0;
	m_mask = 0x0f;
	m_temp = 0;
	m_msb = 0;
	m_current_channel = -1;
	m_last_channel = 3;
	m_hreq = -1;

	set_hreq(0);
	set_eop(CLEAR_LINE);

	set_dack();
}

// One iteration of am9517a_device::execute_run's loop: a DMA clock. MAME's
// suspend_until_trigger(1, true) stops the clock until trigger().
void v5x_dmau::execute_step()
{
	switch (m_state)
	{
	case STATE_SI:
		if (!COMMAND_DISABLE)
		{
			int priority[] = { 0, 1, 2, 3 };

			if (COMMAND_ROTATING_PRIORITY)
			{
				int last_channel = m_last_channel;

				for (int channel = 3; channel >= 0; channel--)
				{
					priority[channel] = last_channel;
					last_channel--;
					if (last_channel < 0) last_channel = 3;
				}
			}

			for (int channel = 0; channel < 4; channel++)
			{
				if (is_request_active(priority[channel]) || is_software_request_active(priority[channel]))
				{
					m_current_channel = m_last_channel = priority[channel];
					m_state = STATE_S0;
					break;
				}
				else if (COMMAND_MEM_TO_MEM && BIT(m_request, channel) && ((m_channel[channel].m_mode & 0xc0) == MODE_SINGLE))
				{
					m_current_channel = m_last_channel = priority[channel];
					m_state = STATE_S0;
					break;
				}
			}
		}
		if(m_state == STATE_SI)
		{
			m_suspended = true;
		}
		break;

	case STATE_S0:
		set_hreq(1);

		if (m_hack)
		{
			m_state = (MODE_MASK == MODE_CASCADE) ? STATE_SC : get_state1(true);
		}
		else
		{
			m_suspended = true;
		}
		break;

	case STATE_SC:
		if (!is_request_active(m_current_channel))
		{
			set_hreq(0);
			m_current_channel = -1;
			m_state = STATE_SI;
		}
		else
		{
			m_suspended = true;
		}

		set_dack();
		break;

	case STATE_S1:
		m_state = STATE_S2;
		break;

	case STATE_S2:
		set_dack();
		if (COMMAND_COMPRESSED_TIMING)
		{
			// signal end of process during last cycle
			if (m_channel[m_current_channel].m_count == 0)
				set_eop(ASSERT_LINE);

			m_state = STATE_S4;
		}
		else
			m_state = STATE_S3;
		break;

	case STATE_S3:
		// signal end of process during last cycle
		if (m_channel[m_current_channel].m_count == 0)
			set_eop(ASSERT_LINE);

		dma_read();

		if (COMMAND_EXTENDED_WRITE)
		{
			dma_write();
		}

		m_state = m_ready ? STATE_S4 : STATE_SW;
		break;

	case STATE_SW:
		m_state = m_ready ? STATE_S4 : STATE_SW;
		break;

	case STATE_S4:
		if (COMMAND_COMPRESSED_TIMING)
		{
			dma_read();
			dma_write();
		}
		else if (!COMMAND_EXTENDED_WRITE)
		{
			dma_write();
		}

		dma_advance();
		break;

	case STATE_S11:
		m_current_channel = 0;

		m_state = STATE_S12;
		break;

	case STATE_S12:
		m_state = STATE_S13;
		break;

	case STATE_S13:
		m_state = STATE_S14;
		break;

	case STATE_S14:
		dma_read();

		m_state = STATE_S21;
		break;

	case STATE_S21:
		m_current_channel = 1;

		m_state = STATE_S22;
		break;

	case STATE_S22:
		m_state = STATE_S23;
		break;

	case STATE_S23:
		// signal end of process during last cycle
		if (m_channel[m_current_channel].m_count == 0)
			set_eop(ASSERT_LINE);

		m_state = STATE_S24;
		break;

	case STATE_S24:
		dma_write();
		dma_advance();

		m_current_channel = 0;
		m_channel[m_current_channel].m_count--;
		if (MODE_ADDRESS_DECREMENT)
		{
			m_channel[m_current_channel].m_address -= transfer_size(m_current_channel);
			m_channel[m_current_channel].m_address &= m_address_mask;
		}
		else
		{
			m_channel[m_current_channel].m_address += transfer_size(m_current_channel);
			m_channel[m_current_channel].m_address &= m_address_mask;
		}

		break;
	}

	if (!m_suspended)
		m_step.adjust_at(m_sched.m_firing + DMAU_TICKS);
}

void v5x_dmau::hack_w(int state)
{
	m_hack = state;
	trigger();
}

u8 v5x_dmau::read(offs_t offset)
{
	uint8_t ret = 0;
	int channel = m_selected_channel;

	switch (offset)
	{
		case 0x01:  // Channel
			ret = (1 << m_selected_channel);
			if (m_base != 0)
				ret |= 0x10;
			break;
		case 0x02:  // Count (low)
			if (m_base != 0)
				ret = m_channel[channel].m_base_count & 0xff;
			else
				ret = m_channel[channel].m_count & 0xff;
			break;
		case 0x03:  // Count (high)
			if (m_base != 0)
				ret = (m_channel[channel].m_base_count >> 8) & 0xff;
			else
				ret = (m_channel[channel].m_count >> 8) & 0xff;
			break;
		case 0x04:  // Address (low)
			if (m_base != 0)
				ret = m_channel[channel].m_base_address & 0xff;
			else
				ret = m_channel[channel].m_address & 0xff;
			break;
		case 0x05:  // Address (mid)
			if (m_base != 0)
				ret = (m_channel[channel].m_base_address >> 8) & 0xff;
			else
				ret = (m_channel[channel].m_address >> 8) & 0xff;
			break;
		case 0x06:  // Address (high)
			if (m_base != 0)
				ret = (m_channel[channel].m_base_address >> 16) & 0xff;
			else
				ret = (m_channel[channel].m_address >> 16) & 0xff;
			break;
		case 0x0a:  // Mode control
				ret = (m_channel[channel].m_mode);
			break;

		case 0x08:  // Device control (low)
			ret = m_command & 0xff;
			break;
		case 0x09:  // Device control (high) // UPD71071 only?
			ret = m_command_high & 0xff;
			break;
		case 0x0b:  // Status
			ret = m_status;
			// clear TC bits
			m_status &= 0xf0;
			break;
		case 0x0c:  // Temporary (low)
			ret = m_temp & 0xff;
			break;
		case 0x0d:  // Temporary (high) // UPD71071 only? (other doesn't do 16-bit?)
			ret = (m_temp >> 8 ) & 0xff;
			break;
		case 0x0e:  // Request
			ret = m_request;
			break;
		case 0x0f:  // Mask
			ret = m_mask;
			break;
	}

	return ret;
}

void v5x_dmau::write(offs_t offset, u8 data)
{
	int channel = m_selected_channel;

	switch (offset & 0xf)
	{
		case 0x00:  // Initialise
			// bit 0 = soft reset
			if (BIT(data, 0))
			{
				soft_reset();

				m_selected_channel = 0;
				m_base = 0;
			}
			break;
		case 0x01:  // Channel
			m_selected_channel = data & 0x03;
			m_base = data & 0x04;
			break;
		case 0x02:  // Count (low)
			m_channel[channel].m_base_count =
				(m_channel[channel].m_base_count & 0xff00) | data;
			if (m_base == 0)
				m_channel[channel].m_count =
				(m_channel[channel].m_count & 0xff00) | data;
			break;
		case 0x03:  // Count (high)
			m_channel[channel].m_base_count =
				(m_channel[channel].m_base_count & 0x00ff) | (data << 8);
			if (m_base == 0)
				m_channel[channel].m_count =
				(m_channel[channel].m_count & 0x00ff) | (data << 8);
			break;
		case 0x04:  // Address (low)
			m_channel[channel].m_base_address =
				(m_channel[channel].m_base_address & 0xffffff00) | data;
			if (m_base == 0)
				m_channel[channel].m_address =
				(m_channel[channel].m_address & 0xffffff00) | data;
			break;
		case 0x05:  // Address (mid)
			m_channel[channel].m_base_address =
				(m_channel[channel].m_base_address & 0xffff00ff) | (data << 8);
			if (m_base == 0)
				m_channel[channel].m_address =
				(m_channel[channel].m_address & 0xffff00ff) | (data << 8);
			break;
		case 0x06:  // Address (high)
			m_channel[channel].m_base_address =
				(m_channel[channel].m_base_address & 0xff00ffff) | (data << 16);
			if (m_base == 0)
				m_channel[channel].m_address =
				(m_channel[channel].m_address & 0xff00ffff) | (data << 16);
			break;
		case 0x0a:  // Mode control
			m_channel[channel].m_mode = data;
			// clear terminal count
			m_status &= ~(1 << channel);
			break;

		case 0x08:  // Device control (low)
			m_command = data;
			break;
		case 0x09:  // Device control (high)
			m_command_high = data;
			break;
		case 0x0c:  // Temporary (low): v5x_dmau ignores it
		case 0x0d:  // Temporary (high)
		case 0x0e:  // Request: no software requests on the v53 integrated version
			break;
		case 0x0f:  // Mask
			m_mask = data & 0x0f;
			break;
	}
	trigger();
}

// ============================================================================================
// the V53A: v5x.cpp
// ============================================================================================

v53a::v53a(nec_space &program, sched &s, v53_board board)
	: nec_common_device(program)
	, m_sched(s)
	, m_board(std::move(board))
	, m_tcu(s, [this](int i, int st) { m_board.tout(i, st); })
	, m_icu(s, [this](int st) { set_int_line(st); })
	, m_dmau(s, m_board.dma)
{
}

void v53a::start()
{
	m_tcu.start();
	m_dmau.start();
}

void v53a::tcu_clock_update()
{
	// no TCLK on hng64 (m_tclk 0): a counter on it stops
	for (int i = 0; i < 3; i++)
		m_tcu.counter(i).set_period(BIT(m_TCKS, i + 2) ? 0 : s64(4) << (m_TCKS & 3));
}

void v53a::reset()
{
	// interface_pre_reset
	m_OPSEL = 0x00;
	m_SULA = 0x00;
	m_TULA = 0x00;
	m_IULA = 0x00;
	m_DULA = 0x00;
	m_OPHA = 0x00;
	m_BRC  = 0x00;
	m_TCKS = 0x00;
	tcu_clock_update();

	// v53_device::device_reset
	device_reset();
	m_SCTL = 0x00;

	// the children, in the order v5x_add_mconfig adds them
	m_tcu.reset();
	m_dmau.reset();
	m_icu.reset();
	m_scu_simk = 0x03;
}

// ---- nec_common_device's io space -----------------------------------------------------------

u8 v53a::internal_port_r(offs_t a)
{
	if (m_int_log && a >= 0xff80) m_int_log('r', a, 0);
	if (a < 0xff80)
	{
		const u16 w = m_v33_transtable[(a - 0xff00) >> 1];
		return (a & 1) ? w >> 8 : w & 0xff;
	}
	switch (a)
	{
	case 0xff80: return m_xa ? 1 : 0;   // xam_r
	case 0xfff0: return m_TCKS;
	case 0xfff8: return m_SULA;
	case 0xfff9: return m_TULA;
	case 0xfffa: return m_IULA;
	case 0xfffb: return m_DULA;
	case 0xfffc: return m_OPHA;
	case 0xfffd: return m_OPSEL;
	case 0xfffe: return m_SCTL;
	}
	return 0;
}

void v53a::internal_port_w(offs_t a, u8 v)
{
	if (m_int_log) m_int_log('w', a, v);
	if (a < 0xff80)
	{
		u16 &w = m_v33_transtable[(a - 0xff00) >> 1];
		w = (a & 1) ? (w & 0x00ff) | (v << 8) : (w & 0xff00) | v;
		return;
	}
	switch (a)
	{
	case 0xffe9: m_BRC = v; break;              // the SCU's baud rate counter
	case 0xfff0: m_TCKS = v; tcu_clock_update(); break;
	case 0xfff8: m_SULA = v; break;
	case 0xfff9: m_TULA = v; break;
	case 0xfffa: m_IULA = v; break;
	case 0xfffb: m_DULA = v; break;
	case 0xfffc: m_OPHA = v; break;
	case 0xfffd: m_OPSEL = v & 0x0f; break;
	case 0xfffe: m_SCTL = v & 0x1f; break;
	}
}

u8 v53a::nec_io_read_byte(offs_t a)
{
	a &= 0xffff;
	if (a >= 0xff00)
		return internal_port_r(a);
	const u16 w = m_board.io_r16(a & ~1, (a & 1) ? 0xff00 : 0x00ff);
	return (a & 1) ? w >> 8 : w & 0xff;
}

u16 v53a::nec_io_read_word(offs_t a)
{
	a &= 0xffff;
	if ((a & 1) || a >= 0xff00)
		return nec_io_read_byte(a) | (nec_io_read_byte(a + 1) << 8);
	return m_board.io_r16(a, 0xffff);
}

void v53a::nec_io_write_byte(offs_t a, u8 v)
{
	a &= 0xffff;
	if (a >= 0xff00)
		internal_port_w(a, v);
	else if (a & 1)
		m_board.io_w16(a & ~1, v << 8, 0xff00);
	else
		m_board.io_w16(a, v, 0x00ff);
}

void v53a::nec_io_write_word(offs_t a, u16 v)
{
	a &= 0xffff;
	if ((a & 1) || a >= 0xff00)
	{
		nec_io_write_byte(a, v & 0xff);
		nec_io_write_byte(a + 1, v >> 8);
	}
	else
		m_board.io_w16(a, v, 0xffff);
}

// ---- AS_INTERNAL_IO ----------------------------------------------------------------------------

enum { PER_TEMP, PER_UNMAPPED, PER_DMAU, PER_ICU, PER_TCU, PER_SCU };

// install_peripheral_io's layout, latest install first. In 16-bit mode (SCTL bit 0 clear) an
// 8-bit unit answers on its base's byte lane only, at a register a word; the other lane in its
// range is unmapped.
int v53a::peripheral_at(offs_t a, int &offset) const
{
	const bool IOAG = m_SCTL & 1;
	auto unit = [&](u8 base, offs_t half8, offs_t half16, int id) -> int {
		if (IOAG)
		{
			const offs_t lo = base & ~half8;
			if (a < lo || a > (base | half8)) return -1;
			offset = a - lo;
			return id;
		}
		const offs_t lo = base & ~half16;
		if (a < lo || a > (base | half16)) return -1;
		if ((a & 1) != (base & 1u)) return PER_UNMAPPED;
		offset = (a - lo) >> 1;
		return id;
	};
	int r;
	if ((m_OPSEL & OPSEL_SS) && (r = unit(m_SULA, 3, 7, PER_SCU)) >= 0) return r;
	if ((m_OPSEL & OPSEL_TS) && (r = unit(m_TULA, 3, 7, PER_TCU)) >= 0) return r;
	if ((m_OPSEL & OPSEL_IS) && (r = unit(m_IULA, 1, 3, PER_ICU)) >= 0) return r;
	if (m_OPSEL & OPSEL_DS)
	{
		const offs_t lo = m_DULA & ~0x0f;
		const bool i8237 = m_SCTL & 0x02;
		const offs_t hi = i8237 && !IOAG ? (m_DULA | 0x1f) : (m_DULA | 0x0f);
		const offs_t lo2 = i8237 && !IOAG ? (m_DULA & ~0x1f) : lo;
		if (a >= lo2 && a <= hi)
		{
			if (i8237) return PER_UNMAPPED;   // uPD71037 mode is not emulated
			offset = a - lo;
			return PER_DMAU;
		}
	}
	return PER_TEMP;
}

u8 v53a::scu_r(offs_t offset)
{
	m_scu_accesses++;
	switch (offset)
	{
	case 1: return 0x05;   // i8251 status after reset: TxEMPTY, TxRDY
	case 3: return m_scu_simk;
	}
	return 0;
}

void v53a::scu_w(offs_t offset, u8 data)
{
	m_scu_accesses++;
	if (offset == 3) m_scu_simk = data;
}

u8 v53a::internal_io_read_byte(offs_t a)
{
	a &= 0xff;
	int offset = 0;
	u8 d;
	switch (peripheral_at(a, offset))
	{
	case PER_DMAU: d = m_dmau.read(offset); break;
	case PER_ICU:  d = m_icu.read(offset); break;
	case PER_TCU:  d = m_tcu.read(offset); break;
	case PER_SCU:  d = scu_r(offset); break;
	case PER_UNMAPPED: d = 0; break;
	default: return nec_io_read_byte(OPHA() | a);   // temp_io_byte_r
	}
	if (m_int_log) m_int_log('r', OPHA() | a, d);
	return d;
}

void v53a::internal_io_write_byte(offs_t a, u8 v)
{
	a &= 0xff;
	int offset = 0;
	const int per = peripheral_at(a, offset);
	if (m_int_log && per != PER_TEMP) m_int_log('w', OPHA() | a, v);
	switch (per)
	{
	case PER_DMAU: m_dmau.write(offset, v); return;
	case PER_ICU:  m_icu.write(offset, v); return;
	case PER_TCU:  m_tcu.write(offset, v); return;
	case PER_SCU:  scu_w(offset, v); return;
	case PER_UNMAPPED: return;
	}
	nec_io_write_byte(OPHA() | a, v);   // temp_io_byte_w
}

// ---- v53_device's io accessors ------------------------------------------------------------------

u8 v53a::io_read_byte(offs_t a)
{
	if (check_OPHA(a))
		return internal_io_read_byte(a);
	else
		return nec_io_read_byte(a);
}

u16 v53a::io_read_word(offs_t a)
{
	if (check_OPHA(a))
	{
		if ((a & 0xff) == 0xff)
			return (internal_io_read_byte(a) & 0x00ff) | ((nec_io_read_byte(a + 1) << 8) & 0xff00);
		else
			return internal_io_read_byte(a) | (internal_io_read_byte(a + 1) << 8);
	}
	else
		return nec_io_read_word(a);
}

void v53a::io_write_byte(offs_t a, u8 v)
{
	if (check_OPHA(a))
		internal_io_write_byte(a, v);
	else
		nec_io_write_byte(a, v);
}

void v53a::io_write_word(offs_t a, u16 v)
{
	if (check_OPHA(a))
	{
		if ((a & 0xff) == 0xff)
		{
			internal_io_write_byte(a, v & 0xff);
			nec_io_write_byte(a + 1, (v >> 8) & 0xff);
		}
		else
		{
			internal_io_write_byte(a, v & 0xff);
			internal_io_write_byte(a + 1, v >> 8);
		}
	}
	else
		nec_io_write_word(a, v);
}
