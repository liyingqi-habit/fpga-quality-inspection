#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REAL_LSU_BUILD:?Run generate.sh first and set REAL_LSU_BUILD}"
test "$(cat "$REAL_LSU_BUILD/mode.txt")" = normal
out=$(mktemp -d "${TMPDIR:-/tmp}/real-lsu-run.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s real_tb -o "$out/sim" "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" \
  "$here/write_bridge.sv" "$here/../write_response/target.sv" "$here/real_tb.sv"
for id in $(seq 0 11); do
  dir="$out/case$id"; mkdir "$dir"
  cp "$REAL_LSU_BUILD/rtl/"*.bin "$dir/"
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles \
    -Wl,-Ttext=0x80000000 -Wl,--no-relax -DTEST_ID="$id" -DTEST_OFFSET="$((id*4))" \
    "$here/program.S" -o "$dir/program.elf"
  riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
  python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/program.hex"
  (cd "$dir"; vvp "$out/sim" +CASE="$id")
done
python3 -B "$here/check_real.py" "$out"
sha256sum "$here/"*.sv "$here/"*.py "$here/program.S" "$REAL_LSU_BUILD/rtl/"* > "$out/inputs.sha256"
