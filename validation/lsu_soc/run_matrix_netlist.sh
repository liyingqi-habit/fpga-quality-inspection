#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${PDS_STAGE:?Set to the new matrix PDS stage}"
: "${PDS_SIM_LIB:?Set to the installed vendor simulation library}"
: "${MATRIX_BUILD:?Set to build_matrix.sh output}"
: "${NETLIST_SHA256:?Record and supply the corresponding synthesis netlist SHA256}"
net="$PDS_STAGE/prj_tasks/syn_1/synthesize/mini_soc_first_board_syn.vm"
test "$(sha256sum "$net" | cut -d ' ' -f1)" = "$NETLIST_SHA256"
cmp "$PDS_STAGE/firmware.hex" "$MATRIX_BUILD/firmware.hex"
test "$(sha256sum "$PDS_STAGE/VexWriteResponse.v" | cut -d ' ' -f1)" = 63bb55e1bb43cc472699a09f1e2dbd674a68cab562da0df9d988b16f9b321140
cmp "$PDS_STAGE/mini_soc.v" "$here/mini_soc.v"
test -f "$PDS_SIM_LIB/GTP_GRS.v"
out=$(mktemp -d "${TMPDIR:-/tmp}/regfile-netlist.XXXXXXXX")
echo "OUTPUT=$out"
exec > >(tee "$out/run.log") 2>&1
for mode in rtl gate poison negative;do
  dir="$out/$mode";mkdir "$dir"
  cp "$MATRIX_BUILD/"matrix*.hex "$MATRIX_BUILD/matrix_config.vh" "$MATRIX_BUILD/cases.json" "$dir/"
  cp "$PDS_STAGE/firmware.hex" "$PDS_STAGE/"*.bin "$dir/"
  if [ "$mode" != rtl ];then
    sources=(-DGATE -y "$PDS_SIM_LIB" -Y .v "$net")
    if [ "$mode" = poison ];then sources+=(-DPOISON_RAW);fi
    if [ "$mode" = negative ];then sources+=(-DEXPECTATION_MUTATION);fi
  else
    sources=("$PDS_STAGE/VexWriteResponse.v" "$PDS_STAGE/mini_soc.v" "$PDS_STAGE/mini_uart.v" "$PDS_STAGE/mini_soc_first_board.v")
  fi
  iverilog -g2012 -I "$dir" -s regfile_matrix_tb -M "$dir/dependencies.txt" -o "$dir/sim" "${sources[@]}" "$here/regfile_matrix_tb.sv" > "$dir/compile.log" 2>&1
  if [ "$mode" = negative ];then
    status=0
    (cd "$dir";vvp sim) > "$dir/simulation.log" 2>&1 || status=$?
    if [ "$status" = 0 ] || ! grep -q 'Matrix reference mismatch case=0' "$dir/simulation.log";then
      cat "$dir/simulation.log";echo 'FAIL: negative oracle';exit 1
    fi
    echo 'PASS: netlist negative reference rejected at case 0'
    continue
  fi
  (cd "$dir";vvp sim) | tee "$dir/simulation.log"
  grep -q '^PASS: regfile matrix functional regression' "$dir/simulation.log"
done
cmp "$out/rtl/commands.csv" "$out/gate/commands.csv"
cmp "$out/rtl/commands.csv" "$out/poison/commands.csv"
while IFS= read -r file;do test ! -f "$file" || sha256sum "$file";done < "$out/gate/dependencies.txt" > "$out/dependencies.sha256"
sha256sum "$PDS_STAGE/firmware.hex" "$net" "$MATRIX_BUILD/cases.json" > "$out/inputs.sha256"
echo 'PASS: RTL/gate/poison matrix command streams match across two boots'
echo 'LIMITS: no SDF; observed primitive collisions are not an exhaustive valid-consumer proof'
