-------------------------------------------------------------
-- MSS copyright 2011-2013
--	Filename:  com5402pkg.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 1
--	Date last modified: 10/5/13
-- Inheritance: 	n/a
--
-- description:  This package defines supplemental types, subtypes, 
--	constants, and functions. 
--
-- Usage: enter the number of UDP tx and rx components, the number of TCP servers and the number of TCP clients.
---------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package com5402pkg is

	--// UDP -----------------------------------------------------
	constant IPv6_ENABLED: std_logic := '0';
	-- future use. 

	--// TCP STREAMS -----------------------------------------------------
	constant NTCPSTREAMS_MAX: integer range 0 to 255 := 3;  
	-- MAXIMUM number of concurrent TCP streams handled by this component
	-- MUST BE >= NTCPSTREAM in the generic section of COM5402
	-- limitation: <= 255 streams (some integer to 8-bit slv conversions in the memory pointers)
	-- In practice, the number of concurrent TCP streams per instantiated server is quite small as timing
	-- gets worse. If a large number of concurrent TCP streams is needed, it may be better to create
	-- multiple instantiations of the TCP_SERVER, each with a limited number of concurrent streams.
	type SLV32xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(31 downto 0);
	type SLV24xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(23 downto 0);
	type SLV20xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(19 downto 0);
	type SLV16xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(15 downto 0);
	type SLV17xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(16 downto 0);
	type SLV9xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(8 downto 0);
	type SLV8xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(7 downto 0);
	type SLV4xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(3 downto 0);
	type SLV2xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic_vector(1 downto 0);
	type SLxNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of std_logic;
	
	type U64xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(63 downto 0);
	type U32xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(31 downto 0);
	type U24xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(23 downto 0);
	type U17xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(16 downto 0);
	type U16xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(15 downto 0);
	type U8xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(7 downto 0);
	type U4xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(3 downto 0);
	type U2xNTCPSTREAMStype is array (integer range 0 to (NTCPSTREAMS_MAX-1)) of unsigned(1 downto 0);
	


end com5402pkg;

package body com5402pkg is
-- Future use


end com5402pkg;

