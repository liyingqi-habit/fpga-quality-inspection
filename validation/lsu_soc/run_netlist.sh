#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${PDS_STAGE:?Set to preserved CPU-WR-05 PDS stage}"
: "${PDS_SIM_LIB:?Set to installed vendor simulation library}"
net="$PDS_STAGE/prj_tasks/syn_1/synthesize/mini_soc_first_board_syn.vm"
test "$(sha256sum "$net" | cut -d ' ' -f1)" = dcdaa8b0d105de15585fc5359fc16037b5f8c99a068b073f7ee9ea6ddefe5f99
test "$(sha256sum "$PDS_STAGE/firmware.hex" | cut -d ' ' -f1)" = cb7b3241b068f381292c90a257c89626226ef8ced8f363157b2e534a07a71479
test -f "$PDS_SIM_LIB/GTP_GRS.v"
out=$(mktemp -d "${TMPDIR:-/tmp}/lsu-netlist.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
for mode in rtl gate poison negative;do
  dir="$out/$mode";mkdir "$dir"
  python3 -B "$here/mixed_model.py" "$dir"
  cp "$PDS_STAGE/firmware.hex" "$PDS_STAGE/"*.bin "$dir/"
  if [ "$mode" != rtl ];then
    sources=(-DGATE -y "$PDS_SIM_LIB" -Y .v "$net")
    if [ "$mode" = poison ];then sources+=(-DPOISON_RAW);fi
    if [ "$mode" = negative ];then sources+=(-DEXPECTATION_MUTATION);fi
  else
    sources=("$PDS_STAGE/VexWriteResponse.v" "$PDS_STAGE/mini_soc.v" "$PDS_STAGE/mini_uart.v" "$PDS_STAGE/mini_soc_first_board.v")
  fi
  iverilog -g2012 -s netlist_tb -M "$dir/dependencies.txt" -o "$dir/sim" "${sources[@]}" "$here/netlist_tb.sv" > "$dir/compile.log" 2>&1
  if [ "$mode" = negative ];then
    status=0
    (cd "$dir";vvp sim) > "$dir/simulation.log" 2>&1 || status=$?
    if [ "$status" = 0 ] || ! grep -q 'Reference mismatch word=4' "$dir/simulation.log";then
      cat "$dir/simulation.log";echo 'FAIL: negative oracle';exit 1
    fi
    echo 'PASS: netlist negative reference rejected at word 4'
    continue
  fi
  (cd "$dir";vvp sim) | tee "$dir/simulation.log"
  grep -q '^PASS: mixed netlist-compatible' "$dir/simulation.log"
done
cmp "$out/rtl/commands.csv" "$out/gate/commands.csv"
cmp "$out/rtl/commands.csv" "$out/poison/commands.csv"
while IFS= read -r file;do test ! -f "$file" || sha256sum "$file";done < "$out/gate/dependencies.txt" > "$out/dependencies.sha256"
echo 'PASS: RTL and synthesis netlist command streams match across two boots'
echo 'PASS: collision raw-data X injection does not change architectural command results'
echo 'LIMITS: baked mixed firmware, sampled collisions only, no SDF or board'
