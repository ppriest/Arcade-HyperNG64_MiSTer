// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** Each span's parameters at its first pixel, from the triangle's at the setup's origin (x0, y0):
  * p = p0 + (x - x0) dP/dx + (y - y0) dP/dy, each modulo its width. SpinalVoodoo's walker carries
  * the parameters in every cursor and steps them with the edges; the sums are the same integers,
  * and the walker keeps only the edges. Three stages, a span a clock: the offsets, the products,
  * the sums. The triangle is read where the setup holds it; the walker lets it go only once this
  * is empty (`idle`).
  */
case class SpanParams(c: RasterConfig) extends Component {
  val io = new Bundle {
    val i = slave(Stream(SpanWalker.Walk()))
    val tri = in(TriangleSetup.Output(c))
    val o = master(Stream(SpanWalker.Span(c)))
    val idle = out Bool ()
  }
  val ob = c.pixBits + 1

  val a = (io.i ~~ { w =>
    val o = SpanParams.Offs(c)
    o.w := w
    o.ox := (w.x0.resize(ob bits).asSInt - io.tri.x0.resize(ob bits)).resize(ob bits)
    o.oy := (w.y.resize(ob bits).asSInt - io.tri.y0.resize(ob bits)).resize(ob bits)
    o
  }).m2sPipe()

  val b = (a ~~ { r =>
    val o = SpanParams.Prods(c)
    o.w := r.w
    for (k <- 0 until c.nParams) {
      o.px.v(k) := (r.ox * io.tri.dx.v(k)).resize(c.paramBits(k) bits)
      o.py.v(k) := (r.oy * io.tri.dy.v(k)).resize(c.paramBits(k) bits)
    }
    o
  }).m2sPipe()

  val f = (b ~~ { r =>
    val o = SpanWalker.Span(c)
    o.x0 := r.w.x0
    o.x1 := r.w.x1
    o.y := r.w.y
    for (k <- 0 until c.nParams) o.p.v(k) := io.tri.p.v(k) + r.px.v(k) + r.py.v(k)
    o.dx := io.tri.dx
    o.attr := io.tri.attr
    o
  }).m2sPipe()

  io.o << f
  io.idle := !a.valid && !b.valid && !f.valid
}

object SpanParams {
  case class Offs(c: RasterConfig) extends Bundle {
    val w = SpanWalker.Walk()
    val ox, oy = SInt(c.pixBits + 1 bits)
  }
  case class Prods(c: RasterConfig) extends Bundle {
    val w = SpanWalker.Walk()
    val px, py = Params(c)
  }
}
