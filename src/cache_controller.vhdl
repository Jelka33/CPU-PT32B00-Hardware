library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.cpu_pt32b00_package.all;

entity cache_controller is
    generic (
        CACHE_LINE_DEPTH : natural := 64;       -- bytes per cache line
        NUMBER_SETS : natural := 0;             -- number of sets
        CACHE_LINES_PER_SET : natural := 1      -- associative lines in every set
    );
    port (
        i_clk   : in std_logic;
        i_reset : in std_logic;

        -- from control unit
        i_port_req : std_logic;
        i_port_number : unsigned(7 downto 0);
        i_port_data : unsigned(31 downto 0);    -- always assume write

        -- from memory manager
        i_address : in std_logic_vector(31 downto 0);
        i_write_data : in unsigned(31 downto 0);
        i_request : in std_logic;
        i_write_en : in std_logic;
        i_ram_en : in std_logic;
        i_data_fetch_en : in std_logic;

        -- from cache memory
        i_cache_row_data : in t_cache_row(0 to CACHE_LINES_PER_SET-1);
        i_cache_row_metadata : in t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);

        -- from outside
        i_fetch_data : in unsigned(31 downto 0);
        i_memory_rdy : in std_logic;

        -- to memory manager
        o_fetch_data : out unsigned(31 downto 0);
        o_cache_rdy : out std_logic;

        -- to cache memory
        o_cache_address_r : out std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
        o_cache_address_w : out std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
        o_cache_data : out t_cache_row(0 to CACHE_LINES_PER_SET-1);
        o_cache_write_en : out std_logic;
        o_cache_data_metadata : out t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
        o_cache_write_metadata_en : out std_logic;
        o_cache_inst_cache_en : out std_logic;
        o_cache_data_cache_en : out std_logic;

        -- to outside
        o_address : out std_logic_vector(31 downto 0);
        o_write_data : out unsigned(31 downto 0);
        o_request : out std_logic;
        o_write_en : out std_logic;
        o_ram_en : out std_logic
    );
end entity;

architecture rtl of cache_controller is

    -- Types
    type t_cache_controller_state is (RESET, READY, READ, WRITE, FETCH, WRITE_TO_RAM, WAIT_FOR_MMIO, EVICT);
    type t_cache_lru_ram is array(0 to NUMBER_SETS-1) of std_logic_vector(f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET-1 downto 0);
    type t_cache_lru_ram_output is array(0 to CACHE_LINES_PER_SET-1) of unsigned(f_log2(CACHE_LINES_PER_SET)-1 downto 0);

    -- Functions
    function f_fill_lru_ram return t_cache_lru_ram is
        variable output : t_cache_lru_ram;
    begin
        for i in 0 to output'length-1 loop
            for j in 0 to CACHE_LINES_PER_SET-1 loop
                output(i)(
                    (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-j*f_log2(CACHE_LINES_PER_SET)-1 downto
                    (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-j*f_log2(CACHE_LINES_PER_SET)-2
                ) := std_logic_vector(to_unsigned(j, f_log2(CACHE_LINES_PER_SET)));
            end loop;
        end loop;

        return output;
    end function;

    -- RAMs (inferred)
    signal inst_cache_lru_ram : t_cache_lru_ram := f_fill_lru_ram;
    signal data_cache_lru_ram : t_cache_lru_ram := f_fill_lru_ram;
    signal cache_lru_ram_write_data : t_cache_lru_ram_output;
    signal cache_lru_ram_write_en : std_logic;
    signal inst_cache_lru : t_cache_lru_ram_output;    -- the output of the RAM but easier to access
    signal data_cache_lru : t_cache_lru_ram_output;    -- the output of the RAM but easier to access
    signal cache_lru : t_cache_lru_ram_output;    -- the output of the selected RAM

    -- Registers
    signal s_cache_controller : t_cache_controller_state;
    signal s_cache_controller_next : t_cache_controller_state;

    signal reset_counter_reg : unsigned(f_log2(NUMBER_SETS)-1 downto 0);
    signal reset_counter_reg_next : unsigned(f_log2(NUMBER_SETS)-1 downto 0);

    signal req_address_reg : std_logic_vector(31 downto 0);
    signal req_address_reg_next : std_logic_vector(31 downto 0);

    signal word_counter_reg : unsigned(f_log2(CACHE_LINE_DEPTH/4)-1 downto 0);
    signal word_counter_reg_next : unsigned(f_log2(CACHE_LINE_DEPTH/4)-1 downto 0);

    signal addr_cacheline_misalignment_reg : std_logic;     -- turns on when the data lies in two cachelines
    signal addr_cacheline_misalignment_reg_next : std_logic;

    signal misaligned_data_reg : unsigned(23 downto 0);     -- only the first part of the data (so up to 3 bytes)
    signal misaligned_data_reg_next : unsigned(23 downto 0);

    signal misaligned_data_out_en_reg : std_logic;      -- means the collected misaligned data from two cachlines should be output
    signal misaligned_data_out_en_reg_next : std_logic;

    signal port_num_reg : unsigned(7 downto 0);     -- holds the accessed port number
    signal port_num_reg_next : unsigned(7 downto 0);

    -- Cache control
    signal cache_line_num_in_set : unsigned(f_log2(CACHE_LINES_PER_SET)-1 downto 0);    -- used only for reading when cache hit
    signal cache_hit : std_logic;
    signal cache_line_valid : std_logic;
    signal cache_line_dirty : std_logic;

    -- Outputs
    signal fetch_data : unsigned(31 downto 0);
    signal cache_rdy : std_logic;

    signal cache_address_r_out : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
    signal cache_address_w_out : std_logic_vector(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
    signal cache_data_out : t_cache_row(0 to CACHE_LINES_PER_SET-1);
    signal cache_write_en : std_logic;
    signal cache_data_metadata_out : t_cache_row_metadata(0 to CACHE_LINES_PER_SET-1)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+2 downto 0);
    signal cache_write_metadata_en : std_logic;
    signal cache_inst_cache_en : std_logic;
    signal cache_data_cache_en : std_logic;

    signal address_out : std_logic_vector(31 downto 0);
    signal write_data : unsigned(31 downto 0);
    signal mem_request : std_logic;
    signal mem_write_en : std_logic;
    signal mem_ram_en : std_logic;

    -- Misc
    signal req_address_plus_one : std_logic_vector(31-f_log2(CACHE_LINE_DEPTH) downto 0);     -- req_address_reg +1 without the cacheline offset

    signal addr_offset : std_logic_vector(f_log2(CACHE_LINE_DEPTH)-1 downto 0);
    signal addr_set : std_logic_vector(f_log2(NUMBER_SETS)-1 downto 0);
    signal addr_tag : std_logic_vector(31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH) downto 0);

    signal word_counter_c : std_logic;  -- turns on when word_counter_reg is by 1 away from overflow and i_memory_rdy is '1'
    signal word_counter_c_d : std_logic;    -- 1 clock cycle delay (used because of the delay between sending the new data to the BRAM and getting it back)

    signal misaligned_data_out : unsigned(31 downto 0);
    signal cache_write_data : unsigned(31 downto 0);

begin

    -- Default assignments
    req_address_plus_one <= std_logic_vector(unsigned(req_address_reg(req_address_reg'length-1 downto f_log2(CACHE_LINE_DEPTH))) + 1);

    addr_offset <= req_address_reg(f_log2(CACHE_LINE_DEPTH)-1 downto 0);
    addr_set <= req_address_reg(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto f_log2(CACHE_LINE_DEPTH));
    addr_tag <= req_address_reg(31 downto f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS));

    word_counter_c <= '1' when to_integer(word_counter_reg) = 2 ** word_counter_reg'length - 1 and i_memory_rdy = '1' else '0';

    misaligned_data_out <=  misaligned_data_reg(23 downto 0) & fetch_data(31 downto 24) when i_address(1 downto 0) = "01" else
                            misaligned_data_reg(23 downto 8) & fetch_data(31 downto 16) when i_address(1 downto 0) = "10" else
                            misaligned_data_reg(23 downto 16) & fetch_data(31 downto 8);      -- when "11"

    cache_lru_ram_write_en <= '1' when cache_hit = '1' and (s_cache_controller = READ or s_cache_controller = WRITE) else '0';
    cache_lru <= inst_cache_lru when i_data_fetch_en = '0' else data_cache_lru;

    -- Outputs
    o_fetch_data <= fetch_data when misaligned_data_out_en_reg = '0' else misaligned_data_out;
    o_cache_rdy <= cache_rdy;

    o_cache_address_r <= cache_address_r_out;
    o_cache_address_w <= cache_address_w_out;
    o_cache_data <= cache_data_out;
    o_cache_write_en <= cache_write_en;
    o_cache_data_metadata <= cache_data_metadata_out;
    o_cache_write_metadata_en <= cache_write_metadata_en;
    o_cache_inst_cache_en <= cache_inst_cache_en;
    o_cache_data_cache_en <= cache_data_cache_en;

    o_address <= address_out;
    o_write_data <= write_data;
    o_request <= mem_request;
    o_write_en <= mem_write_en;
    o_ram_en <= mem_ram_en;

    -- Clocked process
    prs_seq : process(i_clk, i_reset)
    begin
        if i_reset = '1' then
            s_cache_controller <= RESET;

            reset_counter_reg <= (others => '0');

            req_address_reg <= (others => '0');

            word_counter_reg <= (others => '0');

            word_counter_c_d <= '0';

            addr_cacheline_misalignment_reg <= '0';

            misaligned_data_reg <= (others => '0');

            misaligned_data_out_en_reg <= '0';

            port_num_reg <= (others => '0');
        elsif rising_edge(i_clk) then
            s_cache_controller <= s_cache_controller_next;

            reset_counter_reg <= reset_counter_reg_next;

            req_address_reg <= req_address_reg_next;

            word_counter_reg <= word_counter_reg_next;

            word_counter_c_d <= word_counter_c;

            addr_cacheline_misalignment_reg <= addr_cacheline_misalignment_reg_next;

            misaligned_data_reg <= misaligned_data_reg_next;

            misaligned_data_out_en_reg <= misaligned_data_out_en_reg_next;

            port_num_reg <= port_num_reg_next;
        end if;
    end process;

    -- inferred RAM
    prs_inst_cache_lru_ram_seq : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if cache_lru_ram_write_en = '1' and i_data_fetch_en = '0' then
                for i in 0 to CACHE_LINES_PER_SET-1 loop
                    inst_cache_lru_ram(to_integer(unsigned(addr_set)))(
                        (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-1 downto
                        (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-2
                    ) <= std_logic_vector(cache_lru_ram_write_data(i));
                end loop;
            end if;

            for i in 0 to CACHE_LINES_PER_SET-1 loop
                inst_cache_lru(i) <= unsigned(inst_cache_lru_ram(to_integer(unsigned(addr_set)))(
                    (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-1 downto
                    (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-2
                ));
            end loop;
        end if;
    end process;

    -- inferred RAM
    prs_data_cache_lru_ram_seq : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if cache_lru_ram_write_en = '1' and i_data_fetch_en = '1' then
                for i in 0 to CACHE_LINES_PER_SET-1 loop
                    data_cache_lru_ram(to_integer(unsigned(addr_set)))(
                        (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-1 downto
                        (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-2
                    ) <= std_logic_vector(cache_lru_ram_write_data(i));
                end loop;
            end if;

            for i in 0 to CACHE_LINES_PER_SET-1 loop
                data_cache_lru(i) <= unsigned(data_cache_lru_ram(to_integer(unsigned(addr_set)))(
                    (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-1 downto
                    (f_log2(CACHE_LINES_PER_SET)*CACHE_LINES_PER_SET)-i*f_log2(CACHE_LINES_PER_SET)-2
                ));
            end loop;
        end if;
    end process;

    -- Find the accessed cache line in the set, put it to the top of the LRU queue
    -- and shift all entries after it one place lower
    prs_cache_lru_sort : process(all)
        variable index : unsigned(f_log2(CACHE_LINES_PER_SET)-1 downto 0);
    begin
        cache_lru_ram_write_data <= cache_lru;    -- default assignment

        -- find the index of the hit cache line
        for i in 0 to CACHE_LINES_PER_SET-1 loop
            if cache_lru(i) = cache_line_num_in_set then
                index := to_unsigned(i, index'length);
            end if;
        end loop;

        -- shift the cache lines in the LRU queue
        for i in to_integer(index) to CACHE_LINES_PER_SET-2 loop
            cache_lru_ram_write_data(i) <= cache_lru(i+1);
        end loop;

        -- put the accessed cache line to the top
        cache_lru_ram_write_data(cache_lru_ram_write_data'length-1) <= cache_lru(to_integer(index));
    end process;

    -- Get the dirty and valid bits of the cache line that is to be replaced
    prs_dirty_and_valid_bits : process(all)
    begin
        cache_line_valid <= i_cache_row_metadata(to_integer(cache_lru(0)))
                                (31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+CACHE_VALID_FLAG_OFFSET);
        cache_line_dirty <= i_cache_row_metadata(to_integer(cache_lru(0)))
                                (31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+CACHE_DIRTY_FLAG_OFFSET);
    end process;

    -- Cache hit and cache line number in the set
    prs_hit : process(all)
        variable tag_check : std_logic_vector(0 to CACHE_LINES_PER_SET-1);
    begin
        cache_line_num_in_set <= (others => '0');

        for i in 0 to CACHE_LINES_PER_SET-1 loop
            if i_cache_row_metadata(i)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS) downto 0)
                = req_address_reg(31 downto f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)) and
                i_cache_row_metadata(i)(31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+CACHE_VALID_FLAG_OFFSET)
                = '1' then
                    tag_check(i) := '1';
                    cache_line_num_in_set <= to_unsigned(i, cache_line_num_in_set'length);
            else
                tag_check(i) := '0';
            end if;
        end loop;

        cache_hit <= or tag_check;
    end process;

    -- Fetched words counter
    prs_fetch_word_counter : process(all)
    begin
        word_counter_reg_next <= (others => '0');

        case s_cache_controller is
            when FETCH | WRITE_TO_RAM =>
                if i_memory_rdy = '1' then
                    word_counter_reg_next <= word_counter_reg + 1;
                else
                    word_counter_reg_next <= word_counter_reg;
                end if;

            when others =>
                null;
        end case;
    end process;

    -- Collects the first part of the misaligned data between the cachelines
    prs_misaligned_data_collector : process(all)
    begin
        misaligned_data_reg_next <= misaligned_data_reg;

        if s_cache_controller = READ and cache_hit = '1' and addr_cacheline_misalignment_reg = '1' then
            misaligned_data_reg_next <= fetch_data(31 downto 8);
        end if;
    end process;

    -- Prepares the data to be written to the cache
    prs_cache_write_data : process(all)
    begin
        cache_write_data <= i_write_data;

        -- when the address is cacheline misaligned
        if addr_cacheline_misalignment_reg = '1' then   -- the first part of the data
            case i_address(1 downto 0) is
                when "01" =>
                    cache_write_data(31 downto 24) <= i_write_data(31 downto 24);
                    cache_write_data(23 downto 16) <= i_write_data(23 downto 16);
                    cache_write_data(15 downto 8) <= i_write_data(15 downto 8);
                    cache_write_data(7 downto 0) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(7 downto 0));

                when "10" =>
                    cache_write_data(31 downto 24) <= i_write_data(31 downto 24);
                    cache_write_data(23 downto 16) <= i_write_data(23 downto 16);
                    cache_write_data(15 downto 8) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(15 downto 8));
                    cache_write_data(7 downto 0) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(7 downto 0));

                when "11" =>
                    cache_write_data(31 downto 24) <= i_write_data(31 downto 24);
                    cache_write_data(23 downto 16) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(23 downto 16));
                    cache_write_data(15 downto 8) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(15 downto 8));
                    cache_write_data(7 downto 0) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(7 downto 0));

                when others =>
                    null;
            end case;
        elsif misaligned_data_out_en_reg = '1' then     -- the second part of the data
            case i_address(1 downto 0) is
                when "01" =>
                    cache_write_data(31 downto 24) <= i_write_data(7 downto 0);
                    cache_write_data(23 downto 16) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(23 downto 16));
                    cache_write_data(15 downto 8) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(15 downto 8));
                    cache_write_data(7 downto 0) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(7 downto 0));

                when "10" =>
                    cache_write_data(31 downto 24) <= i_write_data(15 downto 8);
                    cache_write_data(23 downto 16) <= i_write_data(7 downto 0);
                    cache_write_data(15 downto 8) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(15 downto 8));
                    cache_write_data(7 downto 0) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(7 downto 0));

                when "11" =>
                    cache_write_data(31 downto 24) <= i_write_data(23 downto 16);
                    cache_write_data(23 downto 16) <= i_write_data(15 downto 8);
                    cache_write_data(15 downto 8) <= i_write_data(7 downto 0);
                    cache_write_data(7 downto 0) <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set))(7 downto 0));

                when others =>
                    null;
            end case;
        end if;
    end process;

    -- State machine process
    prs_fsm : process(all)
    begin
        s_cache_controller_next <= s_cache_controller;

        case s_cache_controller is
            when RESET =>
                if reset_counter_reg = 2 ** NUMBER_SETS - 1 then
                    s_cache_controller_next <= READY;
                end if;

            when READY =>
                if i_request = '1' then
                    if i_ram_en = '1' then
                        if i_write_en = '1' then
                            s_cache_controller_next <= WRITE;
                        else
                            s_cache_controller_next <= READ;
                        end if;
                    else
                        s_cache_controller_next <= WAIT_FOR_MMIO;
                    end if;
                end if;

                if i_port_req = '1' then
                    if i_port_number = CACHE_EVICT_INST_LINE_IO or 
                        i_port_number = CACHE_EVICT_DATA_LINE_IO then
                            s_cache_controller_next <= EVICT;
                    elsif (i_port_number = CACHE_PUSH_INST_LINE_IO or 
                        i_port_number = CACHE_PUSH_DATA_LINE_IO) and
                        i_cache_row_metadata(to_integer(cache_line_num_in_set))(
                            31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+CACHE_VALID_FLAG_OFFSET
                        ) = '1' and
                        i_cache_row_metadata(to_integer(cache_line_num_in_set))(
                            31-f_log2(CACHE_LINE_DEPTH)-f_log2(NUMBER_SETS)+CACHE_DIRTY_FLAG_OFFSET
                        ) = '1' then
                            s_cache_controller_next <= WRITE_TO_RAM;
                    end if;
                end if;

            when READ =>
                if cache_hit = '1' then
                    if addr_cacheline_misalignment_reg = '0' then
                        s_cache_controller_next <= READY;
                    else
                        s_cache_controller_next <= READ;
                    end if;
                elsif cache_line_valid = '0' or cache_line_dirty = '0' then
                    s_cache_controller_next <= FETCH;
                else
                    s_cache_controller_next <= WRITE_TO_RAM;
                end if;

            when WRITE =>
                if cache_hit = '1' then
                    if addr_cacheline_misalignment_reg = '0' then
                        s_cache_controller_next <= READY;
                    else
                        s_cache_controller_next <= WRITE;
                    end if;
                elsif cache_line_valid = '0' or cache_line_dirty = '0' then
                    s_cache_controller_next <= FETCH;
                else
                    s_cache_controller_next <= WRITE_TO_RAM;
                end if;

            when FETCH =>
                if word_counter_c_d = '1' then
                    if i_write_en = '1' then
                        s_cache_controller_next <= WRITE;
                    else
                        s_cache_controller_next <= READ;
                    end if;
                end if;

            when WRITE_TO_RAM =>
                if word_counter_c_d = '1' then
                    s_cache_controller_next <= FETCH;
                end if;

            when WAIT_FOR_MMIO =>
                if i_memory_rdy = '1' then
                    s_cache_controller_next <= READY;
                end if;

            when EVICT =>
                s_cache_controller_next <= READY;

            when others =>
                s_cache_controller_next <= READY;
        end case;
    end process;

    -- Outputs process
    prs_outputs : process(all)
    begin
        reset_counter_reg_next <= reset_counter_reg;

        req_address_reg_next <= req_address_reg;

        fetch_data <= (others => '0');
        cache_rdy <= '0';

        cache_address_r_out <= (others => '0');
        cache_address_w_out <= (others => '0');
        cache_data_out <= i_cache_row_data;
        cache_write_en <= '0';
        cache_data_metadata_out <= i_cache_row_metadata;
        cache_write_metadata_en <= '0';
        cache_inst_cache_en <= not i_data_fetch_en;
        cache_data_cache_en <= i_data_fetch_en;

        address_out <= (others => '0');
        write_data <= (others => '0');
        mem_request <= '0';
        mem_ram_en <= '0';
        mem_write_en <= '0';

        addr_cacheline_misalignment_reg_next <= addr_cacheline_misalignment_reg;
        misaligned_data_out_en_reg_next <= misaligned_data_out_en_reg;

        port_num_reg_next <= port_num_reg;

        case s_cache_controller is
            when RESET =>
                reset_counter_reg_next <= reset_counter_reg + 1;

                cache_address_r_out(
                    cache_address_r_out'length-1 downto f_log2(CACHE_LINE_DEPTH)
                ) <= std_logic_vector(reset_counter_reg_next);
                cache_address_r_out(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');

                cache_address_w_out(
                    cache_address_w_out'length-1 downto f_log2(CACHE_LINE_DEPTH)
                ) <= std_logic_vector(reset_counter_reg);
                cache_address_w_out(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');

                for i in 0 to CACHE_LINES_PER_SET-1 loop
                    cache_data_metadata_out(i)(
                        31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_VALID_FLAG_OFFSET
                    ) <= '0';
                    cache_data_metadata_out(i)(
                        31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_DIRTY_FLAG_OFFSET
                    ) <= '0';
                end loop;

                cache_write_metadata_en <= '1';

                cache_inst_cache_en <= '1';
                cache_data_cache_en <= '1';

            when READY =>
                cache_rdy <= '1';

                if i_port_req = '1' and (
                    i_port_number = CACHE_EVICT_INST_LINE_IO or
                    i_port_number = CACHE_EVICT_DATA_LINE_IO or
                    i_port_number = CACHE_PUSH_INST_LINE_IO or
                    i_port_number = CACHE_PUSH_DATA_LINE_IO
                ) then
                    req_address_reg_next <= std_logic_vector(i_port_data(
                        i_port_data'length-1 downto f_log2(CACHE_LINE_DEPTH)
                    ));
                    req_address_reg_next(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');

                    cache_address_r_out(
                        cache_address_r_out'length-1 downto f_log2(CACHE_LINE_DEPTH)
                    ) <= std_logic_vector(i_port_data(
                        f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto
                        f_log2(CACHE_LINE_DEPTH)
                    ));
                    cache_address_r_out(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');
                else
                    req_address_reg_next <= i_address;
                    cache_address_r_out <= i_address(f_log2(CACHE_LINE_DEPTH)+f_log2(NUMBER_SETS)-1 downto 0);
                end if;

                if i_port_req = '1' then
                    if i_port_number = CACHE_EVICT_INST_LINE_IO or
                        i_port_number = CACHE_EVICT_DATA_LINE_IO then
                            mem_ram_en <= '0';
                    elsif i_port_number = CACHE_PUSH_INST_LINE_IO or
                        i_port_number = CACHE_PUSH_DATA_LINE_IO then
                            mem_ram_en <= '1';
                    end if;
                end if;

                port_num_reg_next <= i_port_number;

                addr_cacheline_misalignment_reg_next <= '1' when
                    to_integer(unsigned(
                        i_address(f_log2(CACHE_LINE_DEPTH)-1 downto 2)
                    )) = 2 ** f_log2(CACHE_LINE_DEPTH/4) - 1 and
                    i_address(1 downto 0) /= "00" and
                    i_request = '1' and
                    i_ram_en = '1'
                else '0';  -- when the cacheline offset is all 1s, but the lowest 2 bits are not "00" (e.g. "111101" instead of aligned "111100")

                if i_ram_en = '0' then
                    address_out <= i_address;
                    write_data <= i_write_data;
                    mem_request <= mem_request;
                    mem_write_en <= i_write_en;
                end if;

            when READ =>
                fetch_data <= unsigned(i_cache_row_data(to_integer(cache_line_num_in_set)));

                if addr_cacheline_misalignment_reg = '0' then
                    cache_rdy <= cache_hit;

                    if cache_hit = '1' then
                        misaligned_data_out_en_reg_next <= '0';
                    end if;
                end if;
                if addr_cacheline_misalignment_reg = '1' then
                    misaligned_data_out_en_reg_next <= '1';
                end if;

                -- technically makes the process 1 clock cycle faster, but not really needed
                -- if cache_line_valid = '0' or cache_line_dirty = '0' then    -- when next state is FETCH
                --     address_out(31 downto f_log2(CACHE_LINE_DEPTH)) <= req_address_reg(31 downto f_log2(CACHE_LINE_DEPTH));
                --     address_out(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');

                --     mem_request <= not cache_hit;
                --     mem_ram_en <= '1';
                -- end if;

                cache_address_r_out(cache_address_r_out'length-addr_set'length-1 downto 0) <= (others => '0');

                if addr_cacheline_misalignment_reg = '0' then       -- in case it goes to WRITE_TO_RAM
                    cache_address_r_out(cache_address_r_out'length-1 downto cache_address_r_out'length-addr_set'length) <= addr_set;
                else        -- in case it goes back to READ
                    cache_address_r_out(cache_address_r_out'length-1 downto cache_address_r_out'length-addr_set'length) <= req_address_plus_one(f_log2(NUMBER_SETS)-1 downto 0);
                end if;

                -- when the request address is cacheline misaligned, but the first part of the data is fetched
                if addr_cacheline_misalignment_reg = '1' and cache_hit = '1' then
                    addr_cacheline_misalignment_reg_next <= '0';

                    req_address_reg_next(req_address_reg_next'length-1 downto f_log2(CACHE_LINE_DEPTH)) <= req_address_plus_one;
                    req_address_reg_next(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');
                end if;

            when WRITE =>
                cache_address_w_out <= addr_set & addr_offset;
                cache_data_out(to_integer(cache_line_num_in_set)) <= std_logic_vector(cache_write_data);
                cache_write_en <= cache_hit;
                cache_data_metadata_out(to_integer(cache_line_num_in_set))(31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_DIRTY_FLAG_OFFSET) <= '1';
                cache_write_metadata_en <= cache_hit;

                if addr_cacheline_misalignment_reg = '0' and cache_hit = '1' then
                    misaligned_data_out_en_reg_next <= '0';
                end if;
                if addr_cacheline_misalignment_reg = '1' then
                    misaligned_data_out_en_reg_next <= '1';
                end if;

                cache_address_r_out(cache_address_r_out'length-addr_set'length-1 downto 0) <= (others => '0');

                if addr_cacheline_misalignment_reg = '0' then       -- in case it goes to WRITE_TO_RAM
                    cache_address_r_out(cache_address_r_out'length-1 downto cache_address_r_out'length-addr_set'length) <= addr_set;
                else        -- in case it goes back to WRITE
                    cache_address_r_out(cache_address_r_out'length-1 downto cache_address_r_out'length-addr_set'length) <= req_address_plus_one(f_log2(NUMBER_SETS)-1 downto 0);
                end if;

                -- when the request address is cacheline misaligned, but the first part of the data is fetched
                if addr_cacheline_misalignment_reg = '1' and cache_hit = '1' then
                    addr_cacheline_misalignment_reg_next <= '0';

                    req_address_reg_next(req_address_reg_next'length-1 downto f_log2(CACHE_LINE_DEPTH)) <= req_address_plus_one;
                    req_address_reg_next(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');
                end if;

            when FETCH =>
                address_out(31 downto f_log2(CACHE_LINE_DEPTH)) <= req_address_reg(31 downto f_log2(CACHE_LINE_DEPTH));
                address_out(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');
                mem_request <= not word_counter_c_d;    -- '1' except for the last clock cycle of this state (because of the SDRAM controller)
                mem_ram_en <= '1';

                cache_address_r_out <= addr_set & std_logic_vector(word_counter_reg_next) & "00";
                cache_address_w_out <= addr_set & std_logic_vector(word_counter_reg) & "00";
                cache_data_out(to_integer(cache_lru(0))) <= std_logic_vector(i_fetch_data);
                cache_write_en <= i_memory_rdy;

                -- set up the metadata of the cache line
                if word_counter_c = '1' then
                    cache_data_metadata_out(to_integer(cache_lru(0)))(31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_DIRTY_FLAG_OFFSET) <= '0';
                    cache_data_metadata_out(to_integer(cache_lru(0)))(31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_VALID_FLAG_OFFSET) <= '1';
                    cache_data_metadata_out(to_integer(cache_lru(0)))(31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH) downto 0) <= addr_tag;
                    cache_write_metadata_en <= '1';
                end if;

                -- if the next state is READ or WRITE, set the corresponding address for the cache
                if word_counter_c_d = '1' then
                    cache_address_r_out <= addr_set & addr_offset;
                end if;

            when WRITE_TO_RAM =>
                address_out(address_out'length-1 downto f_log2(CACHE_LINE_DEPTH)) <=
                    i_cache_row_metadata(to_integer(cache_lru(0)))(
                        31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH) downto 0
                    ) & addr_set;
                address_out(f_log2(CACHE_LINE_DEPTH)-1 downto 0) <= (others => '0');
                -- '1' except for the last 2 clock cycles of this state
                -- (because of the SDRAM controller and delay between BRAM access and data output)
                mem_request <= not (word_counter_c or word_counter_c_d);
                mem_ram_en <= '1';
                mem_write_en <= '1';

                cache_address_r_out <= addr_set & std_logic_vector(word_counter_reg_next) & "00";
                write_data <= unsigned(i_cache_row_data(to_integer(cache_lru(0))));

                if port_num_reg = CACHE_PUSH_INST_LINE_IO then
                    cache_inst_cache_en <= '1';
                    cache_data_cache_en <= '0';
                else
                    cache_inst_cache_en <= '0';
                    cache_data_cache_en <= '1';
                end if;

            when WAIT_FOR_MMIO =>
                fetch_data <= i_fetch_data;
                cache_rdy <= i_memory_rdy;

            when EVICT =>
                cache_address_w_out <= addr_set & addr_offset;
                cache_data_metadata_out(to_integer(cache_line_num_in_set))(
                    31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_VALID_FLAG_OFFSET
                ) <= '0';
                cache_data_metadata_out(to_integer(cache_line_num_in_set))(
                    31-f_log2(NUMBER_SETS)-f_log2(CACHE_LINE_DEPTH)+CACHE_DIRTY_FLAG_OFFSET
                ) <= '0';
                cache_write_metadata_en <= '1';

                if port_num_reg = CACHE_EVICT_INST_LINE_IO then
                    cache_inst_cache_en <= '1';
                    cache_data_cache_en <= '0';
                else
                    cache_inst_cache_en <= '0';
                    cache_data_cache_en <= '1';
                end if;

            when others =>
                null;
        end case;
    end process;

end architecture;