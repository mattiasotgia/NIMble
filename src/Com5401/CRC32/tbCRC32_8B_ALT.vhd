-------------------------------------------------------------
--	Filename:  tbCRC32_8B_ALT.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 1
--	Date last modified: 8/5/12
-- Inheritance: 	n/a
--
-- description:  
-- VHDL Test Bench for module: CRC32_8B
-- Validate a 32-bit CRC for a specific packet (collected over the LAN)
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.ALL;
 
ENTITY tbCRC32_8B_ALT IS
END tbCRC32_8B_ALT;
 
ARCHITECTURE behavior OF tbCRC32_8B_ALT IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT CRC32_8B
    PORT(
         SYNC_RESET : IN  std_logic;
         CLK : IN  std_logic;
         CRC32_IN : IN  std_logic_vector(31 downto 0);
         DATA_IN : IN  std_logic_vector(7 downto 0);
         SAMPLE_CLK_IN : IN  std_logic;
         CRC32_OUT : OUT  std_logic_vector(31 downto 0);
         CRC32_VALID : OUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal SYNC_RESET : std_logic := '0';
   signal CLK : std_logic := '0';
   signal DATA_IN : std_logic_vector(7 downto 0) := (others => '0');
   signal SAMPLE_CLK_REF : std_logic := '0';

   -- Clock period definitions
   constant CLK_period : time := 10 ns;
	
	-- others
	signal COUNTER: std_logic_vector(6 downto 0);  -- byte counter
	signal TX_DATA: std_logic_vector(7 downto 0);
	
	-- CRC check
   signal CRC32B_IN : std_logic_vector(31 downto 0) := (others => '0');
   signal CRC32B_OUT : std_logic_vector(31 downto 0);
   signal CRC32B_VALID : std_logic;
 
BEGIN
 

   -- Clock process definitions
   CLK_process :process
   begin
		CLK <= '0';
		wait for CLK_period/2;
		CLK <= '1';
		wait for CLK_period/2;
   end process;
 

	gen_001: process 
	begin
		SAMPLE_CLK_REF <= '0';
		wait for 100 ns;
		SAMPLE_CLK_REF <= '1';
		wait for 10 ns;
	end process;
 

	reset_001: process 
	begin
		SYNC_RESET <= '1';
		wait for 100 ns;
		SYNC_RESET <= '0';
		wait;
	end process;
	
	-- count the number of bytes per frame. Modulo - 32 counter. 
	-- count from 0 to 31
	counter_gen: process(CLK)
	begin
		if rising_edge(CLK) then
			if(SYNC_RESET = '1') then
				COUNTER <= (others => '0');
			elsif (SAMPLE_CLK_REF = '1') then
				COUNTER <= COUNTER + 1;
			end if;
		end if;
	end process;

	rx_packet_gen: process(CLK)
	begin
		if rising_edge(CLK) then
			case(COUNTER) is
			 when "0000000" => TX_DATA <= x"FF";
			 when "0000001" => TX_DATA <= x"FF";
			 when "0000010" => TX_DATA <= x"FF";
			 when "0000011" => TX_DATA <= x"FF";
			 when "0000100" => TX_DATA <= x"FF";
			 when "0000101" => TX_DATA <= x"FF";
			 when "0000110" => TX_DATA <= x"00";
			 when "0000111" => TX_DATA <= x"0E";
			 when "0001000" => TX_DATA <= x"08";
			 when "0001001" => TX_DATA <= x"CA";
			 when "0001010" => TX_DATA <= x"BB";
			 when "0001011" => TX_DATA <= x"A3";
			 when "0001100" => TX_DATA <= x"08";
			 when "0001101" => TX_DATA <= x"06";
			 when "0001110" => TX_DATA <= x"00";
			 when "0001111" => TX_DATA <= x"01";
			 when "0010000" => TX_DATA <= x"08";
			 when "0010001" => TX_DATA <= x"00";
			 when "0010010" => TX_DATA <= x"06";
			 when "0010011" => TX_DATA <= x"04";
			 when "0010100" => TX_DATA <= x"00";
			 when "0010101" => TX_DATA <= x"01";
			 when "0010110" => TX_DATA <= x"00";
			 when "0010111" => TX_DATA <= x"0E";
			 when "0011000" => TX_DATA <= x"08";
			 when "0011001" => TX_DATA <= x"CA";
			 when "0011010" => TX_DATA <= x"BB";
			 when "0011011" => TX_DATA <= x"A3";
			 when "0011100" => TX_DATA <= x"AC";
			 when "0011101" => TX_DATA <= x"10";
			 when "0011110" => TX_DATA <= x"01";
			 when "0011111" => TX_DATA <= x"7E";
			 when "0100000" => TX_DATA <= x"00";
			 when "0100001" => TX_DATA <= x"00";
			 when "0100010" => TX_DATA <= x"00";
			 when "0100011" => TX_DATA <= x"00";
			 when "0100100" => TX_DATA <= x"00";
			 when "0100101" => TX_DATA <= x"00";
			 when "0100110" => TX_DATA <= x"AC";
			 when "0100111" => TX_DATA <= x"10";
			 when "0101000" => TX_DATA <= x"01";
			 when "0101001" => TX_DATA <= x"1F";
			 when "0101010" => TX_DATA <= x"00";
			 when "0101011" => TX_DATA <= x"00";
			 when "0101100" => TX_DATA <= x"00";
			 when "0101101" => TX_DATA <= x"00";
			 when "0101110" => TX_DATA <= x"00";
			 when "0101111" => TX_DATA <= x"00";
			 when "0110000" => TX_DATA <= x"00";
			 when "0110001" => TX_DATA <= x"00";
			 when "0110010" => TX_DATA <= x"00";
			 when "0110011" => TX_DATA <= x"00";
			 when "0110100" => TX_DATA <= x"00";
			 when "0110101" => TX_DATA <= x"00";
			 when "0110110" => TX_DATA <= x"00";
			 when "0110111" => TX_DATA <= x"00";
			 when "0111000" => TX_DATA <= x"00";
			 when "0111001" => TX_DATA <= x"00";
			 when "0111010" => TX_DATA <= x"00";
			 when "0111011" => TX_DATA <= x"00";
			 when "0111100" => TX_DATA <= x"13";
			 when "0111101" => TX_DATA <= x"1B";
			 when "0111110" => TX_DATA <= x"C4";
			 when "0111111" => TX_DATA <= x"D3";
			 when others => TX_DATA <= x"00";
		end case;
	end if;
end process;

	-- CRC32 check at receiver ------------------------------------------------------------

   crccheck: CRC32_8B PORT MAP (
          SYNC_RESET => SYNC_RESET,
          CLK => CLK,
          CRC32_IN => CRC32B_IN,
          DATA_IN => TX_DATA,
          SAMPLE_CLK_IN => SAMPLE_CLK_REF,
          CRC32_OUT => CRC32B_OUT,
          CRC32_VALID => CRC32B_VALID
        );
 
 CRC32B_IN <= CRC32B_OUT;
END;
