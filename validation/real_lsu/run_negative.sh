#!/usr/bin/env bash
# The caller must supply RTL generated with WR_NEGATIVE_CONTROL=1.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REAL_LSU_NEGATIVE_BUILD:?Set to the separate negative-control generation directory}"
test "$(cat "$REAL_LSU_NEGATIVE_BUILD/mode.txt")" = negative
out=$(mktemp -d "${TMPDIR:-/tmp}/real-lsu-negative.XXXXXXXX")
echo "OUTPUT=$out"
iverilog -g2012 -s real_tb -o "$out/sim" "$REAL_LSU_NEGATIVE_BUILD/rtl/VexWriteResponse.v" \
  "$here/write_bridge.sv" "$here/../write_response/target.sv" "$here/real_tb.sv"
cp "$REAL_LSU_NEGATIVE_BUILD/rtl/"*.bin "$out/"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
  -Wl,-Ttext=0x80000000 -Wl,--no-relax -DTEST_ID=0 -DTEST_OFFSET=0 \
  "$here/program.S" -o "$out/program.elf"
riscv64-unknown-elf-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$out/program.bin" "$out/program.hex"
# The SV scoreboard may fail before the independent checker; retain either result.
set +e
(cd "$out"; vvp sim +CASE=0) > "$out/simulation.log" 2>&1
status=$?
set -e
echo "NEGATIVE_SIM_EXIT=$status"
python3 -B "$here/check_negative.py" "$out/trace.csv"
