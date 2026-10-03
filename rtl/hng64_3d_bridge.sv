// SPDX-License-Identifier: GPL-3.0-or-later
//
// The 3D's DDR3 traffic between its own clock (clk3d) and the arbiter's (clk2x, hng64_ddram).
//
// ONE COMMAND QUEUE, IN ORDER. The render buffer writes lines back and reads them again, and the
// texture copy writes what the texture cache later reads, so a read must not overtake a write
// made before it. Every command - the vertex, texture and depth reads and the writes - goes
// through one FIFO; on clk2x its head is offered to the matching arbiter port and taken only when
// that port takes it, and the arbiter issues what it takes in the order it takes it.
//
// Replies come back through a FIFO a read client. Each client may have at most RD reads
// outstanding (asked and not yet handed back), so its reply FIFO never overflows.
//
// `idle` (clk3d) is set when every command written has been taken by the arbiter: a count of the
// port's takes crosses back in Gray code. (The queue's own count drops as words are fetched to its
// read side, before the arbiter has them.)

module hng64_3d_bridge #(
    parameter int CA = 5,                   // command queue, 2^CA
    parameter int RA = 5                    // a reply queue, 2^RA; also the reads a client may have out
) (
    input  logic        clk3d,
    input  logic        rst3d,
    input  logic        clk2x,
    input  logic        rst2x,

    // clk3d: the 3D's ports
    input  logic        v_rd, t_rd, z_rd,
    output logic        v_ready, t_ready, z_ready,
    input  logic [27:0] v_addr, t_addr, z_addr,
    output logic        v_valid, t_valid, z_valid,
    output logic [63:0] v_data, t_data, z_data,
    input  logic        w_valid,
    output logic        w_ready,
    input  logic [27:0] w_addr,
    input  logic [63:0] w_data,
    input  logic  [7:0] w_be,
    input  logic        w_urgent,
    output logic        idle,

    // clk2x: hng64_ddram's ports
    output logic [27:0] dv_addr, dt_addr, dz_addr,
    output logic        dv_rd, dt_rd, dz_rd,
    input  logic        dv_ready, dt_ready, dz_ready,
    input  logic        dv_valid, dt_valid, dz_valid,
    input  logic [63:0] d_data,
    output logic [27:0] dw_addr,
    output logic [63:0] dw_data,
    output logic  [7:0] dw_be,
    output logic        dw_valid,
    output logic        dw_urgent,
    input  logic        dw_ready
);

    localparam logic [1:0] K_V = 2'd0, K_T = 2'd1, K_Z = 2'd2, K_W = 2'd3;

    // ---- clk3d: one command a clock, the four sources in turn ------------------------------------------
    logic [RA:0] cr_v, cr_t, cr_z;          // reads out, a client
    logic  [1:0] last;
    logic        cq_wready;
    logic  [1:0] pick;
    logic        pick_any;
    logic  [3:0] want;

    always_comb begin
        want[K_V] = v_rd && cr_v != (RA+1)'(1 << RA);
        want[K_T] = t_rd && cr_t != (RA+1)'(1 << RA);
        want[K_Z] = z_rd && cr_z != (RA+1)'(1 << RA);
        want[K_W] = w_valid;
        pick = last;
        pick_any = 1'b0;
        for (int k = 1; k <= 4; k++) begin
            logic [1:0] i;
            i = last + 2'(k);
            if (!pick_any && want[i]) begin
                pick = i;
                pick_any = 1'b1;
            end
        end
    end

    wire take = pick_any && cq_wready;
    assign v_ready = take && pick == K_V;
    assign t_ready = take && pick == K_T;
    assign z_ready = take && pick == K_Z;
    assign w_ready = take && pick == K_W;

    logic [27:0] c_addr;
    always_comb
        case (pick)
            K_V:     c_addr = v_addr;
            K_T:     c_addr = t_addr;
            K_Z:     c_addr = z_addr;
            default: c_addr = w_addr;
        endcase

    // replies, popped as they arrive (the 3D's read ports take a word a clock without a ready)
    logic r_v_ok, r_t_ok, r_z_ok;
    assign v_valid = r_v_ok;
    assign t_valid = r_t_ok;
    assign z_valid = r_z_ok;

    always_ff @(posedge clk3d) begin
        if (rst3d) begin
            last <= 2'd3;
            cr_v <= '0;
            cr_t <= '0;
            cr_z <= '0;
        end else begin
            if (take) last <= pick;
            cr_v <= cr_v + (RA+1)'(v_ready) - (RA+1)'(r_v_ok);
            cr_t <= cr_t + (RA+1)'(t_ready) - (RA+1)'(r_t_ok);
            cr_z <= cr_z + (RA+1)'(z_ready) - (RA+1)'(r_z_ok);
        end
    end

    // commands written, and the port's takes (clk2x, below) as clk3d sees them
    logic [7:0] n_wr, tk_b, tk_g, tk_3a, tk_3b;
    always_ff @(posedge clk3d) begin
        tk_3a <= tk_g;
        tk_3b <= tk_3a;
        if (rst3d) n_wr <= '0;
        else if (take) n_wr <= n_wr + 8'd1;
    end
    function automatic logic [7:0] ungray(input logic [7:0] g);
        logic [7:0] v;
        v[7] = g[7];
        for (int i = 6; i >= 0; i--) v[i] = v[i + 1] ^ g[i];
        return v;
    endfunction
    assign idle = n_wr == ungray(tk_3b);

    // ---- the queues -----------------------------------------------------------------------------------
    logic         cq_rvalid, cq_rready;
    logic [101:0] cq_rdata;

    hng64_afifo #(.DW(102), .AW(CA)) u_cmd (
        .wclk(clk3d), .wrst(rst3d), .w_valid(take), .w_ready(cq_wready),
        .w_data({pick, c_addr, w_data, w_be}), .w_count(),
        .rclk(clk2x), .rrst(rst2x), .r_valid(cq_rvalid), .r_ready(cq_rready), .r_data(cq_rdata));

    hng64_afifo #(.DW(64), .AW(RA)) u_rv (
        .wclk(clk2x), .wrst(rst2x), .w_valid(dv_valid), .w_ready(), .w_data(d_data), .w_count(),
        .rclk(clk3d), .rrst(rst3d), .r_valid(r_v_ok), .r_ready(1'b1), .r_data(v_data));
    hng64_afifo #(.DW(64), .AW(RA)) u_rt (
        .wclk(clk2x), .wrst(rst2x), .w_valid(dt_valid), .w_ready(), .w_data(d_data), .w_count(),
        .rclk(clk3d), .rrst(rst3d), .r_valid(r_t_ok), .r_ready(1'b1), .r_data(t_data));
    hng64_afifo #(.DW(64), .AW(RA)) u_rz (
        .wclk(clk2x), .wrst(rst2x), .w_valid(dz_valid), .w_ready(), .w_data(d_data), .w_count(),
        .rclk(clk3d), .rrst(rst3d), .r_valid(r_z_ok), .r_ready(1'b1), .r_data(z_data));

    // ---- clk2x: the head to its port ------------------------------------------------------------------
    // Through a skid register: the queue pops while the skid is empty, and a head the port does not
    // take that clock waits in it. The port's ready reaches only sk_v (into the queue's pop and its
    // head it missed clk2x by 0.44 ns); the skid's fields load whenever it is empty.
    logic         sk_v;
    logic [101:0] sk_d;
    wire  [101:0] hd = sk_v ? sk_d : cq_rdata;
    wire          hv = sk_v || cq_rvalid;
    wire    [1:0] hk = hd[101:100];
    assign dv_addr  = hd[99:72];
    assign dt_addr  = hd[99:72];
    assign dz_addr  = hd[99:72];
    assign dw_addr  = hd[99:72];
    assign dw_data  = hd[71:8];
    assign dw_be    = hd[7:0];
    assign dv_rd    = hv && hk == K_V;
    assign dt_rd    = hv && hk == K_T;
    assign dz_rd    = hv && hk == K_Z;
    assign dw_valid = hv && hk == K_W;
    wire taken = (hk == K_V && dv_ready) || (hk == K_T && dt_ready) ||
                 (hk == K_Z && dz_ready) || (hk == K_W && dw_ready);
    assign cq_rready = !sk_v;

    // takes are counted a clock late (tk_inc): from the skid through the port's ready into the
    // count's 16 bits it missed clk2x by 0.78 ns (3f20971)
    logic tk_inc;
    always_ff @(posedge clk2x) begin
        if (rst2x) begin
            sk_v   <= 1'b0;
            tk_inc <= 1'b0;
            tk_b   <= '0;
            tk_g   <= '0;
        end else begin
            sk_v   <= hv && !taken;
            tk_inc <= hv && taken;
            if (tk_inc) begin
                tk_b <= tk_b + 8'd1;
                tk_g <= (tk_b + 8'd1) ^ ((tk_b + 8'd1) >> 1);
            end
        end
        if (!sk_v) sk_d <= cq_rdata;
    end

    // Kept as registers: Quartus made this chain and the arbiter's h_urg one M10K shift register
    // with sys's video delay, its slow output then in front of every DDR3 client's ready (0.45 ns
    // over clk2x into the sprite's rq_head, 00a9080).
    (* altera_attribute = "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF" *) logic urg1, urg2;
    always_ff @(posedge clk2x) begin
        urg1 <= w_urgent;
        urg2 <= urg1;
    end
    assign dw_urgent = urg2;

endmodule
