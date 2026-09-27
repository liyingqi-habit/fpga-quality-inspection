#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?normal AXIL CPU build}"
: "${CPU_INPUT_ROOT:?legal UART input root}"
test "$(cat "$AXIL_CPU_BUILD/mode.txt")" = normal
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
test "$(sha256sum "$CPU_INPUT_ROOT/rtl/mini_uart.v" | cut -d ' ' -f1)" = 12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-csr.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s csr_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/bridge.sv" "$here/soc.sv" "$here/csr_tb.sv"
for suite in readonly boundary;do
 dir="$out/$suite";mkdir "$dir"
 python3 -B "$here/csr_program.py" "$dir" "$suite"
 riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$dir/program.S" -o "$dir/program.elf"
 riscv64-unknown-elf-nm -n "$dir/program.elf" > "$dir/symbols.txt"
 riscv64-unknown-elf-objdump -d "$dir/program.elf" > "$dir/program.dis"
 riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
 python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
 cp "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
 (cd "$dir";vvp "$out/sim") > "$dir/simulation.log" 2>&1
 cat "$dir/simulation.log"
done
sha256sum "$here/run_csr.sh" "$here/csr_program.py" "$here/csr_tb.sv" "$here/check_csr.py" "$here/bridge.sv" "$here/soc.sv" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/"*/firmware.hex > "$out/inputs.sha256"
python3 -B "$here/check_csr.py" "$out"
mkdir "$out/negative"
python3 -B "$here/csr_negative.py" generate "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/negative"
for mode in readonly align mpp;do
 mkdir "$out/negative/$mode"
 iverilog -g2012 -s csr_tb -o "$out/negative/$mode/sim" "$out/negative/$mode.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/bridge.sv" "$here/soc.sv" "$here/csr_tb.sv"
 for suite in readonly boundary;do
  dir="$out/negative/$mode/$suite";mkdir "$dir"
  cp "$out/$suite/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
  (cd "$dir";vvp "$out/negative/$mode/sim") > "$dir/simulation.log" 2>&1
 done
done
python3 -B "$here/csr_negative.py" check "$out" "$out/negative"
sha256sum "$here/csr_negative.py" "$out/negative/"*.v >> "$out/inputs.sha256"
