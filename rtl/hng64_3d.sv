// SPDX-License-Identifier: GPL-3.0-or-later
//
// The 3D pipeline in the core: the display list and its upload queue, the geometry engine
// (rtl/3d/hng64_geo.v), the rasteriser and render buffer (rtl/3d/hng64_raster.v), and the frame
// sequence around them. docs/phase3_3d.md has the design and its measurements.
//
// THE QUEUE. MAME renders a display list the moment it is uploaded and raises interrupt 3 a fixed
// 5,120 CPU cycles later whatever the work (hng64_io.sv, D_DLUP). The engine takes longer than that
// for most uploads, so each upload copies the display list (256 u16) and the texture-wrap bytes
// into a slot of a queue, and the engine takes the slots in order; the game keeps MAME's timing
// while the engine catches up within the frame. The copy takes 129 clk1x clocks, during which a
// display-list write waits (dl_busy). A clearing vblank (tcram 0x50 bit 16, MAME's screen_vblank)
// is queued as an event of its own between the uploads either side of it. With the queue full,
// interrupt 3 is held back until a slot is free (dl_full, docs/HACKS.md), and an upload waits.
//
// THE FRAME. Two colour planes and one depth plane in DDR3 (RenderBuf.scala). An upload runs the
// engine's upload entry and its triangles go straight to the rasteriser. A clearing vblank ends
// the frame: the rasteriser drains, the render buffer finishes its writes, and the finished plane
// is offered to the display (hng64_fb3d), which takes it in the next vblank; once it has, the new
// frame starts in the other plane and the engine runs its clear entry. So the display shows the
// last finished frame, one behind MAME's, which shows the buffer as it is being drawn
// (docs/HACKS.md). A frame not finished by the vblank after its clear stays off screen a frame
// longer.
//
// START-UP. After reset the textures are copied into their blocked layout (TexBlock, about 43 ms),
// the engine runs its init entry, and the first frame starts with the whole depth plane scrubbed.
// Without 3D data in the .mra (a zero textures0 or verts size) events are dropped as they come.

module hng64_3d #(
    parameter int SLOTS = 32
) (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        reset,              // clk1x-registered, held for both

    // hng64_io, clk1x
    input  logic        dl_we,
    input  logic  [6:0] dl_addr,
    input  logic  [3:0] dl_be,
    input  logic [31:0] dl_wdata,
    input  logic        dl_up,
    output logic        dl_busy,            // a display-list write must wait
    output logic        dl_upbusy,          // an upload must wait
    output logic        dl_full,            // hold interrupt 3
    input  logic  [7:0] texwrap [0:31],
    input  logic        vblank,             // MAME's screen vblank (hng64_vtiming vblank_level)
    input  logic        clear_en,           // tcram 0x50 bit 16

    // the layout
    input  logic        have3d,
    input  logic        samsho,             // init_ss64's m_samsho64_3d_hack
    input  logic [27:0] vert_base,
    input  logic [23:0] vert_len,           // u16 entries
    input  logic [27:0] tex_rom,            // textures0 as loaded
    input  logic [11:0] tex_groups,         // its size in 8 KB groups
    input  logic [27:0] tex_blocked,        // the blocked copy
    input  logic [27:0] depth_base,
    input  logic [27:0] plane_base [0:1],

    // the display, clk2x
    output logic        show_valid,
    output logic        show_plane,
    input  logic        shown_valid,
    input  logic        shown_plane,

    // DDR3 read clients (hng64_ddram), clk2x: the vertex ROM, textures, depth
    output logic [27:0] v_addr,
    output logic        v_rd,
    input  logic        v_ready,
    input  logic        v_valid,
    output logic [27:0] t_addr,
    output logic        t_rd,
    input  logic        t_ready,
    input  logic        t_valid,
    output logic [27:0] z_addr,
    output logic        z_rd,
    input  logic        z_ready,
    input  logic        z_valid,
    input  logic [63:0] d_data,

    // the writer
    output logic [27:0] w_addr,
    output logic [63:0] w_data,
    output logic  [7:0] w_be,
    output logic        w_valid,
    output logic        w_urgent,
    input  logic        w_ready,

    output logic  [3:0] dbg_state,
    output logic  [5:0] dbg_queued,
    output logic        dbg_tri         // a triangle taken by the rasteriser, one clk2x clock
);

    localparam int SW = $clog2(SLOTS);

    // ============================================================================================
    // clk1x: the live display list, the copy into the queue, the events
    // ============================================================================================
    logic [31:0] live_q;
    logic  [7:0] cp_i;                      // 0-128
    logic  [6:0] cp_wi;
    logic        cp_active, cp_wr;
    logic [SW:0] wptr, rptr;                // rptr is clk2x's
    logic        kind [0:SLOTS-1];          // 1 upload, 0 clearing vblank
    logic        vb_q, c_pend;

    wire  [SW:0] occ = wptr - rptr;
    wire  [SW-1:0] wslot = wptr[SW-1:0];

    hng64_bram #(.AW(7), .DW(32)) u_live (
        .a_clk(clk1x), .a_addr(dl_addr), .a_be(dl_we ? dl_be : 4'd0), .a_wdata(dl_wdata),
        .a_rdata(),
        .b_clk(clk1x), .b_addr(cp_i[6:0]), .b_rdata(live_q));

    assign dl_busy   = cp_active;
    assign dl_upbusy = cp_active || c_pend || (occ >= (SW+1)'(SLOTS));
    assign dl_full   = (occ >= (SW+1)'(SLOTS - 1));

    always_ff @(posedge clk1x) begin
        cp_wr <= 1'b0;
        vb_q  <= vblank;
        if (reset) begin
            cp_active <= 1'b0;
            c_pend    <= 1'b0;
            wptr      <= '0;
        end else begin
            if (vblank && !vb_q && clear_en) c_pend <= 1'b1;
            if (dl_up) begin
                cp_active <= 1'b1;
                cp_i      <= 8'd0;
            end else if (cp_active) begin
                cp_i  <= cp_i + 8'd1;
                cp_wr <= !cp_i[7];
                cp_wi <= cp_i[6:0];
                if (cp_i[7]) begin
                    cp_active   <= 1'b0;
                    kind[wslot] <= 1'b1;
                    wptr        <= wptr + 1'b1;
                end
            end else if (c_pend && occ < (SW+1)'(SLOTS)) begin
                c_pend      <= 1'b0;
                kind[wslot] <= 1'b0;
                wptr        <= wptr + 1'b1;
            end
        end
    end

    // the queue: 128 words a slot, written on clk1x, read by the engine on clk2x
    logic  [7:0] geo_dl_addr;
    logic [31:0] q_word;
    logic        q_sel;
    logic [SW-1:0] rslot;

    hng64_bram #(.AW(SW + 7), .DW(32)) u_queue (
        .a_clk(clk1x), .a_addr({wslot, cp_wi}), .a_be({4{cp_wr}}), .a_wdata(live_q), .a_rdata(),
        .b_clk(clk2x), .b_addr({rslot, geo_dl_addr[7:1]}), .b_rdata(q_word));

    // the wrap bytes, eight words a slot, big-endian as the CPU wrote them
    logic [31:0] wrap_w, wrap_q;
    logic  [2:0] wj;
    always_comb
        wrap_w = {texwrap[{cp_i[2:0], 2'd0}], texwrap[{cp_i[2:0], 2'd1}],
                  texwrap[{cp_i[2:0], 2'd2}], texwrap[{cp_i[2:0], 2'd3}]};

    hng64_bram #(.AW(SW + 3), .DW(32)) u_wrap (
        .a_clk(clk1x), .a_addr({wslot, cp_i[2:0]}),
        .a_be({4{cp_active && cp_i < 8'd8}}), .a_wdata(wrap_w), .a_rdata(),
        .b_clk(clk2x), .b_addr({rslot, wj}), .b_rdata(wrap_q));

    // ============================================================================================
    // clk2x: the engine, the rasteriser, the sequence
    // ============================================================================================
    typedef enum logic [3:0] {
        S_OFF, S_BLOCK, S_BLOCKW, S_INIT, S_RUNW, S_FIRST, S_IDLE, S_WRAP, S_GEO,
        S_FLUSH, S_FIN, S_SWAP, S_CLEAR
    } state_t;
    state_t st;

    logic        geo_start, geo_busy;
    logic  [1:0] geo_entry;
    logic  [7:0] wrap [0:31];
    logic  [3:0] wk;                        // wrap words requested, 0-8
    logic        started;                   // the engine has had a clock to raise busy
    logic        after_run;                 // S_RUNW returns to: 0 S_FIRST, 1 pop and S_IDLE

    logic        r_start, r_full, r_finish, r_done, r_busy, r_blk_start, r_blk_done;
    logic  [7:0] r_tag;
    logic  [6:0] r_scrub;
    logic        draw;                      // the plane being drawn

    assign rslot     = rptr[SW-1:0];
    assign dbg_state = st;
    assign dbg_queued = 6'(occ);

    // the triangle between the two: the setup record (geo_engine.setup_record)
    logic         tri_valid, tri_ready, t_neg;
    assign dbg_tri = tri_valid && tri_ready;
    logic  [23:0] t_xy [0:5];
    logic  [29:0] t_p0_0;
    logic  [33:0] t_p0_1;
    logic  [23:0] t_p0_2;
    logic  [31:0] t_p0_3, t_p0_4;
    logic  [41:0] t_dx_0, t_dy_0;
    logic  [45:0] t_dx_1, t_dy_1;
    logic  [35:0] t_dx_2, t_dy_2;
    logic  [43:0] t_dx_3, t_dy_3, t_dx_4, t_dy_4;
    logic  [66:0] tattr;

    always_ff @(posedge clk2x) begin
        geo_start   <= 1'b0;
        r_start     <= 1'b0;
        r_finish    <= 1'b0;
        r_blk_start <= 1'b0;
        q_sel       <= geo_dl_addr[0];
        if (reset) begin
            st         <= S_OFF;
            rptr       <= '0;
            show_valid <= 1'b0;
            show_plane <= 1'b0;
            draw       <= 1'b0;
            wk         <= 4'd0;
        end else begin
            case (st)
                S_OFF: begin
                    if (have3d) st <= S_BLOCK;
                    else if (occ != '0) rptr <= rptr + 1'b1;
                end
                S_BLOCK: begin
                    r_blk_start <= 1'b1;
                    st <= S_BLOCKW;
                end
                S_BLOCKW: if (r_blk_done) st <= S_INIT;
                S_INIT: begin
                    geo_entry <= 2'd0;
                    geo_start <= 1'b1;
                    started   <= 1'b0;
                    after_run <= 1'b0;
                    st <= S_RUNW;
                end
                S_RUNW: begin
                    started <= 1'b1;
                    if (started && !geo_busy && !tri_valid) begin
                        if (after_run) begin
                            rptr <= rptr + 1'b1;
                            st <= S_IDLE;
                        end else begin
                            st <= S_FIRST;
                        end
                    end
                end
                S_FIRST: begin
                    r_start <= 1'b1;
                    r_full  <= 1'b1;
                    r_tag   <= 8'd1;
                    r_scrub <= 7'd0;
                    draw    <= 1'b0;
                    st <= S_IDLE;
                end
                S_IDLE: if (occ != '0) begin
                    if (kind[rslot]) begin
                        wj <= 3'd0;
                        wk <= 4'd0;
                        st <= S_WRAP;
                    end else begin
                        st <= S_FLUSH;
                    end
                end
                // eight reads; each word lands the clock after its address
                S_WRAP: begin
                    wj <= wj + 3'd1;
                    wk <= wk + 4'd1;
                    if (wk != 4'd0)
                        for (int n = 0; n < 4; n++)
                            wrap[{wk[2:0] - 3'd1, 2'(n)}] <= wrap_q[31 - 8 * n -: 8];
                    if (wk == 4'd8) st <= S_GEO;
                end
                S_GEO: begin
                    geo_entry <= 2'd2;
                    geo_start <= 1'b1;
                    started   <= 1'b0;
                    after_run <= 1'b1;
                    st <= S_RUNW;
                end
                // the clearing vblank: every triangle through, then the buffer's last writes
                S_FLUSH: if (!r_busy && !tri_valid) begin
                    r_finish <= 1'b1;
                    st <= S_FIN;
                end
                S_FIN: if (r_done) begin
                    show_valid <= 1'b1;
                    show_plane <= draw;
                    st <= S_SWAP;
                end
                // the other plane is free once the display has left it
                S_SWAP: if (shown_valid && shown_plane == draw) begin
                    draw    <= !draw;
                    r_start <= 1'b1;
                    r_full  <= 1'b0;
                    r_tag   <= r_tag + 8'd1;
                    r_scrub <= r_scrub + 7'd1;
                    st <= S_CLEAR;
                end
                S_CLEAR: begin
                    geo_entry <= 2'd1;
                    geo_start <= 1'b1;
                    started   <= 1'b0;
                    after_run <= 1'b1;
                    st <= S_RUNW;
                end
                default: st <= S_OFF;
            endcase
        end
    end

    hng64_geo u_geo (
        .clk(clk2x), .reset(reset),
        .io_start(geo_start), .io_entry(geo_entry), .io_samsho(samsho), .io_vlen(vert_len),
        .io_busy(geo_busy),
        .io_dlAddr(geo_dl_addr), .io_dlData(q_sel ? q_word[15:0] : q_word[31:16]),
        .io_wrap_0(wrap[0]),   .io_wrap_1(wrap[1]),   .io_wrap_2(wrap[2]),   .io_wrap_3(wrap[3]),
        .io_wrap_4(wrap[4]),   .io_wrap_5(wrap[5]),   .io_wrap_6(wrap[6]),   .io_wrap_7(wrap[7]),
        .io_wrap_8(wrap[8]),   .io_wrap_9(wrap[9]),   .io_wrap_10(wrap[10]), .io_wrap_11(wrap[11]),
        .io_wrap_12(wrap[12]), .io_wrap_13(wrap[13]), .io_wrap_14(wrap[14]), .io_wrap_15(wrap[15]),
        .io_wrap_16(wrap[16]), .io_wrap_17(wrap[17]), .io_wrap_18(wrap[18]), .io_wrap_19(wrap[19]),
        .io_wrap_20(wrap[20]), .io_wrap_21(wrap[21]), .io_wrap_22(wrap[22]), .io_wrap_23(wrap[23]),
        .io_wrap_24(wrap[24]), .io_wrap_25(wrap[25]), .io_wrap_26(wrap[26]), .io_wrap_27(wrap[27]),
        .io_wrap_28(wrap[28]), .io_wrap_29(wrap[29]), .io_wrap_30(wrap[30]), .io_wrap_31(wrap[31]),
        .io_vBase(vert_base),
        .io_vRd_valid(v_rd), .io_vRd_ready(v_ready), .io_vRd_payload(v_addr),
        .io_vData_valid(v_valid), .io_vData_payload(d_data),
        .io_tri_valid(tri_valid), .io_tri_ready(tri_ready),
        .io_tri_payload_v_0_0(t_xy[0]), .io_tri_payload_v_0_1(t_xy[1]),
        .io_tri_payload_v_1_0(t_xy[2]), .io_tri_payload_v_1_1(t_xy[3]),
        .io_tri_payload_v_2_0(t_xy[4]), .io_tri_payload_v_2_1(t_xy[5]),
        .io_tri_payload_neg(t_neg),
        .io_tri_payload_p0_v_0(t_p0_0), .io_tri_payload_p0_v_1(t_p0_1), .io_tri_payload_p0_v_2(t_p0_2),
        .io_tri_payload_p0_v_3(t_p0_3), .io_tri_payload_p0_v_4(t_p0_4),
        .io_tri_payload_dx_v_0(t_dx_0), .io_tri_payload_dx_v_1(t_dx_1), .io_tri_payload_dx_v_2(t_dx_2),
        .io_tri_payload_dx_v_3(t_dx_3), .io_tri_payload_dx_v_4(t_dx_4),
        .io_tri_payload_dy_v_0(t_dy_0), .io_tri_payload_dy_v_1(t_dy_1), .io_tri_payload_dy_v_2(t_dy_2),
        .io_tri_payload_dy_v_3(t_dy_3), .io_tri_payload_dy_v_4(t_dy_4),
        .io_tri_payload_attr(tattr));

    hng64_raster u_raster (
        .clk(clk2x), .reset(reset),
        .io_tri_valid(tri_valid), .io_tri_ready(tri_ready),
        .io_tri_payload_v_0_0(t_xy[0]), .io_tri_payload_v_0_1(t_xy[1]),
        .io_tri_payload_v_1_0(t_xy[2]), .io_tri_payload_v_1_1(t_xy[3]),
        .io_tri_payload_v_2_0(t_xy[4]), .io_tri_payload_v_2_1(t_xy[5]),
        .io_tri_payload_neg(t_neg),
        .io_tri_payload_p0_v_0(t_p0_0), .io_tri_payload_p0_v_1(t_p0_1), .io_tri_payload_p0_v_2(t_p0_2),
        .io_tri_payload_p0_v_3(t_p0_3), .io_tri_payload_p0_v_4(t_p0_4),
        .io_tri_payload_dx_v_0(t_dx_0), .io_tri_payload_dx_v_1(t_dx_1), .io_tri_payload_dx_v_2(t_dx_2),
        .io_tri_payload_dx_v_3(t_dx_3), .io_tri_payload_dx_v_4(t_dx_4),
        .io_tri_payload_dy_v_0(t_dy_0), .io_tri_payload_dy_v_1(t_dy_1), .io_tri_payload_dy_v_2(t_dy_2),
        .io_tri_payload_dy_v_3(t_dy_3), .io_tri_payload_dy_v_4(t_dy_4),
        .io_tri_payload_attr(tattr),
        .io_depthRd_valid(z_rd), .io_depthRd_ready(z_ready), .io_depthRd_payload(z_addr),
        .io_depthData_valid(z_valid), .io_depthData_payload(d_data),
        .io_wr_valid(w_valid), .io_wr_ready(w_ready), .io_wr_payload_addr(w_addr),
        .io_wr_payload_data(w_data), .io_wr_payload_be(w_be), .io_urgent(w_urgent),
        .io_start(r_start), .io_full(r_full), .io_tag(r_tag), .io_scrub(r_scrub),
        .io_colourBase(plane_base[draw]), .io_depthBase(depth_base),
        .io_finish(r_finish), .io_done(r_done),
        .io_blockStart(r_blk_start), .io_blockSrc(tex_rom), .io_blockGroups(tex_groups),
        .io_blockDone(r_blk_done),
        .io_texBase(tex_blocked),
        .io_texRd_valid(t_rd), .io_texRd_ready(t_ready), .io_texRd_payload(t_addr),
        .io_texData_valid(t_valid), .io_texData_payload(d_data),
        .io_busy(r_busy));

endmodule
