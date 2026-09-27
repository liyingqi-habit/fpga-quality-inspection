#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REAL_LSU_BUILD:?Set to normal CPU-WR-03 generated RTL directory}"
: "${CPU_INPUT_ROOT:?Set to legal original mini SoC directory (UART input only)}"
test "$(cat "$REAL_LSU_BUILD/mode.txt")" = normal
test "$(sha256sum "$CPU_INPUT_ROOT/rtl/mini_uart.v" | cut -d ' ' -f1)" = 12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e
out=$(mktemp -d "${TMPDIR:-/tmp}/lsu-soc.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
mkdir -p "$out/rtl/generated"
cp "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" "$out/rtl/generated/VexRiscv.v"
cp "$REAL_LSU_BUILD/rtl/"*.bin "$out/rtl/generated/"
cp "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$out/rtl/"
cp "$here/mini_soc.v" "$out/rtl/"
cp -R "$here/../cpu/sw" "$here/../cpu/tb" "$here/../cpu/scripts" "$out/"
# Only the staged copies change: enable precise-store expectations for case26.
sed -i 's/iverilog -g2012/iverilog -DMIGRATED_SOC -g2012/g; s/"$@" sw\/cpu_directed.S/"$@" -DMIGRATED_SOC sw\/cpu_directed.S/; s/no board, DDR, AXI B response/no board, DDR, full AXI/; s/, precise store-access fault//g' "$out/scripts/test_cpu_directed.sh" "$out/scripts/test_cpu_traps.sh"
bash "$out/scripts/test_cpu_directed.sh"
bash "$out/scripts/test_cpu_traps.sh"
for delay in 0 7 31; do
  dir="$out/access-$delay";mkdir "$dir"
  cp "$REAL_LSU_BUILD/rtl/"*.bin "$dir/"
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax \
    -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$here/access.S" -o "$dir/program.elf"
  riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
  python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
  riscv64-unknown-elf-objdump -d "$dir/program.elf" > "$dir/program.dis"
  iverilog -g2012 -s access_tb -Paccess_tb.DELAY="$delay" -o "$dir/sim" \
    "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" "$out/rtl/mini_uart.v" "$here/mini_soc.v" "$here/access_tb.sv"
  (cd "$dir";vvp sim)
done
negative() {
local flag="$1" expected="$2"
local dir="$out/negative-$flag";mkdir "$dir"
cp "$REAL_LSU_BUILD/rtl/"*.bin "$dir/"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -D"$flag" \
  -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$here/access.S" -o "$dir/program.elf"
riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
set +e
(cd "$dir";vvp "$out/access-7/sim") > "$dir/negative.log" 2>&1
status=$?
set -e
if [ "$status" = 0 ] || ! grep -q "$expected" "$dir/negative.log"; then
  cat "$dir/negative.log";echo 'FAIL: access negative control';exit 1
fi
echo "PASS: negative $flag rejected: $expected"
}
negative ACCESS_MUTATION 'Access failure signature=86'
negative LOAD_MUTATION 'Access failure signature=81'
negative FLUSH_MUTATION 'Wrong-path side effect reached bus'
sha256sum "$here/mini_soc.v" "$here/access.S" "$here/access_tb.sv" \
  "$out/rtl/mini_uart.v" "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" > "$out/inputs.sha256"
echo 'PASS: migrated mini SoC, delayed read/write/subword/flush tests and negative controls'
echo 'LIMITS: local synchronous target, global local reset, not external AXI/DDR/board'
