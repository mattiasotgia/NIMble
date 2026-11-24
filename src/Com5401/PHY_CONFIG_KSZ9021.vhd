-------------------------------------------------------------
-- MSS copyright 2010-2016
--	Filename:  PHY_CONFIG_KSZ9021.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 7
--	Date last modified: 7/19/16
-- Inheritance: 	n/a
--
-- description:  Configures a PHY through a MDIO interface.
-- MII/GMII: see 802.3 22.2.4 Management functions
--   implementing reg0 control, reg1 status and reg2 phy ID 
-- RGMII: 
-- 
-- Rev 2  2-4-11 AZ 
-- added read for extended status registers.
--
-- Rev 3  11/19/11 AZ 
-- Added basic status report by reading the register 1 (link, duplex, speed)
-- Latch 
--
-- Rev 4 8/7/12 AZ
-- Additional signal initialization for simulation.
-- Force LINK_STATUS to '0' at reset.
-- More extensive use of SYNC_RESET
--
-- Rev 5 5/17/13 AZ
-- Defensive code: protected against another CONFIG_CHANGE while we are still processing the previous one. 
-- CONFIG_CHANGE is held in the mean time.
-- Corrected reading transaction for extended status registers
--
-- Rev 6 8/18/14 AZ
-- Better control of skew (using two control registers instead of just one)
--
-- Rev 7 7/19/16 AZ
-- Added generic parameter NO_1000 to advertise or not 1000Mbps capability. Default is yes.
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity PHY_CONFIG_KSZ9021 is
	generic (
		PHY_ADDR: std_logic_vector(4 downto 0);	-- PHY Address
		NO_1000: std_logic := '0'	
			-- '1' to stop advertising 1000Mbps capabilities during autonegotiations
			-- Use when 125 MHz clockk for GbE is too high for place and route
	);
    Port ( 
		--// CLK, RESET
		SYNC_RESET: in std_logic;
		CLK: in std_logic;
		
		--// CONTROLS
		CONFIG_CHANGE: in std_logic;
			-- 1 CLK-wide pulse to activate any configuration change below.
			-- Not needed if the default values are acceptable.
		PHY_RESET: in std_logic; 
			-- 1 = PHY software reset, 0 = no reset
		SPEED: in std_logic_vector(1 downto 0);
			-- 00 = force 10 Mbps
			-- 01 = force 100 Mbps
			-- 10 = force 1000 Mbps
			-- 11 = auto-negotiation (default)
		DUPLEX: in std_logic;
			-- 1 = full-duplex (default), 0 = half-duplex
		TEST_MODE: in std_logic_vector(1 downto 0);
			-- 00 = normal mode (default)
			-- 01 = loopback mode
			-- 10 = remote loopback
			-- 11 = led test mode
		POWER_DOWN: in std_logic;
			-- software power down mode. 1 = enabled, 0 = disabled (default).
		CLK_SKEW1: in std_logic_vector(15 downto 0);
			-- Register 260 RGMII clock and control pad skew
			-- Note: tested with Micrel KSZ9021 PHY. Should be altered to work with other PHYs (different vendors/models).
		CLK_SKEW2: in std_logic_vector(15 downto 0);
			-- Register 261 RGMII rx data pad skew
			-- Note: tested with Micrel KSZ9021 PHY. Should be altered to work with other PHYs (different vendors/models).

		--// MONITORING
		SREG_READ_START: in std_logic;
			-- 1 CLK wide pulse to start read transaction
			-- will be ignored if the previous transaction is yet to be completed.
		SREG_REGAD: in std_logic_vector(8 downto 0);	
			-- 32 register address space for the PHY (ieee 802.3)
			--  0 - 15 are standard PHY registers as per IEEE specification.
			-- 16 - 31 are vendor-specific registers
			-- 256+ are extended registers
		SREG_DATA : OUT std_logic_vector(15 downto 0);
			-- 16-bit status register. Read when SREG_SAMPLE_CLK = '1'
		SREG_SAMPLE_CLK: out std_logic;
		
		--// BASIC STATUS REPORT (status register 1)
		LINK_STATUS: out std_logic;  
			-- 0 = link down, 1 = link up
			
		--// serial interface. connect to PHY 
		MCLK: out std_logic;
		MDIO: inout std_logic;  -- (tri-state)
		
		--// TEST POINTS
		TP: out std_logic_vector(10 downto 1)
		
		
);
end entity;

architecture Behavioral of PHY_CONFIG_KSZ9021 is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
	COMPONENT MII_MI
	GENERIC (
		PHY_ADDR: std_logic_vector(4 downto 0)
	);	
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		MI_REGAD : IN std_logic_vector(4 downto 0);
		MI_TX_DATA : IN std_logic_vector(15 downto 0);
		MI_READ_START : IN std_logic;
		MI_WRITE_START : IN std_logic;    
		MDIO : INOUT std_logic;      
		MI_RX_DATA : OUT std_logic_vector(15 downto 0);
		MI_TRANSACTION_COMPLETE : OUT std_logic;
		MCLK : OUT std_logic
		);
	END COMPONENT;
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal CONFIG_CHANGE_PENDING_FLAG: std_logic:= '0';
signal PHY_RESET0: std_logic:= '0';
signal PHY_RESET_D: std_logic:= '0';
signal SPEED0: std_logic_vector(1 downto 0) := (others => '0');
signal SPEED_D: std_logic_vector(1 downto 0) := (others => '0');
signal DUPLEX0: std_logic:= '0';
signal DUPLEX_D: std_logic:= '0';
signal TEST_MODE0: std_logic_vector(1 downto 0) := (others => '0');
signal POWER_DOWN0: std_logic:= '0';
signal POWER_DOWN_D: std_logic:= '0';
signal CLK_SKEW10: std_logic_vector(15 downto 0):= (others => '0');
signal CLK_SKEW20: std_logic_vector(15 downto 0):= (others => '0');
signal CLK_SKEW1_D: std_logic_vector(15 downto 0):= (others => '0');
signal CLK_SKEW2_D: std_logic_vector(15 downto 0):= (others => '0');
signal STATE: std_logic_vector(4 downto 0) := (others => '0');
signal MI_WRITE_START: std_logic := '0';
signal MI_REGAD: std_logic_vector(4 downto 0) := "00000";
signal MI_TX_DATA: std_logic_vector(15 downto 0) := (others => '0');
signal MI_READ_START: std_logic := '0';
signal MI_RX_DATA: std_logic_vector(15 downto 0) := (others => '0');
signal MI_TRANSACTION_COMPLETE: std_logic:= '0';
signal LOOPBACK_MODE: std_logic:= '0';
signal AUTONEG: std_logic:= '0';
signal REMOTE_LOOPBACK: std_logic:= '0';
signal LED_TEST_MODE: std_logic:= '0';
signal SREG_SAMPLE_CLK_local: std_logic := '0';

constant RGMII_INBAND_STATUS_EN: std_logic := '1'; -- enable in-band status reporting in RGMII
--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

-- hold the configuration request until it is time to process it (state machine may be busy)
CONFIG_SAVE_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(CONFIG_CHANGE = '1') then
			CONFIG_CHANGE_PENDING_FLAG <= '1';
			PHY_RESET0 <= PHY_RESET;
			SPEED0 <= SPEED;
			DUPLEX0 <= DUPLEX;
			TEST_MODE0 <= TEST_MODE;
			POWER_DOWN0 <= POWER_DOWN;
			CLK_SKEW10 <= CLK_SKEW1;
			CLK_SKEW20 <= CLK_SKEW2;
		elsif(STATE = 0) and (CONFIG_CHANGE_PENDING_FLAG = '1') then
			CONFIG_CHANGE_PENDING_FLAG <= '0';
		end if;
	end if;
end process;


-- save the configuration so that it does not change while the configuration is in progress
RECLOCK_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(STATE = 0) and (CONFIG_CHANGE_PENDING_FLAG = '1') then
			PHY_RESET_D <= PHY_RESET0;
			SPEED_D <= SPEED0;
			DUPLEX_D <= DUPLEX0;
			POWER_DOWN_D <= POWER_DOWN0;
			CLK_SKEW1_D <= CLK_SKEW10;
			CLK_SKEW2_D <= CLK_SKEW20;
			
			if(SPEED0 = "11") then
				AUTONEG <= '1';
			else
				AUTONEG <= '0';
			end if;
			
			case TEST_MODE0 is
				when "00" => 
					LOOPBACK_MODE <= '0';
					REMOTE_LOOPBACK <= '0';
					LED_TEST_MODE <= '0';
				when "01" => 
					LOOPBACK_MODE <= '1';
					REMOTE_LOOPBACK <= '0';
					LED_TEST_MODE <= '0';
				when "10" => 
					LOOPBACK_MODE <= '0';
					REMOTE_LOOPBACK <= '1';
					LED_TEST_MODE <= '0';
				when others => 
					LOOPBACK_MODE <= '0';
					REMOTE_LOOPBACK <= '0';
					LED_TEST_MODE <= '1';
			end case;
		end if;
	end if;
end process;

-- state machine
STATE_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			STATE <= (others => '0');
			MI_REGAD <= (others => '0');
			MI_TX_DATA <= (others => '0');
			MI_WRITE_START <= '0';
			MI_READ_START <= '0';
			SREG_SAMPLE_CLK_local <= '0';
			LINK_STATUS <= '0';

		-- WRITE ALL CONFIGURATION REGISTERS
		elsif(STATE = 0) and (CONFIG_CHANGE_PENDING_FLAG = '1') then
			-- triggers a PHY reconfiguration. await PHY MDIO availability
			STATE <= STATE + 1;
			SREG_SAMPLE_CLK_local <= '0';

		elsif(STATE = 1) and (MI_TRANSACTION_COMPLETE = '1') then
			-- PHY is ready for next transaction.
			-- Register 0: basic control (applicable to all: GMII, MII, RGMII)
			STATE <= STATE + 1;
			MI_REGAD <= "00000";
			MI_TX_DATA(15 downto 8) <= PHY_RESET_D & LOOPBACK_MODE & SPEED_D(0) & AUTONEG & POWER_DOWN_D & "00" & DUPLEX_D;
			MI_TX_DATA(7 downto 0) <= "0" & SPEED_D(1) & "000000";
			MI_WRITE_START <= '1';
			
-- tested for Micrel KSZ9021RN -------
-- adjust as needed depending on the PHY 	(the extended registers vary depending on the manufacturer/model).		
		elsif(STATE = 2) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Register 17. vendor-specific register: Remote Loopback, LED Mode
			STATE <= STATE + 1;
			MI_REGAD <= "10001";  
			MI_TX_DATA(15 downto 8) <= "0000001" & REMOTE_LOOPBACK;
			MI_TX_DATA(7 downto 0) <= "1111" & LED_TEST_MODE & "000";
			MI_WRITE_START <= '1';
		elsif(STATE = 3) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 256 (1/2): common control
			STATE <= STATE + 1;
			MI_REGAD <= "01011";  
			MI_TX_DATA <= x"8100";  -- write to extended register 256
			MI_WRITE_START <= '1';
		elsif(STATE = 4) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 256 (2/2): common control
			STATE <= STATE + 1;
			MI_REGAD <= "01100";  
			MI_TX_DATA(15 downto 8) <= "0000000" & RGMII_INBAND_STATUS_EN;
			MI_TX_DATA(7 downto 0) <= x"02";  -- reserved (undocumented)
			MI_WRITE_START <= '1';
		elsif(STATE = 5) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 260 (1/2): RGMII clock and control pad skew
			STATE <= STATE + 1;
			MI_REGAD <= "01011";  
			MI_TX_DATA <= x"8104";  -- write to extended register 260
			MI_WRITE_START <= '1';
		elsif(STATE = 6) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 260 (2/2): RGMII clock and control pad skew
			STATE <= STATE + 1;
			MI_REGAD <= "01100";  
			MI_TX_DATA <= CLK_SKEW1_D;	-- RGMII clocks and control pad skew 7*0.2ns
			MI_WRITE_START <= '1';
		elsif(STATE = 7) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 261 (1/2): RGMII rx data pad skew
			STATE <= STATE + 1;
			MI_REGAD <= "01011";  
			MI_TX_DATA <= x"8105";  -- write to extended register 261
			MI_WRITE_START <= '1';
		elsif(STATE = 8) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 261 (2/2): RGMII rx data pad skew
			STATE <= STATE + 1;
			MI_REGAD <= "01100";  
			MI_TX_DATA <= CLK_SKEW2_D;	-- RGMII rx data pad skew 7*0.2ns
			MI_WRITE_START <= '1';
		elsif(STATE = 9) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- Extended register 9: 
			STATE <= STATE + 1;
			MI_REGAD <= "01001";  
			if(NO_1000 = '0') then
				MI_TX_DATA <= x"0300";	-- advertise 1000Mbps capability, half and full duplex
			else
				MI_TX_DATA <= x"0000";	-- advertise no 1000Mbps capability
			end if;
			MI_WRITE_START <= '1';
		elsif(STATE = 10) and (MI_TRANSACTION_COMPLETE = '1') then 
			-- we are done configuring! Going back to idle.
			STATE <= (others => '0');
			MI_WRITE_START <= '0';
			
			
		-- READ ONE STATUS REGISTER	
		elsif(STATE = 0) and (SREG_READ_START = '1') and (SREG_REGAD(8) = '0') then
			-- triggers a PHY status read. await PHY MDIO availability
			STATE <= "01100";
			SREG_SAMPLE_CLK_local <= '0';
		elsif(STATE = 12) and (MI_TRANSACTION_COMPLETE = '1') then
			-- PHY is ready for next transaction.
			STATE <= STATE + 1;
			MI_REGAD <= SREG_REGAD(4 downto 0);  
			MI_READ_START <= '1';
		elsif(STATE = 13) and (MI_TRANSACTION_COMPLETE = '1') then
			-- we are done reading a status register! Going back to idle.
			STATE <= (others => '0');
			MI_READ_START <= '0';
			SREG_SAMPLE_CLK_local <= '1';


		-- READ ONE EXTENDED REGISTER	
		elsif(STATE = 0) and (SREG_READ_START = '1') and (SREG_REGAD(8) = '1') then
			-- triggers extended status register  read. await PHY MDIO availability
			STATE <= "10000";
			SREG_SAMPLE_CLK_local <= '0';
		elsif(STATE = 16) and (MI_TRANSACTION_COMPLETE = '1')  then
			-- Extended register (1/2)
			STATE <= STATE + 1;
			MI_REGAD <= "01011";  
			MI_TX_DATA <= "0000000" & SREG_REGAD;  -- read extended register
			MI_WRITE_START <= '1';
		elsif(STATE = 17) and (MI_TRANSACTION_COMPLETE = '1') then
			-- triggers a PHY status read. await PHY MDIO availability
			STATE <= STATE + 1;
			MI_REGAD <= "01101";  
			MI_READ_START <= '1';
		elsif(STATE = 18) and (MI_TRANSACTION_COMPLETE = '1') then
			-- we are done reading a status register! Going back to idle.
			STATE <= (others => '0');
			MI_READ_START <= '0';
			SREG_SAMPLE_CLK_local <= '1';
			
		-- PERIODIC READ BASIC STATUS: LINK
		elsif(STATE = 0) and (MI_TRANSACTION_COMPLETE = '1') then
			-- Register 1: basic status (applicable to all: GMII, MII, RGMII)
			STATE <= "10011";
			MI_REGAD <= "00001";  
			MI_READ_START <= '1';
			SREG_SAMPLE_CLK_local <= '0';
		elsif(STATE = 19) and (MI_TRANSACTION_COMPLETE = '1') then
			-- we are done reading a status register! Going back to idle.
			STATE <= (others => '0');
			LINK_STATUS <= MI_RX_DATA(2);
			MI_READ_START <= '0';
			
		
		else
			MI_WRITE_START <= '0';
			MI_READ_START <= '0';
			SREG_SAMPLE_CLK_local <= '0';
		
		end if;
	end if;
end process;

-- latch status register
SREGOUT_001:  process(CLK)
begin
	if rising_edge(CLK) then
		SREG_SAMPLE_CLK <= SREG_SAMPLE_CLK_local;
		
		if(SREG_SAMPLE_CLK_local = '1') then
			SREG_DATA <= MI_RX_DATA;
		end if;
	end if;
end process;


Inst_MII_MI: MII_MI 
GENERIC MAP(
	PHY_ADDR => PHY_ADDR
)
PORT MAP(
	SYNC_RESET => SYNC_RESET,
	CLK => CLK,
	MI_REGAD => MI_REGAD,
	MI_TX_DATA => MI_TX_DATA,
	MI_RX_DATA => MI_RX_DATA,
	MI_READ_START => MI_READ_START,
	MI_WRITE_START => MI_WRITE_START,
	MI_TRANSACTION_COMPLETE => MI_TRANSACTION_COMPLETE,
	MCLK => MCLK,
	MDIO => MDIO
);

--// TEST POINTS -------------------------
TP(1) <= CONFIG_CHANGE;
TP(2) <= MI_TRANSACTION_COMPLETE;
TP(3) <= '1' when (STATE = 13) else '0';
TP(4) <= MI_WRITE_START;
TP(5) <= MI_READ_START;


end Behavioral;

