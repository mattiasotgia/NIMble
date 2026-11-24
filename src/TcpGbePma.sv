
module tcp_gbe_pma #(parameter NTCPSTREAMS = 3, parameter DHCP_EN = 0, parameter SIMULATION = 0)(
	input [31:0] IPv4_ADDR, input [31:0] SUBNET_MASK, input [31:0] GATEWAY_IP_ADDR,
	output [31:0] IPv4_ADDR_OUT,
	input [47:0] MAC_ADDR,
	input DYNAMIC_IP,
	input SYSCLK_200, input PMA_RESET, input STACK_RESET, output MMCM_LOCKED, output PMA_RESET_DONE,
	output GCLK_125_REF_RST, output GCLK_125_REF,
//	Fiber Transceiver Interface
	input FIBER_CLK_P, input FIBER_CLK_N,
	output FIBER_TX_P, output FIBER_TX_N, input FIBER_RX_P, input FIBER_RX_N,
	output FIBER_TX_DIS, output [15:0] FIBER_RX_ERR_CNT,
//	TCP interface ports
	output [0:NTCPSTREAMS-1] [7:0] TCP_RX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
//	output [NTCPSTREAMS-1:0] [7:0] TCP_RX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
	output [NTCPSTREAMS-1:0] TCP_RX_DATA_VALID,
	output [NTCPSTREAMS-1:0] TCP_RX_RTS,
	input [NTCPSTREAMS-1:0] TCP_RX_CTS,
	input [0:NTCPSTREAMS-1][7:0] TCP_TX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
//	input [NTCPSTREAMS-1:0][7:0] TCP_TX_DATA,	// This is System Verilog: VHDL array of std_logic_vector
	input [NTCPSTREAMS-1:0] TCP_TX_DATA_VALID,
	output [NTCPSTREAMS-1:0] TCP_TX_CTS,
	output [NTCPSTREAMS-1:0] TCP_CONNECTED
);
	
	wire userclk, async_reset, mmcm_locked_phy, pma_link_status;
	wire gmii_mii_tx_en, gmii_mii_tx_er, gmii_mii_rx_dv, gmii_mii_rx_er;
	wire [15:0] pma_status_vector;
	wire [7:0] gmii_mii_txd, gmii_mii_rxd;
	wire rx_err_cnt_ovf, rst_cnt_done, sync_reset, all_connected;
	wire [1:0] speed_status;
	wire [NTCPSTREAMS-1:0] connection_reset;
	wire LINK_STATUS, DUPLEX_STATUS;	// Unused

	reg [7:0] rst;
	reg [15:0] rx_err_cnt;
	reg pma_resetx;
	reg [22:0] rst_cnt;

	assign GCLK_125_REF = userclk;
	assign GCLK_125_REF_RST = async_reset | ~all_connected;
	assign FIBER_TX_DIS = 1'b0;
	assign FIBER_RX_ERR_CNT = rx_err_cnt;
	assign MMCM_LOCKED = mmcm_locked_phy;

	assign all_connected = |TCP_CONNECTED;
//	assign async_reset = ~mmcm_locked_phy;
	assign async_reset = ~mmcm_locked_phy | STACK_RESET;

	assign rst_cnt_done = (SIMULATION>0) ? rst_cnt[7] : rst_cnt[22];
	assign sync_reset = rst[7];
//	assign sync_reset = STACK_RESET;
	assign pma_link_status = pma_status_vector[0];
	
//	assign connection_reset[0] = 1'b0;	// BEN's hint
 	genvar i;
	generate
		for (i=0; i<NTCPSTREAMS; i++) begin
			assign connection_reset[i] = sync_reset;	// BUS_RESET_SOFT from BEN's code
		end
	endgenerate

	always @(posedge SYSCLK_200 or posedge PMA_RESET)
	begin
		if( PMA_RESET == 1'b1 )
		begin
			pma_resetx <= 1;
			rst_cnt <= 0;
		end
		else
		begin
			pma_resetx <= ~rst_cnt_done;

			if( rst_cnt_done == 1'b0 )
				rst_cnt <= rst_cnt + 1;
		end
	end

	always @(posedge userclk or posedge async_reset)
	begin
		if( async_reset == 1'b1 )
			rst <= 8'hFF;
		else
			rst <= {rst[6:0], 1'b0};
	end

	always @(posedge userclk)
	begin
		if( pma_status_vector[0] == 1'b0 )
			rx_err_cnt <= 0;
		else
			if( pma_status_vector[6] == 1'b1 && rx_err_cnt_ovf == 1'b0 )
				rx_err_cnt <= rx_err_cnt + 1; 
	end

	assign rx_err_cnt_ovf = (rx_err_cnt == 16'hFFFF) ? 1'b1 : 1'b0;


	gig_ethernet_pcs_pma_1 gig_ethernet_pcs_pma_inst(
//	Transceiver Interface      
		.gtrefclk_p(FIBER_CLK_P),	// in  std_logic;                          
		.gtrefclk_n(FIBER_CLK_N),	// in  std_logic;                         

		.gtrefclk_out(),		// out std_logic; -- Very high quality clock for GT transceiver
		.gtrefclk_bufg_out(),		// out std_logic;                           

		.txp(FIBER_TX_P),		// out std_logic; -- Differential +ve of serial transmission from PMA to PMD
		.txn(FIBER_TX_N),		// out std_logic; -- Differential -ve of serial transmission from PMA to PMD
		.rxp(FIBER_RX_P),		// in std_logic;  -- Differential +ve for serial reception from PMD to PMA
		.rxn(FIBER_RX_N),		// in std_logic;  -- Differential -ve for serial reception from PMD to PMA
		.resetdone(PMA_RESET_DONE),	// out std_logic; -- The GT transceiver has completed its reset cycle
		.userclk_out(),			// out std_logic;                           
		.userclk2_out(userclk),  	// out std_logic;                           
		.rxuserclk_out(),		// out std_logic;                         
		.rxuserclk2_out(),		// out std_logic;                         
		.pma_reset_out(),		// out std_logic; -- transceiver PMA reset signal
		.mmcm_locked_out(mmcm_locked_phy),	// out std_logic; -- MMCM Locked
		.independent_clock_bufg(SYSCLK_200),	// in std_logic;                   
      
//	GMII Interface
		.gmii_txd(gmii_mii_txd),	// in std_logic_vector(7 downto 0);  -- Transmit data from client MAC
		.gmii_tx_en(gmii_mii_tx_en),	// in std_logic;                     -- Transmit control signal from client MAC
		.gmii_tx_er(gmii_mii_tx_er),	// in std_logic;                     -- Transmit control signal from client MAC
		.gmii_rxd(gmii_mii_rxd),	// out std_logic_vector(7 downto 0); -- Received Data to client MAC
		.gmii_rx_dv(gmii_mii_rx_dv),	// out std_logic;                    -- Received control signal to client MAC
		.gmii_rx_er(gmii_mii_rx_er),	// out std_logic;                    -- Received control signal to client MAC
		.gmii_isolate(),		// out std_logic;                    -- 3-state control to electrically isolate GMII
      
//	Management: Alternative to MDIO Interface
      
		.configuration_vector(5'b10000),// in std_logic_vector(4 downto 0);  -- Alternative to MDIO interface.
      
      
		.an_interrupt(),		// out std_logic; -- Irq to processor to signal that Auto-Negotiation has completed
		.an_adv_config_vector(16'h0020),// in std_logic_vector(15 downto 0); -- Alternate interface to program REG4 (AN ADV)
		.an_restart_config(1'b0),	// in std_logic;                     -- Alternate signal to modify AN restart bit in REG0
      
//	General IO's
		.status_vector(pma_status_vector),// out std_logic_vector(15 downto 0); -- Core status.
		.reset(pma_resetx),		// in std_logic;           -- Asynchronous reset for entire core.
//		.reset(PMA_RESET),		// in std_logic;           -- Asynchronous reset for entire core.
      
		.signal_detect(1'b1),		// -- Input from PMD to indicate presence of optical input; can be ~SFP_RX_LOS
		.gt0_qplloutrefclk_out(),
		.gt0_qplloutclk_out()
    );

	com5402tcpstack_5401mac #(
		.NTCPSTREAMS(NTCPSTREAMS),
		.DHCP_EN(DHCP_EN),
		.SIMULATION(SIMULATION))
    com5402tcpstack_5401mac_inst(
		.CLK(userclk),
		.SYNC_RESET(sync_reset),
		.IPv4_ADDR(IPv4_ADDR),
		.IPv4_ADDR_OUT(IPv4_ADDR_OUT),
		.SUBNET_MASK(SUBNET_MASK),
		.GATEWAY_IP_ADDR(GATEWAY_IP_ADDR),
		.MAC_ADDR(MAC_ADDR),
		.DYNAMIC_IP(DYNAMIC_IP),
		.LINK_STATUS(LINK_STATUS),
		.SPEED_STATUS(speed_status),
		.DUPLEX_STATUS(DUPLEX_STATUS),
		.CONNECTION_RESET(connection_reset),	// TO BE BETTER SEEN
		.TCP_RX_DATA(TCP_RX_DATA),	// This is System Verilog: VHDL array of std_logic_vector
		.TCP_RX_DATA_VALID(TCP_RX_DATA_VALID),
		.TCP_RX_RTS(TCP_RX_RTS),
		.TCP_RX_CTS(TCP_RX_CTS),
		.TCP_TX_DATA(TCP_TX_DATA),	// This is System Verilog: VHDL array of std_logic_vector
		.TCP_TX_DATA_VALID(TCP_TX_DATA_VALID),
		.TCP_TX_CTS(TCP_TX_CTS),
		.TCP_CONNECTED(TCP_CONNECTED),
		.MII_TX_CLK(userclk),
		.GMII_TX_CLK(),
		.GMII_MII_TXD(gmii_mii_txd),
		.GMII_MII_TX_EN(gmii_mii_tx_en),
		.GMII_MII_TX_ER(gmii_mii_tx_er),
		.GMII_MII_CRS(1'b0),
		.GMII_MII_COL(1'b0),
		.GMII_MII_RX_CLK(userclk),
		.GMII_MII_RXD(gmii_mii_rxd),
		.GMII_MII_RX_DV(gmii_mii_rx_dv),
		.GMII_MII_RX_ER(gmii_mii_rx_er),
		.GMII_MII_LINK_STATUS(pma_status_vector[0])
	);

endmodule
