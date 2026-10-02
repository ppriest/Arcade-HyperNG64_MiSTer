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
//
// CLOCKS. The queue's write side is clk1x (the CPU's); the engine, the rasteriser and the sequence
// run on clk3d, their own 100 MHz, not related to the others (user decision: at clk2x's 125 MHz
// the 3D was most of what missed timing). The queue's pointers cross as Gray code, show/shown as
// single bits through two registers, and DDR3 traffic through hng64_3d_bridge, which keeps
// writes and reads in order.

module hng64_3d #(
    parameter int SLOTS = 32
) (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        clk3d,
    input  logic        reset,              // clk1x-registered; synchronised for clk3d here

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

    // the display, clk2x (synchronised here both ways)
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
    output logic        dbg_tri         // a triangle taken by the rasteriser, one clk3d clock
);

    localparam int SW = $clog2(SLOTS);

    // ============================================================================================
    // clk1x: the live display list, the copy into the queue, the events
    // ============================================================================================
    logic [31:0] live_q;
    logic  [7:0] cp_i;                      // 0-128
    logic  [6:0] cp_wi;
    logic        cp_active, cp_wr;
    logic [SW:0] wptr, rptr;                // wptr is clk1x's, rptr clk3d's
    logic [SW:0] wptr_g, rptr_g;            // each in Gray code, registered in its own domain
    logic [SW:0] rptr_1a, rptr_1b, wptr_3a, wptr_3b;    // and synchronised into the other

    function automatic logic [SW:0] gray(input logic [SW:0] b);
        return b ^ (b >> 1);
    endfunction
    function automatic logic [SW:0] ungray(input logic [SW:0] g);
        logic [SW:0] b;
        b[SW] = g[SW];
        for (int i = SW - 1; i >= 0; i--) b[i] = b[i + 1] ^ g[i];
        return b;
    endfunction
    wire [SW:0] rptr1 = ungray(rptr_1b);    // clk1x's view of rptr, late, so occ is never low
    wire [SW:0] wptr3 = ungray(wptr_3b);    // clk3d's view of wptr, late
    logic        kind [0:SLOTS-1];          // 1 upload, 0 clearing vblank
    logic        vb_q, c_pend;

    wire  [SW:0] occ = wptr - rptr1;        // clk1x
    wire  [SW:0] occ3 = wptr3 - rptr;       // clk3d
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
        wptr_g  <= gray(wptr);
        rptr_1a <= rptr_g;
        rptr_1b <= rptr_1a;
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

    // the queue: 128 words a slot, written on clk1x, read by the engine on clk3d
    logic  [7:0] geo_dl_addr;
    logic [31:0] q_word;
    logic        q_sel;
    logic [SW-1:0] rslot;

    hng64_bram #(.AW(SW + 7), .DW(32)) u_queue (
        .a_clk(clk1x), .a_addr({wslot, cp_wi}), .a_be({4{cp_wr}}), .a_wdata(live_q), .a_rdata(),
        .b_clk(clk3d), .b_addr({rslot, geo_dl_addr[7:1]}), .b_rdata(q_word));

    // the wrap bytes, eight words a slot, big-endian as the CPU wrote them
    logic [31:0] wrap_w, wrap_q;
    logic  [2:0] wj;
    always_comb
        wrap_w = {texwrap[{cp_i[2:0], 2'd0}], texwrap[{cp_i[2:0], 2'd1}],
                  texwrap[{cp_i[2:0], 2'd2}], texwrap[{cp_i[2:0], 2'd3}]};

    hng64_bram #(.AW(SW + 3), .DW(32)) u_wrap (
        .a_clk(clk1x), .a_addr({wslot, cp_i[2:0]}),
        .a_be({4{cp_active && cp_i < 8'd8}}), .a_wdata(wrap_w), .a_rdata(),
        .b_clk(clk3d), .b_addr({rslot, wj}), .b_rdata(wrap_q));

    // ============================================================================================
    // clk3d: the engine, the rasteriser, the sequence
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

    // reset, the pointers and show/shown into clk3d
    logic rst3a, rst3, shown_v3a, shown_v3, shown_p3a, shown_p3;
    always_ff @(posedge clk3d) begin
        rst3a     <= reset;
        rst3      <= rst3a;
        wptr_3a   <= wptr_g;
        wptr_3b   <= wptr_3a;
        rptr_g    <= gray(rptr);
        shown_v3a <= shown_valid;
        shown_v3  <= shown_v3a;
        shown_p3a <= shown_plane;
        shown_p3  <= shown_p3a;
    end
    // and show out to clk2x
    logic show_v3, show_p3, show_v2a, show_p2a;
    always_ff @(posedge clk2x) begin
        show_v2a   <= show_v3;
        show_valid <= show_v2a;
        show_p2a   <= show_p3;
        show_plane <= show_p2a;
    end

    logic br_idle;                          // every DDR3 command has reached the arbiter
    logic blk_seen, fin_seen;

    always_ff @(posedge clk3d) begin
        geo_start   <= 1'b0;
        r_start     <= 1'b0;
        r_finish    <= 1'b0;
        r_blk_start <= 1'b0;
        q_sel       <= geo_dl_addr[0];
        if (rst3) begin
            st         <= S_OFF;
            rptr       <= '0;
            show_v3    <= 1'b0;
            show_p3    <= 1'b0;
            draw       <= 1'b0;
            wk         <= 4'd0;
            blk_seen   <= 1'b0;
            fin_seen   <= 1'b0;
        end else begin
            case (st)
                S_OFF: begin
                    if (have3d) st <= S_BLOCK;
                    else if (occ3 != '0) rptr <= rptr + 1'b1;
                end
                S_BLOCK: begin
                    r_blk_start <= 1'b1;
                    st <= S_BLOCKW;
                end
                // and the blocked copy's last writes through the bridge before anything reads it
                S_BLOCKW: begin
                    if (r_blk_done) blk_seen <= 1'b1;
                    if ((r_blk_done || blk_seen) && br_idle) begin
                        blk_seen <= 1'b0;
                        st <= S_INIT;
                    end
                end
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
                S_IDLE: if (occ3 != '0) begin
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
                // the frame's writes through the bridge before it is offered
                S_FIN: begin
                    if (r_done) fin_seen <= 1'b1;
                    if ((r_done || fin_seen) && br_idle) begin
                        fin_seen <= 1'b0;
                        show_v3  <= 1'b1;
                        show_p3  <= draw;
                        st <= S_SWAP;
                    end
                end
                // the other plane is free once the display has left it
                S_SWAP: if (shown_v3 && shown_p3 == draw) begin
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

    // the 3D's DDR3 ports, on clk3d
    logic [27:0] v3_addr, t3_addr, z3_addr, w3_addr;
    logic        v3_rd, t3_rd, z3_rd, v3_ready, t3_ready, z3_ready, v3_valid, t3_valid, z3_valid;
    logic [63:0] v3_data, t3_data, z3_data, w3_data;
    logic  [7:0] w3_be;
    logic        w3_valid, w3_ready, w3_urgent;

    hng64_geo u_geo (
        .clk(clk3d), .reset(rst3),
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
        .io_vRd_valid(v3_rd), .io_vRd_ready(v3_ready), .io_vRd_payload(v3_addr),
        .io_vData_valid(v3_valid), .io_vData_payload(v3_data),
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
        .clk(clk3d), .reset(rst3),
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
        .io_depthRd_valid(z3_rd), .io_depthRd_ready(z3_ready), .io_depthRd_payload(z3_addr),
        .io_depthData_valid(z3_valid), .io_depthData_payload(z3_data),
        .io_wr_valid(w3_valid), .io_wr_ready(w3_ready), .io_wr_payload_addr(w3_addr),
        .io_wr_payload_data(w3_data), .io_wr_payload_be(w3_be), .io_urgent(w3_urgent),
        .io_start(r_start), .io_full(r_full), .io_tag(r_tag), .io_scrub(r_scrub),
        .io_colourBase(plane_base[draw]), .io_depthBase(depth_base),
        .io_finish(r_finish), .io_done(r_done),
        .io_blockStart(r_blk_start), .io_blockSrc(tex_rom), .io_blockGroups(tex_groups),
        .io_blockDone(r_blk_done),
        .io_texBase(tex_blocked),
        .io_texRd_valid(t3_rd), .io_texRd_ready(t3_ready), .io_texRd_payload(t3_addr),
        .io_texData_valid(t3_valid), .io_texData_payload(t3_data),
        .io_busy(r_busy));

    hng64_3d_bridge u_bridge (
        .clk3d(clk3d), .rst3d(rst3), .clk2x(clk2x), .rst2x(reset),
        .v_rd(v3_rd), .t_rd(t3_rd), .z_rd(z3_rd), .v_ready(v3_ready), .t_ready(t3_ready), .z_ready(z3_ready),
        .v_addr(v3_addr), .t_addr(t3_addr), .z_addr(z3_addr),
        .v_valid(v3_valid), .t_valid(t3_valid), .z_valid(z3_valid),
        .v_data(v3_data), .t_data(t3_data), .z_data(z3_data),
        .w_valid(w3_valid), .w_ready(w3_ready), .w_addr(w3_addr), .w_data(w3_data), .w_be(w3_be),
        .w_urgent(w3_urgent), .idle(br_idle),
        .dv_addr(v_addr), .dt_addr(t_addr), .dz_addr(z_addr),
        .dv_rd(v_rd), .dt_rd(t_rd), .dz_rd(z_rd),
        .dv_ready(v_ready), .dt_ready(t_ready), .dz_ready(z_ready),
        .dv_valid(v_valid), .dt_valid(t_valid), .dz_valid(z_valid), .d_data(d_data),
        .dw_addr(w_addr), .dw_data(w_data), .dw_be(w_be), .dw_valid(w_valid), .dw_urgent(w_urgent),
        .dw_ready(w_ready));

endmodule
