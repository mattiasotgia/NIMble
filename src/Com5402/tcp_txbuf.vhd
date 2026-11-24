-------------------------------------------------------------
-- MSS copyright 2023
-- Filename:  TCP_TXBUF.VHD
-- Author: Alain Zarembowitch / MSS
-- Version: 3
-- Date last modified: 7/10/23
-- Inheritance: 	TCP_TXBUF_10G 8/18/18
--
-- description:  Buffer management for the transmit TCP payload data. 1G version.  
-- Payload data and partial checksum computation has to be ready immediately when requested by the TCP 
-- protocol engine (TCP_SERVER.vhd).
-- This component segments the data stream into packets, raises the Ready-To-Send flag (RTS) and waits
-- for trigger from the TCP protocol engine.
-- The input stream is segmented into data packets. The packet transmission
-- is triggered when one of two events occur:
-- (a) full packet: the number of bytes waiting for transmission is greater than or equal to MSS = MTU-40 = 1460 for ethernet
-- or, if less, the effective rx window as defined in the TCP protocol. 
-- (b) no-new-input timeout: there are a few bytes waiting for transmission but no new input 
-- bytes were received in the last 200us (or adjust constant TX_IDLE_TIMEOUT within).
-- (c) the user application requested an immediate flush APP_DATA_FLUSH
--
-- The overall buffer size (which affects overall throughput) is user selected in the generic section (see ADDR_WIDTH).
--
-- A frame is ready for transmission when 
-- (a) the effective client rx window size is non-zero
-- (b) the tx buffer contains either the effective client rx window size or MSS bytes or no new data received in the last 200us
--
-- Device utilization (NTCPSTREAMS=1, MSS = 1460, ADDR_WIDTH=11, OB_ADDR_WIDTH=12)
-- FF: 294
-- LUT: 268
-- DSP48: 0
-- 36Kb BRAM: 1.5
-- BUFG: 1
-- Minimum period: ns (Maximum Frequency: MHz) Artix7-100T -1 speed grade

-- rev 2 3/5/23 AZ
-- updated algorithm as per tcp_txbuf_10G.vhd 3/12/21
--
-- rev3 7/10/23 AZ
-- Corrected potential vulnerability on EVENTS0C when ADDR_WIDTH < 16. SEE EMAIL 6/4/23!
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
use work.com5402pkg.all;	-- defines global types, number of TCP streams, etc

entity TCP_TXBUF is
	generic (
		NTCPSTREAMS: integer := 1;  
			-- number of concurrent TCP streams handled by this component
		MSS: integer := 1460;
			-- The Maximum Segment Size (MSS) is the largest segment of TCP data that can be transmitted.
			-- Fixed as the Ethernet MTU (Maximum Transmission Unit) of 1500-9000 bytes - 40(IPv4) or -60(IPv6) overhead bytes 
			-- IMPORTANT: MAKE SURE MSS is < buffer size 8*2^ADDR_WIDTH
		ADDR_WIDTH: integer range 8 to 15:= 11;
			-- size of the dual-port RAM buffers instantiated within for each stream = 8b * 2^ADDR_WIDTH
			-- Trade-off buffer depth and overall TCP throughput.
			-- IMPORTANT: current max is 15 (262 Kbits buffer per stream)
		OB_ADDR_WIDTH: integer range 8 to 15:= 12;
			-- output buffer size (common for all streams)
			-- must be large enough for two MSS-sized frames
			-- for example, 12 when MSS = 1460
		TX_IDLE_TIMEOUT: integer range 0 to 50:= 50;	
			-- inactive input timeout, expressed in 4us units. -- 50*4us = 200us 
			-- Controls the transmit stream segmentation: data in the elastic buffer will be transmitted if
			-- no input is received within TX_IDLE_TIMEOUT, without waiting for the transmit frame to be filled with MSS data bytes.
		SIMULATION: std_logic := '0'
			-- mostly to shorten long timers during simulation
	);
    Port ( 
		--// CLK, RESET
		SYNC_RESET: in std_logic;
		CLK: in std_logic;		-- synchronous clock
			-- Must be a global clocks. No BUFG instantiation within this component.
		TICK_4US: in std_logic;
			-- 1 CLK-wide pulse every 4us

		--// APPLICATION INTERFACE -> TX BUFFER
		-- NTCPSTREAMS can operate independently and concurrently. No scheduling arbitration needed here.
		APP_DATA: in SLV8xNTCPSTREAMStype;
		APP_DATA_VALID: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		APP_CTS: out std_logic_vector((NTCPSTREAMS-1) downto 0);	
			-- Clear To Send = transmit flow control. 
			-- App is responsible for checking the CTS signal before sending APP_DATA
	   APP_DATA_FLUSH: in std_logic_vector((NTCPSTREAMS-1) downto 0);	
	        -- '1' to force the immediate transmission of any byte still in the elastic buffer.
	        -- This 1 CLK pulse can happen any time (not tied to APP_DATA_VALID)

		--// TX BUFFER <-> TX TCP protocol layer
		-- Part I: control path to/from TCP_SERVER engine
		-- (a) TCP_SERVER sends rx window information upon receiving an ACK from the TCP client
		-- Partial computation (rx window size + RX_TCP_ACK_NO)
		EFF_RX_WINDOW_SIZE_PARTIAL_IN: in std_logic_vector(16 downto 0);
			-- Explanation: EFF_RX_WINDOW_SIZE_PARTIAL_IN represents the maximum TX_SEQ_NO acceptable for the 
			-- TCP server (beyond which the rx buffers would be overflowing)
		EFF_RX_WINDOW_SIZE_PARTIAL_STREAM: in std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');	
		EFF_RX_WINDOW_SIZE_PARTIAL_VALID: in std_logic; -- 1 CLK-wide pulse to indicate that the above information is valid
		-- (b)  TCP_SERVER sends location of next frame start. Warning: could rewind to an earlier location.
		TX_SEQ_NO_IN: in SLV17xNTCPSTREAMStype;
		TX_SEQ_NO_JUMP: in std_logic_vector(NTCPSTREAMS-1 downto 0);
		      -- TX_SEQ_NO progresses regularly as new bytes are being transmitted, except when TX_SEQ_NO_JUMP(I) = '1'
		-- (c) for tx flow-control purposes, last acknowledged tx byte location
		-- Units: bytes
		RX_TCP_ACK_NO_D: in SLV17xNTCPSTREAMStype;
		-- Units: bytes

		-- (d) TCP_SERVER reports about TCP connection state. 
		-- '1' when TCP-IP connection is in the 'connected' state, 0 otherwise
		-- Do not store tx data until a connection is established
		CONNECTED_FLAG: in std_logic_vector((NTCPSTREAMS-1) downto 0);
		-- (e) upon reaching TCP_TX_STATE = 2, tell the TCP protocol engine (TCP_SERVER) 
		-- which stream is ready to send data next, i.e. meets the following criteria:
		-- (1) MSS bytes, or a lower size that meets the client effective rx window size, ready to send, OR
		-- (2) some data to be sent but no additional data received in the last 200us
		TX_STREAM_SEL: out std_logic_vector((NTCPSTREAMS-1) downto 0)  := (others => '0');	
			-- valid only when TX_PAYLOAD_RTS = '1', ignore otherwise
		TX_PAYLOAD_RTS: out std_logic;
			-- '1' when at least one stream has payload data available for transmission.
		TX_PAYLOAD_CHECKSUM: out std_logic_vector(16 downto 0) := (others => '0');
			-- partial TCP checksum computation. payload only, no header. bits 16 is the carry, add later.
			-- valid only when TX_PAYLOAD_RTS = '1', ignore otherwise
		TX_PAYLOAD_SIZE: out std_logic_vector(15 downto 0)  := (others => '0');
			-- payload size in bytes for the next tx frame
			-- valid only when TX_PAYLOAD_RTS = '1', ignore otherwise
			-- range is 0 - MSS 

		-- Part II: data path to TCP_TX for frame formatting
		TX_PAYLOAD_CTS: in std_logic;
			-- clear to send payload data: go ahead signal for forwarding data from the TX_STREAM_SEL stream
			-- to the TCP_TX component responsible for formatting the next transmit packet.
			-- 2 CLK latency until 1st data byte is available at TX_PAYLOAD_DATA
			-- The last CTS pulse does not trigger a TX_PAYLOAD_DATA_VALID (OBUF=0), thus marking the end of frame.
		TX_PAYLOAD_DATA: out std_logic_vector(7 downto 0);
			-- TCP payload data field when TX_PAYLOAD_DATA_VALID = '1'
		TX_PAYLOAD_DATA_VALID: out std_logic;
			-- delineates the TCP payload data field
		TX_PAYLOAD_DATA_EOF: out std_logic;
			-- End Of Frame. 1 CLK-wide pulse aligned with TX_PAYLOAD_DATA_VALID
		TP: out std_logic_vector(10 downto 1)
			-- test points
			);
end entity;

architecture Behavioral of TCP_TXBUF is
--------------------------------------------------------
--      COMPONENTS
--------------------------------------------------------
	COMPONENT BRAM_DP2C
	GENERIC(
		DATA_WIDTH: integer;
		ADDR_WIDTH: integer
	);
	PORT(
		CLK   : in  std_logic;
		CSA: in std_logic;	
		WEA    : in  std_logic;	
		ADDRA  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
		DIA   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
		CSB: in std_logic;	-- chip select, active high
		ADDRB  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
		DOB  : out std_logic_vector(DATA_WIDTH-1 downto 0)
		);
	END COMPONENT;

--------------------------------------------------------
--     SIGNALS
--------------------------------------------------------

--//-- INPUT IDLE DETECTION ---------------------------
type CNTRtype is array (integer range 0 to (NTCPSTREAMS-1)) of integer range 0 to 50;
signal TX_IDLE_TIMER: CNTRtype := (others => TX_IDLE_TIMEOUT);
signal TX_IDLE: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');

--//-- ELASTIC BUFFER ---------------------------
signal APP_DATA_VALID_D: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal APP_DATA_FLUSH_PENDING: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal APP_DATA_FLUSH_PENDING_D: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal DIA: SLV8xNTCPSTREAMStype := (others => (others => '0'));
signal DOB: SLV8xNTCPSTREAMStype := (others => (others => '0'));
type PTRtype is array (integer range 0 to (NTCPSTREAMS-1)) of unsigned(ADDR_WIDTH-1 downto 0);
signal WPTR: U17xNTCPSTREAMStype := (others => (others => '0'));
signal RPTR: PTRtype := (others => (others => '0'));
signal RPTR_MAX: unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
signal RPTR_BEYOND_UPPER_LIMIT: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
type SIZEtype is array (integer range 0 to (NTCPSTREAMS-1)) of unsigned(ADDR_WIDTH downto 0);
	-- extend one bit to make signed signals
signal BUF_SIZE: SIZEtype := (others => (others => '0'));
signal NEXT_TX_FRAME_SIZE: PTRtype := (others => (others => '0'));
signal AVAILABLE_BUF_SPACE: PTRtype := (others => (others => '0'));
signal WEA: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal APP_CTS_local: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal CONNECTED_FLAG_D: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal CONNECTED_FLAG_D2: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');

--// SEGMENT INPUT DATA INTO PACKETS 
signal SAMPLE2_CLK: std_logic := '0';
signal SAMPLE2_CLK_D: std_logic := '0';
signal SAMPLE2_CLK_D2: std_logic := '0';
signal DATA2: std_logic_vector(7 downto 0) := (others => '0');
signal DATA2_D: std_logic_vector(7 downto 0) := (others => '0');
signal DATA2_WORD: std_logic_vector(16 downto 0) := (others => '0');
signal DATA2_SHIFT8: std_logic_vector(16 downto 0) := (others => '0');

signal FRAME_SIZE2: unsigned(ADDR_WIDTH-1 downto 0):= (others => '0');
signal TX_PAYLOAD_DATA_local: std_logic_vector(7 downto 0) := x"00";

--// TCP_SERVER INTERFACE ------------------------
signal EFF_RX_WINDOW_SIZE: U17xNTCPSTREAMStype := (others => (others => '0'));
signal EFF_RX_WINDOW_SIZE_D: U17xNTCPSTREAMStype := (others => (others => '0'));
signal EFF_RX_WINDOW_SIZE_MSB: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EFF_RX_WINDOW_SIZE_MSB_D: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EFF_RX_WINDOW_SIZE_PARTIAL: U17xNTCPSTREAMStype := (others => (others => '0'));
signal TX_SEQ_NO: U17xNTCPSTREAMStype := (others => (others => '0'));

--// TCP TX CHECKSUM  ---------------------------
signal TCP_CKSUM: unsigned(16 downto 0):= (others => '0');
signal ODD_EVENn: std_logic := '0';

--// OUTPUT BUFFER --------------------------------
signal OB_WEA: std_logic := '0';
signal OB_ADDRA: unsigned(OB_ADDR_WIDTH-1 downto 0) := (others => '0');
signal OB_ADDRB: unsigned(OB_ADDR_WIDTH-1 downto 0) := (others => '0'); 
signal WPTR_END: unsigned(OB_ADDR_WIDTH-1 downto 0) := (others => '0'); 
signal OBUF_SIZE: unsigned(OB_ADDR_WIDTH-1 downto 0) := (others => '0'); 
signal OBUF_SIZE_ZERO: std_logic := '0';


signal OB_SAMPLE_CLK_E: std_logic := '0';
signal OB_SAMPLE_CLK: std_logic := '0';
signal OB_DIA: std_logic_vector(7 downto 0) := (others => '0');
signal OB_DOB: std_logic_vector(7 downto 0) := (others => '0');
signal TX_STREAM_SEL_local: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal TX_STREAM_SEL_local0: std_logic_vector((NTCPSTREAMS-1) downto 0):= (others => '0');
signal TX_PAYLOAD_CHECKSUM0: std_logic_vector(16 downto 0) := (others => '0');
signal TX_PAYLOAD_SIZE0: std_logic_vector(15 downto 0)  := (others => '0');

signal OUTPUT_STREAM_CONNECTED: std_logic := '0';
signal TX_PAYLOAD_DATA_VALID_local: std_logic := '0';

--// TCP TX STATE MACHINE ---------------------------
signal EVENTS0A: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS0B: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS0C: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS0D: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS0E: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS1A: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS1B: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS1: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS2: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS3: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENTS5: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 
signal EVENT4: std_logic := '0';
signal EVENT5: std_logic := '0';
type STATEtype is array (integer range 0 to (NTCPSTREAMS-1)) of integer range 0 to 3;
signal TCP_TX_STATE: STATEtype;
type CNTR2type is array (integer range 0 to (NTCPSTREAMS-1)) of integer range 0 to 3;
signal TIMER1: CNTR2type := (others => 0);
signal TX_SEQ_NO_JUMP_D: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0'); 

--// CHECKSUM STATE MACHINE -------------------------
signal CKSUM_STATE: integer range 0 to 3 := 0;  
signal CKSUM_STREAM_SEL: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal CKSUM_STREAM_SEL2: std_logic_vector((NTCPSTREAMS-1) downto 0) := (others => '0');
signal CKSUM_START_TRIGGER: std_logic := '0';
signal CKSUM_START_TRIGGER_D: std_logic := '0';


--------------------------------------------------------
--      IMPLEMENTATION
--------------------------------------------------------
begin

--// SEGMENT INPUT DATA INTO PACKETS -----------------

-- Raise a flag when no new Tx data is received in the last 200 us. 
-- Keep track for each stream.
TX_IDLE_GENx: FOR I in 0 to (NTCPSTREAMS-1) generate
	TX_IDLE_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') or (CONNECTED_FLAG(I) = '0') then
				if(SIMULATION = '1') then
					TX_IDLE_TIMER(I) <= 2;	-- shortened timeout during simulation
				else
					TX_IDLE_TIMER(I) <= TX_IDLE_TIMEOUT;
				end if;
			elsif(APP_DATA_VALID(I) = '1') then
				-- new transmit data, re-arm timer
				if(SIMULATION = '1') then
					TX_IDLE_TIMER(I) <= 2;	-- shortened timeout during simulation
				else
					TX_IDLE_TIMER(I) <= TX_IDLE_TIMEOUT;
				end if;
			elsif(TICK_4US = '1') and (TX_IDLE_TIMER(I) /= 0) then
				-- otherwise, decrement until counter reaches 0 (TX_IDLE condition)
				TX_IDLE_TIMER(I) <= TX_IDLE_TIMER(I) -1;
			end if;
		end if;
	end process;

	TX_IDLE(I) <= '1' when (TX_IDLE_TIMER(I) = 0) and (APP_DATA_VALID(I) = '0') else '0';
end generate;

--//-- INPUT ELASTIC BUFFER ---------------------------
SHIFT_APP_DATA_IN_00X: for I in 0 to (NTCPSTREAMS-1) generate
	SHIFT_APP_DATA_IN_001:process(CLK)
	begin
		if rising_edge(CLK) then
			APP_DATA_VALID_D(I) <= APP_DATA_VALID(I);

			if(CONNECTED_FLAG(I) = '0') then
				-- on hold until WPTR is initialized
				WEA(I) <= '0';
			elsif(APP_DATA_VALID(I) = '1') then
				-- write input byte
				WEA(I) <= '1';
				DIA(I) <= APP_DATA(I);
			else
				WEA(I) <= '0';
			end if;
		end if;
	end process;
	 
	-- remember if a flush is pending
	FLUSH_PENDING_001:process(CLK)
	begin
		if rising_edge(CLK) then
			APP_DATA_FLUSH_PENDING_D(I) <= APP_DATA_FLUSH_PENDING(I);	-- need extra clock until BUF_SIZE includes the latest word
			
			if(APP_DATA_FLUSH(I) = '1') then
				APP_DATA_FLUSH_PENDING(I) <= '1';
			elsif(EVENTS1(I) = '1') then
				-- decision to transmit is made. clear flush_pending
				APP_DATA_FLUSH_PENDING(I) <= '0';
			end if;
		end if;
	end process;
end generate;        

-- write pointer management. One for each stream.
-- Definition: next memory location to be written to.
WPTR_GENx: FOR I in 0 to (NTCPSTREAMS-1) generate
	WPTR_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(CONNECTED_FLAG(I) = '0') then
				-- near and up to the start of connection. TX_SEQ_NO_IN is ready to be read.
				-- Pre-position the write and read memory pointers so that the addresses are consistent with the 
				-- TCP sequence numbers (which start with a random initial sequence number upon establishing a TCP connection).
				WPTR(I) <= unsigned(TX_SEQ_NO_IN(I));    -- units: bytes
			elsif(WEA(I) = '1') then -- *011723
				WPTR(I) <= WPTR(I) + 1;
			end if;
		end if;
	end process;
	
	
end generate;

BRAM_DP2_X: for I in 0 to (NTCPSTREAMS-1) generate
--  BRAM size is determined by ADDR_WIDTH
    BRAM_DP2_001: BRAM_DP2C 
    GENERIC MAP(
        DATA_WIDTH => 8,		
        ADDR_WIDTH => ADDR_WIDTH
    )
    PORT MAP(
        CLK => CLK,
        CSA => '1',
        WEA => WEA(I),      -- Port A Write Enable Input
        ADDRA =>  std_logic_vector(WPTR(I)(ADDR_WIDTH-1 downto 0)),
        DIA => DIA(I),      -- Port A  Data Input
        CSB => '1',
        ADDRB => std_logic_vector(RPTR(I)(ADDR_WIDTH-1 downto 0)),  -- Port B Address Input
        DOB => DOB(I)      -- Port B Data Output
    );    
end generate;

-- read pointer management
-- Rule #1: RPTR = TX_SEQ_NO(I) at start and upon client ack timeout (TX_SEQ_NO_JUMP)
-- Rule #2: RPTR points to the next memory location to be read
-- Rule #3: Clear all data within the elastic buffer after closing TCP connection

RPTR_GENx: FOR I in 0 to (NTCPSTREAMS-1) generate
	RPTR_GEN_002: process(CLK)
	begin
		if rising_edge(CLK) then
			if(CONNECTED_FLAG(I) = '0') then
				-- At the same time as we set the WPTR -> cause the occupied size to be zero.
				RPTR(I) <= unsigned(TX_SEQ_NO_IN(I)(ADDR_WIDTH-1 downto 0));    -- units: bytes
			else
				if(TCP_TX_STATE(I) < 2)  then
					-- idle states. re-position the read pointer
					RPTR(I) <= TX_SEQ_NO(I)(ADDR_WIDTH-1 downto 0);
				elsif(TCP_TX_STATE(I) = 2) and (CKSUM_STREAM_SEL2(I) = '1')then
					-- read a frame to the checksum computation circuit and output buffer
					if (EVENTS3(I) = '0') then
						-- continue reading the frame
						RPTR(I) <= RPTR(I) + 1;
					else
						-- completed checksum scan. 
						RPTR(I) <= RPTR_MAX;   -- fine repositioning (because +8 increment is sometimes too much for the last word)
					end if;
				end if;
			end if;
		end if;
	end process;
	
	-- detect the last read (and beyond)
	RPTR_BEYOND_UPPER_LIMIT(I) <= '1' when (RPTR(I)(ADDR_WIDTH-1 downto 0)  = RPTR_MAX(ADDR_WIDTH-1 downto 0)) else
										'0';
	
	
end generate;

--// BUFFER OUTPUT ----------------

-- One checksum computation circuit
-- First mux streams into checksum computation
MUX2CHECKSUM_001: process(CLK)
variable S2_CLK: std_logic;
begin
    if rising_edge(CLK) then
        S2_CLK := '0';
        for I in 0 to NTCPSTREAMS-1 loop
            if(TCP_TX_STATE(I)  = 2) and (EVENTS3(I) = '0') then
                S2_CLK := '1';
            end if;
        end loop;
        SAMPLE2_CLK <= S2_CLK;
    end if;
end process;

MUX2CHECKSUM_002: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			FRAME_SIZE2 <= (others => '0');
			RPTR_MAX <= (others => '0');
		else
			for I in 0 to NTCPSTREAMS-1 loop
				if(EVENTS2(I) = '1') then	
					-- trigger checksum computation. Freeze info
					FRAME_SIZE2 <= NEXT_TX_FRAME_SIZE(I);
					RPTR_MAX <= NEXT_TX_FRAME_SIZE(I) + TX_SEQ_NO(I)(ADDR_WIDTH-1 downto 0);
				end if;
			end loop;
		end if;
	end if;
end process;

MUX2CHECKSUM_003: process(CKSUM_STREAM_SEL2, DOB)
variable DATA2v: std_logic_vector(7 downto 0);
begin
	 DATA2v := (others => '0');
    for I in 0 to NTCPSTREAMS-1 loop
        if(CKSUM_STREAM_SEL2(I) = '1') then
            DATA2v := DOB(I);
        end if;
    end loop;
    DATA2 <= DATA2v;
end process;

--// TCP TX CHECKSUM  ---------------------------
-- Compute the TCP payload checksum (excluding headers which are included in the TCP_TX formatting component).

-- final 1 carry bit will be added later (in calling entity)
DATA2_WORD <= "0" & DATA2_D & DATA2;
DATA2_SHIFT8 <= "0" & DATA2_D & x"00";
UDP_CKSUM_001: 	process(CLK)
begin
	if rising_edge(CLK) then
	    SAMPLE2_CLK_D <= SAMPLE2_CLK;
	    SAMPLE2_CLK_D2 <= SAMPLE2_CLK_D;
	    
        if(CKSUM_START_TRIGGER = '1') then
				ODD_EVENn <= '0';
            TCP_CKSUM <= (others => '0');  
        elsif(SAMPLE2_CLK = '1') then
				ODD_EVENn <= not ODD_EVENn;	-- toggle odd/even
				if(ODD_EVENn = '0') then
					DATA2_D <= DATA2;
				else
					TCP_CKSUM <= resize(TCP_CKSUM(15 downto 0),17) + resize(TCP_CKSUM(16 downto 16),17)
									+ unsigned(DATA2_WORD);
				end if;
			elsif(ODD_EVENn = '1') then
				-- odd number of bytes in the TCP payload. Pad on the right with zeros and sum one last time.
				ODD_EVENn <= not ODD_EVENn;	-- toggle odd/even
				TCP_CKSUM <= resize(TCP_CKSUM(15 downto 0),17) + resize(TCP_CKSUM(16 downto 16),17)
								+ unsigned(DATA2_SHIFT8);
        end if;
    end if;
end process;


--// OUTPUT BUFFER --------------------------------
-- Must be sized (through OB_ADDR_WIDTH) to contain at least 2 maximum-size frames (MSS)
-- This circular buffer is used for up to two simultaneous transactions:
-- - read a ready-to-transmit frame for which we have already computed the (partial) checksum
-- from the B-side of the dual-port RAM 
-- - write a frame while computing its (partial) checksum
-- to the A-side of the dual-port RAM 
OB_WEA <= SAMPLE2_CLK;
OB_DIA <= DATA2;

-- write pointer management
OB_WPTR_GEN: process(CLK)
begin
    if rising_edge(CLK) then
        if(SYNC_RESET = '1') then
            OB_ADDRA <= (others => '0');
			elsif(EVENT5 = '1') then -- *072718
				-- disruption of current stream selected for checksum computation (server size asks to rewind)
				OB_ADDRA <= WPTR_END; -- cancel partial output frame
        elsif(OB_WEA = '1') and (CKSUM_STATE = 1) then
            OB_ADDRA <= OB_ADDRA + 1;
        end if;
    end if;
end process;

OB_001: BRAM_DP2C 
GENERIC MAP(
    DATA_WIDTH => 8,        
    ADDR_WIDTH => OB_ADDR_WIDTH
)
PORT MAP(
    CLK => CLK,
    CSA => '1',
    WEA => OB_WEA,      -- Port A Write Enable Input
    ADDRA =>  std_logic_vector(OB_ADDRA),
    DIA => OB_DIA,      -- Port A  Data Input
    CSB => '1',
    ADDRB => std_logic_vector(OB_ADDRB),  -- Port B Address Input
    DOB => OB_DOB      -- Port B Data Output
);    

TX_PAYLOAD_DATA <= OB_DOB;
TX_PAYLOAD_DATA_VALID <= OB_SAMPLE_CLK;
TX_PAYLOAD_DATA_EOF <= OBUF_SIZE_ZERO and OB_SAMPLE_CLK; 
OBUF_SIZE <= WPTR_END + not(OB_ADDRB);

-- output buffer read pointer
-- OB_ADDRB = last address read
OB_RPTR_GEN: process(CLK)
begin
    if rising_edge(CLK) then
        OB_SAMPLE_CLK <= OB_SAMPLE_CLK_E;
        
        if(SYNC_RESET = '1') then
            OB_ADDRB <= (others => '1');
            OB_SAMPLE_CLK_E <= '0';
--        elsif(TX_PAYLOAD_CTS = '1') and (OBUF_SIZE /= 0) and (CKSUM_STATE /= 0) then
-- test test test
        elsif(TX_PAYLOAD_CTS = '1') and (OBUF_SIZE /= 0) then
            OB_ADDRB <= OB_ADDRB + 1;
            OB_SAMPLE_CLK_E <= '1';
        else
            OB_SAMPLE_CLK_E <= '0';
        end if;
		  
		-- aligned with OB_SAMPLE_CLK
		if(OBUF_SIZE = 0) then
			OBUF_SIZE_ZERO <= '1';
		else
			OBUF_SIZE_ZERO <= '0';
		end if;
    end if;
end process;





--// TCP_SERVER INTERFACE ------------------------
-- predict the next frame TX_SEQ_NO 
FREEZE_TX_SEQ_NO_x: for I in 0 to (NTCPSTREAMS - 1) generate
	FREEZE_TX_SEQ_NO_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(TX_SEQ_NO_JUMP(I) = '1') then	--*072718
				-- force rewind. Abort any current read/checksum computation			
				-- update TCP_TX_NO after the server has reported a discontinuity (at connection time, or when the client
				-- asks to retransmit). Update locally upon processing successive frames, unless a 
				-- discontinuity is requested.
				TX_SEQ_NO(I) <= unsigned(TX_SEQ_NO_IN(I));
			elsif(EVENTS3(I) = '1') then
				-- completed reading a frame out of the memory to compute payload checksum
				-- regular progress at the end of frame
				TX_SEQ_NO(I) <= TX_SEQ_NO(I) + resize(FRAME_SIZE2, TX_SEQ_NO(I)'length);
			end if;
		end if;
	end process;
end generate;

-- compute the Effective TCP rx window size = advertised TCP rx window size - unacknowledged but sent data size
-- changes at end of tx frame, and upon receiving a valid ack
EFF_RX_WINDOW_SIZE_GENx: for I in 0 to (NTCPSTREAMS - 1) generate
	EFF_RX_WINDOW_SIZE_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(EFF_RX_WINDOW_SIZE_PARTIAL_VALID = '1') and (EFF_RX_WINDOW_SIZE_PARTIAL_STREAM(I) = '1') then
				EFF_RX_WINDOW_SIZE_PARTIAL(I) <= unsigned(EFF_RX_WINDOW_SIZE_PARTIAL_IN);
			end if;
		end if;
	end process;
end generate;
	
	
-- effective TCP rx window size is EFF_RX_WINDOW_SIZE_PARTIAL - TX_SEQ_NO 
-- This is the maximum number of bytes that the TCP client can accept.
-- EFF_RX_WINDOW_SIZE is valid only up to the tx decision time (while TCP_TX_STATE = 0)
EFF_RX_WINDOW_SIZE_GENy: for I in 0 to (NTCPSTREAMS - 1) generate
	EFF_I_GEN: process(CLK, EFF_RX_WINDOW_SIZE)
	begin
		if rising_edge(CLK) then
			EFF_RX_WINDOW_SIZE_D(I) <= EFF_RX_WINDOW_SIZE(I);
			
			if(CONNECTED_FLAG(I) = '0') then
				EFF_RX_WINDOW_SIZE(I) <= (others => '0');	-- *121418
			else
				EFF_RX_WINDOW_SIZE(I) <= EFF_RX_WINDOW_SIZE_PARTIAL(I) - unsigned(TX_SEQ_NO(I));
			end if;
		end if;
		EFF_RX_WINDOW_SIZE_MSB(I) <= EFF_RX_WINDOW_SIZE(I)(16);
				-- detect if window size goes negative temporarily (can happen if the other side adjusts the rx window)
	end process;
end generate;

--// TX EVENTS -------------------------------------
-- has the input been idle for over 200us? see TX_IDLE

-- How many bytes are waiting in the tx buffer? 
-- BUF_SIZE is valid only up to the tx decision time (while TCP_TX_STATE = 0)
TX_BUFFER_SIZE_GENx: for I in 0 to (NTCPSTREAMS - 1) generate
	BUF_SIZE_I_GEN: process(CLK)
	begin
		if rising_edge(CLK) then
			BUF_SIZE(I) <= WPTR(I)(ADDR_WIDTH downto 0) - unsigned(TX_SEQ_NO(I)(ADDR_WIDTH downto 0));
		end if;
	end process;
end generate;

-- Compute the next tx frame size
-- two upper bounds for the tx frame size: MSS bytes and EFF_RX_WINDOW_SIZE_D
NEXT_TX_FRAME_SIZE_GENx: for I in 0 to (NTCPSTREAMS - 1) generate
	NEXT_TX_FRAME_SIZE_GEN_001:  process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				NEXT_TX_FRAME_SIZE(I) <= (others => '0');
			elsif(CONNECTED_FLAG_D2(I) = '0') then
				-- no TCP-IP connection yet, or pointer information not fully available yet. Nothing to send.
				NEXT_TX_FRAME_SIZE(I) <= (others => '0');
			elsif(TCP_TX_STATE(I) = 0) then
				-- update frame size up to the tx decision time
				-- Once the decision to transmit is taken, freeze NEXT_TX_FRAME_SIZE into FRAME_SIZE2 until the frame transmission is complete.
				if(EVENTS0D(I) = '0') then
					-- no space at receiving end
					NEXT_TX_FRAME_SIZE(I) <= (others => '0');
				elsif(EVENTS0B(I) = '0') and (EVENTS0C(I) = '0') and (BUF_SIZE(I)(ADDR_WIDTH) = '0') then
					-- BUF_SIZE is positive, does not exceed MSS or the available space at the receiving end
               NEXT_TX_FRAME_SIZE(I) <= BUF_SIZE(I)(ADDR_WIDTH-1 downto 0);
				elsif(EVENTS0B(I) = '1') and (EVENTS0C(I) = '0') then
					-- effective rx window size not the most stringent constraint.
					-- maximum payload size is constrained by MSS byte ceiling
					-- KEY ASSUMPTION: MSS is smaller than the instantiated buffer(s) address range.						
					NEXT_TX_FRAME_SIZE(I) <= to_unsigned(MSS,NEXT_TX_FRAME_SIZE(I)'length);
				elsif(EVENTS0B(I) = '0') and (EVENTS0C(I) = '1') then
					-- effective rx window size is the most stringent constraint.
					NEXT_TX_FRAME_SIZE(I) <= EFF_RX_WINDOW_SIZE_D(I)(ADDR_WIDTH-1 downto 0);
				elsif(EVENTS0E(I) = '1') then
					-- effective rx window size limit
               NEXT_TX_FRAME_SIZE(I) <= EFF_RX_WINDOW_SIZE_D(I)(ADDR_WIDTH-1 downto 0);
				else
					-- MSS limit
               NEXT_TX_FRAME_SIZE(I) <= to_unsigned(MSS,NEXT_TX_FRAME_SIZE(I)'length);
				end if;
			end if;
		end if;
	end process;
end generate;

--// TX STATE MACHINE -------------------------------------
-- Decision to send a packet is made here based on
-- (a) input has been idle for more than 200 us, or
-- (b) the packet size collected so far has reached its threshold of MSS bytes, or less if the effective 
-- rx window is smaller. 
-- (c) immediate flush request
TCP_TX_STATE_GENx: for I in 0 to (NTCPSTREAMS - 1) generate
	-- for timing purposes, reclock these trigger events
	EVENTS0_I_GEN: process(CLK)
	begin
		if rising_edge(CLK) then
			-- data in buffer
			if(BUF_SIZE(I) > 0) then
				EVENTS0A(I) <= '1';
			else
				EVENTS0A(I) <= '0';
			end if;

			-- buffer size greater than MSS
			if(BUF_SIZE(I) >= MSS) then
				EVENTS0B(I) <= '1';
			else
				EVENTS0B(I) <= '0';
			end if;

			-- buffer size greater than EFF_RX_WINDOW_SIZE(I)
			-- and EFF_RX_WINDOW_SIZE(I) is not negative (meaning zero space available at rx end)
			if(BUF_SIZE(I) >= EFF_RX_WINDOW_SIZE(I)(ADDR_WIDTH downto 0)) and (EFF_RX_WINDOW_SIZE(I)(16 downto ADDR_WIDTH+1) = 0) then
				EVENTS0C(I) <= '1';
			else
				EVENTS0C(I) <= '0';
			end if;

			-- receiving end has space for more data
			if(EFF_RX_WINDOW_SIZE(I) > 0) and (EFF_RX_WINDOW_SIZE_MSB(I) = '0')  then
				EVENTS0D(I) <= '1';
			else
				EVENTS0D(I) <= '0';
			end if;

			-- MSS greater than EFF_RX_WINDOW_SIZE(I)
			if(EFF_RX_WINDOW_SIZE(I) < MSS) or (EFF_RX_WINDOW_SIZE_MSB(I) = '1') then
				EVENTS0E(I) <= '1';
			else
				EVENTS0E(I) <= '0';
			end if;
			
		end if;
	end process;
	
    EVENTS1A(I) <= '1' when (CONNECTED_FLAG(I) = '1') and (TCP_TX_STATE(I) = 0) and (EVENTS0A(I) = '1') and 
			(EVENTS0D(I) = '1') and ((TX_IDLE(I) = '1') or (APP_DATA_FLUSH_PENDING_D(I) = '1')) else '0';
        -- immediate flush request or no new data in 200us while data is waiting to be transmitted and rx end can accept new data. 
		  -- Initiate transmission
    EVENTS1B(I) <= '1' when (CONNECTED_FLAG(I) = '1') and (TCP_TX_STATE(I) = 0) and (EVENTS0A(I) = '1') and
			(EVENTS0D(I) = '1') and ((EVENTS0B(I) = '1') or (EVENTS0C(I) = '1')) else '0';
        -- enough data for a full tx frame or enough to fill the receiving end. don't wait. 
		  -- Initiate transmission.
-- old. seems uncessary
--    EVENTS1C(I) <= '1' when (CONNECTED_FLAG(I) = '1') and (TCP_TX_STATE(I) = 0) and (EVENTS0A(I) = '1') and 
--			(EVENTS0D(I) = '1') and (APP_CTS_local(I) = '0') and (EVENTS0C(I) = '1') else '0';
--			-- Elastic buffer is full and enough to fill the receiving end. don't wait. 
--			-- Initiate transmission.
    EVENTS1(I) <=  EVENTS1A(I) or EVENTS1B(I);
        -- transmit decision time
    EVENTS2(I) <= '1' when (CONNECTED_FLAG(I) = '1') and (TCP_TX_STATE(I) = 1) and (CKSUM_STREAM_SEL2(I) = '1') and (CKSUM_START_TRIGGER = '1') else '0';
        -- start checksum computation
    EVENTS3(I) <= '1' when (CONNECTED_FLAG(I) = '1') and (TCP_TX_STATE(I) = 2) and (CKSUM_STREAM_SEL2(I) = '1') and 
                        (RPTR_BEYOND_UPPER_LIMIT(I) = '1') else '0'; 
        -- completed reading a frame to the checksum computation circuit and output buffer

	EVENTS5(I) <= CKSUM_START_TRIGGER when (TX_SEQ_NO_JUMP(I) = '1') and (CKSUM_STREAM_SEL2(I) = '1')   else '0';
		-- disruption of current stream selected for checksum computation (server size asks to rewind)


	-- TCP_TX_STATE
	-- 0 = idle
	-- 1 = frame size committed. awaiting checksum computation circuit availability
	-- 2 = reading data from the input buffer, computing checksum
	-- 3 = fixed gap after checksum computation
	TCP_TX_STATE_GEN_001: process(CLK)
	begin
		if rising_edge(CLK) then
			TX_SEQ_NO_JUMP_D <= TX_SEQ_NO_JUMP;
			
			if(SYNC_RESET = '1') or (CONNECTED_FLAG(I) = '0') then
				-- lost or no connection. Reset tx state machine, irrespective of the current state
				TCP_TX_STATE(I) <= 0;	-- back to idle
				TIMER1(I) <= 0;	
			elsif(TX_SEQ_NO_JUMP(I) = '1') and (TX_SEQ_NO_JUMP_D(I) = '0') then	--*011623
				-- force rewind. Abort any current read/checksum computation
				TCP_TX_STATE(I) <= 0;	-- back to idle
				TIMER1(I) <= 2;	-- need one extra clock to compute BUF_SIZE

			-- transmit decision time
			elsif(EVENTS1(I) = '1') and (TIMER1(I) = 0) then
				-- immediate flush request or no new data in 200us while data is waiting to be transmitted. Initiate transmission
				-- or enough data for a full tx frame. don't wait. Initiate transmission.
				TCP_TX_STATE(I) <= 1;	-- awaiting checksum circuit trigger
			elsif(EVENTS2(I) = '1') then
				-- start checksum computation
				TCP_TX_STATE(I) <= 2;	-- reading data from the elastic buffer, computing checksum
			elsif (EVENTS3(I) = '1') then
				-- completed reading a frame out of the memory to compute payload checksum
				TCP_TX_STATE(I) <= 3;    -- delay until the next tx size is computed
				TIMER1(I) <= 1;	-- need one extra clock until key events are ready
			elsif (TCP_TX_STATE(I) = 3) and (TIMER1(I) = 0) then
				TCP_TX_STATE(I) <= 0;	-- timer expired. back to idle
			elsif(TIMER1(I) > 0) then
				TIMER1(I) <= TIMER1(I) - 1;
			end if;
			
		end if;
	end process;
end generate;

EVENT4 <=   '1' when (SAMPLE2_CLK_D = '1') and (SAMPLE2_CLK = '0') and (ODD_EVENn = '0') else -- even # of payload bytes
            '1' when (SAMPLE2_CLK_D2 = '1') and (SAMPLE2_CLK_D = '0') and (ODD_EVENn = '0') else    -- odd # of payload bytes, +1 clk to complete cksum 
            '0';
  -- end of checksum computation

EVENT5 <= '1' when (unsigned(EVENTS5) /= 0) else '0';
	-- checksum computation disruption. Rewind.
	-- disruption of current stream selected for checksum computation (server size asks to rewind)

--// CHECKSUM STATE MACHINE -------------------------
-- all streams out of the elastic buffers are multiplexed into a single checksum computation circuit based on 
-- CKSUM_STREAM_SEL. The checksum circuit state machine is below:
CKSUM_STATE_GEN: process(CLK)
begin
	if rising_edge(CLK) then
        CKSUM_START_TRIGGER_D <= CKSUM_START_TRIGGER;
        
		if(SYNC_RESET = '1') then
			CKSUM_STATE <= 0;
			CKSUM_START_TRIGGER <= '0';
			
		elsif(EVENT5 = '1') then -- *072718
			-- disruption of current stream selected for checksum computation (server size asks to rewind)
			CKSUM_STATE <= 0;
	    elsif(CKSUM_STATE = 0) then
	       -- checksum circuit idle 
	       -- is any stream awaiting checksum circuit trigger? If so, start computing checksum
	      for I in 0 to NTCPSTREAMS-1 loop
                if(CKSUM_STREAM_SEL(I) = '1') and (TCP_TX_STATE(I) = 1) and (CONNECTED_FLAG(I) = '1') then
                    -- freeze the ONE stream selected for checksum computation
                    CKSUM_STATE <= 1;
                    CKSUM_START_TRIGGER <= '1';
                    CKSUM_STREAM_SEL2 <= CKSUM_STREAM_SEL;  
                end if;
          end loop;
        elsif (CKSUM_STATE = 1) and (EVENT4 = '1') then 
          -- end of checksum computation 
          CKSUM_START_TRIGGER <= '0';
          if(OBUF_SIZE /= 0) then
            -- we are not yet done reading the previous frame. wait
            CKSUM_STATE <= 2;
          else
            -- done with both checksum computation and previous frame out
            -- we can trigger the next frame output processing
            CKSUM_STATE <= 0;
            WPTR_END <= OB_ADDRA;   -- upper limit for next frame to be forwarded to TCP_TX
         end if;
        elsif (CKSUM_STATE = 2) and (OBUF_SIZE = 0) then 
            -- done with both checksum computation and previous frame out
            -- Wait for one more word request (with no response from us) to mark the end of frame in TCP_TX_10G.vhd.
            CKSUM_STATE <= 3;
        elsif (CKSUM_STATE = 3) then 
            -- we can trigger the next frame output processing
            CKSUM_STATE <= 0;
            WPTR_END <= OB_ADDRA;   -- upper limit for next frame to be forwarded to TCP_TX
        else
          CKSUM_START_TRIGGER <= '0';
          -- also detect disconnection
	      for I in 0 to NTCPSTREAMS-1 loop
                if(CKSUM_STREAM_SEL2(I) = '1') and (CONNECTED_FLAG(I) = '0') then
                    CKSUM_STATE <= 0;
                    WPTR_END <= (others => '0');
                    CKSUM_STREAM_SEL2(I) <= '0';
                end if;
          end loop;
		end if;
    end if;
end process;


-- select the stream for the next checksum computation
-- scan all possible streams until we reach TCP_TX_STATE(I) = 1 (awaiting checksum circuit trigger) 
-- THERE CAN BE ONLY ONE SINGLE STREAM SELECTED FOR THE CHECKSUM AND OUTPUT BUFFER
NEXT_STREAM_SELECT_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			CKSUM_STREAM_SEL(0) <= '1';
			CKSUM_STREAM_SEL(CKSUM_STREAM_SEL'left downto 1) <= (others => '0');
		elsif(NTCPSTREAMS > 1) then
		  for I in 0 to NTCPSTREAMS-1 loop
              if(CKSUM_STREAM_SEL(I) = '1') and ((TCP_TX_STATE(I) /= 1) or (CONNECTED_FLAG(I) = '0')) then
                  -- this stream is not awaiting checksum circuit trigger. move on.
                  -- or this stream just completed a checksum computation, back to the end of the line
                  -- circular rotation
                  CKSUM_STREAM_SEL(NTCPSTREAMS-1 downto 1) <= CKSUM_STREAM_SEL(NTCPSTREAMS-2 downto 0);
                  CKSUM_STREAM_SEL(0) <= CKSUM_STREAM_SEL(NTCPSTREAMS-1);
		      end if;    
		  end loop;
		end if;
	end if;
end process;
	
-- tell the TCP_SERVER about the stream selected for the next tx frame, the partial checksum, the number of payload bytes.
-- The information is valid when TX_PAYLOAD_RTS = '1'.
TCP_SERVER_INFO_GEN: process(CLK)
begin
	if rising_edge(CLK) then
		if(SYNC_RESET = '1') then
			TX_PAYLOAD_CHECKSUM <= (others => '0');
			TX_PAYLOAD_SIZE <= (others => '0');
			TX_STREAM_SEL_local <= (others => '0');
		elsif (CKSUM_STATE = 1) and (EVENT4 = '1') then
			if(OBUF_SIZE /= 0) then
				-- we are not yet done reading the previous frame. wait
				-- freeze info regarding the next tx frame until we are about to start next tx frame
				TX_PAYLOAD_CHECKSUM0 <= std_logic_vector(TCP_CKSUM); -- up to 2 bits of carry
				TX_PAYLOAD_SIZE0 <= std_logic_vector(resize(FRAME_SIZE2,16)); -- payload size in bytes
				TX_STREAM_SEL_local0 <= CKSUM_STREAM_SEL2;
			else
				-- done with checksum computation. Previous frame is either being read out or completely read.
				-- next tx frame is about to start
				TX_PAYLOAD_CHECKSUM <= std_logic_vector(TCP_CKSUM); -- up to 2 bits of carry
				TX_PAYLOAD_SIZE <= std_logic_vector(resize(FRAME_SIZE2,16)); -- payload size in bytes
				TX_STREAM_SEL_local <= CKSUM_STREAM_SEL2;
			end if;
		elsif (CKSUM_STATE = 3) then 
			-- next tx frame is about to start
			TX_PAYLOAD_CHECKSUM <= TX_PAYLOAD_CHECKSUM0;
			TX_PAYLOAD_SIZE <= TX_PAYLOAD_SIZE0;
			TX_STREAM_SEL_local <= TX_STREAM_SEL_local0;
		end if;
    end if;
end process;
TX_STREAM_SEL <= TX_STREAM_SEL_local;

-- is the output stream still connected?
OUTPUT_STREAM_CONNECTED_GEN: process(TX_STREAM_SEL_local, CONNECTED_FLAG)
variable OSC: std_logic;
begin
    OSC := '0';
    for I in 0 to NTCPSTREAMS-1 loop
        if(TX_STREAM_SEL_local(I) = '1') and (CONNECTED_FLAG(I) = '1') then
            OSC := '1';
        end if;
    end loop;
    OUTPUT_STREAM_CONNECTED <= OSC;
end process;
TX_PAYLOAD_RTS <= OUTPUT_STREAM_CONNECTED when (OBUF_SIZE /= 0) else '0';
    -- payload data is available for transmission AND TCP connection is still on.

--// TCP TX FLOW CONTROL  ---------------------------
-- The basic tx flow control rule is that the buffer WPTR must never pass the last acknowledged tx byte location.
AVAILABLE_BUF_SPACE_GENx: for I in 0 to (NTCPSTREAMS - 1) generate

	AVAILABLE_BUF_SPACE_001: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				AVAILABLE_BUF_SPACE(I) <=(others => '0');
				CONNECTED_FLAG_D(I) <= '0';
				CONNECTED_FLAG_D2(I) <= '0';
			else
				CONNECTED_FLAG_D(I) <= CONNECTED_FLAG(I); 
				CONNECTED_FLAG_D2(I) <= CONNECTED_FLAG_D(I); -- align with AVAILABLE_BUF_SPACE
				AVAILABLE_BUF_SPACE(I) <= unsigned(RX_TCP_ACK_NO_D(I)(ADDR_WIDTH-1 downto 0)) + not(WPTR(I)(ADDR_WIDTH-1 downto 0));   -- units: bytes
			end if;
		end if;
	end process;
	
	-- input flow control
	-- no point in asking for data when there is no TCP connection and data is being discarded.	
	-- allow more tx data in if there is room for at least 512 bytes
	APP_CTS_local(I) <=   '0' when (CONNECTED_FLAG(I) = '0') else 
						  '1' when (AVAILABLE_BUF_SPACE(I)(ADDR_WIDTH-1 downto 9) /=  0) else 
						  '0';
end generate;
APP_CTS <= APP_CTS_local;
-- allow more tx data in if there is room for at least 512 bytes

----// TEST POINTS --------------------------------
TP(1) <= TX_SEQ_NO_JUMP(0);
TP(2) <= '1' when (TIMER1(0) = 0) else '0';
TP(3) <= '1' when(EVENTS1(0) = '1') and (TIMER1(0) = 0) else '0';
TP(4) <= EVENTS1(0);
TP(5) <= EVENTS1A(0);
TP(6) <= EVENTS1B(0);
TP(7) <= EVENTS0A(0);
TP(8) <= EVENTS0D(0);
TP(9) <= EVENTS0B(0) or EVENTS0C(0);
TP(10) <= CONNECTED_FLAG(0);


end Behavioral;
