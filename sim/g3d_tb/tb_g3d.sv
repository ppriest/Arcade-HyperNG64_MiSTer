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
    longint r_f [0:6], r_b [0:6], r_s [0:6];
    string  pcprof = "";
    initial void'($value$plusargs("pcprof=%s", pcprof));
    longint pc_go [0:2047], pc_stl [0:2047], pc_bub [0:2047];
    initial for (int k = 0; k < 2048; k++) begin pc_go[k] = 0; pc_stl[k] = 0; pc_bub[k] = 0; end
    longint n_tmiss, n_tfill, n_thold;
    longint n_wst [0:7];
    longint n_wemitb, n_wdrain;
    initial begin for (int k = 0; k < 8; k++) n_wst[k] = 0; n_wemitb = 0; n_wdrain = 0; end
    longint n_dmiss, n_dpend, n_dcred, n_dfifo, n_dline, n_ddrain, n_cflush;
    initial for (int k = 0; k < 7; k++) begin r_f[k] = 0; r_b[k] = 0; r_s[k] = 0; end
    function automatic void r_cnt(int k, logic v, logic r);
        if (v && r) r_f[k]++;
        else if (v) r_b[k]++;
        else r_s[k]++;
    endfunction
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
        // +pcprof=FILE: the engine's busy clocks by pcE, as issued, stalled, or a bubble (E empty,
        // or the slot after a taken branch), for each frame of a million clocks or more
        if (pcprof != "" && u_3d.geo_busy) begin
            if (!u_3d.u_geo.eLive) pc_bub[u_3d.u_geo.pcE]++;
            else if (u_3d.u_geo.stall) pc_stl[u_3d.u_geo.pcE]++;
            else pc_go[u_3d.u_geo.pcE]++;
        end
        if (u_3d.t3_rd && !u_3d.t3_ready) n_twait++;
        if (u_3d.z3_rd && !u_3d.z3_ready) n_zwait++;
        if (u_3d.w3_valid && !u_3d.w3_ready) n_wwait++;
        // the rasteriser's stages, at each one's input: a stall upstream of the slowest shows as
        // blocked, downstream of it as starved
        if (u_3d.r_busy) begin
            r_cnt(0, u_3d.u_raster.setup.io_i_valid,      u_3d.u_raster.setup.io_i_ready);
            r_cnt(1, u_3d.u_raster.walker.io_i_valid,     u_3d.u_raster.walker.io_i_ready);
            r_cnt(2, u_3d.u_raster.spanParams.io_i_valid, u_3d.u_raster.spanParams.io_i_ready);
            r_cnt(3, u_3d.u_raster.pixels.io_i_valid,     u_3d.u_raster.pixels.io_i_ready);
            r_cnt(4, u_3d.u_raster.pixUnit.io_i_valid,    u_3d.u_raster.pixUnit.io_i_ready);
            r_cnt(5, u_3d.u_raster.texCache.io_i_valid,   u_3d.u_raster.texCache.io_i_ready);
            r_cnt(6, u_3d.u_raster.renderBuf.io_i_valid,  u_3d.u_raster.renderBuf.io_i_ready);
            if (u_3d.u_raster.texCache.allocate) n_tmiss++;
            if (u_3d.u_raster.texCache.frags_io_pop_valid && !u_3d.u_raster.texCache.go_valid) n_tfill++;
            if (u_3d.u_raster.texCache.tagRd_valid && !u_3d.u_raster.texCache.canGo) n_thold++;
            // the render buffer's depth cache: misses; a lookup held by a pending victim, by no free
            // fill slot, by a full FIFO; the head waiting on DDR3 for its line, or on a drain; and
            // the colour combiner holding the depth test while it flushes a line
            n_wst[u_3d.u_raster.walker.state]++;
            if (u_3d.u_raster.walker.state == 3'd6 && !u_3d.u_raster.walker.io_o_ready) n_wemitb++;
            if (u_3d.u_raster.walker.state == 3'd7 && !u_3d.u_raster.walker.io_drained) n_wdrain++;
            if (u_3d.u_raster.renderBuf.allocate) n_dmiss++;
            if (u_3d.u_raster.renderBuf.prep_valid && !u_3d.u_raster.renderBuf.canGo) begin
                if (!u_3d.u_raster.renderBuf.fragIn_ready) n_dfifo++;
                else if (u_3d.u_raster.renderBuf.pendingHit) n_dpend++;
                else n_dcred++;
            end
            if (u_3d.u_raster.renderBuf.needFill && !u_3d.u_raster.renderBuf.lineQ_io_pop_valid) n_dline++;
            if (u_3d.u_raster.renderBuf.needFill && u_3d.u_raster.renderBuf.lineQ_io_pop_valid
                && u_3d.u_raster.renderBuf.vLeft != 0) n_ddrain++;
            if (u_3d.u_raster.renderBuf.comb_valid && !u_3d.u_raster.renderBuf.comb_ready) n_cflush++;
        end
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
            $display("prof: raster stages, fired / blocked by the next / starved, at each input: setup %0d/%0d/%0d walker %0d/%0d/%0d spans %0d/%0d/%0d pixels %0d/%0d/%0d pixunit %0d/%0d/%0d texcache %0d/%0d/%0d renderbuf %0d/%0d/%0d; texcache misses %0d, head waiting on a fill %0d, entry held %0d",
                     r_f[0], r_b[0], r_s[0], r_f[1], r_b[1], r_s[1], r_f[2], r_b[2], r_s[2], r_f[3], r_b[3], r_s[3],
                     r_f[4], r_b[4], r_s[4], r_f[5], r_b[5], r_s[5], r_f[6], r_b[6], r_s[6], n_tmiss, n_tfill, n_thold);
            for (int k = 0; k < 7; k++) begin r_f[k] = 0; r_b[k] = 0; r_s[k] = 0; end
            $display("prof: depth cache misses %0d; lookup held by a pending victim %0d, no fill slot %0d, FIFO full %0d; head waiting on DDR3 %0d, on a drain %0d; colour flush holding %0d",
                     n_dmiss, n_dpend, n_dcred, n_dfifo, n_dline, n_ddrain, n_cflush);
            $display("prof: span walker clocks: idle %0d decide %0d recover-left %0d right-to-enter %0d left-to-exit %0d right-to-exit %0d emit %0d (held %0d) advance %0d (waiting to drain %0d)",
                     n_wst[0], n_wst[1], n_wst[2], n_wst[3], n_wst[4], n_wst[5], n_wst[6], n_wemitb, n_wst[7], n_wdrain);
            for (int k = 0; k < 8; k++) n_wst[k] = 0;
            n_wemitb = 0; n_wdrain = 0;
            n_dmiss = 0; n_dpend = 0; n_dcred = 0; n_dfifo = 0; n_dline = 0; n_ddrain = 0; n_cflush = 0;
            n_tmiss = 0; n_tfill = 0; n_thold = 0;
            if (pcprof != "" && n_geo >= 1000000) begin
                int fd;
                fd = $fopen(pcprof, "w");
                for (int k = 0; k < 2048; k++)
                    if (pc_go[k] + pc_stl[k] + pc_bub[k] != 0)
                        $fdisplay(fd, "%0d %0d %0d %0d", k, pc_go[k], pc_stl[k], pc_bub[k]);
                $fclose(fd);
            end
            for (int k = 0; k < 2048; k++) begin pc_go[k] = 0; pc_stl[k] = 0; pc_bub[k] = 0; end
            n_all = 0; n_geo = 0; n_gstall = 0; n_rbusy = 0; n_ronly = 0; n_idle = 0; n_flush = 0;
            n_fin = 0; n_swap = 0; n_ups = 0; n_tris = 0; n_tqmax = 0; n_vwait = 0; n_twait = 0; n_zwait = 0; n_wwait = 0;
        end
    end

endmodule
