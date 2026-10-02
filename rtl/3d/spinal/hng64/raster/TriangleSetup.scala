// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** Triangle setup after SpinalVoodoo's `voodoo.raster.TriangleSetup` (PROVENANCE.md): the same
  * bounding box, edge functions, top-left rule and parameter start, in HNG64's widths.
  *
  * Two computations are rearranged to the same integers:
  *   - the edge value at the first pixel centre (xc, yc) is a(xc - x0) + b(yc - y0), which is
  *     SpinalVoodoo's a xc + b yc + c since c = -(a x0 + b y0) exactly, so no c is formed;
  *   - a parameter's start is pA + ((xc - xA) dP/dx + (yc - yA) dP/dy) >> xyFrac, SpinalVoodoo's
  *     sub-pixel correction to A's pixel centre plus whole-pixel steps: the whole steps are
  *     multiples of 2^xyFrac, so the floor is the same.
  * SpinalVoodoo forms all of it in one clock and steps the whole pixels two bits a clock; here two
  * multipliers take one edge or parameter a clock, eleven clocks a triangle.
  */
case class TriangleSetup(c: RasterConfig) extends Component {
  val io = new Bundle {
    val i = slave(Stream(TriangleSetup.Input(c)))
    val o = master(Stream(TriangleSetup.Output(c)))
  }

  val F = c.xyFrac
  val half = 1 << (F - 1)

  object S extends SpinalEnum { val Idle, Prep0, Prep, Prep2, Mul, Done = newElement() }
  val state = RegInit(S.Idle)
  // the triangle is read where the gradient unit holds it, and let go when this one's output is
  // taken: no copy (the units run one triangle at a time; the engine is the frame's bottleneck)
  val t = io.i.payload
  val out = Reg(TriangleSetup.Output(c))

  io.i.ready := state === S.Done && io.o.ready
  io.o.valid := state === S.Done
  io.o.payload := out

  when(state === S.Idle && io.i.valid) {
    state := S.Prep0
  }

  // ---- Prep: bounding box, edges, pixel-centre offsets ---------------------------------------------
  def vx(n: Int) = t.v(n)(0)
  def vy(n: Int) = t.v(n)(1)
  def floorPix(v: SInt) = (v >> F).resize(c.pixBits bits)
  def ceilPix(v: SInt) = ((v.resize(c.xyBits + 1 bits) + ((1 << F) - 1)) >> F).resize(c.pixBits bits)
  def roundHalfDownPix(v: SInt) = ((v.resize(c.xyBits + 1 bits) + (half - 1)) >> F).resize(c.pixBits bits)

  // Prep0 registers the x range and the raw edge differences, Prep the rest from them: from the
  // input through two compare-selects and a rounding add, or a subtract, a negate and the
  // top-left compares, in one clock missed clk2x by 3.0 ns
  val xmin = Reg(SInt(t.v(0)(0).getWidth bits))
  val xmax = Reg(SInt(t.v(0)(0).getWidth bits))
  val arR = Reg(Vec(SInt(c.diffBits bits), 3))
  val brR = Reg(Vec(SInt(c.diffBits bits), 3))
  when(state === S.Prep0) {
    // three compares side by side, then one select each (two compare-selects in series missed
    // clk2x by 4.0 ns)
    val l01 = vx(0) < vx(1)
    val l02 = vx(0) < vx(2)
    val l12 = vx(1) < vx(2)
    xmin := (l01 && l02) ? vx(0) | ((!l01 && l12) ? vx(1) | vx(2))
    xmax := (!l01 && !l02) ? vx(0) | ((l01 && !l12) ? vx(1) | vx(2))
    for (((i0, i1), n) <- Seq((0, 1), (1, 2), (2, 0)).zipWithIndex) {
      arR(n) := vy(i0).resize(c.diffBits bits) - vy(i1).resize(c.diffBits bits)
      brR(n) := vx(i1).resize(c.diffBits bits) - vx(i0).resize(c.diffBits bits)
    }
    state := S.Prep
  }
  // Prep: the box and the edges; Prep2: the first pixel centre (in vertex units) less each vertex
  val x0Reg, y0Reg = Reg(SInt(c.pixBits bits))
  val xc = ((x0Reg.resize(c.diffBits bits) |<< F) + half).resize(c.diffBits bits)
  val yc = ((y0Reg.resize(c.diffBits bits) |<< F) + half).resize(c.diffBits bits)

  val a = Reg(Vec(SInt(c.diffBits bits), 3))
  val b = Reg(Vec(SInt(c.diffBits bits), 3))
  val bias = Reg(Bits(3 bits))
  val offX = Reg(Vec(SInt(c.diffBits bits), 3))  // the first pixel centre less vertex n
  val offY = Reg(Vec(SInt(c.diffBits bits), 3))

  when(state === S.Prep) {
    for (n <- 0 until 3) {
      val an = Mux(t.neg, -arR(n), arR(n))
      val bn = Mux(t.neg, -brR(n), brR(n))
      a(n) := an
      b(n) := bn
      bias(n) := !(an > 0 || (an === 0 && bn > 0))   // not a top or left edge
    }
    x0Reg := floorPix(xmin)
    y0Reg := roundHalfDownPix(vy(0))
    out.x0 := floorPix(xmin)
    out.x1 := ceilPix(xmax)
    out.y0 := roundHalfDownPix(vy(0))
    out.y1 := roundHalfDownPix(vy(2))
    out.attr := t.attr
    for (k <- 0 until c.nParams) {
      out.dx.v(k) := t.dx.v(k).resize(c.paramBits(k) bits)
      out.dy.v(k) := t.dy.v(k).resize(c.paramBits(k) bits)
    }
    state := S.Prep2
  }
  when(state === S.Prep2) {
    for (n <- 0 until 3) {
      offX(n) := xc - vx(n).resize(c.diffBits bits)
      offY(n) := yc - vy(n).resize(c.diffBits bits)
    }
    state := S.Mul
  }

  // ---- Mul: slot n < 3 is edge n, then the parameters ----------------------------------------------
  val slots = 3 + c.nParams
  val idx = Reg(UInt(log2Up(slots + 1) bits)) init (0)
  val pIdx = Reg(UInt(log2Up(slots + 1) bits)) init (0)
  val pValid = RegInit(False)
  val prodX = Reg(SInt(c.diffBits + c.mulBits bits))
  val prodY = Reg(SInt(c.diffBits + c.mulBits bits))

  val coefX = Vec(SInt(c.mulBits bits), slots)
  val coefY = Vec(SInt(c.mulBits bits), slots)
  val mOffX = Vec(SInt(c.diffBits bits), slots)
  val mOffY = Vec(SInt(c.diffBits bits), slots)
  for (n <- 0 until 3) {
    coefX(n) := a(n).resize(c.mulBits bits)
    coefY(n) := b(n).resize(c.mulBits bits)
    mOffX(n) := offX(n)
    mOffY(n) := offY(n)
  }
  for (k <- 0 until c.nParams) {
    coefX(3 + k) := t.dx.v(k).resize(c.mulBits bits)
    coefY(3 + k) := t.dy.v(k).resize(c.mulBits bits)
    mOffX(3 + k) := offX(0)
    mOffY(3 + k) := offY(0)
  }

  // the operands are registered before their products: a select, then a multiply, then the sum
  val selX, selY = Reg(SInt(c.diffBits bits))
  val selCX, selCY = Reg(SInt(c.mulBits bits))
  val selIdx = Reg(UInt(log2Up(slots + 1) bits))
  val selValid = RegInit(False)
  pValid := False
  selValid := False
  when(state === S.Mul) {
    when(idx < slots) {
      val n = idx.resize(log2Up(slots) bits)
      selX := mOffX(n)
      selY := mOffY(n)
      selCX := coefX(n)
      selCY := coefY(n)
      selIdx := idx
      selValid := True
      idx := idx + 1
    }
    when(selValid) {
      prodX := selX * selCX
      prodY := selY * selCY
      pIdx := selIdx
      pValid := True
    }
    when(pValid) {
      val sum = prodX.resize(c.diffBits + c.mulBits + 1 bits) + prodY.resize(c.diffBits + c.mulBits + 1 bits)
      for (n <- 0 until 3) when(pIdx === n) {
        out.edge(n) := Mux(bias(n), sum - 1, sum).resize(c.edgeBits bits)
      }
      for (k <- 0 until c.nParams) when(pIdx === 3 + k) {
        out.p.v(k) := t.p0.v(k) + (sum >> F).resize(c.paramBits(k) bits)
      }
      when(pIdx === slots - 1) {
        idx := 0
        state := S.Done
      }
    }
  }
  for (n <- 0 until 3) {
    out.a(n) := a(n)
    out.b(n) := b(n)
  }

  when(state === S.Done && io.o.ready) {
    state := S.Idle
  }
}

object TriangleSetup {
  /** A triangle, vertices sorted by y (v(0) top, v(2) bottom). `neg`: the vertices run clockwise
    * on screen (negative area), so the edge functions are negated to be positive inside. p0 is
    * each parameter at v(0); dx, dy its gradients per pixel.
    */
  case class Input(c: RasterConfig) extends Bundle {
    val v = Vec(Vec(SInt(c.xyBits bits), 2), 3)
    val neg = Bool()
    val p0 = Params(c)
    val dx = Params(c, c.xyFrac)
    val dy = Params(c, c.xyFrac)
    val attr = Bits(c.attrBits bits)
  }

  /** Columns [x0, x1) and rows [y0, y1) in pixels; the edge values (in 2^-2xyFrac pixel^2) and
    * parameters at the centre of pixel (x0, y0); per edge, a and b in vertex units, so a step of
    * one pixel in x adds a << xyFrac.
    */
  case class Output(c: RasterConfig) extends Bundle {
    val x0, x1, y0, y1 = SInt(c.pixBits bits)
    val a = Vec(SInt(c.diffBits bits), 3)
    val b = Vec(SInt(c.diffBits bits), 3)
    val edge = Vec(SInt(c.edgeBits bits), 3)
    val p = Params(c)
    val dx = Params(c)
    val dy = Params(c)
    val attr = Bits(c.attrBits bits)
  }
}
