-------------------------------------------------------------
-- MSS copyright 2004-2023
--	Filename:  TCP_SERVER.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 20
--	Date last modified: 11/19/23
-- Inheritance: 	COM-5003 TCP_PROT5.VHD 9/17/09
--
-- description:  TCP protocol for a server. Tx and Rx. 
-- Server awaits connection from a client. Once the connection is established, bi-directional
-- data transmission can take place. 
-- One instantiation per port. 
-- This component is mainly a state machine. It avoids storing any packet data to keep size to its minimum.
-- Consequently, the rx data recipient should be able to backtrack and throw out the received packet if
-- proven invalid at the end. 
-- Likewise, the tx data source should be able to rewind and re-transmit previous data if the TCP client 
-- requests is.
-- Since this is a server, we do not know a priori whether the protocol is IPv4 or IPv6 (it depends on the client).
-- So each server is given two IP addresses, one for each IP version.
--
-- Rev2 11/2/11 AZ
-- Added TCP_ISN pipelining for better timing.
-- 
-- Rev 3 11/4/11 AZ
-- restricts the retransmission scheme to the connected state. 
--
-- Rev 4 8/7/12 AZ
-- Added simulation initializations
--
-- Rev 5 10/9/13 AZ
-- Transition to SYNC_RESET.
-- Improve concurrent events handling in TX_PACKET_TYPE_QUEUED
--
-- Rev 6 1/28/14 AZ
-- Send multiple rx window resize messages, one for each stream, when window size is no longer zero.
-- Increased EFF_RX_WINDOW_SIZE_PARTIAL precision to 17 bits to detect abnormal negative window size reports
--
-- Rev7 1/31/14 AZ
-- Updated sensitivity lists.
--
-- Rev 8 2/13/14 AZ
-- Corrected double SYN ACK during connection setup
-- Added individual RX_FREE_SPACE for each stream
--
-- Rev 9 4/13/14 AZ
-- Send an ACK upon receiving a non-zero length TCP frame, even if there is a gap in sequence.
-- Justification: otherwise sender/receiver can be deadlocked when an ACK is lost.
-- 
-- Rev 10 5/7/14 AZ
-- Corrected bug when client closes the connection (ack number not incremented)
--
-- Rev 11 6/27/16 AZ
-- Corrected bug in transmit retransmission when bi-directional data transmission
-- Corrected for case when server receives multiple (delayed)SYN messages
-- Corrected for TX_FLAGS changing before end of transmission while receiving a frame from a different source
--
-- Rev 12 7/14/16 AZ
-- Corrected issue with Windows OS taking 5 seconds to resume TCP transmission when the TCP transmit side 'thinks'
-- the rx window is zero, whereas the TCP rx side computes a small but non zero window in its rx buffer.
-- Solution: send an ACK to the TCP transmit side as soon as the rx buffer goes from near-full to enough room (threshold = 1 MSS)
--
-- Rev 13 12/3/16 AZ
-- Added support for optional keep-alive (RFC1122 4.2.3.6). Both sending probe and acknowledging rx keep alive probes
-- Added support for zero-window probe. Both sending multiple probes with one byte and acknowledging rx zero-window probes.
--
-- Rev 14 11/15/18 AZ
-- Corrected typo RX_TCP_WINDOW_SIZE(15 downto 1)
-- Switched to numeric_std library
-- individual TCP_KEEPALIVE_EN selection for each stream
-- added margin to TX_ACK_WINDOW_LENGTH_OUT because of delayed information on RX_FREE_SPACE
-- 
-- Rev 15 12/2/18 AZ
-- avoid getting stuck in TCP_STATE 2
-- new TCP_TXBUF (from 10G version)
-- 
-- Rev 16 1/16/20 AZ
-- Eliminated instability in the ack/retransmission feedback loop
--
-- Rev 17 1/19/23
-- update to reflect the changes tested in TCP_CLIENTS.vhd
--
-- Rev 18 2/18/23 AZ
-- Detected alternate zero-window probe method (Windows10?)
--
-- Rev 19 8/19/23 AZ
-- Corrected RX_OUT_OF_BOUND2 being 1 CLK too late
--
-- Rev 20 11/19/23 AZ
-- re-instated GAP_IN_RX_SEQ to detect out of order rx packets
-- as per jacob@peoplechips.co.kr
--
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.com5402pkg.all;	-- defines global types, number of TCP streams, etc

entity TCP_SERVER is
	generic (
		NTCPSTREAMS: integer := 1;  
			-- number of concurrent TCP streams handled by this component
		MSS: integer := 1460;
			-- The Maximum Segment Size (MSS) is the largest segment of TCP data that can be transmitted.
			-- Fixed as the Ethernet MTU (Maximum Transmission Unit) of 1500-9000 bytes - 40(IPv4) or -60(IPv6) overhead bytes 
		TCP_KEEPALIVE_PERIOD: integer := 60;
			-- period in seconds for sending a keep-alive frame after no data and no ack is received. 
			-- "Typically TCP Keepalives are sent every 45 or 60 seconds on an idle TCP connection, and the connection is 
			-- dropped after 3 sequential ACKs are missed" 
		IPv6_ENABLED: std_logic := '0';
			-- 0 to minimize size, 1 to allow IPv6 in addition to IPv4 (larger size)
		SIMULATION: std_logic := '0'
			-- 1 during simulation. for example to fix the tx_seq_no so that it matches the Wireshark 
			-- captures. 
	);
    Port ( 
		--// CLK, RESET, TIME
		CLK: in std_logic;	
			-- Must be a global clock. No BUFG instantiation within this component.
		SYNC_RESET: in std_logic;

		TICK_4US: in std_logic;
		TICK_100MS: in std_logic;
			-- 1 CLK-wide pulse every 4us and 10ms

		--// Configuration Fields
		MAC_ADDR: in std_logic_vector(47 downto 0);
			-- MAC address. Unique for each network interface card.
			-- Natural byte order: (MSB) 0x000102030405 (LSB) 
			-- as transmitted in the Ethernet packet.
		TCP_LOCAL_PORTS: in SLV16xNTCPSTREAMStype;
			-- TCP_SERVER port configuration. Each one of the NTCPSTREAMS streams handled by this
			-- component must be configured with a distinct port number. 
			-- This value is used as destination port number to filter incoming packets, 
			-- and as source port number in outgoing packets.

		--// User-initiated connection reset for stream I
		CONNECTION_RESET: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		TCP_KEEPALIVE_EN: in std_logic_vector((NTCPSTREAMS-1) downto 0);
			-- enable TCP Keepalive (1) or not (0)

		--// Received IP frame from MAC layer
		-- Excludes MAC and Ethernet layer headers. Includes IP header.
		-- Pre-processed by PACKET_PARSING to extract key Ethernet, IP and TCP information (see below)
		IP_RX_DATA: in std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID: in std_logic;	
		IP_RX_SOF: in std_logic;
		IP_RX_EOF: in std_logic;
		IP_BYTE_COUNT: in std_logic_vector(15 downto 0);	
		IP_HEADER_FLAG: in std_logic;
			-- latency: 2 CLKs after MAC_RX_DATA
			-- As the IP frame validity is checked on-the-fly, the user should always check if 
			-- the IP_RX_DATA_VALID is high AT THE END of the IP frame (IP_RX_EOF) to confirm that the 
			-- ENTIRE IP frame is valid. Validity checks already performed (in PACKET_PARSING) are 
			-- (a) destination IP address matches
			-- (b) protocol is IP
			-- (c) correct IP header checksum
			-- IP_BYTE_COUNT is reset at the start of the data field (i.e. immediately after the header)
			-- Always use IP_BYTE_COUNT using the IP_HEADER_FLAG context (inside or outside the IP header?)

		--// IP type, already parsed in PACKET_PARSING (shared code)
		RX_IPv4_6n: in std_logic;
			-- IP version. 4 or 6
		RX_IP_PROTOCOL: in std_logic_vector(7 downto 0);
			-- The protocol information is valid as soon as the 8-bit IP protocol field in the IP header is read.
			-- Information stays until start of following packet.
			-- This component responds to protocol 6 = TCP 
	  	RX_IP_PROTOCOL_RDY: in std_logic;
			-- 1 CLK wide pulse. 
			
		--// Packet origin, already parsed in PACKET_PARSING (shared code)
		RX_SOURCE_MAC_ADDR: in std_logic_vector(47 downto 0);
		RX_SOURCE_IP_ADDR: in std_logic_vector(127 downto 0);
		RX_SOURCE_TCP_PORT_NO: in std_logic_vector(15 downto 0);

		--// TCP attributes, already parsed in PACKET_PARSING (shared code)
		-- BEWARE!!!!!!!! WE ALSO RECEIVE PACKETS NOT DESTINED FOR THIS SESSION (NOT FOR  THIS PORT)
		-- IT IS THE IMPLEMENTATION'S RESPONSIBILITY TO DISCARD DATA NOT DESTINED FOR THIS TCP PORT.
		RX_TCP_HEADER_FLAG: in std_logic;
			-- outlines the TCP header. Aligned with IP_RX_....
		RX_TCP_FLAGS: in std_logic_vector(7 downto 0);
			-- TCP flags (MSb) CWR/ECE/URG/ACK/PSH/RST/SYN/FIN (LSb)
		RX_TCP_CKSUM: in std_logic_vector(16 downto 0);
			-- TCP checksum (including pseudo-header).
			-- Correct checksum is either x10000 or x00001. Read 1 clk after IP_RX_EOF
		RX_TCP_SEQ_NO: in std_logic_vector(31 downto 0);
			-- sequence number decoded from the incoming TCP segment 
		RX_TCP_ACK_NO: in std_logic_vector(31 downto 0);
			-- acknowledgement number decoded from the incoming TCP segment
		RX_TCP_WINDOW_SIZE: in std_logic_vector(15 downto 0);
			-- window size decoded from the incoming TCP segment 
		RX_DEST_TCP_PORT_NO: in std_logic_vector(15 downto 0);
			-- destination TCP port (IDENTIFIES THE STREAM #)
			
		--// RX TCP PAYLOAD -> EXTERNAL RX BUFFER 
		-- Latency: 2 CLKs after the received IP frame.
		RX_DATA: out std_logic_vector(7 downto 0);
			-- TCP payload data field when RX_DATA_VALID = '1'
		RX_DATA_VALID: out std_logic;
			-- delineates the TCP payload data field
		RX_SOF: out std_logic;
			-- 1 CLK pulse indicating that RX_DATA is the first byte in the TCP data field.
		RX_STREAM_SEL: out std_logic_vector((NTCPSTREAMS-1) downto 0);
			-- output port based on the destination TCP port
		RX_EOF: out std_logic;
			-- 1 CLK pulse indicating that RX_DATA is the last byte in the TCP data field.
			-- ALWAYS CHECK RX_DATA_VALID at the end of packet (RX_EOF = '1') to confirm
			-- that the TCP packet is valid. External buffer may have to backtrack to the the last
			-- valid pointer to discard an invalid TCP packet.
			-- Reason: we only knows about bad TCP packets at the end.
		RX_FREE_SPACE: in SLV16xNTCPSTREAMStype;
			-- External buffer available space, expressed in bytes. 
			-- Information is updated upon receiving the EOF of a valid rx frame.
			-- The real-time available space is always larger

		--// OUTPUTS to TX PACKET ASSEMBLY (via TCP_TX.vhd component)
		TX_PACKET_SEQUENCE_START_OUT: out std_logic;	
			-- 1 CLK pulse to trigger packet transmission. The decision to transmit is taken by TCP_SERVER.
			-- From this trigger pulse to the end of frame, this component assembles and send data bytes
			-- like clockwork. 
			-- Note that the payload data has to be ready at exactly the right time to be appended.
			
		-- These variables are read only at the start of packet, when TX_PACKET_SEQUENCE_START_OUT = '1'
		-- They can change from packet to packet (internal code is memoryless).
		TX_DEST_MAC_ADDR_OUT: out std_logic_vector(47 downto 0);
		TX_DEST_IP_ADDR_OUT: out std_logic_vector(127 downto 0);
		TX_DEST_PORT_NO_OUT: out std_logic_vector(15 downto 0);
		TX_SOURCE_PORT_NO_OUT: out std_logic_vector(15 downto 0);
		TX_IPv4_6n_OUT: out std_logic;
		TX_SEQ_NO_OUT: out std_logic_vector(31 downto 0);
		TX_ACK_NO_OUT: out std_logic_vector(31 downto 0);
		TX_ACK_WINDOW_LENGTH_OUT: out std_logic_vector(15 downto 0);
		TX_FLAGS_OUT: out std_logic_vector(7 downto 0);
		TX_PACKET_TYPE_OUT : out std_logic_vector(1 downto 0); 
			-- 0 = undefined
			-- 1 = SYN, no data, 24-byte header
			-- 2 = ACK, no data, 20-byte header
			-- 3 = payload data, 20-byte header


			

--		--// TX TCP layer -> Transmit MAC Interface
		MAC_TX_EOF: in std_logic;	-- need to know when packet tx is complete
		RTS: out std_logic := '0';
			-- '1' when a frame is ready to be sent (tell the COM5402 arbiter)
			-- When the MAC starts reading the output buffer, it is expected that it will be
			-- read until empty.

		--// EXTERNAL TX BUFFER <-> TX TCP layer
		-- upon receiving an ACK from the client, send rx window information to TXBUF for computing 
		-- the next packet size, boundaries, etc.
		-- Partial computation (rx window size + RX_TCP_ACK_NO).
		EFF_RX_WINDOW_SIZE_PARTIAL: out std_logic_vector(16 downto 0) := (others => '0');
			-- Explanation: EFF_RX_WINDOW_SIZE_PARTIAL represents the maximum TX_SEQ_NO acceptable for the 
			-- TCP client (beyond which the rx buffers would be overflowing)
		EFF_RX_WINDOW_SIZE_PARTIAL_STREAM: out std_logic_vector(NTCPSTREAMS-1 downto 0) := (others => '0');
		EFF_RX_WINDOW_SIZE_PARTIAL_VALID: out std_logic; -- 1 CLK-wide pulse to indicate that the above information is valid
		-- Let the TXBUF know where the next byte to be transmitted is located
		-- computing the next frame size, boundaries, etc
		TX_SEQ_NO: out SLV17xNTCPSTREAMStype := (others => (others => '0'));
		TX_SEQ_NO_JUMP: out std_logic_vector(NTCPSTREAMS-1 downto 0) := (others => '0');
		      -- TX_SEQ_NO progresses regularly as new bytes are being transmitted, except when TX_SEQ_NO_JUMP(I) = '1'
		RX_TCP_ACK_NO_D: out SLV17xNTCPSTREAMStype := (others => (others => '0'));
			-- last acknowledged tx byte location


		CONNECTED_FLAG: out std_logic_vector((NTCPSTREAMS-1) downto 0);
			-- '1' when TCP-IP connection is in the 'connected' state, 0 otherwise
			-- Main use: TXBUF should not store tx data until a connection is established

		TX_STREAM_SEL: in std_logic_vector((NTCPSTREAMS-1) downto 0);
			-- valid only when TX_PAYLOAD_RTS = '1', ignore otherwise
		TX_PAYLOAD_RTS: in std_logic;
			-- '1' when at least one stream has payload data available for transmission.
		TX_PAYLOAD_SIZE: in std_logic_vector(15 downto 0);
		
	
		
		
		-- Test Points
		TP: out std_logic_vector(10 downto 1)

			);
end entity;

architecture Behavioral of TCP_SERVER is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
-- Suffix _D indicates a one CLK delayed version of the net with the same name
-- Suffix _E indicates a one CLK early version of the net with the same name
-- Suffix _X indicates an extended precision version of the net with the same name
-- Suffix _N indicates an inverted version of the net with the same name

--//===== COMMON ==========================================
signal TICK_CNTR: unsigned(3 downto 0) := "0000";
signal TICK_1S: std_logic := '0';

--//===== NON-VOLATILE PORT-SPECIFIC DATA ==================
-- (to be saved after a packet ends) 
-- state machine
type STATEtype is array (integer range 0 to (NTCPSTREAMS-1)) of integer range 0 to 15; -- (i.e. 4-bits)
signal TCP_STATE: STATEtype := (others => 0);
signal TIMER1: U8xNTCPSTREAMStype := (others => (others => '0'));	-- timer range 0 - 25.5s
signal CONNECTED_FLAG_local: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
-- keep-alive timer
signal TIMER2: U8xNTCPSTREAMStype := (others => (others => '0'));	-- timer range 0 - 255s
signal TIMER2_D: U8xNTCPSTREAMStype := (others => (others => '0'));	-- timer range 0 - 255s
signal KASTATE: U2xNTCPSTREAMStype:= (others => (others => '0'));	-- keep alive state
-- zero-window probe timer
signal ZWS: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal TIMER3: U8xNTCPSTREAMStype := (others => (others => '0'));	-- timer range 0 - 25.5s
constant ZERO_WINDOW_PROBE_PERIOD: integer := 3;	-- first interval to send zero-window probe (in 100ms units)
signal ZWP_STATE: U4xNTCPSTREAMStype:= (others => (others => '0'));	-- zero-window probe state
signal ZWP_TRIGGER: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');

-- relevant transmit destination information
type MAC_ADDRtype is array (integer range 0 to (NTCPSTREAMS-1)) of std_logic_vector(47 downto 0);
type IP_ADDRtype is array (integer range 0 to (NTCPSTREAMS-1)) of std_logic_vector(127 downto 0);
signal TX_DEST_MAC_ADDR: MAC_ADDRtype := (others => (others => '0'));
signal TX_DEST_IP_ADDR: IP_ADDRtype := (others => (others => '0'));
signal TX_DEST_PORT_NO: SLV16xNTCPSTREAMStype := (others => (others => '0'));
-- tx sequence numbers
signal TX_ACK_NO: U32xNTCPSTREAMStype := (others => (others => '0'));
signal TX_ACK_NO2: unsigned(31 downto 0) := (others => '0');
signal TX_SEQ_NO_local: U32xNTCPSTREAMStype := (others => (others => '0'));
signal TX_SEQ_NO_OUT_local: U32xNTCPSTREAMStype := (others => (others => '0'));
-- received sequence number
signal RX_TCP_ACK_NO_D_local: U32xNTCPSTREAMStype := (others => (others => '0'));
signal RX_TCP_SEQ_NO_MAX2: unsigned(31 downto 0) := (others => '0');
signal RX_TCP_SEQ_NO_MIN2: unsigned(31 downto 0) := (others => '0');
signal TX_IPv4_6n: std_logic_vector((NTCPSTREAMS-1) downto 0);
signal TX_PACKET_TYPE_QUEUED: SLV2xNTCPSTREAMStype := (others => (others => '0'));
signal TX_PACKET_TYPE: std_logic_vector(1 downto 0) := "00";
signal TX_FLAGS: SLV8xNTCPSTREAMStype := (others => (others => '0'));


--//==== VARIABLES WITH A 1 PACKET LIFESPAN ==================
-- TCP stream identification ------------------
signal RX_TCP_STREAM_SEL: std_logic_vector(NTCPSTREAMS-1 downto 0) := (others => '0');
signal RX_TCP_STREAM_SEL_D: std_logic_vector(NTCPSTREAMS-1 downto 0) := (others => '0');
signal RX_TCP_STREAM_SEL_RDY: std_logic := '0';
signal RX_TCP_STREAM_SEL_RDY_D: std_logic := '0';
signal IP_PAYLOAD_SOF: std_logic := '0';
signal IP_PAYLOAD_EOF: std_logic := '0';
signal IP_PAYLOAD_EOF_D: std_logic := '0';

--// CHECK RX TCP VALIDITY 
signal VALID_TCP_CKSUM: std_logic := '0';
signal VALID_RX_TCP0: std_logic := '0';
signal VALID_RX_TCP_ALL: std_logic := '0';
signal VALID_RX_TCP2: std_logic := '0';	-- aligned with RX_EOF_E
signal VALID_RX_TCP2_D: std_logic := '0';	
signal TCP_RX_EOF_D: std_logic := '0';	

--// COPY RX TCP DATA TO BUFFER 
signal RX_DATA_E: std_logic_vector(7 downto 0) := (others => '0');
signal RX_DATA_VALID_E: std_logic := '0';
signal RX_DATA_VALID_local: std_logic := '0';
signal RX_SOF_E: std_logic := '0';
signal RX_EOF_E: std_logic := '0';
signal RX_EOF_local: std_logic := '0';
signal RX_WPTR_E: unsigned(31 downto 0) := (others => '0');
signal RX_WPTR_E_INC: unsigned(31 downto 0) := (others => '0');
signal RX_TCP_HEADER_FLAG_D: std_logic := '0';
signal RX_TCP_NON_ZERO_DATA_LENGTH: std_logic := '0';

--// RX SEQUENCE NUMBER
signal RX_TCP_SEQ_NO_RDY: std_logic := '0';
signal RX_TCP_SEQ_NO_INC: unsigned(31 downto 0) := (others => '0');
signal RX_OUTOFBOUND2: std_logic := '0';
signal RX_OUTOFBOUND2_D: std_logic := '0';
signal UPDATE_TX_ACK_NO: std_logic := '0';
signal FIRST_RXTCP_BYTE_OUTOFRANGE: std_logic := '0';
signal RX_ZERO_WINDOW_PROBE: std_logic := '0';
signal GAP_IN_RX_SEQ: std_logic := '0';
signal RETRANSMIT_FLAG: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal TX_SEQ_NO_JUMP_local: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal TX_SEQ_NO_JUMP_D: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal RX_VALID_ACK_TIMOUT: U24xNTCPSTREAMStype;

--// state machine
signal TCP_STATE_localrx: integer range 0 to 15 := 0;
signal EVENTS2: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS4: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS4A: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS4B: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS4C: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS5: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS7: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS10: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS11: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENTS12: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal EVENT1: std_logic:= '0';
signal EVENT2: std_logic:= '0';
signal EVENT4: std_logic:= '0';
signal EVENT4A: std_logic:= '0';
signal EVENT4B: std_logic:= '0';
signal EVENT6: std_logic:= '0';
signal EVENT8: std_logic:= '0';

----// ACK generation
signal SEND_ACK_NOW: std_logic:= '0';
signal DUPLICATE_RX_TCP_ACK_CNTR: U2xNTCPSTREAMStype := (others => (others => '0'));

-- Keep-Alive probe sequence detection
signal KA_PROBE_DET: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');

--// relevant transmit destination information
signal ORIGINATOR_IDENTIFIED: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal RX_BUF_FULL: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal RX_BUF_1MSSFREE: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal TX_ACK_WINDOW_LENGTH: unsigned(15 downto 0) := (others => '0');
signal RX_WINDOW_RESIZE_STATE: SLV2xNTCPSTREAMStype := (others => (others => '0'));
signal SEND_RX_WINDOW_RESIZE: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal RX_WINDOW_RESIZE2_STATE: SLV2xNTCPSTREAMStype := (others => (others => '0'));
signal SEND_RX_WINDOW_RESIZE2: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');


--// Measure round-trip delay: client -> server -> client
signal TXRX_DELAY_CNTR: U24xNTCPSTREAMStype := (others => (others => '0'));
signal TXRX_DELAY: U24xNTCPSTREAMStype := (others => (others => '0'));
signal TXRX_DELAY_STATE: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');


--// transmit packet assembly
signal TCP_ISN: unsigned(31 downto 0) := x"010ae614";
signal TCP_ISN_D: unsigned(31 downto 0) := x"010ae614";
constant TX_TCP_RTS: std_logic := '0';  -- temp

-- TCP transmit flow control -------------------
signal EFF_RX_WINDOW_SIZE_PARTIAL_local: unsigned(16 downto 0) := (others => '0');

--//---- TX PACKET ASSEMBLY   
signal TCP_CONGESTION_WINDOW: U16xNTCPSTREAMStype;
signal TCP_TX_SLOW_START: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal NEXT_TX_TCP_FRAME_QUEUED: std_logic := '0';
signal NEXT_TX_TCP_STREAM_SEL: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal TX_TCP_STREAM_SEL: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal RTS_local: std_logic := '0';
signal TX_PACKET_SEQUENCE_START: std_logic := '0';

--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

TICK_1S_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(TICK_100MS = '1') then
			if(TICK_CNTR = 9) then
				TICK_CNTR <= (others => '0');
				TICK_1S <= '1';
			else
				TICK_CNTR <= TICK_CNTR + 1;
				TICK_1S <= '0';
			end if;
		else
			TICK_1S <= '0';
		end if;
	end if;
end process;

-------------------------------------------------
---- TCP stream identification ------------------
-------------------------------------------------
-- Identify the stream based on the destination tcp port for each 
-- incoming frame.
-- Valid from first IP_RX_DATA after the destination port until next IP_RX_SOF (included)
STREAM_INDEX_001: process(RX_DEST_TCP_PORT_NO, TCP_LOCAL_PORTS)
begin
	for I in 0 to (NTCPSTREAMS-1) loop
		if(RX_DEST_TCP_PORT_NO  = TCP_LOCAL_PORTS(I)) then
		    RX_TCP_STREAM_SEL(I) <= '1';
		else
		    RX_TCP_STREAM_SEL(I) <= '0';
		end if;
	end loop;
end process;
RX_TCP_STREAM_SEL_RDY <= '1' when (RX_TCP_HEADER_FLAG = '1') and (unsigned(IP_BYTE_COUNT(4 downto 0)) = 4) else '0';

IP_PAYLOAD_SOF <= '1' when (IP_RX_DATA_VALID = '1') and (RX_TCP_HEADER_FLAG = '1') and (unsigned(IP_BYTE_COUNT(4 downto 0)) = 0) else '0';
	-- 1 CLK pulse to mark the first byte of IP payload (i.e. TCP header first byte)
IP_PAYLOAD_EOF <= IP_RX_DATA_VALID and IP_RX_EOF;
	-- 1 CLK pulse to mark the last byte of IP payload 
	
-- reclock for better timing
STREAM_INDEX_002: process(CLK)
begin
	if rising_edge(CLK) then
	   RX_TCP_STREAM_SEL_D <= RX_TCP_STREAM_SEL;
		RX_TCP_STREAM_SEL_RDY_D <= RX_TCP_STREAM_SEL_RDY;
	end if;
end process;

-- Demux and freeze key fields based on the current rx stream
DEMUX_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(RX_TCP_STREAM_SEL_RDY_D = '1') then
			for I in 0 to NTCPSTREAMS-1 loop
				if(RX_TCP_STREAM_SEL_D(I) = '1') then
				    -- changes typically at two events: end of valid rx frame and when RX_FREE_SPACE changes
					RX_TCP_SEQ_NO_MAX2 <= TX_ACK_NO(I) + unsigned(RX_FREE_SPACE(I));	
					RX_TCP_SEQ_NO_MIN2 <= TX_ACK_NO(I);
				end if;
			end loop;
		end if;
	end if;
end process;

-- *121218 simplify/do not delay
DEMUX_002: process(CLK)
begin
	if rising_edge(CLK) then
		for I in 0 to NTCPSTREAMS-1 loop
			 if(RX_TCP_STREAM_SEL_D(I) = '1') then
				 TX_ACK_NO2 <= unsigned(TX_ACK_NO(I));
			 end if;
		end loop;
	end if;
end process;

-------------------------------------------------
---- Collect response information ---------------
-------------------------------------------------
-- save destination IP, destination port and other relevant information
-- upon receiving SYN. The information will be kept until the connection is closed.
INFO_X: for I in 0 to (NTCPSTREAMS-1) generate
	INFO_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(RX_TCP_STREAM_SEL_D(I) = '1') and (TCP_STATE(I) = 0) and (EVENT1 = '1') then
				-- Received valid SYN while in LISTEN state
				-- Save the destination addresses during the connection
				TX_DEST_MAC_ADDR(I) <= RX_SOURCE_MAC_ADDR;	
				TX_DEST_IP_ADDR(I) <= RX_SOURCE_IP_ADDR;	
				TX_DEST_PORT_NO(I) <= RX_SOURCE_TCP_PORT_NO;	
				TX_IPv4_6n(I) <= RX_IPv4_6n;
			end if;
		end if;
	end process;
end generate;

-- After the initial SYN message where the originator identification characteristics
-- are collected (MAC/IP/PORT), the origination of subsequent messages addressed 
-- to this IP/Port is verified. (we don't want a third party to crash our connection
-- by sending RST or other disrupting messages.
-- Information is valid at the end of the TCP header until the next received packet.
ORIGIN_001: process(CLK) 
begin
	if rising_edge(CLK) then
		for I in 0 to (NTCPSTREAMS-1) loop
			if(TX_DEST_MAC_ADDR(I) = RX_SOURCE_MAC_ADDR) and 
				(TX_DEST_IP_ADDR(I) = RX_SOURCE_IP_ADDR) and 
				(TX_DEST_PORT_NO(I) = RX_SOURCE_TCP_PORT_NO)  then
				ORIGINATOR_IDENTIFIED(I) <= '1';
			else
				ORIGINATOR_IDENTIFIED(I) <= '0';
			end if;
		end loop;
	end if;
end process;
	

---------------------------------------------------
------ State Machine / Events ---------------------
---------------------------------------------------
-- received packet is for this port and from the correct originator: make it a pulse
VALID_RX_TCP2 <= '1' when (TCP_RX_EOF_D = '1') and (VALID_RX_TCP_ALL = '1') else '0';

-- independent state machine for each server
TCP_STATE_X: for I in 0 to (NTCPSTREAMS-1) generate

	-- EVENTS2(I)
	-- End of TCP segment transmission. Exclude the end of data frames. 
	EVENTS2(I) <= '1' when (TX_TCP_STREAM_SEL(I) = '1') and (MAC_TX_EOF = '1') and (TX_PACKET_TYPE = "10") else '0';

	-- EVENTS4(I): received valid ACK flag and ACK number from the connection client. Wait until the end of frame to confirm validity.
	EVENTS4(I) <= EVENTS12(I) when (RX_TCP_FLAGS(4) = '1') else '0';
	-- Events 4A: received valid non-duplicate ACK (a subset of EVENTS4)
	EVENTS4A(I) <= EVENTS4(I) when (RX_TCP_ACK_NO_D_local(I)(15 downto 0) /= unsigned(RX_TCP_ACK_NO(15 downto 0))) else '0';
	-- Events 4B: received valid duplicate ACK (a subset of EVENTS4)
	EVENTS4B(I) <= EVENTS4(I) when (RX_TCP_ACK_NO_D_local(I)(15 downto 0) = unsigned(RX_TCP_ACK_NO(15 downto 0))) else '0';
	-- Events 4C: received expected ACK number = previous transmit sequence number + 1 or payload length
	EVENTS4C(I) <= EVENTS4(I) when (TX_SEQ_NO_local(I)(15 downto 0) = unsigned(RX_TCP_ACK_NO(15 downto 0))) else '0';

	-- EVENTS5(I)
	-- Received valid FIN flag from expected server. Wait until the end of frame to confirm validity.
	EVENTS5(I) <= '1' when (RX_TCP_STREAM_SEL_D(I) = '1') and 
							(VALID_RX_TCP2 = '1') and (RX_TCP_FLAGS(0) = '1') 
							else '0';

	-- EVENTS7(I)
	-- Received valid RST flag from the connection server
	EVENTS7(I) <= '1' when (RX_TCP_STREAM_SEL_D(I) = '1') and 
							(VALID_RX_TCP2 = '1') and (RX_TCP_FLAGS(2) = '1') 
							else '0';
							
	-- EVENTS10(I)
	-- Window resizing (receive flow control), no segment to transmit. The receive buffer is no 
	-- longer empty. Send a single ACK with a non-zero window.
	EVENTS10(I) <= '1' when (((SEND_RX_WINDOW_RESIZE(I) = '1') or (SEND_RX_WINDOW_RESIZE2(I) = '1')) and (TX_TCP_RTS = '0')) else '0';

	-- EVENTS11(I)
	-- keep-alive or zero-window check: RFC: "send a probe segment designed to elicit a response from the
	-- peer TCP.  Such a segment generally contains SEG.SEQ = SND.NXT-1
	EVENTS11(I) <= '1' when ((TCP_KEEPALIVE_EN(I) = '1') and (TIMER2_D(I) /= 0) and (TIMER2(I) = 0) and (TX_TCP_RTS = '0')) else 
						ZWP_TRIGGER(I);

	-- EVENTS12(I)
	-- Receiving a valid TCP frame or ACK for stream I from expected client
	EVENTS12(I) <= '1' when (RX_TCP_STREAM_SEL_D(I) = '1')  and 
							(VALID_RX_TCP2 = '1') else '0';
	
	-- Note: removed state 2 because in the SYN/SYN ACK/ACK sequence
	-- if the ACK and only the ACK is dropped, the connection becomes established. If more things are dropped, there is a reset.
	TCP_STATE_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				-- reset all connections (abrupt, may cause server side to remain connected, thus preventing any further connection on that port)
				TCP_STATE(I) <= 0;
			elsif(CONNECTED_FLAG_local(I) = '1') and (CONNECTION_RESET(I) = '1') then
				-- user-initiated selective connection request while connected
				TCP_STATE(I) <= 6;	-- send FIN
			elsif(CONNECTED_FLAG_local(I) = '1') and (TCP_KEEPALIVE_EN(I) = '1') and (KASTATE(I) = 0) then
				-- failed keepalive. Automatic disconnect.
				TCP_STATE(I) <= 6;	-- send FIN

			-- rx-related events
			elsif(EVENTS7(I) = '1') then
				-- Reset / Abort (true in any state, as long as we verify the originator)
				-- received RST
				TCP_STATE(I) <= 0;
			elsif(RX_TCP_STREAM_SEL_D(I) = '1') and (TCP_STATE(I) = 0)  and (EVENT1 = '1') then
				-- LISTEN
				-- Received valid SYN
				TCP_STATE(I) <= 1;	-- SYN_RCVD. Transmitting SYN,ACK in progress
			elsif(TCP_STATE(I) = 2) and (EVENTS4C(I) = '1') then
				-- CONNECTION ESTABLISHMENT: Await ACK from client
				-- received valid ACK and ACK number
				TCP_STATE(I) <= 3;	-- CONNECTED state
			elsif(CONNECTED_FLAG_local(I) = '1') and (EVENTS5(I) = '1') then
				-- client-initiated connection termination . Send ACK
				TCP_STATE(I) <= 4;	-- sending ACK
			elsif (TCP_STATE(I) = 7) and (EVENTS5(I) = '1') then
				-- received FIN after FIN. Send final ACK.
				TCP_STATE(I) <= 8;	
			elsif (TCP_STATE(I) = 5) and (EVENTS4(I) = '1') then	
				-- received final ACK after FIN/ACK+FIN. Connection is properly closed.
				TCP_STATE(I) <= 0;	
			

			-- tx-related events (end of transmission)
			elsif (TCP_STATE(I) = 6) and (EVENTS2(I) = '1') and (TX_FLAGS(I)(0) = '1') then
				-- sent FIN. Awaiting ACK + FIN
				TCP_STATE(I) <= 7;	
			elsif (TCP_STATE(I) = 8) and (EVENTS2(I) = '1') and (TX_FLAGS(I)(4) = '1') then
				-- Sent final ACK. Connection is properly closed
				TCP_STATE(I) <= 0;
			elsif (TCP_STATE(I) = 4) and (EVENTS2(I) = '1') and (TX_FLAGS(I)(4) = '1') then
				-- sent ACK after receiving FIN. send final FIN. Await final ack.
				TCP_STATE(I) <= 5;	
			elsif(TX_TCP_STREAM_SEL(I) = '1') and (TCP_STATE(I) = 1) and (EVENT2 = '1') then 
				-- Sent SYN/ACK. Awaiting ACK (not essential). 
				TCP_STATE(I) <= 2;	-- CONNECTED state
--			elsif(TX_TCP_STREAM_SEL(I) = '1') and (TCP_STATE(I) = 4) and (EVENT2 = '1') then
--				-- CONNECTION TERMINATION: await end of ACK transmission
--				-- completed ACK transmission
--				TCP_STATE(I) <= 5;	-- await end of FIN/ACK transmission
--			elsif(TX_TCP_STREAM_SEL(I) = '1') and (TCP_STATE(I) = 5) and (EVENT2 = '1') then
--				-- CONNECTION TERMINATION: await end of FIN/ACK transmission
--				-- completed FIN/ACK transmission
--				-- don't wait for an ACK from client (race condition: next connection SYN could arrive first)
--				TCP_STATE(I) <= 0;	-- LISTEN STATE
				
			-- timeouts
			elsif ((TCP_STATE(I) = 6) or (TCP_STATE(I) = 7) or (TCP_STATE(I) = 8)) and (TIMER1(I)= 0) then
				-- timeout waiting for normal server-originated connection termination. Abnormal connection termination.
				TCP_STATE(I) <= 0;
			elsif ((TCP_STATE(I) = 4) or (TCP_STATE(I) = 5)) and (TIMER1(I)= 0) then
				-- timeout waiting for normal client-originated connection termination. Abnormal connection termination.
				TCP_STATE(I) <= 0;
				
			end if;
		end if;
	end process;

	--// TCP-IP connection status
	-- report TCP-IP connection status to TCP_TXBUF
	CONNECTED_FLAG_local(I) <= '1' when (TCP_STATE(I) = 3) or (TCP_STATE(I) = 2) else '0';	-- *120218
	CONNECTED_FLAG(I) <= CONNECTED_FLAG_local(I);

	-- state machine timer (so that we do not get stuck into a state)
	TIMER1_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				-- reset all connections (abrupt, may cause other side to remain connected, thus preventing any further connection on that port)
				-- idle state, clear timer to 'expired' (0)
				TIMER1(I) <= (others => '0');
			elsif(CONNECTED_FLAG_local(I) = '1') and (CONNECTION_RESET(I) = '1') then
				-- user-initiated selective connection request while connected
				TIMER1(I) <= to_unsigned(20, TIMER1(I)'length);
			elsif(CONNECTED_FLAG_local(I) = '1') and (TCP_KEEPALIVE_EN(I) = '1') and (KASTATE(I) = 0) then
				-- failed keepalive. Disconnect.
				TIMER1(I) <= to_unsigned(20, TIMER1(I)'length);
			elsif (CONNECTED_FLAG_local(I) = '1') and (EVENTS5(I) = '1') then
				-- client-initiated connection termination . 
				TIMER1(I) <= to_unsigned(20, TIMER1(I)'length);
			elsif(TCP_STATE(I) = 0) then
				-- idle state, clear timer to 'expired' (0)
				TIMER1(I) <= (others => '0');
			elsif(TICK_100MS = '1') and (TIMER1(I) /= 0) then
				-- decrement until timer has expired (0)
				TIMER1(I) <= TIMER1(I) - 1;
			end if;
		end if;
	end process;
end generate;

-- contextual TCP_STATE while receiving a frame
RX_TCP_STATE_GEN: process(RX_TCP_STREAM_SEL_D, TCP_STATE)
variable TCP_STATEv: integer;
begin  
    TCP_STATEv := 0; 
	for I in 0 to (NTCPSTREAMS-1) loop
	   if(RX_TCP_STREAM_SEL_D(I) = '1') then
	       TCP_STATEv := TCP_STATE(I);
	   end if;
    end loop;
    TCP_STATE_localrx <= TCP_STATEv;
end process; 
	
-- keep-alive timer
-- Send zero-data length keep alive message when TIMER2 = 0
-- TIMER2 is expressed in 1s units
TIMER2_GEN_X: for I in 0 to (NTCPSTREAMS-1) generate
	TIMER2_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			TIMER2_D(I) <= TIMER2(I);

			if(SYNC_RESET = '1') or (CONNECTED_FLAG_local(I) = '0') or (TCP_KEEPALIVE_EN(I) = '0') then
				-- reset or not connected state or keepalive not enabled
				TIMER2(I) <= to_unsigned(TCP_KEEPALIVE_PERIOD, TIMER2(I)'length);
			elsif(EVENTS12(I) = '1') then
				-- received data or ACK from client I. re-arm keepalive timer
				TIMER2(I) <= to_unsigned(TCP_KEEPALIVE_PERIOD, TIMER2(I)'length);
			elsif(NEXT_TX_TCP_STREAM_SEL(I) = '1') and (NEXT_TX_TCP_FRAME_QUEUED = '1') and (RTS_local = '0') then
				-- sending a frame to client. re-arm keepalive timer
				TIMER2(I) <= to_unsigned(TCP_KEEPALIVE_PERIOD, TIMER2(I)'length);
			elsif((TICK_1S = '1') and (TIMER2(I) /= 0)) then
				-- decrement until timer has expired (0)
				TIMER2(I) <= TIMER2(I) - 1;
			end if;
		end if;
	end process;

-- detect broken connection: keepalive message sent, ack or no ack received
-- Algo: set KASTATE to 3 when receiving ACK, decrement every timeout. Broken link when 0
	TIMER2_GEN_002: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') or (CONNECTED_FLAG_local(I) = '0') or (TCP_KEEPALIVE_EN(I) = '0') then
				-- reset or not connected state or keepalive not enabled
				KASTATE(I) <= "11";	-- awaiting ACK from client
			elsif(EVENTS12(I) = '1') then
				-- received data or ACK from client I
				KASTATE(I) <= "11";
			elsif((TICK_1S = '1') and (TIMER2(I) = 1))  then
				-- keepalive timeout. Send a probe with no data				
				if(KASTATE(I) /= 0) then
					KASTATE(I) <= KASTATE(I) - 1;
				end if;
			end if;
		end if;
	end process;
end generate;
-- connection status in KASTATE(I)(1)
				
--// zero-window probe timer
-- Keep track of zero-window sizes (yes/no) reported by the other side of the TCP connection
ZWS_GEN_X: for I in 0 to (NTCPSTREAMS-1) generate
	ZWS_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') or (CONNECTED_FLAG_local(I) = '0') then
				ZWS(I) <= '0';
			elsif(EVENTS4(I) = '1') then 
				-- Valid ACK received for stream RX_TCP_STREAM_SEL_D 
				if(unsigned(RX_TCP_WINDOW_SIZE) = 0) then
					ZWS(I) <= '1';
				else
					ZWS(I) <= '0';
				end if;
			end if;
		end if;
	end process;

	-- Send zero-window probe message when TIMER3 = 0
	-- TIMER3 is expressed in 100ms units
	-- ZERO_WINDOW_PROBE_PERIOD = minimum interval to send zero-window probe (in 100ms units)
	TIMER3_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') or (CONNECTED_FLAG_local(I) = '0') or (ZWS(I) = '0')then
				-- reset or not connected state or keepalive not enabled
				TIMER3(I) <= to_unsigned(ZERO_WINDOW_PROBE_PERIOD, TIMER3(I)'length);
			elsif((TICK_100MS = '1') and (TIMER3(I) = 0) and (ZWP_STATE(I)(3) = '0')) then
				-- timer3 expired (0) => send zero-window probe. 
				-- Re-arm timer3. Increase period between successive zero-window probes.
				case ZWP_STATE(I) is
					when "0000" => TIMER3(I) <= to_unsigned(ZERO_WINDOW_PROBE_PERIOD, TIMER3(I)'length);	-- 0.3s
					when "0001" => TIMER3(I) <= to_unsigned(2*ZERO_WINDOW_PROBE_PERIOD, TIMER3(I)'length);-- 0.6s
					when "0010" => TIMER3(I) <= to_unsigned(4*ZERO_WINDOW_PROBE_PERIOD, TIMER3(I)'length);-- 1.2s
					when "0011" => TIMER3(I) <= to_unsigned(8*ZERO_WINDOW_PROBE_PERIOD, TIMER3(I)'length);-- 2.4s
					when others => TIMER3(I) <= to_unsigned(16*ZERO_WINDOW_PROBE_PERIOD, TIMER3(I)'length);-- 5.8s
				end case;
			elsif((TICK_100MS = '1') and (TIMER3(I) /= 0)) then
				-- decrement until timer has expired (0)
				TIMER3(I) <= TIMER3(I) - 1;
			end if;
		end if;
	end process;
	
	-- slowly increase time between successive zero window probes
	-- ZWP_STATE(I) goes from 0 to 8 and stays there until connection is reset or zero-window condition disappears.
	TIMER3_GEN_002: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') or (CONNECTED_FLAG_local(I) = '0') or (ZWS(I) = '0')then
				-- reset or not connected state or keepalive not enabled
				ZWP_STATE(I) <= (others => '0');	
			elsif((TICK_100MS = '1') and (TIMER3(I) = 0) and (ZWP_STATE(I)(3) = '0')) then
				-- slowly increase time between successive zero window probes
				ZWP_STATE(I) <= ZWP_STATE(I) + 1;	
			end if;
		end if;
	end process;
	
	ZWP_TRIGGER(I) <= '1' when ((TICK_100MS = '1') and (TIMER3(I) = 0))  else '0';
	
end generate;

---------------------------------------------------
------ State Machine EVENTS -----------------------
---------------------------------------------------
-- Event 1: receive valid SYN flag (from anyone). Wait until the end of frame to confirm validity.
EVENT1 <= '1' when (RX_EOF_E = '1') and (VALID_RX_TCP_ALL = '1') and (RX_TCP_FLAGS(1) = '1') else '0';

-- Event 2: completed transmission of TCP segment.
EVENT2 <= MAC_TX_EOF;  

-- Event 4: received valid ACK flag and ACK number from the connection client
-- Event 4A: received valid non-duplicate ACK (a subset of EVENT4)
-- Event 4B: received valid duplicate ACK (a subset of EVENT4)
EVENT4_GENX: process(RX_TCP_STREAM_SEL_D, EVENTS4, EVENTS4A, EVENTS4B)
variable EVENT4var: std_logic;
variable EVENT4Avar: std_logic;
variable EVENT4Bvar: std_logic;
begin
	EVENT4var := '0';
	EVENT4Avar := '0';
	EVENT4Bvar := '0';
	for I in 0 to NTCPSTREAMS-1 loop
		if(RX_TCP_STREAM_SEL_D(I) = '1') then
			EVENT4var := EVENTS4(I);
			EVENT4Avar := EVENTS4A(I);
			EVENT4Bvar := EVENTS4B(I);
		end if;
	end loop;
	EVENT4 <= EVENT4var;
	EVENT4A <= EVENT4Avar;
	EVENT4B <= EVENT4Bvar;
end process;

-- Event 6
-- received valid segment, no segment to transmit. generate ACK only.
EVENT6 <= '1' when ((SEND_ACK_NOW = '1') and (TX_TCP_RTS = '0')) else '0'; 

-- Event 8
-- data is ready to be transmitted over TCP. Send data.  A distinct tx state machine is located 
-- in TCP_TXBUF together with the transmit buffers. 
-- Block sending until we receive a valid ACK from the previous transmission
-- A frame is ready for transmission when 
-- (a) the effective client rx window size is non-zero
-- (b) the tx buffer contains either the effective client rx window size or 1023 bytes or no new data received in the last 200us
-- (c) TCP is not busy transmitting/assembling another packet
-- implied condition: TCP is in connected state (3) otherwise TX_PAYLOAD_RTS = '0'
EVENT8 <= '1' when ((TX_PAYLOAD_RTS = '1') and (RTS_local = '0')) else '0';

-------------------------------------------------
---- Receive data -------------------------------
-------------------------------------------------

--// CHECK RX TCP VALIDITY -----------------------------
-- overall TCP validity. Can also be used in the case of zero-length TCP data fields)
-- Partial verification done prior to the TCP payload field, 
-- Final verification is aligned with IP_PAYLOAD_EOF_D
-- Invalidity criteria:
-- (a) the received packet type is not an IP datagram  (done in common code PACKET_PARSING)
-- (b) invalid destination IP  (done in common code PACKET_PARSING)
-- (c) incorrect IP header checksum (done in common code PACKET_PARSING)
-- (d) the received IP type is not TCP 
-- (e) destination port number is not the specified TCP_LOCAL_PORTS
-- (f) TCP checksum is incorrect
-- (g) TCP connection is established and origin MAC/IP/Port is invalid
VALIDITY_CHECK_001: process(CLK)
begin
	if rising_edge(CLK) then
		IP_PAYLOAD_EOF_D <= IP_PAYLOAD_EOF;
		VALID_RX_TCP2_D <= VALID_RX_TCP2;

		if(SYNC_RESET = '1') or (IP_PAYLOAD_SOF = '1') then
			if(unsigned(RX_IP_PROTOCOL) /= 6) then
				-- not TCP
				VALID_RX_TCP0 <= '0';
			else
				-- valid unless proven otherwise
				VALID_RX_TCP0 <= '1';
			end if;
		elsif(IP_PAYLOAD_EOF = '1') then
			-- most checks performed at the end of frame
			if(IP_RX_DATA_VALID = '0') then
				-- (a) the received packet type is not an IP datagram  (done in common code PACKET_PARSING)
				-- (b) invalid destination IP  (done in common code PACKET_PARSING)
				-- (c) incorrect IP header checksum (done in common code PACKET_PARSING)
				-- (e) Ethernet frame is valid (correct FCS, dest address)
				VALID_RX_TCP0 <= '0';
			elsif (unsigned(RX_TCP_STREAM_SEL_D) = 0) then
				-- (e) destination port number does not match any of the specified TCP_LOCAL_PORTS
				VALID_RX_TCP0 <= '0';
			elsif (TCP_STATE_localrx = 3) and (ORIGINATOR_IDENTIFIED /= RX_TCP_STREAM_SEL_D) then
				-- (g) TCP connection is established and origin MAC/IP/Port is inconsistent (spoof detection)
				VALID_RX_TCP0 <= '0';
			end if;
		elsif(IP_PAYLOAD_EOF_D = '1') then
			if(VALID_TCP_CKSUM = '0') then
				VALID_RX_TCP0 <= '0';
			end if;
		end if;
	end if;
end process;

-- late arrival (one CLK after IP_RX_EOF)
VALID_TCP_CKSUM <= '1' when ((RX_TCP_CKSUM = "1" & x"0000") or (RX_TCP_CKSUM = "0" & x"0001") ) else '0';
		--(f) TCP checksum is incorrect
		-- NOTE: this check is performed while reading the last TCP byte. The outcome is available
		-- one clock AFTER the TCP_EOF

-- overall TCP validity (All above criteria. Can also be used in the case of zero-length TCP data fields)
-- read at RX_EOF_E
-- Note: additional checks must be performed to forward data to the output data sink (TCP state = connected, 
-- enough space in data sink to accept the data).
VALID_RX_TCP_ALL <= VALID_TCP_CKSUM and VALID_RX_TCP0;

			

--// COPY TCP DATA TO OUTPUT BUFFER ------------------------

-- Prepare output. Strip IP and TCP headers.
-- Aligned with IP_RX_DATA_VALID_D
OUTPUT_GEN_001a: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_DATA_E <= (others => '0');
			RX_DATA_VALID_E <= '0';
			RX_TCP_HEADER_FLAG_D <= '0';
		else
			RX_TCP_HEADER_FLAG_D <= RX_TCP_HEADER_FLAG;
			if(IP_RX_DATA_VALID = '1') and (IP_RX_SOF = '1') then 
				RX_DATA_VALID_E <= '0';
			elsif(IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0') and 
				(RX_TCP_HEADER_FLAG = '0') and (GAP_IN_RX_SEQ = '0') and (RX_OUTOFBOUND2 = '0') then --*111923	
				-- Strip IP and TCP headers. Data field starts after TCP header.
				-- write byte to buffer as long as there is meaningful and valid TCP data, not filler.
				-- No point in writing non-TCP data to the rx buffer in the first place (those pesky
				-- NetBUI packets fill-up pretty fast, even if we rewind the write pointer at the next valid
				-- TCP packet)
				-- Do not forward data to the rx buffer if the client 
				-- is doing a zero window-length probe (i.e. writing past the declared max)
				RX_DATA_E <= IP_RX_DATA;
				RX_DATA_VALID_E <= '1';	-- Data field starts after TCP header.
			else
				RX_DATA_VALID_E <= '0';
			end if;
		end if;
	end if;
end process;

OUTPUT_GEN_001b: process(CLK)
begin
	if rising_edge(CLK) then
	    RX_OUTOFBOUND2_D <= RX_OUTOFBOUND2;
	    
		if(SYNC_RESET = '1') then
			RX_SOF_E <= '0';
		else
			if(IP_RX_DATA_VALID = '1') and (IP_RX_SOF = '1') then 
				RX_SOF_E <= '0';
			elsif(IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0') and 
				(RX_TCP_HEADER_FLAG = '0') and (GAP_IN_RX_SEQ = '0') then --*111923	
				if(RX_TCP_HEADER_FLAG_D = '1') and (RX_OUTOFBOUND2 = '0') then
					-- 1st TCP data byte in range
					RX_SOF_E <= '1';
			    elsif(RX_OUTOFBOUND2 = '0') and (RX_OUTOFBOUND2_D = '1') then
			        -- 1st TCP data Byte in range
					RX_SOF_E <= '1';
				else
					RX_SOF_E <= '0';
				end if;
			else
				RX_SOF_E <= '0';
			end if;
		end if;
	end if;
end process;

FIRST_RXTCP_BYTE_OUTOFRANGE <= '1' when (IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0')
                and (RX_TCP_HEADER_FLAG = '0')  and (RX_TCP_HEADER_FLAG_D = '1') and (RX_OUTOFBOUND2 = '1') else '0';

-- end of TCP field: TCP_RX_EOF_D 
OUTPUT_GEN_001c: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TCP_RX_EOF_D <= '0';
		elsif(IP_RX_DATA_VALID = '1') and (IP_RX_EOF = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0') then 
			TCP_RX_EOF_D <= '1';
		else	
			TCP_RX_EOF_D <= '0';
		end if;
	end if;
end process;

-- RX_EOF_E marks the last TCP data byte (unless there is no data, in which case marks the last byte in TCP header)
OUTPUT_GEN_001d: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_EOF_E <= '0';
		else
			if(IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0') then 
				if(RX_TCP_HEADER_FLAG = '0') and (IP_RX_EOF = '1') and (RX_OUTOFBOUND2 = '0')then
				    -- generate EOF pulse even when data is not forwarded to the output buffer
        			RX_EOF_E <= '1';
				elsif(RX_TCP_HEADER_FLAG = '1') and (IP_RX_EOF = '1')  then
				    -- generate EOF even if TCP data field is empty
        			RX_EOF_E <= '1';
				elsif(RX_TCP_HEADER_FLAG = '0') and (RX_OUTOFBOUND2 = '0') and (RX_WPTR_E_INC = RX_TCP_SEQ_NO_MAX2) then
				    -- reached the rx window upper boundary before the end of TCP data field
        			RX_EOF_E <= '1';
				else
        			RX_EOF_E <= '0';
				end if;
			else	
                RX_EOF_E <= '0';
            end if;            
		end if;
	end if;
end process;

-- Keep track of whether the received packet has zero data length or not. (Needed to 
-- determine whether an ACK should be sent)
RX_TCP_NON_ZERO_DATA_LENGTH_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_TCP_NON_ZERO_DATA_LENGTH <= '0';
		else
			if(IP_RX_DATA_VALID = '1') and (IP_RX_SOF = '1') then 
				RX_TCP_NON_ZERO_DATA_LENGTH <= '0';
				
			elsif(IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0') and 
--				(RX_TCP_HEADER_FLAG = '0') and (RX_OUTOFBOUND = '0') then 
				(RX_TCP_HEADER_FLAG = '0') then 
				-- Even if there is a gap in rx sequence, send ACK (otherwise tx/rx may be deadlocked
				-- when an ACK is lost) when a non-zero data length frame is received. 
				-- Irrespective of RX_OUTOFBOUND (this may be a zero-window probe segment)  **120316 
				if(RX_TCP_HEADER_FLAG_D = '1') then
					-- 1 st TCP data byte
					RX_TCP_NON_ZERO_DATA_LENGTH <= '1';	-- TCP payload field is not empty.
				end if;
			end if;
		end if;
	end if;
end process;

-- read the TCP client sequence number in the received TCP header. 
-- This is subsequently used as ack when replying or sending data to the TCP client.
RX_WPTR_E_INC <= RX_WPTR_E + 1;
RX_WPTR_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_WPTR_E <= (others => '0');
	  	elsif(IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (RX_TCP_HEADER_FLAG = '1') 
		and (RX_TCP_SEQ_NO_RDY = '1') then    -- *081923
			-- last byte of a valid rx TCP header
			RX_WPTR_E <= unsigned(RX_TCP_SEQ_NO); -- initialize external buffer write pointer location
		elsif(IP_RX_DATA_VALID = '1') and (unsigned(RX_IP_PROTOCOL) = 6) and (IP_HEADER_FLAG = '0') and 
			(RX_TCP_HEADER_FLAG = '0') and (GAP_IN_RX_SEQ = '0') then --*111923	
			-- Update as we read each data byte in the TCP data field
			-- RX_WPTR_E keeps track of ALL received TCP data, even if out-of-bound.
			RX_WPTR_E <= RX_WPTR_E_INC;	-- increment external buffer write pointer
		end if;
	end if;
end process;

-- Delay TCP payload output because we have to wait one more CLK for the TCP checksum outcome.
-- Aligned with IP_RX_DATA_VALID_D2
-- Forward data to output if and only if the TCP state is "Connected"
OUTPUT_GEN_002: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_DATA <= (others => '0');
			RX_DATA_VALID_local <= '0';
			RX_SOF <= '0';
			RX_EOF_local <= '0';
		elsif(TCP_STATE_localrx = 3) then
			-- TCP connection is established. 
			RX_DATA <= RX_DATA_E;
			RX_SOF <= RX_SOF_E;
			RX_EOF_local <= RX_EOF_E and RX_TCP_NON_ZERO_DATA_LENGTH; 
				-- Always generate EOF (user must know when to check the final RX_DATA_VALID status)
				-- except when no data	-*121218
			if(RX_SOF_E = '1') then
				-- let the demux know which stream
				RX_STREAM_SEL <= RX_TCP_STREAM_SEL_D;
			end if;
			if(RX_EOF_E = '1') then
				-- final tcp DATA validity information (including the checksum). 
				-- Does not include IP/TCP headers nor zero data length TCP frames.
				RX_DATA_VALID_local <= RX_DATA_VALID_E and VALID_RX_TCP_ALL;
			else
				-- Does not include IP/TCP headers nor zero data length TCP frames.
				RX_DATA_VALID_local <= RX_DATA_VALID_E;	-- packet assumed good until RX_EOF_E
			end if;
		else
			-- block data if not connected.
			RX_DATA <= (others => '0');
			RX_DATA_VALID_local <= '0';
			RX_SOF <= '0';
			RX_EOF_local <= '0';
		end if;
	end if;
end process;

RX_DATA_VALID <= RX_DATA_VALID_local;
RX_EOF <= RX_EOF_local;

--// RX SEQUENCE NUMBER ------------------------
RX_TCP_SEQ_NO_RDY <= '1' when (RX_TCP_HEADER_FLAG = '1') and (unsigned(IP_BYTE_COUNT(4 downto 0)) = 8) else '0'; 
RX_TCP_SEQ_NO_INC <= unsigned(RX_TCP_SEQ_NO) + 1;

-- Manage tx ack number
TX_ACK_GENx: for I in 0 to (NTCPSTREAMS-1) generate
	TX_ACK_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(RX_TCP_STREAM_SEL_D(I) = '1') then
				-- rx event
				if(TCP_STATE(I) < 3) and (EVENT1 = '1') then	-- *062716
					-- Received valid SYN while in LISTEN state
					-- ACK sequence number is the one received + 1
					-- Extend the applicability to the case when we receive multiple SYN messages (could happen
					-- when transmission delay is long)  *062716
					TX_ACK_NO(I) <= RX_TCP_SEQ_NO_INC;
				elsif(CONNECTED_FLAG_local(I) = '1') and (EVENTS5(I) = '1') then
					-- Received valid FIN while in CONNECTED state
					-- ACK sequence number depends on whether FIN packets include data or not
					TX_ACK_NO(I) <= RX_WPTR_E_INC;
				elsif(RX_ZERO_WINDOW_PROBE = '1') then
					-- TCP zero-window-length exception. sender may be testing whether the TX_ACK_WINDOW_LENGTH is 
					-- still zero by sending a 1-byte data. Treat as a zero-length packet
                elsif(CONNECTED_FLAG_local(I) = '1') and (VALID_RX_TCP2 = '1') and (UPDATE_TX_ACK_NO = '1') then  -- *011923
                    -- in CONNECTED state, received and successfully forwarded a rx segment. 
                    -- TX_ACK_NO is the next expected number (do not update TX_ACK_NO in the case of a retransmitted earlier frame)
                    TX_ACK_NO(I) <= RX_WPTR_E;
                end if;
            end if;
		end if;
	end process;
end generate;


------------------------------------------------
---- TCP receive flow control -------------------
-------------------------------------------------

-- for each received TCP payload byte, check is within the expected range (i.e. not before the expected RX_TCP_SEQ_NO
-- and not after the available free space in buffer  *011623
-- if out-of-bound, block the data transfer to the TCP_RXBUFNDEMUX2
RX_OUTOFBOUND_002: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RX_OUTOFBOUND2 <= '0';
        elsif(RX_WPTR_E_INC >= RX_TCP_SEQ_NO_MAX2) and 
        not((RX_WPTR_E_INC(31 downto 30) = "11") and (RX_TCP_SEQ_NO_MAX2(31 downto 30) = "00")) then
            -- a bit complicated because of modulo 2^32 counters.
            RX_OUTOFBOUND2 <= '1';
        elsif(RX_WPTR_E_INC < RX_TCP_SEQ_NO_MIN2) and 
        not((RX_WPTR_E_INC(31 downto 30) = "00") and (RX_TCP_SEQ_NO_MIN2(31 downto 30) = "11")) then
            RX_OUTOFBOUND2 <= '1';
        else
            RX_OUTOFBOUND2 <= '0';
        end if;
	end if;
end process;

-- update or not update TX_ACK_NO(I)? do not update TX_ACK_NO in the case of a retransmitted earlier frame
-- One CLK before the last TCP payload byte (@ IP_RX_EOF), verify that the final received sequence number is smaller or greater than TX_ACK_NO. 
-- Update TX_ACK_NO only if greater.
UPDATE_TX_ACK_NO_GEN: process(CLK)
begin
    if rising_edge(CLK) then
        if(IP_RX_EOF = '1') and ((RX_WPTR_E_INC >= TX_ACK_NO2) or ((RX_WPTR_E_INC(31 downto 30) = "00") and (TX_ACK_NO2(31 downto 30) = "11"))) and (GAP_IN_RX_SEQ = '0') then --*111923	
            UPDATE_TX_ACK_NO <= '1';
        else
            UPDATE_TX_ACK_NO <= '0';
        end if;
    end if;
end process;

-- Send ACK immediately upon receiving a valid data segment while TCP connected.
-- Watch out for infinite loops! cannot send an ACK on an ACK
-- Therefore, inhibit SEND_ACK_NOW if the last packet received has the ACK with zero-length.
SEND_ACK_NOW <= VALID_RX_TCP2 when  (TCP_STATE_localrx = 3) and (RX_TCP_NON_ZERO_DATA_LENGTH = '1') else '0';

-- Detect when there is a gap in the RX_TCP_SEQ_NO, indicating a previous frame is missing
-- In general, we expect RX_TCP_SEQ_NO to match TX_ACK_NO, the next expected rx sequence number.
GAP_IN_RX_SEQ <= '1' when (unsigned(RX_TCP_SEQ_NO) /= TX_ACK_NO2) else '0';	

-- Detect when client tries to send data past the end of the window (for example during 
-- TCP zero-window probing. Sender may be probing whether the TX_ACK_WINDOW_LENGTH is 
--	still zero by sending a 1-byte data past the end of the window or 1-byte while window is still zero. 
RX_ZERO_WINDOW_PROBE_GEN: process (CLK)   -- *021823
begin
    if rising_edge(CLK) then
        if(SYNC_RESET = '1') then
            RX_ZERO_WINDOW_PROBE <= '0';
        elsif(RX_TCP_SEQ_NO_RDY = '1') then
            if (RX_TCP_SEQ_NO_INC(15 downto 0) = TX_ACK_NO2(15 downto 0)) then
                RX_ZERO_WINDOW_PROBE <= '1';
            else
                RX_ZERO_WINDOW_PROBE <= '0';
            end if;
        elsif(FIRST_RXTCP_BYTE_OUTOFRANGE = '1') then
            RX_ZERO_WINDOW_PROBE <= '1';
        end if;        
    end if;
end process;

-- external receive buffer is full 
RX_BUF_FULL_GEN: for I in 0 to (NTCPSTREAMS-1) generate
	RX_BUF_FULL(I) <= '1' when (unsigned(RX_FREE_SPACE(I)) = 0) else '0';
end generate;

-- external receive buffer has space for at least one MSS frame *071416
RX_BUF_1MSSFREE_GEN: for I in 0 to (NTCPSTREAMS-1) generate
	RX_BUF_1MSSFREE(I) <= '1' when (unsigned(RX_FREE_SPACE(I)) > MSS) else '0';
end generate;

-- flow control information is sent to the client within the ack 
-- using the TX_ACK_WINDOW_LENGTH window size FROZEN during packet transmission
TX_ACK_WINDOW_LENGTH_GEN_001: process(CLK) 
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TX_ACK_WINDOW_LENGTH <= to_unsigned(MSS,TX_ACK_WINDOW_LENGTH'length);	-- initial available is at least 1 MSS
		elsif(RTS_local = '0') then
			-- update TX_ACK_WINDOW_LENGTH when triggering a frame transmission back to a client
			-- Two trigger events:
			if(NEXT_TX_TCP_FRAME_QUEUED = '1') then
				-- short (no payload data) tx packet for stream NEXT_TX_TCP_STREAM_SEL
				for I in 0 to NTCPSTREAMS-1 loop
					if(NEXT_TX_TCP_STREAM_SEL(I) = '1') then
						TX_ACK_WINDOW_LENGTH <= unsigned(RX_FREE_SPACE(I));
					end if;
        	    end loop;
			elsif(EVENT8 = '1') then
				-- long (with payload data) tx packet for stream TX_STREAM_SEL
				for I in 0 to NTCPSTREAMS-1 loop
				    if(TX_STREAM_SEL(I) = '1') then
				        TX_ACK_WINDOW_LENGTH <= unsigned(RX_FREE_SPACE(I));
				    end if;
				end loop;
			end if;
		end if;
	end if;
end process;
-- new *080818 take a margin of 4 samples = 4 bytes when reporting about the available space in the rx buffer
-- as we are trying to shorten the time between RX_EOF and ack transmission. 
-- Reason: RX_FREE_SPACE information is 3 clocks late
TX_ACK_WINDOW_LENGTH_GEN_002: process(TX_ACK_WINDOW_LENGTH) 
begin
	if(TX_ACK_WINDOW_LENGTH >= 4) then
		TX_ACK_WINDOW_LENGTH_OUT <= std_logic_vector(TX_ACK_WINDOW_LENGTH - 4);
	else
		TX_ACK_WINDOW_LENGTH_OUT <= (others => '0');
	end if;
end process;

-- window resizing
-- set when transmitting an ACK with TX_ACK_WINDOW_LENGTH = 0 indicating receiver buffer is full,
-- clear when the input receive buffer is no longer empty. 
RX_WINDOW_RESIZE_STATEx: for I in 0 to (NTCPSTREAMS-1) generate
	RX_WINDOW_RESIZE_STATE_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				RX_WINDOW_RESIZE_STATE(I) <= "00";
				SEND_RX_WINDOW_RESIZE(I) <= '0';
			elsif(TX_PACKET_SEQUENCE_START = '1') and (TX_TCP_STREAM_SEL(I) = '1') and (RX_BUF_FULL(I) = '1') then
				-- not enough room in rx buffer. Sending ACK with zero-width ACK window to client I.
				RX_WINDOW_RESIZE_STATE(I) <= "01";
			elsif(RX_WINDOW_RESIZE_STATE(I) = "01") and (MAC_TX_EOF = '1') and (TX_TCP_STREAM_SEL(I) = '1') then
				-- completed transmission of the ACK with TX_ACK_WINDOW_LENGTH = 0 to client I
				RX_WINDOW_RESIZE_STATE(I) <= "10";
			elsif (RX_WINDOW_RESIZE_STATE(I) = "10") and (RX_BUF_FULL(I) = '0') then
				-- Receive buffer has room for another segment. 
				-- time to send unsollicited ACKs to indicate window resizing. The receive window is no
				-- longer empty, the clients are on-hold due to the previous ACK with zero-width ack window.
				RX_WINDOW_RESIZE_STATE(I) <= "00";
				SEND_RX_WINDOW_RESIZE(I) <= '1';
			else
				SEND_RX_WINDOW_RESIZE(I) <= '0';
			end if;
		end if;
	end process;
end generate;

-- window resizing2 *071416
-- set when the receive buffer available space goes very low and no further data is received (Windows OS waits 5 seconds)
-- clear when the input receive buffer has enough room for a full MSS-size frame
-- The objective is to avoid waiting a long time (5s) until the Windows OS decides to send data again. 
RX_WINDOW_RESIZE2_STATEx: for I in 0 to (NTCPSTREAMS-1) generate
	RX_WINDOW_RESIZE2_STATE_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				RX_WINDOW_RESIZE2_STATE(I) <= "00";
				SEND_RX_WINDOW_RESIZE2(I) <= '0';
			elsif(TX_PACKET_SEQUENCE_START = '1') and (TX_TCP_STREAM_SEL(I) = '1')  and (RX_BUF_1MSSFREE(I) = '0') then
				-- rx buffer is getting full... wait
				RX_WINDOW_RESIZE2_STATE(I) <= "01";
			elsif(RX_WINDOW_RESIZE2_STATE(I) = "01") and (MAC_TX_EOF = '1') and (TX_TCP_STREAM_SEL(I) = '1')  then
				-- completed transmission of the ACK  to client I
				RX_WINDOW_RESIZE2_STATE(I) <= "10";
			elsif(RX_WINDOW_RESIZE2_STATE(I) = "10") and (TX_TCP_STREAM_SEL(I) = '1')  and (RX_BUF_1MSSFREE(I) = '1') then
				-- receive buffer now has enough space on rx buffer for a full MSS-size frame. Go back to idle
				RX_WINDOW_RESIZE2_STATE(I) <= "00";
				SEND_RX_WINDOW_RESIZE2(I) <= '1';
			else
				SEND_RX_WINDOW_RESIZE2(I) <= '0';
			end if;
		end if;
	end process;
end generate;


-- RECEIVE CODE ABOVE ^^^^^^^^^^^^^^^^^^^
--=============================================================================================
--=============================================================================================
--=============================================================================================
--=============================================================================================
-- TRANSMIT CODE BELOW  VVVVVVVVVVVVVVVVVV

---------------------------------------------------
------ Transmit EVENTS ----------------------------
---------------------------------------------------

---------------------------------------------------
--//---- TX SEQUENCER  ----------------------------
---------------------------------------------------
-- First, schedule a TX frame based on RX events.
-- The decision to transmit is made here and stored in non-volatile TX_PACKET_TYPE_QUEUED() variable until
-- the actual frame transmission can take place. This is a kind of queue to avoid conflicts.
-- Identify the stream based on the destination tcp port for each 
-- incoming frame.
SCHEDULE_TX_FRAME_GENx: for I in 0 to (NTCPSTREAMS-1) generate
	SCHEDULE_TX_FRAME_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				TX_PACKET_TYPE_QUEUED(I) <= "00";	-- undefined tx packet type
			elsif (NEXT_TX_TCP_STREAM_SEL(I) = '1')  and (RTS_local = '0') and (NEXT_TX_TCP_FRAME_QUEUED = '1') then
				-- scheduled for transmission, clear any tx frame queued
				TX_PACKET_TYPE_QUEUED(I) <= "00";	-- undefined tx packet type
			elsif (TCP_STATE(I) = 0) and (RX_TCP_STREAM_SEL_D(I) = '1') and (EVENT1 = '1')  then
				-- Connection establishment. send SYN/ACK
				TX_PACKET_TYPE_QUEUED(I) <= "01";		-- SYN/ACK, 24 bytes TCP header, no TCP payload
				-- send MSS option with the SYN message. TCP header is thus 24 byte long.
			elsif(CONNECTED_FLAG_local(I) = '1') and (CONNECTION_RESET(I) = '1') then
				-- user-initiated selective connection request while connected. Send FIN.
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif(CONNECTED_FLAG_local(I) = '1') and (TCP_KEEPALIVE_EN(I) = '1') and (KASTATE(I) = 0) then
				-- failed keepalive. Automatic disconnect. Send FIN.
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif (TCP_STATE(I) = 7) and (EVENTS5(I) = '1') then
				-- received FIN after FIN. Send final ACK.
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif (CONNECTED_FLAG_local(I) = '1') and (EVENTS5(I) = '1') then
				-- client-initiated connection termination . Send ACK
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif (TCP_STATE(I) = 4) and (EVENTS2(I) = '1') and (TX_FLAGS(I)(4) = '1') then
				-- sent ACK after receiving FIN. send final FIN
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif ((CONNECTED_FLAG_local(I) = '1') and (EVENTS11(I) = '1')) then
				-- keep-alive or zero-window check: send a probe segment (zero-length, TX_SEQ_NO = RX_TCP_ACK_NO -1)
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif (KA_PROBE_DET(I) = '1') then
				-- received a keep-alive probe segment. Send ack
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			elsif (CONNECTED_FLAG_local(I) = '1') and (RX_TCP_STREAM_SEL_D(I) = '1') and (EVENT6 = '1') then
				-- received valid segment, no segment to transmit. generate ACK only.
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
				-- default length
			elsif (CONNECTED_FLAG_local(I) = '1') and (EVENTS10(I) = '1') then
				-- Window resizing (receive flow control), no segment to transmit. The receive buffer is no 
				-- longer empty. Send a single ACK with a non-zero window.
				TX_PACKET_TYPE_QUEUED(I) <= "10";		-- 40-byte long ACK, 20 bytes TCP header
			end if;
		end if;
	end process;
end generate;	

-- Trigger response
-- Which stream is next? Check if any non-payload packet is queued (TX_PACKET_TYPE_QUEUED(I) /= 0)
NEXT_TCP_TX_STREAM_INDEX_001: process(TX_PACKET_TYPE_QUEUED)
variable TX_STREAM_NO: std_logic_vector(NTCPSTREAMS-1 downto 0);
variable TX_FRAME_QUEUED: std_logic := '0';
begin
	TX_STREAM_NO  := (others => '0');
	TX_FRAME_QUEUED := '0';
	for I in 0 to (NTCPSTREAMS-1) loop
		if(TX_FRAME_QUEUED = '0') and (TX_PACKET_TYPE_QUEUED(I) /= "00") then
			TX_FRAME_QUEUED := '1';
			TX_STREAM_NO(I) := '1';	-- rephrasing 081918
		end if;
	end loop;
	NEXT_TX_TCP_STREAM_SEL <= TX_STREAM_NO;
	NEXT_TX_TCP_FRAME_QUEUED <= TX_FRAME_QUEUED;
end process;

-- decision to transmit a frame (with or without payload) is made here.
-- TX_PACKET_TYPE is valid during transmission from the TX_PACKET_SEQUENCE_START pulse (incl) 
-- to MAC_TX_EOF (incl), undefined otherwise.
TX_PACKET_SEQUENCE_START_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RTS_local <= '0';
			TX_PACKET_TYPE <= (others => '0');	-- undefined
		elsif(RTS_local = '0') then
			-- Prevent a new packet assembly/transmission until current assembly/transmission is complete.
			if(NEXT_TX_TCP_FRAME_QUEUED = '1') then
				-- short (no payload data) tx packet for stream NEXT_TX_TCP_STREAM_SEL
				RTS_local <= '1';	
				TX_PACKET_SEQUENCE_START <='1';	
				TX_TCP_STREAM_SEL <= NEXT_TX_TCP_STREAM_SEL;
				for I in 0 to NTCPSTREAMS-1 loop
				    if(NEXT_TX_TCP_STREAM_SEL(I) = '1') then
				        TX_PACKET_TYPE <= TX_PACKET_TYPE_QUEUED(I);
				    end if;
			     end loop;
			elsif(EVENT8 = '1') then
				-- long (with payload data) tx packet for stream TX_STREAM_SEL
				RTS_local <= '1';	
				TX_PACKET_SEQUENCE_START <='1';	
				TX_TCP_STREAM_SEL <= TX_STREAM_SEL;
				TX_PACKET_TYPE <= "11";		-- tx data packet, 20 bytes TCP header
			end if;
		elsif(MAC_TX_EOF = '1') then
			-- transmit is complete.
			RTS_local <= '0';
			TX_PACKET_TYPE <= (others => '0');
		else
			TX_PACKET_SEQUENCE_START <= '0';	-- make it a one-CLK pulse
		end if;
	end if;
end process;
RTS <= RTS_local;	-- tell TCP_TX
		
		
-- send all relevant information to TCP_TX so that it can format the transmit frame
OUTPUT_GEN: process(TX_TCP_STREAM_SEL, TX_DEST_MAC_ADDR, TX_DEST_IP_ADDR, TX_DEST_PORT_NO, TCP_LOCAL_PORTS,
	TX_IPv4_6n, TX_SEQ_NO_OUT_local, TX_ACK_NO, TX_FLAGS)
variable TX_DEST_MAC_ADDRv: std_logic_vector(47 downto 0);
variable TX_DEST_IP_ADDRv: std_logic_vector(127 downto 0);
variable TX_DEST_PORT_NOv: std_logic_vector(15 downto 0);
variable TCP_LOCAL_PORTSv: std_logic_vector(15 downto 0);
variable TX_IPv4_6nv: std_logic;
variable TX_SEQ_NO_OUTv: std_logic_vector(31 downto 0);
variable TX_ACK_NOv: std_logic_vector(31 downto 0);
variable TX_FLAGSv: std_logic_vector(7 downto 0);
begin
	TX_DEST_MAC_ADDRv := (others => '0');
	TX_DEST_IP_ADDRv := (others => '0');
	TX_DEST_PORT_NOv := (others => '0');
	TCP_LOCAL_PORTSv := (others => '0');
	TX_IPv4_6nv := '0';
	TX_SEQ_NO_OUTv := (others => '0');
	TX_ACK_NOv := (others => '0');
	TX_FLAGSv := (others => '0');
	for I in 0 to NTCPSTREAMS-1 loop
		if(TX_TCP_STREAM_SEL(I) = '1') then
			TX_DEST_MAC_ADDRv := TX_DEST_MAC_ADDR(I);
			TX_DEST_IP_ADDRv := TX_DEST_IP_ADDR(I);
			TX_DEST_PORT_NOv := TX_DEST_PORT_NO(I);
			TCP_LOCAL_PORTSv := TCP_LOCAL_PORTS(I);
			TX_IPv4_6nv := TX_IPv4_6n(I);    
			TX_SEQ_NO_OUTv := std_logic_vector(TX_SEQ_NO_OUT_local(I));
			TX_ACK_NOv := std_logic_vector(TX_ACK_NO(I));
			TX_FLAGSv := TX_FLAGS(I);
		end if;
		TX_DEST_MAC_ADDR_OUT <= TX_DEST_MAC_ADDRv;
		TX_DEST_IP_ADDR_OUT <= TX_DEST_IP_ADDRv;
		TX_DEST_PORT_NO_OUT <= TX_DEST_PORT_NOv;
		TX_SOURCE_PORT_NO_OUT <= TCP_LOCAL_PORTSv;
		TX_IPv4_6n_OUT <= TX_IPv4_6nv;    
		TX_SEQ_NO_OUT <= TX_SEQ_NO_OUTv;
		TX_ACK_NO_OUT <= TX_ACK_NOv;
		TX_FLAGS_OUT <= TX_FLAGSv;
	end loop;
end process;
TX_PACKET_SEQUENCE_START_OUT <= TX_PACKET_SEQUENCE_START;
TX_PACKET_TYPE_OUT <= TX_PACKET_TYPE;



-------------------------------------------------
---- TCP transmit flow control -------------------
-------------------------------------------------
-- last byte sent : TX_SEQ_NO
-- last byte ack'd: RX_TCP_ACK_NO
-- advertised rx window: RX_TCP_WINDOW_SIZE
-- sent and unacknowledged: TX_SEQ_NO - RX_TCP_ACK_NO

-- The next TCP tx frame size is determined by 
-- (a) the maximum packet size in the MAC (assumed 1023 payload data in TCP_TXBUF) or
-- (b) the effective TCP rx window size as reported by the receive side, or

-- Effective TCP rx window size = advertised TCP rx window size - unacknowledged but sent data size
-- changes at end of tx packet (TX_EOF_D2), and upon receiving a valid ack
-- Partial computation upon receiving a valid ACK, complete computation upon frame transmission
-- when TX_SEQ_NO is updated.
-- The effective TCP rx window size can be temporarily reduced by the TCP congestion window.

-- The TCP congestion window starts at 2 segments (see MSS) and doubles at each valid ACK.
EFF_RX_WINDOW_SIZE_PARTIAL_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			EFF_RX_WINDOW_SIZE_PARTIAL_local <= (others => '0');
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM <= (others => '0');
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID <= '0';
		elsif(TCP_STATE_localrx = 2) and (EVENT4 = '1') then
			-- entering the 'connected' state
			-- enter slow start phase: TCP congestion window starts with 2 segment. increases after each ACK
			-- until we reach the effective window size advertized by the receive side.
			EFF_RX_WINDOW_SIZE_PARTIAL_local <= unsigned(RX_TCP_ACK_NO(16 downto 0)) + 2*MSS;	   
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM <= RX_TCP_STREAM_SEL_D;
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID <= '1';
			for I in 0 to NTCPSTREAMS-1 loop
			     if(RX_TCP_STREAM_SEL_D(I) = '1') then
        			TCP_CONGESTION_WINDOW(I) <=  to_unsigned(2*MSS,16);	 -- remember it for each stream
        			TCP_TX_SLOW_START(I) <= '1';
			     end if;
			end loop;
		elsif(EVENT4A = '1') and (unsigned(RX_TCP_WINDOW_SIZE) /= 0) then 
			-- Valid ACK received for stream RX_TCP_STREAM_SEL_D (not a duplicate ACK)
			for I in 0 to NTCPSTREAMS-1 loop
                 if(RX_TCP_STREAM_SEL_D(I) = '1') then
                    if(TCP_TX_SLOW_START(I) = '1') and (TCP_CONGESTION_WINDOW(I)(15) = '0') and 
                     (TCP_CONGESTION_WINDOW(I)(14 downto 0) < unsigned(RX_TCP_WINDOW_SIZE(15 downto 1))) then	-- *072818
                         -- double the next tx frame size until we reach the effective TCP rx window size
                         EFF_RX_WINDOW_SIZE_PARTIAL_local <= ("0" & TCP_CONGESTION_WINDOW(I)(14 downto 0) & "0") + unsigned(RX_TCP_ACK_NO(16 downto 0));
                         -- remember it here
                         TCP_CONGESTION_WINDOW(I) <= TCP_CONGESTION_WINDOW(I)(14 downto 0) & "0";  
                     else
                         EFF_RX_WINDOW_SIZE_PARTIAL_local <= resize(unsigned(RX_TCP_WINDOW_SIZE),17) + unsigned(RX_TCP_ACK_NO(16 downto 0));  
                         TCP_TX_SLOW_START(I) <= '0';    -- end of slow-start phase
                     end if;
                 end if;
            end loop;
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM <= RX_TCP_STREAM_SEL_D;
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID <= '1';
			-- partial computation of the effective tcp rx window size
		elsif(EVENT4B = '1') and (unsigned(RX_TCP_WINDOW_SIZE) /= 0) then 
			-- Duplicate ACK for stream RX_TCP_STREAM_SEL_D. Even though the RX_TCP_ACK_NO is the same, the
			-- RX_TCP_WINDOW_SIZE may have changed (window resizing)
			EFF_RX_WINDOW_SIZE_PARTIAL_local <= resize(unsigned(RX_TCP_WINDOW_SIZE),17) + unsigned(RX_TCP_ACK_NO(16 downto 0));  
			for I in 0 to NTCPSTREAMS-1 loop
                 if(RX_TCP_STREAM_SEL_D(I) = '1') then
        			TCP_TX_SLOW_START(I) <= '0';	-- end of slow-start phase
                 end if;
            end loop;
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM <= RX_TCP_STREAM_SEL_D;
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID <= '1';
		else
			-- ignore duplicate ACKs.
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID <= '0';
		end if;
	end if;
end process;
EFF_RX_WINDOW_SIZE_PARTIAL <= std_logic_vector(EFF_RX_WINDOW_SIZE_PARTIAL_local);

-- detect duplicate ACKs (an indication that at least one of our tx packet got lost/collided)
-- keep the flag up until (a) the condition disappears, or (b) we rewind and transmit a packet 
RX_VALID_ACK_GENx: for I in 0 to (NTCPSTREAMS-1) generate
	-- send duplicate if we have received three ACKs in a row with the same ack no.
	-- why 3? because it is normal to receive two acks without lost packet (regular ack + window adjustment for example).

	-- tell TCP_TXBUF about the last acknowledged location.
	RX_TCP_ACK_NO_D(I) <= std_logic_vector(RX_TCP_ACK_NO_D_local(I)(16 downto 0));	-- don't need the entire 32-bits

	RX_VALID_ACK_GEN_002: process(CLK)
	begin
		if rising_edge(CLK) then
			if(EVENTS4(I) = '1') then
				-- rx event:
				-- save rx ack number (RX_TCP_ACK_NO is transient)
				RX_TCP_ACK_NO_D_local(I) <= unsigned(RX_TCP_ACK_NO);
				-- detect duplicates
				if(RX_TCP_ACK_NO_D_local(I)(15 downto 0) = unsigned(RX_TCP_ACK_NO(15 downto 0))) 
				and (unsigned(RX_TCP_ACK_NO(15 downto 0)) /= TX_SEQ_NO_local(I)(15 downto 0)) 
				and (RX_TCP_NON_ZERO_DATA_LENGTH = '0') then	-- *120918
					-- Note: no need to compare all 31 bits of ack and sequence numbers 
					-- Ignore duplicates when already matching the expected TX_SEQ_NO_local
					-- Ignore duplicates due to multiple received payloads while still transmitting.
					if(DUPLICATE_RX_TCP_ACK_CNTR(I) /= 3) then
						DUPLICATE_RX_TCP_ACK_CNTR(I) <= DUPLICATE_RX_TCP_ACK_CNTR(I) + 1;   -- counts from 0 to 3
					end if;
				else
					-- received new or expected ack. condition is gone.
					DUPLICATE_RX_TCP_ACK_CNTR(I) <= "00";
				end if;
			elsif (TX_TCP_STREAM_SEL(I) = '1') and (TX_PACKET_SEQUENCE_START = '1') and (TX_PACKET_TYPE = "11")
				and (TX_SEQ_NO_local(I)(15 downto 0) =  RX_TCP_ACK_NO_D_local(I)(15 downto 0)) then 
				-- tx event:
				-- started retransmitting unacknowledged data. clear flag
				DUPLICATE_RX_TCP_ACK_CNTR(I) <= "00";
			end if;
		end if;
	end process;
end generate;

-- detect keep-alive probe segment: RX_TCP_SEQ_NO is TX_ACK_NO -1 and no data
KA_PROBE_DET_GENx: for I in 0 to (NTCPSTREAMS-1) generate
	KA_PROBE_DET_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if ((CONNECTED_FLAG_local(I) = '1') and (EVENTS12(I) = '1') and (RX_TCP_NON_ZERO_DATA_LENGTH = '0') and
			(RX_TCP_SEQ_NO_INC(15 downto 0) = TX_ACK_NO(I)(15 downto 0))) then
				KA_PROBE_DET(I) <= '1';
			else
				KA_PROBE_DET(I) <= '0';
			end if;
		end if;
	end process;
end generate;

-- Retransmission timeout
-- Compute timout since we have transmitted a packet and not received any ACK with different RX_TCP_ACK_NO.
-- See RFC 2988 Section 5: Managing the RTO timer. 
-- At this time, we do not implement the RTO mins (1s) and max(60s) nor the backing-off algorithm for 
-- repeated timeouts.
RX_VALID_ACK_TIMEOUT_x: for I in 0 to (NTCPSTREAMS-1) generate
	RX_VALID_ACK_TIMEOUT_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') or (TCP_STATE(I) = 0) then	-- *121818
				-- clear at start of connection
				RX_VALID_ACK_TIMOUT(I) <= (others => '0');
			elsif(TX_TCP_STREAM_SEL(I) = '1') and (TX_PACKET_TYPE = "11") and (TX_PACKET_SEQUENCE_START = '1') then	-- *062716
				-- tx event: just (re)transmitted 1 frame with payload data. must wait for ACK
				-- arm timer
				RX_VALID_ACK_TIMOUT(I) <= TXRX_DELAY(I)(19 downto 0) & "0000"; -- 16* the average round-trip delay
			elsif(EVENTS4(I) = '1') and (unsigned(RX_TCP_ACK_NO(15 downto 0))  = TX_SEQ_NO_local(I)(15 downto 0)) then  --*062316
				-- rx event: received a valid ACK, all outstanding data has been acknowledged
				-- turn off the retransmission timer.
				RX_VALID_ACK_TIMOUT(I) <= (others => '0');
			elsif(EVENTS4(I) = '1') and (unsigned(RX_TCP_ACK_NO(15 downto 0)) /= TX_SEQ_NO_local(I)(15 downto 0)) 
					and (unsigned(RX_TCP_ACK_NO(15 downto 0)) /= RX_TCP_ACK_NO_D_local(I)(15 downto 0)) then  --*062316
				-- rx event: received a valid ACK, not a duplicate, acknowledging new data
				-- re-arm timer
				RX_VALID_ACK_TIMOUT(I) <= TXRX_DELAY(I)(19 downto 0) & "0000"; -- 16* the average round-trip delay
			elsif(TICK_4US = '1') and (RX_VALID_ACK_TIMOUT(I) > 1) then
				-- otherwise, decrement until counter reaches 1 (Re-transmit condition)
				RX_VALID_ACK_TIMOUT(I) <= RX_VALID_ACK_TIMOUT(I) -1;
			end if;
		end if;
	end process;

	RETRANSMIT_FLAG(I) <= '1' when (RX_VALID_ACK_TIMOUT(I) = 1) else '0'; 
end generate;

-- Measure round-trip delay: server -> client -> server
-- Units: 4us
TXRX_DELAY_x: for I in 0 to (NTCPSTREAMS-1) generate
	TXRX_DELAY_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				TXRX_DELAY_STATE(I) <= '0';
				TXRX_DELAY_CNTR(I) <= (others => '0');
				TXRX_DELAY(I) <= x"01E848";  -- 0.5s worst case default (leave 6 extra MSBs for xX multiplication in timeout)
			elsif(TCP_STATE(I) = 0) then
				-- clear the last RT delay value at the start of connection
				TXRX_DELAY_STATE(I) <= '0';
				TXRX_DELAY_CNTR(I) <= (others => '0');
				TXRX_DELAY(I) <= x"01E848";  -- 0.5s worst case default (leave 6 extra MSBs for xX multiplication in timeout)
			elsif(TXRX_DELAY_STATE(I) = '0') and (TX_PACKET_SEQUENCE_START = '1') and (TX_TCP_STREAM_SEL(I) = '1') then
				-- regular tx event
				TXRX_DELAY_STATE(I) <= '1';
				-- start the stop watch
				TXRX_DELAY_CNTR(I) <= (others => '0');
			elsif(TXRX_DELAY_STATE(I) = '1') and (EVENTS4(I) = '1') then
				-- received ACK 
				TXRX_DELAY_STATE(I) <= '0';
				-- set a minimum RT delay value (here 32us)
				if(TXRX_DELAY_CNTR(I)(19 downto 3) = 0) then
					TXRX_DELAY(I) <= x"000008";
				else
					TXRX_DELAY(I) <= TXRX_DELAY_CNTR(I);
				end if;
			elsif(TXRX_DELAY_STATE(I) = '1') and (TICK_4US = '1') then
				-- increment stop watch up to 0.5s max
				if(TXRX_DELAY_CNTR(I) <  x"01E848") then
					TXRX_DELAY_CNTR(I) <= TXRX_DELAY_CNTR(I) + 1;
				else
					-- reached the max value of 0.5s
					TXRX_DELAY_STATE(I) <= '0';
					TXRX_DELAY(I) <= TXRX_DELAY_CNTR(I);
				end if;
			end if;
		end if;
	end process;
end generate;


--
-------------------------------------------------
---- Transmit data ------------------------------
-------------------------------------------------
-- 32-bit initial sequence number to be used at TCP connection time.
-- This is simply a counter incremented every 4 usec.
TCP_ISN_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		TCP_ISN_D <= TCP_ISN;	-- pipelining for better timing
		
		if(TICK_4US = '1') then
			TCP_ISN <= TCP_ISN + 1;
		end if;
	end if;
end process;

-- Manage tx sequence number. Changes based on INDEPENDENT rx and tx events (we may be receiving data about stream#1 
-- while transmitting data about stream#2).
-- To prevent deadlocks, TX_SEQ_NO should only change upon completing a frame transmission or when 
-- no data is waiting for transmission in TCP_TXBUF.
-- We keep two sets: TX_SEQ_NO_local has memory, TX_SEQ_NO_OUT_local is for output only, generally the same as TX_SEQ_NO_local
-- but can vary in special cases like probing (see keep-alive)
TX_SEQ_NO_GENx: for I in 0 to (NTCPSTREAMS-1) generate
	-- forward information to TXBUF (to compute effective rx window size and reposition the buffer read
	-- pointer)
	TX_SEQ_NO(I) <= std_logic_vector(TX_SEQ_NO_local(I)(16 downto 0));	-- don't need the entire 32-bits

	TX_SEQ_NO_GENx_001: process(CLK)
	begin
		if rising_edge(CLK) then 
		    TX_SEQ_NO_JUMP_D(I) <= TX_SEQ_NO_JUMP_local(I);
		    
			if(RX_TCP_STREAM_SEL_D(I) = '1') and (TCP_STATE(I) = 0) and (EVENT1 = '1') then
				-- rx event: Received valid SYN while in LISTEN state
				-- Save the initial sequence number
				if(SIMULATION = '1') then
					-- During simulations, set the TX_SEQ_NO so that it matches Wireshark captures
					-- (sequence number in the SYN/ACK packet)
					TX_SEQ_NO_local(I) <= x"01a8d12c";
					TX_SEQ_NO_OUT_local(I) <= x"01a8d12c";
				else
					-- use a random number (time)
					TX_SEQ_NO_local(I) <= TCP_ISN_D;
					TX_SEQ_NO_OUT_local(I) <= TCP_ISN_D;
				end if;
				TX_SEQ_NO_JUMP_local(I) <= '1';
			elsif(TX_TCP_STREAM_SEL(I) = '1') and (TX_PACKET_TYPE = "11") and (TX_PACKET_SEQUENCE_START = '1') then
				-- regular tx event: 
				-- just triggered transmission of a frame with TX_PAYLOAD_SIZE payload bytes.
				TX_SEQ_NO_local(I) <= TX_SEQ_NO_local(I) + resize(unsigned(TX_PAYLOAD_SIZE), TX_SEQ_NO_local(I)'length);
				TX_SEQ_NO_OUT_local(I) <= TX_SEQ_NO_local(I) + resize(unsigned(TX_PAYLOAD_SIZE), TX_SEQ_NO_local(I)'length);
				TX_SEQ_NO_JUMP_local(I) <= '0';
			elsif(TX_TCP_STREAM_SEL(I) = '1') and (TX_PACKET_SEQUENCE_START = '1') and ((TX_FLAGS(I)(1) = '1') or (TX_FLAGS(I)(0) = '1'))then
				-- tx event: 
				-- SYN and FIN flags consumes a sequence number
				-- Update sequence number upon tx completion, getting ready for comparison with the RX_TCP_ACK_NO
				TX_SEQ_NO_local(I) <= TX_SEQ_NO_local(I) + 1;
				TX_SEQ_NO_OUT_local(I) <= TX_SEQ_NO_local(I) + 1;
				TX_SEQ_NO_JUMP_local(I) <= '1';
			elsif (RETRANSMIT_FLAG(I) = '1') and (CONNECTED_FLAG_local(I) = '1') then	-- NEW 11/4/11 AZ. this re-transmission scheme works only during connected state.
				-- tx event. timeout awaiting for ACK. Rewind TX_SEQ_NO which will indirectly cause a re-transmission since
				-- TCP_TXBUF will declare data ready to send.
				-- Rewind tx sequence number to the last acknowledged seq no at the start of retransmission
				TX_SEQ_NO_local(I) <= RX_TCP_ACK_NO_D_local(I);
				TX_SEQ_NO_OUT_local(I) <= RX_TCP_ACK_NO_D_local(I);
				TX_SEQ_NO_JUMP_local(I) <= '1';
			elsif (EVENTS4B(I) = '1') and (DUPLICATE_RX_TCP_ACK_CNTR(I) = 2) then
				-- rx event: received 3 duplicate acks (could be a missed packet). 
				-- Rewind tx sequence number to the last acknowledged seq no at the start of retransmission
				-- TCP_TXBUF will declare data ready to send.
				TX_SEQ_NO_local(I) <= RX_TCP_ACK_NO_D_local(I);
				TX_SEQ_NO_OUT_local(I) <= RX_TCP_ACK_NO_D_local(I);
				TX_SEQ_NO_JUMP_local(I) <= '1';
			elsif ((CONNECTED_FLAG_local(I) = '1') and (EVENTS11(I) = '1')) then
				-- non-tx related events		
				-- keep-alive or zero-window check: send a probe segment (zero-length, TX_SEQ_NO = RX_TCP_ACK_NO -1)
				TX_SEQ_NO_OUT_local(I) <= RX_TCP_ACK_NO_D_local(I) - 1;
			elsif(TX_TCP_STREAM_SEL(I) = '1') and (MAC_TX_EOF = '1') then
				-- after transmitting a probe segment , restore the normal TX_SEQ_NO 
				TX_SEQ_NO_OUT_local(I) <= TX_SEQ_NO_local(I);
			else
				TX_SEQ_NO_JUMP_local(I) <= '0';
			end if;
		end if;
	end process;
end generate;
TX_SEQ_NO_JUMP <= TX_SEQ_NO_JUMP_local and not TX_SEQ_NO_JUMP_D;

-- Manage tx TCP flags:  
-- (MSb) CWR Congestion Window Reduced (CWR) flag/ECE - ECN-Echo/URG/ACK/PSH/RST/SYN/FIN (LSb)
TX_FLAGS_GENx: for I in 0 to (NTCPSTREAMS-1) generate
	TX_FLAGS_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				TX_FLAGS(I) <= "00000000";	
			elsif(CONNECTED_FLAG_local(I) = '1') and (CONNECTION_RESET(I) = '1') then
				-- user-initiated selective connection request while connected. Send FIN/ACK.
				TX_FLAGS(I) <= "00010001";	
			elsif(CONNECTED_FLAG_local(I) = '1') and (TCP_KEEPALIVE_EN(I) = '1') and (KASTATE(I) = 0) then
				-- failed keepalive. Automatic disconnect. Send FIN/ACK.
				TX_FLAGS(I) <= "00010001";	
			elsif (TCP_STATE(I) = 7) and (EVENTS5(I) = '1') then
				-- received FIN after FIN. Send final ACK.
				TX_FLAGS(I) <= "00010000";	
			elsif (CONNECTED_FLAG_local(I) = '1') and (EVENTS5(I) = '1') then
				-- client-initiated connection termination . Send ACK
				TX_FLAGS(I) <= "00010000";	
			elsif (TCP_STATE(I) = 4) and (EVENTS2(I) = '1') and (TX_FLAGS(I)(4) = '1') then
				-- sent ACK after receiving FIN. send final FIN/ACK
				TX_FLAGS(I) <= "00010001";	
			elsif(TCP_STATE(I) = 0) and (EVENT1 = '1') then
				-- Received valid SYN while in LISTEN state
				TX_FLAGS(I) <= "00010010";	-- SYN flag set in response
			elsif (EVENT8 = '1') then
				-- CONNECTED state(implied in EVENT8). send or re-send data. set PUSH flag
				TX_FLAGS(I) <= "00011000";	-- flags in response
			elsif (CONNECTED_FLAG_local(I) = '1') and ((EVENTS5(I) = '1') or (EVENT6 = '1') or (EVENTS10(I) = '1')) then
				-- CONNECTED state. ACK only. clear PUSH flag
				TX_FLAGS(I) <= "00010000";	-- flags in response
			elsif(TCP_STATE(I) = 4) and (EVENT2 = '1') then
				-- Connection termination. Send FIN
				TX_FLAGS(I) <= "00010001";	-- FIN/ACK flag set in response
			elsif ((CONNECTED_FLAG_local(I) = '1') and (EVENTS11(I) = '1')) then
				-- keep-alive or zero-window check: send a probe segment (zero-length, TX_SEQ_NO = RX_TCP_ACK_NO -1)
				TX_FLAGS(I) <= "00000000";	-- flags in response
			elsif (KA_PROBE_DET(I) = '1') then
				-- received a keep-alive probe segment. Send ack
				TX_FLAGS(I) <= "00010000";	-- flags in response
			end if;
		end if;
	end process;
end generate;

--// Test Point
TP(1) <= '1' when (TCP_STATE(0) = 0) else '0';	-- connected
TP(2) <= '1' when (TCP_STATE(0) = 1) else '0';	-- connected
TP(3) <= '1' when (TCP_STATE(0) = 2) else '0';	-- connected
TP(4) <= '1' when (TCP_STATE(0) = 3) else '0';	-- connected
TP(5) <= '1' when (TCP_STATE(0) = 4) else '0';	-- connected
TP(6) <= '1' when (TCP_STATE(0) = 5) else '0';	-- connected
TP(7) <= EVENT1;	-- SYN
TP(8) <= EVENT2;	-- SENT
TP(9) <= EVENT4;	-- ACK
TP(10) <= '0' when (unsigned(EVENTS5) = 0) else '1';	-- FIN
--TP(2) <= TX_SEQ_NO_local(0)(0);
--TP(3) <= RX_TCP_ACK_NO_D_local(0)(0);
--TP(4) <= EVENT4;	-- ACK
--TP(5) <= '1' when (RX_TCP_STREAM_SEL_D(I) = '1') 
--				and (TCP_STATE_localrx = 0) and (EVENT1 = '1') else '0';  -- initialize TX_SEQ_NO
--TP(6) <= '1' when (TX_TCP_STREAM_SEL(0) = '1') and (TX_PACKET_TYPE = "11") and (MAC_TX_EOF = '1')  else '0';
--	-- TX_SEQ_NO regular tx event
--TP(7) <= '1' when (TX_TCP_STREAM_SEL(0) = '1') and (MAC_TX_EOF = '1') and (TX_FLAGS(1) = '1') else '0';
--TP(8) <= '1' when (TX_TCP_STREAM_SEL(0) = '1') and (MAC_TX_EOF = '1') and (TX_FLAGS(0) = '1') else '0';
--TP(9) <= RETRANSMIT_FLAG(0);
--TP(10) <= '1' when (RX_TCP_STREAM_SEL_D(I) = '1') and 
--					(EVENT4B = '1') and (DUPLICATE_RX_TCP_ACK_CNTR(0)(1) = '1')  and 
--					(TX_SEQ_NO_local(0)(15 downto 0) /=  RX_TCP_ACK_NO_D_local(0)(15 downto 0)) else '0';
--
							 

end Behavioral;
