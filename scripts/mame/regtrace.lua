-- Every main-CPU access to the HNG64's registers, reads and writes, in order, for comparing with
-- the core's ISSP trace T in its default (register) mode: everything that is not main RAM,
-- program ROM, BIOS, or the tilemap, sprite, palette, 3D-bank and sound memories (HyperNG64.sv,
-- t_mem). MAME's system trace logs reads only in a few ranges; this logs them all.
--   REG_OUT  output file      REG_N  accesses to log, then exit
local out = assert(io.open(os.getenv("REG_OUT"), "w"))
local n_max = tonumber(os.getenv("REG_N") or "20000")
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local n = 0

local function mem(a)
    return (a >= 0x20000000 and a < 0x2000C000) or (a >= 0x20100000 and a < 0x20180000) or
           (a >= 0x20200000 and a < 0x20204000) or (a >= 0x30100000 and a < 0x30300000) or
           (a >= 0x60000000 and a < 0x68000000)
end

local function log(kind, offset, data, mask)
    if mem(offset) or n >= n_max then return end
    n = n + 1
    out:write(string.format("%s %08x %08x %08x\n", kind, offset, data, mask))
    if n == n_max then out:close(); manager.machine:exit() end
end

_G.__regtrace = {}
for _, r in ipairs({{0x1F700000, 0x1F8087FF}, {0x20000000, 0x3FFFFFFF}, {0x68000000, 0x6FFFFFFF},
                    {0xC0000000, 0xC0001007}}) do
    local lo, hi = r[1], r[2]
    table.insert(_G.__regtrace, prog:install_read_tap(lo, hi, "rr" .. lo, function(o, d, m) log("r", o, d, m) end))
    table.insert(_G.__regtrace, prog:install_write_tap(lo, hi, "rw" .. lo, function(o, d, m) log("w", o, d, m) end))
end
