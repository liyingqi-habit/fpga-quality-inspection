#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${PDS_STAGE:?Set to prior PDS stage for unchanged RTL inputs}"
out=$(mktemp -d "${TMPDIR:-/tmp}/regfile-matrix.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
python3 -B "$here/regfile_matrix.py" "$out" "$@"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles \
  -T "$here/../cpu/sw/link.ld" "$out/matrix.S" -o "$out/program.elf"
riscv64-unknown-elf-objcopy -O binary "$out/program.elf" "$out/program.bin"
test "$(stat -c %s "$out/program.bin")" -le 16384 || { echo 'FAIL: ROM overflow; split into smaller batches'; exit 1; }
python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$out/program.bin" "$out/firmware.hex"
riscv64-unknown-elf-objdump -d "$out/program.elf" > "$out/program.dis"
riscv64-unknown-elf-size "$out/program.elf"
cp "$PDS_STAGE/"*.bin "$out/"
iverilog -g2012 -I "$out" -s regfile_matrix_tb -o "$out/sim" "$PDS_STAGE/VexWriteResponse.v" \
  "$PDS_STAGE/mini_soc.v" "$PDS_STAGE/mini_uart.v" "$PDS_STAGE/mini_soc_first_board.v" "$here/regfile_matrix_tb.sv"
(cd "$out";vvp sim) | tee "$out/rtl.log"
sha256sum "$out/firmware.hex" "$out/matrix.S" "$out/cases.json" > "$out/firmware.sha256"
