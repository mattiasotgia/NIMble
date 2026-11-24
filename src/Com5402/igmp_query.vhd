-------------------------------------------------------------
-- MSS copyright 2014
--	Filename:  IGMP_QUERY.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 1
--	Date last modified: 12/27/14
-- Inheritance: 	N/A
--
-- description:  detect a valid IGMP membership query and trigger a response when applicable 
-- 
-- Expects the following external validation checks (in PARSING):
-- MAC address(just multicast bit), IP type, IP header checksum
-- NO prior validation for complete MAC address, IP multicast destination address, IGMP checksum
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

entity IGMP_QUERY is
    Port ( 
		--// CLK, RESET
		CLK: in std_logic;
		SYNC_RESET: in std_logic;

        --// Configuration
		MULTICAST_IP_ADDR : IN std_logic_vector(31 downto 0);
        
		--// Received IP frame
		-- Excludes MAC layer header. Includes IP header.
		IP_RX_DATA: in std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID: in std_logic;	
		IP_RX_SOF: in std_logic;
		IP_RX_EOF: in std_logic;
		IP_BYTE_COUNT: in std_logic_vector(15 downto 0);	
		IP_HEADER_FLAG: in std_logic;
			-- latency: 2 CLKs after MAC_RX_DATA
			-- IP_BYTE_COUNT is reset at the start of the data field (i.e. immediately after the header)
			-- Always use IP_BYTE_COUNT using the IP_HEADER_FLAG context (inside or outside the IP header?)

		--// IP type, already parsed in PACKET_PARSING (shared code)
		RX_IP_PROTOCOL: in std_logic_vector(7 downto 0);
			-- The protocol information is valid as soon as the 8-bit IP protocol field in the IP header is read.
			-- Information stays until start of following packet.
			-- This component responds to protocol 2 = IGMP 
			-- latency: 3 CLK after IP protocol field at byte 9 of the IP header
	  	RX_IP_PROTOCOL_RDY: in std_logic;
			-- 1 CLK wide pulse. 
		RX_DEST_IP_ADDR: in std_logic_vector(31 downto 0);
		
		--// Output
		TRIGGER_RESPONSE: out std_logic;
		
		-- Test Points
		TP: out std_logic_vector(10 downto 1)

			);
end entity;

architecture Behavioral of IGMP_QUERY is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------

--// IGMP 16-BIT WORD -----------------------------
signal IP_RX_DATA_PREVIOUS: std_logic_vector(7 downto 0) := (others => '0');
signal IGMP_BYTE_COUNT: unsigned(15 downto 0) := (others => '0');
signal IP_RX_DATA16: unsigned(15 downto 0) := (others => '0');

--// CHECK IGMP QUERY VALIDITY -----------------------------
signal VALID_RX_IGMP: std_logic := '0';
signal IGMP_CKSUM: unsigned(16 downto 0) := (others => '0');
signal IGMP_CKSUM_VALID: std_logic := '0';
signal IGMP_CKSUM_VALID_RDY: std_logic := '0';
signal IP_RX_EOF_D: std_logic := '0';
signal IP_RX_EOF_D2: std_logic := '0';

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

IGMP_BYTE_COUNT <= unsigned(IP_BYTE_COUNT);	-- valid outside the IP header, inside the IGMP frame.

--// IGMP 16-BIT WORD -----------------------------
-- reconstruct 16-bit words
IGMP_PREVIOUS_BYTE_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(IP_RX_DATA_VALID = '1') and (IP_HEADER_FLAG = '0') then
			-- IGMP frame
			IP_RX_DATA_PREVIOUS <= IP_RX_DATA;	-- remember previous byte (useful when reading 16-bit fields)
		end if;
	end if;
end process;
IP_RX_DATA16 <= unsigned(IP_RX_DATA_PREVIOUS & IP_RX_DATA);	-- reconstruct 16-bit field. 

--// CHECK IGMP QUERY VALIDITY -----------------------------
-- The IGMP packet reception is immediately cancelled if 
-- (a) the received packet type is not an IP datagram  (done in common code PACKET_PARSING)
-- (b) invalid destination IP  
-- (c) incorrect IP header checksum (done in common code PACKET_PARSING)
-- (d) the received IP type is not IGMP 
-- (e) IGMP type is not membership request
-- (f) IGMP checksum is incorrect
-- Aligned with IP_RX_DATA_VALID_D
VALIDITY_CHECK_001: process(CLK)
begin
	if rising_edge(CLK) then
	   if(SYNC_RESET = '1') then
           VALID_RX_IGMP <= '1';
        elsif(IP_RX_SOF = '1') then
            -- just received first word. Valid UDP datagram until proven otherwise
            VALID_RX_IGMP <= '1';
        elsif(IGMP_BYTE_COUNT = 0) and (IP_HEADER_FLAG = '0') then
            if(RX_DEST_IP_ADDR /= MULTICAST_IP_ADDR) then 
                -- (b) IP address does not match 
                VALID_RX_IGMP <= '0';
            elsif (IP_RX_DATA /= x"11") then
                -- (e) IGMP type is not a membership request
                VALID_RX_IGMP <= '0';
            end if;

         elsif(IP_RX_EOF = '1') and (IP_RX_DATA_VALID = '0') then
            -- (c) invalid IP frame reported at the end of the IP frame.
            VALID_RX_IGMP <= '0';
        elsif(unsigned(RX_IP_PROTOCOL) /= 2) and (RX_IP_PROTOCOL_RDY = '1') then
            -- (d) the received IP type is not IGMP 
            VALID_RX_IGMP <= '0';
        elsif(IGMP_CKSUM_VALID_RDY = '1') and (IGMP_CKSUM_VALID = '0') then
            -- (f)  IGMP checksum is incorrect
            VALID_RX_IGMP <= '0';
        end if;
 	end if;
end process;


IP_HEADER_CHECKSUM_001: process(CLK)
begin
	if rising_edge(CLK) then
		IP_RX_EOF_D <= IP_RX_EOF;
		IP_RX_EOF_D2 <= IP_RX_EOF_D;

	    if(SYNC_RESET = '1') or (IP_RX_SOF = '1') then
			-- clear last checksum
			IGMP_CKSUM <= (others => '0');
			IGMP_CKSUM_VALID <= '0';
			IGMP_CKSUM_VALID_RDY <= '0';
		elsif (IP_RX_DATA_VALID = '1') and (IP_HEADER_FLAG = '0') and (IGMP_BYTE_COUNT(0) = '1') then 
			-- once every word (2 bytes) do 16-bit sum, 1's complement. If previous carry in IP_HEADER_CHECKSUM(16), add 1.
			IGMP_CKSUM <=  ("0" & IGMP_CKSUM(15 downto 0)) 
										+ ("0" & IP_RX_DATA16) + (x"0000" & IGMP_CKSUM(16)); 
	    elsif(IP_RX_EOF_D = '1') then
	       -- end of IGMP field. Correct for last carry and verify checksum.
			IGMP_CKSUM_VALID_RDY <= '1';
			if(IGMP_CKSUM(16 downto 0) = "0" & x"FFFF") then
               -- case1: no previous carry. Checksum OK
               IGMP_CKSUM_VALID <= '1';
            elsif(IGMP_CKSUM(16 downto 0) = "1" & x"FFFE") then
               -- case2: previous carry. Checksum OK
               IGMP_CKSUM_VALID <= '1';
            else
               IGMP_CKSUM_VALID <= '0';
            end if;
		else
			IGMP_CKSUM_VALID_RDY <= '0';
	   end if;
 	end if;
end process;

-- trigger a response to a query
TRIGGER_RESPONSE <= VALID_RX_IGMP and IP_RX_EOF_D2;


--// Test Point
-- N/A
end Behavioral;
