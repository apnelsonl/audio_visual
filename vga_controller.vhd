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
	
	-- fft block
	COMPONENT fft
	  PORT (
		 clk : IN STD_LOGIC;
		 start : IN STD_LOGIC;
		 unload : IN STD_LOGIC;
		 xn_re : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
		 xn_im : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
		 fwd_inv : IN STD_LOGIC;
		 fwd_inv_we : IN STD_LOGIC;
		 rfd : OUT STD_LOGIC;
		 xn_index : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
		 busy : OUT STD_LOGIC;
		 edone : OUT STD_LOGIC;
		 done : OUT STD_LOGIC;
		 dv : OUT STD_LOGIC;
		 xk_index : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
		 xk_re : OUT STD_LOGIC_VECTOR(16 DOWNTO 0);
		 xk_im : OUT STD_LOGIC_VECTOR(16 DOWNTO 0)
	  );
	END COMPONENT;

	
	-- intermediate video signals
	signal video_on:	std_logic;
	signal v_sync: 	std_logic;
	signal h_sync:		std_logic;
	signal h_count: 	unsigned(9 downto 0);
	signal v_count: 	unsigned(9 downto 0);
	
	-- intermediate adc signals
	signal adc_count:		unsigned(13 downto 0) := (others => '0');
	signal trigger_tick:	std_logic;
	signal trigger:		std_logic;
	signal dout:			std_logic_vector(9 downto 0);
	signal outval:			std_logic;
	signal colors:			std_logic_vector (7 downto 0);
	
	-- intermediate ram signals
	signal addr1		:	unsigned(5 downto 0) := (others => '0');
	signal ram_din1	:	unsigned(15 downto 0) := (others => '0');
	signal wen1			: 	std_logic;
	signal ram_dout1	:	unsigned(15 downto 0) := (others => '0');
	signal addr2		:	unsigned(5 downto 0) := (others => '0');
	signal ram_din2	:	unsigned(15 downto 0) := (others => '0');
	signal wen2			: 	std_logic;
	signal ram_dout2	:	unsigned(15 downto 0) := (others => '0');
	signal display1	:	std_logic;
	signal display2	:	std_logic;
	type top_state is (S_INIT, S_TOP_1, S_TOP_2);
	type sub_state is (S_ADC, S_FFT_LOAD, S_FFT_UNLOAD, S_WAIT);
	signal state_t		: top_state;
	signal state_s		: sub_state;
	signal display 	: std_logic_vector(1 downto 0);
	signal write_screen1 : std_logic;
	signal write_screen2 : std_logic;
	
	-- fft signals
	 signal start : STD_LOGIC := '0';
	 signal unload :STD_LOGIC := '0';
	 signal xn_re : STD_LOGIC_VECTOR(9 DOWNTO 0);
	 signal xn_im : STD_LOGIC_VECTOR(9 DOWNTO 0);
	 signal fwd_inv : STD_LOGIC;
	 signal fwd_inv_we : STD_LOGIC;
	 signal rfd : STD_LOGIC;
	 signal xn_index : STD_LOGIC_VECTOR(5 DOWNTO 0);
	 signal busy : STD_LOGIC;
	 signal edone : STD_LOGIC;
	 signal done : STD_LOGIC;
	 signal dv : STD_LOGIC;
	 signal xk_index : STD_LOGIC_VECTOR(5 DOWNTO 0);
	 signal xk_re : STD_LOGIC_VECTOR(16 DOWNTO 0);
	 signal xk_im : STD_LOGIC_VECTOR(16 DOWNTO 0);
	 
	 -- signals for fft and adc sharing ram
	 signal adc_addr1		:	unsigned(5 downto 0) := (others => '0');
	 signal adc_addr2		:	unsigned(5 downto 0) := (others => '0');
	 signal fft_addr1		:	unsigned(5 downto 0);
	 signal fft_addr2		:	unsigned(5 downto 0);
	 signal adc_fft_sel1	:	std_logic;
	 signal adc_fft_sel2	:	std_logic;
	 signal fft_mux_sel	:	std_logic_vector(1 downto 0);
	 signal fft_unload1	:	std_logic := '0';
	 signal fft_unload2	:	std_logic := '0';
	 signal fft_rw_sel1	:	std_logic_vector(1 downto 0);
	 signal fft_rw_sel2	:	std_logic_vector(1 downto 0);
	 signal test_input	:	unsigned(15 downto 0);
	 
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
							
	-- fft mapping
	fft1 : fft PORT MAP (
    clk => clk,
    start => start,
    unload => unload,
    xn_re => xn_re,
    xn_im => xn_im,
    fwd_inv => fwd_inv,
    fwd_inv_we => fwd_inv_we,
    rfd => rfd,
    xn_index => xn_index,
    busy => busy,
    edone => edone,
    done => done,
    dv => dv,
    xk_index => xk_index,
    xk_re => xk_re,
    xk_im => xk_im
  );
							
	-- edge detection for adc trigger
	process(clk)
	begin
		if clk'event and clk = '1' then
			adc_count <= adc_count + 1;
			trigger_tick <= adc_count(13);
		end if;
	end process;
	
	-- adc conversion
	trigger <= (not trigger_tick) and adc_count(13);
	
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
			case state_t is
				when S_INIT =>
					start <= '0';
					unload <= '0';
					fft_unload1 <= '0';
					fft_unload2 <= '0';
					display1 <= '0';
					display2 <= '1';
					adc_addr1 <= (others => '0');
					adc_addr2 <= (others => '0');
					adc_fft_sel1 <= '0';
					adc_fft_sel2 <= '0';
					state_t <= S_TOP_1;
					state_s <= S_ADC;
				-- sample RAM_IN_1 then FFT RAM_IN_1 while diplaying RAM_OUT_2 values
				when S_TOP_1 =>
					adc_addr2 <= h_count(8 downto 3);
					case state_s is
						when S_ADC =>
							if adc_addr1 < 63 and outval = '1' then
								adc_addr1 <= adc_addr1 + 1;
								state_t <= S_TOP_1;
								state_s <= S_ADC;
							elsif adc_addr1 <= 63 and outval = '0' then
								state_t <= S_TOP_1;
								state_s <= S_ADC;
							elsif adc_addr1 = 63 and outval = '1' then
								state_t <= S_TOP_1;
								state_s <= S_FFT_LOAD;
							else
								state_t <= S_INIT;
								state_s <= S_ADC;
							end if;
						when S_FFT_LOAD =>
							start <= '1';
							adc_fft_sel1 <= '1';
							if edone = '1' then
								start <= '0';
								state_t <= S_TOP_1;
								state_s <= S_FFT_UNLOAD;
							else
								state_t <= S_TOP_1;
								state_s <= S_FFT_LOAD;
							end if;
						when S_FFT_UNLOAD =>
							unload <= '1';
							fft_unload1 <= '1';
							if unsigned(xk_index) < 63 then
								state_t <= S_TOP_1;
								state_s <= S_FFT_UNLOAD;
							else
								unload <= '0';
								state_t <= S_TOP_1;
								state_s <= S_WAIT;
							end if;
						when S_WAIT =>
							if v_count = 0 then
								fft_unload2 <= '0';
								adc_fft_sel2 <= '0';
								fft_unload1 <= '1';
								adc_fft_sel1 <= '0';
								display1 <= '1';
								display2 <= '0';
								adc_addr1 <= h_count(8 downto 3);
								adc_addr2 <= (others => '0');
								state_t <= S_TOP_2;
								state_s <= S_ADC;
							else
								state_t <= S_TOP_1;
								state_s <= S_WAIT;
							end if;
						when others =>
							state_t <= S_INIT;
							state_s <= S_ADC;
					end case;
				-- sample RAM_IN_2 then FFT RAM_IN_2 while diplaying RAM_OUT_1 values
				when S_TOP_2 =>
					adc_addr1 <= h_count(8 downto 3);
					case state_s is
						when S_ADC =>
							if adc_addr2 < 63 and outval = '1' then
								adc_addr2 <= adc_addr2 + 1;
								state_t <= S_TOP_2;
								state_s <= S_ADC;
							elsif adc_addr2 <= 63 and outval = '0' then
								state_t <= S_TOP_2;
								state_s <= S_ADC;
							elsif adc_addr2 = 63 and outval = '1' then
								state_t <= S_TOP_2;
								state_s <= S_FFT_LOAD;
							else
								state_t <= S_INIT;
								state_s <= S_ADC;
							end if; 
						when S_FFT_LOAD =>
							start <= '1';
							adc_fft_sel2 <= '1';
							if edone = '1' then
								start <= '0';
								state_t <= S_TOP_2;
								state_s <= S_FFT_UNLOAD;
							else
								state_t <= S_TOP_2;
								state_s <= S_FFT_LOAD;
							end if;
						when S_FFT_UNLOAD =>
							unload <= '1';
							fft_unload2 <= '1';
							if unsigned(xk_index) < 63 then
								state_t <= S_TOP_2;
								state_s <= S_FFT_UNLOAD;
							else
								unload <= '0';
								state_t <= S_TOP_2;
								state_s <= S_WAIT;
							end if;
						when S_WAIT =>
							if v_count = 0 then
								fft_unload1 <= '0';
								adc_fft_sel1 <= '0';
								fft_unload2 <= '1';
								adc_fft_sel2 <= '0';
								display1 <= '0';
								display2 <= '1';
								adc_addr1 <= (others => '0');
								adc_addr2 <= h_count(8 downto 3);
								state_t <= S_TOP_1;
								state_s <= S_ADC;
							else
								state_t <= S_TOP_2;
								state_s <= S_WAIT;
							end if;
						when others =>
							state_t <= S_INIT;
							state_s <= S_ADC;
					end case;
				when others =>
					state_t <= S_INIT;
					state_s <= S_ADC;
			end case;
		end if;
	end process;
	
	io(6) <= h_sync;
	io(7) <= v_sync;
	
	-- assign fft signals
	fft_addr1 <= unsigned(xn_index);
	fft_addr2 <= unsigned(xn_index);
	fwd_inv <= '1';
	fwd_inv_we <= '1';
	fft_rw_sel1 <= adc_fft_sel1 & fft_unload1;
	fft_rw_sel2 <= adc_fft_sel2 & fft_unload2;
	

	-- assign fft input values as ram1 or ram2
	fft_mux_sel <= adc_fft_sel2 & adc_fft_sel1;
	with fft_mux_sel select
		xn_re <= std_logic_vector(ram_dout1(9 downto 0)) when "01",
					std_logic_vector(ram_dout2(9 downto 0)) when "10",
					(others => '0') when others;
	xn_im <= (others => '0');
	
	-- select between adc and fft ram addresses
	with fft_rw_sel1 select
		addr1 <= adc_addr1 				when "00",
					h_count(8 downto 3)	when "01",
					fft_addr1				when "10",
					unsigned(xk_index) 	when "11",
					(others => '0')		when others;
	with fft_rw_sel2 select
		addr2 <= adc_addr2 				when "00",
					h_count(8 downto 3)	when "01",
					fft_addr2				when "10",
					unsigned(xk_index) 	when "11",
					(others => '0')		when others;
	
	-- write ram data
	wen1 <= '1' when	(outval = '1' and state_t = S_TOP_1)
					or		(unload = '1' and state_t = S_TOP_1)
					else	'0';
	wen2 <= '1' when	(outval = '1' and state_t = S_TOP_2)
					or		(unload = '1' and state_t = S_TOP_2)
					else	'0';
					
	-- input to ram (normally dout)
	test_input <= "0000000111010110";
	ram_din1 <= unsigned("0000" & xk_re(16 downto 5)) when unload = '1' else unsigned("0000000" & dout(9 downto 1));
	ram_din2 <= unsigned("0000" & xk_re(16 downto 5)) when unload = '1' else unsigned("0000000" & dout(9 downto 1));

	-- display ram data through mux
	display <= display2 & display1;
	write_screen1 <= '1' when 10*unsigned(ram_dout1(9 downto 0)) > v_count
								and  unsigned(ram_dout1(9 downto 0)) < 700
								and  addr1 > 0
								and  video_on = '1'
								and  h_count < 512
								else '0';
								
	write_screen2 <= '1' when 10*unsigned(ram_dout2(9 downto 0)) > 3*v_count
								and  addr2 > 0
								and  unsigned(ram_dout2(9 downto 0)) < 700
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

