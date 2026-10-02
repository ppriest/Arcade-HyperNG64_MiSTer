// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** A span to pixels, one a clock, as SpinalVoodoo's `Rasterizer.SpanRasterizer` does through its
  * StreamWhile: the parameters step by dx from the span's first pixel.
  */
case class SpanPixels(c: RasterConfig) extends Component {
  val io = new Bundle {
    val i = slave(Stream(SpanWalker.Span(c)))
    val o = master(Stream(Raster.Pixel(c)))
    val busy = out Bool ()
  }
  val running = RegInit(False)
  val s = Reg(SpanWalker.Span(c))

  io.i.ready := !running
  io.busy := running
  io.o.valid := running
  io.o.payload.x := s.x0
  io.o.payload.y := s.y
  io.o.payload.p := s.p
  io.o.payload.attr := s.attr

  when(io.i.fire) {
    s := io.i.payload
    running := True
  }
  when(io.o.fire) {
    when(s.x0 >= s.x1) {
      running := False
    }.otherwise {
      s.x0 := s.x0 + 1
      for (k <- 0 until c.nParams) s.p.v(k) := s.p.v(k) + s.dx.v(k)
    }
  }
}

/** Triangles in (the setup record: vertices sorted by y, the plane's gradients, the pixel unit's
  * fields; computed by the geometry engine's microcode, geo_engine.setup_record), the render buffer
  * written in DDR3. `start` begins a frame (colour clear, depth scrub),
  * triangles follow, `finish` once the last is in; `done` when the frame is all in DDR3. `busy`
  * covers the raster and texturing, not the render buffer (whose `done` ends a frame).
  */
case class Raster(c: RasterConfig) extends Component {
  val io = new Bundle {
    val tri = slave(Stream(TriangleSetup.Input(c)))
    val depthRd = master(Stream(UInt(28 bits)))    // hng64_ddram's client port
    val depthData = slave(Flow(Bits(64 bits)))
    val wr = master(Stream(RenderBuf.Beat()))      // hng64_ddram's writer
    val urgent = out Bool ()
    val start = in Bool ()
    val full = in Bool ()
    val tag = in UInt (8 bits)
    val scrub = in UInt (7 bits)
    val colourBase = in UInt (28 bits)
    val depthBase = in UInt (28 bits)
    val finish = in Bool ()
    val done = out Bool ()
    val blockStart = in Bool ()                    // TexBlock: the start-up copy of textures0
    val blockSrc = in UInt (28 bits)
    val blockGroups = in UInt (12 bits)
    val blockDone = out Bool ()
    val texBase = in UInt (28 bits)                // the blocked textures' byte offset in DDR3
    val texRd = master(Stream(UInt(28 bits)))      // hng64_ddram's client port
    val texData = slave(Flow(Bits(64 bits)))
    val busy = out Bool ()
  }
  val setup = TriangleSetup(c)
  val walker = SpanWalker(c)
  val pixels = SpanPixels(c)
  val pixUnit = PixelUnit(c)
  val texCache = TexCache(c)
  val renderBuf = RenderBuf(c)
  val texBlock = TexBlock()

  // a register between the geometry engine's triangle and the setup (2.7 ns over clk2x across them)
  val triIn = io.tri.m2sPipe()
  setup.io.i << triIn
  walker.io.i << setup.io.o
  val spanParams = SpanParams(c)
  // a skid buffer between the walker and SpanParams, so the walker's ready is a register (from
  // the span queue's fill back into the walker's state it missed clk2x by 2.1 ns)
  val walkOut = walker.io.o.s2mPipe()
  spanParams.io.i << walkOut
  spanParams.io.tri := setup.io.o.payload
  walker.io.drained := spanParams.io.idle && !walker.io.o.valid && !walkOut.valid
  val spans = spanParams.io.o.queue(4)
  pixels.io.i << spans
  val skid0 = pixels.io.o.s2mPipe()                   // skid buffers: ready is registered here
  pixUnit.io.i << skid0
  val skid1 = pixUnit.io.o.s2mPipe()
  texCache.io.i << skid1
  texCache.io.texBase := io.texBase
  // the texture read port and the writer are TexBlock's while it runs (the 3D is idle then)
  val blocking = texBlock.io.busy
  texBlock.io.start := io.blockStart
  texBlock.io.src := io.blockSrc
  texBlock.io.dst := io.texBase
  texBlock.io.groups := io.blockGroups
  io.blockDone := texBlock.io.done
  io.texRd << StreamMux(blocking.asUInt, Seq(texCache.io.rdAddr, texBlock.io.rdAddr))
  texCache.io.rdData.valid := io.texData.valid && !blocking
  texCache.io.rdData.payload := io.texData.payload
  texBlock.io.rdData.valid := io.texData.valid && blocking
  texBlock.io.rdData.payload := io.texData.payload
  val skid2 = texCache.io.o.s2mPipe()
  renderBuf.io.i << skid2
  io.depthRd << renderBuf.io.rdAddr
  renderBuf.io.rdData << io.depthData
  io.wr << StreamMux(blocking.asUInt, Seq(renderBuf.io.wr, texBlock.io.wr))
  io.urgent := renderBuf.io.urgent
  renderBuf.io.start := io.start
  renderBuf.io.full := io.full
  renderBuf.io.tag := io.tag
  renderBuf.io.scrub := io.scrub
  renderBuf.io.colourBase := io.colourBase
  renderBuf.io.depthBase := io.depthBase
  renderBuf.io.finish := io.finish
  io.done := renderBuf.io.done
  // the engine holds each triangle until the setup has read it
  io.busy := io.tri.valid || triIn.valid || setup.io.o.valid || walker.io.busy || walkOut.valid || !spanParams.io.idle || spans.valid || pixels.io.busy ||
    skid0.valid || pixUnit.io.busy || skid1.valid || texCache.io.busy || skid2.valid
}

object Raster {
  case class Pixel(c: RasterConfig) extends Bundle {
    val x, y = UInt(9 bits)
    val p = Params(c)
    val attr = Bits(c.attrBits bits)
  }
}

/** Writes rtl/3d/hng64_raster.v (scripts/gen_3d_rtl.sh). */
object GenRaster extends App {
  SpinalConfig(
    mode = Verilog,
    targetDirectory = args.headOption.getOrElse("."),
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = SYNC),
    oneFilePerComponent = false,
    globalPrefix = "hng64_raster_",
    inlineRom = true                   // no $readmemb file: its path differs between tools
  ).generate(Raster(RasterConfig()).setDefinitionName("hng64_raster"))
}
