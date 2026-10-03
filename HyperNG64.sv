// SPDX-License-Identifier: GPL-3.0-or-later
//
// HyperNG64 for MiSTer: the framework glue around rtl/hng64_core.sv (the board less its CPU) and
// rtl/cpu/hng64_cpu.vhd (the VR4300). Clocks: clk1x the bus and hps_io, clk2x SDRAM, DDR3, video
// and the IO MCU; the CPU on its own PLL (c93, c1x, c2x) and the 3D on its own (clk3d), each
// crossing to the board through FIFOs (docs/ROADMAP.md, clock plan). No sound yet.
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

assign AUDIO_S = 1;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

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
	"O[65],Flip Screen,Off,On;",
	"O[114:113],CPU clock (on reset),75 MHz,87.5 MHz,100 MHz;",
	"O[116:115],3D clock (on reset),100 MHz,83.3 MHz,71.4 MHz;",
	"O[119:117],Game speed,100%,90%,80%,75%,67%,50%;",
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
	"H1P1O[86],3D,On,Off;",
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
wire  [31:0] joy_pad_0, joy_pad_1;      // hps_io; joystick_N adds the keyboard (hng64_keyboard)
wire  [31:0] joystick_0, joystick_1;
wire  [10:0] ps2_key;
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
	.joystick_0(joy_pad_0),
	.joystick_1(joy_pad_1),
	.ps2_key(ps2_key)
);

// MAME's default arcade keys, ORed into the pads
wire [31:0] key_0, key_1;
hng64_keyboard u_keys (.clk(clk1x), .ps2_key(ps2_key), .key0(key_0), .key1(key_1));
assign joystick_0 = joy_pad_0 | key_0;
assign joystick_1 = joy_pad_1 | key_1;

///////////////////////   CLOCKS   ///////////////////////////////

wire clk3d, clk1x, clk2x, clk_sdram, pll_locked;
wire [63:0] main_to_pll, main_from_pll;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk3d),
	.outclk_1(clk1x),
	.outclk_2(clk2x),
	.outclk_3(clk_sdram),
	.locked(pll_locked),
	.reconfig_to_pll(main_to_pll),
	.reconfig_from_pll(main_from_pll)
);

// The 3D's clock from the OSD, applied at a reset: outclk_0's divider of the PLL's 500 MHz
// counters, 5, 6 or 7 (100, 83.3, 71.4 MHz). Built and timed at 100, so the slower ones only gain
// slack. The core is held in reset (clk3d_hold) until it is done.
wire        maincfg_wait, maincfg_write, clk3d_hold;
wire  [5:0] maincfg_addr;
wire [31:0] maincfg_data;
pll_cfg pll_cfg_main
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(maincfg_wait),
	.mgmt_read(0),
	.mgmt_write(maincfg_write),
	.mgmt_readdata(),
	.mgmt_address(maincfg_addr),
	.mgmt_writedata(maincfg_data),
	.reconfig_to_pll(main_to_pll),
	.reconfig_from_pll(main_from_pll)
);

hng64_pllsel #(.ADDR(6'd5), .V0(32'h0002_0302), .V1(32'h0000_0303), .V2(32'h0002_0403)) u_3dclk
(
	.clk(CLK_50M), .sel(status[116:115]), .apply(reset), .locked(pll_locked), .hold(clk3d_hold),
	.mgmt_waitrequest(maincfg_wait), .mgmt_write(maincfg_write), .mgmt_address(maincfg_addr),
	.mgmt_writedata(maincfg_data)
);
// SDRAM_CLK through a DDIO output, so it leaves from the I/O cell as the data does: as a plain
// assign the PLL output reached the pin through fabric routing and the read capture missed clk2x
// by 2.4 ns. datain_h 1, datain_l 0: the pin follows clk_sdram, whose phase stays the PLL's.
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b1),
	.datain_l(1'b0),
	.outclock(clk_sdram),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

assign DDRAM_CLK = clk2x;

// held through every download: hng64_core's loader copies the BIOS on its release
wire reset = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download | clk3d_hold;

///////////////////////   INPUTS   ////////////////////////////////

// MiSTer joystick bits: 0 R, 1 L, 2 D, 3 U, then the J1 list from bit 4: 4-7 buttons 1-4,
// 8 start, 9 coin, 10 pause, 11 service, 12 test.
wire [31:0] dbg_j0;                     // stp: ISSP source K, held into player 1's inputs
wire [31:0] j0 = joystick_0 | dbg_j0, j1 = joystick_1;

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

// The CPU on its own PLL (rtl/pll/pll_cpu.v): c93 its pipeline, c1x and c2x its memory port, in
// the 3:2:4 the vendored VR4300 needs, at 75 MHz as built and timed, or 87.5 or 100 MHz from the
// OSD (hng64_pllsel, applied at a reset). hng64_cpu_cdc carries its port to the board's clk1x and
// clk2x. The board side keeps the mem_* names; the CPU's are c_*.
wire        c93, c1x, c2x, cpu_locked;
wire [63:0] cpu_to_pll, cpu_from_pll;
pll_cpu pll_cpu
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(c93),
	.outclk_1(c1x),
	.outclk_2(c2x),
	.locked(cpu_locked),
	.reconfig_to_pll(cpu_to_pll),
	.reconfig_from_pll(cpu_from_pll)
);

wire        cpucfg_wait, cpucfg_write, cpuclk_hold;
wire  [5:0] cpucfg_addr;
wire [31:0] cpucfg_data;
pll_cfg pll_cfg_cpu
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cpucfg_wait),
	.mgmt_read(0),
	.mgmt_write(cpucfg_write),
	.mgmt_readdata(),
	.mgmt_address(cpucfg_addr),
	.mgmt_writedata(cpucfg_data),
	.reconfig_to_pll(cpu_to_pll),
	.reconfig_from_pll(cpu_from_pll)
);

hng64_pllsel #(.ADDR(6'd4), .V0(32'h0000_0303), .V1(32'h0002_0403), .V2(32'h0000_0404)) u_cpuclk
(
	.clk(CLK_50M), .sel(status[114:113]), .apply(reset), .locked(cpu_locked), .hold(cpuclk_hold),
	.mgmt_waitrequest(cpucfg_wait), .mgmt_write(cpucfg_write), .mgmt_address(cpucfg_addr),
	.mgmt_writedata(cpucfg_data)
);

wire        mem_request, mem_rnw, mem_req64, mem_done, rdram_granted2x, ddr3_DOUT_READY;
wire [31:0] mem_address;
wire  [2:0] mem_size;
wire  [7:0] mem_writeMask;
wire [63:0] mem_dataWrite, mem_dataRead, ddr3_DOUT;
wire        c_request, c_rnw, c_req64, c_done, c_granted2x, c_DOUT_READY;
wire [31:0] c_address;
wire  [2:0] c_size;
wire  [7:0] c_writeMask;
wire [63:0] c_dataWrite, c_dataRead, c_DOUT;
wire        cpu_irq, cpu_reset, cpu_error;
wire [31:0] cpu_pc;
wire [127:0] cpu_cop0;

// hng64_cpu wants the reset-state load (ss_reset) to fall while its reset is still held, then
// rewrites COP0 Status and Config two and three c93 cycles later. The core's cpu_reset (clk1x),
// and hng64_pllsel's hold while the clock changes, are taken into c93 through two registers, where
// ss_reset falls with them and the CPU's reset 16 cycles after; the CPU's c1x reset is that one
// taken across.
reg       rst93_a = 1'b1, rst93_s = 1'b1, ss_reset = 1'b1, cpu_rst93 = 1'b1, cpu_rst1x = 1'b1;
reg [3:0] rst93_cnt = 4'd0;
always @(posedge c93) begin
	rst93_a <= cpu_reset | cpuclk_hold;
	rst93_s <= rst93_a;
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
always @(posedge c1x) cpu_rst1x <= cpu_rst93;

// the interrupt line and Pause into the CPU's c1x
reg irq_a = 1'b0, irq_c = 1'b0, pause_a = 1'b0, pause_c = 1'b0;
always @(posedge c1x) begin
	irq_a   <= cpu_irq;
	irq_c   <= irq_a;
	pause_a <= pause | dbg_pause;
	pause_c <= pause_a;
end

hng64_cpu u_cpu
(
	.clk1x(c1x), .clk93(c93), .clk2x(c2x),
	.reset_1x(cpu_rst1x), .reset_93(cpu_rst93), .ss_reset(ss_reset),
	.irq(irq_c), .pause(pause_c),
	.mem_request(c_request), .mem_rnw(c_rnw), .mem_address(c_address),
	.mem_req64(c_req64), .mem_size(c_size), .mem_writeMask(c_writeMask),
	.mem_dataWrite(c_dataWrite), .mem_dataRead(c_dataRead), .mem_done(c_done),
	.rdram_granted2x(c_granted2x), .ddr3_DOUT(c_DOUT), .ddr3_DOUT_READY(c_DOUT_READY),
	.dbg_pc(cpu_pc), .dbg_cop0(cpu_cop0), .error_any(cpu_error)
);

hng64_cpu_cdc u_cpu_cdc
(
	.c1x(c1x), .c2x(c2x), .c_rst(cpu_rst1x),
	.c_request(c_request), .c_rnw(c_rnw), .c_address(c_address), .c_req64(c_req64),
	.c_size(c_size), .c_mask(c_writeMask), .c_wdata(c_dataWrite),
	.c_dataRead(c_dataRead), .c_done(c_done),
	.c_granted2x(c_granted2x), .c_DOUT(c_DOUT), .c_DOUT_READY(c_DOUT_READY),
	.b1x(clk1x), .b2x(clk2x), .b_rst(cpu_reset),
	.b_request(mem_request), .b_rnw(mem_rnw), .b_address(mem_address), .b_req64(mem_req64),
	.b_size(mem_size), .b_mask(mem_writeMask), .b_wdata(mem_dataWrite),
	.b_dataRead(mem_dataRead), .b_done(mem_done),
	.b_granted2x(rdram_granted2x), .b_DOUT(ddr3_DOUT), .b_DOUT_READY(ddr3_DOUT_READY)
);

///////////////////////   BOARD   /////////////////////////////////

wire       ce_pix, hsync, vsync, hblank, vblank;
wire [7:0] r, g, b;
wire [5:0] dbg_fault;
wire [7:0] dbg_load;
wire [15:0] dbg_mcu_pc;
wire       dbg_mcu_fetch;
wire [31:0] dbg_irq_pending;
wire  [4:0] dbg_irq_level;
wire  [7:0] dbg_ddr_inflight;
wire [12:0] dbg_3d;
wire        dbg_3d_tri, dbg_3d_up, dbg_mcu_int0;
wire [31:0] dbg_vid;
wire [48:0] dbg_spr;
wire [185:0] dbg_tq;
wire  [59:0] dbg_sc;
wire [154:0] dbg_rc;
wire        dbg_rd, dbg_rdone;
wire  [2:0] dbg_rsel;
wire [13:0] dbg_raddr;
wire [31:0] dbg_rdata;

hng64_core u_core
(
	.clk1x(clk1x), .clk2x(clk2x), .clk3d(clk3d), .reset(reset), .sdram_init(~pll_locked),

	.mem_request(mem_request), .mem_rnw(mem_rnw), .mem_address(mem_address),
	.mem_req64(mem_req64), .mem_size(mem_size), .mem_writeMask(mem_writeMask),
	.mem_dataWrite(mem_dataWrite), .mem_dataRead(mem_dataRead), .mem_done(mem_done),
	.rdram_granted2x(rdram_granted2x), .ddr3_DOUT(ddr3_DOUT), .ddr3_DOUT_READY(ddr3_DOUT_READY),
	.cpu_irq(cpu_irq), .cpu_reset(cpu_reset),

	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
	.rtc(rtc[55:0]), .nv_rdata(nv_rdata), .nv_written(nv_written), .inputs(inputs), .flip(flip), .game_speed(status[119:117]),

	.SDRAM_A(SDRAM_A), .SDRAM_DQ(SDRAM_DQ), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE),
	.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(), .SDRAM_CKE(SDRAM_CKE),

	.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),

	.ce_pix(ce_pix), .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
	.r(r), .g(g), .b(b),
	.lamp_we(), .lamp_addr(), .lamp_data(),
	.dbg_fault(dbg_fault), .dbg_layer_off(status[86:81]),
	.dbg_load(dbg_load), .dbg_mcu_pc(dbg_mcu_pc), .dbg_mcu_fetch(dbg_mcu_fetch),
	.dbg_irq_pending(dbg_irq_pending), .dbg_irq_level(dbg_irq_level),
	.dbg_ddr_inflight(dbg_ddr_inflight), .dbg_3d(dbg_3d), .dbg_3d_tri(dbg_3d_tri), .dbg_3d_up(dbg_3d_up),
	.dbg_mcu_int0(dbg_mcu_int0), .dbg_vid(dbg_vid), .dbg_spr(dbg_spr), .dbg_tq(dbg_tq), .dbg_sc(dbg_sc), .dbg_rc(dbg_rc),
	.dbg_rd(dbg_rd), .dbg_rsel(dbg_rsel), .dbg_raddr(dbg_raddr), .dbg_rdone(dbg_rdone),
	.dbg_rdata(dbg_rdata)
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
//   [79]      0 (was HDMI rotation)             [80]     PLL locked
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
	end else begin
		if (vblank && !vb_d && ~&cnt_frames) cnt_frames <= cnt_frames + 1'd1;
	end
end
always @(posedge clk1x) begin
	if (dbg_clear)                       cnt_mcu <= 0;
	else if (dbg_mcu_fetch && ~&cnt_mcu) cnt_mcu <= cnt_mcu + 1'd1;
end

issp_probe #(.INSTANCE_ID("F"), .PROBE_W(128), .SOURCE_W(8)) u_issp_f (
	.clk(clk1x),
	.probe({cnt_irq, cpu_irq, cnt_mcu, dbg_mcu_pc, pause, cpu_reset, pll_locked, 1'b0,
	        cpu_error, dbg_fault, dbg_load, last_addr, cnt_req, cnt_frames}),
	.source(src_f)
);

// ISSP instance G: interrupts, the 3D, DDR3, and whether the CPU is waiting on the bus. Counters
// as F's (no reset, saturating, cleared by F's source bit 0). Field table: read_issp.tcl fields_G.
//
//   [31:0]    hng64_io's irq_pending           [36:32]  irq_level
//   [48:37]   interrupt 3 (the 3D FIFO) rises  [61:49]  dbg_3d: {dl_full, dl_upbusy, dl_busy,
//                                                         state[3:0], queued[5:0]} (hng64_3d)
//   [69:62]   DDR3 reads in flight             [85:70]  display-list uploads
//   [101:86]  triangles to the rasteriser      [102]    a CPU request is outstanding
//   [118:103] clk1x clocks it has waited       [127:119] INT0 pulses to the IO MCU
reg [11:0] cnt_irq3 = 0;
reg [15:0] cnt_up = 0, cnt_tri = 0, pend_cyc = 0;
reg [8:0]  cnt_int0 = 0;
reg        irq3_d = 0, mem_pend = 0, int0_d = 0;
always @(posedge clk1x) begin
	irq3_d <= dbg_irq_pending[3];
	int0_d <= dbg_mcu_int0;
	if (dbg_mcu_int0 && !int0_d && ~&cnt_int0) cnt_int0 <= cnt_int0 + 1'd1;
	if (mem_request) begin
		mem_pend <= 1'b1;
		pend_cyc <= 0;
	end else if (mem_done) begin
		mem_pend <= 1'b0;
	end else if (mem_pend && ~&pend_cyc) begin
		pend_cyc <= pend_cyc + 1'd1;
	end
	if (dbg_clear) begin
		cnt_irq3 <= 0;
		cnt_up <= 0;
	end else begin
		if (dbg_irq_pending[3] && !irq3_d && ~&cnt_irq3) cnt_irq3 <= cnt_irq3 + 1'd1;
		if (dbg_3d_up && ~&cnt_up) cnt_up <= cnt_up + 1'd1;
	end
end
always @(posedge clk2x) begin
	if (dbg_clear) cnt_tri <= 0;
	else if (dbg_3d_tri && ~&cnt_tri) cnt_tri <= cnt_tri + 1'd1;
end

issp_probe #(.INSTANCE_ID("G"), .PROBE_W(128), .SOURCE_W(1)) u_issp_g (
	.clk(clk1x),
	.probe({cnt_int0, pend_cyc, mem_pend, cnt_tri, cnt_up, dbg_ddr_inflight, dbg_3d, cnt_irq3,
	        dbg_irq_level, dbg_irq_pending}),
	.source()
);

// ISSP instance T: CPU requests as they complete, {req64, read, byte mask, data (the write's, or
// the read's as returned), address}, 4,096 of them. By default only register accesses (not main
// RAM, program ROM, BIOS, or the tilemap, sprite, palette, 3D-bank and sound memories the BIOS
// tests) and only the first 4,096 after configuration or a restart, which is the
// order MAME's system trace (scripts/mame/systrace.lua) can be compared with. Source: [11:0] the
// entry read out, [12] stop the capture, [13] keep the last 4,096 instead, [14] all requests,
// [15] restart (a rising edge). Probe: {entries recorded [15:0], the next slot [11:0], the entry
// [79:0]}; `read_issp.py T dump` reads them (read_issp.tcl). [16] widens the default to the
// memories as well (every I/O request). [17] keeps writes only, and [18] leaves out the 3D display
// list (0x20300000-0x203001ff), so a ring holds the game's recent register writes.
wire [18:0] src_t;
reg  [79:0] trace [0:4095];
reg  [79:0] trace_q;
reg  [11:0] trace_w = 0;
reg  [15:0] trace_n = 0;
reg         t_pend = 0, t_rnw, t_64, t_io, t_mem, t_rst_d = 0;
reg  [31:0] t_addr, t_wdata;
reg  [7:0]  t_mask;
wire        t_full = !src_t[13] && trace_n[12];
always @(posedge clk1x) begin
	trace_q <= trace[src_t[11:0]];
	t_rst_d <= src_t[15];
	if (mem_request) begin
		t_pend  <= 1'b1;
		t_addr  <= mem_address;
		t_rnw   <= mem_rnw;
		t_64    <= mem_req64;
		t_mask  <= mem_writeMask;
		t_wdata <= mem_dataWrite[31:0];
		t_io    <= (mem_size == 3'b001) && !(mem_address < 32'h0100_0000 ||
		           (mem_address >= 32'h0400_0000 && mem_address < 32'h0600_0000) ||
		           (mem_address >= 32'h1FC0_0000 && mem_address < 32'h1FC8_0000));
		t_mem   <= (mem_address >= 32'h2000_0000 && mem_address < 32'h2000_C000) ||
		           (mem_address >= 32'h2010_0000 && mem_address < 32'h2018_0000) ||
		           (mem_address >= 32'h2020_0000 && mem_address < 32'h2020_4000) ||
		           (mem_address >= 32'h3010_0000 && mem_address < 32'h3030_0000) ||
		           (mem_address >= 32'h6000_0000 && mem_address < 32'h6800_0000);
	end else if (mem_done && t_pend) begin
		t_pend <= 1'b0;
		if (((t_io && (!t_mem || src_t[16])) || src_t[14]) && !src_t[12] && !t_full &&
		    !(src_t[17] && t_rnw) && !(src_t[18] && t_addr[31:9] == 23'h101800)) begin
			trace[trace_w] <= {6'd0, t_64, t_rnw, t_mask, t_rnw ? mem_dataRead[31:0] : t_wdata, t_addr};
			trace_w <= trace_w + 1'd1;
			if (~&trace_n) trace_n <= trace_n + 1'd1;
		end
	end
	if (src_t[15] && !t_rst_d) begin
		trace_w <= 0;
		trace_n <= 0;
	end
end

issp_probe #(.INSTANCE_ID("T"), .PROBE_W(108), .SOURCE_W(19)) u_issp_t (
	.clk(clk1x),
	.probe({trace_n, trace_w, trace_q}),
	.source(src_t)
);

// ISSP instance P: the CPU's fetch PC, sampled; reading it a few times shows where the CPU is.
// And COP0's BadVAddr, Status, Cause and EPC (low words): after an exception the handler runs
// with EXL set, so they hold the exception's until it returns.
reg [31:0]  pc_s;
reg [127:0] cop0_s;
always @(posedge c93) begin
	pc_s   <= cpu_pc;
	cop0_s <= cpu_cop0;
end
issp_probe #(.INSTANCE_ID("P"), .PROBE_W(160), .SOURCE_W(1)) u_issp_p (
	.clk(c93),
	.probe({cop0_s, pc_s}),
	.source()
);

// ISSP instance V (clk2x): the video's scheduling and the DDR3 arbiter's requests. Field table:
// read_issp.tcl fields_V. Counters saturate and are cleared by F's source bit 0.
//   [31:0]    dbg_vid (hng64_core), sampled    [47:32]   frame_starts
//   [63:48]   line_starts                      [79:64]   late passes
//   [95:80]   late passes in the last frame    [104:96]  line_starts before its first late pass
//   the last frame's longest line pass, in clk2x clocks (a line is 3840):
//   [120:105] its length (linepass busy)       [136:121] sprites busy in it
//   [152:137] a tilemap busy                   [168:153] 3D fetch busy
//   [184:169] mixer busy                       [200:185] a video DDR3 read (0, 1, 7) not taken
//   [216:201] a 3D write offered
//   [265:217] the sprite engine, sampled (hng64_sprite dbg_q)
reg [31:0] vid_s;
reg [15:0] cnt_fs = 0, cnt_ls = 0, cnt_late = 0, late_cur = 0, late_last = 0;
reg  [8:0] ls_cur = 0, first_cur = 0, first_last = 0;
always @(posedge clk2x) begin
	vid_s <= dbg_vid;
	if (dbg_clear) begin
		cnt_fs <= 0; cnt_ls <= 0; cnt_late <= 0;
	end else begin
		if (dbg_vid[0] && ~&cnt_fs)   cnt_fs   <= cnt_fs + 1'd1;
		if (dbg_vid[1] && ~&cnt_ls)   cnt_ls   <= cnt_ls + 1'd1;
		if (dbg_vid[13] && ~&cnt_late) cnt_late <= cnt_late + 1'd1;
	end
	if (dbg_vid[0]) begin
		late_last  <= late_cur;   late_cur  <= 0;
		first_last <= first_cur;  first_cur <= 9'h1FF;
		ls_cur     <= 0;
	end else begin
		if (dbg_vid[1] && ~&ls_cur) ls_cur <= ls_cur + 1'd1;
		if (dbg_vid[13]) begin
			if (~&late_cur) late_cur <= late_cur + 1'd1;
			if (late_cur == 0) first_cur <= ls_cur;
		end
	end
end
// per pass: counted while the line pass is busy, the longest kept for the frame
reg [15:0] p_len, p_spr, p_tm, p_f3, p_mix, p_stall, p_wv;
reg [15:0] m_len, m_spr, m_tm, m_f3, m_mix, m_stall, m_wv;
reg [15:0] l_len, l_spr, l_tm, l_f3, l_mix, l_stall, l_wv;
reg        pass_q;
wire       pass_on  = vid_s[10];
wire       vstall   = |(vid_s[21:14] & ~vid_s[29:22] & 8'b1000_0011);
function [15:0] inc(input [15:0] v, input c); inc = (c && ~&v) ? v + 1'd1 : v; endfunction
always @(posedge clk2x) begin
	pass_q <= pass_on;
	if (pass_on && !pass_q) begin
		p_len <= 1; p_spr <= vid_s[9]; p_tm <= |vid_s[7:4]; p_f3 <= vid_s[8];
		p_mix <= vid_s[3]; p_stall <= vstall; p_wv <= vid_s[30];
	end else if (pass_on) begin
		p_len <= inc(p_len, 1'b1); p_spr <= inc(p_spr, vid_s[9]); p_tm <= inc(p_tm, |vid_s[7:4]);
		p_f3 <= inc(p_f3, vid_s[8]); p_mix <= inc(p_mix, vid_s[3]); p_stall <= inc(p_stall, vstall);
		p_wv <= inc(p_wv, vid_s[30]);
	end else if (pass_q && p_len > m_len) begin
		{m_len, m_spr, m_tm, m_f3, m_mix, m_stall, m_wv} <= {p_len, p_spr, p_tm, p_f3, p_mix, p_stall, p_wv};
	end
	if (vid_s[0]) begin
		{l_len, l_spr, l_tm, l_f3, l_mix, l_stall, l_wv} <= {m_len, m_spr, m_tm, m_f3, m_mix, m_stall, m_wv};
		m_len <= 0;
	end
end

reg [48:0] spr_s;
always @(posedge clk2x) spr_s <= dbg_spr;
issp_probe #(.INSTANCE_ID("V"), .PROBE_W(266), .SOURCE_W(1)) u_issp_v (
	.clk(clk2x),
	.probe({spr_s, l_wv, l_stall, l_mix, l_f3, l_tm, l_spr, l_len, first_last, late_last, cnt_late, cnt_ls, cnt_fs, vid_s}),
	.source()
);

// ISSP instance Q: the tilemap engines' stages and queues and the arbiters' reply tags
// (hng64_video dbg_tq), for a pass that never ends: which reply is owed, VRAM or tile ROM.
reg [185:0] tq_s;
always @(posedge clk2x) tq_s <= dbg_tq;
issp_probe #(.INSTANCE_ID("Q"), .PROBE_W(186), .SOURCE_W(1)) u_issp_q (
	.clk(clk2x),
	.probe(tq_s),
	.source()
);

// ISSP instance S: sprite pixels in the last frame - drawn, past the z-test, read by the mixer
reg [59:0] sc_s;
always @(posedge clk2x) sc_s <= dbg_sc;
issp_probe #(.INSTANCE_ID("S"), .PROBE_W(60), .SOURCE_W(1)) u_issp_s (
	.clk(clk2x),
	.probe(sc_s),
	.source()
);

// ISSP instance D: the DDR3 port over the last frame, latched at each vblank rise (clk2x): clocks
// with a request presented, clocks of those it waited on DDRAM_BUSY, reads and writes it took, and
// the sum of reads in flight each clock, so the mean read latency is that sum over the reads
// (Little's law). Field table: read_issp.tcl fields_D.
reg [21:0] dd_req = 0, dd_stall = 0, dd_rd = 0, dd_wr = 0, ld_req = 0, ld_stall = 0, ld_rd = 0, ld_wr = 0;
reg [31:0] dd_infl = 0, ld_infl = 0;
reg  [7:0] dd_frames = 0;
reg        dd_vb = 0;
wire       dd_any = DDRAM_RD || DDRAM_WE;
always @(posedge clk2x) begin
	dd_vb <= vblank;
	if (vblank && !dd_vb) begin
		ld_req    <= dd_req;
		ld_stall  <= dd_stall;
		ld_rd     <= dd_rd;
		ld_wr     <= dd_wr;
		ld_infl   <= dd_infl;
		dd_frames <= dd_frames + 1'd1;
		dd_req    <= 0;
		dd_stall  <= 0;
		dd_rd     <= 0;
		dd_wr     <= 0;
		dd_infl   <= 0;
	end else begin
		dd_req   <= dd_req + dd_any;
		dd_stall <= dd_stall + (dd_any && DDRAM_BUSY);
		dd_rd    <= dd_rd + (DDRAM_RD && !DDRAM_BUSY);
		dd_wr    <= dd_wr + (DDRAM_WE && !DDRAM_BUSY);
		dd_infl  <= dd_infl + dbg_ddr_inflight;
	end
end
issp_probe #(.INSTANCE_ID("D"), .PROBE_W(128), .SOURCE_W(1)) u_issp_d (
	.clk(clk2x),
	.probe({dd_frames, ld_infl, ld_wr, ld_rd, ld_stall, ld_req}),
	.source()
);

// ISSP instance E: where the 3D's time goes, over the last video frame (clk2x clocks, latched at each
// vblank rise): its sequence state (hng64_3d st, sampled across from clk3d) running the engine,
// flushing, finishing, waiting for the display to take a plane, idle with nothing queued; clocks
// with the upload queue full; and clk3d clocks over the frame (a clk3d count crossed in Gray code),
// to check the 3D's clock. Field table: read_issp.tcl fields_E.
wire [3:0] e3_st = dbg_3d[9:6];
reg [20:0] e3_runw = 0, e3_flush = 0, e3_fin = 0, e3_swap = 0, e3_idle = 0, e3_full = 0;
reg [20:0] l3_runw = 0, l3_flush = 0, l3_fin = 0, l3_swap = 0, l3_idle = 0, l3_full = 0;
reg [20:0] c3_bin = 0, c3_gray = 0;
reg [20:0] c3_s1 = 0, c3_s2 = 0, c3_at = 0, l3_c3 = 0;
reg        e3_vb = 0;
always @(posedge clk3d) begin
	c3_bin  <= c3_bin + 1'd1;
	c3_gray <= (c3_bin + 1'd1) ^ ((c3_bin + 1'd1) >> 1);
end
function [20:0] ungray21(input [20:0] g);
	integer k;
	begin
		ungray21[20] = g[20];
		for (k = 19; k >= 0; k = k - 1) ungray21[k] = ungray21[k + 1] ^ g[k];
	end
endfunction
always @(posedge clk2x) begin
	c3_s1 <= c3_gray;
	c3_s2 <= c3_s1;
	e3_vb <= vblank;
	if (vblank && !e3_vb) begin
		l3_runw <= e3_runw; l3_flush <= e3_flush; l3_fin <= e3_fin;
		l3_swap <= e3_swap; l3_idle <= e3_idle; l3_full <= e3_full;
		l3_c3   <= ungray21(c3_s2) - c3_at;
		c3_at   <= ungray21(c3_s2);
		e3_runw <= 0; e3_flush <= 0; e3_fin <= 0; e3_swap <= 0; e3_idle <= 0; e3_full <= 0;
	end else begin
		e3_runw  <= e3_runw  + (e3_st == 4'd4);
		e3_flush <= e3_flush + (e3_st == 4'd9);
		e3_fin   <= e3_fin   + (e3_st == 4'd10);
		e3_swap  <= e3_swap  + (e3_st == 4'd11);
		e3_idle  <= e3_idle  + (e3_st == 4'd6 && dbg_3d[5:0] == 6'd0);
		e3_full  <= e3_full  + dbg_3d[12];
	end
end
issp_probe #(.INSTANCE_ID("E"), .PROBE_W(147), .SOURCE_W(1)) u_issp_e (
	.clk(clk2x),
	.probe({l3_c3, l3_full, l3_idle, l3_swap, l3_fin, l3_flush, l3_runw}),
	.source()
);

// ISSP instance R: one line of the sprite engine's traffic. Source {arm toggle, line, sel, idx}:
// a toggle arms a capture of the next pass for `line`: every ROM read the port takes (address),
// every reply word, and every line-buffer write (both pixels). sel 0/1/2 with idx reads them back.
wire [19:0] src_r;
reg   [1:0] r_arm_s = 0;
reg         r_armed = 0, r_on = 0, r_seen = 0;
reg   [6:0] r_nreq = 0, r_nrep = 0;
reg   [7:0] r_npix = 0;
reg  [25:0] r_req [0:127];
reg  [63:0] r_rep [0:127];
reg  [51:0] r_pix [0:255];
reg  [63:0] r_q;
wire  [8:0] rc_line  = dbg_rc[154:146];
wire        rc_start = dbg_rc[145];
wire [31:0] rc_px    = dbg_rc[144:113];
wire [17:0] rc_x     = dbg_rc[112:95];
wire  [1:0] rc_we    = dbg_rc[94:93];
wire [63:0] rc_rep   = dbg_rc[92:29];
wire        rc_valid = dbg_rc[28], rc_ready = dbg_rc[27], rc_rd = dbg_rc[26];
wire [25:0] rc_addr  = dbg_rc[25:0];
always @(posedge clk2x) begin
	r_arm_s <= {r_arm_s[0], src_r[19]};
	if (r_arm_s[1] != r_seen) begin
		r_seen  <= r_arm_s[1];
		r_armed <= 1'b1;
	end
	if (rc_start) begin
		if (r_armed && rc_line == src_r[18:10]) begin
			r_on <= 1'b1; r_armed <= 1'b0;
			r_nreq <= 0; r_nrep <= 0; r_npix <= 0;
		end else r_on <= 1'b0;
	end else if (r_on) begin
		if (rc_rd && rc_ready && ~&r_nreq) begin r_req[r_nreq] <= rc_addr; r_nreq <= r_nreq + 1'd1; end
		if (rc_valid && ~&r_nrep)          begin r_rep[r_nrep] <= rc_rep;  r_nrep <= r_nrep + 1'd1; end
		if (|rc_we && ~&r_npix) begin
			r_pix[r_npix] <= {rc_we[1], rc_x[17:9], rc_px[31:16], rc_we[0], rc_x[8:0], rc_px[15:0]};
			r_npix <= r_npix + 1'd1;
		end
	end
	case (src_r[9:8])
		2'd0:    r_q <= {38'd0, r_req[src_r[6:0]]};
		2'd1:    r_q <= r_rep[src_r[6:0]];
		default: r_q <= {12'd0, r_pix[src_r[7:0]]};
	endcase
end
issp_probe #(.INSTANCE_ID("R"), .PROBE_W(88), .SOURCE_W(20)) u_issp_r (
	.clk(clk2x),
	.probe({r_on, r_armed, r_npix, r_nrep, r_nreq, r_q}),
	.source(src_r)
);

// ISSP instance M: the video memories as the CPU sees them (hng64_vbus v_sel: 0 sprite RAM,
// 1 sprite registers, 2 video registers, 3 palette, 4 tcram). Source {toggle, sel, addr}: a
// toggle asks for one dword; the probe's toggle follows it when the data is there.
// scripts/read_issp.tcl `M dump` reads a whole memory into debug/hw-cap.
wire [17:0] src_m;
assign dbg_rd    = src_m[17];
assign dbg_rsel  = src_m[16:14];
assign dbg_raddr = src_m[13:0];
issp_probe #(.INSTANCE_ID("M"), .PROBE_W(33), .SOURCE_W(18)) u_issp_m (
	.clk(clk1x),
	.probe({dbg_rdone, dbg_rdata}),
	.source(src_m)
);

// ISSP instance K: player 1's inputs held from JTAG (the Remote API only taps keys): the source is
// ORed into joystick_0 (J1 layout: 8 Start, 9 Coin, 11 Service, 12 Test); the probe is IN4 and IN7
// as the IO MCU reads them. read_issp.py K set N holds them, K set 0 lets go.
wire [31:0] src_k;
assign dbg_j0 = src_k;
issp_probe #(.INSTANCE_ID("K"), .PROBE_W(16), .SOURCE_W(32)) u_issp_k (
	.clk(clk1x),
	.probe({inputs[7], inputs[4]}),
	.source(src_k)
);
`else
assign dbg_j0    = 32'd0;
assign dbg_pause = 1'b0;
assign dbg_rd    = 1'b0;
assign dbg_rsel  = 3'd0;
assign dbg_raddr = 14'd0;
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

// The picture is 4:3 whatever its pixel count: the board drove a 4:3 monitor.
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
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(crop_size),
	.CROP_OFF(status[75:71]),
	.SCALE(status[68:66])
);

// cpu_error is the CPU's (c93), taken into clk1x before it leaves for sys's 50 MHz
reg cpu_err_a = 0, cpu_err_1x = 0;
always @(posedge clk1x) begin
	cpu_err_a  <= cpu_error;
	cpu_err_1x <= cpu_err_a;
end
assign LED_USER = |dbg_fault | cpu_err_1x;

endmodule
