// SPDX-License-Identifier: GPL-3.0-or-later
package hng64.raster

import spinal.core._
import spinal.lib._

/** The start-up copy of textures0 into 4 x 8-byte blocks (user decision; TexCache.scala has the
  * layout): the ROM image stays where the HPS loaded it and the blocked copy goes to `dst`, so a
  * reset without a reload blocks it again from the same source.
  *
  * Eight 1,024-byte rows at a time: their 1,024 beats read into two banks (even rows, odd rows,
  * 512 x 64 bits each), then written out as 256 blocks of four beats, beat j of block b being
  * rows 2j and 2j + 1 at columns 4b to 4b + 3. Reads go out as fast as they are accepted, replies
  * in order; about 2,100 clocks and one latency a group.
  */
case class TexBlock() extends Component {
  val io = new Bundle {
    val start = in Bool ()                           // one clock
    val src, dst = in UInt (28 bits)                 // byte offsets, 8 KB aligned
    val groups = in UInt (12 bits)                   // size / 8 KB; 0 is 4,096 (32 MB)
    val done = out Bool ()                           // one clock
    val busy = out Bool ()
    val rdAddr = master(Stream(UInt(28 bits)))
    val rdData = slave(Flow(Bits(64 bits)))
    val wr = master(Stream(RenderBuf.Beat()))
  }

  object S extends SpinalEnum { val Idle, Read, Write = newElement() }
  val st = RegInit(S.Idle)
  val src, dst = Reg(UInt(28 bits))
  val left = Reg(UInt(13 bits))
  val group = Reg(UInt(12 bits))
  val issued = Reg(UInt(11 bits))                    // reads sent this group
  val got = Reg(UInt(11 bits))                       // replies stored
  val wbeat = Reg(UInt(11 bits))                     // beats written: block (8 bits), beat (2)

  val even = Mem(Bits(64 bits), 512)
  val odd = Mem(Bits(64 bits), 512)

  io.done := False
  io.busy := st =/= S.Idle

  when(st === S.Idle && io.start) {
    src := io.src
    dst := io.dst
    left := (io.groups === 0) ? U(4096, 13 bits) | io.groups.resize(13 bits)
    group := 0
    issued := 0
    got := 0
    st := S.Read
  }

  // ---- read eight rows ------------------------------------------------------------------------------
  val gBase = (group @@ U(0, 13 bits)).resize(28 bits)
  io.rdAddr.valid := st === S.Read && !issued.msb
  io.rdAddr.payload := src + gBase + (issued(9 downto 0) @@ U(0, 3 bits)).resize(28 bits)
  when(io.rdAddr.fire) { issued := issued + 1 }

  // reply k: row k >> 7, word k & 127; rows alternate between the banks
  val k = got(9 downto 0)
  val bankAddr = k(9 downto 8) @@ k(6 downto 0)
  even.write(bankAddr, io.rdData.payload, io.rdData.valid && !k(7))
  odd.write(bankAddr, io.rdData.payload, io.rdData.valid && k(7))
  when(io.rdData.valid) { got := got + 1 }
  when(st === S.Read && got.msb) {
    wbeat := 0
    st := S.Write
  }

  // ---- write 256 blocks ----------------------------------------------------------------------------
  // beat (b, j) reads word j * 128 + b / 2 of both banks; the half is b & 1
  val beats = Stream(RenderBuf.Beat())
  val cmd = Stream(UInt(11 bits))
  cmd.valid := st === S.Write && !wbeat.msb
  cmd.payload := wbeat
  when(cmd.fire) { wbeat := wbeat + 1 }
  val rdAddr = cmd.payload(1 downto 0) @@ cmd.payload(9 downto 3)
  val e = even.readSync(rdAddr, cmd.fire)
  val o = odd.readSync(rdAddr, cmd.fire)
  val cmdQ = cmd.m2sPipe()
  val half = cmdQ.payload(2)
  beats.valid := cmdQ.valid
  beats.payload.addr := dst + gBase + (cmdQ.payload(9 downto 2) @@ cmdQ.payload(1 downto 0) @@ U(0, 3 bits)).resize(28 bits)
  beats.payload.data := half ? (o(63 downto 32) ## e(63 downto 32)) | (o(31 downto 0) ## e(31 downto 0))
  beats.payload.be := B"8'xFF"
  cmdQ.ready := beats.ready
  io.wr << beats

  when(st === S.Write && wbeat.msb && !cmdQ.valid) {
    group := group + 1
    issued := 0
    got := 0
    when(left === 1) {
      io.done := True
      st := S.Idle
    }.otherwise {
      left := left - 1
      st := S.Read
    }
  }
}
