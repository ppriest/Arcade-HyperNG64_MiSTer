-- Hold analogue inputs at fixed values and snap frames: does a set's boot depend on them?
--   CORE_AN     "tag=value,..." e.g. ":AN0=255,:AN1=255"
--   CORE_SNAPS  frames to snap, "1500,3000"; the run ends two frames after the last
local want = {}
for tag, v in string.gmatch(os.getenv("CORE_AN") or "", "([^=,]+)=(%d+)") do want[tag] = tonumber(v) end
local snaps, last = {}, 0
for n in string.gmatch(os.getenv("CORE_SNAPS") or "", "%d+") do
    snaps[tonumber(n)] = true
    last = math.max(last, tonumber(n))
end
local f = 0
core_an_sub = emu.add_machine_frame_notifier(function()
    f = f + 1
    for tag, v in pairs(want) do
        local port = manager.machine.ioport.ports[tag]
        if port then
            for _, field in pairs(port.fields) do field:set_value(v) end
        end
    end
    if snaps[f] then
        manager.machine.video:snapshot()
        for tag, _ in pairs(want) do
            local port = manager.machine.ioport.ports[tag]
            if port then print(string.format("frame %d %s reads %d", f, tag, port:read())) end
        end
    end
    if f == last + 2 then manager.machine:exit() end
end)
