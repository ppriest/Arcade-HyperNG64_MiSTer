-- Capture video/machine state from MAME at a chosen frame. Driven by
-- scripts/mame_capture.py, which passes scripts/mame/regions.json as:
--
--   CORE_OUT     output directory
--   CORE_FRAME   frame to capture at
--   CORE_CPU     device tag, e.g. :maincpu
--   CORE_SPACE   address space, e.g. program
--   CORE_BYTES   bus width in bytes (1, 2, 4, 8)
--   CORE_BIG     1 if the bus is big-endian
--   CORE_READ    "name:hexlo:hexhi,..."  RAM readable through the CPU's view
--   CORE_WTAP    "name:hexlo:hexhi,..."  write-only registers, rebuilt from writes
--   CORE_WLOG    "name:hexlo:hexhi,..."  optional: every write to these, in order, to
--                wlog.trace ("seq w addr mask data vpos": systrace.lua's columns, the
--                last the beam's line when the write was made), with
--                "# frame N" at each frame and "# capture" where the capture is taken.
--                The 3D model replays it from boot (scripts/render_3d.py).
--
-- Readable RAM is read through the CPU's address space: that is what the CPU
-- would read, handlers and umask included, which is what the RTL must match.
-- Write-only registers cannot be read back; MAME keeps them inside the device.
-- They are rebuilt from a write tap installed before the machine runs: the last
-- byte written to each address is the register state at the captured frame.
--
-- Banked memory (a window whose page is set by a register) needs the bank
-- tracked per write. Add that per core below the generic taps; see the
-- KonamiGX core's scripts/mame/capture.lua for a worked example.

local OUT   = os.getenv("CORE_OUT") or "capture"
local FRAME = tonumber(os.getenv("CORE_FRAME") or "1200")
local BYTES = tonumber(os.getenv("CORE_BYTES") or "2")
local BIG   = os.getenv("CORE_BIG") ~= "0"
local m     = manager.machine

local function mkdir(p) os.execute('mkdir "' .. p:gsub("/", "\\") .. '" 2>nul') end
mkdir(OUT)

-- An error inside a Lua callback is silent: MAME keeps running and exits 0
-- having produced nothing. Every callback goes through guard(), which writes
-- the failure where the Python side reads it back.
local function guard(what, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            local f = io.open(OUT .. "/ERROR.txt", "a")
            if f then f:write(what, ": ", tostring(err), "\n"); f:close() end
            print("CORE_CAPTURE_ERROR " .. what .. ": " .. tostring(err))
            error(err)
        end
        return ok
    end
end

local function wr(name, bytes)
    local f = assert(io.open(OUT .. "/" .. name, "wb"))
    f:write(bytes)
    f:close()
end

local function ranges(s)
    local out = {}
    for spec in string.gmatch(s or "", "([^,]+)") do
        local name, lo, hi = spec:match("^([^:]+):(%x+):(%x+)$")
        assert(name, "bad range spec: " .. spec)
        out[#out + 1] = { name = name, lo = tonumber(lo, 16), hi = tonumber(hi, 16) }
    end
    return out
end

-- Global on purpose: an autoboot chunk's locals are collected once the chunk
-- returns, and taps and notifiers held only by a local stop firing silently.
core_subs = {}

local sp = m.devices[os.getenv("CORE_CPU") or ":maincpu"].spaces[os.getenv("CORE_SPACE") or "program"]

-- Split a tap's data by the mask actually driven, not by an assumed width.
local function note(tbl, base, addr, data, mask)
    for b = 0, BYTES - 1 do
        local sh = BIG and (BYTES - 1 - b) * 8 or b * 8
        if (mask >> sh) & 0xff ~= 0 then
            tbl[(addr - base) + b] = (data >> sh) & 0xff
        end
    end
end

local regs = {}
local WTAP = ranges(os.getenv("CORE_WTAP"))
for _, r in ipairs(WTAP) do
    regs[r.name] = {}
    core_subs[#core_subs + 1] = sp:install_write_tap(r.lo, r.hi, "core_" .. r.name,
        guard("tap_" .. r.name, function(offset, data, mask)
            note(regs[r.name], r.lo, offset, data, mask)
        end))
end

-- The write log: a counter per frame notifier, as systrace.lua numbers its markers.
local WLOG = ranges(os.getenv("CORE_WLOG"))
local wlog, wseq, wframe = nil, 0, 0
local wscr = m.screens[":screen"]
-- The beam's line: MAME's Lua gives no vpos, only the time until line 0 comes round again.
local function vpos()
    local fp, sp = wscr.frame_period, wscr.scan_period
    local total = math.floor(fp / sp + 0.5)
    return math.floor((fp - wscr:time_until_pos(0)) / sp + 1e-6) % total
end
if #WLOG > 0 then
    wlog = assert(io.open(OUT .. "/wlog.trace", "w"))
    wlog:write("# writes to ", os.getenv("CORE_WLOG"), "\n")
    for _, r in ipairs(WLOG) do
        core_subs[#core_subs + 1] = sp:install_write_tap(r.lo, r.hi, "core_wlog_" .. r.name,
            guard("wlog_" .. r.name, function(offset, data, mask)
                wseq = wseq + 1
                wlog:write(string.format("%d\tw\t%08X\t%08X\t%08X\t%d\n", wseq, offset,
                                         mask & 0xffffffff, data & 0xffffffff, vpos()))
            end))
    end
end

local function read_block(lo, hi)
    local t = {}
    for a = lo, hi do t[#t + 1] = string.char(sp:read_u8(a)) end
    return table.concat(t)
end

local function dump_sparse(name, tbl, size)
    local t = {}
    for i = 0, size - 1 do t[i + 1] = string.char(tbl[i] or 0) end
    wr(name, table.concat(t))
end

local done = false
core_subs[#core_subs + 1] = emu.add_machine_frame_notifier(guard("frame", function()
    if done then return end
    local scr = m.screens[":screen"]
    local capture = scr:frame_number() >= FRAME
    if wlog then
        wframe = wframe + 1
        if capture then wlog:write("# capture\n") end
        wlog:write(string.format("# frame %d\n", wframe))
    end
    if not capture then return end
    done = true
    if wlog then wlog:close() end

    for _, r in ipairs(ranges(os.getenv("CORE_READ"))) do
        wr(r.name .. ".bin", read_block(r.lo, r.hi))
    end
    for _, r in ipairs(WTAP) do
        dump_sparse("reg_" .. r.name .. ".bin", regs[r.name], r.hi - r.lo + 1)
    end

    scr:snapshot(OUT .. "/reference.png")

    local f = assert(io.open(OUT .. "/manifest.txt", "w"))
    f:write("set ", m.system.name, "\n")
    f:write("mame ", emu.app_version(), "\n")
    f:write("frame ", tostring(scr:frame_number()), "\n")
    f:write("screen ", tostring(scr.width), "x", tostring(scr.height), "\n")
    f:close()

    print("CORE_CAPTURE_OK " .. OUT)
    m:exit()
end))
