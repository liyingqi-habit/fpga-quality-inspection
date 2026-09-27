#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?Generated full CSR CPU directory}"
: "${CPU_INPUT_ROOT:?Legal mini_uart input directory}"
test "$(cat "$AXIL_CPU_BUILD/mode.txt")" = normal
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
test "$(sha256sum "$CPU_INPUT_ROOT/rtl/mini_uart.v" | cut -d ' ' -f1)" = 12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-soc.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
python3 -B "$here/program.py" "$out"
cp "$AXIL_CPU_BUILD/rtl/"*.bin "$out/"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$out/program.S" -o "$out/program.elf"
riscv64-unknown-elf-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$out/program.bin" "$out/firmware.hex"
riscv64-unknown-elf-objdump -d "$out/program.elf" > "$out/program.dis"
iverilog -g2012 -I "$out" -s soc_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/bridge.sv" "$here/soc.sv" "$here/soc_tb.sv"
(cd "$out";vvp sim)
iverilog -g2012 -DEXPECTATION_MUTATION -I "$out" -s soc_tb -o "$out/negative" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/bridge.sv" "$here/soc.sv" "$here/soc_tb.sv"
status=0
(cd "$out";vvp negative) > "$out/negative.log" 2>&1 || status=$?
if [ "$status" = 0 ] || ! grep -q 'ISA result mismatch word=4' "$out/negative.log";then
  cat "$out/negative.log";echo 'FAIL: negative expected value escaped';exit 1
fi
echo 'PASS: independent expected-value mutation rejected at word 4'
sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/firmware.hex" "$here/bridge.sv" "$here/soc.sv" > "$out/inputs.sha256"
