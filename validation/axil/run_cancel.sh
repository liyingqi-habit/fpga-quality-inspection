#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${AXIL_CPU_BUILD:?normal generated AXIL CPU build required}"
test "$(cat "$AXIL_CPU_BUILD/mode.txt")" = normal
test "$(sha256sum "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" | cut -d ' ' -f1)" = 6bc91de7f76e88d7edf056e8d30790c645876bf13e7177e7827c949ff12d141e
out=$(mktemp -d "${TMPDIR:-/tmp}/axil-cancel.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s cancel_tb -o "$out/sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$here/bridge.sv" "$here/cancel_target.sv" "$here/cancel_tb.sv"
for w in 0 1;do
  fw="$out/fw$w";mkdir "$fw"
  for boot in 0 1;do
    riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--no-relax -DBOOT="$boot" -DWRITE="$w" "$here/cancel.S" -o "$fw/boot$boot.elf"
    riscv64-unknown-elf-objcopy -O binary "$fw/boot$boot.elf" "$fw/boot$boot.bin"
    riscv64-unknown-elf-objdump -d "$fw/boot$boot.elf" > "$fw/boot$boot.dis"
    python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$fw/boot$boot.bin" "$fw/boot$boot.hex"
  done
  for p in 0 1 2 3 4 5 6 7;do
    if [ "$w" = 0 ] && { [ "$p" = 2 ] || [ "$p" = 3 ]; };then continue;fi
    for c in 0 2 3;do
      for d in 3 17;do
        dir="$out/w${w}_p${p}_c${c}_d${d}";mkdir "$dir"
        cp "$fw/"*.hex "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
        (cd "$dir";vvp "$out/sim" +WRITE="$w" +PHASE="$p" +CODE="$c" +DELAY="$d") > "$dir/simulation.log" 2>&1
      done
    done
  done
done
python3 -B "$here/negative_bridge.py" "$out"
for mode in lost_error stale_response early_release;do
  iverilog -g2012 -s cancel_tb -o "$out/$mode.sim" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" "$out/$mode.sv" "$here/cancel_target.sv" "$here/cancel_tb.sv"
  for w in 0 1;do
    dir="$out/negative_${mode}_w$w";mkdir "$dir"
    cp "$out/fw$w/"*.hex "$AXIL_CPU_BUILD/rtl/"*.bin "$dir/"
    if [ "$mode" = lost_error ];then p=0;c=2;else p=4;c=0;fi
    (cd "$dir";vvp "$out/$mode.sim" +WRITE="$w" +PHASE="$p" +CODE="$c" +DELAY=17) > "$dir/simulation.log" 2>&1
  done
done
python3 -B "$here/check_cancel.py" "$out"
sha256sum "$here/cancel.S" "$here/cancel_tb.sv" "$here/cancel_target.sv" "$here/bridge.sv" "$here/check_cancel.py" "$AXIL_CPU_BUILD/rtl/VexAxilCpu.v" > "$out/inputs.sha256"
