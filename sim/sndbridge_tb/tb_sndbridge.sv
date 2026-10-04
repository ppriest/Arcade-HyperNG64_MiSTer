// SPDX-License-Identifier: GPL-3.0-or-later
// hng64_sndbridge with its ports out for sim/sndbridge_tb/main.cpp; a poll every 64 clocks and
// "live" for 16 of them, so a heartbeat's stop shows in microseconds.
module tb_sndbridge (
    input  logic        clk,
    input  logic        reset,
    input  logic        cfg_valid,
    input  logic [27:0] smp_base,
    input  logic [27:0] smp_size,
    input  logic        st_req,
    input  logic        st_we,
    input  logic [31:0] st_addr,
    input  logic [63:0] st_wdata,
    input  logic  [7:0] st_be,
    input  logic [15:0] main0,
    input  logic [15:0] main1,
    input  logic        irq,
    input  logic        en,
    input  logic [15:0] en_cmd,
    output logic        live,
    output logic [15:0] rep0,
    output logic [15:0] rep1,
    output logic [27:0] w_addr,
    output logic [63:0] w_data,
    output logic  [7:0] w_be,
    output logic        w_valid,
    input  logic        w_ready,
    output logic [27:0] r_addr,
    output logic        r_rd,
    input  logic        r_ready,
    input  logic        r_valid,
    input  logic [63:0] r_data,
    output logic        dbg_overflow
);
    hng64_sndbridge #(.POLL(64), .LIVE(16)) u (.*);
endmodule
