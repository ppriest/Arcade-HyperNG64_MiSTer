// SPDX-License-Identifier: GPL-3.0-or-later
//
// HyperNG64 for MiSTer: the framework glue around rtl/hng64_core.sv (the board less its CPU) and
// rtl/cpu/hng64_cpu.vhd (the VR4300). Clocks: clk93 the CPU pipeline, clk1x the bus and hps_io,
// clk2x SDRAM, DDR3, video and the IO MCU (docs/ROADMAP.md, clock plan). No sound yet.
//
// Download indices: 0 the ROM set, which the HPS writes straight into DDR3 (.mra address=);
// 1 the layout blob (rtl/memory/hng64_romcfg.sv); 2 the IO MCU's ROM; 4 the NVRAM (.nvm), which
// is also uploaded back.
//
// This file is derived from MiSTer_Template's Template.sv, which is GPL-2.0-or-later; it is
// distributed here under GPL-3.0-or-later.

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;

assign AUDIO_S = 1;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

// HDMI orientation, for a monitor turned on its side. Auto is no rotation: every set is
// horizontal. The rotator taps the native raster, so it follows Flip Screen and not CRT Adjust.
wire [1:0] rot_sel    = status[64:63];
wire       rotate_en  = rot_sel[1];                 // CW or CCW
wire       rotate_ccw = (rot_sel == 2'd3);

`include "build_id.v"

// The Debug page (H1) is in the menu of the stp revision only, which defines DEBUG_ISSP; its bits
// still work from a .CFG in the release. Every switch is worded so that 0 is normal.
`ifdef DEBUG_ISSP
localparam DEBUG_MENU_HIDE = 1'b0;
`else
localparam DEBUG_MENU_HIDE = 1'b1;
`endif

localparam CONF_STR = {
	"HyperNG64;;",
	"-;",
	// H5: the HDMI scaler's options, hidden under direct video where they do nothing
	"H5O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H5O[64:63],Orientation,Auto,Off,CW,CCW;",
	"O[65],Flip Screen,Off,On;",
	"H5O[68:66],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
	"H5O[70:69],Crop,Off,432 lines,360 lines;",
	"H5O[75:71],Crop offset,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"DIP;",
	"-;",
	// H3: CRT Adjust's settings, shown when it is on
	"O[94],CRT Adjust,Off,On;",
	"H3O[99:95],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H3O[106:100],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"H3O[112:107],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"H1P1,Debug;",
	"H1P1-;",
	"H1P1O[81],Tilemap 0,On,Off;",
	"H1P1O[82],Tilemap 1,On,Off;",
	"H1P1O[83],Tilemap 2,On,Off;",
	"H1P1O[84],Tilemap 3,On,Off;",
	"H1P1O[85],Sprites,On,Off;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"J1,Button 1,Button 2,Button 3,Button 4,Start,Coin,Pause,Service,Test;",
	"jn,A,B,X,Y,Start,Select,L;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
wire         direct_video;
wire  [31:0] joystick_0, joystick_1;
wire  [64:0] rtc;

wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_upload;
wire  [7:0] nv_rdata;
wire        nv_written;

// The core cannot write the SD card; it asks the HPS to read the NVRAM back into the .mra's
// <nvram> file when the OSD opens, if the game has written NVRAM since the last save.
reg nvram_dirty = 1'b0, nvram_save = 1'b0, osd_d = 1'b0;
always @(posedge clk1x) begin
	osd_d      <= OSD_STATUS;
	nvram_save <= 1'b0;
	if (nv_written) nvram_dirty <= 1'b1;
	if (OSD_STATUS && !osd_d && nvram_dirty) begin
		nvram_save  <= 1'b1;
		nvram_dirty <= 1'b0;
	end
end

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk1x),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),
	.status_menumask({10'd0, direct_video, 1'b0, ~status[94], 1'b0, DEBUG_MENU_HIDE, 1'b0}),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(1'b0),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(nvram_save),
	.ioctl_upload_index(8'd4),
	.ioctl_din(nv_rdata),
	.ioctl_rd(),

	.RTC(rtc),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk93, clk1x, clk2x, clk_sdram, pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk93),
	.outclk_1(clk1x),
	.outclk_2(clk2x),
	.outclk_3(clk_sdram),
	.locked(pll_locked)
);
assign SDRAM_CLK = clk_sdram;
assign DDRAM_CLK = clk2x;

// held through every download: hng64_core's loader copies the BIOS on its release
wire reset = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download;

///////////////////////   INPUTS   ////////////////////////////////

// MiSTer joystick bits: 0 R, 1 L, 2 D, 3 U, then the J1 list from bit 4: 4-7 buttons 1-4,
// 8 start, 9 coin, 10 pause, 11 service, 12 test.
wire [31:0] j0 = joystick_0, j1 = joystick_1;

// MAME's coins are PORT_IMPULSE(1): one frame low per press. 2^20 clk1x is 16.8 ms.
reg [20:0] coin_t [2] = '{21'd0, 21'd0};
reg  [1:0] coin_d = 2'b00;
wire [1:0] coin = {j1[9], j0[9]};
always @(posedge clk1x) begin
	coin_d <= coin;
	for (int i = 0; i < 2; i++) begin
		if (coin[i] && !coin_d[i])             coin_t[i] <= 21'h100000;
		else if (coin_t[i] != 0)               coin_t[i] <= coin_t[i] - 1'd1;
	end
end

// IN0-IN7 as MAME's hng64_fight ports, active low. IN5 is player 2 shifted up a bit, as MAME
// has it; IN6 bit 0 is player 2's button 4.
wire [7:0] inputs [0:7];
assign inputs[0] = 8'hFF;
assign inputs[1] = 8'hFF;
assign inputs[2] = 8'hFF;
assign inputs[3] = 8'hFF;
assign inputs[4] = ~{j0[7], j0[6], j0[5], j0[4], j0[0], j0[1], j0[2], j0[3]};
assign inputs[5] = ~{j1[6], j1[5], j1[4], j1[0], j1[1], j1[2], j1[3], 1'b0};
assign inputs[6] = ~{7'd0, j1[7]};
assign inputs[7] = ~{j1[8], j0[8], 2'b00, coin_t[1] != 0, coin_t[0] != 0,
                     j0[12] | j1[12], j0[11] | j1[11]};

// DIP switches, .mra index 254. None of the fight sets has one in MAME; bit 0 of the first byte
// is the core's own Flip Screen, a fake DIP the game never reads.
reg [7:0] dsw0 = 8'h00;
always @(posedge clk1x) if (ioctl_download && ioctl_wr && ioctl_index == 16'd254 && ioctl_addr == 27'd0)
	dsw0 <= ioctl_dout;

// Flip Screen: the OSD's and the DIP's, either one; both together cancel
wire flip = status[65] ^ dsw0[0];

// Pause suspends the main CPU at its next memory access (hng64_cpu.vhd); the rest of the board
// runs, so the display holds the last frame the game drew.
reg pause_d = 1'b0, pause = 1'b0;
always @(posedge clk1x) begin
	pause_d <= j0[10] | j1[10];
	if (reset)                               pause <= 1'b0;
	else if ((j0[10] | j1[10]) && !pause_d)  pause <= ~pause;
end
wire dbg_pause;                         // ISSP source bit 1, stp revision only

///////////////////////   CPU   ///////////////////////////////////

wire        mem_request, mem_rnw, mem_req64, mem_done, rdram_granted2x, ddr3_DOUT_READY;
wire [31:0] mem_address;
wire  [2:0] mem_size;
wire  [7:0] mem_writeMask;
wire [63:0] mem_dataWrite, mem_dataRead, ddr3_DOUT;
wire        cpu_irq, cpu_reset, cpu_error;

// hng64_cpu wants the reset-state load (ss_reset) to fall while its reset is still held, then
// rewrites COP0 Status and Config two and three clk93 cycles later. The core's cpu_reset (clk1x)
// is taken into clk93, where ss_reset falls with it and the CPU's reset 16 cycles after; the
// CPU's clk1x reset is that one taken back.
reg       rst93_s = 1'b1, ss_reset = 1'b1, cpu_rst93 = 1'b1, cpu_rst1x = 1'b1;
reg [3:0] rst93_cnt = 4'd0;
always @(posedge clk93) begin
	rst93_s <= cpu_reset;
	if (rst93_s) begin
		ss_reset  <= 1'b1;
		cpu_rst93 <= 1'b1;
		rst93_cnt <= 4'd0;
	end else begin
		ss_reset <= 1'b0;
		if (&rst93_cnt) cpu_rst93 <= 1'b0;
		else            rst93_cnt <= rst93_cnt + 1'd1;
	end
end
always @(posedge clk1x) cpu_rst1x <= cpu_rst93;

hng64_cpu u_cpu
(
	.clk1x(clk1x), .clk93(clk93), .clk2x(clk2x),
	.reset_1x(cpu_rst1x), .reset_93(cpu_rst93), .ss_reset(ss_reset),
	.irq(cpu_irq), .pause(pause | dbg_pause),
	.mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
	.mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
	.mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
	.rdram_granted2x(rdram_granted2x), .ddr3_DOUT(ddr3_DOUT), .ddr3_DOUT_READY(ddr3_DOUT_READY),
	.error_any(cpu_error)
);

///////////////////////   BOARD   /////////////////////////////////

wire       ce_pix, hsync, vsync, hblank, vblank;
wire        rot_we, rot_overflow;
wire [28:0] rot_addr;
wire [63:0] rot_din;
wire  [7:0] rot_be;
wire [7:0] r, g, b;
wire [5:0] dbg_fault;
wire [7:0] dbg_load;
wire [15:0] dbg_mcu_pc;
wire       dbg_mcu_fetch;

hng64_core u_core
(
	.clk1x(clk1x), .clk2x(clk2x), .reset(reset), .sdram_init(~pll_locked),

	.mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
	.mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
	.mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
	.rdram_granted2x(rdram_granted2x), .ddr3_DOUT(ddr3_DOUT), .ddr3_DOUT_READY(ddr3_DOUT_READY),
	.cpu_irq(cpu_irq), .cpu_reset(cpu_reset),

	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
	.rtc(rtc[55:0]), .nv_rdata(nv_rdata), .nv_written(nv_written), .inputs(inputs), .flip(flip),

	.SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(), .SDRAM_CKE(SDRAM_CKE),

	.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
	.rot_we(rot_we), .rot_addr(rot_addr), .rot_din(rot_din), .rot_be(rot_be),
	.rot_overflow(rot_overflow),

	.ce_pix(ce_pix), .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
	.r(r), .g(g), .b(b),
	.lamp_we(), .lamp_addr(), .lamp_data(),
	.dbg_fault(dbg_fault), .dbg_layer_off(status[85:81]),
	.dbg_load(dbg_load), .dbg_mcu_pc(dbg_mcu_pc), .dbg_mcu_fetch(dbg_mcu_fetch)
);

///////////////////////   DEBUG PROBE   ///////////////////////////

`ifdef DEBUG_ISSP
// ISSP instance F, the bring-up questions: did the image load and the BIOS copy, is the CPU
// making requests and where, is the IO MCU running, are frames coming out. Counters have no reset
// (they count from configuration, through the resets being investigated), saturate, and clear on
// source bit 0. Source bit 1 holds the CPU as Pause does. Field table: scripts/read_issp.tcl,
// fields_F; keep the two in step.
//
//   [15:0]    frames (vblank rises)            [31:16]  CPU memory requests
//   [63:32]   the last CPU request's address   [71:64]  dbg_load (hng64_core)
//   [77:72]   dbg_fault                        [78]     CPU error_any
//   [79]      rotator queue overflow            [80]     PLL locked
//   [81]      CPU reset                         [82]     pause
//   [98:83]   IO MCU PC                         [114:99] IO MCU instructions
//   [115]     CPU interrupt line                [127:116] CPU interrupt rises
wire [7:0] src_f;
wire       dbg_clear = src_f[0];
assign     dbg_pause = src_f[1];

reg [15:0] cnt_frames = 0, cnt_req = 0, cnt_mcu = 0;
reg [11:0] cnt_irq = 0;
reg [31:0] last_addr = 0;
reg        vb_d = 0, irq_d = 0;
always @(posedge clk1x) begin
	irq_d <= cpu_irq;
	if (mem_request) last_addr <= mem_address;
	if (dbg_clear) begin
		cnt_req <= 0;
		cnt_irq <= 0;
	end else begin
		if (mem_request && ~&cnt_req)   cnt_req <= cnt_req + 1'd1;
		if (cpu_irq && !irq_d && ~&cnt_irq) cnt_irq <= cnt_irq + 1'd1;
	end
end
always @(posedge clk2x) begin
	vb_d <= vblank;
	if (dbg_clear) begin
		cnt_frames <= 0;
		cnt_mcu <= 0;
	end else begin
		if (vblank && !vb_d && ~&cnt_frames) cnt_frames <= cnt_frames + 1'd1;
		if (dbg_mcu_fetch && ~&cnt_mcu)      cnt_mcu <= cnt_mcu + 1'd1;
	end
end

issp_probe #(.INSTANCE_ID("F"), .PROBE_W(128), .SOURCE_W(8)) u_issp_f (
	.clk(clk1x),
	.probe({cnt_irq, cpu_irq, cnt_mcu, dbg_mcu_pc, pause, cpu_reset, pll_locked, rot_overflow,
	        cpu_error, dbg_fault, dbg_load, last_addr, cnt_req, cnt_frames}),
	.source(src_f)
);
`else
assign dbg_pause = 1'b0;
`endif


///////////////////////   VIDEO   /////////////////////////////////

// 512 x 448 at 25 MHz, 32.55 kHz progressive: no scandoubler (docs/HACKS.md, sync positions).
// CRT Adjust (rtl/video/hng64_crt.sv) is in the path when it is on; HDMI follows it.
wire [7:0] crt_r, crt_g, crt_b;
wire       crt_hs, crt_vs, crt_hb, crt_vb, crt_on, crt_ce;

hng64_crt u_crt
(
	.clk(clk2x), .ce(ce_pix), .adjust(status[94]),
	.hsize_idx(status[99:95]), .hpos_idx(status[106:100]), .vshift_idx(status[112:107]),
	.r_in(r), .g_in(g), .b_in(b),
	.hs_in(hsync), .vs_in(vsync), .hb_in(hblank), .vb_in(vblank),
	.active(crt_on), .ce_out(crt_ce),
	.r_out(crt_r), .g_out(crt_g), .b_out(crt_b),
	.hs_out(crt_hs), .vs_out(crt_vs), .hb_out(crt_hb), .vb_out(crt_vb)
);

assign CLK_VIDEO = clk2x;
assign CE_PIXEL  = crt_on ? crt_ce : ce_pix;
assign VGA_HS    = crt_on ? crt_hs : hsync;
assign VGA_VS    = crt_on ? crt_vs : vsync;
assign VGA_R     = crt_on ? crt_r  : r;
assign VGA_G     = crt_on ? crt_g  : g;
assign VGA_B     = crt_on ? crt_b  : b;
wire   vga_de    = crt_on ? ~(crt_hb | crt_vb) : ~(hblank | vblank);

// Crop keeps 432 lines of 448 (5x on 2160) or 360 (3x on 1080, 2x on 720, 4x on 1440).
wire [11:0] crop_size = (status[70:69] == 2'd1) ? 12'd432 :
                        (status[70:69] == 2'd2) ? 12'd360 : 12'd0;

// The picture is 4:3 whatever its pixel count, the board drove a 4:3 monitor; 3:4 turned.
video_freak video_freak
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_VS(VGA_VS),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),

	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? (rotate_en ? 12'd3 : 12'd4) : (ar - 1'd1)),
	.ARY((!ar) ? (rotate_en ? 12'd4 : 12'd3) : 12'd0),
	.CROP_SIZE(crop_size),
	.CROP_OFF(status[75:71]),
	.SCALE(status[68:66])
);

// HDMI rotation (screen_rotate_two, vendored): a copy of the frame turned into DDR3 at
// 0x24000000, which the framework's scaler shows instead; analog keeps the native raster. Its
// writes are queued in the core and share hng64_ddram with the ROM reads (sim/sys_tb +rot=1).
screen_rotate_two screen_rotate
(
	.CLK_VIDEO(clk2x), .CE_PIXEL(ce_pix),
	.VGA_R(r), .VGA_G(g), .VGA_B(b), .VGA_HS(hsync), .VGA_VS(vsync), .VGA_DE(~(hblank | vblank)),
	.rotate_ccw(rotate_ccw), .no_rotate(~rotate_en), .flip(1'b0), .two_screen(1'b0),
	.video_rotated(),
	.FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE), .FB_STRIDE(FB_STRIDE), .FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.DDRAM_CLK(), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(), .DDRAM_ADDR(rot_addr),
	.DDRAM_DIN(rot_din), .DDRAM_BE(rot_be), .DDRAM_WE(rot_we), .DDRAM_RD()
);

assign LED_USER = |dbg_fault | cpu_error | rot_overflow;

endmodule
