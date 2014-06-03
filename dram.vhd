library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity dram is
	port(
		clk	: 	in  std_logic;
		addr	:	in	 unsigned(5 downto 0) := (others => '0');
		din	:	in  unsigned(15 downto 0);
		wen	: 	in	 std_logic;
		dout	:	out unsigned(15 downto 0) := (others => '0')
	);
end dram;

architecture arch of dram is

	subtype ram_word_t is unsigned(15 downto 0); -- RAM word type.
	type ram_t is array (0 to 63) of ram_word_t; -- RAM word array.
	signal ram_r : Ram_t := ((others=> (others=>'0'))); -- RAM declaration.

begin

	process (clk)
	begin
		if (clk'event and clk = '1') then
			if (wen = '1') then
				ram_r(to_integer(addr)) <= din;
			end if;
		end if;
	end process;
	dout <= ram_r(to_integer(addr));

end arch;

