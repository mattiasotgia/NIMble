-------------------------------------------------------------
-- MSS copyright 2014-2018
--	Filename:  IGMP_REPORT.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 2
--	Date last modified: 12/2/18
-- Inheritance: 	n/a
--
-- description:  send an IGMP membership report out to whom it may concern
-- 
-- rev2 12/2/18 AZ
-- typo
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

entity IGMP_REPORT is
    Port ( 
		--// CLK, RESET
		SYNC_RESET: in std_logic;
		CLK: in std_logic;
		
		--// User interface
		MULTICAST_IP_ADDR: in std_logic_vector(31 downto 0);
			-- multicast IP address to report. 
		IGMP_START: in std_logic;
			-- 1 CLK pulse to start the IGMP report
			-- new requests will be ignored until the module is 
			-- finished with the previous request. 

		--// Configuration data: IP address, MAC address
		MAC_ADDR: in std_logic_vector(47 downto 0);
			-- local MAC address. Unique for each network interface card.
			-- Natural byte order: (MSB = REG32) 0x000102030405 (LSB = REG37) 
			-- as transmitted in the Ethernet packet.
		IPv4_ADDR: in std_logic_vector(31 downto 0);
			-- local IP address
			-- Natural order (MSB - REG0) 172.16.1.128 (LSB-REG3)
		IP_ID: in std_logic_vector(15 downto 0);
            -- 16-bit IP ID, unique for each IP frame. Incremented every time
            -- an IP frame is sent .

		--// Transmit frame/packet
		MAC_TX_DATA: out std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID: out std_logic;
			-- one CLK-wide pulse indicating a new word is sent on MAC_TX_DATA
		MAC_TX_EOF: out std_logic;
			-- End of Frame: one CLK-wide pulse indicating the last word in the transmit frame.
 		   -- aligned with MAC_TX_DATA_VALID.
		MAC_TX_CTS: in std_logic;
			-- 1 CLK-wide pulse requesting output samples. Check RTS first.
		RTS: out std_logic;
			-- '1' when a full or partial packet is ready to be read.
			-- '0' when output buffer is empty.
			-- When the user starts reading the output buffer, it is expected that it will be
			-- read until empty.

		-- Test Points
		TP: out std_logic_vector(10 downto 1)

			);
end entity;

architecture Behavioral of IGMP_REPORT is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
signal STATE: integer range 0 to 2 := 0;
signal MULTICAST_IP_ADDR_D: std_logic_vector(31 downto 0) := (others => '0');
signal MAC_TX_DATA_local: std_logic_vector(7 downto 0) := (others => '0');
signal MAC_TX_DATA_D: std_logic_vector(7 downto 0) := (others => '0');
signal TX_PACKET_SEQUENCE_E: unsigned(5 downto 0) := (others => '1');  
signal TX_PACKET_SEQUENCE_LSB: std_logic := '1';
signal MAC_TX_DATA_VALID_E: std_logic := '0';
signal MAC_TX_EOF_local: std_logic := '0';
signal RTS_local: std_logic := '0';
signal IP_HEADER_E: std_logic := '0';
signal IP_HEADER: std_logic := '0';
signal IGMP_FIELD_E: std_logic := '0';
signal IGMP_FIELD: std_logic := '0';
signal CKSUM: unsigned(16 downto 0) := (others => '0');
signal IP_HEADER_CKSUM: unsigned(15 downto 0) := (others => '0');
signal IGMP_CKSUM: unsigned(15 downto 0) := (others => '0');

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

--// Generate IGMP report
-- MAC_TX_DATA_local aligned with TX_PACKET_SEQUENCE
ARP_RESP_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
	    TX_PACKET_SEQUENCE_LSB <= TX_PACKET_SEQUENCE_E(0);
	    
		if(SYNC_RESET = '1') then
			MAC_TX_DATA_local <= (others => '0');
		else
			case(TX_PACKET_SEQUENCE_E) is
				-- Ethernet header
                -- reserved a block of Ethernet addresses that map on to the Class D multicast addresses
                -- The reserved address 0x0100.5e00.0000 is used by Ethernet to determine a unique multicast MAC				-- destination MAC address: multicast.
				when "000000" => MAC_TX_DATA_local <= x"01";
				when "000001" => MAC_TX_DATA_local <= x"00";
				when "000010" => MAC_TX_DATA_local <= x"5E";
				when "000011" => MAC_TX_DATA_local <= "0" & MULTICAST_IP_ADDR_D(22 downto 16);
				when "000100" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(15 downto 8);
				when "000101" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(7 downto 0);
				-- source Ethernet address
				when "000110" => MAC_TX_DATA_local <= MAC_ADDR(47 downto 40);	
				when "000111" => MAC_TX_DATA_local <= MAC_ADDR(39 downto 32);	
				when "001000" => MAC_TX_DATA_local <= MAC_ADDR(31 downto 24);		
				when "001001" => MAC_TX_DATA_local <= MAC_ADDR(23 downto 16);
				when "001010" => MAC_TX_DATA_local <= MAC_ADDR(15 downto 8);		
				when "001011" => MAC_TX_DATA_local <= MAC_ADDR(7 downto 0);
				-- Ethernet type
				when "001100" => MAC_TX_DATA_local <= x"08";	
				when "001101" => MAC_TX_DATA_local <= x"00";
				-- IP header
				when "001110" => MAC_TX_DATA_local <= x"46";	 -- IP version 4, 24-byte header length	
				when "001111" => MAC_TX_DATA_local <= x"00";	 -- DSCP 0
				when "010000" => MAC_TX_DATA_local <= x"00";   -- total length 32	
				when "010001" => MAC_TX_DATA_local <= x"20";
				when "010010" => MAC_TX_DATA_local <= IP_ID(15 downto 8);     -- IP ID	
				when "010011" => MAC_TX_DATA_local <= IP_ID(7 downto 0); 	
				when "010100" => MAC_TX_DATA_local <= x"00";  -- flags	
				when "010101" => MAC_TX_DATA_local <= x"00";  -- fragment offset	
				when "010110" => MAC_TX_DATA_local <= x"01";  -- TTL always 1	
				when "010111" => MAC_TX_DATA_local <= x"02";  -- protocol IGMP
				when "011000" => MAC_TX_DATA_local <= std_logic_vector(IP_HEADER_CKSUM(15 downto 8));  -- IP header checksum		
				when "011001" => MAC_TX_DATA_local <= std_logic_vector(IP_HEADER_CKSUM(7 downto 0));  -- IP header checksum	
				-- sender IP address
				when "011010" => MAC_TX_DATA_local <= IPv4_ADDR(31 downto 24);    	
				when "011011" => MAC_TX_DATA_local <= IPv4_ADDR(23 downto 16);
				when "011100" => MAC_TX_DATA_local <= IPv4_ADDR(15 downto 8);	
				when "011101" => MAC_TX_DATA_local <= IPv4_ADDR(7 downto 0);
				-- multicast IP address being reported
				when "011110" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(31 downto 24);	
				when "011111" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(23 downto 16);
				when "100000" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(15 downto 8);
				when "100001" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(7 downto 0);
				-- options
				when "100010" => MAC_TX_DATA_local <= x"94";	-- router alert: every router examines packet
				when "100011" => MAC_TX_DATA_local <= x"04";
				when "100100" => MAC_TX_DATA_local <= x"00";	
				when "100101" => MAC_TX_DATA_local <= x"00";		 
				-- IGMPv2
				when "100110" => MAC_TX_DATA_local <= x"16";	-- membership report	
				when "100111" => MAC_TX_DATA_local <= x"00";  -- maximum response time		
				when "101000" => MAC_TX_DATA_local <= std_logic_vector(IGMP_CKSUM(15 downto 8));	-- header checksum	
				when "101001" => MAC_TX_DATA_local <= std_logic_vector(IGMP_CKSUM(7 downto 0));	--
				when "101010" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(31 downto 24);	-- multicast address
				when "101011" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(23 downto 16);	
				when "101100" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(15 downto 8);	
				when "101101" => MAC_TX_DATA_local <= MULTICAST_IP_ADDR_D(7 downto 0);
				when others => MAC_TX_DATA_local <= x"00"; -- default & trailer	
			end case;
		end if;
	end if;
end process;
MAC_TX_DATA <= MAC_TX_DATA_local;

-- compute checksums (IP header, IGMP)
CKSUM_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') or ((IGMP_START = '1') and (STATE = 0)) then
		  MAC_TX_DATA_D <= (others => '0');
	      IP_HEADER <= '0';
          IGMP_FIELD <= '0';
          IP_HEADER_CKSUM <= (others => '0');
          IGMP_CKSUM <= (others => '0');
          CKSUM <= (others => '0');
	   else
	       -- compute checksums only during first pass (only time IP_HEADER and IGMP_FIELD are '1')
	      MAC_TX_DATA_D <= MAC_TX_DATA_local;
	      IP_HEADER <= IP_HEADER_E;
          IGMP_FIELD <= IGMP_FIELD_E;
          if(TX_PACKET_SEQUENCE_LSB = '1') and ((IP_HEADER = '1') or (IGMP_FIELD = '1')) then
                -- odd byte (i.e we have collected a 16-bit word)
                CKSUM <= ("0" & CKSUM(15 downto 0)) + 
                                   (x"0000" & CKSUM(16)) +
                                   unsigned("0" & MAC_TX_DATA_D & MAC_TX_DATA_local);
          else 
              -- at the end of the IP header field, latch in the checksum
              if(STATE = 1) and (TX_PACKET_SEQUENCE_E = 39) then
                --// final checksum
                -- don't forget to add the last carry immediately at the end of the IP header
                IP_HEADER_CKSUM <= not(CKSUM(15 downto 0) + ("000" & x"000" & CKSUM(16))) ;
                CKSUM <= (others => '0'); -- reset prior to IGMP checksum
              end if;    
              -- at the end of the IGMP field, latch in the checksum
              if(STATE = 2) then
                    -- don't forget to add the last carry immediately at the end of the IGMP field
                  IGMP_CKSUM <= not(CKSUM(15 downto 0) + ("000" & x"000" & CKSUM(16))) ;
              end if;    
          end if;
	   end if;
	end if;
end process;





-- two passes: one to compute checksum, the other to send data out to MAC
TX_SEQUENCE_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TX_PACKET_SEQUENCE_E <= (others => '1');
			MULTICAST_IP_ADDR_D <= (others => '0');
			MAC_TX_DATA_VALID_E <= '0';
			MAC_TX_DATA_VALID <= '0';
			IP_HEADER_E <= '0';
			IGMP_FIELD_E <= '0';
		else

			MAC_TX_DATA_VALID <= MAC_TX_DATA_VALID_E;  -- 1 clk delay in reading MAC_TX_DATA

			if(IGMP_START = '1') and (STATE = 0) then
				-- new transaction. Sending ARP request
				-- ready to send ARP request
				TX_PACKET_SEQUENCE_E <= "001110"; -- point to start of IP header
				IP_HEADER_E <= '1';
				-- save multicast IP address
				MULTICAST_IP_ADDR_D <= MULTICAST_IP_ADDR;
		    elsif(STATE = 1) then
		      if (TX_PACKET_SEQUENCE_E = "101101") then
		          -- end of IGMP field
				  IGMP_FIELD_E <= '0';
				  -- rewind pointer
			      TX_PACKET_SEQUENCE_E <= (others => '1');
		      elsif (TX_PACKET_SEQUENCE_E = "100101") then
		          -- end of IP header. Start of IGMP field
				  IP_HEADER_E <= '0';
				  IGMP_FIELD_E <= '1';
				  TX_PACKET_SEQUENCE_E <= TX_PACKET_SEQUENCE_E + 1;
		      else
		          -- still computing checksums
				  TX_PACKET_SEQUENCE_E <= TX_PACKET_SEQUENCE_E + 1;
		      end if;
			elsif(STATE = 2) and (MAC_TX_CTS = '1') and ((TX_PACKET_SEQUENCE_E < 45) or (TX_PACKET_SEQUENCE_E(5 downto 4) = "11"))then
				-- read the next word
				TX_PACKET_SEQUENCE_E <= TX_PACKET_SEQUENCE_E + 1;
				MAC_TX_DATA_VALID_E <= '1';
			else 
				MAC_TX_DATA_VALID_E <= '0';
			end if;
		end if;
	end if;
end process;

-- aligned with MAC_TX_DATA_VALID
MAC_TX_EOF_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			MAC_TX_EOF_local <= '0';
		else
			if(MAC_TX_DATA_VALID_E = '1') and (TX_PACKET_SEQUENCE_E = 45) then
				-- done. transmitting the last word
				MAC_TX_EOF_local <= '1';
			else
				MAC_TX_EOF_local <= '0';
			end if;
		end if;
	end if;
end process;
MAC_TX_EOF <= MAC_TX_EOF_local;

-- State machine
RTS_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RTS_local <= '0';
			STATE <= 0;
		else
			if(IGMP_START = '1') and (STATE = 0) then
                 -- new transaction. Compute checksums
                 STATE <= 1;
			elsif(STATE = 1) and  (TX_PACKET_SEQUENCE_E = "101101") then
			 -- checksum computations done. tell MAC that we got a frame ready to send
				 RTS_local <= '1';
			     STATE <= 2;
			elsif(MAC_TX_EOF_local = '1') then
				-- done. transmitting the last word
				RTS_local <= '0';
				STATE <= 0;
			end if;
		end if;
	end if;
end process;
RTS <= RTS_local;


--// Test Point
TP(1) <= IGMP_START;
TP(2) <= MAC_TX_CTS;
TP(3) <= MAC_TX_DATA_VALID_E;
TP(4) <= MAC_TX_EOF_local;
TP(5) <= RTS_local;

end Behavioral;
