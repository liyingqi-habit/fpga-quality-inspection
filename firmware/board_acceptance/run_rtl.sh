#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?generated RC1 CPU directory}"
: "${UART_FILE:?path to legally supplied mini_uart.v}"
test "$(cat "$AXIL_CPU_BUILD/mode.txt")" = normal
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
test "$(sha256sum "$UART_FILE" | cut -d ' ' -f1)" = 12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e
out=$(mktemp -d "${TMPDIR:-/tmp}/board-rtl.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
inputs=("$here/start.S" "$here/build.sh" "$here/run_rtl.sh" "$here/acceptance_tb.sv" "$here/check_uart.py" "$here/negative_rom.py"
  "$here/../../validation/cpu/sw/link.ld" "$here/../../validation/cpu/scripts/bin_to_hex.py"
  "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$UART_FILE"
  "$here/../../validation/axil/bridge.sv" "$here/../../validation/axil/soc.sv" "$AXIL_CPU_BUILD/rtl/"*.bin)
sha256sum "${inputs[@]}" > "$out/before.sha256"
verilator --version
iverilog -V > "$out/iverilog-version.log" 2>&1
bash "$here/build.sh" | tee "$out/build.log"
build=$(sed -n 's/^OUTPUT=//p' "$out/build.log")
cp "$build/firmware.hex" "$out/"
cp "$AXIL_CPU_BUILD/rtl/"*.bin "$out/"
riscv64-unknown-elf-nm "$build/firmware.elf" | awk '$3 ~ /^(ram_check|wait_irq|wait_release|trap|idle|quiet_failure|ecall_site)$/ {printf "`define PC_%s 32\047h%s\n",$3,$1}' > "$out/symbols.vh"
verilator --binary --timing -Wno-fatal --top-module acceptance_tb -j 2 \
  -I"$out" --Mdir "$out/obj" -o sim \
  "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$UART_FILE" \
  "$here/../../validation/axil/bridge.sv" "$here/../../validation/axil/soc.sv" \
  "$here/acceptance_tb.sv" > "$out/compile.log" 2>&1
for scenario in ${CASES:-0 1 2 3 4 5 6 7 8 9 10 11 12 13}; do
  (cd "$out"; ./obj/sim +CASE="$scenario" +LOG="uart-$scenario.log") > "$out/case-$scenario.log" 2>&1
  python3 -B "$here/check_uart.py" "$out/uart-$scenario.log" "$scenario"
done
if [ -f "$out/uart-0.log" ];then
  python3 -B "$here/check_uart.py" "$out/uart-0.log" 0 --self-test
  (cd "$out"; ./obj/sim +CASE=0 +CORRUPT_SERIAL +LOG=uart-corrupt.log) > "$out/corrupt.log" 2>&1
  if python3 -B "$here/check_uart.py" "$out/uart-corrupt.log" 0 > "$out/corrupt-check.log" 2>&1;then
    echo 'FAIL: corrupted serial stream escaped oracle';exit 1
  fi
  grep -q 'normal transcript mismatch' "$out/corrupt-check.log"
  echo 'PASS: corrupted serial stream rejected'
fi
if [ "${FOUR_STATE:-1}" = 1 ] && [ -f "$out/uart-0.log" ];then
  iverilog -g2012 -I "$out" -s acceptance_tb -o "$out/sim4" \
    "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$UART_FILE" \
    "$here/../../validation/axil/bridge.sv" "$here/../../validation/axil/soc.sv" \
    "$here/acceptance_tb.sv" > "$out/compile4.log" 2>&1
  (cd "$out"; vvp sim4 +CASE=0 +FAST_RELEASE +LOG=uart-4state.log) > "$out/4state.log" 2>&1
  python3 -B "$here/check_uart.py" "$out/uart-4state.log" 0
  cmp "$out/uart-0.log" "$out/uart-4state.log"
  echo 'PASS: four-state accelerated-release normal serial transcript matches'
  (cd "$out"; vvp sim4 +CASE=1 +LOG=uart-4state-ram.log) > "$out/4state-ram.log" 2>&1
  python3 -B "$here/check_uart.py" "$out/uart-4state-ram.log" 1
  mkdir "$out/no-init"
  cp "$AXIL_CPU_BUILD/rtl/"*.bin "$out/no-init/"
  riscv64-unknown-elf-nm "$build/firmware.elf" > "$out/symbols.txt"
  python3 -B "$here/negative_rom.py" "$out/firmware.hex" "$out/symbols.txt" "$out/no-init/firmware.hex"
  if (cd "$out/no-init"; vvp ../sim4 +CASE=1 +LOG=uart.log) > "$out/no-init/run.log" 2>&1;then
    echo 'FAIL: uninitialized diagnostic mutant escaped';exit 1
  fi
  grep -q 'UART unknown data' "$out/no-init/run.log"
  echo 'PASS: omitted diagnostic initialization rejected by four-state UART decoder'
fi
sha256sum "${inputs[@]}" > "$out/after.sha256"
cmp "$out/before.sha256" "$out/after.sha256"
sha256sum "$here/start.S" "$here/acceptance_tb.sv" "$here/check_uart.py" \
  "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$UART_FILE" \
  "$here/../../validation/axil/bridge.sv" "$here/../../validation/axil/soc.sv" \
  "$out/firmware.hex" > "$out/inputs.sha256"
echo 'RTL ONLY; netlist/PDS for this firmware NOT_RUN; board UNVERIFIED'
