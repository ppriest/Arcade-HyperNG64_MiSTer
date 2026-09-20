-- Sample the video registers every frame, to find frames that use a given feature.
-- Driven by scripts/scan_video.py.
--
--   CORE_OUT     output file
--   CORE_FRAMES  how many frames to sample
--   CORE_SPRSTEP sample the sprite list every this many frames (0 to skip)
--
-- One CSV line a frame: the fourteen videoregs, three tcram words, two sprite regs, and the
-- sprite-list flags when they were sampled. Everything is read through the CPU's view, as
-- capture.lua does.

local OUT      = os.getenv("CORE_OUT") or "scan.csv"
local FRAMES   = tonumber(os.getenv("CORE_FRAMES") or "3600")
local SPRSTEP  = tonumber(os.getenv("CORE_SPRSTEP") or "30")
local m        = manager.machine

core_subs = {}

local sp = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(OUT, "w"))

local function guard(what, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            print("CORE_SCAN_ERROR " .. what .. ": " .. tostring(err))
            error(err)
        end
        return ok
    end
end

-- bit 23 of word 4 is blend, bit 26 checkerboard, bits 31:28 mosaic; word 2 bit 8 chains
local function sprite_flags()
    local blend, checker, mosaic, chain = 0, 0, 0, 0
    for i = 0, 1535 do
        local w2 = sp:read_u32(0x20000000 + i * 32 + 8)
        local w4 = sp:read_u32(0x20000000 + i * 32 + 16)
        if (w4 & 0x00800000) ~= 0 then blend = blend + 1 end
        if (w4 & 0x04000000) ~= 0 then checker = checker + 1 end
        if (w4 & 0xf0000000) ~= 0 then mosaic = mosaic + 1 end
        if (w2 & 0x00000100) ~= 0 then chain = chain + 1 end
    end
    return blend, checker, mosaic, chain
end

core_subs[#core_subs + 1] = emu.add_machine_frame_notifier(guard("frame", function()
    local scr = m.screens[":screen"]
    local n = scr:frame_number()
    if n > FRAMES then
        f:close()
        print("CORE_SCAN_OK")
        m:exit()
        return
    end
    local t = { tostring(n) }
    for i = 0, 13 do t[#t + 1] = string.format("%08x", sp:read_u32(0x20190000 + i * 4)) end
    for _, o in ipairs({ 0x0c, 0x24, 0x4c }) do
        t[#t + 1] = string.format("%08x", sp:read_u32(0x20208000 + o))
    end
    t[#t + 1] = string.format("%08x", sp:read_u32(0x20010000))
    t[#t + 1] = string.format("%08x", sp:read_u32(0x20010004))
    -- fbcontrol: byte 0 is the high byte of this word, and its bit 0 skips the 3D blit
    t[#t + 1] = string.format("%08x", sp:read_u32(0x30000000))
    if SPRSTEP > 0 and n % SPRSTEP == 0 then
        local b, c, mo, ch = sprite_flags()
        t[#t + 1] = string.format("%d,%d,%d,%d", b, c, mo, ch)
    else
        t[#t + 1] = ",,,"
    end
    f:write(table.concat(t, ","), "\n")
end))
