// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** Finds each row's covered span by walking pixel centres and testing the three edge values, as
  * SpinalVoodoo's `voodoo.raster.SpanWalker` (PROVENANCE.md), state for state. A pixel is inside
  * when all three edge values are >= 0 (the setup has applied the top-left rule).
  *
  * The parameters are not walked: SpanParams gives each span its start from the triangle's.
  *
  * HNG64's differences: positions are integer pixels (SpinalVoodoo keeps them in 12.4 with a zero
  * fraction); the parameters are HNG64's five; the clip is always MAME's 513 columns by 512 rows
  * (the span's x is 9 bits out, so column 512 is written to column 0, as MAME_KLUDGES logs); the
  * walk stops at the buffer's last row rather than the triangle's.
  */
case class SpanWalker(c: RasterConfig, nLook: Int = 4) extends Component {
  val io = new Bundle {
    val i = slave(Stream(TriangleSetup.Output(c)))
    val o = master(Stream(SpanWalker.Walk()))
    val drained = in Bool ()                         // SpanParams is through with this triangle's spans
    val busy = out Bool ()
  }

  object W extends SpinalEnum {
    val Idle, Decide, RecoverLeft, SearchRightToEnter, SearchLeftToExit, SearchRightToExit,
        EmitSpan, AdvanceRow = newElement()
  }

  val state = RegInit(W.Idle)
  // the triangle is read where the setup holds it, and let go after its last row: no copy
  val tri = io.i.payload
  // the step down and left, precomputed so the next row's guess is one add: b - a
  val bma = Reg(Vec(SInt(c.edgeBits bits), 3))
  val rowGuess = Reg(SpanWalker.Cursor(c))
  val probe = Reg(SpanWalker.Cursor(c))
  val bookmark = Reg(SpanWalker.Cursor(c))
  val leftEdge = Reg(SpanWalker.Cursor(c))
  val nextRowBase = Reg(SpanWalker.Cursor(c))
  val nextRowLeftBiased = RegInit(False)
  val emitRight = Reg(SInt(c.pixBits bits))
  val firstSpanPending = RegInit(False)
  val recoverFoundInside = RegInit(False)

  io.busy := state =/= W.Idle

  def inside(k: SpanWalker.Cursor): Bool = k.e.map(_ >= 0).reduce(_ && _)

  // the probe's edge values 1 to nLook pixels on in the search's direction, kept beside it (below)
  val ahead = Vec.fill(nLook)(Vec.fill(3)(Reg(SInt(c.edgeBits bits))))
  val aValid = RegInit(False)
  val aRight = Reg(Bool())
  val stepped = False                                 // a search stepped the probe a pixel
  val moved = False                                   // the probe was set otherwise
  val goRight = state === W.SearchRightToEnter || state === W.SearchRightToExit
  val aReady = aValid && aRight === goRight

  // a search's step waits a clock while `ahead` is made for the probe (the search's state then
  // holds, the same as a step later)
  def stepProbe(right: Boolean): Unit = when(aReady) {
    step(probe, probe, right)
    pS := (if (right) pS + 1 else pS - 1)
    pE := (if (right) pE + 1 else pE - 1)
    stepped := True
  }
  def probeFromBookmark(): Unit = { probe := bookmark; pS := bS; pE := bE; moved := True }
  def bookmarkFromProbe(): Unit = { bookmark := probe; bS := pS; bE := pE }

  def step(dst: SpanWalker.Cursor, src: SpanWalker.Cursor, right: Boolean): Unit = {
    dst.x := (if (right) src.x + 1 else src.x - 1)
    dst.y := src.y
    for (n <- 0 until 3) {
      val an = tri.a(n).resize(c.edgeBits bits) |<< c.xyFrac
      dst.e(n) := (if (right) src.e(n) + an else src.e(n) - an)
    }
  }

  def stepDown(dst: SpanWalker.Cursor, src: SpanWalker.Cursor): Unit = {
    dst.x := src.x
    dst.y := src.y + 1
    for (n <- 0 until 3) dst.e(n) := src.e(n) + (tri.b(n).resize(c.edgeBits bits) |<< c.xyFrac)
  }

  // SpinalVoodoo's clip, enabled, to the buffer. Registered as the triangle is taken (Decide, the
  // state after, does not use it): worked out from the setup's output on every clock, from x0
  // through the clip, the compare with the probe, the next state and the edge values' select it
  // missed clk3d by 0.29 ns (20b5e7d seed 2).
  val visibleStart = Reg(SInt(c.pixBits bits))
  // probe.x - visibleStart and probe.x - visibleEnd, and the bookmark's, kept beside probe.x so its
  // tests against the bounds are a sign or a compare with a small constant: the compares on probe.x
  // missed clk3d by 1.24 ns into probe (3f41ccc seed 1)
  val pS, pE, bS, bE = Reg(SInt(c.pixBits + 1 bits))
  val visibleEnd = Reg(SInt(c.pixBits bits))
  val lastRow = Reg(SInt(c.pixBits bits))
  io.i.ready := state === W.AdvanceRow && nextRowBase.y + 1 >= lastRow && io.drained
  val emitVisibleX = leftEdge.x <= emitRight && emitRight >= 0 && leftEdge.x < c.clipW
  val emitVisibleY = leftEdge.y >= 0 && leftEdge.y < c.clipH
  val emitVisible = emitVisibleX && emitVisibleY

  io.o.valid := state === W.EmitSpan && emitVisible
  io.o.payload.x0 := leftEdge.x.resize(9 bits).asUInt
  io.o.payload.x1 := emitRight.resize(9 bits).asUInt
  io.o.payload.y := leftEdge.y.resize(9 bits).asUInt

  def nextRow(base: SpanWalker.Cursor, leftBiased: Boolean): Unit = {
    nextRowBase := base
    nextRowLeftBiased := Bool(leftBiased)
    state := W.AdvanceRow
  }

  def captureVisibleLeftEdgeFromProbe(): Unit = {
    when(pS < 0) {
      step(leftEdge, probe, right = true)
    }.otherwise {
      leftEdge := probe
    }
  }

  // k pixels' step of each edge value, k = 1 to nLook, and its negation: the searches' lookahead
  val aK, aKn = Vec.fill(nLook)(Vec.fill(3)(Reg(SInt(c.edgeBits bits))))

  when(state === W.Idle && io.i.valid) {
    for (n <- 0 until 3)
      bma(n) := (io.i.payload.b(n).resize(c.edgeBits bits) - io.i.payload.a(n).resize(c.edgeBits bits)) |<< c.xyFrac
    for (k <- 1 to nLook; n <- 0 until 3) {
      val a1 = io.i.payload.a(n).resize(c.edgeBits bits) |<< c.xyFrac
      val ak = (0 until 3).filter(b => ((k >> b) & 1) == 1).map(b => a1 |<< b).reduce(_ + _)
      aK(k - 1)(n) := ak
      aKn(k - 1)(n) := -ak
    }
    moved := True
    for (k <- Seq(rowGuess, probe, bookmark)) {
      k.x := io.i.payload.x0
      k.y := io.i.payload.y0
      k.e := io.i.payload.edge
    }
    visibleStart := Mux(tri.x0 > 0, tri.x0, S(0, c.pixBits bits))
    visibleEnd := Mux(tri.x1 < c.clipW, tri.x1, S(c.clipW, c.pixBits bits))
    lastRow := Mux(tri.y1 < c.clipH, tri.y1, S(c.clipH, c.pixBits bits))
    firstSpanPending := True
    state := W.Decide
  }

  when(state === W.Decide) {
    val dS = probe.x.resize(c.pixBits + 1 bits) - visibleStart.resize(c.pixBits + 1 bits)
    val dE = probe.x.resize(c.pixBits + 1 bits) - visibleEnd.resize(c.pixBits + 1 bits)
    pS := dS; pE := dE; bS := dS; bE := dE
    when(inside(probe)) {
      bookmark := probe
      state := W.SearchLeftToExit
    }.otherwise {
      state := W.SearchRightToEnter
    }
  }

  when(state === W.RecoverLeft) {
    when(inside(probe)) {
      when(!recoverFoundInside) {
        bookmarkFromProbe()
        recoverFoundInside := True
      }
      when(pS <= 0) {
        captureVisibleLeftEdgeFromProbe()
        // SpinalVoodoo takes the bookmark here even when this probe is the first inside pixel,
        // whose bookmark write lands only at this clock's end: the old bookmark is the row guess,
        // right of the span when it is outside, and the span then runs on to the guess.
        when(recoverFoundInside) { probeFromBookmark() }
        recoverFoundInside := False
        state := W.SearchRightToExit
      }.otherwise {
        stepProbe(right = false)
      }
    }.otherwise {
      when(recoverFoundInside) {
        step(leftEdge, probe, right = true)
        probeFromBookmark()
        recoverFoundInside := False
        state := W.SearchRightToExit
      }.elsewhen(pS <= 0) {
        probeFromBookmark()
        state := W.SearchRightToEnter
      }.otherwise {
        stepProbe(right = false)
      }
    }
  }

  when(state === W.SearchRightToEnter) {
    when(inside(probe) && pS >= 0) {
      leftEdge := probe
      bookmarkFromProbe()
      state := W.SearchRightToExit
    }.elsewhen(pE >= 0) {
      when(firstSpanPending) {
        nextRow(rowGuess, leftBiased = false)
      }.otherwise {
        nextRow(bookmark, leftBiased = true)
      }
    }.otherwise {
      stepProbe(right = true)
    }
  }

  when(state === W.SearchLeftToExit) {
    when(inside(probe)) {
      when(pS <= 0) {
        captureVisibleLeftEdgeFromProbe()
        probeFromBookmark()
        state := W.SearchRightToExit
      }.otherwise {
        stepProbe(right = false)
      }
    }.otherwise {
      step(leftEdge, probe, right = true)
      probeFromBookmark()
      state := W.SearchRightToExit
    }
  }

  when(state === W.SearchRightToExit) {
    when(inside(probe)) {
      when(pE >= 0) {
        emitRight := visibleEnd - 1
        state := W.EmitSpan
      }.otherwise {
        stepProbe(right = true)
      }
    }.otherwise {
      emitRight := probe.x - 1
      state := W.EmitSpan
    }
  }

  // Lookahead: a search state that steps the probe does nothing else on that clock, and steps while
  // its condition holds at the probe. So when the condition holds at the probe and the next
  // nLook - 1 pixels, the probe goes nLook pixels on; else a pixel, as before; the state's own logic
  // acts where it fails. The same states and spans as a pixel a clock (bbust2 f2000: 1.41 M of the
  // walker's 1.85 M clocks were these steps). The pixels' edge values are registers (ahead), so the
  // test is their signs: added from the probe in the test's clock it missed clk3d by 0.52 ns
  // (5367caf seed 1). `ahead` moves with the probe; when the probe is set otherwise, or the search
  // turns, it is made again from the probe, the step waiting that clock.
  def cont(in: Bool, gtS: Bool, geS: Bool, ltE: Bool): Bool = state.mux(
    W.RecoverLeft -> (in === recoverFoundInside && gtS),
    W.SearchRightToEnter -> (!(in && geS) && ltE),
    W.SearchLeftToExit -> (in && gtS),
    W.SearchRightToExit -> (in && ltE),
    default -> False)
  def inE(e: Vec[SInt]): Bool = e.map(_ >= 0).reduce(_ && _)
  // x + k against a bound is pS or pE against -k; x - k is pS against k (the right-going states test
  // only x >= start and x < end, the left-going only x > start)
  val runR = (1 until nLook).map(k => cont(inE(ahead(k - 1)), False, pS >= -k, pE < -k)).reduce(_ && _)
  val runL = (1 until nLook).map(k => cont(inE(ahead(k - 1)), pS > k, False, False)).reduce(_ && _)
  val here = cont(inside(probe), pS > 0, pS >= 0, pE < 0)
  val jump = aReady && here && (goRight ? runR | runL)
  when(jump) {
    probe.x := goRight ? (probe.x + nLook) | (probe.x - nLook)
    probe.e := ahead(nLook - 1)
    pS := goRight ? (pS + nLook) | (pS - nLook)
    pE := goRight ? (pE + nLook) | (pE - nLook)
  }
  // one add a value: a jump adds nLook pixels' step, a step moves them along and adds a pixel's to
  // the last, a remake adds k pixels' to the probe
  def kStep(k: Int): Vec[SInt] = Vec((0 until 3).map(n => goRight ? aK(k - 1)(n) | aKn(k - 1)(n)))
  val remake = !aReady && !moved
  for (k <- 1 to nLook; n <- 0 until 3) {
    val base = jump ? ahead(k - 1)(n) | (stepped ? ahead(k min (nLook - 1))(n) | probe.e(n))
    val delta = jump ? kStep(nLook)(n) |
      (stepped ? (if (k == nLook) kStep(1)(n) else S(0, c.edgeBits bits)) | kStep(k)(n))
    when(jump || stepped || remake) { ahead(k - 1)(n) := base + delta }
  }
  when(moved) { aValid := False }.elsewhen(remake) { aValid := True; aRight := goRight }

  when(state === W.EmitSpan && (!emitVisible || io.o.ready)) {
    firstSpanPending := False
    nextRow(leftEdge, leftBiased = true)
  }

  when(state === W.AdvanceRow) {
    when(nextRowBase.y + 1 >= lastRow && io.drained) {
      state := W.Idle
      firstSpanPending := False
      recoverFoundInside := False
    }.otherwise {
      val down = SpanWalker.Cursor(c)
      val downLeft = SpanWalker.Cursor(c)
      stepDown(down, nextRowBase)
      downLeft.x := nextRowBase.x - 1
      downLeft.y := nextRowBase.y + 1
      for (n <- 0 until 3) downLeft.e(n) := nextRowBase.e(n) + bma(n)
      val next = nextRowLeftBiased ? downLeft | down
      rowGuess := next
      probe := next
      moved := True
      val nS = next.x.resize(c.pixBits + 1 bits) - visibleStart.resize(c.pixBits + 1 bits)
      val nE = next.x.resize(c.pixBits + 1 bits) - visibleEnd.resize(c.pixBits + 1 bits)
      pS := nS; pE := nE; bS := nS; bE := nE
      bookmark := next
      recoverFoundInside := False
      state := nextRowLeftBiased ? W.RecoverLeft | W.Decide
    }
  }
}

object SpanWalker {
  case class Cursor(c: RasterConfig) extends Bundle {
    val x, y = SInt(c.pixBits bits)
    val e = Vec(SInt(c.edgeBits bits), 3)
  }

  /** A covered span as the walker finds it: pixels x0 to x1 inclusive of row y. */
  case class Walk() extends Bundle {
    val x0, x1, y = UInt(9 bits)
  }

  /** Pixels x0 to x1 inclusive of row y; the parameters at x0 and their step per pixel. */
  case class Span(c: RasterConfig) extends Bundle {
    val x0, x1, y = UInt(9 bits)
    val p = Params(c)
    val dx = Params(c)
    val attr = Bits(c.attrBits bits)
  }
}
