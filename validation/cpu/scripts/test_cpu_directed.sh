#!/usr/bin/env bash
# Isolated, offline regression. Does not change build/firmware.hex or invoke PDS.
set -euo pipefail
cd "$(dirname "$0")/.."
src="$PWD"
mkdir -p build/cpu_directed
out=$(mktemp -d "$src/build/cpu_directed/run-XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -V 2>&1 | head -n 2 || true
riscv64-unknown-elf-gcc --version | head -n 1
sha256sum rtl/generated/VexRiscv.v rtl/mini_soc.v rtl/mini_uart.v \
  sw/cpu_directed.S tb/cpu_directed_tb.sv scripts/test_cpu_directed.sh > "$out/inputs.sha256"
cp rtl/generated/*.bin "$out/"

# Rebuild the existing baseline in the isolated directory, not its board outputs.
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -Os -g \
  -ffreestanding -fno-builtin -fno-pic -fno-strict-aliasing -msmall-data-limit=0 -mno-relax \
  -nostdlib -nostartfiles -Wl,--gc-sections -T sw/link.ld \
  sw/start.S sw/hazard_test.S sw/main.c -o "$out/baseline.elf"
riscv64-unknown-elf-objcopy -O binary "$out/baseline.elf" "$out/baseline.bin"
python3 scripts/bin_to_hex.py "$out/baseline.bin" "$out/firmware.hex"
cp "$out/firmware.hex" "$out/baseline.hex"
sha256sum "$out/baseline.hex" > "$out/baseline-hex.sha256"
iverilog -g2012 -s mini_soc_tb -o "$out/baseline_sim" \
  rtl/generated/VexRiscv.v rtl/mini_uart.v rtl/mini_soc.v tb/mini_soc_tb.sv
(cd "$out"; vvp baseline_sim) | tee "$out/baseline.log"
grep -q '^PASS:' "$out/baseline.log"

iverilog -g2012 -s mini_uart_tb -o "$out/uart_sim" rtl/mini_uart.v tb/mini_uart_tb.sv
vvp "$out/uart_sim" | tee "$out/uart.log"
grep -q '^PASS:' "$out/uart.log"
iverilog -g2012 -s cpu_directed_tb -o "$out/directed_sim" \
  rtl/generated/VexRiscv.v rtl/mini_uart.v rtl/mini_soc.v tb/cpu_directed_tb.sv

build_directed() {
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax \
    -nostdlib -nostartfiles -T sw/link.ld "$@" sw/cpu_directed.S -o "$out/directed.elf"
  riscv64-unknown-elf-objcopy -O binary "$out/directed.elf" "$out/directed.bin"
  python3 scripts/bin_to_hex.py "$out/directed.bin" "$out/firmware.hex"
}
build_directed
riscv64-unknown-elf-objdump -d "$out/directed.elf" > "$out/directed.dis"
sha256sum "$out/firmware.hex" > "$out/directed-hex.sha256"
(cd "$out"; vvp directed_sim) | tee "$out/directed.log"
grep -q '^PASS: directed CPU tests' "$out/directed.log"

# Deliberately wrong MUL expectation must be detected, not report PASS.
mkdir "$out/mutation"
cp "$out/firmware.hex" "$out/good-directed.hex"
build_directed -DCPU_TEST_MUTATION
cp "$out/firmware.hex" "$out/mutation/firmware.hex"
cp "$out/directed.elf" "$out/mutation/directed.elf"
cp "$out/directed.bin" "$out/mutation/directed.bin"
set +e
(cd "$out"; vvp directed_sim) > "$out/mutation.log" 2>&1
rc=$?
set -e
build_directed
if [[ "$rc" -eq 0 ]] || ! grep -q 'failure signature=81 case=1' "$out/mutation.log"; then
  cat "$out/mutation.log"
  echo 'FAIL: negative control did not reject wrong expectation'; exit 1
fi
echo 'PASS: negative control rejected wrong MUL expectation at case 1'
echo 'LIMITS: no board, DDR, AXI B response, DMA, cache, interrupts or full ISA certification'
