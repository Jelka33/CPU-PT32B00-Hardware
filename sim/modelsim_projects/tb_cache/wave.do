onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_cache/i_clk
add wave -noupdate /tb_cache/i_reset
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/i_address
add wave -noupdate /tb_cache/i_write_data
add wave -noupdate /tb_cache/i_request
add wave -noupdate /tb_cache/i_write_en
add wave -noupdate /tb_cache/i_ram_en
add wave -noupdate /tb_cache/i_data_fetch_en
add wave -noupdate /tb_cache/i_fetch_data
add wave -noupdate /tb_cache/i_memory_rdy
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/o_fetch_data
add wave -noupdate /tb_cache/o_cache_rdy
add wave -noupdate /tb_cache/o_address
add wave -noupdate /tb_cache/o_write_data
add wave -noupdate /tb_cache/o_request
add wave -noupdate /tb_cache/o_write_en
add wave -noupdate /tb_cache/o_ram_en
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/dut1/i_cache_row_data
add wave -noupdate /tb_cache/dut1/i_cache_row_metadata
add wave -noupdate /tb_cache/dut1/o_cache_address_r
add wave -noupdate /tb_cache/dut1/o_cache_address_w
add wave -noupdate /tb_cache/dut1/o_cache_data
add wave -noupdate /tb_cache/dut1/o_cache_write_en
add wave -noupdate /tb_cache/dut1/o_cache_data_metadata
add wave -noupdate /tb_cache/dut1/o_cache_write_metadata_en
add wave -noupdate /tb_cache/dut1/inst_cache_lru_ram
add wave -noupdate /tb_cache/dut1/inst_cache_lru
add wave -noupdate /tb_cache/dut1/data_cache_lru_ram
add wave -noupdate /tb_cache/dut1/data_cache_lru
add wave -noupdate /tb_cache/dut1/cache_lru
add wave -noupdate /tb_cache/dut1/cache_lru_ram_write_data
add wave -noupdate /tb_cache/dut1/cache_lru_ram_write_en
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/dut1/s_cache_controller
add wave -noupdate /tb_cache/dut1/word_counter_reg
add wave -noupdate /tb_cache/dut1/word_counter_c
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/dut1/req_address_reg
add wave -noupdate /tb_cache/dut1/addr_cacheline_misalignment_reg
add wave -noupdate /tb_cache/dut1/misaligned_data_out_en_reg
add wave -noupdate /tb_cache/dut1/misaligned_data_reg
add wave -noupdate /tb_cache/dut1/misaligned_data_out
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/dut2/ram_instruction_cache
add wave -noupdate /tb_cache/dut2/ram_instruction_cache_metadata
add wave -noupdate /tb_cache/dut3/ram_data_cache_block_1
add wave -noupdate /tb_cache/dut3/ram_data_cache_block_2
add wave -noupdate /tb_cache/dut3/ram_data_cache_block_3
add wave -noupdate /tb_cache/dut3/ram_data_cache_block_4
add wave -noupdate /tb_cache/dut3/ram_data_cache_metadata
add wave -noupdate -divider <NULL>
add wave -noupdate /tb_cache/dut2/o_row_data
add wave -noupdate /tb_cache/dut3/o_row_data
add wave -noupdate /tb_cache/dut3/r_addr_plus_one
add wave -noupdate /tb_cache/dut3/w_addr_plus_one
add wave -noupdate /tb_cache/dut3/block1_out
add wave -noupdate /tb_cache/dut3/block2_out
add wave -noupdate /tb_cache/dut3/block3_out
add wave -noupdate /tb_cache/dut3/block4_out
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 263
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {113235591 ps} {117724443 ps}
