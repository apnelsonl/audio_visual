-- Signals on Pins (IO):
-- Hsync: 6
-- Vsync: 7
-- R: 18
-- G: 17
-- B: 16

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity vga_controller is
	port(
		clk:			in		std_logic;
		adc_miso: 	in 	std_logic;
		adc_mosi: 	out 	std_logic;
		adc_sck: 	out 	std_logic;
		adc_csn:	 	out 	std_logic;
		io: 			out	std_logic_vector (18 downto 0)
	);
end vga_controller;

architecture controller of vga_controller is

	-- vga driver circuit
	component vga_vhdl is
		port(
			clk:			in 	std_logic;
			h_sync:		out 	std_logic;
			v_sync:		out 	std_logic;
			video_on:	out 	std_logic;
			horizontal:	out 	unsigned(9 downto 0);
			vertical:	out	unsigned(9 downto 0)
		);
	end component;
	
	-- ADC provided by micro nova website
	component MercuryADC is
		port(
			-- command input
			clock    : in  std_logic;         -- 50MHz onboard oscillator
			trigger  : in  std_logic;         -- assert to sample ADC
			channel  : in  std_logic_vector(3 downto 0);  -- channel to sample
			-- data output
			Dout     : out std_logic_vector(9 downto 0);  -- data from ADC
			OutVal   : out std_logic;         -- pulsed when data sampled
			-- ADC connection
			adc_miso : in  std_logic;         -- ADC SPI MISO
			adc_mosi : out std_logic;         -- ADC SPI MOSI
			adc_cs   : out std_logic;         -- ADC SPI CHIP SELECT
			adc_clk  : out std_logic          -- ADC SPI CLOCK
		);
	end component;
	
	-- distributed RAM
	component dram is
		port(
			clk	: 	in  std_logic;
			addr	:	in  unsigned(5 downto 0);
			din	:	in  unsigned(15 downto 0);
			wen	: 	in	 std_logic;
			dout	:	out unsigned(15 downto 0)
		);
	end component;
	
	-- intermediate video signals
	signal video_on:	std_logic;
	signal v_sync: 	std_logic;
	signal h_sync:		std_logic;
	signal h_count: 	unsigned(9 downto 0);
	signal v_count: 	unsigned(9 downto 0);
	
	-- intermediate adc signals
	signal adc_count:		unsigned(7 downto 0) := (others => '0');
	signal trigger_tick:	std_logic;
	signal trigger:		std_logic := '0';
	signal dout:			std_logic_vector(9 downto 0);
	signal outval:			std_logic;
	signal colors:			std_logic_vector (7 downto 0);
	
	-- intermediate ram signals
	signal addr1		:	unsigned(5 downto 0);
	signal ram_din1	:	unsigned(15 downto 0);
	signal wen1			: 	std_logic;
	signal ram_dout1	:	unsigned(15 downto 0);
	signal addr2		:	unsigned(5 downto 0);
	signal ram_din2	:	unsigned(15 downto 0);
	signal wen2			: 	std_logic;
	signal ram_dout2	:	unsigned(15 downto 0);
	signal display1	:	std_logic;
	signal display2	:	std_logic;
	type adc_state is (INIT, ADC1, ADC2);
	signal state_a 	: adc_state;
	signal display 	: std_logic_vector(1 downto 0);
	signal write_screen1 : std_logic;
	signal write_screen2 : std_logic;
	
begin

	-- map vga driver to top level signals
	d1: vga_vhdl port map (clk 			=>	clk,
								  h_sync 		=> h_sync,
								  v_sync			=> v_sync,
								  video_on 		=> video_on,
								  horizontal 	=> h_count,
								  vertical 		=> v_count);
								
	-- map adc to top level signals
	d2: MercuryAdc port map (clock 	 => clk,   
									 trigger  => trigger,
									 channel  => "0010", 
									 Dout     => dout,
									 OutVal   => outval,
									 adc_miso => adc_miso,
									 adc_mosi => adc_mosi,
									 adc_cs   => adc_csn,
									 adc_clk  => adc_sck);
	
	-- map ram to top level signals
	r1: dram port map (clk	=>	clk,
							addr	=>	addr1,
							din	=>	ram_din1,
							wen	=>	wen1,
							dout	=>	ram_dout1);
							
	r2: dram port map (clk	=>	clk,
							addr	=>	addr2,
							din	=>	ram_din2,
							wen	=>	wen2,
							dout	=>	ram_dout2);
							
	-- edge detection for adc trigger
	process(clk)
	begin
		if clk'event and clk = '1' then
			adc_count <= adc_count + 1;
			trigger_tick <= adc_count(7);
		end if;
	end process;
	
	-- adc conversion
	trigger <= (not trigger_tick) and adc_count(7);
	
	-- generate color bar
	process(clk)
	begin
		if clk'event and clk = '1' then
			if outval = '1' then
				colors <= dout(8 downto 1);
			end if;
		end if;
	end process;
	
	-- ADC process
	process(clk)
	begin
		if clk'event and clk = '1' then
			case state_a is
				when INIT =>
					wen1 <= '0';
					wen2 <= '0';
					display1 <= '0';
					display2 <= '1';
					addr1 <= (others => '0');
					addr2 <= (others => '0');
					state_a <= ADC1;
				when ADC1 =>
					addr2 <= h_count(8 downto 3);
					if addr1 < 63 and outval = '1' then
						addr1 <= addr1 + 1;
						wen1 <= '1';
						state_a <= ADC1;
					elsif addr1 < 63 and outval = '0' then
						wen1 <= '0';
						state_a <= ADC1;
					else
						wen1 <= '0';
						wen2 <= '0';
						display1 <= '1';
						display2 <= '0';
						addr1 <= (others => '0');
						addr2 <= (others => '0');
						state_a <= ADC2;
					end if;
				when ADC2 =>
					addr1 <= h_count(8 downto 3);
					if addr2 < 63 and outval = '1' then
						addr2 <= addr2 + 1;
						wen2 <= '1';
						state_a <= ADC2;
					elsif addr2 < 63 and outval = '0' then
						wen2 <= '0';
						state_a <= ADC2;
					else
						wen1 <= '0';
						wen2 <= '0';
						display1 <= '0';
						display2 <= '1';
						addr1 <= (others => '0');
						addr2 <= (others => '0');
						state_a <= ADC1;
					end if;
			end case;
		end if;
	end process;
	
	io(6) <= h_sync;
	io(7) <= v_sync;
	
	-- write ram data
	ram_din1 <= unsigned("000000" & dout);
	ram_din2 <= unsigned("000000" & dout);

	-- display ram data through mux
	display <= display2 & display1;
	write_screen1 <= '1' when unsigned(ram_dout1) > v_count
								and  video_on = '1'
								and  h_count < 512
								else '0';
								
	write_screen2 <= '1' when unsigned(ram_dout2) > v_count
								and  video_on = '1'
								and  h_count < 512
								else '0';							
	
	
	with display select
	io(18) <= write_screen1 when "01",
				 write_screen2 when "10",
			    '0'				when others;
	
	
	-- bar of color
	io(15 downto 8) <= colors(7 downto 0) 	when 	v_count > 350
														and	v_count < 450
														and 	video_on = '1'
														else 	(others => '0');
	
	
	io(17 downto 16) <= (others => '0');
	io(5 downto 0) <= (others => '0');

end controller;

