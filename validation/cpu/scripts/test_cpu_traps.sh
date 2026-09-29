#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
src="$PWD"
mkdir -p build/cpu_traps
out=$(mktemp -d "$src/build/cpu_traps/run-XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -V 2>&1 | head -n 2 || true
riscv64-unknown-elf-gcc --version | head -n 1
sha256sum rtl/generated/VexRiscv.v rtl/mini_soc.v rtl/mini_uart.v sw/cpu_traps.S tb/cpu_traps_tb.sv scripts/test_cpu_traps.sh > "$out/inputs.sha256"
cp rtl/generated/*.bin "$out/"
iverilog -g2012 -s cpu_traps_tb -o "$out/sim" rtl/generated/VexRiscv.v rtl/mini_uart.v rtl/mini_soc.v tb/cpu_traps_tb.sv
build() {
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T sw/link.ld "$@" sw/cpu_traps.S -o "$out/traps.elf"
  riscv64-unknown-elf-objcopy -O binary "$out/traps.elf" "$out/traps.bin"
  python3 scripts/bin_to_hex.py "$out/traps.bin" "$out/firmware.hex"
}
build
riscv64-unknown-elf-objdump -d "$out/traps.elf" > "$out/traps.dis"
(cd "$out"; vvp sim) | tee "$out/positive.log"
grep -q '^PASS: trap regression and reset' "$out/positive.log"
mkdir "$out/mutation"
build -DTRAP_MUTATION
cp "$out/firmware.hex" "$out/traps.elf" "$out/traps.bin" "$out/mutation/"
set +e
(cd "$out"; vvp sim) > "$out/mutation.log" 2>&1
rc=$?
set -e
build
if [[ "$rc" -eq 0 ]] || ! grep -q 'Trap failure signature=81' "$out/mutation.log"; then
  cat "$out/mutation.log"; echo 'FAIL: wrong mcause expectation not rejected'; exit 1
fi
sha256sum "$out/firmware.hex" > "$out/firmware.sha256"
echo 'PASS: negative control rejected incorrect illegal-instruction mcause'
echo 'LIMITS: directed RTL checks only; no board, interrupts, precise store-access fault or full ISA certification'
