-- The main CPU's side of the IO MCU protocol, with emulated times, for sim/iomcu_tb +events: its
-- writes to the dual-port RAM (W), its writes to the MCU interrupt register 0x1f7021c4 (I), its
-- reads of 0x1f808008, where the fight games read Start (R, from frame CORE_START - 5), and each
-- frame's end (F). Coin 1 is pressed for frame CORE_COIN and Start 1 held for frames CORE_START to
-- CORE_START + 9; the run stops at CORE_START + 20.
--
--   CORE_OUT=debug/mame_start/mipsev.txt mame sams64 ... -autoboot_script scripts/mame/mcu_proto.lua
local out = io.open(os.getenv("CORE_OUT") or "mipsev.txt", "w")
local F_COIN = tonumber(os.getenv("CORE_COIN") or "1300")
local F_START = tonumber(os.getenv("CORE_START") or "1400")
local f = 0
local in7 = manager.machine.ioport.ports[":IN7"]
local coin, start
for _, fl in pairs(in7.fields) do
  if fl.mask == 0x04 then coin = fl end
  if fl.mask == 0x40 then start = fl end
end
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local function t() return manager.machine.time:as_double() end
core_tw = sp:install_write_tap(0x1f808000, 0x1f8087ff, "dpw", function(off, data, mask)
  out:write(string.format("%.9f W %08x %08x %08x\n", t(), off, mask, data)); return data end)
core_ti = sp:install_write_tap(0x1f7021c4, 0x1f7021c7, "irq", function(off, data, mask)
  out:write(string.format("%.9f I %08x %08x %08x\n", t(), off, mask, data)); return data end)
core_tr = sp:install_read_tap(0x1f808008, 0x1f80800b, "dpr", function(off, data, mask)
  if f >= F_START - 5 then out:write(string.format("%.9f R %08x %08x %08x\n", t(), off, mask, data)) end
  return data end)
emu.register_frame_done(function()
  f = f + 1
  out:write(string.format("%.9f F %d\n", t(), f))
  if f == F_COIN then coin:set_value(1) end
  if f == F_COIN + 1 then coin:clear_value() end
  if f == F_START then start:set_value(1) end
  if f == F_START + 10 then start:clear_value() end
  if f >= F_START + 20 then out:close(); manager.machine:exit() end
end)
