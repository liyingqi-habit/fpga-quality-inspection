#!/usr/bin/env bash
# Compile only. Never simulates, replaces PDS ROM, or programs hardware.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d "${TMPDIR:-/tmp}/board-acceptance.XXXXXXXX")
echo "OUTPUT=$out"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax \
  -nostdlib -nostartfiles -Wl,--no-relax,-Map,"$out/firmware.map" \
  -T "$here/../../validation/cpu/sw/link.ld" "$here/start.S" -o "$out/firmware.elf"
riscv64-unknown-elf-objcopy -O binary "$out/firmware.elf" "$out/firmware.bin"
python3 -B "$here/../../validation/cpu/scripts/bin_to_hex.py" "$out/firmware.bin" "$out/firmware.hex"
riscv64-unknown-elf-objdump -d "$out/firmware.elf" > "$out/firmware.dis"
riscv64-unknown-elf-size "$out/firmware.elf"
# Full-RAM destructive test is only valid with no RAM-resident program state.
riscv64-unknown-elf-size "$out/firmware.elf" | awk 'NR==2 {if ($2 != 0 || $3 != 0) exit 1}'
test "$(riscv64-unknown-elf-nm "$out/firmware.elf" | awk '$3=="_start" {print $1}')" = 80000000
test "$(wc -l < "$out/firmware.hex")" -eq 4096
sha256sum "$here/start.S" "$here/build.sh" "$here/../../validation/cpu/sw/link.ld" \
  "$here/../../validation/cpu/scripts/bin_to_hex.py" \
  "$out/firmware.elf" "$out/firmware.hex" > "$out/inputs.sha256"
echo 'BUILD ONLY: simulation NOT_RUN; board NOT_RUN; firmware UNVERIFIED'
