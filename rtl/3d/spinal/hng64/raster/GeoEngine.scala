// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

import scala.io.Source

/** The geometry engine (user decision: microcoded; docs/phase3_3d.md). It runs the microcode
  * scripts/geo_ucode.py assembles, with the instruction set scripts/geo_engine.py defines and
  * simulates; that simulator is the reference this is checked against (sim/geo_tb).
  *
  * Pipeline, in order, one instruction a clock:
  *   F  the microcode ROM is read at `fetch`: the branch target, or the next address
  *   D  the instruction; the register file's reads (copies A and B of a 512 x 48 RAM, read every
  *      clock so a held instruction sees writes made while it waited)
  *   E  operands (forwarded from M and W), the ALU, branches (resolved here, the fetch redirected
  *      the clock after: two instructions dropped, two clocks), the multiplier
  *   M  the accumulator (MUL, MAC, MSB, LDA, ADA, ADAV, ASHL, in order), the accumulator stores
  *      (ST, STF, STV), and every register write
  * An instruction using the value of the store just before it waits a clock (the store's value
  * exists only at M), as does an accumulator branch or DIV straight after an accumulator op.
  * LDX, STX, TRSQ, TRCP, DL, SHLV, LOG2 and NORM take a clock more (copy X of the register file serves the indexed
  * reads), DIV its quotient bits and one, VRD until its word is there, EMIT 23 while the setup
  * record (22 words, TriangleSetup.Input: the rasteriser's gradients are computed in microcode)
  * is read out through copy X.
  */
case class GeoEngine(ucodeDir: String, c: RasterConfig = RasterConfig()) extends Component {
  val io = new Bundle {
    val start = in Bool ()                           // one clock: run from `entry`
    val entry = in UInt (2 bits)                     // 0 init, 1 clear, 2 upload
    val samsho = in Bool ()                          // written into the microcode's registers at init
    val vlen = in UInt (24 bits)
    val busy = out Bool ()

    val dlAddr = out UInt (8 bits)                   // the display list, data the clock after
    val dlData = in Bits (16 bits)
    val wrap = in Vec (UInt(8 bits), 32)

    val vBase = in UInt (28 bits)                    // the vertex ROM's byte offset in DDR3
    val vRd = master(Stream(UInt(28 bits)))          // hng64_ddram's client port
    val vData = slave(Flow(Bits(64 bits)))

    val tri = master(Stream(TriangleSetup.Input(c)))  // the setup record (geo_engine.setup_record)
  }

  // ---- the microcode and tables, as scripts/geo_ucode.py --export wrote them ---------------------
  def hexLines(f: String) =
    Source.fromFile(s"$ucodeDir/$f").getLines().filter(_.nonEmpty).map(BigInt(_, 16)).toSeq
  val info = Source.fromFile(s"$ucodeDir/ucode_info.txt").getLines().map(_.split(" ")).toSeq
  def entryOf(n: String) = info.find(l => l(0) == "entry" && l(1) == n).get(2).toInt
  def regOf(n: String) = info.find(l => l(0) == "reg" && l(1) == n).get(2).toInt
  val ucode = hexLines("ucode.hex")
  require(ucode.size <= 2048, "the microcode is over 2,048 words")
  val rom = Mem(Bits(49 bits), 2048) init ((ucode ++ Seq.fill(2048 - ucode.size)(BigInt(0))).map(B(_, 49 bits)))
  val rsqRom = Mem(UInt(17 bits), 256) init (hexLines("rsq.hex").map(U(_, 17 bits)))
  val rcpRom = Mem(UInt(12 bits), 1024) init (hexLines("rcp.hex").map(U(_, 12 bits)))

  // opcodes: scripts/geo_engine.py OPS, in order
  val OPS = Seq("NOP", "MUL", "MAC", "MSB", "LDA", "ADA", "ADAV", "ASHL", "ST", "STF", "STV", "DIV",
    "ADD", "SUB", "MIN", "MAX", "OR", "AND", "ADDI", "ANDI", "SHLI", "SHRI", "SHLV", "MOVI", "NEG",
    "ABS", "SEXT16", "LOG2", "NORM", "LDX", "STX", "TRSQ", "TRCP", "WRAP", "DL", "VSEEK", "VRD",
    "VRDS", "AOUT", "VOUT", "EMIT", "J", "JAL", "RET", "BZ", "BNZ", "BLTZ", "BGEZ", "BLT", "BGE",
    "BEQ", "BNE", "BACCN", "BACCNN", "BGTZ", "HALT", "STVW")
  def op(n: String) = U(OPS.indexOf(n), 6 bits)
  def fOp(i: Bits) = i(48 downto 43).asUInt
  def fD(i: Bits) = i(42 downto 34).asUInt
  def fA(i: Bits) = i(33 downto 25).asUInt
  def fB(i: Bits) = i(24 downto 16).asUInt
  def fI(i: Bits) = i(15 downto 0).asSInt

  val W = 48
  val rfA = Mem(SInt(W bits), 512)
  val rfB = Mem(SInt(W bits), 512)
  val rfX = Mem(SInt(W bits), 512)                   // indexed reads and EMIT's
  for (m <- Seq(rfA, rfB, rfX)) m.addAttribute("ramstyle", "M10K")

  // ---- state -----------------------------------------------------------------------------------------
  val running = RegInit(False)
  val cfgStep = RegInit(U(0, 2 bits))                // init: samsho and vlen into their registers
  io.busy := running || cfgStep =/= 0

  val stall = Bool()                                 // E holds: F, D and E keep their instructions
  val flush = Bool()                                 // E's branch is taken
  val target = UInt(11 bits)

  val pcSeq = Reg(UInt(11 bits)) init (0)            // the next sequential fetch
  val brPending = RegInit(False)                     // E's branch, taken last clock: redirect now
  val brTarget = Reg(UInt(11 bits))
  val fetch = brPending ? brTarget | pcSeq
  val instrD = rom.readSync(fetch, enable = !stall)
  val validD = RegInit(False)
  val pcD = Reg(UInt(11 bits))
  val validE = RegInit(False)
  val pcE = Reg(UInt(11 bits))
  val instrE = Reg(Bits(49 bits)) init (0)

  // the register reads: D's operands, or E's again while E holds (so its operands stay current)
  val rdAddrA, rdAddrB = UInt(9 bits)
  val rdA = rfA.readSync(rdAddrA)
  val rdB = rfB.readSync(rdAddrB)

  // M and W
  val mValid = RegInit(False)
  val mInstr = Reg(Bits(49 bits)) init (0)
  val mVal = Reg(SInt(W bits))                       // an ALU or multi-cycle result
  val mWrites = RegInit(False)
  val mIsSt = RegInit(False)
  val mAccOp = RegInit(False)                        // M changes the accumulator
  val wValid = RegInit(False)
  val wReg = Reg(UInt(9 bits))
  val wVal = Reg(SInt(W bits))

  // 72 bits: the widest value measured is 58 (sams64 3500); geo_engine.py's Sim stops on a wider one
  val AW = 72
  val acc = Reg(SInt(AW bits)) init (0)
  val prod = Reg(SInt(AW bits))
  val mulOp = RegInit(U(0, 2 bits))                  // 0 none, 1 MUL, 2 MAC, 3 MSB
  val accOp = RegInit(U(0, 2 bits))                  // 0 none, 1 set, 2 add, 3 shift
  val accVal = Reg(SInt(AW bits))
  val mSh = Reg(SInt(8 bits))                        // ASHL's or a store's shift

  // ---- E -----------------------------------------------------------------------------------------------
  val eLive = validE && !brPending                   // the instruction after a taken branch is dropped
  val o = fOp(instrE)
  val d = fD(instrE)
  val ra = fA(instrE)
  val rb = fB(instrE)
  val imm = fI(instrE)

  // Forwarding: M's result, else W's, else the register file; r0 reads 0. Which one is decided a
  // clock early, into registers (fwdSel below, from what E, M and W will hold), so E's path is a
  // mux and not also the three 9-bit compares in front of it: the first full fit failed by 7.4 ns
  // from wReg through the compare, the ALU and into mVal.
  val selMA, selMB, selWA, selWB, zeroA, zeroB = RegInit(False)
  def fwd(zero: Bool, selM: Bool, selW: Bool, v: SInt): SInt =
    zero ? S(0, W bits) | (selM ? mVal | (selW ? wVal | v))
  val a = fwd(zeroA, selMA, selWA, rdA)
  val b = fwd(zeroB, selMB, selWB, rdB)

  val usesD = o === op("STX")
  val stHazard = mValid && mIsSt && fD(mInstr) =/= 0 &&
    ((fD(mInstr) === ra) || (fD(mInstr) === rb) || (usesD && fD(mInstr) === d))
  val accBranchHazard = mValid && mAccOp && (o === op("BACCN") || o === op("BACCNN") || o === op("DIV"))

  // ALU
  val alu = SInt(W bits)
  alu := 0
  val aluWrites = Bool()
  aluWrites := False
  def topBit(v: SInt): UInt = OHToUInt(OHMasking.last(v.asBits))
  def shiftBy(v: SInt, sh: SInt): SInt =             // sh > 0 left, < 0 arithmetic right
    (sh >= 0) ? (v |<< sh.asUInt.resize(6 bits)) | (v >> (-sh).asUInt.resize(6 bits))
  switch(o) {
    is(op("ADD")) { alu := a + b; aluWrites := True }
    is(op("SUB")) { alu := a - b; aluWrites := True }
    is(op("MIN")) { alu := (a < b) ? a | b; aluWrites := True }
    is(op("MAX")) { alu := (a > b) ? a | b; aluWrites := True }
    is(op("OR")) { alu := a | b; aluWrites := True }
    is(op("AND")) { alu := a & b; aluWrites := True }
    is(op("ADDI")) { alu := a + imm.resize(W bits); aluWrites := True }
    is(op("ANDI")) { alu := a & imm.resize(W bits); aluWrites := True }
    is(op("SHLI")) { alu := a |<< imm.asUInt.resize(6 bits); aluWrites := True }
    is(op("SHRI")) { alu := a >> imm.asUInt.resize(6 bits); aluWrites := True }
    is(op("MOVI")) { alu := imm.resize(W bits); aluWrites := True }
    is(op("NEG")) { alu := -a; aluWrites := True }
    is(op("ABS")) { alu := (a < 0) ? -a | a; aluWrites := True }
    is(op("SEXT16")) { alu := a(15 downto 0).resize(W bits); aluWrites := True }
    is(op("WRAP")) { alu := io.wrap(a.asUInt.resize(5 bits)).resize(W bits).asSInt; aluWrites := True }
  }

  // ---- multi-cycle operations ------------------------------------------------------------------------
  val mcStep = RegInit(U(0, 2 bits))
  val mcVal = SInt(W bits)                           // the result, on the clock it completes
  mcVal := 0
  val mcDone = Bool()
  mcDone := False
  val xAddr = UInt(9 bits)
  xAddr := (a + b).asUInt.resize(9 bits)
  val rdXraw = rfX.readSync(xAddr)
  val xAddrPrev = RegNext(xAddr)
  val rdX = (wValid && wReg === xAddrPrev && xAddrPrev =/= 0) ? wVal | rdXraw
  val rsqV = rsqRom.readSync(a.asUInt.resize(8 bits))
  val rcpV = rcpRom.readSync(a.asUInt.resize(10 bits))
  io.dlAddr := a.asUInt.resize(8 bits)

  val vWord = Stream(Bits(16 bits))
  vWord.ready := False

  val divRem = Reg(UInt(AW bits))
  val divDen = Reg(UInt(48 bits))
  val divQ = Reg(UInt(48 bits))
  val divNeg = Reg(Bool())
  val divLeft = Reg(UInt(6 bits))

  // the triangle out, and the attributes AOUT sets, at their own widths
  val attr = Reg(Attr())
  val triOut = Reg(TriangleSetup.Input(c))
  val emitCount = Reg(UInt(5 bits))
  val triValid = RegInit(False)

  // SHLV, LOG2 and NORM (a priority encoder and a barrel shifter) take their operands a clock
  // before they compute, off E's forwarding path
  val slowAlu = o === op("SHLV") || o === op("LOG2") || o === op("NORM")
  val isMc = o === op("LDX") || o === op("STX") || o === op("TRSQ") || o === op("TRCP") ||
    o === op("DL") || o === op("VRD") || o === op("VRDS") || o === op("DIV") || o === op("EMIT") || slowAlu
  val mcWrites = o === op("LDX") || o === op("TRSQ") || o === op("TRCP") || o === op("DL") ||
    o === op("VRD") || o === op("VRDS") || o === op("DIV") || slowAlu
  val slowA = Reg(SInt(W bits))
  val slowB = Reg(SInt(8 bits))
  val stxWrite = Bool()
  stxWrite := False


  val mcGo = eLive && isMc && !stHazard && !accBranchHazard
  when(mcGo) {
    switch(o) {
      is(op("LDX")) {
        when(mcStep === 0) { mcStep := 1 }.otherwise { mcVal := rdX; mcDone := True }
      }
      is(op("STX")) {
        // step 0: read the value (d) through copy X; step 1: write it at a + b
        when(mcStep === 0) { xAddr := d; mcStep := 1 }.otherwise { stxWrite := True; mcDone := True }
      }
      is(op("SHLV"), op("LOG2"), op("NORM")) {
        when(mcStep === 0) {
          slowA := a
          slowB := (o === op("SHLV")) ? b.resize(8 bits) | imm.resize(8 bits)
          mcStep := 1
        }.otherwise {
          switch(o) {
            is(op("SHLV")) { mcVal := shiftBy(slowA, slowB) }
            is(op("LOG2")) { mcVal := (slowA > 0) ? topBit(slowA).resize(W bits).asSInt | S(-1, W bits) }
            default { mcVal := shiftBy(slowA, slowB - topBit(slowA).resize(8 bits).asSInt) }
          }
          mcDone := True
        }
      }
      is(op("TRSQ")) {
        when(mcStep === 0) { mcStep := 1 }.otherwise { mcVal := rsqV.resize(W bits).asSInt; mcDone := True }
      }
      is(op("TRCP")) {
        when(mcStep === 0) { mcStep := 1 }.otherwise { mcVal := rcpV.resize(W bits).asSInt; mcDone := True }
      }
      is(op("DL")) {
        when(mcStep === 0) { mcStep := 1 }.otherwise {
          mcVal := io.dlData.asUInt.resize(W bits).asSInt
          mcDone := True
        }
      }
      is(op("VRD"), op("VRDS")) {
        when(vWord.valid) {
          vWord.ready := True
          mcVal := (o === op("VRDS")) ? vWord.payload.asSInt.resize(W bits) | vWord.payload.asUInt.resize(W bits).asSInt
          mcDone := True
        }
      }
      is(op("DIV")) {
        // restoring, on magnitudes; the quotient under 2^imm
        when(mcStep === 0) {
          divRem := acc.abs
          divDen := b.abs
          divNeg := (acc < 0) =/= (b < 0)
          divQ := 0
          divLeft := imm.asUInt.resize(6 bits)
          mcStep := 1
        }.elsewhen(divLeft === 0) {
          mcVal := divNeg ? (-(divQ.asSInt)).resize(W bits) | divQ.asSInt.resize(W bits)
          mcDone := True
        }.otherwise {
          val k = divLeft - 1
          // rem >= den << k, as (rem >> k) >= den: nothing wider than the remainder
          val take = (divRem >> k) >= divDen.resize(AW bits)
          when(take) { divRem := divRem - (divDen.resize(AW bits) |<< k) }
          divQ := (divQ |<< 1) | take.asUInt.resize(48 bits)
          divLeft := k
        }
      }
      is(op("EMIT")) {
        // step 0: wait for the output to be free; 1: read the setup record, R[a .. a + 21], out
        // through copy X (address at count c, data at c + 1); then offer the triangle
        when(mcStep === 0) {
          when(!triValid) { emitCount := 0; mcStep := 1 }
        }.otherwise {
          xAddr := ra + emitCount.resize(9 bits)
          when(emitCount =/= 0) {
            val t = triOut
            val words = Seq(t.v(0)(0), t.v(0)(1), t.v(1)(0), t.v(1)(1), t.v(2)(0), t.v(2)(1)) ++
              t.p0.v ++ t.dx.v ++ t.dy.v
            switch(emitCount - 1) {
              is(6) { t.neg := rdX(0) }
              for ((f, n) <- words.zipWithIndex) is(if (n < 6) n else n + 1) {
                f := rdX.resize(f.getWidth bits)
              }
            }
          }
          emitCount := emitCount + 1
          when(emitCount === 22) {
            triOut.attr := attr.asBits
            triValid := True
            mcDone := True
          }
        }
      }
    }
  }
  when(mcDone) { mcStep := 0 }

  // ---- E's hold, branches, and the hand-over to M ----------------------------------------------------------
  stall := eLive && (stHazard || accBranchHazard || (isMc && !mcDone)) || cfgStep =/= 0
  val eGo = eLive && !stall

  val taken = Bool()
  taken := False
  target := imm.asUInt.resize(11 bits)
  val retStack = Reg(Vec(UInt(11 bits), 4))
  val retSp = Reg(UInt(2 bits)) init (0)
  when(eGo) {
    switch(o) {
      is(op("J")) { taken := True }
      is(op("JAL")) {
        taken := True
        retStack(retSp) := pcE + 1
        retSp := retSp + 1
      }
      is(op("RET")) {
        taken := True
        target := retStack(retSp - 1)
        retSp := retSp - 1
      }
      is(op("BZ")) { taken := a === 0 }
      is(op("BNZ")) { taken := a =/= 0 }
      is(op("BLTZ")) { taken := a < 0 }
      is(op("BGEZ")) { taken := a >= 0 }
      is(op("BGTZ")) { taken := a > 0 }
      is(op("BLT")) { taken := a < b }
      is(op("BGE")) { taken := a >= b }
      is(op("BEQ")) { taken := a === b }
      is(op("BNE")) { taken := a =/= b }
      is(op("BACCN")) { taken := acc < 0 }
      is(op("BACCNN")) { taken := acc >= 0 }
      is(op("AOUT")) {
        switch(d.resize(4 bits)) {
          is(0) { attr.flat := a(0) }
          is(1) { attr.blend := a(0) }
          is(2) { attr.tex4bpp := a(0) }
          is(3) { attr.texIndex := a.asUInt.resize(4 bits) }
          is(4) { attr.sub := a.asBits.resize(2 bits) }
          is(5) { attr.hoff := a.asUInt.resize(7 bits) }
          is(6) { attr.voff := a.asUInt.resize(7 bits) }
          is(7) { attr.pal := a.asBits.resize(16 bits) }
          is(8) { attr.scrollX := a.asUInt.resize(9 bits) }
          is(9) { attr.scrollY := a.asUInt.resize(9 bits) }
          is(10) { attr.wrapX := a.asUInt.resize(5 bits) }
          is(11) { attr.wrapY := a.asUInt.resize(5 bits) }
        }
      }
      is(op("HALT")) { running := False; taken := True; target := pcE }
    }
  }
  flush := taken
  brPending := eGo && taken
  when(eGo && taken) { brTarget := target }

  val isSt = o === op("ST") || o === op("STF") || o === op("STV") || o === op("STVW")
  mValid := eGo
  when(eGo) { mInstr := instrE }
  mWrites := eGo && (aluWrites || mcWrites || isSt)
  mIsSt := eGo && isSt
  mVal := mcWrites ? mcVal | alu
  mulOp := 0
  accOp := 0
  mAccOp := False
  when(eGo) {
    switch(o) {
      is(op("MUL")) { mulOp := 1; mAccOp := True }
      is(op("MAC")) { mulOp := 2; mAccOp := True }
      is(op("MSB")) { mulOp := 3; mAccOp := True }
      is(op("LDA")) { accOp := 1; mAccOp := True }
      is(op("ADA"), op("ADAV")) { accOp := 2; mAccOp := True }
      is(op("ASHL")) { accOp := 3; mAccOp := True }
    }
    prod := (a.resize(36 bits) * b.resize(36 bits)).resize(AW bits)
    accVal := a.resize(AW bits) |<< ((o === op("ADAV")) ? b.asUInt.resize(7 bits) | imm.asUInt.resize(7 bits))
    mSh := (o === op("STV") || o === op("STVW")) ? (b + imm.resize(W bits)).resize(8 bits) | imm.resize(8 bits)
  }

  // ---- M ------------------------------------------------------------------------------------------------
  switch(mulOp) {
    is(1) { acc := prod }
    is(2) { acc := acc + prod }
    is(3) { acc := acc - prod }
  }
  switch(accOp) {
    is(1) { acc := accVal }
    is(2) { acc := acc + accVal }
    is(3) { acc := (mSh >= 0) ? (acc |<< mSh.asUInt.resize(7 bits)) | (acc >> (-mSh).asUInt.resize(7 bits)) }
  }
  // a store reads the accumulator as the ops before it left it (they were in M a clock earlier)
  val mo = fOp(mInstr)
  val half = (mSh > 0) ? (S(1, AW bits) |<< (mSh - 1).asUInt.resize(7 bits)) | S(0, AW bits)
  val rounded = acc + ((mo === op("STF")) ? S(0, AW bits) | half)
  val stVal = (mSh >= 0) ? (rounded >> mSh.asUInt.resize(7 bits)) | (acc |<< (-mSh).asUInt.resize(7 bits))
  val mOut = mIsSt ? stVal.resize(W bits) | mVal
  val mDst = fD(mInstr)

  // the one write port: the configuration at init, STX, or M
  val wrEn = Bool()
  val wrAddr = UInt(9 bits)
  val wrData = SInt(W bits)
  wrEn := mValid && mWrites && mDst =/= 0
  wrAddr := mDst
  wrData := mOut
  when(stxWrite) {
    wrEn := True
    wrAddr := xAddr
    wrData := (d === 0) ? S(0, W bits) | rdX
  }
  when(cfgStep === 1) {
    wrEn := True
    wrAddr := U(regOf("samsho"), 9 bits)
    wrData := io.samsho.asUInt.resize(W bits).asSInt
  }
  when(cfgStep === 2) {
    wrEn := True
    wrAddr := U(regOf("vlen"), 9 bits)
    wrData := io.vlen.resize(W bits).asSInt
  }
  for (m <- Seq(rfA, rfB, rfX)) m.write(wrAddr, wrData, wrEn)
  wValid := wrEn
  wReg := wrAddr
  wVal := wrData
  rdAddrA := stall ? ra | fA(instrD)
  rdAddrB := stall ? rb | fB(instrD)

  // fwdSel: next clock's E instruction is the one read above; next clock's M is E if it goes
  // (a writing op that is not a store: a store's value is only there at M, and stHazard waits
  // for it), and next clock's W is this clock's register-file write
  val mNext = eGo && (aluWrites || mcWrites) && !isSt
  for ((r, selM, selW, zero) <- Seq((rdAddrA, selMA, selWA, zeroA), (rdAddrB, selMB, selWB, zeroB))) {
    selM := mNext && d === r
    selW := wrEn && wrAddr === r
    zero := r === 0
  }

  // ---- the pc ------------------------------------------------------------------------------------------
  when(!stall) {
    validD := running
    pcD := fetch
    pcSeq := fetch + 1
    validE := validD && !brPending
    pcE := pcD
    instrE := instrD
  }
  when(io.start && !running && cfgStep === 0) {
    val e = io.entry.mux(0 -> U(entryOf("init"), 11 bits), 1 -> U(entryOf("clear"), 11 bits),
      default -> U(entryOf("upload"), 11 bits))
    pcSeq := e
    validD := False
    validE := False
    retSp := 0
    running := True
    when(io.entry === 0) { cfgStep := 1 }
  }
  when(cfgStep === 1) { cfgStep := 2 }
  when(cfgStep === 2) { cfgStep := 0 }

  // ---- the vertex ROM stream: VSEEK restarts it at a word; reads run ahead, replies in order --------
  val seeked = RegInit(False)
  val vReq = Reg(UInt(26 bits))                      // the next beat's first word to request
  val vDrop = RegInit(U(0, 6 bits))                  // replies still owed to an older seek
  val vOut = RegInit(U(0, 6 bits))                   // requests in flight
  val vFifo = StreamFifo(Bits(64 bits), 16)
  val vSkip = RegInit(U(0, 2 bits))                  // words of the head beat already used
  val seek = eGo && o === op("VSEEK")
  val room = vFifo.io.availability > vOut.resize(vFifo.io.availability.getWidth bits)
  io.vRd.valid := seeked && room && !seek
  io.vRd.payload := io.vBase + (vReq(25 downto 2) @@ U(0, 3 bits)).resize(28 bits)
  when(io.vRd.fire) { vReq := vReq + 4 }
  vFifo.io.push.valid := io.vData.valid && vDrop === 0 && !seek
  vFifo.io.push.payload := io.vData.payload
  vOut := vOut + U(io.vRd.fire).resize(6 bits) - U(io.vData.valid).resize(6 bits)
  when(io.vData.valid && vDrop =/= 0) { vDrop := vDrop - 1 }
  vWord.valid := vFifo.io.pop.valid
  vWord.payload := vFifo.io.pop.payload.subdivideIn(16 bits)(vSkip)
  vFifo.io.pop.ready := vWord.fire && vSkip === 3
  when(vWord.fire) { vSkip := vSkip + 1 }
  vFifo.io.flush := seek
  when(seek) {
    val w = a.asUInt.resize(26 bits)
    seeked := True
    vReq := w(25 downto 2) @@ U(0, 2 bits)
    vSkip := w(1 downto 0)
    vDrop := vOut - U(io.vData.valid).resize(6 bits)
  }

  // ---- the triangle out: three records of x, y, z, 1/w, light/w, u/w, v/w and the attributes ---------
  io.tri.valid := triValid
  when(io.tri.fire) { triValid := False }
  io.tri.payload := triOut
}

/** Writes rtl/3d/hng64_geo.v (scripts/gen_3d_rtl.sh). */
object GenGeo extends App {
  SpinalConfig(
    mode = Verilog,
    targetDirectory = args.headOption.getOrElse("."),
    defaultConfigForClockDomains = ClockDomainConfig(resetKind = SYNC),
    oneFilePerComponent = false,
    globalPrefix = "hng64_geo_",
    inlineRom = true
  ).generate(GeoEngine(args.lift(1).getOrElse("rtl/3d/spinal/geo")).setDefinitionName("hng64_geo"))
}
