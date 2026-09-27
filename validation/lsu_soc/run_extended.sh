#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${REAL_LSU_BUILD:?Set to normal CPU-WR-03 generated RTL directory}"
: "${CPU_INPUT_ROOT:?Set to legal UART input directory}"
test "$(cat "$REAL_LSU_BUILD/mode.txt")" = normal
test "$(sha256sum "$CPU_INPUT_ROOT/rtl/mini_uart.v" | cut -d ' ' -f1)" = 12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e
out=$(mktemp -d "${TMPDIR:-/tmp}/lsu-extended.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
build() {
  local dir="$1" program="$2";shift 2
  mkdir -p "$dir"
  cp "$REAL_LSU_BUILD/rtl/"*.bin "$dir/"
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax \
    -nostdlib -nostartfiles -T "$here/../cpu/sw/link.ld" "$@" "$here/$program.S" -o "$dir/program.elf"
  riscv64-unknown-elf-objcopy -O binary "$dir/program.elf" "$dir/program.bin"
  python3 -B "$here/../cpu/scripts/bin_to_hex.py" "$dir/program.bin" "$dir/firmware.hex"
  riscv64-unknown-elf-objdump -d "$dir/program.elf" > "$dir/program.dis"
}
compile() {
  local dir="$1" tb="$2";shift 2
  iverilog -g2012 -s "$tb" "$@" -o "$dir/sim" "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" \
    "$CPU_INPUT_ROOT/rtl/mini_uart.v" "$here/mini_soc.v" "$here/$tb.sv"
}
reject() {
  local dir="$1" reason="$2" status=0
  (cd "$dir";vvp sim) > "$dir/negative.log" 2>&1 || status=$?
  if [ "$status" = 0 ] || ! grep -q "$reason" "$dir/negative.log"; then
    cat "$dir/negative.log";echo 'FAIL: negative control';exit 1
  fi
  echo "PASS: negative rejected: $reason"
}
for delay in 7 31;do
  for kind in 0 1 2 3;do
    for phase in 0 1 2;do
      dir="$out/reset-$delay-$kind-$phase"
      build "$dir" reset
      compile "$dir" reset_tb -Preset_tb.DELAY="$delay" -Preset_tb.KIND="$kind" -Preset_tb.PHASE="$phase"
      (cd "$dir";vvp sim)
    done
  done
done
for delay in 0 7 31;do
  dir="$out/mixed-$delay"
  python3 -B "$here/mixed_model.py" "$dir"
  build "$dir" mixed -Wa,-I,"$dir"
  compile "$dir" mixed_tb -Pmixed_tb.DELAY="$delay"
  (cd "$dir";vvp sim)
done
dir="$out/negative-stale"
build "$dir" reset
compile "$dir" reset_tb -DSTALE_RESPONSE_MUTATION
reject "$dir" 'Stale response after reset'
dir="$out/negative-mixed"
python3 -B "$here/mixed_model.py" "$dir"
build "$dir" mixed -Wa,-I,"$dir" -DMIX_MUTATION
compile "$dir" mixed_tb
reject "$dir" 'Mixed reference mismatch'
sha256sum "$here/"*.sv "$here/"*.S "$here/mini_soc.v" "$here/mixed_model.py" \
  "$REAL_LSU_BUILD/rtl/VexWriteResponse.v" "$CPU_INPUT_ROOT/rtl/mini_uart.v" > "$out/inputs.sha256"
echo 'PASS: 24 reset windows, 6 mixed boots, 2 negative controls'
echo 'LIMITS: global local reset, deterministic directed coverage, not full ISA or board certification'
