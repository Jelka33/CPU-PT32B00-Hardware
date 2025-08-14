library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity alu is
    port (
        i_clk : in std_logic;

        i_a_operand : in unsigned(31 downto 0);
        i_b_operand : in unsigned(31 downto 0);
        i_operation : in t_alu_operation;
        i_last_carry : in std_logic;

        o_flags : out std_logic_vector(3 downto 0);
        o_result : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of alu is

    signal carry_operand : unsigned(0 downto 0);
    signal is_carry_operation : unsigned(0 downto 0);

    signal reg_mul_h : unsigned(31 downto 0);
    signal reg_mul_h_next : unsigned(31 downto 0);

    signal add_result : unsigned(32 downto 0);
    signal sub_result : unsigned(32 downto 0);
    signal mul_u_result : unsigned(63 downto 0);
    signal mul_hs_result : unsigned(63 downto 32);
    signal and_result : unsigned(31 downto 0);
    signal or_result : unsigned(31 downto 0);
    signal xor_result : unsigned(31 downto 0);
    signal shr_result : unsigned(31 downto 0);

    signal result : unsigned(31 downto 0);

begin

    -- Misc wiring
    o_result <= result;
    
    is_carry_operation <= "1" when i_operation = ALU_OP_ADC or i_operation = ALU_OP_SBB else "0";
    carry_operand <= "" & i_last_carry and is_carry_operation;

    -- All operations are always calculated
    add_result <= resize(i_a_operand, 33) + i_b_operand + carry_operand;
    sub_result <= resize(i_a_operand, 33) - i_b_operand - carry_operand;

    mul_u_result <= i_a_operand * i_b_operand;      -- the whole unsigned multiplication
    mul_hs_result <= unsigned("*"(signed(i_a_operand), signed(i_b_operand))(63 downto 32));
                                                    -- signed upper half, the lower half
                                                    -- can be used from the above

    reg_mul_h_next <= mul_hs_result(63 downto 32) when i_operation = ALU_OP_MUL_LS
                        else mul_u_result(63 downto 32);

    and_result <= i_a_operand and i_b_operand;
    or_result <= i_a_operand or i_b_operand;
    xor_result <= i_a_operand xor i_b_operand;

    shr_result(30 downto 0) <= shift_right(i_a_operand, to_integer(i_b_operand))(30 downto 0);
    shr_result(31) <= i_a_operand(31) when i_operation = ALU_OP_SHAR else '0';

    prs_seq : process (i_clk)
    begin
        if rising_edge(i_clk) then
            reg_mul_h <= reg_mul_h_next;
        end if;
    end process;

    -- Output the correct operation
    prs_res : process (all)
    begin
        case i_operation is
            when ALU_OP_ADD | ALU_OP_ADC =>
                result <= add_result(31 downto 0);
            when ALU_OP_SUB | ALU_OP_SBB =>
                result <= sub_result(31 downto 0);
            when ALU_OP_MUL_LU | ALU_OP_MUL_LS =>
                result <= mul_u_result(31 downto 0);
            when ALU_OP_MUL_H =>
                result <= reg_mul_h;
            when ALU_OP_AND =>
                result <= and_result;
            when ALU_OP_OR =>
                result <= or_result;
            when ALU_OP_XOR =>
                result <= xor_result;
            when ALU_OP_SHLR | ALU_OP_SHAR =>
                result <= shr_result;
            when ALU_OP_PASS_B =>
                result <= i_b_operand;
            when others =>
                result <= (others => '0');
        end case;
    end process;

    -- Output the flags
    prs_flags : process (all)
    begin
        -- zero flag
        if result = 0 then
            o_flags(0) <= '1';
        else
            o_flags(0) <= '0';
        end if;

        -- overflow flag
        if (i_operation = ALU_OP_ADD or i_operation = ALU_OP_ADC)
                and i_a_operand(31) = i_b_operand(31) and i_b_operand(31) /= result(31) then
            o_flags(2) <= '1';
        elsif (i_operation = ALU_OP_SUB or i_operation = ALU_OP_SBB)
                and i_a_operand(31) /= i_b_operand(31) and i_b_operand(31) = result(31) then
            o_flags(2) <= '1';
        else
            o_flags(2) <= '0';
        end if;

        -- sign flag
        o_flags(3) <= result(31);

        -- carry flag
        case i_operation is
            when ALU_OP_ADD | ALU_OP_ADC =>
                o_flags(1) <= add_result(32);
            when ALU_OP_SUB | ALU_OP_SBB =>
                o_flags(1) <= sub_result(32);
            when ALU_OP_MUL_LU | ALU_OP_MUL_LS =>
                if reg_mul_h_next /= 0 then
                    o_flags(1) <= '1';
                else
                    o_flags(1) <= '0';
                end if;
            when others =>
                o_flags(1) <= '0';
        end case;
    end process;

end architecture;