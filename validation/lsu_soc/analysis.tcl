# PDS 2025.2 commands follow the locally installed, previously run PDS flow.
# No programming, bitstream generation, or edits to the original project.
add_design VexWriteResponse.v
add_design mini_uart.v
add_design mini_soc.v
add_design mini_soc_first_board.v
# Unmodified, hash-pinned pre-existing six-port candidate constraint profile.
# This does not resolve physical board revision compatibility.
add_constraint mini_first_board.fdc
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module mini_soc_first_board
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr
report_timing
save_project
exit
