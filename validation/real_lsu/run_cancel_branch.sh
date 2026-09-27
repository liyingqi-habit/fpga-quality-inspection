#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REAL_LSU_BUILD:?normal CPU build required}"
test "$(sha256sum "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" | cut -d ' ' -f1)" = 63bb55e1bb43cc472699a09f1e2dbd674a68cab562da0df9d988b16f9b321140
out=$(mktemp -d "${TMPDIR:-/tmp}/cancel-branch.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
iverilog -g2012 -s cancel_branch_tb -o "$out/sim" "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" "$here/write_bridge.sv" "$here/../write_response/target.sv" "$here/cancel_branch_tb.sv"
for branch in 0 1 2;do
  for id in $(seq 0 11);do
    dir="$out/branch$branch/case$id";mkdir -p "$dir"
    cp "$REAL_LSU_BUILD/rtl/"*.bin "$dir/"
    riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,-Ttext=0x80000000 -Wl,--no-relax -DTEST_ID="$id" -DTEST_OFFSET="$((id*4))" -DBRANCH_KIND="$branch" "$here/cancel_branch.S" -o "$dir/program.elf"
    riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
    python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/program.hex"
    (cd "$dir";vvp "$out/sim" +CASE="$id")
  done
done
python3 -B "$here/check_cancel_branch.py" "$out"
sha256sum "$here/cancel_branch.S" "$here/cancel_branch_tb.sv" "$here/check_real.py" "$here/check_cancel_branch.py" > "$out/inputs.sha256"
echo 'PASS: 36 branch/error/cancel cases (RTL) and independent trace audit'
