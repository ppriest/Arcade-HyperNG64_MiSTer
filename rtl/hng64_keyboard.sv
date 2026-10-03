// SPDX-License-Identifier: GPL-3.0-or-later
//
// MAME's default keys (src/emu/inpttype.ipp), in this core's J1 joystick layout so they OR into the
// pads: right, left, down, up at bits 0-3, buttons 1-4 at 4-7, Start 8, Coin 9, Pause 10, Service
// 11, Test 12. After the Konami GX core's gx_keyboard.sv.
//
//   P1  arrows, LCtrl LAlt Space LShift, 1 start, 5 coin
//   P2  R F D G, A S Q W, 2 start, 6 coin
//   P pause, 9 service (MAME's Service 1), F2 test (MAME's Service Mode)
module hng64_keyboard (
	input             clk,
	input      [10:0] ps2_key,          // [10] toggles per event, [9] pressed, [8] E0 prefix, [7:0] set-2 code
	output reg [31:0] key0 = 32'd0,
	output reg [31:0] key1 = 32'd0
);

wire p = ps2_key[9];
reg  tog = 1'b0;

always @(posedge clk) begin
	tog <= ps2_key[10];
	if (ps2_key[10] != tog)
		case (ps2_key[8:0])
			9'h175: key0[3]  <= p;      // up
			9'h172: key0[2]  <= p;      // down
			9'h16B: key0[1]  <= p;      // left
			9'h174: key0[0]  <= p;      // right
			9'h014: key0[4]  <= p;      // left ctrl
			9'h011: key0[5]  <= p;      // left alt
			9'h029: key0[6]  <= p;      // space
			9'h012: key0[7]  <= p;      // left shift
			9'h016: key0[8]  <= p;      // 1
			9'h02E: key0[9]  <= p;      // 5
			9'h04D: key0[10] <= p;      // P
			9'h046: key0[11] <= p;      // 9
			9'h006: key0[12] <= p;      // F2

			9'h02D: key1[3]  <= p;      // R
			9'h02B: key1[2]  <= p;      // F
			9'h023: key1[1]  <= p;      // D
			9'h034: key1[0]  <= p;      // G
			9'h01C: key1[4]  <= p;      // A
			9'h01B: key1[5]  <= p;      // S
			9'h015: key1[6]  <= p;      // Q
			9'h01D: key1[7]  <= p;      // W
			9'h01E: key1[8]  <= p;      // 2
			9'h036: key1[9]  <= p;      // 6
			default: ;
		endcase
end

endmodule
