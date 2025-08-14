library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity instruction_cache_memory is
    generic (
        CACHE_LINE_DEPTH : natural;         -- bytes per cache line
        NUMBER_SETS : natural;              -- number of sets
        CACHE_LINES_PER_SET : natural       -- associative lines in every set
    );
    port (
        i_clk : in std_logic;

        i_address_r : in std_logic_vector(f_log2(CACHE_LINE_DEPTH/4)+f_log2(NUMBER_SETS)-1 downto 0);
        i_address_w : in std_logic_vector(f_log2(CACHE_LINE_DEPTH/4)+f_log2(NUMBER_SETS)-1 downto 0);
        i_data : in t_cache_row(0 to CACHE_LINES_PER_SET-1);
        i_write_cache_en : in std_logic;
        i_data_metadata : in t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
        i_write_metadata_en : in std_logic;

        o_row_data : out t_cache_row(0 to CACHE_LINES_PER_SET-1);
        o_row_metadata : out t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0)
    );
end entity;

architecture rtl of instruction_cache_memory is

    -- Types
    type t_instruction_cache is array(0 to CACHE_LINE_DEPTH/4 * NUMBER_SETS - 1) of t_cache_row(0 to CACHE_LINES_PER_SET-1);
    type t_instruction_cache_metadata is array(0 to NUMBER_SETS - 1) of t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    -- Functions
    function f_fill_zeros return t_instruction_cache_metadata is
        variable output : t_instruction_cache_metadata;
    begin
        for i in 0 to output'length - 1 loop
            for j in 0 to output(0)'length - 1 loop
                output(i)(j) := (others => '0');
            end loop;
        end loop;
        
        return output;
    end function;

    -- RAMs
    signal ram_instruction_cache : t_instruction_cache;
    signal ram_instruction_cache_metadata : t_instruction_cache_metadata := f_fill_zeros;

    -- Outputs
    signal row_data_out : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal row_metadata_out : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

begin

    -- Outputs
    o_row_data <= row_data_out;
    o_row_metadata <= row_metadata_out;

    prs_seq : process (i_clk)
    begin
        if rising_edge(i_clk) then
            if i_write_cache_en = '1' then
                ram_instruction_cache(to_integer(unsigned(i_address_w))) <= i_data;
            end if;
            if i_write_metadata_en = '1' then
                ram_instruction_cache_metadata(to_integer(unsigned(i_address_w(i_address_w'length-1 downto f_log2(CACHE_LINE_DEPTH/4))))) <= i_data_metadata;
            end if;

            row_data_out <= ram_instruction_cache(to_integer(unsigned(i_address_r)));
            row_metadata_out <= ram_instruction_cache_metadata(to_integer(unsigned(i_address_r(i_address_r'length-1 downto f_log2(CACHE_LINE_DEPTH/4)))));
        end if;
    end process;

end architecture;