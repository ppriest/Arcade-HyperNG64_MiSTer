-- Log the first reads and writes of an address range, with the CPU's PC, then exit.
--   TAP_LO, TAP_HI  the range (hex); TAP_N  how many accesses; TAP_OUT  output file
local lo = tonumber(os.getenv("TAP_LO"), 16)
local hi = tonumber(os.getenv("TAP_HI"), 16)
local n_max = tonumber(os.getenv("TAP_N") or "40")
local out = assert(io.open(os.getenv("TAP_OUT"), "w"))
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local n = 0
local function log(kind, offset, data, mask)
    n = n + 1
    if n <= n_max then
        out:write(string.format("%s %08x %08x mask %08x pc %s\n", kind, offset, data, mask,
            tostring(cpu.state["PC"] and string.format("%x", cpu.state["PC"].value) or "?")))
    end
    if n == n_max then out:close(); manager.machine:exit() end
    return data
end
_G.__tap_r = prog:install_read_tap(lo, hi, "vr", function(o, d, m) log("r", o, d, m) end)
_G.__tap_w = prog:install_write_tap(lo, hi, "vw", function(o, d, m) log("w", o, d, m) end)
