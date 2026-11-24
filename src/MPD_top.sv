`ifdef QUESTA
`define MPD_trenz 1
`define MPD_10G 1
`define COMPILE_TIME 32'h678E2B98
`else
`include "MpdTop_defines.v"
`include "CompileTime.v"
`endif

module MPD_top # (
`ifdef MPD_10G
	parameter nstreams = 2,
`else		 
	parameter nstreams = 3,
`endif
	parameter dhcp_en = 1,
	parameter simula = 2,	// 2 is the positional value for VHDL '0'
//	parameter simula = 3,	// 3 is the positional value for VHDL '1'

    // Global Generic Variables, all are 32 bit except the last one
    parameter GLOBAL_DATE  = 0,	// Date of last commit
    parameter GLOBAL_TIME  = 0,	// Time of last commit
    parameter GLOBAL_VER   = 0,
    parameter GLOBAL_SHA   = 0,

    parameter TOP_SHA     = 0,
    parameter TOP_VER     = 0,

    parameter CON_SHA     = 0,
    parameter CON_VER     = 0,

    parameter HOG_SHA     = 0,
    parameter HOG_VER     = 0,

    // Optional IPBus xml
    parameter XML_SHA     = 0,
    parameter XML_VER     = 0,

    // Project Specific Lists (One for each .src file in your Top/myproj/list folder)
//  parameter <MYLIB0>_VER = 0,
//  parameter <MYLIB0>_SHA = 0,
//  parameter <MYLIB1>_VER = 0,
//  parameter <MYLIB1>_SHA = 0,

    // External library specific variables (only if you have an external library)
//  parameter <MYEXTLIB>_SHA = 0,
    // Project flavour
    parameter FLAVOUR = 0	// integer
)
(
// On Board signals
`ifndef MPD_trenz
	output DBG0, output DBG1, output DBG2, output DBG3,
// DBG0 = USER_GPIO_P, DBG1 = USER_GPIO_N, DBG2 = USER_SMA_CLK_N, DBG3 = USER_SMA_CLK_P
	output [7:0] LED,
`endif

`ifdef MPD_mmp
	output CDCM6001_RSTB, output CDCM6001_PR0, output CDCM6001_PR1,
	output CDCM6001_OD0, output CDCM6001_OD1, output CDCM6001_OD2,
`endif

`ifdef MPD_trenz
	// Resources on module
// Bank 14: VCCIO = 3.3 V
output SPI_CS,
output  SPI_IO0,
input  SPI_IO1,
//inout  SPI_IO0,
//inout  SPI_IO1,
inout  SPI_IO2,
inout  SPI_IO3,
output SYS_LED1,	// RED: 1 = ON
output SYS_LED2,	// GREEN: 1 = ON
output PLL_IN4,
output CLK_EN,
input  REV2_ID,
input  REV1_ID,
input  REV0_ID,
output EN_MGT,		// Enable the MGTAVCC & MGTAVTT regulators
input  PG_MGT_1V,	// MGTAVCC OK
input  PG_MGT_1V2,	// MGTAVTT OK
inout  XIO,			// OneWire
output I2C_PLL_SCL,
inout  I2C_PLL_SDA,

//input  SYS_DIFF_CLK_P,	// B14_L12_P, SI5338-CLK0A renamed SYSCLK_P
//input  SYS_DIFF_CLK_N,	// B14_L12_N, SI5338-CLK0B renamed SYSCLK_N
input  MGT_CLK1_P,	// SI5338-CLK1A to Bank 116 (125 MHz)
input  MGT_CLK1_N,	// SI5338-CLK1B to Bank 116
input  MGT_CLK3_P,	// SI5338-CLK2A to Bank 115 (156.25 MHz)
input  MGT_CLK3_N,	// SI5338-CLK2B to Bank 115
	// JB1 (JM1 on module) - 100 pin left
//output MGT_TX7_P,	// Bank 115
//output MGT_TX7_N,
//input  MGT_RX7_P,	// Bank 115
//input  MGT_RX7_N,
//output MGT_TX6_P,	// Bank 115
//output MGT_TX5_P,	// Bank 115
//output MGT_TX6_N,
//output MGT_TX5_N,
//input  MGT_RX6_P,	// Bank 115
//input  MGT_RX6_N,
//input  MGT_RX5_P,	// Bank 115
//input  MGT_RX5_N,
// Bank 13: VCCIO = 2.5 V
inout  B13_L1_N,
inout  B13_L1_P,
inout  B13_L2_N,
inout  B13_L2_P,
input  B13_L3_N,	// ADC16n
input  B13_L3_P,	// ADC16p
input  B13_L4_N,	// ADC15n
input  B13_L4_P,	// ADC15p
input  B13_L5_N,	// ADC14n
input  B13_L5_P,	// ADC14p
input  B13_L6_N,	// ADC13n
input  B13_L6_P,	// ADC13p
input  B13_L7_N,	// ADC12n
input  B13_L7_P,	// ADC12p
input  B13_L8_N,	// ADC11n
input  B13_L8_P,	// ADC11p
input  B13_L9_N,	// ADC10n
input  B13_L9_P,	// ADC10p
input  B13_L10_N,	// ADC9n
input  B13_L10_P,	// ADC9p
input  B13_L11_N,	// LCLK_ADC2n
input  B13_L11_P,	// LCLK_ADC2p
input  B13_L12_N,	// ADCLK_ADC2n
input  B13_L12_P,	// ADCLK_ADC2p

input  B13_L13_N,	// ADCLK_ADC1n
input  B13_L13_P,	// ADCLK_ADC1p
input  B13_L14_N,	// LCLK_ADC1n
input  B13_L14_P,	// LCLK_ADC1p
input  B13_L15_N,	// ADC8n
input  B13_L15_P,	// ADC8p
input  B13_L16_N,	// ADC7n
input  B13_L16_P,	// ADC7p
input  B13_L17_N,	// ADC6n
input  B13_L17_P,	// ADC6p
input  B13_L18_N,	// ADC5n
input  B13_L18_P,	// ADC5p
input  B13_L19_N,	// ADC4n
input  B13_L19_P,	// ADC4p
input  B13_L20_N,	// ADC3n
input  B13_L20_P,	// ADC3p
input  B13_L21_N,	// ADC2n
input  B13_L21_P,	// ADC2p
input  B13_L22_N,	// ADC1n
input  B13_L22_P,	// ADC1p
inout  B13_L23_N,
inout  B13_L23_P,
inout  B13_L24_N,
inout  B13_L24_P,
// Bank 14: VCCIO = 3.3 V
input  MIO15,	// EXT_CLK
output MIO0,	// EXT_CLK_SEL
input  MIO9,	// USER_PUSH_BUTTON (active low)
inout  MIO14,
inout  MIO11,
inout  MIO10,
inout  MIO13,
//input  MIO12,	// ASYNC_RSTb

	// JB2 (JM2 on module) - 100 pin right
// Bank 15: VCCIO = 3.3 V
output B15_L5_N,	// SFP_RATESEL
output B15_L5_P,	// SFP_TX_DISABLE
input  B15_L7_N,	// IN1_TTL_FPGA
input  B15_L7_P,	// IN0_TTL_FPGA
output B15_L11_N,	// SEL_OUT0
output B15_L11_P,	// TRG_APV
output B15_L12_N,	// RESET_ADCb
output B15_L12_P,	// SEL_OUT1
output B15_L13_N,	// I2C_APV2_EN
output B15_L13_P,	// I2C_APV1_EN
inout  B15_L14_N,	// I2C_SDA
inout  B15_L14_P,	// I2C_SCL
input  B15_L20_N,	// IN0_NIM_FPGA
input  B15_L20_P,	// IN1_NIM_FPGA
output B15_L21_N,	// SCLK_ADC
output B15_L21_P,	// SDA_ADC
output B15_L23_N,	// CS_ADC1b
output B15_L23_P,	// CS_ADC2b
// Bank 12: VCCIO = 2.5 V
output B12_L1_N,	// DLY1[1]
output B12_L1_P,	// DLY1[0]
output B12_L2_N,	// DLY1[3]
output B12_L2_P,	// DLY1[2]
output B12_L3_N,	// DLY1[7]
output B12_L3_P,	// DLY1[6]
inout  B12_L4_N,
input  B12_L4_P,	// SFP_PRESENT
output B12_L5_N,	// DLY1[8]
output B12_L5_P,	// DLY1[9]
input  B12_L6_N,	// SFP_RX_LOS
input  B12_L6_P,	// SFP_TX_FAULT
output B12_L7_N,	// LED3
output B12_L7_P,	// LED2
output B12_L8_N,	// DLY1[10]
output B12_L8_P,	// DLY2[0]
output B12_L9_N,	// DLY2[2]
output B12_L9_P,	// DLY2[1]
output B12_L10_N,	// LED0
output B12_L10_P,	// LED1
output B12_L11_N,	// DLY1[5]
output B12_L11_P,	// DLY1[4]
inout  B12_L12_N,
inout  B12_L12_P,
output B12_L13_N,	// OUT1_FPGA
output B12_L13_P,	// OUT0_FPGA
inout  B12_L14_N,
inout  B12_L14_P,
output B12_L15_N,	// DLY2[10]
output B12_L15_P,	// RST_APV	// active low
output B12_L16_N,	// DLY2[7]
output B12_L16_P,	// DLY2[8]
input  B12_L17_N,	// SWITCH1
input  B12_L17_P,	// SWITCH0
input  B12_L18_N,	// SWITCH3
input  B12_L18_P,	// SWITCH2
output B12_L19_N,	// CLK_APV2b
output B12_L19_P,	// CLK_APV2
output B12_L20_N,	// CLK_ADC2b
output B12_L20_P,	// CLK_ADC2
output B12_L21_N,	// DLY2[6]
output B12_L21_P,	// DLY2[5]
output B12_L22_N,	// CLK_ADC1b
output B12_L22_P,	// CLK_ADC1
output B12_L23_N,	// DLY2[4]
output B12_L23_P,	// DLY2[3]
output B12_L24_N,	// CLK_APV1b
output B12_L24_P,	// CLK_APV1
output B12_L0,		// DLY2[9]
inout  B12_L25,

	// JB3 (JM3 on module) - 60 pin top
//output MGT_TX4_N,
//input  MGT_RX4_N,
//output MGT_TX4_P,	// Bank 115
//input  MGT_RX4_P,	// Bank 115
//output MGT_TX0_N,	// SFP_TDn renamed FIBER_TX_N
//input  MGT_RX0_N,	// SFP_RDn renamed FIBER_RX_N
//output MGT_TX0_P,	// Bank 116, SFP_TDp renamed FIBER_TX_P
//input  MGT_RX0_P,	// Bank 116, SFP_RDp renamed FIBER_RX_P
//output MGT_TX1_N,
//input  MGT_RX1_N,
//output MGT_TX1_P,	// Bank 116
//input  MGT_RX1_P,	// Bank 116
//output MGT_TX2_N,
//input  MGT_RX2_N,
//output MGT_TX2_P,	// Bank 116
//input  MGT_RX2_P,	// Bank 116
//output MGT_TX3_N,
//input  MGT_RX3_N,
//output MGT_TX3_P,	// Bank 116
//input  MGT_RX3_P,	// Bank 116
//input  MGT_CLK0_N,	// CK125n renamed FIBER_CLK_N
//input  MGT_CLK2_N,
//input  MGT_CLK0_P,	// CK125p renamed FIBER_CLK_P, to Bank 116
//input  MGT_CLK2_P,	// to Bank 115
// Bank 16: VCCIO = 2.5 V
input  B16_L11_N,	// XX1_DLYn
input  B16_L11_P,	// XX1_DLYp
inout  B16_L12_N,
inout  B16_L12_P,
inout  B16_L13_N,
inout  B16_L13_P,
output B16_L14_N,	// XX1n
output B16_L14_P,	// XX1p
inout  B16_L17_N,
inout  B16_L17_P,
inout  B16_L18_N,
inout  B16_L18_P,
input  B16_L21_N,	// XX2_DLYn
input  B16_L21_P,	// XX2_DLYp
output B16_L23_N,	// XX2n
output B16_L23_P,	// XX2p
// Bank 14: VCCIO = 3.3 V
inout  B14_L4_N,
inout  B14_L4_P,
inout  B14_L13_N,
input  B14_L13_P,	// CK40
`endif

// Common signals
	input SYSCLK_P,	// B14_L12_P, SI5338-CLK0A
	input SYSCLK_N,	// 100 MHZ on Trenz (not used), 200 MHz on other modules

//A.C. if MPD_ucf is defined, then this module is not the top, but it is wrapped. 
//  Fiber I/O is not here, but in top module. 
`ifndef MPD_ucf
    input FIBER_CLK_P, input FIBER_CLK_N,
	input FIBER_RX_P, input FIBER_RX_N,
	output FIBER_TX_P, output FIBER_TX_N,
// Instead, in the port there are
// 4502 TCP signals (RX/TX)
// MAC output
`else
    input [0:nstreams-1] [7:0] TCP_RX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
//	output [NTCPSTREAMS-1:0] [7:0] TCP_RX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
	input [nstreams-1:0] TCP_RX_DATA_VALID,
	input [nstreams-1:0] TCP_RX_RTS,
	output [nstreams-1:0] TCP_RX_CTS,
	output [0:nstreams-1][7:0] TCP_TX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
//	input [NTCPSTREAMS-1:0][7:0] TCP_TX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
	output [nstreams-1:0] TCP_TX_DATA_VALID,
	input [nstreams-1:0] TCP_TX_CTS,
	input [nstreams-1:0] TCP_CONNECTED,
	output [47:0] MAC_ADDR,
	//5402 clock and reset
	input GCLK_125_REF,
	input GCLK_125_REF_RST,
	//Event builder clock, enable, empty, and data
	output EVB_CLOCK_OUT,
	output EVB_ENABLE_OUT,
	output EVB_EMPTY_OUT,
	output [31:0] EVB_DATA_OUT,
	input TRIG_IN_UCF,
	input SYNC_IN_UCF,
`endif
	input ASYNC_RSTb	// active low
);

// Xilinx manufacturer MAC address:
//	48'h00_0A_35_xx_xx_xx
//	48'h00_5D_03_xx_xx_xx
parameter static_macaddr = 48'h00_0A_35_02_8C_BB;	// KC705 INFN-GE registered MAC address

// Work INFN-Genova
parameter ipaddr = 32'hC1_CE_90_F3;	// 193.206.144.243 (INFN-GE assigned address)
parameter smask = 32'hFF_FF_FC_00;	// 255.255.252.0 (INFN-GE subnet mask)
parameter gwaddr = 32'hC1_CE_90_01;	// 193.206.144.1 (INFN-GE gateway)

// Home Chiavari
//parameter ipaddr = 32'hC0_A8_01_F3;	// 192.168.1.243 (Home assigned address)
//parameter smask = 32'hFF_FF_FF_00;	// 255.255.255.0 (Home subnet mask)
//parameter gwaddr = 32'hC0_A8_01_01;	// 192.168.1.1 (Home gateway)


// Internal signals
wire clk312, clk200, clk125, clk100, clk40, clk8, clk05, clk156, tcp_clk, bus_clk, apv_clk;
wire pcs_block_lock, qpll_lock, reset_counter_done, pma_txreset_done, pma_rxreset_done;
wire gttxreset_out, gtrxreset_out, txuserrdy_out;
wire mac_frame_present, mac_frame_present_s;
wire main_resetB, spi_reset, pma_reset, stack_reset, main_pll_locked, pma_mmcm_locked, pma_reset_done;
wire [15:0] temperature, vccint, vccaux, vccbram;
wire [15:0] temperature_bus_clk, vccint_bus_clk, vccaux_bus_clk_bus_clk, vccbram_bus_clk;
reg [7:0] stack_reset_cnt;
reg stack_block_reset;
wire end_of_startup, stack_reset_clk156;
wire si5338_done, si5338_error;
wire [15:0] fiber_err_cnt;
`ifdef MPD_10G
reg bus_reset;
wire [0:nstreams-1] [63:0] tcp_rx_d, tcp_tx_d;	// VHDL array of std_logic_vector
wire [nstreams-1:0] [7:0] tcp_rx_dv, tcp_tx_dv;
`else
wire bus_reset;
wire [0:nstreams-1] [7:0] tcp_rx_d, tcp_tx_d;	// VHDL array of std_logic_vector
wire [nstreams-1:0] tcp_rx_dv, tcp_tx_dv;
`endif
wire [nstreams-1:0] tcp_rx_rts, tcp_rx_cts, tcp_tx_cts, tcp_connected;
wire [nstreams-1:0] bus_we, bus_re;
wire [3:0] bus_am0, bus_am1, bus_am2;
wire [31:0] bus_addr0, bus_addr1, bus_addr2, bus_dw0, bus_dw1, bus_dw2;
`ifdef QUESTA
wire [31:0] bus_dr1, bus_dr2;	// These should be pull-upped 3-state buses
`endif
reg [31:0] bus_dr0;	// These should be pull-upped 3-state buses
wire [31:0] TestRegister;
wire sel0, sel1_0, sel1_1, sel2, tcp_error0, tcp_error1, tcp_error2;
wire sel_regbank, sel_adc_config, sel_i2c;
wire [1:0] sel_histo, sel_histo_reg, user_in;
wire sda_oeB, scl_oeB;
wire psincdec, psen1, psen2, psdone1, psdone2, locked1, locked2, reset_pll1, reset_pll2, adc_ps_done;
wire [7:0] adc_phase;
wire user_soft_reset, user_soft_reset_ck40, i2c_ApvReset;
wire [11:0] padc0, padc1, padc2, padc3, padc4, padc5, padc6, padc7;
wire [11:0] padc8, padc9, padc10, padc11, padc12, padc13, padc14, padc15;
wire [11:0] padcx0, padcx1, padcx2, padcx3, padcx4, padcx5, padcx6, padcx7;
wire [11:0] padcx8, padcx9, padcx10, padcx11, padcx12, padcx13, padcx14, padcx15;
wire [31:0] IoConfig, ReadoutConfig, TrigGenConfig;
wire [31:0] TrigGenConfig_ck40, IoConfig_ck40;
wire [2:0] TrigMode, ReadoutMode;
wire [7:0] ApvSyncPeriod, ResetLatency, CalibLatency, TriggerDelay, TriggerDelay_ck40;
wire [11:0] one_threshold, zero_threshold, common_offset;
wire FIR_enable, sel_time_clk, disable_evb_deadlock, Enable_Slave_Terminate;
wire Pack24BitData, Data64Bit, UseSdramFifo;
wire en_baseline_subtraction, Enable_EventBuilder, AllFifoClear, DirectReadoutEnabled, Fiber_data_re;
wire [3:0] MaxTrigOut, HwRev, PwrStat;
wire TrigTestMode, sw_apv_trig, sw_apv_reset;
wire EnTrig1P0, EnTrig2P0, EnTrigFront, EnSyncP0, EnSyncFront;
wire [7:0] MarkerCh, EventPerBlock, SamplePerEvent;
wire [7:0] MarkerCh_ck40, EventPerBlock_ck125, SamplePerEvent_sync;
reg module_access, module_select;

wire [31:0] BusyThreshold, BusyThresholdLocal;
wire [15:0] ApvEnable;
wire [15:0] fir_coeff0, fir_coeff1, fir_coeff2, fir_coeff3;
wire [15:0] fir_coeff4, fir_coeff5, fir_coeff6, fir_coeff7;
wire [15:0] fir_coeff8, fir_coeff9, fir_coeff10, fir_coeff11;
wire [15:0] fir_coeff12, fir_coeff13, fir_coeff14, fir_coeff15;
wire ch_en, ped_ram_en, thr_ram_en, obuf_en, obuf_status_en;
wire [31:0] ipv4_out, ipv4_out_bus_clk;

wire incoming_trigger, apv_trigger_pulse, sync, internal_trigger_disabled, apv_reset101;
wire [31:0] apv_trigger_count, incoming_trigger_count;
wire [31:0] apv_trigger_count_s, incoming_trigger_count_s;
wire no_more_space;
wire [15:0] ApvSynced, ApvFifoEmpty, ApvFifoFull, ApvFifo_read, ApvFifoRd_EVB,
		OneMoreEvent, ApvEndFrame, ApvFrameGate, ApvFifoFullLatched, ProcFifoFullLatched;
wire [25:0] ApvFifoData0, ApvFifoData1, ApvFifoData2, ApvFifoData3,
		ApvFifoData4, ApvFifoData5, ApvFifoData6, ApvFifoData7,
		ApvFifoData8, ApvFifoData9, ApvFifoData10, ApvFifoData11,
		ApvFifoData12, ApvFifoData13, ApvFifoData14, ApvFifoData15;
wire [25:0] EvbData0, EvbData1, EvbData2, EvbData3, EvbData4, EvbData5, EvbData6, EvbData7,
		EvbData8, EvbData9, EvbData10, EvbData11, EvbData12, EvbData13, EvbData14, EvbData15;
wire [7:0] missing_trigger_count, missing_trigger_count_s; 

	wire [15:0] DecrEventCounter;
	wire [11:0] used_fifo_words0, used_fifo_words1, used_fifo_words2, used_fifo_words3,
		used_fifo_words4, used_fifo_words5, used_fifo_words6, used_fifo_words7,
		used_fifo_words8, used_fifo_words9, used_fifo_words10, used_fifo_words11,
		used_fifo_words12, used_fifo_words13, used_fifo_words14, used_fifo_words15;

	wire [15:0] we_ped_ram, re_ped_ram, we_thr_ram, re_thr_ram;
	wire EventBuilder_Read, TcpEventBuilder_Read, dummy_empty, dummy_enable, dummy_rd;
	wire [31:0] EvBuilderDataOut, dummy_data;
	wire EventBuilder_Empty, EventBuilder_Full;
	wire [12:0] EventBuilder_Wc;
	wire [23:0] EventBuilder_EvCnt;


	wire Output_Fifo_Empty, Output_Fifo_Full;
	wire [12:0] Output_Fifo_Wc;

	wire trigger_time_fifo_rd, trigger_time_fifo_rd_evb, trigger_time_fifo_full, trigger_time_fifo_empty, tdc_select;
	wire [7:0] trigger_time_fifo_data, EventBuilder_BlockCnt, Obuf_BlockCnt;

	wire pll_clock_switch0, pll_clock_switch1;
	wire FifoLevel1, FifoLevel2, EvbFifoAlmostFull;
	wire [1:0] Vme_histo_reg, Fiber_histo_reg, histo_reg;

	wire EvbFifoFullLatched, EventFifoFullLatched, TimeFifoFullLatched,OutputFifoFullLatched;


	wire OutputFifoBlockWordCount_Rd, OutputFifoBlockWordCount_Empty, OutputFifoBlockWordCount_Full;
	wire [19:0] OutputFifoBlockWordCount_Q;

// The following signals will go on dedicated pins
wire CLK_ADC1, CLK_ADC2, ADC_CS1b, ADC_CS2b, ADC_SCLK, ADC_SDA;	// OUT
wire I2C_SDA, I2C_SCL;	// INOUT
wire APV_CLOCK1, APV_CLOCK2, APV_TRIGGER;	// OUT
reg AllClear, RST_APV, BUSY_OUT;	// OUT
wire ADC0, ADC1, ADC2, ADC3, ADC4, ADC5, ADC6, ADC7;	// IN
wire ADC8, ADC9, ADC10, ADC11, ADC12, ADC13, ADC14, ADC15;	// IN
wire LCLK_ADC1, ADCLK_ADC1, LCLK_ADC2, ADCLK_ADC2;	// IN
wire [1:0] USER_IN_TTL, USER_IN_NIM;	// IN
wire [1:0] USER_OUT, SEL_OUT;	// OUT
wire USER_PUSH_BUTTON, EXT_CLK, CK40, TRIG1_IN, TRIG2_IN, SYNC_IN;	// IN
wire [3:0] LED;	// OUT
wire [3:0] SWITCH;	// IN
wire I2C_APV1_EN, I2C_APV2_EN, RESET_ADCb, SFP_RATESEL, SFP_TX_DISABLE, EXT_CLK_SEL;	// OUT
wire SFP_RX_LOS, SFP_TX_FAULT, SFP_PRESENT, XX1_DLY, XX2_DLY;	// IN
wire XX1, XX2;	// OUT
wire [10:0] DLY1, DLY2;	// OUT
wire LCLK_ADC1_bufr, LCLK_ADC2_bufr, CK40_bufg;
wire read_flash_id, read_flash_id_clk8, done_spi_rd, mac_gen_start;
wire [127:0] flash_id;
(* mark_debug = "true" *) wire [31:0] rdata_regbank, rdata_adc_config, rdata_i2c, rdata_histo0, rdata_histo1, rdata_ch;
wire [47:0] generated_mac_address;
wire [4:0] module_id;
wire AllClear_clk156;

wire [7:0] missed_event_cnt0, missed_event_cnt1, missed_event_cnt2, missed_event_cnt3;
wire [7:0] missed_event_cnt4, missed_event_cnt5, missed_event_cnt6, missed_event_cnt7;
wire [7:0] missed_event_cnt8, missed_event_cnt9, missed_event_cnt10, missed_event_cnt11;
wire [7:0] missed_event_cnt12, missed_event_cnt13, missed_event_cnt14, missed_event_cnt15;
wire [7:0] writefull_cnt0, writefull_cnt1, writefull_cnt2, writefull_cnt3;
wire [7:0] writefull_cnt4, writefull_cnt5, writefull_cnt6, writefull_cnt7;
wire [7:0] writefull_cnt8, writefull_cnt9, writefull_cnt10, writefull_cnt11;
wire [7:0] writefull_cnt12, writefull_cnt13, writefull_cnt14, writefull_cnt15;
wire [15:0] WAITING_ON_APV_MASK;
wire [7:0] SyncCounter;
wire [7:0] pcs_core_status;

wire synth_run_enable;
wire [31:0] synth_event_count, synth_trig_count, synth_missed_trig_count;
wire [31:0] synth_beat_count, synth_word_count, synth_checksum_count;
wire [63:0] synth_tx_data, tcp_tx_d_evb;
wire [7:0] synth_tx_dv, tcp_tx_dv_evb;


    function [7:0] count1;
        input [15:0] apv_mask;
        reg   [7:0] x;
        int i;
        begin
			x = 8'b0;
			for(i=0; i<16; i=i+1)
				if( apv_mask[i] == 1'b1 )
					x = x + 1;
            count1 = x;
        end
    endfunction



assign module_id = SWITCH[2] ? static_macaddr[4:0] : generated_mac_address[4:0];

`ifdef MPD_mmp
//# To have 125 MHz: PR[1:0] = 2'b11; OD[2:0] = 3'b011
	assign CDCM6001_RSTB = 1'b1;
    assign CDCM6001_PR1 = 1'b1;
    assign CDCM6001_PR0 = 1'b1;
    assign CDCM6001_OD2 = 1'b0;
    assign CDCM6001_OD1 = 1'b1;
	assign CDCM6001_OD0 = 1'b1;
`endif

`ifdef MPD_trenz
assign HwRev = {SFP_PRESENT, REV2_ID, REV1_ID, REV0_ID};
assign PwrStat = {SFP_TX_FAULT, SFP_RX_LOS, PG_MGT_1V2, PG_MGT_1V};
//assign HwRev = {1'b0, REV2_ID, REV1_ID, REV0_ID};
//assign PwrStat = {S2'b00, PG_MGT_1V2, PG_MGT_1V};
assign USER_PUSH_BUTTON = MIO9;	// active low
assign EXT_CLK = MIO15;
assign CK40 = B14_L13_P;
assign USER_IN_TTL[0] = B15_L7_P;
assign USER_IN_TTL[1] = B15_L7_N;
assign USER_IN_NIM[0] = B15_L20_N;
assign USER_IN_NIM[1] = B15_L20_P;
assign SFP_RX_LOS = B12_L6_N;
assign SFP_TX_FAULT = B12_L6_P; 
assign SFP_PRESENT = B12_L4_P; 
assign SWITCH = {B12_L18_N,B12_L18_P,B12_L17_N,B12_L17_P};
assign {B12_L7_N,B12_L7_P,B12_L10_P,B12_L10_N} = LED;
assign B15_L11_P = APV_TRIGGER;
assign B15_L13_P = I2C_APV1_EN;
assign B15_L13_N = I2C_APV2_EN;
assign B15_L11_N = SEL_OUT[0];
assign B15_L12_P = SEL_OUT[1];
//assign B15_L14_P = I2C_SCL;
//assign B15_L14_N = I2C_SDA;
assign I2C_SCL = B15_L14_P;	// in
assign I2C_SDA = B15_L14_N;	// in
assign B12_L15_P = RST_APV;
assign B12_L13_P = USER_OUT[0];
assign B12_L13_N = USER_OUT[1];
assign B15_L21_P = ADC_SDA;
assign B15_L21_N = ADC_SCLK;
assign B15_L23_N = ADC_CS1b;
assign B15_L23_P = ADC_CS2b;
assign B15_L12_N = RESET_ADCb;
assign B15_L5_N = SFP_RATESEL;
assign B15_L5_P = SFP_TX_DISABLE;
assign MIO0 = EXT_CLK_SEL;

assign DLY1 = {B12_L8_N,B12_L5_P,B12_L5_N,B12_L3_N,B12_L3_P,
	B12_L11_N,B12_L11_P,B12_L2_N,B12_L2_P,B12_L1_N,B12_L1_P};
assign DLY2 = {B12_L15_N,B12_L0,B12_L16_P,B12_L16_N,B12_L21_N,
	B12_L21_P,B12_L23_N,B12_L23_P,B12_L9_N,B12_L9_P,B12_L8_P};

// From now on we can use more easy signal names
`ifndef MPD_10G
assign CLK_EN = 1'b0;	// Local Trenz module 25 MHz oscillator and Si5338A not used for 1G
assign I2C_PLL_SCL = 1'b1;
assign I2C_PLL_SDA = 1'b1;
assign si5338_done = 1'b1;
`else
assign CLK_EN = 1'b1;	// Local Trenz module 25 MHz oscillator and Si5338A used for 10G
`endif
assign EN_MGT = 1'b1;	// Enable GTX transceivers power supplies
assign PLL_IN4 = 1'b0;	// Si5338A I2C address = 7'b1110000
assign SYS_LED1 = locked1 & locked2;

CDC_Sync1 frame_present_sync(.CK(clk156), .IN(mac_frame_present), .OUT(mac_frame_present_s));

OneShot TurnOnSysLed2(.OUT(SYS_LED2), .START(mac_frame_present_s), .CK(clk05), .RSTb(main_resetB));

BUFG BUFG_CK40 (.O(CK40_bufg), .I(CK40));

// Differential I/O buffers
IBUFGDS IBUFGDS_SYS_DIFF_CLK (.O(clk100), .I(SYSCLK_P), .IB(SYSCLK_N));	// 100 MHz, default
IBUFDS IBUFDS_ADC1 (.O(ADC0), .I(B13_L22_P), .IB(B13_L22_N));
IBUFDS IBUFDS_ADC2 (.O(ADC1), .I(B13_L21_P), .IB(B13_L21_N));
IBUFDS IBUFDS_ADC3 (.O(ADC2), .I(B13_L20_P), .IB(B13_L20_N));
IBUFDS IBUFDS_ADC4 (.O(ADC3), .I(B13_L19_P), .IB(B13_L19_N));
IBUFDS IBUFDS_ADC5 (.O(ADC4), .I(B13_L18_P), .IB(B13_L18_N));
IBUFDS IBUFDS_ADC6 (.O(ADC5), .I(B13_L17_P), .IB(B13_L17_N));
IBUFDS IBUFDS_ADC7 (.O(ADC6), .I(B13_L16_P), .IB(B13_L16_N));
IBUFDS IBUFDS_ADC8 (.O(ADC7), .I(B13_L15_P), .IB(B13_L15_N));
IBUFDS IBUFDS_ADC9 (.O(ADC8), .I(B13_L10_P), .IB(B13_L10_N));
IBUFDS IBUFDS_ADC10 (.O(ADC9), .I(B13_L9_P), .IB(B13_L9_N));
IBUFDS IBUFDS_ADC11 (.O(ADC10), .I(B13_L8_P), .IB(B13_L8_N));
IBUFDS IBUFDS_ADC12 (.O(ADC11), .I(B13_L7_P), .IB(B13_L7_N));
IBUFDS IBUFDS_ADC13 (.O(ADC12), .I(B13_L6_P), .IB(B13_L6_N));
IBUFDS IBUFDS_ADC14 (.O(ADC13), .I(B13_L5_P), .IB(B13_L5_N));
IBUFDS IBUFDS_ADC15 (.O(ADC14), .I(B13_L4_P), .IB(B13_L4_N));
IBUFDS IBUFDS_ADC16 (.O(ADC15), .I(B13_L3_P), .IB(B13_L3_N));
IBUFDS IBUFDS_LCLK_ADC1 (.O(LCLK_ADC1), .I(B13_L14_P), .IB(B13_L14_N));
IBUFDS IBUFDS_ADCLK_ADC1 (.O(ADCLK_ADC1), .I(B13_L13_P), .IB(B13_L13_N));
IBUFDS IBUFDS_LCLK_ADC2 (.O(LCLK_ADC2), .I(B13_L11_P), .IB(B13_L11_N));
IBUFDS IBUFDS_ADCLK_ADC2 (.O(ADCLK_ADC2), .I(B13_L12_P), .IB(B13_L12_N));
BUFR BUFR_LCLK_ADC1 (
      .O(LCLK_ADC1_bufr),     // 1-bit output: Clock output port
      .CE(1'b1),   // 1-bit input: Active high, clock enable (Divided modes only)
      .CLR(1'b0), // 1-bit input: Active high, asynchronous clear (Divided modes only)
      .I(LCLK_ADC1)      // 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
   );
BUFR BUFR_LCLK_ADC2 (
      .O(LCLK_ADC2_bufr),     // 1-bit output: Clock output port
      .CE(1'b1),   // 1-bit input: Active high, clock enable (Divided modes only)
      .CLR(1'b0), // 1-bit input: Active high, asynchronous clear (Divided modes only)
      .I(LCLK_ADC2)      // 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
   );

IBUFDS IBUFDS_XX1 (.O(XX1_DLY), .I(B16_L11_P), .IB(B16_L11_N));	// XX1_DLY is a delayed copy of XX1
IBUFDS IBUFDS_XX2 (.O(XX2_DLY), .I(B16_L21_P), .IB(B16_L21_N));	// XX2_DLY is a delayed copy of XX2
OBUFDS OBUFDS_XX1 (.I(XX1), .O(B16_L14_P), .OB(B16_L14_N));		// XX1 delay is set by DLY1[10:0]
OBUFDS OBUFDS_XX2 (.I(XX2), .O(B16_L23_P), .OB(B16_L23_N));		// XX2 delay is set by DLY2[10:0]

OBUFDS OBUFDS_CLK_ADC1 (.I(CLK_ADC1), .O(B12_L22_P), .OB(B12_L22_N));
OBUFDS OBUFDS_CLK_ADC2 (.I(CLK_ADC2), .O(B12_L20_P), .OB(B12_L20_N));
OBUFDS OBUFDS_CLK_APV1 (.I(APV_CLOCK1), .O(B12_L24_P), .OB(B12_L24_N));
OBUFDS OBUFDS_CLK_APV2 (.I(APV_CLOCK2), .O(B12_L19_P), .OB(B12_L19_N));

// End of differential I/O buffers
`endif

`ifndef MPD_trenz
assign HwRev = 4'b0000;
assign PwrStat = 4'b0000;
//assign LED = TestRegister[7:0];
assign DBG0 = clk40;
assign DBG1 = CLK_ADC1;
assign DBG2 = CLK_ADC2;
assign DBG3 = adc_ps_done;
`else
//assign LED = TestRegister[3:0];
`endif

assign RESET_ADCb = main_resetB;
assign SFP_RATESEL = 1'b1;
`ifndef MPD_10G
assign SFP_TX_DISABLE = 1'b0;
`endif
assign EXT_CLK_SEL = SWITCH[1];	// 0 = closed = NIM, 1 = open = LVTTL

`ifdef QUESTA
assign sel1_0 = (bus_addr1[3:0] == 4'h0) ? 1 : 0;
assign sel1_1 = (bus_addr1[3:0] == 4'h1) ? 1 : 0;
assign sel2 = (bus_addr2[3:0] == 4'h5) ? 1 : 0;

assign (weak0, weak1) bus_dr1 = bus_dr1;	// 3-state Bus Keeper
assign (weak0, weak1) bus_dr2 = bus_dr2;
`endif

//assign I2C_SCL = (scl_oeB == 0) ? 0 : 1'bz;
//assign I2C_SDA = (sda_oeB == 0) ? 0 : 1'bz;
assign B15_L14_P = (scl_oeB == 0) ? 0 : 1'bz;	// I2C_SCL out
assign B15_L14_N = (sda_oeB == 0) ? 0 : 1'bz;	// I2C_SDA out

assign apv_clk = clk40;
assign APV_CLOCK1 = apv_clk;
assign APV_CLOCK2 = apv_clk;
assign user_in[0] = ~IoConfig_ck40[0] ? USER_IN_TTL[0] : ~USER_IN_NIM[0];	// 1: NIM, 0: LVTTL default
assign user_in[1] = ~IoConfig_ck40[1] ? USER_IN_TTL[1] : ~USER_IN_NIM[1];	// 1: NIM, 0: LVTTL default

assign SEL_OUT[0] = IoConfig_ck40[2];	// 1: NIM, 0: LVTTL default
assign SEL_OUT[1] = IoConfig_ck40[3];	// 1: NIM, 0: LVTTL default
//assign USER_OUT[0] = SEL_OUT[0] ? ~BUSY_OUT : BUSY_OUT;	// BUSY signal
//assign USER_OUT[1] = SEL_OUT[1] ? ~apv_clk : apv_clk;
assign USER_OUT[0] = pcs_block_lock;
assign USER_OUT[1] = pma_reset_done;

assign pcs_block_lock = pcs_core_status[0];

assign ReadoutMode = ReadoutConfig[2:0];
//						DisableMode              = (DAQ_MODE == 3'b000);
//						ApvReadoutMode_Simple    = (DAQ_MODE == 3'b001);
//						SampleMode               = (DAQ_MODE == 3'b010);
//						ApvReadoutMode_Processed = (DAQ_MODE == 3'b011);
assign DirectReadoutEnabled = ReadoutConfig[3];
assign FIR_enable = ReadoutConfig[4];
assign sel_time_clk = ReadoutConfig[5];		// Not Used
assign disable_evb_deadlock = ReadoutConfig[6];
assign synth_run_enable = ReadoutConfig[7];
assign Enable_Slave_Terminate = ReadoutConfig[8];	// Not Used
assign I2C_APV1_EN = ReadoutConfig[9];
assign I2C_APV2_EN = ReadoutConfig[10];
assign Pack24BitData = ReadoutConfig[13];	// Not Used
assign Data64Bit = ReadoutConfig[14];		// Not Used
assign UseSdramFifo = ReadoutConfig[15];	// Not Used
assign common_offset = ReadoutConfig[27:16];
assign en_baseline_subtraction = ReadoutConfig[28];
assign dummy_enable = ReadoutConfig[29];
assign Enable_EventBuilder = ReadoutConfig[30];
assign AllFifoClear = ReadoutConfig[31];

assign ResetLatency = TrigGenConfig_ck40[7:0];
assign MaxTrigOut = TrigGenConfig_ck40[11:8];
assign TrigMode = TrigGenConfig_ck40[14:12];
//						trig_disable      = (TRIG_MODE == 3'b000);
//						trig_apv_normal   = (TRIG_MODE == 3'b001);
//						trig_apv_multiple = (TRIG_MODE == 3'b010);
//						calib_trig_apv    = (TRIG_MODE == 3'b011);
assign TrigTestMode = TrigGenConfig_ck40[15];	// NOT USED
assign EnSyncP0 = TrigGenConfig_ck40[16];
assign EnSyncFront = TrigGenConfig_ck40[17];
assign sw_apv_trig = TrigGenConfig_ck40[18];
assign sw_apv_reset = TrigGenConfig_ck40[19];
assign tdc_select = TrigGenConfig_ck40[20];
assign EnTrig1P0 = TrigGenConfig_ck40[21];
assign EnTrig2P0 = TrigGenConfig_ck40[22];
assign EnTrigFront = TrigGenConfig_ck40[23];
assign CalibLatency = TrigGenConfig_ck40[31:24];	// effective latency = CalibLatency + 4

`ifndef MPD_ucf
assign incoming_trigger = (EnTrigFront & user_in[0]) | sw_apv_trig;
assign sync = (EnSyncFront & user_in[1]) | sw_apv_reset;
`else
assign incoming_trigger = (EnTrigFront & TRIG_IN_UCF) | sw_apv_trig;
assign sync = (EnSyncFront & SYNC_IN_UCF) | sw_apv_reset;
`endif

assign EventBuilder_Read = DirectReadoutEnabled ? TcpEventBuilder_Read : ApvFifo_read[0];

	always @(posedge bus_clk)
	begin
		module_access <= (|bus_we) | (|bus_re);
		module_select <= |tcp_connected;
	end

	always @(posedge apv_clk)
	begin
		RST_APV <= main_resetB & ~i2c_ApvReset;	// active low
		BUSY_OUT <= internal_trigger_disabled; // | (FifoLevel1&UseSdramFifo) | (EvbFifoAlmostFull&~UseSdramFifo);
		AllClear <= AllFifoClear | apv_reset101;
	end

`ifdef QUESTA
assign si5338_done = 1'b1;
assign si5338_error = 1'b0;
assign I2C_PLL_SCL = 1'b1;
assign I2C_PLL_SDA = 1'b1;
`else

`ifdef MPD_10G
si5338  #(.input_clk(40_000_000), .i2c_address(7'b111_0000), .bus_clk(250_000)
	) si5338_inst (
		.clk(CK40_bufg),
		.reset(~ASYNC_RSTb),
		.done(si5338_done),		// can be used to release the reset
		.error(si5338_error),
		.SCL(I2C_PLL_SCL),
		.SDA(I2C_PLL_SDA)
	);
`else
assign si5338_done = 1'b1;
assign si5338_error = 1'b0;
assign I2C_PLL_SCL = 1'b1;
assign I2C_PLL_SDA = 1'b1;
`endif

`endif

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(1))
	xpm_cdc_array_single_user_soft_reset (
		.dest_out(user_soft_reset_ck40),
		.dest_clk(CK40_bufg),
		.src_clk(1'b0),
		.src_in(user_soft_reset)
	);

SyncReset ResetGenerator_orig(.CK(CK40_bufg),
`ifdef QUESTA
	.ASYNC_RSTb(ASYNC_RSTb & main_pll_locked),
`else
	.ASYNC_RSTb(ASYNC_RSTb & end_of_startup & si5338_done & |generated_mac_address & main_pll_locked),
`endif
	.USER_RSTb(~user_soft_reset_ck40), .SYNC_RSTb(main_resetB));
assign spi_reset = ~ASYNC_RSTb;
assign pma_reset = ~main_resetB;
assign stack_reset = ~main_resetB;

CDC_Sync1 stack_reset_sync(.CK(clk156), .IN(stack_reset), .OUT(stack_reset_clk156));

/*
always @(posedge clk156 or negedge qpll_lock)
begin
	if( qpll_lock == 0 )
	begin
		stack_block_reset <= 1;
		stack_reset_cnt <= 0;
	end
	else
	begin
		if( stack_reset_cnt < 255 )
			stack_reset_cnt <= stack_reset_cnt + 1;
		if( stack_reset_cnt > 0 && stack_reset_cnt < 64 )
			stack_block_reset <= 0;
		if( stack_reset_cnt > 0 && stack_reset_cnt >= 64 && stack_reset_cnt < 255)
			stack_block_reset <= 1;
		if( stack_reset_cnt == 255 )
			stack_block_reset <= 0;			
	end
end
*/

/*
MpdReset ResetGenerator(.CLK(CK40_bufg), .ASYNC_RSTb(ASYNC_RSTb & ~user_soft_reset),
	.SFP_TXFAULT(SFP_TX_FAULT), .SFP_LOS(SFP_RX_LOS), .SFP_PRES(SFP_PRESENT), .EOS(end_of_startup),
	.PG_MGT_1V(PG_MGT_1V), .PG_MGT_1V2(PG_MGT_1V2), .EN_MGT(EN_MGT),
	.MAIN_PLL_LOCK(main_pll_locked), .PMA_MMCM_LOCK(pma_mmcm_locked), .PMA_RESET_DONE(pma_reset_done),
	.MAC_ADDR(generated_mac_address),
	.SPI_RESET(spi_reset),
	.PMA_RESET(pma_reset),
	.STACK_RESET(stack_reset),
	.MAIN_RESETb(main_resetB)
);
*/
// LED stuff
Div8 Ck500KHz_Gen(.OUT(clk05), .CK(clk8), .RSTb(main_resetB));
OneShot TurnOnLed0(.OUT(LED[0]), .START(module_access), .CK(clk05), .RSTb(main_resetB));
//OneShot TurnOnLed1(.OUT(LED[1]), .START(APV_TRIGGER), .CK(clk05), .RSTb(main_resetB));
//OneShot TurnOnLed2(.OUT(LED[2]), .START(~I2C_SCL), .CK(clk05), .RSTb(main_resetB));
//OneShot TurnOnLed3(.OUT(LED[3]), .START(1'b0), .CK(clk05), .RSTb(main_resetB));
assign LED[1] = txuserrdy_out;
assign LED[2] = pma_rxreset_done;
assign LED[3] = gtrxreset_out;

// In real MPD the Main clock generator must use 2 single ended inputs at 40 MHz, selectable with a switch
MainClockGen ClockGenerator(.reset(~ASYNC_RSTb), .locked(main_pll_locked),
`ifdef MPD_trenz
	.clk_in1(EXT_CLK), .clk_in2(CK40), .clk_in_sel(SWITCH[0]),	// clk_in_sel ? clk_in1 : clk_in2
`else
	.clk_in1_p(SYSCLK_P), .clk_in1_n(SYSCLK_N),
`endif
    // Clock out ports
`ifndef MPD_10G
    .clk_out1(clk200),		// 200 MHz (to PMA only)
    .clk_out2(clk125),		// 125 MHz (data processing clock)
    .clk_out3(clk40),		// 40 MHz (to APV)
    .clk_out4(bus_clk),		// 31.25 MHz Bus clock
    .clk_out5(clk8));		// 8 MHz (ADC SPI and other low speed devices)
`else
    .clk_out1(),			// not used in 10G version
    .clk_out2(),			// not used in 10G version
    .clk_out3(clk40),		// 40 MHz (to APV)
    .clk_out4(),			// not used in 10G version
    .clk_out5(clk8));		// 8 MHz (ADC SPI, flash access and other low speed devices)
assign bus_clk = clk156;	// was clk40
assign clk125 = clk156;		// used in CDC sync stages
assign tcp_clk = clk156;	// used in CDC sync stages
assign clk200 = 0;
`endif

ClkAdcGen ClkGenAdc1(
    .clk_in1(clk40),
    .clk_out1(CLK_ADC1),     // 40 MHz to ADC1
    .psclk(bus_clk), .psen(psen1), .psincdec(psincdec), .psdone(psdone1),
    .reset(reset_pll1), // input reset
    .locked(locked1));
	
ClkAdcGen ClkGenAdc2(
    .clk_in1(clk40),
    .clk_out1(CLK_ADC2),     // 40 MHz to ADC2
    .psclk(bus_clk), .psen(psen2), .psincdec(psincdec), .psdone(psdone2),
    .reset(reset_pll2), // input reset
    .locked(locked2));

PhaseShiftCtrl PsAdcControl(.CLK(bus_clk), .RSTb(main_resetB),
	.PHASE(adc_phase[5:0]), .ADC(adc_phase[6]), .RUN(adc_phase[7]), .DONE(adc_ps_done),
	.PSINCDEC(psincdec), .PSEN1(psen1), .PSEN2(psen2),
	.PSDONE1(psdone1), .PSDONE2(psdone2), .LOCKED1(locked1), .LOCKED2(locked2),
	.RSTPLL1(reset_pll1), .RSTPLL2(reset_pll2));

// bus_reset is active also when TCP is not connected
// A.C. In case of MPD_ucf, this is instantiated in TOP module
`ifdef MPD_ucf
//Assign TCP RX
assign tcp_rx_d = TCP_RX_DATA;
assign tcp_rx_dv = TCP_RX_DATA_VALID;
assign tcp_rx_rts = TCP_RX_RTS;
assign  TCP_RX_CTS = tcp_rx_cts;
//assign TCP TX
assign TCP_TX_DATA = tcp_tx_d;
assign TCP_TX_DATA_VALID=tcp_tx_dv;
assign tcp_tx_cts = TCP_TX_CTS;
assign tcp_connected=TCP_CONNECTED;
//assign tcp clk and bus reset=/[
assign clk156 = GCLK_125_REF;
assign bus_reset = GCLK_125_REF_RST;
`elsif MPD_10G

	always @(posedge clk156)
		bus_reset <= ~main_resetB;

// The follwing immplemets a 10GBASE-R interface
tcp_10gbe_pma #(
`ifdef QUESTA
	.DHCP_CLIENT_EN(dhcp_en? 2'b11 : 2'b10),
	.SIMULATION(simula ? 2'b11 : 2'b10))
`else
		.DHCP_CLIENT_EN(1'b1),
 		.SIMULATION(1'b0))
`endif
	Tcp10GbePma_inst(
    .REFCLK_P(MGT_CLK3_P),		// 156.25 MHz	// could be swapped to MGT_CLK1, but Si5338 must be reprogrammed
    .REFCLK_N(MGT_CLK3_N),		// 156.25 MHz
	.CLK100(clk100),			// 100 MHz to DRP
//	reset pulse must be > slowest clock period  (>400ns)
//	synchronous with TXOUTCLK
    .RESET_MAC(stack_reset_clk156),	// ???
    .RESET_STACK(stack_reset_clk156),	// ???
    .RESET_PMA(pma_reset),	// ???
//	IP signals
    .DYNAMIC_IPv4(~SWITCH[2]),
    .IPv4_ADDR(ipaddr),
    .IPv4_SUBNET_MASK(smask),
    .IPv4_GATEWAY_ADDR(gwaddr),
	.IPv4_ADDR_OUT(ipv4_out),	// static or DHCP assigned
    .CONNECTION_RESET(1'b0),
    .TCP_KEEPALIVE_EN(1'b1),
//	TCP payload
    .TCP_RX_DATA0(tcp_rx_d[0]),
    .TCP_RX_DATA1(tcp_rx_d[1]),
    .TCP_RX_DATA_VALID0(tcp_rx_dv[0]),
    .TCP_RX_DATA_VALID1(tcp_rx_dv[1]),
    .TCP_RX_RTS0(tcp_rx_rts[0]),
    .TCP_RX_RTS1(tcp_rx_rts[1]),
    .TCP_RX_CTS0(tcp_rx_cts[0]),
    .TCP_RX_CTS1(tcp_rx_cts[1]),
    .TCP_RX_CTS_ACK0(),
    .TCP_RX_CTS_ACK1(),
    .TCP_TX_DATA0(tcp_tx_d[0]),
    .TCP_TX_DATA1(tcp_tx_d[1]),
    .TCP_TX_DATA_VALID0(tcp_tx_dv[0]),
    .TCP_TX_DATA_VALID1(tcp_tx_dv[1]),
    .TCP_TX_DATA_FLUSH0(1'b0),
    .TCP_TX_DATA_FLUSH1(1'b0),
    .TCP_TX_CTS0(tcp_tx_cts[0]),
    .TCP_TX_CTS1(tcp_tx_cts[1]),
    .TCP_CONNECTED_FLAG0(tcp_connected[0]),
    .TCP_CONNECTED_FLAG1(tcp_connected[1]),
//	PCS/PMA signals
    .PMA_PMD_TYPE(3'b111),	// 10GBASE-SR
    .PCS_CORE_STATUS(pcs_core_status),		// out std_logic_vector(7 downto 0);
    .SIGNAL_DETECT(~SFP_RX_LOS),	// SFP_RX_LOS: 1 means that signal is not good
    .TX_FAULT(SFP_TX_FAULT),	// was 1'b0
    .TX_DISABLE(SFP_TX_DISABLE),// was unconnected
//	PCS/PMA shared signals
    .TXOUTCLK(clk156),		// 156.25 MHz
	.TXOUTCLK_2X(clk312),	// 312.5 MHz
//	MAC
    .MAC_ADDR(SWITCH[2] ? static_macaddr : generated_mac_address),
	.MAC_RX_FRAME_PRESENT(mac_frame_present),
//	PHY
    .PHY_CONFIG_CHANGE(1'b0),
    .PHY_RESET(pma_reset),
    .PHY_TEST_MODE(2'b00),
    .PHY_POWER_DOWN(1'b0),
    .PHY_STATUS(),			// out std_logic_vector(7 downto 0);
    .PHY_STATUS2(),			// out std_logic_vector(7 downto 0);
    .PHY_ID(),				// out std_logic_vector(15 downto 0);
    .PMA_RESETDONE(pma_reset_done),	// out std_logic;
	.QPLL_LOCK(qpll_lock),						// DEBUG
	.RESET_COUNTER_DONE(reset_counter_done),	// DEBUG
	.PMA_TXRESETDONE(pma_txreset_done),	// DEBUG
	.PMA_RXRESETDONE(pma_rxreset_done),	// DEBUG
    .GTTXRESET_OUT(gttxreset_out),		// DEBUG
    .GTRXRESET_OUT(gtrxreset_out),		// DEBUG
    .TXUSERRDY_OUT(txuserrdy_out),		// DEBUG
//	SFP Module
    .TXP(FIBER_TX_P),
    .TXN(FIBER_TX_N),
    .RXP(FIBER_RX_P),
    .RXN(FIBER_RX_N)
);
`else
assign mac_frame_present = 0;	// TO BE FIXED !!!
tcp_gbe_pma #(.NTCPSTREAMS(nstreams),.DHCP_EN(dhcp_en),.SIMULATION(simula)) TcpGbePma_inst(
	.IPv4_ADDR(ipaddr), .SUBNET_MASK(smask), .GATEWAY_IP_ADDR(gwaddr),	// static
	.IPv4_ADDR_OUT(ipv4_out),	// static or DHCP assigned
	.MAC_ADDR(SWITCH[2] ? static_macaddr : generated_mac_address),
	.DYNAMIC_IP(~SWITCH[2]),
	.SYSCLK_200(clk200), .PMA_RESET(pma_reset), .STACK_RESET(stack_reset),
	.MMCM_LOCKED(pma_mmcm_locked), .PMA_RESET_DONE(pma_reset_done),
	.GCLK_125_REF_RST(bus_reset), .GCLK_125_REF(tcp_clk),
//	Fiber Transceiver Interface
	.FIBER_CLK_P(FIBER_CLK_P), .FIBER_CLK_N(FIBER_CLK_N),
	.FIBER_TX_P(FIBER_TX_P), .FIBER_TX_N(FIBER_TX_N),
	.FIBER_RX_P(FIBER_RX_P), .FIBER_RX_N(FIBER_RX_N),
	.FIBER_TX_DIS(), .FIBER_RX_ERR_CNT(fiber_err_cnt),
//	TCP interface ports
	.TCP_RX_DATA(tcp_rx_d),	// This is System Verilog: VHDL array of std_logic_vector
	.TCP_RX_DATA_VALID(tcp_rx_dv),
	.TCP_RX_RTS(tcp_rx_rts),
	.TCP_RX_CTS(tcp_rx_cts),
	.TCP_TX_DATA(tcp_tx_d),	// This is System Verilog: VHDL array of std_logic_vector
	.TCP_TX_DATA_VALID(tcp_tx_dv),
	.TCP_TX_CTS(tcp_tx_cts),
	.TCP_CONNECTED(tcp_connected)
);
`endif

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(32))
	xpm_cdc_array_single_IP_ADDR (
		.dest_out(ipv4_out_bus_clk),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(ipv4_out)
	);

`ifndef MPD_10G
TcpBridge TcpBridge_6102(	// connected to the 1st TCP port (6102)
//	TCP interface ports
	.TCP_CLK(tcp_clk),
	.TCP_RX_DATA(tcp_rx_d[0]),
	.TCP_RX_DATA_VALID(tcp_rx_dv[0]),
	.TCP_RX_RTS(tcp_rx_rts[0]),
	.TCP_RX_CTS(tcp_rx_cts[0]),
	.TCP_TX_DATA(tcp_tx_d[0]),
	.TCP_TX_DATA_VALID(tcp_tx_dv[0]),
	.TCP_TX_CTS(tcp_tx_cts[0]),
	.TCP_CONNECTED(tcp_connected[0]),
	.TCP_ERROR(tcp_error0),
//	USER interface ports
	.BUS_CLK(bus_clk),
	.BUS_RESET(bus_reset),
	.BUS_WE(bus_we[0]),
	.BUS_ADDR(bus_addr0),
	.BUS_AM(bus_am0),
	.BUS_DW(bus_dw0),
	.BUS_RE(bus_re[0]),
	.BUS_DR(bus_dr0)
);
`else
TcpBridge_10G TcpBridge_6102(	// connected to the 1st TCP port (6102)
//	TCP interface ports
	.TCP_CLK(clk156),
	.TCP_RX_DATA(tcp_rx_d[0]),
	.TCP_RX_DATA_VALID(tcp_rx_dv[0]),
	.TCP_RX_RTS(tcp_rx_rts[0]),
	.TCP_RX_CTS(tcp_rx_cts[0]),
	.TCP_TX_DATA(tcp_tx_d[0]),
	.TCP_TX_DATA_VALID(tcp_tx_dv[0]),
	.TCP_TX_CTS(tcp_tx_cts[0]),
	.TCP_CONNECTED(tcp_connected[0]),
	.TCP_ERROR(tcp_error0),
//	USER interface ports
	.BUS_CLK(bus_clk),
//	.BUS_CLK(clk312),		// using clk312 needs to change it also to all other connected modules
	.BUS_RESET(bus_reset),
	.BUS_WE(bus_we[0]),
	.BUS_ADDR(bus_addr0),
	.BUS_AM(bus_am0),
	.BUS_DW(bus_dw0),
	.BUS_RE(bus_re[0]),
	.BUS_DR(bus_dr0)
);
`endif

`ifdef QUESTA
RWregister #(.NBIT(32)) ReadWriteTestRegister_6104	// addr = 5
	(.CK(bus_clk), .RST(1'b0), .DEN(sel2 & bus_we[2]), .OEN(sel2 & bus_re[2]), .D(bus_dw2),
	.Q(), .Q_HiZ(bus_dr2));
`ifndef MPD_10G
TcpBridge TcpBridge_6104(	// connected to the 3rd TCP port (6104)
//	TCP interface ports
	.TCP_CLK(tcp_clk),
	.TCP_RX_DATA(tcp_rx_d[2]),
	.TCP_RX_DATA_VALID(tcp_rx_dv[2]),
	.TCP_RX_RTS(tcp_rx_rts[2]),
	.TCP_RX_CTS(tcp_rx_cts[2]),
	.TCP_TX_DATA(tcp_tx_d[2]),
	.TCP_TX_DATA_VALID(tcp_tx_dv[2]),
	.TCP_TX_CTS(tcp_tx_cts[2]),
	.TCP_CONNECTED(tcp_connected[2]),
	.TCP_ERROR(tcp_error2),
//	USER interface ports
	.BUS_CLK(bus_clk),
	.BUS_RESET(bus_reset),
	.BUS_WE(bus_we[2]),
	.BUS_ADDR(bus_addr2),
	.BUS_AM(bus_am2),
	.BUS_DW(bus_dw2),
	.BUS_RE(bus_re[2]),
	.BUS_DR(bus_dr2)
);
	
`endif
`endif

	always @(*)
	begin
		case({sel_regbank, sel_adc_config, sel_i2c, sel_histo, (obuf_status_en | obuf_en | ch_en | thr_ram_en | ped_ram_en)})
			6'b100000: bus_dr0 <= rdata_regbank;
			6'b010000: bus_dr0 <= rdata_adc_config;
			6'b001000: bus_dr0 <= rdata_i2c;
			6'b000100: bus_dr0 <= rdata_histo1;
			6'b000010: bus_dr0 <= rdata_histo0;
			6'b000001: bus_dr0 <= rdata_ch;
			default: bus_dr0 <= 32'b0;
		endcase
	end
	
xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(1))
	xpm_cdc_array_single_read_flash_id (
		.dest_out(read_flash_id_clk8),
		.dest_clk(clk8),
		.src_clk(1'b0),
		.src_in(read_flash_id)
	);

SPI SpiFlash(
        .CLK(clk8),
        .reset(spi_reset),
        .si(SPI_IO0),
        .start(read_flash_id_clk8 | mac_gen_start),
        .command(8'h4B),
        .address(32'h0000_0000),
        .done(done_spi_rd),
        .sc(SPI_CS),
        .so(SPI_IO1),
        .data(flash_id),
		.eos(end_of_startup)
    );
	
mac_gen MacAddressGenerator(
		.clk(clk8),
		.reset(spi_reset),
		.eos(end_of_startup),
		.done(done_spi_rd),
		.flash_id(flash_id),
		.start_id_rd(mac_gen_start),
		.register(generated_mac_address)       
	);

//`ifndef QUESTA	// Do not simulate XADC
`ifndef MPD_kc705	// Simulate XADC for all but not KC705
XadcMpd Xadc_inst(
	.DCLK(CK40_bufg),
	.RESET(stack_reset),   
	.MEASURED_TEMP(temperature),	// T = -273.15 + (ADC_Code * 503.975) / 4096
	.MEASURED_VCCINT(vccint),	// Vx = 3.0 V * ADC_Code / 4096
	.MEASURED_VCCAUX(vccaux),	// ADC_Code is 12 bit unsigned value
	.MEASURED_VCCBRAM(vccbram)	// ADC_Code is on the 12 MSB of the 16 bit word
    );     
`else
assign temperature = 16'h5550;
assign vccint = 16'hAAA0;
assign vccaux = 16'hA5A0;
assign vccbram = 16'h5A50;
`endif

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(16))
	xpm_cdc_array_single_temperature (
		.dest_out(temperature_bus_clk),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(temperature)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(16))
	xpm_cdc_array_single_vccint (
		.dest_out(vccint_bus_clk),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(vccint)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(16))
	xpm_cdc_array_single_vccaux (
		.dest_out(vccaux_bus_clk),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(vccaux)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(16))
	xpm_cdc_array_single_vccbram (
		.dest_out(vccbram_bus_clk),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(vccbram)
	);


//A.C. in case of MPD_ucf, propagate in output the generated_mac_address
`ifdef MPD_ucf
assign MAC_ADDR=generated_mac_address;
`endif

PheripheralDecoder AddressDecoder_6102(.ADDR(bus_addr0[15:0]), .AM(bus_am0),
	.CONFIG_EN(sel_regbank), .ADC_EN(sel_adc_config), .I2C_EN(sel_i2c),
	.HISTO_EN(sel_histo), .HISTO_REG_EN(sel_histo_reg), .CHANNELS_EN(ch_en),
	.PED_RAM_EN(ped_ram_en), .THR_RAM_EN(thr_ram_en), .OBUF_EN(obuf_en),
	.OBUF_STATUS_EN(obuf_status_en)
	);

RegisterBank # (
	.HOG_DATE(GLOBAL_DATE), .HOG_TIME(GLOBAL_TIME), .HOG_VER(GLOBAL_VER),
	.HOG_SHA(GLOBAL_SHA), .COMPILE_TIME(`COMPILE_TIME)
	) ConfigRegisters (
	.RSTb(main_resetB), .CLK(bus_clk),
	.ADDR(bus_addr0[7:0]), .D_IN(bus_dw0), .D_OUT(rdata_regbank),
	.WE(bus_we[0]), .RE(bus_re[0]), .CE(sel_regbank),
	.HW_REV(HwRev), .PWR_STAT(PwrStat),
	.GEN_MAC_ADDR(generated_mac_address), .IPV4(ipv4_out_bus_clk),
	.PS_DONE(adc_ps_done), .FLASH_ID(flash_id), .READ_FLASH_ID(read_flash_id),
	.USER_RESET(user_soft_reset),
	.SAMPLE_PER_EVENT(SamplePerEvent), .EVENT_PER_BLOCK(EventPerBlock),
	.BUSY_THRESHOLD(BusyThreshold), .BUSY_THRESHOLD_LOCAL(BusyThresholdLocal),
	.IO_CONFIG(IoConfig), .READOUT_CONFIG(ReadoutConfig), .TRIGGER_CONFIG(TrigGenConfig),
	.TRIGGER_DELAY(TriggerDelay), .SYNC_PERIOD(ApvSyncPeriod), .MARKER_CHANNEL(MarkerCh),
	.CHANNEL_ENABLE(ApvEnable), .ZERO_THRESHOLD(zero_threshold),
	.ONE_THRESHOLD(one_threshold), .ADC_PHASE(adc_phase),
	.FIR0_COEFF(fir_coeff0), .FIR1_COEFF(fir_coeff1), .FIR2_COEFF(fir_coeff2),
	.FIR3_COEFF(fir_coeff3), .FIR4_COEFF(fir_coeff4), .FIR5_COEFF(fir_coeff5),
	.FIR6_COEFF(fir_coeff6), .FIR7_COEFF(fir_coeff7), .FIR8_COEFF(fir_coeff8),
	.FIR9_COEFF(fir_coeff9), .FIR10_COEFF(fir_coeff10), .FIR11_COEFF(fir_coeff11),
	.FIR12_COEFF(fir_coeff12), .FIR13_COEFF(fir_coeff13), .FIR14_COEFF(fir_coeff14),
	.FIR15_COEFF(fir_coeff15),
	.TEMP(temperature_bus_clk), .VCCINT(vccint_bus_clk),
	.VCCAUX(vccaux_bus_clk), .VCCBRAM(vccbram_bus_clk));

AdcConfigMachine AdcConfigurator(
	.RSTb(main_resetB), .CLK(bus_clk),
	.WE(bus_we[0]), .RE(bus_re[0]), .CE(sel_adc_config),
	.D_IN(bus_dw0), .D_OUT(rdata_adc_config),
	.AdcConfigClk(clk8),
	.ADC_CS1b(ADC_CS1b), .ADC_CS2b(ADC_CS2b), .ADC_SCLK(ADC_SCLK), .ADC_SDA(ADC_SDA));

i2c_master_top I2C_Controller(
	.wb_clk_i(bus_clk), .wb_rst_i(1'b0), .arst_i(main_resetB), .wb_adr_i(bus_addr0[2:0]),
	.WE(bus_we[0]), .RE(bus_re[0]), .CE(sel_i2c),
	.D_IN(bus_dw0[7:0]), .D_OUT(rdata_i2c),
	.scl_pad_i(I2C_SCL), .scl_pad_o(), .scl_padoen_o(scl_oeB),
	.sda_pad_i(I2C_SDA), .sda_pad_o(), .sda_padoen_o(sda_oeB),
	.ApvReset(i2c_ApvReset) );

AdcDeser AdcDeser0(.ADC_SDATA({ADC7,ADC6,ADC5,ADC4,ADC3,ADC2,ADC1,ADC0}),
	.LCLK(LCLK_ADC1_bufr), .ADCLK(ADCLK_ADC1),
	.ADC_PDATA0(padc0), .ADC_PDATA1(padc1), .ADC_PDATA2(padc2), .ADC_PDATA3(padc3),
	.ADC_PDATA4(padc4), .ADC_PDATA5(padc5), .ADC_PDATA6(padc6), .ADC_PDATA7(padc7));

AdcDeser AdcDeser1(.ADC_SDATA({ADC15,ADC14,ADC13,ADC12,ADC11,ADC10,ADC9,ADC8}),
	.LCLK(LCLK_ADC2_bufr), .ADCLK(ADCLK_ADC2),
	.ADC_PDATA0(padc8), .ADC_PDATA1(padc9), .ADC_PDATA2(padc10), .ADC_PDATA3(padc11),
	.ADC_PDATA4(padc12), .ADC_PDATA5(padc13), .ADC_PDATA6(padc14), .ADC_PDATA7(padc15));

fir_8ch filter1(.CLK(ADCLK_ADC1), .ENABLE_FIR(FIR_enable),
	.COEFF_0(fir_coeff0), .COEFF_1(fir_coeff1), .COEFF_2(fir_coeff2), .COEFF_3(fir_coeff3),
	.COEFF_4(fir_coeff4), .COEFF_5(fir_coeff5), .COEFF_6(fir_coeff6), .COEFF_7(fir_coeff7),
	.COEFF_8(fir_coeff8), .COEFF_9(fir_coeff9), .COEFF_10(fir_coeff10), .COEFF_11(fir_coeff11),
	.COEFF_12(fir_coeff12), .COEFF_13(fir_coeff13), .COEFF_14(fir_coeff14),
	.COEFF_15(fir_coeff15),
	.DATA_IN0(padc0), .DATA_OUT0(padcx0),
	.DATA_IN1(padc1), .DATA_OUT1(padcx1),
	.DATA_IN2(padc2), .DATA_OUT2(padcx2),
	.DATA_IN3(padc3), .DATA_OUT3(padcx3),
	.DATA_IN4(padc4), .DATA_OUT4(padcx4),
	.DATA_IN5(padc5), .DATA_OUT5(padcx5),
	.DATA_IN6(padc6), .DATA_OUT6(padcx6),
	.DATA_IN7(padc7), .DATA_OUT7(padcx7));

fir_8ch filter2(.CLK(ADCLK_ADC2), .ENABLE_FIR(FIR_enable),
	.COEFF_0(fir_coeff0), .COEFF_1(fir_coeff1), .COEFF_2(fir_coeff2), .COEFF_3(fir_coeff3),
	.COEFF_4(fir_coeff4), .COEFF_5(fir_coeff5), .COEFF_6(fir_coeff6), .COEFF_7(fir_coeff7),
	.COEFF_8(fir_coeff8), .COEFF_9(fir_coeff9), .COEFF_10(fir_coeff10), .COEFF_11(fir_coeff11),
	.COEFF_12(fir_coeff12), .COEFF_13(fir_coeff13), .COEFF_14(fir_coeff14),
	.COEFF_15(fir_coeff15),
	.DATA_IN0(padc8), .DATA_OUT0(padcx8),
	.DATA_IN1(padc9), .DATA_OUT1(padcx9),
	.DATA_IN2(padc10), .DATA_OUT2(padcx10),
	.DATA_IN3(padc11), .DATA_OUT3(padcx11),
	.DATA_IN4(padc12), .DATA_OUT4(padcx12),
	.DATA_IN5(padc13), .DATA_OUT5(padcx13),
	.DATA_IN6(padc14), .DATA_OUT6(padcx14),
	.DATA_IN7(padc15), .DATA_OUT7(padcx15));

// Block transfer write operation does not work on Histo RAM
Histogrammer AdcHisto0(.LCLK(LCLK_ADC1_bufr), .ADCLK(ADCLK_ADC1),
	.ADC_PDATA0(padcx0), .ADC_PDATA1(padcx1), .ADC_PDATA2(padcx2), .ADC_PDATA3(padcx3),
	.ADC_PDATA4(padcx4), .ADC_PDATA5(padcx5), .ADC_PDATA6(padcx6), .ADC_PDATA7(padcx7),
	.RSTb(main_resetB), .CLK(bus_clk),
	.WE(bus_we[0]), .RE(bus_re[0]), .CE(sel_histo[0]),
	.USER_ADDR({sel_histo_reg[0], bus_addr0[11:0]}),
	.DATA_IN(bus_dw0), .DATA_OUT(rdata_histo0));

Histogrammer AdcHisto1(.LCLK(LCLK_ADC2_bufr), .ADCLK(ADCLK_ADC2),
	.ADC_PDATA0(padcx8), .ADC_PDATA1(padcx9), .ADC_PDATA2(padcx10), .ADC_PDATA3(padcx11),
	.ADC_PDATA4(padcx12), .ADC_PDATA5(padcx13), .ADC_PDATA6(padcx14), .ADC_PDATA7(padcx15),
	.RSTb(main_resetB), .CLK(bus_clk),
	.WE(bus_we[0]), .RE(bus_re[0]), .CE(sel_histo[1]),
	.USER_ADDR({sel_histo_reg[1], bus_addr0[11:0]}),
	.DATA_IN(bus_dw0), .DATA_OUT(rdata_histo1));

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(32))
	xpm_cdc_array_single_TRIGGER_CONFIG (
		.dest_out(TrigGenConfig_ck40),
		.dest_clk(apv_clk),
		.src_clk(1'b0),
		.src_in(TrigGenConfig)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(32))
	xpm_cdc_array_single_IO_CONFIG (
		.dest_out(IoConfig_ck40),
		.dest_clk(apv_clk),
		.src_clk(1'b0),
		.src_in(IoConfig)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(8))
	xpm_cdc_array_single_TRIGGER_DELAY (
		.dest_out(TriggerDelay_ck40),
		.dest_clk(apv_clk),
		.src_clk(1'b0),
		.src_in(TriggerDelay)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(8))
	xpm_cdc_array_single_MARKER_CH (
		.dest_out(MarkerCh_ck40),
		.dest_clk(apv_clk),
		.src_clk(1'b0),
		.src_in(MarkerCh)
	);

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(8))
	xpm_cdc_array_single_EVENT_PER_BLOCK (
		.dest_out(EventPerBlock_ck125),
		.dest_clk(clk125),
		.src_clk(1'b0),
		.src_in(EventPerBlock)
	);


TrigGen ApvTriggerHandler(.APV_TRG(APV_TRIGGER), .RESET101(apv_reset101), .RSTb(main_resetB),
	.CLK(apv_clk), .MAX_TRIG_OUT(MaxTrigOut), .TRIG_PULSE(apv_trigger_pulse),
	.TRIG_MODE(TrigMode),
	.TRIG_CMD(incoming_trigger), .RESET_CMD(sync),
	.MISSING_TRIGGER_CNT(missing_trigger_count), .APV_TRIGGER_CNT(apv_trigger_count),
	.INCOMING_TRIGGER_CNT(incoming_trigger_count),
	.MAX_RESET_LATENCY(ResetLatency), .CALIB_LATENCY(CalibLatency),
	.NO_MORE_SPACE(no_more_space),
	.SPACE_AVAILABLE( &ApvFifoEmpty ), .OUTPUT_FIFO_ALMOST_FULL(1'b0),	// TBC
	.TRIGGER_DISABLED(internal_trigger_disabled), .TRIGGER_DELAY(TriggerDelay_ck40));

xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(8))
	xpm_cdc_array_single_MISSING_TRIGGER_COUNT (
		.dest_out(missing_trigger_count_s),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(missing_trigger_count)
	);
xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(32))
	xpm_cdc_array_single_APV_TRIGGER_COUNT (
		.dest_out(apv_trigger_count_s),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(apv_trigger_count)
	);
xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(32))
	xpm_cdc_array_single_INCOMING_TRIGGER_COUNT (
		.dest_out(incoming_trigger_count_s),
		.dest_clk(bus_clk),
		.src_clk(1'b0),
		.src_in(incoming_trigger_count)
	);

AllChannels Channels(.RSTb_sync(main_resetB),
	.PROCESS_CLK(bus_clk),
	.ADC_FRAME_CK1(ADCLK_ADC1), .ADC_FRAME_CK2(ADCLK_ADC2),
	.APV_ENABLE(ApvEnable), .EN_BASELINE_SUBTRACTION(en_baseline_subtraction),
	.ADCX0(padcx0), .ADCX1(padcx1), .ADCX2(padcx2), .ADCX3(padcx3), 
	.ADCX4(padcx4), .ADCX5(padcx5), .ADCX6(padcx6), .ADCX7(padcx7), 
	.ADCX8(padcx8), .ADCX9(padcx9), .ADCX10(padcx10), .ADCX11(padcx11), 
	.ADCX12(padcx12), .ADCX13(padcx13), .ADCX14(padcx14), //.ADCX15(padcx15),
	.SYNC_PERIOD(ApvSyncPeriod), .APV_SYNCED(ApvSynced), .COMMON_OFFSET(common_offset),
	.APV_FIFO_DATA0(ApvFifoData0), .APV_FIFO_DATA1(ApvFifoData1),
	.APV_FIFO_DATA2(ApvFifoData2), .APV_FIFO_DATA3(ApvFifoData3),
	.APV_FIFO_DATA4(ApvFifoData4), .APV_FIFO_DATA5(ApvFifoData5),
	.APV_FIFO_DATA6(ApvFifoData6), .APV_FIFO_DATA7(ApvFifoData7),
	.APV_FIFO_DATA8(ApvFifoData8), .APV_FIFO_DATA9(ApvFifoData9),
	.APV_FIFO_DATA10(ApvFifoData10), .APV_FIFO_DATA11(ApvFifoData11),
	.APV_FIFO_DATA12(ApvFifoData12), .APV_FIFO_DATA13(ApvFifoData13),
	.APV_FIFO_DATA14(ApvFifoData14), .APV_FIFO_DATA15(ApvFifoData15),
	.EVB_DATA0(EvbData0), .EVB_DATA1(EvbData1),
	.EVB_DATA2(EvbData2), .EVB_DATA3(EvbData3),
	.EVB_DATA4(EvbData4), .EVB_DATA5(EvbData5),
	.EVB_DATA6(EvbData6), .EVB_DATA7(EvbData7),
	.EVB_DATA8(EvbData8), .EVB_DATA9(EvbData9),
	.EVB_DATA10(EvbData10), .EVB_DATA11(EvbData11),
	.EVB_DATA12(EvbData12), .EVB_DATA13(EvbData13),
	.EVB_DATA14(EvbData14), .EVB_DATA15(EvbData15),
	.APV_FIFO_EMPTY(ApvFifoEmpty), .APV_FIFO_FULL(ApvFifoFull),
	.READ_FIFO(Enable_EventBuilder ? ApvFifoRd_EVB : ApvFifo_read),
	.ONE_THRESHOLD(one_threshold), .ZERO_THRESHOLD(zero_threshold),
//	.ALL_CLEAR(AllClear_clk156), .READOUT_MODE(ReadoutMode),
	.ALL_CLEAR(AllClear), .READOUT_MODE(ReadoutMode),
	.USED_FIFO_WORDS0(used_fifo_words0), .USED_FIFO_WORDS1(used_fifo_words1),
	.USED_FIFO_WORDS2(used_fifo_words2), .USED_FIFO_WORDS3(used_fifo_words3),
	.USED_FIFO_WORDS4(used_fifo_words4), .USED_FIFO_WORDS5(used_fifo_words5),
	.USED_FIFO_WORDS6(used_fifo_words6), .USED_FIFO_WORDS7(used_fifo_words7),
	.USED_FIFO_WORDS8(used_fifo_words8), .USED_FIFO_WORDS9(used_fifo_words9),
	.USED_FIFO_WORDS10(used_fifo_words10), .USED_FIFO_WORDS11(used_fifo_words11),
	.USED_FIFO_WORDS12(used_fifo_words12), .USED_FIFO_WORDS13(used_fifo_words13),
	.USED_FIFO_WORDS14(used_fifo_words14), .USED_FIFO_WORDS15(used_fifo_words15),
	.ONE_MORE_EVENT(OneMoreEvent), .DECR_EVENT_COUNTER(DecrEventCounter),
	.NO_MORE_SPACE(no_more_space), .MARKER_CH(MarkerCh_ck40), .SAMPLE_PER_EVENT(SamplePerEvent),
	.WE_PED_RAM(we_ped_ram), .RE_PED_RAM(re_ped_ram),
	.WE_THR_RAM(we_thr_ram), .RE_THR_RAM(re_thr_ram),
	.RAM_ADDR(bus_addr0[6:0]), .RAM_DIN(bus_dw0), .MODULE_ID(module_id),
	.APV_FIFO_FULL_L(ApvFifoFullLatched), .PROC_FIFO_FULL_L(ProcFifoFullLatched),
	.missed_event_cnt0(missed_event_cnt0), .missed_event_cnt1(missed_event_cnt1),
	.missed_event_cnt2(missed_event_cnt2), .missed_event_cnt3(missed_event_cnt3),
	.missed_event_cnt4(missed_event_cnt4), .missed_event_cnt5(missed_event_cnt5),
	.missed_event_cnt6(missed_event_cnt6), .missed_event_cnt7(missed_event_cnt7),
	.missed_event_cnt8(missed_event_cnt8), .missed_event_cnt9(missed_event_cnt9),
	.missed_event_cnt10(missed_event_cnt10), .missed_event_cnt11(missed_event_cnt11),
	.missed_event_cnt12(missed_event_cnt12), .missed_event_cnt13(missed_event_cnt13),
	.missed_event_cnt14(missed_event_cnt14), .missed_event_cnt15(missed_event_cnt15),
	.writefull_cnt0(writefull_cnt0), .writefull_cnt1(writefull_cnt1),
	.writefull_cnt2(writefull_cnt2), .writefull_cnt3(writefull_cnt3),
	.writefull_cnt4(writefull_cnt4), .writefull_cnt5(writefull_cnt5),
	.writefull_cnt6(writefull_cnt6), .writefull_cnt7(writefull_cnt7),
	.writefull_cnt8(writefull_cnt8), .writefull_cnt9(writefull_cnt9),
	.writefull_cnt10(writefull_cnt10), .writefull_cnt11(writefull_cnt11),
	.writefull_cnt12(writefull_cnt12), .writefull_cnt13(writefull_cnt13),
	.writefull_cnt14(writefull_cnt14), .writefull_cnt15(writefull_cnt15)
);

FifoIf DebugFifoIf(.FIFO_RD(ApvFifo_read),
	.FIFO_DATA_OUT0(ApvFifoData0), .FIFO_DATA_OUT1(ApvFifoData1),
	.FIFO_DATA_OUT2(ApvFifoData2), .FIFO_DATA_OUT3(ApvFifoData3),
	.FIFO_DATA_OUT4(ApvFifoData4), .FIFO_DATA_OUT5(ApvFifoData5),
	.FIFO_DATA_OUT6(ApvFifoData6), .FIFO_DATA_OUT7(ApvFifoData7),
	.FIFO_DATA_OUT8(ApvFifoData8), .FIFO_DATA_OUT9(ApvFifoData9),
	.FIFO_DATA_OUT10(ApvFifoData10), .FIFO_DATA_OUT11(ApvFifoData11),
	.FIFO_DATA_OUT12(ApvFifoData12), .FIFO_DATA_OUT13(ApvFifoData13),
	.FIFO_DATA_OUT14(ApvFifoData14), .FIFO_DATA_OUT15(ApvFifoData15),
	.USED_FIFO_WORDS0(used_fifo_words0), .USED_FIFO_WORDS1(used_fifo_words1),
	.USED_FIFO_WORDS2(used_fifo_words2), .USED_FIFO_WORDS3(used_fifo_words3),
	.USED_FIFO_WORDS4(used_fifo_words4), .USED_FIFO_WORDS5(used_fifo_words5),
	.USED_FIFO_WORDS6(used_fifo_words6), .USED_FIFO_WORDS7(used_fifo_words7),
	.USED_FIFO_WORDS8(used_fifo_words8), .USED_FIFO_WORDS9(used_fifo_words9),
	.USED_FIFO_WORDS10(used_fifo_words10), .USED_FIFO_WORDS11(used_fifo_words11),
	.USED_FIFO_WORDS12(used_fifo_words12), .USED_FIFO_WORDS13(used_fifo_words13),
	.USED_FIFO_WORDS14(used_fifo_words14), .USED_FIFO_WORDS15(used_fifo_words15),
	.FIFO_EMPTY(ApvFifoEmpty), .FIFO_FULL(ApvFifoFull),
	.SYNCED(ApvSynced),
	
	.RSTb(main_resetB), .CLK(bus_clk),
	.WE(bus_we[0]), .RE(bus_re[0]),
	.FIFO_CE(ch_en), .THR_CE(thr_ram_en), .PED_CE(ped_ram_en), .OBUF_STATUS_CE(obuf_status_en),
	.USER_ADDR(bus_addr0[15:0]),
	.DATA_OUT(rdata_ch),

	.MISSED_TRIGGER(missing_trigger_count_s), .INCOMING_TRIGGER_CNT(incoming_trigger_count_s),
	.WAITING_ON_APV_MASK(WAITING_ON_APV_MASK),
	.WE_PED_RAM(we_ped_ram), .RE_PED_RAM(re_ped_ram),
	.WE_THR_RAM(we_thr_ram), //.RE_THR_RAM(re_thr_ram),
	.EV_BUILDER_ENABLE(Enable_EventBuilder),
	.EV_BUILDER_FIFO_WC({3'h0,EventBuilder_Wc}),
	.EV_BUILDER_EV_CNT(EventBuilder_EvCnt),
	.EV_BUILDER_BLOCK_CNT(EventBuilder_BlockCnt),
	.EV_BUILDER_DATA_OUT(EvBuilderDataOut),
	.EV_BUILDER_FIFO_EMPTY(EventBuilder_Empty),
	.EV_BUILDER_FIFO_FULL(EventBuilder_Full),
	.TRIGGER_COUNTER(apv_trigger_count_s),
	.TRIGGER_TIME_FIFO_RD(trigger_time_fifo_rd),
//	.TRIGGER_TIME_FIFO(trigger_time_fifo_data),
//	.TRIGGER_TIME_FIFO_FULL(trigger_time_fifo_full), .TRIGGER_TIME_FIFO_EMPTY(trigger_time_fifo_empty),
	.TRIGGER_TIME_FIFO(8'h00),
	.TRIGGER_TIME_FIFO_FULL(1'b0), .TRIGGER_TIME_FIFO_EMPTY(1'b1),
	.APV_FIFO_FULL_L(ApvFifoFullLatched), .PROC_FIFO_FULL_L(ProcFifoFullLatched),
//	.OUTPUT_FIFO_FULL(Output_Fifo_Full), .OUTPUT_FIFO_EMPTY(Output_Fifo_Empty), .OUTPUT_FIFO_WC(Output_Fifo_Wc),
//	.OUTPUT_FIFO_FULL_L(OutputFifoFullLatched),
	.OUTPUT_FIFO_FULL(1'b0), .OUTPUT_FIFO_EMPTY(1'b1), .OUTPUT_FIFO_WC(13'b0),
	.OUTPUT_FIFO_FULL_L(1'b0),
//	.EVB_FIFO_FULL_L(EvbFifoFullLatched), .EVENT_FIFO_FULL_L(EventFifoFullLatched), .TIME_FIFO_FULL_L(TimeFifoFullLatched),
	.EVB_FIFO_FULL_L(1'b0), .EVENT_FIFO_FULL_L(1'b0), .TIME_FIFO_FULL_L(1'b0),
	.missed_event_cnt0(missed_event_cnt0), .missed_event_cnt1(missed_event_cnt1),
	.missed_event_cnt2(missed_event_cnt2), .missed_event_cnt3(missed_event_cnt3),
	.missed_event_cnt4(missed_event_cnt4), .missed_event_cnt5(missed_event_cnt5),
	.missed_event_cnt6(missed_event_cnt6), .missed_event_cnt7(missed_event_cnt7),
	.missed_event_cnt8(missed_event_cnt8), .missed_event_cnt9(missed_event_cnt9),
	.missed_event_cnt10(missed_event_cnt10), .missed_event_cnt11(missed_event_cnt11),
	.missed_event_cnt12(missed_event_cnt12), .missed_event_cnt13(missed_event_cnt13),
	.missed_event_cnt14(missed_event_cnt14), .missed_event_cnt15(missed_event_cnt15),
	.writefull_cnt0(writefull_cnt0), .writefull_cnt1(writefull_cnt1),
	.writefull_cnt2(writefull_cnt2), .writefull_cnt3(writefull_cnt3),
	.writefull_cnt4(writefull_cnt4), .writefull_cnt5(writefull_cnt5),
	.writefull_cnt6(writefull_cnt6), .writefull_cnt7(writefull_cnt7),
	.writefull_cnt8(writefull_cnt8), .writefull_cnt9(writefull_cnt9),
	.writefull_cnt10(writefull_cnt10), .writefull_cnt11(writefull_cnt11),
	.writefull_cnt12(writefull_cnt12), .writefull_cnt13(writefull_cnt13),
	.writefull_cnt14(writefull_cnt14), .writefull_cnt15(writefull_cnt15),
	.SyncCounter(SyncCounter)
	);
	
	
xpm_cdc_array_single #(.SRC_INPUT_REG(0), .DEST_SYNC_FF(2), .WIDTH(1))
	xpm_cdc_array_single_AllClear (
		.dest_out(AllClear_clk156),
		.dest_clk(clk156),
		.src_clk(1'b0),
		.src_in(AllClear)
	);

EventBuilder TheBuilder(.RSTb(main_resetB), .APV_CLOCK(apv_clk),
	.CLK(clk156),
	.TRIGGER(apv_trigger_pulse),	// Pulse sent to APVs
	.SYNC(apv_reset101),
	.ALL_CLEAR(AllClear_clk156),
	.SAMPLE_PER_EVENT(SamplePerEvent), .EVENT_PER_BLOCK(EventPerBlock_ck125),
	.ENABLE_MASK(ApvEnable), .ENABLE_EVBUILD(Enable_EventBuilder),
//	.TRIGGER_TIME_FIFO(trigger_time_fifo_data), .TRIGGER_TIME_FIFO_RD(trigger_time_fifo_rd_evb),
	.DISABLE_DEADLOCK(disable_evb_deadlock),
	.CH_DATA0(EvbData0), .CH_DATA1(EvbData1),
	.CH_DATA2(EvbData2), .CH_DATA3(EvbData3),
	.CH_DATA4(EvbData4), .CH_DATA5(EvbData5),
	.CH_DATA6(EvbData6), .CH_DATA7(EvbData7),
	.CH_DATA8(EvbData8), .CH_DATA9(EvbData9),
	.CH_DATA10(EvbData10), .CH_DATA11(EvbData11),
	.CH_DATA12(EvbData12), .CH_DATA13(EvbData13),
	.CH_DATA14(EvbData14), .CH_DATA15(EvbData15),
	.DATA_RD(ApvFifoRd_EVB), .EVENT_PRESENT(OneMoreEvent),
	.DECREMENT_EVENT_COUNT(DecrEventCounter), .MODULE_ID(module_id),
	.DATA_OUT(EvBuilderDataOut), .EMPTY(EventBuilder_Empty), .FULL(EventBuilder_Full),
	.ALMOST_FULL(EvbFifoAlmostFull),
	.DATA_OUT_CNT(EventBuilder_Wc), .DATA_OUT_RD(EventBuilder_Read),
	.EV_CNT(EventBuilder_EvCnt), .BLOCK_CNT(EventBuilder_BlockCnt),
	.EVB_FIFO_FULL_L(EvbFifoFullLatched), .EVENT_FIFO_FULL_L(EventFifoFullLatched), .TIME_FIFO_FULL_L(TimeFifoFullLatched),
	.WAITING_ON_APV_MASK(WAITING_ON_APV_MASK), .SyncCounter(SyncCounter)
	);

`ifdef MPD_10G
TcpBridgeEvb_10G TcpBridge_6103(	// connected to the 2nd TCP port (6103)
//	TCP interface ports
	.TCP_CLK(clk156),
	.TCP_RX_DATA(tcp_rx_d[1]),
	.TCP_RX_DATA_VALID(tcp_rx_dv[1]),
	.TCP_RX_RTS(tcp_rx_rts[1]),
	.TCP_RX_CTS(tcp_rx_cts[1]),
//	.TCP_TX_DATA(tcp_tx_d[1]),
//	.TCP_TX_DATA_VALID(tcp_tx_dv[1]),
	.TCP_TX_DATA(tcp_tx_d_evb),
	.TCP_TX_DATA_VALID(tcp_tx_dv_evb),
	.TCP_TX_CTS(tcp_tx_cts[1]),
	.TCP_CONNECTED(tcp_connected[1]),
	.TCP_ERROR(tcp_error1),
//	Event Builder interface ports
	.EVB_CLK(clk156),
	.EVB_RESET(~main_resetB),
	.EVB_EMPTY(Enable_EventBuilder ? EventBuilder_Empty : dummy_empty),
	.EVB_ENABLE(Enable_EventBuilder | dummy_enable),
	.EVB_RD(TcpEventBuilder_Read),
	.EVB_DATA(Enable_EventBuilder ? EvBuilderDataOut : dummy_data)
);
`else
TcpBridgeEvb TcpBridge_6103(	// connected to the 2nd TCP port (6103)
//	TCP interface ports
	.TCP_CLK(tcp_clk),
	.TCP_RX_DATA(tcp_rx_d[1]),
	.TCP_RX_DATA_VALID(tcp_rx_dv[1]),
	.TCP_RX_RTS(tcp_rx_rts[1]),
	.TCP_RX_CTS(tcp_rx_cts[1]),
	.TCP_TX_DATA(tcp_tx_d[1]),
	.TCP_TX_DATA_VALID(tcp_tx_dv[1]),
	.TCP_TX_CTS(tcp_tx_cts[1]),
	.TCP_CONNECTED(tcp_connected[1]),
	.TCP_ERROR(tcp_error1),
//	Event Builder interface ports
	.EVB_CLK(clk125),
	.EVB_RESET(~main_resetB),
	.EVB_EMPTY(Enable_EventBuilder ? EventBuilder_Empty : dummy_empty),
	.EVB_ENABLE(Enable_EventBuilder | dummy_enable),
	.EVB_RD(TcpEventBuilder_Read),
	.EVB_DATA(Enable_EventBuilder ? EvBuilderDataOut : dummy_data)
);
`endif

TestDataGenerator DummyDataGen(
`ifdef MPD_10G 
	.CLK(tcp_clk),
`else
	.CLK(clk312),
`endif
	.RESET(~main_resetB | ~tcp_connected[1]),
	.EMPTY(dummy_empty),
	.NEXT(dummy_enable & TcpEventBuilder_Read),
	.DATA(dummy_data)
);
`ifdef MPD_ucf	// To be checked!
    assign EVB_CLOCK_OUT = clk125;
    assign EVB_ENABLE_OUT = Enable_EventBuilder | dummy_enable;
    assign EVB_EMPTY_OUT = Enable_EventBuilder ? EventBuilder_Empty : dummy_empty;
    assign EVB_DATA_OUT = Enable_EventBuilder ? EvBuilderDataOut : dummy_data;
`endif

/* MISSING PARTS: TO BE RECHECKED!!!
TrigMeas TriggerMeasurements(.FAST_CK(ADC_LCLK1), .RSTb(main_resetB),
	.START_TDC(APV_CLOCK), .STOP_TDC(incoming_trigger),
	.ALL_CLEAR(AllClear), .TDC_SELECT(tdc_select),
	.TRIGGER_TIME_FIFO_RD(trigger_time_fifo_rd|trigger_time_fifo_rd_evb),  .TRIGGER_TIME_FIFO_CK(bus_clk),
	.TRIGGER_TIME_FIFO(trigger_time_fifo_data),
	.TRIGGER_TIME_FIFO_FULL(trigger_time_fifo_full), .TRIGGER_TIME_FIFO_EMPTY(trigger_time_fifo_empty));
*/

apv_synthetic_event_source_64 ApvGenerator(
    .CLK(clk156),
    .RST(~main_resetB),

    .RUN_ENABLE(synth_run_enable),
    .TRIG_PULSE(apv_trigger_pulse),

    .BOARD_ID({11'b0,module_id}),
    .N_APV(count1(ApvEnable)),
    .SAMPLES_PER_EVENT(SamplePerEvent),

    .TX_READY(tcp_tx_cts[1]),
    .TX_DATA(synth_tx_data),
    .TX_VALID(synth_tx_dv),

    .EVENT_COUNT(synth_event_count),
    .TRIGGER_COUNT(synth_trig_count),
    .MISSED_TRIGGER_COUNT(synth_missed_trig_count),
    .BEAT_COUNT(synth_beat_count),
    .WORD_COUNT(synth_word_count),
    .CHECKSUM_COUNT(synth_checksum_count)
);

ila_0 synth_checker(.clk(clk156),
	.probe0(synth_event_count),
	.probe1(synth_trig_count),
	.probe2(synth_missed_trig_count),
	.probe3(synth_beat_count),
	.probe4(synth_word_count),
	.probe5(synth_checksum_count));


assign tcp_tx_d[1] = synth_run_enable ? synth_tx_data : tcp_tx_d_evb;
assign tcp_tx_dv[1] = synth_run_enable ? synth_tx_dv : tcp_tx_dv_evb;



endmodule
