// license:BSD-3-Clause
// copyright-holders:Patrick Mackinlay, Wilbert Pol, Nathan Woods, Curt Coder
// The V53A: the V33 core and its TCU, ICU and DMAU, from MAME (PROVENANCE.md):
//   v53a       src/devices/cpu/nec/v5x.cpp (v53_device, device_v5x_interface)
//   pit_counter, pit8254   src/devices/machine/pit8253.cpp
//   pic8259    src/devices/machine/pic8259.cpp (v5x_icu_device)
//   v5x_dmau   src/devices/machine/am9517a.cpp (am9517a, upd71071, v5x_dmau_device)
// The SCU (an i8251 subset) is a stub: nothing is attached to it on hng64.
#pragma once

#include <functional>
#include "nec_core.h"
#include "emu_sched.h"

// ---- TCU ------------------------------------------------------------------------------------

class pit_counter
{
public:
	pit_counter(sched &s, int index, std::function<void(int)> out);
	void start();    // device_start's zerofill
	void reset();

	u8 read();
	void readback(int command);
	void control_w(u8 data);
	void count_w(u8 data);
	void gate_w(int state);
	// set_clockin as a period in ticks; 0 stops the clock
	void set_period(s64 ticks);

private:
	void adjust_timer(s64 target);
	uint32_t adjusted_count() const;
	void decrease_counter_value(int64_t cycles);
	void load_counter_value();
	void set_output(int output);
	void flush_output();
	void simulate(int64_t elapsed_cycles);
	void update();
	uint16_t masked_value() const;
	void load_count(uint16_t newcount);
	bool edge_sensitive_gate() const;

	sched &m_sched;
	int m_index;
	std::function<void(int)> m_out;
	s64 m_period = 0;           // m_clock_period; 0 for MAME's m_clockin == 0
	int m_period_shift = 0;     // log2(m_period): it is 4 << n, and the ARM has no divide
	s64 m_last_updated = 0;
	s64 m_next_update = NEVER;
	emu_timer m_update_timer;

	uint8_t m_control;
	uint8_t m_status;
	uint8_t m_lowcount;
	bool m_rmsb;
	bool m_wmsb;
	int m_output;
	int m_output_pin;
	uint16_t m_count;
	uint16_t m_value;
	uint16_t m_latch;
	int m_gate;
	int m_gate_input;
	int m_gate_rose;
	int m_latched_count;
	int m_latched_status;
	int m_null_count;
	int m_phase;
};

class pit8254
{
public:
	pit8254(sched &s, std::function<void(int, int)> out);
	void start();
	void reset();
	u8 read(offs_t offset);
	void write(offs_t offset, u8 data);
	pit_counter &counter(int i) { return *m_counter[i]; }

private:
	pit_counter m_c0, m_c1, m_c2;
	pit_counter *m_counter[3];
};

// ---- ICU ------------------------------------------------------------------------------------

class pic8259
{
public:
	pic8259(sched &s, std::function<void(int)> out_int)
		: m_out_int_func(std::move(out_int)), m_irq_timer(s, [this] { irq_timer_tick(); }), m_sched(s) {}
	void reset();
	u8 read(offs_t offset);
	void write(offs_t offset, u8 data);
	void ir_w(int irq, int state) { set_irq_line(irq, state); }
	u8 acknowledge();

private:
	enum class state_t : u8 { ICW1, ICW2, ICW3, ICW4, READY };

	// run from a zero-length timer, as in MAME: an acknowledge must not raise INT again before the
	// core has cleared its pending interrupt
	void irq_timer_tick();
	void set_irq_line(int irq, int state);

	std::function<void(int)> m_out_int_func;
	emu_timer m_irq_timer;
	sched &m_sched;
	state_t m_state = state_t::READY;
	uint8_t m_isr = 0, m_irr = 0, m_prio = 0, m_imr = 0, m_irq_lines = 0;
	uint8_t m_input = 0, m_ocw3 = 0, m_master = 1;
	uint8_t m_level_trig_mode = 0, m_vector_size = 0, m_cascade = 0, m_icw4_needed = 0;
	uint32_t m_vector_addr_low = 0;
	uint8_t m_base = 0, m_vector_addr_high = 0, m_slave = 0, m_nested = 0, m_mode = 0;
	uint8_t m_auto_eoi = 0, m_is_x86 = 0;
	int8_t m_current_level = -1;
	uint8_t m_inta_sequence = 0;
};

// ---- DMAU -----------------------------------------------------------------------------------

struct dmau_bus
{
	std::function<void(int)> out_hreq;
	std::function<u8(offs_t)> in_memr;                  // 8-bit memory read
	std::function<u16(int, offs_t)> in_io16r;           // 16-bit I/O read, by channel
	std::function<void(int, offs_t, u16)> out_io16w;    // 16-bit I/O write, by channel
};

class v5x_dmau
{
public:
	v5x_dmau(sched &s, dmau_bus bus);
	void start();
	void reset() { soft_reset(); m_selected_channel = 0; m_base = 0; }
	u8 read(offs_t offset);
	void write(offs_t offset, u8 data);
	void hack_w(int state);
	void dreq_w(int channel, int state) { dma_request(channel, state); }

private:
	void soft_reset();
	void trigger();
	void execute_step();
	void dma_request(int channel, bool state);
	void mask_channel(int channel, bool state);
	bool is_request_active(int channel);
	bool is_software_request_active(int channel);
	void set_hreq(int state);
	void set_dack() {}
	void set_eop(int state) { m_eop = state; }
	int get_state1(bool msb_changed);
	void dma_read();
	void dma_write();
	void dma_advance();
	void end_of_process();
	int transfer_size(int channel) const { return (m_channel[channel].m_mode & 0x1) ? 2 : 1; }

	sched &m_sched;
	dmau_bus m_bus;
	emu_timer m_step;           // the next DMA clock while not suspended
	bool m_suspended = true;

	uint32_t m_address_mask = 0x00ffffff;
	struct
	{
		uint32_t m_address;
		uint32_t m_count;
		uint32_t m_base_address;
		uint16_t m_base_count;
		uint8_t m_mode;
	} m_channel[4];

	int m_msb = 0;
	int m_hreq = -1;
	int m_hack = 0;
	int m_ready = 1;
	int m_eop = 1;
	int m_state = 0;
	int m_current_channel = -1;
	int m_last_channel = 3;
	uint8_t m_command = 0;
	uint8_t m_command_high = 0;
	uint8_t m_mask = 0x0f;
	uint8_t m_status = 0;
	uint16_t m_temp = 0;
	uint8_t m_request = 0;
	int m_selected_channel = 0;
	int m_base = 0;
};

// ---- the V53A ---------------------------------------------------------------------------------

// What the board puts on the V53A's pins
struct v53_board
{
	std::function<u16(offs_t, u16)> io_r16;              // word address (even), lane mask
	std::function<void(offs_t, u16, u16)> io_w16;
	std::function<void(int, int)> tout;                  // TCU outputs, by counter
	dmau_bus dma;
};

class v53a : public nec_common_device
{
public:
	v53a(nec_space &program, sched &s, v53_board board);

	void start();
	// the reset on RESET's release: the V5x registers, the core, and every peripheral
	void reset();
	// v5x_set_input: INT0-7 go through the ICU
	void set_input(int irqline, int state) { m_icu.ir_w(irqline, state); }
	void dreq_w(int channel, int state) { if (!(m_SCTL & 0x02)) m_dmau.dreq_w(channel, state); }
	void hack_w(int state) { if (!(m_SCTL & 0x02)) m_dmau.hack_w(state); }

	u32 scu_accesses() const { return m_scu_accesses; }
	// the internal registers' traffic: (rw 'r'/'w', the io address, data)
	std::function<void(char, offs_t, u8)> m_int_log;

protected:
	u8 io_read_byte(offs_t a) override;
	u16 io_read_word(offs_t a) override;
	void io_write_byte(offs_t a, u8 v) override;
	void io_write_word(offs_t a, u16 v) override;
	int irq_acknowledge() override { return m_icu.acknowledge(); }

private:
	enum { OPSEL_DS = 0x01, OPSEL_IS = 0x02, OPSEL_TS = 0x04, OPSEL_SS = 0x08, OPSEL_MASK = 0x0f };

	u16 OPHA() const { return (m_OPHA << 8) & 0xff00; }
	bool check_OPHA(offs_t a) const
	{
		return ((m_OPSEL & OPSEL_MASK) != 0) && (m_OPHA != 0xff) && ((a & 0xff00) == OPHA());
	}

	// nec_common_device's io space: the internal port map at 0xff00 up, else the board
	u8 nec_io_read_byte(offs_t a);
	u16 nec_io_read_word(offs_t a);
	void nec_io_write_byte(offs_t a, u8 v);
	void nec_io_write_word(offs_t a, u16 v);
	u8 internal_port_r(offs_t a);
	void internal_port_w(offs_t a, u8 v);

	// AS_INTERNAL_IO: the relocatable peripherals, as install_peripheral_io lays them out
	u8 internal_io_read_byte(offs_t a);
	void internal_io_write_byte(offs_t a, u8 v);
	int peripheral_at(offs_t a, int &offset) const;
	u8 scu_r(offs_t offset);
	void scu_w(offs_t offset, u8 data);

	void tcu_clock_update();

	sched &m_sched;
	v53_board m_board;
	pit8254 m_tcu;
	pic8259 m_icu;
	v5x_dmau m_dmau;

	u8 m_OPSEL = 0, m_SULA = 0, m_TULA = 0, m_IULA = 0, m_DULA = 0, m_OPHA = 0, m_TCKS = 0;
	u8 m_BRC = 0, m_SCTL = 0;
	u8 m_scu_simk = 0x03;
	u32 m_scu_accesses = 0;
};
