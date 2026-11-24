-------------------------------------------------------------
-- MSS copyright 2011-2016
--	Filename:  LAN_TX_TEST.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 2
--	Date last modified: 4/16/16
-- Inheritance: 	N/A
--
-- description:  Generates periodic transmit packets to test the COM5401 transmit 10/100/1000 MAC.
-- Depending on the commented lines, the packet can be a 64-byte packet with
-- CRC-32 or a truncated packet (MAC must add padding + crc32)
--
-- Rev 2 4/16/16 AZ
-- Make sure there is no MAC_TX_EOF when MAC_TX_CTS = '0'
-- SYNC_RESET
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity LAN_TX_TEST is
	generic (
		CLK_FREQUENCY: integer := 120
			-- CLK frequency in MHz. Needed to compute actual delays.
	);
    Port ( 
		--// CLK, RESET
		CLK: in std_logic;
			-- GLOBAL CLOCK
		SYNC_RESET: in std_logic;
			-- reset pulse

		--// Transmit MAC Interface
		-- 32-bit CRC is automatically appended. User should not supply it.
		-- Synchonous with CLK
		MAC_TX_DATA: out std_logic_vector(7 downto 0);
			-- MAC reads the data at the rising edge of CLK when MAC_TX_DATA_VALID = '1'
		MAC_TX_DATA_VALID: out std_logic;
			-- data valid
		MAC_TX_EOF: out std_logic;
			-- '1' when sending the last byte in a packet to be transmitted. 
			-- Aligned with MAC_TX_DATA_VALID
		MAC_TX_CTS: in std_logic
			-- MAC-generated Clear To Send flow control signal. The user should check that this 
			-- signal is high before sending the next MAC_TX_DATA byte. 
			
 );
end entity;

architecture Behavioral of LAN_TX_TEST is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
-- NOTATIONS: 
-- _E as one-CLK early sample
-- _D as one-CLK delayed sample
-- _D2 as two-CLKs delayed sample
signal TIMER1: std_logic_vector(27 downto 0) := x"0000000";
constant TIMER1_VAL: integer := (CLK_FREQUENCY * 1000000) -1;
	-- the objective is to generate a 1s periodic pulse. 
signal T1S: std_logic;
signal TX_STARTED: std_logic := '0';

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

-- generate a 1s pulse
TIMER_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TIMER1 <= (others => '0');
			T1S <= '0';
		elsif(TIMER1 =  TIMER1_VAL) then
			TIMER1 <= (others => '0');
			T1S <= '1';
		else
			TIMER1 <= TIMER1 + 1;
			T1S <= '0';
		end if;
	end if;
end process;

TX_SEQUENCER: process(CLK)
begin
	if rising_edge(CLK) then
		case(TIMER1(6 downto 0)) is
			 when "0000000" => MAC_TX_DATA <= x"FF";
			 when "0000001" => MAC_TX_DATA <= x"FF";
			 when "0000010" => MAC_TX_DATA <= x"FF";
			 when "0000011" => MAC_TX_DATA <= x"FF";
			 when "0000100" => MAC_TX_DATA <= x"FF";
			 when "0000101" => MAC_TX_DATA <= x"FF";
			 when "0000110" => MAC_TX_DATA <= x"00";
			 when "0000111" => MAC_TX_DATA <= x"0E";
			 when "0001000" => MAC_TX_DATA <= x"08";
			 when "0001001" => MAC_TX_DATA <= x"CA";
			 when "0001010" => MAC_TX_DATA <= x"BB";
			 when "0001011" => MAC_TX_DATA <= x"A3";
			 when "0001100" => MAC_TX_DATA <= x"08";
			 when "0001101" => MAC_TX_DATA <= x"06";
			 when "0001110" => MAC_TX_DATA <= x"00";
			 when "0001111" => MAC_TX_DATA <= x"01";
			 when "0010000" => MAC_TX_DATA <= x"08";
			 when "0010001" => MAC_TX_DATA <= x"00";
			 when "0010010" => MAC_TX_DATA <= x"06";
			 when "0010011" => MAC_TX_DATA <= x"04";
			 when "0010100" => MAC_TX_DATA <= x"00";
			 when "0010101" => MAC_TX_DATA <= x"01";
			 when "0010110" => MAC_TX_DATA <= x"00";
			 when "0010111" => MAC_TX_DATA <= x"0E";
			 when "0011000" => MAC_TX_DATA <= x"08";
			 when "0011001" => MAC_TX_DATA <= x"CA";
			 when "0011010" => MAC_TX_DATA <= x"BB";
			 when "0011011" => MAC_TX_DATA <= x"A3";
			 when "0011100" => MAC_TX_DATA <= x"AC";
			 when "0011101" => MAC_TX_DATA <= x"10";
			 when "0011110" => MAC_TX_DATA <= x"01";
			 when "0011111" => MAC_TX_DATA <= x"7E";
			 when "0100000" => MAC_TX_DATA <= x"00";
			 when "0100001" => MAC_TX_DATA <= x"00";
			 when "0100010" => MAC_TX_DATA <= x"00";
			 when "0100011" => MAC_TX_DATA <= x"00";
			 when "0100100" => MAC_TX_DATA <= x"00";
			 when "0100101" => MAC_TX_DATA <= x"00";
			 when "0100110" => MAC_TX_DATA <= x"AC";
			 when "0100111" => MAC_TX_DATA <= x"10";
			 when "0101000" => MAC_TX_DATA <= x"01";
			 when "0101001" => MAC_TX_DATA <= x"1F";
			 when "0101010" => MAC_TX_DATA <= x"00";
			 when "0101011" => MAC_TX_DATA <= x"00";
			 when "0101100" => MAC_TX_DATA <= x"00";
			 when "0101101" => MAC_TX_DATA <= x"00";
			 when "0101110" => MAC_TX_DATA <= x"00";
			 when "0101111" => MAC_TX_DATA <= x"00";
			 when "0110000" => MAC_TX_DATA <= x"00";
			 when "0110001" => MAC_TX_DATA <= x"00";
			 when "0110010" => MAC_TX_DATA <= x"00";
			 when "0110011" => MAC_TX_DATA <= x"00";
			 when "0110100" => MAC_TX_DATA <= x"00";
			 when "0110101" => MAC_TX_DATA <= x"00";
			 when "0110110" => MAC_TX_DATA <= x"00";
			 when "0110111" => MAC_TX_DATA <= x"00";
			 when "0111000" => MAC_TX_DATA <= x"00";
			 when "0111001" => MAC_TX_DATA <= x"00";
			 when "0111010" => MAC_TX_DATA <= x"00";
			 when "0111011" => MAC_TX_DATA <= x"00";
			 when "0111100" => MAC_TX_DATA <= x"13";
			 when "0111101" => MAC_TX_DATA <= x"1B";
			 when "0111110" => MAC_TX_DATA <= x"C4";
			 when "0111111" => MAC_TX_DATA <= x"D3";
			 when others => MAC_TX_DATA <= x"00";
		end case;
	end if;
end process;

-- generate MAC_TX_DATA_VALID
TX_SEQUENCER2: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			MAC_TX_DATA_VALID <= '0';	
			MAC_TX_EOF <= '0';	
			TX_STARTED <= '0';
		elsif(MAC_TX_CTS = '1') and (T1S = '1') then
			MAC_TX_DATA_VALID <= '1';	-- first byte
			MAC_TX_EOF <= '0';	
			TX_STARTED <= '1';
--		elsif(TIMER1 = 63) and (TX_STARTED = '1') then	-- no pad/crc32 added
		elsif(TIMER1 = 41) and (TX_STARTED = '1') then -- mac must add pad + crc32
			MAC_TX_EOF <= '1';	-- last byte
			TX_STARTED <= '0';
--		elsif(TIMER1 = 64) then
		elsif(TIMER1 = 42) then
			MAC_TX_DATA_VALID <= '0';
			MAC_TX_EOF <= '0';	
		end if;
	end if;
end process;



end Behavioral;

