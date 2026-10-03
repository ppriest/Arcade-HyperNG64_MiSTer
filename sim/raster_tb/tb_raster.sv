// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_raster (generated from rtl/3d/spinal): sim/raster_tb/main.cpp feeds it the
// triangles render_3d_fx.py dumped, serves its DDR3 ports from a memory image, and compares the
// colour plane it writes with the model's 3D buffer. The ports are the generated ones flattened,
// the attributes packed here (Pixel.scala Attr: first field lowest); the widths are RasterConfig's.

module tb_raster (
    input  logic        clk,
    input  logic        reset,
    input  logic        tri_valid,
    output logic        tri_ready,
    input  logic [63:0] rec [0:21],    // the setup record (geo_engine.setup_record), words truncated here
    input  logic [0:0] a_flat,
    input  logic [0:0] a_blend,
    input  logic [0:0] a_tex4bpp,
    input  logic [3:0] a_tex_index,
    input  logic [1:0] a_sub,
    input  logic [6:0] a_hoff,
    input  logic [6:0] a_voff,
    input  logic [15:0] a_pal,
    input  logic [8:0] a_scroll_x,
    input  logic [8:0] a_scroll_y,
    input  logic [4:0] a_wrap_x,
    input  logic [4:0] a_wrap_y,
    output logic  [7:0] f_texel,
    output logic        depth_rd,
    input  logic        depth_rd_ready,
    output logic [27:0] depth_rd_addr,
    input  logic        depth_data_valid,
    input  logic [63:0] depth_data,
    output logic        wr,
    input  logic        wr_ready,
    output logic [27:0] wr_addr,
    output logic [63:0] wr_data,
    output logic  [7:0] wr_be,
    output logic        urgent,
    input  logic        start,
    input  logic        full,
    input  logic  [7:0] tag,
    input  logic  [6:0] scrub,
    input  logic [27:0] colour_base,
    input  logic [27:0] depth_base,
    input  logic        finish,
    output logic        done,
    input  logic        block_start,
    input  logic [27:0] block_src,
    input  logic [11:0] block_groups,
    output logic        block_done,
    input  logic [27:0] tex_base,
    output logic        tex_rd,
    input  logic        tex_rd_ready,
    output logic [27:0] tex_rd_addr,
    input  logic        tex_data_valid,
    input  logic [63:0] tex_data,
    output logic        busy
);

    hng64_raster u_dut (
        .clk(clk),
        .reset(reset),
        .io_tri_valid(tri_valid),
        .io_tri_ready(tri_ready),
        .io_tri_payload_v_0_0(rec[0][23:0]),
        .io_tri_payload_v_0_1(rec[1][23:0]),
        .io_tri_payload_v_1_0(rec[2][23:0]),
        .io_tri_payload_v_1_1(rec[3][23:0]),
        .io_tri_payload_v_2_0(rec[4][23:0]),
        .io_tri_payload_v_2_1(rec[5][23:0]),
        .io_tri_payload_neg(rec[6][0]),
        .io_tri_payload_p0_v_0(rec[7][29:0]),
        .io_tri_payload_p0_v_1(rec[8][33:0]),
        .io_tri_payload_p0_v_2(rec[9][23:0]),
        .io_tri_payload_p0_v_3(rec[10][31:0]),
        .io_tri_payload_p0_v_4(rec[11][31:0]),
        .io_tri_payload_dx_v_0(rec[12][41:0]),
        .io_tri_payload_dx_v_1(rec[13][45:0]),
        .io_tri_payload_dx_v_2(rec[14][35:0]),
        .io_tri_payload_dx_v_3(rec[15][43:0]),
        .io_tri_payload_dx_v_4(rec[16][43:0]),
        .io_tri_payload_dy_v_0(rec[17][41:0]),
        .io_tri_payload_dy_v_1(rec[18][45:0]),
        .io_tri_payload_dy_v_2(rec[19][35:0]),
        .io_tri_payload_dy_v_3(rec[20][43:0]),
        .io_tri_payload_dy_v_4(rec[21][43:0]),
        .io_tri_payload_attr({a_wrap_y, a_wrap_x, a_scroll_y, a_scroll_x, a_pal, a_voff, a_hoff, a_sub, a_tex_index, a_tex4bpp, a_blend, a_flat}),
        .io_depthRd_valid(depth_rd),
        .io_depthRd_ready(depth_rd_ready),
        .io_depthRd_payload(depth_rd_addr),
        .io_depthData_valid(depth_data_valid),
        .io_depthData_payload(depth_data),
        .io_wr_valid(wr),
        .io_wr_ready(wr_ready),
        .io_wr_payload_addr(wr_addr),
        .io_wr_payload_data(wr_data),
        .io_wr_payload_be(wr_be),
        .io_urgent(urgent),
        .io_start(start),
        .io_full(full),
        .io_tag(tag),
        .io_scrub(scrub),
        .io_colourBase(colour_base),
        .io_depthBase(depth_base),
        .io_finish(finish),
        .io_done(done),
        .io_blockStart(block_start),
        .io_blockSrc(block_src),
        .io_blockGroups(block_groups),
        .io_blockDone(block_done),
        .io_texBase(tex_base),
        .io_texRd_valid(tex_rd),
        .io_texRd_ready(tex_rd_ready),
        .io_texRd_payload(tex_rd_addr),
        .io_texData_valid(tex_data_valid),
        .io_texData_payload(tex_data),
        .io_busy(busy));

    // +prof: where the rasteriser's busy clocks go, over the whole run, printed at the end
    bit prof = 1'b0;
    initial prof = $test$plusargs("prof");
    longint n_busy, n_frag, n_pidle, n_walk, n_tcst, n_rbst, n_setupw;
    logic done_q;
    always @(posedge clk) if (prof) begin
        done_q <= done;
        if (done && !done_q) begin
            $display("prof: %0d busy clocks: %0d fragments out of the span rasteriser, it idle %0d; walker busy %0d, walker and setup both empty %0d; stalled at the texture cache %0d, at the render buffer %0d",
                     n_busy, n_frag, n_pidle, n_walk, n_setupw, n_tcst, n_rbst);
            n_busy = 0; n_frag = 0; n_pidle = 0; n_walk = 0; n_tcst = 0; n_rbst = 0; n_setupw = 0;
        end
    end
    always @(posedge clk) if (prof && busy) begin
        n_busy++;
        if (u_dut.skid0_valid && u_dut.skid0_ready) n_frag++;
        if (!u_dut.pixels_io_busy) n_pidle++;
        if (u_dut.walker_io_busy) n_walk++;
        if (u_dut.skid1_valid && !u_dut.skid1_ready) n_tcst++;
        if (u_dut.skid2_valid && !u_dut.skid2_ready) n_rbst++;
        if (!u_dut.walker_io_busy && !u_dut.setup_io_o_valid) n_setupw++;
    end

endmodule
