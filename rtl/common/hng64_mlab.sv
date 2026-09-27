// SPDX-License-Identifier: GPL-3.0-or-later
//
// A small RAM read combinationally: one registered write port, one read port whose data follows
// its address in the same clock. Quartus 17 will not infer this ("uninferred due to asynchronous
// read logic") and builds it from registers and a wide multiplexer; Cyclone V's MLABs do it, so in
// synthesis this is an altdpram in MLAB, as the vendored VR4300's RamMLAB.vhd is. The behavioural
// model below is what every simulator runs; Quartus synthesis defines ALTERA_RESERVED_QIS. A read
// of the address being written in the same clock returns the old data in both.

module hng64_mlab #(
    parameter int AW = 5,
    parameter int DW = 16
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] rdata
);

`ifndef ALTERA_RESERVED_QIS
    logic [DW-1:0] mem [0:(1 << AW) - 1];

    initial for (int i = 0; i < (1 << AW); i++) mem[i] = '0;

    always_ff @(posedge clk) if (we) mem[waddr] <= wdata;
    assign rdata = mem[raddr];
`else
    altdpram #(
        .indata_aclr("OFF"), .indata_reg("INCLOCK"),
        .intended_device_family("Cyclone V"), .lpm_type("altdpram"),
        .outdata_aclr("OFF"), .outdata_reg("UNREGISTERED"),
        .ram_block_type("MLAB"),
        .rdaddress_aclr("OFF"), .rdaddress_reg("UNREGISTERED"),
        .rdcontrol_aclr("OFF"), .rdcontrol_reg("UNREGISTERED"),
        .read_during_write_mode_mixed_ports("CONSTRAINED_DONT_CARE"),
        .width(DW), .widthad(AW), .width_byteena(1),
        .wraddress_aclr("OFF"), .wraddress_reg("INCLOCK"),
        .wrcontrol_aclr("OFF"), .wrcontrol_reg("INCLOCK")
    ) u_ram (
        .inclock(clk), .wren(we), .data(wdata), .wraddress(waddr), .rdaddress(raddr), .q(rdata),
        .aclr(1'b0), .byteena(1'b1), .inclocken(1'b1), .outclock(1'b1), .outclocken(1'b1),
        .rdaddressstall(1'b0), .rden(1'b1), .wraddressstall(1'b0)
    );
`endif

endmodule
