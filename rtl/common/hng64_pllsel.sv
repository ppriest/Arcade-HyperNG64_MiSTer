// SPDX-License-Identifier: GPL-3.0-or-later
//
// A clock chosen on the OSD and applied at a reset: rewrites one register of a reconfigurable PLL
// through sys/pll_cfg, as sys_top.v does the HDMI PLL's (the register, then a write to start,
// address 2), and holds `hold` until the PLL has its new setting and is locked.
//
//   the CPU's (rtl/pll/pll_cpu.v)  ADDR 4, the M counter: 75 / 87.5 / 100 MHz. Built and timed
//                                  at 75, so 87.5 and 100 are not checked by timing analysis.
//   the 3D's (rtl/pll/pll_0002.v)  ADDR 5, outclk_0's C counter: 100 / 83.3 / 71.4 MHz. Built
//                                  and timed at 100, so the others only gain slack.
//
// A setting of 3 is ignored. The charge pump and bandwidth stay as Quartus chose them for the
// built setting; whether the CPU PLL's other M values lock as cleanly is unmeasured.

module hng64_pllsel #(
    parameter logic  [5:0] ADDR = 6'd4,
    parameter logic [31:0] V0 = 32'h0000_0303,  // the built setting
    parameter logic [31:0] V1 = 32'h0002_0403,
    parameter logic [31:0] V2 = 32'h0000_0404
) (
    input  logic        clk,            // the 50 MHz reference
    input  logic  [1:0] sel,            // the OSD setting (any clock)
    input  logic        apply,          // the core's reset (any clock): a change is made only then
    input  logic        locked,         // the PLL's

    output logic        hold,

    // to sys/pll_cfg
    input  logic        mgmt_waitrequest,
    output logic        mgmt_write,
    output logic  [5:0] mgmt_address,
    output logic [31:0] mgmt_writedata
);

    function automatic logic [31:0] value(input logic [1:0] s);
        case (s)
            2'd1:    return V1;
            2'd2:    return V2;
            default: return V0;
        endcase
    endfunction

    logic [1:0] sel_a, sel_b, cur = 2'd0, want;
    logic       ap_a, ap_b, lk_a, lk_b;
    always_ff @(posedge clk) begin
        sel_a <= sel;  sel_b <= sel_a;
        ap_a  <= apply; ap_b <= ap_a;
        lk_a  <= locked; lk_b <= lk_a;
    end

    typedef enum logic [1:0] { C_IDLE, C_REG, C_START, C_WAIT } cst_t;
    cst_t        st = C_IDLE;
    logic        seen;
    logic [19:0] tmo;

    assign hold = st != C_IDLE || !lk_b;

    always_ff @(posedge clk) begin
        case (st)
            C_IDLE: begin
                mgmt_write <= 1'b0;
                if (ap_b && sel_b != cur && sel_b != 2'd3) begin
                    want           <= sel_b;
                    mgmt_address   <= ADDR;
                    mgmt_writedata <= value(sel_b);
                    mgmt_write     <= 1'b1;
                    st <= C_REG;
                end
            end
            C_REG: if (!mgmt_waitrequest) begin
                mgmt_address   <= 6'd2;
                mgmt_writedata <= 32'd0;
                st <= C_START;
            end
            C_START: if (!mgmt_waitrequest) begin
                mgmt_write <= 1'b0;
                seen <= 1'b0;
                tmo  <= '0;
                st <= C_WAIT;
            end
            // pll_cfg (WAIT_FOR_LOCK) holds waitrequest until the PLL has its new setting
            default: begin
                tmo <= tmo + 1'b1;
                if (mgmt_waitrequest) seen <= 1'b1;
                if ((seen && !mgmt_waitrequest) || &tmo) begin
                    cur <= want;
                    st  <= C_IDLE;
                end
            end
        endcase
    end

endmodule
