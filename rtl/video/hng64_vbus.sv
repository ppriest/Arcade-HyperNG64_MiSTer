// SPDX-License-Identifier: GPL-3.0-or-later
//
// The video's side of the CPU: what hng64_io.sv's v_* port writes and reads, held where
// hng64_video.sv reads it.
//
//   v_sel 0  sprite RAM, 0x20000000, 12,288 dwords
//         1  sprite registers, 0x20010000, 5 dwords
//         2  video registers, 0x20190000, 14 dwords
//         3  palette, 0x20200000, 4,096 dwords
//         4  tcram, 0x20208000, 24 dwords (hng64_io answers the vblank read at 0x48 itself)
//
// The CPU side runs on clk1x and the video side on clk2x, twice clk1x from the same PLL: the
// registers cross as they are, as everywhere else in the core, and the RAMs have a clock per
// port.
//
// SPRITE RAM IS TWO COPIES. MAME draws sprites at vblank from the list as it stands then
// (screen_update, hng64_v.cpp:745), and the CPU rewrites the list during the frame. The CPU
// writes its own copy; at vblank `snapshot` copies all of it into the one the sprite engine
// reads, 12,288 clocks, and `snapshot_done` then starts the engine's frame.
//
// THE PALETTE IS ONE RAM: the CPU writes and reads it on port A (clk1x) and the mixer reads it on
// port B (clk2x), one contributor a clock (hng64_mixer.sv). It was six copies while the mixer read
// five entries a clock.
//
// The background colour is palette entry 0 when bit 0 of the 3D buffer control's first byte is
// set, else black, as tb_video has it from MAME (hng64_v.cpp, screen_update).

module hng64_vbus (
    input  logic        clk1x,
    input  logic        clk2x,
    input  logic        reset,

    // from hng64_io, clk1x: a request a clock, acknowledged the next
    input  logic        v_req,
    input  logic        v_we,
    input  logic  [2:0] v_sel,
    input  logic [13:0] v_addr,
    input  logic  [3:0] v_be,
    input  logic [31:0] v_wdata,
    output logic        v_ack,
    output logic [31:0] v_rdata,
    input  logic  [7:0] fbcontrol0,     // m_fbcontrol[0]

    // to hng64_video, clk2x
    output logic [31:0] videoregs [0:13],
    output logic [31:0] tcram [0:23],
    output logic [31:0] spriteregs0,
    output logic [31:0] spriteregs1,
    output logic [23:0] bg_rgb,

    // The game's visible window and screen disable, as tcram_w keeps them (hng64_v.cpp:1389): taken
    // on each write to tcram 0x08 from 0x04 (x0, y0) and 0x08 (width, height); a zero width or
    // height disables the screen and leaves the window. 512 x 448 at 0, 0 until a game sets one.
    output logic  [9:0] vis_x0,
    output logic  [9:0] vis_y0,
    output logic  [9:0] vis_w,
    output logic  [9:0] vis_h,
    output logic        screen_dis,

    input  logic        snapshot,       // one clock at vblank start
    output logic        snapshot_done,  // one clock when the engine's copy is complete

    input  logic [13:0] sram_addr,      // the engine's copy, data the clock after
    output logic [31:0] sram_data,
    input  logic [11:0] pal_a,          // the mixer's read, data the clock after
    output logic [31:0] pal_d
);

    localparam logic [2:0] V_SPR = 3'd0, V_SPRREG = 3'd1, V_VREG = 3'd2, V_PAL = 3'd3,
                           V_TCRAM = 3'd4;

    function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] d,
                                          input logic [3:0] be);
        for (int k = 0; k < 4; k++) merge[8*k +: 8] = be[k] ? d[8*k +: 8] : old[8*k +: 8];
    endfunction

    // ---- registers ----------------------------------------------------------------------------------
    logic [31:0] sprregs [0:4];
    logic [31:0] pal0;                  // palette entry 0, for the background

    assign spriteregs0 = sprregs[0];
    assign spriteregs1 = sprregs[1];
    assign bg_rgb = fbcontrol0[0] ? pal0[23:0] : 24'd0;

    wire wr_spr = v_req && v_we && v_sel == V_SPR;
    wire wr_pal = v_req && v_we && v_sel == V_PAL;

    // ---- sprite RAM: the CPU's copy, and the engine's --------------------------------------------------
    logic [31:0] spr_cpu_q, spr_copy_q;
    logic [13:0] copy_rd;
    logic [13:0] copy_wr, copy_wr2;
    logic        copy_run, copy_wr_en, copy_wr_en2;
    logic [31:0] copy_d;                // the word read, registered: RAM to RAM missed clk2x by 1.6 ns

    // Each is a hng64_bram, an explicit altsyncram in synthesis: the CPU's copy is written and read
    // by the CPU on clk1x and read by the vblank copy on clk2x.
    hng64_bram #(.AW(14), .DW(32), .WORDS(12288)) u_spr_cpu (
        .a_clk(clk1x), .a_addr(v_addr), .a_be(wr_spr ? v_be : 4'd0), .a_wdata(v_wdata),
        .a_rdata(spr_cpu_q),
        .b_clk(clk2x), .b_addr(copy_rd), .b_rdata(spr_copy_q));

    hng64_bram #(.AW(14), .DW(32), .WORDS(12288)) u_spr_eng (
        .a_clk(clk2x), .a_addr(copy_wr2), .a_be({4{copy_wr_en2}}), .a_wdata(copy_d),
        .a_rdata(),
        .b_clk(clk2x), .b_addr(sram_addr), .b_rdata(sram_data));

    // the vblank copy: read two clocks ahead of the write
    always_ff @(posedge clk2x) begin
        snapshot_done <= 1'b0;
        copy_wr_en <= 1'b0;
        copy_wr_en2 <= copy_wr_en;
        copy_wr2    <= copy_wr;
        copy_d      <= spr_copy_q;
        if (reset) begin
            copy_run <= 1'b0;
        end else if (snapshot && !copy_run) begin
            copy_run <= 1'b1;
            copy_rd <= 14'd0;
        end else if (copy_run) begin
            copy_wr    <= copy_rd;
            copy_wr_en <= 1'b1;
            if (copy_rd == 14'd12287) copy_run <= 1'b0;
            else copy_rd <= copy_rd + 14'd1;
        end
        // the last write lands two clocks after the last read
        if (copy_wr_en2 && copy_wr2 == 14'd12287) snapshot_done <= 1'b1;
    end

    // ---- palette ------------------------------------------------------------------------------------
    logic [31:0] pal_cpu_q;

    hng64_bram #(.AW(12), .DW(32)) u_pal (
        .a_clk(clk1x), .a_addr(v_addr[11:0]), .a_be(wr_pal ? v_be : 4'd0), .a_wdata(v_wdata),
        .a_rdata(pal_cpu_q),
        .b_clk(clk2x), .b_addr(pal_a), .b_rdata(pal_d));

    // ---- the CPU port -------------------------------------------------------------------------------
    logic       ack_pending;
    logic [2:0] rd_sel;
    logic [4:0] rd_reg;
    wire [31:0] tc2_new = merge(tcram[2], v_wdata, v_be);   // Quartus 17 takes no part-select of a call

    always_ff @(posedge clk1x) begin
        v_ack <= 1'b0;
        if (reset) begin
            ack_pending <= 1'b0;
            pal0 <= 32'd0;
            for (int i = 0; i < 5; i++) sprregs[i] <= 32'd0;
            // MAME's machine_start fills them with 0xdeadbeef, register 0 apart (hng64.cpp:2174),
            // and the BIOS read-modifies-writes them, keeping some of the fill (MAME_KLUDGES.md)
            for (int i = 0; i < 14; i++) videoregs[i] <= (i == 0) ? 32'd0 : 32'hdeadbeef;
            for (int i = 0; i < 24; i++) tcram[i] <= 32'd0;
            vis_x0 <= 10'd0;
            vis_y0 <= 10'd0;
            vis_w <= 10'd512;
            vis_h <= 10'd448;
            screen_dis <= 1'b0;
        end else begin
            if (v_req && v_we && v_sel == V_TCRAM && v_addr == 14'd2) begin
                if (tc2_new[31:16] == 16'd0 || tc2_new[15:0] == 16'd0) begin
                    screen_dis <= 1'b1;
                end else begin
                    screen_dis <= 1'b0;
                    vis_x0 <= tcram[1][25:16];
                    vis_y0 <= tcram[1][9:0];
                    vis_w <= tc2_new[25:16];
                    vis_h <= tc2_new[9:0];
                end
            end
            if (v_req) begin
                ack_pending <= 1'b1;
                rd_sel <= v_sel;
                rd_reg <= v_addr[4:0];
                if (v_we) begin
                    case (v_sel)
                        V_SPRREG: if (v_addr < 14'd5)  sprregs[v_addr[2:0]]   <= merge(sprregs[v_addr[2:0]], v_wdata, v_be);
                        V_VREG:   if (v_addr < 14'd14) videoregs[v_addr[3:0]] <= merge(videoregs[v_addr[3:0]], v_wdata, v_be);
                        V_TCRAM:  if (v_addr < 14'd24) tcram[v_addr[4:0]]     <= merge(tcram[v_addr[4:0]], v_wdata, v_be);
                        V_PAL:    if (v_addr[11:0] == 12'd0) pal0 <= merge(pal0, v_wdata, v_be);
                        default: ;
                    endcase
                end
            end
            if (ack_pending) begin
                ack_pending <= 1'b0;
                v_ack <= 1'b1;
                case (rd_sel)
                    V_SPR:    v_rdata <= spr_cpu_q;
                    V_SPRREG: v_rdata <= (rd_reg < 5'd5)  ? sprregs[rd_reg[2:0]]   : 32'd0;
                    V_VREG:   v_rdata <= (rd_reg < 5'd14) ? videoregs[rd_reg[3:0]] : 32'd0;
                    V_PAL:    v_rdata <= pal_cpu_q;
                    default:  v_rdata <= (rd_reg < 5'd24) ? tcram[rd_reg]          : 32'd0;
                endcase
            end
        end
    end

endmodule
