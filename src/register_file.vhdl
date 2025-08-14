library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity register_file is
    port (
        i_clk   : in std_logic;
        i_reset : in std_logic;
        
        i_write_data : in unsigned(31 downto 0);
        i_sel_reg_a : in unsigned(3 downto 0);
        i_sel_reg_b : in unsigned(3 downto 0);
        i_sel_reg_w : in unsigned(3 downto 0);
        i_write_reg_en : in std_logic;

        o_reg_a : out unsigned(31 downto 0);
        o_reg_b : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of register_file is

    type t_registers_array is array (0 to 15) of unsigned(31 downto 0);
    signal registers : t_registers_array;
    signal registers_next : t_registers_array;
    
begin

    prs_seq : process (i_clk, i_reset)
    begin
        if i_reset = '1' then
            registers <= (others => (others => '0'));
        elsif rising_edge(i_clk) then
            registers <= registers_next;
        end if;
    end process;

    prs_comb : process (all)
    begin
        registers_next <= registers;

        if i_write_reg_en = '1' then
            registers_next(to_integer(i_sel_reg_w)) <= i_write_data;
        end if;
    end process;

    prs_out : process (all)
    begin
        o_reg_a <= registers(to_integer(i_sel_reg_a));
        o_reg_b <= registers(to_integer(i_sel_reg_b));
    end process;

end architecture;
