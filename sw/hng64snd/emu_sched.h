// SPDX-License-Identifier: GPL-3.0-or-later
// Time for the sound board: one 64-bit count of the V53A's 32 MHz input clock (MAME runs the V33
// core at that clock, a cycle a tick). The few MAME timers the ported devices use become entries
// here; the board runs the CPU up to the earliest and fires it.
#pragma once

#include <functional>
#include <vector>
#include "mame_shim.h"

constexpr s64 NEVER = INT64_MAX;

class sched;

class emu_timer
{
public:
	emu_timer(sched &s, std::function<void()> fn);
	// fire at tick t (NEVER disarms); a time already past fires at the next chance
	void adjust_at(s64 t);
	s64 when() const { return m_when; }

private:
	friend class sched;
	sched &m_sched;
	std::function<void()> m_fn;
	s64 m_when = NEVER;
};

class sched
{
public:
	// MAME's machine().time(): the CPU's local time while it runs, a timer's own time while it
	// fires
	s64 now() const { return m_now(); }
	std::function<s64()> m_now;
	// called when a timer is armed earlier than the CPU's slice end (MAME's abort_timeslice)
	std::function<void(s64)> m_armed;

	s64 next_event() const
	{
		s64 t = NEVER;
		for (auto *x : m_timers)
			if (x->m_when < t) t = x->m_when;
		return t;
	}

	// fires the earliest timer due at or before t; false when none is. Sets m_firing to its
	// time for now() to return.
	bool fire_one(s64 t)
	{
		emu_timer *e = nullptr;
		for (auto *x : m_timers)
			if (x->m_when <= t && (!e || x->m_when < e->m_when)) e = x;
		if (!e) return false;
		m_firing = e->m_when;
		e->m_when = NEVER;
		e->m_fn();
		return true;
	}
	s64 m_firing = 0;

private:
	friend class emu_timer;
	std::vector<emu_timer *> m_timers;
};

inline emu_timer::emu_timer(sched &s, std::function<void()> fn) : m_sched(s), m_fn(std::move(fn))
{
	s.m_timers.push_back(this);
}

inline void emu_timer::adjust_at(s64 t)
{
	m_when = t;
	if (t != NEVER && m_sched.m_armed) m_sched.m_armed(t);
}
