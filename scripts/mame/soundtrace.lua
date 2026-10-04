-- The sound interface from both sides, as the reference for the ARM sound bridge and the bench
-- of its emulator. Driven by scripts/mame_sound_trace.py:
--
--   CORE_OUT, CORE_TAG, CORE_FRAMES     output dir, filename prefix, frames to log
--   CORE_SAMPLES                        file to dump the l7a1045 region to (skipped if empty)
--
-- Logged, each with the frame and MAME's time in microseconds (the executing CPU's, to the ns):
--   main CPU  writes to the sound CPU enable (0x6f000000), every access to the mailbox
--             (0x68000000-0x6800000f), and sound RAM (0x60000000-0x603fffff) accesses once the
--             sound CPU has been enabled; before that, sound RAM traffic is counted per frame
--   V53A      I/O reads and writes of the L7A1045 (0x00-0x0f), port 0x80, the latches
--             (0x100-0x10f) and the banks (0x200-0x21f)
-- At each 0x55AA to the enable, sound RAM as the V53A sees it (byte n at its address n) goes to
-- <tag>_sndram_<k>.bin.

local OUT     = os.getenv("CORE_OUT") or "."
local TAG     = os.getenv("CORE_TAG") or "trace"
local FRAMES  = tonumber(os.getenv("CORE_FRAMES") or "600")
local SAMPLES = os.getenv("CORE_SAMPLES") or ""

local mach  = manager.machine
local main  = mach.devices[":maincpu"].spaces["program"]
local snd   = mach.devices[":audiocpu"].spaces["io"]

local f = assert(io.open(string.format("%s/%s_sound.trace", OUT, TAG), "w"))
f:write("# frame\tus\tside\trw\taddr\tmask\tdata\n")

local frame, done, first_err, enabled, dumping, enables = 0, false, nil, false, false, 0
local pre_w, pre_r = 0, 0

local function us() return mach.time:as_double() * 1e6 end

local function log(side, rw, offset, data, mask)
    f:write(string.format("%d\t%.3f\t%s\t%s\t%08X\t%08X\t%08X\n", frame, us(), side, rw, offset,
                          mask, data))
end

local function guard(fn)
    return function(offset, data, mask)
        if not done and not dumping then
            local ok, err = pcall(fn, offset, data, mask)
            if not ok and not first_err then first_err = tostring(err) end
        end
        return data
    end
end

local function stop()
    if done then return end
    done = true
    if first_err then f:write("# FIRST ERROR: " .. first_err .. "\n") end
    f:close()
    print(string.format("SOUNDTRACE %d frames to %s/%s_sound.trace", frame, OUT, TAG))
    mach:exit()
end

-- 0x60200000 up is the V53A's RAM; the main CPU's big-endian bytes are the V53A's in order
local function dump_sndram()
    dumping = true
    local o = assert(io.open(string.format("%s/%s_sndram_%d.bin", OUT, TAG, enables), "wb"))
    for base = 0x60200000, 0x603fffff, 0x10000 do
        local t = {}
        for a = base, base + 0xffff, 4 do t[#t + 1] = string.pack(">I4", main:read_u32(a)) end
        o:write(table.concat(t))
    end
    o:close()
    dumping = false
    f:write(string.format("# sound RAM %d at %.3f us\n", enables, us()))
    enables = enables + 1
end

local function dump_samples()
    local r = mach.memory.regions[":l7a1045"]
    local o = assert(io.open(SAMPLES, "wb"))
    for base = 0, r.size - 1, 0x10000 do
        local t = {}
        for a = base, base + 0xffff, 4 do t[#t + 1] = string.pack("<I4", r:read_u32(a)) end
        o:write(table.concat(t))
    end
    o:close()
end
if SAMPLES ~= "" then dump_samples() end

-- Global, so the taps are not collected.
core_subs = {}
local function tap(space, kind, lo, hi, name, fn)
    local inst = kind == "w" and space.install_write_tap or space.install_read_tap
    core_subs[#core_subs + 1] = inst(space, lo, hi, name, guard(fn))
end

tap(main, "w", 0x6f000000, 0x6f000003, "snd_en", function(o, d, m)
    log("main", "w", o, d, m)
    if (m & 0xffff0000) ~= 0 then
        local cmd = (d >> 16) & 0xffff
        if cmd == 0x55aa then
            dump_sndram()
            enabled = true
        elseif cmd == 0xaa55 then
            enabled = false
        end
    end
end)
tap(main, "w", 0x68000000, 0x6800000f, "mbox_w", function(o, d, m) log("main", "w", o, d, m) end)
tap(main, "r", 0x68000000, 0x6800000f, "mbox_r", function(o, d, m) log("main", "r", o, d, m) end)
tap(main, "w", 0x60000000, 0x603fffff, "sram_w", function(o, d, m)
    if enabled then log("main", "w", o, d, m) else pre_w = pre_w + 1 end
end)
tap(main, "r", 0x60000000, 0x603fffff, "sram_r", function(o, d, m)
    if enabled then log("main", "r", o, d, m) else pre_r = pre_r + 1 end
end)
tap(snd, "w", 0x0000, 0x000f, "v53_dsp_w", function(o, d, m) log("v53", "w", o, d, m) end)
tap(snd, "r", 0x0000, 0x000f, "v53_dsp_r", function(o, d, m) log("v53", "r", o, d, m) end)
tap(snd, "w", 0x0080, 0x0081, "v53_80_w", function(o, d, m) log("v53", "w", o, d, m) end)
tap(snd, "w", 0x0100, 0x010f, "v53_com_w", function(o, d, m) log("v53", "w", o, d, m) end)
tap(snd, "r", 0x0100, 0x010f, "v53_com_r", function(o, d, m) log("v53", "r", o, d, m) end)
tap(snd, "w", 0x0200, 0x021f, "v53_bank", function(o, d, m) log("v53", "w", o, d, m) end)

core_subs[#core_subs + 1] = emu.add_machine_frame_notifier(function()
    if done then return end
    frame = frame + 1
    if pre_w + pre_r > 0 then
        f:write(string.format("# frame %d: sound RAM %d writes, %d reads before enable\n", frame,
                              pre_w, pre_r))
        pre_w, pre_r = 0, 0
    end
    if frame >= FRAMES then stop() end
end)
