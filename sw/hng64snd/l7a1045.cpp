// license:BSD-3-Clause
// copyright-holders:R. Belmont, O. Galibert
// From MAME src/devices/sound/l7a1045_l6028_dsp_a.cpp (PROVENANCE.md); the register notes are
// in MAME's source. The stream's output, MAME's add_int(..., 32768), is kept as the integer sum.

#include "l7a1045.h"
#include <algorithm>

enum
{
	L6028_Start = 0,
	L6028_End,
	L6028_Loop_Start,
	L6028_Volume_Env,
	L6028_Volume_Env_Target,
	L6028_Filter_Env,
	L6028_Filter_Env_Target,
	L6028_Mixer_Params
};

static constexpr int CONTROL_DMA_START      = 6;
static constexpr int CONTROL_KEY_ON         = 8;

// channel mapping is weird
static constexpr int channel_remap[8] = { 3, 1, 7, 5, 2, 0, 6, 4 };

// 64 clocks of 33.8688 MHz: 80000 / 1323 ticks of 32 MHz, 60 and 620 / 1323
static constexpr s64 DMA_TICKS = 60, DMA_REM = 620, DMA_DEN = 1323;

l7a1045::l7a1045(sched &s, const u8 *rom, std::function<void(int)> drq)
	: m_sched(s)
	, m_rom(rom)
	, m_ram(0x10000, 0)
	, m_drq_handler(std::move(drq))
	, m_dma_timer(s, [this] { dma_timer_callback(); })
{
}

void l7a1045::update()
{
	const s64 now441 = m_sched.now() * 441;
	int n = 0;
	while (m_lim <= now441)
	{
		m_lim += 320000;
		n++;
	}
	if (n)
	{
		sound_stream_update(m_next, n);
		m_next += n;
	}
}

void l7a1045::sound_stream_update(s64 from, int samples)
{
	const size_t base = size_t(from - m_first) * OUTPUTS;
	m_out.resize(base + size_t(samples) * OUTPUTS, 0);
	s32 *out = &m_out[base];

	// MAME's loop with each voice's state in locals for the samples, stored back once: the stores
	// into out would otherwise make the compiler reload every field each sample. MAME's volume
	// products, (fout * (uint64_t(vol) * uint64_t(env))) >> 24 taken to s32, are bits 24-55 of the
	// product, which the signed 32x32 multiply below gives too: the output is the same.
	for (int i = 0; i < NUM_VOICES; i++)
	{
		if (m_key & (1 << i))
		{
			l7a1045_voice *vptr = &m_voice[i];

			const uint32_t start = vptr->start;
			const uint32_t end = vptr->end;
			const uint32_t step  = vptr->step;
			const uint32_t loop_start = vptr->loop_start;
			const uint8_t sample_type = vptr->sample_type;
			const uint32_t l_volume = vptr->l_volume, r_volume = vptr->r_volume;
			const uint32_t send_level = vptr->send_level;
			// MAME reads channel_remap[8] with any dest but 0xf; 8-14 read past it. Here they send
			// nothing.
			const int send_out = (send_level > 0 && (vptr->send_dest & 0xf) < 8)
				? 2 + channel_remap[vptr->send_dest & 0xf] : -1;
			const uint16_t env_target = vptr->env_target, env_step = vptr->env_step;
			const uint16_t flt_target = vptr->flt_target, flt_step = vptr->flt_step;
			const int32_t flt_resonance = vptr->flt_resonance;

			uint32_t pos = vptr->pos;
			uint32_t frac = vptr->frac;
			uint16_t env_volume = vptr->env_volume;
			uint32_t env_pos = vptr->env_pos;
			uint16_t flt_freq = vptr->flt_freq;
			uint32_t flt_pos = vptr->flt_pos;
			int32_t b = vptr->b, l = vptr->l;

			for (int j = 0; j < samples; j++)
			{
				uint32_t address;
				int32_t sample;
				uint8_t data;

				pos += (frac >> 12);
				frac &= 0xfff;

				if ((end > start) && ((start + pos) >= end))
				{
					pos = (end - start) - loop_start;
				}

				switch (sample_type)
				{
					case 0: // 16-bit linear, little-endian
						address = ((start << 1) + (pos << 1));
						sample = (int16_t)ram_read_word(address);
						break;

					case 1: // 12-bit non-linear, encoded into 8 bits
						address = (start + pos);
						data = rom_read_byte(address);
						sample = (data & 0xfc) >> 2;
						if (sample & 0x20)
							sample -= 0x40;
						sample <<= 4 + 2 * (~data & 3);
						break;

					default:
						logerror("l7a1045: unknown sample type %d\n", sample_type);
						sample = 0;
						break;
				}

				frac += step;

				// volume envelope processing
				env_pos += env_step;
				const int steps = (env_pos / 0x100);
				if (steps > 0)
				{
					if (env_volume < env_target)
					{
						env_volume += std::min(steps, (env_target - env_volume));
					}
					else if (env_volume > env_target)
					{
						env_volume -= std::min(steps, (env_volume - env_target));
					}
				}
				env_pos &= 0xff;

				// filter envelope processing
				flt_pos += flt_step;
				const int flt_steps = (flt_pos / 0x100);
				if (flt_steps > 0)
				{
					if (flt_freq < flt_target)
					{
						flt_freq += std::min(flt_steps, (flt_target - flt_freq));
					}
					else if (flt_freq > flt_target)
					{
						flt_freq -= std::min(flt_steps, (flt_freq - flt_target));
					}
				}
				flt_pos &= 0xff;

				// low pass filter processing using a chamberlin configuration
				const int32_t h = sample - l - b + ((flt_resonance * b) >> 4);
				b += (flt_freq * h) >> 15;
				l += (flt_freq * b) >> 15;

				const int32_t fout = l;
				out[j * OUTPUTS + 0] += s32((int64_t(fout) * int64_t(l_volume * env_volume)) >> 24);
				out[j * OUTPUTS + 1] += s32((int64_t(fout) * int64_t(r_volume * env_volume)) >> 24);
				if (send_out >= 0)
					out[j * OUTPUTS + send_out] += s32((int64_t(fout) * int64_t(send_level * env_volume)) >> 24);
			}

			vptr->pos = pos;
			vptr->frac = frac;
			vptr->env_volume = env_volume;
			vptr->env_pos = env_pos;
			vptr->flt_freq = flt_freq;
			vptr->flt_pos = flt_pos;
			vptr->b = b;
			vptr->l = l;
		}
	}
}

// the device map: 0-1 voice select, 2-7 the voice's registers, 8-9 control, c-d atomic
u16 l7a1045::read(offs_t offset, u16 mem_mask)
{
	if (offset >= 2 && offset <= 7)
		return voiceregs_r((offset - 2) >> 1);
	if (offset == 8 || offset == 9)
		return control_r();
	return 0;
}

void l7a1045::write(offs_t offset, u16 data, u16 mem_mask)
{
	if (offset <= 1)
		voice_select_w(0, data, mem_mask);
	else if (offset <= 7)
		voiceregs_w((offset - 2) >> 1, data);
	else if (offset <= 9)
		control_w(data);
	else if (offset == 0xc || offset == 0xd)
		atomic_w(data);
}

void l7a1045::voice_select_w(offs_t offset, uint16_t data, uint16_t mem_mask)
{
	// ---- rrrr 000c cccc
	// r = register
	// c = channel

	update();

	if (mem_mask & 0x00ff)
	{
		m_cur_channel = data;
		if (m_cur_channel & 0xe0)
		{
			logerror("l7a1045_sound_select_w unknown channel %01x\n", m_cur_channel & 0xff);
		}
		m_cur_channel &= 0x1f;
	}

	if (mem_mask & 0xff00)
	{
		m_cur_register = (data >> 8);
		if (m_cur_register > 0x0a)
		{
			logerror("l7a1045_sound_select_w unknown register %01x\n", m_cur_register & 0xff);
		}
		m_cur_register &= 0x0f;
	}
}

uint16_t l7a1045::voiceregs_r(offs_t offset)
{
	const l7a1045_voice *vptr = &m_voice[m_cur_channel];

	update();

	// refresh the register shadow from the current voice status if necessary
	switch (m_cur_register)
	{
	case L6028_Start:
	{
		const uint32_t current_addr = vptr->start + vptr->pos;

		// Reads back the current playback position in the original register 0 format.
		// (roadedge at 0x9DA0)
		m_regs[0][m_cur_channel] &= 0xfff0'0000'0000;
		m_regs[0][m_cur_channel] |= (uint64_t(current_addr) << 12);
		m_regs[0][m_cur_channel] |= vptr->frac & 0x0fff;
	}
	break;

	case L6028_Volume_Env:
		m_regs[L6028_Volume_Env][m_cur_channel] &= 0xffff'0000'ffff;
		m_regs[L6028_Volume_Env][m_cur_channel] |= (uint64_t(vptr->env_volume) << 16);
		break;

	case L6028_Filter_Env:
		m_regs[L6028_Filter_Env][m_cur_channel] &= 0xffff'0000'ffff;
		m_regs[L6028_Filter_Env][m_cur_channel] |= (uint64_t(vptr->flt_freq) << 16);
		break;
	}

	return (m_regs[m_cur_register][m_cur_channel] >> (offset * 16)) & 0xffff;
}

void l7a1045::voiceregs_w(offs_t offset, uint16_t data)
{
	l7a1045_voice* const vptr = &m_voice[m_cur_channel];
	const uint64_t offset_mask[3] = { 0xffff'ffff'0000ULL, 0xffff'0000'ffffULL, 0x0000'ffff'ffffULL };

	update();

	m_regs[m_cur_register][m_cur_channel] &= offset_mask[offset];
	m_regs[m_cur_register][m_cur_channel] |= (uint64_t(data) << (offset * 16));

	switch (m_cur_register)
	{
		// sample start address
		case L6028_Start:
			vptr->start = (m_regs[L6028_Start][m_cur_channel] >> 12) & 0x00ff'ffff;
			vptr->sample_type = (m_regs[L6028_Start][m_cur_channel] >> 36) & 0xf;

			// clear the pos on start writes (required for DMA tests on MPC3000, and HNG64 likes to leave voices keyed on and just write new parameters)
			vptr->pos = 0;
			vptr->frac = 0;
			// clear the filter state too
			vptr->flt_pos = 0;
			vptr->l = vptr->b = 0;

			if (offset == 2)
			{
				m_regs[L6028_Loop_Start][m_cur_channel] = 0;
			}
			break;

		// loop end address and pitch step
		case L6028_End:
			vptr->end = (m_regs[L6028_End][m_cur_channel] >> 12) & 0x00ff'fff0;

			vptr->step = m_regs[1][m_cur_channel] & 0xffff;
			if (offset == 2)
			{
				recalc_loop_start(vptr);
			}
			break;

		// loop start
		case L6028_Loop_Start:
			recalc_loop_start(vptr);
			break;

		// starting envelope volume
		case L6028_Volume_Env:
			vptr->env_volume = (m_regs[L6028_Volume_Env][m_cur_channel] & 0xffff'0000) >> 16;
			vptr->env_pos = 0;

			// MPC3000 writes timed 0 to offset 0 to silence
			if (offset == 0 && data == 0)
			{
				m_key &= ~(1 << m_cur_channel);
			}
			break;

		// envelope target volumes plus step rate
		case L6028_Volume_Env_Target:
			vptr->env_target = (m_regs[L6028_Volume_Env_Target][m_cur_channel] & 0xffff'0000) >> 16;
			vptr->env_step = m_regs[L6028_Volume_Env_Target][m_cur_channel] & 0xffff;
			break;

		// reg 5 = starting lowpass cutoff frequency
		case L6028_Filter_Env:
			if (vptr->flt_pos == 0)
			{
				vptr->flt_freq = (m_regs[L6028_Filter_Env][m_cur_channel] & 0xffff'0000) >> 16;
			}
			break;

		// reg 6 = lowpass cutoff target, resonance, and step rate
		case L6028_Filter_Env_Target:
			vptr->flt_target = (m_regs[L6028_Filter_Env_Target][m_cur_channel] & 0xfff0'0000) >> 16;
			vptr->flt_resonance = (m_regs[L6028_Filter_Env_Target][m_cur_channel] & 0x000f'0000) >> 16;
			vptr->flt_step = m_regs[6][m_cur_channel] & 0xffff;
			break;

		// voice main volume plus effects routing
		case L6028_Mixer_Params:
			vptr->r_volume = (m_regs[L6028_Mixer_Params][m_cur_channel] & 0xff);
			vptr->l_volume = (m_regs[L6028_Mixer_Params][m_cur_channel] >> 8) & 0xff;
			vptr->send_dest = (m_regs[L6028_Mixer_Params][m_cur_channel] >> 16) & 0xff;
			vptr->send_level = (m_regs[L6028_Mixer_Params][m_cur_channel] >> 24) & 0xff;
			break;
	}
}

void l7a1045::recalc_loop_start(l7a1045_voice *vptr)
{
	if (BIT(m_regs[L6028_End][m_cur_channel], 8 + 32))
	{
		const uint32_t length = vptr->end - vptr->start;

		vptr->loop_start = (m_regs[L6028_Loop_Start][m_cur_channel] & 0xffff'f000) >> 12;
		vptr->loop_start |= (m_regs[L6028_Loop_Start][m_cur_channel] & 0x000f) << 20;

		vptr->loop_start = vptr->end - vptr->loop_start;
		if (vptr->loop_start > length)
		{
			vptr->loop_start = length;
		}
	}
	else
	{
		const uint32_t multiplier = (((m_regs[L6028_Loop_Start][m_cur_channel] & 0xffff'0000) >> 16) ^ 0xffff) + 1;
		const uint32_t base = m_regs[L6028_Loop_Start][m_cur_channel] & 0xffff;
		vptr->loop_start = (base * multiplier) >> 12;
	}
}

uint16_t l7a1045::control_r()
{
	return m_control;
}

void l7a1045::control_w(uint16_t data)
{
	update();

	m_control = data;

	if (BIT(data, CONTROL_KEY_ON))
	{
		l7a1045_voice* const vptr = &m_voice[m_cur_channel];

		vptr->frac = 0;
		vptr->pos = 0;
		m_key |= 1 << m_cur_channel;

		recalc_loop_start(vptr);
	}

	if (BIT(m_control, CONTROL_DMA_START))
	{
		// 8x the sample period
		m_dma_tick = m_sched.now() + DMA_TICKS;
		m_dma_rem = DMA_REM;
		m_dma_timer.adjust_at(m_dma_tick + (m_dma_rem != 0));
	}
	else
	{
		m_dma_timer.adjust_at(NEVER);
	}
}

void l7a1045::atomic_w(uint16_t data)
{
	m_regs[m_cur_register][m_cur_channel] = 0;
}

uint16_t l7a1045::dma_r16_cb()
{
	const offs_t byteoffs = (m_voice[0].start << 1) + (m_voice[0].pos << 1);

	m_drq_handler(CLEAR_LINE);

	m_voice[0].pos++;
	if (m_voice[0].sample_type == 1)
		return rom_read_word(byteoffs);

	return ram_read_word(byteoffs);
}

void l7a1045::dma_w16_cb(uint16_t data)
{
	const offs_t byteoffs = (m_voice[0].start << 1) + (m_voice[0].pos << 1);

	m_drq_handler(CLEAR_LINE);

	// a write to ROM goes nowhere
	if (m_voice[0].sample_type != 1)
		ram_write_word(byteoffs, data);

	m_voice[0].pos++;
}

void l7a1045::dma_timer_callback()
{
	m_drq_handler(ASSERT_LINE);
	m_dma_tick += DMA_TICKS;
	m_dma_rem += DMA_REM;
	if (m_dma_rem >= DMA_DEN)
	{
		m_dma_rem -= DMA_DEN;
		m_dma_tick++;
	}
	m_dma_timer.adjust_at(m_dma_tick + (m_dma_rem != 0));
}
