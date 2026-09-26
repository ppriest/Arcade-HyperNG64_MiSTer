// SPDX-License-Identifier: GPL-3.0-or-later
//
// The IO board's MCU, with what MAME puts around it: the TMP87PH40AN's memory map and
// peripherals (src/devices/cpu/tlcs870/tlcs870.cpp) and the HNG64 board wiring on its ports
// (src/mame/snk/hng64.cpp:2285-2530).
//
// MEMORY MAP (tmp87ph40an_mem, tlcs870.cpp:24)
//   0x0000-0x003f  SFRs. 0x3a-0x3f (EIR, IL, PSW) live in the core.
//   0x0040-0x023f  internal RAM, which also holds the register banks
//   0x0f80-0x0fff  DBR; 0x0ff0-0x0fff are the serial buffers
//   0xc000-0xffff  ROM, the top 16 KB of the 32 KB dump
// Anything else reads 0, MAME's default for an unmapped read, and ignores writes.
//
// THE BOARD ON THE PORTS
//   P0  data to and from the dual-port RAM shared with the MIPS, at an address P7 clocks
//   P1  out: bits 7:5 select which input byte P3 reads and which lamp byte P3 writes; bit 3
//       enables the lamp write
//   P3  in: the selected input byte (IN0-IN7, active low). out: lamps and coin counters
//   P7  out: bits 3:2 the dual-port RAM address's top two bits; a falling bit 0 clears the
//       nine-bit counter under them, a falling bit 1 advances it, a falling bit 7 interrupts
//       the MIPS
// Every other port reads 0xff from its pins, as MAME's unbound callbacks do.
//
// PERIPHERALS, AS MAME HAS THEM - which is less than the chip has (docs/MAME_KLUDGES.md):
//   timer 2    fires INTTC2 every 1,500 MCU cycles while TC2S is set, whatever TREG2 and the
//              clock select say (`tc2_reload`, "TODO: use real value")
//   serial 1   a transmit shifts one bit every 1,000 cycles, the first at once, and raises
//              INTSIO1 after the last byte; the bits themselves go nowhere on this board
//   ADC        a start samples the selected input at once; ADCCR always reads "finished"
//   INT0       the MIPS's command interrupt, taken on a rising edge
//   timers 1, 3 and 4, the time-base timer, the watchdog and serial 2 hold their registers
//   and do nothing else.
//
// The MCU's own interrupt timing is therefore MAME's, not the chip's: see HACKS.md.

module hng64_iomcu (
    input  logic        clk,
    input  logic        reset,
    input  logic        ce,             // one pulse per MCU clock, 8 MHz

    // the ROM, loaded once: file offsets 0x4000-0x7fff of tmp87ph40an.bin
    input  logic        rom_we,
    input  logic [13:0] rom_addr,
    input  logic  [7:0] rom_data,

    input  logic  [7:0] inputs [0:7],   // IN0-IN7, active low
    input  logic  [7:0] analog [0:7],   // AN0-AN7
    input  logic        int0,           // from the MIPS: its command interrupt

    output logic        lamp_we,        // one clock
    output logic  [2:0] lamp_addr,
    output logic  [7:0] lamp_data,
    output logic        mips_irq,       // one clock: the MCU asks the MIPS for attention

    // the MIPS side of the dual-port RAM (IDT71321, 2K x 8)
    input  logic [10:0] dp_addr,
    input  logic        dp_we,
    input  logic  [7:0] dp_wdata,
    output logic  [7:0] dp_rdata,

    // the core's per-instruction export, for sim/iomcu_tb
    output logic        dbg_fetch,
    output logic [15:0] dbg_pc,
    output logic  [7:0] dbg_op,
    output logic  [7:0] dbg_op1,
    output logic        dbg_unimpl,
    output logic        dbg_overrun,
    output logic [15:0] dbg_sp,
    output logic  [3:0] dbg_rbs,
    output logic  [7:0] dbg_f,
    // the core's writes, so a bench can keep its own copy of internal RAM - where the registers
    // live - without a second read port that would stop it being block RAM
    output logic        dbg_we,
    output logic [15:0] dbg_addr,
    output logic  [7:0] dbg_wdata
);

    // ---- the core ---------------------------------------------------------------------------------
    logic [15:0] a;
    logic        rd, we, latch;
    logic  [7:0] wd, rdata;
    logic [15:0] irq;

    hng64_tlcs870 u_cpu (
        .clk(clk), .reset(reset), .ce(ce),
        .mem_addr(a), .mem_rd(rd), .mem_we(we), .mem_latch(latch), .mem_wdata(wd),
        .mem_rdata(rdata), .irq(irq),
        .dbg_fetch(dbg_fetch), .dbg_pc(dbg_pc), .dbg_op(dbg_op), .dbg_op1(dbg_op1),
        .dbg_unimpl(dbg_unimpl), .dbg_overrun(dbg_overrun),
        .dbg_sp(dbg_sp), .dbg_rbs(dbg_rbs), .dbg_f(dbg_f));

    // ---- decode -----------------------------------------------------------------------------------
    wire is_sfr  = (a[15:6] == 10'd0);
    wire is_iram = (a >= 16'h0040) && (a <= 16'h023f);
    wire is_dbr  = (a[15:7] == 9'h01f);                 // 0x0f80-0x0fff
    wire is_rom  = (a[15:14] == 2'b11);

    // ---- ROM, internal RAM, DBR: one read port each, data the clock after the address -------------
    logic [7:0] rom  [0:16383];
    logic [7:0] iram [0:511];
    logic [7:0] dbr  [0:127];
    logic [7:0] rom_q, iram_q, dbr_q;

    initial begin
        for (int i = 0; i < 512; i++) iram[i] = 8'd0;
        for (int i = 0; i < 128; i++) dbr[i] = 8'd0;
    end

    wire [8:0] iram_i = 9'(a - 16'h0040);

    always_ff @(posedge clk) begin
        if (rom_we) rom[rom_addr] <= rom_data;
        rom_q <= rom[a[13:0]];
    end

    always_ff @(posedge clk) begin
        if (we && is_iram) iram[iram_i] <= wd;
        iram_q <= iram[iram_i];
    end

    always_ff @(posedge clk) begin
        if (we && is_dbr) dbr[a[6:0]] <= wd;
        dbr_q <= dbr[a[6:0]];
    end

    assign dbg_we    = we;
    assign dbg_addr  = a;
    assign dbg_wdata = wd;

    // ---- the dual-port RAM ---------------------------------------------------------------------------
    logic [8:0] dp_ctr;                 // m_ex_ramaddr
    logic [1:0] dp_upper;               // m_ex_ramaddr_upper
    logic [7:0] dp_left_q;

    hng64_tdpram #(.AW(11), .DW(8)) u_dpram (
        .clk(clk),
        .a_addr({dp_upper, dp_ctr}), .a_we(we && a == 16'h0000), .a_wdata(wd),
        .a_rdata(dp_left_q),
        .b_addr(dp_addr), .b_we(dp_we), .b_wdata(dp_wdata), .b_rdata(dp_rdata));

    // ---- SFRs ---------------------------------------------------------------------------------------
    logic [7:0] port [0:7];             // the output latches
    logic [7:0] port7_prev;             // hng64_state's own m_port7, for the edges
    logic [7:0] adccr, adcdr, tbtcr, syscr1, syscr2, tc2cr, sio1cr1, sio1cr2;
    logic [15:0] treg1b;
    logic [7:0] treg3a, treg3b;

    // what a read of a port's pins returns on this board
    function automatic logic [7:0] pins(input logic [2:0] n);
        case (n)
            3'd3:    pins = inputs[port[1][7:5]];
            default: pins = 8'hff;                          // P0 is the dual-port RAM, below
        endcase
    endfunction

    // A read's source, registered with the data so the mux sees both on the same clock.
    typedef enum logic [2:0] { S_ZERO, S_SFR, S_DP, S_IRAM, S_DBR, S_ROM } src_t;
    src_t src;
    logic [7:0] sfr_q;

    always_ff @(posedge clk) begin
        if (rd) begin
            src <= S_ZERO;
            if (is_sfr) begin
                src <= (a[5:0] == 6'h00 && !latch) ? S_DP : S_SFR;
                case (a[5:0])
                    6'h00, 6'h01, 6'h02, 6'h03, 6'h04, 6'h05, 6'h06, 6'h07:
                        sfr_q <= latch ? port[a[2:0]] : pins(a[2:0]);
                    6'h0e: sfr_q <= adccr | 8'h80;          // always "finished"
                    6'h0f: sfr_q <= adcdr;
                    6'h12: sfr_q <= treg1b[7:0];
                    6'h13: sfr_q <= treg1b[15:8];
                    6'h18: sfr_q <= treg3a;
                    6'h19: sfr_q <= treg3b;
                    6'h36: sfr_q <= tbtcr;
                    6'h38: sfr_q <= syscr1;
                    6'h39: sfr_q <= syscr2 | 8'h0f;         // low bits always read as 1
                    default: sfr_q <= 8'd0;                 // write-only, reserved, and the
                                                            // status registers MAME reads as 0
                endcase
            end
            else if (is_iram) src <= S_IRAM;
            else if (is_dbr)  src <= S_DBR;
            else if (is_rom)  src <= S_ROM;
        end
    end

    always_comb begin
        case (src)
            S_SFR:   rdata = sfr_q;
            S_DP:    rdata = dp_left_q;
            S_IRAM:  rdata = iram_q;
            S_DBR:   rdata = dbr_q;
            S_ROM:   rdata = rom_q;
            default: rdata = 8'd0;
        endcase
    end

    // ---- timer 2 and serial 1 ------------------------------------------------------------------------
    logic [10:0] tc2_cnt;
    logic        tc2_run, tc2_fire;
    logic  [9:0] sio_cnt;
    logic  [2:0] sio_shift;             // m_transfer_shiftpos
    logic  [3:0] sio_pos;               // m_transfer_pos
    logic        sio_run, sio_fire;

    wire  [2:0] sio_mode = sio1cr1[5:3];
    wire        sio_tx   = (sio_mode == 3'd0) || (sio_mode == 3'd2) || (sio_mode == 3'd4);

    // sio0_transmit_cb (tlcs870.cpp:577): one bit; after the eighth, the next byte, and after the
    // last byte the interrupt. Used at the start, which shifts the first bit at once, and on
    // each 1,000-cycle tick after it.
    typedef struct packed { logic [2:0] shift; logic [3:0] pos; logic done; } sio_step_t;
    function automatic sio_step_t sio_bit(input logic [2:0] shift, input logic [3:0] pos,
                                          input logic [2:0] numbytes);
        sio_bit.done = 1'b0;
        sio_bit.shift = shift + 3'd1;
        sio_bit.pos = pos;
        if (shift == 3'd7) begin
            sio_bit.shift = 3'd0;
            sio_bit.pos = pos + 4'd1;
            if (pos + 4'd1 > {1'b0, numbytes}) sio_bit.done = 1'b1;
        end
    endfunction

    sio_step_t sio_nx;

    always_ff @(posedge clk) begin
        lamp_we  <= 1'b0;
        mips_irq <= 1'b0;
        tc2_fire <= 1'b0;
        sio_fire <= 1'b0;

        // timer 2: tc2_cb raises INTTC2 and reloads
        if (ce && tc2_run) begin
            if (tc2_cnt == 11'd1) begin
                tc2_fire <= 1'b1;
                tc2_cnt  <= 11'd1500;
            end else begin
                tc2_cnt <= tc2_cnt - 11'd1;
            end
        end

        // serial 1, between bits
        if (ce && sio_run) begin
            if (sio_cnt == 10'd1) begin
                sio_nx = sio_bit(sio_shift, sio_pos, sio1cr2[2:0]);
                sio_shift <= sio_nx.shift;
                sio_pos   <= sio_nx.pos;
                sio_cnt   <= 10'd1000;
                if (sio_nx.done) begin
                    sio_run  <= 1'b0;
                    sio_fire <= 1'b1;
                    sio1cr1[7] <= 1'b0;
                end
            end else begin
                sio_cnt <= sio_cnt - 10'd1;
            end
        end

        if (we && is_sfr) begin
            case (a[5:0])
                6'h00, 6'h01, 6'h02, 6'h03, 6'h04, 6'h05, 6'h06, 6'h07: port[a[2:0]] <= wd;
                6'h0e: begin
                    adccr <= wd;
                    if (wd[6]) adcdr <= analog[wd[2:0]];
                end
                6'h12: treg1b[7:0]  <= wd;
                6'h13: treg1b[15:8] <= wd;
                6'h15: begin                                // tc2cr_w
                    if (wd[5]) begin
                        if (!tc2cr[5]) begin tc2_run <= 1'b1; tc2_cnt <= 11'd1500; end
                    end else begin
                        tc2_run <= 1'b0;
                    end
                    tc2cr <= wd;
                end
                6'h18: treg3a <= wd;
                6'h20: begin                                // sio1cr1_w
                    sio1cr1 <= wd;
                    if (wd[7:6] == 2'b10) begin
                        // the first bit goes at once; only the transmit modes run on
                        if ((wd[5:3] == 3'd0) || (wd[5:3] == 3'd2) || (wd[5:3] == 3'd4)) begin
                            sio_nx = sio_bit(3'd0, 4'd0, sio1cr2[2:0]);
                            sio_shift <= sio_nx.shift;
                            sio_pos   <= sio_nx.pos;
                            sio_cnt   <= 10'd1000;
                            sio_run   <= 1'b1;
                        end else begin
                            sio_run <= 1'b0;
                        end
                    end
                end
                6'h21: sio1cr2 <= wd;
                6'h36: tbtcr  <= wd;
                6'h38: syscr1 <= wd;
                6'h39: syscr2 <= wd;
                default: ;
            endcase

            // the board's side of each port write
            case (a[5:0])
                6'h03: if (port[1][3]) begin                // ioport3_w: lamps when P1 bit 3
                    lamp_we   <= 1'b1;
                    lamp_addr <= port[1][7:5];
                    lamp_data <= wd;
                end
                6'h07: begin                                // ioport7_w
                    dp_upper <= wd[3:2];
                    if (!wd[7] && port7_prev[7]) mips_irq <= 1'b1;
                    // a falling bit 0 clears the counter, then a falling bit 1 advances it
                    if (!wd[0] && port7_prev[0])
                        dp_ctr <= (!wd[1] && port7_prev[1]) ? 9'd1 : 9'd0;
                    else if (!wd[1] && port7_prev[1])
                        dp_ctr <= dp_ctr + 9'd1;
                    port7_prev <= wd;
                end
                default: ;
            endcase
        end

        if (reset) begin
            // device_reset (tlcs870.cpp:1027)
            port[0] <= 8'h00; port[1] <= 8'h00; port[2] <= 8'hff; port[3] <= 8'hff;
            port[4] <= 8'hff; port[5] <= 8'hff; port[6] <= 8'h00; port[7] <= 8'h00;
            port7_prev <= 8'h00;
            adccr <= 8'h00; adcdr <= 8'h00; tbtcr <= 8'h00;
            syscr1 <= 8'h00; syscr2 <= 8'h80;
            treg1b <= 16'h4321; treg3a <= 8'h10; treg3b <= 8'h32;
            tc2cr <= 8'h00; tc2_run <= 1'b0; tc2_cnt <= 11'd1500;
            sio1cr1 <= 8'h00; sio1cr2 <= 8'h00; sio_run <= 1'b0;
            sio_shift <= 3'd0; sio_pos <= 4'd0; sio_cnt <= 10'd1000;
            dp_ctr <= 9'd0; dp_upper <= 2'd0;
        end
    end

    // IL bits are 15 minus MAME's enum: INT0 is bit 3, INTSIO1 bit 9, INTTC2 bit 14. The core
    // latches a rising edge, which is what set_irq_line does for INT0 and what a one-clock
    // pulse gives for the other two.
    always_comb begin
        irq = 16'd0;
        irq[3]  = int0;
        irq[9]  = sio_fire;
        irq[14] = tc2_fire;
    end

endmodule
