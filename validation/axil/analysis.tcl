# Offline implementation only. Never generates/programs a bitstream.
add_design VexAxilCpu.v
add_design mini_uart.v
add_design bridge.sv
add_design soc.sv
add_design mini_soc_first_board.v
add_constraint mini_first_board.fdc
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module mini_soc_first_board
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr
report_timing
save_project
exit
