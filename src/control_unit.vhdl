library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity control_unit is
    port (
        i_clk   : in std_logic;
        i_reset : in std_logic;
        
        i_data : in unsigned(31 downto 0);
        i_memory_manager_rdy : in std_logic;
        i_fetch_data_rdy : in std_logic;
        i_page_fault : in std_logic;

        i_port_data : in unsigned(31 downto 0);

        i_reg_b_data : in unsigned(31 downto 0);

        i_alu_flags : in std_logic_vector(3 downto 0);
        i_calculated_address : in unsigned(31 downto 0);

        i_irq : in std_logic;
        i_irq_num : in unsigned(2 downto 0);

        o_select_reg_a : out unsigned(3 downto 0);
        o_select_reg_b : out unsigned(3 downto 0);
        o_select_reg_w : out unsigned(3 downto 0);
        o_reg_write_en : out std_logic;

        o_shl_reg_a : out unsigned(1 downto 0);

        o_alu_reg_a_en : out std_logic;
        o_alu_reg_b_en : out std_logic;
        o_alu_operation : out t_alu_operation;
        o_alu_b_data : out unsigned(31 downto 0);

        o_address : out std_logic_vector(31 downto 0);
        o_memory_request : out std_logic;
        o_data : out unsigned(31 downto 0);
        o_memory_write_en : out std_logic;
        o_data_fetch_en : out std_logic;
        o_paging_en : out std_logic;
        o_privilege_mode : out std_logic;
        o_page_directory_address : out unsigned(19 downto 0);

        o_port_number : out unsigned(7 downto 0);
        o_port_request_en : out std_logic;
        o_port_data : out unsigned(31 downto 0);
        o_port_write_en : out std_logic
    );
end entity;

architecture rtl of control_unit is

    -- Types
    type t_control_unit_state is (FETCH_INST, WAIT_INST_FETCH, EXECUTE, EXECUTE2,
                                    EXECUTE3, ACCESS_MEMORY, WAIT_DATA_FETCH, HALT,
                                    INT_EXECUTE1, INT_EXECUTE2, INT_EXECUTE3, INT_JUMP);
    type t_special_regs is array(0 to 13) of unsigned(31 downto 0);
    type t_int_queue is array(0 to 3) of unsigned(5 downto 0);

    -- Registers
    signal s_control_unit : t_control_unit_state;
    signal s_control_unit_next : t_control_unit_state;
    
    signal reg_pc : unsigned(31 downto 0);
    signal reg_pc_next : unsigned(31 downto 0);

    signal reg_instruction : std_logic_vector(31 downto 0);
    signal reg_instruction_next : std_logic_vector(31 downto 0);

    signal reg_fetched_data : unsigned(31 downto 0);
    signal reg_fetched_data_next : unsigned(31 downto 0);

    signal reg_fetch_by_load : std_logic;
    signal reg_fetch_by_load_next : std_logic;

    signal reg_special_regs : t_special_regs;
    signal reg_special_regs_next : t_special_regs;

    signal reg_int_irq : std_logic;
    signal reg_int_irq_next : std_logic;

    signal reg_int_num : unsigned(5 downto 0);
    signal reg_int_num_next : unsigned(5 downto 0);

    signal reg_int_execution_en : std_logic;
    signal reg_int_execution_en_next : std_logic;

    signal reg_int_queue : t_int_queue;

    signal reg_int_queue_ptr : unsigned(1 downto 0);
    signal reg_int_queue_ptr_next : unsigned(1 downto 0);

    signal reg_int_queue_en : std_logic;
    signal reg_int_queue_en_next : std_logic;

    -- Outputs
    signal select_reg_a : unsigned(3 downto 0);
    signal select_reg_b : unsigned(3 downto 0);
    signal select_reg_w : unsigned(3 downto 0);
    signal reg_write_en : std_logic;

    signal shl_reg_a : unsigned(1 downto 0);

    signal alu_reg_a_en : std_logic;
    signal alu_reg_b_en : std_logic;
    signal alu_operation : t_alu_operation;
    signal alu_b_data : unsigned(31 downto 0);

    signal address_out : unsigned(31 downto 0);
    signal memory_request : std_logic;
    signal data_out : unsigned(31 downto 0);
    signal memory_write_en : std_logic;
    signal data_fetch_en : std_logic;

    signal port_data_out : unsigned(31 downto 0);
    signal port_number : unsigned(7 downto 0);
    signal port_write_en : std_logic;
    signal port_request_en : std_logic;

    -- Misc
    signal opcode : unsigned(7 downto 0);

    signal special_regs_data_in : unsigned(31 downto 0);
    signal special_regs_data_out : unsigned(31 downto 0);
    signal special_regs_select : unsigned(5 downto 0);
    signal special_regs_write_en : std_logic;

    signal update_alu_flags_en : std_logic;

    signal jump_condition_met_en : std_logic;

    signal int_num : unsigned(5 downto 0);
    signal int_instruction_irq : std_logic;
    signal int_instruction_num : unsigned(5 downto 0);
    signal clear_int : std_logic;
    signal finished_int_execution : std_logic;
    signal int_queue_append_en : std_logic;
    signal int_queue_advance_en : std_logic;

begin
    -- Outputs
    o_select_reg_a <= select_reg_a;
    o_select_reg_b <= select_reg_b;
    o_select_reg_w <= select_reg_w;
    o_reg_write_en <= reg_write_en;

    o_shl_reg_a <= shl_reg_a;

    o_alu_reg_a_en <= alu_reg_a_en;
    o_alu_reg_b_en <= alu_reg_b_en;
    o_alu_operation <= alu_operation;
    o_alu_b_data <= alu_b_data;

    o_address <= std_logic_vector(address_out);
    o_memory_request <= memory_request;
    o_data(7 downto 0) <= data_out(31 downto 24);       -- swap endiannes
    o_data(15 downto 8) <= data_out(23 downto 16);
    o_data(23 downto 16) <= data_out(15 downto 8);
    o_data(31 downto 24) <= data_out(7 downto 0);
    o_memory_write_en <= memory_write_en;
    o_data_fetch_en <= data_fetch_en;
    o_paging_en <= reg_special_regs(REGISTER_CR0_I-16)(REG_CR0_PAGING_EN_BIT);
    o_privilege_mode <= reg_special_regs(REGISTER_FLAGS_I-16)(4);
    o_page_directory_address <= reg_special_regs(REGISTER_CR1_I-16)(31 downto 12);

    o_port_data <= port_data_out;
    o_port_number <= port_number;
    o_port_write_en <= port_write_en;
    o_port_request_en <= port_request_en;

    -- Misc
    opcode <= unsigned(reg_instruction(31 downto 24));
    special_regs_data_out <= reg_special_regs(to_integer(special_regs_select));

    -- Clocked process
    prs_seq : process (i_clk, i_reset)
    begin
        if i_reset = '1' then

            s_control_unit <= FETCH_INST;

            reg_pc <= x"FFFF_FFF8";
            reg_instruction <= (others => '0');
            reg_fetched_data <= (others => '0');

            reg_fetch_by_load <= '0';

            reg_special_regs <= (others => (others => '0'));

            reg_int_irq <= '0';
            reg_int_num <= (others => '0');
            reg_int_execution_en <= '0';

            reg_int_queue <= (others => (others => '0'));
            reg_int_queue_ptr <= (others => '0');
            reg_int_queue_en <= '0';

        elsif rising_edge(i_clk) then

            if reg_int_irq_next = '1' and s_control_unit_next = FETCH_INST then
                s_control_unit <= INT_EXECUTE1;         -- in case of an interrupt
            else
                s_control_unit <= s_control_unit_next;  -- normal flow
            end if;

            reg_pc <= reg_pc_next;
            reg_instruction <= reg_instruction_next;
            reg_fetched_data <= reg_fetched_data_next;

            reg_fetch_by_load <= reg_fetch_by_load_next;

            reg_special_regs <= reg_special_regs_next;

            reg_int_irq <= reg_int_irq_next;
            reg_int_num <= reg_int_num_next;
            reg_int_execution_en <= reg_int_execution_en_next;

            if int_queue_append_en = '1' then
                reg_int_queue(to_integer(reg_int_queue_ptr)) <= int_num;
            end if;
            if int_queue_advance_en = '1' then
                reg_int_queue(0) <= reg_int_queue(1);
                reg_int_queue(1) <= reg_int_queue(2);
                reg_int_queue(2) <= reg_int_queue(3);
                reg_int_queue(3) <= to_unsigned(0, reg_int_queue(3)'length);
            end if;
            reg_int_queue_ptr <= reg_int_queue_ptr_next;
            reg_int_queue_en <= reg_int_queue_en_next;

        end if;
    end process;

    -- States process
    prs_fsm : process (all)
    begin
        s_control_unit_next <= s_control_unit;

        case s_control_unit is
            when FETCH_INST =>
                if i_memory_manager_rdy = '1' then
                    s_control_unit_next <= WAIT_INST_FETCH;
                end if;

            when WAIT_INST_FETCH =>
                if i_fetch_data_rdy = '1' then
                    s_control_unit_next <= EXECUTE;
                end if;

            when EXECUTE =>
                case opcode is
                    when OPCODE_ADD_R32 | OPCODE_ADC_R32 | OPCODE_SUB_R32 |
                         OPCODE_SBB_R32 | OPCODE_MUL_R32 | OPCODE_UMUL_R32 |
                         OPCODE_SMUL_R32 | OPCODE_AND_R32 | OPCODE_OR_R32 |
                         OPCODE_XOR_R32 | OPCODE_CMP_R32 | OPCODE_MOV_R32 |
                         OPCODE_PUSH_32 =>       -- instructions with imm32
                        s_control_unit_next <= WAIT_DATA_FETCH;

                    when OPCODE_UMUL_RR | OPCODE_SMUL_RR | OPCODE_PUSH_R =>
                        s_control_unit_next <= EXECUTE2;

                    when OPCODE_LOAD | OPCODE_STORE =>
                        if unsigned(reg_instruction(9 downto 7)) = x"0" or
                            unsigned(reg_instruction(9 downto 7)) = x"2" or
                            unsigned(reg_instruction(9 downto 7)) = x"4" then
                            -- the addressing mode uses imm32
                            s_control_unit_next <= WAIT_DATA_FETCH;
                        else
                            s_control_unit_next <= ACCESS_MEMORY;
                        end if;

                    when OPCODE_POP =>
                        if reg_instruction(19) = '1' then
                            s_control_unit_next <= WAIT_DATA_FETCH;
                        else
                            s_control_unit_next <= FETCH_INST;
                        end if;

                    when OPCODE_JMP =>
                        if reg_instruction(23) = '0' then
                            s_control_unit_next <= WAIT_DATA_FETCH;
                        elsif reg_instruction(22) = '1' then
                            s_control_unit_next <= EXECUTE2;
                        else
                            s_control_unit_next <= FETCH_INST;
                        end if;

                        if jump_condition_met_en /= '1' then
                            s_control_unit_next <= FETCH_INST;
                        end if;

                    when OPCODE_IRET =>
                        s_control_unit_next <= WAIT_DATA_FETCH;

                    when OPCODE_HLT =>
                        s_control_unit_next <= HALT;
                    
                    when others =>
                        s_control_unit_next <= FETCH_INST;
                end case;

                if int_instruction_irq = '1' then
                    s_control_unit_next <= FETCH_INST;
                end if;

            when EXECUTE2 =>
                case opcode is
                    when OPCODE_UMUL_R32 | OPCODE_SMUL_R32 =>
                        s_control_unit_next <= EXECUTE3;
                    
                    when OPCODE_LOAD | OPCODE_STORE =>
                        if unsigned(reg_instruction(9 downto 7)) = x"4" then
                            s_control_unit_next <= EXECUTE3;
                        else
                            s_control_unit_next <= ACCESS_MEMORY;
                        end if;

                    when OPCODE_IRET =>
                        s_control_unit_next <= WAIT_DATA_FETCH;
                    
                    when others =>
                        s_control_unit_next <= FETCH_INST;
                end case;

                if int_instruction_irq = '1' then
                    s_control_unit_next <= FETCH_INST;
                end if;

            when EXECUTE3 =>
                case opcode is
                    when OPCODE_LOAD | OPCODE_STORE =>
                        if reg_fetch_by_load = '0' then
                            s_control_unit_next <= ACCESS_MEMORY;
                        else
                            s_control_unit_next <= FETCH_INST;
                        end if;

                    when others =>
                        s_control_unit_next <= FETCH_INST;
                end case;

            when ACCESS_MEMORY =>
                if i_memory_manager_rdy = '1' then
                    if opcode = OPCODE_LOAD or reg_int_irq = '1' then
                        s_control_unit_next <= WAIT_DATA_FETCH;
                    else
                        s_control_unit_next <= FETCH_INST;
                    end if;
                end if;

            when WAIT_DATA_FETCH =>
                if i_fetch_data_rdy = '1' then
                    if reg_fetch_by_load = '1' then
                        if reg_int_irq = '1' then
                            s_control_unit_next <= INT_JUMP;
                        else
                            s_control_unit_next <= EXECUTE3;
                        end if;
                    else
                        s_control_unit_next <= EXECUTE2;
                    end if;
                end if;

            when HALT =>
                if reg_int_irq = '1' then
                    s_control_unit_next <= INT_EXECUTE1;
                end if;

            when INT_EXECUTE1 =>
                s_control_unit_next <= INT_EXECUTE2;

            when INT_EXECUTE2 =>
                s_control_unit_next <= INT_EXECUTE3;

            when INT_EXECUTE3 =>
                if i_memory_manager_rdy = '1' then
                    s_control_unit_next <= ACCESS_MEMORY;
                end if;

            when INT_JUMP =>
                s_control_unit_next <= FETCH_INST;

            when others =>
                s_control_unit_next <= FETCH_INST;
        end case;
    end process;

    -- Memory-fetch registers process
    prs_mem_fetch_regs : process (all)
    begin
        reg_instruction_next <= reg_instruction;
        reg_fetched_data_next <= reg_fetched_data;

        case s_control_unit is
            when WAIT_INST_FETCH =>
                reg_instruction_next <= std_logic_vector(i_data);

            when WAIT_DATA_FETCH =>
                -- switch endianness of data
                reg_fetched_data_next(7 downto 0) <= i_data(31 downto 24);
                reg_fetched_data_next(15 downto 8) <= i_data(23 downto 16);
                reg_fetched_data_next(23 downto 16) <= i_data(15 downto 8);
                reg_fetched_data_next(31 downto 24) <= i_data(7 downto 0);

            when others =>
                null;
        end case;
    end process;

    -- `fetch_by_load` register process
    prs_reg_fetch_by_load : process (all)
    begin
        case s_control_unit is
            when ACCESS_MEMORY =>
                reg_fetch_by_load_next <= '1';
            when WAIT_DATA_FETCH =>
                reg_fetch_by_load_next <= reg_fetch_by_load;
            when EXECUTE2 =>
                if opcode = OPCODE_IRET then
                    reg_fetch_by_load_next <= '1';
                else
                    reg_fetch_by_load_next <= '0';
                end if;
            when others =>
                reg_fetch_by_load_next <= '0';
        end case;
    end process;

    -- Special regs driver process
    prs_special_regs_driver : process (all)
    begin
        reg_special_regs_next <= reg_special_regs;

        if special_regs_write_en = '1' and special_regs_select /= REGISTER_FLAGS_I-16 then
            reg_special_regs_next(to_integer(special_regs_select)) <= special_regs_data_in;
        end if;

        -- auto-update flags
        if update_alu_flags_en = '1' then
            if s_control_unit = EXECUTE3 and opcode = OPCODE_IRET then
                reg_special_regs_next(REGISTER_FLAGS_I-16) <= reg_fetched_data;
            else
                reg_special_regs_next(REGISTER_FLAGS_I-16)(3 downto 0) <= unsigned(i_alu_flags);
            end if;
        end if;

        -- set the privilege mode flag
        if reg_special_regs(REGISTER_CR0_I-16)(REG_CR0_PAGING_EN_BIT) = '1' and reg_int_execution_en = '0' then
            reg_special_regs_next(REGISTER_FLAGS_I-16)(4) <= '0';
        else
            reg_special_regs_next(REGISTER_FLAGS_I-16)(4) <= '1';
        end if;
    end process;

    -- Process for checking if jump should be executed or not
    prs_jump_condition_check : process(all)
    begin
        jump_condition_met_en <= '0';

        case unsigned(reg_instruction(20 downto 16)) is
            when to_unsigned(0, 5) =>
                jump_condition_met_en <= '1';

            when to_unsigned(1, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(1) = '1' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(2, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(1) = '0' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(3, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(2) = '1' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(4, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(2) = '0' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(5, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(3) = '1' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(6, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(3) = '0' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(7, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(0) = '1' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(8, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(0) = '0' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(9, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(0) = '0' and
                    reg_special_regs(REGISTER_FLAGS_I-16)(3) = reg_special_regs(REGISTER_FLAGS_I-16)(2) then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(10, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(3) = reg_special_regs(REGISTER_FLAGS_I-16)(2) then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(11, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(3) /= reg_special_regs(REGISTER_FLAGS_I-16)(2) then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(12, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(0) = '1' or
                    reg_special_regs(REGISTER_FLAGS_I-16)(3) /= reg_special_regs(REGISTER_FLAGS_I-16)(2) then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(13, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(1) = '0' and reg_special_regs(REGISTER_FLAGS_I-16)(0) = '0' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(14, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(1) = '0' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(15, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(1) = '1' then
                    jump_condition_met_en <= '1';
                end if;

            when to_unsigned(16, 5) =>
                if reg_special_regs(REGISTER_FLAGS_I-16)(1) = '1' or reg_special_regs(REGISTER_FLAGS_I-16)(0) = '1' then
                    jump_condition_met_en <= '1';
                end if;

            when others =>
                null;
        end case;
    end process;

    -- Activate interrupt process
    prs_interrupt_activate : process(all)
    begin
        reg_int_irq_next <= reg_int_irq;
        reg_int_num_next <= reg_int_num;
        reg_int_execution_en_next <= reg_int_execution_en;
        reg_int_queue_en_next <= reg_int_queue_en;
        reg_int_queue_ptr_next <= reg_int_queue_ptr;

        int_queue_append_en <= '0';
        int_queue_advance_en <= '0';

        -- if interrupts are enabled and any occured
        if reg_special_regs(REGISTER_CR0_I-16)(0) = '1' and (i_irq = '1' or int_instruction_irq = '1' or i_page_fault = '1') then
            if reg_int_execution_en = '0' then       -- if no interrupt is handled currently
                if int_num(5) = '0' then
                    reg_int_irq_next <= reg_special_regs(REGISTER_ISRVR1_I-16)(to_integer(int_num(4 downto 0)));
                    reg_int_execution_en_next <= reg_special_regs(REGISTER_ISRVR1_I-16)(to_integer(int_num(4 downto 0)));
                else
                    reg_int_irq_next <= reg_special_regs(REGISTER_ISRVR2_I-16)(to_integer(int_num(4 downto 0)));
                    reg_int_execution_en_next <= reg_special_regs(REGISTER_ISRVR2_I-16)(to_integer(int_num(4 downto 0)));
                end if;

                -- update interrupt number only when an interrupt occured
                reg_int_num_next <= int_num;
            else        -- if an interrupt is handled currently, add the next to the queue
                if (int_num(5) = '0' and
                        reg_special_regs(REGISTER_ISRVR1_I-16)(to_integer(int_num(4 downto 0))) = '1') or
                    (int_num(5) = '1' and
                        reg_special_regs(REGISTER_ISRVR2_I-16)(to_integer(int_num(4 downto 0))) = '1') then
                    reg_int_queue_ptr_next <= reg_int_queue_ptr + 1;
                    reg_int_queue_en_next <= '1';
                    int_queue_append_en <= '1';
                end if;
            end if;
        elsif clear_int = '1' then
            reg_int_irq_next <= '0';
        end if;

        if finished_int_execution = '1' then
            reg_int_execution_en_next <= reg_int_queue_en;

            if reg_int_queue_en = '1' then
                reg_int_irq_next <= '1';
                reg_int_num_next <= reg_int_queue(0);
                reg_int_queue_ptr_next <= reg_int_queue_ptr - 1;
                int_queue_advance_en <= '1';

                if reg_int_queue_ptr = 1 then
                    reg_int_queue_en_next <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Interrupts' number process
    prs_interrupts_num : process(all)
    begin
        -- prefer page fault
        if i_page_fault = '1' then
            int_num <= to_unsigned(INTNUM_PAGE_FAULT, int_num'length);
        elsif int_instruction_irq = '1' then    -- then instruction interrupts
            int_num <= int_instruction_num;
        else
            -- the hardware interrupt
            int_num <= resize(i_irq_num, int_num'length) + 5;
            -- (the constant is the offset of exceptions + reserved interrupts)
        end if;
    end process;

    -- Outputs process
    prs_outputs : process (all)
    begin
        -- Default assignments
        reg_pc_next <= reg_pc;
        address_out <= to_unsigned(0, address_out'length);
        data_out <= (others => '0');
        memory_request <= '0';
        memory_write_en <= '0';
        data_fetch_en <= '0';

        shl_reg_a <= (others => '0');

        select_reg_a <= to_unsigned(0, select_reg_a'length);
        select_reg_b <= to_unsigned(0, select_reg_b'length);
        select_reg_w <= to_unsigned(0, select_reg_w'length);
        reg_write_en <= '0';

        alu_reg_a_en <= '0';
        alu_reg_b_en <= '0';
        alu_b_data <= to_unsigned(0, alu_b_data'length);
        alu_operation <= ALU_OP_ADD;

        special_regs_data_in <= to_unsigned(0, special_regs_data_in'length);
        special_regs_select <= to_unsigned(0, special_regs_select'length);
        special_regs_write_en <= '0';

        update_alu_flags_en <= '0';

        port_data_out <= to_unsigned(0, port_data_out'length);
        port_number <= to_unsigned(0, port_number'length);
        port_write_en <= '0';
        port_request_en <= '0';

        int_instruction_irq <= '0';
        int_instruction_num <= (others => '0');
        clear_int <= '0';
        finished_int_execution <= '0';

        -- State dependent assignments
        case s_control_unit is
            when FETCH_INST =>
                address_out <= reg_pc;
                memory_request <= '1';

                if i_memory_manager_rdy = '1' then
                    reg_pc_next <= reg_pc + 4;
                end if;

            when EXECUTE =>
                case opcode is
                    when OPCODE_ADD_RR | OPCODE_ADC_RR | OPCODE_SUB_RR | OPCODE_SBB_RR |
                            OPCODE_MUL_RR | OPCODE_AND_RR | OPCODE_OR_RR | OPCODE_XOR_RR =>
                        select_reg_w <= unsigned(reg_instruction(23 downto 20));
                        select_reg_a <= unsigned(reg_instruction(19 downto 16));
                        select_reg_b <= unsigned(reg_instruction(15 downto 12));
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_reg_b_en <= '1';

                        update_alu_flags_en <= '1';

                    when OPCODE_CMP_RR =>
                        select_reg_a <= unsigned(reg_instruction(19 downto 16));
                        select_reg_b <= unsigned(reg_instruction(15 downto 12));

                        alu_reg_a_en <= '1';
                        alu_reg_b_en <= '1';

                        update_alu_flags_en <= '1';

                    when OPCODE_ADD_R16 | OPCODE_ADC_R16 | OPCODE_SUB_R16 | OPCODE_SBB_R16 |
                            OPCODE_SHR | OPCODE_SAR =>
                        select_reg_w <= unsigned(reg_instruction(23 downto 20));
                        select_reg_a <= unsigned(reg_instruction(19 downto 16));
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_b_data <= resize(unsigned(reg_instruction(15 downto 0)), alu_b_data'length);

                        update_alu_flags_en <= '1';

                    when OPCODE_UMUL_RR | OPCODE_SMUL_RR =>
                        select_reg_w <= unsigned(reg_instruction(19 downto 16));
                        select_reg_a <= unsigned(reg_instruction(15 downto 12));
                        select_reg_b <= unsigned(reg_instruction(11 downto 8));
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_reg_b_en <= '1';

                        update_alu_flags_en <= '1';

                    when OPCODE_ADD_R32 | OPCODE_ADC_R32 | OPCODE_SUB_R32 | OPCODE_SBB_R32 |
                            OPCODE_MUL_R32 | OPCODE_UMUL_R32 | OPCODE_SMUL_R32 | OPCODE_AND_R32 |
                            OPCODE_OR_R32 | OPCODE_XOR_R32 | OPCODE_CMP_R32 | OPCODE_MOV_R32 =>
                        address_out <= reg_pc;
                        memory_request <= '1';

                        reg_pc_next <= reg_pc + 4;

                    when OPCODE_MOV_RR =>
                        update_alu_flags_en <= '1';

                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '0' and (
                            unsigned(reg_instruction(23 downto 18)) > REGISTER_FLAGS_I or
                            unsigned(reg_instruction(17 downto 12)) > REGISTER_FLAGS_I) then
                            -- MOV to and from registers beyond the FLAGS register in user mode is not allowed
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        elsif unsigned(reg_instruction(23 downto 22)) = 0 and unsigned(reg_instruction(17 downto 16)) = 0 then
                            select_reg_w <= unsigned(reg_instruction(21 downto 18));
                            select_reg_b <= unsigned(reg_instruction(15 downto 12));
                            reg_write_en <= '1';

                            alu_reg_b_en <= '1';
                            alu_operation <= ALU_OP_PASS_B;
                        elsif unsigned(reg_instruction(23 downto 22)) = 0 and unsigned(reg_instruction(17 downto 16)) /= 0 then
                            select_reg_w <= unsigned(reg_instruction(21 downto 18));
                            reg_write_en <= '1';

                            special_regs_select <= unsigned(reg_instruction(17 downto 16))-1 &
                                                    unsigned(reg_instruction(15 downto 12));
                            alu_b_data <= special_regs_data_out;
                            alu_operation <= ALU_OP_PASS_B;
                        elsif unsigned(reg_instruction(23 downto 22)) /= 0 and unsigned(reg_instruction(17 downto 16)) = 0 then
                            select_reg_b <= unsigned(reg_instruction(15 downto 12));

                            special_regs_select <= unsigned(reg_instruction(23 downto 22))-1 &
                                                    unsigned(reg_instruction(21 downto 18));
                            special_regs_data_in <= i_reg_b_data;
                            special_regs_write_en <= '1';
                        else
                            -- MOV between two inner registers is not supported!
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_INST_INVALID, int_instruction_num'length);
                        end if;

                    when OPCODE_LOAD | OPCODE_STORE =>
                        if unsigned(reg_instruction(9 downto 7)) = x"0" or
                            unsigned(reg_instruction(9 downto 7)) = x"2" or
                            unsigned(reg_instruction(9 downto 7)) = x"4" then
                            -- the addressing mode uses imm32
                            address_out <= reg_pc;
                            memory_request <= '1';

                            reg_pc_next <= reg_pc + 4;
                        else
                            -- the addressing mode does not use imm32
                            select_reg_a <= unsigned(reg_instruction(19 downto 16));
                            shl_reg_a <= unsigned(reg_instruction(11 downto 10));
                            alu_reg_a_en <= '1';

                            alu_operation <= ALU_OP_ADD;

                            if unsigned(reg_instruction(9 downto 7)) = x"1" then
                                alu_b_data <= to_unsigned(0, alu_b_data'length);
                            elsif unsigned(reg_instruction(9 downto 7)) = x"3" then
                                select_reg_b <= unsigned(reg_instruction(15 downto 12));
                                alu_reg_b_en <= '1';
                            else
                                -- Oops... the addressing mode is actually invalid...
                                int_instruction_irq <= '1';
                                int_instruction_num <= to_unsigned(INTNUM_INST_INVALID, int_instruction_num'length);
                            end if;
                        end if;

                    when OPCODE_PUSH_R =>
                        select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                        select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                        reg_write_en <= '1';
                        
                        alu_reg_a_en <= '1';
                        alu_b_data <= to_unsigned(4, alu_b_data'length);

                    when OPCODE_PUSH_32 =>
                        address_out <= reg_pc;
                        memory_request <= '1';

                        reg_pc_next <= reg_pc + 4;

                        select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                        select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                        reg_write_en <= '1';
                        
                        alu_reg_a_en <= '1';
                        alu_b_data <= to_unsigned(4, alu_b_data'length);

                    when OPCODE_POP =>
                        select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                        select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_b_data <= to_unsigned(4, alu_b_data'length);

                        -- if the value should be saved
                        select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                        address_out <= i_reg_b_data;
                        memory_request <= reg_instruction(19);
                        data_fetch_en <= '1';

                    when OPCODE_JMP =>
                        if jump_condition_met_en = '1' then
                            if (reg_instruction(22) and reg_instruction(21)) = '1' then
                                -- both a call and a return doesn't make much sence
                                int_instruction_irq <= '1';
                                int_instruction_num <= to_unsigned(INTNUM_INST_INVALID, int_instruction_num'length);
                            elsif reg_instruction(23) = '0' then
                                -- [a far jump]
                                memory_request <= '1';

                                if reg_instruction(21) = '0' then
                                    -- [not a return]
                                    -- get imm32
                                    address_out <= reg_pc;
                                    reg_pc_next <= reg_pc + 4;
                                else
                                    -- [a return]
                                    -- load address from stack
                                    select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                                    address_out <= i_reg_b_data;
                                    data_fetch_en <= '1';

                                    -- increase the stack pointer
                                    select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                                    select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                                    reg_write_en <= '1';

                                    alu_reg_a_en <= '1';
                                    alu_b_data <= to_unsigned(4, alu_b_data'length);
                                    alu_operation <= ALU_OP_ADD;
                                end if;

                                if reg_instruction(22) = '1' then
                                    -- [a call]
                                    -- descrease stack pointer
                                    select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                                    select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                                    reg_write_en <= '1';

                                    alu_reg_a_en <= '1';
                                    alu_b_data <= to_unsigned(4, alu_b_data'length);
                                    alu_operation <= ALU_OP_SUB;
                                end if;
                            else
                                -- [a near jump]
                                if reg_instruction(22) = '0' then
                                    -- [not a call]
                                    -- set PC to a new relative address

                                    -- HACK: technically ALU could be used, but it
                                    -- takes 3 clock cycles (output PC > add imm16 > input PC)
                                    reg_pc_next <= unsigned(signed(reg_pc) + signed(reg_instruction(15 downto 0)));
                                else
                                    -- [a call]
                                    -- decrease the stack pointer
                                    select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                                    select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                                    reg_write_en <= '1';
                                    
                                    alu_reg_a_en <= '1';
                                    alu_b_data <= to_unsigned(4, alu_b_data'length);
                                    alu_operation <= ALU_OP_SUB;
                                end if;
                            end if;
                        end if;

                    when OPCODE_INT =>
                        int_instruction_irq <= '1';
                        int_instruction_num <= unsigned(reg_instruction(21 downto 16));

                    when OPCODE_IRET =>
                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '1' then
                            -- pop PC
                            -- load address from stack
                            select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                            address_out <= i_reg_b_data;
                            memory_request <= '1';
                            data_fetch_en <= '1';

                            -- increase the stack pointer
                            select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                            select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                            reg_write_en <= '1';

                            alu_reg_a_en <= '1';
                            alu_b_data <= to_unsigned(4, alu_b_data'length);
                        else
                            -- IRET is only allowed in kernel mode
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        end if;

                    when OPCODE_HLT =>
                        null;

                    when OPCODE_IN =>
                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '1' then
                            select_reg_w <= unsigned(reg_instruction(15 downto 12));
                            reg_write_en <= '1';

                            alu_b_data <= i_port_data;
                            alu_operation <= ALU_OP_PASS_B;

                            update_alu_flags_en <= '1';

                            port_number <= unsigned(reg_instruction(23 downto 16));
                            port_request_en <= '1';
                            -- TODO: A bad idea? Should answer really come in the same clock cycle?
                            -- Eventually add "port_ready" signal
                        else
                            -- IN is only allowed in kernel mode
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        end if;

                    when OPCODE_OUT =>
                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '1' then
                            select_reg_b <= unsigned(reg_instruction(15 downto 12));

                            port_data_out <= i_reg_b_data;
                            port_number <= unsigned(reg_instruction(23 downto 16));
                            port_write_en <= '1';
                            port_request_en <= '1';
                        else
                            -- OUT is only allowed in kernel mode
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        end if;

                    when OPCODE_CLI =>
                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '1' then
                            special_regs_data_in <= reg_special_regs(REGISTER_CR0_I-16);
                            special_regs_data_in(0) <= '0';
                            special_regs_select <= to_unsigned(REGISTER_CR0_I-16, special_regs_select'length);
                            special_regs_write_en <= '1';
                        else
                            -- CLI is only allowed in kernel mode
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        end if;

                    when OPCODE_STI =>
                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '1' then
                            special_regs_data_in <= reg_special_regs(REGISTER_CR0_I-16);
                            special_regs_data_in(0) <= '1';
                            special_regs_select <= to_unsigned(REGISTER_CR0_I-16, special_regs_select'length);
                            special_regs_write_en <= '1';
                        else
                            -- STI is only allowed in kernel mode
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        end if;

                    when others =>
                        int_instruction_irq <= '1';
                        int_instruction_num <= to_unsigned(INTNUM_INST_INVALID, int_instruction_num'length);
                        null;

                end case;

                -- ALU operation
                case opcode is
                    when OPCODE_ADD_RR | OPCODE_ADD_R16 | OPCODE_POP | OPCODE_IRET =>
                        alu_operation <= ALU_OP_ADD;

                    when OPCODE_ADC_RR | OPCODE_ADC_R16 =>
                        alu_operation <= ALU_OP_ADC;

                    when OPCODE_SUB_RR | OPCODE_SUB_R16 | OPCODE_CMP_RR |
                            OPCODE_PUSH_R | OPCODE_PUSH_32 =>
                        alu_operation <= ALU_OP_SUB;

                    when OPCODE_SBB_RR | OPCODE_SBB_R16 =>
                        alu_operation <= ALU_OP_SBB;

                    when OPCODE_MUL_RR | OPCODE_UMUL_RR =>
                        alu_operation <= ALU_OP_MUL_LU;

                    when OPCODE_SMUL_RR =>
                        alu_operation <= ALU_OP_MUL_LS;

                    when OPCODE_AND_RR =>
                        alu_operation <= ALU_OP_AND;

                    when OPCODE_OR_RR =>
                        alu_operation <= ALU_OP_OR;

                    when OPCODE_XOR_RR =>
                        alu_operation <= ALU_OP_XOR;

                    when OPCODE_SHR =>
                        alu_operation <= ALU_OP_SHLR;

                    when OPCODE_SAR =>
                        alu_operation <= ALU_OP_SHAR;

                    when others =>
                        null;
                end case;

            when EXECUTE2 =>
                case opcode is
                    when OPCODE_ADD_R32 | OPCODE_ADC_R32 | OPCODE_SUB_R32 | OPCODE_SBB_R32 |
                            OPCODE_MUL_R32 | OPCODE_AND_R32 | OPCODE_OR_R32 | OPCODE_XOR_R32 =>
                        select_reg_w <= unsigned(reg_instruction(23 downto 20));
                        select_reg_a <= unsigned(reg_instruction(19 downto 16));
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_b_data <= reg_fetched_data;

                        update_alu_flags_en <= '1';

                    when OPCODE_CMP_R32 =>
                        select_reg_a <= unsigned(reg_instruction(19 downto 16));

                        alu_reg_a_en <= '1';
                        alu_b_data <= reg_fetched_data;

                        update_alu_flags_en <= '1';

                    when OPCODE_UMUL_RR | OPCODE_SMUL_RR =>
                        select_reg_w <= unsigned(reg_instruction(23 downto 20));
                        reg_write_en <= '1';

                        alu_operation <= ALU_OP_MUL_H;

                        update_alu_flags_en <= '1';

                    when OPCODE_UMUL_R32 | OPCODE_SMUL_R32 =>
                        select_reg_w <= unsigned(reg_instruction(19 downto 16));
                        select_reg_a <= unsigned(reg_instruction(15 downto 12));
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_b_data <= reg_fetched_data;

                        update_alu_flags_en <= '1';

                    when OPCODE_MOV_R32 =>
                        update_alu_flags_en <= '1';

                        if reg_special_regs(REGISTER_FLAGS_I-16)(4) = '0' and
                            unsigned(reg_instruction(23 downto 18)) > REGISTER_FLAGS_I then
                            -- MOV to registers beyond the FLAGS register in user mode is not allowed
                            int_instruction_irq <= '1';
                            int_instruction_num <= to_unsigned(INTNUM_PRIVILEGE_FAULT, int_instruction_num'length);
                        elsif unsigned(reg_instruction(23 downto 22)) = 0 then
                            select_reg_w <= unsigned(reg_instruction(21 downto 18));
                            reg_write_en <= '1';

                            alu_b_data <= reg_fetched_data;
                            alu_operation <= ALU_OP_PASS_B;
                        else
                            special_regs_select <= unsigned(reg_instruction(23 downto 22))-1 &
                                                    unsigned(reg_instruction(21 downto 18));
                            special_regs_data_in <= reg_fetched_data;
                            special_regs_write_en <= '1';
                        end if;

                    when OPCODE_LOAD | OPCODE_STORE =>
                        if unsigned(reg_instruction(9 downto 7)) = x"0" then
                            alu_b_data <= reg_fetched_data;
                            alu_operation <= ALU_OP_PASS_B;
                        else
                            select_reg_a <= unsigned(reg_instruction(19 downto 16));
                            shl_reg_a <= unsigned(reg_instruction(11 downto 10));
                            alu_reg_a_en <= '1';
                            alu_b_data <= reg_fetched_data;
                            alu_operation <= ALU_OP_ADD;
                        end if;

                    when OPCODE_PUSH_R =>
                        address_out <= i_calculated_address;
                        memory_request <= '1';
                        memory_write_en <= '1';
                        data_fetch_en <= '1';

                        select_reg_b <= unsigned(reg_instruction(23 downto 20));
                        data_out <= i_reg_b_data;

                    when OPCODE_PUSH_32 =>
                        select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                        address_out <= i_reg_b_data;
                        memory_request <= '1';
                        memory_write_en <= '1';
                        data_fetch_en <= '1';

                        data_out <= reg_fetched_data;

                    when OPCODE_POP =>
                        select_reg_w <= unsigned(reg_instruction(23 downto 20));
                        reg_write_en <= '1';

                        alu_b_data <= reg_fetched_data;
                        alu_operation <= ALU_OP_PASS_B;

                        update_alu_flags_en <= '1';

                    when OPCODE_JMP =>
                        if reg_instruction(23) = '0' then
                            -- [a far jump]
                            reg_pc_next <= reg_fetched_data;

                            if reg_instruction(22) = '1' then
                                -- [a call]
                                -- push PC
                                select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                                address_out <= i_reg_b_data;

                                data_out <= reg_pc;
                                memory_write_en <= '1';
                                memory_request <= '1';
                                data_fetch_en <= '1';
                            end if;
                        else
                            -- [a near jump]
                            -- [also will always be a call]

                            -- HACK: technically ALU could be used, but it
                            -- takes 3 clock cycles (output PC > add imm16 > input PC)
                            reg_pc_next <= unsigned(signed(reg_pc) + signed(reg_instruction(15 downto 0)));

                            -- push PC
                            address_out <= i_calculated_address;
                            data_out <= reg_pc;
                            memory_write_en <= '1';
                            memory_request <= '1';
                            data_fetch_en <= '1';
                        end if;

                    when OPCODE_IRET =>
                        -- save PC
                        reg_pc_next <= reg_fetched_data;

                        -- pop FLAGS
                        -- load flags from stack
                        select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                        address_out <= i_reg_b_data;
                        memory_request <= '1';
                        data_fetch_en <= '1';

                        -- increase the stack pointer
                        select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                        select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);
                        reg_write_en <= '1';

                        alu_reg_a_en <= '1';
                        alu_b_data <= to_unsigned(4, alu_b_data'length);

                    when others =>
                        null;
                end case;

                -- ALU operation
                case opcode is
                    when OPCODE_ADD_R32 | OPCODE_IRET =>
                        alu_operation <= ALU_OP_ADD;

                    when OPCODE_ADC_R32 =>
                        alu_operation <= ALU_OP_ADC;

                    when OPCODE_SUB_R32 | OPCODE_CMP_R32 =>
                        alu_operation <= ALU_OP_SUB;

                    when OPCODE_SBB_R32 =>
                        alu_operation <= ALU_OP_SBB;

                    when OPCODE_MUL_R32 | OPCODE_UMUL_R32 =>
                        alu_operation <= ALU_OP_MUL_LU;

                    when OPCODE_SMUL_R32 =>
                        alu_operation <= ALU_OP_MUL_LS;

                    when OPCODE_AND_R32 =>
                        alu_operation <= ALU_OP_AND;

                    when OPCODE_OR_R32 =>
                        alu_operation <= ALU_OP_OR;

                    when OPCODE_XOR_R32 =>
                        alu_operation <= ALU_OP_XOR;

                    when others =>
                        null;
                end case;

            when EXECUTE3 =>
                case opcode is
                    when OPCODE_UMUL_R32 | OPCODE_SMUL_R32 =>
                        select_reg_w <= unsigned(reg_instruction(23 downto 20));
                        reg_write_en <= '1';

                        alu_operation <= ALU_OP_MUL_H;

                        update_alu_flags_en <= '1';

                    when OPCODE_LOAD | OPCODE_STORE =>
                        if reg_fetch_by_load = '0' then
                            -- address calculation
                            select_reg_b <= unsigned(reg_instruction(15 downto 12));
                            
                            alu_reg_b_en <= '1';
                            alu_operation <= ALU_OP_ADD;
                        else
                            -- data save after load
                            select_reg_w <= unsigned(reg_instruction(23 downto 20));
                            reg_write_en <= '1';

                            alu_b_data <= reg_fetched_data;
                            alu_operation <= ALU_OP_PASS_B;

                            update_alu_flags_en <= '1';
                        end if;

                    when OPCODE_IRET =>
                        -- save FLAGS
                        update_alu_flags_en <= '1';

                        finished_int_execution <= '1';
                    
                    when others =>
                        null;
                end case;

            when ACCESS_MEMORY =>
                address_out <= i_calculated_address;
                memory_request <= '1';
                data_fetch_en <= '1';

                if opcode = OPCODE_STORE then
                    memory_write_en <= '1';
                else
                    memory_write_en <= '0';
                end if;

                -- for store (it doesn't conflict with load)
                select_reg_b <= unsigned(reg_instruction(23 downto 20));
                data_out <= i_reg_b_data;

            when INT_EXECUTE1 =>
                -- decrease stack pointer
                select_reg_a <= to_unsigned(REGISTER_SP_I, select_reg_a'length);

                alu_reg_a_en <= '1';
                alu_b_data <= to_unsigned(4, alu_b_data'length);
                alu_operation <= ALU_OP_SUB;

            when INT_EXECUTE2 =>
                -- decrease stack pointer once more
                -- (it was used last cycle -> auto fed to alu)
                select_reg_w <= to_unsigned(REGISTER_SP_I, select_reg_w'length);
                reg_write_en <= '1';

                alu_b_data <= to_unsigned(4, alu_b_data'length);
                alu_operation <= ALU_OP_SUB;

                -- push flags
                data_out <= reg_special_regs(REGISTER_FLAGS_I-16);
                address_out <= i_calculated_address;
                memory_request <= '1';
                memory_write_en <= '1';
                data_fetch_en <= '1';

            when INT_EXECUTE3 =>
                -- save address of the stack pointer for the next clock cycle
                select_reg_b <= to_unsigned(REGISTER_SP_I, select_reg_b'length);
                -- save address of the IVT entry for the next clock cycle
                alu_b_data <= reg_special_regs(REGISTER_IVTAR_I-16) + shift_left(reg_int_num, 2);

                alu_operation <= ALU_OP_PASS_B;

                -- select if the SP or IVTAR is output
                -- (IVTAR is needed for the next state, SP for current write to RAM)
                if i_memory_manager_rdy = '0' then
                    alu_reg_b_en <= '1';
                else
                    alu_reg_b_en <= '0';
                end if;

                -- push PC
                data_out <= reg_pc;
                address_out <= i_calculated_address;
                memory_request <= '1';
                memory_write_en <= '1';
                data_fetch_en <= '1';

            when INT_JUMP =>
                reg_pc_next <= reg_fetched_data;
                clear_int <= '1';

            when others =>
                null;
        end case;
    end process;

end architecture;