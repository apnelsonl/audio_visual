library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vga_vhdl is
	port(
		clk		  :   in  std_logic;
		h_sync	  :   out std_logic;
		v_sync	  :   out std_logic;
		video_on	  :   out std_logic;
		horizontal :   out unsigned(9 downto 0);
		vertical   :   out unsigned(9 downto 0)
	);
end vga_vhdl;

architecture arch of vga_vhdl is
	-- horizontal 
	constant HD: integer := 640;
	constant HF: integer := 11;
	constant HB: integer := 53;
	constant HR: integer := 96;

	-- vertical
	constant VD: integer := 480;
	constant VF: integer := 7;
	constant VB: integer := 34;
	constant VR: integer := 2;
	
	-- counters
	signal v_count: unsigned(9 downto 0) := (others => '0');
	signal h_count: unsigned(9 downto 0) := (others => '0');
	
	-- signals
	signal h_end: std_logic := '0';
	signal v_end: std_logic := '0';
	
	-- divide clock by 2
	signal clk_div: std_logic := '0';
	
begin

	clock_divide : process (clk)
	begin
		if clk'event and clk = '1' then
			clk_div <= not clk_div;
		end if;
	end process;
	
	h_end <= '1' when h_count=(HD+HF+HB+HR-1) else '0';
	v_end <= '1' when v_count=(VD+VF+VB+VR-1) else '0';
	
	-- determine horizontal
	horizontal_sync : process (clk_div)
	begin
		if clk_div'event and clk_div = '1' then
			if h_end = '1' then
				h_count <= (others => '0');
			else
				h_count <= h_count + 1;
			end if;
		end if;
	end process;
	
	-- determine vertical
	vertical_sync : process (clk_div)
	begin
		if clk_div'event and clk_div = '1' and h_end = '1' then
			if v_end = '1' then
				v_count <= (others => '0');
			else
				v_count <= v_count + 1;
			end if;
		end if;
	end process;
	
	-- output signals
	video_on <= '1' when (h_count < HD) and (v_count < VD) else '0';
	h_sync <= '1' when (h_count >= (HD+HF)) and (h_count <= (HD+HF+HR-1)) else '0';
	v_sync <= '1' when (v_count >= (VD+VF)) and (v_count <= (VD+VF+VR-1)) else '0';
	vertical <= v_count;
	horizontal <= h_count;
	
end arch;

