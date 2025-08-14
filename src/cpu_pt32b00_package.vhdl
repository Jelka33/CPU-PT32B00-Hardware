library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cpu_pt32b00_package is
    -- Global types
    type t_alu_operation is (
        ALU_OP_ADD, ALU_OP_ADC, ALU_OP_SUB, ALU_OP_SBB,
        ALU_OP_MUL_LU, ALU_OP_MUL_LS, ALU_OP_MUL_H, ALU_OP_AND,
        ALU_OP_OR, ALU_OP_XOR, ALU_OP_SHLR, ALU_OP_SHAR, ALU_OP_PASS_B
    );

    type t_cache_row is array(natural range <>) of std_logic_vector(31 downto 0);
    type t_cache_row_metadata is array(natural range <>) of std_logic_vector;

    -- Opcodes
    constant OPCODE_NOP : unsigned(7 downto 0) := x"00";

    constant OPCODE_ADD_RR : unsigned(7 downto 0) := x"01";
    constant OPCODE_ADD_R32 : unsigned(7 downto 0) := x"02";
    constant OPCODE_ADD_R16 : unsigned(7 downto 0) := x"03";

    constant OPCODE_ADC_RR : unsigned(7 downto 0) := x"04";
    constant OPCODE_ADC_R32 : unsigned(7 downto 0) := x"05";
    constant OPCODE_ADC_R16 : unsigned(7 downto 0) := x"06";

    constant OPCODE_SUB_RR : unsigned(7 downto 0) := x"07";
    constant OPCODE_SUB_R32 : unsigned(7 downto 0) := x"08";
    constant OPCODE_SUB_R16 : unsigned(7 downto 0) := x"09";

    constant OPCODE_SBB_RR : unsigned(7 downto 0) := x"0A";
    constant OPCODE_SBB_R32 : unsigned(7 downto 0) := x"0B";
    constant OPCODE_SBB_R16 : unsigned(7 downto 0) := x"0C";

    constant OPCODE_MUL_RR : unsigned(7 downto 0) := x"0D";
    constant OPCODE_MUL_R32 : unsigned(7 downto 0) := x"0E";

    constant OPCODE_UMUL_RR : unsigned(7 downto 0) := x"0F";
    constant OPCODE_UMUL_R32 : unsigned(7 downto 0) := x"10";

    constant OPCODE_SMUL_RR : unsigned(7 downto 0) := x"11";
    constant OPCODE_SMUL_R32 : unsigned(7 downto 0) := x"12";


    constant OPCODE_AND_RR : unsigned(7 downto 0) := x"13";
    constant OPCODE_AND_R32 : unsigned(7 downto 0) := x"14";

    constant OPCODE_OR_RR : unsigned(7 downto 0) := x"15";
    constant OPCODE_OR_R32 : unsigned(7 downto 0) := x"16";

    constant OPCODE_XOR_RR : unsigned(7 downto 0) := x"17";
    constant OPCODE_XOR_R32 : unsigned(7 downto 0) := x"18";

    constant OPCODE_SHR : unsigned(7 downto 0) := x"19";

    constant OPCODE_SAR : unsigned(7 downto 0) := x"1A";


    constant OPCODE_CMP_RR : unsigned(7 downto 0) := x"1B";
    constant OPCODE_CMP_R32 : unsigned(7 downto 0) := x"1C";


    constant OPCODE_MOV_RR : unsigned(7 downto 0) := x"1D";
    constant OPCODE_MOV_R32 : unsigned(7 downto 0) := x"1E";

    constant OPCODE_LOAD : unsigned(7 downto 0) := x"1F";

    constant OPCODE_STORE : unsigned(7 downto 0) := x"20";

    constant OPCODE_PUSH_R : unsigned(7 downto 0) := x"21";
    constant OPCODE_PUSH_32 : unsigned(7 downto 0) := x"22";

    constant OPCODE_POP : unsigned(7 downto 0) := x"23";


    constant OPCODE_JMP : unsigned(7 downto 0) := x"24";


    constant OPCODE_INT : unsigned(7 downto 0) := x"25";

    constant OPCODE_IRET : unsigned(7 downto 0) := x"26";


    constant OPCODE_HLT : unsigned(7 downto 0) := x"27";


    constant OPCODE_IN : unsigned(7 downto 0) := x"28";

    constant OPCODE_OUT : unsigned(7 downto 0) := x"29";


    constant OPCODE_CLI : unsigned(7 downto 0) := x"2A";

    constant OPCODE_STI : unsigned(7 downto 0) := x"2B";

    -- Architecture constants
    constant REGISTER_SP_I : natural := 15;
    constant REGISTER_FLAGS_I : natural := 16;
    constant REGISTER_CR0_I : natural := 17;
    constant REGISTER_CR1_I : natural := 18;
    constant REGISTER_CR2_I : natural := 19;
    constant REGISTER_CR3_I : natural := 20;
    constant REGISTER_IVTAR_I : natural := 21;
    constant REGISTER_ISRVR1_I : natural := 22;
    constant REGISTER_ISRVR2_I : natural := 23;
    constant REGISTER_DR0_I : natural := 24;
    constant REGISTER_DR1_I : natural := 25;
    constant REGISTER_DR2_I : natural := 26;
    constant REGISTER_DR3_I : natural := 27;
    constant REGISTER_DR4_I : natural := 28;

    constant REG_CR0_INTERRUPTS_EN_BIT : natural := 0;
    constant REG_CR0_SINGLE_STEP_TRAP_BIT : natural := 1;
    constant REG_CR0_PAGING_EN_BIT : natural := 2;

    constant INTNUM_INST_INVALID : natural := 0;
    constant INTNUM_PRIVILEGE_FAULT : natural := 1;
    constant INTNUM_PAGE_FAULT : natural := 2;
    constant INTNUM_DEBUG : natural := 3;
    constant INTNUM_BREAKPOINT : natural := 4;

    constant CACHE_VALID_FLAG_OFFSET : natural := 1;
    constant CACHE_DIRTY_FLAG_OFFSET : natural := 2;

    -- Port I/O constants
    constant MEMMGR_RAM_DEPTH_IO : natural := 0;
    constant MEMMGR_FLUSH_TLB_IO : natural := 1;
    constant MEMMGR_EVICT_TLB_ENTRY_IO : natural := 2;
    constant CACHE_EVICT_INST_LINE_IO : natural := 3;
    constant CACHE_EVICT_DATA_LINE_IO : natural := 4;
    constant CACHE_PUSH_INST_LINE_IO : natural := 5;
    constant CACHE_PUSH_DATA_LINE_IO : natural := 6;

    -- Functions
    function f_log2 (x : positive) return natural;

end package;

package body cpu_pt32b00_package is

    function f_log2 (x : positive) return natural is
        variable i : natural;
    begin
        i := 0;  
        while (2**i < x) and i < 31 loop
            i := i + 1;
        end loop;
        return i;
    end function;

end package body;