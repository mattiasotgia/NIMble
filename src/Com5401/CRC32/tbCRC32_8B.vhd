-------------------------------------------------------------
--	Filename:  tbCRC32_8B.VHD
-- Author: Alain Zarembowitch / MSS
--	Version: 1
--	Date last modified: 8/5/12
-- Inheritance: 	n/a
--
-- description:  generate the CRC for a 28-byte frame. Append the 4-byte CRC.
-- Then run the CRC check on the complete 32-byte frame. 
-- Verify that the CRC32B_VALID is '1' upon receiving a complete frame.
-- The default data DATA_IN is all zeros but can be customized as well.
---------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.std_logic_unsigned.all;
USE ieee.numeric_std.ALL;
 
ENTITY tbCRC32_8B IS
END tbCRC32_8B;
 
ARCHITECTURE behavior OF tbCRC32_8B IS 
 
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
   signal CRC32_IN : std_logic_vector(31 downto 0) := (others => '0');
   signal DATA_IN : std_logic_vector(7 downto 0) := (others => '0');
   signal SAMPLE_CLK_REF : std_logic := '0';
   signal SAMPLE_CLK_IN : std_logic := '0';

 	--Outputs
   signal CRC32_OUT : std_logic_vector(31 downto 0);
   signal CRC32_VALID : std_logic;

   -- Clock period definitions
   constant CLK_period : time := 10 ns;
	
	-- others
	signal COUNTER: std_logic_vector(9 downto 0);  -- byte counter
	signal TX_DATA: std_logic_vector(7 downto 0);
	signal TX_DATA_LSBFIRST: std_logic_vector(7 downto 0);
	
	-- CRC check
   signal CRC32B_IN : std_logic_vector(31 downto 0) := (others => '0');
   signal CRC32B_OUT : std_logic_vector(31 downto 0);
   signal CRC32B_VALID : std_logic;
 
BEGIN
 
	-- CRC32 generation ------------------------------------------------------------
 DATA_IN <= x"00";
 SAMPLE_CLK_IN <= SAMPLE_CLK_REF when (COUNTER < 28) else '0';  -- block 4 sample clocks per frame (to make room for CRC insertion at the output)

   crcgen: CRC32_8B PORT MAP (
          SYNC_RESET => SYNC_RESET,
          CLK => CLK,
          CRC32_IN => CRC32_IN,
          DATA_IN => DATA_IN,
          SAMPLE_CLK_IN => SAMPLE_CLK_IN,
          CRC32_OUT => CRC32_OUT,
          CRC32_VALID => CRC32_VALID
        );
	CRC32_IN <= CRC32_OUT;

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
				if(COUNTER = 31) then
					COUNTER <= (others => '0');
				else
					COUNTER <= COUNTER + 1;
				end if;
			end if;
		end if;
	end process;


	-- CRC32 check at receiver ------------------------------------------------------------
-- append CRC-32 (after inversion)
TX_DATA <= DATA_IN when (COUNTER < 28) else 
			  (not CRC32_OUT(31 downto 24)) when (COUNTER = 28) else
			  (not CRC32_OUT(23 downto 16)) when (COUNTER = 29) else
			  (not CRC32_OUT(15 downto 8)) when (COUNTER = 30) else
			  (not CRC32_OUT(7 downto 0));
			  
-- LSb is sent first
TX_DATA_LSBFIRST(7) <= TX_DATA(0);
TX_DATA_LSBFIRST(6) <= TX_DATA(1);
TX_DATA_LSBFIRST(5) <= TX_DATA(2);
TX_DATA_LSBFIRST(4) <= TX_DATA(3);
TX_DATA_LSBFIRST(3) <= TX_DATA(4);
TX_DATA_LSBFIRST(2) <= TX_DATA(5);
TX_DATA_LSBFIRST(1) <= TX_DATA(6);
TX_DATA_LSBFIRST(0) <= TX_DATA(7);

   crccheck: CRC32_8B PORT MAP (
          SYNC_RESET => SYNC_RESET,
          CLK => CLK,
          CRC32_IN => CRC32B_IN,
          DATA_IN => TX_DATA_LSBFIRST,
          SAMPLE_CLK_IN => SAMPLE_CLK_REF,
          CRC32_OUT => CRC32B_OUT,
          CRC32_VALID => CRC32B_VALID
        );
 
 CRC32B_IN <= CRC32B_OUT;
END;
