-- Register accesses with the frame they fall in, leaving out the per-frame chatter (sprite clears,
-- the interrupt controller, the IO MCU's mailbox) so a long run stays small. For finding what the
-- game does around a given point, e.g. its Nth display-list upload.
--   RF_OUT  output file      RF_FRAMES  frames to run
local out = assert(io.open(os.getenv("RF_OUT"), "w"))
local frames = tonumber(os.getenv("RF_FRAMES") or "1500")
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local frame = 0

local function skip(a)
    return (a >= 0x20000000 and a < 0x2000C000) or (a >= 0x20100000 and a < 0x20180000) or
           (a >= 0x20200000 and a < 0x20204000) or (a >= 0x30100000 and a < 0x30300000) or
           (a >= 0x60000000 and a < 0x68000000) or (a >= 0x2000D800 and a < 0x2000F000) or
           (a >= 0x1F701100 and a < 0x1F701120) or (a >= 0x1F808000 and a < 0x1F808800) or
           (a >= 0x20300000 and a < 0x20300200)
end

local function log(kind, offset, data, mask)
    if skip(offset) then return end
    out:write(string.format("%d %s %08x %08x %08x\n", frame, kind, offset, data, mask))
end

_G.__rf = {}
for _, r in ipairs({{0x1F700000, 0x1F8087FF}, {0x20000000, 0x3FFFFFFF}, {0x68000000, 0x6FFFFFFF},
                    {0xC0000000, 0xC0001007}}) do
    local lo, hi = r[1], r[2]
    table.insert(_G.__rf, prog:install_read_tap(lo, hi, "fr" .. lo, function(o, d, m) log("r", o, d, m) end))
    table.insert(_G.__rf, prog:install_write_tap(lo, hi, "fw" .. lo, function(o, d, m) log("w", o, d, m) end))
end

emu.register_frame_done(function()
    frame = frame + 1
    if frame >= frames then out:close(); manager.machine:exit() end
end)
