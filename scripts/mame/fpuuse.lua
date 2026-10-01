-- Does the game use the VR4300's FPU or its TLB? For scripts/fpu_use.py.
--
--   FU_OUT     output file
--   FU_FRAMES  frames to run
--   FU_COIN    frame to insert a coin and press Start (0 = attract only); from Start, P1 Right is
--              held and Button 1 pulsed so play goes on
--
-- MAME's MIPS III core raises a coprocessor-unusable exception for any COP1 instruction while
-- Status bit 29 (CU1) is clear, so a game that uses the FPU must set it. Each frame this records
-- Status and whether any FPU register (its low 32 bits, FPSn) or FCR31 changed, and the TLB-facing COP0 registers
-- (Wired, EntryHi, EntryLo0/1, PageMask), whose writes only TLB code makes.

local OUT    = os.getenv("FU_OUT")
local FRAMES = tonumber(os.getenv("FU_FRAMES") or "3600")
local COIN   = tonumber(os.getenv("FU_COIN") or "0")

local mach = manager.machine
local cpu  = mach.devices[":maincpu"]
local st   = cpu.state

local out = assert(io.open(OUT, "w"))
local names = {}
for k, _ in pairs(st) do names[#names + 1] = k end
table.sort(names)
out:write("state " .. table.concat(names, " ") .. "\n")

-- a value MAME's Lua cannot hold as an integer (64 bits, top bit set) raises; it is written as
-- "x" and so changes as seen from here only when it becomes readable or unreadable
local function get(name)
    local ok, v = pcall(function() return st[name].value end)
    if ok then return string.format("%x", v) end
    return "x"
end

local fpu = {}
for _, k in ipairs(names) do
    -- the 32-bit views: a 64-bit FPR with its top bit set is an error to read from Lua
    if k:match("^FPS%d+$") or k:match("^FCR") then fpu[#fpu + 1] = k end
end
local cop0 = {}
for _, k in ipairs({"SR", "Status", "Wired", "EntryHi", "EntryLo0", "EntryLo1", "PageMask", "Index"}) do
    if st[k] then cop0[#cop0 + 1] = k end
end
out:write("fpu " .. table.concat(fpu, " ") .. "\n")
out:write("cop0 " .. table.concat(cop0, " ") .. "\n")

local function field(name)
    for _, port in pairs(mach.ioport.ports) do
        local f = port.fields[name]
        if f then return f end
    end
    return nil
end
local f_coin, f_start = field("Coin 1"), field("1 Player Start")
local f_right, f_b1 = field("P1 Right"), field("P1 Button 1")

local prev_f, prev_c = nil, nil
local n = 0
emu.register_frame_done(function()
    n = n + 1
    if COIN > 0 and f_coin and f_start then
        f_coin:set_value((n >= COIN and n < COIN + 6) and 1 or 0)
        f_start:set_value((n >= COIN + 90 and n < COIN + 96) and 1 or 0)
        if n >= COIN + 96 then
            if f_right then f_right:set_value(1) end
            if f_b1 then f_b1:set_value((n % 20) < 4 and 1 or 0) end
        end
    end
    local fv = {}
    for _, k in ipairs(fpu) do fv[#fv + 1] = get(k) end
    local cv = {}
    for _, k in ipairs(cop0) do cv[#cv + 1] = get(k) end
    local fs, cs = table.concat(fv, ","), table.concat(cv, ",")
    -- a line when anything changed, and every 600 frames
    if fs ~= prev_f or cs ~= prev_c or n % 600 == 0 then
        out:write(string.format("frame %d cop0 %s fpu %s\n", n, cs, fs))
        prev_f, prev_c = fs, cs
    end
    if n >= FRAMES then
        out:write("done\n")
        out:close()
        mach:exit()
    end
end)
