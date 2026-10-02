// Generator : SpinalHDL v1.13.0    git head : d9d72474863badf47d8585d187f3e04ae4749c59
// Component : hng64_raster
// Git hash  : 671558b6ec2d4ea8a2372381d8823bff68f3ecbd

`timescale 1ns/1ps

module hng64_raster (
  input  wire          io_tri_valid,
  output reg           io_tri_ready,
  input  wire [23:0]   io_tri_payload_v_0_0,
  input  wire [23:0]   io_tri_payload_v_0_1,
  input  wire [23:0]   io_tri_payload_v_1_0,
  input  wire [23:0]   io_tri_payload_v_1_1,
  input  wire [23:0]   io_tri_payload_v_2_0,
  input  wire [23:0]   io_tri_payload_v_2_1,
  input  wire          io_tri_payload_neg,
  input  wire [29:0]   io_tri_payload_p0_v_0,
  input  wire [33:0]   io_tri_payload_p0_v_1,
  input  wire [23:0]   io_tri_payload_p0_v_2,
  input  wire [31:0]   io_tri_payload_p0_v_3,
  input  wire [31:0]   io_tri_payload_p0_v_4,
  input  wire [41:0]   io_tri_payload_dx_v_0,
  input  wire [45:0]   io_tri_payload_dx_v_1,
  input  wire [35:0]   io_tri_payload_dx_v_2,
  input  wire [43:0]   io_tri_payload_dx_v_3,
  input  wire [43:0]   io_tri_payload_dx_v_4,
  input  wire [41:0]   io_tri_payload_dy_v_0,
  input  wire [45:0]   io_tri_payload_dy_v_1,
  input  wire [35:0]   io_tri_payload_dy_v_2,
  input  wire [43:0]   io_tri_payload_dy_v_3,
  input  wire [43:0]   io_tri_payload_dy_v_4,
  input  wire [66:0]   io_tri_payload_attr,
  output wire          io_depthRd_valid,
  input  wire          io_depthRd_ready,
  output wire [27:0]   io_depthRd_payload,
  input  wire          io_depthData_valid,
  input  wire [63:0]   io_depthData_payload,
  output wire          io_wr_valid,
  input  wire          io_wr_ready,
  output wire [27:0]   io_wr_payload_addr,
  output wire [63:0]   io_wr_payload_data,
  output wire [7:0]    io_wr_payload_be,
  output wire          io_urgent,
  input  wire          io_start,
  input  wire          io_full,
  input  wire [7:0]    io_tag,
  input  wire [6:0]    io_scrub,
  input  wire [27:0]   io_colourBase,
  input  wire [27:0]   io_depthBase,
  input  wire          io_finish,
  output wire          io_done,
  input  wire          io_blockStart,
  input  wire [27:0]   io_blockSrc,
  input  wire [11:0]   io_blockGroups,
  output wire          io_blockDone,
  input  wire [27:0]   io_texBase,
  output wire          io_texRd_valid,
  input  wire          io_texRd_ready,
  output wire [27:0]   io_texRd_payload,
  input  wire          io_texData_valid,
  input  wire [63:0]   io_texData_payload,
  output wire          io_busy,
  input  wire          clk,
  input  wire          reset
);

  wire                walker_io_drained;
  wire                texCache_io_rdData_valid;
  wire                texBlock_io_rdData_valid;
  wire       [0:0]    streamMux_io_select;
  wire       [0:0]    streamMux_1_io_select;
  wire                setup_io_i_ready;
  wire                setup_io_o_valid;
  wire       [12:0]   setup_io_o_payload_x0;
  wire       [12:0]   setup_io_o_payload_x1;
  wire       [12:0]   setup_io_o_payload_y0;
  wire       [12:0]   setup_io_o_payload_y1;
  wire       [24:0]   setup_io_o_payload_a_0;
  wire       [24:0]   setup_io_o_payload_a_1;
  wire       [24:0]   setup_io_o_payload_a_2;
  wire       [24:0]   setup_io_o_payload_b_0;
  wire       [24:0]   setup_io_o_payload_b_1;
  wire       [24:0]   setup_io_o_payload_b_2;
  wire       [50:0]   setup_io_o_payload_edge_0;
  wire       [50:0]   setup_io_o_payload_edge_1;
  wire       [50:0]   setup_io_o_payload_edge_2;
  wire       [29:0]   setup_io_o_payload_p_v_0;
  wire       [33:0]   setup_io_o_payload_p_v_1;
  wire       [23:0]   setup_io_o_payload_p_v_2;
  wire       [31:0]   setup_io_o_payload_p_v_3;
  wire       [31:0]   setup_io_o_payload_p_v_4;
  wire       [29:0]   setup_io_o_payload_dx_v_0;
  wire       [33:0]   setup_io_o_payload_dx_v_1;
  wire       [23:0]   setup_io_o_payload_dx_v_2;
  wire       [31:0]   setup_io_o_payload_dx_v_3;
  wire       [31:0]   setup_io_o_payload_dx_v_4;
  wire       [29:0]   setup_io_o_payload_dy_v_0;
  wire       [33:0]   setup_io_o_payload_dy_v_1;
  wire       [23:0]   setup_io_o_payload_dy_v_2;
  wire       [31:0]   setup_io_o_payload_dy_v_3;
  wire       [31:0]   setup_io_o_payload_dy_v_4;
  wire       [66:0]   setup_io_o_payload_attr;
  wire                walker_io_i_ready;
  wire                walker_io_o_valid;
  wire       [8:0]    walker_io_o_payload_x0;
  wire       [8:0]    walker_io_o_payload_x1;
  wire       [8:0]    walker_io_o_payload_y;
  wire                walker_io_busy;
  wire                pixels_io_i_ready;
  wire                pixels_io_o_valid;
  wire       [8:0]    pixels_io_o_payload_x;
  wire       [8:0]    pixels_io_o_payload_y;
  wire       [29:0]   pixels_io_o_payload_p_v_0;
  wire       [33:0]   pixels_io_o_payload_p_v_1;
  wire       [23:0]   pixels_io_o_payload_p_v_2;
  wire       [31:0]   pixels_io_o_payload_p_v_3;
  wire       [31:0]   pixels_io_o_payload_p_v_4;
  wire       [66:0]   pixels_io_o_payload_attr;
  wire                pixels_io_busy;
  wire                pixUnit_io_i_ready;
  wire                pixUnit_io_o_valid;
  wire       [8:0]    pixUnit_io_o_payload_x;
  wire       [8:0]    pixUnit_io_o_payload_y;
  wire       [29:0]   pixUnit_io_o_payload_z;
  wire       [23:0]   pixUnit_io_o_payload_addr;
  wire                pixUnit_io_o_payload_nib;
  wire       [7:0]    pixUnit_io_o_payload_light;
  wire                pixUnit_io_o_payload_flat;
  wire                pixUnit_io_o_payload_blend;
  wire                pixUnit_io_o_payload_tex4bpp;
  wire       [15:0]   pixUnit_io_o_payload_pal;
  wire                pixUnit_io_busy;
  wire                texCache_io_i_ready;
  wire                texCache_io_o_valid;
  wire       [8:0]    texCache_io_o_payload_f_x;
  wire       [8:0]    texCache_io_o_payload_f_y;
  wire       [29:0]   texCache_io_o_payload_f_z;
  wire       [23:0]   texCache_io_o_payload_f_addr;
  wire                texCache_io_o_payload_f_nib;
  wire       [7:0]    texCache_io_o_payload_f_light;
  wire                texCache_io_o_payload_f_flat;
  wire                texCache_io_o_payload_f_blend;
  wire                texCache_io_o_payload_f_tex4bpp;
  wire       [15:0]   texCache_io_o_payload_f_pal;
  wire       [7:0]    texCache_io_o_payload_texel;
  wire                texCache_io_rdAddr_valid;
  wire       [27:0]   texCache_io_rdAddr_payload;
  wire                texCache_io_busy;
  wire                renderBuf_io_i_ready;
  wire                renderBuf_io_rdAddr_valid;
  wire       [27:0]   renderBuf_io_rdAddr_payload;
  wire                renderBuf_io_wr_valid;
  wire       [27:0]   renderBuf_io_wr_payload_addr;
  wire       [63:0]   renderBuf_io_wr_payload_data;
  wire       [7:0]    renderBuf_io_wr_payload_be;
  wire                renderBuf_io_urgent;
  wire                renderBuf_io_done;
  wire                renderBuf_io_busy;
  wire                texBlock_io_done;
  wire                texBlock_io_busy;
  wire                texBlock_io_rdAddr_valid;
  wire       [27:0]   texBlock_io_rdAddr_payload;
  wire                texBlock_io_wr_valid;
  wire       [27:0]   texBlock_io_wr_payload_addr;
  wire       [63:0]   texBlock_io_wr_payload_data;
  wire       [7:0]    texBlock_io_wr_payload_be;
  wire                spanParams_io_i_ready;
  wire                spanParams_io_o_valid;
  wire       [8:0]    spanParams_io_o_payload_x0;
  wire       [8:0]    spanParams_io_o_payload_x1;
  wire       [8:0]    spanParams_io_o_payload_y;
  wire       [29:0]   spanParams_io_o_payload_p_v_0;
  wire       [33:0]   spanParams_io_o_payload_p_v_1;
  wire       [23:0]   spanParams_io_o_payload_p_v_2;
  wire       [31:0]   spanParams_io_o_payload_p_v_3;
  wire       [31:0]   spanParams_io_o_payload_p_v_4;
  wire       [29:0]   spanParams_io_o_payload_dx_v_0;
  wire       [33:0]   spanParams_io_o_payload_dx_v_1;
  wire       [23:0]   spanParams_io_o_payload_dx_v_2;
  wire       [31:0]   spanParams_io_o_payload_dx_v_3;
  wire       [31:0]   spanParams_io_o_payload_dx_v_4;
  wire       [66:0]   spanParams_io_o_payload_attr;
  wire                spanParams_io_idle;
  wire                io_o_fifo_io_push_ready;
  wire                io_o_fifo_io_pop_valid;
  wire       [8:0]    io_o_fifo_io_pop_payload_x0;
  wire       [8:0]    io_o_fifo_io_pop_payload_x1;
  wire       [8:0]    io_o_fifo_io_pop_payload_y;
  wire       [29:0]   io_o_fifo_io_pop_payload_p_v_0;
  wire       [33:0]   io_o_fifo_io_pop_payload_p_v_1;
  wire       [23:0]   io_o_fifo_io_pop_payload_p_v_2;
  wire       [31:0]   io_o_fifo_io_pop_payload_p_v_3;
  wire       [31:0]   io_o_fifo_io_pop_payload_p_v_4;
  wire       [29:0]   io_o_fifo_io_pop_payload_dx_v_0;
  wire       [33:0]   io_o_fifo_io_pop_payload_dx_v_1;
  wire       [23:0]   io_o_fifo_io_pop_payload_dx_v_2;
  wire       [31:0]   io_o_fifo_io_pop_payload_dx_v_3;
  wire       [31:0]   io_o_fifo_io_pop_payload_dx_v_4;
  wire       [66:0]   io_o_fifo_io_pop_payload_attr;
  wire       [2:0]    io_o_fifo_io_occupancy;
  wire       [2:0]    io_o_fifo_io_availability;
  wire                streamMux_io_inputs_0_ready;
  wire                streamMux_io_inputs_1_ready;
  wire                streamMux_io_output_valid;
  wire       [27:0]   streamMux_io_output_payload;
  wire                streamMux_1_io_inputs_0_ready;
  wire                streamMux_1_io_inputs_1_ready;
  wire                streamMux_1_io_output_valid;
  wire       [27:0]   streamMux_1_io_output_payload_addr;
  wire       [63:0]   streamMux_1_io_output_payload_data;
  wire       [7:0]    streamMux_1_io_output_payload_be;
  wire                triIn_valid;
  wire                triIn_ready;
  wire       [23:0]   triIn_payload_v_0_0;
  wire       [23:0]   triIn_payload_v_0_1;
  wire       [23:0]   triIn_payload_v_1_0;
  wire       [23:0]   triIn_payload_v_1_1;
  wire       [23:0]   triIn_payload_v_2_0;
  wire       [23:0]   triIn_payload_v_2_1;
  wire                triIn_payload_neg;
  wire       [29:0]   triIn_payload_p0_v_0;
  wire       [33:0]   triIn_payload_p0_v_1;
  wire       [23:0]   triIn_payload_p0_v_2;
  wire       [31:0]   triIn_payload_p0_v_3;
  wire       [31:0]   triIn_payload_p0_v_4;
  wire       [41:0]   triIn_payload_dx_v_0;
  wire       [45:0]   triIn_payload_dx_v_1;
  wire       [35:0]   triIn_payload_dx_v_2;
  wire       [43:0]   triIn_payload_dx_v_3;
  wire       [43:0]   triIn_payload_dx_v_4;
  wire       [41:0]   triIn_payload_dy_v_0;
  wire       [45:0]   triIn_payload_dy_v_1;
  wire       [35:0]   triIn_payload_dy_v_2;
  wire       [43:0]   triIn_payload_dy_v_3;
  wire       [43:0]   triIn_payload_dy_v_4;
  wire       [66:0]   triIn_payload_attr;
  reg                 io_tri_rValid;
  reg        [23:0]   io_tri_rData_v_0_0;
  reg        [23:0]   io_tri_rData_v_0_1;
  reg        [23:0]   io_tri_rData_v_1_0;
  reg        [23:0]   io_tri_rData_v_1_1;
  reg        [23:0]   io_tri_rData_v_2_0;
  reg        [23:0]   io_tri_rData_v_2_1;
  reg                 io_tri_rData_neg;
  reg        [29:0]   io_tri_rData_p0_v_0;
  reg        [33:0]   io_tri_rData_p0_v_1;
  reg        [23:0]   io_tri_rData_p0_v_2;
  reg        [31:0]   io_tri_rData_p0_v_3;
  reg        [31:0]   io_tri_rData_p0_v_4;
  reg        [41:0]   io_tri_rData_dx_v_0;
  reg        [45:0]   io_tri_rData_dx_v_1;
  reg        [35:0]   io_tri_rData_dx_v_2;
  reg        [43:0]   io_tri_rData_dx_v_3;
  reg        [43:0]   io_tri_rData_dx_v_4;
  reg        [41:0]   io_tri_rData_dy_v_0;
  reg        [45:0]   io_tri_rData_dy_v_1;
  reg        [35:0]   io_tri_rData_dy_v_2;
  reg        [43:0]   io_tri_rData_dy_v_3;
  reg        [43:0]   io_tri_rData_dy_v_4;
  reg        [66:0]   io_tri_rData_attr;
  wire                when_Stream_l477;
  wire                walkOut_valid;
  wire                walkOut_ready;
  wire       [8:0]    walkOut_payload_x0;
  wire       [8:0]    walkOut_payload_x1;
  wire       [8:0]    walkOut_payload_y;
  reg                 io_o_rValidN;
  reg        [8:0]    io_o_rData_x0;
  reg        [8:0]    io_o_rData_x1;
  reg        [8:0]    io_o_rData_y;
  wire                skid0_valid;
  wire                skid0_ready;
  wire       [8:0]    skid0_payload_x;
  wire       [8:0]    skid0_payload_y;
  wire       [29:0]   skid0_payload_p_v_0;
  wire       [33:0]   skid0_payload_p_v_1;
  wire       [23:0]   skid0_payload_p_v_2;
  wire       [31:0]   skid0_payload_p_v_3;
  wire       [31:0]   skid0_payload_p_v_4;
  wire       [66:0]   skid0_payload_attr;
  reg                 io_o_rValidN_1;
  reg        [8:0]    io_o_rData_x;
  reg        [8:0]    io_o_rData_y_1;
  reg        [29:0]   io_o_rData_p_v_0;
  reg        [33:0]   io_o_rData_p_v_1;
  reg        [23:0]   io_o_rData_p_v_2;
  reg        [31:0]   io_o_rData_p_v_3;
  reg        [31:0]   io_o_rData_p_v_4;
  reg        [66:0]   io_o_rData_attr;
  wire                skid1_valid;
  wire                skid1_ready;
  wire       [8:0]    skid1_payload_x;
  wire       [8:0]    skid1_payload_y;
  wire       [29:0]   skid1_payload_z;
  wire       [23:0]   skid1_payload_addr;
  wire                skid1_payload_nib;
  wire       [7:0]    skid1_payload_light;
  wire                skid1_payload_flat;
  wire                skid1_payload_blend;
  wire                skid1_payload_tex4bpp;
  wire       [15:0]   skid1_payload_pal;
  reg                 io_o_rValidN_2;
  reg        [8:0]    io_o_rData_x_1;
  reg        [8:0]    io_o_rData_y_2;
  reg        [29:0]   io_o_rData_z;
  reg        [23:0]   io_o_rData_addr;
  reg                 io_o_rData_nib;
  reg        [7:0]    io_o_rData_light;
  reg                 io_o_rData_flat;
  reg                 io_o_rData_blend;
  reg                 io_o_rData_tex4bpp;
  reg        [15:0]   io_o_rData_pal;
  wire                skid2_valid;
  wire                skid2_ready;
  wire       [8:0]    skid2_payload_f_x;
  wire       [8:0]    skid2_payload_f_y;
  wire       [29:0]   skid2_payload_f_z;
  wire       [23:0]   skid2_payload_f_addr;
  wire                skid2_payload_f_nib;
  wire       [7:0]    skid2_payload_f_light;
  wire                skid2_payload_f_flat;
  wire                skid2_payload_f_blend;
  wire                skid2_payload_f_tex4bpp;
  wire       [15:0]   skid2_payload_f_pal;
  wire       [7:0]    skid2_payload_texel;
  reg                 io_o_rValidN_3;
  reg        [8:0]    io_o_rData_f_x;
  reg        [8:0]    io_o_rData_f_y;
  reg        [29:0]   io_o_rData_f_z;
  reg        [23:0]   io_o_rData_f_addr;
  reg                 io_o_rData_f_nib;
  reg        [7:0]    io_o_rData_f_light;
  reg                 io_o_rData_f_flat;
  reg                 io_o_rData_f_blend;
  reg                 io_o_rData_f_tex4bpp;
  reg        [15:0]   io_o_rData_f_pal;
  reg        [7:0]    io_o_rData_texel;

  hng64_raster_TriangleSetup setup (
    .io_i_valid          (triIn_valid                    ), //i
    .io_i_ready          (setup_io_i_ready               ), //o
    .io_i_payload_v_0_0  (triIn_payload_v_0_0[23:0]      ), //i
    .io_i_payload_v_0_1  (triIn_payload_v_0_1[23:0]      ), //i
    .io_i_payload_v_1_0  (triIn_payload_v_1_0[23:0]      ), //i
    .io_i_payload_v_1_1  (triIn_payload_v_1_1[23:0]      ), //i
    .io_i_payload_v_2_0  (triIn_payload_v_2_0[23:0]      ), //i
    .io_i_payload_v_2_1  (triIn_payload_v_2_1[23:0]      ), //i
    .io_i_payload_neg    (triIn_payload_neg              ), //i
    .io_i_payload_p0_v_0 (triIn_payload_p0_v_0[29:0]     ), //i
    .io_i_payload_p0_v_1 (triIn_payload_p0_v_1[33:0]     ), //i
    .io_i_payload_p0_v_2 (triIn_payload_p0_v_2[23:0]     ), //i
    .io_i_payload_p0_v_3 (triIn_payload_p0_v_3[31:0]     ), //i
    .io_i_payload_p0_v_4 (triIn_payload_p0_v_4[31:0]     ), //i
    .io_i_payload_dx_v_0 (triIn_payload_dx_v_0[41:0]     ), //i
    .io_i_payload_dx_v_1 (triIn_payload_dx_v_1[45:0]     ), //i
    .io_i_payload_dx_v_2 (triIn_payload_dx_v_2[35:0]     ), //i
    .io_i_payload_dx_v_3 (triIn_payload_dx_v_3[43:0]     ), //i
    .io_i_payload_dx_v_4 (triIn_payload_dx_v_4[43:0]     ), //i
    .io_i_payload_dy_v_0 (triIn_payload_dy_v_0[41:0]     ), //i
    .io_i_payload_dy_v_1 (triIn_payload_dy_v_1[45:0]     ), //i
    .io_i_payload_dy_v_2 (triIn_payload_dy_v_2[35:0]     ), //i
    .io_i_payload_dy_v_3 (triIn_payload_dy_v_3[43:0]     ), //i
    .io_i_payload_dy_v_4 (triIn_payload_dy_v_4[43:0]     ), //i
    .io_i_payload_attr   (triIn_payload_attr[66:0]       ), //i
    .io_o_valid          (setup_io_o_valid               ), //o
    .io_o_ready          (walker_io_i_ready              ), //i
    .io_o_payload_x0     (setup_io_o_payload_x0[12:0]    ), //o
    .io_o_payload_x1     (setup_io_o_payload_x1[12:0]    ), //o
    .io_o_payload_y0     (setup_io_o_payload_y0[12:0]    ), //o
    .io_o_payload_y1     (setup_io_o_payload_y1[12:0]    ), //o
    .io_o_payload_a_0    (setup_io_o_payload_a_0[24:0]   ), //o
    .io_o_payload_a_1    (setup_io_o_payload_a_1[24:0]   ), //o
    .io_o_payload_a_2    (setup_io_o_payload_a_2[24:0]   ), //o
    .io_o_payload_b_0    (setup_io_o_payload_b_0[24:0]   ), //o
    .io_o_payload_b_1    (setup_io_o_payload_b_1[24:0]   ), //o
    .io_o_payload_b_2    (setup_io_o_payload_b_2[24:0]   ), //o
    .io_o_payload_edge_0 (setup_io_o_payload_edge_0[50:0]), //o
    .io_o_payload_edge_1 (setup_io_o_payload_edge_1[50:0]), //o
    .io_o_payload_edge_2 (setup_io_o_payload_edge_2[50:0]), //o
    .io_o_payload_p_v_0  (setup_io_o_payload_p_v_0[29:0] ), //o
    .io_o_payload_p_v_1  (setup_io_o_payload_p_v_1[33:0] ), //o
    .io_o_payload_p_v_2  (setup_io_o_payload_p_v_2[23:0] ), //o
    .io_o_payload_p_v_3  (setup_io_o_payload_p_v_3[31:0] ), //o
    .io_o_payload_p_v_4  (setup_io_o_payload_p_v_4[31:0] ), //o
    .io_o_payload_dx_v_0 (setup_io_o_payload_dx_v_0[29:0]), //o
    .io_o_payload_dx_v_1 (setup_io_o_payload_dx_v_1[33:0]), //o
    .io_o_payload_dx_v_2 (setup_io_o_payload_dx_v_2[23:0]), //o
    .io_o_payload_dx_v_3 (setup_io_o_payload_dx_v_3[31:0]), //o
    .io_o_payload_dx_v_4 (setup_io_o_payload_dx_v_4[31:0]), //o
    .io_o_payload_dy_v_0 (setup_io_o_payload_dy_v_0[29:0]), //o
    .io_o_payload_dy_v_1 (setup_io_o_payload_dy_v_1[33:0]), //o
    .io_o_payload_dy_v_2 (setup_io_o_payload_dy_v_2[23:0]), //o
    .io_o_payload_dy_v_3 (setup_io_o_payload_dy_v_3[31:0]), //o
    .io_o_payload_dy_v_4 (setup_io_o_payload_dy_v_4[31:0]), //o
    .io_o_payload_attr   (setup_io_o_payload_attr[66:0]  ), //o
    .clk                 (clk                            ), //i
    .reset               (reset                          )  //i
  );
  hng64_raster_SpanWalker walker (
    .io_i_valid          (setup_io_o_valid               ), //i
    .io_i_ready          (walker_io_i_ready              ), //o
    .io_i_payload_x0     (setup_io_o_payload_x0[12:0]    ), //i
    .io_i_payload_x1     (setup_io_o_payload_x1[12:0]    ), //i
    .io_i_payload_y0     (setup_io_o_payload_y0[12:0]    ), //i
    .io_i_payload_y1     (setup_io_o_payload_y1[12:0]    ), //i
    .io_i_payload_a_0    (setup_io_o_payload_a_0[24:0]   ), //i
    .io_i_payload_a_1    (setup_io_o_payload_a_1[24:0]   ), //i
    .io_i_payload_a_2    (setup_io_o_payload_a_2[24:0]   ), //i
    .io_i_payload_b_0    (setup_io_o_payload_b_0[24:0]   ), //i
    .io_i_payload_b_1    (setup_io_o_payload_b_1[24:0]   ), //i
    .io_i_payload_b_2    (setup_io_o_payload_b_2[24:0]   ), //i
    .io_i_payload_edge_0 (setup_io_o_payload_edge_0[50:0]), //i
    .io_i_payload_edge_1 (setup_io_o_payload_edge_1[50:0]), //i
    .io_i_payload_edge_2 (setup_io_o_payload_edge_2[50:0]), //i
    .io_i_payload_p_v_0  (setup_io_o_payload_p_v_0[29:0] ), //i
    .io_i_payload_p_v_1  (setup_io_o_payload_p_v_1[33:0] ), //i
    .io_i_payload_p_v_2  (setup_io_o_payload_p_v_2[23:0] ), //i
    .io_i_payload_p_v_3  (setup_io_o_payload_p_v_3[31:0] ), //i
    .io_i_payload_p_v_4  (setup_io_o_payload_p_v_4[31:0] ), //i
    .io_i_payload_dx_v_0 (setup_io_o_payload_dx_v_0[29:0]), //i
    .io_i_payload_dx_v_1 (setup_io_o_payload_dx_v_1[33:0]), //i
    .io_i_payload_dx_v_2 (setup_io_o_payload_dx_v_2[23:0]), //i
    .io_i_payload_dx_v_3 (setup_io_o_payload_dx_v_3[31:0]), //i
    .io_i_payload_dx_v_4 (setup_io_o_payload_dx_v_4[31:0]), //i
    .io_i_payload_dy_v_0 (setup_io_o_payload_dy_v_0[29:0]), //i
    .io_i_payload_dy_v_1 (setup_io_o_payload_dy_v_1[33:0]), //i
    .io_i_payload_dy_v_2 (setup_io_o_payload_dy_v_2[23:0]), //i
    .io_i_payload_dy_v_3 (setup_io_o_payload_dy_v_3[31:0]), //i
    .io_i_payload_dy_v_4 (setup_io_o_payload_dy_v_4[31:0]), //i
    .io_i_payload_attr   (setup_io_o_payload_attr[66:0]  ), //i
    .io_o_valid          (walker_io_o_valid              ), //o
    .io_o_ready          (io_o_rValidN                   ), //i
    .io_o_payload_x0     (walker_io_o_payload_x0[8:0]    ), //o
    .io_o_payload_x1     (walker_io_o_payload_x1[8:0]    ), //o
    .io_o_payload_y      (walker_io_o_payload_y[8:0]     ), //o
    .io_drained          (walker_io_drained              ), //i
    .io_busy             (walker_io_busy                 ), //o
    .clk                 (clk                            ), //i
    .reset               (reset                          )  //i
  );
  hng64_raster_SpanPixels pixels (
    .io_i_valid          (io_o_fifo_io_pop_valid               ), //i
    .io_i_ready          (pixels_io_i_ready                    ), //o
    .io_i_payload_x0     (io_o_fifo_io_pop_payload_x0[8:0]     ), //i
    .io_i_payload_x1     (io_o_fifo_io_pop_payload_x1[8:0]     ), //i
    .io_i_payload_y      (io_o_fifo_io_pop_payload_y[8:0]      ), //i
    .io_i_payload_p_v_0  (io_o_fifo_io_pop_payload_p_v_0[29:0] ), //i
    .io_i_payload_p_v_1  (io_o_fifo_io_pop_payload_p_v_1[33:0] ), //i
    .io_i_payload_p_v_2  (io_o_fifo_io_pop_payload_p_v_2[23:0] ), //i
    .io_i_payload_p_v_3  (io_o_fifo_io_pop_payload_p_v_3[31:0] ), //i
    .io_i_payload_p_v_4  (io_o_fifo_io_pop_payload_p_v_4[31:0] ), //i
    .io_i_payload_dx_v_0 (io_o_fifo_io_pop_payload_dx_v_0[29:0]), //i
    .io_i_payload_dx_v_1 (io_o_fifo_io_pop_payload_dx_v_1[33:0]), //i
    .io_i_payload_dx_v_2 (io_o_fifo_io_pop_payload_dx_v_2[23:0]), //i
    .io_i_payload_dx_v_3 (io_o_fifo_io_pop_payload_dx_v_3[31:0]), //i
    .io_i_payload_dx_v_4 (io_o_fifo_io_pop_payload_dx_v_4[31:0]), //i
    .io_i_payload_attr   (io_o_fifo_io_pop_payload_attr[66:0]  ), //i
    .io_o_valid          (pixels_io_o_valid                    ), //o
    .io_o_ready          (io_o_rValidN_1                       ), //i
    .io_o_payload_x      (pixels_io_o_payload_x[8:0]           ), //o
    .io_o_payload_y      (pixels_io_o_payload_y[8:0]           ), //o
    .io_o_payload_p_v_0  (pixels_io_o_payload_p_v_0[29:0]      ), //o
    .io_o_payload_p_v_1  (pixels_io_o_payload_p_v_1[33:0]      ), //o
    .io_o_payload_p_v_2  (pixels_io_o_payload_p_v_2[23:0]      ), //o
    .io_o_payload_p_v_3  (pixels_io_o_payload_p_v_3[31:0]      ), //o
    .io_o_payload_p_v_4  (pixels_io_o_payload_p_v_4[31:0]      ), //o
    .io_o_payload_attr   (pixels_io_o_payload_attr[66:0]       ), //o
    .io_busy             (pixels_io_busy                       ), //o
    .clk                 (clk                                  ), //i
    .reset               (reset                                )  //i
  );
  hng64_raster_PixelUnit pixUnit (
    .io_i_valid           (skid0_valid                    ), //i
    .io_i_ready           (pixUnit_io_i_ready             ), //o
    .io_i_payload_x       (skid0_payload_x[8:0]           ), //i
    .io_i_payload_y       (skid0_payload_y[8:0]           ), //i
    .io_i_payload_p_v_0   (skid0_payload_p_v_0[29:0]      ), //i
    .io_i_payload_p_v_1   (skid0_payload_p_v_1[33:0]      ), //i
    .io_i_payload_p_v_2   (skid0_payload_p_v_2[23:0]      ), //i
    .io_i_payload_p_v_3   (skid0_payload_p_v_3[31:0]      ), //i
    .io_i_payload_p_v_4   (skid0_payload_p_v_4[31:0]      ), //i
    .io_i_payload_attr    (skid0_payload_attr[66:0]       ), //i
    .io_o_valid           (pixUnit_io_o_valid             ), //o
    .io_o_ready           (io_o_rValidN_2                 ), //i
    .io_o_payload_x       (pixUnit_io_o_payload_x[8:0]    ), //o
    .io_o_payload_y       (pixUnit_io_o_payload_y[8:0]    ), //o
    .io_o_payload_z       (pixUnit_io_o_payload_z[29:0]   ), //o
    .io_o_payload_addr    (pixUnit_io_o_payload_addr[23:0]), //o
    .io_o_payload_nib     (pixUnit_io_o_payload_nib       ), //o
    .io_o_payload_light   (pixUnit_io_o_payload_light[7:0]), //o
    .io_o_payload_flat    (pixUnit_io_o_payload_flat      ), //o
    .io_o_payload_blend   (pixUnit_io_o_payload_blend     ), //o
    .io_o_payload_tex4bpp (pixUnit_io_o_payload_tex4bpp   ), //o
    .io_o_payload_pal     (pixUnit_io_o_payload_pal[15:0] ), //o
    .io_busy              (pixUnit_io_busy                ), //o
    .clk                  (clk                            ), //i
    .reset                (reset                          )  //i
  );
  hng64_raster_TexCache texCache (
    .io_i_valid             (skid1_valid                       ), //i
    .io_i_ready             (texCache_io_i_ready               ), //o
    .io_i_payload_x         (skid1_payload_x[8:0]              ), //i
    .io_i_payload_y         (skid1_payload_y[8:0]              ), //i
    .io_i_payload_z         (skid1_payload_z[29:0]             ), //i
    .io_i_payload_addr      (skid1_payload_addr[23:0]          ), //i
    .io_i_payload_nib       (skid1_payload_nib                 ), //i
    .io_i_payload_light     (skid1_payload_light[7:0]          ), //i
    .io_i_payload_flat      (skid1_payload_flat                ), //i
    .io_i_payload_blend     (skid1_payload_blend               ), //i
    .io_i_payload_tex4bpp   (skid1_payload_tex4bpp             ), //i
    .io_i_payload_pal       (skid1_payload_pal[15:0]           ), //i
    .io_o_valid             (texCache_io_o_valid               ), //o
    .io_o_ready             (io_o_rValidN_3                    ), //i
    .io_o_payload_f_x       (texCache_io_o_payload_f_x[8:0]    ), //o
    .io_o_payload_f_y       (texCache_io_o_payload_f_y[8:0]    ), //o
    .io_o_payload_f_z       (texCache_io_o_payload_f_z[29:0]   ), //o
    .io_o_payload_f_addr    (texCache_io_o_payload_f_addr[23:0]), //o
    .io_o_payload_f_nib     (texCache_io_o_payload_f_nib       ), //o
    .io_o_payload_f_light   (texCache_io_o_payload_f_light[7:0]), //o
    .io_o_payload_f_flat    (texCache_io_o_payload_f_flat      ), //o
    .io_o_payload_f_blend   (texCache_io_o_payload_f_blend     ), //o
    .io_o_payload_f_tex4bpp (texCache_io_o_payload_f_tex4bpp   ), //o
    .io_o_payload_f_pal     (texCache_io_o_payload_f_pal[15:0] ), //o
    .io_o_payload_texel     (texCache_io_o_payload_texel[7:0]  ), //o
    .io_texBase             (io_texBase[27:0]                  ), //i
    .io_rdAddr_valid        (texCache_io_rdAddr_valid          ), //o
    .io_rdAddr_ready        (streamMux_io_inputs_0_ready       ), //i
    .io_rdAddr_payload      (texCache_io_rdAddr_payload[27:0]  ), //o
    .io_rdData_valid        (texCache_io_rdData_valid          ), //i
    .io_rdData_payload      (io_texData_payload[63:0]          ), //i
    .io_busy                (texCache_io_busy                  ), //o
    .clk                    (clk                               ), //i
    .reset                  (reset                             )  //i
  );
  hng64_raster_RenderBuf renderBuf (
    .io_i_valid             (skid2_valid                       ), //i
    .io_i_ready             (renderBuf_io_i_ready              ), //o
    .io_i_payload_f_x       (skid2_payload_f_x[8:0]            ), //i
    .io_i_payload_f_y       (skid2_payload_f_y[8:0]            ), //i
    .io_i_payload_f_z       (skid2_payload_f_z[29:0]           ), //i
    .io_i_payload_f_addr    (skid2_payload_f_addr[23:0]        ), //i
    .io_i_payload_f_nib     (skid2_payload_f_nib               ), //i
    .io_i_payload_f_light   (skid2_payload_f_light[7:0]        ), //i
    .io_i_payload_f_flat    (skid2_payload_f_flat              ), //i
    .io_i_payload_f_blend   (skid2_payload_f_blend             ), //i
    .io_i_payload_f_tex4bpp (skid2_payload_f_tex4bpp           ), //i
    .io_i_payload_f_pal     (skid2_payload_f_pal[15:0]         ), //i
    .io_i_payload_texel     (skid2_payload_texel[7:0]          ), //i
    .io_rdAddr_valid        (renderBuf_io_rdAddr_valid         ), //o
    .io_rdAddr_ready        (io_depthRd_ready                  ), //i
    .io_rdAddr_payload      (renderBuf_io_rdAddr_payload[27:0] ), //o
    .io_rdData_valid        (io_depthData_valid                ), //i
    .io_rdData_payload      (io_depthData_payload[63:0]        ), //i
    .io_wr_valid            (renderBuf_io_wr_valid             ), //o
    .io_wr_ready            (streamMux_1_io_inputs_0_ready     ), //i
    .io_wr_payload_addr     (renderBuf_io_wr_payload_addr[27:0]), //o
    .io_wr_payload_data     (renderBuf_io_wr_payload_data[63:0]), //o
    .io_wr_payload_be       (renderBuf_io_wr_payload_be[7:0]   ), //o
    .io_urgent              (renderBuf_io_urgent               ), //o
    .io_start               (io_start                          ), //i
    .io_full                (io_full                           ), //i
    .io_tag                 (io_tag[7:0]                       ), //i
    .io_scrub               (io_scrub[6:0]                     ), //i
    .io_colourBase          (io_colourBase[27:0]               ), //i
    .io_depthBase           (io_depthBase[27:0]                ), //i
    .io_finish              (io_finish                         ), //i
    .io_done                (renderBuf_io_done                 ), //o
    .io_busy                (renderBuf_io_busy                 ), //o
    .clk                    (clk                               ), //i
    .reset                  (reset                             )  //i
  );
  hng64_raster_TexBlock texBlock (
    .io_start           (io_blockStart                    ), //i
    .io_src             (io_blockSrc[27:0]                ), //i
    .io_dst             (io_texBase[27:0]                 ), //i
    .io_groups          (io_blockGroups[11:0]             ), //i
    .io_done            (texBlock_io_done                 ), //o
    .io_busy            (texBlock_io_busy                 ), //o
    .io_rdAddr_valid    (texBlock_io_rdAddr_valid         ), //o
    .io_rdAddr_ready    (streamMux_io_inputs_1_ready      ), //i
    .io_rdAddr_payload  (texBlock_io_rdAddr_payload[27:0] ), //o
    .io_rdData_valid    (texBlock_io_rdData_valid         ), //i
    .io_rdData_payload  (io_texData_payload[63:0]         ), //i
    .io_wr_valid        (texBlock_io_wr_valid             ), //o
    .io_wr_ready        (streamMux_1_io_inputs_1_ready    ), //i
    .io_wr_payload_addr (texBlock_io_wr_payload_addr[27:0]), //o
    .io_wr_payload_data (texBlock_io_wr_payload_data[63:0]), //o
    .io_wr_payload_be   (texBlock_io_wr_payload_be[7:0]   ), //o
    .clk                (clk                              ), //i
    .reset              (reset                            )  //i
  );
  hng64_raster_SpanParams spanParams (
    .io_i_valid          (walkOut_valid                       ), //i
    .io_i_ready          (spanParams_io_i_ready               ), //o
    .io_i_payload_x0     (walkOut_payload_x0[8:0]             ), //i
    .io_i_payload_x1     (walkOut_payload_x1[8:0]             ), //i
    .io_i_payload_y      (walkOut_payload_y[8:0]              ), //i
    .io_tri_x0           (setup_io_o_payload_x0[12:0]         ), //i
    .io_tri_x1           (setup_io_o_payload_x1[12:0]         ), //i
    .io_tri_y0           (setup_io_o_payload_y0[12:0]         ), //i
    .io_tri_y1           (setup_io_o_payload_y1[12:0]         ), //i
    .io_tri_a_0          (setup_io_o_payload_a_0[24:0]        ), //i
    .io_tri_a_1          (setup_io_o_payload_a_1[24:0]        ), //i
    .io_tri_a_2          (setup_io_o_payload_a_2[24:0]        ), //i
    .io_tri_b_0          (setup_io_o_payload_b_0[24:0]        ), //i
    .io_tri_b_1          (setup_io_o_payload_b_1[24:0]        ), //i
    .io_tri_b_2          (setup_io_o_payload_b_2[24:0]        ), //i
    .io_tri_edge_0       (setup_io_o_payload_edge_0[50:0]     ), //i
    .io_tri_edge_1       (setup_io_o_payload_edge_1[50:0]     ), //i
    .io_tri_edge_2       (setup_io_o_payload_edge_2[50:0]     ), //i
    .io_tri_p_v_0        (setup_io_o_payload_p_v_0[29:0]      ), //i
    .io_tri_p_v_1        (setup_io_o_payload_p_v_1[33:0]      ), //i
    .io_tri_p_v_2        (setup_io_o_payload_p_v_2[23:0]      ), //i
    .io_tri_p_v_3        (setup_io_o_payload_p_v_3[31:0]      ), //i
    .io_tri_p_v_4        (setup_io_o_payload_p_v_4[31:0]      ), //i
    .io_tri_dx_v_0       (setup_io_o_payload_dx_v_0[29:0]     ), //i
    .io_tri_dx_v_1       (setup_io_o_payload_dx_v_1[33:0]     ), //i
    .io_tri_dx_v_2       (setup_io_o_payload_dx_v_2[23:0]     ), //i
    .io_tri_dx_v_3       (setup_io_o_payload_dx_v_3[31:0]     ), //i
    .io_tri_dx_v_4       (setup_io_o_payload_dx_v_4[31:0]     ), //i
    .io_tri_dy_v_0       (setup_io_o_payload_dy_v_0[29:0]     ), //i
    .io_tri_dy_v_1       (setup_io_o_payload_dy_v_1[33:0]     ), //i
    .io_tri_dy_v_2       (setup_io_o_payload_dy_v_2[23:0]     ), //i
    .io_tri_dy_v_3       (setup_io_o_payload_dy_v_3[31:0]     ), //i
    .io_tri_dy_v_4       (setup_io_o_payload_dy_v_4[31:0]     ), //i
    .io_tri_attr         (setup_io_o_payload_attr[66:0]       ), //i
    .io_o_valid          (spanParams_io_o_valid               ), //o
    .io_o_ready          (io_o_fifo_io_push_ready             ), //i
    .io_o_payload_x0     (spanParams_io_o_payload_x0[8:0]     ), //o
    .io_o_payload_x1     (spanParams_io_o_payload_x1[8:0]     ), //o
    .io_o_payload_y      (spanParams_io_o_payload_y[8:0]      ), //o
    .io_o_payload_p_v_0  (spanParams_io_o_payload_p_v_0[29:0] ), //o
    .io_o_payload_p_v_1  (spanParams_io_o_payload_p_v_1[33:0] ), //o
    .io_o_payload_p_v_2  (spanParams_io_o_payload_p_v_2[23:0] ), //o
    .io_o_payload_p_v_3  (spanParams_io_o_payload_p_v_3[31:0] ), //o
    .io_o_payload_p_v_4  (spanParams_io_o_payload_p_v_4[31:0] ), //o
    .io_o_payload_dx_v_0 (spanParams_io_o_payload_dx_v_0[29:0]), //o
    .io_o_payload_dx_v_1 (spanParams_io_o_payload_dx_v_1[33:0]), //o
    .io_o_payload_dx_v_2 (spanParams_io_o_payload_dx_v_2[23:0]), //o
    .io_o_payload_dx_v_3 (spanParams_io_o_payload_dx_v_3[31:0]), //o
    .io_o_payload_dx_v_4 (spanParams_io_o_payload_dx_v_4[31:0]), //o
    .io_o_payload_attr   (spanParams_io_o_payload_attr[66:0]  ), //o
    .io_idle             (spanParams_io_idle                  ), //o
    .clk                 (clk                                 ), //i
    .reset               (reset                               )  //i
  );
  hng64_raster_StreamFifo_7 io_o_fifo (
    .io_push_valid          (spanParams_io_o_valid                ), //i
    .io_push_ready          (io_o_fifo_io_push_ready              ), //o
    .io_push_payload_x0     (spanParams_io_o_payload_x0[8:0]      ), //i
    .io_push_payload_x1     (spanParams_io_o_payload_x1[8:0]      ), //i
    .io_push_payload_y      (spanParams_io_o_payload_y[8:0]       ), //i
    .io_push_payload_p_v_0  (spanParams_io_o_payload_p_v_0[29:0]  ), //i
    .io_push_payload_p_v_1  (spanParams_io_o_payload_p_v_1[33:0]  ), //i
    .io_push_payload_p_v_2  (spanParams_io_o_payload_p_v_2[23:0]  ), //i
    .io_push_payload_p_v_3  (spanParams_io_o_payload_p_v_3[31:0]  ), //i
    .io_push_payload_p_v_4  (spanParams_io_o_payload_p_v_4[31:0]  ), //i
    .io_push_payload_dx_v_0 (spanParams_io_o_payload_dx_v_0[29:0] ), //i
    .io_push_payload_dx_v_1 (spanParams_io_o_payload_dx_v_1[33:0] ), //i
    .io_push_payload_dx_v_2 (spanParams_io_o_payload_dx_v_2[23:0] ), //i
    .io_push_payload_dx_v_3 (spanParams_io_o_payload_dx_v_3[31:0] ), //i
    .io_push_payload_dx_v_4 (spanParams_io_o_payload_dx_v_4[31:0] ), //i
    .io_push_payload_attr   (spanParams_io_o_payload_attr[66:0]   ), //i
    .io_pop_valid           (io_o_fifo_io_pop_valid               ), //o
    .io_pop_ready           (pixels_io_i_ready                    ), //i
    .io_pop_payload_x0      (io_o_fifo_io_pop_payload_x0[8:0]     ), //o
    .io_pop_payload_x1      (io_o_fifo_io_pop_payload_x1[8:0]     ), //o
    .io_pop_payload_y       (io_o_fifo_io_pop_payload_y[8:0]      ), //o
    .io_pop_payload_p_v_0   (io_o_fifo_io_pop_payload_p_v_0[29:0] ), //o
    .io_pop_payload_p_v_1   (io_o_fifo_io_pop_payload_p_v_1[33:0] ), //o
    .io_pop_payload_p_v_2   (io_o_fifo_io_pop_payload_p_v_2[23:0] ), //o
    .io_pop_payload_p_v_3   (io_o_fifo_io_pop_payload_p_v_3[31:0] ), //o
    .io_pop_payload_p_v_4   (io_o_fifo_io_pop_payload_p_v_4[31:0] ), //o
    .io_pop_payload_dx_v_0  (io_o_fifo_io_pop_payload_dx_v_0[29:0]), //o
    .io_pop_payload_dx_v_1  (io_o_fifo_io_pop_payload_dx_v_1[33:0]), //o
    .io_pop_payload_dx_v_2  (io_o_fifo_io_pop_payload_dx_v_2[23:0]), //o
    .io_pop_payload_dx_v_3  (io_o_fifo_io_pop_payload_dx_v_3[31:0]), //o
    .io_pop_payload_dx_v_4  (io_o_fifo_io_pop_payload_dx_v_4[31:0]), //o
    .io_pop_payload_attr    (io_o_fifo_io_pop_payload_attr[66:0]  ), //o
    .io_flush               (1'b0                                 ), //i
    .io_occupancy           (io_o_fifo_io_occupancy[2:0]          ), //o
    .io_availability        (io_o_fifo_io_availability[2:0]       ), //o
    .clk                    (clk                                  ), //i
    .reset                  (reset                                )  //i
  );
  hng64_raster_StreamMux streamMux (
    .io_select           (streamMux_io_select              ), //i
    .io_inputs_0_valid   (texCache_io_rdAddr_valid         ), //i
    .io_inputs_0_ready   (streamMux_io_inputs_0_ready      ), //o
    .io_inputs_0_payload (texCache_io_rdAddr_payload[27:0] ), //i
    .io_inputs_1_valid   (texBlock_io_rdAddr_valid         ), //i
    .io_inputs_1_ready   (streamMux_io_inputs_1_ready      ), //o
    .io_inputs_1_payload (texBlock_io_rdAddr_payload[27:0] ), //i
    .io_output_valid     (streamMux_io_output_valid        ), //o
    .io_output_ready     (io_texRd_ready                   ), //i
    .io_output_payload   (streamMux_io_output_payload[27:0])  //o
  );
  hng64_raster_StreamMux_1 streamMux_1 (
    .io_select                (streamMux_1_io_select                   ), //i
    .io_inputs_0_valid        (renderBuf_io_wr_valid                   ), //i
    .io_inputs_0_ready        (streamMux_1_io_inputs_0_ready           ), //o
    .io_inputs_0_payload_addr (renderBuf_io_wr_payload_addr[27:0]      ), //i
    .io_inputs_0_payload_data (renderBuf_io_wr_payload_data[63:0]      ), //i
    .io_inputs_0_payload_be   (renderBuf_io_wr_payload_be[7:0]         ), //i
    .io_inputs_1_valid        (texBlock_io_wr_valid                    ), //i
    .io_inputs_1_ready        (streamMux_1_io_inputs_1_ready           ), //o
    .io_inputs_1_payload_addr (texBlock_io_wr_payload_addr[27:0]       ), //i
    .io_inputs_1_payload_data (texBlock_io_wr_payload_data[63:0]       ), //i
    .io_inputs_1_payload_be   (texBlock_io_wr_payload_be[7:0]          ), //i
    .io_output_valid          (streamMux_1_io_output_valid             ), //o
    .io_output_ready          (io_wr_ready                             ), //i
    .io_output_payload_addr   (streamMux_1_io_output_payload_addr[27:0]), //o
    .io_output_payload_data   (streamMux_1_io_output_payload_data[63:0]), //o
    .io_output_payload_be     (streamMux_1_io_output_payload_be[7:0]   )  //o
  );
  always @(*) begin
    io_tri_ready = triIn_ready;
    if(when_Stream_l477) begin
      io_tri_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! triIn_valid);
  assign triIn_valid = io_tri_rValid;
  assign triIn_payload_v_0_0 = io_tri_rData_v_0_0;
  assign triIn_payload_v_0_1 = io_tri_rData_v_0_1;
  assign triIn_payload_v_1_0 = io_tri_rData_v_1_0;
  assign triIn_payload_v_1_1 = io_tri_rData_v_1_1;
  assign triIn_payload_v_2_0 = io_tri_rData_v_2_0;
  assign triIn_payload_v_2_1 = io_tri_rData_v_2_1;
  assign triIn_payload_neg = io_tri_rData_neg;
  assign triIn_payload_p0_v_0 = io_tri_rData_p0_v_0;
  assign triIn_payload_p0_v_1 = io_tri_rData_p0_v_1;
  assign triIn_payload_p0_v_2 = io_tri_rData_p0_v_2;
  assign triIn_payload_p0_v_3 = io_tri_rData_p0_v_3;
  assign triIn_payload_p0_v_4 = io_tri_rData_p0_v_4;
  assign triIn_payload_dx_v_0 = io_tri_rData_dx_v_0;
  assign triIn_payload_dx_v_1 = io_tri_rData_dx_v_1;
  assign triIn_payload_dx_v_2 = io_tri_rData_dx_v_2;
  assign triIn_payload_dx_v_3 = io_tri_rData_dx_v_3;
  assign triIn_payload_dx_v_4 = io_tri_rData_dx_v_4;
  assign triIn_payload_dy_v_0 = io_tri_rData_dy_v_0;
  assign triIn_payload_dy_v_1 = io_tri_rData_dy_v_1;
  assign triIn_payload_dy_v_2 = io_tri_rData_dy_v_2;
  assign triIn_payload_dy_v_3 = io_tri_rData_dy_v_3;
  assign triIn_payload_dy_v_4 = io_tri_rData_dy_v_4;
  assign triIn_payload_attr = io_tri_rData_attr;
  assign triIn_ready = setup_io_i_ready;
  assign walkOut_valid = (walker_io_o_valid || (! io_o_rValidN));
  assign walkOut_payload_x0 = (io_o_rValidN ? walker_io_o_payload_x0 : io_o_rData_x0);
  assign walkOut_payload_x1 = (io_o_rValidN ? walker_io_o_payload_x1 : io_o_rData_x1);
  assign walkOut_payload_y = (io_o_rValidN ? walker_io_o_payload_y : io_o_rData_y);
  assign walkOut_ready = spanParams_io_i_ready;
  assign walker_io_drained = ((spanParams_io_idle && (! walker_io_o_valid)) && (! walkOut_valid));
  assign skid0_valid = (pixels_io_o_valid || (! io_o_rValidN_1));
  assign skid0_payload_x = (io_o_rValidN_1 ? pixels_io_o_payload_x : io_o_rData_x);
  assign skid0_payload_y = (io_o_rValidN_1 ? pixels_io_o_payload_y : io_o_rData_y_1);
  assign skid0_payload_p_v_0 = (io_o_rValidN_1 ? pixels_io_o_payload_p_v_0 : io_o_rData_p_v_0);
  assign skid0_payload_p_v_1 = (io_o_rValidN_1 ? pixels_io_o_payload_p_v_1 : io_o_rData_p_v_1);
  assign skid0_payload_p_v_2 = (io_o_rValidN_1 ? pixels_io_o_payload_p_v_2 : io_o_rData_p_v_2);
  assign skid0_payload_p_v_3 = (io_o_rValidN_1 ? pixels_io_o_payload_p_v_3 : io_o_rData_p_v_3);
  assign skid0_payload_p_v_4 = (io_o_rValidN_1 ? pixels_io_o_payload_p_v_4 : io_o_rData_p_v_4);
  assign skid0_payload_attr = (io_o_rValidN_1 ? pixels_io_o_payload_attr : io_o_rData_attr);
  assign skid0_ready = pixUnit_io_i_ready;
  assign skid1_valid = (pixUnit_io_o_valid || (! io_o_rValidN_2));
  assign skid1_payload_x = (io_o_rValidN_2 ? pixUnit_io_o_payload_x : io_o_rData_x_1);
  assign skid1_payload_y = (io_o_rValidN_2 ? pixUnit_io_o_payload_y : io_o_rData_y_2);
  assign skid1_payload_z = (io_o_rValidN_2 ? pixUnit_io_o_payload_z : io_o_rData_z);
  assign skid1_payload_addr = (io_o_rValidN_2 ? pixUnit_io_o_payload_addr : io_o_rData_addr);
  assign skid1_payload_nib = (io_o_rValidN_2 ? pixUnit_io_o_payload_nib : io_o_rData_nib);
  assign skid1_payload_light = (io_o_rValidN_2 ? pixUnit_io_o_payload_light : io_o_rData_light);
  assign skid1_payload_flat = (io_o_rValidN_2 ? pixUnit_io_o_payload_flat : io_o_rData_flat);
  assign skid1_payload_blend = (io_o_rValidN_2 ? pixUnit_io_o_payload_blend : io_o_rData_blend);
  assign skid1_payload_tex4bpp = (io_o_rValidN_2 ? pixUnit_io_o_payload_tex4bpp : io_o_rData_tex4bpp);
  assign skid1_payload_pal = (io_o_rValidN_2 ? pixUnit_io_o_payload_pal : io_o_rData_pal);
  assign skid1_ready = texCache_io_i_ready;
  assign io_blockDone = texBlock_io_done;
  assign streamMux_io_select = texBlock_io_busy;
  assign io_texRd_valid = streamMux_io_output_valid;
  assign io_texRd_payload = streamMux_io_output_payload;
  assign texCache_io_rdData_valid = (io_texData_valid && (! texBlock_io_busy));
  assign texBlock_io_rdData_valid = (io_texData_valid && texBlock_io_busy);
  assign skid2_valid = (texCache_io_o_valid || (! io_o_rValidN_3));
  assign skid2_payload_f_x = (io_o_rValidN_3 ? texCache_io_o_payload_f_x : io_o_rData_f_x);
  assign skid2_payload_f_y = (io_o_rValidN_3 ? texCache_io_o_payload_f_y : io_o_rData_f_y);
  assign skid2_payload_f_z = (io_o_rValidN_3 ? texCache_io_o_payload_f_z : io_o_rData_f_z);
  assign skid2_payload_f_addr = (io_o_rValidN_3 ? texCache_io_o_payload_f_addr : io_o_rData_f_addr);
  assign skid2_payload_f_nib = (io_o_rValidN_3 ? texCache_io_o_payload_f_nib : io_o_rData_f_nib);
  assign skid2_payload_f_light = (io_o_rValidN_3 ? texCache_io_o_payload_f_light : io_o_rData_f_light);
  assign skid2_payload_f_flat = (io_o_rValidN_3 ? texCache_io_o_payload_f_flat : io_o_rData_f_flat);
  assign skid2_payload_f_blend = (io_o_rValidN_3 ? texCache_io_o_payload_f_blend : io_o_rData_f_blend);
  assign skid2_payload_f_tex4bpp = (io_o_rValidN_3 ? texCache_io_o_payload_f_tex4bpp : io_o_rData_f_tex4bpp);
  assign skid2_payload_f_pal = (io_o_rValidN_3 ? texCache_io_o_payload_f_pal : io_o_rData_f_pal);
  assign skid2_payload_texel = (io_o_rValidN_3 ? texCache_io_o_payload_texel : io_o_rData_texel);
  assign skid2_ready = renderBuf_io_i_ready;
  assign io_depthRd_valid = renderBuf_io_rdAddr_valid;
  assign io_depthRd_payload = renderBuf_io_rdAddr_payload;
  assign streamMux_1_io_select = texBlock_io_busy;
  assign io_wr_valid = streamMux_1_io_output_valid;
  assign io_wr_payload_addr = streamMux_1_io_output_payload_addr;
  assign io_wr_payload_data = streamMux_1_io_output_payload_data;
  assign io_wr_payload_be = streamMux_1_io_output_payload_be;
  assign io_urgent = renderBuf_io_urgent;
  assign io_done = renderBuf_io_done;
  assign io_busy = ((((((((((((io_tri_valid || triIn_valid) || setup_io_o_valid) || walker_io_busy) || walkOut_valid) || (! spanParams_io_idle)) || io_o_fifo_io_pop_valid) || pixels_io_busy) || skid0_valid) || pixUnit_io_busy) || skid1_valid) || texCache_io_busy) || skid2_valid);
  always @(posedge clk) begin
    if(reset) begin
      io_tri_rValid <= 1'b0;
      io_o_rValidN <= 1'b1;
      io_o_rValidN_1 <= 1'b1;
      io_o_rValidN_2 <= 1'b1;
      io_o_rValidN_3 <= 1'b1;
    end else begin
      if(io_tri_ready) begin
        io_tri_rValid <= io_tri_valid;
      end
      if(walker_io_o_valid) begin
        io_o_rValidN <= 1'b0;
      end
      if(walkOut_ready) begin
        io_o_rValidN <= 1'b1;
      end
      if(pixels_io_o_valid) begin
        io_o_rValidN_1 <= 1'b0;
      end
      if(skid0_ready) begin
        io_o_rValidN_1 <= 1'b1;
      end
      if(pixUnit_io_o_valid) begin
        io_o_rValidN_2 <= 1'b0;
      end
      if(skid1_ready) begin
        io_o_rValidN_2 <= 1'b1;
      end
      if(texCache_io_o_valid) begin
        io_o_rValidN_3 <= 1'b0;
      end
      if(skid2_ready) begin
        io_o_rValidN_3 <= 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    if(io_tri_ready) begin
      io_tri_rData_v_0_0 <= io_tri_payload_v_0_0;
      io_tri_rData_v_0_1 <= io_tri_payload_v_0_1;
      io_tri_rData_v_1_0 <= io_tri_payload_v_1_0;
      io_tri_rData_v_1_1 <= io_tri_payload_v_1_1;
      io_tri_rData_v_2_0 <= io_tri_payload_v_2_0;
      io_tri_rData_v_2_1 <= io_tri_payload_v_2_1;
      io_tri_rData_neg <= io_tri_payload_neg;
      io_tri_rData_p0_v_0 <= io_tri_payload_p0_v_0;
      io_tri_rData_p0_v_1 <= io_tri_payload_p0_v_1;
      io_tri_rData_p0_v_2 <= io_tri_payload_p0_v_2;
      io_tri_rData_p0_v_3 <= io_tri_payload_p0_v_3;
      io_tri_rData_p0_v_4 <= io_tri_payload_p0_v_4;
      io_tri_rData_dx_v_0 <= io_tri_payload_dx_v_0;
      io_tri_rData_dx_v_1 <= io_tri_payload_dx_v_1;
      io_tri_rData_dx_v_2 <= io_tri_payload_dx_v_2;
      io_tri_rData_dx_v_3 <= io_tri_payload_dx_v_3;
      io_tri_rData_dx_v_4 <= io_tri_payload_dx_v_4;
      io_tri_rData_dy_v_0 <= io_tri_payload_dy_v_0;
      io_tri_rData_dy_v_1 <= io_tri_payload_dy_v_1;
      io_tri_rData_dy_v_2 <= io_tri_payload_dy_v_2;
      io_tri_rData_dy_v_3 <= io_tri_payload_dy_v_3;
      io_tri_rData_dy_v_4 <= io_tri_payload_dy_v_4;
      io_tri_rData_attr <= io_tri_payload_attr;
    end
    if(io_o_rValidN) begin
      io_o_rData_x0 <= walker_io_o_payload_x0;
      io_o_rData_x1 <= walker_io_o_payload_x1;
      io_o_rData_y <= walker_io_o_payload_y;
    end
    if(io_o_rValidN_1) begin
      io_o_rData_x <= pixels_io_o_payload_x;
      io_o_rData_y_1 <= pixels_io_o_payload_y;
      io_o_rData_p_v_0 <= pixels_io_o_payload_p_v_0;
      io_o_rData_p_v_1 <= pixels_io_o_payload_p_v_1;
      io_o_rData_p_v_2 <= pixels_io_o_payload_p_v_2;
      io_o_rData_p_v_3 <= pixels_io_o_payload_p_v_3;
      io_o_rData_p_v_4 <= pixels_io_o_payload_p_v_4;
      io_o_rData_attr <= pixels_io_o_payload_attr;
    end
    if(io_o_rValidN_2) begin
      io_o_rData_x_1 <= pixUnit_io_o_payload_x;
      io_o_rData_y_2 <= pixUnit_io_o_payload_y;
      io_o_rData_z <= pixUnit_io_o_payload_z;
      io_o_rData_addr <= pixUnit_io_o_payload_addr;
      io_o_rData_nib <= pixUnit_io_o_payload_nib;
      io_o_rData_light <= pixUnit_io_o_payload_light;
      io_o_rData_flat <= pixUnit_io_o_payload_flat;
      io_o_rData_blend <= pixUnit_io_o_payload_blend;
      io_o_rData_tex4bpp <= pixUnit_io_o_payload_tex4bpp;
      io_o_rData_pal <= pixUnit_io_o_payload_pal;
    end
    if(io_o_rValidN_3) begin
      io_o_rData_f_x <= texCache_io_o_payload_f_x;
      io_o_rData_f_y <= texCache_io_o_payload_f_y;
      io_o_rData_f_z <= texCache_io_o_payload_f_z;
      io_o_rData_f_addr <= texCache_io_o_payload_f_addr;
      io_o_rData_f_nib <= texCache_io_o_payload_f_nib;
      io_o_rData_f_light <= texCache_io_o_payload_f_light;
      io_o_rData_f_flat <= texCache_io_o_payload_f_flat;
      io_o_rData_f_blend <= texCache_io_o_payload_f_blend;
      io_o_rData_f_tex4bpp <= texCache_io_o_payload_f_tex4bpp;
      io_o_rData_f_pal <= texCache_io_o_payload_f_pal;
      io_o_rData_texel <= texCache_io_o_payload_texel;
    end
  end


endmodule

module hng64_raster_StreamMux_1 (
  input  wire [0:0]    io_select,
  input  wire          io_inputs_0_valid,
  output wire          io_inputs_0_ready,
  input  wire [27:0]   io_inputs_0_payload_addr,
  input  wire [63:0]   io_inputs_0_payload_data,
  input  wire [7:0]    io_inputs_0_payload_be,
  input  wire          io_inputs_1_valid,
  output wire          io_inputs_1_ready,
  input  wire [27:0]   io_inputs_1_payload_addr,
  input  wire [63:0]   io_inputs_1_payload_data,
  input  wire [7:0]    io_inputs_1_payload_be,
  output wire          io_output_valid,
  input  wire          io_output_ready,
  output wire [27:0]   io_output_payload_addr,
  output wire [63:0]   io_output_payload_data,
  output wire [7:0]    io_output_payload_be
);

  reg                 _zz_io_output_valid;
  reg        [27:0]   _zz_io_output_payload_addr;
  reg        [63:0]   _zz_io_output_payload_data;
  reg        [7:0]    _zz_io_output_payload_be;

  always @(*) begin
    case(io_select)
      1'b0 : begin
        _zz_io_output_valid = io_inputs_0_valid;
        _zz_io_output_payload_addr = io_inputs_0_payload_addr;
        _zz_io_output_payload_data = io_inputs_0_payload_data;
        _zz_io_output_payload_be = io_inputs_0_payload_be;
      end
      default : begin
        _zz_io_output_valid = io_inputs_1_valid;
        _zz_io_output_payload_addr = io_inputs_1_payload_addr;
        _zz_io_output_payload_data = io_inputs_1_payload_data;
        _zz_io_output_payload_be = io_inputs_1_payload_be;
      end
    endcase
  end

  assign io_inputs_0_ready = ((io_select == 1'b0) && io_output_ready);
  assign io_inputs_1_ready = ((io_select == 1'b1) && io_output_ready);
  assign io_output_valid = _zz_io_output_valid;
  assign io_output_payload_addr = _zz_io_output_payload_addr;
  assign io_output_payload_data = _zz_io_output_payload_data;
  assign io_output_payload_be = _zz_io_output_payload_be;

endmodule

module hng64_raster_StreamMux (
  input  wire [0:0]    io_select,
  input  wire          io_inputs_0_valid,
  output wire          io_inputs_0_ready,
  input  wire [27:0]   io_inputs_0_payload,
  input  wire          io_inputs_1_valid,
  output wire          io_inputs_1_ready,
  input  wire [27:0]   io_inputs_1_payload,
  output wire          io_output_valid,
  input  wire          io_output_ready,
  output wire [27:0]   io_output_payload
);

  reg                 _zz_io_output_valid;
  reg        [27:0]   _zz_io_output_payload;

  always @(*) begin
    case(io_select)
      1'b0 : begin
        _zz_io_output_valid = io_inputs_0_valid;
        _zz_io_output_payload = io_inputs_0_payload;
      end
      default : begin
        _zz_io_output_valid = io_inputs_1_valid;
        _zz_io_output_payload = io_inputs_1_payload;
      end
    endcase
  end

  assign io_inputs_0_ready = ((io_select == 1'b0) && io_output_ready);
  assign io_inputs_1_ready = ((io_select == 1'b1) && io_output_ready);
  assign io_output_valid = _zz_io_output_valid;
  assign io_output_payload = _zz_io_output_payload;

endmodule

module hng64_raster_StreamFifo_7 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [8:0]    io_push_payload_x0,
  input  wire [8:0]    io_push_payload_x1,
  input  wire [8:0]    io_push_payload_y,
  input  wire [29:0]   io_push_payload_p_v_0,
  input  wire [33:0]   io_push_payload_p_v_1,
  input  wire [23:0]   io_push_payload_p_v_2,
  input  wire [31:0]   io_push_payload_p_v_3,
  input  wire [31:0]   io_push_payload_p_v_4,
  input  wire [29:0]   io_push_payload_dx_v_0,
  input  wire [33:0]   io_push_payload_dx_v_1,
  input  wire [23:0]   io_push_payload_dx_v_2,
  input  wire [31:0]   io_push_payload_dx_v_3,
  input  wire [31:0]   io_push_payload_dx_v_4,
  input  wire [66:0]   io_push_payload_attr,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [8:0]    io_pop_payload_x0,
  output wire [8:0]    io_pop_payload_x1,
  output wire [8:0]    io_pop_payload_y,
  output wire [29:0]   io_pop_payload_p_v_0,
  output wire [33:0]   io_pop_payload_p_v_1,
  output wire [23:0]   io_pop_payload_p_v_2,
  output wire [31:0]   io_pop_payload_p_v_3,
  output wire [31:0]   io_pop_payload_p_v_4,
  output wire [29:0]   io_pop_payload_dx_v_0,
  output wire [33:0]   io_pop_payload_dx_v_1,
  output wire [23:0]   io_pop_payload_dx_v_2,
  output wire [31:0]   io_pop_payload_dx_v_3,
  output wire [31:0]   io_pop_payload_dx_v_4,
  output wire [66:0]   io_pop_payload_attr,
  input  wire          io_flush,
  output wire [2:0]    io_occupancy,
  output wire [2:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [397:0]  logic_ram_spinal_port1;
  wire       [397:0]  _zz_logic_ram_port;
  wire       [151:0]  _zz__zz_logic_pop_sync_readPort_rsp_p_v_0;
  wire       [151:0]  _zz__zz_logic_pop_sync_readPort_rsp_dx_v_0;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [2:0]    logic_ptr_push;
  reg        [2:0]    logic_ptr_pop;
  wire       [2:0]    logic_ptr_occupancy;
  wire       [2:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [1:0]    logic_push_onRam_write_payload_address;
  wire       [8:0]    logic_push_onRam_write_payload_data_x0;
  wire       [8:0]    logic_push_onRam_write_payload_data_x1;
  wire       [8:0]    logic_push_onRam_write_payload_data_y;
  wire       [29:0]   logic_push_onRam_write_payload_data_p_v_0;
  wire       [33:0]   logic_push_onRam_write_payload_data_p_v_1;
  wire       [23:0]   logic_push_onRam_write_payload_data_p_v_2;
  wire       [31:0]   logic_push_onRam_write_payload_data_p_v_3;
  wire       [31:0]   logic_push_onRam_write_payload_data_p_v_4;
  wire       [29:0]   logic_push_onRam_write_payload_data_dx_v_0;
  wire       [33:0]   logic_push_onRam_write_payload_data_dx_v_1;
  wire       [23:0]   logic_push_onRam_write_payload_data_dx_v_2;
  wire       [31:0]   logic_push_onRam_write_payload_data_dx_v_3;
  wire       [31:0]   logic_push_onRam_write_payload_data_dx_v_4;
  wire       [66:0]   logic_push_onRam_write_payload_data_attr;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [1:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [1:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [1:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [1:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [8:0]    logic_pop_sync_readPort_rsp_x0;
  wire       [8:0]    logic_pop_sync_readPort_rsp_x1;
  wire       [8:0]    logic_pop_sync_readPort_rsp_y;
  wire       [29:0]   logic_pop_sync_readPort_rsp_p_v_0;
  wire       [33:0]   logic_pop_sync_readPort_rsp_p_v_1;
  wire       [23:0]   logic_pop_sync_readPort_rsp_p_v_2;
  wire       [31:0]   logic_pop_sync_readPort_rsp_p_v_3;
  wire       [31:0]   logic_pop_sync_readPort_rsp_p_v_4;
  wire       [29:0]   logic_pop_sync_readPort_rsp_dx_v_0;
  wire       [33:0]   logic_pop_sync_readPort_rsp_dx_v_1;
  wire       [23:0]   logic_pop_sync_readPort_rsp_dx_v_2;
  wire       [31:0]   logic_pop_sync_readPort_rsp_dx_v_3;
  wire       [31:0]   logic_pop_sync_readPort_rsp_dx_v_4;
  wire       [66:0]   logic_pop_sync_readPort_rsp_attr;
  wire       [397:0]  _zz_logic_pop_sync_readPort_rsp_x0;
  wire       [151:0]  _zz_logic_pop_sync_readPort_rsp_p_v_0;
  wire       [151:0]  _zz_logic_pop_sync_readPort_rsp_dx_v_0;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [1:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_x0;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_x1;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_y;
  wire       [29:0]   logic_pop_sync_readArbitation_translated_payload_p_v_0;
  wire       [33:0]   logic_pop_sync_readArbitation_translated_payload_p_v_1;
  wire       [23:0]   logic_pop_sync_readArbitation_translated_payload_p_v_2;
  wire       [31:0]   logic_pop_sync_readArbitation_translated_payload_p_v_3;
  wire       [31:0]   logic_pop_sync_readArbitation_translated_payload_p_v_4;
  wire       [29:0]   logic_pop_sync_readArbitation_translated_payload_dx_v_0;
  wire       [33:0]   logic_pop_sync_readArbitation_translated_payload_dx_v_1;
  wire       [23:0]   logic_pop_sync_readArbitation_translated_payload_dx_v_2;
  wire       [31:0]   logic_pop_sync_readArbitation_translated_payload_dx_v_3;
  wire       [31:0]   logic_pop_sync_readArbitation_translated_payload_dx_v_4;
  wire       [66:0]   logic_pop_sync_readArbitation_translated_payload_attr;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [2:0]    logic_pop_sync_popReg;
  reg [397:0] logic_ram [0:3];

  assign _zz__zz_logic_pop_sync_readPort_rsp_p_v_0 = _zz_logic_pop_sync_readPort_rsp_x0[178 : 27];
  assign _zz__zz_logic_pop_sync_readPort_rsp_dx_v_0 = _zz_logic_pop_sync_readPort_rsp_x0[330 : 179];
  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_attr,{{logic_push_onRam_write_payload_data_dx_v_4,{logic_push_onRam_write_payload_data_dx_v_3,{logic_push_onRam_write_payload_data_dx_v_2,{logic_push_onRam_write_payload_data_dx_v_1,logic_push_onRam_write_payload_data_dx_v_0}}}},{{logic_push_onRam_write_payload_data_p_v_4,{logic_push_onRam_write_payload_data_p_v_3,{logic_push_onRam_write_payload_data_p_v_2,{logic_push_onRam_write_payload_data_p_v_1,logic_push_onRam_write_payload_data_p_v_0}}}},{logic_push_onRam_write_payload_data_y,{logic_push_onRam_write_payload_data_x1,logic_push_onRam_write_payload_data_x0}}}}};
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 3'b100) == 3'b000);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[1:0];
  assign logic_push_onRam_write_payload_data_x0 = io_push_payload_x0;
  assign logic_push_onRam_write_payload_data_x1 = io_push_payload_x1;
  assign logic_push_onRam_write_payload_data_y = io_push_payload_y;
  assign logic_push_onRam_write_payload_data_p_v_0 = io_push_payload_p_v_0;
  assign logic_push_onRam_write_payload_data_p_v_1 = io_push_payload_p_v_1;
  assign logic_push_onRam_write_payload_data_p_v_2 = io_push_payload_p_v_2;
  assign logic_push_onRam_write_payload_data_p_v_3 = io_push_payload_p_v_3;
  assign logic_push_onRam_write_payload_data_p_v_4 = io_push_payload_p_v_4;
  assign logic_push_onRam_write_payload_data_dx_v_0 = io_push_payload_dx_v_0;
  assign logic_push_onRam_write_payload_data_dx_v_1 = io_push_payload_dx_v_1;
  assign logic_push_onRam_write_payload_data_dx_v_2 = io_push_payload_dx_v_2;
  assign logic_push_onRam_write_payload_data_dx_v_3 = io_push_payload_dx_v_3;
  assign logic_push_onRam_write_payload_data_dx_v_4 = io_push_payload_dx_v_4;
  assign logic_push_onRam_write_payload_data_attr = io_push_payload_attr;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[1:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign _zz_logic_pop_sync_readPort_rsp_x0 = logic_ram_spinal_port1;
  assign _zz_logic_pop_sync_readPort_rsp_p_v_0 = _zz__zz_logic_pop_sync_readPort_rsp_p_v_0[151 : 0];
  assign _zz_logic_pop_sync_readPort_rsp_dx_v_0 = _zz__zz_logic_pop_sync_readPort_rsp_dx_v_0[151 : 0];
  assign logic_pop_sync_readPort_rsp_x0 = _zz_logic_pop_sync_readPort_rsp_x0[8 : 0];
  assign logic_pop_sync_readPort_rsp_x1 = _zz_logic_pop_sync_readPort_rsp_x0[17 : 9];
  assign logic_pop_sync_readPort_rsp_y = _zz_logic_pop_sync_readPort_rsp_x0[26 : 18];
  assign logic_pop_sync_readPort_rsp_p_v_0 = _zz_logic_pop_sync_readPort_rsp_p_v_0[29 : 0];
  assign logic_pop_sync_readPort_rsp_p_v_1 = _zz_logic_pop_sync_readPort_rsp_p_v_0[63 : 30];
  assign logic_pop_sync_readPort_rsp_p_v_2 = _zz_logic_pop_sync_readPort_rsp_p_v_0[87 : 64];
  assign logic_pop_sync_readPort_rsp_p_v_3 = _zz_logic_pop_sync_readPort_rsp_p_v_0[119 : 88];
  assign logic_pop_sync_readPort_rsp_p_v_4 = _zz_logic_pop_sync_readPort_rsp_p_v_0[151 : 120];
  assign logic_pop_sync_readPort_rsp_dx_v_0 = _zz_logic_pop_sync_readPort_rsp_dx_v_0[29 : 0];
  assign logic_pop_sync_readPort_rsp_dx_v_1 = _zz_logic_pop_sync_readPort_rsp_dx_v_0[63 : 30];
  assign logic_pop_sync_readPort_rsp_dx_v_2 = _zz_logic_pop_sync_readPort_rsp_dx_v_0[87 : 64];
  assign logic_pop_sync_readPort_rsp_dx_v_3 = _zz_logic_pop_sync_readPort_rsp_dx_v_0[119 : 88];
  assign logic_pop_sync_readPort_rsp_dx_v_4 = _zz_logic_pop_sync_readPort_rsp_dx_v_0[151 : 120];
  assign logic_pop_sync_readPort_rsp_attr = _zz_logic_pop_sync_readPort_rsp_x0[397 : 331];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_x0 = logic_pop_sync_readPort_rsp_x0;
  assign logic_pop_sync_readArbitation_translated_payload_x1 = logic_pop_sync_readPort_rsp_x1;
  assign logic_pop_sync_readArbitation_translated_payload_y = logic_pop_sync_readPort_rsp_y;
  assign logic_pop_sync_readArbitation_translated_payload_p_v_0 = logic_pop_sync_readPort_rsp_p_v_0;
  assign logic_pop_sync_readArbitation_translated_payload_p_v_1 = logic_pop_sync_readPort_rsp_p_v_1;
  assign logic_pop_sync_readArbitation_translated_payload_p_v_2 = logic_pop_sync_readPort_rsp_p_v_2;
  assign logic_pop_sync_readArbitation_translated_payload_p_v_3 = logic_pop_sync_readPort_rsp_p_v_3;
  assign logic_pop_sync_readArbitation_translated_payload_p_v_4 = logic_pop_sync_readPort_rsp_p_v_4;
  assign logic_pop_sync_readArbitation_translated_payload_dx_v_0 = logic_pop_sync_readPort_rsp_dx_v_0;
  assign logic_pop_sync_readArbitation_translated_payload_dx_v_1 = logic_pop_sync_readPort_rsp_dx_v_1;
  assign logic_pop_sync_readArbitation_translated_payload_dx_v_2 = logic_pop_sync_readPort_rsp_dx_v_2;
  assign logic_pop_sync_readArbitation_translated_payload_dx_v_3 = logic_pop_sync_readPort_rsp_dx_v_3;
  assign logic_pop_sync_readArbitation_translated_payload_dx_v_4 = logic_pop_sync_readPort_rsp_dx_v_4;
  assign logic_pop_sync_readArbitation_translated_payload_attr = logic_pop_sync_readPort_rsp_attr;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_x0 = logic_pop_sync_readArbitation_translated_payload_x0;
  assign io_pop_payload_x1 = logic_pop_sync_readArbitation_translated_payload_x1;
  assign io_pop_payload_y = logic_pop_sync_readArbitation_translated_payload_y;
  assign io_pop_payload_p_v_0 = logic_pop_sync_readArbitation_translated_payload_p_v_0;
  assign io_pop_payload_p_v_1 = logic_pop_sync_readArbitation_translated_payload_p_v_1;
  assign io_pop_payload_p_v_2 = logic_pop_sync_readArbitation_translated_payload_p_v_2;
  assign io_pop_payload_p_v_3 = logic_pop_sync_readArbitation_translated_payload_p_v_3;
  assign io_pop_payload_p_v_4 = logic_pop_sync_readArbitation_translated_payload_p_v_4;
  assign io_pop_payload_dx_v_0 = logic_pop_sync_readArbitation_translated_payload_dx_v_0;
  assign io_pop_payload_dx_v_1 = logic_pop_sync_readArbitation_translated_payload_dx_v_1;
  assign io_pop_payload_dx_v_2 = logic_pop_sync_readArbitation_translated_payload_dx_v_2;
  assign io_pop_payload_dx_v_3 = logic_pop_sync_readArbitation_translated_payload_dx_v_3;
  assign io_pop_payload_dx_v_4 = logic_pop_sync_readArbitation_translated_payload_dx_v_4;
  assign io_pop_payload_attr = logic_pop_sync_readArbitation_translated_payload_attr;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (3'b100 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 3'b000;
      logic_ptr_pop <= 3'b000;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 3'b000;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 3'b001);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 3'b001);
      end
      if(io_flush) begin
        logic_ptr_push <= 3'b000;
        logic_ptr_pop <= 3'b000;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 3'b000;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_SpanParams (
  input  wire          io_i_valid,
  output wire          io_i_ready,
  input  wire [8:0]    io_i_payload_x0,
  input  wire [8:0]    io_i_payload_x1,
  input  wire [8:0]    io_i_payload_y,
  input  wire [12:0]   io_tri_x0,
  input  wire [12:0]   io_tri_x1,
  input  wire [12:0]   io_tri_y0,
  input  wire [12:0]   io_tri_y1,
  input  wire [24:0]   io_tri_a_0,
  input  wire [24:0]   io_tri_a_1,
  input  wire [24:0]   io_tri_a_2,
  input  wire [24:0]   io_tri_b_0,
  input  wire [24:0]   io_tri_b_1,
  input  wire [24:0]   io_tri_b_2,
  input  wire [50:0]   io_tri_edge_0,
  input  wire [50:0]   io_tri_edge_1,
  input  wire [50:0]   io_tri_edge_2,
  input  wire [29:0]   io_tri_p_v_0,
  input  wire [33:0]   io_tri_p_v_1,
  input  wire [23:0]   io_tri_p_v_2,
  input  wire [31:0]   io_tri_p_v_3,
  input  wire [31:0]   io_tri_p_v_4,
  input  wire [29:0]   io_tri_dx_v_0,
  input  wire [33:0]   io_tri_dx_v_1,
  input  wire [23:0]   io_tri_dx_v_2,
  input  wire [31:0]   io_tri_dx_v_3,
  input  wire [31:0]   io_tri_dx_v_4,
  input  wire [29:0]   io_tri_dy_v_0,
  input  wire [33:0]   io_tri_dy_v_1,
  input  wire [23:0]   io_tri_dy_v_2,
  input  wire [31:0]   io_tri_dy_v_3,
  input  wire [31:0]   io_tri_dy_v_4,
  input  wire [66:0]   io_tri_attr,
  output wire          io_o_valid,
  input  wire          io_o_ready,
  output wire [8:0]    io_o_payload_x0,
  output wire [8:0]    io_o_payload_x1,
  output wire [8:0]    io_o_payload_y,
  output wire [29:0]   io_o_payload_p_v_0,
  output wire [33:0]   io_o_payload_p_v_1,
  output wire [23:0]   io_o_payload_p_v_2,
  output wire [31:0]   io_o_payload_p_v_3,
  output wire [31:0]   io_o_payload_p_v_4,
  output wire [29:0]   io_o_payload_dx_v_0,
  output wire [33:0]   io_o_payload_dx_v_1,
  output wire [23:0]   io_o_payload_dx_v_2,
  output wire [31:0]   io_o_payload_dx_v_3,
  output wire [31:0]   io_o_payload_dx_v_4,
  output wire [66:0]   io_o_payload_attr,
  output wire          io_idle,
  input  wire          clk,
  input  wire          reset
);

  wire       [13:0]   _zz_io_i_map_payload_ox;
  wire       [13:0]   _zz_io_i_map_payload_ox_1;
  wire       [13:0]   _zz_io_i_map_payload_ox_2;
  wire       [13:0]   _zz_io_i_map_payload_oy;
  wire       [13:0]   _zz_io_i_map_payload_oy_1;
  wire       [13:0]   _zz_io_i_map_payload_oy_2;
  wire       [43:0]   _zz_a_map_payload_px_v_0;
  wire       [47:0]   _zz_a_map_payload_px_v_1;
  wire       [37:0]   _zz_a_map_payload_px_v_2;
  wire       [45:0]   _zz_a_map_payload_px_v_3;
  wire       [45:0]   _zz_a_map_payload_px_v_4;
  wire       [43:0]   _zz_a_map_payload_py_v_0;
  wire       [47:0]   _zz_a_map_payload_py_v_1;
  wire       [37:0]   _zz_a_map_payload_py_v_2;
  wire       [45:0]   _zz_a_map_payload_py_v_3;
  wire       [45:0]   _zz_a_map_payload_py_v_4;
  wire       [29:0]   _zz_b_map_payload_p_v_0;
  wire       [33:0]   _zz_b_map_payload_p_v_1;
  wire       [23:0]   _zz_b_map_payload_p_v_2;
  wire       [31:0]   _zz_b_map_payload_p_v_3;
  wire       [31:0]   _zz_b_map_payload_p_v_4;
  wire                io_i_map_valid;
  reg                 io_i_map_ready;
  wire       [8:0]    io_i_map_payload_w_x0;
  wire       [8:0]    io_i_map_payload_w_x1;
  wire       [8:0]    io_i_map_payload_w_y;
  wire       [13:0]   io_i_map_payload_ox;
  wire       [13:0]   io_i_map_payload_oy;
  wire                a_valid;
  wire                a_ready;
  wire       [8:0]    a_payload_w_x0;
  wire       [8:0]    a_payload_w_x1;
  wire       [8:0]    a_payload_w_y;
  wire       [13:0]   a_payload_ox;
  wire       [13:0]   a_payload_oy;
  reg                 io_i_map_rValid;
  reg        [8:0]    io_i_map_rData_w_x0;
  reg        [8:0]    io_i_map_rData_w_x1;
  reg        [8:0]    io_i_map_rData_w_y;
  reg        [13:0]   io_i_map_rData_ox;
  reg        [13:0]   io_i_map_rData_oy;
  wire                when_Stream_l477;
  wire                a_map_valid;
  reg                 a_map_ready;
  wire       [8:0]    a_map_payload_w_x0;
  wire       [8:0]    a_map_payload_w_x1;
  wire       [8:0]    a_map_payload_w_y;
  wire       [29:0]   a_map_payload_px_v_0;
  wire       [33:0]   a_map_payload_px_v_1;
  wire       [23:0]   a_map_payload_px_v_2;
  wire       [31:0]   a_map_payload_px_v_3;
  wire       [31:0]   a_map_payload_px_v_4;
  wire       [29:0]   a_map_payload_py_v_0;
  wire       [33:0]   a_map_payload_py_v_1;
  wire       [23:0]   a_map_payload_py_v_2;
  wire       [31:0]   a_map_payload_py_v_3;
  wire       [31:0]   a_map_payload_py_v_4;
  wire                b_valid;
  wire                b_ready;
  wire       [8:0]    b_payload_w_x0;
  wire       [8:0]    b_payload_w_x1;
  wire       [8:0]    b_payload_w_y;
  wire       [29:0]   b_payload_px_v_0;
  wire       [33:0]   b_payload_px_v_1;
  wire       [23:0]   b_payload_px_v_2;
  wire       [31:0]   b_payload_px_v_3;
  wire       [31:0]   b_payload_px_v_4;
  wire       [29:0]   b_payload_py_v_0;
  wire       [33:0]   b_payload_py_v_1;
  wire       [23:0]   b_payload_py_v_2;
  wire       [31:0]   b_payload_py_v_3;
  wire       [31:0]   b_payload_py_v_4;
  reg                 a_map_rValid;
  reg        [8:0]    a_map_rData_w_x0;
  reg        [8:0]    a_map_rData_w_x1;
  reg        [8:0]    a_map_rData_w_y;
  reg        [29:0]   a_map_rData_px_v_0;
  reg        [33:0]   a_map_rData_px_v_1;
  reg        [23:0]   a_map_rData_px_v_2;
  reg        [31:0]   a_map_rData_px_v_3;
  reg        [31:0]   a_map_rData_px_v_4;
  reg        [29:0]   a_map_rData_py_v_0;
  reg        [33:0]   a_map_rData_py_v_1;
  reg        [23:0]   a_map_rData_py_v_2;
  reg        [31:0]   a_map_rData_py_v_3;
  reg        [31:0]   a_map_rData_py_v_4;
  wire                when_Stream_l477_1;
  wire                b_map_valid;
  reg                 b_map_ready;
  wire       [8:0]    b_map_payload_x0;
  wire       [8:0]    b_map_payload_x1;
  wire       [8:0]    b_map_payload_y;
  wire       [29:0]   b_map_payload_p_v_0;
  wire       [33:0]   b_map_payload_p_v_1;
  wire       [23:0]   b_map_payload_p_v_2;
  wire       [31:0]   b_map_payload_p_v_3;
  wire       [31:0]   b_map_payload_p_v_4;
  wire       [29:0]   b_map_payload_dx_v_0;
  wire       [33:0]   b_map_payload_dx_v_1;
  wire       [23:0]   b_map_payload_dx_v_2;
  wire       [31:0]   b_map_payload_dx_v_3;
  wire       [31:0]   b_map_payload_dx_v_4;
  wire       [66:0]   b_map_payload_attr;
  wire                f_valid;
  wire                f_ready;
  wire       [8:0]    f_payload_x0;
  wire       [8:0]    f_payload_x1;
  wire       [8:0]    f_payload_y;
  wire       [29:0]   f_payload_p_v_0;
  wire       [33:0]   f_payload_p_v_1;
  wire       [23:0]   f_payload_p_v_2;
  wire       [31:0]   f_payload_p_v_3;
  wire       [31:0]   f_payload_p_v_4;
  wire       [29:0]   f_payload_dx_v_0;
  wire       [33:0]   f_payload_dx_v_1;
  wire       [23:0]   f_payload_dx_v_2;
  wire       [31:0]   f_payload_dx_v_3;
  wire       [31:0]   f_payload_dx_v_4;
  wire       [66:0]   f_payload_attr;
  reg                 b_map_rValid;
  reg        [8:0]    b_map_rData_x0;
  reg        [8:0]    b_map_rData_x1;
  reg        [8:0]    b_map_rData_y;
  reg        [29:0]   b_map_rData_p_v_0;
  reg        [33:0]   b_map_rData_p_v_1;
  reg        [23:0]   b_map_rData_p_v_2;
  reg        [31:0]   b_map_rData_p_v_3;
  reg        [31:0]   b_map_rData_p_v_4;
  reg        [29:0]   b_map_rData_dx_v_0;
  reg        [33:0]   b_map_rData_dx_v_1;
  reg        [23:0]   b_map_rData_dx_v_2;
  reg        [31:0]   b_map_rData_dx_v_3;
  reg        [31:0]   b_map_rData_dx_v_4;
  reg        [66:0]   b_map_rData_attr;
  wire                when_Stream_l477_2;

  assign _zz_io_i_map_payload_ox = _zz_io_i_map_payload_ox_1;
  assign _zz_io_i_map_payload_ox_1 = {5'd0, io_i_payload_x0};
  assign _zz_io_i_map_payload_ox_2 = {{1{io_tri_x0[12]}}, io_tri_x0};
  assign _zz_io_i_map_payload_oy = _zz_io_i_map_payload_oy_1;
  assign _zz_io_i_map_payload_oy_1 = {5'd0, io_i_payload_y};
  assign _zz_io_i_map_payload_oy_2 = {{1{io_tri_y0[12]}}, io_tri_y0};
  assign _zz_a_map_payload_px_v_0 = ($signed(a_payload_ox) * $signed(io_tri_dx_v_0));
  assign _zz_a_map_payload_px_v_1 = ($signed(a_payload_ox) * $signed(io_tri_dx_v_1));
  assign _zz_a_map_payload_px_v_2 = ($signed(a_payload_ox) * $signed(io_tri_dx_v_2));
  assign _zz_a_map_payload_px_v_3 = ($signed(a_payload_ox) * $signed(io_tri_dx_v_3));
  assign _zz_a_map_payload_px_v_4 = ($signed(a_payload_ox) * $signed(io_tri_dx_v_4));
  assign _zz_a_map_payload_py_v_0 = ($signed(a_payload_oy) * $signed(io_tri_dy_v_0));
  assign _zz_a_map_payload_py_v_1 = ($signed(a_payload_oy) * $signed(io_tri_dy_v_1));
  assign _zz_a_map_payload_py_v_2 = ($signed(a_payload_oy) * $signed(io_tri_dy_v_2));
  assign _zz_a_map_payload_py_v_3 = ($signed(a_payload_oy) * $signed(io_tri_dy_v_3));
  assign _zz_a_map_payload_py_v_4 = ($signed(a_payload_oy) * $signed(io_tri_dy_v_4));
  assign _zz_b_map_payload_p_v_0 = ($signed(io_tri_p_v_0) + $signed(b_payload_px_v_0));
  assign _zz_b_map_payload_p_v_1 = ($signed(io_tri_p_v_1) + $signed(b_payload_px_v_1));
  assign _zz_b_map_payload_p_v_2 = ($signed(io_tri_p_v_2) + $signed(b_payload_px_v_2));
  assign _zz_b_map_payload_p_v_3 = ($signed(io_tri_p_v_3) + $signed(b_payload_px_v_3));
  assign _zz_b_map_payload_p_v_4 = ($signed(io_tri_p_v_4) + $signed(b_payload_px_v_4));
  assign io_i_map_valid = io_i_valid;
  assign io_i_ready = io_i_map_ready;
  assign io_i_map_payload_w_x0 = io_i_payload_x0;
  assign io_i_map_payload_w_x1 = io_i_payload_x1;
  assign io_i_map_payload_w_y = io_i_payload_y;
  assign io_i_map_payload_ox = ($signed(_zz_io_i_map_payload_ox) - $signed(_zz_io_i_map_payload_ox_2));
  assign io_i_map_payload_oy = ($signed(_zz_io_i_map_payload_oy) - $signed(_zz_io_i_map_payload_oy_2));
  always @(*) begin
    io_i_map_ready = a_ready;
    if(when_Stream_l477) begin
      io_i_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! a_valid);
  assign a_valid = io_i_map_rValid;
  assign a_payload_w_x0 = io_i_map_rData_w_x0;
  assign a_payload_w_x1 = io_i_map_rData_w_x1;
  assign a_payload_w_y = io_i_map_rData_w_y;
  assign a_payload_ox = io_i_map_rData_ox;
  assign a_payload_oy = io_i_map_rData_oy;
  assign a_map_valid = a_valid;
  assign a_ready = a_map_ready;
  assign a_map_payload_w_x0 = a_payload_w_x0;
  assign a_map_payload_w_x1 = a_payload_w_x1;
  assign a_map_payload_w_y = a_payload_w_y;
  assign a_map_payload_px_v_0 = _zz_a_map_payload_px_v_0[29:0];
  assign a_map_payload_px_v_1 = _zz_a_map_payload_px_v_1[33:0];
  assign a_map_payload_px_v_2 = _zz_a_map_payload_px_v_2[23:0];
  assign a_map_payload_px_v_3 = _zz_a_map_payload_px_v_3[31:0];
  assign a_map_payload_px_v_4 = _zz_a_map_payload_px_v_4[31:0];
  assign a_map_payload_py_v_0 = _zz_a_map_payload_py_v_0[29:0];
  assign a_map_payload_py_v_1 = _zz_a_map_payload_py_v_1[33:0];
  assign a_map_payload_py_v_2 = _zz_a_map_payload_py_v_2[23:0];
  assign a_map_payload_py_v_3 = _zz_a_map_payload_py_v_3[31:0];
  assign a_map_payload_py_v_4 = _zz_a_map_payload_py_v_4[31:0];
  always @(*) begin
    a_map_ready = b_ready;
    if(when_Stream_l477_1) begin
      a_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! b_valid);
  assign b_valid = a_map_rValid;
  assign b_payload_w_x0 = a_map_rData_w_x0;
  assign b_payload_w_x1 = a_map_rData_w_x1;
  assign b_payload_w_y = a_map_rData_w_y;
  assign b_payload_px_v_0 = a_map_rData_px_v_0;
  assign b_payload_px_v_1 = a_map_rData_px_v_1;
  assign b_payload_px_v_2 = a_map_rData_px_v_2;
  assign b_payload_px_v_3 = a_map_rData_px_v_3;
  assign b_payload_px_v_4 = a_map_rData_px_v_4;
  assign b_payload_py_v_0 = a_map_rData_py_v_0;
  assign b_payload_py_v_1 = a_map_rData_py_v_1;
  assign b_payload_py_v_2 = a_map_rData_py_v_2;
  assign b_payload_py_v_3 = a_map_rData_py_v_3;
  assign b_payload_py_v_4 = a_map_rData_py_v_4;
  assign b_map_valid = b_valid;
  assign b_ready = b_map_ready;
  assign b_map_payload_x0 = b_payload_w_x0;
  assign b_map_payload_x1 = b_payload_w_x1;
  assign b_map_payload_y = b_payload_w_y;
  assign b_map_payload_p_v_0 = ($signed(_zz_b_map_payload_p_v_0) + $signed(b_payload_py_v_0));
  assign b_map_payload_p_v_1 = ($signed(_zz_b_map_payload_p_v_1) + $signed(b_payload_py_v_1));
  assign b_map_payload_p_v_2 = ($signed(_zz_b_map_payload_p_v_2) + $signed(b_payload_py_v_2));
  assign b_map_payload_p_v_3 = ($signed(_zz_b_map_payload_p_v_3) + $signed(b_payload_py_v_3));
  assign b_map_payload_p_v_4 = ($signed(_zz_b_map_payload_p_v_4) + $signed(b_payload_py_v_4));
  assign b_map_payload_dx_v_0 = io_tri_dx_v_0;
  assign b_map_payload_dx_v_1 = io_tri_dx_v_1;
  assign b_map_payload_dx_v_2 = io_tri_dx_v_2;
  assign b_map_payload_dx_v_3 = io_tri_dx_v_3;
  assign b_map_payload_dx_v_4 = io_tri_dx_v_4;
  assign b_map_payload_attr = io_tri_attr;
  always @(*) begin
    b_map_ready = f_ready;
    if(when_Stream_l477_2) begin
      b_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_2 = (! f_valid);
  assign f_valid = b_map_rValid;
  assign f_payload_x0 = b_map_rData_x0;
  assign f_payload_x1 = b_map_rData_x1;
  assign f_payload_y = b_map_rData_y;
  assign f_payload_p_v_0 = b_map_rData_p_v_0;
  assign f_payload_p_v_1 = b_map_rData_p_v_1;
  assign f_payload_p_v_2 = b_map_rData_p_v_2;
  assign f_payload_p_v_3 = b_map_rData_p_v_3;
  assign f_payload_p_v_4 = b_map_rData_p_v_4;
  assign f_payload_dx_v_0 = b_map_rData_dx_v_0;
  assign f_payload_dx_v_1 = b_map_rData_dx_v_1;
  assign f_payload_dx_v_2 = b_map_rData_dx_v_2;
  assign f_payload_dx_v_3 = b_map_rData_dx_v_3;
  assign f_payload_dx_v_4 = b_map_rData_dx_v_4;
  assign f_payload_attr = b_map_rData_attr;
  assign io_o_valid = f_valid;
  assign f_ready = io_o_ready;
  assign io_o_payload_x0 = f_payload_x0;
  assign io_o_payload_x1 = f_payload_x1;
  assign io_o_payload_y = f_payload_y;
  assign io_o_payload_p_v_0 = f_payload_p_v_0;
  assign io_o_payload_p_v_1 = f_payload_p_v_1;
  assign io_o_payload_p_v_2 = f_payload_p_v_2;
  assign io_o_payload_p_v_3 = f_payload_p_v_3;
  assign io_o_payload_p_v_4 = f_payload_p_v_4;
  assign io_o_payload_dx_v_0 = f_payload_dx_v_0;
  assign io_o_payload_dx_v_1 = f_payload_dx_v_1;
  assign io_o_payload_dx_v_2 = f_payload_dx_v_2;
  assign io_o_payload_dx_v_3 = f_payload_dx_v_3;
  assign io_o_payload_dx_v_4 = f_payload_dx_v_4;
  assign io_o_payload_attr = f_payload_attr;
  assign io_idle = (((! a_valid) && (! b_valid)) && (! f_valid));
  always @(posedge clk) begin
    if(reset) begin
      io_i_map_rValid <= 1'b0;
      a_map_rValid <= 1'b0;
      b_map_rValid <= 1'b0;
    end else begin
      if(io_i_map_ready) begin
        io_i_map_rValid <= io_i_map_valid;
      end
      if(a_map_ready) begin
        a_map_rValid <= a_map_valid;
      end
      if(b_map_ready) begin
        b_map_rValid <= b_map_valid;
      end
    end
  end

  always @(posedge clk) begin
    if(io_i_map_ready) begin
      io_i_map_rData_w_x0 <= io_i_map_payload_w_x0;
      io_i_map_rData_w_x1 <= io_i_map_payload_w_x1;
      io_i_map_rData_w_y <= io_i_map_payload_w_y;
      io_i_map_rData_ox <= io_i_map_payload_ox;
      io_i_map_rData_oy <= io_i_map_payload_oy;
    end
    if(a_map_ready) begin
      a_map_rData_w_x0 <= a_map_payload_w_x0;
      a_map_rData_w_x1 <= a_map_payload_w_x1;
      a_map_rData_w_y <= a_map_payload_w_y;
      a_map_rData_px_v_0 <= a_map_payload_px_v_0;
      a_map_rData_px_v_1 <= a_map_payload_px_v_1;
      a_map_rData_px_v_2 <= a_map_payload_px_v_2;
      a_map_rData_px_v_3 <= a_map_payload_px_v_3;
      a_map_rData_px_v_4 <= a_map_payload_px_v_4;
      a_map_rData_py_v_0 <= a_map_payload_py_v_0;
      a_map_rData_py_v_1 <= a_map_payload_py_v_1;
      a_map_rData_py_v_2 <= a_map_payload_py_v_2;
      a_map_rData_py_v_3 <= a_map_payload_py_v_3;
      a_map_rData_py_v_4 <= a_map_payload_py_v_4;
    end
    if(b_map_ready) begin
      b_map_rData_x0 <= b_map_payload_x0;
      b_map_rData_x1 <= b_map_payload_x1;
      b_map_rData_y <= b_map_payload_y;
      b_map_rData_p_v_0 <= b_map_payload_p_v_0;
      b_map_rData_p_v_1 <= b_map_payload_p_v_1;
      b_map_rData_p_v_2 <= b_map_payload_p_v_2;
      b_map_rData_p_v_3 <= b_map_payload_p_v_3;
      b_map_rData_p_v_4 <= b_map_payload_p_v_4;
      b_map_rData_dx_v_0 <= b_map_payload_dx_v_0;
      b_map_rData_dx_v_1 <= b_map_payload_dx_v_1;
      b_map_rData_dx_v_2 <= b_map_payload_dx_v_2;
      b_map_rData_dx_v_3 <= b_map_payload_dx_v_3;
      b_map_rData_dx_v_4 <= b_map_payload_dx_v_4;
      b_map_rData_attr <= b_map_payload_attr;
    end
  end


endmodule

module hng64_raster_TexBlock (
  input  wire          io_start,
  input  wire [27:0]   io_src,
  input  wire [27:0]   io_dst,
  input  wire [11:0]   io_groups,
  output reg           io_done,
  output wire          io_busy,
  output wire          io_rdAddr_valid,
  input  wire          io_rdAddr_ready,
  output wire [27:0]   io_rdAddr_payload,
  input  wire          io_rdData_valid,
  input  wire [63:0]   io_rdData_payload,
  output wire          io_wr_valid,
  input  wire          io_wr_ready,
  output wire [27:0]   io_wr_payload_addr,
  output wire [63:0]   io_wr_payload_data,
  output wire [7:0]    io_wr_payload_be,
  input  wire          clk,
  input  wire          reset
);
  localparam hng64_raster_S_1_Idle = 2'd0;
  localparam hng64_raster_S_1_Read = 2'd1;
  localparam hng64_raster_S_1_Write = 2'd2;

  reg        [63:0]   even_spinal_port1;
  reg        [63:0]   odd_spinal_port1;
  wire       [12:0]   _zz_left;
  wire       [24:0]   _zz_gBase;
  wire       [27:0]   _zz_io_rdAddr_payload;
  wire       [27:0]   _zz_io_rdAddr_payload_1;
  wire       [12:0]   _zz_io_rdAddr_payload_2;
  wire                _zz_even_port;
  wire                _zz_odd_port;
  wire       [27:0]   _zz_beats_payload_addr;
  wire       [27:0]   _zz_beats_payload_addr_1;
  wire       [12:0]   _zz_beats_payload_addr_2;
  reg        [1:0]    st;
  reg        [27:0]   src;
  reg        [27:0]   dst;
  reg        [12:0]   left;
  reg        [11:0]   group_1;
  reg        [10:0]   issued;
  reg        [10:0]   got;
  reg        [10:0]   wbeat;
  wire                when_TexBlock_l43;
  wire       [27:0]   gBase;
  wire                io_rdAddr_fire;
  wire       [9:0]    k;
  wire       [8:0]    bankAddr;
  wire                when_TexBlock_l65;
  wire                beats_valid;
  wire                beats_ready;
  wire       [27:0]   beats_payload_addr;
  wire       [63:0]   beats_payload_data;
  wire       [7:0]    beats_payload_be;
  wire                cmd_valid;
  reg                 cmd_ready;
  wire       [10:0]   cmd_payload;
  wire                cmd_fire;
  wire       [8:0]    rdAddr;
  wire       [63:0]   e;
  wire       [63:0]   o;
  wire                cmdQ_valid;
  wire                cmdQ_ready;
  wire       [10:0]   cmdQ_payload;
  reg                 cmd_rValid;
  reg        [10:0]   cmd_rData;
  wire                when_Stream_l477;
  wire                half;
  wire                when_TexBlock_l89;
  wire                when_TexBlock_l93;
  `ifndef SYNTHESIS
  reg [39:0] st_string;
  `endif

  reg [63:0] even [0:511];
  reg [63:0] odd [0:511];

  assign _zz_left = {1'd0, io_groups};
  assign _zz_gBase = {group_1,13'h0};
  assign _zz_io_rdAddr_payload = (src + gBase);
  assign _zz_io_rdAddr_payload_2 = {issued[9 : 0],3'b000};
  assign _zz_io_rdAddr_payload_1 = {15'd0, _zz_io_rdAddr_payload_2};
  assign _zz_beats_payload_addr = (dst + gBase);
  assign _zz_beats_payload_addr_2 = {{cmdQ_payload[9 : 2],cmdQ_payload[1 : 0]},3'b000};
  assign _zz_beats_payload_addr_1 = {15'd0, _zz_beats_payload_addr_2};
  assign _zz_even_port = (io_rdData_valid && (! k[7]));
  assign _zz_odd_port = (io_rdData_valid && k[7]);
  always @(posedge clk) begin
    if(_zz_even_port) begin
      even[bankAddr] <= io_rdData_payload;
    end
  end

  always @(posedge clk) begin
    if(cmd_fire) begin
      even_spinal_port1 <= even[rdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_odd_port) begin
      odd[bankAddr] <= io_rdData_payload;
    end
  end

  always @(posedge clk) begin
    if(cmd_fire) begin
      odd_spinal_port1 <= odd[rdAddr];
    end
  end

  `ifndef SYNTHESIS
  always @(*) begin
    case(st)
      hng64_raster_S_1_Idle : st_string = "Idle ";
      hng64_raster_S_1_Read : st_string = "Read ";
      hng64_raster_S_1_Write : st_string = "Write";
      default : st_string = "?????";
    endcase
  end
  `endif

  always @(*) begin
    io_done = 1'b0;
    if(when_TexBlock_l89) begin
      if(when_TexBlock_l93) begin
        io_done = 1'b1;
      end
    end
  end

  assign io_busy = (st != hng64_raster_S_1_Idle);
  assign when_TexBlock_l43 = ((st == hng64_raster_S_1_Idle) && io_start);
  assign gBase = {3'd0, _zz_gBase};
  assign io_rdAddr_valid = ((st == hng64_raster_S_1_Read) && (! issued[10]));
  assign io_rdAddr_payload = (_zz_io_rdAddr_payload + _zz_io_rdAddr_payload_1);
  assign io_rdAddr_fire = (io_rdAddr_valid && io_rdAddr_ready);
  assign k = got[9 : 0];
  assign bankAddr = {k[9 : 8],k[6 : 0]};
  assign when_TexBlock_l65 = ((st == hng64_raster_S_1_Read) && got[10]);
  assign cmd_valid = ((st == hng64_raster_S_1_Write) && (! wbeat[10]));
  assign cmd_payload = wbeat;
  assign cmd_fire = (cmd_valid && cmd_ready);
  assign rdAddr = {cmd_payload[1 : 0],cmd_payload[9 : 3]};
  assign e = even_spinal_port1;
  assign o = odd_spinal_port1;
  always @(*) begin
    cmd_ready = cmdQ_ready;
    if(when_Stream_l477) begin
      cmd_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! cmdQ_valid);
  assign cmdQ_valid = cmd_rValid;
  assign cmdQ_payload = cmd_rData;
  assign half = cmdQ_payload[2];
  assign beats_valid = cmdQ_valid;
  assign beats_payload_addr = (_zz_beats_payload_addr + _zz_beats_payload_addr_1);
  assign beats_payload_data = (half ? {o[63 : 32],e[63 : 32]} : {o[31 : 0],e[31 : 0]});
  assign beats_payload_be = 8'hff;
  assign cmdQ_ready = beats_ready;
  assign io_wr_valid = beats_valid;
  assign beats_ready = io_wr_ready;
  assign io_wr_payload_addr = beats_payload_addr;
  assign io_wr_payload_data = beats_payload_data;
  assign io_wr_payload_be = beats_payload_be;
  assign when_TexBlock_l89 = (((st == hng64_raster_S_1_Write) && wbeat[10]) && (! cmdQ_valid));
  assign when_TexBlock_l93 = (left == 13'h0001);
  always @(posedge clk) begin
    if(reset) begin
      st <= hng64_raster_S_1_Idle;
      cmd_rValid <= 1'b0;
    end else begin
      if(when_TexBlock_l43) begin
        st <= hng64_raster_S_1_Read;
      end
      if(when_TexBlock_l65) begin
        st <= hng64_raster_S_1_Write;
      end
      if(cmd_ready) begin
        cmd_rValid <= cmd_valid;
      end
      if(when_TexBlock_l89) begin
        if(when_TexBlock_l93) begin
          st <= hng64_raster_S_1_Idle;
        end else begin
          st <= hng64_raster_S_1_Read;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(when_TexBlock_l43) begin
      src <= io_src;
      dst <= io_dst;
      left <= ((io_groups == 12'h0) ? 13'h1000 : _zz_left);
      group_1 <= 12'h0;
      issued <= 11'h0;
      got <= 11'h0;
    end
    if(io_rdAddr_fire) begin
      issued <= (issued + 11'h001);
    end
    if(io_rdData_valid) begin
      got <= (got + 11'h001);
    end
    if(when_TexBlock_l65) begin
      wbeat <= 11'h0;
    end
    if(cmd_fire) begin
      wbeat <= (wbeat + 11'h001);
    end
    if(cmd_ready) begin
      cmd_rData <= cmd_payload;
    end
    if(when_TexBlock_l89) begin
      group_1 <= (group_1 + 12'h001);
      issued <= 11'h0;
      got <= 11'h0;
      if(!when_TexBlock_l93) begin
        left <= (left - 13'h0001);
      end
    end
  end


endmodule

module hng64_raster_RenderBuf (
  input  wire          io_i_valid,
  output reg           io_i_ready,
  input  wire [8:0]    io_i_payload_f_x,
  input  wire [8:0]    io_i_payload_f_y,
  input  wire [29:0]   io_i_payload_f_z,
  input  wire [23:0]   io_i_payload_f_addr,
  input  wire          io_i_payload_f_nib,
  input  wire [7:0]    io_i_payload_f_light,
  input  wire          io_i_payload_f_flat,
  input  wire          io_i_payload_f_blend,
  input  wire          io_i_payload_f_tex4bpp,
  input  wire [15:0]   io_i_payload_f_pal,
  input  wire [7:0]    io_i_payload_texel,
  output wire          io_rdAddr_valid,
  input  wire          io_rdAddr_ready,
  output wire [27:0]   io_rdAddr_payload,
  input  wire          io_rdData_valid,
  input  wire [63:0]   io_rdData_payload,
  output wire          io_wr_valid,
  input  wire          io_wr_ready,
  output wire [27:0]   io_wr_payload_addr,
  output wire [63:0]   io_wr_payload_data,
  output wire [7:0]    io_wr_payload_be,
  output wire          io_urgent,
  input  wire          io_start,
  input  wire          io_full,
  input  wire [7:0]    io_tag,
  input  wire [6:0]    io_scrub,
  input  wire [27:0]   io_colourBase,
  input  wire [27:0]   io_depthBase,
  input  wire          io_finish,
  output reg           io_done,
  output wire          io_busy,
  input  wire          clk,
  input  wire          reset
);
  localparam hng64_raster_F_Idle = 3'd0;
  localparam hng64_raster_F_Clear = 3'd1;
  localparam hng64_raster_F_Scrub = 3'd2;
  localparam hng64_raster_F_Render = 3'd3;
  localparam hng64_raster_F_Drain = 3'd4;
  localparam hng64_raster_F_Flush = 3'd5;
  localparam hng64_raster_F_Done = 3'd6;
  localparam hng64_raster_H_Wait_1 = 2'd0;
  localparam hng64_raster_H_ReadVictim = 2'd1;
  localparam hng64_raster_H_Fill = 2'd2;

  wire                missQ_io_push_valid;
  wire                missQ_io_pop_ready;
  wire                lineQ_io_push_valid;
  wire       [511:0]  lineQ_io_push_payload;
  reg                 lineQ_io_pop_ready;
  reg        [31:0]   banks_0_spinal_port0;
  reg        [31:0]   banks_1_spinal_port0;
  reg        [31:0]   banks_2_spinal_port0;
  reg        [31:0]   banks_3_spinal_port0;
  reg        [31:0]   banks_4_spinal_port0;
  reg        [31:0]   banks_5_spinal_port0;
  reg        [31:0]   banks_6_spinal_port0;
  reg        [31:0]   banks_7_spinal_port0;
  reg        [31:0]   banks_8_spinal_port0;
  reg        [31:0]   banks_9_spinal_port0;
  reg        [31:0]   banks_10_spinal_port0;
  reg        [31:0]   banks_11_spinal_port0;
  reg        [31:0]   banks_12_spinal_port0;
  reg        [31:0]   banks_13_spinal_port0;
  reg        [31:0]   banks_14_spinal_port0;
  reg        [31:0]   banks_15_spinal_port0;
  wire                wq_io_push_ready;
  wire                wq_io_pop_valid;
  wire       [27:0]   wq_io_pop_payload_b_addr;
  wire       [63:0]   wq_io_pop_payload_b_data;
  wire       [7:0]    wq_io_pop_payload_b_be;
  wire                wq_io_pop_payload_rel;
  wire       [2:0]    wq_io_pop_payload_relSlot;
  wire       [4:0]    wq_io_occupancy;
  wire       [4:0]    wq_io_availability;
  wire                streamArbiter_io_inputs_0_ready;
  wire                streamArbiter_io_inputs_1_ready;
  wire                streamArbiter_io_inputs_2_ready;
  wire                streamArbiter_io_output_valid;
  wire       [27:0]   streamArbiter_io_output_payload_b_addr;
  wire       [63:0]   streamArbiter_io_output_payload_b_data;
  wire       [7:0]    streamArbiter_io_output_payload_b_be;
  wire                streamArbiter_io_output_payload_rel;
  wire       [2:0]    streamArbiter_io_output_payload_relSlot;
  wire       [1:0]    streamArbiter_io_chosen;
  wire       [2:0]    streamArbiter_io_chosenOH;
  wire                frags_io_push_ready;
  wire                frags_io_pop_valid;
  wire       [8:0]    frags_io_pop_payload_f_x;
  wire       [8:0]    frags_io_pop_payload_f_y;
  wire       [23:0]   frags_io_pop_payload_f_z;
  wire       [15:0]   frags_io_pop_payload_f_colour;
  wire       [3:0]    frags_io_pop_payload_slot;
  wire                frags_io_pop_payload_miss;
  wire                frags_io_pop_payload_victim;
  wire       [13:0]   frags_io_pop_payload_vLine;
  wire       [2:0]    frags_io_pop_payload_pend;
  wire       [6:0]    frags_io_occupancy;
  wire       [6:0]    frags_io_availability;
  wire                missQ_io_push_ready;
  wire                missQ_io_pop_valid;
  wire       [13:0]   missQ_io_pop_payload;
  wire       [3:0]    missQ_io_occupancy;
  wire       [3:0]    missQ_io_availability;
  wire                lineQ_io_push_ready;
  wire                lineQ_io_pop_valid;
  wire       [511:0]  lineQ_io_pop_payload;
  wire       [3:0]    lineQ_io_occupancy;
  wire       [3:0]    lineQ_io_availability;
  wire       [7:0]    _zz_stale;
  wire       [27:0]   _zz_clearW_payload_b_addr;
  wire       [27:0]   _zz_clearW_payload_b_addr_1;
  wire       [20:0]   _zz_clearW_payload_b_addr_2;
  wire       [27:0]   _zz_clearW_payload_b_addr_3;
  wire       [27:0]   _zz_clearW_payload_b_addr_4;
  wire       [19:0]   _zz_clearW_payload_b_addr_5;
  wire       [7:0]    _zz_when_Stream_l581;
  wire       [3:0]    _zz_when_Stream_l581_1;
  wire       [23:0]   _zz_io_i_throwWhen_map_payload_z_1;
  wire       [25:0]   _zz_io_i_throwWhen_map_payload_z_2;
  wire       [10:0]   _zz_io_i_throwWhen_map_payload_colour;
  wire       [15:0]   _zz_io_i_throwWhen_map_payload_colour_1;
  wire       [15:0]   _zz_io_i_throwWhen_map_payload_colour_2;
  wire       [7:0]    _zz_io_i_throwWhen_map_payload_colour_3;
  wire       [7:0]    _zz_io_i_throwWhen_map_payload_colour_4;
  wire       [3:0]    _zz_io_i_throwWhen_map_payload_colour_5;
  reg                 _zz_hitW_0;
  wire       [3:0]    _zz_hitW_0_1;
  reg        [10:0]   _zz_hitW_0_2;
  wire       [3:0]    _zz_hitW_0_3;
  reg                 _zz_hitW_1;
  wire       [3:0]    _zz_hitW_1_1;
  reg        [10:0]   _zz_hitW_1_2;
  wire       [3:0]    _zz_hitW_1_3;
  reg                 _zz__zz_way;
  reg                 _zz_vValid;
  reg        [10:0]   _zz_vLine;
  wire                _zz_pendingHit;
  wire                _zz_pendingHit_1;
  wire                _zz_pendingHit_2;
  wire       [0:0]    _zz_pendingHit_3;
  wire       [1:0]    _zz_pendingHit_4;
  wire       [7:0]    _zz_free_ohFirst_masked;
  reg                 _zz__zz_pVic_0;
  reg        [10:0]   _zz__zz_pLine_0;
  wire       [3:0]    _zz_credits;
  wire       [3:0]    _zz_credits_1;
  wire       [0:0]    _zz_credits_2;
  wire       [3:0]    _zz_credits_3;
  wire       [0:0]    _zz_credits_4;
  wire       [27:0]   _zz_io_rdAddr_payload;
  wire       [19:0]   _zz_io_rdAddr_payload_1;
  reg                 _zz__zz_vLeft;
  wire       [27:0]   _zz_backW_payload_b_addr;
  wire       [19:0]   _zz_backW_payload_b_addr_1;
  wire       [2:0]    _zz_backW_payload_b_addr_2;
  wire       [3:0]    _zz_backW_payload_b_addr_3;
  reg        [63:0]   _zz_backW_payload_b_data;
  wire       [2:0]    _zz_backW_payload_b_data_1;
  wire       [3:0]    _zz_backW_payload_b_data_2;
  reg        [31:0]   _zz_readWord;
  wire       [24:0]   _zz_storedZ;
  wire       [23:0]   _zz_storedZ_1;
  wire       [24:0]   _zz_pass;
  wire       [3:0]    _zz_banks_0_port;
  wire       [31:0]   _zz_banks_0_port_1;
  wire                _zz_banks_0_port_2;
  wire       [3:0]    _zz_banks_1_port;
  wire       [31:0]   _zz_banks_1_port_1;
  wire                _zz_banks_1_port_2;
  wire       [3:0]    _zz_banks_2_port;
  wire       [31:0]   _zz_banks_2_port_1;
  wire                _zz_banks_2_port_2;
  wire       [3:0]    _zz_banks_3_port;
  wire       [31:0]   _zz_banks_3_port_1;
  wire                _zz_banks_3_port_2;
  wire       [3:0]    _zz_banks_4_port;
  wire       [31:0]   _zz_banks_4_port_1;
  wire                _zz_banks_4_port_2;
  wire       [3:0]    _zz_banks_5_port;
  wire       [31:0]   _zz_banks_5_port_1;
  wire                _zz_banks_5_port_2;
  wire       [3:0]    _zz_banks_6_port;
  wire       [31:0]   _zz_banks_6_port_1;
  wire                _zz_banks_6_port_2;
  wire       [3:0]    _zz_banks_7_port;
  wire       [31:0]   _zz_banks_7_port_1;
  wire                _zz_banks_7_port_2;
  wire       [3:0]    _zz_banks_8_port;
  wire       [31:0]   _zz_banks_8_port_1;
  wire                _zz_banks_8_port_2;
  wire       [3:0]    _zz_banks_9_port;
  wire       [31:0]   _zz_banks_9_port_1;
  wire                _zz_banks_9_port_2;
  wire       [3:0]    _zz_banks_10_port;
  wire       [31:0]   _zz_banks_10_port_1;
  wire                _zz_banks_10_port_2;
  wire       [3:0]    _zz_banks_11_port;
  wire       [31:0]   _zz_banks_11_port_1;
  wire                _zz_banks_11_port_2;
  wire       [3:0]    _zz_banks_12_port;
  wire       [31:0]   _zz_banks_12_port_1;
  wire                _zz_banks_12_port_2;
  wire       [3:0]    _zz_banks_13_port;
  wire       [31:0]   _zz_banks_13_port_1;
  wire                _zz_banks_13_port_2;
  wire       [3:0]    _zz_banks_14_port;
  wire       [31:0]   _zz_banks_14_port_1;
  wire                _zz_banks_14_port_2;
  wire       [3:0]    _zz_banks_15_port;
  wire       [31:0]   _zz_banks_15_port_1;
  wire                _zz_banks_15_port_2;
  reg        [7:0]    _zz__zz_colourW_valid;
  wire       [27:0]   _zz_colourW_payload_b_addr;
  wire       [18:0]   _zz_colourW_payload_b_addr_1;
  reg        [63:0]   _zz_colourW_payload_b_data;
  reg                 _zz_when_RenderBuf_l418;
  wire       [3:0]    _zz_when_RenderBuf_l418_1;
  reg                 _zz_when_RenderBuf_l418_2;
  wire       [3:0]    _zz_when_RenderBuf_l418_3;
  reg        [10:0]   _zz_vAddr_1;
  reg        [2:0]    fs;
  reg        [7:0]    tag;
  reg                 full;
  reg        [6:0]    scrubPhase;
  reg        [27:0]   cBase;
  reg        [27:0]   dBase;
  reg                 finishing;
  reg        [17:0]   count;
  wire                when_RenderBuf_l62;
  wire                clearW_valid;
  wire                clearW_ready;
  wire       [27:0]   clearW_payload_b_addr;
  wire       [63:0]   clearW_payload_b_data;
  wire       [7:0]    clearW_payload_b_be;
  wire                clearW_payload_rel;
  wire       [2:0]    clearW_payload_relSlot;
  wire                backW_valid;
  wire                backW_ready;
  wire       [27:0]   backW_payload_b_addr;
  wire       [63:0]   backW_payload_b_data;
  wire       [7:0]    backW_payload_b_be;
  wire                backW_payload_rel;
  wire       [2:0]    backW_payload_relSlot;
  wire                colourW_valid;
  wire                colourW_ready;
  wire       [27:0]   colourW_payload_b_addr;
  wire       [63:0]   colourW_payload_b_data;
  wire       [7:0]    colourW_payload_b_be;
  wire                colourW_payload_rel;
  wire       [2:0]    colourW_payload_relSlot;
  wire                wq_io_pop_translated_valid;
  wire                wq_io_pop_translated_ready;
  wire       [27:0]   wq_io_pop_translated_payload_addr;
  wire       [63:0]   wq_io_pop_translated_payload_data;
  wire       [7:0]    wq_io_pop_translated_payload_be;
  wire       [7:0]    stale;
  wire                clearW_fire;
  wire                when_RenderBuf_l94;
  wire                when_RenderBuf_l98;
  wire                when_Stream_l581;
  reg                 io_i_throwWhen_valid;
  wire                io_i_throwWhen_ready;
  wire       [8:0]    io_i_throwWhen_payload_f_x;
  wire       [8:0]    io_i_throwWhen_payload_f_y;
  wire       [29:0]   io_i_throwWhen_payload_f_z;
  wire       [23:0]   io_i_throwWhen_payload_f_addr;
  wire                io_i_throwWhen_payload_f_nib;
  wire       [7:0]    io_i_throwWhen_payload_f_light;
  wire                io_i_throwWhen_payload_f_flat;
  wire                io_i_throwWhen_payload_f_blend;
  wire                io_i_throwWhen_payload_f_tex4bpp;
  wire       [15:0]   io_i_throwWhen_payload_f_pal;
  wire       [7:0]    io_i_throwWhen_payload_texel;
  wire       [25:0]   _zz_io_i_throwWhen_map_payload_z;
  wire                io_i_throwWhen_map_valid;
  reg                 io_i_throwWhen_map_ready;
  wire       [8:0]    io_i_throwWhen_map_payload_x;
  wire       [8:0]    io_i_throwWhen_map_payload_y;
  wire       [23:0]   io_i_throwWhen_map_payload_z;
  wire       [15:0]   io_i_throwWhen_map_payload_colour;
  wire                io_i_throwWhen_map_m2sPipe_valid;
  wire                io_i_throwWhen_map_m2sPipe_ready;
  wire       [8:0]    io_i_throwWhen_map_m2sPipe_payload_x;
  wire       [8:0]    io_i_throwWhen_map_m2sPipe_payload_y;
  wire       [23:0]   io_i_throwWhen_map_m2sPipe_payload_z;
  wire       [15:0]   io_i_throwWhen_map_m2sPipe_payload_colour;
  reg                 io_i_throwWhen_map_rValid;
  reg        [8:0]    io_i_throwWhen_map_rData_x;
  reg        [8:0]    io_i_throwWhen_map_rData_y;
  reg        [23:0]   io_i_throwWhen_map_rData_z;
  reg        [15:0]   io_i_throwWhen_map_rData_colour;
  wire                when_Stream_l477;
  wire                _zz_io_i_throwWhen_map_m2sPipe_ready;
  wire                prep_valid;
  wire                prep_ready;
  wire       [8:0]    prep_payload_x;
  wire       [8:0]    prep_payload_y;
  wire       [23:0]   prep_payload_z;
  wire       [15:0]   prep_payload_colour;
  reg                 tValid_0;
  reg                 tValid_1;
  reg                 tValid_2;
  reg                 tValid_3;
  reg                 tValid_4;
  reg                 tValid_5;
  reg                 tValid_6;
  reg                 tValid_7;
  reg                 tValid_8;
  reg                 tValid_9;
  reg                 tValid_10;
  reg                 tValid_11;
  reg                 tValid_12;
  reg                 tValid_13;
  reg                 tValid_14;
  reg                 tValid_15;
  reg        [10:0]   tTag_0;
  reg        [10:0]   tTag_1;
  reg        [10:0]   tTag_2;
  reg        [10:0]   tTag_3;
  reg        [10:0]   tTag_4;
  reg        [10:0]   tTag_5;
  reg        [10:0]   tTag_6;
  reg        [10:0]   tTag_7;
  reg        [10:0]   tTag_8;
  reg        [10:0]   tTag_9;
  reg        [10:0]   tTag_10;
  reg        [10:0]   tTag_11;
  reg        [10:0]   tTag_12;
  reg        [10:0]   tTag_13;
  reg        [10:0]   tTag_14;
  reg        [10:0]   tTag_15;
  reg                 lru_0;
  reg                 lru_1;
  reg                 lru_2;
  reg                 lru_3;
  reg                 lru_4;
  reg                 lru_5;
  reg                 lru_6;
  reg                 lru_7;
  reg                 pOcc_0;
  reg                 pOcc_1;
  reg                 pOcc_2;
  reg                 pOcc_3;
  reg                 pOcc_4;
  reg                 pOcc_5;
  reg                 pOcc_6;
  reg                 pOcc_7;
  reg                 pVic_0;
  reg                 pVic_1;
  reg                 pVic_2;
  reg                 pVic_3;
  reg                 pVic_4;
  reg                 pVic_5;
  reg                 pVic_6;
  reg                 pVic_7;
  reg        [13:0]   pLine_0;
  reg        [13:0]   pLine_1;
  reg        [13:0]   pLine_2;
  reg        [13:0]   pLine_3;
  reg        [13:0]   pLine_4;
  reg        [13:0]   pLine_5;
  reg        [13:0]   pLine_6;
  reg        [13:0]   pLine_7;
  reg        [3:0]    credits;
  wire       [13:0]   line;
  wire       [2:0]    set;
  wire       [10:0]   ltag;
  wire                hitW_0;
  wire                hitW_1;
  wire                hit;
  wire                _zz_way;
  wire       [7:0]    _zz_1;
  wire       [0:0]    way;
  wire       [3:0]    slot;
  wire                vValid;
  wire       [15:0]   _zz_2;
  wire       [15:0]   _zz_3;
  wire       [13:0]   vLine;
  wire                pendingHit;
  wire       [7:0]    free;
  wire       [7:0]    free_ohFirst_input;
  wire       [7:0]    free_ohFirst_masked;
  wire       [7:0]    free_ohFirst_value;
  wire                _zz_freeSlot;
  wire                _zz_freeSlot_1;
  wire                _zz_freeSlot_2;
  wire                _zz_freeSlot_3;
  wire                _zz_freeSlot_4;
  wire                _zz_freeSlot_5;
  wire                _zz_freeSlot_6;
  wire       [2:0]    freeSlot;
  wire                fragIn_valid;
  reg                 fragIn_ready;
  wire       [8:0]    fragIn_payload_f_x;
  wire       [8:0]    fragIn_payload_f_y;
  wire       [23:0]   fragIn_payload_f_z;
  wire       [15:0]   fragIn_payload_f_colour;
  wire       [3:0]    fragIn_payload_slot;
  wire                fragIn_payload_miss;
  wire                fragIn_payload_victim;
  wire       [13:0]   fragIn_payload_vLine;
  wire       [2:0]    fragIn_payload_pend;
  wire                fragIn_m2sPipe_valid;
  wire                fragIn_m2sPipe_ready;
  wire       [8:0]    fragIn_m2sPipe_payload_f_x;
  wire       [8:0]    fragIn_m2sPipe_payload_f_y;
  wire       [23:0]   fragIn_m2sPipe_payload_f_z;
  wire       [15:0]   fragIn_m2sPipe_payload_f_colour;
  wire       [3:0]    fragIn_m2sPipe_payload_slot;
  wire                fragIn_m2sPipe_payload_miss;
  wire                fragIn_m2sPipe_payload_victim;
  wire       [13:0]   fragIn_m2sPipe_payload_vLine;
  wire       [2:0]    fragIn_m2sPipe_payload_pend;
  reg                 fragIn_rValid;
  reg        [8:0]    fragIn_rData_f_x;
  reg        [8:0]    fragIn_rData_f_y;
  reg        [23:0]   fragIn_rData_f_z;
  reg        [15:0]   fragIn_rData_f_colour;
  reg        [3:0]    fragIn_rData_slot;
  reg                 fragIn_rData_miss;
  reg                 fragIn_rData_victim;
  reg        [13:0]   fragIn_rData_vLine;
  reg        [2:0]    fragIn_rData_pend;
  wire                when_Stream_l477_1;
  wire                canGo;
  reg                 consume;
  reg                 release_valid;
  reg        [2:0]    release_payload;
  wire                releaseWb_valid;
  wire       [2:0]    releaseWb_payload;
  wire                prep_fire;
  wire                allocate;
  wire       [3:0]    mSlot;
  wire                when_RenderBuf_l177;
  wire                _zz_pVic_0;
  wire       [10:0]   _zz_pLine_0;
  wire                when_RenderBuf_l177_1;
  wire                when_RenderBuf_l177_2;
  wire                when_RenderBuf_l177_3;
  wire                when_RenderBuf_l177_4;
  wire                when_RenderBuf_l177_5;
  wire                when_RenderBuf_l177_6;
  wire                when_RenderBuf_l177_7;
  wire                _zz_lru_0;
  wire                when_RenderBuf_l183;
  wire       [7:0]    _zz_4;
  wire       [7:0]    _zz_5;
  wire       [7:0]    _zz_6;
  reg        [2:0]    beat;
  wire                io_rdAddr_fire;
  reg        [63:0]   gather_0;
  reg        [63:0]   gather_1;
  reg        [63:0]   gather_2;
  reg        [63:0]   gather_3;
  reg        [63:0]   gather_4;
  reg        [63:0]   gather_5;
  reg        [63:0]   gather_6;
  reg        [63:0]   gather_7;
  reg        [2:0]    gBeat;
  wire       [7:0]    _zz_7;
  reg                 dirty_0;
  reg                 dirty_1;
  reg                 dirty_2;
  reg                 dirty_3;
  reg                 dirty_4;
  reg                 dirty_5;
  reg                 dirty_6;
  reg                 dirty_7;
  reg                 dirty_8;
  reg                 dirty_9;
  reg                 dirty_10;
  reg                 dirty_11;
  reg                 dirty_12;
  reg                 dirty_13;
  reg                 dirty_14;
  reg                 dirty_15;
  reg        [1:0]    hs;
  reg                 filled;
  reg        [63:0]   vBuf_0;
  reg        [63:0]   vBuf_1;
  reg        [63:0]   vBuf_2;
  reg        [63:0]   vBuf_3;
  reg        [63:0]   vBuf_4;
  reg        [63:0]   vBuf_5;
  reg        [63:0]   vBuf_6;
  reg        [63:0]   vBuf_7;
  reg        [3:0]    vLeft;
  reg        [13:0]   vAddr;
  reg        [2:0]    vPend;
  reg                 vRelease;
  reg                 rValid;
  reg        [8:0]    rF_f_x;
  reg        [8:0]    rF_f_y;
  reg        [23:0]   rF_f_z;
  reg        [15:0]   rF_f_colour;
  reg        [3:0]    rF_slot;
  reg                 rF_miss;
  reg                 rF_victim;
  reg        [13:0]   rF_vLine;
  reg        [2:0]    rF_pend;
  wire                sValidW;
  wire                cValidW;
  wire                rIdle;
  reg        [3:0]    bankRdAddr;
  reg                 bankRdEn;
  wire       [31:0]   bankRd_0;
  wire       [31:0]   bankRd_1;
  wire       [31:0]   bankRd_2;
  wire       [31:0]   bankRd_3;
  wire       [31:0]   bankRd_4;
  wire       [31:0]   bankRd_5;
  wire       [31:0]   bankRd_6;
  wire       [31:0]   bankRd_7;
  wire       [31:0]   bankRd_8;
  wire       [31:0]   bankRd_9;
  wire       [31:0]   bankRd_10;
  wire       [31:0]   bankRd_11;
  wire       [31:0]   bankRd_12;
  wire       [31:0]   bankRd_13;
  wire       [31:0]   bankRd_14;
  wire       [31:0]   bankRd_15;
  wire                needFill;
  wire                go;
  wire                when_RenderBuf_l252;
  wire                when_RenderBuf_l257;
  wire       [15:0]   _zz_24;
  wire                _zz_vLeft;
  wire                when_RenderBuf_l264;
  wire                backW_fire;
  wire                io_wr_fire;
  reg                 sValid;
  reg                 cValid;
  reg        [8:0]    sF_f_x;
  reg        [8:0]    sF_f_y;
  reg        [23:0]   sF_f_z;
  reg        [15:0]   sF_f_colour;
  reg        [3:0]    sF_slot;
  reg                 sF_miss;
  reg                 sF_victim;
  reg        [13:0]   sF_vLine;
  reg        [2:0]    sF_pend;
  reg        [8:0]    cF_f_x;
  reg        [8:0]    cF_f_y;
  reg        [23:0]   cF_f_z;
  reg        [15:0]   cF_f_colour;
  reg        [3:0]    cF_slot;
  reg                 cF_miss;
  reg                 cF_victim;
  reg        [13:0]   cF_vLine;
  reg        [2:0]    cF_pend;
  reg                 sPass;
  reg                 cPass;
  reg        [31:0]   sWord;
  reg        [31:0]   cWord;
  reg                 lastWr;
  reg        [3:0]    lastSlot;
  reg        [3:0]    lastPx;
  reg        [31:0]   lastWord;
  wire                comb_valid;
  wire                comb_ready;
  wire       [17:0]   comb_payload_pixel;
  wire       [15:0]   comb_payload_colour;
  wire                cDone;
  wire                sMove;
  wire                sFree;
  wire                rMove;
  wire                rFree;
  wire       [3:0]    px;
  wire       [31:0]   readWord;
  reg        [31:0]   word;
  wire                when_RenderBuf_l316;
  wire                when_RenderBuf_l317;
  wire                when_RenderBuf_l318;
  wire       [24:0]   storedZ;
  wire                pass;
  wire                fillNow;
  wire                cWrite;
  wire       [3:0]    cPx;
  wire       [15:0]   _zz_41;
  reg        [12:0]   cLine;
  reg        [63:0]   cData_0;
  reg        [63:0]   cData_1;
  reg        [63:0]   cData_2;
  reg        [63:0]   cData_3;
  reg        [63:0]   cData_4;
  reg        [63:0]   cData_5;
  reg        [63:0]   cData_6;
  reg        [63:0]   cData_7;
  reg        [7:0]    cBe_0;
  reg        [7:0]    cBe_1;
  reg        [7:0]    cBe_2;
  reg        [7:0]    cBe_3;
  reg        [7:0]    cBe_4;
  reg        [7:0]    cBe_5;
  reg        [7:0]    cBe_6;
  reg        [7:0]    cBe_7;
  reg                 flushing;
  reg        [2:0]    fBeat;
  reg                 anyBe;
  wire       [12:0]   cLineOf;
  wire                needFlush;
  wire                frameFlush;
  wire                when_RenderBuf_l377;
  wire       [7:0]    _zz_colourW_valid;
  wire       [7:0]    _zz_42;
  wire                colourW_fire;
  wire                when_RenderBuf_l387;
  wire                when_RenderBuf_l390;
  wire                comb_fire;
  wire       [4:0]    _zz_when_RenderBuf_l398;
  wire                when_RenderBuf_l398;
  wire                when_RenderBuf_l398_1;
  wire                when_RenderBuf_l398_2;
  wire                when_RenderBuf_l398_3;
  wire                when_RenderBuf_l398_4;
  wire                when_RenderBuf_l398_5;
  wire                when_RenderBuf_l398_6;
  wire                when_RenderBuf_l398_7;
  wire                when_RenderBuf_l398_8;
  wire                when_RenderBuf_l398_9;
  wire                when_RenderBuf_l398_10;
  wire                when_RenderBuf_l398_11;
  wire                when_RenderBuf_l398_12;
  wire                when_RenderBuf_l398_13;
  wire                when_RenderBuf_l398_14;
  wire                when_RenderBuf_l398_15;
  wire                when_RenderBuf_l398_16;
  wire                when_RenderBuf_l398_17;
  wire                when_RenderBuf_l398_18;
  wire                when_RenderBuf_l398_19;
  wire                when_RenderBuf_l398_20;
  wire                when_RenderBuf_l398_21;
  wire                when_RenderBuf_l398_22;
  wire                when_RenderBuf_l398_23;
  wire                when_RenderBuf_l398_24;
  wire                when_RenderBuf_l398_25;
  wire                when_RenderBuf_l398_26;
  wire                when_RenderBuf_l398_27;
  wire                when_RenderBuf_l398_28;
  wire                when_RenderBuf_l398_29;
  wire                when_RenderBuf_l398_30;
  wire                when_RenderBuf_l398_31;
  wire                pipeEmpty;
  reg        [4:0]    flushSlot;
  wire                when_RenderBuf_l409;
  reg                 drainRead;
  wire                when_RenderBuf_l415;
  wire                when_RenderBuf_l416;
  wire                when_RenderBuf_l418;
  wire       [3:0]    _zz_vAddr;
  wire       [15:0]   _zz_43;
  wire                when_RenderBuf_l436;
  wire                when_RenderBuf_l439;
  `ifndef SYNTHESIS
  reg [47:0] fs_string;
  reg [79:0] hs_string;
  `endif

  (* ramstyle = "M10K" *) reg [31:0] banks_0 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_1 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_2 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_3 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_4 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_5 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_6 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_7 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_8 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_9 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_10 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_11 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_12 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_13 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_14 [0:15];
  (* ramstyle = "M10K" *) reg [31:0] banks_15 [0:15];

  assign _zz_stale = (tag + 8'h80);
  assign _zz_clearW_payload_b_addr = (cBase + _zz_clearW_payload_b_addr_1);
  assign _zz_clearW_payload_b_addr_2 = {count,3'b000};
  assign _zz_clearW_payload_b_addr_1 = {7'd0, _zz_clearW_payload_b_addr_2};
  assign _zz_clearW_payload_b_addr_3 = (dBase + _zz_clearW_payload_b_addr_4);
  assign _zz_clearW_payload_b_addr_5 = {(full ? count[16 : 0] : {scrubPhase,count[9 : 0]}),3'b000};
  assign _zz_clearW_payload_b_addr_4 = {8'd0, _zz_clearW_payload_b_addr_5};
  assign _zz_when_Stream_l581_1 = (io_i_payload_f_nib ? io_i_payload_texel[7 : 4] : io_i_payload_texel[3 : 0]);
  assign _zz_when_Stream_l581 = {4'd0, _zz_when_Stream_l581_1};
  assign _zz_io_i_throwWhen_map_payload_z_2 = _zz_io_i_throwWhen_map_payload_z;
  assign _zz_io_i_throwWhen_map_payload_z_1 = _zz_io_i_throwWhen_map_payload_z_2[23:0];
  assign _zz_io_i_throwWhen_map_payload_colour_1 = (io_i_throwWhen_payload_f_pal + _zz_io_i_throwWhen_map_payload_colour_2);
  assign _zz_io_i_throwWhen_map_payload_colour = _zz_io_i_throwWhen_map_payload_colour_1[10:0];
  assign _zz_io_i_throwWhen_map_payload_colour_3 = (io_i_throwWhen_payload_f_tex4bpp ? _zz_io_i_throwWhen_map_payload_colour_4 : io_i_throwWhen_payload_texel);
  assign _zz_io_i_throwWhen_map_payload_colour_2 = {8'd0, _zz_io_i_throwWhen_map_payload_colour_3};
  assign _zz_io_i_throwWhen_map_payload_colour_5 = (io_i_throwWhen_payload_f_nib ? io_i_throwWhen_payload_texel[7 : 4] : io_i_throwWhen_payload_texel[3 : 0]);
  assign _zz_io_i_throwWhen_map_payload_colour_4 = {4'd0, _zz_io_i_throwWhen_map_payload_colour_5};
  assign _zz_free_ohFirst_masked = (free_ohFirst_input - 8'h01);
  assign _zz_credits = (credits - _zz_credits_1);
  assign _zz_credits_2 = allocate;
  assign _zz_credits_1 = {3'd0, _zz_credits_2};
  assign _zz_credits_4 = consume;
  assign _zz_credits_3 = {3'd0, _zz_credits_4};
  assign _zz_io_rdAddr_payload_1 = {{missQ_io_pop_payload,beat},3'b000};
  assign _zz_io_rdAddr_payload = {8'd0, _zz_io_rdAddr_payload_1};
  assign _zz_backW_payload_b_addr_1 = {{vAddr,_zz_backW_payload_b_addr_2},3'b000};
  assign _zz_backW_payload_b_addr = {8'd0, _zz_backW_payload_b_addr_1};
  assign _zz_backW_payload_b_addr_3 = (4'b1000 - vLeft);
  assign _zz_backW_payload_b_addr_2 = _zz_backW_payload_b_addr_3[2:0];
  assign _zz_backW_payload_b_data_2 = (4'b1000 - vLeft);
  assign _zz_backW_payload_b_data_1 = _zz_backW_payload_b_data_2[2:0];
  assign _zz_storedZ_1 = word[23 : 0];
  assign _zz_storedZ = {1'd0, _zz_storedZ_1};
  assign _zz_pass = {1'd0, rF_f_z};
  assign _zz_colourW_payload_b_addr_1 = {{cLine,fBeat},3'b000};
  assign _zz_colourW_payload_b_addr = {9'd0, _zz_colourW_payload_b_addr_1};
  assign _zz_banks_0_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_0_port_1 = (fillNow ? lineQ_io_pop_payload[31 : 0] : cWord);
  assign _zz_banks_0_port_2 = (fillNow || (cWrite && (cPx == 4'b0000)));
  assign _zz_banks_1_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_1_port_1 = (fillNow ? lineQ_io_pop_payload[63 : 32] : cWord);
  assign _zz_banks_1_port_2 = (fillNow || (cWrite && (cPx == 4'b0001)));
  assign _zz_banks_2_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_2_port_1 = (fillNow ? lineQ_io_pop_payload[95 : 64] : cWord);
  assign _zz_banks_2_port_2 = (fillNow || (cWrite && (cPx == 4'b0010)));
  assign _zz_banks_3_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_3_port_1 = (fillNow ? lineQ_io_pop_payload[127 : 96] : cWord);
  assign _zz_banks_3_port_2 = (fillNow || (cWrite && (cPx == 4'b0011)));
  assign _zz_banks_4_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_4_port_1 = (fillNow ? lineQ_io_pop_payload[159 : 128] : cWord);
  assign _zz_banks_4_port_2 = (fillNow || (cWrite && (cPx == 4'b0100)));
  assign _zz_banks_5_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_5_port_1 = (fillNow ? lineQ_io_pop_payload[191 : 160] : cWord);
  assign _zz_banks_5_port_2 = (fillNow || (cWrite && (cPx == 4'b0101)));
  assign _zz_banks_6_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_6_port_1 = (fillNow ? lineQ_io_pop_payload[223 : 192] : cWord);
  assign _zz_banks_6_port_2 = (fillNow || (cWrite && (cPx == 4'b0110)));
  assign _zz_banks_7_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_7_port_1 = (fillNow ? lineQ_io_pop_payload[255 : 224] : cWord);
  assign _zz_banks_7_port_2 = (fillNow || (cWrite && (cPx == 4'b0111)));
  assign _zz_banks_8_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_8_port_1 = (fillNow ? lineQ_io_pop_payload[287 : 256] : cWord);
  assign _zz_banks_8_port_2 = (fillNow || (cWrite && (cPx == 4'b1000)));
  assign _zz_banks_9_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_9_port_1 = (fillNow ? lineQ_io_pop_payload[319 : 288] : cWord);
  assign _zz_banks_9_port_2 = (fillNow || (cWrite && (cPx == 4'b1001)));
  assign _zz_banks_10_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_10_port_1 = (fillNow ? lineQ_io_pop_payload[351 : 320] : cWord);
  assign _zz_banks_10_port_2 = (fillNow || (cWrite && (cPx == 4'b1010)));
  assign _zz_banks_11_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_11_port_1 = (fillNow ? lineQ_io_pop_payload[383 : 352] : cWord);
  assign _zz_banks_11_port_2 = (fillNow || (cWrite && (cPx == 4'b1011)));
  assign _zz_banks_12_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_12_port_1 = (fillNow ? lineQ_io_pop_payload[415 : 384] : cWord);
  assign _zz_banks_12_port_2 = (fillNow || (cWrite && (cPx == 4'b1100)));
  assign _zz_banks_13_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_13_port_1 = (fillNow ? lineQ_io_pop_payload[447 : 416] : cWord);
  assign _zz_banks_13_port_2 = (fillNow || (cWrite && (cPx == 4'b1101)));
  assign _zz_banks_14_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_14_port_1 = (fillNow ? lineQ_io_pop_payload[479 : 448] : cWord);
  assign _zz_banks_14_port_2 = (fillNow || (cWrite && (cPx == 4'b1110)));
  assign _zz_banks_15_port = (fillNow ? frags_io_pop_payload_slot : cF_slot);
  assign _zz_banks_15_port_1 = (fillNow ? lineQ_io_pop_payload[511 : 480] : cWord);
  assign _zz_banks_15_port_2 = (fillNow || (cWrite && (cPx == 4'b1111)));
  assign _zz_hitW_0_1 = {set,1'b0};
  assign _zz_hitW_0_3 = {set,1'b0};
  assign _zz_hitW_1_1 = {set,1'b1};
  assign _zz_hitW_1_3 = {set,1'b1};
  assign _zz_when_RenderBuf_l418_1 = flushSlot[3 : 0];
  assign _zz_when_RenderBuf_l418_3 = flushSlot[3 : 0];
  assign _zz_pendingHit = (pOcc_4 && pVic_4);
  assign _zz_pendingHit_1 = (pLine_4 == line);
  assign _zz_pendingHit_2 = ((pOcc_3 && pVic_3) && (pLine_3 == line));
  assign _zz_pendingHit_3 = ((pOcc_2 && pVic_2) && (pLine_2 == line));
  assign _zz_pendingHit_4 = {((pOcc_1 && pVic_1) && (pLine_1 == line)),((pOcc_0 && pVic_0) && (pLine_0 == line))};
  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_0_spinal_port0 <= banks_0[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_0_port_2) begin
      banks_0[_zz_banks_0_port] <= _zz_banks_0_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_1_spinal_port0 <= banks_1[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_1_port_2) begin
      banks_1[_zz_banks_1_port] <= _zz_banks_1_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_2_spinal_port0 <= banks_2[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_2_port_2) begin
      banks_2[_zz_banks_2_port] <= _zz_banks_2_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_3_spinal_port0 <= banks_3[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_3_port_2) begin
      banks_3[_zz_banks_3_port] <= _zz_banks_3_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_4_spinal_port0 <= banks_4[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_4_port_2) begin
      banks_4[_zz_banks_4_port] <= _zz_banks_4_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_5_spinal_port0 <= banks_5[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_5_port_2) begin
      banks_5[_zz_banks_5_port] <= _zz_banks_5_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_6_spinal_port0 <= banks_6[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_6_port_2) begin
      banks_6[_zz_banks_6_port] <= _zz_banks_6_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_7_spinal_port0 <= banks_7[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_7_port_2) begin
      banks_7[_zz_banks_7_port] <= _zz_banks_7_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_8_spinal_port0 <= banks_8[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_8_port_2) begin
      banks_8[_zz_banks_8_port] <= _zz_banks_8_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_9_spinal_port0 <= banks_9[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_9_port_2) begin
      banks_9[_zz_banks_9_port] <= _zz_banks_9_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_10_spinal_port0 <= banks_10[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_10_port_2) begin
      banks_10[_zz_banks_10_port] <= _zz_banks_10_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_11_spinal_port0 <= banks_11[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_11_port_2) begin
      banks_11[_zz_banks_11_port] <= _zz_banks_11_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_12_spinal_port0 <= banks_12[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_12_port_2) begin
      banks_12[_zz_banks_12_port] <= _zz_banks_12_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_13_spinal_port0 <= banks_13[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_13_port_2) begin
      banks_13[_zz_banks_13_port] <= _zz_banks_13_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_14_spinal_port0 <= banks_14[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_14_port_2) begin
      banks_14[_zz_banks_14_port] <= _zz_banks_14_port_1;
    end
  end

  always @(posedge clk) begin
    if(bankRdEn) begin
      banks_15_spinal_port0 <= banks_15[bankRdAddr];
    end
  end

  always @(posedge clk) begin
    if(_zz_banks_15_port_2) begin
      banks_15[_zz_banks_15_port] <= _zz_banks_15_port_1;
    end
  end

  hng64_raster_StreamFifo_3 wq (
    .io_push_valid           (streamArbiter_io_output_valid               ), //i
    .io_push_ready           (wq_io_push_ready                            ), //o
    .io_push_payload_b_addr  (streamArbiter_io_output_payload_b_addr[27:0]), //i
    .io_push_payload_b_data  (streamArbiter_io_output_payload_b_data[63:0]), //i
    .io_push_payload_b_be    (streamArbiter_io_output_payload_b_be[7:0]   ), //i
    .io_push_payload_rel     (streamArbiter_io_output_payload_rel         ), //i
    .io_push_payload_relSlot (streamArbiter_io_output_payload_relSlot[2:0]), //i
    .io_pop_valid            (wq_io_pop_valid                             ), //o
    .io_pop_ready            (wq_io_pop_translated_ready                  ), //i
    .io_pop_payload_b_addr   (wq_io_pop_payload_b_addr[27:0]              ), //o
    .io_pop_payload_b_data   (wq_io_pop_payload_b_data[63:0]              ), //o
    .io_pop_payload_b_be     (wq_io_pop_payload_b_be[7:0]                 ), //o
    .io_pop_payload_rel      (wq_io_pop_payload_rel                       ), //o
    .io_pop_payload_relSlot  (wq_io_pop_payload_relSlot[2:0]              ), //o
    .io_flush                (1'b0                                        ), //i
    .io_occupancy            (wq_io_occupancy[4:0]                        ), //o
    .io_availability         (wq_io_availability[4:0]                     ), //o
    .clk                     (clk                                         ), //i
    .reset                   (reset                                       )  //i
  );
  hng64_raster_StreamArbiter streamArbiter (
    .io_inputs_0_valid           (backW_valid                                 ), //i
    .io_inputs_0_ready           (streamArbiter_io_inputs_0_ready             ), //o
    .io_inputs_0_payload_b_addr  (backW_payload_b_addr[27:0]                  ), //i
    .io_inputs_0_payload_b_data  (backW_payload_b_data[63:0]                  ), //i
    .io_inputs_0_payload_b_be    (backW_payload_b_be[7:0]                     ), //i
    .io_inputs_0_payload_rel     (backW_payload_rel                           ), //i
    .io_inputs_0_payload_relSlot (backW_payload_relSlot[2:0]                  ), //i
    .io_inputs_1_valid           (colourW_valid                               ), //i
    .io_inputs_1_ready           (streamArbiter_io_inputs_1_ready             ), //o
    .io_inputs_1_payload_b_addr  (colourW_payload_b_addr[27:0]                ), //i
    .io_inputs_1_payload_b_data  (colourW_payload_b_data[63:0]                ), //i
    .io_inputs_1_payload_b_be    (colourW_payload_b_be[7:0]                   ), //i
    .io_inputs_1_payload_rel     (colourW_payload_rel                         ), //i
    .io_inputs_1_payload_relSlot (colourW_payload_relSlot[2:0]                ), //i
    .io_inputs_2_valid           (clearW_valid                                ), //i
    .io_inputs_2_ready           (streamArbiter_io_inputs_2_ready             ), //o
    .io_inputs_2_payload_b_addr  (clearW_payload_b_addr[27:0]                 ), //i
    .io_inputs_2_payload_b_data  (clearW_payload_b_data[63:0]                 ), //i
    .io_inputs_2_payload_b_be    (clearW_payload_b_be[7:0]                    ), //i
    .io_inputs_2_payload_rel     (clearW_payload_rel                          ), //i
    .io_inputs_2_payload_relSlot (clearW_payload_relSlot[2:0]                 ), //i
    .io_output_valid             (streamArbiter_io_output_valid               ), //o
    .io_output_ready             (wq_io_push_ready                            ), //i
    .io_output_payload_b_addr    (streamArbiter_io_output_payload_b_addr[27:0]), //o
    .io_output_payload_b_data    (streamArbiter_io_output_payload_b_data[63:0]), //o
    .io_output_payload_b_be      (streamArbiter_io_output_payload_b_be[7:0]   ), //o
    .io_output_payload_rel       (streamArbiter_io_output_payload_rel         ), //o
    .io_output_payload_relSlot   (streamArbiter_io_output_payload_relSlot[2:0]), //o
    .io_chosen                   (streamArbiter_io_chosen[1:0]                ), //o
    .io_chosenOH                 (streamArbiter_io_chosenOH[2:0]              ), //o
    .clk                         (clk                                         ), //i
    .reset                       (reset                                       )  //i
  );
  hng64_raster_StreamFifo_4 frags (
    .io_push_valid            (fragIn_m2sPipe_valid                 ), //i
    .io_push_ready            (frags_io_push_ready                  ), //o
    .io_push_payload_f_x      (fragIn_m2sPipe_payload_f_x[8:0]      ), //i
    .io_push_payload_f_y      (fragIn_m2sPipe_payload_f_y[8:0]      ), //i
    .io_push_payload_f_z      (fragIn_m2sPipe_payload_f_z[23:0]     ), //i
    .io_push_payload_f_colour (fragIn_m2sPipe_payload_f_colour[15:0]), //i
    .io_push_payload_slot     (fragIn_m2sPipe_payload_slot[3:0]     ), //i
    .io_push_payload_miss     (fragIn_m2sPipe_payload_miss          ), //i
    .io_push_payload_victim   (fragIn_m2sPipe_payload_victim        ), //i
    .io_push_payload_vLine    (fragIn_m2sPipe_payload_vLine[13:0]   ), //i
    .io_push_payload_pend     (fragIn_m2sPipe_payload_pend[2:0]     ), //i
    .io_pop_valid             (frags_io_pop_valid                   ), //o
    .io_pop_ready             (go                                   ), //i
    .io_pop_payload_f_x       (frags_io_pop_payload_f_x[8:0]        ), //o
    .io_pop_payload_f_y       (frags_io_pop_payload_f_y[8:0]        ), //o
    .io_pop_payload_f_z       (frags_io_pop_payload_f_z[23:0]       ), //o
    .io_pop_payload_f_colour  (frags_io_pop_payload_f_colour[15:0]  ), //o
    .io_pop_payload_slot      (frags_io_pop_payload_slot[3:0]       ), //o
    .io_pop_payload_miss      (frags_io_pop_payload_miss            ), //o
    .io_pop_payload_victim    (frags_io_pop_payload_victim          ), //o
    .io_pop_payload_vLine     (frags_io_pop_payload_vLine[13:0]     ), //o
    .io_pop_payload_pend      (frags_io_pop_payload_pend[2:0]       ), //o
    .io_flush                 (1'b0                                 ), //i
    .io_occupancy             (frags_io_occupancy[6:0]              ), //o
    .io_availability          (frags_io_availability[6:0]           ), //o
    .clk                      (clk                                  ), //i
    .reset                    (reset                                )  //i
  );
  hng64_raster_StreamFifo_5 missQ (
    .io_push_valid   (missQ_io_push_valid       ), //i
    .io_push_ready   (missQ_io_push_ready       ), //o
    .io_push_payload (line[13:0]                ), //i
    .io_pop_valid    (missQ_io_pop_valid        ), //o
    .io_pop_ready    (missQ_io_pop_ready        ), //i
    .io_pop_payload  (missQ_io_pop_payload[13:0]), //o
    .io_flush        (1'b0                      ), //i
    .io_occupancy    (missQ_io_occupancy[3:0]   ), //o
    .io_availability (missQ_io_availability[3:0]), //o
    .clk             (clk                       ), //i
    .reset           (reset                     )  //i
  );
  hng64_raster_StreamFifo_6 lineQ (
    .io_push_valid   (lineQ_io_push_valid         ), //i
    .io_push_ready   (lineQ_io_push_ready         ), //o
    .io_push_payload (lineQ_io_push_payload[511:0]), //i
    .io_pop_valid    (lineQ_io_pop_valid          ), //o
    .io_pop_ready    (lineQ_io_pop_ready          ), //i
    .io_pop_payload  (lineQ_io_pop_payload[511:0] ), //o
    .io_flush        (1'b0                        ), //i
    .io_occupancy    (lineQ_io_occupancy[3:0]     ), //o
    .io_availability (lineQ_io_availability[3:0]  ), //o
    .clk             (clk                         ), //i
    .reset           (reset                       )  //i
  );
  always @(*) begin
    case(_zz_hitW_0_1)
      4'b0000 : _zz_hitW_0 = tValid_0;
      4'b0001 : _zz_hitW_0 = tValid_1;
      4'b0010 : _zz_hitW_0 = tValid_2;
      4'b0011 : _zz_hitW_0 = tValid_3;
      4'b0100 : _zz_hitW_0 = tValid_4;
      4'b0101 : _zz_hitW_0 = tValid_5;
      4'b0110 : _zz_hitW_0 = tValid_6;
      4'b0111 : _zz_hitW_0 = tValid_7;
      4'b1000 : _zz_hitW_0 = tValid_8;
      4'b1001 : _zz_hitW_0 = tValid_9;
      4'b1010 : _zz_hitW_0 = tValid_10;
      4'b1011 : _zz_hitW_0 = tValid_11;
      4'b1100 : _zz_hitW_0 = tValid_12;
      4'b1101 : _zz_hitW_0 = tValid_13;
      4'b1110 : _zz_hitW_0 = tValid_14;
      default : _zz_hitW_0 = tValid_15;
    endcase
  end

  always @(*) begin
    case(_zz_hitW_0_3)
      4'b0000 : _zz_hitW_0_2 = tTag_0;
      4'b0001 : _zz_hitW_0_2 = tTag_1;
      4'b0010 : _zz_hitW_0_2 = tTag_2;
      4'b0011 : _zz_hitW_0_2 = tTag_3;
      4'b0100 : _zz_hitW_0_2 = tTag_4;
      4'b0101 : _zz_hitW_0_2 = tTag_5;
      4'b0110 : _zz_hitW_0_2 = tTag_6;
      4'b0111 : _zz_hitW_0_2 = tTag_7;
      4'b1000 : _zz_hitW_0_2 = tTag_8;
      4'b1001 : _zz_hitW_0_2 = tTag_9;
      4'b1010 : _zz_hitW_0_2 = tTag_10;
      4'b1011 : _zz_hitW_0_2 = tTag_11;
      4'b1100 : _zz_hitW_0_2 = tTag_12;
      4'b1101 : _zz_hitW_0_2 = tTag_13;
      4'b1110 : _zz_hitW_0_2 = tTag_14;
      default : _zz_hitW_0_2 = tTag_15;
    endcase
  end

  always @(*) begin
    case(_zz_hitW_1_1)
      4'b0000 : _zz_hitW_1 = tValid_0;
      4'b0001 : _zz_hitW_1 = tValid_1;
      4'b0010 : _zz_hitW_1 = tValid_2;
      4'b0011 : _zz_hitW_1 = tValid_3;
      4'b0100 : _zz_hitW_1 = tValid_4;
      4'b0101 : _zz_hitW_1 = tValid_5;
      4'b0110 : _zz_hitW_1 = tValid_6;
      4'b0111 : _zz_hitW_1 = tValid_7;
      4'b1000 : _zz_hitW_1 = tValid_8;
      4'b1001 : _zz_hitW_1 = tValid_9;
      4'b1010 : _zz_hitW_1 = tValid_10;
      4'b1011 : _zz_hitW_1 = tValid_11;
      4'b1100 : _zz_hitW_1 = tValid_12;
      4'b1101 : _zz_hitW_1 = tValid_13;
      4'b1110 : _zz_hitW_1 = tValid_14;
      default : _zz_hitW_1 = tValid_15;
    endcase
  end

  always @(*) begin
    case(_zz_hitW_1_3)
      4'b0000 : _zz_hitW_1_2 = tTag_0;
      4'b0001 : _zz_hitW_1_2 = tTag_1;
      4'b0010 : _zz_hitW_1_2 = tTag_2;
      4'b0011 : _zz_hitW_1_2 = tTag_3;
      4'b0100 : _zz_hitW_1_2 = tTag_4;
      4'b0101 : _zz_hitW_1_2 = tTag_5;
      4'b0110 : _zz_hitW_1_2 = tTag_6;
      4'b0111 : _zz_hitW_1_2 = tTag_7;
      4'b1000 : _zz_hitW_1_2 = tTag_8;
      4'b1001 : _zz_hitW_1_2 = tTag_9;
      4'b1010 : _zz_hitW_1_2 = tTag_10;
      4'b1011 : _zz_hitW_1_2 = tTag_11;
      4'b1100 : _zz_hitW_1_2 = tTag_12;
      4'b1101 : _zz_hitW_1_2 = tTag_13;
      4'b1110 : _zz_hitW_1_2 = tTag_14;
      default : _zz_hitW_1_2 = tTag_15;
    endcase
  end

  always @(*) begin
    case(set)
      3'b000 : _zz__zz_way = lru_0;
      3'b001 : _zz__zz_way = lru_1;
      3'b010 : _zz__zz_way = lru_2;
      3'b011 : _zz__zz_way = lru_3;
      3'b100 : _zz__zz_way = lru_4;
      3'b101 : _zz__zz_way = lru_5;
      3'b110 : _zz__zz_way = lru_6;
      default : _zz__zz_way = lru_7;
    endcase
  end

  always @(*) begin
    case(slot)
      4'b0000 : begin
        _zz_vValid = tValid_0;
        _zz_vLine = tTag_0;
      end
      4'b0001 : begin
        _zz_vValid = tValid_1;
        _zz_vLine = tTag_1;
      end
      4'b0010 : begin
        _zz_vValid = tValid_2;
        _zz_vLine = tTag_2;
      end
      4'b0011 : begin
        _zz_vValid = tValid_3;
        _zz_vLine = tTag_3;
      end
      4'b0100 : begin
        _zz_vValid = tValid_4;
        _zz_vLine = tTag_4;
      end
      4'b0101 : begin
        _zz_vValid = tValid_5;
        _zz_vLine = tTag_5;
      end
      4'b0110 : begin
        _zz_vValid = tValid_6;
        _zz_vLine = tTag_6;
      end
      4'b0111 : begin
        _zz_vValid = tValid_7;
        _zz_vLine = tTag_7;
      end
      4'b1000 : begin
        _zz_vValid = tValid_8;
        _zz_vLine = tTag_8;
      end
      4'b1001 : begin
        _zz_vValid = tValid_9;
        _zz_vLine = tTag_9;
      end
      4'b1010 : begin
        _zz_vValid = tValid_10;
        _zz_vLine = tTag_10;
      end
      4'b1011 : begin
        _zz_vValid = tValid_11;
        _zz_vLine = tTag_11;
      end
      4'b1100 : begin
        _zz_vValid = tValid_12;
        _zz_vLine = tTag_12;
      end
      4'b1101 : begin
        _zz_vValid = tValid_13;
        _zz_vLine = tTag_13;
      end
      4'b1110 : begin
        _zz_vValid = tValid_14;
        _zz_vLine = tTag_14;
      end
      default : begin
        _zz_vValid = tValid_15;
        _zz_vLine = tTag_15;
      end
    endcase
  end

  always @(*) begin
    case(mSlot)
      4'b0000 : begin
        _zz__zz_pVic_0 = tValid_0;
        _zz__zz_pLine_0 = tTag_0;
      end
      4'b0001 : begin
        _zz__zz_pVic_0 = tValid_1;
        _zz__zz_pLine_0 = tTag_1;
      end
      4'b0010 : begin
        _zz__zz_pVic_0 = tValid_2;
        _zz__zz_pLine_0 = tTag_2;
      end
      4'b0011 : begin
        _zz__zz_pVic_0 = tValid_3;
        _zz__zz_pLine_0 = tTag_3;
      end
      4'b0100 : begin
        _zz__zz_pVic_0 = tValid_4;
        _zz__zz_pLine_0 = tTag_4;
      end
      4'b0101 : begin
        _zz__zz_pVic_0 = tValid_5;
        _zz__zz_pLine_0 = tTag_5;
      end
      4'b0110 : begin
        _zz__zz_pVic_0 = tValid_6;
        _zz__zz_pLine_0 = tTag_6;
      end
      4'b0111 : begin
        _zz__zz_pVic_0 = tValid_7;
        _zz__zz_pLine_0 = tTag_7;
      end
      4'b1000 : begin
        _zz__zz_pVic_0 = tValid_8;
        _zz__zz_pLine_0 = tTag_8;
      end
      4'b1001 : begin
        _zz__zz_pVic_0 = tValid_9;
        _zz__zz_pLine_0 = tTag_9;
      end
      4'b1010 : begin
        _zz__zz_pVic_0 = tValid_10;
        _zz__zz_pLine_0 = tTag_10;
      end
      4'b1011 : begin
        _zz__zz_pVic_0 = tValid_11;
        _zz__zz_pLine_0 = tTag_11;
      end
      4'b1100 : begin
        _zz__zz_pVic_0 = tValid_12;
        _zz__zz_pLine_0 = tTag_12;
      end
      4'b1101 : begin
        _zz__zz_pVic_0 = tValid_13;
        _zz__zz_pLine_0 = tTag_13;
      end
      4'b1110 : begin
        _zz__zz_pVic_0 = tValid_14;
        _zz__zz_pLine_0 = tTag_14;
      end
      default : begin
        _zz__zz_pVic_0 = tValid_15;
        _zz__zz_pLine_0 = tTag_15;
      end
    endcase
  end

  always @(*) begin
    case(frags_io_pop_payload_slot)
      4'b0000 : _zz__zz_vLeft = dirty_0;
      4'b0001 : _zz__zz_vLeft = dirty_1;
      4'b0010 : _zz__zz_vLeft = dirty_2;
      4'b0011 : _zz__zz_vLeft = dirty_3;
      4'b0100 : _zz__zz_vLeft = dirty_4;
      4'b0101 : _zz__zz_vLeft = dirty_5;
      4'b0110 : _zz__zz_vLeft = dirty_6;
      4'b0111 : _zz__zz_vLeft = dirty_7;
      4'b1000 : _zz__zz_vLeft = dirty_8;
      4'b1001 : _zz__zz_vLeft = dirty_9;
      4'b1010 : _zz__zz_vLeft = dirty_10;
      4'b1011 : _zz__zz_vLeft = dirty_11;
      4'b1100 : _zz__zz_vLeft = dirty_12;
      4'b1101 : _zz__zz_vLeft = dirty_13;
      4'b1110 : _zz__zz_vLeft = dirty_14;
      default : _zz__zz_vLeft = dirty_15;
    endcase
  end

  always @(*) begin
    case(_zz_backW_payload_b_data_1)
      3'b000 : _zz_backW_payload_b_data = vBuf_0;
      3'b001 : _zz_backW_payload_b_data = vBuf_1;
      3'b010 : _zz_backW_payload_b_data = vBuf_2;
      3'b011 : _zz_backW_payload_b_data = vBuf_3;
      3'b100 : _zz_backW_payload_b_data = vBuf_4;
      3'b101 : _zz_backW_payload_b_data = vBuf_5;
      3'b110 : _zz_backW_payload_b_data = vBuf_6;
      default : _zz_backW_payload_b_data = vBuf_7;
    endcase
  end

  always @(*) begin
    case(px)
      4'b0000 : _zz_readWord = bankRd_0;
      4'b0001 : _zz_readWord = bankRd_1;
      4'b0010 : _zz_readWord = bankRd_2;
      4'b0011 : _zz_readWord = bankRd_3;
      4'b0100 : _zz_readWord = bankRd_4;
      4'b0101 : _zz_readWord = bankRd_5;
      4'b0110 : _zz_readWord = bankRd_6;
      4'b0111 : _zz_readWord = bankRd_7;
      4'b1000 : _zz_readWord = bankRd_8;
      4'b1001 : _zz_readWord = bankRd_9;
      4'b1010 : _zz_readWord = bankRd_10;
      4'b1011 : _zz_readWord = bankRd_11;
      4'b1100 : _zz_readWord = bankRd_12;
      4'b1101 : _zz_readWord = bankRd_13;
      4'b1110 : _zz_readWord = bankRd_14;
      default : _zz_readWord = bankRd_15;
    endcase
  end

  always @(*) begin
    case(fBeat)
      3'b000 : begin
        _zz__zz_colourW_valid = cBe_0;
        _zz_colourW_payload_b_data = cData_0;
      end
      3'b001 : begin
        _zz__zz_colourW_valid = cBe_1;
        _zz_colourW_payload_b_data = cData_1;
      end
      3'b010 : begin
        _zz__zz_colourW_valid = cBe_2;
        _zz_colourW_payload_b_data = cData_2;
      end
      3'b011 : begin
        _zz__zz_colourW_valid = cBe_3;
        _zz_colourW_payload_b_data = cData_3;
      end
      3'b100 : begin
        _zz__zz_colourW_valid = cBe_4;
        _zz_colourW_payload_b_data = cData_4;
      end
      3'b101 : begin
        _zz__zz_colourW_valid = cBe_5;
        _zz_colourW_payload_b_data = cData_5;
      end
      3'b110 : begin
        _zz__zz_colourW_valid = cBe_6;
        _zz_colourW_payload_b_data = cData_6;
      end
      default : begin
        _zz__zz_colourW_valid = cBe_7;
        _zz_colourW_payload_b_data = cData_7;
      end
    endcase
  end

  always @(*) begin
    case(_zz_when_RenderBuf_l418_1)
      4'b0000 : _zz_when_RenderBuf_l418 = tValid_0;
      4'b0001 : _zz_when_RenderBuf_l418 = tValid_1;
      4'b0010 : _zz_when_RenderBuf_l418 = tValid_2;
      4'b0011 : _zz_when_RenderBuf_l418 = tValid_3;
      4'b0100 : _zz_when_RenderBuf_l418 = tValid_4;
      4'b0101 : _zz_when_RenderBuf_l418 = tValid_5;
      4'b0110 : _zz_when_RenderBuf_l418 = tValid_6;
      4'b0111 : _zz_when_RenderBuf_l418 = tValid_7;
      4'b1000 : _zz_when_RenderBuf_l418 = tValid_8;
      4'b1001 : _zz_when_RenderBuf_l418 = tValid_9;
      4'b1010 : _zz_when_RenderBuf_l418 = tValid_10;
      4'b1011 : _zz_when_RenderBuf_l418 = tValid_11;
      4'b1100 : _zz_when_RenderBuf_l418 = tValid_12;
      4'b1101 : _zz_when_RenderBuf_l418 = tValid_13;
      4'b1110 : _zz_when_RenderBuf_l418 = tValid_14;
      default : _zz_when_RenderBuf_l418 = tValid_15;
    endcase
  end

  always @(*) begin
    case(_zz_when_RenderBuf_l418_3)
      4'b0000 : _zz_when_RenderBuf_l418_2 = dirty_0;
      4'b0001 : _zz_when_RenderBuf_l418_2 = dirty_1;
      4'b0010 : _zz_when_RenderBuf_l418_2 = dirty_2;
      4'b0011 : _zz_when_RenderBuf_l418_2 = dirty_3;
      4'b0100 : _zz_when_RenderBuf_l418_2 = dirty_4;
      4'b0101 : _zz_when_RenderBuf_l418_2 = dirty_5;
      4'b0110 : _zz_when_RenderBuf_l418_2 = dirty_6;
      4'b0111 : _zz_when_RenderBuf_l418_2 = dirty_7;
      4'b1000 : _zz_when_RenderBuf_l418_2 = dirty_8;
      4'b1001 : _zz_when_RenderBuf_l418_2 = dirty_9;
      4'b1010 : _zz_when_RenderBuf_l418_2 = dirty_10;
      4'b1011 : _zz_when_RenderBuf_l418_2 = dirty_11;
      4'b1100 : _zz_when_RenderBuf_l418_2 = dirty_12;
      4'b1101 : _zz_when_RenderBuf_l418_2 = dirty_13;
      4'b1110 : _zz_when_RenderBuf_l418_2 = dirty_14;
      default : _zz_when_RenderBuf_l418_2 = dirty_15;
    endcase
  end

  always @(*) begin
    case(_zz_vAddr)
      4'b0000 : _zz_vAddr_1 = tTag_0;
      4'b0001 : _zz_vAddr_1 = tTag_1;
      4'b0010 : _zz_vAddr_1 = tTag_2;
      4'b0011 : _zz_vAddr_1 = tTag_3;
      4'b0100 : _zz_vAddr_1 = tTag_4;
      4'b0101 : _zz_vAddr_1 = tTag_5;
      4'b0110 : _zz_vAddr_1 = tTag_6;
      4'b0111 : _zz_vAddr_1 = tTag_7;
      4'b1000 : _zz_vAddr_1 = tTag_8;
      4'b1001 : _zz_vAddr_1 = tTag_9;
      4'b1010 : _zz_vAddr_1 = tTag_10;
      4'b1011 : _zz_vAddr_1 = tTag_11;
      4'b1100 : _zz_vAddr_1 = tTag_12;
      4'b1101 : _zz_vAddr_1 = tTag_13;
      4'b1110 : _zz_vAddr_1 = tTag_14;
      default : _zz_vAddr_1 = tTag_15;
    endcase
  end

  `ifndef SYNTHESIS
  always @(*) begin
    case(fs)
      hng64_raster_F_Idle : fs_string = "Idle  ";
      hng64_raster_F_Clear : fs_string = "Clear ";
      hng64_raster_F_Scrub : fs_string = "Scrub ";
      hng64_raster_F_Render : fs_string = "Render";
      hng64_raster_F_Drain : fs_string = "Drain ";
      hng64_raster_F_Flush : fs_string = "Flush ";
      hng64_raster_F_Done : fs_string = "Done  ";
      default : fs_string = "??????";
    endcase
  end
  always @(*) begin
    case(hs)
      hng64_raster_H_Wait_1 : hs_string = "Wait_1    ";
      hng64_raster_H_ReadVictim : hs_string = "ReadVictim";
      hng64_raster_H_Fill : hs_string = "Fill      ";
      default : hs_string = "??????????";
    endcase
  end
  `endif

  always @(*) begin
    io_done = 1'b0;
    if(when_RenderBuf_l439) begin
      io_done = 1'b1;
    end
  end

  assign when_RenderBuf_l62 = ((fs == hng64_raster_F_Idle) && io_start);
  assign backW_ready = streamArbiter_io_inputs_0_ready;
  assign colourW_ready = streamArbiter_io_inputs_1_ready;
  assign clearW_ready = streamArbiter_io_inputs_2_ready;
  assign wq_io_pop_translated_valid = wq_io_pop_valid;
  assign wq_io_pop_translated_payload_addr = wq_io_pop_payload_b_addr;
  assign wq_io_pop_translated_payload_data = wq_io_pop_payload_b_data;
  assign wq_io_pop_translated_payload_be = wq_io_pop_payload_b_be;
  assign io_wr_valid = wq_io_pop_translated_valid;
  assign wq_io_pop_translated_ready = io_wr_ready;
  assign io_wr_payload_addr = wq_io_pop_translated_payload_addr;
  assign io_wr_payload_data = wq_io_pop_translated_payload_data;
  assign io_wr_payload_be = wq_io_pop_translated_payload_be;
  assign io_urgent = (5'h08 <= wq_io_occupancy);
  assign stale = _zz_stale;
  assign clearW_valid = ((fs == hng64_raster_F_Clear) || (fs == hng64_raster_F_Scrub));
  assign clearW_payload_rel = 1'b0;
  assign clearW_payload_relSlot = 3'b000;
  assign clearW_payload_b_addr = ((fs == hng64_raster_F_Clear) ? _zz_clearW_payload_b_addr : _zz_clearW_payload_b_addr_3);
  assign clearW_payload_b_data = ((fs == hng64_raster_F_Clear) ? 64'h0 : {{{stale,24'h0},stale},24'h0});
  assign clearW_payload_b_be = 8'hff;
  assign clearW_fire = (clearW_valid && clearW_ready);
  assign when_RenderBuf_l94 = ((fs == hng64_raster_F_Clear) && (count == 18'h0ffff));
  assign when_RenderBuf_l98 = ((fs == hng64_raster_F_Scrub) && ((full && (count == 18'h1ffff)) || ((! full) && (count == 18'h003ff))));
  assign when_Stream_l581 = ((! io_i_payload_f_flat) && ((io_i_payload_f_tex4bpp ? _zz_when_Stream_l581 : io_i_payload_texel) == 8'h0));
  always @(*) begin
    io_i_throwWhen_valid = io_i_valid;
    if(when_Stream_l581) begin
      io_i_throwWhen_valid = 1'b0;
    end
  end

  always @(*) begin
    io_i_ready = io_i_throwWhen_ready;
    if(when_Stream_l581) begin
      io_i_ready = 1'b1;
    end
  end

  assign io_i_throwWhen_payload_f_x = io_i_payload_f_x;
  assign io_i_throwWhen_payload_f_y = io_i_payload_f_y;
  assign io_i_throwWhen_payload_f_z = io_i_payload_f_z;
  assign io_i_throwWhen_payload_f_addr = io_i_payload_f_addr;
  assign io_i_throwWhen_payload_f_nib = io_i_payload_f_nib;
  assign io_i_throwWhen_payload_f_light = io_i_payload_f_light;
  assign io_i_throwWhen_payload_f_flat = io_i_payload_f_flat;
  assign io_i_throwWhen_payload_f_blend = io_i_payload_f_blend;
  assign io_i_throwWhen_payload_f_tex4bpp = io_i_payload_f_tex4bpp;
  assign io_i_throwWhen_payload_f_pal = io_i_payload_f_pal;
  assign io_i_throwWhen_payload_texel = io_i_payload_texel;
  assign _zz_io_i_throwWhen_map_payload_z = (io_i_throwWhen_payload_f_z >>> 3'd4);
  assign io_i_throwWhen_map_valid = io_i_throwWhen_valid;
  assign io_i_throwWhen_ready = io_i_throwWhen_map_ready;
  assign io_i_throwWhen_map_payload_x = io_i_throwWhen_payload_f_x;
  assign io_i_throwWhen_map_payload_y = io_i_throwWhen_payload_f_y;
  assign io_i_throwWhen_map_payload_z = (($signed(_zz_io_i_throwWhen_map_payload_z) < $signed(26'h0)) ? 24'h0 : (($signed(26'h1000000) <= $signed(_zz_io_i_throwWhen_map_payload_z)) ? 24'hffffff : _zz_io_i_throwWhen_map_payload_z_1));
  assign io_i_throwWhen_map_payload_colour = (io_i_throwWhen_payload_f_flat ? io_i_throwWhen_payload_f_pal : {{io_i_throwWhen_payload_f_light[3 : 0],io_i_throwWhen_payload_f_blend},_zz_io_i_throwWhen_map_payload_colour});
  always @(*) begin
    io_i_throwWhen_map_ready = io_i_throwWhen_map_m2sPipe_ready;
    if(when_Stream_l477) begin
      io_i_throwWhen_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! io_i_throwWhen_map_m2sPipe_valid);
  assign io_i_throwWhen_map_m2sPipe_valid = io_i_throwWhen_map_rValid;
  assign io_i_throwWhen_map_m2sPipe_payload_x = io_i_throwWhen_map_rData_x;
  assign io_i_throwWhen_map_m2sPipe_payload_y = io_i_throwWhen_map_rData_y;
  assign io_i_throwWhen_map_m2sPipe_payload_z = io_i_throwWhen_map_rData_z;
  assign io_i_throwWhen_map_m2sPipe_payload_colour = io_i_throwWhen_map_rData_colour;
  assign _zz_io_i_throwWhen_map_m2sPipe_ready = (! (fs != hng64_raster_F_Render));
  assign prep_valid = (io_i_throwWhen_map_m2sPipe_valid && _zz_io_i_throwWhen_map_m2sPipe_ready);
  assign io_i_throwWhen_map_m2sPipe_ready = (prep_ready && _zz_io_i_throwWhen_map_m2sPipe_ready);
  assign prep_payload_x = io_i_throwWhen_map_m2sPipe_payload_x;
  assign prep_payload_y = io_i_throwWhen_map_m2sPipe_payload_y;
  assign prep_payload_z = io_i_throwWhen_map_m2sPipe_payload_z;
  assign prep_payload_colour = io_i_throwWhen_map_m2sPipe_payload_colour;
  assign line = {prep_payload_y,prep_payload_x[8 : 4]};
  assign set = line[2 : 0];
  assign ltag = line[13 : 3];
  assign hitW_0 = (_zz_hitW_0 && (_zz_hitW_0_2 == ltag));
  assign hitW_1 = (_zz_hitW_1 && (_zz_hitW_1_2 == ltag));
  assign hit = (|{hitW_1,hitW_0});
  assign _zz_way = _zz__zz_way;
  assign _zz_1 = ({7'd0,1'b1} <<< set);
  assign way = (hit ? hitW_1 : _zz_way);
  assign slot = {set,way};
  assign vValid = _zz_vValid;
  assign _zz_2 = ({15'd0,1'b1} <<< slot);
  assign _zz_3 = ({15'd0,1'b1} <<< slot);
  assign vLine = {_zz_vLine,set};
  assign pendingHit = (|{((pOcc_7 && pVic_7) && (pLine_7 == line)),{((pOcc_6 && pVic_6) && (pLine_6 == line)),{((pOcc_5 && pVic_5) && (pLine_5 == line)),{(_zz_pendingHit && _zz_pendingHit_1),{_zz_pendingHit_2,{_zz_pendingHit_3,_zz_pendingHit_4}}}}}});
  assign free = {(! pOcc_7),{(! pOcc_6),{(! pOcc_5),{(! pOcc_4),{(! pOcc_3),{(! pOcc_2),{(! pOcc_1),(! pOcc_0)}}}}}}};
  assign free_ohFirst_input = free;
  assign free_ohFirst_masked = (free_ohFirst_input & (~ _zz_free_ohFirst_masked));
  assign free_ohFirst_value = free_ohFirst_masked;
  assign _zz_freeSlot = free_ohFirst_value[3];
  assign _zz_freeSlot_1 = free_ohFirst_value[5];
  assign _zz_freeSlot_2 = free_ohFirst_value[6];
  assign _zz_freeSlot_3 = free_ohFirst_value[7];
  assign _zz_freeSlot_4 = (((free_ohFirst_value[1] || _zz_freeSlot) || _zz_freeSlot_1) || _zz_freeSlot_3);
  assign _zz_freeSlot_5 = (((free_ohFirst_value[2] || _zz_freeSlot) || _zz_freeSlot_2) || _zz_freeSlot_3);
  assign _zz_freeSlot_6 = (((free_ohFirst_value[4] || _zz_freeSlot_1) || _zz_freeSlot_2) || _zz_freeSlot_3);
  assign freeSlot = {_zz_freeSlot_6,{_zz_freeSlot_5,_zz_freeSlot_4}};
  always @(*) begin
    fragIn_ready = fragIn_m2sPipe_ready;
    if(when_Stream_l477_1) begin
      fragIn_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! fragIn_m2sPipe_valid);
  assign fragIn_m2sPipe_valid = fragIn_rValid;
  assign fragIn_m2sPipe_payload_f_x = fragIn_rData_f_x;
  assign fragIn_m2sPipe_payload_f_y = fragIn_rData_f_y;
  assign fragIn_m2sPipe_payload_f_z = fragIn_rData_f_z;
  assign fragIn_m2sPipe_payload_f_colour = fragIn_rData_f_colour;
  assign fragIn_m2sPipe_payload_slot = fragIn_rData_slot;
  assign fragIn_m2sPipe_payload_miss = fragIn_rData_miss;
  assign fragIn_m2sPipe_payload_victim = fragIn_rData_victim;
  assign fragIn_m2sPipe_payload_vLine = fragIn_rData_vLine;
  assign fragIn_m2sPipe_payload_pend = fragIn_rData_pend;
  assign fragIn_m2sPipe_ready = frags_io_push_ready;
  assign canGo = (fragIn_ready && (hit || ((((! pendingHit) && (|free)) && (credits != 4'b0000)) && missQ_io_push_ready)));
  assign prep_ready = canGo;
  assign fragIn_valid = (prep_valid && canGo);
  assign fragIn_payload_f_x = prep_payload_x;
  assign fragIn_payload_f_y = prep_payload_y;
  assign fragIn_payload_f_z = prep_payload_z;
  assign fragIn_payload_f_colour = prep_payload_colour;
  assign fragIn_payload_slot = slot;
  assign fragIn_payload_miss = (! hit);
  assign fragIn_payload_victim = vValid;
  assign fragIn_payload_vLine = vLine;
  assign fragIn_payload_pend = freeSlot;
  assign missQ_io_push_valid = ((prep_valid && canGo) && (! hit));
  assign prep_fire = (prep_valid && prep_ready);
  assign allocate = (prep_fire && (! hit));
  assign mSlot = {set,_zz_way};
  assign when_RenderBuf_l177 = (! pOcc_0);
  assign _zz_pVic_0 = _zz__zz_pVic_0;
  assign _zz_pLine_0 = _zz__zz_pLine_0;
  assign when_RenderBuf_l177_1 = (! pOcc_1);
  assign when_RenderBuf_l177_2 = (! pOcc_2);
  assign when_RenderBuf_l177_3 = (! pOcc_3);
  assign when_RenderBuf_l177_4 = (! pOcc_4);
  assign when_RenderBuf_l177_5 = (! pOcc_5);
  assign when_RenderBuf_l177_6 = (! pOcc_6);
  assign when_RenderBuf_l177_7 = (! pOcc_7);
  assign _zz_lru_0 = (! way[0]);
  assign when_RenderBuf_l183 = (! hit);
  assign _zz_4 = ({7'd0,1'b1} <<< freeSlot);
  assign _zz_5 = ({7'd0,1'b1} <<< release_payload);
  assign _zz_6 = ({7'd0,1'b1} <<< releaseWb_payload);
  assign io_rdAddr_valid = missQ_io_pop_valid;
  assign io_rdAddr_payload = (dBase + _zz_io_rdAddr_payload);
  assign missQ_io_pop_ready = (io_rdAddr_ready && (beat == 3'b111));
  assign io_rdAddr_fire = (io_rdAddr_valid && io_rdAddr_ready);
  assign lineQ_io_push_valid = (io_rdData_valid && (gBeat == 3'b111));
  assign lineQ_io_push_payload = {io_rdData_payload,{{{{{{gather_6,gather_5},gather_4},gather_3},gather_2},gather_1},gather_0}};
  assign _zz_7 = ({7'd0,1'b1} <<< gBeat);
  assign rIdle = (((! rValid) && (! sValidW)) && (! cValidW));
  assign bankRd_0 = banks_0_spinal_port0;
  assign bankRd_1 = banks_1_spinal_port0;
  assign bankRd_2 = banks_2_spinal_port0;
  assign bankRd_3 = banks_3_spinal_port0;
  assign bankRd_4 = banks_4_spinal_port0;
  assign bankRd_5 = banks_5_spinal_port0;
  assign bankRd_6 = banks_6_spinal_port0;
  assign bankRd_7 = banks_7_spinal_port0;
  assign bankRd_8 = banks_8_spinal_port0;
  assign bankRd_9 = banks_9_spinal_port0;
  assign bankRd_10 = banks_10_spinal_port0;
  assign bankRd_11 = banks_11_spinal_port0;
  assign bankRd_12 = banks_12_spinal_port0;
  assign bankRd_13 = banks_13_spinal_port0;
  assign bankRd_14 = banks_14_spinal_port0;
  assign bankRd_15 = banks_15_spinal_port0;
  always @(*) begin
    consume = 1'b0;
    if(when_RenderBuf_l257) begin
      consume = 1'b1;
    end
  end

  always @(*) begin
    release_valid = 1'b0;
    if(when_RenderBuf_l257) begin
      if(when_RenderBuf_l264) begin
        release_valid = 1'b1;
      end
    end
  end

  always @(*) begin
    release_payload = vPend;
    if(when_RenderBuf_l257) begin
      if(when_RenderBuf_l264) begin
        release_payload = frags_io_pop_payload_pend;
      end
    end
  end

  always @(*) begin
    lineQ_io_pop_ready = 1'b0;
    if(when_RenderBuf_l257) begin
      lineQ_io_pop_ready = 1'b1;
    end
  end

  assign needFill = ((frags_io_pop_valid && frags_io_pop_payload_miss) && (! filled));
  always @(*) begin
    bankRdAddr = (go ? frags_io_pop_payload_slot : rF_slot);
    if(when_RenderBuf_l252) begin
      bankRdAddr = frags_io_pop_payload_slot;
    end
    if(when_RenderBuf_l415) begin
      if(!when_RenderBuf_l416) begin
        if(when_RenderBuf_l418) begin
          bankRdAddr = flushSlot[3 : 0];
        end
      end
    end
  end

  always @(*) begin
    bankRdEn = (go || rValid);
    if(when_RenderBuf_l252) begin
      bankRdEn = 1'b1;
    end
    if(when_RenderBuf_l415) begin
      if(!when_RenderBuf_l416) begin
        if(when_RenderBuf_l418) begin
          bankRdEn = 1'b1;
        end
      end
    end
  end

  assign when_RenderBuf_l252 = (((((hs == hng64_raster_H_Wait_1) && needFill) && lineQ_io_pop_valid) && (vLeft == 4'b0000)) && rIdle);
  assign when_RenderBuf_l257 = (hs == hng64_raster_H_ReadVictim);
  assign _zz_24 = ({15'd0,1'b1} <<< frags_io_pop_payload_slot);
  assign _zz_vLeft = (frags_io_pop_payload_victim && _zz__zz_vLeft);
  assign when_RenderBuf_l264 = (! _zz_vLeft);
  assign backW_valid = (vLeft != 4'b0000);
  assign backW_payload_b_addr = (dBase + _zz_backW_payload_b_addr);
  assign backW_payload_b_data = _zz_backW_payload_b_data;
  assign backW_payload_b_be = 8'hff;
  assign backW_payload_rel = ((vLeft == 4'b0001) && vRelease);
  assign backW_payload_relSlot = vPend;
  assign backW_fire = (backW_valid && backW_ready);
  assign io_wr_fire = (io_wr_valid && io_wr_ready);
  assign releaseWb_valid = (io_wr_fire && wq_io_pop_payload_rel);
  assign releaseWb_payload = wq_io_pop_payload_relSlot;
  assign cDone = (((! cValid) || (! cPass)) || comb_ready);
  assign sMove = (sValid && cDone);
  assign sFree = ((! sValid) || cDone);
  assign rMove = (rValid && sFree);
  assign rFree = ((! rValid) || sFree);
  assign go = ((((frags_io_pop_valid && ((! frags_io_pop_payload_miss) || filled)) && (hs == hng64_raster_H_Wait_1)) && (! needFill)) && rFree);
  assign px = rF_f_x[3 : 0];
  assign readWord = _zz_readWord;
  always @(*) begin
    word = readWord;
    if(when_RenderBuf_l316) begin
      word = lastWord;
    end
    if(when_RenderBuf_l317) begin
      word = cWord;
    end
    if(when_RenderBuf_l318) begin
      word = sWord;
    end
  end

  assign when_RenderBuf_l316 = ((lastWr && (lastSlot == rF_slot)) && (lastPx == px));
  assign when_RenderBuf_l317 = (((cValid && cPass) && (cF_slot == rF_slot)) && (cF_f_x[3 : 0] == px));
  assign when_RenderBuf_l318 = (((sValid && sPass) && (sF_slot == rF_slot)) && (sF_f_x[3 : 0] == px));
  assign storedZ = ((word[31 : 24] == tag) ? _zz_storedZ : 25'h1000000);
  assign pass = (_zz_pass < storedZ);
  assign comb_valid = (cValid && cPass);
  assign comb_payload_pixel = {cF_f_y,cF_f_x};
  assign comb_payload_colour = cF_f_colour;
  assign fillNow = (hs == hng64_raster_H_ReadVictim);
  assign cWrite = ((cValid && cPass) && comb_ready);
  assign cPx = cF_f_x[3 : 0];
  assign _zz_41 = ({15'd0,1'b1} <<< cF_slot);
  assign sValidW = sValid;
  assign cValidW = cValid;
  assign cLineOf = comb_payload_pixel[17 : 5];
  assign needFlush = ((comb_valid && anyBe) && (cLineOf != cLine));
  assign frameFlush = ((fs == hng64_raster_F_Flush) && anyBe);
  assign when_RenderBuf_l377 = ((! flushing) && (needFlush || frameFlush));
  assign _zz_colourW_valid = _zz__zz_colourW_valid;
  assign _zz_42 = ({7'd0,1'b1} <<< fBeat);
  assign colourW_valid = (flushing && (|_zz_colourW_valid));
  assign colourW_payload_rel = 1'b0;
  assign colourW_payload_relSlot = 3'b000;
  assign colourW_payload_b_addr = (cBase + _zz_colourW_payload_b_addr);
  assign colourW_payload_b_data = _zz_colourW_payload_b_data;
  assign colourW_payload_b_be = _zz_colourW_valid;
  assign colourW_fire = (colourW_valid && colourW_ready);
  assign when_RenderBuf_l387 = (flushing && (colourW_fire || (! (|_zz_colourW_valid))));
  assign when_RenderBuf_l390 = (fBeat == 3'b111);
  assign comb_ready = ((! flushing) && (! needFlush));
  assign comb_fire = (comb_valid && comb_ready);
  assign _zz_when_RenderBuf_l398 = comb_payload_pixel[4 : 0];
  assign when_RenderBuf_l398 = (_zz_when_RenderBuf_l398 == 5'h0);
  assign when_RenderBuf_l398_1 = (_zz_when_RenderBuf_l398 == 5'h01);
  assign when_RenderBuf_l398_2 = (_zz_when_RenderBuf_l398 == 5'h02);
  assign when_RenderBuf_l398_3 = (_zz_when_RenderBuf_l398 == 5'h03);
  assign when_RenderBuf_l398_4 = (_zz_when_RenderBuf_l398 == 5'h04);
  assign when_RenderBuf_l398_5 = (_zz_when_RenderBuf_l398 == 5'h05);
  assign when_RenderBuf_l398_6 = (_zz_when_RenderBuf_l398 == 5'h06);
  assign when_RenderBuf_l398_7 = (_zz_when_RenderBuf_l398 == 5'h07);
  assign when_RenderBuf_l398_8 = (_zz_when_RenderBuf_l398 == 5'h08);
  assign when_RenderBuf_l398_9 = (_zz_when_RenderBuf_l398 == 5'h09);
  assign when_RenderBuf_l398_10 = (_zz_when_RenderBuf_l398 == 5'h0a);
  assign when_RenderBuf_l398_11 = (_zz_when_RenderBuf_l398 == 5'h0b);
  assign when_RenderBuf_l398_12 = (_zz_when_RenderBuf_l398 == 5'h0c);
  assign when_RenderBuf_l398_13 = (_zz_when_RenderBuf_l398 == 5'h0d);
  assign when_RenderBuf_l398_14 = (_zz_when_RenderBuf_l398 == 5'h0e);
  assign when_RenderBuf_l398_15 = (_zz_when_RenderBuf_l398 == 5'h0f);
  assign when_RenderBuf_l398_16 = (_zz_when_RenderBuf_l398 == 5'h10);
  assign when_RenderBuf_l398_17 = (_zz_when_RenderBuf_l398 == 5'h11);
  assign when_RenderBuf_l398_18 = (_zz_when_RenderBuf_l398 == 5'h12);
  assign when_RenderBuf_l398_19 = (_zz_when_RenderBuf_l398 == 5'h13);
  assign when_RenderBuf_l398_20 = (_zz_when_RenderBuf_l398 == 5'h14);
  assign when_RenderBuf_l398_21 = (_zz_when_RenderBuf_l398 == 5'h15);
  assign when_RenderBuf_l398_22 = (_zz_when_RenderBuf_l398 == 5'h16);
  assign when_RenderBuf_l398_23 = (_zz_when_RenderBuf_l398 == 5'h17);
  assign when_RenderBuf_l398_24 = (_zz_when_RenderBuf_l398 == 5'h18);
  assign when_RenderBuf_l398_25 = (_zz_when_RenderBuf_l398 == 5'h19);
  assign when_RenderBuf_l398_26 = (_zz_when_RenderBuf_l398 == 5'h1a);
  assign when_RenderBuf_l398_27 = (_zz_when_RenderBuf_l398 == 5'h1b);
  assign when_RenderBuf_l398_28 = (_zz_when_RenderBuf_l398 == 5'h1c);
  assign when_RenderBuf_l398_29 = (_zz_when_RenderBuf_l398 == 5'h1d);
  assign when_RenderBuf_l398_30 = (_zz_when_RenderBuf_l398 == 5'h1e);
  assign when_RenderBuf_l398_31 = (_zz_when_RenderBuf_l398 == 5'h1f);
  assign pipeEmpty = ((((((((! prep_valid) && (! fragIn_m2sPipe_valid)) && (frags_io_occupancy == 7'h0)) && rIdle) && (missQ_io_occupancy == 4'b0000)) && (lineQ_io_occupancy == 4'b0000)) && (vLeft == 4'b0000)) && (hs == hng64_raster_H_Wait_1));
  assign when_RenderBuf_l409 = ((((fs == hng64_raster_F_Render) && finishing) && pipeEmpty) && (! io_i_valid));
  assign when_RenderBuf_l415 = (((fs == hng64_raster_F_Drain) && (vLeft == 4'b0000)) && (! drainRead));
  assign when_RenderBuf_l416 = flushSlot[4];
  assign when_RenderBuf_l418 = (_zz_when_RenderBuf_l418 && _zz_when_RenderBuf_l418_2);
  assign _zz_vAddr = flushSlot[3 : 0];
  assign _zz_43 = ({15'd0,1'b1} <<< _zz_vAddr);
  assign when_RenderBuf_l436 = (((((fs == hng64_raster_F_Flush) && (! anyBe)) && (! flushing)) && (wq_io_occupancy == 5'h0)) && (! wq_io_pop_valid));
  assign when_RenderBuf_l439 = (fs == hng64_raster_F_Done);
  assign io_busy = (fs != hng64_raster_F_Idle);
  always @(posedge clk) begin
    if(reset) begin
      fs <= hng64_raster_F_Idle;
      finishing <= 1'b0;
      io_i_throwWhen_map_rValid <= 1'b0;
      tValid_0 <= 1'b0;
      tValid_1 <= 1'b0;
      tValid_2 <= 1'b0;
      tValid_3 <= 1'b0;
      tValid_4 <= 1'b0;
      tValid_5 <= 1'b0;
      tValid_6 <= 1'b0;
      tValid_7 <= 1'b0;
      tValid_8 <= 1'b0;
      tValid_9 <= 1'b0;
      tValid_10 <= 1'b0;
      tValid_11 <= 1'b0;
      tValid_12 <= 1'b0;
      tValid_13 <= 1'b0;
      tValid_14 <= 1'b0;
      tValid_15 <= 1'b0;
      lru_0 <= 1'b0;
      lru_1 <= 1'b0;
      lru_2 <= 1'b0;
      lru_3 <= 1'b0;
      lru_4 <= 1'b0;
      lru_5 <= 1'b0;
      lru_6 <= 1'b0;
      lru_7 <= 1'b0;
      pOcc_0 <= 1'b0;
      pOcc_1 <= 1'b0;
      pOcc_2 <= 1'b0;
      pOcc_3 <= 1'b0;
      pOcc_4 <= 1'b0;
      pOcc_5 <= 1'b0;
      pOcc_6 <= 1'b0;
      pOcc_7 <= 1'b0;
      credits <= 4'b1000;
      fragIn_rValid <= 1'b0;
      beat <= 3'b000;
      gBeat <= 3'b000;
      dirty_0 <= 1'b0;
      dirty_1 <= 1'b0;
      dirty_2 <= 1'b0;
      dirty_3 <= 1'b0;
      dirty_4 <= 1'b0;
      dirty_5 <= 1'b0;
      dirty_6 <= 1'b0;
      dirty_7 <= 1'b0;
      dirty_8 <= 1'b0;
      dirty_9 <= 1'b0;
      dirty_10 <= 1'b0;
      dirty_11 <= 1'b0;
      dirty_12 <= 1'b0;
      dirty_13 <= 1'b0;
      dirty_14 <= 1'b0;
      dirty_15 <= 1'b0;
      hs <= hng64_raster_H_Wait_1;
      filled <= 1'b0;
      vLeft <= 4'b0000;
      rValid <= 1'b0;
      sValid <= 1'b0;
      cValid <= 1'b0;
      lastWr <= 1'b0;
      cBe_0 <= 8'h0;
      cBe_1 <= 8'h0;
      cBe_2 <= 8'h0;
      cBe_3 <= 8'h0;
      cBe_4 <= 8'h0;
      cBe_5 <= 8'h0;
      cBe_6 <= 8'h0;
      cBe_7 <= 8'h0;
      flushing <= 1'b0;
      fBeat <= 3'b000;
      anyBe <= 1'b0;
      drainRead <= 1'b0;
    end else begin
      if(when_RenderBuf_l62) begin
        finishing <= 1'b0;
        fs <= hng64_raster_F_Clear;
      end
      if(io_finish) begin
        finishing <= 1'b1;
      end
      if(clearW_fire) begin
        if(when_RenderBuf_l94) begin
          fs <= hng64_raster_F_Scrub;
        end
        if(when_RenderBuf_l98) begin
          fs <= hng64_raster_F_Render;
        end
      end
      if(io_i_throwWhen_map_ready) begin
        io_i_throwWhen_map_rValid <= io_i_throwWhen_map_valid;
      end
      if(fragIn_ready) begin
        fragIn_rValid <= fragIn_valid;
      end
      if(prep_fire) begin
        if(_zz_1[0]) begin
          lru_0 <= _zz_lru_0;
        end
        if(_zz_1[1]) begin
          lru_1 <= _zz_lru_0;
        end
        if(_zz_1[2]) begin
          lru_2 <= _zz_lru_0;
        end
        if(_zz_1[3]) begin
          lru_3 <= _zz_lru_0;
        end
        if(_zz_1[4]) begin
          lru_4 <= _zz_lru_0;
        end
        if(_zz_1[5]) begin
          lru_5 <= _zz_lru_0;
        end
        if(_zz_1[6]) begin
          lru_6 <= _zz_lru_0;
        end
        if(_zz_1[7]) begin
          lru_7 <= _zz_lru_0;
        end
        if(when_RenderBuf_l183) begin
          if(_zz_2[0]) begin
            tValid_0 <= 1'b1;
          end
          if(_zz_2[1]) begin
            tValid_1 <= 1'b1;
          end
          if(_zz_2[2]) begin
            tValid_2 <= 1'b1;
          end
          if(_zz_2[3]) begin
            tValid_3 <= 1'b1;
          end
          if(_zz_2[4]) begin
            tValid_4 <= 1'b1;
          end
          if(_zz_2[5]) begin
            tValid_5 <= 1'b1;
          end
          if(_zz_2[6]) begin
            tValid_6 <= 1'b1;
          end
          if(_zz_2[7]) begin
            tValid_7 <= 1'b1;
          end
          if(_zz_2[8]) begin
            tValid_8 <= 1'b1;
          end
          if(_zz_2[9]) begin
            tValid_9 <= 1'b1;
          end
          if(_zz_2[10]) begin
            tValid_10 <= 1'b1;
          end
          if(_zz_2[11]) begin
            tValid_11 <= 1'b1;
          end
          if(_zz_2[12]) begin
            tValid_12 <= 1'b1;
          end
          if(_zz_2[13]) begin
            tValid_13 <= 1'b1;
          end
          if(_zz_2[14]) begin
            tValid_14 <= 1'b1;
          end
          if(_zz_2[15]) begin
            tValid_15 <= 1'b1;
          end
          if(_zz_4[0]) begin
            pOcc_0 <= 1'b1;
          end
          if(_zz_4[1]) begin
            pOcc_1 <= 1'b1;
          end
          if(_zz_4[2]) begin
            pOcc_2 <= 1'b1;
          end
          if(_zz_4[3]) begin
            pOcc_3 <= 1'b1;
          end
          if(_zz_4[4]) begin
            pOcc_4 <= 1'b1;
          end
          if(_zz_4[5]) begin
            pOcc_5 <= 1'b1;
          end
          if(_zz_4[6]) begin
            pOcc_6 <= 1'b1;
          end
          if(_zz_4[7]) begin
            pOcc_7 <= 1'b1;
          end
        end
      end
      if(release_valid) begin
        if(_zz_5[0]) begin
          pOcc_0 <= 1'b0;
        end
        if(_zz_5[1]) begin
          pOcc_1 <= 1'b0;
        end
        if(_zz_5[2]) begin
          pOcc_2 <= 1'b0;
        end
        if(_zz_5[3]) begin
          pOcc_3 <= 1'b0;
        end
        if(_zz_5[4]) begin
          pOcc_4 <= 1'b0;
        end
        if(_zz_5[5]) begin
          pOcc_5 <= 1'b0;
        end
        if(_zz_5[6]) begin
          pOcc_6 <= 1'b0;
        end
        if(_zz_5[7]) begin
          pOcc_7 <= 1'b0;
        end
      end
      if(releaseWb_valid) begin
        if(_zz_6[0]) begin
          pOcc_0 <= 1'b0;
        end
        if(_zz_6[1]) begin
          pOcc_1 <= 1'b0;
        end
        if(_zz_6[2]) begin
          pOcc_2 <= 1'b0;
        end
        if(_zz_6[3]) begin
          pOcc_3 <= 1'b0;
        end
        if(_zz_6[4]) begin
          pOcc_4 <= 1'b0;
        end
        if(_zz_6[5]) begin
          pOcc_5 <= 1'b0;
        end
        if(_zz_6[6]) begin
          pOcc_6 <= 1'b0;
        end
        if(_zz_6[7]) begin
          pOcc_7 <= 1'b0;
        end
      end
      credits <= (_zz_credits + _zz_credits_3);
      if(io_rdAddr_fire) begin
        beat <= (beat + 3'b001);
      end
      if(io_rdData_valid) begin
        gBeat <= (gBeat + 3'b001);
      end
      if(when_RenderBuf_l252) begin
        hs <= hng64_raster_H_ReadVictim;
      end
      if(when_RenderBuf_l257) begin
        vLeft <= (_zz_vLeft ? 4'b1000 : 4'b0000);
        if(_zz_24[0]) begin
          dirty_0 <= 1'b0;
        end
        if(_zz_24[1]) begin
          dirty_1 <= 1'b0;
        end
        if(_zz_24[2]) begin
          dirty_2 <= 1'b0;
        end
        if(_zz_24[3]) begin
          dirty_3 <= 1'b0;
        end
        if(_zz_24[4]) begin
          dirty_4 <= 1'b0;
        end
        if(_zz_24[5]) begin
          dirty_5 <= 1'b0;
        end
        if(_zz_24[6]) begin
          dirty_6 <= 1'b0;
        end
        if(_zz_24[7]) begin
          dirty_7 <= 1'b0;
        end
        if(_zz_24[8]) begin
          dirty_8 <= 1'b0;
        end
        if(_zz_24[9]) begin
          dirty_9 <= 1'b0;
        end
        if(_zz_24[10]) begin
          dirty_10 <= 1'b0;
        end
        if(_zz_24[11]) begin
          dirty_11 <= 1'b0;
        end
        if(_zz_24[12]) begin
          dirty_12 <= 1'b0;
        end
        if(_zz_24[13]) begin
          dirty_13 <= 1'b0;
        end
        if(_zz_24[14]) begin
          dirty_14 <= 1'b0;
        end
        if(_zz_24[15]) begin
          dirty_15 <= 1'b0;
        end
        filled <= 1'b1;
        hs <= hng64_raster_H_Wait_1;
      end
      if(backW_fire) begin
        vLeft <= (vLeft - 4'b0001);
      end
      if(go) begin
        filled <= 1'b0;
      end
      if(go) begin
        rValid <= 1'b1;
      end else begin
        if(rMove) begin
          rValid <= 1'b0;
        end
      end
      if(rMove) begin
        sValid <= 1'b1;
      end else begin
        if(sMove) begin
          sValid <= 1'b0;
        end
      end
      if(sMove) begin
        cValid <= 1'b1;
      end else begin
        if(cDone) begin
          cValid <= 1'b0;
        end
      end
      lastWr <= 1'b0;
      if(cWrite) begin
        if(_zz_41[0]) begin
          dirty_0 <= 1'b1;
        end
        if(_zz_41[1]) begin
          dirty_1 <= 1'b1;
        end
        if(_zz_41[2]) begin
          dirty_2 <= 1'b1;
        end
        if(_zz_41[3]) begin
          dirty_3 <= 1'b1;
        end
        if(_zz_41[4]) begin
          dirty_4 <= 1'b1;
        end
        if(_zz_41[5]) begin
          dirty_5 <= 1'b1;
        end
        if(_zz_41[6]) begin
          dirty_6 <= 1'b1;
        end
        if(_zz_41[7]) begin
          dirty_7 <= 1'b1;
        end
        if(_zz_41[8]) begin
          dirty_8 <= 1'b1;
        end
        if(_zz_41[9]) begin
          dirty_9 <= 1'b1;
        end
        if(_zz_41[10]) begin
          dirty_10 <= 1'b1;
        end
        if(_zz_41[11]) begin
          dirty_11 <= 1'b1;
        end
        if(_zz_41[12]) begin
          dirty_12 <= 1'b1;
        end
        if(_zz_41[13]) begin
          dirty_13 <= 1'b1;
        end
        if(_zz_41[14]) begin
          dirty_14 <= 1'b1;
        end
        if(_zz_41[15]) begin
          dirty_15 <= 1'b1;
        end
        lastWr <= 1'b1;
      end
      if(when_RenderBuf_l377) begin
        flushing <= 1'b1;
        fBeat <= 3'b000;
      end
      if(when_RenderBuf_l387) begin
        if(_zz_42[0]) begin
          cBe_0 <= 8'h0;
        end
        if(_zz_42[1]) begin
          cBe_1 <= 8'h0;
        end
        if(_zz_42[2]) begin
          cBe_2 <= 8'h0;
        end
        if(_zz_42[3]) begin
          cBe_3 <= 8'h0;
        end
        if(_zz_42[4]) begin
          cBe_4 <= 8'h0;
        end
        if(_zz_42[5]) begin
          cBe_5 <= 8'h0;
        end
        if(_zz_42[6]) begin
          cBe_6 <= 8'h0;
        end
        if(_zz_42[7]) begin
          cBe_7 <= 8'h0;
        end
        fBeat <= (fBeat + 3'b001);
        if(when_RenderBuf_l390) begin
          flushing <= 1'b0;
          anyBe <= 1'b0;
        end
      end
      if(comb_fire) begin
        anyBe <= 1'b1;
        if(when_RenderBuf_l398) begin
          cBe_0[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_1) begin
          cBe_0[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_2) begin
          cBe_0[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_3) begin
          cBe_0[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_4) begin
          cBe_1[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_5) begin
          cBe_1[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_6) begin
          cBe_1[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_7) begin
          cBe_1[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_8) begin
          cBe_2[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_9) begin
          cBe_2[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_10) begin
          cBe_2[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_11) begin
          cBe_2[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_12) begin
          cBe_3[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_13) begin
          cBe_3[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_14) begin
          cBe_3[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_15) begin
          cBe_3[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_16) begin
          cBe_4[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_17) begin
          cBe_4[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_18) begin
          cBe_4[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_19) begin
          cBe_4[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_20) begin
          cBe_5[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_21) begin
          cBe_5[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_22) begin
          cBe_5[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_23) begin
          cBe_5[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_24) begin
          cBe_6[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_25) begin
          cBe_6[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_26) begin
          cBe_6[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_27) begin
          cBe_6[7 : 6] <= 2'b11;
        end
        if(when_RenderBuf_l398_28) begin
          cBe_7[1 : 0] <= 2'b11;
        end
        if(when_RenderBuf_l398_29) begin
          cBe_7[3 : 2] <= 2'b11;
        end
        if(when_RenderBuf_l398_30) begin
          cBe_7[5 : 4] <= 2'b11;
        end
        if(when_RenderBuf_l398_31) begin
          cBe_7[7 : 6] <= 2'b11;
        end
      end
      if(when_RenderBuf_l409) begin
        fs <= hng64_raster_F_Drain;
      end
      if(when_RenderBuf_l415) begin
        if(when_RenderBuf_l416) begin
          fs <= hng64_raster_F_Flush;
        end else begin
          if(when_RenderBuf_l418) begin
            drainRead <= 1'b1;
          end
        end
      end
      if(drainRead) begin
        vLeft <= 4'b1000;
        if(_zz_43[0]) begin
          dirty_0 <= 1'b0;
        end
        if(_zz_43[1]) begin
          dirty_1 <= 1'b0;
        end
        if(_zz_43[2]) begin
          dirty_2 <= 1'b0;
        end
        if(_zz_43[3]) begin
          dirty_3 <= 1'b0;
        end
        if(_zz_43[4]) begin
          dirty_4 <= 1'b0;
        end
        if(_zz_43[5]) begin
          dirty_5 <= 1'b0;
        end
        if(_zz_43[6]) begin
          dirty_6 <= 1'b0;
        end
        if(_zz_43[7]) begin
          dirty_7 <= 1'b0;
        end
        if(_zz_43[8]) begin
          dirty_8 <= 1'b0;
        end
        if(_zz_43[9]) begin
          dirty_9 <= 1'b0;
        end
        if(_zz_43[10]) begin
          dirty_10 <= 1'b0;
        end
        if(_zz_43[11]) begin
          dirty_11 <= 1'b0;
        end
        if(_zz_43[12]) begin
          dirty_12 <= 1'b0;
        end
        if(_zz_43[13]) begin
          dirty_13 <= 1'b0;
        end
        if(_zz_43[14]) begin
          dirty_14 <= 1'b0;
        end
        if(_zz_43[15]) begin
          dirty_15 <= 1'b0;
        end
        drainRead <= 1'b0;
      end
      if(when_RenderBuf_l436) begin
        fs <= hng64_raster_F_Done;
      end
      if(when_RenderBuf_l439) begin
        tValid_0 <= 1'b0;
        tValid_1 <= 1'b0;
        tValid_2 <= 1'b0;
        tValid_3 <= 1'b0;
        tValid_4 <= 1'b0;
        tValid_5 <= 1'b0;
        tValid_6 <= 1'b0;
        tValid_7 <= 1'b0;
        tValid_8 <= 1'b0;
        tValid_9 <= 1'b0;
        tValid_10 <= 1'b0;
        tValid_11 <= 1'b0;
        tValid_12 <= 1'b0;
        tValid_13 <= 1'b0;
        tValid_14 <= 1'b0;
        tValid_15 <= 1'b0;
        fs <= hng64_raster_F_Idle;
      end
    end
  end

  always @(posedge clk) begin
    if(when_RenderBuf_l62) begin
      tag <= io_tag;
      full <= io_full;
      scrubPhase <= io_scrub;
      cBase <= io_colourBase;
      dBase <= io_depthBase;
      count <= 18'h0;
    end
    if(clearW_fire) begin
      count <= (count + 18'h00001);
      if(when_RenderBuf_l94) begin
        count <= 18'h0;
      end
    end
    if(io_i_throwWhen_map_ready) begin
      io_i_throwWhen_map_rData_x <= io_i_throwWhen_map_payload_x;
      io_i_throwWhen_map_rData_y <= io_i_throwWhen_map_payload_y;
      io_i_throwWhen_map_rData_z <= io_i_throwWhen_map_payload_z;
      io_i_throwWhen_map_rData_colour <= io_i_throwWhen_map_payload_colour;
    end
    if(fragIn_ready) begin
      fragIn_rData_f_x <= fragIn_payload_f_x;
      fragIn_rData_f_y <= fragIn_payload_f_y;
      fragIn_rData_f_z <= fragIn_payload_f_z;
      fragIn_rData_f_colour <= fragIn_payload_f_colour;
      fragIn_rData_slot <= fragIn_payload_slot;
      fragIn_rData_miss <= fragIn_payload_miss;
      fragIn_rData_victim <= fragIn_payload_victim;
      fragIn_rData_vLine <= fragIn_payload_vLine;
      fragIn_rData_pend <= fragIn_payload_pend;
    end
    if(when_RenderBuf_l177) begin
      pVic_0 <= _zz_pVic_0;
      pLine_0 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_1) begin
      pVic_1 <= _zz_pVic_0;
      pLine_1 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_2) begin
      pVic_2 <= _zz_pVic_0;
      pLine_2 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_3) begin
      pVic_3 <= _zz_pVic_0;
      pLine_3 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_4) begin
      pVic_4 <= _zz_pVic_0;
      pLine_4 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_5) begin
      pVic_5 <= _zz_pVic_0;
      pLine_5 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_6) begin
      pVic_6 <= _zz_pVic_0;
      pLine_6 <= {_zz_pLine_0,set};
    end
    if(when_RenderBuf_l177_7) begin
      pVic_7 <= _zz_pVic_0;
      pLine_7 <= {_zz_pLine_0,set};
    end
    if(prep_fire) begin
      if(when_RenderBuf_l183) begin
        if(_zz_3[0]) begin
          tTag_0 <= ltag;
        end
        if(_zz_3[1]) begin
          tTag_1 <= ltag;
        end
        if(_zz_3[2]) begin
          tTag_2 <= ltag;
        end
        if(_zz_3[3]) begin
          tTag_3 <= ltag;
        end
        if(_zz_3[4]) begin
          tTag_4 <= ltag;
        end
        if(_zz_3[5]) begin
          tTag_5 <= ltag;
        end
        if(_zz_3[6]) begin
          tTag_6 <= ltag;
        end
        if(_zz_3[7]) begin
          tTag_7 <= ltag;
        end
        if(_zz_3[8]) begin
          tTag_8 <= ltag;
        end
        if(_zz_3[9]) begin
          tTag_9 <= ltag;
        end
        if(_zz_3[10]) begin
          tTag_10 <= ltag;
        end
        if(_zz_3[11]) begin
          tTag_11 <= ltag;
        end
        if(_zz_3[12]) begin
          tTag_12 <= ltag;
        end
        if(_zz_3[13]) begin
          tTag_13 <= ltag;
        end
        if(_zz_3[14]) begin
          tTag_14 <= ltag;
        end
        if(_zz_3[15]) begin
          tTag_15 <= ltag;
        end
      end
    end
    if(io_rdData_valid) begin
      if(_zz_7[0]) begin
        gather_0 <= io_rdData_payload;
      end
      if(_zz_7[1]) begin
        gather_1 <= io_rdData_payload;
      end
      if(_zz_7[2]) begin
        gather_2 <= io_rdData_payload;
      end
      if(_zz_7[3]) begin
        gather_3 <= io_rdData_payload;
      end
      if(_zz_7[4]) begin
        gather_4 <= io_rdData_payload;
      end
      if(_zz_7[5]) begin
        gather_5 <= io_rdData_payload;
      end
      if(_zz_7[6]) begin
        gather_6 <= io_rdData_payload;
      end
      if(_zz_7[7]) begin
        gather_7 <= io_rdData_payload;
      end
    end
    if(when_RenderBuf_l257) begin
      vBuf_0 <= {bankRd_1,bankRd_0};
      vBuf_1 <= {bankRd_3,bankRd_2};
      vBuf_2 <= {bankRd_5,bankRd_4};
      vBuf_3 <= {bankRd_7,bankRd_6};
      vBuf_4 <= {bankRd_9,bankRd_8};
      vBuf_5 <= {bankRd_11,bankRd_10};
      vBuf_6 <= {bankRd_13,bankRd_12};
      vBuf_7 <= {bankRd_15,bankRd_14};
      vAddr <= frags_io_pop_payload_vLine;
      vPend <= frags_io_pop_payload_pend;
      vRelease <= 1'b1;
    end
    if(go) begin
      rF_f_x <= frags_io_pop_payload_f_x;
      rF_f_y <= frags_io_pop_payload_f_y;
      rF_f_z <= frags_io_pop_payload_f_z;
      rF_f_colour <= frags_io_pop_payload_f_colour;
      rF_slot <= frags_io_pop_payload_slot;
      rF_miss <= frags_io_pop_payload_miss;
      rF_victim <= frags_io_pop_payload_victim;
      rF_vLine <= frags_io_pop_payload_vLine;
      rF_pend <= frags_io_pop_payload_pend;
    end
    if(rMove) begin
      sF_f_x <= rF_f_x;
      sF_f_y <= rF_f_y;
      sF_f_z <= rF_f_z;
      sF_f_colour <= rF_f_colour;
      sF_slot <= rF_slot;
      sF_miss <= rF_miss;
      sF_victim <= rF_victim;
      sF_vLine <= rF_vLine;
      sF_pend <= rF_pend;
      sPass <= pass;
      sWord <= {tag,rF_f_z};
    end
    if(sMove) begin
      cF_f_x <= sF_f_x;
      cF_f_y <= sF_f_y;
      cF_f_z <= sF_f_z;
      cF_f_colour <= sF_f_colour;
      cF_slot <= sF_slot;
      cF_miss <= sF_miss;
      cF_victim <= sF_victim;
      cF_vLine <= sF_vLine;
      cF_pend <= sF_pend;
      cPass <= sPass;
      cWord <= sWord;
    end
    if(cWrite) begin
      lastSlot <= cF_slot;
      lastPx <= cPx;
      lastWord <= cWord;
    end
    if(comb_fire) begin
      cLine <= cLineOf;
      if(when_RenderBuf_l398) begin
        cData_0[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_1) begin
        cData_0[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_2) begin
        cData_0[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_3) begin
        cData_0[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_4) begin
        cData_1[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_5) begin
        cData_1[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_6) begin
        cData_1[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_7) begin
        cData_1[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_8) begin
        cData_2[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_9) begin
        cData_2[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_10) begin
        cData_2[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_11) begin
        cData_2[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_12) begin
        cData_3[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_13) begin
        cData_3[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_14) begin
        cData_3[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_15) begin
        cData_3[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_16) begin
        cData_4[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_17) begin
        cData_4[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_18) begin
        cData_4[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_19) begin
        cData_4[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_20) begin
        cData_5[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_21) begin
        cData_5[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_22) begin
        cData_5[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_23) begin
        cData_5[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_24) begin
        cData_6[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_25) begin
        cData_6[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_26) begin
        cData_6[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_27) begin
        cData_6[63 : 48] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_28) begin
        cData_7[15 : 0] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_29) begin
        cData_7[31 : 16] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_30) begin
        cData_7[47 : 32] <= comb_payload_colour;
      end
      if(when_RenderBuf_l398_31) begin
        cData_7[63 : 48] <= comb_payload_colour;
      end
    end
    if(when_RenderBuf_l409) begin
      flushSlot <= 5'h0;
    end
    if(when_RenderBuf_l415) begin
      if(!when_RenderBuf_l416) begin
        if(!when_RenderBuf_l418) begin
          flushSlot <= (flushSlot + 5'h01);
        end
      end
    end
    if(drainRead) begin
      vBuf_0 <= {bankRd_1,bankRd_0};
      vBuf_1 <= {bankRd_3,bankRd_2};
      vBuf_2 <= {bankRd_5,bankRd_4};
      vBuf_3 <= {bankRd_7,bankRd_6};
      vBuf_4 <= {bankRd_9,bankRd_8};
      vBuf_5 <= {bankRd_11,bankRd_10};
      vBuf_6 <= {bankRd_13,bankRd_12};
      vBuf_7 <= {bankRd_15,bankRd_14};
      vAddr <= {_zz_vAddr_1,_zz_vAddr[3 : 1]};
      vRelease <= 1'b0;
      flushSlot <= (flushSlot + 5'h01);
    end
  end


endmodule

module hng64_raster_TexCache (
  input  wire          io_i_valid,
  output wire          io_i_ready,
  input  wire [8:0]    io_i_payload_x,
  input  wire [8:0]    io_i_payload_y,
  input  wire [29:0]   io_i_payload_z,
  input  wire [23:0]   io_i_payload_addr,
  input  wire          io_i_payload_nib,
  input  wire [7:0]    io_i_payload_light,
  input  wire          io_i_payload_flat,
  input  wire          io_i_payload_blend,
  input  wire          io_i_payload_tex4bpp,
  input  wire [15:0]   io_i_payload_pal,
  output wire          io_o_valid,
  input  wire          io_o_ready,
  output wire [8:0]    io_o_payload_f_x,
  output wire [8:0]    io_o_payload_f_y,
  output wire [29:0]   io_o_payload_f_z,
  output wire [23:0]   io_o_payload_f_addr,
  output wire          io_o_payload_f_nib,
  output wire [7:0]    io_o_payload_f_light,
  output wire          io_o_payload_f_flat,
  output wire          io_o_payload_f_blend,
  output wire          io_o_payload_f_tex4bpp,
  output wire [15:0]   io_o_payload_f_pal,
  output wire [7:0]    io_o_payload_texel,
  input  wire [27:0]   io_texBase,
  output wire          io_rdAddr_valid,
  input  wire          io_rdAddr_ready,
  output wire [27:0]   io_rdAddr_payload,
  input  wire          io_rdData_valid,
  input  wire [63:0]   io_rdData_payload,
  output wire          io_busy,
  input  wire          clk,
  input  wire          reset
);

  wire                missQ_io_push_valid;
  wire       [18:0]   missQ_io_push_payload;
  wire                missQ_io_pop_ready;
  wire                frags_io_push_valid;
  wire       [9:0]    frags_io_push_payload_word;
  wire       [2:0]    frags_io_push_payload_byte;
  wire                frags_io_pop_ready;
  reg        [11:0]   tagRam_spinal_port0;
  reg        [63:0]   dataRam_spinal_port1;
  wire                missQ_io_push_ready;
  wire                missQ_io_pop_valid;
  wire       [18:0]   missQ_io_pop_payload;
  wire       [3:0]    missQ_io_occupancy;
  wire       [3:0]    missQ_io_availability;
  wire                frags_io_push_ready;
  wire                frags_io_pop_valid;
  wire       [8:0]    frags_io_pop_payload_f_x;
  wire       [8:0]    frags_io_pop_payload_f_y;
  wire       [29:0]   frags_io_pop_payload_f_z;
  wire       [23:0]   frags_io_pop_payload_f_addr;
  wire                frags_io_pop_payload_f_nib;
  wire       [7:0]    frags_io_pop_payload_f_light;
  wire                frags_io_pop_payload_f_flat;
  wire                frags_io_pop_payload_f_blend;
  wire                frags_io_pop_payload_f_tex4bpp;
  wire       [15:0]   frags_io_pop_payload_f_pal;
  wire       [9:0]    frags_io_pop_payload_word;
  wire       [2:0]    frags_io_pop_payload_byte;
  wire                frags_io_pop_payload_miss;
  wire       [7:0]    frags_io_occupancy;
  wire       [7:0]    frags_io_availability;
  wire                fill_io_push_ready;
  wire                fill_io_pop_valid;
  wire       [63:0]   fill_io_pop_payload;
  wire       [6:0]    fill_io_occupancy;
  wire       [6:0]    fill_io_availability;
  wire       [7:0]    _zz_tagRam_port;
  wire       [11:0]   _zz_tagRam_port_1;
  wire                _zz_tagRam_port_2;
  wire       [4:0]    _zz_credits;
  wire       [4:0]    _zz_credits_1;
  wire       [0:0]    _zz_credits_2;
  wire       [4:0]    _zz_credits_3;
  wire       [0:0]    _zz_credits_4;
  wire       [27:0]   _zz_io_rdAddr_payload;
  wire       [23:0]   _zz_io_rdAddr_payload_1;
  wire       [9:0]    _zz_dataRam_port;
  wire                _zz_dataRam_port_1;
  reg        [7:0]    _zz_rd_map_payload_texel;
  reg        [8:0]    clearIdx;
  wire                clearing;
  wire                _zz_io_i_ready;
  wire                entry_valid;
  wire                entry_ready;
  wire       [8:0]    entry_payload_x;
  wire       [8:0]    entry_payload_y;
  wire       [29:0]   entry_payload_z;
  wire       [23:0]   entry_payload_addr;
  wire                entry_payload_nib;
  wire       [7:0]    entry_payload_light;
  wire                entry_payload_flat;
  wire                entry_payload_blend;
  wire                entry_payload_tex4bpp;
  wire       [15:0]   entry_payload_pal;
  wire                entry_translated_valid;
  wire                entry_translated_ready;
  wire       [7:0]    entry_translated_payload;
  wire                tagRd_valid;
  wire                tagRd_ready;
  wire       [11:0]   tagRd_payload_value;
  wire       [8:0]    tagRd_payload_linked_x;
  wire       [8:0]    tagRd_payload_linked_y;
  wire       [29:0]   tagRd_payload_linked_z;
  wire       [23:0]   tagRd_payload_linked_addr;
  wire                tagRd_payload_linked_nib;
  wire       [7:0]    tagRd_payload_linked_light;
  wire                tagRd_payload_linked_flat;
  wire                tagRd_payload_linked_blend;
  wire                tagRd_payload_linked_tex4bpp;
  wire       [15:0]   tagRd_payload_linked_pal;
  reg                 _zz_tagRd_valid;
  wire                entry_translated_fire;
  reg        [8:0]    entry_payload_regNextWhen_x;
  reg        [8:0]    entry_payload_regNextWhen_y;
  reg        [29:0]   entry_payload_regNextWhen_z;
  reg        [23:0]   entry_payload_regNextWhen_addr;
  reg                 entry_payload_regNextWhen_nib;
  reg        [7:0]    entry_payload_regNextWhen_light;
  reg                 entry_payload_regNextWhen_flat;
  reg                 entry_payload_regNextWhen_blend;
  reg                 entry_payload_regNextWhen_tex4bpp;
  reg        [15:0]   entry_payload_regNextWhen_pal;
  wire                tagRd_isFree;
  reg                 lastWrValid;
  reg        [7:0]    lastWrIdx;
  reg        [11:0]   lastWrTag;
  reg        [4:0]    credits;
  wire       [23:0]   ba;
  wire       [7:0]    idx;
  wire       [11:0]   tag;
  wire       [11:0]   stored;
  wire                miss;
  wire                consume;
  wire                canGo;
  wire                tagRd_fire;
  wire                allocate;
  reg        [1:0]    beat;
  wire                io_rdAddr_fire;
  reg                 filling;
  reg                 filled;
  reg        [1:0]    fillBeat;
  wire                when_TexCache_l104;
  wire                when_TexCache_l109;
  wire                when_TexCache_l111;
  wire                _zz_go_valid;
  wire                go_valid;
  wire                go_ready;
  wire       [8:0]    go_payload_f_x;
  wire       [8:0]    go_payload_f_y;
  wire       [29:0]   go_payload_f_z;
  wire       [23:0]   go_payload_f_addr;
  wire                go_payload_f_nib;
  wire       [7:0]    go_payload_f_light;
  wire                go_payload_f_flat;
  wire                go_payload_f_blend;
  wire                go_payload_f_tex4bpp;
  wire       [15:0]   go_payload_f_pal;
  wire       [9:0]    go_payload_word;
  wire       [2:0]    go_payload_byte;
  wire                go_payload_miss;
  wire                go_fire;
  wire                go_translated_valid;
  wire                go_translated_ready;
  wire       [9:0]    go_translated_payload;
  wire                rd_valid;
  wire                rd_ready;
  wire       [63:0]   rd_payload_value;
  wire       [8:0]    rd_payload_linked_f_x;
  wire       [8:0]    rd_payload_linked_f_y;
  wire       [29:0]   rd_payload_linked_f_z;
  wire       [23:0]   rd_payload_linked_f_addr;
  wire                rd_payload_linked_f_nib;
  wire       [7:0]    rd_payload_linked_f_light;
  wire                rd_payload_linked_f_flat;
  wire                rd_payload_linked_f_blend;
  wire                rd_payload_linked_f_tex4bpp;
  wire       [15:0]   rd_payload_linked_f_pal;
  wire       [9:0]    rd_payload_linked_word;
  wire       [2:0]    rd_payload_linked_byte;
  wire                rd_payload_linked_miss;
  reg                 _zz_rd_valid;
  wire                go_translated_fire;
  reg        [8:0]    go_payload_regNextWhen_f_x;
  reg        [8:0]    go_payload_regNextWhen_f_y;
  reg        [29:0]   go_payload_regNextWhen_f_z;
  reg        [23:0]   go_payload_regNextWhen_f_addr;
  reg                 go_payload_regNextWhen_f_nib;
  reg        [7:0]    go_payload_regNextWhen_f_light;
  reg                 go_payload_regNextWhen_f_flat;
  reg                 go_payload_regNextWhen_f_blend;
  reg                 go_payload_regNextWhen_f_tex4bpp;
  reg        [15:0]   go_payload_regNextWhen_f_pal;
  reg        [9:0]    go_payload_regNextWhen_word;
  reg        [2:0]    go_payload_regNextWhen_byte;
  reg                 go_payload_regNextWhen_miss;
  wire                rd_isFree;
  wire                rd_map_valid;
  reg                 rd_map_ready;
  wire       [8:0]    rd_map_payload_f_x;
  wire       [8:0]    rd_map_payload_f_y;
  wire       [29:0]   rd_map_payload_f_z;
  wire       [23:0]   rd_map_payload_f_addr;
  wire                rd_map_payload_f_nib;
  wire       [7:0]    rd_map_payload_f_light;
  wire                rd_map_payload_f_flat;
  wire                rd_map_payload_f_blend;
  wire                rd_map_payload_f_tex4bpp;
  wire       [15:0]   rd_map_payload_f_pal;
  wire       [7:0]    rd_map_payload_texel;
  wire                texeled_valid;
  wire                texeled_ready;
  wire       [8:0]    texeled_payload_f_x;
  wire       [8:0]    texeled_payload_f_y;
  wire       [29:0]   texeled_payload_f_z;
  wire       [23:0]   texeled_payload_f_addr;
  wire                texeled_payload_f_nib;
  wire       [7:0]    texeled_payload_f_light;
  wire                texeled_payload_f_flat;
  wire                texeled_payload_f_blend;
  wire                texeled_payload_f_tex4bpp;
  wire       [15:0]   texeled_payload_f_pal;
  wire       [7:0]    texeled_payload_texel;
  reg                 rd_map_rValid;
  reg        [8:0]    rd_map_rData_f_x;
  reg        [8:0]    rd_map_rData_f_y;
  reg        [29:0]   rd_map_rData_f_z;
  reg        [23:0]   rd_map_rData_f_addr;
  reg                 rd_map_rData_f_nib;
  reg        [7:0]    rd_map_rData_f_light;
  reg                 rd_map_rData_f_flat;
  reg                 rd_map_rData_f_blend;
  reg                 rd_map_rData_f_tex4bpp;
  reg        [15:0]   rd_map_rData_f_pal;
  reg        [7:0]    rd_map_rData_texel;
  wire                when_Stream_l477;
  reg [11:0] tagRam [0:255];
  reg [63:0] dataRam [0:1023];

  assign _zz_credits = (credits - _zz_credits_1);
  assign _zz_credits_2 = allocate;
  assign _zz_credits_1 = {4'd0, _zz_credits_2};
  assign _zz_credits_4 = consume;
  assign _zz_credits_3 = {4'd0, _zz_credits_4};
  assign _zz_io_rdAddr_payload_1 = {{missQ_io_pop_payload,beat},3'b000};
  assign _zz_io_rdAddr_payload = {4'd0, _zz_io_rdAddr_payload_1};
  assign _zz_tagRam_port = (clearing ? clearIdx[7 : 0] : idx);
  assign _zz_tagRam_port_1 = (clearing ? 12'h0 : tag);
  assign _zz_tagRam_port_2 = (clearing || allocate);
  assign _zz_dataRam_port = {frags_io_pop_payload_word[9 : 2],fillBeat};
  assign _zz_dataRam_port_1 = (filling && fill_io_pop_valid);
  always @(posedge clk) begin
    if(entry_translated_fire) begin
      tagRam_spinal_port0 <= tagRam[entry_translated_payload];
    end
  end

  always @(posedge clk) begin
    if(_zz_tagRam_port_2) begin
      tagRam[_zz_tagRam_port] <= _zz_tagRam_port_1;
    end
  end

  always @(posedge clk) begin
    if(_zz_dataRam_port_1) begin
      dataRam[_zz_dataRam_port] <= fill_io_pop_payload;
    end
  end

  always @(posedge clk) begin
    if(go_translated_fire) begin
      dataRam_spinal_port1 <= dataRam[go_translated_payload];
    end
  end

  hng64_raster_StreamFifo missQ (
    .io_push_valid   (missQ_io_push_valid        ), //i
    .io_push_ready   (missQ_io_push_ready        ), //o
    .io_push_payload (missQ_io_push_payload[18:0]), //i
    .io_pop_valid    (missQ_io_pop_valid         ), //o
    .io_pop_ready    (missQ_io_pop_ready         ), //i
    .io_pop_payload  (missQ_io_pop_payload[18:0] ), //o
    .io_flush        (1'b0                       ), //i
    .io_occupancy    (missQ_io_occupancy[3:0]    ), //o
    .io_availability (missQ_io_availability[3:0] ), //o
    .clk             (clk                        ), //i
    .reset           (reset                      )  //i
  );
  hng64_raster_StreamFifo_1 frags (
    .io_push_valid             (frags_io_push_valid              ), //i
    .io_push_ready             (frags_io_push_ready              ), //o
    .io_push_payload_f_x       (tagRd_payload_linked_x[8:0]      ), //i
    .io_push_payload_f_y       (tagRd_payload_linked_y[8:0]      ), //i
    .io_push_payload_f_z       (tagRd_payload_linked_z[29:0]     ), //i
    .io_push_payload_f_addr    (tagRd_payload_linked_addr[23:0]  ), //i
    .io_push_payload_f_nib     (tagRd_payload_linked_nib         ), //i
    .io_push_payload_f_light   (tagRd_payload_linked_light[7:0]  ), //i
    .io_push_payload_f_flat    (tagRd_payload_linked_flat        ), //i
    .io_push_payload_f_blend   (tagRd_payload_linked_blend       ), //i
    .io_push_payload_f_tex4bpp (tagRd_payload_linked_tex4bpp     ), //i
    .io_push_payload_f_pal     (tagRd_payload_linked_pal[15:0]   ), //i
    .io_push_payload_word      (frags_io_push_payload_word[9:0]  ), //i
    .io_push_payload_byte      (frags_io_push_payload_byte[2:0]  ), //i
    .io_push_payload_miss      (miss                             ), //i
    .io_pop_valid              (frags_io_pop_valid               ), //o
    .io_pop_ready              (frags_io_pop_ready               ), //i
    .io_pop_payload_f_x        (frags_io_pop_payload_f_x[8:0]    ), //o
    .io_pop_payload_f_y        (frags_io_pop_payload_f_y[8:0]    ), //o
    .io_pop_payload_f_z        (frags_io_pop_payload_f_z[29:0]   ), //o
    .io_pop_payload_f_addr     (frags_io_pop_payload_f_addr[23:0]), //o
    .io_pop_payload_f_nib      (frags_io_pop_payload_f_nib       ), //o
    .io_pop_payload_f_light    (frags_io_pop_payload_f_light[7:0]), //o
    .io_pop_payload_f_flat     (frags_io_pop_payload_f_flat      ), //o
    .io_pop_payload_f_blend    (frags_io_pop_payload_f_blend     ), //o
    .io_pop_payload_f_tex4bpp  (frags_io_pop_payload_f_tex4bpp   ), //o
    .io_pop_payload_f_pal      (frags_io_pop_payload_f_pal[15:0] ), //o
    .io_pop_payload_word       (frags_io_pop_payload_word[9:0]   ), //o
    .io_pop_payload_byte       (frags_io_pop_payload_byte[2:0]   ), //o
    .io_pop_payload_miss       (frags_io_pop_payload_miss        ), //o
    .io_flush                  (1'b0                             ), //i
    .io_occupancy              (frags_io_occupancy[7:0]          ), //o
    .io_availability           (frags_io_availability[7:0]       ), //o
    .clk                       (clk                              ), //i
    .reset                     (reset                            )  //i
  );
  hng64_raster_StreamFifo_2 fill (
    .io_push_valid   (io_rdData_valid          ), //i
    .io_push_ready   (fill_io_push_ready       ), //o
    .io_push_payload (io_rdData_payload[63:0]  ), //i
    .io_pop_valid    (fill_io_pop_valid        ), //o
    .io_pop_ready    (filling                  ), //i
    .io_pop_payload  (fill_io_pop_payload[63:0]), //o
    .io_flush        (1'b0                     ), //i
    .io_occupancy    (fill_io_occupancy[6:0]   ), //o
    .io_availability (fill_io_availability[6:0]), //o
    .clk             (clk                      ), //i
    .reset           (reset                    )  //i
  );
  always @(*) begin
    case(rd_payload_linked_byte)
      3'b000 : _zz_rd_map_payload_texel = rd_payload_value[7 : 0];
      3'b001 : _zz_rd_map_payload_texel = rd_payload_value[15 : 8];
      3'b010 : _zz_rd_map_payload_texel = rd_payload_value[23 : 16];
      3'b011 : _zz_rd_map_payload_texel = rd_payload_value[31 : 24];
      3'b100 : _zz_rd_map_payload_texel = rd_payload_value[39 : 32];
      3'b101 : _zz_rd_map_payload_texel = rd_payload_value[47 : 40];
      3'b110 : _zz_rd_map_payload_texel = rd_payload_value[55 : 48];
      default : _zz_rd_map_payload_texel = rd_payload_value[63 : 56];
    endcase
  end

  assign clearing = (! clearIdx[8]);
  assign _zz_io_i_ready = (! clearing);
  assign entry_valid = (io_i_valid && _zz_io_i_ready);
  assign io_i_ready = (entry_ready && _zz_io_i_ready);
  assign entry_payload_x = io_i_payload_x;
  assign entry_payload_y = io_i_payload_y;
  assign entry_payload_z = io_i_payload_z;
  assign entry_payload_addr = io_i_payload_addr;
  assign entry_payload_nib = io_i_payload_nib;
  assign entry_payload_light = io_i_payload_light;
  assign entry_payload_flat = io_i_payload_flat;
  assign entry_payload_blend = io_i_payload_blend;
  assign entry_payload_tex4bpp = io_i_payload_tex4bpp;
  assign entry_payload_pal = io_i_payload_pal;
  assign entry_translated_valid = entry_valid;
  assign entry_ready = entry_translated_ready;
  assign entry_translated_payload = entry_payload_addr[9 : 2];
  assign entry_translated_fire = (entry_translated_valid && entry_translated_ready);
  assign tagRd_isFree = ((! tagRd_valid) || tagRd_ready);
  assign entry_translated_ready = tagRd_isFree;
  assign tagRd_valid = _zz_tagRd_valid;
  assign tagRd_payload_value = tagRam_spinal_port0;
  assign tagRd_payload_linked_x = entry_payload_regNextWhen_x;
  assign tagRd_payload_linked_y = entry_payload_regNextWhen_y;
  assign tagRd_payload_linked_z = entry_payload_regNextWhen_z;
  assign tagRd_payload_linked_addr = entry_payload_regNextWhen_addr;
  assign tagRd_payload_linked_nib = entry_payload_regNextWhen_nib;
  assign tagRd_payload_linked_light = entry_payload_regNextWhen_light;
  assign tagRd_payload_linked_flat = entry_payload_regNextWhen_flat;
  assign tagRd_payload_linked_blend = entry_payload_regNextWhen_blend;
  assign tagRd_payload_linked_tex4bpp = entry_payload_regNextWhen_tex4bpp;
  assign tagRd_payload_linked_pal = entry_payload_regNextWhen_pal;
  assign ba = {{{tagRd_payload_linked_addr[23 : 13],tagRd_payload_linked_addr[9 : 2]},tagRd_payload_linked_addr[12 : 10]},tagRd_payload_linked_addr[1 : 0]};
  assign idx = ba[12 : 5];
  assign tag = {1'b1,ba[23 : 13]};
  assign stored = ((lastWrValid && (lastWrIdx == idx)) ? lastWrTag : tagRd_payload_value);
  assign miss = ((! tagRd_payload_linked_flat) && (stored != tag));
  assign canGo = (frags_io_push_ready && ((! miss) || (missQ_io_push_ready && (credits != 5'h0))));
  assign tagRd_ready = canGo;
  assign frags_io_push_valid = (tagRd_valid && canGo);
  assign frags_io_push_payload_word = ba[12 : 3];
  assign frags_io_push_payload_byte = ba[2 : 0];
  assign missQ_io_push_valid = ((tagRd_valid && canGo) && miss);
  assign missQ_io_push_payload = ba[23 : 5];
  assign tagRd_fire = (tagRd_valid && tagRd_ready);
  assign allocate = (tagRd_fire && miss);
  assign io_rdAddr_valid = missQ_io_pop_valid;
  assign io_rdAddr_payload = (io_texBase + _zz_io_rdAddr_payload);
  assign missQ_io_pop_ready = (io_rdAddr_ready && (beat == 2'b11));
  assign io_rdAddr_fire = (io_rdAddr_valid && io_rdAddr_ready);
  assign when_TexCache_l104 = (((((! filling) && (! filled)) && frags_io_pop_valid) && frags_io_pop_payload_miss) && (7'h04 <= fill_io_occupancy));
  assign when_TexCache_l109 = (filling && fill_io_pop_valid);
  assign when_TexCache_l111 = (fillBeat == 2'b11);
  assign consume = ((filling && fill_io_pop_valid) && (fillBeat == 2'b11));
  assign _zz_go_valid = (! (frags_io_pop_payload_miss && (! filled)));
  assign go_valid = (frags_io_pop_valid && _zz_go_valid);
  assign frags_io_pop_ready = (go_ready && _zz_go_valid);
  assign go_payload_f_x = frags_io_pop_payload_f_x;
  assign go_payload_f_y = frags_io_pop_payload_f_y;
  assign go_payload_f_z = frags_io_pop_payload_f_z;
  assign go_payload_f_addr = frags_io_pop_payload_f_addr;
  assign go_payload_f_nib = frags_io_pop_payload_f_nib;
  assign go_payload_f_light = frags_io_pop_payload_f_light;
  assign go_payload_f_flat = frags_io_pop_payload_f_flat;
  assign go_payload_f_blend = frags_io_pop_payload_f_blend;
  assign go_payload_f_tex4bpp = frags_io_pop_payload_f_tex4bpp;
  assign go_payload_f_pal = frags_io_pop_payload_f_pal;
  assign go_payload_word = frags_io_pop_payload_word;
  assign go_payload_byte = frags_io_pop_payload_byte;
  assign go_payload_miss = frags_io_pop_payload_miss;
  assign go_fire = (go_valid && go_ready);
  assign go_translated_valid = go_valid;
  assign go_ready = go_translated_ready;
  assign go_translated_payload = go_payload_word;
  assign go_translated_fire = (go_translated_valid && go_translated_ready);
  assign rd_isFree = ((! rd_valid) || rd_ready);
  assign go_translated_ready = rd_isFree;
  assign rd_valid = _zz_rd_valid;
  assign rd_payload_value = dataRam_spinal_port1;
  assign rd_payload_linked_f_x = go_payload_regNextWhen_f_x;
  assign rd_payload_linked_f_y = go_payload_regNextWhen_f_y;
  assign rd_payload_linked_f_z = go_payload_regNextWhen_f_z;
  assign rd_payload_linked_f_addr = go_payload_regNextWhen_f_addr;
  assign rd_payload_linked_f_nib = go_payload_regNextWhen_f_nib;
  assign rd_payload_linked_f_light = go_payload_regNextWhen_f_light;
  assign rd_payload_linked_f_flat = go_payload_regNextWhen_f_flat;
  assign rd_payload_linked_f_blend = go_payload_regNextWhen_f_blend;
  assign rd_payload_linked_f_tex4bpp = go_payload_regNextWhen_f_tex4bpp;
  assign rd_payload_linked_f_pal = go_payload_regNextWhen_f_pal;
  assign rd_payload_linked_word = go_payload_regNextWhen_word;
  assign rd_payload_linked_byte = go_payload_regNextWhen_byte;
  assign rd_payload_linked_miss = go_payload_regNextWhen_miss;
  assign rd_map_valid = rd_valid;
  assign rd_ready = rd_map_ready;
  assign rd_map_payload_f_x = rd_payload_linked_f_x;
  assign rd_map_payload_f_y = rd_payload_linked_f_y;
  assign rd_map_payload_f_z = rd_payload_linked_f_z;
  assign rd_map_payload_f_addr = rd_payload_linked_f_addr;
  assign rd_map_payload_f_nib = rd_payload_linked_f_nib;
  assign rd_map_payload_f_light = rd_payload_linked_f_light;
  assign rd_map_payload_f_flat = rd_payload_linked_f_flat;
  assign rd_map_payload_f_blend = rd_payload_linked_f_blend;
  assign rd_map_payload_f_tex4bpp = rd_payload_linked_f_tex4bpp;
  assign rd_map_payload_f_pal = rd_payload_linked_f_pal;
  assign rd_map_payload_texel = _zz_rd_map_payload_texel;
  always @(*) begin
    rd_map_ready = texeled_ready;
    if(when_Stream_l477) begin
      rd_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! texeled_valid);
  assign texeled_valid = rd_map_rValid;
  assign texeled_payload_f_x = rd_map_rData_f_x;
  assign texeled_payload_f_y = rd_map_rData_f_y;
  assign texeled_payload_f_z = rd_map_rData_f_z;
  assign texeled_payload_f_addr = rd_map_rData_f_addr;
  assign texeled_payload_f_nib = rd_map_rData_f_nib;
  assign texeled_payload_f_light = rd_map_rData_f_light;
  assign texeled_payload_f_flat = rd_map_rData_f_flat;
  assign texeled_payload_f_blend = rd_map_rData_f_blend;
  assign texeled_payload_f_tex4bpp = rd_map_rData_f_tex4bpp;
  assign texeled_payload_f_pal = rd_map_rData_f_pal;
  assign texeled_payload_texel = rd_map_rData_texel;
  assign io_o_valid = texeled_valid;
  assign texeled_ready = io_o_ready;
  assign io_o_payload_f_x = texeled_payload_f_x;
  assign io_o_payload_f_y = texeled_payload_f_y;
  assign io_o_payload_f_z = texeled_payload_f_z;
  assign io_o_payload_f_addr = texeled_payload_f_addr;
  assign io_o_payload_f_nib = texeled_payload_f_nib;
  assign io_o_payload_f_light = texeled_payload_f_light;
  assign io_o_payload_f_flat = texeled_payload_f_flat;
  assign io_o_payload_f_blend = texeled_payload_f_blend;
  assign io_o_payload_f_tex4bpp = texeled_payload_f_tex4bpp;
  assign io_o_payload_f_pal = texeled_payload_f_pal;
  assign io_o_payload_texel = texeled_payload_texel;
  assign io_busy = ((((((clearing || tagRd_valid) || (frags_io_occupancy != 8'h0)) || rd_valid) || texeled_valid) || (missQ_io_occupancy != 4'b0000)) || (fill_io_occupancy != 7'h0));
  always @(posedge clk) begin
    if(reset) begin
      clearIdx <= 9'h0;
      _zz_tagRd_valid <= 1'b0;
      lastWrValid <= 1'b0;
      credits <= 5'h10;
      beat <= 2'b00;
      filling <= 1'b0;
      filled <= 1'b0;
      fillBeat <= 2'b00;
      _zz_rd_valid <= 1'b0;
      rd_map_rValid <= 1'b0;
    end else begin
      if(clearing) begin
        clearIdx <= (clearIdx + 9'h001);
      end
      if(entry_translated_ready) begin
        _zz_tagRd_valid <= entry_translated_valid;
      end
      if(allocate) begin
        lastWrValid <= 1'b1;
      end
      if(clearing) begin
        lastWrValid <= 1'b0;
      end
      credits <= (_zz_credits + _zz_credits_3);
      if(io_rdAddr_fire) begin
        beat <= (beat + 2'b01);
      end
      if(when_TexCache_l104) begin
        filling <= 1'b1;
        fillBeat <= 2'b00;
      end
      if(when_TexCache_l109) begin
        fillBeat <= (fillBeat + 2'b01);
        if(when_TexCache_l111) begin
          filling <= 1'b0;
          filled <= 1'b1;
        end
      end
      if(go_fire) begin
        filled <= 1'b0;
      end
      if(go_translated_ready) begin
        _zz_rd_valid <= go_translated_valid;
      end
      if(rd_map_ready) begin
        rd_map_rValid <= rd_map_valid;
      end
    end
  end

  always @(posedge clk) begin
    if(entry_translated_ready) begin
      entry_payload_regNextWhen_x <= entry_payload_x;
      entry_payload_regNextWhen_y <= entry_payload_y;
      entry_payload_regNextWhen_z <= entry_payload_z;
      entry_payload_regNextWhen_addr <= entry_payload_addr;
      entry_payload_regNextWhen_nib <= entry_payload_nib;
      entry_payload_regNextWhen_light <= entry_payload_light;
      entry_payload_regNextWhen_flat <= entry_payload_flat;
      entry_payload_regNextWhen_blend <= entry_payload_blend;
      entry_payload_regNextWhen_tex4bpp <= entry_payload_tex4bpp;
      entry_payload_regNextWhen_pal <= entry_payload_pal;
    end
    if(allocate) begin
      lastWrIdx <= idx;
      lastWrTag <= tag;
    end
    if(go_translated_ready) begin
      go_payload_regNextWhen_f_x <= go_payload_f_x;
      go_payload_regNextWhen_f_y <= go_payload_f_y;
      go_payload_regNextWhen_f_z <= go_payload_f_z;
      go_payload_regNextWhen_f_addr <= go_payload_f_addr;
      go_payload_regNextWhen_f_nib <= go_payload_f_nib;
      go_payload_regNextWhen_f_light <= go_payload_f_light;
      go_payload_regNextWhen_f_flat <= go_payload_f_flat;
      go_payload_regNextWhen_f_blend <= go_payload_f_blend;
      go_payload_regNextWhen_f_tex4bpp <= go_payload_f_tex4bpp;
      go_payload_regNextWhen_f_pal <= go_payload_f_pal;
      go_payload_regNextWhen_word <= go_payload_word;
      go_payload_regNextWhen_byte <= go_payload_byte;
      go_payload_regNextWhen_miss <= go_payload_miss;
    end
    if(rd_map_ready) begin
      rd_map_rData_f_x <= rd_map_payload_f_x;
      rd_map_rData_f_y <= rd_map_payload_f_y;
      rd_map_rData_f_z <= rd_map_payload_f_z;
      rd_map_rData_f_addr <= rd_map_payload_f_addr;
      rd_map_rData_f_nib <= rd_map_payload_f_nib;
      rd_map_rData_f_light <= rd_map_payload_f_light;
      rd_map_rData_f_flat <= rd_map_payload_f_flat;
      rd_map_rData_f_blend <= rd_map_payload_f_blend;
      rd_map_rData_f_tex4bpp <= rd_map_payload_f_tex4bpp;
      rd_map_rData_f_pal <= rd_map_payload_f_pal;
      rd_map_rData_texel <= rd_map_payload_texel;
    end
  end


endmodule

module hng64_raster_PixelUnit (
  input  wire          io_i_valid,
  output wire          io_i_ready,
  input  wire [8:0]    io_i_payload_x,
  input  wire [8:0]    io_i_payload_y,
  input  wire [29:0]   io_i_payload_p_v_0,
  input  wire [33:0]   io_i_payload_p_v_1,
  input  wire [23:0]   io_i_payload_p_v_2,
  input  wire [31:0]   io_i_payload_p_v_3,
  input  wire [31:0]   io_i_payload_p_v_4,
  input  wire [66:0]   io_i_payload_attr,
  output wire          io_o_valid,
  input  wire          io_o_ready,
  output wire [8:0]    io_o_payload_x,
  output wire [8:0]    io_o_payload_y,
  output wire [29:0]   io_o_payload_z,
  output wire [23:0]   io_o_payload_addr,
  output wire          io_o_payload_nib,
  output wire [7:0]    io_o_payload_light,
  output wire          io_o_payload_flat,
  output wire          io_o_payload_blend,
  output wire          io_o_payload_tex4bpp,
  output wire [15:0]   io_o_payload_pal,
  output wire          io_busy,
  input  wire          clk,
  input  wire          reset
);

  reg        [11:0]   rom_spinal_port0;
  wire       [33:0]   _zz__zz_io_i_map_payload_e_3;
  wire                _zz__zz_io_i_map_payload_e_32;
  wire       [33:0]   _zz_a0_map_payload_wn;
  wire       [5:0]    _zz_a0_map_payload_wn_1;
  wire       [32:0]   _zz_b_map_payload_corr;
  wire       [22:0]   _zz_cS_map_payload_y1;
  wire       [45:0]   _zz_cS_map_payload_y1_1;
  wire       [31:0]   _zz_d_map_payload_sa;
  wire       [31:0]   _zz_d_map_payload_sa_1;
  wire       [31:0]   _zz_d_map_payload_sa_2;
  wire       [0:0]    _zz_d_map_payload_sa_3;
  wire       [31:0]   _zz_d_map_payload_ta;
  wire       [31:0]   _zz_d_map_payload_ta_1;
  wire       [31:0]   _zz_d_map_payload_ta_2;
  wire       [0:0]    _zz_d_map_payload_ta_3;
  wire       [23:0]   _zz_d_map_payload_la;
  wire       [23:0]   _zz_d_map_payload_la_1;
  wire       [23:0]   _zz_d_map_payload_la_2;
  wire       [0:0]    _zz_d_map_payload_la_3;
  wire       [6:0]    _zz__zz_e_map_payload_ps;
  wire       [6:0]    _zz__zz_e_map_payload_pl;
  wire       [45:0]   _zz_fc_map_payload_ml;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_4;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_4_1;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_4_2;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_4_3;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_4_4;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_4_5;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_4_6;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_4_7;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_4_8;
  wire       [8:0]    _zz__zz_f0_map_payload_addr_4_9;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_5;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_5_1;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_5_2;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_5_3;
  wire       [0:0]    _zz__zz_f0_map_payload_addr_5_4;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_5_5;
  wire       [3:0]    _zz__zz_f0_map_payload_addr_5_6;
  wire       [3:0]    _zz__zz_f0_map_payload_addr_5_7;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_6;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_6_1;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_6_2;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_6_3;
  wire       [6:0]    _zz__zz_f0_map_payload_addr_6_4;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_6_5;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_7;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_7_1;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_7_2;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_7_3;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_7_4;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_7_5;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_7_6;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_7_7;
  wire       [53:0]   _zz__zz_f0_map_payload_addr_7_8;
  wire       [8:0]    _zz__zz_f0_map_payload_addr_7_9;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_8;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_8_1;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_8_2;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_8_3;
  wire       [0:0]    _zz__zz_f0_map_payload_addr_8_4;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_8_5;
  wire       [3:0]    _zz__zz_f0_map_payload_addr_8_6;
  wire       [3:0]    _zz__zz_f0_map_payload_addr_8_7;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_9;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_9_1;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_9_2;
  wire       [9:0]    _zz__zz_f0_map_payload_addr_9_3;
  wire       [6:0]    _zz__zz_f0_map_payload_addr_9_4;
  wire       [54:0]   _zz__zz_f0_map_payload_addr_9_5;
  wire       [7:0]    _zz_f0_map_payload_light;
  wire       [11:0]   table_0;
  wire       [11:0]   table_1;
  wire       [11:0]   table_2;
  wire       [11:0]   table_3;
  wire       [11:0]   table_4;
  wire       [11:0]   table_5;
  wire       [11:0]   table_6;
  wire       [11:0]   table_7;
  wire       [11:0]   table_8;
  wire       [11:0]   table_9;
  wire       [11:0]   table_10;
  wire       [11:0]   table_11;
  wire       [11:0]   table_12;
  wire       [11:0]   table_13;
  wire       [11:0]   table_14;
  wire       [11:0]   table_15;
  wire       [11:0]   table_16;
  wire       [11:0]   table_17;
  wire       [11:0]   table_18;
  wire       [11:0]   table_19;
  wire       [11:0]   table_20;
  wire       [11:0]   table_21;
  wire       [11:0]   table_22;
  wire       [11:0]   table_23;
  wire       [11:0]   table_24;
  wire       [11:0]   table_25;
  wire       [11:0]   table_26;
  wire       [11:0]   table_27;
  wire       [11:0]   table_28;
  wire       [11:0]   table_29;
  wire       [11:0]   table_30;
  wire       [11:0]   table_31;
  wire       [11:0]   table_32;
  wire       [11:0]   table_33;
  wire       [11:0]   table_34;
  wire       [11:0]   table_35;
  wire       [11:0]   table_36;
  wire       [11:0]   table_37;
  wire       [11:0]   table_38;
  wire       [11:0]   table_39;
  wire       [11:0]   table_40;
  wire       [11:0]   table_41;
  wire       [11:0]   table_42;
  wire       [11:0]   table_43;
  wire       [11:0]   table_44;
  wire       [11:0]   table_45;
  wire       [11:0]   table_46;
  wire       [11:0]   table_47;
  wire       [11:0]   table_48;
  wire       [11:0]   table_49;
  wire       [11:0]   table_50;
  wire       [11:0]   table_51;
  wire       [11:0]   table_52;
  wire       [11:0]   table_53;
  wire       [11:0]   table_54;
  wire       [11:0]   table_55;
  wire       [11:0]   table_56;
  wire       [11:0]   table_57;
  wire       [11:0]   table_58;
  wire       [11:0]   table_59;
  wire       [11:0]   table_60;
  wire       [11:0]   table_61;
  wire       [11:0]   table_62;
  wire       [11:0]   table_63;
  wire       [11:0]   table_64;
  wire       [11:0]   table_65;
  wire       [11:0]   table_66;
  wire       [11:0]   table_67;
  wire       [11:0]   table_68;
  wire       [11:0]   table_69;
  wire       [11:0]   table_70;
  wire       [11:0]   table_71;
  wire       [11:0]   table_72;
  wire       [11:0]   table_73;
  wire       [11:0]   table_74;
  wire       [11:0]   table_75;
  wire       [11:0]   table_76;
  wire       [11:0]   table_77;
  wire       [11:0]   table_78;
  wire       [11:0]   table_79;
  wire       [11:0]   table_80;
  wire       [11:0]   table_81;
  wire       [11:0]   table_82;
  wire       [11:0]   table_83;
  wire       [11:0]   table_84;
  wire       [11:0]   table_85;
  wire       [11:0]   table_86;
  wire       [11:0]   table_87;
  wire       [11:0]   table_88;
  wire       [11:0]   table_89;
  wire       [11:0]   table_90;
  wire       [11:0]   table_91;
  wire       [11:0]   table_92;
  wire       [11:0]   table_93;
  wire       [11:0]   table_94;
  wire       [11:0]   table_95;
  wire       [11:0]   table_96;
  wire       [11:0]   table_97;
  wire       [11:0]   table_98;
  wire       [11:0]   table_99;
  wire       [11:0]   table_100;
  wire       [11:0]   table_101;
  wire       [11:0]   table_102;
  wire       [11:0]   table_103;
  wire       [11:0]   table_104;
  wire       [11:0]   table_105;
  wire       [11:0]   table_106;
  wire       [11:0]   table_107;
  wire       [11:0]   table_108;
  wire       [11:0]   table_109;
  wire       [11:0]   table_110;
  wire       [11:0]   table_111;
  wire       [11:0]   table_112;
  wire       [11:0]   table_113;
  wire       [11:0]   table_114;
  wire       [11:0]   table_115;
  wire       [11:0]   table_116;
  wire       [11:0]   table_117;
  wire       [11:0]   table_118;
  wire       [11:0]   table_119;
  wire       [11:0]   table_120;
  wire       [11:0]   table_121;
  wire       [11:0]   table_122;
  wire       [11:0]   table_123;
  wire       [11:0]   table_124;
  wire       [11:0]   table_125;
  wire       [11:0]   table_126;
  wire       [11:0]   table_127;
  wire       [11:0]   table_128;
  wire       [11:0]   table_129;
  wire       [11:0]   table_130;
  wire       [11:0]   table_131;
  wire       [11:0]   table_132;
  wire       [11:0]   table_133;
  wire       [11:0]   table_134;
  wire       [11:0]   table_135;
  wire       [11:0]   table_136;
  wire       [11:0]   table_137;
  wire       [11:0]   table_138;
  wire       [11:0]   table_139;
  wire       [11:0]   table_140;
  wire       [11:0]   table_141;
  wire       [11:0]   table_142;
  wire       [11:0]   table_143;
  wire       [11:0]   table_144;
  wire       [11:0]   table_145;
  wire       [11:0]   table_146;
  wire       [11:0]   table_147;
  wire       [11:0]   table_148;
  wire       [11:0]   table_149;
  wire       [11:0]   table_150;
  wire       [11:0]   table_151;
  wire       [11:0]   table_152;
  wire       [11:0]   table_153;
  wire       [11:0]   table_154;
  wire       [11:0]   table_155;
  wire       [11:0]   table_156;
  wire       [11:0]   table_157;
  wire       [11:0]   table_158;
  wire       [11:0]   table_159;
  wire       [11:0]   table_160;
  wire       [11:0]   table_161;
  wire       [11:0]   table_162;
  wire       [11:0]   table_163;
  wire       [11:0]   table_164;
  wire       [11:0]   table_165;
  wire       [11:0]   table_166;
  wire       [11:0]   table_167;
  wire       [11:0]   table_168;
  wire       [11:0]   table_169;
  wire       [11:0]   table_170;
  wire       [11:0]   table_171;
  wire       [11:0]   table_172;
  wire       [11:0]   table_173;
  wire       [11:0]   table_174;
  wire       [11:0]   table_175;
  wire       [11:0]   table_176;
  wire       [11:0]   table_177;
  wire       [11:0]   table_178;
  wire       [11:0]   table_179;
  wire       [11:0]   table_180;
  wire       [11:0]   table_181;
  wire       [11:0]   table_182;
  wire       [11:0]   table_183;
  wire       [11:0]   table_184;
  wire       [11:0]   table_185;
  wire       [11:0]   table_186;
  wire       [11:0]   table_187;
  wire       [11:0]   table_188;
  wire       [11:0]   table_189;
  wire       [11:0]   table_190;
  wire       [11:0]   table_191;
  wire       [11:0]   table_192;
  wire       [11:0]   table_193;
  wire       [11:0]   table_194;
  wire       [11:0]   table_195;
  wire       [11:0]   table_196;
  wire       [11:0]   table_197;
  wire       [11:0]   table_198;
  wire       [11:0]   table_199;
  wire       [11:0]   table_200;
  wire       [11:0]   table_201;
  wire       [11:0]   table_202;
  wire       [11:0]   table_203;
  wire       [11:0]   table_204;
  wire       [11:0]   table_205;
  wire       [11:0]   table_206;
  wire       [11:0]   table_207;
  wire       [11:0]   table_208;
  wire       [11:0]   table_209;
  wire       [11:0]   table_210;
  wire       [11:0]   table_211;
  wire       [11:0]   table_212;
  wire       [11:0]   table_213;
  wire       [11:0]   table_214;
  wire       [11:0]   table_215;
  wire       [11:0]   table_216;
  wire       [11:0]   table_217;
  wire       [11:0]   table_218;
  wire       [11:0]   table_219;
  wire       [11:0]   table_220;
  wire       [11:0]   table_221;
  wire       [11:0]   table_222;
  wire       [11:0]   table_223;
  wire       [11:0]   table_224;
  wire       [11:0]   table_225;
  wire       [11:0]   table_226;
  wire       [11:0]   table_227;
  wire       [11:0]   table_228;
  wire       [11:0]   table_229;
  wire       [11:0]   table_230;
  wire       [11:0]   table_231;
  wire       [11:0]   table_232;
  wire       [11:0]   table_233;
  wire       [11:0]   table_234;
  wire       [11:0]   table_235;
  wire       [11:0]   table_236;
  wire       [11:0]   table_237;
  wire       [11:0]   table_238;
  wire       [11:0]   table_239;
  wire       [11:0]   table_240;
  wire       [11:0]   table_241;
  wire       [11:0]   table_242;
  wire       [11:0]   table_243;
  wire       [11:0]   table_244;
  wire       [11:0]   table_245;
  wire       [11:0]   table_246;
  wire       [11:0]   table_247;
  wire       [11:0]   table_248;
  wire       [11:0]   table_249;
  wire       [11:0]   table_250;
  wire       [11:0]   table_251;
  wire       [11:0]   table_252;
  wire       [11:0]   table_253;
  wire       [11:0]   table_254;
  wire       [11:0]   table_255;
  wire       [11:0]   table_256;
  wire       [11:0]   table_257;
  wire       [11:0]   table_258;
  wire       [11:0]   table_259;
  wire       [11:0]   table_260;
  wire       [11:0]   table_261;
  wire       [11:0]   table_262;
  wire       [11:0]   table_263;
  wire       [11:0]   table_264;
  wire       [11:0]   table_265;
  wire       [11:0]   table_266;
  wire       [11:0]   table_267;
  wire       [11:0]   table_268;
  wire       [11:0]   table_269;
  wire       [11:0]   table_270;
  wire       [11:0]   table_271;
  wire       [11:0]   table_272;
  wire       [11:0]   table_273;
  wire       [11:0]   table_274;
  wire       [11:0]   table_275;
  wire       [11:0]   table_276;
  wire       [11:0]   table_277;
  wire       [11:0]   table_278;
  wire       [11:0]   table_279;
  wire       [11:0]   table_280;
  wire       [11:0]   table_281;
  wire       [11:0]   table_282;
  wire       [11:0]   table_283;
  wire       [11:0]   table_284;
  wire       [11:0]   table_285;
  wire       [11:0]   table_286;
  wire       [11:0]   table_287;
  wire       [11:0]   table_288;
  wire       [11:0]   table_289;
  wire       [11:0]   table_290;
  wire       [11:0]   table_291;
  wire       [11:0]   table_292;
  wire       [11:0]   table_293;
  wire       [11:0]   table_294;
  wire       [11:0]   table_295;
  wire       [11:0]   table_296;
  wire       [11:0]   table_297;
  wire       [11:0]   table_298;
  wire       [11:0]   table_299;
  wire       [11:0]   table_300;
  wire       [11:0]   table_301;
  wire       [11:0]   table_302;
  wire       [11:0]   table_303;
  wire       [11:0]   table_304;
  wire       [11:0]   table_305;
  wire       [11:0]   table_306;
  wire       [11:0]   table_307;
  wire       [11:0]   table_308;
  wire       [11:0]   table_309;
  wire       [11:0]   table_310;
  wire       [11:0]   table_311;
  wire       [11:0]   table_312;
  wire       [11:0]   table_313;
  wire       [11:0]   table_314;
  wire       [11:0]   table_315;
  wire       [11:0]   table_316;
  wire       [11:0]   table_317;
  wire       [11:0]   table_318;
  wire       [11:0]   table_319;
  wire       [11:0]   table_320;
  wire       [11:0]   table_321;
  wire       [11:0]   table_322;
  wire       [11:0]   table_323;
  wire       [11:0]   table_324;
  wire       [11:0]   table_325;
  wire       [11:0]   table_326;
  wire       [11:0]   table_327;
  wire       [11:0]   table_328;
  wire       [11:0]   table_329;
  wire       [11:0]   table_330;
  wire       [11:0]   table_331;
  wire       [11:0]   table_332;
  wire       [11:0]   table_333;
  wire       [11:0]   table_334;
  wire       [11:0]   table_335;
  wire       [11:0]   table_336;
  wire       [11:0]   table_337;
  wire       [11:0]   table_338;
  wire       [11:0]   table_339;
  wire       [11:0]   table_340;
  wire       [11:0]   table_341;
  wire       [11:0]   table_342;
  wire       [11:0]   table_343;
  wire       [11:0]   table_344;
  wire       [11:0]   table_345;
  wire       [11:0]   table_346;
  wire       [11:0]   table_347;
  wire       [11:0]   table_348;
  wire       [11:0]   table_349;
  wire       [11:0]   table_350;
  wire       [11:0]   table_351;
  wire       [11:0]   table_352;
  wire       [11:0]   table_353;
  wire       [11:0]   table_354;
  wire       [11:0]   table_355;
  wire       [11:0]   table_356;
  wire       [11:0]   table_357;
  wire       [11:0]   table_358;
  wire       [11:0]   table_359;
  wire       [11:0]   table_360;
  wire       [11:0]   table_361;
  wire       [11:0]   table_362;
  wire       [11:0]   table_363;
  wire       [11:0]   table_364;
  wire       [11:0]   table_365;
  wire       [11:0]   table_366;
  wire       [11:0]   table_367;
  wire       [11:0]   table_368;
  wire       [11:0]   table_369;
  wire       [11:0]   table_370;
  wire       [11:0]   table_371;
  wire       [11:0]   table_372;
  wire       [11:0]   table_373;
  wire       [11:0]   table_374;
  wire       [11:0]   table_375;
  wire       [11:0]   table_376;
  wire       [11:0]   table_377;
  wire       [11:0]   table_378;
  wire       [11:0]   table_379;
  wire       [11:0]   table_380;
  wire       [11:0]   table_381;
  wire       [11:0]   table_382;
  wire       [11:0]   table_383;
  wire       [11:0]   table_384;
  wire       [11:0]   table_385;
  wire       [11:0]   table_386;
  wire       [11:0]   table_387;
  wire       [11:0]   table_388;
  wire       [11:0]   table_389;
  wire       [11:0]   table_390;
  wire       [11:0]   table_391;
  wire       [11:0]   table_392;
  wire       [11:0]   table_393;
  wire       [11:0]   table_394;
  wire       [11:0]   table_395;
  wire       [11:0]   table_396;
  wire       [11:0]   table_397;
  wire       [11:0]   table_398;
  wire       [11:0]   table_399;
  wire       [11:0]   table_400;
  wire       [11:0]   table_401;
  wire       [11:0]   table_402;
  wire       [11:0]   table_403;
  wire       [11:0]   table_404;
  wire       [11:0]   table_405;
  wire       [11:0]   table_406;
  wire       [11:0]   table_407;
  wire       [11:0]   table_408;
  wire       [11:0]   table_409;
  wire       [11:0]   table_410;
  wire       [11:0]   table_411;
  wire       [11:0]   table_412;
  wire       [11:0]   table_413;
  wire       [11:0]   table_414;
  wire       [11:0]   table_415;
  wire       [11:0]   table_416;
  wire       [11:0]   table_417;
  wire       [11:0]   table_418;
  wire       [11:0]   table_419;
  wire       [11:0]   table_420;
  wire       [11:0]   table_421;
  wire       [11:0]   table_422;
  wire       [11:0]   table_423;
  wire       [11:0]   table_424;
  wire       [11:0]   table_425;
  wire       [11:0]   table_426;
  wire       [11:0]   table_427;
  wire       [11:0]   table_428;
  wire       [11:0]   table_429;
  wire       [11:0]   table_430;
  wire       [11:0]   table_431;
  wire       [11:0]   table_432;
  wire       [11:0]   table_433;
  wire       [11:0]   table_434;
  wire       [11:0]   table_435;
  wire       [11:0]   table_436;
  wire       [11:0]   table_437;
  wire       [11:0]   table_438;
  wire       [11:0]   table_439;
  wire       [11:0]   table_440;
  wire       [11:0]   table_441;
  wire       [11:0]   table_442;
  wire       [11:0]   table_443;
  wire       [11:0]   table_444;
  wire       [11:0]   table_445;
  wire       [11:0]   table_446;
  wire       [11:0]   table_447;
  wire       [11:0]   table_448;
  wire       [11:0]   table_449;
  wire       [11:0]   table_450;
  wire       [11:0]   table_451;
  wire       [11:0]   table_452;
  wire       [11:0]   table_453;
  wire       [11:0]   table_454;
  wire       [11:0]   table_455;
  wire       [11:0]   table_456;
  wire       [11:0]   table_457;
  wire       [11:0]   table_458;
  wire       [11:0]   table_459;
  wire       [11:0]   table_460;
  wire       [11:0]   table_461;
  wire       [11:0]   table_462;
  wire       [11:0]   table_463;
  wire       [11:0]   table_464;
  wire       [11:0]   table_465;
  wire       [11:0]   table_466;
  wire       [11:0]   table_467;
  wire       [11:0]   table_468;
  wire       [11:0]   table_469;
  wire       [11:0]   table_470;
  wire       [11:0]   table_471;
  wire       [11:0]   table_472;
  wire       [11:0]   table_473;
  wire       [11:0]   table_474;
  wire       [11:0]   table_475;
  wire       [11:0]   table_476;
  wire       [11:0]   table_477;
  wire       [11:0]   table_478;
  wire       [11:0]   table_479;
  wire       [11:0]   table_480;
  wire       [11:0]   table_481;
  wire       [11:0]   table_482;
  wire       [11:0]   table_483;
  wire       [11:0]   table_484;
  wire       [11:0]   table_485;
  wire       [11:0]   table_486;
  wire       [11:0]   table_487;
  wire       [11:0]   table_488;
  wire       [11:0]   table_489;
  wire       [11:0]   table_490;
  wire       [11:0]   table_491;
  wire       [11:0]   table_492;
  wire       [11:0]   table_493;
  wire       [11:0]   table_494;
  wire       [11:0]   table_495;
  wire       [11:0]   table_496;
  wire       [11:0]   table_497;
  wire       [11:0]   table_498;
  wire       [11:0]   table_499;
  wire       [11:0]   table_500;
  wire       [11:0]   table_501;
  wire       [11:0]   table_502;
  wire       [11:0]   table_503;
  wire       [11:0]   table_504;
  wire       [11:0]   table_505;
  wire       [11:0]   table_506;
  wire       [11:0]   table_507;
  wire       [11:0]   table_508;
  wire       [11:0]   table_509;
  wire       [11:0]   table_510;
  wire       [11:0]   table_511;
  wire       [11:0]   table_512;
  wire       [11:0]   table_513;
  wire       [11:0]   table_514;
  wire       [11:0]   table_515;
  wire       [11:0]   table_516;
  wire       [11:0]   table_517;
  wire       [11:0]   table_518;
  wire       [11:0]   table_519;
  wire       [11:0]   table_520;
  wire       [11:0]   table_521;
  wire       [11:0]   table_522;
  wire       [11:0]   table_523;
  wire       [11:0]   table_524;
  wire       [11:0]   table_525;
  wire       [11:0]   table_526;
  wire       [11:0]   table_527;
  wire       [11:0]   table_528;
  wire       [11:0]   table_529;
  wire       [11:0]   table_530;
  wire       [11:0]   table_531;
  wire       [11:0]   table_532;
  wire       [11:0]   table_533;
  wire       [11:0]   table_534;
  wire       [11:0]   table_535;
  wire       [11:0]   table_536;
  wire       [11:0]   table_537;
  wire       [11:0]   table_538;
  wire       [11:0]   table_539;
  wire       [11:0]   table_540;
  wire       [11:0]   table_541;
  wire       [11:0]   table_542;
  wire       [11:0]   table_543;
  wire       [11:0]   table_544;
  wire       [11:0]   table_545;
  wire       [11:0]   table_546;
  wire       [11:0]   table_547;
  wire       [11:0]   table_548;
  wire       [11:0]   table_549;
  wire       [11:0]   table_550;
  wire       [11:0]   table_551;
  wire       [11:0]   table_552;
  wire       [11:0]   table_553;
  wire       [11:0]   table_554;
  wire       [11:0]   table_555;
  wire       [11:0]   table_556;
  wire       [11:0]   table_557;
  wire       [11:0]   table_558;
  wire       [11:0]   table_559;
  wire       [11:0]   table_560;
  wire       [11:0]   table_561;
  wire       [11:0]   table_562;
  wire       [11:0]   table_563;
  wire       [11:0]   table_564;
  wire       [11:0]   table_565;
  wire       [11:0]   table_566;
  wire       [11:0]   table_567;
  wire       [11:0]   table_568;
  wire       [11:0]   table_569;
  wire       [11:0]   table_570;
  wire       [11:0]   table_571;
  wire       [11:0]   table_572;
  wire       [11:0]   table_573;
  wire       [11:0]   table_574;
  wire       [11:0]   table_575;
  wire       [11:0]   table_576;
  wire       [11:0]   table_577;
  wire       [11:0]   table_578;
  wire       [11:0]   table_579;
  wire       [11:0]   table_580;
  wire       [11:0]   table_581;
  wire       [11:0]   table_582;
  wire       [11:0]   table_583;
  wire       [11:0]   table_584;
  wire       [11:0]   table_585;
  wire       [11:0]   table_586;
  wire       [11:0]   table_587;
  wire       [11:0]   table_588;
  wire       [11:0]   table_589;
  wire       [11:0]   table_590;
  wire       [11:0]   table_591;
  wire       [11:0]   table_592;
  wire       [11:0]   table_593;
  wire       [11:0]   table_594;
  wire       [11:0]   table_595;
  wire       [11:0]   table_596;
  wire       [11:0]   table_597;
  wire       [11:0]   table_598;
  wire       [11:0]   table_599;
  wire       [11:0]   table_600;
  wire       [11:0]   table_601;
  wire       [11:0]   table_602;
  wire       [11:0]   table_603;
  wire       [11:0]   table_604;
  wire       [11:0]   table_605;
  wire       [11:0]   table_606;
  wire       [11:0]   table_607;
  wire       [11:0]   table_608;
  wire       [11:0]   table_609;
  wire       [11:0]   table_610;
  wire       [11:0]   table_611;
  wire       [11:0]   table_612;
  wire       [11:0]   table_613;
  wire       [11:0]   table_614;
  wire       [11:0]   table_615;
  wire       [11:0]   table_616;
  wire       [11:0]   table_617;
  wire       [11:0]   table_618;
  wire       [11:0]   table_619;
  wire       [11:0]   table_620;
  wire       [11:0]   table_621;
  wire       [11:0]   table_622;
  wire       [11:0]   table_623;
  wire       [11:0]   table_624;
  wire       [11:0]   table_625;
  wire       [11:0]   table_626;
  wire       [11:0]   table_627;
  wire       [11:0]   table_628;
  wire       [11:0]   table_629;
  wire       [11:0]   table_630;
  wire       [11:0]   table_631;
  wire       [11:0]   table_632;
  wire       [11:0]   table_633;
  wire       [11:0]   table_634;
  wire       [11:0]   table_635;
  wire       [11:0]   table_636;
  wire       [11:0]   table_637;
  wire       [11:0]   table_638;
  wire       [11:0]   table_639;
  wire       [11:0]   table_640;
  wire       [11:0]   table_641;
  wire       [11:0]   table_642;
  wire       [11:0]   table_643;
  wire       [11:0]   table_644;
  wire       [11:0]   table_645;
  wire       [11:0]   table_646;
  wire       [11:0]   table_647;
  wire       [11:0]   table_648;
  wire       [11:0]   table_649;
  wire       [11:0]   table_650;
  wire       [11:0]   table_651;
  wire       [11:0]   table_652;
  wire       [11:0]   table_653;
  wire       [11:0]   table_654;
  wire       [11:0]   table_655;
  wire       [11:0]   table_656;
  wire       [11:0]   table_657;
  wire       [11:0]   table_658;
  wire       [11:0]   table_659;
  wire       [11:0]   table_660;
  wire       [11:0]   table_661;
  wire       [11:0]   table_662;
  wire       [11:0]   table_663;
  wire       [11:0]   table_664;
  wire       [11:0]   table_665;
  wire       [11:0]   table_666;
  wire       [11:0]   table_667;
  wire       [11:0]   table_668;
  wire       [11:0]   table_669;
  wire       [11:0]   table_670;
  wire       [11:0]   table_671;
  wire       [11:0]   table_672;
  wire       [11:0]   table_673;
  wire       [11:0]   table_674;
  wire       [11:0]   table_675;
  wire       [11:0]   table_676;
  wire       [11:0]   table_677;
  wire       [11:0]   table_678;
  wire       [11:0]   table_679;
  wire       [11:0]   table_680;
  wire       [11:0]   table_681;
  wire       [11:0]   table_682;
  wire       [11:0]   table_683;
  wire       [11:0]   table_684;
  wire       [11:0]   table_685;
  wire       [11:0]   table_686;
  wire       [11:0]   table_687;
  wire       [11:0]   table_688;
  wire       [11:0]   table_689;
  wire       [11:0]   table_690;
  wire       [11:0]   table_691;
  wire       [11:0]   table_692;
  wire       [11:0]   table_693;
  wire       [11:0]   table_694;
  wire       [11:0]   table_695;
  wire       [11:0]   table_696;
  wire       [11:0]   table_697;
  wire       [11:0]   table_698;
  wire       [11:0]   table_699;
  wire       [11:0]   table_700;
  wire       [11:0]   table_701;
  wire       [11:0]   table_702;
  wire       [11:0]   table_703;
  wire       [11:0]   table_704;
  wire       [11:0]   table_705;
  wire       [11:0]   table_706;
  wire       [11:0]   table_707;
  wire       [11:0]   table_708;
  wire       [11:0]   table_709;
  wire       [11:0]   table_710;
  wire       [11:0]   table_711;
  wire       [11:0]   table_712;
  wire       [11:0]   table_713;
  wire       [11:0]   table_714;
  wire       [11:0]   table_715;
  wire       [11:0]   table_716;
  wire       [11:0]   table_717;
  wire       [11:0]   table_718;
  wire       [11:0]   table_719;
  wire       [11:0]   table_720;
  wire       [11:0]   table_721;
  wire       [11:0]   table_722;
  wire       [11:0]   table_723;
  wire       [11:0]   table_724;
  wire       [11:0]   table_725;
  wire       [11:0]   table_726;
  wire       [11:0]   table_727;
  wire       [11:0]   table_728;
  wire       [11:0]   table_729;
  wire       [11:0]   table_730;
  wire       [11:0]   table_731;
  wire       [11:0]   table_732;
  wire       [11:0]   table_733;
  wire       [11:0]   table_734;
  wire       [11:0]   table_735;
  wire       [11:0]   table_736;
  wire       [11:0]   table_737;
  wire       [11:0]   table_738;
  wire       [11:0]   table_739;
  wire       [11:0]   table_740;
  wire       [11:0]   table_741;
  wire       [11:0]   table_742;
  wire       [11:0]   table_743;
  wire       [11:0]   table_744;
  wire       [11:0]   table_745;
  wire       [11:0]   table_746;
  wire       [11:0]   table_747;
  wire       [11:0]   table_748;
  wire       [11:0]   table_749;
  wire       [11:0]   table_750;
  wire       [11:0]   table_751;
  wire       [11:0]   table_752;
  wire       [11:0]   table_753;
  wire       [11:0]   table_754;
  wire       [11:0]   table_755;
  wire       [11:0]   table_756;
  wire       [11:0]   table_757;
  wire       [11:0]   table_758;
  wire       [11:0]   table_759;
  wire       [11:0]   table_760;
  wire       [11:0]   table_761;
  wire       [11:0]   table_762;
  wire       [11:0]   table_763;
  wire       [11:0]   table_764;
  wire       [11:0]   table_765;
  wire       [11:0]   table_766;
  wire       [11:0]   table_767;
  wire       [11:0]   table_768;
  wire       [11:0]   table_769;
  wire       [11:0]   table_770;
  wire       [11:0]   table_771;
  wire       [11:0]   table_772;
  wire       [11:0]   table_773;
  wire       [11:0]   table_774;
  wire       [11:0]   table_775;
  wire       [11:0]   table_776;
  wire       [11:0]   table_777;
  wire       [11:0]   table_778;
  wire       [11:0]   table_779;
  wire       [11:0]   table_780;
  wire       [11:0]   table_781;
  wire       [11:0]   table_782;
  wire       [11:0]   table_783;
  wire       [11:0]   table_784;
  wire       [11:0]   table_785;
  wire       [11:0]   table_786;
  wire       [11:0]   table_787;
  wire       [11:0]   table_788;
  wire       [11:0]   table_789;
  wire       [11:0]   table_790;
  wire       [11:0]   table_791;
  wire       [11:0]   table_792;
  wire       [11:0]   table_793;
  wire       [11:0]   table_794;
  wire       [11:0]   table_795;
  wire       [11:0]   table_796;
  wire       [11:0]   table_797;
  wire       [11:0]   table_798;
  wire       [11:0]   table_799;
  wire       [11:0]   table_800;
  wire       [11:0]   table_801;
  wire       [11:0]   table_802;
  wire       [11:0]   table_803;
  wire       [11:0]   table_804;
  wire       [11:0]   table_805;
  wire       [11:0]   table_806;
  wire       [11:0]   table_807;
  wire       [11:0]   table_808;
  wire       [11:0]   table_809;
  wire       [11:0]   table_810;
  wire       [11:0]   table_811;
  wire       [11:0]   table_812;
  wire       [11:0]   table_813;
  wire       [11:0]   table_814;
  wire       [11:0]   table_815;
  wire       [11:0]   table_816;
  wire       [11:0]   table_817;
  wire       [11:0]   table_818;
  wire       [11:0]   table_819;
  wire       [11:0]   table_820;
  wire       [11:0]   table_821;
  wire       [11:0]   table_822;
  wire       [11:0]   table_823;
  wire       [11:0]   table_824;
  wire       [11:0]   table_825;
  wire       [11:0]   table_826;
  wire       [11:0]   table_827;
  wire       [11:0]   table_828;
  wire       [11:0]   table_829;
  wire       [11:0]   table_830;
  wire       [11:0]   table_831;
  wire       [11:0]   table_832;
  wire       [11:0]   table_833;
  wire       [11:0]   table_834;
  wire       [11:0]   table_835;
  wire       [11:0]   table_836;
  wire       [11:0]   table_837;
  wire       [11:0]   table_838;
  wire       [11:0]   table_839;
  wire       [11:0]   table_840;
  wire       [11:0]   table_841;
  wire       [11:0]   table_842;
  wire       [11:0]   table_843;
  wire       [11:0]   table_844;
  wire       [11:0]   table_845;
  wire       [11:0]   table_846;
  wire       [11:0]   table_847;
  wire       [11:0]   table_848;
  wire       [11:0]   table_849;
  wire       [11:0]   table_850;
  wire       [11:0]   table_851;
  wire       [11:0]   table_852;
  wire       [11:0]   table_853;
  wire       [11:0]   table_854;
  wire       [11:0]   table_855;
  wire       [11:0]   table_856;
  wire       [11:0]   table_857;
  wire       [11:0]   table_858;
  wire       [11:0]   table_859;
  wire       [11:0]   table_860;
  wire       [11:0]   table_861;
  wire       [11:0]   table_862;
  wire       [11:0]   table_863;
  wire       [11:0]   table_864;
  wire       [11:0]   table_865;
  wire       [11:0]   table_866;
  wire       [11:0]   table_867;
  wire       [11:0]   table_868;
  wire       [11:0]   table_869;
  wire       [11:0]   table_870;
  wire       [11:0]   table_871;
  wire       [11:0]   table_872;
  wire       [11:0]   table_873;
  wire       [11:0]   table_874;
  wire       [11:0]   table_875;
  wire       [11:0]   table_876;
  wire       [11:0]   table_877;
  wire       [11:0]   table_878;
  wire       [11:0]   table_879;
  wire       [11:0]   table_880;
  wire       [11:0]   table_881;
  wire       [11:0]   table_882;
  wire       [11:0]   table_883;
  wire       [11:0]   table_884;
  wire       [11:0]   table_885;
  wire       [11:0]   table_886;
  wire       [11:0]   table_887;
  wire       [11:0]   table_888;
  wire       [11:0]   table_889;
  wire       [11:0]   table_890;
  wire       [11:0]   table_891;
  wire       [11:0]   table_892;
  wire       [11:0]   table_893;
  wire       [11:0]   table_894;
  wire       [11:0]   table_895;
  wire       [11:0]   table_896;
  wire       [11:0]   table_897;
  wire       [11:0]   table_898;
  wire       [11:0]   table_899;
  wire       [11:0]   table_900;
  wire       [11:0]   table_901;
  wire       [11:0]   table_902;
  wire       [11:0]   table_903;
  wire       [11:0]   table_904;
  wire       [11:0]   table_905;
  wire       [11:0]   table_906;
  wire       [11:0]   table_907;
  wire       [11:0]   table_908;
  wire       [11:0]   table_909;
  wire       [11:0]   table_910;
  wire       [11:0]   table_911;
  wire       [11:0]   table_912;
  wire       [11:0]   table_913;
  wire       [11:0]   table_914;
  wire       [11:0]   table_915;
  wire       [11:0]   table_916;
  wire       [11:0]   table_917;
  wire       [11:0]   table_918;
  wire       [11:0]   table_919;
  wire       [11:0]   table_920;
  wire       [11:0]   table_921;
  wire       [11:0]   table_922;
  wire       [11:0]   table_923;
  wire       [11:0]   table_924;
  wire       [11:0]   table_925;
  wire       [11:0]   table_926;
  wire       [11:0]   table_927;
  wire       [11:0]   table_928;
  wire       [11:0]   table_929;
  wire       [11:0]   table_930;
  wire       [11:0]   table_931;
  wire       [11:0]   table_932;
  wire       [11:0]   table_933;
  wire       [11:0]   table_934;
  wire       [11:0]   table_935;
  wire       [11:0]   table_936;
  wire       [11:0]   table_937;
  wire       [11:0]   table_938;
  wire       [11:0]   table_939;
  wire       [11:0]   table_940;
  wire       [11:0]   table_941;
  wire       [11:0]   table_942;
  wire       [11:0]   table_943;
  wire       [11:0]   table_944;
  wire       [11:0]   table_945;
  wire       [11:0]   table_946;
  wire       [11:0]   table_947;
  wire       [11:0]   table_948;
  wire       [11:0]   table_949;
  wire       [11:0]   table_950;
  wire       [11:0]   table_951;
  wire       [11:0]   table_952;
  wire       [11:0]   table_953;
  wire       [11:0]   table_954;
  wire       [11:0]   table_955;
  wire       [11:0]   table_956;
  wire       [11:0]   table_957;
  wire       [11:0]   table_958;
  wire       [11:0]   table_959;
  wire       [11:0]   table_960;
  wire       [11:0]   table_961;
  wire       [11:0]   table_962;
  wire       [11:0]   table_963;
  wire       [11:0]   table_964;
  wire       [11:0]   table_965;
  wire       [11:0]   table_966;
  wire       [11:0]   table_967;
  wire       [11:0]   table_968;
  wire       [11:0]   table_969;
  wire       [11:0]   table_970;
  wire       [11:0]   table_971;
  wire       [11:0]   table_972;
  wire       [11:0]   table_973;
  wire       [11:0]   table_974;
  wire       [11:0]   table_975;
  wire       [11:0]   table_976;
  wire       [11:0]   table_977;
  wire       [11:0]   table_978;
  wire       [11:0]   table_979;
  wire       [11:0]   table_980;
  wire       [11:0]   table_981;
  wire       [11:0]   table_982;
  wire       [11:0]   table_983;
  wire       [11:0]   table_984;
  wire       [11:0]   table_985;
  wire       [11:0]   table_986;
  wire       [11:0]   table_987;
  wire       [11:0]   table_988;
  wire       [11:0]   table_989;
  wire       [11:0]   table_990;
  wire       [11:0]   table_991;
  wire       [11:0]   table_992;
  wire       [11:0]   table_993;
  wire       [11:0]   table_994;
  wire       [11:0]   table_995;
  wire       [11:0]   table_996;
  wire       [11:0]   table_997;
  wire       [11:0]   table_998;
  wire       [11:0]   table_999;
  wire       [11:0]   table_1000;
  wire       [11:0]   table_1001;
  wire       [11:0]   table_1002;
  wire       [11:0]   table_1003;
  wire       [11:0]   table_1004;
  wire       [11:0]   table_1005;
  wire       [11:0]   table_1006;
  wire       [11:0]   table_1007;
  wire       [11:0]   table_1008;
  wire       [11:0]   table_1009;
  wire       [11:0]   table_1010;
  wire       [11:0]   table_1011;
  wire       [11:0]   table_1012;
  wire       [11:0]   table_1013;
  wire       [11:0]   table_1014;
  wire       [11:0]   table_1015;
  wire       [11:0]   table_1016;
  wire       [11:0]   table_1017;
  wire       [11:0]   table_1018;
  wire       [11:0]   table_1019;
  wire       [11:0]   table_1020;
  wire       [11:0]   table_1021;
  wire       [11:0]   table_1022;
  wire       [11:0]   table_1023;
  wire                _zz_io_i_map_payload_wu;
  wire       [33:0]   _zz_io_i_map_payload_e;
  reg        [33:0]   _zz_io_i_map_payload_e_1;
  wire       [33:0]   _zz_io_i_map_payload_e_2;
  wire       [33:0]   _zz_io_i_map_payload_e_3;
  reg        [33:0]   _zz_io_i_map_payload_e_4;
  wire                _zz_io_i_map_payload_e_5;
  wire                _zz_io_i_map_payload_e_6;
  wire                _zz_io_i_map_payload_e_7;
  wire                _zz_io_i_map_payload_e_8;
  wire                _zz_io_i_map_payload_e_9;
  wire                _zz_io_i_map_payload_e_10;
  wire                _zz_io_i_map_payload_e_11;
  wire                _zz_io_i_map_payload_e_12;
  wire                _zz_io_i_map_payload_e_13;
  wire                _zz_io_i_map_payload_e_14;
  wire                _zz_io_i_map_payload_e_15;
  wire                _zz_io_i_map_payload_e_16;
  wire                _zz_io_i_map_payload_e_17;
  wire                _zz_io_i_map_payload_e_18;
  wire                _zz_io_i_map_payload_e_19;
  wire                _zz_io_i_map_payload_e_20;
  wire                _zz_io_i_map_payload_e_21;
  wire                _zz_io_i_map_payload_e_22;
  wire                _zz_io_i_map_payload_e_23;
  wire                _zz_io_i_map_payload_e_24;
  wire                _zz_io_i_map_payload_e_25;
  wire                _zz_io_i_map_payload_e_26;
  wire                _zz_io_i_map_payload_e_27;
  wire                _zz_io_i_map_payload_e_28;
  wire                _zz_io_i_map_payload_e_29;
  wire                _zz_io_i_map_payload_e_30;
  wire                _zz_io_i_map_payload_e_31;
  wire                _zz_io_i_map_payload_e_32;
  wire                _zz_io_i_map_payload_e_33;
  wire                _zz_io_i_map_payload_e_34;
  wire                _zz_io_i_map_payload_e_35;
  wire                _zz_io_i_map_payload_e_36;
  wire                _zz_io_i_map_payload_e_37;
  wire                io_i_map_valid;
  reg                 io_i_map_ready;
  wire       [8:0]    io_i_map_payload_px_x;
  wire       [8:0]    io_i_map_payload_px_y;
  wire       [29:0]   io_i_map_payload_px_p_v_0;
  wire       [33:0]   io_i_map_payload_px_p_v_1;
  wire       [23:0]   io_i_map_payload_px_p_v_2;
  wire       [31:0]   io_i_map_payload_px_p_v_3;
  wire       [31:0]   io_i_map_payload_px_p_v_4;
  wire       [66:0]   io_i_map_payload_px_attr;
  wire       [33:0]   io_i_map_payload_wu;
  wire       [5:0]    io_i_map_payload_e;
  wire                a0_valid;
  wire                a0_ready;
  wire       [8:0]    a0_payload_px_x;
  wire       [8:0]    a0_payload_px_y;
  wire       [29:0]   a0_payload_px_p_v_0;
  wire       [33:0]   a0_payload_px_p_v_1;
  wire       [23:0]   a0_payload_px_p_v_2;
  wire       [31:0]   a0_payload_px_p_v_3;
  wire       [31:0]   a0_payload_px_p_v_4;
  wire       [66:0]   a0_payload_px_attr;
  wire       [33:0]   a0_payload_wu;
  wire       [5:0]    a0_payload_e;
  reg                 io_i_map_rValid;
  reg        [8:0]    io_i_map_rData_px_x;
  reg        [8:0]    io_i_map_rData_px_y;
  reg        [29:0]   io_i_map_rData_px_p_v_0;
  reg        [33:0]   io_i_map_rData_px_p_v_1;
  reg        [23:0]   io_i_map_rData_px_p_v_2;
  reg        [31:0]   io_i_map_rData_px_p_v_3;
  reg        [31:0]   io_i_map_rData_px_p_v_4;
  reg        [66:0]   io_i_map_rData_px_attr;
  reg        [33:0]   io_i_map_rData_wu;
  reg        [5:0]    io_i_map_rData_e;
  wire                when_Stream_l477;
  wire                a0_map_valid;
  reg                 a0_map_ready;
  wire       [8:0]    a0_map_payload_px_x;
  wire       [8:0]    a0_map_payload_px_y;
  wire       [29:0]   a0_map_payload_px_p_v_0;
  wire       [33:0]   a0_map_payload_px_p_v_1;
  wire       [23:0]   a0_map_payload_px_p_v_2;
  wire       [31:0]   a0_map_payload_px_p_v_3;
  wire       [31:0]   a0_map_payload_px_p_v_4;
  wire       [66:0]   a0_map_payload_px_attr;
  wire       [5:0]    a0_map_payload_e;
  wire       [20:0]   a0_map_payload_wn;
  wire                a_valid;
  wire                a_ready;
  wire       [8:0]    a_payload_px_x;
  wire       [8:0]    a_payload_px_y;
  wire       [29:0]   a_payload_px_p_v_0;
  wire       [33:0]   a_payload_px_p_v_1;
  wire       [23:0]   a_payload_px_p_v_2;
  wire       [31:0]   a_payload_px_p_v_3;
  wire       [31:0]   a_payload_px_p_v_4;
  wire       [66:0]   a_payload_px_attr;
  wire       [5:0]    a_payload_e;
  wire       [20:0]   a_payload_wn;
  reg                 a0_map_rValid;
  reg        [8:0]    a0_map_rData_px_x;
  reg        [8:0]    a0_map_rData_px_y;
  reg        [29:0]   a0_map_rData_px_p_v_0;
  reg        [33:0]   a0_map_rData_px_p_v_1;
  reg        [23:0]   a0_map_rData_px_p_v_2;
  reg        [31:0]   a0_map_rData_px_p_v_3;
  reg        [31:0]   a0_map_rData_px_p_v_4;
  reg        [66:0]   a0_map_rData_px_attr;
  reg        [5:0]    a0_map_rData_e;
  reg        [20:0]   a0_map_rData_wn;
  wire                when_Stream_l477_1;
  wire                a_translated_valid;
  wire                a_translated_ready;
  wire       [9:0]    a_translated_payload;
  wire                b_valid;
  wire                b_ready;
  wire       [11:0]   b_payload_value;
  wire       [8:0]    b_payload_linked_px_x;
  wire       [8:0]    b_payload_linked_px_y;
  wire       [29:0]   b_payload_linked_px_p_v_0;
  wire       [33:0]   b_payload_linked_px_p_v_1;
  wire       [23:0]   b_payload_linked_px_p_v_2;
  wire       [31:0]   b_payload_linked_px_p_v_3;
  wire       [31:0]   b_payload_linked_px_p_v_4;
  wire       [66:0]   b_payload_linked_px_attr;
  wire       [5:0]    b_payload_linked_e;
  wire       [20:0]   b_payload_linked_wn;
  reg                 _zz_b_valid;
  wire                a_translated_fire;
  reg        [8:0]    a_payload_regNextWhen_px_x;
  reg        [8:0]    a_payload_regNextWhen_px_y;
  reg        [29:0]   a_payload_regNextWhen_px_p_v_0;
  reg        [33:0]   a_payload_regNextWhen_px_p_v_1;
  reg        [23:0]   a_payload_regNextWhen_px_p_v_2;
  reg        [31:0]   a_payload_regNextWhen_px_p_v_3;
  reg        [31:0]   a_payload_regNextWhen_px_p_v_4;
  reg        [66:0]   a_payload_regNextWhen_px_attr;
  reg        [5:0]    a_payload_regNextWhen_e;
  reg        [20:0]   a_payload_regNextWhen_wn;
  wire                b_isFree;
  wire                b_map_valid;
  reg                 b_map_ready;
  wire       [8:0]    b_map_payload_a_px_x;
  wire       [8:0]    b_map_payload_a_px_y;
  wire       [29:0]   b_map_payload_a_px_p_v_0;
  wire       [33:0]   b_map_payload_a_px_p_v_1;
  wire       [23:0]   b_map_payload_a_px_p_v_2;
  wire       [31:0]   b_map_payload_a_px_p_v_3;
  wire       [31:0]   b_map_payload_a_px_p_v_4;
  wire       [66:0]   b_map_payload_a_px_attr;
  wire       [5:0]    b_map_payload_a_e;
  wire       [20:0]   b_map_payload_a_wn;
  wire       [11:0]   b_map_payload_y0;
  wire       [33:0]   b_map_payload_corr;
  wire                c0_valid;
  wire                c0_ready;
  wire       [8:0]    c0_payload_a_px_x;
  wire       [8:0]    c0_payload_a_px_y;
  wire       [29:0]   c0_payload_a_px_p_v_0;
  wire       [33:0]   c0_payload_a_px_p_v_1;
  wire       [23:0]   c0_payload_a_px_p_v_2;
  wire       [31:0]   c0_payload_a_px_p_v_3;
  wire       [31:0]   c0_payload_a_px_p_v_4;
  wire       [66:0]   c0_payload_a_px_attr;
  wire       [5:0]    c0_payload_a_e;
  wire       [20:0]   c0_payload_a_wn;
  wire       [11:0]   c0_payload_y0;
  wire       [33:0]   c0_payload_corr;
  reg                 b_map_rValid;
  reg        [8:0]    b_map_rData_a_px_x;
  reg        [8:0]    b_map_rData_a_px_y;
  reg        [29:0]   b_map_rData_a_px_p_v_0;
  reg        [33:0]   b_map_rData_a_px_p_v_1;
  reg        [23:0]   b_map_rData_a_px_p_v_2;
  reg        [31:0]   b_map_rData_a_px_p_v_3;
  reg        [31:0]   b_map_rData_a_px_p_v_4;
  reg        [66:0]   b_map_rData_a_px_attr;
  reg        [5:0]    b_map_rData_a_e;
  reg        [20:0]   b_map_rData_a_wn;
  reg        [11:0]   b_map_rData_y0;
  reg        [33:0]   b_map_rData_corr;
  wire                when_Stream_l477_2;
  wire                c0_map_valid;
  reg                 c0_map_ready;
  wire       [8:0]    c0_map_payload_a_px_x;
  wire       [8:0]    c0_map_payload_a_px_y;
  wire       [29:0]   c0_map_payload_a_px_p_v_0;
  wire       [33:0]   c0_map_payload_a_px_p_v_1;
  wire       [23:0]   c0_map_payload_a_px_p_v_2;
  wire       [31:0]   c0_map_payload_a_px_p_v_3;
  wire       [31:0]   c0_map_payload_a_px_p_v_4;
  wire       [66:0]   c0_map_payload_a_px_attr;
  wire       [5:0]    c0_map_payload_a_e;
  wire       [20:0]   c0_map_payload_a_wn;
  wire       [11:0]   c0_map_payload_y0;
  wire       [33:0]   c0_map_payload_corr;
  wire                cS_valid;
  wire                cS_ready;
  wire       [8:0]    cS_payload_a_px_x;
  wire       [8:0]    cS_payload_a_px_y;
  wire       [29:0]   cS_payload_a_px_p_v_0;
  wire       [33:0]   cS_payload_a_px_p_v_1;
  wire       [23:0]   cS_payload_a_px_p_v_2;
  wire       [31:0]   cS_payload_a_px_p_v_3;
  wire       [31:0]   cS_payload_a_px_p_v_4;
  wire       [66:0]   cS_payload_a_px_attr;
  wire       [5:0]    cS_payload_a_e;
  wire       [20:0]   cS_payload_a_wn;
  wire       [11:0]   cS_payload_y0;
  wire       [33:0]   cS_payload_corr;
  reg                 c0_map_rValid;
  reg        [8:0]    c0_map_rData_a_px_x;
  reg        [8:0]    c0_map_rData_a_px_y;
  reg        [29:0]   c0_map_rData_a_px_p_v_0;
  reg        [33:0]   c0_map_rData_a_px_p_v_1;
  reg        [23:0]   c0_map_rData_a_px_p_v_2;
  reg        [31:0]   c0_map_rData_a_px_p_v_3;
  reg        [31:0]   c0_map_rData_a_px_p_v_4;
  reg        [66:0]   c0_map_rData_a_px_attr;
  reg        [5:0]    c0_map_rData_a_e;
  reg        [20:0]   c0_map_rData_a_wn;
  reg        [11:0]   c0_map_rData_y0;
  reg        [33:0]   c0_map_rData_corr;
  wire                when_Stream_l477_3;
  wire                cS_map_valid;
  reg                 cS_map_ready;
  wire       [8:0]    cS_map_payload_a_px_x;
  wire       [8:0]    cS_map_payload_a_px_y;
  wire       [29:0]   cS_map_payload_a_px_p_v_0;
  wire       [33:0]   cS_map_payload_a_px_p_v_1;
  wire       [23:0]   cS_map_payload_a_px_p_v_2;
  wire       [31:0]   cS_map_payload_a_px_p_v_3;
  wire       [31:0]   cS_map_payload_a_px_p_v_4;
  wire       [66:0]   cS_map_payload_a_px_attr;
  wire       [5:0]    cS_map_payload_a_e;
  wire       [20:0]   cS_map_payload_a_wn;
  wire       [21:0]   cS_map_payload_y1;
  wire                d_valid;
  wire                d_ready;
  wire       [8:0]    d_payload_a_px_x;
  wire       [8:0]    d_payload_a_px_y;
  wire       [29:0]   d_payload_a_px_p_v_0;
  wire       [33:0]   d_payload_a_px_p_v_1;
  wire       [23:0]   d_payload_a_px_p_v_2;
  wire       [31:0]   d_payload_a_px_p_v_3;
  wire       [31:0]   d_payload_a_px_p_v_4;
  wire       [66:0]   d_payload_a_px_attr;
  wire       [5:0]    d_payload_a_e;
  wire       [20:0]   d_payload_a_wn;
  wire       [21:0]   d_payload_y1;
  reg                 cS_map_rValid;
  reg        [8:0]    cS_map_rData_a_px_x;
  reg        [8:0]    cS_map_rData_a_px_y;
  reg        [29:0]   cS_map_rData_a_px_p_v_0;
  reg        [33:0]   cS_map_rData_a_px_p_v_1;
  reg        [23:0]   cS_map_rData_a_px_p_v_2;
  reg        [31:0]   cS_map_rData_a_px_p_v_3;
  reg        [31:0]   cS_map_rData_a_px_p_v_4;
  reg        [66:0]   cS_map_rData_a_px_attr;
  reg        [5:0]    cS_map_rData_a_e;
  reg        [20:0]   cS_map_rData_a_wn;
  reg        [21:0]   cS_map_rData_y1;
  wire                when_Stream_l477_4;
  wire                d_map_valid;
  reg                 d_map_ready;
  wire       [8:0]    d_map_payload_a_px_x;
  wire       [8:0]    d_map_payload_a_px_y;
  wire       [29:0]   d_map_payload_a_px_p_v_0;
  wire       [33:0]   d_map_payload_a_px_p_v_1;
  wire       [23:0]   d_map_payload_a_px_p_v_2;
  wire       [31:0]   d_map_payload_a_px_p_v_3;
  wire       [31:0]   d_map_payload_a_px_p_v_4;
  wire       [66:0]   d_map_payload_a_px_attr;
  wire       [5:0]    d_map_payload_a_e;
  wire       [20:0]   d_map_payload_a_wn;
  wire       [21:0]   d_map_payload_y1;
  wire                d_map_payload_sNeg;
  wire                d_map_payload_tNeg;
  wire                d_map_payload_lNeg;
  wire       [31:0]   d_map_payload_sa;
  wire       [31:0]   d_map_payload_ta;
  wire       [23:0]   d_map_payload_la;
  wire                e0_valid;
  wire                e0_ready;
  wire       [8:0]    e0_payload_a_px_x;
  wire       [8:0]    e0_payload_a_px_y;
  wire       [29:0]   e0_payload_a_px_p_v_0;
  wire       [33:0]   e0_payload_a_px_p_v_1;
  wire       [23:0]   e0_payload_a_px_p_v_2;
  wire       [31:0]   e0_payload_a_px_p_v_3;
  wire       [31:0]   e0_payload_a_px_p_v_4;
  wire       [66:0]   e0_payload_a_px_attr;
  wire       [5:0]    e0_payload_a_e;
  wire       [20:0]   e0_payload_a_wn;
  wire       [21:0]   e0_payload_y1;
  wire                e0_payload_sNeg;
  wire                e0_payload_tNeg;
  wire                e0_payload_lNeg;
  wire       [31:0]   e0_payload_sa;
  wire       [31:0]   e0_payload_ta;
  wire       [23:0]   e0_payload_la;
  reg                 d_map_rValid;
  reg        [8:0]    d_map_rData_a_px_x;
  reg        [8:0]    d_map_rData_a_px_y;
  reg        [29:0]   d_map_rData_a_px_p_v_0;
  reg        [33:0]   d_map_rData_a_px_p_v_1;
  reg        [23:0]   d_map_rData_a_px_p_v_2;
  reg        [31:0]   d_map_rData_a_px_p_v_3;
  reg        [31:0]   d_map_rData_a_px_p_v_4;
  reg        [66:0]   d_map_rData_a_px_attr;
  reg        [5:0]    d_map_rData_a_e;
  reg        [20:0]   d_map_rData_a_wn;
  reg        [21:0]   d_map_rData_y1;
  reg                 d_map_rData_sNeg;
  reg                 d_map_rData_tNeg;
  reg                 d_map_rData_lNeg;
  reg        [31:0]   d_map_rData_sa;
  reg        [31:0]   d_map_rData_ta;
  reg        [23:0]   d_map_rData_la;
  wire                when_Stream_l477_5;
  wire                e0_map_valid;
  reg                 e0_map_ready;
  wire       [8:0]    e0_map_payload_a_px_x;
  wire       [8:0]    e0_map_payload_a_px_y;
  wire       [29:0]   e0_map_payload_a_px_p_v_0;
  wire       [33:0]   e0_map_payload_a_px_p_v_1;
  wire       [23:0]   e0_map_payload_a_px_p_v_2;
  wire       [31:0]   e0_map_payload_a_px_p_v_3;
  wire       [31:0]   e0_map_payload_a_px_p_v_4;
  wire       [66:0]   e0_map_payload_a_px_attr;
  wire       [5:0]    e0_map_payload_a_e;
  wire       [20:0]   e0_map_payload_a_wn;
  wire                e0_map_payload_sNeg;
  wire                e0_map_payload_tNeg;
  wire                e0_map_payload_lNeg;
  wire       [53:0]   e0_map_payload_ps;
  wire       [53:0]   e0_map_payload_pt;
  wire       [45:0]   e0_map_payload_pl;
  wire                e_valid;
  wire                e_ready;
  wire       [8:0]    e_payload_a_px_x;
  wire       [8:0]    e_payload_a_px_y;
  wire       [29:0]   e_payload_a_px_p_v_0;
  wire       [33:0]   e_payload_a_px_p_v_1;
  wire       [23:0]   e_payload_a_px_p_v_2;
  wire       [31:0]   e_payload_a_px_p_v_3;
  wire       [31:0]   e_payload_a_px_p_v_4;
  wire       [66:0]   e_payload_a_px_attr;
  wire       [5:0]    e_payload_a_e;
  wire       [20:0]   e_payload_a_wn;
  wire                e_payload_sNeg;
  wire                e_payload_tNeg;
  wire                e_payload_lNeg;
  wire       [53:0]   e_payload_ps;
  wire       [53:0]   e_payload_pt;
  wire       [45:0]   e_payload_pl;
  reg                 e0_map_rValid;
  reg        [8:0]    e0_map_rData_a_px_x;
  reg        [8:0]    e0_map_rData_a_px_y;
  reg        [29:0]   e0_map_rData_a_px_p_v_0;
  reg        [33:0]   e0_map_rData_a_px_p_v_1;
  reg        [23:0]   e0_map_rData_a_px_p_v_2;
  reg        [31:0]   e0_map_rData_a_px_p_v_3;
  reg        [31:0]   e0_map_rData_a_px_p_v_4;
  reg        [66:0]   e0_map_rData_a_px_attr;
  reg        [5:0]    e0_map_rData_a_e;
  reg        [20:0]   e0_map_rData_a_wn;
  reg                 e0_map_rData_sNeg;
  reg                 e0_map_rData_tNeg;
  reg                 e0_map_rData_lNeg;
  reg        [53:0]   e0_map_rData_ps;
  reg        [53:0]   e0_map_rData_pt;
  reg        [45:0]   e0_map_rData_pl;
  wire                when_Stream_l477_6;
  wire       [6:0]    _zz_e_map_payload_ps;
  wire       [6:0]    _zz_e_map_payload_pl;
  wire                e_map_valid;
  reg                 e_map_ready;
  wire       [8:0]    e_map_payload_a_px_x;
  wire       [8:0]    e_map_payload_a_px_y;
  wire       [29:0]   e_map_payload_a_px_p_v_0;
  wire       [33:0]   e_map_payload_a_px_p_v_1;
  wire       [23:0]   e_map_payload_a_px_p_v_2;
  wire       [31:0]   e_map_payload_a_px_p_v_3;
  wire       [31:0]   e_map_payload_a_px_p_v_4;
  wire       [66:0]   e_map_payload_a_px_attr;
  wire       [5:0]    e_map_payload_a_e;
  wire       [20:0]   e_map_payload_a_wn;
  wire                e_map_payload_sNeg;
  wire                e_map_payload_tNeg;
  wire                e_map_payload_lNeg;
  wire       [53:0]   e_map_payload_ps;
  wire       [53:0]   e_map_payload_pt;
  wire       [45:0]   e_map_payload_pl;
  wire       [2:0]    e_map_payload_fineT;
  wire       [2:0]    e_map_payload_fineL;
  wire                fc_valid;
  wire                fc_ready;
  wire       [8:0]    fc_payload_a_px_x;
  wire       [8:0]    fc_payload_a_px_y;
  wire       [29:0]   fc_payload_a_px_p_v_0;
  wire       [33:0]   fc_payload_a_px_p_v_1;
  wire       [23:0]   fc_payload_a_px_p_v_2;
  wire       [31:0]   fc_payload_a_px_p_v_3;
  wire       [31:0]   fc_payload_a_px_p_v_4;
  wire       [66:0]   fc_payload_a_px_attr;
  wire       [5:0]    fc_payload_a_e;
  wire       [20:0]   fc_payload_a_wn;
  wire                fc_payload_sNeg;
  wire                fc_payload_tNeg;
  wire                fc_payload_lNeg;
  wire       [53:0]   fc_payload_ps;
  wire       [53:0]   fc_payload_pt;
  wire       [45:0]   fc_payload_pl;
  wire       [2:0]    fc_payload_fineT;
  wire       [2:0]    fc_payload_fineL;
  reg                 e_map_rValid;
  reg        [8:0]    e_map_rData_a_px_x;
  reg        [8:0]    e_map_rData_a_px_y;
  reg        [29:0]   e_map_rData_a_px_p_v_0;
  reg        [33:0]   e_map_rData_a_px_p_v_1;
  reg        [23:0]   e_map_rData_a_px_p_v_2;
  reg        [31:0]   e_map_rData_a_px_p_v_3;
  reg        [31:0]   e_map_rData_a_px_p_v_4;
  reg        [66:0]   e_map_rData_a_px_attr;
  reg        [5:0]    e_map_rData_a_e;
  reg        [20:0]   e_map_rData_a_wn;
  reg                 e_map_rData_sNeg;
  reg                 e_map_rData_tNeg;
  reg                 e_map_rData_lNeg;
  reg        [53:0]   e_map_rData_ps;
  reg        [53:0]   e_map_rData_pt;
  reg        [45:0]   e_map_rData_pl;
  reg        [2:0]    e_map_rData_fineT;
  reg        [2:0]    e_map_rData_fineL;
  wire                when_Stream_l477_7;
  wire                fc_map_valid;
  reg                 fc_map_ready;
  wire       [8:0]    fc_map_payload_a_px_x;
  wire       [8:0]    fc_map_payload_a_px_y;
  wire       [29:0]   fc_map_payload_a_px_p_v_0;
  wire       [33:0]   fc_map_payload_a_px_p_v_1;
  wire       [23:0]   fc_map_payload_a_px_p_v_2;
  wire       [31:0]   fc_map_payload_a_px_p_v_3;
  wire       [31:0]   fc_map_payload_a_px_p_v_4;
  wire       [66:0]   fc_map_payload_a_px_attr;
  wire       [5:0]    fc_map_payload_a_e;
  wire       [20:0]   fc_map_payload_a_wn;
  wire                fc_map_payload_sNeg;
  wire                fc_map_payload_tNeg;
  wire                fc_map_payload_lNeg;
  wire       [53:0]   fc_map_payload_ms;
  wire       [53:0]   fc_map_payload_mt;
  wire       [7:0]    fc_map_payload_ml;
  wire                f0_valid;
  wire                f0_ready;
  wire       [8:0]    f0_payload_a_px_x;
  wire       [8:0]    f0_payload_a_px_y;
  wire       [29:0]   f0_payload_a_px_p_v_0;
  wire       [33:0]   f0_payload_a_px_p_v_1;
  wire       [23:0]   f0_payload_a_px_p_v_2;
  wire       [31:0]   f0_payload_a_px_p_v_3;
  wire       [31:0]   f0_payload_a_px_p_v_4;
  wire       [66:0]   f0_payload_a_px_attr;
  wire       [5:0]    f0_payload_a_e;
  wire       [20:0]   f0_payload_a_wn;
  wire                f0_payload_sNeg;
  wire                f0_payload_tNeg;
  wire                f0_payload_lNeg;
  wire       [53:0]   f0_payload_ms;
  wire       [53:0]   f0_payload_mt;
  wire       [7:0]    f0_payload_ml;
  reg                 fc_map_rValid;
  reg        [8:0]    fc_map_rData_a_px_x;
  reg        [8:0]    fc_map_rData_a_px_y;
  reg        [29:0]   fc_map_rData_a_px_p_v_0;
  reg        [33:0]   fc_map_rData_a_px_p_v_1;
  reg        [23:0]   fc_map_rData_a_px_p_v_2;
  reg        [31:0]   fc_map_rData_a_px_p_v_3;
  reg        [31:0]   fc_map_rData_a_px_p_v_4;
  reg        [66:0]   fc_map_rData_a_px_attr;
  reg        [5:0]    fc_map_rData_a_e;
  reg        [20:0]   fc_map_rData_a_wn;
  reg                 fc_map_rData_sNeg;
  reg                 fc_map_rData_tNeg;
  reg                 fc_map_rData_lNeg;
  reg        [53:0]   fc_map_rData_ms;
  reg        [53:0]   fc_map_rData_mt;
  reg        [7:0]    fc_map_rData_ml;
  wire                when_Stream_l477_8;
  wire                _zz_f0_map_payload_addr;
  wire       [4:0]    _zz_f0_map_payload_addr_1;
  wire       [4:0]    _zz_f0_map_payload_addr_2;
  wire                _zz_f0_map_payload_addr_3;
  wire       [54:0]   _zz_f0_map_payload_addr_4;
  wire       [9:0]    _zz_f0_map_payload_addr_5;
  wire       [9:0]    _zz_f0_map_payload_addr_6;
  wire       [54:0]   _zz_f0_map_payload_addr_7;
  wire       [9:0]    _zz_f0_map_payload_addr_8;
  wire       [9:0]    _zz_f0_map_payload_addr_9;
  wire                f0_map_valid;
  reg                 f0_map_ready;
  wire       [8:0]    f0_map_payload_x;
  wire       [8:0]    f0_map_payload_y;
  wire       [29:0]   f0_map_payload_z;
  wire       [23:0]   f0_map_payload_addr;
  wire                f0_map_payload_nib;
  wire       [7:0]    f0_map_payload_light;
  wire                f0_map_payload_flat;
  wire                f0_map_payload_blend;
  wire                f0_map_payload_tex4bpp;
  wire       [15:0]   f0_map_payload_pal;
  wire                f_valid;
  wire                f_ready;
  wire       [8:0]    f_payload_x;
  wire       [8:0]    f_payload_y;
  wire       [29:0]   f_payload_z;
  wire       [23:0]   f_payload_addr;
  wire                f_payload_nib;
  wire       [7:0]    f_payload_light;
  wire                f_payload_flat;
  wire                f_payload_blend;
  wire                f_payload_tex4bpp;
  wire       [15:0]   f_payload_pal;
  reg                 f0_map_rValid;
  reg        [8:0]    f0_map_rData_x;
  reg        [8:0]    f0_map_rData_y;
  reg        [29:0]   f0_map_rData_z;
  reg        [23:0]   f0_map_rData_addr;
  reg                 f0_map_rData_nib;
  reg        [7:0]    f0_map_rData_light;
  reg                 f0_map_rData_flat;
  reg                 f0_map_rData_blend;
  reg                 f0_map_rData_tex4bpp;
  reg        [15:0]   f0_map_rData_pal;
  wire                when_Stream_l477_9;
  reg [11:0] rom [0:1023];

  assign _zz__zz_io_i_map_payload_e_3 = (_zz_io_i_map_payload_e_1 - 34'h000000001);
  assign _zz_a0_map_payload_wn = (a0_payload_wu <<< _zz_a0_map_payload_wn_1);
  assign _zz_a0_map_payload_wn_1 = (6'h21 - a0_payload_e);
  assign _zz_b_map_payload_corr = (b_payload_linked_wn * b_payload_value);
  assign _zz_cS_map_payload_y1 = (_zz_cS_map_payload_y1_1 >>> 5'd23);
  assign _zz_cS_map_payload_y1_1 = (cS_payload_y0 * cS_payload_corr);
  assign _zz_d_map_payload_sa = (d_payload_a_px_p_v_3[31] ? _zz_d_map_payload_sa_1 : d_payload_a_px_p_v_3);
  assign _zz_d_map_payload_sa_1 = (~ d_payload_a_px_p_v_3);
  assign _zz_d_map_payload_sa_3 = d_payload_a_px_p_v_3[31];
  assign _zz_d_map_payload_sa_2 = {31'd0, _zz_d_map_payload_sa_3};
  assign _zz_d_map_payload_ta = (d_payload_a_px_p_v_4[31] ? _zz_d_map_payload_ta_1 : d_payload_a_px_p_v_4);
  assign _zz_d_map_payload_ta_1 = (~ d_payload_a_px_p_v_4);
  assign _zz_d_map_payload_ta_3 = d_payload_a_px_p_v_4[31];
  assign _zz_d_map_payload_ta_2 = {31'd0, _zz_d_map_payload_ta_3};
  assign _zz_d_map_payload_la = (d_payload_a_px_p_v_2[23] ? _zz_d_map_payload_la_1 : d_payload_a_px_p_v_2);
  assign _zz_d_map_payload_la_1 = (~ d_payload_a_px_p_v_2);
  assign _zz_d_map_payload_la_3 = d_payload_a_px_p_v_2[23];
  assign _zz_d_map_payload_la_2 = {23'd0, _zz_d_map_payload_la_3};
  assign _zz__zz_e_map_payload_ps = {1'd0, e_payload_a_e};
  assign _zz__zz_e_map_payload_pl = {1'd0, e_payload_a_e};
  assign _zz_fc_map_payload_ml = (fc_payload_pl >>> fc_payload_fineL);
  assign _zz__zz_f0_map_payload_addr_4 = (f0_payload_sNeg ? _zz__zz_f0_map_payload_addr_4_1 : _zz__zz_f0_map_payload_addr_4_4);
  assign _zz__zz_f0_map_payload_addr_4_1 = (- _zz__zz_f0_map_payload_addr_4_2);
  assign _zz__zz_f0_map_payload_addr_4_3 = f0_payload_ms;
  assign _zz__zz_f0_map_payload_addr_4_2 = {{1{_zz__zz_f0_map_payload_addr_4_3[53]}}, _zz__zz_f0_map_payload_addr_4_3};
  assign _zz__zz_f0_map_payload_addr_4_5 = f0_payload_ms;
  assign _zz__zz_f0_map_payload_addr_4_4 = {{1{_zz__zz_f0_map_payload_addr_4_5[53]}}, _zz__zz_f0_map_payload_addr_4_5};
  assign _zz__zz_f0_map_payload_addr_4_7 = _zz__zz_f0_map_payload_addr_4_8;
  assign _zz__zz_f0_map_payload_addr_4_6 = {{1{_zz__zz_f0_map_payload_addr_4_7[53]}}, _zz__zz_f0_map_payload_addr_4_7};
  assign _zz__zz_f0_map_payload_addr_4_9 = f0_payload_a_px_attr[56 : 48];
  assign _zz__zz_f0_map_payload_addr_4_8 = {45'd0, _zz__zz_f0_map_payload_addr_4_9};
  assign _zz__zz_f0_map_payload_addr_5 = (_zz__zz_f0_map_payload_addr_5_1 + _zz__zz_f0_map_payload_addr_5_3);
  assign _zz__zz_f0_map_payload_addr_5_1 = (_zz_f0_map_payload_addr_4[54] ? _zz__zz_f0_map_payload_addr_5_2 : _zz_f0_map_payload_addr_4);
  assign _zz__zz_f0_map_payload_addr_5_2 = (~ _zz_f0_map_payload_addr_4);
  assign _zz__zz_f0_map_payload_addr_5_4 = _zz_f0_map_payload_addr_4[54];
  assign _zz__zz_f0_map_payload_addr_5_3 = {54'd0, _zz__zz_f0_map_payload_addr_5_4};
  assign _zz__zz_f0_map_payload_addr_5_5 = (10'h3ff >>> _zz__zz_f0_map_payload_addr_5_6);
  assign _zz__zz_f0_map_payload_addr_5_6 = (4'b1010 - _zz__zz_f0_map_payload_addr_5_7);
  assign _zz__zz_f0_map_payload_addr_5_7 = _zz_f0_map_payload_addr_2[3:0];
  assign _zz__zz_f0_map_payload_addr_6 = ((_zz_f0_map_payload_addr_4[54] ? _zz__zz_f0_map_payload_addr_6_1 : _zz_f0_map_payload_addr_5) + _zz__zz_f0_map_payload_addr_6_2);
  assign _zz__zz_f0_map_payload_addr_6_1 = (10'h0 - _zz_f0_map_payload_addr_5);
  assign _zz__zz_f0_map_payload_addr_6_2 = (_zz__zz_f0_map_payload_addr_6_3 <<< 3);
  assign _zz__zz_f0_map_payload_addr_6_4 = f0_payload_a_px_attr[22 : 16];
  assign _zz__zz_f0_map_payload_addr_6_3 = {3'd0, _zz__zz_f0_map_payload_addr_6_4};
  assign _zz__zz_f0_map_payload_addr_6_5 = _zz_f0_map_payload_addr_4;
  assign _zz__zz_f0_map_payload_addr_7 = (f0_payload_tNeg ? _zz__zz_f0_map_payload_addr_7_1 : _zz__zz_f0_map_payload_addr_7_4);
  assign _zz__zz_f0_map_payload_addr_7_1 = (- _zz__zz_f0_map_payload_addr_7_2);
  assign _zz__zz_f0_map_payload_addr_7_3 = f0_payload_mt;
  assign _zz__zz_f0_map_payload_addr_7_2 = {{1{_zz__zz_f0_map_payload_addr_7_3[53]}}, _zz__zz_f0_map_payload_addr_7_3};
  assign _zz__zz_f0_map_payload_addr_7_5 = f0_payload_mt;
  assign _zz__zz_f0_map_payload_addr_7_4 = {{1{_zz__zz_f0_map_payload_addr_7_5[53]}}, _zz__zz_f0_map_payload_addr_7_5};
  assign _zz__zz_f0_map_payload_addr_7_7 = _zz__zz_f0_map_payload_addr_7_8;
  assign _zz__zz_f0_map_payload_addr_7_6 = {{1{_zz__zz_f0_map_payload_addr_7_7[53]}}, _zz__zz_f0_map_payload_addr_7_7};
  assign _zz__zz_f0_map_payload_addr_7_9 = f0_payload_a_px_attr[47 : 39];
  assign _zz__zz_f0_map_payload_addr_7_8 = {45'd0, _zz__zz_f0_map_payload_addr_7_9};
  assign _zz__zz_f0_map_payload_addr_8 = (_zz__zz_f0_map_payload_addr_8_1 + _zz__zz_f0_map_payload_addr_8_3);
  assign _zz__zz_f0_map_payload_addr_8_1 = (_zz_f0_map_payload_addr_7[54] ? _zz__zz_f0_map_payload_addr_8_2 : _zz_f0_map_payload_addr_7);
  assign _zz__zz_f0_map_payload_addr_8_2 = (~ _zz_f0_map_payload_addr_7);
  assign _zz__zz_f0_map_payload_addr_8_4 = _zz_f0_map_payload_addr_7[54];
  assign _zz__zz_f0_map_payload_addr_8_3 = {54'd0, _zz__zz_f0_map_payload_addr_8_4};
  assign _zz__zz_f0_map_payload_addr_8_5 = (10'h3ff >>> _zz__zz_f0_map_payload_addr_8_6);
  assign _zz__zz_f0_map_payload_addr_8_6 = (4'b1010 - _zz__zz_f0_map_payload_addr_8_7);
  assign _zz__zz_f0_map_payload_addr_8_7 = _zz_f0_map_payload_addr_1[3:0];
  assign _zz__zz_f0_map_payload_addr_9 = ((_zz_f0_map_payload_addr_7[54] ? _zz__zz_f0_map_payload_addr_9_1 : _zz_f0_map_payload_addr_8) + _zz__zz_f0_map_payload_addr_9_2);
  assign _zz__zz_f0_map_payload_addr_9_1 = (10'h0 - _zz_f0_map_payload_addr_8);
  assign _zz__zz_f0_map_payload_addr_9_2 = (_zz__zz_f0_map_payload_addr_9_3 <<< 3);
  assign _zz__zz_f0_map_payload_addr_9_4 = f0_payload_a_px_attr[15 : 9];
  assign _zz__zz_f0_map_payload_addr_9_3 = {3'd0, _zz__zz_f0_map_payload_addr_9_4};
  assign _zz__zz_f0_map_payload_addr_9_5 = _zz_f0_map_payload_addr_7;
  assign _zz_f0_map_payload_light = (8'h0 - f0_payload_ml);
  assign _zz__zz_io_i_map_payload_e_32 = _zz_io_i_map_payload_e_2[1];
  initial begin
    rom[0] = 12'b111111111110;
    rom[1] = 12'b111111111010;
    rom[2] = 12'b111111110110;
    rom[3] = 12'b111111110010;
    rom[4] = 12'b111111101110;
    rom[5] = 12'b111111101010;
    rom[6] = 12'b111111100110;
    rom[7] = 12'b111111100010;
    rom[8] = 12'b111111011110;
    rom[9] = 12'b111111011010;
    rom[10] = 12'b111111010110;
    rom[11] = 12'b111111010011;
    rom[12] = 12'b111111001111;
    rom[13] = 12'b111111001011;
    rom[14] = 12'b111111000111;
    rom[15] = 12'b111111000011;
    rom[16] = 12'b111110111111;
    rom[17] = 12'b111110111011;
    rom[18] = 12'b111110110111;
    rom[19] = 12'b111110110011;
    rom[20] = 12'b111110110000;
    rom[21] = 12'b111110101100;
    rom[22] = 12'b111110101000;
    rom[23] = 12'b111110100100;
    rom[24] = 12'b111110100000;
    rom[25] = 12'b111110011100;
    rom[26] = 12'b111110011001;
    rom[27] = 12'b111110010101;
    rom[28] = 12'b111110010001;
    rom[29] = 12'b111110001101;
    rom[30] = 12'b111110001010;
    rom[31] = 12'b111110000110;
    rom[32] = 12'b111110000010;
    rom[33] = 12'b111101111110;
    rom[34] = 12'b111101111010;
    rom[35] = 12'b111101110111;
    rom[36] = 12'b111101110011;
    rom[37] = 12'b111101101111;
    rom[38] = 12'b111101101100;
    rom[39] = 12'b111101101000;
    rom[40] = 12'b111101100100;
    rom[41] = 12'b111101100000;
    rom[42] = 12'b111101011101;
    rom[43] = 12'b111101011001;
    rom[44] = 12'b111101010101;
    rom[45] = 12'b111101010010;
    rom[46] = 12'b111101001110;
    rom[47] = 12'b111101001010;
    rom[48] = 12'b111101000111;
    rom[49] = 12'b111101000011;
    rom[50] = 12'b111100111111;
    rom[51] = 12'b111100111100;
    rom[52] = 12'b111100111000;
    rom[53] = 12'b111100110101;
    rom[54] = 12'b111100110001;
    rom[55] = 12'b111100101101;
    rom[56] = 12'b111100101010;
    rom[57] = 12'b111100100110;
    rom[58] = 12'b111100100011;
    rom[59] = 12'b111100011111;
    rom[60] = 12'b111100011100;
    rom[61] = 12'b111100011000;
    rom[62] = 12'b111100010100;
    rom[63] = 12'b111100010001;
    rom[64] = 12'b111100001101;
    rom[65] = 12'b111100001010;
    rom[66] = 12'b111100000110;
    rom[67] = 12'b111100000011;
    rom[68] = 12'b111011111111;
    rom[69] = 12'b111011111100;
    rom[70] = 12'b111011111000;
    rom[71] = 12'b111011110101;
    rom[72] = 12'b111011110001;
    rom[73] = 12'b111011101110;
    rom[74] = 12'b111011101010;
    rom[75] = 12'b111011100111;
    rom[76] = 12'b111011100011;
    rom[77] = 12'b111011100000;
    rom[78] = 12'b111011011100;
    rom[79] = 12'b111011011001;
    rom[80] = 12'b111011010101;
    rom[81] = 12'b111011010010;
    rom[82] = 12'b111011001111;
    rom[83] = 12'b111011001011;
    rom[84] = 12'b111011001000;
    rom[85] = 12'b111011000100;
    rom[86] = 12'b111011000001;
    rom[87] = 12'b111010111110;
    rom[88] = 12'b111010111010;
    rom[89] = 12'b111010110111;
    rom[90] = 12'b111010110011;
    rom[91] = 12'b111010110000;
    rom[92] = 12'b111010101101;
    rom[93] = 12'b111010101001;
    rom[94] = 12'b111010100110;
    rom[95] = 12'b111010100011;
    rom[96] = 12'b111010011111;
    rom[97] = 12'b111010011100;
    rom[98] = 12'b111010011001;
    rom[99] = 12'b111010010101;
    rom[100] = 12'b111010010010;
    rom[101] = 12'b111010001111;
    rom[102] = 12'b111010001011;
    rom[103] = 12'b111010001000;
    rom[104] = 12'b111010000101;
    rom[105] = 12'b111010000001;
    rom[106] = 12'b111001111110;
    rom[107] = 12'b111001111011;
    rom[108] = 12'b111001111000;
    rom[109] = 12'b111001110100;
    rom[110] = 12'b111001110001;
    rom[111] = 12'b111001101110;
    rom[112] = 12'b111001101011;
    rom[113] = 12'b111001100111;
    rom[114] = 12'b111001100100;
    rom[115] = 12'b111001100001;
    rom[116] = 12'b111001011110;
    rom[117] = 12'b111001011010;
    rom[118] = 12'b111001010111;
    rom[119] = 12'b111001010100;
    rom[120] = 12'b111001010001;
    rom[121] = 12'b111001001110;
    rom[122] = 12'b111001001010;
    rom[123] = 12'b111001000111;
    rom[124] = 12'b111001000100;
    rom[125] = 12'b111001000001;
    rom[126] = 12'b111000111110;
    rom[127] = 12'b111000111010;
    rom[128] = 12'b111000110111;
    rom[129] = 12'b111000110100;
    rom[130] = 12'b111000110001;
    rom[131] = 12'b111000101110;
    rom[132] = 12'b111000101011;
    rom[133] = 12'b111000101000;
    rom[134] = 12'b111000100100;
    rom[135] = 12'b111000100001;
    rom[136] = 12'b111000011110;
    rom[137] = 12'b111000011011;
    rom[138] = 12'b111000011000;
    rom[139] = 12'b111000010101;
    rom[140] = 12'b111000010010;
    rom[141] = 12'b111000001111;
    rom[142] = 12'b111000001100;
    rom[143] = 12'b111000001001;
    rom[144] = 12'b111000000101;
    rom[145] = 12'b111000000010;
    rom[146] = 12'b110111111111;
    rom[147] = 12'b110111111100;
    rom[148] = 12'b110111111001;
    rom[149] = 12'b110111110110;
    rom[150] = 12'b110111110011;
    rom[151] = 12'b110111110000;
    rom[152] = 12'b110111101101;
    rom[153] = 12'b110111101010;
    rom[154] = 12'b110111100111;
    rom[155] = 12'b110111100100;
    rom[156] = 12'b110111100001;
    rom[157] = 12'b110111011110;
    rom[158] = 12'b110111011011;
    rom[159] = 12'b110111011000;
    rom[160] = 12'b110111010101;
    rom[161] = 12'b110111010010;
    rom[162] = 12'b110111001111;
    rom[163] = 12'b110111001100;
    rom[164] = 12'b110111001001;
    rom[165] = 12'b110111000110;
    rom[166] = 12'b110111000011;
    rom[167] = 12'b110111000000;
    rom[168] = 12'b110110111101;
    rom[169] = 12'b110110111010;
    rom[170] = 12'b110110110111;
    rom[171] = 12'b110110110100;
    rom[172] = 12'b110110110001;
    rom[173] = 12'b110110101111;
    rom[174] = 12'b110110101100;
    rom[175] = 12'b110110101001;
    rom[176] = 12'b110110100110;
    rom[177] = 12'b110110100011;
    rom[178] = 12'b110110100000;
    rom[179] = 12'b110110011101;
    rom[180] = 12'b110110011010;
    rom[181] = 12'b110110010111;
    rom[182] = 12'b110110010100;
    rom[183] = 12'b110110010010;
    rom[184] = 12'b110110001111;
    rom[185] = 12'b110110001100;
    rom[186] = 12'b110110001001;
    rom[187] = 12'b110110000110;
    rom[188] = 12'b110110000011;
    rom[189] = 12'b110110000000;
    rom[190] = 12'b110101111110;
    rom[191] = 12'b110101111011;
    rom[192] = 12'b110101111000;
    rom[193] = 12'b110101110101;
    rom[194] = 12'b110101110010;
    rom[195] = 12'b110101101111;
    rom[196] = 12'b110101101101;
    rom[197] = 12'b110101101010;
    rom[198] = 12'b110101100111;
    rom[199] = 12'b110101100100;
    rom[200] = 12'b110101100001;
    rom[201] = 12'b110101011111;
    rom[202] = 12'b110101011100;
    rom[203] = 12'b110101011001;
    rom[204] = 12'b110101010110;
    rom[205] = 12'b110101010011;
    rom[206] = 12'b110101010001;
    rom[207] = 12'b110101001110;
    rom[208] = 12'b110101001011;
    rom[209] = 12'b110101001000;
    rom[210] = 12'b110101000110;
    rom[211] = 12'b110101000011;
    rom[212] = 12'b110101000000;
    rom[213] = 12'b110100111101;
    rom[214] = 12'b110100111011;
    rom[215] = 12'b110100111000;
    rom[216] = 12'b110100110101;
    rom[217] = 12'b110100110010;
    rom[218] = 12'b110100110000;
    rom[219] = 12'b110100101101;
    rom[220] = 12'b110100101010;
    rom[221] = 12'b110100101000;
    rom[222] = 12'b110100100101;
    rom[223] = 12'b110100100010;
    rom[224] = 12'b110100011111;
    rom[225] = 12'b110100011101;
    rom[226] = 12'b110100011010;
    rom[227] = 12'b110100010111;
    rom[228] = 12'b110100010101;
    rom[229] = 12'b110100010010;
    rom[230] = 12'b110100001111;
    rom[231] = 12'b110100001101;
    rom[232] = 12'b110100001010;
    rom[233] = 12'b110100000111;
    rom[234] = 12'b110100000101;
    rom[235] = 12'b110100000010;
    rom[236] = 12'b110011111111;
    rom[237] = 12'b110011111101;
    rom[238] = 12'b110011111010;
    rom[239] = 12'b110011111000;
    rom[240] = 12'b110011110101;
    rom[241] = 12'b110011110010;
    rom[242] = 12'b110011110000;
    rom[243] = 12'b110011101101;
    rom[244] = 12'b110011101011;
    rom[245] = 12'b110011101000;
    rom[246] = 12'b110011100101;
    rom[247] = 12'b110011100011;
    rom[248] = 12'b110011100000;
    rom[249] = 12'b110011011110;
    rom[250] = 12'b110011011011;
    rom[251] = 12'b110011011000;
    rom[252] = 12'b110011010110;
    rom[253] = 12'b110011010011;
    rom[254] = 12'b110011010001;
    rom[255] = 12'b110011001110;
    rom[256] = 12'b110011001100;
    rom[257] = 12'b110011001001;
    rom[258] = 12'b110011000110;
    rom[259] = 12'b110011000100;
    rom[260] = 12'b110011000001;
    rom[261] = 12'b110010111111;
    rom[262] = 12'b110010111100;
    rom[263] = 12'b110010111010;
    rom[264] = 12'b110010110111;
    rom[265] = 12'b110010110101;
    rom[266] = 12'b110010110010;
    rom[267] = 12'b110010110000;
    rom[268] = 12'b110010101101;
    rom[269] = 12'b110010101011;
    rom[270] = 12'b110010101000;
    rom[271] = 12'b110010100110;
    rom[272] = 12'b110010100011;
    rom[273] = 12'b110010100001;
    rom[274] = 12'b110010011110;
    rom[275] = 12'b110010011100;
    rom[276] = 12'b110010011001;
    rom[277] = 12'b110010010111;
    rom[278] = 12'b110010010100;
    rom[279] = 12'b110010010010;
    rom[280] = 12'b110010001111;
    rom[281] = 12'b110010001101;
    rom[282] = 12'b110010001010;
    rom[283] = 12'b110010001000;
    rom[284] = 12'b110010000101;
    rom[285] = 12'b110010000011;
    rom[286] = 12'b110010000001;
    rom[287] = 12'b110001111110;
    rom[288] = 12'b110001111100;
    rom[289] = 12'b110001111001;
    rom[290] = 12'b110001110111;
    rom[291] = 12'b110001110100;
    rom[292] = 12'b110001110010;
    rom[293] = 12'b110001110000;
    rom[294] = 12'b110001101101;
    rom[295] = 12'b110001101011;
    rom[296] = 12'b110001101000;
    rom[297] = 12'b110001100110;
    rom[298] = 12'b110001100011;
    rom[299] = 12'b110001100001;
    rom[300] = 12'b110001011111;
    rom[301] = 12'b110001011100;
    rom[302] = 12'b110001011010;
    rom[303] = 12'b110001011000;
    rom[304] = 12'b110001010101;
    rom[305] = 12'b110001010011;
    rom[306] = 12'b110001010000;
    rom[307] = 12'b110001001110;
    rom[308] = 12'b110001001100;
    rom[309] = 12'b110001001001;
    rom[310] = 12'b110001000111;
    rom[311] = 12'b110001000101;
    rom[312] = 12'b110001000010;
    rom[313] = 12'b110001000000;
    rom[314] = 12'b110000111110;
    rom[315] = 12'b110000111011;
    rom[316] = 12'b110000111001;
    rom[317] = 12'b110000110111;
    rom[318] = 12'b110000110100;
    rom[319] = 12'b110000110010;
    rom[320] = 12'b110000110000;
    rom[321] = 12'b110000101101;
    rom[322] = 12'b110000101011;
    rom[323] = 12'b110000101001;
    rom[324] = 12'b110000100110;
    rom[325] = 12'b110000100100;
    rom[326] = 12'b110000100010;
    rom[327] = 12'b110000011111;
    rom[328] = 12'b110000011101;
    rom[329] = 12'b110000011011;
    rom[330] = 12'b110000011001;
    rom[331] = 12'b110000010110;
    rom[332] = 12'b110000010100;
    rom[333] = 12'b110000010010;
    rom[334] = 12'b110000001111;
    rom[335] = 12'b110000001101;
    rom[336] = 12'b110000001011;
    rom[337] = 12'b110000001001;
    rom[338] = 12'b110000000110;
    rom[339] = 12'b110000000100;
    rom[340] = 12'b110000000010;
    rom[341] = 12'b110000000000;
    rom[342] = 12'b101111111101;
    rom[343] = 12'b101111111011;
    rom[344] = 12'b101111111001;
    rom[345] = 12'b101111110111;
    rom[346] = 12'b101111110100;
    rom[347] = 12'b101111110010;
    rom[348] = 12'b101111110000;
    rom[349] = 12'b101111101110;
    rom[350] = 12'b101111101100;
    rom[351] = 12'b101111101001;
    rom[352] = 12'b101111100111;
    rom[353] = 12'b101111100101;
    rom[354] = 12'b101111100011;
    rom[355] = 12'b101111100000;
    rom[356] = 12'b101111011110;
    rom[357] = 12'b101111011100;
    rom[358] = 12'b101111011010;
    rom[359] = 12'b101111011000;
    rom[360] = 12'b101111010101;
    rom[361] = 12'b101111010011;
    rom[362] = 12'b101111010001;
    rom[363] = 12'b101111001111;
    rom[364] = 12'b101111001101;
    rom[365] = 12'b101111001011;
    rom[366] = 12'b101111001000;
    rom[367] = 12'b101111000110;
    rom[368] = 12'b101111000100;
    rom[369] = 12'b101111000010;
    rom[370] = 12'b101111000000;
    rom[371] = 12'b101110111110;
    rom[372] = 12'b101110111011;
    rom[373] = 12'b101110111001;
    rom[374] = 12'b101110110111;
    rom[375] = 12'b101110110101;
    rom[376] = 12'b101110110011;
    rom[377] = 12'b101110110001;
    rom[378] = 12'b101110101111;
    rom[379] = 12'b101110101100;
    rom[380] = 12'b101110101010;
    rom[381] = 12'b101110101000;
    rom[382] = 12'b101110100110;
    rom[383] = 12'b101110100100;
    rom[384] = 12'b101110100010;
    rom[385] = 12'b101110100000;
    rom[386] = 12'b101110011110;
    rom[387] = 12'b101110011100;
    rom[388] = 12'b101110011001;
    rom[389] = 12'b101110010111;
    rom[390] = 12'b101110010101;
    rom[391] = 12'b101110010011;
    rom[392] = 12'b101110010001;
    rom[393] = 12'b101110001111;
    rom[394] = 12'b101110001101;
    rom[395] = 12'b101110001011;
    rom[396] = 12'b101110001001;
    rom[397] = 12'b101110000111;
    rom[398] = 12'b101110000101;
    rom[399] = 12'b101110000010;
    rom[400] = 12'b101110000000;
    rom[401] = 12'b101101111110;
    rom[402] = 12'b101101111100;
    rom[403] = 12'b101101111010;
    rom[404] = 12'b101101111000;
    rom[405] = 12'b101101110110;
    rom[406] = 12'b101101110100;
    rom[407] = 12'b101101110010;
    rom[408] = 12'b101101110000;
    rom[409] = 12'b101101101110;
    rom[410] = 12'b101101101100;
    rom[411] = 12'b101101101010;
    rom[412] = 12'b101101101000;
    rom[413] = 12'b101101100110;
    rom[414] = 12'b101101100100;
    rom[415] = 12'b101101100010;
    rom[416] = 12'b101101100000;
    rom[417] = 12'b101101011110;
    rom[418] = 12'b101101011100;
    rom[419] = 12'b101101011010;
    rom[420] = 12'b101101011000;
    rom[421] = 12'b101101010110;
    rom[422] = 12'b101101010100;
    rom[423] = 12'b101101010010;
    rom[424] = 12'b101101010000;
    rom[425] = 12'b101101001110;
    rom[426] = 12'b101101001100;
    rom[427] = 12'b101101001010;
    rom[428] = 12'b101101001000;
    rom[429] = 12'b101101000110;
    rom[430] = 12'b101101000100;
    rom[431] = 12'b101101000010;
    rom[432] = 12'b101101000000;
    rom[433] = 12'b101100111110;
    rom[434] = 12'b101100111100;
    rom[435] = 12'b101100111010;
    rom[436] = 12'b101100111000;
    rom[437] = 12'b101100110110;
    rom[438] = 12'b101100110100;
    rom[439] = 12'b101100110010;
    rom[440] = 12'b101100110000;
    rom[441] = 12'b101100101110;
    rom[442] = 12'b101100101100;
    rom[443] = 12'b101100101010;
    rom[444] = 12'b101100101000;
    rom[445] = 12'b101100100110;
    rom[446] = 12'b101100100100;
    rom[447] = 12'b101100100010;
    rom[448] = 12'b101100100000;
    rom[449] = 12'b101100011110;
    rom[450] = 12'b101100011101;
    rom[451] = 12'b101100011011;
    rom[452] = 12'b101100011001;
    rom[453] = 12'b101100010111;
    rom[454] = 12'b101100010101;
    rom[455] = 12'b101100010011;
    rom[456] = 12'b101100010001;
    rom[457] = 12'b101100001111;
    rom[458] = 12'b101100001101;
    rom[459] = 12'b101100001011;
    rom[460] = 12'b101100001001;
    rom[461] = 12'b101100000111;
    rom[462] = 12'b101100000110;
    rom[463] = 12'b101100000100;
    rom[464] = 12'b101100000010;
    rom[465] = 12'b101100000000;
    rom[466] = 12'b101011111110;
    rom[467] = 12'b101011111100;
    rom[468] = 12'b101011111010;
    rom[469] = 12'b101011111000;
    rom[470] = 12'b101011110110;
    rom[471] = 12'b101011110101;
    rom[472] = 12'b101011110011;
    rom[473] = 12'b101011110001;
    rom[474] = 12'b101011101111;
    rom[475] = 12'b101011101101;
    rom[476] = 12'b101011101011;
    rom[477] = 12'b101011101001;
    rom[478] = 12'b101011101000;
    rom[479] = 12'b101011100110;
    rom[480] = 12'b101011100100;
    rom[481] = 12'b101011100010;
    rom[482] = 12'b101011100000;
    rom[483] = 12'b101011011110;
    rom[484] = 12'b101011011100;
    rom[485] = 12'b101011011011;
    rom[486] = 12'b101011011001;
    rom[487] = 12'b101011010111;
    rom[488] = 12'b101011010101;
    rom[489] = 12'b101011010011;
    rom[490] = 12'b101011010001;
    rom[491] = 12'b101011010000;
    rom[492] = 12'b101011001110;
    rom[493] = 12'b101011001100;
    rom[494] = 12'b101011001010;
    rom[495] = 12'b101011001000;
    rom[496] = 12'b101011000111;
    rom[497] = 12'b101011000101;
    rom[498] = 12'b101011000011;
    rom[499] = 12'b101011000001;
    rom[500] = 12'b101010111111;
    rom[501] = 12'b101010111101;
    rom[502] = 12'b101010111100;
    rom[503] = 12'b101010111010;
    rom[504] = 12'b101010111000;
    rom[505] = 12'b101010110110;
    rom[506] = 12'b101010110100;
    rom[507] = 12'b101010110011;
    rom[508] = 12'b101010110001;
    rom[509] = 12'b101010101111;
    rom[510] = 12'b101010101101;
    rom[511] = 12'b101010101100;
    rom[512] = 12'b101010101010;
    rom[513] = 12'b101010101000;
    rom[514] = 12'b101010100110;
    rom[515] = 12'b101010100100;
    rom[516] = 12'b101010100011;
    rom[517] = 12'b101010100001;
    rom[518] = 12'b101010011111;
    rom[519] = 12'b101010011101;
    rom[520] = 12'b101010011100;
    rom[521] = 12'b101010011010;
    rom[522] = 12'b101010011000;
    rom[523] = 12'b101010010110;
    rom[524] = 12'b101010010101;
    rom[525] = 12'b101010010011;
    rom[526] = 12'b101010010001;
    rom[527] = 12'b101010001111;
    rom[528] = 12'b101010001110;
    rom[529] = 12'b101010001100;
    rom[530] = 12'b101010001010;
    rom[531] = 12'b101010001000;
    rom[532] = 12'b101010000111;
    rom[533] = 12'b101010000101;
    rom[534] = 12'b101010000011;
    rom[535] = 12'b101010000010;
    rom[536] = 12'b101010000000;
    rom[537] = 12'b101001111110;
    rom[538] = 12'b101001111100;
    rom[539] = 12'b101001111011;
    rom[540] = 12'b101001111001;
    rom[541] = 12'b101001110111;
    rom[542] = 12'b101001110110;
    rom[543] = 12'b101001110100;
    rom[544] = 12'b101001110010;
    rom[545] = 12'b101001110000;
    rom[546] = 12'b101001101111;
    rom[547] = 12'b101001101101;
    rom[548] = 12'b101001101011;
    rom[549] = 12'b101001101010;
    rom[550] = 12'b101001101000;
    rom[551] = 12'b101001100110;
    rom[552] = 12'b101001100101;
    rom[553] = 12'b101001100011;
    rom[554] = 12'b101001100001;
    rom[555] = 12'b101001011111;
    rom[556] = 12'b101001011110;
    rom[557] = 12'b101001011100;
    rom[558] = 12'b101001011010;
    rom[559] = 12'b101001011001;
    rom[560] = 12'b101001010111;
    rom[561] = 12'b101001010101;
    rom[562] = 12'b101001010100;
    rom[563] = 12'b101001010010;
    rom[564] = 12'b101001010000;
    rom[565] = 12'b101001001111;
    rom[566] = 12'b101001001101;
    rom[567] = 12'b101001001011;
    rom[568] = 12'b101001001010;
    rom[569] = 12'b101001001000;
    rom[570] = 12'b101001000110;
    rom[571] = 12'b101001000101;
    rom[572] = 12'b101001000011;
    rom[573] = 12'b101001000010;
    rom[574] = 12'b101001000000;
    rom[575] = 12'b101000111110;
    rom[576] = 12'b101000111101;
    rom[577] = 12'b101000111011;
    rom[578] = 12'b101000111001;
    rom[579] = 12'b101000111000;
    rom[580] = 12'b101000110110;
    rom[581] = 12'b101000110100;
    rom[582] = 12'b101000110011;
    rom[583] = 12'b101000110001;
    rom[584] = 12'b101000110000;
    rom[585] = 12'b101000101110;
    rom[586] = 12'b101000101100;
    rom[587] = 12'b101000101011;
    rom[588] = 12'b101000101001;
    rom[589] = 12'b101000101000;
    rom[590] = 12'b101000100110;
    rom[591] = 12'b101000100100;
    rom[592] = 12'b101000100011;
    rom[593] = 12'b101000100001;
    rom[594] = 12'b101000011111;
    rom[595] = 12'b101000011110;
    rom[596] = 12'b101000011100;
    rom[597] = 12'b101000011011;
    rom[598] = 12'b101000011001;
    rom[599] = 12'b101000010111;
    rom[600] = 12'b101000010110;
    rom[601] = 12'b101000010100;
    rom[602] = 12'b101000010011;
    rom[603] = 12'b101000010001;
    rom[604] = 12'b101000010000;
    rom[605] = 12'b101000001110;
    rom[606] = 12'b101000001100;
    rom[607] = 12'b101000001011;
    rom[608] = 12'b101000001001;
    rom[609] = 12'b101000001000;
    rom[610] = 12'b101000000110;
    rom[611] = 12'b101000000101;
    rom[612] = 12'b101000000011;
    rom[613] = 12'b101000000001;
    rom[614] = 12'b101000000000;
    rom[615] = 12'b100111111110;
    rom[616] = 12'b100111111101;
    rom[617] = 12'b100111111011;
    rom[618] = 12'b100111111010;
    rom[619] = 12'b100111111000;
    rom[620] = 12'b100111110111;
    rom[621] = 12'b100111110101;
    rom[622] = 12'b100111110011;
    rom[623] = 12'b100111110010;
    rom[624] = 12'b100111110000;
    rom[625] = 12'b100111101111;
    rom[626] = 12'b100111101101;
    rom[627] = 12'b100111101100;
    rom[628] = 12'b100111101010;
    rom[629] = 12'b100111101001;
    rom[630] = 12'b100111100111;
    rom[631] = 12'b100111100110;
    rom[632] = 12'b100111100100;
    rom[633] = 12'b100111100011;
    rom[634] = 12'b100111100001;
    rom[635] = 12'b100111011111;
    rom[636] = 12'b100111011110;
    rom[637] = 12'b100111011100;
    rom[638] = 12'b100111011011;
    rom[639] = 12'b100111011001;
    rom[640] = 12'b100111011000;
    rom[641] = 12'b100111010110;
    rom[642] = 12'b100111010101;
    rom[643] = 12'b100111010011;
    rom[644] = 12'b100111010010;
    rom[645] = 12'b100111010000;
    rom[646] = 12'b100111001111;
    rom[647] = 12'b100111001101;
    rom[648] = 12'b100111001100;
    rom[649] = 12'b100111001010;
    rom[650] = 12'b100111001001;
    rom[651] = 12'b100111000111;
    rom[652] = 12'b100111000110;
    rom[653] = 12'b100111000100;
    rom[654] = 12'b100111000011;
    rom[655] = 12'b100111000001;
    rom[656] = 12'b100111000000;
    rom[657] = 12'b100110111110;
    rom[658] = 12'b100110111101;
    rom[659] = 12'b100110111011;
    rom[660] = 12'b100110111010;
    rom[661] = 12'b100110111000;
    rom[662] = 12'b100110110111;
    rom[663] = 12'b100110110110;
    rom[664] = 12'b100110110100;
    rom[665] = 12'b100110110011;
    rom[666] = 12'b100110110001;
    rom[667] = 12'b100110110000;
    rom[668] = 12'b100110101110;
    rom[669] = 12'b100110101101;
    rom[670] = 12'b100110101011;
    rom[671] = 12'b100110101010;
    rom[672] = 12'b100110101000;
    rom[673] = 12'b100110100111;
    rom[674] = 12'b100110100101;
    rom[675] = 12'b100110100100;
    rom[676] = 12'b100110100011;
    rom[677] = 12'b100110100001;
    rom[678] = 12'b100110100000;
    rom[679] = 12'b100110011110;
    rom[680] = 12'b100110011101;
    rom[681] = 12'b100110011011;
    rom[682] = 12'b100110011010;
    rom[683] = 12'b100110011000;
    rom[684] = 12'b100110010111;
    rom[685] = 12'b100110010110;
    rom[686] = 12'b100110010100;
    rom[687] = 12'b100110010011;
    rom[688] = 12'b100110010001;
    rom[689] = 12'b100110010000;
    rom[690] = 12'b100110001110;
    rom[691] = 12'b100110001101;
    rom[692] = 12'b100110001100;
    rom[693] = 12'b100110001010;
    rom[694] = 12'b100110001001;
    rom[695] = 12'b100110000111;
    rom[696] = 12'b100110000110;
    rom[697] = 12'b100110000100;
    rom[698] = 12'b100110000011;
    rom[699] = 12'b100110000010;
    rom[700] = 12'b100110000000;
    rom[701] = 12'b100101111111;
    rom[702] = 12'b100101111101;
    rom[703] = 12'b100101111100;
    rom[704] = 12'b100101111011;
    rom[705] = 12'b100101111001;
    rom[706] = 12'b100101111000;
    rom[707] = 12'b100101110110;
    rom[708] = 12'b100101110101;
    rom[709] = 12'b100101110100;
    rom[710] = 12'b100101110010;
    rom[711] = 12'b100101110001;
    rom[712] = 12'b100101101111;
    rom[713] = 12'b100101101110;
    rom[714] = 12'b100101101101;
    rom[715] = 12'b100101101011;
    rom[716] = 12'b100101101010;
    rom[717] = 12'b100101101000;
    rom[718] = 12'b100101100111;
    rom[719] = 12'b100101100110;
    rom[720] = 12'b100101100100;
    rom[721] = 12'b100101100011;
    rom[722] = 12'b100101100010;
    rom[723] = 12'b100101100000;
    rom[724] = 12'b100101011111;
    rom[725] = 12'b100101011101;
    rom[726] = 12'b100101011100;
    rom[727] = 12'b100101011011;
    rom[728] = 12'b100101011001;
    rom[729] = 12'b100101011000;
    rom[730] = 12'b100101010111;
    rom[731] = 12'b100101010101;
    rom[732] = 12'b100101010100;
    rom[733] = 12'b100101010011;
    rom[734] = 12'b100101010001;
    rom[735] = 12'b100101010000;
    rom[736] = 12'b100101001110;
    rom[737] = 12'b100101001101;
    rom[738] = 12'b100101001100;
    rom[739] = 12'b100101001010;
    rom[740] = 12'b100101001001;
    rom[741] = 12'b100101001000;
    rom[742] = 12'b100101000110;
    rom[743] = 12'b100101000101;
    rom[744] = 12'b100101000100;
    rom[745] = 12'b100101000010;
    rom[746] = 12'b100101000001;
    rom[747] = 12'b100101000000;
    rom[748] = 12'b100100111110;
    rom[749] = 12'b100100111101;
    rom[750] = 12'b100100111100;
    rom[751] = 12'b100100111010;
    rom[752] = 12'b100100111001;
    rom[753] = 12'b100100111000;
    rom[754] = 12'b100100110110;
    rom[755] = 12'b100100110101;
    rom[756] = 12'b100100110100;
    rom[757] = 12'b100100110010;
    rom[758] = 12'b100100110001;
    rom[759] = 12'b100100110000;
    rom[760] = 12'b100100101110;
    rom[761] = 12'b100100101101;
    rom[762] = 12'b100100101100;
    rom[763] = 12'b100100101010;
    rom[764] = 12'b100100101001;
    rom[765] = 12'b100100101000;
    rom[766] = 12'b100100100111;
    rom[767] = 12'b100100100101;
    rom[768] = 12'b100100100100;
    rom[769] = 12'b100100100011;
    rom[770] = 12'b100100100001;
    rom[771] = 12'b100100100000;
    rom[772] = 12'b100100011111;
    rom[773] = 12'b100100011101;
    rom[774] = 12'b100100011100;
    rom[775] = 12'b100100011011;
    rom[776] = 12'b100100011010;
    rom[777] = 12'b100100011000;
    rom[778] = 12'b100100010111;
    rom[779] = 12'b100100010110;
    rom[780] = 12'b100100010100;
    rom[781] = 12'b100100010011;
    rom[782] = 12'b100100010010;
    rom[783] = 12'b100100010001;
    rom[784] = 12'b100100001111;
    rom[785] = 12'b100100001110;
    rom[786] = 12'b100100001101;
    rom[787] = 12'b100100001011;
    rom[788] = 12'b100100001010;
    rom[789] = 12'b100100001001;
    rom[790] = 12'b100100001000;
    rom[791] = 12'b100100000110;
    rom[792] = 12'b100100000101;
    rom[793] = 12'b100100000100;
    rom[794] = 12'b100100000010;
    rom[795] = 12'b100100000001;
    rom[796] = 12'b100100000000;
    rom[797] = 12'b100011111111;
    rom[798] = 12'b100011111101;
    rom[799] = 12'b100011111100;
    rom[800] = 12'b100011111011;
    rom[801] = 12'b100011111010;
    rom[802] = 12'b100011111000;
    rom[803] = 12'b100011110111;
    rom[804] = 12'b100011110110;
    rom[805] = 12'b100011110101;
    rom[806] = 12'b100011110011;
    rom[807] = 12'b100011110010;
    rom[808] = 12'b100011110001;
    rom[809] = 12'b100011110000;
    rom[810] = 12'b100011101110;
    rom[811] = 12'b100011101101;
    rom[812] = 12'b100011101100;
    rom[813] = 12'b100011101011;
    rom[814] = 12'b100011101001;
    rom[815] = 12'b100011101000;
    rom[816] = 12'b100011100111;
    rom[817] = 12'b100011100110;
    rom[818] = 12'b100011100100;
    rom[819] = 12'b100011100011;
    rom[820] = 12'b100011100010;
    rom[821] = 12'b100011100001;
    rom[822] = 12'b100011011111;
    rom[823] = 12'b100011011110;
    rom[824] = 12'b100011011101;
    rom[825] = 12'b100011011100;
    rom[826] = 12'b100011011011;
    rom[827] = 12'b100011011001;
    rom[828] = 12'b100011011000;
    rom[829] = 12'b100011010111;
    rom[830] = 12'b100011010110;
    rom[831] = 12'b100011010100;
    rom[832] = 12'b100011010011;
    rom[833] = 12'b100011010010;
    rom[834] = 12'b100011010001;
    rom[835] = 12'b100011010000;
    rom[836] = 12'b100011001110;
    rom[837] = 12'b100011001101;
    rom[838] = 12'b100011001100;
    rom[839] = 12'b100011001011;
    rom[840] = 12'b100011001010;
    rom[841] = 12'b100011001000;
    rom[842] = 12'b100011000111;
    rom[843] = 12'b100011000110;
    rom[844] = 12'b100011000101;
    rom[845] = 12'b100011000100;
    rom[846] = 12'b100011000010;
    rom[847] = 12'b100011000001;
    rom[848] = 12'b100011000000;
    rom[849] = 12'b100010111111;
    rom[850] = 12'b100010111110;
    rom[851] = 12'b100010111100;
    rom[852] = 12'b100010111011;
    rom[853] = 12'b100010111010;
    rom[854] = 12'b100010111001;
    rom[855] = 12'b100010111000;
    rom[856] = 12'b100010110110;
    rom[857] = 12'b100010110101;
    rom[858] = 12'b100010110100;
    rom[859] = 12'b100010110011;
    rom[860] = 12'b100010110010;
    rom[861] = 12'b100010110001;
    rom[862] = 12'b100010101111;
    rom[863] = 12'b100010101110;
    rom[864] = 12'b100010101101;
    rom[865] = 12'b100010101100;
    rom[866] = 12'b100010101011;
    rom[867] = 12'b100010101001;
    rom[868] = 12'b100010101000;
    rom[869] = 12'b100010100111;
    rom[870] = 12'b100010100110;
    rom[871] = 12'b100010100101;
    rom[872] = 12'b100010100100;
    rom[873] = 12'b100010100010;
    rom[874] = 12'b100010100001;
    rom[875] = 12'b100010100000;
    rom[876] = 12'b100010011111;
    rom[877] = 12'b100010011110;
    rom[878] = 12'b100010011101;
    rom[879] = 12'b100010011011;
    rom[880] = 12'b100010011010;
    rom[881] = 12'b100010011001;
    rom[882] = 12'b100010011000;
    rom[883] = 12'b100010010111;
    rom[884] = 12'b100010010110;
    rom[885] = 12'b100010010101;
    rom[886] = 12'b100010010011;
    rom[887] = 12'b100010010010;
    rom[888] = 12'b100010010001;
    rom[889] = 12'b100010010000;
    rom[890] = 12'b100010001111;
    rom[891] = 12'b100010001110;
    rom[892] = 12'b100010001101;
    rom[893] = 12'b100010001011;
    rom[894] = 12'b100010001010;
    rom[895] = 12'b100010001001;
    rom[896] = 12'b100010001000;
    rom[897] = 12'b100010000111;
    rom[898] = 12'b100010000110;
    rom[899] = 12'b100010000101;
    rom[900] = 12'b100010000011;
    rom[901] = 12'b100010000010;
    rom[902] = 12'b100010000001;
    rom[903] = 12'b100010000000;
    rom[904] = 12'b100001111111;
    rom[905] = 12'b100001111110;
    rom[906] = 12'b100001111101;
    rom[907] = 12'b100001111100;
    rom[908] = 12'b100001111010;
    rom[909] = 12'b100001111001;
    rom[910] = 12'b100001111000;
    rom[911] = 12'b100001110111;
    rom[912] = 12'b100001110110;
    rom[913] = 12'b100001110101;
    rom[914] = 12'b100001110100;
    rom[915] = 12'b100001110011;
    rom[916] = 12'b100001110001;
    rom[917] = 12'b100001110000;
    rom[918] = 12'b100001101111;
    rom[919] = 12'b100001101110;
    rom[920] = 12'b100001101101;
    rom[921] = 12'b100001101100;
    rom[922] = 12'b100001101011;
    rom[923] = 12'b100001101010;
    rom[924] = 12'b100001101001;
    rom[925] = 12'b100001100111;
    rom[926] = 12'b100001100110;
    rom[927] = 12'b100001100101;
    rom[928] = 12'b100001100100;
    rom[929] = 12'b100001100011;
    rom[930] = 12'b100001100010;
    rom[931] = 12'b100001100001;
    rom[932] = 12'b100001100000;
    rom[933] = 12'b100001011111;
    rom[934] = 12'b100001011110;
    rom[935] = 12'b100001011100;
    rom[936] = 12'b100001011011;
    rom[937] = 12'b100001011010;
    rom[938] = 12'b100001011001;
    rom[939] = 12'b100001011000;
    rom[940] = 12'b100001010111;
    rom[941] = 12'b100001010110;
    rom[942] = 12'b100001010101;
    rom[943] = 12'b100001010100;
    rom[944] = 12'b100001010011;
    rom[945] = 12'b100001010010;
    rom[946] = 12'b100001010001;
    rom[947] = 12'b100001001111;
    rom[948] = 12'b100001001110;
    rom[949] = 12'b100001001101;
    rom[950] = 12'b100001001100;
    rom[951] = 12'b100001001011;
    rom[952] = 12'b100001001010;
    rom[953] = 12'b100001001001;
    rom[954] = 12'b100001001000;
    rom[955] = 12'b100001000111;
    rom[956] = 12'b100001000110;
    rom[957] = 12'b100001000101;
    rom[958] = 12'b100001000100;
    rom[959] = 12'b100001000011;
    rom[960] = 12'b100001000010;
    rom[961] = 12'b100001000000;
    rom[962] = 12'b100000111111;
    rom[963] = 12'b100000111110;
    rom[964] = 12'b100000111101;
    rom[965] = 12'b100000111100;
    rom[966] = 12'b100000111011;
    rom[967] = 12'b100000111010;
    rom[968] = 12'b100000111001;
    rom[969] = 12'b100000111000;
    rom[970] = 12'b100000110111;
    rom[971] = 12'b100000110110;
    rom[972] = 12'b100000110101;
    rom[973] = 12'b100000110100;
    rom[974] = 12'b100000110011;
    rom[975] = 12'b100000110010;
    rom[976] = 12'b100000110001;
    rom[977] = 12'b100000110000;
    rom[978] = 12'b100000101111;
    rom[979] = 12'b100000101101;
    rom[980] = 12'b100000101100;
    rom[981] = 12'b100000101011;
    rom[982] = 12'b100000101010;
    rom[983] = 12'b100000101001;
    rom[984] = 12'b100000101000;
    rom[985] = 12'b100000100111;
    rom[986] = 12'b100000100110;
    rom[987] = 12'b100000100101;
    rom[988] = 12'b100000100100;
    rom[989] = 12'b100000100011;
    rom[990] = 12'b100000100010;
    rom[991] = 12'b100000100001;
    rom[992] = 12'b100000100000;
    rom[993] = 12'b100000011111;
    rom[994] = 12'b100000011110;
    rom[995] = 12'b100000011101;
    rom[996] = 12'b100000011100;
    rom[997] = 12'b100000011011;
    rom[998] = 12'b100000011010;
    rom[999] = 12'b100000011001;
    rom[1000] = 12'b100000011000;
    rom[1001] = 12'b100000010111;
    rom[1002] = 12'b100000010110;
    rom[1003] = 12'b100000010101;
    rom[1004] = 12'b100000010100;
    rom[1005] = 12'b100000010011;
    rom[1006] = 12'b100000010010;
    rom[1007] = 12'b100000010001;
    rom[1008] = 12'b100000010000;
    rom[1009] = 12'b100000001111;
    rom[1010] = 12'b100000001110;
    rom[1011] = 12'b100000001101;
    rom[1012] = 12'b100000001100;
    rom[1013] = 12'b100000001011;
    rom[1014] = 12'b100000001010;
    rom[1015] = 12'b100000001001;
    rom[1016] = 12'b100000001000;
    rom[1017] = 12'b100000000111;
    rom[1018] = 12'b100000000110;
    rom[1019] = 12'b100000000101;
    rom[1020] = 12'b100000000100;
    rom[1021] = 12'b100000000011;
    rom[1022] = 12'b100000000010;
    rom[1023] = 12'b100000000001;
  end
  always @(posedge clk) begin
    if(a_translated_fire) begin
      rom_spinal_port0 <= rom[a_translated_payload];
    end
  end

  assign table_0 = 12'hffe;
  assign table_1 = 12'hffa;
  assign table_2 = 12'hff6;
  assign table_3 = 12'hff2;
  assign table_4 = 12'hfee;
  assign table_5 = 12'hfea;
  assign table_6 = 12'hfe6;
  assign table_7 = 12'hfe2;
  assign table_8 = 12'hfde;
  assign table_9 = 12'hfda;
  assign table_10 = 12'hfd6;
  assign table_11 = 12'hfd3;
  assign table_12 = 12'hfcf;
  assign table_13 = 12'hfcb;
  assign table_14 = 12'hfc7;
  assign table_15 = 12'hfc3;
  assign table_16 = 12'hfbf;
  assign table_17 = 12'hfbb;
  assign table_18 = 12'hfb7;
  assign table_19 = 12'hfb3;
  assign table_20 = 12'hfb0;
  assign table_21 = 12'hfac;
  assign table_22 = 12'hfa8;
  assign table_23 = 12'hfa4;
  assign table_24 = 12'hfa0;
  assign table_25 = 12'hf9c;
  assign table_26 = 12'hf99;
  assign table_27 = 12'hf95;
  assign table_28 = 12'hf91;
  assign table_29 = 12'hf8d;
  assign table_30 = 12'hf8a;
  assign table_31 = 12'hf86;
  assign table_32 = 12'hf82;
  assign table_33 = 12'hf7e;
  assign table_34 = 12'hf7a;
  assign table_35 = 12'hf77;
  assign table_36 = 12'hf73;
  assign table_37 = 12'hf6f;
  assign table_38 = 12'hf6c;
  assign table_39 = 12'hf68;
  assign table_40 = 12'hf64;
  assign table_41 = 12'hf60;
  assign table_42 = 12'hf5d;
  assign table_43 = 12'hf59;
  assign table_44 = 12'hf55;
  assign table_45 = 12'hf52;
  assign table_46 = 12'hf4e;
  assign table_47 = 12'hf4a;
  assign table_48 = 12'hf47;
  assign table_49 = 12'hf43;
  assign table_50 = 12'hf3f;
  assign table_51 = 12'hf3c;
  assign table_52 = 12'hf38;
  assign table_53 = 12'hf35;
  assign table_54 = 12'hf31;
  assign table_55 = 12'hf2d;
  assign table_56 = 12'hf2a;
  assign table_57 = 12'hf26;
  assign table_58 = 12'hf23;
  assign table_59 = 12'hf1f;
  assign table_60 = 12'hf1c;
  assign table_61 = 12'hf18;
  assign table_62 = 12'hf14;
  assign table_63 = 12'hf11;
  assign table_64 = 12'hf0d;
  assign table_65 = 12'hf0a;
  assign table_66 = 12'hf06;
  assign table_67 = 12'hf03;
  assign table_68 = 12'heff;
  assign table_69 = 12'hefc;
  assign table_70 = 12'hef8;
  assign table_71 = 12'hef5;
  assign table_72 = 12'hef1;
  assign table_73 = 12'heee;
  assign table_74 = 12'heea;
  assign table_75 = 12'hee7;
  assign table_76 = 12'hee3;
  assign table_77 = 12'hee0;
  assign table_78 = 12'hedc;
  assign table_79 = 12'hed9;
  assign table_80 = 12'hed5;
  assign table_81 = 12'hed2;
  assign table_82 = 12'hecf;
  assign table_83 = 12'hecb;
  assign table_84 = 12'hec8;
  assign table_85 = 12'hec4;
  assign table_86 = 12'hec1;
  assign table_87 = 12'hebe;
  assign table_88 = 12'heba;
  assign table_89 = 12'heb7;
  assign table_90 = 12'heb3;
  assign table_91 = 12'heb0;
  assign table_92 = 12'head;
  assign table_93 = 12'hea9;
  assign table_94 = 12'hea6;
  assign table_95 = 12'hea3;
  assign table_96 = 12'he9f;
  assign table_97 = 12'he9c;
  assign table_98 = 12'he99;
  assign table_99 = 12'he95;
  assign table_100 = 12'he92;
  assign table_101 = 12'he8f;
  assign table_102 = 12'he8b;
  assign table_103 = 12'he88;
  assign table_104 = 12'he85;
  assign table_105 = 12'he81;
  assign table_106 = 12'he7e;
  assign table_107 = 12'he7b;
  assign table_108 = 12'he78;
  assign table_109 = 12'he74;
  assign table_110 = 12'he71;
  assign table_111 = 12'he6e;
  assign table_112 = 12'he6b;
  assign table_113 = 12'he67;
  assign table_114 = 12'he64;
  assign table_115 = 12'he61;
  assign table_116 = 12'he5e;
  assign table_117 = 12'he5a;
  assign table_118 = 12'he57;
  assign table_119 = 12'he54;
  assign table_120 = 12'he51;
  assign table_121 = 12'he4e;
  assign table_122 = 12'he4a;
  assign table_123 = 12'he47;
  assign table_124 = 12'he44;
  assign table_125 = 12'he41;
  assign table_126 = 12'he3e;
  assign table_127 = 12'he3a;
  assign table_128 = 12'he37;
  assign table_129 = 12'he34;
  assign table_130 = 12'he31;
  assign table_131 = 12'he2e;
  assign table_132 = 12'he2b;
  assign table_133 = 12'he28;
  assign table_134 = 12'he24;
  assign table_135 = 12'he21;
  assign table_136 = 12'he1e;
  assign table_137 = 12'he1b;
  assign table_138 = 12'he18;
  assign table_139 = 12'he15;
  assign table_140 = 12'he12;
  assign table_141 = 12'he0f;
  assign table_142 = 12'he0c;
  assign table_143 = 12'he09;
  assign table_144 = 12'he05;
  assign table_145 = 12'he02;
  assign table_146 = 12'hdff;
  assign table_147 = 12'hdfc;
  assign table_148 = 12'hdf9;
  assign table_149 = 12'hdf6;
  assign table_150 = 12'hdf3;
  assign table_151 = 12'hdf0;
  assign table_152 = 12'hded;
  assign table_153 = 12'hdea;
  assign table_154 = 12'hde7;
  assign table_155 = 12'hde4;
  assign table_156 = 12'hde1;
  assign table_157 = 12'hdde;
  assign table_158 = 12'hddb;
  assign table_159 = 12'hdd8;
  assign table_160 = 12'hdd5;
  assign table_161 = 12'hdd2;
  assign table_162 = 12'hdcf;
  assign table_163 = 12'hdcc;
  assign table_164 = 12'hdc9;
  assign table_165 = 12'hdc6;
  assign table_166 = 12'hdc3;
  assign table_167 = 12'hdc0;
  assign table_168 = 12'hdbd;
  assign table_169 = 12'hdba;
  assign table_170 = 12'hdb7;
  assign table_171 = 12'hdb4;
  assign table_172 = 12'hdb1;
  assign table_173 = 12'hdaf;
  assign table_174 = 12'hdac;
  assign table_175 = 12'hda9;
  assign table_176 = 12'hda6;
  assign table_177 = 12'hda3;
  assign table_178 = 12'hda0;
  assign table_179 = 12'hd9d;
  assign table_180 = 12'hd9a;
  assign table_181 = 12'hd97;
  assign table_182 = 12'hd94;
  assign table_183 = 12'hd92;
  assign table_184 = 12'hd8f;
  assign table_185 = 12'hd8c;
  assign table_186 = 12'hd89;
  assign table_187 = 12'hd86;
  assign table_188 = 12'hd83;
  assign table_189 = 12'hd80;
  assign table_190 = 12'hd7e;
  assign table_191 = 12'hd7b;
  assign table_192 = 12'hd78;
  assign table_193 = 12'hd75;
  assign table_194 = 12'hd72;
  assign table_195 = 12'hd6f;
  assign table_196 = 12'hd6d;
  assign table_197 = 12'hd6a;
  assign table_198 = 12'hd67;
  assign table_199 = 12'hd64;
  assign table_200 = 12'hd61;
  assign table_201 = 12'hd5f;
  assign table_202 = 12'hd5c;
  assign table_203 = 12'hd59;
  assign table_204 = 12'hd56;
  assign table_205 = 12'hd53;
  assign table_206 = 12'hd51;
  assign table_207 = 12'hd4e;
  assign table_208 = 12'hd4b;
  assign table_209 = 12'hd48;
  assign table_210 = 12'hd46;
  assign table_211 = 12'hd43;
  assign table_212 = 12'hd40;
  assign table_213 = 12'hd3d;
  assign table_214 = 12'hd3b;
  assign table_215 = 12'hd38;
  assign table_216 = 12'hd35;
  assign table_217 = 12'hd32;
  assign table_218 = 12'hd30;
  assign table_219 = 12'hd2d;
  assign table_220 = 12'hd2a;
  assign table_221 = 12'hd28;
  assign table_222 = 12'hd25;
  assign table_223 = 12'hd22;
  assign table_224 = 12'hd1f;
  assign table_225 = 12'hd1d;
  assign table_226 = 12'hd1a;
  assign table_227 = 12'hd17;
  assign table_228 = 12'hd15;
  assign table_229 = 12'hd12;
  assign table_230 = 12'hd0f;
  assign table_231 = 12'hd0d;
  assign table_232 = 12'hd0a;
  assign table_233 = 12'hd07;
  assign table_234 = 12'hd05;
  assign table_235 = 12'hd02;
  assign table_236 = 12'hcff;
  assign table_237 = 12'hcfd;
  assign table_238 = 12'hcfa;
  assign table_239 = 12'hcf8;
  assign table_240 = 12'hcf5;
  assign table_241 = 12'hcf2;
  assign table_242 = 12'hcf0;
  assign table_243 = 12'hced;
  assign table_244 = 12'hceb;
  assign table_245 = 12'hce8;
  assign table_246 = 12'hce5;
  assign table_247 = 12'hce3;
  assign table_248 = 12'hce0;
  assign table_249 = 12'hcde;
  assign table_250 = 12'hcdb;
  assign table_251 = 12'hcd8;
  assign table_252 = 12'hcd6;
  assign table_253 = 12'hcd3;
  assign table_254 = 12'hcd1;
  assign table_255 = 12'hcce;
  assign table_256 = 12'hccc;
  assign table_257 = 12'hcc9;
  assign table_258 = 12'hcc6;
  assign table_259 = 12'hcc4;
  assign table_260 = 12'hcc1;
  assign table_261 = 12'hcbf;
  assign table_262 = 12'hcbc;
  assign table_263 = 12'hcba;
  assign table_264 = 12'hcb7;
  assign table_265 = 12'hcb5;
  assign table_266 = 12'hcb2;
  assign table_267 = 12'hcb0;
  assign table_268 = 12'hcad;
  assign table_269 = 12'hcab;
  assign table_270 = 12'hca8;
  assign table_271 = 12'hca6;
  assign table_272 = 12'hca3;
  assign table_273 = 12'hca1;
  assign table_274 = 12'hc9e;
  assign table_275 = 12'hc9c;
  assign table_276 = 12'hc99;
  assign table_277 = 12'hc97;
  assign table_278 = 12'hc94;
  assign table_279 = 12'hc92;
  assign table_280 = 12'hc8f;
  assign table_281 = 12'hc8d;
  assign table_282 = 12'hc8a;
  assign table_283 = 12'hc88;
  assign table_284 = 12'hc85;
  assign table_285 = 12'hc83;
  assign table_286 = 12'hc81;
  assign table_287 = 12'hc7e;
  assign table_288 = 12'hc7c;
  assign table_289 = 12'hc79;
  assign table_290 = 12'hc77;
  assign table_291 = 12'hc74;
  assign table_292 = 12'hc72;
  assign table_293 = 12'hc70;
  assign table_294 = 12'hc6d;
  assign table_295 = 12'hc6b;
  assign table_296 = 12'hc68;
  assign table_297 = 12'hc66;
  assign table_298 = 12'hc63;
  assign table_299 = 12'hc61;
  assign table_300 = 12'hc5f;
  assign table_301 = 12'hc5c;
  assign table_302 = 12'hc5a;
  assign table_303 = 12'hc58;
  assign table_304 = 12'hc55;
  assign table_305 = 12'hc53;
  assign table_306 = 12'hc50;
  assign table_307 = 12'hc4e;
  assign table_308 = 12'hc4c;
  assign table_309 = 12'hc49;
  assign table_310 = 12'hc47;
  assign table_311 = 12'hc45;
  assign table_312 = 12'hc42;
  assign table_313 = 12'hc40;
  assign table_314 = 12'hc3e;
  assign table_315 = 12'hc3b;
  assign table_316 = 12'hc39;
  assign table_317 = 12'hc37;
  assign table_318 = 12'hc34;
  assign table_319 = 12'hc32;
  assign table_320 = 12'hc30;
  assign table_321 = 12'hc2d;
  assign table_322 = 12'hc2b;
  assign table_323 = 12'hc29;
  assign table_324 = 12'hc26;
  assign table_325 = 12'hc24;
  assign table_326 = 12'hc22;
  assign table_327 = 12'hc1f;
  assign table_328 = 12'hc1d;
  assign table_329 = 12'hc1b;
  assign table_330 = 12'hc19;
  assign table_331 = 12'hc16;
  assign table_332 = 12'hc14;
  assign table_333 = 12'hc12;
  assign table_334 = 12'hc0f;
  assign table_335 = 12'hc0d;
  assign table_336 = 12'hc0b;
  assign table_337 = 12'hc09;
  assign table_338 = 12'hc06;
  assign table_339 = 12'hc04;
  assign table_340 = 12'hc02;
  assign table_341 = 12'hc00;
  assign table_342 = 12'hbfd;
  assign table_343 = 12'hbfb;
  assign table_344 = 12'hbf9;
  assign table_345 = 12'hbf7;
  assign table_346 = 12'hbf4;
  assign table_347 = 12'hbf2;
  assign table_348 = 12'hbf0;
  assign table_349 = 12'hbee;
  assign table_350 = 12'hbec;
  assign table_351 = 12'hbe9;
  assign table_352 = 12'hbe7;
  assign table_353 = 12'hbe5;
  assign table_354 = 12'hbe3;
  assign table_355 = 12'hbe0;
  assign table_356 = 12'hbde;
  assign table_357 = 12'hbdc;
  assign table_358 = 12'hbda;
  assign table_359 = 12'hbd8;
  assign table_360 = 12'hbd5;
  assign table_361 = 12'hbd3;
  assign table_362 = 12'hbd1;
  assign table_363 = 12'hbcf;
  assign table_364 = 12'hbcd;
  assign table_365 = 12'hbcb;
  assign table_366 = 12'hbc8;
  assign table_367 = 12'hbc6;
  assign table_368 = 12'hbc4;
  assign table_369 = 12'hbc2;
  assign table_370 = 12'hbc0;
  assign table_371 = 12'hbbe;
  assign table_372 = 12'hbbb;
  assign table_373 = 12'hbb9;
  assign table_374 = 12'hbb7;
  assign table_375 = 12'hbb5;
  assign table_376 = 12'hbb3;
  assign table_377 = 12'hbb1;
  assign table_378 = 12'hbaf;
  assign table_379 = 12'hbac;
  assign table_380 = 12'hbaa;
  assign table_381 = 12'hba8;
  assign table_382 = 12'hba6;
  assign table_383 = 12'hba4;
  assign table_384 = 12'hba2;
  assign table_385 = 12'hba0;
  assign table_386 = 12'hb9e;
  assign table_387 = 12'hb9c;
  assign table_388 = 12'hb99;
  assign table_389 = 12'hb97;
  assign table_390 = 12'hb95;
  assign table_391 = 12'hb93;
  assign table_392 = 12'hb91;
  assign table_393 = 12'hb8f;
  assign table_394 = 12'hb8d;
  assign table_395 = 12'hb8b;
  assign table_396 = 12'hb89;
  assign table_397 = 12'hb87;
  assign table_398 = 12'hb85;
  assign table_399 = 12'hb82;
  assign table_400 = 12'hb80;
  assign table_401 = 12'hb7e;
  assign table_402 = 12'hb7c;
  assign table_403 = 12'hb7a;
  assign table_404 = 12'hb78;
  assign table_405 = 12'hb76;
  assign table_406 = 12'hb74;
  assign table_407 = 12'hb72;
  assign table_408 = 12'hb70;
  assign table_409 = 12'hb6e;
  assign table_410 = 12'hb6c;
  assign table_411 = 12'hb6a;
  assign table_412 = 12'hb68;
  assign table_413 = 12'hb66;
  assign table_414 = 12'hb64;
  assign table_415 = 12'hb62;
  assign table_416 = 12'hb60;
  assign table_417 = 12'hb5e;
  assign table_418 = 12'hb5c;
  assign table_419 = 12'hb5a;
  assign table_420 = 12'hb58;
  assign table_421 = 12'hb56;
  assign table_422 = 12'hb54;
  assign table_423 = 12'hb52;
  assign table_424 = 12'hb50;
  assign table_425 = 12'hb4e;
  assign table_426 = 12'hb4c;
  assign table_427 = 12'hb4a;
  assign table_428 = 12'hb48;
  assign table_429 = 12'hb46;
  assign table_430 = 12'hb44;
  assign table_431 = 12'hb42;
  assign table_432 = 12'hb40;
  assign table_433 = 12'hb3e;
  assign table_434 = 12'hb3c;
  assign table_435 = 12'hb3a;
  assign table_436 = 12'hb38;
  assign table_437 = 12'hb36;
  assign table_438 = 12'hb34;
  assign table_439 = 12'hb32;
  assign table_440 = 12'hb30;
  assign table_441 = 12'hb2e;
  assign table_442 = 12'hb2c;
  assign table_443 = 12'hb2a;
  assign table_444 = 12'hb28;
  assign table_445 = 12'hb26;
  assign table_446 = 12'hb24;
  assign table_447 = 12'hb22;
  assign table_448 = 12'hb20;
  assign table_449 = 12'hb1e;
  assign table_450 = 12'hb1d;
  assign table_451 = 12'hb1b;
  assign table_452 = 12'hb19;
  assign table_453 = 12'hb17;
  assign table_454 = 12'hb15;
  assign table_455 = 12'hb13;
  assign table_456 = 12'hb11;
  assign table_457 = 12'hb0f;
  assign table_458 = 12'hb0d;
  assign table_459 = 12'hb0b;
  assign table_460 = 12'hb09;
  assign table_461 = 12'hb07;
  assign table_462 = 12'hb06;
  assign table_463 = 12'hb04;
  assign table_464 = 12'hb02;
  assign table_465 = 12'hb00;
  assign table_466 = 12'hafe;
  assign table_467 = 12'hafc;
  assign table_468 = 12'hafa;
  assign table_469 = 12'haf8;
  assign table_470 = 12'haf6;
  assign table_471 = 12'haf5;
  assign table_472 = 12'haf3;
  assign table_473 = 12'haf1;
  assign table_474 = 12'haef;
  assign table_475 = 12'haed;
  assign table_476 = 12'haeb;
  assign table_477 = 12'hae9;
  assign table_478 = 12'hae8;
  assign table_479 = 12'hae6;
  assign table_480 = 12'hae4;
  assign table_481 = 12'hae2;
  assign table_482 = 12'hae0;
  assign table_483 = 12'hade;
  assign table_484 = 12'hadc;
  assign table_485 = 12'hadb;
  assign table_486 = 12'had9;
  assign table_487 = 12'had7;
  assign table_488 = 12'had5;
  assign table_489 = 12'had3;
  assign table_490 = 12'had1;
  assign table_491 = 12'had0;
  assign table_492 = 12'hace;
  assign table_493 = 12'hacc;
  assign table_494 = 12'haca;
  assign table_495 = 12'hac8;
  assign table_496 = 12'hac7;
  assign table_497 = 12'hac5;
  assign table_498 = 12'hac3;
  assign table_499 = 12'hac1;
  assign table_500 = 12'habf;
  assign table_501 = 12'habd;
  assign table_502 = 12'habc;
  assign table_503 = 12'haba;
  assign table_504 = 12'hab8;
  assign table_505 = 12'hab6;
  assign table_506 = 12'hab4;
  assign table_507 = 12'hab3;
  assign table_508 = 12'hab1;
  assign table_509 = 12'haaf;
  assign table_510 = 12'haad;
  assign table_511 = 12'haac;
  assign table_512 = 12'haaa;
  assign table_513 = 12'haa8;
  assign table_514 = 12'haa6;
  assign table_515 = 12'haa4;
  assign table_516 = 12'haa3;
  assign table_517 = 12'haa1;
  assign table_518 = 12'ha9f;
  assign table_519 = 12'ha9d;
  assign table_520 = 12'ha9c;
  assign table_521 = 12'ha9a;
  assign table_522 = 12'ha98;
  assign table_523 = 12'ha96;
  assign table_524 = 12'ha95;
  assign table_525 = 12'ha93;
  assign table_526 = 12'ha91;
  assign table_527 = 12'ha8f;
  assign table_528 = 12'ha8e;
  assign table_529 = 12'ha8c;
  assign table_530 = 12'ha8a;
  assign table_531 = 12'ha88;
  assign table_532 = 12'ha87;
  assign table_533 = 12'ha85;
  assign table_534 = 12'ha83;
  assign table_535 = 12'ha82;
  assign table_536 = 12'ha80;
  assign table_537 = 12'ha7e;
  assign table_538 = 12'ha7c;
  assign table_539 = 12'ha7b;
  assign table_540 = 12'ha79;
  assign table_541 = 12'ha77;
  assign table_542 = 12'ha76;
  assign table_543 = 12'ha74;
  assign table_544 = 12'ha72;
  assign table_545 = 12'ha70;
  assign table_546 = 12'ha6f;
  assign table_547 = 12'ha6d;
  assign table_548 = 12'ha6b;
  assign table_549 = 12'ha6a;
  assign table_550 = 12'ha68;
  assign table_551 = 12'ha66;
  assign table_552 = 12'ha65;
  assign table_553 = 12'ha63;
  assign table_554 = 12'ha61;
  assign table_555 = 12'ha5f;
  assign table_556 = 12'ha5e;
  assign table_557 = 12'ha5c;
  assign table_558 = 12'ha5a;
  assign table_559 = 12'ha59;
  assign table_560 = 12'ha57;
  assign table_561 = 12'ha55;
  assign table_562 = 12'ha54;
  assign table_563 = 12'ha52;
  assign table_564 = 12'ha50;
  assign table_565 = 12'ha4f;
  assign table_566 = 12'ha4d;
  assign table_567 = 12'ha4b;
  assign table_568 = 12'ha4a;
  assign table_569 = 12'ha48;
  assign table_570 = 12'ha46;
  assign table_571 = 12'ha45;
  assign table_572 = 12'ha43;
  assign table_573 = 12'ha42;
  assign table_574 = 12'ha40;
  assign table_575 = 12'ha3e;
  assign table_576 = 12'ha3d;
  assign table_577 = 12'ha3b;
  assign table_578 = 12'ha39;
  assign table_579 = 12'ha38;
  assign table_580 = 12'ha36;
  assign table_581 = 12'ha34;
  assign table_582 = 12'ha33;
  assign table_583 = 12'ha31;
  assign table_584 = 12'ha30;
  assign table_585 = 12'ha2e;
  assign table_586 = 12'ha2c;
  assign table_587 = 12'ha2b;
  assign table_588 = 12'ha29;
  assign table_589 = 12'ha28;
  assign table_590 = 12'ha26;
  assign table_591 = 12'ha24;
  assign table_592 = 12'ha23;
  assign table_593 = 12'ha21;
  assign table_594 = 12'ha1f;
  assign table_595 = 12'ha1e;
  assign table_596 = 12'ha1c;
  assign table_597 = 12'ha1b;
  assign table_598 = 12'ha19;
  assign table_599 = 12'ha17;
  assign table_600 = 12'ha16;
  assign table_601 = 12'ha14;
  assign table_602 = 12'ha13;
  assign table_603 = 12'ha11;
  assign table_604 = 12'ha10;
  assign table_605 = 12'ha0e;
  assign table_606 = 12'ha0c;
  assign table_607 = 12'ha0b;
  assign table_608 = 12'ha09;
  assign table_609 = 12'ha08;
  assign table_610 = 12'ha06;
  assign table_611 = 12'ha05;
  assign table_612 = 12'ha03;
  assign table_613 = 12'ha01;
  assign table_614 = 12'ha00;
  assign table_615 = 12'h9fe;
  assign table_616 = 12'h9fd;
  assign table_617 = 12'h9fb;
  assign table_618 = 12'h9fa;
  assign table_619 = 12'h9f8;
  assign table_620 = 12'h9f7;
  assign table_621 = 12'h9f5;
  assign table_622 = 12'h9f3;
  assign table_623 = 12'h9f2;
  assign table_624 = 12'h9f0;
  assign table_625 = 12'h9ef;
  assign table_626 = 12'h9ed;
  assign table_627 = 12'h9ec;
  assign table_628 = 12'h9ea;
  assign table_629 = 12'h9e9;
  assign table_630 = 12'h9e7;
  assign table_631 = 12'h9e6;
  assign table_632 = 12'h9e4;
  assign table_633 = 12'h9e3;
  assign table_634 = 12'h9e1;
  assign table_635 = 12'h9df;
  assign table_636 = 12'h9de;
  assign table_637 = 12'h9dc;
  assign table_638 = 12'h9db;
  assign table_639 = 12'h9d9;
  assign table_640 = 12'h9d8;
  assign table_641 = 12'h9d6;
  assign table_642 = 12'h9d5;
  assign table_643 = 12'h9d3;
  assign table_644 = 12'h9d2;
  assign table_645 = 12'h9d0;
  assign table_646 = 12'h9cf;
  assign table_647 = 12'h9cd;
  assign table_648 = 12'h9cc;
  assign table_649 = 12'h9ca;
  assign table_650 = 12'h9c9;
  assign table_651 = 12'h9c7;
  assign table_652 = 12'h9c6;
  assign table_653 = 12'h9c4;
  assign table_654 = 12'h9c3;
  assign table_655 = 12'h9c1;
  assign table_656 = 12'h9c0;
  assign table_657 = 12'h9be;
  assign table_658 = 12'h9bd;
  assign table_659 = 12'h9bb;
  assign table_660 = 12'h9ba;
  assign table_661 = 12'h9b8;
  assign table_662 = 12'h9b7;
  assign table_663 = 12'h9b6;
  assign table_664 = 12'h9b4;
  assign table_665 = 12'h9b3;
  assign table_666 = 12'h9b1;
  assign table_667 = 12'h9b0;
  assign table_668 = 12'h9ae;
  assign table_669 = 12'h9ad;
  assign table_670 = 12'h9ab;
  assign table_671 = 12'h9aa;
  assign table_672 = 12'h9a8;
  assign table_673 = 12'h9a7;
  assign table_674 = 12'h9a5;
  assign table_675 = 12'h9a4;
  assign table_676 = 12'h9a3;
  assign table_677 = 12'h9a1;
  assign table_678 = 12'h9a0;
  assign table_679 = 12'h99e;
  assign table_680 = 12'h99d;
  assign table_681 = 12'h99b;
  assign table_682 = 12'h99a;
  assign table_683 = 12'h998;
  assign table_684 = 12'h997;
  assign table_685 = 12'h996;
  assign table_686 = 12'h994;
  assign table_687 = 12'h993;
  assign table_688 = 12'h991;
  assign table_689 = 12'h990;
  assign table_690 = 12'h98e;
  assign table_691 = 12'h98d;
  assign table_692 = 12'h98c;
  assign table_693 = 12'h98a;
  assign table_694 = 12'h989;
  assign table_695 = 12'h987;
  assign table_696 = 12'h986;
  assign table_697 = 12'h984;
  assign table_698 = 12'h983;
  assign table_699 = 12'h982;
  assign table_700 = 12'h980;
  assign table_701 = 12'h97f;
  assign table_702 = 12'h97d;
  assign table_703 = 12'h97c;
  assign table_704 = 12'h97b;
  assign table_705 = 12'h979;
  assign table_706 = 12'h978;
  assign table_707 = 12'h976;
  assign table_708 = 12'h975;
  assign table_709 = 12'h974;
  assign table_710 = 12'h972;
  assign table_711 = 12'h971;
  assign table_712 = 12'h96f;
  assign table_713 = 12'h96e;
  assign table_714 = 12'h96d;
  assign table_715 = 12'h96b;
  assign table_716 = 12'h96a;
  assign table_717 = 12'h968;
  assign table_718 = 12'h967;
  assign table_719 = 12'h966;
  assign table_720 = 12'h964;
  assign table_721 = 12'h963;
  assign table_722 = 12'h962;
  assign table_723 = 12'h960;
  assign table_724 = 12'h95f;
  assign table_725 = 12'h95d;
  assign table_726 = 12'h95c;
  assign table_727 = 12'h95b;
  assign table_728 = 12'h959;
  assign table_729 = 12'h958;
  assign table_730 = 12'h957;
  assign table_731 = 12'h955;
  assign table_732 = 12'h954;
  assign table_733 = 12'h953;
  assign table_734 = 12'h951;
  assign table_735 = 12'h950;
  assign table_736 = 12'h94e;
  assign table_737 = 12'h94d;
  assign table_738 = 12'h94c;
  assign table_739 = 12'h94a;
  assign table_740 = 12'h949;
  assign table_741 = 12'h948;
  assign table_742 = 12'h946;
  assign table_743 = 12'h945;
  assign table_744 = 12'h944;
  assign table_745 = 12'h942;
  assign table_746 = 12'h941;
  assign table_747 = 12'h940;
  assign table_748 = 12'h93e;
  assign table_749 = 12'h93d;
  assign table_750 = 12'h93c;
  assign table_751 = 12'h93a;
  assign table_752 = 12'h939;
  assign table_753 = 12'h938;
  assign table_754 = 12'h936;
  assign table_755 = 12'h935;
  assign table_756 = 12'h934;
  assign table_757 = 12'h932;
  assign table_758 = 12'h931;
  assign table_759 = 12'h930;
  assign table_760 = 12'h92e;
  assign table_761 = 12'h92d;
  assign table_762 = 12'h92c;
  assign table_763 = 12'h92a;
  assign table_764 = 12'h929;
  assign table_765 = 12'h928;
  assign table_766 = 12'h927;
  assign table_767 = 12'h925;
  assign table_768 = 12'h924;
  assign table_769 = 12'h923;
  assign table_770 = 12'h921;
  assign table_771 = 12'h920;
  assign table_772 = 12'h91f;
  assign table_773 = 12'h91d;
  assign table_774 = 12'h91c;
  assign table_775 = 12'h91b;
  assign table_776 = 12'h91a;
  assign table_777 = 12'h918;
  assign table_778 = 12'h917;
  assign table_779 = 12'h916;
  assign table_780 = 12'h914;
  assign table_781 = 12'h913;
  assign table_782 = 12'h912;
  assign table_783 = 12'h911;
  assign table_784 = 12'h90f;
  assign table_785 = 12'h90e;
  assign table_786 = 12'h90d;
  assign table_787 = 12'h90b;
  assign table_788 = 12'h90a;
  assign table_789 = 12'h909;
  assign table_790 = 12'h908;
  assign table_791 = 12'h906;
  assign table_792 = 12'h905;
  assign table_793 = 12'h904;
  assign table_794 = 12'h902;
  assign table_795 = 12'h901;
  assign table_796 = 12'h900;
  assign table_797 = 12'h8ff;
  assign table_798 = 12'h8fd;
  assign table_799 = 12'h8fc;
  assign table_800 = 12'h8fb;
  assign table_801 = 12'h8fa;
  assign table_802 = 12'h8f8;
  assign table_803 = 12'h8f7;
  assign table_804 = 12'h8f6;
  assign table_805 = 12'h8f5;
  assign table_806 = 12'h8f3;
  assign table_807 = 12'h8f2;
  assign table_808 = 12'h8f1;
  assign table_809 = 12'h8f0;
  assign table_810 = 12'h8ee;
  assign table_811 = 12'h8ed;
  assign table_812 = 12'h8ec;
  assign table_813 = 12'h8eb;
  assign table_814 = 12'h8e9;
  assign table_815 = 12'h8e8;
  assign table_816 = 12'h8e7;
  assign table_817 = 12'h8e6;
  assign table_818 = 12'h8e4;
  assign table_819 = 12'h8e3;
  assign table_820 = 12'h8e2;
  assign table_821 = 12'h8e1;
  assign table_822 = 12'h8df;
  assign table_823 = 12'h8de;
  assign table_824 = 12'h8dd;
  assign table_825 = 12'h8dc;
  assign table_826 = 12'h8db;
  assign table_827 = 12'h8d9;
  assign table_828 = 12'h8d8;
  assign table_829 = 12'h8d7;
  assign table_830 = 12'h8d6;
  assign table_831 = 12'h8d4;
  assign table_832 = 12'h8d3;
  assign table_833 = 12'h8d2;
  assign table_834 = 12'h8d1;
  assign table_835 = 12'h8d0;
  assign table_836 = 12'h8ce;
  assign table_837 = 12'h8cd;
  assign table_838 = 12'h8cc;
  assign table_839 = 12'h8cb;
  assign table_840 = 12'h8ca;
  assign table_841 = 12'h8c8;
  assign table_842 = 12'h8c7;
  assign table_843 = 12'h8c6;
  assign table_844 = 12'h8c5;
  assign table_845 = 12'h8c4;
  assign table_846 = 12'h8c2;
  assign table_847 = 12'h8c1;
  assign table_848 = 12'h8c0;
  assign table_849 = 12'h8bf;
  assign table_850 = 12'h8be;
  assign table_851 = 12'h8bc;
  assign table_852 = 12'h8bb;
  assign table_853 = 12'h8ba;
  assign table_854 = 12'h8b9;
  assign table_855 = 12'h8b8;
  assign table_856 = 12'h8b6;
  assign table_857 = 12'h8b5;
  assign table_858 = 12'h8b4;
  assign table_859 = 12'h8b3;
  assign table_860 = 12'h8b2;
  assign table_861 = 12'h8b1;
  assign table_862 = 12'h8af;
  assign table_863 = 12'h8ae;
  assign table_864 = 12'h8ad;
  assign table_865 = 12'h8ac;
  assign table_866 = 12'h8ab;
  assign table_867 = 12'h8a9;
  assign table_868 = 12'h8a8;
  assign table_869 = 12'h8a7;
  assign table_870 = 12'h8a6;
  assign table_871 = 12'h8a5;
  assign table_872 = 12'h8a4;
  assign table_873 = 12'h8a2;
  assign table_874 = 12'h8a1;
  assign table_875 = 12'h8a0;
  assign table_876 = 12'h89f;
  assign table_877 = 12'h89e;
  assign table_878 = 12'h89d;
  assign table_879 = 12'h89b;
  assign table_880 = 12'h89a;
  assign table_881 = 12'h899;
  assign table_882 = 12'h898;
  assign table_883 = 12'h897;
  assign table_884 = 12'h896;
  assign table_885 = 12'h895;
  assign table_886 = 12'h893;
  assign table_887 = 12'h892;
  assign table_888 = 12'h891;
  assign table_889 = 12'h890;
  assign table_890 = 12'h88f;
  assign table_891 = 12'h88e;
  assign table_892 = 12'h88d;
  assign table_893 = 12'h88b;
  assign table_894 = 12'h88a;
  assign table_895 = 12'h889;
  assign table_896 = 12'h888;
  assign table_897 = 12'h887;
  assign table_898 = 12'h886;
  assign table_899 = 12'h885;
  assign table_900 = 12'h883;
  assign table_901 = 12'h882;
  assign table_902 = 12'h881;
  assign table_903 = 12'h880;
  assign table_904 = 12'h87f;
  assign table_905 = 12'h87e;
  assign table_906 = 12'h87d;
  assign table_907 = 12'h87c;
  assign table_908 = 12'h87a;
  assign table_909 = 12'h879;
  assign table_910 = 12'h878;
  assign table_911 = 12'h877;
  assign table_912 = 12'h876;
  assign table_913 = 12'h875;
  assign table_914 = 12'h874;
  assign table_915 = 12'h873;
  assign table_916 = 12'h871;
  assign table_917 = 12'h870;
  assign table_918 = 12'h86f;
  assign table_919 = 12'h86e;
  assign table_920 = 12'h86d;
  assign table_921 = 12'h86c;
  assign table_922 = 12'h86b;
  assign table_923 = 12'h86a;
  assign table_924 = 12'h869;
  assign table_925 = 12'h867;
  assign table_926 = 12'h866;
  assign table_927 = 12'h865;
  assign table_928 = 12'h864;
  assign table_929 = 12'h863;
  assign table_930 = 12'h862;
  assign table_931 = 12'h861;
  assign table_932 = 12'h860;
  assign table_933 = 12'h85f;
  assign table_934 = 12'h85e;
  assign table_935 = 12'h85c;
  assign table_936 = 12'h85b;
  assign table_937 = 12'h85a;
  assign table_938 = 12'h859;
  assign table_939 = 12'h858;
  assign table_940 = 12'h857;
  assign table_941 = 12'h856;
  assign table_942 = 12'h855;
  assign table_943 = 12'h854;
  assign table_944 = 12'h853;
  assign table_945 = 12'h852;
  assign table_946 = 12'h851;
  assign table_947 = 12'h84f;
  assign table_948 = 12'h84e;
  assign table_949 = 12'h84d;
  assign table_950 = 12'h84c;
  assign table_951 = 12'h84b;
  assign table_952 = 12'h84a;
  assign table_953 = 12'h849;
  assign table_954 = 12'h848;
  assign table_955 = 12'h847;
  assign table_956 = 12'h846;
  assign table_957 = 12'h845;
  assign table_958 = 12'h844;
  assign table_959 = 12'h843;
  assign table_960 = 12'h842;
  assign table_961 = 12'h840;
  assign table_962 = 12'h83f;
  assign table_963 = 12'h83e;
  assign table_964 = 12'h83d;
  assign table_965 = 12'h83c;
  assign table_966 = 12'h83b;
  assign table_967 = 12'h83a;
  assign table_968 = 12'h839;
  assign table_969 = 12'h838;
  assign table_970 = 12'h837;
  assign table_971 = 12'h836;
  assign table_972 = 12'h835;
  assign table_973 = 12'h834;
  assign table_974 = 12'h833;
  assign table_975 = 12'h832;
  assign table_976 = 12'h831;
  assign table_977 = 12'h830;
  assign table_978 = 12'h82f;
  assign table_979 = 12'h82d;
  assign table_980 = 12'h82c;
  assign table_981 = 12'h82b;
  assign table_982 = 12'h82a;
  assign table_983 = 12'h829;
  assign table_984 = 12'h828;
  assign table_985 = 12'h827;
  assign table_986 = 12'h826;
  assign table_987 = 12'h825;
  assign table_988 = 12'h824;
  assign table_989 = 12'h823;
  assign table_990 = 12'h822;
  assign table_991 = 12'h821;
  assign table_992 = 12'h820;
  assign table_993 = 12'h81f;
  assign table_994 = 12'h81e;
  assign table_995 = 12'h81d;
  assign table_996 = 12'h81c;
  assign table_997 = 12'h81b;
  assign table_998 = 12'h81a;
  assign table_999 = 12'h819;
  assign table_1000 = 12'h818;
  assign table_1001 = 12'h817;
  assign table_1002 = 12'h816;
  assign table_1003 = 12'h815;
  assign table_1004 = 12'h814;
  assign table_1005 = 12'h813;
  assign table_1006 = 12'h812;
  assign table_1007 = 12'h811;
  assign table_1008 = 12'h810;
  assign table_1009 = 12'h80f;
  assign table_1010 = 12'h80e;
  assign table_1011 = 12'h80d;
  assign table_1012 = 12'h80c;
  assign table_1013 = 12'h80b;
  assign table_1014 = 12'h80a;
  assign table_1015 = 12'h809;
  assign table_1016 = 12'h808;
  assign table_1017 = 12'h807;
  assign table_1018 = 12'h806;
  assign table_1019 = 12'h805;
  assign table_1020 = 12'h804;
  assign table_1021 = 12'h803;
  assign table_1022 = 12'h802;
  assign table_1023 = 12'h801;
  assign _zz_io_i_map_payload_wu = ($signed(io_i_payload_p_v_1) <= $signed(34'h0));
  assign _zz_io_i_map_payload_e = io_i_payload_p_v_1;
  always @(*) begin
    _zz_io_i_map_payload_e_1[0] = _zz_io_i_map_payload_e[33];
    _zz_io_i_map_payload_e_1[1] = _zz_io_i_map_payload_e[32];
    _zz_io_i_map_payload_e_1[2] = _zz_io_i_map_payload_e[31];
    _zz_io_i_map_payload_e_1[3] = _zz_io_i_map_payload_e[30];
    _zz_io_i_map_payload_e_1[4] = _zz_io_i_map_payload_e[29];
    _zz_io_i_map_payload_e_1[5] = _zz_io_i_map_payload_e[28];
    _zz_io_i_map_payload_e_1[6] = _zz_io_i_map_payload_e[27];
    _zz_io_i_map_payload_e_1[7] = _zz_io_i_map_payload_e[26];
    _zz_io_i_map_payload_e_1[8] = _zz_io_i_map_payload_e[25];
    _zz_io_i_map_payload_e_1[9] = _zz_io_i_map_payload_e[24];
    _zz_io_i_map_payload_e_1[10] = _zz_io_i_map_payload_e[23];
    _zz_io_i_map_payload_e_1[11] = _zz_io_i_map_payload_e[22];
    _zz_io_i_map_payload_e_1[12] = _zz_io_i_map_payload_e[21];
    _zz_io_i_map_payload_e_1[13] = _zz_io_i_map_payload_e[20];
    _zz_io_i_map_payload_e_1[14] = _zz_io_i_map_payload_e[19];
    _zz_io_i_map_payload_e_1[15] = _zz_io_i_map_payload_e[18];
    _zz_io_i_map_payload_e_1[16] = _zz_io_i_map_payload_e[17];
    _zz_io_i_map_payload_e_1[17] = _zz_io_i_map_payload_e[16];
    _zz_io_i_map_payload_e_1[18] = _zz_io_i_map_payload_e[15];
    _zz_io_i_map_payload_e_1[19] = _zz_io_i_map_payload_e[14];
    _zz_io_i_map_payload_e_1[20] = _zz_io_i_map_payload_e[13];
    _zz_io_i_map_payload_e_1[21] = _zz_io_i_map_payload_e[12];
    _zz_io_i_map_payload_e_1[22] = _zz_io_i_map_payload_e[11];
    _zz_io_i_map_payload_e_1[23] = _zz_io_i_map_payload_e[10];
    _zz_io_i_map_payload_e_1[24] = _zz_io_i_map_payload_e[9];
    _zz_io_i_map_payload_e_1[25] = _zz_io_i_map_payload_e[8];
    _zz_io_i_map_payload_e_1[26] = _zz_io_i_map_payload_e[7];
    _zz_io_i_map_payload_e_1[27] = _zz_io_i_map_payload_e[6];
    _zz_io_i_map_payload_e_1[28] = _zz_io_i_map_payload_e[5];
    _zz_io_i_map_payload_e_1[29] = _zz_io_i_map_payload_e[4];
    _zz_io_i_map_payload_e_1[30] = _zz_io_i_map_payload_e[3];
    _zz_io_i_map_payload_e_1[31] = _zz_io_i_map_payload_e[2];
    _zz_io_i_map_payload_e_1[32] = _zz_io_i_map_payload_e[1];
    _zz_io_i_map_payload_e_1[33] = _zz_io_i_map_payload_e[0];
  end

  assign _zz_io_i_map_payload_e_3 = (_zz_io_i_map_payload_e_1 & (~ _zz__zz_io_i_map_payload_e_3));
  always @(*) begin
    _zz_io_i_map_payload_e_4[0] = _zz_io_i_map_payload_e_3[33];
    _zz_io_i_map_payload_e_4[1] = _zz_io_i_map_payload_e_3[32];
    _zz_io_i_map_payload_e_4[2] = _zz_io_i_map_payload_e_3[31];
    _zz_io_i_map_payload_e_4[3] = _zz_io_i_map_payload_e_3[30];
    _zz_io_i_map_payload_e_4[4] = _zz_io_i_map_payload_e_3[29];
    _zz_io_i_map_payload_e_4[5] = _zz_io_i_map_payload_e_3[28];
    _zz_io_i_map_payload_e_4[6] = _zz_io_i_map_payload_e_3[27];
    _zz_io_i_map_payload_e_4[7] = _zz_io_i_map_payload_e_3[26];
    _zz_io_i_map_payload_e_4[8] = _zz_io_i_map_payload_e_3[25];
    _zz_io_i_map_payload_e_4[9] = _zz_io_i_map_payload_e_3[24];
    _zz_io_i_map_payload_e_4[10] = _zz_io_i_map_payload_e_3[23];
    _zz_io_i_map_payload_e_4[11] = _zz_io_i_map_payload_e_3[22];
    _zz_io_i_map_payload_e_4[12] = _zz_io_i_map_payload_e_3[21];
    _zz_io_i_map_payload_e_4[13] = _zz_io_i_map_payload_e_3[20];
    _zz_io_i_map_payload_e_4[14] = _zz_io_i_map_payload_e_3[19];
    _zz_io_i_map_payload_e_4[15] = _zz_io_i_map_payload_e_3[18];
    _zz_io_i_map_payload_e_4[16] = _zz_io_i_map_payload_e_3[17];
    _zz_io_i_map_payload_e_4[17] = _zz_io_i_map_payload_e_3[16];
    _zz_io_i_map_payload_e_4[18] = _zz_io_i_map_payload_e_3[15];
    _zz_io_i_map_payload_e_4[19] = _zz_io_i_map_payload_e_3[14];
    _zz_io_i_map_payload_e_4[20] = _zz_io_i_map_payload_e_3[13];
    _zz_io_i_map_payload_e_4[21] = _zz_io_i_map_payload_e_3[12];
    _zz_io_i_map_payload_e_4[22] = _zz_io_i_map_payload_e_3[11];
    _zz_io_i_map_payload_e_4[23] = _zz_io_i_map_payload_e_3[10];
    _zz_io_i_map_payload_e_4[24] = _zz_io_i_map_payload_e_3[9];
    _zz_io_i_map_payload_e_4[25] = _zz_io_i_map_payload_e_3[8];
    _zz_io_i_map_payload_e_4[26] = _zz_io_i_map_payload_e_3[7];
    _zz_io_i_map_payload_e_4[27] = _zz_io_i_map_payload_e_3[6];
    _zz_io_i_map_payload_e_4[28] = _zz_io_i_map_payload_e_3[5];
    _zz_io_i_map_payload_e_4[29] = _zz_io_i_map_payload_e_3[4];
    _zz_io_i_map_payload_e_4[30] = _zz_io_i_map_payload_e_3[3];
    _zz_io_i_map_payload_e_4[31] = _zz_io_i_map_payload_e_3[2];
    _zz_io_i_map_payload_e_4[32] = _zz_io_i_map_payload_e_3[1];
    _zz_io_i_map_payload_e_4[33] = _zz_io_i_map_payload_e_3[0];
  end

  assign _zz_io_i_map_payload_e_2 = _zz_io_i_map_payload_e_4;
  assign _zz_io_i_map_payload_e_5 = _zz_io_i_map_payload_e_2[3];
  assign _zz_io_i_map_payload_e_6 = _zz_io_i_map_payload_e_2[5];
  assign _zz_io_i_map_payload_e_7 = _zz_io_i_map_payload_e_2[6];
  assign _zz_io_i_map_payload_e_8 = _zz_io_i_map_payload_e_2[7];
  assign _zz_io_i_map_payload_e_9 = _zz_io_i_map_payload_e_2[9];
  assign _zz_io_i_map_payload_e_10 = _zz_io_i_map_payload_e_2[10];
  assign _zz_io_i_map_payload_e_11 = _zz_io_i_map_payload_e_2[11];
  assign _zz_io_i_map_payload_e_12 = _zz_io_i_map_payload_e_2[12];
  assign _zz_io_i_map_payload_e_13 = _zz_io_i_map_payload_e_2[13];
  assign _zz_io_i_map_payload_e_14 = _zz_io_i_map_payload_e_2[14];
  assign _zz_io_i_map_payload_e_15 = _zz_io_i_map_payload_e_2[15];
  assign _zz_io_i_map_payload_e_16 = _zz_io_i_map_payload_e_2[17];
  assign _zz_io_i_map_payload_e_17 = _zz_io_i_map_payload_e_2[18];
  assign _zz_io_i_map_payload_e_18 = _zz_io_i_map_payload_e_2[19];
  assign _zz_io_i_map_payload_e_19 = _zz_io_i_map_payload_e_2[20];
  assign _zz_io_i_map_payload_e_20 = _zz_io_i_map_payload_e_2[21];
  assign _zz_io_i_map_payload_e_21 = _zz_io_i_map_payload_e_2[22];
  assign _zz_io_i_map_payload_e_22 = _zz_io_i_map_payload_e_2[23];
  assign _zz_io_i_map_payload_e_23 = _zz_io_i_map_payload_e_2[24];
  assign _zz_io_i_map_payload_e_24 = _zz_io_i_map_payload_e_2[25];
  assign _zz_io_i_map_payload_e_25 = _zz_io_i_map_payload_e_2[26];
  assign _zz_io_i_map_payload_e_26 = _zz_io_i_map_payload_e_2[27];
  assign _zz_io_i_map_payload_e_27 = _zz_io_i_map_payload_e_2[28];
  assign _zz_io_i_map_payload_e_28 = _zz_io_i_map_payload_e_2[29];
  assign _zz_io_i_map_payload_e_29 = _zz_io_i_map_payload_e_2[30];
  assign _zz_io_i_map_payload_e_30 = _zz_io_i_map_payload_e_2[31];
  assign _zz_io_i_map_payload_e_31 = _zz_io_i_map_payload_e_2[33];
  assign _zz_io_i_map_payload_e_32 = ((((((((((((((((_zz__zz_io_i_map_payload_e_32 || _zz_io_i_map_payload_e_5) || _zz_io_i_map_payload_e_6) || _zz_io_i_map_payload_e_8) || _zz_io_i_map_payload_e_9) || _zz_io_i_map_payload_e_11) || _zz_io_i_map_payload_e_13) || _zz_io_i_map_payload_e_15) || _zz_io_i_map_payload_e_16) || _zz_io_i_map_payload_e_18) || _zz_io_i_map_payload_e_20) || _zz_io_i_map_payload_e_22) || _zz_io_i_map_payload_e_24) || _zz_io_i_map_payload_e_26) || _zz_io_i_map_payload_e_28) || _zz_io_i_map_payload_e_30) || _zz_io_i_map_payload_e_31);
  assign _zz_io_i_map_payload_e_33 = (((((((((((((((_zz_io_i_map_payload_e_2[2] || _zz_io_i_map_payload_e_5) || _zz_io_i_map_payload_e_7) || _zz_io_i_map_payload_e_8) || _zz_io_i_map_payload_e_10) || _zz_io_i_map_payload_e_11) || _zz_io_i_map_payload_e_14) || _zz_io_i_map_payload_e_15) || _zz_io_i_map_payload_e_17) || _zz_io_i_map_payload_e_18) || _zz_io_i_map_payload_e_21) || _zz_io_i_map_payload_e_22) || _zz_io_i_map_payload_e_25) || _zz_io_i_map_payload_e_26) || _zz_io_i_map_payload_e_29) || _zz_io_i_map_payload_e_30);
  assign _zz_io_i_map_payload_e_34 = (((((((((((((((_zz_io_i_map_payload_e_2[4] || _zz_io_i_map_payload_e_6) || _zz_io_i_map_payload_e_7) || _zz_io_i_map_payload_e_8) || _zz_io_i_map_payload_e_12) || _zz_io_i_map_payload_e_13) || _zz_io_i_map_payload_e_14) || _zz_io_i_map_payload_e_15) || _zz_io_i_map_payload_e_19) || _zz_io_i_map_payload_e_20) || _zz_io_i_map_payload_e_21) || _zz_io_i_map_payload_e_22) || _zz_io_i_map_payload_e_27) || _zz_io_i_map_payload_e_28) || _zz_io_i_map_payload_e_29) || _zz_io_i_map_payload_e_30);
  assign _zz_io_i_map_payload_e_35 = (((((((((((((((_zz_io_i_map_payload_e_2[8] || _zz_io_i_map_payload_e_9) || _zz_io_i_map_payload_e_10) || _zz_io_i_map_payload_e_11) || _zz_io_i_map_payload_e_12) || _zz_io_i_map_payload_e_13) || _zz_io_i_map_payload_e_14) || _zz_io_i_map_payload_e_15) || _zz_io_i_map_payload_e_23) || _zz_io_i_map_payload_e_24) || _zz_io_i_map_payload_e_25) || _zz_io_i_map_payload_e_26) || _zz_io_i_map_payload_e_27) || _zz_io_i_map_payload_e_28) || _zz_io_i_map_payload_e_29) || _zz_io_i_map_payload_e_30);
  assign _zz_io_i_map_payload_e_36 = (((((((((((((((_zz_io_i_map_payload_e_2[16] || _zz_io_i_map_payload_e_16) || _zz_io_i_map_payload_e_17) || _zz_io_i_map_payload_e_18) || _zz_io_i_map_payload_e_19) || _zz_io_i_map_payload_e_20) || _zz_io_i_map_payload_e_21) || _zz_io_i_map_payload_e_22) || _zz_io_i_map_payload_e_23) || _zz_io_i_map_payload_e_24) || _zz_io_i_map_payload_e_25) || _zz_io_i_map_payload_e_26) || _zz_io_i_map_payload_e_27) || _zz_io_i_map_payload_e_28) || _zz_io_i_map_payload_e_29) || _zz_io_i_map_payload_e_30);
  assign _zz_io_i_map_payload_e_37 = (_zz_io_i_map_payload_e_2[32] || _zz_io_i_map_payload_e_31);
  assign io_i_map_valid = io_i_valid;
  assign io_i_ready = io_i_map_ready;
  assign io_i_map_payload_px_x = io_i_payload_x;
  assign io_i_map_payload_px_y = io_i_payload_y;
  assign io_i_map_payload_px_p_v_0 = io_i_payload_p_v_0;
  assign io_i_map_payload_px_p_v_1 = io_i_payload_p_v_1;
  assign io_i_map_payload_px_p_v_2 = io_i_payload_p_v_2;
  assign io_i_map_payload_px_p_v_3 = io_i_payload_p_v_3;
  assign io_i_map_payload_px_p_v_4 = io_i_payload_p_v_4;
  assign io_i_map_payload_px_attr = io_i_payload_attr;
  assign io_i_map_payload_wu = (_zz_io_i_map_payload_wu ? 34'h000000001 : io_i_payload_p_v_1);
  assign io_i_map_payload_e = (_zz_io_i_map_payload_wu ? 6'h0 : {_zz_io_i_map_payload_e_37,{_zz_io_i_map_payload_e_36,{_zz_io_i_map_payload_e_35,{_zz_io_i_map_payload_e_34,{_zz_io_i_map_payload_e_33,_zz_io_i_map_payload_e_32}}}}});
  always @(*) begin
    io_i_map_ready = a0_ready;
    if(when_Stream_l477) begin
      io_i_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! a0_valid);
  assign a0_valid = io_i_map_rValid;
  assign a0_payload_px_x = io_i_map_rData_px_x;
  assign a0_payload_px_y = io_i_map_rData_px_y;
  assign a0_payload_px_p_v_0 = io_i_map_rData_px_p_v_0;
  assign a0_payload_px_p_v_1 = io_i_map_rData_px_p_v_1;
  assign a0_payload_px_p_v_2 = io_i_map_rData_px_p_v_2;
  assign a0_payload_px_p_v_3 = io_i_map_rData_px_p_v_3;
  assign a0_payload_px_p_v_4 = io_i_map_rData_px_p_v_4;
  assign a0_payload_px_attr = io_i_map_rData_px_attr;
  assign a0_payload_wu = io_i_map_rData_wu;
  assign a0_payload_e = io_i_map_rData_e;
  assign a0_map_valid = a0_valid;
  assign a0_ready = a0_map_ready;
  assign a0_map_payload_px_x = a0_payload_px_x;
  assign a0_map_payload_px_y = a0_payload_px_y;
  assign a0_map_payload_px_p_v_0 = a0_payload_px_p_v_0;
  assign a0_map_payload_px_p_v_1 = a0_payload_px_p_v_1;
  assign a0_map_payload_px_p_v_2 = a0_payload_px_p_v_2;
  assign a0_map_payload_px_p_v_3 = a0_payload_px_p_v_3;
  assign a0_map_payload_px_p_v_4 = a0_payload_px_p_v_4;
  assign a0_map_payload_px_attr = a0_payload_px_attr;
  assign a0_map_payload_e = a0_payload_e;
  assign a0_map_payload_wn = _zz_a0_map_payload_wn[33 : 13];
  always @(*) begin
    a0_map_ready = a_ready;
    if(when_Stream_l477_1) begin
      a0_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_1 = (! a_valid);
  assign a_valid = a0_map_rValid;
  assign a_payload_px_x = a0_map_rData_px_x;
  assign a_payload_px_y = a0_map_rData_px_y;
  assign a_payload_px_p_v_0 = a0_map_rData_px_p_v_0;
  assign a_payload_px_p_v_1 = a0_map_rData_px_p_v_1;
  assign a_payload_px_p_v_2 = a0_map_rData_px_p_v_2;
  assign a_payload_px_p_v_3 = a0_map_rData_px_p_v_3;
  assign a_payload_px_p_v_4 = a0_map_rData_px_p_v_4;
  assign a_payload_px_attr = a0_map_rData_px_attr;
  assign a_payload_e = a0_map_rData_e;
  assign a_payload_wn = a0_map_rData_wn;
  assign a_translated_valid = a_valid;
  assign a_ready = a_translated_ready;
  assign a_translated_payload = a_payload_wn[19 : 10];
  assign a_translated_fire = (a_translated_valid && a_translated_ready);
  assign b_isFree = ((! b_valid) || b_ready);
  assign a_translated_ready = b_isFree;
  assign b_valid = _zz_b_valid;
  assign b_payload_value = rom_spinal_port0;
  assign b_payload_linked_px_x = a_payload_regNextWhen_px_x;
  assign b_payload_linked_px_y = a_payload_regNextWhen_px_y;
  assign b_payload_linked_px_p_v_0 = a_payload_regNextWhen_px_p_v_0;
  assign b_payload_linked_px_p_v_1 = a_payload_regNextWhen_px_p_v_1;
  assign b_payload_linked_px_p_v_2 = a_payload_regNextWhen_px_p_v_2;
  assign b_payload_linked_px_p_v_3 = a_payload_regNextWhen_px_p_v_3;
  assign b_payload_linked_px_p_v_4 = a_payload_regNextWhen_px_p_v_4;
  assign b_payload_linked_px_attr = a_payload_regNextWhen_px_attr;
  assign b_payload_linked_e = a_payload_regNextWhen_e;
  assign b_payload_linked_wn = a_payload_regNextWhen_wn;
  assign b_map_valid = b_valid;
  assign b_ready = b_map_ready;
  assign b_map_payload_a_px_x = b_payload_linked_px_x;
  assign b_map_payload_a_px_y = b_payload_linked_px_y;
  assign b_map_payload_a_px_p_v_0 = b_payload_linked_px_p_v_0;
  assign b_map_payload_a_px_p_v_1 = b_payload_linked_px_p_v_1;
  assign b_map_payload_a_px_p_v_2 = b_payload_linked_px_p_v_2;
  assign b_map_payload_a_px_p_v_3 = b_payload_linked_px_p_v_3;
  assign b_map_payload_a_px_p_v_4 = b_payload_linked_px_p_v_4;
  assign b_map_payload_a_px_attr = b_payload_linked_px_attr;
  assign b_map_payload_a_e = b_payload_linked_e;
  assign b_map_payload_a_wn = b_payload_linked_wn;
  assign b_map_payload_y0 = b_payload_value;
  assign b_map_payload_corr = {1'd0, _zz_b_map_payload_corr};
  always @(*) begin
    b_map_ready = c0_ready;
    if(when_Stream_l477_2) begin
      b_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_2 = (! c0_valid);
  assign c0_valid = b_map_rValid;
  assign c0_payload_a_px_x = b_map_rData_a_px_x;
  assign c0_payload_a_px_y = b_map_rData_a_px_y;
  assign c0_payload_a_px_p_v_0 = b_map_rData_a_px_p_v_0;
  assign c0_payload_a_px_p_v_1 = b_map_rData_a_px_p_v_1;
  assign c0_payload_a_px_p_v_2 = b_map_rData_a_px_p_v_2;
  assign c0_payload_a_px_p_v_3 = b_map_rData_a_px_p_v_3;
  assign c0_payload_a_px_p_v_4 = b_map_rData_a_px_p_v_4;
  assign c0_payload_a_px_attr = b_map_rData_a_px_attr;
  assign c0_payload_a_e = b_map_rData_a_e;
  assign c0_payload_a_wn = b_map_rData_a_wn;
  assign c0_payload_y0 = b_map_rData_y0;
  assign c0_payload_corr = b_map_rData_corr;
  assign c0_map_valid = c0_valid;
  assign c0_ready = c0_map_ready;
  assign c0_map_payload_a_px_x = c0_payload_a_px_x;
  assign c0_map_payload_a_px_y = c0_payload_a_px_y;
  assign c0_map_payload_a_px_p_v_0 = c0_payload_a_px_p_v_0;
  assign c0_map_payload_a_px_p_v_1 = c0_payload_a_px_p_v_1;
  assign c0_map_payload_a_px_p_v_2 = c0_payload_a_px_p_v_2;
  assign c0_map_payload_a_px_p_v_3 = c0_payload_a_px_p_v_3;
  assign c0_map_payload_a_px_p_v_4 = c0_payload_a_px_p_v_4;
  assign c0_map_payload_a_px_attr = c0_payload_a_px_attr;
  assign c0_map_payload_a_e = c0_payload_a_e;
  assign c0_map_payload_a_wn = c0_payload_a_wn;
  assign c0_map_payload_y0 = c0_payload_y0;
  assign c0_map_payload_corr = (34'h200000000 - c0_payload_corr);
  always @(*) begin
    c0_map_ready = cS_ready;
    if(when_Stream_l477_3) begin
      c0_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_3 = (! cS_valid);
  assign cS_valid = c0_map_rValid;
  assign cS_payload_a_px_x = c0_map_rData_a_px_x;
  assign cS_payload_a_px_y = c0_map_rData_a_px_y;
  assign cS_payload_a_px_p_v_0 = c0_map_rData_a_px_p_v_0;
  assign cS_payload_a_px_p_v_1 = c0_map_rData_a_px_p_v_1;
  assign cS_payload_a_px_p_v_2 = c0_map_rData_a_px_p_v_2;
  assign cS_payload_a_px_p_v_3 = c0_map_rData_a_px_p_v_3;
  assign cS_payload_a_px_p_v_4 = c0_map_rData_a_px_p_v_4;
  assign cS_payload_a_px_attr = c0_map_rData_a_px_attr;
  assign cS_payload_a_e = c0_map_rData_a_e;
  assign cS_payload_a_wn = c0_map_rData_a_wn;
  assign cS_payload_y0 = c0_map_rData_y0;
  assign cS_payload_corr = c0_map_rData_corr;
  assign cS_map_valid = cS_valid;
  assign cS_ready = cS_map_ready;
  assign cS_map_payload_a_px_x = cS_payload_a_px_x;
  assign cS_map_payload_a_px_y = cS_payload_a_px_y;
  assign cS_map_payload_a_px_p_v_0 = cS_payload_a_px_p_v_0;
  assign cS_map_payload_a_px_p_v_1 = cS_payload_a_px_p_v_1;
  assign cS_map_payload_a_px_p_v_2 = cS_payload_a_px_p_v_2;
  assign cS_map_payload_a_px_p_v_3 = cS_payload_a_px_p_v_3;
  assign cS_map_payload_a_px_p_v_4 = cS_payload_a_px_p_v_4;
  assign cS_map_payload_a_px_attr = cS_payload_a_px_attr;
  assign cS_map_payload_a_e = cS_payload_a_e;
  assign cS_map_payload_a_wn = cS_payload_a_wn;
  assign cS_map_payload_y1 = _zz_cS_map_payload_y1[21:0];
  always @(*) begin
    cS_map_ready = d_ready;
    if(when_Stream_l477_4) begin
      cS_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_4 = (! d_valid);
  assign d_valid = cS_map_rValid;
  assign d_payload_a_px_x = cS_map_rData_a_px_x;
  assign d_payload_a_px_y = cS_map_rData_a_px_y;
  assign d_payload_a_px_p_v_0 = cS_map_rData_a_px_p_v_0;
  assign d_payload_a_px_p_v_1 = cS_map_rData_a_px_p_v_1;
  assign d_payload_a_px_p_v_2 = cS_map_rData_a_px_p_v_2;
  assign d_payload_a_px_p_v_3 = cS_map_rData_a_px_p_v_3;
  assign d_payload_a_px_p_v_4 = cS_map_rData_a_px_p_v_4;
  assign d_payload_a_px_attr = cS_map_rData_a_px_attr;
  assign d_payload_a_e = cS_map_rData_a_e;
  assign d_payload_a_wn = cS_map_rData_a_wn;
  assign d_payload_y1 = cS_map_rData_y1;
  assign d_map_valid = d_valid;
  assign d_ready = d_map_ready;
  assign d_map_payload_a_px_x = d_payload_a_px_x;
  assign d_map_payload_a_px_y = d_payload_a_px_y;
  assign d_map_payload_a_px_p_v_0 = d_payload_a_px_p_v_0;
  assign d_map_payload_a_px_p_v_1 = d_payload_a_px_p_v_1;
  assign d_map_payload_a_px_p_v_2 = d_payload_a_px_p_v_2;
  assign d_map_payload_a_px_p_v_3 = d_payload_a_px_p_v_3;
  assign d_map_payload_a_px_p_v_4 = d_payload_a_px_p_v_4;
  assign d_map_payload_a_px_attr = d_payload_a_px_attr;
  assign d_map_payload_a_e = d_payload_a_e;
  assign d_map_payload_a_wn = d_payload_a_wn;
  assign d_map_payload_y1 = d_payload_y1;
  assign d_map_payload_sNeg = d_payload_a_px_p_v_3[31];
  assign d_map_payload_tNeg = d_payload_a_px_p_v_4[31];
  assign d_map_payload_lNeg = d_payload_a_px_p_v_2[23];
  assign d_map_payload_sa = (_zz_d_map_payload_sa + _zz_d_map_payload_sa_2);
  assign d_map_payload_ta = (_zz_d_map_payload_ta + _zz_d_map_payload_ta_2);
  assign d_map_payload_la = (_zz_d_map_payload_la + _zz_d_map_payload_la_2);
  always @(*) begin
    d_map_ready = e0_ready;
    if(when_Stream_l477_5) begin
      d_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_5 = (! e0_valid);
  assign e0_valid = d_map_rValid;
  assign e0_payload_a_px_x = d_map_rData_a_px_x;
  assign e0_payload_a_px_y = d_map_rData_a_px_y;
  assign e0_payload_a_px_p_v_0 = d_map_rData_a_px_p_v_0;
  assign e0_payload_a_px_p_v_1 = d_map_rData_a_px_p_v_1;
  assign e0_payload_a_px_p_v_2 = d_map_rData_a_px_p_v_2;
  assign e0_payload_a_px_p_v_3 = d_map_rData_a_px_p_v_3;
  assign e0_payload_a_px_p_v_4 = d_map_rData_a_px_p_v_4;
  assign e0_payload_a_px_attr = d_map_rData_a_px_attr;
  assign e0_payload_a_e = d_map_rData_a_e;
  assign e0_payload_a_wn = d_map_rData_a_wn;
  assign e0_payload_y1 = d_map_rData_y1;
  assign e0_payload_sNeg = d_map_rData_sNeg;
  assign e0_payload_tNeg = d_map_rData_tNeg;
  assign e0_payload_lNeg = d_map_rData_lNeg;
  assign e0_payload_sa = d_map_rData_sa;
  assign e0_payload_ta = d_map_rData_ta;
  assign e0_payload_la = d_map_rData_la;
  assign e0_map_valid = e0_valid;
  assign e0_ready = e0_map_ready;
  assign e0_map_payload_a_px_x = e0_payload_a_px_x;
  assign e0_map_payload_a_px_y = e0_payload_a_px_y;
  assign e0_map_payload_a_px_p_v_0 = e0_payload_a_px_p_v_0;
  assign e0_map_payload_a_px_p_v_1 = e0_payload_a_px_p_v_1;
  assign e0_map_payload_a_px_p_v_2 = e0_payload_a_px_p_v_2;
  assign e0_map_payload_a_px_p_v_3 = e0_payload_a_px_p_v_3;
  assign e0_map_payload_a_px_p_v_4 = e0_payload_a_px_p_v_4;
  assign e0_map_payload_a_px_attr = e0_payload_a_px_attr;
  assign e0_map_payload_a_e = e0_payload_a_e;
  assign e0_map_payload_a_wn = e0_payload_a_wn;
  assign e0_map_payload_sNeg = e0_payload_sNeg;
  assign e0_map_payload_tNeg = e0_payload_tNeg;
  assign e0_map_payload_lNeg = e0_payload_lNeg;
  assign e0_map_payload_ps = (e0_payload_sa * e0_payload_y1);
  assign e0_map_payload_pt = (e0_payload_ta * e0_payload_y1);
  assign e0_map_payload_pl = (e0_payload_la * e0_payload_y1);
  always @(*) begin
    e0_map_ready = e_ready;
    if(when_Stream_l477_6) begin
      e0_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_6 = (! e_valid);
  assign e_valid = e0_map_rValid;
  assign e_payload_a_px_x = e0_map_rData_a_px_x;
  assign e_payload_a_px_y = e0_map_rData_a_px_y;
  assign e_payload_a_px_p_v_0 = e0_map_rData_a_px_p_v_0;
  assign e_payload_a_px_p_v_1 = e0_map_rData_a_px_p_v_1;
  assign e_payload_a_px_p_v_2 = e0_map_rData_a_px_p_v_2;
  assign e_payload_a_px_p_v_3 = e0_map_rData_a_px_p_v_3;
  assign e_payload_a_px_p_v_4 = e0_map_rData_a_px_p_v_4;
  assign e_payload_a_px_attr = e0_map_rData_a_px_attr;
  assign e_payload_a_e = e0_map_rData_a_e;
  assign e_payload_a_wn = e0_map_rData_a_wn;
  assign e_payload_sNeg = e0_map_rData_sNeg;
  assign e_payload_tNeg = e0_map_rData_tNeg;
  assign e_payload_lNeg = e0_map_rData_lNeg;
  assign e_payload_ps = e0_map_rData_ps;
  assign e_payload_pt = e0_map_rData_pt;
  assign e_payload_pl = e0_map_rData_pl;
  assign _zz_e_map_payload_ps = (_zz__zz_e_map_payload_ps + 7'h09);
  assign _zz_e_map_payload_pl = (_zz__zz_e_map_payload_pl + 7'h07);
  assign e_map_valid = e_valid;
  assign e_ready = e_map_ready;
  assign e_map_payload_a_px_x = e_payload_a_px_x;
  assign e_map_payload_a_px_y = e_payload_a_px_y;
  assign e_map_payload_a_px_p_v_0 = e_payload_a_px_p_v_0;
  assign e_map_payload_a_px_p_v_1 = e_payload_a_px_p_v_1;
  assign e_map_payload_a_px_p_v_2 = e_payload_a_px_p_v_2;
  assign e_map_payload_a_px_p_v_3 = e_payload_a_px_p_v_3;
  assign e_map_payload_a_px_p_v_4 = e_payload_a_px_p_v_4;
  assign e_map_payload_a_px_attr = e_payload_a_px_attr;
  assign e_map_payload_a_e = e_payload_a_e;
  assign e_map_payload_a_wn = e_payload_a_wn;
  assign e_map_payload_sNeg = e_payload_sNeg;
  assign e_map_payload_tNeg = e_payload_tNeg;
  assign e_map_payload_lNeg = e_payload_lNeg;
  assign e_map_payload_ps = (e_payload_ps >>> (_zz_e_map_payload_ps & (~ 7'h07)));
  assign e_map_payload_pt = (e_payload_pt >>> (_zz_e_map_payload_ps & (~ 7'h07)));
  assign e_map_payload_pl = (e_payload_pl >>> (_zz_e_map_payload_pl & (~ 7'h07)));
  assign e_map_payload_fineT = _zz_e_map_payload_ps[2 : 0];
  assign e_map_payload_fineL = _zz_e_map_payload_pl[2 : 0];
  always @(*) begin
    e_map_ready = fc_ready;
    if(when_Stream_l477_7) begin
      e_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_7 = (! fc_valid);
  assign fc_valid = e_map_rValid;
  assign fc_payload_a_px_x = e_map_rData_a_px_x;
  assign fc_payload_a_px_y = e_map_rData_a_px_y;
  assign fc_payload_a_px_p_v_0 = e_map_rData_a_px_p_v_0;
  assign fc_payload_a_px_p_v_1 = e_map_rData_a_px_p_v_1;
  assign fc_payload_a_px_p_v_2 = e_map_rData_a_px_p_v_2;
  assign fc_payload_a_px_p_v_3 = e_map_rData_a_px_p_v_3;
  assign fc_payload_a_px_p_v_4 = e_map_rData_a_px_p_v_4;
  assign fc_payload_a_px_attr = e_map_rData_a_px_attr;
  assign fc_payload_a_e = e_map_rData_a_e;
  assign fc_payload_a_wn = e_map_rData_a_wn;
  assign fc_payload_sNeg = e_map_rData_sNeg;
  assign fc_payload_tNeg = e_map_rData_tNeg;
  assign fc_payload_lNeg = e_map_rData_lNeg;
  assign fc_payload_ps = e_map_rData_ps;
  assign fc_payload_pt = e_map_rData_pt;
  assign fc_payload_pl = e_map_rData_pl;
  assign fc_payload_fineT = e_map_rData_fineT;
  assign fc_payload_fineL = e_map_rData_fineL;
  assign fc_map_valid = fc_valid;
  assign fc_ready = fc_map_ready;
  assign fc_map_payload_a_px_x = fc_payload_a_px_x;
  assign fc_map_payload_a_px_y = fc_payload_a_px_y;
  assign fc_map_payload_a_px_p_v_0 = fc_payload_a_px_p_v_0;
  assign fc_map_payload_a_px_p_v_1 = fc_payload_a_px_p_v_1;
  assign fc_map_payload_a_px_p_v_2 = fc_payload_a_px_p_v_2;
  assign fc_map_payload_a_px_p_v_3 = fc_payload_a_px_p_v_3;
  assign fc_map_payload_a_px_p_v_4 = fc_payload_a_px_p_v_4;
  assign fc_map_payload_a_px_attr = fc_payload_a_px_attr;
  assign fc_map_payload_a_e = fc_payload_a_e;
  assign fc_map_payload_a_wn = fc_payload_a_wn;
  assign fc_map_payload_sNeg = fc_payload_sNeg;
  assign fc_map_payload_tNeg = fc_payload_tNeg;
  assign fc_map_payload_lNeg = fc_payload_lNeg;
  assign fc_map_payload_ms = (fc_payload_ps >>> fc_payload_fineT);
  assign fc_map_payload_mt = (fc_payload_pt >>> fc_payload_fineT);
  assign fc_map_payload_ml = _zz_fc_map_payload_ml[7:0];
  always @(*) begin
    fc_map_ready = f0_ready;
    if(when_Stream_l477_8) begin
      fc_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_8 = (! f0_valid);
  assign f0_valid = fc_map_rValid;
  assign f0_payload_a_px_x = fc_map_rData_a_px_x;
  assign f0_payload_a_px_y = fc_map_rData_a_px_y;
  assign f0_payload_a_px_p_v_0 = fc_map_rData_a_px_p_v_0;
  assign f0_payload_a_px_p_v_1 = fc_map_rData_a_px_p_v_1;
  assign f0_payload_a_px_p_v_2 = fc_map_rData_a_px_p_v_2;
  assign f0_payload_a_px_p_v_3 = fc_map_rData_a_px_p_v_3;
  assign f0_payload_a_px_p_v_4 = fc_map_rData_a_px_p_v_4;
  assign f0_payload_a_px_attr = fc_map_rData_a_px_attr;
  assign f0_payload_a_e = fc_map_rData_a_e;
  assign f0_payload_a_wn = fc_map_rData_a_wn;
  assign f0_payload_sNeg = fc_map_rData_sNeg;
  assign f0_payload_tNeg = fc_map_rData_tNeg;
  assign f0_payload_lNeg = fc_map_rData_lNeg;
  assign f0_payload_ms = fc_map_rData_ms;
  assign f0_payload_mt = fc_map_rData_mt;
  assign f0_payload_ml = fc_map_rData_ml;
  assign _zz_f0_map_payload_addr = f0_payload_a_px_attr[2];
  assign _zz_f0_map_payload_addr_1 = f0_payload_a_px_attr[61 : 57];
  assign _zz_f0_map_payload_addr_2 = f0_payload_a_px_attr[66 : 62];
  assign _zz_f0_map_payload_addr_3 = f0_payload_a_px_attr[8];
  assign _zz_f0_map_payload_addr_4 = ($signed(_zz__zz_f0_map_payload_addr_4) + $signed(_zz__zz_f0_map_payload_addr_4_6));
  assign _zz_f0_map_payload_addr_5 = (_zz__zz_f0_map_payload_addr_5[9 : 0] & ((5'h0a <= _zz_f0_map_payload_addr_2) ? 10'h3ff : _zz__zz_f0_map_payload_addr_5_5));
  assign _zz_f0_map_payload_addr_6 = (_zz_f0_map_payload_addr_3 ? _zz__zz_f0_map_payload_addr_6 : _zz__zz_f0_map_payload_addr_6_5[9 : 0]);
  assign _zz_f0_map_payload_addr_7 = ($signed(_zz__zz_f0_map_payload_addr_7) + $signed(_zz__zz_f0_map_payload_addr_7_6));
  assign _zz_f0_map_payload_addr_8 = (_zz__zz_f0_map_payload_addr_8[9 : 0] & ((5'h0a <= _zz_f0_map_payload_addr_1) ? 10'h3ff : _zz__zz_f0_map_payload_addr_8_5));
  assign _zz_f0_map_payload_addr_9 = (_zz_f0_map_payload_addr_3 ? _zz__zz_f0_map_payload_addr_9 : _zz__zz_f0_map_payload_addr_9_5[9 : 0]);
  assign f0_map_valid = f0_valid;
  assign f0_ready = f0_map_ready;
  assign f0_map_payload_x = f0_payload_a_px_x;
  assign f0_map_payload_y = f0_payload_a_px_y;
  assign f0_map_payload_z = f0_payload_a_px_p_v_0;
  assign f0_map_payload_addr = {f0_payload_a_px_attr[6 : 3],(_zz_f0_map_payload_addr ? {{1'b0,_zz_f0_map_payload_addr_6},_zz_f0_map_payload_addr_9[9 : 1]} : {_zz_f0_map_payload_addr_6,_zz_f0_map_payload_addr_9})};
  assign f0_map_payload_nib = _zz_f0_map_payload_addr_9[0];
  assign f0_map_payload_light = (f0_payload_lNeg ? _zz_f0_map_payload_light : f0_payload_ml);
  assign f0_map_payload_flat = f0_payload_a_px_attr[0];
  assign f0_map_payload_blend = f0_payload_a_px_attr[1];
  assign f0_map_payload_tex4bpp = _zz_f0_map_payload_addr;
  assign f0_map_payload_pal = f0_payload_a_px_attr[38 : 23];
  always @(*) begin
    f0_map_ready = f_ready;
    if(when_Stream_l477_9) begin
      f0_map_ready = 1'b1;
    end
  end

  assign when_Stream_l477_9 = (! f_valid);
  assign f_valid = f0_map_rValid;
  assign f_payload_x = f0_map_rData_x;
  assign f_payload_y = f0_map_rData_y;
  assign f_payload_z = f0_map_rData_z;
  assign f_payload_addr = f0_map_rData_addr;
  assign f_payload_nib = f0_map_rData_nib;
  assign f_payload_light = f0_map_rData_light;
  assign f_payload_flat = f0_map_rData_flat;
  assign f_payload_blend = f0_map_rData_blend;
  assign f_payload_tex4bpp = f0_map_rData_tex4bpp;
  assign f_payload_pal = f0_map_rData_pal;
  assign io_o_valid = f_valid;
  assign f_ready = io_o_ready;
  assign io_o_payload_x = f_payload_x;
  assign io_o_payload_y = f_payload_y;
  assign io_o_payload_z = f_payload_z;
  assign io_o_payload_addr = f_payload_addr;
  assign io_o_payload_nib = f_payload_nib;
  assign io_o_payload_light = f_payload_light;
  assign io_o_payload_flat = f_payload_flat;
  assign io_o_payload_blend = f_payload_blend;
  assign io_o_payload_tex4bpp = f_payload_tex4bpp;
  assign io_o_payload_pal = f_payload_pal;
  assign io_busy = ((((((((((a0_valid || a_valid) || b_valid) || c0_valid) || cS_valid) || d_valid) || e0_valid) || e_valid) || fc_valid) || f0_valid) || f_valid);
  always @(posedge clk) begin
    if(reset) begin
      io_i_map_rValid <= 1'b0;
      a0_map_rValid <= 1'b0;
      _zz_b_valid <= 1'b0;
      b_map_rValid <= 1'b0;
      c0_map_rValid <= 1'b0;
      cS_map_rValid <= 1'b0;
      d_map_rValid <= 1'b0;
      e0_map_rValid <= 1'b0;
      e_map_rValid <= 1'b0;
      fc_map_rValid <= 1'b0;
      f0_map_rValid <= 1'b0;
    end else begin
      if(io_i_map_ready) begin
        io_i_map_rValid <= io_i_map_valid;
      end
      if(a0_map_ready) begin
        a0_map_rValid <= a0_map_valid;
      end
      if(a_translated_ready) begin
        _zz_b_valid <= a_translated_valid;
      end
      if(b_map_ready) begin
        b_map_rValid <= b_map_valid;
      end
      if(c0_map_ready) begin
        c0_map_rValid <= c0_map_valid;
      end
      if(cS_map_ready) begin
        cS_map_rValid <= cS_map_valid;
      end
      if(d_map_ready) begin
        d_map_rValid <= d_map_valid;
      end
      if(e0_map_ready) begin
        e0_map_rValid <= e0_map_valid;
      end
      if(e_map_ready) begin
        e_map_rValid <= e_map_valid;
      end
      if(fc_map_ready) begin
        fc_map_rValid <= fc_map_valid;
      end
      if(f0_map_ready) begin
        f0_map_rValid <= f0_map_valid;
      end
    end
  end

  always @(posedge clk) begin
    if(io_i_map_ready) begin
      io_i_map_rData_px_x <= io_i_map_payload_px_x;
      io_i_map_rData_px_y <= io_i_map_payload_px_y;
      io_i_map_rData_px_p_v_0 <= io_i_map_payload_px_p_v_0;
      io_i_map_rData_px_p_v_1 <= io_i_map_payload_px_p_v_1;
      io_i_map_rData_px_p_v_2 <= io_i_map_payload_px_p_v_2;
      io_i_map_rData_px_p_v_3 <= io_i_map_payload_px_p_v_3;
      io_i_map_rData_px_p_v_4 <= io_i_map_payload_px_p_v_4;
      io_i_map_rData_px_attr <= io_i_map_payload_px_attr;
      io_i_map_rData_wu <= io_i_map_payload_wu;
      io_i_map_rData_e <= io_i_map_payload_e;
    end
    if(a0_map_ready) begin
      a0_map_rData_px_x <= a0_map_payload_px_x;
      a0_map_rData_px_y <= a0_map_payload_px_y;
      a0_map_rData_px_p_v_0 <= a0_map_payload_px_p_v_0;
      a0_map_rData_px_p_v_1 <= a0_map_payload_px_p_v_1;
      a0_map_rData_px_p_v_2 <= a0_map_payload_px_p_v_2;
      a0_map_rData_px_p_v_3 <= a0_map_payload_px_p_v_3;
      a0_map_rData_px_p_v_4 <= a0_map_payload_px_p_v_4;
      a0_map_rData_px_attr <= a0_map_payload_px_attr;
      a0_map_rData_e <= a0_map_payload_e;
      a0_map_rData_wn <= a0_map_payload_wn;
    end
    if(a_translated_ready) begin
      a_payload_regNextWhen_px_x <= a_payload_px_x;
      a_payload_regNextWhen_px_y <= a_payload_px_y;
      a_payload_regNextWhen_px_p_v_0 <= a_payload_px_p_v_0;
      a_payload_regNextWhen_px_p_v_1 <= a_payload_px_p_v_1;
      a_payload_regNextWhen_px_p_v_2 <= a_payload_px_p_v_2;
      a_payload_regNextWhen_px_p_v_3 <= a_payload_px_p_v_3;
      a_payload_regNextWhen_px_p_v_4 <= a_payload_px_p_v_4;
      a_payload_regNextWhen_px_attr <= a_payload_px_attr;
      a_payload_regNextWhen_e <= a_payload_e;
      a_payload_regNextWhen_wn <= a_payload_wn;
    end
    if(b_map_ready) begin
      b_map_rData_a_px_x <= b_map_payload_a_px_x;
      b_map_rData_a_px_y <= b_map_payload_a_px_y;
      b_map_rData_a_px_p_v_0 <= b_map_payload_a_px_p_v_0;
      b_map_rData_a_px_p_v_1 <= b_map_payload_a_px_p_v_1;
      b_map_rData_a_px_p_v_2 <= b_map_payload_a_px_p_v_2;
      b_map_rData_a_px_p_v_3 <= b_map_payload_a_px_p_v_3;
      b_map_rData_a_px_p_v_4 <= b_map_payload_a_px_p_v_4;
      b_map_rData_a_px_attr <= b_map_payload_a_px_attr;
      b_map_rData_a_e <= b_map_payload_a_e;
      b_map_rData_a_wn <= b_map_payload_a_wn;
      b_map_rData_y0 <= b_map_payload_y0;
      b_map_rData_corr <= b_map_payload_corr;
    end
    if(c0_map_ready) begin
      c0_map_rData_a_px_x <= c0_map_payload_a_px_x;
      c0_map_rData_a_px_y <= c0_map_payload_a_px_y;
      c0_map_rData_a_px_p_v_0 <= c0_map_payload_a_px_p_v_0;
      c0_map_rData_a_px_p_v_1 <= c0_map_payload_a_px_p_v_1;
      c0_map_rData_a_px_p_v_2 <= c0_map_payload_a_px_p_v_2;
      c0_map_rData_a_px_p_v_3 <= c0_map_payload_a_px_p_v_3;
      c0_map_rData_a_px_p_v_4 <= c0_map_payload_a_px_p_v_4;
      c0_map_rData_a_px_attr <= c0_map_payload_a_px_attr;
      c0_map_rData_a_e <= c0_map_payload_a_e;
      c0_map_rData_a_wn <= c0_map_payload_a_wn;
      c0_map_rData_y0 <= c0_map_payload_y0;
      c0_map_rData_corr <= c0_map_payload_corr;
    end
    if(cS_map_ready) begin
      cS_map_rData_a_px_x <= cS_map_payload_a_px_x;
      cS_map_rData_a_px_y <= cS_map_payload_a_px_y;
      cS_map_rData_a_px_p_v_0 <= cS_map_payload_a_px_p_v_0;
      cS_map_rData_a_px_p_v_1 <= cS_map_payload_a_px_p_v_1;
      cS_map_rData_a_px_p_v_2 <= cS_map_payload_a_px_p_v_2;
      cS_map_rData_a_px_p_v_3 <= cS_map_payload_a_px_p_v_3;
      cS_map_rData_a_px_p_v_4 <= cS_map_payload_a_px_p_v_4;
      cS_map_rData_a_px_attr <= cS_map_payload_a_px_attr;
      cS_map_rData_a_e <= cS_map_payload_a_e;
      cS_map_rData_a_wn <= cS_map_payload_a_wn;
      cS_map_rData_y1 <= cS_map_payload_y1;
    end
    if(d_map_ready) begin
      d_map_rData_a_px_x <= d_map_payload_a_px_x;
      d_map_rData_a_px_y <= d_map_payload_a_px_y;
      d_map_rData_a_px_p_v_0 <= d_map_payload_a_px_p_v_0;
      d_map_rData_a_px_p_v_1 <= d_map_payload_a_px_p_v_1;
      d_map_rData_a_px_p_v_2 <= d_map_payload_a_px_p_v_2;
      d_map_rData_a_px_p_v_3 <= d_map_payload_a_px_p_v_3;
      d_map_rData_a_px_p_v_4 <= d_map_payload_a_px_p_v_4;
      d_map_rData_a_px_attr <= d_map_payload_a_px_attr;
      d_map_rData_a_e <= d_map_payload_a_e;
      d_map_rData_a_wn <= d_map_payload_a_wn;
      d_map_rData_y1 <= d_map_payload_y1;
      d_map_rData_sNeg <= d_map_payload_sNeg;
      d_map_rData_tNeg <= d_map_payload_tNeg;
      d_map_rData_lNeg <= d_map_payload_lNeg;
      d_map_rData_sa <= d_map_payload_sa;
      d_map_rData_ta <= d_map_payload_ta;
      d_map_rData_la <= d_map_payload_la;
    end
    if(e0_map_ready) begin
      e0_map_rData_a_px_x <= e0_map_payload_a_px_x;
      e0_map_rData_a_px_y <= e0_map_payload_a_px_y;
      e0_map_rData_a_px_p_v_0 <= e0_map_payload_a_px_p_v_0;
      e0_map_rData_a_px_p_v_1 <= e0_map_payload_a_px_p_v_1;
      e0_map_rData_a_px_p_v_2 <= e0_map_payload_a_px_p_v_2;
      e0_map_rData_a_px_p_v_3 <= e0_map_payload_a_px_p_v_3;
      e0_map_rData_a_px_p_v_4 <= e0_map_payload_a_px_p_v_4;
      e0_map_rData_a_px_attr <= e0_map_payload_a_px_attr;
      e0_map_rData_a_e <= e0_map_payload_a_e;
      e0_map_rData_a_wn <= e0_map_payload_a_wn;
      e0_map_rData_sNeg <= e0_map_payload_sNeg;
      e0_map_rData_tNeg <= e0_map_payload_tNeg;
      e0_map_rData_lNeg <= e0_map_payload_lNeg;
      e0_map_rData_ps <= e0_map_payload_ps;
      e0_map_rData_pt <= e0_map_payload_pt;
      e0_map_rData_pl <= e0_map_payload_pl;
    end
    if(e_map_ready) begin
      e_map_rData_a_px_x <= e_map_payload_a_px_x;
      e_map_rData_a_px_y <= e_map_payload_a_px_y;
      e_map_rData_a_px_p_v_0 <= e_map_payload_a_px_p_v_0;
      e_map_rData_a_px_p_v_1 <= e_map_payload_a_px_p_v_1;
      e_map_rData_a_px_p_v_2 <= e_map_payload_a_px_p_v_2;
      e_map_rData_a_px_p_v_3 <= e_map_payload_a_px_p_v_3;
      e_map_rData_a_px_p_v_4 <= e_map_payload_a_px_p_v_4;
      e_map_rData_a_px_attr <= e_map_payload_a_px_attr;
      e_map_rData_a_e <= e_map_payload_a_e;
      e_map_rData_a_wn <= e_map_payload_a_wn;
      e_map_rData_sNeg <= e_map_payload_sNeg;
      e_map_rData_tNeg <= e_map_payload_tNeg;
      e_map_rData_lNeg <= e_map_payload_lNeg;
      e_map_rData_ps <= e_map_payload_ps;
      e_map_rData_pt <= e_map_payload_pt;
      e_map_rData_pl <= e_map_payload_pl;
      e_map_rData_fineT <= e_map_payload_fineT;
      e_map_rData_fineL <= e_map_payload_fineL;
    end
    if(fc_map_ready) begin
      fc_map_rData_a_px_x <= fc_map_payload_a_px_x;
      fc_map_rData_a_px_y <= fc_map_payload_a_px_y;
      fc_map_rData_a_px_p_v_0 <= fc_map_payload_a_px_p_v_0;
      fc_map_rData_a_px_p_v_1 <= fc_map_payload_a_px_p_v_1;
      fc_map_rData_a_px_p_v_2 <= fc_map_payload_a_px_p_v_2;
      fc_map_rData_a_px_p_v_3 <= fc_map_payload_a_px_p_v_3;
      fc_map_rData_a_px_p_v_4 <= fc_map_payload_a_px_p_v_4;
      fc_map_rData_a_px_attr <= fc_map_payload_a_px_attr;
      fc_map_rData_a_e <= fc_map_payload_a_e;
      fc_map_rData_a_wn <= fc_map_payload_a_wn;
      fc_map_rData_sNeg <= fc_map_payload_sNeg;
      fc_map_rData_tNeg <= fc_map_payload_tNeg;
      fc_map_rData_lNeg <= fc_map_payload_lNeg;
      fc_map_rData_ms <= fc_map_payload_ms;
      fc_map_rData_mt <= fc_map_payload_mt;
      fc_map_rData_ml <= fc_map_payload_ml;
    end
    if(f0_map_ready) begin
      f0_map_rData_x <= f0_map_payload_x;
      f0_map_rData_y <= f0_map_payload_y;
      f0_map_rData_z <= f0_map_payload_z;
      f0_map_rData_addr <= f0_map_payload_addr;
      f0_map_rData_nib <= f0_map_payload_nib;
      f0_map_rData_light <= f0_map_payload_light;
      f0_map_rData_flat <= f0_map_payload_flat;
      f0_map_rData_blend <= f0_map_payload_blend;
      f0_map_rData_tex4bpp <= f0_map_payload_tex4bpp;
      f0_map_rData_pal <= f0_map_payload_pal;
    end
  end


endmodule

module hng64_raster_SpanPixels (
  input  wire          io_i_valid,
  output wire          io_i_ready,
  input  wire [8:0]    io_i_payload_x0,
  input  wire [8:0]    io_i_payload_x1,
  input  wire [8:0]    io_i_payload_y,
  input  wire [29:0]   io_i_payload_p_v_0,
  input  wire [33:0]   io_i_payload_p_v_1,
  input  wire [23:0]   io_i_payload_p_v_2,
  input  wire [31:0]   io_i_payload_p_v_3,
  input  wire [31:0]   io_i_payload_p_v_4,
  input  wire [29:0]   io_i_payload_dx_v_0,
  input  wire [33:0]   io_i_payload_dx_v_1,
  input  wire [23:0]   io_i_payload_dx_v_2,
  input  wire [31:0]   io_i_payload_dx_v_3,
  input  wire [31:0]   io_i_payload_dx_v_4,
  input  wire [66:0]   io_i_payload_attr,
  output wire          io_o_valid,
  input  wire          io_o_ready,
  output wire [8:0]    io_o_payload_x,
  output wire [8:0]    io_o_payload_y,
  output wire [29:0]   io_o_payload_p_v_0,
  output wire [33:0]   io_o_payload_p_v_1,
  output wire [23:0]   io_o_payload_p_v_2,
  output wire [31:0]   io_o_payload_p_v_3,
  output wire [31:0]   io_o_payload_p_v_4,
  output wire [66:0]   io_o_payload_attr,
  output wire          io_busy,
  input  wire          clk,
  input  wire          reset
);

  reg                 running;
  reg        [8:0]    s_x0;
  reg        [8:0]    s_x1;
  reg        [8:0]    s_y;
  reg        [29:0]   s_p_v_0;
  reg        [33:0]   s_p_v_1;
  reg        [23:0]   s_p_v_2;
  reg        [31:0]   s_p_v_3;
  reg        [31:0]   s_p_v_4;
  reg        [29:0]   s_dx_v_0;
  reg        [33:0]   s_dx_v_1;
  reg        [23:0]   s_dx_v_2;
  reg        [31:0]   s_dx_v_3;
  reg        [31:0]   s_dx_v_4;
  reg        [66:0]   s_attr;
  wire                io_i_fire;
  wire                io_o_fire;
  wire                when_Raster_l32;

  assign io_i_ready = (! running);
  assign io_busy = running;
  assign io_o_valid = running;
  assign io_o_payload_x = s_x0;
  assign io_o_payload_y = s_y;
  assign io_o_payload_p_v_0 = s_p_v_0;
  assign io_o_payload_p_v_1 = s_p_v_1;
  assign io_o_payload_p_v_2 = s_p_v_2;
  assign io_o_payload_p_v_3 = s_p_v_3;
  assign io_o_payload_p_v_4 = s_p_v_4;
  assign io_o_payload_attr = s_attr;
  assign io_i_fire = (io_i_valid && io_i_ready);
  assign io_o_fire = (io_o_valid && io_o_ready);
  assign when_Raster_l32 = (s_x1 <= s_x0);
  always @(posedge clk) begin
    if(reset) begin
      running <= 1'b0;
    end else begin
      if(io_i_fire) begin
        running <= 1'b1;
      end
      if(io_o_fire) begin
        if(when_Raster_l32) begin
          running <= 1'b0;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(io_i_fire) begin
      s_x0 <= io_i_payload_x0;
      s_x1 <= io_i_payload_x1;
      s_y <= io_i_payload_y;
      s_p_v_0 <= io_i_payload_p_v_0;
      s_p_v_1 <= io_i_payload_p_v_1;
      s_p_v_2 <= io_i_payload_p_v_2;
      s_p_v_3 <= io_i_payload_p_v_3;
      s_p_v_4 <= io_i_payload_p_v_4;
      s_dx_v_0 <= io_i_payload_dx_v_0;
      s_dx_v_1 <= io_i_payload_dx_v_1;
      s_dx_v_2 <= io_i_payload_dx_v_2;
      s_dx_v_3 <= io_i_payload_dx_v_3;
      s_dx_v_4 <= io_i_payload_dx_v_4;
      s_attr <= io_i_payload_attr;
    end
    if(io_o_fire) begin
      if(!when_Raster_l32) begin
        s_x0 <= (s_x0 + 9'h001);
        s_p_v_0 <= ($signed(s_p_v_0) + $signed(s_dx_v_0));
        s_p_v_1 <= ($signed(s_p_v_1) + $signed(s_dx_v_1));
        s_p_v_2 <= ($signed(s_p_v_2) + $signed(s_dx_v_2));
        s_p_v_3 <= ($signed(s_p_v_3) + $signed(s_dx_v_3));
        s_p_v_4 <= ($signed(s_p_v_4) + $signed(s_dx_v_4));
      end
    end
  end


endmodule

module hng64_raster_SpanWalker (
  input  wire          io_i_valid,
  output wire          io_i_ready,
  input  wire [12:0]   io_i_payload_x0,
  input  wire [12:0]   io_i_payload_x1,
  input  wire [12:0]   io_i_payload_y0,
  input  wire [12:0]   io_i_payload_y1,
  input  wire [24:0]   io_i_payload_a_0,
  input  wire [24:0]   io_i_payload_a_1,
  input  wire [24:0]   io_i_payload_a_2,
  input  wire [24:0]   io_i_payload_b_0,
  input  wire [24:0]   io_i_payload_b_1,
  input  wire [24:0]   io_i_payload_b_2,
  input  wire [50:0]   io_i_payload_edge_0,
  input  wire [50:0]   io_i_payload_edge_1,
  input  wire [50:0]   io_i_payload_edge_2,
  input  wire [29:0]   io_i_payload_p_v_0,
  input  wire [33:0]   io_i_payload_p_v_1,
  input  wire [23:0]   io_i_payload_p_v_2,
  input  wire [31:0]   io_i_payload_p_v_3,
  input  wire [31:0]   io_i_payload_p_v_4,
  input  wire [29:0]   io_i_payload_dx_v_0,
  input  wire [33:0]   io_i_payload_dx_v_1,
  input  wire [23:0]   io_i_payload_dx_v_2,
  input  wire [31:0]   io_i_payload_dx_v_3,
  input  wire [31:0]   io_i_payload_dx_v_4,
  input  wire [29:0]   io_i_payload_dy_v_0,
  input  wire [33:0]   io_i_payload_dy_v_1,
  input  wire [23:0]   io_i_payload_dy_v_2,
  input  wire [31:0]   io_i_payload_dy_v_3,
  input  wire [31:0]   io_i_payload_dy_v_4,
  input  wire [66:0]   io_i_payload_attr,
  output wire          io_o_valid,
  input  wire          io_o_ready,
  output wire [8:0]    io_o_payload_x0,
  output wire [8:0]    io_o_payload_x1,
  output wire [8:0]    io_o_payload_y,
  input  wire          io_drained,
  output wire          io_busy,
  input  wire          clk,
  input  wire          reset
);
  localparam hng64_raster_W_Idle = 3'd0;
  localparam hng64_raster_W_Decide = 3'd1;
  localparam hng64_raster_W_RecoverLeft = 3'd2;
  localparam hng64_raster_W_SearchRightToEnter = 3'd3;
  localparam hng64_raster_W_SearchLeftToExit = 3'd4;
  localparam hng64_raster_W_SearchRightToExit = 3'd5;
  localparam hng64_raster_W_EmitSpan = 3'd6;
  localparam hng64_raster_W_AdvanceRow = 3'd7;

  wire       [12:0]   _zz_io_i_ready;
  wire       [8:0]    _zz_io_o_payload_x0;
  wire       [8:0]    _zz_io_o_payload_x1;
  wire       [8:0]    _zz_io_o_payload_y;
  wire       [50:0]   _zz_bma_0;
  wire       [50:0]   _zz_bma_0_1;
  wire       [50:0]   _zz_bma_0_2;
  wire       [50:0]   _zz_bma_1;
  wire       [50:0]   _zz_bma_1_1;
  wire       [50:0]   _zz_bma_1_2;
  wire       [50:0]   _zz_bma_2;
  wire       [50:0]   _zz_bma_2_1;
  wire       [50:0]   _zz_bma_2_2;
  wire       [50:0]   _zz_leftEdge_e_0;
  wire       [50:0]   _zz_leftEdge_e_0_1;
  wire       [50:0]   _zz_leftEdge_e_1;
  wire       [50:0]   _zz_leftEdge_e_1_1;
  wire       [50:0]   _zz_leftEdge_e_2;
  wire       [50:0]   _zz_leftEdge_e_2_1;
  wire       [50:0]   _zz_probe_e_0;
  wire       [50:0]   _zz_probe_e_0_1;
  wire       [50:0]   _zz_probe_e_1;
  wire       [50:0]   _zz_probe_e_1_1;
  wire       [50:0]   _zz_probe_e_2;
  wire       [50:0]   _zz_probe_e_2_1;
  wire       [50:0]   _zz_leftEdge_e_0_2;
  wire       [50:0]   _zz_leftEdge_e_0_3;
  wire       [50:0]   _zz_leftEdge_e_1_2;
  wire       [50:0]   _zz_leftEdge_e_1_3;
  wire       [50:0]   _zz_leftEdge_e_2_2;
  wire       [50:0]   _zz_leftEdge_e_2_3;
  wire       [50:0]   _zz_probe_e_0_2;
  wire       [50:0]   _zz_probe_e_0_3;
  wire       [50:0]   _zz_probe_e_1_2;
  wire       [50:0]   _zz_probe_e_1_3;
  wire       [50:0]   _zz_probe_e_2_2;
  wire       [50:0]   _zz_probe_e_2_3;
  wire       [50:0]   _zz_probe_e_0_4;
  wire       [50:0]   _zz_probe_e_0_5;
  wire       [50:0]   _zz_probe_e_1_4;
  wire       [50:0]   _zz_probe_e_1_5;
  wire       [50:0]   _zz_probe_e_2_4;
  wire       [50:0]   _zz_probe_e_2_5;
  wire       [50:0]   _zz_leftEdge_e_0_4;
  wire       [50:0]   _zz_leftEdge_e_0_5;
  wire       [50:0]   _zz_leftEdge_e_1_4;
  wire       [50:0]   _zz_leftEdge_e_1_5;
  wire       [50:0]   _zz_leftEdge_e_2_4;
  wire       [50:0]   _zz_leftEdge_e_2_5;
  wire       [50:0]   _zz_probe_e_0_6;
  wire       [50:0]   _zz_probe_e_0_7;
  wire       [50:0]   _zz_probe_e_1_6;
  wire       [50:0]   _zz_probe_e_1_7;
  wire       [50:0]   _zz_probe_e_2_6;
  wire       [50:0]   _zz_probe_e_2_7;
  wire       [50:0]   _zz_leftEdge_e_0_6;
  wire       [50:0]   _zz_leftEdge_e_0_7;
  wire       [50:0]   _zz_leftEdge_e_1_6;
  wire       [50:0]   _zz_leftEdge_e_1_7;
  wire       [50:0]   _zz_leftEdge_e_2_6;
  wire       [50:0]   _zz_leftEdge_e_2_7;
  wire       [50:0]   _zz_probe_e_0_8;
  wire       [50:0]   _zz_probe_e_0_9;
  wire       [50:0]   _zz_probe_e_1_8;
  wire       [50:0]   _zz_probe_e_1_9;
  wire       [50:0]   _zz_probe_e_2_8;
  wire       [50:0]   _zz_probe_e_2_9;
  wire       [12:0]   _zz_when_SpanWalker_l198;
  wire       [12:0]   _zz__zz_rowGuess_x;
  wire       [12:0]   _zz__zz_rowGuess_y;
  wire       [12:0]   _zz__zz_rowGuess_y_1;
  wire       [50:0]   _zz__zz_rowGuess_e_0;
  wire       [50:0]   _zz__zz_rowGuess_e_0_1;
  wire       [50:0]   _zz__zz_rowGuess_e_0_2;
  wire       [50:0]   _zz__zz_rowGuess_e_0_3;
  wire       [50:0]   _zz__zz_rowGuess_e_1;
  wire       [50:0]   _zz__zz_rowGuess_e_1_1;
  wire       [50:0]   _zz__zz_rowGuess_e_1_2;
  wire       [50:0]   _zz__zz_rowGuess_e_1_3;
  wire       [50:0]   _zz__zz_rowGuess_e_2;
  wire       [50:0]   _zz__zz_rowGuess_e_2_1;
  wire       [50:0]   _zz__zz_rowGuess_e_2_2;
  wire       [50:0]   _zz__zz_rowGuess_e_2_3;
  reg        [2:0]    state;
  reg        [50:0]   bma_0;
  reg        [50:0]   bma_1;
  reg        [50:0]   bma_2;
  reg        [12:0]   rowGuess_x;
  reg        [12:0]   rowGuess_y;
  reg        [50:0]   rowGuess_e_0;
  reg        [50:0]   rowGuess_e_1;
  reg        [50:0]   rowGuess_e_2;
  reg        [12:0]   probe_x;
  reg        [12:0]   probe_y;
  reg        [50:0]   probe_e_0;
  reg        [50:0]   probe_e_1;
  reg        [50:0]   probe_e_2;
  reg        [12:0]   bookmark_x;
  reg        [12:0]   bookmark_y;
  reg        [50:0]   bookmark_e_0;
  reg        [50:0]   bookmark_e_1;
  reg        [50:0]   bookmark_e_2;
  reg        [12:0]   leftEdge_x;
  reg        [12:0]   leftEdge_y;
  reg        [50:0]   leftEdge_e_0;
  reg        [50:0]   leftEdge_e_1;
  reg        [50:0]   leftEdge_e_2;
  reg        [12:0]   nextRowBase_x;
  reg        [12:0]   nextRowBase_y;
  reg        [50:0]   nextRowBase_e_0;
  reg        [50:0]   nextRowBase_e_1;
  reg        [50:0]   nextRowBase_e_2;
  reg                 nextRowLeftBiased;
  reg        [12:0]   emitRight;
  reg                 firstSpanPending;
  reg                 recoverFoundInside;
  wire       [12:0]   visibleStart;
  wire       [12:0]   visibleEnd;
  wire       [12:0]   lastRow;
  wire                emitVisibleX;
  wire                emitVisibleY;
  wire                emitVisible;
  wire                when_SpanWalker_l93;
  wire                when_SpanWalker_l105;
  wire                when_SpanWalker_l106;
  wire                when_SpanWalker_l114;
  wire                when_SpanWalker_l115;
  wire                when_SpanWalker_l116;
  wire                when_SpanWalker_l120;
  wire                when_SpanWalker_l86;
  wire                when_SpanWalker_l137;
  wire                when_SpanWalker_l146;
  wire                when_SpanWalker_l147;
  wire                when_SpanWalker_l151;
  wire                when_SpanWalker_l162;
  wire                when_SpanWalker_l163;
  wire                when_SpanWalker_l164;
  wire                when_SpanWalker_l86_1;
  wire                when_SpanWalker_l178;
  wire                when_SpanWalker_l179;
  wire                when_SpanWalker_l180;
  wire                when_SpanWalker_l192;
  wire                when_SpanWalker_l197;
  wire                when_SpanWalker_l198;
  wire       [12:0]   _zz_rowGuess_x;
  wire       [12:0]   _zz_rowGuess_y;
  wire       [50:0]   _zz_rowGuess_e_0;
  wire       [50:0]   _zz_rowGuess_e_1;
  wire       [50:0]   _zz_rowGuess_e_2;
  wire       [2:0]    _zz_state;
  `ifndef SYNTHESIS
  reg [143:0] state_string;
  reg [143:0] _zz_state_string;
  `endif


  assign _zz_io_i_ready = ($signed(nextRowBase_y) + $signed(13'h0001));
  assign _zz_io_o_payload_x0 = leftEdge_x[8:0];
  assign _zz_io_o_payload_x1 = emitRight[8:0];
  assign _zz_io_o_payload_y = leftEdge_y[8:0];
  assign _zz_bma_0 = ($signed(_zz_bma_0_1) - $signed(_zz_bma_0_2));
  assign _zz_bma_0_1 = {{26{io_i_payload_b_0[24]}}, io_i_payload_b_0};
  assign _zz_bma_0_2 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_bma_1 = ($signed(_zz_bma_1_1) - $signed(_zz_bma_1_2));
  assign _zz_bma_1_1 = {{26{io_i_payload_b_1[24]}}, io_i_payload_b_1};
  assign _zz_bma_1_2 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_bma_2 = ($signed(_zz_bma_2_1) - $signed(_zz_bma_2_2));
  assign _zz_bma_2_1 = {{26{io_i_payload_b_2[24]}}, io_i_payload_b_2};
  assign _zz_bma_2_2 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_leftEdge_e_0 = (_zz_leftEdge_e_0_1 <<< 12);
  assign _zz_leftEdge_e_0_1 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_leftEdge_e_1 = (_zz_leftEdge_e_1_1 <<< 12);
  assign _zz_leftEdge_e_1_1 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_leftEdge_e_2 = (_zz_leftEdge_e_2_1 <<< 12);
  assign _zz_leftEdge_e_2_1 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_probe_e_0 = (_zz_probe_e_0_1 <<< 12);
  assign _zz_probe_e_0_1 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_probe_e_1 = (_zz_probe_e_1_1 <<< 12);
  assign _zz_probe_e_1_1 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_probe_e_2 = (_zz_probe_e_2_1 <<< 12);
  assign _zz_probe_e_2_1 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_leftEdge_e_0_2 = (_zz_leftEdge_e_0_3 <<< 12);
  assign _zz_leftEdge_e_0_3 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_leftEdge_e_1_2 = (_zz_leftEdge_e_1_3 <<< 12);
  assign _zz_leftEdge_e_1_3 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_leftEdge_e_2_2 = (_zz_leftEdge_e_2_3 <<< 12);
  assign _zz_leftEdge_e_2_3 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_probe_e_0_2 = (_zz_probe_e_0_3 <<< 12);
  assign _zz_probe_e_0_3 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_probe_e_1_2 = (_zz_probe_e_1_3 <<< 12);
  assign _zz_probe_e_1_3 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_probe_e_2_2 = (_zz_probe_e_2_3 <<< 12);
  assign _zz_probe_e_2_3 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_probe_e_0_4 = (_zz_probe_e_0_5 <<< 12);
  assign _zz_probe_e_0_5 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_probe_e_1_4 = (_zz_probe_e_1_5 <<< 12);
  assign _zz_probe_e_1_5 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_probe_e_2_4 = (_zz_probe_e_2_5 <<< 12);
  assign _zz_probe_e_2_5 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_leftEdge_e_0_4 = (_zz_leftEdge_e_0_5 <<< 12);
  assign _zz_leftEdge_e_0_5 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_leftEdge_e_1_4 = (_zz_leftEdge_e_1_5 <<< 12);
  assign _zz_leftEdge_e_1_5 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_leftEdge_e_2_4 = (_zz_leftEdge_e_2_5 <<< 12);
  assign _zz_leftEdge_e_2_5 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_probe_e_0_6 = (_zz_probe_e_0_7 <<< 12);
  assign _zz_probe_e_0_7 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_probe_e_1_6 = (_zz_probe_e_1_7 <<< 12);
  assign _zz_probe_e_1_7 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_probe_e_2_6 = (_zz_probe_e_2_7 <<< 12);
  assign _zz_probe_e_2_7 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_leftEdge_e_0_6 = (_zz_leftEdge_e_0_7 <<< 12);
  assign _zz_leftEdge_e_0_7 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_leftEdge_e_1_6 = (_zz_leftEdge_e_1_7 <<< 12);
  assign _zz_leftEdge_e_1_7 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_leftEdge_e_2_6 = (_zz_leftEdge_e_2_7 <<< 12);
  assign _zz_leftEdge_e_2_7 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_probe_e_0_8 = (_zz_probe_e_0_9 <<< 12);
  assign _zz_probe_e_0_9 = {{26{io_i_payload_a_0[24]}}, io_i_payload_a_0};
  assign _zz_probe_e_1_8 = (_zz_probe_e_1_9 <<< 12);
  assign _zz_probe_e_1_9 = {{26{io_i_payload_a_1[24]}}, io_i_payload_a_1};
  assign _zz_probe_e_2_8 = (_zz_probe_e_2_9 <<< 12);
  assign _zz_probe_e_2_9 = {{26{io_i_payload_a_2[24]}}, io_i_payload_a_2};
  assign _zz_when_SpanWalker_l198 = ($signed(nextRowBase_y) + $signed(13'h0001));
  assign _zz__zz_rowGuess_x = ($signed(nextRowBase_x) - $signed(13'h0001));
  assign _zz__zz_rowGuess_y = ($signed(nextRowBase_y) + $signed(13'h0001));
  assign _zz__zz_rowGuess_y_1 = ($signed(nextRowBase_y) + $signed(13'h0001));
  assign _zz__zz_rowGuess_e_0 = ($signed(nextRowBase_e_0) + $signed(bma_0));
  assign _zz__zz_rowGuess_e_0_1 = ($signed(nextRowBase_e_0) + $signed(_zz__zz_rowGuess_e_0_2));
  assign _zz__zz_rowGuess_e_0_2 = (_zz__zz_rowGuess_e_0_3 <<< 12);
  assign _zz__zz_rowGuess_e_0_3 = {{26{io_i_payload_b_0[24]}}, io_i_payload_b_0};
  assign _zz__zz_rowGuess_e_1 = ($signed(nextRowBase_e_1) + $signed(bma_1));
  assign _zz__zz_rowGuess_e_1_1 = ($signed(nextRowBase_e_1) + $signed(_zz__zz_rowGuess_e_1_2));
  assign _zz__zz_rowGuess_e_1_2 = (_zz__zz_rowGuess_e_1_3 <<< 12);
  assign _zz__zz_rowGuess_e_1_3 = {{26{io_i_payload_b_1[24]}}, io_i_payload_b_1};
  assign _zz__zz_rowGuess_e_2 = ($signed(nextRowBase_e_2) + $signed(bma_2));
  assign _zz__zz_rowGuess_e_2_1 = ($signed(nextRowBase_e_2) + $signed(_zz__zz_rowGuess_e_2_2));
  assign _zz__zz_rowGuess_e_2_2 = (_zz__zz_rowGuess_e_2_3 <<< 12);
  assign _zz__zz_rowGuess_e_2_3 = {{26{io_i_payload_b_2[24]}}, io_i_payload_b_2};
  `ifndef SYNTHESIS
  always @(*) begin
    case(state)
      hng64_raster_W_Idle : state_string = "Idle              ";
      hng64_raster_W_Decide : state_string = "Decide            ";
      hng64_raster_W_RecoverLeft : state_string = "RecoverLeft       ";
      hng64_raster_W_SearchRightToEnter : state_string = "SearchRightToEnter";
      hng64_raster_W_SearchLeftToExit : state_string = "SearchLeftToExit  ";
      hng64_raster_W_SearchRightToExit : state_string = "SearchRightToExit ";
      hng64_raster_W_EmitSpan : state_string = "EmitSpan          ";
      hng64_raster_W_AdvanceRow : state_string = "AdvanceRow        ";
      default : state_string = "??????????????????";
    endcase
  end
  always @(*) begin
    case(_zz_state)
      hng64_raster_W_Idle : _zz_state_string = "Idle              ";
      hng64_raster_W_Decide : _zz_state_string = "Decide            ";
      hng64_raster_W_RecoverLeft : _zz_state_string = "RecoverLeft       ";
      hng64_raster_W_SearchRightToEnter : _zz_state_string = "SearchRightToEnter";
      hng64_raster_W_SearchLeftToExit : _zz_state_string = "SearchLeftToExit  ";
      hng64_raster_W_SearchRightToExit : _zz_state_string = "SearchRightToExit ";
      hng64_raster_W_EmitSpan : _zz_state_string = "EmitSpan          ";
      hng64_raster_W_AdvanceRow : _zz_state_string = "AdvanceRow        ";
      default : _zz_state_string = "??????????????????";
    endcase
  end
  `endif

  assign io_busy = (state != hng64_raster_W_Idle);
  assign visibleStart = (($signed(13'h0) < $signed(io_i_payload_x0)) ? io_i_payload_x0 : 13'h0);
  assign visibleEnd = (($signed(io_i_payload_x1) < $signed(13'h0201)) ? io_i_payload_x1 : 13'h0201);
  assign lastRow = (($signed(io_i_payload_y1) < $signed(13'h0200)) ? io_i_payload_y1 : 13'h0200);
  assign io_i_ready = (((state == hng64_raster_W_AdvanceRow) && ($signed(lastRow) <= $signed(_zz_io_i_ready))) && io_drained);
  assign emitVisibleX = ((($signed(leftEdge_x) <= $signed(emitRight)) && ($signed(13'h0) <= $signed(emitRight))) && ($signed(leftEdge_x) < $signed(13'h0201)));
  assign emitVisibleY = (($signed(13'h0) <= $signed(leftEdge_y)) && ($signed(leftEdge_y) < $signed(13'h0200)));
  assign emitVisible = (emitVisibleX && emitVisibleY);
  assign io_o_valid = ((state == hng64_raster_W_EmitSpan) && emitVisible);
  assign io_o_payload_x0 = _zz_io_o_payload_x0;
  assign io_o_payload_x1 = _zz_io_o_payload_x1;
  assign io_o_payload_y = _zz_io_o_payload_y;
  assign when_SpanWalker_l93 = ((state == hng64_raster_W_Idle) && io_i_valid);
  assign when_SpanWalker_l105 = (state == hng64_raster_W_Decide);
  assign when_SpanWalker_l106 = ((($signed(51'h0) <= $signed(probe_e_0)) && ($signed(51'h0) <= $signed(probe_e_1))) && ($signed(51'h0) <= $signed(probe_e_2)));
  assign when_SpanWalker_l114 = (state == hng64_raster_W_RecoverLeft);
  assign when_SpanWalker_l115 = ((($signed(51'h0) <= $signed(probe_e_0)) && ($signed(51'h0) <= $signed(probe_e_1))) && ($signed(51'h0) <= $signed(probe_e_2)));
  assign when_SpanWalker_l116 = (! recoverFoundInside);
  assign when_SpanWalker_l120 = ($signed(probe_x) <= $signed(visibleStart));
  assign when_SpanWalker_l86 = ($signed(probe_x) < $signed(visibleStart));
  assign when_SpanWalker_l137 = ($signed(probe_x) <= $signed(visibleStart));
  assign when_SpanWalker_l146 = (state == hng64_raster_W_SearchRightToEnter);
  assign when_SpanWalker_l147 = (((($signed(51'h0) <= $signed(probe_e_0)) && ($signed(51'h0) <= $signed(probe_e_1))) && ($signed(51'h0) <= $signed(probe_e_2))) && ($signed(visibleStart) <= $signed(probe_x)));
  assign when_SpanWalker_l151 = ($signed(visibleEnd) <= $signed(probe_x));
  assign when_SpanWalker_l162 = (state == hng64_raster_W_SearchLeftToExit);
  assign when_SpanWalker_l163 = ((($signed(51'h0) <= $signed(probe_e_0)) && ($signed(51'h0) <= $signed(probe_e_1))) && ($signed(51'h0) <= $signed(probe_e_2)));
  assign when_SpanWalker_l164 = ($signed(probe_x) <= $signed(visibleStart));
  assign when_SpanWalker_l86_1 = ($signed(probe_x) < $signed(visibleStart));
  assign when_SpanWalker_l178 = (state == hng64_raster_W_SearchRightToExit);
  assign when_SpanWalker_l179 = ((($signed(51'h0) <= $signed(probe_e_0)) && ($signed(51'h0) <= $signed(probe_e_1))) && ($signed(51'h0) <= $signed(probe_e_2)));
  assign when_SpanWalker_l180 = ($signed(visibleEnd) <= $signed(probe_x));
  assign when_SpanWalker_l192 = ((state == hng64_raster_W_EmitSpan) && ((! emitVisible) || io_o_ready));
  assign when_SpanWalker_l197 = (state == hng64_raster_W_AdvanceRow);
  assign when_SpanWalker_l198 = (($signed(lastRow) <= $signed(_zz_when_SpanWalker_l198)) && io_drained);
  assign _zz_rowGuess_x = (nextRowLeftBiased ? _zz__zz_rowGuess_x : nextRowBase_x);
  assign _zz_rowGuess_y = (nextRowLeftBiased ? _zz__zz_rowGuess_y : _zz__zz_rowGuess_y_1);
  assign _zz_rowGuess_e_0 = (nextRowLeftBiased ? _zz__zz_rowGuess_e_0 : _zz__zz_rowGuess_e_0_1);
  assign _zz_rowGuess_e_1 = (nextRowLeftBiased ? _zz__zz_rowGuess_e_1 : _zz__zz_rowGuess_e_1_1);
  assign _zz_rowGuess_e_2 = (nextRowLeftBiased ? _zz__zz_rowGuess_e_2 : _zz__zz_rowGuess_e_2_1);
  assign _zz_state = (nextRowLeftBiased ? hng64_raster_W_RecoverLeft : hng64_raster_W_Decide);
  always @(posedge clk) begin
    if(reset) begin
      state <= hng64_raster_W_Idle;
      nextRowLeftBiased <= 1'b0;
      firstSpanPending <= 1'b0;
      recoverFoundInside <= 1'b0;
    end else begin
      if(when_SpanWalker_l93) begin
        firstSpanPending <= 1'b1;
        state <= hng64_raster_W_Decide;
      end
      if(when_SpanWalker_l105) begin
        if(when_SpanWalker_l106) begin
          state <= hng64_raster_W_SearchLeftToExit;
        end else begin
          state <= hng64_raster_W_SearchRightToEnter;
        end
      end
      if(when_SpanWalker_l114) begin
        if(when_SpanWalker_l115) begin
          if(when_SpanWalker_l116) begin
            recoverFoundInside <= 1'b1;
          end
          if(when_SpanWalker_l120) begin
            recoverFoundInside <= 1'b0;
            state <= hng64_raster_W_SearchRightToExit;
          end
        end else begin
          if(recoverFoundInside) begin
            recoverFoundInside <= 1'b0;
            state <= hng64_raster_W_SearchRightToExit;
          end else begin
            if(when_SpanWalker_l137) begin
              state <= hng64_raster_W_SearchRightToEnter;
            end
          end
        end
      end
      if(when_SpanWalker_l146) begin
        if(when_SpanWalker_l147) begin
          state <= hng64_raster_W_SearchRightToExit;
        end else begin
          if(when_SpanWalker_l151) begin
            if(firstSpanPending) begin
              nextRowLeftBiased <= 1'b0;
              state <= hng64_raster_W_AdvanceRow;
            end else begin
              nextRowLeftBiased <= 1'b1;
              state <= hng64_raster_W_AdvanceRow;
            end
          end
        end
      end
      if(when_SpanWalker_l162) begin
        if(when_SpanWalker_l163) begin
          if(when_SpanWalker_l164) begin
            state <= hng64_raster_W_SearchRightToExit;
          end
        end else begin
          state <= hng64_raster_W_SearchRightToExit;
        end
      end
      if(when_SpanWalker_l178) begin
        if(when_SpanWalker_l179) begin
          if(when_SpanWalker_l180) begin
            state <= hng64_raster_W_EmitSpan;
          end
        end else begin
          state <= hng64_raster_W_EmitSpan;
        end
      end
      if(when_SpanWalker_l192) begin
        firstSpanPending <= 1'b0;
        nextRowLeftBiased <= 1'b1;
        state <= hng64_raster_W_AdvanceRow;
      end
      if(when_SpanWalker_l197) begin
        if(when_SpanWalker_l198) begin
          state <= hng64_raster_W_Idle;
          firstSpanPending <= 1'b0;
          recoverFoundInside <= 1'b0;
        end else begin
          recoverFoundInside <= 1'b0;
          state <= _zz_state;
        end
      end
    end
  end

  always @(posedge clk) begin
    if(when_SpanWalker_l93) begin
      bma_0 <= (_zz_bma_0 <<< 12);
      bma_1 <= (_zz_bma_1 <<< 12);
      bma_2 <= (_zz_bma_2 <<< 12);
      rowGuess_x <= io_i_payload_x0;
      rowGuess_y <= io_i_payload_y0;
      rowGuess_e_0 <= io_i_payload_edge_0;
      rowGuess_e_1 <= io_i_payload_edge_1;
      rowGuess_e_2 <= io_i_payload_edge_2;
      probe_x <= io_i_payload_x0;
      probe_y <= io_i_payload_y0;
      probe_e_0 <= io_i_payload_edge_0;
      probe_e_1 <= io_i_payload_edge_1;
      probe_e_2 <= io_i_payload_edge_2;
      bookmark_x <= io_i_payload_x0;
      bookmark_y <= io_i_payload_y0;
      bookmark_e_0 <= io_i_payload_edge_0;
      bookmark_e_1 <= io_i_payload_edge_1;
      bookmark_e_2 <= io_i_payload_edge_2;
    end
    if(when_SpanWalker_l105) begin
      if(when_SpanWalker_l106) begin
        bookmark_x <= probe_x;
        bookmark_y <= probe_y;
        bookmark_e_0 <= probe_e_0;
        bookmark_e_1 <= probe_e_1;
        bookmark_e_2 <= probe_e_2;
      end
    end
    if(when_SpanWalker_l114) begin
      if(when_SpanWalker_l115) begin
        if(when_SpanWalker_l116) begin
          bookmark_x <= probe_x;
          bookmark_y <= probe_y;
          bookmark_e_0 <= probe_e_0;
          bookmark_e_1 <= probe_e_1;
          bookmark_e_2 <= probe_e_2;
        end
        if(when_SpanWalker_l120) begin
          if(when_SpanWalker_l86) begin
            leftEdge_x <= ($signed(probe_x) + $signed(13'h0001));
            leftEdge_y <= probe_y;
            leftEdge_e_0 <= ($signed(probe_e_0) + $signed(_zz_leftEdge_e_0));
            leftEdge_e_1 <= ($signed(probe_e_1) + $signed(_zz_leftEdge_e_1));
            leftEdge_e_2 <= ($signed(probe_e_2) + $signed(_zz_leftEdge_e_2));
          end else begin
            leftEdge_x <= probe_x;
            leftEdge_y <= probe_y;
            leftEdge_e_0 <= probe_e_0;
            leftEdge_e_1 <= probe_e_1;
            leftEdge_e_2 <= probe_e_2;
          end
          if(recoverFoundInside) begin
            probe_x <= bookmark_x;
            probe_y <= bookmark_y;
            probe_e_0 <= bookmark_e_0;
            probe_e_1 <= bookmark_e_1;
            probe_e_2 <= bookmark_e_2;
          end
        end else begin
          probe_x <= ($signed(probe_x) - $signed(13'h0001));
          probe_y <= probe_y;
          probe_e_0 <= ($signed(probe_e_0) - $signed(_zz_probe_e_0));
          probe_e_1 <= ($signed(probe_e_1) - $signed(_zz_probe_e_1));
          probe_e_2 <= ($signed(probe_e_2) - $signed(_zz_probe_e_2));
        end
      end else begin
        if(recoverFoundInside) begin
          leftEdge_x <= ($signed(probe_x) + $signed(13'h0001));
          leftEdge_y <= probe_y;
          leftEdge_e_0 <= ($signed(probe_e_0) + $signed(_zz_leftEdge_e_0_2));
          leftEdge_e_1 <= ($signed(probe_e_1) + $signed(_zz_leftEdge_e_1_2));
          leftEdge_e_2 <= ($signed(probe_e_2) + $signed(_zz_leftEdge_e_2_2));
          probe_x <= bookmark_x;
          probe_y <= bookmark_y;
          probe_e_0 <= bookmark_e_0;
          probe_e_1 <= bookmark_e_1;
          probe_e_2 <= bookmark_e_2;
        end else begin
          if(when_SpanWalker_l137) begin
            probe_x <= bookmark_x;
            probe_y <= bookmark_y;
            probe_e_0 <= bookmark_e_0;
            probe_e_1 <= bookmark_e_1;
            probe_e_2 <= bookmark_e_2;
          end else begin
            probe_x <= ($signed(probe_x) - $signed(13'h0001));
            probe_y <= probe_y;
            probe_e_0 <= ($signed(probe_e_0) - $signed(_zz_probe_e_0_2));
            probe_e_1 <= ($signed(probe_e_1) - $signed(_zz_probe_e_1_2));
            probe_e_2 <= ($signed(probe_e_2) - $signed(_zz_probe_e_2_2));
          end
        end
      end
    end
    if(when_SpanWalker_l146) begin
      if(when_SpanWalker_l147) begin
        leftEdge_x <= probe_x;
        leftEdge_y <= probe_y;
        leftEdge_e_0 <= probe_e_0;
        leftEdge_e_1 <= probe_e_1;
        leftEdge_e_2 <= probe_e_2;
        bookmark_x <= probe_x;
        bookmark_y <= probe_y;
        bookmark_e_0 <= probe_e_0;
        bookmark_e_1 <= probe_e_1;
        bookmark_e_2 <= probe_e_2;
      end else begin
        if(when_SpanWalker_l151) begin
          if(firstSpanPending) begin
            nextRowBase_x <= rowGuess_x;
            nextRowBase_y <= rowGuess_y;
            nextRowBase_e_0 <= rowGuess_e_0;
            nextRowBase_e_1 <= rowGuess_e_1;
            nextRowBase_e_2 <= rowGuess_e_2;
          end else begin
            nextRowBase_x <= bookmark_x;
            nextRowBase_y <= bookmark_y;
            nextRowBase_e_0 <= bookmark_e_0;
            nextRowBase_e_1 <= bookmark_e_1;
            nextRowBase_e_2 <= bookmark_e_2;
          end
        end else begin
          probe_x <= ($signed(probe_x) + $signed(13'h0001));
          probe_y <= probe_y;
          probe_e_0 <= ($signed(probe_e_0) + $signed(_zz_probe_e_0_4));
          probe_e_1 <= ($signed(probe_e_1) + $signed(_zz_probe_e_1_4));
          probe_e_2 <= ($signed(probe_e_2) + $signed(_zz_probe_e_2_4));
        end
      end
    end
    if(when_SpanWalker_l162) begin
      if(when_SpanWalker_l163) begin
        if(when_SpanWalker_l164) begin
          if(when_SpanWalker_l86_1) begin
            leftEdge_x <= ($signed(probe_x) + $signed(13'h0001));
            leftEdge_y <= probe_y;
            leftEdge_e_0 <= ($signed(probe_e_0) + $signed(_zz_leftEdge_e_0_4));
            leftEdge_e_1 <= ($signed(probe_e_1) + $signed(_zz_leftEdge_e_1_4));
            leftEdge_e_2 <= ($signed(probe_e_2) + $signed(_zz_leftEdge_e_2_4));
          end else begin
            leftEdge_x <= probe_x;
            leftEdge_y <= probe_y;
            leftEdge_e_0 <= probe_e_0;
            leftEdge_e_1 <= probe_e_1;
            leftEdge_e_2 <= probe_e_2;
          end
          probe_x <= bookmark_x;
          probe_y <= bookmark_y;
          probe_e_0 <= bookmark_e_0;
          probe_e_1 <= bookmark_e_1;
          probe_e_2 <= bookmark_e_2;
        end else begin
          probe_x <= ($signed(probe_x) - $signed(13'h0001));
          probe_y <= probe_y;
          probe_e_0 <= ($signed(probe_e_0) - $signed(_zz_probe_e_0_6));
          probe_e_1 <= ($signed(probe_e_1) - $signed(_zz_probe_e_1_6));
          probe_e_2 <= ($signed(probe_e_2) - $signed(_zz_probe_e_2_6));
        end
      end else begin
        leftEdge_x <= ($signed(probe_x) + $signed(13'h0001));
        leftEdge_y <= probe_y;
        leftEdge_e_0 <= ($signed(probe_e_0) + $signed(_zz_leftEdge_e_0_6));
        leftEdge_e_1 <= ($signed(probe_e_1) + $signed(_zz_leftEdge_e_1_6));
        leftEdge_e_2 <= ($signed(probe_e_2) + $signed(_zz_leftEdge_e_2_6));
        probe_x <= bookmark_x;
        probe_y <= bookmark_y;
        probe_e_0 <= bookmark_e_0;
        probe_e_1 <= bookmark_e_1;
        probe_e_2 <= bookmark_e_2;
      end
    end
    if(when_SpanWalker_l178) begin
      if(when_SpanWalker_l179) begin
        if(when_SpanWalker_l180) begin
          emitRight <= ($signed(visibleEnd) - $signed(13'h0001));
        end else begin
          probe_x <= ($signed(probe_x) + $signed(13'h0001));
          probe_y <= probe_y;
          probe_e_0 <= ($signed(probe_e_0) + $signed(_zz_probe_e_0_8));
          probe_e_1 <= ($signed(probe_e_1) + $signed(_zz_probe_e_1_8));
          probe_e_2 <= ($signed(probe_e_2) + $signed(_zz_probe_e_2_8));
        end
      end else begin
        emitRight <= ($signed(probe_x) - $signed(13'h0001));
      end
    end
    if(when_SpanWalker_l192) begin
      nextRowBase_x <= leftEdge_x;
      nextRowBase_y <= leftEdge_y;
      nextRowBase_e_0 <= leftEdge_e_0;
      nextRowBase_e_1 <= leftEdge_e_1;
      nextRowBase_e_2 <= leftEdge_e_2;
    end
    if(when_SpanWalker_l197) begin
      if(!when_SpanWalker_l198) begin
        rowGuess_x <= _zz_rowGuess_x;
        rowGuess_y <= _zz_rowGuess_y;
        rowGuess_e_0 <= _zz_rowGuess_e_0;
        rowGuess_e_1 <= _zz_rowGuess_e_1;
        rowGuess_e_2 <= _zz_rowGuess_e_2;
        probe_x <= _zz_rowGuess_x;
        probe_y <= _zz_rowGuess_y;
        probe_e_0 <= _zz_rowGuess_e_0;
        probe_e_1 <= _zz_rowGuess_e_1;
        probe_e_2 <= _zz_rowGuess_e_2;
        bookmark_x <= _zz_rowGuess_x;
        bookmark_y <= _zz_rowGuess_y;
        bookmark_e_0 <= _zz_rowGuess_e_0;
        bookmark_e_1 <= _zz_rowGuess_e_1;
        bookmark_e_2 <= _zz_rowGuess_e_2;
      end
    end
  end


endmodule

module hng64_raster_TriangleSetup (
  input  wire          io_i_valid,
  output wire          io_i_ready,
  input  wire [23:0]   io_i_payload_v_0_0,
  input  wire [23:0]   io_i_payload_v_0_1,
  input  wire [23:0]   io_i_payload_v_1_0,
  input  wire [23:0]   io_i_payload_v_1_1,
  input  wire [23:0]   io_i_payload_v_2_0,
  input  wire [23:0]   io_i_payload_v_2_1,
  input  wire          io_i_payload_neg,
  input  wire [29:0]   io_i_payload_p0_v_0,
  input  wire [33:0]   io_i_payload_p0_v_1,
  input  wire [23:0]   io_i_payload_p0_v_2,
  input  wire [31:0]   io_i_payload_p0_v_3,
  input  wire [31:0]   io_i_payload_p0_v_4,
  input  wire [41:0]   io_i_payload_dx_v_0,
  input  wire [45:0]   io_i_payload_dx_v_1,
  input  wire [35:0]   io_i_payload_dx_v_2,
  input  wire [43:0]   io_i_payload_dx_v_3,
  input  wire [43:0]   io_i_payload_dx_v_4,
  input  wire [41:0]   io_i_payload_dy_v_0,
  input  wire [45:0]   io_i_payload_dy_v_1,
  input  wire [35:0]   io_i_payload_dy_v_2,
  input  wire [43:0]   io_i_payload_dy_v_3,
  input  wire [43:0]   io_i_payload_dy_v_4,
  input  wire [66:0]   io_i_payload_attr,
  output wire          io_o_valid,
  input  wire          io_o_ready,
  output wire [12:0]   io_o_payload_x0,
  output wire [12:0]   io_o_payload_x1,
  output wire [12:0]   io_o_payload_y0,
  output wire [12:0]   io_o_payload_y1,
  output wire [24:0]   io_o_payload_a_0,
  output wire [24:0]   io_o_payload_a_1,
  output wire [24:0]   io_o_payload_a_2,
  output wire [24:0]   io_o_payload_b_0,
  output wire [24:0]   io_o_payload_b_1,
  output wire [24:0]   io_o_payload_b_2,
  output wire [50:0]   io_o_payload_edge_0,
  output wire [50:0]   io_o_payload_edge_1,
  output wire [50:0]   io_o_payload_edge_2,
  output wire [29:0]   io_o_payload_p_v_0,
  output wire [33:0]   io_o_payload_p_v_1,
  output wire [23:0]   io_o_payload_p_v_2,
  output wire [31:0]   io_o_payload_p_v_3,
  output wire [31:0]   io_o_payload_p_v_4,
  output wire [29:0]   io_o_payload_dx_v_0,
  output wire [33:0]   io_o_payload_dx_v_1,
  output wire [23:0]   io_o_payload_dx_v_2,
  output wire [31:0]   io_o_payload_dx_v_3,
  output wire [31:0]   io_o_payload_dx_v_4,
  output wire [29:0]   io_o_payload_dy_v_0,
  output wire [33:0]   io_o_payload_dy_v_1,
  output wire [23:0]   io_o_payload_dy_v_2,
  output wire [31:0]   io_o_payload_dy_v_3,
  output wire [31:0]   io_o_payload_dy_v_4,
  output wire [66:0]   io_o_payload_attr,
  input  wire          clk,
  input  wire          reset
);
  localparam hng64_raster_S_Idle = 3'd0;
  localparam hng64_raster_S_Prep0 = 3'd1;
  localparam hng64_raster_S_Prep = 3'd2;
  localparam hng64_raster_S_Prep2 = 3'd3;
  localparam hng64_raster_S_Mul = 3'd4;
  localparam hng64_raster_S_Done = 3'd5;

  wire       [23:0]   _zz_xmin_3;
  wire       [23:0]   _zz_xmax;
  wire       [24:0]   _zz_arR_0;
  wire       [24:0]   _zz_arR_0_1;
  wire       [24:0]   _zz_brR_0;
  wire       [24:0]   _zz_brR_0_1;
  wire       [24:0]   _zz_arR_1;
  wire       [24:0]   _zz_arR_1_1;
  wire       [24:0]   _zz_brR_1;
  wire       [24:0]   _zz_brR_1_1;
  wire       [24:0]   _zz_arR_2;
  wire       [24:0]   _zz_arR_2_1;
  wire       [24:0]   _zz_brR_2;
  wire       [24:0]   _zz_brR_2_1;
  wire       [24:0]   _zz_xc;
  wire       [24:0]   _zz_xc_1;
  wire       [24:0]   _zz_yc;
  wire       [24:0]   _zz_yc_1;
  wire       [24:0]   _zz__zz_a_0;
  wire       [24:0]   _zz__zz_b_0;
  wire       [24:0]   _zz__zz_a_1;
  wire       [24:0]   _zz__zz_b_1;
  wire       [24:0]   _zz__zz_a_2;
  wire       [24:0]   _zz__zz_b_2;
  wire       [11:0]   _zz_x0Reg;
  wire       [24:0]   _zz_y0Reg;
  wire       [24:0]   _zz_y0Reg_1;
  wire       [11:0]   _zz_out_x0;
  wire       [24:0]   _zz_out_x1;
  wire       [24:0]   _zz_out_x1_1;
  wire       [24:0]   _zz_out_y0;
  wire       [24:0]   _zz_out_y0_1;
  wire       [24:0]   _zz_out_y1;
  wire       [24:0]   _zz_out_y1_1;
  wire       [24:0]   _zz_offX_0;
  wire       [24:0]   _zz_offY_0;
  wire       [24:0]   _zz_offX_1;
  wire       [24:0]   _zz_offY_1;
  wire       [24:0]   _zz_offX_2;
  wire       [24:0]   _zz_offY_2;
  reg        [24:0]   _zz_selX_1;
  reg        [24:0]   _zz_selY;
  reg        [45:0]   _zz_selCX;
  reg        [45:0]   _zz_selCY;
  wire       [71:0]   _zz__zz_out_edge_0;
  wire       [71:0]   _zz__zz_out_edge_0_1;
  wire       [71:0]   _zz_out_edge_0_1;
  wire       [71:0]   _zz_out_edge_0_2;
  wire       [71:0]   _zz_out_edge_1;
  wire       [71:0]   _zz_out_edge_1_1;
  wire       [71:0]   _zz_out_edge_2;
  wire       [71:0]   _zz_out_edge_2_1;
  wire       [29:0]   _zz_out_p_v_0;
  wire       [59:0]   _zz_out_p_v_0_1;
  wire       [33:0]   _zz_out_p_v_1;
  wire       [59:0]   _zz_out_p_v_1_1;
  wire       [23:0]   _zz_out_p_v_2;
  wire       [59:0]   _zz_out_p_v_2_1;
  wire       [31:0]   _zz_out_p_v_3;
  wire       [59:0]   _zz_out_p_v_3_1;
  wire       [31:0]   _zz_out_p_v_4;
  wire       [59:0]   _zz_out_p_v_4_1;
  reg        [2:0]    state;
  reg        [12:0]   out_x0;
  reg        [12:0]   out_x1;
  reg        [12:0]   out_y0;
  reg        [12:0]   out_y1;
  reg        [24:0]   out_a_0;
  reg        [24:0]   out_a_1;
  reg        [24:0]   out_a_2;
  reg        [24:0]   out_b_0;
  reg        [24:0]   out_b_1;
  reg        [24:0]   out_b_2;
  reg        [50:0]   out_edge_0;
  reg        [50:0]   out_edge_1;
  reg        [50:0]   out_edge_2;
  reg        [29:0]   out_p_v_0;
  reg        [33:0]   out_p_v_1;
  reg        [23:0]   out_p_v_2;
  reg        [31:0]   out_p_v_3;
  reg        [31:0]   out_p_v_4;
  reg        [29:0]   out_dx_v_0;
  reg        [33:0]   out_dx_v_1;
  reg        [23:0]   out_dx_v_2;
  reg        [31:0]   out_dx_v_3;
  reg        [31:0]   out_dx_v_4;
  reg        [29:0]   out_dy_v_0;
  reg        [33:0]   out_dy_v_1;
  reg        [23:0]   out_dy_v_2;
  reg        [31:0]   out_dy_v_3;
  reg        [31:0]   out_dy_v_4;
  reg        [66:0]   out_attr;
  wire                when_TriangleSetup_l39;
  reg        [23:0]   xmin;
  reg        [23:0]   xmax;
  reg        [24:0]   arR_0;
  reg        [24:0]   arR_1;
  reg        [24:0]   arR_2;
  reg        [24:0]   brR_0;
  reg        [24:0]   brR_1;
  reg        [24:0]   brR_2;
  wire                when_TriangleSetup_l57;
  wire                _zz_xmin;
  wire                _zz_xmin_1;
  wire                _zz_xmin_2;
  reg        [12:0]   x0Reg;
  reg        [12:0]   y0Reg;
  wire       [24:0]   xc;
  wire       [24:0]   yc;
  reg        [24:0]   a_0;
  reg        [24:0]   a_1;
  reg        [24:0]   a_2;
  reg        [24:0]   b_0;
  reg        [24:0]   b_1;
  reg        [24:0]   b_2;
  reg        [2:0]    bias;
  reg        [24:0]   offX_0;
  reg        [24:0]   offX_1;
  reg        [24:0]   offX_2;
  reg        [24:0]   offY_0;
  reg        [24:0]   offY_1;
  reg        [24:0]   offY_2;
  wire                when_TriangleSetup_l82;
  wire       [24:0]   _zz_a_0;
  wire       [24:0]   _zz_b_0;
  wire       [24:0]   _zz_a_1;
  wire       [24:0]   _zz_b_1;
  wire       [24:0]   _zz_a_2;
  wire       [24:0]   _zz_b_2;
  wire                when_TriangleSetup_l103;
  reg        [3:0]    idx;
  reg        [3:0]    pIdx;
  reg                 pValid;
  reg        [70:0]   prodX;
  reg        [70:0]   prodY;
  wire       [45:0]   coefX_0;
  wire       [45:0]   coefX_1;
  wire       [45:0]   coefX_2;
  wire       [45:0]   coefX_3;
  wire       [45:0]   coefX_4;
  wire       [45:0]   coefX_5;
  wire       [45:0]   coefX_6;
  wire       [45:0]   coefX_7;
  wire       [45:0]   coefY_0;
  wire       [45:0]   coefY_1;
  wire       [45:0]   coefY_2;
  wire       [45:0]   coefY_3;
  wire       [45:0]   coefY_4;
  wire       [45:0]   coefY_5;
  wire       [45:0]   coefY_6;
  wire       [45:0]   coefY_7;
  wire       [24:0]   mOffX_0;
  wire       [24:0]   mOffX_1;
  wire       [24:0]   mOffX_2;
  wire       [24:0]   mOffX_3;
  wire       [24:0]   mOffX_4;
  wire       [24:0]   mOffX_5;
  wire       [24:0]   mOffX_6;
  wire       [24:0]   mOffX_7;
  wire       [24:0]   mOffY_0;
  wire       [24:0]   mOffY_1;
  wire       [24:0]   mOffY_2;
  wire       [24:0]   mOffY_3;
  wire       [24:0]   mOffY_4;
  wire       [24:0]   mOffY_5;
  wire       [24:0]   mOffY_6;
  wire       [24:0]   mOffY_7;
  reg        [24:0]   selX;
  reg        [24:0]   selY;
  reg        [45:0]   selCX;
  reg        [45:0]   selCY;
  reg        [3:0]    selIdx;
  reg                 selValid;
  wire                when_TriangleSetup_l143;
  wire                when_TriangleSetup_l144;
  wire       [2:0]    _zz_selX;
  wire       [71:0]   _zz_out_edge_0;
  wire                when_TriangleSetup_l162;
  wire                when_TriangleSetup_l162_1;
  wire                when_TriangleSetup_l162_2;
  wire                when_TriangleSetup_l165;
  wire                when_TriangleSetup_l165_1;
  wire                when_TriangleSetup_l165_2;
  wire                when_TriangleSetup_l165_3;
  wire                when_TriangleSetup_l165_4;
  wire                when_TriangleSetup_l168;
  wire                when_TriangleSetup_l179;
  `ifndef SYNTHESIS
  reg [39:0] state_string;
  `endif


  assign _zz_xmin_3 = (((! _zz_xmin) && _zz_xmin_2) ? io_i_payload_v_1_0 : io_i_payload_v_2_0);
  assign _zz_xmax = ((_zz_xmin && (! _zz_xmin_2)) ? io_i_payload_v_1_0 : io_i_payload_v_2_0);
  assign _zz_arR_0 = {{1{io_i_payload_v_0_1[23]}}, io_i_payload_v_0_1};
  assign _zz_arR_0_1 = {{1{io_i_payload_v_1_1[23]}}, io_i_payload_v_1_1};
  assign _zz_brR_0 = {{1{io_i_payload_v_1_0[23]}}, io_i_payload_v_1_0};
  assign _zz_brR_0_1 = {{1{io_i_payload_v_0_0[23]}}, io_i_payload_v_0_0};
  assign _zz_arR_1 = {{1{io_i_payload_v_1_1[23]}}, io_i_payload_v_1_1};
  assign _zz_arR_1_1 = {{1{io_i_payload_v_2_1[23]}}, io_i_payload_v_2_1};
  assign _zz_brR_1 = {{1{io_i_payload_v_2_0[23]}}, io_i_payload_v_2_0};
  assign _zz_brR_1_1 = {{1{io_i_payload_v_1_0[23]}}, io_i_payload_v_1_0};
  assign _zz_arR_2 = {{1{io_i_payload_v_2_1[23]}}, io_i_payload_v_2_1};
  assign _zz_arR_2_1 = {{1{io_i_payload_v_0_1[23]}}, io_i_payload_v_0_1};
  assign _zz_brR_2 = {{1{io_i_payload_v_0_0[23]}}, io_i_payload_v_0_0};
  assign _zz_brR_2_1 = {{1{io_i_payload_v_2_0[23]}}, io_i_payload_v_2_0};
  assign _zz_xc = (_zz_xc_1 <<< 12);
  assign _zz_xc_1 = {{12{x0Reg[12]}}, x0Reg};
  assign _zz_yc = (_zz_yc_1 <<< 12);
  assign _zz_yc_1 = {{12{y0Reg[12]}}, y0Reg};
  assign _zz__zz_a_0 = (- arR_0);
  assign _zz__zz_b_0 = (- brR_0);
  assign _zz__zz_a_1 = (- arR_1);
  assign _zz__zz_b_1 = (- brR_1);
  assign _zz__zz_a_2 = (- arR_2);
  assign _zz__zz_b_2 = (- brR_2);
  assign _zz_x0Reg = (xmin >>> 4'd12);
  assign _zz_y0Reg = ($signed(_zz_y0Reg_1) + $signed(25'h00007ff));
  assign _zz_y0Reg_1 = {{1{io_i_payload_v_0_1[23]}}, io_i_payload_v_0_1};
  assign _zz_out_x0 = (xmin >>> 4'd12);
  assign _zz_out_x1 = ($signed(_zz_out_x1_1) + $signed(25'h0000fff));
  assign _zz_out_x1_1 = {{1{xmax[23]}}, xmax};
  assign _zz_out_y0 = ($signed(_zz_out_y0_1) + $signed(25'h00007ff));
  assign _zz_out_y0_1 = {{1{io_i_payload_v_0_1[23]}}, io_i_payload_v_0_1};
  assign _zz_out_y1 = ($signed(_zz_out_y1_1) + $signed(25'h00007ff));
  assign _zz_out_y1_1 = {{1{io_i_payload_v_2_1[23]}}, io_i_payload_v_2_1};
  assign _zz_offX_0 = {{1{io_i_payload_v_0_0[23]}}, io_i_payload_v_0_0};
  assign _zz_offY_0 = {{1{io_i_payload_v_0_1[23]}}, io_i_payload_v_0_1};
  assign _zz_offX_1 = {{1{io_i_payload_v_1_0[23]}}, io_i_payload_v_1_0};
  assign _zz_offY_1 = {{1{io_i_payload_v_1_1[23]}}, io_i_payload_v_1_1};
  assign _zz_offX_2 = {{1{io_i_payload_v_2_0[23]}}, io_i_payload_v_2_0};
  assign _zz_offY_2 = {{1{io_i_payload_v_2_1[23]}}, io_i_payload_v_2_1};
  assign _zz__zz_out_edge_0 = {{1{prodX[70]}}, prodX};
  assign _zz__zz_out_edge_0_1 = {{1{prodY[70]}}, prodY};
  assign _zz_out_edge_0_1 = (bias[0] ? _zz_out_edge_0_2 : _zz_out_edge_0);
  assign _zz_out_edge_0_2 = ($signed(_zz_out_edge_0) - $signed(72'h000000000000000001));
  assign _zz_out_edge_1 = (bias[1] ? _zz_out_edge_1_1 : _zz_out_edge_0);
  assign _zz_out_edge_1_1 = ($signed(_zz_out_edge_0) - $signed(72'h000000000000000001));
  assign _zz_out_edge_2 = (bias[2] ? _zz_out_edge_2_1 : _zz_out_edge_0);
  assign _zz_out_edge_2_1 = ($signed(_zz_out_edge_0) - $signed(72'h000000000000000001));
  assign _zz_out_p_v_0_1 = (_zz_out_edge_0 >>> 4'd12);
  assign _zz_out_p_v_0 = _zz_out_p_v_0_1[29:0];
  assign _zz_out_p_v_1_1 = (_zz_out_edge_0 >>> 4'd12);
  assign _zz_out_p_v_1 = _zz_out_p_v_1_1[33:0];
  assign _zz_out_p_v_2_1 = (_zz_out_edge_0 >>> 4'd12);
  assign _zz_out_p_v_2 = _zz_out_p_v_2_1[23:0];
  assign _zz_out_p_v_3_1 = (_zz_out_edge_0 >>> 4'd12);
  assign _zz_out_p_v_3 = _zz_out_p_v_3_1[31:0];
  assign _zz_out_p_v_4_1 = (_zz_out_edge_0 >>> 4'd12);
  assign _zz_out_p_v_4 = _zz_out_p_v_4_1[31:0];
  always @(*) begin
    case(_zz_selX)
      3'b000 : begin
        _zz_selX_1 = mOffX_0;
        _zz_selY = mOffY_0;
        _zz_selCX = coefX_0;
        _zz_selCY = coefY_0;
      end
      3'b001 : begin
        _zz_selX_1 = mOffX_1;
        _zz_selY = mOffY_1;
        _zz_selCX = coefX_1;
        _zz_selCY = coefY_1;
      end
      3'b010 : begin
        _zz_selX_1 = mOffX_2;
        _zz_selY = mOffY_2;
        _zz_selCX = coefX_2;
        _zz_selCY = coefY_2;
      end
      3'b011 : begin
        _zz_selX_1 = mOffX_3;
        _zz_selY = mOffY_3;
        _zz_selCX = coefX_3;
        _zz_selCY = coefY_3;
      end
      3'b100 : begin
        _zz_selX_1 = mOffX_4;
        _zz_selY = mOffY_4;
        _zz_selCX = coefX_4;
        _zz_selCY = coefY_4;
      end
      3'b101 : begin
        _zz_selX_1 = mOffX_5;
        _zz_selY = mOffY_5;
        _zz_selCX = coefX_5;
        _zz_selCY = coefY_5;
      end
      3'b110 : begin
        _zz_selX_1 = mOffX_6;
        _zz_selY = mOffY_6;
        _zz_selCX = coefX_6;
        _zz_selCY = coefY_6;
      end
      default : begin
        _zz_selX_1 = mOffX_7;
        _zz_selY = mOffY_7;
        _zz_selCX = coefX_7;
        _zz_selCY = coefY_7;
      end
    endcase
  end

  `ifndef SYNTHESIS
  always @(*) begin
    case(state)
      hng64_raster_S_Idle : state_string = "Idle ";
      hng64_raster_S_Prep0 : state_string = "Prep0";
      hng64_raster_S_Prep : state_string = "Prep ";
      hng64_raster_S_Prep2 : state_string = "Prep2";
      hng64_raster_S_Mul : state_string = "Mul  ";
      hng64_raster_S_Done : state_string = "Done ";
      default : state_string = "?????";
    endcase
  end
  `endif

  assign io_i_ready = ((state == hng64_raster_S_Done) && io_o_ready);
  assign io_o_valid = (state == hng64_raster_S_Done);
  assign io_o_payload_x0 = out_x0;
  assign io_o_payload_x1 = out_x1;
  assign io_o_payload_y0 = out_y0;
  assign io_o_payload_y1 = out_y1;
  assign io_o_payload_a_0 = out_a_0;
  assign io_o_payload_a_1 = out_a_1;
  assign io_o_payload_a_2 = out_a_2;
  assign io_o_payload_b_0 = out_b_0;
  assign io_o_payload_b_1 = out_b_1;
  assign io_o_payload_b_2 = out_b_2;
  assign io_o_payload_edge_0 = out_edge_0;
  assign io_o_payload_edge_1 = out_edge_1;
  assign io_o_payload_edge_2 = out_edge_2;
  assign io_o_payload_p_v_0 = out_p_v_0;
  assign io_o_payload_p_v_1 = out_p_v_1;
  assign io_o_payload_p_v_2 = out_p_v_2;
  assign io_o_payload_p_v_3 = out_p_v_3;
  assign io_o_payload_p_v_4 = out_p_v_4;
  assign io_o_payload_dx_v_0 = out_dx_v_0;
  assign io_o_payload_dx_v_1 = out_dx_v_1;
  assign io_o_payload_dx_v_2 = out_dx_v_2;
  assign io_o_payload_dx_v_3 = out_dx_v_3;
  assign io_o_payload_dx_v_4 = out_dx_v_4;
  assign io_o_payload_dy_v_0 = out_dy_v_0;
  assign io_o_payload_dy_v_1 = out_dy_v_1;
  assign io_o_payload_dy_v_2 = out_dy_v_2;
  assign io_o_payload_dy_v_3 = out_dy_v_3;
  assign io_o_payload_dy_v_4 = out_dy_v_4;
  assign io_o_payload_attr = out_attr;
  assign when_TriangleSetup_l39 = ((state == hng64_raster_S_Idle) && io_i_valid);
  assign when_TriangleSetup_l57 = (state == hng64_raster_S_Prep0);
  assign _zz_xmin = ($signed(io_i_payload_v_0_0) < $signed(io_i_payload_v_1_0));
  assign _zz_xmin_1 = ($signed(io_i_payload_v_0_0) < $signed(io_i_payload_v_2_0));
  assign _zz_xmin_2 = ($signed(io_i_payload_v_1_0) < $signed(io_i_payload_v_2_0));
  assign xc = ($signed(_zz_xc) + $signed(25'h0000800));
  assign yc = ($signed(_zz_yc) + $signed(25'h0000800));
  assign when_TriangleSetup_l82 = (state == hng64_raster_S_Prep);
  assign _zz_a_0 = (io_i_payload_neg ? _zz__zz_a_0 : arR_0);
  assign _zz_b_0 = (io_i_payload_neg ? _zz__zz_b_0 : brR_0);
  assign _zz_a_1 = (io_i_payload_neg ? _zz__zz_a_1 : arR_1);
  assign _zz_b_1 = (io_i_payload_neg ? _zz__zz_b_1 : brR_1);
  assign _zz_a_2 = (io_i_payload_neg ? _zz__zz_a_2 : arR_2);
  assign _zz_b_2 = (io_i_payload_neg ? _zz__zz_b_2 : brR_2);
  assign when_TriangleSetup_l103 = (state == hng64_raster_S_Prep2);
  assign coefX_0 = {{21{a_0[24]}}, a_0};
  assign coefY_0 = {{21{b_0[24]}}, b_0};
  assign mOffX_0 = offX_0;
  assign mOffY_0 = offY_0;
  assign coefX_1 = {{21{a_1[24]}}, a_1};
  assign coefY_1 = {{21{b_1[24]}}, b_1};
  assign mOffX_1 = offX_1;
  assign mOffY_1 = offY_1;
  assign coefX_2 = {{21{a_2[24]}}, a_2};
  assign coefY_2 = {{21{b_2[24]}}, b_2};
  assign mOffX_2 = offX_2;
  assign mOffY_2 = offY_2;
  assign coefX_3 = {{4{io_i_payload_dx_v_0[41]}}, io_i_payload_dx_v_0};
  assign coefY_3 = {{4{io_i_payload_dy_v_0[41]}}, io_i_payload_dy_v_0};
  assign mOffX_3 = offX_0;
  assign mOffY_3 = offY_0;
  assign coefX_4 = io_i_payload_dx_v_1;
  assign coefY_4 = io_i_payload_dy_v_1;
  assign mOffX_4 = offX_0;
  assign mOffY_4 = offY_0;
  assign coefX_5 = {{10{io_i_payload_dx_v_2[35]}}, io_i_payload_dx_v_2};
  assign coefY_5 = {{10{io_i_payload_dy_v_2[35]}}, io_i_payload_dy_v_2};
  assign mOffX_5 = offX_0;
  assign mOffY_5 = offY_0;
  assign coefX_6 = {{2{io_i_payload_dx_v_3[43]}}, io_i_payload_dx_v_3};
  assign coefY_6 = {{2{io_i_payload_dy_v_3[43]}}, io_i_payload_dy_v_3};
  assign mOffX_6 = offX_0;
  assign mOffY_6 = offY_0;
  assign coefX_7 = {{2{io_i_payload_dx_v_4[43]}}, io_i_payload_dx_v_4};
  assign coefY_7 = {{2{io_i_payload_dy_v_4[43]}}, io_i_payload_dy_v_4};
  assign mOffX_7 = offX_0;
  assign mOffY_7 = offY_0;
  assign when_TriangleSetup_l143 = (state == hng64_raster_S_Mul);
  assign when_TriangleSetup_l144 = (idx < 4'b1000);
  assign _zz_selX = idx[2:0];
  assign _zz_out_edge_0 = ($signed(_zz__zz_out_edge_0) + $signed(_zz__zz_out_edge_0_1));
  assign when_TriangleSetup_l162 = (pIdx == 4'b0000);
  assign when_TriangleSetup_l162_1 = (pIdx == 4'b0001);
  assign when_TriangleSetup_l162_2 = (pIdx == 4'b0010);
  assign when_TriangleSetup_l165 = (pIdx == 4'b0011);
  assign when_TriangleSetup_l165_1 = (pIdx == 4'b0100);
  assign when_TriangleSetup_l165_2 = (pIdx == 4'b0101);
  assign when_TriangleSetup_l165_3 = (pIdx == 4'b0110);
  assign when_TriangleSetup_l165_4 = (pIdx == 4'b0111);
  assign when_TriangleSetup_l168 = (pIdx == 4'b0111);
  assign when_TriangleSetup_l179 = ((state == hng64_raster_S_Done) && io_o_ready);
  always @(posedge clk) begin
    if(reset) begin
      state <= hng64_raster_S_Idle;
      idx <= 4'b0000;
      pIdx <= 4'b0000;
      pValid <= 1'b0;
      selValid <= 1'b0;
    end else begin
      if(when_TriangleSetup_l39) begin
        state <= hng64_raster_S_Prep0;
      end
      if(when_TriangleSetup_l57) begin
        state <= hng64_raster_S_Prep;
      end
      if(when_TriangleSetup_l82) begin
        state <= hng64_raster_S_Prep2;
      end
      if(when_TriangleSetup_l103) begin
        state <= hng64_raster_S_Mul;
      end
      pValid <= 1'b0;
      selValid <= 1'b0;
      if(when_TriangleSetup_l143) begin
        if(when_TriangleSetup_l144) begin
          selValid <= 1'b1;
          idx <= (idx + 4'b0001);
        end
        if(selValid) begin
          pIdx <= selIdx;
          pValid <= 1'b1;
        end
        if(pValid) begin
          if(when_TriangleSetup_l168) begin
            idx <= 4'b0000;
            state <= hng64_raster_S_Done;
          end
        end
      end
      if(when_TriangleSetup_l179) begin
        state <= hng64_raster_S_Idle;
      end
    end
  end

  always @(posedge clk) begin
    if(when_TriangleSetup_l57) begin
      xmin <= ((_zz_xmin && _zz_xmin_1) ? io_i_payload_v_0_0 : _zz_xmin_3);
      xmax <= (((! _zz_xmin) && (! _zz_xmin_1)) ? io_i_payload_v_0_0 : _zz_xmax);
      arR_0 <= ($signed(_zz_arR_0) - $signed(_zz_arR_0_1));
      brR_0 <= ($signed(_zz_brR_0) - $signed(_zz_brR_0_1));
      arR_1 <= ($signed(_zz_arR_1) - $signed(_zz_arR_1_1));
      brR_1 <= ($signed(_zz_brR_1) - $signed(_zz_brR_1_1));
      arR_2 <= ($signed(_zz_arR_2) - $signed(_zz_arR_2_1));
      brR_2 <= ($signed(_zz_brR_2) - $signed(_zz_brR_2_1));
    end
    if(when_TriangleSetup_l82) begin
      a_0 <= _zz_a_0;
      b_0 <= _zz_b_0;
      bias[0] <= (! (($signed(25'h0) < $signed(_zz_a_0)) || (($signed(_zz_a_0) == $signed(25'h0)) && ($signed(25'h0) < $signed(_zz_b_0)))));
      a_1 <= _zz_a_1;
      b_1 <= _zz_b_1;
      bias[1] <= (! (($signed(25'h0) < $signed(_zz_a_1)) || (($signed(_zz_a_1) == $signed(25'h0)) && ($signed(25'h0) < $signed(_zz_b_1)))));
      a_2 <= _zz_a_2;
      b_2 <= _zz_b_2;
      bias[2] <= (! (($signed(25'h0) < $signed(_zz_a_2)) || (($signed(_zz_a_2) == $signed(25'h0)) && ($signed(25'h0) < $signed(_zz_b_2)))));
      x0Reg <= {{1{_zz_x0Reg[11]}}, _zz_x0Reg};
      y0Reg <= (_zz_y0Reg >>> 4'd12);
      out_x0 <= {{1{_zz_out_x0[11]}}, _zz_out_x0};
      out_x1 <= (_zz_out_x1 >>> 4'd12);
      out_y0 <= (_zz_out_y0 >>> 4'd12);
      out_y1 <= (_zz_out_y1 >>> 4'd12);
      out_attr <= io_i_payload_attr;
      out_dx_v_0 <= io_i_payload_dx_v_0[29:0];
      out_dy_v_0 <= io_i_payload_dy_v_0[29:0];
      out_dx_v_1 <= io_i_payload_dx_v_1[33:0];
      out_dy_v_1 <= io_i_payload_dy_v_1[33:0];
      out_dx_v_2 <= io_i_payload_dx_v_2[23:0];
      out_dy_v_2 <= io_i_payload_dy_v_2[23:0];
      out_dx_v_3 <= io_i_payload_dx_v_3[31:0];
      out_dy_v_3 <= io_i_payload_dy_v_3[31:0];
      out_dx_v_4 <= io_i_payload_dx_v_4[31:0];
      out_dy_v_4 <= io_i_payload_dy_v_4[31:0];
    end
    if(when_TriangleSetup_l103) begin
      offX_0 <= ($signed(xc) - $signed(_zz_offX_0));
      offY_0 <= ($signed(yc) - $signed(_zz_offY_0));
      offX_1 <= ($signed(xc) - $signed(_zz_offX_1));
      offY_1 <= ($signed(yc) - $signed(_zz_offY_1));
      offX_2 <= ($signed(xc) - $signed(_zz_offX_2));
      offY_2 <= ($signed(yc) - $signed(_zz_offY_2));
    end
    if(when_TriangleSetup_l143) begin
      if(when_TriangleSetup_l144) begin
        selX <= _zz_selX_1;
        selY <= _zz_selY;
        selCX <= _zz_selCX;
        selCY <= _zz_selCY;
        selIdx <= idx;
      end
      if(selValid) begin
        prodX <= ($signed(selX) * $signed(selCX));
        prodY <= ($signed(selY) * $signed(selCY));
      end
      if(pValid) begin
        if(when_TriangleSetup_l162) begin
          out_edge_0 <= _zz_out_edge_0_1[50:0];
        end
        if(when_TriangleSetup_l162_1) begin
          out_edge_1 <= _zz_out_edge_1[50:0];
        end
        if(when_TriangleSetup_l162_2) begin
          out_edge_2 <= _zz_out_edge_2[50:0];
        end
        if(when_TriangleSetup_l165) begin
          out_p_v_0 <= ($signed(io_i_payload_p0_v_0) + $signed(_zz_out_p_v_0));
        end
        if(when_TriangleSetup_l165_1) begin
          out_p_v_1 <= ($signed(io_i_payload_p0_v_1) + $signed(_zz_out_p_v_1));
        end
        if(when_TriangleSetup_l165_2) begin
          out_p_v_2 <= ($signed(io_i_payload_p0_v_2) + $signed(_zz_out_p_v_2));
        end
        if(when_TriangleSetup_l165_3) begin
          out_p_v_3 <= ($signed(io_i_payload_p0_v_3) + $signed(_zz_out_p_v_3));
        end
        if(when_TriangleSetup_l165_4) begin
          out_p_v_4 <= ($signed(io_i_payload_p0_v_4) + $signed(_zz_out_p_v_4));
        end
      end
    end
    out_a_0 <= a_0;
    out_b_0 <= b_0;
    out_a_1 <= a_1;
    out_b_1 <= b_1;
    out_a_2 <= a_2;
    out_b_2 <= b_2;
  end


endmodule

module hng64_raster_StreamFifo_6 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [511:0]  io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [511:0]  io_pop_payload,
  input  wire          io_flush,
  output wire [3:0]    io_occupancy,
  output wire [3:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [511:0]  logic_ram_spinal_port1;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [3:0]    logic_ptr_push;
  reg        [3:0]    logic_ptr_pop;
  wire       [3:0]    logic_ptr_occupancy;
  wire       [3:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [2:0]    logic_push_onRam_write_payload_address;
  wire       [511:0]  logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [2:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [2:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [2:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [2:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [511:0]  logic_pop_sync_readPort_rsp;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [2:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [511:0]  logic_pop_sync_readArbitation_translated_payload;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [3:0]    logic_pop_sync_popReg;
  reg [511:0] logic_ram [0:7];

  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= logic_push_onRam_write_payload_data;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 4'b1000) == 4'b0000);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[2:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[2:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign logic_pop_sync_readPort_rsp = logic_ram_spinal_port1;
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload = logic_pop_sync_readPort_rsp;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = logic_pop_sync_readArbitation_translated_payload;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (4'b1000 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 4'b0000;
      logic_ptr_pop <= 4'b0000;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 4'b0000;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 4'b0001);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 4'b0001);
      end
      if(io_flush) begin
        logic_ptr_push <= 4'b0000;
        logic_ptr_pop <= 4'b0000;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 4'b0000;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_StreamFifo_5 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [13:0]   io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [13:0]   io_pop_payload,
  input  wire          io_flush,
  output wire [3:0]    io_occupancy,
  output wire [3:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [13:0]   logic_ram_spinal_port1;
  wire       [13:0]   _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [3:0]    logic_ptr_push;
  reg        [3:0]    logic_ptr_pop;
  wire       [3:0]    logic_ptr_occupancy;
  wire       [3:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [2:0]    logic_push_onRam_write_payload_address;
  wire       [13:0]   logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [2:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [2:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [2:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [2:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [13:0]   logic_pop_sync_readPort_rsp;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [2:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [13:0]   logic_pop_sync_readArbitation_translated_payload;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [3:0]    logic_pop_sync_popReg;
  reg [13:0] logic_ram [0:7];

  assign _zz_logic_ram_port = logic_push_onRam_write_payload_data;
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 4'b1000) == 4'b0000);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[2:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[2:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign logic_pop_sync_readPort_rsp = logic_ram_spinal_port1;
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload = logic_pop_sync_readPort_rsp;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = logic_pop_sync_readArbitation_translated_payload;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (4'b1000 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 4'b0000;
      logic_ptr_pop <= 4'b0000;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 4'b0000;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 4'b0001);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 4'b0001);
      end
      if(io_flush) begin
        logic_ptr_push <= 4'b0000;
        logic_ptr_pop <= 4'b0000;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 4'b0000;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_StreamFifo_4 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [8:0]    io_push_payload_f_x,
  input  wire [8:0]    io_push_payload_f_y,
  input  wire [23:0]   io_push_payload_f_z,
  input  wire [15:0]   io_push_payload_f_colour,
  input  wire [3:0]    io_push_payload_slot,
  input  wire          io_push_payload_miss,
  input  wire          io_push_payload_victim,
  input  wire [13:0]   io_push_payload_vLine,
  input  wire [2:0]    io_push_payload_pend,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [8:0]    io_pop_payload_f_x,
  output wire [8:0]    io_pop_payload_f_y,
  output wire [23:0]   io_pop_payload_f_z,
  output wire [15:0]   io_pop_payload_f_colour,
  output wire [3:0]    io_pop_payload_slot,
  output wire          io_pop_payload_miss,
  output wire          io_pop_payload_victim,
  output wire [13:0]   io_pop_payload_vLine,
  output wire [2:0]    io_pop_payload_pend,
  input  wire          io_flush,
  output wire [6:0]    io_occupancy,
  output wire [6:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [80:0]   logic_ram_spinal_port1;
  wire       [80:0]   _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [6:0]    logic_ptr_push;
  reg        [6:0]    logic_ptr_pop;
  wire       [6:0]    logic_ptr_occupancy;
  wire       [6:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [5:0]    logic_push_onRam_write_payload_address;
  wire       [8:0]    logic_push_onRam_write_payload_data_f_x;
  wire       [8:0]    logic_push_onRam_write_payload_data_f_y;
  wire       [23:0]   logic_push_onRam_write_payload_data_f_z;
  wire       [15:0]   logic_push_onRam_write_payload_data_f_colour;
  wire       [3:0]    logic_push_onRam_write_payload_data_slot;
  wire                logic_push_onRam_write_payload_data_miss;
  wire                logic_push_onRam_write_payload_data_victim;
  wire       [13:0]   logic_push_onRam_write_payload_data_vLine;
  wire       [2:0]    logic_push_onRam_write_payload_data_pend;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [5:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [5:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [5:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [5:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [8:0]    logic_pop_sync_readPort_rsp_f_x;
  wire       [8:0]    logic_pop_sync_readPort_rsp_f_y;
  wire       [23:0]   logic_pop_sync_readPort_rsp_f_z;
  wire       [15:0]   logic_pop_sync_readPort_rsp_f_colour;
  wire       [3:0]    logic_pop_sync_readPort_rsp_slot;
  wire                logic_pop_sync_readPort_rsp_miss;
  wire                logic_pop_sync_readPort_rsp_victim;
  wire       [13:0]   logic_pop_sync_readPort_rsp_vLine;
  wire       [2:0]    logic_pop_sync_readPort_rsp_pend;
  wire       [80:0]   _zz_logic_pop_sync_readPort_rsp_slot;
  wire       [57:0]   _zz_logic_pop_sync_readPort_rsp_f_x;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [5:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_f_x;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_f_y;
  wire       [23:0]   logic_pop_sync_readArbitation_translated_payload_f_z;
  wire       [15:0]   logic_pop_sync_readArbitation_translated_payload_f_colour;
  wire       [3:0]    logic_pop_sync_readArbitation_translated_payload_slot;
  wire                logic_pop_sync_readArbitation_translated_payload_miss;
  wire                logic_pop_sync_readArbitation_translated_payload_victim;
  wire       [13:0]   logic_pop_sync_readArbitation_translated_payload_vLine;
  wire       [2:0]    logic_pop_sync_readArbitation_translated_payload_pend;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [6:0]    logic_pop_sync_popReg;
  reg [80:0] logic_ram [0:63];

  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_pend,{logic_push_onRam_write_payload_data_vLine,{logic_push_onRam_write_payload_data_victim,{logic_push_onRam_write_payload_data_miss,{logic_push_onRam_write_payload_data_slot,{logic_push_onRam_write_payload_data_f_colour,{logic_push_onRam_write_payload_data_f_z,{logic_push_onRam_write_payload_data_f_y,logic_push_onRam_write_payload_data_f_x}}}}}}}};
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 7'h40) == 7'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[5:0];
  assign logic_push_onRam_write_payload_data_f_x = io_push_payload_f_x;
  assign logic_push_onRam_write_payload_data_f_y = io_push_payload_f_y;
  assign logic_push_onRam_write_payload_data_f_z = io_push_payload_f_z;
  assign logic_push_onRam_write_payload_data_f_colour = io_push_payload_f_colour;
  assign logic_push_onRam_write_payload_data_slot = io_push_payload_slot;
  assign logic_push_onRam_write_payload_data_miss = io_push_payload_miss;
  assign logic_push_onRam_write_payload_data_victim = io_push_payload_victim;
  assign logic_push_onRam_write_payload_data_vLine = io_push_payload_vLine;
  assign logic_push_onRam_write_payload_data_pend = io_push_payload_pend;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[5:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign _zz_logic_pop_sync_readPort_rsp_slot = logic_ram_spinal_port1;
  assign _zz_logic_pop_sync_readPort_rsp_f_x = _zz_logic_pop_sync_readPort_rsp_slot[57 : 0];
  assign logic_pop_sync_readPort_rsp_f_x = _zz_logic_pop_sync_readPort_rsp_f_x[8 : 0];
  assign logic_pop_sync_readPort_rsp_f_y = _zz_logic_pop_sync_readPort_rsp_f_x[17 : 9];
  assign logic_pop_sync_readPort_rsp_f_z = _zz_logic_pop_sync_readPort_rsp_f_x[41 : 18];
  assign logic_pop_sync_readPort_rsp_f_colour = _zz_logic_pop_sync_readPort_rsp_f_x[57 : 42];
  assign logic_pop_sync_readPort_rsp_slot = _zz_logic_pop_sync_readPort_rsp_slot[61 : 58];
  assign logic_pop_sync_readPort_rsp_miss = _zz_logic_pop_sync_readPort_rsp_slot[62];
  assign logic_pop_sync_readPort_rsp_victim = _zz_logic_pop_sync_readPort_rsp_slot[63];
  assign logic_pop_sync_readPort_rsp_vLine = _zz_logic_pop_sync_readPort_rsp_slot[77 : 64];
  assign logic_pop_sync_readPort_rsp_pend = _zz_logic_pop_sync_readPort_rsp_slot[80 : 78];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_f_x = logic_pop_sync_readPort_rsp_f_x;
  assign logic_pop_sync_readArbitation_translated_payload_f_y = logic_pop_sync_readPort_rsp_f_y;
  assign logic_pop_sync_readArbitation_translated_payload_f_z = logic_pop_sync_readPort_rsp_f_z;
  assign logic_pop_sync_readArbitation_translated_payload_f_colour = logic_pop_sync_readPort_rsp_f_colour;
  assign logic_pop_sync_readArbitation_translated_payload_slot = logic_pop_sync_readPort_rsp_slot;
  assign logic_pop_sync_readArbitation_translated_payload_miss = logic_pop_sync_readPort_rsp_miss;
  assign logic_pop_sync_readArbitation_translated_payload_victim = logic_pop_sync_readPort_rsp_victim;
  assign logic_pop_sync_readArbitation_translated_payload_vLine = logic_pop_sync_readPort_rsp_vLine;
  assign logic_pop_sync_readArbitation_translated_payload_pend = logic_pop_sync_readPort_rsp_pend;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_f_x = logic_pop_sync_readArbitation_translated_payload_f_x;
  assign io_pop_payload_f_y = logic_pop_sync_readArbitation_translated_payload_f_y;
  assign io_pop_payload_f_z = logic_pop_sync_readArbitation_translated_payload_f_z;
  assign io_pop_payload_f_colour = logic_pop_sync_readArbitation_translated_payload_f_colour;
  assign io_pop_payload_slot = logic_pop_sync_readArbitation_translated_payload_slot;
  assign io_pop_payload_miss = logic_pop_sync_readArbitation_translated_payload_miss;
  assign io_pop_payload_victim = logic_pop_sync_readArbitation_translated_payload_victim;
  assign io_pop_payload_vLine = logic_pop_sync_readArbitation_translated_payload_vLine;
  assign io_pop_payload_pend = logic_pop_sync_readArbitation_translated_payload_pend;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (7'h40 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 7'h0;
      logic_ptr_pop <= 7'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 7'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 7'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 7'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 7'h0;
        logic_ptr_pop <= 7'h0;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 7'h0;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_StreamArbiter (
  input  wire          io_inputs_0_valid,
  output wire          io_inputs_0_ready,
  input  wire [27:0]   io_inputs_0_payload_b_addr,
  input  wire [63:0]   io_inputs_0_payload_b_data,
  input  wire [7:0]    io_inputs_0_payload_b_be,
  input  wire          io_inputs_0_payload_rel,
  input  wire [2:0]    io_inputs_0_payload_relSlot,
  input  wire          io_inputs_1_valid,
  output wire          io_inputs_1_ready,
  input  wire [27:0]   io_inputs_1_payload_b_addr,
  input  wire [63:0]   io_inputs_1_payload_b_data,
  input  wire [7:0]    io_inputs_1_payload_b_be,
  input  wire          io_inputs_1_payload_rel,
  input  wire [2:0]    io_inputs_1_payload_relSlot,
  input  wire          io_inputs_2_valid,
  output wire          io_inputs_2_ready,
  input  wire [27:0]   io_inputs_2_payload_b_addr,
  input  wire [63:0]   io_inputs_2_payload_b_data,
  input  wire [7:0]    io_inputs_2_payload_b_be,
  input  wire          io_inputs_2_payload_rel,
  input  wire [2:0]    io_inputs_2_payload_relSlot,
  output wire          io_output_valid,
  input  wire          io_output_ready,
  output wire [27:0]   io_output_payload_b_addr,
  output wire [63:0]   io_output_payload_b_data,
  output wire [7:0]    io_output_payload_b_be,
  output wire          io_output_payload_rel,
  output wire [2:0]    io_output_payload_relSlot,
  output wire [1:0]    io_chosen,
  output wire [2:0]    io_chosenOH,
  input  wire          clk,
  input  wire          reset
);

  wire       [2:0]    _zz__zz_maskProposal_1_1;
  reg        [27:0]   _zz_io_output_payload_b_addr_1;
  reg        [63:0]   _zz_io_output_payload_b_data;
  reg        [7:0]    _zz_io_output_payload_b_be;
  reg                 _zz_io_output_payload_rel;
  reg        [2:0]    _zz_io_output_payload_relSlot;
  reg                 locked;
  wire                maskProposal_0;
  wire                maskProposal_1;
  wire                maskProposal_2;
  reg                 maskLocked_0;
  reg                 maskLocked_1;
  reg                 maskLocked_2;
  wire                maskRouted_0;
  wire                maskRouted_1;
  wire                maskRouted_2;
  wire       [2:0]    _zz_maskProposal_1;
  wire       [2:0]    _zz_maskProposal_1_1;
  wire                io_output_fire;
  wire       [1:0]    _zz_io_output_payload_b_addr;
  wire                _zz_io_chosen;
  wire                _zz_io_chosen_1;

  assign _zz__zz_maskProposal_1_1 = (_zz_maskProposal_1 - 3'b001);
  always @(*) begin
    case(_zz_io_output_payload_b_addr)
      2'b00 : begin
        _zz_io_output_payload_b_addr_1 = io_inputs_0_payload_b_addr;
        _zz_io_output_payload_b_data = io_inputs_0_payload_b_data;
        _zz_io_output_payload_b_be = io_inputs_0_payload_b_be;
        _zz_io_output_payload_rel = io_inputs_0_payload_rel;
        _zz_io_output_payload_relSlot = io_inputs_0_payload_relSlot;
      end
      2'b01 : begin
        _zz_io_output_payload_b_addr_1 = io_inputs_1_payload_b_addr;
        _zz_io_output_payload_b_data = io_inputs_1_payload_b_data;
        _zz_io_output_payload_b_be = io_inputs_1_payload_b_be;
        _zz_io_output_payload_rel = io_inputs_1_payload_rel;
        _zz_io_output_payload_relSlot = io_inputs_1_payload_relSlot;
      end
      default : begin
        _zz_io_output_payload_b_addr_1 = io_inputs_2_payload_b_addr;
        _zz_io_output_payload_b_data = io_inputs_2_payload_b_data;
        _zz_io_output_payload_b_be = io_inputs_2_payload_b_be;
        _zz_io_output_payload_rel = io_inputs_2_payload_rel;
        _zz_io_output_payload_relSlot = io_inputs_2_payload_relSlot;
      end
    endcase
  end

  assign maskRouted_0 = (locked ? maskLocked_0 : maskProposal_0);
  assign maskRouted_1 = (locked ? maskLocked_1 : maskProposal_1);
  assign maskRouted_2 = (locked ? maskLocked_2 : maskProposal_2);
  assign _zz_maskProposal_1 = {io_inputs_2_valid,{io_inputs_1_valid,io_inputs_0_valid}};
  assign _zz_maskProposal_1_1 = (_zz_maskProposal_1 & (~ _zz__zz_maskProposal_1_1));
  assign maskProposal_0 = io_inputs_0_valid;
  assign maskProposal_1 = _zz_maskProposal_1_1[1];
  assign maskProposal_2 = _zz_maskProposal_1_1[2];
  assign io_output_fire = (io_output_valid && io_output_ready);
  assign io_output_valid = (((io_inputs_0_valid && maskRouted_0) || (io_inputs_1_valid && maskRouted_1)) || (io_inputs_2_valid && maskRouted_2));
  assign _zz_io_output_payload_b_addr = {maskRouted_2,maskRouted_1};
  assign io_output_payload_b_addr = _zz_io_output_payload_b_addr_1;
  assign io_output_payload_b_data = _zz_io_output_payload_b_data;
  assign io_output_payload_b_be = _zz_io_output_payload_b_be;
  assign io_output_payload_rel = _zz_io_output_payload_rel;
  assign io_output_payload_relSlot = _zz_io_output_payload_relSlot;
  assign io_inputs_0_ready = ((1'b0 || maskRouted_0) && io_output_ready);
  assign io_inputs_1_ready = ((1'b0 || maskRouted_1) && io_output_ready);
  assign io_inputs_2_ready = ((1'b0 || maskRouted_2) && io_output_ready);
  assign io_chosenOH = {maskRouted_2,{maskRouted_1,maskRouted_0}};
  assign _zz_io_chosen = io_chosenOH[1];
  assign _zz_io_chosen_1 = io_chosenOH[2];
  assign io_chosen = {_zz_io_chosen_1,_zz_io_chosen};
  always @(posedge clk) begin
    if(reset) begin
      locked <= 1'b0;
    end else begin
      if(io_output_valid) begin
        locked <= 1'b1;
      end
      if(io_output_fire) begin
        locked <= 1'b0;
      end
    end
  end

  always @(posedge clk) begin
    if(io_output_valid) begin
      maskLocked_0 <= maskRouted_0;
      maskLocked_1 <= maskRouted_1;
      maskLocked_2 <= maskRouted_2;
    end
  end


endmodule

module hng64_raster_StreamFifo_3 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [27:0]   io_push_payload_b_addr,
  input  wire [63:0]   io_push_payload_b_data,
  input  wire [7:0]    io_push_payload_b_be,
  input  wire          io_push_payload_rel,
  input  wire [2:0]    io_push_payload_relSlot,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [27:0]   io_pop_payload_b_addr,
  output wire [63:0]   io_pop_payload_b_data,
  output wire [7:0]    io_pop_payload_b_be,
  output wire          io_pop_payload_rel,
  output wire [2:0]    io_pop_payload_relSlot,
  input  wire          io_flush,
  output wire [4:0]    io_occupancy,
  output wire [4:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [103:0]  logic_ram_spinal_port1;
  wire       [103:0]  _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [4:0]    logic_ptr_push;
  reg        [4:0]    logic_ptr_pop;
  wire       [4:0]    logic_ptr_occupancy;
  wire       [4:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [3:0]    logic_push_onRam_write_payload_address;
  wire       [27:0]   logic_push_onRam_write_payload_data_b_addr;
  wire       [63:0]   logic_push_onRam_write_payload_data_b_data;
  wire       [7:0]    logic_push_onRam_write_payload_data_b_be;
  wire                logic_push_onRam_write_payload_data_rel;
  wire       [2:0]    logic_push_onRam_write_payload_data_relSlot;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [3:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [3:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [3:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [3:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [27:0]   logic_pop_sync_readPort_rsp_b_addr;
  wire       [63:0]   logic_pop_sync_readPort_rsp_b_data;
  wire       [7:0]    logic_pop_sync_readPort_rsp_b_be;
  wire                logic_pop_sync_readPort_rsp_rel;
  wire       [2:0]    logic_pop_sync_readPort_rsp_relSlot;
  wire       [103:0]  _zz_logic_pop_sync_readPort_rsp_rel;
  wire       [99:0]   _zz_logic_pop_sync_readPort_rsp_b_addr;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [3:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [27:0]   logic_pop_sync_readArbitation_translated_payload_b_addr;
  wire       [63:0]   logic_pop_sync_readArbitation_translated_payload_b_data;
  wire       [7:0]    logic_pop_sync_readArbitation_translated_payload_b_be;
  wire                logic_pop_sync_readArbitation_translated_payload_rel;
  wire       [2:0]    logic_pop_sync_readArbitation_translated_payload_relSlot;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [4:0]    logic_pop_sync_popReg;
  reg [103:0] logic_ram [0:15];

  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_relSlot,{logic_push_onRam_write_payload_data_rel,{logic_push_onRam_write_payload_data_b_be,{logic_push_onRam_write_payload_data_b_data,logic_push_onRam_write_payload_data_b_addr}}}};
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 5'h10) == 5'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[3:0];
  assign logic_push_onRam_write_payload_data_b_addr = io_push_payload_b_addr;
  assign logic_push_onRam_write_payload_data_b_data = io_push_payload_b_data;
  assign logic_push_onRam_write_payload_data_b_be = io_push_payload_b_be;
  assign logic_push_onRam_write_payload_data_rel = io_push_payload_rel;
  assign logic_push_onRam_write_payload_data_relSlot = io_push_payload_relSlot;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[3:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign _zz_logic_pop_sync_readPort_rsp_rel = logic_ram_spinal_port1;
  assign _zz_logic_pop_sync_readPort_rsp_b_addr = _zz_logic_pop_sync_readPort_rsp_rel[99 : 0];
  assign logic_pop_sync_readPort_rsp_b_addr = _zz_logic_pop_sync_readPort_rsp_b_addr[27 : 0];
  assign logic_pop_sync_readPort_rsp_b_data = _zz_logic_pop_sync_readPort_rsp_b_addr[91 : 28];
  assign logic_pop_sync_readPort_rsp_b_be = _zz_logic_pop_sync_readPort_rsp_b_addr[99 : 92];
  assign logic_pop_sync_readPort_rsp_rel = _zz_logic_pop_sync_readPort_rsp_rel[100];
  assign logic_pop_sync_readPort_rsp_relSlot = _zz_logic_pop_sync_readPort_rsp_rel[103 : 101];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_b_addr = logic_pop_sync_readPort_rsp_b_addr;
  assign logic_pop_sync_readArbitation_translated_payload_b_data = logic_pop_sync_readPort_rsp_b_data;
  assign logic_pop_sync_readArbitation_translated_payload_b_be = logic_pop_sync_readPort_rsp_b_be;
  assign logic_pop_sync_readArbitation_translated_payload_rel = logic_pop_sync_readPort_rsp_rel;
  assign logic_pop_sync_readArbitation_translated_payload_relSlot = logic_pop_sync_readPort_rsp_relSlot;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_b_addr = logic_pop_sync_readArbitation_translated_payload_b_addr;
  assign io_pop_payload_b_data = logic_pop_sync_readArbitation_translated_payload_b_data;
  assign io_pop_payload_b_be = logic_pop_sync_readArbitation_translated_payload_b_be;
  assign io_pop_payload_rel = logic_pop_sync_readArbitation_translated_payload_rel;
  assign io_pop_payload_relSlot = logic_pop_sync_readArbitation_translated_payload_relSlot;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (5'h10 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 5'h0;
      logic_ptr_pop <= 5'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 5'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 5'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 5'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 5'h0;
        logic_ptr_pop <= 5'h0;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 5'h0;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_StreamFifo_2 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [63:0]   io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [63:0]   io_pop_payload,
  input  wire          io_flush,
  output wire [6:0]    io_occupancy,
  output wire [6:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [63:0]   logic_ram_spinal_port1;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [6:0]    logic_ptr_push;
  reg        [6:0]    logic_ptr_pop;
  wire       [6:0]    logic_ptr_occupancy;
  wire       [6:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [5:0]    logic_push_onRam_write_payload_address;
  wire       [63:0]   logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [5:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [5:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [5:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [5:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [63:0]   logic_pop_sync_readPort_rsp;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [5:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [63:0]   logic_pop_sync_readArbitation_translated_payload;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [6:0]    logic_pop_sync_popReg;
  reg [63:0] logic_ram [0:63];

  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= logic_push_onRam_write_payload_data;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 7'h40) == 7'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[5:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[5:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign logic_pop_sync_readPort_rsp = logic_ram_spinal_port1;
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload = logic_pop_sync_readPort_rsp;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = logic_pop_sync_readArbitation_translated_payload;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (7'h40 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 7'h0;
      logic_ptr_pop <= 7'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 7'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 7'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 7'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 7'h0;
        logic_ptr_pop <= 7'h0;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 7'h0;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_StreamFifo_1 (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [8:0]    io_push_payload_f_x,
  input  wire [8:0]    io_push_payload_f_y,
  input  wire [29:0]   io_push_payload_f_z,
  input  wire [23:0]   io_push_payload_f_addr,
  input  wire          io_push_payload_f_nib,
  input  wire [7:0]    io_push_payload_f_light,
  input  wire          io_push_payload_f_flat,
  input  wire          io_push_payload_f_blend,
  input  wire          io_push_payload_f_tex4bpp,
  input  wire [15:0]   io_push_payload_f_pal,
  input  wire [9:0]    io_push_payload_word,
  input  wire [2:0]    io_push_payload_byte,
  input  wire          io_push_payload_miss,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [8:0]    io_pop_payload_f_x,
  output wire [8:0]    io_pop_payload_f_y,
  output wire [29:0]   io_pop_payload_f_z,
  output wire [23:0]   io_pop_payload_f_addr,
  output wire          io_pop_payload_f_nib,
  output wire [7:0]    io_pop_payload_f_light,
  output wire          io_pop_payload_f_flat,
  output wire          io_pop_payload_f_blend,
  output wire          io_pop_payload_f_tex4bpp,
  output wire [15:0]   io_pop_payload_f_pal,
  output wire [9:0]    io_pop_payload_word,
  output wire [2:0]    io_pop_payload_byte,
  output wire          io_pop_payload_miss,
  input  wire          io_flush,
  output wire [7:0]    io_occupancy,
  output wire [7:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [113:0]  logic_ram_spinal_port1;
  wire       [113:0]  _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [7:0]    logic_ptr_push;
  reg        [7:0]    logic_ptr_pop;
  wire       [7:0]    logic_ptr_occupancy;
  wire       [7:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [6:0]    logic_push_onRam_write_payload_address;
  wire       [8:0]    logic_push_onRam_write_payload_data_f_x;
  wire       [8:0]    logic_push_onRam_write_payload_data_f_y;
  wire       [29:0]   logic_push_onRam_write_payload_data_f_z;
  wire       [23:0]   logic_push_onRam_write_payload_data_f_addr;
  wire                logic_push_onRam_write_payload_data_f_nib;
  wire       [7:0]    logic_push_onRam_write_payload_data_f_light;
  wire                logic_push_onRam_write_payload_data_f_flat;
  wire                logic_push_onRam_write_payload_data_f_blend;
  wire                logic_push_onRam_write_payload_data_f_tex4bpp;
  wire       [15:0]   logic_push_onRam_write_payload_data_f_pal;
  wire       [9:0]    logic_push_onRam_write_payload_data_word;
  wire       [2:0]    logic_push_onRam_write_payload_data_byte;
  wire                logic_push_onRam_write_payload_data_miss;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [6:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [6:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [6:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [6:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [8:0]    logic_pop_sync_readPort_rsp_f_x;
  wire       [8:0]    logic_pop_sync_readPort_rsp_f_y;
  wire       [29:0]   logic_pop_sync_readPort_rsp_f_z;
  wire       [23:0]   logic_pop_sync_readPort_rsp_f_addr;
  wire                logic_pop_sync_readPort_rsp_f_nib;
  wire       [7:0]    logic_pop_sync_readPort_rsp_f_light;
  wire                logic_pop_sync_readPort_rsp_f_flat;
  wire                logic_pop_sync_readPort_rsp_f_blend;
  wire                logic_pop_sync_readPort_rsp_f_tex4bpp;
  wire       [15:0]   logic_pop_sync_readPort_rsp_f_pal;
  wire       [9:0]    logic_pop_sync_readPort_rsp_word;
  wire       [2:0]    logic_pop_sync_readPort_rsp_byte;
  wire                logic_pop_sync_readPort_rsp_miss;
  wire       [113:0]  _zz_logic_pop_sync_readPort_rsp_word;
  wire       [99:0]   _zz_logic_pop_sync_readPort_rsp_f_x;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [6:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_f_x;
  wire       [8:0]    logic_pop_sync_readArbitation_translated_payload_f_y;
  wire       [29:0]   logic_pop_sync_readArbitation_translated_payload_f_z;
  wire       [23:0]   logic_pop_sync_readArbitation_translated_payload_f_addr;
  wire                logic_pop_sync_readArbitation_translated_payload_f_nib;
  wire       [7:0]    logic_pop_sync_readArbitation_translated_payload_f_light;
  wire                logic_pop_sync_readArbitation_translated_payload_f_flat;
  wire                logic_pop_sync_readArbitation_translated_payload_f_blend;
  wire                logic_pop_sync_readArbitation_translated_payload_f_tex4bpp;
  wire       [15:0]   logic_pop_sync_readArbitation_translated_payload_f_pal;
  wire       [9:0]    logic_pop_sync_readArbitation_translated_payload_word;
  wire       [2:0]    logic_pop_sync_readArbitation_translated_payload_byte;
  wire                logic_pop_sync_readArbitation_translated_payload_miss;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [7:0]    logic_pop_sync_popReg;
  reg [113:0] logic_ram [0:127];

  assign _zz_logic_ram_port = {logic_push_onRam_write_payload_data_miss,{logic_push_onRam_write_payload_data_byte,{logic_push_onRam_write_payload_data_word,{logic_push_onRam_write_payload_data_f_pal,{logic_push_onRam_write_payload_data_f_tex4bpp,{logic_push_onRam_write_payload_data_f_blend,{logic_push_onRam_write_payload_data_f_flat,{logic_push_onRam_write_payload_data_f_light,{logic_push_onRam_write_payload_data_f_nib,{logic_push_onRam_write_payload_data_f_addr,{logic_push_onRam_write_payload_data_f_z,{logic_push_onRam_write_payload_data_f_y,logic_push_onRam_write_payload_data_f_x}}}}}}}}}}}};
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 8'h80) == 8'h0);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[6:0];
  assign logic_push_onRam_write_payload_data_f_x = io_push_payload_f_x;
  assign logic_push_onRam_write_payload_data_f_y = io_push_payload_f_y;
  assign logic_push_onRam_write_payload_data_f_z = io_push_payload_f_z;
  assign logic_push_onRam_write_payload_data_f_addr = io_push_payload_f_addr;
  assign logic_push_onRam_write_payload_data_f_nib = io_push_payload_f_nib;
  assign logic_push_onRam_write_payload_data_f_light = io_push_payload_f_light;
  assign logic_push_onRam_write_payload_data_f_flat = io_push_payload_f_flat;
  assign logic_push_onRam_write_payload_data_f_blend = io_push_payload_f_blend;
  assign logic_push_onRam_write_payload_data_f_tex4bpp = io_push_payload_f_tex4bpp;
  assign logic_push_onRam_write_payload_data_f_pal = io_push_payload_f_pal;
  assign logic_push_onRam_write_payload_data_word = io_push_payload_word;
  assign logic_push_onRam_write_payload_data_byte = io_push_payload_byte;
  assign logic_push_onRam_write_payload_data_miss = io_push_payload_miss;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[6:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign _zz_logic_pop_sync_readPort_rsp_word = logic_ram_spinal_port1;
  assign _zz_logic_pop_sync_readPort_rsp_f_x = _zz_logic_pop_sync_readPort_rsp_word[99 : 0];
  assign logic_pop_sync_readPort_rsp_f_x = _zz_logic_pop_sync_readPort_rsp_f_x[8 : 0];
  assign logic_pop_sync_readPort_rsp_f_y = _zz_logic_pop_sync_readPort_rsp_f_x[17 : 9];
  assign logic_pop_sync_readPort_rsp_f_z = _zz_logic_pop_sync_readPort_rsp_f_x[47 : 18];
  assign logic_pop_sync_readPort_rsp_f_addr = _zz_logic_pop_sync_readPort_rsp_f_x[71 : 48];
  assign logic_pop_sync_readPort_rsp_f_nib = _zz_logic_pop_sync_readPort_rsp_f_x[72];
  assign logic_pop_sync_readPort_rsp_f_light = _zz_logic_pop_sync_readPort_rsp_f_x[80 : 73];
  assign logic_pop_sync_readPort_rsp_f_flat = _zz_logic_pop_sync_readPort_rsp_f_x[81];
  assign logic_pop_sync_readPort_rsp_f_blend = _zz_logic_pop_sync_readPort_rsp_f_x[82];
  assign logic_pop_sync_readPort_rsp_f_tex4bpp = _zz_logic_pop_sync_readPort_rsp_f_x[83];
  assign logic_pop_sync_readPort_rsp_f_pal = _zz_logic_pop_sync_readPort_rsp_f_x[99 : 84];
  assign logic_pop_sync_readPort_rsp_word = _zz_logic_pop_sync_readPort_rsp_word[109 : 100];
  assign logic_pop_sync_readPort_rsp_byte = _zz_logic_pop_sync_readPort_rsp_word[112 : 110];
  assign logic_pop_sync_readPort_rsp_miss = _zz_logic_pop_sync_readPort_rsp_word[113];
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload_f_x = logic_pop_sync_readPort_rsp_f_x;
  assign logic_pop_sync_readArbitation_translated_payload_f_y = logic_pop_sync_readPort_rsp_f_y;
  assign logic_pop_sync_readArbitation_translated_payload_f_z = logic_pop_sync_readPort_rsp_f_z;
  assign logic_pop_sync_readArbitation_translated_payload_f_addr = logic_pop_sync_readPort_rsp_f_addr;
  assign logic_pop_sync_readArbitation_translated_payload_f_nib = logic_pop_sync_readPort_rsp_f_nib;
  assign logic_pop_sync_readArbitation_translated_payload_f_light = logic_pop_sync_readPort_rsp_f_light;
  assign logic_pop_sync_readArbitation_translated_payload_f_flat = logic_pop_sync_readPort_rsp_f_flat;
  assign logic_pop_sync_readArbitation_translated_payload_f_blend = logic_pop_sync_readPort_rsp_f_blend;
  assign logic_pop_sync_readArbitation_translated_payload_f_tex4bpp = logic_pop_sync_readPort_rsp_f_tex4bpp;
  assign logic_pop_sync_readArbitation_translated_payload_f_pal = logic_pop_sync_readPort_rsp_f_pal;
  assign logic_pop_sync_readArbitation_translated_payload_word = logic_pop_sync_readPort_rsp_word;
  assign logic_pop_sync_readArbitation_translated_payload_byte = logic_pop_sync_readPort_rsp_byte;
  assign logic_pop_sync_readArbitation_translated_payload_miss = logic_pop_sync_readPort_rsp_miss;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload_f_x = logic_pop_sync_readArbitation_translated_payload_f_x;
  assign io_pop_payload_f_y = logic_pop_sync_readArbitation_translated_payload_f_y;
  assign io_pop_payload_f_z = logic_pop_sync_readArbitation_translated_payload_f_z;
  assign io_pop_payload_f_addr = logic_pop_sync_readArbitation_translated_payload_f_addr;
  assign io_pop_payload_f_nib = logic_pop_sync_readArbitation_translated_payload_f_nib;
  assign io_pop_payload_f_light = logic_pop_sync_readArbitation_translated_payload_f_light;
  assign io_pop_payload_f_flat = logic_pop_sync_readArbitation_translated_payload_f_flat;
  assign io_pop_payload_f_blend = logic_pop_sync_readArbitation_translated_payload_f_blend;
  assign io_pop_payload_f_tex4bpp = logic_pop_sync_readArbitation_translated_payload_f_tex4bpp;
  assign io_pop_payload_f_pal = logic_pop_sync_readArbitation_translated_payload_f_pal;
  assign io_pop_payload_word = logic_pop_sync_readArbitation_translated_payload_word;
  assign io_pop_payload_byte = logic_pop_sync_readArbitation_translated_payload_byte;
  assign io_pop_payload_miss = logic_pop_sync_readArbitation_translated_payload_miss;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (8'h80 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 8'h0;
      logic_ptr_pop <= 8'h0;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 8'h0;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 8'h01);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 8'h01);
      end
      if(io_flush) begin
        logic_ptr_push <= 8'h0;
        logic_ptr_pop <= 8'h0;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 8'h0;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule

module hng64_raster_StreamFifo (
  input  wire          io_push_valid,
  output wire          io_push_ready,
  input  wire [18:0]   io_push_payload,
  output wire          io_pop_valid,
  input  wire          io_pop_ready,
  output wire [18:0]   io_pop_payload,
  input  wire          io_flush,
  output wire [3:0]    io_occupancy,
  output wire [3:0]    io_availability,
  input  wire          clk,
  input  wire          reset
);

  reg        [18:0]   logic_ram_spinal_port1;
  wire       [18:0]   _zz_logic_ram_port;
  reg                 _zz_1;
  wire                logic_ptr_doPush;
  wire                logic_ptr_doPop;
  wire                logic_ptr_full;
  wire                logic_ptr_empty;
  reg        [3:0]    logic_ptr_push;
  reg        [3:0]    logic_ptr_pop;
  wire       [3:0]    logic_ptr_occupancy;
  wire       [3:0]    logic_ptr_popOnIo;
  wire                when_Stream_l1455;
  reg                 logic_ptr_wentUp;
  wire                io_push_fire;
  wire                logic_push_onRam_write_valid;
  wire       [2:0]    logic_push_onRam_write_payload_address;
  wire       [18:0]   logic_push_onRam_write_payload_data;
  wire                logic_pop_addressGen_valid;
  reg                 logic_pop_addressGen_ready;
  wire       [2:0]    logic_pop_addressGen_payload;
  wire                logic_pop_addressGen_fire;
  wire                logic_pop_sync_readArbitation_valid;
  wire                logic_pop_sync_readArbitation_ready;
  wire       [2:0]    logic_pop_sync_readArbitation_payload;
  reg                 logic_pop_addressGen_rValid;
  reg        [2:0]    logic_pop_addressGen_rData;
  wire                when_Stream_l477;
  wire                logic_pop_sync_readPort_cmd_valid;
  wire       [2:0]    logic_pop_sync_readPort_cmd_payload;
  wire       [18:0]   logic_pop_sync_readPort_rsp;
  wire                logic_pop_addressGen_toFlowFire_valid;
  wire       [2:0]    logic_pop_addressGen_toFlowFire_payload;
  wire                logic_pop_sync_readArbitation_translated_valid;
  wire                logic_pop_sync_readArbitation_translated_ready;
  wire       [18:0]   logic_pop_sync_readArbitation_translated_payload;
  wire                logic_pop_sync_readArbitation_fire;
  reg        [3:0]    logic_pop_sync_popReg;
  reg [18:0] logic_ram [0:7];

  assign _zz_logic_ram_port = logic_push_onRam_write_payload_data;
  always @(posedge clk) begin
    if(_zz_1) begin
      logic_ram[logic_push_onRam_write_payload_address] <= _zz_logic_ram_port;
    end
  end

  always @(posedge clk) begin
    if(logic_pop_sync_readPort_cmd_valid) begin
      logic_ram_spinal_port1 <= logic_ram[logic_pop_sync_readPort_cmd_payload];
    end
  end

  always @(*) begin
    _zz_1 = 1'b0;
    if(logic_push_onRam_write_valid) begin
      _zz_1 = 1'b1;
    end
  end

  assign when_Stream_l1455 = (logic_ptr_doPush != logic_ptr_doPop);
  assign logic_ptr_full = (((logic_ptr_push ^ logic_ptr_popOnIo) ^ 4'b1000) == 4'b0000);
  assign logic_ptr_empty = (logic_ptr_push == logic_ptr_pop);
  assign logic_ptr_occupancy = (logic_ptr_push - logic_ptr_popOnIo);
  assign io_push_ready = (! logic_ptr_full);
  assign io_push_fire = (io_push_valid && io_push_ready);
  assign logic_ptr_doPush = io_push_fire;
  assign logic_push_onRam_write_valid = io_push_fire;
  assign logic_push_onRam_write_payload_address = logic_ptr_push[2:0];
  assign logic_push_onRam_write_payload_data = io_push_payload;
  assign logic_pop_addressGen_valid = (! logic_ptr_empty);
  assign logic_pop_addressGen_payload = logic_ptr_pop[2:0];
  assign logic_pop_addressGen_fire = (logic_pop_addressGen_valid && logic_pop_addressGen_ready);
  assign logic_ptr_doPop = logic_pop_addressGen_fire;
  always @(*) begin
    logic_pop_addressGen_ready = logic_pop_sync_readArbitation_ready;
    if(when_Stream_l477) begin
      logic_pop_addressGen_ready = 1'b1;
    end
  end

  assign when_Stream_l477 = (! logic_pop_sync_readArbitation_valid);
  assign logic_pop_sync_readArbitation_valid = logic_pop_addressGen_rValid;
  assign logic_pop_sync_readArbitation_payload = logic_pop_addressGen_rData;
  assign logic_pop_sync_readPort_rsp = logic_ram_spinal_port1;
  assign logic_pop_addressGen_toFlowFire_valid = logic_pop_addressGen_fire;
  assign logic_pop_addressGen_toFlowFire_payload = logic_pop_addressGen_payload;
  assign logic_pop_sync_readPort_cmd_valid = logic_pop_addressGen_toFlowFire_valid;
  assign logic_pop_sync_readPort_cmd_payload = logic_pop_addressGen_toFlowFire_payload;
  assign logic_pop_sync_readArbitation_translated_valid = logic_pop_sync_readArbitation_valid;
  assign logic_pop_sync_readArbitation_ready = logic_pop_sync_readArbitation_translated_ready;
  assign logic_pop_sync_readArbitation_translated_payload = logic_pop_sync_readPort_rsp;
  assign io_pop_valid = logic_pop_sync_readArbitation_translated_valid;
  assign logic_pop_sync_readArbitation_translated_ready = io_pop_ready;
  assign io_pop_payload = logic_pop_sync_readArbitation_translated_payload;
  assign logic_pop_sync_readArbitation_fire = (logic_pop_sync_readArbitation_valid && logic_pop_sync_readArbitation_ready);
  assign logic_ptr_popOnIo = logic_pop_sync_popReg;
  assign io_occupancy = logic_ptr_occupancy;
  assign io_availability = (4'b1000 - logic_ptr_occupancy);
  always @(posedge clk) begin
    if(reset) begin
      logic_ptr_push <= 4'b0000;
      logic_ptr_pop <= 4'b0000;
      logic_ptr_wentUp <= 1'b0;
      logic_pop_addressGen_rValid <= 1'b0;
      logic_pop_sync_popReg <= 4'b0000;
    end else begin
      if(when_Stream_l1455) begin
        logic_ptr_wentUp <= logic_ptr_doPush;
      end
      if(io_flush) begin
        logic_ptr_wentUp <= 1'b0;
      end
      if(logic_ptr_doPush) begin
        logic_ptr_push <= (logic_ptr_push + 4'b0001);
      end
      if(logic_ptr_doPop) begin
        logic_ptr_pop <= (logic_ptr_pop + 4'b0001);
      end
      if(io_flush) begin
        logic_ptr_push <= 4'b0000;
        logic_ptr_pop <= 4'b0000;
      end
      if(logic_pop_addressGen_ready) begin
        logic_pop_addressGen_rValid <= logic_pop_addressGen_valid;
      end
      if(io_flush) begin
        logic_pop_addressGen_rValid <= 1'b0;
      end
      if(logic_pop_sync_readArbitation_fire) begin
        logic_pop_sync_popReg <= logic_ptr_pop;
      end
      if(io_flush) begin
        logic_pop_sync_popReg <= 4'b0000;
      end
    end
  end

  always @(posedge clk) begin
    if(logic_pop_addressGen_ready) begin
      logic_pop_addressGen_rData <= logic_pop_addressGen_payload;
    end
  end


endmodule
