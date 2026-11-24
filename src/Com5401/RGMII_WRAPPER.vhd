-------------------------------------------------------------
-- MSS copyright 2010-2016
--	Filename:  RGMII_WRAPPER.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 9
--	Date last modified: 5/31/16
-- Inheritance: 	N/A
--
-- description:  Wrapper between the MAC and the PHY (RGMII interface) 
-- Complies with RGMII Version 2.0 4/1/2002
--
--
-- Rev 2 3/1/11 AZ
-- Reduced number of clocks from 2 (125 MHz reference clock from PHY, RX clock from PHY)
-- to just one (RX clock from PHY). The main reason is that the 125 MHz from the PHY was not clean enough, 
-- nor is it absolutely necessary. Cleaner code. The fewer clocks the better.
-- + rx and tx clock delays are implemented in the PHY itself, instead of using an uncalibrated IODELAY2.
--
-- Rev 3 11/20/11 AZ
-- Switched SPEED_STATUS to a generic algorithm (no longer dependent on the use of extended registers).
-- Moved LINK_STATUS to more generic PHY_CONFIG.vhd
--
-- Rev 4 8/8/12 AZ
-- Improved SPEED STATUS detection algorithm to cover the case when the PHY does not generate a clock (while in reset for example)
--
-- Rev 5 5/26/13 AZ
-- Corrected counter overflow in computing the speed status when CLK_FREQUENCY is small. 
--
-- Rev 6 1/7/14 AZ
-- Ported to Artix-7
--
-- Rev 7 2/18/14 AZ
-- changed sensitivity lists to avoid warnings
-- Corrected missed detection of 10 Mbps case
-- Switched to numeric_std library
--
-- Rev 8 6/21/14 AZ
-- codify plans A and B for delaying the RXC and TXC clocks here or at the PHY.
--
-- Rev 9 5/31/16 AZ
-- Added external 125/25 MHz clocks with delay because sometimes the LAN PHY is unable to fully correct the tx timing.
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity RGMII_WRAPPER is
	generic (
		PLATFORM: integer := 7;
			-- valid platforms 6 = Spartan-6, 7 = Artix-7
		INTERNAL_PHY_TX_CLKS_DELAYS: std_logic := '0';
		INTERNAL_PHY_RX_CLKS_DELAYS: std_logic := '0';
			-- Additional delay implemented within? In addition to the PHY-implemented delays.
			-- '0' to implement the delays only at the PHY using the CLK_SKEW value (plan A)
			-- '1' to implement ADDITIONAL RXC and TXC clock delays within (plan A+B)
		CLK_FREQUENCY: integer := 125
			-- CLK frequency in MHz. Needed to compute actual delays.
			-- unused in baseline code. Alternative code for detecting speed.
			-- If less than 8 MHz, counters sizes must be increased to prevent overflow
	);
    Port ( 
		--// CLK, RESET
		CLK: in std_logic;
			-- USER-side GLOBAL CLOCK 
			-- Mostly used for detecting speed.
		SYNC_RESET: in std_logic;
			-- block the RGMII output signals to the PHY during the PHY reset.
			-- synchronous with RXCg_OUT
		CLK125_0: in std_logic;	-- must be a GLOBAL clock
		CLK125_1: in std_logic;	-- no need for global buffer here
		CLK25: in std_logic;	-- no need for global buffer here
			-- 125 MHz clocks with small (ns) phase offset, 25 MHz clock (50% duty cycle)
			-- Used for TXC delay when external LAN PHY is unable to correct the tx signals timing or when
			-- the FPGA does not have output delay capability (for example Xilinx 7-series HR banks).
			-- Used when INTERNAL_PHY_TX_CLKS_DELAYS = '1' and PLATFORM = 7
		
		--// PHY RGMII Interface ----------------------------------------------------------------
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
		
		--// MAC Interface ----------------------------------------------------------------

		-- All rx signals are synchronous with the rising edge of the RXCg_OUT clock 
		-- recovered by the PHY (could be 2.5/25/125 MHz)
		RXCg_OUT: out std_logic;
			-- received clock (already a global clock, no need for any additional BUFG)
			-- 125 MHz (1000 Mbps), 25 MHz (100 Mbps) or 2.5 MHz (10 Mbps)
		MAC_RXD: out std_logic_vector(7 downto 0);
			-- 8-bit of data (any speed, byte is reconstructed from 4-bit nibbles within)
		MAC_RX_DV: out std_logic;
		MAC_RX_ER: out std_logic;
		MAC_RX_SAMPLE_CLK: out std_logic;


		-- All tx signals are synchronous with the rising edge of the TXCg_OUT clock 
		-- (could be 2.5/25/125 MHz)
		TXCg_OUT: out std_logic;
			-- transmit clock (already a global clock, no need for any additional BUFG)
			-- 125 MHz (1000 Mbps), 25 MHz (100 Mbps) or 2.5 MHz (10 Mbps)
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
			-- 1-TXCg_OUT wide pulse. 
			-- read the above MAC_TX? signals at the rising edge of TXCg_OUT when MAC_TX_SAMPLE_CLK = '1'.
			-- Continuous '1' when the transmit speed is set at 1000 Mbps  
			-- 1-TXCg_OUT pulse once every (exactly) 2 CLKs when the transmit speed is set at 100 Mbps = 12.5 MHz
			-- 1-TXCg_OUT pulse once every (exactly) 2 CLKs when the transmit speed is set at 10 Mbps = 1.25 MHz
			
			
		--// controls
		TX_SPEED: in std_logic_vector(1 downto 0);
			-- 00/01/10  for 10/100/1000 Mbps transmit speed
		
		--// PHY status
		-- synchronous with RXCg global clock
		-- required in-band status
		CRS: out std_logic;  -- carrier sense
		COL: out std_logic;  -- collision detection
		
		-- status (generic method)  
		SPEED_STATUS: out std_logic_vector(1 downto 0);
			-- RXC clock speed, 00 = 2.5 MHz, 01 = 25 MHz, 10 = 125 MHz, 11 = undefined (no RXCg clock from PHY)
			
		--// test points
		TP: out std_logic_vector(10 downto 1)
		
 );
end entity;

architecture Behavioral of RGMII_WRAPPER is
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
constant RXC_DELAY: integer range 0 to 255 := 0;  -- adjust as needed.
constant TXC_DELAY: integer range 0 to 255 := 32;  -- adjust as needed.

--// RXC clock frequency detection
signal RX_COUNTER1: std_logic_vector(7 downto 0) := (others => '0');
signal RX_COUNTER: std_logic_vector(11 downto 0) := (others => '0');	-- min CLK_FREQUENCY 8 (MHz)
signal RX_COUNTER_FINAL: std_logic_vector(11 downto 0) := (others => '0');
signal RX_COUNTER_FINAL_D: std_logic_vector(11 downto 0) := (others => '0');
signal C1MSB: std_logic := '0';
signal C1MSB_D: std_logic := '0';
signal CMSB: std_logic := '0';
signal CMSB_D: std_logic := '0';

signal RXCB: std_logic := '0';
signal RXC2: std_logic := '0';
signal RGMII_EN: std_logic := '0';
signal RXC_DELAYED: std_logic := '0';
signal RXCg: std_logic := '0';	-- global clock, delayed 2ns w.r.t. received RXC.
signal RXCg_N: std_logic := '0';  		-- negative edge of the RXCg global clock. needed for IDDR.
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
signal MAC_RX_SAMPLE_CLK_local: std_logic := '0';

signal MAC_TXD_D: std_logic_vector(7 downto 0) := (others => '0');
signal TX_CTL_E: std_logic := '0';
signal TXC1: std_logic := '0';
signal TXC2: std_logic := '0';
signal MAC_TX_EN_D: std_logic := '0';
signal TXCg: std_logic := '0';	
signal TXCg_n: std_logic := '0';	
signal TXC_MUX: std_logic := '0';	
signal CNTR2P5: unsigned(4 downto 0) := (others => '0');
signal CLK2p5: std_logic := '0';	
signal TXC2_1A: std_logic := '0';	

--signal LINK_STATUS_LOCAL: std_logic := '0';
signal SPEED_STATUS_local: std_logic_vector(1 downto 0) := (others => '0');
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
-- Detect received speed (more generic than alternate method: RGMII in-status).
-- Algorithm: two counters, one based the variable frequency clock (RX_CLKG), the other
-- based on the CLK user-supplied clock.

DETECT_RX_SPEED_001: process(SYNC_RESET, CLK)
begin
	if rising_edge(CLK) then
		-- modulo 256 counter
		RX_COUNTER1 <= RX_COUNTER1 + 1;
		C1MSB_D <= C1MSB;
		if(C1MSB_D = '0') and (C1MSB = '1') then
			-- middle of the counter period. resample RX_COUNTER_FINAL when stable.
			RX_COUNTER_FINAL_D <= RX_COUNTER_FINAL;
		end if;

		-- 256*125/CLK_FREQUENCY when 1000Mbps rx mode (RXCg is 125 MHz)
		-- 256*25/CLK_FREQUENCY when 100Mbps rx mode (RXCg is 25 MHz)
		-- 256*2.5/CLK_FREQUENCY when 10Mbps rx mode (RXCg is 2.5 MHz)
		if(RX_COUNTER_FINAL_D > (256*125/(2*CLK_FREQUENCY))) then
			-- 1000Mbps rx mode (125 MHz detected)
			SPEED_STATUS_local <= "10";
		elsif(RX_COUNTER_FINAL_D > (256*25/(2*CLK_FREQUENCY))) then 
			-- 100Mbps rx mode (25 MHz detected)
			SPEED_STATUS_local <= "01";
		elsif(RX_COUNTER_FINAL_D >= 2) then -- new 1/11/14 AZ
			-- 10Mbps rx mode (2.5 MHz detected)
			SPEED_STATUS_local <= "00";
		else
			SPEED_STATUS_local <= "11";	-- undefined (includes the case with no PHY clock RXCg)
		end if;

	end if;
end process;
C1MSB <= RX_COUNTER1(7);

DETECT_RX_SPEED_002: process(RXCg)
begin
	if rising_edge(RXCg) then		
		CMSB <= RX_COUNTER1(7);
		CMSB_D <= CMSB;
		if(SYNC_RESET = '1') then
			RX_COUNTER <= (others => '0');
		elsif(CMSB_D = '1') and (CMSB = '0') then
			-- end of counting period. 
			RX_COUNTER_FINAL <= RX_COUNTER;	-- freeze final count
			RX_COUNTER <= (others => '0');	-- start new count
		else
			RX_COUNTER <= RX_COUNTER + 1;
		end if;
	end if;
end process;

-- report rx speed to MAC
SPEED_STATUS <= SPEED_STATUS_local;

-- force IBUF or IBUFG selection (otherwise tools may select the wrong primitive)
-- Use IBUF if the signal is connected to a regular I/O pin.
-- Use IBUFG if the signal is connected to a global clock pin.
IBUFG_001: IBUFG  port map (I=> RXC, O=> RXCB);	

PLANB6_RX: if(PLATFORM = 6) and (INTERNAL_PHY_RX_CLKS_DELAYS = '1') generate	
-- Plan B.
-- delay the RX clock by 2ns so that the clock is always slightly AFTER the signal transition.
   IODELAY2_001 : IODELAY2
   generic map (
      COUNTER_WRAPAROUND => "STAY_AT_LIMIT", -- STAY_AT_LIMIT or WRAPAROUND
      DATA_RATE => "DDR",                 -- DDR 
 		DELAY_SRC => "IDATAIN",             -- IO, ODATAIN or IDATAIN (output is not delayed)
      IDELAY2_VALUE => 0,                 -- Amount of Input Delay (0-255) 
      IDELAY_MODE => "NORMAL",            -- Unsupported
      IDELAY_TYPE => "FIXED",             -- FIXED, DEFAULT, VARIABLE_FROM_ZERO, VARIABLE_FROM_HALF_MAX or
                                          -- DIFF_PHASE_DETECTOR
      IDELAY_VALUE => RXC_DELAY,          -- Amount of input delay (0-255) 
      ODELAY_VALUE => 0,                  -- Amount of output delay (0-255)
      SERDES_MODE => "NONE",              -- NONE, MASTER or SLAVE
      SIM_TAPDELAY_VALUE => 62            -- Amount of delay used for simulation in pS
   )
   port map (
		-- IOB interface
      IDATAIN => RXCB,  	 		-- 1-bit Data Signal from IOB
		DOUT => open,  				-- Delayed signal to IOB
		TOUT => open,  	 			-- Delayed Tristate signal to IOB
		-- logic interface
		ODATAIN => '0', 				-- Data from OLOGIC or OSERDES.
		DATAOUT => RXC_DELAYED,		-- Delayed data to D pin of ILOGIC2 or ISERDES2
		T => '0',              		-- Tristate control signal (input/output flow selection)
		DATAOUT2 => open, 	 		-- Secondary delayed data output. Unused.
		-- m&c
		CAL => '0',						-- Initiate calibration command
		BUSY => open,         		-- Busy after CAL. Unused.  Just for test purposes.
      CE => '0',            		-- 1-bit Enable increment/decrement
      CLK => '0',           		-- 1-bit Clock input. FIXED delay mode. no clock needed.
      INC => '0',           		-- 1-bit Increment / Decrement input
      IOCLK0 => '0',			 		-- 
		IOCLK1 => '0',	 				-- secondary clock input/frequency doubler.
		RST => '0'     				-- Reset to zero or 1/2 of total period
	);


	BUFIO2_inst : BUFIO2
	generic map (
		DIVIDE => 1,           -- DIVCLK divider (1-8)
		DIVIDE_BYPASS => TRUE, -- Bypass the divider circuitry (TRUE/FALSE)
		I_INVERT => FALSE,     -- Invert clock (TRUE/FALSE)
		USE_DOUBLER => FALSE   -- Use doubler circuitry (TRUE/FALSE)
	)
	port map (
		DIVCLK => RXC2,             -- 1-bit output Divided clock output
		IOCLK => open,               -- 1-bit output I/O output clock
		SERDESSTROBE => open, -- 1-bit output Output SERDES strobe (connect to ISERDES2/OSERDES2)
		I => RXC_DELAYED                        -- 1-bit input Clock input (connect to IBUFG)
	);

	-- declare the RX clock as a global clock
	BUFG_001: BUFG port map(
		I => RXC2,	-- when using IODELAY2 and BUFIO2 (plan B)
		O => RXCg
	);
end generate;

PLANB7_RX: if(PLATFORM = 7) and (INTERNAL_PHY_RX_CLKS_DELAYS = '1') generate	
-- Plan B.
-- delay the RX clock by 2ns so that the clock is always slightly AFTER the signal transition.
-- Not needed so far. FUTURE
end generate;

PLANA6_RX: if(PLATFORM = 6) and (INTERNAL_PHY_RX_CLKS_DELAYS = '0') generate	
	-- declare the RX clock as a global clock
	BUFG_001: BUFG port map(
		I => RXCB,	-- when the fine delay adjustment is performed by the PHY under register 260 control.
		O => RXCg
	);
end generate;

PLANA7_RX: if(PLATFORM = 7) and (INTERNAL_PHY_RX_CLKS_DELAYS = '0') generate	
	-- declare the RX clock as a regional clock  (we need to save a few ns... TBC)
   BUFR_001 : BUFR
generic map (
   BUFR_DIVIDE => "BYPASS",   -- Values: "BYPASS, 1, 2, 3, 4, 5, 6, 7, 8" 
   SIM_DEVICE => "7SERIES"  -- Must be set to "7SERIES" 
)
port map (
   O => RXCg,     -- 1-bit output: Clock output port
   CE => '1',   -- 1-bit input: Active high, clock enable (Divided modes only)
   CLR => '0', -- 1-bit input: Active high, asynchronous clear (Divided modes only)
   I => RXCB      -- 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
);
end generate;



RXCg_N <= not RXCg;

-- RGMII receive side 
IDDR2_RX_001: for I in 0 to 3 generate   
	IDDR2_INST_6: if(PLATFORM = 6) generate
		-- See Xilinx application note xapp692
		-- IDDR2: Input Double Data Rate Input Register with Set, Reset
		--        and Clock Enable. 
		--        Spartan-6
		-- Xilinx HDL Language Template, version 11.4
		IDDR2_INST : IDDR2
		generic map(
			DDR_ALIGNMENT => "C0", -- Sets output alignment to "NONE", "C0", "C1" 
			INIT_Q0 => '0', -- Sets initial state of the Q0 output to '0' or '1'
			INIT_Q1 => '0', -- Sets initial state of the Q1 output to '0' or '1'
			SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q0 => RXD_DR_E(I), -- 1-bit output captured with rising edge
			Q1 => RXD_DF(I), -- 1-bit output captured with falling edge
			C0 => RXCg, -- 1-bit clock input
			C1 => RXCg_N, -- 1-bit clock input
			CE => '1',  -- 1-bit clock enable input
			D => RXD(I),   -- 1-bit data input 
			R => '0',    -- 1-bit reset input
			S => '0'     -- 1-bit set input
		);
	end generate;
	
	IDDR2_INST_7: if(PLATFORM = 7) generate
		-- IDDR: Double Data Rate Input Register with Set, Reset
		--       and Clock Enable. 
		--       Artix-7
		-- Xilinx HDL Language Template, version 14.4
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
			C => RXCg, -- 1-bit clock input
			CE => '1',  -- 1-bit clock enable input
			D => RXD(I),   -- 1-bit data input 
			R => '0',   -- 1-bit reset
			S => '0'    -- 1-bit set
			);
	end generate;
end generate;

-- reclock at the rising edge and reconstruct the received byte
-- see XAPP692
RECLOCK_001: process(RXCg)
begin
	if rising_edge(RXCg) then
		RXD_DR <= RXD_DR_E;	-- realignment rising_edge/falling_edge after IDDR2 C0 alignment. 
		RX_CTL_DR <= RX_CTL_DR_E;	-- realignment rising_edge/falling_edge after IDDR2 C0 alignment. 
		RX_CTL_DR_D <= RX_CTL_DR;
		
		if (SPEED_STATUS_local = "10") then	
			-- link is on, 1000 Mbps
			-- data width is 8-bit when 1000Mbps operation
			MAC_RXD_LOCAL(3 downto 0) <= RXD_DR;
			MAC_RXD_LOCAL(7 downto 4) <= RXD_DF;
			MAC_RX_SAMPLE_CLK_local <= '1';
			MAC_RX_DV_LOCAL <= RX_CTL_DR;
			MAC_RX_ER_LOCAL <= RX_CTL_DR xor RX_CTL_DF;
		elsif (SPEED_STATUS_local(1) = '0') then
			-- link is on, 10/100 Mbps. reconstruct 8-bit word from 4-bit nibbles.
			-- data width is 4-bit (duplicated on bits (7:4) and (3:0)) when 10/100 Mbps operation
			if(RX_CTL_DR_D = '0') and (RX_CTL_DR = '1') then
				-- KEY ASSUMPTION (TBC): low and high nibbles are always in successive periods without gaps.
				-- first valid nibble should be MAC_RXD(3 downto 0) (lsbs are received first)
				LOW_NIBBLE <= '0';		-- next nibble MAC_RXD_LOCAL(7 downto 4)
				RXD_DR_D  <= RXD_DR;	-- LSb received first
				MAC_RX_SAMPLE_CLK_local <= '0';	-- wait for the other half byte
			else
				LOW_NIBBLE <= not LOW_NIBBLE;
				if(LOW_NIBBLE = '1') then
					RXD_DR_D <= RXD_DR;	-- LSb received first
					MAC_RX_SAMPLE_CLK_local <= '0';
				else
					-- byte assembly is complete -> to output
					MAC_RXD_LOCAL(3 downto 0) <=  RXD_DR_D; 	-- LSb received first
					MAC_RXD_LOCAL(7 downto 4) <= RXD_DR;
					MAC_RX_SAMPLE_CLK_local <= '1';
					MAC_RX_DV_LOCAL <= RX_CTL_DR;
					MAC_RX_ER_LOCAL <= RX_CTL_DR xor RX_CTL_DF;
				end if;
			end if;
		end if;
	end if;
end process;
MAC_RX_SAMPLE_CLK <= MAC_RX_SAMPLE_CLK_local;

-- RX_CTL
IDDR2_INST_6: if(PLATFORM = 6) generate
	IDDR2_INST : IDDR2
	generic map(
		DDR_ALIGNMENT => "C0", -- Sets output alignment to "NONE", "C0", "C1" 
		INIT_Q0 => '0', -- Sets initial state of the Q0 output to '0' or '1'
		INIT_Q1 => '0', -- Sets initial state of the Q1 output to '0' or '1'
		SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
	port map (
		Q0 => RX_CTL_DR_E, -- 1-bit output captured with rising edge
		Q1 => RX_CTL_DF, -- 1-bit output captured with falling edge
		C0 => RXCg,   -- 1-bit clock input
		C1 => RXCg_N, -- 1-bit clock input
		CE => '1',    -- 1-bit clock enable input
		D => RX_CTL,  -- 1-bit data input 
		R => '0',     -- 1-bit reset input
		S => '0'      -- 1-bit set input
	);
end generate;

IDDR2_INST_7: if(PLATFORM = 7) generate
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
		C => RXCg,   -- 1-bit clock input
		CE => '1',  -- 1-bit clock enable input
		D => RX_CTL,  -- 1-bit data input 
		R => '0',   -- 1-bit reset
		S => '0'    -- 1-bit set
		);
end generate;

-- reclock at the rising edge and reconstruct the received byte
-- Interframe status. Tested with Micrel KSZ9021 PHY. However, this requires access to the 
-- extended control registers which may vary depending on Manufacturer/PHY model.
-- Use alternate, more generic method.
--RECLOCK_002: process(RXCg)
--begin
--	if rising_edge(RXCg) then
--		
--		
--		-- Decode RXD,RX_DV,RX_ER as per RGMII specifications
--		-- see also XAPP692
--		-- Write code so that the status is available at the same time as the received data MAC_RXD
--		if(RX_CTL_DR = '0') and (RX_CTL_DF = '0') then
--			-- Normal inter-frame
--		   -- Note: optional. Must enable reporting in extended control register 256 during prior configuration. 
--			-- Nibbles are repeated on the rising and falling edge.
--			LINK_STATUS_LOCAL <= RXD_DR(0);  -- RXD(0) = link status
--			SPEED_STATUS_local <= RXD_DR(2 downto 1);  -- speed status 00/01/10 for 2.5/25/125 MHz RXC clock speed
--			DUPLEX_STATUS_LOCAL <= RXD_DR(3);  -- duplex status 0/1 for half/full-duplex
--		end if;
--	end if;
--end process;

-- carrier sense
-- see RGMII 2.0 section 3.4.2
RECLOCK_003: process(RXCg)
begin
	if rising_edge(RXCg) then
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

RXCg_OUT <= RXCg;
MAC_RXD <= MAC_RXD_LOCAL;
MAC_RX_DV <= MAC_RX_DV_LOCAL;
MAC_RX_ER <= MAC_RX_ER_LOCAL;
CRS <= CRS_LOCAL;

---------------------------------------------
-- TRANSMIT SECTION
---------------------------------------------
-- First, reconstruct a 50% duty cycle transmit clock for the MAC_TXC
-- In most cases, make tx clock = rx clock frequency (2.5/25/125 MHz)
-- However, in some special cases (PHY and FPGA cannot fully adjust timing on tx signals), the 
-- tx clock is derived from two 125 MHz clocks offset by a ns delay.

-- general case
TXCg_GEN_006: if(PLATFORM = 6) or (INTERNAL_PHY_TX_CLKS_DELAYS = '0') generate
	-- can be 125/25/2.5 MHz after autonegotiation, as directed by the LAN PHY
	TXCg <= RXCg;
	TXCg_n <= not RXCg;
end generate;

-- special case
TXCg_GEN_007: if(PLATFORM = 7) and (INTERNAL_PHY_TX_CLKS_DELAYS = '1') generate
	-- can be 125/25/2.5 MHz after autonegotiation, as directed by the LAN PHY
	
	-- divide 125 MHz by 50
	CLK2P5_GEN: process( CLK125_0)
	begin
		if rising_edge(CLK125_0) then
			-- modulo-25 counter (divide 125 MHz frequency by 50 = 2.5 MHz)
			if(CNTR2P5 = 24) then
				CNTR2P5 <= (others => '0');
				CLK2p5 <= not CLK2p5;
			else
				CNTR2P5 <= CNTR2P5 + 1;
			end if;
		end if;
	end process;

	TXC_MUX_GEN: process(TX_SPEED, CLK125_0, CLK25, CLK2p5)
	begin
		if(TX_SPEED = "10") then
			-- 125 MHz
			TXC_MUX <= 	CLK125_0;		
		elsif(TX_SPEED = "01") then
			-- 25 MHz
			TXC_MUX <= 	CLK25;		
		else
			-- 2.5 MHz
			TXC_MUX <= CLK2p5;		
		end if;
		TXCg_n <= not TXCg;
	end process;

   BUFR_001 : BUFR
	generic map (
		BUFR_DIVIDE => "BYPASS",   -- Values: "BYPASS, 1, 2, 3, 4, 5, 6, 7, 8" 
		SIM_DEVICE => "7SERIES"  -- Must be set to "7SERIES" 
	)
	port map (
		O => TXCg,     -- 1-bit output: Clock output port
		CE => '1',   -- 1-bit input: Active high, clock enable (Divided modes only)
		CLR => '0', -- 1-bit input: Active high, asynchronous clear (Divided modes only)
		I => TXC_MUX      -- 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
	);

end generate;
TXCg_OUT <= TXCg;

-- Reclock TX signals so that they are stable during the entire period (we don't
-- want any transition between the DDR rising and falling edges.)
-- Also, split the 8-bit input byte into two 4-bit nibbles (RGMII requirement)
RECLOCK_005: process(TXCg)
begin
	if rising_edge(TXCg) then
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
   
ODDR2_TX_001: for I in 0 to 3 generate   
	ODDR2_inst_6: if(PLATFORM = 6) generate
		ODDR2_inst : ODDR2
		generic map(
			DDR_ALIGNMENT => "C0", -- Sets output alignment to "NONE", "C0", "C1" 
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => TXD(I), 	-- 1-bit output data
			C0 => TXCg, 		-- 1-bit clock input
			C1 => TXCg_n, 	-- 1-bit clock input
			CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
			D0 => MAC_TXD_D(I),   -- 1-bit data input (associated with C0)
			D1 => MAC_TXD_D(I+4),   -- 1-bit data input (associated with C1)
			R => '0',    -- 1-bit reset input
			S => '0'     -- 1-bit set input
		);
	end generate;
	
	ODDR2_inst_7: if(PLATFORM = 7) generate
		-- ODDR: Output Double Data Rate Output Register with Set, Reset
		--       and Clock Enable. 
		--       Artix-7
		-- Xilinx HDL Language Template, version 14.4
		
		ODDR_inst : ODDR
		generic map(
			DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
			INIT => '0',   -- Initial value for Q port ('1' or '0')
			SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
		port map (
			Q => TXD(I), 	-- 1-bit output data
			C => TXCg, 		-- 1-bit clock input
			CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
			D1 => MAC_TXD_D(I),   -- 1-bit data input (associated with C0)
			D2 => MAC_TXD_D(I+4),   -- 1-bit data input (associated with C1)
			R => '0',    -- 1-bit reset input
			S => '0'     -- 1-bit set input
		);
	end generate;	
end generate;

ODDR2_TX_002_6: if(PLATFORM = 6) generate
	ODDR2_TX_002 : ODDR2
	generic map(
		DDR_ALIGNMENT => "C0", -- Sets output alignment to "NONE", "C0", "C1" 
		INIT => '0', -- Sets initial state of the Q output to '0' or '1'
		SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
	port map (
		Q => TX_CTL, 	-- 1-bit output data
		C0 => TXCg, 		-- 1-bit clock input
		C1 => TXCg_n, 	-- 1-bit clock input
		CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
		D0 => MAC_TX_EN_D,   -- 1-bit data input (associated with C0)
		D1 => TX_CTL_E,   -- 1-bit data input (associated with C1)
		R => '0',    -- 1-bit reset input
		S => '0'     -- 1-bit set input
	);
	
end generate;

ODDR2_TX_002_7: if(PLATFORM = 7) generate
	ODDR_inst : ODDR
	generic map(
		DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
		INIT => '0',   -- Initial value for Q port ('1' or '0')
		SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
	port map (
		Q => TX_CTL, 	-- 1-bit output data
		C => TXCg, 		-- 1-bit clock input
		CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
		D1 => MAC_TX_EN_D,   -- 1-bit data input (associated with C0)
		D2 => TX_CTL_E,   -- 1-bit data input (associated with C1)
		R => '0',    -- 1-bit reset input
		S => '0'     -- 1-bit set input
	);
end generate;

--// TX CLOCKS ------------------------

-- Plan A is to delay clock at the PHY under control register 260 (Micrel KSZ9021/31 specific)
ODDR2_TX_003_6: if(PLATFORM = 6) generate
	ODDR2_TX_003:  ODDR2
		generic map(
			DDR_ALIGNMENT => "C0", -- Sets output alignment to "NONE", "C0", "C1" 
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => TXC1, 	-- 1-bit output data
			C0 => TXCg, 		-- 1-bit clock input
			C1 => TXCg_n, 	-- 1-bit clock input
			CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
			D0 => '1',   -- 1-bit data input (associated with C0)
			D1 => '0',   -- 1-bit data input (associated with C1)
			R => '0',    -- 1-bit reset input
			S => '0'     -- 1-bit set input
		);

	PLANA_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '0') generate	
		TXC <= TXC1;	-- plan A 
	end generate;
		
	PLANB6_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '1') generate	
	-- delay the TX clock by 2ns so that the clock is always slightly AFTER the signal transition. (Plan B)
		-- IODELAY2: Input and Output Fixed or Variable Delay Element
		--           Spartan-6
		-- Xilinx HDL Language Template, version 11.4

		IODELAY2_002 : IODELAY2
		generic map (
			COUNTER_WRAPAROUND => "STAY_AT_LIMIT", -- STAY_AT_LIMIT or WRAPAROUND
			DATA_RATE => "DDR",                 -- DDR 
			DELAY_SRC => "ODATAIN",             -- IO, ODATAIN or IDATAIN
			IDELAY2_VALUE => 0,                 -- Amount of Input Delay (0-255) 
			IDELAY_MODE => "NORMAL",            -- Unsupported
			IDELAY_TYPE => "FIXED",             -- FIXED, DEFAULT, VARIABLE_FROM_ZERO, VARIABLE_FROM_HALF_MAX or
															-- DIFF_PHASE_DETECTOR
			IDELAY_VALUE => 0,          			-- Amount of input delay (0-255) 
			ODELAY_VALUE => TXC_DELAY,          -- Amount of output delay (0-255)
			SERDES_MODE => "NONE",              -- NONE, MASTER or SLAVE
			SIM_TAPDELAY_VALUE => 62            -- Amount of delay used for simulation in pS
		)
		port map (
			BUSY => open,         -- 1-bit Busy after CAL
			DATAOUT => open,   	 -- 1-bit Delayed data output
			DATAOUT2 => open, 	 -- 1-bit Delayed data output
			DOUT => TXC,          -- 1-bit Delayed Data Output to IOB
			TOUT => open,         -- 1-bit Delayed Tristate Output
			CAL => '0',           -- 1-bit Initiate calibration input
			CE => '0',            -- 1-bit Enable increment/decrement
			CLK => '0',           -- 1-bit Clock input. FIXED delay mode. no clock needed.
			IDATAIN => '0',  	 	 -- 1-bit Data Signal from IOB
			INC => '0',           -- 1-bit Increment / Decrement input
			-- IOCLK0 - IOCLK1: 1-bit (each) I/O Clock inputs
			IOCLK0 => '0',			 -- 
			IOCLK1 => '0',
			ODATAIN => TXC1,   	 -- 1-bit Output data input from OLOGIC or OSERDES.
			RST => '0',    -- 1-bit Reset to zero or 1/2 of total period
			T => '0'              -- 1-bit Tristate input signal
		);
	end generate;
end generate;

ODDR2_TX_003_7: if(PLATFORM = 7) generate

	PLANB_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '1') generate	
		-- delay the TX clock by approx 2ns so that the clock is always slightly AFTER the signal transition. (Plan B)
		RECLOCK_DELAY: process(CLK125_0)
		begin
			if falling_edge(CLK125_0) then	-- NOTE: FALLING EDGE = 4ns delay
				if(TX_SPEED = "01") then
					TXC2_1A <= CLK25;	-- 25 MHz
				else
					TXC2_1A <= CLK2p5;	-- 2.5 MHz
				end if;
			end if;
		end process;
		-- create a delayed version of TXC for all speed 125/25/2.5 MHz
		TXC2_MUX_GEN: process(TX_SPEED, CLK125_1, TXC2_1A)
		begin
			case(TX_SPEED) is
				when "10" => TXC2 <= CLK125_1;	-- 125 MHz delayed in PLL/MMCM
				when others => TXC2 <= TXC2_1A;	-- 25 MHz/2.5 MHz
			end case;
	end process;
		
	end generate;
	
	PLANA_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '0') generate	
		TXC2 <= TXCg;	-- plan A 
	end generate;


	ODDR_inst : ODDR
	generic map(
		DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
		INIT => '0',   -- Initial value for Q port ('1' or '0')
		SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
	port map (
		Q => TXC, 	-- 1-bit output data
		C => TXC2, 		-- 1-bit clock input
		CE => RGMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
		D1 => '1',   -- 1-bit data input (associated with C0)
		D2 => '0',   -- 1-bit data input (associated with C1)
		R => '0',    -- 1-bit reset input
		S => '0'     -- 1-bit set input
	);
end generate;
	
--// TEST POINTS -------------------
TP(1) <= RXCg;
TP(2) <= RX_CTL_DR_E;
TP(3) <= RX_CTL_DR_D;
TP(4) <= RX_CTL_DF;
TP(5) <= LOW_NIBBLE;
TP(6) <= '1' when (RXD_DR = x"5") else '0';
TP(7) <= '1' when (RXD_DR = x"D") else '0';
TP(8) <= MAC_RX_DV_LOCAL;
TP(9) <= '1' when (MAC_RXD_LOCAL = x"D5")   else '0';
TP(10) <= '1' when (MAC_RXD_LOCAL = x"55")   else '0';
end Behavioral;

