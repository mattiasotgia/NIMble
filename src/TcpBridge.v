/* Translate packetized data to a simple synchronous parallel bus.
 *
 * Packet format
 * uint32 TYPE_SIZE
 * uint32 ADDR0
 * uint32 DATA[]
 *
 * TYPE_SIZE fields:
 * [31:24] MAGIC_WORD (0xFA)
 * [23:16] Type of transfer
 *			bit [23:20]: taken out to AM wires
 *			bit 19: 1 = ack_on_write, not used on received packets
 *			bit 18: 1 = request ACK on write
 *			bit 17: 1 = Address autoincrement
 *			bit 16: 0 = Write, 1 = Read
 * [15:0]  Size of transfer (in 32 bit words)
 *
 * Write operations can send back a packet (0 data) if ACK is requested
 * Read operations always send back a packet with the same format
 *
 * On the user side the interface will provide a standard non muxed bus as following:
 *           _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _   _
 * BUS_CLK _| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_| |_
 *          ____ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ 
 * A[31:0]  ____X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___
 *          ____ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ ___ 
 * AM[3:0]  ____X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___X___
 *                   ___         ___ ___
 * DW[31:0] ----X---X___X---X---X___X___X---X---X---X---X---X---X---X---X---X---X---X---X---
 *                                                ___         ___ ___
 * DR[31:0] -----X---X---X---X---X---X---X---X---X___X---X---X___X___X---X---X---X---X---X---
 *                   ___         _______
 * WE       ________|   |_______|       |___________________________________________________
 *                                               ___         _______
 * RE       ____________________________________|   |_______|       |_______________________
 *
 * The above diagram show that WE and RE pulse are always 1 CLK cycle wide.
 * Async device can write with the falling edge of WE, sync device can use
 * the rising edge of CLK at the end of WE.
 * RE pulses can be used to extract data from sync (with CLK) or async devices.
 *
 * Wavedrom description https://wavedrom.com/editor.html
{ signal: [
  { name: "CLOCK", wave: 'P.................', period: 1 },
  ['Addr',
  { name: "ADDR", wave: 'x.=x.==x..=x.==x..', data: ["Valid", "Valid", "Valid", "Valid", "Valid", "Valid"]  },
  { name: "AM", wave: 'x.=x.=.x..=x.=.x..', data: ["Valid", "Valid", "Valid", "Valid"]  },
  ],
  ['Write',
  { name: "WE", wave: '0.10.1.0..........' },
  { name: "DW", wave: 'x.7x.77x..........' },
  ],
  ['Read',
  { name: "RE", wave: '0.........10.1.0..' },
  { name: "DR", wave: 'x.........4x.44x..', phase: -0.25 },
  ]
],
head: {text:
  ['tspan',
    ['tspan', {class:'success h3'}, 'Tcp data stream to user        '],
    ['tspan', {class:'warning h3'}, 'User data to tcp data stream']
   ]
}
}
 *
 */
module TcpBridge (
//	TCP interface ports
	input TCP_CLK,

	input [7:0] TCP_RX_DATA,
	input TCP_RX_DATA_VALID,
	input TCP_RX_RTS,
	output TCP_RX_CTS,
	output [7:0] TCP_TX_DATA,
	output TCP_TX_DATA_VALID,
	input TCP_TX_CTS,
	input TCP_CONNECTED,
	output TCP_ERROR,
//	USER interface ports
	input BUS_CLK,
	input BUS_RESET,

	output BUS_WE,
	output [31:0] BUS_ADDR,
	output [3:0] BUS_AM,
	output [31:0] BUS_DW,

	output BUS_RE,
	input [31:0] BUS_DR
);


	(* mark_debug = "true" *) wire rst_fifo, wr_en_tx, rd_en_tx, prog_full_tx, empty_tx, rd_en_rx, prog_full_rx, empty_rx, rd_en_rx_fsm;
	(* mark_debug = "true" *) reg tcp_connected_q, bus_reset_q;
	(* mark_debug = "true" *) wire [31:0] din_tx, dout_rx;

	assign rst_fifo = ~tcp_connected_q;
	assign TCP_RX_CTS = ~prog_full_rx;
	assign TCP_TX_DATA_VALID = rd_en_tx;
	assign rd_en_tx = TCP_TX_CTS & ~empty_tx;
	assign rd_en_rx = rd_en_rx_fsm & ~empty_rx;

	always @(posedge BUS_CLK)
	begin
		tcp_connected_q <= TCP_CONNECTED;
		bus_reset_q <= BUS_RESET;
	end


	fifo_1024wr8b_rd32b fifo_1024wr8b_rd32b_inst(
		.rst(rst_fifo),
		.wr_clk(TCP_CLK),
		.rd_clk(BUS_CLK),
		.din(TCP_RX_DATA),
		.wr_en(TCP_RX_DATA_VALID),
		.rd_en(rd_en_rx),
//		.prog_full_thresh(10'b11_0000_0000),
		.dout({dout_rx[7:0], dout_rx[15:8], dout_rx[23:16], dout_rx[31:24]}),
		.full(),
		.empty(empty_rx),
		.prog_full(prog_full_rx)	// Active at 768
	);

	fifo_256wr32b_rd8b fifo_256wr32b_rd8b_inst(
		.rst(rst_fifo),
		.wr_clk(BUS_CLK),
		.rd_clk(TCP_CLK),
		.din({din_tx[7:0], din_tx[15:8], din_tx[23:16], din_tx[31:24]}),
		.wr_en(wr_en_tx),
		.rd_en(rd_en_tx),
//		.prog_full_thresh(8'b11000000),
		.dout(TCP_TX_DATA),
		.full(),
		.empty(empty_tx),
		.prog_full(prog_full_tx)	// active at 192
	);

	tcpbridge_sm tcpbridge_sm_inst(
		.BUS_CLK(BUS_CLK),

		.BUS_RESET(bus_reset_q),
		.BUS_WE(BUS_WE),
		.BUS_ADDR(BUS_ADDR),
		.BUS_AM(BUS_AM),
		.BUS_DW(BUS_DW),
		.BUS_RE(BUS_RE),
		.BUS_DR(BUS_DR),
		.TCP_CONNECTED(tcp_connected_q),
		.TCP_ERROR(TCP_ERROR),
		.PROG_FULL_TX(prog_full_tx),
		.DOUT_RX(dout_rx),
		.EMPTY_RX(empty_rx),
		.WR_EN_TX(wr_en_tx),
		.RD_EN_RX(rd_en_rx_fsm),
		.DIN_TX(din_tx)
	);

endmodule


module tcpbridge_sm (
	input BUS_CLK,
	input BUS_RESET,
    output reg BUS_WE,
    output reg [31:0] BUS_ADDR,
    output reg [3:0] BUS_AM,
	output reg [31:0] BUS_DW,
	output reg BUS_RE,
	input [31:0] BUS_DR,

	input TCP_CONNECTED,
	output reg TCP_ERROR,
// FIFO control
	input PROG_FULL_TX,
	input [31:0] DOUT_RX,		// incoming TCP payload
	input EMPTY_RX,
	output reg WR_EN_TX,
	output reg RD_EN_RX, 
	output reg [31:0] DIN_TX	// outgoing TCP payload
	);

	parameter ST_INIT = 8'd0;		// FSM Status
	parameter ST_RECV_HDR = 8'd1;
	parameter ST_GET_ADDR = 8'd2;
	parameter ST_WRITE = 8'd3;
	parameter ST_ACK_ON_WRITE = 8'd4;
	parameter ST_ACK_ON_WRITE2 = 8'd5;
	parameter ST_ACK_ON_WRITE3 = 8'd6;
	parameter ST_READ = 8'd7;
	parameter ST_READ_DATA = 8'd8;
	parameter ST_READ_DATA2 = 8'd9;
	parameter ST_WRITE_WAIT = 8'd10;
	parameter ST_TCP_ERROR = 8'd11;
	
	parameter MAGIC_WORD = 8'hFA;

	wire state_chg, write_ack_timeout, read_ack_timeout;
	reg [7:0] tcp_proc_state_cnt;
	(* mark_debug = "true" *) reg [7:0] tcp_proc_state, tcp_proc_state_next;
	reg dir, ack_on_write, autoinc;
	(* mark_debug = "true" *) reg [15:0] size;
	(* mark_debug = "true" *) reg [1:0] dintx_select;
	(* mark_debug = "true" *) reg [31:0] dintx_internal;

	assign state_chg = (tcp_proc_state != tcp_proc_state_next) ? 1 : 0;

	assign write_ack_timeout = (tcp_proc_state_cnt == 8'd128) ? 1 : 0;
	assign read_ack_timeout  = (tcp_proc_state_cnt == 8'd128) ? 1 : 0;

	always @(posedge BUS_CLK)

	begin
		if( state_chg == 1 )
			tcp_proc_state_cnt <= 0;
		else
			tcp_proc_state_cnt <= tcp_proc_state_cnt + 1;
	end


	always @(posedge BUS_CLK)	// state change register
	begin
		tcp_proc_state <= tcp_proc_state_next;
	end

	always @(*)
	begin
		case(dintx_select)
			0: DIN_TX <= {MAGIC_WORD, BUS_AM, 1'b1, autoinc, ack_on_write, dir, size};
			1: DIN_TX <= BUS_ADDR;
			2: DIN_TX <= BUS_DR;
			3: DIN_TX <= dintx_internal;	// used for ack_on_write
		endcase
	end
	
	always @(posedge BUS_CLK )	// state machine (sync reset)
	begin
		if( BUS_RESET == 1 || TCP_CONNECTED == 0 )
		begin
			tcp_proc_state_next <= ST_INIT;
			TCP_ERROR <= 0;
			WR_EN_TX <= 0;
			RD_EN_RX <= 0;
//			DIN_TX <= 32'h00000000;
			BUS_WE <= 0;
			BUS_RE <= 0;
			BUS_ADDR <= 32'h00000000;
			BUS_AM <= 4'h0;
			BUS_DW <= 32'h00000000;
			dir <= 0;
			ack_on_write <= 0;
			size <= 16'h0000;
			autoinc <= 0;
			dintx_select <= 0;
			dintx_internal <= 32'h00000000;
		end
		else
		begin
			case( tcp_proc_state_next )
				ST_INIT: begin
					TCP_ERROR <= 0;
					WR_EN_TX <= 0;
					RD_EN_RX <= 0;
					BUS_WE <= 0;
					BUS_RE <= 0;
					dintx_select <= 0;
//					DIN_TX <= 32'h00000000;
//					BUS_ADDR <= 32'h00000000;
//					BUS_AM <= 4'h0;
//					BUS_DW <= 32'h00000000;
//					dir <= 0;
//					ack_on_write <= 0;
//					size <= 16'h0000;
//					autoinc <= 0;

					if( EMPTY_RX == 0 )
					begin
						RD_EN_RX <= 1;
						tcp_proc_state_next <= ST_RECV_HDR;
					end
				end
				

				ST_RECV_HDR: begin
					if( EMPTY_RX == 0 )
					begin
						RD_EN_RX <= 1;
						if( DOUT_RX[31:24] == MAGIC_WORD )
						begin
							size <= DOUT_RX[15:0];
							dir <= DOUT_RX[16];
							autoinc <= DOUT_RX[17];
							ack_on_write <= DOUT_RX[18];
							BUS_AM <= DOUT_RX[23:20];
							tcp_proc_state_next <= ST_GET_ADDR;
						end
						else
//							RD_EN_RX <= 0;
							tcp_proc_state_next <= ST_TCP_ERROR;
					end
				end

				ST_GET_ADDR: begin
					if( EMPTY_RX == 0 )
					begin
						BUS_ADDR <= (autoinc == 0) ? DOUT_RX : DOUT_RX-1;
						if( size > 0 && dir == 0 )	// Write some data
						begin
							RD_EN_RX <= 1;
							tcp_proc_state_next <= ST_WRITE;
						end
						if( size > 0 && dir == 1 )	// Read some data
						begin
							RD_EN_RX <= 1;	// was 0
							tcp_proc_state_next <= ST_READ;
						end
						if( size == 0 )
						begin
							RD_EN_RX <= 0;
							tcp_proc_state_next <= ST_INIT;
						end
					end
				end

				ST_WRITE: begin
					BUS_DW <= DOUT_RX;
					if( EMPTY_RX == 0 )
					begin
						RD_EN_RX <= (size > 1) ? 1 : 0;	// was size > 0
						BUS_WE <= (size > 0) ? 1 : 0;
						if( autoinc == 1 )
							BUS_ADDR <= BUS_ADDR + 1;
						if( size == 0 )
						begin
							RD_EN_RX <= 0;
							BUS_WE <= 0;
							if( ack_on_write == 1 )
							begin
								dintx_select <= 3;
								tcp_proc_state_next <= ST_ACK_ON_WRITE;
							end
							else
								tcp_proc_state_next <= ST_INIT;
						end
						else
							size <= size - 1;
					end
					else
					begin
						RD_EN_RX <= 0;
						BUS_WE <= 0;
						if( size == 0 )
							tcp_proc_state_next <= ST_INIT;

						else
							tcp_proc_state_next <= ST_WRITE_WAIT;
					end
				end

				ST_WRITE_WAIT: begin
					BUS_DW <= DOUT_RX;
					if( EMPTY_RX == 0 )
						RD_EN_RX <= 1;
					tcp_proc_state_next <= ST_WRITE;
				end

				ST_ACK_ON_WRITE: begin
					if( PROG_FULL_TX == 0 )
					begin
						dintx_internal <= {MAGIC_WORD, BUS_AM, 1'b1, autoinc, ack_on_write, dir, 16'h0000};
						WR_EN_TX <= 1;
						tcp_proc_state_next <= ST_ACK_ON_WRITE2;
					end
					else
						WR_EN_TX <= 0;
				end

				ST_ACK_ON_WRITE2: begin
					if( PROG_FULL_TX == 0 )
					begin
						dintx_internal <= BUS_ADDR;
						WR_EN_TX <= 1;
						tcp_proc_state_next <= ST_ACK_ON_WRITE3;
					end
					else
						WR_EN_TX <= 0;
				end

				ST_ACK_ON_WRITE3: begin
					WR_EN_TX <= 0;
					tcp_proc_state_next <= ST_INIT;
				end

				ST_READ: begin
					RD_EN_RX <= 0;
//					dintx_select <= 1;
					if( PROG_FULL_TX == 0 )
					begin
//						DIN_TX <= {MAGIC_WORD, BUS_AM, 1'b1, autoinc, ack_on_write, dir, size};
						WR_EN_TX <= 1;
						tcp_proc_state_next <= ST_READ_DATA;
					end
					else
						WR_EN_TX <= 0;
				end

				ST_READ_DATA: begin
					dintx_select <= 1;
					if( PROG_FULL_TX == 0 )
					begin
//						DIN_TX <= BUS_ADDR;
						WR_EN_TX <= 1;
						tcp_proc_state_next <= ST_READ_DATA2;
					end
					else
						WR_EN_TX <= 0;
				end

				ST_READ_DATA2: begin
					dintx_select <= 2;
					if( PROG_FULL_TX == 0 )
					begin
//						DIN_TX <= BUS_DR;
						WR_EN_TX <= (size > 0) ? 1 : 0;

						BUS_RE <= (size > 0) ? 1 : 0;
						if( autoinc )
							BUS_ADDR <= BUS_ADDR + 1;
						if( size == 0 )
						begin
							WR_EN_TX <= 0;
							BUS_RE <= 0;
							tcp_proc_state_next <= ST_INIT;
						end
						else
						begin
							size <= size - 1;
						end
					end
					else
					begin
						WR_EN_TX <= 0;
						BUS_RE <= 0;
						if( size == 0 )
							tcp_proc_state_next <= ST_INIT;
//						tcp_proc_state_next <= ST_INIT;	// ???
					end
				end

				ST_TCP_ERROR: begin
					RD_EN_RX <= 0;
					TCP_ERROR <= 1;
					tcp_proc_state_next <= ST_INIT;
				end
				
				default: tcp_proc_state_next <= ST_INIT;
			endcase
		end
	end

endmodule

