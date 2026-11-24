-------------------------------------------------------------
-- MSS copyright 2010-2012
--	Filename:  RGMII_WRAPPER_V5.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 3
--	Date last modified: 2/28/12
-- Inheritance: 	RGMII_WRAPPER.VHD, rev 3 11/20/11
--
-- description:  Wrapper between the MAC and the PHY (RGMII interface) 
-- Complies with RGMII Version 2.0 4/1/2002
-- Virtex5 version
--
-- Rev 2 2/28/12 AZ
-- Corrected bug: IDDR, ODDR primitives
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity RGMII_WRAPPER_V5 is
	generic (
		CLK_FREQUENCY: integer
			-- CLK frequency in MHz. Needed to compute actual delays.
			-- unused in baseline code. Alternative code for detecting speed.
	);
    Port ( 
		--// CLK, RESET
		CLK: in std_logic;
			-- USER-side GLOBAL CLOCK (used as time-reference only)
			-- unused in baseline code. Alternative code for detecting speed.
		IDELAYREFCLK200MHZ: in std_logic;
			-- 190-210 MHz clock required for implementing IO delay(s).
		SYNC_RESET: in std_logic;
			-- block the RGMII output signals to the PHY during the PHY reset.
			-- minimum width 50ns for Virtex 5 (IDELAYCTRL contraint)
			-- MANDATORY at power up.
		
		--// PHY RGMII Interface
		-- Connect directly to FPGA pins
		TXC: out std_logic;  -- tx clock
			-- transmit reference is 125MHz, 25 MHz, or 2.5 MHz +/- 50ppm depending on speed
			-- Delayed by 2ns to prevent glitches when the PHY is reading.
		TXD: out std_logic_vector(3 downto 0);  
			-- tx data. bits 3:0 sent at the rising edge of TXC, bits 7:4 at the falling edge of TXC.
		TX_CTL: out std_logic;  
			-- tx control contains TX_EN on the rising edge of TXC and a logical derivative of
			-- TX_EN and TX_ERR on the falling edge of TXC.
		
		RXC: in std_logic;  
			-- continuous receive reference clock recovered by the PHY from the received signal
			-- 125/25/2.5 MHz +/- 50 ppm. 
			-- must be delayed by 1.5 to 2.1 ns to prevent glitches
		RXD: in std_logic_vector(3 downto 0);  
			-- rx data. bits 3:0 read at the rising edge of RXC, bits 7:4 at the falling edge of RXC.
		RX_CTL: in std_logic;  
			-- receive control. RX_DV on the rising edge of RXC and a logical derivative of
			-- RX_DV and RX_ERR on the falling edge of RXC.
			-- Note: Micrel KSZ9021RN PHY defines these as dual-function signals.
			-- Set the strapping options in the .ucf constraint file.
		
		--// MAC Interface
		-- receive signals are synchronous with the RXCG_OUT clock recovered by the PHY
		MAC_RXD: out std_logic_vector(7 downto 0);
			-- 8-bit of data (any speed, byte is reconstructed from 4-bit nibbles within)
		MAC_RX_DV: out std_logic;
		MAC_RX_ER: out std_logic;
		MAC_RX_SAMPLE_CLK: out std_logic;
		RXCG_OUT: out std_logic;
			-- received clock (global buf)
		
		-- transmit signals are synchronous with the rising edge of the 125 MHz CLK 
		MAC_TXD: in std_logic_vector(7 downto 0);
			-- 8-bit of data (any speed, byte is split into two 4-bit nibbles within)
			-- LSb is sent first. 
		MAC_TX_EN: in std_logic;
			-- The MAC is responsible for holding the tx enable low until it has verified that it
			-- operates at the same speed as the PHY (as reported in the SPEED_STATUS)
		MAC_TX_ER: in std_logic;
			-- use (TX_EN,TX_ER) as follows:
			-- 0,0  = transmit complete
			-- 0,1 and TX_D = 0x0F = carrier extend
			-- 0,1 and TX_D = 0x1F = carrier extend error
			-- 1,0 = normal transmission
			-- 1,1 = transmit error
		MAC_TX_SAMPLE_CLK: in std_logic;
			-- 1-CLK wide pulse. 
			-- read the above MAC_TX? signals at the rising edge of CLK when MAC_TX_SAMPLE_CLK = '1'.
			-- MAC_TX_SAMPLE_CLK conveys the transmit speed information. 
			-- Always '1' when the transmit speed is set at 1000 Mbps  
			-- 1-CLK pulse once every (exactly) 2 CLKs when the transmit speed is set at 100 Mbps = 12.5 MHz
			-- 1-CLK pulse once every (exactly) 2 CLKs when the transmit speed is set at 10 Mbps = 1.25 MHz
			
			
		--// controls
		TX_SPEED: in std_logic_vector(1 downto 0);
			-- 00/01/10  for 10/100/1000 Mbps transmit speed
		
		
		--// PHY status
		-- synchronous with RXCG global clock
		-- required in-band status
		CRS: out std_logic;  -- carrier sense
		COL: out std_logic;  -- collision detection
		
		-- optional in-band status (must be enabled at PHY)
		LINK_STATUS: out std_logic;  -- 0 = link down, 1 = link up
		SPEED_STATUS: out std_logic_vector(1 downto 0);
			-- RXC clock speed, 00 = 2.5 MHz, 01 = 25 MHz, 10 = 125 MHz, 11 = reserved
		DUPLEX_STATUS: out std_logic;
			-- 0 = half duplex, 1 = full duplex
			
		--// test points
		TP: out std_logic_vector(10 downto 1)
		
 );
end entity;

architecture Behavioral of RGMII_WRAPPER_V5 is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
-- suffix _E denotes one CLK early
-- suffix _D denotes a one CLK delay.. etc

-- rx and tx clocks will likely need timing adjustments, depending on the hardware.
-- Plan A is to use the control register 260 in the PHY (see PHY configuration)
-- Plan B is to use an IODELAY2 function here.
--constant RXC_DELAY: integer range 0 to 255 := 0;  -- adjust as needed.
constant TXC_DELAY: integer range 0 to 255 := 32;  -- adjust as needed.

--// RXC clock frequency detection
--signal RX_COUNTER1: std_logic_vector(7 downto 0) := (others => '0');
--signal RX_COUNTER: std_logic_vector(8 downto 0) := (others => '0');
--signal CMSB: std_logic := '0';
--signal CMSB_D: std_logic := '0';

signal RXCB: std_logic := '0';
--signal RXC2: std_logic := '0';
signal RGMII_EN: std_logic := '0';
signal RXC_DELAYED: std_logic := '0';
signal RXCG: std_logic := '0';	-- global clock, delayed 2ns w.r.t. received RXC.
signal RXD_DR_E: std_logic_vector(3 downto 0) := (others => '0');
signal RXD_DR: std_logic_vector(3 downto 0) := (others => '0');
signal RXD_DR_D: std_logic_vector(3 downto 0) := (others => '0');
signal RXD_DF: std_logic_vector(3 downto 0) := (others => '0');
signal MAC_RXD_LOCAL: std_logic_vector(7 downto 0) := (others => '0');
signal RX_CTL_DR_E: std_logic := '0';
signal RX_CTL_DR: std_logic := '0';
signal RX_CTL_DR_D: std_logic := '0';
signal RX_CTL_DF: std_logic := '0';
signal MAC_RX_DV_LOCAL: std_logic := '0';
signal MAC_RX_ER_LOCAL: std_logic := '0';
signal CRS_LOCAL: std_logic := '0';

signal MAC_TXD_D: std_logic_vector(7 downto 0) := (others => '0');
signal TX_CTL_E: std_logic := '0';
signal TXC0: std_logic := '0';  -- clock for ODDR use.
signal TXC1: std_logic := '0';
signal MAC_TX_EN_D: std_logic := '0';

signal LINK_STATUS_LOCAL: std_logic := '0';
signal SPEED_STATUS_LOCAL: std_logic_vector(1 downto 0) := (others => '0');
signal DUPLEX_STATUS_LOCAL: std_logic := '0';
signal LOW_NIBBLE: std_logic := '0';

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

RGMII_EN <= not SYNC_RESET;
  -- disable the RGMII outputs while the PHY is being reset.

---------------------------------------------
-- RECEIVE SECTION
---------------------------------------------

--// RXC clock frequency detection
-- Detect received speed (alternate to RGMII in-status).
--DETECT_RX_SPEED_001: process(CLK)
--begin
--	if rising_edge(CLK) then
--		-- modulo 256 counter
--		RX_COUNTER1 <= RX_COUNTER1 + 1;
--	end if;
--end process;
--
--DETECT_RX_SPEED_002: process(RXCG, RX_COUNTER1(7))
--begin
--	if rising_edge(RXCG) then		
--		CMSB <= RX_COUNTER1(7);
--		CMSB_D <= CMSB;
--		if(CMSB_D = '1') and (CMSB = '0') then
--			-- end of counting period. Final counter is approximately
--			-- 256*125/CLK_FREQUENCY when 1000Mbps rx mode (RXCG is 125 MHz)
--			-- 256*25/CLK_FREQUENCY when 100Mbps rx mode (RXCG is 25 MHz)
--			-- 256*2.5/CLK_FREQUENCY when 10Mbps rx mode (RXCG is 2.5 MHz)
--			if(RX_COUNTER > (256*125/(2*CLK_FREQUENCY))) then
--				-- 1000Mbps rx mode (125 MHz detected)
--				SPEED_STATUS_LOCAL <= "10";
--			elsif(RX_COUNTER > (256*25/(2*CLK_FREQUENCY))) then 
--				-- 100Mbps rx mode (25 MHz detected)
--				SPEED_STATUS_LOCAL <= "01";
--			else
--				SPEED_STATUS_LOCAL <= "00";
--			end if;
--			RX_COUNTER <= (others => '0');
--		else
--			RX_COUNTER <= RX_COUNTER + 1;
--		end if;
--	end if;
--end process;


IBUFG_001: IBUFG  port map (I=> RXC, O=> RXCB);	

---- Plan B.
---- delay the RX clock by 2ns so that the clock is always slightly AFTER the signal transition.
--   IODELAY2_001 : IODELAY2
--   generic map (
--      COUNTER_WRAPAROUND => "STAY_AT_LIMIT", -- STAY_AT_LIMIT or WRAPAROUND
--      DATA_RATE => "SDR",                 -- SDR or DDR (???NOT SURE apply equal delay to the rising edge/falling edge)
-- 		DELAY_SRC => "IDATAIN",             -- IO, ODATAIN or IDATAIN (output is not delayed)
--      IDELAY2_VALUE => 0,                 -- Amount of Input Delay (0-255) 
--      IDELAY_MODE => "NORMAL",            -- Unsupported
--      IDELAY_TYPE => "FIXED",             -- FIXED, DEFAULT, VARIABLE_FROM_ZERO, VARIABLE_FROM_HALF_MAX or
--                                          -- DIFF_PHASE_DETECTOR
--      IDELAY_VALUE => RXC_DELAY,          -- Amount of input delay (0-255) 
--      ODELAY_VALUE => 0,                  -- Amount of output delay (0-255)
--      SERDES_MODE => "NONE",              -- NONE, MASTER or SLAVE
--      SIM_TAPDELAY_VALUE => 62            -- Amount of delay used for simulation in pS
--   )
--   port map (
--		-- IOB interface
--      IDATAIN => RXCB,  	 		-- 1-bit Data Signal from IOB
--		DOUT => open,  				-- Delayed signal to IOB
--		TOUT => open,  	 			-- Delayed Tristate signal to IOB
--		-- logic interface
--		ODATAIN => '0', 				-- Data from OLOGIC or OSERDES.
--		DATAOUT => RXC_DELAYED,		-- Delayed data to D pin of ILOGIC2 or ISERDES2
--		T => '0',              		-- Tristate control signal (input/output flow selection)
--		DATAOUT2 => open, 	 		-- Secondary delayed data output. Unused.
--		-- m&c
--		CAL => '0',						-- Initiate calibration command
--		BUSY => open,         		-- Busy after CAL. Unused.  Just for test purposes.
--      CE => '0',            		-- 1-bit Enable increment/decrement
--      CLK => '0',           		-- 1-bit Clock input. FIXED delay mode. no clock needed.
--      INC => '0',           		-- 1-bit Increment / Decrement input
--      IOCLK0 => '0',			 		-- 
--		IOCLK1 => '0',	 				-- secondary clock input/frequency doubler.
--		RST => '0'     				-- Reset to zero or 1/2 of total period
-- );

--BUFIO2_inst : BUFIO2
--generic map (
--	DIVIDE => 1,           -- DIVCLK divider (1-8)
--	DIVIDE_BYPASS => TRUE, -- Bypass the divider circuitry (TRUE/FALSE)
--	I_INVERT => FALSE,     -- Invert clock (TRUE/FALSE)
--	USE_DOUBLER => FALSE   -- Use doubler circuitry (TRUE/FALSE)
--)
--port map (
--	DIVCLK => RXC2,             -- 1-bit output Divided clock output
--	IOCLK => open,               -- 1-bit output I/O output clock
--	SERDESSTROBE => open, -- 1-bit output Output SERDES strobe (connect to ISERDES2/OSERDES2)
--	I => RXC_DELAYED                        -- 1-bit input Clock input (connect to IBUFG)
--);
--

-- declare the RX clock as a global clock
BUFG_001: BUFG port map(
--	I => RXC2,	-- when using IODELAY2 and BUFIO2 (plan B)
	I => RXCB,	-- when the fine delay adjustment is performed by the PHY under register 260 control.
	O => RXCG
);

-- RGMII receive side 
-- See Xilinx application note xapp692
IDDR_RX_001: for I in 0 to 3 generate   
   -- IDDR: Double Data Rate Input Register with Set, Reset
   --       and Clock Enable. 
   --       Virtex-5
   -- Xilinx HDL Language Template, version 13.4

   IDDR_inst : IDDR 
   generic map (
      DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE", "SAME_EDGE" 
                                       -- or "SAME_EDGE_PIPELINED" 
      INIT_Q1 => '0', -- Initial value of Q1: '0' or '1'
      INIT_Q2 => '0', -- Initial value of Q2: '0' or '1'
      SRTYPE => "ASYNC") -- Set/Reset type: "SYNC" or "ASYNC" 
   port map (
      Q1 => RXD_DR_E(I), -- 1-bit output captured with rising edge
      Q2 => RXD_DF(I), -- 1-bit output captured with falling edge
      C => RXCG, -- 1-bit clock input
      CE => '1', -- 1-bit clock enable input
      D => RXD(I),   -- 1-bit data input 
      R => SYNC_RESET,    -- 1-bit reset input
      S => '0'     -- 1-bit set input
      );
end generate;

-- reclock at the rising edge and reconstruct the received byte
-- see XAPP692
RECLOCK_001: process(RXCG)
begin
	if rising_edge(RXCG) then
		RXD_DR <= RXD_DR_E;	-- realignment rising_edge/falling_edge after IDDR C0 alignment. 
		RX_CTL_DR <= RX_CTL_DR_E;	-- realignment rising_edge/falling_edge after IDDR C0 alignment. 
		RX_CTL_DR_D <= RX_CTL_DR;
		
		if (SPEED_STATUS_LOCAL = "10") then	
			-- link is on, 1000 Mbps
			-- data width is 8-bit when 1000Mbps operation
			MAC_RXD_LOCAL(3 downto 0) <= RXD_DR;
			MAC_RXD_LOCAL(7 downto 4) <= RXD_DF;
			MAC_RX_SAMPLE_CLK <= '1';
			MAC_RX_DV_LOCAL <= RX_CTL_DR;
			MAC_RX_ER_LOCAL <= RX_CTL_DR xor RX_CTL_DF;
		elsif (SPEED_STATUS_LOCAL(1) = '0') then
			-- link is on, 10/100 Mbps. reconstruct 8-bit word from 4-bit nibbles.
			-- data width is 4-bit (duplicated on bits (7:4) and (3:0)) when 10/100 Mbps operation
			if(RX_CTL_DR_D = '0') and (RX_CTL_DR = '1') then
				-- KEY ASSUMPTION (TBC): low and high nibbles are always in successive periods without gaps.
				-- first valid nibble should be MAC_RXD(3 downto 0) (lsbs are received first)
				LOW_NIBBLE <= '0';		-- next nibble MAC_RXD_LOCAL(7 downto 4)
				RXD_DR_D  <= RXD_DR;	-- LSb received first
				MAC_RX_SAMPLE_CLK <= '0';	-- wait for the other half byte
			else
				LOW_NIBBLE <= not LOW_NIBBLE;
				if(LOW_NIBBLE = '1') then
					RXD_DR_D <= RXD_DR;	-- LSb received first
					MAC_RX_SAMPLE_CLK <= '0';
				else
					-- byte assembly is complete -> to output
					MAC_RXD_LOCAL(3 downto 0) <=  RXD_DR_D; 	-- LSb received first
					MAC_RXD_LOCAL(7 downto 4) <= RXD_DR;
					MAC_RX_SAMPLE_CLK <= '1';
					MAC_RX_DV_LOCAL <= RX_CTL_DR;
					MAC_RX_ER_LOCAL <= RX_CTL_DR xor RX_CTL_DF;
				end if;
			end if;
		end if;
	end if;
end process;


-- RX_CTL
-- IDDR: Double Data Rate Input Register with Set, Reset
--       and Clock Enable. 
--       Virtex-5
-- Xilinx HDL Language Template, version 13.4

IDDR_inst : IDDR 
generic map (
	DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE", "SAME_EDGE" 
												-- or "SAME_EDGE_PIPELINED" 
	INIT_Q1 => '0', -- Initial value of Q1: '0' or '1'
	INIT_Q2 => '0', -- Initial value of Q2: '0' or '1'
	SRTYPE => "ASYNC") -- Set/Reset type: "SYNC" or "ASYNC" 
port map (
	Q1 => RX_CTL_DR_E, -- 1-bit output captured with rising edge
	Q2 => RX_CTL_DF, -- 1-bit output captured with falling edge
	C => RXCG,   -- 1-bit clock input
	CE => '1',    -- 1-bit clock enable input
	D => RX_CTL,  -- 1-bit data input 
	R => SYNC_RESET,     -- 1-bit reset input
	S => '0'      -- 1-bit set input
	);

-- reclock at the rising edge and reconstruct the received byte
-- Interframe status
RECLOCK_002: process(RXCG)
begin
	if rising_edge(RXCG) then
		
		
		-- Decode RXD,RX_DV,RX_ER as per RGMII specifications
		-- see also XAPP692
		-- Write code so that the status is available at the same time as the received data MAC_RXD
		if(RX_CTL_DR = '0') and (RX_CTL_DF = '0') then
			-- Normal inter-frame
		   -- Note: optional. Must enable reporting in extended control register 256 during prior configuration. 
			-- Nibbles are repeated on the rising and falling edge.
			LINK_STATUS_LOCAL <= RXD_DR(0);  -- RXD(0) = link status
			SPEED_STATUS_LOCAL <= RXD_DR(2 downto 1);  -- speed status 00/01/10 for 2.5/25/125 MHz RXC clock speed
			DUPLEX_STATUS_LOCAL <= RXD_DR(3);  -- duplex status 0/1 for half/full-duplex
		end if;
	end if;
end process;
LINK_STATUS <= LINK_STATUS_LOCAL;
SPEED_STATUS <= SPEED_STATUS_LOCAL;
DUPLEX_STATUS <= DUPLEX_STATUS_LOCAL;

-- carrier sense
-- see RGMII 2.0 section 3.4.2
RECLOCK_003: process(RXCG)
begin
	if rising_edge(RXCG) then
		if(RX_CTL_DR = '1') then
			-- carrier sense is true when rx data valid
			CRS_LOCAL <= '1';	
		elsif(RX_CTL_DR = '0') and (RX_CTL_DF = '1') and (RXD_DR = x"F") and (RXD_DF = x"F") then
			-- or when carrier sense. 
			CRS_LOCAL <= '1';	
		elsif(RX_CTL_DR = '0') and (RX_CTL_DF = '1') and (RXD_DR = x"F") and (RXD_DF = x"0") then
			-- or when carrier extend
			CRS_LOCAL <= '1';	
		elsif(RX_CTL_DR = '0') and (RX_CTL_DF = '1') and (RXD_DR = x"F") and (RXD_DF = x"1") then
			-- or when carrier extend error
			CRS_LOCAL <= '1';	
		elsif(RX_CTL_DR = '0') and (RX_CTL_DF = '1') and (RXD_DR = x"E") and (RXD_DF = x"0") then
			-- false carrier
			CRS_LOCAL <= '1';	
		else
			CRS_LOCAL <= '0';
		end if;
	end if;
end process;



-- Collision
-- "Collision is determined at the MAC by the assertion of TXEN being true while either 
-- CRS or RXDV are true"
COL <= '1' when (MAC_TX_EN = '1') and ((CRS_LOCAL = '1') or (MAC_RX_DV_LOCAL = '1')) else '0';

RXCG_OUT <= RXCG;
MAC_RXD <= MAC_RXD_LOCAL;
MAC_RX_DV <= MAC_RX_DV_LOCAL;
MAC_RX_ER <= MAC_RX_ER_LOCAL;
CRS <= CRS_LOCAL;

---------------------------------------------
-- TRANSMIT SECTION
---------------------------------------------
-- First, reconstruct a 50% duty cycle transmit clock for the MAC_TXC
-- Make tx clock = rx clock frequency (2.5/25/125 MHz)
TXC0 <= 	RXCG;		

-- Reclock TX signals so that they are stable during the entire period (we don't
-- want any transition between the DDR rising and falling edges.)
-- Also, split the 8-bit input byte into two 4-bit nibbles (RGMII requirement)
RECLOCK_005: process(RXCG)
begin
	if rising_edge(RXCG) then
		if (TX_SPEED(1) = '0') then
			-- 10/100 Mbps case
			if(MAC_TX_SAMPLE_CLK = '1') then
				MAC_TXD_D(3 downto 0) <= MAC_TXD(3 downto 0);
				MAC_TXD_D(7 downto 4) <= MAC_TXD(3 downto 0);
				TX_CTL_E <= MAC_TX_EN xor MAC_TX_ER;
				MAC_TX_EN_D <= MAC_TX_EN;
			else
				MAC_TXD_D(3 downto 0) <= MAC_TXD(7 downto 4);
				MAC_TXD_D(7 downto 4) <= MAC_TXD(7 downto 4);
			end if;
		else
			-- 1000 Mbps case
			if (MAC_TX_SAMPLE_CLK = '1') then
				MAC_TXD_D <= MAC_TXD;
				TX_CTL_E <= MAC_TX_EN xor MAC_TX_ER;
				MAC_TX_EN_D <= MAC_TX_EN;
			end if;
		end if;
	end if;
end process;
			
			
--// TXD, TX_CTL AND TXC should be timed as close as possible (TskewT = +/- 0.5ns in RGMII specs)
   
ODDR_TX_001: for I in 0 to 3 generate   
   -- ODDR: Output Double Data Rate Output Register with Set, Reset
   --       and Clock Enable. 
   --       Virtex-5
   -- Xilinx HDL Language Template, version 13.4
   
   ODDR_inst : ODDR
   generic map(
      DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
      INIT => '0',   -- Initial value for Q port ('1' or '0')
      SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
   port map (
      Q => TXD(I), 	-- 1-bit output data
      C => TXC0, 		-- 1-bit clock input
      CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
      D1 => MAC_TXD_D(I),   -- 1-bit data input (associated with C0)
      D2 => MAC_TXD_D(I+4),   -- 1-bit data input (associated with C1)
      R => SYNC_RESET,    -- 1-bit reset input
      S => '0'     -- 1-bit set input
   );
end generate;

-- ODDR: Output Double Data Rate Output Register with Set, Reset
--       and Clock Enable. 
--       Virtex-5
-- Xilinx HDL Language Template, version 13.4

ODDR_TX_002 : ODDR
generic map(
	DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
	INIT => '0',   -- Initial value for Q port ('1' or '0')
	SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
port map (
	Q => TX_CTL, 	-- 1-bit output data
	C => TXC0, 		-- 1-bit clock input
   CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
	D1 => MAC_TX_EN_D,   -- 1-bit data input (associated with C0)
	D2 => TX_CTL_E,   -- 1-bit data input (associated with C1)
	R => SYNC_RESET,    -- 1-bit reset input
	S => '0'     -- 1-bit set input
);

-- Plan A is to delay clock at the PHY under control register 260
ODDR_TX_003:  ODDR
   generic map(
		DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
		INIT => '0',   -- Initial value for Q port ('1' or '0')
		SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
   port map (
      Q => TXC1, 	-- 1-bit output data
      C => TXC0, 		-- 1-bit clock input
      CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
      D1 => '1',   -- 1-bit data input (associated with C0)
      D2 => '0',   -- 1-bit data input (associated with C1)
      R => SYNC_RESET,    -- 1-bit reset input
      S => '0'     -- 1-bit set input
   );

-- delay the TX clock by 2ns so that the clock is always slightly AFTER the signal transition. (Plan B)
   IDELAYCTRL_inst : IDELAYCTRL
   port map (
      RDY => open,       -- 1-bit output indicates validity of the REFCLK
      REFCLK => IDELAYREFCLK200MHZ, -- 1-bit reference clock input 190-210 MHz
      RST => SYNC_RESET        -- 1-bit reset input. Minimum width 50ns
   );


   -- Xilinx Virtex-5 IODELAY: Input and Output Fixed or Variable Delay Element
   IODELAY_002 : IODELAY
   generic map (
      DELAY_SRC => "O", -- Specify which input port to be used
                        -- "I"=IDATAIN, "O"=ODATAIN, "DATAIN"=DATAIN, "IO"=Bi-directional
      HIGH_PERFORMANCE_MODE => TRUE, -- TRUE specifies lower jitter
                                     -- at expense of more power
      IDELAY_TYPE => "FIXED",  -- "FIXED" or "VARIABLE" 
      IDELAY_VALUE => 0,   -- 0 to 63 tap values
      ODELAY_VALUE => 2,   -- 0 to 63 tap values
      REFCLK_FREQUENCY => 200.0,   -- Frequency used for IDELAYCTRL
                                    -- 175.0 to 225.0
      SIGNAL_PATTERN => "CLOCK")    -- Input signal type, "CLOCK" or "DATA" 
   port map (
      DATAOUT => TXC,  -- 1-bit delayed data output
      C => '0',     -- 1-bit clock input
      CE => '0',   -- 1-bit clock enable input
      DATAIN => '0', -- 1-bit internal data input
      IDATAIN => '0',  -- 1-bit input data input (connect to port)
      INC => '0', -- 1-bit increment/decrement input
      ODATAIN => TXC1,  -- 1-bit output data input
      RST => '0',  -- 1-bit active high, synch reset input
      T => '0'  -- 1-bit 3-state control input
   );



--// TEST POINTS -------------------
TP(1) <= RXCG;
TP(2) <= RX_CTL_DR;
TP(3) <= RX_CTL_DF;
TP(4) <= RXD_DR(0);
TP(5) <= RXD_DR(1);
TP(6) <= RXD_DR(2);
TP(7) <= RXD_DR(3);
TP(8) <= '1' when SPEED_STATUS_LOCAL = "10" else '0';
TP(9) <= '1' when SPEED_STATUS_LOCAL = "01" else '0';
TP(10) <= RXD_DF(0);


--TP(2) <= CLK;
--TP(3) <= MAC_TX_EN;
--TP(4) <= MAC_TX_ER;
--TP(5) <= MAC_TX_SAMPLE_CLK;
--TP(6) <= TX_CTL_E;
--TP(7) <= RGMII_EN;
--TP(10) <= MAC_TXD_D(0);

end Behavioral;

