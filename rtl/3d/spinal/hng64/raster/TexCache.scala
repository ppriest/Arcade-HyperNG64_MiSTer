// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** The texture cache: 8 KB, direct mapped, 32-byte lines, over the blocked copy of textures0
  * (docs/phase3_3d.md, DDR3 traffic: 4 x 8-byte blocks, one a line).
  *
  * Prefetching, after Igehy, Eldridge and Proudfoot (1998): a fragment's tag is checked as it
  * enters and a miss requests its line at once; the fragment then waits in a FIFO long enough to
  * cover DDR3's latency. Lines arrive in order into a fill FIFO, and a miss's line is written into
  * the data RAM only when that fragment reaches the FIFO's head, so no fragment ahead of it can
  * lose the line it was promised. Tags change at entry: a later fragment wanting an evicted line
  * misses and fetches it again.
  *
  * The blocked address of texel byte A (row A >> 10, column A & 1023) is
  * (row >> 3) : (column >> 2) : (row & 7) : (column & 3), so a 32-byte line is 8 rows of 4 bytes and
  * the cache index is column >> 2. Flat fragments pass through untouched.
  *
  * Memory: 8-byte reads at `texBase` + the blocked address, a request held until accepted, the
  * replies in order (hng64_ddram's client port).
  */
case class TexCache(c: RasterConfig, fifoDepth: Int = 128, fillLines: Int = 16) extends Component {
  val io = new Bundle {
    val i = slave(Stream(Fragment(c)))
    val o = master(Stream(TexCache.Texeled(c)))
    val texBase = in UInt (28 bits)
    val rdAddr = master(Stream(UInt(28 bits)))
    val rdData = slave(Flow(Bits(64 bits)))
    val busy = out Bool ()
  }

  val lines = 256

  // ---- invalidate every tag out of reset ------------------------------------------------------------
  val tagRam = Mem(Bits(12 bits), lines)            // valid, tag
  val clearIdx = Reg(UInt(9 bits)) init (0)
  val clearing = !clearIdx.msb
  when(clearing) { clearIdx := clearIdx + 1 }

  def blocked(a: UInt): UInt = a(23 downto 13) @@ a(9 downto 2) @@ a(12 downto 10) @@ a(1 downto 0)

  // ---- entry: read the tag ------------------------------------------------------------------------
  val entry = io.i.haltWhen(clearing)
  val tagRd = tagRam.streamReadSync(entry.translateWith(entry.addr(9 downto 2)), entry.payload)

  // ---- compare, allocate, request -----------------------------------------------------------------
  val lastWrValid = RegInit(False)
  val lastWrIdx = Reg(UInt(8 bits))
  val lastWrTag = Reg(Bits(12 bits))

  val credits = Reg(UInt(log2Up(fillLines + 1) bits)) init (fillLines)
  val missQ = StreamFifo(UInt(19 bits), 8)
  val frags = StreamFifo(TexCache.Waiting(c), fifoDepth)

  val f = tagRd.linked
  val ba = blocked(f.addr)
  val idx = ba(12 downto 5)
  val tag = B"1" ## ba(23 downto 13).asBits
  val stored = (lastWrValid && lastWrIdx === idx) ? lastWrTag | tagRd.value
  val miss = !f.flat && stored =/= tag
  val consume = Bool()

  val canGo = frags.io.push.ready && (!miss || (missQ.io.push.ready && credits =/= 0))
  tagRd.ready := canGo
  frags.io.push.valid := tagRd.valid && canGo
  frags.io.push.payload.f := f
  frags.io.push.payload.word := ba(12 downto 3)
  frags.io.push.payload.byte := ba(2 downto 0)
  frags.io.push.payload.miss := miss
  missQ.io.push.valid := tagRd.valid && canGo && miss
  missQ.io.push.payload := ba(23 downto 5)

  val allocate = tagRd.fire && miss
  when(allocate) {
    lastWrValid := True
    lastWrIdx := idx
    lastWrTag := tag
  }
  tagRam.write(clearing ? clearIdx(7 downto 0) | idx, clearing ? B(0, 12 bits) | tag, clearing || allocate)
  when(clearing) { lastWrValid := False }
  credits := credits - U(allocate) + U(consume)

  // ---- issue each missed line as four reads -----------------------------------------------------------
  val beat = Reg(UInt(2 bits)) init (0)
  io.rdAddr.valid := missQ.io.pop.valid
  io.rdAddr.payload := io.texBase + (missQ.io.pop.payload @@ beat @@ U(0, 3 bits)).resize(28 bits)
  missQ.io.pop.ready := io.rdAddr.ready && beat === 3
  when(io.rdAddr.fire) { beat := beat + 1 }

  val fill = StreamFifo(Bits(64 bits), 4 * fillLines)
  fill.io.push.valid := io.rdData.valid
  fill.io.push.payload := io.rdData.payload

  // ---- the head: write a miss's line, then read the texel's word ---------------------------------------
  val dataRam = Mem(Bits(64 bits), lines * 4)
  val head = frags.io.pop
  val filling = RegInit(False)
  val filled = RegInit(False)
  val fillBeat = Reg(UInt(2 bits)) init (0)

  fill.io.pop.ready := filling
  when(!filling && !filled && head.valid && head.miss && fill.io.occupancy >= 4) {
    filling := True
    fillBeat := 0
  }
  dataRam.write(head.word(9 downto 2) @@ fillBeat, fill.io.pop.payload, filling && fill.io.pop.valid)
  when(filling && fill.io.pop.valid) {
    fillBeat := fillBeat + 1
    when(fillBeat === 3) {
      filling := False
      filled := True
    }
  }
  consume := filling && fill.io.pop.valid && fillBeat === 3

  val go = head.haltWhen(head.miss && !filled)
  when(go.fire) { filled := False }
  val rd = dataRam.streamReadSync(go.translateWith(go.word), go.payload)

  val texeled = (rd ~~ { r =>
    val o = TexCache.Texeled(c)
    o.f := r.linked.f
    o.texel := r.value.subdivideIn(8 bits)(r.linked.byte)       // DDR3 is little-endian
    o
  }).m2sPipe()
  io.o << texeled

  io.busy := clearing || tagRd.valid || frags.io.occupancy =/= 0 || rd.valid || texeled.valid ||
    missQ.io.occupancy =/= 0 || fill.io.occupancy =/= 0
}

object TexCache {
  case class Waiting(c: RasterConfig) extends Bundle {
    val f = Fragment(c)
    val word = UInt(10 bits)         // the line's index and the 8-byte word within it
    val byte = UInt(3 bits)          // the texel's byte in that word
    val miss = Bool()
  }

  case class Texeled(c: RasterConfig) extends Bundle {
    val f = Fragment(c)
    val texel = Bits(8 bits)
  }
}
