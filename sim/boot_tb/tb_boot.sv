// SPDX-License-Identifier: GPL-3.0-or-later
//
// Phase 0 criterion 1: the VR4300 (rtl/cpu/hng64_cpu.vhd) boots the hng64 BIOS through the
// bus bridge (rtl/hng64_bus.sv). Inputs from scripts/prep_boot_tb.py; run from the repo root:
//
//     python scripts/prep_boot_tb.py
//     scripts/run_sim.sh boot_tb +N=20000
//     python scripts/compare_insn_trace.py hng64
//
// Writes debug/hng64-insn/rtl.tr: one line per retired instruction (export_new), r1..r31 then
// "PC: opcode", the shape of MAME's trace (scripts/mame_insn_trace.py --regs all).
// I/O reads are answered from MAME's reads in order; an address mismatch stops the run.

module tb_boot;

    // clk2x 125 MHz, clk1x 62.5 MHz from it, clk93 93.75 MHz: the N64 core's clocks.
    logic clk2x = 0, clk1x = 0, clk93 = 0;
    always #4 clk2x = ~clk2x;
    always @(posedge clk2x) clk1x <= ~clk1x;
    always #5.333 clk93 = ~clk93;

    logic reset = 1, ss_reset = 1;
    int   N = 20000;

    // CPU <-> bridge
    logic        mem_request, mem_rnw, mem_req64, mem_done, granted, dout_ready, cpu_err, bus_err;
    logic [31:0] mem_address;
    logic  [2:0] mem_size;
    logic  [7:0] mem_writeMask;
    logic [63:0] mem_dataWrite, mem_dataRead, dout;
    logic        ex_new;
    logic [63:0] ex_pc;
    logic [31:0] ex_op;
    logic [2047:0] ex_regs;

    // bridge <-> models
    logic        st_req, st_we, st_rvalid, st_wdone;
    logic [31:0] st_addr;
    logic  [2:0] st_beats;
    logic [63:0] st_wdata, st_rdata;
    logic  [7:0] st_be;
    logic        io_req, io_we, io_ack;
    logic [31:0] io_addr, io_wdata, io_rdata;
    logic  [3:0] io_be;

    hng64_cpu u_cpu (
        .clk1x(clk1x), .clk93(clk93), .clk2x(clk2x),
        .reset_1x(reset), .reset_93(reset), .ss_reset(ss_reset), .irq(1'b0),
        .mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
        .mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
        .mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
        .rdram_granted2x(granted), .ddr3_DOUT(dout), .ddr3_DOUT_READY(dout_ready),
        .error_any(cpu_err),
        .export_new(ex_new), .export_pc(ex_pc), .export_opcode(ex_op), .export_regs(ex_regs));

    hng64_bus u_bus (
        .clk1x(clk1x), .clk2x(clk2x), .reset(reset),
        .mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
        .mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
        .mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
        .rdram_granted2x(granted), .ddr3_DOUT(dout), .ddr3_DOUT_READY(dout_ready),
        .st_req(st_req), .st_we(st_we), .st_addr(st_addr), .st_beats(st_beats),
        .st_wdata(st_wdata), .st_be(st_be), .st_rvalid(st_rvalid), .st_rdata(st_rdata),
        .st_wdone(st_wdone),
        .io_req(io_req), .io_we(io_we), .io_addr(io_addr), .io_be(io_be), .io_wdata(io_wdata),
        .io_ack(io_ack), .io_rdata(io_rdata),
        .err_unmapped64(bus_err));

    // ------------------------------------------------ backing store: BIOS, 16 MB RAM, no game
    logic [63:0] bios [0:65535];
    logic [63:0] ram  [0:2097151];
    initial begin
        $readmemh("sim/boot_tb/bios.hex", bios);
        for (int i = 0; i < 2097152; i++) ram[i] = 64'd0;
    end

    function automatic logic [63:0] rd(input logic [31:0] a);
        if (a < 32'h0100_0000)                          return ram[a[23:3]];
        if (a >= 32'h1FC0_0000 && a < 32'h1FC8_0000)    return bios[a[18:3]];
        return {64{1'b1}};                              // program ROM: absent (ERASEFF)
    endfunction

    // Fixed latency, then one beat a clk2x cycle. LAT is a placeholder until the SDRAM/DDR3
    // design exists: it sets the CPI the bench reports, so quote it with any CPI figure.
    localparam int LAT = 6;
    logic [31:0] s_addr;
    int          s_left, s_wait;
    logic        s_busy, s_we;
    always_ff @(posedge clk2x) begin
        st_rvalid <= 0;
        st_wdone  <= 0;
        if (st_req) begin
            s_busy <= 1; s_we <= st_we; s_addr <= st_addr; s_left <= st_beats; s_wait <= LAT;
            if (st_we && st_addr < 32'h0100_0000)
                for (int b = 0; b < 8; b++)
                    if (st_be[b]) ram[st_addr[23:3]][b*8 +: 8] <= st_wdata[b*8 +: 8];
        end else if (s_busy) begin
            if (s_wait > 0) s_wait <= s_wait - 1;
            else if (s_we) begin
                st_wdone <= 1; s_busy <= 0;
            end else begin
                st_rvalid <= 1; st_rdata <= rd(s_addr);
                s_addr <= s_addr + 8; s_left <= s_left - 1;
                if (s_left == 1) s_busy <= 0;
            end
        end
    end

    // ------------------------------------------------ I/O: replay MAME's reads, log writes
    logic [63:0] replay [0:399999];
    int          rp = 0, io_fd, tr_fd, retired = 0;
    initial begin
        for (int i = 0; i < 400000; i++) replay[i] = 64'hx;
        $readmemh("sim/boot_tb/io_replay.hex", replay);
    end
    always_ff @(posedge clk1x) begin
        io_ack <= 0;
        if (io_req) begin
            io_ack <= 1;
            if (io_we) begin
                $fwrite(io_fd, "w %08x %1x %08x\n", io_addr, io_be, io_wdata);
            end else begin
                if (replay[rp][63:32] !== io_addr) begin
                    $display("IO READ MISMATCH #%0d: RTL %08x, MAME %08x (after %0d instructions)",
                             rp, io_addr, replay[rp][63:32], retired);
                    $finish;
                end
                io_rdata <= replay[rp][31:0];
                $fwrite(io_fd, "r %08x %08x\n", io_addr, replay[rp][31:0]);
                rp <= rp + 1;
            end
        end
    end

    // ------------------------------------------------ instruction trace
    // Phase 0 criterion 3: cycles per instruction, and how much of it is memory stall.
    int cyc93 = 0, cyc_stall = 0;
    logic req_seen;
    always @(posedge clk93) if (!reset) begin
        cyc93 <= cyc93 + 1;
        if (req_seen) cyc_stall <= cyc_stall + 1;
    end
    always @(posedge clk1x) if (!reset) begin
        if (mem_request) req_seen <= 1;
        else if (mem_done) req_seen <= 0;
    end

    always @(posedge clk93) if (!reset && ex_new) begin
        for (int r = 1; r < 32; r++) $fwrite(tr_fd, "%016X ", ex_regs[r*64 +: 64]);
        $fwrite(tr_fd, "%08X: %08x\n", ex_pc[31:0], ex_op);
        retired = retired + 1;
        if (retired >= N) begin
            $display("DONE %0d instructions, %0d I/O reads replayed", retired, rp);
            $display("CPI x1000 = %0d over %0d clk93 cycles; %0d%% of them waiting on memory",
                     (cyc93 * 1000) / retired, cyc93, (cyc_stall * 100) / cyc93);
            $finish;
        end
    end

    always @(posedge clk1x) if (!reset && (cpu_err || bus_err)) begin
        $display("ERROR cpu_err=%0b bus_err=%0b after %0d instructions", cpu_err, bus_err, retired);
        $finish;
    end

    initial begin
        void'($value$plusargs("N=%d", N));
        io_fd = $fopen("debug/hng64-insn/rtl_io.log", "w");
        tr_fd = $fopen("debug/hng64-insn/rtl.tr", "w");
        #1000 ss_reset = 0;
        #1000 reset = 0;
        #(N * 200) $display("TIMEOUT after %0d instructions", retired);
        $finish;
    end

    final begin
        $fclose(tr_fd);
        $fclose(io_fd);
    end

endmodule
