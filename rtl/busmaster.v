////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	busmaster.v
//
// Project:	OpenArty, an entirely open SoC based upon the Arty platform
//
// Purpose:	This is the "bus interconnect", herein called the "busmaster".
//		This module connects all the devices on the Wishbone bus
//		within this project together.  It is created by hand, not
//	automatically.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015-2017, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype	none
//
`define	NO_ZIP_WBU_DELAY
`define	ZIPCPU
//
//
`define	SDCARD_ACCESS
`define	ETHERNET_ACCESS
`ifndef	VERILATOR
`define	ICAPE_ACCESS
`endif
`define	FLASH_ACCESS
`define	SDRAM_ACCESS
`define	GPS_CLOCK
`ifdef	VERILATOR
`define	GPSTB
`endif
//	UART_ACCESS and GPS_UART have both been placed within fastio
//		`define	UART_ACCESS
//		`define	GPS_UART
`define	RTC_ACCESS
`define	OLEDRGB_ACCESS
//
//
//
//
//
// Now, conditional compilation based upon what capabilities we have turned
// on
//
`ifdef	ZIPCPU
`define	ZIP_SYSTEM
`ifndef	ZIP_SYSTEM
`define	ZIP_BONES
`endif	// ZIP_SYSTEM
`endif	// ZipCPU
//
//
// SCOPE POSITION ZERO
//
`ifdef	FLASH_ACCESS
// `define	FLASH_SCOPE	// Position zero
`endif
`ifdef ZIPCPU
`ifndef	FLASH_SCOPE
`define	CPU_SCOPE	// Position zero
`endif
`endif
//
// SCOPE POSITION ONE
//
// `define	GPS_SCOPE	// Position one
// `ifdef ICAPE_ACCESS
// `define	CFG_SCOPE	// Position one
// `endif
// `define	WBU_SCOPE
//
// SCOPE POSITION TWO
//
`ifdef	SDRAM_ACCESS
// `define	SDRAM_SCOPE		// Position two
`endif
//
// SCOPE POSITION THREE
//
`ifdef	ETHERNET_ACCESS
`define	ENET_SCOPE
`endif
//
//
module	busmaster(i_clk, i_rst,
		// CNC
		i_rx_stb, i_rx_data, o_tx_stb, o_tx_data, i_tx_busy,
		// Boad I/O
		i_sw, i_btn, o_led,
		o_clr_led0, o_clr_led1, o_clr_led2, o_clr_led3,
		// PMod I/O
		i_aux_rx, o_aux_tx, i_aux_cts_n, o_aux_rts_n, i_gps_rx, o_gps_tx,
		// The Quad SPI Flash
		o_qspi_cs_n, o_qspi_sck, o_qspi_dat, i_qspi_dat, o_qspi_mod,
		//
		// The DDR3 SDRAM
		//
		// The actual wires need to be controlled from the device
		// dependent file.  In order to keep this device independent,
		// we export only the wishbone interface to the RAM.
		//
		// o_ddr_ck_p, o_ddr_ck_n, o_ddr_reset_n, o_ddr_cke,
		// o_ddr_cs_n, o_ddr_ras_n, o_ddr_cas_n, o_ddr_we_n,
		// o_ddr_ba, o_ddr_addr, o_ddr_odt, o_ddr_dm,
		// o_ddr_dqs, i_ddr_data, o_ddr_data,
		//
		// These wires allow us to push how we deal with the RAM
		// to the next level up, where they'll be use to interact
		// with a Xilinx specific core.
		o_ram_cyc, o_ram_stb, o_ram_we, o_ram_addr, o_ram_wdata, o_ram_sel,
			i_ram_ack, i_ram_stall, i_ram_rdata, i_ram_err,
			i_ram_dbg,
		// The SD Card
		o_sd_sck, o_sd_cmd, o_sd_data, i_sd_cmd, i_sd_data, i_sd_detect,
		// Ethernet control (packets) lines
		o_net_reset_n, i_net_rx_clk, i_net_col, i_net_crs, i_net_dv,
			i_net_rxd, i_net_rxerr,
		i_net_tx_clk, o_net_tx_en, o_net_txd,
		// Ethernet control (MDIO) lines
		o_mdclk, o_mdio, o_mdwe, i_mdio,
		// OLED Control interface (roughly SPI)
		o_oled_sck, o_oled_cs_n, o_oled_mosi, o_oled_dcn,
		o_oled_reset_n, o_oled_vccen, o_oled_pmoden,
		// The GPS PMod
		i_gps_pps, i_gps_3df,
		// Other GPIO wires
		i_gpio, o_gpio
		);
	parameter	ZA=28, ZIPINTS=14, RESET_ADDRESS=32'h01380000,
			NGPI = 4, NGPO = 1;
	input	wire		i_clk, i_rst;
	// The bus commander, via an external uart port
	input	wire		i_rx_stb;
	input	wire	[7:0]	i_rx_data;
	output	wire		o_tx_stb;
	output	wire	[7:0]	o_tx_data;
	input	wire		i_tx_busy;
	// I/O to/from board level devices
	input	wire	[3:0]	i_sw;	// 16 switch bus
	input	wire	[3:0]	i_btn;	// 5 Buttons
	output	wire	[3:0]	o_led;	// 16 wide LED's
	output	wire	[2:0]	o_clr_led0, o_clr_led1, o_clr_led2, o_clr_led3;
	// PMod UARTs
	input	wire		i_aux_rx, i_aux_cts_n;
	output	wire		o_aux_tx, o_aux_rts_n;
	input	wire		i_gps_rx;
	output	wire		o_gps_tx;
	// Quad-SPI flash control
	output	wire		o_qspi_cs_n, o_qspi_sck;
	output	wire	[3:0]	o_qspi_dat;
	input	wire	[3:0]	i_qspi_dat;
	output	wire	[1:0]	o_qspi_mod;
	//
	// DDR3 RAM controller
	//
	// These would be our RAM control lines.  However, these are device,
	// implementation, and architecture dependent, rather than just simply
	// logic dependent.  Therefore, this interface as it exists cannot
	// exist here.  Instead, we export a device independent wishbone to
	// the RAM rather than the RAM wires themselves.

	// output	wire	o_ddr_ck_p, o_ddr_ck_n,o_ddr_reset_n, o_ddr_cke,
	//		o_ddr_cs_n, o_ddr_ras_n, o_ddr_cas_n,o_ddr_we_n;
	// output	wire	[2:0]	o_ddr_ba;
	// output	wire	[13:0]	o_ddr_addr;
	// output	wire		o_ddr_odt;
	// output	wire	[1:0]	o_ddr_dm;
	// output	wire	[1:0]	o_ddr_dqs;
	// input	wire	[15:0]	i_ddr_data;
	// output	wire	[15:0]	o_ddr_data;
	//
	output	wire		o_ram_cyc, o_ram_stb, o_ram_we;
	output	wire	[25:0]	o_ram_addr;
	output	wire	[31:0]	o_ram_wdata;
	output	wire	[3:0]	o_ram_sel;
	input	wire		i_ram_ack, i_ram_stall;
	input	wire	[31:0]	i_ram_rdata;
	input	wire		i_ram_err;
	input	wire	[31:0]	i_ram_dbg;
	// The SD Card
	output	wire		o_sd_sck;
	output	wire		o_sd_cmd;
	output	wire	[3:0]	o_sd_data;
	input	wire		i_sd_cmd;
	input	wire	[3:0]	i_sd_data;
	input	wire		i_sd_detect;
	// Ethernet control
	output	wire		o_net_reset_n;
	input	wire		i_net_rx_clk, i_net_col, i_net_crs, i_net_dv;
	input	wire	[3:0]	i_net_rxd;
	input	wire		i_net_rxerr;
	input	wire		i_net_tx_clk;
	output	wire		o_net_tx_en;
	output	wire	[3:0]	o_net_txd;
	// Ethernet control (MDIO)
	output	wire		o_mdclk, o_mdio, o_mdwe;
	input	wire		i_mdio;
	// OLEDRGB interface
	output	wire		o_oled_sck, o_oled_cs_n, o_oled_mosi,
				o_oled_dcn, o_oled_reset_n, o_oled_vccen,
				o_oled_pmoden;
	// GPS PMod (GPS UART above)
	input	wire		i_gps_pps;
	input	wire		i_gps_3df;
	// Other GPIO wires
	input	wire	[(NGPI-1):0]	i_gpio;
	output	wire	[(NGPO-1):0]	o_gpio;

	//
	//
	// Master wishbone wires
	//
	//
	wire		wb_cyc, wb_stb, wb_we, wb_stall, wb_err, ram_err;
	wire	[31:0]		wb_data;
	wire	[(ZA-1):0]	wb_addr;
	wire	[3:0]	wb_sel;
	reg		wb_ack;
	reg	[31:0]	wb_idata;

	// Interrupts
	wire		gpio_int, oled_int, flash_int, scop_int;
	wire		enet_tx_int, enet_rx_int, sdcard_int, rtc_int, rtc_pps,
			auxrxf_int, auxtxf_int, gpsrxf_int, gpstxf_int,
			auxrx_int, auxtx_int, gpsrx_int, gpstx_int,
			sw_int, btn_int;

	//
	//
	// First BUS master source: The UART
	//
	//
	wire	[31:0]	dwb_idata;

	// Wires going to devices
	wire		wbu_cyc, wbu_stb, wbu_we;
	wire	[31:0]	wbu_addr, wbu_data;
	wire	[3:0]	wbu_sel;
	// and then coming from devices
	wire		wbu_ack, wbu_stall, wbu_err;
	wire	[31:0]	wbu_idata;
	// And then headed back home
	wire	w_bus_interrupt;
	// Oh, and the debug control for the ZIP CPU
	wire		wbu_zip_sel, zip_dbg_ack, zip_dbg_stall;
	wire	[31:0]	zip_dbg_data;
`ifdef	WBU_SCOPE
	wire	[31:0]	wbu_debug;
`endif
	wbubus	genbus(i_clk, i_rx_stb, i_rx_data,
			wbu_cyc, wbu_stb, wbu_we, wbu_addr, wbu_data,
			(wbu_zip_sel)?zip_dbg_ack:wbu_ack,
			(wbu_zip_sel)?zip_dbg_stall:wbu_stall,
				wbu_err,
				(wbu_zip_sel)?zip_dbg_data:wbu_idata,
			w_bus_interrupt,
			o_tx_stb, o_tx_data, i_tx_busy
			// , wbu_debug
			);
	assign	wbu_sel = 4'hf;

`ifdef	WBU_SCOPE
	// assign	o_dbg = (wbu_ack)&&(wbu_cyc);
	assign	wbu_debug = { wbu_cyc, wbu_stb, wbu_we, wbu_ack, wbu_stall,
				wbu_err, wbu_zip_sel,
				wbu_addr[8:0],
				wbu_data[7:0],
				wbu_idata[7:0] };
`endif

	wire	zip_cpu_int; // True if the CPU suddenly halts
`ifdef	ZIPCPU
	// Are we trying to access the ZipCPU?  Such accesses must be special,
	// because they must succeed regardless of whether or not the ZipCPU
	// is on the bus.  Hence, we trap them here.
	assign	wbu_zip_sel = (wbu_addr[27]);

	//
	//
	// Second BUS master source: The ZipCPU
	//
	//
	wire			zip_cyc, zip_stb, zip_we;
	wire	[(ZA-1):0]	zip_addr;
	wire	[31:0]		zip_data, zip_scope_data;
	wire	[3:0]		zip_sel;
	// and then coming from devices
	wire		zip_ack, zip_stall, zip_err;

`ifdef	ZIP_SYSTEM
	wire	[(ZIPINTS-1):0]	zip_interrupt_vec = {
		// Lazy(ier) interrupts
			gpstx_int, gpsrx_int,
			auxtx_int, auxrx_int,
			rtc_ppd,
		// Fast interrupts
		oled_int, w_bus_interrupt,
			gpstxf_int, gpsrxf_int,
			auxtxf_int, auxrxf_int,
			enet_tx_int, enet_rx_int, rtc_pps
		};

	zipsystem #(	.RESET_ADDRESS(RESET_ADDRESS),
			.ADDRESS_WIDTH(ZA),
			.LGICACHE(10),
			.START_HALTED(1),
			.EXTERNAL_INTERRUPTS(ZIPINTS))
		swic(i_clk, i_rst,
			// Zippys wishbone interface
			zip_cyc, zip_stb, zip_we, zip_addr, zip_data, zip_sel,
				zip_ack, zip_stall, dwb_idata, zip_err,
			zip_interrupt_vec, zip_cpu_int,
			// Debug wishbone interface
			((wbu_cyc)&&(wbu_zip_sel)),
				((wbu_stb)&&(wbu_zip_sel)),wbu_we, wbu_addr[0],
				wbu_data,
				zip_dbg_ack, zip_dbg_stall, zip_dbg_data
`ifdef	CPU_SCOPE
			, zip_scope_data
`endif
			);
`else // ZIP_SYSTEM
	wire	w_zip_cpu_int_ignored;
	zipbones #(	.RESET_ADDRESS(RESET_ADDRESS),
			.ADDRESS_WIDTH(ZA),
			.LGICACHE(10),
			.START_HALTED(1))
		swic(i_clk, i_rst,
			// Zippys wishbone interface
			zip_cyc, zip_stb, zip_we, zip_addr, zip_data, zip_sel,
				zip_ack, zip_stall, dwb_idata, zip_err,
			w_bus_interrupt, w_zip_cpu_int_ignored,
			// Debug wishbone interface
			((wbu_cyc)&&(wbu_zip_sel)),
				((wbu_stb)&&(wbu_zip_sel)),wbu_we, wbu_addr[0],
				wbu_data,
				zip_dbg_ack, zip_dbg_stall, zip_dbg_data
`ifdef	CPU_SCOPE
			, zip_scope_data
`endif
			);
	assign	zip_cpu_int = 1'b0;
`endif	// ZIP_SYSTEM v ZIP_BONES

	//
	//
	// And an arbiter to decide who gets to access the bus
	//
	//
	wire	dwb_we, dwb_stb, dwb_cyc, dwb_ack, dwb_stall, dwb_err;
	wire	[(ZA-1):0]	dwb_addr;
	wire	[31:0]		dwb_odata;
	wire	[3:0]		dwb_sel;
	wbpriarbiter #(32,ZA) wbu_zip_arbiter(i_clk,
		// The ZIP CPU Master -- Gets the priority slot
		zip_cyc, zip_stb, zip_we, zip_addr, zip_data, zip_sel,
			zip_ack, zip_stall, zip_err,
		// The UART interface Master
		(wbu_cyc)&&(!wbu_zip_sel), (wbu_stb)&&(!wbu_zip_sel), wbu_we,
			wbu_addr[(ZA-1):0], wbu_data, wbu_sel,
			wbu_ack, wbu_stall, wbu_err,
		// Common bus returns
		dwb_cyc, dwb_stb, dwb_we, dwb_addr, dwb_odata, dwb_sel,
			dwb_ack, dwb_stall, dwb_err);

	//
	//
	// And because the ZIP CPU and the Arbiter create an unacceptable
	// delay, we fail timing.  So we add in a delay cycle ...
	//
	//
	assign	wbu_idata = dwb_idata;
	busdelay #(ZA)	wbu_zip_delay(i_clk,
			dwb_cyc, dwb_stb, dwb_we, dwb_addr, dwb_odata, dwb_sel,
				dwb_ack, dwb_stall, dwb_idata, dwb_err,
			wb_cyc, wb_stb, wb_we, wb_addr, wb_data, wb_sel,
				wb_ack, wb_stall, wb_idata, wb_err);

`else	// ZIPCPU
	assign	zip_cpu_int = 1'b0; // No CPU here to halt
	assign	wbu_zip_sel = 1'b0;

	// If there's no ZipCPU, there's no need for a Zip/WB-Uart bus delay.
	// We can go directly from the WB-Uart master bus to the master bus
	// itself.
	assign	wb_cyc    = wbu_cyc;
	assign	wb_stb    = wbu_stb;
	assign	wb_we     = wbu_we;
	assign	wb_addr   = wbu_addr;
	assign	wb_data   = wbu_data;
	assign	wb_sel    = wbu_sel;
	assign	wbu_idata = wb_idata;
	assign	wbu_ack   = wb_ack;
	assign	wbu_stall = wb_stall;
	assign	wbu_err   = wb_err;

	// The CPU never halts if it doesn't exist, so set this interrupt to
	// zero.
	assign	zip_cpu_int= 1'b0;
`endif	// ZIPCPU


	//
	// Peripheral select lines.
	//
	// These lines will be true during any wishbone cycle whose address
	// line selects the given I/O peripheral.  The none_sel and many_sel
	// lines are used to detect problems, such as when no device is
	// selected or many devices are selected.  Such problems will lead to
	// bus errors (below).
	//
	wire	io_sel, scop_sel, rtc_sel, oled_sel, uart_sel, gpsu_sel,
			sdcard_sel, gps_sel, netp_sel, mio_sel, cfg_sel,
			ram_sel, flash_sel, flctl_sel, mem_sel, netb_sel,
			none_sel;

	wire	idle_n;
`ifdef	ZERO_ON_IDLE
	assign idle_n = wb_stb;
`else
	assign idle_n = 1'b1;
`endif
	wire	[4:0]	skipaddr;
	assign	skipaddr = { wb_addr[26], wb_addr[22], wb_addr[15], wb_addr[11],
				~wb_addr[8] };
	assign	ram_sel   = (idle_n)&&(skipaddr[4]);
	assign	flash_sel = (idle_n)&&(skipaddr[4:3]==2'b01);
	assign	mem_sel   = (idle_n)&&(skipaddr[4:2]==3'b001);
	assign	netb_sel  = (idle_n)&&(skipaddr[4:1]==4'b0001);
	assign	io_sel    = (idle_n)&&(~|skipaddr)&&(wb_addr[7:5]==3'b00_0);
	assign	scop_sel  = (idle_n)&&(~|skipaddr)&&(wb_addr[7:3]==5'b00_100);
	assign	rtc_sel   = (idle_n)&&(~|skipaddr)&&(wb_addr[7:2]==6'b00_1010);
	assign	oled_sel  = (idle_n)&&(~|skipaddr)&&(wb_addr[7:2]==6'b00_1011);
	assign	uart_sel  = (idle_n)&&(~|skipaddr)&&(wb_addr[7:2]==6'b00_1100);
	assign	gpsu_sel  = (idle_n)&&(~|skipaddr)&&(wb_addr[7:2]==6'b00_1101);
	assign	sdcard_sel= (idle_n)&&(~|skipaddr)&&(wb_addr[7:2]==6'b00_1110);
	//assign unused_  = (idle_n)&&(~|skipaddr)&&(wb_addr[7:2]==6'b00_1111);
	assign	gps_sel   = (idle_n)&&(~|skipaddr)&&((wb_addr[7:2]==6'b01_0000)
						    ||(wb_addr[7:3]==5'b01_001));
	assign	netp_sel  = (idle_n)&&(~|skipaddr)&&(wb_addr[7:3]==5'b01_010);
	assign	mio_sel   = (idle_n)&&(~|skipaddr)&&(wb_addr[7:5]==3'b01_1);
	assign	flctl_sel = (idle_n)&&(~|skipaddr)&&(wb_addr[7:5]==3'b10_0);
	assign	cfg_sel   = (idle_n)&&(~|skipaddr)&&(wb_addr[7:5]==3'b10_1);

	/*
	wire	skiperr;
	assign	skiperr = (idle_n)&&((|wb_addr[(ZA-1):27])
				||(~skipaddr[4])&&(|wb_addr[25:23])
				||(skipaddr[4:3]==2'b00)&&(|wb_addr[21:16])
				||(skipaddr[4:2]==3'b000)&&(|wb_addr[14:12])
				||(skipaddr[4:1]==4'b0000)&&(|wb_addr[10:9])
				||(skipaddr[4:0]==5'b00001));
	*/


	//
	// Peripheral acknowledgement lines
	//
	// These are only a touch more confusing, since the flash device will
	// ACK for both flctl_sel (the control line select), as well as the
	// flash_sel (the memory line select).  Hence we have one fewer ack
	// line.
	wire	io_ack, rtc_ack, oled_ack, uart_ack, gpsu_ack, sdcard_ack,
			gps_ack, net_ack, mio_ack, cfg_ack, 
			mem_ack, flash_ack, ram_ack;

	reg	many_ack, slow_many_ack;
	reg	slow_ack, scop_ack;
	wire	[4:0]	ack_list;
	assign	ack_list = { ram_ack, flash_ack, mem_ack, net_ack, slow_ack };
	initial	many_ack = 1'b0;
	always @(posedge i_clk)
		many_ack <= ((ack_list != 5'h10)
			&&(ack_list != 5'h8)
			&&(ack_list != 5'h4)
			&&(ack_list != 5'h2)
			&&(ack_list != 5'h1)
			&&(ack_list != 5'h0));
	wire	[9:0] slow_ack_list;
	assign slow_ack_list = { cfg_ack, mio_ack, gps_ack, uart_ack, gpsu_ack,
			sdcard_ack, rtc_ack, scop_ack, oled_ack, io_ack };
	initial	slow_many_ack = 1'b0;
	always @(posedge i_clk)
		slow_many_ack <= ((slow_ack_list != 10'h200)
			&&(slow_ack_list != 10'h100)
			&&(slow_ack_list != 10'h080)
			&&(slow_ack_list != 10'h040)
			&&(slow_ack_list != 10'h020)
			&&(slow_ack_list != 10'h010)
			&&(slow_ack_list != 10'h008)
			&&(slow_ack_list != 10'h004)
			&&(slow_ack_list != 10'h002)
			&&(slow_ack_list != 10'h001)
			&&(slow_ack_list != 10'h000));

	always @(posedge i_clk)
		wb_ack <= (wb_cyc)&&(|ack_list);
	always @(posedge i_clk)
		slow_ack <= (wb_cyc)&&(|slow_ack_list);

	//
	// Peripheral data lines
	//
	wire	[31:0]	io_data, rtc_data, oled_data, uart_data, gpsu_data,
			sdcard_data, 
			net_data, gps_data, mio_data, cfg_data,
			mem_data, flash_data, ram_data;
	reg	[31:0]	slow_data, scop_data;

	// 4 control lines, 5x32 data lines ...
	always @(posedge i_clk)
		if ((ram_ack)||(flash_ack))
			wb_idata <= (ram_ack)?ram_data:flash_data;
		else if ((mem_ack)||(net_ack))
			wb_idata <= (mem_ack)?mem_data:net_data;
		else
			wb_idata <= slow_data;

	// 9 control lines, 10x32 data lines
	always @(posedge i_clk)
		if ((cfg_ack)||(mio_ack))
			slow_data <= (cfg_ack) ? cfg_data : mio_data;
		else if ((uart_ack)||(gpsu_ack))
			slow_data <= (uart_ack)?uart_data : gpsu_data;
		else if ((sdcard_ack)||(rtc_ack))
			slow_data <= (sdcard_ack)?sdcard_data : rtc_data;
		else if ((scop_ack)|(oled_ack))
			slow_data <= (scop_ack)?scop_data:oled_data;
		else
			slow_data <= (gps_ack) ? gps_data : io_data;

	//
	// Peripheral stall lines
	//
	// As per the wishbone spec, these cannot be clocked or delayed.  They
	// *must* be done via combinatorial logic.
	//
	wire	io_stall, scop_stall, oled_stall,
			rtc_stall, sdcard_stall, uart_stall, gpsu_stall,
			net_stall, gps_stall, mio_stall, cfg_stall,
			mem_stall, flash_stall, ram_stall;
	assign	wb_stall = (wb_cyc)&&(
			((io_sel)&&(io_stall))		// Never stalls
			||((scop_sel)&&(scop_stall))	// Never stalls
			||((rtc_sel)&&(rtc_stall))	// Never stalls
			||((oled_sel)&&(oled_stall))	// Never stalls
			||((uart_sel)&&(uart_stall))	// Never stalls
			||((gpsu_sel)&&(gpsu_stall))	// Never stalls
			||((sdcard_sel)&&(sdcard_stall))// Never stalls
			||((netp_sel)&&(net_stall))	// Never stalls
			||((gps_sel)&&(gps_stall))	//(maybe? never stalls?)
			||((mio_sel)&&(mio_stall))
			||((cfg_sel)&&(cfg_stall))
			||((netb_sel)&&(net_stall))	// Never stalls
			||((mem_sel)&&(mem_stall))	// Never stalls
			||((flash_sel|flctl_sel)&&(flash_stall))
			||((ram_sel)&&(ram_stall)));


	//
	// Bus Error calculation(s)
	//

	// Selecting nothing is only an error if the strobe line is high as well
	// as the cycle line.  However, this is captured within the wb_err
	// logic itself, so we can ignore it for a line or two.
	assign	none_sel = ( //(skiperr)||
				(~|{ io_sel, scop_sel, flctl_sel, rtc_sel,
					sdcard_sel, netp_sel, gps_sel,
					oled_sel,
					mio_sel, cfg_sel, netb_sel, mem_sel,
					flash_sel,ram_sel }));
	//
	// Selecting multiple devices at once is a design flaw that should
	// never happen.  Hence, if this logic won't build, we won't include
	// it.  Still, having this logic in place has saved my tush more than
	// once.
	//
	reg	[(ZA-1):0]	sel_addr;
	always @(posedge i_clk)
		sel_addr <= wb_addr;

	reg	many_sel_a, many_sel_b, single_sel_a, single_sel_b, last_stb;
	always @(posedge i_clk)
	begin
		last_stb <= wb_stb;

		single_sel_a <= (wb_stb)&&((ram_sel)|(flash_sel)
					|(mem_sel)|(netb_sel)|(cfg_sel)
					|(uart_sel)|(gpsu_sel));
		many_sel_a <= 1'b0;
		if ((ram_sel)&&((flash_sel)||(mem_sel)||(netb_sel)||(cfg_sel)
				||(uart_sel)||(gpsu_sel)))
			many_sel_a <= 1'b1;
		else if ((flash_sel)&&((mem_sel)||(netb_sel)||(cfg_sel)
				||(uart_sel)||(gpsu_sel)))
			many_sel_a <= 1'b1;
		else if ((mem_sel)&&((netb_sel)||(cfg_sel)
				||(uart_sel)||(gpsu_sel)))
			many_sel_a <= 1'b1;
		else if ((netb_sel)&&((cfg_sel)||(uart_sel)||(gpsu_sel)))
			many_sel_a <= 1'b1;
		else if ((cfg_sel)&&((uart_sel)||(gpsu_sel)))
			many_sel_a <= 1'b1;
		else if ((uart_sel)&&(gpsu_sel))
			many_sel_a <= 1'b1;

		single_sel_b <= (wb_stb)&&((mio_sel)||(gps_sel)||(netp_sel)
					||(sdcard_sel)||(rtc_sel)||(flctl_sel)
					||(oled_sel)||(scop_sel)||(io_sel));
		many_sel_b <= 1'b0;
		if ((mio_sel)&&((gps_sel)||(netp_sel)||(sdcard_sel)||(rtc_sel)
				||(flctl_sel)||(scop_sel)||(oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((gps_sel)&&((netp_sel)||(sdcard_sel)||(rtc_sel)
				||(flctl_sel)||(scop_sel)||(oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((netp_sel)&&((sdcard_sel)||(rtc_sel)
				||(flctl_sel)||(scop_sel)||(oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((sdcard_sel)&&((rtc_sel)
				||(flctl_sel)||(scop_sel)||(oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((rtc_sel)&&((flctl_sel)||(scop_sel)||(oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((flctl_sel)&&((scop_sel)||(oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((scop_sel)&&((oled_sel)||(io_sel)))
			many_sel_b <= 1'b1;
		else if ((oled_sel)&&(io_sel))
			many_sel_b <= 1'b1;
	end

	wire	sel_err; // 5 inputs
	assign	sel_err = ( (last_stb)&&(!single_sel_a)&&(!single_sel_b))
				||((single_sel_a)&&(single_sel_b))
				||((single_sel_a)&&(many_sel_a))
				||((single_sel_b)&&(many_sel_b));
	assign	wb_err = (wb_cyc)&&(sel_err || many_ack || slow_many_ack||ram_err);


	// Finally, if we ever encounter a bus error, knowing the address of
	// the error will be important to figuring out how to fix it.  Hence,
	// we grab it here.  Be aware, however, that this might not truly be
	// the address that caused an error: in the case of none_sel it will
	// be, but if many_ack or slow_many_ack are true then we might just be
	// looking at an address on the bus that was nearby the one requested.
	reg	[(ZA-1):0]	r_bus_err_addr;
	initial	r_bus_err_addr = 0;
	always @(posedge i_clk)
		if (wb_err)
			r_bus_err_addr <= sel_addr;
	wire	[31:0]	bus_err_addr;
	assign bus_err_addr[(ZA+1):0] = { r_bus_err_addr, 2'b00 };
	generate if (ZA < 30)
		assign bus_err_addr[31:(ZA+2)] = 0;
	endgenerate

	//
	// I/O peripheral
	//
	// The I/O processor, herein called an fastio.  This is a unique
	// set of peripherals--these are all of the peripherals that can answer
	// in a single clock--or, rather, they are the peripherals that can
	// answer the bus before their clock.  Hence, the fastio simply consists
	// of a mux that selects between various peripheral responses.  Further,
	// these peripherals are not allowed to stall the bus.
	//
	// There is no option for turning these off--they will always be on.
	wire	[11:0]	master_ints;
	assign	master_ints = { zip_cpu_int,
			gpsrx_int, auxtx_int, auxrx_int,
			oled_int, rtc_int, sdcard_int,
			enet_tx_int, enet_rx_int,
			scop_int, flash_int, rtc_pps };
	wire	[2:0]	board_ints;
	wire	[3:0]	w_led;
	wire	rtc_ppd;
	fastio	#(
		.EXTRACLOCK(0), .NGPI(NGPI), .NGPO(NGPO)
		) runio(i_clk, i_sw, i_btn, 
			w_led, o_clr_led0, o_clr_led1, o_clr_led2, o_clr_led3,
			i_gpio, o_gpio,
			wb_cyc, (io_sel)&&(wb_stb), wb_we, wb_addr[4:0],
				wb_data, io_ack, io_stall, io_data,
			rtc_ppd,
			bus_err_addr, gps_now[63:32], gps_step[47:16],
			master_ints, w_bus_interrupt,
			board_ints);
	assign	{ gpio_int, sw_int, btn_int } = board_ints;

	assign	o_led = w_led;


	//
	//
	//	Real Time Clock (RTC) device level access
	//
	//
	wire	gps_tracking, ck_pps;
	wire	[63:0]	gps_step;
`ifdef	RTC_ACCESS
	rtcgps
		// #(32'h15798f)	// 2^48 / 200MHz
		// #(32'h1a6e3a)	// 2^48 / 162.5 MHz
		#(32'h34dc74)		// 2^48 /  81.25MHz
		// #(32'h35afe6)	// 2^48 /  80.0 MHz
		thertc(i_clk,
			wb_cyc, (wb_stb)&&(rtc_sel), wb_we,
				wb_addr[1:0], wb_data,
				rtc_data, rtc_int, rtc_ppd,
			gps_tracking, ck_pps, gps_step[47:16], rtc_pps);
`else
	assign	rtc_data = 32'h00;
	assign	rtc_int   = 1'b0;
	assign	rtc_pps   = 1'b0;
	assign	rtc_ppd   = 1'b0;
`endif
	reg	r_rtc_ack;
	initial	r_rtc_ack = 1'b0;
	always @(posedge i_clk)
		r_rtc_ack <= (wb_stb)&&(rtc_sel);
	assign	rtc_ack = r_rtc_ack;
	assign	rtc_stall = 1'b0;

	//
	//
	//	Auxilliary UART (console port)
	//
	//
	wbuart	#(.INITIAL_SETUP(31'd705),	// 115200 Baud, 8N1, from 81.25M
		.HARDWARE_FLOW_CONTROL_PRESENT(1'b0))
		console(i_clk, 1'b0,
		wb_cyc, (wb_stb)&&(uart_sel), wb_we, wb_addr[1:0], wb_data,
			uart_ack, uart_stall, uart_data,
		i_aux_rx, o_aux_tx, i_aux_cts_n, o_aux_rts_n,
		auxrx_int, auxtx_int, auxrxf_int, auxtxf_int);

	//
	//
	//	GPS Data UART
	//
	//
	wire	gps_rts_n_ignored;
	wbuart	#(.INITIAL_SETUP(31'd8464),	//   9600 Baud, 8N1
		.HARDWARE_FLOW_CONTROL_PRESENT(1'b0))
		gpsdata(i_clk, 1'b0,
		wb_cyc, (wb_stb)&&(gpsu_sel), wb_we, wb_addr[1:0], wb_data,
			gpsu_ack, gpsu_stall, gpsu_data,
		i_gps_rx, o_gps_tx, 1'b0, gps_rts_n_ignored,
		gpsrx_int, gpstx_int, gpsrxf_int, gpstxf_int);
			
	//
	//
	//	SDCard device level access
	//
	//
`ifdef	SDCARD_ACCESS
	wire	[31:0]	sd_dbg;
	// SPI mapping
	wire	w_sd_cs_n, w_sd_mosi, w_sd_miso;

	sdspi	sdctrl(i_clk,
			wb_cyc, (wb_stb)&&(sdcard_sel), wb_we,
				wb_addr[1:0], wb_data,
				sdcard_ack, sdcard_stall, sdcard_data,
			w_sd_cs_n, o_sd_sck, w_sd_mosi, w_sd_miso,
			sdcard_int, 1'b1, sd_dbg);
	assign	w_sd_miso = i_sd_data[0];
	assign	o_sd_data = { w_sd_cs_n, 3'b111 };
	assign	o_sd_cmd  = w_sd_mosi;
`else
	reg	r_sdcard_ack;
	always @(posedge i_clk)
		r_sdcard_ack <= (wb_stb)&&(sdcard_sel);
	assign	sdcard_ack = r_sdcard_ack;

	assign	sdcard_data = 32'h00;
	assign	sdcard_stall= 1'b0;
	assign	sdcard_int  = 1'b0;
`endif

	//
	//
	//	OLEDrgb device control
	//
	//
`ifdef	OLEDRGB_ACCESS
	wboled
		#( .CBITS(4))// Div ck by 2^4=16, words take 200ns@81.25MHz
		rgbctrl(i_clk,
			wb_cyc, (wb_stb)&&(oled_sel), wb_we,
				wb_addr[1:0], wb_data,
				oled_ack, oled_stall, oled_data,
			o_oled_sck, o_oled_cs_n, o_oled_mosi, o_oled_dcn,
			{ o_oled_reset_n, o_oled_vccen, o_oled_pmoden },
			oled_int);
`else
	assign	o_oled_cs_n    = 1'b1;
	assign	o_oled_sck     = 1'b1;
	assign	o_oled_mosi    = 1'b1;
	assign	o_oled_dcn     = 1'b1;
	assign	o_oled_reset_n = 1'b0;
	assign	o_oled_vccen   = 1'b0;
	assign	o_oled_pmoden  = 1'b0;

	reg	r_oled_ack;
	always @(posedge i_clk)
		r_oled_ack <= (wb_stb)&&(oled_sel);
	assign	oled_ack = r_oled_ack;

	assign	oled_data = 32'h00;
	assign	oled_stall= 1'b0;
	assign	oled_int  = 1'b0;
`endif

	//
	//
	//	GPS CLOCK CONTROLS, BOTH THE TEST BENCH AND THE CLOCK ITSELF
	//
	//
	wire	[63:0]	gps_now, gps_err;
	wire	[31:0]	gck_data, gtb_data;
	wire	gck_ack, gck_stall, gtb_ack, gtb_stall;
`ifdef	GPS_CLOCK
	//
	//	GPS CLOCK SCHOOL TESTING
	//
	wire	gps_pps, tb_pps, gps_locked;
	wire	[1:0]	gps_dbg_tick;

	gpsclock_tb ppscktb(i_clk, ck_pps, tb_pps,
			(wb_stb)&&(gps_sel)&&(wb_addr[3]),
				wb_we, wb_addr[2:0],
				wb_data, gtb_ack, gtb_stall, gtb_data,
			gps_err, gps_now, gps_step);
`ifdef	GPSTB
	assign	gps_pps = tb_pps; // Let the truth come from our test bench
`else
	assign	gps_pps = i_gps_pps;
`endif
	wire	gps_led;

	//
	//	GPS CLOCK CONTROL
	//
	gpsclock #(
		.DEFAULT_STEP(32'h834d_c736)
		) ppsck(i_clk, 1'b0, gps_pps, ck_pps, gps_led,
			(wb_stb)&&(gps_sel)&&(!wb_addr[3]),
				wb_we, wb_addr[1:0],
				wb_data, gck_ack, gck_stall, gck_data,
			gps_tracking, gps_now, gps_step, gps_err, gps_locked,
			gps_dbg_tick);
`else

	assign	gps_err = 64'h0;
	assign	gps_now = 64'h0;
	assign	gck_data = 32'h0;
	assign	gtb_data = 32'h0;
	assign	gtb_stall = 1'b0;
	assign	gck_stall = 1'b0;
	assign	ck_pps = 1'b0;

	assign	gps_tracking = 1'b0;
	// Appropriate step for a 200MHz clock
	assign	gps_step = { 16'h00, 32'h015798e, 16'h00 };

	reg	r_gck_ack;
	always @(posedge i_clk)
		r_gck_ack <= (wb_stb)&&(gps_sel);
	assign	gck_ack = r_gck_ack;
	assign	gtb_ack = r_gck_ack;

`endif

	assign	gps_ack   = (gck_ack | gtb_ack);
	assign	gps_stall = (gck_stall | gtb_stall);
	assign	gps_data  = (gck_ack) ? gck_data : gtb_data;


	//
	//	ETHERNET DEVICE ACCESS
	//
`ifdef	ETHERNET_ACCESS
`ifdef	ENET_SCOPE
	wire	[31:0]	txnet_data;
`endif

	enetpackets	#(12)
		netctrl(i_clk, i_rst, wb_cyc,(wb_stb)&&((netp_sel)||(netb_sel)),
			wb_we, { (netb_sel), wb_addr[10:0] }, wb_data, wb_sel,
				net_ack, net_stall, net_data,
			o_net_reset_n,
			i_net_rx_clk, i_net_col, i_net_crs, i_net_dv, i_net_rxd,
				i_net_rxerr,
			i_net_tx_clk, o_net_tx_en, o_net_txd,
			enet_rx_int, enet_tx_int
`ifdef	ENET_SCOPE
			, txnet_data
`endif
			);

	wire	[31:0]	mdio_debug;
	enetctrl #(2)
		mdio(i_clk, i_rst, wb_cyc, (wb_stb)&&(mio_sel), wb_we,
				wb_addr[4:0], wb_data[15:0],
			mio_ack, mio_stall, mio_data,
			o_mdclk, o_mdio, i_mdio, o_mdwe,
			mdio_debug);
`else
	reg	r_mio_ack;
	always @(posedge i_clk)
		r_mio_ack <= (wb_stb)&&(mio_sel);
	assign	mio_ack = r_mio_ack;

	assign	mio_data  = 32'h00;
	assign	mio_stall = 1'b0;
	assign	enet_rx_int = 1'b0;
	assign	enet_tx_int = 1'b0;

	//
	// 8kW memory, 4kW for each of transmit and receive.  (Max pkt length
	// is 512W, so this allows for two 512W in memory.)  Since we don't
	// really have ethernet without ETHERNET_ACCESS defined, this just
	// consumes resources for us so we have an idea of what might be
	// available when we do have ETHERNET_ACCESS defined.
	//
	memdev #(13) enet_buffers(i_clk, wb_cyc,
			(wb_stb)&&((netb_sel)||(netp_sel)), wb_we,
		wb_addr[10:0], wb_data, wb_sel, net_ack, net_stall, net_data);
	assign	o_mdclk = 1'b1;
	assign	o_mdio = 1'b1;
	assign	o_mdwe = 1'b1;
`endif


	//
	//	MULTIBOOT/ICAPE2 CONFIGURATION ACCESS
	//
`ifdef	ICAPE_ACCESS
	wire	[31:0]	cfg_debug;
	wbicapetwo	#(.LGDIV(1)) // Divide the clock by two
		fpga_cfg(i_clk, wb_cyc,(cfg_sel)&&(wb_stb), wb_we,
				wb_addr[4:0], wb_data,
				cfg_ack, cfg_stall, cfg_data, cfg_debug);
`else
	reg	r_cfg_ack;
	always @(posedge i_clk)
		r_cfg_ack <= (cfg_sel)&&(wb_stb);
	assign	cfg_ack   = r_cfg_ack;
	assign	cfg_stall = 1'b0;
	assign	cfg_data  = 32'h00;
`endif

	//
	//	RAM MEMORY ACCESS
	//
	// There is no option to turn this off--this RAM must always be
	// present in the design.
	memdev	#(.LGMEMSZ(17),
		.EXTRACLOCK(0)) // 32kW, or 128kB, 15 address lines
		blkram(i_clk, wb_cyc, (wb_stb)&&(mem_sel), wb_we, wb_addr[14:0],
				wb_data, wb_sel, mem_ack, mem_stall, mem_data);

	//
	//	FLASH MEMORY ACCESS
	//
`ifdef	FLASH_ACCESS
// `ifdef	FLASH_SCOPE
	wire	[31:0]	flash_debug;
// `endif
	wire	w_ignore_cmd_accepted;
	eqspiflash	flashmem(i_clk, i_rst,
		wb_cyc,(wb_stb)&&(flash_sel),(wb_stb)&&(flctl_sel),wb_we,
			wb_addr[21:0], wb_data,
		flash_ack, flash_stall, flash_data,
		o_qspi_sck, o_qspi_cs_n, o_qspi_mod, o_qspi_dat, i_qspi_dat,
		flash_int, w_ignore_cmd_accepted
// `ifdef	FLASH_SCOPE
		, flash_debug
// `endif
		);
`else
	assign	o_qspi_sck = 1'b1;
	assign	o_qspi_cs_n= 1'b1;
	assign	o_qspi_mod = 2'b01;
	assign	o_qspi_dat = 4'h0;
	assign	flash_data = 32'h00;
	assign	flash_stall  = 1'b0;
	assign	flash_int = 1'b0;

	reg	r_flash_ack;
	always @(posedge i_clk)
		r_flash_ack <= (wb_stb)&&(flash_sel);
	assign	flash_ack = r_flash_ack;
`endif


	//
	//
	//	DDR3-SDRAM
	//
	//
`ifdef	SDRAM_ACCESS
/*
	wire	[31:0]	i_ram_dbg;
	assign	i_ram_dbg = 0;
	wire	[1:0]	o_ddr_dqs;
	wbddrsdram	rami(i_clk,
		wb_cyc, (wb_stb)&&(ram_sel), wb_we, wb_addr[25:0], wb_data,
			wb_sel, ram_ack, ram_stall, ram_data,
		o_ddr_reset_n, o_ddr_cke,
		o_ddr_cs_n, o_ddr_ras_n, o_ddr_cas_n, o_ddr_we_n,
		o_ddr_dqs,
		o_ddr_addr, o_ddr_ba, o_ddr_data, i_ddr_data);
*/
	assign	o_ram_cyc	= wb_cyc;
	assign	o_ram_stb	= (wb_stb)&&(ram_sel);
	assign	o_ram_we	= wb_we;
	assign	o_ram_addr	= wb_addr[25:0];
	assign	o_ram_wdata	= wb_data;
	assign	o_ram_sel	= wb_sel;
	assign	ram_ack	= i_ram_ack;
	assign	ram_stall	= i_ram_stall;
	assign	ram_data	= i_ram_rdata;
	assign	ram_err		= i_ram_err;
	/*
	migsdram rami(i_clk, i_memref_clk_200mhz, i_rst,
		wb_cyc, (wb_stb)&&(ram_sel), wb_we, wb_addr[25:0], wb_data,
			4'hf,
		ram_ack, ram_stall, ram_data, ram_err,
		//
		o_ddr_ck_p, o_ddr_ck_n,
		o_ddr_reset_n, o_ddr_cke,
		o_ddr_cs_n, o_ddr_ras_n, o_ddr_cas_n, o_ddr_we_n,
		o_ddr_ba, o_ddr_addr,
		o_ddr_odt, o_ddr_dm,
		io_ddr_dqs_p, io_ddr_dqs_n,
		io_ddr_data,
		ram_ready
	);
	*/
`else
	assign	ram_data  = 32'h00;
	assign	ram_stall = 1'b0;
	reg	r_ram_ack;
	always @(posedge i_clk)
		r_ram_ack <= (wb_stb)&&(ram_sel);
	assign	ram_ack = r_ram_ack;

	// And idle the DDR3 SDRAM
	assign	o_ddr_reset_n = 1'b0;	// Leave the SDRAM in reset
	assign	o_ddr_cke     = 1'b0;	// Disable the SDRAM clock
	// DQS
	assign	o_ddr_dqs = 2'b11; // Leave DQS pins in high impedence
	// DDR3 control wires (not enabled if CKE=0)
	assign	o_ddr_cs_n	= 1'b0;	 // NOOP command
	assign	o_ddr_ras_n	= 1'b1;
	assign	o_ddr_cas_n	= 1'b1;
	assign	o_ddr_we_n	= 1'b1;
	// (Unused) data wires
	assign	o_ddr_addr = 14'h00;
	assign	o_ddr_ba   = 3'h0;
	assign	o_ddr_data = 16'h00;
`endif


	//
	//
	//	WISHBONE SCOPES
	//
	//
	//
	//
	wire	[31:0]	scop_a_data;
	wire	scop_a_ack, scop_a_stall, scop_a_interrupt;
`ifdef	CPU_SCOPE
	wire	[31:0]	scop_cpu_data;
	wire	scop_cpu_ack, scop_cpu_stall, scop_cpu_interrupt;
	wire	scop_cpu_trigger;
	assign	scop_cpu_trigger = (zip_scope_data[31]);
	wbscope #(	.LGMEM(5'd13),
			.DEFAULT_HOLDOFF(32))
		cpuscope(i_clk, 1'b1,(scop_cpu_trigger),zip_scope_data,
			// Wishbone interface
			i_clk, wb_cyc,
				((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b00)),
				wb_we, wb_addr[0], wb_data,
				scop_cpu_ack, scop_cpu_stall, scop_cpu_data,
			scop_cpu_interrupt);

	assign	scop_a_data = scop_cpu_data;
	assign	scop_a_ack = scop_cpu_ack;
	assign	scop_a_stall = scop_cpu_stall;
	assign	scop_a_interrupt = scop_cpu_interrupt;
`else
`ifdef	FLASH_SCOPE
	wire	[31:0]	scop_flash_data;
	wire	scop_flash_ack, scop_flash_stall, scop_flash_interrupt;
	wire	scop_flash_trigger;
	assign	scop_flash_trigger = (wb_stb)&&((flash_sel)||(flctl_sel));
	wbscope #(5'd11) flashscope(i_clk, 1'b1,
			(scop_flash_trigger), flash_debug,
		// Wishbone interface
		i_clk, wb_cyc, ((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b00)),
			wb_we, wb_addr[0], wb_data,
			scop_flash_ack, scop_flash_stall, scop_flash_data,
		scop_flash_interrupt);

	assign	scop_a_data = scop_flash_data;
	assign	scop_a_ack = scop_flash_ack;
	assign	scop_a_stall = scop_flash_stall;
	assign	scop_a_interrupt = scop_flash_interrupt;
`else
	reg	r_scop_a_ack;
	always @(posedge i_clk)
		r_scop_a_ack <= (wb_stb)&&(scop_sel)&&(wb_addr[2:1] == 2'b00);
	assign	scop_a_data = 32'h00;
	assign	scop_a_ack = r_scop_a_ack;
	assign	scop_a_stall = 1'b0;
	assign	scop_a_interrupt = 1'b0;
`endif
`endif

	wire	[31:0]	scop_b_data;
	wire	scop_b_ack, scop_b_stall, scop_b_interrupt;
`ifdef	GPS_SCOPE
	reg	[18:0]	r_gps_debug;
	wire	[31:0]	scop_gps_data;
	wire		scop_gps_ack, scop_gps_stall, scop_gps_interrupt;
	always @(posedge i_clk)
		r_gps_debug <= {
			gps_dbg_tick, gps_tracking, gps_locked,
				gpu_data[7:0],
			// (wb_cyc)&&(wb_stb)&&(io_sel),
			(wb_stb)&&(io_sel)&&(wb_addr[4:3]==2'b11)&&(wb_we),
			(wb_stb)&&(gps_sel)&&(wb_addr[3:2]==2'b01),
				gpu_int,
				i_gps_rx, rtc_pps, ck_pps, i_gps_pps };
	wbscopc	#(5'd13,19,32,1) gpsscope(i_clk, 1'b1, ck_pps, r_gps_debug,
		// Wishbone interface
		i_clk, wb_cyc, ((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b01)),
			wb_we, wb_addr[0], wb_data,
			scop_gps_ack, scop_gps_stall, scop_gps_data,
		scop_gps_interrupt);

	assign	scop_b_ack   = scop_gps_ack;
	assign	scop_b_stall = scop_gps_stall;
	assign	scop_b_data  = scop_gps_data;
	assign	scop_b_interrupt = scop_gps_interrupt;
`else
`ifdef	CFG_SCOPE
	wire	[31:0]	scop_cfg_data;
	wire		scop_cfg_ack, scop_cfg_stall, scop_cfg_interrupt;
	wire	[31:0]	cfg_debug_2;
	assign	cfg_debug_2 = {
			wb_ack, cfg_debug[30:17], slow_ack,
				slow_data[7:0], wb_data[7:0]
			};
	wbscope	#(5'd8,32,1) cfgscope(i_clk, 1'b1, (cfg_sel)&&(wb_stb),
			cfg_debug_2,
		// Wishbone interface
		i_clk, wb_cyc, ((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b01)),
			wb_we, wb_addr[0], wb_data,
			scop_cfg_ack, scop_cfg_stall, scop_cfg_data,
		scop_cfg_interrupt);

	assign	scop_b_data = scop_cfg_data;
	assign	scop_b_stall = scop_cfg_stall;
	assign	scop_b_ack = scop_cfg_ack;
	assign	scop_b_interrupt = scop_cfg_interrupt;
`else
`ifdef	WBU_SCOPE
	wire	[31:0]	scop_wbu_data;
	wire		scop_wbu_ack, scop_wbu_stall, scop_wbu_interrupt;
	wbscope	#(5'd10,32,1) wbuscope(i_clk, 1'b1, (flash_sel)&&(wb_stb),
			wbu_debug,
		// Wishbone interface
		i_clk, wb_cyc, ((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b01)),
			wb_we, wb_addr[0], wb_data,
			scop_wbu_ack, scop_wbu_stall, scop_wbu_data,
		scop_wbu_interrupt);

	assign	scop_b_data = scop_wbu_data;
	assign	scop_b_stall = scop_wbu_stall;
	assign	scop_b_ack = scop_wbu_ack;
	assign	scop_b_interrupt = scop_wbu_interrupt;
`else
	assign	scop_b_data = 32'h00;
	assign	scop_b_stall = 1'b0;
	assign	scop_b_interrupt = 1'b0;

	reg	r_scop_b_ack;
	always @(posedge i_clk)
		r_scop_b_ack <= (wb_stb)&&(scop_sel)&&(wb_addr[2:1] == 2'b01);
	assign	scop_b_ack  = r_scop_b_ack;
`endif
`endif
`endif

	//
	// SCOPE C
	//
	wire	[31:0]	scop_c_data;
	wire	scop_c_ack, scop_c_stall, scop_c_interrupt;
	//
`ifdef	SDRAM_SCOPE
	wire	[31:0]	scop_sdram_data;
	wire		scop_sdram_ack, scop_sdram_stall, scop_sdram_interrupt;
	wire		sdram_trigger;
	wire	[31:0]	sdram_debug;
	assign	sdram_trigger = (ram_sel)&&(wb_stb);
	assign	sdram_debug= i_ram_dbg;

	wbscope #(5'd9,32,1)
		ramscope(i_clk, 1'b1, sdram_trigger, sdram_debug,
			// Wishbone interface
			i_clk, wb_cyc,
				((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b10)),
				wb_we, wb_addr[0], wb_data,
			scop_sdram_ack, scop_sdram_stall, scop_sdram_data,
			scop_sdram_interrupt);

	assign	scop_c_ack       = scop_sdram_ack;
	assign	scop_c_stall     = scop_sdram_stall;
	assign	scop_c_data      = scop_sdram_data;
	assign	scop_c_interrupt = scop_sdram_interrupt;
`else
	assign	scop_c_data = 32'h00;
	assign	scop_c_stall = 1'b0;
	assign	scop_c_interrupt = 1'b0;

	reg	r_scop_c_ack;
	always @(posedge i_clk)
		r_scop_c_ack <= (wb_stb)&&(scop_sel)&&(wb_addr[2:1] == 2'b10);
	assign	scop_c_ack = r_scop_c_ack;
`endif

	//
	// SCOPE D
	//
	wire	[31:0]	scop_d_data;
	wire	scop_d_ack, scop_d_stall, scop_d_interrupt;
	//
`ifdef	ENET_SCOPE
	wire	[31:0]	scop_net_data;
	wire		scop_net_ack, scop_net_stall, scop_net_interrupt;

	/*
	wbscope	#(5'd8,32,1)
		net_scope(i_clk, 1'b1, !mdio_debug[1], mdio_debug,
		// Wishbone interface
		i_clk, wb_cyc, ((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b11)),
			wb_we, wb_addr[0], wb_data,
			scop_net_ack, scop_net_stall, scop_net_data,
		scop_net_interrupt);
	*/

	// 5'd8 is sufficient for small packets, and indeed the minimum for
	// watching any packets--as the minimum packet size is 64 bytes, or
	// 128 nibbles.
	wbscope	#(5'd9,32,0)
		net_scope(i_net_rx_clk, 1'b1, txnet_data[31], txnet_data,
		// Wishbone interface
		i_clk, wb_cyc, ((wb_stb)&&(scop_sel)&&(wb_addr[2:1]==2'b11)),
			wb_we, wb_addr[0], wb_data,
			scop_net_ack, scop_net_stall, scop_net_data,
		scop_net_interrupt);

	assign	scop_d_ack       = scop_net_ack;
	assign	scop_d_stall     = scop_net_stall;
	assign	scop_d_data      = scop_net_data;
	assign	scop_d_interrupt = scop_net_interrupt;
`else
	assign	scop_d_data = 32'h00;
	assign	scop_d_stall = 1'b0;
	assign	scop_d_interrupt = 1'b0;

	reg	r_scop_d_ack;
	always @(posedge i_clk)
		r_scop_d_ack <= (wb_stb)&&(scop_sel)&&(wb_addr[2:1] == 2'b11);
	assign	scop_d_ack = r_scop_d_ack;
`endif

	reg	all_scope_interrupts;
	always @(posedge i_clk)
		all_scope_interrupts <= (scop_a_interrupt)
				|| (scop_b_interrupt)
				|| (scop_c_interrupt)
				|| (scop_d_interrupt);
	assign	scop_int = all_scope_interrupts;

	// Scopes don't stall, so this line is more formality than anything
	// else.
	assign	scop_stall = ((wb_addr[2:1]==2'b0)?scop_a_stall
				: ((wb_addr[2:1]==2'b01)?scop_b_stall
				: ((wb_addr[2:1]==2'b10)?scop_c_stall
				: scop_d_stall))); // Will always be 1'b0;
	initial	scop_ack = 1'b0;
	always @(posedge i_clk)
		scop_ack  <= scop_a_ack | scop_b_ack | scop_c_ack | scop_d_ack;
	always @(posedge i_clk)
		if (scop_a_ack)
			scop_data <= scop_a_data;
		else if (scop_b_ack)
			scop_data <= scop_b_data;
		else if (scop_c_ack)
			scop_data <= scop_c_data;
		else // if (scop_d_ack)
			scop_data <= scop_d_data;

	// verilator lint_off UNUSED
	wire	[180:0]	unused;
	assign	unused = { none_sel, gps_rts_n_ignored, sd_dbg, gps_locked, gps_dbg_tick, gps_led, w_ignore_cmd_accepted, i_sd_cmd, i_sd_data[3:1], i_sd_detect, i_gps_pps, i_gps_3df, gpio_int, sw_int, btn_int,
		wbu_addr[31:28], 
		mdio_debug, flash_debug, i_ram_dbg, sd_dbg };
	// verilator lint_on  UNUSED
endmodule
