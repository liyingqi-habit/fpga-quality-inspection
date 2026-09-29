#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?normal generated CPU required}"
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = d0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-nested.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
build_fw() {
 local dir=$1 source=$2;shift 2
 mkdir "$dir"
 riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$@" "$source" -o "$dir/program.elf"
 riscv64-unknown-elf-nm -n "$dir/program.elf" > "$dir/symbols.txt"
 riscv64-unknown-elf-objdump -d "$dir/program.elf" > "$dir/program.dis"
 riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
 python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
}
run_case() {
 local fw=$1 dir=$2 p=$3 h=$4 d=$5
 mkdir "$dir"
 cp "$fw/firmware.hex" "$dir/boot0.hex"
 cp "$out/recovery/firmware.hex" "$dir/boot1.hex"
 cp "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
 local a b c
 a=$(awk '$3=="outer_entry" {print $1}' "$fw/symbols.txt")
 b=$(awk '$3=="inner_entry" {print $1}' "$fw/symbols.txt")
 c=$(awk '$3=="outer_return_prepare" {print $1}' "$fw/symbols.txt")
 (cd "$dir";vvp "${sim_override:-$out/sim}" +PHASE="$p" +HOLD="$h" +DELAY="$d" +OUTERPC="$a" +INNERPC="$b" +RETURNPC="$c") > "$dir/simulation.log" 2>&1
}
iverilog -g2012 -s nested_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$here/bridge.sv" "$here/cancel_target.sv" "$here/nested_tb.sv"
build_fw "$out/recovery" "$here/nested_recovery.S"
for o in 0 3 7 11;do
 for i in 3 7 11;do
  test "$o" != "$i" || continue
  for n in 0 1;do
   fw="$out/fw_o${o}_i${i}_n${n}"
   build_fw "$fw" "$here/nested.S" -DOUTER="$o" -DINNER="$i" -DNESTED="$n" -DBAD_RESTORE=0
   for d in 2 13;do
    run_case "$fw" "$out/o${o}_i${i}_n${n}_p0_h0_d${d}" 0 0 "$d"
    # Reset nested handler only when nesting is enabled. Deferred IRQ is covered by p0.
    for p in 1 2 3 4 5;do
     if test "$p" -eq 3 && test "$n" -eq 0;then continue;fi
     for h in 0 1;do run_case "$fw" "$out/o${o}_i${i}_n${n}_p${p}_h${h}_d${d}" "$p" "$h" "$d";done
    done
   done
   echo "TRACES_COMPLETE outer=$o inner=$i nested=$n"
  done
 done
done
build_fw "$out/negative_fw" "$here/nested.S" -DOUTER=0 -DINNER=3 -DNESTED=1 -DBAD_RESTORE=1
set +e
run_case "$out/negative_fw" "$out/negative_restore" 0 0 2
status=$?
set -e
test "$status" -eq 0 || { test "$status" -eq 1 && grep -q 'Nested timeout' "$out/negative_restore/simulation.log"; }
python3 -B - "$here/bridge.sv" "$out/stale_bridge.sv" <<'PY'
import sys
from pathlib import Path
source=Path(sys.argv[1]).read_text()
old='if(!cancelled && !reset_request) begin'
assert source.count(old)==1
Path(sys.argv[2]).write_text(source.replace(old,"if(1'b1) begin"))
PY
iverilog -g2012 -s nested_tb -o "$out/stale.sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/stale_bridge.sv" "$here/cancel_target.sv" "$here/nested_tb.sv"
sim_override="$out/stale.sim"
set +e
run_case "$out/fw_o0_i3_n1" "$out/negative_stale" 2 1 13
status=$?
set -e
test "$status" -eq 0 || { test "$status" -eq 1 && grep -q 'Nested timeout' "$out/negative_stale/simulation.log"; }
python3 -B "$here/check_nested.py" "$out"
sha256sum "$here/nested.S" "$here/nested_recovery.S" "$here/nested_tb.sv" "$here/check_nested.py" "$here/run_nested.sh" "$here/bridge.sv" "$here/cancel_target.sv" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" > "$out/inputs.sha256"
sha256sum "$out"/fw_*/firmware.hex "$out/recovery/firmware.hex" "$out/negative_fw/firmware.hex" >> "$out/inputs.sha256"
