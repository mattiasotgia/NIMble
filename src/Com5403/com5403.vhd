-------------------------------------------------------------
-- MSS copyright 2011-2020
--	Filename:  COM5403.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 15
--	Date last modified: 10/2/20
-- Inheritance: 	COM5402.vhd 8/8/12
--
-- description:  Internet IP stack: IP/TCP(client)/UDP/ARP/PING.
-- The IP stack relies on the lower layers: MAC (COM5401) and PHY (Integrated circuit)
-- Interfaces directly with COM-5401SOFT MAC protocol layer or equivalent.
-- TCP implements only the client side. For TCP server, see COM5402.vhd.
--
-- Rev 2 11/10/13 AZ
-- Added DHCP client protocol
-- Added MAC_TX_SOF flag for an easier interface with Xilinx tri-mode MAC
-- Corrected IP header bug in UDP_TX.vhd
--
-- Rev 3 1/28/14 AZ
-- Increased EFF_RX_WINDOW_SIZE_PARTIAL precision to 17 bits to detect abnormal negative window size reports
--
-- Rev 4 1/31/14 AZ
-- moved TX_IDLE_TIMEOUT up to a generic parameter.
--
-- Rev 5 2/2/14 AZ
-- Corrected missing DHCP assignment of subnet mask and gateway IP address
--
-- Rev 6 4/2/15 AZ
-- consolidated shared components updates (udp_rx, packet parsing, packets_2_stream)
-- 
-- Rev 7 4/23/16 AZ
-- consolidated shared components with COM-5402SOFT
-- Added multicast IP address (UDP)
--
-- Rev 8 6/25/16 AZ
-- Added MAC_TX_RTS output: potentially useful if there is an external transmission arbiter 
-- (for example in the case of multiple clients)
--
-- Rev 9 7/14/16 AZ
-- Corrected issue with Windows OS taking 5 seconds to resume TCP transmission when the TCP transmit side 'thinks'
-- the rx window is zero, whereas the TCP rx side computes a small but non zero window in its rx buffer.
-- Solution: send an ACK to the TCP transmit side as soon as the rx buffer goes from near-full to enough room (threshold = 1 MSS)
--
-- Rev 13 12/1/16 AZ
-- Added optional TCP keep-alive packets. Usage: TCP_KEEPALIVE_PERIOD in the generic section.
--
-- Rev 14 12/4/18 AZ
-- updated tcp_txbuf for higher throughput
-- typos
-- added	TX_SEQ_NO_JUMP in TCP_CLIENTS
-- extended TCP_KEEPALIVE to individual streams
--
-- Rev 15 10/2/20 AZ
-- added generate wrapper around the IGMP code
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use work.com5402pkg.all;	-- defines global types, number of TCP streams, etc

entity COM5403 is
	generic (
--		DHCP_CLIENT_EN: std_logic := '1';
		DHCP_CLIENT_EN: std_logic := '0';
			-- '0' for static address (for minimum size), '1' for static/dynamic address (instantiates a DHCP_CLIENT component)
		NUDPTX: integer range 0 to 1:= 1;
		NUDPRX: integer range 0 to 1:= 1;
			-- number of UDP ports enabled for tx and rx
		IGMP_EN: std_logic := '1';
			-- '1' to enable UDP multicast (which requires IGMP)
		NTCPSTREAMS: integer range 0 to 255 := 3;  
			-- number of concurrent TCP streams handled by this component
		CLK_FREQUENCY: integer := 125;
			-- CLK frequency in MHz. Needed to compute actual delays.
		TX_IDLE_TIMEOUT: integer range 0 to 50:= 50;	
			-- inactive input timeout, expressed in 4us units. -- 50*4us = 200us 
			-- Controls the transmit stream segmentation: data in the elastic buffer will be transmitted if
			-- no input is received within TX_IDLE_TIMEOUT, without waiting for the transmit frame to be filled with MSS data bytes.
		TCP_KEEPALIVE_PERIOD: integer := 60;
			-- period in seconds for sending no data keepalive frames. 
			-- "Typically TCP Keepalives are sent every 45 or 60 seconds on an idle TCP connection, and the connection is 
			-- dropped after 3 sequential ACKs are missed" 
		SIMULATION: std_logic := '0'
			-- 1 during simulation with Wireshark .cap file, '0' otherwise
			-- Wireshark many not be able to collect offloaded checksum computations.
			-- when SIMULATION =  '1': (a) IP header checksum is valid if 0000,
			-- (b) TCP checksum computation is forced to a valid 00001 irrespective of the 16-bit checksum
			-- captured by Wireshark.
	);
    Port ( 
		--//-- CLK, RESET
		CLK: in std_logic;
			-- All signals are synchronous with CLK
			-- CLK must be a global clock 125 MHz or faster to match the Gbps MAC speed.
		SYNC_RESET: in std_logic;
		
		--//-- CONFIGURATION
		-- configuration signals are synchonous with CLK
		-- Synchronous with CLK clock.
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		DYNAMIC_IP: in std_logic;	
			-- '1' if dynamic IP address using an external DHCP server, '0' if fixed (static) IP address.
			-- Dynamic IP address requires the generic parameter DHCP_CLIENT_EN = '1' to instantiate a DHCP client within.
		REQUESTED_IPv4_ADDR: in std_logic_vector(31 downto 0);
			-- fixed IP address if static, or requested IP address if dynamic.
			-- In the case of dynamic IP, this is typically the last IP address, as stored in external non-volatile memory.
			-- In the case of dynamic IP, use 0.0.0.0 if no previous IP address is available.
			-- In the case of dynamic IP, this field is read only when SYNC_RESET = '1'
			-- Natural order (MSB) 172.16.1.128 (LSB) as transmitted in the IP frame.
		DHCPC_IPv4_ADDR_out: out std_logic_vector(31 downto 0);
			-- DHCP server-assigned address
		IPv6_ADDR: in std_logic_vector(127 downto 0);
			-- future
		MULTICAST_IP_ADDR: in std_logic_vector(31 downto 0); 
		    -- to receive UDP multicast messages. One multicast address only
            -- 0.0.0.0 to signify that IP multicasting is not supported here.
		IPv4_SUBNET_MASK: in std_logic_vector(31 downto 0);
			-- user-defined when DYNAMIC_IP = '0', otherwise automatically superseded by a DHCP server
		IPv4_GATEWAY_ADDR: in std_logic_vector(31 downto 0);
			-- Address where transmit IP frames will be sent to when the IP address is non-local (WAN) 
			-- user-defined when DYNAMIC_IP = '0', otherwise automatically superseded by a DHCP server
			

		--//-- Protocol -> Transmit MAC Interface
		-- 32-bit CRC is automatically appended by the MAC layer. User should not supply it.
		-- Synchonous with the user-side CLK
		MAC_TX_DATA: out std_logic_vector(7 downto 0);
			-- MAC reads the data at the rising edge of CLK when MAC_TX_DATA_VALID = '1'
		MAC_TX_DATA_VALID: out std_logic;
			-- data valid
		MAC_TX_SOF: out std_logic;
			-- start of frame: '1' when sending the first byte. 
			-- Aligned with MAC_TX_DATA_VALID
		MAC_TX_EOF: out std_logic;
			-- End of frame: '1' when sending the last byte in a packet to be transmitted. 
			-- Aligned with MAC_TX_DATA_VALID
		MAC_TX_CTS: in std_logic;
			-- MAC-generated Clear To Send flow control signal, indicating room in the 
			-- MAC tx elastic buffer for a complete maximum size frame 1518B. 
			-- The user should check that this signal is high before deciding to send
			-- sending the next frame. 
			-- Note: MAC_TX_CTS may go low while the frame is transfered in. Ignore it as space is guaranteed
			-- at the start of frame.
		MAC_TX_RTS: out std_logic;
			-- '1' when at least one of the inner processes is ready to transmit. Will on transmit when CTS goes high.
			-- useful if there is an external transmission arbiter (for example in the case of multiple clients)

		--//-- Receive MAC -> Protocol
		-- Valid rx packets only: packets with bad CRC or invalid address are discarded.
		-- The 32-bit CRC is always removed by the MAC layer.
		-- Synchonous with the user-side CLK
		MAC_RX_DATA: in std_logic_vector(7 downto 0);
			-- USER reads the data at the rising edge of CLK when MAC_RX_DATA_VALID = '1'
		MAC_RX_DATA_VALID: in std_logic;
			-- data valid
			-- ALWAYS ON FROM SOF TO EOF (i.e. no gaps)
		MAC_RX_SOF: in std_logic;
			-- '1' when sending the first byte in a received packet. 
			-- Aligned with MAC_RX_DATA_VALID
		MAC_RX_EOF: in std_logic;
			-- '1' when sending the last byte in a received packet. 
			-- Aligned with MAC_RX_DATA_VALID

		--//-- Application <- UDP rx
		UDP_RX_DATA: out std_logic_vector(7 downto 0);
		UDP_RX_DATA_VALID: out std_logic;
		UDP_RX_SOF: out std_logic;	
		UDP_RX_EOF: out std_logic;	
			-- 1 CLK pulse indicating that UDP_RX_DATA is the last byte in the UDP data field.
			-- ALWAYS CHECK UDP_RX_DATA_VALID at the end of packet (UDP_RX_EOF = '1') to confirm
			-- that the UDP packet is valid. External buffer may have to backtrack to the the last
			-- valid pointer to discard an invalid UDP packet.
			-- Reason: we only knows about bad UDP packets at the end.
		UDP_RX_DEST_PORT_NO_IN: in std_logic_vector(15 downto 0);
		CHECK_UDP_RX_DEST_PORT_NO: in std_logic;
			-- check the destination port number matches UDP_RX_DEST_PORT_NO (1) or ignore it (0)
			-- The latter case is useful when this component is shared among multiple UDP ports
		UDP_RX_DEST_PORT_NO_OUT: out std_logic_vector(15 downto 0);
			-- Collected destination UDP port in received UDP frame. Read when APP_EOF = '1' 
				
		--//-- Application -> UDP tx
		UDP_TX_DATA: in std_logic_vector(7 downto 0);
		UDP_TX_DATA_VALID: in std_logic;
		UDP_TX_SOF: in std_logic;	-- 1 CLK-wide pulse to mark the first byte in the tx UDP frame
		UDP_TX_EOF: in std_logic;	-- 1 CLK-wide pulse to mark the last byte in the tx UDP frame
		UDP_TX_CTS: out std_logic;	
		UDP_TX_ACK: out std_logic;	-- 1 CLK-wide pulse indicating that the previous UDP frame is being sent
		UDP_TX_NAK: out std_logic;	-- 1 CLK-wide pulse indicating that the previous UDP frame could not be sent
		UDP_TX_DEST_IP_ADDR: in std_logic_vector(127 downto 0);
		UDP_TX_DEST_PORT_NO: in std_logic_vector(15 downto 0);
		UDP_TX_SOURCE_PORT_NO: in std_logic_vector(15 downto 0);
			-- the IP and port information is latched in at the UDP_TX_SOF pulse.
			-- USAGE: wait until the previous UDP tx frame UDP_TX_ACK or UDP_TX_NAK to send the follow-on UDP tx frame
		
		--//-- Application controls of TCP clients 
		DEST_IPv4_ADDR: in SLV32xNTCPSTREAMStype;
		DEST_PORT: in SLV16xNTCPSTREAMStype;
			-- for each TCP client, specify the destination TCP server when STATE is idle, prior to requesting a connection
		STATE_REQUESTED: in SLV4xNTCPSTREAMStype;
			-- ask for TCP connection. Request states:
			-- 0 = go back to idle (terminate connection if currently connected or connecting)
			-- 1 = initiate connection
		STATE_STATUS: out SLV4xNTCPSTREAMStype;
			-- monitor connection state
			-- idle (0), connecting (1), connected (2), unreacheable IP (3), destination port busy (4)
		TCP_KEEPALIVE_EN: in std_logic_vector((NTCPSTREAMS-1) downto 0);
			-- enable TCP Keepalive (1) or not (0)
		
		
		--//-- Application <- TCP rx
		-- NTCPSTREAMS can operate independently and concurrently. No scheduling arbitration needed here.
		TCP_LOCAL_PORTS: in SLV16xNTCPSTREAMStype;
			-- TCP_CLIENTS ports configuration. Each one of the NTCPSTREAMS streams handled by this
			-- component must be configured with a distinct port number. 
			-- This value is used as destination port number to filter incoming packets, 
			-- and as source port number in outgoing packets.
		TCP_RX_DATA: out SLV8xNTCPSTREAMStype;
		TCP_RX_DATA_VALID: out std_logic_vector((NTCPSTREAMS-1) downto 0);
		TCP_RX_RTS: out std_logic_vector((NTCPSTREAMS-1) downto 0);	-- Ready To Send
		TCP_RX_CTS: in std_logic_vector((NTCPSTREAMS-1) downto 0);	-- Clear To Send
		
		--//-- Application -> TCP tx
		-- NTCPSTREAMS can operate independently and concurrently. No scheduling arbitration needed here.
		TCP_TX_DATA: in SLV8xNTCPSTREAMStype;
		TCP_TX_DATA_VALID: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		TCP_TX_CTS: out std_logic_vector((NTCPSTREAMS-1) downto 0);	
			-- Clear To Send = transmit flow control. 
			-- App is responsible for checking the CTS signal before sending APP_DATA

		--//-- TEST POINTS, COMSCOPE TRACES
		TCP_CONNECTED_FLAG: out std_logic_vector((NTCPSTREAMS-1) downto 0);
		CS1: out std_logic_vector(7 downto 0);
		CS1_CLK: out std_logic;
		CS2: out std_logic_vector(7 downto 0);
		CS2_CLK: out std_logic;
		TP: out std_logic_vector(10 downto 1)
	   
 );
end entity;

architecture Behavioral of COM5403 is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
	COMPONENT TIMER_4US
	GENERIC (
		CLK_FREQUENCY: integer 
	);
	PORT(
		CLK : IN std_logic;          
		SYNC_RESET : IN std_logic;
		TICK_4US : OUT std_logic;
		TICK_100MS: out std_logic
		);
	END COMPONENT;

	COMPONENT PACKET_PARSING
	GENERIC (
		IPv6_ENABLED: std_logic;
		SIMULATION: std_logic
	);	
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		TICK_4US : IN std_logic;
		MAC_RX_DATA : IN std_logic_vector(7 downto 0);
		MAC_RX_DATA_VALID : IN std_logic;
		MAC_RX_SOF : IN std_logic;
		MAC_RX_EOF : IN std_logic;
		IPv4_ADDR: in std_logic_vector(31 downto 0);
		IPv6_ADDR: in std_logic_vector(127 downto 0);
		IP_RX_DATA: out std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID: out std_logic;	
		IP_RX_DATA_VALID2: out std_logic;	
		IP_RX_SOF: out std_logic;
		IP_RX_EOF: out std_logic;
		IP_BYTE_COUNT: out std_logic_vector(15 downto 0);	
		IP_HEADER_FLAG: out std_logic;
		RX_TYPE : OUT std_logic_vector(3 downto 0);
		RX_TYPE_RDY : OUT std_logic;
		RX_IPv4_6n: out std_logic;
		RX_IP_PROTOCOL : OUT std_logic_vector(7 downto 0);
		RX_IP_PROTOCOL_RDY : OUT std_logic;
		VALID_DEST_IP : OUT std_logic;
		VALID_DEST_IP_RDY : OUT std_logic;
		IP_HEADER_CHECKSUM_VALID: out std_logic;
		IP_HEADER_CHECKSUM_VALID_RDY: out std_logic;
		RX_SOURCE_MAC_ADDR: out std_logic_vector(47 downto 0);
		RX_SOURCE_IP_ADDR: out std_logic_vector(127 downto 0);
		RX_SOURCE_TCP_PORT_NO: out std_logic_vector(15 downto 0);
		RX_DEST_IP_ADDR: out std_logic_vector(127 downto 0);
		RX_DEST_TCP_PORT_NO: out std_logic_vector(15 downto 0);
		RX_UDP_CKSUM: out std_logic_vector(16 downto 0);
		RX_UDP_CKSUM_RDY: out std_logic;
		RX_TCP_HEADER_FLAG: out std_logic;
		RX_TCP_FLAGS: out std_logic_vector(7 downto 0);
		RX_TCP_CKSUM: out std_logic_vector(16 downto 0);
		RX_TCP_SEQ_NO: out std_logic_vector(31 downto 0);
		RX_TCP_ACK_NO: out std_logic_vector(31 downto 0);
		RX_TCP_WINDOW_SIZE: out std_logic_vector(15 downto 0);
		
		CS1 : OUT std_logic_vector(7 downto 0);
		CS1_CLK : OUT std_logic;
		CS2 : OUT std_logic_vector(7 downto 0);
		CS2_CLK : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT PING
	GENERIC (
		IPv6_ENABLED: std_logic;
		MAX_PING_SIZE: std_logic_vector(15 downto 0)
	);	
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		MAC_RX_DATA : IN std_logic_vector(7 downto 0);
		MAC_RX_DATA_VALID : IN std_logic;
		MAC_RX_SOF : IN std_logic;
		MAC_RX_EOF : IN std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		IPv4_ADDR: in std_logic_vector(31 downto 0);
		IPv6_ADDR: in std_logic_vector(127 downto 0);
		RX_IPv4_6n: in std_logic;
		RX_IP_PROTOCOL : IN std_logic_vector(7 downto 0);
		RX_IP_PROTOCOL_RDY : IN std_logic;
		IP_RX_DATA_VALID: in std_logic;	
		IP_RX_EOF : IN std_logic;
		MAC_TX_CTS : IN std_logic;          
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		RTS : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT ARP
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		MAC_RX_DATA : IN std_logic_vector(7 downto 0);
		MAC_RX_DATA_VALID : IN std_logic;
		MAC_RX_SOF : IN std_logic;
		MAC_RX_EOF : IN std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		IPv4_ADDR: in std_logic_vector(31 downto 0);
		RX_TYPE : IN std_logic_vector(3 downto 0);
		RX_TYPE_RDY : IN std_logic;
		RX_SOURCE_MAC_ADDR: in std_logic_vector(47 downto 0);
		RX_SOURCE_IP_ADDR: in std_logic_vector(31 downto 0);
		MAC_TX_CTS : IN std_logic;          
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		RTS : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT WHOIS2
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		WHOIS_IP_ADDR : IN std_logic_vector(31 downto 0);
		WHOIS_START : IN std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		IPv4_ADDR : IN std_logic_vector(31 downto 0);
		MAC_TX_CTS : IN std_logic;          
		WHOIS_RDY : OUT std_logic;
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		RTS : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT ARP_CACHE2
	PORT(
		SYNC_RESET: in std_logic;
		CLK : IN std_logic;
		TICK_100MS : IN std_logic;          
		RT_IP_ADDR : IN std_logic_vector(31 downto 0);
		RT_REQ_RTS : IN std_logic;
		RT_CTS: out std_logic;	
		RT_MAC_REPLY : OUT std_logic_vector(47 downto 0);
		RT_MAC_RDY : OUT std_logic;
		RT_NAK: out std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		IPv4_ADDR : IN std_logic_vector(31 downto 0);
		SUBNET_MASK : IN std_logic_vector(31 downto 0);
		GATEWAY_IP_ADDR: in std_logic_vector(31 downto 0);
		RX_SOURCE_ADDR_RDY: in std_logic;
		RX_SOURCE_MAC_ADDR: in std_logic_vector(47 downto 0);	
		RX_SOURCE_IP_ADDR: in std_logic_vector(31 downto 0); 
		WHOIS_IP_ADDR : OUT std_logic_vector(31 downto 0);
		WHOIS_START : OUT std_logic;
		SREG1 : OUT std_logic_vector(7 downto 0);
		SREG2 : OUT std_logic_vector(7 downto 0);
		SREG3 : OUT std_logic_vector(7 downto 0);
		SREG4 : OUT std_logic_vector(7 downto 0);
		SREG5 : OUT std_logic_vector(7 downto 0);
		SREG6 : OUT std_logic_vector(7 downto 0);
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT DHCP_CLIENT
	GENERIC (
		SIMULATION: std_logic
	);	
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		TICK_4US : IN std_logic;
		TICK_100MS : IN std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		LAST_IPv4_ADDR : IN std_logic_vector(31 downto 0);
		IP_ID_IN : IN std_logic_vector(15 downto 0);
		IP_RX_DATA : IN std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID : IN std_logic;
		IP_RX_SOF : IN std_logic;
		IP_RX_EOF : IN std_logic;
		IP_BYTE_COUNT : IN std_logic_vector(15 downto 0);
		IP_HEADER_FLAG : IN std_logic;
		RX_IP_PROTOCOL : IN std_logic_vector(7 downto 0);
		RX_IP_PROTOCOL_RDY : IN std_logic;
		RX_SOURCE_IP_ADDR : IN std_logic_vector(31 downto 0);
		RX_UDP_CKSUM : IN std_logic_vector(16 downto 0);
		RX_UDP_CKSUM_RDY : IN std_logic;
		MAC_TX_CTS : IN std_logic;          
		IPv4_ADDR : OUT std_logic_vector(31 downto 0);
		LEASE_TIME : OUT std_logic_vector(31 downto 0);
		SUBNET_MASK : OUT std_logic_vector(31 downto 0);
		ROUTER : OUT std_logic_vector(31 downto 0);
		DNS1 : OUT std_logic_vector(31 downto 0);
		DNS2 : OUT std_logic_vector(31 downto 0);
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		RTS : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT IGMP_QUERY
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		MULTICAST_IP_ADDR : IN std_logic_vector(31 downto 0);
		IP_RX_DATA : IN std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID : IN std_logic;
		IP_RX_SOF : IN std_logic;
		IP_RX_EOF : IN std_logic;
		IP_BYTE_COUNT : IN std_logic_vector(15 downto 0);
		IP_HEADER_FLAG : IN std_logic;
		RX_IP_PROTOCOL : IN std_logic_vector(7 downto 0);
		RX_IP_PROTOCOL_RDY : IN std_logic;          
		RX_DEST_IP_ADDR: in std_logic_vector(31 downto 0);
		TRIGGER_RESPONSE : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT IGMP_REPORT
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		MULTICAST_IP_ADDR : IN std_logic_vector(31 downto 0);
		IGMP_START : IN std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		IPv4_ADDR : IN std_logic_vector(31 downto 0);
		IP_ID : IN std_logic_vector(15 downto 0);
		MAC_TX_CTS : IN std_logic;          
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		RTS : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT UDP2SERIAL
	GENERIC (
		PORT_NO: std_logic_vector(15 downto 0);
		CLK_FREQUENCY: integer
	);	
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		IP_RX_DATA : IN std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID : IN std_logic;
		IP_RX_SOF : IN std_logic;
		IP_RX_EOF : IN std_logic;
		IP_HEADER_FLAG : IN std_logic;
		RX_IP_PROTOCOL : IN std_logic_vector(7 downto 0);
		RX_IP_PROTOCOL_RDY : IN std_logic;
		SERIAL_OUT : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT UDP_RX
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		IP_RX_DATA : IN std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID : IN std_logic;
		IP_RX_SOF : IN std_logic;
		IP_RX_EOF : IN std_logic;
		IP_BYTE_COUNT: in std_logic_vector(15 downto 0);	
		IP_HEADER_FLAG : IN std_logic;
		RX_IP_PROTOCOL : IN std_logic_vector(7 downto 0);
		RX_IP_PROTOCOL_RDY : IN std_logic;          
		RX_UDP_CKSUM: in std_logic_vector(16 downto 0);
		RX_UDP_CKSUM_RDY: in std_logic;
		PORT_NO: in std_logic_vector(15 downto 0);
		CHECK_UDP_RX_DEST_PORT_NO: in std_logic;
		APP_DATA : OUT std_logic_vector(7 downto 0);
		APP_DATA_VALID : OUT std_logic;
		APP_SOF : OUT std_logic;
		APP_EOF : OUT std_logic;
		APP_SRC_UDP_PORT: OUT std_logic_vector(15 downto 0);			
		APP_DEST_UDP_PORT: out std_logic_vector(15 downto 0);
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT UDP_TX
	generic (
		NBUFS: integer ;
		IPv6_ENABLED: std_logic
	);
	PORT(
		CLK : IN std_logic;
		SYNC_RESET : IN std_logic;
		TICK_4US: in std_logic;
		APP_DATA : IN std_logic_vector(7 downto 0);
		APP_DATA_VALID : IN std_logic;
		APP_SOF : IN std_logic;
		APP_EOF : IN std_logic;
		APP_CTS : OUT std_logic;
		DEST_IP_ADDR: in std_logic_vector(127 downto 0);	
		DEST_PORT_NO : IN std_logic_vector(15 downto 0);
		SOURCE_PORT_NO : IN std_logic_vector(15 downto 0);
		IPv4_6n: in std_logic;
		MAC_ADDR: in std_logic_vector(47 downto 0);
		IPv4_ADDR: in std_logic_vector(31 downto 0);
		IPv6_ADDR: in std_logic_vector(127 downto 0);
		IP_ID: in std_logic_vector(15 downto 0);
		ACK : OUT std_logic;
		NAK : OUT std_logic;
		RT_IP_ADDR : OUT std_logic_vector(31 downto 0);
		RT_REQ_RTS: out std_logic;
		RT_REQ_CTS: in std_logic;
		RT_MAC_REPLY : IN std_logic_vector(47 downto 0);
		RT_MAC_RDY : IN std_logic;
		RT_NAK: in std_logic;
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		MAC_TX_CTS : IN std_logic;          
		RTS: out std_logic := '0';
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT TCP_CLIENTS
	GENERIC (
		NTCPSTREAMS: integer;  
		MSS: integer;
		TCP_KEEPALIVE_PERIOD: integer;
		IPv6_ENABLED: std_logic;
		SIMULATION: std_logic
	);	
	PORT(
		CLK : IN std_logic;
		SYNC_RESET: in std_logic;
		TICK_4US : IN std_logic;
		TICK_100MS : IN std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		TCP_LOCAL_PORTS: in SLV16xNTCPSTREAMStype;
		DEST_IPv4_ADDR: in SLV32xNTCPSTREAMStype;
		DEST_PORT: in SLV16xNTCPSTREAMStype;
		STATE_REQUESTED: in SLV4xNTCPSTREAMStype;
		STATE_STATUS: out SLV4xNTCPSTREAMStype;
		TCP_KEEPALIVE_EN: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		RT_IP_ADDR: out std_logic_vector(31 downto 0);
		RT_REQ_RTS: out std_logic;
		RT_REQ_CTS: in std_logic;
		RT_MAC_REPLY: in std_logic_vector(47 downto 0);
		RT_MAC_RDY: in std_logic;
		RT_NAK: in std_logic;
		IP_RX_DATA: in std_logic_vector(7 downto 0);
		IP_RX_DATA_VALID: in std_logic;	
		IP_RX_SOF: in std_logic;
		IP_RX_EOF: in std_logic;
		IP_BYTE_COUNT: in std_logic_vector(15 downto 0);	
		IP_HEADER_FLAG: in std_logic;
		RX_IPv4_6n: in std_logic;
		RX_IP_PROTOCOL: in std_logic_vector(7 downto 0);
	  	RX_IP_PROTOCOL_RDY: in std_logic;
		RX_SOURCE_MAC_ADDR: in std_logic_vector(47 downto 0);
		RX_SOURCE_IP_ADDR: in std_logic_vector(127 downto 0);
		RX_SOURCE_TCP_PORT_NO: in std_logic_vector(15 downto 0);
		RX_TCP_HEADER_FLAG: in std_logic;
		RX_TCP_FLAGS: in std_logic_vector(7 downto 0);
		RX_TCP_CKSUM: in std_logic_vector(16 downto 0);
		RX_TCP_SEQ_NO: in std_logic_vector(31 downto 0);
		RX_TCP_ACK_NO: in std_logic_vector(31 downto 0);
		RX_TCP_WINDOW_SIZE: in std_logic_vector(15 downto 0);
		RX_DEST_TCP_PORT_NO: in std_logic_vector(15 downto 0);
		RX_DATA: out std_logic_vector(7 downto 0);
		RX_DATA_VALID: out std_logic;
		RX_SOF: out std_logic;
		RX_STREAM_SEL: out std_logic_vector((NTCPSTREAMS-1) downto 0);
		RX_EOF: out std_logic;
		RX_FREE_SPACE: in SLV16xNTCPSTREAMStype;
		TX_PACKET_SEQUENCE_START_OUT: out std_logic;	
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
		MAC_TX_EOF: in std_logic;	-- need to know when packet tx is complete
		RTS: out std_logic := '0';
		EFF_RX_WINDOW_SIZE_PARTIAL: out std_logic_vector(16 downto 0);
		EFF_RX_WINDOW_SIZE_PARTIAL_STREAM: out std_logic_vector(NTCPSTREAMS-1 downto 0) := (others => '0');
		EFF_RX_WINDOW_SIZE_PARTIAL_VALID: out std_logic; -- 1 CLK-wide pulse to indicate that the above information is valid
		TX_SEQ_NO: out SLV17xNTCPSTREAMStype;
		TX_SEQ_NO_JUMP: out std_logic_vector(NTCPSTREAMS-1 downto 0);
		RX_TCP_ACK_NO_D: out SLV17xNTCPSTREAMStype;
		CONNECTED_FLAG: out std_logic_vector((NTCPSTREAMS-1) downto 0);
		TX_STREAM_SEL: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		TX_PAYLOAD_RTS: in std_logic;
		TX_PAYLOAD_SIZE: in std_logic_vector(15 downto 0);
		TP: out std_logic_vector(10 downto 1)
		);
	END COMPONENT;

	COMPONENT TCP_TXBUF is
		generic (
			NTCPSTREAMS: integer;  
			MSS: integer;
			ADDR_WIDTH: integer range 8 to 15;
			OB_ADDR_WIDTH: integer range 8 to 15;
			TX_IDLE_TIMEOUT: integer range 0 to 50;	
			SIMULATION: std_logic
		);
		 Port ( 
			--//-- CLK, RESET
			CLK: in std_logic;		
			SYNC_RESET: in std_logic;
			TICK_4US: in std_logic;
			APP_DATA: in SLV8xNTCPSTREAMStype;
			APP_DATA_VALID: in std_logic_vector((NTCPSTREAMS-1) downto 0);
			APP_CTS: out std_logic_vector((NTCPSTREAMS-1) downto 0);	
			APP_DATA_FLUSH: in std_logic_vector((NTCPSTREAMS-1) downto 0);	
			EFF_RX_WINDOW_SIZE_PARTIAL_IN: in std_logic_vector(16 downto 0);
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM: in std_logic_vector((NTCPSTREAMS-1) downto 0);	
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID: in std_logic; -- 1 CLK-wide pulse to indicate that the above information is valid
			TX_SEQ_NO_IN: in SLV17xNTCPSTREAMStype;
			TX_SEQ_NO_JUMP: in std_logic_vector(NTCPSTREAMS-1 downto 0);
			RX_TCP_ACK_NO_D: in SLV17xNTCPSTREAMStype;
			CONNECTED_FLAG: in std_logic_vector((NTCPSTREAMS-1) downto 0);
			TX_STREAM_SEL: out std_logic_vector((NTCPSTREAMS-1) downto 0)  := (others => '0');	
			TX_PAYLOAD_RTS: out std_logic;
			TX_PAYLOAD_CHECKSUM: out std_logic_vector(16 downto 0);
			TX_PAYLOAD_SIZE: out std_logic_vector(15 downto 0);
			TX_PAYLOAD_CTS: in std_logic;
			TX_PAYLOAD_DATA: out std_logic_vector(7 downto 0);
			TX_PAYLOAD_DATA_VALID: out std_logic;
			TX_PAYLOAD_DATA_EOF: out std_logic;
			TP: out std_logic_vector(10 downto 1)

				);
	end COMPONENT;
	

	COMPONENT TCP_TX
	GENERIC (
		MSS: std_logic_vector(15 downto 0);	
		IPv6_ENABLED: std_logic
	);	
	PORT(
		CLK : IN std_logic;
		SYNC_RESET: in std_logic;
		MAC_ADDR : IN std_logic_vector(47 downto 0);
		IPv4_ADDR : IN std_logic_vector(31 downto 0);
		IPv6_ADDR : IN std_logic_vector(127 downto 0);
		TX_PACKET_SEQUENCE_START : IN std_logic;
		TX_DEST_MAC_ADDR_IN : IN std_logic_vector(47 downto 0);
		TX_DEST_IP_ADDR_IN : IN std_logic_vector(127 downto 0);
		TX_DEST_PORT_NO_IN : IN std_logic_vector(15 downto 0);
		TX_SOURCE_PORT_NO_IN : IN std_logic_vector(15 downto 0);
		TX_IPv4_6n_IN : IN std_logic;
		TX_SEQ_NO_IN : IN std_logic_vector(31 downto 0);
		TX_ACK_NO_IN : IN std_logic_vector(31 downto 0);
		TX_ACK_WINDOW_LENGTH_IN : IN std_logic_vector(15 downto 0);
		IP_ID_IN : IN std_logic_vector(15 downto 0);
		TX_FLAGS_IN : IN std_logic_vector(7 downto 0);
		TX_PACKET_TYPE_IN : IN std_logic_vector(1 downto 0);
		TX_PAYLOAD_DATA : IN std_logic_vector(7 downto 0);
		TX_PAYLOAD_DATA_VALID : IN std_logic;
		TX_PAYLOAD_DATA_EOF: in std_logic;
		TX_PAYLOAD_RTS : IN std_logic;
		TX_PAYLOAD_CTS : OUT std_logic;
		TX_PAYLOAD_SIZE : IN std_logic_vector(15 downto 0);
		TX_PAYLOAD_CHECKSUM: in std_logic_vector(16 downto 0);
		MAC_TX_CTS : IN std_logic;          
		MAC_TX_DATA : OUT std_logic_vector(7 downto 0);
		MAC_TX_DATA_VALID : OUT std_logic;
		MAC_TX_EOF : OUT std_logic;
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;
	

	COMPONENT TCP_RXBUFNDEMUX2
	GENERIC (
		NTCPSTREAMS: integer;  
--		ADDR_WIDTH: integer range 8 to 12
		ADDR_WIDTH: integer range 8 to 13
	);	
	PORT(
		SYNC_RESET : IN std_logic;
		CLK : IN std_logic;
		RX_DATA : IN std_logic_vector(7 downto 0);
		RX_DATA_VALID : IN std_logic;
		RX_SOF : IN std_logic;
		RX_TCP_STREAM_SEL: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		RX_EOF : IN std_logic;
		RX_FREE_SPACE: OUT SLV16xNTCPSTREAMStype;
		RX_APP_DATA: out SLV8xNTCPSTREAMStype;
		RX_APP_DATA_VALID: out std_logic_vector((NTCPSTREAMS-1) downto 0);
		RX_APP_RTS: out std_logic_vector((NTCPSTREAMS-1) downto 0);
		RX_APP_CTS: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		TP : OUT std_logic_vector(10 downto 1)
		);
	END COMPONENT;


--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------
-- NOTATIONS: 
-- _E as one-CLK early sample
-- _D as one-CLK delayed sample
-- _D2 as two-CLKs delayed sample

--//-- TIMERS -----------------------------
signal TICK_4US: std_logic := '0';
signal TICK_100MS_rt: std_logic := '0';
signal TICK_100MS: std_logic := '0';
signal TICK_CNTR: std_logic_vector(6 downto 0) := (others => '0');       
signal TICK_CNTR2: std_logic_vector(9 downto 0) := (others => '0');       

--//-- MAC INTERFACE --------------
signal MAC_TX_DATA_VALID_local : std_logic  := '0';
signal MAC_TX_EOF_FLAG : std_logic  := '0';
signal MAC_TX_EOF_local : std_logic  := '0';

--//-- PARSE INCOMING PACKET --------------
signal RX_TYPE: std_logic_vector(3 downto 0) := (others => '0');
signal RX_TYPE_RDY : std_logic  := '0';
signal RX_IPv4_6n : std_logic  := '0';
signal RX_IP_PROTOCOL : std_logic_vector(7 downto 0) := (others => '0');
signal RX_IP_PROTOCOL_RDY : std_logic  := '0';
signal IP_RX_DATA : std_logic_vector(7 downto 0) := (others => '0');
signal IP_RX_DATA_VALID : std_logic  := '0';
signal IP_RX_DATA_VALID2 : std_logic  := '0';
signal IP_RX_SOF : std_logic  := '0';
signal IP_RX_EOF : std_logic  := '0';
signal IP_BYTE_COUNT : std_logic_vector(15 downto 0) := (others => '0');
signal IP_HEADER_FLAG : std_logic  := '0';
signal RX_UDP_CKSUM: std_logic_vector(16 downto 0) := (others => '0');
signal RX_UDP_CKSUM_RDY: std_logic := '0';
signal RX_TCP_HEADER_FLAG: std_logic  := '0';
signal RX_TCP_FLAGS: std_logic_vector(7 downto 0) := (others => '0');
signal RX_TCP_CKSUM: std_logic_vector(16 downto 0) := (others => '0');
signal RX_TCP_SEQ_NO: std_logic_vector(31 downto 0) := (others => '0');
signal RX_TCP_ACK_NO: std_logic_vector(31 downto 0) := (others => '0');
signal RX_TCP_WINDOW_SIZE: std_logic_vector(15 downto 0) := (others => '0');
signal RX_DEST_TCP_PORT_NO: std_logic_vector(15 downto 0) := (others => '0');
signal TP_PARSING: std_logic_vector(10 downto 1);
signal RX_SOURCE_MAC_ADDR: std_logic_vector(47 downto 0) := (others => '0');
signal RX_SOURCE_IP_ADDR: std_logic_vector(127 downto 0) := (others => '0');
signal RX_SOURCE_TCP_PORT_NO: std_logic_vector(15 downto 0) := (others => '0');
signal RX_DEST_IP_ADDR: std_logic_vector(127 downto 0) := (others => '0');
signal IP_HEADER_CHECKSUM_VALID: std_logic := '0';
signal IP_HEADER_CHECKSUM_VALID_RDY: std_logic := '0';

--//-- ARP REPLY --------------
signal ARP_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal ARP_MAC_TX_DATA_VALID: std_logic := '0';
signal ARP_MAC_TX_EOF: std_logic := '0';
signal ARP_MAC_TX_CTS: std_logic := '0';
signal ARP_RTS: std_logic := '0';
signal TP_ARP: std_logic_vector(10 downto 1);

--//-- PING REPLY --------------
signal PING_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal PING_MAC_TX_DATA_VALID: std_logic := '0';
signal PING_MAC_TX_EOF: std_logic := '0';
signal PING_MAC_TX_CTS: std_logic := '0';
signal PING_RTS: std_logic := '0';
signal TP_PING: std_logic_vector(10 downto 1);

--//-- WHOIS ---------------------------------------------
signal WHOIS_IP_ADDR: std_logic_vector(31 downto 0) := (others => '0');
signal WHOIS_START: std_logic := '0';
signal WHOIS_RDY: std_logic := '0';
signal WHOIS_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal WHOIS_MAC_TX_DATA_VALID: std_logic := '0';
signal WHOIS_MAC_TX_EOF: std_logic := '0';
signal WHOIS_MAC_TX_CTS: std_logic := '0';
signal WHOIS_RTS: std_logic := '0';
signal TP_WHOIS: std_logic_vector(10 downto 1)  := (others => '0');

--//-- ARP CACHE  -----------------------------------------
signal RT_IP_ADDR: std_logic_vector(31 downto 0) := (others => '0');
signal RT_REQ_RTS: std_logic := '0';
signal RT_CTS: std_logic := '0';
signal RT_MAC_REPLY: std_logic_vector(47 downto 0) := (others => '0');
signal RT_MAC_RDY:  std_logic := '0';
signal RT_NAK:  std_logic := '0';
signal TP_ARP_CACHE2: std_logic_vector(10 downto 1)  := (others => '0');

--//-- DHCP CLIENT ------------------------------------
signal IPv4_ADDR: std_logic_vector(31 downto 0) := (others => '0'); 
signal IPv4_SUBNET_MASK_local: std_logic_vector(31 downto 0) := (others => '0'); 
signal IPv4_GATEWAY_ADDR_local: std_logic_vector(31 downto 0) := (others => '0'); 
signal DHCPC_SYNC_RESET: std_logic := '0';
signal DHCPC_IPv4_ADDR: std_logic_vector(31 downto 0) := (others => '0'); 
signal DHCP_SUBNET_MASK: std_logic_vector(31 downto 0) := (others => '0'); 
signal DHCP_ROUTER: std_logic_vector(31 downto 0) := (others => '0'); 
signal DHCP_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal DHCP_MAC_TX_DATA_VALID: std_logic := '0';
signal DHCP_MAC_TX_EOF: std_logic := '0';
signal DHCP_MAC_TX_CTS: std_logic := '0';
signal DHCP_RTS: std_logic := '0';
signal TP_DHCP: std_logic_vector(10 downto 1)  := (others => '0');

--//-- IGMP (MULTICAST) -----------------------------------------
signal IGMP_REPORT_START: std_logic := '0';
signal IGMP_TRIGGER_RESPONSE: std_logic := '0';
signal IGMP_TRIGGER_RESPONSE2: std_logic := '0';
signal IGMP_TRIGGER_RESPONSE3: std_logic := '0';
signal IGMP_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal IGMP_MAC_TX_DATA_VALID: std_logic := '0';
signal IGMP_MAC_TX_EOF: std_logic := '0';
signal IGMP_MAC_TX_CTS: std_logic := '0';
signal IGMP_RTS: std_logic := '0';
signal TP_IGMP: std_logic_vector(10 downto 1) := (others => '0');

--//-- UDP RX ------------------------------------
signal UDP_RX_VALID_DEST_IP: std_logic := '0';
signal IP_RX_DATA_VALID3 : std_logic  := '0';
signal TP_UDP_RX: std_logic_vector(10 downto 1) := (others => '0');

--//-- UDP TX ------------------------------------
signal UDP001_RT_REQ_RTS: std_logic := '0';
signal UDP001_RT_REQ_CTS: std_logic := '0';
signal UDP001_RT_IP_ADDR: std_logic_vector(31 downto 0) := (others => '0');
signal UDP001_RT_MAC_RDY: std_logic := '0';
signal UDP001_RT_NAK: std_logic := '0';
signal UDP001_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal UDP001_MAC_TX_DATA_VALID: std_logic := '0';
signal UDP001_MAC_TX_EOF: std_logic := '0';
signal UDP001_MAC_TX_CTS: std_logic := '0';
signal UDP001_RTS: std_logic := '0';
signal TP_UDP_TX: std_logic_vector(10 downto 1) := (others => '0');
signal UDP_TX_ACK_local: std_logic := '0';
signal UDP_TX_NAK_local: std_logic := '0';

--//-- TCP RX ------------------------------------
-- TCP CLIENTS 001
signal TCP001_SYNC_RESET: std_logic := '0'; 
signal TCP001_RT_REQ_RTS: std_logic := '0';
signal TCP001_RT_REQ_CTS: std_logic := '0';
signal TCP001_RT_IP_ADDR: std_logic_vector(31 downto 0) := (others => '0');
signal TCP001_RT_MAC_RDY: std_logic := '0';
signal TCP001_RT_NAK: std_logic := '0';
signal TCP001_MAC_TX_DATA: std_logic_vector(7 downto 0) := x"00";
signal TCP001_MAC_TX_DATA_VALID: std_logic := '0';
signal TCP001_MAC_TX_EOF: std_logic := '0';
signal TCP001_MAC_TX_CTS: std_logic := '0';
signal TCP001_RTS: std_logic := '0';
signal TCP001_RX_DATA: std_logic_vector(7 downto 0) := x"00";
signal TCP001_RX_DATA_VALID: std_logic := '0';
signal TCP001_RX_SOF: std_logic := '0';
signal TCP001_RX_STREAM_SEL: std_logic_vector(NTCPSTREAMS-1 downto 0) := (others => '0');	
signal TCP001_RX_EOF: std_logic := '0';
signal TCP001_RX_FREE_SPACE: SLV16xNTCPSTREAMStype;
signal TCP001_TX_PACKET_SEQUENCE_START: std_logic  := '0';
signal TCP001_TX_DEST_MAC_ADDR: std_logic_vector(47 downto 0) := (others => '0');
signal TCP001_TX_DEST_IP_ADDR: std_logic_vector(127 downto 0) := (others => '0');
signal TCP001_TX_DEST_PORT_NO: std_logic_vector(15 downto 0) := (others => '0');
signal TCP001_TX_SOURCE_PORT_NO: std_logic_vector(15 downto 0) := (others => '0');
signal TCP001_TX_IPv4_6n: std_logic  := '0';
signal TCP001_TX_SEQ_NO: std_logic_vector(31 downto 0) := (others => '0');
signal TCP001_TX_ACK_NO: std_logic_vector(31 downto 0) := (others => '0');
signal TCP001_TX_ACK_WINDOW_LENGTH: std_logic_vector(15 downto 0) := (others => '0');
signal TCP001_TX_FLAGS: std_logic_vector(7 downto 0) := (others => '0');
signal TCP001_TX_PACKET_TYPE: std_logic_vector(1 downto 0) := (others => '0');
signal TCP001_EFF_RX_WINDOW_SIZE_PARTIAL: std_logic_vector(16 downto 0) := (others => '0');
signal TCP001_EFF_RX_WINDOW_SIZE_PARTIAL_STREAM: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal TCP001_EFF_RX_WINDOW_SIZE_PARTIAL_VALID: std_logic := '0'; -- 1 CLK-wide pulse to indicate that the above information is valid
signal TCP001_TX_SEQ_NOxNTCPSTREAMS: SLV17xNTCPSTREAMStype;
signal TCP001_TX_SEQ_NO_JUMP: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal TCP001_RX_ACK_NOxNTCPSTREAMS: SLV17xNTCPSTREAMStype;
signal TCP001_CONNECTED_FLAG: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal TCP001_TX_PAYLOAD_DATA: std_logic_vector(7 downto 0) := x"00";
signal TCP001_TX_PAYLOAD_DATA_VALID: std_logic := '0';
signal TCP001_TX_PAYLOAD_DATA_EOF: std_logic := '0';
signal TCP001_TX_PAYLOAD_RTS: std_logic := '0';
signal TCP001_TX_PAYLOAD_CTS: std_logic := '0';
signal TCP001_TX_PAYLOAD_SIZE: std_logic_vector(15 downto 0) := (others => '0');
signal TCP001_TX_PAYLOAD_CHECKSUM: std_logic_vector(16 downto 0) := "0" & x"0000";
signal TCP001_TX_STREAM_SEL: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');	
-- TODO DEL
signal TCP001_TX_STREAM_SELint: integer range 0 to (NTCPSTREAMS-1);	
signal TCP001_TCP_TX_CTS: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');	
signal TP_TCP_CLIENTS: std_logic_vector(10 downto 1);
signal TP_TCP_TXBUF: std_logic_vector(10 downto 1);

-- TCP client 002...etc

--//-- APP -> TCP TX BUFFER
signal TCP_TXBUF_DATA: std_logic_vector(7 downto 0) := x"00";
signal TCP_TXBUF_DATA_VALID: std_logic := '0';
signal TCP_TXBUF_SOF: std_logic := '0';
signal TCP_TXBUF_EOF: std_logic := '0';
signal TCP_TXBUF_RTS: std_logic := '0';
signal TCP_TXBUF_CTS: std_logic := '0';
--???signal TCP_TXBUF_PAYLOAD_SIZE: std_logic_vector(15 downto 0) := x"0000";
signal TCP_TXBUF_PARTIAL_CKSUM: std_logic_vector(15 downto 0) := x"0000";
signal TCP_TXBUF_RPTR: std_logic_vector(31 downto 0) := x"00000000";
signal TCP_TXBUF_RPTR_CONFIRMED: std_logic_vector(31 downto 0) := x"00000000";


--//-- TRANSMISSION ARBITER --------------
signal IP_ID: std_logic_vector(15 downto 0) := x"0000";
signal TX_MUX_STATE: integer range 0 to 10;	-- up to 10 protocol engines. Increase size if more.

--//-- ROUTING TABLE ARBITER --------------
signal RT_MUX_STATE: integer range 0 to 10;	
	-- 1 + number of transmit components vying for access to the routing table. Adjust as needed.

--//-- TEST POINTS 
------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

--//-- TIMERS -----------------------------
	Inst_TIMER_4US: TIMER_4US 
	GENERIC MAP(
		CLK_FREQUENCY => CLK_FREQUENCY
	)
	PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		TICK_4US => TICK_4US,
		TICK_100MS => TICK_100MS_rt
	);

TICK_100MS <= TICK_4US when (SIMULATION = '1') else TICK_100MS_rt;	-- to accelerate simulations


--//-- PARSE INCOMING PACKET --------------
-- Code is common to all protocols. Extracts key information from incoming packets.
	Inst_PACKET_PARSING: PACKET_PARSING 
	GENERIC MAP(
		IPv6_ENABLED => '0',
		SIMULATION => SIMULATION
	)
	PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		TICK_4US => TICK_4US,
		MAC_RX_DATA => MAC_RX_DATA,
		MAC_RX_DATA_VALID => MAC_RX_DATA_VALID,
		MAC_RX_SOF => MAC_RX_SOF,
		MAC_RX_EOF => MAC_RX_EOF,
		IPv4_ADDR => IPv4_ADDR,
		IPv6_ADDR => IPv6_ADDR,
		IP_RX_DATA => IP_RX_DATA,
		IP_RX_DATA_VALID => IP_RX_DATA_VALID,
		IP_RX_DATA_VALID2 => IP_RX_DATA_VALID2,   -- same as IP_RX_DATA_VALID but no IP destination addr check
		IP_RX_SOF => IP_RX_SOF,
		IP_RX_EOF => IP_RX_EOF,
		IP_BYTE_COUNT => IP_BYTE_COUNT,
		IP_HEADER_FLAG => IP_HEADER_FLAG,
		RX_TYPE => RX_TYPE,
		RX_TYPE_RDY => RX_TYPE_RDY,
		RX_IPv4_6n => RX_IPv4_6n,
		RX_IP_PROTOCOL => RX_IP_PROTOCOL,
		RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
		VALID_DEST_IP => open,
		VALID_DEST_IP_RDY => open,
		IP_HEADER_CHECKSUM_VALID => IP_HEADER_CHECKSUM_VALID,
		IP_HEADER_CHECKSUM_VALID_RDY => IP_HEADER_CHECKSUM_VALID_RDY,
		RX_SOURCE_MAC_ADDR => RX_SOURCE_MAC_ADDR,
		RX_SOURCE_IP_ADDR => RX_SOURCE_IP_ADDR,
		RX_SOURCE_TCP_PORT_NO => RX_SOURCE_TCP_PORT_NO,
		RX_DEST_IP_ADDR => RX_DEST_IP_ADDR,
		RX_DEST_TCP_PORT_NO => RX_DEST_TCP_PORT_NO,
		RX_UDP_CKSUM => RX_UDP_CKSUM,
		RX_UDP_CKSUM_RDY => RX_UDP_CKSUM_RDY,
--		RX_TCP_BYTE_COUNT => RX_TCP_BYTE_COUNT,
		RX_TCP_HEADER_FLAG => RX_TCP_HEADER_FLAG,
		RX_TCP_FLAGS => RX_TCP_FLAGS,
		RX_TCP_CKSUM => RX_TCP_CKSUM,
		RX_TCP_SEQ_NO => RX_TCP_SEQ_NO,
		RX_TCP_ACK_NO => RX_TCP_ACK_NO,
		RX_TCP_WINDOW_SIZE => RX_TCP_WINDOW_SIZE,
		CS1 => open,
		CS1_CLK => open,
		CS2 => open,
		CS2_CLK => open,
		TP => TP_PARSING
	);
	
	
--//-- ARP REPLY --------------
-- Instantiated once per PHY.   IPv4-only. Use NDP for IPv6.
	Inst_ARP: ARP 
	PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		MAC_RX_DATA => MAC_RX_DATA,
		MAC_RX_DATA_VALID => MAC_RX_DATA_VALID,
		MAC_RX_SOF => MAC_RX_SOF,
		MAC_RX_EOF => MAC_RX_EOF,
		MAC_ADDR => MAC_ADDR,
		IPv4_ADDR => IPv4_ADDR,
		RX_TYPE => RX_TYPE,
		RX_TYPE_RDY => RX_TYPE_RDY,
		RX_SOURCE_MAC_ADDR => RX_SOURCE_MAC_ADDR,
		RX_SOURCE_IP_ADDR => RX_SOURCE_IP_ADDR(31 downto 0),
		MAC_TX_DATA => ARP_MAC_TX_DATA,
		MAC_TX_DATA_VALID => ARP_MAC_TX_DATA_VALID,
		MAC_TX_EOF => ARP_MAC_TX_EOF,
		MAC_TX_CTS => ARP_MAC_TX_CTS,
		RTS => ARP_RTS,
		TP => TP_ARP
	);
	
--//-- PING REPLY --------------
-- Instantiated once per PHY.
	Inst_PING: PING 
	GENERIC MAP(
		IPv6_ENABLED => '0',
		MAX_PING_SIZE => x"0200"	-- 512 byte threshold for ping requests
	)
	PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		MAC_RX_DATA => MAC_RX_DATA,
		MAC_RX_DATA_VALID => MAC_RX_DATA_VALID,
		MAC_RX_SOF => MAC_RX_SOF,
		MAC_RX_EOF => MAC_RX_EOF,
		MAC_ADDR => MAC_ADDR,
		IPv4_ADDR => IPv4_ADDR,
		IPv6_ADDR => IPv6_ADDR,
		RX_IPv4_6n => RX_IPv4_6n,
		RX_IP_PROTOCOL => RX_IP_PROTOCOL,
		RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
		IP_RX_DATA_VALID => IP_RX_DATA_VALID,
		IP_RX_EOF => IP_RX_EOF,		
		MAC_TX_DATA => PING_MAC_TX_DATA,	
		MAC_TX_DATA_VALID => PING_MAC_TX_DATA_VALID,
		MAC_TX_EOF => PING_MAC_TX_EOF,
		MAC_TX_CTS => PING_MAC_TX_CTS,
		RTS => PING_RTS,
		TP => TP_PING
	);
	
--//-- WHOIS ---------------------------------------------
-- Sends ARP requests 
-- Currently only used by UDP tx and TCP clients
WHOIS2_X: if(NUDPTX /= 0) or (NTCPSTREAMS /= 0) generate
	WHOIS2_001: WHOIS2 PORT MAP(
		SYNC_RESET => SYNC_RESET,
		CLK => CLK,
		WHOIS_IP_ADDR => WHOIS_IP_ADDR,
		WHOIS_START => WHOIS_START,
		WHOIS_RDY => WHOIS_RDY,  -- unused
		MAC_ADDR => MAC_ADDR,
		IPv4_ADDR => IPv4_ADDR,
		MAC_TX_DATA => WHOIS_MAC_TX_DATA,
		MAC_TX_DATA_VALID => WHOIS_MAC_TX_DATA_VALID,
		MAC_TX_EOF => WHOIS_MAC_TX_EOF,
		MAC_TX_CTS => WHOIS_MAC_TX_CTS,
		RTS => WHOIS_RTS,
		TP => TP_WHOIS
	);
end generate;

--//-- ARP CACHE  (ROUTING TABLE) -----------------------------------------
-- Routing table mapping destination IP addresses and associated MAC addresses.
-- Currently only used by UDP tx and TCP clients
ARP_CACHE2_X: if(NUDPTX /= 0) or (NTCPSTREAMS /= 0) generate
	ARP_CACHE2_001: ARP_CACHE2 PORT MAP(
		SYNC_RESET => SYNC_RESET,
		CLK => CLK,
		TICK_100MS => TICK_100MS,
		RT_IP_ADDR => RT_IP_ADDR,	
		RT_REQ_RTS => RT_REQ_RTS,	
		RT_CTS => RT_CTS,	
		RT_MAC_REPLY => RT_MAC_REPLY,
		RT_MAC_RDY => RT_MAC_RDY,
		RT_NAK => RT_NAK,
		MAC_ADDR => MAC_ADDR,
		IPv4_ADDR => IPv4_ADDR,
		SUBNET_MASK => IPv4_SUBNET_MASK_local,
		GATEWAY_IP_ADDR => IPv4_GATEWAY_ADDR_local,
		WHOIS_IP_ADDR => WHOIS_IP_ADDR,
		WHOIS_START => WHOIS_START,
		RX_SOURCE_ADDR_RDY => MAC_RX_EOF,
		RX_SOURCE_MAC_ADDR => RX_SOURCE_MAC_ADDR,
		RX_SOURCE_IP_ADDR => RX_SOURCE_IP_ADDR(31 downto 0),	-- IPv4 only
		SREG1 => open,
		SREG2 => open,
		SREG3 => open,
		SREG4 => open,
		SREG5 => open,
		SREG6 => open,
		TP => TP_ARP_CACHE2
	);
end generate;

--//-- DHCP CLIENT (DYNAMIC IP) -----------------------------------------
DHCP_CLIENT_001: if(DHCP_CLIENT_EN = '0') generate
	-- no DHCP client is instantiated. Always static IP address
	IPv4_ADDR <= REQUESTED_IPv4_ADDR;
	IPv4_SUBNET_MASK_local <= IPv4_SUBNET_MASK;
	IPv4_GATEWAY_ADDR_local <= IPv4_GATEWAY_ADDR;
end generate;

DHCP_CLIENT_002: if(DHCP_CLIENT_EN = '1') generate
	-- keep this component in reset if the user selects static IP
	DHCPC_SYNC_RESET <= (not DYNAMIC_IP) or SYNC_RESET;
	
	-- remember the last assigned address
	DHCPC_LAST_IPv4_ADDR_GEN: process(CLK)
	begin
		if rising_edge(CLK) then
			if(DYNAMIC_IP = '0') then
				-- static IP address
				IPv4_ADDR <= REQUESTED_IPv4_ADDR;
				IPv4_SUBNET_MASK_local <= IPv4_SUBNET_MASK;
				IPv4_GATEWAY_ADDR_local <= IPv4_GATEWAY_ADDR;
			else
				-- dynamic IP address, based on DHCP server assignment
				IPv4_ADDR <= DHCPC_IPv4_ADDR;	
				IPv4_SUBNET_MASK_local <= DHCP_SUBNET_MASK;
				IPv4_GATEWAY_ADDR_local <= DHCP_ROUTER;
			end if;
		end if;
	end process;
				
	Inst_DHCP_CLIENT: DHCP_CLIENT 
	GENERIC MAP(
		SIMULATION => SIMULATION
	)
	PORT MAP(
		SYNC_RESET => DHCPC_SYNC_RESET,
		CLK => CLK,
		TICK_4US => TICK_4US,
		TICK_100MS => TICK_100MS,
		MAC_ADDR => MAC_ADDR,
		LAST_IPv4_ADDR => REQUESTED_IPv4_ADDR,	
		IPv4_ADDR => DHCPC_IPv4_ADDR,
		LEASE_TIME => open,
		SUBNET_MASK => DHCP_SUBNET_MASK,
		ROUTER => DHCP_ROUTER,
		DNS1 => open,
		DNS2 => open,
		IP_ID_IN => IP_ID,
		IP_RX_DATA => IP_RX_DATA,
		IP_RX_DATA_VALID => IP_RX_DATA_VALID,
		IP_RX_SOF => IP_RX_SOF,
		IP_RX_EOF => IP_RX_EOF,
		IP_BYTE_COUNT => IP_BYTE_COUNT,
		IP_HEADER_FLAG => IP_HEADER_FLAG,
		RX_IP_PROTOCOL => RX_IP_PROTOCOL,
		RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
		RX_SOURCE_IP_ADDR => RX_SOURCE_IP_ADDR(31 downto 0),
		RX_UDP_CKSUM => RX_UDP_CKSUM,
		RX_UDP_CKSUM_RDY => RX_UDP_CKSUM_RDY,
		-- MAC interface
		MAC_TX_DATA => DHCP_MAC_TX_DATA,
		MAC_TX_DATA_VALID => DHCP_MAC_TX_DATA_VALID,
		MAC_TX_EOF => DHCP_MAC_TX_EOF,
		MAC_TX_CTS => DHCP_MAC_TX_CTS,
		RTS => DHCP_RTS,		
		TP => TP_DHCP
	);
end generate;
DHCPC_IPv4_ADDR_out <= DHCPC_IPv4_ADDR;

--//-- IGMP (MULTICAST) -----------------------------------------
-- detects an IGMP membership query. Triggers a response
IGMP_QUERY_001x: if (IGMP_EN = '1') and (NUDPTX /= 0) generate
	IGMP_QUERY_001: IGMP_QUERY PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		MULTICAST_IP_ADDR => MULTICAST_IP_ADDR,
		IP_RX_DATA => IP_RX_DATA,
		IP_RX_DATA_VALID => IP_RX_DATA_VALID2,
		IP_RX_SOF => IP_RX_SOF,
		IP_RX_EOF => IP_RX_EOF,
		IP_BYTE_COUNT => IP_BYTE_COUNT,
		IP_HEADER_FLAG => IP_HEADER_FLAG,
		RX_IP_PROTOCOL => RX_IP_PROTOCOL,
		RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
		RX_DEST_IP_ADDR => RX_DEST_IP_ADDR(31 downto 0),
		TRIGGER_RESPONSE => IGMP_TRIGGER_RESPONSE,
		TP => open
	);

	-- send an IGMP membership report either in response to a membership query
	-- or a couple of times at power up/reset
	-- or once every 102.4 seconds
	IGMP_REPORT_TIMER_GEN: process(CLK)
	begin
		 if rising_edge(CLK) then
			  if (SYNC_RESET = '1') then
					TICK_CNTR <= (others => '0');
			  elsif(TICK_100MS = '1') and (TICK_CNTR(6) = '0') then
					-- counts from 0 to 64 and stay there
					TICK_CNTR <= TICK_CNTR + 1;
			  end if;
			  
			  -- modulo 1024 counter
			  if (SYNC_RESET = '1') then
					TICK_CNTR2 <= (others => '0');
			  elsif(TICK_100MS = '1') then
					TICK_CNTR2 <= TICK_CNTR2 + 1;
			  end if;
			  
			  
			  if(TICK_100MS = '1') and (TICK_CNTR(6) = '0') and (TICK_CNTR(4 downto 0) = 0) then
					-- generate two pulses at 3.4 and 6.4s after reset
					IGMP_TRIGGER_RESPONSE2 <= '1';
			  else
					IGMP_TRIGGER_RESPONSE2 <= '0';
			  end if;

			  if(TICK_100MS = '1') and (TICK_CNTR2 = 1023) then
					-- generate periodic pulses once every 102.4 seconds
					IGMP_TRIGGER_RESPONSE3 <= '1';
			  else
					IGMP_TRIGGER_RESPONSE3 <= '0';
			  end if;

		 end if;
	end process;

	-- 0.0.0.0 to signify that IP multicasting is not supported here.
	IGMP_REPORT_START <= (IGMP_TRIGGER_RESPONSE or IGMP_TRIGGER_RESPONSE2 or IGMP_TRIGGER_RESPONSE3) when (MULTICAST_IP_ADDR /= 0) else '0';

	IGMP_REPORT_001: IGMP_REPORT 
	PORT MAP(
		SYNC_RESET => SYNC_RESET,
		CLK => CLK,
		MULTICAST_IP_ADDR => MULTICAST_IP_ADDR,
		IGMP_START => IGMP_REPORT_START,  
		MAC_ADDR => MAC_ADDR,
		IPv4_ADDR => IPv4_ADDR,
		IP_ID => IP_ID,
		MAC_TX_DATA => IGMP_MAC_TX_DATA,
		MAC_TX_DATA_VALID => IGMP_MAC_TX_DATA_VALID,
		MAC_TX_EOF => IGMP_MAC_TX_EOF,
		MAC_TX_CTS => IGMP_MAC_TX_CTS,
		RTS => IGMP_RTS,
		TP => TP_IGMP
	);
end generate;

--//-- UDP RX to Serial (Monitoring and control) ---------
	Inst_UDP2SERIAL: UDP2SERIAL 
	GENERIC MAP(
		PORT_NO => x"0405",  --1029
		CLK_FREQUENCY => CLK_FREQUENCY
	)
	PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		IP_RX_DATA => IP_RX_DATA,
		IP_RX_DATA_VALID => IP_RX_DATA_VALID,
		IP_RX_SOF => IP_RX_SOF,
		IP_RX_EOF => IP_RX_EOF,
		IP_HEADER_FLAG => IP_HEADER_FLAG,
		RX_IP_PROTOCOL => RX_IP_PROTOCOL,
		RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
		SERIAL_OUT => open,
		TP => open
	);

--//-- UDP RX ------------------------------------
UDP_RX_X: if(NUDPRX /= 0) generate
    -- UDP receiver should also check multicast addresses
    UDP_RX_VALID_DEST_IP_GEN: process(CLK)
    begin
        if rising_edge(CLK) then
            if(RX_DEST_IP_ADDR(31 downto 0) = IPv4_ADDR) then
                UDP_RX_VALID_DEST_IP <= '1';
            elsif(MULTICAST_IP_ADDR(31 downto 24) /= 0) and (RX_DEST_IP_ADDR(31 downto 0) = MULTICAST_IP_ADDR) then
                UDP_RX_VALID_DEST_IP <= '1';
            else
                UDP_RX_VALID_DEST_IP <= '0';
            end if;
        end if;
    end process;
    IP_RX_DATA_VALID3 <= IP_RX_DATA_VALID2 and UDP_RX_VALID_DEST_IP;
    
	UDP_RX_001: UDP_RX 
	PORT MAP(
		SYNC_RESET => SYNC_RESET,
		CLK => CLK,
		IP_RX_DATA => IP_RX_DATA,
		IP_RX_DATA_VALID => IP_RX_DATA_VALID3,
		IP_RX_SOF => IP_RX_SOF,
		IP_RX_EOF => IP_RX_EOF,
		IP_BYTE_COUNT => IP_BYTE_COUNT,
		IP_HEADER_FLAG => IP_HEADER_FLAG,
		RX_IP_PROTOCOL => RX_IP_PROTOCOL,
		RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
		RX_UDP_CKSUM => RX_UDP_CKSUM,
		RX_UDP_CKSUM_RDY => RX_UDP_CKSUM_RDY,
		-- configuration
		PORT_NO => UDP_RX_DEST_PORT_NO_IN,
		CHECK_UDP_RX_DEST_PORT_NO => CHECK_UDP_RX_DEST_PORT_NO,
		-- Application interface
		APP_DATA => UDP_RX_DATA,
		APP_DATA_VALID => UDP_RX_DATA_VALID,
		APP_SOF => UDP_RX_SOF,
		APP_EOF => UDP_RX_EOF,
		APP_SRC_UDP_PORT => open,
		APP_DEST_UDP_PORT => UDP_RX_DEST_PORT_NO_OUT,
		TP => TP_UDP_RX
	);
end generate;	



--//-- UDP TX ------------------------------------
UDP_TX_NZ: if(NUDPTX /= 0) generate
	UDP_TX_001: UDP_TX 
	GENERIC MAP(
		NBUFS => 1,
		IPv6_ENABLED => '0'
	)
	PORT MAP(
		CLK => CLK,
		SYNC_RESET => SYNC_RESET,
		TICK_4US => TICK_4US,
		-- Application interface
		APP_DATA => UDP_TX_DATA,
		APP_DATA_VALID => UDP_TX_DATA_VALID,
		APP_SOF => UDP_TX_SOF,
		APP_EOF => UDP_TX_EOF,
		APP_CTS => UDP_TX_CTS,
		ACK => UDP_TX_ACK_local,
		NAK => UDP_TX_NAK_local,
		DEST_IP_ADDR => UDP_TX_DEST_IP_ADDR,
		DEST_PORT_NO => UDP_TX_DEST_PORT_NO,
		SOURCE_PORT_NO => UDP_TX_SOURCE_PORT_NO,	
		IPv4_6n => '1',
		-- Configuration
		MAC_ADDR => MAC_ADDR,
		IPv4_ADDR => IPv4_ADDR,
		IPv6_ADDR => IPv6_ADDR,
		IP_ID => IP_ID,
		-- Routing
		RT_IP_ADDR => UDP001_RT_IP_ADDR,
		RT_REQ_RTS => UDP001_RT_REQ_RTS,
		RT_REQ_CTS => UDP001_RT_REQ_CTS,
		RT_MAC_REPLY => RT_MAC_REPLY,
		RT_MAC_RDY => UDP001_RT_MAC_RDY,
		RT_NAK => UDP001_RT_NAK,
		-- MAC interface
		MAC_TX_DATA => UDP001_MAC_TX_DATA,
		MAC_TX_DATA_VALID => UDP001_MAC_TX_DATA_VALID,
		MAC_TX_EOF => UDP001_MAC_TX_EOF,
		MAC_TX_CTS => UDP001_MAC_TX_CTS,
		RTS => UDP001_RTS,
		TP => TP_UDP_TX
	);
end generate;
UDP_TX_ACK <= UDP_TX_ACK_local;
UDP_TX_NAK <= UDP_TX_NAK_local;

--//-- TCP CLIENTS 001 ------------------------------------
-- declare the port number for each TCP stream (NTCPSTREAMS streams, declared in com5402pkg)
TCP_CLIENTS_X: if (NTCPSTREAMS /= 0) generate
		-- There is no point in processing TCP messages until a non-zero IP address is assigned to this TCP client.
		TCP001_SYNC_RESET <= '1' when (IPv4_ADDR = 0) or (SYNC_RESET = '1') else '0';


		TCP_CLIENTS_001: TCP_CLIENTS 
		GENERIC MAP(
			NTCPSTREAMS => NTCPSTREAMS,
			MSS => 1460, -- bytes	
			TCP_KEEPALIVE_PERIOD => TCP_KEEPALIVE_PERIOD,
			IPv6_ENABLED => '0',
			SIMULATION => SIMULATION
		)
		PORT MAP(
			CLK => CLK,
			SYNC_RESET => TCP001_SYNC_RESET,
			TICK_4US => TICK_4US,
			TICK_100MS => TICK_100MS,
			MAC_ADDR => MAC_ADDR,
			TCP_LOCAL_PORTS => TCP_LOCAL_PORTS,
			DEST_IPv4_ADDR => DEST_IPv4_ADDR,
			DEST_PORT => DEST_PORT,
			STATE_REQUESTED => STATE_REQUESTED,
			STATE_STATUS => STATE_STATUS,
			TCP_KEEPALIVE_EN => TCP_KEEPALIVE_EN,
			RT_IP_ADDR => TCP001_RT_IP_ADDR,
			RT_REQ_RTS => TCP001_RT_REQ_RTS,
			RT_REQ_CTS => TCP001_RT_REQ_CTS,
			RT_MAC_REPLY => RT_MAC_REPLY,
			RT_MAC_RDY => TCP001_RT_MAC_RDY,
			RT_NAK => TCP001_RT_NAK,
			IP_RX_DATA => IP_RX_DATA,
			IP_RX_DATA_VALID => IP_RX_DATA_VALID,
			IP_RX_SOF => IP_RX_SOF,
			IP_RX_EOF => IP_RX_EOF,
			IP_BYTE_COUNT => IP_BYTE_COUNT,
			IP_HEADER_FLAG => IP_HEADER_FLAG,
			RX_IPv4_6n => RX_IPv4_6n,
			RX_IP_PROTOCOL => RX_IP_PROTOCOL,
			RX_IP_PROTOCOL_RDY => RX_IP_PROTOCOL_RDY,
			RX_SOURCE_MAC_ADDR => RX_SOURCE_MAC_ADDR,
			RX_SOURCE_IP_ADDR => RX_SOURCE_IP_ADDR,
			RX_SOURCE_TCP_PORT_NO => RX_SOURCE_TCP_PORT_NO,
	--		RX_TCP_BYTE_COUNT => RX_TCP_BYTE_COUNT,
			RX_TCP_HEADER_FLAG => RX_TCP_HEADER_FLAG,
			RX_TCP_FLAGS => RX_TCP_FLAGS,
			RX_TCP_CKSUM => RX_TCP_CKSUM,
			RX_TCP_SEQ_NO => RX_TCP_SEQ_NO,
			RX_TCP_ACK_NO => RX_TCP_ACK_NO,
			RX_TCP_WINDOW_SIZE => RX_TCP_WINDOW_SIZE,
			RX_DEST_TCP_PORT_NO => RX_DEST_TCP_PORT_NO,
			RX_DATA => TCP001_RX_DATA,
			RX_DATA_VALID => TCP001_RX_DATA_VALID,
			RX_SOF => TCP001_RX_SOF,
			RX_STREAM_SEL => TCP001_RX_STREAM_SEL,
			RX_EOF => TCP001_RX_EOF,
			RX_FREE_SPACE => TCP001_RX_FREE_SPACE,	
			TX_PACKET_SEQUENCE_START_OUT => TCP001_TX_PACKET_SEQUENCE_START,
			TX_DEST_MAC_ADDR_OUT => TCP001_TX_DEST_MAC_ADDR,
			TX_DEST_IP_ADDR_OUT => TCP001_TX_DEST_IP_ADDR,
			TX_DEST_PORT_NO_OUT => TCP001_TX_DEST_PORT_NO,
			TX_SOURCE_PORT_NO_OUT => TCP001_TX_SOURCE_PORT_NO,
			TX_IPv4_6n_OUT => TCP001_TX_IPv4_6n,
			TX_SEQ_NO_OUT => TCP001_TX_SEQ_NO,
			TX_ACK_NO_OUT => TCP001_TX_ACK_NO,
			TX_ACK_WINDOW_LENGTH_OUT => TCP001_TX_ACK_WINDOW_LENGTH,
			TX_FLAGS_OUT => TCP001_TX_FLAGS,
			TX_PACKET_TYPE_OUT => TCP001_TX_PACKET_TYPE,
			MAC_TX_EOF => TCP001_MAC_TX_EOF,
			RTS => TCP001_RTS,
			EFF_RX_WINDOW_SIZE_PARTIAL => TCP001_EFF_RX_WINDOW_SIZE_PARTIAL,
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM => TCP001_EFF_RX_WINDOW_SIZE_PARTIAL_STREAM,
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID => TCP001_EFF_RX_WINDOW_SIZE_PARTIAL_VALID,
			TX_SEQ_NO => TCP001_TX_SEQ_NOxNTCPSTREAMS,
			TX_SEQ_NO_JUMP => TCP001_TX_SEQ_NO_JUMP,
			RX_TCP_ACK_NO_D => TCP001_RX_ACK_NOxNTCPSTREAMS,
			TX_STREAM_SEL => TCP001_TX_STREAM_SEL,
			TX_PAYLOAD_RTS => TCP001_TX_PAYLOAD_RTS,
			TX_PAYLOAD_SIZE => TCP001_TX_PAYLOAD_SIZE,
			CONNECTED_FLAG => TCP001_CONNECTED_FLAG,
			TP => TP_TCP_CLIENTS
		);

	-- assemble tx packet (MAC/IP/TCP)
		Inst_TCP_TX: TCP_TX 
		GENERIC MAP(
			MSS => x"05B4",	-- 1460 bytes	
			IPv6_ENABLED => '0'
		)
		PORT MAP(
			CLK => CLK,
			SYNC_RESET => SYNC_RESET,
			MAC_ADDR => MAC_ADDR,
			IPv4_ADDR => IPv4_ADDR,
			IPv6_ADDR => IPv6_ADDR,
			TX_PACKET_SEQUENCE_START => TCP001_TX_PACKET_SEQUENCE_START,
			TX_DEST_MAC_ADDR_IN => TCP001_TX_DEST_MAC_ADDR,
			TX_DEST_IP_ADDR_IN => TCP001_TX_DEST_IP_ADDR,
			TX_DEST_PORT_NO_IN => TCP001_TX_DEST_PORT_NO,
			TX_SOURCE_PORT_NO_IN => TCP001_TX_SOURCE_PORT_NO,
			TX_IPv4_6n_IN => TCP001_TX_IPv4_6n,
			TX_SEQ_NO_IN => TCP001_TX_SEQ_NO,
			TX_ACK_NO_IN => TCP001_TX_ACK_NO,
			TX_ACK_WINDOW_LENGTH_IN => TCP001_TX_ACK_WINDOW_LENGTH,
			IP_ID_IN => IP_ID,
			TX_FLAGS_IN => TCP001_TX_FLAGS,
			TX_PACKET_TYPE_IN => TCP001_TX_PACKET_TYPE,
			TX_PAYLOAD_DATA => TCP001_TX_PAYLOAD_DATA,
			TX_PAYLOAD_DATA_VALID => TCP001_TX_PAYLOAD_DATA_VALID,
			TX_PAYLOAD_DATA_EOF => TCP001_TX_PAYLOAD_DATA_EOF,	
			TX_PAYLOAD_RTS => TCP001_TX_PAYLOAD_RTS,
			TX_PAYLOAD_CTS => TCP001_TX_PAYLOAD_CTS,
			TX_PAYLOAD_SIZE => TCP001_TX_PAYLOAD_SIZE,
			TX_PAYLOAD_CHECKSUM => TCP001_TX_PAYLOAD_CHECKSUM,
			MAC_TX_DATA => TCP001_MAC_TX_DATA,	
			MAC_TX_DATA_VALID => TCP001_MAC_TX_DATA_VALID,
			MAC_TX_EOF => TCP001_MAC_TX_EOF,
			MAC_TX_CTS => TCP001_MAC_TX_CTS,
			TP => open
		);


		Inst_TCP_RXBUFNDEMUX2: TCP_RXBUFNDEMUX2 
		GENERIC MAP(
			NTCPSTREAMS => NTCPSTREAMS,
--			ADDR_WIDTH => 12		-- must be large enough to include 2 MSS per enabled TCP stream.
			ADDR_WIDTH => 13		-- must be large enough to include 2 MSS per enabled TCP stream.
		)
		PORT MAP(
			SYNC_RESET => SYNC_RESET,
			CLK => CLK,
			RX_DATA => TCP001_RX_DATA,
			RX_DATA_VALID => TCP001_RX_DATA_VALID,
			RX_SOF => TCP001_RX_SOF,
			RX_TCP_STREAM_SEL => TCP001_RX_STREAM_SEL,
			RX_EOF => TCP001_RX_EOF,
			RX_FREE_SPACE => TCP001_RX_FREE_SPACE,	
			RX_APP_DATA => TCP_RX_DATA,
			RX_APP_DATA_VALID => TCP_RX_DATA_VALID,
			RX_APP_CTS => TCP_RX_CTS,
			RX_APP_RTS => TCP_RX_RTS,
			TP => open
		);

		Inst_TCP_TXBUF: TCP_TXBUF 
		GENERIC MAP(
			NTCPSTREAMS => NTCPSTREAMS,
			MSS => 1460,	-- 1460 bytes, consistent with Ethernet MTU of 1500 bytes.
--			ADDR_WIDTH => 11,	-- trade-off device utilization vs throughput
--			ADDR_WIDTH => 13,	
			ADDR_WIDTH => 15,	
			OB_ADDR_WIDTH => 12,
			TX_IDLE_TIMEOUT => TX_IDLE_TIMEOUT,
			SIMULATION => SIMULATION	
		)
		PORT MAP(
			CLK => CLK,
			SYNC_RESET => SYNC_RESET,
			TICK_4US => TICK_4US,
			-- application interface -------
			APP_DATA => TCP_TX_DATA,
			APP_DATA_VALID => TCP_TX_DATA_VALID,
			APP_CTS => TCP001_TCP_TX_CTS,
			APP_DATA_FLUSH =>	(others => '0'),	-- FUTURE FEATURE (SEE COM5502)
			-- TCP_SERVER interface -------
			EFF_RX_WINDOW_SIZE_PARTIAL_IN => TCP001_EFF_RX_WINDOW_SIZE_PARTIAL,
			EFF_RX_WINDOW_SIZE_PARTIAL_STREAM => TCP001_EFF_RX_WINDOW_SIZE_PARTIAL_STREAM,
			EFF_RX_WINDOW_SIZE_PARTIAL_VALID => TCP001_EFF_RX_WINDOW_SIZE_PARTIAL_VALID,
			TX_SEQ_NO_IN => TCP001_TX_SEQ_NOxNTCPSTREAMS,
			TX_SEQ_NO_JUMP => TCP001_TX_SEQ_NO_JUMP,
			RX_TCP_ACK_NO_D => TCP001_RX_ACK_NOxNTCPSTREAMS,
			CONNECTED_FLAG => TCP001_CONNECTED_FLAG,
			TX_STREAM_SEL => TCP001_TX_STREAM_SEL,
			-- TCP_TX interface -------
			TX_PAYLOAD_DATA => TCP001_TX_PAYLOAD_DATA,
			TX_PAYLOAD_DATA_VALID => TCP001_TX_PAYLOAD_DATA_VALID,
			TX_PAYLOAD_DATA_EOF => TCP001_TX_PAYLOAD_DATA_EOF,	
			TX_PAYLOAD_RTS => TCP001_TX_PAYLOAD_RTS,
			TX_PAYLOAD_CTS => TCP001_TX_PAYLOAD_CTS,
			TX_PAYLOAD_SIZE => TCP001_TX_PAYLOAD_SIZE,
			TX_PAYLOAD_CHECKSUM => TCP001_TX_PAYLOAD_CHECKSUM,
			TP => TP_TCP_TXBUF
		);
		TCP_TX_CTS <= TCP001_TCP_TX_CTS;
end generate;
	
 --//-- IP ID generation
-- Increment IP ID every time an IP datagram is sent
IP_ID_GEN_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			IP_ID <= (others => '0');	
		elsif(TCP001_MAC_TX_EOF = '1') or (UDP001_MAC_TX_EOF = '1') or (DHCP_MAC_TX_EOF = '1') or (IGMP_MAC_TX_EOF = '1') then
--		elsif(TCP001_MAC_TX_EOF = '1') or (TCP002_MAC_TX_EOF = '1') or (UDP001_MAC_TX_EOF = '1') then
			-- increment every time an IP packet is send. 
			-- Adjust as needed when other IP/UDP/TCP components are instantiated
			IP_ID <= IP_ID + 1;
		end if;
	end if;
end process;

	
--//-- TRANSMISSION ARBITER --------------
-- determines the source for the next packet to be transmitted.
-- State machine to prevent overlapping between two packets ready... 
-- For example, one has to wait until a UDP packet has completed transmission 
-- before starting to send a TCP packet.
TX_MUX_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TX_MUX_STATE <= 0;	-- idle
		elsif(TX_MUX_STATE = 0) and (MAC_TX_CTS = '1') then
			-- from idle to ...
			if(ARP_RTS = '1') then
				TX_MUX_STATE <= 1;	-- enable ARP response
			elsif(PING_RTS = '1') then
				TX_MUX_STATE <= 2;	-- enable PING response
			elsif(TCP001_RTS = '1') and (NTCPSTREAMS /= 0) then
				TX_MUX_STATE <= 3;	-- enable TCP001 transmission 
			elsif(WHOIS_RTS = '1') and ((NUDPTX /= 0) or (NTCPSTREAMS /= 0)) then
				TX_MUX_STATE <= 4;	-- enable WHOIS transmission
			elsif(UDP001_RTS = '1') and (NUDPTX /= 0) then
				TX_MUX_STATE <= 5;	-- enable UDP001 transmission (duplicate as needed)
			elsif(IGMP_RTS = '1') and (IGMP_EN = '1') and (NUDPTX /= 0) then
				TX_MUX_STATE <= 6;    -- enable IGMP message transmission
			elsif(DHCP_RTS = '1') and (DHCP_CLIENT_EN = '1') then
				TX_MUX_STATE <= 7;	-- enable DHCP transmission
--			elsif(TCP002_RTS = '1') and (NTCPSTREAMS /= 0) then
--				TX_MUX_STATE <= 8;	-- enable TCP002 transmission 
			end if;

		-- Done transmitting. go from ... to idle
	 	elsif(TX_MUX_STATE = 1) and (ARP_MAC_TX_EOF = '1') then
			TX_MUX_STATE <= 0;	-- idle
	 	elsif(TX_MUX_STATE = 2) and (PING_MAC_TX_EOF = '1') then
			TX_MUX_STATE <= 0;	-- idle
	 	elsif(TX_MUX_STATE = 3) and (TCP001_MAC_TX_EOF = '1') and (NTCPSTREAMS /= 0)  then 
			TX_MUX_STATE <= 0;	-- idle
	 	elsif(TX_MUX_STATE = 4) and (WHOIS_MAC_TX_EOF = '1') and ((NUDPTX /= 0) or (NTCPSTREAMS /= 0)) then
			TX_MUX_STATE <= 0;	-- idle
	 	elsif(TX_MUX_STATE = 5) and (UDP001_MAC_TX_EOF = '1') and (NUDPTX /= 0) then -- (duplicate as needed)
			TX_MUX_STATE <= 0;	-- idle
	 	elsif(TX_MUX_STATE = 6) and (IGMP_MAC_TX_EOF = '1') then 
            TX_MUX_STATE <= 0;    -- idle
	 	elsif(TX_MUX_STATE = 7) and (DHCP_MAC_TX_EOF = '1') and (DHCP_CLIENT_EN = '1') then
			TX_MUX_STATE <= 0;	-- idle
--	 	elsif(TX_MUX_STATE = 8) and (TCP002_MAC_TX_EOF = '1') and (NTCPSTREAMS /= 0)  then 
--			TX_MUX_STATE <= 0;	-- idle
	 	end if;
	end if;
end process;
MAC_TX_RTS <= ARP_RTS or PING_RTS or TCP001_RTS or WHOIS_RTS or UDP001_RTS or DHCP_RTS or IGMP_RTS;
	
TX_MUX_002: process(TX_MUX_STATE, ARP_MAC_TX_EOF, ARP_MAC_TX_DATA_VALID, ARP_MAC_TX_DATA,
							PING_MAC_TX_EOF, PING_MAC_TX_DATA_VALID, PING_MAC_TX_DATA,
							TCP001_MAC_TX_EOF, TCP001_MAC_TX_DATA_VALID, TCP001_MAC_TX_DATA,
							WHOIS_MAC_TX_DATA, WHOIS_MAC_TX_DATA_VALID, WHOIS_MAC_TX_EOF,
							UDP001_MAC_TX_DATA, UDP001_MAC_TX_DATA_VALID, UDP001_MAC_TX_EOF,
							DHCP_MAC_TX_DATA, DHCP_MAC_TX_DATA_VALID, DHCP_MAC_TX_EOF,
							IGMP_MAC_TX_DATA, IGMP_MAC_TX_DATA_VALID, IGMP_MAC_TX_EOF)
begin
	case(TX_MUX_STATE) is
		when (1) =>
			MAC_TX_DATA <= ARP_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= ARP_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= ARP_MAC_TX_EOF;
		when (2) =>
			MAC_TX_DATA <= PING_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= PING_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= PING_MAC_TX_EOF;
		when (3) =>
			MAC_TX_DATA <= TCP001_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= TCP001_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= TCP001_MAC_TX_EOF;
		when (4) =>
			MAC_TX_DATA <= WHOIS_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= WHOIS_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= WHOIS_MAC_TX_EOF;
		when (5) =>
			MAC_TX_DATA <= UDP001_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= UDP001_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= UDP001_MAC_TX_EOF;
		when (6) =>
			MAC_TX_DATA <= IGMP_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= IGMP_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= IGMP_MAC_TX_EOF;			
		when (7) =>
			MAC_TX_DATA <= DHCP_MAC_TX_DATA;
			MAC_TX_DATA_VALID_local <= DHCP_MAC_TX_DATA_VALID;
			MAC_TX_EOF_local <= DHCP_MAC_TX_EOF;
--		when (8) =>
--			MAC_TX_DATA <= TCP002_MAC_TX_DATA;
--			MAC_TX_DATA_VALID_local <= TCP002_MAC_TX_DATA_VALID;
--			MAC_TX_EOF_local <= TCP002_MAC_TX_EOF;
		when others => 
			MAC_TX_DATA <= (others => '0');
			MAC_TX_DATA_VALID_local <= '0';
			MAC_TX_EOF_local <= '0';
	end case;
end process;

MAC_TX_DATA_VALID <= MAC_TX_DATA_VALID_local;
MAC_TX_EOF <= MAC_TX_EOF_local;

-- reconstruct a SOF pulse for local loopback
SOF_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			MAC_TX_EOF_FLAG <= '1';
		elsif(MAC_TX_EOF_local = '1') then
			MAC_TX_EOF_FLAG <= '1';
		elsif(MAC_TX_DATA_VALID_local = '1') then
			MAC_TX_EOF_FLAG <= '0';
		end if;
	end if;
end process;
MAC_TX_SOF <= '1' when (MAC_TX_DATA_VALID_local = '1') and (MAC_TX_EOF_FLAG = '1') else '0';


-- Route "Clear To Send" signal from the MAC to the proper protocol component
ARP_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 1) else '0';
PING_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 2) else '0';
TCP001_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 3) else '0';
WHOIS_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 4) else '0';
UDP001_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 5) else '0';
IGMP_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 6) else '0';
DHCP_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 7) else '0';
--TCP002_MAC_TX_CTS <= '1' when (TX_MUX_STATE = 8) else '0';


--//-- ROUTING TABLE ARBITER --------------
-- Since several components could send simultaneous routing (RT) requests, one must 
-- determine who can access the routing table next
RT_MUX_001: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			RT_MUX_STATE <= 0;	-- idle
		elsif(RT_MUX_STATE = 0) then
			-- from idle to ...
			if(TCP001_RT_REQ_RTS = '1') then
				RT_MUX_STATE <= 1;	-- gives TCP001 access to the routing table
			elsif(UDP001_RT_REQ_RTS = '1') then
				RT_MUX_STATE <= 2;	-- gives UDP001 access to the routing table
--			elsif(UDP002_RT_REQ_RTS = '1') then
--				RT_MUX_STATE <= 3;	-- gives UDP002 access to the routing table
--			elsif(UDP003_RT_REQ_RTS = '1') then
--				RT_MUX_STATE <= 4;	-- gives UDP003 access to the routing table
			end if;

		-- Routing table transaction complete. go back to idle
	 	elsif (RT_MAC_RDY = '1') or (RT_NAK = '1') then
			RT_MUX_STATE <= 0;	-- idle
	 	end if;
	end if;
end process;
	
RT_MUX_002: process(RT_MUX_STATE, TCP001_RT_IP_ADDR, TCP001_RT_REQ_RTS, UDP001_RT_IP_ADDR, UDP001_RT_REQ_RTS)
begin
	case(RT_MUX_STATE) is
		when (1) =>
			RT_IP_ADDR <= TCP001_RT_IP_ADDR;
			RT_REQ_RTS <= TCP001_RT_REQ_RTS;
		when (2) =>
			RT_IP_ADDR <= UDP001_RT_IP_ADDR;
			RT_REQ_RTS <= UDP001_RT_REQ_RTS;
--		when (3) =>
--			RT_IP_ADDR <= UDP002_RT_IP_ADDR;
--		when (4) =>
--			RT_IP_ADDR <= UDP003_RT_IP_ADDR;
-- etc...
		when others =>
			RT_IP_ADDR <= (others => '0');
			RT_REQ_RTS <= '0';
	end case;
end process;
		
TCP001_RT_REQ_CTS <= RT_CTS when (RT_MUX_STATE = 1) else '0';
UDP001_RT_REQ_CTS <= RT_CTS when (RT_MUX_STATE = 2) else '0';
--UDP002_RT_REQ_CTS <= RT_CTS when (RT_MUX_STATE = 3) else '0';
--UDP003_RT_REQ_CTS <= RT_CTS when (RT_MUX_STATE = 4) else '0';
-- etc...

TCP001_RT_MAC_RDY <= RT_MAC_RDY when (RT_MUX_STATE = 1) else '0';
UDP001_RT_MAC_RDY <= RT_MAC_RDY when (RT_MUX_STATE = 2) else '0';
--UDP002_RT_MAC_RDY <= RT_MAC_RDY when (RT_MUX_STATE = 3) else '0';
--UDP003_RT_MAC_RDY <= RT_MAC_RDY when (RT_MUX_STATE = 4) else '0';
-- etc...

TCP001_RT_NAK <= RT_NAK when (RT_MUX_STATE = 1) else '0';
UDP001_RT_NAK <= RT_NAK when (RT_MUX_STATE = 2) else '0';
--UDP002_RT_NAK <= RT_NAK when (RT_MUX_STATE = 3) else '0';
--UDP003_RT_NAK <= RT_NAK when (RT_MUX_STATE = 4) else '0';
-- etc...

--//-- TEST POINTS
TP <= TP_ARP;
--TP(1) <= '1' when (TX_MUX_STATE=1) else '0';	-- arp
--TP(2) <= '1' when (TX_MUX_STATE=2) else '0';	-- ping
--TP(3) <= '1' when (TX_MUX_STATE=4) else '0';	-- whois
--TP(4) <= '1' when (TX_MUX_STATE=5) else '0';	-- udp tx
--TP(5) <= UDP_TX_DATA_VALID;
--TP(6) <= UDP_TX_ACK_local;
--TP(7) <= UDP_TX_NAK_local;
--TP(8)	<= WHOIS_START;
--TP(9) <= RT_REQ_RTS;
--TP(10) <= RT_MAC_RDY;

--TP(1) <= IGMP_TRIGGER_RESPONSE;
--TP(2) <= IGMP_TRIGGER_RESPONSE2;
--TP(3) <= IGMP_REPORT_START;
--TP(4) <= TICK_100MS;
--TP(5) <= TICK_CNTR(0);
--TP(6) <= TICK_CNTR(5);
--TP(7) <= IGMP_MAC_TX_CTS;
--TP(8) <= IGMP_MAC_TX_DATA_VALID;
--TP(9) <= IGMP_MAC_TX_EOF;

end Behavioral;
