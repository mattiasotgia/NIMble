-------------------------------------------------------------
-- MSS copyright 2010-2019
--	Filename:  GMII_MII_WRAPPER.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 6
--	Date last modified: 3/11/19
-- Inheritance: 	N/A
--
-- Use Case: this MII/GMII wrapper may need simple adjustments depending on the hardware platform.
-- (a) adjust RX_CLK delay so that the RX_CLK edges are clearly separated from the RXD data bits transitions
-- see RXC_DELAY constant below.
-- (b) Same for GTX_CLK
-- see TXC_DELAY constant below.
-- 
-- 
-- description:  Wrapper between the MAC and the PHY (GMII/MII interface) 
-- 10/100 Mbps: Complies with the MII interface specification in the 802.3 standard clause 22
-- 1000 Mbps:  Complies with the GMII interface specification in the 802.3 standard clause 35
-- Automatic detection of the rx speed.
-- 
-- IMPORTANT Key design assumption: PHY always generates a RX_CLK, even when no cable is connected.
--
-- SIMULATOR ISSUE: the Xilinx Isim simulator is a bit confused when simulating one reclocking statement in COM5401 
-- l1711:			MAC_RXD_D <= MAC_RXD;  
-- In order to alleviate this issue, the output clock RXCG_OUT is inverted during simulation.

--
-- Rev 2 11/18/11 AZ
-- Corrected bug in speed detection. (previous code assumed that CLK frequency was 125 MHz)
-- Reduced number of clocks from 2 (125 MHz reference clock from PHY, RX clock from PHY)
-- to just one (RX clock from PHY). The main reason is that a 125 MHz from the PHY may not be available or clean enough, 
-- nor is it absolutely necessary. Cleaner code. The fewer clocks the better.
-- Link status is no longer read here. Use generic status status register 1 instead (works for all PHYs)
--
-- Rev 3 8/8/12 AZ
-- Improved SPEED STATUS detection algorithm to cover the case when the PHY does not generate a clock (while in reset for example)
--
-- Rev 4 2/1/14 AZ
-- changed sensitivity lists to avoid warnings
--
-- Rev 5 2/20/18 AZ
-- workaround the Xilinx isim simulator issue (see SIMULATOR ISSUE note above)
--
-- Rev 6 3/11/19 AZ
-- Added support for Xilinx 7-series (Untested)
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity GMII_MII_WRAPPER is
	generic (
		PLATFORM: integer := 7;
			-- valid platforms 6 = Spartan-6, 7 = Artix-7
		INTERNAL_PHY_TX_CLKS_DELAYS: std_logic := '0';
		INTERNAL_PHY_RX_CLKS_DELAYS: std_logic := '0';
			-- Additional delay implemented within? In addition to the PHY-implemented delays.
			-- '0' to implement the delays only at the PHY using the CLK_SKEW value (plan A)
			-- '1' to implement ADDITIONAL RXC and TXC clock delays within (plan A+B)
		CLK_FREQUENCY: integer;
			-- CLK frequency in MHz. Used as frequency reference for detecting PHY speed.
		SIMULATION: std_logic := '0'
	);
    Port ( 
		--// CLK, RESET
		SYNC_RESET: in std_logic;
			-- block the GMII/MII output signals to the PHY during the PHY reset.
		CLK: in std_logic;
			-- USER-side GLOBAL CLOCK (used as time-reference only)
			-- Only used as frequency reference for detecting speed.
		CLK125_0: in std_logic;	-- must be a GLOBAL clock
			-- 125 MHz clock used for GMII
		CLK125_1: in std_logic;	-- no need for global buffer here
			-- 2ns offset 125 MHz clock used to alleviate any glitch on the GMII tx path
			-- Used for GTX_CLK delay when external LAN PHY is unable to correct the tx signals timing or when
			-- the FPGA does not have output delay capability (for example Xilinx 7-series HR banks).
		
		--// PHY GMII/MII Interface ----------------------------------------------------------------
		-- Connect directly to FPGA pins
		TX_CLK: in std_logic;  
			-- MII tx clock from PHY. Continuous clock. (10/100 Mbps only) 
			-- 25 MHz (100 Mbps), or 2.5 MHz (10 Mbps) depending on speed
			-- accuracy: +/- 100ppm (MII)
			-- duty cycle between 35% and 65% inclusive (MII).
		GTX_CLK: out std_logic;  
			-- GMII tx clock to PHY. Continuous clock. 125MHz (1000 Mbps only)
			-- 2ns delay inside (user adjustable).
		TXD: out std_logic_vector(7 downto 0);  
			-- tx data (when TX_EN = '1' and TX_ER = '0') or special codes otherwise (carrier extend, 
			-- carrier extend error, transmit error propagation). See 802.3 table 35-1 for definitions.
		TX_EN: out std_logic;  
			-- 
		TX_ER: out std_logic;  
			-- to deliberately corrupt the contents of the frame (so as to be detected as such by the receiver)
		
		RX_CLK: in std_logic;  
			-- continuous receive reference clock recovered by the PHY from the received signal
			-- 125/25/2.5 MHz +/- 50 ppm. 
			-- Duty cycle better than 35%/65% (MII)
			-- 125 MHz must be delayed by 1.5 to 2.1 ns to prevent glitches (TBC. true for RGMII, but for GMII TOO???)
			
		RXD: in std_logic_vector(7 downto 0);  
			-- rx data. 8-bit when 1000 Mbps. 4-bit nibble (3:0) when 10/100 Mbps.
		RX_DV: in std_logic;  
		RX_ER: in std_logic;  
		CRS: in std_logic;  
			-- carrier sense
		COL: in std_logic;  
			-- collision detection
		
		--// MAC Interface ----------------------------------------------------------------
		
		-- Rx signals are synchronous with the rising edge of the RXCG_OUT clock 
		-- recovered by the PHY (could be 2.5/25/125 MHz)
		MAC_RXD: out std_logic_vector(7 downto 0);
			-- 8-bits of rx data
			-- read the above MAC_RX? signals at the rising edge of RXCG_OUT when MAC_RX_SAMPLE_CLK = '1'.
		MAC_RX_DV: out std_logic;
		MAC_RX_ER: out std_logic;
		MAC_RX_SAMPLE_CLK: out std_logic;
		RXCG_OUT: out std_logic;
			-- received clock (already a global clock, no need for any additional BUFG)
			-- 125 MHz (1000 Mbps), 25 MHz (100 Mbps) or 2.5 MHz (10 Mbps)
			
		-- Tx signals are synchronous with the rising edge of the TXCG_OUT clock 
		-- from the PHY (could be 2.5/25/125 MHz)
		MAC_TXD: in std_logic_vector(7 downto 0);
			-- 8-bits of tx data
			-- tx data (when MAC_TX_EN = '1' and MAC_TX_ER = '0') or special codes otherwise (carrier extend, 
			-- carrier extend error, transmit error propagation). See 802.3 table 35-1 for definitions.
		MAC_TX_EN: in std_logic;
			-- The MAC is responsible for holding the tx enable low until it has verified that it
			-- operates at the same speed as the PHY (as reported in the SPEED_STATUS)
		MAC_TX_ER: in std_logic;
			-- use (MAC_TX_EN, MAC_TX_ER) as follows:
			-- 0,0  = transmit complete
			-- 0,1 and MAC_TXD = 0x0F = carrier extend
			-- 0,1 and MAC_TXD = 0x1F = carrier extend error
			-- 1,0 = normal transmission
			-- 1,1 = transmit error
		MAC_TX_SAMPLE_CLK: in std_logic;
			-- 1-TXCG_OUT wide pulse. 
			-- read the above MAC_TX? signals at the rising edge of TXCG_OUT when MAC_TX_SAMPLE_CLK = '1'.
			-- Continuous '1' when the transmit speed is set at 1000 Mbps  
			-- 1-TXCG_OUT pulse once every (exactly) 2 TXCG_OUT when the transmit speed is set at 100 Mbps = 12.5 MHz
			-- 1-TXCG_OUT pulse once every (exactly) 2 TXCG_OUT when the transmit speed is set at 10 Mbps = 1.25 MHz
		TXCG_OUT: out std_logic;
			-- tx clock (already a global clock, no need for any additional BUFG)
			-- 125 MHz (1000 Mbps), 25 MHz (100 Mbps) or 2.5 MHz (10 Mbps)
			-- can be same as RXCG (1000 Mbps) or independent (10/100 Mbps)
			
		-- MAC monitoring and control
		MAC_TX_SPEED: in std_logic_vector(1 downto 0);
			-- 00/01/10  for 10/100/1000 Mbps transmit speed (not really a control, but this component
			-- needs to know what speed it should run at).
		MAC_CRS: out std_logic;  
			-- carrier sense. Directly from PHY over MII.
		MAC_COL: out std_logic;  
			-- collision detection. Directly from PHY over MII.
		
		--// PHY status
		SPEED_STATUS: out std_logic_vector(1 downto 0)
			-- Detected RX_CLK clock speed, 00 = 2.5 MHz, 01 = 25 MHz, 10 = 125 MHz, 11 = reserved
		
 );
end entity;

architecture Behavioral of GMII_MII_WRAPPER is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
constant RXC_DELAY: integer range 0 to 255 := 32;  -- adjust as needed. Here: 2ns
constant TXC_DELAY: integer range 0 to 255 := 32;  -- adjust as needed. Here: 2ns
--
signal RXCB: std_logic;
signal RX_CLK_DELAYED: std_logic := '0';
signal RX_CLK2: std_logic;
signal RXCg: std_logic := '0';	-- global clock, delayed 2ns w.r.t. received RXC.
signal RX_DV_D: std_logic;
signal RX_DV_D2: std_logic;
signal RX_ER_D: std_logic;
signal RXD_NIBBLE_TOGGLE: std_logic := '0';
signal RXD_D: std_logic_vector(7 downto 0) := (others => '0');

--// RXC clock frequency detection
signal RX_COUNTER1: std_logic_vector(7 downto 0) := (others => '0');
signal RX_COUNTER: std_logic_vector(8 downto 0) := (others => '0');
signal RX_COUNTER_FINAL: std_logic_vector(8 downto 0) := (others => '0');
signal RX_COUNTER_FINAL_D: std_logic_vector(8 downto 0) := (others => '0');
signal C1MSB: std_logic := '0';
signal C1MSB_D: std_logic := '0';
signal CMSB: std_logic := '0';
signal CMSB_D: std_logic := '0';
signal SPEED_STATUS_local: std_logic_vector(1 downto 0) := "00";

signal GMII_FLAG: std_logic := '0';
signal MAC_RX_ER_LOCAL: std_logic := '0';

signal TXCg: std_logic := '0';	
signal TXCg_n: std_logic := '0';	
signal TX_CLKG: std_logic := '0';	
signal MAC_TX_SAMPLE_CLK_D: std_logic := '0';	
signal MAC_TXD_D: std_logic_vector(7 downto 0);
signal MAC_TX_EN_D: std_logic;
signal MAC_TX_ER_D: std_logic;
signal TXD_NIBBLE_TOGGLE: std_logic;
signal GMII_EN: std_logic := '0';

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

GMII_EN <= not SYNC_RESET;
  -- disable the GMII outputs while the PHY is being reset.
--
---------------------------------------------
-- RECEIVE SECTION
---------------------------------------------

-- force IBUF or IBUFG selection (otherwise tools may select the wrong primitive)
-- Use IBUF if the signal is connected to a regular I/O pin.
-- Use IBUFG if the signal is connected to a global clock pin.
IBUF_001: IBUF port map( I => RX_CLK, O => RXCB);

PLANB6_RX: if(PLATFORM = 6) and (INTERNAL_PHY_RX_CLKS_DELAYS = '1') generate	
-- Plan B.
-- delay the RX clock by 2ns so that the clock is always slightly AFTER the signal transition.
   IODELAY2_001 : IODELAY2
   generic map (
      COUNTER_WRAPAROUND => "STAY_AT_LIMIT", -- STAY_AT_LIMIT or WRAPAROUND
      DATA_RATE => "SDR",                 -- SDR or DDR (???NOT SURE apply equal delay to the rising edge/falling edge)
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
		DATAOUT => RX_CLK_DELAYED,		-- Delayed data to D pin of ILOGIC2 or ISERDES2
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
		DIVCLK => RX_CLK2,             -- 1-bit output Divided clock output
		IOCLK => open,               -- 1-bit output I/O output clock
		SERDESSTROBE => open, -- 1-bit output Output SERDES strobe (connect to ISERDES2/OSERDES2)
		I => RX_CLK_DELAYED                        -- 1-bit input Clock input (connect to IBUFG)
	);


	-- declare the RX clock as a global clock
	BUFG_001 : BUFG port map (
		O => RXCg,     -- Clock buffer output
		I => RX_CLK2      -- Clock buffer input
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

-- immediately reclock rx input signals 
RECLOCK_RX_001: process(RXCg)
begin
	if rising_edge(RXCg) then
		RXD_D <= RXD;
		RX_DV_D <= RX_DV;
		RX_ER_D <= RX_ER;
	end if;
end process;

-- re-assemble 8-bit rx data (from 4-bit nibbles at 10/100 Mbps)
RX8B_001: process(RXCg)
begin
	if rising_edge(RXCg) then
		RX_DV_D2 <= RX_DV_D;
		
		if(SPEED_STATUS_local(1) = '0') and (RX_DV_D = '1') and (RX_DV_D2 = '0') then
			-- 10/100 Mbps. Start of new packet. Reset toggle
			RXD_NIBBLE_TOGGLE <= '1';
		else
			RXD_NIBBLE_TOGGLE <= not RXD_NIBBLE_TOGGLE;
		end if;
	end if;
end process;

MAX_RX_OUT_001: process(RXCg)
begin
	if rising_edge(RXCg) then
		MAC_CRS <= CRS;
		MAC_COL <= COL;
		
		if(SPEED_STATUS_local = "10") then
			-- 1000 Mbps
			MAC_RXD <= RXD_D;
			MAC_RX_DV <= RX_DV_D; 
			MAC_RX_ER_LOCAL <= RX_ER_D; 
			MAC_RX_SAMPLE_CLK <= '1';
		elsif(SPEED_STATUS_local(1) = '0') and (RX_DV_D = '1') and (RX_DV_D2 = '0') then
			-- start of new packet. Reset toggle
			MAC_RXD(3 downto 0) <= RXD_D(3 downto 0);
			MAC_RX_DV <= RX_DV_D; 
			MAC_RX_ER_LOCAL <= RX_ER_D; 
			MAC_RX_SAMPLE_CLK <= '0';  -- waiting for the other half
		elsif(SPEED_STATUS_local(1) = '0') and (RXD_NIBBLE_TOGGLE = '0') then
			-- 1st nibble (1/2)
			MAC_RXD(3 downto 0) <= RXD_D(3 downto 0);
			MAC_RX_DV <= RX_DV_D; 
			MAC_RX_ER_LOCAL <= RX_ER_D; 
			MAC_RX_SAMPLE_CLK <= '0';  -- waiting for the other half
		elsif(SPEED_STATUS_local(1) = '0') and (RXD_NIBBLE_TOGGLE = '1') then
			-- 2nd nibble (2/2)
			MAC_RXD(7 downto 4) <= RXD_D(3 downto 0);
			MAC_RX_SAMPLE_CLK <= '1';  -- got a complete byte
			MAC_RX_ER_LOCAL <= MAC_RX_ER_LOCAL or RX_ER_D;  -- RX_ER can be as short as one RXCg.
		else
			MAC_RX_SAMPLE_CLK <= '0';  
		end if;
	end if;
end process;

-- outputs to MAC
RXCG_OUT_GEN0: if(SIMULATION = '0') generate
	RXCG_OUT <= RXCg;
end generate;
RXCG_OUT_GEN1: if(SIMULATION = '1') generate
	-- SIMULATOR ISSUE: the Xilinx Isim simulator is a bit confused when simulating one reclocking statement in COM5401 
	-- l1711:			MAC_RXD_D <= MAC_RXD;  
	-- In order to alleviate this issue, the output clock RXCG_OUT is inverted during simulation.
	RXCG_OUT <= not RXCg;
end generate;
MAC_RX_ER <= MAC_RX_ER_LOCAL;

--// RX_SPEED AUTODETECT ------------------------------------------
-- Automatically detect rx speed based on the RX_CLK.
-- Algorithm: two counters, one based the variable frequency clock (RXCg), the other
-- based on the CLK user-supplied clock.

DETECT_RX_SPEED_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_COUNTER1 <= (others => '0');
		else
			-- modulo 256 counter
			RX_COUNTER1 <= RX_COUNTER1 + 1;
			C1MSB_D <= C1MSB;
			if(C1MSB_D = '0') and (C1MSB = '1') then
				-- middle of the counter period. resample RX_COUNTER_FINAL when stable.
				RX_COUNTER_FINAL_D <= RX_COUNTER_FINAL;
			end if;

			-- 256*125/CLK_FREQUENCY when 1000Mbps rx mode (RXCG is 125 MHz)
			-- 256*25/CLK_FREQUENCY when 100Mbps rx mode (RXCG is 25 MHz)
			-- 256*2.5/CLK_FREQUENCY when 10Mbps rx mode (RXCG is 2.5 MHz)
			if(RX_COUNTER_FINAL_D > (256*125/(2*CLK_FREQUENCY))) then
				-- 1000Mbps rx mode (125 MHz detected)
				SPEED_STATUS_LOCAL <= "10";
			elsif(RX_COUNTER_FINAL_D > (256*25/(2*CLK_FREQUENCY))) then 
				-- 100Mbps rx mode (25 MHz detected)
				SPEED_STATUS_LOCAL <= "01";
			elsif(RX_COUNTER_FINAL_D > 2) then 
				-- 10Mbps rx mode (2.5 MHz detected)
				SPEED_STATUS_LOCAL <= "00";
			else
				SPEED_STATUS_LOCAL <= "11";	-- undefined (includes the case with no PHY clock RXCG)
			end if;

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

GMII_FLAG <= '1' when SPEED_STATUS_local = "10" else '0';

-- report rx speed to MAC
SPEED_STATUS <= SPEED_STATUS_local;

---------------------------------------------
-- TRANSMIT SECTION
---------------------------------------------
-- two cases: @1000 Mbps (GMII), the GTX_CLK is an output . At 10/100Mbps (MII), the TX_CLK in an input.

-- In the 1000Mbps mode, we must provide a 125 MHz GTX_CLK to the PHY via CLK125_0 and the delayed version CLK125_1
-- In the 10/100 Mbps mode, the TX_CLKG clock is generated by the PHY (may drift w.r.t rx clock frequency)
-- IMPORTANT Key design assumption: PHY always generates a RX_CLK, even when no cable is connected.


BUFGMUX_inst : BUFGMUX
generic map (
	CLK_SEL_TYPE => "SYNC"  -- Glitchless ("SYNC") or fast ("ASYNC") clock switch-over
)
port map (
	O => TX_CLKG,   -- 1-bit output: Clock buffer output
	I0 => TX_CLK, -- 1-bit input: Clock buffer input (S=0)
	I1 => CLK125_0, -- 1-bit input: Clock buffer input (S=1)
	S => GMII_FLAG    -- 1-bit input: Clock buffer select
);

-- outputs to MAC
TXCG_OUT <= TX_CLKG;

-- Reclock TX signals so that they are stable during the entire period 
RECLOCK_005: process(TX_CLKG)
begin
	if rising_edge(TX_CLKG) then
		MAC_TX_SAMPLE_CLK_D <= MAC_TX_SAMPLE_CLK;
		
		if(SYNC_RESET = '1') then
			MAC_TXD_D <= (others => '0');
			MAC_TX_EN_D <= '0';
			MAC_TX_ER_D <= '0';
			TXD_NIBBLE_TOGGLE <= '0';
		elsif (MAC_TX_SAMPLE_CLK = '1') then
			MAC_TXD_D <= MAC_TXD;
			MAC_TX_EN_D <= MAC_TX_EN;
			MAC_TX_ER_D <= MAC_TX_ER;
			TXD_NIBBLE_TOGGLE <= '0';  -- point to lower nibble (3:0) first
		elsif(MAC_TX_SPEED(1) = '0') and (MAC_TX_SAMPLE_CLK_D = '1') then  -- 10/100 Mbps
			-- read another nibble. toggle upper/lower nibble pointer
			TXD_NIBBLE_TOGGLE <= not TXD_NIBBLE_TOGGLE;
		end if;
	end if;
end process;

TXD_OUTPUT_001: process(TX_CLKG)
begin
	if rising_edge(TX_CLKG) then
		if(SYNC_RESET = '1') then
			-- disable all outputs while the component is being reset.
			TXD <= (others => '0');
			TX_EN <= '0';
			TX_ER <= '0';
		elsif(MAC_TX_SPEED(1) = '0') then  -- 10/100 Mbps
			if(TXD_NIBBLE_TOGGLE = '0') then
				-- lower nibble (3:0)
				TXD <= MAC_TXD_D(3 downto 0) & MAC_TXD_D(3 downto 0);  -- data
			else
				TXD <= MAC_TXD_D(7 downto 4) & MAC_TXD_D(7 downto 4);  -- data
			end if;
			TX_EN <= MAC_TX_EN_D;
			TX_ER <= MAC_TX_ER_D;
		elsif(MAC_TX_SPEED = "10") then  -- 1000 Mbps
			TXD <= MAC_TXD_D;  -- data
			TX_EN <= MAC_TX_EN_D;
			TX_ER <= MAC_TX_ER_D;
		end if;
	end if;
end process;


ODDR2_TX_003_6: if(PLATFORM = 6) generate
	ODDR2_TX_003:  ODDR2
		generic map(
			DDR_ALIGNMENT => "C0", -- Sets output alignment to "NONE", "C0", "C1" 
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "ASYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => GTX_CLK, 	-- 1-bit output data
			C0 => TXCg, 		-- 1-bit clock input
			C1 => TXCg_n, 	-- 1-bit clock input
			CE => GMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
			D0 => '1',   -- 1-bit data input (associated with C0)
			D1 => '0',   -- 1-bit data input (associated with C1)
			R => '0',    -- 1-bit reset input
			S => '0'     -- 1-bit set input
		);
	TXCg_n <= not TXCg;

	PLANA_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '0') generate	
		TXCg <= TX_CLKG;	-- plan A 
	end generate;

	PLANB6_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '1') generate	
	-- delay the GTX_CLK clock by 2ns so that the clock is always slightly AFTER the signal transition. (Plan B)
		-- IODELAY2: Input and Output Fixed or Variable Delay Element
		--           Spartan-6
		-- Xilinx HDL Language Template, version 11.4

		IODELAY2_002 : IODELAY2
		generic map (
			COUNTER_WRAPAROUND => "STAY_AT_LIMIT", -- STAY_AT_LIMIT or WRAPAROUND
			DATA_RATE => "SDR",                 -- SDR or DDR (???NOT SURE. apply equal delay to the rising edge/falling edge)
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
			DOUT => TXCg,      -- 1-bit Delayed Data Output to IOB
			TOUT => open,         -- 1-bit Delayed Tristate Output
			CAL => '0',           -- 1-bit Initiate calibration input
			CE => '0',            -- 1-bit Enable increment/decrement
			CLK => '0',           -- 1-bit Clock input. FIXED delay mode. no clock needed.
			IDATAIN => '0',  	 	 -- 1-bit Data Signal from IOB
			INC => '0',           -- 1-bit Increment / Decrement input
			-- IOCLK0 - IOCLK1: 1-bit (each) I/O Clock inputs
			IOCLK0 => '0',			 -- 
			IOCLK1 => '0',
			ODATAIN => TX_CLKG,   	 -- 1-bit Output data input from OLOGIC or OSERDES.
			RST => '0',    -- 1-bit Reset to zero or 1/2 of total period
			T => '0'              -- 1-bit Tristate input signal
		);
	end generate;
end generate;

ODDR2_TX_003_7: if(PLATFORM = 7) generate

	PLANB_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '1') generate	
		-- delay the TX clock by approx 2ns so that the clock is always slightly AFTER the signal transition. (Plan B)
		TXCg <= CLK125_1;	-- plan B 
	end generate;

	PLANA_TX: if(INTERNAL_PHY_TX_CLKS_DELAYS = '0') generate	
		TXCg <= TX_CLKG;	-- plan A 
	end generate;

	ODDR_inst : ODDR
	generic map(
		DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
		INIT => '0',   -- Initial value for Q port ('1' or '0')
		SRTYPE => "ASYNC") -- Reset Type ("ASYNC" or "SYNC")
	port map (
		Q => GTX_CLK, 	-- 1-bit output data
		C => TXCg, 		-- 1-bit clock input
		CE => GMII_EN,  	-- 1-bit clock enable input (disabled during PHY reset)
		D1 => '1',   -- 1-bit data input (associated with C0)
		D2 => '0',   -- 1-bit data input (associated with C1)
		R => '0',    -- 1-bit reset input
		S => '0'     -- 1-bit set input
	);
end generate;

end Behavioral;

