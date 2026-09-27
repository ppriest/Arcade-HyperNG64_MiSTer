// SPDX-License-Identifier: GPL-3.0-or-later
//
// A block RAM with byte enables: port A writes (per byte) and reads on its clock, port B reads on
// its own. Read data the clock after the address on either port.
//
// SYNTHESIS INSTANTIATES altsyncram. Written behaviourally, with a byte-enabled write and a read
// on a second clock, Quartus 17 built these from registers without saying so: the first full fit
// needed 663,477 ALMs against 41,910, 526,000 registers of them the sprite list and palette in
// hng64_vbus. A BIDIR_DUAL_PORT altsyncram is one M10K array, as the MS32 core's dpram_dc is
// (LESSONS_LEARNED, Quartus synthesis gotchas). The behavioural model below is what every simulator
// runs; Quartus synthesis defines ALTERA_RESERVED_QIS. A read on port A in the clock of a write to
// the same address returns the new data in the chip and the old in the model: no user reads there.

module hng64_bram #(
    parameter int AW = 12,
    parameter int DW = 32,              // a multiple of 8
    parameter int WORDS = 1 << AW       // fewer than 2^AW takes fewer blocks
) (
    input  logic          a_clk,
    input  logic [AW-1:0] a_addr,
    input  logic [DW/8-1:0] a_be,       // bytes written this clock; 0 for none
    input  logic [DW-1:0] a_wdata,
    output logic [DW-1:0] a_rdata,

    input  logic          b_clk,
    input  logic [AW-1:0] b_addr,
    output logic [DW-1:0] b_rdata
);

`ifndef ALTERA_RESERVED_QIS
    logic [DW-1:0] mem [0:WORDS - 1];

    initial for (int i = 0; i < WORDS; i++) mem[i] = '0;

    always_ff @(posedge a_clk) begin
        a_rdata <= mem[a_addr];
        for (int k = 0; k < DW / 8; k++)
            if (a_be[k]) mem[a_addr][8*k +: 8] <= a_wdata[8*k +: 8];
    end

    always_ff @(posedge b_clk) b_rdata <= mem[b_addr];
`else
    altsyncram #(
        .operation_mode("BIDIR_DUAL_PORT"),
        .ram_block_type("M10K"),
        .intended_device_family("Cyclone V"),
        .lpm_type("altsyncram"),
        .numwords_a(WORDS), .widthad_a(AW), .width_a(DW),
        .numwords_b(WORDS), .widthad_b(AW), .width_b(DW),
        .width_byteena_a(DW / 8), .byte_size(8),
        .width_byteena_b(1),
        .outdata_reg_a("UNREGISTERED"), .outdata_reg_b("UNREGISTERED"),
        .address_reg_b("CLOCK1"), .indata_reg_b("CLOCK1"), .wrcontrol_wraddress_reg_b("CLOCK1"),
        .clock_enable_input_a("BYPASS"), .clock_enable_output_a("BYPASS"),
        .clock_enable_input_b("BYPASS"), .clock_enable_output_b("BYPASS"),
        .outdata_aclr_a("NONE"), .outdata_aclr_b("NONE"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
        .power_up_uninitialized("FALSE")
    ) u_ram (
        .clock0(a_clk), .address_a(a_addr), .data_a(a_wdata), .wren_a(|a_be), .byteena_a(a_be),
        .q_a(a_rdata),
        .clock1(b_clk), .address_b(b_addr), .data_b({DW{1'b0}}), .wren_b(1'b0), .q_b(b_rdata),
        .aclr0(1'b0), .aclr1(1'b0), .addressstall_a(1'b0), .addressstall_b(1'b0), .byteena_b(1'b1),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .rden_a(1'b1), .rden_b(1'b1), .eccstatus()
    );
`endif

endmodule
