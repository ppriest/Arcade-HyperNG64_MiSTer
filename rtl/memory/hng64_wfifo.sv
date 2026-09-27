// SPDX-License-Identifier: GPL-3.0-or-later
//
// The HDMI rotator's writes, queued for hng64_ddram. screen_rotate_two makes a one-clock write
// per pixel and does not look at DDRAM_BUSY, so each is taken here or lost; `overflow` is sticky
// if one ever was. Its data is {pixel, pixel} with BE 0F or F0, so one copy of the pixel and the
// half are kept. After the MS32 core's ms32_ddram_mux.

module hng64_wfifo #(
    parameter int LOG2 = 8
) (
    input  logic        clk,
    input  logic        reset,

    input  logic        in_we,
    input  logic [28:0] in_addr,
    input  logic [63:0] in_din,
    input  logic  [7:0] in_be,

    output logic [28:0] w_addr,
    output logic [63:0] w_din,
    output logic  [7:0] w_be,
    output logic        w_valid,
    output logic        w_urgent,       // half full
    input  logic        w_ready,

    output logic        overflow
);

    localparam int W = 29 + 32 + 1;
    logic [W-1:0]  mem [0:(1 << LOG2) - 1];
    logic [LOG2:0] wp, rp;
    wire  [LOG2:0] fill = wp - rp;      // entries not yet loaded into the head
    wire           full = fill[LOG2];
    logic [W-1:0]  head;

    // the head is a registered read of mem[rp], enabled only when it loads, so an entry is read no
    // earlier than the clock after it was written
    wire load = (!w_valid || w_ready) && (fill != 0);
    always_ff @(posedge clk) begin
        if (in_we && !full) mem[wp[LOG2-1:0]] <= {in_addr, in_be[4] ? in_din[63:32] : in_din[31:0], in_be[4]};
        if (load) head <= mem[rp[LOG2-1:0]];
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            wp <= '0;
            rp <= '0;
            w_valid <= 1'b0;
            overflow <= 1'b0;
        end else begin
            if (in_we && !full) wp <= wp + 1'b1;
            if (in_we && full)  overflow <= 1'b1;
            if (load)           rp <= rp + 1'b1;
            if (load)           w_valid <= 1'b1;
            else if (w_ready)   w_valid <= 1'b0;
        end
    end

    assign w_addr   = head[W-1 -: 29];
    assign w_din    = {2{head[32:1]}};
    assign w_be     = head[0] ? 8'hF0 : 8'h0F;
    assign w_urgent = fill[LOG2-1] | full;

endmodule
