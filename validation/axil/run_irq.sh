#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?normal AXIL CPU build}"
: "${CPU_INPUT_ROOT:?legal UART input root}"
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
test "$(sha256sum "$CPU_INPUT_ROOT/rtl/mini_uart.v" | cut -d ' ' -f1)" = 12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-irq.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
python3 -B "$here/irq_program.py" "$out"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$out/program.S" -o "$out/program.elf"
riscv64-unknown-elf-nm -n "$out/program.elf" > "$out/symbols.txt"
riscv64-unknown-elf-objdump -d "$out/program.elf" > "$out/program.dis"
riscv64-unknown-elf-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$out/program.bin" "$out/firmware.hex"
iverilog -g2012 -s irq_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/bridge.sv" "$here/soc.sv" "$here/irq_tb.sv"
for delay in 0 9;do
 dir="$out/delay$delay";mkdir "$dir"
 cp "$out/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
 (cd "$dir";vvp "$out/sim" +KEY_DELAY="$delay") > "$dir/simulation.log" 2>&1
 cat "$dir/simulation.log"
done
python3 -B "$here/irq_negative.py" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/reversed-priority.v"
iverilog -g2012 -s irq_tb -o "$out/negative.sim" "$out/reversed-priority.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/bridge.sv" "$here/soc.sv" "$here/irq_tb.sv"
mkdir "$out/negative"
cp "$out/firmware.hex" "$AXIL_CPU_BUILD/rtl/"*.bin "$out/negative/"
(cd "$out/negative";vvp "$out/negative.sim" +KEY_DELAY=0) > "$out/negative/simulation.log" 2>&1
python3 -B "$here/check_irq.py" "$out"
sha256sum "$here/run_irq.sh" "$here/irq_negative.py" "$here/irq_program.py" "$here/irq_tb.sv" "$here/check_irq.py" "$here/bridge.sv" "$here/soc.sv" "$out/firmware.hex" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" > "$out/inputs.sha256"
