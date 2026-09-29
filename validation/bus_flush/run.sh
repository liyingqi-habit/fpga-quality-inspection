#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REAL_LSU_BUILD:?Set to normal generated CPU}"
test "$(cat "$REAL_LSU_BUILD/mode.txt")" = normal
test "$(sha256sum "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" | cut -d ' ' -f1)" = 63bb55e1bb43cc472699a09f1e2dbd674a68cab562da0df9d988b16f9b321140
out=$(mktemp -d "${TMPDIR:-/tmp}/bus-flush.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
python3 -B "$here/generate.py" "$out"
iverilog -g2012 -s bus_flush_tb -o "$out/sim" "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" "$here/../real_lsu/write_bridge.sv" "$here/tb.sv"
for program in "$out/"*/program.S;do
  dir=$(dirname "$program")
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$program" -o "$dir/program.elf"
  riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
  python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
  riscv64-unknown-elf-objdump -d "$dir/program.elf" > "$dir/program.dis"
  branch_pc=$(riscv64-unknown-elf-nm "$dir/program.elf" | awk '$3=="tested_branch" {print $1}')
  test -n "$branch_pc"
  for schedule in 0 1 2;do for delay in 0 7 31;do for admit in 0 5;do
    run="$dir/s$schedule-$delay-$admit";mkdir "$run"
    cp "$dir/firmware.hex" "$REAL_LSU_BUILD/rtl/"*.bin "$run/"
    (cd "$run";vvp "$out/sim" +SCHEDULE="$schedule" +DELAY="$delay" +ADMIT="$admit" +BRANCH_PC="$branch_pc") > "$run/simulation.log" 2>&1 || { cat "$run/simulation.log";exit 1; }
  done;done;done
  echo "PASS: $(basename "$dir") 18 schedules x 2 boots"
done
python3 -B "$here/check.py" "$out" | tee "$out/summary.json"
dir="$out/negative";mkdir "$dir"
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -DFLUSH_MUTATION -T "$here/../cpu/sw/link.ld" "$out/beq_taken-0/program.S" -o "$dir/program.elf"
riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
cp "$REAL_LSU_BUILD/rtl/"*.bin "$dir/"
status=0
branch_pc=$(riscv64-unknown-elf-nm "$dir/program.elf" | awk '$3=="tested_branch" {print $1}')
(cd "$dir";vvp "$out/sim" +SCHEDULE=0 +DELAY=31 +ADMIT=5 +BRANCH_PC="$branch_pc") > "$dir/simulation.log" 2>&1 || status=$?
if [ "$status" = 0 ] || ! grep -q 'Wrong-path request addr=10000040' "$dir/simulation.log";then echo 'FAIL: wrong-path mutation escaped';exit 1;fi
sha256sum "$here/"*.py "$here/tb.sv" "$here/../real_lsu/write_bridge.sv" "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" > "$out/inputs.sha256"
echo 'PASS: 432 configurations, 864 boots, real wrong-path mutation rejected; RTL only'
