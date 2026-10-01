#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Every captured frame: every enabled tilemap layer, the sprite layer, the mixer and the
# whole video block end to end, RTL against the software model. RUN FROM THE REPO ROOT.
#
#     scripts/video_regress.sh [set ...]        # default: every set under debug/
#
# Each capture is re-rendered by the model first, so a model change is picked up. A set's tile
# ROM images must exist (scripts/rom_regions.py <set> scrtile, and sprtile). They are the regions
# as the ROMs load them; the scrtile reorder is undone by address, in the RTL and in the benches.
set -u
# without this each line's status is tail's, and a failing bench leaves the script exiting 0
set -o pipefail

sets=${*:-"sams64 fatfurwa buriki xrally"}
fail=0

for s in $sets; do
    scr=debug/rom/$s-scrtile.bin
    spr=debug/rom/$s-sprtile.bin
    for d in debug/$s-*; do
        [ -d "$d" ] || continue
        [ -f "$d/videoregs.bin" ] || continue
        name=${d#debug/$s-}
        python scripts/render_model.py "$s" "$name" --dump >/dev/null || { echo "$s $name: model failed"; fail=1; continue; }
        for tm in 0 1 2 3; do
            [ -f "$d/layer$tm.bin" ] || continue
            printf '%-9s %-8s tm%d  ' "$s" "$name" "$tm"
            scripts/run_verilator.sh tilemap_tb +cap="$d" +tm=$tm +rom="$scr" 2>&1 | tail -1 || fail=1
        done
        printf '%-9s %-8s spr  ' "$s" "$name"
        scripts/run_verilator.sh sprite_tb +cap="$d" +rom="$spr" 2>&1 | tail -1 || fail=1
        printf '%-9s %-8s mix  ' "$s" "$name"
        scripts/run_verilator.sh mixer_tb +cap="$d" 2>&1 | tail -1 || fail=1
        # the 3D rasteriser, on the triangles render_3d_fx.py --dump last wrote for this capture
        if [ -f "$d/raster.txt" ]; then
            printf '%-9s %-8s 3dr  ' "$s" "$name"
            scripts/run_verilator.sh raster_tb +cap="$d" +tex=debug/rom/$s-textures0.bin +noblock=1 2>&1 | tail -1 || fail=1
        fi
        printf '%-9s %-8s all  ' "$s" "$name"
        scripts/run_verilator.sh video_tb +cap="$d" +srom="$scr" +prom="$spr" 2>&1 | tail -1 || fail=1
    done
done

# the 3D's start-up texture blocking, once: it is 16 MB whatever the capture
if [ -f debug/sams64-f2500/raster.txt ]; then
    printf '%-9s %-8s 3db  ' sams64 f2500
    scripts/run_verilator.sh raster_tb +cap=debug/sams64-f2500 +tex=debug/rom/sams64-textures0.bin 2>&1 | tail -1 || fail=1
fi

# the 3D as the core has it (queue, engine, rasteriser, DDRAM port), on the one capture whose
# events geo_engine.py --dump wrote; its raster_color.bin must come from the same model version
if [ -f debug/sams64-f2500/geo_events.txt ]; then
    printf '%-9s %-8s 3d   ' sams64 f2500
    scripts/run_verilator.sh g3d_tb +cap=debug/sams64-f2500 +tex=debug/rom/sams64-textures0.bin         +verts=debug/rom/sams64-verts.bin 2>&1 | tail -1 || fail=1
fi

# the memory stack has no captures to replay; it is checked against a pattern
printf '%-9s %-8s mem  ' cpu backing
scripts/run_verilator.sh mainmem_tb 2>&1 | tail -1 || fail=1
printf '%-9s %-8s load ' rom loading
scripts/run_verilator.sh romload_tb 2>&1 | tail -1 || fail=1
printf '%-9s %-8s mcu  ' io tlcs870
# the whole trace: the first interrupt is past 2.2M instructions
scripts/run_verilator.sh iomcu_tb +n=3000000 2>&1 | tail -1 || fail=1
printf '%-9s %-8s io   ' main board
scripts/run_verilator.sh io_tb 2>&1 | tail -1 || fail=1
# the whole board less its CPU, replaying MAME's boot, with frames 400 and 800 compared
printf '%-9s %-8s sys  ' whole board
scripts/run_verilator.sh sys_tb +frames=400,800 2>&1 | tail -1 || fail=1
printf '%-9s %-8s sys  ' whole flipped
scripts/run_verilator.sh sys_tb +frames=400,800 +flip=1 2>&1 | tail -1 || fail=1
# the 3D model against MAME's frames, from the bus trace (the BIOS logo)
printf '%-9s %-8s 3d   ' sams64 logo
python scripts/render_3d.py sams64 566 600 601 630 652 2>&1 | grep '^frame' | awk '{print} / [1-9][0-9]* of 229376/ {bad=1} END {exit bad}' | tail -1 || fail=1
# CRT Adjust on the output raster
printf '%-9s %-8s crt  ' output crt
# (not `tee /dev/stderr`: with the output redirected to a file, that reopens and truncates it)
crt=$(scripts/run_verilator.sh crt_tb 2>&1 | grep "^crt:")
echo "$crt"
[[ $crt == *PASS* ]] || fail=1

exit $fail
