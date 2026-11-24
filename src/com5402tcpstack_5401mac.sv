
module com5402tcpstack_5401mac #(parameter NTCPSTREAMS = 3, parameter DHCP_EN = 0, parameter SIMULATION = 0)(
		input CLK,
		input SYNC_RESET,

		input [31:0] IPv4_ADDR,
		input [31:0] SUBNET_MASK,
		input [31:0] GATEWAY_IP_ADDR,
		input [47:0] MAC_ADDR,
		input DYNAMIC_IP,
		
		output [31:0] IPv4_ADDR_OUT,
		output LINK_STATUS,
		output [1:0] SPEED_STATUS,
		output DUPLEX_STATUS,
		
		input [NTCPSTREAMS-1:0] CONNECTION_RESET,

//	TCP Interface

		output [0:NTCPSTREAMS-1][7:0] TCP_RX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
//		output [NTCPSTREAMS-1:0][7:0] TCP_RX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
		output [NTCPSTREAMS-1:0] TCP_RX_DATA_VALID,
		output [NTCPSTREAMS-1:0] TCP_RX_RTS,
		input [NTCPSTREAMS-1:0] TCP_RX_CTS,
		
		input [0:NTCPSTREAMS-1][7:0] TCP_TX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
//		input [NTCPSTREAMS-1:0][7:0] TCP_TX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
		input [NTCPSTREAMS-1:0] TCP_TX_DATA_VALID,
		output [NTCPSTREAMS-1:0] TCP_TX_CTS,	
		output [NTCPSTREAMS-1:0] TCP_CONNECTED,

//	GMII interface (internal)
		input MII_TX_CLK,
		output GMII_TX_CLK,
		output [7:0] GMII_MII_TXD,
		output GMII_MII_TX_EN,
		output GMII_MII_TX_ER,
		input GMII_MII_CRS,
		input GMII_MII_COL,
		input GMII_MII_RX_CLK,
		input [7:0] GMII_MII_RXD,
		input GMII_MII_RX_DV,
		input GMII_MII_RX_ER,
		input GMII_MII_LINK_STATUS

	);
	
	wire [7:0] MAC_TX_DATA, MAC_RX_DATA;
	wire MAC_TX_DATA_VALID, MAC_TX_SOF, MAC_TX_EOF, MAC_TX_CTS;
	wire MAC_RX_DATA_VALID, MAC_RX_SOF, MAC_RX_EOF;
	wire [127:0] tcp_keep_alive;
	
	assign tcp_keep_alive = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;

	com5402 #(
`ifdef QUESTA
			.DHCP_CLIENT_EN(DHCP_EN ? 2'b11 : 2'b10),
`else
			.DHCP_CLIENT_EN(DHCP_EN ? 1'b1 : 1'b0),	// To be checked
`endif
			.NUDPTX(0),
			.NUDPRX(0),
			.NTCPSTREAMS(NTCPSTREAMS),
			.CLK_FREQUENCY(125),
`ifdef QUESTA
			.SIMULATION(SIMULATION),
			.TX_IDLE_TIMEOUT(1))	// SIMULATION ? 1 : 50
`else
			.TX_IDLE_TIMEOUT(50))
`endif
		com5402_inst (
		
			.CLK(CLK),
			.SYNC_RESET(SYNC_RESET),
			.MAC_ADDR(MAC_ADDR),
			.DYNAMIC_IP(DYNAMIC_IP),
			.IPv4_ADDR_REQ(DYNAMIC_IP ? 32'b0 : IPv4_ADDR),
			.DHCPC_IPv4_ADDR_out(IPv4_ADDR_OUT),
			.IPv6_ADDR(128'h0000_0000_0000_0000_0000_0000_0000_0000),
			.MULTICAST_IP_ADDR(32'h0000_0000),
			.SUBNET_MASK(SUBNET_MASK),
			.GATEWAY_IP_ADDR(GATEWAY_IP_ADDR),
			.CONNECTION_RESET(CONNECTION_RESET),
			.TCP_KEEPALIVE_EN(tcp_keep_alive[NTCPSTREAMS-1:0]),
			.MAC_TX_DATA(MAC_TX_DATA),
			.MAC_TX_DATA_VALID(MAC_TX_DATA_VALID),
			.MAC_TX_SOF(MAC_TX_SOF),
			.MAC_TX_EOF(MAC_TX_EOF),
			.MAC_TX_CTS(MAC_TX_CTS),
			.MAC_TX_RTS(),
			.MAC_RX_DATA(MAC_RX_DATA),
			.MAC_RX_DATA_VALID(MAC_RX_DATA_VALID),
			.MAC_RX_SOF(MAC_RX_SOF),
			.MAC_RX_EOF(MAC_RX_EOF),
			.UDP_RX_DATA(),
			.UDP_RX_DATA_VALID(),
			.UDP_RX_SOF(),
			.UDP_RX_EOF(),
			.UDP_RX_DEST_PORT_NO_IN(16'h0000),
			.CHECK_UDP_RX_DEST_PORT_NO(1'b0),
			.UDP_RX_DEST_PORT_NO_OUT(),
			.UDP_TX_DATA(8'h00),
			.UDP_TX_DATA_VALID(1'b0),
			.UDP_TX_SOF(1'b0),
			.UDP_TX_EOF(1'b0),
			.UDP_TX_CTS(),
			.UDP_TX_ACK(),
			.UDP_TX_NAK(),
			.UDP_TX_DEST_IP_ADDR(128'h0000_0000_0000_0000_0000_0000_0000_0000),
			.UDP_TX_DEST_PORT_NO(16'h0000),
			.UDP_TX_SOURCE_PORT_NO(16'h0000),
			.TCP_RX_DATA(TCP_RX_DATA),	// This is System Verilog: VHDL array of std_logic_vector
			.TCP_RX_DATA_VALID(TCP_RX_DATA_VALID),
			.TCP_RX_RTS(TCP_RX_RTS),
			.TCP_RX_CTS(TCP_RX_CTS),
			.TCP_TX_DATA(TCP_TX_DATA),	// This is System Verilog: VHDL array of std_logic_vector
			.TCP_TX_DATA_VALID(TCP_TX_DATA_VALID),
			.TCP_TX_CTS(TCP_TX_CTS),
			.TCP_CONNECTED_FLAG(TCP_CONNECTED),
			.CS1(),
			.CS1_CLK(),
			.CS2(),
			.CS2_CLK(),
			.TP()
		);

	com5401 #(
			.MII_SEL(2),
			.PHY_ADDR(5'b00100),
			.CLK_FREQUENCY(125),
			.PLATFORM(0),
`ifdef QUESTA
			.SIMULATION(SIMULATION),
`endif
			.TARGET_PHY(0))
		com5401_inst(
			.CLK(CLK),
			.SYNC_RESET(SYNC_RESET),
			.CLK125_0(1'b0),
			.CLK125_1(1'b0),
			.CLK25(1'b0),
			.MAC_TX_CONFIG(16'h0003),
			.MAC_RX_CONFIG(16'h0006),
			.MAC_ADDR(MAC_ADDR),
			.PHY_CONFIG_CHANGE(1'b0),
			.PHY_RESET(1'b0),
			.SPEED(2'b11),
			.DUPLEX(1'b1),
			.TEST_MODE(2'b00),
			.POWER_DOWN(1'b0),
			.CLK_SKEW1(16'h7777),
			.CLK_SKEW2(16'h7777),
			.MAC_TX_DATA(MAC_TX_DATA),
			.MAC_TX_DATA_VALID(MAC_TX_DATA_VALID),
			.MAC_TX_EOF(MAC_TX_EOF),
			.MAC_TX_CTS(MAC_TX_CTS),
			.MAC_RX_DATA(MAC_RX_DATA),
			.MAC_RX_DATA_VALID(MAC_RX_DATA_VALID),
			.MAC_RX_SOF(MAC_RX_SOF),
			.MAC_RX_EOF(MAC_RX_EOF),
			.MAC_RX_CTS(1'b1),
			.TXC(),
			.TXD(),
			.TX_CTL(),
			.RXC(1'b0),
			.RXD(4'b0000),
			.RX_CTL(1'b0),
			.RESET_N(),
			.MCLK(),
			.MDIO(),
			.MII_TX_CLK(MII_TX_CLK),
			.GMII_TX_CLK(GMII_TX_CLK),
			.GMII_MII_TXD(GMII_MII_TXD),
			.GMII_MII_TX_EN(GMII_MII_TX_EN),
			.GMII_MII_TX_ER(GMII_MII_TX_ER),
			.GMII_MII_CRS(GMII_MII_CRS),
			.GMII_MII_COL(GMII_MII_COL),
			.GMII_MII_RX_CLK(GMII_MII_RX_CLK),
			.GMII_MII_RXD(GMII_MII_RXD),
			.GMII_MII_RX_DV(GMII_MII_RX_DV),
			.GMII_MII_RX_ER(GMII_MII_RX_ER),
			.GMII_MII_LINK_STATUS(GMII_MII_LINK_STATUS),
			.SPEED_STATUS(SPEED_STATUS),
			.LINK_STATUS(LINK_STATUS),
			.DUPLEX_STATUS(DUPLEX_STATUS),
			.PHY_ID(),
			.N_RX_FRAMES(),
			.N_RX_BAD_CRCS(),
			.N_RX_FRAMES_TOO_SHORT(),
			.N_RX_FRAMES_TOO_LONG(),
			.N_RX_WRONG_ADDR(),
			.N_RX_LENGTH_ERRORS(),
			.CS_CLKG(),
			.CS1(),
			.CS1_CLK(),
			.CS2(),
			.CS2_CLK(),
			.CT1(),
			.CT1_CLK(),
			.TP()
		);


endmodule
