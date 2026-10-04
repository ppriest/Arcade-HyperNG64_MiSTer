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
case class SpanWalker(c: RasterConfig) extends Component {
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
    when(probe.x < visibleStart) {
      step(leftEdge, probe, right = true)
    }.otherwise {
      leftEdge := probe
    }
  }

  when(state === W.Idle && io.i.valid) {
    for (n <- 0 until 3)
      bma(n) := (io.i.payload.b(n).resize(c.edgeBits bits) - io.i.payload.a(n).resize(c.edgeBits bits)) |<< c.xyFrac
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
        bookmark := probe
        recoverFoundInside := True
      }
      when(probe.x <= visibleStart) {
        captureVisibleLeftEdgeFromProbe()
        // SpinalVoodoo takes the bookmark here even when this probe is the first inside pixel,
        // whose bookmark write lands only at this clock's end: the old bookmark is the row guess,
        // right of the span when it is outside, and the span then runs on to the guess.
        when(recoverFoundInside) { probe := bookmark }
        recoverFoundInside := False
        state := W.SearchRightToExit
      }.otherwise {
        step(probe, probe, right = false)
      }
    }.otherwise {
      when(recoverFoundInside) {
        step(leftEdge, probe, right = true)
        probe := bookmark
        recoverFoundInside := False
        state := W.SearchRightToExit
      }.elsewhen(probe.x <= visibleStart) {
        probe := bookmark
        state := W.SearchRightToEnter
      }.otherwise {
        step(probe, probe, right = false)
      }
    }
  }

  when(state === W.SearchRightToEnter) {
    when(inside(probe) && probe.x >= visibleStart) {
      leftEdge := probe
      bookmark := probe
      state := W.SearchRightToExit
    }.elsewhen(probe.x >= visibleEnd) {
      when(firstSpanPending) {
        nextRow(rowGuess, leftBiased = false)
      }.otherwise {
        nextRow(bookmark, leftBiased = true)
      }
    }.otherwise {
      step(probe, probe, right = true)
    }
  }

  when(state === W.SearchLeftToExit) {
    when(inside(probe)) {
      when(probe.x <= visibleStart) {
        captureVisibleLeftEdgeFromProbe()
        probe := bookmark
        state := W.SearchRightToExit
      }.otherwise {
        step(probe, probe, right = false)
      }
    }.otherwise {
      step(leftEdge, probe, right = true)
      probe := bookmark
      state := W.SearchRightToExit
    }
  }

  when(state === W.SearchRightToExit) {
    when(inside(probe)) {
      when(probe.x >= visibleEnd) {
        emitRight := visibleEnd - 1
        state := W.EmitSpan
      }.otherwise {
        step(probe, probe, right = true)
      }
    }.otherwise {
      emitRight := probe.x - 1
      state := W.EmitSpan
    }
  }

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
