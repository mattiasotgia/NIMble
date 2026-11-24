-------------------------------------------------------------
-- MSS copyright 2010
--	Filename:  STRAPPING_OPTIONS.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 1
--	Date last modified: 3-5-10
-- Inheritance: 	n/a
--
-- description:  
-- A few PHY pins are defined with dual functionality, with one meaning at power-up or reset 
-- and another afterwards. This wrapper intercepts the I/Os to provide the 
-- necessary configuration at power-up/reset.
-- This component is written specifically for the Micrel KSZ9021RN part.
-- Other PHYs will require one to modify this component.
-- The strapping options and the length of the RESET_N pulse are defined at the time of HDL synthesis (see the constants within)
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity STRAPPING_OPTIONS is
    Port ( 
	 --// CLK
	 CLK: in std_logic;
		-- reference clock for synchronous design
	 
	 --// function selection from the HDL code
	 RESET_START: in std_logic;
		-- 1-CLK pulse to reset PHY IC and set the strapping options.
		-- MANDATORY: the PHY will stay in reset until a reset transaction occurs.
	 RESET_COMPLETE: out std_logic;
		-- '1' to indicate the end of this reset transaction. '1' while transaction is in progress.
	 
	 --// Main pin function, outputs to the HDL code
	 RX_CLK: out std_logic;
	 RXD: out std_logic_vector(3 downto 0);
	 RX_DV: out std_logic;
	 CLK125_NDO: out std_logic;
	 
	 --// Pin function at reset, inputs from the HDL code
	 PHYAD2: in std_logic;
	 MODE: in std_logic_vector(3 downto 0);
	 CLK125_EN: in std_logic;
	 LED_MODE: in std_logic;

	 --// PHY INTERFACE  (dual-mode pins)
	 RESET_N: out std_logic;
		-- hardware pin configurations are strapped-in at the de-assertion (rising edge)
		-- of RESET_N. 10ms long.
	 RX_CLK_PHYAD2: inout std_logic;
	 RXD3_MODE3: inout std_logic;
	 RXD2_MODE2: inout std_logic;
	 RXD1_MODE1: inout std_logic;
	 RXD0_MODE0: inout std_logic;
	 RX_DV_CLK125_EN: inout std_logic;
	 CLK125_NDO_LED_MODE: inout std_logic
	 
	 
);
end entity;

architecture Behavioral of STRAPPING_OPTIONS is
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal TIMER_COUNTER: std_logic_vector(20 downto 0) := '0' & x"00000";
	-- 21 bits to divide the CLK frequency by 2^21
	-- the objective is to generate a 10ms RESET_N pulse. Adjust vector length as needed.
	-- Example: CLK = 125 MHz clock. TIMER_COUNTER vector size is 21 bits
	-- The resulting RESET_N pulse length is 2^21/125E6 = 16.7ms > 10 ms
signal RESET_STARTED: std_logic := '0';
signal TIMER_EXPIRED: std_logic := '0';
signal RESET_COMPLETE_LOCAL: std_logic := '0';
signal RESET_N_D: std_logic := '0';
	

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

RESET_N_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(RESET_START = '1') then
			-- initialize timer
			TIMER_COUNTER <= (others => '1');
			RESET_STARTED <= '1';  -- reset in progress
		elsif(TIMER_EXPIRED = '0') then
			-- countdown until 0 (timer expired)
			TIMER_COUNTER <= TIMER_COUNTER - 1;  
		end if;
	end if;
end process;

-- timer has expired when zero
TIMER_EXPIRED <= '1' when (TIMER_COUNTER = 0) else '0';

RESET_N_GEN_002: process(CLK)
begin
	if rising_edge(CLK) then
		RESET_N_D <= TIMER_EXPIRED and RESET_STARTED;  -- output strapping options until 1 CLK AFTER RESET_N ends
	
		if(RESET_START = '1') then
			-- force to zero immediately upon start of reset
			RESET_COMPLETE_LOCAL <= '0';
		else
			RESET_COMPLETE_LOCAL <= TIMER_EXPIRED and RESET_STARTED;
		end if;
	end if;
end process;

RESET_COMPLETE <= '0' when (RESET_START = '1') else RESET_COMPLETE_LOCAL;
	-- force to zero immediately upon start of reset
	
	
--// OUTPUTS ----------------------
RESET_N <= TIMER_EXPIRED and RESET_STARTED;  -- active low reset

-- the PHY latches the strapping options during RESET_N
RX_CLK_PHYAD2 <= PHYAD2  when (RESET_N_D = '0') else 'Z';
RXD3_MODE3 <= MODE(3) when (RESET_N_D = '0') else 'Z';
RXD2_MODE2 <= MODE(2) when (RESET_N_D = '0') else 'Z';
RXD1_MODE1 <= MODE(1) when (RESET_N_D = '0') else 'Z';
RXD0_MODE0 <= MODE(0) when (RESET_N_D = '0') else 'Z';
RX_DV_CLK125_EN <= CLK125_EN when (RESET_N_D = '0') else 'Z';
CLK125_NDO_LED_MODE <= CLK125_NDO_LED_MODE when (RESET_N_D = '0') else 'Z';

--// INPUTS ------------------------
RX_CLK <= RX_CLK_PHYAD2;
RXD(3) <= RXD3_MODE3;
RXD(2) <= RXD2_MODE2;
RXD(1) <= RXD1_MODE1;
RXD(0) <= RXD0_MODE0;
RX_DV <= RX_DV_CLK125_EN;
CLK125_NDO <= CLK125_NDO_LED_MODE;

end Behavioral;

