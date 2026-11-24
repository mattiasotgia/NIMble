--------------------------------------------------------------------------------
-- Company: 
-- Engineer:
--
-- Create Date:   09:19:04 03/07/2010
-- Design Name:   
-- Module Name:   C:/Users/Admin/Documents/VHDL source/com-5401/sim/tbSTRAPPING_OPTIONS.vhd
-- Project Name:  com-5401
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: STRAPPING_OPTIONS
-- 
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends
-- that these types always be used for the top-level I/O of a design in order
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.ALL;
 
ENTITY tbSTRAPPING_OPTIONS IS
END tbSTRAPPING_OPTIONS;
 
ARCHITECTURE behavior OF tbSTRAPPING_OPTIONS IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT STRAPPING_OPTIONS
    PORT(
         CLK : IN  std_logic;
         RESET_START : IN  std_logic;
         RESET_COMPLETE : OUT  std_logic;
         RX_CLK : OUT  std_logic;
         RXD : OUT  std_logic_vector(3 downto 0);
         RX_DV : OUT  std_logic;
         CLK125_NDO : OUT  std_logic;
         PHYAD2 : IN  std_logic;
         MODE : IN  std_logic_vector(3 downto 0);
         CLK125_EN : IN  std_logic;
         LED_MODE : IN  std_logic;
         RESET_N : OUT  std_logic;
         RX_CLK_PHYAD2 : INOUT  std_logic;
         RXD3_MODE3 : INOUT  std_logic;
         RXD2_MODE2 : INOUT  std_logic;
         RXD1_MODE1 : INOUT  std_logic;
         RXD0_MODE0 : INOUT  std_logic;
         RX_DV_CLK125_EN : INOUT  std_logic;
         CLK125_NDO_LED_MODE : INOUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal CLK : std_logic := '0';
   signal RESET_START : std_logic := '0';
   signal PHYAD2 : std_logic := '0';
   signal MODE : std_logic_vector(3 downto 0) := (others => '0');
   signal CLK125_EN : std_logic := '0';
   signal LED_MODE : std_logic := '0';

	--BiDirs
   signal RX_CLK_PHYAD2 : std_logic;
   signal RXD3_MODE3 : std_logic;
   signal RXD2_MODE2 : std_logic;
   signal RXD1_MODE1 : std_logic;
   signal RXD0_MODE0 : std_logic;
   signal RX_DV_CLK125_EN : std_logic;
   signal CLK125_NDO_LED_MODE : std_logic;

 	--Outputs
   signal RESET_COMPLETE : std_logic;
   signal RX_CLK : std_logic;
   signal RXD : std_logic_vector(3 downto 0);
   signal RX_DV : std_logic;
   signal CLK125_NDO : std_logic;
   signal RESET_N : std_logic;

   -- Clock period definitions
   constant CLK_period : time := 8 ns;
   constant RX_CLK_period : time := 8 ns;

   signal RX_CLK_LOCAL : std_logic;

 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: STRAPPING_OPTIONS PORT MAP (
          CLK => CLK,
          RESET_START => RESET_START,
          RESET_COMPLETE => RESET_COMPLETE,
          RX_CLK => RX_CLK,
          RXD => RXD,
          RX_DV => RX_DV,
          CLK125_NDO => CLK125_NDO,
          PHYAD2 => PHYAD2,
          MODE => MODE,
          CLK125_EN => CLK125_EN,
          LED_MODE => LED_MODE,
          RESET_N => RESET_N,
          RX_CLK_PHYAD2 => RX_CLK_PHYAD2,
          RXD3_MODE3 => RXD3_MODE3,
          RXD2_MODE2 => RXD2_MODE2,
          RXD1_MODE1 => RXD1_MODE1,
          RXD0_MODE0 => RXD0_MODE0,
          RX_DV_CLK125_EN => RX_DV_CLK125_EN,
          CLK125_NDO_LED_MODE => CLK125_NDO_LED_MODE
        );

   -- Clock process definitions
   CLK_process :process
   begin
		CLK <= '0';
		wait for CLK_period/2;
		CLK <= '1';
		wait for CLK_period/2;
   end process;
	
	-- user trigger
	TRIGGER_001: process
    begin
		RESET_START <= '0';
		wait for 1ms;
		RESET_START <= '1';
		wait for 8ns;
		RESET_START <= '0';
		wait;
   end process;
	
	-- user controls
	CLK125_EN <= '0';
	LED_MODE <= '0'; 
	PHYAD2 <= '0';
	MODE <= "0000";
	
	-- PHY outputs
	
   RX_CLK_process :process
   begin
		RX_CLK_LOCAL <= '0';
		wait for RX_CLK_period/2;
		RX_CLK_LOCAL <= '1';
		wait for RX_CLK_period/2;
   end process;
	
	RX_CLK_PHYAD2 <= 'Z' when (RESET_N = '0') else RX_CLK_LOCAL;
	CLK125_NDO_LED_MODE <= 'Z' when (RESET_N = '0') else (not RX_CLK_LOCAL);
	RXD3_MODE3 <= 'Z' when (RESET_N = '0') else '1';
	RXD2_MODE2 <= 'Z' when (RESET_N = '0') else '1';
	RXD1_MODE1 <= 'Z' when (RESET_N = '0') else '1';
	RXD0_MODE0 <= 'Z' when (RESET_N = '0') else '1';
	RX_DV_CLK125_EN <= 'Z' when (RESET_N = '0') else '1';
	

 


END;
