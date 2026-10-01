// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_geo (generated from rtl/3d/spinal, GeoEngine.scala): sim/geo_tb/main.cpp
// replays a capture's display-list events and compares the triangles with the Python engine's.
// The ports are the generated ones flattened; the wrap table is packed here.

module tb_geo (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic  [1:0] entry,
    input  logic        samsho,
    input  logic [23:0] vlen,
    output logic        busy,
    output logic  [7:0] dl_addr,
    input  logic [15:0] dl_data,
    input  logic [255:0] wrap,
    input  logic [27:0] vbase,
    output logic        v_rd,
    input  logic        v_rd_ready,
    output logic [27:0] v_rd_addr,
    input  logic        v_data_valid,
    input  logic [63:0] v_data,
    output logic        tri_valid,
    input  logic        tri_ready,
    output logic [63:0] rec [0:21],     // the setup record, each word sign-extended
    output logic [66:0] tri_attr
);

    logic [23:0] w_v_0_0;
    logic [23:0] w_v_0_1;
    logic [23:0] w_v_1_0;
    logic [23:0] w_v_1_1;
    logic [23:0] w_v_2_0;
    logic [23:0] w_v_2_1;
    logic [0:0] w_neg;
    logic [29:0] w_p0_v_0;
    logic [33:0] w_p0_v_1;
    logic [23:0] w_p0_v_2;
    logic [31:0] w_p0_v_3;
    logic [31:0] w_p0_v_4;
    logic [41:0] w_dx_v_0;
    logic [45:0] w_dx_v_1;
    logic [35:0] w_dx_v_2;
    logic [43:0] w_dx_v_3;
    logic [43:0] w_dx_v_4;
    logic [41:0] w_dy_v_0;
    logic [45:0] w_dy_v_1;
    logic [35:0] w_dy_v_2;
    logic [43:0] w_dy_v_3;
    logic [43:0] w_dy_v_4;
    always_comb begin
        rec[0] = {{40{w_v_0_0[23]}}, w_v_0_0};
        rec[1] = {{40{w_v_0_1[23]}}, w_v_0_1};
        rec[2] = {{40{w_v_1_0[23]}}, w_v_1_0};
        rec[3] = {{40{w_v_1_1[23]}}, w_v_1_1};
        rec[4] = {{40{w_v_2_0[23]}}, w_v_2_0};
        rec[5] = {{40{w_v_2_1[23]}}, w_v_2_1};
        rec[6] = {63'd0, w_neg};
        rec[7] = {{34{w_p0_v_0[29]}}, w_p0_v_0};
        rec[8] = {{30{w_p0_v_1[33]}}, w_p0_v_1};
        rec[9] = {{40{w_p0_v_2[23]}}, w_p0_v_2};
        rec[10] = {{32{w_p0_v_3[31]}}, w_p0_v_3};
        rec[11] = {{32{w_p0_v_4[31]}}, w_p0_v_4};
        rec[12] = {{22{w_dx_v_0[41]}}, w_dx_v_0};
        rec[13] = {{18{w_dx_v_1[45]}}, w_dx_v_1};
        rec[14] = {{28{w_dx_v_2[35]}}, w_dx_v_2};
        rec[15] = {{20{w_dx_v_3[43]}}, w_dx_v_3};
        rec[16] = {{20{w_dx_v_4[43]}}, w_dx_v_4};
        rec[17] = {{22{w_dy_v_0[41]}}, w_dy_v_0};
        rec[18] = {{18{w_dy_v_1[45]}}, w_dy_v_1};
        rec[19] = {{28{w_dy_v_2[35]}}, w_dy_v_2};
        rec[20] = {{20{w_dy_v_3[43]}}, w_dy_v_3};
        rec[21] = {{20{w_dy_v_4[43]}}, w_dy_v_4};
    end

    hng64_geo u_dut (
        .clk(clk),
        .reset(reset),
        .io_start(start),
        .io_entry(entry),
        .io_samsho(samsho),
        .io_vlen(vlen),
        .io_busy(busy),
        .io_dlAddr(dl_addr),
        .io_dlData(dl_data),
        .io_wrap_0(wrap[7:0]),
        .io_wrap_1(wrap[15:8]),
        .io_wrap_2(wrap[23:16]),
        .io_wrap_3(wrap[31:24]),
        .io_wrap_4(wrap[39:32]),
        .io_wrap_5(wrap[47:40]),
        .io_wrap_6(wrap[55:48]),
        .io_wrap_7(wrap[63:56]),
        .io_wrap_8(wrap[71:64]),
        .io_wrap_9(wrap[79:72]),
        .io_wrap_10(wrap[87:80]),
        .io_wrap_11(wrap[95:88]),
        .io_wrap_12(wrap[103:96]),
        .io_wrap_13(wrap[111:104]),
        .io_wrap_14(wrap[119:112]),
        .io_wrap_15(wrap[127:120]),
        .io_wrap_16(wrap[135:128]),
        .io_wrap_17(wrap[143:136]),
        .io_wrap_18(wrap[151:144]),
        .io_wrap_19(wrap[159:152]),
        .io_wrap_20(wrap[167:160]),
        .io_wrap_21(wrap[175:168]),
        .io_wrap_22(wrap[183:176]),
        .io_wrap_23(wrap[191:184]),
        .io_wrap_24(wrap[199:192]),
        .io_wrap_25(wrap[207:200]),
        .io_wrap_26(wrap[215:208]),
        .io_wrap_27(wrap[223:216]),
        .io_wrap_28(wrap[231:224]),
        .io_wrap_29(wrap[239:232]),
        .io_wrap_30(wrap[247:240]),
        .io_wrap_31(wrap[255:248]),
        .io_vBase(vbase),
        .io_vRd_valid(v_rd),
        .io_vRd_ready(v_rd_ready),
        .io_vRd_payload(v_rd_addr),
        .io_vData_valid(v_data_valid),
        .io_vData_payload(v_data),
        .io_tri_valid(tri_valid),
        .io_tri_ready(tri_ready),
        .io_tri_payload_v_0_0(w_v_0_0),
        .io_tri_payload_v_0_1(w_v_0_1),
        .io_tri_payload_v_1_0(w_v_1_0),
        .io_tri_payload_v_1_1(w_v_1_1),
        .io_tri_payload_v_2_0(w_v_2_0),
        .io_tri_payload_v_2_1(w_v_2_1),
        .io_tri_payload_neg(w_neg),
        .io_tri_payload_p0_v_0(w_p0_v_0),
        .io_tri_payload_p0_v_1(w_p0_v_1),
        .io_tri_payload_p0_v_2(w_p0_v_2),
        .io_tri_payload_p0_v_3(w_p0_v_3),
        .io_tri_payload_p0_v_4(w_p0_v_4),
        .io_tri_payload_dx_v_0(w_dx_v_0),
        .io_tri_payload_dx_v_1(w_dx_v_1),
        .io_tri_payload_dx_v_2(w_dx_v_2),
        .io_tri_payload_dx_v_3(w_dx_v_3),
        .io_tri_payload_dx_v_4(w_dx_v_4),
        .io_tri_payload_dy_v_0(w_dy_v_0),
        .io_tri_payload_dy_v_1(w_dy_v_1),
        .io_tri_payload_dy_v_2(w_dy_v_2),
        .io_tri_payload_dy_v_3(w_dy_v_3),
        .io_tri_payload_dy_v_4(w_dy_v_4),
        .io_tri_payload_attr(tri_attr));

endmodule
