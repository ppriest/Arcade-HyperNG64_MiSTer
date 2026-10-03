// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wrapper for hng64_3d behind hng64_ddram, as hng64_core connects them: sim/g3d_tb/main.cpp plays
// a capture's display-list events in through the CPU side and serves the DDRAM port. Arrays are
// packed here for the C++ side.

module tb_g3d (
    input  logic         clk1x,
    input  logic         clk2x,
    input  logic         clk3d,
    input  logic         reset,

    input  logic         dl_we,
    input  logic   [6:0] dl_addr,
    input  logic   [3:0] dl_be,
    input  logic  [31:0] dl_wdata,
    input  logic         dl_up,
    output logic         dl_busy,
    output logic         dl_upbusy,
    output logic         dl_full,
    input  logic [255:0] texwrap,           // byte k at bits 8k+7:8k
    input  logic         vblank,
    input  logic         clear_en,

    input  logic         samsho,
    input  logic  [27:0] vert_base,
    input  logic  [23:0] vert_len,
    input  logic  [27:0] tex_rom,
    input  logic  [11:0] tex_groups,

    output logic         show_valid,
    output logic         show_plane,
    input  logic         shown_valid,
    input  logic         shown_plane,

    input  logic         DDRAM_BUSY,
    output logic   [7:0] DDRAM_BURSTCNT,
    output logic  [28:0] DDRAM_ADDR,
    input  logic  [63:0] DDRAM_DOUT,
    input  logic         DDRAM_DOUT_READY,
    output logic         DDRAM_RD,
    output logic  [63:0] DDRAM_DIN,
    output logic   [7:0] DDRAM_BE,
    output logic         DDRAM_WE,

    output logic   [3:0] state,
    output logic   [5:0] queued,

    // other readers of the port, as the core has them: a PRIO one (the video engines) and a plain
    // one (main memory); main.cpp raises and holds their requests
    input  logic         vid_rd,
    input  logic  [27:0] vid_addr,
    output logic         vid_ready,
    input  logic         cpu_rd,
    input  logic  [27:0] cpu_addr,
    output logic         cpu_ready
);

    localparam logic [27:0] D3_TEX = 28'hE000000, D3_DEPTH = 28'hF000000,
                            D3_COL0 = 28'hF100000, D3_COL1 = 28'hF180000;

    logic  [7:0] wrap [0:31];
    always_comb for (int k = 0; k < 32; k++) wrap[k] = texwrap[8 * k +: 8];

    logic [27:0] plane_base [0:1];
    assign plane_base[0] = D3_COL0;
    assign plane_base[1] = D3_COL1;

    logic [27:0] c_addr [0:4];
    logic        c_rd [0:4], c_ready [0:4], c_valid [0:4];
    assign c_addr[3] = vid_addr;
    assign c_rd[3]   = vid_rd;
    assign vid_ready = c_ready[3];
    assign c_addr[4] = cpu_addr;
    assign c_rd[4]   = cpu_rd;
    assign cpu_ready = c_ready[4];
    logic [63:0] d_data;
    logic [27:0] w_addr;
    logic [63:0] w_data;
    logic  [7:0] w_be;
    logic        w_valid, w_urgent, w_ready;

    hng64_3d u_3d (
        .clk1x(clk1x), .clk2x(clk2x), .clk3d(clk3d), .reset(reset),
        .dl_we(dl_we), .dl_addr(dl_addr), .dl_be(dl_be), .dl_wdata(dl_wdata), .dl_up(dl_up),
        .dl_busy(dl_busy), .dl_upbusy(dl_upbusy), .dl_full(dl_full), .texwrap(wrap),
        .vblank(vblank), .clear_en(clear_en),
        .have3d(1'b1), .samsho(samsho), .vert_base(vert_base), .vert_len(vert_len),
        .tex_rom(tex_rom), .tex_groups(tex_groups), .tex_blocked(D3_TEX),
        .depth_base(D3_DEPTH), .plane_base(plane_base),
        .show_valid(show_valid), .show_plane(show_plane),
        .shown_valid(shown_valid), .shown_plane(shown_plane),
        .v_addr(c_addr[0]), .v_rd(c_rd[0]), .v_ready(c_ready[0]), .v_valid(c_valid[0]),
        .t_addr(c_addr[1]), .t_rd(c_rd[1]), .t_ready(c_ready[1]), .t_valid(c_valid[1]),
        .z_addr(c_addr[2]), .z_rd(c_rd[2]), .z_ready(c_ready[2]), .z_valid(c_valid[2]),
        .d_data(d_data),
        .w_addr(w_addr), .w_data(w_data), .w_be(w_be), .w_valid(w_valid),
        .w_urgent(w_urgent), .w_ready(w_ready),
        .dbg_state(state), .dbg_queued(queued));

    hng64_ddram #(.N(5), .PRIO(5'b01000), .ORD(5'b00111)) u_ddr (
        .clk(clk2x), .reset(reset),
        .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
        .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
        .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
        .w_addr({4'b0011, w_addr[27:3]}), .w_din(w_data), .w_be(w_be), .w_valid(w_valid),
        .w_urgent(w_urgent), .w_ready(w_ready),
        .c_addr(c_addr), .c_rd(c_rd), .c_ready(c_ready), .c_data(d_data), .c_valid(c_valid));

    // +prof: where a frame's clk3d clocks go, printed as it is offered (S_FIN to S_SWAP)
    bit prof = 1'b0;
    initial prof = $test$plusargs("prof");
    longint n_all, n_geo, n_gstall, n_rbusy, n_ronly, n_idle, n_flush, n_fin, n_swap;
    longint n_vwait, n_twait, n_zwait, n_wwait, n_tris, n_ups, n_tqmax;
    logic [3:0] st_q;
    longint n_stall [0:63];                 // the engine's stalled clocks by the opcode in E
    initial for (int k = 0; k < 64; k++) n_stall[k] = 0;
    always @(posedge clk3d) if (prof) begin
        st_q <= u_3d.st;
        n_all++;
        if (u_3d.geo_busy) n_geo++;
        if (u_3d.g_valid && !u_3d.g_ready) n_gstall++;
        if (longint'(9'(u_3d.tq_w - u_3d.tq_r)) > n_tqmax) n_tqmax = longint'(9'(u_3d.tq_w - u_3d.tq_r));
        if (u_3d.tri_valid && u_3d.tri_ready) n_tris++;
        if (u_3d.r_busy) n_rbusy++;
        if (u_3d.r_busy && !u_3d.geo_busy) n_ronly++;
        if (u_3d.st == 4'd6 && u_3d.occ3 == '0) n_idle++;
        if (u_3d.st == 4'd9) n_flush++;
        if (u_3d.st == 4'd10) n_fin++;
        if (u_3d.st == 4'd11) n_swap++;
        if (u_3d.st == 4'd8) n_ups++;
        if (u_3d.v3_rd && !u_3d.v3_ready) n_vwait++;
        if (u_3d.geo_busy && u_3d.u_geo.stall) n_stall[u_3d.u_geo.o]++;
        if (u_3d.t3_rd && !u_3d.t3_ready) n_twait++;
        if (u_3d.z3_rd && !u_3d.z3_ready) n_zwait++;
        if (u_3d.w3_valid && !u_3d.w3_ready) n_wwait++;
        if (st_q == 4'd10 && u_3d.st == 4'd11) begin
            $display("prof: %0d clk3d: geo busy %0d (out blocked %0d), raster busy %0d (geo idle %0d), queue empty %0d, flush %0d, fin %0d, swap %0d; %0d uploads, %0d triangles (FIFO up to %0d); ports refused: vert %0d tex %0d depth %0d write %0d",
                     n_all, n_geo, n_gstall, n_rbusy, n_ronly, n_idle, n_flush, n_fin, n_swap, n_ups, n_tris, n_tqmax,
                     n_vwait, n_twait, n_zwait, n_wwait);
            begin
                longint top; int k_top;
                $write("prof: engine stalls by opcode:");
                for (int r = 0; r < 6; r++) begin
                    top = 0; k_top = 0;
                    for (int k = 0; k < 64; k++) if (n_stall[k] > top) begin top = n_stall[k]; k_top = k; end
                    if (top == 0) break;
                    $write(" %0d:%0d", k_top, top);
                    n_stall[k_top] = -n_stall[k_top];
                end
                $display("");
                for (int k = 0; k < 64; k++) n_stall[k] = 0;
            end
            n_all = 0; n_geo = 0; n_gstall = 0; n_rbusy = 0; n_ronly = 0; n_idle = 0; n_flush = 0;
            n_fin = 0; n_swap = 0; n_ups = 0; n_tris = 0; n_tqmax = 0; n_vwait = 0; n_twait = 0; n_zwait = 0; n_wwait = 0;
        end
    end

endmodule
