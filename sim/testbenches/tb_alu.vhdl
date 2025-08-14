-- Testbench automatically generated online
-- at https://vhdl.lapinoo.net
-- Generation date : 14.1.2025 15:11:57 UTC

-- Edited afterwards

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity tb_alu is
end tb_alu;

architecture tb of tb_alu is

    component alu
        port (i_clk        : in std_logic;
              i_a_operand  : in unsigned (31 downto 0);
              i_b_operand  : in unsigned (31 downto 0);
              i_operation  : in t_alu_operation;
              i_last_carry : in std_logic;
              o_flags      : out std_logic_vector (3 downto 0);
              o_result     : out unsigned (31 downto 0));
    end component;

    signal i_clk        : std_logic;
    signal i_a_operand  : unsigned (31 downto 0);
    signal i_b_operand  : unsigned (31 downto 0);
    signal i_operation  : t_alu_operation;
    signal i_last_carry : std_logic;
    signal o_flags      : std_logic_vector (3 downto 0);
    signal o_result     : unsigned (31 downto 0);

    constant TbPeriod : time := 1000 ns; -- EDIT Put right period here
    signal TbClock : std_logic := '0';
    signal TbSimEnded : std_logic := '0';

begin

    dut : alu
    port map (i_clk        => i_clk,
              i_a_operand  => i_a_operand,
              i_b_operand  => i_b_operand,
              i_operation  => i_operation,
              i_last_carry => i_last_carry,
              o_flags      => o_flags,
              o_result     => o_result);

    -- Clock generation
    TbClock <= not TbClock after TbPeriod/2 when TbSimEnded /= '1' else '0';

    -- EDIT: Check that i_clk is really your main clock signal
    i_clk <= TbClock;

    stimuli : process
    begin
        -- EDIT Adapt initialization as needed
        i_a_operand <= (others => '0');
        i_b_operand <= (others => '0');
        i_operation <= ALU_OP_ADD;
        i_last_carry <= '0';

        -- EDIT Add stimuli here
        wait for 10 * TbPeriod;

        i_a_operand <= to_unsigned(123, 32);
        i_b_operand <= to_unsigned(321, 32);
        i_operation <= ALU_OP_ADD;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = 444 report "Fail ADD (1)" severity FAILURE;
        assert o_flags = "0000" report "Fail ADD (1)" severity FAILURE;
        

        i_a_operand <= x"FFFF_FFFF";
        i_b_operand <= to_unsigned(10, 32);
        i_operation <= ALU_OP_ADD;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = 9 report "Fail ADD (2)" severity FAILURE;
        assert o_flags = "0010" report "Fail ADD (2)" severity FAILURE;


        i_a_operand <= x"7FFF_FFFF";
        i_b_operand <= to_unsigned(10, 32);
        i_operation <= ALU_OP_ADD;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = x"8000_0009" report "Fail ADD (3)" severity FAILURE;
        assert o_flags = "1100" report "Fail ADD (3)" severity FAILURE;


        i_a_operand <= x"FFFF_FFFF";
        i_b_operand <= to_unsigned(10, 32);
        i_operation <= ALU_OP_ADC;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = 9 report "Fail ADC (1)" severity FAILURE;
        assert o_flags = "0010" report "Fail ADC (1)" severity FAILURE;


        i_a_operand <= x"FFFF_FFFF";
        i_b_operand <= to_unsigned(10, 32);
        i_operation <= ALU_OP_ADC;
        i_last_carry <= '1';
        wait for TbPeriod;
        assert o_result = 10 report "Fail ADC (1)" severity FAILURE;
        assert o_flags = "0010" report "Fail ADC (1)" severity FAILURE;


        i_a_operand <= to_unsigned(321, 32);
        i_b_operand <= to_unsigned(123, 32);
        i_operation <= ALU_OP_SUB;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = 198 report "Fail SUB (1)" severity FAILURE;
        assert o_flags = "0000" report "Fail SUB (1)" severity FAILURE;


        i_a_operand <= to_unsigned(123, 32);
        i_b_operand <= to_unsigned(321, 32);
        i_operation <= ALU_OP_SUB;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = not to_unsigned(198, 32) + 1 report "Fail SUB (2)" severity FAILURE;
        assert o_flags = "1010" report "Fail SUB (2)" severity FAILURE;


        i_a_operand <= to_unsigned(123, 32);
        i_b_operand <= to_unsigned(321, 32);
        i_operation <= ALU_OP_SBB;
        i_last_carry <= '1';
        wait for TbPeriod;
        assert o_result = not to_unsigned(199, 32) + 1 report "Fail SBB (1)" severity FAILURE;
        assert o_flags = "1010" report "Fail SBB (1)" severity FAILURE;


        i_a_operand <= to_unsigned(100, 32);
        i_b_operand <= to_unsigned(321, 32);
        i_operation <= ALU_OP_MUL_L;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = 32100 report "Fail MUL_L (1)" severity FAILURE;
        assert o_flags = "0000" report "Fail MUL_L (1)" severity FAILURE;


        i_a_operand <= x"FFFF_FFFF";
        i_b_operand <= to_unsigned(16, 32);
        i_operation <= ALU_OP_MUL_L;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = x"FFFF_FFF0" report "Fail MUL_L (2)" severity FAILURE;
        assert o_flags = "1010" report "Fail MUL_L (2)" severity FAILURE;
        i_operation <= ALU_OP_MUL_H;
        wait for TbPeriod;
        assert o_result = x"F" report "Fail MUL_H (1)" severity FAILURE;
        assert o_flags = "0000" report "Fail MUL_H (1)" severity FAILURE;


        i_a_operand <= x"7FFF_FFFF";
        i_b_operand <= to_unsigned(2, 32);
        i_operation <= ALU_OP_MUL_L;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = x"FFFF_FFFE" report "Fail MUL_L (3)" severity FAILURE;
        assert o_flags = "1000" report "Fail MUL_L (3)" severity FAILURE;
        i_operation <= ALU_OP_MUL_H;
        wait for TbPeriod;
        assert o_result = x"0" report "Fail MUL_H (2)" severity FAILURE;
        assert o_flags = "0001" report "Fail MUL_H (2)" severity FAILURE;


        i_a_operand <= x"FFFF_FFFF";
        i_b_operand <= to_unsigned(500, 32);
        i_operation <= ALU_OP_SHLR;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = x"7FFF_FFFF" report "Fail SHLR (1)" severity FAILURE;
        assert o_flags = "0000" report "Fail SHLR (1)" severity FAILURE;


        i_a_operand <= x"F0FF_FFFF";
        i_b_operand <= to_unsigned(500, 32);
        i_operation <= ALU_OP_SHAR;
        i_last_carry <= '0';
        wait for TbPeriod;
        assert o_result = x"F87F_FFFF" report "Fail SHAR (1)" severity FAILURE;
        assert o_flags = "1000" report "Fail SHAR (1)" severity FAILURE;


        i_a_operand <= x"F0FF_FFFF";
        i_b_operand <= to_unsigned(500, 32);
        i_operation <= ALU_OP_PASS_B;
        i_last_carry <= '1';
        wait for TbPeriod;
        assert o_result = 500 report "Fail PASS_B (1)" severity FAILURE;
        assert o_flags = "0000" report "Fail PASS_B (1)" severity FAILURE;
        

        report "Testbench finished successfully!" severity NOTE;
        -- Stop the clock and hence terminate the simulation
        TbSimEnded <= '1';
        wait;
    end process;

end tb;

-- Configuration block below is required by some simulators. Usually no need to edit.

configuration cfg_tb_alu of tb_alu is
    for tb
    end for;
end cfg_tb_alu;