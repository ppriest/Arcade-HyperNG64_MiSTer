// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._

/** Widths of the rasteriser, from the captured frames (docs/phase3_3d.md, `render_3d_fx.py --dump`).
  *
  * Vertices are x, y in window pixels with `xyFrac` fraction bits. Each parameter is an integer in
  * the model's format (render_3d_fx.py SCALE): z, 1/w, light/w, u/w, v/w. Their widths hold every
  * value the rasteriser emits; values between pixels, and gradients, may wrap, since the walk only
  * adds. The setup's `>> xyFrac` is not modular, so its gradients carry `xyFrac` more bits.
  */
case class RasterConfig(
    xyFrac: Int = 12,
    xyBits: Int = 24,
    pixBits: Int = 13,
    paramBits: Seq[Int] = Seq(30, 34, 24, 32, 32),
    rcpBits: Int = 20,                      // the gradients' reciprocal of det (phase3_3d.md)
    pixTableBits: Int = 10,                 // the pixel unit's reciprocal table index
    clipW: Int = 513,                       // MAME's 513: x = 512 lands in column 0 (MAME_KLUDGES)
    clipH: Int = 512
) {
  val nParams = paramBits.size
  val diffBits = xyBits + 1                 // a vertex difference, or a pixel centre less a vertex
  val edgeBits = 2 * diffBits + 1           // a*dx + b*dy, in 2^-(2 xyFrac) pixel^2
  val gradBits = paramBits.map(_ + xyFrac)
  val mulBits = (diffBits +: gradBits).max  // the setup multipliers' coefficient operand
  val attrBits = Attr.bits                  // a triangle's fields for the pixel unit, carried along
}

/** One value per parameter, each at its own width plus `extra`. */
case class Params(c: RasterConfig, extra: Int = 0) extends Bundle {
  val v = Vec(c.paramBits.map(w => SInt(w + extra bits)))
}
