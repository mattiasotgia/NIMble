----------------------------------------------
-- MSS copyright 2013
-- Filename: COUNTER32BSEQUENCE.VHD
-- Authors: 
--		Alain Zarembowitch / MSS
-- Inheritance: n/a
-- Edit date: 11/10/13
-- Revision: 0
-- Description: 
--		Test sequence generator. Send 32-bit sequential numbers, one byte at a time. 
-- 	This can be helpful in determining whether there are gaps on the receiving end.
-- 	The MSB is sent first.   
---------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

entity COUNTER32BSEQUENCE is
  port (
	CLK: in  std_logic;   
		-- clock synchronous
	SYNC_RESET: in std_logic;
		-- synchronous reset, active high

	DATA_OUT: out std_logic_vector(7 downto 0);
		-- Output test sequence. Read at rising edge of CLK when SAMPLE_CLK_OUT = '1'
		-- MSb is first.
	SAMPLE_CLK_OUT: out std_logic := '0';
		-- one CLK wide pulse indicating that the DATA_OUT is ready. 
		-- Latency w.r.t. SAMPLE_CLK_OUT_REQ is two CLKs. 
	SAMPLE_CLK_OUT_REQ: in std_logic
		-- flow control
    );
end entity;

architecture behavior of COUNTER32BSEQUENCE is
-----------------------------------------------------------------
-- SIGNALS
-----------------------------------------------------------------
signal MOD4CNTR: std_logic_vector(1 downto 0) := (others => '1');
signal COUNTER32B: std_logic_vector (31 downto 0) := (others => '1');

-----------------------------------------------------------------
-- IMPLEMENTATION
-----------------------------------------------------------------
begin

-- modulo-4 byte counter
MODULO4_001: process(CLK)
begin
	if rising_edge(CLK) then
	
		if(SYNC_RESET = '1') then
			MOD4CNTR <= (others => '1');
			COUNTER32B <= (others => '1');
			SAMPLE_CLK_OUT <= '0';
		elsif(SAMPLE_CLK_OUT_REQ = '1') then
			SAMPLE_CLK_OUT <= '1';
			
			MOD4CNTR <= MOD4CNTR + 1;
			if(MOD4CNTR = 3) then
				COUNTER32B <= COUNTER32B + 1;
			end if;
		else
			SAMPLE_CLK_OUT <= '0';
		end if;
	end if;
end process;

MUX_OUT: process(MOD4CNTR, COUNTER32B)
begin
	case MOD4CNTR is
		when "00" => DATA_OUT <= COUNTER32B(31 downto 24);
		when "01" => DATA_OUT <= COUNTER32B(23 downto 16);
		when "10" => DATA_OUT <= COUNTER32B(15 downto 8);
		when others => DATA_OUT <= COUNTER32B(7 downto 0);
	end case;
end process;

  
end behavior;

