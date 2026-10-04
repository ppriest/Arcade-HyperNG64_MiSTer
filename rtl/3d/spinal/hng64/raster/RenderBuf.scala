// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** The render buffer in DDR3 (docs/phase3_3d.md, DDR3 traffic; user decision): one depth plane
  * shared by every frame and a colour plane per buffer.
  *
  * Depth: a 32-bit word a pixel, row-major, the frame tag in the top 8 bits and z's top 24 bits
  * below (render_3d_fx.py Z_DROP). A word whose tag is not this frame's reads as cleared, so the
  * plane is never cleared; instead each frame first rewrites 1/128 of it with a tag 128 away from
  * its own, so no word can keep a tag long enough to come round again (every region is rewritten
  * within 128 frames, and tags repeat after 256). `full` rewrites all of it, for the first frame.
  *
  * The depth cache: 1 KB, 2-way, 64-byte lines (16 pixels), write-back, prefetching as TexCache
  * does: tags and LRU in registers, checked as a fragment enters; a miss requests its line (eight
  * 8-byte reads) and reserves its victim; beats are gathered into whole lines as they arrive; at
  * the fragment's turn the victim is read out whole, the new line written whole, and a dirty victim
  * drained to DDR3 behind. A victim stays in `pending` until its last beat has left, and a miss for
  * a pending line waits, so a line is never read back before its write-back is ahead of the read.
  * The line's 16 pixels are 16 one-word banks, so a line fills in one clock and a pixel is read and
  * written on its own.
  *
  * Colour: 16 bits a pixel, cleared at the frame's start (the display reads colour alone), written
  * through a one-line (32-pixel) write combiner.
  */
case class RenderBuf(c: RasterConfig, fifoDepth: Int = 64, fillLines: Int = 8) extends Component {
  val io = new Bundle {
    val i = slave(Stream(TexCache.Texeled(c)))
    val rdAddr = master(Stream(UInt(28 bits)))
    val rdData = slave(Flow(Bits(64 bits)))
    val wr = master(Stream(RenderBuf.Beat()))
    val urgent = out Bool ()                         // hng64_ddram's w_urgent: writes before reads

    val start = in Bool ()                           // one clock: begin a frame with these
    val full = in Bool ()
    val tag = in UInt (8 bits)
    val scrub = in UInt (7 bits)
    val colourBase = in UInt (28 bits)
    val depthBase = in UInt (28 bits)
    val finish = in Bool ()                          // one clock: no more fragments this frame
    val done = out Bool ()                           // one clock: every write of the frame issued
    val busy = out Bool ()
  }

  val nSets = 8
  val nWays = 2
  val nSlots = nSets * nWays

  // ---- frame control ----------------------------------------------------------------------------
  object F extends SpinalEnum { val Idle, Clear, Scrub, Render, Drain, Flush, Done = newElement() }
  val fs = RegInit(F.Idle)
  val tag = Reg(UInt(8 bits))
  val full = Reg(Bool())
  val scrubPhase = Reg(UInt(7 bits))
  val cBase, dBase = Reg(UInt(28 bits))
  val finishing = RegInit(False)
  val count = Reg(UInt(18 bits))
  io.done := False

  when(fs === F.Idle && io.start) {
    tag := io.tag
    full := io.full
    scrubPhase := io.scrub
    cBase := io.colourBase
    dBase := io.depthBase
    count := 0
    finishing := False
    fs := F.Clear
  }
  when(io.finish) { finishing := True }

  // ---- writes: clear and scrub, write-backs, colour; one FIFO to hng64_ddram ---------------------
  val clearW = Stream(RenderBuf.QBeat())
  val backW = Stream(RenderBuf.QBeat())
  val colourW = Stream(RenderBuf.QBeat())
  val wq = StreamFifo(RenderBuf.QBeat(), 16)
  wq.io.push << StreamArbiterFactory.lowerFirst.on(Seq(backW, colourW, clearW))
  io.wr << wq.io.pop.translateWith(wq.io.pop.b)
  io.urgent := wq.io.occupancy >= 8

  // colour: 65,536 beats of zero; depth: 1,024 beats (8 KB, 1/128) or all 131,072
  val stale = (tag + 128).asBits
  clearW.valid := fs === F.Clear || fs === F.Scrub
  clearW.payload.rel := False
  clearW.payload.relSlot := 0
  clearW.payload.b.addr := (fs === F.Clear) ? (cBase + (count @@ U(0, 3 bits)).resize(28 bits)) |
    (dBase + ((full ? count(16 downto 0) | (scrubPhase @@ count(9 downto 0))) @@ U(0, 3 bits)).resize(28 bits))
  clearW.payload.b.data := (fs === F.Clear) ? B(0, 64 bits) | (stale ## B(0, 24 bits) ## stale ## B(0, 24 bits))
  clearW.payload.b.be := B"8'xFF"
  when(clearW.fire) {
    count := count + 1
    when(fs === F.Clear && count === 65535) {
      count := 0
      fs := F.Scrub
    }
    when(fs === F.Scrub && ((full && count === 131071) || (!full && count === 1023))) {
      fs := F.Render
    }
  }

  // ---- the fragment: colour, draw, z ---------------------------------------------------------------
  // registered before the tag lookup (m2sPipe): from the texture cache's output through the prep,
  // the lookup and the pending-slot pick in one clock missed clk2x by 3.6 ns. The hold outside
  // F.Render comes after the register, so no fragment passes it during a clear or flush.
  val prep = (io.i.throwWhen({
    val f = io.i.f
    val pen = f.tex4bpp ? (f.nib ? io.i.texel(7 downto 4) | io.i.texel(3 downto 0)).resize(8 bits) | io.i.texel
    !f.flat && pen === 0
  }) ~~ { t =>
    val o = RenderBuf.Frag()
    val f = t.f
    val pen = f.tex4bpp ? (f.nib ? t.texel(7 downto 4) | t.texel(3 downto 0)).resize(8 bits).asUInt | t.texel.asUInt
    val pal = (f.pal.asUInt + pen).resize(11 bits)
    o.colour := f.flat ? f.pal | (f.light(3 downto 0) ## f.blend ## pal.asBits)
    val zs = f.z >> 4
    o.z := (zs < 0) ? U(0, 24 bits) | ((zs >= (1 << 24)) ? U((1 << 24) - 1, 24 bits) | zs.asUInt.resize(24 bits))
    o.x := f.x
    o.y := f.y
    o
  }).m2sPipe().haltWhen(fs =/= F.Render)

  // ---- entry: tags, LRU, pending victims ------------------------------------------------------------
  val tValid = Vec.fill(nSlots)(RegInit(False))
  val tTag = Vec.fill(nSlots)(Reg(UInt(11 bits)))
  val lru = Vec.fill(nSets)(RegInit(False))           // the way to replace next
  // a miss holds a pending slot from entry until its victim is written back (or found clean)
  val pOcc = Vec.fill(fillLines)(RegInit(False))
  val pVic = Vec.fill(fillLines)(Reg(Bool()))       // the slot's victim is a real line
  val pLine = Vec.fill(fillLines)(Reg(UInt(14 bits)))
  val credits = Reg(UInt(log2Up(fillLines + 1) bits)) init (fillLines)
  val frags = StreamFifo(RenderBuf.Waiting(), fifoDepth)
  val missQ = StreamFifo(UInt(14 bits), 8)

  val e = prep.payload
  val line = e.y @@ e.x(8 downto 4)                  // 14 bits: 32 lines a row
  val set = line(2 downto 0)
  val ltag = line(13 downto 3)
  val hitW = Vec((0 until nWays).map(w => tValid(set @@ U(w, 1 bits)) && tTag(set @@ U(w, 1 bits)) === ltag))
  val hit = hitW.orR
  val way = hit ? hitW(1).asUInt | lru(set).asUInt
  val slot = set @@ way
  val vValid = tValid(slot)
  val vLine = tTag(slot) @@ set
  val pendingHit = (0 until fillLines).map(k => pOcc(k) && pVic(k) && pLine(k) === line).orR
  val free = Vec(pOcc.map(!_)).asBits
  val freeSlot = OHToUInt(OHMasking.first(free))
  // the lookup's record goes into the FIFO through a register (fragIn): from the tags through the
  // hit, way and slot into the FIFO's write data missed clk2x by 2.25 ns. The tags, LRU and
  // pending slots still change on the lookup's clock; the FIFO keeps the order.
  val fragIn = Stream(RenderBuf.Waiting())
  frags.io.push << fragIn.m2sPipe()
  val canGo = fragIn.ready &&
    (hit || (!pendingHit && free.orR && credits =/= 0 && missQ.io.push.ready))

  prep.ready := canGo
  fragIn.valid := prep.valid && canGo
  fragIn.payload.f := e
  fragIn.payload.slot := slot
  fragIn.payload.miss := !hit
  fragIn.payload.victim := vValid
  fragIn.payload.vLine := vLine
  fragIn.payload.pend := freeSlot
  missQ.io.push.valid := prep.valid && canGo && !hit
  missQ.io.push.payload := line

  val consume = Bool()
  val release = Flow(UInt(log2Up(fillLines) bits))    // a clean victim, at its fill
  val releaseWb = Flow(UInt(log2Up(fillLines) bits))  // a dirty victim, its last beat gone
  val allocate = prep.fire && !hit
  // a free slot's victim fields are not looked at (pendingHit needs pOcc), so every free slot takes
  // the victim a miss here would have, and an allocation only marks one occupied. A miss replaces
  // the LRU way, so that victim is read through lru(set), not the hit: from the lookup's hit into
  // these missed clk3d by 0.95 ns.
  val mSlot = set @@ lru(set).asUInt
  for (k <- 0 until fillLines) when(!pOcc(k)) {
    pVic(k) := tValid(mSlot)
    pLine(k) := tTag(mSlot) @@ set
  }
  when(prep.fire) {
    lru(set) := !way.asBool
    when(!hit) {
      tValid(slot) := True
      tTag(slot) := ltag
      pOcc(freeSlot) := True
    }
  }
  when(release.valid) { pOcc(release.payload) := False }
  when(releaseWb.valid) { pOcc(releaseWb.payload) := False }
  credits := credits - U(allocate) + U(consume)

  // ---- misses out, lines in ----------------------------------------------------------------------------
  val beat = Reg(UInt(3 bits)) init (0)
  io.rdAddr.valid := missQ.io.pop.valid
  io.rdAddr.payload := dBase + (missQ.io.pop.payload @@ beat @@ U(0, 3 bits)).resize(28 bits)
  missQ.io.pop.ready := io.rdAddr.ready && beat === 7
  when(io.rdAddr.fire) { beat := beat + 1 }

  val gather = Reg(Vec(Bits(64 bits), 8))
  val gBeat = Reg(UInt(3 bits)) init (0)
  val lineQ = StreamFifo(Bits(512 bits), fillLines)
  lineQ.io.push.valid := io.rdData.valid && gBeat === 7
  lineQ.io.push.payload := io.rdData.payload ## gather.reverse.drop(1).reduce(_ ## _)
  when(io.rdData.valid) {
    gather(gBeat) := io.rdData.payload
    gBeat := gBeat + 1
  }

  // ---- the line store: 16 banks of one 32-bit word, one a pixel of the line --------------------------
  // M10K, not MLAB: 16 of the 166 blocks the full fit left free, for about 320 ALMs. Their reads are
  // registered, and a read in the clock of a write to the same word is covered by the bypass from
  // lastWr, so the block's read-during-write behaviour is never seen.
  val banks = (0 until 16).map { k =>
    val m = Mem(Bits(32 bits), nSlots)
    m.addAttribute("ramstyle", "M10K")
    m
  }
  val dirty = Vec.fill(nSlots)(RegInit(False))

  // ---- the head: fill a miss, then the depth test ----------------------------------------------------
  val head = frags.io.pop
  val h = head.payload
  object H extends SpinalEnum { val Wait, ReadVictim, Fill = newElement() }
  val hs = RegInit(H.Wait)
  val filled = RegInit(False)
  val vBuf = Reg(Vec(Bits(64 bits), 8))
  val vLeft = Reg(UInt(4 bits)) init (0)              // beats of the victim still to drain
  val vAddr = Reg(UInt(14 bits))
  val vPend = Reg(UInt(log2Up(fillLines) bits))
  val vRelease = Reg(Bool())                          // the drain frees vPend when it ends

  // the depth pipeline: R reads the banks, C compares and writes
  val rValid = RegInit(False)
  val rF = Reg(RenderBuf.Waiting())
  val sValidW, cValidW = Bool()                       // S and C hold a fragment (below)
  val rIdle = !rValid && !sValidW && !cValidW

  val bankRdAddr = UInt(4 bits)
  val bankRdEn = Bool()
  val bankRd = banks.map(_.readSync(bankRdAddr, bankRdEn))

  consume := False
  release.valid := False
  release.payload := vPend
  lineQ.io.pop.ready := False

  val needFill = head.valid && h.miss && !filled
  val go = Bool()
  bankRdAddr := go ? h.slot | rF.slot                  // below: the fill's and drain's reads override
  bankRdEn := go || rValid
  when(hs === H.Wait && needFill && lineQ.io.pop.valid && vLeft === 0 && rIdle) {
    bankRdAddr := h.slot
    bankRdEn := True                                   // the victim's words, whole
    hs := H.ReadVictim
  }
  when(hs === H.ReadVictim) {
    val drain = h.victim && dirty(h.slot)
    for (j <- 0 until 8) vBuf(j) := bankRd(2 * j + 1) ## bankRd(2 * j)
    vAddr := h.vLine
    vPend := h.pend
    vRelease := True
    vLeft := drain ? U(8, 4 bits) | U(0, 4 bits)
    when(!drain) { release.valid := True; release.payload := h.pend }
    lineQ.io.pop.ready := True
    dirty(h.slot) := False
    consume := True
    filled := True
    hs := H.Wait
  }

  // the victim's last beat frees its pending slot as it leaves for DDR3, not as it enters the
  // queue: a read of the line must not reach DDR3 ahead of the write-back
  backW.valid := vLeft =/= 0
  backW.payload.b.addr := dBase + (vAddr @@ (U(8, 4 bits) - vLeft).resize(3 bits) @@ U(0, 3 bits)).resize(28 bits)
  backW.payload.b.data := vBuf((U(8, 4 bits) - vLeft).resize(3 bits))
  backW.payload.b.be := B"8'xFF"
  backW.payload.rel := vLeft === 1 && vRelease
  backW.payload.relSlot := vPend
  when(backW.fire) { vLeft := vLeft - 1 }
  releaseWb.valid := io.wr.fire && wq.io.pop.rel
  releaseWb.payload := wq.io.pop.relSlot

  // R: the fragment's line is present and its words are read (again every clock while it waits,
  // so the read has every write but the latest). S: the fragment's word, from that read or from a
  // write not yet in it (the fragment ahead in S, then C, then the last write), and the depth test,
  // registered. C: the write, and the colour. The compare's long path ends in S's registers; the
  // write enables of the sixteen banks start from C's.
  val sValid = RegInit(False)
  val cValid = RegInit(False)
  val sF, cF = Reg(RenderBuf.Waiting())
  val sPass, cPass = Reg(Bool())
  val sWord, cWord = Reg(Bits(32 bits))
  val lastWr = RegInit(False)
  val lastSlot = Reg(UInt(4 bits))
  val lastPx = Reg(UInt(4 bits))
  val lastWord = Reg(Bits(32 bits))

  val comb = Stream(RenderBuf.Colour())
  val cDone = !cValid || !cPass || comb.ready       // C empty, or leaving this clock
  val sMove = sValid && cDone
  val sFree = !sValid || cDone
  val rMove = rValid && sFree
  val rFree = !rValid || sFree
  go := head.valid && (!h.miss || filled) && hs === H.Wait && !(needFill) && rFree
  head.ready := go
  when(go) { filled := False }
  when(go) { rF := h; rValid := True }.elsewhen(rMove) { rValid := False }

  // S
  val px = rF.f.x(3 downto 0)
  def same(v: Bool, f: RenderBuf.Waiting) = v && f.slot === rF.slot && f.f.x(3 downto 0) === px
  val readWord = Vec(bankRd)(px)
  // The depth test made on each candidate word, then the result picked by the same priority: picked
  // as a word ahead of the tag and depth compares, from sPass through the bypass select into sPass it
  // missed clk3d by 0.44 ns (6063e54 seed 2 with the stronger fitter settings).
  def passOf(w: Bits): Bool = {
    val storedZ = (w(31 downto 24).asUInt === tag) ? w(23 downto 0).asUInt.resize(25 bits) | U(1 << 24, 25 bits)
    rF.f.z.resize(25 bits) < storedZ
  }
  val pass = Bool()
  pass := passOf(readWord)
  when(lastWr && lastSlot === rF.slot && lastPx === px) { pass := passOf(lastWord) }
  when(same(cValid && cPass, cF)) { pass := passOf(cWord) }
  when(same(sValid && sPass, sF)) { pass := passOf(sWord) }
  when(rMove) {
    sF := rF
    sPass := pass
    sWord := tag.asBits ## rF.f.z.asBits
    sValid := True
  }.elsewhen(sMove) { sValid := False }
  when(sMove) {
    cF := sF
    cPass := sPass
    cWord := sWord
    cValid := True
  }.elsewhen(cDone) { cValid := False }

  // C
  comb.valid := cValid && cPass
  comb.payload.pixel := cF.f.y @@ cF.f.x
  comb.payload.colour := cF.f.colour

  // one write port a bank (an MLAB has one): the whole line at a fill, or the pixel's word.
  // Mem.write's explicit enable is not qualified by an enclosing `when`, so it carries all of it.
  val fillNow = hs === H.ReadVictim
  val cWrite = cValid && cPass && comb.ready
  val cPx = cF.f.x(3 downto 0)
  for (k <- 0 until 16) {
    banks(k).write(
      address = fillNow ? h.slot | cF.slot,
      data = fillNow ? lineQ.io.pop.payload(32 * k + 31 downto 32 * k) | cWord,
      enable = fillNow || (cWrite && cPx === k))
  }

  lastWr := False
  when(cWrite) {
    dirty(cF.slot) := True
    lastWr := True
    lastSlot := cF.slot
    lastPx := cPx
    lastWord := cWord
  }

  sValidW := sValid
  cValidW := cValid

  // ---- colour: a one-line write combiner ------------------------------------------------------------
  val cLine = Reg(UInt(13 bits))
  val cData = Reg(Vec(Bits(64 bits), 8))
  val cBe = Vec.fill(8)(Reg(Bits(8 bits)) init (B(0, 8 bits)))
  val flushing = RegInit(False)
  val fBeat = Reg(UInt(3 bits)) init (0)
  // the combiner holds a pixel: set as one enters, cleared as a flush ends (no pixel enters while
  // it flushes). A register rather than the OR of all 64 enables, which sat in front of the depth
  // banks' read address through comb.ready and go (the first full fit, -5.5 ns).
  val anyBe = RegInit(False)
  val cLineOf = comb.pixel(17 downto 5)
  val needFlush = comb.valid && anyBe && cLineOf =/= cLine
  val frameFlush = fs === F.Flush && anyBe

  when(!flushing && (needFlush || frameFlush)) {
    flushing := True
    fBeat := 0
  }
  colourW.valid := flushing && cBe(fBeat).orR
  colourW.payload.rel := False
  colourW.payload.relSlot := 0
  colourW.payload.b.addr := cBase + (cLine @@ fBeat @@ U(0, 3 bits)).resize(28 bits)
  colourW.payload.b.data := cData(fBeat)
  colourW.payload.b.be := cBe(fBeat)
  when(flushing && (colourW.fire || !cBe(fBeat).orR)) {
    cBe(fBeat) := B(0, 8 bits)
    fBeat := fBeat + 1
    when(fBeat === 7) { flushing := False; anyBe := False }
  }
  comb.ready := !flushing && !needFlush
  when(comb.fire) {
    val off = comb.pixel(4 downto 0)
    anyBe := True
    cLine := cLineOf
    for (j <- 0 until 8; l <- 0 until 4) {
      when(off === j * 4 + l) {
        cData(j)(16 * l + 15 downto 16 * l) := comb.colour
        cBe(j)(2 * l + 1 downto 2 * l) := B"11"
      }
    }
  }

  // ---- the frame's end: every fragment through, every dirty line and the combiner written -------------
  val pipeEmpty = !prep.valid && !frags.io.push.valid && frags.io.occupancy === 0 && rIdle && missQ.io.occupancy === 0 &&
    lineQ.io.occupancy === 0 && vLeft === 0 && hs === H.Wait
  val flushSlot = Reg(UInt(5 bits))
  when(fs === F.Render && finishing && pipeEmpty && !io.i.valid) {
    flushSlot := 0
    fs := F.Drain
  }
  // Drain: each dirty slot read whole into the victim buffer and written back
  val drainRead = RegInit(False)
  when(fs === F.Drain && vLeft === 0 && !drainRead) {
    when(flushSlot.msb) {
      fs := F.Flush
    }.elsewhen(tValid(flushSlot(3 downto 0)) && dirty(flushSlot(3 downto 0))) {
      bankRdAddr := flushSlot(3 downto 0)
      bankRdEn := True
      drainRead := True
    }.otherwise {
      flushSlot := flushSlot + 1
    }
  }
  when(drainRead) {
    val s = flushSlot(3 downto 0)
    for (j <- 0 until 8) vBuf(j) := bankRd(2 * j + 1) ## bankRd(2 * j)
    vAddr := tTag(s) @@ s(3 downto 1)
    vLeft := 8
    vRelease := False
    dirty(s) := False
    drainRead := False
    flushSlot := flushSlot + 1
  }
  when(fs === F.Flush && !anyBe && !flushing && wq.io.occupancy === 0 && !wq.io.pop.valid) {
    fs := F.Done
  }
  when(fs === F.Done) {
    io.done := True
    for (k <- 0 until nSlots) tValid(k) := False      // the next frame's tag makes every line stale
    fs := F.Idle
  }

  io.busy := fs =/= F.Idle
}

object RenderBuf {
  case class Beat() extends Bundle {
    val addr = UInt(28 bits)                         // byte offset from the core's DDR3 base
    val data = Bits(64 bits)
    val be = Bits(8 bits)
  }

  case class QBeat() extends Bundle {
    val b = Beat()
    val rel = Bool()                                 // the last beat of a victim: free relSlot
    val relSlot = UInt(3 bits)
  }

  case class Frag() extends Bundle {
    val x, y = UInt(9 bits)
    val z = UInt(24 bits)
    val colour = Bits(16 bits)
  }

  case class Waiting() extends Bundle {
    val f = Frag()
    val slot = UInt(4 bits)
    val miss = Bool()
    val victim = Bool()
    val vLine = UInt(14 bits)
    val pend = UInt(3 bits)
  }

  case class Colour() extends Bundle {
    val pixel = UInt(18 bits)
    val colour = Bits(16 bits)
  }
}
