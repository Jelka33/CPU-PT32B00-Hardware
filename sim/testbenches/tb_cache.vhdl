library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity tb_cache is
end entity;

architecture behavioural of tb_cache is

    constant ClkPeriod : time := 1000 ns;
    signal SimEnded : std_logic := '0';

    -- FOR THE DUT1 --

    constant CACHE_LINE_DEPTH : natural := 16;
    constant NUMBER_SETS : natural := 4;
    constant CACHE_LINES_PER_SET : natural := 4;

    signal i_clk   : std_logic := '0';
    signal i_reset : std_logic;

    -- from memory manager
    signal i_address : std_logic_vector(31 downto 0);
    signal i_write_data : unsigned(31 downto 0);
    signal i_request : std_logic;
    signal i_write_en : std_logic;
    signal i_ram_en : std_logic;
    signal i_data_fetch_en : std_logic;

    -- from cache memory
    signal i_cache_row_data : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal i_cache_row_metadata : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    -- from outside
    signal i_fetch_data : unsigned(31 downto 0);
    signal i_memory_rdy : std_logic;

    -- to memory manager
    signal o_fetch_data : unsigned(31 downto 0);
    signal o_cache_rdy : std_logic;

    -- to cache memory
    signal o_cache_address_r : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
    signal o_cache_address_w : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
    signal o_cache_data : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal o_cache_write_en : std_logic;
    signal o_cache_data_metadata : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
    signal o_cache_write_metadata_en : std_logic;

    -- to outside
    signal o_address : std_logic_vector(31 downto 0);
    signal o_write_data : unsigned(31 downto 0);
    signal o_request : std_logic;
    signal o_write_en : std_logic;
    signal o_ram_en : std_logic;

    -- FOR THE DUT2 --
    signal inst_cache_row_data : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal inst_cache_row_metadata : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
    signal inst_cache_write_en : std_logic;
    signal inst_cache_write_metadata_en : std_logic;

    -- FOR THE DUT3 --
    signal data_cache_row_data : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal data_cache_row_metadata : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
    signal data_cache_write_en : std_logic;
    signal data_cache_write_metadata_en : std_logic;

begin

    dut1 : entity work.cache_controller(rtl)
     generic map(
        CACHE_LINE_DEPTH => CACHE_LINE_DEPTH,
        NUMBER_SETS => NUMBER_SETS,
        CACHE_LINES_PER_SET => CACHE_LINES_PER_SET
    )
     port map(
        i_clk => i_clk,
        i_reset => i_reset,

        i_address => i_address,
        i_write_data => i_write_data,
        i_request => i_request,
        i_write_en => i_write_en,
        i_ram_en => i_ram_en,
        i_data_fetch_en => i_data_fetch_en,

        i_cache_row_data => i_cache_row_data,
        i_cache_row_metadata => i_cache_row_metadata,

        i_fetch_data => i_fetch_data,
        i_memory_rdy => i_memory_rdy,

        o_fetch_data => o_fetch_data,
        o_cache_rdy => o_cache_rdy,

        o_cache_address_r => o_cache_address_r,
        o_cache_address_w => o_cache_address_w,
        o_cache_data => o_cache_data,
        o_cache_write_en => o_cache_write_en,
        o_cache_data_metadata => o_cache_data_metadata,
        o_cache_write_metadata_en => o_cache_write_metadata_en,

        o_address => o_address,
        o_write_data => o_write_data,
        o_request => o_request,
        o_write_en => o_write_en,
        o_ram_en => o_ram_en
    );

    dut2 : entity work.instruction_cache_memory(rtl)
     generic map(
        CACHE_LINE_DEPTH => CACHE_LINE_DEPTH,
        NUMBER_SETS => NUMBER_SETS,
        CACHE_LINES_PER_SET => CACHE_LINES_PER_SET
    )
     port map(
        i_clk => i_clk,
        i_address_r => o_cache_address_r(o_cache_address_r'length-1 downto 2),
        i_address_w => o_cache_address_w(o_cache_address_w'length-1 downto 2),
        i_data => o_cache_data,
        i_write_cache_en => inst_cache_write_en,
        i_data_metadata => o_cache_data_metadata,
        i_write_metadata_en => inst_cache_write_metadata_en,
        o_row_data => inst_cache_row_data,
        o_row_metadata => inst_cache_row_metadata
    );

    dut3 : entity work.data_cache_memory(rtl)
     generic map(
        CACHE_LINE_DEPTH => CACHE_LINE_DEPTH,
        NUMBER_SETS => NUMBER_SETS,
        CACHE_LINES_PER_SET => CACHE_LINES_PER_SET
    )
     port map(
        i_clk => i_clk,
        i_address_r => o_cache_address_r,
        i_address_w => o_cache_address_w,
        i_data => o_cache_data,
        i_write_cache_en => data_cache_write_en,
        i_data_metadata => o_cache_data_metadata,
        i_write_metadata_en => data_cache_write_metadata_en,
        o_row_data => data_cache_row_data,
        o_row_metadata => data_cache_row_metadata
    );

    i_cache_row_data <= inst_cache_row_data when i_data_fetch_en = '0' else data_cache_row_data;
    i_cache_row_metadata <= inst_cache_row_metadata when i_data_fetch_en = '0' else data_cache_row_metadata;
    inst_cache_write_en <= o_cache_write_en when i_data_fetch_en = '0' else '0';
    inst_cache_write_metadata_en <= o_cache_write_metadata_en when i_data_fetch_en = '0' else '0';
    data_cache_write_en <= o_cache_write_en when i_data_fetch_en = '1' else '0';
    data_cache_write_metadata_en <= o_cache_write_metadata_en when i_data_fetch_en = '1' else '0';

    -- Clock
    i_clk <= not i_clk after ClkPeriod/2 when SimEnded /= '1' else '0';

    stimuli : process
    begin
        wait for ClkPeriod / 2;

        -- Reset
        i_reset <= '1';
        i_address <= (others => '0');
        i_write_data <= (others => '0');
        i_request <= '0';
        i_ram_en <= '0';
        i_write_en <= '0';
        i_data_fetch_en <= '0';
        i_fetch_data <= (others => '0');
        i_memory_rdy <= '0';
        i_memory_rdy <= '0';
        wait for 5 * ClkPeriod;
        i_reset <= '0';

        -- 1st access
        -- i_address <= (others => '0');
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 1 to CACHE_LINE_DEPTH/4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 2nd access
        -- i_address <= std_logic_vector(TO_UNSIGNED(4, i_address'length));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 3rd access
        -- i_address <= std_logic_vector(TO_UNSIGNED(1, i_address'length - f_log2(CACHE_LINE_DEPTH))) & std_logic_vector(TO_UNSIGNED(8, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in CACHE_LINE_DEPTH/4 downto 1 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 4th access
        -- i_address <= std_logic_vector(TO_UNSIGNED(1, i_address'length - f_log2(CACHE_LINE_DEPTH))) & std_logic_vector(TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 5th access
        -- i_address <= std_logic_vector(TO_UNSIGNED(123, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS))) & std_logic_vector(TO_UNSIGNED(12, f_log2(CACHE_LINE_DEPTH) + f_log2(NUMBER_SETS)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 2 to CACHE_LINE_DEPTH/4 + 1 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 6th access
        -- i_address <= std_logic_vector(TO_UNSIGNED(1234, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS))) & std_logic_vector(TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH) + f_log2(NUMBER_SETS)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 3 to CACHE_LINE_DEPTH/4 + 2 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 7th access
        -- i_address <= std_logic_vector(TO_UNSIGNED(12345, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS))) & std_logic_vector(TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH) + f_log2(NUMBER_SETS)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 4 to CACHE_LINE_DEPTH/4 + 3 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 8th access
        -- i_address <= std_logic_vector(TO_UNSIGNED(1, i_address'length - f_log2(CACHE_LINE_DEPTH))) & std_logic_vector(TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 9th access
        -- i_address <= (others => '0');
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 10th access
        -- i_address <= std_logic_vector(TO_UNSIGNED(100, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS))) & std_logic_vector(TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH) + f_log2(NUMBER_SETS)));
        -- i_request <= '1';
        -- i_ram_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 5 to CACHE_LINE_DEPTH/4 + 4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 11th access
        -- i_address <= std_logic_vector(to_unsigned(1, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS)) & TO_UNSIGNED(1, f_log2(NUMBER_SETS)) & TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';
        -- i_write_data <= to_unsigned(51, i_write_data'length);
        -- i_write_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 5 to CACHE_LINE_DEPTH/4 + 4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 12th access
        -- i_address <= std_logic_vector(to_unsigned(2, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS)) & TO_UNSIGNED(1, f_log2(NUMBER_SETS)) & TO_UNSIGNED(4, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';
        -- i_write_data <= to_unsigned(51, i_write_data'length);
        -- i_write_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 5 to CACHE_LINE_DEPTH/4 + 4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 13th access
        -- i_address <= std_logic_vector(to_unsigned(3, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS)) & TO_UNSIGNED(1, f_log2(NUMBER_SETS)) & TO_UNSIGNED(8, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';
        -- i_write_data <= to_unsigned(51, i_write_data'length);
        -- i_write_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 5 to CACHE_LINE_DEPTH/4 + 4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 14th access
        -- i_address <= std_logic_vector(to_unsigned(4, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS)) & TO_UNSIGNED(1, f_log2(NUMBER_SETS)) & TO_UNSIGNED(12, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';
        -- i_write_data <= to_unsigned(51, i_write_data'length);
        -- i_write_en <= '1';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 5 to CACHE_LINE_DEPTH/4 + 4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- -- 15th access
        -- i_address <= std_logic_vector(to_unsigned(5, i_address'length - f_log2(CACHE_LINE_DEPTH) - f_log2(NUMBER_SETS)) & TO_UNSIGNED(1, f_log2(NUMBER_SETS)) & TO_UNSIGNED(4, f_log2(CACHE_LINE_DEPTH)));
        -- i_request <= '1';
        -- i_ram_en <= '1';
        -- i_write_data <= TO_UNSIGNED(0, i_write_data'length);
        -- i_write_en <= '0';

        -- i_memory_rdy <= '1';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '0';

        -- wait for 2 * ClkPeriod;

        -- i_memory_rdy <= '1';

        -- for i in 0 to CACHE_LINE_DEPTH/4 - 1 loop
        --     i_memory_rdy <= '1';
        --     wait for ClkPeriod;

        --     i_memory_rdy <= '0';
        --     wait for ClkPeriod;
        -- end loop;

        -- for i in 5 to CACHE_LINE_DEPTH/4 + 4 loop
        --     i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
        --     i_memory_rdy <= '1';

        --     wait for ClkPeriod;

        --     i_fetch_data <= (others => '0');
        --     i_memory_rdy <= '0';

        --     wait for ClkPeriod;
        -- end loop;

        -- i_request <= '0';

        -- wait for 10 * ClkPeriod;

        -- data cache
        i_data_fetch_en <= '1';
        -- 16th access
        i_address <= std_logic_vector(TO_UNSIGNED(0, i_address'length));
        i_request <= '1';
        i_ram_en <= '1';

        i_memory_rdy <= '1';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '0';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '1';

        for i in 1 to CACHE_LINE_DEPTH/4 loop
            i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length);
            i_memory_rdy <= '1';

            wait for ClkPeriod;

            i_fetch_data <= (others => '0');
            i_memory_rdy <= '0';

            wait for ClkPeriod;
        end loop;

        i_request <= '0';

        wait for 10 * ClkPeriod;

        -- 17th access
        i_address <= std_logic_vector(TO_UNSIGNED(1, i_address'length-f_log2(CACHE_LINE_DEPTH)) & TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH)));
        i_request <= '1';
        i_ram_en <= '1';

        i_memory_rdy <= '1';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '0';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '1';

        for i in 2 to CACHE_LINE_DEPTH/4 + 1 loop
            i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length/2) & TO_UNSIGNED(i, i_fetch_data'length/2);
            i_memory_rdy <= '1';

            wait for ClkPeriod;

            i_fetch_data <= (others => '0');
            i_memory_rdy <= '0';

            wait for ClkPeriod;
        end loop;

        i_request <= '0';

        wait for 10 * ClkPeriod;

        -- 18th access
        i_address <= std_logic_vector(TO_UNSIGNED(0, i_address'length-f_log2(CACHE_LINE_DEPTH)) & TO_UNSIGNED(2 ** f_log2(CACHE_LINE_DEPTH) -1, f_log2(CACHE_LINE_DEPTH)));
        i_request <= '1';
        i_ram_en <= '1';
        i_write_en <= '1';
        i_write_data <= (others => '1');

        i_memory_rdy <= '1';

        wait for 3 * ClkPeriod;

        i_request <= '0';
        i_write_en <= '0';

        wait for 10 * ClkPeriod;

        -- 19th access
        i_address <= std_logic_vector(TO_UNSIGNED(1, i_address'length-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)) & TO_UNSIGNED(0, f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)));
        i_request <= '1';
        i_ram_en <= '1';

        i_memory_rdy <= '1';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '0';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '1';

        for i in 1 to CACHE_LINE_DEPTH/4 loop
            i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length/2) & TO_UNSIGNED(i, i_fetch_data'length/2);
            i_memory_rdy <= '1';

            wait for ClkPeriod;

            i_fetch_data <= (others => '0');
            i_memory_rdy <= '0';

            wait for ClkPeriod;
        end loop;

        i_request <= '0';

        wait for 10 * ClkPeriod;

        -- 20th access
        i_address <= std_logic_vector(TO_UNSIGNED(1, i_address'length-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)) & TO_UNSIGNED(2 ** f_log2(CACHE_LINE_DEPTH) -2, f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)));
        i_request <= '1';
        i_ram_en <= '1';
        i_write_en <= '1';

        i_memory_rdy <= '1';

        wait for 2 * ClkPeriod;

        i_memory_rdy <= '0';

        wait for 3 * ClkPeriod;

        i_memory_rdy <= '1';

        for i in 2 to CACHE_LINE_DEPTH/4 + 1 loop
            i_fetch_data <= TO_UNSIGNED(i, i_fetch_data'length/2) + 1000 & TO_UNSIGNED(i, i_fetch_data'length/2);
            i_memory_rdy <= '1';

            wait for ClkPeriod;

            i_fetch_data <= (others => '0');
            i_memory_rdy <= '0';

            wait for ClkPeriod;
        end loop;

        i_request <= '0';
        i_write_en <= '0';

        wait for 10 * ClkPeriod;

        -- End the simulation
        SimEnded <= '1';

        wait for 10 * ClkPeriod;

        report "Simulation Ended" severity failure;
    end process;

end architecture;
