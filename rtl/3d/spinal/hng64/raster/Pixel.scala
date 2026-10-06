// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** A triangle's fields for the pixel unit (render_3d_fx.py `_set_attr`), carried through the
  * raster as Bits: the first field is the lowest bit. `pal` is the palette offset, or a flat
  * triangle's whole colour; the wrap exponents give the sub-page masks 2^wrap.
  */
case class Attr() extends Bundle {
  val flat, blend, tex4bpp = Bool()
  val texIndex = UInt(4 bits)
  val sub = Bits(2 bits)
  val hoff, voff = UInt(7 bits)
  val pal = Bits(16 bits)
  val scrollX, scrollY = UInt(9 bits)
  val wrapX, wrapY = UInt(5 bits)
}

object Attr {
  val bits = 67
}

/** A pixel ready for its texel and the depth test: the texel's byte in the texture ROM and which
  * nibble of it (4 bpp), the light, and the triangle's colour fields. For a flat triangle only
  * x, y, z, flat and pal mean anything.
  */
case class Fragment(c: RasterConfig) extends Bundle {
  val x, y = UInt(9 bits)
  val z = SInt(c.paramBits(0) bits)
  val addr = UInt(24 bits)
  val nib = Bool()
  val light = Bits(8 bits)
  val flat, blend, tex4bpp = Bool()
  val pal = Bits(16 bits)
}

/** The texel coordinates and light of a pixel (render_3d_fx.py texture_scan with `rcp_newton`).
  *
  * 1/w's reciprocal: w's top 21 bits wn, a table of 2^T entries indexed by the T bits after the
  * leading one (each the reciprocal of its interval's midpoint to T + 2 fraction bits), one Newton
  * step y1 = y0 (2 - wn y0) to 21 fraction bits; 1/w = y1 / 2^(21 + e), e w's top bit. Then
  * u = |u/w| y1 >> (21 + e - k), sign restored (C's truncation), k from the parameters' scales,
  * plus the scroll; the sub-page wrap is C's fmod by 2^wrap, plus the page offset; the texel is
  * the low 10 bits. The light is |light/w| y1 the same way, low 8 bits.
  *
  * Nine pipeline stages, one pixel a clock.
  */
case class PixelUnit(c: RasterConfig) extends Component {
  val io = new Bundle {
    val i = slave(Stream(Raster.Pixel(c)))
    val o = master(Stream(Fragment(c)))
    val busy = out Bool ()
  }

  val T = c.pixTableBits
  val P = T + 2
  val wBits = c.paramBits(1)
  val eBits = log2Up(wBits)
  // k in x 2^k / w: 1/w is * 2^26, u/w and v/w * 2^24, light/w * 2^8 (render_3d_fx.py SCALE)
  val kTex = 26 + 10 - 24
  val kLight = 26 - 4 - 8

  val table = (0 until (1 << T)).map { k =>
    val num = BigInt(1) << (P + T + 2)
    val den = BigInt((1 << (T + 1)) + 2 * k + 1)
    U((num / den + 1) >> 1, P bits)
  }
  val rom = Mem(UInt(P bits), table)

  // ---- A: normalise w, in two clocks: the top bit, then the shift ----------------------------------
  // (from the skid buffer through the encoder and the shift in one clock missed clk2x by 3.6 ns)
  val a0 = (io.i ~~ { px =>
    val o = PixelUnit.A0(c, wBits)
    val w = px.p.v(1)
    val nonPos = w <= 0
    o.px := px
    o.wu := nonPos ? U(1, wBits bits) | w.asUInt
    // the encoder on w itself, beside the test: a w of 1 (what w <= 0 becomes) has its top bit at 0
    o.e := nonPos ? U(0, eBits bits) | OHToUInt(OHMasking.last(w.asBits))
    o
  }).m2sPipe()
  val a = (a0 ~~ { r =>
    val o = PixelUnit.A(c)
    val normed = r.wu |<< (U(wBits - 1, eBits bits) - r.e)
    o.px := r.px
    o.e := r.e
    o.wn := normed(wBits - 1 downto wBits - 21)
    o
  }).m2sPipe()

  // ---- B: the table ----------------------------------------------------------------------------------
  val b = rom.streamReadSync(a.translateWith(a.wn(19 downto 20 - T)), a.payload)

  // ---- C: wn y0 ------------------------------------------------------------------------------------
  val c0 = (b ~~ { r =>
    val o = PixelUnit.C(c, P)
    o.a := r.linked
    o.y0 := r.value
    o.corr := (r.linked.wn * r.value).resize(21 + P + 1 bits)      // the product; C takes it from 2^(21+P)
    o
  }).m2sPipe()
  val cS = (c0 ~~ { r =>
    val o = PixelUnit.C(c, P)
    o.a := r.a
    o.y0 := r.y0
    o.corr := U(BigInt(1) << (21 + P), 21 + P + 1 bits) - r.corr
    o
  }).m2sPipe()

  // ---- D: y1 = y0 corr ---------------------------------------------------------------------------------
  val d = (cS ~~ { r =>
    val o = PixelUnit.D(c)
    o.a := r.a
    o.y1 := ((r.y0 * r.corr) >> (2 * P - 1)).resize(22 bits)
    o
  }).m2sPipe()

  // ---- E: the magnitudes, then the three products (a stage each; the multipliers registered
  // on both sides) -----------------------------------------------------------------------------------
  val e0 = (d ~~ { r =>
    val o = PixelUnit.E0(c)
    val p = r.a.px.p
    o.a := r.a
    o.y1 := r.y1
    o.sNeg := p.v(3).msb
    o.tNeg := p.v(4).msb
    o.lNeg := p.v(2).msb
    o.sa := p.v(3).abs
    o.ta := p.v(4).abs
    o.la := p.v(2).abs
    o
  }).m2sPipe()

  val e = (e0 ~~ { r =>
    val o = PixelUnit.E(c)
    o.a := r.a
    o.sNeg := r.sNeg
    o.tNeg := r.tNeg
    o.lNeg := r.lNeg
    o.ps := (r.sa * r.y1).resize(o.ps.getWidth bits)
    o.pt := (r.ta * r.y1).resize(o.pt.getWidth bits)
    o.pl := (r.la * r.y1).resize(o.pl.getWidth bits)
    o
  }).m2sPipe()

  // ---- F: the shifts (two stages: by eights, then the rest), then signs, scroll, wrap and the
  // address. From the multiplier through one whole shift missed clk2x by 2.1 ns. ----------------------
  val fc = (e ~~ { r =>
    val o = PixelUnit.FC(c, eBits)
    o.a := r.a
    o.sNeg := r.sNeg
    o.tNeg := r.tNeg
    o.lNeg := r.lNeg
    val shTex = (r.a.e.resize(eBits + 1 bits) + (21 - kTex)).resize(eBits + 1 bits)
    val shLight = (r.a.e.resize(eBits + 1 bits) + (21 - kLight)).resize(eBits + 1 bits)
    o.ps := r.ps >> (shTex & ~U(7, eBits + 1 bits))
    o.pt := r.pt >> (shTex & ~U(7, eBits + 1 bits))
    o.pl := r.pl >> (shLight & ~U(7, eBits + 1 bits))
    o.fineT := shTex(2 downto 0)
    o.fineL := shLight(2 downto 0)
    o
  }).m2sPipe()
  val f0 = (fc ~~ { r =>
    val o = PixelUnit.F0(c)
    o.a := r.a
    o.sNeg := r.sNeg
    o.tNeg := r.tNeg
    o.lNeg := r.lNeg
    o.ms := r.ps >> r.fineT
    o.mt := r.pt >> r.fineT
    o.ml := (r.pl >> r.fineL).resize(8 bits)
    o
  }).m2sPipe()

  // A texel coordinate in two clocks: v = +-m + scroll at full width, of which only the sign and the
  // low 10 bits are kept (|v|'s low 10 bits are those of v's, negated when v is), then the wrap on
  // 10 bits. In one clock, from F0 through the negation, the add, |v|, the mask, the negation and
  // the offset into the address it missed clk3d by 0.16 ns (64f9bd4 seed 6649).
  def texelV(m: UInt, neg: Bool, scroll: UInt): (Bool, UInt) = {
    val w = m.getWidth + 1
    val ms = m.asSInt.resize(w bits)
    val sc = scroll.resize(m.getWidth bits).asSInt.resize(w bits)
    val v = neg ? (sc - ms) | (sc + ms)
    (v.msb, v.asUInt(9 downto 0))
  }
  def texelW(vNeg: Bool, v10: UInt, wrapOn: Bool, wrap: UInt, off: UInt): UInt = {
    val mag10 = vNeg ? (U(0, 10 bits) - v10) | v10
    val msk10 = (wrap >= 10) ? U(1023, 10 bits) | (U(1023, 10 bits) >> (U(10, 4 bits) - wrap.resize(4 bits)))
    val kept = mag10 & msk10
    val fm10 = vNeg ? (U(0, 10 bits) - kept) | kept
    val wrapped = fm10 + (off.resize(10 bits) |<< 3)
    wrapOn ? wrapped | v10
  }

  val f1 = (f0 ~~ { r =>
    val o = PixelUnit.F1(c)
    val at = Attr()
    at.assignFromBits(r.a.px.attr)
    o.a := r.a
    val (sn, s10) = texelV(r.ms, r.sNeg, at.scrollY)
    val (tn, t10) = texelV(r.mt, r.tNeg, at.scrollX)
    o.sNeg := sn
    o.s10 := s10
    o.tNeg := tn
    o.t10 := t10
    o.l := r.lNeg ? (U(0, 8 bits) - r.ml) | r.ml
    o
  }).m2sPipe()

  val f = (f1 ~~ { r =>
    val o = Fragment(c)
    val px = r.a.px
    val at = Attr()
    at.assignFromBits(px.attr)
    val wrapOn = at.sub(1)
    val si = texelW(r.sNeg, r.s10, wrapOn, at.wrapY, at.voff)
    val ti = texelW(r.tNeg, r.t10, wrapOn, at.wrapX, at.hoff)
    val l = r.l
    o.x := px.x
    o.y := px.y
    o.z := px.p.v(0)
    o.addr := at.texIndex @@ (at.tex4bpp ? (U(0, 1 bits) @@ si @@ ti(9 downto 1)) | (si @@ ti))
    o.nib := ti(0)
    o.light := l.asBits
    o.flat := at.flat
    o.blend := at.blend
    o.tex4bpp := at.tex4bpp
    o.pal := at.pal
    o
  }).m2sPipe()

  io.o << f
  io.busy := a0.valid || a.valid || b.valid || c0.valid || cS.valid || d.valid || e0.valid || e.valid || fc.valid || f0.valid || f1.valid || f.valid
}

object PixelUnit {
  case class A0(c: RasterConfig, wBits: Int) extends Bundle {
    val px = Raster.Pixel(c)
    val wu = UInt(wBits bits)
    val e = UInt(log2Up(c.paramBits(1)) bits)
  }
  case class A(c: RasterConfig) extends Bundle {
    val px = Raster.Pixel(c)
    val e = UInt(log2Up(c.paramBits(1)) bits)
    val wn = UInt(21 bits)
  }
  case class C(c: RasterConfig, p: Int) extends Bundle {
    val a = A(c)
    val y0 = UInt(p bits)
    val corr = UInt(21 + p + 1 bits)
  }
  case class D(c: RasterConfig) extends Bundle {
    val a = A(c)
    val y1 = UInt(22 bits)
  }
  case class E0(c: RasterConfig) extends Bundle {
    val a = A(c)
    val y1 = UInt(22 bits)
    val sNeg, tNeg, lNeg = Bool()
    val sa = UInt(c.paramBits(3) bits)
    val ta = UInt(c.paramBits(4) bits)
    val la = UInt(c.paramBits(2) bits)
  }
  case class F0(c: RasterConfig) extends Bundle {
    val a = A(c)
    val sNeg, tNeg, lNeg = Bool()
    val ms = UInt(c.paramBits(3) + 22 bits)
    val mt = UInt(c.paramBits(4) + 22 bits)
    val ml = UInt(8 bits)
  }
  case class F1(c: RasterConfig) extends Bundle {
    val a = A(c)
    val sNeg, tNeg = Bool()
    val s10, t10 = UInt(10 bits)
    val l = UInt(8 bits)
  }
  case class FC(c: RasterConfig, eBits: Int) extends Bundle {
    val a = A(c)
    val sNeg, tNeg, lNeg = Bool()
    val ps = UInt(c.paramBits(3) + 22 bits)
    val pt = UInt(c.paramBits(4) + 22 bits)
    val pl = UInt(c.paramBits(2) + 22 bits)
    val fineT, fineL = UInt(3 bits)
  }
  case class E(c: RasterConfig) extends Bundle {
    val a = A(c)
    val sNeg, tNeg, lNeg = Bool()
    val ps = UInt(c.paramBits(3) + 22 bits)
    val pt = UInt(c.paramBits(4) + 22 bits)
    val pl = UInt(c.paramBits(2) + 22 bits)
  }
}
