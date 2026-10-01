# 3D: reused designs

`hng64_raster.v` and `hng64_geo.v` are generated from `spinal/` (SpinalHDL, Scala) by
`scripts/gen_3d_rtl.sh`, which also exports the geometry microcode from `scripts/geo_ucode.py` into
`spinal/geo/`; edit the Scala or the microcode, not the Verilog. The generated Verilog is committed
so that Quartus and the benches need no Scala toolchain.

`SpanParams.scala`, `Pixel.scala`, `TexCache.scala`, `RenderBuf.scala`, `TexBlock.scala` and
`GeoEngine.scala` are ours (the cache after Igehy, Eldridge and Proudfoot, "Prefetching in a Texture
Cache Architecture", 1998). SpinalVoodoo's host supplies the gradients; here the geometry engine's
microcode does (`geo_engine.setup_record`). Its TMU and pixel pipeline do not fit HNG64's textures
(docs/phase3_3d.md).

## SpinalVoodoo: triangle setup, span walker, span rasteriser

- Upstream: https://github.com/fayalalebrun/SpinalVoodoo, commit 28d1435, files
  `src/voodoo/raster/TriangleSetup.scala`, `SpanWalker.scala`, `Rasterizer.scala`
- Licence: the repository has none. One has been asked of the author; reuse assumes it is granted
  (user decision, docs/ROADMAP.md). If it is refused, these three files are rewritten.
- Taken: the bounding box, edge functions with the top-left rule, the parameter start at the first
  pixel centre, and the span walker's states and search order.
- Changed for HNG64:
  - vertices 12.12 (Voodoo 12.4), edge values and parameters as raw integers in the widths of
    `RasterConfig`, positions in whole pixels;
  - the edge value at the first pixel is a(xc - x0) + b(yc - y0), and a parameter's start one
    multiply per axis; both equal SpinalVoodoo's integers (`TriangleSetup.scala` says why);
  - the setup is sequential, two multipliers over eight slots;
  - five parameters (z, 1/w, light/w, u/w, v/w) and a triangle's pixel-unit fields carried
    along; the parameter adjustment is always on;
  - the clip is always MAME's 513 x 512 (column 512 lands in column 0), and the walk ends at the
    buffer's last row;
  - the walker carries only the edges; `SpanParams.scala` (ours) gives each span its parameters
    from the triangle's origin, the same integers the walked parameters would be;
  - the span walker's RecoverLeft bug below is fixed.

### A bug in SpinalVoodoo's SpanWalker

In `RecoverLeft`, when the probe is inside, is the first inside pixel of the row
(`recoverFoundInside` false) and is at or left of the visible start, the state machine assigns
`bookmark := probe` and `probe := bookmark` in the same clock. The probe takes the old bookmark,
the row guess; when the guess is outside the triangle, right of the span, `SearchRightToExit` ends
the span at guess - 1 and draws the pixels between the span's real end and the guess. Seen on
5 of 10,179 triangles of the six captures, one pixel each (sim/raster_tb; sams64 frame 600,
triangle 223, row 268: 262-263 drawn, 262 covered). Fixed here by keeping the probe when it is the
first inside pixel. Upstream at 28d1435 has it.
