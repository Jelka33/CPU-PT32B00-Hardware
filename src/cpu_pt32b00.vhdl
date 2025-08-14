library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity cpu_pt32b00 is
    port (
        i_clk   : in std_logic;
        i_reset : in std_logic;

        i_mem_data : in unsigned(31 downto 0);
        i_memory_rdy : in std_logic;

        i_port_data : in unsigned(31 downto 0);

        i_irq : in std_logic;
        i_int_num : in unsigned(2 downto 0);

        o_mem_address : out std_logic_vector(31 downto 0);
        o_mem_data : out unsigned(31 downto 0);
        o_mem_en : out std_logic;
        o_mem_write_en : out std_logic;
        o_mem_ram_en : out std_logic;

        o_port_number : out unsigned(7 downto 0);
        o_port_data : out unsigned(31 downto 0);
        o_port_en : out std_logic;
        o_port_write_en : out std_logic
    );
end entity;

architecture rtl of cpu_pt32b00 is

    -- Constants
    constant CACHE_LINE_DEPTH : natural := 64;       -- bytes per cache line
    constant NUMBER_SETS : natural := 0;             -- number of sets
    constant CACHE_LINES_PER_SET : natural := 1;     -- associative lines in every set

    -- Registers
    signal reg_calculated_address : unsigned(31 downto 0);
    signal reg_calculated_address_next : unsigned(31 downto 0);

    -- Connections to the control unit
    signal cu_data_in : unsigned(31 downto 0);
    signal memory_manager_rdy : std_logic;
    signal cu_fetch_data_rdy : std_logic;
    signal cu_page_fault : std_logic;

    signal cu_port_data_in : unsigned(31 downto 0);

    signal data_reg_b : unsigned(31 downto 0);

    signal alu_flags : std_logic_vector(3 downto 0);
    signal alu_calculated_address : unsigned(31 downto 0);

    signal select_reg_a : unsigned(3 downto 0);
    signal select_reg_b : unsigned(3 downto 0);
    signal select_reg_w : unsigned(3 downto 0);
    signal write_reg_en : std_logic;

    signal shl_reg_a : unsigned(1 downto 0);

    signal alu_reg_a_en : std_logic;
    signal alu_reg_b_en : std_logic;
    signal alu_operation : t_alu_operation;
    signal alu_b_data : unsigned(31 downto 0);

    signal cu_address : std_logic_vector(31 downto 0);
    signal cu_memory_request : std_logic;
    signal cu_data_out : unsigned(31 downto 0);
    signal cu_memory_write_en : std_logic;
    signal cu_data_fetch_en : std_logic;
    signal paging_memory_manager_en : std_logic;
    signal cu_privilege_mode : std_logic;
    signal cu_page_directory_address : unsigned(19 downto 0);

    signal cu_port_data_out : unsigned(31 downto 0);
    signal cu_port_number : unsigned(7 downto 0);
    signal cu_port_write_en : std_logic;
    signal cu_port_request_en : std_logic;

    -- Connections to the register file
    signal a_reg_out : unsigned(31 downto 0);
    signal b_reg_out : unsigned(31 downto 0);

    -- Connections to the ALU
    signal alu_a_in : unsigned(31 downto 0);
    signal alu_b_in : unsigned(31 downto 0);
    signal alu_result : unsigned(31 downto 0);

    -- Connections to the memory manager
    signal memmgr_data_in : unsigned(31 downto 0);
    signal memmgr_mem_rdy : std_logic;

    signal memmgr_address : std_logic_vector(31 downto 0);
    signal memmgr_mem_req : std_logic;
    signal memmgr_write_data : unsigned(31 downto 0);
    signal memmgr_write_en : std_logic;
    signal memmgr_data_fetch_en : std_logic;
    signal memmgr_ram_en : std_logic;

    signal memmgr_port_data_out : unsigned(31 downto 0);

    -- Connections to the cache controller
    signal cache_row_data_in : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal cache_row_metadata_in : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    signal cache_address_r : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
    signal cache_address_w : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
    signal cache_data_out : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal cache_write_en : std_logic;
    signal cache_data_metadata_out : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
    signal cache_write_metadata_en : std_logic;
    signal cache_inst_cache_en : std_logic;
    signal cache_data_cache_en : std_logic;

    -- Connections to the instruction cache memory
    signal inst_cache_write_en : std_logic;
    signal inst_cache_metadata_write_en : std_logic;
    signal inst_cache_row_data : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal inst_cache_row_metadata : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    -- Connections to the data cache memory
    signal data_cache_write_en : std_logic;
    signal data_cache_metadata_write_en : std_logic;
    signal data_cache_row_data : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal data_cache_row_metadata : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

    -- Outputs
    signal mem_address_out : std_logic_vector(31 downto 0);
    signal mem_en_out : std_logic;
    signal mem_data_out : unsigned(31 downto 0);
    signal mem_write_en_out : std_logic;
    signal mem_ram_en_out : std_logic;

begin

    -- Outputs
    o_mem_address <= mem_address_out;
    o_mem_data <= mem_data_out;
    o_mem_en <= mem_en_out;
    o_mem_write_en <= mem_write_en_out;
    o_mem_ram_en <= mem_ram_en_out;

    o_port_number <= cu_port_number;
    o_port_data <= cu_port_data_out;
    o_port_en <= cu_port_request_en;
    o_port_write_en <= cu_port_write_en;

    u_control_unit : entity work.control_unit(rtl)
        port map (
            i_clk => i_clk,
            i_reset => i_reset,

            i_data => cu_data_in,
            i_memory_manager_rdy => memory_manager_rdy,
            i_fetch_data_rdy => cu_fetch_data_rdy,
            i_page_fault => cu_page_fault,

            i_port_data => cu_port_data_in,

            i_reg_b_data => data_reg_b,

            i_alu_flags => alu_flags,
            i_calculated_address => alu_calculated_address,

            i_irq => i_irq,
            i_irq_num => i_int_num,

            o_select_reg_a => select_reg_a,
            o_select_reg_b => select_reg_b,
            o_select_reg_w => select_reg_w,
            o_reg_write_en => write_reg_en,

            o_shl_reg_a => shl_reg_a,

            o_alu_reg_a_en => alu_reg_a_en,
            o_alu_reg_b_en => alu_reg_b_en,
            o_alu_operation => alu_operation,
            o_alu_b_data => alu_b_data,

            o_address => cu_address,
            o_memory_request => cu_memory_request,
            o_data => cu_data_out,
            o_memory_write_en => cu_memory_write_en,
            o_data_fetch_en => cu_data_fetch_en,
            o_paging_en => paging_memory_manager_en,
            o_privilege_mode => cu_privilege_mode,
            o_page_directory_address => cu_page_directory_address,

            o_port_data => cu_port_data_out,
            o_port_number => cu_port_number,
            o_port_write_en => cu_port_write_en,
            o_port_request_en => cu_port_request_en
        );

    data_reg_b <= b_reg_out;
    alu_calculated_address <= reg_calculated_address;
    
    u_register_file : entity work.register_file(rtl)
        port map(
            i_clk => i_clk,
            i_reset => i_reset,

            i_write_data => alu_result,
            i_sel_reg_a => select_reg_a,
            i_sel_reg_b => select_reg_b,
            i_sel_reg_w => select_reg_w,
            i_write_reg_en => write_reg_en,

            o_reg_a => a_reg_out,
            o_reg_b => b_reg_out
        );

    u_alu : entity work.alu(rtl)
        port map(
            i_clk => i_clk,

            i_a_operand => alu_a_in,
            i_b_operand => alu_b_in,
            i_operation => alu_operation,
            i_last_carry => '0',

            o_flags => alu_flags,
            o_result => alu_result
        );

    alu_a_in <= shift_left(a_reg_out, to_integer(shl_reg_a)) when alu_reg_a_en = '1' else reg_calculated_address;
    alu_b_in <= b_reg_out when alu_reg_b_en = '1' else alu_b_data;
    reg_calculated_address_next <= alu_result;

    u_memory_manager : entity work.memory_manager(rtl)
        port map(
            i_clk => i_clk,
            i_reset => i_reset,

            i_address => cu_address,
            i_memory_request => cu_memory_request,
            i_write_data => cu_data_out,
            i_memory_write_en => cu_memory_write_en,
            i_data_fetch_en => cu_data_fetch_en,
            i_paging_en => paging_memory_manager_en,
            i_privilege_mode => cu_privilege_mode,
            i_page_directory_address => cu_page_directory_address,

            i_port_num => cu_port_number,
            i_port_data => cu_port_data_out,
            i_port_req => cu_port_request_en,
            i_port_write_en => cu_port_write_en,

            i_fetch_data => i_mem_data,
            i_memory_rdy => i_memory_rdy,

            o_fetch_data => cu_data_in,
            o_memory_manager_rdy => memory_manager_rdy,
            o_fetch_data_rdy => cu_fetch_data_rdy,

            o_port_data => memmgr_port_data_out,

            o_address => memmgr_address,
            o_memory_request => memmgr_mem_req,
            o_write_data => memmgr_write_data,
            o_memory_write_en => memmgr_write_en,
            o_data_fetch_en => memmgr_data_fetch_en,
            o_memory_ram_en => memmgr_ram_en
        );

    u_cache_controller : entity work.cache_controller(rtl)
        generic map(
            CACHE_LINE_DEPTH => CACHE_LINE_DEPTH,
            NUMBER_SETS => NUMBER_SETS,
            CACHE_LINES_PER_SET => CACHE_LINES_PER_SET
        )
        port map(
            i_clk => i_clk,
            i_reset => i_reset,

            -- from control unit
            i_port_req => cu_port_request_en,
            i_port_number => cu_port_number,
            i_port_data => cu_port_data_out,

            -- from memory manager
            i_address => memmgr_address,
            i_write_data => memmgr_write_data,
            i_request => memmgr_mem_req,
            i_write_en => memmgr_write_en,
            i_ram_en => memmgr_ram_en,
            i_data_fetch_en => memmgr_data_fetch_en,

            -- from cache memory
            i_cache_row_data => cache_row_data_in,
            i_cache_row_metadata => cache_row_metadata_in,

            -- from outside
            i_fetch_data => i_mem_data,
            i_memory_rdy => i_memory_rdy,

            -- to memory manager
            o_fetch_data => memmgr_data_in,
            o_cache_rdy => memmgr_mem_rdy,

            -- to cache memory
            o_cache_address_r => cache_address_r,
            o_cache_address_w => cache_address_w,
            o_cache_data => cache_data_out,
            o_cache_write_en => cache_write_en,
            o_cache_data_metadata => cache_data_metadata_out,
            o_cache_write_metadata_en => cache_write_metadata_en,
            o_cache_inst_cache_en => cache_inst_cache_en,
            o_cache_data_cache_en => cache_data_cache_en,

            -- to outside
            o_address => mem_address_out,
            o_write_data => mem_data_out,
            o_request => mem_en_out,
            o_write_en => mem_write_en_out,
            o_ram_en => mem_ram_en_out
        );

    cache_row_data_in <= inst_cache_row_data when cache_data_cache_en = '0' else data_cache_row_data;
    cache_row_metadata_in <= inst_cache_row_metadata when cache_data_cache_en = '0' else data_cache_row_metadata;

    u_instruction_cache_memory : entity work.instruction_cache_memory(rtl)
        generic map(
            CACHE_LINE_DEPTH => CACHE_LINE_DEPTH,
            NUMBER_SETS => NUMBER_SETS,
            CACHE_LINES_PER_SET => CACHE_LINES_PER_SET
        )
        port map(
            i_clk => i_clk,
            i_address_r => cache_address_r(cache_address_r'length-1 downto 2),
            i_address_w => cache_address_w(cache_address_w'length-1 downto 2),
            i_data => cache_data_out,
            i_write_cache_en => inst_cache_write_en,
            i_data_metadata => cache_data_metadata_out,
            i_write_metadata_en => inst_cache_metadata_write_en,
            o_row_data => inst_cache_row_data,
            o_row_metadata => inst_cache_row_metadata
        );

    inst_cache_write_en <= cache_write_en when cache_inst_cache_en = '1' else '0';
    inst_cache_metadata_write_en <= cache_write_metadata_en when cache_inst_cache_en = '1' else '0';

    u_data_cache_memory : entity work.data_cache_memory(rtl)
        generic map(
            CACHE_LINE_DEPTH => CACHE_LINE_DEPTH,
            NUMBER_SETS => NUMBER_SETS,
            CACHE_LINES_PER_SET => CACHE_LINES_PER_SET
        )
        port map(
            i_clk => i_clk,
            i_address_r => cache_address_r,
            i_address_w => cache_address_w,
            i_data => cache_data_out,
            i_write_cache_en => data_cache_write_en,
            i_data_metadata => cache_data_metadata_out,
            i_write_metadata_en => data_cache_metadata_write_en,
            o_row_data => data_cache_row_data,
            o_row_metadata => data_cache_row_metadata
        );

    data_cache_write_en <= cache_write_en when cache_data_cache_en = '1' else '0';
    data_cache_metadata_write_en <= cache_write_metadata_en when cache_data_cache_en = '1' else '0';

    -- Clocked process
    prs_seq : process (i_clk, i_reset)
    begin
        if i_reset = '1' then
            reg_calculated_address <= (others => '0');
        elsif rising_edge(i_clk) then
            reg_calculated_address <= reg_calculated_address_next;
        end if;
    end process;

    -- Port I/O input process
    prs_port_io_input : process(all)
    begin
        cu_port_data_in <= i_port_data;

        case cu_port_number is
            when to_unsigned(MEMMGR_RAM_DEPTH_IO, cu_port_number'length) =>
                cu_port_data_in <= memmgr_port_data_out;

            when others =>
                null;
        end case;
    end process;

end architecture;