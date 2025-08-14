library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity memory_manager is
    port (
        i_clk   : in std_logic;
        i_reset : in std_logic;
        
        -- from control unit
        i_address : in std_logic_vector(31 downto 0);
        i_memory_request : in std_logic;
        i_write_data : in unsigned(31 downto 0);
        i_memory_write_en : in std_logic;
        i_data_fetch_en : in std_logic;
        i_paging_en : in std_logic;
        i_privilege_mode : in std_logic;
        i_page_directory_address : in unsigned(19 downto 0);
        
        i_port_num : in unsigned(7 downto 0);
        i_port_data : in unsigned(31 downto 0);
        i_port_req : in std_logic;
        i_port_write_en : in std_logic;

        -- from outside
        i_fetch_data : in unsigned(31 downto 0);
        i_memory_rdy : in std_logic;

        -- to control unit
        o_fetch_data : out unsigned(31 downto 0);
        o_memory_manager_rdy : out std_logic;
        o_fetch_data_rdy : out std_logic;
        o_page_fault : out std_logic;

        o_port_data : out unsigned(31 downto 0);

        -- to cache
        o_address : out std_logic_vector(31 downto 0);
        o_memory_request : out std_logic;
        o_write_data : out unsigned(31 downto 0);
        o_memory_write_en : out std_logic;
        o_data_fetch_en : out std_logic;
        o_memory_ram_en : out std_logic
    );
end entity;

architecture rtl of memory_manager is

    -- Constants
    constant NUM_TLB_ENTRIES : positive := 16;

    -- Types
    type t_memory_manager_state is (READY, WAIT_ON_DIR_ENTRY, WAIT_ON_TABLE_ENTRY, WAIT_ON_DATA);
    type t_tlb_entry is record
        pd_index : unsigned(9 downto 0);
        pt_index : unsigned(9 downto 0);
        frame : std_logic_vector(19 downto 0);
        global : std_logic;
        user_en : std_logic;
        exec_en : std_logic;
        write_en : std_logic;
        valid : std_logic;
    end record;
    type t_tlb is array(0 to NUM_TLB_ENTRIES-1) of t_tlb_entry;
    type t_tlb_lru is array(0 to NUM_TLB_ENTRIES-1) of unsigned(f_log2(NUM_TLB_ENTRIES)-1 downto 0);

    -- Constants
    constant EMPTY_TLB_ENTRY : t_tlb_entry := (
        pd_index => (others => '0'),
        pt_index => (others => '0'),
        frame => (others => '0'),
        global => '0',
        user_en => '0',
        exec_en => '0',
        write_en => '0',
        valid => '0'
    );

    -- Registers
    signal s_memory_manager : t_memory_manager_state;
    signal s_memory_manager_next : t_memory_manager_state;

    signal reg_address : std_logic_vector(31 downto 0);
    signal reg_address_next : std_logic_vector(31 downto 0);

    signal reg_write_data : unsigned(31 downto 0);
    signal reg_write_data_next : unsigned(31 downto 0);

    signal reg_memory_write_en : std_logic;
    signal reg_memory_write_en_next : std_logic;

    signal reg_data_fetch_en : std_logic;
    signal reg_data_fetch_en_next : std_logic;

    signal reg_memory_ram_en : std_logic;
    signal reg_memory_ram_en_next : std_logic;

    signal reg_ram_depth : unsigned(31 downto 0);
    signal reg_ram_depth_next : unsigned(31 downto 0);

    signal reg_tlb : t_tlb;
    signal reg_tlb_next : t_tlb;

    signal reg_fetched_address : std_logic_vector(19 downto 0);         -- the upper 20 bits of page table and frame address
    signal reg_fetched_address_next : std_logic_vector(19 downto 0);

    signal reg_tlb_lru : t_tlb_lru;
    signal reg_tlb_lru_next : t_tlb_lru;

    signal reg_page_directory_address : unsigned(19 downto 0);      -- used to check if the page directory address got changed

    -- TLB
    signal tlb_hit : std_logic;
    signal tlb_entry_num : unsigned(f_log2(NUM_TLB_ENTRIES)-1 downto 0);
    signal tlb_entry : t_tlb_entry;     -- used for easier access to the 'hit' entry

    -- Outputs
    signal fetch_data : unsigned(31 downto 0);
    signal memory_manager_rdy : std_logic;
    signal fetch_data_rdy : std_logic;
    signal page_fault : std_logic;

    signal port_data_out : unsigned(31 downto 0);

    signal address : std_logic_vector(31 downto 0);
    signal memory_request : std_logic;
    signal write_data : unsigned(31 downto 0);
    signal memory_write_en : std_logic;
    signal memory_data_fetch_en : std_logic;
    signal memory_ram_en : std_logic;

    -- Misc
    signal enable_ram : std_logic;
    signal page_fault_flags : std_logic_vector(3 downto 0);

begin

    -- Default assignments
    tlb_entry <= reg_tlb(to_integer(tlb_entry_num));

    -- Outputs
    o_fetch_data <= fetch_data;
    o_memory_manager_rdy <= memory_manager_rdy;
    o_fetch_data_rdy <= fetch_data_rdy;
    o_page_fault <= page_fault and i_paging_en;

    o_port_data <= reg_ram_depth;

    o_address <= address;
    o_memory_request <= memory_request;
    o_write_data <= write_data;
    o_memory_write_en <= memory_write_en;
    o_data_fetch_en <= memory_data_fetch_en;
    o_memory_ram_en <= memory_ram_en;

    -- Misc
    enable_ram <= '1' when unsigned(i_address) < reg_ram_depth else '0';

    -- Clocked process
    prs_seq : process (i_clk, i_reset)
    begin
        if i_reset = '1' then

            s_memory_manager <= READY;

            reg_write_data <= (others => '0');
            reg_address <= (others => '0');
            reg_memory_write_en <= '0';
            reg_data_fetch_en <= '0';
            reg_memory_ram_en <= '0';

            reg_ram_depth <= (others => '0');

            for i in 0 to NUM_TLB_ENTRIES-1 loop
                reg_tlb(i).global <= '0';
                reg_tlb(i).valid <= '0';
            end loop;

            reg_fetched_address <= (others => '0');

            for i in 0 to NUM_TLB_ENTRIES-1 loop
                reg_tlb_lru(i) <= to_unsigned(i, reg_tlb_lru(i)'length);
            end loop;

            reg_page_directory_address <= (others => '0');

        elsif rising_edge(i_clk) then

            s_memory_manager <= s_memory_manager_next;

            reg_write_data <= reg_write_data_next;
            reg_address <= reg_address_next;
            reg_memory_write_en <= reg_memory_write_en_next;
            reg_data_fetch_en <= reg_data_fetch_en_next;
            reg_memory_ram_en <= reg_memory_ram_en_next;

            reg_ram_depth <= reg_ram_depth_next;

            reg_tlb <= reg_tlb_next;

            reg_fetched_address <= reg_fetched_address_next;

            reg_tlb_lru <= reg_tlb_lru_next;

            reg_page_directory_address <= i_page_directory_address;

        end if;
    end process;

    -- RAM depth process
    prs_ram_depth : process(all)
    begin
        reg_ram_depth_next <= reg_ram_depth;

        if i_port_req = '1' and i_port_num = MEMMGR_RAM_DEPTH_IO and i_port_write_en = '1' then
            reg_ram_depth_next <= i_port_data;
        end if;
    end process;

    -- TLB hit and entry number process
    prs_hit : process(all)
        variable entry_hit : std_logic_vector(0 to NUM_TLB_ENTRIES-1);
    begin
        tlb_entry_num <= (others => '0');

        for i in 0 to NUM_TLB_ENTRIES-1 loop
            if reg_tlb(i).pd_index = unsigned(i_address(31 downto 22)) and
                reg_tlb(i).pt_index = unsigned(i_address(21 downto 12)) and
                reg_tlb(i).valid = '1' then
                    entry_hit(i) := '1';
                    tlb_entry_num <= to_unsigned(i, tlb_entry_num'length);
            else
                entry_hit(i) := '0';
            end if;
        end loop;

        tlb_hit <= or entry_hit;
    end process;

    -- Conditions check process
    prs_page_fault : process(all)
    begin
        page_fault <= '0';
        page_fault_flags <= (others => '0');

        if tlb_hit = '1' then
            -- the page is present if there is a hit in the TLB
            page_fault_flags(0) <= '1';

            -- write to a read-only page?
            if i_memory_write_en = '1' and tlb_entry.write_en = '0' then
                page_fault_flags(1) <= '1';
                page_fault <= '1';
            end if;

            -- execute from a non-executable page?
            if i_data_fetch_en = '0' and tlb_entry.exec_en = '0' then
                page_fault_flags(2) <= '1';
                page_fault <= '1';
            end if;

            -- kernel page access from user-mode?
            if i_privilege_mode = '0' and tlb_entry.user_en = '0' then
                page_fault_flags(3) <= '1';
                page_fault <= '1';
            end if;
        end if;

        if i_memory_rdy = '1' then
            if s_memory_manager = WAIT_ON_DIR_ENTRY then
                if i_fetch_data(0) = '0' then
                    page_fault <= '1';
                    page_fault_flags <= (others => '0');
                end if;
            elsif s_memory_manager = WAIT_ON_TABLE_ENTRY then
                page_fault_flags <= (others => '0');

                -- is the page present?
                if i_fetch_data(0) = '1' then
                    page_fault_flags(0) <= '1';     -- if yes, it's not a fault but has to be "noted"
                else
                    page_fault <= '1';      -- if not then it's a fault
                end if;

                -- write to a read-only page?
                if i_memory_write_en = '1' and i_fetch_data(1) = '0' then
                    page_fault <= '1';
                    page_fault_flags(1) <= '1';
                end if;

                -- execute from a non-executable page?
                if i_data_fetch_en = '0' and i_fetch_data(2) = '0' then
                    page_fault <= '1';
                    page_fault_flags(2) <= '1';
                end if;

                -- kernel page access from user-mode?
                if i_privilege_mode = '0' and i_fetch_data(3) = '0' then
                    page_fault <= '1';
                    page_fault_flags(3) <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Find the accessed TLB entry, put it to the top of the LRU queue
    -- and shift all entries after it one place lower
    prs_tlb_lru_sort : process(all)
        variable index : unsigned(f_log2(NUM_TLB_ENTRIES)-1 downto 0);
    begin
        reg_tlb_lru_next <= reg_tlb_lru;

        -- find the index of the hit TLB entry
        for i in 0 to NUM_TLB_ENTRIES-1 loop
            if reg_tlb_lru(i) = tlb_entry_num then
                index := to_unsigned(i, index'length);
            end if;
        end loop;

        -- shift the entries in the LRU queue
        -- (only during READY state, because inputs change in the following clock cycle)
        if i_memory_request = '1' and tlb_hit = '1' and page_fault = '0' and s_memory_manager = READY then
            for i in to_integer(index) to NUM_TLB_ENTRIES-1 loop
                reg_tlb_lru_next(i) <= reg_tlb_lru(i+1);
            end loop;

            -- put the accessed entry number to the top
            reg_tlb_lru_next(reg_tlb_lru_next'length-1) <= reg_tlb_lru(to_integer(index));
        end if;
    end process;

    -- Adds and removes stuff from the TLB
    prs_tlb : process(all)
    begin
        reg_tlb_next <= reg_tlb;

        -- save the newly accessed entry (after a TLB miss)
        if s_memory_manager = WAIT_ON_TABLE_ENTRY and i_memory_rdy = '1' and page_fault = '0' then
            reg_tlb_next(to_integer(reg_tlb_lru(0))) <= (
                pd_index => unsigned(reg_address(31 downto 22)),
                pt_index => unsigned(reg_address(21 downto 12)),
                frame => std_logic_vector(i_fetch_data(31 downto 12)),
                global => i_fetch_data(4),
                user_en => i_fetch_data(3),
                exec_en => i_fetch_data(2),
                write_en => i_fetch_data(1),
                valid => '1'
            );
        end if;

        -- flush the TLB after change in the page directory address (probably a new process is about to start)
        if i_page_directory_address /= reg_page_directory_address then
            for i in 0 to NUM_TLB_ENTRIES-1 loop
                if reg_tlb(i).global = '0' then
                    reg_tlb_next(i).valid <= '0';
                end if;
            end loop;
        end if;

        -- manual flushing TLB
        if i_port_req = '1' and i_port_num = MEMMGR_FLUSH_TLB_IO then
            for i in 0 to NUM_TLB_ENTRIES-1 loop
                reg_tlb_next(i).valid <= '0';
            end loop;
        end if;

        -- evicting a specific entry
        if i_port_req = '1' and i_port_num = MEMMGR_EVICT_TLB_ENTRY_IO then
            for i in 0 to NUM_TLB_ENTRIES-1 loop
                if reg_tlb(i).pd_index = unsigned(i_address(31 downto 22)) and reg_tlb(i).pt_index = unsigned(i_address(21 downto 12)) then
                    reg_tlb_next(i).valid <= '0';
                end if;
            end loop;
        end if;
    end process;

    -- States process
    prs_fsm : process (all)
    begin
        s_memory_manager_next <= s_memory_manager;

        case s_memory_manager is
            when READY =>
                if i_memory_request = '1' then
                    if tlb_hit = '1' then
                        if page_fault = '0' then
                            s_memory_manager_next <= WAIT_ON_DATA;
                        end if;
                    else
                        s_memory_manager_next <= WAIT_ON_DIR_ENTRY;
                    end if;
                    if i_paging_en = '0' then
                        s_memory_manager_next <= WAIT_ON_DATA;
                    end if;
                end if;

            when WAIT_ON_DIR_ENTRY =>
                if i_memory_rdy = '1' then
                    if page_fault = '0' then
                        s_memory_manager_next <= WAIT_ON_TABLE_ENTRY;
                    else
                        s_memory_manager_next <= READY;
                    end if;
                end if;

            when WAIT_ON_TABLE_ENTRY =>
                if i_memory_rdy = '1' then
                    if page_fault = '0' then
                        s_memory_manager_next <= WAIT_ON_DATA;
                    else
                        s_memory_manager_next <= READY;
                    end if;
                end if;

            when WAIT_ON_DATA =>
                if i_memory_rdy = '1' then
                    s_memory_manager_next <= READY;
                end if;
            
            when others =>
                s_memory_manager_next <= READY;
        end case;
    end process;

    -- Outputs process
    prs_outputs : process (all)
    begin
        -- Default assignments
        address <= reg_address;
        memory_request <= '0';
        write_data <= reg_write_data;
        memory_write_en <= reg_memory_write_en;
        memory_data_fetch_en <= reg_data_fetch_en;
        memory_ram_en <= reg_memory_ram_en;

        fetch_data <= i_fetch_data;
        memory_manager_rdy <= '0';
        fetch_data_rdy <= '0';

        reg_address_next <= reg_address;
        reg_write_data_next <= reg_write_data;
        reg_memory_ram_en_next <= reg_memory_write_en;
        reg_data_fetch_en_next <= reg_data_fetch_en;
        reg_memory_ram_en_next <= reg_memory_ram_en;

        reg_fetched_address_next <= reg_fetched_address;

        case s_memory_manager is
            when READY =>
                memory_manager_rdy <= '1';

                -- these can be always set, the important ones are below in the if-statements
                write_data <= i_write_data;
                memory_write_en <= i_memory_write_en;
                memory_data_fetch_en <= i_data_fetch_en;
                memory_ram_en <= enable_ram;

                reg_address_next <= i_address;
                reg_write_data_next <= i_write_data;
                reg_memory_write_en_next <= i_memory_write_en;
                reg_data_fetch_en_next <= i_data_fetch_en;
                reg_memory_ram_en_next <= enable_ram;

                if i_paging_en = '0' then
                    address <= i_address;
                    memory_request <= i_memory_request;
                else
                    if page_fault = '0' then
                        if tlb_hit = '1' then
                            address(31 downto 12) <= tlb_entry.frame;
                            address(11 downto 0) <= i_address(11 downto 0);
                            memory_request <= i_memory_request;
                        else
                            address(31 downto 12) <= std_logic_vector(i_page_directory_address);
                            address(11 downto 0) <= i_address(31 downto 22);
                            memory_request <= i_memory_request;
                            memory_write_en <= '0';
                            memory_data_fetch_en <= '1';
                        end if;
                    else
                        fetch_data(31 downto page_fault_flags'length) <= (others => '0');
                        fetch_data(page_fault_flags'length-1 downto 0) <= unsigned(page_fault_flags);
                    end if;
                end if;

            when WAIT_ON_DIR_ENTRY =>
                address(31 downto 12) <= std_logic_vector(i_page_directory_address);
                address(11 downto 0) <= reg_address(31 downto 22);
                memory_request <= '1';
                memory_write_en <= '0';
                memory_data_fetch_en <= '1';

                if i_memory_rdy = '1' then
                    reg_fetched_address_next <= std_logic_vector(i_fetch_data(31 downto 12));
                end if;

            when WAIT_ON_TABLE_ENTRY =>
                address(31 downto 12) <= reg_fetched_address;
                address(11 downto 0) <= reg_address(21 downto 12);
                memory_request <= '1';
                memory_write_en <= '0';
                memory_data_fetch_en <= '1';

                if i_memory_rdy = '1' then
                    if page_fault = '0' then
                        reg_address_next(31 downto 12) <= std_logic_vector(i_fetch_data(31 downto 12));
                    else
                        fetch_data(31 downto page_fault_flags'length) <= (others => '0');
                        fetch_data(page_fault_flags'length-1 downto 0) <= unsigned(page_fault_flags);
                    end if;
                end if;

            when WAIT_ON_DATA =>
                memory_request <= '1';

                fetch_data <= i_fetch_data;
                fetch_data_rdy <= i_memory_rdy;

            when others =>
                null;
        end case;
    end process;

end architecture;