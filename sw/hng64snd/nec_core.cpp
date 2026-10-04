// license:BSD-3-Clause
// copyright-holders:Bryan McPhail
// From MAME src/devices/cpu/nec/nec.cpp (PROVENANCE.md): the V33's construction, reset,
// interrupts and run loop; the instruction files in nec/ are MAME's, unchanged.

#include "nec_core.h"
#include <algorithm>

typedef uint8_t BOOLEAN;
typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;

#include "nec/necpriv.ipp"

// MAME's debugger hooks, unused here
#define debugger_exception_hook(n) do {} while (0)
// MAME's logmacro.h, as nec.cpp sets it up: nothing logged
#define LOG_BUSLOCK (1 << 1)
#define LOGMASKED(mask, ...) do {} while (0)

inline offs_t nec_common_device::v33_translate(offs_t addr)
{
	if (m_xa)
		return uint32_t(m_v33_transtable[(addr >> 14) & 63]) << 14 | (addr & 0x03fff);
	else
		return addr & 0xfffff;
}

void nec_common_device::prefetch()
{
	m_prefetch_count--;
}

// MAME's two loops, a byte a cycle, in closed form: the V33's m_prefetch_cycles is 1
void nec_common_device::do_prefetch()
{
	/* The implementation is not accurate, but comes close.
	 * It does not respect that the V30 will fetch two bytes
	 * at once directly, but instead uses only 2 cycles instead
	 * of 4. There are however only very few sources publicly
	 * available and they are vague.
	 */
	if (m_prefetch_count < 0)
	{
		// a byte from m_cur_cycles while it is over 1, the rest from m_icount
		const int32_t n = -m_prefetch_count;
		const int32_t k = std::min(n, std::max(m_cur_cycles - 1, 0));
		m_cur_cycles -= k;
		m_icount -= n - k;
		m_prefetch_count = 0;
	}

	if (m_prefetch_reset)
	{
		m_prefetch_count = 0;
		m_prefetch_reset = 0;
		return;
	}

	if (m_cur_cycles >= 1 && m_prefetch_count < m_prefetch_size)
	{
		const int32_t k = std::min<int32_t>(m_cur_cycles, m_prefetch_size - m_prefetch_count);
		m_cur_cycles -= k;
		m_prefetch_count += k;
	}
}

uint8_t nec_common_device::fetch()
{
	prefetch();
	return m_dr8((Sreg(PS)<<4) + m_ip++);
}

uint16_t nec_common_device::fetchword()
{
	uint16_t r = fetch();
	r |= (fetch()<<8);
	return r;
}

#include "nec/necinstr.h"
#include "nec/necmacro.h"
#include "nec/necea.h"
#include "nec/necmodrm.h"

static uint8_t parity_table[256];

uint8_t nec_common_device::fetchop()
{
	prefetch();
	return m_dr8((Sreg(PS)<<4) + m_ip++);
}

uint32_t nec_common_device::pc() const
{
	return PC();
}

/***************************************************************************/

// MAME's constructor for the V33 (v33_base_device: 16-bit, prefetch 6 bytes at 1 cycle, no
// divide quirk) and its device_start
nec_common_device::nec_common_device(nec_space &program)
{
	unsigned int i, j, c;

	static const WREGS wreg_name[8]={ AW, CW, DW, BW, SP, BP, IX, IY };
	static const BREGS breg_name[8]={ AL, CL, DL, BL, AH, CH, DH, BH };

	for (i = 0; i < 256; i++)
	{
		for (j = i, c = 0; j > 0; j >>= 1)
			if (j & 1) c++;
		parity_table[i] = !(c & 1);
	}

	for (i = 0; i < 256; i++)
	{
		Mod_RM.reg.b[i] = breg_name[(i & 0x38) >> 3];
		Mod_RM.reg.w[i] = wreg_name[(i & 0x38) >> 3];
	}

	for (i = 0xc0; i < 0x100; i++)
	{
		Mod_RM.RM.w[i] = wreg_name[i & 7];
		Mod_RM.RM.b[i] = breg_name[i & 7];
	}

	m_no_interrupt = 0;
	m_cur_cycles = 0;
	m_prefetch_count = 0;
	m_prefetch_reset = 0;
	m_prefix_base = 0;
	m_seg_prefix = 0;
	m_EA = 0;
	m_EO = 0;
	m_E16 = 0;
	m_ip = 0;
	m_prev_ip = 0;
	m_rep_ip = 0;

	memset(m_regs.w, 0x00, sizeof(m_regs.w));
	memset(m_sregs, 0x00, sizeof(m_sregs));
	memset(m_v33_transtable, 0x00, sizeof(m_v33_transtable));

	m_program = &program;
	m_icount = 0;
	m_xa = false;
}

void nec_common_device::device_reset()
{
	memset( &m_regs.w, 0, sizeof(m_regs.w));

	m_ip = 0;
	m_prev_ip = 0;
	m_rep_ip = 0;
	m_TF = 0;
	m_IF = 0;
	m_DF = 0;
	m_MF = 1;
	m_em = 1;
	m_SignVal = 0;
	m_AuxVal = 0;
	m_OverVal = 0;
	m_ZeroVal = 1;
	m_CarryVal = 0;
	m_ParityVal = 1;
	m_pending_irq = 0;
	m_nmi_state = 0;
	m_irq_state = 0;
	m_poll_state = 1;
	m_halted = 0;
	m_rep_params = 0;

	if (m_chip_type == V33_TYPE)
		m_xa = false;

	Sreg(PS) = 0xffff;
	Sreg(SS) = 0;
	Sreg(DS0) = 0;
	Sreg(DS1) = 0;

	CHANGE_PC;
}


void nec_common_device::nec_interrupt(unsigned int_num, int/*INTSOURCES*/ source)
{
	uint32_t dest_seg, dest_off;

	m_rep_params = 0;
	i_pushf();
	m_TF = m_IF = 0;
	m_MF = 1;

	if (source == INT_IRQ)  /* get vector */
		int_num = irq_acknowledge();
	debugger_exception_hook(int_num);

	dest_off = read_mem_word(int_num*4);
	dest_seg = read_mem_word(int_num*4+2);

	PUSH(Sreg(PS));
	PUSH(m_ip);
	m_prev_ip = m_ip = (WORD)dest_off;
	Sreg(PS) = (WORD)dest_seg;
	CHANGE_PC;
}

void nec_common_device::nec_trap()
{
	(this->*s_nec_instruction[fetchop()])();
	nec_interrupt(NEC_TRAP_VECTOR, BRK);
}

void nec_common_device::nec_brk(unsigned int_num)
{
	if (m_chip_type != V33_TYPE)
	{
		m_em = 0;
		m_MF = 0;
		i_pushf();
		PUSH(Sreg(PS));
		PUSH(m_ip);
	}
	m_prev_ip = m_ip = read_mem_word(int_num*4);
	Sreg(PS) = read_mem_word(int_num*4+2);
	CHANGE_PC;
}

void nec_common_device::external_int()
{
	if (m_pending_irq & NMI_IRQ)
	{
		nec_interrupt(NEC_NMI_VECTOR, NMI_IRQ);
		m_pending_irq &= ~NMI_IRQ;
	}
	else if (m_pending_irq)
	{
		/* the actual vector is retrieved after pushing flags */
		/* and clearing the IF */
		nec_interrupt((uint32_t)-1, INT_IRQ);
		m_irq_state = CLEAR_LINE;
		m_pending_irq &= ~INT_IRQ;
	}
}

/****************************************************************************/
/*                             OPCODES                                      */
/****************************************************************************/

#include "nec/necinstr.hxx"
#include "nec/nec80inst.hxx"

/*****************************************************************************/

void nec_common_device::set_int_line(int state)
{
	m_irq_state = state;
	if (state == CLEAR_LINE)
		m_pending_irq &= ~INT_IRQ;
	else
	{
		m_pending_irq |= INT_IRQ;
		m_halted = 0;
	}
}

void nec_common_device::set_nmi_line(int state)
{
	if (m_nmi_state == state)
		return;
	m_nmi_state = state;
	if (state != CLEAR_LINE)
	{
		m_pending_irq |= NMI_IRQ;
		m_halted = 0;
	}
}

void nec_common_device::set_poll_line(int state)
{
	m_poll_state = state;
}

#ifdef NEC_PROFILE
uint32_t nec_profile[0x100000];
#endif

int nec_common_device::execute_run(int cycles)
{
	m_slice = cycles;
	m_icount = cycles;

	if (m_halted)
	{
		m_icount = 0;
		return cycles;
	}

	while(m_icount>0)
	{
		m_prev_ip = m_ip;

		// Dispatch IRQ
		if (m_pending_irq && m_no_interrupt==0)
		{
			if (m_pending_irq & NMI_IRQ)
				external_int();
			else if (m_IF)
				external_int();
		}

		// No interrupt allowed between last instruction and this one
		if (m_no_interrupt)
			m_no_interrupt--;

		m_cur_cycles = 0;
#ifdef NEC_PROFILE
		nec_profile[PC() & 0xfffff]++;
#endif

		if (m_rep_params)
			cont_rep();
		else
		{
			if (m_MF)
				(this->*s_nec_instruction[fetchop()])();
			else
				(this->*s_nec80_instruction[fetchop()])();
		}
		do_prefetch();
	}
	return m_slice - m_icount;
}
