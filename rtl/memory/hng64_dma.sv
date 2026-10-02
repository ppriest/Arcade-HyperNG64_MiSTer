// SPDX-License-Identifier: GPL-3.0-or-later
//
// The main board's DMA (do_dma, hng64.cpp:811): dwords from one address to another, len + 1
// of them. MAME does the whole copy inside the CPU's write to the length register; here
// hng64_io.sv holds that write unacknowledged until the copy is done, so the CPU sees the same
// thing - nothing between the write and the copy being complete.
//
// The copy goes through the backing-store port (hng64_mainmem's st_*), which the top level
// hands to this module while `active`: the bridge cannot use it then, because the CPU is
// waiting on the I/O write that started the copy. MAME's copy goes through the whole address
// space; this one reaches the backing store only, which covers the one copy the boot makes
// (1,024 dwords from `gameprg` + 0x200 to RAM 0x1000) and every copy of that kind. A source or
// destination outside it raises `err_nonstore` and is copied from and to nowhere.
//
// Bytes move in address order: a dword at A is bytes (A & 4)..(A & 4)+3 of the beat at A & ~7,
// byte k of a beat at [8k+7:8k] (the bridge's convention), so no byte is reordered.
//
// go and done are toggles from and to hng64_io's clk1x. clk2x is twice clk1x from the same PLL,
// so, as in the bridge, the registers cross without synchronisers.

module hng64_dma (
    input  logic        clk,            // clk2x
    input  logic        reset,

    input  logic [31:0] src,            // held by hng64_io from go to done
    input  logic [31:0] dst,
    input  logic [31:0] count,          // dwords
    input  logic        go,
    output logic        done,
    output logic        active,

    output logic        st_req,
    output logic        st_we,
    output logic [31:0] st_addr,
    output logic  [2:0] st_beats,
    output logic [63:0] st_wdata,
    output logic  [7:0] st_be,
    input  logic        st_rvalid,
    input  logic [63:0] st_rdata,
    input  logic        st_wdone,

    output logic        err_nonstore    // sticky
);

    // the same table as hng64_bus.sv's is_store
    function automatic logic is_store(input logic [31:0] a);
        return (a < 32'h0100_0000)
            || (a >= 32'h0400_0000 && a < 32'h0600_0000)
            || (a >= 32'h1FC0_0000 && a < 32'h1FC8_0000)
            || (a >= 32'h2010_0000 && a < 32'h2018_0000)
            || (a >= 32'h3010_0000 && a < 32'h3016_0000)
            || (a >= 32'h3020_0000 && a < 32'h3026_0000)
            || (a >= 32'h6020_0000 && a < 32'h6040_0000);
    endfunction

    typedef enum logic [1:0] { D_IDLE, D_READ, D_WRITE } state_t;
    state_t st;

    logic [31:0] s, d, left;
    logic [31:0] dword;
    logic        waiting;               // a request is out and its answer has not come back

    // is_store of the two addresses, registered: through the range compares into the data select
    // missed clk2x by 1.65 ns. D_READ waits a clock (settle) after s moves, for s_ok to follow;
    // D_WRITE comes at least a clock after that, so d_ok has followed d.
    logic        s_ok, d_ok, settle;
    always_ff @(posedge clk) begin
        s_ok <= is_store(s);
        d_ok <= is_store(d);
    end

    assign active   = (st != D_IDLE);
    assign st_beats = 3'd1;

    always_ff @(posedge clk) begin
        st_req <= 1'b0;
        if (reset) begin
            st <= D_IDLE;
            done <= 1'b0;
            waiting <= 1'b0;
            err_nonstore <= 1'b0;
        end else begin
            case (st)
                D_IDLE: if (go != done) begin
                    s <= src;
                    d <= dst;
                    left <= count;
                    waiting <= 1'b0;
                    settle <= 1'b1;
                    st <= (count == 32'd0) ? D_IDLE : D_READ;
                    if (count == 32'd0) done <= go;
                end

                D_READ: begin
                    if (settle) begin
                        settle <= 1'b0;
                    end else if (!waiting) begin
                        if (s_ok) begin
                            st_req  <= 1'b1;
                            st_we   <= 1'b0;
                            st_addr <= {s[31:3], 3'b000};
                            waiting <= 1'b1;
                        end else begin
                            err_nonstore <= 1'b1;
                            dword <= 32'd0;
                            st <= D_WRITE;
                        end
                    end else if (st_rvalid) begin
                        dword   <= s[2] ? st_rdata[63:32] : st_rdata[31:0];
                        waiting <= 1'b0;
                        st <= D_WRITE;
                    end
                end

                default: begin                  // D_WRITE
                    if (!waiting) begin
                        if (d_ok) begin
                            st_req   <= 1'b1;
                            st_we    <= 1'b1;
                            st_addr  <= {d[31:3], 3'b000};
                            st_wdata <= {dword, dword};
                            st_be    <= d[2] ? 8'hf0 : 8'h0f;
                            waiting  <= 1'b1;
                        end else begin
                            err_nonstore <= 1'b1;
                            waiting <= 1'b1;    // nothing to wait for: fall through below
                        end
                    end
                    if ((waiting && st_wdone) || (waiting && !d_ok)) begin
                        waiting <= 1'b0;
                        settle  <= 1'b1;
                        s <= s + 32'd4;
                        d <= d + 32'd4;
                        left <= left - 32'd1;
                        if (left == 32'd1) begin
                            done <= go;
                            st <= D_IDLE;
                        end else begin
                            st <= D_READ;
                        end
                    end
                end
            endcase
        end
    end

endmodule
