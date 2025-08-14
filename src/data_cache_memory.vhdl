library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity data_cache_memory is
    generic (
        CACHE_LINE_DEPTH : natural;         -- bytes per cache line
        NUMBER_SETS : natural;              -- number of sets
        CACHE_LINES_PER_SET : natural       -- associative lines in every set
    );
    port (
        i_clk : in std_logic;

        i_address_r : in std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
        i_address_w : in std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
        i_data : in t_cache_row(0 to CACHE_LINES_PER_SET-1);
        i_write_cache_en : in std_logic;
        i_data_metadata : in t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
        i_write_metadata_en : in std_logic;

        o_row_data : out t_cache_row(0 to CACHE_LINES_PER_SET-1);
        o_row_metadata : out t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0)
    );
end entity;

architecture rtl of data_cache_memory is

    -- Types
    type t_data_cache_block_row is array(0 to CACHE_LINES_PER_SET-1) of std_logic_vector(7 downto 0);
    type t_data_cache_block is array(0 to CACHE_LINE_DEPTH/4 * NUMBER_SETS - 1) of t_data_cache_block_row;
    type t_data_cache_metadata is array(0 to NUMBER_SETS - 1) of t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    -- Functions
    function f_fill_zeros return t_data_cache_metadata is
        variable output : t_data_cache_metadata;
    begin
        for i in 0 to output'length - 1 loop
            for j in 0 to output(0)'length - 1 loop
                output(i)(j) := (others => '0');
            end loop;
        end loop;
        
        return output;
    end function;

    -- Registers
    signal r_addr_reg : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);

    -- RAMs
    signal ram_data_cache_block_1 : t_data_cache_block;
    signal ram_data_cache_block_2 : t_data_cache_block;
    signal ram_data_cache_block_3 : t_data_cache_block;
    signal ram_data_cache_block_4 : t_data_cache_block;
    signal ram_data_cache_metadata : t_data_cache_metadata := f_fill_zeros;

    signal block1_in : t_data_cache_block_row;
    signal block2_in : t_data_cache_block_row;
    signal block3_in : t_data_cache_block_row;
    signal block4_in : t_data_cache_block_row;

    signal block1_out : t_data_cache_block_row;
    signal block2_out : t_data_cache_block_row;
    signal block3_out : t_data_cache_block_row;
    signal block4_out : t_data_cache_block_row;

    -- Outputs
    signal row_data_out : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal row_metadata_out : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    -- Misc
    signal r_addr_plus_one : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-3 downto 0);     -- address used to access blocks when input address is not word-aligned
    signal w_addr_plus_one : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-3 downto 0);     -- address used to access blocks when input address is not word-aligned

begin

    -- Outputs
    o_row_data <= row_data_out;
    o_row_metadata <= row_metadata_out;

    -- Misc
    r_addr_plus_one <= std_logic_vector(unsigned(i_address_r(i_address_r'length-1 downto 2)) + 1);
    w_addr_plus_one <= std_logic_vector(unsigned(i_address_w(i_address_w'length-1 downto 2)) + 1);

    prs_seq : process (i_clk)
    begin
        if rising_edge(i_clk) then
            if i_write_cache_en = '1' then
                -- Block 1 input
                if i_address_w(1 downto 0) = "00" then
                    ram_data_cache_block_1(to_integer(unsigned(i_address_w(i_address_w'length-1 downto 2)))) <= block1_in;
                else
                    ram_data_cache_block_1(to_integer(unsigned(w_addr_plus_one))) <= block1_in;
                end if;
                -- Block 2 input
                if i_address_w(1) = '0' then
                    ram_data_cache_block_2(to_integer(unsigned(i_address_w(i_address_w'length-1 downto 2)))) <= block2_in;
                else
                    ram_data_cache_block_2(to_integer(unsigned(w_addr_plus_one))) <= block2_in;
                end if;
                -- Block 3 input
                if i_address_w(1 downto 0) /= "11" then
                    ram_data_cache_block_3(to_integer(unsigned(i_address_w(i_address_w'length-1 downto 2)))) <= block3_in;
                else
                    ram_data_cache_block_3(to_integer(unsigned(w_addr_plus_one))) <= block3_in;
                end if;
                -- Block 4 input
                ram_data_cache_block_4(to_integer(unsigned(i_address_w(i_address_w'length-1 downto 2)))) <= block4_in;
            end if;
            if i_write_metadata_en = '1' then
                ram_data_cache_metadata(to_integer(unsigned(i_address_w(i_address_w'length-1 downto f_log2(CACHE_LINE_DEPTH))))) <= i_data_metadata;
            end if;

            row_metadata_out <= ram_data_cache_metadata(to_integer(unsigned(i_address_r(i_address_r'length-1 downto f_log2(CACHE_LINE_DEPTH)))));

            -- Block 1 output
            if i_address_r(1 downto 0) = "00" then
                block1_out <= ram_data_cache_block_1(to_integer(unsigned(i_address_r(i_address_r'length-1 downto 2))));
            else
                block1_out <= ram_data_cache_block_1(to_integer(unsigned(r_addr_plus_one)));
            end if;
            -- Block 2 output
            if i_address_r(1) = '0' then
                block2_out <= ram_data_cache_block_2(to_integer(unsigned(i_address_r(i_address_r'length-1 downto 2))));
            else
                block2_out <= ram_data_cache_block_2(to_integer(unsigned(r_addr_plus_one)));
            end if;
            -- Block 3 output
            if i_address_r(1 downto 0) /= "11" then
                block3_out <= ram_data_cache_block_3(to_integer(unsigned(i_address_r(i_address_r'length-1 downto 2))));
            else
                block3_out <= ram_data_cache_block_3(to_integer(unsigned(r_addr_plus_one)));
            end if;
            -- Block 4 output
            block4_out <= ram_data_cache_block_4(to_integer(unsigned(i_address_r(i_address_r'length-1 downto 2))));

            -- Address register
            r_addr_reg <= i_address_r;
        end if;
    end process;

    prs_input : process(all)
    begin
        for i in 0 to CACHE_LINES_PER_SET-1 loop
            case i_address_w(1 downto 0) is
                when "00" =>
                    block1_in(i) <= i_data(i)(31 downto 24);
                    block2_in(i) <= i_data(i)(23 downto 16);
                    block3_in(i) <= i_data(i)(15 downto 8);
                    block4_in(i) <= i_data(i)(7 downto 0);

                when "01" =>
                    block2_in(i) <= i_data(i)(31 downto 24);
                    block3_in(i) <= i_data(i)(23 downto 16);
                    block4_in(i) <= i_data(i)(15 downto 8);
                    block1_in(i) <= i_data(i)(7 downto 0);

                when "10" =>
                    block3_in(i) <= i_data(i)(31 downto 24);
                    block4_in(i) <= i_data(i)(23 downto 16);
                    block1_in(i) <= i_data(i)(15 downto 8);
                    block2_in(i) <= i_data(i)(7 downto 0);

                when "11" =>
                    block4_in(i) <= i_data(i)(31 downto 24);
                    block1_in(i) <= i_data(i)(23 downto 16);
                    block2_in(i) <= i_data(i)(15 downto 8);
                    block3_in(i) <= i_data(i)(7 downto 0);

                when others =>      -- should never happen, but just for completeness
                    block1_in(i) <= (others => '0');
                    block2_in(i) <= (others => '0');
                    block3_in(i) <= (others => '0');
                    block4_in(i) <= (others => '0');
            end case;
        end loop;
    end process;

    prs_output : process(all)
    begin
        for i in 0 to CACHE_LINES_PER_SET-1 loop
            case r_addr_reg(1 downto 0) is
                when "00" =>
                    row_data_out(i)(31 downto 24)   <= block1_out(i);
                    row_data_out(i)(23 downto 16)   <= block2_out(i);
                    row_data_out(i)(15 downto 8)    <= block3_out(i);
                    row_data_out(i)(7 downto 0)     <= block4_out(i);

                when "01" =>
                    row_data_out(i)(31 downto 24)   <= block2_out(i);
                    row_data_out(i)(23 downto 16)   <= block3_out(i);
                    row_data_out(i)(15 downto 8)    <= block4_out(i);
                    row_data_out(i)(7 downto 0)     <= block1_out(i);

                when "10" =>
                    row_data_out(i)(31 downto 24)   <= block3_out(i);
                    row_data_out(i)(23 downto 16)   <= block4_out(i);
                    row_data_out(i)(15 downto 8)    <= block1_out(i);
                    row_data_out(i)(7 downto 0)     <= block2_out(i);

                when "11" =>
                    row_data_out(i)(31 downto 24)   <= block4_out(i);
                    row_data_out(i)(23 downto 16)   <= block1_out(i);
                    row_data_out(i)(15 downto 8)    <= block2_out(i);
                    row_data_out(i)(7 downto 0)     <= block3_out(i);

                when others =>      -- should never happen, but just for completeness
                    row_data_out(i) <= (others => '0');
            end case;
        end loop;
    end process;

end architecture;