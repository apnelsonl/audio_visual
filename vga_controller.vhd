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
	signal addr			:	unsigned(5 downto 0);
	signal ram_din		:	unsigned(15 downto 0);
	signal wen			: 	std_logic;
	signal ram_dout	:	unsigned(15 downto 0);
	
	-- fsm signals
	type state_type is (INIT,DRAW,RAM_WRITE);
	signal state : state_type;
	signal d_addr : unsigned(5 downto 0);
	signal w_addr : unsigned(5 downto 0);
	signal display: std_logic;

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
	d3: dram port map (clk	=>	clk,
							addr	=>	addr,
							din	=>	ram_din,
							wen	=>	wen,
							dout	=>	ram_dout);
							
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
	
	process(clk)
	begin
		if clk'event and clk = '1' then
			if outval = '1' then
				colors <= dout(8 downto 1);
			end if;
		end if;
	end process;
	
	-- synchronous state machine
	state_machine: process(clk)
	begin
		if clk'event and clk = '1' then
			case state is
				-- INIT state when button is pressed
				when INIT =>
					d_addr <= (others => '0');
					w_addr <= (others => '0');
					display <= '1';
					wen <= '0';
					addr <= d_addr;
					state <= DRAW;	
				-- draws data on screen with io(18)
				when DRAW =>
					d_addr <= h_count(8 downto 3);
					addr <= d_addr;
					if outval = '1' then
						display <= '0';
						wen <= '1';
						addr <= w_addr;
						state <= RAM_WRITE;
					else
						wen <= '0';
						state <= DRAW;
					end if;
				-- RAM_WRITE steps through ram and writes value of adc conversion when adc is sampled
				when RAM_WRITE =>
					if w_addr < 63 then
						w_addr <= w_addr + 1;
					else
						w_addr <= (others => '0');
					end if;
					display <= '1';
					addr <= d_addr;
					wen <= '0';
					state <= DRAW;
				when others => -- the catch-all condition
					state <= INIT; 
			end case;
		end if;
	end process state_machine;
	
	io(6) <= h_sync;
	io(7) <= v_sync;
	
	-- write ram data
	ram_din <= unsigned("000000" & dout);
	
	-- display ram data
	io(18) <= '1' when display = '1'
					  and  unsigned(ram_dout) > v_count 
					  and  video_on = '1'
					  and  h_count < 512  
					  else '0';
	
	
	-- bar of color
	io(15 downto 8) <= colors(7 downto 0) 	when 	v_count > 350
														and	v_count < 450
														and 	video_on = '1'
														else 	(others => '0');
	
	
	io(17 downto 16) <= (others => '0');
	io(5 downto 0) <= (others => '0');

end controller;

