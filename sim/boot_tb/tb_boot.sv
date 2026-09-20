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

    // ---------------------------------------- backing store: the real memory stack
    // Main RAM and the BIOS in SDRAM through the vendored controller and a chip model;
    // `gameprg` would be in DDR3, but this bench runs the BIOS with no game, so that window
    // answers all-ones, which is what an absent ROM reads as (ERASEFF).
    wire  [15:0] SDRAM_DQ;
    wire  [12:0] SDRAM_A;
    wire   [1:0] SDRAM_BA;
    wire         SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS;
    wire         SDRAM_CLK, SDRAM_CKE;

    logic [25:0] s_addr;
    logic        s_rd, s_we_m, s_ready, s_valid;
    logic [63:0] s_wdata, s_data;
    logic  [7:0] s_be;
    logic [27:0] m_addr;
    logic        m_rd, m_ready, m_valid;
    logic [63:0] m_data;

    hng64_mainmem u_mem (
        .clk(clk2x), .reset(reset),
        .st_req(st_req), .st_we(st_we), .st_addr(st_addr), .st_beats(st_beats),
        .st_wdata(st_wdata), .st_be(st_be),
        .st_rvalid(st_rvalid), .st_rdata(st_rdata), .st_wdone(st_wdone),
        .s_addr(s_addr), .s_rd(s_rd), .s_we(s_we_m), .s_wdata(s_wdata), .s_be(s_be),
        .s_ready(s_ready), .s_data(s_data), .s_valid(s_valid),
        .d_addr(m_addr), .d_rd(m_rd), .d_ready(m_ready), .d_data(m_data), .d_valid(m_valid));

    hng64_sdram u_sdram (
        .clk(clk2x), .init(reset), .reset(reset),
        .SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
        .SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
        .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK),
        .SDRAM_CKE(SDRAM_CKE),
        .v_addr(17'd0), .v_rd(1'b0), .v_ready(), .v_data(), .v_valid(),
        .c_addr(s_addr), .c_rd(s_rd), .c_we(s_we_m), .c_wdata(s_wdata), .c_be(s_be),
        .c_ready(s_ready), .c_data(s_data), .c_valid(s_valid),
        .d_addr(25'd0), .d_din(16'd0), .d_we(1'b0), .d_ready());

    sdram_chip_model_wide #(.MB(32)) u_chip (
        .clk(clk2x), .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
        .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
        .SDRAM_nCAS(SDRAM_nCAS));

    // the absent program ROM, with the latency a DDR3 read would have
    localparam int DDR_LAT = 20;
    int m_wait = 0;
    assign m_ready = 1'b1;
    always_ff @(posedge clk2x) begin
        m_valid <= 1'b0;
        if (reset) m_wait <= 0;
        else begin
            if (m_rd) m_wait <= DDR_LAT;
            else if (m_wait > 1) m_wait <= m_wait - 1;
            else if (m_wait == 1) begin
                m_wait  <= 0;
                m_data  <= {64{1'b1}};
                m_valid <= 1'b1;
            end
        end
    end

    // The BIOS, and cleared main RAM, put straight into the chip model. The download port is
    // how the core will fill it; poking the array here keeps the bench to its point, which is
    // whether the CPU still boots identically with this memory behind it.
    logic [63:0] bios [0:65535];
    initial begin
        $readmemh("sim/boot_tb/bios.hex", bios);
        for (int i = 0; i < 8 * 1024 * 1024; i++) u_chip.mem[i] = 16'd0;
        for (int g = 0; g < 65536; g++)
            for (int w = 0; w < 4; w++)
                u_chip.mem[(26'h140_0000 >> 1) + g * 4 + w] = bios[g][w * 16 +: 16];
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
