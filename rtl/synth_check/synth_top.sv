// SPDX-License-Identifier: GPL-3.0-or-later
//
// Phase 0 criterion 4: what the VR4300 and the bus bridge cost on their own, and at what Fmax.
// A Quartus project of its own (rtl/synth_check/), not part of the core build:
//
//     quartus_sh --flow compile rtl/synth_check/synth_check
//
// Every interface is driven from registers seeded by one input pin and reduced to one output
// pin, so nothing optimises away and no path is pin-bound.

module synth_top (
    input  logic clk1x,
    input  logic clk2x,
    input  logic clk93,
    input  logic reset,
    input  logic din,
    output logic dout
);

    logic        mem_request, mem_rnw, mem_req64, mem_done, granted, dout_ready, cpu_err, bus_err;
    logic [31:0] mem_address;
    logic  [2:0] mem_size;
    logic  [7:0] mem_writeMask;
    logic [63:0] mem_dataWrite, mem_dataRead, beat;
    logic        st_req, st_we, st_rvalid, st_wdone;
    logic [31:0] st_addr;
    logic  [2:0] st_beats;
    logic [63:0] st_wdata, st_rdata;
    logic  [7:0] st_be;
    logic        io_req, io_we, io_ack;
    logic [31:0] io_addr, io_wdata, io_rdata;
    logic  [3:0] io_be;

    // Stimulus and responses: an LFSR, so the interfaces toggle and keep their logic.
    logic [63:0] lfsr = 64'd1;
    always_ff @(posedge clk2x) begin
        lfsr      <= {lfsr[62:0], lfsr[63] ^ lfsr[62] ^ lfsr[60] ^ lfsr[59] ^ din};
        st_rdata  <= lfsr;
        st_rvalid <= st_req | (lfsr[0] & ~st_we);
        st_wdone  <= lfsr[1];
    end
    always_ff @(posedge clk1x) begin
        io_rdata <= lfsr[31:0];
        io_ack   <= io_req | lfsr[2];
    end

    hng64_cpu u_cpu (
        .clk1x(clk1x), .clk93(clk93), .clk2x(clk2x),
        .reset_1x(reset), .reset_93(reset), .ss_reset(reset), .irq(din),
        .mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
        .mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
        .mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
        .rdram_granted2x(granted), .ddr3_DOUT(beat), .ddr3_DOUT_READY(dout_ready),
        .error_any(cpu_err));   // export ports exist only in simulation

    hng64_bus u_bus (
        .clk1x(clk1x), .clk2x(clk2x), .reset(reset),
        .mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
        .mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
        .mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
        .rdram_granted2x(granted), .ddr3_DOUT(beat), .ddr3_DOUT_READY(dout_ready),
        .st_req(st_req), .st_we(st_we), .st_addr(st_addr), .st_beats(st_beats),
        .st_wdata(st_wdata), .st_be(st_be), .st_rvalid(st_rvalid), .st_rdata(st_rdata),
        .st_wdone(st_wdone),
        .io_req(io_req), .io_we(io_we), .io_addr(io_addr), .io_be(io_be), .io_wdata(io_wdata),
        .io_ack(io_ack), .io_rdata(io_rdata),
        .err_unmapped64(bus_err));

    // One output pin, so every result is used but no path ends at a pin unregistered.
    logic acc = 0;
    always_ff @(posedge clk93) begin
        acc <= ^{mem_address, mem_dataWrite, mem_writeMask, mem_request, mem_rnw, mem_size,
                 mem_req64, cpu_err, bus_err,
                 st_addr, st_wdata, st_be, st_req, st_we, st_beats,
                 io_addr, io_wdata, io_be, io_req, io_we, acc};
    end
    assign dout = acc;

endmodule
